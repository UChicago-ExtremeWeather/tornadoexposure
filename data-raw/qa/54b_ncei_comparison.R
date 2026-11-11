# Run from the package root after 54a_ncei_download.R:  caffeinate -i Rscript data-raw/qa/54b_ncei_comparison.R   (progress: data-raw/qa/out/54b.log)
# Compares every SPC tornado of 2007 to 2025 with the NCEI Storm Events tornado records. Matching method (stated here, not tuned): each NCEI tornado event (a county segment) is assigned
# to the SPC tornado, dated within one day, whose path (straight start-to-end line; the start point for point tracks) lies closest to BOTH of the event's end points (the larger of the two
# distances is minimized, in EPSG:5070); the event is assigned only if that distance is at most `tol` km. tol = 2 km is the value used for the comparison; 1, 2 and 5 km are reported for the counts.
# Nothing is merged into the SPC values: NCEI values are summed or maximized over the segments of one tornado only to compare them. Saves data-raw/qa/out/ncei_comparison.rds.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220)
source("data-raw/qa/helpers.R"); lg <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S "), ...); cat(m, "\n"); cat(m, "\n", file = qa_out("54b.log"), append = TRUE) }
nf <- readRDS(qa_out("ncei_files.rds")); R <- list(files = nf); tol_main <- 2
rd <- function(f) read.csv(gzfile(file.path(qa_cache("ncei_full"), f)), stringsAsFactors = FALSE, colClasses = c(BEGIN_TIME = "character", END_TIME = "character", EVENT_NARRATIVE = "character", EPISODE_NARRATIVE = "character"))
N <- bind_rows(lapply(nf$file[nf$kind == "details"], function(f) { x <- rd(f); x[x$EVENT_TYPE == "Tornado", ] })); lg("NCEI tornado events: ", nrow(N))
N$tz_h <- as.numeric(sub(".*?(-?[0-9]+)$", "\\1", N$CZ_TIMEZONE)); N$bt <- as.POSIXct(N$BEGIN_DATE_TIME, format = "%d-%b-%y %H:%M:%S", tz = "UTC"); N$bt[N$bt > as.POSIXct("2026-12-31", tz = "UTC")] <- N$bt[N$bt > as.POSIXct("2026-12-31", tz = "UTC")] - 100 * 365.25 * 86400
N$utc <- N$bt - N$tz_h * 3600; N$date <- as.Date(N$bt)
N$ef <- suppressWarnings(as.integer(sub("^E?F", "", N$TOR_F_SCALE))); N$ef[N$TOR_F_SCALE %in% c("EFU", "FU", "")] <- NA
dmg <- function(s) { u <- c(K = 1e3, M = 1e6, B = 1e9); v <- suppressWarnings(as.numeric(sub("[KMB]$", "", s))); m <- sub("^[0-9.]*", "", s); v * ifelse(m %in% names(u), u[m], ifelse(s == "", NA, 1)) }
N$dmg <- dmg(N$DAMAGE_PROPERTY); N$inj <- N$INJURIES_DIRECT + N$INJURIES_INDIRECT; N$dth <- N$DEATHS_DIRECT + N$DEATHS_INDIRECT
N$ok_c <- is.finite(N$BEGIN_LAT) & is.finite(N$BEGIN_LON) & N$BEGIN_LAT != 0; R$ncei_events <- nrow(N); R$ncei_events_no_coords <- sum(!N$ok_c)
# ---- SPC ----------------------------------------------------------------------------------------------------------------
raw <- read.csv(qa_spc_csv(), stringsAsFactors = FALSE); raw <- raw[raw$yr >= 2007, ]; S <- raw[raw$sg == 1, ]; S$tornado_id <- paste(S$yr, S$om, sep = "_"); S$utc <- as.POSIXct(paste(S$date, S$time), tz = "UTC") + 6 * 3600; S$d <- as.Date(S$date)
S$line <- !(is.na(S$elat) | S$elat == 0 | S$elon == 0) & !(S$slat == S$elat & S$slon == S$elon)
pj <- function(lon, lat) { ok <- is.finite(lon) & is.finite(lat); o <- matrix(NA_real_, length(lon), 2); if (any(ok)) o[ok, ] <- st_coordinates(st_transform(st_sfc(lapply(which(ok), function(i) st_point(c(lon[i], lat[i]))), crs = 4326), 5070)); o }
s5 <- pj(S$slon, S$slat); e5 <- pj(ifelse(S$line, S$elon, S$slon), ifelse(S$line, S$elat, S$slat)); nb5 <- pj(N$BEGIN_LON, N$BEGIN_LAT); ne5 <- pj(ifelse(is.finite(N$END_LON) & N$END_LON != 0, N$END_LON, N$BEGIN_LON), ifelse(is.finite(N$END_LAT) & N$END_LAT != 0, N$END_LAT, N$BEGIN_LAT))
pdist <- function(px, py, ax, ay, bx, by) { dx <- bx - ax; dy <- by - ay; L2 <- dx^2 + dy^2; t <- ifelse(L2 > 0, pmax(0, pmin(1, ((px - ax) * dx + (py - ay) * dy) / L2)), 0); sqrt((px - (ax + t * dx))^2 + (py - (ay + t * dy))^2) }
# candidate pairs: dated within one day
sd <- data.frame(k = seq_len(nrow(S)), d = S$d); nd <- data.frame(n = which(N$ok_c), d = N$date[N$ok_c])
cand <- bind_rows(lapply(-1:1, function(o) merge(transform(nd, d = d + o), sd, by = "d")[, c("n", "k")]))
cand$dist <- pmax(pdist(nb5[cand$n, 1], nb5[cand$n, 2], s5[cand$k, 1], s5[cand$k, 2], e5[cand$k, 1], e5[cand$k, 2]), pdist(ne5[cand$n, 1], ne5[cand$n, 2], s5[cand$k, 1], s5[cand$k, 2], e5[cand$k, 1], e5[cand$k, 2])) / 1000
best <- cand %>% group_by(n) %>% slice_min(dist, n = 1, with_ties = FALSE) %>% ungroup(); lg("candidate pairs ", nrow(cand), "; best per event ", nrow(best))
R$tol_counts <- do.call(rbind, lapply(c(1, 2, 5), function(tl) { b <- best[best$dist <= tl, ]; data.frame(tol_km = tl, ncei_events_assigned = nrow(b), spc_tornadoes_with_ncei = length(unique(b$k)), spc_total = nrow(S), ncei_events_unassigned = sum(N$ok_c) - nrow(b)) }))
A <- best[best$dist <= tol_main, ]; N$k <- NA_integer_; N$k[A$n] <- A$k; N$dist_km <- NA_real_; N$dist_km[A$n] <- A$dist; N$tornado_id <- S$tornado_id[N$k]
R$unassigned_by_year <- table(N$YEAR[is.na(N$k)]); R$assigned_by_year <- table(N$YEAR[!is.na(N$k)]); R$spc_without_ncei_by_year <- table(S$yr[!S$tornado_id %in% N$tornado_id])
# ---- per tornado comparison ----------------------------------------------------------------------------------------------------------
G <- N[!is.na(N$k), ] %>% arrange(k, utc) %>% group_by(k) %>% summarise(n_events = n(), ncei_ef = if (all(is.na(ef))) NA_integer_ else max(ef, na.rm = TRUE), ncei_len = sum(TOR_LENGTH), ncei_wid = max(TOR_WIDTH), ncei_inj = sum(inj), ncei_dth = sum(dth),
  ncei_dmg = if (all(is.na(dmg))) NA_real_ else sum(dmg, na.rm = TRUE), blat = first(BEGIN_LAT), blon = first(BEGIN_LON), nelat = last(END_LAT), nelon = last(END_LON), n_states = n_distinct(STATE), first_utc = first(utc),
  wfo = first(WFO), event_ids = paste(EVENT_ID, collapse = ","), ncei_ef_min = if (all(is.na(ef))) NA_integer_ else min(ef, na.rm = TRUE), .groups = "drop")
