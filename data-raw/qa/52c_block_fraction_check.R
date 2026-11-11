# Run from the package root, several copies at once if wanted:  caffeinate -i Rscript data-raw/qa/52c_block_fraction_check.R     (each copy claims state-census year files that no other copy has claimed; progress: data-raw/qa/out/52c_<vintage>.log)
# The published population step caps the share of a block inside a path at 1 (pmin). This recomputes, for the published modeled path polygons of each census year, the intersection of every path with every
# candidate block (the same candidate test, 5 km margin, and the same EPSG:5070 areas) and counts the pieces whose share of the block area exceeds 1, and by how much. One line per state and census year is
# written to the log; data-raw/qa/60 and 61 read the logs. Claims are folders in data-raw/qa/out/52c_claims/ (delete the folder to start again).
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R"); source("R/path_polygon.R")
load("data/tornado_tracks.rda"); tt <- tornado_tracks; yr <- as.integer(substr(tt$tornado_id, 1, 4)); vint <- ifelse(yr < 2010, 2000L, ifelse(yr < 2020, 2010L, 2020L)); states <- pop_states()
tg_of <- function(v) { poly <- .path_polygon(tt[vint == v, ], tt$wid_yd[vint == v], tt$len_mi[vint == v], tt$track_type[vint == v]); st_sf(tid = tt$tornado_id[vint == v], kind = "modeled", geometry = poly) }
cl <- qa_out("52c_claims"); dir.create(cl, showWarnings = FALSE); cur <- NULL; targets <- NULL
for (v in c(2020L, 2010L, 2000L)) for (i in seq_len(nrow(states))) { st <- states[i, ]; if (!dir.create(file.path(cl, paste(v, st$state)), showWarnings = FALSE)) next
  if (!identical(cur, v)) { targets <- tg_of(v); cur <- v }; lgf <- qa_out(sprintf("52c_%s.log", v)); b <- read_blocks(v, st$state_code, st$dir_name, st$abb); bb <- st_as_sfc(st_bbox(b)); tg4269 <- st_transform(targets, 4269); near <- lengths(st_intersects(tg4269, bb)) > 0
  res <- function(pieces = 0L, na_hit = 0L, a1 = 0L, a1t = 0L, mx = NA_real_, nap = 0L, z = 0L) cat(format(Sys.time(), "%H:%M:%S "), v, st$state, pieces, na_hit, a1, a1t, mx, nap, z, "\n", file = lgf, append = TRUE)
  if (!any(near)) { res(); next }; tg <- targets[near, ]; cand <- lengths(st_intersects(b, st_transform(st_union(st_buffer(st_geometry(tg), 5000)), 4269))) > 0; if (!any(cand)) { res(); next }
  bc <- st_make_valid(st_transform(b[cand, ], 5070)); bc$a_blk <- as.numeric(st_area(bc)); bc$bid <- seq_len(nrow(bc)); x <- suppressWarnings(st_intersection(tg[, c("tid", "kind")], bc[, c("bid", "pop", "a_blk")]))
  x <- st_collection_extract(x, "POLYGON"); x$a_in <- as.numeric(st_area(x)); x <- st_drop_geometry(x); x$frac <- x$a_in / x$a_blk
  res(nrow(x), length(unique(x$bid[is.na(x$pop)])), sum(x$frac > 1), sum(x$frac > 1 + 1e-9), max(x$frac), sum(is.na(x$pop)), sum(x$a_blk == 0)); rm(b, bc, x); gc(verbose = FALSE) }
