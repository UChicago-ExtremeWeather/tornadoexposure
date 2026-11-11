# Run from the package root:  caffeinate -i Rscript data-raw/qa/52b_block_validity_duplicates.R 2010     (one vintage per run; progress in data-raw/qa/out/52b_<vintage>.log)
# For every census block file of the vintage: blocks, invalid polygons (as read), blocks whose internal point lies in more than one ZCTA of the vintage (the published code
# kept only the first), blocks with an NA population or no internal point. Saves data-raw/qa/out/block_audit_<vintage>.rds.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE)
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R")
v <- as.integer(commandArgs(TRUE)[1]); states <- pop_states(); zl <- zcta_layer(v); out <- list(); lgf <- qa_out(sprintf("52b_%s.log", v))
for (i in seq_len(nrow(states))) { st <- states[i, ]
  zip <- download_cached(block_url(v, st$state_code), record = FALSE); td <- tempfile("blk"); dir.create(td); utils::unzip(zip, exdir = td)
  shp <- list.files(td, pattern = "\\.shp$", full.names = TRUE); lay <- tools::file_path_sans_ext(basename(shp)); sfx <- substr(v, 3, 4); gcol <- if (v == 2000) "BLKIDFP00" else paste0("GEOID", sfx)
  dbf <- sf::st_read(sub("\\.shp$", ".dbf", shp), quiet = TRUE); nfeat <- nrow(dbf)   # attributes only (no geometry)
  lat <- as.numeric(dbf[[paste0("INTPTLAT", sfx)]]); lon <- as.numeric(dbf[[paste0("INTPTLON", sfx)]]); geoid <- dbf[[gcol]]; popna <- if (v == 2020) sum(is.na(dbf$POP20)) else NA_integer_
  inv <- 0L; for (a in seq(0, nfeat - 1, by = 50000)) { ch <- sf::st_read(shp, query = sprintf("SELECT %s FROM %s WHERE FID >= %d AND FID < %d", gcol, lay, a, a + 50000), quiet = TRUE); inv <- inv + sum(!sf::st_is_valid(ch)); rm(ch) }   # geometry in chunks
  ok <- is.finite(lat) & is.finite(lon)
  pts <- sf::st_as_sf(data.frame(GEOID = geoid[ok], lon = lon[ok], lat = lat[ok]), coords = c("lon", "lat"), crs = 4269)
  zsub <- zl[lengths(sf::st_intersects(zl, sf::st_as_sfc(sf::st_bbox(pts)))) > 0, ]; j <- sf::st_join(pts, zsub, join = sf::st_intersects)
  nmatch <- table(j$GEOID); multi <- sum(nmatch > 1)
  pop_na <- popna
  out[[i]] <- data.frame(vintage = v, state = st$state, blocks = nfeat, invalid_blocks = inv, duplicated_geoid_in_file = sum(duplicated(geoid)), no_internal_point = sum(!ok), blocks_in_more_than_one_zcta = multi, extra_rows = sum(nmatch[nmatch > 1] - 1), pop_na_2020_field = pop_na)
  unlink(td, recursive = TRUE); cat(format(Sys.time(), "%H:%M:%S "), v, st$state, paste(unlist(out[[i]][1, -(1:2)]), collapse = " "), "\n", file = lgf, append = TRUE) }
A <- bind_rows(out); saveRDS(A, qa_out(sprintf("block_audit_%s.rds", v))); print(colSums(A[, -(1:2)], na.rm = TRUE))
