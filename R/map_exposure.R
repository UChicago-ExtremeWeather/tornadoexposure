# Aggregates a feature across ZCTAs: returns one row per ZCTA with a `value`.
generate_feature <- function(exposed_zctas,
                             feature = c("tornado_id", "magnitude",
                                         "total_fatality", "total_injury")) {
  feature <- match.arg(feature)
  z <- exposed_zctas$ZCTA
  value <- switch(
    feature,
    magnitude = tapply(exposed_zctas$magnitude, z, mean, na.rm = TRUE),
    tornado_id = tapply(exposed_zctas$tornado_id, z,
                        function(x) length(unique(x))),
    tapply(as.numeric(exposed_zctas[[feature]]), z, sum, na.rm = TRUE)
  )
  data.frame(ZCTA = names(value), value = as.numeric(value),
             stringsAsFactors = FALSE)
}

.feature_labels <- c(
  tornado_id = "Number of tornadoes",
  magnitude = "Average magnitude (EF)",
  total_fatality = "Fatalities (sum of tornado totals)",
  total_injury = "Injuries (sum of tornado totals)"
)

.year_label <- function(year_range) {
  if (min(year_range) == max(year_range)) {
    as.character(min(year_range))
  } else {
    paste0(min(year_range), "-", max(year_range))
  }
}

#' Map tornado exposure across ZCTAs
#'
#' Draws ZCTA boundaries for the requested ZCTAs and, if `feature` is given,
#' fills each ZCTA with a summary of the tornadoes that exposed it under the
#' exposure definition you chose (see [get_data()]).
#'
#' Boundaries come from the Census Bureau (via tigris) and are downloaded when
#' the function runs. A year range that spans Census vintages is plotted on one
#' boundary vintage (2000, 2010 or 2020, whichever is closest to the middle of
#' the range), while exposures use the vintage that matches each tornado's year.
#'
#' Injury and fatality values are tornado-level counts attributed to every ZCTA
#' the tornado touched, then summed across tornadoes within a ZCTA. A ZCTA with
#' no exposures is left unfilled.
#'
#' @inheritParams get_data
#' @param feature Name of the feature to fill: `"tornado_id"` (number of
#'   tornadoes), `"magnitude"` (average magnitude), `"total_fatality"` or
#'   `"total_injury"`. If `NULL` (default), an unfilled map of the ZCTA
#'   boundaries is returned.
#'
#' @return A ggplot object.
#'
#' @examples
#' \donttest{
#' # needs internet access to download boundaries
#' map_exposure(geo_list = "648", year_range = 2011, feature = "tornado_id")
#' }
#'
#' @export
map_exposure <- function(geography = "zcta", geo_list, year_range,
                         feature = NULL, magnitude = 1:5, area_thresh = NULL) {
  v <- .validate_args(
    "map_exposure", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(area_thresh = area_thresh)
  )
  if (!is.null(feature) &&
      (!is.character(feature) || length(feature) != 1L ||
       !feature %in% names(.feature_labels))) {
    stop("feature must be NULL or one of: ",
         paste0('"', names(.feature_labels), '"', collapse = ", "), ".",
         call. = FALSE)
  }

  exposures <- .select_exposures(v)
  boundary <- get_geometry(v$geo_list, v$year_range)

  title <- paste0("Tornado exposures, ", .year_label(v$year_range))
  subtitle <- if (v$definition == "overlap") {
    "Exposed = any overlap with the tornado path"
  } else {
    paste0("Exposed = ", v$definition, " >= ", v$threshold)
  }

  if (!is.null(feature) && nrow(exposures) > 0L) {
    fill <- generate_feature(exposures, feature)
    boundary$value <- fill$value[match(boundary$ZCTA, fill$ZCTA)]
    p <- ggplot2::ggplot(boundary) +
      ggplot2::geom_sf(ggplot2::aes(fill = .data$value), color = "black") +
      scico::scale_fill_scico(palette = "lajolla", na.value = "transparent",
                              direction = -1) +
      ggplot2::labs(fill = .feature_labels[[feature]])
  } else {
    p <- ggplot2::ggplot(boundary) +
      ggplot2::geom_sf(fill = NA, color = "black")
  }
  p + ggplot2::labs(title = title, subtitle = subtitle) +
    ggplot2::theme_void()
}
