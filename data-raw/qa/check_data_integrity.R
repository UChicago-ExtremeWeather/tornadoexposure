# Run from the package root after every data update:  Rscript data-raw/qa/check_data_integrity.R
# Checks the bundled datasets in data/ (no network needed). Every failed check is listed and the
# script stops with an error if there is any.
suppressMessages(library(sf))
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
fails <- character(); n_checks <- 0L
check <- function(name, ok) {
  ok <- isTRUE(ok); n_checks <<- n_checks + 1L
  cat(if (ok) "ok    " else "FAIL  ", name, "\n", sep = "")
  if (!ok) fails <<- c(fails, name)
}
d <- tornado_exposure; tr <- tornado_tracks; t0 <- st_drop_geometry(tr); vint_ <- ifelse(d$year < 2010, 2000L, ifelse(d$year < 2020, 2010L, 2020L))
area_cols <- paste0("dat_area_share_ef", 0:5); pop_cols <- paste0("dat_pop_ef", 0:5); pt_cols <- c(paste0("dat_points_ef", 0:5), "dat_points_efu", "dat_points_wind", "dat_points_other")

# ---- spc_records ----------------------------------------------------------------------------
check("spc_records has one row per SPC record of 1996 on (every sg), with tornado_id first", names(spc_records)[1] == "tornado_id" && all(spc_records$yr >= 1996) && all(c("om", "yr", "mo", "dy", "date", "time", "tz", "st", "stf", "mag", "inj", "fat", "loss", "closs", "slat", "slon", "elat", "elon", "len", "wid", "ns", "sn", "sg", "f1", "f2", "f3", "f4", "fc") %in% names(spc_records)))
whole <- spc_records[spc_records$sg == 1, ]
check("every whole-track record (sg 1) is one tornado in tornado_tracks, and the other way round", setequal(whole$tornado_id, tr$tornado_id) && !anyDuplicated(whole$tornado_id) && nrow(whole) == nrow(tr))
w <- whole[match(tr$tornado_id, whole$tornado_id), ]
check("SPC start and end coordinates, len and wid in tornado_tracks are identical to the SPC record", identical(t0$slat, w$slat) && identical(t0$slon, w$slon) && identical(t0$elat, w$elat) && identical(t0$elon, w$elon) && identical(t0$len_mi, w$len) && identical(t0$wid_yd, w$wid))
check("rating, injuries, deaths and raw loss in tornado_tracks are identical to the SPC record", identical(t0$total_injury, w$inj) && identical(t0$total_fatality, w$fat) && identical(t0$loss_raw, w$loss) && identical(t0$magnitude, ifelse(w$mag == -9, NA_integer_, as.integer(w$mag))))

# ---- tornado_tracks -----------------------------------------------------------------------
check("tornado_tracks is an sf object in EPSG:4326", inherits(tr, "sf") && identical(st_crs(tr)$epsg, 4326L))
check("tornado_id is unique in tracks", !anyDuplicated(tr$tornado_id))
check("track_type is line or point", all(t0$track_type %in% c("line", "point")))
bad_end <- is.na(t0$elon) | is.na(t0$elat) | t0$elon == 0 | t0$elat == 0 | (t0$slon == t0$elon & t0$slat == t0$elat)
check("track_type is point exactly where the end coordinates are missing, 0 or equal to the start", identical(t0$track_type == "point", bad_end))
g <- st_geometry(tr)
check("a line track is a LINESTRING from the raw start to the raw end, a point track is a POINT at the raw start",
      all(st_geometry_type(g)[t0$track_type == "line"] == "LINESTRING") && all(st_geometry_type(g)[t0$track_type == "point"] == "POINT") &&
        all(vapply(which(t0$track_type == "line")[1:200], function(i) identical(unname(unclass(g[[i]])), unname(rbind(c(t0$slon[i], t0$slat[i]), c(t0$elon[i], t0$elat[i])))), logical(1))) &&
        all(vapply(which(t0$track_type == "point")[1:200], function(i) identical(as.numeric(g[[i]]), c(t0$slon[i], t0$slat[i])), logical(1))))
