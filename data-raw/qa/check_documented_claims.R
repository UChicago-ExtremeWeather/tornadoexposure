# Run from the package root after every data refresh, before the checks:  Rscript data-raw/qa/check_documented_claims.R
# Checks that the numbers in the documents agree with the data and the code, and lists the numbers that no script produces.
#   (1) help pages: the package is documented again in a temporary copy (roxygen evaluates the numbers in the help text from the data) and every help page is compared with the stored one;
#   (2) README: README.md is rebuilt in the temporary copy (needs an internet connection for the maps) and compared;
#   (3) the constants that the documents state (thresholds, limits, sizes) are compared with the code, and the statements about the data with the data (the generated blocks of data-raw/known_issues.md are written by the
#       QA scripts from the data, see data-raw/qa/README.md);
#   (4) the numbers that nothing recomputes (written by hand in known_issues.md outside the generated blocks) are counted and listed in data-raw/qa/out/numbers_without_a_script.csv, and the count is written into the
#       block "unchecked" of known_issues.md.
# Stops with a table of the differences if any of (1) to (3) differ.
suppressMessages({library(sf); library(dplyr)})
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
tt <- st_drop_geometry(tornado_tracks); d <- tornado_exposure
fails <- list(); n_ok <- 0L; fail <- function(document, check) fails[[length(fails) + 1L]] <<- data.frame(document = document, check = check)

# ---- (1) and (2): documents rebuilt in a temporary copy -----------------------------------------------
tmp <- file.path(tempdir(), "pkgcopy"); dir.create(tmp)
status <- system2("rsync", c("-a", "--exclude=.git", "--exclude=data-raw/qa/cache", "--exclude=data-raw/cache", "--exclude=data-raw/qa/out", "--exclude=data-raw/dat/fetch", "--exclude=.Rproj.user", "./", paste0(tmp, "/"))); stopifnot(status == 0)
old <- setwd(tmp); suppressMessages(roxygen2::roxygenise(".", roclets = c("rd", "namespace"))); setwd(old)
man_new <- list.files(file.path(tmp, "man")); man_old <- list.files("man")
diff_man <- unique(c(setdiff(man_new, man_old), setdiff(man_old, man_new), intersect(man_new, man_old)[vapply(intersect(man_new, man_old), function(f) !identical(readLines(file.path(tmp, "man", f)), readLines(file.path("man", f))), TRUE)]))
cat("help pages: ", length(man_old), " compared, ", length(diff_man), " differ", if (length(diff_man)) paste0(" (", paste(diff_man, collapse = ", "), ")"), "\n", sep = "")
for (f in diff_man) fail(paste0("man/", f), "help page differs from the data (run devtools::document())"); n_ok <- n_ok + length(man_old) - length(diff_man)
if (!identical(readLines(file.path(tmp, "NAMESPACE")), readLines("NAMESPACE"))) fail("NAMESPACE", "differs from the roxygen tags") else n_ok <- n_ok + 1L
old <- setwd(tmp); r <- system2("Rscript", "data-raw/readme/build_readme.R", stdout = FALSE, stderr = FALSE); setwd(old)
if (!file.exists(file.path(tmp, "README.md")) || r != 0) stop("README.md could not be rebuilt (needs an internet connection for the maps)")
rd_new <- readLines(file.path(tmp, "README.md")); rd_old <- readLines("README.md"); rd_diff <- !identical(rd_new, rd_old)
cat("README.md: ", if (rd_diff) "differs from a fresh build" else "identical to a fresh build", "\n", sep = "")
if (rd_diff) { k <- which(rd_new[seq_len(min(length(rd_new), length(rd_old)))] != rd_old[seq_len(min(length(rd_new), length(rd_old)))])[1]; fail("README.md", paste0("differs from a fresh build (first difference at line ", k, ": '", rd_old[k], "' versus '", rd_new[k], "')")) } else n_ok <- n_ok + 1L

