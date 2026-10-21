#' Tornado exposure by ZCTA
#'
#' One row per tornado and ZCTA for every tornado in the United States from
#' `r min(tornado_exposure$year)` to `r max(tornado_exposure$year)`:
#' `r format(nrow(tornado_exposure), big.mark = ",")` rows covering
#' `r format(length(unique(tornado_exposure$tornado_id)), big.mark = ",")`
#' tornadoes. A tornado appears once for each ZCTA its path polygon overlaps.
#' A ZCTA (ZIP Code Tabulation Area) is the Census Bureau's approximation of a ZIP code
#' area. A path polygon is the straight line between SPC's start and end points
#' widened to SPC's width, or a disc for a tornado with no usable end point.
#' All ratings are included, EF0 to EF5 and unknown (see `magnitude`).
#'
#' @details
#' **Path polygons.** Each tornado's path is a polygon built from the SPC track
#' and width (see `.path_polygon()` in the package source): a line track is
#' buffered by half the width with flat end caps. A tornado with an unknown or
#' zero-length track is a point track; because the direction is unknown, its
#' polygon is a disc centered on the start point (area equal to length times
#' width when the length is above 0, otherwise radius equal to half the width).
#' All areas are computed in an equal-area CRS (EPSG:5070). A point track has
#' `track_type = "point_equal_area"` (SPC gave a length, so the disc has an area
#' equal to length times width) or `"point_half_width"` (the length is 0, so the
#' disc has a radius of half the width). Only the start point is known and the
#' extent of the disc is a stand-in, because the direction is unknown. Point
#' tracks are `r sprintf("%.1f", 100 * mean(tornado_tracks$track_type != "line"))`% of all tornadoes
#' (`r format(sum(tornado_tracks$track_type == "point_equal_area"), big.mark = ",")` with `"point_equal_area"` and
#' `r format(sum(tornado_tracks$track_type == "point_half_width"), big.mark = ",")` with `"point_half_width"`);
#' excluding `track_type != "line"` shows how much they matter.
#'
#' **Width and straight-line limitations.** SPC gives one width in yards for each
#' tornado. NWS instructions for Storm Data define the path width entered for a
#' tornado as the maximum width over the entire path (or of each segment), SPC
#' compiles its database from Storm Data, and this package treats `wid` as that
#' maximum width (`data-raw/known_issues.md`, section Path accuracy, gives the
#' source and two checks that agree). The width is applied along the whole track,
#' so, treating `wid` as the maximum, every area and proportion derived from a
#' path is larger than that of the damage swath, most for long tracks whose
#' width varied. For example, the Joplin tornado
#' (`2011_1105221634-01`) is modeled with a width of
#' `r tornado_tracks$wid_yd[tornado_tracks$tornado_id == "2011_1105221634-01"]`
#' yards across
#' `r tornado_tracks$len_mi[tornado_tracks$tornado_id == "2011_1105221634-01"]`
#' miles, and the Mayfield tornado (`2021_2112102054-01`) with
#' `r tornado_tracks$wid_yd[tornado_tracks$tornado_id == "2021_2112102054-01"]`
#' yards across
#' `r tornado_tracks$len_mi[tornado_tracks$tornado_id == "2021_2112102054-01"]`
#' miles gives a path area of
#' `r round(tornado_tracks$tornado_area_m2[tornado_tracks$tornado_id == "2021_2112102054-01"] / 1e6)`
#' square kilometers. Halving the average width would halve the proportions. For
#' the `r format(sum(survey_matches$status == "included"), big.mark = ",")` tornadoes whose damage swath was surveyed (see [survey_matches]), the
#' modeled path area has a median of
#' `r sprintf("%.2f", median(tornado_tracks$tornado_area_m2[match(survey_matches$tornado_id[survey_matches$status == "included"], tornado_tracks$tornado_id)] / (survey_matches$swath_km2[survey_matches$status == "included"] * 1e6)))`
#' times the surveyed swath area.
#' SPC gives only a start and an end point, so each path is drawn as a straight
#' line even though real tornadoes curve; the modeled path can sit away from
#' the surveyed damage path (see the Path accuracy section of `data-raw/known_issues.md` in the repository for
#' comparisons with NWS surveys).
#'
#' **Census boundary year.** The Census Bureau publishes ZCTA boundaries
#' for the 2000, 2010 and 2020 censuses; each set of boundaries is called a Census boundary year here.
#' Tornadoes are intersected with the boundaries that match
#' their year: the 2000 file for years before 2010, the 2010 file for 2010 to
#' 2019, and the 2020 file from 2020. The same ZCTA code can cover a different
#' area in different boundary years, and the 2000 polygons omit large water bodies
#' that the 2010 and 2020 polygons include (`data-raw/known_issues.md` gives the
#' counts).
#'
#' **Exposure.** A ZCTA is exposed to a tornado when the path overlaps it
#' (any overlap, including very small touches). Thresholds on
#' `area_prop_affected` or `pop_prop_affected` are applied to each tornado
#' separately, not cumulatively across tornadoes. Area share depends on the size of
#' the ZCTA as well as on how the path crossed it; population share follows where
#' residents live.
#'
#' **Population.** `pop_affected` estimates the residents inside the path within
#' the ZCTA. It uses block-level total population (all ages, no age weights)
#' from the census of the ZCTA
#' boundary year: 2000 blocks for years before 2010, 2010 blocks for 2010 to 2019 and
#' 2020 blocks from 2020, so population is fixed at the census year within each
#' decade. Each block's population is allocated to the path by the share of the
#' block's area inside the path (uniform density within a block; block polygons
#' include any water in the block), and blocks are assigned to ZCTAs by their
#' internal points (ZCTAs are built from whole blocks). `zcta_pop` is the sum of the
#' populations of the blocks assigned to the ZCTA and is the denominator of
#' `pop_prop_affected`, which is `NA` for the
#' `r format(sum(tornado_exposure$zcta_pop == 0), big.mark = ",")` rows where
#' `zcta_pop` is 0. Because `zcta_pop` is the weight, the sum of `pop_affected`
#' divided by the sum of `zcta_pop` over any set of ZCTAs equals the
#' `zcta_pop`-weighted average of `pop_prop_affected`, and summing `pop_affected`
#' across tornadoes counts a resident once for each tornado that hit them. Two
#' paths that cover the same share of a ZCTA's land can have very different
#' `pop_prop_affected`: a path through a dense town holds many residents, while one
#' over farmland of the same area holds few. Limitations: the path is the
#' straight-line path with one width applied along the whole track (see the Path accuracy section of `data-raw/known_issues.md` in the repository),
#' and 2020 block counts have disclosure-avoidance noise added by the Census Bureau,
#' which is larger for small areas.
#'
#' **Tornadoes without a ZCTA.**
#' `r nrow(tornado_tracks) - length(unique(tornado_exposure$tornado_id))`
#' tornadoes intersect no ZCTA of their boundary year (paths over water, and areas
#' that the Census does not assign to a ZCTA; `data-raw/known_issues.md` gives
#' the counts). They are in [tornado_tracks]
#' but not in this dataset, and their property loss is not allocated.
#'
#' **Property loss.** `property_loss_tornado_total` is the SPC `loss` for the
#' whole tornado in nominal dollars (repeated on every row of the tornado; do
#' not sum it across rows), and `property_loss_allocated` splits it across the
#' ZCTAs in proportion to `area_share_of_tornado`, so a tornado's allocated
#' values sum to its total. It is an estimate, not a measurement: it assumes
#' the damage is spread evenly over the area of the path, so a tornado that
#' crosses a sparsely settled ZCTA for most of its length but hits a dense one
#' briefly has most of its loss assigned to the sparse ZCTA. Both are `NA` when SPC recorded 0 or
#' no value, which NOAA says does not mean $0. SPC loss is incomplete even for
#' the deadliest tornadoes: the Mayfield, Kentucky tornado of December 2021
#' (`r tornado_tracks$total_fatality[tornado_tracks$tornado_id == "2021_2112102054-01"]`
#' deaths) has a loss of
#' `r format(tornado_tracks$property_loss_tornado_total[tornado_tracks$tornado_id == "2021_2112102054-01"], big.mark = ",")`
#' dollars, and `r sum(is.na(tornado_tracks$property_loss_tornado_total) & !is.na(tornado_tracks$magnitude) & tornado_tracks$magnitude >= 4 & as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2007)`
#' of the `r sum(!is.na(tornado_tracks$magnitude) & tornado_tracks$magnitude >= 4 & as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2007)`
#' EF4 and EF5 tornadoes since 2007 have no loss recorded. SPC reports loss in
#' millions of dollars through 2006 (converted here); the raw value and its unit
#' are in [tornado_tracks] (`loss_raw`, `loss_raw_unit`).
#'
#' **Injuries and fatalities** are tornado-level totals attributed to every ZCTA
#' the tornado touched (they are not allocated), so do not sum them across the
#' rows of one tornado.
#'
#' **Coordinate rounding.** Coordinates for 1996 to 2006 are rounded to 0.01
#' degrees, which is about 1.1 km of latitude, so a coordinate can be off by up
#' to 0.005 degrees (about 0.55 km). Coordinates from 2007 onward are rounded to
#' 0.0001 degrees (about 11 m). Paths of short tornadoes, and their ZCTA
#' membership near ZCTA boundaries, are therefore less certain before 2007: in a
#' simulation that moves each coordinate by up to half its rounding step,
#' `data-raw/known_issues.md` (section Coordinates) gives the share of tornadoes
#' whose set of ZCTAs changes in each period. A sensitivity analysis restricted
#' to 2007 onward is recommended. No column flags the coarse coordinates; filter
#' on `year`.
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
#'     original Fujita scale before 2007), or `NA` when SPC records the rating as unknown. Unknown
#'     ratings first occur in `r format(min(tornado_tracks$date[is.na(tornado_tracks$magnitude)]), "%Y")`
#'     and are more common after, so counts of EF0 tornadoes are not comparable
#'     across years unless unknown ratings are included (see `data-raw/known_issues.md`
#'     for the counts by year).}
#'   \item{total_injury}{Injuries from the whole tornado (tornado-level total,
#'     repeated on every row of the tornado).}
#'   \item{total_fatality}{Fatalities from the whole tornado (tornado-level
#'     total, repeated on every row of the tornado).}
#'   \item{property_loss_tornado_total}{SPC property loss for the whole tornado
#'     in nominal dollars, repeated on every row of the tornado; `NA` when SPC
#'     recorded 0 or no value (see Property loss).}
#'   \item{property_loss_allocated}{`property_loss_tornado_total` times
#'     `area_share_of_tornado` (area-weighted approximation); `NA` when the
#'     tornado total is `NA`.}
#'   \item{ZCTA}{Five-character ZCTA code as a string, with leading zeros.}
#'   \item{area_prop_affected}{Area of the path inside the ZCTA divided by the
#'     ZCTA's land area (`ALAND`), as a proportion from 0 to 1. Capped at 1
#'     because `ALAND` excludes water while the ZCTA polygon includes it.
#'     Larger than the damage swath if `wid` is the maximum width (see Width
#'     and straight-line limitations). Used by `area_thresh`.}
#'   \item{pop_affected}{Estimated residents inside the path within the ZCTA
#'     (a count, not rounded), from block populations allocated by the share of each
#'     block's area inside the path. `get_data()` and `get_survey_data()` return it
#'     in every call. The `pop_thresh` argument applies to the share
#'     (`pop_prop_affected`) only; to filter on the count, subset the result, for
#'     example `subset(x, pop_affected >= n)` with `n` a number of residents of your choice.}
#'   \item{zcta_pop}{Total population of the ZCTA in the boundary year used for the
#'     tornado's year (sum of its blocks' populations).}
#'   \item{pop_prop_affected}{`pop_affected / zcta_pop`, from 0 to 1; `NA` when
#'     `zcta_pop` is 0. Used by `pop_thresh`.}
#'   \item{area_share_of_tornado}{Area of the path inside the ZCTA divided by
#'     the sum of that tornado's areas across all ZCTAs it crossed. Shares sum
#'     to 1 over a tornado's rows. This is a different denominator from
#'     `area_prop_affected`.}
#'   \item{track_type}{`"line"`, `"point_equal_area"` (point track with a
#'     reported length) or `"point_half_width"` (point track with length 0).}
#' }
#'
#' @source NOAA Storm Prediction Center severe weather database
#'   (<https://www.spc.noaa.gov/wcm/data/1950-`r max(tornado_exposure$year)`_all_tornadoes.csv>)
#'   and Census Bureau ZCTA boundaries (2000, 2010 and 2020 boundary years) via tigris.
#'   Built by `data-raw/process_tracks.R` (full rebuild) and extended year by year by
#'   `data-raw/update_data.R`.
#'
#' @references
#' NOAA Storm Prediction Center. Severe Weather Database.
#' <https://www.spc.noaa.gov/wcm/> (accessed `r readLines("data-raw/access_date.txt")`).
"tornado_exposure"