check("a width of 0 is never replaced: wid_yd has zeros and no value is changed", sum(t0$wid_yd == 0, na.rm = TRUE) > 0 && min(t0$wid_yd, na.rm = TRUE) == 0)
check("no polygon or modeled column exists for SPC: no modeled_path_area_m2 in tracks and no modeled_ column in exposure", !"modeled_path_area_m2" %in% names(t0) && !any(grepl("^modeled_", names(d))) && !any(grepl("area_thresh|pop_thresh", names(d))))
check("len_ratio is NA for point tracks", all(is.na(t0$len_ratio[t0$track_type == "point"])))
check("there are no point_equal_area or point_half_width tracks and no width_imputed column", !any(grepl("point_", t0$track_type)) && !"width_imputed" %in% names(t0) && !"tornado_area_m2" %in% names(t0))
check("line_km and line_km_outside_zcta are NA exactly for point tracks, line_km is positive for lines, and 0 <= line_km_outside_zcta <= line_km", identical(is.na(t0$line_km), t0$track_type == "point") && identical(is.na(t0$line_km_outside_zcta), t0$track_type == "point") && all(t0$line_km[t0$track_type == "line"] > 0) && all(t0$line_km_outside_zcta >= 0 & t0$line_km_outside_zcta <= t0$line_km + 1e-9, na.rm = TRUE))

# ---- tornado_exposure -------------------------------------------------------------------
check("tornado_id and ZCTA pairs are unique", !anyDuplicated(d[c("tornado_id", "ZCTA")]))
for (k in c("tornado_id", "date", "year", "month", "day", "ZCTA", "track_type", "total_injury", "total_fatality", "spc_exposed", "boundary_dist_km", "centroid_dist_km", "zcta_polygon_area_m2", "zcta_land_area_m2", "zcta_land_shape_area_m2", "zcta_pop", "dat_linked"))
  check(paste("no missing values in", k), !anyNA(d[[k]]))
check("ZCTA is a character vector of 5 digits", is.character(d$ZCTA) && all(grepl("^[0-9]{5}$", d$ZCTA)))
check("magnitude is 0 to 5 or NA", all(d$magnitude %in% c(0:5, NA)))
check("track_type agrees between exposure and tracks", identical(d$track_type, tr$track_type[match(d$tornado_id, tr$tornado_id)]))
check("every tornado_id in exposure exists in tracks", all(d$tornado_id %in% tr$tornado_id))
sp <- d[d$spc_exposed, ]; lo <- d[!d$spc_exposed, ]
check("a point tornado has exactly one SPC row unless its start lies on a ZCTA boundary, and its share is 1 / the number of rows", { n <- table(sp$tornado_id[sp$track_type == "point"]); all(n >= 1L) && all(abs(sp$line_share_of_tornado[sp$track_type == "point"] - 1 / n[sp$tornado_id[sp$track_type == "point"]]) < 1e-12) })
check("line_km_in_zcta and line_share_of_tornado are NA exactly where the SPC line does not cross (spc_exposed FALSE), and line_km_in_zcta is also NA for points", all(is.na(lo$line_km_in_zcta)) && all(is.na(lo$line_share_of_tornado)) && all(is.na(lo$property_loss_allocated)) && all(!is.na(sp$line_share_of_tornado)) && identical(is.na(sp$line_km_in_zcta), sp$track_type == "point") && all(sp$line_km_in_zcta[sp$track_type == "line"] > 0))
check("line_share_of_tornado sums to 1 for every tornado with an SPC row", all(abs(tapply(sp$line_share_of_tornado, sp$tornado_id, sum) - 1) < 1e-9))
check("line_km_in_zcta plus line_km_outside_zcta equals line_km for every line (to 1e-6 km)", { s <- tapply(sp$line_km_in_zcta[sp$track_type == "line"], sp$tornado_id[sp$track_type == "line"], sum); m <- match(names(s), tr$tornado_id); all(abs(s + t0$line_km_outside_zcta[m] - t0$line_km[m]) < 1e-6) })
check("every line tornado with no SPC row has line_km_outside_zcta equal to line_km", { x <- t0[t0$track_type == "line" & !t0$tornado_id %in% sp$tornado_id, ]; all(x$line_km_outside_zcta == x$line_km) })
check("boundary_dist_km and centroid_dist_km are not negative and have no missing value", all(d$boundary_dist_km >= 0) && all(d$centroid_dist_km >= 0))
check("boundary_dist_km is 0 exactly where spc_exposed is TRUE", all(d$boundary_dist_km[d$spc_exposed] == 0) && all(d$boundary_dist_km[!d$spc_exposed] > 0))
cen_in <- zcta_centroids$centroid_in_zcta[match(paste(d$ZCTA, vint_), paste(zcta_centroids$ZCTA, zcta_centroids$vintage))]
check("boundary_dist_km is not larger than centroid_dist_km where the centroid lies inside the ZCTA", all(d$boundary_dist_km[cen_in] <= d$centroid_dist_km[cen_in] + 1e-9))
check("zcta_land_shape_area_m2 is positive for every row and not larger than the polygon area", all(d$zcta_land_shape_area_m2 > 0) && all(d$zcta_land_shape_area_m2 <= d$zcta_polygon_area_m2 * (1 + 1e-9)))

