# Run from the package root: Rscript data-raw/qa/16_pop_zcta_totals.R
# Compares zcta_pop (sum of block populations assigned to a ZCTA) with the
# official ZCTA populations in the Census Gazetteer files that need no API key:
#   2010: Gaz_zcta_national.txt (POP10), 2000: zcta5.txt (POP2000; ZCTAs that cross
#   state lines appear once per state, so they are summed).
# 2020: the Gazetteer has no population and the API needs a key, so 2020 is not
# checked here.
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R")
suppressMessages({library(dplyr)})
R <- readRDS(qa_out("population_results.rds")); zp <- R$zcta_pop
load("data/tornado_exposure.rda")
td <- tempfile(); dir.create(td)
unzip(download_cached("https://www2.census.gov/geo/docs/maps-data/data/gazetteer/Gaz_zcta_national.zip"), exdir = td)
g10 <- read.delim(list.files(td, pattern = "Gaz_zcta_national.txt", full.names = TRUE), colClasses = "character", check.names = FALSE)
names(g10) <- trimws(names(g10)); off10 <- data.frame(ZCTA = trimws(g10$GEOID), pop_off = as.numeric(g10$POP10))
td2 <- tempfile(); dir.create(td2); unzip(download_cached("https://www2.census.gov/geo/docs/maps-data/data/gazetteer/zcta5.zip"), exdir = td2)
l <- readLines(list.files(td2, pattern = "zcta5.txt", full.names = TRUE))
tok <- strsplit(trimws(l), "[[:space:]]+")
off00 <- data.frame(ZCTA = substr(vapply(tok, `[`, "", 1), 3, 7), pop_off = suppressWarnings(as.numeric(vapply(tok, `[`, "", 4))), stringsAsFactors = FALSE) %>%
  filter(!is.na(pop_off)) %>% group_by(ZCTA) %>% summarise(pop_off = sum(pop_off), .groups = "drop")
cmp <- function(v, off) {
  m <- zp %>% filter(vint == v) %>% inner_join(off, by = "ZCTA") %>% mutate(diff = zcta_pop - pop_off, rel = ifelse(pop_off > 0, abs(diff) / pop_off, NA_real_))
  exposed <- unique(tornado_exposure$ZCTA[ifelse(tornado_exposure$year < 2010, 2000, ifelse(tornado_exposure$year < 2020, 2010, 2020)) == v])
  me <- m %>% filter(ZCTA %in% exposed)
  cat(sprintf("\n== %d vintage ==\nZCTAs with an official population: %d; with zcta_pop: %d; compared (both): %d\n", v, nrow(off), sum(zp$vint == v), nrow(m)))
  cat(sprintf("identical zcta_pop: %d (%.2f%%); |difference| <= 10 people: %.2f%%; relative difference quantiles (50/90/99/100%%): %s\n", sum(m$diff == 0), 100 * mean(m$diff == 0), 100 * mean(abs(m$diff) <= 10), paste(signif(quantile(m$rel, c(.5, .9, .99, 1), na.rm = TRUE), 3), collapse = " ")))
  cat(sprintf("total population: ours %s, official %s (difference %s)\n", format(sum(m$zcta_pop), big.mark = ","), format(sum(m$pop_off), big.mark = ","), format(sum(m$diff), big.mark = ",")))
  cat(sprintf("exposed ZCTAs only (%d): identical %.2f%%, relative difference quantiles (50/90/99/100%%): %s\n", nrow(me), 100 * mean(me$diff == 0), paste(signif(quantile(me$rel, c(.5, .9, .99, 1), na.rm = TRUE), 3), collapse = " ")))
  cat("largest differences:\n"); print(m %>% arrange(desc(abs(diff))) %>% head(6) %>% select(ZCTA, zcta_pop, pop_off, diff))
  invisible(m) }
a <- cmp(2010, off10); b <- cmp(2000, off00)
saveRDS(list(m2010 = a, m2000 = b), qa_out("pop_zcta_totals.rds"))
