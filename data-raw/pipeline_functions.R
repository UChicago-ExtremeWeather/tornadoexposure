# Functions that turn SPC tornado records into the package data. Shared by
#   data-raw/process_tracks.R  (full rebuild, for verification and deliberate full rebuilds)
#   data-raw/update_data.R     (incremental, append-only update with a new SPC release)
# so the two cannot disagree. Source from the package root.
suppressMessages({library(readr); library(dplyr); library(sf)})
source("R/path_polygon.R")
options(tigris_use_cache = TRUE)

area_crs <- .area_crs
yd_to_m <- .yd_to_m
mi_to_m <- .mi_to_m
min_width_yd <- 10      # NOAA documents a 30 foot (10 yard) minimum width
first_year <- 1996
vint_of <- function(y) ifelse(y < 2010, 2000L, ifelse(y < 2020, 2010L, 2020L))

# ---- SPC file ---------------------------------------------------------------
spc_url <- function(latest_year) sprintf("https://www.spc.noaa.gov/wcm/data/1950-%s_all_tornadoes.csv", latest_year)

# downloads the file once so that it can be fingerprinted (provenance)
spc_download <- function(latest_year) {
  url <- spc_url(latest_year)
  f <- tempfile(fileext = ".csv")
  utils::download.file(url, f, mode = "wb", quiet = TRUE)
  list(file = f, url = url, md5 = unname(tools::md5sum(f)), bytes = file.size(f), access_date = Sys.Date())
}

# ---- cleaning ---------------------------------------------------------------
# Keeps the whole-track records (sg == 1) of `years`, makes tornado_id, harmonizes loss to nominal
# dollars (with the unit-break guard), classifies line and point tracks, imputes zero widths.
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

  # loss: harmonize to nominal dollars. NOAA documents SPC `loss` as millions of dollars from 1996.
  # In the 2025 file the values are in millions through 2006 and in whole dollars from 2007 (SPC
  # re-coded 2007-2015 between its 2024 and 2025 releases). Guard thresholds were chosen from the
  # data: for 1996-2006 the yearly median of nonzero loss is at most 0.07 and the maximum is 1,000;
  # for 2007 onward the yearly median is at least 50,000. If SPC moves the break, stop rather than
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
  # raw millions have at most three decimals, so rounding to whole dollars is exact
  tornadoes$loss_usd <- ifelse(tornadoes$yr < loss_break_year, round(tornadoes$loss * 1e6), tornadoes$loss)
  message("Loss unit guard passed (break at ", loss_break_year, "); nonzero loss: ",
          sum(tornadoes$loss > 0), " tornadoes, ", sum(tornadoes$loss == 0), " with loss 0")

  # no valid start location: cannot be placed
  no_start <- is.na(tornadoes$slon) | is.na(tornadoes$slat) | tornadoes$slon == 0 | tornadoes$slat == 0
  message("Dropped, no valid start location: ", sum(no_start))
  tornadoes <- tornadoes[!no_start, ]

  # missing or zero end coordinates (unknown end), or end == start, are treated as a point at the
  # start. Direction is unknown, so the path polygon is a disc:
  #   point_equal_area: len > 0, disc centered on the start with area len * wid
  #   point_half_width: len == 0, disc with radius of half the width
  bad_end <- is.na(tornadoes$elon) | is.na(tornadoes$elat) | tornadoes$elon == 0 | tornadoes$elat == 0
  same_pt <- !bad_end & tornadoes$slon == tornadoes$elon & tornadoes$slat == tornadoes$elat
  tornadoes$track_type <- ifelse(
    !(bad_end | same_pt), "line",
    ifelse(!is.na(tornadoes$len) & tornadoes$len > 0, "point_equal_area", "point_half_width"))
  message("Track type: ", paste(names(table(tornadoes$track_type)), table(tornadoes$track_type), collapse = ", "))

  # width of 0 (or missing) is replaced by the documented minimum
  tornadoes$width_imputed <- is.na(tornadoes$wid) | tornadoes$wid <= 0
  tornadoes$wid[tornadoes$width_imputed] <- min_width_yd
  message("Width imputed to ", min_width_yd, " yards: ", sum(tornadoes$width_imputed))
  tornadoes
}

