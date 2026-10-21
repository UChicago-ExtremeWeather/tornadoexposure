# Builds the NWS survey layer used by get_survey_data():
#   survey_exposure  tornado-ZCTA rows from the surveyed damage swaths
#   survey_tracks    the swaths simplified to 50 m, for plotting and distances
#   survey_matches   one row per SPC tornado since 2007 with its status and the details of its pairing
#
# Run from the package root, after data-raw/add_population.R and data-raw/add_centroids.R, under caffeinate if the computer may sleep:
#   caffeinate -i Rscript data-raw/survey/build_survey.R      (progress: data-raw/qa/out/build_survey.log)
#
# Source: NOAA National Weather Service Damage Assessment Toolkit (DAT), layers "Damage Lines SDE" (1) and "Damage Polygons SDE" (2) of
# https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer
# The script queries the live service (survey lines dated 2007 to the last SPC year, 2025; damage polygons generalized to 0.0002 degrees,
# about 20 m) and writes the date of the query to data-raw/survey/access_date.txt. SURVEY_USE_SAVED=1 reuses the last fetch.
#
# Pairing (functions in data-raw/survey/pairing_functions.R): candidates are the SPC tornadoes since 2007 (line and point tracks) and
# the survey lines (any length) dated within 1 day; survey lines that are exact copies of each other are merged first. The distance between
# a tornado and a survey line is the mean of the 21 distances between corresponding equally spaced points along the two paths, with the
# survey line read in the direction that gives the smaller mean (for a point track, the distance from the point to the survey line). A
# tornado is paired with a survey line when each is the other's closest candidate. Nothing else is used: no distance limit, no test on
# length or direction, no minimum length. Swath: the rated (EF0-EF5) damage polygons that cross the surveyed centerline on the same date
# (within one day) and lie at least 90% within a distance from it equal to the SPC path width plus 500 m, merged; the swath is usable when it
# lies within 200 m of at least 50% of the centerline's length.
# status: "included" (paired, usable swath), "no_swath" (paired, no usable swath), "no_pair" (no mutual closest survey line).
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE)
options(width = 170, tigris_use_cache = TRUE, timeout = 600)
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R"); source("data-raw/survey/pairing_functions.R")
log <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S"), " ", paste0(...)); cat(m, "\n"); cat(m, "\n", file = qa_out("build_survey.log"), append = TRUE) }
load("data/tornado_tracks.rda"); load("data/zcta_centroids.rda"); load("data/tornado_exposure.rda")
last_year <- max(tornado_exposure$year); vint_of <- function(y) ifelse(y < 2010, 2000L, ifelse(y < 2020, 2010L, 2020L))

# ---- 0. the population cache must be complete: a missing file would mean a download ------------------------------------------------------------
states <- pop_states()
need <- unlist(lapply(c(2000, 2010, 2020), function(v) vapply(states$state_code, function(fp) pop_cache("work", sprintf("%s_%s.rds", v, fp)), "")))
if (!all(file.exists(need))) stop("The population cache is incomplete (", sum(!file.exists(need)), " per-state files missing); a download of Census block files would be needed. Run data-raw/add_population.R first.", call. = FALSE)

# ---- 1. fetch ---------------------------------------------------------------------------------------------------------------------------------
F <- dat_fetch_all(last_year); writeLines(format(F$date), "data-raw/survey/access_date.txt")
Du <- merge_copies(F$lines); P <- F$polys
log("survey lines: ", nrow(F$lines), "; after merging exact copies: ", nrow(Du), "; damage polygons: ", nrow(P), "; fetched ", format(F$date))
yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4)); Tt <- tornado_tracks[yr >= 2007, ]
Tt$date <- as.Date(Tt$date)

