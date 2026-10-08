# Internal helpers: argument validation shared by get_data(), map_exposure() and
# add_tracks().

.exposure <- function() tornadoexposure::tornado_exposure
.tracks <- function() tornadoexposure::tornado_tracks
.data_years <- function() range(.exposure()$year)

# Threshold validators. To add a new exposure definition (for example
# pop_thresh), add one entry here and pass it in the `thresholds` list of the
# calling function. Each validator returns the checked value.
.threshold_checks <- list(
  area_thresh = function(x) {
    .check_proportion(x, "area_thresh",
                      "the share of the ZCTA's land area covered by the path")
  }
)

.check_proportion <- function(x, name, what) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x)) {
    stop(name, " must be a single number in (0, 1] or NULL (any overlap).",
         call. = FALSE)
  }
  if (x == 0) {
    stop(name, " = 0 is not allowed. ZCTAs the path did not touch are never ",
         "returned, so 0 would mean nothing. Use ", name, " = NULL (the ",
         "default) to return any exposure, or a number in (0, 1].",
         call. = FALSE)
  }
  if (x < 0 || x > 1) {
    stop(name, " must be a proportion in (0, 1], for example ", name,
         " = 0.05 for ", what, " of at least 5%. Got ", x, ".", call. = FALSE)
  }
  x
}

.validate_geography <- function(geography, fn) {
  ok <- is.character(geography) && length(geography) == 1L &&
    !is.na(geography) && tolower(geography) == "zcta"
  if (!ok) {
    stop('geography must be "zcta". Did you mean ', fn,
         "(geo_list = ..., year_range = ...)? Use named arguments.",
         call. = FALSE)
  }
  "zcta"
}

.validate_geo_list <- function(geo_list) {
  if (is.null(geo_list) || length(geo_list) == 0L) {
    stop("geo_list is required: a character vector of ZCTAs or ZCTA prefixes ",
         '(1 to 5 digits), for example geo_list = "648".', call. = FALSE)
  }
  if (anyNA(geo_list)) stop("geo_list must not contain missing values.",
                            call. = FALSE)
  if (is.numeric(geo_list)) {
    if (any(geo_list != round(geo_list)) || any(geo_list < 0) ||
        any(geo_list > 99999)) {
      stop("Numeric geo_list values must be whole numbers from 0 to 99999. ",
           "Pass ZCTAs as character strings, for example \"02139\".",
           call. = FALSE)
    }
    geo_chr <- as.character(as.integer(geo_list))
    short <- geo_chr[nchar(geo_chr) < 5L]
    if (length(short) > 0L) {
      warning("geo_list is numeric, so leading zeros are lost (02139 becomes ",
              "2139) and Northeast ZCTAs will not match. Treating ",
              paste(unique(short), collapse = ", "),
              " as prefixes. Pass character strings instead, for example ",
              'geo_list = "02139".', call. = FALSE)
    }
    geo_list <- geo_chr
  }
  if (!is.character(geo_list)) {
    stop("geo_list must be a character vector of ZCTAs or ZCTA prefixes ",
         "(1 to 5 digits).", call. = FALSE)
  }
  bad <- geo_list[!grepl("^[0-9]{1,5}$", geo_list)]
  if (length(bad) > 0L) {
    stop("geo_list must contain only ZCTA codes or prefixes of 1 to 5 digits. ",
         "Invalid: ", paste(utils_head(unique(bad)), collapse = ", "), ".",
         call. = FALSE)
  }
  unique(geo_list)
}

utils_head <- function(x, n = 5L) if (length(x) > n) c(x[seq_len(n)], "...") else x

.validate_year_range <- function(year_range) {
  if (is.null(year_range) || length(year_range) == 0L) {
    stop("year_range is required, for example year_range = 2010:2015.",
         call. = FALSE)
  }
  if (!is.numeric(year_range) || anyNA(year_range) ||
      any(year_range != round(year_range))) {
    stop("year_range must be whole years, for example year_range = 2010:2015.",
         call. = FALSE)
  }
  years <- sort(unique(as.integer(year_range)))
  rng <- .data_years()
  inside <- years >= rng[1] & years <= rng[2]
  if (!any(inside)) {
    stop("year_range (", paste(range(years), collapse = "-"), ") is outside ",
         "the years in the data (", rng[1], "-", rng[2], ").", call. = FALSE)
  }
  if (!all(inside)) {
    warning("Years outside the data (", rng[1], "-", rng[2], ") have no ",
            "tornadoes and are ignored: ",
            paste(utils_head(years[!inside]), collapse = ", "), ".",
            call. = FALSE)
  }
  years
}

.validate_magnitude <- function(magnitude) {
  if (!is.numeric(magnitude) || length(magnitude) == 0L || anyNA(magnitude) ||
      any(magnitude != round(magnitude)) || any(!magnitude %in% 1:5)) {
    stop("magnitude must be whole numbers from 1 to 5 (EF0 tornadoes are not ",
         "in the data). For example, magnitude = 3:5 keeps EF3 and above.",
         call. = FALSE)
  }
  sort(unique(as.integer(magnitude)))
}

.validate_thresholds <- function(thresholds) {
  given <- names(Filter(Negate(is.null), thresholds))
  if (length(given) > 1L) {
    stop("Only one exposure definition can be used per call, but you supplied ",
         paste(given, collapse = " and "), ". Use one threshold argument at ",
         "a time, or none to return any overlap.", call. = FALSE)
  }
  if (length(given) == 0L) {
    return(list(name = "overlap", value = NULL))
  }
  list(name = given, value = .threshold_checks[[given]](thresholds[[given]]))
}

# Validates the arguments common to get_data(), map_exposure() and add_tracks().
# `fn` is the calling function's name (used in messages). `geo_list` and
# `year_range` are NULL when the caller did not supply them.
.validate_args <- function(fn, geography, geo_list, year_range, magnitude,
                           thresholds = list()) {
  geography <- .validate_geography(geography, fn)
  geo_list <- .validate_geo_list(geo_list)
  year_range <- .validate_year_range(year_range)
  magnitude <- .validate_magnitude(magnitude)
  definition <- .validate_thresholds(thresholds)
  list(geography = geography, geo_list = geo_list, year_range = year_range,
       magnitude = magnitude, definition = definition$name,
       threshold = definition$value)
}

# Human-readable description of a validated request (for messages and titles)
.describe_request <- function(v) {
  yrs <- if (length(v$year_range) == 1L) {
    as.character(v$year_range)
  } else {
    paste0(min(v$year_range), "-", max(v$year_range))
  }
  mags <- if (length(v$magnitude) == 1L) {
    paste0("EF", v$magnitude)
  } else {
    paste0("EF", paste(range(v$magnitude), collapse = "-"))
  }
  def <- if (v$definition == "overlap") {
    "any overlap"
  } else {
    paste0(v$definition, " >= ", v$threshold)
  }
  paste0("ZCTAs starting with ", paste(v$geo_list, collapse = ", "), ", ",
         yrs, ", ", mags, ", ", def)
}
