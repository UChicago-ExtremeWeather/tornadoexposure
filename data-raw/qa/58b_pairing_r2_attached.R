# Run from the package root after 58_pairing_study.R:  Rscript data-raw/qa/58b_pairing_r2_attached.R     Saves data-raw/qa/out/pairing_r2_attached.rds
# The survey lines that rule R2 of 58_pairing_study.R attaches to an already paired tornado: their one-sided distance, the SPC length, and whether each is usable on its own.
# Study of pairing rules between SPC tornadoes of 2007 to 2025 and NWS survey lines, on a fresh full-resolution fetch of the Damage Assessment Toolkit. Nothing here changes a shipped dataset or the published pairing.
# Rules (no distance cut-off in any of them):
#   R0  the published rule: 21 index-aligned points, mean distance, mutual closest, one survey line per tornado, candidates dated within one day
#   R1  each survey line goes to its nearest SPC tornado by the one-sided distance (mean distance of the line's own 21 points to the SPC line; for an SPC point track the distance from the point to the line); several lines per tornado
#   R2  R0, and every survey line that R0 leaves unpaired is attached to its one-sided nearest tornado when that tornado is already paired
#   R3  as R0, with candidates chosen by timestamp (the DAT stormdate within T hours of the SPC start time in UTC) instead of the one-day window; T = 1, 3 and 6 hours
#   R4  survey lines linked through event_id: a numeric DAT event_id equal to the NCEI event id of an event assigned to an SPC tornado in data-raw/qa/54b
# The swath of a tornado is the union of the polygons selected for each of its lines with the published filter (rated EF0 to EF5, at least 90% of the polygon within the SPC width plus 500 m of the centerline);
# each line is usable on its own as in the published rule (its swath lies within 200 m of at least 50% of its length), and the swath of a tornado is the union of the swaths of its usable lines; the tornado is usable when it has at least one usable line. These filter values are the published ones, not new.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220, tigris_use_cache = TRUE)
source("data-raw/qa/helpers.R"); source("data-raw/survey/pairing_functions.R"); lg <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S "), ...); cat(m, "\n"); cat(m, "\n", file = qa_out("58.log"), append = TRUE) }
for (f in list.files("data", pattern = "\\.rda$", full.names = TRUE)) load(f); R <- list()
dt <- function(x) as.POSIXct(as.numeric(x) / 1000, origin = "1970-01-01", tz = "UTC")
Lf <- readRDS(qa_out("dat_full_layer1.rds")); Pf <- readRDS(qa_out("dat_full_layer2.rds")); Lf$stormdate <- as.numeric(Lf$stormdate); Pf$stormdate <- as.numeric(Pf$stormdate); Lf$length <- as.numeric(Lf$length); Lf$sd <- dt(Lf$stormdate); Pf$sd <- dt(Pf$stormdate)
Lf <- Lf[!is.na(Lf$sd) & Lf$sd >= as.POSIXct("2007-01-01", tz = "UTC") & Lf$sd < as.POSIXct("2026-01-01", tz = "UTC"), ]; Pf <- Pf[!is.na(Pf$sd) & Pf$sd >= as.POSIXct("2007-01-01", tz = "UTC") & Pf$sd < as.POSIXct("2026-01-02", tz = "UTC"), ]
Lf <- Lf[!st_is_empty(Lf), ]; Pf <- Pf[!st_is_empty(Pf), ]; lg("fresh lines ", nrow(Lf), "; polygons ", nrow(Pf)); R$fresh <- c(lines = nrow(Lf), polygons = nrow(Pf))
Du <- merge_copies(Lf); yr <- as.integer(substr(tornado_tracks$tornado_id, 1, 4)); Tt <- tornado_tracks[yr >= 2007, ]; Tt$date <- as.Date(Tt$date); tt <- st_drop_geometry(Tt)
sp <- spc_paths(Tt); sv <- survey_paths(Du); sw <- swath_setup(Du, sv, Pf); lg("distinct lines ", nrow(Du), "; SPC tornadoes ", nrow(Tt))
pr <- candidate_distances(Du, Tt, sp, sv, 1); lg("candidate pairs ", nrow(pr))
pdist <- function(px, py, ax, ay, bx, by) { dx <- bx - ax; dy <- by - ay; L2 <- dx^2 + dy^2; t <- pmax(0, pmin(1, ((px - ax) * dx + (py - ay) * dy) / ifelse(L2 > 0, L2, 1))); sqrt((px - (ax + t * dx))^2 + (py - (ay + t * dy))^2) }   # px, py may be matrices (one row per pair); a zero-length segment gives t = 0
d1 <- numeric(nrow(pr)); isl <- sp$is_line[pr$k]
for (ch in split(seq_len(nrow(pr)), ceiling(seq_len(nrow(pr)) / 50000))) { i <- pr$i[ch]; k <- pr$k[ch]; ns <- n_samples
  d1[ch] <- rowMeans(pdist(sv$Sx[i, , drop = FALSE], sv$Sy[i, , drop = FALSE], sp$s5[k, 1], sp$s5[k, 2], sp$e5[k, 1], sp$e5[k, 2])) / 1000 }
