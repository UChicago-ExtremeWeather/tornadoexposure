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
modeled <- c("modeled_intersection_m2", "modeled_area_prop", "modeled_pop_affected", "modeled_pop_prop", "modeled_area_share_of_tornado", "modeled_property_loss_allocated")

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
check("modeled_path_area_m2 is positive for a line with a positive width and NA otherwise", identical(is.na(t0$modeled_path_area_m2), !(t0$track_type == "line" & !is.na(t0$wid_yd) & t0$wid_yd > 0)) && all(t0$modeled_path_area_m2 > 0, na.rm = TRUE))
check("len_ratio is NA for point tracks", all(is.na(t0$len_ratio[t0$track_type == "point"])))
check("there are no point_equal_area or point_half_width tracks and no width_imputed column", !any(grepl("point_", t0$track_type)) && !"width_imputed" %in% names(t0) && !"tornado_area_m2" %in% names(t0))

# ---- tornado_exposure -------------------------------------------------------------------
check("tornado_id and ZCTA pairs are unique", !anyDuplicated(d[c("tornado_id", "ZCTA")]))
for (k in c("tornado_id", "date", "year", "month", "day", "ZCTA", "track_type", "total_injury", "total_fatality", "boundary_dist_km", "centroid_dist_km", "zcta_polygon_area_m2", "zcta_land_area_m2", "zcta_pop"))
  check(paste("no missing values in", k), !anyNA(d[[k]]))
check("ZCTA is a character vector of 5 digits", is.character(d$ZCTA) && all(grepl("^[0-9]{5}$", d$ZCTA)))
check("magnitude is 0 to 5 or NA", all(d$magnitude %in% c(0:5, NA)))
check("track_type agrees between exposure and tracks", identical(d$track_type, tr$track_type[match(d$tornado_id, tr$tornado_id)]))
check("every tornado_id in exposure exists in tracks", all(d$tornado_id %in% tr$tornado_id))
noshape <- d$track_type == "point" | t0$wid_yd[match(d$tornado_id, tr$tornado_id)] == 0
check("the modeled columns are NA exactly for tornadoes with no usable end point and for lines with a width of 0", all(is.na(d[noshape, modeled])) && !any(is.na(d$modeled_intersection_m2[!noshape])) && !any(is.na(d$modeled_area_prop[!noshape])) && !any(is.na(d$modeled_pop_affected[!noshape])))
check("a point tornado has exactly one row (the ZCTA that contains the start point)", all(table(d$tornado_id[d$track_type == "point"]) == 1L))
check("modeled_area_prop is above 0 and is not capped (no cap anywhere)", all(d$modeled_area_prop > 0, na.rm = TRUE) && isTRUE(all.equal(d$modeled_area_prop, d$modeled_intersection_m2 / d$zcta_polygon_area_m2)))
check("modeled_area_share_of_tornado sums to 1 for every tornado with a modeled path", all(abs(tapply(d$modeled_area_share_of_tornado[!noshape], d$tornado_id[!noshape], sum) - 1) < 1e-9))
check("modeled_intersection_m2 summed over a tornado's ZCTAs does not exceed its modeled path area", { s <- tapply(d$modeled_intersection_m2[!noshape], d$tornado_id[!noshape], sum); all(s <= t0$modeled_path_area_m2[match(names(s), tr$tornado_id)] * (1 + 1e-9)) })
check("boundary_dist_km and centroid_dist_km are not negative", all(d$boundary_dist_km >= 0) && all(d$centroid_dist_km >= 0))
check("boundary_dist_km is 0 for every ZCTA that holds a point tornado's start or a centerline, and for most rows of a modeled path", all(d$boundary_dist_km[noshape] == 0) && mean(d$boundary_dist_km[!noshape] == 0) > 0.9)
cen_in <- zcta_centroids$centroid_in_zcta[match(paste(d$ZCTA, vint_), paste(zcta_centroids$ZCTA, zcta_centroids$vintage))]
check("boundary_dist_km is not larger than centroid_dist_km where the centroid lies inside the ZCTA", all(d$boundary_dist_km[cen_in] <= d$centroid_dist_km[cen_in] + 1e-9))
check("zcta_land_area_m2 is not larger than zcta_polygon_area_m2 by more than 1e-6 relative (ALAND excludes water), unless the polygon is the smaller", mean(d$zcta_land_area_m2 <= d$zcta_polygon_area_m2 * (1 + 1e-6)) > 0.99)

