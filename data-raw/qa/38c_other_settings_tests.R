# Run from the package root:  Rscript data-raw/qa/38c_other_settings_tests.R
# Tests and measurements for the remaining fixed settings (results: data-raw/qa/out/other_settings.rds):
#   - minimum path width used when SPC records a width of 0 (10 yards): effect of 5, 10 and 20 yards
#   - the sanity limits of the update checks (path length, coordinates): the values actually in the data
#   - the 10 km buffer around state outlines used to choose which states' blocks are read
#   - the 1.05 factor on the search radius in distance queries
# The 5 km candidate-block buffer is checked by 35_population_candidate_check.R.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE)
source("R/path_polygon.R"); source("data-raw/population/population_functions.R"); source("data-raw/qa/helpers.R")
load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda"); load("data/zcta_centroids.rda")
out <- list()
# ---- minimum width ---------------------------------------------------------------------
tt <- tornado_tracks; aff <- tt[tt$width_imputed, ]
cat("tornadoes with SPC width 0 or missing (width set to the minimum):", nrow(aff), "of", nrow(tt), "\n")
w_nonzero <- tt$wid_yd[!tt$width_imputed]
cat("smallest SPC width above 0 (yards):", min(w_nonzero), "; tornadoes at 10 yards or less:", sum(w_nonzero <= 10), "; at exactly 10 yards:", sum(w_nonzero == 10), "\n")
yr <- as.integer(substr(aff$tornado_id, 1, 4)); vint <- ifelse(yr < 2010, 2000L, ifelse(yr < 2020, 2010L, 2020L))
zl <- lapply(c(2000L, 2010L, 2020L), zcta_layer); names(zl) <- c(2000, 2010, 2020)
rows_at <- function(w) { poly <- .path_polygon(aff, rep(w, nrow(aff)), aff$len_mi, aff$track_type)
  n <- integer(nrow(aff)); for (v in c(2000L, 2010L, 2020L)) { k <- which(vint == v); if (length(k)) n[k] <- lengths(st_intersects(poly[k], st_transform(zl[[as.character(v)]], st_crs(poly)))) }
  list(n = n, area = as.numeric(st_area(poly)) / 1e6) }
r <- lapply(c(5, 10, 20), rows_at); names(r) <- c(5, 10, 20)
out$min_width <- data.frame(width_yd = c(5, 10, 20), tornadoes = nrow(aff), zcta_pairs = vapply(r, function(x) sum(x$n), 0), tornadoes_with_a_zcta = vapply(r, function(x) sum(x$n > 0), 0),
                            median_area_km2 = round(vapply(r, function(x) median(x$area), 0), 5), pair_change_vs_10yd = vapply(r, function(x) sum(x$n), 0) - sum(r[["10"]]$n))
print(out$min_width, row.names = FALSE)
cur <- tornado_exposure[tornado_exposure$tornado_id %in% aff$tornado_id, ]
cat("rows in tornado_exposure for these tornadoes (10 yards):", nrow(cur), "; with area_prop_affected at most 0.01:", sum(cur$area_prop_affected <= 0.01), "\n")
# ---- extremes of the update sanity limits -----------------------------------------------------------
xy <- do.call(rbind, lapply(st_geometry(tornado_tracks), function(g) { m <- unclass(g); if (!is.matrix(m)) m <- matrix(m, ncol = 2); m }))
out$extremes <- list(max_len_mi = max(tt$len_mi), longest_id = tt$tornado_id[which.max(tt$len_mi)], lat = range(xy[, 2]), lon = range(xy[, 1]), n_over_100_mi = sum(tt$len_mi > 100))
print(out$extremes)
# ---- state buffer ------------------------------------------------------------------------------------
stt <- tigris::states(cb = TRUE, year = 2020, progress_bar = FALSE); stt <- sf::st_transform(stt[, "STATEFP"], 5070)
states <- pop_states(); stt <- stt[stt$STATEFP %in% states$state_code, ]
set.seed(11); ids <- unique(c(tt$tornado_id[order(-tt$len_mi)][1:100], sample(tt$tornado_id, 3000)))
sub <- tt[match(ids, tt$tornado_id), ]; poly <- .path_polygon(sub, sub$wid_yd, sub$len_mi, sub$track_type)
nset <- function(b) { hit <- st_intersects(poly, if (b > 0) st_buffer(stt, b) else stt); vapply(hit, function(h) paste(sort(stt$STATEFP[h]), collapse = ","), "") }
s0 <- nset(0); s10 <- nset(10000); s50 <- nset(50000)
cat("paths with no state outline within 10 km:", paste(ids[s10 == ""], collapse = ", "), "\n")
out$state_buffer <- data.frame(tornadoes = length(ids), differ_0_vs_10km = sum(s0 != s10), differ_10km_vs_50km = sum(s10 != s50), none_at_0 = sum(s0 == ""), none_at_10km = sum(s10 == ""))
print(out$state_buffer, row.names = FALSE)
# ---- radius factor -----------------------------------------------------------------------------------
cen <- zcta_centroids; set.seed(5); k <- sample(nrow(tt[tt$track_type == "line", ]), 200); tl <- tt[tt$track_type == "line", ][k, ]
polyl <- .path_polygon(tl, tl$wid_yd, tl$len_mi, tl$track_type); pts <- sf::st_transform(sf::st_as_sf(cen[cen$vintage == 2020, ], coords = c("lon", "lat"), crs = 4269), 5070); pts <- st_geometry(pts)
res <- lapply(c(5, 25), function(rad) { n <- vapply(c(1.0, 1.05, 1.5), function(f) { cand <- st_intersects(st_buffer(polyl, rad * 1000 * f), pts); ii <- rep(seq_along(cand), lengths(cand)); jj <- unlist(cand)
  d <- as.numeric(st_distance(polyl[ii], pts[jj], by_element = TRUE)) / 1000; sum(d <= rad) }, 0); data.frame(radius_km = rad, factor_1.00 = n[1], factor_1.05 = n[2], factor_1.50 = n[3]) })
out$radius_factor <- bind_rows(res); print(out$radius_factor, row.names = FALSE)
saveRDS(out, qa_out("other_settings.rds"))
