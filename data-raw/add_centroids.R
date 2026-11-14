# Builds `zcta_centroids`: one population-weighted centroid per ZCTA and vintage
# (2000, 2010, 2020), used for distance exposure (centroid_dist_km).
#
# Run from the package root after data-raw/add_population.R (it reuses the
# per-state block populations and block-to-ZCTA assignments cached there):
#   Rscript data-raw/add_centroids.R
#
# Method: each block's internal point (fields INTPTLAT/INTPTLON with the
# vintage suffix 00, 10 or 20 in the Census TIGER/Line block files) is weighted
# by the block's population, and the centroid is the weighted mean of those
# points on the sphere (unit vectors, so no projection is involved). Blocks are
# assigned to ZCTAs through their internal point, as for zcta_pop.
#   * ZCTAs with no residents use the geometric centroid of the polygon
#     (centroid_type = "geometric"); if that point falls outside the polygon, a
#     point on the polygon surface is used instead.
#   * centroid_in_zcta says whether the final point lies inside its own polygon.
# Coordinates are NAD83 (EPSG:4269), as computed (not rounded).
# zcta_land_area_m2 is the Census land area (ALAND), zcta_polygon_area_m2 the area of the full TIGER/Line ZCTA polygon in EPSG:5070, and
# zcta_land_shape_area_m2 the area of the land-only shape (the polygon minus the Census water polygons inside it, data-raw/land_functions.R).
source("data-raw/pipeline_functions.R")            # load_zctas(): the full TIGER/Line polygons and their areas, as used for tornado_exposure
source("data-raw/land_functions.R")
source("data-raw/population/population_functions.R")
suppressMessages(library(dplyr))
states <- pop_states()
ll2xyz <- function(lon, lat) { lo <- lon * pi / 180; la <- lat * pi / 180; cbind(cos(la) * cos(lo), cos(la) * sin(lo), sin(la)) }
xyz2ll <- function(x, y, z) data.frame(lon = atan2(y, x) * 180 / pi, lat = atan2(z, sqrt(x^2 + y^2)) * 180 / pi)
pt5070 <- function(lon, lat) sf::st_geometry(sf::st_transform(sf::st_as_sf(data.frame(lon = lon, lat = lat), coords = c("lon", "lat"), crs = 4269), 5070))
out <- list(); report <- list(); dropped <- list()
for (v in c(2000, 2010, 2020)) {
  acc <- list(); sfx <- substr(v, 3, 4); n_pts <- 0; n_blocks <- 0
  for (i in seq_len(nrow(states))) {
    st <- states[i, ]
    wf <- pop_cache("work", sprintf("%s_%s.rds", v, st$state_code))
    if (!file.exists(wf)) stop("Missing cached population results: ", wf, ". Run data-raw/add_population.R first.")
    bl <- readRDS(wf)$blocks
    zip <- download_cached(block_url(v, st$state_code), record = FALSE)
    td <- tempfile("dbf"); dir.create(td)
    fl <- utils::unzip(zip, list = TRUE)$Name; dbf <- fl[grepl("\\.dbf$", fl)]
    utils::unzip(zip, files = dbf, exdir = td)
    d <- sf::st_read(file.path(td, dbf), quiet = TRUE); unlink(td, recursive = TRUE)
    gcol <- if (v == 2000) "BLKIDFP00" else paste0("GEOID", sfx)
    d <- data.frame(GEOID = d[[gcol]], lat = as.numeric(d[[paste0("INTPTLAT", sfx)]]), lon = as.numeric(d[[paste0("INTPTLON", sfx)]]))
    j <- merge(bl, d, by = "GEOID")
    n_blocks <- n_blocks + nrow(bl); n_pts <- n_pts + sum(is.finite(j$lat) & is.finite(j$lon))
    j <- j[!is.na(j$ZCTA) & is.finite(j$lat) & is.finite(j$lon), ]
    j$pop[is.na(j$pop)] <- 0
    xyz <- ll2xyz(j$lon, j$lat)
    acc[[i]] <- data.frame(ZCTA = j$ZCTA, nb = 1L, pop = j$pop, x = j$pop * xyz[, 1], y = j$pop * xyz[, 2], z = j$pop * xyz[, 3])
    message(v, " ", st$state)
  }
  stopifnot(n_pts == n_blocks)   # every block has an internal point
  a <- bind_rows(acc) %>% group_by(ZCTA) %>% summarise(zcta_pop = sum(pop), n_blocks = sum(nb), sx = sum(x), sy = sum(y), sz = sum(z), .groups = "drop")
  zfull <- load_zctas(v); zl <- zcta_land(v, cores = as.integer(Sys.getenv("NPROC", "3")))
  stopifnot(!anyDuplicated(zfull$ZCTA), identical(zl$d$ZCTA, zfull$ZCTA))
  z <- zcta_layer(v); z$ALAND <- zfull$ALAND[match(z$ZCTA, zfull$ZCTA)]; z$poly_m2 <- zfull$zcta_polygon_area_m2[match(z$ZCTA, zfull$ZCTA)]; z$land_shape_m2 <- zl$d$land_m2[match(z$ZCTA, zfull$ZCTA)]
  # The block data cover the 50 states, DC and Puerto Rico. ZCTAs with no block at
  # all lie outside that area (the 2020 file has Guam, the Northern Marianas,
  # American Samoa and the US Virgin Islands) and get no centroid. Stop if any
  # other ZCTA is dropped.
  no_block <- !z$ZCTA %in% a$ZCTA
  stopifnot(all(substr(z$ZCTA[no_block], 1, 3) %in% c("969", "008") | z$ZCTA[no_block] == "96799"))
  message(v, ": ZCTAs without block data, dropped: ", sum(no_block), " (", paste(z$ZCTA[no_block], collapse = " "), ")")
  dropped[[as.character(v)]] <- sum(no_block)
  z <- z[!no_block, ]; z5 <- sf::st_transform(z, 5070)
  c1 <- a[match(z$ZCTA, a$ZCTA), ]; c1$ZCTA <- z$ZCTA
  c1$zcta_pop <- ifelse(is.na(c1$zcta_pop), 0, c1$zcta_pop)
  c1$n_blocks <- ifelse(is.na(c1$n_blocks), 0L, c1$n_blocks)
  pc <- xyz2ll(c1$sx, c1$sy, c1$sz)
  populated <- c1$zcta_pop > 0
  gc <- sf::st_coordinates(sf::st_transform(sf::st_centroid(sf::st_geometry(z5)), 4269))
  lon <- ifelse(populated, pc$lon, gc[, 1]); lat <- ifelse(populated, pc$lat, gc[, 2])
  inside_of <- function(lon, lat) {
    p <- pt5070(lon, lat)
    h <- sf::st_intersects(p, sf::st_geometry(z5))
    vapply(seq_along(h), function(k) k %in% h[[k]], logical(1))
  }
  inside <- inside_of(lon, lat)
  fix <- !populated & !inside      # geometric centroid outside its own polygon
  if (any(fix)) {
    ps <- sf::st_coordinates(sf::st_transform(sf::st_point_on_surface(sf::st_geometry(z5)[fix]), 4269))
    lon[fix] <- ps[, 1]; lat[fix] <- ps[, 2]
    inside[fix] <- inside_of(lon, lat)[fix]
  }
  stopifnot(all(inside[!populated]))
  out[[as.character(v)]] <- data.frame(ZCTA = c1$ZCTA, vintage = as.integer(v), lon = lon, lat = lat,
    centroid_type = ifelse(populated, "population", "geometric"), centroid_in_zcta = inside, zcta_pop = as.integer(c1$zcta_pop),
    zcta_land_area_m2 = z$ALAND, zcta_polygon_area_m2 = z$poly_m2, zcta_land_shape_area_m2 = z$land_shape_m2, stringsAsFactors = FALSE)
  report[[as.character(v)]] <- c(vintage = v, zctas = nrow(c1), dropped_no_blocks = dropped[[as.character(v)]], zero_resident = sum(!populated), pop_centroid_outside = sum(populated & !inside), geom_moved_to_surface = sum(fix))
}
zcta_centroids <- bind_rows(out)
zcta_centroids <- zcta_centroids[order(zcta_centroids$vintage, zcta_centroids$ZCTA), ]; rownames(zcta_centroids) <- NULL
print(do.call(rbind, report))
stopifnot(!anyNA(zcta_centroids[, c("ZCTA", "vintage", "lon", "lat", "centroid_type", "centroid_in_zcta", "zcta_pop")]), !anyDuplicated(zcta_centroids[, c("ZCTA", "vintage")]))
usethis::use_data(zcta_centroids, overwrite = TRUE, compress = "xz")
cat("zcta_centroids:", nrow(zcta_centroids), "rows,", round(file.size("data/zcta_centroids.rda") / 1024), "KB\n")
water_provenance()   # URLs, sizes, md5 and dates of the water files used for the land-only shapes
