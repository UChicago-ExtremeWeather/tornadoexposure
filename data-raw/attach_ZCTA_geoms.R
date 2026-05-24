library(readr)
library(dplyr)
library(sf)
library(tigris)

load("data/tornado_tracks.rda")

# get Census ZCTA boundary files from Tigris
zctas_2000 <- zctas(year = 2000)
zctas_2010 <- zctas(year = 2010)
zctas_2020 <- zctas(year = 2020)

# split tornado tracks into chunks for each Census file
tornados_2000 <- tornado_tracks %>% filter(year < 2010)
tornados_2010 <- tornado_tracks %>% filter(year >= 2010 & year < 2020)
tornados_2020 <- tornado_tracks %>% filter(year >= 2020)

# align CRS (tornado_track in ESPG:3857)
zctas_2000 <- st_transform(zctas_2000, 3857)
zctas_2010 <- st_transform(zctas_2010, 3857)
zctas_2020 <- st_transform(zctas_2020, 3857)

# combine each chunked dataset with its associated Census ZCTA boundaries
zt_2000 <- st_join(tornados_2000, zctas_2000)
zt_2010 <- st_join(tornados_2010, zctas_2010)
zt_2020 <- st_join(tornados_2020, zctas_2020)

# bind into a single dataframe
zt <- bind_rows(zt_2000, zt_2010, zt_2020)
zt <- zt %>%
  mutate( # coalesce into one ZCTA column
    ZCTA = coalesce(ZCTA5CE00, ZCTA5CE10, ZCTA5CE20)
  ) %>%
  mutate( # coalesce area columns
    zcta_area = coalesce(ALAND00, ALAND10, ALAND20)
  ) %>%
  mutate( # calculate the percentage of each ZCTA area affected by each tornado
    area_pct_affected = (tornado_area_m2 / zcta_area) * 100
  )

keep_cols <- c("tornado_id", "date", "year", "month", "day", "magnitude",
               "total_injury", "total_fatality","area_pct_affected", "ZCTA")
zt <- zt %>%
  select(all_of(keep_cols))

# write to clean data folder
usethis::use_data(zt, overwrite = TRUE)
