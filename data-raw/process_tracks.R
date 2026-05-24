library(readr)
library(dplyr)
library(sf)

# manually update csv link for each annual update (version 0.1.1 initialized with 2025 update)
tornados <- read_csv("https://www.spc.noaa.gov/wcm/data/1950-2025_all_tornadoes.csv")

# make tornado id
tornados <- tornados %>%
  mutate(tornado_id = paste(yr, om, sep = "_"))

# drop all EF0s
tornados <- tornados %>%
  filter(mag > 0)

# restrict dataset to storms after 1995 (Doppler radar improvement)
# keeps dataset in safe range for GitHub
tornados <- tornados %>%
  filter(yr > 1995)

# remove rows with missing coordinates
tornados <- tornados %>%
  filter(
    !is.na(slon),
    !is.na(slat),
    !is.na(elon),
    !is.na(elat)
  )

# remove degenerate tracks
tornados <- tornados %>%
  filter(!(slon == elon & slat == elat))

# create wkt column from start/end coordinate pairs
tornados <- tornados %>%
  mutate(geometry = sprintf("LINESTRING(%f %f, %f %f)",
                       slon, slat,
                       elon, elat))

# create tornado track linestring geometries from wkt column
tornado_tracks <- st_as_sf(tornados, wkt = "geometry", crs = 4326)

# repair any remaining invalid geometries
tornado_tracks <- st_make_valid(tornado_tracks)

# keep only valid LINESTRING geometries
tornado_tracks <- tornado_tracks %>%
  filter(
    st_is_valid(.),
    st_geometry_type(.) == "LINESTRING"
  )

# transform geometries to appropriate crs (meters)
tornado_tracks <- sf::st_transform(
  tornado_tracks,
  3857
)

# create column to store track width in meters
tornado_tracks <- tornado_tracks %>%
  mutate(width_m = wid * 0.9144)

# create buffer to create track polygons using width
buf <- st_buffer(
  st_geometry(tornado_tracks),
  dist = as.numeric(tornado_tracks$width_m) / 2
)

# calculate track area (in meters squared)
tornado_tracks$area_m2 <- as.numeric(st_area(buf))

# limit to relevant columns
keep_cols <- c(
  "tornado_id", "date", "yr", "mo", "dy", "mag", "inj", "fat", "area_m2", "geometry")
tornado_tracks <- tornado_tracks %>%
  select(all_of(keep_cols))

# rename columns
tornado_tracks <- tornado_tracks %>%
  rename(year = yr, month = mo, day = dy, magnitude = mag, total_injury = inj,
         total_fatality = fat, tornado_area_m2 = area_m2)

# write to clean data folder
usethis::use_data(tornado_tracks, overwrite = TRUE)
