# Run from the package root after data-raw/update_data.R and data-raw/dat/build_dat.R and data-raw/dat/build_dat_exposure.R (or any change to the data):  caffeinate -i Rscript data-raw/qa/run_post_update_checks.R
# Runs, in the order the update instructions give (header of data-raw/update_data.R), the data checks, the QA scripts that save the numbers quoted in the documents, the scripts that write the
# generated blocks of data-raw/known_issues.md, the check of the documented numbers, the documentation build, the README and R CMD check. It stops at the first failure.
# Scripts that download large files or take hours (the population and DAT rebuilds, 02, 03, 48, 51, 52b, 54a, 67, 69 and the block audits) are not run here: see data-raw/qa/README.md.
steps <- c("data-raw/qa/check_data_integrity.R",
  paste0("data-raw/qa/", c("05_ncei_loss_check.R", "06_zcta_integrity.R", "07_point_tracks.R", "08_no_zcta_tornadoes.R", "09_state_mismatch.R", "12_ncei_point_tracks.R", "39_spc_release_comparison.R", "54b_ncei_comparison.R", "63_land_only_report.R",
    "19_population_known_issues.R", "20_zcta_2000_gap.R", "23_distance_tables.R", "29_zcta_vintage_overlap.R", "36_special_cases.R", "46_path_accuracy.R", "47_no_zcta_details.R", "50_readme_numbers.R", "66_spc_vs_dat.R", "72_far_rows_and_ratings.R", "70_land_section.R", "71_dat_exposure_section.R",
    "57_dat_section.R", "60_no_end_point_section.R", "62_st_louis_section.R", "65_provides_section.R", "68_known_issues_core.R", "61_fidelity_section.R")),
  "data-raw/qa/check_documented_claims.R", "document", "data-raw/readme/build_readme.R", "check")
run <- function(cmd) { cat("\n==== ", cmd, "\n"); if (cmd == "document") { devtools::document(); return(invisible()) }; if (cmd == "check") { r <- devtools::check(args = "--no-manual", error_on = "error"); return(invisible()) }
  if (!file.exists(cmd)) stop("missing script: ", cmd, call. = FALSE); st <- system2("Rscript", cmd); if (st != 0) stop("failed: ", cmd, call. = FALSE) }
invisible(lapply(steps, run)); cat("\nAll post-update checks finished.\n")
