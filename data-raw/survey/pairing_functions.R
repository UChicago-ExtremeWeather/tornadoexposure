# Functions of the survey layer, shared by data-raw/survey/build_survey.R and the QA scripts in data-raw/qa/.
# Source from the package root after loading sf and dplyr. The pairing:
#   candidates   every SPC tornado since 2007 (line and point tracks) and every survey line (any length) dated within `window` days
#                (1 day in the layer); survey lines that are exact copies of each other (same date, length and coordinates) are
#                merged first
#   distance     21 equally spaced points are taken along each path, from start to end. The distance between a tornado and a survey line
#                is the mean of the 21 distances between corresponding points, with the survey line read in the direction that gives
#                the smaller mean (kilometers, computed in EPSG:5070). For an SPC point track it is the distance from the point to the
#                survey line.
#   pairing      a tornado and a survey line are paired when each is the other's closest candidate
# The swath filter (rated EF0 to EF5 polygons with at least 90% of their area within the SPC path width plus 500 m of the centerline;
# usable when the swath lies within 200 m of at least 50% of the centerline) is in swath_of().
dat_url <- "https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer/"
n_samples <- 21

# ---- fetch from the live service ---------------------------------------------------------------------------------------------
dat_fetch_layer <- function(layer, where, fields, extra = "") {
  B <- paste0(dat_url, layer, "/query")
  cnt <- jsonlite::fromJSON(paste0(B, "?where=", URLencode(where, reserved = TRUE), "&returnCountOnly=true&f=json"))$count
  pages <- list(); off <- 0
  while (off < cnt) {
    u <- paste0(B, "?where=", URLencode(where, reserved = TRUE), "&outFields=", fields, "&outSR=4326&returnGeometry=true", extra,
                "&orderByFields=objectid&resultOffset=", off, "&resultRecordCount=1000&f=geojson")
    p <- tryCatch(sf::read_sf(u, quiet = TRUE), error = function(e) NULL)
    if (is.null(p) || !nrow(p)) stop("page failed at ", off, " of ", cnt, " (layer ", layer, ")")
    pages[[length(pages) + 1]] <- p; off <- off + 1000
  }
  x <- do.call(rbind, pages); list(data = x[!sf::st_is_empty(x), ], count = cnt)
}
# Survey lines of 2007 to `last_year` (any length) and damage polygons (generalized to 0.0002 degrees, about 20 m). The fetch is kept
# in data-raw/qa/out/ together with its date; SURVEY_USE_SAVED=1 reuses it instead of querying the service.
dat_fetch_all <- function(last_year = 2025, saved = nzchar(Sys.getenv("SURVEY_USE_SAVED"))) {
  fl <- qa_out("dat_lines_live.rds"); fp <- qa_out("dat_polys_live.rds"); fd <- qa_out("dat_fetch_date.txt")
  if (saved && file.exists(fl) && file.exists(fp) && file.exists(fd)) return(list(lines = readRDS(fl), polys = readRDS(fp), date = as.Date(readLines(fd))))
  since <- "stormdate >= timestamp '2007-01-01 00:00:00'"
  L <- dat_fetch_layer(1, paste0(since, " AND stormdate < timestamp '", last_year + 1, "-01-01 00:00:00'"), "objectid,event_id,wfo,stormdate,length,width,efscale,startlat,startlon,endlat,endlon")
  P <- dat_fetch_layer(2, paste0(since, " AND stormdate < timestamp '", last_year + 1, "-01-02 00:00:00'"), "efscale,stormdate,event_id,length,width", "&maxAllowableOffset=0.0002")
  saveRDS(L$data, fl); saveRDS(P$data, fp); writeLines(format(Sys.Date()), fd)
  message("fetched ", nrow(L$data), " survey lines and ", nrow(P$data), " damage polygons")
  list(lines = L$data, polys = P$data, date = Sys.Date())
}
dat_date <- function(x) as.Date(as.POSIXct(x / 1000, origin = "1970-01-01", tz = "UTC"))
line_ends <- function(g) { m <- unclass(g); if (!is.matrix(m)) m <- do.call(rbind, lapply(g, unclass)); c(m[1, 1:2], m[nrow(m), 1:2]) }

