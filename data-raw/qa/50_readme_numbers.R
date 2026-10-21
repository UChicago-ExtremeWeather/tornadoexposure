# Run from the package root after the QA scripts 29, 02, 46, 47 and 48:  Rscript data-raw/qa/50_readme_numbers.R
# Collects the README numbers that come from the QA scripts into data-raw/readme/numbers.csv (name, value, source); README.Rmd reads that file.
# Numbers that can be computed directly from the bundled data are computed in README.Rmd itself.
suppressMessages({library(sf); library(dplyr)}); source("data-raw/qa/helpers.R")
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
tt <- st_drop_geometry(tornado_tracks); d <- tornado_exposure; sm <- survey_matches; se <- survey_exposure
out <- list(); add <- function(name, value, source) out[[length(out) + 1]] <<- data.frame(name = name, value = value, source = source)
# largest distance between the surveyed centerline and the modeled line (tornadoes with a usable swath, line tracks), data-raw/qa/46
cal <- readRDS(qa_out("survey_path_accuracy.rds"))$calibration
add("offset_n", nrow(cal), "46"); add("offset_median_km", median(cal$max_km), "46"); add("offset_p90_km", unname(quantile(cal$max_km, .9)), "46")
# coordinate rounding simulation, data-raw/qa/02
r <- readRDS(qa_out("coordinate_rounding_summary.rds"))
add("round_before_2007_pct", r$`tornadoes_changed_%/rep`[1], "02"); add("round_from_2007_pct", r$`tornadoes_changed_%/rep`[2], "02")
add("round_before_2007_any_pct", r$`tornadoes_changed_in_any_rep_%`[1], "02"); add("round_from_2007_any_pct", r$`tornadoes_changed_in_any_rep_%`[2], "02"); add("round_n_per_era", r$tornadoes[1], "02")
# ZCTA codes whose two boundary files overlap by less than half (intersection area divided by union area), data-raw/qa/29
v <- readRDS(qa_out("zcta_vintage_overlap.rds"))
add("overlap_half_2010_2020_pct", 100 * mean(v$r1020$ratio < 0.5), "29"); add("overlap_half_2000_2010_pct", 100 * mean(v$r0010$ratio < 0.5), "29")
add("overlap_codes_2010_2020", nrow(v$r1020), "29"); add("overlap_codes_2000_2010", nrow(v$r0010), "29")
# tornadoes without a ZCTA, data-raw/qa/47
z <- readRDS(qa_out("no_zcta_summary.rds"))
add("noz_n", z$n, "47"); add("noz_pct", 100 * z$n / nrow(tt), "47")
add("noz_water", z$cats[["over water"]], "47"); add("noz_nonear", z$cats[["over land, no ZCTA nearby"]], "47"); add("noz_mostly", z$cats[["on land, mostly covered"]], "47")
# modeled / surveyed share of residents in the same ZCTA, tornadoes with a usable swath (population-share row of the agreement table), as in check_documented_claims.R
inc <- sm$tornado_id[sm$status == "included"]
J <- full_join(d[d$tornado_id %in% inc, c("tornado_id", "ZCTA", "pop_prop_affected")], se[, c("tornado_id", "ZCTA", "pop_prop_affected")], by = c("tornado_id", "ZCTA"), suffix = c("_m", "_s"))
pb <- J[!is.na(J$pop_prop_affected_m) & !is.na(J$pop_prop_affected_s) & J$pop_prop_affected_m > 0 & J$pop_prop_affected_s > 0, ]; q <- pb$pop_prop_affected_m / pb$pop_prop_affected_s
add("popratio_n", nrow(pb), "agreement table"); add("popratio_median", median(q), "agreement table"); add("popratio_p10", unname(quantile(q, .1)), "agreement table"); add("popratio_p90", unname(quantile(q, .9)), "agreement table")
# first and second map_exposure() call, data-raw/qa/48
m <- readRDS(qa_out("first_map_timing.rds"))
add("map_zip_mb_2000", m$size_mb[["cb_2000"]], "48"); add("map_zip_mb_2020", m$size_mb[["cb_2020"]], "48")
add("map_first_s", m$first_s, "48"); add("map_second_s", m$second_s, "48"); add("map_zip_mb", m$zip_mb, "48"); add("map_disk_mb", m$downloaded_mb, "48")
res <- do.call(rbind, out); write.csv(res, "data-raw/readme/numbers.csv", row.names = FALSE); print(res, row.names = FALSE)
