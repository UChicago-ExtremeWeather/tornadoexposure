# Documentation of the survey sensitivity layer datasets (see R/survey.R)

#' NWS survey exposures (sensitivity layer)
#'
#' One row per tornado-ZCTA pair for the tornadoes with a usable damage-survey
#' swath, computed from the swath instead of from SPC's straight path. It has the
#' same columns, definitions and caveats as [tornado_exposure], plus the three
#' columns below, so the two can be compared directly. Use [get_survey_data()]
#' to query it.
#'
#' @details
#' A tornado is in this table when it was paired with a National Weather Service
#' survey line (its closest survey line, whose closest tornado is also that
#' tornado; see [get_survey_data()]) and the survey's rated damage polygons, after
#' a filter described in [survey_matches], lie within 200 m of at least half of
#' the length of the surveyed centerline (a usable damage swath). The swath is the
#' union of those polygons. `area_prop_affected` is the swath area
#' inside the ZCTA divided by the ZCTA's land area, `area_share_of_tornado` the
#' swath's share across ZCTAs, and `pop_affected` the residents inside the swath
#' from block-level population, as for the SPC paths. The swath polygons were
#' fetched with the service's generalization set to 0.0002 degrees (about 20 m).
#' Property loss, injuries, fatalities and rating are
#' SPC's, allocated or repeated as in [tornado_exposure]. The survey data are
#' preliminary (the service says so). See [survey_matches] for how each tornado
#' was paired, and [get_survey_data()] for credit and terms.
#'
#' @format A data frame with `r format(nrow(survey_exposure), big.mark = ",")`
#'   rows for `r format(length(unique(survey_exposure$tornado_id)), big.mark = ",")`
#'   tornadoes and `r ncol(survey_exposure)` variables. The first
#'   `r ncol(tornado_exposure)` have the same definitions as in [tornado_exposure]
#'   (the path is the survey swath), and the last three are specific to this layer:
#' \describe{
#'   \item{tornado_id}{Tornado identifier (SPC).}
#'   \item{date, year, month, day}{Date of the tornado.}
#'   \item{magnitude}{SPC rating from 0 to 5, or `NA` when unknown.}
#'   \item{total_injury, total_fatality}{Tornado-level totals (SPC), repeated on
#'     every row of the tornado.}
#'   \item{property_loss_tornado_total}{SPC property loss for the whole tornado,
#'     in nominal dollars, repeated on every row; `NA` when SPC recorded 0 or no
#'     value.}
#'   \item{property_loss_allocated}{`property_loss_tornado_total` times
#'     `area_share_of_tornado` (area-weighted approximation); `NA` when the total
#'     is `NA`.}
#'   \item{ZCTA}{Five-character ZCTA code.}
#'   \item{area_prop_affected}{Swath area inside the ZCTA divided by the ZCTA's
#'     land area, capped at 1.}
#'   \item{pop_affected}{Estimated residents inside the swath within the ZCTA.}
#'   \item{zcta_pop}{Total population of the ZCTA in the boundary year of the tornado's
#'     year.}
#'   \item{pop_prop_affected}{`pop_affected / zcta_pop`; `NA` when `zcta_pop` is 0.}
#'   \item{area_share_of_tornado}{Swath area in the ZCTA divided by the swath area
#'     in all ZCTAs; sums to 1 over a tornado's rows.}
#'   \item{track_type}{SPC track type of the tornado (`"line"` for every tornado in
#'     this layer).}
#'   \item{path_source}{Always `"nws_survey"`.}
#'   \item{survey_line_id}{`objectid` of the survey line in layer 1 of the Damage
#'     Assessment Toolkit service at the time of the snapshot.}
#'   \item{survey_event_id}{`event_id` of the survey line (missing or empty for
#'     some lines).}
#' }
#'
#' @source NOAA National Weather Service Damage Assessment Toolkit (see
#'   [get_survey_data()]), matched to SPC tornadoes. Built by
#'   `data-raw/survey/build_survey.R`.
"survey_exposure"

