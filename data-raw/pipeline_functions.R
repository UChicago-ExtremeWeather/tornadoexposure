# Functions that turn SPC tornado records into the package data. Shared by
#   data-raw/process_tracks.R  (full rebuild, for verification and deliberate full rebuilds)
#   data-raw/update_data.R     (incremental, append-only update with a new SPC release)
# so the two cannot disagree. Source from the package root.
suppressMessages({library(readr); library(dplyr); library(sf)})
source("R/constants.R")
options(tigris_use_cache = TRUE)

area_crs <- .area_crs
yd_to_m <- .yd_to_m
mi_to_m <- .mi_to_m
first_year <- 1996      # the package starts in 1996. SPC's file starts in 1950; 1996 is the start of the original package, inherited here, and no reason for it is documented
vint_of <- function(y) ifelse(y < 2010, 2000L, ifelse(y < 2020, 2010L, 2020L))
source("R/distance.R")  # .distance_region(), .distance_crs, .track_centroid_dist()

# ---- SPC file ---------------------------------------------------------------
spc_url <- function(latest_year) sprintf("https://www.spc.noaa.gov/wcm/data/1950-%s_all_tornadoes.csv", latest_year)

# downloads the file once so that it can be fingerprinted (provenance)
spc_download <- function(latest_year) {
  url <- spc_url(latest_year)
  f <- tempfile(fileext = ".csv")
  utils::download.file(url, f, mode = "wb", quiet = TRUE)
  list(file = f, url = url, md5 = unname(tools::md5sum(f)), bytes = file.size(f), access_date = Sys.Date())
}

# Uses an SPC file that was downloaded earlier (its md5 must be in data-raw/provenance_years.csv, which also gives the access date), so a rebuild
# does not depend on the file SPC serves today.
spc_stored <- function(file, latest_year, prov_dir = "data-raw") {
  md5 <- unname(tools::md5sum(file))
  prov <- utils::read.csv(file.path(prov_dir, "provenance_years.csv"), stringsAsFactors = FALSE)
  i <- which(prov$md5 == md5)
  if (!length(i)) stop("The md5 of ", file, " (", md5, ") is not in data-raw/provenance_years.csv.", call. = FALSE)
  list(file = file, url = spc_url(latest_year), md5 = md5, bytes = file.size(file), access_date = as.Date(prov$access_date[i[1]]))
}

# Reads the SPC file with every column as SPC gives it (the time of day stays text).
spc_read <- function(file) read_csv(file, show_col_types = FALSE, col_types = cols(time = col_character(), .default = col_guess()))

