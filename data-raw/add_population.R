# Add resident population to tornado_exposure:
#   pop_affected     residents inside the path in the ZCTA, from block populations
#                    allocated by the share of each block's area inside the path
#   zcta_pop         the ZCTA's total population (sum of the blocks assigned to it)
#   pop_prop_affected pop_affected / zcta_pop (NA when zcta_pop is 0)
#
# Run from the package root after data-raw/process_tracks.R:
#   Rscript data-raw/add_population.R
# Vintage rule: 2000 blocks for years before 2010, 2010 for 2010-2019, 2020 from 2020.
# Downloads (about 24 GB) are cached outside the repository (see pop_cache());
# per-state results are cached so an interrupted run resumes. Environment
# variables for tests: POP_STATES=ri,mo (restrict states), POP_VINTAGES=2010,
# POP_WRITE=false (do not touch data/).

source("data-raw/population/population_functions.R")
source("R/path_polygon.R")
env_states <- Sys.getenv("POP_STATES", "")
env_vint <- Sys.getenv("POP_VINTAGES", "")
write_data <- !identical(tolower(Sys.getenv("POP_WRITE", "true")), "false")

load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda")
exposure <- tornado_exposure[, setdiff(names(tornado_exposure), c("pop_affected", "zcta_pop", "pop_prop_affected"))]
yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4))
vint_of <- function(y) ifelse(y < 2010, 2000L, ifelse(y < 2020, 2010L, 2020L))

# targets: modeled path polygons for every tornado (the surveyed swaths of the survey layer get their population in data-raw/survey/build_survey.R)
poly <- .path_polygon(tornado_tracks, tornado_tracks$wid_yd, tornado_tracks$len_mi, tornado_tracks$track_type)
targets <- sf::st_sf(tid = tornado_tracks$tornado_id, kind = "modeled", vint = vint_of(yr), geometry = poly)
message("targets: ", nrow(targets), " (", sum(targets$kind == "modeled"), " modeled, ", sum(targets$kind == "survey"), " survey)")

states <- pop_states()
if (nzchar(env_states)) states <- states[states$abb %in% strsplit(env_states, ",")[[1]], ]
vintages <- if (nzchar(env_vint)) as.integer(strsplit(env_vint, ",")[[1]]) else c(2020L, 2010L, 2000L)

for (v in vintages) {
  zl <- zcta_layer(v)
  tv <- targets[targets$vint == v, c("tid", "kind")]
  for (i in seq_len(nrow(states))) {
    st <- states[i, ]
    f <- pop_cache("work", sprintf("%s_%s.rds", v, st$state_code))
    if (file.exists(f)) next
    t0 <- Sys.time()
    res <- tryCatch(process_state(v, st, tv, zl), error = function(e) { message("FAILED ", v, " ", st$state, ": ", conditionMessage(e)); NULL })
    if (is.null(res)) next
    saveRDS(res, f)
    message(sprintf("%s %s done in %.1f min (%d blocks)", v, st$state, as.numeric(Sys.time() - t0, units = "mins"), res$summary$blocks))
  }
}

# ---- combine ------------------------------------------------------------------
load_work <- function(v) lapply(seq_len(nrow(states)), function(i) { f <- pop_cache("work", sprintf("%s_%s.rds", v, states$state_code[i])); if (file.exists(f)) readRDS(f) else NULL })
all_done <- all(unlist(lapply(vintages, function(v) vapply(states$state_code, function(fp) file.exists(pop_cache("work", sprintf("%s_%s.rds", v, fp))), logical(1)))))
zcta_pop <- list(); pop_aff <- list(); sums <- list()
for (v in vintages) {
  w <- Filter(Negate(is.null), load_work(v))
  zb <- dplyr::bind_rows(lapply(w, function(x) x$blocks))
  zcta_pop[[as.character(v)]] <- zb %>% dplyr::filter(!is.na(ZCTA)) %>% dplyr::group_by(ZCTA) %>% dplyr::summarise(zcta_pop = sum(pop, na.rm = TRUE), .groups = "drop") %>% dplyr::mutate(vint = v)
  pop_aff[[as.character(v)]] <- dplyr::bind_rows(lapply(w, function(x) x$pop_aff)) %>% dplyr::group_by(tid, kind, ZCTA) %>% dplyr::summarise(pop_aff = sum(pop_aff), .groups = "drop") %>% dplyr::mutate(vint = v)
  sums[[as.character(v)]] <- dplyr::bind_rows(lapply(w, function(x) x$summary))
}
zcta_pop <- dplyr::bind_rows(zcta_pop); pop_aff <- dplyr::bind_rows(pop_aff); sums <- dplyr::bind_rows(sums)
dir.create("data-raw/qa/out", recursive = TRUE, showWarnings = FALSE)
saveRDS(list(zcta_pop = zcta_pop, pop_aff = pop_aff, summary = sums), "data-raw/qa/out/population_results.rds")
message("block summary rows: ", nrow(sums))
if (!all_done) { message("Not all states processed for the requested vintages; data/ not updated."); quit(save = "no") }

