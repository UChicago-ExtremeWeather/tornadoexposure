#' Retrieve ZCTA geometries from Tigris
#'
#' Takes a list of US ZCTA codes and a year, and returns a simple features
#' geometry object for those ZCTA boundaries in the given year
#'
#' @param zcta_list Vector of ZCTAs (or ZCTA prefixes)
#' @note ZCTAs/prefixes can be passed in as characters or integers
#' @note ZCTAs/prefixes can be 1-5 characters
#' @param yr Census year for requested geometries
#'
#' @return An sf object containing ZCTA boundary geometries
#'
#' @keywords internal
get_geometry <- function(zcta_list, yr){
  # default to closest year in tigris
  valid_years <- c(2000, 2010, 2020)

  # default to 2000 for any year before 2000
  year_plot <- max(valid_years[valid_years <= yr], na.rm = TRUE)
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
#' @param year Census year for requested geometries
#'
#' @return A mapping of boundaries for requested ZCTAs
#'
#' @keywords internal
get_basemap <- function(zcta_list, year){
  boundary_geom <- get_geometry(zcta_list, year)
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
                             feature = c("tornado_id", "mag", "fat", "inj")){
  feature <- match.arg(feature)
  allowed <- c("tornado_id", "mag", "fat", "inj")

  if (!feature %in% allowed) {
    stop("feature must be one of: ", paste(allowed, collapse = ", "))
  }

  agg <- exposed_zctas %>%
    dplyr::group_by(ZCTA)

  if (feature == "mag") {

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

#' Generates a dataframe containing all exposures for a given set of ZCTA-years
#'
#' Takes a list of US ZCTA codes, a year, and a feature, and returns a dataframe
#' containing all exposure data for the requested ZCTA boundaries
#'
#' @param zcta_list Vector of ZCTAs (or ZCTA prefixes)
#' @note ZCTAs/prefixes can be passed in as characters or integers
#' @note ZCTAs/prefixes can be 1-5 characters
#' @param year Census year for requested geometries
#'
#' @return A dataframe with exposure data for selected ZCTAs
#'
#' @export
#'
#' @importFrom dplyr %>%
get_data <- function(zcta_list, year){

  subset <- zt %>% dplyr::filter(
    yr == year,
    stringr::str_starts(as.character(ZCTA), as.character(zcta_list))
  ) # force ZCTA and zcta_list to be characters

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
#' @param year Census year for requested geometries
#' @param feature Name of feature to be visualized (can be tornado_id, mag,
#' fatality, injury)
#' @note Feature name should align with column name in dataset, must be string
#'
#' @return A map of the distribution of feature of interest across selected ZCTAs
#'
#' @export
#'
#' @importFrom dplyr %>%
map_exposure <- function(zcta_list, year, feature){

  feature_labels <- c(
    tornado_id = "Number of Tornadoes",
    mag = "Average Tornado Magnitude",
    fat = "Total Fatalities (Per Tornado)",
    inj = "Total Injuries (Per Tornado)"
  )

  subset <- get_data(zt, zcta_list, year)

  fill_data <- generate_feature(subset, feature)

  boundary_geom <- get_geometry(zcta_list, year)

  plot_data <- boundary_geom %>%
    dplyr::left_join(
      sf::st_drop_geometry(fill_data),
      by = "ZCTA")

  ggplot2::ggplot(plot_data) +
    ggplot2::geom_sf(
      ggplot2::aes(fill = value),
      color = "black"
    ) +
    ggplot2::scale_fill_viridis_c(na.value = "transparent") +
    ggplot2::labs( # eventually modify so that the fill value isn't just the column name
      fill = feature_labels[[feature]]
    ) + ggplot2::theme_void()
}

#' Overlay tornado tracks on top of ZCTA boundary maps
#'
#' Takes a map object (either choropleth filled or blank ZCTA boundaries) and
#' overlays tornado tracks
#'
#' @param zcta_list Vector of ZCTAs (or ZCTA prefixes)
#' @note ZCTAs/prefixes can be passed in as characters or integers
#' @note ZCTAs/prefixes can be 1-5 characters
#' @param year Census year for requested geometries
#' @param plot An sf plot object
#' @note Can be a choropleth created by map_exposure or unfilled ZCTA boundaries
#' from get_geometry
#'
#' @return A map with tornado tracks overlaid
#'
#' @export
#'
#' @importFrom dplyr %>%
add_tracks <- function(zcta_list, year, plot){

  zcta_subset <- get_data(zt, zcta_list, year)

  tracks_subset <- tornado_tracks %>%
    dplyr::filter(yr == year) %>%
    sf::st_transform(sf::st_crs(zcta_subset))

  affected_tracks <- sf::st_filter(
    tracks_subset,
    zcta_subset,
    .predicate = sf::st_intersects
  )
  plot +
    ggplot2::geom_sf(data = affected_tracks,
                     ggplot2::aes(color = mag)
    ) +
    ggplot2::scale_color_viridis_c() +
    ggplot2::labs(color = "Magnitude")
}
