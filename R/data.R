#' Tornado tracks with exposed ZCTAs
#'
#' A dataset containing tracks for each tornado with a magnitude of EF 1 or
#' greater in the United States between 1996-2025 (as of May 2026)
#'
#' @details Tornado tracks are stored as LINESTRING geometries, which are
#' generated from the raw dataset's start and end coordinates.
#'
#' For more details on the process of generating the tornado track geometries,
#' consult `data-raw/process_tracks.R`
#'
#' @format A data frame with 31,137 rows and 11 variables:
#' \describe{
#'   \item{tornado_id}{Unique identifier for tornado, created from raw
#'                        dataset's yr and om columns}
#'   \item{date}{Date of the tornado in yyyy-mm-dd format}
#'   \item{year}{Year of tornado}
#'   \item{month}{Month of tornado}
#'   \item{day}{Day of tornado}
#'   \item{magnitude}{Magnitude of the tornado on the (Enhanced) Fujita (E)F
#'   scale}
#'   \item{total_injury}{Number of injuries associated with tornado}
#'   \item{total_fatality}{Number of fatalities associated with tornado}
#'   \item{area_pct_affected}{Percentage of total ZCTA land area affected by tornado}
#'   \item{ZCTA}{The 5 digit code associated with the exposed ZCTA}
#'   \item{geometry}{A linestring representing the location and path of the tornado track}
#' }
#'
#' @source \url{https://www.spc.noaa.gov/wcm/data/1950-2025_all_tornadoes.csv}
#'
#' @references
#' NOAA Storm Prediction Center. Severe Weather Database.
#' https://www.spc.noaa.gov/wcm/ (accessed 2026-05-06)
"zcta_tracks"