C <- cbind(S[G$k, c("tornado_id", "yr", "date", "mag", "inj", "fat", "loss", "len", "wid", "slat", "slon", "elat", "elon", "ns", "utc", "st")], G[, -1]); names(C)[names(C) == "utc"] <- "spc_utc"
hav <- function(lat1, lon1, lat2, lon2) { r <- pi / 180; a <- sin((lat2 - lat1) * r / 2)^2 + cos(lat1 * r) * cos(lat2 * r) * sin((lon2 - lon1) * r / 2)^2; 12742 * asin(sqrt(a)) }
C$spc_mag <- ifelse(C$mag == -9, NA, C$mag); C$start_km <- hav(C$slat, C$slon, C$blat, C$blon); C$end_km <- ifelse(C$elat == 0, NA, hav(C$elat, C$elon, C$nelat, C$nelon))
C$loss_usd <- ifelse(C$yr < 2007, C$loss * 1e6, C$loss); C$time_h <- as.numeric(difftime(C$first_utc, C$spc_utc, units = "hours"))
agree <- function(d) data.frame(n = nrow(d), rating_equal = mean(d$spc_mag == d$ncei_ef | (is.na(d$spc_mag) & is.na(d$ncei_ef)), na.rm = TRUE) * 100, rating_equal_max_seg = mean(d$spc_mag == d$ncei_ef, na.rm = TRUE) * 100,
  length_within_0.1mi = mean(abs(d$len - d$ncei_len) <= 0.1 + 1e-9) * 100, length_within_10pct = mean(abs(d$len - d$ncei_len) <= 0.1 * pmax(d$len, 0.1)) * 100, width_equal = mean(d$wid == d$ncei_wid) * 100,
  start_within_0.1km = mean(d$start_km <= 0.1) * 100, end_within_0.1km = mean(d$end_km <= 0.1, na.rm = TRUE) * 100, injuries_equal = mean(d$inj == d$ncei_inj) * 100, deaths_equal = mean(d$fat == d$ncei_dth) * 100,
  damage_equal = mean(abs(d$loss_usd - d$ncei_dmg) <= 0.01 * pmax(abs(d$loss_usd), 1), na.rm = TRUE) * 100)