# Merge survey lines that are exact copies of each other. Returns the table of distinct lines with the object ids of all copies.
merge_copies <- function(D) {
  D$date <- dat_date(D$stormdate); dcc <- do.call(rbind, lapply(sf::st_geometry(D), line_ends))
  D$key <- paste(D$stormdate, D$length, round(dcc[, 1], 6), round(dcc[, 2], 6), round(dcc[, 3], 6), round(dcc[, 4], 6))
  first <- !duplicated(D$key); Du <- D[first, ]
  Du$n_copies <- as.integer(table(D$key)[Du$key]); Du$all_ids <- vapply(Du$key, function(k) paste(D$objectid[D$key == k], collapse = ","), "")
  Du$s_lon <- dcc[first, 1]; Du$s_lat <- dcc[first, 2]; Du$e_lon <- dcc[first, 3]; Du$e_lat <- dcc[first, 4]
  Du
}

# ---- paths sampled at equally spaced points -------------------------------------------------------------------------------------
spc_paths <- function(Tt) {
  g <- sf::st_geometry(Tt); is_line <- Tt$track_type == "line"
  tl <- do.call(rbind, lapply(seq_along(g), function(k) { m <- sf::st_coordinates(g[k])[, 1:2, drop = FALSE]; if (nrow(m) == 1) c(m[1, ], m[1, ]) else c(m[1, ], m[nrow(m), ]) }))
  pt5 <- function(lon, lat) sf::st_coordinates(sf::st_transform(sf::st_sfc(lapply(seq_along(lon), function(k) sf::st_point(c(lon[k], lat[k]))), crs = 4326), 5070))
  s5 <- pt5(tl[, 1], tl[, 2]); e5 <- pt5(tl[, 3], tl[, 4]); tt <- seq(0, 1, length.out = n_samples)
  list(is_line = is_line, tl = tl, s5 = s5, e5 = e5, Tx = outer(s5[, 1], 1 - tt) + outer(e5[, 1], tt), Ty = outer(s5[, 2], 1 - tt) + outer(e5[, 2], tt),
       chord_km = sqrt((e5[, 1] - s5[, 1])^2 + (e5[, 2] - s5[, 2])^2) / 1000)
}
survey_paths <- function(Du) {
  Lg <- sf::st_make_valid(sf::st_geometry(Du)); L5 <- sf::st_transform(Lg, 5070)
  L5 <- sf::st_sfc(lapply(seq_along(L5), function(i) { g <- L5[[i]]
    if (inherits(g, "MULTILINESTRING")) { g <- sf::st_line_merge(g); if (inherits(g, "MULTILINESTRING")) { parts <- lapply(unclass(g), sf::st_linestring); g <- parts[[which.max(vapply(parts, function(p) as.numeric(sf::st_length(p)), 0))]] } }
    g }), crs = 5070)
  samp <- sf::st_coordinates(sf::st_cast(sf::st_line_sample(L5, sample = seq(0, 1, length.out = n_samples)), "POINT"))[, 1:2]
  list(Lg = Lg, L5 = L5, Sx = matrix(samp[, 1], ncol = n_samples, byrow = TRUE), Sy = matrix(samp[, 2], ncol = n_samples, byrow = TRUE))
}

# ---- candidate pairs and distances -----------------------------------------------------------------------------------------------
candidate_distances <- function(Du, Tt, sp, sv, window = 1) {
  pr <- dplyr::bind_rows(lapply(-window:window, function(o) merge(transform(data.frame(i = seq_len(nrow(Du)), date = Du$date), date = date + o), data.frame(k = seq_len(nrow(Tt)), date = Tt$date), by = "date")[, c("i", "k")]))
  ns <- n_samples; d <- numeric(nrow(pr)); rev <- logical(nrow(pr))
  for (ch in split(seq_len(nrow(pr)), ceiling(seq_len(nrow(pr)) / 50000))) { i <- pr$i[ch]; k <- pr$k[ch]
    dfw <- rowMeans(sqrt((sv$Sx[i, , drop = FALSE] - sp$Tx[k, , drop = FALSE])^2 + (sv$Sy[i, , drop = FALSE] - sp$Ty[k, , drop = FALSE])^2))
    drv <- rowMeans(sqrt((sv$Sx[i, ns:1, drop = FALSE] - sp$Tx[k, , drop = FALSE])^2 + (sv$Sy[i, ns:1, drop = FALSE] - sp$Ty[k, , drop = FALSE])^2))
    d[ch] <- pmin(dfw, drv) / 1000; rev[ch] <- drv < dfw }
  pt <- which(!sp$is_line[pr$k])
  if (length(pt)) { gp <- sf::st_sfc(lapply(pr$k[pt], function(k) sf::st_point(sp$s5[k, ])), crs = 5070); d[pt] <- as.numeric(sf::st_distance(gp, sv$L5[pr$i[pt]], by_element = TRUE)) / 1000; rev[pt] <- FALSE }
  pr$dist_km <- d; pr$rev <- rev
  pr %>% dplyr::group_by(i) %>% dplyr::mutate(rank_s = rank(dist_km, ties.method = "first"), n_cand_s = dplyr::n(), second_s = ifelse(dplyr::n() > 1, sort(dist_km)[2], NA_real_)) %>% dplyr::ungroup() %>%
    dplyr::group_by(k) %>% dplyr::mutate(rank_t = rank(dist_km, ties.method = "first"), n_cand_t = dplyr::n(), second_t = ifelse(dplyr::n() > 1, sort(dist_km)[2], NA_real_)) %>% dplyr::ungroup()
}
mutual_closest <- function(pr) pr[pr$rank_s == 1 & pr$rank_t == 1, ]
bearing <- function(x1, y1, x2, y2) (atan2(x2 - x1, y2 - y1) * 180 / pi + 360) %% 360   # degrees clockwise from north (planar coordinates)

