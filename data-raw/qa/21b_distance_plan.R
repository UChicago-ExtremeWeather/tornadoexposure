# Run from the package root: Rscript data-raw/qa/21b_distance_plan.R
# Diagnostics for centroid_dist_km (changes nothing).
# Needs 21a. Reports: centroids outside their own polygon, zero-resident ZCTAs,
# size of the centroid table, runtime of a distance query, how the distance set
# relates to the overlap set, and a check of EPSG:5070 distances against geodesic ones.
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R"); source("R/path_polygon.R")
suppressMessages({library(sf); library(dplyr)}); options(width = 170); sf_use_s2(FALSE)
CT <- readRDS(qa_out("zcta_centroids_plan.rds")); cen <- CT$centroids
load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda")
cat("block internal points present (blocks with finite INTPTLAT/INTPTLON out of blocks):\n")
print(CT$block_point_check %>% group_by(vint) %>% summarise(blocks = sum(blocks), with_point = sum(with_point), .groups = "drop") %>% as.data.frame(), row.names = FALSE)
pt5070 <- function(lon, lat) sf::st_transform(sf::st_as_sf(data.frame(lon = lon, lat = lat), coords = c("lon", "lat"), crs = 4269), 5070)
# ---- centroid table: type, location, inside own polygon --------------------
out <- list(); polys <- list()
for (v in c(2000, 2010, 2020)) {
  z <- zcta_layer(v); z5 <- sf::st_transform(z, 5070); polys[[as.character(v)]] <- z5
  c1 <- cen[cen$vint == v, ]; c1 <- c1[match(z5$ZCTA, c1$ZCTA), ]
  c1$centroid_type <- ifelse(c1$zcta_pop > 0, "population", "geometric")
  c1$lon <- ifelse(c1$zcta_pop > 0, c1$pop_lon, c1$geom_lon); c1$lat <- ifelse(c1$zcta_pop > 0, c1$pop_lat, c1$geom_lat)
  p <- pt5070(c1$lon, c1$lat)
  inside <- as.logical(sf::st_intersects(sf::st_geometry(p), sf::st_geometry(z5), sparse = FALSE)[cbind(seq_len(nrow(c1)), seq_len(nrow(c1)))])
  dout <- as.numeric(sf::st_distance(sf::st_geometry(p), sf::st_geometry(z5), by_element = TRUE)) / 1000
  c1$inside <- inside; c1$dist_out_km <- ifelse(inside, 0, dout)
  # geometric centroid inside its own polygon? (matters for the zero-resident fallback)
  g <- pt5070(c1$geom_lon, c1$geom_lat)
  c1$geom_inside <- sf::st_intersects(sf::st_geometry(g), sf::st_geometry(z5), sparse = FALSE)[cbind(seq_len(nrow(c1)), seq_len(nrow(c1)))]
  both <- c1$zcta_pop > 0
  c1$pop_vs_geom_km <- ifelse(both, as.numeric(sf::st_distance(sf::st_geometry(p), sf::st_geometry(g), by_element = TRUE)) / 1000, NA)
  out[[as.character(v)]] <- c1
  cat(sprintf("\n=== ZCTA vintage %d: %d polygons ===\n", v, nrow(c1)))
  cat(sprintf("zero-resident ZCTAs (geometric-centroid fallback): %d (%.1f%%); with residents: %d\n", sum(!both), 100 * mean(!both), sum(both)))
  cat(sprintf("population centroid outside its own polygon: %d of %d (%.2f%%); their residents: %s (%.3f%% of all)\n", sum(!inside[both]), sum(both), 100 * mean(!inside[both]), format(sum(c1$zcta_pop[both & !inside]), big.mark = ","), 100 * sum(c1$zcta_pop[both & !inside]) / sum(c1$zcta_pop)))
  d <- c1$dist_out_km[both & !inside]; cat("  distance from the centroid to its polygon (km), outside cases: quantiles 50/90/99/100:", paste(signif(quantile(d, c(.5, .9, .99, 1)), 3), collapse = " "), "; over 1 km:", sum(d > 1), "; over 5 km:", sum(d > 5), "\n")
  cat(sprintf("geometric centroid outside its polygon: %d of %d (%d of the %d zero-resident ZCTAs)\n", sum(!c1$geom_inside), nrow(c1), sum(!c1$geom_inside[!both]), sum(!both)))
  dd <- c1$pop_vs_geom_km[both]; cat("population centroid vs geometric centroid (km), ZCTAs with residents: quantiles 50/90/99/100:", paste(signif(quantile(dd, c(.5, .9, .99, 1)), 3), collapse = " "), "\n")
}
tab <- bind_rows(out)
zc <- tab %>% transmute(ZCTA, vintage = as.integer(vint), lon = round(lon, 5), lat = round(lat, 5), centroid_type, centroid_in_zcta = inside)
tmp <- tempfile(fileext = ".rda"); zcta_centroids <- zc; save(zcta_centroids, file = tmp, compress = "xz")
cat(sprintf("\nzcta_centroids: %d rows (%s), %d columns; xz .rda size %.0f KB\n", nrow(zc), paste(table(zc$vintage), collapse = " + "), ncol(zc), file.size(tmp) / 1024))
saveRDS(tab, qa_out("zcta_centroids_plan_full.rds"))
# ---- query runtime and relation to the overlap set -------------------------
yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4)); vint <- ifelse(yr < 2010, 2000L, ifelse(yr < 2020, 2010L, 2020L))
poly <- .path_polygon(tornado_tracks, tornado_tracks$wid_yd, tornado_tracks$len_mi, tornado_tracks$track_type)
pts <- lapply(c("2000", "2010", "2020"), function(v) { c1 <- out[[v]]; sf::st_sf(ZCTA = c1$ZCTA, geometry = sf::st_geometry(pt5070(c1$lon, c1$lat))) }); names(pts) <- c("2000", "2010", "2020")
ex <- tornado_exposure %>% mutate(vint = ifelse(year < 2010, 2000L, ifelse(year < 2020, 2010L, 2020L)))
run <- function(R) {
  t0 <- proc.time()[3]; rows <- list()
  for (v in c(2000L, 2010L, 2020L)) {
    i <- which(vint == v); pl <- poly[i]; pp <- pts[[as.character(v)]]
    # buffer + intersects uses the spatial index (st_is_within_distance does not, and is far too slow);
    # the exact distance is then computed only for the candidate pairs
    h <- sf::st_intersects(sf::st_buffer(pl, R * 1000 * 1.02), pp, sparse = TRUE)
    n <- lengths(h); ii <- rep(seq_along(h), n); jj <- unlist(h)
    d <- as.numeric(sf::st_distance(pl[ii], sf::st_geometry(pp)[jj], by_element = TRUE)) / 1000
    k <- d <= R
    rows[[length(rows) + 1]] <- data.frame(tornado_id = tornado_tracks$tornado_id[i][ii][k], ZCTA = pp$ZCTA[jj][k], dist_km = d[k], vint = v)
  }
  list(rows = bind_rows(rows), secs = proc.time()[3] - t0)
}
res <- list()
cat("\nNationwide 1996-2025 query (all 38,027 tracks, all ZCTAs), by radius; one core:\n")
for (R in c(1, 5, 10, 25, 50)) {
  r <- run(R); res[[as.character(R)]] <- r$rows
  d <- r$rows; ov <- ex %>% select(tornado_id, ZCTA)
  key <- function(x) paste(x$tornado_id, x$ZCTA)
  in_ov <- key(d) %in% key(ov); ov_in <- key(ov) %in% key(d)
  nz <- setdiff(tornado_tracks$tornado_id, ex$tornado_id)
  cat(sprintf("R = %2d km: %7d rows, %5d tornadoes with no row, time %5.1f s; overlap pairs also within R: %.1f%%; rows not in the overlap set: %.1f%%; of the %d no-ZCTA tornadoes, %d get a row\n",
              R, nrow(d), nrow(tornado_tracks) - length(unique(d$tornado_id)), r$secs, 100 * mean(ov_in), 100 * mean(!in_ov), length(nz), sum(nz %in% d$tornado_id)))
}
d25 <- res[["25"]]
# ---- projection check: EPSG:5070 distances versus spherical-geodesic ones -----
set.seed(1); smp <- d25[sample(nrow(d25), 3000), ]; smp$vint <- smp$vint
chk <- lapply(split(smp, smp$vint), function(s) {
  v <- s$vint[1]; pl <- poly[match(s$tornado_id, tornado_tracks$tornado_id)]
  pp <- pts[[as.character(v)]]; pt <- sf::st_geometry(pp)[match(s$ZCTA, pp$ZCTA)]
  pl_seg <- sf::st_segmentize(pl, 500)   # metres: straight in 5070, so keep vertices dense before leaving the projection
  sf_use_s2(TRUE)
  g <- as.numeric(sf::st_distance(sf::st_transform(pl_seg, 4326), sf::st_transform(pt, 4326), by_element = TRUE)) / 1000
  sf_use_s2(FALSE)
  data.frame(s, geo_km = g)
}) %>% bind_rows()
chk$in_poly <- chk$dist_km == 0
chk$region <- ifelse(substr(chk$ZCTA, 1, 2) %in% c("99") | substr(chk$ZCTA, 1, 3) %in% c("967", "968") | substr(chk$ZCTA, 1, 3) %in% c("006", "007", "008", "009"), "AK, HI, PR", "contiguous US")
nz <- chk[chk$dist_km > 1, ]; nz$err_km <- nz$dist_km - nz$geo_km; nz$rel <- nz$err_km / nz$geo_km
cat("\nEPSG:5070 distance versus spherical geodesic distance (sample of 3000 pairs within 25 km; pairs over 1 km shown):\n")
print(nz %>% group_by(region) %>% summarise(pairs = n(), median_abs_err_m = round(1000 * median(abs(err_km))), p99_abs_err_m = round(1000 * quantile(abs(err_km), .99)), max_abs_err_m = round(1000 * max(abs(err_km))), median_rel_pct = round(100 * median(rel), 3), max_abs_rel_pct = round(100 * max(abs(rel)), 3), .groups = "drop") %>% as.data.frame(), row.names = FALSE)
cat("pairs with distance 0 (centroid inside the polygon) in 5070:", sum(chk$in_poly), "; of those, geodesic distance > 0.01 km:", sum(chk$in_poly & chk$geo_km > 0.01), "\n")
saveRDS(list(chk = chk, res_counts = lapply(res, nrow)), qa_out("distance_plan_results.rds"))
