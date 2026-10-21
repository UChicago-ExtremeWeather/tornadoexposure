# Run from the package root: Rscript data-raw/qa/31_test_incremental_update.R
# Test of data-raw/update_data.R: delete the most recent year from a COPY of the stored data, re-add it with the
# incremental update, and compare with the full stored data. Also tries the failure checks. The stored data in data/
# and data-raw/ are not touched (everything happens in a temporary directory).
suppressMessages({library(dplyr); library(sf)})
load("data/tornado_exposure.rda"); load("data/tornado_tracks.rda")
ship_e <- tornado_exposure; ship_t <- tornado_tracks   # the full stored data, for the comparison
last <- max(tornado_exposure$year)
tmp <- "data-raw/qa/out/incr_test"; unlink(tmp, recursive = TRUE); dir.create(file.path(tmp, "data"), recursive = TRUE); dir.create(file.path(tmp, "prov"))   # git-ignored; kept so the log can be read
ex_old <- tornado_exposure[tornado_exposure$year < last, ]; tr_old <- tornado_tracks[as.integer(substr(tornado_tracks$tornado_id, 1, 4)) < last, ]
cat("copy without", last, ": ", nrow(tr_old), "tornadoes,", nrow(ex_old), "rows (full data:", nrow(tornado_tracks), ",", nrow(tornado_exposure), ")\n")
tornado_exposure <- ex_old; tornado_tracks <- tr_old
save(tornado_exposure, file = file.path(tmp, "data", "tornado_exposure.rda"), compress = "xz"); save(tornado_tracks, file = file.path(tmp, "data", "tornado_tracks.rda"), compress = "xz")
file.copy(c("data-raw/provenance.txt", "data-raw/access_date.txt"), file.path(tmp, "prov"))
py <- read.csv("data-raw/provenance_years.csv"); py$last_year <- last - 1; write.csv(py, file.path(tmp, "prov", "provenance_years.csv"), row.names = FALSE)
checks_only <- identical(Sys.getenv("CHECKS_ONLY"), "1")   # CHECKS_ONLY=1 skips the update and the comparison and runs only the failure checks
if (!checks_only) {
t0 <- Sys.time()
status <- system2("Rscript", "data-raw/update_data.R", env = c(paste0("UPDATE_DATA_DIR=", file.path(tmp, "data")), paste0("UPDATE_PROV_DIR=", file.path(tmp, "prov")), paste0("UPDATE_LATEST_YEAR=", last)), stdout = file.path(tmp, "update.log"), stderr = file.path(tmp, "update.log"))
cat("update_data.R exit status:", status, "; time", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "minutes\n")
cat(grep("^(Stored|SPC file|Stored years|Tornadoes after|Loss unit|Track type|Checks passed|Population|Wrote|Nothing|The new rows|  -)", readLines(file.path(tmp, "update.log")), value = TRUE), sep = "\n")
if (status != 0) { cat("update_data.R failed; last lines of its log:\n"); cat(tail(readLines(file.path(tmp, "update.log")), 15), sep = "\n"); stop("update failed") }
n <- new.env(); load(file.path(tmp, "data", "tornado_exposure.rda"), envir = n); load(file.path(tmp, "data", "tornado_tracks.rda"), envir = n)
cat("\n== comparison with the stored data ==\n")
ne <- n$tornado_exposure; nt <- n$tornado_tracks
cat("tornado_exposure: rows", nrow(ne), "vs stored", nrow(ship_e), "; identical():", identical(ne, ship_e), "\n")
num <- names(ship_e)[sapply(ship_e, is.numeric)]
dif <- sapply(num, function(v) max(abs(ne[[v]] - ship_e[[v]]), na.rm = TRUE)); cat("largest absolute difference by numeric column:\n"); print(signif(dif, 3))
cat("rows differing in any column:", sum(!vapply(seq_len(nrow(ne)), function(i) identical(ne[i, ], ship_e[i, ]), logical(1))), "of", nrow(ne), "\n")
cat("rows of", last, "only: identical():", identical(ne[ne$year == last, ], ship_e[ship_e$year == last, ]), "; rows before", last, "unchanged:", identical(ne[ne$year < last, ], ship_e[ship_e$year < last, ]), "\n")
cat("tornado_tracks: rows", nrow(nt), "vs stored", nrow(ship_t), "; attributes identical():", identical(sf::st_drop_geometry(nt), sf::st_drop_geometry(ship_t)), "; geometry identical():", identical(sf::st_geometry(nt), sf::st_geometry(ship_t)), "; whole object identical():", identical(nt, ship_t), "\n")
cat("same tornado_id order:", identical(nt$tornado_id, ship_t$tornado_id), "\n")
cat("\nRESULT: tornado_exposure identical in EVERY column (including pop_affected, zcta_pop, pop_prop_affected):", identical(ne, ship_e), "; tornado_tracks identical:", identical(nt, ship_t), "\n")
cat("\nprovenance_years.csv after the update:\n"); print(read.csv(file.path(tmp, "prov", "provenance_years.csv")))
cat("\nprovenance.txt section:\n"); p <- readLines(file.path(tmp, "prov", "provenance.txt")); i <- which(p == "## SPC release by year"); cat(p[i:(i + 4)], sep = "\n")
}
# ---- failure checks ------------------------------------------------------------------------
cat("\n== checks that must stop the update (run on the new", last, "rows) ==\n")
source("data-raw/pipeline_functions.R")
new_t <- ship_t[as.integer(substr(ship_t$tornado_id, 1, 4)) == last, ]; new_e <- ship_e[ship_e$year == last, ]
old_t <- tr_old; old_e <- ex_old
try_check <- function(label, t = new_t, e = new_e) { r <- tryCatch({ check_new_rows(t, e, old_t, old_e, last); "passed" }, error = function(err) conditionMessage(err)); cat("\n>", label, "\n", r, "\n") }
try_check("unchanged rows (should pass)")
k <- !is.na(new_t$property_loss_tornado_total)
t2 <- new_t; t2$property_loss_tornado_total[k] <- t2$property_loss_tornado_total[k] / 1e6; try_check("loss in millions instead of dollars", t2)
t2 <- new_t; t2$property_loss_tornado_total[!k][1] <- 0; try_check("unknown loss stored as 0 instead of NA", t2)
e2 <- new_e; e2$property_loss_allocated[!is.na(e2$property_loss_allocated)][1] <- NA; try_check("allocated loss NA where the total is known", e = e2)
e2 <- new_e; e2$property_loss_allocated[!is.na(e2$property_loss_allocated)][1] <- 1; try_check("allocated loss that does not sum back to the total", e = e2)
t2 <- new_t; t2$loss_raw_unit[1] <- "millions"; try_check("loss unit millions in a new year", t2)
t2 <- new_t; t2$tornado_id[1] <- "abc"; try_check("tornado_id with the wrong pattern", t2)
t2 <- new_t; t2$wid_yd[1] <- 25000; try_check("width of 25,000 yards", t2)
t2 <- new_t; t2$len_mi[1] <- 900; try_check("length of 900 miles", t2)
t2 <- new_t; g <- sf::st_geometry(t2); g[[1]] <- sf::st_point(c(10, 10)); sf::st_geometry(t2) <- sf::st_sfc(g, crs = 4326); try_check("coordinates outside the United States", t2)
t2 <- new_t; t2$total_injury <- as.character(t2$total_injury); try_check("a column with a different type", t2)
e2 <- new_e; names(e2)[3] <- "yr"; try_check("a different column name", e = e2)
t2 <- new_t; t2$tornado_id[1] <- old_t$tornado_id[1]; try_check("a tornado_id that is already stored", t2)
cat("\nwhen no year is new:\n"); r <- system2("Rscript", "data-raw/update_data.R", env = c(paste0("UPDATE_DATA_DIR=", "data"), paste0("UPDATE_PROV_DIR=", "data-raw"), paste0("UPDATE_LATEST_YEAR=", last)), stdout = TRUE, stderr = TRUE); cat(tail(r, 3), sep = "\n")
cat("\nthe stored data and provenance files were not changed by this test\n")
