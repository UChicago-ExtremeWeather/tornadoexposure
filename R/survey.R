# NWS survey sensitivity layer. Everything about it lives in this file, in
# R/data_survey.R, in the datasets survey_exposure, survey_tracks and
# survey_matches (data/), in data-raw/survey/, in the survey section of
# data-raw/qa/check_data_integrity.R, and in one branch of add_tracks()
# (geometry = "survey"). To remove the layer, delete those and that branch.

.survey_exposure <- function() tornadoexposure::survey_exposure
.survey_tracks <- function() tornadoexposure::survey_tracks
.survey_matches <- function() tornadoexposure::survey_matches
.survey_id_columns <- c("path_source", "survey_line_id", "survey_event_id")

.empty_survey <- function(distance) {
  e <- .survey_exposure()[0, , drop = FALSE]
  if (distance) {
    e$dist_km <- numeric(0); e$centroid_type <- character(0)
    e$centroid_in_zcta <- logical(0)
  }
  e
}

# Survey paths with the centroid of each requested ZCTA within v$threshold km.
# The swaths are the 50 m simplified polygons in survey_tracks, so distances
# differ from those to the full-resolution swaths by at most 50 m.
.survey_distance <- function(v) {
  trk <- .survey_tracks()
  tt <- .tracks()
  attrs <- sf::st_drop_geometry(tt)[match(trk$tornado_id, tt$tornado_id),
    c("tornado_id", "date", "magnitude", "total_injury", "total_fatality",
      "property_loss_tornado_total", "track_type")]
  year <- as.integer(substr(trk$tornado_id, 1, 4))
  keep <- year %in% v$year_range & attrs$magnitude %in% v$magnitude
  trk <- trk[keep, ]
  attrs <- attrs[keep, ]
  cen <- .centroids()
  cen <- cen[Reduce(`|`, lapply(v$geo_list, function(p) startsWith(cen$ZCTA, p))), ]
  out <- .empty_survey(TRUE)
  if (nrow(trk) > 0L && nrow(cen) > 0L) {
    vint <- .vintage_of(as.integer(substr(trk$tornado_id, 1, 4)))
    .slow_distance_message(v$threshold, .vint_counts(vint), cen)
    geom <- sf::st_geometry(trk)
    pr <- .distance_pairs(.distance_region(trk), vint, cen, v$threshold,
                          function(i, crs) sf::st_transform(geom[i], crs))
    if (nrow(pr) > 0L) {
      pairs <- data.frame(tornado_id = trk$tornado_id[pr$i], ZCTA = cen$ZCTA[pr$j],
                          vintage = cen$vintage[pr$j], dist_km = pr$dist_km,
                          stringsAsFactors = FALSE)
      res <- .assemble_distance(pairs, attrs, .survey_exposure(), cen)
      m <- .survey_matches()[match(res$tornado_id, .survey_matches()$tornado_id), ]
      res$path_source <- "nws_survey"
      res$survey_line_id <- m$survey_line_id
      res$survey_event_id <- m$survey_event_id
      out <- res[, c(.exposure_columns(), .survey_id_columns, .distance_columns)]
    }
  }
  out
}

# What the survey layer covers for this request, as one message
.survey_coverage_message <- function(v, n_returned) {
  sm <- .survey_matches()
  spc <- .filter_overlap_rows(.exposure(), list(
    geo_list = v$geo_list, year_range = v$year_range, magnitude = v$magnitude,
    definition = "overlap", threshold = NULL))
  ids <- unique(spc$tornado_id)
  st <- sm$status[match(ids, sm$tornado_id)]
  n_in <- sum(st %in% "included")
  survey_years <- sort(unique(as.integer(substr(.survey_tracks()$tornado_id, 1, 4))))
  data_years <- seq(.data_years()[1], .data_years()[2])
  asked <- intersect(v$year_range, data_years)
  none <- setdiff(asked, survey_years)
  msg <- paste0(
    "NWS survey coverage for this request: ", n_in, " of ", length(ids),
    " SPC tornadoes that overlap these ZCTAs in the requested years and ratings have a surveyed damage swath (see ?survey_matches)",
    if (n_in < length(ids)) ". The rest have no surveyed swath and are not returned." else ".")
  if (length(none) > 0L) {
    msg <- paste0(msg, " No survey swaths exist for ",
                  if (length(none) == length(asked)) "any requested year" else "the years",
                  ": ", paste(.year_runs(none), collapse = ", "), ".")
  }
  message(paste(strwrap(msg, width = 78), collapse = "\n"))
  invisible(NULL)
}

# 2007:2010 -> "2007-2010", c(1996, 1998) -> c("1996", "1998")
.year_runs <- function(y) {
  y <- sort(unique(y))
  grp <- cumsum(c(TRUE, diff(y) != 1L))
  vapply(split(y, grp), function(x) {
    if (length(x) == 1L) as.character(x) else paste0(min(x), "-", max(x))
  }, character(1), USE.NAMES = FALSE)
}