# ---- cleaning ---------------------------------------------------------------
# Keeps the whole-track records (sg == 1) of `years`, makes tornado_id, converts loss to dollars (stops if the
# conversion is not exact or the unit break moved) and classifies line and point tracks. No value is replaced.
spc_clean <- function(raw, years) {
  tornadoes <- raw %>%
    filter(yr >= first_year, yr %in% years) %>%
    # sg == 1 is the entire-track record. Other rows are state segments or
    # continuing county FIPS records (sg == 2 or -9) that repeat the same om.
    filter(sg == 1) %>%
    mutate(tornado_id = paste(yr, om, sep = "_"))

  # magnitude: keep EF0 to EF5; SPC codes unknown ratings as -9, which becomes NA.
  # Any other code would be unexpected, so stop.
  stopifnot("unexpected magnitude code(s) in SPC file" = all(tornadoes$mag %in% c(-9, 0:5)))
  tornadoes$magnitude <- ifelse(tornadoes$mag == -9, NA_integer_, as.integer(tornadoes$mag))
  message("Tornadoes after year >= 1996 and sg == 1: ", nrow(tornadoes),
          " (EF0: ", sum(tornadoes$magnitude == 0, na.rm = TRUE),
          ", EF1-EF5: ", sum(tornadoes$magnitude >= 1, na.rm = TRUE),
          ", unknown: ", sum(is.na(tornadoes$magnitude)), ")")

  # a few distinct tornadoes share the same yr and om in SPC (each has its own
  # sg == 1 row, coordinates and totals). Suffix them _1, _2 so tornado_id is unique.
  dup_id <- duplicated(tornadoes$tornado_id) | duplicated(tornadoes$tornado_id, fromLast = TRUE)
  if (any(dup_id)) message("Rows sharing a tornado_id with another sg == 1 row: ", sum(dup_id),
                           " (", paste(unique(tornadoes$tornado_id[dup_id]), collapse = ", "), ")")
  tornadoes$tornado_id[dup_id] <- paste0(
    tornadoes$tornado_id[dup_id], "_",
    ave(seq_len(sum(dup_id)), tornadoes$tornado_id[dup_id], FUN = seq_along))
  stopifnot(!anyDuplicated(tornadoes$tornado_id))

  # loss: NOAA documents SPC `loss` as millions of dollars from 1996. In the 2025 file the values are in millions
  # through 2006 and in whole dollars from 2007 (SPC re-coded 2007-2015 between its 2024 and 2025 releases). Guard
  # thresholds were chosen from the data: for 1996-2006 the yearly median of nonzero loss is at most 0.07 and the
  # maximum is 1,000; for 2007 onward the yearly median is at least 50,000. If SPC moves the break, stop rather than
  # mis-scale losses.
  loss_break_year <- 2007
  max_median_millions <- 1       # observed maximum yearly median: 0.07
  max_value_millions <- 10000    # observed maximum value: 1,000
  min_median_dollars <- 10000    # observed minimum yearly median: 50,000
  nz <- tornadoes[tornadoes$loss > 0, ]
  yr_med <- tapply(nz$loss, nz$yr, median)
  yr_max <- tapply(nz$loss, nz$yr, max)
  bad_m <- names(yr_med)[as.integer(names(yr_med)) < loss_break_year & (yr_med > max_median_millions | yr_max > max_value_millions)]
  bad_d <- names(yr_med)[as.integer(names(yr_med)) >= loss_break_year & yr_med < min_median_dollars]
  if (length(bad_m) + length(bad_d) > 0) {
    stop("The SPC loss unit break has moved. Expected millions of dollars before ",
         loss_break_year, " and whole dollars from ", loss_break_year,
         ". Years that look like dollars but are expected to be millions: ",
         paste(bad_m, collapse = ", "), ". Years that look like millions but ",
         "are expected to be dollars: ", paste(bad_d, collapse = ", "),
         ". Inspect the SPC file and update loss_break_year in data-raw/pipeline_functions.R.", call. = FALSE)
  }
  tornadoes$loss_raw <- tornadoes$loss
  tornadoes$loss_raw_unit <- ifelse(tornadoes$yr < loss_break_year, "millions", "dollars")
  # millions to dollars. Raw millions have at most three decimals, so the product is a whole number of dollars up to
  # floating-point error. Stop if any value is not.
  exact <- tornadoes$loss * 1e6
  tornadoes$loss_usd <- ifelse(tornadoes$yr < loss_break_year, round(exact), tornadoes$loss)
  off <- abs(tornadoes$loss_usd - ifelse(tornadoes$yr < loss_break_year, exact, tornadoes$loss))
  if (any(off > 1e-9 * pmax(1, abs(tornadoes$loss_usd)))) {
    stop("The loss conversion from millions to dollars is not exact for ", sum(off > 1e-9 * pmax(1, abs(tornadoes$loss_usd))),
         " records (largest difference ", max(off), " dollars). Inspect the SPC file.", call. = FALSE)
  }
  message("Loss unit guard passed (break at ", loss_break_year, "); nonzero loss: ",
          sum(tornadoes$loss > 0), " tornadoes, ", sum(tornadoes$loss == 0), " with loss 0; largest conversion difference ", signif(max(off), 3), " dollars")

  # no valid start location: stop (the package never drops a record)
  no_start <- is.na(tornadoes$slon) | is.na(tornadoes$slat) | tornadoes$slon == 0 | tornadoes$slat == 0
  if (any(no_start)) stop(sum(no_start), " whole-track records have no valid start location (", paste(utils::head(tornadoes$tornado_id[no_start], 5), collapse = ", "),
                          "). A record is never dropped without the maintainer's approval.", call. = FALSE)

  # A tornado with no usable end point (end coordinates missing, 0, or equal to the start) is a point at the start.
  # The raw coordinates stay in slat, slon, elat and elon.
  bad_end <- is.na(tornadoes$elon) | is.na(tornadoes$elat) | tornadoes$elon == 0 | tornadoes$elat == 0
  same_pt <- !bad_end & tornadoes$slon == tornadoes$elon & tornadoes$slat == tornadoes$elat
  tornadoes$track_type <- ifelse(bad_end | same_pt, "point", "line")
  message("Track type: ", paste(names(table(tornadoes$track_type)), table(tornadoes$track_type), collapse = ", "))
  message("Lines with a width of 0 or missing (kept as given): ", sum(tornadoes$track_type == "line" & (is.na(tornadoes$wid) | tornadoes$wid <= 0)))
  tornadoes
}

