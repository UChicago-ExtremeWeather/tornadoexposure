# Run from the package root:  Rscript data-raw/qa/48_first_map_timing.R
# Time and download size of the first map_exposure() call with an empty boundary-file cache (a new cache folder), then of the second identical call.
# Result: data-raw/qa/out/first_map_timing.rds
suppressMessages({devtools::load_all(".", quiet = TRUE)})
cd <- file.path(tempdir(), "tigris_empty"); dir.create(cd); Sys.setenv(TIGRIS_CACHE_DIR = cd); options(tigris_use_cache = TRUE)
sz <- function() sum(file.info(list.files(cd, recursive = TRUE, full.names = TRUE))$size)
t1 <- system.time(p1 <- map_exposure(geo_list = "648", year_range = 2011, feature = "tornado_id"))[["elapsed"]]; s1 <- sz(); f1 <- list.files(cd, recursive = TRUE)
t2 <- system.time(p2 <- map_exposure(geo_list = "648", year_range = 2011, feature = "tornado_id"))[["elapsed"]]; s2 <- sz()
zipurl <- "https://www2.census.gov/geo/tiger/GENZ2010/gz_2010_us_860_00_500k.zip"
h <- curl::curl_fetch_memory(zipurl, handle = curl::new_handle(nobody = TRUE)); zip_mb <- as.numeric(sub(".*content-length: ([0-9]+).*", "\\1", tolower(rawToChar(h$headers)))) / 1e6   # size of the file that is downloaded (a zip), from the server header
# sizes of the three boundary files used for maps (cb = TRUE, as in get_geometry()) and of the full TIGER/Line files (cb = FALSE), from the server headers
urls <- c(cb_2000 = "https://www2.census.gov/geo/tiger/PREVGENZ/zt/z500shp/zt99_d00_shp.zip", cb_2010 = "https://www2.census.gov/geo/tiger/GENZ2010/gz_2010_us_860_00_500k.zip",
          cb_2020 = "https://www2.census.gov/geo/tiger/GENZ2020/shp/cb_2020_us_zcta520_500k.zip", full_2000 = "https://www2.census.gov/geo/tiger/TIGER2010/ZCTA5/2000/tl_2010_us_zcta500.zip",
          full_2010 = "https://www2.census.gov/geo/tiger/TIGER2010/ZCTA5/2010/tl_2010_us_zcta510.zip", full_2020 = "https://www2.census.gov/geo/tiger/TIGER2020/ZCTA520/tl_2020_us_zcta520.zip")
size_mb <- vapply(urls, function(u) { h <- curl::curl_fetch_memory(u, handle = curl::new_handle(nobody = TRUE, followlocation = TRUE)); as.numeric(sub(".*content-length: ([0-9]+).*", "\\1", tolower(rawToChar(h$headers)))) / 1e6 }, 1)
res <- list(zip_mb = zip_mb, size_mb = size_mb, zip_url = zipurl, first_s = t1, second_s = t2, downloaded_mb = s1 / 1e6, files = f1, grew_second = s2 - s1, when = Sys.time(), r = R.version.string, os = utils::sessionInfo()$running)
saveRDS(res, "data-raw/qa/out/first_map_timing.rds"); print(res)