# ---- 2. pairing ------------------------------------------------------------------------------------------------------------------------------------
sp <- spc_paths(Tt); sv <- survey_paths(Du)
pr <- candidate_distances(Du, Tt, sp, sv, window = 1); M <- mutual_closest(pr)
log("candidate pairs: ", nrow(pr), "; pairs (mutual closest): ", nrow(M))
stt <- tigris::states(cb = TRUE, year = 2020, progress_bar = FALSE); stt <- st_transform(stt[, "STUSPS"], 4326)
st_of <- function(lon, lat) stt$STUSPS[sapply(st_intersects(st_as_sf(data.frame(lon, lat), coords = c("lon", "lat"), crs = 4326), stt), function(x) if (length(x)) x[1] else NA_integer_)]
spc_state <- st_of(sp$tl[, 1], sp$tl[, 2]); line_state_s <- st_of(Du$s_lon, Du$s_lat); line_state_e <- st_of(Du$e_lon, Du$e_lat)
ns <- n_samples; i <- M$i; k <- M$k
sd0 <- cbind(sv$Sx[cbind(i, ifelse(M$rev, ns, 1))], sv$Sy[cbind(i, ifelse(M$rev, ns, 1))]); sd1 <- cbind(sv$Sx[cbind(i, ifelse(M$rev, 1, ns))], sv$Sy[cbind(i, ifelse(M$rev, 1, ns))])
sb <- bearing(sd0[, 1], sd0[, 2], sd1[, 1], sd1[, 2]); tb <- bearing(sp$s5[k, 1], sp$s5[k, 2], sp$e5[k, 1], sp$e5[k, 2]); dd <- abs(sb - tb)
M$direction_diff_deg <- ifelse(sp$is_line[k], pmin(dd, 360 - dd), NA_real_)
M$length_ratio <- ifelse(Tt$len_mi[k] > 0, Du$length[i] / Tt$len_mi[k], NA_real_)
M$same_state <- !is.na(spc_state[k]) & (spc_state[k] == line_state_s[i] | spc_state[k] == line_state_e[i]); M$same_state[is.na(spc_state[k])] <- NA

# ---- 3. swaths -------------------------------------------------------------------------------------------------------------------------------------
sw <- swath_setup(Du, sv, P); n <- nrow(M); n_raw <- n_used <- integer(n); cover <- area <- rep(NA_real_, n); geoms <- vector("list", n)
for (r in seq_len(n)) { s <- swath_of(sw, M$i[r], M$k[r], Tt$wid_yd); n_raw[r] <- s$n_raw; n_used[r] <- s$n_used; cover[r] <- s$cover; area[r] <- s$area_km2; geoms[r] <- list(s$geom)
  if (r %% 1000 == 0) log("swath filter: ", r, " of ", n) }
usable <- !is.na(cover) & cover >= 0.5
log("pairs with a rated polygon along the centerline: ", sum(n_used > 0), "; usable swaths: ", sum(usable))

# ---- 4. match table: one row per SPC tornado since 2007 ---------------------------------------------------------------------------------------
ncand <- tabulate(pr$k, nbins = nrow(Tt))
sm <- data.frame(tornado_id = Tt$tornado_id, status = "no_pair", stringsAsFactors = FALSE)
sm$distance_km <- NA_real_; sm$length_ratio <- NA_real_; sm$direction_diff_deg <- NA_real_; sm$n_candidates_tornado <- ncand; sm$n_candidates_line <- NA_integer_
sm$second_distance_tornado_km <- NA_real_; sm$second_distance_line_km <- NA_real_; sm$same_state <- NA
sm$survey_line_id <- NA_integer_; sm$survey_line_ids <- NA_character_; sm$n_duplicate_lines <- NA_integer_; sm$survey_event_id <- NA_character_; sm$survey_wfo <- NA_character_
sm$n_polygons_raw <- NA_integer_; sm$n_polygons_used <- NA_integer_; sm$swath_cover <- NA_real_; sm$swath_km2 <- NA_real_
sm$status[k] <- ifelse(usable, "included", "no_swath")
sm$distance_km[k] <- M$dist_km; sm$length_ratio[k] <- M$length_ratio; sm$direction_diff_deg[k] <- M$direction_diff_deg; sm$n_candidates_line[k] <- M$n_cand_s
sm$second_distance_tornado_km[k] <- M$second_t; sm$second_distance_line_km[k] <- M$second_s; sm$same_state[k] <- M$same_state
sm$survey_line_id[k] <- as.integer(Du$objectid[i]); sm$survey_line_ids[k] <- Du$all_ids[i]; sm$n_duplicate_lines[k] <- Du$n_copies[i] - 1L
sm$survey_event_id[k] <- iconv(Du$event_id[i], "UTF-8", "ASCII", sub = ""); sm$survey_wfo[k] <- Du$wfo[i]   # one event id has an invisible soft hyphen (U+00AD): dropped, so the data are plain ASCII
sm$n_polygons_raw[k] <- n_raw; sm$n_polygons_used[k] <- n_used; sm$swath_cover[k] <- cover; sm$swath_km2[k] <- area
survey_matches <- sm[order(sm$tornado_id), ]; rownames(survey_matches) <- NULL
stopifnot(!anyDuplicated(survey_matches$tornado_id), !anyNA(survey_matches$status))
log("status:"); print(table(survey_matches$status)); cat(paste(capture.output(print(table(survey_matches$status))), collapse = "\n"), "\n", file = qa_out("build_survey.log"), append = TRUE)

