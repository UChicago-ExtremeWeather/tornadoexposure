# Run from the package root after a rebuild:  Rscript data-raw/qa/67_compare_with_published.R      Saves data-raw/qa/out/compare_with_published.rds
# Compares the rebuilt tables in data/ with the tables of the published version (the commit PUBLISHED below, read from git): every column that is unchanged by design must be identical()
# and every difference (rows lost, rows gained, values changed) is counted by its cause.
PUBLISHED <- Sys.getenv("PUBLISHED_COMMIT", "130bbfc")
suppressMessages({library(sf); library(dplyr)}); source("data-raw/qa/helpers.R")
old <- new.env(); new <- new.env()
for (f in c("tornado_exposure", "tornado_tracks", "zcta_centroids")) { tf <- tempfile(fileext = ".rda"); system2("git", c("show", paste0(PUBLISHED, ":data/", f, ".rda")), stdout = tf); load(tf, envir = old) }
for (f in c("tornado_exposure", "tornado_tracks", "zcta_centroids", "spc_records")) load(sprintf("data/%s.rda", f), envir = new)
ot <- old$tornado_tracks; nt <- new$tornado_tracks; oe <- old$tornado_exposure; ne <- new$tornado_exposure; oc <- old$zcta_centroids; nc <- new$zcta_centroids
R <- list(commit = PUBLISHED)
# ---- tornado_tracks ------------------------------------------------------------------------------
R$tracks_same_ids <- identical(ot$tornado_id, nt$tornado_id)
o <- st_drop_geometry(ot); n <- st_drop_geometry(nt)
for (k in c("tornado_id", "date", "magnitude", "total_injury", "total_fatality", "property_loss_tornado_total", "loss_raw", "loss_raw_unit", "len_mi", "len_ratio")) R[[paste0("identical_", k)]] <- identical(o[[k]], n[[k]])
chg_w <- which(!(o$wid_yd == n$wid_yd) | xor(is.na(o$wid_yd), is.na(n$wid_yd)))
R$wid_changed <- length(chg_w); R$wid_changed_equals_old_flag <- identical(chg_w, which(o$width_imputed)); R$wid_old_values <- table(o$wid_yd[chg_w]); R$wid_new_values <- table(n$wid_yd[chg_w], useNA = "ifany")
R$wid_unchanged_identical <- identical(o$wid_yd[-chg_w], n$wid_yd[-chg_w]); R$wid_changed_by_type <- table(n$track_type[chg_w])
R$track_type_map <- table(old = o$track_type, new = n$track_type)
ln <- o$track_type == "line"
R$geometry_identical_lines <- identical(st_geometry(ot)[ln], st_geometry(nt)[ln]); R$geometry_identical_points <- identical(st_geometry(ot)[!ln], st_geometry(nt)[!ln])
R$geometry_identical_all <- identical(st_geometry(ot), st_geometry(nt))
a <- o$tornado_area_m2; b <- n$modeled_path_area_m2; same_line <- ln & !o$width_imputed
R$path_area_identical_lines_with_width <- identical(a[same_line], b[same_line]); R$path_area_changed <- c(width_imputed_lines = sum(ln & o$width_imputed), points = sum(!ln), now_NA = sum(is.na(b)))
spc_w <- new$spc_records[new$spc_records$sg == 1, ]; w <- spc_w[match(nt$tornado_id, spc_w$tornado_id), ]
R$raw_columns_identical_to_spc <- c(slat = identical(n$slat, w$slat), slon = identical(n$slon, w$slon), elat = identical(n$elat, w$elat), elon = identical(n$elon, w$elon), len = identical(n$len_mi, w$len), wid = identical(n$wid_yd, w$wid))
# ---- tornado_exposure ----------------------------------------------------------------------------
ko <- paste(oe$tornado_id, oe$ZCTA); kn <- paste(ne$tornado_id, ne$ZCTA)
lost <- !ko %in% kn; gained <- !kn %in% ko
tl <- function(ids) { x <- n$track_type[match(ids, n$tornado_id)]; wi <- o$width_imputed[match(ids, o$tornado_id)]; ifelse(x == "point", "point", ifelse(wi, "line, width replaced", "line")) }
R$exposure_rows <- c(old = nrow(oe), new = nrow(ne), common = sum(!lost), lost = sum(lost), gained = sum(gained))
R$rows_lost_by_cause <- table(tl(oe$tornado_id[lost])); R$rows_gained_by_cause <- table(tl(ne$tornado_id[gained]))
tid_lost <- setdiff(oe$tornado_id, ne$tornado_id); R$tornadoes_without_rows_now <- c(lost_tornadoes = length(tid_lost), by_type = table(n$track_type[match(tid_lost, n$tornado_id)]))
R$lines_with_width_same_zcta_lists <- { ids <- o$tornado_id[ln & !o$width_imputed]; identical(sort(ko[oe$tornado_id %in% ids]), sort(kn[ne$tornado_id %in% ids])) }
R$width_replaced_lines_same_zcta_lists <- { ids <- o$tornado_id[ln & o$width_imputed]; identical(sort(ko[oe$tornado_id %in% ids]), sort(kn[ne$tornado_id %in% ids])) }
R$width_replaced_lines_n <- sum(ln & o$width_imputed)
m <- inner_join(oe, ne, by = c("tornado_id", "ZCTA"), suffix = c(".old", ".new"))
for (k in c("date", "year", "month", "day", "magnitude", "total_injury", "total_fatality", "property_loss_tornado_total", "zcta_pop")) R[[paste0("exposure_identical_", k)]] <- identical(m[[paste0(k, ".old")]], m[[paste0(k, ".new")]])
R$exposure_track_type <- table(old = m$track_type.old, new = m$track_type.new)
lw <- m$track_type.old == "line" & !(m$tornado_id %in% o$tornado_id[o$width_imputed])      # line tornadoes whose width was not replaced
R$lines_with_width_rows <- sum(lw)
R$area_share_identical <- identical(m$area_share_of_tornado[lw], m$modeled_area_share_of_tornado[lw]); R$area_share_max_abs_diff <- max(abs(m$area_share_of_tornado[lw] - m$modeled_area_share_of_tornado[lw]))
R$loss_allocated_identical <- identical(m$property_loss_allocated[lw], m$modeled_property_loss_allocated[lw]); R$loss_allocated_max_abs_diff <- max(abs(m$property_loss_allocated[lw] - m$modeled_property_loss_allocated[lw]), na.rm = TRUE)
# area: the old column is min(intersection / ALAND, 1); the new column is intersection / polygon area. The intersection areas are recovered through ALAND (old) and the polygon area (new)
aland <- ne$zcta_land_area_m2[match(paste(m$tornado_id, m$ZCTA), kn)]; inter_old <- m$area_prop_affected * aland; inter_new <- m$modeled_intersection_m2
R$intersection_identical_to_1e9 <- c(rows = sum(lw), relative_diff_over_1e9 = sum(abs(inter_new[lw] - inter_old[lw]) / inter_new[lw] > 1e-9 & m$area_prop_affected[lw] < 1), capped_rows_old = sum(m$area_prop_affected[lw] == 1))
R$capped_rows_old_all <- sum(m$area_prop_affected == 1)
R$area_basis <- data.frame(compare = c("modeled_area_prop vs area_prop_affected"), differ_over_1pct = sum(abs(m$modeled_area_prop[lw] / m$area_prop_affected[lw] - 1) > .01), differ_over_10pct = sum(abs(m$modeled_area_prop[lw] / m$area_prop_affected[lw] - 1) > .1), differ_over_50pct = sum(abs(m$modeled_area_prop[lw] / m$area_prop_affected[lw] - 1) > .5), rows = sum(lw))
rp <- m$pop_affected[lw]; np <- m$modeled_pop_affected[lw]
R$pop_affected <- c(identical = identical(rp, np), rows = length(rp), rows_not_identical = sum(rp != np), max_relative_diff = max(abs(rp - np) / pmax(rp, 1)))
R$pop_prop <- c(rows_not_identical = sum(m$pop_prop_affected[lw] != m$modeled_pop_prop[lw] | xor(is.na(m$pop_prop_affected[lw]), is.na(m$modeled_pop_prop[lw]))), max_abs_diff = max(abs(m$pop_prop_affected[lw] - m$modeled_pop_prop[lw]), na.rm = TRUE))
R$ZCTA_pop_centroids <- identical(oc$zcta_pop, nc$zcta_pop)
# ---- zcta_centroids ------------------------------------------------------------------------------
R$centroids_same_keys <- identical(oc[c("ZCTA", "vintage")], nc[c("ZCTA", "vintage")])
for (k in c("centroid_type", "centroid_in_zcta", "zcta_pop")) R[[paste0("centroids_identical_", k)]] <- identical(oc[[k]], nc[[k]])
R$centroids_rounded_equals_old <- c(lon = identical(round(nc$lon, 5), oc$lon), lat = identical(round(nc$lat, 5), oc$lat))
R$centroids_unrounded_rows_changed <- c(rows = nrow(nc), lon_differs = sum(nc$lon != oc$lon), lat_differs = sum(nc$lat != oc$lat), either = sum(nc$lon != oc$lon | nc$lat != oc$lat), max_shift_m = max(sqrt(((nc$lon - oc$lon) * 111320 * cos(nc$lat * pi / 180))^2 + ((nc$lat - oc$lat) * 110574)^2)))
saveRDS(R, qa_out("compare_with_published.rds")); print(R)
