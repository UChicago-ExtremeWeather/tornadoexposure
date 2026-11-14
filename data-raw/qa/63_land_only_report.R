# Run from the package root after data-raw/add_centroids.R and data-raw/dat/build_dat_exposure.R:  Rscript data-raw/qa/63_land_only_report.R
# Reports how the land-only shapes (the unit polygon minus the Census water polygons, data-raw/land_functions.R) compare with the Census land area ALAND:
#   ZCTAs: every ZCTA of each boundary year (cached in data-raw/cache/zcta_land_<year>.rds by add_centroids.R): quantiles of land_shape / ALAND, the share within 1, 5 and
#          10 percent, the number of ZCTAs with a water polygon inside, the ZCTAs that differ by more than 1 percent, the 20 largest differences.
#   blocks: every block of the tracts that the DAT footprints reach (the blocks of data-raw/dat/fetch/block_pass/): the same comparison with the block's ALAND.
# Output: data-raw/qa/out/63_land_report.rds and rows land_* in data-raw/readme/numbers.csv.
source("data-raw/qa/helpers.R"); source("data-raw/dat/exposure_functions.R", local = TRUE); suppressMessages(library(dplyr))
q <- function(r) quantile(r, c(0, .001, .01, .05, .5, .95, .99, .999, 1), names = FALSE)
within <- function(r, t) mean(abs(r - 1) <= t)
Z <- list()
for (v in c(2000, 2010, 2020)) {
  x <- readRDS(sprintf("data-raw/cache/zcta_land_%s.rds", v)); d <- x$d; ok <- d$ALAND > 0; r <- d$land_m2[ok] / d$ALAND[ok]
  ws <- readRDS(sprintf("data-raw/cache/water_summary_%s.rds", x$water_set))
  big <- d[ok & abs(d$land_m2 / d$ALAND - 1) > 0.01, ]; big$ratio <- big$land_m2 / big$ALAND
  Z[[as.character(v)]] <- list(zctas = nrow(d), aland_zero = sum(!ok), land_zero = sum(d$land_m2 <= 0), water_touched = sum(d$water_touched), quantiles = q(r), within1 = within(r, .01), within5 = within(r, .05), within10 = within(r, .10),
    over1 = nrow(big), land_larger = sum(big$ratio > 1), land_smaller = sum(big$ratio < 1), worst = head(big[order(-abs(big$ratio - 1)), c("ZCTA", "ALAND", "land_m2", "ratio")], 20), ratio_above_1 = sum(r > 1 + 1e-9),
    polygons_invalid_repaired = x$invalid_repaired, water_set = x$water_set, water_files = sum(ws$files), water_bytes = sum(ws$bytes), water_polygons = sum(ws$water_polygons), water_invalid_repaired = sum(ws$invalid_repaired))
}
passes <- list.files("data-raw/dat/fetch/block_pass", pattern = "[.]rds$", full.names = TRUE)
B <- bind_rows(lapply(passes, function(f) { p <- readRDS(f); b <- p$blocks; b$vint <- rep(as.integer(sub("_.*", "", basename(f))), nrow(b)); b }))
B <- B[!duplicated(B[c("vint", "GEOID")]), ]
Bs <- lapply(c(2000, 2010, 2020), function(v) { b <- B[B$vint == v, ]; ok <- b$ALAND > 0; r <- b$land_m2[ok] / b$ALAND[ok]
  list(blocks = nrow(b), aland_zero = sum(!ok), aland_zero_land_positive = sum(!ok & b$land_m2 > 0), land_zero_with_residents = sum(b$land_m2 <= 0 & b$pop > 0), quantiles = q(r), within1 = within(r, .01), within5 = within(r, .05), within10 = within(r, .10),
       over1 = sum(abs(r - 1) > .01), over10 = sum(abs(r - 1) > .10), ratio_above_1 = sum(r > 1 + 1e-9), max_ratio = max(r), min_ratio = min(r), land_over_aland_total = sum(b$land_m2) / sum(b$ALAND)) })
names(Bs) <- c("2000", "2010", "2020")
Ball <- list(blocks = nrow(B), min_land_shape_m2 = min(B$land_m2[B$land_m2 > land_tolerance_m2 & B$ALAND > 0]), min_land_shape_state = NA, by_vint = Bs, within1 = within(B$land_m2[B$ALAND > 0] / B$ALAND[B$ALAND > 0], .01), within5 = within(B$land_m2[B$ALAND > 0] / B$ALAND[B$ALAND > 0], .05))
R <- list(zcta = Z, blocks = Ball); saveRDS(R, qa_out("63_land_report.rds")); print(Z[["2020"]][c("zctas", "water_touched", "quantiles", "within1", "within5", "over1", "worst")]); print(Ball)
nm <- c(); for (v in names(Z)) nm <- c(nm, setNames(c(Z[[v]]$zctas, Z[[v]]$water_touched, 100 * Z[[v]]$within1, 100 * Z[[v]]$within5, 100 * Z[[v]]$within10, Z[[v]]$over1, Z[[v]]$water_files, round(Z[[v]]$water_bytes / 1e6)),
  paste0("land_zcta_", c("n", "water_touched", "within1_pct", "within5_pct", "within10_pct", "over1_n", "water_files", "water_mb"), "_", v)))
for (v in names(Bs)) nm <- c(nm, setNames(c(Bs[[v]]$blocks, 100 * Bs[[v]]$within1, 100 * Bs[[v]]$within5, Bs[[v]]$over1, Bs[[v]]$land_zero_with_residents), paste0("land_block_", c("n", "within1_pct", "within5_pct", "over1_n", "land_zero_residents_n"), "_", v)))
f <- "data-raw/readme/numbers.csv"; n <- read.csv(f, stringsAsFactors = FALSE); n <- n[!n$name %in% names(nm), ]
write.csv(rbind(n, data.frame(name = names(nm), value = unname(nm), source = "63")), f, row.names = FALSE)
