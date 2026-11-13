#' Tornado exposure by ZCTA
#'
#' One row per tornado and ZCTA for every tornado in the United States from
#' `r min(tornado_exposure$year)` to `r max(tornado_exposure$year)`:
#' `r format(nrow(tornado_exposure), big.mark = ",")` rows covering
#' `r format(length(unique(tornado_exposure$tornado_id)), big.mark = ",")`
#' tornadoes. A ZCTA (ZIP Code Tabulation Area) is the Census Bureau's approximation of a ZIP code
#' area. A tornado appears once for each ZCTA it touched:
#' * a line track with a positive width touches the ZCTAs that its modeled path polygon overlaps (the straight line between SPC's
#'   start and end points, widened to SPC's width);
#' * a line track with a width of 0 or missing has no polygon; it touches the ZCTAs that a positive length of the line lies in;
#' * a tornado with no usable end point is a point at its start (see [tornado_tracks]); it touches the ZCTA that contains the start point,
#'   and has no row when the start point lies in no ZCTA.
#'
#' All ratings are included, EF0 to EF5 and unknown (see `magnitude`).
#'
#' @details
#' **Modeled columns.** The columns that begin with `modeled_` come from the modeled path polygon: a straight line at SPC's single
#' width. NWS instructions for Storm Data define the path width entered for a tornado as the maximum width over the entire path (or
#' of each segment), SPC compiles its database from Storm Data, and this package treats `wid` as that maximum width
#' (`data-raw/known_issues.md`, section Modeled columns, gives the source and the comparison with the NWS damage polygons). The width is applied along the whole track, so
#' every modeled area and proportion is larger than that of the damage swath, most for long tracks whose width varied: for the
#' tornadoes with a usable NWS damage swath (the damage polygons of the linked survey line; the comparison is defined in `data-raw/known_issues.md`), the modeled path area is a median of
#' `r sprintf("%.2f", .doc_number("modeled_vs_dat_path_area_median"))` times the area of the NWS damage polygons
#' (10th to 90th percentile `r sprintf("%.2f", .doc_number("modeled_vs_dat_path_area_p10"))` to `r sprintf("%.2f", .doc_number("modeled_vs_dat_path_area_p90"))`), the modeled area share of a ZCTA is
#' `r sprintf("%.2f", .doc_number("modeled_vs_dat_area_share_median"))` times the share computed from the NWS polygons (`r sprintf("%.2f", .doc_number("modeled_vs_dat_area_share_p10"))` to `r sprintf("%.2f", .doc_number("modeled_vs_dat_area_share_p90"))`) and
#' the modeled resident share `r sprintf("%.2f", .doc_number("modeled_vs_dat_pop_share_median"))` times (`r sprintf("%.2f", .doc_number("modeled_vs_dat_pop_share_p10"))` to `r sprintf("%.2f", .doc_number("modeled_vs_dat_pop_share_p90"))`). They are noisy for any single
#' tornado and are approximations, not a damage boundary. SPC gives only a start and an end point, so each path is a straight
#' line even though real tornadoes curve (section Modeled columns of `data-raw/known_issues.md`). The modeled columns are `NA` for the
#' tornadoes with no modeled path shape (`track_type = "point"`, and lines with `wid_yd` of 0).
#'
#' **Census boundary year.** The Census Bureau publishes ZCTA boundaries
#' for the 2000, 2010 and 2020 censuses; each set of boundaries is called a Census boundary year here.
#' Tornadoes are intersected with the full TIGER/Line boundaries that match
#' their year: the 2000 file for years before 2010, the 2010 file for 2010 to
#' 2019, and the 2020 file from 2020. The same ZCTA code can cover a different
#' area in different boundary years, and the 2000 polygons omit large water bodies
#' that the 2010 and 2020 polygons include (`data-raw/known_issues.md` gives the
#' counts).
#'
#' **Exposure.** A ZCTA is exposed to a tornado when the tornado touched it
#' (any overlap, including very small touches). Thresholds on
#' `modeled_area_prop` or `modeled_pop_prop` are applied to each tornado
#' separately, not cumulatively across tornadoes. Area share depends on the size of
#' the ZCTA as well as on how the path crossed it; population share follows where
#' residents live.
#'
#' **Area.** `modeled_area_prop` is the modeled intersection divided by the area of the full ZCTA
#' polygon (`zcta_polygon_area_m2`), with the same geometry in numerator and denominator. It is not capped. The Census land area
#' (`ALAND`, `zcta_land_area_m2`) is returned too: the ZCTA polygon includes inland and coastal water that `ALAND` excludes, so the
#' polygon is larger than the land area for ZCTAs with water.
#'
#' **Population.** `modeled_pop_affected` estimates the residents inside the modeled path within
#' the ZCTA. It uses block-level total population (all ages, no age weights)
#' from the census of the ZCTA
#' boundary year: 2000 blocks for years before 2010, 2010 blocks for 2010 to 2019 and
#' 2020 blocks from 2020, so population is fixed at the census year within each
#' decade. Each block's population is allocated to the path by the share of the
#' block's area inside the path (uniform density within a block; block polygons
#' include any water in the block), and blocks are assigned to ZCTAs by their
#' internal points (ZCTAs are built from whole blocks). `zcta_pop` is the sum of the
#' populations of the blocks assigned to the ZCTA and is the denominator of
#' `modeled_pop_prop`, which is `NA` for the
#' `r format(sum(tornado_exposure$zcta_pop == 0 & !is.na(tornado_exposure$modeled_pop_affected)), big.mark = ",")` modeled rows where
#' `zcta_pop` is 0. Two paths that cover the same share of a ZCTA's area can have very different
#' `modeled_pop_prop`: a path through a dense town holds many residents, while one
#' over farmland of the same area holds few. Limitations: the path is the
#' straight-line path with one width applied along the whole track, and 2020 block counts have disclosure-avoidance noise added by
#' the Census Bureau, which is larger for small areas.
#'
#' **Distances.** `boundary_dist_km` is the distance from the SPC line (the start point for a point tornado) to the
#' ZCTA boundary of the boundary year: 0 when the line touches the ZCTA. Every row of this dataset is a ZCTA that the modeled path or
#' the line touched, so the value is 0 except where the polygon, but not the line, reaches the ZCTA
#' (`r format(sum(tornado_exposure$boundary_dist_km > 0), big.mark = ",")` rows). `centroid_dist_km` is the distance from the same line or
#' point to the population-weighted centroid of the ZCTA ([zcta_centroids]). Both are in kilometers. For ZCTAs a tornado did not touch use
#' `get_data(centroid_dist_km = ...)` or `get_data(boundary_dist_km = ...)`.
#'
#' **Tornadoes without a ZCTA.**
#' `r nrow(tornado_tracks) - length(unique(tornado_exposure$tornado_id))`
#' tornadoes touch no ZCTA of their boundary year (paths over water, and areas
#' that the Census does not assign to a ZCTA; `data-raw/known_issues.md` gives
#' the counts). They are in [tornado_tracks]
#' but not in this dataset, and their property loss is not allocated.
#'
#' **Property loss.** `property_loss_tornado_total` is the SPC `loss` for the
#' whole tornado in nominal dollars (repeated on every row of the tornado; do
#' not sum it across rows), and `modeled_property_loss_allocated` splits it across the
#' ZCTAs in proportion to `modeled_area_share_of_tornado`, so a tornado's allocated
#' values sum to its total. It is an estimate, not a measurement: it assumes
#' the damage is spread evenly over the area of the path, so a tornado that
#' crosses a sparsely settled ZCTA for most of its length but hits a dense one
#' briefly has most of its loss assigned to the sparse ZCTA. The total is `NA` when SPC recorded 0 or
#' no value, which NOAA says does not mean $0. SPC loss is incomplete even for
#' the deadliest tornadoes: the Mayfield, Kentucky tornado of December 2021
#' (`r tornado_tracks$total_fatality[tornado_tracks$tornado_id == "2021_2112102054-01"]`
#' deaths) has a loss of
#' `r format(tornado_tracks$property_loss_tornado_total[tornado_tracks$tornado_id == "2021_2112102054-01"], big.mark = ",")`
#' dollars, and `r sum(is.na(tornado_tracks$property_loss_tornado_total) & !is.na(tornado_tracks$magnitude) & tornado_tracks$magnitude >= 4 & as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2007)`
#' of the `r sum(!is.na(tornado_tracks$magnitude) & tornado_tracks$magnitude >= 4 & as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2007)`
#' EF4 and EF5 tornadoes since 2007 have no loss recorded. SPC reports loss in
#' millions of dollars through 2006 (converted here without rounding beyond floating-point error); the raw value and its unit
#' are in [tornado_tracks] (`loss_raw`, `loss_raw_unit`).
#'
#' **Injuries and fatalities** are tornado-level totals attributed to every ZCTA
#' the tornado touched (they are not allocated), so do not sum them across the
#' rows of one tornado.
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
#'   \item{track_type}{`"line"` or `"point"` (see [tornado_tracks]).}
#'   \item{ZCTA}{Five-character ZCTA code as a string, with leading zeros.}
#'   \item{boundary_dist_km}{Distance in kilometers from the SPC line (or start point) to the ZCTA boundary; 0 when the line touches the ZCTA.}
#'   \item{centroid_dist_km}{Distance in kilometers from the SPC line (or start point) to the population-weighted centroid of the ZCTA.}
#'   \item{modeled_intersection_m2}{Area of the modeled path inside the ZCTA, in square meters (EPSG:5070). `NA` when no path shape is modeled.}
#'   \item{modeled_area_prop}{`modeled_intersection_m2 / zcta_polygon_area_m2`, not capped. Used by `area_thresh`.}
#'   \item{modeled_pop_affected}{Estimated residents inside the modeled path within the ZCTA
#'     (a count, not rounded), from block populations allocated by the share of each
#'     block's area inside the path. The `pop_thresh` argument applies to the share
#'     (`modeled_pop_prop`) only; to filter on the count, subset the result, for
#'     example `subset(x, modeled_pop_affected >= n)` with `n` a number of residents of your choice.}
#'   \item{modeled_pop_prop}{`modeled_pop_affected / zcta_pop`, not capped; `NA` when
#'     `zcta_pop` is 0. Used by `pop_thresh`.}
#'   \item{modeled_area_share_of_tornado}{Modeled area inside the ZCTA divided by
#'     the sum of that tornado's modeled areas across all ZCTAs it crossed. Shares sum
#'     to 1 over a tornado's rows. This is a different denominator from
#'     `modeled_area_prop`.}
#'   \item{modeled_property_loss_allocated}{`property_loss_tornado_total` times
#'     `modeled_area_share_of_tornado` (area-weighted approximation); `NA` when the
#'     tornado total or the modeled path is `NA`.}
#'   \item{zcta_polygon_area_m2}{Area of the full TIGER/Line ZCTA polygon of the boundary year, in square meters (EPSG:5070).}
#'   \item{zcta_land_area_m2}{Census land area (`ALAND`) of the ZCTA in the boundary year, in square meters.}
#'   \item{zcta_pop}{Total population of the ZCTA in the boundary year used for the
#'     tornado's year (sum of its blocks' populations).}
#' }
#'
#' @source NOAA Storm Prediction Center severe weather database
#'   (<https://www.spc.noaa.gov/wcm/data/1950-`r max(tornado_exposure$year)`_all_tornadoes.csv>)
#'   and Census Bureau ZCTA boundaries (2000, 2010 and 2020 boundary years) via tigris.
#'   Built by `data-raw/process_tracks.R` (full rebuild) and extended year by year by
#'   `data-raw/update_data.R`; the population columns by `data-raw/add_population.R`.
#'
#' @seealso [tornado_tracks], [spc_records], [get_data()]
"tornado_exposure"

