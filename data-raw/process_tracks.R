# Build the bundled datasets `tornado_exposure` and `tornado_tracks`.
#
# Source: NOAA Storm Prediction Center (SPC) severe weather database
# (tornado records) and Census Bureau ZCTA boundaries (via tigris).
#
# To refresh for a new year: change `latest_year`, rerun this script from the
# package root, then run devtools::document() and devtools::check().

library(readr)
library(dplyr)
library(sf)
library(tigris)

latest_year <- 2025
noaa_url <- sprintf(
  "https://www.spc.noaa.gov/wcm/data/1950-%s_all_tornadoes.csv", latest_year
)
access_date <- Sys.Date()
options(tigris_use_cache = TRUE)

# equal-area CRS used for every area calculation (NAD83 / Conus Albers)
area_crs <- 5070
# SPC reports width in yards; NOAA documents a 30 foot (10 yard) minimum width
yd_to_m <- 0.9144
min_width_yd <- 10

# ---- 1. read and filter raw SPC records ------------------------------------

raw <- read_csv(noaa_url, show_col_types = FALSE)
message("Raw records: ", nrow(raw))

tornadoes <- raw %>%
  filter(yr >= 1996) %>%
  # sg == 1 is the entire-track record. Other rows are state segments or
  # continuing county FIPS records (sg == 2 or -9) that repeat the same om.
  filter(sg == 1) %>%
  # drop EF0 and unknown (-9) magnitudes
  filter(mag >= 1) %>%
  mutate(tornado_id = paste(yr, om, sep = "_"))

message("Tornadoes after year >= 1996, sg == 1, magnitude >= 1: ",
        nrow(tornadoes))

# PROVISIONAL (awaiting Kate): a few distinct tornadoes share the same yr and
# om in SPC (each has its own sg == 1 row, coordinates and totals). Suffix
# them _1, _2 so tornado_id is unique.
dup_id <- duplicated(tornadoes$tornado_id) |
  duplicated(tornadoes$tornado_id, fromLast = TRUE)
message("Rows sharing a tornado_id with another sg == 1 row: ", sum(dup_id),
        " (", paste(unique(tornadoes$tornado_id[dup_id]), collapse = ", "), ")")
tornadoes$tornado_id[dup_id] <- paste0(
  tornadoes$tornado_id[dup_id], "_",
  ave(seq_len(sum(dup_id)), tornadoes$tornado_id[dup_id], FUN = seq_along)
)
stopifnot(!anyDuplicated(tornadoes$tornado_id))

# ---- 2. classify tracks as lines or points ---------------------------------

# no valid start location: cannot be placed
no_start <- is.na(tornadoes$slon) | is.na(tornadoes$slat) |
  tornadoes$slon == 0 | tornadoes$slat == 0
message("Dropped, no valid start location: ", sum(no_start))
tornadoes <- tornadoes[!no_start, ]

# missing or zero end coordinates (unknown end), or end == start, are treated
# as a point and buffered by half the width around the start
bad_end <- is.na(tornadoes$elon) | is.na(tornadoes$elat) |
  tornadoes$elon == 0 | tornadoes$elat == 0
same_pt <- !bad_end & tornadoes$slon == tornadoes$elon &
  tornadoes$slat == tornadoes$elat
tornadoes$track_type <- ifelse(bad_end | same_pt, "point", "line")
message("Track type: ", paste(names(table(tornadoes$track_type)),
                              table(tornadoes$track_type), collapse = ", "),
        " (end missing/zero: ", sum(bad_end), ", start == end: ",
        sum(same_pt), ")")

# width of 0 (or missing) is replaced by the documented minimum
tornadoes$width_imputed <- is.na(tornadoes$wid) | tornadoes$wid <= 0
tornadoes$wid[tornadoes$width_imputed] <- min_width_yd
message("Width imputed to ", min_width_yd, " yards: ",
        sum(tornadoes$width_imputed))

# ---- 3. build track geometries (EPSG:4326) ---------------------------------

make_geom <- function(i) {
  if (tornadoes$track_type[i] == "line") {
    st_linestring(rbind(c(tornadoes$slon[i], tornadoes$slat[i]),
                        c(tornadoes$elon[i], tornadoes$elat[i])))
  } else {
    st_point(c(tornadoes$slon[i], tornadoes$slat[i]))
  }
}
geom <- st_sfc(lapply(seq_len(nrow(tornadoes)), make_geom), crs = 4326)

# ---- 4. buffer by half the width in the equal-area CRS ---------------------

geom_area <- st_transform(geom, area_crs)
half_width_m <- tornadoes$wid * yd_to_m / 2

# flat end caps for lines (round caps would add area); points get a circle
is_line <- tornadoes$track_type == "line"
poly_list <- vector("list", length(geom_area))
poly_list[is_line] <- as.list(st_buffer(
  geom_area[is_line], dist = half_width_m[is_line], endCapStyle = "FLAT"))
