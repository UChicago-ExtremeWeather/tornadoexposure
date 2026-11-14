#' NWS damage surveys: damage points, lines and polygons
#'
#' Every feature that the National Weather Service Damage Assessment Toolkit (DAT) service held when it was queried on
#' `r readLines("data-raw/dat/access_date.txt")`, with every field the service gives, at full resolution, in the service's spatial reference (WGS 84, EPSG:4326),
#' unmodified. Nothing is simplified, generalized, rounded, snapped or filtered: no swath filter, no date filter, no feature dropped (features with
#' no date or an empty geometry are kept).
#' * `dat_points`: damage points surveyed on the ground, `r format(nrow(dat_points), big.mark = ",")` features (the "Damage Points" layer).
#' * `dat_lines`: centerlines of surveyed tornado tracks, `r format(nrow(dat_lines), big.mark = ",")` features (the "Damage Lines" layer).
#' * `dat_polygons`: damage polygons, rated by EF scale, `r format(nrow(dat_polygons), big.mark = ",")` features (the "Damage Polygons" layer); damage polygons of different EF
#'   ratings are nested, so they overlap.
#'
#' @details
#' **Dates.** The service stores dates as milliseconds since 1970-01-01 00:00:00 UTC. Each date field (`stormdate`, `surveydate`, `starttime`, `endtime`,
#' `edit_time`, `created_date`, `last_edited_date`, as the layer has them) is kept as that number, and the column of the same name with the suffix `_utc` is the same instant as
#' a date-time in UTC. The service gives the numbers as text; they are stored as numbers, with the same values. A missing date is `NA`.
#'
#' **Field values are the service's.** Fields such as `efscale` hold whatever the survey teams entered, including values that are not EF ratings (for example `EFU`, `TSTM/Wind`, `N/A`, `UNKNOWN`);
#' `event_id` is free text (`data-raw/known_issues.md` gives how it is filled) and is not a key that links the layers or an NCEI event id.
#'
#' **Status of the data.** The data are preliminary: the stewards describe the dataset as preliminary and as intended for public access and use
#' (<https://disasters-geoplatform.hub.arcgis.com/pages/noaa-damage-assessment-toolkit-dat>). No license text was found, and this package does not claim that the data are in the public domain.
#' The accuracy of the damage polygons has not been measured, positions are the survey teams', and surveys are not available for every tornado:
#' coverage grows from a few tornadoes in 2007 to most tornadoes in 2025 (`data-raw/known_issues.md`).
#'
#' **Linking.** [tornado_dat_link] links the lines to SPC tornadoes and [dat_polygon_line_link] relates the polygons to the lines. Points are not linked to tornadoes by any rule; [tornado_exposure] counts the points that lie in a ZCTA within one day of a tornado.
#'
#' @format An sf data frame in EPSG:4326: `dat_points` has `r ncol(dat_points) - 1` columns plus geometry (POINT), `dat_lines` `r ncol(dat_lines) - 1` (LINESTRING) and `dat_polygons` `r ncol(dat_polygons) - 1` (POLYGON and MULTIPOLYGON).
#'   The fields are those of the service; `objectid` identifies a feature within its layer.
#'   `dat_points`: `r paste0("\x60", setdiff(names(dat_points), "geometry"), "\x60", collapse = ", ")`.
#'   `dat_lines`: `r paste0("\x60", setdiff(names(dat_lines), "geometry"), "\x60", collapse = ", ")`.
#'   `dat_polygons`: `r paste0("\x60", setdiff(names(dat_polygons), "geometry"), "\x60", collapse = ", ")`.
#'   In `dat_lines`, `length` is in miles and `width` in yards.
#'
#' @source NOAA National Weather Service, Damage Assessment Toolkit,
#'   <https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer> (layers 0, 1 and 2), queried on `r readLines("data-raw/dat/access_date.txt")`.
#'   Fetched by `data-raw/dat/fetch_dat.R`, built by `data-raw/dat/build_dat.R`.
#' @name dat_features
#' @aliases dat_points dat_lines dat_polygons
NULL

#' @rdname dat_features
"dat_points"

#' @rdname dat_features
"dat_lines"

#' @rdname dat_features
"dat_polygons"

