#' Get tornado exposures for a set of ZCTAs
#'
#' Returns one row per exposed tornado-ZCTA pair for the requested ZCTAs, years
#' and tornado magnitudes. A call uses exactly one exposure definition. By
#' default a ZCTA is exposed when the tornado touched it: the modeled path polygon
#' (the SPC line buffered by the reported width) overlaps it, the centerline lies in
#' it when SPC reports no width, or the start point lies in it for a tornado with no
#' usable end point. With `area_thresh` the modeled share of the ZCTA's area inside
#' the path must be at least that share, with `pop_thresh` the modeled share of its
#' residents must be, with `centroid_dist_km` the ZCTA's population-weighted centroid
#' must lie within that distance of the SPC line, and with `boundary_dist_km` the ZCTA's
#' boundary must lie within that distance of the SPC line. Thresholds are applied to
#' each tornado on its own, not cumulatively across tornadoes.
#'
#' @details
#' **Modeled columns.** The columns that begin with `modeled_` come from a straight
#' line at SPC's single width, which NWS instructions define as the maximum width of
#' the damage path. They run about 1.2 times the area of the NWS surveyed damage
#' swaths, are noisy for any single tornado, and are approximations, not a damage
#' boundary (`data-raw/known_issues.md`, section "Modeled columns", gives the
#' comparison with the surveyed swaths). They are `NA` for a tornado with no
#' usable end point (a point: SPC's end coordinates are missing, 0 or equal to the
#' start) and for a line with a width of 0 or missing: no path shape is modeled for
#' them. `area_thresh` and `pop_thresh` do not evaluate such tornadoes and do not
#' return them; overlap, `centroid_dist_km` and `boundary_dist_km` include them, and
#' every call prints how many are in the request (see [tornado_tracks]).
#'
#' **Choosing a definition.** Overlap counts any intersection of the path with
#' the ZCTA, however small. The area share depends on the size of the ZCTA as
#' well as on how the path crossed it, and the population share follows where
#' residents live: a path through a dense town and the same area of farmland in
#' one ZCTA have the same area share but very different population shares. The
#' distance definitions are measured from the SPC line (the start point for a
#' tornado with no usable end point) and have no upper limit; their ZCTAs are not
#' a superset of the overlap set. `data-raw/known_issues.md` in the repository
#' compares the definitions for the Joplin tornado.
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
#' @param area_thresh `NULL` (default) returns every tornado that touched the
#'   ZCTA, including very small overlaps. A number in (0, 1] keeps rows with
#'   `modeled_area_prop >= area_thresh` (0.5 means half of the ZCTA's polygon area).
#'   `0` is an error. A higher threshold means fewer ZCTAs qualify as exposed. The
#'   area share depends on the size of the ZCTA as well as on how the path crossed it.
#'   Tornadoes with no modeled path shape are not evaluated and not returned. Cannot
#'   be combined with another definition.
#' @param pop_thresh `NULL` (default) or a proportion in (0, 1]. Keeps rows with
#'   `modeled_pop_prop >= pop_thresh`: the share of the ZCTA's resident
#'   population (total population, all ages, at the census year of the ZCTA's
#'   boundary year) estimated to live inside the modeled path, from block-level population
#'   allocated by the share of each block's area inside the path. It follows where
#'   residents live rather than how much land the path covered. `0` is an error.
#'   ZCTAs with no residents have no population share and are never returned
#'   under this definition. Tornadoes with no modeled path shape are not evaluated and
#'   not returned. The count of residents (`modeled_pop_affected`) and the ZCTA's
#'   population (`zcta_pop`) are returned by every call, so you can
#'   filter on the count yourself, for example
#'   `subset(x, modeled_pop_affected >= n)` with `n` a number of residents of your choice. Cannot be combined with another definition.
#' @param centroid_dist_km `NULL` (default) or a positive number of kilometers.
#'   Keeps ZCTAs whose population-weighted centroid (see [zcta_centroids]) lies
#'   within this distance of the SPC line (of the start point for a tornado with no
#'   usable end point), whether or not the path touches the ZCTA. `0` is an error and
#'   there is no upper limit. The result is not a superset of the overlap set: a large
#'   ZCTA crossed at its edge can have a centroid farther than the radius. For ZCTAs
#'   the path does not touch, `modeled_*` columns are 0 (a tornado with a modeled path
#'   shape) or `NA` (a tornado without one) and `boundary_dist_km` is `NA`
#'   (use `boundary_dist_km` to measure it). SPC's paths are straight lines
#'   between the start and end points and real paths curve:
#'   `data-raw/known_issues.md` (section "Modeled columns") gives the median
#'   and 90th percentile of the largest distance between the surveyed
#'   centerline and the SPC line, by tornado length, and a radius smaller than
#'   those distances cannot separate exposure from path-location error. Large radii
#'   across many years and ZCTAs can be slow, and a message gives a rough time
#'   before the work starts. Cannot be combined with another definition.
#' @param boundary_dist_km `NULL` (default) or a positive number of kilometers.
#'   Keeps ZCTAs whose boundary lies within this distance of the SPC line (of the start
#'   point for a tornado with no usable end point); the distance is 0 when the line
#'   touches the ZCTA. There is no upper limit. The distance uses the full
#'   TIGER/Line ZCTA boundaries (not the generalized cartographic files), a national
#'   file of about 680 MB (2000 boundaries), 524 MB (2010) or 528 MB (2020) that is
#'   downloaded once and cached; a message says which. Cannot be combined with another
#'   definition.
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
#' # EF1 and above, keeping tornadoes whose rating is unknown
#' get_data(geo_list = "648", year_range = 2011, magnitude = c(1:5, NA))
#'
#' # only ZCTAs where the modeled path covered at least 5% of the ZCTA's area
#' # (5% is an example, not a recommendation)
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5,
#'          area_thresh = 0.05)
#'
#' # ZCTAs whose population-weighted centroid is within 10 km of the SPC line
#' # (10 km is an example, not a recommendation)
#' get_data(geo_list = "648", year_range = 2011, magnitude = 5,
#'          centroid_dist_km = 10)
#'
#' @export
get_data <- function(geography = "zcta", geo_list, year_range,
                     magnitude = c(0:5, NA), area_thresh = NULL,
                     pop_thresh = NULL, centroid_dist_km = NULL,
                     boundary_dist_km = NULL) {
  v <- .validate_args(
    "get_data", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(area_thresh = area_thresh, pop_thresh = pop_thresh,
                      centroid_dist_km = centroid_dist_km,
                      boundary_dist_km = boundary_dist_km)
  )
  .select_exposures(v)
}

