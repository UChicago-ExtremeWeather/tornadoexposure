# Adds the DAT columns to tornado_exposure and builds dat_exposure_tract and dat_exposure_blockgroup. Run from the package root after
# data-raw/process_tracks.R (the SPC rows), data-raw/add_centroids.R and data-raw/dat/build_dat.R:
#   caffeinate -i Rscript data-raw/dat/build_dat_exposure.R
# Rules and definitions: data-raw/dat/exposure_functions.R (polygon rule, zones by the highest rating, land-only shapes, residents).
# This script always recomputes every DAT column and every DAT-only row from the current DAT datasets, so the DAT refresh replaces them whole; the SPC rows
# (spc_exposed == TRUE) are never changed here. Resumable: the block pass of each boundary year and state is saved in data-raw/dat/fetch/block_pass/.
# Environment variables: NPROC (cores for the water subtraction, default 3), ONLY_VINT (for example 2020; no data is written), ONLY_STATE (a state FIPS),
# BLOCKS_ONLY=1 (run only the block passes of step 3, which need no other table, and stop), TEST_DIR=<dir> (with ONLY_VINT or ONLY_STATE: build the tables for that subset into <dir> instead of data/).
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(tigris_use_cache = TRUE)
source("data-raw/pipeline_functions.R"); source("data-raw/population/population_functions.R"); source("data-raw/land_functions.R")
source("data-raw/dat/pairing_functions.R"); source("data-raw/dat/exposure_functions.R")
lg <- function(...) message(format(Sys.time(), "%H:%M:%S "), ...)
nproc <- as.integer(Sys.getenv("NPROC", "3")); only_v <- Sys.getenv("ONLY_VINT", ""); only_st <- Sys.getenv("ONLY_STATE", ""); blocks_only <- identical(Sys.getenv("BLOCKS_ONLY"), "1"); test_dir <- Sys.getenv("TEST_DIR", ""); write_data <- (!nzchar(only_v) && !nzchar(only_st) && !blocks_only) || (nzchar(test_dir) && !blocks_only)
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f)
S <- list(); pass_dir <- if (nzchar(Sys.getenv("TEST_DIR", ""))) file.path(Sys.getenv("TEST_DIR"), "block_pass") else "data-raw/dat/fetch/block_pass"; dir.create(pass_dir, recursive = TRUE, showWarnings = FALSE)
spc_rows <- tornado_exposure[tornado_exposure$spc_exposed, ]          # the SPC rows, as stored
tt <- st_drop_geometry(tornado_tracks); tt$date <- as.Date(tt$date); tt$vint <- vint_of(as.integer(substr(tt$tornado_id, 1, 4)))
vints <- if (nzchar(only_v)) as.integer(only_v) else c(2000L, 2010L, 2020L)

# ---- 1. footprint polygons and zones ------------------------------------------------------------------------------------------------------------
F <- footprint_pairs(tornado_dat_link, dat_polygon_line_link, dat_polygons)
S$footprint <- c(pairs_touching = nrow(F$all), pairs_ef0_ef5 = nrow(F$used), pairs_other_efscale = nrow(F$other), tornadoes_with_footprint = length(unique(F$used$tornado_id)),
                 polygons_used = length(unique(F$used$dat_polygon_id)), polygons_other_touching = length(unique(F$other$dat_polygon_id)))
S$other_efscale <- table(F$other$efscale)
S$polygons_other_total <- sum(!dat_polygons$efscale %in% paste0("EF", 0:5)); S$polygons_no_date <- sum(is.na(dat_polygons$stormdate)); S$polygons_empty <- sum(st_is_empty(dat_polygons))
zones <- footprint_zones(F$used, dat_polygons); S$zones <- c(zones = nrow(zones), polygons_repaired = attr(zones, "polygons_repaired"))
zones$vint <- vint_of(as.integer(substr(zones$tornado_id, 1, 4))); print(S$footprint); print(S$zones)