# ---- 5. swaths -----------------------------------------------------------------------------------------------------------------------------------------
new_ids <- Tt$tornado_id[k][usable]
S <- st_sf(tornado_id = new_ids, geometry = st_sfc(lapply(which(usable), function(r) geoms[[r]][[1]]), crs = 5070))
S$year <- as.integer(substr(S$tornado_id, 1, 4)); S$vint <- vint_of(S$year)

# ---- 6. exposure of the swaths --------------------------------------------------------------------------------------------------------------------
load_z <- function(v) { z <- tigris::zctas(year = v, progress_bar = FALSE); sfx <- substr(v, 3, 4); z <- z[, c(paste0("ZCTA5CE", sfx), paste0("ALAND", sfx))]; names(z) <- c("ZCTA", "ALAND", "geometry"); z$ALAND <- as.numeric(z$ALAND); st_make_valid(st_transform(z, 5070)) }
Z <- lapply(c(2000, 2010, 2020), load_z); names(Z) <- c(2000, 2010, 2020)
pieces <- bind_rows(lapply(c(2000, 2010, 2020), function(v) {
  sub <- S[S$vint == v, ]; if (!nrow(sub)) return(NULL)
  x <- suppressWarnings(st_intersection(sub["tornado_id"], Z[[as.character(v)]])); x <- st_collection_extract(x, "POLYGON")
  x$a <- as.numeric(st_area(x))
  st_drop_geometry(x) %>% group_by(tornado_id, ZCTA, ALAND) %>% summarise(a = sum(a), .groups = "drop") %>% mutate(vintage = v) }))
pieces <- pieces[pieces$a > 0, ]
log("swath-ZCTA pairs: ", nrow(pieces), " for ", length(unique(pieces$tornado_id)), " tornadoes; area_prop above 1 (capped): ", sum(pieces$a / pieces$ALAND > 1))
tg <- st_sf(tid = S$tornado_id, kind = "survey", geometry = st_geometry(S))
pa <- bind_rows(lapply(sort(unique(S$vint)), function(v) { log("population, vintage ", v, ": ", sum(S$vint == v), " swaths"); pop_aff_cached(v, tg[S$vint == v, ], states, zcta_layer(v)) %>% mutate(vintage = as.numeric(v)) })) %>%
  filter(!is.na(ZCTA)) %>% transmute(tornado_id = tid, ZCTA, vintage, pop_affected = pop_aff)
tt <- st_drop_geometry(tornado_tracks)
se <- pieces %>% group_by(tornado_id) %>% mutate(area_share_of_tornado = a / sum(a)) %>% ungroup() %>%
  mutate(area_prop_affected = pmin(a / ALAND, 1)) %>%
  left_join(pa, by = c("tornado_id", "ZCTA", "vintage")) %>%
  left_join(zcta_centroids[, c("ZCTA", "vintage", "zcta_pop")], by = c("ZCTA", "vintage")) %>%
  left_join(tt[, c("tornado_id", "date", "magnitude", "total_injury", "total_fatality", "property_loss_tornado_total", "track_type")], by = "tornado_id") %>%
  left_join(survey_matches[, c("tornado_id", "survey_line_id", "survey_event_id")], by = "tornado_id")
