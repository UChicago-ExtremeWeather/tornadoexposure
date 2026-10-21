# README.md is generated from data-raw/readme/README.Rmd by this script (edit the Rmd, not the README): real code,
# real output, and the maps in figures/. Printed numbers use 3 decimals (an output hook in the Rmd).
# Run from the package root: Rscript data-raw/readme/build_readme.R   (needs an internet connection for the maps)
# The README is short on purpose. The tables and long explanations (Path accuracy, the radius capture table, the comparison
# of the exposure definitions, the vintage note) are in data-raw/known_issues.md, which the QA scripts write:
# data-raw/qa/19, 20, 23, 36, 38d and 46.
suppressMessages(library(knitr)); knitr::opts_knit$set(root.dir = normalizePath("."))
knitr::knit("data-raw/readme/README.Rmd", output = "README.md", quiet = TRUE)
# tidy the knitr output: no leading blank lines, single blank lines, plain ```r fences
x <- readLines("README.md"); x <- sub("^``` r$", "```r", x)
x <- x[!(x == "" & c("", head(x, -1)) == "")]; x <- x[cumsum(x != "") > 0]
x <- x[!(x == "" & c("", head(x, -1)) %in% grep("^#", x, value = TRUE))]   # no blank line right after a heading
writeLines(x, "README.md")
cat("README.md written:", length(x), "lines, longest", max(nchar(x)), "characters\n")
