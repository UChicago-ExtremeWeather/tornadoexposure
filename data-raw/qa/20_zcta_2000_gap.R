# Run from the package root: Rscript data-raw/qa/20_zcta_2000_gap.R
# The official 2000 ZCTA list (Census Gazetteer) has more ZCTAs than the 2000
# boundary file has polygons. Estimates how many 1996-2009 tornadoes (2000 vintage)
# reach an official ZCTA that has no polygon, using a proxy location for each missing
# ZCTA: its polygon in the 2010 file, else in the 2020 file, else a disc with the
# official land area centered on the Gazetteer internal point.
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R"); source("R/path_polygon.R")
suppressMessages({library(dplyr); library(sf)}); sf_use_s2(FALSE)
td <- tempfile(); dir.create(td); unzip(download_cached("https://www2.census.gov/geo/docs/maps-data/data/gazetteer/zcta5.zip"), exdir = td)
tok <- strsplit(trimws(readLines(list.files(td, pattern = "zcta5.txt", full.names = TRUE))), "[[:space:]]+")
off <- data.frame(ZCTA = substr(vapply(tok, `[`, "", 1), 3, 7), pop = suppressWarnings(as.numeric(vapply(tok, `[`, "", 4))), aland = suppressWarnings(as.numeric(vapply(tok, `[`, "", 6))),
                  lat = suppressWarnings(as.numeric(vapply(tok, `[`, "", 10))), lon = suppressWarnings(as.numeric(vapply(tok, `[`, "", 11))), stringsAsFactors = FALSE) %>%
  filter(!is.na(pop)) %>% group_by(ZCTA) %>% summarise(pop = sum(pop), aland = sum(aland), lat = first(lat), lon = first(lon), .groups = "drop")
poly00 <- sf::read_sf(file.path(Sys.getenv("HOME"), "Library/Caches/tigris/tl_2010_us_zcta500.dbf"))$ZCTA5CE00
miss <- off %>% filter(!ZCTA %in% poly00)
cat(sprintf("official 2000 ZCTAs: %s; polygons in the 2000 file: %s; official ZCTAs without a polygon: %s (%s with a polygon but not official: %s)\n", format(nrow(off), big.mark = ","), format(length(unique(poly00)), big.mark = ","), format(nrow(miss), big.mark = ","), "", sum(!unique(poly00) %in% off$ZCTA)))
cat(sprintf("missing ZCTAs: official population %s (%.3f%% of %s), land area %.0f km2 (%.3f%% of the official total); with population 0: %d; with land area 0: %d\n", format(sum(miss$pop), big.mark = ","), 100 * sum(miss$pop) / sum(off$pop), format(sum(off$pop), big.mark = ","), sum(miss$aland) / 1e6, 100 * sum(miss$aland) / sum(off$aland), sum(miss$pop == 0), sum(miss$aland == 0)))
cat("size of the missing ZCTAs (official population quantiles 25/50/75/95/100):", paste(quantile(miss$pop, c(.25, .5, .75, .95, 1)), collapse = " "), "\n")
z10 <- zcta_layer(2010); z20 <- zcta_layer(2020)
p10 <- z10[z10$ZCTA %in% miss$ZCTA, ]; p20 <- z20[z20$ZCTA %in% setdiff(miss$ZCTA, p10$ZCTA), ]
rest <- miss %>% filter(!ZCTA %in% c(p10$ZCTA, p20$ZCTA), !is.na(lat))
cat(sprintf("proxy locations: %d from the 2010 file, %d from the 2020 file; %d have no polygon in any file and are placed by the Gazetteer internal point (%d as a disc with the official land area, %d as a point because the official land area is 0); %d have no coordinates\n", nrow(p10), nrow(p20), nrow(rest), sum(rest$aland > 0), sum(rest$aland == 0), nrow(miss) - nrow(p10) - nrow(p20) - nrow(rest)))
cat("largest missing ZCTAs by official land area (km2) and population:\n"); print(miss %>% arrange(desc(aland)) %>% head(5) %>% transmute(ZCTA, land_km2 = round(aland / 1e6), pop))
pts5 <- st_transform(st_as_sf(rest, coords = c("lon", "lat"), crs = 4269), 5070)
prox <- bind_rows(st_transform(p10, 5070) %>% transmute(ZCTA, src = "2010 polygon"), st_transform(p20, 5070) %>% transmute(ZCTA, src = "2020 polygon"),
  st_sf(ZCTA = rest$ZCTA, src = ifelse(rest$aland > 0, "disc (official land area)", "point (zero land area)"), geometry = st_geometry(st_buffer(pts5, ifelse(rest$aland > 0, sqrt(rest$aland / pi), 1)))))
