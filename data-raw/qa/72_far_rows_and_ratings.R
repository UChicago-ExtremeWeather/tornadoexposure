# Run from the package root, after data-raw/dat/build_dat_exposure.R:  Rscript data-raw/qa/72_far_rows_and_ratings.R
# 1. The DAT-only rows of tornado_exposure (spc_exposed FALSE and dat_exposed TRUE): how far they lie from the SPC line (boundary_dist_km). For 5, 25 and 100 km (descriptive values, not
#    recommendations) the number of rows and of tornadoes with at least one such row beyond the distance, the tornadoes whose rows all lie within 5 km, the farthest row, and the
#    quantiles of dat_link_dist_km (the largest one-sided link distance of the tornado) for the rows beyond 5 km against the rows within 5 km.
# 2. The unknown ratings (magnitude NA) of tornado_tracks by year: count and share of the tornadoes of each year.
# 3. The share of EF0 among the tornadoes with no usable end point, of all of them and of those with a rating.
# Output: data-raw/qa/out/72_far_rows_and_ratings.rds and rows far_*, unk_* and ef0_point_* in data-raw/readme/numbers.csv.
source("data-raw/qa/helpers.R"); suppressMessages(library(dplyr))
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f)
ex <- tornado_exposure; tt <- sf::st_drop_geometry(tornado_tracks)
d <- ex[!ex$spc_exposed & ex$dat_exposed %in% TRUE, ]
beyond <- function(km) c(rows = sum(d$boundary_dist_km > km), tornadoes = length(unique(d$tornado_id[d$boundary_dist_km > km])))
q <- c(0, .1, .25, .5, .75, .9, 1)
far <- d$boundary_dist_km > 5
qs <- list(far = quantile(d$dat_link_dist_km[far], q), near = quantile(d$dat_link_dist_km[!far], q))
lk <- ex[ex$dat_linked, ]; lk1 <- lk[!duplicated(lk$tornado_id), ]
yr <- as.integer(format(tt$date, "%Y")); unk <- is.na(tt$magnitude)
by_year <- data.frame(year = sort(unique(yr)), n = as.vector(table(yr)), unknown = as.vector(tapply(unk, yr, sum)))
by_year$pct <- 100 * by_year$unknown / by_year$n
pt <- tt$track_type == "point"
R <- list(dat_only_rows = nrow(d), dat_only_tornadoes = length(unique(d$tornado_id)), within5_tornadoes = length(unique(d$tornado_id)) - beyond(5)[["tornadoes"]],
          b5 = beyond(5), b25 = beyond(25), b100 = beyond(100), max_km = max(d$boundary_dist_km), quantiles_dat_link_dist = qs, by_year = by_year,
          link_dist_rows = sum(!is.na(ex$dat_link_dist_km)), link_dist_tornadoes = length(unique(ex$tornado_id[!is.na(ex$dat_link_dist_km)])),
          link_dist_quantiles = quantile(lk1$dat_link_dist_km, c(0, .1, .25, .5, .75, .9, .99, 1)), ef0_rated = 100 * mean(tt$magnitude[pt] == 0, na.rm = TRUE),
          ef0_all = 100 * mean(tt$magnitude[pt] %in% 0), rated_points = sum(pt & !unk))
saveRDS(R, qa_out("72_far_rows_and_ratings.rds")); print(R)
y <- by_year
stopifnot(all(y$unknown[y$year <= 2006] == 0), y$unknown[y$year == 2007] > 0, all(y$unknown[y$year >= 2008 & y$year <= 2015] == 0), all(y$unknown[y$year >= 2016] > 0))
nm <- c(far_dat_only_rows = R$dat_only_rows, far_dat_only_tornadoes = R$dat_only_tornadoes, far_within5_tornadoes = R$within5_tornadoes,
        far_5_rows = R$b5[["rows"]], far_5_tornadoes = R$b5[["tornadoes"]], far_25_rows = R$b25[["rows"]], far_25_tornadoes = R$b25[["tornadoes"]],
        far_100_rows = R$b100[["rows"]], far_100_tornadoes = R$b100[["tornadoes"]], far_max_km = R$max_km,
        unk_2007_n = y$unknown[y$year == 2007], unk_2016_25_min_n = min(y$unknown[y$year >= 2016]), unk_2016_25_max_n = max(y$unknown[y$year >= 2016]),
        unk_2016_25_min_pct = min(y$pct[y$year >= 2016]), unk_2016_25_max_pct = max(y$pct[y$year >= 2016]), unk_2007_pct = y$pct[y$year == 2007],
        ef0_point_all_pct = R$ef0_all, ef0_point_rated_pct = R$ef0_rated)
f <- "data-raw/readme/numbers.csv"; n <- read.csv(f, stringsAsFactors = FALSE); n <- n[!n$name %in% names(nm), ]
write.csv(rbind(n, data.frame(name = names(nm), value = unname(nm), source = "72")), f, row.names = FALSE)
