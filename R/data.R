#' Tornado exposure by ZCTA
#'
#' One row per tornado and ZCTA that either source exposes, for the tornadoes of the United States from
#' `r min(tornado_exposure$year)` to `r max(tornado_exposure$year)`:
#' `r format(nrow(tornado_exposure), big.mark = ",")` rows covering
#' `r format(length(unique(tornado_exposure$tornado_id)), big.mark = ",")`
#' tornadoes. A ZCTA (ZIP Code Tabulation Area) is the Census Bureau's approximation of a ZIP code
#' area. A row exists when
#' * the SPC line crosses the ZCTA (`spc_exposed` is `TRUE`; `r format(sum(tornado_exposure$spc_exposed), big.mark = ",")` rows). A tornado with no usable end point is a point at
#'   its start (see [tornado_tracks]); it is exposed in the ZCTA that contains the start point, and has no SPC row when the start point lies in no ZCTA; or
#' * a damage polygon of a linked NWS damage-survey line covers some land in the ZCTA (`dat_exposed` is `TRUE`; `r format(sum(tornado_exposure$dat_exposed, na.rm = TRUE), big.mark = ",")` rows).
#'   `r format(sum(!tornado_exposure$spc_exposed), big.mark = ",")` rows are exposed only by the NWS polygons: `spc_exposed` is `FALSE` and the SPC columns are `NA` except the distances.
#'
#' All ratings are included, EF0 to EF5 and unknown (see `magnitude`).
#'
#' @details
#' **What the package draws.** SPC provides a start point, an end point and a width. The package draws only the straight line between the start and
#' end points (straight in EPSG:5070) and builds no polygon from the width. The NWS damage polygons are the NWS's own survey shapes ([dat_polygons]).
#'
#' **SPC columns.** `line_km_in_zcta` is the length of the line inside the ZCTA in kilometers (`NA` for a point tornado): the share of the line in the ZCTA, measured in EPSG:5070,
#' times the length of the whole line (`line_km` in [tornado_tracks], measured on the sphere). `line_share_of_tornado` is the length of the line in the ZCTA divided by
#' the length of the line inside all the ZCTAs it reaches, so it sums to 1 over the SPC rows of a tornado (it is 1 for a point tornado). The kilometers of the line outside every ZCTA are
#' `line_km_outside_zcta` in [tornado_tracks]. The line is exposed, not the damage: nothing here says where along the line damage occurred.
#'
#' **Property loss.** `property_loss_tornado_total` is the SPC `loss` for the whole tornado in nominal dollars (repeated on every row of the tornado; do not sum it across rows),
#' and `property_loss_allocated` is that total times `line_share_of_tornado`, so a tornado's allocated values sum to its total over its SPC rows. It assumes that damage is spread
#' evenly along the line, so it is an estimate, not a measurement. It is `NA` where the total is `NA` (SPC recorded 0 or no value, which NOAA says does not mean $0) and on rows
#' that only the NWS polygons expose. SPC loss is incomplete even for the deadliest tornadoes: the Mayfield, Kentucky tornado of December 2021
#' (`r tornado_tracks$total_fatality[tornado_tracks$tornado_id == "2021_2112102054-01"]`
#' deaths) has a loss of
#' `r format(tornado_tracks$property_loss_tornado_total[tornado_tracks$tornado_id == "2021_2112102054-01"], big.mark = ",")`
#' dollars, and `r sum(is.na(tornado_tracks$property_loss_tornado_total) & !is.na(tornado_tracks$magnitude) & tornado_tracks$magnitude >= 4 & as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2007)`
#' of the `r sum(!is.na(tornado_tracks$magnitude) & tornado_tracks$magnitude >= 4 & as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2007)`
#' EF4 and EF5 tornadoes since 2007 have no loss recorded. SPC reports loss in millions of dollars through 2006 (converted here without rounding beyond floating-point error); the raw value and its unit
#' are in [tornado_tracks] (`loss_raw`, `loss_raw_unit`).
#'
#' **DAT columns.** They describe the damage polygons of the NWS damage-survey lines linked to the tornado ([tornado_dat_link]) and are `NA` for a tornado with no linked line
#' (`dat_linked` is `FALSE`). A polygon belongs to a tornado when a linked line touches it (`line_share_in_polygon` above 0 in [dat_polygon_line_link]: a zero test, not a cutoff). Only polygons
#' rated EF0 to EF5 are used; polygons with another `efscale` stay in [dat_polygons] and are counted in `data-raw/known_issues.md`. Polygons with no date are never linked and are not used.
#' The polygons of different ratings overlap, so for each tornado every part of the footprint is given the highest rating that covers it; `dat_area_share_ef0` to `dat_area_share_ef5` are the land shares
#' whose highest rated polygon has that rating, and they sum to `dat_area_share`, the share of the ZCTA's land covered by the union of the tornado's polygons (each area counted once).
#' `dat_pop_ef0` to `dat_pop_ef5` and `dat_pop_affected` are the same in residents. For a linked tornado the columns are 0 where no polygon covers land in the ZCTA.
#'
#' **Land-only shares.** Areas are land-only: the ZCTA polygon minus the Census water polygons (TIGER/Line AREAWATER) inside it (`zcta_land_shape_area_m2`; `data-raw/known_issues.md` compares it with the Census land area
#' `zcta_land_area_m2`). Shares are at most 1 and are never capped. Residents are allocated from census blocks: each block's population times the share of the block's land-only shape covered
#' (uniform density on the land of a block), assigned to the ZCTA that contains the block's internal point. Population is fixed at the census of the boundary year (below).
#'
#' **Damage points.** `dat_points_ef0` to `dat_points_ef5`, `dat_points_efu`, `dat_points_wind` and `dat_points_other` count the NWS damage points ([dat_points]) that lie in the ZCTA and are dated within one day of the
#' tornado (UTC date of the point against the tornado's date), by `efscale` as entered: `EF0` to `EF5`, `EFU`, `TSTM/Wind`, and every other value or none. Points are not linked to tornadoes by any rule, so
#' a point can belong to another tornado of the same day: `other_tornadoes_in_zcta_within_a_day` is the number of other SPC tornadoes whose line crosses the ZCTA within one day of this tornado. Points are counted only
#' in the ZCTAs that have a row for the tornado.
#'
#' **Census boundary year.** The Census Bureau publishes ZCTA boundaries
#' for the 2000, 2010 and 2020 censuses; each set of boundaries is called a Census boundary year here.
#' Tornadoes are intersected with the full TIGER/Line boundaries that match
#' their year: the 2000 file for years before 2010, the 2010 file for 2010 to
#' 2019, and the 2020 file from 2020. The same ZCTA code can cover a different
#' area in different boundary years, and the 2000 polygons omit large water bodies
#' that the 2010 and 2020 polygons include (`data-raw/known_issues.md` gives the
#' counts). `zcta_pop` and the residents use the census of the boundary year (total population, all ages), and 2020 block counts have disclosure-avoidance noise added by the Census Bureau, which is larger for small areas.
#'
#' **Distances.** `boundary_dist_km` is the distance from the SPC line (the start point for a point tornado) to the ZCTA boundary of the boundary year: 0 exactly where `spc_exposed` is `TRUE`.
#' `centroid_dist_km` is the distance from the same line or point to the population-weighted centroid of the ZCTA ([zcta_centroids]). Both are in kilometers and are given for every row.
#' A row with a positive distance is a ZCTA that the line does not cross; it is in the table because a linked NWS polygon covers land in it
#' (`r format(sum(tornado_exposure$boundary_dist_km > 0), big.mark = ",")` rows). For other ZCTAs use `get_data(centroid_dist_km = ...)` or `get_data(boundary_dist_km = ...)`.
#'
#' **Tornadoes without a ZCTA.**
#' `r nrow(tornado_tracks) - length(unique(tornado_exposure$tornado_id))`
#' tornadoes have no row (their line crosses no ZCTA of their boundary year, or their start point lies in none, and no NWS polygon covers land in a ZCTA). They are in [tornado_tracks]
#' but not in this dataset, and their property loss is not allocated (`data-raw/known_issues.md` gives the counts).
#'
#' **Injuries and fatalities** are tornado-level totals attributed to every ZCTA of the tornado (they are not allocated), so do not sum them across the rows of one tornado.
#'
#' **Coordinate rounding.** Coordinates for 1996 to 2006 are given by SPC to 0.01
#' degrees, which is about 1.1 km of latitude, so a coordinate can be off by up
#' to 0.005 degrees (about 0.55 km). Coordinates from 2007 onward are given to
#' 0.0001 degrees (about 11 m). Paths of short tornadoes, and their ZCTA
#' membership near ZCTA boundaries, are therefore less certain before 2007: in a
#' simulation that moves each coordinate by up to half its rounding step,
#' `data-raw/known_issues.md` (section Coordinates) gives the share of tornadoes
#' whose set of ZCTAs changes in each period. A sensitivity analysis restricted
#' to 2007 onward is recommended. No column flags the coarse coordinates; filter
#' on `year`. The package does not round, snap or move any coordinate.
#'
#' **Identifiers.** `tornado_id` is unique within a package version but is not
#' stable across SPC releases for 2007 onward: SPC changed its `om` numbering
#' between its 2024 and 2025 releases and also revises coordinates. To link
#' records across package versions, join on `ZCTA` and `date`.
#'
#' @format A data frame with `r format(nrow(tornado_exposure), big.mark = ",")`
#'   rows and `r ncol(tornado_exposure)` variables:
#' \describe{
#'   \item{tornado_id}{Tornado identifier made from the SPC year and `om`
#'     columns (for example `"2011_1105221634-01"`: the year, then SPC's record
#'     number for the tornado). Distinct tornadoes that
#'     share a year and `om` in SPC are suffixed `_1` and `_2`.}
#'   \item{date}{Date of the tornado.}
#'   \item{year, month, day}{Year, month and day of the tornado.}
#'   \item{magnitude}{EF rating from 0 to 5 (the Enhanced Fujita scale from 2007; the
#'     original Fujita scale before 2007), or `NA` when SPC records the rating as unknown.
#'     `r local({ y <- as.integer(format(tornado_tracks$date, "%Y")); u <- tapply(is.na(tornado_tracks$magnitude), y, sum); q <- 100 * u / table(y); yy <- as.integer(names(u)); stopifnot(all(u[yy <= 2006] == 0), all(u[yy %in% 2008:2015] == 0), all(u[yy >= 2016] > 0)); paste0("There are no unknown ratings in 1996 to 2006, ", u[["2007"]], " in 2007, none in 2008 to 2015, and some in every year from 2016 to 2025 (", min(u[yy >= 2016]), " to ", max(u[yy >= 2016]), " tornadoes a year, ", sprintf("%.1f", min(q[yy >= 2016])), "% to ", sprintf("%.1f", max(q[yy >= 2016])), "% of the year).") })`
#'     Counts of EF0 tornadoes are comparable across years only if unknown ratings are
#'     included, and this matters from 2016 on (see `data-raw/known_issues.md`
#'     for the counts by year).}
#'   \item{total_injury}{Injuries from the whole tornado (tornado-level total,
#'     repeated on every row of the tornado).}
#'   \item{total_fatality}{Fatalities from the whole tornado (tornado-level
#'     total, repeated on every row of the tornado).}
#'   \item{property_loss_tornado_total}{SPC property loss for the whole tornado
#'     in nominal dollars, repeated on every row of the tornado; `NA` when SPC
#'     recorded 0 or no value (see Property loss).}
#'   \item{track_type}{`"line"` or `"point"` (see [tornado_tracks]).}
#'   \item{ZCTA}{Five-character ZCTA code as a string, with leading zeros.}
#'   \item{spc_exposed}{`TRUE` when the SPC line crosses the ZCTA (the start point lies in it, for a point tornado); `FALSE` for a ZCTA that only the NWS polygons expose.}
#'   \item{line_km_in_zcta}{Kilometers of the SPC line inside the ZCTA; `NA` for a point tornado and for a ZCTA the line does not cross (`NA` on rows with `spc_exposed` `FALSE` in this dataset).}
#'   \item{line_share_of_tornado}{Length of the line in the ZCTA divided by the length of the line in all the ZCTAs it reaches (sums to 1 over a tornado's SPC rows; 1 for a point tornado); `NA` where `spc_exposed` is `FALSE`.}
#'   \item{property_loss_allocated}{`property_loss_tornado_total` times `line_share_of_tornado`; `NA` where either is `NA`.}
#'   \item{centroid_dist_km}{Distance in kilometers from the SPC line (or start point) to the population-weighted centroid of the ZCTA.}
#'   \item{boundary_dist_km}{Distance in kilometers from the SPC line (or start point) to the ZCTA boundary; 0 exactly where `spc_exposed` is `TRUE`.}
#'   \item{zcta_pop}{Total population of the ZCTA in the boundary year used for the tornado's year (sum of its blocks' populations).}
#'   \item{zcta_land_area_m2}{Census land area (`ALAND`) of the ZCTA in the boundary year, in square meters.}
#'   \item{zcta_polygon_area_m2}{Area of the full TIGER/Line ZCTA polygon of the boundary year, in square meters (EPSG:5070).}
#'   \item{zcta_land_shape_area_m2}{Area of the land-only shape of the ZCTA (the polygon minus the Census water polygons inside it), in square meters (EPSG:5070); the denominator of the DAT area shares.}
#'   \item{dat_linked}{`TRUE` when the tornado has at least one linked DAT line ([tornado_dat_link]).}
#'   \item{dat_line_ids}{`objectid` of the linked lines in [dat_lines], separated by `;`; `NA` without a link.}
#'   \item{dat_link_dist_km}{The largest one-sided distance (km) among the tornado's linked DAT lines, `one_sided_dist_km` of [tornado_dat_link]; `NA` exactly where `dat_linked` is `FALSE`. The value for each line is in [tornado_dat_link]. No cutoff is applied: filter on this and on `boundary_dist_km` for your purpose.}
#'   \item{dat_exposed}{`TRUE` when a linked NWS polygon covers some land in the ZCTA; `NA` for a tornado with no link.}
#'   \item{dat_area_share}{Share of the ZCTA's land-only area covered by the union of the tornado's linked NWS polygons (EF0 to EF5), each area counted once; `NA` without a link.}
#'   \item{dat_area_share_ef0, dat_area_share_ef1, dat_area_share_ef2, dat_area_share_ef3, dat_area_share_ef4, dat_area_share_ef5}{The part of `dat_area_share` whose highest rated linked polygon has that rating. They sum to `dat_area_share`.}
#'   \item{dat_pop_affected}{Residents in the covered land of the ZCTA (a count, not rounded); `NA` without a link.}
#'   \item{dat_pop_ef0, dat_pop_ef1, dat_pop_ef2, dat_pop_ef3, dat_pop_ef4, dat_pop_ef5}{The part of `dat_pop_affected` by highest rating, as for the area shares.}
#'   \item{dat_points_ef0, dat_points_ef1, dat_points_ef2, dat_points_ef3, dat_points_ef4, dat_points_ef5, dat_points_efu, dat_points_wind, dat_points_other}{Counts of NWS damage points in the ZCTA dated within one day of the tornado, by `efscale` as entered (`EF0` to `EF5`, `EFU`, `TSTM/Wind`, other values and none); `NA` without a link.}
#'   \item{other_tornadoes_in_zcta_within_a_day}{Number of other SPC tornadoes whose line crosses the ZCTA within one day of this tornado; `NA` without a link.}
#' }
#'
#' @source NOAA Storm Prediction Center severe weather database
#'   (<https://www.spc.noaa.gov/wcm/data/1950-`r max(tornado_exposure$year)`_all_tornadoes.csv>),
#'   NOAA National Weather Service Damage Assessment Toolkit, and Census Bureau ZCTA boundaries, water polygons and blocks (2000, 2010 and 2020 boundary years).
#'   The SPC rows are built by `data-raw/process_tracks.R` (full rebuild) and extended year by year by
#'   `data-raw/update_data.R`; the DAT columns and rows by `data-raw/dat/build_dat_exposure.R`.
#'
#' @seealso [tornado_tracks], [spc_records], [get_data()], [dat_exposure_tract]
"tornado_exposure"

