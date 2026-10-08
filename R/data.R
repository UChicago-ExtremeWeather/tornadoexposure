#' Tornado exposure by ZCTA
#'
#' One row per tornado and ZCTA for every tornado of magnitude EF1 or greater in
#' the United States from `r min(tornado_exposure$year)` to
#' `r max(tornado_exposure$year)`: `r format(nrow(tornado_exposure), big.mark = ",")`
#' rows covering `r format(length(unique(tornado_exposure$tornado_id)), big.mark = ",")`
#' tornadoes. A tornado appears once for each ZCTA its path polygon overlaps.
#' EF0 tornadoes are not included.
#'
#' @details
#' **Path polygons.** Each tornado's path is a polygon built from the SPC track
#' and width (see `.path_polygon()` in the package source): a line track is
#' buffered by half the width with flat end caps. A tornado with an unknown or
#' zero-length track is a point track; because the direction is unknown, its
#' polygon is a disc centered on the start point (area equal to length times
#' width when the length is above 0, otherwise radius equal to half the width).
#' All areas are computed in an equal-area CRS (EPSG:5070). SPC reports the
#' maximum path width, applied here along the whole track, so every area and
#' proportion derived from a path is an upper-bound estimate. Point tracks are
#' approximations (direction unknown); exclude `track_type != "line"` as a
#' sensitivity check.
#'
#' **ZCTA vintage.** Tornadoes are intersected with Census ZCTA boundaries for
#' the matching vintage: the 2000 file for years before 2010, the 2010 file for
#' 2010 to 2019, and the 2020 file from 2020. The same ZCTA code can cover a
#' different area in different vintages, and the 2000 polygons omit large water
#' bodies that the 2010 and 2020 polygons include.
#'
#' **Exposure.** A ZCTA is exposed to a tornado when the path overlaps it
#' (any overlap, including very small touches). Thresholds on
#' `area_prop_affected` are applied to each tornado separately, not
#' cumulatively across tornadoes.
#'
#' **Tornadoes without a ZCTA.** `r nrow(tornado_tracks) - length(unique(tornado_exposure$tornado_id))`
#' tornadoes intersect no ZCTA of their vintage (for example paths over water
#' or uninhabited areas that the Census omits). They are in [tornado_tracks]
#' but not in this dataset, and their property loss is not allocated.
#'
#' **Property loss.** `property_loss_tornado_total` is the SPC `loss` value for
#' the whole tornado, repeated on every row of that tornado; do not sum it
#' across rows. `property_loss_allocated` splits it across ZCTAs in proportion
#' to `area_share_of_tornado`, so summing it over a tornado's rows recovers the
#' tornado total. This is an area-weighted approximation that assumes damage is
#' spread evenly over the path; it misattributes loss when a tornado crosses a
#' sparsely settled ZCTA for most of its length but hits a dense one briefly.
#' **Units caveat:** NOAA documents `loss` as millions of dollars from 1996, and
#' says 0 does not mean $0, but the data contain mixed values (some consistent
#' with millions and some with whole dollars, especially before 2016). The
#' values are carried as reported and not harmonized, so do not sum losses
#' across tornadoes without checking units.
#'
#' **Injuries and fatalities** are tornado-level totals attributed to every ZCTA
#' the tornado touched (they are not allocated), so do not sum them across the
#' rows of one tornado.
#'
#' **Positional precision.** SPC coordinates have two decimal places (about 1 km)
#' before 2007 and four decimal places (about 10 m) from 2007, so paths of short
#' tornadoes, and their ZCTA membership, are uncertain, especially before 2007.
#'
#' @format A data frame with `r format(nrow(tornado_exposure), big.mark = ",")`
#'   rows and `r ncol(tornado_exposure)` variables:
#' \describe{
#'   \item{tornado_id}{Tornado identifier made from the SPC year and `om`
#'     columns (for example `"2011_1105221634-01"`). The two distinct 2001
#'     tornadoes that share `2001_56` are suffixed `_1` and `_2`.}
#'   \item{date}{Date of the tornado.}
#'   \item{year, month, day}{Year, month and day of the tornado.}
#'   \item{magnitude}{(Enhanced) Fujita scale rating, 1 to 5.}
#'   \item{total_injury}{Injuries from the whole tornado (tornado-level total,
#'     repeated on every row of the tornado).}
#'   \item{total_fatality}{Fatalities from the whole tornado (tornado-level
#'     total, repeated on every row of the tornado).}
#'   \item{property_loss_tornado_total}{SPC property loss for the whole tornado,
#'     as reported (repeated on every row of the tornado; units caveat above).}
#'   \item{property_loss_allocated}{`property_loss_tornado_total` times
#'     `area_share_of_tornado` (area-weighted approximation; units caveat
#'     above).}
#'   \item{ZCTA}{Five-character ZCTA code as a string, with leading zeros.}
#'   \item{area_prop_affected}{Area of the path inside the ZCTA divided by the
#'     ZCTA's land area (`ALAND`), as a proportion from 0 to 1. Capped at 1
#'     because `ALAND` excludes water while the ZCTA polygon includes it.
#'     Upper-bound estimate. Used by `area_thresh`.}
#'   \item{area_share_of_tornado}{Area of the path inside the ZCTA divided by
#'     the sum of that tornado's areas across all ZCTAs it crossed. Shares sum
#'     to 1 over a tornado's rows. This is a different denominator from
#'     `area_prop_affected`.}
#'   \item{track_type}{`"line"`, `"point_equal_area"` (point track with a
#'     reported length) or `"point_half_width"` (point track with length 0).}
#' }
#'
#' @source NOAA Storm Prediction Center severe weather database
#'   (<https://www.spc.noaa.gov/wcm/data/1950-2025_all_tornadoes.csv>) and
#'   Census Bureau ZCTA boundaries (2000, 2010 and 2020 vintages) via tigris.
#'   Built by `data-raw/process_tracks.R`.
#'
#' @references
#' NOAA Storm Prediction Center. Severe Weather Database.
#' <https://www.spc.noaa.gov/wcm/> (accessed 2026-10-08).
"tornado_exposure"

