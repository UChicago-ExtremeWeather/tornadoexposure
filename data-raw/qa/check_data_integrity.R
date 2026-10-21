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
d <- tornado_exposure; tr <- tornado_tracks

# ---- tornado_exposure -------------------------------------------------------------------
check("tornado_id and ZCTA pairs are unique", !anyDuplicated(d[c("tornado_id", "ZCTA")]))
key <- c("tornado_id", "date", "year", "month", "day", "ZCTA", "area_prop_affected", "area_share_of_tornado",
         "track_type", "total_injury", "total_fatality", "pop_affected", "zcta_pop")
for (k in key) check(paste("no missing values in", k), !anyNA(d[[k]]))
check("ZCTA is a character vector of 5 digits", is.character(d$ZCTA) && all(grepl("^[0-9]{5}$", d$ZCTA)))
check("area_prop_affected is in (0, 1]", all(d$area_prop_affected > 0 & d$area_prop_affected <= 1))
check("area_share_of_tornado is in (0, 1]", all(d$area_share_of_tornado > 0 & d$area_share_of_tornado <= 1))
check("area_share_of_tornado sums to 1 for every tornado", all(abs(tapply(d$area_share_of_tornado, d$tornado_id, sum) - 1) < 1e-9))
check("magnitude is 0 to 5 or NA", all(d$magnitude %in% c(0:5, NA)))
valid <- c("line", "point_equal_area", "point_half_width")
check("track_type has valid values (exposure)", all(d$track_type %in% valid))
check("track_type has valid values (tracks)", all(tr$track_type %in% valid))
check("track_type agrees between exposure and tracks", identical(d$track_type, tr$track_type[match(d$tornado_id, tr$tornado_id)]))
check("every tornado_id in exposure exists in tracks", all(d$tornado_id %in% tr$tornado_id))
check("tornado_id is unique in tracks", !anyDuplicated(tr$tornado_id))

# loss: NA exactly where SPC recorded 0; allocated loss sums back to the tornado total
check("allocated loss is NA exactly where the tornado total is NA", identical(is.na(d$property_loss_allocated), is.na(d$property_loss_tornado_total)))
check("tornado loss is constant within a tornado", all(tapply(d$property_loss_tornado_total, d$tornado_id, function(x) length(unique(x))) == 1L))
tot <- tapply(d$property_loss_tornado_total, d$tornado_id, function(x) x[1]); al <- tapply(d$property_loss_allocated, d$tornado_id, sum)
kn <- !is.na(tot)
check("some tornadoes have known loss", sum(kn) > 0)
check("allocated loss sums to the tornado total (known loss)", all(abs(al[kn] - tot[kn]) <= 1e-8 * pmax(1, tot[kn])))
check("allocated loss is NA for every row of a tornado with unknown loss", all(is.na(al[!kn])))
check("loss units are 'millions' or 'dollars'", all(tr$loss_raw_unit %in% c("millions", "dollars")))
yr <- as.integer(substr(tr$tornado_id, 1, 4))
check("loss is in millions through 2006 and in dollars from 2007", all(tr$loss_raw_unit[yr <= 2006] == "millions") && all(tr$loss_raw_unit[yr >= 2007] == "dollars"))
raw <- tr$loss_raw[match(names(tot), tr$tornado_id)]; unit <- tr$loss_raw_unit[match(names(tot), tr$tornado_id)]
check("loss in dollars = raw value (times 1e6 if in millions), NA where SPC recorded 0",
      isTRUE(all.equal(as.numeric(tot), as.numeric(ifelse(raw == 0, NA_real_, ifelse(unit == "millions", round(raw * 1e6), raw))))))
check("tornado_tracks loss is NA exactly where SPC recorded 0", identical(is.na(tr$property_loss_tornado_total), tr$loss_raw == 0))
nz <- tr[tr$loss_raw > 0, ]; med <- tapply(nz$loss_raw, as.integer(substr(nz$tornado_id, 1, 4)), median)
check("yearly median nonzero loss is below 1 (millions) through 2006 and at least 10,000 (dollars) from 2007",
      all(med[as.integer(names(med)) <= 2006] < 1) && all(med[as.integer(names(med)) >= 2007] >= 10000))

# population
check("pop_affected and zcta_pop are not negative", all(d$pop_affected >= 0 & d$zcta_pop >= 0))
check("pop_affected does not exceed zcta_pop", all(d$pop_affected <= d$zcta_pop + 1e-6))
ok <- d$zcta_pop > 0
check("pop_prop_affected = pop_affected / zcta_pop, NA where zcta_pop is 0", isTRUE(all.equal(d$pop_prop_affected[ok], d$pop_affected[ok] / d$zcta_pop[ok])) && all(is.na(d$pop_prop_affected[!ok])))
check("pop_prop_affected is in [0, 1]", all(d$pop_prop_affected >= 0 & d$pop_prop_affected <= 1 + 1e-9, na.rm = TRUE))
vint <- ifelse(d$year < 2010, 2000, ifelse(d$year < 2020, 2010, 2020))
check("zcta_pop is one value per ZCTA and vintage", all(tapply(d$zcta_pop, paste(vint, d$ZCTA), function(x) length(unique(x))) == 1L))

