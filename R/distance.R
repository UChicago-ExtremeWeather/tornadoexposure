# Distance exposure: a ZCTA is exposed when the population-weighted centroid of
# the ZCTA lies within `centroid_dist_km` of the tornado path polygon. Nothing is
# precomputed: distances are computed on demand from the stored tracks and the
# small zcta_centroids table.

.centroids <- function() tornadoexposure::zcta_centroids

.vintage_of <- function(year) {
  ifelse(year < 2010, 2000L, ifelse(year < 2020, 2010L, 2020L))
}

# Distances are measured in a projection that suits the region: EPSG:5070 (the
# equal-area CRS used for areas) for the 48 states, and a local CRS for Alaska,
# Hawaii and Puerto Rico, which lie far from its standard parallels. Against
# spherical geodesic distances the largest relative difference was 1.5% in the 48
# states and at most 1.3% in the other regions (data-raw/known_issues.md, section
# Exposure definitions). Areas stay in EPSG:5070 everywhere.
.distance_crs <- list(conus = 5070, ak = 3338, hi = "ESRI:102007", pr = 32161)

# Region of each track from its centroid (lon, lat)
.distance_region <- function(tracks) {
  ct <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf::st_geometry(tracks))))
  ifelse(ct[, 2] >= 50.5, "ak",
         ifelse(ct[, 2] < 23 & ct[, 1] < -150, "hi",
                ifelse(ct[, 2] < 20 & ct[, 1] > -70, "pr", "conus")))
}

# Centroids as sf points in `crs`
.centroid_points <- function(cen, crs) {
  sf::st_geometry(sf::st_transform(
    sf::st_as_sf(cen, coords = c("lon", "lat"), crs = 4269), crs))
}

# Pairs (path polygon, centroid) with the centroid within `radius_km` of the
# polygon. `region` and `vint` give the region and ZCTA vintage of each path,
# `cen` is the (already filtered) centroid table, and `make_poly(i, crs)` returns
# the path polygons of paths `i` in `crs`. Returns a data frame with `i` (index of
# the path), `j` (centroid row) and `dist_km`. The spatial index is used through
# a slightly oversized buffer; exact distances are then computed for the
# candidate pairs only (sf::st_is_within_distance has no index and is far too
# slow for a nationwide call).
.distance_pairs <- function(region, vint, cen, radius_km, make_poly) {
  out <- list()
  for (rg in unique(region)) for (vv in sort(unique(vint))) {
    i <- which(region == rg & vint == vv)
    jrows <- which(cen$vintage == vv)
    if (length(i) == 0L || length(jrows) == 0L) next
    crs <- .distance_crs[[rg]]
    poly <- make_poly(i, crs)
    pts <- .centroid_points(cen[jrows, , drop = FALSE], crs)
    cand <- sf::st_intersects(sf::st_buffer(poly, radius_km * 1000 * 1.05),
                              pts, sparse = TRUE)
    n <- lengths(cand)
    ii <- rep(seq_along(i), n)
    jj <- unlist(cand)
    if (length(jj) == 0L) next
    d <- as.numeric(sf::st_distance(poly[ii], pts[jj], by_element = TRUE)) / 1000
    keep <- d <= radius_km
    out[[length(out) + 1L]] <- data.frame(i = i[ii[keep]], j = jrows[jj[keep]],
                                          dist_km = d[keep])
  }
  if (length(out) == 0L) {
    return(data.frame(i = integer(0), j = integer(0), dist_km = numeric(0)))
  }
  do.call(rbind, out)
}

# counts per vintage, always with the three names
.vint_counts <- function(x) {
  n <- as.integer(table(factor(x, levels = c(2000, 2010, 2020))))
  stats::setNames(n, c("2000", "2010", "2020"))
}

# Rough time for a distance call. The measured times of the nationwide 1996-2025
# query (every tornado, about 33,000 ZCTAs per vintage, one core) at radii of 1,
# 5, 10, 25 and 50 km are in the table of data-raw/known_issues.md (written by
# data-raw/qa/23_distance_tables.R); the estimate interpolates between them on
# log scales (and extends the last segment beyond 50 km), and scales with the
# number of (track, ZCTA) combinations in the request. Only a rough guide.
.distance_timings <- data.frame(radius_km = c(1, 5, 10, 25, 50), seconds = c(9, 17, 32, 119, 362))
.distance_seconds <- function(radius_km, n_tracks_by_vint, n_zcta_by_vint) {
  v <- names(n_tracks_by_vint)
  full_tracks <- .vint_counts(.vintage_of(as.integer(substr(.tracks()$tornado_id, 1, 4))))
  cen <- .centroids()
  full_zcta <- .vint_counts(cen$vintage)
  frac <- sum(n_tracks_by_vint * n_zcta_by_vint[v]) / sum(full_tracks * full_zcta)
  lx <- log(.distance_timings$radius_km); ly <- log(.distance_timings$seconds)
  k <- findInterval(log(radius_km), lx, all.inside = TRUE)
  full <- exp(ly[k] + (ly[k + 1L] - ly[k]) * (log(radius_km) - lx[k]) / (lx[k + 1L] - lx[k]))
  full * frac
}