poly_list[!is_line] <- as.list(st_buffer(
  geom_area[!is_line], dist = half_width_m[!is_line]))
poly <- st_sfc(poly_list, crs = area_crs)
poly <- st_make_valid(poly)

tornado_polys <- st_sf(
  tornado_id = tornadoes$tornado_id,
  tornado_area_m2 = as.numeric(st_area(poly)),
  geometry = poly
)

# ---- 5. intersect with ZCTA polygons of the matching Census vintage --------

load_zctas <- function(vintage) {
  z <- zctas(year = vintage)
  z <- z %>%
    rename(ZCTA = paste0("ZCTA5CE", substr(vintage, 3, 4)),
           ALAND = paste0("ALAND", substr(vintage, 3, 4))) %>%
    select(ZCTA, ALAND)
  z$ALAND <- as.numeric(z$ALAND)
  st_make_valid(st_transform(z, area_crs))
}

intersect_vintage <- function(tracks, vintage) {
  zc <- load_zctas(vintage)
  x <- suppressWarnings(st_intersection(tracks["tornado_id"], zc))
  # keep polygonal pieces only (touching boundaries yield lines or points)
  x <- st_collection_extract(x, "POLYGON")
  x$intersection_m2 <- as.numeric(st_area(x))
  x %>%
    st_drop_geometry() %>%
    group_by(tornado_id, ZCTA, ALAND) %>%
    summarise(intersection_m2 = sum(intersection_m2), .groups = "drop")
}

yr_of <- tornadoes$yr
pieces <- bind_rows(
  intersect_vintage(tornado_polys[yr_of < 2010, ], 2000),
  intersect_vintage(tornado_polys[yr_of >= 2010 & yr_of < 2020, ], 2010),
  intersect_vintage(tornado_polys[yr_of >= 2020, ], 2020)
)
message("Tornado-ZCTA pairs before dropping zero areas: ", nrow(pieces))

zero_area <- pieces$intersection_m2 <= 0
message("Dropped, exact-zero intersection area: ", sum(zero_area))
pieces <- pieces[!zero_area, ]

no_zcta <- setdiff(tornadoes$tornado_id, pieces$tornado_id)
message("Tornadoes that intersect no ZCTA (kept in tornado_tracks only): ",
        length(no_zcta))

# ---- 6. exposure measures and loss allocation ------------------------------

tornado_exposure <- pieces %>%
  group_by(tornado_id) %>%
  mutate(area_share_of_tornado = intersection_m2 / sum(intersection_m2)) %>%
  ungroup() %>%
  # ALAND excludes water while ZCTA polygons include it, so a path can slightly
  # exceed ALAND; cap the proportion at 1 (reported below)
  mutate(area_prop_uncapped = intersection_m2 / ALAND,
         area_prop_affected = pmin(area_prop_uncapped, 1)) %>%
  left_join(
    tornadoes %>%
      transmute(tornado_id, date, year = yr, month = mo, day = dy,
                magnitude = mag, total_injury = inj, total_fatality = fat,
                property_loss_tornado_total = loss),
    by = "tornado_id"
  ) %>%
  mutate(property_loss_allocated =
           property_loss_tornado_total * area_share_of_tornado) %>%
  select(tornado_id, date, year, month, day, magnitude, total_injury,
         total_fatality, property_loss_tornado_total, property_loss_allocated,
         ZCTA, area_prop_affected, area_prop_uncapped, area_share_of_tornado) %>%
  arrange(tornado_id, ZCTA) %>%
  as.data.frame()

message("area_prop_affected capped at 1: ",
        sum(tornado_exposure$area_prop_uncapped > 1), " rows")
tornado_exposure$area_prop_uncapped <- NULL

# checks: shares sum to 1 and allocated loss sums back to the tornado total
chk <- tornado_exposure %>%
  group_by(tornado_id) %>%
  summarise(share = sum(area_share_of_tornado),
            alloc = sum(property_loss_allocated),
            total = first(property_loss_tornado_total), .groups = "drop")
stopifnot(all(abs(chk$share - 1) < 1e-9))
stopifnot(all(abs(chk$alloc - chk$total) <= 1e-8 * pmax(1, abs(chk$total))))

# ---- 7. track geometries for plotting --------------------------------------

tornado_tracks <- st_sf(
  tornado_id = tornadoes$tornado_id,
  track_type = tornadoes$track_type,
  width_imputed = tornadoes$width_imputed,
  tornado_area_m2 = tornado_polys$tornado_area_m2,
  geometry = geom
)

# ---- 8. save ---------------------------------------------------------------

writeLines(format(access_date), "data-raw/access_date.txt")
message("Data accessed: ", access_date, " (", noaa_url, ")")
message("tornado_exposure rows: ", nrow(tornado_exposure),
        "; tornado_tracks rows: ", nrow(tornado_tracks))

usethis::use_data(tornado_exposure, tornado_tracks, overwrite = TRUE,
                  compress = "xz")
