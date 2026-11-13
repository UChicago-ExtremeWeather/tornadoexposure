# Fetches EVERY feature of the three layers of the NWS Damage Assessment Toolkit (DAT) service, with all fields, at full resolution, in the service's
# native spatial reference (EPSG:4326), with no date filter, no generalization or simplification parameter and no filter on geometry.
# Source: https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer
#   layer 0 damage points, layer 1 damage lines (centerlines of surveyed tornado tracks), layer 2 damage polygons
# Run from the package root:  caffeinate -i Rscript data-raw/dat/fetch_dat.R      (layer 0 has about 240,000 features and takes about 30 minutes)
# Output (git-ignored): data-raw/dat/fetch/pages/ (the service's JSON responses as received, gzip), data-raw/dat/fetch/layer<N>.rds (as read by sf),
# data-raw/dat/fetch/fetch_summary.rds (count the service reported, features read, size, time). The date of the fetch is written to data-raw/dat/access_date.txt.
# The script stops if the features read differ from the count the service reports.
suppressMessages({library(sf); library(jsonlite); library(httr)})
svc <- "https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer"
dir.create("data-raw/dat/fetch/pages", recursive = TRUE, showWarnings = FALSE)
page <- c(`0` = 2000, `1` = 2000, `2` = 500); res <- list()
for (i in 0:2) {
  t0 <- Sys.time(); cnt <- fromJSON(paste0(svc, "/", i, "/query?where=1%3D1&returnCountOnly=true&f=json"))$count; off <- 0; bytes <- 0; pages <- list(); k <- 0
  repeat {
    u <- GET(paste0(svc, "/", i, "/query"), query = list(where = "1=1", outFields = "*", returnGeometry = "true", orderByFields = "objectid",
                                                         resultOffset = off, resultRecordCount = page[[as.character(i)]], f = "json"))
    stop_for_status(u); raw <- content(u, as = "raw"); bytes <- bytes + length(raw); txt <- rawToChar(raw); Encoding(txt) <- "UTF-8"
    con <- gzfile(file.path("data-raw/dat/fetch/pages", sprintf("layer%d_%05d.json.gz", i, off)), "wb"); writeBin(raw, con); close(con)
    tf <- tempfile(fileext = ".json"); writeLines(txt, tf, useBytes = TRUE); x <- st_read(tf, quiet = TRUE); k <- k + 1; pages[[k]] <- x; n <- nrow(x); off <- off + n
    js <- fromJSON(txt, simplifyVector = FALSE, flatten = FALSE); if (!isTRUE(js$exceededTransferLimit) || n == 0) break
  }
  X <- do.call(rbind, pages); saveRDS(X, sprintf("data-raw/dat/fetch/layer%d.rds", i))
  res[[i + 1]] <- data.frame(layer = i, count_reported = cnt, features_read = nrow(X), json_mb = bytes / 1e6, seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")), fetched = format(Sys.time()))
  if (nrow(X) != cnt) stop("Layer ", i, ": ", nrow(X), " features read, the service reports ", cnt, ".", call. = FALSE)
}
R <- do.call(rbind, res); saveRDS(R, "data-raw/dat/fetch/fetch_summary.rds"); writeLines(format(Sys.Date()), "data-raw/dat/access_date.txt"); print(R)