# loss: NA exactly where SPC recorded 0; allocated loss sums back to the tornado total
check("property_loss_allocated is NA exactly where the tornado total is NA or the line does not cross the ZCTA", identical(is.na(d$property_loss_allocated), is.na(d$property_loss_tornado_total) | !d$spc_exposed))
check("tornado loss is constant within a tornado", all(tapply(d$property_loss_tornado_total, d$tornado_id, function(x) length(unique(x))) == 1L))
tot <- tapply(sp$property_loss_tornado_total, sp$tornado_id, function(x) x[1]); al <- tapply(sp$property_loss_allocated, sp$tornado_id, sum)
kn <- !is.na(tot)
check("some tornadoes have known loss", sum(kn) > 0)
check("allocated loss sums to the tornado total (known loss, SPC rows)", all(abs(al[kn] - tot[kn]) <= 1e-8 * pmax(1, tot[kn])))
check("loss units are 'millions' or 'dollars'", all(tr$loss_raw_unit %in% c("millions", "dollars")))
yr <- as.integer(substr(tr$tornado_id, 1, 4))
check("loss is in millions through 2006 and in dollars from 2007", all(tr$loss_raw_unit[yr <= 2006] == "millions") && all(tr$loss_raw_unit[yr >= 2007] == "dollars"))
raw <- tr$loss_raw; unit <- tr$loss_raw_unit; ex <- raw * ifelse(unit == "millions", 1e6, 1)
check("loss in dollars = raw value (times 1e6 if in millions), NA where SPC recorded 0, with no rounding beyond floating-point error",
      identical(is.na(tr$property_loss_tornado_total), raw == 0) && all(abs(tr$property_loss_tornado_total - ex)[raw > 0] <= 1e-9 * ex[raw > 0]))
nz <- tr[tr$loss_raw > 0, ]; med <- tapply(nz$loss_raw, as.integer(substr(nz$tornado_id, 1, 4)), median)
check("yearly median nonzero loss is below 1 (millions) through 2006 and at least 10,000 (dollars) from 2007",
      all(med[as.integer(names(med)) <= 2006] < 1) && all(med[as.integer(names(med)) >= 2007] >= 10000))
check("zcta_pop is not negative and is one value per ZCTA and boundary year", all(d$zcta_pop >= 0) && all(tapply(d$zcta_pop, paste(vint_, d$ZCTA), function(x) length(unique(x))) == 1L))

# DAT columns
lk <- tornado_dat_link; linked <- d$tornado_id %in% lk$tornado_id
check("dat_linked is TRUE exactly for tornadoes in tornado_dat_link", identical(d$dat_linked, linked))
check("dat_line_ids lists the linked lines (separated by ;) and is NA without a link", identical(is.na(d$dat_line_ids), !linked) && all(d$dat_line_ids[linked] == vapply(split(lk$dat_line_id, lk$tornado_id), function(x) paste(sort(x), collapse = ";"), "")[d$tornado_id[linked]]))
mx <- tapply(lk$one_sided_dist_km, lk$tornado_id, max)
check("dat_link_dist_km is NA exactly where dat_linked is FALSE and equals the largest one_sided_dist_km of the tornado's links in tornado_dat_link", identical(is.na(d$dat_link_dist_km), !d$dat_linked) && identical(d$dat_link_dist_km[linked], as.numeric(mx[d$tornado_id[linked]])))
check("dat_link_dist_km is one value per tornado, is not negative, and is in the tract and block-group tables (no NA, the largest one_sided_dist_km of the tornado)", all(tapply(d$dat_link_dist_km[linked], d$tornado_id[linked], function(x) length(unique(x))) == 1L) && all(d$dat_link_dist_km[linked] >= 0) &&
  all(vapply(list(dat_exposure_tract, dat_exposure_blockgroup), function(u) !anyNA(u$dat_link_dist_km) && identical(u$dat_link_dist_km, as.numeric(mx[u$tornado_id])), TRUE)))