#' NWS survey swaths (sensitivity layer)
#'
#' The surveyed damage swath of each tornado in [survey_exposure], as polygons in
#' EPSG:4326, simplified to 50 m (no point of the outline moves by more than
#' 50 m; `data-raw/known_issues.md` gives the resulting change in area).
#' They are used for plotting (`add_tracks(geometry = "survey")`) and for
#' distances to ZCTA centroids; the exposure columns come from the full-resolution
#' swaths, not from these polygons.
#'
#' @format An sf data frame with `r format(nrow(survey_tracks), big.mark = ",")`
#'   rows and 2 variables: `tornado_id` and `geometry`.
#'
#' @source See [survey_exposure].
"survey_tracks"

#' Match table for the NWS survey layer
#'
#' One row for every SPC tornado since 2007, with a `status` that says whether the
#' tornado was paired with a survey line and has a usable damage swath (and is
#' therefore in [survey_exposure]), and the details of its pairing. The code is in
#' `data-raw/survey/build_survey.R`.
#'
#' @details
#' Each tornado is paired with its closest survey line when that line's closest
#' tornado is also that tornado (see [get_survey_data()]); the distance and the
#' other columns below describe the pair and are not used to filter it.
#'
#' `r paste(readLines("data-raw/survey/status_definitions.md"), collapse = "\n")`
#'
#' @format A data frame with `r format(nrow(survey_matches), big.mark = ",")`
#'   rows (one per SPC tornado since 2007) and `r ncol(survey_matches)` variables.
#'   The columns that describe the pair are `NA` when `status` is `"no_pair"`:
#' \describe{
#'   \item{tornado_id}{SPC tornado identifier.}
#'   \item{status}{`"included"` (`r sum(survey_matches$status == "included")`),
#'     `"no_swath"` (`r sum(survey_matches$status == "no_swath")`) or `"no_pair"`
#'     (`r format(sum(survey_matches$status == "no_pair"), big.mark = ",")`); defined above.}
#'   \item{distance_km}{Distance between the SPC tornado and its survey line, in
#'     kilometers: the mean of the distances between 21 equally spaced points along
#'     the two paths (for an SPC point track, the distance from the point to the
#'     survey line).}
#'   \item{length_ratio}{Survey line length divided by SPC length (`NA` when SPC
#'     gives a length of 0; 0 when the survey line has a length of 0).}
#'   \item{direction_diff_deg}{Difference between the directions of the two
#'     paths, in degrees from 0 to 180 (`NA` for SPC point tracks).}
#'   \item{n_candidates_tornado}{Survey lines dated within 1 day of the tornado
#'     (also given for tornadoes with status `"no_pair"`).}
#'   \item{n_candidates_line}{SPC tornadoes dated within 1 day of the survey line.}
#'   \item{second_distance_tornado_km, second_distance_line_km}{Distance of the
#'     second-closest candidate: the second-closest survey line to the tornado, and
#'     the second-closest tornado to the survey line (`NA` when there is only one
#'     candidate).}
#'   \item{same_state}{Whether the SPC start point lies in the same state as the
#'     start point or the end point of the survey line (state outlines of the 2020
#'     cartographic boundary file).}
#'   \item{survey_line_id}{`objectid` of the survey line in layer 1 of the Damage
#'     Assessment Toolkit service.}
#'   \item{survey_line_ids}{`objectid` of the survey line and of any exact copies
#'     merged with it, comma separated.}
#'   \item{n_duplicate_lines}{Exact copies merged into the survey line.}
#'   \item{survey_event_id, survey_wfo}{`event_id` and National Weather Service
#'     office (`wfo`) of the survey line.}
#'   \item{n_polygons_raw}{Damage polygons crossing the surveyed centerline on the
#'     same date (within one day).}
#'   \item{n_polygons_used}{Rated polygons kept by the swath filter.}
#'   \item{swath_cover}{Share of the length of the surveyed centerline that lies
#'     within 200 m of the swath (0 to 1; `NA` when no polygon is kept).}
#'   \item{swath_km2}{Swath area in square kilometers.}
#' }
#'
#' @source See [survey_exposure].
"survey_matches"
