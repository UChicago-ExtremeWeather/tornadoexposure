# Block population cache and provenance. For every boundary year (2000, 2010, 2020) and every state (50 states, DC and Puerto Rico) this reads the Census
# tabulation blocks and their population, assigns every block to a ZCTA through its internal point, and stores the result outside the repository
# (see pop_cache()). data-raw/add_centroids.R (zcta_pop and the population-weighted centroids) and data-raw/dat/build_dat_exposure.R (residents inside
# the DAT footprints) read that cache. A state that is already cached is not processed again.
#
# Run from the package root:  Rscript data-raw/add_population.R
# Sources (no key or account needed): 2020, TIGER/Line tabulation blocks (field POP20); 2010 and 2000, tabulation blocks plus the Census PL 94-171
# redistricting files (total population by block). About 24 GB are downloaded for all states and boundary years (manifest: data-raw/provenance_population.csv).
# Environment variable: POP_VINTAGES=2010 (restrict boundary years).
# Stop conditions (nothing is imputed or dropped without the maintainer's approval): a block with an NA population, a duplicated GEOID in a block file.

source("data-raw/population/population_functions.R")
env_vint <- Sys.getenv("POP_VINTAGES", "")
states <- pop_states()
vintages <- if (nzchar(env_vint)) as.integer(strsplit(env_vint, ",")[[1]]) else c(2020L, 2010L, 2000L)
for (v in vintages) {
  zl <- NULL
  for (i in seq_len(nrow(states))) {
    st <- states[i, ]; wf <- pop_cache("work", sprintf("%s_%s.rds", v, st$state_code))
    if (file.exists(wf)) next
    if (is.null(zl)) zl <- zcta_layer(v)
    message(v, " ", st$state, ": processing")
    res <- process_state(v, st, zl); saveRDS(res, wf)
  }
}
sums <- dplyr::bind_rows(lapply(c(2000L, 2010L, 2020L), function(v) dplyr::bind_rows(lapply(states$state_code, function(fp) readRDS(pop_cache("work", sprintf("%s_%s.rds", v, fp)))$summary))))
saveRDS(sums, "data-raw/qa/out/population_summary.rds")
bad <- sums[sums$pop_na > 0, ]
if (nrow(bad)) stop("Blocks with NA population: ", sum(bad$pop_na), ". NA stays NA and the build stops.", call. = FALSE)

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
