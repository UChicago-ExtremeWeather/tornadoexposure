# Add resident population to tornado_exposure, for the rows with a modeled path polygon:
#   modeled_pop_affected  residents inside the modeled path in the ZCTA, from block populations
#                         allocated by the share of each block's area inside the path (uncapped)
#   modeled_pop_prop      modeled_pop_affected / zcta_pop (NA when zcta_pop is 0)
# Rows without a modeled path polygon (tornadoes with no usable end point, lines with a width of 0 or missing) keep NA.
# zcta_pop (the ZCTA's total population, the sum of the blocks assigned to it) comes from zcta_centroids.
#
# Run from the package root after data-raw/add_centroids.R and data-raw/process_tracks.R:
#   Rscript data-raw/add_population.R
# One vintage per process can run at the same time (POP_VINTAGES=2020, 2010 or 2000); the last one to finish combines them.
# Vintage rule: 2000 blocks for years before 2010, 2010 for 2010-2019, 2020 from 2020.
# The per-state block results (block population and the block-to-ZCTA assignment) are cached outside the repository (see pop_cache()) by the
# first full build of a vintage; the block geometries are read again only where the paths are. A state missing from the cache is processed
# in full (downloads about 24 GB for all states and vintages; manifest in data-raw/provenance_population.csv).
# Environment variables: POP_VINTAGES=2010 (restrict vintages), POP_WRITE=false (do not touch data/).

source("data-raw/population/population_functions.R")
source("R/path_polygon.R")
env_vint <- Sys.getenv("POP_VINTAGES", "")
write_data <- !identical(tolower(Sys.getenv("POP_WRITE", "true")), "false")

load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda"); load("data/zcta_centroids.rda")
vint_of <- function(y) ifelse(y < 2010, 2000L, ifelse(y < 2020, 2010L, 2020L))
yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4))

# targets: modeled path polygons of the line tornadoes with a positive width
hp <- !is.na(tornado_tracks$modeled_path_area_m2)
poly <- .path_polygon(tornado_tracks[hp, ], tornado_tracks$wid_yd[hp])
targets <- sf::st_sf(tid = tornado_tracks$tornado_id[hp], kind = "modeled", vint = vint_of(yr[hp]), geometry = poly)
message("targets: ", nrow(targets), " modeled path polygons")

states <- pop_states()
vintages <- if (nzchar(env_vint)) as.integer(strsplit(env_vint, ",")[[1]]) else c(2020L, 2010L, 2000L)
dir.create("data-raw/qa/out", recursive = TRUE, showWarnings = FALSE)
for (v in vintages) {
  f <- sprintf("data-raw/qa/out/pop_aff_%s.rds", v)
  if (file.exists(f)) next
  t0 <- Sys.time()
  res <- pop_aff_cached(v, targets[targets$vint == v, c("tid", "kind")], states, zcta_layer(v))
  attr(res, "frac_stats") <- as.list(pop_frac_stats)   # path-block pieces, pieces with a share above 1 (within 1e-9), largest share
  saveRDS(res, f)
  message(sprintf("%s done in %.1f min (%d tornado-ZCTA sums)", v, as.numeric(Sys.time() - t0, units = "mins"), nrow(res)))
}
fs <- sprintf("data-raw/qa/out/pop_aff_%s.rds", c(2000, 2010, 2020))
if (!all(file.exists(fs))) { message("Not all vintages are done; data/ not updated."); quit(save = "no") }

# ---- attach to tornado_exposure -------------------------------------------------
pop_aff <- dplyr::bind_rows(Map(function(f, v) { x <- readRDS(f); x$vint <- v; x }, fs, c(2000L, 2010L, 2020L)))
e <- tornado_exposure
e$vint <- vint_of(e$year)
m <- pop_aff %>% dplyr::filter(!is.na(ZCTA)) %>% dplyr::select(tornado_id = tid, vint, ZCTA, pop = pop_aff)
n_lost <- sum(pop_aff$pop_aff[!is.na(pop_aff$ZCTA)]) - sum(m$pop[paste(m$tornado_id, m$ZCTA) %in% paste(e$tornado_id, e$ZCTA)])
e <- e %>% dplyr::left_join(m, by = c("tornado_id", "vint", "ZCTA"))
shaped <- !is.na(e$modeled_intersection_m2)
e$modeled_pop_affected <- ifelse(shaped, ifelse(is.na(e$pop), 0, e$pop), NA_real_)
e$modeled_pop_prop <- ifelse(shaped & e$zcta_pop > 0, e$modeled_pop_affected / e$zcta_pop, NA_real_)
message("modeled rows with zcta_pop == 0: ", sum(shaped & e$zcta_pop == 0), "; residents allocated to a ZCTA that the path polygon does not overlap (not in the table): ", round(n_lost, 1))
message("modeled_pop_prop above 1 (not capped): ", sum(e$modeled_pop_prop > 1, na.rm = TRUE), "; largest ", max(e$modeled_pop_prop, na.rm = TRUE))
e$vint <- NULL; e$pop <- NULL
tornado_exposure <- as.data.frame(e[, names(tornado_exposure)])
sums <- dplyr::bind_rows(lapply(c(2000L, 2010L, 2020L), function(v) dplyr::bind_rows(lapply(states$state_code, function(fp) readRDS(pop_cache("work", sprintf("%s_%s.rds", v, fp)))$summary))))   # one row per state and boundary year, from the cached block results
saveRDS(list(pop_aff = pop_aff, summary = sums, lost = n_lost, frac_stats = lapply(fs, function(f) attr(readRDS(f), "frac_stats"))), "data-raw/qa/out/population_results.rds")
if (write_data) usethis::use_data(tornado_exposure, overwrite = TRUE, compress = "xz")

# ---- provenance: URLs, sizes and checksums of everything downloaded ----------------
rec <- read.csv(pop_cache("downloads_record.csv"), stringsAsFactors = FALSE)
rec <- rec[order(rec$url), ]
write.csv(rec, "data-raw/provenance_population.csv", row.names = FALSE)
prov <- readLines("data-raw/provenance.txt")
i <- which(prov == "## Population sources")[1]
if (!is.na(i)) prov <- prov[seq_len(i - 1)]
writeLines(c(prov, "## Population sources",
  paste0("Downloaded: ", min(rec$date), " to ", max(rec$date), " (the date of each file is in data-raw/provenance_population.csv); this table was computed on ", format(Sys.Date())),
  "2020: TIGER/Line 2020 tabulation blocks (TABBLOCK20), population from field POP20",
  "2010 and 2000: TIGER/Line tabulation blocks (TABBLOCK/2010, TABBLOCK/2000) with total population from the Census PL 94-171 redistricting files",
  paste0("Downloads: ", nrow(rec), " files, ", round(sum(rec$bytes) / 1e9, 1), " GB; every URL, size and md5 is in data-raw/provenance_population.csv (md5 of that file: ", unname(tools::md5sum("data-raw/provenance_population.csv")), ")"),
  paste0("Areas processed per boundary year: ", paste(names(table(sums$vintage)), table(sums$vintage), sep = " = ", collapse = ", "), " (50 states, DC and Puerto Rico)"),
  paste0("Block population totals match the PL 94-171 state totals for ", sum(sums$vintage != 2020 & sums$pop_sum == sums$state_total_pl, na.rm = TRUE), " of ", sum(sums$vintage != 2020), " state-year files (2010 and 2000)")),
  "data-raw/provenance.txt")
