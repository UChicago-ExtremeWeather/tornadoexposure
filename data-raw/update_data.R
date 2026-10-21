# Incremental, append-only update of the bundled data with a new SPC release.
# (This header is the full documentation of the update.)
#
# HOW TO RUN (from the package root)
#   1. Wait for SPC to announce the new year in its change log (https://www.spc.noaa.gov/wcm/data/changelog.txt;
#      recent entries are "Initial release of the <year> Database", published April to July of the following year).
#      The change log gives no date when a year becomes final. In 2018 it separated "Initial Release of the 2018 Severe
#      Weather Database, including preliminary 2017 severe weather reports" (11 Apr 2018) from "Updated Release of the 2018
#      Severe Weather Database, including the finalized 2017 severe weather reports" (3 Jul 2018); entries from 2022 on say only
#      "Initial release of the <year> Database". So wait for that entry, and for an updated release if SPC posts one.
#   2. Set `latest_year` below (or UPDATE_LATEST_YEAR=2026 in the environment).
#   3. Rscript data-raw/update_data.R
#   4. Follow-up, in this order: Rscript data-raw/qa/check_data_integrity.R (stops if a check on the data fails);
#      the QA scripts that save the numbers quoted in known_issues.md (data-raw/qa/05, 06, 07, 08, 09, 12 and 39; the NCEI and SPC
#      downloads are small, 8 MB for the SPC 2024 file and 232 MB for NCEI);
#      the QA scripts that write the tables into data-raw/known_issues.md (data-raw/qa/11c, 19, 20, 23, 36, 38d, 44, 49 (before 44b), 44b, 45, 46 and 47; 23 also writes the
#      distance, Moore and boundary-year sections); data-raw/qa/48 and 50 (the first-map timing and the README numbers, data-raw/readme/numbers.csv; 50 after 02, 29, 46, 47 and 48); Rscript data-raw/qa/check_documented_claims.R (stops, with a table, if a number in the README,
#      the help pages or known_issues.md no longer matches the data); devtools::document(); devtools::check();
#      Rscript data-raw/readme/build_readme.R (rebuilds the short README: the counts and the maps in figures/); update the access dates in
#      inst/CITATION. The update script itself adds the new year's SPC release to data-raw/provenance_years.csv. Then cut a GitHub release.
#   5. Zenodo: upload by hand to the lab Zenodo account. Never use Zenodo's GitHub integration. A published record is permanent,
#      so check with Kate first. Bump Version in DESCRIPTION, commit, publish a GitHub Release, then on the existing Zenodo record
#      click New version, upload the new Release zip, update the Version field, and publish. The "cite all versions" DOI
#      (10.5281/zenodo.23544841) is already in inst/CITATION and never changes. There is no separate data record, because the data
#      are bundled in the package.
#
# INSTALLED SIZE: R CMD check reports a NOTE that the installed size (about 5.2 MB) is above the 5 MB guideline of CRAN. The package is not
# published to CRAN, so the note is expected.
#
# WHAT IT DOES
# Loads the stored tornado_exposure and tornado_tracks, downloads the SPC file, and processes ONLY the years after the last
# stored year with the same code as the full rebuild (data-raw/pipeline_functions.R): tracks and tornado-level attributes,
# ZCTA exposure, and the population columns (from the per-state block results that data-raw/add_population.R cached outside the
# repository; only the blocks along the new paths are read; states that were never cached are processed in full). It checks the new
# rows against the stored ones and writes nothing if a check fails. Stored years are never changed, even if SPC has revised them
# (SPC revises magnitude, injuries, fatalities, len, wid and loss between releases, and changes ids: on 4 Jan 2021 reprocessing
# changed the ordering and some om numbers, and on 24 Apr 2026 SPC changed om_number from 2007 on to the format YYMMDDHHMM-01, so
# tornado_id is not stable across SPC releases). The script prints how many stored years have a different number of records in
# the new SPC file. It records which SPC download each year came from in data-raw/provenance_years.csv and data-raw/provenance.txt.
#
# STOP CONDITIONS (a clear message, nothing written)
#   * latest_year is not after the last stored year, or the SPC file has no whole-track records for a new year;
#   * a new year needs a Census vintage that is not in zcta_centroids (see "Next decennial vintage" below);
#   * an unexpected magnitude code (anything but -9 and 0 to 5);
#   * the SPC loss unit break (2007) has moved: for years before 2007 the yearly median of nonzero loss must be at most 1 and the
#     maximum at most 10,000 (millions of dollars); from 2007 the yearly median must be at least 10,000 (dollars). SPC's 3 Jul 2018
#     entry says "Beginning with the 2016 data, loss values are in actual dollar amounts", and the 2025 file has 2007 to 2015 in dollars;
#   * the columns or column types of the new rows differ from the stored ones, or the CRS differs;
#   * tornado_id does not match <year>_<om> (for example 2011_1105221634-01), is duplicated, or already exists in the stored data;
#   * the new rows contain years other than the ones being added;
#   * track coordinates outside latitude 15 to 72 and longitude -180 to -60; width outside 0 to 10,000 yards; length outside 0 to 400 miles
#     (sanity limits against corrupt records, not scientific values; the extremes in the data are in data-raw/known_issues.md, section
#     "Other fixed settings");
#   * loss not in dollars: any new row with loss_raw_unit "millions", or a median of known loss below 10,000 or a maximum above 1e11 dollars
#     (sanity limits);
#   * property_loss_tornado_total not NA exactly where SPC's loss is 0 (NOAA says 0 does not mean $0), or property_loss_allocated not NA
#     exactly where the tornado total is NA, or allocated loss not summing back to the total for a tornado with a known loss;
#   * area_prop_affected outside (0, 1], pop_prop_affected outside [0, 1], pop_affected above zcta_pop, or area_share_of_tornado not
#     summing to 1 for every tornado.
#
# DOWNLOADS AND CACHES (sizes from data-raw/provenance_years.csv and data-raw/provenance_population.csv; checked by
# data-raw/qa/check_documented_claims.R)
#   * SPC file 1950-<year>_all_tornadoes.csv: 9,219,030 bytes for 1950-2025.
#   * The 2020 ZCTA boundary file, through tigris (cached in ~/Library/Caches/tigris).
#   * The 2020 TIGER/Line tabulation blocks (tl_2020_<state>_tabblock20.zip) of the states that the new tornadoes touch: all 52 files are
#     10.33 GB (largest Texas 746 MB, smallest DC 4.7 MB, median 195 MB). They are cached in
#     ~/Library/Caches/org.R-project.R/R/tornadoexposure (set TORNADOEXPOSURE_CACHE to move it) together with the per-state results of
#     data-raw/add_population.R. Keep at least 10.4 GB free, and keep this cache between updates: without it, each touched state is
#     processed in full (every block is assigned to a ZCTA).
#   * A full rebuild (data-raw/process_tracks.R, the verification and full-rebuild mode, then add_population.R,
#     add_centroids.R and survey/build_survey.R) reads 24.6 GB of population files (2020 blocks 10.3 GB, 2010 blocks 7.0 GB, 2000 blocks
#     5.8 GB, 2010 PL files 1.0 GB, 2000 PL files 0.4 GB), the three ZCTA files through tigris and the SPC file.
#     Manifest: data-raw/provenance_population.csv.
#
# NOT EXTENDED AUTOMATICALLY
#   * zcta_centroids: only needed when a new census vintage is added; new years use the latest vintage (2020).
#   * Next decennial vintage (after the 2030 census), by hand: add the new ZCTA boundaries (tigris::zctas(year = 2030)) and the
#     tabulation blocks with population (check the file and field names), extend vint_of() in data-raw/pipeline_functions.R,
#     data-raw/add_population.R and data-raw/population/population_functions.R, .vintage_of() in R/distance.R and .plot_vintage() in
#     R/geometry.R, and run data-raw/add_centroids.R for the new vintage (it appends rows). Only new years use it; stored years never change.
#   * The NWS survey layer (survey_exposure, survey_tracks, survey_matches): after SPC has finalized the year and the Damage
#     Assessment Toolkit has surveys for it, run data-raw/survey/build_survey.R (it takes the last year from tornado_exposure). It queries the live service and rebuilds the whole layer, so the stored years can change if the service
#     changed: compare survey_matches and survey_exposure for the old years with the previous version before committing. Then rerun
#     data-raw/qa/11c, 44, 49, 44b, 45 and 46 (the tables and the pairing text of known_issues.md and the survey help).
#
# CHECKS OF THIS SCRIPT: data-raw/qa/31_test_incremental_update.R deletes the latest year from a copy of the data and re-adds it, requires the
# result to be identical to the stored data in every column, and tries the checks above.
#
# Environment (for tests): UPDATE_DATA_DIR (default "data"), UPDATE_PROV_DIR (default "data-raw"), UPDATE_LATEST_YEAR,
# UPDATE_DRY_RUN=true (everything but writing).

