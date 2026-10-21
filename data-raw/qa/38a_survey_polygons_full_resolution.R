# Run from the package root: Rscript data-raw/qa/38a_survey_polygons_full_resolution.R
# Fetches the damage polygons from the Damage Assessment Toolkit service at full resolution (the polygons of the survey layer are fetched with
# the service's generalization set to 0.0002 degrees, about 20 m), for the same dates as the build, to test the effect of that generalization
# (data-raw/qa/44_survey_pairing_numbers.R). Result: data-raw/qa/out/dat_polys_2007_full.rds
source("data-raw/qa/helpers.R"); source("data-raw/survey/pairing_functions.R")
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE)
last_year <- 2025
P <- dat_fetch_layer(2, paste0("stormdate >= timestamp '2007-01-01 00:00:00' AND stormdate < timestamp '", last_year + 1, "-01-02 00:00:00'"), "efscale,stormdate,event_id,length,width")
cat("full-resolution polygons:", nrow(P$data), "\n"); saveRDS(P$data, qa_out("dat_polys_2007_full.rds")); cat("fetched", format(Sys.Date()), "\n")
