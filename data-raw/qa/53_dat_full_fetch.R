# Run from the package root:  caffeinate -i Rscript data-raw/qa/53_dat_full_fetch.R    (progress: data-raw/qa/out/53.log)
# Fetches EVERY feature of the three layers of the live NWS Damage Assessment Toolkit service (no date filter, all fields, full resolution, native spatial reference
# EPSG:4326, no generalization parameter), keeping the service's JSON responses as received (gzip) in data-raw/qa/cache/dat_full/ and an sf copy in data-raw/qa/out/.
# Records download size and time per layer. The cache and out folders are git-ignored.
suppressMessages({library(sf); library(jsonlite); library(httr)})
source("data-raw/qa/helpers.R"); svc <- "https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer"
lg <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S "), ...); cat(m, "\n"); cat(m, "\n", file = qa_out("53.log"), append = TRUE) }
dir.create(qa_cache("dat_full"), showWarnings = FALSE); res <- list(); page <- c(`0` = 2000, `1` = 2000, `2` = 500)
for (i in 0:2) { t0 <- Sys.time(); cnt <- fromJSON(paste0(svc, "/", i, "/query?where=1%3D1&returnCountOnly=true&f=json"))$count; off <- 0; bytes <- 0; pages <- list(); k <- 0
  repeat { u <- GET(paste0(svc, "/", i, "/query"), query = list(where = "1=1", outFields = "*", returnGeometry = "true", orderByFields = "objectid", resultOffset = off, resultRecordCount = page[[as.character(i)]], f = "json"), timeout(300))
    stop_for_status(u); raw <- content(u, as = "raw"); bytes <- bytes + length(raw); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
    f <- file.path(qa_cache("dat_full"), sprintf("layer%d_%05d.json.gz", i, off)); con <- gzfile(f, "wb"); writeBin(raw, con); close(con)
    tf <- tempfile(fileext = ".json"); writeLines(txt, tf, useBytes = TRUE); x <- st_read(tf, quiet = TRUE); k <- k + 1; pages[[k]] <- x; n <- nrow(x); off <- off + n
    if (k %% 10 == 0) lg("layer ", i, ": ", off, " of ", cnt); js <- fromJSON(txt, simplifyVector = FALSE, flatten = FALSE); if (!isTRUE(js$exceededTransferLimit) || n == 0) break }
  X <- do.call(rbind, pages); saveRDS(X, qa_out(sprintf("dat_full_layer%d.rds", i)))
  res[[as.character(i)]] <- data.frame(layer = i, count_reported = cnt, features_read = nrow(X), json_mb = bytes / 1e6, seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")), fetched = format(Sys.time())); lg("layer ", i, " done: ", nrow(X), " features, ", round(bytes / 1e6, 1), " MB, ", round(res[[as.character(i)]]$seconds), " s") }
R <- do.call(rbind, res); saveRDS(R, qa_out("dat_full_fetch.rds")); print(R)
