# Run from the package root, after data-raw/dat/build_dat.R and data-raw/add_population.R:  caffeinate -i Rscript data-raw/qa/66_modeled_vs_dat.R
# Compares the modeled columns of tornado_exposure (a straight line at SPC's width) with the NWS damage polygons, for the line tornadoes that have a modeled path polygon and a linked DAT line (tornado_dat_link) with a usable damage swath.
# The comparison swath is a definition of this script, not a package dataset. For a linked DAT line it is the union of the full-resolution DAT polygons that
#   (1) cross the line (st_intersects in EPSG:4326) and are dated within one day of the line (the link window),
#   (2) have an efscale of EF0 to EF5 (the other values, such as EFU or TSTM/Wind, are not tornado damage ratings),
#   (3) have at least 90% of their area within a distance of the line equal to SPC's width plus 500 m (a polygon that mostly lies farther away belongs to another tornado of the same day),
# and the swath is usable when it lies within 200 m of at least 50% of the length of the line (so that it describes the line). The values 90%, 500 m, 200 m and 50% are comparison settings: they were chosen
# so that a polygon of another tornado is not mistaken for this one and a line with only a stray polygon is not used; a different value changes which tornadoes are compared and the ratios below, not any shipped data.
# The swath of a tornado is the union of the swaths of its usable lines. It is projected to EPSG:5070, nothing is simplified, and an invalid polygon is repaired (counted in the output). Its intersection with the ZCTAs of the
# tornado's boundary year, and the residents inside it (block populations allocated by the share of each block's area, the same method as the modeled columns), give the same quantities as the modeled columns.
# Quantities (each ratio is modeled / DAT swath; the 10th and 90th percentiles are of the ratio):
#   path_area       modeled_path_area_m2 / area of the swath, per tornado
#   area_share      modeled_area_prop / (swath intersection with the ZCTA / ZCTA polygon area), per tornado-ZCTA pair present in both
#   pop_share       modeled_pop_prop / (swath residents in the ZCTA / zcta_pop), per pair present in both with zcta_pop above 0 and swath residents above 0
#   zcta_agreement  pairs in both / pairs in either, over all tornadoes together
# Output: data-raw/qa/out/modeled_vs_dat.rds and rows modeled_vs_dat_* in data-raw/readme/numbers.csv.
suppressMessages({library(sf); library(dplyr)}); options(width = 200, tigris_use_cache = TRUE)
source("data-raw/pipeline_functions.R"); source("data-raw/population/population_functions.R"); source("data-raw/qa/helpers.R"); sf_use_s2(FALSE)
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
lg <- function(...) message(format(Sys.time(), "%H:%M:%S "), ...)
tt <- tornado_tracks; cand <- tt$tornado_id[!is.na(tt$modeled_path_area_m2)]
lk <- tornado_dat_link[tornado_dat_link$tornado_id %in% cand, c("tornado_id", "dat_line_id")]
Ls <- dat_lines[match(lk$dat_line_id, dat_lines$objectid), ]; ldate <- as.Date(Ls$stormdate_utc); Lg <- st_geometry(Ls); L5 <- st_transform(Lg, 5070); Llen <- as.numeric(st_length(L5))
Pall <- dat_polygons[!st_is_empty(dat_polygons) & !is.na(dat_polygons$stormdate), ]; nrep <- sum(!st_is_valid(Pall)); Pg <- st_geometry(Pall); P5 <- st_transform(st_make_valid(Pg), 5070); Parea <- as.numeric(st_area(P5)); Pdate <- as.Date(Pall$stormdate_utc)
hit <- st_intersects(Lg, Pg); wid <- tt$wid_yd[match(lk$tornado_id, tt$tornado_id)]; kept <- vector("list", nrow(lk)); usable <- logical(nrow(lk)); lg("candidate links: ", nrow(lk))
for (r in seq_len(nrow(lk))) { q <- hit[[r]]; q <- q[abs(as.numeric(Pdate[q] - ldate[r])) <= 1]; q <- q[Pall$efscale[q] %in% paste0("EF", 0:5)]
  if (length(q)) { buf <- st_buffer(L5[r], wid[r] * 0.9144 + 500); inb <- vapply(q, function(z) tryCatch(as.numeric(st_area(st_intersection(P5[z], buf))) / Parea[z], error = function(e) NA_real_), numeric(1)); q <- q[!is.na(inb) & inb >= 0.9] }
  if (length(q)) { u <- st_union(P5[q]); inside <- tryCatch(sum(as.numeric(st_length(st_intersection(L5[r], st_buffer(u, 200))))), error = function(e) NA_real_); if (!is.na(inside) && inside / Llen[r] >= 0.5) { usable[r] <- TRUE; kept[[r]] <- q } } }