check("all DAT columns are NA without a link, and none is NA with a link except dat_exposed rules", all(is.na(d[!linked, c("dat_exposed", "dat_area_share", area_cols, "dat_pop_affected", pop_cols, pt_cols, "other_tornadoes_in_zcta_within_a_day")])) && !anyNA(d[linked, c("dat_exposed", "dat_area_share", area_cols, "dat_pop_affected", pop_cols)]))
check("dat_exposed is TRUE exactly where dat_area_share is above 0", identical(d$dat_exposed[linked], d$dat_area_share[linked] > 0))
check("every row is exposed by a source: spc_exposed or dat_exposed", all(d$spc_exposed | d$dat_exposed %in% TRUE))
check("rows with spc_exposed FALSE all have dat_exposed TRUE (the ZCTAs only the NWS polygons expose)", all(lo$dat_exposed %in% TRUE))
check("dat_area_share_ef0 to ef5 sum to dat_area_share, and dat_pop_ef0 to ef5 to dat_pop_affected", isTRUE(all.equal(unname(rowSums(d[linked, area_cols])), d$dat_area_share[linked], tolerance = 1e-12)) && isTRUE(all.equal(unname(rowSums(d[linked, pop_cols])), d$dat_pop_affected[linked], tolerance = 1e-9)))
check("land-only shares never exceed 1 (not capped), and are not negative", all(d$dat_area_share <= 1 + 1e-9, na.rm = TRUE) && all(d[linked, area_cols] >= 0) && all(d[linked, pop_cols] >= 0))
check("dat_pop_affected does not exceed zcta_pop by more than floating-point error", all(d$dat_pop_affected <= d$zcta_pop * (1 + 1e-9) + 1e-6, na.rm = TRUE))
check("damage point counts are whole numbers, not negative", all(unlist(d[linked, pt_cols]) >= 0) && is.integer(d$dat_points_ef0) && is.integer(d$other_tornadoes_in_zcta_within_a_day))
check("the SPC rows are the rows that a tornado's line crosses: every SPC row has a tornado with a line or a point", all(sp$tornado_id %in% tr$tornado_id))
check("dat_exposure_tract and dat_exposure_blockgroup: unique tornado and unit, shares by rating sum to the total, shares not above 1, no SPC columns", {
  ok <- TRUE; for (u in list(dat_exposure_tract, dat_exposure_blockgroup)) ok <- ok && !anyDuplicated(u[c("tornado_id", "GEOID")]) && isTRUE(all.equal(unname(rowSums(u[area_cols])), u$dat_area_share, tolerance = 1e-12)) && isTRUE(all.equal(unname(rowSums(u[pop_cols])), u$dat_pop_affected, tolerance = 1e-9)) && all(u$dat_area_share <= 1 + 1e-9) && all(u$dat_area_share > 0) && !any(grepl("spc_|line_|modeled", names(u)))
  ok && all(nchar(dat_exposure_tract$GEOID) == 11) && all(nchar(dat_exposure_blockgroup$GEOID) == 12) })
check("tract and block-group tornadoes are linked tornadoes with a footprint, the two tables hold the same tornadoes, and every tornado with a ZCTA row exposed by the polygons is in them", all(dat_exposure_tract$tornado_id %in% lk$tornado_id) && setequal(dat_exposure_tract$tornado_id, dat_exposure_blockgroup$tornado_id) && all(d$tornado_id[d$dat_exposed %in% TRUE] %in% dat_exposure_tract$tornado_id))

