# Run from the package root:  caffeinate -i Rscript data-raw/qa/63_land_only_area_test.R
# Tests whether a land-only ZCTA shape (the full ZCTA polygon minus the Census water polygons, TIGER/Line AREAWATER by county)
# reproduces the Census land area ALAND. Water files: data-raw/qa/cache/areawater/<year>/tl_<year>_<county fips>_areawater.zip
# (TIGER2020 for the 2020 boundary year, TIGER2010 for the 2010 and 2000 boundary years). Nothing here is shipped.
# Per ZCTA: water_m2 = area of (ZCTA polygon intersect water polygons), summed over counties (AREAWATER is cut at county lines);
# land_m2 = polygon area - water_m2; ratio = land_m2 / ALAND. Areas are in EPSG:5070 (equal area). Output: out/63_land_test.rds
suppressMessages({library(sf); library(dplyr); library(parallel)}); sf_use_s2(FALSE); source("data-raw/qa/helpers.R")
cache <- Sys.getenv("TIGRIS_CACHE_DIR", rappdirs::user_cache_dir("tigris"))
zfile <- c("2020" = "tl_2020_us_zcta520", "2010" = "tl_2010_us_zcta510", "2000" = "tl_2010_us_zcta500")
alandc <- c("2020" = "ALAND20", "2010" = "ALAND10", "2000" = "ALAND00"); awc <- sub("ALAND", "AWATER", alandc); zc <- c("2020" = "ZCTA5CE20", "2010" = "ZCTA5CE10", "2000" = "ZCTA5CE00")
wset <- c("2020" = "2020", "2010" = "2010", "2000" = "2010")
read_z <- function(by) {
  z <- st_read(file.path(cache, paste0(zfile[[by]], ".shp")), quiet = TRUE)
  z <- data.frame(ZCTA = as.character(z[[zc[[by]]]]), ALAND = as.numeric(z[[alandc[[by]]]]), AWATER = as.numeric(z[[awc[[by]]]]), geometry = st_geometry(z))
  z <- st_sf(z); z <- st_transform(z, 5070); inv <- sum(!st_is_valid(z)); z <- st_make_valid(z)   # validity counted in EPSG:5070 (planar), as for the package
  z$a <- as.numeric(st_area(z)); bb <- t(vapply(st_geometry(z), function(g) as.numeric(st_bbox(g)), numeric(4))); z$xmin <- bb[, 1]; z$ymin <- bb[, 2]; z$xmax <- bb[, 3]; z$ymax <- bb[, 4]
  list(z = z, invalid = inv)
}
one_county <- function(f, z) {
  w <- tryCatch(st_read(paste0("/vsizip/", f), quiet = TRUE), error = function(e) NULL)
  if (is.null(w) || nrow(w) == 0) return(data.frame(ZCTA = character(), water_m2 = numeric(), nw = integer()))
  w <- st_transform(st_make_valid(w), 5070); wb <- st_bbox(w)
  h <- which(z$xmin <= wb[["xmax"]] & z$xmax >= wb[["xmin"]] & z$ymin <= wb[["ymax"]] & z$ymax >= wb[["ymin"]]); if (!length(h)) return(data.frame(ZCTA = character(), water_m2 = numeric(), nw = integer()))
  wu <- st_union(st_geometry(w)); zz <- z[h, ]
  zz <- zz[lengths(st_intersects(zz, wu)) > 0, ]; if (!nrow(zz)) return(data.frame(ZCTA = character(), water_m2 = numeric(), nw = integer()))
  x <- suppressWarnings(st_intersection(st_geometry(zz), wu))
  data.frame(ZCTA = zz$ZCTA[attr(x, "idx")[, 1]], water_m2 = as.numeric(st_area(x)), nw = nrow(w))
}
nproc <- as.integer(Sys.getenv("NPROC", "3")); years <- strsplit(Sys.getenv("BY", "2020,2010,2000"), ",")[[1]]   # BY=2020 runs one boundary year
res <- if (file.exists(qa_out("63_land_test.rds"))) readRDS(qa_out("63_land_test.rds")) else list()
for (by in years) {
  zl <- read_z(by); z <- zl$z; files <- list.files(file.path("data-raw/qa/cache/areawater", wset[[by]]), full.names = TRUE)
  cat(format(Sys.time(), "%H:%M:%S"), by, nrow(z), "ZCTA rows,", length(files), "water files\n")
  out <- mclapply(files, one_county, z = z, mc.cores = nproc, mc.preschedule = TRUE); err <- sum(vapply(out, inherits, logical(1), "try-error"))
  wd <- bind_rows(out); nw <- sum(vapply(out, function(d) if (nrow(d)) d$nw[1] else 0L, numeric(1)))
  zt <- z %>% st_drop_geometry() %>% group_by(ZCTA) %>% summarise(ALAND = sum(ALAND), AWATER = sum(AWATER), poly_m2 = sum(a), rows = n())
  wt <- wd %>% group_by(ZCTA) %>% summarise(water_m2 = sum(water_m2))
  d <- zt %>% left_join(wt, by = "ZCTA") %>% mutate(water_m2 = ifelse(is.na(water_m2), 0, water_m2), land_m2 = poly_m2 - water_m2, ratio = land_m2 / ALAND,
                                                     water_poly = poly_m2 - ALAND)
  res[[by]] <- list(d = d, invalid = zl$invalid, errors = err, water_files = length(files), water_size = sum(file.size(files)))
  saveRDS(res, qa_out("63_land_test.rds"))
}
cat("done\n")