# ---- tornado_tracks -----------------------------------------------------------------------
t0 <- st_drop_geometry(tr)
check("tornado_tracks is an sf object in EPSG:4326", inherits(tr, "sf") && identical(st_crs(tr)$epsg, 4326L))
check("track widths and areas are positive", all(t0$wid_yd > 0) && all(t0$tornado_area_m2 > 0))
check("len_ratio is NA for point tracks", all(is.na(t0$len_ratio[t0$track_type != "line"])))

# ---- zcta_centroids -------------------------------------------------------------------------
cen <- zcta_centroids
check("zcta_centroids has the expected columns", identical(names(cen), c("ZCTA", "vintage", "lon", "lat", "centroid_type", "centroid_in_zcta", "zcta_pop")))
check("zcta_centroids has no missing values", !anyNA(cen))
check("zcta_centroids is unique by ZCTA and vintage", !anyDuplicated(cen[c("ZCTA", "vintage")]))
check("zcta_centroids covers vintages 2000, 2010 and 2020", setequal(cen$vintage, c(2000L, 2010L, 2020L)))
check("centroid_type is 'population' or 'geometric'", all(cen$centroid_type %in% c("population", "geometric")))
check("geometric centroids are exactly the ZCTAs with no residents", all((cen$zcta_pop == 0) == (cen$centroid_type == "geometric")))
ex <- unique(data.frame(ZCTA = d$ZCTA, vintage = as.integer(vint), zp = d$zcta_pop)); m <- merge(ex, cen, by = c("ZCTA", "vintage"))
check("zcta_pop agrees between exposure and centroids", nrow(m) == nrow(ex) && all(m$zp == m$zcta_pop))

# ---- survey layer -----------------------------------------------------------------------------
se <- survey_exposure; sm <- survey_matches; st <- survey_tracks
check("survey_exposure has the columns of tornado_exposure plus path_source, survey_line_id, survey_event_id", identical(names(se), c(names(tornado_exposure), "path_source", "survey_line_id", "survey_event_id")))
check("survey_exposure pairs are unique", !anyDuplicated(se[c("tornado_id", "ZCTA")]))
check("survey_exposure area_prop_affected is in (0, 1]", all(se$area_prop_affected > 0 & se$area_prop_affected <= 1))
check("survey_exposure pop_affected does not exceed zcta_pop", all(se$pop_affected >= 0 & se$pop_affected <= se$zcta_pop + 1e-6))
check("survey_exposure shares sum to 1 per tornado", all(abs(tapply(se$area_share_of_tornado, se$tornado_id, sum) - 1) < 1e-9))
check("survey_exposure tornado_ids are in tornado_tracks", all(se$tornado_id %in% tr$tornado_id))
check("survey_matches status has the three valid values", setequal(unique(sm$status), c("included", "no_swath", "no_pair")))
check("survey_matches has one row per SPC tornado since 2007", !anyDuplicated(sm$tornado_id) && setequal(sm$tornado_id, tr$tornado_id[as.integer(substr(tr$tornado_id, 1, 4)) >= 2007]))
pairedr <- sm$status != "no_pair"
check("pair columns are NA exactly when status is no_pair", all(is.na(sm$distance_km) == !pairedr) && all(is.na(sm$survey_line_id) == !pairedr) && all(is.na(sm$n_candidates_line) == !pairedr))
check("distance_km is not negative and every second-closest distance is at least the closest", all(sm$distance_km[pairedr] >= 0) && all(sm$second_distance_tornado_km[pairedr] >= sm$distance_km[pairedr] - 1e-9, na.rm = TRUE) && all(sm$second_distance_line_km[pairedr] >= sm$distance_km[pairedr] - 1e-9, na.rm = TRUE))
check("direction_diff_deg is in [0, 180] and length_ratio is not negative", all(sm$direction_diff_deg >= 0 & sm$direction_diff_deg <= 180, na.rm = TRUE) && all(sm$length_ratio >= 0, na.rm = TRUE))
check("each survey line is paired with at most one tornado", !anyDuplicated(sm$survey_line_id[pairedr]))
check("a tornado with no candidate survey line has status no_pair", all(sm$status[sm$n_candidates_tornado == 0] == "no_pair"))
check("included means a swath covering at least half of the centerline, no_swath less than half or none", all(sm$swath_cover[sm$status == "included"] >= 0.5) && all(is.na(sm$swath_cover[sm$status == "no_swath"]) | sm$swath_cover[sm$status == "no_swath"] < 0.5))
check("survey_tracks tornadoes are exactly the included tornadoes", setequal(st$tornado_id, sm$tornado_id[sm$status == "included"]) && !anyDuplicated(st$tornado_id))
check("survey_exposure tornadoes are included tornadoes", all(se$tornado_id %in% sm$tornado_id[sm$status == "included"]))
check("survey_tracks are polygons in EPSG:4326", all(st_is(st, c("POLYGON", "MULTIPOLYGON"))) && identical(st_crs(st)$epsg, 4326L))

if (length(fails)) stop(length(fails), " check(s) failed:\n  ", paste(fails, collapse = "\n  "), call. = FALSE)
cat("\nAll", n_checks, "checks passed.\n")
