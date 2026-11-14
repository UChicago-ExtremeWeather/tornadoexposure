# Run from the package root: Rscript data-raw/qa/trials.R
# User-facing trials T2 to T8: a tornado with no usable end point, a multi-state tornado, a tornado with no SPC row, input errors, a rural
# and an urban ZCTA with similar NWS area shares, a clean install, and a ZCTA whose boundary changed between vintages. The printed output is the result.
# Plots go to data-raw/qa/out/ (git-ignored). Needs an internet connection (tigris boundaries; T7 builds and checks the package).
suppressMessages({devtools::load_all(quiet = TRUE); library(dplyr); library(sf)}); options(width = 150); sf_use_s2(FALSE)
source("data-raw/qa/helpers.R")
hdr <- function(x) cat("\n", strrep("=", 100), "\n", x, "\n", strrep("=", 100), "\n", sep = "")
catch <- function(expr) { w <- NULL; r <- withCallingHandlers(tryCatch(expr, error = function(e) paste0("ERROR: ", conditionMessage(e))), warning = function(w1) { w <<- c(w, conditionMessage(w1)); invokeRestart("muffleWarning") }, message = function(m) invokeRestart("muffleMessage")); list(result = r, warnings = w) }
show_err <- function(label, expr) { o <- catch(expr); cat("\n>", label, "\n"); if (is.character(o$result) && length(o$result) == 1 && grepl("^ERROR", o$result)) cat(o$result, "\n") else cat("returned", if (is.data.frame(o$result)) paste(nrow(o$result), "rows") else "a value", "\n"); for (w in o$warnings) cat("WARNING:", w, "\n"); invisible(o) }

hdr("T2: a tornado with no usable end point (a point at the start: one SPC row, no line length, plotted point)")
pe <- tornado_tracks[tornado_tracks$track_type == "point" & as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2010, ]
ids_with_rows <- pe$tornado_id[pe$tornado_id %in% tornado_exposure$tornado_id[tornado_exposure$spc_exposed] & pe$len_mi >= 1]
tid <- ids_with_rows[1]; tr <- tornado_tracks[tornado_tracks$tornado_id == tid, ]
cat("tornado:", tid, "| track_type:", tr$track_type, "| reported length (mi):", tr$len_mi, "| width (yd):", tr$wid_yd, "\n")
rows <- tornado_exposure[tornado_exposure$tornado_id == tid, ]
print(rows[, c("tornado_id", "magnitude", "ZCTA", "spc_exposed", "line_km_in_zcta", "line_share_of_tornado", "boundary_dist_km", "centroid_dist_km", "track_type")], row.names = FALSE)
cat("line_km_in_zcta is NA and the share is 1 for the SPC row:", all(is.na(rows$line_km_in_zcta[rows$spc_exposed])), all(rows$line_share_of_tornado[rows$spc_exposed] == 1), "\n")
zc <- rows$ZCTA[1]
p <- map_exposure(geo_list = zc, year_range = rows$year[1], magnitude = c(0:5, NA), layers = c("zcta", "spc_tracks"))
ggplot2::ggsave(qa_out("trials_T2_point.png"), p, width = 6, height = 5, dpi = 120); cat("plotted point saved to", qa_out("trials_T2_point.png"), "\n")

hdr("T3: a multi-state tornado")
raw <- read.csv(qa_spc_csv()) %>% filter(yr >= 1996)
multi <- raw %>% group_by(yr, om) %>% summarise(states = paste(sort(unique(st)), collapse = ","), n_states = n_distinct(st), seg = paste(sg, collapse = ","), inj = paste(inj, collapse = ","), fat = paste(fat, collapse = ","), .groups = "drop") %>% filter(n_states > 1)
cat("1996 om 1124 in the raw SPC file:\n"); print(as.data.frame(raw[raw$yr == 1996 & raw$om == 1124, c("yr", "om", "st", "sg", "inj", "fat", "slat", "slon", "elat", "elon", "len", "wid")]), row.names = FALSE)
cat("tornado-years with segments in more than one state:", nrow(multi), "\n")
mid <- "1996_1124"; if (!mid %in% tornado_tracks$tornado_id) { mid <- paste(multi$yr[1], multi$om[1], sep = "_") }
cat("using", mid, "\n")
r <- raw[paste(raw$yr, raw$om, sep = "_") == mid, ]; cat("SPC records for it:\n"); print(as.data.frame(r[, c("st", "sg", "inj", "fat", "len")]), row.names = FALSE)
e <- tornado_exposure[tornado_exposure$tornado_id == mid, ]
print(e[, c("tornado_id", "ZCTA", "total_injury", "total_fatality", "property_loss_tornado_total", "line_share_of_tornado")], row.names = FALSE)
cat(sprintf("SPC whole-track (sg == 1) record: injuries %d, fatalities %d; sum over all segment records: injuries %d, fatalities %d; package value: injuries %d, fatalities %d (not double counted)\n",
            r$inj[r$sg == 1][1], r$fat[r$sg == 1][1], sum(r$inj), sum(r$fat), e$total_injury[1], e$total_fatality[1]))
