# Functions for the population step (block-level resident population in each
# tornado path, assigned to ZCTAs). Sourced by data-raw/add_population.R.
#
# Sources (no API key or account needed):
#   2020: TIGER/Line tabulation blocks (field POP20 holds the block population)
#   2010 and 2000: TIGER/Line tabulation blocks plus the Census PL 94-171
#                  redistricting files (total population by block)
# Downloads are cached outside the repository.

suppressMessages({library(sf); library(dplyr)})
sf_use_s2(FALSE)
options(tigris_use_cache = TRUE)

pop_cache <- function(...) {
  d <- Sys.getenv("TORNADOEXPOSURE_CACHE", tools::R_user_dir("tornadoexposure", "cache"))
  p <- file.path(d, ...)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  p
}

# 50 states, DC and Puerto Rico
pop_states <- function() {
  fc <- unique(tigris::fips_codes[, c("state", "state_code", "state_name")])
  fc <- fc[fc$state_code <= "56" | fc$state_code == "72", ]
  fc$dir_name <- gsub(" ", "_", fc$state_name)
  fc$abb <- tolower(fc$state)
  rownames(fc) <- NULL
  fc
}

block_url <- function(vintage, fips) {
  switch(as.character(vintage),
    "2020" = sprintf("https://www2.census.gov/geo/tiger/TIGER2020/TABBLOCK20/tl_2020_%s_tabblock20.zip", fips),
    "2010" = sprintf("https://www2.census.gov/geo/tiger/TIGER2010/TABBLOCK/2010/tl_2010_%s_tabblock10.zip", fips),
    "2000" = sprintf("https://www2.census.gov/geo/tiger/TIGER2010/TABBLOCK/2000/tl_2010_%s_tabblock00.zip", fips))
}

pl_urls <- function(vintage, dir_name, abb) {
  switch(as.character(vintage),
    "2010" = sprintf("https://www2.census.gov/census_2010/01-Redistricting_File--PL_94-171/%s/%s2010.pl.zip", dir_name, abb),
    "2000" = c(sprintf("https://www2.census.gov/census_2000/datasets/redistricting_file--pl_94-171/%s/%s00001.upl.zip", dir_name, abb),
               sprintf("https://www2.census.gov/census_2000/datasets/redistricting_file--pl_94-171/%s/%sgeo.upl.zip", dir_name, abb)))
}

# download with retries; returns the local path and records url, size and md5
download_cached <- function(url, record = TRUE) {
  dest <- pop_cache("downloads", basename(url))
  if (!file.exists(dest)) {
    tmp <- paste0(dest, ".part")
    ok <- FALSE
    for (k in 1:4) {
      ok <- tryCatch({ download.file(url, tmp, mode = "wb", quiet = TRUE, method = "libcurl"); TRUE }, error = function(e) FALSE, warning = function(w) FALSE)
      if (ok && file.exists(tmp) && file.size(tmp) > 0) break
      Sys.sleep(5 * k)
    }
    if (!ok) stop("download failed: ", url)
    file.rename(tmp, dest)
  }
  if (record) {
    rec <- pop_cache("downloads_record.csv")
    if (!file.exists(rec) || !(url %in% read.csv(rec, stringsAsFactors = FALSE)$url)) {
      row <- data.frame(url = url, bytes = file.size(dest), md5 = unname(tools::md5sum(dest)), date = format(Sys.Date()))
      write.table(row, rec, sep = ",", row.names = FALSE, col.names = !file.exists(rec), append = file.exists(rec))
    }
  }
  dest
}

