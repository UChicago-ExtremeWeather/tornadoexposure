# Run from the package root after every data refresh, before the checks:  Rscript data-raw/qa/check_documented_claims.R
# Checks that the numbers in the documents agree with the data, and lists the numbers that no script produces.
#   (1) help pages: the package is documented again in a temporary copy (roxygen evaluates the numbers in the help text
#       from the data) and every help page is compared with the stored one;
#   (2) README: README.md is rebuilt in the temporary copy (needs an internet connection for the maps) and compared;
#   (3) data-raw/known_issues.md, the pairing text and the survey help text: every number written by hand that can be
#       recomputed from the data is recomputed and compared with the text;
#   (4) the numbers that nothing recomputes (written by hand in the documents, outside the blocks that the QA scripts write)
#       are listed in data-raw/qa/out/numbers_without_a_script.csv.
# Stops with a table of the differences if any of (1) to (3) differ.
suppressMessages({library(sf); library(dplyr)})
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
tt <- st_drop_geometry(tornado_tracks); d <- tornado_exposure; sm <- survey_matches; se <- survey_exposure
yr <- as.integer(substr(tt$tornado_id, 1, 4)); isna <- is.na(tt$property_loss_tornado_total); noz <- !tt$tornado_id %in% d$tornado_id
fails <- list(); n_ok <- 0L

# ---- (1) and (2): documents rebuilt in a temporary copy -----------------------------------------------
tmp <- file.path(tempdir(), "pkgcopy"); dir.create(tmp)
status <- system2("rsync", c("-a", "--exclude=.git", "--exclude=data-raw/qa/cache", "--exclude=data-raw/qa/out", "--exclude=.Rproj.user", "./", paste0(tmp, "/")))
stopifnot(status == 0)
old <- setwd(tmp)
suppressMessages(roxygen2::roxygenise(".", roclets = c("rd", "namespace")))
setwd(old)
man_new <- list.files(file.path(tmp, "man"), full.names = FALSE); man_old <- list.files("man", full.names = FALSE)
diff_man <- unique(c(setdiff(man_new, man_old), setdiff(man_old, man_new),
                     intersect(man_new, man_old)[vapply(intersect(man_new, man_old), function(f) !identical(readLines(file.path(tmp, "man", f)), readLines(file.path("man", f))), TRUE)]))
cat("help pages: ", length(man_old), " compared, ", length(diff_man), " differ", if (length(diff_man)) paste0(" (", paste(diff_man, collapse = ", "), ")"), "\n", sep = "")
if (length(diff_man)) fails$man <- data.frame(document = paste0("man/", diff_man), check = "help page differs from the data (run devtools::document())")
n_ok <- n_ok + length(man_old) - length(diff_man)
old <- setwd(tmp); r <- system2("Rscript", "data-raw/readme/build_readme.R", stdout = FALSE, stderr = FALSE); setwd(old)
if (!file.exists(file.path(tmp, "README.md")) || r != 0) stop("README.md could not be rebuilt (needs an internet connection for the maps)")
rd_new <- readLines(file.path(tmp, "README.md")); rd_old <- readLines("README.md")
rd_diff <- !identical(rd_new, rd_old)
cat("README.md: ", if (rd_diff) "differs from a fresh build" else "identical to a fresh build", "\n", sep = "")
if (rd_diff) { k <- which(rd_new[seq_len(min(length(rd_new), length(rd_old)))] != rd_old[seq_len(min(length(rd_new), length(rd_old)))])[1]
  fails$readme <- data.frame(document = "README.md", check = paste0("differs from a fresh build (first difference at line ", k, ": '", rd_old[k], "' versus '", rd_new[k], "')")) } else n_ok <- n_ok + 1L

