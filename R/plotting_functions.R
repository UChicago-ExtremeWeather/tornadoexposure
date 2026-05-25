#' Retrieve ZCTA geometries from Tigris
#'
#' Takes a list of US ZCTA codes and a year, and returns a simple features
#' geometry object for those ZCTA boundaries in the given year
#'
#' @param zcta_list Vector of ZCTAs (or ZCTA prefixes)
#' @note ZCTAs/prefixes can be passed in as characters or integers
#' @note ZCTAs/prefixes can be 1-5 characters
#' @param year_range Range of years across which data should be aggregated
#'
#' @return An sf object containing ZCTA boundary geometries
#'
#' @keywords internal
get_geometry <- function(zcta_list, year_range){
  # default to closest year in tigris
  valid_years <- c(2000, 2010, 2020)

  if (length(year_range) == 1) {
    years <- year_range
  } else {
    years <- seq(min(year_range), max(year_range))
  }

  mid_year <- median(years)

  # default to 2000 for any year before 2000
  year_plot <- max(valid_years[valid_years <= mid_year], na.rm = TRUE)
  if (is.infinite(year_plot)) year_plot <- 2000

  boundary <- tigris::zctas(
    starts_with = as.character(zcta_list),
    year = year_plot,
    cb = TRUE)

  # standardize ZCTA column name
  boundary <- if (year_plot == 2010) {
    dplyr::mutate(boundary, ZCTA = ZCTA5)
  } else if (year_plot == 2020) {
    dplyr::mutate(boundary, ZCTA = GEOID20)
  } else {
    boundary
  }
  return(boundary)
}

#' Generate basemap for ZCTA boundaries
#'
#' Takes a list of US ZCTA codes and a year, and returns a plot of the requested
#' ZCTA boundaries
#'
#' @param zcta_list Vector of ZCTAs (or ZCTA prefixes)
#' @note ZCTAs/prefixes can be passed in as characters or integers
#' @note ZCTAs/prefixes can be 1-5 characters
#' @param year_range Range of years across which data should be aggregated
#'
#' @return A mapping of boundaries for requested ZCTAs
#'
#' @keywords internal
get_basemap <- function(zcta_list, year_range){
  boundary_geom <- get_geometry(zcta_list, year_range)
  ggplot2::ggplot(data = boundary_geom) +
    ggplot2::geom_sf(fill = NA, color = "black") +
    ggplot2::theme_void()
}

#' Aggregates a feature of interest across ZCTAs for given timeframe
#'
#' Takes a dataframe of exposures, returns a dataframe where each row is a ZCTA
#' and the sum or average (if magnitude) of the feature
#'
#' @param exposed_zctas Dataframe of tornado-level exposures
#' @param feature The feature of interest (tornado_id for count, mag for magnitude,
#' fat for fatalities, inj for injuries)
#'
#' @return Dataframe of feature aggregated at ZCTA level
#'
#' @keywords internal
generate_feature <- function(exposed_zctas,
                             feature = c("tornado_id", "magnitude",
                                         "total_fatality", "total_injury")){
  feature <- match.arg(feature)
  allowed <- c("tornado_id", "magnitude", "total_fatality", "total_injury")

  if (!feature %in% allowed) {
    stop("feature must be one of: ", paste(allowed, collapse = ", "))
  }

  agg <- exposed_zctas %>%
    dplyr::group_by(ZCTA)

  if (feature == "magnitude") {

    agg <- agg %>%
      dplyr::summarise(
        value = mean(.data[[feature]], na.rm = TRUE),
        .groups = "drop"
      )

  } else if (feature == "tornado_id") {

    agg <- agg %>%
      dplyr::summarise(
        value = dplyr::n_distinct(.data[[feature]]),
        .groups = "drop"
      )

  } else {

    agg <- agg %>%
      dplyr::summarise(
        value = sum(as.numeric(.data[[feature]]), na.rm = TRUE),
        .groups = "drop"
      )
  }

  agg
}

#' Generates a dataframe containing all exposures for a given set of ZCTAs over
#' a specified range of years
#'
#' Takes a list of US ZCTA codes and a year (or range of years), and returns a
#' dataframe containing all exposure data for the requested ZCTA boundaries
#'
#' @param zcta_list Vector of ZCTAs (or ZCTA prefixes)
#' @note ZCTAs/prefixes can be passed in as characters or integers
#' @note ZCTAs/prefixes can be 1-5 characters
#' @param year_range Range of years across which data should be aggregated
#'
#' @return A dataframe containing exposure data for selected ZCTAs across
#' specified range of years
#'
#' @export
#'
#' @importFrom dplyr %>%
get_data <- function(zcta_list, year_range){

  zcta_list <- as.character(zcta_list)

  keep <- zcta_tracks$year %in% year_range &
    purrr::map_lgl(
      as.character(zcta_tracks$ZCTA),
      ~ any(startsWith(.x, zcta_list))
    )

  subset <- zcta_tracks[keep, ]

  subset
}

