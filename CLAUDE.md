# Project brief: refactor `tornadoexposure` to v0.2.0

Owner: Kate (co-PI). This file is your standing instructions. Read all of it before doing anything.

## Context

`tornadoexposure` is one of a family of R packages that provide pre-processed US environmental exposure data at common spatial units (ZCTA here) so researchers can install a package and load data without assembling it from raw sources. The lab template is the `exposure_template` repo and the lab conventions are in `team_docs/how_we_build_exposure_packages.md` (if you can read them; otherwise rely on this brief).

This package already exists (v0.1.0). The goal is to bring it up to the template's standards, fix an analytic error in the exposure calculation, and redesign the API. The data is small, so it stays bundled in the package as `.rda`. Do NOT adopt the template's Zenodo, `arrow`, or Parquet machinery.

## Working rules

1. You are running in a cloud session against the GitHub repo. Work only on the branch `refactor-0.2.0` (create it from `main` when you reach step 1 if it does not exist; step 0 pushes nothing). Kate will paste this brief into the session, so include it as `CLAUDE.md` in your first commit in step 1. You may push commits to that branch only. Never push to `main`, never merge, never change GitHub repo settings, and never change where the repo lives. Open a DRAFT pull request into `main` at the end, and Kate will review and merge it herself. The repo lives at `UChicago-ExtremeWeather/tornadoexposure`. The current README install command and the `DESCRIPTION` `URL` and `BugReports` fields point to `hailhan/tornadoexposure`; update them to the org URL (confirm with `git remote -v`).
2. START WITH A READ-ONLY PASS. Inspect the repo, run `devtools::check()` to get a baseline, run the data audit below, and report findings. Make no edits and push nothing until Kate approves the plan.
   - First check the cloud environment and report the result: is R installed, are `devtools`, `sf`, `tigris`, `usethis`, and `testthat` installable (sf needs system spatial libraries such as GDAL, GEOS, and PROJ), and is there network access to `www.spc.noaa.gov` and the Census Bureau download servers that `tigris` uses? Note the VM's CPU, memory, and disk limits.
   - If something is missing, report it and propose a setup script. Do NOT change the methods in this brief to work around a missing tool, and do not substitute made-up or cached data.
3. Then work in small commits, one per step in the task order below. Show me each diff summary.
4. Run `devtools::document()` after any roxygen change and `devtools::check()` after each major step.
5. If something in this brief conflicts with what you find in the repo, or an item is marked OPEN, stop and ask. Never guess about data. Never invent citations, DOIs, author names, or numbers.
6. Do not use em dashes in any text you write (docs, README, comments).

## Decisions already made (do not relitigate)

- Data stays bundled as compressed `.rda` (`usethis::use_data(..., compress = "xz")`). No Parquet, no `arrow`, no Zenodo data record. One Zenodo record only (the code archive, created automatically from a GitHub release).
- Package license: `GPL (>= 2)`.
- No county level. `geography` exists for cross-package consistency and accepts only `"zcta"`.
- No untouched-ZCTA output. `area_thresh = 0` is NOT allowed.
- No changes to the `team_docs` repo.
- Property loss is allocated to ZCTAs by area share (normalized), stored alongside the original tornado total. Injuries and fatalities are not allocated. All of this must be documented in `R/data.R`, the README, and `NEWS.md`.

## Exposure definition

A ZCTA is exposed to a tornado when the area of the tornado track that falls inside the ZCTA, divided by the ZCTA's land area (`ALAND`), is at least `area_thresh`. The threshold is a proportion from 0 to 1 (0.5 means half the ZCTA). It is applied per tornado, not cumulatively across tornadoes. Document this.

## Data pipeline rewrite (`data-raw/process_tracks.R`)

Current analytic error: `st_join` duplicates each tornado per ZCTA, but `area_pct_affected` divides the WHOLE tornado's area by each ZCTA's area, so a tornado crossing several ZCTAs is credited full area in each. Areas are also computed in EPSG:3857, which distorts area at US latitudes.

