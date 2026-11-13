# Functions that link NWS damage-survey lines (DAT layer 1) to SPC tornadoes. Source from the package root after loading sf and dplyr.
#
# Candidates: every SPC tornado (line and point tracks) and every DAT line with a date and a geometry, dated within `window` days (1 day).
# Distances (kilometers, computed in EPSG:5070):
#   index-aligned distance  21 equally spaced points are taken along each path, from start to end; the distance is the mean of the 21 distances
#                           between corresponding points, with the DAT line read in the direction that gives the smaller mean. For an SPC point track
#                           (no usable end point) it is the distance from the start point to the DAT line.
#   one-sided distance      the mean distance of the DAT line's own 21 points to the SPC straight line (for an SPC point track, as above).
# Rule:
#   mutual_closest      a tornado and a DAT line are linked when each is the other's closest candidate by the index-aligned distance
#                       (a tie is broken by the lower objectid)
#   attached_to_paired  a DAT line that is in no mutual-closest pair is attached to its one-sided nearest tornado when that tornado already has a
#                       mutual-closest line (so a tornado can have several DAT lines)
# No distance limit, no test on length or direction and no minimum length is used; every number is a column of the link table.
n_samples <- 21

dat_date <- function(ms) as.Date(as.POSIXct(ms / 1000, origin = "1970-01-01", tz = "UTC"))
bearing <- function(x1, y1, x2, y2) (atan2(x2 - x1, y2 - y1) * 180 / pi + 360) %% 360   # degrees clockwise from north (planar coordinates)

# ---- paths sampled at equally spaced points -------------------------------------------------------------------------------------
spc_paths <- function(Tt) {
  g <- sf::st_geometry(Tt); is_line <- Tt$track_type == "line"
  tl <- do.call(rbind, lapply(seq_along(g), function(k) { m <- sf::st_coordinates(g[k])[, 1:2, drop = FALSE]; if (nrow(m) == 1) c(m[1, ], m[1, ]) else c(m[1, ], m[nrow(m), ]) }))
  pt5 <- function(lon, lat) sf::st_coordinates(sf::st_transform(sf::st_sfc(lapply(seq_along(lon), function(k) sf::st_point(c(lon[k], lat[k]))), crs = 4326), 5070))
  s5 <- pt5(tl[, 1], tl[, 2]); e5 <- pt5(tl[, 3], tl[, 4]); tt <- seq(0, 1, length.out = n_samples)
  list(is_line = is_line, tl = tl, s5 = s5, e5 = e5, Tx = outer(s5[, 1], 1 - tt) + outer(e5[, 1], tt), Ty = outer(s5[, 2], 1 - tt) + outer(e5[, 2], tt))
}

# DAT lines (sf, LINESTRING, EPSG:4326, none empty): the geometry in EPSG:5070 and the 21 sample points. Stops on a multipart line.
dat_line_paths <- function(L) {
  if (!all(sf::st_geometry_type(L) == "LINESTRING")) stop("A DAT line is not a single LINESTRING; stop and report (", sum(sf::st_geometry_type(L) != "LINESTRING"), " lines).", call. = FALSE)
  L5 <- sf::st_transform(sf::st_geometry(L), 5070)
  samp <- sf::st_coordinates(sf::st_cast(sf::st_line_sample(L5, sample = seq(0, 1, length.out = n_samples)), "POINT"))[, 1:2]
  list(L5 = L5, Sx = matrix(samp[, 1], ncol = n_samples, byrow = TRUE), Sy = matrix(samp[, 2], ncol = n_samples, byrow = TRUE))
}

pdist <- function(px, py, ax, ay, bx, by) { dx <- bx - ax; dy <- by - ay; L2 <- dx^2 + dy^2; t <- pmax(0, pmin(1, ((px - ax) * dx + (py - ay) * dy) / ifelse(L2 > 0, L2, 1))); sqrt((px - (ax + t * dx))^2 + (py - (ay + t * dy))^2) }   # px, py may be matrices (one row per pair); a zero-length segment gives t = 0

