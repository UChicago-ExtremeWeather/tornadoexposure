# Incremental, append-only update of the bundled SPC data with a new SPC release, and the refresh of the DAT datasets.
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
#   3. Rscript data-raw/update_data.R            (SPC records, tracks, ZCTA exposure and the modeled population columns of the new years)
#   4. DAT refresh (the three layers are fetched whole again and the link tables are rebuilt; stored SPC years are not touched):
#        caffeinate -i Rscript data-raw/dat/fetch_dat.R      (about 30 minutes; writes data-raw/dat/access_date.txt)
#        Rscript data-raw/dat/build_dat.R                    (the DAT datasets, tornado_dat_link and dat_polygon_line_link; needs the SPC tables of step 3)
#      The service can change between fetches, so the stored DAT datasets are replaced, not appended to; compare the counts with the previous version before committing.
#   5. Follow-up: Rscript data-raw/qa/run_post_update_checks.R runs, in order: data-raw/qa/check_data_integrity.R (stops if a check on the data fails); the QA scripts that save the numbers quoted in
#      data-raw/known_issues.md (05, 06, 07, 08, 09, 12, 39 and the NCEI comparison 54b; the NCEI and SPC downloads are small, 8 MB for the SPC 2024 file and 232 MB for NCEI); the scripts that write the generated blocks of
#      data-raw/known_issues.md (19, 20, 23, 29, 36, 46, 47, 57, 60, 61, 62, 65, 66 and 68; 50 collects the README numbers); data-raw/qa/check_documented_claims.R (stops, with a table, if a number in the README, the help pages or the code
#      constants no longer matches); devtools::document(); data-raw/readme/build_readme.R (rebuilds the README: the counts and the maps in figures/); devtools::check(). Update the access dates in inst/CITATION. The update script itself adds the new
#      year's SPC release to data-raw/provenance_years.csv. The slow audits (02, 52b, 63, 64, 67) are run separately when the data change. Then cut a GitHub release.
#   6. Zenodo: upload by hand to the lab Zenodo account. Never use Zenodo's GitHub integration. A published record is permanent,
#      so confirm with the maintainer first. Versioning: bump Version and Date in DESCRIPTION, CITATION.cff and .zenodo.json (the new version number is the maintainer's decision; a yearly update adds a year of data
#      and does not change stored years), commit, publish a GitHub Release, then on the existing Zenodo record
#      click New version, upload the new Release zip, update the Version field, and publish. The "cite all versions" DOI
#      (10.5281/zenodo.23544841) is already in inst/CITATION and never changes. There is no separate data record, because the data
#      are bundled in the package.
#
# INSTALLED SIZE: R CMD check reports a NOTE that the installed size is above the 5 MB guideline of CRAN, because the DAT datasets are shipped whole and unmodified. The package is not
# published to CRAN, so the note is expected. The sizes of the data files are in data-raw/known_issues.md (section What the package provides).
#
# WHAT IT DOES
# Loads the stored spc_records, tornado_exposure and tornado_tracks, downloads the SPC file, and processes ONLY the years after the last
# stored year with the same code as the full rebuild (data-raw/pipeline_functions.R): the complete SPC records, tracks and tornado-level attributes,
# ZCTA exposure (with the distances), and the modeled population columns (from the per-state block results that data-raw/add_population.R cached outside the
# repository; only the blocks along the new paths are read; states that were never cached are processed in full). It checks the new
# rows against the stored ones and writes nothing if a check fails. Stored years are never changed, even if SPC has revised them
# (SPC revises magnitude, injuries, fatalities, len, wid and loss between releases, and changes ids: on 4 Jan 2021 reprocessing
# changed the ordering and some om numbers, and on 24 Apr 2026 SPC changed om_number from 2007 on to the format YYMMDDHHMM-01, so
# tornado_id is not stable across SPC releases). The script prints how many stored years have a different number of records in
# the new SPC file. It records which SPC download each year came from in data-raw/provenance_years.csv and data-raw/provenance.txt.
# No value is capped, imputed or replaced; a record that cannot be placed stops the update.
#
# STOP CONDITIONS (a clear message, nothing written)
#   * latest_year is not after the last stored year, or the SPC file has no whole-track records for a new year;
#   * a new year needs a Census boundary year that is not in zcta_centroids (see "Next decennial boundary year" below);
#   * an unexpected magnitude code (anything but -9 and 0 to 5);
#   * a whole-track record without a valid start location (the package never drops a record);
#   * the SPC loss unit break (2007) has moved: for years before 2007 the yearly median of nonzero loss must be at most 1 and the
#     maximum at most 10,000 (millions of dollars); from 2007 the yearly median must be at least 10,000 (dollars). SPC's 3 Jul 2018
#     entry says "Beginning with the 2016 data, loss values are in actual dollar amounts", and the 2025 file has 2007 to 2015 in dollars;
#   * the conversion of loss from millions to dollars is not exact (a value that is not a whole number of dollars up to floating-point error);
#   * a census block with an NA population, a duplicated block GEOID, or a share of a block inside a path above 1 by more than 1e-9 (nothing is capped);
#   * the columns or column types of the new rows differ from the stored ones, or the CRS differs;
#   * tornado_id does not match <year>_<om> (for example 2011_1105221634-01), is duplicated, or already exists in the stored data;
#   * the new rows contain years other than the ones being added;
#   * track coordinates outside latitude 15 to 72 and longitude -180 to -60; width outside 0 to 10,000 yards (a width of 0 is kept); length outside 0 to 400 miles
#     (sanity limits against corrupt records, not scientific values; the table of constants in data-raw/known_issues.md lists them);
#   * loss not in dollars: any new row with loss_raw_unit "millions", or a median of known loss below 10,000 or a maximum above 1e11 dollars
#     (sanity limits);
#   * property_loss_tornado_total not NA exactly where SPC's loss is 0 (NOAA says 0 does not mean $0), or modeled_property_loss_allocated not NA
#     exactly where the tornado total and the modeled path exist, or allocated loss not summing back to the total for a tornado with a known loss;
#   * the modeled columns not NA exactly for tornadoes with no usable end point and lines with a width of 0, modeled_area_prop not above 0, modeled_pop_prop outside [0, 1],
#     modeled_pop_affected above zcta_pop, or modeled_area_share_of_tornado not summing to 1 for every tornado with a modeled path.
#
# DOWNLOADS AND CACHES (sizes from data-raw/provenance_years.csv and data-raw/provenance_population.csv)
#   * SPC file 1950-<year>_all_tornadoes.csv: 9,219,030 bytes for 1950-2025.
#   * The full TIGER/Line ZCTA boundary file of the boundary year of the new years, through tigris (cached in ~/Library/Caches/tigris).
#   * The 2020 TIGER/Line tabulation blocks (tl_2020_<state>_tabblock20.zip) of the states that the new tornadoes touch: all 52 files are
#     10.33 GB (largest Texas 746 MB, smallest DC 4.7 MB, median 195 MB). They are cached in
#     ~/Library/Caches/org.R-project.R/R/tornadoexposure (set TORNADOEXPOSURE_CACHE to move it) together with the per-state results of
#     data-raw/add_population.R. Keep at least 10.4 GB free, and keep this cache between updates: without it, each touched state is
#     processed in full (every block is assigned to a ZCTA).
#   * A full rebuild (data-raw/add_centroids.R, then data-raw/process_tracks.R, data-raw/add_population.R and data-raw/dat/build_dat.R) reads 24.6 GB of population files (2020 blocks 10.3 GB, 2010 blocks 7.0 GB, 2000 blocks
#     5.8 GB, 2010 PL files 1.0 GB, 2000 PL files 0.4 GB), the three full ZCTA files through tigris and the SPC file; the DAT fetch is about 190 MB of JSON.
#     Manifest: data-raw/provenance_population.csv.
#
# NOT EXTENDED AUTOMATICALLY
#   * zcta_centroids: only needed when a new census boundary year is added; new years use the latest boundary year (2020).
#   * Next decennial boundary year (after the 2030 census), by hand: add the new ZCTA boundaries (tigris::zctas(year = 2030)) and the
#     tabulation blocks with population (check the file and field names), extend vint_of() in data-raw/pipeline_functions.R,
#     data-raw/add_population.R and data-raw/population/population_functions.R, .vintage_of() in R/distance.R, .plot_vintage() in
#     R/geometry.R and the file sizes in .full_zcta() of R/distance.R, and run data-raw/add_centroids.R for the boundary year (it appends rows). Only new years use it; stored years never change.
#   * The DAT datasets and link tables: refreshed whole by steps 4 above.
#
# CHECKS OF THIS SCRIPT: data-raw/qa/31_test_incremental_update.R deletes the latest year from a copy of the data, re-adds it, requires the
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
load(file.path(data_dir, "tornado_exposure.rda"), envir = e); load(file.path(data_dir, "tornado_tracks.rda"), envir = e); load(file.path(data_dir, "spc_records.rda"), envir = e)
load("data/zcta_centroids.rda", envir = e)
stored_exposure <- e$tornado_exposure; stored_tracks <- e$tornado_tracks; stored_records <- e$spc_records; zcta_centroids <- e$zcta_centroids
last_year <- max(stored_exposure$year)
stopifnot("stored datasets disagree on the last year" = last_year == max(as.integer(substr(stored_tracks$tornado_id, 1, 4))))
message("Stored data: ", first_year, "-", last_year, " (", nrow(stored_tracks), " tornadoes, ", nrow(stored_exposure), " tornado-ZCTA rows)")
if (latest_year <= last_year) stop("Nothing to add: the stored data already run to ", last_year, " and latest_year is ", latest_year, ".", call. = FALSE)
new_years <- (last_year + 1):latest_year
no_vint <- setdiff(unique(vint_of(new_years)), unique(zcta_centroids$vintage))
if (length(no_vint)) stop("Years ", paste(new_years, collapse = ", "), " need the ", paste(no_vint, collapse = ", "), " Census boundary year, which is not in zcta_centroids. Add the new decennial boundaries and block data by hand first (see the section NOT EXTENDED AUTOMATICALLY in the header).", call. = FALSE)

