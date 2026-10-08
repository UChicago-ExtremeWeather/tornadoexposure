# Internal constants shared by the data pipeline and the plotting functions
.yd_to_m <- 0.9144
.mi_to_m <- 1609.344
.area_crs <- 5070
.track_types <- c("line", "point_equal_area", "point_half_width")
# segments per quarter circle for point discs (polygon area within 0.01% of a circle)
.disc_quad_segs <- 90

#' Build tornado path polygons
#'
#' The single place where a tornado track becomes a path polygon. It is used by
#' `data-raw/process_tracks.R` (to compute areas and intersections) and by
#' [add_tracks()] (to draw polygons), so the two cannot disagree.
#'
#' * `"line"`: the track buffered by half the width with flat end caps (round
#'   caps would add area).
#' * `"point_equal_area"`: a disc centered on the start point whose area equals
#'   `len_mi * wid_yd` (in square meters).
#' * `"point_half_width"`: a disc centered on the start point with radius of
#'   half the width.
#'
#' @param track An sf or sfc object of LINESTRING (line) and POINT (point)
#'   geometries in any CRS.
#' @param wid_yd Path width in yards, after imputation (all values above 0).
#' @param len_mi Reported path length in miles (used only for
#'   `"point_equal_area"`).
#' @param track_type One of `"line"`, `"point_equal_area"`, `"point_half_width"`
#'   for each track.
#' @param crs CRS for the output (default EPSG:5070, an equal-area CRS).
#'
#' @return An sfc of valid polygons in `crs`, one per track.
#'
#' @keywords internal
#' @noRd
.path_polygon <- function(track, wid_yd, len_mi, track_type, crs = .area_crs) {
  g <- sf::st_geometry(track)
  n <- length(g)
  if (length(wid_yd) != n || length(len_mi) != n || length(track_type) != n) {
    stop("track, wid_yd, len_mi and track_type must have the same length.",
         call. = FALSE)
  }
  if (!all(track_type %in% .track_types)) {
    stop("track_type must be one of: ", paste(.track_types, collapse = ", "),
         call. = FALSE)
  }
  if (anyNA(wid_yd) || any(wid_yd <= 0)) {
    stop("wid_yd must be positive and non-missing.", call. = FALSE)
  }
  eq <- track_type == "point_equal_area"
  if (any(eq) && (anyNA(len_mi[eq]) || any(len_mi[eq] <= 0))) {
    stop("len_mi must be positive for point_equal_area tracks.", call. = FALSE)
  }

  g <- sf::st_transform(g, crs)
  half_width_m <- wid_yd * .yd_to_m / 2
  # pi * r^2 = len (m) * wid (m)
  radius_m <- half_width_m
  radius_m[eq] <- sqrt(len_mi[eq] * .mi_to_m * wid_yd[eq] * .yd_to_m / pi)

  is_line <- track_type == "line"
  out <- vector("list", n)
  if (any(is_line)) {
    out[is_line] <- as.list(sf::st_buffer(
      g[is_line], dist = half_width_m[is_line], endCapStyle = "FLAT"))
  }
  if (any(!is_line)) {
    out[!is_line] <- as.list(sf::st_buffer(
      g[!is_line], dist = radius_m[!is_line], nQuadSegs = .disc_quad_segs))
  }
  sf::st_make_valid(sf::st_sfc(out, crs = crs))
}