#' Create a choropleth map for variable of interest across selected ZCTAs
#'
#' Takes a list of US ZCTA codes, a year, and a feature, and returns a plot of
#' the requested ZCTA boundaries with a choropleth fill to represent the spatial
#' distribution of the feature
#'
#' @param zcta_list Vector of ZCTAs (or ZCTA prefixes)
#' @note ZCTAs/prefixes can be passed in as characters or integers
#' @note ZCTAs/prefixes can be 1-5 characters
#' @param year_range Range of years across which data should be aggregated
#' @param feature Name of feature to be visualized (can be "tornado_id", "magnitude",
#' "total_fatality", "total_injury")
#' @note Feature name should be passed in as a string in quotations
#' @note If not feature name is supplied, function will return an unfilled map
#' of the requested ZCTA boundaries
#'
#' @return A map of the distribution of feature of interest across selected ZCTAs
#'
#' @export
#'
#' @importFrom dplyr %>%
map_exposure <- function(zcta_list, year_range, feature=NULL){

  feature_labels <- c(
    tornado_id = "Number of Tornadoes",
    magnitude = "Average Tornado Magnitude",
    total_fatality = "Total Fatalities (Per Tornado)",
    total_injury = "Total Injuries (Per Tornado)"
  )

  subset <- get_data(zcta_list, year_range)

  boundary_geom <- get_geometry(zcta_list, year_range)

  if (!is.null(feature)) {

    fill_data <- generate_feature(subset, feature)

    plot_data <- boundary_geom %>%
      dplyr::left_join(
        sf::st_drop_geometry(fill_data),
        by = "ZCTA"
      )

  } else {

    plot_data <- boundary_geom

  }

  yr_label <- if (length(year_range) == 1 ||
                  min(year_range) == max(year_range)
                  ) {
    as.character(min(year_range))
  } else {
    paste0(min(year_range), "–", max(year_range))
  }

  p <- ggplot2::ggplot(plot_data)

  if (!is.null(feature)) {

    p <- p +
      ggplot2::geom_sf(
        ggplot2::aes(fill = value),
        color = "black"
      ) +
      scico::scale_fill_scico(
        palette = "lajolla",
        na.value = "transparent",
        direction = -1
      ) +
      ggplot2::labs(
        fill = feature_labels[[feature]],
        title = paste0("Tornado Exposures, ", yr_label)
      )

  } else {

    p <- p +
      ggplot2::geom_sf(
        fill = NA,
        color = "black"
      ) +
      ggplot2::labs(
        title = paste0("Tornado Exposures, ", yr_label)
      )

  }

  p + ggplot2::theme_void()
}

#' Overlay tornado tracks on top of ZCTA boundary maps
#'
#' Takes a map object (either choropleth filled or blank ZCTA boundaries) and
#' overlays tornado tracks
#'
#' @param zcta_list Vector of ZCTAs (or ZCTA prefixes)
#' @note ZCTAs/prefixes can be passed in as characters or integers
#' @note ZCTAs/prefixes can be 1-5 characters
#' @param year_range Range of years across which data should be aggregated
#' @param plot An sf plot object
#' @note Can be a choropleth or map of ZCTA boundaries created by ```map_exposure```
#'
#' @return A map with tornado tracks overlaid
#'
#' @export
#'
#' @importFrom dplyr %>%
add_tracks <- function(zcta_list, year_range, plot){

  zcta_subset <- get_data(zcta_list, year_range)

  tracks_subset <- zcta_tracks %>%
    dplyr::filter(year %in% year_range) %>%
    sf::st_transform(sf::st_crs(zcta_subset))

  affected_tracks <- sf::st_filter(
    tracks_subset,
    zcta_subset,
    .predicate = sf::st_intersects
  )
  plot +
    ggplot2::geom_sf(data = affected_tracks,
                     ggplot2::aes(color = magnitude)
    ) +
    ggplot2::scale_color_viridis_c(option = "plasma", direction = -1) +
    ggplot2::labs(color = "Magnitude")
}
