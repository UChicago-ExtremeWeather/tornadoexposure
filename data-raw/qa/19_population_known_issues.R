# Run from the package root after 14 to 16, 52b, 63 and data-raw/dat/build_dat_exposure.R: Rscript data-raw/qa/19_population_known_issues.R
# Writes the "Population" section of data-raw/known_issues.md from the saved
# validation results (every number computed, nothing typed in).
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr)})
fmt <- function(x, d = 2) formatC(x, format = "f", digits = d, big.mark = ","); pct <- function(x, d = 1) paste0(formatC(100 * x, format = "f", digits = d), "%"); nf <- function(x) formatC(round(x), format = "d", big.mark = ",")
load("data/tornado_exposure.rda")
S <- readRDS(qa_out("population_summary.rds"))
a <- readRDS(qa_out("pop_block_zcta_2020.rds")); z <- readRDS(qa_out("pop_zcta_totals.rds"))
wb <- bind_rows(lapply(list.files(qa_out(""), pattern = "^pop_whole_block_.*\\.rds$", full.names = TRUE), readRDS))
# --- sources and block assignment
tab <- a$tab; same <- tab$blocks[tab$cat == "same ZCTA"]; both_un <- tab$blocks[tab$cat == "both unassigned"]; nb <- sum(tab$blocks)
mism <- sum(tab$blocks[!tab$cat %in% c("same ZCTA", "both unassigned")]); mism_pop <- sum(tab$pop[!tab$cat %in% c("same ZCTA", "both unassigned")])
v <- S %>% group_by(vintage) %>% summarise(blocks = sum(blocks), pop = sum(pop_sum), no_zcta_blocks = sum(blocks_no_zcta), no_zcta_pop = sum(pop_no_zcta), pop_na = sum(pop_na), .groups = "drop")
vt <- v %>% transmute(Vintage = vintage, Blocks = nf(blocks), `Resident population in the blocks` = nf(pop), `Blocks assigned to no ZCTA` = paste0(nf(no_zcta_blocks), " (", pct(no_zcta_blocks / blocks, 2), ")"), `Residents in those blocks` = paste0(nf(no_zcta_pop), " (", pct(no_zcta_pop / pop, 3), ")"))
md <- function(df) paste(c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"), apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))), collapse = "\n")
zt <- function(m, v) paste0(nf(nrow(m)), " ZCTAs compared; identical `zcta_pop` for ", nf(sum(m$diff == 0)), " (", pct(mean(m$diff == 0), 3), "); largest absolute difference ", nf(max(abs(m$diff))), " residents; total difference ", nf(sum(m$diff)), " residents")
wbt <- wb %>% transmute(Vintage = vintage, State = toupper(state), `Blocks sampled` = nf(sampled), `Assigned to a ZCTA` = nf(assigned), `Assigned: at least 99% of area inside the ZCTA` = pct(own_ge99, 2), `Assigned: minimum share inside` = fmt(own_min, 3), `Unassigned: blocks sampled` = nf(unassigned), `Unassigned: share with at most 1% of area inside any ZCTA` = ifelse(is.na(unassigned_le1), "n/a", pct(unassigned_le1, 1))) %>% arrange(Vintage, State)
e <- tornado_exposure[tornado_exposure$dat_linked, ]; ds <- readRDS("data-raw/dat/fetch/exposure_summary_tables.rds"); sl <- readRDS("data-raw/dat/fetch/exposure_summary.rds")
lp <- readRDS(qa_out("63_land_report.rds"))
bq <- lp$blocks$by_vint; nz <- function(x) sum(vapply(x, function(v) v, numeric(1)))
txt <- paste0('<!-- population:start -->
## Population (`zcta_pop`, `dat_pop_affected` and the tract and block-group residents)

`zcta_pop` is the sum of the populations of the census blocks assigned to a ZCTA (total population, all ages), with blocks assigned to ZCTAs by their internal points. `dat_pop_affected` and its parts by rating are the residents in the land covered by the linked NWS polygons: each block keeps its population, which is allocated by the share of the block\'s land-only shape that the polygons cover (uniform density on the land of a block), and the residents of the blocks assigned to a ZCTA are added up. Tract and block-group residents are the sums over the blocks of the unit (the first 11 or 12 digits of the block GEOID). Population is fixed at the census year within each decade (2000 blocks for years before 2010, 2010 blocks for 2010 to 2019, 2020 blocks from 2020). Sources: TIGER/Line tabulation blocks, with population from field `POP20` (2020) or the Census PL 94-171 redistricting files (2010 and 2000); URLs, sizes and checksums are in `data-raw/provenance_population.csv`.

', md(vt), '

**Block-to-ZCTA assignment against the official 2020 relationship file.** Of ', nf(nb), ' blocks in the 50 states, DC and Puerto Rico, ', nf(same), ' have the same ZCTA in the Census Bureau\'s 2020 ZCTA-to-block relationship file and our assignment, ', nf(both_un), ' are assigned to no ZCTA in both, and ', nf(mism), ' disagree (', fmt(mism_pop, 0), ' residents). `zcta_pop` is identical under both assignments for ', pct(mean(a$z$diff == 0), 2), ' of the ', nf(nrow(a$z)), ' ZCTAs.

**`zcta_pop` against official ZCTA populations** (Census Gazetteer files, which need no API key; the 2020 Gazetteer has no population and the API needs a key, so 2020 is checked only through the relationship file above). 2010: ', zt(z$m2010), '. 2000: ', zt(z$m2000), '.

**Whole-block and internal-point checks.** ZCTAs are built from whole blocks, so a block assigned to a ZCTA by its internal point should lie almost entirely inside it, and a block assigned to none should lie outside every ZCTA. Random samples of blocks:

', md(wbt), '

**Blocks whose internal point lies in two ZCTAs.** ', nf(sum(vapply(c(2000, 2010, 2020), function(v) sum(readRDS(qa_out(sprintf('block_audit_%s.rds', v)))$blocks_in_more_than_one_zcta), 0))), ' blocks (all blocks of the three boundary years, `52b_block_validity_duplicates.R`) have an internal point on the boundary of two ZCTAs; the assignment keeps the first ZCTA (`!duplicated(GEOID)`), which the fidelity rule does not allow without approval, so it is reported (section What is and is not done to the source data).

**Integrity of the residents.** For the ', nf(nrow(e)), ' rows of the ', nf(length(unique(e$tornado_id))), ' linked tornadoes, `dat_pop_affected` never exceeds `zcta_pop` (up to floating-point error), the parts by rating add up to the total, and no share of a block is capped: the largest share of the land of a block covered by a polygon zone is ', format(ds$blocks[["largest_share"]], digits = 12), ' (the build stops above 1 by more than 1e-9). The blocks of the tracts that the footprints reach number ', nf(ds$blocks[["blocks_in_tracts"]]), ' (', nf(ds$blocks[["pieces"]]), ' polygon-block pieces); ', nf(ds$blocks[["blocks_no_land_with_residents"]]), ' blocks have residents and no land in their land-only shape (their ', nf(ds$blocks[["residents_in_no_land_blocks"]]), ' residents are allocated by the share of the block polygon covered, section Land-only shapes). Residents in a block assigned to a ZCTA that has no row for the tornado (the polygons cover land in the block\'s tract but no land in the ZCTA) are not in `tornado_exposure`: ', nf(round(ds$residents_in_zctas_without_area)), ' residents in all; residents in blocks assigned to no ZCTA: ', nf(round(ds$residents_no_zcta)), '. 2020 block counts have disclosure-avoidance noise added by the Census Bureau, which is larger for small areas.
<!-- population:end -->
')
k <- paste(readLines("data-raw/known_issues.md", warn = FALSE), collapse = "\n")
if (grepl("<!-- population:start -->", k, fixed = TRUE)) { a1 <- regexpr("<!-- population:start -->", k, fixed = TRUE); b1 <- regexpr("<!-- population:end -->", k, fixed = TRUE) + nchar("<!-- population:end -->"); k <- paste0(substr(k, 1, a1 - 1), sub("\n$", "", txt), substr(k, b1, nchar(k)))
} else { a1 <- regexpr("## Point tracks", k, fixed = TRUE); k <- paste0(substr(k, 1, a1 - 1), txt, "\n", substr(k, a1, nchar(k))) }
writeLines(sub("\n+$", "", k), "data-raw/known_issues.md"); cat("wrote the population section of known_issues.md\n")
