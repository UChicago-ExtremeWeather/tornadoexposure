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

# create wkt column from start/end coordinate pairs
tornados <- tornados %>%
  mutate(geometry = sprintf("LINESTRING(%f %f, %f %f)",
                       slon, slat,
                       elon, elat))

# create tornado track linestring geometries from wkt column
tornado_tracks <- st_as_sf(tornados, wkt = "geometry", crs = 4326)

# transform geometries to appropriate crs
tornado_tracks <- sf::st_transform(
  tornado_tracks,
  3857
)

# limit to relevant columns
keep_cols <- c("tornado_id", "date", "yr", "mo", "dy", "mag", "inj", "fat", "geometry")
tornado_tracks <- tornado_tracks %>%
  select(all_of(keep_cols))

# write to clean data folder
usethis::use_data(tornado_tracks, overwrite = TRUE)
