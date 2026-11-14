# Land-only shapes: a Census unit (ZCTA, or a block) polygon minus the Census water polygons (TIGER/Line AREAWATER, one file per county).
# Source from the package root after loading sf and dplyr, with sf_use_s2(FALSE). Areas and overlays are in EPSG:5070 (equal area).
#
# Water files: data-raw/cache/areawater/<set>/tl_<set>_<county fips>_areawater.zip, TIGER2020 for the 2020 boundary year and TIGER2010 for the 2010 and
# 2000 boundary years (the Census published no separate AREAWATER files for 2000). prepare_water() reads each file once, transforms it to EPSG:5070,
# repairs invalid polygons (the number is kept) and stores the polygons of each state in data-raw/cache/water_prepared/ (git-ignored).
# Nothing is simplified, rounded or thinned: a land shape is the unit polygon with the part inside a water polygon removed.
water_set <- c("2000" = "2010", "2010" = "2010", "2020" = "2020")
water_dir <- "data-raw/cache/areawater"
water_prep_dir <- "data-raw/cache/water_prepared"

prepare_water <- function(set) {
  dir.create(water_prep_dir, recursive = TRUE, showWarnings = FALSE)
  files <- list.files(file.path(water_dir, set), pattern = "_areawater[.]zip$", full.names = TRUE)
  county <- sub(".*_([0-9]{5})_areawater[.]zip$", "\\1", files)
  rows <- list()
  for (st in sort(unique(substr(county, 1, 2)))) {
    out <- file.path(water_prep_dir, sprintf("%s_%s.rds", set, st))
    if (file.exists(out)) { rows[[st]] <- readRDS(out)$summary; next }
    fs <- files[substr(county, 1, 2) == st]; invalid <- 0L; nw <- 0L; g <- list()
    for (f in fs) {
      w <- tryCatch(sf::st_read(paste0("/vsizip/", f), quiet = TRUE), error = function(e) NULL)
      if (is.null(w) || nrow(w) == 0) next
      w <- sf::st_transform(sf::st_geometry(w), 5070); bad <- !sf::st_is_valid(w); invalid <- invalid + sum(bad)
      nw <- nw + length(w); g[[length(g) + 1]] <- sf::st_make_valid(w)
    }
    gg <- if (length(g)) do.call(c, g) else sf::st_sfc(crs = 5070)
    gg <- gg[!sf::st_is_empty(gg)]
    s <- data.frame(set = set, state = st, files = length(fs), bytes = sum(file.size(fs)), water_polygons = nw, invalid_repaired = invalid)
    saveRDS(list(geom = gg, bbox = if (length(gg)) as.numeric(sf::st_bbox(gg)) else rep(NA_real_, 4), summary = s), out)
    rows[[st]] <- s; message(format(Sys.time(), "%H:%M:%S "), set, " state ", st, ": ", length(fs), " files, ", nw, " water polygons, ", invalid, " repaired")
  }
  do.call(rbind, rows)
}

# bounding box of the water polygons of each state file (EPSG:5070), so that only the files near the units are read
water_index <- function(set) {
  f <- file.path("data-raw/cache", paste0("water_index_", set, ".rds"))
  if (file.exists(f)) return(readRDS(f))
  fs <- list.files(water_prep_dir, pattern = paste0("^", set, "_[0-9]{2}[.]rds$"), full.names = TRUE)
  ix <- do.call(rbind, lapply(fs, function(x) { b <- readRDS(x)$bbox; data.frame(file = x, xmin = b[1], ymin = b[2], xmax = b[3], ymax = b[4]) }))
  ix <- ix[!is.na(ix$xmin), ]; saveRDS(ix, f); ix
}

# Polygons only (a difference can return a collection); an empty result stays an empty polygon
.polygons_only <- function(x, crs = 5070) {
  if (length(x) == 0 || all(sf::st_is_empty(x))) return(sf::st_sfc(sf::st_polygon(), crs = crs))
  if (any(sf::st_geometry_type(x) == "GEOMETRYCOLLECTION")) x <- sf::st_collection_extract(x, "POLYGON")
  if (length(x) > 1) x <- sf::st_union(x)
  x
}

