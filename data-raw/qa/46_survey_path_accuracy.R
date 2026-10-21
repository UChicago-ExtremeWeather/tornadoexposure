# Run from the package root after data-raw/survey/build_survey.R, 11c, 44 and 45:  caffeinate -i Rscript data-raw/qa/46_survey_path_accuracy.R
# Writes the "Path accuracy" and "When to use SPC and when to use the survey data" sections of data-raw/known_issues.md. Every number is computed
# from the data or from the saved results of the scripts named above.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 200)
source("data-raw/qa/helpers.R"); source("data-raw/survey/pairing_functions.R")
for (f in c("tornado_tracks", "survey_matches", "survey_exposure", "tornado_exposure")) load(file.path("data", paste0(f, ".rda")))
sm <- survey_matches; ctx <- survey_context(); list2env(ctx, environment())
fmt <- function(x, d = 2) formatC(x, format = "f", digits = d, big.mark = ","); pct <- function(x, d = 1) paste0(formatC(100 * x, format = "f", digits = d), "%"); nfmt <- function(x) formatC(x, format = "d", big.mark = ",")
md_table <- function(df) paste(c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"), apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))), collapse = "\n")
tt <- st_drop_geometry(Tt); tt$status <- sm$status[match(tt$tornado_id, sm$tornado_id)]; tt$year <- as.integer(substr(tt$tornado_id, 1, 4))
tt$rating <- ifelse(is.na(tt$magnitude), "unknown", paste0("EF", tt$magnitude)); tt$chord_mi <- ifelse(sp$is_line, sp$chord_km / 1.609344, NA)
tt$chord_class <- ifelse(!sp$is_line, "point track", as.character(cut(tt$chord_mi, c(-1, 5, 20, 1e4), labels = c("under 5 mi", "5-20 mi", "over 20 mi"), right = FALSE)))
tt$paired <- tt$status != "no_pair"; tt$usable <- tt$status == "included"
# ---- coverage ---------------------------------------------------------------------------------------------------------------------------------------------
cov_by <- function(g, label) tt %>% group_by(.data[[g]]) %>% summarise(n = n(), paired = sum(paired), usable = sum(usable), .groups = "drop") %>% rename(key = 1) %>%
  transmute(!!label := key, `SPC tornadoes since 2007` = nfmt(n), Paired = nfmt(paired), `Share paired` = pct(paired / n), `With a usable swath` = nfmt(usable), `Share with a usable swath` = pct(usable / n))
tot_row <- function(label, key) tt %>% summarise(n = n(), paired = sum(paired), usable = sum(usable)) %>% transmute(!!label := key, `SPC tornadoes since 2007` = nfmt(n), Paired = nfmt(paired), `Share paired` = pct(paired / n), `With a usable swath` = nfmt(usable), `Share with a usable swath` = pct(usable / n))
ord_r <- c("EF0", "EF1", "EF2", "EF3", "EF4", "EF5", "unknown")
cov_r <- bind_rows(cov_by("rating", "Rating")[match(ord_r, cov_by("rating", "Rating")$Rating), ], tot_row("Rating", "all"))
cov_y <- bind_rows(cov_by("year", "Year") %>% mutate(Year = as.character(Year)), tot_row("Year", "all"))
cc_ord <- c("under 5 mi", "5-20 mi", "over 20 mi", "point track"); cv <- cov_by("chord_class", "Chord length"); cov_c <- bind_rows(cv[match(cc_ord, cv$`Chord length`), ], tot_row("Chord length", "all"))
yy <- tt %>% group_by(year) %>% summarise(sh = mean(usable), .groups = "drop"); early <- mean(tt$usable[tt$year <= 2010]); late_rng <- range(yy$sh[yy$year >= 2020])
chord_all <- median(tt$chord_mi, na.rm = TRUE); chord_use <- median(tt$chord_mi[tt$usable], na.rm = TRUE); long_all <- mean(tt$chord_mi > 20, na.rm = TRUE); long_use <- mean(tt$chord_mi[tt$usable] > 20, na.rm = TRUE)
# ---- calibration: surveyed centerline against the modeled straight line, for the tornadoes with a usable swath (line tracks) --------------------------------
pairs <- data.frame(k = match(sm$tornado_id[sm$status == "included"], Tt$tornado_id)); pairs$i <- match(sm$survey_line_id[sm$status == "included"], as.integer(Du$objectid)); pairs <- pairs[sp$is_line[pairs$k] & !is.na(pairs$i), ]
cal <- bind_rows(lapply(seq_len(nrow(pairs)), function(r) { k <- pairs$k[r]; i <- pairs$i[r]; surv <- sv$L5[i]; mod <- st_sfc(st_linestring(rbind(sp$s5[k, ], sp$e5[k, ])), crs = 5070)
  n <- max(3, ceiling(as.numeric(st_length(surv)) / 500) + 1); p <- st_cast(st_line_sample(surv, n = n), "POINT"); d <- as.numeric(st_distance(p, mod)) / 1000
  chord_mi <- sp$chord_km[k] / 1.609344; len <- Tt$len_mi[k]
  data.frame(tornado_id = Tt$tornado_id[k], chord_mi = chord_mi, spc_len = len, med_km = median(d), max_km = max(d), half_km = Tt$wid_yd[k] * 0.9144 / 2 / 1000, s_km = 1.609344 * ifelse(len > chord_mi, sqrt(3 * chord_mi * (len - chord_mi) / 8), 0)) }))
cal$cls <- cut(cal$chord_mi, c(0, 5, 20, 1e3), labels = c("under 5 mi", "5-20 mi", "over 20 mi"), right = FALSE)
cs <- function(d, lab) d %>% summarise(n = n(), med = median(max_km), p90 = quantile(max_km, .9), beyond = mean(max_km > half_km), beyond_med = mean(med_km > half_km), rel = median(max_km / (chord_mi * 1.609344))) %>% mutate(cls = lab)
calt <- bind_rows(lapply(levels(cal$cls), function(l) cs(cal[cal$cls == l, ], l)), cs(cal, "all"))
cal_tab <- calt %>% transmute(`Chord length` = cls, Tornadoes = nfmt(n), `Maximum offset, median (km)` = fmt(med), `Maximum offset, 90th percentile (km)` = fmt(p90), `Maximum offset beyond the modeled half-width` = pct(beyond), `Typical (median) offset beyond the half-width` = pct(beyond_med))
rel_med <- calt$rel[calt$cls == "all"]; sp_cor <- sapply(levels(cal$cls), function(l) { d <- cal[cal$cls == l, ]; cor(d$s_km, d$max_km, method = "spearman") })
# ---- area ratio ---------------------------------------------------------------------------------------------------------------------------------------------
u <- sm[sm$status == "included" & sm$swath_km2 > 0, ]; u$ratio <- tornado_tracks$tornado_area_m2[match(u$tornado_id, tornado_tracks$tornado_id)] / 1e6 / u$swath_km2
u$cls <- tt$chord_class[match(u$tornado_id, tt$tornado_id)]
rsum <- function(d) d %>% summarise(n = n(), p10 = quantile(ratio, .1), p25 = quantile(ratio, .25), p50 = median(ratio), p75 = quantile(ratio, .75), p90 = quantile(ratio, .9), larger = mean(ratio > 1))
rt <- bind_rows(lapply(cc_ord, function(l) rsum(u[u$cls == l, ]) %>% mutate(cls = l)), rsum(u) %>% mutate(cls = "all")) %>% filter(n > 0) %>%
  transmute(`Chord length` = cls, Tornadoes = nfmt(n), `10th pct` = fmt(p10), `25th pct` = fmt(p25), Median = fmt(p50), `75th pct` = fmt(p75), `90th pct` = fmt(p90), `Modeled larger than surveyed` = pct(larger))
ratio_med <- median(u$ratio); ratio_p <- quantile(u$ratio, c(.1, .9)); joplin <- tornado_tracks[tornado_tracks$tornado_id == "2011_1105221634-01", ]; joplin_status <- sm$status[sm$tornado_id == "2011_1105221634-01"]
# ---- case studies (11c) -------------------------------------------------------------------------------------------------------------------------------------
cases <- readRDS(qa_out("dat_cases.rds")); case_names <- c(Moore = "Moore, OK 2013", Mayfield = "Mayfield, KY 2021", `Tuscaloosa-Birmingham` = "Tuscaloosa-Birmingham, AL 2011", Rainsville = "Rainsville, AL 2011")
cs_t <- cases %>% filter(case %in% names(case_names)) %>% transmute(Tornado = case_names[case], `Median / maximum distance from the surveyed centerline to the modeled line` = paste0(fmt(median_km), " / ", fmt(max_km), " km"),
  `Surveyed centerline farther than the modeled half-width` = paste0(round(pct_beyond_half_width), "%"), `Modeled polygon vs surveyed swath` = ifelse(is.na(swath_km2), paste0(fmt(modeled_km2, 1), " km2 vs no usable survey swath"), paste0(fmt(modeled_km2, 1), " vs ", fmt(swath_km2, 1), " km2 (", fmt(modeled_km2 / swath_km2, 1), " times)")),
  `Surveyed swath inside the modeled polygon` = ifelse(is.na(pct_swath_in_modeled), "n/a", paste0(fmt(pct_swath_in_modeled, 1), "%")))
cs_ratio <- range((cases$modeled_km2 / cases$swath_km2)[cases$case %in% names(case_names)], na.rm = TRUE)
case_ids <- c("2013_1305201356-01", "2021_2112102054-01", "2011_1104271543-01"); case_status <- sm$status[match(case_ids, sm$tornado_id)]
# ---- comparison tables from 45 ----------------------------------------------------------------------------------------------------------------------------
cmp <- readRDS(qa_out("survey_comparison.rds")); t1 <- cmp$t1; t2 <- cmp$t2; n44 <- readRDS(qa_out("survey_layer_numbers.rds"))
heading <- "## Path accuracy (straight line, one width)"
width_txt <- paste0("**What SPC's width means.** NWS instructions for Storm Data define the path width entered for a tornado as the maximum width.
NWSI 10-1605 ([current text, 26 July 2021](https://www.weather.gov/media/directives/010_pdfs/pd01016005curr.pdf)), section 47.7
\"Determining Path Length and Width\": \"Path length (in miles and tenths of miles) and maximum path width (in yards) will be indicated for all
tornadoes, including each member of families of tornadoes, or for all segments of multi-segmented tornadoes.\" The archived text of
6 January 2003 ([archived appendix](https://www.weather.gov/media/directives/010_pdfs_archived/pd01016005a_incomplete.pdf)), section 31
\"Tornado (C)\": \"Path width in the entry header is the maximum width over the entire path, or of each segment in a multi-segment tornado.\"
SPC compiles its database from Storm Data. SPC's current description
([SPC_severe_database_description.pdf](https://www.spc.noaa.gov/wcm/data/SPC_severe_database_description.pdf)) gives only \"Width in yards\", and an
older SPC format document ([torforma.doc](https://www.spc.noaa.gov/wcm/torforma.doc)) describes a mean width (\"Mean tornado path width ... The mean
width along the entire track is reported\"). This package treats `wid` as the maximum width. Two checks agree with that. For the ", nfmt(nrow(u)),
" tornadoes with a usable swath, the modeled path area, built from `wid`, is a median of ", fmt(ratio_med, 2), " times the surveyed swath area (10th to 90th percentile ", fmt(ratio_p[1], 2), " to ", fmt(ratio_p[2], 2),
"), which is consistent with a maximum width held along the whole path where the real width varies. For Joplin, SPC gives ", nfmt(joplin$wid_yd), " yards (", fmt(joplin$wid_yd / 1760, 2), " mile) and the NWS Service Assessment says the path was up to 1 mile wide. These checks do not show which width SPC recorded for every tornado.")
body <- paste0(heading, "

SPC records only a start point, an end point and one width for each tornado, so the package draws every tornado as a straight line between the two
points, buffered by half the width. Real tornado paths curve and their width varies along the track. Point tracks (no usable end point) are discs, and their
direction is unknown.

", width_txt, "

**Modeled versus surveyed paths.** The National Weather Service's [Damage Assessment Toolkit](https://apps.dat.noaa.gov/StormDamage/DamageViewer/) (DAT)
holds surveyed centerlines and damage swath polygons. The DAT describes its own data as preliminary. Four case studies of long, strong tornadoes that have a survey (they are among the longest and strongest, so their offsets are larger than typical; see the calibration below for all paired tornadoes):

", md_table(cs_t), "

The modeled polygons are ", fmt(cs_ratio[1], 1), " to ", fmt(cs_ratio[2], 1), " times larger than the surveyed swaths in the cases with a usable swath (the width, treated as the maximum, is held along the whole path). For Joplin (2011) the survey layer has status `", joplin_status, "` and no survey GIS was found. The NWS [Service
Assessment](https://www.weather.gov/media/publications/assessments/Joplin_tornado.pdf) gives a path 22.1 miles long and up to 1 mile wide, with the EF4-EF5 portion about 6 miles long and generally one-half to three-quarters of a mile wide; SPC has a length of ", fmt(joplin$len_mi, 2), " miles and a width of ", nfmt(joplin$wid_yd), " yards.

**Calibration across the paired tornadoes with a usable swath (line tracks).** The largest distance between the surveyed centerline and the modeled straight line, by straight-line (chord) length:

", md_table(cal_tab), "

The maximum offset is about ", pct(rel_med, 0), " of the chord length (median). An offset estimate based on the difference between `len` and the straight-line distance was tested against these surveys and was a weak predictor (rank correlation ", fmt(min(sp_cor), 2), " to ", fmt(max(sp_cor), 2), " by chord class), so it is not used.

**Modeled area against surveyed area.** For the ", nfmt(nrow(u)), " tornadoes with a usable swath, the modeled path polygon area divided by the surveyed swath area:

", md_table(rt), "

**Coverage.** The survey layer has a usable swath for ", nfmt(sum(tt$usable)), " of the ", nfmt(nrow(tt)), " SPC tornadoes since 2007 (", pct(mean(tt$usable)), "), and a paired survey line for ", nfmt(sum(tt$paired)), " (", pct(mean(tt$paired)), "). Tornadoes with a usable swath are skewed toward stronger, longer and more recent ones: the median chord is ", fmt(chord_use, 1), " miles against ", fmt(chord_all, 1), " miles for all line tracks since 2007, and ", pct(long_use), " are over 20 miles against ", pct(long_all), ". By rating, year and chord length:

", md_table(cov_r), "

", md_table(cov_y), "

", md_table(cov_c), "

The DAT has almost no surveys before 2011, so nothing here tests the 1996-2006 tracks.

", paste(readLines("data-raw/survey/pairing_issues.md"), collapse = "\n"), "

", paste(readLines("data-raw/survey/status_definitions.md"), collapse = "\n"), "

", paste(readLines("data-raw/survey/settings_issues.md"), collapse = "\n"), "

", paste(readLines("data-raw/survey/comparison_tables.md"), collapse = "\n"), "

**What this means.** The straight-line path shifts and widens the modeled swath. Of the ZCTAs exposed in either layer, ", t1$Agreement, " are exposed in both, and ", t1$`Tornadoes with identical ZCTAs`, " of the tornadoes have the same list of ZCTAs in both. The size of the shares differs more: for the pairs in both layers, the SPC area share is a median of ", t2$`Median of SPC value divided by survey value`[1], " times the survey area share (10th to 90th percentile ", t2$`10th to 90th percentile of that ratio`[1], ") and the SPC population share a median of ", t2$`Median of SPC value divided by survey value`[2], " times the survey population share (", t2$`10th to 90th percentile of that ratio`[2], "). Population shares follow where residents live. Distance-based exposure (`centroid_dist_km`) is a way to allow for this uncertainty; the offsets between modeled and surveyed paths are given above by tornado length, and a radius smaller than them cannot separate exposure from path-location error. If the error in a tornado's position is unrelated to the outcome being studied, it generally pulls estimated associations toward zero (non-differential misclassification of exposure); this was not tested with these data.

Notes on the analysis (`data-raw/qa/11c`, `44`, `45`, `46`): DAT swath polygons are linked to the surveyed centerline spatially, because the polygon layer has no usable link field. Polygons that cross the centerline on the same date can include straight-line wind swaths, multi-tornado polygons and zones of neighboring tornadoes, which would inflate the surveyed side, so the swath filter keeps only rated EF0-EF5 polygons with at least 90% of their area within a distance of the SPC path width plus 500 m of the centerline, and requires the swath to lie within 200 m of at least half of the centerline. The survey build was rerun against the live service on ", format(n44$counts$fetch_date), ".
")
pa_block <- paste0("<!-- path-accuracy:start -->\n", body, "<!-- path-accuracy:end -->\n")
when <- paste0("<!-- when-to-use:start -->
## When to use SPC and when to use the survey data

*`get_survey_data()` returns the same exposure definitions for the tornadoes in the survey layer (credit, preliminary status and terms are in its help page).*

* Use `get_data()` (SPC) as the main exposure. It covers every tornado from 1996 on one consistent definition, and it is the right choice for trends over time and for tornadoes with no survey.
* Use `get_survey_data()` as a sensitivity analysis, not a replacement. The two sources agree on which ZCTAs a path touches (", t1$Agreement, " of the ZCTAs exposed in either layer are exposed in both) and differ more in how large the shares are (the SPC area share is a median of ", t2$`Median of SPC value divided by survey value`[1], " times the survey area share, 10th to 90th percentile ", t2$`10th to 90th percentile of that ratio`[1], "), so an exposure defined by an area or population share is where the two layers differ most.
* Do not compare survey-based and SPC-based results across years without care. The share of SPC tornadoes with a usable swath rises from ", pct(early, 2), " in 2007-2010 to ", pct(late_rng[1], 0), " to ", pct(late_rng[2], 0), " in each year of 2020-2025, so a survey-only trend would mostly reflect coverage.
* A tornado with no survey line, or whose closest survey line has another tornado closer to it, is not in the layer (status `no_pair`: ", nfmt(sum(sm$status == "no_pair")), " of ", nfmt(nrow(sm)), " SPC tornadoes since 2007); the layer pairs each tornado with its closest survey line without a cut-off (see Limitation above).
* Suggested sensitivity design: restrict to tornadoes that have a usable survey swath, compute exposure both ways, and compare the estimates paired.
<!-- when-to-use:end -->
")
repl <- function(file, block, tag, fallback_start, fallback_end = NULL) {
  s <- paste(readLines(file, warn = FALSE), collapse = "\n"); s <- paste0(s, "\n"); st <- paste0("<!-- ", tag, ":start -->"); en <- paste0("<!-- ", tag, ":end -->")
  if (grepl(st, s, fixed = TRUE)) { a <- regexpr(st, s, fixed = TRUE); b <- regexpr(en, s, fixed = TRUE) + nchar(en); s <- paste0(substr(s, 1, a - 1), sub("\n$", "", block), substr(s, b, nchar(s)))
  } else { a <- regexpr(fallback_start, s, fixed = TRUE); if (a < 0) { s <- paste0(s, "\n", block) } else { b <- if (is.null(fallback_end)) nchar(s) + 1 else regexpr(fallback_end, s, fixed = TRUE); s <- paste0(substr(s, 1, a - 1), block, "\n", substr(s, b, nchar(s))) } }
  writeLines(sub("\n+$", "", s), file) }
repl("data-raw/known_issues.md", pa_block, "path-accuracy", heading, "## Point tracks"); repl("data-raw/known_issues.md", when, "when-to-use", "<!-- distance:start -->", "<!-- distance:start -->")
saveRDS(list(coverage = list(r = cov_r, y = cov_y, c = cov_c), calibration = cal, area_ratio = u, usable = sum(tt$usable), paired = sum(tt$paired)), qa_out("survey_path_accuracy.rds"))
cat("wrote data-raw/known_issues.md\n")