# ---- 2. ZCTA areas -------------------------------------------------------------------------------------------------------------------------------
zpieces <- list()
for (v in if (blocks_only) integer(0) else vints) {
  zl <- zcta_land(v, nproc); z <- zones[zones$vint == v, ]
  p <- zone_pieces(z, zl$land, zl$d$ZCTA); names(p)[names(p) == "key"] <- "ZCTA"; p$vint <- v
  p$land_shape_m2 <- zl$d$land_m2[match(p$ZCTA, zl$d$ZCTA)]; zpieces[[as.character(v)]] <- p
  lg("ZCTA ", v, ": ", nrow(p), " zone-ZCTA pieces; ", length(unique(p$tornado_id)), " tornadoes")
}
zpieces <- if (length(zpieces)) bind_rows(zpieces) else NULL

# ---- 3. blocks: residents, tract and block-group areas ---------------------------------------------------------------------------------------------
states <- pop_states(); stt <- tigris::states(cb = TRUE, year = 2020, progress_bar = FALSE)
stt <- st_buffer(st_transform(stt[, "STATEFP"], 5070), 10000)       # generous outlines
pts_all <- dat_points[!is.na(dat_points$stormdate) & !st_is_empty(dat_points), c("objectid", "stormdate_utc", "efscale")]
pts_all$date <- as.Date(pts_all$stormdate_utc); pts_all5 <- st_transform(pts_all, 5070)
linked <- tt[tt$tornado_id %in% tornado_dat_link$tornado_id, ]
passes <- list()
for (v in vints) {
  z <- zones[zones$vint == v, ]; if (!nrow(z)) next
  hit <- st_intersects(z, stt); fips <- sort(unique(stt$STATEFP[unlist(hit)])); fips <- fips[fips %in% states$state_code]
  if (nzchar(only_st)) fips <- intersect(fips, only_st)
  lv <- linked[linked$vint == v, ]; dts <- sort(unique(c(lv$date - 1, lv$date, lv$date + 1)))
  pv <- pts_all5[pts_all5$date %in% dts, ]
  for (fp in fips) {
    f <- file.path(pass_dir, sprintf("%s_%s.rds", v, fp))
    if (!file.exists(f)) {
      zs <- z[vapply(hit, function(h) fp %in% stt$STATEFP[h], logical(1)), ]
      ps <- pv[lengths(st_intersects(pv, stt[stt$STATEFP == fp, ])) > 0, ]; ps <- st_transform(ps, 4269)
      lg("block pass ", v, " state ", fp, ": ", nrow(zs), " zones, ", nrow(ps), " points")
      r <- block_pass(v, states[states$state_code == fp, ], zs, ps, nproc); saveRDS(r, f)
    }
    passes[[paste(v, fp)]] <- readRDS(f); passes[[paste(v, fp)]]$vint <- v; passes[[paste(v, fp)]]$fips <- fp
  }
}
if (!write_data) { lg("test run: no data written"); quit(save = "no") }
if (!nzchar(test_dir)) saveRDS(list(S = S, passes = lapply(passes, function(p) p[c("invalid_repaired", "blocks_water_touched", "blocks_read", "vint", "fips", "no_land")])), "data-raw/dat/fetch/exposure_summary.rds")

# ---- 4. tables -----------------------------------------------------------------------------------------------------------------------------------
bl <- bind_rows(lapply(passes, function(p) cbind(p$blocks, vint = rep(p$vint, nrow(p$blocks)))))
bl <- bl[!duplicated(bl[c("vint", "GEOID")]), ]
pc <- bind_rows(lapply(passes, function(p) { x <- p$pieces; x$vint <- rep(p$vint, nrow(x)); x }))
pc$pop <- bl$pop[match(paste(pc$vint, pc$GEOID), paste(bl$vint, bl$GEOID))]; pc$ZCTA <- bl$ZCTA[match(paste(pc$vint, pc$GEOID), paste(bl$vint, bl$GEOID))]
pc$share <- pc$area_m2 / pc$land_m2; pc$resid <- pc$pop * pc$share
pcp <- bind_rows(lapply(passes, function(p) { x <- p$pieces_polygon; x$vint <- rep(p$vint, nrow(x)); x }))      # blocks with residents and no land: residents by the share of the block polygon
pcp$pop <- bl$pop[match(paste(pcp$vint, pcp$GEOID), paste(bl$vint, bl$GEOID))]; pcp$ZCTA <- bl$ZCTA[match(paste(pcp$vint, pcp$GEOID), paste(bl$vint, bl$GEOID))]; pcp$resid <- pcp$pop * pcp$area_m2 / pcp$poly_m2
rcols <- c("tornado_id", "rating", "GEOID", "vint", "ZCTA", "resid"); pr_all <- bind_rows(pc[rcols], pcp[rcols])
nl <- do.call(rbind, lapply(passes, function(p) p$no_land))
S$blocks <- c(blocks_in_tracts = nrow(bl), pieces = nrow(pc), water_touched = sum(vapply(passes, function(p) p$blocks_water_touched, numeric(1))), invalid_repaired = sum(vapply(passes, function(p) p$invalid_repaired, numeric(1))),
              blocks_no_land = sum(nl[, "blocks"]), blocks_no_land_with_residents = sum(nl[, "with_residents"]), residents_in_no_land_blocks = sum(nl[, "residents"]), largest_land_residue_m2 = max(nl[, "largest_residue_m2"]), no_land_but_aland_positive = sum(nl[, "aland_positive"]),
              polygon_pieces_for_residents = nrow(pcp), residents_by_polygon_share = sum(pcp$resid), largest_share = max(pc$share, pcp$area_m2 / pcp$poly_m2))