lg("usable lines: ", sum(usable), " of ", nrow(lk))
ids <- unique(lk$tornado_id[usable]); sw <- lapply(ids, function(id) st_union(P5[unique(unlist(kept[usable & lk$tornado_id == id]))]))
swath <- st_sf(tid = ids, kind = "dat", geometry = st_sfc(do.call(c, sw), crs = 5070)); swath$area_m2 <- as.numeric(st_area(swath)); lg("swaths built: ", length(ids), "; polygons repaired: ", nrep)
yr <- as.integer(substr(ids, 1, 4)); swath$vint <- vint_of(yr)
# ZCTA intersections
pieces <- bind_rows(lapply(c(2000L, 2010L, 2020L), function(v) { s <- swath[swath$vint == v, ]; if (!nrow(s)) return(NULL); zc <- load_zctas(v)
  x <- st_collection_extract(suppressWarnings(st_intersection(s["tid"], zc)), "POLYGON"); x$a <- as.numeric(st_area(x)); x <- st_drop_geometry(x) %>% group_by(tid, ZCTA, zcta_polygon_area_m2) %>% summarise(a = sum(a), .groups = "drop"); x$vint <- v; x[x$a > 0, ] }))
lg("swath-ZCTA pairs: ", nrow(pieces))
# residents inside the swaths
states <- pop_states(); pa <- bind_rows(lapply(sort(unique(swath$vint)), function(v) { lg("population, boundary year ", v); pop_aff_cached(v, swath[swath$vint == v, c("tid", "kind")], states, zcta_layer(v)) %>% mutate(vint = v) }))
pieces <- pieces %>% left_join(pa %>% filter(!is.na(ZCTA)) %>% select(tid, ZCTA, vint, dat_pop = pop_aff), by = c("tid", "ZCTA", "vint"))
pieces$dat_pop[is.na(pieces$dat_pop)] <- 0
# compare
e <- tornado_exposure[tornado_exposure$tornado_id %in% ids & !is.na(tornado_exposure$modeled_intersection_m2), ]
a <- swath %>% st_drop_geometry() %>% mutate(path = tt$modeled_path_area_m2[match(tid, tt$tornado_id)], ratio = path / area_m2)
j <- inner_join(e, pieces, by = c("tornado_id" = "tid", "ZCTA"))
j$r_area <- j$modeled_area_prop / (j$a / j$zcta_polygon_area_m2.y)
jp <- j[j$zcta_pop > 0 & j$dat_pop > 0, ]; jp$r_pop <- jp$modeled_pop_prop / (jp$dat_pop / jp$zcta_pop)
both <- nrow(j); either <- nrow(e) + nrow(pieces) - both
q <- function(x) quantile(x, c(.1, .5, .9), names = FALSE)
R <- list(tornadoes = length(ids), candidate_links = nrow(lk), usable_links = sum(usable), polygons_repaired = nrep, pairs_both = both, pairs_modeled_only = nrow(e) - both, pairs_dat_only = nrow(pieces) - both, zcta_agreement = both / either,
          path_area = q(a$ratio), area_share = q(j$r_area), pop_share = q(jp$r_pop), n_pop_pairs = nrow(jp))
saveRDS(R, qa_out("modeled_vs_dat.rds")); print(R)
nm <- c(modeled_vs_dat_n = R$tornadoes, modeled_vs_dat_zcta_agreement_pct = 100 * R$zcta_agreement,
        modeled_vs_dat_path_area_p10 = R$path_area[1], modeled_vs_dat_path_area_median = R$path_area[2], modeled_vs_dat_path_area_p90 = R$path_area[3],
        modeled_vs_dat_area_share_p10 = R$area_share[1], modeled_vs_dat_area_share_median = R$area_share[2], modeled_vs_dat_area_share_p90 = R$area_share[3],
        modeled_vs_dat_pop_share_p10 = R$pop_share[1], modeled_vs_dat_pop_share_median = R$pop_share[2], modeled_vs_dat_pop_share_p90 = R$pop_share[3])
f <- "data-raw/readme/numbers.csv"; n <- read.csv(f, stringsAsFactors = FALSE); n <- n[!n$name %in% names(nm), ]
write.csv(rbind(n, data.frame(name = names(nm), value = unname(nm), source = "66")), f, row.names = FALSE)
