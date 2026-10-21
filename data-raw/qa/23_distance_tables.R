# Run from the package root: Rscript data-raw/qa/23_distance_tables.R
# Needs the built datasets (zcta_centroids, survey_*), the saved plan results from
# 21b (centroid comparison with the geometric centroid) and 46 (centerline
# offsets). Computes, with the package's own distance code, the distance-exposure
# tables and writes the distance section into
# and the distance section into data-raw/known_issues.md between marker comments.
# Slow: the 50 km nationwide query takes several minutes.
suppressMessages({devtools::load_all(quiet = TRUE); library(dplyr); library(sf)})
source("data-raw/qa/helpers.R"); options(width = 170); sf_use_s2(FALSE)
f0 <- function(x, d = 1) formatC(x, format = "f", digits = d, big.mark = ",")
pc <- function(x, d = 1) paste0(f0(100 * x, d), "%")
tt <- .tracks(); ex <- .exposure(); cen <- .centroids()
yr <- as.integer(substr(tt$tornado_id, 1, 4)); vint <- .vintage_of(yr)
region <- .distance_region(tt)
make_poly <- function(i, crs) .path_polygon(tt[i, ], tt$wid_yd[i], tt$len_mi[i], tt$track_type[i], crs = crs)
key <- function(id, z) paste(id, z)
ov_key <- key(ex$tornado_id, ex$ZCTA)
no_zcta <- setdiff(tt$tornado_id, ex$tornado_id)
# ---- nationwide query by radius (the call a user would make with a very wide request) --
rad <- c(1, 5, 10, 25, 50)
reuse <- identical(Sys.getenv("REUSE"), "1") && file.exists(qa_out("distance_tables.rds"))   # REUSE=1 skips the slow queries and reuses the saved results
if (reuse) { old <- readRDS(qa_out("distance_tables.rds")); tab <- old$tab; geo <- old$geo } else {
tab <- lapply(rad, function(R) {
  t0 <- proc.time()[3]
  pr <- .distance_pairs(region, vint, cen, R, make_poly)
  secs <- proc.time()[3] - t0
  k <- key(tt$tornado_id[pr$i], cen$ZCTA[pr$j])
  data.frame(radius_km = R, rows = nrow(pr), tornadoes_without_a_row = nrow(tt) - length(unique(pr$i)), seconds = secs,
             overlap_pairs_within_radius = mean(ov_key %in% k), rows_not_in_overlap_set = mean(!k %in% ov_key),
             no_zcta_tornadoes_with_a_row = sum(unique(tt$tornado_id[pr$i]) %in% no_zcta))
})
tab <- bind_rows(tab)
}
print(tab, digits = 4)
# ---- geodesic check (same as the test): 48 states, AK, HI, PR -----------------------
if (!reuse) {
set.seed(3); idx <- c(which(region != "conus"), sample(which(region == "conus"), 60))
trs <- tt[idx, ]; vv <- vint[idx]
mp <- function(i, crs) .path_polygon(trs[i, ], trs$wid_yd[i], trs$len_mi[i], trs$track_type[i], crs = crs)
pr <- .distance_pairs(region[idx], vv, cen, 100, mp); pr <- pr[pr$dist_km > 1, ]
poly <- sf::st_segmentize(.path_polygon(trs[pr$i, ], trs$wid_yd[pr$i], trs$len_mi[pr$i], trs$track_type[pr$i]), 500)
pts <- sf::st_as_sf(cen[pr$j, ], coords = c("lon", "lat"), crs = 4269)
sf_use_s2(TRUE); g <- as.numeric(sf::st_distance(sf::st_transform(poly, 4326), sf::st_transform(pts, 4326), by_element = TRUE)) / 1000; sf_use_s2(FALSE)
geo <- data.frame(region = region[idx][pr$i], rel = abs(pr$dist_km - g) / g, absm = 1000 * abs(pr$dist_km - g)) %>%
  group_by(region) %>% summarise(pairs = n(), median_pct = 100 * median(rel), max_pct = 100 * max(rel), max_m = max(absm), .groups = "drop")
}
print(geo, digits = 3)
# ---- centroid facts --------------------------------------------------------------
cv <- cen %>% group_by(vintage) %>% summarise(zctas = n(), zero_resident = sum(centroid_type == "geometric"),
        pop_centroid_outside = sum(centroid_type == "population" & !centroid_in_zcta), outside_residents = sum(zcta_pop[centroid_type == "population" & !centroid_in_zcta]), residents = sum(zcta_pop), .groups = "drop")