print(S$blocks); stopifnot(!anyNA(pr_all$resid))
rate <- function(x, pre, val) { w <- tapply(x[[val]], list(paste(x$tornado_id, x$key), paste0(pre, x$rating)), sum); cols <- paste0(pre, 0:5); w <- w[, intersect(cols, colnames(w)), drop = FALSE]
  m <- matrix(0, nrow(w), 6, dimnames = list(rownames(w), cols)); m[, colnames(w)] <- ifelse(is.na(w), 0, w); m }

# ZCTA
za <- zpieces; za$key <- za$ZCTA; za$share <- za$area_m2 / za$land_shape_m2
if (any(za$share > 1 + 1e-9)) stop(sum(za$share > 1 + 1e-9), " zone-ZCTA shares above 1.", call. = FALSE)
A <- rate(za, "dat_area_share_ef", "share"); zk <- strsplit(rownames(A), " "); zdat <- data.frame(tornado_id = vapply(zk, `[`, "", 1), ZCTA = vapply(zk, `[`, "", 2), A, stringsAsFactors = FALSE, check.names = FALSE)
pz <- pr_all[!is.na(pr_all$ZCTA), ]; pz$key <- pz$ZCTA; Pm <- rate(pz, "dat_pop_ef", "resid")
S$residents_no_zcta <- sum(pr_all$resid[is.na(pr_all$ZCTA)])
rownames(Pm) <- sub("^(.*) (.*)$", "\\1 \\2", rownames(Pm))
S$residents_in_zctas_without_area <- sum(Pm[!rownames(Pm) %in% rownames(A), ])
key_z <- paste(zdat$tornado_id, zdat$ZCTA)

# ---- 5. points in ZCTAs ----------------------------------------------------------------------------------------------------------------------------
cls <- function(e) ifelse(e %in% paste0("EF", 0:5), paste0("ef", substr(e, 3, 3)), ifelse(e %in% "EFU", "efu", ifelse(e %in% "TSTM/Wind", "wind", "other")))
pts_cls <- cls(pts_all$efscale); lv_all <- linked
zfull <- lapply(c(2000L, 2010L, 2020L), load_zctas); names(zfull) <- c("2000", "2010", "2020")
zp <- list()
for (v in c(2000L, 2010L, 2020L)) {
  zc <- zfull[[as.character(v)]]; h <- st_intersects(pts_all5, zc)
  pz_ <- data.frame(objectid = rep(pts_all$objectid, lengths(h)), ZCTA = zc$ZCTA[unlist(h)], stringsAsFactors = FALSE)
  lv <- lv_all[lv_all$vint == v, c("tornado_id", "date")]
  pr <- bind_rows(lapply(-1:1, function(o) merge(transform(lv, d2 = date + o), data.frame(objectid = pts_all$objectid, d2 = pts_all$date), by = "d2")[, c("tornado_id", "objectid")]))
  x <- merge(pr, pz_, by = "objectid"); x$cls <- pts_cls[match(x$objectid, pts_all$objectid)]; x$vint <- v; zp[[as.character(v)]] <- x
  lg("points ", v, ": ", nrow(x), " tornado-point-ZCTA pairs")
}
zp <- bind_rows(zp)
zcount <- zp %>% count(tornado_id, ZCTA, cls) %>% tidyr::pivot_wider(names_from = cls, values_from = n, values_fill = 0L)
for (c_ in c(paste0("ef", 0:5), "efu", "wind", "other")) if (!c_ %in% names(zcount)) zcount[[c_]] <- 0L

