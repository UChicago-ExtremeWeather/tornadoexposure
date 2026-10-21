# Run from the package root after 14-18: Rscript data-raw/qa/19_population_known_issues.R
# Writes the "Population" section of data-raw/known_issues.md from the saved
# validation results (every number computed, nothing typed in).
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr)})
fmt <- function(x, d = 2) formatC(x, format = "f", digits = d, big.mark = ","); pct <- function(x, d = 1) paste0(formatC(100 * x, format = "f", digits = d), "%"); nf <- function(x) formatC(round(x), format = "d", big.mark = ",")
load("data/tornado_exposure.rda")
R <- readRDS(qa_out("population_results.rds")); S <- R$summary
a <- readRDS(qa_out("pop_block_zcta_2020.rds")); z <- readRDS(qa_out("pop_zcta_totals.rds"))
wb <- bind_rows(lapply(list.files(qa_out(""), pattern = "^pop_whole_block_.*\\.rds$", full.names = TRUE), readRDS))
jp <- readRDS(qa_out("pop_joplin_shift.rds")); bgs <- readRDS(qa_out("pop_block_group_sensitivity.rds"))
# --- sources and block assignment
tab <- a$tab; same <- tab$blocks[tab$cat == "same ZCTA"]; both_un <- tab$blocks[tab$cat == "both unassigned"]; nb <- sum(tab$blocks)
mism <- sum(tab$blocks[!tab$cat %in% c("same ZCTA", "both unassigned")]); mism_pop <- sum(tab$pop[!tab$cat %in% c("same ZCTA", "both unassigned")])
v <- S %>% group_by(vintage) %>% summarise(blocks = sum(blocks), pop = sum(pop_sum), no_zcta_blocks = sum(blocks_no_zcta), no_zcta_pop = sum(pop_no_zcta), pop_na = sum(pop_na), .groups = "drop")
vt <- v %>% transmute(Vintage = vintage, Blocks = nf(blocks), `Resident population in the blocks` = nf(pop), `Blocks assigned to no ZCTA` = paste0(nf(no_zcta_blocks), " (", pct(no_zcta_blocks / blocks, 2), ")"), `Residents in those blocks` = paste0(nf(no_zcta_pop), " (", pct(no_zcta_pop / pop, 3), ")"))
md <- function(df) paste(c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"), apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))), collapse = "\n")
zt <- function(m, v) paste0(nf(nrow(m)), " ZCTAs compared; identical `zcta_pop` for ", nf(sum(m$diff == 0)), " (", pct(mean(m$diff == 0), 3), "); largest absolute difference ", nf(max(abs(m$diff))), " residents; total difference ", nf(sum(m$diff)), " residents")
wbt <- wb %>% transmute(Vintage = vintage, State = toupper(state), `Blocks sampled` = nf(sampled), `Assigned to a ZCTA` = nf(assigned), `Assigned: at least 99% of area inside the ZCTA` = pct(own_ge99, 2), `Assigned: minimum share inside` = fmt(own_min, 3), `Unassigned: blocks sampled` = nf(unassigned), `Unassigned: share with at most 1% of area inside any ZCTA` = ifelse(is.na(unassigned_le1), "n/a", pct(unassigned_le1, 1))) %>% arrange(Vintage, State)
e <- tornado_exposure
iq <- quantile(e$pop_prop_affected, c(.5, .9, .99), na.rm = TRUE)
bgr <- function(th) { s <- bgs %>% filter(block_pop >= th); r <- s$bg_pop / s$block_pop; data.frame(th = th, n = nrow(s), med = median(r), q25 = quantile(r, .25), q75 = quantile(r, .75), w25 = mean(abs(r - 1) <= .25), w2 = mean(r >= .5 & r <= 2), sp = cor(s$block_pop, s$bg_pop, method = "spearman")) }
bgt <- bind_rows(lapply(c(1, 100, 1000), bgr)) %>% transmute(`Residents in the path (blocks) at least` = nf(th), Tornadoes = nf(n), `Median block-group / block` = fmt(med), `Interquartile range` = paste0(fmt(q25), " to ", fmt(q75)), `Within 25%` = pct(w25), `Within a factor of 2` = pct(w2), `Rank correlation` = fmt(sp, 3))
jp0 <- jp$pop[jp$shift_km == 0]; jpm <- max(jp$pop); jps <- jp$shift_km[which.max(jp$pop)]
j <- e %>% filter(tornado_id == "2011_1105221634-01")
txt <- paste0('<!-- population:start -->
## Population (`pop_affected`, `zcta_pop`, `pop_prop_affected`)

`pop_affected` is the estimated number of residents (total population, all ages) inside the modeled path within a ZCTA. Each census block of the ZCTA vintage keeps its population, which is allocated to the path by the share of the block\'s area inside the path (uniform density within a block, water included in the block polygon). Blocks are assigned to ZCTAs by their internal points, and `zcta_pop` is the sum of the populations of the blocks assigned to a ZCTA. Population is fixed at the census year within each decade (2000 blocks for years before 2010, 2010 blocks for 2010 to 2019, 2020 blocks from 2020). Sources: TIGER/Line tabulation blocks, with population from field `POP20` (2020) or the Census PL 94-171 redistricting files (2010 and 2000); URLs, sizes and checksums are in `data-raw/provenance_population.csv`.

', md(vt), '

**Block-to-ZCTA assignment against the official 2020 relationship file.** Of ', nf(nb), ' blocks in the 50 states, DC and Puerto Rico, ', nf(same), ' have the same ZCTA in the Census Bureau\'s 2020 ZCTA-to-block relationship file and our assignment, ', nf(both_un), ' are assigned to no ZCTA in both, and ', nf(mism), ' disagree (', fmt(mism_pop, 0), ' residents). `zcta_pop` is identical under both assignments for ', pct(mean(a$z$diff == 0), 2), ' of the ', nf(nrow(a$z)), ' ZCTAs.

**`zcta_pop` against official ZCTA populations** (Census Gazetteer files, which need no API key; the 2020 Gazetteer has no population and the API needs a key, so 2020 is checked only through the relationship file above). 2010: ', zt(z$m2010), '. 2000: ', zt(z$m2000), '.

**Whole-block and internal-point checks.** ZCTAs are built from whole blocks, so a block assigned to a ZCTA by its internal point should lie almost entirely inside it, and a block assigned to none should lie outside every ZCTA. Random samples of blocks:

', md(wbt), '

**Integrity.** `pop_affected` never exceeds `zcta_pop`, `pop_prop_affected` is within 0 to 1, and for every tornado the residents in the exposure rows plus the residents in blocks assigned to no ZCTA equal the residents in the modeled path. `pop_prop_affected` is `NA` for ', nf(sum(e$zcta_pop == 0)), ' rows (`zcta_pop` is 0). Its median is ', fmt(iq[1], 5), ', its 90th percentile ', fmt(iq[2], 4), ' and its 99th percentile ', fmt(iq[3], 3), '; ', nf(sum(e$pop_affected == 0)), ' rows (', pct(mean(e$pop_affected == 0)), ') have `pop_affected` 0.

**Joplin (`2011_1105221634-01`).** The modeled path holds ', nf(round(sum(j$pop_affected))), ' residents (', paste0(j$ZCTA, ": ", nf(round(j$pop_affected)), collapse = "; "), '). No survey GIS exists for Joplin. The straight modeled path can sit kilometers from the real one (see Path accuracy), and the residents it holds depend strongly on its sideways position: shifting the modeled polygon sideways changes them from ', nf(min(jp$pop)), ' to ', nf(jpm), ' (', fmt(jpm / jp0, 1), ' times the unshifted ', nf(jp0), ', reached at a shift of ', fmt(jps, 1), ' km to the left of the direction of travel, about north, toward the Joplin city center, which is about 5 km north of the modeled centerline). The unshifted estimate is therefore very uncertain, and a path displaced to the north would hold several times more residents; without a survey the true figure cannot be determined.

**Block versus block group, tornadoes from 2020 on** (the minimum residents of 1, 100 and 1,000 are a span chosen to show how the comparison changes with the size of the population; "within 25%" and "within a factor of 2" describe the comparison and are not tested choices). The Census Bureau adds noise to 2020 block counts (differential privacy) and recommends aggregating. The residents in the modeled path computed from block groups instead of blocks (block-group population allocated by area share):

', md(bgt), '

This shows how much the uniform-density assumption and the block resolution matter; it is not a measurement of the noise itself, which cannot be isolated without noise-free data.
<!-- population:end -->
')
k <- paste(readLines("data-raw/known_issues.md", warn = FALSE), collapse = "\n")
if (grepl("<!-- population:start -->", k, fixed = TRUE)) { a1 <- regexpr("<!-- population:start -->", k, fixed = TRUE); b1 <- regexpr("<!-- population:end -->", k, fixed = TRUE) + nchar("<!-- population:end -->"); k <- paste0(substr(k, 1, a1 - 1), sub("\n$", "", txt), substr(k, b1, nchar(k)))
} else { a1 <- regexpr("## Point tracks", k, fixed = TRUE); k <- paste0(substr(k, 1, a1 - 1), txt, "\n", substr(k, a1, nchar(k))) }
writeLines(sub("\n+$", "", k), "data-raw/known_issues.md"); cat("wrote the population section of known_issues.md\n")
