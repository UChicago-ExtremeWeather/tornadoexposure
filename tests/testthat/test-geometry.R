test_that("plot vintage follows the middle of the year range", {
  expect_equal(.plot_vintage(1996:2005), 2000)
  expect_equal(.plot_vintage(2009:2011), 2010)
  expect_equal(.plot_vintage(2011), 2010)
  expect_equal(.plot_vintage(2018:2022), 2020)
  expect_equal(.plot_vintage(1996), 2000)
})

square <- function(x) sf::st_polygon(list(rbind(c(x, 0), c(x + 1, 0), c(x + 1, 1),
                                               c(x, 1), c(x, 0))))

test_that(".standardize_zcta handles each vintage's column and the 2000 quirks", {
  # 2020 file
  b20 <- sf::st_sf(ZCTA5CE20 = "64801", GEOID20 = "64801",
                   geometry = sf::st_sfc(square(0), crs = 4269))
  expect_equal(.standardize_zcta(b20)$ZCTA, "64801")
  # 2010 cartographic file, GEO_ID first
  b10 <- sf::st_sf(GEO_ID = "8600000US02139", ZCTA5 = "02139",
                   geometry = sf::st_sfc(square(0), crs = 4269))
  expect_equal(.standardize_zcta(b10)$ZCTA, "02139")
  # 2000 cartographic file: column ZCTA, no CRS, a ZCTA split in two polygons
  b00 <- sf::st_sf(ZCTA = c("02139", "02139", "64801"),
                   geometry = sf::st_sfc(square(0), square(5), square(10)))
  s <- .standardize_zcta(b00)
  expect_equal(s$ZCTA, c("02139", "64801"))
  expect_equal(sf::st_crs(s)$epsg, 4269L)
  expect_equal(nrow(s), 2L)
  expect_error(.standardize_zcta(sf::st_sf(A = 1, geometry = sf::st_sfc(square(0)))),
               "Could not find a ZCTA column")
})

test_that("get_geometry works for every vintage (needs internet)", {
  skip_on_cran()
  skip_if_offline("www2.census.gov")
  for (yr in c(2000, 2010, 2020)) {
    g <- get_geometry("648", yr)
    expect_s3_class(g, "sf")
    expect_true(all(startsWith(g$ZCTA, "648")))
    expect_equal(anyDuplicated(g$ZCTA), 0L)
    expect_false(is.na(sf::st_crs(g)))
  }
})
