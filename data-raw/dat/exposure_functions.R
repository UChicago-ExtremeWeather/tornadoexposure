# Functions for the DAT columns of tornado_exposure and for dat_exposure_tract and dat_exposure_blockgroup. Source from the package root after
# data-raw/pipeline_functions.R, data-raw/land_functions.R and data-raw/population/population_functions.R, with sf_use_s2(FALSE).
#
# Polygon rule (the one rule of these tables): a DAT polygon belongs to a tornado when a DAT line linked to the tornado (tornado_dat_link) touches it
# (dat_polygon_line_link, line_share_in_polygon > 0: a zero test, not a cutoff). The footprint polygons are those rated EF0 to EF5; polygons with
# another efscale stay in dat_polygons and are counted in the documentation. A polygon with no date is never linked and is not used.
# Zones: for each tornado, the footprint is cut into zones by the highest rating that covers each part (a zone of rating r is the union of the
# polygons rated r minus the union of the polygons rated above r). The zones do not overlap, so their areas add up to the area of the union.
# Areas are land-only: a zone is intersected with the land-only shape of the unit (the unit polygon minus the Census water polygons).
# Residents: block population times the share of the block's land-only shape that a zone covers (uniform density on the block's land).

# A block whose land-only shape has an area at or below this (square meters) has no land: the subtraction leaves floating-point residue where a block boundary and a water boundary
# coincide (largest residue in the blocks the footprints reach: 1.4e-05; smallest land-only shape of a block with Census land area: 1.1; data-raw/qa/63_land_only_report.R). Such a block takes no part in the area shares, and
# its residents (a block with residents and a Census land area of 0, for example on water) are allocated by the share of the block polygon that a zone covers.
land_tolerance_m2 <- 1e-3

ef_rating <- function(x) ifelse(x %in% paste0("EF", 0:5), as.integer(substr(x, 3, 3)), NA_integer_)

# footprint polygon pairs (tornado_id, dat_polygon_id, rating) from the link tables
footprint_pairs <- function(tornado_dat_link, dat_polygon_line_link, dat_polygons) {
  touch <- dat_polygon_line_link[dat_polygon_line_link$line_share_in_polygon > 0, ]
  fp <- unique(merge(tornado_dat_link[, c("tornado_id", "dat_line_id")], touch, by = "dat_line_id")[, c("tornado_id", "dat_polygon_id")])
  fp$efscale <- dat_polygons$efscale[match(fp$dat_polygon_id, dat_polygons$objectid)]
  list(all = fp, used = fp[fp$efscale %in% paste0("EF", 0:5), ], other = fp[!fp$efscale %in% paste0("EF", 0:5), ])
}

# zones of one set of tornadoes: sf in EPSG:5070 with tornado_id, rating and geometry. `fp` has tornado_id, dat_polygon_id, efscale.
footprint_zones <- function(fp, dat_polygons) {
  ids <- unique(fp$dat_polygon_id); pol <- dat_polygons[match(ids, dat_polygons$objectid), ]
  repaired <- sum(!st_is_valid(pol)); P5 <- st_transform(st_make_valid(st_geometry(pol)), 5070)
  out <- list()
  for (tid in unique(fp$tornado_id)) {
    q <- fp[fp$tornado_id == tid, ]; rt <- ef_rating(q$efscale); g <- P5[match(q$dat_polygon_id, ids)]
    higher <- NULL
    for (r in sort(unique(rt), decreasing = TRUE)) {
      u <- st_union(g[rt == r]); z <- if (is.null(higher)) u else st_difference(u, higher)
      z <- .polygons_only(z)
      if (!all(st_is_empty(z)) && as.numeric(st_area(z)) > 0) out[[length(out) + 1]] <- st_sf(tornado_id = tid, rating = r, geometry = z)
      higher <- if (is.null(higher)) u else st_union(higher, u)
    }
  }
  z <- do.call(rbind, out); attr(z, "polygons_repaired") <- repaired; z
}

# pieces: intersections of the zones with land-only unit shapes. `land` is an sfc of land shapes with the unit keys in `key`.
zone_pieces <- function(zones, land, key) {
  u <- st_sf(key = key, geometry = land); u <- u[!st_is_empty(u), ]
  x <- suppressWarnings(st_intersection(zones, u)); if (!nrow(x)) return(data.frame(tornado_id = character(), rating = integer(), key = character(), area_m2 = numeric()))
  x <- st_collection_extract(x, "POLYGON"); x$area_m2 <- as.numeric(st_area(x))
  x <- st_drop_geometry(x); x <- x[x$area_m2 > 0, ]
  aggregate(area_m2 ~ tornado_id + rating + key, data = x, FUN = sum)
}

