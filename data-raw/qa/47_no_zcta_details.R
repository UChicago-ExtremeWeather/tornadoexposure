# Run from the package root after 08_no_zcta_tornadoes.R:  caffeinate -i Rscript data-raw/qa/47_no_zcta_details.R   (progress: data-raw/qa/out/47.log)
# The tornadoes whose path polygon overlaps no ZCTA of their Census boundary year (no rows in tornado_exposure): categories, counts, a sample, the size of the
# uncovered area around each path, evidence about the 2000 file, a map, and the section "Tornadoes without a ZCTA" of data-raw/known_issues.md.
# Writes data-raw/no_zcta_categories.csv (tornado_id, category; read by the README), data-raw/qa/out/no_zcta_summary.rds and ~/tornadoexposure-no-zcta-map.png.
#   over water                          the path polygon does not touch state land in the Census cartographic boundary file of the states (2020, cb, 1:500,000)
#   over land, no ZCTA nearby           it does touch state land, and more than 50% of the land within 3 km of the path is not covered by any ZCTA of the boundary year
#   on land, mostly covered             it touches state land, and at most 50% of the land within 3 km of the path is not covered
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220, tigris_use_cache = TRUE, timeout = 600)
source("data-raw/qa/helpers.R"); source("R/path_polygon.R")
log <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S"), " ", paste0(...)); cat(m, "\n"); cat(m, "\n", file = qa_out("47.log"), append = TRUE) }
load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda")
no <- read.csv(qa_out("no_zcta.csv"), stringsAsFactors = FALSE); stopifnot(nrow(no) == sum(!tornado_tracks$tornado_id %in% tornado_exposure$tornado_id))
no$category <- c("offshore/water" = "over water", "on land, uncovered gap" = "over land, no ZCTA nearby", "on land, mostly covered" = "on land, mostly covered")[no$cat]
no$boundary_year <- ifelse(no$yr < 2010, 2000L, ifelse(no$yr < 2020, 2010L, 2020L))
write.csv(no[, c("tornado_id", "category")], "data-raw/no_zcta_categories.csv", row.names = FALSE)
f0 <- function(x) format(x, big.mark = ",", trim = TRUE); pc <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
md_table <- function(d) paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(d)), collapse = "|"), "|"), apply(d, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))), collapse = "\n")
cats <- c("over water", "over land, no ZCTA nearby", "on land, mostly covered")
tab_by <- function(v, lab) { t <- as.data.frame.matrix(table(factor(no[[v]]), factor(no$category, cats))); t$Total <- rowSums(t); t <- cbind(setNames(data.frame(rownames(t)), lab), t); t[order(-t$Total), ] }
by_year <- tab_by("boundary_year", "Census boundary year"); by_type <- tab_by("track_type", "Track type")
st <- tab_by("st", "State"); top10 <- st$State[1:10]
by_state <- rbind(st[1:10, ], data.frame(State = paste0("all other (", nrow(st) - 10, " states and territories)"), t(colSums(st[-(1:10), -1])), check.names = FALSE)); names(by_state)[1] <- "State"
# ---- the uncovered area around each path (cached) ----------------------------------------------------------------------------------------------------------
hf <- qa_out("no_zcta_holes.rds")
if (file.exists(hf)) holes <- readRDS(hf) else {
  log("loading ZCTA layers")
  Z <- setNames(lapply(c(2000, 2010, 2020), function(v) st_make_valid(st_simplify(st_transform(tigris::zctas(year = v, progress_bar = FALSE), 5070), dTolerance = 100))), c(2000, 2010, 2020))
  tr <- tornado_tracks[match(no$tornado_id, tornado_tracks$tornado_id), ]; poly <- .path_polygon(tr, tr$wid_yd, tr$len_mi, tr$track_type)
  holes <- data.frame(tornado_id = no$tornado_id, hole_km2 = NA_real_, reaches_window = NA)
  for (i in seq_len(nrow(no))) { w <- st_as_sfc(st_bbox(st_buffer(poly[i], 15000)), crs = 5070); z <- Z[[as.character(no$boundary_year[i])]]; zw <- st_geometry(z[lengths(st_intersects(z, w)) > 0, ])
    U <- if (length(zw)) st_union(st_intersection(zw, w)) else st_sfc(st_polygon(), crs = 5070); h <- st_difference(w, U); h <- st_cast(st_sfc(st_make_valid(h)), "POLYGON")
    hit <- h[lengths(st_intersects(h, poly[i])) > 0]; if (!length(hit)) hit <- h[which.min(as.numeric(st_distance(h, poly[i])))]
    holes$hole_km2[i] <- as.numeric(sum(st_area(hit))) / 1e6; holes$reaches_window[i] <- any(lengths(st_intersects(st_boundary(w), hit)) > 0)
    if (i %% 50 == 0) log("holes: ", i, " of ", nrow(no)) }
  saveRDS(holes, hf) }
