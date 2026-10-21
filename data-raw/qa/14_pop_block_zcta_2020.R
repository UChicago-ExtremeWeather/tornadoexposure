# Run from the package root: Rscript data-raw/qa/14_pop_block_zcta_2020.R
# Needs data-raw/add_population.R to have processed the 2020 vintage.
# Compares the block-to-ZCTA assignment used for zcta_pop (internal point in the
# ZCTA polygon) with the Census Bureau's official 2020 ZCTA-to-block
# relationship file, nationwide (50 states, DC and Puerto Rico).
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R")
suppressMessages({library(dplyr); library(readr)})
url <- "https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_tabblock20_natl.txt"
f <- download_cached(url)
rel <- read_delim(f, delim = "|", col_types = cols(.default = "c"), col_select = matches("^GEOID_(ZCTA5|TABBLOCK)"), progress = FALSE)
cat("relationship file rows:", nrow(rel), "; columns:", paste(names(rel), collapse = ", "), "\n")
zc <- grep("^GEOID_ZCTA5", names(rel), value = TRUE); bc <- grep("^GEOID_TABBLOCK", names(rel), value = TRUE)
off <- rel %>% transmute(GEOID = .data[[bc]], ZCTA_off = .data[[zc]]) %>% mutate(ZCTA_off = ifelse(ZCTA_off == "" , NA, ZCTA_off))
cat("blocks in the official file:", nrow(off), "; blocks appearing more than once:", sum(duplicated(off$GEOID)), "\n")
off <- off[!duplicated(off$GEOID), ]
states <- pop_states(); mine <- bind_rows(lapply(states$state_code, function(fp) { fl <- pop_cache("work", sprintf("2020_%s.rds", fp)); if (file.exists(fl)) readRDS(fl)$blocks else NULL }))
cat("blocks with our assignment:", nrow(mine), "(states processed:", sum(vapply(states$state_code, function(fp) file.exists(pop_cache("work", sprintf("2020_%s.rds", fp))), logical(1))), "of", nrow(states), ")\n")
j <- mine %>% inner_join(off, by = "GEOID")
cat("blocks matched on GEOID:", nrow(j), "of", nrow(mine), "; in the official file but not processed here (territories or unprocessed states):", sum(!off$GEOID %in% mine$GEOID), "\n")
j$cat <- with(j, ifelse(is.na(ZCTA) & is.na(ZCTA_off), "both unassigned", ifelse(is.na(ZCTA) & !is.na(ZCTA_off), "official has a ZCTA, ours none", ifelse(!is.na(ZCTA) & is.na(ZCTA_off), "ours has a ZCTA, official none", ifelse(ZCTA == ZCTA_off, "same ZCTA", "different ZCTA")))))
pop <- ifelse(is.na(j$pop), 0, j$pop)
tab <- j %>% mutate(pop = pop) %>% group_by(cat) %>% summarise(blocks = n(), pop = sum(pop), .groups = "drop") %>% mutate(pct_blocks = round(100 * blocks / sum(blocks), 4), pct_pop = round(100 * pop / sum(pop), 4))
print(as.data.frame(tab), row.names = FALSE)
mism <- j %>% filter(cat %in% c("official has a ZCTA, ours none", "ours has a ZCTA, official none", "different ZCTA"))
cat(sprintf("\nMismatch (any kind): %d blocks (%.4f%% of blocks), %d residents (%.4f%% of residents)\n", nrow(mism), 100 * nrow(mism) / nrow(j), sum(mism$pop, na.rm = TRUE), 100 * sum(mism$pop, na.rm = TRUE) / sum(pop)))
cat("by state (mismatch rate of blocks, largest 8):\n"); print(j %>% mutate(st = substr(GEOID, 1, 2), mm = cat %in% c("official has a ZCTA, ours none", "ours has a ZCTA, official none", "different ZCTA")) %>% group_by(st) %>% summarise(blocks = n(), mismatch = sum(mm), pct = round(100 * mean(mm), 3)) %>% arrange(desc(pct)) %>% head(8))
# effect on ZCTA populations: our zcta_pop versus the population implied by the official assignment
ours <- j %>% filter(!is.na(ZCTA)) %>% group_by(ZCTA) %>% summarise(pop_ours = sum(pop, na.rm = TRUE), .groups = "drop")
offz <- j %>% filter(!is.na(ZCTA_off)) %>% group_by(ZCTA = ZCTA_off) %>% summarise(pop_off = sum(pop, na.rm = TRUE), .groups = "drop")
z <- full_join(ours, offz, by = "ZCTA") %>% mutate(pop_ours = coalesce(pop_ours, 0), pop_off = coalesce(pop_off, 0), diff = pop_ours - pop_off)
cat(sprintf("\nZCTAs: %d; identical zcta_pop under both assignments: %d (%.2f%%); relative difference quantiles for ZCTAs with pop_off > 0 (|diff|/pop_off): %s\n", nrow(z), sum(z$diff == 0), 100 * mean(z$diff == 0), paste(signif(quantile(abs(z$diff[z$pop_off > 0]) / z$pop_off[z$pop_off > 0], c(.5, .9, .99, 1)), 3), collapse = " ")))
saveRDS(list(tab = tab, mism = mism %>% head(2000), z = z), qa_out("pop_block_zcta_2020.rds"))
