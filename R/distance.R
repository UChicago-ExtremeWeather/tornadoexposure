# Distance exposure, measured from the SPC line (or from the start point of a tornado
# with no usable end point):
#   centroid_dist_km  the population-weighted centroid of the ZCTA lies within this distance
#   boundary_dist_km  the ZCTA's boundary (full TIGER/Line polygon) lies within this distance
#                     (0 when the line crosses the ZCTA)
# Nothing beyond the rows of tornado_exposure is precomputed: distances are computed on
# demand from the stored tracks, the small zcta_centroids table and, for the boundary
# distance, the full TIGER/Line ZCTA file.

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

# Distance in km from each track (an sfc of LINESTRING or POINT in EPSG:4326, one per
# element) to the point (lon, lat) of the same index (NAD83), element by element.
.track_centroid_dist <- function(geom, lon, lat) {
  region <- .distance_region(geom)
  d <- numeric(length(geom))
  for (rg in unique(region)) {
    i <- which(region == rg)
    crs <- .distance_crs[[rg]]
    d[i] <- as.numeric(sf::st_distance(
      sf::st_transform(sf::st_geometry(geom)[i], crs),
      .centroid_points(data.frame(lon = lon[i], lat = lat[i]), crs),
      by_element = TRUE)) / 1000
  }
  d
}

# Distance in km from each track to the ZCTA polygon of the same index (sfc in any CRS),
# element by element; 0 when they touch.
.track_zcta_dist <- function(geom, zpoly) {
  region <- .distance_region(geom)
  d <- numeric(length(geom))
  for (rg in unique(region)) {
    i <- which(region == rg)
    crs <- .distance_crs[[rg]]
    d[i] <- as.numeric(sf::st_distance(
      sf::st_transform(sf::st_geometry(geom)[i], crs),
      sf::st_transform(sf::st_geometry(zpoly)[i], crs), by_element = TRUE)) / 1000
  }
  d
}