cat("states of the ZCTAs hit (first digits):", paste(unique(substr(e$ZCTA, 1, 3)), collapse = " "), "\n")

hdr("T4: a tornado with no SPC row (empty results, no crash)")
nz <- setdiff(tornado_tracks$tornado_id, tornado_exposure$tornado_id[tornado_exposure$spc_exposed])
cat("tornadoes in tornado_tracks with no SPC row:", length(nz), "\n")
nzt <- tornado_tracks[tornado_tracks$tornado_id %in% nz & tornado_tracks$track_type == "line" & as.integer(substr(tornado_tracks$tornado_id, 1, 4)) >= 2015, ][1, ]
cat("example:", nzt$tornado_id, "| rating", nzt$magnitude, "| length (mi)", nzt$len_mi, "\n")
yr <- as.integer(substr(nzt$tornado_id, 1, 4))
all_z <- as.character(0:9)
for (R in c(1, 10, 25, 50)) { d <- suppressMessages(suppressWarnings(get_data(geo_list = all_z, year_range = yr, centroid_dist_km = R))); cat(sprintf("centroid_dist_km = %2d: rows for this tornado: %d\n", R, sum(d$tornado_id == nzt$tornado_id))) }
d0 <- suppressMessages(get_data(geo_list = all_z, year_range = yr)); cat("exposed definition, all ZCTAs, that year: rows for this tornado:", sum(d0$tornado_id == nzt$tornado_id), "\n")
e1 <- catch(get_data(geo_list = "648", year_range = 1996, magnitude = 5)); cat("empty request (Joplin ZCTAs, 1996, EF5): rows", nrow(e1$result), "; columns kept:", ncol(e1$result), "\n")
cat("message:"); invisible(withCallingHandlers(get_data(geo_list = "648", year_range = 1996, magnitude = 5), message = function(m) { cat(" ", conditionMessage(m)); invokeRestart("muffleMessage") }))
cat("map_exposure with nothing to draw returns a plot: ", inherits(suppressMessages(map_exposure(geo_list = "648", year_range = 1996, magnitude = 5)), "ggplot"), "\n")

hdr("T5: input errors and warnings (exact messages)")
show_err("get_data(c(648), 2010:2015)  [swapped / unnamed arguments]", get_data(c(648), 2010:2015))
z0 <- tornado_exposure$ZCTA[startsWith(tornado_exposure$ZCTA, "0")][1]; z0n <- as.numeric(z0)
cat("\nA Northeast ZCTA with tornado exposure rows:", z0, "(as a number it becomes", z0n, ")\n")
show_err(sprintf("get_data(geo_list = %d, year_range = 1996:2025)  [numeric Northeast ZCTA loses its leading zero]", z0n), get_data(geo_list = z0n, year_range = 1996:2025))
cat(sprintf("  rows with the string \"%s\": %d; rows with the number %d: %d (it is treated as the prefix \"%d\", which matches no ZCTA)\n", z0, nrow(get_data(geo_list = z0, year_range = 1996:2025)), z0n, nrow(suppressMessages(suppressWarnings(get_data(geo_list = z0n, year_range = 1996:2025)))), z0n))
show_err("area_thresh = 0.1  [argument removed]", get_data(geo_list = "648", year_range = 2011, area_thresh = 0.1))
show_err("pop_thresh = 0.1  [argument removed]", get_data(geo_list = "648", year_range = 2011, pop_thresh = 0.1))
show_err("centroid_dist_km and boundary_dist_km together", get_data(geo_list = "648", year_range = 2011, centroid_dist_km = 5, boundary_dist_km = 5))
show_err("centroid_dist_km = 0", get_data(geo_list = "648", year_range = 2011, centroid_dist_km = 0))
show_err("centroid_dist_km = -3", get_data(geo_list = "648", year_range = 2011, centroid_dist_km = -3))
show_err("magnitude = 6", get_data(geo_list = "648", year_range = 2011, magnitude = 6))
show_err("magnitude = \"EF3\"", get_data(geo_list = "648", year_range = 2011, magnitude = "EF3"))
show_err("year_range = 1990:1994  [all years outside the data]", get_data(geo_list = "648", year_range = 1990:1994))
show_err("year_range = 1990:1997  [some years outside]", get_data(geo_list = "648", year_range = 1990:1997))
show_err("year_range = 2030", get_data(geo_list = "648", year_range = 2030))
show_err("geo_list missing", get_data(year_range = 2011))
show_err("year_range missing", get_data(geo_list = "648"))
show_err("geography = \"county\"", get_data(geography = "county", geo_list = "648", year_range = 2011))
show_err("geo_list = \"abc\"", get_data(geo_list = "abc", year_range = 2011))
show_err("map_exposure(feature = \"wind\")", map_exposure(geo_list = "648", year_range = 2011, feature = "wind"))
show_err("map_exposure(layers = \"spc_path\")  [layer removed]", map_exposure(geo_list = "648", year_range = 2011, layers = c("zcta", "spc_path")))
show_err("map_exposure(layers = \"wind\")", map_exposure(geo_list = "648", year_range = 2011, layers = "wind"))
show_err("boundary_dist_km = 0", get_data(geo_list = "648", year_range = 2011, boundary_dist_km = 0))

