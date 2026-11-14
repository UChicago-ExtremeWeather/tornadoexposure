# Run from the package root after a rebuild:  Rscript data-raw/qa/69_boundary_distance_check.R      (about 10 minutes; reads the three full ZCTA files)
# Checks every row of tornado_exposure: boundary_dist_km is 0 exactly where the SPC line (or start point) touches the ZCTA polygon, and that this is exactly where spc_exposed is TRUE of the boundary year, and where it is not 0 it equals the distance from the line to the polygon
# (kilometers, in the regional projection of R/distance.R). Stops if one row differs.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); source("data-raw/pipeline_functions.R"); sf_use_s2(FALSE)
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f)
d <- tornado_exposure; tr <- tornado_tracks; g5 <- st_transform(st_geometry(tr), 5070); bad <- 0L; checked <- 0L; pos <- 0L
for (v in c(2000L, 2010L, 2020L)) { zc <- load_zctas(v); r <- which(vint_of(d$year) == v); ti <- match(d$tornado_id[r], tr$tornado_id); zi <- match(d$ZCTA[r], zc$ZCTA)
  touch <- vapply(seq_along(r), function(k) lengths(st_intersects(g5[ti[k]], st_geometry(zc)[zi[k]])) > 0, logical(1))
  stopifnot(identical(touch, d$boundary_dist_km[r] == 0), identical(touch, d$spc_exposed[r]))   # 0 exactly where the line crosses (spc_exposed)
  far <- which(!touch); dd <- .track_zcta_dist(st_geometry(tr)[ti[far]], st_geometry(zc)[zi[far]]); stopifnot(isTRUE(all.equal(dd, d$boundary_dist_km[r][far], tolerance = 1e-9)))
  checked <- checked + length(r); pos <- pos + length(far); cat(v, ": ", length(r), " rows, ", length(far), " with a positive distance\n", sep = "") }
cat("boundary_dist_km agrees with the geometry for all ", checked, " rows (", pos, " positive)\n", sep = "")
