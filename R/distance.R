# Distance exposure, measured from the SPC line (or from the start point of a tornado
# with no usable end point):
#   centroid_dist_km  the population-weighted centroid of the ZCTA lies within this distance
#   boundary_dist_km  the ZCTA's boundary (full TIGER/Line polygon) lies within this distance
#                     (0 when the line touches the ZCTA)
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
# number of (track, ZCTA) combinations in the request. Only a rough guide.
.distance_timings <- data.frame(radius_km = c(1, 5, 10, 25, 50), seconds = c(5, 12, 28, 111, 343))
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
.modeled_columns <- c("modeled_intersection_m2", "modeled_area_prop", "modeled_pop_affected",
                      "modeled_pop_prop", "modeled_area_share_of_tornado", "modeled_property_loss_allocated")

# Assemble the output rows of a distance call.
#   pairs    data frame with tornado_id, ZCTA, vintage and the distance columns that were measured
#   attrs    one row per tornado: tornado_id, date, magnitude, total_injury,
#            total_fatality, property_loss_tornado_total, track_type, has_shape
#   overlap  stored overlap rows (tornado_exposure) with the modeled columns for pairs where
#            the modeled path overlaps the ZCTA
#   cen      the centroid table
# Pairs with no stored row (the modeled path does not overlap the ZCTA) get 0 for the modeled
# columns when the tornado has a modeled path polygon and NA when it has none.
.assemble_distance <- function(pairs, attrs, overlap, cen) {
  out <- merge(pairs, attrs, by = "tornado_id", all.x = TRUE, sort = FALSE)
  out <- merge(out, cen[, c("ZCTA", "vintage", "zcta_pop", "zcta_polygon_area_m2", "zcta_land_area_m2")], by = c("ZCTA", "vintage"), all.x = TRUE, sort = FALSE)
  ov <- overlap[, c("tornado_id", "ZCTA", .modeled_columns)]
  out <- merge(out, ov, by = c("tornado_id", "ZCTA"), all.x = TRUE, sort = FALSE)
  none <- is.na(out$modeled_intersection_m2) & out$has_shape
  out$modeled_intersection_m2[none] <- 0
  out$modeled_area_prop[none] <- 0
  out$modeled_area_share_of_tornado[none] <- 0
  out$modeled_property_loss_allocated[none] <- ifelse(is.na(out$property_loss_tornado_total[none]), NA_real_, 0)
  out$modeled_pop_affected[none] <- 0
  out$modeled_pop_prop[none] <- ifelse(out$zcta_pop[none] > 0, 0, NA_real_)
  out$year <- as.numeric(format(out$date, "%Y"))   # the types of tornado_exposure
  out$month <- format(out$date, "%m")
  out$day <- format(out$date, "%d")
  out <- out[order(out$date, out$tornado_id, out$ZCTA), , drop = FALSE]
  out
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

.track_attrs <- function(tracks) {
  a <- sf::st_drop_geometry(tracks)[, c("tornado_id", "date", "magnitude", "total_injury", "total_fatality",
                                         "property_loss_tornado_total", "track_type")]
  a$has_shape <- !is.na(tracks$modeled_path_area_m2)
  a
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
      ov <- .exposure()
      pairs$boundary_dist_km <- ifelse(paste(pairs$tornado_id, pairs$ZCTA) %in% paste(ov$tornado_id, ov$ZCTA),
                                       ov$boundary_dist_km[match(paste(pairs$tornado_id, pairs$ZCTA), paste(ov$tornado_id, ov$ZCTA))], NA_real_)
      out <- .finish_distance(.assemble_distance(pairs, .track_attrs(tracks), ov, cen))
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
        out <- .finish_distance(.assemble_distance(pairs, .track_attrs(tracks), .exposure(), cen))
      }
    }
  }
  if (nrow(out) == 0L) {
    message("No tornado exposures found for ", .describe_request(v), ". ",
            "Try a wider year_range, more magnitudes, or a larger boundary_dist_km.")
  }
  out
}
