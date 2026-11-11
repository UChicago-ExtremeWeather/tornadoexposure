# Run from the package root:  caffeinate -i Rscript data-raw/qa/52_fidelity_audit_counts.R   (progress: data-raw/qa/out/52.log)
# Counts for the audit of every operation applied to source data or geometry (what each touches). Saves data-raw/qa/out/audit_counts.rds.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220)
source("data-raw/qa/helpers.R"); source("data-raw/survey/pairing_functions.R")
lg <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S "), ...); cat(m, "\n"); cat(m, "\n", file = qa_out("52.log"), append = TRUE) }
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
tt <- st_drop_geometry(tornado_tracks); yr <- as.integer(substr(tt$tornado_id, 1, 4)); era <- ifelse(yr < 2007, "1996-2006", "2007+"); R <- list()
# ---- SPC file: what is dropped -----------------------------------------------------------------------------------------------
raw <- read.csv(qa_spc_csv(), stringsAsFactors = FALSE); R$spc_md5_ok <- identical(unname(tools::md5sum(qa_spc_csv())), "75a41f9ae8f9ef74cc4be7e9cae78fa9")
R$raw_rows <- nrow(raw); R$raw_cols <- names(raw); R$yr_before_1996 <- sum(raw$yr < 1996); r96 <- raw[raw$yr >= 1996, ]
R$sg_table_1996 <- table(r96$sg); R$sg_other_by_era <- table(r96$sg[r96$sg != 1], ifelse(r96$yr[r96$sg != 1] < 2007, "1996-2006", "2007+"))
s1 <- r96[r96$sg == 1, ]; R$sg1_rows <- nrow(s1)
R$no_valid_start <- sum(is.na(s1$slon) | is.na(s1$slat) | s1$slon == 0 | s1$slat == 0)
s1$tornado_id <- paste(s1$yr, s1$om, sep = "_"); dup <- duplicated(s1$tornado_id) | duplicated(s1$tornado_id, fromLast = TRUE)
R$dup_id_rows <- sum(dup); R$dup_id_values <- unique(s1$tornado_id[dup])
R$cols_kept <- c("yr", "mo", "dy", "date", "om", "mag", "inj", "fat", "loss", "slat", "slon", "elat", "elon", "len", "wid", "sg")
R$cols_dropped <- setdiff(names(raw), R$cols_kept)
R$raw_head <- head(raw, 2)
# columns in the stored tracks: which raw values are not kept for point tracks (raw end coordinates)
tid_ok <- s1$tornado_id; tid_ok[dup] <- paste0(tid_ok[dup], "_", ave(seq_len(sum(dup)), s1$tornado_id[dup], FUN = seq_along))
s1$tornado_id2 <- tid_ok; m <- match(tt$tornado_id, s1$tornado_id2); stopifnot(!anyNA(m)); sp <- s1[m, ]
# ---- widths -----------------------------------------------------------------------------------------------------------------------
imp <- tt$width_imputed; R$width_imputed <- sum(imp); R$width_imputed_by_type <- table(ifelse(tt$track_type == "line", "line", "point"), imp)
R$width_imputed_by_type_era <- table(tt$track_type[imp], era[imp]); R$width_raw_value <- table(ifelse(is.na(sp$wid[imp]), "NA", as.character(sp$wid[imp])))
R$width_stored_vs_raw <- sum(!imp & sp$wid != tt$wid_yd, na.rm = TRUE)
# ---- point tracks -------------------------------------------------------------------------------------------------------------------
pt <- tt$track_type != "line"; R$point_total <- sum(pt); R$point_by_type <- table(tt$track_type); R$point_by_era <- table(era, pt)
R$point_by_era_rating <- table(era[pt], ifelse(is.na(tt$magnitude[pt]), "unknown", paste0("EF", tt$magnitude[pt])))
R$point_reason <- table(ifelse(is.na(sp$elon[pt]) | is.na(sp$elat[pt]), "end missing", ifelse(sp$elon[pt] == 0 | sp$elat[pt] == 0, "end 0", "end equals start")))
R$point_reason_era <- table(ifelse(is.na(sp$elon[pt]) | is.na(sp$elat[pt]), "end missing", ifelse(sp$elon[pt] == 0 | sp$elat[pt] == 0, "end 0", "end equals start")), era[pt])
R$point_len_zero <- sum(pt & tt$len_mi == 0); R$point_len_na <- sum(pt & is.na(tt$len_mi))
# ---- loss ----------------------------------------------------------------------------------------------------------------------------
mm <- sp$loss[yr < 2007] * 1e6; d <- abs(mm - round(mm)); R$loss_millions_n <- sum(yr < 2007 & sp$loss > 0); R$loss_round_changed <- sum(d > 1e-6, na.rm = TRUE); R$loss_round_max_diff_dollars <- max(d, na.rm = TRUE)
R$loss_round_changed_1e9 <- sum(d > 1e-9, na.rm = TRUE); dec <- function(x) { s <- sub("0+$", "", format(x, scientific = FALSE, digits = 15)); nchar(sub("^[^.]*\\.?", "", s)) }
R$loss_millions_decimals <- table(dec(sp$loss[yr < 2007 & sp$loss > 0]))
# ---- caps ----------------------------------------------------------------------------------------------------------------------------
R$cap_modeled_rows_eq1 <- sum(tornado_exposure$area_prop_affected == 1); R$cap_modeled_rows_total <- nrow(tornado_exposure); R$cap_survey_rows_eq1 <- sum(survey_exposure$area_prop_affected == 1)
R$cap_modeled_by_type <- table(tornado_exposure$track_type[tornado_exposure$area_prop_affected == 1])
# ---- centroids -----------------------------------------------------------------------------------------------------------------------
R$centroid_rows <- nrow(zcta_centroids); R$centroid_decimals_max <- max(vapply(zcta_centroids$lon[1:5000], function(x) nchar(sub("^[^.]*\\.?", "", format(x, digits = 15))), 1L))
# ---- DAT fetch, lines and polygons ----------------------------------------------------------------------------------------------
L <- readRDS(qa_out("dat_lines_live.rds")); P <- readRDS(qa_out("dat_polys_live.rds")); R$dat_lines <- nrow(L); R$dat_polys <- nrow(P)
R$dat_poly_vertices <- sum(vapply(st_geometry(P), function(x) sum(rapply(list(unclass(x)), function(m) nrow(m), classes = "matrix", how = "unlist")), 1)); R$dat_poly_types <- table(st_geometry_type(P)); R$dat_line_types <- table(st_geometry_type(L))
R$dat_polys_invalid <- sum(!st_is_valid(P)); R$dat_lines_invalid <- sum(!st_is_valid(L)); R$dat_poly_efscale <- table(P$efscale, useNA = "ifany"); R$dat_line_efscale <- table(L$efscale, useNA = "ifany")
ctx <- survey_context(); Du <- ctx$Du; R$lines_after_merge <- nrow(Du); R$exact_copy_lines_removed <- nrow(L) - nrow(Du)
multi <- vapply(st_geometry(L), function(g) inherits(g, "MULTILINESTRING"), NA); R$multipart_lines_raw <- sum(multi); R$multipart_lines_distinct <- sum(vapply(st_geometry(Du), function(g) inherits(g, "MULTILINESTRING"), NA))
mm5 <- st_transform(st_make_valid(st_geometry(Du)), 5070); mu <- which(vapply(mm5, function(g) inherits(g, "MULTILINESTRING"), NA))
parts <- lapply(mu, function(i) { g <- st_line_merge(mm5[[i]]); if (inherits(g, "MULTILINESTRING")) vapply(unclass(g), function(p) as.numeric(st_length(st_linestring(p))), 0) else NA }); R$multipart_still_multi_after_merge <- sum(vapply(parts, function(p) length(p) > 1, NA))
R$multipart_dropped_km <- sum(vapply(parts, function(p) if (length(p) > 1) sum(p) - max(p) else 0, 0)) / 1000; R$multipart_total_km <- sum(vapply(mu, function(i) as.numeric(st_length(mm5[[i]])), 0)) / 1000
lg("DAT lines and polygons counted")
# ---- the swath filter ------------------------------------------------------------------------------------------------------------------
sm <- survey_matches; M <- sm[sm$status != "no_pair", ]; sw <- ctx$sw; Tt <- ctx$Tt; pr <- candidate_distances(Du, Tt, ctx$sp, ctx$sv, 1); MC <- mutual_closest(pr)
tot_raw <- tot_ef <- tot_kept <- 0L; used_poly <- integer(0); drop_ef <- drop_90 <- 0L; geoms <- vector("list", nrow(MC)); nused <- integer(nrow(MC))
for (r in seq_len(nrow(MC))) { i <- MC$i[r]; k <- MC$k[r]; q <- sw$hit[[i]]; q <- q[abs(as.numeric(sw$Pd[q] - Du$date[i])) <= 1]; tot_raw <- tot_raw + length(q)
  q2 <- q[sw$P$efscale[q] %in% paste0("EF", 0:5)]; drop_ef <- drop_ef + length(q) - length(q2); tot_ef <- tot_ef + length(q2); keep <- integer(0)
  if (length(q2)) { half_km <- Tt$wid_yd[k] * 0.9144 / 2 / 1000; buf <- st_buffer(sw$sv$L5[i], half_km * 2 * 1000 + 500)
    inb <- vapply(q2, function(z) tryCatch(as.numeric(st_area(st_intersection(sw$P5[z], buf))) / sw$P_area[z], error = function(e) NA_real_), numeric(1)); keep <- q2[!is.na(inb) & inb >= 0.9]; drop_90 <- drop_90 + length(q2) - length(keep) }
  tot_kept <- tot_kept + length(keep); nused[r] <- length(keep)
  if (length(keep)) { u <- st_union(st_make_valid(sw$P5[keep])); cov <- tryCatch(as.numeric(st_length(st_intersection(sw$sv$L5[i], st_buffer(u, 200)))) / as.numeric(st_length(sw$sv$L5[i])), error = function(e) NA_real_); if (!is.na(cov) && cov >= 0.5) { geoms[[r]] <- u; used_poly <- c(used_poly, keep) } }
  if (r %% 2000 == 0) lg("swath loop ", r) }
