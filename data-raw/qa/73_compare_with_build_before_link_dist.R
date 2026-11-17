# Run from the package root:  Rscript data-raw/qa/73_compare_with_build_before_link_dist.R <folder with the .rda files of the build to compare with>
# Compares every table of data/ with the same table of an earlier build: identical() for each table that is not expected to differ, and for each column of the tables
# that gained the column dat_link_dist_km. Reports every difference.
a <- commandArgs(TRUE)[1]; stopifnot(!is.na(a), dir.exists(a))
old <- new.env(); cur <- new.env()
for (f in list.files(a, pattern = "[.]rda$", full.names = TRUE)) load(f, envir = old)
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f, envir = cur)
stopifnot(setequal(ls(old), ls(cur)))
for (t in sort(ls(cur))) {
  o <- get(t, old); n <- get(t, cur)
  if (identical(o, n)) { cat(sprintf("%-26s identical\n", t)); next }
  added <- setdiff(names(n), names(o)); removed <- setdiff(names(o), names(n)); common <- intersect(names(o), names(n))
  same <- vapply(common, function(k) identical(o[[k]], n[[k]]), TRUE)
  cat(sprintf("%-26s columns added: %s; removed: %s; common columns identical: %d of %d; rows %d -> %d; order of the common columns kept: %s\n", t, paste(added, collapse = ", "), paste(removed, collapse = ", "),
              sum(same), length(common), nrow(o), nrow(n), identical(common, names(n)[names(n) %in% names(o)])))
  if (any(!same)) cat("  DIFFER:", paste(common[!same], collapse = ", "), "\n")
}