no <- left_join(no, holes, by = "tornado_id"); two_sqmi <- 2 * 2.589988
hole_tab <- no %>% group_by(`Census boundary year` = boundary_year) %>% summarise(Tornadoes = n(), `Uncovered area around the path over 2 square miles` = f0(sum(hole_km2 > two_sqmi, na.rm = TRUE)), `Share` = pc(mean(hole_km2 > two_sqmi, na.rm = TRUE)), `Median uncovered area (square miles)` = sprintf("%.1f", median(hole_km2, na.rm = TRUE) / 2.589988), .groups = "drop")
# ---- evidence about the 2000 file: polygon area against land area ---------------------------------------------------------------------------------------------
area_tab <- bind_rows(lapply(c(2000, 2010, 2020), function(v) { z <- tigris::zctas(year = v, progress_bar = FALSE); sfx <- substr(v, 3, 4); al <- sum(as.numeric(z[[paste0("ALAND", sfx)]]), na.rm = TRUE)
  pa <- sum(as.numeric(st_area(st_transform(st_make_valid(z), 5070)))); data.frame(`Census boundary year` = v, `ZCTA polygon area (million km2)` = sprintf("%.2f", pa / 1e12), `Land area ALAND (million km2)` = sprintf("%.2f", al / 1e12), `Polygon area divided by land area` = sprintf("%.3f", pa / al), check.names = FALSE) }))
other <- no %>% group_by(`Census boundary year` = boundary_year) %>% summarise(Tornadoes = n(), `Overlap a ZCTA of another boundary year` = sum(hit_other), Share = pc(mean(hit_other)), .groups = "drop")
# ---- the 86 on land, mostly covered: a sample of 20 ----------------------------------------------------------------------------------------------------------------
mc <- no[no$category == "on land, mostly covered", ]; set.seed(20); sm20 <- mc[sample(nrow(mc), 20), ]
sample_tab <- sm20 %>% transmute(Tornado = tornado_id, State = st, `Track type` = track_type, `Length (mi)` = len, `Width (yd)` = wid, `Distance to nearest ZCTA (m)` = round(near_km * 1000), `Land within 3 km not covered` = pc(gap_share, 0), `Uncovered area around the path (square miles)` = sprintf("%.2f", hole_km2 / 2.589988), `Overlaps a ZCTA of another boundary year` = ifelse(hit_other, "yes", "no"))
mcs <- mc %>% summarise(n = n(), point = sum(track_type != "line"), within_100m = sum(near_km <= 0.1), within_500m = sum(near_km <= 0.5), median_near_m = median(near_km) * 1000, hit_other = sum(hit_other), median_hole = median(hole_km2) / 2.589988, small_hole = sum(hole_km2 <= two_sqmi, na.rm = TRUE), median_gap = median(gap_share, na.rm = TRUE))
# ---- map ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
suppressMessages(library(ggplot2)); stt <- tigris::states(cb = TRUE, year = 2020, progress_bar = FALSE); no$cat_f <- factor(no$category, cats)
p <- ggplot() + geom_sf(data = stt, fill = "grey95", color = "grey60", linewidth = 0.2) + geom_point(data = no, aes(slon, slat, color = cat_f), size = 0.9, alpha = 0.8) + scale_color_manual(values = c("#1f78b4", "#d95f02", "#1b9e77"), name = "Category") +
  coord_sf(xlim = c(-125, -66), ylim = c(24, 50), crs = 4269) + labs(title = paste0(nrow(no), " tornadoes that overlap no ZCTA: start points by category"), subtitle = sprintf("The map shows the 48 states; %d start points lie in Alaska, Hawaii, Puerto Rico or the Virgin Islands (not shown).", sum(no$slon < -125 | no$slon > -66 | no$slat < 24 | no$slat > 50))) + theme_minimal(base_size = 9) + theme(legend.position = "bottom")
