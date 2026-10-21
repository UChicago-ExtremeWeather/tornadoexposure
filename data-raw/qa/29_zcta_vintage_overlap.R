# Run from the package root: Rscript data-raw/qa/29_zcta_vintage_overlap.R
# How much do ZCTA codes change between Census vintages? For each code present in two boundary files,
# the overlap ratio is area(A intersect B) / area(A union B) of its two polygons (1 = the same area, 0 = no
# overlap), in EPSG:5070. Writes data-raw/qa/out/zcta_vintage_overlap.rds, which the README builds from.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(tigris_use_cache = TRUE)
source("data-raw/qa/helpers.R")
load("data/tornado_exposure.rda")
lz <- function(v) { z <- tigris::zctas(year = v, progress_bar = FALSE); sfx <- substr(v, 3, 4); z <- z[, c(paste0("ZCTA5CE", sfx), paste0("ALAND", sfx))]; names(z) <- c("ZCTA", "ALAND", "geometry"); z$ALAND <- as.numeric(z$ALAND); sf::st_make_valid(sf::st_transform(z, 5070)) }
Z <- lapply(c(2000, 2010, 2020), lz); names(Z) <- c("2000", "2010", "2020")
area_or0 <- function(g) if (length(g) == 0 || all(sf::st_is_empty(g))) 0 else as.numeric(sf::st_area(g))
ratio <- function(A, B) { both <- intersect(A$ZCTA, B$ZCTA); a <- sf::st_geometry(A)[match(both, A$ZCTA)]; b <- sf::st_geometry(B)[match(both, B$ZCTA)]
  r <- vapply(seq_along(both), function(i) { u <- as.numeric(sf::st_area(sf::st_union(a[i], b[i]))); area_or0(suppressWarnings(sf::st_intersection(a[i], b[i]))) / u }, numeric(1))
  data.frame(ZCTA = both, ratio = r, codes_in_first = nrow(A), codes_in_second = nrow(B)) }
r1020 <- ratio(Z[["2010"]], Z[["2020"]]); r0010 <- ratio(Z[["2000"]], Z[["2010"]])
used <- unique(tornado_exposure$ZCTA)
sm <- function(r, nm) { u <- r[r$ZCTA %in% used, ]; data.frame(pair = nm, codes_in_both = nrow(r), below_0.9 = sum(r$ratio < 0.9), share_below_0.9 = mean(r$ratio < 0.9), codes_with_exposure = nrow(u), exposure_below_0.9 = sum(u$ratio < 0.9), share_exposure_below_0.9 = mean(u$ratio < 0.9), zero_overlap = sum(r$ratio == 0), median_ratio = median(r$ratio)) }
res <- bind_rows(sm(r1020, "2010 to 2020"), sm(r0010, "2000 to 2010")); print(res, digits = 3)
saveRDS(list(summary = res, r1020 = r1020, r0010 = r0010), qa_out("zcta_vintage_overlap.rds"))
