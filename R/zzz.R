#' @importFrom ggplot2 .data
#' @importFrom sf st_geometry
NULL
.onLoad <- function(libname, pkgname) {
  options(tigris_use_cache = TRUE)
}