# Pairs (track, target) with the target within `radius_km` of the track. `region` and
# `vint` give the region and ZCTA vintage of each track, `targets` is an sf (centroid
# points as a table with lon and lat, or ZCTA polygons) with a `vintage` column,
# `make_geom(i, crs)` returns the geometries of tracks `i` in `crs` and
# `make_target(j, crs)` those of targets `j`. Returns a data frame with `i` (index of
# the track), `j` (target row) and `dist_km`. The spatial index is used through a
# slightly oversized buffer; exact distances are then computed for the candidate
# pairs only (sf::st_is_within_distance has no index and is far too slow for a
# nationwide call).
.distance_pairs <- function(region, vint, vintage, radius_km, make_geom, make_target) {
  out <- list()
  for (rg in unique(region)) for (vv in sort(unique(vint))) {
    i <- which(region == rg & vint == vv)
    jrows <- which(vintage == vv)
    if (length(i) == 0L || length(jrows) == 0L) next
    crs <- .distance_crs[[rg]]
    g <- make_geom(i, crs)
    tg <- make_target(jrows, crs)
    cand <- sf::st_intersects(sf::st_buffer(g, radius_km * 1000 * 1.05), tg, sparse = TRUE)
    n <- lengths(cand)
    ii <- rep(seq_along(i), n)
    jj <- unlist(cand)
    if (length(jj) == 0L) next
    d <- as.numeric(sf::st_distance(g[ii], tg[jj], by_element = TRUE)) / 1000
    keep <- d <= radius_km
    out[[length(out) + 1L]] <- data.frame(i = i[ii[keep]], j = jrows[jj[keep]], dist_km = d[keep])
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

# Rough time for a centroid distance call. The measured times of the nationwide 1996-2025
# query (every tornado, about 33,000 ZCTAs per vintage, one core) at radii of 1,
# 5, 10, 25 and 50 km are in the table of data-raw/known_issues.md (written by
# data-raw/qa/23_distance_tables.R); the estimate interpolates between them on
# log scales (and extends the last segment beyond 50 km), and scales with the
# number of (track, ZCTA) combinations in the request. Only a rough guide: the times vary between runs and
# data-raw/qa/check_documented_claims.R requires them to be within a factor of 2 of the latest measurement.
.distance_timings <- data.frame(radius_km = c(1, 5, 10, 25, 50), seconds = c(5, 12, 26, 110, 373))
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

.dat_count_columns <- function() grep("^dat_points_", names(.exposure()), value = TRUE)

# Attributes of the tornadoes of a request: tornado_id, date, magnitude, injuries, fatalities, loss, track type
.track_attrs <- function(tracks) {
  sf::st_drop_geometry(tracks)[, c("tornado_id", "date", "magnitude", "total_injury", "total_fatality", "property_loss_tornado_total", "track_type")]
}

# Assemble the output rows of a distance call.
#   pairs    data frame with tornado_id, ZCTA, vintage and the distance columns that were measured
#   tracks   the tornadoes of the request (sf)
#   stored   tornado_exposure
#   cen      the centroid table
# A pair that has a stored row (the ZCTA is exposed by the SPC line or by a linked DAT polygon) returns the stored row. A pair with no stored row is a ZCTA
# that neither source exposes: spc_exposed is FALSE, the line is not in the ZCTA (0 km and share 0 for a line, NA for a point; allocated loss 0, or NA where the
# tornado's loss is NA), and for a tornado with a linked DAT line dat_exposed is FALSE and the DAT area and resident columns are 0. The point counts and
# other_tornadoes_in_zcta_within_a_day are not tabulated for ZCTAs that no source exposes (NA), and the distance that was not asked for is NA.
.assemble_distance <- function(pairs, tracks, stored, cen) {
  key <- paste(pairs$tornado_id, pairs$ZCTA); sk <- paste(stored$tornado_id, stored$ZCTA)
  hit <- key %in% sk
  old <- stored[match(key[hit], sk), , drop = FALSE]
  new <- pairs[!hit, , drop = FALSE]
  parts <- list(old)
  if (nrow(new) > 0L) {
    at <- .track_attrs(tracks)[match(new$tornado_id, tracks$tornado_id), ]
    cc <- cen[match(paste(new$ZCTA, new$vintage), paste(cen$ZCTA, cen$vintage)), ]
    ids <- .dat_line_ids()
    linked <- new$tornado_id %in% names(ids)
    n <- data.frame(tornado_id = new$tornado_id, date = at$date, stringsAsFactors = FALSE)
    n$year <- as.numeric(format(at$date, "%Y")); n$month <- format(at$date, "%m"); n$day <- format(at$date, "%d")
    n$magnitude <- at$magnitude; n$total_injury <- at$total_injury; n$total_fatality <- at$total_fatality
    n$property_loss_tornado_total <- at$property_loss_tornado_total; n$track_type <- at$track_type; n$ZCTA <- new$ZCTA
    n$spc_exposed <- FALSE
    n$line_km_in_zcta <- ifelse(at$track_type == "line", 0, NA_real_)
    n$line_share_of_tornado <- 0
    n$property_loss_allocated <- ifelse(is.na(at$property_loss_tornado_total), NA_real_, 0)
    n$centroid_dist_km <- if ("centroid_dist_km" %in% names(new)) new$centroid_dist_km else NA_real_
    n$boundary_dist_km <- if ("boundary_dist_km" %in% names(new)) new$boundary_dist_km else NA_real_
    n$zcta_pop <- as.numeric(cc$zcta_pop); n$zcta_land_area_m2 <- cc$zcta_land_area_m2
    n$zcta_polygon_area_m2 <- cc$zcta_polygon_area_m2; n$zcta_land_shape_area_m2 <- cc$zcta_land_shape_area_m2
    n$dat_linked <- linked; n$dat_line_ids <- unname(ids[new$tornado_id])
    n$dat_exposed <- ifelse(linked, FALSE, NA)
    zero <- function(x) ifelse(linked, x, NA_real_)
    for (nm in grep("^dat_(area_share|pop)", names(stored), value = TRUE)) n[[nm]] <- zero(0)
    for (nm in c(.dat_count_columns(), "other_tornadoes_in_zcta_within_a_day")) n[[nm]] <- NA_integer_
    parts[[2]] <- n[, names(stored), drop = FALSE]
  }
  out <- do.call(rbind, parts)
  out[order(out$date, out$tornado_id, out$ZCTA), , drop = FALSE]
}

# the linked DAT line ids of each tornado, as in the column dat_line_ids
.dat_line_ids <- function() {
  lk <- tornadoexposure::tornado_dat_link
  vapply(split(lk$dat_line_id, lk$tornado_id), function(x) paste(sort(x), collapse = ";"), "")
}

.finish_distance <- function(out) {
  out <- out[, .exposure_columns(), drop = FALSE]
  rownames(out) <- NULL
  out
}

.empty_distance <- function() .exposure()[0, , drop = FALSE]

.warn_geometric_centroids <- function(out, cen) {
  gz <- cen$ZCTA[cen$centroid_type == "geometric"]
  n <- length(unique(out$ZCTA[out$ZCTA %in% gz]))
  if (n > 0L) {
    warning(n, " ZCTA", if (n > 1L) "s" else "", " in the result ",
            if (n > 1L) "have" else "has", " no residents, so ",
            if (n > 1L) "their centroids are" else "its centroid is",
            " the geometric center of the ZCTA, not a population-weighted ",
            'one (see zcta_centroids$centroid_type).', call. = FALSE)
  }
  invisible(out)
}

# Tornadoes of the request (years and ratings) as an sf of tracks
.request_tracks <- function(v) {
  tracks <- .tracks()
  yr <- as.integer(substr(tracks$tornado_id, 1, 4))
  tracks[yr %in% v$year_range & tracks$magnitude %in% v$magnitude, ]
}

# SPC tracks: tornadoes in the request, with the centroid of each requested ZCTA within
# v$threshold km of the SPC line (or start point)
.select_distance <- function(v) {
  tracks <- .request_tracks(v)
  cen <- .centroids()
  cen <- cen[Reduce(`|`, lapply(v$geo_list, function(p) startsWith(cen$ZCTA, p))), ]
  out <- .empty_distance()
  if (nrow(tracks) > 0L && nrow(cen) > 0L) {
    vint <- .vintage_of(as.integer(substr(tracks$tornado_id, 1, 4)))
    .slow_distance_message(v$threshold, .vint_counts(vint), cen)
    pr <- .distance_pairs(.distance_region(tracks), vint, cen$vintage, v$threshold,
                          make_geom = function(i, crs) sf::st_transform(sf::st_geometry(tracks)[i], crs),
                          make_target = function(j, crs) .centroid_points(cen[j, , drop = FALSE], crs))
    if (nrow(pr) > 0L) {
      pairs <- data.frame(tornado_id = tracks$tornado_id[pr$i], ZCTA = cen$ZCTA[pr$j],
                          vintage = cen$vintage[pr$j], centroid_dist_km = pr$dist_km,
                          stringsAsFactors = FALSE)
      out <- .finish_distance(.assemble_distance(pairs, tracks, .exposure(), cen))
    }
  }
  if (nrow(out) == 0L) {
    message("No tornado exposures found for ", .describe_request(v), ". ",
            "Try a wider year_range, more magnitudes, or a larger centroid_dist_km.")
  } else {
    .warn_geometric_centroids(out, cen)
  }
  out
}

# Full TIGER/Line ZCTA polygons (cb = FALSE) for the ZCTAs starting with `geo_list` of one
# vintage, as an sf in EPSG:4269 with columns ZCTA and vintage. The national file is
# downloaded once through tigris (its size is in the message) and cached.
.full_zcta <- function(geo_list, vintage) {
  size_mb <- c(`2000` = 680, `2010` = 524, `2020` = 528)[[as.character(vintage)]]
  message("Boundary distances use the full TIGER/Line ZCTA boundaries of ", vintage,
          ": a national file of about ", size_mb, " MB, downloaded once and cached by tigris.")
  z <- tigris::zctas(year = vintage, cb = FALSE, progress_bar = FALSE)
  z <- .standardize_zcta(z)
  z <- z[Reduce(`|`, lapply(geo_list, function(p) startsWith(z$ZCTA, p))), ]
  z <- sf::st_transform(z, 4269)
  z$vintage <- vintage
  z
}

# SPC tracks: tornadoes in the request, with the boundary of each requested ZCTA within
# v$threshold km of the SPC line (or start point)
.select_boundary <- function(v) {
  tracks <- .request_tracks(v)
  cen <- .centroids()
  out <- .empty_distance()
  if (nrow(tracks) > 0L) {
    vint <- .vintage_of(as.integer(substr(tracks$tornado_id, 1, 4)))
    zz <- do.call(rbind, lapply(sort(unique(vint)), function(vv) .full_zcta(v$geo_list, vv)))
    if (!is.null(zz) && nrow(zz) > 0L) {
      pr <- .distance_pairs(.distance_region(tracks), vint, zz$vintage, v$threshold,
                            make_geom = function(i, crs) sf::st_transform(sf::st_geometry(tracks)[i], crs),
                            make_target = function(j, crs) sf::st_transform(sf::st_geometry(zz)[j], crs))
      if (nrow(pr) > 0L) {
        pairs <- data.frame(tornado_id = tracks$tornado_id[pr$i], ZCTA = zz$ZCTA[pr$j],
                            vintage = zz$vintage[pr$j], boundary_dist_km = pr$dist_km,
                            stringsAsFactors = FALSE)
        cc <- cen[match(paste(pairs$ZCTA, pairs$vintage), paste(cen$ZCTA, cen$vintage)), ]
        has_cen <- !is.na(cc$lon); pairs <- pairs[has_cen, ]; cc <- cc[has_cen, ]   # ZCTAs outside the block data (Guam and others) have no centroid
        pairs$centroid_dist_km <- .track_centroid_dist(sf::st_geometry(tracks)[match(pairs$tornado_id, tracks$tornado_id)], cc$lon, cc$lat)
        out <- .finish_distance(.assemble_distance(pairs, tracks, .exposure(), cen))
      }
    }
  }
  if (nrow(out) == 0L) {
    message("No tornado exposures found for ", .describe_request(v), ". ",
            "Try a wider year_range, more magnitudes, or a larger boundary_dist_km.")
  }
  out
}