plan <- readRDS(qa_out("zcta_centroids_plan_full.rds"))
cmp <- plan %>% filter(zcta_pop > 0) %>% group_by(vint) %>% summarise(median_km = median(pop_vs_geom_km), p90_km = quantile(pop_vs_geom_km, .9), p99_km = quantile(pop_vs_geom_km, .99), max_km = max(pop_vs_geom_km), .groups = "drop")
out_d <- plan %>% filter(zcta_pop > 0, !inside) %>% group_by(vint) %>% summarise(median_km = median(dist_out_km), p99_km = quantile(dist_out_km, .99), max_km = max(dist_out_km), over1 = sum(dist_out_km > 1), over5 = sum(dist_out_km > 5), .groups = "drop")
print(cv); print(cmp); print(out_d)
# ---- centerline offsets from the survey comparison ---------------------------------
Om <- readRDS(qa_out("survey_path_accuracy.rds"))$calibration   # paired tornadoes with a usable swath, line tracks (46_survey_path_accuracy.R)
cases <- readRDS(qa_out("dat_cases.rds")); cases <- cases[match(c("Mayfield", "Tuscaloosa-Birmingham", "Moore", "Rainsville"), cases$case), ]
off <- Om %>% group_by(cls) %>% summarise(n = n(), med = median(max_km), p90 = quantile(max_km, .9), .groups = "drop")
# ---- Joplin: which ZCTAs qualify under each definition -------------------------------
jid <- "2011_1105221634-01"
g1 <- function(...) { d <- suppressWarnings(suppressMessages(get_data(geo_list = "648", year_range = 2011, magnitude = 5, ...))); unique(d$ZCTA[d$tornado_id == jid]) }
defs <- list(`overlap` = g1(), `area_thresh = 0.05` = g1(area_thresh = 0.05), `area_thresh = 0.5` = g1(area_thresh = 0.5),
             `pop_thresh = 0.05` = g1(pop_thresh = 0.05), `pop_thresh = 0.25` = g1(pop_thresh = 0.25),
             `centroid_dist_km = 5` = g1(centroid_dist_km = 5), `centroid_dist_km = 10` = g1(centroid_dist_km = 10), `centroid_dist_km = 25` = g1(centroid_dist_km = 25))
