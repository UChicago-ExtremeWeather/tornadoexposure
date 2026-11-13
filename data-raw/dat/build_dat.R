# Builds the DAT datasets and their link tables from the full fetch of data-raw/dat/fetch_dat.R:
#   dat_points, dat_lines, dat_polygons   every feature of the three layers, all fields, full resolution, EPSG:4326, nothing dropped.
#                                         Date fields stay as the service gives them (milliseconds since 1970-01-01 UTC, a number) with a copy
#                                         <field>_utc beside each (POSIXct, UTC). A missing date is NA.
#   tornado_dat_link                      one row per DAT line linked to an SPC tornado (rules in data-raw/dat/pairing_functions.R)
#   dat_polygon_line_link                 one row per DAT polygon and DAT line dated within one day of each other: the distance between them and
#                                         the share of the line's length inside the polygon (no cutoff)
# Operations on the source geometry: none on the shipped datasets. For the two link tables the geometries are projected to EPSG:5070 and an invalid
# polygon is repaired with st_make_valid (the number repaired is printed and saved in data-raw/dat/fetch/build_summary.rds); the shipped polygons are not repaired.
#
# Run from the package root, after data-raw/process_tracks.R:  caffeinate -i Rscript data-raw/dat/build_dat.R
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(tigris_use_cache = TRUE)
source("data-raw/dat/pairing_functions.R")
lg <- function(...) message(format(Sys.time(), "%H:%M:%S "), ...)
S <- list()

# ---- 1. the datasets as the service gives them -----------------------------------------------------------------------------------------
summ <- readRDS("data-raw/dat/fetch/fetch_summary.rds")
date_fields <- list(`0` = c("stormdate", "surveydate", "edit_time"), `1` = c("stormdate", "starttime", "endtime", "edit_time", "created_date", "last_edited_date"),
                    `2` = c("stormdate", "edit_time", "created_date", "last_edited_date"))
shape <- function(i) {
  x <- readRDS(sprintf("data-raw/dat/fetch/layer%d.rds", i))
  stopifnot(nrow(x) == summ$count_reported[summ$layer == i], !anyDuplicated(x$objectid), identical(st_crs(x)$epsg, 4326L))
  g <- st_geometry(x); d <- st_drop_geometry(x); cols <- list()
  for (nm in names(d)) {
    if (nm %in% date_fields[[as.character(i)]]) { ms <- as.numeric(d[[nm]]); cols[[nm]] <- ms; cols[[paste0(nm, "_utc")]] <- as.POSIXct(ms / 1000, origin = "1970-01-01", tz = "UTC") }
    else cols[[nm]] <- d[[nm]]
  }
  st_sf(as.data.frame(cols, stringsAsFactors = FALSE), geometry = g)
}
dat_points <- shape(0); dat_lines <- shape(1); dat_polygons <- shape(2)
S$counts <- c(points = nrow(dat_points), lines = nrow(dat_lines), polygons = nrow(dat_polygons))
S$empty <- c(points = sum(st_is_empty(dat_points)), lines = sum(st_is_empty(dat_lines)), polygons = sum(st_is_empty(dat_polygons)))
S$no_date <- c(points = sum(is.na(dat_points$stormdate)), lines = sum(is.na(dat_lines$stormdate)), polygons = sum(is.na(dat_polygons$stormdate)))
lg("features: ", paste(names(S$counts), S$counts, collapse = ", "), "; empty geometry: ", paste(names(S$empty), S$empty, collapse = ", "), "; no stormdate: ", paste(names(S$no_date), S$no_date, collapse = ", "))

# ---- 2. SPC tornadoes -------------------------------------------------------------------------------------------------------------------
load("data/tornado_tracks.rda"); load("data/spc_records.rda")
Tt <- tornado_tracks; Tt$date <- as.Date(Tt$date)
spc_st <- spc_records$st[match(Tt$tornado_id, ifelse(spc_records$sg == 1, spc_records$tornado_id, NA_character_))]
stopifnot(!anyNA(spc_st))