# ---- zcta_centroids -------------------------------------------------------------------------
cen <- zcta_centroids
check("zcta_centroids has the expected columns", identical(names(cen), c("ZCTA", "vintage", "lon", "lat", "centroid_type", "centroid_in_zcta", "zcta_pop", "zcta_land_area_m2", "zcta_polygon_area_m2", "zcta_land_shape_area_m2")))
check("zcta_centroids has no missing values", !anyNA(cen))
check("zcta_centroids is unique by ZCTA and boundary year", !anyDuplicated(cen[c("ZCTA", "vintage")]))
check("zcta_centroids covers boundary years 2000, 2010 and 2020", setequal(cen$vintage, c(2000L, 2010L, 2020L)))
check("centroid_type is 'population' or 'geometric'", all(cen$centroid_type %in% c("population", "geometric")))
check("geometric centroids are exactly the ZCTAs with no residents", all((cen$zcta_pop == 0) == (cen$centroid_type == "geometric")))
check("centroid coordinates are not rounded (not all at 5 decimals)", mean(abs(cen$lon * 1e5 - round(cen$lon * 1e5)) < 1e-6) < 0.01)
m <- merge(unique(data.frame(ZCTA = d$ZCTA, vintage = as.integer(vint_), zp = d$zcta_pop, la = d$zcta_land_area_m2, pa = d$zcta_polygon_area_m2, ls = d$zcta_land_shape_area_m2)), cen, by = c("ZCTA", "vintage"))
check("zcta_pop and the ZCTA areas agree between exposure and centroids", nrow(m) == nrow(unique(data.frame(d$ZCTA, vint_))) && all(m$zp == m$zcta_pop) && all(m$la == m$zcta_land_area_m2) && all(m$pa == m$zcta_polygon_area_m2) && all(m$ls == m$zcta_land_shape_area_m2))
check("the land-only shape never has more area than the polygon, and is within 1 percent of the Census land area for most ZCTAs", all(cen$zcta_land_shape_area_m2 <= cen$zcta_polygon_area_m2 * (1 + 1e-9)) && mean(abs(cen$zcta_land_shape_area_m2 / cen$zcta_land_area_m2 - 1) <= 0.01, na.rm = TRUE) > 0.98)

# ---- DAT datasets and link tables -----------------------------------------------------------
fetch <- readRDS("data-raw/dat/fetch/fetch_summary.rds")
check("every DAT feature of the service is kept: counts equal the counts the service reported", nrow(dat_points) == fetch$count_reported[fetch$layer == 0] && nrow(dat_lines) == fetch$count_reported[fetch$layer == 1] && nrow(dat_polygons) == fetch$count_reported[fetch$layer == 2])
check("the DAT datasets are sf objects in EPSG:4326 with unique objectid", all(vapply(list(dat_points, dat_lines, dat_polygons), function(x) inherits(x, "sf") && identical(st_crs(x)$epsg, 4326L) && !anyDuplicated(x$objectid), logical(1))))
chk_utc <- function(x, f) isTRUE(all.equal(as.numeric(x[[paste0(f, "_utc")]]), as.numeric(x[[f]]) / 1000)) && is.numeric(x[[f]])
check("every DAT date field keeps the raw milliseconds (numeric) and has a _utc copy", chk_utc(dat_points, "stormdate") && chk_utc(dat_lines, "stormdate") && chk_utc(dat_polygons, "stormdate") && chk_utc(dat_lines, "starttime") && chk_utc(dat_points, "surveydate"))
check("DAT lines and polygons have not been simplified: a line keeps its vertices as the service gave them (the median line has more than 2 vertices)", median(vapply(st_geometry(dat_lines)[!st_is_empty(dat_lines)], nrow, 1L)) > 2)
fl <- list.files("data-raw/dat/fetch/pages", pattern = "^layer1_", full.names = TRUE); js <- jsonlite::fromJSON(paste(readLines(gzfile(fl[1]), warn = FALSE), collapse = ""), simplifyVector = FALSE)
f1 <- js$features[[1]]; g1 <- do.call(rbind, lapply(f1$geometry$paths[[1]], function(p) unlist(p)[1:2])); l1 <- st_coordinates(dat_lines[dat_lines$objectid == f1$attributes$objectid, ])[, 1:2]
check("the first DAT line equals the service's response coordinate for coordinate (no rounding)", isTRUE(all.equal(unname(g1), unname(l1), tolerance = 0)))
lk <- tornado_dat_link
check("tornado_dat_link has the columns of the documented table", identical(names(lk), c("tornado_id", "dat_line_id", "index_aligned_dist_km", "one_sided_dist_km", "length_ratio", "direction_diff_deg", "same_state", "n_candidates_tornado", "n_candidates_line", "second_dist_tornado_km", "second_dist_line_km", "relationship", "rule")))
check("every DAT line is linked to at most one tornado, and every link has a tornado and a line", !anyDuplicated(lk$dat_line_id) && all(lk$tornado_id %in% tr$tornado_id) && all(lk$dat_line_id %in% dat_lines$objectid))
check("rule is mutual_closest or attached_to_paired; every attached line is attached to a tornado that has a mutual-closest line", all(lk$rule %in% c("mutual_closest", "attached_to_paired")) && all(lk$tornado_id[lk$rule == "attached_to_paired"] %in% lk$tornado_id[lk$rule == "mutual_closest"]))
check("each tornado has at most one mutual-closest line", !anyDuplicated(lk$tornado_id[lk$rule == "mutual_closest"]))
check("relationship is one_to_many exactly for tornadoes with more than one linked line", identical(lk$relationship == "one_to_many", lk$tornado_id %in% lk$tornado_id[duplicated(lk$tornado_id)]))
check("distances are not negative, and the second-closest distance is at least the closest", all(lk$index_aligned_dist_km >= 0) && all(lk$one_sided_dist_km >= 0) && all(lk$second_dist_tornado_km[lk$rule == "mutual_closest"] >= lk$index_aligned_dist_km[lk$rule == "mutual_closest"] - 1e-9, na.rm = TRUE))
check("direction_diff_deg is in [0, 180], NA for point tornadoes", all(lk$direction_diff_deg >= 0 & lk$direction_diff_deg <= 180, na.rm = TRUE) && all(is.na(lk$direction_diff_deg[lk$tornado_id %in% tr$tornado_id[tr$track_type == "point"]])))
pl <- dat_polygon_line_link
check("dat_polygon_line_link has one row per polygon and line pair, columns documented, shares in [0, 1] up to floating point", identical(names(pl), c("dat_polygon_id", "dat_line_id", "dist_km", "line_share_in_polygon")) && !anyDuplicated(pl[c("dat_polygon_id", "dat_line_id")]) && all(pl$line_share_in_polygon >= 0 & pl$line_share_in_polygon <= 1 + 1e-9) && all(pl$dist_km >= 0) && all(pl$line_share_in_polygon[pl$dist_km > 0] == 0))
check("dat_polygon_line_link ids exist in the datasets", all(pl$dat_polygon_id %in% dat_polygons$objectid) && all(pl$dat_line_id %in% dat_lines$objectid))

