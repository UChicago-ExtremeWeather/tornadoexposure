# Run from the package root after data-raw/add_population.R has finished:
#   Rscript data-raw/qa/18_pop_block_group_sensitivity.R
# For tornadoes from 2020 on, compares the residents in the modeled path computed
# from blocks (as in the package) with the same calculation from block groups
# (each block group's population allocated by area share), which is less affected
# by the noise the Census Bureau adds to 2020 block counts (differential privacy)
# and shows how much the uniform-density assumption matters.
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R"); source("R/path_polygon.R")
suppressMessages({library(dplyr); library(sf)})
R <- readRDS(qa_out("population_results.rds"))
blk <- R$pop_aff %>% filter(kind == "modeled", vint == 2020) %>% group_by(tid) %>% summarise(block_pop = sum(pop_aff), .groups = "drop")
load("data/tornado_tracks.rda")
yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4)); tt <- tornado_tracks[yr >= 2020, ]
poly <- .path_polygon(tt, tt$wid_yd, tt$len_mi, tt$track_type)
tg <- st_sf(tid = tt$tornado_id, geometry = poly); tg4 <- st_transform(tg, 4269)
states <- pop_states(); out <- list()
for (i in seq_len(nrow(states))) { st <- states[i, ]
  url <- sprintf("https://www2.census.gov/geo/tiger/TIGER2020/BG/tl_2020_%s_bg.zip", st$state_code)
  zip <- tryCatch(download_cached(url, record = TRUE), error = function(e) NULL); if (is.null(zip)) next
  td <- tempfile(); dir.create(td); unzip(zip, exdir = td); bg <- read_sf(list.files(td, pattern = "\\.shp$", full.names = TRUE))
  bg <- bg[, "GEOID"]
  fl <- pop_cache("work", sprintf("2020_%s.rds", st$state_code)); if (!file.exists(fl)) next
  bp <- readRDS(fl)$blocks %>% mutate(bgid = substr(GEOID, 1, 12)) %>% group_by(bgid) %>% summarise(pop = sum(pop, na.rm = TRUE), .groups = "drop")
  bg$pop <- bp$pop[match(bg$GEOID, bp$bgid)]; bg$pop[is.na(bg$pop)] <- 0
  bbx <- st_as_sfc(st_bbox(bg)); near <- lengths(st_intersects(tg4, bbx)) > 0
  if (any(near)) { cand <- bg[lengths(st_intersects(bg, st_union(st_geometry(tg4[near, ])))) > 0, ]
    if (nrow(cand)) { c5 <- st_make_valid(st_transform(cand, 5070)); c5$a <- as.numeric(st_area(c5)); c5$id <- seq_len(nrow(c5))
      x <- suppressWarnings(st_intersection(tg[near, "tid"], c5[, c("id", "pop", "a")])); x <- st_collection_extract(x, "POLYGON")
      x$a_in <- as.numeric(st_area(x)); x <- st_drop_geometry(x)
      out[[length(out) + 1]] <- x %>% mutate(pop_aff = pop * pmin(a_in / a, 1)) %>% group_by(tid) %>% summarise(bg_pop = sum(pop_aff), .groups = "drop") } }
  unlink(td, recursive = TRUE); message(st$state, " done") }
bgp <- bind_rows(out) %>% group_by(tid) %>% summarise(bg_pop = sum(bg_pop), .groups = "drop")
g <- tt %>% st_drop_geometry() %>% select(tid = tornado_id, track_type) %>% left_join(blk, by = "tid") %>% left_join(bgp, by = "tid") %>% mutate(block_pop = coalesce(block_pop, 0), bg_pop = coalesce(bg_pop, 0))
cat("tornadoes from 2020 on:", nrow(g), "; with block-based population > 0:", sum(g$block_pop > 0), "; with block-group-based > 0:", sum(g$bg_pop > 0), "\n")
cat(sprintf("total residents: blocks %s, block groups %s (ratio %.3f)\n", format(round(sum(g$block_pop)), big.mark = ","), format(round(sum(g$bg_pop)), big.mark = ","), sum(g$bg_pop) / sum(g$block_pop)))
for (th in c(1, 100, 1000)) { s <- g %>% filter(block_pop >= th); r <- s$bg_pop / s$block_pop
  cat(sprintf("tornadoes with block-based population >= %d (n = %d): block-group/block ratio quantiles 5/25/50/75/95%%: %s; within 10%%: %.1f%%; within 25%%: %.1f%%; within a factor of 2: %.1f%%; Spearman %.3f\n", th, nrow(s), paste(signif(quantile(r, c(.05, .25, .5, .75, .95)), 3), collapse = " "), 100 * mean(abs(r - 1) <= .1), 100 * mean(abs(r - 1) <= .25), 100 * mean(r >= .5 & r <= 2), cor(s$block_pop, s$bg_pop, method = "spearman"))) }
saveRDS(g, qa_out("pop_block_group_sensitivity.rds"))
