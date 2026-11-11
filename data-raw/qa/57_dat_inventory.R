# Run from the package root after 53_dat_full_fetch.R and 54b:  caffeinate -i Rscript data-raw/qa/57_dat_inventory.R     Saves data-raw/qa/out/dat_inventory.rds
# Inventory of the NWS Damage Assessment Toolkit service: layers, fields, counts, by year since 2007, how many SPC tornadoes have any DAT feature near their path on a date within a day (several distances),
# how often event_id is populated and links the layers, whether DAT event_id is the NCEI Storm Events event id, and the time instants (SPC time in CST converted to UTC against the DAT timestamps).
suppressMessages({library(sf); library(dplyr); library(jsonlite)}); sf_use_s2(FALSE); options(width = 220); source("data-raw/qa/helpers.R")
lg <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S "), ...); cat(m, "\n"); cat(m, "\n", file = qa_out("57.log"), append = TRUE) }
svc <- "https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer"; R <- list()
lay <- lapply(0:2, function(i) fromJSON(paste0(svc, "/", i, "?f=json"), simplifyVector = FALSE)); R$layers <- do.call(rbind, lapply(lay, function(l) data.frame(id = l$id, name = l$name, geometry = l$geometryType, spatial_reference = l$extent$spatialReference$wkid, fields = length(l$fields), max_record_count = l$maxRecordCount)))
R$fields <- lapply(lay, function(l) data.frame(name = vapply(l$fields, `[[`, "", "name"), type = sub("esriFieldType", "", vapply(l$fields, `[[`, "", "type")), length = vapply(l$fields, function(f) if (is.null(f$length)) NA_integer_ else as.integer(f$length), 1L)))
L0 <- readRDS(qa_out("dat_full_layer0.rds")); L1 <- readRDS(qa_out("dat_full_layer1.rds")); L2 <- readRDS(qa_out("dat_full_layer2.rds")); R$counts_all <- c(points = nrow(L0), lines = nrow(L1), polygons = nrow(L2))
dt <- function(x) as.POSIXct(as.numeric(x) / 1000, origin = "1970-01-01", tz = "UTC"); for (nm in c("L0", "L1", "L2")) { x <- get(nm); x$sd <- dt(x$stormdate); assign(nm, x) }
yrs <- function(x) as.integer(format(x$sd, "%Y")); R$by_year <- data.frame(year = 2007:2026, lines = as.integer(table(factor(yrs(L1), 2007:2026))), polygons = as.integer(table(factor(yrs(L2), 2007:2026))), points = as.integer(table(factor(yrs(L0), 2007:2026))))
R$null_stormdate <- c(points = sum(is.na(L0$sd)), lines = sum(is.na(L1$sd)), polygons = sum(is.na(L2$sd))); R$before_2007 <- c(points = sum(yrs(L0) < 2007, na.rm = TRUE), lines = sum(yrs(L1) < 2007, na.rm = TRUE), polygons = sum(yrs(L2) < 2007, na.rm = TRUE))
lg("layers loaded")
# ---- SPC paths ------------------------------------------------------------------------------------------------------------------------------
load("data/tornado_tracks.rda"); tt <- tornado_tracks; yr <- as.integer(substr(tt$tornado_id, 1, 4)); T7 <- tt[yr >= 2007, ]; T7$d <- as.Date(T7$date)
co <- lapply(st_geometry(T7), function(g) { m <- unclass(g); if (is.matrix(m)) c(m[1, ], m[nrow(m), ]) else c(m, m) }); co <- do.call(rbind, co)
pj <- function(lon, lat) st_coordinates(st_transform(st_sfc(lapply(seq_along(lon), function(i) st_point(c(lon[i], lat[i]))), crs = 4326), 5070)); s5 <- pj(co[, 1], co[, 2]); e5 <- pj(co[, 3], co[, 4])
pdist <- function(px, py, ax, ay, bx, by) { dx <- bx - ax; dy <- by - ay; L2 <- dx^2 + dy^2; t <- ifelse(L2 > 0, pmax(0, pmin(1, ((px - ax) * dx + (py - ay) * dy) / L2)), 0); sqrt((px - (ax + t * dx))^2 + (py - (ay + t * dy))^2) }
# DAT features within +-1 day: points by exact vector arithmetic; lines and polygons by bounding boxes first, then exact distances
within <- function(X, d, kind) { X <- X[!is.na(X$sd) & X$sd >= as.POSIXct("2007-01-01", tz = "UTC") & !st_is_empty(X), ]; X$d <- as.Date(X$sd); X5 <- st_transform(X, 5070)
  cand <- bind_rows(lapply(-1:1, function(o) merge(transform(data.frame(f = seq_len(nrow(X)), d = X$d), d = d + o), data.frame(k = seq_len(nrow(T7)), d = T7$d), by = "d")[, c("f", "k")]))
  if (kind == "point") { xy <- st_coordinates(X5); cand$dist <- pdist(xy[cand$f, 1], xy[cand$f, 2], s5[cand$k, 1], s5[cand$k, 2], e5[cand$k, 1], e5[cand$k, 2]) } else {
    bb <- t(vapply(st_geometry(X5), function(g) as.numeric(st_bbox(g)), numeric(4))); lx <- pmin(s5[, 1], e5[, 1]); hx <- pmax(s5[, 1], e5[, 1]); ly <- pmin(s5[, 2], e5[, 2]); hy <- pmax(s5[, 2], e5[, 2])
    gap <- pmax(0, bb[cand$f, 1] - hx[cand$k], lx[cand$k] - bb[cand$f, 3]); gap2 <- pmax(0, bb[cand$f, 2] - hy[cand$k], ly[cand$k] - bb[cand$f, 4]); cand <- cand[which(sqrt(gap^2 + gap2^2) <= 10000), ]
    spc <- st_sfc(lapply(seq_len(nrow(cand)), function(r) { k <- cand$k[r]; if (all(s5[k, ] == e5[k, ])) st_point(s5[k, ]) else st_linestring(rbind(s5[k, ], e5[k, ])) }), crs = 5070); cand$dist <- as.numeric(st_distance(spc, st_geometry(X5)[cand$f], by_element = TRUE)) }
  cand %>% group_by(k) %>% summarise(dmin = min(dist) / 1000, .groups = "drop") }
