# Run from the package root: Rscript data-raw/qa/03_crs_independence.R
# Does the set of ZCTAs that an SPC line crosses, and its length share in each, depend on the projection in which the straight line between the start and end points is drawn?
# A random sample of 300 line tornadoes (100 per boundary year, seed 303) is intersected with the full ZCTA polygons of its boundary year with the line drawn straight in
# EPSG:5070 (the package), in EPSG:6933 (equal-area cylindrical), in a local azimuthal equal-area projection centered on the line, and in longitude/latitude (planar). Reports the
# number of tornadoes whose ZCTA set differs from the package's, and the largest difference in line_share_of_tornado.
source("data-raw/qa/helpers.R"); source("data-raw/pipeline_functions.R")
suppressMessages({library(dplyr); library(sf)}); sf_use_s2(FALSE); options(width = 160)
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f)
set.seed(303)
ln <- tornado_tracks[tornado_tracks$track_type == "line", ]; ln$v <- vint_of(as.integer(substr(ln$tornado_id, 1, 4)))
smp <- bind_rows(lapply(c(2000L, 2010L, 2020L), function(v) { x <- ln[ln$v == v, ]; x[sample(nrow(x), 100), ] }))
pieces <- function(line_geom, zc_crs) {   # ZCTA codes and length shares for each line (sfc in the CRS of zc_crs)
  lapply(seq_along(line_geom), function(i) {
    zc <- zc_crs$z[st_intersects(line_geom[i], zc_crs$z)[[1]], ]
    if (!nrow(zc)) return(data.frame(ZCTA = character(), share = numeric()))
    x <- suppressWarnings(st_intersection(line_geom[i], st_geometry(zc))); len <- as.numeric(st_length(x)); keep <- len > 0
    data.frame(ZCTA = zc$ZCTA[attr(x, "idx")[, 2]][keep], share = len[keep] / sum(len[keep]))
  })
}
res <- list()
for (v in c(2000L, 2010L, 2020L)) {
  s <- smp[smp$v == v, ]; zc <- load_zctas(v); zz <- st_geometry(zc)
  centers <- st_coordinates(suppressWarnings(st_centroid(st_geometry(s))))
  line5 <- st_transform(st_geometry(s), 5070)
  cand <- st_intersects(st_buffer(line5, 10000), zz)      # only the ZCTAs near the line are transformed for each alternative projection
  crs_of <- function(nm, i) switch(nm, `6933` = 6933, laea = sprintf("+proj=laea +lat_0=%f +lon_0=%f +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs", centers[i, 2], centers[i, 1]), lonlat = 4269)
  for (i in seq_len(nrow(s))) {
    zi <- cand[[i]]; zi_sf <- st_sf(ZCTA = zc$ZCTA[zi], geometry = zz[zi])
    a <- pieces(line5[i], list(z = zi_sf))[[1]]
    for (nm in c("6933", "laea", "lonlat")) { crs <- crs_of(nm, i)
      b <- pieces(st_transform(st_geometry(s)[i], crs), list(z = st_sf(ZCTA = zi_sf$ZCTA, geometry = st_transform(st_geometry(zi_sf), crs))))[[1]]
      m <- merge(a, b, by = "ZCTA", all = TRUE, suffixes = c(".5070", ".alt")); m[is.na(m)] <- 0
      res[[length(res) + 1]] <- data.frame(vint = v, crs = nm, tornado_id = s$tornado_id[i], same_set = setequal(a$ZCTA, b$ZCTA), max_share_diff = max(abs(m$share.5070 - m$share.alt), 0)) }
  }
}
R <- bind_rows(res); out <- R %>% group_by(crs) %>% summarise(tornadoes = n(), set_differs = sum(!same_set), share_diff_max = max(max_share_diff), share_diff_p99 = quantile(max_share_diff, .99), share_diff_median = median(max_share_diff))
print(out); saveRDS(list(summary = out, detail = R), qa_out("crs_independence.rds"))