# ---- geometry and ZCTA intersection -----------------------------------------
load_zctas <- function(vintage) {
  z <- tigris::zctas(year = vintage)
  z <- z %>%
    rename(ZCTA = paste0("ZCTA5CE", substr(vintage, 3, 4)), ALAND = paste0("ALAND", substr(vintage, 3, 4))) %>%
    select(ZCTA, ALAND)
  z$ALAND <- as.numeric(z$ALAND)
  st_make_valid(st_transform(z, area_crs))
}

# Builds, for cleaned tornadoes: `tracks` (tornado_tracks, with the tornado-level attributes) and
# `exposure` (tornado_exposure without the population columns). Needs the ZCTA files of the vintages
# of the years present (downloaded through tigris).
spc_build <- function(tornadoes) {
  make_geom <- function(i) {
    if (tornadoes$track_type[i] == "line") {
      st_linestring(rbind(c(tornadoes$slon[i], tornadoes$slat[i]), c(tornadoes$elon[i], tornadoes$elat[i])))
    } else st_point(c(tornadoes$slon[i], tornadoes$slat[i]))
  }
  geom <- st_sfc(lapply(seq_len(nrow(tornadoes)), make_geom), crs = 4326)
  is_line <- tornadoes$track_type == "line"
  is_eq <- tornadoes$track_type == "point_equal_area"
  half_width_m <- tornadoes$wid * yd_to_m / 2
  radius_eq_m <- sqrt(tornadoes$len * mi_to_m * tornadoes$wid * yd_to_m / pi)
  message("Equal-area discs smaller than the half-width disc: ", sum(is_eq & radius_eq_m < half_width_m))
  # the shared builder (also used by add_tracks() in the package)
  poly <- .path_polygon(geom, tornadoes$wid, tornadoes$len, tornadoes$track_type, crs = area_crs)
  tornado_polys <- st_sf(tornado_id = tornadoes$tornado_id, tornado_area_m2 = as.numeric(st_area(poly)), geometry = poly)

  intersect_vintage <- function(tracks, vintage) {
    if (nrow(tracks) == 0) return(NULL)
    zc <- load_zctas(vintage)
    x <- suppressWarnings(st_intersection(tracks["tornado_id"], zc))
    # keep polygonal pieces only (touching boundaries yield lines or points)
    x <- st_collection_extract(x, "POLYGON")
    x$intersection_m2 <- as.numeric(st_area(x))
    x %>% st_drop_geometry() %>% group_by(tornado_id, ZCTA, ALAND) %>% summarise(intersection_m2 = sum(intersection_m2), .groups = "drop")
  }
  yr_of <- tornadoes$yr
  pieces <- bind_rows(
    intersect_vintage(tornado_polys[yr_of < 2010, ], 2000),
    intersect_vintage(tornado_polys[yr_of >= 2010 & yr_of < 2020, ], 2010),
    intersect_vintage(tornado_polys[yr_of >= 2020, ], 2020))
  message("Tornado-ZCTA pairs before dropping zero areas: ", nrow(pieces))
  zero_area <- pieces$intersection_m2 <= 0
  message("Dropped, exact-zero intersection area: ", sum(zero_area))
  pieces <- pieces[!zero_area, ]
  no_zcta <- setdiff(tornadoes$tornado_id, pieces$tornado_id)
  message("Tornadoes that intersect no ZCTA (kept in tornado_tracks only): ", length(no_zcta))

  exposure <- pieces %>%
    group_by(tornado_id) %>%
    mutate(area_share_of_tornado = intersection_m2 / sum(intersection_m2)) %>%
    ungroup() %>%
    # ALAND excludes water while ZCTA polygons include it, so a path can slightly exceed ALAND; cap at 1
    mutate(area_prop_uncapped = intersection_m2 / ALAND, area_prop_affected = pmin(area_prop_uncapped, 1)) %>%
    left_join(tornadoes %>% transmute(tornado_id, date, year = yr, month = mo, day = dy, magnitude,
                                      total_injury = inj, total_fatality = fat,
                                      # SPC loss 0 means unknown (NOAA: it does not mean $0), so it becomes NA
                                      property_loss_tornado_total = ifelse(loss_usd > 0, loss_usd, NA_real_), track_type),
              by = "tornado_id") %>%
    mutate(property_loss_allocated = property_loss_tornado_total * area_share_of_tornado) %>%
    select(tornado_id, date, year, month, day, magnitude, total_injury, total_fatality,
           property_loss_tornado_total, property_loss_allocated, ZCTA, area_prop_affected, area_prop_uncapped,
           area_share_of_tornado, track_type) %>%
    arrange(tornado_id, ZCTA) %>%
    as.data.frame()
  message("area_prop_affected capped at 1: ", sum(exposure$area_prop_uncapped > 1), " rows")
  exposure$area_prop_uncapped <- NULL
  chk <- exposure %>% group_by(tornado_id) %>%
    summarise(share = sum(area_share_of_tornado), alloc = sum(property_loss_allocated), total = first(property_loss_tornado_total), .groups = "drop")
  stopifnot(all(abs(chk$share - 1) < 1e-9))
  # known loss: the allocated loss sums back to the total; unknown loss (NA): the allocated loss is NA
  known <- !is.na(chk$total)
  stopifnot(all(abs(chk$alloc[known] - chk$total[known]) <= 1e-8 * pmax(1, abs(chk$total[known]))), all(is.na(chk$alloc[!known])))

  # straight start-to-end distance over reported length; NA for points. A ratio above 1 is physically
  # impossible; coordinates are trusted as given.
  mi_straight <- rep(NA_real_, nrow(tornadoes))
  mi_straight[is_line] <- as.numeric(st_length(geom[is_line])) / mi_to_m
  len_ratio <- ifelse(is_line & tornadoes$len > 0, mi_straight / tornadoes$len, NA_real_)
  tracks <- st_sf(
    tornado_id = tornadoes$tornado_id, date = tornadoes$date, magnitude = tornadoes$magnitude,
    total_injury = tornadoes$inj, total_fatality = tornadoes$fat,
    property_loss_tornado_total = ifelse(tornadoes$loss_usd > 0, tornadoes$loss_usd, NA_real_),
    track_type = tornadoes$track_type, width_imputed = tornadoes$width_imputed, len_mi = tornadoes$len,
    wid_yd = tornadoes$wid, len_ratio = len_ratio, tornado_area_m2 = tornado_polys$tornado_area_m2,
    loss_raw = tornadoes$loss_raw, loss_raw_unit = tornadoes$loss_raw_unit, geometry = geom)
  list(tracks = tracks, exposure = exposure, no_zcta = no_zcta, polygons = poly)
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

# ---- checks before appending ---------------------------------------------------------
# Stops with one message listing everything that does not match the stored data.
check_new_rows <- function(new_tracks, new_exposure, stored_tracks, stored_exposure, new_years) {
  bad <- character(0)
  cls <- function(d) vapply(sf::st_drop_geometry(d), function(x) class(x)[1], character(1))
  if (!identical(names(new_exposure), names(stored_exposure))) bad <- c(bad, "tornado_exposure columns differ from the stored columns")
  else if (!identical(cls(new_exposure), cls(stored_exposure))) bad <- c(bad, paste0("tornado_exposure column types differ: ", paste(names(stored_exposure)[cls(new_exposure) != cls(stored_exposure)], collapse = ", ")))
  if (!identical(names(sf::st_drop_geometry(new_tracks)), names(sf::st_drop_geometry(stored_tracks)))) bad <- c(bad, "tornado_tracks columns differ from the stored columns")
  else if (!identical(cls(new_tracks), cls(stored_tracks))) bad <- c(bad, paste0("tornado_tracks column types differ: ", paste(setdiff(names(cls(stored_tracks)), names(cls(stored_tracks))[cls(new_tracks) == cls(stored_tracks)]), collapse = ", ")))
  if (!identical(sf::st_crs(new_tracks), sf::st_crs(stored_tracks))) bad <- c(bad, "tornado_tracks CRS differs from the stored CRS")
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
  if (any(!is.finite(new_tracks$wid_yd) | new_tracks$wid_yd <= 0 | new_tracks$wid_yd > 10000)) bad <- c(bad, "path width outside 0 to 10,000 yards")
  if (any(!is.finite(new_tracks$len_mi) | new_tracks$len_mi < 0 | new_tracks$len_mi > 400)) bad <- c(bad, "path length outside 0 to 400 miles")
  if (!all(new_tracks$magnitude %in% c(0:5, NA))) bad <- c(bad, "magnitude outside 0 to 5")
  if (!all(new_tracks$loss_raw_unit == "dollars" | new_tracks$loss_raw_unit == "millions")) bad <- c(bad, "unexpected loss unit")
  if (any(new_tracks$loss_raw_unit == "millions")) bad <- c(bad, "new years must have loss in dollars (loss_raw_unit), but some are in millions")
  # SPC loss of 0 means unknown and is stored as NA (the raw value stays in loss_raw)
  if (!identical(is.na(new_tracks$property_loss_tornado_total), new_tracks$loss_raw == 0)) bad <- c(bad, "property_loss_tornado_total must be NA exactly where SPC loss is 0")
  if (!identical(is.na(new_exposure$property_loss_allocated), is.na(new_exposure$property_loss_tornado_total))) bad <- c(bad, "property_loss_allocated must be NA exactly where property_loss_tornado_total is NA")
  nzl <- new_tracks$property_loss_tornado_total[!is.na(new_tracks$property_loss_tornado_total)]
  if (length(nzl) && (median(nzl) < 10000 || max(nzl) > 1e11)) bad <- c(bad, sprintf("loss outside the dollar range (median of known loss %.0f, maximum %.0f; expected median of at least 10,000 and maximum below 1e11)", median(nzl), max(nzl)))
  if (any(new_exposure$area_prop_affected <= 0 | new_exposure$area_prop_affected > 1)) bad <- c(bad, "area_prop_affected outside (0, 1]")
  if (any(!is.na(new_exposure$pop_prop_affected) & (new_exposure$pop_prop_affected < 0 | new_exposure$pop_prop_affected > 1 + 1e-9))) bad <- c(bad, "pop_prop_affected outside [0, 1]")
  if (any(new_exposure$pop_affected > new_exposure$zcta_pop + 1e-6)) bad <- c(bad, "pop_affected above zcta_pop")
  if (any(abs(tapply(new_exposure$area_share_of_tornado, new_exposure$tornado_id, sum) - 1) > 1e-9)) bad <- c(bad, "area_share_of_tornado does not sum to 1 for every tornado")
  al <- tapply(new_exposure$property_loss_allocated, new_exposure$tornado_id, sum); tl <- tapply(new_exposure$property_loss_tornado_total, new_exposure$tornado_id, function(x) x[1])
  if (any(!is.na(tl) & abs(al - tl) > 1e-8 * pmax(1, abs(tl)), na.rm = TRUE)) bad <- c(bad, "allocated loss does not sum back to the tornado total for every tornado with a known loss")
  if (length(bad)) stop("The new rows do not match the stored data, so nothing was written:\n  - ", paste(bad, collapse = "\n  - "), "\nInspect the SPC file and the checks in data-raw/pipeline_functions.R (check_new_rows).", call. = FALSE)
  invisible(TRUE)
}
