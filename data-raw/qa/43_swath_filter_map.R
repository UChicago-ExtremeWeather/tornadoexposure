# Run from the package root after data-raw/survey/build_survey.R:  Rscript data-raw/qa/43_swath_filter_map.R [output.png] [tornado_id] [label]
# One real example of the swath filter: the Moore, Oklahoma tornado of 20 May 2013 (2013_1305201356-01). Draws the surveyed centerline, the corridor
# (the distance from the centerline equal to the SPC path width plus 500 m) and every damage polygon that crosses the centerline on the same date
# (within one day), colored by whether the filter keeps it or drops it and why: not rated EF0 to EF5, or under 90% of its area inside the corridor.
# The title gives the share of the centerline's length that lies within 200 m of the kept polygons. The file goes outside the repository.
suppressMessages({library(sf); library(dplyr); library(ggplot2)}); sf_use_s2(FALSE)
source("data-raw/qa/helpers.R")
args <- commandArgs(trailingOnly = TRUE); out <- if (length(args)) args[1] else path.expand("~/tornadoexposure-moore-swath-filter.png")
source("data-raw/survey/pairing_functions.R"); load("data/tornado_tracks.rda"); load("data/survey_matches.rda")
id <- if (length(args) >= 2) args[2] else "2013_1305201356-01"; label <- if (length(args) >= 3) args[3] else "Moore, Oklahoma, 20 May 2013"
ctx <- survey_context(); Du <- ctx$Du; Tt <- ctx$Tt; P <- ctx$P; dt <- dat_date
k <- match(id, Tt$tornado_id); i <- match(survey_matches$survey_line_id[survey_matches$tornado_id == id], as.integer(Du$objectid)); stopifnot(length(i) == 1, !is.na(i))
Dg <- Du; Pd <- dt(P$stormdate)
L <- st_transform(st_make_valid(st_geometry(Dg))[i], 5070); width_m <- Tt$wid_yd[k] * 0.9144; corridor <- st_buffer(L, width_m + 500)
Pg <- st_make_valid(st_geometry(P)); hit <- st_intersects(st_make_valid(st_geometry(Dg))[i], Pg)[[1]]; hit <- hit[abs(as.numeric(Pd[hit] - dt(Dg$stormdate[i]))) <= 1]
P5 <- st_transform(Pg[hit], 5070); inside <- vapply(seq_along(hit), function(z) as.numeric(st_area(st_intersection(P5[z], corridor))) / as.numeric(st_area(P5[z])), 0)
ef <- P$efscale[hit]; ok_ef <- paste0("EF", 0:5)
status <- ifelse(!ef %in% ok_ef, "dropped: no EF0 to EF5 rating", ifelse(inside < 0.9, "dropped: under 90% of its area inside the corridor", "kept"))
kept <- st_union(st_make_valid(P5[status == "kept"])); cover <- sum(as.numeric(st_length(st_intersection(L, st_buffer(kept, 200))))) / as.numeric(st_length(L))
df <- st_sf(status = status, rating = ifelse(is.na(ef) | ef == "", "none", ef), inside = round(100 * inside), geometry = st_geometry(P5))
cat("polygons crossing the centerline on that date:", nrow(df), "\n"); print(table(status)); print(table(df$rating, status)); cat("share of the centerline within 200 m of the kept polygons:", round(cover, 3), "\n")
spc <- st_transform(st_sfc(tornado_tracks$geometry[tornado_tracks$tornado_id == id][[1]], crs = 4326), 5070)
cols <- c(`kept` = "#1b9e77", `dropped: no EF0 to EF5 rating` = "#7570b3", `dropped: under 90% of its area inside the corridor` = "#d95f02")
p <- ggplot() + geom_sf(data = corridor, fill = "grey90", color = "grey50", linetype = "dashed") +
  geom_sf(data = df, aes(fill = status), color = "grey25", alpha = 0.55, linewidth = 0.2) +
  geom_sf(data = L, color = "black", linewidth = 0.9) + geom_sf(data = spc, color = "#1f78b4", linewidth = 0.8, linetype = "dotdash") +
  scale_fill_manual(values = cols, name = "Swath filter") +
  labs(title = paste0(label, " (", id, ")"),
       subtitle = sprintf("black: surveyed centerline; dashed outline: corridor (all points within the SPC width, %d yd, plus 500 m of the centerline); blue dash-dot: SPC straight path.\n%d polygons cross the centerline: %d kept, %d dropped. Share of the centerline within 200 m of the kept polygons: %.0f%%.",
                          Tt$wid_yd[k], nrow(df), sum(status == "kept"), sum(status != "kept"), 100 * cover)) +
  theme_minimal(base_size = 9) + theme(legend.position = "bottom", legend.direction = "vertical", plot.subtitle = element_text(size = 7))
ggsave(out, p, width = 9, height = 7, dpi = 130); cat("saved", out, "\n")
