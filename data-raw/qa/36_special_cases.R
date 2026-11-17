# Run from the package root: Rscript data-raw/qa/36_special_cases.R
# Writes three notes into data-raw/known_issues.md (every number computed from the data): ratings by year (unknown ratings
# by year: none in 1996 to 2006, some from 2007), line tracks whose reported length is 0 although their coordinates are far apart, and tornadoes that
# start outside the 48 states.
suppressMessages({devtools::load_all(quiet = TRUE); library(dplyr); library(sf)})
source("data-raw/qa/helpers.R")
tt <- st_drop_geometry(tornado_tracks); tt$year <- as.integer(substr(tt$tornado_id, 1, 4))
f0 <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = ",")
md_table <- function(df) c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
                           apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
# ---- (a) ratings by year -----------------------------------------------------------------------------
by_year <- tt %>% group_by(year) %>% summarise(EF0 = sum(magnitude == 0, na.rm = TRUE), `EF1 to EF5` = sum(magnitude >= 1, na.rm = TRUE), unknown = sum(is.na(magnitude)), .groups = "drop") %>% mutate(`share unknown` = paste0(f0(100 * unknown / (EF0 + `EF1 to EF5` + unknown), 1), "%"))
by_year$n <- by_year$EF0 + by_year$`EF1 to EF5` + by_year$unknown; u <- setNames(by_year$unknown, by_year$year); yq <- 100 * by_year$unknown / by_year$n; late <- by_year$year >= 2016
stopifnot(all(u[by_year$year <= 2006] == 0), u[["2007"]] > 0, all(u[by_year$year %in% 2008:2015] == 0), all(u[late] > 0))   # the sentence below states exactly this pattern
txt_a <- c(paste0("Unknown ratings (`magnitude` is `NA`): ", f0(sum(by_year$unknown)), " of ", f0(nrow(tt)), " tornadoes. There are none in 1996 to 2006, ", u[["2007"]], " in 2007 (", f0(yq[by_year$year == 2007], 1), "% of that year), none in 2008 to 2015, and some in every year from 2016 to 2025: ", f0(min(u[late])), " to ", f0(max(u[late])), " a year (", f0(min(yq[late]), 1), "% to ", f0(max(yq[late]), 1), "% of the tornadoes of the year). Counts of EF0 tornadoes are comparable across years only if unknown ratings are included, and this matters from 2016 on. Tornadoes per year by rating:"), "", md_table(transform(by_year, n = NULL, year = as.character(year), EF0 = f0(EF0), `EF1 to EF5` = f0(`EF1 to EF5`), unknown = f0(unknown), check.names = FALSE)))
# ---- (b) line tracks with len_mi = 0 -----------------------------------------------------------------------
ln <- tornado_tracks[tornado_tracks$track_type == "line" & tornado_tracks$len_mi == 0, ]
chord <- as.numeric(st_length(st_transform(ln, 5070))) / 1609.344
txt_b <- c(paste0(nrow(ln), " line tracks have a reported length of 0 although their start and end coordinates are far apart (", paste0("`", ln$tornado_id, "`: ", f0(chord, 1), " miles", collapse = "; "), "). These look like SPC data errors. `len_ratio` is `NA` for them, and the package draws them from the coordinates."))
# ---- (c) tornadoes that start outside the 48 states -------------------------------------------------------------
xy <- do.call(rbind, lapply(st_geometry(tornado_tracks), function(g) { m <- unclass(g); if (!is.matrix(m)) m <- matrix(m, ncol = 2); m[1, ] }))
region <- ifelse(xy[, 2] >= 50.5, "Alaska", ifelse(xy[, 2] < 23 & xy[, 1] < -150, "Hawaii", ifelse(xy[, 2] < 20 & xy[, 1] > -65.1, "US Virgin Islands",
                 ifelse(xy[, 2] < 20 & xy[, 1] > -70, "Puerto Rico", "48 states"))))   # by the start coordinates
out <- sort(table(region[region != "48 states"]), decreasing = TRUE)
vi <- tornado_tracks$tornado_id[region == "US Virgin Islands"]
txt_c <- c(paste0(sum(out), " tornadoes start outside the 48 states, by their start coordinates (", paste(f0(as.numeric(out)), names(out), collapse = ", "), "). The Virgin Islands ZCTAs are not in the data (the block data cover the 50 states, DC and Puerto Rico), so the ",
                  length(vi), " Virgin Islands tornadoes ", if (all(!vi %in% tornado_exposure$tornado_id[tornado_exposure$spc_exposed])) "have no exposure rows" else paste(sum(vi %in% tornado_exposure$tornado_id[tornado_exposure$spc_exposed]), "have exposure rows"), "; they stay in `tornado_tracks`."))
block <- paste(c("<!-- special-cases:start -->", "## Ratings by year, special tracks and territories", "", txt_a, "", "### Line tracks with a length of 0", "", txt_b, "", "### Tornadoes that start outside the 48 states", "", txt_c, "<!-- special-cases:end -->"), collapse = "\n")
p <- "data-raw/known_issues.md"; s <- paste0(paste(readLines(p, warn = FALSE), collapse = "\n"), "\n"); st_ <- "<!-- special-cases:start -->"; en <- "<!-- special-cases:end -->"
if (grepl(st_, s, fixed = TRUE)) { a <- regexpr(st_, s, fixed = TRUE); b <- regexpr(en, s, fixed = TRUE) + nchar(en); s <- paste0(substr(s, 1, a - 1), block, substr(s, b, nchar(s))) } else s <- paste0(s, "\n", block, "\n")
writeLines(sub("\n+$", "", s), p)
cat(txt_b, "\n", txt_c, "\n"); cat("wrote data-raw/known_issues.md\n")