R$agree_all <- agree(C); R$agree_by_year <- bind_rows(lapply(split(C, C$yr), function(d) cbind(year = d$yr[1], agree(d)))); R$matched <- nrow(C); R$spc_total <- nrow(S)
C$rating_diff <- C$ncei_ef - C$spc_mag; R$rating_diff_table <- table(pmax(pmin(C$rating_diff, 2), -2), useNA = "ifany"); R$len_diff_quant <- quantile(C$len - C$ncei_len, c(0, .01, .05, .5, .95, .99, 1), na.rm = TRUE)
R$len_ratio_quant <- quantile(C$ncei_len / C$len, c(.01, .05, .5, .95, .99), na.rm = TRUE); R$start_km_quant <- quantile(C$start_km, c(.5, .9, .99, 1)); R$end_km_quant <- quantile(C$end_km, c(.5, .9, .99, 1), na.rm = TRUE)
R$time_h_quant <- quantile(C$time_h, c(.01, .05, .5, .95, .99), na.rm = TRUE); R$time_within_1h <- mean(abs(C$time_h) <= 1, na.rm = TRUE) * 100; R$time_same_minute <- mean(abs(C$time_h) < 1 / 60, na.rm = TRUE) * 100
# largest disagreements: score = rating difference (in steps) + length difference / 5 miles + start and end offsets / 5 km; reported with the components
C$score <- abs(ifelse(is.na(C$rating_diff), 0, C$rating_diff)) + abs(C$len - C$ncei_len) / 5 + C$start_km / 5 + ifelse(is.na(C$end_km), 0, C$end_km) / 5
top <- C[order(-C$score), c("tornado_id", "st", "spc_mag", "ncei_ef", "len", "ncei_len", "wid", "ncei_wid", "start_km", "end_km", "inj", "ncei_inj", "fat", "ncei_dth", "n_events", "event_ids", "score")]; R$top20 <- head(top, 20)
R$st_louis <- C[C$tornado_id == "2025_2505161339-01", ]; R$segments_per_tornado <- table(pmin(C$n_events, 6)); R$ns_vs_states <- table(C$ns, C$n_states)
# SPC segments (sg == 2) against NCEI events of the same tornado
seg <- raw[raw$sg == 2, ]; R$spc_segment_rows <- nrow(seg); R$spc_tornadoes_with_segments <- length(unique(paste(seg$yr, seg$om)))
# SPC segment max versus sg == 1 magnitude (item 5d), tornadoes of 2007 on; the om of the segment rows is the om of the whole-track row in the 2025 format
lg("segments in SPC: ", nrow(seg))
# revisions: NCEI file dates against the SPC release of 24 April 2026
R$file_dates <- nf[nf$kind == "details", c("year", "cdate")]; R$agree_by_file_date <- C %>% mutate(after = yr %in% nf$year[nf$kind == "details" & nf$cdate > "20260424"]) %>% group_by(after) %>% group_modify(~ agree(.x))
old <- list.files(qa_cache("ncei"), pattern = "details", full.names = TRUE); R$old_cache_files <- basename(old)
# narratives of surveyed tornadoes (paired with a usable swath in the published layer)
load("data/survey_matches.rda"); inc <- survey_matches$tornado_id[survey_matches$status == "included"]; Nn <- N[N$tornado_id %in% inc, ]
R$narr <- data.frame(events = nrow(Nn), narrative_nonempty = mean(nzchar(Nn$EVENT_NARRATIVE)) * 100, mentions_coordinates = mean(grepl("[0-9]{2}\\.[0-9]{3,}\\s*,\\s*-?[0-9]{2,3}\\.[0-9]{3,}", Nn$EVENT_NARRATIVE)) * 100, mentions_miles = mean(grepl("[0-9.]+\\s*(-)?\\s*mile", Nn$EVENT_NARRATIVE, ignore.case = TRUE)) * 100,
  mentions_ef = mean(grepl("EF-?[0-5]", Nn$EVENT_NARRATIVE)) * 100, mentions_upgrade = mean(grepl("upgrad|updated|revised|re-surveyed|resurvey", Nn$EVENT_NARRATIVE, ignore.case = TRUE)) * 100, mentions_nws_survey = mean(grepl("survey", Nn$EVENT_NARRATIVE, ignore.case = TRUE)) * 100)
