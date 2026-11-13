# Internal constants shared by the data pipeline and the plotting functions
.yd_to_m <- 0.9144
.mi_to_m <- 1609.344
.area_crs <- 5070

#' Build modeled tornado path polygons
#'
#' The single place where a tornado track becomes a path polygon. It is used by
#' `data-raw/process_tracks.R` (to compute areas and intersections) and by
#' [map_exposure()] (to draw the rectangle), so the two cannot disagree. The
#' polygon is the straight line from the start to the end point buffered by half
#' the reported width on each side, with flat ends (round ends would add area).
#' It exists only for line tracks with a positive width.
#'
#' @param track An sf or sfc object of LINESTRING geometries in any CRS.
#' @param wid_yd Path width in yards, as SPC reports it (all values above 0).
#' @param crs CRS for the output (default EPSG:5070, an equal-area CRS).
#'
#' @return An sfc of valid polygons in `crs`, one per track.
#'
#' @keywords internal
#' @noRd
.path_polygon <- function(track, wid_yd, crs = .area_crs) {
  g <- sf::st_geometry(track)
  if (length(wid_yd) != length(g)) {
    stop("track and wid_yd must have the same length.", call. = FALSE)
  }
  if (anyNA(wid_yd) || any(wid_yd <= 0)) {
    stop("wid_yd must be positive and non-missing.", call. = FALSE)
  }
  if (!all(sf::st_geometry_type(g) == "LINESTRING")) {
    stop("A path polygon exists only for line tracks.", call. = FALSE)
  }
  g <- sf::st_transform(g, crs)
  sf::st_make_valid(sf::st_buffer(g, dist = wid_yd * .yd_to_m / 2,
                                  endCapStyle = "FLAT"))
}