# ---- 2. SPC file -----------------------------------------------------------------------
dl <- spc_download(latest_year)
raw <- spc_read(dl$file)
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
b <- spc_build(tornadoes, zcta_centroids)
new_tracks <- b$tracks; new_exposure <- b$exposure
new_records <- spc_records(raw, new_years, tornadoes)

# ---- 4. modeled population columns ---------------------------------------------------------------------
source("data-raw/population/population_functions.R")
states <- pop_states()
hp <- b$has_poly
targets <- sf::st_sf(tid = new_tracks$tornado_id[hp], kind = "modeled", vint = vint_of(as.integer(substr(new_tracks$tornado_id[hp], 1, 4))), geometry = b$polygons)
pa <- list()
for (v in sort(unique(targets$vint))) {
  message("Population, boundary year ", v, ": ", sum(targets$vint == v), " paths")
  pa[[as.character(v)]] <- pop_aff_cached(v, targets[targets$vint == v, c("tid", "kind")], states, zcta_layer(v)) %>% mutate(vint = v)
}
pa <- bind_rows(pa) %>% filter(!is.na(ZCTA)) %>% select(tornado_id = tid, vint, ZCTA, pop = pop_aff)
x <- new_exposure
x$vint <- vint_of(x$year)
x <- x %>% left_join(pa, by = c("tornado_id", "vint", "ZCTA"))
shaped <- !is.na(x$modeled_intersection_m2)
x$modeled_pop_affected <- ifelse(shaped, ifelse(is.na(x$pop), 0, x$pop), NA_real_)
x$modeled_pop_prop <- ifelse(shaped & x$zcta_pop > 0, x$modeled_pop_affected / x$zcta_pop, NA_real_)
x$vint <- NULL; x$pop <- NULL
new_exposure <- as.data.frame(x[, names(stored_exposure)])

