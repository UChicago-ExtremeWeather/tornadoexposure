test_that("get_data returns a plain data frame, one row per tornado-ZCTA", {
  d <- get_data(geo_list = "648", year_range = 2011, magnitude = 5)
  expect_s3_class(d, "data.frame")
  expect_false(inherits(d, "sf"))
  expect_false(anyDuplicated(d[c("tornado_id", "ZCTA")]) > 0)
  expect_true("track_type" %in% names(d))
  expect_true(all(startsWith(d$ZCTA, "648")))
})

test_that("prefix matching works for 1 to 5 digits", {
  d1 <- get_data(geo_list = "6", year_range = 2011)
  d3 <- get_data(geo_list = "648", year_range = 2011)
  d5 <- get_data(geo_list = "64804", year_range = 2011)
  expect_true(all(startsWith(d1$ZCTA, "6")))
  expect_true(nrow(d1) >= nrow(d3) && nrow(d3) >= nrow(d5))
  expect_true(all(d5$ZCTA == "64804"))
  both <- get_data(geo_list = c("64804", "64840"), year_range = 2011)
  expect_setequal(unique(both$ZCTA), c("64804", "64840"))
})

test_that("leading zeros are preserved", {
  d <- get_data(geo_list = "02", year_range = 1996:2025)
  expect_gt(nrow(d), 0)
  expect_true(all(startsWith(d$ZCTA, "02")))
  expect_true(all(nchar(d$ZCTA) == 5L))
})

test_that("magnitude vector filters", {
  d <- get_data(geo_list = "6", year_range = 2011:2013, magnitude = c(3, 5))
  expect_true(all(d$magnitude %in% c(3, 5)))
  all_mag <- get_data(geo_list = "6", year_range = 2011:2013)
  expect_true(nrow(all_mag) > nrow(d))
})

test_that("area_thresh keeps rows at or above the threshold", {
  any_overlap <- get_data(geo_list = "6", year_range = 2011:2013)
  d <- get_data(geo_list = "6", year_range = 2011:2013, area_thresh = 0.05)
  expect_true(all(d$area_prop_affected >= 0.05))
  expect_lt(nrow(d), nrow(any_overlap))
  expect_equal(nrow(get_data(geo_list = "6", year_range = 2011:2013,
                             area_thresh = 1)),
               sum(any_overlap$area_prop_affected >= 1))
})

test_that("empty results give a message and an empty data frame", {
  expect_message(
    d <- get_data(geo_list = "99999", year_range = 2011),
    "No tornado exposures found"
  )
  expect_equal(nrow(d), 0L)
  expect_equal(names(d), names(tornado_exposure))
})