# ---- attach to tornado_exposure -------------------------------------------------
e <- exposure
e$vint <- vint_of(e$year)
m <- pop_aff %>% dplyr::filter(kind == "modeled", !is.na(ZCTA)) %>% dplyr::select(tornado_id = tid, vint, ZCTA, pop_affected = pop_aff)
e <- e %>% dplyr::left_join(m, by = c("tornado_id", "vint", "ZCTA")) %>% dplyr::left_join(zcta_pop %>% dplyr::select(vint, ZCTA, zcta_pop), by = c("vint", "ZCTA"))
e$pop_affected[is.na(e$pop_affected)] <- 0
e$zcta_pop[is.na(e$zcta_pop)] <- 0
e$pop_prop_affected <- ifelse(e$zcta_pop > 0, e$pop_affected / e$zcta_pop, NA_real_)
message("zcta_pop == 0 rows: ", sum(e$zcta_pop == 0), "; pop_prop_affected NA: ", sum(is.na(e$pop_prop_affected)))
e$vint <- NULL
e <- e[, c("tornado_id", "date", "year", "month", "day", "magnitude", "total_injury", "total_fatality",
           "property_loss_tornado_total", "property_loss_allocated", "ZCTA", "area_prop_affected",
           "pop_affected", "zcta_pop", "pop_prop_affected", "area_share_of_tornado", "track_type")]
tornado_exposure <- as.data.frame(e)
if (write_data) usethis::use_data(tornado_exposure, overwrite = TRUE, compress = "xz")

# ---- provenance: URLs, sizes and checksums of everything downloaded ----------------
rec <- read.csv(pop_cache("downloads_record.csv"), stringsAsFactors = FALSE)
rec <- rec[order(rec$url), ]
write.csv(rec, "data-raw/provenance_population.csv", row.names = FALSE)
prov <- readLines("data-raw/provenance.txt")
i <- which(prov == "## Population sources")[1]
if (!is.na(i)) prov <- prov[seq_len(i - 1)]
vsum <- sums
writeLines(c(prov, "## Population sources",
  paste("Run date:", format(Sys.Date())),
  "2020: TIGER/Line 2020 tabulation blocks (TABBLOCK20), population from field POP20",
  "2010 and 2000: TIGER/Line tabulation blocks (TABBLOCK/2010, TABBLOCK/2000) with total population from the Census PL 94-171 redistricting files",
  paste0("Downloads: ", nrow(rec), " files, ", round(sum(rec$bytes) / 1e9, 1), " GB; every URL, size and md5 is in data-raw/provenance_population.csv (md5 of that file: ", unname(tools::md5sum("data-raw/provenance_population.csv")), ")"),
  paste0("Areas processed per vintage: ", paste(names(table(vsum$vintage)), table(vsum$vintage), sep = " = ", collapse = ", "), " (50 states, DC and Puerto Rico)"),
  paste0("Block population totals match the PL 94-171 state totals for ", sum(vsum$vintage != 2020 & vsum$pop_sum == vsum$state_total_pl, na.rm = TRUE), " of ", sum(vsum$vintage != 2020), " state-vintage files (2010 and 2000)")),
  "data-raw/provenance.txt")
