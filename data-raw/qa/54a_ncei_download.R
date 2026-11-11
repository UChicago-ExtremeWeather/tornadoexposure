# Run from the package root:  Rscript data-raw/qa/54a_ncei_download.R
# Downloads the current NCEI Storm Events details and locations files for 2007 to 2025 into data-raw/qa/cache/ncei_full/ (git-ignored) and records file names, sizes, md5 and the date.
source("data-raw/qa/helpers.R"); options(timeout = 1200)
idx_f <- qa_cache("ncei_index_current.html"); download.file("https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/", idx_f, quiet = TRUE); idx <- readLines(idx_f, warn = FALSE)
files <- unique(unlist(regmatches(idx, gregexpr("StormEvents_(details|locations)-ftp_v1\\.0_d[0-9]{4}_c[0-9]{8}\\.csv\\.gz", idx))))
d <- data.frame(file = files, kind = sub("StormEvents_([a-z]+)-.*", "\\1", files), year = as.integer(sub(".*_d([0-9]{4})_.*", "\\1", files)), cdate = sub(".*_c([0-9]{8}).*", "\\1", files))
d <- d[d$year >= 2007 & d$year <= 2025, ]; d <- d[order(d$kind, d$year, d$cdate, decreasing = c(FALSE, FALSE, TRUE), method = "radix"), ]; d <- d[!duplicated(d[c("kind", "year")]), ]
dir.create(qa_cache("ncei_full"), showWarnings = FALSE); out <- list()
for (i in seq_len(nrow(d))) { dest <- file.path(qa_cache("ncei_full"), d$file[i]); if (!file.exists(dest)) download.file(paste0("https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/", d$file[i]), dest, mode = "wb", quiet = TRUE)
  out[[i]] <- cbind(d[i, ], bytes = file.size(dest), md5 = unname(tools::md5sum(dest)), downloaded = format(Sys.Date())); cat(d$file[i], file.size(dest), "\n") }
saveRDS(do.call(rbind, out), qa_out("ncei_files.rds"))
