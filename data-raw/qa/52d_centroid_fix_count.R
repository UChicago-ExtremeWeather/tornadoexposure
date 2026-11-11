# Run from the package root:  Rscript data-raw/qa/52d_centroid_fix_count.R     Saves data-raw/qa/out/centroid_fix_count.rds
# add_centroids.R replaces the geometric centroid of a ZCTA with no residents by a point on the polygon surface when the geometric centroid falls outside the polygon. How many ZCTAs did that touch?
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(tigris_use_cache = TRUE); source("data-raw/qa/helpers.R"); load("data/zcta_centroids.rda"); out <- list()
for (v in c(2000, 2010, 2020)) { sfx <- substr(v, 3, 4); z <- tigris::zctas(year = v, progress_bar = FALSE); z <- z[, paste0("ZCTA5CE", sfx)]; names(z)[1] <- "ZCTA"; z <- st_transform(z, 5070)
  zc <- zcta_centroids[zcta_centroids$vintage == v & zcta_centroids$centroid_type == "geometric", ]; zz <- z[match(zc$ZCTA, z$ZCTA), ]; zz <- st_make_valid(zz); cen <- st_centroid(st_geometry(zz)); inside <- lengths(st_intersects(cen, st_geometry(zz))) > 0
  out[[as.character(v)]] <- data.frame(vintage = v, zero_resident_zctas = nrow(zc), geometric_centroid_outside_polygon_replaced = sum(!inside)) }
A <- bind_rows(out); saveRDS(A, qa_out("centroid_fix_count.rds")); print(A)