# One state and one boundary year of the block pass. `zones`: the zones (EPSG:5070) of the tornadoes of this boundary year that reach the state;
# `pts`: damage points (sf, EPSG:4326, columns objectid and date) to place in blocks. Returns
#   pieces  tornado_id, rating, GEOID, area_m2 (zone area inside the land-only block shape), land_m2 of the block
#   pieces_polygon  the same for blocks with residents and no land (area_m2 inside the block polygon, poly_m2 the polygon area)
#   blocks  GEOID, ALAND, land_m2, area_m2 (polygon), pop, ZCTA of every block in the tracts the zones reach (the denominators of tracts and block groups)
#   points  objectid, GEOID of the points that lie in a block
# Stops on a block with NA population, a duplicated GEOID, or a share above 1 + 1e-9. Uses the cached block results of data-raw/add_population.R.
block_pass <- function(vintage, st, zones, pts, cores = 1) {
  sfx <- substr(vintage, 3, 4); gcol <- if (vintage == 2000) "BLKIDFP00" else paste0("GEOID", sfx); set <- water_set[[as.character(vintage)]]
  cache <- readRDS(pop_cache("work", sprintf("%s_%s.rds", vintage, st$state_code)))$blocks
  if (anyNA(cache$pop)) stop("Block population is NA in ", vintage, " ", st$state, ".", call. = FALSE)
  if (anyDuplicated(cache$GEOID)) stop("Duplicated block GEOIDs in ", vintage, " ", st$state, ".", call. = FALSE)
  zip <- download_cached(block_url(vintage, st$state_code), record = FALSE)
  td <- tempfile("blk"); dir.create(td); utils::unzip(zip, exdir = td); on.exit(unlink(td, recursive = TRUE))
  shp <- list.files(td, pattern = "[.]shp$", full.names = TRUE); lay <- tools::file_path_sans_ext(basename(shp))
  zb <- st_bbox(st_transform(st_geometry(zones), 4269))
  b <- sf::read_sf(shp, query = sprintf("SELECT %s AS GEOID, ALAND%s AS ALAND FROM %s", gcol, sfx, lay)); b$ALAND <- as.numeric(b$ALAND)
  if (anyDuplicated(b$GEOID)) stop("Duplicated block GEOIDs in the ", vintage, " ", st$state, " block file.", call. = FALSE)
  # blocks the zones touch (planar, EPSG:5070), then every block of the tracts they lie in
  zb <- st_as_sfc(st_bbox(c(xmin = zb[[1]], ymin = zb[[2]], xmax = zb[[3]], ymax = zb[[4]]), crs = st_crs(b)))
  inbox <- which(st_intersects(st_geometry(b), zb, sparse = FALSE)[, 1])
  b5 <- st_transform(st_make_valid(st_geometry(b)[inbox]), 5070)
  hit <- lengths(st_intersects(b5, st_geometry(zones))) > 0
  tracts <- unique(substr(b$GEOID[inbox][hit], 1, 11))
  sel <- which(substr(b$GEOID, 1, 11) %in% tracts)
  g <- st_geometry(b)[sel]; inv <- sum(!st_is_valid(g)); g5 <- st_transform(st_make_valid(g), 5070)
  L <- land_of(g5, set, cores)
  no_land <- L$land_m2 <= land_tolerance_m2; residue <- L$land_m2[no_land]
  lst <- unclass(L$land); for (i in which(no_land)) lst[[i]] <- sf::st_polygon(); L$land <- st_sfc(lapply(lst, identity), crs = st_crs(g5)); L$land_m2[no_land] <- 0
  blk <- data.frame(GEOID = b$GEOID[sel], ALAND = b$ALAND[sel], land_m2 = L$land_m2, area_m2 = L$area_m2, stringsAsFactors = FALSE)
  blk$pop <- cache$pop[match(blk$GEOID, cache$GEOID)]; blk$ZCTA <- cache$ZCTA[match(blk$GEOID, cache$GEOID)]
  stopifnot(!anyNA(blk$pop))
  pc <- zone_pieces(zones, L$land, blk$GEOID); names(pc)[names(pc) == "key"] <- "GEOID"; pc$land_m2 <- blk$land_m2[match(pc$GEOID, blk$GEOID)]
  fb <- which(no_land & blk$pop > 0)       # blocks with residents and no land: residents by the share of the block polygon
  pcp <- if (length(fb)) zone_pieces(zones, g5[fb], blk$GEOID[fb]) else data.frame(tornado_id = character(), rating = integer(), key = character(), area_m2 = numeric())
  names(pcp)[names(pcp) == "key"] <- "GEOID"; pcp$poly_m2 <- blk$area_m2[match(pcp$GEOID, blk$GEOID)]
  if (any(pcp$area_m2 > pcp$poly_m2 * (1 + 1e-9))) stop(sum(pcp$area_m2 > pcp$poly_m2 * (1 + 1e-9)), " pieces cover more than the polygon of a block in ", vintage, " ", st$state, ".", call. = FALSE)
  if (any(pc$area_m2 > pc$land_m2 * (1 + 1e-9))) stop(sum(pc$area_m2 > pc$land_m2 * (1 + 1e-9)), " pieces cover more than the land shape of a block in ", vintage, " ", st$state, ".", call. = FALSE)
  # damage points in blocks
  pb <- data.frame(objectid = integer(), GEOID = character())
  if (!is.null(pts) && nrow(pts)) {
    pts <- st_transform(pts, st_crs(b)); h <- st_intersects(st_geometry(pts), st_geometry(b)); has <- lengths(h) > 0
    if (any(has)) pb <- data.frame(objectid = rep(pts$objectid[has], lengths(h[has])), GEOID = b$GEOID[unlist(h[has])], stringsAsFactors = FALSE)
  }
  list(pieces = pc, pieces_polygon = pcp, blocks = blk, points = pb, invalid_repaired = inv, blocks_water_touched = length(L$water_touched), blocks_read = nrow(b),
       no_land = c(blocks = sum(no_land), with_residents = length(fb), residents = sum(blk$pop[fb]), largest_residue_m2 = if (length(residue)) max(residue) else 0, aland_positive = sum(no_land & blk$ALAND > 0)))
}

# The largest one-sided distance (km) among a tornado's linked DAT lines, from tornado_dat_link; NA where the tornado has no linked line.
link_dist_max <- function(tornado_id, link) {
  m <- tapply(link$one_sided_dist_km, link$tornado_id, max)
  as.numeric(m[match(tornado_id, names(m))])
}
