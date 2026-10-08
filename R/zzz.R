#' @importFrom ggplot2 .data
NULL
.onLoad <- function(libname, pkgname) {
  options(tigris_use_cache = TRUE)
}
