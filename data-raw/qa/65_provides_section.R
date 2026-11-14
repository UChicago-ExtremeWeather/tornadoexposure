# Run from the package root after a rebuild:  Rscript data-raw/qa/65_provides_section.R
# Writes the section "What the package provides" of data-raw/known_issues.md (between <!-- provides:start --> and <!-- provides:end -->): every dataset with its rows, columns and file size, from the files in data/.
suppressMessages(library(sf)); for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f)
f0 <- function(x) formatC(x, format = "d", big.mark = ","); mb <- function(f) sprintf("%.2f MB", file.size(file.path("data", paste0(f, ".rda"))) / 1e6)
what <- c(spc_records = "SPC, every tornado record from 1996 on, every column and every row (all `sg`), as SPC gives them",
  tornado_tracks = "SPC, one row per tornado (whole-track record): a line from the raw start to the raw end point, or a point at the start for a tornado with no usable end point; SPC's raw coordinates, length and width; loss as given and in dollars",
  tornado_exposure = "one row per tornado and ZCTA that the SPC line crosses or a linked NWS polygon covers land in: line length and share, distances (`boundary_dist_km`, `centroid_dist_km`), ZCTA areas and population, and the DAT columns (area and residents by rating, damage point counts)",
  dat_exposure_tract = "NWS columns only, one row per tornado and census tract that a linked NWS polygon covers land in: land-only area share and residents by rating, damage point counts",
  dat_exposure_blockgroup = "as `dat_exposure_tract`, for census block groups",
  zcta_centroids = "Census, one population-weighted centroid per ZCTA and boundary year, with the ZCTA's population, polygon area and land area",
  dat_points = "NWS Damage Assessment Toolkit, every damage point, all fields, unmodified",
  dat_lines = "NWS Damage Assessment Toolkit, every damage line (centerline of a surveyed track), all fields, unmodified",
  dat_polygons = "NWS Damage Assessment Toolkit, every damage polygon, all fields, unmodified",
  tornado_dat_link = "one row per DAT line linked to an SPC tornado, with every number that describes the link",
  dat_polygon_line_link = "one row per DAT polygon and line dated within a day of each other: distance and the share of the line inside the polygon")
rows <- vapply(names(what), function(n) { x <- get(n); paste0("| `", n, "` | ", what[[n]], " | ", f0(nrow(x)), " | ", ncol(x) - inherits(x, "sf"), if (inherits(x, "sf")) " + geometry" else "", " | ", mb(n), " |") }, "")
tot <- sum(file.size(list.files("data", pattern = "\\.rda$", full.names = TRUE))) / 1e6
txt <- c("<!-- provides:start -->", "## What the package provides", "", "| Dataset | Contents | Rows | Columns | File size (xz) |", "|---|---|---|---|---|", rows, "",
  sprintf("The files in `data/` add up to %.2f MB. Census inputs (ZCTA boundaries, block populations and shapes, water polygons) are read when the data are built and are not shipped; maps and the boundary distance download the full TIGER/Line files (sizes in `?get_data` and `?map_exposure`).", tot), "<!-- provides:end -->")
kl <- readLines("data-raw/known_issues.md"); a <- grep("<!-- provides:start -->", kl, fixed = TRUE); b <- grep("<!-- provides:end -->", kl, fixed = TRUE)
kl <- if (length(a) && length(b)) c(kl[seq_len(a - 1)], txt, kl[-seq_len(b)]) else append(kl, c(txt, ""), after = grep("^## What is and is not done", kl)[1] - 2)
writeLines(kl, "data-raw/known_issues.md"); cat(txt, sep = "\n")