#' Tornado tracks
#'
#' One row per tornado (the whole-track record of SPC, `sg == 1`) from
#' `r min(as.integer(substr(tornado_tracks$tornado_id, 1, 4)))` to `r max(as.integer(substr(tornado_tracks$tornado_id, 1, 4)))`,
#' with the track as geometry (EPSG:4326, longitude and latitude) and SPC's values as given.
#' `r format(nrow(tornado_tracks), big.mark = ",")` tornadoes, including the
#' `r nrow(tornado_tracks) - length(unique(tornado_exposure$tornado_id))` that have no row in [tornado_exposure].
#'
#' @details
#' **Tracks with no usable end point.** For
#' `r format(sum(tornado_tracks$track_type == "point"), big.mark = ",")` tornadoes
#' (`r sprintf("%.1f", 100 * mean(tornado_tracks$track_type == "point"))`%) SPC's end coordinates are missing, 0 or equal to the start
#' (`r format(sum(tornado_tracks$track_type == "point" & tornado_tracks$elon == tornado_tracks$slon & tornado_tracks$elat == tornado_tracks$slat), big.mark = ",")` have an end equal
#' to the start), so the direction and extent of the path are unknown. They are drawn as a POINT at the start
#' (`track_type = "point"`), SPC's raw coordinates stay in `slat`, `slon`, `elat` and `elon`, and `line_km` and `line_km_outside_zcta` are `NA`. Most are EF0 and short, but SPC gives a length for nearly all of them and some are long
#' (`data-raw/known_issues.md`, section Tornadoes with no usable end point, gives the counts by rating, length, era and casualties). `get_data()`
#' prints how many such tornadoes a request holds.
#'
#' **Width.** `wid_yd` is SPC's width in yards exactly as given. A width of 0 or missing
#' (`r format(sum(tornado_tracks$wid_yd == 0, na.rm = TRUE), big.mark = ",")` tornadoes) is never replaced. The package does not use the width to draw anything.
#'
#' **Line length.** `line_km` is the length of the straight line from the start to the end point in kilometers, measured on the sphere (the same measure as `len_ratio`); `line_km_outside_zcta` is the part of
#' it that lies in no ZCTA of the tornado's boundary year ([tornado_exposure] gives the part in each ZCTA). Both are `NA` for a point.
#'
#' **Loss.** SPC reports `loss` in millions of dollars through 2006 and in whole dollars from 2007. `loss_raw` and `loss_raw_unit` are SPC's
#' value and its unit; `property_loss_tornado_total` is the loss in dollars (the conversion from millions is exact), `NA` where SPC recorded 0, which NOAA says
#' does not mean $0.
#'
#' @format An sf data frame with `r format(nrow(tornado_tracks), big.mark = ",")` rows and `r ncol(tornado_tracks) - 1` variables plus the geometry:
#' \describe{
#'   \item{tornado_id}{As in [tornado_exposure].}
#'   \item{date}{Date of the tornado.}
#'   \item{magnitude}{EF rating from 0 to 5, `NA` when unknown.}
#'   \item{total_injury, total_fatality}{Injuries and fatalities of the whole tornado, as SPC gives them.}
#'   \item{property_loss_tornado_total}{Loss in dollars, `NA` where SPC recorded 0.}
#'   \item{track_type}{`"line"` (a straight line from SPC's start to its end point) or `"point"` (no usable end point; a POINT at the start).}
#'   \item{len_mi}{SPC's length in miles, as given.}
#'   \item{wid_yd}{SPC's width in yards, as given (0 stays 0).}
#'   \item{slat, slon, elat, elon}{SPC's start and end coordinates, as given.}
#'   \item{len_ratio}{Straight-line length from the start to the end point divided by `len_mi`; `NA` for a point or a length of 0.}
#'   \item{line_km}{Length of the straight line from the start to the end point in kilometers (on the sphere); `NA` for a point.}
#'   \item{line_km_outside_zcta}{Kilometers of the line that lie in no ZCTA of the tornado's boundary year; `NA` for a point.}
#'   \item{loss_raw, loss_raw_unit}{SPC's loss and its unit (`"millions"` or `"dollars"`).}
#' }
#'
#' @source NOAA Storm Prediction Center severe weather database. Built by `data-raw/process_tracks.R`.
#' @seealso [tornado_exposure], [spc_records]
"tornado_tracks"