# ---- known case ---------------------------------------------------------------------------------
# The St. Louis tornado of 16 May 2025 (SPC 2025_2505161339-01, one record of 23.22 miles across Missouri and Illinois): NWS surveyed two separate tornadoes from one storm circulation
# (EF3, DAT line 2671973, and EF1, DAT line 2671572). Both lines are linked to the one SPC record.
sl <- lk[lk$tornado_id == "2025_2505161339-01", ]; sz <- d[d$tornado_id == "2025_2505161339-01", ]
check("St. Louis 2025_2505161339-01 is linked to DAT lines 2671572 (EF1) and 2671973 (EF3), one mutual-closest and one attached, one_to_many", setequal(sl$dat_line_id, c(2671572L, 2671973L)) && all(sl$relationship == "one_to_many") && setequal(sl$rule, c("mutual_closest", "attached_to_paired")))
check("St. Louis: the index-aligned distance of the line that is the mutual closest is 8.99 or 9.11 km and the one-sided distances are below 2 km", all(round(sl$index_aligned_dist_km, 2) %in% c(8.99, 9.11)) && all(sl$one_sided_dist_km < 2))
check("St. Louis: SPC rows in Missouri (63...) and Illinois (62...) ZCTAs, rating 2, and DAT-only ZCTAs (spc_exposed FALSE) are flagged", any(substr(sz$ZCTA[sz$spc_exposed], 1, 2) == "63") && any(substr(sz$ZCTA[sz$spc_exposed], 1, 2) == "62") && all(sz$magnitude == 2) && sum(sz$spc_exposed) > 0 && all(sz$dat_linked) && all(sz$dat_line_ids == "2671572;2671973") && all(sz$dat_exposed[!sz$spc_exposed]))
check("St. Louis: line shares sum to 1, and the DAT area shares by rating sum to the total", abs(sum(sz$line_share_of_tornado, na.rm = TRUE) - 1) < 1e-9 && isTRUE(all.equal(unname(rowSums(sz[area_cols])), sz$dat_area_share, tolerance = 1e-12)) && any(sz$dat_area_share > 0) && any(sz$dat_area_share_ef3 > 0) && any(sz$dat_area_share_ef1 > 0))
if (length(fails)) stop(length(fails), " check(s) failed:\n  ", paste(fails, collapse = "\n  "), call. = FALSE)
cat("\nAll", n_checks, "checks passed.\n")
