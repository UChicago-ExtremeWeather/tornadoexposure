# QA scripts

Scripts that check the bundled data and the model against other sources, and write the generated blocks of
`data-raw/known_issues.md`. They are not part of the package build. Run each from the package
root, for example

    Rscript data-raw/qa/04_loss_reconciliation.R

Downloads (the SPC file, NCEI Storm Events, Census water polygons) are cached in
`data-raw/qa/cache/`, and results go to `data-raw/qa/out/`; both folders are git-ignored. `helpers.R` finds the SPC file for
the release year in the data and warns if its checksum differs from `data-raw/provenance.txt`. The numbers in
`data-raw/known_issues.md` come from these scripts as run on the current data; run them again after a data change.
The DAT fetch and its build are in `data-raw/dat/`, not here.

## After every data update

`run_post_update_checks.R` runs, in order:

1. `check_data_integrity.R`: checks on the bundled datasets (unique keys, SPC values identical to the SPC record, no shape-dependent value for point tornadoes, no cap, no rounding, boundary distance 0 where the line touches, every DAT feature kept, link tables, the St. Louis case). It stops with a list of the failed checks.
2. The scripts that save numbers (`05`, `06`, `07`, `08`, `09`, `12`, `39`, `54b`) and the scripts that write blocks of `known_issues.md` and the README numbers (`19`, `20`, `23`, `29`, `36`, `46`, `47`, `50`, `57`, `60`, `61`, `62`, `65`, `66`, `68`).
3. `check_documented_claims.R`: rebuilds the help pages and the README in a temporary copy and compares them with the stored ones, compares the constants that the documents state with the code, and stops with a table if any differ. It writes `out/numbers_without_a_script.csv` and the block "Numbers that no script recomputes".
4. `devtools::document()`, the README build and `devtools::check()`.

## Scripts

| Script | What it checks or writes |
|--------|--------------------------|
| `00a`, `00b` | SPC state-segment records (`sg`), multi-state totals, ids from 2007 |
| `02_coordinate_rounding_run.R`, `02_coordinate_rounding_analysis.R` | How often the set of ZCTAs a tornado touches changes when each coordinate is moved by up to half its rounding step (slow; read by `50` and `68`) |
| `03_crs_independence.R` | Area proportions in other equal-area projections |
| `04_loss_reconciliation.R` | Loss totals, allocation, unallocated loss, loss reliability |
| `05_ncei_loss_check.R` | SPC values versus NCEI Storm Events for two tornadoes |
| `06_zcta_integrity.R` | ZCTA format, codes per boundary year, codes that change or vanish |
| `07_point_tracks.R` | Tornadoes with no usable end point by year, era and length, and whether coordinate rounding explains them |
| `08_no_zcta_tornadoes.R`, `08b` | Tornadoes that touch no ZCTA, with maps (slow) |
| `09_state_mismatch.R` | Start points in a different state from the reported one |
| `10_path_offset_formula.R` | An estimate of the sideways offset of a curved path from the difference between `len` and the straight-line distance |
| `12_ncei_point_tracks.R` | Whether NCEI has end coordinates for tornadoes with no usable end point |
| `13_counts.R` | Counts by rating, no-end-point and no-ZCTA shares |
| `14` to `16`, `18`, `19`, `35` | Population checks: block-to-ZCTA assignment against the official 2020 relationship file, whole-block checks, `zcta_pop` against official totals, blocks against block groups, the Population block of `known_issues.md` (`19`), and the candidate-block preselection of `pop_aff_cached()` |
| `20_zcta_2000_gap.R`, `29_zcta_vintage_overlap.R` | Official 2000 ZCTAs that have no polygon; how much ZCTA codes change between boundary years |
| `21a_centroid_table.R`, `21b_distance_plan.R` | Population-weighted centroids against geometric centroids, centroids outside their polygon |
| `23_distance_tables.R` | The nationwide centroid-distance query by radius (the measured times used by `R/distance.R`) and the exposure definitions compared for the Joplin tornado |
| `30_verify_pipeline.R`, `31_test_incremental_update.R` | The pipeline functions reproduce the stored data; the update re-adds the latest year identically and its checks stop bad input |
| `36_special_cases.R` | Ratings by year, special tracks and territories |
| `39_spc_release_comparison.R` | How much SPC revised its records between its 2024 and 2025 releases; downloads the 2024 file (8 MB) |
| `46_path_accuracy.R` | Largest distance from the DAT centerline to the SPC line, by length |
| `47_no_zcta_details.R` | The tornadoes that touch no ZCTA: categories, counts, the uncovered area, the 2000 file, a sample, a map |
| `48_first_map_timing.R` | Time and download size of the first and second `map_exposure()` call with an empty boundary-file cache |
| `50_readme_numbers.R` | Collects the README numbers into `data-raw/readme/numbers.csv` |
| `51_dat_st_louis_extract.R` | Extracts the St. Louis event from every layer of the live DAT service into a GeoPackage outside the repository |
| `52b_block_validity_duplicates.R` | Invalid block polygons, duplicated GEOIDs, blocks whose internal point lies in more than one ZCTA |
| `54a_ncei_download.R`, `54b_ncei_comparison.R` | Downloads the NCEI Storm Events files for 2007 to 2025 and compares every SPC tornado with them (matching method in the header) |
| `57_dat_section.R`, `60`, `62`, `65`, `68` | Write the blocks "NWS damage-survey data (DAT)", "Tornadoes with no usable end point", the St. Louis example, "What the package provides" and the descriptive sections of `known_issues.md` |
| `61_fidelity_section.R` | Writes "What is and is not done to the source data" |
| `63_land_only_area_test.R`, `63b_land_only_tables.R`, `63c_land_share_effect.R`, `64_dat_exposure_design.R` | Tests of a land-only ZCTA shape built from the Census water polygons (the ratio of its area to ALAND, and what a land-only share would change), and the counts and table sizes behind a possible DAT exposure table (nothing is shipped) |
| `66_modeled_vs_dat.R` | The modeled columns against the NWS damage polygons that touch the linked line |
| `69_boundary_distance_check.R` | Recomputes `boundary_dist_km` for every row from the geometry (0 exactly where the line touches the ZCTA) |
| `67_compare_with_published.R` | The rebuilt tables against the tables of the published version (every unchanged column identical, every difference counted by cause) |
| `trials.R` | User-facing trials (inputs and errors, a clean install) |