# ---- (3) numbers written by hand, recomputed ---------------------------------------------------------------
NUM <- "([0-9][0-9,]*\\.?[0-9]*)"
read_flat <- function(f, strip = FALSE) { l <- readLines(f, warn = FALSE); if (strip) l <- sub("^#'?\\s?", "", l); st <- cumsum(c(1, nchar(l) + 1))[seq_along(l)]; list(flat = paste(l, collapse = " "), starts = st, lines = l) }
docs <- list(ki = read_flat("data-raw/known_issues.md"), ph = read_flat("data-raw/survey/pairing_help.md"), dist = read_flat("R/distance.R"), ud = read_flat("data-raw/update_data.R", strip = TRUE), pf = read_flat("data-raw/pipeline_functions.R"), dd = read_flat("R/data.R", strip = TRUE))
claims <- data.frame(doc = character(), id = character(), line = integer(), text = character(), expected = character(), found = character(), ok = logical())
covered <- list()   # doc -> data frame (line, value)
claim <- function(doc, id, pattern, expected, digits = NULL) {
  D <- docs[[doc]]; esc <- function(x) gsub("([.()\\[\\]?*+^$|{}\\\\])", "\\\\\\1", x, perl = TRUE)
  p <- paste(vapply(strsplit(pattern, " ", fixed = TRUE)[[1]], function(t) paste(esc(strsplit(paste0(t, "\001"), "NUM", fixed = TRUE)[[1]]), collapse = NUM), ""), collapse = "\\s+")
  p <- gsub("\001", "", p, fixed = TRUE)
  m <- regexpr(p, D$flat, perl = TRUE)
  if (m < 0) { claims[nrow(claims) + 1, ] <<- list(doc, id, NA_integer_, pattern, paste(expected, collapse = " | "), "text not found", FALSE); return(invisible()) }
  s <- attr(m, "capture.start"); l <- attr(m, "capture.length"); got <- substring(D$flat, s, s + l - 1)
  gv <- as.numeric(gsub(",", "", got)); dg <- ifelse(grepl("\\.", got), nchar(sub("^[^.]*\\.", "", got)), 0)
  exp_r <- round(expected, dg); ok <- length(gv) == length(expected) && all(abs(gv - exp_r) < 1e-9)
  line <- findInterval(m, D$starts)
  claims[nrow(claims) + 1, ] <<- list(doc, id, line, pattern, paste(exp_r, collapse = " | "), paste(gv, collapse = " | "), ok)
  last <- findInterval(m + attr(m, "match.length"), D$starts)
  covered[[doc]] <<- rbind(covered[[doc]], data.frame(line = rep(line:last, each = length(gv)), value = rep(gv, times = last - line + 1)))
  invisible()
}
pct <- function(x) 100 * x
el <- yr <= 2006; ln <- tt$track_type == "line"; pt <- !ln
claim("ki", "loss NA, all tornadoes", "NUM of NUM tornadoes (NUM%) become", c(sum(isna), nrow(tt), pct(mean(isna))))
claim("ki", "loss NA by era", "NUM of NUM in 1996-2006 (NUM%) and NUM of NUM from 2007 (NUM%)", c(sum(isna[el]), sum(el), pct(mean(isna[el])), sum(isna[!el]), sum(!el), pct(mean(isna[!el]))))
tr_rows <- tapply(is.na(d$property_loss_tornado_total), d$tornado_id, function(x) x[1])
claim("ki", "loss NA, exposure rows", "that is NUM of NUM rows (NUM%; NUM of the NUM tornadoes with rows)", c(sum(is.na(d$property_loss_tornado_total)), nrow(d), pct(mean(is.na(d$property_loss_tornado_total))), sum(tr_rows), length(tr_rows)))
claim("ki", "loss NA, survey rows", "`survey_exposure` NUM of NUM rows (NUM of NUM tornadoes)", c(sum(is.na(se$property_loss_tornado_total)), nrow(se), length(unique(se$tornado_id[is.na(se$property_loss_tornado_total)])), length(unique(se$tornado_id))))
m07 <- yr >= 2007
claim("ki", "EF4 and EF5 without loss", "Since 2007, NUM of NUM EF4 and EF5 tornadoes have no loss", c(sum(isna & !is.na(tt$magnitude) & tt$magnitude >= 4 & m07), sum(!is.na(tt$magnitude) & tt$magnitude >= 4 & m07)))
claim("ki", "deadly tornadoes without loss", "and NUM of NUM tornadoes with at least 10 deaths", c(sum(isna & tt$total_fatality >= 10 & m07), sum(tt$total_fatality >= 10 & m07)))
may <- tt[tt$tornado_id == "2021_2112102054-01", ]
claim("ki", "Mayfield", "(NUM deaths, NUM injuries) has loss NUM.", c(may$total_fatality, may$total_injury, may$property_loss_tornado_total))
l_all <- sum(tt$property_loss_tornado_total, na.rm = TRUE)
claim("ki", "loss of tornadoes without a ZCTA", "Loss of the NUM tornadoes that intersect no ZCTA is not allocated: NUM dollars (NUM tornadoes with loss above 0), NUM% of all loss", c(sum(noz), sum(tt$property_loss_tornado_total[noz], na.rm = TRUE), sum(noz & !is.na(tt$property_loss_tornado_total) & tt$property_loss_tornado_total > 0), pct(sum(tt$property_loss_tornado_total[noz], na.rm = TRUE) / l_all)))
claim("ki", "point tracks", "NUM of NUM tornadoes (NUM%) have no usable end point", c(sum(pt), nrow(tt), pct(mean(pt))))
claim("ki", "point tracks by era and rating", "NUM% of 1996-2006 tornadoes and NUM% from 2007, NUM% of EF0 and NUM% of EF1 and above", c(pct(mean(pt[el])), pct(mean(pt[!el])), pct(mean(pt[!is.na(tt$magnitude) & tt$magnitude == 0])), pct(mean(pt[!is.na(tt$magnitude) & tt$magnitude >= 1]))))
pe <- tt$track_type == "point_equal_area"
claim("ki", "point tracks with a length of at least 1 mile", "NUM of the NUM early `point_equal_area` tracks have a reported length of at least 1 mile, and NUM of the NUM from 2007", c(sum(pe & el & tt$len_mi >= 1), sum(pe & el), sum(pe & !el & tt$len_mi >= 1), sum(pe & !el)))
claim("ki", "len_ratio above 1.5", "is above 1.5 for NUM% of 1996-2006 line tracks and NUM% from 2007", c(pct(mean(tt$len_ratio[ln & el] > 1.5, na.rm = TRUE)), pct(mean(tt$len_ratio[ln & !el] > 1.5, na.rm = TRUE))))
claim("ki", "len_ratio above 1.5, reference in the coordinates section", "(`len_ratio` is above 1.5 for NUM% of line tracks from 2007 against NUM% in 1996-2006", c(pct(mean(tt$len_ratio[ln & !el] > 1.5, na.rm = TRUE)), pct(mean(tt$len_ratio[ln & el] > 1.5, na.rm = TRUE))))
ga <- tt[tt$tornado_id == "2023_2301121527-01", ]
claim("ki", "the extreme len_ratio", "`len` NUM miles against a NUM mile chord (ratio NUM)", c(ga$len_mi, ga$len_ratio * ga$len_mi, ga$len_ratio))
rat <- function(x) ifelse(is.na(x), "unknown", ifelse(x == 0, "EF0", "EF1+"))
nz_by <- tapply(noz, rat(tt$magnitude), mean)
z47 <- readRDS("data-raw/qa/out/no_zcta_summary.rds")
claim("ki", "tornadoes without a ZCTA", "NUM of NUM tornadoes (NUM%) have a path polygon that overlaps no ZCTA", c(sum(noz), nrow(tt), 100 * mean(noz)), digits = 2)
claim("ki", "no-ZCTA categories", "**Over water** (NUM)", c(z47$cats[["over water"]]))
claim("ki", "no-ZCTA categories 2", "**Over land, no ZCTA nearby** (NUM)", c(z47$cats[["over land, no ZCTA nearby"]]))
claim("ki", "no-ZCTA categories 3", "**On land, mostly covered** (NUM)", c(z47$cats[["on land, mostly covered"]]))
claim("ki", "no-ZCTA by year", "(2000: NUM, 2010: NUM, 2020: NUM)", c(sum(noz & yr < 2010), sum(noz & yr >= 2010 & yr < 2020), sum(noz & yr >= 2020)))
claim("ki", "no-ZCTA sample text", "Of all NUM, NUM are point tracks, NUM lie within 100 m of a ZCTA and NUM within 500 m (median NUM m), NUM overlap a ZCTA of another boundary year", c(z47$mc$n, z47$mc$point, z47$mc$within_100m, z47$mc$within_500m, z47$mc$median_near_m, z47$mc$hit_other))
claim("ki", "ratings", "All ratings are kept: NUM EF0, NUM EF1-EF5 and NUM unknown", c(sum(tt$magnitude == 0, na.rm = TRUE), sum(tt$magnitude >= 1, na.rm = TRUE), sum(is.na(tt$magnitude))))
# survey pairing text (known_issues.md and the help text are generated from the same file; both are checked)
# survey layer: pairing text (known_issues.md and the help text are generated from the same file; both are checked) and the tables
n44 <- readRDS("data-raw/qa/out/survey_layer_numbers.rds"); w44 <- n44$window
len_km <- pmax(tt$len_mi[match(sm$tornado_id, tt$tornado_id)], 0.1) * 1.609344; pairedr <- sm$status != "no_pair"; far <- pairedr & sm$distance_km > len_km
for (doc in c("ki", "ph")) {
  claim(doc, paste("survey: lines merged", doc), "are merged first: NUM lines became NUM", c(n44$counts$lines_fetched, n44$counts$lines_distinct))
  claim(doc, paste("survey: date windows", doc), "NUM tornadoes are paired and NUM have a usable swath with 0 days, NUM and NUM with 1 day, and NUM and NUM with 2 days", c(w44$paired[1], w44$usable[1], w44$paired[2], w44$usable[2], w44$paired[3], w44$usable[3]))
  dw49 <- readRDS("data-raw/qa/out/date_window_check.rds")
  claim(doc, paste("survey: date explanation", doc), "For NUM of the NUM pairs (NUM%) the survey date equals the UTC date of SPC's time, and NUM pairs (NUM%) have a survey date one day later than SPC's; of those, NUM (NUM%) have an SPC time of 18:00 CST",
    c(dw49$cmp$pairs[2] + dw49$cmp$pairs[3], dw49$n_pairs, 100 * (dw49$cmp$pairs[2] + dw49$cmp$pairs[3]) / dw49$n_pairs, dw49$by_diff[["1"]], 100 * dw49$by_diff[["1"]] / dw49$n_pairs, dw49$late[1], 100 * dw49$late[1] / dw49$late[2]))
  claim(doc, paste("survey: time of day", doc), "equals SPC's time converted to UTC for NUM% of the pairs (within one hour for NUM%)", c(dw49$dt_tab$same_hour_of_day_as_survey, dw49$dt_tab$within_1h))
  claim(doc, paste("survey: earlier dates", doc), "and only NUM pairs have a survey date one day earlier", c(dw49$by_diff[["-1"]]))
  claim(doc, paste("survey: pairs", doc), "Of the NUM survey lines, NUM are paired (NUM%); of the NUM SPC tornadoes since 2007, NUM are paired (NUM%).", c(n44$counts$lines_distinct, sum(pairedr), 100 * sum(pairedr) / n44$counts$lines_distinct, nrow(sm), sum(pairedr), 100 * mean(pairedr)))
  claim(doc, paste("survey: limitation", doc), "NUM of the NUM pairs (NUM%) have a survey line farther away than the larger of the SPC tornado's reported length and 0.1 mile (the shortest length assumed in SPC's older format description), NUM of them with a usable swath", c(sum(far), sum(pairedr), 100 * sum(far) / sum(pairedr), sum(far & sm$status == "included")))
}
claim("ki", "survey: no_swath counts", "NUM (NUM with no polygon left, NUM with polygons near under half of the centerline)", c(sum(sm$status == "no_swath"), sum(sm$status == "no_swath" & sm$n_polygons_used == 0), sum(sm$status == "no_swath" & sm$n_polygons_used > 0)))
claim("ki", "survey: no_pair counts", "NUM (NUM with no survey line dated within 1 day)", c(sum(sm$status == "no_pair"), sum(sm$status == "no_pair" & sm$n_candidates_tornado == 0)))
claim("ki", "survey: coverage", "has a usable swath for NUM of the NUM SPC tornadoes since 2007 (NUM%), and a paired survey line for NUM (NUM%)", c(sum(sm$status == "included"), nrow(sm), 100 * mean(sm$status == "included"), sum(pairedr), 100 * mean(pairedr)))
# the two agreement tables, recomputed from the two layers
inc_all <- sm$tornado_id[sm$status == "included"]
J <- full_join(d[d$tornado_id %in% inc_all, c("tornado_id", "ZCTA", "area_prop_affected", "pop_prop_affected")], se[, c("tornado_id", "ZCTA", "area_prop_affected", "pop_prop_affected")], by = c("tornado_id", "ZCTA"), suffix = c("_m", "_s"))
J$in_m <- !is.na(J$area_prop_affected_m); J$in_s <- !is.na(J$area_prop_affected_s)
per <- J %>% group_by(tornado_id) %>% summarise(m = sum(in_m), s = sum(in_s), b = sum(in_m & in_s), same = all(in_m == in_s), .groups = "drop")
bo <- J[J$in_m & J$in_s, ]; pb <- bo[!is.na(bo$pop_prop_affected_m) & !is.na(bo$pop_prop_affected_s) & bo$pop_prop_affected_m > 0 & bo$pop_prop_affected_s > 0, ]
claim("ki", "agreement table 1", "| Overlap: any part of the ZCTA is inside the path (SPC) or the swath (survey) | NUM | NUM | NUM | NUM | NUM% | NUM% | NUM% | NUM% |",
      c(nrow(per), sum(per$m), sum(per$s), sum(per$b), 100 * sum(per$b) / sum(per$m), 100 * sum(per$b) / sum(per$s), 100 * sum(per$b) / (sum(per$m) + sum(per$s) - sum(per$b)), 100 * mean(per$same)))