#' Tornado tracks
#'
#' One row per tornado (all ratings, 1996 onward), with the reported track
#' geometry. Use it to map tornado tracks; join to [tornado_exposure] on
#' `tornado_id` to get exposures. It includes tornadoes that intersect no ZCTA,
#' so it has more rows than `tornado_exposure` has tornadoes.
#'
#' @details
#' Geometry is a LINESTRING from the SPC start to end coordinates for line
#' tracks, and a POINT at the start coordinate for point tracks (unknown end, or
#' end equal to start), in EPSG:4326. Track coordinates are trusted as reported.
#' Coordinates for 1996 to 2006 are rounded to 0.01 degrees (about 1.1 km of
#' latitude, so a coordinate can be off by up to about 0.55 km); coordinates from
#' 2007 onward are rounded to 0.0001 degrees (about 11 m). Positions of
#' short tracks are therefore uncertain before 2007. No column flags this;
#' filter on the year in `tornado_id` or join to [tornado_exposure].
#'
#' `len_ratio` compares the straight start-to-end distance with the reported
#' length. Small departures from 1 are expected: length is entered in tenths of
#' a mile before 2007, coordinates are rounded, and real paths curve. Only
#' values far from 1 suggest an inconsistency between coordinates and length
#' (`r round(100 * mean(tornado_tracks$len_ratio > 1.5, na.rm = TRUE), 1)`% of
#' line tracks are above 1.5, against
#' `r round(100 * mean(tornado_tracks$len_ratio[as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2007] > 1.5, na.rm = TRUE), 1)`% from 2007 and
#' `r round(100 * mean(tornado_tracks$len_ratio[as.integer(substr(tornado_tracks$tornado_id, 1, 4)) <= 2006] > 1.5, na.rm = TRUE), 1)`% before). From 2007 the reported length is close to the
#' straight-line distance, which suggests that it is computed from the
#' coordinates, so `len_ratio` cannot independently validate modern
#' coordinates. The coordinates are used for the geometry regardless.
#'
#' `tornado_area_m2` is the area of the path polygon (see [tornado_exposure])
#' and is larger than the damage swath if SPC's width is the maximum width of the
#' path (see [tornado_exposure]).
#'
#' The tornado-level attributes (`date`, `magnitude`, `total_injury`,
#' `total_fatality`, `property_loss_tornado_total`) are the same values as in
#' [tornado_exposure]. They are repeated here because distance exposure (the
#' `centroid_dist_km` argument) can return tornadoes that overlap no ZCTA, and
#' those have no row in `tornado_exposure`. Injuries and fatalities are
#' tornado-level totals. Property loss is in nominal dollars, `NA` when SPC
#' recorded 0 or no value (which NOAA says does not mean $0); the raw SPC value
#' is kept as `loss_raw` with its unit in `loss_raw_unit`.
#'
#' @format An sf data frame with `r format(nrow(tornado_tracks), big.mark = ",")`
#'   rows and `r ncol(tornado_tracks)` variables:
#' \describe{
#'   \item{tornado_id}{Tornado identifier, as in [tornado_exposure].}
#'   \item{date}{Date of the tornado.}
#'   \item{magnitude}{Rating from 0 to 5, or `NA` when unknown (as in
#'     [tornado_exposure]).}
#'   \item{total_injury, total_fatality}{Injuries and fatalities from the whole
#'     tornado (tornado-level totals).}
#'   \item{property_loss_tornado_total}{SPC property loss for the whole tornado
#'     in nominal dollars; `NA` when SPC recorded 0 or no value.}
#'   \item{track_type}{`"line"`, `"point_equal_area"` or `"point_half_width"`.
#'     Point tracks are approximations because the direction is unknown.}
#'   \item{width_imputed}{`TRUE` when SPC's width was 0 or missing and 10 yards
#'     was used instead. SPC's older format description assumes a minimum path width
#'     of 30 feet (10 yards); `data-raw/known_issues.md`, section Other fixed
#'     settings, gives the effect of 5 and 20 yards.}
#'   \item{len_mi}{Path length in miles as reported by SPC.}
#'   \item{wid_yd}{Path width in yards as used (after imputation), treated as the
#'     maximum width of the path.}
#'   \item{len_ratio}{Straight start-to-end distance divided by `len_mi`
#'     (`NA` for point tracks).}
#'   \item{tornado_area_m2}{Area of the path polygon in square meters (larger than
#'     the damage swath if `wid_yd` is the maximum width).}
#'   \item{loss_raw}{SPC property loss exactly as reported.}
#'   \item{loss_raw_unit}{`"millions"` (1996 to 2006) or `"dollars"` (2007
#'     onward): the unit of `loss_raw` in the current SPC file.}
#'   \item{geometry}{Track geometry in EPSG:4326.}
#' }
#'
#' @source NOAA Storm Prediction Center severe weather database
#'   (<https://www.spc.noaa.gov/wcm/data/1950-`r max(tornado_exposure$year)`_all_tornadoes.csv>).
#'   Built by `data-raw/process_tracks.R` (full rebuild) and extended year by year by
#'   `data-raw/update_data.R`.
"tornado_tracks"