.select_survey <- function(v) {
  out <- if (v$definition == "centroid_dist_km") {
    .survey_distance(v)
  } else {
    d <- .filter_overlap_rows(.survey_exposure(), v)
    d <- d[order(d$date, d$tornado_id, d$ZCTA), , drop = FALSE]
    rownames(d) <- NULL
    d
  }
  .survey_coverage_message(v, nrow(out))
  if (nrow(out) == 0L) {
    message("No survey exposures found for ", .describe_request(v), ". ",
            "Try a wider year_range, more magnitudes, or a lower threshold.")
  } else if (v$definition == "centroid_dist_km") {
    .warn_geometric_centroids(out)
  }
  out
}

#' Get tornado exposures from NWS damage-survey paths (sensitivity layer)
#'
#' The same exposure definitions as [get_data()], computed from the swaths
#' surveyed by National Weather Service offices instead of from SPC's straight
#' line between the start and end points. SPC remains the main exposure; this is
#' a sensitivity layer for the tornadoes that have a usable damage swath (defined
#' below). See `data-raw/known_issues.md` (section "When to use SPC and when to
#' use the survey data") for when to use which.
#'
#' Returns one row per exposed tornado-ZCTA pair under the single definition you
#' pass (overlap by default, or `area_thresh`, `pop_thresh` or `centroid_dist_km`;
#' they cannot be combined). Rows have the columns of [tornado_exposure] plus
#' `path_source` (always `"nws_survey"`), `survey_line_id` and `survey_event_id`
#' (identifiers of the survey line in the Damage Assessment Toolkit; the event id
#' is missing for some lines), and, with `centroid_dist_km`, the distance columns
#' described in [get_data()]. Tornado-level attributes (magnitude, injuries,
#' fatalities, property loss) are SPC's, repeated as in [get_data()].
#' `track_type` is the SPC track type of the tornado.
#'
#' Only tornadoes with a usable damage swath are in this layer, so a call returns
#' no rows for most tornadoes (`data-raw/known_issues.md` gives the share of
#' tornadoes with a swath by year, rating and length). Every call prints
#' a message with the coverage for your request: how many of the SPC tornadoes
#' that overlap the requested ZCTAs, years and ratings have a swath, and any
#' requested years with no survey swaths at all.
#'
#' `r paste(readLines("data-raw/survey/pairing_help.md"), collapse = "\n")`
#'
#' `r paste(readLines("data-raw/survey/status_definitions.md"), collapse = "\n")`
#'
#' `r paste(readLines("data-raw/survey/settings_help.md"), collapse = "\n")`
#'
#' **The data are preliminary.** The service description reads: "While the data
#' has been quality controlled, it is still considered preliminary." The service's
#' copyright text is "NOAA National Weather Service". Its item on the NOAA
#' GeoPlatform (<https://www.arcgis.com/home/item.html?id=b6b9dd55450a4f64bcafb3cd6e005a5c>)
#' gives the credit "NOAA/National Weather Service" and the constraint "All data
#' is considered preliminary and unofficial." A GeoPlatform page for the Damage
#' Assessment Toolkit
#' (<https://disasters-geoplatform.hub.arcgis.com/pages/noaa-damage-assessment-toolkit-dat>)
#' says "This dataset is intended for public access and use."; that page links the
#' viewer and an older service address that no longer exists, so it is not
#' confirmed to refer to the service used here. No notice found sets terms of use
#' or asks for a particular citation. The exact wording of every notice is in
#' `data-raw/known_issues.md`.
#'
#' **What the survey layer is.** The survey data are damage zones mapped by National
#' Weather Service survey teams after the tornado. They are used to see whether results
#' change when the surveyed damage area replaces the modeled path.
#'
#' **Credit.** NOAA National Weather Service Damage Assessment Toolkit,
#' <https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer>,
#' layers 1 (Damage Lines) and 2 (Damage Polygons), accessed
#' `r readLines("data-raw/survey/access_date.txt")`. The data in this package are a
#' frozen snapshot of that service; nothing is downloaded when you call the
#' function.
#'
#' @inheritParams get_data
#' @param magnitude Ratings to include, as in [get_data()]. The rating is SPC's
#'   rating of the tornado.
#'
#' @return A data frame (no geometry), possibly empty (with a message).
#'
#' @examples
#' # Moore, Oklahoma, May 2013 (the SPC path is in get_data())
#' get_survey_data(geo_list = "731", year_range = 2013, magnitude = 5)
#'
#' @export
get_survey_data <- function(geography = "zcta", geo_list, year_range,
                            magnitude = c(0:5, NA), area_thresh = NULL,
                            pop_thresh = NULL, centroid_dist_km = NULL) {
  v <- .validate_args(
    "get_survey_data", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(area_thresh = area_thresh, pop_thresh = pop_thresh,
                      centroid_dist_km = centroid_dist_km)
  )
  .select_survey(v)
}