R$st_louis_events <- N[N$YEAR == 2025 & as.Date(N$bt) == as.Date("2025-05-16") & N$BEGIN_LAT > 38.5 & N$BEGIN_LAT < 38.9 & N$BEGIN_LON > -90.5 & N$BEGIN_LON < -89.8, c("EVENT_ID", "STATE", "CZ_NAME", "BEGIN_TIME", "TOR_F_SCALE", "TOR_LENGTH", "TOR_WIDTH", "BEGIN_LAT", "BEGIN_LON", "END_LAT", "END_LON", "INJURIES_DIRECT", "DEATHS_DIRECT", "DAMAGE_PROPERTY", "tornado_id", "dist_km", "EVENT_NARRATIVE")]
saveRDS(list(R = R, C = C, N = N[, setdiff(names(N), c("EVENT_NARRATIVE", "EPISODE_NARRATIVE"))], S = S), qa_out("ncei_comparison.rds")); lg("done 54b")
for (nm in c("tol_counts", "agree_all", "rating_diff_table", "len_ratio_quant", "start_km_quant", "end_km_quant", "time_h_quant", "time_within_1h", "time_same_minute", "segments_per_tornado", "agree_by_file_date", "narr")) { cat("\n##", nm, "\n"); print(R[[nm]]) }
