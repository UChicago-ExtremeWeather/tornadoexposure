# Internal helpers for ZCTA boundary maps

# Census boundary vintage used for plotting a year range: the latest of
# 2000, 2010 and 2020 that is not after the middle of the range (2000 for
# earlier years).
.plot_vintage <- function(year_range) {
  mid_year <- (min(year_range) + max(year_range)) / 2
  valid <- c(2000, 2010, 2020)
  valid <- valid[valid <= mid_year]
  if (length(valid) == 0L) 2000 else max(valid)
}

# Standardize a boundary file from tigris::zctas() to columns ZCTA (character)
# and geometry, one row per ZCTA, with a CRS. The ZCTA column is named
# ZCTA5CE20 (2020), ZCTA5 (2010 cartographic) or ZCTA (2000 cartographic);
# 2000 cartographic files have no CRS (NAD83 is assumed) and split
# discontiguous ZCTAs into several rows.
.standardize_zcta <- function(boundary) {
  candidates <- c("ZCTA5CE20", "ZCTA5CE10", "ZCTA5CE00", "ZCTA5", "ZCTA",
                  "GEOID20", "GEOID10")
  col <- candidates[candidates %in% names(boundary)][1]
  if (is.na(col)) {
    stop("Could not find a ZCTA column in the boundary file.", call. = FALSE)
  }
  geom <- sf::st_geometry(boundary)
  if (is.na(sf::st_crs(geom))) sf::st_crs(geom) <- 4269
  zcta <- as.character(boundary[[col]])
  zcta <- sub("^.*US", "", zcta)  # drop any "8600000US" style prefix
  if (anyDuplicated(zcta)) {
    ids <- unique(zcta)
    geom <- do.call(c, lapply(ids, function(z) {
      sf::st_union(geom[zcta == z])
    }))
    zcta <- ids
  }
  sf::st_sf(ZCTA = zcta, geometry = geom)
}

#' Retrieve ZCTA boundaries from tigris
#'
#' Returns boundaries for ZCTAs whose codes start with any of `geo_list`, from
#' the Census vintage closest to the middle of `year_range` (2000, 2010 or
#' 2020). A year range that spans vintages is plotted on one boundary vintage.
#'
#' @param geo_list Character vector of ZCTAs or ZCTA prefixes.
#' @param year_range Years to be mapped.
#'
#' @return An sf object with columns `ZCTA` (character) and `geometry`.
#'
#' @keywords internal
#' @noRd
get_geometry <- function(geo_list, year_range) {
  year_plot <- .plot_vintage(year_range)
  boundary <- tryCatch(
    withCallingHandlers(
      tigris::zctas(starts_with = geo_list, year = year_plot, cb = TRUE,
                    progress_bar = FALSE),
      # the 2000 file splits discontiguous ZCTAs; .standardize_zcta() dissolves them
      warning = function(w) {
        if (grepl("discontiguous", conditionMessage(w))) {
          invokeRestart("muffleWarning")
        }
      }
    ),
    error = function(e) {
      stop("Could not download ZCTA boundaries from the Census Bureau (",
           year_plot, " vintage): ", conditionMessage(e), call. = FALSE)
    }
  )
  if (is.null(boundary) || nrow(boundary) == 0L) {
    stop("No ZCTA boundaries found for prefixes ",
         paste(geo_list, collapse = ", "), " in the ", year_plot,
         " Census boundary file.", call. = FALSE)
  }
  .standardize_zcta(boundary)
}