latest_year <- 2025

source("data-raw/pipeline_functions.R")          # before population_functions.R, which switches s2 off
latest_year <- as.integer(Sys.getenv("UPDATE_LATEST_YEAR", latest_year))
data_dir <- Sys.getenv("UPDATE_DATA_DIR", "data")
prov_dir <- Sys.getenv("UPDATE_PROV_DIR", "data-raw")
dry_run <- identical(tolower(Sys.getenv("UPDATE_DRY_RUN", "false")), "true")

# ---- 1. stored data ----------------------------------------------------------------
e <- new.env()
load(file.path(data_dir, "tornado_exposure.rda"), envir = e); load(file.path(data_dir, "tornado_tracks.rda"), envir = e)
load("data/zcta_centroids.rda", envir = e)
stored_exposure <- e$tornado_exposure; stored_tracks <- e$tornado_tracks; zcta_centroids <- e$zcta_centroids
last_year <- max(stored_exposure$year)
stopifnot("stored datasets disagree on the last year" = last_year == max(as.integer(substr(stored_tracks$tornado_id, 1, 4))))
message("Stored data: ", first_year, "-", last_year, " (", nrow(stored_tracks), " tornadoes, ", nrow(stored_exposure), " tornado-ZCTA rows)")
if (latest_year <= last_year) stop("Nothing to add: the stored data already run to ", last_year, " and latest_year is ", latest_year, ".", call. = FALSE)
new_years <- (last_year + 1):latest_year
no_vint <- setdiff(unique(vint_of(new_years)), unique(zcta_centroids$vintage))
if (length(no_vint)) stop("Years ", paste(new_years, collapse = ", "), " need the ", paste(no_vint, collapse = ", "), " Census vintage, which is not in zcta_centroids. Add the new decennial boundaries and block data by hand first (see the section NOT EXTENDED AUTOMATICALLY in the header of this script), then extend vint_of() in data-raw/pipeline_functions.R, R/geometry.R and the population scripts.", call. = FALSE)