# ---- (3) constants and statements about the data ---------------------------------------------------------------------
code <- function(f) paste(readLines(f, warn = FALSE), collapse = "\n")
has <- function(f, pattern, what) { ok <- grepl(pattern, code(f), perl = TRUE); cat(if (ok) "ok    " else "FAIL  ", what, "\n", sep = ""); if (ok) n_ok <<- n_ok + 1L else fail(f, paste("constant stated in the documents is not in the code:", what)) }
ki <- code("data-raw/known_issues.md"); rm_ <- code("README.md"); dd <- paste(code("R/data.R"), code("R/data_dat.R"), code("R/get_data.R"), code("R/map_exposure.R"))
has("data-raw/pipeline_functions.R", "first_year <- 1996", "the data start in 1996")
has("data-raw/pipeline_functions.R", "loss_break_year <- 2007", "the loss unit breaks in 2007")
has("data-raw/pipeline_functions.R", "(?s)max_median_millions <- 1\\b.*max_value_millions <- 10000\\b.*min_median_dollars <- 10000\\b", "loss guard limits 1, 10,000 and 10,000")
has("data-raw/pipeline_functions.R", "off > 1e-9", "exact-conversion tolerance 1e-9")
has("data-raw/dat/exposure_functions.R", "1 \\+ 1e-9", "block share tolerance 1e-9")
has("data-raw/dat/build_dat_exposure.R", "1 \\+ 1e-9", "unit share tolerance 1e-9")
has("data-raw/dat/exposure_functions.R", "line_share_in_polygon > 0", "the polygon rule: line_share_in_polygon above 0")
has("data-raw/dat/exposure_functions.R", "EF0|paste0\\(\"EF\", 0:5\\)", "footprint polygons are those rated EF0 to EF5")
has("data-raw/land_functions.R", "st_difference", "land-only shapes are the unit polygon minus the water polygons")
has("data-raw/pipeline_functions.R", "piece_m > 0", "an SPC line exposes a ZCTA when a positive length of the line lies in it")
has("data-raw/dat/pairing_functions.R", "n_samples <- 21", "21 sample points")
has("data-raw/dat/pairing_functions.R", "window = 1", "link window 1 day")
has("data-raw/dat/build_dat.R", "-1:1", "polygon-line window 1 day")
has("R/distance.R", "radius_km \\* 1000 \\* 1\\.05", "distance index factor 1.05")
has("R/distance.R", "\\.distance_crs <- list\\(conus = 5070, ak = 3338, hi = \"ESRI:102007\", pr = 32161\\)", "regional distance projections")
has("R/map_exposure.R", "nrow\\(dpt\\) > 2000L", "note above 2,000 damage points")
has("R/distance.R", "threshold = 20", "time note at 20 seconds")
has("data-raw/pipeline_functions.R", "latitude 15 to 72|xy\\[, 2\\] < 15 \\| xy\\[, 2\\] > 72 \\| xy\\[, 1\\] < -180 \\| xy\\[, 1\\] > -60", "update sanity limits for coordinates")
has("data-raw/pipeline_functions.R", "wid_yd > 10000", "update sanity limit for width 10,000")
has("data-raw/pipeline_functions.R", "len_mi > 400", "update sanity limit for length 400")
has("data-raw/pipeline_functions.R", "1e11", "update sanity limit for loss 1e11")
# distance timings of the code are the measured ones
tb <- readRDS("data-raw/qa/out/distance_tables.rds")$tab; dtxt <- code("R/distance.R"); secs <- as.numeric(strsplit(sub("seconds = c\\(([0-9, ]+)\\)", "\\1", regmatches(dtxt, regexpr("seconds = c\\([0-9, ]+\\)", dtxt))), ",\\s*")[[1]]); ok <- length(secs) == nrow(tb) && all(secs / tb$seconds > 0.5 & secs / tb$seconds < 2)   # a rough guide: within a factor of 2 of the latest measurement
cat(if (ok) "ok    " else "FAIL  ", ".distance_timings are within a factor of 2 of the times measured by 23_distance_tables.R\n", sep = ""); if (ok) n_ok <- n_ok + 1L else fail("R/distance.R", ".distance_timings differ from out/distance_tables.rds")
# map download sizes in the code and the help pages agree with the server headers (MB, rounded)
nm <- read.csv("data-raw/readme/numbers.csv", stringsAsFactors = FALSE); N <- function(x) nm$value[match(x, nm$name)]
ok <- all(round(c(N("map_zip_mb_2000"), N("map_zip_mb_2010"), N("map_zip_mb_2020"))) == c(680, 524, 528)); cat(if (ok) "ok    " else "FAIL  ", "boundary download sizes 680, 524 and 528 MB in the code agree with the server headers\n", sep = ""); if (ok) n_ok <- n_ok + 1L else fail("R/distance.R", "boundary download sizes differ from the server headers")
# statements about the data
chk <- function(what, ok) { cat(if (isTRUE(ok)) "ok    " else "FAIL  ", what, "\n", sep = ""); if (isTRUE(ok)) n_ok <<- n_ok + 1L else fail("documents", what) }
chk("tornado_exposure has no modeled_ column and tornado_tracks no modeled_path_area_m2 (documented: no polygon is built from SPC's width)", !any(grepl("^modeled_", names(d))) && !"modeled_path_area_m2" %in% names(tt))
chk("the St. Louis tornado is linked to two DAT lines (README)", sum(tornado_dat_link$tornado_id == "2025_2505161339-01") == 2)
chk("a point tornado has one SPC row unless its start lies on a ZCTA boundary (help page of tornado_exposure)", { n <- table(d$tornado_id[d$track_type == "point" & d$spc_exposed]); mean(n == 1) > 0.999 })
chk("line_share_of_tornado sums to 1 over the SPC rows of each tornado (help page of tornado_exposure)", all(abs(tapply(d$line_share_of_tornado[d$spc_exposed], d$tornado_id[d$spc_exposed], sum) - 1) < 1e-9))
chk("boundary_dist_km is 0 exactly where spc_exposed is TRUE (help page of tornado_exposure)", all(d$boundary_dist_km[d$spc_exposed] == 0) && all(d$boundary_dist_km[!d$spc_exposed] > 0))
chk("dat_area_share_ef0 to ef5 sum to dat_area_share (help page of tornado_exposure)", isTRUE(all.equal(unname(rowSums(d[d$dat_linked, paste0("dat_area_share_ef", 0:5)])), d$dat_area_share[d$dat_linked], tolerance = 1e-12)))
fm <- function(x) formatC(x, format = "d", big.mark = ","); do_ <- d[!d$spc_exposed & d$dat_exposed %in% TRUE, ]; fr <- function(km) c(sum(do_$boundary_dist_km > km), length(unique(do_$tornado_id[do_$boundary_dist_km > km])))
chk("the far DAT-only rows stated in the README and known_issues.md (rows and tornadoes beyond 5, 25 and 100 km, the farthest row, tornadoes within 5 km)", all(vapply(list(rm_, ki), function(x) grepl(paste0(fm(nrow(do_)), " "), x, fixed = TRUE) && grepl(paste0("for ", fm(length(unique(do_$tornado_id)) - fr(5)[2]), " "), tolower(x), fixed = TRUE) && grepl(paste0(fm(fr(5)[1]), " rows (", fm(fr(5)[2]), " tornadoes) beyond 5 km, ", fm(fr(25)[1]), " (", fm(fr(25)[2]), ") beyond 25 km and ", fm(fr(100)[1]), " (", fm(fr(100)[2]), ") beyond 100 km, the farthest ", sprintf("%.2f", max(do_$boundary_dist_km)), " km"), x, fixed = TRUE), TRUE)))
uy <- tapply(is.na(tt$magnitude), as.integer(format(tt$date, "%Y")), sum); uyr <- as.integer(names(uy)); un_ <- 100 * uy / table(as.integer(format(tt$date, "%Y")))
chk("unknown ratings: none in 1996 to 2006, some in 2007, none in 2008 to 2015, some in every year from 2016 to 2025 (README, known_issues.md and the help page state this pattern, and no document says 'only from 2007')", all(uy[uyr <= 2006] == 0) && uy[["2007"]] > 0 && all(uy[uyr %in% 2008:2015] == 0) && all(uy[uyr >= 2016] > 0) &&
    grepl(paste0("some in every year from 2016 to 2025: ", fm(min(uy[uyr >= 2016])), " to ", fm(max(uy[uyr >= 2016])), " a year"), rm_ , fixed = TRUE) && grepl(paste0("some in every year from 2016 to 2025: ", fm(min(uy[uyr >= 2016])), " to ", fm(max(uy[uyr >= 2016])), " a year"), ki, fixed = TRUE) && !grepl("only from 2007|appear only|grow after", paste(rm_, ki, dd)))
