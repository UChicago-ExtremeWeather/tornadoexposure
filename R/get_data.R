#' Get tornado exposures for a set of ZCTAs
#'
#' Returns one row per tornado and ZCTA for the requested ZCTAs, years and
#' tornado magnitudes. A call uses exactly one exposure definition. By default
#' it returns the rows of [tornado_exposure]: the ZCTAs that either source
#' exposes. A ZCTA is exposed by the SPC when the SPC line crosses it (for a
#' tornado with no usable end point, when the start point lies in it) and by the
#' NWS damage survey when a damage polygon of a linked NWS line covers some land
#' in it. Filter on `spc_exposed` and `dat_exposed` to use one source. With
#' `centroid_dist_km` the ZCTA's population-weighted centroid must lie within that
#' distance of the SPC line, and with `boundary_dist_km` the ZCTA's boundary must.
#'
#' @details
#' **What the package draws.** The SPC provides a start point, an end point and
#' a width. The package uses only the straight line between the start and end
#' points; it draws no polygon from the width. The NWS damage polygons are the
#' NWS's own survey shapes ([dat_polygons]); the columns that begin with `dat_`
#' come from them, for tornadoes linked to an NWS damage-survey line
#' ([tornado_dat_link]). They are `NA` for a tornado with no linked line.
#'
#' **Tornadoes with no usable end point.** SPC's end coordinates are missing, 0 or
#' equal to the start. Such a tornado is a point at its start and is exposed only in
#' the ZCTA that contains the start point (`line_km_in_zcta` is `NA`). A start
#' point inside no ZCTA gives no SPC row. Every call prints how many of the returned
#' tornadoes have no usable end point (see [tornado_tracks]).
#'
#' **Distances.** The distance definitions are measured from the SPC line (the start
#' point for a tornado with no usable end point) and have no upper limit. A row
#' with a positive `boundary_dist_km` is a ZCTA that the line does not cross.
#' The centroid or boundary radius that separates exposure from error in the
#' location of SPC's straight line is not known to the package;
#' `data-raw/known_issues.md` gives the measured offsets between the surveyed
#' centerlines and the SPC line.
#'
#' @param geography Geography of the data. Only `"zcta"` is available; the
#'   argument exists for consistency with sibling exposure packages.
#' @param geo_list Character vector of ZCTAs or ZCTA prefixes (1 to 5 digits),
#'   for example `"648"` or `c("60637", "606")`. Use character strings:
#'   numbers lose leading zeros (02139 becomes 2139), which breaks matching in
#'   the Northeast. A numeric value with fewer than five digits triggers a warning and
#'   is treated as a prefix.
#' @param year_range Years to include, for example `2010:2015`. The data cover
#'   1996 to the latest release year.
#' @param magnitude Vector of magnitudes to include. The default keeps every
#'   rating, EF0 to EF5 and unknown. Use `magnitude = 1:5` for EF1 and above,
#'   or `3:5` for EF3 and above. Tornadoes with an unknown rating have a
#'   magnitude of `NA`; they are kept only if `NA` is in the vector, as in
#'   `magnitude = c(1:5, NA)`. Ratings before 2007 are on the original Fujita
#'   (F) scale.
#' @param centroid_dist_km `NULL` (default) or a positive number of kilometers.
#'   Keeps ZCTAs whose population-weighted centroid (see [zcta_centroids]) lies
#'   within this distance of the SPC line (of the start point for a tornado with no
#'   usable end point), whether or not the line crosses the ZCTA. `0` is an error and
#'   there is no upper limit. The result is not a superset of the exposed set: a large
#'   ZCTA crossed at its edge can have a centroid farther than the radius. For a ZCTA
#'   that neither source exposes, `spc_exposed` is `FALSE`, `line_km_in_zcta` and
#'   `line_share_of_tornado` are 0 (`NA` for a point), the DAT area and resident
#'   columns are 0 for a tornado with a linked line, the point counts are `NA`
#'   (they are tabulated only for exposed ZCTAs), and `boundary_dist_km` is `NA`
#'   (use `boundary_dist_km` to measure it). Large radii across many years and ZCTAs
#'   can be slow, and a message gives a rough time before the work starts.
#'   Cannot be combined with another definition.
#' @param boundary_dist_km `NULL` (default) or a positive number of kilometers.
#'   Keeps ZCTAs whose boundary lies within this distance of the SPC line (of the start
#'   point for a tornado with no usable end point); the distance is 0 when the line
#'   crosses the ZCTA. There is no upper limit. The distance uses the full
#'   TIGER/Line ZCTA boundaries (not the generalized cartographic files), a national
#'   file of about 680 MB (2000 boundaries), 524 MB (2010) or 528 MB (2020) that is
#'   downloaded once and cached; a message says which. Rows for ZCTAs that no source
#'   exposes are filled as described under `centroid_dist_km`. Cannot be combined
#'   with another definition.
#'
#' @return A data frame (no geometry) with one row per tornado-ZCTA pair and
#'   the columns described in [tornado_exposure]. Injury and fatality counts
#'   are tornado-level totals repeated on every ZCTA of the tornado, so do
#'   not sum them across ZCTAs. If nothing matches, an empty data frame with
#'   the same columns is returned and a message explains the request.
#'
#' @examples
#' # Joplin, Missouri, May 2011: ZCTAs starting with 648, EF5 only
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5)
#'
#' # EF1 and above, keeping tornadoes whose rating is unknown
#' get_data(geo_list = "648", year_range = 2011, magnitude = c(1:5, NA))
#'
#' # ZCTAs whose population-weighted centroid is within 10 km of the SPC line
#' # (10 km is an example, not a recommendation)
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5,
#'          centroid_dist_km = 10)
#'
#' @export
get_data <- function(geography = "zcta", geo_list, year_range,
                     magnitude = c(0:5, NA), centroid_dist_km = NULL,
                     boundary_dist_km = NULL) {
  v <- .validate_args(
    "get_data", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(centroid_dist_km = centroid_dist_km,
                      boundary_dist_km = boundary_dist_km)
  )
  .select_exposures(v)
}

