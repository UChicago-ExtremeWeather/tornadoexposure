#' Get tornado exposures for a set of ZCTAs
#'
#' Returns one row per exposed tornado-ZCTA pair for the requested ZCTAs, years
#' and tornado magnitudes. A ZCTA is exposed to a tornado when the tornado's
#' path polygon overlaps it (the default) or, if `area_thresh` is given, when
#' the share of the ZCTA's land area covered by the path is at least
#' `area_thresh`, or, if `pop_thresh` is given, when the share of the ZCTA's
#' residents inside the path is at least `pop_thresh`, or, if `centroid_dist_km`
#' is given, when the population-weighted centroid of the ZCTA (the average
#' location of its residents, from census block locations weighted by population)
#' lies within that
#' many kilometers of the path. A call uses exactly one of these definitions. Thresholds are applied to each tornado on its own, not
#' cumulatively across tornadoes.
#'
#' Every row returned is an exposed ZCTA under the single definition you
#' passed. ZCTAs the path did not touch are never returned.
#'
#' @details
#' **Choosing a definition.** Overlap counts any intersection of the path with
#' the ZCTA, however small. The area share depends on the size of the ZCTA as
#' well as on how the path crossed it, and the population share follows where
#' residents live: a path through a dense town and the same area of farmland in
#' one ZCTA have the same area share but very different population shares. The
#' centroid distance does not need an overlap, and the ZCTAs it returns are not
#' a superset of the overlap set. `data-raw/known_issues.md` in the repository
#' compares the definitions for the Joplin tornado and shows how many of the
#' overlapped ZCTAs each radius captures.
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
#' @param area_thresh `NULL` (default) returns every tornado whose path
#'   overlaps the ZCTA, including very small overlaps. A number in (0, 1]
#'   keeps rows with `area_prop_affected >= area_thresh` (0.5 means half of the
#'   ZCTA's land area). `0` is an error. A higher threshold means fewer ZCTAs
#'   qualify as exposed. Area share depends on the size of the ZCTA as well as on
#'   how the path crossed it. Cannot be combined with `pop_thresh`.
#' @param pop_thresh `NULL` (default) or a proportion in (0, 1]. Keeps rows with
#'   `pop_prop_affected >= pop_thresh`: the share of the ZCTA's resident
#'   population (total population, all ages, at the census year of the ZCTA's
#'   boundary year) estimated to live inside the path, from block-level population
#'   allocated by the share of each block's area inside the path. It follows where
#'   residents live rather than how much land the path covered. `0` is an error.
#'   ZCTAs with no residents have no population share and are never returned
#'   under this definition. The threshold applies to the share
#'   (`pop_prop_affected`) only. The count of residents in the path (`pop_affected`)
#'   and the ZCTA's population (`zcta_pop`) are returned by every call, so you can
#'   filter on the count yourself, for example
#'   `subset(x, pop_affected >= n)` with `n` a number of residents of your choice. Cannot be combined with `area_thresh` or
#'   `centroid_dist_km`.
#' @param centroid_dist_km `NULL` (default) or a positive number of kilometers.
#'   Keeps ZCTAs whose population-weighted centroid (see [zcta_centroids]) lies
#'   within this distance of the tornado path polygon, whether or not the path
#'   overlaps the ZCTA. `0` is an error and there is no upper limit. Rows have
#'   the same columns as other calls plus `dist_km` (0 when the centroid is inside
#'   the path), `centroid_type` and `centroid_in_zcta`; `area_prop_affected`,
#'   `pop_affected` and the related columns are 0 for ZCTAs the path does not
#'   overlap. Widening the radius only adds ZCTAs, but the result is not a
#'   superset of the overlap set: a large ZCTA crossed at its edge can have a
#'   centroid farther than the radius (`data-raw/known_issues.md` gives the share of overlap
#'   pairs within each radius). Choose the radius to fit your question. SPC's
#'   paths are straight lines between the start and end points and real paths
#'   curve: `data-raw/known_issues.md` (section "Path accuracy") gives the median
#'   and 90th percentile of the largest distance between the surveyed
#'   centerline and the modeled line, by tornado length, and a radius smaller than
#'   those distances cannot separate exposure from path-location error. An empty
#'   result is a message, not an error. Large radii
#'   across many years and ZCTAs can be slow, and a message gives a rough time
#'   before the work starts. Cannot be combined with `area_thresh` or
#'   `pop_thresh`.
#'
#' @return A data frame (no geometry) with one row per tornado-ZCTA pair and
#'   the columns described in [tornado_exposure]. Injury and fatality counts
#'   are tornado-level totals repeated on every ZCTA the tornado touched, so do
#'   not sum them across ZCTAs. With `centroid_dist_km` there are three more
#'   columns, `dist_km`, `centroid_type` and `centroid_in_zcta`. If nothing matches, an empty data frame with
#'   the same columns is returned and a message explains the request.
#'
#' @examples
#' # Joplin, Missouri, May 2011: ZCTAs starting with 648, EF5 only
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5)
#'
#' # EF1 and above, keeping tornadoes whose rating is unknown
#' get_data(geo_list = "648", year_range = 2011, magnitude = c(1:5, NA))
#'
#' # only ZCTAs where the path covered at least 5% of the land area
#' # (5% is an example value, not a recommendation)
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5,
#'          area_thresh = 0.05)
#'
#' # ZCTAs whose population-weighted centroid is within 10 km of the path
#' # (10 km is an example value, not a recommendation)
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5,
#'          centroid_dist_km = 10)
#'
#' @export
get_data <- function(geography = "zcta", geo_list, year_range,
                     magnitude = c(0:5, NA), area_thresh = NULL,
                     pop_thresh = NULL, centroid_dist_km = NULL) {
  v <- .validate_args(
    "get_data", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(area_thresh = area_thresh, pop_thresh = pop_thresh,
                      centroid_dist_km = centroid_dist_km)
  )
  .select_exposures(v)
}

# Rows of an exposure-like table that match the geo_list, years, ratings and
# threshold of a validated request (overlap, area_thresh or pop_thresh)
.filter_overlap_rows <- function(d, v) {
  in_zcta <- Reduce(`|`, lapply(v$geo_list, function(p) startsWith(d$ZCTA, p)))
  keep <- in_zcta & d$year %in% v$year_range & d$magnitude %in% v$magnitude
  if (v$definition == "area_thresh") {
    keep <- keep & d$area_prop_affected >= v$threshold
  } else if (v$definition == "pop_thresh") {
    keep <- keep & !is.na(d$pop_prop_affected) & d$pop_prop_affected >= v$threshold
  }
  d[keep, , drop = FALSE]
}

# Filters tornado_exposure for a validated request (see .validate_args())
.select_exposures <- function(v) {
  if (v$definition == "centroid_dist_km") {
    return(.select_distance(v))
  }
  out <- .filter_overlap_rows(.exposure(), v)
  out <- out[order(out$date, out$tornado_id, out$ZCTA), , drop = FALSE]
  rownames(out) <- NULL
  if (nrow(out) == 0L) {
    message("No tornado exposures found for ", .describe_request(v), ". ",
            "Try a wider year_range, more magnitudes, or a lower threshold.")
  }
  out
}
