# QA scripts

Scripts that check the bundled data and the model against other sources, and write the generated sections of
`data-raw/known_issues.md` and the survey help text. They are not part of the package build. Run each from the package
root, for example

    Rscript data-raw/qa/04_loss_reconciliation.R

Downloads (the SPC file, NCEI Storm Events, the National Weather Service Damage Assessment Toolkit layers) are cached in
`data-raw/qa/cache/`, and results go to `data-raw/qa/out/`; both folders are git-ignored. `helpers.R` finds the SPC file for
the release year in the data and warns if its checksum differs from `data-raw/provenance.txt`. The numbers in
`data-raw/known_issues.md` come from these scripts as run on the current data; run them again after a data change.

## After every data update, in this order

1. `check_data_integrity.R`: checks on the bundled datasets (unique keys, proportions in range, shares summing to 1, loss
   handling, survey tables). It stops with a list of the failed checks.
2. The scripts that save the numbers quoted in `known_issues.md` (`05`, `06`, `07`, `08`, `09`, `12`, `39`; the NCEI files they need are 232 MB in all) and the scripts that write `known_issues.md` and the survey help text (below).
3. `check_documented_claims.R`: rebuilds the help pages and the README in a temporary copy and compares them with the stored
   ones, recomputes the numbers written by hand in `known_issues.md` and the pairing text, and stops with a table if any differ.
   It also writes `out/numbers_without_a_script.csv`, the numbers that nothing recomputes.

## Scripts

| Script | What it checks or writes |
|--------|--------------------------|
| `00a`, `00b` | SPC state-segment records (`sg`), multi-state totals, ids from 2007 |
| `02_coordinate_rounding_run.R`, `02_coordinate_rounding_analysis.R` | How often the set of ZCTAs of a path changes when each coordinate is moved by up to half its rounding step (slow) |
| `03_crs_independence.R` | Area proportions in other equal-area projections |
| `04_loss_reconciliation.R` | Loss totals, allocation, unallocated loss, loss reliability |
| `05_ncei_loss_check.R` | SPC values versus NCEI Storm Events for two tornadoes |
| `06_zcta_integrity.R` | ZCTA format, codes per vintage (Census boundary year), codes that change or vanish |
| `07_point_tracks.R` | Point tracks by year, era and length, and whether coordinate rounding explains them |
| `08_no_zcta_tornadoes.R`, `08b` | Tornadoes that intersect no ZCTA, with maps (slow) |
| `09_state_mismatch.R` | Start points in a different state from the reported one |
| `10_path_offset_formula.R` | An estimate of the sideways offset of a curved path from the difference between `len` and the straight-line distance; it was a weak predictor of the surveyed offsets |
| `12_ncei_point_tracks.R` | Whether NCEI has end coordinates for point tracks |
| `11c_nws_dat_cases.R`, `11f_nws_plot_paths.R` | Four case studies of long, strong tornadoes against the live survey service (distances between the surveyed centerline and the modeled line, areas), and their plots |
| `38a_survey_polygons_full_resolution.R` | Fetches the damage polygons at full resolution, to test the effect of the 20 m generalization used in the layer |
| `38c_other_settings_tests.R`, `38d_settings_text.R` | Tests the minimum path width, the sanity limits of the update checks, the state margin and the radius factor, and writes the "Other fixed settings" section of `known_issues.md` (with `35`) |
| `39_spc_release_comparison.R` | How much SPC revised its records between its 2024 and 2025 releases (ids, ratings, injuries, fatalities, length, width, loss); downloads the 2024 file (8 MB) |
| `43_swath_filter_map.R` | Map of the swath filter for one tornado (written outside the repository) |
| `44_survey_pairing_numbers.R`, `44b_survey_pairing_text.R` | The date window (0, 1 and 2 days), the swath filter and the polygon resolution tested, and the counts of the pairing (`44`); the pairing text, status definitions and settings text in `data-raw/survey/*.md` (`44b`) |
| `45_survey_comparison.R` | Four pairing rules compared, and the two agreement tables of the survey layer against the SPC paths (`data-raw/survey/comparison_tables.md`) |
| `46_survey_path_accuracy.R` | Writes the Path accuracy and When-to-use sections of `known_issues.md` from `11c`, `44` and `45` and the data (calibration, area ratio, coverage by rating, year and chord length) |
| `47_no_zcta_details.R` | The 588 tornadoes with no ZCTA: categories, counts by Census boundary year, track type and state, the uncovered area, the 2000 file, a sample of 20, a map; writes its section of `known_issues.md` and `data-raw/no_zcta_categories.csv` |
| `48_first_map_timing.R` | Time and download size of the first and second `map_exposure()` call with an empty boundary-file cache |
| `49_date_window_check.R` | Pairs by survey date minus SPC date, and the CST/UTC explanation of 1-day differences; read by `44b` |
| `50_readme_numbers.R` | Collects the README numbers that come from other QA scripts into `data-raw/readme/numbers.csv` |
| `check_data_integrity.R`, `check_documented_claims.R` | See above |
| `13_counts.R` | Counts by rating, point-track and no-ZCTA shares |

Population checks (run after `data-raw/add_population.R`): `14_pop_block_zcta_2020.R` (block-to-ZCTA assignment against the
official 2020 relationship file), `15_pop_whole_block_checks.R` (whole-block and internal-point checks by state),
`16_pop_zcta_totals.R` (`zcta_pop` against official 2010 and 2000 ZCTA totals), `17_pop_integrity_joplin_swath.R`
(integrity, the Joplin shift test, modeled path versus surveyed swath), `18_pop_block_group_sensitivity.R` (blocks versus block
groups for 2020 on), `19_population_known_issues.R` (writes the Population section of `known_issues.md`),
`20_zcta_2000_gap.R` (official 2000 ZCTAs that have no polygon; writes the 2000 gap section), and
`35_population_candidate_check.R` (the preselection of candidate census blocks in `pop_aff_cached()` misses no block).

Distance and survey (run after `add_centroids.R` and `survey/build_survey.R`): `21a_centroid_table.R` and
`21b_distance_plan.R` (population-weighted centroids against geometric centroids, centroids outside their polygon, query
runtime), `23_distance_tables.R` (writes the distance, Moore and vintage sections of `known_issues.md`; set `REUSE=1` to skip
the slow queries), `36_special_cases.R` (writes the rating-by-year, special-track and territory notes of `known_issues.md`).

Updates and vintages: `29_zcta_vintage_overlap.R` (how much ZCTA codes change between Census boundary years),
`30_verify_pipeline.R` (the shared pipeline functions reproduce the stored data for all years),
`31_test_incremental_update.R` (deletes the latest year from a copy of the data, re-adds it with `data-raw/update_data.R`, and
tries the checks that must stop an update). `trials.R` runs user-facing trials (inputs and errors, a clean install).
