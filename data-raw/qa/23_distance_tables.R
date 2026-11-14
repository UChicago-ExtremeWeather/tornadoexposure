# Run from the package root after a rebuild:  Rscript data-raw/qa/23_distance_tables.R      (slow: the 50 km nationwide centroid query takes several minutes; REUSE=1 reuses the saved radius table)
# Computes, with the package's own distance code, (1) the nationwide centroid-distance query by radius (rows, tornadoes without a row, how many of the overlap pairs have the centroid within the radius,
# seconds) and (2) the exposure definitions compared for the Joplin tornado, and writes the section "Exposure definitions and distance exposure" of data-raw/known_issues.md (between <!-- distance:start --> and <!-- distance:end -->).
# The seconds are the measured times that R/distance.R uses for its time estimate (.distance_timings).
suppressMessages({devtools::load_all(quiet = TRUE); library(dplyr); library(sf)})
source("data-raw/qa/helpers.R"); options(width = 170, tigris_use_cache = TRUE); sf_use_s2(FALSE)
f0 <- function(x, d = 1) formatC(x, format = "f", digits = d, big.mark = ","); pc <- function(x, d = 1) paste0(f0(100 * x, d), "%")
md <- function(df) { df[] <- lapply(df, as.character); paste(c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"), apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))), collapse = "\n") }
tt <- .tracks(); ex <- .exposure(); ex <- ex[ex$spc_exposed, ]; cen <- .centroids(); yr <- as.integer(substr(tt$tornado_id, 1, 4)); vint <- .vintage_of(yr); region <- .distance_region(tt)
key <- function(id, z) paste(id, z); ov_key <- key(ex$tornado_id, ex$ZCTA)
rad <- c(1, 5, 10, 25, 50)
if (identical(Sys.getenv("REUSE"), "1") && file.exists(qa_out("distance_tables.rds"))) tab <- readRDS(qa_out("distance_tables.rds"))$tab else {
  tab <- bind_rows(lapply(rad, function(R) { t0 <- proc.time()[3]
    pr <- .distance_pairs(region, vint, cen$vintage, R, make_geom = function(i, crs) sf::st_transform(sf::st_geometry(tt)[i], crs), make_target = function(j, crs) .centroid_points(cen[j, , drop = FALSE], crs))
    secs <- proc.time()[3] - t0; k <- key(tt$tornado_id[pr$i], cen$ZCTA[pr$j])
    data.frame(radius_km = R, rows = nrow(pr), tornadoes_without_a_row = nrow(tt) - length(unique(pr$i)), seconds = round(secs), overlap_pairs_within_radius = mean(ov_key %in% k), rows_not_in_overlap_set = mean(!k %in% ov_key)) })) }
saveRDS(list(tab = tab), qa_out("distance_tables.rds"))
# Joplin: the definitions compared (geo_list covers the ZCTAs of the tornado and its neighbours)
id <- "2011_1105221634-01"; gl <- c("647", "648", "649")
defs <- list(`exposed (default)` = quote(get_data(geo_list = gl, year_range = 2011, magnitude = 5)),
  `centroid_dist_km = 1` = quote(get_data(geo_list = gl, year_range = 2011, magnitude = 5, centroid_dist_km = 1)), `centroid_dist_km = 5` = quote(get_data(geo_list = gl, year_range = 2011, magnitude = 5, centroid_dist_km = 5)),
  `centroid_dist_km = 10` = quote(get_data(geo_list = gl, year_range = 2011, magnitude = 5, centroid_dist_km = 10)), `boundary_dist_km = 1` = quote(get_data(geo_list = gl, year_range = 2011, magnitude = 5, boundary_dist_km = 1)),
  `boundary_dist_km = 5` = quote(get_data(geo_list = gl, year_range = 2011, magnitude = 5, boundary_dist_km = 5)))
jp <- bind_rows(lapply(names(defs), function(nm) { x <- suppressMessages(eval(defs[[nm]])); x <- x[x$tornado_id == id, ]; data.frame(Definition = nm, ZCTAs = nrow(x), `ZCTA codes` = paste(x$ZCTA, collapse = " "), check.names = FALSE) }))
spc <- ex[ex$tornado_id == id, ]
txt <- c("<!-- distance:start -->", "## Exposure definitions and distance exposure", "",
 "A call uses one exposure definition. The default returns the rows of `tornado_exposure`: the ZCTAs that a positive length of the SPC line lies in (the ZCTA that contains the start point, for a tornado with no usable end point) and the ZCTAs in which a linked NWS polygon covers land. `centroid_dist_km` and `boundary_dist_km` are measured from the SPC line (the start point for a tornado with no usable end point) and have no upper limit; a ZCTA with a positive `boundary_dist_km` is not crossed by the line.", "",
 paste0("**Joplin, Missouri, 22 May 2011** (`", id, "`, EF5, ", nrow(spc), " ZCTAs crossed by the SPC line: ", paste(spc$ZCTA, collapse = " "), "), with the ZCTAs starting with 647, 648 or 649 (the radii are examples, not recommendations):"), "", md(jp), "",
 "**Nationwide centroid-distance query** (every tornado, every ZCTA of each boundary year, one core; `seconds` is the time of the query and is the basis of the time estimate that `get_data()` prints for large requests):", "",
 md(data.frame(`Radius (km)` = tab$radius_km, `Tornado-ZCTA rows` = f0(tab$rows, 0), `Tornadoes without a row` = f0(tab$tornadoes_without_a_row, 0), Seconds = tab$seconds, `SPC-exposed pairs with the centroid within the radius` = pc(tab$overlap_pairs_within_radius), `Rows that are not SPC-exposed pairs` = pc(tab$rows_not_in_overlap_set), check.names = FALSE)), "",
 "The result of a centroid-distance call is not a superset of the SPC-exposed set: a large ZCTA crossed at its edge can have a centroid farther than the radius, as the share of exposed pairs within each radius shows. The distance from the SPC line to the centroid is measured in a projection that suits the region (EPSG:5070 in the 48 states, EPSG:3338 in Alaska, ESRI:102007 in Hawaii, EPSG:32161 in Puerto Rico).",
 "<!-- distance:end -->")
kl <- readLines("data-raw/known_issues.md"); a <- grep("<!-- distance:start -->", kl, fixed = TRUE); b <- grep("<!-- distance:end -->", kl, fixed = TRUE)
kl <- c(kl[seq_len(a - 1)], txt, kl[-seq_len(b)]); writeLines(kl, "data-raw/known_issues.md"); cat(txt, sep = "\n")
dt <- sprintf("seconds = c(%s)", paste(tab$seconds, collapse = ", ")); cat("\n.distance_timings in R/distance.R should read: radius_km = c(1, 5, 10, 25, 50),", dt, "\n")