pt_ <- tt$track_type == "point"; e_all <- sprintf("%.1f%%", 100 * mean(tt$magnitude[pt_] %in% 0)); e_rated <- sprintf("%.1f%%", 100 * mean(tt$magnitude[pt_] == 0, na.rm = TRUE))
chk("the EF0 share of tornadoes with no usable end point is stated for all of them and for those with a rating (README, known_issues.md)", all(vapply(list(rm_, ki), function(x) grepl(paste0(e_all, " of them are EF0 (", e_rated, " of those with a rating)"), x, fixed = TRUE) || grepl(paste0(e_all, " of these tornadoes are EF0 (", e_rated, " of those with a rating)"), x, fixed = TRUE), TRUE)) && !grepl("84.2% of them are EF0 and", rm_, fixed = TRUE))
chk("all tornadoes with no SPC row have no row at all (README, known_issues.md)", { nr <- sum(!tt$tornado_id %in% d$tornado_id); nr == sum(!tt$tornado_id %in% d$tornado_id[d$spc_exposed]) && grepl(paste0("All ", fm(nr), " have no row at all"), rm_, fixed = TRUE) && grepl(paste0("All ", fm(nr), " have no row at all"), ki, fixed = TRUE) })
chk("the README has one citation sentence with the DOI link", length(grep("To cite the package", readLines("README.md"))) == 1L && grepl("To cite the package, use https://doi.org/10.5281/zenodo.23544841.", rm_, fixed = TRUE))
chk("dat_link_dist_km is documented in the help pages and the README variable table", grepl("dat_link_dist_km", dd, fixed = TRUE) && grepl("`dat_link_dist_km`", rm_, fixed = TRUE))
chk("dat_features documents all fields of the three layers", all(vapply(list(dat_points, dat_lines, dat_polygons), function(x) all(names(x) != ""), TRUE)))