# PL 94-171 total population by block for 2010 and 2000 (fixed-width geographic
# header plus the first data file; verified against the state totals)
read_pl_pop <- function(vintage, dir_name, abb) {
  urls <- pl_urls(vintage, dir_name, abb)
  td <- tempfile("pl"); dir.create(td)
  on.exit(unlink(td, recursive = TRUE))
  for (u in urls) utils::unzip(download_cached(u), exdir = td)
  if (vintage == 2010) {
    geo <- list.files(td, pattern = "geo2010\\.pl$", full.names = TRUE)
    dat <- list.files(td, pattern = "000012010\\.pl$", full.names = TRUE)
    pos <- list(st = c(28, 29), co = c(30, 32), tr = c(55, 60), bl = c(62, 65))
  } else {
    geo <- list.files(td, pattern = "geo\\.upl$", full.names = TRUE)
    dat <- list.files(td, pattern = "00001\\.upl$", full.names = TRUE)
    pos <- list(st = c(30, 31), co = c(32, 34), tr = c(56, 61), bl = c(63, 66))
  }
  g <- readLines(geo, encoding = "latin1")
  header <- g[substr(g, 1, 4) %in% c("PLST", "uPL ", "uPL")][1]
  blocks <- g[substr(g, 9, 11) == "750"]
  geoid <- paste0(substr(blocks, pos$st[1], pos$st[2]), substr(blocks, pos$co[1], pos$co[2]),
                  substr(blocks, pos$tr[1], pos$tr[2]), substr(blocks, pos$bl[1], pos$bl[2]))
  lr <- as.integer(substr(blocks, 19, 25))
  d <- utils::read.csv(dat, header = FALSE, colClasses = "character")
  pop <- setNames(as.integer(d$V6), as.integer(d$V5))
  # state total from the state record (SUMLEV 040) as a check
  state_rec <- g[substr(g, 9, 11) == "040"][1]
  state_total <- unname(pop[as.character(as.integer(substr(state_rec, 19, 25)))])
  out <- data.frame(GEOID = geoid, pop = unname(pop[as.character(lr)]), stringsAsFactors = FALSE)
  attr(out, "state_total") <- state_total
  out
}

# blocks of one state: GEOID, pop, internal point, geometry (EPSG:4269)
read_blocks <- function(vintage, fips, dir_name, abb) {
  zip <- download_cached(block_url(vintage, fips))
  td <- tempfile("blk"); dir.create(td)
  on.exit(unlink(td, recursive = TRUE))
  utils::unzip(zip, exdir = td)
  shp <- list.files(td, pattern = "\\.shp$", full.names = TRUE)
  lay <- tools::file_path_sans_ext(basename(shp))
  sfx <- substr(vintage, 3, 4)
  gcol <- if (vintage == 2000) "BLKIDFP00" else paste0("GEOID", sfx)
  popcol <- if (vintage == 2020) ", POP20 AS pop" else ""
  q <- sprintf("SELECT %s AS GEOID, INTPTLAT%s AS lat, INTPTLON%s AS lon%s FROM %s", gcol, sfx, sfx, popcol, lay)
  b <- sf::read_sf(shp, query = q)
  b$lat <- as.numeric(b$lat); b$lon <- as.numeric(b$lon)
  if (vintage != 2020) {
    p <- read_pl_pop(vintage, dir_name, abb)
    b$pop <- p$pop[match(b$GEOID, p$GEOID)]
    attr(b, "state_total") <- attr(p, "state_total")
  } else {
    b$pop <- as.integer(b$pop)
  }
  b
}

zcta_layer <- function(vintage) {
  z <- tigris::zctas(year = vintage, progress_bar = FALSE)
  sfx <- substr(vintage, 3, 4)
  z <- z[, paste0("ZCTA5CE", sfx)]
  names(z)[1] <- "ZCTA"
  sf::st_make_valid(sf::st_transform(z, 4269))
}

