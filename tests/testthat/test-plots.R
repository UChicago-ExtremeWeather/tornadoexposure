test_that("generate_feature aggregates per ZCTA", {
  d <- data.frame(ZCTA = c("a", "a", "b"), tornado_id = c("x", "y", "x"),
                  magnitude = c(2, 4, 3), total_injury = c(1, 2, 3),
                  total_fatality = c(0, 1, 0))
  expect_equal(generate_feature(d, "tornado_id")$value, c(2, 1))
  expect_equal(generate_feature(d, "magnitude")$value, c(3, 3))
  expect_equal(generate_feature(d, "total_injury")$value, c(3, 3))
  expect_error(generate_feature(d, "nope"))
})

test_that("map_exposure and add_tracks validate before downloading", {
  expect_error(map_exposure(geo_list = "648", year_range = 2011, feature = "x"),
               "feature must be")
  expect_error(add_tracks(geo_list = "648", year_range = 2011, plot = 1),
               "plot must be a ggplot")
  expect_error(map_exposure(c(648), 2011), 'geography must be "zcta"')
})

test_that("maps and tracks draw (needs internet)", {
  skip_on_cran()
  skip_if_offline("www2.census.gov")
  p <- map_exposure(geo_list = "648", year_range = 2011, feature = "tornado_id",
                    magnitude = 5)
  expect_s3_class(p, "ggplot")
  for (g in c("track", "polygon")) {
    p2 <- add_tracks(geo_list = "648", year_range = 2011, plot = p,
                     magnitude = 5, geometry = g)
    expect_s3_class(p2, "ggplot")
    expect_gt(length(p2$layers), length(p$layers))
  }
  # empty result: plot unchanged, no crash
  expect_message(
    p3 <- add_tracks(geo_list = "648", year_range = 2011, plot = p,
                     magnitude = 1, area_thresh = 1),
    "No tornado exposures found"
  )
  expect_equal(length(p3$layers), length(p$layers))
})