# geom: sfc of valid polygons in EPSG:5070. Returns list(land = sfc of the same length (the polygon minus the water polygons inside it; an empty
# polygon where all of it is water), water_touched = which polygons had a water polygon inside them, water_m2, area_m2, land_m2). The polygons are
# processed in chunks of `chunk` (ordered west to east) to bound the memory; the result does not depend on the chunking.
land_of <- function(geom, set, cores = 1, chunk = 2500) {
  n <- length(geom); crs <- sf::st_crs(geom); ix <- water_index(set)
  bbx <- t(vapply(geom, function(g) as.numeric(sf::st_bbox(g)), numeric(4)))
  ord <- order(bbx[, 1] + bbx[, 3]); lst <- unclass(geom); touched <- integer(0)
  for (ch in split(ord, ceiling(seq_along(ord) / chunk))) {
    bb <- bbx[ch, , drop = FALSE]; wl <- vector("list", length(ch)); g <- geom[ch]
    for (f in ix$file[ix$xmin <= max(bb[, 3]) & ix$xmax >= min(bb[, 1]) & ix$ymin <= max(bb[, 4]) & ix$ymax >= min(bb[, 2])]) {
      W <- readRDS(f); if (!length(W$geom)) next; wb <- W$bbox
      cand <- which(bb[, 1] <= wb[3] & bb[, 3] >= wb[1] & bb[, 2] <= wb[4] & bb[, 4] >= wb[2]); if (!length(cand)) next
      h <- sf::st_intersects(g[cand], W$geom)
      for (k in which(lengths(h) > 0)) wl[[cand[k]]] <- c(wl[[cand[k]]], list(W$geom[h[[k]]]))
      rm(W, h)
    }
    has <- which(lengths(wl) > 0)
    one <- function(i) .polygons_only(sf::st_difference(g[i], sf::st_union(do.call(c, wl[[i]]))), crs)[[1]]
    res <- if (cores > 1 && length(has) > 1) parallel::mclapply(has, one, mc.cores = cores) else lapply(has, one)
    for (k in seq_along(has)) lst[[ch[has[k]]]] <- res[[k]]
    touched <- c(touched, ch[has]); rm(wl, res, g); invisible(gc())
  }
  land <- sf::st_sfc(lapply(lst, identity), crs = crs)
  area <- as.numeric(sf::st_area(geom)); la <- as.numeric(sf::st_area(land))
  list(land = land, water_touched = sort(touched), area_m2 = area, land_m2 = la, water_m2 = area - la)
}

# The land-only shapes of the ZCTAs of one boundary year (full TIGER/Line polygons), cached outside the repository.
zcta_land <- function(vintage, cores = 1) {
  f <- file.path("data-raw/cache", sprintf("zcta_land_%s.rds", vintage))
  if (file.exists(f)) return(readRDS(f))
  z <- load_zctas(vintage); set <- water_set[[as.character(vintage)]]
  L <- land_of(sf::st_geometry(z), set, cores)
  d <- data.frame(ZCTA = z$ZCTA, ALAND = z$ALAND, polygon_m2 = L$area_m2, land_m2 = L$land_m2, water_m2 = L$water_m2, water_touched = seq_len(nrow(z)) %in% L$water_touched, stringsAsFactors = FALSE)
  out <- list(d = d, land = L$land, vintage = vintage, invalid_repaired = attr(z, "n_repaired"), water_set = set)
  saveRDS(out, f); out
}

# URL, size, md5 and download date of every water file (the file date is the day it was downloaded), written to data-raw/provenance_water.csv and into data-raw/provenance.txt
water_provenance <- function() {
  rows <- lapply(c("2010", "2020"), function(set) { fs <- list.files(file.path(water_dir, set), pattern = "_areawater[.]zip$", full.names = TRUE)
    data.frame(url = sprintf("https://www2.census.gov/geo/tiger/TIGER%s/AREAWATER/%s", set, basename(fs)), bytes = file.size(fs), md5 = unname(tools::md5sum(fs)), date = format(file.mtime(fs), "%Y-%m-%d"), stringsAsFactors = FALSE) })
  w <- do.call(rbind, rows); w <- w[order(w$url), ]; write.csv(w, "data-raw/provenance_water.csv", row.names = FALSE)
  prov <- readLines("data-raw/provenance.txt"); i <- which(prov == "## Water polygons")[1]
  if (!is.na(i)) { nxt <- which(grepl("^## ", prov) & seq_along(prov) > i)[1]; prov <- prov[-(i:(if (is.na(nxt)) length(prov) else nxt - 1))] }
  writeLines(c(prov, "## Water polygons", paste0("Downloaded: ", min(w$date), " to ", max(w$date), " (the date of each file is in data-raw/provenance_water.csv)"),
    "TIGER/Line AREAWATER, one file per county: TIGER2020 for the 2020 boundary year, TIGER2010 for the 2010 and 2000 boundary years (no separate files exist for 2000)",
    paste0("Downloads: ", nrow(w), " files, ", round(sum(w$bytes) / 1e9, 1), " GB; every URL, size and md5 is in data-raw/provenance_water.csv (md5 of that file: ", unname(tools::md5sum("data-raw/provenance_water.csv")), ")")), "data-raw/provenance.txt")
  invisible(w)
}