#' Link between SPC tornadoes and NWS damage-survey lines
#'
#' One row per DAT line ([dat_lines]) that is linked to an SPC tornado ([tornado_tracks]):
#' `r format(nrow(tornado_dat_link), big.mark = ",")` lines linked to `r format(length(unique(tornado_dat_link$tornado_id)), big.mark = ",")` tornadoes
#' (of `r format(nrow(dat_lines), big.mark = ",")` lines). A tornado can have several DAT lines.
#'
#' @details
#' **Candidates.** Every SPC tornado (a line or a point track) and every DAT line that has a date and a geometry, dated within one day of each other (the DAT date
#' is the UTC date of `stormdate`, the SPC date is SPC's local date).
#'
#' **Distances.** Both are in kilometers, computed in EPSG:5070.
#' * `index_aligned_dist_km`: 21 equally spaced points are taken along each path, from the start to the end; the distance is the mean of the 21 distances between corresponding
#'   points, with the DAT line read in the direction that gives the smaller mean. For an SPC point track (no usable end point) it is the distance from the start point to the DAT line.
#' * `one_sided_dist_km`: the mean distance of the DAT line's own 21 points to the SPC straight line (the same distance as above for a point track).
#'
#' **Rule.**
#' * `mutual_closest`: a tornado and a DAT line are linked when each is the other's closest candidate by `index_aligned_dist_km` (a tie is broken by the lower `objectid`).
#' * `attached_to_paired`: a DAT line that is in no mutual-closest pair is attached to its one-sided nearest tornado (by `one_sided_dist_km`) when that tornado already has a
#'   mutual-closest line.
#'
#' No distance limit, no minimum length, no test on length or direction and no flag is used: every number that describes a link is a column, so you can apply your own
#' limits. The St. Louis tornado of 16 May 2025 is one SPC record linked to two DAT lines, the EF3 and the EF1 (`data-raw/known_issues.md`).
#' Lines that are in no row (`r format(sum(!dat_lines$objectid %in% tornado_dat_link$dat_line_id), big.mark = ",")` of the `r format(nrow(dat_lines), big.mark = ",")`) have no mutual-closest or attachable
#' tornado, no date or no geometry, or no SPC tornado within a day: surveys that SPC does not list, surveys before 1996, and surveys of damage without a rated tornado.
#'
#' @format A data frame with the variables:
#' \describe{
#'   \item{tornado_id}{SPC tornado ([tornado_tracks]).}
#'   \item{dat_line_id}{`objectid` of the line in [dat_lines].}
#'   \item{index_aligned_dist_km}{Mean distance of 21 corresponding points, in kilometers.}
#'   \item{one_sided_dist_km}{Mean distance of the DAT line's 21 points to the SPC line, in kilometers.}
#'   \item{length_ratio}{DAT `length` divided by SPC `len_mi`; `NA` where SPC's length is 0.}
#'   \item{direction_diff_deg}{Difference in degrees (0 to 180) between the direction of the DAT line (read in the direction used for the distance) and of the SPC line; `NA` for a point track.}
#'   \item{same_state}{Whether SPC's state of the tornado is the state of the start or the end point of the DAT line (full TIGER/Line state boundaries).}
#'   \item{n_candidates_tornado}{Number of DAT lines within a day of the tornado.}
#'   \item{n_candidates_line}{Number of SPC tornadoes within a day of the DAT line.}
#'   \item{second_dist_tornado_km}{The tornado's second smallest `index_aligned_dist_km` among its candidates (`NA` if it has one candidate).}
#'   \item{second_dist_line_km}{The line's second smallest `index_aligned_dist_km` among its candidates (`NA` if it has one candidate).}
#'   \item{relationship}{`"one_to_one"` (the tornado has one linked line) or `"one_to_many"`.}
#'   \item{rule}{`"mutual_closest"` or `"attached_to_paired"`.}
#' }
#'
#' @source Built by `data-raw/dat/build_dat.R` from [tornado_tracks] and [dat_lines].
#' @seealso [dat_features], [dat_polygon_line_link]
"tornado_dat_link"