Required method:
1. Build each tornado's track polygon by buffering the track by half its width, with FLAT end caps (default round caps add area). Convert width from yards to meters (`wid * 0.9144`).
2. Do all area work in an equal-area CRS (EPSG:5070).
3. Intersect each track polygon with the ZCTA polygons of the correct Census vintage (2000 file for years before 2010, 2010 file for 2010 to 2019, 2020 file for 2020 onward, as in the current script). Join on the buffered polygon, not the centerline, so ZCTAs touched by the width but missed by the centerline are included.
4. For each tornado-ZCTA pair, compute `intersection_area / ZCTA ALAND`. Store as a proportion named `area_prop_affected` (0 to 1). OPEN: Kate to confirm the proportion convention and column rename (recommended so the column matches `area_thresh`).
5. Drop exact-zero areas. Report how many rows have proportions below 1e-6 (slivers) and how many exceed 1 (possible water/land mismatch: tigris ZCTA polygons likely include water, while ALAND does not). Do not silently cap. Report and ask. Kate has chosen ALAND as the denominator.
6. Compute `area_share_of_tornado` and `property_loss_allocated` as defined in the outputs section. Verify per tornado that shares sum to 1 (within tolerance) and that allocated losses sum back to the tornado total.
7. Keep the existing filters (year >= 1996, magnitude >= 1) unless the audit shows a problem.

Modeling assumption to document (Kate approved area-proportional allocation): damage is assumed to be spread evenly over the track's area. This can misattribute loss when a tornado crosses a sparsely settled ZCTA for most of its length but hits a dense one briefly. Population or building-density weighting would be better but needs another data source, so it is out of scope. Do not claim the allocation is accurate; call it an area-weighted approximation.

Outputs (two datasets, saved to `data/`):
- `tornado_exposure`: one row per tornado-ZCTA, NO geometry. Columns: `tornado_id`, `date`, `year`, `month`, `day`, `magnitude`, `total_injury`, `total_fatality`, `property_loss_tornado_total`, `property_loss_allocated`, `ZCTA`, `area_prop_affected`, `area_share_of_tornado`.
  - `area_prop_affected` = intersection area / ZCTA ALAND (used for `area_thresh`).
  - `area_share_of_tornado` = intersection area / sum of that tornado's intersection areas across all ZCTAs it crossed (normalized so shares sum to 1 per tornado; this fully distributes loss across ZCTAs the tornado actually crossed, since any part over water or outside a ZCTA is assumed to carry no damage).
  - `property_loss_tornado_total` = the original tornado-level `loss` value, repeated on every row for that tornado (do NOT sum it across rows).
  - `property_loss_allocated` = `property_loss_tornado_total * area_share_of_tornado`. Summing it across a tornado's rows recovers the tornado total.
  - Injuries and fatalities are NOT allocated (allocation would produce fractional people). They stay as tornado-level totals, repeated per row, and must be labeled that way everywhere.
- `tornado_tracks`: one row per tornado, `tornado_id` plus track LINESTRING geometry, stored in EPSG:4326.

Parametrize the script: a `latest_year` variable at the top builds the NOAA URL (`https://www.spc.noaa.gov/wcm/data/1950-<latest_year>_all_tornadoes.csv`), and the script records the access date for use in docs.

### Data audit (report BEFORE fixing; these are hypotheses to test, not known problems)

