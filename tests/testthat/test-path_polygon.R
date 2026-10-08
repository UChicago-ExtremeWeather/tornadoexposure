test_that("rebuilt path polygons match tornado_area_m2 for every tornado", {
  tr <- tornado_tracks
  poly <- .path_polygon(tr, tr$wid_yd, tr$len_mi, tr$track_type)
  area <- as.numeric(sf::st_area(poly))
  # same function and same inputs as the pipeline: agreement to 1e-8 relative
  expect_equal(area, tr$tornado_area_m2, tolerance = 1e-8)
  expect_true(all(sf::st_is_valid(poly)))
  expect_equal(sf::st_crs(poly)$epsg, 5070L)
})

test_that("equal-area discs have area len * wid", {
  tr <- tornado_tracks[tornado_tracks$track_type == "point_equal_area", ]
  target <- tr$len_mi * 1609.344 * tr$wid_yd * 0.9144
  # 360-sided polygon: within 0.01% of a circle
  expect_equal(tr$tornado_area_m2 / target, rep(1, nrow(tr)), tolerance = 1e-4)
})

test_that(".path_polygon uses flat caps, discs and rejects bad input", {
  line <- sf::st_sfc(sf::st_linestring(rbind(c(-97, 35), c(-96.9, 35))),
                     crs = 4326)
  p <- .path_polygon(line, 100, 5, "line")
  len_m <- as.numeric(sf::st_length(sf::st_transform(line, 5070)))
  # flat caps: area is length * width (a round cap would add pi * r^2)
  expect_equal(as.numeric(sf::st_area(p)), len_m * 100 * 0.9144, tolerance = 1e-3)

  pt <- sf::st_sfc(sf::st_point(c(-97, 35)), crs = 4326)
  half <- .path_polygon(pt, 100, 0, "point_half_width")
  expect_equal(as.numeric(sf::st_area(half)), pi * (100 * 0.9144 / 2)^2,
               tolerance = 1e-3)
  eq <- .path_polygon(pt, 100, 2, "point_equal_area")
  expect_equal(as.numeric(sf::st_area(eq)), 2 * 1609.344 * 100 * 0.9144,
               tolerance = 1e-3)

  expect_error(.path_polygon(pt, 100, 0, "blob"), "track_type")
  expect_error(.path_polygon(pt, 0, 1, "point_equal_area"), "wid_yd")
  expect_error(.path_polygon(pt, 10, 0, "point_equal_area"), "len_mi")
})