#' Relation between NWS damage polygons and damage-survey lines
#'
#' One row per damage polygon ([dat_polygons]) and damage line ([dat_lines]) whose dates are within one day of each other (polygons and lines with a date and a geometry):
#' `r format(nrow(dat_polygon_line_link), big.mark = ",")` rows. It holds numbers only and no cutoff: a polygon that is far from a line is a row with a large distance and a share of 0, so
#' you choose which polygons belong to a line (`line_share_in_polygon > 0` means the line touches the polygon).
#'
#' @format A data frame with the variables:
#' \describe{
#'   \item{dat_polygon_id}{`objectid` of the polygon in [dat_polygons].}
#'   \item{dat_line_id}{`objectid` of the line in [dat_lines].}
#'   \item{dist_km}{Shortest distance between the polygon and the line, in kilometers (EPSG:5070; 0 when they touch).}
#'   \item{line_share_in_polygon}{Length of the line inside the polygon divided by the length of the line (0 to 1; the polygons are repaired with `st_make_valid()` where invalid for this
#'     computation only).}
#' }
#'
#' @source Built by `data-raw/dat/build_dat.R`.
#' @seealso [dat_features], [tornado_dat_link]
"dat_polygon_line_link"

#' NWS damage polygons by tract and block group
#'
#' The NWS damage-survey columns of [tornado_exposure] at two finer Census units: `dat_exposure_tract` has `r format(nrow(dat_exposure_tract), big.mark = ",")` rows (one per tornado and census tract
#' that a linked NWS damage polygon covers land in, `r format(length(unique(dat_exposure_tract$tornado_id)), big.mark = ",")` tornadoes) and `dat_exposure_blockgroup`
#' has `r format(nrow(dat_exposure_blockgroup), big.mark = ",")` rows (block groups, `r format(length(unique(dat_exposure_blockgroup$tornado_id)), big.mark = ",")` tornadoes).
#' There are no SPC columns: SPC's positions (a straight line from a start to an end point, rounded to 0.01 degrees before 2007) are not accurate enough to say which tract or
#' block group a tornado crossed.
#'
#' @details
#' The rules are those of the DAT columns of [tornado_exposure]: a polygon belongs to a tornado when a linked line touches it (`line_share_in_polygon` above 0 in [dat_polygon_line_link]), only polygons rated EF0 to EF5 are
#' used, and every part of the footprint is given the highest rating that covers it, so the `_ef0` to `_ef5` columns sum to the total. Units use the Census boundary year of the tornado's year (2000 before 2010, 2010 for
#' 2010 to 2019, 2020 from 2020), and the unit of a block is read from its GEOID: the first 11 digits are the tract and the first 12 the block group. Areas and residents come from the blocks of the unit: the land-only area of a unit
#' is the sum of the land-only areas of its blocks (each block polygon minus the Census water polygons inside it), the share is the covered land divided by that area, and residents are each block's population
#' times the share of the block's land-only shape covered. The point counts are the NWS damage points inside the unit's blocks dated within one day of the tornado.
#'
#' @format A data frame with the variables:
#' \describe{
#'   \item{tornado_id}{As in [tornado_exposure].}
#'   \item{GEOID}{Census tract (11 characters) or block group (12 characters) code.}
#'   \item{tract_pop, tract_land_area_m2, tract_land_shape_area_m2 (blockgroup_pop, blockgroup_land_area_m2, blockgroup_land_shape_area_m2 in `dat_exposure_blockgroup`)}{Population (sum of the blocks), Census land area (sum of the blocks' `ALAND`) and land-only area (sum of the blocks' land-only shapes, in square meters, EPSG:5070) of the unit.}
#'   \item{dat_area_share, dat_area_share_ef0 to dat_area_share_ef5}{As in [tornado_exposure], for the unit's land-only area.}
#'   \item{dat_pop_affected, dat_pop_ef0 to dat_pop_ef5}{As in [tornado_exposure], in residents.}
#'   \item{dat_points_ef0 to dat_points_ef5, dat_points_efu, dat_points_wind, dat_points_other}{Counts of NWS damage points in the unit dated within one day of the tornado, by `efscale` as entered.}
#' }
#'
#' @source Built by `data-raw/dat/build_dat_exposure.R` from [dat_polygons], [dat_points], [tornado_dat_link], [dat_polygon_line_link] and the Census Bureau TIGER/Line tabulation blocks and water polygons.
#' @seealso [tornado_exposure], [dat_features]
#' @name dat_exposure_units
#' @aliases dat_exposure_tract dat_exposure_blockgroup
NULL

#' @rdname dat_exposure_units
"dat_exposure_tract"

#' @rdname dat_exposure_units
"dat_exposure_blockgroup"
