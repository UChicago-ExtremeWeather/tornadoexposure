# Run from the package root:  caffeinate -i Rscript data-raw/qa/55_area_basis.R    (progress: data-raw/qa/out/55.log)
# Recomputes every tornado-ZCTA intersection of the published modeled paths with the full TIGER/Line ZCTA polygons, and keeps the pieces needed to compare the area bases:
# intersection / ALAND (land only, the published area_prop_affected before the cap) and intersection / area of the full ZCTA polygon (land and water). Saves data-raw/qa/out/area_basis_pairs.rds.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220, tigris_use_cache = TRUE)
source("data-raw/qa/helpers.R"); source("R/path_polygon.R"); load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda")
lg <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S "), ...); cat(m, "\n"); cat(m, "\n", file = qa_out("55.log"), append = TRUE) }
tt <- tornado_tracks; yr <- as.integer(substr(tt$tornado_id, 1, 4)); poly <- .path_polygon(tt, tt$wid_yd, tt$len_mi, tt$track_type); P <- st_sf(tornado_id = tt$tornado_id, track_type = tt$track_type, geometry = poly)
vint <- ifelse(yr < 2010, 2000L, ifelse(yr < 2020, 2010L, 2020L)); out <- list()
for (v in c(2000, 2010, 2020)) { sfx <- substr(v, 3, 4); z <- tigris::zctas(year = v, progress_bar = FALSE); z <- z[, c(paste0("ZCTA5CE", sfx), paste0("ALAND", sfx), paste0("AWATER", sfx))]; names(z)[1:3] <- c("ZCTA", "ALAND", "AWATER"); z$ALAND <- as.numeric(z$ALAND); z$AWATER <- as.numeric(z$AWATER)
  z <- st_make_valid(st_transform(z, 5070)); z$zcta_poly_m2 <- as.numeric(st_area(z)); lg("vintage ", v, ": ", nrow(z), " ZCTAs; paths ", sum(vint == v))
  x <- suppressWarnings(st_intersection(P[vint == v, "tornado_id"], z)); gt <- as.character(st_geometry_type(x)); lg("intersection pieces ", nrow(x), " by type: ", paste(names(table(gt)), table(gt), collapse = ", ")); x <- st_collection_extract(x, "POLYGON"); x$intersection_m2 <- as.numeric(st_area(x))
  out[[as.character(v)]] <- st_drop_geometry(x) %>% group_by(tornado_id, ZCTA, ALAND, AWATER, zcta_poly_m2) %>% summarise(intersection_m2 = sum(intersection_m2), .groups = "drop") %>% mutate(vintage = v); lg("pieces ", nrow(out[[as.character(v)]])) }
A <- bind_rows(out); lg("pieces before dropping exact-zero intersection areas: ", nrow(A), "; exact zero: ", sum(A$intersection_m2 <= 0)); A <- A[A$intersection_m2 > 0, ]; A$track_type <- tt$track_type[match(A$tornado_id, tt$tornado_id)]
pub <- tornado_exposure[, c("tornado_id", "ZCTA", "area_prop_affected")]; A <- merge(A, pub, by = c("tornado_id", "ZCTA"), all = TRUE); saveRDS(A, qa_out("area_basis_pairs.rds"))
a <- A[!is.na(A$intersection_m2), ]; a$land <- a$intersection_m2 / a$ALAND; a$full <- a$intersection_m2 / a$zcta_poly_m2; a$water_share <- a$AWATER / (a$ALAND + a$AWATER)
lg("rows recomputed ", nrow(a), "; published ", nrow(pub), "; recomputed rows not in published: ", sum(is.na(a$area_prop_affected)), "; published not recomputed: ", sum(is.na(A$intersection_m2)))
lg("max abs difference to the published value after capping at 1: ", signif(max(abs(pmin(a$land, 1) - a$area_prop_affected), na.rm = TRUE), 3))
lg("rows with intersection / ALAND above 1: ", sum(a$land > 1), "; above 1.01: ", sum(a$land > 1.01), "; above 2: ", sum(a$land > 2), "; max ", signif(max(a$land), 4)); lg("ALAND == 0 rows: ", sum(a$ALAND == 0))
lg("intersection / full polygon above 1 (impossible): ", sum(a$full > 1 + 1e-9))