# One state, one vintage. `targets` is an sf of polygons in EPSG:5070 with
# columns tid (character) and kind. Returns:
#   blocks:  GEOID, pop, ZCTA (block assigned by its internal point; NA if none)
#   pop_aff: per target and ZCTA (NA = blocks assigned to no ZCTA), the residents
#            allocated by the share of each block's area inside the polygon
process_state <- function(vintage, st, targets, zl) {
  b <- read_blocks(vintage, st$state_code, st$dir_name, st$abb)
  st_total_pl <- attr(b, "state_total")
  n_blocks <- nrow(b)
  # assign every block to a ZCTA through its internal point
  ok <- !is.na(b$lat) & !is.na(b$lon)
  pts <- sf::st_as_sf(data.frame(GEOID = b$GEOID[ok], lon = b$lon[ok], lat = b$lat[ok]), coords = c("lon", "lat"), crs = 4269)
  bb <- sf::st_as_sfc(sf::st_bbox(b))
  zsub <- zl[lengths(sf::st_intersects(zl, bb)) > 0, ]
  j <- sf::st_join(pts, zsub, join = sf::st_intersects)
  j <- j[!duplicated(j$GEOID), ]
  b$ZCTA <- j$ZCTA[match(b$GEOID, j$GEOID)]
  blocks <- sf::st_drop_geometry(b)[, c("GEOID", "pop", "ZCTA")]
  summary_row <- data.frame(vintage = vintage, state = st$state, blocks = n_blocks, pop_sum = sum(b$pop, na.rm = TRUE),
                            pop_na = sum(is.na(b$pop)), state_total_pl = if (is.null(st_total_pl)) NA_real_ else st_total_pl,
                            blocks_no_zcta = sum(is.na(b$ZCTA)), pop_no_zcta = sum(b$pop[is.na(b$ZCTA)], na.rm = TRUE))
  # targets that reach this state
  tg4269 <- sf::st_transform(targets, 4269)
  near <- lengths(sf::st_intersects(tg4269, bb)) > 0
  pop_aff <- NULL
  if (any(near)) {
    tg <- targets[near, ]; tg4 <- tg4269[near, ]
    # candidate blocks: near the paths. The paths are straight-edged in EPSG:5070, but this test is done in
    # longitude/latitude, where their edges are curved (up to about 1 km for the longest paths), so the paths are
    # buffered by 5 km first: a block that a path touches is never missed, and the result does not depend on which
    # other paths are processed together. The intersection itself is computed in EPSG:5070.
    cand <- lengths(sf::st_intersects(b, sf::st_transform(sf::st_union(sf::st_buffer(sf::st_geometry(tg), 5000)), 4269))) > 0
    if (any(cand)) {
      bc <- sf::st_make_valid(sf::st_transform(b[cand, ], 5070))
      bc$a_blk <- as.numeric(sf::st_area(bc))
      bc$bid <- seq_len(nrow(bc))
      x <- suppressWarnings(sf::st_intersection(tg[, c("tid", "kind")], bc[, c("bid", "pop", "ZCTA", "a_blk")]))
      if (nrow(x)) {
        x <- sf::st_collection_extract(x, "POLYGON")
        x$a_in <- as.numeric(sf::st_area(x))
        x <- sf::st_drop_geometry(x)
        x$frac <- pmin(x$a_in / x$a_blk, 1)
        x$pop_aff <- ifelse(is.na(x$pop), 0, x$pop) * x$frac
        pop_aff <- x %>% group_by(tid, kind, ZCTA) %>% summarise(pop_aff = sum(pop_aff), n_blocks = n(), .groups = "drop")
      }
    }
  }
  list(blocks = blocks, pop_aff = pop_aff, summary = summary_row)
}

