# Run from the package root, after data-raw/dat/build_dat.R:  Rscript data-raw/qa/46_path_accuracy.R     Saves data-raw/qa/out/path_accuracy.rds and the rows offset_* of data-raw/readme/numbers.csv
# How far the SPC straight line is from the surveyed centerline: for every SPC line tornado linked to a DAT line (tornado_dat_link), the largest distance from a vertex of the full-resolution DAT line
# to the SPC straight line (kilometers, EPSG:5070). Chord = length of the SPC straight line, in miles; classes under 5, 5 to 20 and over 20 miles.
# Every linked pair counts, whatever its link distance (no cutoff).
suppressMessages({library(sf); library(dplyr)}); source("data-raw/qa/helpers.R"); source("data-raw/dat/pairing_functions.R"); sf_use_s2(FALSE)
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
mi_to_m <- 1609.344
lk <- tornado_dat_link; tt <- tornado_tracks; lk <- lk[lk$tornado_id %in% tt$tornado_id[tt$track_type == "line"], ]
L5 <- st_transform(st_geometry(dat_lines)[match(lk$dat_line_id, dat_lines$objectid)], 5070); Tt <- tt[match(lk$tornado_id, tt$tornado_id), ]; sp <- spc_paths(Tt)
mx <- vapply(seq_along(L5), function(i) { m <- st_coordinates(L5[i])[, 1:2, drop = FALSE]; max(pdist(m[, 1], m[, 2], sp$s5[i, 1], sp$s5[i, 2], sp$e5[i, 1], sp$e5[i, 2])) / 1000 }, 0)
chord_mi <- sqrt((sp$e5[, 1] - sp$s5[, 1])^2 + (sp$e5[, 2] - sp$s5[, 2])^2) / mi_to_m
d <- data.frame(tornado_id = lk$tornado_id, dat_line_id = lk$dat_line_id, rule = lk$rule, max_km = mx, chord_mi = chord_mi, cls = cut(chord_mi, c(-Inf, 5, 20, Inf), labels = c("under 5 miles", "5 to 20 miles", "over 20 miles")))
q <- function(x) quantile(x, c(.5, .9), names = FALSE)
R <- list(all = c(n = nrow(d), median = q(d$max_km)[1], p90 = q(d$max_km)[2]), by_class = d %>% group_by(cls) %>% summarise(n = n(), median = median(max_km), p90 = quantile(max_km, .9), .groups = "drop"), data = d)
saveRDS(R, qa_out("path_accuracy.rds")); print(R[1:2])
nm <- c(offset_n = nrow(d), offset_median_km = q(d$max_km)[1], offset_p90_km = q(d$max_km)[2])
f <- "data-raw/readme/numbers.csv"; n <- read.csv(f, stringsAsFactors = FALSE); n <- n[!n$name %in% names(nm), ]
write.csv(rbind(n, data.frame(name = names(nm), value = unname(nm), source = "46")), f, row.names = FALSE)
