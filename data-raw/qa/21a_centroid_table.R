# Run from the package root: Rscript data-raw/qa/21a_centroid_table.R
# Diagnostic table (nothing here changes the package data).
# Builds, for each ZCTA vintage, the population-weighted centroid of the ZCTA
# from block internal points (INTPTLAT/INTPTLON fields in the block files) and
# the block populations and ZCTA assignments already cached by add_population.R.
# Also builds the geometric centroid of each ZCTA polygon. Output:
# data-raw/qa/out/zcta_centroids_plan.rds
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R")
suppressMessages(library(dplyr))
states <- pop_states()
# unit-vector mean on the sphere, so no projection is involved
ll2xyz <- function(lon, lat) { lo <- lon * pi / 180; la <- lat * pi / 180; cbind(cos(la) * cos(lo), cos(la) * sin(lo), sin(la)) }
res <- list(); chk <- list()
for (v in c(2000, 2010, 2020)) {
  acc <- list(); sfx <- substr(v, 3, 4)
  for (i in seq_len(nrow(states))) {
    st <- states[i, ]
    wf <- pop_cache("work", sprintf("%s_%s.rds", v, st$state_code))
    if (!file.exists(wf)) next
    bl <- readRDS(wf)$blocks
    zip <- download_cached(block_url(v, st$state_code), record = FALSE)
    td <- tempfile("dbf"); dir.create(td)
    fl <- utils::unzip(zip, list = TRUE)$Name; dbf <- fl[grepl("\\.dbf$", fl)]
    utils::unzip(zip, files = dbf, exdir = td)
    d <- sf::st_read(file.path(td, dbf), quiet = TRUE)
    unlink(td, recursive = TRUE)
    gcol <- if (v == 2000) "BLKIDFP00" else paste0("GEOID", sfx)
    d <- data.frame(GEOID = d[[gcol]], lat = as.numeric(d[[paste0("INTPTLAT", sfx)]]), lon = as.numeric(d[[paste0("INTPTLON", sfx)]]))
    j <- merge(bl, d, by = "GEOID")
    chk[[length(chk) + 1]] <- data.frame(vint = v, state = st$state, blocks = nrow(bl), with_point = sum(is.finite(j$lat) & is.finite(j$lon)))
    j <- j[!is.na(j$ZCTA) & is.finite(j$lat) & is.finite(j$lon), ]
    j$pop[is.na(j$pop)] <- 0
    xyz <- ll2xyz(j$lon, j$lat)
    acc[[i]] <- data.frame(ZCTA = j$ZCTA, pop = j$pop, w = j$pop * xyz[, 1], y = j$pop * xyz[, 2], z = j$pop * xyz[, 3],
                           n_blocks = 1L, ux = xyz[, 1], uy = xyz[, 2], uz = xyz[, 3])
    cat(v, st$state, "\n")
  }
  a <- bind_rows(acc) %>% group_by(ZCTA) %>% summarise(zcta_pop = sum(pop), n_blocks = sum(n_blocks), sx = sum(w), sy = sum(y), sz = sum(z), mx = mean(ux), my = mean(uy), mz = mean(uz), .groups = "drop")
  xyz2ll <- function(x, y, z) data.frame(lon = atan2(y, x) * 180 / pi, lat = atan2(z, sqrt(x^2 + y^2)) * 180 / pi)
  pc <- xyz2ll(a$sx, a$sy, a$sz)
  a$pop_lon <- ifelse(a$zcta_pop > 0, pc$lon, NA); a$pop_lat <- ifelse(a$zcta_pop > 0, pc$lat, NA)
  # unweighted mean of block points, kept only as a fallback to compare with the polygon centroid
  bp <- xyz2ll(a$mx, a$my, a$mz); a$blkmean_lon <- bp$lon; a$blkmean_lat <- bp$lat
  z <- zcta_layer(v)
  z5070 <- sf::st_transform(z, 5070)
  g <- sf::st_transform(sf::st_centroid(sf::st_geometry(z5070)), 4269)
  gc <- sf::st_coordinates(g)
  z$geom_lon <- gc[, 1]; z$geom_lat <- gc[, 2]
  z$land_m2 <- NA
  out <- merge(sf::st_drop_geometry(z), a, by = "ZCTA", all.x = TRUE)
  out$zcta_pop[is.na(out$zcta_pop)] <- 0; out$n_blocks[is.na(out$n_blocks)] <- 0
  out$vint <- v
  res[[as.character(v)]] <- out
}
saveRDS(list(centroids = bind_rows(res), block_point_check = bind_rows(chk)), qa_out("zcta_centroids_plan.rds"))
cat("done\n")
