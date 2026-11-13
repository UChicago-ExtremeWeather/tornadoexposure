# Run from the package root:  caffeinate -i Rscript data-raw/qa/64_dat_exposure_design.R      Saves data-raw/qa/out/dat_exposure_design.rds
# Counts behind the proposed DAT exposure tables (nothing is shipped). Inputs: the full DAT fetch (53_dat_full_fetch.R), the full TIGER/Line ZCTA files of the boundary years (2010 for polygons dated 2007 to 2019,
# 2020 for polygons dated 2020 on or without a date) and the 2020 cartographic tract and block-group files (500k; used for every polygon, so the tract and block-group counts are estimates).
# Rows = pairs of a DAT polygon and a unit whose intersection has a positive area in EPSG:5070. Table sizes are measured on a table with the real number of rows and the real data types (xz-compressed .rda).
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); source("data-raw/qa/helpers.R"); R <- list()
cache <- rappdirs::user_cache_dir("tigris")
P <- readRDS(qa_out("dat_full_layer2.rds")); Q <- readRDS(qa_out("dat_full_layer0.rds")); L <- readRDS(qa_out("dat_full_layer1.rds"))
P$id <- P$objectid; P$ms <- as.numeric(P$stormdate); P$yr <- as.integer(format(as.POSIXct(P$ms / 1000, origin = "1970-01-01", tz = "UTC"), "%Y")); Q$ms <- as.numeric(Q$stormdate); Q$yr <- as.integer(format(as.POSIXct(Q$ms / 1000, origin = "1970-01-01", tz = "UTC"), "%Y"))
R$counts <- c(points = nrow(Q), lines = nrow(L), polygons = nrow(P), polygons_empty = sum(st_is_empty(P)), points_empty = sum(st_is_empty(Q)), polygons_no_date = sum(is.na(P$ms)), points_no_date = sum(is.na(Q$ms)))
P <- P[!st_is_empty(P), ]; inv <- sum(!st_is_valid(P)); R$polygons_invalid <- inv; Pv <- st_make_valid(P); P5 <- st_transform(Pv, 5070); P$area_m2 <- as.numeric(st_area(P5)); P5$id <- P$id
vint <- ifelse(!is.na(P$yr) & P$yr < 2020, 2010L, 2020L); P5$vint <- vint
zc <- function(f, col) { z <- st_read(file.path(cache, paste0(f, ".shp")), quiet = TRUE); z <- st_sf(unit = as.character(z[[col]]), geometry = st_geometry(z)); st_transform(st_make_valid(z), 5070) }
units <- list(zcta2010 = zc("tl_2010_us_zcta510", "ZCTA5CE10"), zcta2020 = zc("tl_2020_us_zcta520", "ZCTA5CE20"))
for (nm in c("tract", "bg")) { f <- file.path("data-raw/qa/cache/tractbg", sprintf("cb_2020_us_%s_500k.zip", nm)); z <- st_read(paste0("/vsizip/", f), quiet = TRUE); units[[nm]] <- st_transform(st_make_valid(st_sf(unit = z$GEOID, geometry = st_geometry(z))), 5070) }
cnt <- function(zu, pol) { h <- st_intersects(pol, zu); idx <- which(lengths(h) > 0); out <- list()
  for (ch in split(idx, ceiling(seq_along(idx) / 500))) { x <- suppressWarnings(st_intersection(pol[ch, "id"], zu[unique(unlist(h[ch])), "unit"])); x <- st_collection_extract(x, "POLYGON"); x$a <- as.numeric(st_area(x)); out[[length(out) + 1]] <- st_drop_geometry(x) }
  x <- bind_rows(out); x <- x %>% group_by(id, unit) %>% summarise(a = sum(a), .groups = "drop"); x[x$a > 0, ] }
