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
#' tracks). Path polygons are larger than surveyed damage swaths (the modeled area
#' is a median of
#' `r sprintf("%.2f", median(tornado_tracks$tornado_area_m2[match(survey_matches$tornado_id[survey_matches$status == "included"], tornado_tracks$tornado_id)] / (survey_matches$swath_km2[survey_matches$status == "included"] * 1e6)))`
#' times the surveyed area for the tornadoes with a survey; see [survey_matches]),
#' because the polygon holds SPC's width, treated as the maximum width, along the
#' whole track (see [tornado_exposure]).
#' The polygon of a point track is a disc whose size is a stand-in, because the
#' direction is unknown (see [tornado_exposure]).
#'
#' @inheritParams get_data
#' @param plot A ggplot object to draw on, usually from [map_exposure()].
#' @param geometry `"track"` (default), `"polygon"` or `"survey"`. With
#'   `"survey"` the tornadoes come from [get_survey_data()] (same arguments) and
#'   their surveyed damage swaths (simplified to 50 m) are drawn. Only tornadoes
#'   with a usable survey swath are drawn; the coverage message says how many.
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
                       magnitude = c(0:5, NA), area_thresh = NULL,
                       pop_thresh = NULL, centroid_dist_km = NULL,
                       geometry = c("track", "polygon", "survey")) {
  v <- .validate_args(
    "add_tracks", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(area_thresh = area_thresh, pop_thresh = pop_thresh,
                      centroid_dist_km = centroid_dist_km)
  )
  if (missing(plot) || !inherits(plot, "ggplot")) {
    stop("plot must be a ggplot object, for example the result of ",
         "map_exposure(geo_list = ..., year_range = ...).", call. = FALSE)
  }
  geometry <- match.arg(geometry)

  exposures <- if (geometry == "survey") .select_survey(v) else .select_exposures(v)
  if (nrow(exposures) == 0L) {
    return(plot)
  }

  if (geometry == "survey") {
    ids <- unique(exposures$tornado_id)
    sw <- .survey_tracks()
    sw <- sw[match(ids, sw$tornado_id), ]
    sw$magnitude <- exposures$magnitude[match(ids, exposures$tornado_id)]
    return(plot +
      ggplot2::geom_sf(data = sw, ggplot2::aes(color = .data$magnitude),
                       fill = "black", alpha = 0.3, inherit.aes = FALSE) +
      ggplot2::scale_color_viridis_c(option = "plasma", direction = -1) +
      ggplot2::labs(color = "Magnitude"))
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