# The complete SPC record of `years` (1996 on): every column and every row (sg 1, 2 and -9) as SPC gives them, plus the
# column tornado_id (not an SPC column) in front: the id of the whole-track row of the same year and om (NA where that is
# ambiguous or there is none).
spc_records <- function(raw, years, tornadoes) {
  r <- raw %>% filter(yr >= first_year, yr %in% years)
  key <- paste(r$yr, r$om, sep = "_")
  whole <- r$sg == 1
  stopifnot(sum(whole) == nrow(tornadoes), identical(key[whole], paste(tornadoes$yr, tornadoes$om, sep = "_")))   # spc_clean() keeps the sg == 1 rows in file order
  r$tornado_id <- NA_character_
  r$tornado_id[whole] <- tornadoes$tornado_id                       # the whole-track rows: the id, with the _1, _2 suffix where two share a year and om
  tkey <- paste(tornadoes$yr, tornadoes$om, sep = "_"); n <- table(tkey)
  other <- which(!whole & key %in% tkey & n[key] == 1L)               # other rows: the id of the whole-track row of the same year and om, when there is exactly one
  r$tornado_id[other] <- tornadoes$tornado_id[match(key[other], tkey)]
  r <- r[, c("tornado_id", setdiff(names(r), "tornado_id"))]
  as.data.frame(r)
}

# ---- geometry and ZCTA intersection -----------------------------------------
# Full TIGER/Line ZCTA polygons (not the cartographic files), repaired where invalid; the number repaired is an attribute.
load_zctas <- function(vintage) {
  z <- tigris::zctas(year = vintage)
  z <- z %>%
    rename(ZCTA = paste0("ZCTA5CE", substr(vintage, 3, 4)), ALAND = paste0("ALAND", substr(vintage, 3, 4))) %>%
    select(ZCTA, ALAND)
  z$ALAND <- as.numeric(z$ALAND)
  z <- st_transform(z, area_crs)
  invalid <- sum(!st_is_valid(z))      # planar (GEOS) validity in EPSG:5070, where the polygons are used
  z <- st_make_valid(z)
  z$zcta_polygon_area_m2 <- as.numeric(st_area(z))
  attr(z, "n_repaired") <- invalid
  z
}

# Length in meters of the straight line between the start and end points, on the sphere (as sf measures a longitude/latitude line with s2 on; the
# same measure as len_ratio). Only the line tornadoes have one.
.line_m <- function(geom) {
  old <- suppressMessages(sf::sf_use_s2(TRUE)); on.exit(suppressMessages(sf::sf_use_s2(old)))
  as.numeric(sf::st_length(geom))
}