# Rows of an exposure-like table that match the geo_list, years and ratings of a validated request
.filter_request_rows <- function(d, v) {
  in_zcta <- Reduce(`|`, lapply(v$geo_list, function(p) startsWith(d$ZCTA, p)))
  d[in_zcta & d$year %in% v$year_range & d$magnitude %in% v$magnitude, , drop = FALSE]
}

# The message about tornadoes that have no usable end point, for the rows returned
.shape_message <- function(out) {
  m <- length(unique(out$tornado_id))
  if (m == 0L) return(invisible())
  tt <- out[!duplicated(out$tornado_id), ]
  n_pt <- sum(tt$track_type == "point")
  if (n_pt > 0L) {
    message(n_pt, " of the ", m, " tornadoes returned (", sprintf("%.1f%%", 100 * n_pt / m),
            ") have no usable end point, so they are placed at their start point and are exposed only in the ZCTA that contains it (see ?tornado_tracks).")
  }
  invisible()
}

# Filters tornado_exposure for a validated request (see .validate_args())
.select_exposures <- function(v) {
  if (v$definition == "centroid_dist_km") {
    out <- .select_distance(v)
  } else if (v$definition == "boundary_dist_km") {
    out <- .select_boundary(v)
  } else {
    out <- .filter_request_rows(.exposure(), v)
    out <- out[order(out$date, out$tornado_id, out$ZCTA), , drop = FALSE]
    rownames(out) <- NULL
    if (nrow(out) == 0L) {
      message("No tornado exposures found for ", .describe_request(v), ". ",
              "Try a wider year_range or more magnitudes.")
    }
  }
  if (nrow(out) > 0L) .shape_message(out)
  out
}