claim("ki", "agreement table 2, area", "| Area share (ZCTA land area inside the path or swath) | NUM | NUM | NUM to NUM | NUM |", c(nrow(bo), median(bo$area_prop_affected_m / bo$area_prop_affected_s), quantile(bo$area_prop_affected_m / bo$area_prop_affected_s, .1, names = FALSE), quantile(bo$area_prop_affected_m / bo$area_prop_affected_s, .9, names = FALSE), cor(bo$area_prop_affected_m, bo$area_prop_affected_s, method = "spearman")))
claim("ki", "agreement table 2, population", "| Population share (ZCTA residents inside the path or swath) | NUM | NUM | NUM to NUM | NUM |", c(nrow(pb), median(pb$pop_prop_affected_m / pb$pop_prop_affected_s), quantile(pb$pop_prop_affected_m / pb$pop_prop_affected_s, .1, names = FALSE), quantile(pb$pop_prop_affected_m / pb$pop_prop_affected_s, .9, names = FALSE), cor(pb$pop_prop_affected_m, pb$pop_prop_affected_s, method = "spearman")))

# download sizes (decimal GB, from the manifest of the downloads)
pp <- read.csv("data-raw/provenance_population.csv"); gb <- function(re) sum(pp$bytes[grepl(re, pp$url)]) / 1e9
prov <- read.csv("data-raw/provenance_years.csv")
claim("ki", "SPC file size", "downloads the SPC file (NUM bytes)", prov$bytes[nrow(prov)])
claim("ki", "population download sizes", "(2020: NUM GB in NUM files; 2010: NUM GB; 2000: NUM GB) and the PL 94-171 files (2010: NUM GB; 2000: NUM GB), NUM GB in all",
      c(gb("TABBLOCK20/"), sum(grepl("TABBLOCK20/", pp$url)), gb("TABBLOCK/2010"), gb("TABBLOCK/2000"), gb("census_2010"), gb("census_2000"),
        gb("TABBLOCK20/|TABBLOCK/2010|TABBLOCK/2000|census_2010|census_2000")))