# Builds, for cleaned tornadoes: `tracks` (tornado_tracks, with the tornado-level attributes) and `exposure` (the SPC columns of tornado_exposure; the
# DAT columns are added by data-raw/dat/build_dat_exposure.R). Needs the ZCTA files of the boundary years of the years present (downloaded through
# tigris) and zcta_centroids (`cen`).
#   line   : a ZCTA is exposed when a positive length of the line lies in it. The line is the straight line between SPC's start and end points
#            (straight in EPSG:5070). line_km_in_zcta is the share of the line in the ZCTA (measured in EPSG:5070) times line_km.
#   point  : a tornado with no usable end point is exposed in the ZCTA that contains its start point (boundary points count for each ZCTA).
spc_build <- function(tornadoes, cen) {
  is_line <- tornadoes$track_type == "line"
  geom <- st_sfc(lapply(seq_len(nrow(tornadoes)), function(i) {
    if (is_line[i]) st_linestring(rbind(c(tornadoes$slon[i], tornadoes$slat[i]), c(tornadoes$elon[i], tornadoes$elat[i])))
    else st_point(c(tornadoes$slon[i], tornadoes$slat[i]))
  }), crs = 4326)
  g5 <- st_transform(geom, area_crs)
  ids <- tornadoes$tornado_id
  line_m <- rep(NA_real_, nrow(tornadoes)); line_m[is_line] <- .line_m(geom[is_line]); line_km <- line_m / 1000
  len5 <- rep(NA_real_, nrow(tornadoes)); len5[is_line] <- as.numeric(st_length(g5[is_line]))

  intersect_vintage <- function(vintage, rows) {
    if (!length(rows)) return(NULL)
    zc <- load_zctas(vintage); message("  ZCTA file ", vintage, ": ", attr(zc, "n_repaired"), " invalid polygons repaired by st_make_valid")
    out <- list(); zcols <- c("ZCTA", "ALAND", "zcta_polygon_area_m2")
    rl <- rows[is_line[rows]]; rt <- rows[!is_line[rows]]
    if (length(rl)) {
      x <- suppressWarnings(st_intersection(st_sf(tornado_id = ids[rl], geometry = g5[rl]), zc))
      x <- x[st_geometry_type(x) %in% c("LINESTRING", "MULTILINESTRING"), ]; x$piece_m <- as.numeric(st_length(x))
      out[[1]] <- x %>% st_drop_geometry() %>% filter(piece_m > 0) %>% group_by(tornado_id, ZCTA) %>% summarise(piece_m = sum(piece_m), .groups = "drop") %>% mutate(kind = "line")
      # a ZCTA the line only touches at a point (zero length) is not exposed; the number is reported
      li <- st_intersects(g5[rl], zc); n_touch <- sum(lengths(li)) - nrow(out[[1]])
      message("  ZCTA file ", vintage, ": line-ZCTA pairs that touch at a point only (zero length, not exposed): ", n_touch)
    }
    if (length(rt)) {
      x <- suppressWarnings(st_intersection(st_sf(tornado_id = ids[rt], geometry = g5[rt]), zc))
      out[[2]] <- x %>% st_drop_geometry() %>% distinct(tornado_id, ZCTA) %>% mutate(piece_m = NA_real_, kind = "start point")
    }
    bind_rows(out)
  }
  yr_of <- tornadoes$yr
  pieces <- bind_rows(lapply(c(2000L, 2010L, 2020L), function(v) intersect_vintage(v, which(vint_of(yr_of) == v))))
  message("Tornado-ZCTA pairs: ", nrow(pieces), " (", paste(names(table(pieces$kind)), table(pieces$kind), collapse = ", "), ")")
  pt_n <- pieces %>% filter(kind == "start point") %>% count(tornado_id) %>% filter(n > 1)
  message("Point tornadoes whose start lies in more than one ZCTA: ", nrow(pt_n))
  no_zcta <- setdiff(tornadoes$tornado_id, pieces$tornado_id)
  message("Tornadoes with no exposed ZCTA (kept in tornado_tracks only): ", length(no_zcta), " (", sum(tornadoes$track_type[tornadoes$tornado_id %in% no_zcta] == "point"), " are points)")

  tinfo <- tornadoes %>% transmute(tornado_id, date, year = yr, month = mo, day = dy, magnitude,
                                   total_injury = inj, total_fatality = fat,
                                   # SPC loss 0 means unknown (NOAA: it does not mean $0), so it becomes NA
                                   property_loss_tornado_total = ifelse(loss_usd > 0, loss_usd, NA_real_), track_type)
  k <- match(pieces$tornado_id, ids)
  pieces$line_share_of_tornado <- ifelse(pieces$kind == "line", pieces$piece_m / ave(pieces$piece_m, pieces$tornado_id, FUN = sum), 1 / ave(rep(1, nrow(pieces)), pieces$tornado_id, FUN = sum))
  pieces$line_km_in_zcta <- ifelse(pieces$kind == "line", line_km[k] * pieces$piece_m / len5[k], NA_real_)
  exposure <- pieces %>%
    transmute(tornado_id, ZCTA, spc_exposed = TRUE, line_km_in_zcta, line_share_of_tornado) %>%
    left_join(tinfo, by = "tornado_id") %>%
    mutate(property_loss_allocated = property_loss_tornado_total * line_share_of_tornado, vint = vint_of(year)) %>%
    left_join(cen %>% transmute(vint = vintage, ZCTA, lon, lat, zcta_pop = as.numeric(zcta_pop), zcta_land_area_m2, zcta_polygon_area_m2, zcta_land_shape_area_m2), by = c("vint", "ZCTA"))
  if (anyNA(exposure$lon)) stop(sum(is.na(exposure$lon)), " tornado-ZCTA rows have a ZCTA that is not in zcta_centroids.", call. = FALSE)
  exposure$centroid_dist_km <- .track_centroid_dist(geom[match(exposure$tornado_id, ids)], exposure$lon, exposure$lat)
  exposure$boundary_dist_km <- 0     # exposed: the line crosses the ZCTA (or the start point lies in it)
  exposure <- exposure %>%
    select(tornado_id, date, year, month, day, magnitude, total_injury, total_fatality, property_loss_tornado_total, track_type, ZCTA,
           spc_exposed, line_km_in_zcta, line_share_of_tornado, property_loss_allocated, centroid_dist_km, boundary_dist_km,
           zcta_pop, zcta_land_area_m2, zcta_polygon_area_m2, zcta_land_shape_area_m2) %>%
    arrange(tornado_id, ZCTA) %>% as.data.frame()
  chk <- exposure %>% group_by(tornado_id) %>%
    summarise(share = sum(line_share_of_tornado), alloc = sum(property_loss_allocated), total = first(property_loss_tornado_total), .groups = "drop")
  stopifnot(all(abs(chk$share - 1) < 1e-9))
  known <- !is.na(chk$total)
  stopifnot(all(abs(chk$alloc[known] - chk$total[known]) <= 1e-8 * pmax(1, abs(chk$total[known]))), all(is.na(chk$alloc[!known])))
  inside_km <- tapply(exposure$line_km_in_zcta, exposure$tornado_id, sum)
  line_km_outside <- rep(NA_real_, nrow(tornadoes)); line_km_outside[is_line] <- line_km[is_line]
  m <- match(names(inside_km), ids); has <- !is.na(inside_km) & is_line[m]
  line_km_outside[m[has]] <- line_km[m[has]] - inside_km[has]
  message("line_km_outside_zcta: ", sum(line_km_outside < 0, na.rm = TRUE), " lines with a negative value (smallest ", signif(min(line_km_outside, na.rm = TRUE), 3), " km)")
  stopifnot(all(line_km_outside >= -1e-6, na.rm = TRUE))      # the ZCTAs do not overlap beyond floating-point error
  line_km_outside <- pmax(line_km_outside, 0)

  # straight start-to-end distance over reported length; NA for points. A ratio above 1 is physically
  # impossible; coordinates are trusted as given.
  mi_straight <- rep(NA_real_, nrow(tornadoes))
  mi_straight[is_line] <- line_m[is_line] / mi_to_m
  len_ratio <- ifelse(is_line & tornadoes$len > 0, mi_straight / tornadoes$len, NA_real_)
  tracks <- st_sf(
    tornado_id = tornadoes$tornado_id, date = tornadoes$date, magnitude = tornadoes$magnitude,
    total_injury = tornadoes$inj, total_fatality = tornadoes$fat,
    property_loss_tornado_total = ifelse(tornadoes$loss_usd > 0, tornadoes$loss_usd, NA_real_),
    track_type = tornadoes$track_type, len_mi = tornadoes$len, wid_yd = tornadoes$wid,
    slat = tornadoes$slat, slon = tornadoes$slon, elat = tornadoes$elat, elon = tornadoes$elon,
    len_ratio = len_ratio, line_km = line_km, line_km_outside_zcta = line_km_outside,
    loss_raw = tornadoes$loss_raw, loss_raw_unit = tornadoes$loss_raw_unit, geometry = geom)
  list(tracks = tracks, exposure = exposure, no_zcta = no_zcta)
}

