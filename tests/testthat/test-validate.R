test_that("swapped arguments give a helpful error", {
  expect_error(get_data(c(648), 2010:2015),
               'geography must be "zcta".*get_data\\(geo_list = \\.\\.\\., year_range = \\.\\.\\.\\)')
  expect_error(map_exposure(c(648), 2010:2015), 'geography must be "zcta"')
})

test_that("missing arguments are reported", {
  expect_error(get_data(year_range = 2011), "geo_list is required")
  expect_error(get_data(geo_list = "648"), "year_range is required")
})

test_that("area_thresh = 0 and out-of-range values error", {
  expect_error(get_data(geo_list = "648", year_range = 2011, area_thresh = 0),
               "area_thresh = 0 is not allowed.*NULL")
  expect_error(get_data(geo_list = "648", year_range = 2011, area_thresh = 1.5),
               "proportion in \\(0, 1\\]")
  expect_error(get_data(geo_list = "648", year_range = 2011, area_thresh = -0.1),
               "proportion in \\(0, 1\\]")
  expect_error(get_data(geo_list = "648", year_range = 2011, area_thresh = "a"),
               "single number")
})

test_that("magnitude is validated", {
  expect_error(get_data(geo_list = "648", year_range = 2011, magnitude = 0:2),
               "whole numbers from 1 to 5")
  expect_error(get_data(geo_list = "648", year_range = 2011, magnitude = 6),
               "whole numbers from 1 to 5")
})

test_that("threshold arguments are mutually exclusive", {
  thresholds <- list(area_thresh = 0.1, other_thresh = 0.2)
  expect_error(.validate_thresholds(thresholds),
               "Only one exposure definition.*area_thresh and other_thresh")
  expect_equal(.validate_thresholds(list(area_thresh = NULL))$name, "overlap")
  expect_equal(.validate_thresholds(list(area_thresh = 0.5))$value, 0.5)
})

test_that("year_range outside the data errors; partly outside warns", {
  expect_error(get_data(geo_list = "648", year_range = 1980:1990),
               "outside the years in the data")
  expect_warning(
    d <- get_data(geo_list = "648", year_range = 1990:1997),
    "have no tornadoes"
  )
  expect_true(all(d$year %in% 1996:1997))
})

test_that("numeric ZCTAs warn about leading zeros; strings do not", {
  expect_warning(suppressMessages(get_data(geo_list = 2139, year_range = 2011)),
                 "leading zeros are lost")
  expect_no_warning(suppressMessages(
    get_data(geo_list = "02139", year_range = 2011)))
  expect_error(get_data(geo_list = "abc", year_range = 2011), "1 to 5 digits")
  expect_error(get_data(geo_list = "123456", year_range = 2011),
               "1 to 5 digits")
})