# coordinate rounding simulation (written by 02_coordinate_rounding_analysis.R)
if (file.exists("data-raw/qa/out/coordinate_rounding_summary.rds")) {
  et <- readRDS("data-raw/qa/out/coordinate_rounding_summary.rds"); nm <- names(et)
  g <- function(pattern) et[[grep(pattern, nm, fixed = TRUE)[1]]]
  claim("ki", "coordinate rounding simulation", "changes the set of ZCTAs for NUM% of 1996-2006 tornadoes per replicate (NUM% in at least one replicate) but NUM% from 2007 (NUM% in at least one).",
        c(g("tornadoes_changed_%/rep")[1], g("in_any_rep")[1], g("tornadoes_changed_%/rep")[2], g("in_any_rep")[2]))
  claim("ki", "coordinate rounding, area_thresh flips", "NUM of NUM exposed tornado-ZCTA pairs (NUM%) flip per replicate before 2007 and NUM of NUM (NUM%) from 2007",
        c(g("flips_at_0.01_per_rep")[1], g("base_pairs_ge0.01")[1], g("flip_%_of_base")[1], g("flips_at_0.01_per_rep")[2], g("base_pairs_ge0.01")[2], g("flip_%_of_base")[2]))
}

# ---- numbers from the source scripts (each script saves what the documents quote; rerun the script after a data change) ----
need <- function(n) { f <- sprintf("data-raw/qa/out/documented_%s.rds", n); if (!file.exists(f)) stop("Run data-raw/qa/", n, "_*.R first: ", f, " is missing", call. = FALSE); readRDS(f) }
fact <- function(id, ok, detail = "") claims[nrow(claims) + 1, ] <<- list("ki", id, NA_integer_, "", "TRUE", as.character(isTRUE(ok)), isTRUE(ok))
d05 <- need("05"); d06 <- need("06"); d07 <- need("07"); d08 <- need("08"); d09 <- need("09"); d39 <- need("39")
claim("ki", "NCEI Mayfield segments", "when its county segments are summed (NUM and NUM), with property damage blank for the EF4 segments; SPC's NUM is the damage NCEI lists for the first (Obion, TN) segment",
      c(d05$mayfield_deaths, d05$mayfield_injuries, d05$mayfield_first_segment_damage))
fact("NCEI Mayfield: the first segment is in Obion, Tennessee; the EF4 segments have no damage value", d05$mayfield_first_segment_cz == "OBION" && d05$mayfield_first_segment_state == "TENNESSEE" && d05$mayfield_ef4_damage_missing)
fact("NCEI Mayfield: the segments run from SPC's start to SPC's end", abs(d05$mayfield_last_end_lat - d05$spc_end_lat) < 0.001)
t2011 <- tt[tt$tornado_id == "2011_1104271719-01", ]
claim("ki", "NCEI 2011-04-27 EF5", "(EF5, NUM deaths) has NUM injuries and NUM loss in SPC and in NCEI (event NUM: NUM direct deaths, NUM injuries, NUM.NUMK damage)",
      c(t2011$total_fatality, t2011$total_injury, t2011$loss_raw, 301829, d05$e301829_deaths, d05$e301829_injuries, 0, 0))
claim("ki", "early points with a start and end in the same cell", "(NUM% of early tornadoes with reported length of at most NUM mi have start and end in the same NUM degree cell)", c(100 * d07$share_same_cell_le_0.5, 0.5, 0.01))
r12 <- readRDS("data-raw/qa/out/d9_result.rds")
claim("ki", "NCEI end coordinates of point tracks", "NUM of NUM sampled EF1+ point tracks have the same start and end in NCEI", c(sum(!r12$distinct_end), nrow(r12)))
claim("ki", "start points in another state", "NUM of NUM start points fall in a different state from the reported state (NUM before 2007), and NUM fall outside every state outline", c(d09$n_mismatch, d09$n_tornadoes, d09$n_mismatch_early, d09$n_outside))
claim("ki", "ZCTA codes across vintages", "land area changed by more than NUM% for NUM% of codes from 2000 to 2010 and NUM% from 2010 to 2020. NUM exposed 2000-vintage codes (NUM rows) do not exist in the 2010 file, NUM exposed 2010-vintage codes (NUM rows) do not exist in the 2020 file, and NUM exposed codes (NUM rows) are not in the 2020 file",
      c(10, d06$v2000$changed_gt10, d06$v2010$changed_gt10, d06$v2000$codes_missing, d06$v2000$rows_missing, d06$v2010$codes_missing, d06$v2010$rows_missing, d06$absent_2020_codes, d06$absent_2020_rows))
claim("ki", "SPC releases: ids", "(all NUM matched 2007+ tornadoes changed ids)", d39$om_changed_2007)
fact("SPC releases: every matched 2007+ tornado changed its id", d39$om_changed_2007 == d39$matched_2007)
claim("ki", "SPC releases: revisions", "NUM tornadoes matched; magnitude changed for NUM, injuries for NUM, fatalities for NUM, `len` for NUM and `wid` for NUM; loss changed for NUM (NUM of them by exactly a factor of one million",
      c(d39$matched, d39$mag, d39$inj, d39$fat, d39$len, d39$wid, d39$loss, d39$loss_changed_by_1e6))
