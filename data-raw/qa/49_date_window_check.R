# Run from the package root after data-raw/survey/build_survey.R:  Rscript data-raw/qa/49_date_window_check.R
# Pairs of the survey layer by the difference between the survey date and the SPC date (0 days, or 1 day later or earlier): distance, length ratio, same state,
# usable swath, and one possible explanation of the 1-day differences: SPC records times converted to CST (a fixed UTC-6), so an evening storm can fall on the next
# calendar date in a source that uses UTC or local time. SPC database description, field 7 (tz): "All times, except for ?=unknown and 9=GMT, were converted to 3=CST";
# the older format document (torforma.doc) says the same. Result: data-raw/qa/out/date_window_check.rds
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220)
source("data-raw/qa/helpers.R"); source("data-raw/survey/pairing_functions.R")
load("data/tornado_tracks.rda"); load("data/survey_matches.rda")
ctx <- survey_context(); list2env(ctx, environment()); sm <- survey_matches
pr <- candidate_distances(Du, Tt, sp, sv, 1); M <- mutual_closest(pr)
M$tornado_id <- Tt$tornado_id[M$k]; M$diff <- as.integer(Du$date[M$i] - Tt$date[M$k])
raw <- read.csv(qa_spc_csv()) %>% filter(yr >= 2007, sg == 1) %>% mutate(tornado_id = paste(yr, om, sep = "_")) %>% filter(!duplicated(tornado_id))
M$time <- raw$time[match(M$tornado_id, raw$tornado_id)]; M$tz <- raw$tz[match(M$tornado_id, raw$tornado_id)]
M$hour <- as.integer(substr(M$time, 1, 2)) + as.integer(substr(M$time, 4, 5)) / 60
sm1 <- sm[match(M$tornado_id, sm$tornado_id), ]; M$length_ratio <- sm1$length_ratio; M$same_state <- sm1$same_state; M$usable <- sm1$status == "included"
cat("SPC time zone codes of the paired tornadoes:", paste(names(table(M$tz)), table(M$tz), sep = ": ", collapse = "; "), "\n")
q <- function(x) signif(quantile(x, c(.5, .9), na.rm = TRUE, names = FALSE), 3)
grp <- function(d, lab) data.frame(group = lab, pairs = nrow(d), median_dist_km = q(d$dist_km)[1], p90_dist_km = q(d$dist_km)[2], median_length_ratio = q(d$length_ratio)[1], p90_length_ratio = q(d$length_ratio)[2], same_state = round(100 * mean(d$same_state, na.rm = TRUE), 1), usable = round(100 * mean(d$usable), 1))
tab <- bind_rows(grp(M[M$diff == 0, ], "same date"), grp(M[M$diff != 0, ], "date differs by 1 day"), grp(M[M$diff == 1, ], "survey date 1 day later"), grp(M[M$diff == -1, ], "survey date 1 day earlier")); print(tab, row.names = FALSE)
cat("pairs by date difference:\n"); print(table(M$diff))
hr <- function(d) c(n = nrow(d), median_hour = round(median(d$hour, na.rm = TRUE), 1), share_18_or_later = round(100 * mean(d$hour >= 18, na.rm = TRUE), 1), share_23_or_later = round(100 * mean(d$hour >= 23, na.rm = TRUE), 1), share_before_06 = round(100 * mean(d$hour < 6, na.rm = TRUE), 1), share_before_01 = round(100 * mean(d$hour < 1, na.rm = TRUE), 1))
hrs <- rbind(`same date` = hr(M[M$diff == 0, ]), `survey 1 day later` = hr(M[M$diff == 1, ]), `survey 1 day earlier` = hr(M[M$diff == -1, ])); print(hrs)
# SPC time of day in 3-hour bins, by direction
M$bin <- cut(M$hour, c(0, 3, 6, 9, 12, 15, 18, 21, 24), right = FALSE); print(table(M$bin, M$diff))
# which date matches: the SPC date in CST, or the date in UTC (CST + 6 hours)?
M$utc_date <- as.Date(M$date <- Tt$date[M$k]) + ifelse(M$hour >= 18, 1, 0); M$survey_date <- Du$date[M$i]
cmp <- data.frame(`survey date equals` = c("SPC date (CST) only", "UTC date of the SPC time only", "both", "neither"), pairs = c(sum(M$survey_date == M$date & M$survey_date != M$utc_date), sum(M$survey_date == M$utc_date & M$survey_date != M$date), sum(M$survey_date == M$date & M$survey_date == M$utc_date), sum(M$survey_date != M$date & M$survey_date != M$utc_date)), check.names = FALSE); print(cmp)
# the survey stormdate is a date-time (milliseconds since 1970, UTC): compare with the SPC time converted to UTC (CST + 6 hours)
spc_utc <- as.POSIXct(paste(M$date, M$time), tz = "UTC") + 6 * 3600; svy_utc <- as.POSIXct(Du$stormdate[M$i] / 1000, origin = "1970-01-01", tz = "UTC"); dh <- as.numeric(difftime(svy_utc, spc_utc, units = "hours"))
dt_tab <- data.frame(n = sum(!is.na(dh)), median_hours = round(median(dh, na.rm = TRUE), 2), p10 = round(quantile(dh, .1, na.rm = TRUE), 2), p90 = round(quantile(dh, .9, na.rm = TRUE), 2), within_1h = round(100 * mean(abs(dh) <= 1, na.rm = TRUE), 1), within_3h = round(100 * mean(abs(dh) <= 3, na.rm = TRUE), 1), same_hour_of_day_as_survey = round(100 * mean(abs(dh) <= 0.01, na.rm = TRUE), 1))
cat("survey time minus SPC time in UTC (hours): "); print(dt_tab, row.names = FALSE)
late <- M[M$diff == 1, ]; early <- M[M$diff == -1, ]
cat("survey date 1 day later: SPC time 18:00 or later:", sum(late$hour >= 18, na.rm = TRUE), "of", nrow(late), "\n"); cat("survey date 1 day earlier: SPC time before 06:00:", sum(early$hour < 6, na.rm = TRUE), "of", nrow(early), "\n")
saveRDS(list(tab = tab, by_diff = table(M$diff), hours = hrs, bins = table(M$bin, M$diff), cmp = cmp, tz = table(M$tz), late = c(sum(late$hour >= 18, na.rm = TRUE), nrow(late)), early = c(sum(early$hour < 6, na.rm = TRUE), nrow(early)), dt_tab = dt_tab, n_pairs = nrow(M)), qa_out("date_window_check.rds"))