# ---- 2. SPC file -----------------------------------------------------------------------
dl <- spc_download(latest_year)
raw <- read_csv(dl$file, show_col_types = FALSE)
message("SPC file ", dl$url, ": ", nrow(raw), " records, md5 ", dl$md5)
have <- unique(raw$yr[raw$sg == 1])
if (!all(new_years %in% have)) stop("The SPC file has no whole-track records for ", paste(setdiff(new_years, have), collapse = ", "), ". Wait until SPC announces the year in its change log.", call. = FALSE)
# information only: how the file's counts for the stored years compare with the stored data (SPC revises old years; they are not changed)
cnt <- table(factor(raw$yr[raw$sg == 1 & raw$yr %in% first_year:last_year], levels = first_year:last_year))
sto <- table(factor(as.integer(substr(stored_tracks$tornado_id, 1, 4)), levels = first_year:last_year))
d <- cnt - sto
message("Stored years: ", sum(d != 0), " of ", length(d), " have a different number of tornado records in this SPC file than in the stored data",
        if (any(d != 0)) paste0(" (largest difference ", d[which.max(abs(d))], " in ", names(d)[which.max(abs(d))], "); stored years are not changed") else "")

# ---- 3. new years: clean, geometry, ZCTA intersection (same code as the full rebuild) ---------
tornadoes <- spc_clean(raw, new_years)
b <- spc_build(tornadoes)
new_tracks <- b$tracks; new_exposure <- b$exposure