#' Tornado tracks
#'
#' One row per tornado (the whole-track record of SPC, `sg == 1`) from
#' `r min(as.integer(substr(tornado_tracks$tornado_id, 1, 4)))` to `r max(as.integer(substr(tornado_tracks$tornado_id, 1, 4)))`,
#' with the track as geometry (EPSG:4326, longitude and latitude), SPC's values as given, and the modeled path area.
#' `r format(nrow(tornado_tracks), big.mark = ",")` tornadoes, including the
#' `r nrow(tornado_tracks) - length(unique(tornado_exposure$tornado_id))` that touch no ZCTA and are absent from [tornado_exposure].
#'
#' @details
#' **Tracks with no usable end point.** For
#' `r format(sum(tornado_tracks$track_type == "point"), big.mark = ",")` tornadoes
#' (`r sprintf("%.1f", 100 * mean(tornado_tracks$track_type == "point"))`%) SPC's end coordinates are missing, 0 or equal to the start
#' (`r format(sum(tornado_tracks$track_type == "point" & tornado_tracks$elon == tornado_tracks$slon & tornado_tracks$elat == tornado_tracks$slat), big.mark = ",")` have an end equal
#' to the start), so the direction and extent of the path are unknown. They are drawn as a POINT at the start
#' (`track_type = "point"`), SPC's raw coordinates stay in `slat`, `slon`, `elat` and `elon`, and no path shape is modeled for them (`modeled_path_area_m2` is `NA`
#' and the `modeled_*` columns of [tornado_exposure] are `NA`). Most are EF0 and short, but SPC gives a length for nearly all of them and some are long
#' (`data-raw/known_issues.md`, section Tornadoes with no usable end point, gives the counts by rating, length, era and casualties). `get_data()`
#' prints how many such tornadoes a request holds.
#'
#' **Width.** `wid_yd` is SPC's width in yards exactly as given. A width of 0 or missing
#' (`r format(sum(tornado_tracks$wid_yd == 0, na.rm = TRUE), big.mark = ",")` tornadoes, `r format(sum(tornado_tracks$wid_yd == 0 & tornado_tracks$track_type == "line", na.rm = TRUE), big.mark = ",")` of them lines)
#' is never replaced: such a line has no modeled path polygon and its `modeled_*` columns are `NA`.
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
#'   \item{modeled_path_area_m2}{Area of the modeled path polygon in square meters (EPSG:5070); `NA` for a point and for a width of 0.}
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
#' }
#'
#' @source Census Bureau TIGER/Line tabulation blocks and ZCTA boundaries; PL 94-171 files for 2000 and 2010. Built by `data-raw/add_centroids.R`.
"zcta_centroids"
