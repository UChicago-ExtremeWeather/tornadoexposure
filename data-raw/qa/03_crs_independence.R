# Run from the package root: Rscript data-raw/qa/03_crs_independence.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf)}); options(width=160)
source("R/path_polygon.R"); load("data/tornado_exposure.rda"); load("data/tornado_tracks.rda")
set.seed(303)
cache <- file.path(Sys.getenv("HOME"), "Library/Caches/tigris")
zfile <- c("2000"="tl_2010_us_zcta500", "2010"="tl_2010_us_zcta510", "2020"="tl_2020_us_zcta520"); suf <- c("2000"="00","2010"="10","2020"="20")
vint <- function(y) as.character(ifelse(y<2010,2000, ifelse(y<2020,2010,2020)))
ex <- tornado_exposure %>% filter(area_prop_affected < 1)
smp <- ex[sample(nrow(ex), 200), c("tornado_id","ZCTA","year","area_prop_affected","track_type")]
smp$v <- vint(smp$year)
# read only the needed ZCTAs per vintage
zs <- lapply(names(zfile), function(v) { codes <- unique(smp$ZCTA[smp$v==v]); if (!length(codes)) return(NULL)
  col <- paste0("ZCTA5CE", suf[[v]]); lay <- zfile[[v]]
  q <- sprintf("SELECT %s, ALAND%s FROM %s WHERE %s IN (%s)", col, suf[[v]], lay, col, paste0("'", codes, "'", collapse=","))
  z <- sf::read_sf(file.path(cache, paste0(lay, ".shp")), query=q); names(z)[1:2] <- c("ZCTA","ALAND"); z$ALAND <- as.numeric(z$ALAND); z }); names(zs) <- names(zfile)
tr <- tornado_tracks[match(smp$tornado_id, tornado_tracks$tornado_id), ]
alt_area <- function(i, crs) {
  p <- .path_polygon(tr[i, ], tr$wid_yd[i], tr$len_mi[i], tr$track_type[i], crs = crs)
  z <- zs[[smp$v[i]]]; z <- z[z$ZCTA == smp$ZCTA[i], ]
  zg <- sf::st_make_valid(sf::st_transform(sf::st_geometry(z), crs))
  a <- sf::st_area(sf::st_intersection(sf::st_union(zg), p[[1]] |> sf::st_sfc(crs = crs)))
  as.numeric(sum(a)) / z$ALAND[1]
}
t0 <- Sys.time()
smp$p_6933 <- sapply(seq_len(nrow(smp)), alt_area, crs = 6933)
cat("6933 done", format(Sys.time()-t0), "\n")
cen <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(tr)))
smp$p_laea <- sapply(seq_len(nrow(smp)), function(i) alt_area(i, sprintf("+proj=laea +lat_0=%f +lon_0=%f +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs", cen[i,2], cen[i,1])))
smp$rel_6933 <- smp$p_6933/smp$area_prop_affected - 1; smp$rel_laea <- smp$p_laea/smp$area_prop_affected - 1
cat("rows:", nrow(smp), " (by vintage:", paste(names(table(smp$v)), table(smp$v), collapse=" "), "; track types:", paste(names(table(smp$track_type)), table(smp$track_type), collapse=" "), ")\n")
cat("stored area_prop range in sample:", signif(range(smp$area_prop_affected),3), "\n")
for (nm in c("rel_6933","rel_laea")) { cat("\nrelative difference (new CRS / EPSG:5070 - 1):", nm, "\n"); print(signif(quantile(smp[[nm]], c(0,.01,.05,.25,.5,.75,.95,.99,1), na.rm=TRUE),3)); cat("max abs:", signif(max(abs(smp[[nm]]), na.rm=TRUE),3), " share within 0.1%:", mean(abs(smp[[nm]])<=.001, na.rm=TRUE), " within 1%:", mean(abs(smp[[nm]])<=.01, na.rm=TRUE), " NA:", sum(is.na(smp[[nm]])), "\n") }
cat("\nworst 6 by LAEA:\n"); print(smp %>% arrange(desc(abs(rel_laea))) %>% head(6) %>% transmute(tornado_id, ZCTA, track_type, area_prop=signif(area_prop_affected,3), p_laea=signif(p_laea,3), rel_laea=signif(rel_laea,3), rel_6933=signif(rel_6933,3)))
cat("\nrelative difference of path polygon area itself (EPSG:5070 vs 6933 vs LAEA) for the same tornadoes:\n")
pa <- function(crs_i) sapply(seq_len(nrow(tr)), function(i) as.numeric(sf::st_area(.path_polygon(tr[i,], tr$wid_yd[i], tr$len_mi[i], tr$track_type[i], crs = crs_i(i)))))
a5070 <- tr$tornado_area_m2; a6933 <- pa(function(i) 6933); alaea <- pa(function(i) sprintf("+proj=laea +lat_0=%f +lon_0=%f +datum=NAD83 +units=m +no_defs", cen[i,2], cen[i,1]))
print(signif(quantile(a6933/a5070-1, c(0,.5,1)),3)); print(signif(quantile(alaea/a5070-1, c(0,.5,1)),3))