# ---- 6. the ZCTA rows ----------------------------------------------------------------------------------------------------------------------------
pop_cols <- paste0("dat_pop_ef", 0:5); area_cols <- paste0("dat_area_share_ef", 0:5)
keys_dat <- zdat[rowSums(zdat[area_cols]) > 0, c("tornado_id", "ZCTA")]
keys_spc <- spc_rows[, c("tornado_id", "ZCTA")]
only_dat <- keys_dat[!paste(keys_dat$tornado_id, keys_dat$ZCTA) %in% paste(keys_spc$tornado_id, keys_spc$ZCTA), ]
S$rows <- c(spc_rows = nrow(spc_rows), dat_exposed_rows = nrow(keys_dat), dat_only_rows = nrow(only_dat), both = nrow(keys_dat) - nrow(only_dat))
print(S$rows)
cen <- zcta_centroids; tr <- tornado_tracks
# DAT-only rows: tornado attributes, the distances from the SPC line, and the ZCTA columns
d <- only_dat; d$year <- as.numeric(substr(d$tornado_id, 1, 4)); d$vint <- vint_of(d$year)
a <- tt[match(d$tornado_id, tt$tornado_id), ]
d$date <- a$date; d$month <- format(a$date, "%m"); d$day <- format(a$date, "%d"); d$magnitude <- a$magnitude; d$total_injury <- a$total_injury; d$total_fatality <- a$total_fatality
d$property_loss_tornado_total <- a$property_loss_tornado_total; d$track_type <- a$track_type; d$spc_exposed <- FALSE; d$line_km_in_zcta <- NA_real_; d$line_share_of_tornado <- NA_real_; d$property_loss_allocated <- NA_real_
cc <- cen[match(paste(d$vint, d$ZCTA), paste(cen$vintage, cen$ZCTA)), ]; stopifnot(!anyNA(cc$lon))
g <- st_geometry(tr)[match(d$tornado_id, tr$tornado_id)]
d$centroid_dist_km <- .track_centroid_dist(g, cc$lon, cc$lat)
zg <- st_sfc(lapply(seq_len(nrow(d)), function(i) st_geometry(zfull[[as.character(d$vint[i])]])[match(d$ZCTA[i], zfull[[as.character(d$vint[i])]]$ZCTA)][[1]]), crs = 5070)
d$boundary_dist_km <- .track_zcta_dist(g, zg)
d$zcta_pop <- as.numeric(cc$zcta_pop); d$zcta_land_area_m2 <- cc$zcta_land_area_m2; d$zcta_polygon_area_m2 <- cc$zcta_polygon_area_m2; d$zcta_land_shape_area_m2 <- cc$zcta_land_shape_area_m2
S$dat_only_boundary_dist <- summary(d$boundary_dist_km)
all_rows <- bind_rows(spc_rows[, names(spc_rows)[names(spc_rows) %in% names(d)]], d[, names(d) %in% names(spc_rows)])
all_rows$vint <- vint_of(all_rows$year); rk <- paste(all_rows$tornado_id, all_rows$ZCTA)
lnk <- aggregate(dat_line_id ~ tornado_id, data = tornado_dat_link, FUN = function(x) paste(sort(x), collapse = ";"))
all_rows$dat_linked <- all_rows$tornado_id %in% tornado_dat_link$tornado_id; all_rows$dat_line_ids <- lnk$dat_line_id[match(all_rows$tornado_id, lnk$tornado_id)]
zi <- match(rk, key_z); lk <- all_rows$dat_linked
for (j in 0:5) {
  a_ <- zdat[[paste0("dat_area_share_ef", j)]][zi]; all_rows[[paste0("dat_area_share_ef", j)]] <- ifelse(lk, ifelse(is.na(a_), 0, a_), NA_real_)
  p_ <- Pm[match(rk, rownames(Pm)), paste0("dat_pop_ef", j)]; all_rows[[paste0("dat_pop_ef", j)]] <- ifelse(lk, ifelse(is.na(p_), 0, p_), NA_real_)
}
all_rows$dat_area_share <- ifelse(lk, rowSums(all_rows[area_cols]), NA_real_); all_rows$dat_pop_affected <- ifelse(lk, rowSums(all_rows[pop_cols]), NA_real_)
all_rows$dat_exposed <- ifelse(lk, all_rows$dat_area_share > 0, NA)
ci <- match(rk, paste(zcount$tornado_id, zcount$ZCTA))
for (c_ in c(paste0("ef", 0:5), "efu", "wind", "other")) { x <- zcount[[c_]][ci]; all_rows[[paste0("dat_points_", c_)]] <- ifelse(lk, ifelse(is.na(x), 0L, x), NA_integer_) }
# other SPC tornadoes exposing the ZCTA within a day
sp <- spc_rows; sp$date <- as.Date(sp$date); n_by <- table(paste(sp$ZCTA, sp$date))
cnt <- function(z, dd) { k <- paste(z, dd); r <- as.integer(n_by[k]); ifelse(is.na(r), 0L, r) }
dd <- as.Date(all_rows$date); tot <- cnt(all_rows$ZCTA, dd - 1) + cnt(all_rows$ZCTA, dd) + cnt(all_rows$ZCTA, dd + 1)
all_rows$other_tornadoes_in_zcta_within_a_day <- ifelse(lk, tot - ifelse(all_rows$spc_exposed, 1L, 0L), NA_integer_)
cols <- c("tornado_id", "date", "year", "month", "day", "magnitude", "total_injury", "total_fatality", "property_loss_tornado_total", "track_type", "ZCTA",
          "spc_exposed", "line_km_in_zcta", "line_share_of_tornado", "property_loss_allocated", "centroid_dist_km", "boundary_dist_km",
          "zcta_pop", "zcta_land_area_m2", "zcta_polygon_area_m2", "zcta_land_shape_area_m2",
          "dat_linked", "dat_line_ids", "dat_exposed", "dat_area_share", area_cols, "dat_pop_affected", pop_cols,
          paste0("dat_points_ef", 0:5), "dat_points_efu", "dat_points_wind", "dat_points_other", "other_tornadoes_in_zcta_within_a_day")