# loss: NA exactly where SPC recorded 0; allocated loss sums back to the tornado total
check("modeled_property_loss_allocated is NA exactly where the tornado total or the modeled path is NA", identical(is.na(d$modeled_property_loss_allocated), is.na(d$property_loss_tornado_total) | noshape))
check("tornado loss is constant within a tornado", all(tapply(d$property_loss_tornado_total, d$tornado_id, function(x) length(unique(x))) == 1L))
ok <- !noshape
tot <- tapply(d$property_loss_tornado_total[ok], d$tornado_id[ok], function(x) x[1]); al <- tapply(d$modeled_property_loss_allocated[ok], d$tornado_id[ok], sum)
kn <- !is.na(tot)
check("some tornadoes have known loss", sum(kn) > 0)
check("allocated loss sums to the tornado total (known loss, modeled path)", all(abs(al[kn] - tot[kn]) <= 1e-8 * pmax(1, tot[kn])))
check("loss units are 'millions' or 'dollars'", all(tr$loss_raw_unit %in% c("millions", "dollars")))
yr <- as.integer(substr(tr$tornado_id, 1, 4))
check("loss is in millions through 2006 and in dollars from 2007", all(tr$loss_raw_unit[yr <= 2006] == "millions") && all(tr$loss_raw_unit[yr >= 2007] == "dollars"))
raw <- tr$loss_raw; unit <- tr$loss_raw_unit; ex <- raw * ifelse(unit == "millions", 1e6, 1)
check("loss in dollars = raw value (times 1e6 if in millions), NA where SPC recorded 0, with no rounding beyond floating-point error",
      identical(is.na(tr$property_loss_tornado_total), raw == 0) && all(abs(tr$property_loss_tornado_total - ex)[raw > 0] <= 1e-9 * ex[raw > 0]))
nz <- tr[tr$loss_raw > 0, ]; med <- tapply(nz$loss_raw, as.integer(substr(nz$tornado_id, 1, 4)), median)
check("yearly median nonzero loss is below 1 (millions) through 2006 and at least 10,000 (dollars) from 2007",
      all(med[as.integer(names(med)) <= 2006] < 1) && all(med[as.integer(names(med)) >= 2007] >= 10000))

# population
check("modeled_pop_affected and zcta_pop are not negative", all(d$modeled_pop_affected >= 0, na.rm = TRUE) && all(d$zcta_pop >= 0))
check("modeled_pop_affected does not exceed zcta_pop", all(d$modeled_pop_affected <= d$zcta_pop + 1e-6, na.rm = TRUE))
ok <- !noshape & d$zcta_pop > 0
check("modeled_pop_prop = modeled_pop_affected / zcta_pop, NA where zcta_pop is 0 or there is no modeled path", isTRUE(all.equal(d$modeled_pop_prop[ok], d$modeled_pop_affected[ok] / d$zcta_pop[ok])) && all(is.na(d$modeled_pop_prop[!ok])))
check("modeled_pop_prop is in [0, 1] (not capped)", all(d$modeled_pop_prop >= 0 & d$modeled_pop_prop <= 1 + 1e-9, na.rm = TRUE))
vint <- ifelse(d$year < 2010, 2000, ifelse(d$year < 2020, 2010, 2020))
check("zcta_pop is one value per ZCTA and boundary year", all(tapply(d$zcta_pop, paste(vint, d$ZCTA), function(x) length(unique(x))) == 1L))

# ---- zcta_centroids -------------------------------------------------------------------------
cen <- zcta_centroids
check("zcta_centroids has the expected columns", identical(names(cen), c("ZCTA", "vintage", "lon", "lat", "centroid_type", "centroid_in_zcta", "zcta_pop", "zcta_land_area_m2", "zcta_polygon_area_m2")))
check("zcta_centroids has no missing values", !anyNA(cen))
check("zcta_centroids is unique by ZCTA and boundary year", !anyDuplicated(cen[c("ZCTA", "vintage")]))
check("zcta_centroids covers boundary years 2000, 2010 and 2020", setequal(cen$vintage, c(2000L, 2010L, 2020L)))
check("centroid_type is 'population' or 'geometric'", all(cen$centroid_type %in% c("population", "geometric")))
check("geometric centroids are exactly the ZCTAs with no residents", all((cen$zcta_pop == 0) == (cen$centroid_type == "geometric")))
check("centroid coordinates are not rounded (not all at 5 decimals)", mean(abs(cen$lon * 1e5 - round(cen$lon * 1e5)) < 1e-6) < 0.01)
m <- merge(unique(data.frame(ZCTA = d$ZCTA, vintage = as.integer(vint), zp = d$zcta_pop, la = d$zcta_land_area_m2, pa = d$zcta_polygon_area_m2)), cen, by = c("ZCTA", "vintage"))
check("zcta_pop and the ZCTA areas agree between exposure and centroids", nrow(m) == nrow(unique(data.frame(d$ZCTA, vint))) && all(m$zp == m$zcta_pop) && all(m$la == m$zcta_land_area_m2) && all(m$pa == m$zcta_polygon_area_m2))

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
check("St. Louis: the SPC record's ZCTAs include Missouri (63...) and Illinois (62...) ZCTAs, and its rating is 2", any(substr(sz$ZCTA, 1, 2) == "63") && any(substr(sz$ZCTA, 1, 2) == "62") && all(sz$magnitude == 2))
if (length(fails)) stop(length(fails), " check(s) failed:\n  ", paste(fails, collapse = "\n  "), call. = FALSE)
cat("\nAll", n_checks, "checks passed.\n")
