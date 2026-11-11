# Run from the package root after 54b:  Rscript data-raw/qa/56_rating_check.R     Saves data-raw/qa/out/rating_check.rds
# (a) the raw SPC rows of the St. Louis event; (b) SPC rating against NCEI and the DAT lines for it; (c) SPC magnitude against the efscale of the paired survey line for all pairs of the published layer;
# (d) whole-track (sg == 1) magnitude against the maximum over its segment rows (sg == 2); (e) the current SPC file against the stored copy and the SPC change log.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220); source("data-raw/qa/helpers.R")
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f); R <- list()
raw <- read.csv(qa_spc_csv(), stringsAsFactors = FALSE)
R$a_rows <- raw[raw$date == "2025-05-16" & raw$slat > 38.4 & raw$slat < 39 & raw$slon > -90.6 & raw$slon < -89.7, ]
# (c) published pairs
sm <- survey_matches; P <- sm[sm$status != "no_pair", ]; L <- readRDS(qa_out("dat_lines_live.rds")); ef <- function(x) suppressWarnings(as.integer(sub("^EF", "", x)))
tt <- st_drop_geometry(tornado_tracks); P$spc <- tt$magnitude[match(P$tornado_id, tt$tornado_id)]; P$line_ef <- ef(L$efscale[match(P$survey_line_id, L$objectid)]); P$line_ef_txt <- L$efscale[match(P$survey_line_id, L$objectid)]
P$year <- as.integer(substr(P$tornado_id, 1, 4)); P$len_mi <- tt$len_mi[match(P$tornado_id, tt$tornado_id)]; P$track <- tt$track_type[match(P$tornado_id, tt$tornado_id)]
P$chord <- cut(P$len_mi, c(-Inf, 5, 20, Inf), labels = c("under 5 mi", "5-20 mi", "over 20 mi"))
cmp <- function(d) { d <- d[!is.na(d$spc) & !is.na(d$line_ef), ]; data.frame(n = nrow(d), equal = mean(d$spc == d$line_ef) * 100, spc_lower_by_1 = mean(d$line_ef - d$spc == 1) * 100, spc_lower_by_2_or_more = mean(d$line_ef - d$spc >= 2) * 100, spc_higher = mean(d$spc > d$line_ef) * 100) }
R$c_all <- cmp(P); R$c_table <- table(SPC = P$spc, line = P$line_ef_txt, useNA = "ifany"); R$c_by_year <- bind_rows(lapply(split(P, P$year), function(d) cbind(year = d$year[1], cmp(d)))); R$c_by_chord <- bind_rows(lapply(split(P, P$chord), function(d) cbind(chord = as.character(d$chord[1]), cmp(d))))
R$c_included_only <- cmp(P[P$status == "included", ]); R$c_unknown_spc <- sum(is.na(P$spc)); R$c_line_unrated <- sum(is.na(P$line_ef))
P$diff <- P$line_ef - P$spc; R$c_top20 <- head(P[!is.na(P$diff), ][order(-abs(P$diff[!is.na(P$diff)]), P$tornado_id[!is.na(P$diff)]), c("tornado_id", "spc", "line_ef_txt", "diff", "distance_km", "len_mi", "length_ratio", "same_state", "status")], 20)
R$c_stlouis <- P[P$tornado_id == "2025_2505161339-01", c("tornado_id", "spc", "line_ef_txt", "diff", "distance_km", "status")]
R$c_diff_ge2 <- sum(abs(P$diff) >= 2, na.rm = TRUE); R$c_diff_ge2_among_close <- cmp(P[P$distance_km <= pmax(P$len_mi, 0.1) * 1.609344 & P$same_state %in% TRUE, ])
# (d) segments
s <- raw[raw$yr >= 1996, ]; s$date <- as.Date(s$date); main <- s[s$sg == 1, ]; seg <- s[s$sg == 2, ]; R$d_segments <- nrow(seg)
pj <- function(lon, lat) st_coordinates(st_transform(st_sfc(lapply(seq_along(lon), function(i) st_point(c(lon[i], lat[i]))), crs = 4326), 5070))
mg <- main[main$slat != 0 & main$slon != 0, ]; ms <- pj(mg$slon, mg$slat); me <- pj(ifelse(mg$elat == 0, mg$slon, mg$elon), ifelse(mg$elat == 0, mg$slat, mg$elat)); ss <- pj(seg$slon, seg$slat); se <- pj(ifelse(seg$elat == 0, seg$slon, seg$elon), ifelse(seg$elat == 0, seg$slat, seg$elat))
pdist <- function(px, py, ax, ay, bx, by) { dx <- bx - ax; dy <- by - ay; L2 <- dx^2 + dy^2; t <- ifelse(L2 > 0, pmax(0, pmin(1, ((px - ax) * dx + (py - ay) * dy) / L2)), 0); sqrt((px - (ax + t * dx))^2 + (py - (ay + t * dy))^2) }
cand <- merge(data.frame(i = seq_len(nrow(seg)), date = seg$date), data.frame(k = seq_len(nrow(mg)), date = mg$date), by = "date"); cand$d <- pmax(pdist(ss[cand$i, 1], ss[cand$i, 2], ms[cand$k, 1], ms[cand$k, 2], me[cand$k, 1], me[cand$k, 2]), pdist(se[cand$i, 1], se[cand$i, 2], ms[cand$k, 1], ms[cand$k, 2], me[cand$k, 1], me[cand$k, 2])) / 1000
b <- cand %>% group_by(i) %>% slice_min(d, n = 1, with_ties = FALSE) %>% ungroup(); R$d_segment_link_km_quantiles <- quantile(b$d, c(.5, .9, .99, 1)); b <- b[b$d <= 2, ]; R$d_segments_linked <- nrow(b); R$d_segments_total <- nrow(seg)
seg$k <- NA_integer_; seg$k[b$i] <- b$k; g <- seg[!is.na(seg$k), ] %>% group_by(k) %>% summarise(seg_max = max(mag), seg_n = n(), .groups = "drop"); g$id <- paste(mg$yr[g$k], mg$om[g$k], sep = "_"); g$main_mag <- mg$mag[g$k]; g$state <- mg$st[g$k]; g$len <- mg$len[g$k]
R$d_tornadoes_with_segments <- nrow(g); R$d_table <- table(ifelse(g$main_mag == g$seg_max, "equal", ifelse(g$main_mag < g$seg_max, "whole-track lower than the maximum segment", "whole-track higher")))
R$d_lower <- g[g$main_mag < g$seg_max, ]; R$d_lower_by_era <- table(ifelse(as.integer(substr(g$id, 1, 4)) < 2007, "1996-2006", "2007+")[g$main_mag < g$seg_max]); R$d_top20 <- head(g[order(-(g$seg_max - g$main_mag), g$id), ], 20)
R$d_stored_choice_lower <- sum(g$main_mag < g$seg_max & g$id %in% tt$tornado_id)
# (e) the current SPC file
tf <- tempfile(); download.file("https://www.spc.noaa.gov/wcm/data/1950-2025_all_tornadoes.csv", tf, quiet = TRUE, mode = "wb"); R$e_md5_now <- unname(tools::md5sum(tf)); R$e_md5_stored <- read.csv("data-raw/provenance_years.csv")$md5
cl <- readLines("https://www.spc.noaa.gov/wcm/data/changelog.txt", warn = FALSE); R$e_changelog_top <- head(cl[nzchar(trimws(cl))], 6); saveRDS(R, qa_out("rating_check.rds"))
for (nm in setdiff(names(R), c("a_rows", "c_table"))) { cat("\n##", nm, "\n"); print(R[[nm]]) }
