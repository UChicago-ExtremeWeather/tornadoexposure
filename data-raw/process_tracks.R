# Full rebuild of the bundled datasets `tornado_exposure` (without the population columns) and
# `tornado_tracks`, from scratch, for every year.
#
# Source: NOAA Storm Prediction Center (SPC) severe weather database (tornado records) and Census Bureau
# ZCTA boundaries (via tigris). The processing itself is in data-raw/pipeline_functions.R, shared with the
# incremental update (data-raw/update_data.R).
#
# THIS IS NOT HOW THE DATA ARE UPDATED. A yearly update appends only the new year with data-raw/update_data.R
# (its header has the instructions). This script rebuilds every year, for
# verification and for deliberate full rebuilds: SPC revises old records between releases and changes
# ids, so a full rebuild need not reproduce the stored data. After this script run data-raw/add_population.R
# (population columns), data-raw/add_centroids.R (zcta_centroids) and, for the survey layer,
# data-raw/survey/build_survey.R.

latest_year <- 2025
source("data-raw/pipeline_functions.R")

# ---- 1. read and filter raw SPC records ------------------------------------
dl <- spc_download(latest_year)
noaa_url <- dl$url; csv_file <- dl$file; access_date <- dl$access_date
raw <- read_csv(csv_file, show_col_types = FALSE)
message("Raw records: ", nrow(raw))

# ---- 2. clean, build geometries, intersect with ZCTAs of the matching vintage ------
tornadoes <- spc_clean(raw, first_year:latest_year)
b <- spc_build(tornadoes)
tornado_exposure <- b$exposure
tornado_tracks <- b$tracks

# ---- 8. save ---------------------------------------------------------------

writeLines(format(access_date), "data-raw/access_date.txt")

# provenance: what was downloaded and which software produced the data
cache_dir <- Sys.getenv("TIGRIS_CACHE_DIR", rappdirs::user_cache_dir("tigris"))
zfiles <- c("2000" = "tl_2010_us_zcta500", "2010" = "tl_2010_us_zcta510",
            "2020" = "tl_2020_us_zcta520")
tiger_dates <- vapply(zfiles, function(f) {
  p <- file.path(cache_dir, paste0(f, ".shp"))
  if (file.exists(p)) format(file.mtime(p), "%Y-%m-%d") else NA_character_
}, character(1))
ext <- sf::sf_extSoftVersion()
writeLines(c(
  paste("SPC file:", noaa_url),
  paste("Access date:", format(access_date)),
  paste("SPC file md5:", unname(tools::md5sum(csv_file))),
  paste("SPC file size (bytes):", file.size(csv_file)),
  paste("SPC records read:", nrow(raw)),
  paste0("tigris ZCTA files (", names(zfiles), " vintage, ", zfiles,
         "), cache file date: ", tiger_dates),
  "(the cache file date is the day tigris downloaded the file; clear the tigris cache to force a fresh download)",
  paste("R:", R.version.string),
  paste("Platform:", R.version$platform),
  paste("sf:", as.character(packageVersion("sf"))),
  paste("GEOS:", ext[["GEOS"]]), paste("GDAL:", ext[["GDAL"]]),
  paste("PROJ:", ext[["PROJ"]]),
  paste("tigris:", as.character(packageVersion("tigris"))),
  paste("dplyr:", as.character(packageVersion("dplyr"))),
  paste("readr:", as.character(packageVersion("readr")))
), "data-raw/provenance.txt")
record_spc_release(first_year, latest_year, dl, "full build", replace_all = TRUE)
message("Data accessed: ", access_date, " (", noaa_url, ")")
message("tornado_exposure rows: ", nrow(tornado_exposure),
        "; tornado_tracks rows: ", nrow(tornado_tracks))

usethis::use_data(tornado_exposure, tornado_tracks, overwrite = TRUE,
                  compress = "xz")
