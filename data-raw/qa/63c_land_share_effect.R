# Run from the package root after 63_land_only_area_test.R:  caffeinate -i Rscript data-raw/qa/63c_land_share_effect.R      Saves data-raw/qa/out/63c_land_share_effect.rds        (nothing is shipped)
# What a land-only area share would change. For every row of tornado_exposure with a modeled path (the intersection of the path polygon with the full ZCTA polygon), the part of the intersection that lies in water is the intersection with the Census water polygons
# (TIGER/Line AREAWATER by county, data-raw/qa/cache/areawater/); land intersection = intersection - water in the intersection. The land-only share is land intersection / land area of the ZCTA, where the land area of the ZCTA is its polygon area minus the water
# in it (the land shape of 63_land_only_area_test.R). It is compared with modeled_area_prop (intersection with the full polygon divided by the polygon area): the number of rows that differ by more than 1, 10 and 50 percent.
suppressMessages({library(sf); library(dplyr); library(parallel)}); source("data-raw/pipeline_functions.R"); source("data-raw/qa/helpers.R"); sf_use_s2(FALSE)
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f)
L <- readRDS(qa_out("63_land_test.rds")); wset <- c("2000" = "2010", "2010" = "2010", "2020" = "2020"); nproc <- as.integer(Sys.getenv("NPROC", "3"))
tt <- tornado_tracks; hp <- !is.na(tt$modeled_path_area_m2); poly <- .path_polygon(tt[hp, ], tt$wid_yd[hp]); names(poly) <- NULL
pol <- st_sf(tornado_id = tt$tornado_id[hp], geometry = poly)
one_county <- function(f, pieces) {
  w <- tryCatch(st_read(paste0("/vsizip/", f), quiet = TRUE), error = function(e) NULL); if (is.null(w) || nrow(w) == 0) return(NULL)
  w <- st_transform(st_make_valid(w), 5070); wb <- st_bbox(w)
  h <- which(pieces$xmin <= wb[["xmax"]] & pieces$xmax >= wb[["xmin"]] & pieces$ymin <= wb[["ymax"]] & pieces$ymax >= wb[["ymin"]]); if (!length(h)) return(NULL)
  wu <- st_union(st_geometry(w)); pp <- pieces[h, ]; pp <- pp[lengths(st_intersects(pp, wu)) > 0, ]; if (!nrow(pp)) return(NULL)
  x <- suppressWarnings(st_intersection(st_geometry(pp), wu)); data.frame(key = pp$key[attr(x, "idx")[, 1]], water_m2 = as.numeric(st_area(x)))
}
out <- list()
for (v in c(2000L, 2010L, 2020L)) {
  zc <- load_zctas(v); ex <- tornado_exposure[vint_of(tornado_exposure$year) == v & !is.na(tornado_exposure$modeled_intersection_m2), ]
  p <- pol[pol$tornado_id %in% ex$tornado_id, ]; x <- suppressWarnings(st_intersection(p, zc[, "ZCTA"])); x <- st_collection_extract(x, "POLYGON"); x$key <- paste(x$tornado_id, x$ZCTA); x <- x %>% group_by(key, tornado_id, ZCTA) %>% summarise(.groups = "drop")
  x$piece_m2 <- as.numeric(st_area(x)); bb <- t(vapply(st_geometry(x), function(g) as.numeric(st_bbox(g)), numeric(4))); x$xmin <- bb[, 1]; x$ymin <- bb[, 2]; x$xmax <- bb[, 3]; x$ymax <- bb[, 4]
  files <- list.files(file.path("data-raw/qa/cache/areawater", wset[[as.character(v)]]), full.names = TRUE); message(format(Sys.time(), "%H:%M:%S "), v, ": ", nrow(x), " pieces, ", length(files), " water files")
  wd <- bind_rows(mclapply(files, one_county, pieces = x, mc.cores = nproc)); wt <- wd %>% group_by(key) %>% summarise(water_m2 = sum(water_m2), .groups = "drop")
  y <- st_drop_geometry(x)[, c("key", "tornado_id", "ZCTA", "piece_m2")] %>% left_join(wt, by = "key"); y$water_m2[is.na(y$water_m2)] <- 0; y$land_piece_m2 <- y$piece_m2 - y$water_m2
  d <- L[[as.character(v)]]$d; y <- y %>% left_join(d[, c("ZCTA", "poly_m2", "land_m2")], by = "ZCTA"); y$land_prop <- y$land_piece_m2 / y$land_m2; y$full_prop <- y$piece_m2 / y$poly_m2; y$vint <- v; out[[as.character(v)]] <- y
}
Y <- bind_rows(out); Y$rel <- Y$land_prop / Y$full_prop - 1
chk <- tornado_exposure[match(Y$key, paste(tornado_exposure$tornado_id, tornado_exposure$ZCTA)), ]
R <- list(rows = nrow(Y), full_prop_equals_modeled_area_prop = isTRUE(all.equal(Y$full_prop, chk$modeled_area_prop, tolerance = 1e-9)), rows_land_over_full = c(over_1pct = sum(abs(Y$rel) > .01), over_10pct = sum(abs(Y$rel) > .1), over_50pct = sum(abs(Y$rel) > .5)),
  land_larger = sum(Y$rel > .01), land_smaller = sum(Y$rel < -.01), land_prop_above_1 = sum(Y$land_prop > 1), land_prop_above_1_max = max(Y$land_prop), rel_quantiles = quantile(Y$rel, c(.01, .1, .5, .9, .99), names = FALSE), by_vint = Y %>% group_by(vint) %>% summarise(rows = n(), over_1 = sum(abs(rel) > .01), over_10 = sum(abs(rel) > .1), over_50 = sum(abs(rel) > .5)), data = Y)
saveRDS(R, qa_out("63c_land_share_effect.rds")); print(R[setdiff(names(R), "data")])
