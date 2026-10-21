# Run from the package root: Rscript data-raw/qa/06_zcta_integrity.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf)}); options(width=170)
load("data/tornado_exposure.rda"); load("data/tornado_tracks.rda")
cat("\n== D6: ZCTA integrity ==\n")
z <- tornado_exposure$ZCTA
cat("class:", class(z), " all 5 chars:", all(nchar(z)==5), " all digits:", all(grepl("^[0-9]{5}$", z)), " NA:", sum(is.na(z)), "\n")
cat("codes starting with 0:", sum(startsWith(z,"0")), "rows,", n_distinct(z[startsWith(z,"0")]), "distinct; starting with 00:", sum(startsWith(z,"00")), "rows (PR/VI)\n")
cache <- file.path(Sys.getenv("HOME"), "Library/Caches/tigris")
zfile <- c("2000"="tl_2010_us_zcta500", "2010"="tl_2010_us_zcta510", "2020"="tl_2020_us_zcta520"); suf <- c("2000"="00","2010"="10","2020"="20")
Z <- lapply(names(zfile), function(v) { x <- sf::read_sf(file.path(cache, paste0(zfile[[v]], ".dbf"))); data.frame(ZCTA=x[[paste0("ZCTA5CE", suf[[v]])]], ALAND=as.numeric(x[[paste0("ALAND", suf[[v]])]]), stringsAsFactors=FALSE) }); names(Z) <- names(zfile)
for (v in names(Z)) cat("vintage", v, ": distinct codes", n_distinct(Z[[v]]$ZCTA), " all 5-digit char:", all(nchar(Z[[v]]$ZCTA)==5), " ALAND==0:", sum(Z[[v]]$ALAND==0), "\n")
vint <- function(y) ifelse(y<2010,"2000", ifelse(y<2020,"2010","2020"))
ex <- tornado_exposure %>% mutate(v=vint(year))
cat("distinct ZCTA codes in tornado_exposure by vintage:\n"); print(ex %>% group_by(v) %>% summarise(rows=n(), codes=n_distinct(ZCTA)))
nxt <- c("2000"="2010", "2010"="2020"); doc06 <- list()
for (vv in names(nxt)) { d <- ex[ex$v == vv, ]; miss <- d %>% filter(!ZCTA %in% Z[[nxt[[vv]]]]$ZCTA)
  cat(sprintf("\n%s-vintage rows whose code does not exist in the %s file: %d rows (%.2f%%), %d distinct codes (of %d). Examples: %s\n", vv, nxt[[vv]], nrow(miss), 100*nrow(miss)/nrow(d), n_distinct(miss$ZCTA), n_distinct(d$ZCTA), paste(head(unique(miss$ZCTA),8), collapse=", ")))
  both <- inner_join(Z[[vv]] %>% distinct(ZCTA, .keep_all=TRUE), Z[[nxt[[vv]]]] %>% distinct(ZCTA, .keep_all=TRUE), by="ZCTA", suffix=c("_a","_b")) %>% filter(ZCTA %in% d$ZCTA, ALAND_a>0)
  r <- both$ALAND_b/both$ALAND_a
  doc06[[vv]] <- list(rows_missing = nrow(miss), codes_missing = n_distinct(miss$ZCTA), changed_gt10 = 100*mean(abs(r-1)>.1))
  cat(sprintf("  among exposed codes present in both files (%d): land area changed by >10%%: %.1f%%, >50%%: %.1f%%; ratio quantiles (next/this):\n", nrow(both), 100*mean(abs(r-1)>.1), 100*mean(abs(r-1)>.5))); print(signif(quantile(r, c(.01,.05,.25,.5,.75,.95,.99)),3)) }
d20 <- ex %>% filter(!ZCTA %in% Z[["2020"]]$ZCTA); cat(sprintf("\nrows whose code is absent from the 2020 file (users joining current ZCTA data): %d rows, %d codes\n", nrow(d20), n_distinct(d20$ZCTA)))

# numbers quoted in data-raw/known_issues.md (read by check_documented_claims.R)
saveRDS(list(v2000 = doc06[["2000"]], v2010 = doc06[["2010"]], absent_2020_rows = nrow(d20), absent_2020_codes = n_distinct(d20$ZCTA)), qa_out("documented_06.rds"))