dd <- c(0.1, 0.5, 1, 2, 5, 10); res <- list(); k_any <- list()
for (kind in c("point", "line", "polygon")) { X <- list(point = L0, line = L1, polygon = L2)[[kind]]; w <- within(X, d, kind); k_any[[kind]] <- w; lg("within ", kind, ": ", nrow(w), " tornadoes with a candidate within 10 km") }
R$spc_with_dat <- do.call(rbind, lapply(dd, function(d) { ks <- lapply(k_any, function(w) w$k[w$dmin <= d]); data.frame(distance_km = d, with_point = length(ks$point), with_line = length(ks$line), with_polygon = length(ks$polygon), with_any = length(unique(unlist(ks))), with_line_or_polygon = length(unique(c(ks$line, ks$polygon))), spc_tornadoes = nrow(T7)) }))
R$spc_with_dat_by_year <- do.call(rbind, lapply(2007:2025, function(y) { k <- which(as.integer(format(T7$d, "%Y")) == y); data.frame(year = y, spc = length(k), any_within_1km = length(intersect(k, unique(unlist(lapply(k_any, function(w) w$k[w$dmin <= 1]))))), any_within_10km = length(intersect(k, unique(unlist(lapply(k_any, function(w) w$k[w$dmin <= 10])))))) }))
lg("distances done")
# ---- event_id ------------------------------------------------------------------------------------------------------------------------------
ev <- function(x) { e <- trimws(as.character(x$event_id)); e[is.na(e)] <- ""; e }; e0 <- ev(L0); e1 <- ev(L1); e2 <- ev(L2)
R$event_id_populated <- c(points = mean(nzchar(e0)), lines = mean(nzchar(e1)), polygons = mean(nzchar(e2))) * 100; R$event_id_distinct <- c(points = length(unique(e0[nzchar(e0)])), lines = length(unique(e1[nzchar(e1)])), polygons = length(unique(e2[nzchar(e2)])))
R$event_id_numeric_share <- c(points = mean(grepl("^[0-9]+$", e0[nzchar(e0)])), lines = mean(grepl("^[0-9]+$", e1[nzchar(e1)])), polygons = mean(grepl("^[0-9]+$", e2[nzchar(e2)]))) * 100
R$event_id_examples <- list(lines = head(sample(unique(e1[nzchar(e1)]), 20), 20), points = head(sample(unique(e0[nzchar(e0)]), 20), 20), polygons = head(sample(unique(e2[nzchar(e2)]), 20), 20))
R$link <- data.frame(lines_with_id = sum(nzchar(e1)), lines_id_in_polygons = sum(nzchar(e1) & e1 %in% e2), lines_id_in_points = sum(nzchar(e1) & e1 %in% e0), lines_id_in_both = sum(nzchar(e1) & e1 %in% e2 & e1 %in% e0),
  polygons_with_id = sum(nzchar(e2)), polygons_id_in_lines = sum(nzchar(e2) & e2 %in% e1), points_with_id = sum(nzchar(e0)), points_id_in_lines = sum(nzchar(e0) & e0 %in% e1))