fact("SPC releases: no 1996-2006 record changed", d39$early_any_change == 0 && d39$om_changed_1996_2006 == 0)
# loss units and the guard limits
nzl <- tt[tt$loss_raw > 0, ]; ym <- tapply(nzl$loss_raw, as.integer(substr(nzl$tornado_id, 1, 4)), median); yy <- as.integer(names(ym))
claim("ki", "loss units", "(yearly median at most NUM, maximum NUM) and whole dollars from 2007 (yearly median at least NUM)", c(max(ym[yy <= 2006]), max(nzl$loss_raw[as.integer(substr(nzl$tornado_id, 1, 4)) <= 2006]), min(ym[yy >= 2007])))
pfl <- readLines("data-raw/pipeline_functions.R"); pv <- function(n) as.numeric(sub(paste0("^\\s*", n, " <- ([0-9.e+]+).*"), "\\1", grep(paste0("^\\s*", n, " <- "), pfl, value = TRUE)[1]))
claim("ki", "loss guard limits", "has a median above NUM or a value above NUM, or if a year from 2007 has a median below NUM", c(pv("max_median_millions"), pv("max_value_millions"), pv("min_median_dollars")))
# download sizes in the header of the update script
b20 <- pp[grepl("TABBLOCK20/", pp$url), ]
claim("ud", "update header: SPC file size", "SPC file 1950-<year>_all_tornadoes.csv: NUM bytes for 1950-2025", prov$bytes[nrow(prov)])
claim("ud", "update header: block file sizes", "all 52 files are NUM GB (largest Texas NUM MB, smallest DC NUM MB, median NUM MB)", c(sum(b20$bytes) / 1e9, max(b20$bytes) / 1e6, min(b20$bytes) / 1e6, median(b20$bytes) / 1e6))
claim("ud", "update header: full rebuild sizes", "reads NUM GB of population files (2020 blocks NUM GB, 2010 blocks NUM GB, 2000 blocks NUM GB, 2010 PL files NUM GB, 2000 PL files NUM GB)",
      c(gb("TABBLOCK20/|TABBLOCK/2010|TABBLOCK/2000|census_2010|census_2000"), gb("TABBLOCK20/"), gb("TABBLOCK/2010"), gb("TABBLOCK/2000"), gb("census_2010"), gb("census_2000")))

claim("ki", "dependence: SPC file size", "(one URL, NUM MB)", prov$bytes[nrow(prov)] / 1e6)
claim("ki", "dependence: block files", "the NUM files for all states are NUM GB; the largest, Texas, is NUM MB and the smallest, DC, NUM MB", c(nrow(b20), sum(b20$bytes) / 1e9, max(b20$bytes) / 1e6, min(b20$bytes) / 1e6))
if (file.exists("data-raw/qa/out/d2_results.rds")) { R2 <- readRDS("data-raw/qa/out/d2_results.rds"); claim("ki", "coordinate rounding simulation design", "(NUM replicates, NUM tornadoes per era: sample sizes", c(length(R2$res) - 1, min(table(R2$S$era)))) }

decimals <- function(x) { x <- abs(x - trunc(x)); max(nchar(sub("^0\\.?", "", format(round(x, 8), scientific = FALSE, trim = TRUE)))) }
claim("dd", "centroid coordinates are rounded to 5 decimals", "rounded to NUM decimals (about NUM m).", c(max(decimals(zcta_centroids$lon), decimals(zcta_centroids$lat)), round(1e-5 * 111195)))