# ---- 5. checks, then append ----------------------------------------------------------------------
check_new_rows(new_tracks, new_exposure, stored_tracks, stored_exposure, new_years, new_records, stored_records)
message("Checks passed: ", nrow(new_tracks), " new tornadoes, ", nrow(new_exposure), " new tornado-ZCTA rows, ", nrow(new_records), " new SPC records (", min(new_years), "-", max(new_years), ")")
tornado_exposure <- rbind(stored_exposure, new_exposure); rownames(tornado_exposure) <- NULL
tornado_tracks <- rbind(stored_tracks, new_tracks)
spc_records <- rbind(stored_records, new_records); rownames(spc_records) <- NULL
if (dry_run) { message("Dry run: nothing written."); quit(save = "no") }
save(tornado_exposure, file = file.path(data_dir, "tornado_exposure.rda"), compress = "xz")
save(tornado_tracks, file = file.path(data_dir, "tornado_tracks.rda"), compress = "xz")
save(spc_records, file = file.path(data_dir, "spc_records.rda"), compress = "xz")
writeLines(format(dl$access_date), file.path(prov_dir, "access_date.txt"))
record_spc_release(min(new_years), max(new_years), dl, "incremental update", prov_dir)
message("Wrote ", file.path(data_dir, c("tornado_exposure.rda", "tornado_tracks.rda", "spc_records.rda")), " and the provenance files.\n",
        "Next: data-raw/dat/fetch_dat.R and data-raw/dat/build_dat.R (the DAT datasets and link tables are rebuilt whole); data-raw/qa/run_post_update_checks.R.\n",
        "zcta_centroids was not changed (see the header of data-raw/update_data.R).")