#' ZCTA centroids for distance exposure
#'
#' One population-weighted centroid per ZCTA and Census boundary year (2000, 2010 and
#' 2020), used when `centroid_dist_km` is given to [get_data()],
#' [map_exposure()] or [add_tracks()]. A ZCTA is then exposed when its centroid
#' lies within that many kilometers of the tornado path.
#'
#' @details
#' The centroid is the mean of the block internal points of the ZCTA's blocks
#' (fields `INTPTLAT` and `INTPTLON` in the Census TIGER/Line block files),
#' weighted by block population and computed on the sphere. Blocks are assigned
#' to ZCTAs through their internal point, as for `zcta_pop`. It therefore sits
#' where residents live, not at the geometric center of the ZCTA, and the two can
#' differ by many kilometers for large ZCTAs (for example in Alaska) where
#' residents are concentrated in one town.
#'
#' ZCTAs with no residents (`r sum(zcta_centroids$centroid_type == "geometric" & zcta_centroids$vintage == 2000)`,
#' `r sum(zcta_centroids$centroid_type == "geometric" & zcta_centroids$vintage == 2010)` and
#' `r sum(zcta_centroids$centroid_type == "geometric" & zcta_centroids$vintage == 2020)` in the 2000, 2010 and 2020 boundary years)
#' use the geometric centroid of the polygon (`centroid_type = "geometric"`), or a point on
#' the polygon surface if the geometric centroid falls outside it. A result that
#' contains such ZCTAs triggers a warning.
#'
#' A population-weighted centroid can fall outside its own polygon when the ZCTA
#' is crescent-shaped or has several parts (`r sum(!zcta_centroids$centroid_in_zcta)` of
#' `r format(nrow(zcta_centroids), big.mark = ",")` ZCTA-boundary-year rows).
#' `centroid_in_zcta` flags them. The centroid is kept where it is, because it
#' is the defined quantity, and the distance to it is used as is.
#'
#' ZCTAs without a polygon in the Census boundary file (see the known issues in
#' `data-raw/known_issues.md` for the 2000 boundary year) have no centroid.
#'
#' @format A data frame with `r format(nrow(zcta_centroids), big.mark = ",")`
#'   rows and `r ncol(zcta_centroids)` variables:
#' \describe{
#'   \item{ZCTA}{Five-character ZCTA code as a string.}
#'   \item{vintage}{Census boundary year (the column is named `vintage`): 2000, 2010 or 2020. Tornadoes of
#'     1996 to 2009 use 2000, 2010 to 2019 use 2010, and 2020 onward use 2020.}
#'   \item{lon, lat}{Centroid longitude and latitude in NAD83 (EPSG:4269),
#'     rounded to 5 decimals (about 1 m).}
#'   \item{centroid_type}{`"population"` or `"geometric"` (no residents).}
#'   \item{centroid_in_zcta}{Whether the centroid lies inside its own ZCTA
#'     polygon.}
#'   \item{zcta_pop}{Total population of the ZCTA in that boundary year (the same
#'     value as `zcta_pop` in [tornado_exposure]); used to fill the population
#'     columns for ZCTAs the path does not overlap.}
#' }
#'
#' @source Census Bureau TIGER/Line tabulation blocks (2000, 2010 and 2020),
#'   2010 and 2000 PL 94-171 redistricting files for block population, and ZCTA
#'   boundaries via tigris. Built by `data-raw/add_centroids.R`.
"zcta_centroids"