# width: ratio of the modeled path area to the surveyed swath area, and the Joplin comparison
inc <- sm[sm$status == "included", ]; rt <- tornado_tracks$tornado_area_m2[match(inc$tornado_id, tornado_tracks$tornado_id)] / (inc$swath_km2 * 1e6)
claim("ki", "width check: area ratio", "is a median of NUM times the surveyed swath area (10th to 90th percentile NUM to NUM)", c(median(rt), quantile(rt, .1, names = FALSE), quantile(rt, .9, names = FALSE)))
jop <- tt[tt$tornado_id == "2011_1105221634-01", ]
claim("ki", "width check: Joplin", "For Joplin, SPC gives NUM yards (NUM mile) and the NWS Service Assessment says the path was up to 1 mile wide", c(jop$wid_yd, jop$wid_yd / 1760))
claim("ki", "Joplin length and width", "has a length of NUM miles and a width of NUM yards.", c(jop$len_mi, jop$wid_yd))
# distance timings used by the slow-call message
dt <- readRDS("data-raw/qa/out/distance_tables.rds")$tab
tm <- regmatches(docs$dist$flat, regexpr("seconds = c\\([0-9, ]+\\)", docs$dist$flat)); tm <- as.numeric(strsplit(gsub("seconds = c\\(|\\)", "", tm), ",")[[1]])
claims[nrow(claims) + 1, ] <- list("dist", "slow-call message timings (R/distance.R)", NA_integer_, ".distance_timings", paste(round(dt$seconds), collapse = " | "), paste(tm, collapse = " | "), identical(as.numeric(round(dt$seconds)), tm))
print(claims[, c("doc", "id", "line", "expected", "found", "ok")], row.names = FALSE, right = FALSE)
# ---- (3b) constants, definitions and behaviors stated in the README and the help pages ---------------------------------------------------------------
suppressMessages(devtools::load_all(".", quiet = TRUE))
err <- function(expr) inherits(try(suppressWarnings(expr), silent = TRUE), "try-error")
cl <- lapply(st_geometry(tornado_tracks), function(x) { m <- unclass(x); if (is.matrix(m)) m else matrix(m, 1) })
co <- do.call(rbind, cl); yr_of <- rep(as.integer(substr(tornado_tracks$tornado_id, 1, 4)), vapply(cl, nrow, 1L))
mult <- function(x, step) mean(abs(x / step - round(x / step)) < 1e-6)
fact("README/help: coordinates before 2007 are rounded to 0.01 degrees (99% or more are multiples of 0.01)", mult(c(co[yr_of < 2007, 1], co[yr_of < 2007, 2]), 0.01) >= 0.99)
fact("README/help: coordinates from 2007 have 0.0001 degrees (99% or more are multiples of 0.0001)", mult(c(co[yr_of >= 2007, 1], co[yr_of >= 2007, 2]), 1e-4) >= 0.99)
km_deg <- 6371.0088 * pi / 180
fact("README/help: 0.01 degrees of latitude is about 1.1 km", round(0.01 * km_deg, 1) == 1.1)
fact("help: 0.005 degrees is about 0.55 km", round(0.005 * km_deg, 2) == 0.56 || round(0.005 * km_deg, 2) == 0.55)
fact("README/help: 0.0001 degrees of latitude is about 11 m", round(1e-4 * km_deg * 1000) == 11)
fact("help: 0.0002 degrees of latitude is about 20 m (22 m rounds to 20 at one significant digit)", signif(2e-4 * km_deg * 1000, 1) == 20)
fact("help: 5 decimals of a degree of latitude are about 1 m (1.1 m)", signif(1e-5 * km_deg * 1000, 1) == 1)
fact("help: 30 feet is 10 yards", 30 / 3 == 10)
fact("help: width_imputed rows have a width of 10 yards", all(tornado_tracks$wid_yd[tornado_tracks$width_imputed] == 10))
fact("help: magnitude is 0 to 5 or NA (tornado_tracks)", all(tornado_tracks$magnitude %in% c(0:5, NA)) && all(0:5 %in% tornado_tracks$magnitude))
fact("help: magnitude is 0 to 5 or NA (tornado_exposure, survey_exposure)", all(tornado_exposure$magnitude %in% c(0:5, NA)) && all(survey_exposure$magnitude %in% c(0:5, NA)))
fact("help: area_prop_affected is a proportion from 0 to 1", all(tornado_exposure$area_prop_affected >= 0 & tornado_exposure$area_prop_affected <= 1) && all(survey_exposure$area_prop_affected >= 0 & survey_exposure$area_prop_affected <= 1))
fact("help: pop_prop_affected is from 0 to 1, NA when zcta_pop is 0", all(tornado_exposure$pop_prop_affected >= 0 & tornado_exposure$pop_prop_affected <= 1, na.rm = TRUE) && all(is.na(tornado_exposure$pop_prop_affected[tornado_exposure$zcta_pop == 0])) && all(!is.na(tornado_exposure$pop_prop_affected[tornado_exposure$zcta_pop > 0])))
fact("help: pop_affected is 0 when zcta_pop is 0", all(tornado_exposure$pop_affected[tornado_exposure$zcta_pop == 0] == 0))
fact("README: pop_affected is fractional", any(tornado_exposure$pop_affected != round(tornado_exposure$pop_affected)))
as_sum <- tapply(tornado_exposure$area_share_of_tornado, tornado_exposure$tornado_id, sum)
fact("help: area_share_of_tornado sums to 1 over a tornado's rows (all tornadoes with rows)", all(abs(as_sum - 1) < 1e-6))
fact("README: property_loss_allocated is property_loss_tornado_total times area_share_of_tornado", { ok <- !is.na(tornado_exposure$property_loss_tornado_total); all(abs(tornado_exposure$property_loss_allocated[ok] - tornado_exposure$property_loss_tornado_total[ok] * tornado_exposure$area_share_of_tornado[ok]) < 1e-6 * pmax(1, tornado_exposure$property_loss_tornado_total[ok])) })
fact("README: total_injury and total_fatality are repeated on every ZCTA row of a tornado", all(tapply(tornado_exposure$total_injury, tornado_exposure$tornado_id, function(x) length(unique(x))) == 1) && all(tapply(tornado_exposure$total_fatality, tornado_exposure$tornado_id, function(x) length(unique(x))) == 1))
fact("help: track geometry is in EPSG:4326 (tornado_tracks, survey_tracks)", st_crs(tornado_tracks)$epsg == 4326 && st_crs(survey_tracks)$epsg == 4326)
fact("help: path polygons are built in EPSG:5070", st_crs(.area_crs)$epsg == 5070)
fact("help: path_polygon default CRS is EPSG:5070", identical(eval(formals(.path_polygon)$crs), .area_crs))
fact("help: survey_tracks has 2 variables, tornado_id and geometry", identical(names(survey_tracks), c("tornado_id", "geometry")))
fact("README: survey_matches has one row per SPC tornado since 2007", nrow(survey_matches) == sum(yr >= 2007) && !anyDuplicated(survey_matches$tornado_id) && all(survey_matches$tornado_id %in% tt$tornado_id[yr >= 2007]))
fact("help: survey direction_diff_deg is from 0 to 180", all(survey_matches$direction_diff_deg >= 0 & survey_matches$direction_diff_deg <= 180, na.rm = TRUE))
fact("help: survey swath_cover is from 0 to 1", all(survey_matches$swath_cover >= 0 & survey_matches$swath_cover <= 1 + 1e-9, na.rm = TRUE))
pf <- readLines("data-raw/survey/pairing_functions.R"); bs <- readLines("data-raw/survey/build_survey.R")
fact("help: 21 equally spaced points (n_samples in the pairing code)", any(grepl("^n_samples <- 21$", pf)))
fact("help: the swath lies within 200 m of the centerline and the candidate window is 1 day (defaults of swath_of)", { f <- readLines("data-raw/survey/pairing_functions.R"); any(grepl("cover_dist = 200", f, fixed = TRUE)) && any(grepl("window = 1", f, fixed = TRUE)) })
fact("help: swaths are simplified to 50 m (build script)", any(grepl("dTolerance = 50", bs, fixed = TRUE)))
fact("help: polygons are generalized to 0.0002 degrees (pairing code)", any(grepl("0.0002", pf, fixed = TRUE)))
fact("help: the usable swath needs at least half of the centerline (status rule in the build script)", any(grepl("0.5", bs, fixed = TRUE)))
# arguments and behaviors of the functions
fact("README/help: area_thresh, pop_thresh and centroid_dist_km of 0 are errors", err(get_data(geo_list = "648", year_range = 2011, area_thresh = 0)) && err(get_data(geo_list = "648", year_range = 2011, pop_thresh = 0)) && err(get_data(geo_list = "648", year_range = 2011, centroid_dist_km = 0)))
fact("README/help: a threshold above 1 or a negative distance is an error; 1 is allowed", err(get_data(geo_list = "648", year_range = 2011, area_thresh = 1.01)) && err(get_data(geo_list = "648", year_range = 2011, centroid_dist_km = -1)) && !err(get_data(geo_list = "648", year_range = 2011, area_thresh = 1)))
fact("README/help: only one of the three definitions can be used at a time", err(get_data(geo_list = "648", year_range = 2011, area_thresh = 0.1, pop_thresh = 0.1)))
fact("help: a numeric geo_list with fewer than five digits warns (02139 becomes 2139); five digits do not", as.numeric("02139") == 2139 && inherits(tryCatch(get_data(geo_list = 2139, year_range = 2011), warning = function(w) w), "warning") && !inherits(tryCatch(get_data(geo_list = 64804, year_range = 2011), warning = function(w) w), "warning"))
jop <- get_data(geo_list = "648", year_range = 2011, magnitude = 5)
fact("README: the Joplin tornado is EF5 of 22 May 2011 in ZCTAs starting with 648", all(jop$date == as.Date("2011-05-22")) && length(unique(jop$tornado_id)) == 1)
mo <- get_survey_data(geo_list = "731", year_range = 2013, magnitude = 5)
fact("README: the Moore example tornado is of 20 May 2013 (SPC and survey)", all(get_data(geo_list = "731", year_range = 2013, magnitude = 5)$date == as.Date("2013-05-20")) && length(unique(mo$tornado_id)) == 1)
fact("README: geo_list accepts prefixes of 1 to 5 digits", all(vapply(c("6", "64", "648", "6480", "64804"), function(g) nrow(get_data(geo_list = g, year_range = 2011, magnitude = 5)) > 0, NA)))
fact("README: area_thresh = 0.05 keeps only rows with area_prop_affected of at least 0.05", all(get_data(geo_list = "648", year_range = 2011, magnitude = 5, area_thresh = 0.05)$area_prop_affected >= 0.05))
fact("README: pop_thresh = 0.05 keeps only rows with pop_prop_affected of at least 0.05", all(get_data(geo_list = "648", year_range = 2011, magnitude = 5, pop_thresh = 0.05)$pop_prop_affected >= 0.05))
dj <- get_data(geo_list = "648", year_range = 2011, magnitude = 5, centroid_dist_km = 10)
fact("README: centroid_dist_km results have dist_km (at most 10), centroid_type and centroid_in_zcta, and include ZCTAs the path did not overlap", all(c("dist_km", "centroid_type", "centroid_in_zcta") %in% names(dj)) && all(dj$dist_km <= 10) && any(!dj$ZCTA %in% jop$ZCTA))
w <- get_data(geo_list = "73", year_range = 2019:2023)
fact("README: magnitude = 1:5 drops unknown ratings, c(1:5, NA) keeps them, 5 keeps only EF5, the default keeps all", { a <- get_data(geo_list = "73", year_range = 2019:2023, magnitude = 1:5); b <- get_data(geo_list = "73", year_range = 2019:2023, magnitude = c(1:5, NA)); anyNA(w$magnitude) && !anyNA(a$magnitude) && min(a$magnitude) == 1 && anyNA(b$magnitude) && nrow(b) == nrow(a) + sum(is.na(w$magnitude)) && nrow(e0 <- get_data(geo_list = "7", year_range = 2011:2013, magnitude = 5)) > 0 && all(e0$magnitude == 5) && nrow(w) == nrow(b) + sum(w$magnitude == 0, na.rm = TRUE) })
gd <- names(formals(get_data))
fact("README: map_exposure() and add_tracks() take the same arguments as get_data()", all(setdiff(gd, "geography") %in% names(formals(map_exposure))) && all(setdiff(gd, "geography") %in% names(formals(add_tracks))))
fact("README: add_tracks() also accepts geometry = \"survey\", \"polygon\" and \"track\"", identical(eval(formals(add_tracks)$geometry), c("track", "polygon", "survey")))
fact("README: map_exposure() features are tornado_id, magnitude, total_fatality and total_injury", identical(eval(formals(generate_feature)$feature), c("tornado_id", "magnitude", "total_fatality", "total_injury")))
zero <- zcta_centroids[zcta_centroids$centroid_type == "geometric" & zcta_centroids$vintage == 2020, ]
fact("README: ZCTAs with no residents have a geometric centroid (centroid_type), and the other ZCTAs a population centroid", all(zcta_centroids$centroid_type[zcta_centroids$zcta_pop == 0] == "geometric") && all(zcta_centroids$centroid_type[zcta_centroids$zcta_pop > 0] == "population"))
fact("README: a centroid_dist_km result containing a ZCTA with no residents gives a warning and uses its geometric center", { z0 <- zero$ZCTA[1]; r <- withCallingHandlers(get_data(geo_list = z0, year_range = 2020:2025, centroid_dist_km = 300), warning = function(w) { assign("wmsg", conditionMessage(w), envir = globalenv()); invokeRestart("muffleWarning") }); exists("wmsg") && grepl("no residents", wmsg) && all(r$centroid_type == "geometric") })
fact("README: SPC reports loss in millions of dollars before 2007 and in dollars from 2007 (loss_raw_unit)", all(tornado_tracks$loss_raw_unit[yr < 2007] == "millions") && all(tornado_tracks$loss_raw_unit[yr >= 2007] == "dollars"))