.slow_distance_message <- function(radius_km, n_tracks_by_vint, cen, threshold = 20) {
  # a message is printed when the estimate is at least `threshold` seconds: a display setting that does not change any result
  n_zcta <- .vint_counts(cen$vintage)
  est <- .distance_seconds(radius_km, n_tracks_by_vint, n_zcta)
  if (est >= threshold) {
    message("centroid_dist_km = ", radius_km, " for ", sum(n_tracks_by_vint),
            " tornadoes and ", length(unique(cen$ZCTA)), " ZCTAs may take about ",
            if (est >= 90) paste(round(est / 60), "minutes") else paste(round(est), "seconds"),
            " (rough estimate). Narrow geo_list or year_range, or use a smaller radius, to speed it up.")
  }
  invisible(est)
}

.exposure_columns <- function() names(.exposure())
.distance_columns <- c("dist_km", "centroid_type", "centroid_in_zcta")

# Assemble the output rows of a distance call.
#   pairs    data frame with tornado_id, ZCTA, vintage, dist_km
#   attrs    one row per tornado: tornado_id, date, magnitude, total_injury,
#            total_fatality, property_loss_tornado_total, track_type
#   overlap  stored overlap rows (tornado_exposure-like) with the area and
#            population columns for pairs where the path overlaps the ZCTA
#   cen      the centroid table
# Pairs where the path does not overlap the ZCTA get 0 for the area and
# population columns.
.assemble_distance <- function(pairs, attrs, overlap, cen) {
  ov_cols <- c("area_prop_affected", "pop_affected", "pop_prop_affected",
               "area_share_of_tornado", "property_loss_allocated")
  out <- merge(pairs, attrs, by = "tornado_id", all.x = TRUE, sort = FALSE)
  out <- merge(out, cen[, c("ZCTA", "vintage", "zcta_pop", "centroid_type", "centroid_in_zcta")],
               by = c("ZCTA", "vintage"), all.x = TRUE, sort = FALSE)
  out <- merge(out, overlap[, c("tornado_id", "ZCTA", ov_cols)],
               by = c("tornado_id", "ZCTA"), all.x = TRUE, sort = FALSE)
  none <- is.na(out$area_prop_affected)   # no overlap row: the path misses the ZCTA
  out$area_prop_affected[none] <- 0
  out$area_share_of_tornado[none] <- 0
  out$property_loss_allocated[none] <- ifelse(is.na(out$property_loss_tornado_total[none]), NA_real_, 0)
  out$pop_affected[none] <- 0
  out$pop_prop_affected[none] <- ifelse(out$zcta_pop[none] > 0, 0, NA_real_)
  out$year <- as.integer(format(out$date, "%Y"))
  out$month <- as.integer(format(out$date, "%m"))
  out$day <- as.integer(format(out$date, "%d"))
  out <- out[order(out$date, out$tornado_id, out$ZCTA), , drop = FALSE]
  out <- out[, c(.exposure_columns(), .distance_columns), drop = FALSE]
  rownames(out) <- NULL
  out
}

.warn_geometric_centroids <- function(out) {
  n <- length(unique(out$ZCTA[out$centroid_type == "geometric"]))
  if (n > 0L) {
    warning(n, " ZCTA", if (n > 1L) "s" else "", " in the result ",
            if (n > 1L) "have" else "has", " no residents, so ",
            if (n > 1L) "their centroids are" else "its centroid is",
            " the geometric center of the ZCTA, not a population-weighted ",
            'one (centroid_type = "geometric").', call. = FALSE)
  }
  invisible(out)
}

.empty_distance <- function() {
  e <- .exposure()[0, , drop = FALSE]
  e$dist_km <- numeric(0); e$centroid_type <- character(0)
  e$centroid_in_zcta <- logical(0)
  e
}

# SPC paths: tornadoes in the request, with the centroid of each requested ZCTA
# within v$threshold km of the path
.select_distance <- function(v) {
  tracks <- .tracks()
  yr <- as.integer(substr(tracks$tornado_id, 1, 4))
  keep <- yr %in% v$year_range & tracks$magnitude %in% v$magnitude
  tracks <- tracks[keep, ]
  cen <- .centroids()
  cen <- cen[Reduce(`|`, lapply(v$geo_list, function(p) startsWith(cen$ZCTA, p))), ]
  out <- .empty_distance()
  if (nrow(tracks) > 0L && nrow(cen) > 0L) {
    vint <- .vintage_of(as.integer(substr(tracks$tornado_id, 1, 4)))
    .slow_distance_message(v$threshold, .vint_counts(vint), cen)
    make_poly <- function(i, crs) {
      .path_polygon(tracks[i, ], tracks$wid_yd[i], tracks$len_mi[i],
                    tracks$track_type[i], crs = crs)
    }
    pr <- .distance_pairs(.distance_region(tracks), vint, cen, v$threshold,
                          make_poly)
    if (nrow(pr) > 0L) {
      pairs <- data.frame(tornado_id = tracks$tornado_id[pr$i], ZCTA = cen$ZCTA[pr$j],
                          vintage = cen$vintage[pr$j], dist_km = pr$dist_km,
                          stringsAsFactors = FALSE)
      attrs <- sf::st_drop_geometry(tracks)[, c("tornado_id", "date", "magnitude",
        "total_injury", "total_fatality", "property_loss_tornado_total", "track_type")]
      out <- .assemble_distance(pairs, attrs, .exposure(), cen)
    }
  }
  if (nrow(out) == 0L) {
    message("No tornado exposures found for ", .describe_request(v), ". ",
            "Try a wider year_range, more magnitudes, or a larger centroid_dist_km.")
  } else {
    .warn_geometric_centroids(out)
  }
  out
}