hdr("T6: a rural and an urban ZCTA with similar NWS area shares but very different resident shares")
d <- tornado_exposure; d$pop_share <- ifelse(d$zcta_pop > 0, d$dat_pop_affected / d$zcta_pop, NA)
x <- d[d$year >= 2010 & d$dat_linked & d$dat_area_share >= 0.04 & d$dat_area_share <= 0.06 & d$zcta_pop > 0, ]
urban <- x[x$zcta_pop >= 10000, ]; urban <- urban[which.max(urban$pop_share), ]
rural <- x[abs(x$dat_area_share - urban$dat_area_share) <= 0.005 & x$dat_pop_affected > 0, ]; rural <- rural[which.min(rural$pop_share), ]
out <- rbind(cbind(case = "rural", rural), cbind(case = "urban", urban))
print(out[, c("case", "tornado_id", "ZCTA", "magnitude", "dat_area_share", "zcta_pop", "dat_pop_affected", "pop_share")], row.names = FALSE)
cat(sprintf("area shares %.3f and %.3f; resident shares %.4f and %.4f (ratio %.0f)\n", rural$dat_area_share, urban$dat_area_share, rural$pop_share, urban$pop_share, urban$pop_share / rural$pop_share))

hdr("T7: clean install in a fresh temporary library and a new R session")
lib <- tempfile("lib"); dir.create(lib); bd <- tempfile("build"); dir.create(bd)
tarball <- { old <- setwd(bd); on.exit(setwd(old), add = TRUE); system2("R", c("CMD", "build", shQuote(file.path(old)), "--no-build-vignettes"), stdout = FALSE, stderr = FALSE); setwd(old); list.files(bd, pattern = "\\.tar\\.gz$", full.names = TRUE) }
cat("tarball:", basename(tarball), sprintf("(%.1f MB)\n", file.size(tarball) / 1024^2))
t_inst <- system.time(system2("R", c("CMD", "INSTALL", paste0("--library=", lib), shQuote(tarball)), stdout = FALSE, stderr = FALSE))
cat(sprintf("install time %.0f s; installed size %s; data %s\n", t_inst[["elapsed"]], system2("du", c("-sh", file.path(lib, "tornadoexposure")), stdout = TRUE) |> strsplit("\t") |> sapply(`[`, 1), system2("du", c("-sh", file.path(lib, "tornadoexposure", "data")), stdout = TRUE) |> strsplit("\t") |> sapply(`[`, 1)))
code <- 'cat("R session:", R.version.string, "\\n"); t <- system.time(library(tornadoexposure)); cat(sprintf("library(tornadoexposure): %.2f s\\n", t[["elapsed"]])); t2 <- system.time(d <- get_data(geo_list = "648", year_range = 2011, magnitude = 5)); cat(sprintf("get_data (Joplin): %.2f s, %d rows\\n", t2[["elapsed"]], nrow(d))); t3 <- system.time(d2 <- suppressMessages(get_data(geo_list = "6", year_range = 1996:2025, centroid_dist_km = 10))); cat(sprintf("get_data centroid_dist_km = 10, ZCTAs starting with 6, 1996-2025: %.1f s, %d rows\\n", t3[["elapsed"]], nrow(d2))); cat("datasets:", paste(data(package = "tornadoexposure")$results[, "Item"], collapse = ", "), "\\n")'
system2("Rscript", c("-e", shQuote(code)), env = paste0("R_LIBS=", lib))
ck_dir <- tempfile("check"); dir.create(ck_dir)
ck <- system2("R", c("CMD", "check", "--no-manual", "-o", shQuote(ck_dir), shQuote(tarball)), stdout = TRUE, stderr = TRUE, env = paste0("_R_CHECK_FORCE_SUGGESTS_=false"))
cat("R CMD check on the tarball:\n"); cat(grep("WARNING|ERROR|NOTE|Status", ck, value = TRUE), sep = "\n")

