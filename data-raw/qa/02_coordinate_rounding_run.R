# Run from the package root: Rscript data-raw/qa/02_coordinate_rounding_run.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf)}); options(tigris_use_cache=TRUE, timeout=600)
source("R/path_polygon.R")
load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda")
set.seed(2026)
yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4))
era <- ifelse(yr <= 2006, "1996-2006", "2007+")
n_per <- 1000; reps <- 20
idx <- unlist(lapply(split(seq_len(nrow(tornado_tracks)), era), function(i) sample(i, n_per)))
S <- tornado_tracks[idx, ]; S$yr <- yr[idx]; S$era <- era[idx]
cat("sample:", nrow(S), "\n"); print(table(S$era, S$track_type))
h <- ifelse(S$era == "1996-2006", 0.005, 0.00005)
vint <- function(y) ifelse(y < 2010, 2000, ifelse(y < 2020, 2010, 2020))
S$vint <- vint(S$yr)
load_z <- function(v) { z <- tigris::zctas(year=v, progress_bar=FALSE); sfx <- substr(v,3,4)
  z <- z[, c(paste0("ZCTA5CE", sfx), paste0("ALAND", sfx))]; names(z) <- c("ZCTA","ALAND","geometry"); z$ALAND <- as.numeric(z$ALAND); st_make_valid(st_transform(z, 5070)) }
Z <- lapply(c(2000,2010,2020), load_z); names(Z) <- c(2000,2010,2020)
cat("ZCTA layers loaded\n")
geoms <- lapply(sf::st_geometry(S), function(x) if (is.matrix(x)) unclass(x) else matrix(unclass(x), nrow = 1))
build <- function(perturb) {
  g <- lapply(seq_along(geoms), function(i) {
    m <- geoms[[i]]
    if (perturb) {
      # points: start only (end unknown); lines: both ends, each coordinate independently
      m <- m + matrix(runif(length(m), -h[i], h[i]), nrow(m))
    }
    if (nrow(m) == 1) sf::st_point(m[1, ]) else sf::st_linestring(m)
  })
  sf::st_sfc(g, crs = 4326)
}
run_rep <- function(perturb) {
  g <- build(perturb)
  poly <- .path_polygon(g, S$wid_yd, S$len_mi, S$track_type)
  ps <- sf::st_sf(tornado_id = S$tornado_id, geometry = poly)
  out <- lapply(c(2000, 2010, 2020), function(v) {
    sub <- ps[S$vint == v, ]
    x <- suppressWarnings(sf::st_intersection(sub, Z[[as.character(v)]]))
    x <- sf::st_collection_extract(x, "POLYGON")
    x$a <- as.numeric(sf::st_area(x))
    sf::st_drop_geometry(x) |> group_by(tornado_id, ZCTA, ALAND) |> summarise(a = sum(a), .groups = "drop")
  })
  bind_rows(out) |> mutate(area_prop = pmin(a / ALAND, 1)) |> select(tornado_id, ZCTA, area_prop)
}
t0 <- Sys.time()
base <- run_rep(FALSE); cat("baseline done", format(Sys.time() - t0), "\n")
chk <- inner_join(base, tornado_exposure[, c("tornado_id","ZCTA","area_prop_affected")], by = c("tornado_id","ZCTA"))
cat("baseline vs data: rows", nrow(base), "matched", nrow(chk), "max abs diff", max(abs(chk$area_prop - chk$area_prop_affected)), " exposure rows for sampled tornadoes:", sum(tornado_exposure$tornado_id %in% S$tornado_id), "\n")
res <- list(`0` = base)
for (r in seq_len(reps)) { res[[as.character(r)]] <- run_rep(TRUE); cat("rep", r, "done", format(Sys.time() - t0), "\n") }
saveRDS(list(S = st_drop_geometry(S), res = res, h = h), qa_out("d2_results.rds"))
cat("DONE\n")