R$swath_pairs <- nrow(MC); R$swath_polygon_incidences_raw <- tot_raw; R$swath_dropped_unrated_or_other_efscale <- drop_ef; R$swath_dropped_by_90pct_rule <- drop_90; R$swath_incidences_kept <- tot_kept
R$swath_pairs_with_kept <- sum(nused > 0); R$usable_swaths <- sum(!vapply(geoms, is.null, NA)); R$polygons_used_distinct <- length(unique(used_poly)); R$polygons_never_used <- nrow(P) - length(unique(used_poly))
R$polygons_efscale_not_ef0_5 <- sum(!P$efscale %in% paste0("EF", 0:5)); R$polygons_used_by_more_than_one_swath <- sum(table(used_poly) > 1)
# survey_tracks versus the unsimplified swath (5070): vertices and area
ok <- which(!vapply(geoms, is.null, NA)); S <- st_sf(tornado_id = Tt$tornado_id[MC$k[ok]], geometry = st_sfc(lapply(ok, function(r) geoms[[r]][[1]]), crs = 5070))
st5 <- st_transform(survey_tracks, 5070); mt <- match(S$tornado_id, st5$tornado_id); R$survey_tracks_n <- nrow(survey_tracks)
nv <- function(g) vapply(st_geometry(g), function(x) sum(rapply(list(unclass(x)), function(m) nrow(m), classes = "matrix", how = "unlist")), 1); R$swath_vertices_full <- sum(nv(S)); R$survey_tracks_vertices <- sum(nv(st5[mt, ]))
da <- as.numeric(st_area(st5[mt, ])) / as.numeric(st_area(S)) - 1; R$survey_tracks_area_change_pct <- quantile(abs(da) * 100, c(.5, .9, .99, 1))
lg("swath filter counted")
# ---- ZCTA polygons repaired by st_make_valid -----------------------------------------------------------------------------------------
tg <- Sys.getenv("TIGRIS_CACHE_DIR", rappdirs::user_cache_dir("tigris")); R$zcta_invalid <- list()
for (f in c(`2000` = "tl_2010_us_zcta500", `2010` = "tl_2010_us_zcta510", `2020` = "tl_2020_us_zcta520")) { p <- file.path(tg, paste0(f, ".shp")); if (!file.exists(p)) { R$zcta_invalid[[f]] <- NA; next }
  z <- st_read(p, quiet = TRUE); z5 <- st_transform(z, 5070); z4 <- st_transform(z, 4269)
  R$zcta_invalid[[f]] <- c(features = nrow(z), invalid_as_read = sum(!st_is_valid(z)), invalid_after_5070 = sum(!st_is_valid(z5)), invalid_after_4269 = sum(!st_is_valid(z4))); lg("ZCTA ", f, ": ", paste(R$zcta_invalid[[f]], collapse = " ")) }
saveRDS(R, qa_out("audit_counts.rds")); lg("done 52"); str(R, max.level = 1, give.attr = FALSE, vec.len = 3)