hdr("T8: a ZCTA whose boundary visibly changed between vintages")
zl <- lapply(c(2000, 2010, 2020), function(v) { z <- tigris::zctas(year = v, progress_bar = FALSE); sfx <- substr(v, 3, 4); z <- z[, c(paste0("ZCTA5CE", sfx), paste0("ALAND", sfx))]; names(z) <- c("ZCTA", "ALAND", "geometry"); z$ALAND <- as.numeric(z$ALAND); z$vint <- v; sf::st_make_valid(sf::st_transform(z, 5070)) })
a10 <- zl[[2]]; a20 <- zl[[3]]
both <- intersect(a10$ZCTA, a20$ZCTA); m10 <- a10[match(both, a10$ZCTA), ]; m20 <- a20[match(both, a20$ZCTA), ]
used <- unique(tornado_exposure$ZCTA[tornado_exposure$year >= 2010 & tornado_exposure$zcta_pop > 0])
ok <- both %in% used
area_or0 <- function(g) if (length(g) == 0 || all(sf::st_is_empty(g))) 0 else as.numeric(sf::st_area(g))
iou <- vapply(which(ok), function(i) { a <- sf::st_geometry(m10)[i]; b <- sf::st_geometry(m20)[i]; area_or0(suppressWarnings(sf::st_intersection(a, b))) / as.numeric(sf::st_area(sf::st_union(a, b))) }, numeric(1))
chg <- data.frame(ZCTA = both[ok], iou = iou, aland10 = m10$ALAND[ok], aland20 = m20$ALAND[ok]); chg$aland_change_pct <- 100 * (chg$aland20 / chg$aland10 - 1)
chg <- chg[order(chg$iou), ]
cat("ZCTAs present in both the 2010 and 2020 files and with tornado exposure since 2010:", nrow(chg), "; with polygon overlap (IoU) below 0.9:", sum(chg$iou < 0.9), "\n")
print(head(chg, 8), row.names = FALSE, digits = 3)
zc <- chg$ZCTA[chg$iou < 0.9 & chg$aland10 > 5e6][1]; cat("chosen ZCTA:", zc, "\n")
tab <- bind_rows(lapply(zl, function(z) { r <- z[z$ZCTA == zc, ]; if (!nrow(r)) NULL else data.frame(vintage = r$vint, aland_km2 = r$ALAND / 1e6, polygon_km2 = as.numeric(sf::st_area(r)) / 1e6) }))
print(tab, row.names = FALSE, digits = 4)
cat("population-weighted centroid by vintage:\n"); print(zcta_centroids[zcta_centroids$ZCTA == zc, ], row.names = FALSE)
ex <- tornado_exposure[tornado_exposure$ZCTA == zc, c("tornado_id", "year", "line_share_of_tornado", "zcta_pop")]
cat("exposure rows for this ZCTA (the vintage follows the tornado's year):\n"); print(head(ex[order(ex$year), ], 6), row.names = FALSE)
png(qa_out("trials_T8_vintages.png"), width = 1500, height = 500, res = 120); par(mfrow = c(1, 3), mar = c(1, 1, 3, 1))
for (z in zl) { r <- z[z$ZCTA == zc, ]; if (nrow(r)) plot(sf::st_geometry(r), main = paste(zc, r$vint), col = "grey85") else plot.new() }; dev.off()
cat("plot saved to", qa_out("trials_T8_vintages.png"), "\n")