# ---- 3. link the DAT lines to the tornadoes ----------------------------------------------------------------------------------------------
usable <- !st_is_empty(dat_lines) & !is.na(dat_lines$stormdate)
S$lines_not_linkable <- c(empty = sum(st_is_empty(dat_lines)), no_date = sum(!st_is_empty(dat_lines) & is.na(dat_lines$stormdate)))
Ld <- dat_lines[usable, ]; Ld$date <- dat_date(Ld$stormdate)
sp <- spc_paths(Tt); sv <- dat_line_paths(Ld)
pr <- candidate_distances(Ld, Tt, sp, sv, window = 1); lg("candidate pairs: ", nrow(pr))
M <- link_rule(pr); lg("links: ", nrow(M), " (", paste(names(table(M$rule)), table(M$rule), collapse = ", "), ")")
stt <- tigris::states(cb = FALSE, year = 2020, progress_bar = FALSE); stt <- st_transform(stt[, "STUSPS"], 4326)
ends <- do.call(rbind, lapply(st_geometry(Ld), function(g) { m <- unclass(g); c(m[1, 1:2], m[nrow(m), 1:2]) }))
st_of <- function(lon, lat) stt$STUSPS[sapply(st_intersects(st_as_sf(data.frame(lon, lat), coords = c("lon", "lat"), crs = 4326), stt), function(x) if (length(x)) x[1] else NA_integer_)]
line_state_s <- st_of(ends[, 1], ends[, 2]); line_state_e <- st_of(ends[, 3], ends[, 4])
ns <- n_samples; i <- M$i; k <- M$k
sd0 <- cbind(sv$Sx[cbind(i, ifelse(M$rev, ns, 1))], sv$Sy[cbind(i, ifelse(M$rev, ns, 1))]); sd1 <- cbind(sv$Sx[cbind(i, ifelse(M$rev, 1, ns))], sv$Sy[cbind(i, ifelse(M$rev, 1, ns))])
sb <- bearing(sd0[, 1], sd0[, 2], sd1[, 1], sd1[, 2]); tb <- bearing(sp$s5[k, 1], sp$s5[k, 2], sp$e5[k, 1], sp$e5[k, 2]); dd <- abs(sb - tb)
tornado_dat_link <- data.frame(
  tornado_id = Tt$tornado_id[k], dat_line_id = as.integer(Ld$objectid[i]),
  index_aligned_dist_km = M$dist_km, one_sided_dist_km = M$one_sided_km,
  length_ratio = ifelse(Tt$len_mi[k] > 0, Ld$length[i] / Tt$len_mi[k], NA_real_),
  direction_diff_deg = ifelse(sp$is_line[k], pmin(dd, 360 - dd), NA_real_),
  same_state = spc_st[k] == line_state_s[i] | spc_st[k] == line_state_e[i],
  n_candidates_tornado = M$n_cand_t, n_candidates_line = M$n_cand_s,
  second_dist_tornado_km = M$second_t, second_dist_line_km = M$second_s,
  relationship = M$relationship, rule = M$rule, stringsAsFactors = FALSE)
tornado_dat_link <- tornado_dat_link[order(tornado_dat_link$tornado_id, tornado_dat_link$dat_line_id), ]; rownames(tornado_dat_link) <- NULL
stopifnot(!anyDuplicated(tornado_dat_link$dat_line_id), all(tornado_dat_link$tornado_id %in% tornado_tracks$tornado_id), all(tornado_dat_link$dat_line_id %in% dat_lines$objectid))
S$link <- c(rows = nrow(tornado_dat_link), tornadoes = length(unique(tornado_dat_link$tornado_id)), mutual_closest = sum(M$rule == "mutual_closest"), attached = sum(M$rule == "attached_to_paired"),
            one_to_many_tornadoes = length(unique(tornado_dat_link$tornado_id[tornado_dat_link$relationship == "one_to_many"])), lines_unlinked = sum(usable) - nrow(tornado_dat_link), candidate_pairs = nrow(pr))
print(S$link)

# ---- 4. polygons and lines dated within one day ---------------------------------------------------------------------------------------------
pu <- !st_is_empty(dat_polygons) & !is.na(dat_polygons$stormdate)
Pd <- dat_polygons[pu, ]; Pd$date <- dat_date(Pd$stormdate)
S$polygons_invalid <- sum(!st_is_valid(Pd)); lg("polygons repaired (st_make_valid) for the link table: ", S$polygons_invalid)
P5 <- st_transform(st_make_valid(st_geometry(Pd)), 5070)
cp <- dplyr::bind_rows(lapply(-1:1, function(o) merge(transform(data.frame(p = seq_len(nrow(Pd)), date = Pd$date), date = date + o), data.frame(i = seq_len(nrow(Ld)), date = Ld$date), by = "date")[, c("p", "i")]))
cp <- cp[order(cp$p, cp$i), ]; rownames(cp) <- NULL; lg("polygon-line pairs within one day: ", nrow(cp))
cp$dist_km <- NA_real_
for (ch in split(seq_len(nrow(cp)), ceiling(seq_len(nrow(cp)) / 20000))) cp$dist_km[ch] <- as.numeric(st_distance(P5[cp$p[ch]], sv$L5[cp$i[ch]], by_element = TRUE)) / 1000
cp$share <- 0
touch <- which(cp$dist_km == 0); len5 <- as.numeric(st_length(sv$L5))
for (r in touch) { x <- tryCatch(st_intersection(sv$L5[cp$i[r]], P5[cp$p[r]]), error = function(e) NULL); cp$share[r] <- if (is.null(x) || length(x) == 0) 0 else sum(as.numeric(st_length(st_collection_extract(x, "LINESTRING")))) / len5[cp$i[r]] }
dat_polygon_line_link <- data.frame(dat_polygon_id = as.integer(Pd$objectid[cp$p]), dat_line_id = as.integer(Ld$objectid[cp$i]), dist_km = cp$dist_km, line_share_in_polygon = cp$share, stringsAsFactors = FALSE)
S$polygon_line <- c(rows = nrow(dat_polygon_line_link), touching = length(touch), share_above_1 = sum(cp$share > 1 + 1e-9), largest_share = max(cp$share))
print(S$polygon_line)
stopifnot(sum(cp$share > 1 + 1e-9) == 0)

# ---- 5. save ---------------------------------------------------------------------------------------------------------------------------------
S$built <- format(Sys.time()); saveRDS(S, "data-raw/dat/fetch/build_summary.rds")
usethis::use_data(dat_points, dat_lines, dat_polygons, tornado_dat_link, dat_polygon_line_link, overwrite = TRUE, compress = "xz")