if (length(fails)) { F <- do.call(rbind, fails); print(F, row.names = FALSE, right = FALSE); stop(nrow(F), " documented claim(s) do not agree with the data or the code.", call. = FALSE) }
cat("\n", n_ok, " checks agree, 0 differ.\n", sep = "")

# ---- (4) numbers that nothing recomputes ---------------------------------------------------------------------------
ki_l <- readLines("data-raw/known_issues.md", warn = FALSE); inblock <- logical(length(ki_l)); open <- NULL
for (i in seq_along(ki_l)) { m <- regmatches(ki_l[i], regexec("^<!-- ([a-z0-9-]+):(start|end) -->$", ki_l[i]))[[1]]; if (length(m)) { if (m[3] == "start") open <- m[2] else open <- NULL; inblock[i] <- TRUE } else inblock[i] <- !is.null(open) }
outside <- ki_l[!inblock]; nums <- unlist(regmatches(outside, gregexpr("[0-9][0-9,]*\\.?[0-9]*", outside)))
dir.create("data-raw/qa/out", showWarnings = FALSE); write.csv(data.frame(number = nums), "data-raw/qa/out/numbers_without_a_script.csv", row.names = FALSE)
blk <- c("<!-- unchecked:start -->", "## Numbers that no script recomputes", "",
  paste0("`data-raw/qa/check_documented_claims.R` matches ", n_ok, " numbers or statements in the help pages, the README and the code against the data (the generated blocks of this file are written by the QA scripts from the data). In this file ", length(nums), " numbers outside the generated blocks are not matched: quoted source text of external documents, dates and urls, and values read from external documents. They are listed in `data-raw/qa/out/numbers_without_a_script.csv` and are not checked by a script."), "<!-- unchecked:end -->")
a <- grep("<!-- unchecked:start -->", ki_l, fixed = TRUE); b <- grep("<!-- unchecked:end -->", ki_l, fixed = TRUE); writeLines(c(ki_l[seq_len(a - 1)], blk, ki_l[-seq_len(b)]), "data-raw/known_issues.md")
