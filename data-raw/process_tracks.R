# Full rebuild of the bundled datasets `spc_records`, `tornado_tracks` and `tornado_exposure` (without the population columns), from scratch, for every year.
#
# Source: NOAA Storm Prediction Center (SPC) severe weather database (tornado records) and Census Bureau
# ZCTA boundaries (full TIGER/Line files via tigris). The processing itself is in data-raw/pipeline_functions.R, shared with the
# incremental update (data-raw/update_data.R).
#
# THIS IS NOT HOW THE DATA ARE UPDATED. A yearly update appends only the new year with data-raw/update_data.R
# (its header has the instructions). This script rebuilds every year, for
# verification and for deliberate full rebuilds: SPC revises old records between releases and changes
# ids, so a full rebuild need not reproduce the stored data. Order of a full rebuild: data-raw/add_centroids.R (zcta_centroids; needs the
# population cache), this script, data-raw/add_population.R (the modeled population columns), and data-raw/dat/build_dat.R (the DAT datasets).
# SPC_FILE=<path> rebuilds from an SPC file downloaded earlier instead of downloading today's file (its md5 must be in data-raw/provenance_years.csv).

latest_year <- 2025
source("data-raw/pipeline_functions.R")

# ---- 1. read the SPC records ------------------------------------------------
spc_file <- Sys.getenv("SPC_FILE", "")
dl <- if (nzchar(spc_file)) spc_stored(spc_file, latest_year) else spc_download(latest_year)
noaa_url <- dl$url; csv_file <- dl$file; access_date <- dl$access_date
raw <- spc_read(csv_file)
message("Raw records: ", nrow(raw))

# ---- 2. clean, build geometries, intersect with ZCTAs of the matching vintage ------
load("data/zcta_centroids.rda")
tornadoes <- spc_clean(raw, first_year:latest_year)
b <- spc_build(tornadoes, zcta_centroids)
spc_records <- spc_records(raw, first_year:latest_year, tornadoes)
tornado_tracks <- b$tracks
tornado_exposure <- b$exposure
tornado_exposure$modeled_pop_affected <- NA_real_     # filled by data-raw/add_population.R
tornado_exposure$modeled_pop_prop <- NA_real_
tornado_exposure <- tornado_exposure[, c("tornado_id", "date", "year", "month", "day", "magnitude", "total_injury", "total_fatality",
  "property_loss_tornado_total", "track_type", "ZCTA", "boundary_dist_km", "centroid_dist_km", "modeled_intersection_m2", "modeled_area_prop",
  "modeled_pop_affected", "modeled_pop_prop", "modeled_area_share_of_tornado", "modeled_property_loss_allocated",
  "zcta_polygon_area_m2", "zcta_land_area_m2", "zcta_pop")]

# ---- 3. save ---------------------------------------------------------------

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
  paste0("tigris ZCTA files (", names(zfiles), " boundary year, ", zfiles,
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
message("tornado_exposure rows: ", nrow(tornado_exposure), "; tornado_tracks rows: ", nrow(tornado_tracks), "; spc_records rows: ", nrow(spc_records))

usethis::use_data(spc_records, tornado_exposure, tornado_tracks, overwrite = TRUE, compress = "xz")