# Rows of an exposure-like table that match the geo_list, years and ratings of a
# validated request, with the threshold of an overlap, area_thresh or pop_thresh request
.filter_request_rows <- function(d, v) {
  in_zcta <- Reduce(`|`, lapply(v$geo_list, function(p) startsWith(d$ZCTA, p)))
  d[in_zcta & d$year %in% v$year_range & d$magnitude %in% v$magnitude, , drop = FALSE]
}

.filter_overlap_rows <- function(d, v) {
  d <- .filter_request_rows(d, v)
  keep <- rep(TRUE, nrow(d))
  if (v$definition == "area_thresh") {
    keep <- !is.na(d$modeled_area_prop) & d$modeled_area_prop >= v$threshold
  } else if (v$definition == "pop_thresh") {
    keep <- !is.na(d$modeled_pop_prop) & d$modeled_pop_prop >= v$threshold
  }
  d[keep, , drop = FALSE]
}

# The message about tornadoes that have no modeled path shape. `all_rows` are the rows of the request before
# any threshold, `out` the rows returned.
.shape_message <- function(all_rows, out, v) {
  ids <- unique(all_rows$tornado_id)
  m <- length(ids)
  if (m == 0L) return(invisible())
  tt <- all_rows[!duplicated(all_rows$tornado_id), ]
  n_pt <- sum(tt$track_type == "point")
  n_w0 <- sum(tt$track_type == "line" & is.na(tt$modeled_intersection_m2))
  threshold <- v$definition %in% c("area_thresh", "pop_thresh")
  pct <- function(n) sprintf("%.1f%%", 100 * n / m)
  if (n_pt > 0L) {
    msg <- paste0(n_pt, " of the ", m, " tornadoes ", if (threshold) "in the request" else "returned", " (", pct(n_pt),
                  ") have no usable end point, so no path shape is modeled and they are placed at their start point (see ?tornado_tracks)")
    if (threshold) {
      msg <- paste0(msg, ". ", n_pt + n_w0, " tornadoes were not evaluated against ", v$definition,
                    " and are not returned; overlap or a distance definition (centroid_dist_km, boundary_dist_km) includes them")
    }
    message(msg, ".")
  }
  if (n_w0 > 0L) {
    message(n_w0, " of the ", m, " tornadoes ", if (threshold) "in the request" else "returned", " (", pct(n_w0),
            ") are lines with a width of 0 or missing in SPC's record, so no path polygon is modeled for them",
            if (threshold && n_pt == 0L) paste0(" and they were not evaluated against ", v$definition, " and are not returned; overlap or a distance definition includes them") else "",
            " (see ?tornado_tracks).")
  }
  invisible()
}

# Filters tornado_exposure for a validated request (see .validate_args())
.select_exposures <- function(v) {
  if (v$definition == "centroid_dist_km") {
    out <- .select_distance(v)
    if (nrow(out) > 0L) .shape_message(out, out, v)
    return(out)
  }
  if (v$definition == "boundary_dist_km") {
    out <- .select_boundary(v)
    if (nrow(out) > 0L) .shape_message(out, out, v)
    return(out)
  }
  all_rows <- .filter_request_rows(.exposure(), v)
  out <- .filter_overlap_rows(.exposure(), v)
  out <- out[order(out$date, out$tornado_id, out$ZCTA), , drop = FALSE]
  rownames(out) <- NULL
  if (nrow(out) == 0L) {
    message("No tornado exposures found for ", .describe_request(v), ". ",
            "Try a wider year_range, more magnitudes, or a lower threshold.")
  }
  .shape_message(all_rows, out, v)
  out
}