rows <- list(); zp <- list()
for (v in c(2010L, 2020L)) { x <- cnt(units[[paste0("zcta", v)]], P5[P5$vint == v, ]); rows[[paste0("zcta", v)]] <- x }
rows$zcta <- bind_rows(rows$zcta2010, rows$zcta2020); rows$tract <- cnt(units$tract, P5); rows$bg <- cnt(units$bg, P5)
R$polygon_unit_rows <- c(zcta = nrow(rows$zcta), tract = nrow(rows$tract), block_group = nrow(rows$bg)); R$polygons_in_no_zcta <- sum(!P$id %in% rows$zcta$id)
R$units_hit <- c(zcta = length(unique(rows$zcta$unit)), tract = length(unique(rows$tract$unit)), block_group = length(unique(rows$bg$unit)))
R$rows_per_polygon <- sapply(list(zcta = rows$zcta, tract = rows$tract, block_group = rows$bg), function(x) quantile(table(x$id), c(.5, .9, 1)))
# overlap of the polygons with each other: sum of polygon areas against the area of their union (all polygons, any date)
R$sum_polygon_area_km2 <- sum(P$area_m2) / 1e6; R$union_area_km2 <- as.numeric(st_area(st_union(st_geometry(P5)))) / 1e6
# nesting: pairs of polygons dated within one day whose intersection has a positive area
d <- P5[!is.na(P$ms), ]; dd <- P$ms[!is.na(P$ms)]; h <- st_intersects(d, d); pairs <- do.call(rbind, lapply(seq_along(h), function(i) { j <- h[[i]][h[[i]] > i]; j <- j[abs(dd[j] - dd[i]) <= 86400000]; if (length(j)) cbind(i, j) else NULL }))
R$polygon_pairs_candidate_same_window <- if (is.null(pairs)) 0 else nrow(pairs)
if (!is.null(pairs)) { ar <- vapply(seq_len(nrow(pairs)), function(r) tryCatch(as.numeric(st_area(st_intersection(st_geometry(d)[pairs[r, 1]], st_geometry(d)[pairs[r, 2]]))), error = function(e) NA_real_), 0)
  R$polygon_pairs_positive_overlap <- sum(ar > 0, na.rm = TRUE); R$polygons_overlapping_another <- length(unique(c(pairs[ar > 0, 1], pairs[ar > 0, 2]))) }
# points: unit counts by efscale
Q <- Q[!st_is_empty(Q), ]; Q$efs <- ifelse(is.na(Q$efscale), "(missing)", Q$efscale); R$points_efscale <- sort(table(Q$efs), decreasing = TRUE)
Qa <- st_transform(Q, 5070); Qa$vint <- ifelse(!is.na(Q$yr) & Q$yr < 2020, 2010L, 2020L)
ptu <- function(zu, pts) { j <- st_intersects(pts, zu); data.frame(pid = rep(seq_along(j), lengths(j)), unit = zu$unit[unlist(j)]) }
pz <- bind_rows(lapply(c(2010L, 2020L), function(v) { s <- which(Qa$vint == v); x <- ptu(units[[paste0("zcta", v)]], Qa[s, ]); x$pid <- s[x$pid]; x }))
pt <- ptu(units$tract, Qa); pb <- ptu(units$bg, Qa)
R$points_in_no_unit <- c(zcta = nrow(Qa) - length(unique(pz$pid)), tract = nrow(Qa) - length(unique(pt$pid)), block_group = nrow(Qa) - length(unique(pb$pid)))
R$points_in_more_than_one <- c(zcta = sum(duplicated(pz$pid)), tract = sum(duplicated(pt$pid)), block_group = sum(duplicated(pb$pid)))
cr <- function(p) { p$efs <- Q$efs[p$pid]; nrow(unique(p[c("unit", "efs")])) }
R$point_unit_efscale_rows <- c(zcta = cr(pz), tract = cr(pt), block_group = cr(pb))
# points inside a damage polygon (any date), and within the polygons of the same day window
hp <- st_intersects(Qa, st_geometry(P5)); R$points_in_any_polygon <- sum(lengths(hp) > 0)
saveRDS(R, qa_out("dat_exposure_design.rds"))
# sizes: tables with the real number of rows
sz <- function(df) { f <- tempfile(fileext = ".rda"); save(df, file = f, compress = "xz"); file.size(f) / 1e6 }
mk <- function(n, k, ch = 0) { d <- data.frame(id = sample.int(2e7, n, TRUE), unit = sprintf("%011.0f", floor(runif(n) * 1e10)), stringsAsFactors = FALSE); for (j in seq_len(k)) d[[paste0("v", j)]] <- runif(n) * 1e5; d }
R$size_mb <- c(zcta_polygon_rows = sz(mk(nrow(rows$zcta), 5)), tract_polygon_rows = sz(mk(nrow(rows$tract), 5)), block_group_polygon_rows = sz(mk(nrow(rows$bg), 5)),
               zcta_point_counts = sz(mk(R$point_unit_efscale_rows[["zcta"]], 1)), tract_point_counts = sz(mk(R$point_unit_efscale_rows[["tract"]], 1)), block_group_point_counts = sz(mk(R$point_unit_efscale_rows[["block_group"]], 1)))
saveRDS(R, qa_out("dat_exposure_design.rds")); print(R)