bad <- claims[!claims$ok, ]
n_ok <- n_ok + sum(claims$ok)
if (nrow(bad)) fails$claims <- data.frame(document = c(ki = "data-raw/known_issues.md", ph = "data-raw/survey/pairing_help.md", dist = "R/distance.R", ud = "data-raw/update_data.R", pf = "data-raw/pipeline_functions.R", dd = "R/data.R")[bad$doc], check = paste0(bad$id, ": expected ", bad$expected, ", found ", bad$found))

# ---- (4) numbers that nothing recomputes ---------------------------------------------------------------------
tokens <- function(lines, file, skip = rep(FALSE, length(lines)), cov = NULL) {
  out <- list()
  for (i in which(!skip)) {
    x <- lines[i]
    x <- gsub("`[^`]*`", " ", x); x <- gsub("\\]\\([^)]*\\)", "]", x); x <- gsub("<[^>]*>", " ", x); x <- gsub("https?://\\S+", " ", x)
    x <- gsub("[0-9]{4}_[0-9A-Za-z-]+", " ", x); x <- gsub("EF[0-9]", " ", x); x <- gsub("\\bF[0-9]\\b", " ", x)
    x <- gsub("\\b(19|20)[0-9]{2}(-(19|20)[0-9]{2})?\\b", " ", x)   # years and year ranges
    m <- gregexpr("(?<![A-Za-z0-9_.-])[0-9][0-9,]*(\\.[0-9]+)?%?", x, perl = TRUE)[[1]]
    if (m[1] > 0) { tk <- substring(x, m, m + attr(m, "match.length") - 1); tk <- tk[nchar(gsub("[^0-9]", "", tk)) > 0]
      v <- as.numeric(gsub("[,%]", "", tk)); keep <- rep(TRUE, length(tk))
      if (!is.null(cov)) keep <- !(paste(i, v) %in% paste(cov$line, cov$value))
      if (any(keep)) out[[length(out) + 1]] <- data.frame(file = file, line = i, number = tk[keep], context = substr(trimws(lines[i]), 1, 140)) }
  }
  do.call(rbind, out)
}
ki <- docs$ki$lines
gen <- rep(FALSE, length(ki)); for (tag in c("path-accuracy", "when-to-use", "distance", "moore-comparison", "population", "zcta-vintage-overlap", "zcta2000-gap", "special-cases", "fixed-settings", "unchecked")) {
  a <- grep(paste0("<!-- ", tag, ":start -->"), ki, fixed = TRUE); b <- grep(paste0("<!-- ", tag, ":end -->"), ki, fixed = TRUE); if (length(a) && length(b)) gen[a:b] <- TRUE }
