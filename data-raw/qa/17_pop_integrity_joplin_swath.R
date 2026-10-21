# Run from the package root after data-raw/add_population.R has finished:
#   Rscript data-raw/qa/17_pop_integrity_joplin_swath.R
# (d) integrity of pop_affected / zcta_pop / pop_prop_affected, (e) Joplin and how its
# population estimate changes if the straight path is shifted sideways.

source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R"); source("R/path_polygon.R")
suppressMessages({library(dplyr); library(sf)})
R <- readRDS(qa_out("population_results.rds")); pa <- R$pop_aff; zp <- R$zcta_pop
load("data/tornado_tracks.rda")
e <- if (file.exists("data-raw/qa/out/tornado_exposure_pop.rds")) readRDS("data-raw/qa/out/tornado_exposure_pop.rds") else { load("data/tornado_exposure.rda"); tornado_exposure }
cat("== (d) integrity ==\n")
cat("rows:", nrow(e), "; columns:", paste(names(e), collapse = ", "), "\n")
stopifnot(all(c("pop_affected", "zcta_pop", "pop_prop_affected") %in% names(e)))
cat("pop_affected <= zcta_pop (tolerance 1e-6):", all(e$pop_affected <= e$zcta_pop + 1e-6), "; violations:", sum(e$pop_affected > e$zcta_pop + 1e-6), "\n")
cat("pop_prop_affected in [0, 1]:", all(e$pop_prop_affected >= 0 & e$pop_prop_affected <= 1 + 1e-9, na.rm = TRUE), "; NA:", sum(is.na(e$pop_prop_affected)), "(zcta_pop == 0 rows:", sum(e$zcta_pop == 0), ")\n")
cat("pop_affected: min", min(e$pop_affected), "; rows with pop_affected == 0:", sum(e$pop_affected == 0), sprintf("(%.1f%%)", 100 * mean(e$pop_affected == 0)), "\n")
cat("pop_prop_affected quantiles (non-NA):", paste(signif(quantile(e$pop_prop_affected, c(.01, .05, .25, .5, .75, .9, .99, 1), na.rm = TRUE), 3), collapse = " "), "\n")
for (th in c(.01, .05, .1, .5)) cat(sprintf("rows with pop_prop_affected >= %s: %d (%.2f%%)\n", th, sum(e$pop_prop_affected >= th, na.rm = TRUE), 100 * mean(e$pop_prop_affected >= th, na.rm = TRUE)))
# per tornado: sum of pop_affected across exposure rows + residents in blocks assigned to no ZCTA + residents in ZCTAs without an area-intersection row = path population
m <- pa %>% filter(kind == "modeled")
tot <- m %>% group_by(tid) %>% summarise(path_pop = sum(pop_aff), no_zcta = sum(pop_aff[is.na(ZCTA)]), .groups = "drop")
inexp <- e %>% group_by(tornado_id) %>% summarise(in_rows = sum(pop_affected), .groups = "drop")
chk <- tot %>% left_join(inexp, by = c("tid" = "tornado_id")) %>% mutate(in_rows = coalesce(in_rows, 0), other = path_pop - no_zcta - in_rows)
cat(sprintf("\ntornadoes with block results: %d; path population (all): %s\n", nrow(chk), format(round(sum(chk$path_pop)), big.mark = ",")))
cat(sprintf("per tornado: path population = exposure rows + blocks in no ZCTA + other; 'other' (residents in a ZCTA the area calculation did not list for that tornado): %d tornadoes with |other| > 0.5 residents, total %.1f residents (max %.1f)\n", sum(abs(chk$other) > .5), sum(chk$other), max(chk$other)))
cat(sprintf("residents in blocks assigned to no ZCTA: %.1f in %d tornadoes (max %.1f)\n", sum(chk$no_zcta), sum(chk$no_zcta > 0), max(chk$no_zcta)))
cat("rows in the exposure table whose pop_affected is not in the pop table:", sum(!paste(e$tornado_id, e$ZCTA) %in% paste(m$tid[!is.na(m$ZCTA)], m$ZCTA[!is.na(m$ZCTA)]) & e$pop_affected > 0), "\n")
cat("\n== (e) Joplin 2011_1105221634-01 ==\n")
j <- e %>% filter(tornado_id == "2011_1105221634-01") %>% select(ZCTA, area_prop_affected, area_share_of_tornado, pop_affected, zcta_pop, pop_prop_affected); print(as.data.frame(j), row.names = FALSE)
cat(sprintf("path population (modeled): %.0f; in the three ZCTAs: %.0f; in blocks assigned to no ZCTA: %.0f\n", chk$path_pop[chk$tid == "2011_1105221634-01"], sum(j$pop_affected), chk$no_zcta[chk$tid == "2011_1105221634-01"]))
# shift the straight path sideways and recompute the population in it (2010 blocks of Missouri)
jt <- tornado_tracks[tornado_tracks$tornado_id == "2011_1105221634-01", ]
poly <- .path_polygon(jt, jt$wid_yd, jt$len_mi, jt$track_type)[[1]] %>% st_sfc(crs = 5070)
ln <- st_transform(st_geometry(jt), 5070); cc <- st_coordinates(ln)[, 1:2]; dir <- (cc[2, ] - cc[1, ]) / sqrt(sum((cc[2, ] - cc[1, ])^2)); nrm <- c(-dir[2], dir[1])
states <- pop_states(); mo <- states[states$abb == "mo", ]; b <- read_blocks(2010, mo$state_code, mo$dir_name, mo$abb); b5 <- st_make_valid(st_transform(b, 5070)); b5$a <- as.numeric(st_area(b5))
pop_in <- function(p) { cand <- b5[lengths(st_intersects(b5, p)) > 0, ]; x <- suppressWarnings(st_intersection(cand["pop"], p)); x <- st_collection_extract(x, "POLYGON"); sum(ifelse(is.na(x$pop), 0, x$pop) * pmin(as.numeric(st_area(x)) / cand$a[match(seq_len(nrow(x)), seq_len(nrow(x)))], 1)) }
pop_in2 <- function(p) { cand <- b5[lengths(st_intersects(b5, p)) > 0, ]; cand$id <- seq_len(nrow(cand)); x <- suppressWarnings(st_intersection(cand["id"], p)); x <- st_collection_extract(x, "POLYGON"); a_in <- tapply(as.numeric(st_area(x)), x$id, sum); id <- as.integer(names(a_in)); sum(ifelse(is.na(cand$pop[id]), 0, cand$pop[id]) * pmin(a_in / cand$a[id], 1)) }
shifts <- seq(-4000, 4000, by = 500)
sens <- data.frame(shift_km = shifts / 1000, pop = vapply(shifts, function(s) pop_in2(st_sfc(poly[[1]] + nrm * s, crs = 5070)), numeric(1)))
cat("population in the modeled Joplin path polygon when shifted sideways (positive = to the left of the direction of travel, about north):\n"); print(sens %>% mutate(pop = round(pop)), row.names = FALSE)
cat(sprintf("unshifted %.0f; maximum %.0f at a shift of %.1f km; ratio %.2f\n", sens$pop[sens$shift_km == 0], max(sens$pop), sens$shift_km[which.max(sens$pop)], max(sens$pop) / sens$pop[sens$shift_km == 0]))
saveRDS(sens, qa_out("pop_joplin_shift.rds"))