#' Complete SPC tornado records
#'
#' Every row of the SPC tornado database from 1996 on, with every column as SPC gives it and nothing changed:
#' `r format(nrow(spc_records), big.mark = ",")` rows (whole-track rows with `sg == 1`, state segments and continuing county records) and
#' `r ncol(spc_records) - 1` SPC columns, preceded by the column `tornado_id` (not an SPC column), the identifier of the whole-track row of the same year
#' and `om` (`NA` where several whole-track rows share them or there is none). The time of day is text, as in SPC's file. Column definitions are SPC's
#' (<https://www.spc.noaa.gov/wcm/data/SPC_severe_database_description.pdf>).
#'
#' @format A data frame with `r format(nrow(spc_records), big.mark = ",")` rows and `r ncol(spc_records)` variables: `tornado_id` and the SPC columns
#'   `r paste0("\x60", setdiff(names(spc_records), "tornado_id"), "\x60", collapse = ", ")`.
#'
#' @source NOAA Storm Prediction Center (<https://www.spc.noaa.gov/wcm/#data>); see `data-raw/provenance.txt` for the file, its date and its checksum.
#' @seealso [tornado_tracks]
"spc_records"

#' Population-weighted ZCTA centroids
#'
#' One population-weighted centroid for each ZCTA and Census boundary year (2000, 2010 and 2020):
#' `r format(nrow(zcta_centroids), big.mark = ",")` rows. The centroid is the average location of the ZCTA's
#' residents: census block internal points weighted by block population, averaged on the sphere. A ZCTA with no residents uses the geometric centroid of its polygon
#' (`centroid_type = "geometric"`), moved to a point on the polygon if the centroid falls outside it. Used by `get_data(centroid_dist_km = )`.
#' The coordinates are as computed, not rounded.
#'
#' @format A data frame with `r nrow(zcta_centroids)` rows and the variables:
#' \describe{
#'   \item{ZCTA}{Five-character ZCTA code.}
#'   \item{vintage}{Census boundary year of the ZCTA: 2000, 2010 or 2020.}
#'   \item{lon, lat}{Longitude and latitude of the centroid (NAD83, EPSG:4269).}
#'   \item{centroid_type}{`"population"` or `"geometric"`.}
#'   \item{centroid_in_zcta}{Whether the centroid lies inside its own ZCTA polygon.}
#'   \item{zcta_pop}{Total population of the ZCTA: the sum of its blocks.}
#'   \item{zcta_land_area_m2}{Census land area (`ALAND`) in square meters.}
#'   \item{zcta_polygon_area_m2}{Area of the full TIGER/Line polygon in square meters (EPSG:5070).}
#'   \item{zcta_land_shape_area_m2}{Area of the land-only shape (the polygon minus the Census water polygons inside it) in square meters (EPSG:5070).}
#' }
#'
#' @source Census Bureau TIGER/Line tabulation blocks and ZCTA boundaries; PL 94-171 files for 2000 and 2010. Built by `data-raw/add_centroids.R`.
"zcta_centroids"