# ---- provenance: which SPC release each year came from ----------------------------
# data-raw/provenance_years.csv has one row per SPC download (first_year, last_year, file, md5, bytes,
# access date, note); the same table is written into data-raw/provenance.txt.
record_spc_release <- function(first, last, dl, note, prov_dir = "data-raw", replace_all = FALSE) {
  f <- file.path(prov_dir, "provenance_years.csv")
  row <- data.frame(first_year = first, last_year = last, spc_file = dl$url, md5 = dl$md5, bytes = dl$bytes,
                    access_date = format(dl$access_date), note = note, stringsAsFactors = FALSE)
  tab <- if (!replace_all && file.exists(f)) rbind(utils::read.csv(f, stringsAsFactors = FALSE), row) else row
  utils::write.csv(tab, f, row.names = FALSE)
  p <- file.path(prov_dir, "provenance.txt")
  prov <- if (file.exists(p)) readLines(p) else character(0)
  i <- which(prov == "## SPC release by year")[1]
  if (!is.na(i)) {                      # drop the old section (up to the next section or the end)
    nxt <- which(grepl("^## ", prov) & seq_along(prov) > i)[1]
    prov <- prov[-(i:(if (is.na(nxt)) length(prov) else nxt - 1))]
  }
  sec <- c("## SPC release by year",
           "Each year of the data comes from one SPC download (an update appends only the years after the last stored one).",
           apply(tab, 1, function(r) sprintf("%s-%s: %s, md5 %s, %s bytes, accessed %s (%s)", r[["first_year"]], r[["last_year"]], r[["spc_file"]], r[["md5"]], trimws(r[["bytes"]]), r[["access_date"]], r[["note"]])), "")
  j <- which(prov == "## Population sources")[1]
  prov <- if (is.na(j)) c(prov, sec) else append(prov, sec, after = j - 1)
  writeLines(prov, p)
  invisible(tab)
}