load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda")
yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4)); tt <- tornado_tracks[yr <= 2009, ]
pp <- st_sf(tid = tt$tornado_id, geometry = .path_polygon(tt, tt$wid_yd, tt$len_mi, tt$track_type))
hit <- st_intersects(pp, prox)
n_t <- sum(lengths(hit) > 0); pairs <- sum(lengths(hit))
has_row <- pp$tid %in% tornado_exposure$tornado_id
cat(sprintf("\n1996-2009 tornadoes (2000 vintage): %s; whose path reaches a proxy of a missing official ZCTA: %d (%.2f%%); proxy-ZCTA hits (tornado x missing ZCTA pairs): %d\n", format(nrow(pp), big.mark = ","), n_t, 100 * n_t / nrow(pp), pairs))
cat(sprintf("  of those %d, %d already have at least one ZCTA row (so only some of their pairs are lost) and %d have none (they are among the tornadoes that intersect no ZCTA: %d of %d in this vintage)\n", n_t, sum(lengths(hit) > 0 & has_row), sum(lengths(hit) > 0 & !has_row), sum(!has_row), nrow(pp)))
src <- table(unlist(lapply(hit, function(h) prox$src[h]))); cat("hits by proxy type:", paste(names(src), src, collapse = "; "), "\n")
only_poly <- sapply(hit, function(h) any(prox$src[h] %in% c("2010 polygon", "2020 polygon"))); cat("tornadoes reaching a proxy that is a 2010/2020 polygon (better located):", sum(only_poly), "\n")
cat("missing-ZCTA hits per affected tornado (quantiles 50/90/100%):", paste(quantile(lengths(hit)[lengths(hit) > 0], c(.5, .9, 1)), collapse = " "), "\n")
mi <- unlist(lapply(hit, function(h) prox$ZCTA[h])); topm <- sort(table(mi), decreasing = TRUE)
cat("missing ZCTAs hit most often (code: tornadoes, official population):\n"); print(head(data.frame(ZCTA = names(topm), tornadoes = as.integer(topm), pop = miss$pop[match(names(topm), miss$ZCTA)]), 6))
saveRDS(list(miss = miss, n_t = n_t, pairs = pairs, n_2000 = nrow(pp), with_row = sum(lengths(hit) > 0 & has_row), no_row = sum(lengths(hit) > 0 & !has_row), src = src, only_poly = sum(only_poly), n_poly00 = length(unique(poly00)), n_off = nrow(off)), qa_out("zcta_2000_gap.rds"))

# ---- write the known_issues.md block ---------------------------------------------
nf <- function(x) formatC(round(x), format = "d", big.mark = ","); pc <- function(x, d = 2) paste0(formatC(100 * x, format = "f", digits = d), "%")
R <- readRDS(qa_out("population_results.rds")); S <- R$summary %>% filter(vintage == 2000)
xx <- sum(grepl("XX$", miss$ZCTA))
txt <- paste0('<!-- zcta2000-gap:start -->
## The 2000 ZCTA gap

The official 2000 ZCTA list (Census Gazetteer) has ', nf(nrow(off)), ' ZCTAs, but the 2000 boundary file has ', nf(length(unique(poly00))), ' polygons. ', nf(nrow(miss)), ' official ZCTAs have no polygon (and ', sum(!unique(poly00) %in% off$ZCTA), ' polygons have no official entry). ', nf(xx), ' of the missing codes are three-digit placeholders ending in `XX` (for example `997XX`), which stand for areas with no five-digit ZCTA. The missing ZCTAs hold ', nf(sum(miss$pop)), ' residents in the official counts (', pc(sum(miss$pop) / sum(off$pop), 3), ' of the population; ', nf(sum(miss$pop == 0)), ' have none and ', nf(sum(miss$aland == 0)), ' have no land area), which matches the ', nf(sum(S$pop_no_zcta)), ' residents in 2000 blocks assigned to no ZCTA, but ', pc(sum(miss$aland) / sum(off$aland), 1), ' of the official land area (mostly a few very large placeholder areas in Alaska and Nevada).

A tornado in such an area has no exposure row for it. To estimate how many 1996-2009 tornadoes are affected, each missing ZCTA was placed at its Gazetteer internal point, as a disc with the official land area (', nf(sum(rest$aland > 0)), ' codes) or a point (', nf(sum(rest$aland == 0)), ' codes with no land area); ', nf(nrow(miss) - nrow(rest)), ' have no coordinates and cannot be placed. By this estimate ', nf(n_t), ' of ', nf(nrow(pp)), ' tornadoes (', pc(n_t / nrow(pp)), ') reach a missing ZCTA: ', nf(sum(lengths(hit) > 0 & has_row)), ' of them also have a row for another ZCTA, so they lose only a pair, and ', nf(sum(lengths(hit) > 0 & !has_row)), ' are among the ', nf(sum(!has_row)), ' tornadoes of the 2000 vintage that intersect no ZCTA. The real areas are irregular and a disc around one point only approximates them, so the count is approximate; no error bound was computed. The 2010 and 2020 files contain none of the missing codes.
<!-- zcta2000-gap:end -->
')
k <- paste(readLines("data-raw/known_issues.md", warn = FALSE), collapse = "\n")
if (grepl("<!-- zcta2000-gap:start -->", k, fixed = TRUE)) { a1 <- regexpr("<!-- zcta2000-gap:start -->", k, fixed = TRUE); b1 <- regexpr("<!-- zcta2000-gap:end -->", k, fixed = TRUE) + nchar("<!-- zcta2000-gap:end -->"); k <- paste0(substr(k, 1, a1 - 1), sub("\n$", "", txt), substr(k, b1, nchar(k)))
} else { a1 <- regexpr("## Identifiers and SPC revisions", k, fixed = TRUE); k <- paste0(substr(k, 1, a1 - 1), txt, "\n", substr(k, a1, nchar(k))) }
writeLines(sub("\n+$", "", k), "data-raw/known_issues.md"); cat("wrote the 2000 ZCTA gap section of known_issues.md\n")