- Rows where end coordinates are 0 (some SPC records may use 0 for unknown ends). `!is.na()` would not catch them and would create huge bogus tracks.
- The current script drops tornadoes where start equals end. Count them. They are real tornadoes. If many, propose buffering the start point instead.
- Rows with width 0 or missing, and magnitude -9 (unknown).
- Duplicate `tornado_id` values (check NOAA's database description for how multi-state tornadoes are recorded, which could double count injuries and fatalities).
- Units of `loss`. The current README says that after 1996 it is coded as either actual dollars or amounts in thousands of dollars. Read NOAA's database description (link below) and report exactly how `loss` is coded and whether it can be harmonized to dollars. Do NOT harmonize or allocate until Kate approves; if it cannot be harmonized reliably, the allocated column must carry a prominent warning in the docs.
- Confirm tigris column names for each vintage (`ZCTA5CE00`/`ALAND00`, `ZCTA5CE10`/`ALAND10`, `ZCTA5CE20`/`ALAND20`) by running the code.
- SPC `wid` may be the maximum width. If so, a constant-width rectangle gives an upper bound on area. Document as a limitation after checking NOAA's documentation: https://www.spc.noaa.gov/wcm/data/SPC_severe_database_description.pdf

## API redesign (`R/`)

Keep the template argument order (`geography` first) for cross-package consistency.

```r
get_data(geography = "zcta", geo_list, year_range,
         magnitude = 1:5, area_thresh = NULL)

map_exposure(geography = "zcta", geo_list, year_range, feature = NULL,
             magnitude = 1:5, area_thresh = NULL)

add_tracks(geography = "zcta", geo_list, year_range, plot,
           magnitude = 1:5, area_thresh = NULL)
```

- `zcta_list` is renamed `geo_list`. `mag_thresh` is replaced by `magnitude`, a vector of EF values to include (a minimum EF3 is `magnitude = 3:5`).
- `area_thresh`: `NULL` (default) returns any tornado touching the ZCTA. A number in (0, 1] returns rows with `area_prop_affected >= area_thresh`. `0` is an error with a clear message explaining that untouched ZCTAs are not returned and `NULL` means any exposure.
- `get_data()` returns a plain data frame, no geometry, one row per tornado-ZCTA. `add_tracks()` should find the matching `tornado_id`s from `get_data()` and draw those tracks from `tornado_tracks`, replacing the current `st_filter` approach.
- Input validation in a shared helper, with friendly messages. Specifically, fix the argument-misuse problem: a call like `get_data(c(648), 2010:2015)` puts the ZCTAs in `geography`. Detect this (non-character or invalid `geography`) and error with a message such as: `geography must be "zcta". Did you mean get_data(geo_list = ..., year_range = ...)? Use named arguments.` Also error clearly if `geo_list` or `year_range` is missing, `magnitude` has values outside 1 to 5, or `area_thresh` is out of range.
- ZCTA input: prefer character strings. Numeric input loses leading zeros (02139 becomes 2139), which breaks matching in the Northeast. Warn on numeric input and document strings in the README and roxygen. Prefix matching (1 to 5 digits) stays.
- `map_exposure()` feature labels currently say "(Per Tornado)" but the values are sums across tornadoes. Fix the labels. Document that injury and fatality values are tornado-level counts attributed to every ZCTA the tornado touched.
- Test whether `get_geometry()` standardizes the ZCTA column for the 2000 vintage (the 2010 and 2020 branches rename, the 2000 branch returns the boundary unchanged). Document that a year range spanning vintages is plotted on one boundary vintage.
- Package hygiene so `devtools::check()` is clean: declare or import `.data` (use rlang's pronoun or `utils::globalVariables`), use `stats::median`, use `.data$year` etc. inside dplyr verbs, remove the `mag_thresh` doc/formals mismatch, delete unused imports (check whether `purrr` is still needed), and remove dead code only with approval (for example `get_basemap()`, which looks unused).

## Package files

- `DESCRIPTION`: version 0.2.0; `Authors@R` instead of `Author`/`Maintainer` (OPEN: Kate to confirm authors and order; use Hailey Hansen as author/maintainer unless told otherwise); `License: GPL (>= 2)`; fix Description text to the correct year range (data covers 1996 to the latest year, not 1954); remove nothing from `Imports` that is still used; add `testthat` to `Suggests`.
- License file: use `usethis::use_gpl_license(version = 2, include_future = TRUE)` (verify the arguments) so `LICENSE.md` exists and `.Rbuildignore` is updated.
- `.gitignore` and `.Rbuildignore`: merge carefully. CRITICAL: the template `.gitignore` ignores `data/`, which would exclude the bundled `.rda` data from git. Do NOT copy that line. Keep `scratch/`. Remove stale entries (for example `STUDENT_CHECKLIST.md`), and add `CLAUDE.md` to `.Rbuildignore`.
- Do not add the template's `R/data_access.R` or `data-raw/process_data.R` (Zenodo/arrow stubs). Delete stray `exposuretemplate.Rproj` and any duplicated files. Delete `checklist.md` only at the very end, after Kate confirms.
- `R/data.R`: document both datasets with roxygen. Compute row counts from the actual data after the rebuild; do not hardcode old numbers. Update the data-access date. Document every column, and explicitly define `area_prop_affected` vs `area_share_of_tornado` (different denominators), `property_loss_tornado_total` (tornado-level, do not sum across rows) vs `property_loss_allocated` (area-weighted approximation, assumption stated, units caveat), and that injuries and fatalities are tornado-level totals attributed to every ZCTA the tornado touched.
- `inst/CITATION`: one entry for the package (code and bundled data, one DOI), plus the NOAA SPC Severe Weather Database as the data source with URL and access date. Leave the DOI as a clearly marked placeholder to be filled after the GitHub release and Zenodo record exist. Do not invent author names or DOIs.
- `NEWS.md`: record the breaking changes (argument renames, new datasets, corrected area calculation, renamed `area_prop_affected` column, and the new `area_share_of_tornado`, `property_loss_tornado_total`, and `property_loss_allocated` columns with a one-line explanation of each).
- Tests: add `testthat` tests, including: prefix matching and leading-zero handling; `area_thresh = 0` errors; `area_thresh` bounds; `magnitude` vector filtering; the argument-misuse error; all `area_prop_affected` in (0, 1]; a conservation check that for each tornado the summed intersection areas across ZCTAs do not exceed the tornado's total buffered area; `area_share_of_tornado` sums to 1 per tornado; and `property_loss_allocated` sums back to `property_loss_tornado_total` per tornado.
- `README.md`: follow the template structure (intro paragraph on what, data source and provider, geography, and year range; Set-up; Data with variable table; Functions with a runnable example and output image for each; Citation). Use named arguments in every example. State the limitations: EF0 excluded, vintage handling, tornado-level injury and fatality counts, width assumption, and that exposure thresholds are per tornado. Add a dedicated section on property loss that explains: the tornado-level total vs the allocated column, how `area_share_of_tornado` is computed and normalized, the even-spread assumption and when it fails (a tornado crossing a sparse area for most of its length but hitting a dense one briefly), the units caveat from the audit, and a warning that allocated losses should be used with caution and not summed across tornadoes until units are harmonized. Include a short worked example (for instance, a tornado with 99 percent of its area in one ZCTA gets 99 percent of its loss assigned there). Update the variable table to include every new column. Regenerate every image in `figures/` because the numbers will change. Point to the single DOI placeholder.
- Draft the tornado entry for the lab's `updating_packages.md` and save it as `updating_packages_tornado.md` in the repo root (NOT in `scratch/`, which is gitignored and would not be pushed), add it to `.Rbuildignore`, and tell Kate to paste it into `team_docs` herself and then delete the file. Cover: source and annual release timing (NOAA SPC), the refresh procedure (change `latest_year`, rerun `data-raw/process_tracks.R`, `devtools::document()`, `devtools::check()`), the fact that there is no separate data record, so after a refresh you only cut a new GitHub release and the code archive in Zenodo updates automatically, and notes on the Census vintage logic.

## Task order

0. Read-only pass: baseline `check()`, data audit, plan. Wait for approval.
1. Housekeeping: `.gitignore`, `.Rbuildignore`, stray files, `DESCRIPTION`, license file.
2. Rewrite `data-raw/process_tracks.R` and rebuild the two datasets. Report counts and diagnostics before committing the data.
3. Rewrite `R/` functions, validation helper, and roxygen. Regenerate `man/` and `NAMESPACE`.
4. Tests.
5. README, figures, `inst/CITATION`, `NEWS.md`, `R/data.R`.
6. Final `devtools::check()` clean (no errors or warnings; explain any notes), then summarize for Kate. Deleting `checklist.md` and cutting the release happen only on her say-so.
