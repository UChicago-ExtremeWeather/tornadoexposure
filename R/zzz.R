#' @importFrom ggplot2 .data
#' @importFrom sf st_geometry
NULL
.onLoad <- function(libname, pkgname) {
  options(tigris_use_cache = TRUE)
}

# A number computed by a QA script and kept in data-raw/readme/numbers.csv. Used only when the documentation is built
# (devtools::document() runs from the package root).
.doc_number <- function(name) {
  n <- utils::read.csv("data-raw/readme/numbers.csv", stringsAsFactors = FALSE)
  n$value[match(name, n$name)]
}
