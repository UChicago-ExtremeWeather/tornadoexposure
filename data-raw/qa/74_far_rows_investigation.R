# Run from the package root, after data-raw/dat/build_dat_exposure.R:  Rscript data-raw/qa/74_far_rows_investigation.R
# What produces the DAT-only rows of tornado_exposure (spc_exposed FALSE and dat_exposed TRUE) that lie more than 5 km from the SPC line (boundary_dist_km; "far", 5 km is a descriptive value, not a recommendation),
# compared with the DAT-only rows within 5 km ("near")? For every such row, the footprint polygons of the tornado (EF0 to EF5 polygons touched by a linked line, as in data-raw/dat/exposure_functions.R) that
# cover land in the ZCTA (positive area inside the land-only ZCTA shape of the boundary year) are listed with: efscale, area (km2, EPSG:5070), extent (diagonal of the bounding box, km), the number of ZCTAs of the
# boundary year whose land the polygon covers, the number of linked lines that touch it (line_share_in_polygon above 0) with the largest line_share_in_polygon, the smallest one-sided link distance among the linked lines
# that touch it, and the smallest distance (km) between the polygon and the SPC line of the tornado. Each row and each tornado is then assigned to a cause:
#   (a) a polygon that covers land in the ZCTA is touched by a linked line whose one-sided distance (tornado_dat_link) is at most 5 km: the polygon reaches the ZCTA from a line that lies near the SPC line;
#   (b) every such polygon is touched only by linked lines whose one-sided distance is above 5 km: the polygon comes from a distant link;
# a row that is neither is reported as (c). The tornado-level split uses dat_link_dist_km (the largest one-sided distance among the tornado's linked lines).
# Output: data-raw/qa/out/74_far_rows.rds and rows far_cause_* in data-raw/readme/numbers.csv.
source("data-raw/qa/helpers.R"); source("data-raw/pipeline_functions.R"); source("data-raw/land_functions.R"); source("data-raw/dat/exposure_functions.R")
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE)
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f)
ex <- tornado_exposure; d <- ex[!ex$spc_exposed & ex$dat_exposed %in% TRUE, c("tornado_id", "ZCTA", "year", "boundary_dist_km", "dat_link_dist_km")]
d$vint <- vint_of(d$year); d$far <- d$boundary_dist_km > 5
F <- footprint_pairs(tornado_dat_link, dat_polygon_line_link, dat_polygons)$used
tch <- merge(tornado_dat_link[, c("tornado_id", "dat_line_id", "one_sided_dist_km")], dat_polygon_line_link[dat_polygon_line_link$line_share_in_polygon > 0, c("dat_line_id", "dat_polygon_id", "line_share_in_polygon")], by = "dat_line_id")
ids <- unique(F$dat_polygon_id[F$tornado_id %in% d$tornado_id]); pol <- dat_polygons[match(ids, dat_polygons$objectid), ]
P5 <- st_transform(st_make_valid(st_geometry(pol)), 5070); names(P5) <- ids
ext_km <- vapply(seq_along(P5), function(i) { b <- st_bbox(P5[[i]]); sqrt((b[["xmax"]] - b[["xmin"]])^2 + (b[["ymax"]] - b[["ymin"]])^2) / 1000 }, 0)
pinfo <- data.frame(dat_polygon_id = ids, efscale = pol$efscale, area_km2 = as.numeric(st_area(P5)) / 1e6, extent_km = ext_km, stringsAsFactors = FALSE)
trk <- st_transform(tornado_tracks[match(unique(d$tornado_id), tornado_tracks$tornado_id), ], 5070); trk_g <- st_geometry(trk); names(trk_g) <- trk$tornado_id
res <- list()
for (v in c(2000L, 2010L, 2020L)) {
  dv <- d[d$vint == v, ]; if (!nrow(dv)) next
  zl <- zcta_land(v); L <- zl$land; names(L) <- zl$d$ZCTA
  pid_v <- unique(F$dat_polygon_id[F$tornado_id %in% dv$tornado_id]); hits <- st_intersects(P5[as.character(pid_v)], L)
  ov <- do.call(rbind, lapply(seq_along(pid_v), function(i) { h <- hits[[i]]; if (!length(h)) return(NULL)
    a <- vapply(h, function(k) { x <- suppressWarnings(st_intersection(P5[[as.character(pid_v[i])]], L[[k]])); if (length(x) == 0) 0 else sum(as.numeric(st_area(st_collection_extract(st_sfc(x, crs = 5070), "POLYGON")))) }, 0)
    data.frame(dat_polygon_id = pid_v[i], ZCTA = names(L)[h], overlap_m2 = a, stringsAsFactors = FALSE) }))
  ov <- ov[ov$overlap_m2 > 0, ]; nz <- table(ov$dat_polygon_id)
  for (i in seq_len(nrow(dv))) {
    fp <- F[F$tornado_id == dv$tornado_id[i], ]; cov <- fp[fp$dat_polygon_id %in% ov$dat_polygon_id[ov$ZCTA == dv$ZCTA[i]], ]
    if (!nrow(cov)) { res[[length(res) + 1]] <- data.frame(dv[i, ], dat_polygon_id = NA_character_); next }
    for (p in unique(cov$dat_polygon_id)) {
      tc <- tch[tch$tornado_id == dv$tornado_id[i] & tch$dat_polygon_id == p, ]
      res[[length(res) + 1]] <- data.frame(dv[i, ], dat_polygon_id = p, n_zcta = as.integer(nz[[as.character(p)]]), n_lines = nrow(tc), max_line_share = max(tc$line_share_in_polygon), min_link_km = min(tc$one_sided_dist_km),
        spc_to_polygon_km = as.numeric(st_distance(trk_g[[dv$tornado_id[i]]], P5[[as.character(p)]])) / 1000, stringsAsFactors = FALSE)
    }
  }
  rm(zl, L); gc()
}
R <- bind_rows(res); R <- left_join(R, pinfo, by = "dat_polygon_id")
rows <- R %>% group_by(tornado_id, ZCTA, far, boundary_dist_km, dat_link_dist_km) %>% summarise(n_polygons = sum(!is.na(dat_polygon_id)), cause_a = any(min_link_km <= 5, na.rm = TRUE), cause_b = n_polygons > 0 & all(min_link_km > 5, na.rm = TRUE), max_extent_km = suppressWarnings(max(extent_km, na.rm = TRUE)), max_area_km2 = suppressWarnings(max(area_km2, na.rm = TRUE)), .groups = "drop")
rows$cause <- ifelse(rows$n_polygons == 0, "c", ifelse(rows$cause_a, "a", "b"))
torn <- rows %>% group_by(tornado_id, far = tornado_id %in% rows$tornado_id[rows$far]) %>% summarise(rows_far = sum(far), rows = n(), link_km = max(dat_link_dist_km), .groups = "drop")
saveRDS(list(polygons = R, rows = rows), qa_out("74_far_rows.rds"))
q <- function(x) quantile(x, c(0, .25, .5, .75, .9, 1), names = TRUE)
cat("rows:", nrow(rows), " no covering polygon:", sum(rows$n_polygons == 0), "\n"); print(table(far = rows$far, cause = rows$cause))
cat("\nfar rows by tornado-level link distance (dat_link_dist_km above 5 km):\n"); print(table(link_above_5 = rows$dat_link_dist_km[rows$far] > 5, cause = rows$cause[rows$far]))
ft <- unique(rows[rows$far, c("tornado_id", "dat_link_dist_km")]); cat("far tornadoes:", nrow(ft), " link <= 5:", sum(ft$dat_link_dist_km <= 5), " link > 5:", sum(ft$dat_link_dist_km > 5), "\n")
tc <- rows[rows$far, ] %>% group_by(tornado_id) %>% summarise(a = any(cause == "a"), b = any(cause == "b"), c = any(cause == "c"), .groups = "drop"); cat("far tornadoes with at least one row of cause a / b / c:", sum(tc$a), sum(tc$b), sum(tc$c), "; only b:", sum(tc$b & !tc$a), "\n")
pf <- R[!is.na(R$dat_polygon_id) & R$far, ]; pn <- R[!is.na(R$dat_polygon_id) & !R$far, ]; pf <- pf[!duplicated(pf$dat_polygon_id), ]; pn <- pn[!duplicated(pn$dat_polygon_id), ]
for (nm in c("extent_km", "area_km2", "n_zcta", "n_lines", "max_line_share", "spc_to_polygon_km")) { cat("\n", nm, " unique polygons far (", nrow(pf), ") / near (", nrow(pn), ")\n", sep = ""); print(rbind(far = q(pf[[nm]]), near = q(pn[[nm]]))) }
cat("\nrow level: largest polygon extent (km) / area (km2) per row\n"); print(rbind(far_extent = q(rows$max_extent_km[rows$far]), near_extent = q(rows$max_extent_km[!rows$far]), far_area = q(rows$max_area_km2[rows$far]), near_area = q(rows$max_area_km2[!rows$far])))
cat("\nefscale of the polygons far / near:\n"); print(table(pf$efscale)); print(table(pn$efscale))
ex3 <- rows[rows$far, ] %>% group_by(tornado_id) %>% summarise(rows = n(), far_max_km = max(boundary_dist_km), link_km = max(dat_link_dist_km), .groups = "drop") %>% arrange(desc(far_max_km)) %>% head(3)
cat("\nthe three farthest tornadoes:\n"); print(as.data.frame(ex3))
big <- pf[order(-pf$extent_km), c("tornado_id", "ZCTA", "dat_polygon_id", "efscale", "area_km2", "extent_km", "n_zcta", "n_lines", "max_line_share", "min_link_km", "spc_to_polygon_km")] %>% head(3)
cat("\nthe three largest far polygons by extent:\n"); print(as.data.frame(big), digits = 5)
big2 <- pf[order(-pf$area_km2), c("tornado_id", "ZCTA", "dat_polygon_id", "efscale", "area_km2", "extent_km", "n_zcta", "n_lines", "max_line_share", "min_link_km", "spc_to_polygon_km")] %>% head(3)
cat("\nthe three largest far polygons by area:\n"); print(as.data.frame(big2), digits = 5)
fb <- rows[rows$far & rows$cause == "b", ]; fa <- rows[rows$far & rows$cause == "a", ]
nm <- c(far_cause_a_rows = nrow(fa), far_cause_a_tornadoes = length(unique(fa$tornado_id)), far_cause_b_rows = nrow(fb), far_cause_b_tornadoes = length(unique(fb$tornado_id)), far_cause_c_rows = sum(rows$far & rows$cause == "c"),
        far_cause_b_link_min_km = min(fb$dat_link_dist_km), far_cause_b_link_max_km = max(fb$dat_link_dist_km),
        far_poly_n = nrow(pf), near_poly_n = nrow(pn), far_poly_extent_median_km = median(pf$extent_km), near_poly_extent_median_km = median(pn$extent_km),
        far_poly_area_median_km2 = median(pf$area_km2), near_poly_area_median_km2 = median(pn$area_km2), far_poly_extent_max_km = max(pf$extent_km), far_poly_area_max_km2 = max(pf$area_km2), far_poly_nzcta_max = max(pf$n_zcta))
f <- "data-raw/readme/numbers.csv"; n <- read.csv(f, stringsAsFactors = FALSE); n <- n[!n$name %in% names(nm), ]
write.csv(rbind(n, data.frame(name = names(nm), value = unname(nm), source = "74")), f, row.names = FALSE)