tornado_exposure <- all_rows[order(all_rows$tornado_id, all_rows$ZCTA), cols]; rownames(tornado_exposure) <- NULL
tornado_exposure$date <- as.Date(tornado_exposure$date)
S$points_zcta_dropped <- c(pairs = nrow(zp), in_rows = sum(paste(zp$tornado_id, zp$ZCTA) %in% paste(tornado_exposure$tornado_id, tornado_exposure$ZCTA)))
S$ratings_sum <- max(abs(tornado_exposure$dat_area_share - rowSums(tornado_exposure[area_cols])), na.rm = TRUE)
stopifnot(all(tornado_exposure$dat_area_share <= 1 + 1e-9, na.rm = TRUE))

# ---- 7. tract and block group ------------------------------------------------------------------------------------------------------------------------
unit_table <- function(nchar_id, name) {
  b <- bl; b$unit <- substr(b$GEOID, 1, nchar_id)
  den <- b %>% group_by(vint, unit) %>% summarise(land_area_m2 = sum(ALAND), land_shape_area_m2 = sum(land_m2), pop = sum(pop), .groups = "drop")
  p <- pc; p$unit <- substr(p$GEOID, 1, nchar_id); pp <- pr_all; pp$unit <- substr(pp$GEOID, 1, nchar_id)
  ar <- p %>% group_by(tornado_id, vint, unit, rating) %>% summarise(area = sum(area_m2), .groups = "drop")
  rs <- pp %>% group_by(tornado_id, vint, unit, rating) %>% summarise(resid = sum(resid), .groups = "drop")
  num <- full_join(ar, rs, by = c("tornado_id", "vint", "unit", "rating")); num$area[is.na(num$area)] <- 0; num$resid[is.na(num$resid)] <- 0
  has_area <- num %>% group_by(tornado_id, vint, unit) %>% summarise(a = sum(area), .groups = "drop") %>% filter(a > 0)     # a unit has a row where the footprint covers land in it
  S[[paste0("residents_outside_", name, "_rows")]] <<- sum(num$resid[!paste(num$tornado_id, num$vint, num$unit) %in% paste(has_area$tornado_id, has_area$vint, has_area$unit)])
  num <- num[paste(num$tornado_id, num$vint, num$unit) %in% paste(has_area$tornado_id, has_area$vint, has_area$unit), ] %>% left_join(den, by = c("vint", "unit"))
  num$share <- num$area / num$land_shape_area_m2
  if (any(num$share > 1 + 1e-9)) stop(sum(num$share > 1 + 1e-9), " ", name, " shares above 1.", call. = FALSE)
  num$key <- num$unit; A <- rate(num, "dat_area_share_ef", "share"); R <- rate(num, "dat_pop_ef", "resid")
  k <- strsplit(rownames(A), " "); out <- data.frame(tornado_id = vapply(k, `[`, "", 1), GEOID = vapply(k, `[`, "", 2), stringsAsFactors = FALSE)
  out$vint <- vint_of(as.integer(substr(out$tornado_id, 1, 4))); dm <- den[match(paste(out$vint, out$GEOID), paste(den$vint, den$unit)), ]
  out[[paste0(name, "_pop")]] <- dm$pop; out[[paste0(name, "_land_area_m2")]] <- dm$land_area_m2; out[[paste0(name, "_land_shape_area_m2")]] <- dm$land_shape_area_m2
  out$dat_area_share <- rowSums(A); for (j in 0:5) out[[paste0("dat_area_share_ef", j)]] <- A[, j + 1]
  out$dat_pop_affected <- rowSums(R); for (j in 0:5) out[[paste0("dat_pop_ef", j)]] <- R[, j + 1]
  # points in the unit, within one day of the tornado
  pb <- bind_rows(lapply(passes, function(p) { x <- p$points; x$vint <- rep(p$vint, nrow(x)); x })); pb$unit <- substr(pb$GEOID, 1, nchar_id)
  pb$date <- pts_all$date[match(pb$objectid, pts_all$objectid)]; pb$cls <- pts_cls[match(pb$objectid, pts_all$objectid)]
  th <- tt[tt$tornado_id %in% out$tornado_id, c("tornado_id", "date")]
  pr <- bind_rows(lapply(-1:1, function(o) merge(transform(th, d2 = date + o), data.frame(objectid = pb$objectid, d2 = pb$date), by = "d2")[, c("tornado_id", "objectid")]))
  x <- merge(pr, unique(pb[, c("objectid", "unit", "cls", "vint")]), by = "objectid"); x$vint_t <- vint_of(as.integer(substr(x$tornado_id, 1, 4))); x <- x[x$vint == x$vint_t, ]
  ct <- x %>% count(tornado_id, unit, cls) %>% tidyr::pivot_wider(names_from = cls, values_from = n, values_fill = 0L)
  for (c_ in c(paste0("ef", 0:5), "efu", "wind", "other")) if (!c_ %in% names(ct)) ct[[c_]] <- 0L
  m <- match(paste(out$tornado_id, out$GEOID), paste(ct$tornado_id, ct$unit))
  for (c_ in c(paste0("ef", 0:5), "efu", "wind", "other")) { v_ <- ct[[c_]][m]; out[[paste0("dat_points_", c_)]] <- ifelse(is.na(v_), 0L, v_) }
  out$vint <- NULL; out[order(out$tornado_id, out$GEOID), ]
}
dat_exposure_tract <- unit_table(11, "tract"); dat_exposure_blockgroup <- unit_table(12, "blockgroup")
rownames(dat_exposure_tract) <- NULL; rownames(dat_exposure_blockgroup) <- NULL
S$tables <- c(zcta_rows = nrow(tornado_exposure), tract_rows = nrow(dat_exposure_tract), blockgroup_rows = nrow(dat_exposure_blockgroup))
print(S$tables); if (!nzchar(test_dir)) saveRDS(S, "data-raw/dat/fetch/exposure_summary_tables.rds")
if (nzchar(test_dir)) { dir.create(test_dir, showWarnings = FALSE); save(tornado_exposure, dat_exposure_tract, dat_exposure_blockgroup, file = file.path(test_dir, "tables.rda")) } else usethis::use_data(tornado_exposure, dat_exposure_tract, dat_exposure_blockgroup, overwrite = TRUE, compress = "xz")