se$pop_affected[is.na(se$pop_affected)] <- 0
se$zcta_pop[is.na(se$zcta_pop)] <- 0L
se$pop_prop_affected <- ifelse(se$zcta_pop > 0, se$pop_affected / se$zcta_pop, NA_real_)
se$property_loss_allocated <- se$property_loss_tornado_total * se$area_share_of_tornado
se$year <- as.integer(format(se$date, "%Y")); se$month <- as.integer(format(se$date, "%m")); se$day <- as.integer(format(se$date, "%d"))
se$path_source <- "nws_survey"
survey_exposure <- as.data.frame(se[, c(names(tornado_exposure), "path_source", "survey_line_id", "survey_event_id")])
survey_exposure <- survey_exposure[order(survey_exposure$tornado_id, survey_exposure$ZCTA), ]; rownames(survey_exposure) <- NULL
chk <- survey_exposure %>% group_by(tornado_id) %>% summarise(share = sum(area_share_of_tornado), alloc = sum(property_loss_allocated), tot = first(property_loss_tornado_total), .groups = "drop")
kn <- !is.na(chk$tot)   # known loss: allocated loss sums to the total; unknown (NA): allocated is NA
stopifnot(all(abs(chk$share - 1) < 1e-9), all(abs(chk$alloc[kn] - chk$tot[kn]) <= 1e-8 * pmax(1, chk$tot[kn])), all(is.na(chk$alloc[!kn])),
          all(survey_exposure$area_prop_affected > 0 & survey_exposure$area_prop_affected <= 1),
          all(survey_exposure$pop_affected <= survey_exposure$zcta_pop + 1e-6),
          all(survey_exposure$pop_prop_affected[!is.na(survey_exposure$pop_prop_affected)] <= 1 + 1e-9),
          !anyDuplicated(survey_exposure[c("tornado_id", "ZCTA")]), !anyNA(survey_exposure$date))
log("survey_exposure: ", nrow(survey_exposure), " rows, ", length(unique(survey_exposure$tornado_id)), " tornadoes (swaths with no ZCTA overlap: ", length(new_ids) - length(unique(survey_exposure$tornado_id)), ")")

# ---- 7. plotting and distance polygons, simplified to 50 m ----------------------------------------------------------------------------------------
Sx <- st_make_valid(st_simplify(S, dTolerance = 50, preserveTopology = TRUE))
# make_valid can leave stray lines or points next to the polygons of a tiny swath: keep the polygon part only
g <- st_geometry(Sx); gc <- which(st_geometry_type(g) == "GEOMETRYCOLLECTION")
log("simplified swaths that became geometry collections (polygon part kept): ", length(gc))
g <- st_sfc(lapply(seq_along(g), function(r) { if (r %in% gc) st_union(st_collection_extract(st_sfc(g[[r]], crs = st_crs(g)), "POLYGON"))[[1]] else g[[r]] }), crs = st_crs(g))
st_geometry(Sx) <- g
stopifnot(!any(st_is_empty(Sx)), all(st_geometry_type(Sx) %in% c("POLYGON", "MULTIPOLYGON")))
survey_tracks <- st_sf(tornado_id = Sx$tornado_id, geometry = st_transform(st_geometry(Sx), 4326))
log("survey_tracks: ", nrow(survey_tracks), " polygons; area change from simplification (median, max, %): ", paste(signif(100 * quantile(abs(as.numeric(st_area(Sx)) / as.numeric(st_area(S)) - 1), c(.5, 1)), 3), collapse = ", "))
stopifnot(all(st_is_valid(survey_tracks)), setequal(survey_tracks$tornado_id, new_ids))
usethis::use_data(survey_exposure, survey_tracks, survey_matches, overwrite = TRUE, compress = "xz")
log("sizes (KB): ", paste(sapply(c("survey_exposure", "survey_tracks", "survey_matches"), function(nm) round(file.size(file.path("data", paste0(nm, ".rda"))) / 1024)), collapse = ", "))