#' Tornado tracks
#'
#' One row per tornado (EF1 or greater, 1996 onward), with the reported track
#' geometry. Use it to map tornado tracks; join to [tornado_exposure] on
#' `tornado_id` to get exposures. It includes tornadoes that intersect no ZCTA,
#' so it has more rows than `tornado_exposure` has tornadoes.
#'
#' @details
#' Geometry is a LINESTRING from the SPC start to end coordinates for line
#' tracks, and a POINT at the start coordinate for point tracks (unknown end, or
#' end equal to start), in EPSG:4326. Track coordinates are trusted as reported.
#' SPC coordinates have two decimal places (about 1 km) before 2007 and four
#' (about 10 m) from 2007, so positions of short tracks are uncertain.
#'
#' `len_ratio` compares the straight start-to-end distance with the reported
#' length. Small departures from 1 are expected because length is entered in
#' tenths of a mile before 2007 and coordinates are rounded; most line tracks
#' are within 10% of 1. Only values far from 1 suggest an inconsistency
#' between coordinates and length (about 3.8% of line tracks are above 1.5,
#' mostly before 2007). The coordinates are used for the geometry regardless.
#'
#' `tornado_area_m2` is the area of the path polygon (see [tornado_exposure])
#' and is an upper-bound estimate because SPC reports the maximum width.
#'
#' @format An sf data frame with `r format(nrow(tornado_tracks), big.mark = ",")`
#'   rows and `r ncol(tornado_tracks)` variables:
#' \describe{
#'   \item{tornado_id}{Tornado identifier, as in [tornado_exposure].}
#'   \item{track_type}{`"line"`, `"point_equal_area"` or `"point_half_width"`.
#'     Point tracks are approximations because the direction is unknown.}
#'   \item{width_imputed}{`TRUE` when SPC width was 0 and 10 yards (the
#'     documented minimum) was used.}
#'   \item{len_mi}{Path length in miles as reported by SPC.}
#'   \item{wid_yd}{Path width in yards as used (after imputation).}
#'   \item{len_ratio}{Straight start-to-end distance divided by `len_mi`
#'     (`NA` for point tracks).}
#'   \item{tornado_area_m2}{Area of the path polygon in square meters
#'     (upper-bound estimate).}
#'   \item{geometry}{Track geometry in EPSG:4326.}
#' }
#'
#' @source NOAA Storm Prediction Center severe weather database
#'   (<https://www.spc.noaa.gov/wcm/data/1950-2025_all_tornadoes.csv>).
#'   Built by `data-raw/process_tracks.R`.
"tornado_tracks"
