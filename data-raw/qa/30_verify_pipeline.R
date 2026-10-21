# Run from the package root: Rscript data-raw/qa/30_verify_pipeline.R
# Verifies data-raw/pipeline_functions.R (shared by the full rebuild and the incremental update) against the stored
# data: processes EVERY year from the SPC file used for the build and compares tornado_tracks and the non-population
# columns of tornado_exposure. Nothing is written. Slow (the same work as a full rebuild without population).
suppressMessages(library(sf))
source("data-raw/pipeline_functions.R")
load("data/tornado_exposure.rda"); load("data/tornado_tracks.rda")
prov <- utils::read.csv("data-raw/provenance_years.csv")
dl <- spc_download(max(prov$last_year))
cat("SPC file md5:", dl$md5, "; at the build:", prov$md5[1], "; same file:", identical(dl$md5, prov$md5[1]), "\n")
raw <- read_csv(dl$file, show_col_types = FALSE)
b <- spc_build(spc_clean(raw, first_year:max(prov$last_year)))
pc <- c("pop_affected", "zcta_pop", "pop_prop_affected")
ex <- tornado_exposure[, setdiff(names(tornado_exposure), pc)]
cat("\ntornado_exposure (without population columns): rows", nrow(b$exposure), "vs", nrow(ex), "; identical():", identical(b$exposure, ex), "\n")
num <- names(ex)[sapply(ex, is.numeric)]; cat("largest absolute difference by numeric column:\n"); print(signif(sapply(num, function(v) max(abs(b$exposure[[v]] - ex[[v]]), na.rm = TRUE)), 3))
cat("tornado_tracks: rows", nrow(b$tracks), "vs", nrow(tornado_tracks), "; attributes identical():", identical(st_drop_geometry(b$tracks), st_drop_geometry(tornado_tracks)), "; geometry identical():", identical(st_geometry(b$tracks), st_geometry(tornado_tracks)), "; whole object identical():", identical(b$tracks, tornado_tracks), "\n")