# ---- swath filter -----------------------------------------------------------------------------------------------------------------------
swath_setup <- function(Du, sv, P) {
  Pg <- sf::st_make_valid(sf::st_geometry(P)); P5 <- sf::st_transform(Pg, 5070)
  list(P = P, Pd = dat_date(P$stormdate), P5 = P5, P_area = as.numeric(sf::st_area(P5)), hit = sf::st_intersects(sv$Lg, Pg), Du = Du, sv = sv)
}
# The swath of survey line i for tornado k: returns the number of polygons crossing the line on the same date (within one day), the number
# kept by the filter, the share of the line within 200 m of the kept polygons, the swath area (km2) and the swath geometry (EPSG:5070).
swath_of <- function(sw, i, k, wid_yd, margin = 500, frac = 0.9, cover_dist = 200, ok_ef = paste0("EF", 0:5), window = 1) {
  q <- sw$hit[[i]]; q <- q[abs(as.numeric(sw$Pd[q] - sw$Du$date[i])) <= window]; n_raw <- length(q)
  q <- q[sw$P$efscale[q] %in% ok_ef]
  if (length(q)) { half_km <- wid_yd[k] * 0.9144 / 2 / 1000; buf <- sf::st_buffer(sw$sv$L5[i], half_km * 2 * 1000 + margin)
    inb <- vapply(q, function(z) tryCatch(as.numeric(sf::st_area(sf::st_intersection(sw$P5[z], buf))) / sw$P_area[z], error = function(e) NA_real_), numeric(1)); q <- q[!is.na(inb) & inb >= frac] }
  if (!length(q)) return(list(n_raw = n_raw, n_used = 0L, cover = NA_real_, area_km2 = NA_real_, geom = NULL))
  u <- sf::st_union(sf::st_make_valid(sw$P5[q])); inside <- tryCatch(as.numeric(sf::st_length(sf::st_intersection(sw$sv$L5[i], sf::st_buffer(u, cover_dist)))), error = function(e) NA_real_)
  list(n_raw = n_raw, n_used = length(q), cover = sum(inside) / as.numeric(sf::st_length(sw$sv$L5[i])), area_km2 = as.numeric(sf::st_area(u)) / 1e6, geom = u)
}
is_usable <- function(s, covmin = 0.5) !is.na(s$cover) && s$cover >= covmin

# ---- everything the QA scripts need, from the saved fetch of the last build ----------------------------------------------------------
# Needs tornado_tracks (data/) in the global environment and the fetch saved by build_survey.R (data-raw/qa/out/).
survey_context <- function(last_year = 2025) {
  F <- dat_fetch_all(last_year, saved = TRUE); Du <- merge_copies(F$lines); P <- F$polys
  yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4)); Tt <- tornado_tracks[yr >= 2007, ]; Tt$date <- as.Date(Tt$date)
  sp <- spc_paths(Tt); sv <- survey_paths(Du)
  list(F = F, Du = Du, P = P, Tt = Tt, sp = sp, sv = sv, sw = swath_setup(Du, sv, P))
}