# ---- 4. population columns ---------------------------------------------------------------------
source("data-raw/population/population_functions.R")
states <- pop_states()
targets <- sf::st_sf(tid = new_tracks$tornado_id, kind = "modeled", vint = vint_of(as.integer(substr(new_tracks$tornado_id, 1, 4))), geometry = b$polygons)
pa <- list()
for (v in sort(unique(targets$vint))) {
  message("Population, vintage ", v, ": ", sum(targets$vint == v), " paths")
  pa[[as.character(v)]] <- pop_aff_cached(v, targets[targets$vint == v, c("tid", "kind")], states, zcta_layer(v)) %>% mutate(vint = v)
}
pa <- bind_rows(pa) %>% filter(!is.na(ZCTA)) %>% select(tornado_id = tid, vint, ZCTA, pop_affected = pop_aff)
zp <- zcta_centroids %>% transmute(vint = vintage, ZCTA, zcta_pop = as.numeric(zcta_pop))
x <- new_exposure
x$vint <- vint_of(x$year)
x <- x %>% left_join(pa, by = c("tornado_id", "vint", "ZCTA")) %>% left_join(zp, by = c("vint", "ZCTA"))
x$pop_affected[is.na(x$pop_affected)] <- 0
x$zcta_pop[is.na(x$zcta_pop)] <- 0
x$pop_prop_affected <- ifelse(x$zcta_pop > 0, x$pop_affected / x$zcta_pop, NA_real_)
x$vint <- NULL
new_exposure <- as.data.frame(x[, names(stored_exposure)])

# ---- 5. checks, then append ----------------------------------------------------------------------
check_new_rows(new_tracks, new_exposure, stored_tracks, stored_exposure, new_years)
message("Checks passed: ", nrow(new_tracks), " new tornadoes, ", nrow(new_exposure), " new tornado-ZCTA rows (", min(new_years), "-", max(new_years), ")")
tornado_exposure <- rbind(stored_exposure, new_exposure); rownames(tornado_exposure) <- NULL
tornado_tracks <- rbind(stored_tracks, new_tracks)
if (dry_run) { message("Dry run: nothing written."); quit(save = "no") }
save(tornado_exposure, file = file.path(data_dir, "tornado_exposure.rda"), compress = "xz")
save(tornado_tracks, file = file.path(data_dir, "tornado_tracks.rda"), compress = "xz")
writeLines(format(dl$access_date), file.path(prov_dir, "access_date.txt"))
record_spc_release(min(new_years), max(new_years), dl, "incremental update", prov_dir)
message("Wrote ", file.path(data_dir, c("tornado_exposure.rda", "tornado_tracks.rda")), " and the provenance files.\n",
        "Next: data-raw/qa/check_data_integrity.R; the QA scripts that write data-raw/known_issues.md; data-raw/qa/check_documented_claims.R; devtools::document(); devtools::check(); rebuild the README; cut a GitHub release.\n",
        "zcta_centroids and the NWS survey snapshot were not changed (see the header of data-raw/update_data.R).")