R$event_id_duplicated_in_lines <- sum(duplicated(e1[nzchar(e1)])); R$event_id_lines_per_id <- table(pmin(table(e1[nzchar(e1)]), 5))
# DAT event_id against the NCEI Storm Events event id (details files 2007 to 2025)
nc <- readRDS(qa_out("ncei_comparison.rds")); N <- nc$N; Nid <- as.character(N$EVENT_ID)
ids <- unique(c(e0[nzchar(e0)], e1[nzchar(e1)], e2[nzchar(e2)])); R$ncei_match <- data.frame(dat_event_ids = length(ids), numeric = sum(grepl("^[0-9]+$", ids)), equal_to_a_tornado_event_id_of_NCEI = sum(ids %in% Nid))
l7 <- L1[nzchar(e1) & e1 %in% Nid, ]; if (nrow(l7)) { j <- N[match(as.character(l7$event_id), Nid), ]; ll <- do.call(rbind, lapply(st_geometry(l7), function(g) { m <- unclass(g); c(m[1, ], m[nrow(m), ]) })); hav <- function(lat1, lon1, lat2, lon2) { r <- pi / 180; a <- sin((lat2 - lat1) * r / 2)^2 + cos(lat1 * r) * cos(lat2 * r) * sin((lon2 - lon1) * r / 2)^2; 12742 * asin(sqrt(a)) }
  R$ncei_match_geo <- data.frame(lines_with_ncei_id = nrow(l7), start_within_1km_of_NCEI_begin = sum(hav(ll[, 2], ll[, 1], j$BEGIN_LAT, j$BEGIN_LON) <= 1, na.rm = TRUE), same_date = sum(as.Date(l7$sd) == as.Date(j$bt) | abs(as.numeric(l7$sd - j$utc)) < 86400, na.rm = TRUE)) }
R$ncei_event_id_numeric_range <- range(as.numeric(Nid)); R$dat_numeric_id_range <- if (any(grepl("^[0-9]+$", ids))) range(as.numeric(ids[grepl("^[0-9]+$", ids)])) else NA
# ---- time instants ------------------------------------------------------------------------------------------------------------------------
sm <- readRDS(qa_out("dat_lines_live.rds")); load("data/survey_matches.rda"); P <- survey_matches[survey_matches$status != "no_pair", ]; raw <- read.csv(qa_spc_csv(), stringsAsFactors = FALSE); raw <- raw[raw$sg == 1 & raw$yr >= 2007, ]; raw$id <- paste(raw$yr, raw$om, sep = "_"); raw$utc <- as.POSIXct(paste(raw$date, raw$time), tz = "UTC") + 6 * 3600
m1 <- match(P$survey_line_id, L1$objectid); m2 <- match(P$tornado_id, raw$id); ok <- !is.na(m1) & !is.na(m2); dsd <- as.numeric(difftime(L1$sd[m1[ok]], raw$utc[m2[ok]], units = "hours")); L1$st <- dt(L1$starttime); dst <- as.numeric(difftime(L1$st[m1[ok]], raw$utc[m2[ok]], units = "hours")); L1$et <- dt(L1$endtime)
q <- function(x) quantile(x, c(.01, .05, .25, .5, .75, .95, .99), na.rm = TRUE); R$time <- list(pairs = sum(ok), stormdate_minus_spc_hours = q(dsd), starttime_minus_spc_hours = q(dst), within_5min_stormdate = mean(abs(dsd) <= 5 / 60, na.rm = TRUE) * 100, within_1h_stormdate = mean(abs(dsd) <= 1, na.rm = TRUE) * 100, within_5min_starttime = mean(abs(dst) <= 5 / 60, na.rm = TRUE) * 100,
  within_1h_starttime = mean(abs(dst) <= 1, na.rm = TRUE) * 100, stormdate_equals_starttime = mean(L1$sd == L1$st, na.rm = TRUE) * 100, lines_with_starttime = mean(!is.na(L1$st)) * 100, lines_with_endtime = mean(!is.na(L1$et)) * 100)
# if timestamps replaced the one-day window: how many SPC tornadoes of the same UTC day would be candidates for a line, against the day window
Lc <- L1[!is.na(L1$sd) & L1$sd >= as.POSIXct("2007-01-01", tz = "UTC") & L1$sd < as.POSIXct("2026-01-01", tz = "UTC"), ]; rt <- raw$utc; cnt <- function(hh) mean(vapply(seq_len(min(nrow(Lc), 3000)), function(i) sum(abs(as.numeric(difftime(rt, Lc$sd[i], units = "hours"))) <= hh), 1))
R$time$mean_candidates_per_line <- c(day_window = mean(vapply(seq_len(min(nrow(Lc), 3000)), function(i) sum(abs(as.numeric(as.Date(raw$utc) - as.Date(Lc$sd[i]))) <= 1), 1)), `1h` = cnt(1), `3h` = cnt(3), `6h` = cnt(6))
saveRDS(R, qa_out("dat_inventory.rds")); lg("done 57"); for (nm in names(R)) { cat("\n##", nm, "\n"); print(R[[nm]]) }
