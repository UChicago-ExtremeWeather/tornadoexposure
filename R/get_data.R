#' Get tornado exposures for a set of ZCTAs
#'
#' Returns one row per exposed tornado-ZCTA pair for the requested ZCTAs, years
#' and tornado magnitudes. A ZCTA is exposed to a tornado when the tornado's
#' path polygon overlaps it (the default) or, if `area_thresh` is given, when
#' the share of the ZCTA's land area covered by the path is at least
#' `area_thresh`. The threshold is applied to each tornado on its own, not
#' cumulatively across tornadoes.
#'
#' Every row returned is an exposed ZCTA under the single definition you
#' passed. ZCTAs that were not exposed are not returned, so unexposed ZCTAs are
#' the requested ZCTAs that do not appear in the result. EF0 tornadoes are not
#' in the data, so an "unexposed" ZCTA can include ZCTAs hit only by EF0
#' tornadoes.
#'
#' @param geography Geography of the data. Only `"zcta"` is available; the
#'   argument exists for consistency with sibling exposure packages.
#' @param geo_list Character vector of ZCTAs or ZCTA prefixes (1 to 5 digits),
#'   for example `"648"` or `c("60637", "606")`. Use character strings:
#'   numbers lose leading zeros (02139 becomes 2139), which breaks matching in
#'   the Northeast, and numeric input triggers a warning.
#' @param year_range Years to include, for example `2010:2015`. The data cover
#'   1996 to the latest release year.
#' @param magnitude Vector of EF magnitudes to include, from 1 to 5. A minimum
#'   of EF3 is `magnitude = 3:5`. EF0 tornadoes are not in the data.
#' @param area_thresh `NULL` (default) returns every tornado whose path
#'   overlaps the ZCTA, including very small overlaps. A number in (0, 1]
#'   keeps rows with `area_prop_affected >= area_thresh` (0.5 means half of the
#'   ZCTA's land area). `0` is an error. A higher threshold means fewer ZCTAs
#'   qualify as exposed. Cannot be combined with other exposure definitions.
#'
#' @return A data frame (no geometry) with one row per tornado-ZCTA pair and
#'   the columns described in [tornado_exposure]. Injury and fatality counts
#'   are tornado-level totals repeated on every ZCTA the tornado touched, so do
#'   not sum them across ZCTAs. If nothing matches, an empty data frame with
#'   the same columns is returned and a message explains the request.
#'
#' @examples
#' # Joplin, Missouri, May 2011: ZCTAs starting with 648, EF5 only
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5)
#'
#' # only ZCTAs where the path covered at least 5% of the land area
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5,
#'          area_thresh = 0.05)
#'
#' @export
get_data <- function(geography = "zcta", geo_list, year_range,
                     magnitude = 1:5, area_thresh = NULL) {
  v <- .validate_args(
    "get_data", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(area_thresh = area_thresh)
  )
  .select_exposures(v)
}

# Filters tornado_exposure for a validated request (see .validate_args())
.select_exposures <- function(v) {
  d <- .exposure()
  in_zcta <- Reduce(`|`, lapply(v$geo_list, function(p) startsWith(d$ZCTA, p)))
  keep <- in_zcta & d$year %in% v$year_range & d$magnitude %in% v$magnitude
  if (v$definition == "area_thresh") {
    keep <- keep & d$area_prop_affected >= v$threshold
  }
  out <- d[keep, , drop = FALSE]
  out <- out[order(out$date, out$tornado_id, out$ZCTA), , drop = FALSE]
  rownames(out) <- NULL
  if (nrow(out) == 0L) {
    message("No tornado exposures found for ", .describe_request(v), ". ",
            "Try a wider year_range, more magnitudes, or a lower threshold.")
  }
  out
}