rm_chunks <- function(l) { inchunk <- FALSE; out <- character(length(l)); for (i in seq_along(l)) { if (grepl("^```", l[i])) { inchunk <- !inchunk; out[i] <- ""; next }; out[i] <- if (inchunk) "" else l[i] }; gsub("`r [^`]*`", " ", out) }
rmd <- readLines("data-raw/readme/README.Rmd", warn = FALSE)
rox <- do.call(rbind, lapply(list.files("R", pattern = "\\.R$", full.names = TRUE), function(f) { l <- readLines(f, warn = FALSE); k <- grepl("^#'", l); if (!any(k)) return(NULL); x <- sub("^#' ?", "", l); x <- gsub("`r [^`]*`", " ", x); data.frame(file = f, line = seq_along(l)[k], text = x[k]) }))
u <- rbind(tokens(ki, "data-raw/known_issues.md", skip = gen, cov = covered$ki),
           tokens(rm_chunks(rmd), "data-raw/readme/README.Rmd"),
           do.call(rbind, lapply(split(rox, rox$file), function(r) { t <- tokens(r$text, unique(r$file)); if (!is.null(t)) t$line <- r$line[t$line]; t })))
dir.create("data-raw/qa/out", showWarnings = FALSE); write.csv(u, "data-raw/qa/out/numbers_without_a_script.csv", row.names = FALSE)
# classes of the numbers in the README and the help-page sources that no claim matches (rules on the full line; the constants of class "unit or rounding constant" and the example values are checked in section 3b)
src_line <- function(f, i) readLines(f, warn = FALSE)[i]
cls <- function(n, ln) {
  if (grepl("get_data\\(|get_survey_data\\(|map_exposure\\(|add_tracks\\(|geo_list|year_range|magnitude =|_thresh|centroid_dist_km|^# |example|only ZCTAs where|\"648\"|Joplin, Missouri|\"731\"|Moore, Oklahoma tornado|`\"648\"`", ln)) return("example value or argument (run when the README is built or the examples are checked)")
  if (grepl("EPSG|NAD83|PL 94|02139|2139", ln)) return("code or identifier")
  if (grepl("degrees|decimals|yards|feet|\\bkm\\b|0\\.55|about 1 m|about 11 m|Coordinate rounding|Coordinates for 1996", ln)) return("unit or rounding constant (section 3b of this script)")
  if (grepl("recorded 0|\\bis 0|\\bare 0|length of 0|length is 0|above 0|equal to 0|width is 0|\\(0 when|0 when|, 0\\b|or no value|does not mean|length 0|point_half_width", ln)) return("zero as a value or rule (section 3b of this script)")
  if (grepl("0 to 1|0 to 5|0 to 180|\\(0, 1\\]|from 0|to 1\\b|1 to 5|1 day|5 and 20|21 equally|Rating from 0|capped at 1|sums to 1|layer 1|[0-9] variables|from 1 are|far from 1|different denominator", ln)) return("range endpoint or rule (section 3b of this script)")
  if (grepl("percentile|10th|90th|above 1\\.5|overlap ratio|0\\.1 mile|within 200|200 m|50 m|spread evenly|Census boundary year|boundary years", ln)) return("percentile label, cut-off or definition")
  if (grepl("^ ?[0-9]\\)|^[0-9]+$", n) && grepl("claiming copyright|implies an endorsement|official government|Damage Lines", ln)) return("list numbering in quoted source text")
  "other"
}
uu <- u[u$file != "data-raw/known_issues.md", ]; uu$class <- mapply(function(f, i, n) cls(n, src_line(f, i)), uu$file, uu$line, uu$number)
write.csv(uu, "data-raw/qa/out/numbers_without_a_script_classified.csv", row.names = FALSE)
ktab <- table(sub("^R/.*", "R/*.R (help pages)", uu$file), uu$class)
nk <- sum(u$file == "data-raw/known_issues.md")
blk <- c("<!-- unchecked:start -->", "## Numbers that no script recomputes", "",
  paste0("`data-raw/qa/check_documented_claims.R` matches ", n_ok, " numbers or statements in the README, the help pages and this file against the data (section 3b covers the constants, ranges, definitions and examples stated in the README and the help pages, as checks of the data and the code). ",
    "The numbers it cannot match to a computed value are hand-written; they are listed in `data-raw/qa/out/numbers_without_a_script.csv`. In the README and the help-page sources they are all of these kinds:"), "",
  paste0("* ", names(sort(table(uu$class), decreasing = TRUE)), ": ", as.integer(sort(table(uu$class), decreasing = TRUE)), collapse = "\n"), "",
  paste0("In this file ", nk, " numbers outside the generated sections are not matched: cut-offs and their rationale, dates, quoted source text, counts from earlier runs of the QA scripts, and values read from external documents. They are not checked by a script."),
  "<!-- unchecked:end -->")
kl <- readLines("data-raw/known_issues.md"); a <- grep("<!-- unchecked:start -->", kl, fixed = TRUE); b <- grep("<!-- unchecked:end -->", kl, fixed = TRUE)
kl <- if (length(a) && length(b)) c(kl[seq_len(a - 1)], blk, kl[-seq_len(b)]) else append(kl, c(blk, ""), after = grep("^## Point tracks", kl)[1] - 1)
writeLines(kl, "data-raw/known_issues.md")
cat("\nNumbers written by hand that no script recomputes: ", nrow(u), " (", paste(names(table(u$file)), table(u$file), sep = ": ", collapse = "; "), ")\nlisted in data-raw/qa/out/numbers_without_a_script.csv\n", sep = "")
cat("Checks that agree:", n_ok, "\n")
if (length(fails)) { f <- do.call(rbind, fails); print(f, row.names = FALSE, right = FALSE); stop(nrow(f), " documented number(s) differ from the data", call. = FALSE) }
cat("All documented numbers that can be recomputed agree with the data.\n")
