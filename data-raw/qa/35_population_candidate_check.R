# Run from the package root: Rscript data-raw/qa/35_population_candidate_check.R
# Checks that the candidate-block test of pop_aff_cached() (paths buffered by 5 km) misses no block: for the 25 longest tracks,
# 100 random line tracks of 10 miles or more, 25 random shorter lines and 25 point tracks, it recomputes the residents with NO candidate
# test (every block in the 5 km-buffered bounding box of the paths is intersected) and compares with tornado_exposure.
suppressMessages({library(sf); library(dplyr)})
source("R/path_polygon.R"); load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda"); source("data-raw/population/population_functions.R")
set.seed(7)
top <- tornado_tracks$tornado_id[order(-tornado_tracks$len_mi)][1:25]
line <- which(!is.na(tornado_tracks$modeled_path_area_m2)); lg <- line[tornado_tracks$len_mi[line] >= 10]; sh <- line[tornado_tracks$len_mi[line] < 10]   # lines with a modeled path polygon
sel <- unique(c(match(top, tornado_tracks$tornado_id), sample(lg, 100), sample(sh, 25)))
sel <- sel[!is.na(tornado_tracks$modeled_path_area_m2[sel])]
tr <- tornado_tracks[sel, ]; yr <- as.integer(substr(tr$tornado_id, 1, 4)); vint <- ifelse(yr < 2010, 2000L, ifelse(yr < 2020, 2010L, 2020L))
poly <- .path_polygon(tr, tr$wid_yd); tg <- st_sf(tid = tr$tornado_id, kind = "modeled", geometry = poly)
states <- pop_states(); pa <- bind_rows(lapply(c(2020L, 2010L, 2000L), function(v) pop_aff_cached(v, tg[vint == v, ], states, zcta_layer(v), all_blocks = TRUE) %>% mutate(vint = v)))
pa <- pa %>% filter(!is.na(ZCTA)) %>% select(tornado_id = tid, vint, ZCTA, all_blocks = pop_aff)
e <- tornado_exposure[tornado_exposure$tornado_id %in% tr$tornado_id, c("tornado_id", "year", "ZCTA", "modeled_pop_affected")]; e$vint <- ifelse(e$year < 2010, 2000L, ifelse(e$year < 2020, 2010L, 2020L))
m <- e %>% left_join(pa, by = c("tornado_id", "vint", "ZCTA")); m$all_blocks[is.na(m$all_blocks)] <- 0
cat("tornadoes checked:", nrow(tr), "; rows compared:", nrow(m), "; largest absolute difference (residents):", signif(max(abs(m$all_blocks - m$modeled_pop_affected)), 3), "; rows differing by more than 1e-6:", sum(abs(m$all_blocks - m$modeled_pop_affected) > 1e-6), "\n")
dir.create("data-raw/qa/out", showWarnings = FALSE)
saveRDS(list(tornadoes = nrow(tr), rows = nrow(m), max_abs_diff = max(abs(m$all_blocks - m$modeled_pop_affected)), n_differ = sum(abs(m$all_blocks - m$modeled_pop_affected) > 1e-6),
             n_longest = length(top), n_long = 100, n_short = 25, n_point = 25), "data-raw/qa/out/pop_candidate_check.rds")
