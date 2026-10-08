#' Overlay tornado tracks on a ZCTA map
#'
#' Adds the tornadoes returned by [get_data()] (same arguments) to a map such
#' as the one made by [map_exposure()]. The tornado ids come from
#' [get_data()]; the tracks are drawn from [tornado_tracks].
#'
#' With `geometry = "track"` (default) the reported track is drawn: a line from
#' start to end, or a point when the end is unknown or equal to the start. With
#' `geometry = "polygon"` the path polygon used for the exposure calculation is
#' drawn instead (the track buffered by the reported width, or a disc for point
#' tracks). Path polygons are upper-bound estimates because they assume the
#' maximum reported width along the whole track, and polygons for point tracks
#' are approximations because the direction is unknown.
#'
#' @inheritParams get_data
#' @param plot A ggplot object to draw on, usually from [map_exposure()].
#' @param geometry Either `"track"` (default) or `"polygon"`.
#'
#' @return The ggplot object with a tornado layer added, colored by magnitude.
#' If no tornadoes match, `plot` is returned unchanged with a message.
#'
#' @examples
#' \donttest{
#' # needs internet access to download boundaries
#' p <- map_exposure(geo_list = "648", year_range = 2011, magnitude = 5)
#' add_tracks(geo_list = "648", year_range = 2011, plot = p, magnitude = 5)
#' add_tracks(geo_list = "648", year_range = 2011, plot = p, magnitude = 5,
#'            geometry = "polygon")
#' }
#'
#' @export
add_tracks <- function(geography = "zcta", geo_list, year_range, plot,
                       magnitude = 1:5, area_thresh = NULL,
                       geometry = c("track", "polygon")) {
  v <- .validate_args(
    "add_tracks", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(area_thresh = area_thresh)
  )
  if (missing(plot) || !inherits(plot, "ggplot")) {
    stop("plot must be a ggplot object, for example the result of ",
         "map_exposure(geo_list = ..., year_range = ...).", call. = FALSE)
  }
  geometry <- match.arg(geometry)

  exposures <- .select_exposures(v)
  if (nrow(exposures) == 0L) {
    return(plot)
  }

  ids <- unique(exposures$tornado_id)
  tracks <- .tracks()
  tracks <- tracks[match(ids, tracks$tornado_id), ]
  tracks$magnitude <- exposures$magnitude[match(ids, exposures$tornado_id)]

  if (geometry == "polygon") {
    polys <- .path_polygon(tracks, tracks$wid_yd, tracks$len_mi,
                           tracks$track_type)
    tracks <- sf::st_sf(
      tornado_id = tracks$tornado_id, magnitude = tracks$magnitude,
      geometry = sf::st_transform(polys, sf::st_crs(tracks))
    )
    layer <- ggplot2::geom_sf(
      data = tracks, ggplot2::aes(color = .data$magnitude),
      fill = "black", alpha = 0.3, inherit.aes = FALSE
    )
  } else {
    layer <- ggplot2::geom_sf(
      data = tracks, ggplot2::aes(color = .data$magnitude),
      inherit.aes = FALSE
    )
  }
  plot + layer +
    ggplot2::scale_color_viridis_c(option = "plasma", direction = -1) +
    ggplot2::labs(color = "Magnitude")
}