# ---- candidate pairs and distances -----------------------------------------------------------------------------------------------
# Ld: data frame of the DAT lines (column date), Tt: SPC tornadoes (column date), sp / sv: spc_paths() and dat_line_paths()
candidate_distances <- function(Ld, Tt, sp, sv, window = 1) {
  pr <- dplyr::bind_rows(lapply(-window:window, function(o) merge(transform(data.frame(i = seq_len(nrow(Ld)), date = Ld$date), date = date + o), data.frame(k = seq_len(nrow(Tt)), date = Tt$date), by = "date")[, c("i", "k")]))
  pr <- pr[order(pr$i, pr$k), ]; rownames(pr) <- NULL
  ns <- n_samples; d <- d1 <- numeric(nrow(pr)); rev <- logical(nrow(pr))
  for (ch in split(seq_len(nrow(pr)), ceiling(seq_len(nrow(pr)) / 50000))) { i <- pr$i[ch]; k <- pr$k[ch]
    dfw <- rowMeans(sqrt((sv$Sx[i, , drop = FALSE] - sp$Tx[k, , drop = FALSE])^2 + (sv$Sy[i, , drop = FALSE] - sp$Ty[k, , drop = FALSE])^2))
    drv <- rowMeans(sqrt((sv$Sx[i, ns:1, drop = FALSE] - sp$Tx[k, , drop = FALSE])^2 + (sv$Sy[i, ns:1, drop = FALSE] - sp$Ty[k, , drop = FALSE])^2))
    d[ch] <- pmin(dfw, drv) / 1000; rev[ch] <- drv < dfw
    d1[ch] <- rowMeans(pdist(sv$Sx[i, , drop = FALSE], sv$Sy[i, , drop = FALSE], sp$s5[k, 1], sp$s5[k, 2], sp$e5[k, 1], sp$e5[k, 2])) / 1000 }
  pt <- which(!sp$is_line[pr$k])
  if (length(pt)) { gp <- sf::st_sfc(lapply(pr$k[pt], function(k) sf::st_point(sp$s5[k, ])), crs = 5070); dp <- as.numeric(sf::st_distance(gp, sv$L5[pr$i[pt]], by_element = TRUE)) / 1000; d[pt] <- dp; d1[pt] <- dp; rev[pt] <- FALSE }
  pr$dist_km <- d; pr$one_sided_km <- d1; pr$rev <- rev
  pr %>% dplyr::group_by(i) %>% dplyr::mutate(rank_s = rank(dist_km, ties.method = "first"), n_cand_s = dplyr::n(), second_s = ifelse(dplyr::n() > 1, sort(dist_km)[2], NA_real_)) %>% dplyr::ungroup() %>%
    dplyr::group_by(k) %>% dplyr::mutate(rank_t = rank(dist_km, ties.method = "first"), n_cand_t = dplyr::n(), second_t = ifelse(dplyr::n() > 1, sort(dist_km)[2], NA_real_)) %>% dplyr::ungroup()
}

# the links: mutual closest, then the unpaired lines attached to an already paired tornado through the one-sided distance
link_rule <- function(pr) {
  M <- pr[pr$rank_s == 1 & pr$rank_t == 1, ]; M$rule <- "mutual_closest"
  un <- setdiff(unique(pr$i), M$i)
  best1 <- pr[pr$i %in% un, ] %>% dplyr::group_by(i) %>% dplyr::slice_min(one_sided_km, n = 1, with_ties = FALSE) %>% dplyr::ungroup()
  A <- best1[best1$k %in% M$k, ]; A$rule <- "attached_to_paired"
  out <- rbind(M, A); out$relationship <- ifelse(out$k %in% out$k[duplicated(out$k)], "one_to_many", "one_to_one"); out
}