zs <- sort(unique(unlist(defs)))
jd <- suppressWarnings(suppressMessages(get_data(geo_list = "648", year_range = 2011, magnitude = 5, centroid_dist_km = 25)))
jd <- jd[jd$tornado_id == jid, ]; jd <- jd[match(zs, jd$ZCTA), ]
jt <- data.frame(ZCTA = zs, dist_km = round(jd$dist_km, 1), area = signif(jd$area_prop_affected, 2), pop = signif(jd$pop_prop_affected, 2), stringsAsFactors = FALSE)
for (nm in names(defs)) jt[[nm]] <- ifelse(jt$ZCTA %in% defs[[nm]], "yes", "")
jt <- jt[order(jt$dist_km), ]
n_far <- sum(jt$dist_km > 10 & !jt$overlap == "yes")
jt <- jt[jt$dist_km <= 10, ]
print(jt)
# ---- text -----------------------------------------------------------------------------
md_table <- function(df) c(paste0("| ", paste(names(df), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
                           apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
rt <- tab %>% transmute(`Radius (km)` = radius_km, `Rows returned` = f0(rows, 0), `Tornadoes with no row` = f0(tornadoes_without_a_row, 0),
        `Share of overlap pairs within the radius` = pc(overlap_pairs_within_radius), `Share of rows outside the overlap set` = pc(rows_not_in_overlap_set),
        `No-ZCTA tornadoes that get a row` = paste0(no_zcta_tornadoes_with_a_row, " of ", length(no_zcta)), `Time (s)` = f0(seconds, 0))
jtab <- jt %>% rename(`Centroid distance (km)` = dist_km, `area_prop_affected` = area, `pop_prop_affected` = pop)
names(jtab)[1] <- "ZCTA"
body <- c(
"## Choosing an exposure definition", "",
"A call uses exactly one exposure definition, and every row returned is an exposed ZCTA under it.",
"",
"* **Overlap** (no threshold): the path polygon intersects the ZCTA. Any overlap counts, including very small ones.",
"* **Area share** (`area_thresh`): the share of the ZCTA's land area covered by the path. It depends on the size of the ZCTA as well as on how the path crossed it: the same path covers a large share of a small ZCTA and a small share of a large one.",
"* **Population share** (`pop_thresh`): the share of the ZCTA's residents inside the path. It follows where residents live, so a path through a dense town and the same area of farmland in one ZCTA have the same area share but very different population shares.",
"* **Centroid distance** (`centroid_dist_km`): the population-weighted centroid of the ZCTA lies within this many kilometers of the path. The path does not have to overlap the ZCTA.", "",
paste0("**Joplin (", jid, ")** as an example: which of the ZCTAs starting with 648 qualify, with the distance from the path to each ZCTA's population-weighted centroid. A blank means the ZCTA does not qualify; ZCTAs the path overlaps have a positive `area_prop_affected`. ZCTAs more than 10 km from the path are not listed (", n_far, " more qualify at `centroid_dist_km = 25`). The thresholds and radii in the table (0.05 and 0.5 of the land area, 0.05 and 0.25 of the residents, 5, 10 and 25 km) are example values chosen to show how the set of ZCTAs changes; none is a recommendation."),
"", md_table(jtab), "",
paste0("ZCTAs that qualify for this tornado, by definition: ", paste(paste0("`", names(defs), "`: ", lengths(defs)), collapse = "; "), ". The `area_thresh = 0.5` call returns an empty result with a message because no ZCTA reaches that share (the largest `area_prop_affected` for this tornado is ", f0(max(jt$area), 2), ")."), "",
"**Distance exposure in detail.**", "",
paste0("* Distance is measured from the path polygon to the **population-weighted centroid** of the ZCTA (block internal points weighted by block population, for the ZCTA boundary vintage of the tornado's year). It is 0 when the centroid is inside the path. Distances are computed on demand, with no upper limit on the radius. Alaska, Hawaii and Puerto Rico use a local projection for distances (the 48 states use EPSG:5070); against spherical geodesic distances the largest relative difference was ", paste0(sprintf("%s %s%% (%d pairs)", c(conus = "48 states", ak = "Alaska", hi = "Hawaii", pr = "Puerto Rico")[geo$region], f0(geo$max_pct, 1), geo$pairs), collapse = ", "), ", measured on all tornado paths in Alaska, Hawaii and Puerto Rico and a sample of 60 in the 48 states (the spherical reference itself differs from the ellipsoid by up to about 0.5%)."),
"* **The distance set is not a superset of the overlap set.** A large ZCTA crossed at its edge can have its centroid far from the path. Widening the radius only adds ZCTAs, but it takes a radius of tens of kilometers before most overlapped pairs are included. Over all 1996-2025 tornadoes (the radii of 1, 5, 10, 25 and 50 km are a span chosen to show the range; none is a recommendation):",
"", md_table(rt), "",
paste0("  (Timings are for a nationwide 1996-", max(yr), " call on one core of the machine that built the data; a request with a smaller `geo_list` or `year_range` is much faster, and slow calls print an estimate first.) An empty result is not an error: a tornado with no ZCTA centroid inside the radius returns no rows, and the package says so in a message."),
paste0("* **Choosing a radius.** Choose the radius to fit your question; no radius is recommended here. SPC gives only a start point, an end point and one width, and real paths curve, so the exposed location is uncertain. In the comparison with NWS surveys (section \"Path accuracy\"), the largest distance between the surveyed centerline and the modeled straight line has a median of ", paste0(f0(off$med[off$cls == "under 5 mi"], 2), " km for tornadoes under 5 miles, ", f0(off$med[off$cls == "5-20 mi"], 2), " km for 5 to 20 miles and ", f0(off$med[off$cls == "over 20 mi"], 2), " km for those over 20 miles"), ", and a 90th percentile of ", paste0(f0(off$p90[off$cls == "under 5 mi"], 2), ", ", f0(off$p90[off$cls == "5-20 mi"], 2), " and ", f0(off$p90[off$cls == "over 20 mi"], 2), " km"), ". The four case studies of long, strong tornadoes in that section are larger: the largest offset is ", paste(sprintf("%s %s km", cases$case, f0(cases$max_km, 1)), collapse = ", "), " (medians ", paste(sprintf("%s km", f0(cases$median_km, 1)), collapse = ", "), "), so they should not be read as typical. A radius smaller than these offsets cannot separate exposure from path-location error. The table above shows how much of the overlap set each radius captures."),
paste0("* **Zero-resident ZCTAs** use the geometric centroid (`centroid_type = \"geometric\"`, or a point on the polygon surface if the geometric centroid falls outside): ", paste(sprintf("%d in the %d vintage", cv$zero_resident, cv$vintage), collapse = ", "), ". A result containing any triggers a warning."),
paste0("* **Centroids outside their own ZCTA.** A population-weighted centroid can fall outside its polygon (a crescent-shaped or multi-part ZCTA): ", paste(sprintf("%d of %s in %d (%s of residents)", cv$pop_centroid_outside, f0(cv$zctas - cv$zero_resident, 0), cv$vintage, pc(cv$outside_residents / cv$residents, 2)), collapse = "; "), ". It is kept (it is the defined quantity) and flagged by `centroid_in_zcta`. How far outside: median ", paste(f0(out_d$median_km, 2), collapse = ", "), " km, 99th percentile ", paste(f0(out_d$p99_km, 1), collapse = ", "), " km (vintages 2000, 2010, 2020)."),
paste0("* **Population versus geometric centroid.** For ZCTAs with residents the two centroids differ by a median of ", paste(f0(cmp$median_km, 2), collapse = ", "), " km (90th percentile ", paste(f0(cmp$p90_km, 1), collapse = ", "), " km; maximum ", paste(f0(cmp$max_km, 0), collapse = ", "), " km) in the 2000, 2010 and 2020 vintages. The largest differences are large Alaska ZCTAs and ZCTAs with far-flung parts (for example Anchorage 99503) where residents are concentrated in one place."))
repl <- function(file, block, tag, before) {
  s <- paste0(paste(readLines(file, warn = FALSE), collapse = "\n"), "\n")
  st <- paste0("<!-- ", tag, ":start -->"); en <- paste0("<!-- ", tag, ":end -->")
  if (grepl(st, s, fixed = TRUE)) { a <- regexpr(st, s, fixed = TRUE); b <- regexpr(en, s, fixed = TRUE) + nchar(en)
    s <- paste0(substr(s, 1, a - 1), block, substr(s, b, nchar(s))) } else { a <- regexpr(before, s, fixed = TRUE); stopifnot(a > 0); s <- paste0(substr(s, 1, a - 1), block, "\n\n", substr(s, a, nchar(s))) }
  writeLines(sub("\n+$", "", s), file)
}
issues_block <- paste(c("<!-- distance:start -->", sub("^## ", "## ", body[1]), body[-1], "<!-- distance:end -->"), collapse = "\n")
issues_block <- sub("## Choosing an exposure definition", "## Exposure definitions and distance exposure (centroid_dist_km)", issues_block, fixed = TRUE)
repl("data-raw/known_issues.md", issues_block, "distance", "<!-- population:start -->")
# ---- the Moore comparison (SPC and survey, same tornado) -------------------------------
mid <- "2013_1305201356-01"
spc <- suppressMessages(get_data(geo_list = "731", year_range = 2013, magnitude = 5)); spc <- spc[spc$tornado_id == mid, ]
srv <- suppressMessages(get_survey_data(geo_list = "731", year_range = 2013, magnitude = 5)); srv <- srv[srv$tornado_id == mid, ]
mz <- sort(union(spc$ZCTA, srv$ZCTA))
mt <- data.frame(ZCTA = mz, a1 = spc$area_prop_affected[match(mz, spc$ZCTA)], a2 = srv$area_prop_affected[match(mz, srv$ZCTA)], p1 = spc$pop_affected[match(mz, spc$ZCTA)], p2 = srv$pop_affected[match(mz, srv$ZCTA)])
fm <- function(x, d) ifelse(is.na(x), "not exposed", formatC(x, format = "f", digits = d, big.mark = ","))
mtab <- data.frame(ZCTA = mt$ZCTA, `Area share, SPC path` = fm(mt$a1, 3), `Area share, survey swath` = fm(mt$a2, 3), `Residents in path, SPC` = fm(mt$p1, 0), `Residents in swath, survey` = fm(mt$p2, 0), check.names = FALSE)
moore_block <- paste(c("<!-- moore-comparison:start -->", "## Example: the Moore, Oklahoma tornado under SPC and under the survey", "",
  paste0("The 20 May 2013 Moore tornado (`", mid, "`, EF5) with the ZCTAs starting with 731, using `get_data()` and `get_survey_data()` with the overlap definition. The README shows the same call for the survey; the SPC path is a straight line of ", f0(tornado_tracks$len_mi[tornado_tracks$tornado_id == mid] * 1, 2), " miles, and the survey line is ", f0(tornado_tracks$len_mi[tornado_tracks$tornado_id == mid] * survey_matches$length_ratio[survey_matches$tornado_id == mid], 1), " miles (see \"Path accuracy\" for the end-point differences)."), "",
  md_table(mtab), "", "<!-- moore-comparison:end -->"), collapse = "\n")
repl("data-raw/known_issues.md", moore_block, "moore-comparison", "<!-- population:start -->")
# ---- ZCTA codes across vintages (the overlap ratio) -------------------------------------------
vo_all <- readRDS(qa_out("zcta_vintage_overlap.rds")); vo <- vo_all$summary
sh <- function(r, t) f0(100 * mean(r$ratio < t), 1)
vint_block <- paste(c("<!-- zcta-vintage-overlap:start -->", "## ZCTA codes can cover different areas in different vintages", "",
  paste0("Define the overlap ratio of a code as the area of the intersection of its two polygons divided by the area of their union (1 means the same area, 0 no overlap at all). The ratios 0.9, 0.5 and 0.1 are a span chosen to show how much codes change, not tested choices. A ratio below 0.9 means the two polygons differ by more than about 10% of their combined area, so it includes small boundary adjustments. Of the ", formatC(vo$codes_in_both[1], format = "d", big.mark = ","), " codes that are in both the 2010 and the 2020 boundary files, ", formatC(vo$below_0.9[1], format = "d", big.mark = ","), " (", sh(vo_all$r1020, 0.9), "%) have a ratio below 0.9, ", sh(vo_all$r1020, 0.5), "% below 0.5 and ", sh(vo_all$r1020, 0.1), "% below 0.1 (", vo$zero_overlap[1], " have no overlap at all). Between 2000 and 2010 the shares are ", sh(vo_all$r0010, 0.9), "% below 0.9 (", formatC(vo$below_0.9[2], format = "d", big.mark = ","), " of ", formatC(vo$codes_in_both[2], format = "d", big.mark = ","), " codes), ", sh(vo_all$r0010, 0.5), "% below 0.5 and ", sh(vo_all$r0010, 0.1), "% below 0.1. Among the codes that have at least one exposure row, the 2010 to 2020 share below 0.9 is ", f0(100 * vo$share_exposure_below_0.9[1], 1), "%. So the same code in 2010 and in 2020 may not be the same place; compare ZCTA-level results across vintages with care."), "",
  "<!-- zcta-vintage-overlap:end -->"), collapse = "\n")
repl("data-raw/known_issues.md", vint_block, "zcta-vintage-overlap", "<!-- zcta2000-gap:start -->")
saveRDS(list(tab = tab, geo = geo, cv = cv, cmp = cmp, out_d = out_d, off = off, jt = jt), qa_out("distance_tables.rds"))
cat("wrote data-raw/known_issues.md\n")
