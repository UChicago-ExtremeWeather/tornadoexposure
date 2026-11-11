# Run from the package root after data-raw/update_data.R (or any change to the data):  caffeinate -i Rscript data-raw/qa/run_post_update_checks.R
# Runs, in the order the update instructions give (header of data-raw/update_data.R), the data checks, the QA scripts that save the numbers quoted in the documents, the scripts that write the
# generated sections of data-raw/known_issues.md, the check of the documented numbers, the documentation build, the README and R CMD check. It stops at the first failure.
# Scripts that download large files (the population and survey rebuilds, 53 and the 52b/52c block audits) are not run here: see data-raw/qa/README.md.
steps <- list(
  c("Rscript", "data-raw/qa/check_data_integrity.R"),
  paste0("data-raw/qa/", c("05_ncei_loss_check.R", "06_zcta_integrity.R", "07_point_tracks.R", "08_no_zcta_tornadoes.R", "09_state_mismatch.R", "12_ncei_point_tracks.R", "39_spc_release_comparison.R", "02_coordinate_rounding_run.R", "29_zcta_vintage_overlap.R")),
  paste0("data-raw/qa/", c("11c_nws_dat_cases.R", "19_population_known_issues.R", "20_zcta_2000_gap.R", "23_distance_tables.R", "36_special_cases.R", "38d_settings_text.R", "44_survey_pairing_numbers.R", "49_date_window_check.R", "44b_survey_pairing_text.R", "45_survey_comparison.R", "46_survey_path_accuracy.R", "47_no_zcta_details.R", "60_no_end_point_section.R", "61_fidelity_section.R", "62_st_louis_section.R", "48_first_map_timing.R", "50_readme_numbers.R")),
  "data-raw/qa/check_documented_claims.R", "document", "data-raw/readme/build_readme.R", "check")
run <- function(cmd) { cat("\n==== ", cmd, "\n"); if (cmd == "document") { devtools::document(); return(invisible()) }; if (cmd == "check") { r <- devtools::check(args = "--no-manual", error_on = "error"); return(invisible(r)) }
  if (!file.exists(cmd)) stop("missing script: ", cmd, call. = FALSE); st <- system2("Rscript", cmd); if (st != 0) stop("failed: ", cmd, call. = FALSE) }
steps <- unlist(lapply(steps, function(s) if (identical(s[1], "Rscript")) s[2] else s)); invisible(lapply(steps, run)); cat("\nAll post-update checks finished.\n")
