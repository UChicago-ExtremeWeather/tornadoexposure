# Run from the package root after a rebuild:  Rscript data-raw/qa/67_compare_with_previous.R      Saves data-raw/qa/out/compare_with_previous.rds
# Compares the rebuilt tables in data/ with the tables of the previous build (the commit PREVIOUS_COMMIT, default the commit before the line-only design, read from git): every column that is unchanged
# by design must be identical(), and every difference (rows lost, rows gained, values changed) is counted by its cause.
PREVIOUS <- Sys.getenv("PREVIOUS_COMMIT", "ef6cfb5")
suppressMessages({library(sf); library(dplyr)}); source("data-raw/qa/helpers.R")
old <- new.env(); new <- new.env()
for (f in c("tornado_exposure", "tornado_tracks", "zcta_centroids", "spc_records", "tornado_dat_link", "dat_polygon_line_link", "dat_lines", "dat_polygons", "dat_points")) { tf <- tempfile(fileext = ".rda"); system2("git", c("show", paste0(PREVIOUS, ":data/", f, ".rda")), stdout = tf); load(tf, envir = old) }
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f, envir = new)
ot <- old$tornado_tracks; nt <- new$tornado_tracks; oe <- old$tornado_exposure; ne <- new$tornado_exposure; oc <- old$zcta_centroids; nc <- new$zcta_centroids
R <- list(commit = PREVIOUS)
# ---- tornado_tracks ------------------------------------------------------------------------------
o <- st_drop_geometry(ot); n <- st_drop_geometry(nt)
R$tracks <- list(same_ids = identical(ot$tornado_id, nt$tornado_id), columns_removed = setdiff(names(o), names(n)), columns_added = setdiff(names(n), names(o)),
  identical = vapply(intersect(names(o), names(n)), function(k) identical(o[[k]], n[[k]]), logical(1)), geometry_identical = identical(st_geometry(ot), st_geometry(nt)), crs_identical = identical(st_crs(ot), st_crs(nt)))
# ---- tornado_exposure ----------------------------------------------------------------------------
ko <- paste(oe$tornado_id, oe$ZCTA); sp <- ne[ne$spc_exposed, ]; ks <- paste(sp$tornado_id, sp$ZCTA); kd <- paste(ne$tornado_id, ne$ZCTA)[!ne$spc_exposed]
old_kind <- ifelse(!is.na(oe$modeled_intersection_m2), "polygon (line with a width)", ifelse(oe$track_type == "point", "start point", "centerline (width 0)"))
lost <- !ko %in% ks; gained <- !ks %in% ko
R$rows <- c(old_rows = nrow(oe), old_tornadoes = length(unique(oe$tornado_id)), new_rows = nrow(ne), new_tornadoes = length(unique(ne$tornado_id)), new_spc_rows = nrow(sp), new_dat_only_rows = sum(!ne$spc_exposed), new_tornadoes_with_spc_rows = length(unique(sp$tornado_id)))
R$spc_rows <- c(common = sum(!lost), lost = sum(lost), gained = sum(gained)); R$spc_rows_lost_by_old_kind <- table(old_kind[lost]); R$spc_rows_by_old_kind <- table(old_kind)
R$lost_have_positive_old_boundary_dist <- c(rows = sum(lost), positive = sum(oe$boundary_dist_km[lost] > 0)); R$old_positive_boundary_dist_rows <- sum(oe$boundary_dist_km > 0)
R$lost_tornadoes_entire <- length(setdiff(oe$tornado_id, sp$tornado_id)); R$gained_tornadoes <- length(setdiff(sp$tornado_id, oe$tornado_id))
R$dat_only_in_old_table <- c(dat_only_rows = length(kd), also_old_rows = sum(kd %in% ko), new_to_the_table = sum(!kd %in% ko))
R$dat_only_by_type <- table(ne$track_type[!ne$spc_exposed]); R$dat_only_tornadoes <- length(unique(ne$tornado_id[!ne$spc_exposed]))
m <- inner_join(oe, sp, by = c("tornado_id", "ZCTA"), suffix = c(".old", ".new"))
R$common_identical <- vapply(c("date", "year", "month", "day", "magnitude", "total_injury", "total_fatality", "property_loss_tornado_total", "track_type", "centroid_dist_km", "boundary_dist_km", "zcta_pop", "zcta_land_area_m2", "zcta_polygon_area_m2"),
                             function(k) identical(m[[paste0(k, ".old")]], m[[paste0(k, ".new")]]), logical(1))
R$centroid_dist_max_abs_diff <- max(abs(m$centroid_dist_km.old - m$centroid_dist_km.new)); R$boundary_dist_old_positive_in_common <- sum(m$boundary_dist_km.old > 0)
R$loss_allocated <- c(rows = nrow(m), identical = sum(m$modeled_property_loss_allocated == m$property_loss_allocated | (is.na(m$modeled_property_loss_allocated) & is.na(m$property_loss_allocated)), na.rm = TRUE), old_na_new_value = sum(is.na(m$modeled_property_loss_allocated) & !is.na(m$property_loss_allocated)), old_value_new_na = sum(!is.na(m$modeled_property_loss_allocated) & is.na(m$property_loss_allocated)))
R$loss_allocated_rel_diff_quantiles <- quantile(abs(m$property_loss_allocated / m$modeled_property_loss_allocated - 1), c(.5, .9, .99, 1), na.rm = TRUE)
# ---- zcta_centroids ------------------------------------------------------------------------------
R$centroids <- list(same_keys = identical(oc[c("ZCTA", "vintage")], nc[c("ZCTA", "vintage")]), identical = vapply(intersect(names(oc), names(nc)), function(k) identical(oc[[k]], nc[[k]]), logical(1)), columns_added = setdiff(names(nc), names(oc)))
# ---- DAT datasets and links (rebuilt from the same fetch: must be identical) -------------------------
R$dat_identical <- vapply(c("dat_points", "dat_lines", "dat_polygons", "tornado_dat_link", "dat_polygon_line_link", "spc_records"), function(k) identical(get(k, old), get(k, new)), logical(1))
saveRDS(R, qa_out("compare_with_previous.rds")); print(R)
