# Helpers shared by the QA scripts in this folder.
# Run every script from the package root, for example:
#   Rscript data-raw/qa/04_loss_reconciliation.R
# Downloads are cached in data-raw/qa/cache/ and results are written to
# data-raw/qa/out/; both folders are git-ignored.

qa_out <- function(f) {
  dir.create("data-raw/qa/out", recursive = TRUE, showWarnings = FALSE)
  file.path("data-raw/qa/out", f)
}

qa_cache <- function(f) {
  dir.create("data-raw/qa/cache", recursive = TRUE, showWarnings = FALSE)
  file.path("data-raw/qa/cache", f)
}

# The SPC file the package was built from (same release year as the data). A
# warning is given if its checksum differs from data-raw/provenance.txt, which
# happens when SPC has revised the file since the build.
qa_spc_csv <- function() {
  e <- new.env()
  load("data/tornado_exposure.rda", envir = e)
  year <- max(e$tornado_exposure$year)
  f <- qa_cache(sprintf("1950-%s_all_tornadoes.csv", year))
  if (!file.exists(f)) {
    download.file(
      sprintf("https://www.spc.noaa.gov/wcm/data/1950-%s_all_tornadoes.csv", year),
      f, mode = "wb", quiet = TRUE)
  }
  prov <- readLines("data-raw/provenance.txt")
  built <- sub("^SPC file md5: ", "", grep("^SPC file md5:", prov, value = TRUE))
  if (!identical(unname(tools::md5sum(f)), built)) {
    warning("The SPC file in the cache differs from the one the package was ",
            "built from (see data-raw/provenance.txt). Delete ", f,
            " and rebuild the data, or expect small differences.", call. = FALSE)
  }
  f
}

# Index of NCEI Storm Events bulk files
qa_ncei_index <- function() {
  f <- qa_cache("ncei_index.html")
  if (!file.exists(f)) {
    download.file("https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/",
                  f, quiet = TRUE)
  }
  f
}

# Path of the NCEI Storm Events details file of a year (downloaded into the cache if it is not there)
qa_ncei_file <- function(year) {
  dest <- list.files(qa_cache("ncei"), pattern = paste0("_d", year, "_"), full.names = TRUE)
  if (length(dest)) return(dest[1])
  idx <- readLines(qa_ncei_index(), warn = FALSE)
  files <- unique(regmatches(idx, regexpr("StormEvents_details-ftp_v1.0_d[0-9]{4}_c[0-9]{8}.csv.gz", idx)))
  f <- files[grepl(paste0("_d", year, "_"), files)]
  dir.create(qa_cache("ncei"), showWarnings = FALSE)
  dest <- file.path(qa_cache("ncei"), f)
  options(timeout = max(600, getOption("timeout")))
  download.file(paste0("https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/", f), dest, mode = "wb", quiet = TRUE)
  dest
}