pr$d1 <- ifelse(isl, d1, pr$dist_km)   # point tracks: the distance from the point to the survey line (as in the published pairing)
R0 <- mutual_closest(pr)[, c("i", "k")]; lg("R0 pairs: ", nrow(R0))
best1 <- pr %>% group_by(i) %>% slice_min(d1, n = 1, with_ties = FALSE) %>% ungroup(); R1 <- best1[, c("i", "k")]
un <- setdiff(seq_len(nrow(Du)), R0$i); R2 <- rbind(R0, best1[best1$i %in% un & best1$k %in% R0$k, c("i", "k")])
raw <- read.csv(qa_spc_csv(), stringsAsFactors = FALSE); raw <- raw[raw$sg == 1 & raw$yr >= 2007, ]; raw$id <- paste(raw$yr, raw$om, sep = "_"); spc_utc <- as.POSIXct(paste(raw$date, raw$time), tz = "UTC")[match(Tt$tornado_id, raw$id)] + 6 * 3600
pr$dh <- abs(as.numeric(difftime(Du$sd[pr$i], spc_utc[pr$k], units = "hours")))
rankrule <- function(p) { p <- p %>% group_by(i) %>% mutate(rs = rank(dist_km, ties.method = "first")) %>% ungroup() %>% group_by(k) %>% mutate(rt = rank(dist_km, ties.method = "first")) %>% ungroup(); p[p$rs == 1 & p$rt == 1, c("i", "k")] }

# ---- survey lines that R2 attaches to an already paired tornado: distance, SPC length, and whether the line is usable on its own --------------------------------------
memo <- new.env(); len_i <- as.numeric(st_length(sv$L5)); sw_pair <- function(i, k) { key <- paste(i, k); if (!is.null(memo[[key]])) return(memo[[key]]); s <- swath_of(sw, i, k, Tt$wid_yd); memo[[key]] <- s; s }
att <- R2[!paste(R2$i, R2$k) %in% paste(R0$i, R0$k), ]; att$d1_km <- best1$d1[match(att$i, best1$i)]; att$spc_len_km <- pmax(tt$len_mi[att$k], 0.1) * 1.609344; att$farther_than_spc_length <- att$d1_km > att$spc_len_km
att$usable_line <- vapply(seq_len(nrow(att)), function(r) { s <- sw_pair(att$i[r], att$k[r]); !is.na(s$cover) && s$cover >= 0.5 && !is.null(s$geom) }, NA)
att$year <- as.integer(format(Du$date[att$i], "%Y")); att$ef <- Du$efscale[att$i]; att$r0_line_of_tornado_usable <- vapply(att$k, function(k) { i0 <- R0$i[R0$k == k]; s <- sw_pair(i0, k); !is.na(s$cover) && s$cover >= 0.5 && !is.null(s$geom) }, NA)
R <- list(); R$attached <- nrow(att); R$attached_cross <- table(farther_than_spc_length = att$farther_than_spc_length, usable_line = att$usable_line); R$attached_usable_by_distance <- att %>% filter(usable_line) %>% summarise(n = n(), farther = sum(farther_than_spc_length), within = sum(!farther_than_spc_length), d1_median = median(d1_km), d1_max = max(d1_km), d1_over_10km = sum(d1_km > 10))
R$attached_usable_examples <- head(att[att$usable_line, c("i", "k", "d1_km", "spc_len_km", "farther_than_spc_length", "year", "ef", "r0_line_of_tornado_usable")] %>% mutate(objectid = Du$objectid[i], tornado_id = tt$tornado_id[k]) %>% select(objectid, tornado_id, d1_km, spc_len_km, farther_than_spc_length, year, ef, r0_line_of_tornado_usable), 30)
R$attached_d1_quantiles <- quantile(att$d1_km, c(.1, .25, .5, .75, .9)); saveRDS(list(R = R, att = att), qa_out("pairing_r2_attached.rds")); for (n in names(R)) { cat("\n##", n, "\n"); print(R[[n]]) }
