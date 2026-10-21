# Run from the package root: Rscript data-raw/qa/39_spc_release_comparison.R
# How much SPC revised its records between two releases: the 2024 file (1950-2024) against the file the package was built from
# (1950-2025). Whole-track records (sg == 1) of tornadoes rated EF1 or above (1996 to 2024) are matched by date and start
# coordinates; ids (`om`) and the values of the matched tornadoes are compared. The 2024 file (about 8 MB) is downloaded into
# data-raw/qa/cache/. Results: data-raw/qa/out/documented_39.rds (read by check_documented_claims.R).
source("data-raw/qa/helpers.R")
suppressMessages(library(dplyr)); options(width = 170, timeout = 600)
f24 <- qa_cache("1950-2024_all_tornadoes.csv")
if (!file.exists(f24)) download.file("https://www.spc.noaa.gov/wcm/data/1950-2024_all_tornadoes.csv", f24, mode = "wb", quiet = TRUE)
prep <- function(f) read.csv(f, stringsAsFactors = FALSE) %>% filter(sg == 1, yr >= 1996, yr <= 2024, mag >= 1) %>% mutate(key = paste(date, slat, slon))
a <- prep(f24); b <- prep(qa_spc_csv())
a <- a[!duplicated(a$key) & !duplicated(a$key, fromLast = TRUE), ]; b <- b[!duplicated(b$key) & !duplicated(b$key, fromLast = TRUE), ]
m <- inner_join(a, b, by = "key", suffix = c("_24", "_25"))
cat("records in the 2024 file:", nrow(a), "; in the 2025 file:", nrow(b), "; matched:", nrow(m), "\n")
late <- m$yr_24 >= 2007; early <- !late
chg <- function(v, idx = rep(TRUE, nrow(m))) sum(m[[paste0(v, "_24")]][idx] != m[[paste0(v, "_25")]][idx])
res <- list(matched = nrow(m), matched_2007 = sum(late), om_changed_2007 = chg("om", late), om_changed_1996_2006 = chg("om", early),
            mag = chg("mag"), inj = chg("inj"), fat = chg("fat"), len = chg("len"), wid = chg("wid"), loss = chg("loss"),
            early_any_change = sum(early & (m$mag_24 != m$mag_25 | m$inj_24 != m$inj_25 | m$fat_24 != m$fat_25 | m$len_24 != m$len_25 | m$wid_24 != m$wid_25 | m$loss_24 != m$loss_25)),
            loss_changed_by_1e6 = sum(m$loss_24 != m$loss_25 & m$loss_24 > 0 & abs(m$loss_25 / m$loss_24 - 1e6) < 1e-3),
            loss_changed_years = range(m$yr_24[m$loss_24 != m$loss_25]))
print(res)
saveRDS(res, qa_out("documented_39.rds"))
