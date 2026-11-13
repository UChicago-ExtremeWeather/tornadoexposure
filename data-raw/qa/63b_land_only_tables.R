# Run from the package root after 63_land_only_area_test.R:  Rscript data-raw/qa/63b_land_only_tables.R      Prints the tables of the land-only area test and saves data-raw/qa/out/63_land_tables.rds
# Per boundary year: the ratio of the land shape area (ZCTA polygon minus the Census water polygons) to ALAND, its quantiles, the share within 1% and 5%, the 20 worst ZCTAs, and what is missing: the share of water that the AREAWATER polygons
# account for against the ZCTA's own AWATER field, and the difference between the polygon area and ALAND + AWATER (boundary differences).
suppressMessages(library(dplyr)); source("data-raw/qa/helpers.R"); R <- readRDS(qa_out("63_land_test.rds")); out <- list()
for (by in names(R)) { d <- R[[by]]$d; ok <- d$ALAND > 0
  q <- quantile(d$ratio[ok], c(0, .01, .05, .25, .5, .75, .95, .99, 1), names = FALSE)
  out[[by]] <- list(year = by, zctas = nrow(d), aland_zero = sum(!ok), invalid_zcta_polygons_repaired = R[[by]]$invalid, errors = R[[by]]$errors, water_files = R[[by]]$water_files, water_mb = R[[by]]$water_size / 1e6,
    ratio_quantiles = setNames(q, c("min", "p1", "p5", "p25", "median", "p75", "p95", "p99", "max")), within_1pct = mean(abs(d$ratio[ok] - 1) <= .01), within_5pct = mean(abs(d$ratio[ok] - 1) <= .05), within_10pct = mean(abs(d$ratio[ok] - 1) <= .1),
    worst20 = d[ok, ] %>% mutate(abs_dev = abs(ratio - 1)) %>% arrange(desc(abs_dev)) %>% head(20) %>% select(ZCTA, ALAND, AWATER, poly_m2, water_m2, land_m2, ratio),
    water_vs_awater = quantile(d$water_m2[d$AWATER > 0] / d$AWATER[d$AWATER > 0], c(.01, .05, .5, .95, .99), names = FALSE), poly_vs_land_water = quantile(d$poly_m2[ok] / (d$ALAND[ok] + d$AWATER[ok]), c(.01, .05, .5, .95, .99), names = FALSE),
    poly_vs_land_water_within_1pct = mean(abs(d$poly_m2[ok] / (d$ALAND[ok] + d$AWATER[ok]) - 1) <= .01), land_vs_poly_minus_awater_within_1pct = mean(abs(d$land_m2[ok] / (d$poly_m2[ok] - d$AWATER[ok]) - 1) <= .01)) }
saveRDS(out, qa_out("63_land_tables.rds")); print(out)