ggsave(path.expand("~/tornadoexposure-no-zcta-map.png"), p, width = 10, height = 6.5, dpi = 130)
# ---- text ---------------------------------------------------------------------------------------------------------------------------------------------------------------------
n <- nrow(no); nt <- nrow(tornado_tracks); cc <- table(factor(no$category, cats)); line_ct <- table(no$track_type)
txt <- paste(c("<!-- no-zcta:start -->", "## Tornadoes without a ZCTA", "",
  paste0(f0(n), " of ", f0(nt), " tornadoes (", pc(n / nt, 2), ") have a path polygon that overlaps no ZCTA of their Census boundary year, so they have no rows in `tornado_exposure`. They stay in `tornado_tracks`, and their property loss is not assigned to any ZCTA. They fall in three categories, defined by rules:"), "",
  paste0("* **Over water** (", f0(cc[[1]]), "): the path polygon does not touch state land in the Census cartographic boundary file of the states (2020, 1:500,000)."),
  paste0("* **Over land, no ZCTA nearby** (", f0(cc[[2]]), "): the path polygon touches state land, and more than 50% of the land within 3 km of the path is not covered by any ZCTA of the tornado's boundary year (median share of that land not covered: ", pc(median(no$gap_share[no$category == cats[2]], na.rm = TRUE), 0), "). The 3 km and 50% are values chosen to describe the cases, not tested choices."),
  paste0("* **On land, mostly covered** (", f0(cc[[3]]), "): the path polygon touches state land, and at most 50% of the land within 3 km of the path is not covered (median share not covered: ", pc(median(no$gap_share[no$category == cats[3]], na.rm = TRUE), 0), ")."), "",
  paste0("**By Census boundary year** (", paste(paste0(by_year[[1]], ": ", by_year$Total), collapse = ", "), ") **and track type** (", paste(paste0(f0(line_ct), " ", names(line_ct)), collapse = ", "), "):"), "", md_table(by_year), "", md_table(by_type), "",
  "**By state** (start point, top 10 of the states and territories):", "", md_table(by_state), "",
  "**Why there is no ZCTA.** The Census Bureau says that \"Uninhabited areas (land and water areas) over two square miles are potentially left unassigned from 2020 ZCTA coverage\" (https://www.census.gov/programs-surveys/geography/guidance/geo-areas/zctas.html). For the tornadoes of the 2020 boundary year, the connected area around the path that no ZCTA covers (measured in a window of 15 km around the path, so it can be larger) is shown below; the statement was checked for the 2020 file only, and the same numbers are given for the other boundary years without any claim about them.", "", md_table(hole_tab), "",
  paste0("**The 2000 file leaves out large water bodies.** The total area of the ZCTA polygons divided by the total land area was ", area_tab$`Polygon area divided by land area`[1], " in the 2000 file, against ", area_tab$`Polygon area divided by land area`[2], " in 2010 and ", area_tab$`Polygon area divided by land area`[3], " in 2020, and ", f0(other$`Overlap a ZCTA of another boundary year`[1]), " of the ", f0(other$Tornadoes[1]), " tornadoes without a ZCTA in the 2000 boundary year (", other$Share[1], ") overlap a ZCTA of the 2010 or 2020 file:"), "", md_table(area_tab), "", md_table(other), "",
  paste0("**On land, mostly covered: a sample of 20 of the ", f0(mcs$n), ".** Of all ", f0(mcs$n), ", ", f0(mcs$point), " are point tracks, ", f0(mcs$within_100m), " lie within 100 m of a ZCTA and ", f0(mcs$within_500m), " within 500 m (median ", sprintf("%.0f", mcs$median_near_m), " m), ", f0(mcs$hit_other), " overlap a ZCTA of another boundary year, and the median uncovered area around the path is ", sprintf("%.2f", mcs$median_hole), " square miles (", f0(mcs$small_hole), " of them below 2 square miles). What is going on: these are mostly short or point paths (narrow polygons) that lie a short distance from the edge of a ZCTA, next to an unassigned area, and most land nearby is covered, so the polygon falls just outside the ZCTA edge; the ZCTA is close but the path polygon does not reach it. The same path overlaps a ZCTA of another boundary year in most cases, so the gap depends on the boundary file. The sample (random, seed 20):"), "", md_table(sample_tab), "<!-- no-zcta:end -->"), collapse = "\n")
p0 <- "data-raw/known_issues.md"; s <- paste0(paste(readLines(p0, warn = FALSE), collapse = "\n"), "\n"); a <- regexpr("## Tornadoes without a ZCTA", s, fixed = TRUE); b <- regexpr("## ZCTA vintages", s, fixed = TRUE)
if (grepl("<!-- no-zcta:start -->", s, fixed = TRUE)) { a <- regexpr("<!-- no-zcta:start -->", s, fixed = TRUE); b <- regexpr("<!-- no-zcta:end -->", s, fixed = TRUE) + nchar("<!-- no-zcta:end -->"); s <- paste0(substr(s, 1, a - 1), txt, substr(s, b, nchar(s))) } else { stopifnot(a > 0, b > a); s <- paste0(substr(s, 1, a - 1), txt, "\n\n", substr(s, b, nchar(s))) }
writeLines(sub("\n+$", "", s), p0)
saveRDS(list(n = n, cats = cc, by_year = by_year, by_type = by_type, by_state = by_state, hole_tab = hole_tab, area_tab = area_tab, other = other, sample = sample_tab, mc = mcs), qa_out("no_zcta_summary.rds"))
log("done 47"); print(cc); print(by_year); print(by_type); print(by_state); print(hole_tab); print(area_tab); print(other); print(mcs); print(sample_tab)