# Residents inside new target polygons, for the incremental update. Uses the per-state block results
# that data-raw/add_population.R cached (block population and block-to-ZCTA assignment, `blocks`) and
# reads the block geometries only where the targets are. If a state has not been cached, it is processed
# in full with process_state() (slow: it assigns every block to a ZCTA) and cached. `targets` is an sf of
# polygons in EPSG:5070 with columns tid and kind, all of one vintage; `states` is pop_states().
# Returns the residents per target and ZCTA (NA ZCTA = blocks assigned to no ZCTA).
pop_aff_cached <- function(vintage, targets, states, zl, all_blocks = FALSE) {   # all_blocks = TRUE skips the candidate test (for checking it)
  stt <- tigris::states(cb = TRUE, year = 2020, progress_bar = FALSE)
  stt <- sf::st_buffer(sf::st_transform(stt[, "STATEFP"], 5070), 10000)    # generalized outlines: be generous
  hit <- sf::st_intersects(targets, stt)
  fips <- sort(unique(stt$STATEFP[unlist(hit)]))
  fips <- fips[fips %in% states$state_code]
  out <- list()
  for (fp in fips) {
    st <- states[states$state_code == fp, ]
    wf <- pop_cache("work", sprintf("%s_%s.rds", vintage, fp))
    tg <- targets[vapply(hit, function(h) fp %in% stt$STATEFP[h], logical(1)), ]
    if (!file.exists(wf)) {
      res <- process_state(vintage, st, targets, zl); saveRDS(res, wf)
      if (!is.null(res$pop_aff)) out[[length(out) + 1]] <- res$pop_aff[, c("tid", "ZCTA", "pop_aff")]
      next
    }
    bl <- readRDS(wf)$blocks
    zip <- download_cached(block_url(vintage, fp), record = FALSE)
    td <- tempfile("blk"); dir.create(td); utils::unzip(zip, exdir = td)
    shp <- list.files(td, pattern = "\\.shp$", full.names = TRUE)
    wkt <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(sf::st_transform(sf::st_buffer(sf::st_geometry(tg), 5000), 4269))))
    b <- sf::read_sf(shp, wkt_filter = wkt); unlink(td, recursive = TRUE)
    gcol <- if (vintage == 2000) "BLKIDFP00" else paste0("GEOID", substr(vintage, 3, 4))
    b$GEOID <- b[[gcol]]; b <- b[, "GEOID"]
    b$pop <- bl$pop[match(b$GEOID, bl$GEOID)]; b$ZCTA <- bl$ZCTA[match(b$GEOID, bl$GEOID)]
    # candidate blocks: near the paths, buffered by 5 km (see process_state()) so that no touched block is missed
    near_paths <- sf::st_transform(sf::st_union(sf::st_buffer(sf::st_geometry(tg), 5000)), 4269)
    cand <- if (all_blocks) rep(TRUE, nrow(b)) else lengths(sf::st_intersects(b, near_paths)) > 0
    if (!any(cand)) next
    bc <- sf::st_make_valid(sf::st_transform(b[cand, ], 5070)); bc$a_blk <- as.numeric(sf::st_area(bc))
    x <- suppressWarnings(sf::st_intersection(tg[, c("tid", "kind")], bc[, c("GEOID", "pop", "ZCTA", "a_blk")]))
    if (!nrow(x)) next
    x <- sf::st_collection_extract(x, "POLYGON"); x$a_in <- as.numeric(sf::st_area(x)); x <- sf::st_drop_geometry(x)
    x$pop_aff <- ifelse(is.na(x$pop), 0, x$pop) * pmin(x$a_in / x$a_blk, 1)
    # sum in a fixed order (path, ZCTA, block, piece area), so the result does not depend on which other paths were processed together
    x <- x[order(x$tid, x$ZCTA, x$GEOID, x$a_in), ]
    out[[length(out) + 1]] <- x %>% group_by(tid, ZCTA) %>% summarise(pop_aff = sum(pop_aff), .groups = "drop")
    message("  population: ", vintage, " ", st$state, " done")
  }
  if (!length(out)) return(data.frame(tid = character(0), ZCTA = character(0), pop_aff = numeric(0)))
  bind_rows(out) %>% group_by(tid, ZCTA) %>% summarise(pop_aff = sum(pop_aff), .groups = "drop")
}