# The DAT columns for new SPC rows: no DAT link is known yet (data-raw/dat/build_dat_exposure.R fills the DAT columns of every row from the DAT datasets).
# `template` is the stored tornado_exposure, which gives the column order and types.
add_dat_columns <- function(new_exposure, template) {
  for (nm in setdiff(names(template), names(new_exposure))) new_exposure[[nm]] <- if (nm == "dat_linked") rep(FALSE, nrow(new_exposure)) else template[[nm]][NA_integer_][rep(1L, nrow(new_exposure))]
  new_exposure[, names(template)]
}

# ---- checks before appending ---------------------------------------------------------------------------------------------
# Stops with one message listing everything that does not match the stored data.
check_new_rows <- function(new_tracks, new_exposure, stored_tracks, stored_exposure, new_years, new_records = NULL, stored_records = NULL) {
  bad <- character(0)
  cls <- function(d) vapply(sf::st_drop_geometry(d), function(x) class(x)[1], character(1))
  if (!identical(names(new_exposure), names(stored_exposure))) bad <- c(bad, "tornado_exposure columns differ from the stored columns")
  else if (!identical(cls(new_exposure), cls(stored_exposure))) bad <- c(bad, paste0("tornado_exposure column types differ: ", paste(names(stored_exposure)[cls(new_exposure) != cls(stored_exposure)], collapse = ", ")))
  if (!identical(names(sf::st_drop_geometry(new_tracks)), names(sf::st_drop_geometry(stored_tracks)))) bad <- c(bad, "tornado_tracks columns differ from the stored columns")
  else if (!identical(cls(new_tracks), cls(stored_tracks))) bad <- c(bad, paste0("tornado_tracks column types differ: ", paste(setdiff(names(cls(stored_tracks)), names(cls(stored_tracks))[cls(new_tracks) == cls(stored_tracks)]), collapse = ", ")))
  if (!identical(sf::st_crs(new_tracks), sf::st_crs(stored_tracks))) bad <- c(bad, "tornado_tracks CRS differs from the stored CRS")
  if (!is.null(new_records) && !identical(names(new_records), names(stored_records))) bad <- c(bad, "spc_records columns differ from the stored columns")
  if (!is.null(new_records) && !identical(cls(new_records), cls(stored_records))) bad <- c(bad, "spc_records column types differ from the stored types")
  # ids
  pat <- "^[0-9]{4}_[0-9]+(-[0-9]+)?(_[0-9]+)?$"
  if (!all(grepl(pat, new_tracks$tornado_id))) bad <- c(bad, paste0("tornado_id does not follow the pattern <year>_<om> (for example 2011_1105221634-01): ", paste(utils::head(new_tracks$tornado_id[!grepl(pat, new_tracks$tornado_id)], 3), collapse = ", ")))
  if (anyDuplicated(new_tracks$tornado_id)) bad <- c(bad, "duplicated tornado_id in the new rows")
  if (any(new_tracks$tornado_id %in% stored_tracks$tornado_id)) bad <- c(bad, "new tornado_id values already exist in the stored data")
  if (!all(as.integer(substr(new_tracks$tornado_id, 1, 4)) %in% new_years)) bad <- c(bad, "new rows contain years outside the years being added")
  if (!all(new_exposure$tornado_id %in% new_tracks$tornado_id)) bad <- c(bad, "exposure rows without a track")
  if (anyDuplicated(new_exposure[c("tornado_id", "ZCTA")])) bad <- c(bad, "duplicated tornado-ZCTA pairs in the new rows")
  # ranges
  xy <- do.call(rbind, lapply(sf::st_geometry(new_tracks), function(g) { m <- unclass(g); if (!is.matrix(m)) m <- matrix(m, ncol = 2); m[, 1:2, drop = FALSE] }))   # every vertex (lines and points)
  if (any(xy[, 2] < 15 | xy[, 2] > 72 | xy[, 1] < -180 | xy[, 1] > -60)) bad <- c(bad, "track coordinates outside the sanity limits (latitude 15 to 72, longitude -180 to -60)")
  if (any(!is.finite(new_tracks$wid_yd) | new_tracks$wid_yd < 0 | new_tracks$wid_yd > 10000)) bad <- c(bad, "path width outside 0 to 10,000 yards (a width of 0 is allowed and is kept)")
  if (any(!is.finite(new_tracks$len_mi) | new_tracks$len_mi < 0 | new_tracks$len_mi > 400)) bad <- c(bad, "path length outside 0 to 400 miles")
  if (!all(new_tracks$track_type %in% c("line", "point"))) bad <- c(bad, "track_type must be line or point")
  if (!all(new_tracks$magnitude %in% c(0:5, NA))) bad <- c(bad, "magnitude outside 0 to 5")
  if (!all(new_tracks$loss_raw_unit == "dollars" | new_tracks$loss_raw_unit == "millions")) bad <- c(bad, "unexpected loss unit")
  if (any(new_tracks$loss_raw_unit == "millions")) bad <- c(bad, "new years must have loss in dollars (loss_raw_unit), but some are in millions")
  # SPC loss of 0 means unknown and is stored as NA (the raw value stays in loss_raw)
  if (!identical(is.na(new_tracks$property_loss_tornado_total), new_tracks$loss_raw == 0)) bad <- c(bad, "property_loss_tornado_total must be NA exactly where SPC loss is 0")
  if (!identical(is.na(new_exposure$property_loss_allocated), is.na(new_exposure$property_loss_tornado_total))) bad <- c(bad, "property_loss_allocated must be NA exactly where the tornado total is NA")
  nzl <- new_tracks$property_loss_tornado_total[!is.na(new_tracks$property_loss_tornado_total)]
  if (length(nzl) && (median(nzl) < 10000 || max(nzl) > 1e11)) bad <- c(bad, sprintf("loss outside the dollar range (median of known loss %.0f, maximum %.0f; expected median of at least 10,000 and maximum below 1e11)", median(nzl), max(nzl)))
  # SPC columns: every new row is exposed by the SPC line, the shares sum to 1, the line lengths add up, the distances are not negative, the DAT columns are empty
  if (!all(new_exposure$spc_exposed)) bad <- c(bad, "spc_exposed must be TRUE for every new row")
  if (any(new_exposure$boundary_dist_km != 0)) bad <- c(bad, "boundary_dist_km must be 0 where spc_exposed is TRUE")
  if (any(new_exposure$centroid_dist_km < 0)) bad <- c(bad, "negative distance")
  if (any(new_exposure$line_share_of_tornado <= 0 | new_exposure$line_share_of_tornado > 1 + 1e-9)) bad <- c(bad, "line_share_of_tornado must be in (0, 1]")
  sh <- tapply(new_exposure$line_share_of_tornado, new_exposure$tornado_id, sum)
  if (any(abs(sh - 1) > 1e-9)) bad <- c(bad, "line_share_of_tornado does not sum to 1 for every tornado")
  pt <- new_exposure$track_type == "point"
  if (!identical(is.na(new_exposure$line_km_in_zcta), pt)) bad <- c(bad, "line_km_in_zcta must be NA exactly for tornadoes with no usable end point")
  al <- tapply(new_exposure$property_loss_allocated, new_exposure$tornado_id, sum); tl <- tapply(new_exposure$property_loss_tornado_total, new_exposure$tornado_id, function(x) x[1])
  if (any(!is.na(tl) & abs(al - tl) > 1e-8 * pmax(1, abs(tl)), na.rm = TRUE)) bad <- c(bad, "allocated loss does not sum back to the tornado total for every tornado with a known loss")
  if (any(!is.na(new_tracks$line_km_outside_zcta) & (new_tracks$line_km_outside_zcta < 0 | new_tracks$line_km_outside_zcta > new_tracks$line_km + 1e-9))) bad <- c(bad, "line_km_outside_zcta must be between 0 and line_km")
  if (any(new_exposure$dat_linked) || any(!is.na(new_exposure$dat_exposed))) bad <- c(bad, "the DAT columns of new rows must be empty (build_dat_exposure.R fills them)")
  if (length(bad)) stop("The new rows do not match the stored data, so nothing was written:\n  - ", paste(bad, collapse = "\n  - "), "\nInspect the SPC file and the checks in data-raw/pipeline_functions.R (check_new_rows).", call. = FALSE)
  invisible(TRUE)
}
