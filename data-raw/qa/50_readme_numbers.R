# Run from the package root after the QA scripts 29, 02, 46, 47 and 48:  Rscript data-raw/qa/50_readme_numbers.R
# Collects the README numbers that come from the QA scripts into data-raw/readme/numbers.csv (name, value, source); README.Rmd reads that file.
# Numbers that can be computed directly from the bundled data are computed in README.Rmd itself.
suppressMessages({library(sf); library(dplyr)}); source("data-raw/qa/helpers.R")
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
tt <- st_drop_geometry(tornado_tracks); d <- tornado_exposure
f <- "data-raw/readme/numbers.csv"; keep <- if (file.exists(f)) read.csv(f, stringsAsFactors = FALSE) else data.frame(name = character(), value = numeric(), source = character())
keep <- keep[keep$source %in% c("46", "66"), ]    # written by data-raw/qa/46_path_accuracy.R and 66_modeled_vs_dat.R; run those after this script
out <- list(); add <- function(name, value, source) out[[length(out) + 1]] <<- data.frame(name = name, value = value, source = source)
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
# first and second map_exposure() call, data-raw/qa/48
m <- readRDS(qa_out("first_map_timing.rds"))
add("map_zip_mb_2000", m$size_mb[["full_2000"]], "48"); add("map_zip_mb_2010", m$size_mb[["full_2010"]], "48"); add("map_zip_mb_2020", m$size_mb[["full_2020"]], "48")
add("map_first_s", m$first_s, "48"); add("map_second_s", m$second_s, "48"); add("map_zip_mb", m$zip_mb, "48"); add("map_disk_mb", m$downloaded_mb, "48")
res <- rbind(keep, do.call(rbind, out)); write.csv(res, f, row.names = FALSE); print(res, row.names = FALSE)
