# Run from the package root after data-raw/survey/build_survey.R:  caffeinate -i Rscript data-raw/qa/45_survey_comparison.R   (progress: data-raw/qa/out/45.log)
# The survey layer compared with the modeled (SPC) paths, and four pairing rules compared with each other. Writes
# data-raw/survey/comparison_tables.md (put into known_issues.md by 46_survey_path_accuracy.R) and data-raw/qa/out/survey_comparison.rds.
#   Table of four rules: (1) the fixed 0.10-degree total with the 2-mile minimum and with the length and direction tests; (2) the same
#   without a minimum; (3) each end within the larger of 1 km and 25% of the chord, without a minimum; (4) mutual closest (the layer).
#   Agreement tables: for the paired tornadoes with a usable swath, which ZCTAs are exposed (overlap) and how large the shares are.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220, tigris_use_cache = TRUE, timeout = 600)
source("data-raw/qa/helpers.R"); source("data-raw/survey/pairing_functions.R")
log <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S"), " ", paste0(...)); cat(m, "\n"); cat(m, "\n", file = qa_out("45.log"), append = TRUE) }
for (f in c("tornado_tracks", "survey_matches", "survey_exposure", "tornado_exposure")) load(file.path("data", paste0(f, ".rda")))
ctx <- survey_context(); list2env(ctx, environment()); sm <- survey_matches
f0 <- function(x) format(x, big.mark = ",", trim = TRUE); pc <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
md_table <- function(d) paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(d)), collapse = "|"), "|"), apply(d, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))), collapse = "\n")
hav <- function(lon1, lat1, lon2, lat2) { r <- pi / 180; a <- sin((lat2 - lat1) * r / 2)^2 + cos(lat1 * r) * cos(lat2 * r) * sin((lon2 - lon1) * r / 2)^2; 2 * 6371.0088 * asin(pmin(1, sqrt(a))) }
brg <- function(lon1, lat1, lon2, lat2) { r <- pi / 180; (atan2(sin((lon2 - lon1) * r) * cos(lat2 * r), cos(lat1 * r) * sin(lat2 * r) - sin(lat1 * r) * cos(lat2 * r) * cos((lon2 - lon1) * r)) / r + 360) %% 360 }
# ---- candidate pairs with the end-point measures of the older rules ------------------------------------------------------------------------------------
pr <- candidate_distances(Du, Tt, sp, sv, 1); L <- sp$is_line[pr$k]; a <- cbind(Du$s_lon, Du$s_lat, Du$e_lon, Du$e_lat)[pr$i, , drop = FALSE]; b <- sp$tl[pr$k, , drop = FALSE]
d1 <- abs(b[, 1] - a[, 1]) + abs(b[, 2] - a[, 2]) + abs(b[, 3] - a[, 3]) + abs(b[, 4] - a[, 4]); d2 <- abs(b[, 1] - a[, 3]) + abs(b[, 2] - a[, 4]) + abs(b[, 3] - a[, 1]) + abs(b[, 4] - a[, 2])
rv <- d2 < d1; sl <- ifelse(rv, a[, 3], a[, 1]); sa <- ifelse(rv, a[, 4], a[, 2]); el <- ifelse(rv, a[, 1], a[, 3]); ea <- ifelse(rv, a[, 2], a[, 4])
pr$tot_deg <- pmin(d1, d2); pr$s_km <- hav(b[, 1], b[, 2], sl, sa); pr$e_km <- hav(b[, 3], b[, 4], el, ea); pr$endpoint_km <- pr$s_km + pr$e_km; pr$chord_h <- hav(b[, 1], b[, 2], b[, 3], b[, 4])
pr$len_ratio <- ifelse(Tt$len_mi[pr$k] > 0, Du$length[pr$i] / Tt$len_mi[pr$k], NA_real_); x <- abs(brg(b[, 1], b[, 2], b[, 3], b[, 4]) - brg(sl, sa, el, ea)); pr$bear <- pmin(x, 360 - x)
pr$guard <- L & !is.na(pr$len_ratio) & pr$len_ratio >= 0.7 & pr$len_ratio <= 1.4 & pr$bear <= 30
cache <- list()
usable_pair <- function(i, k) { key <- paste(i, k); if (is.null(cache[[key]])) cache[[key]] <<- swath_of(sw, i, k, Tt$wid_yd); cache[[key]] }
run_rule <- function(sat, score, minlen = 0) {
  s <- sat & L & Du$length[pr$i] >= minlen & pr$guard; d <- pr[s, ]; d$score <- d[[score]]
  Lb <- d %>% group_by(i) %>% summarise(k = k[which.min(score)], n_ok = n(), .groups = "drop")
  t <- Lb %>% group_by(k) %>% summarise(n_lines = n(), any_second = any(n_ok > 1), i1 = i[1], .groups = "drop") %>% mutate(amb = n_lines > 1 | any_second)
  t$usable <- vapply(seq_len(nrow(t)), function(r) is_usable(usable_pair(t$i1[r], t$k[r])), logical(1)); t }
log("rules 1 to 3")
r1 <- run_rule(pr$tot_deg <= 0.10, "tot_deg", 2); r2 <- run_rule(pr$tot_deg <= 0.10, "tot_deg", 0); r3 <- run_rule(pr$s_km <= pmax(1, .25 * pr$chord_h) & pr$e_km <= pmax(1, .25 * pr$chord_h), "endpoint_km", 0)
M <- mutual_closest(pr); r4 <- data.frame(k = M$k, i1 = M$i, amb = FALSE, usable = sm$status[match(Tt$tornado_id[M$k], sm$tornado_id)] == "included")
stopifnot(sum(r1$usable & !r1$amb) == 1838, sum(r4$usable) == sum(sm$status == "included"))
rules <- list(`Fixed total end-point difference of 0.10 degrees, survey lines of 2 miles or more, length and direction tests` = r1, `The same without a minimum length` = r2, `Each end within the larger of 1 km and 25% of the chord, no minimum length, length and direction tests` = r3, `Closest survey line in both directions (the survey layer), no tests, no minimum length` = r4)
# ---- area shares of the swath of any (line, tornado) pair; the layer's own rows are used for the layer's pairs --------------------------------------------------
load_z <- function(v) { z <- tigris::zctas(year = v, progress_bar = FALSE); sfx <- substr(v, 3, 4); z <- z[, c(paste0("ZCTA5CE", sfx), paste0("ALAND", sfx))]; names(z) <- c("ZCTA", "ALAND", "geometry"); z$ALAND <- as.numeric(z$ALAND); st_make_valid(st_transform(z, 5070)) }
Z <- NULL
area_rows <- function(i, k) { if (is.null(Z)) Z <<- setNames(lapply(c(2000, 2010, 2020), load_z), c(2000, 2010, 2020))
  s <- usable_pair(i, k); v <- as.character(ifelse(as.integer(format(Tt$date[k], "%Y")) < 2010, 2000, ifelse(as.integer(format(Tt$date[k], "%Y")) < 2020, 2010, 2020)))
  x <- suppressWarnings(st_intersection(st_sf(id = 1, geometry = st_sfc(s$geom[[1]], crs = 5070)), Z[[v]])); if (!nrow(x)) return(data.frame(ZCTA = character(), area_prop = numeric()))
  x <- st_collection_extract(x, "POLYGON"); x$a <- as.numeric(st_area(x)); g <- st_drop_geometry(x) %>% group_by(ZCTA, ALAND) %>% summarise(a = sum(a), .groups = "drop") %>% filter(a > 0); data.frame(ZCTA = g$ZCTA, area_prop = pmin(g$a / g$ALAND, 1)) }
mod_by <- split(tornado_exposure[, c("tornado_id", "ZCTA", "area_prop_affected")], tornado_exposure$tornado_id); lay_by <- split(survey_exposure[, c("tornado_id", "ZCTA", "area_prop_affected")], survey_exposure$tornado_id)
layer_pair <- setNames(Tt$tornado_id[M$k[sm$status[match(Tt$tornado_id[M$k], sm$tornado_id)] == "included"]], NULL)
rows_for_rule <- function(t) { u <- t[t$usable & !t$amb, ]; bind_rows(lapply(seq_len(nrow(u)), function(r) { tid <- Tt$tornado_id[u$k[r]]
  s <- if (u$i1[r] == M$i[match(u$k[r], M$k)] && !is.na(M$i[match(u$k[r], M$k)])) { z <- lay_by[[tid]]; if (is.null(z)) data.frame(ZCTA = character(), area_prop = numeric()) else data.frame(ZCTA = z$ZCTA, area_prop = z$area_prop_affected) } else area_rows(u$i1[r], u$k[r])
  m <- mod_by[[tid]]; if (is.null(m)) m <- data.frame(ZCTA = character(), area_prop_affected = numeric()); z <- union(s$ZCTA, m$ZCTA); if (!length(z)) return(NULL)
  data.frame(tornado_id = tid, ZCTA = z, s = s$area_prop[match(z, s$ZCTA)], m = m$area_prop_affected[match(z, m$ZCTA)]) })) }
cmp <- lapply(names(rules), function(n) { log("rows for: ", n); t <- rules[[n]]; rr <- rows_for_rule(t); both <- !is.na(rr$s) & !is.na(rr$m)
  data.frame(rule = n, paired = nrow(t), usable = sum(t$usable & !t$amb), agreement = sum(both) / nrow(rr), median_ratio = median(rr$m[both] / rr$s[both])) })
out <- list(compare = bind_rows(cmp)); print(out$compare)
# ---- the two agreement tables for the layer ------------------------------------------------------------------------------------------------------------------------
ids <- unique(survey_exposure$tornado_id); inc_all <- sm$tornado_id[sm$status == "included"]; log("paired tornadoes with a usable swath: ", length(inc_all), "; with survey rows: ", length(ids))
sv_rows <- survey_exposure[, c("tornado_id", "ZCTA", "area_prop_affected", "pop_prop_affected")]; names(sv_rows)[3:4] <- c("area_s", "pop_s")
md_rows <- tornado_exposure[tornado_exposure$tornado_id %in% inc_all, c("tornado_id", "ZCTA", "area_prop_affected", "pop_prop_affected")]; names(md_rows)[3:4] <- c("area_m", "pop_m")
J <- full_join(md_rows, sv_rows, by = c("tornado_id", "ZCTA")); J$in_m <- !is.na(J$area_m); J$in_s <- !is.na(J$area_s)
per <- J %>% group_by(tornado_id) %>% summarise(m = sum(in_m), s = sum(in_s), b = sum(in_m & in_s), same = all(in_m == in_s), .groups = "drop")
t1 <- data.frame(Definition = "Overlap: any part of the ZCTA is inside the path (SPC) or the swath (survey)", Tornadoes = f0(nrow(per)), `Pairs, SPC layer` = f0(sum(per$m)), `Pairs, survey layer` = f0(sum(per$s)), `Pairs in both` = f0(sum(per$b)),
  `SPC pairs also in survey` = pc(sum(per$b) / sum(per$m)), `Survey pairs also in SPC` = pc(sum(per$b) / sum(per$s)), Agreement = pc(sum(per$b) / (sum(per$m) + sum(per$s) - sum(per$b))), `Tornadoes with identical ZCTAs` = pc(mean(per$same)), check.names = FALSE)
both <- J[J$in_m & J$in_s, ]; ar <- both$area_m / both$area_s; pb <- both[!is.na(both$pop_m) & !is.na(both$pop_s) & both$pop_m > 0 & both$pop_s > 0, ]; pr_ <- pb$pop_m / pb$pop_s
qq <- function(x) paste0(sprintf("%.2f", quantile(x, .1)), " to ", sprintf("%.2f", quantile(x, .9)))
t2 <- data.frame(Share = c("Area share (ZCTA land area inside the path or swath)", "Population share (ZCTA residents inside the path or swath)"), `Pairs in both layers` = f0(c(nrow(both), nrow(pb))), `Median of SPC value divided by survey value` = sprintf("%.2f", c(median(ar), median(pr_))),
  `10th to 90th percentile of that ratio` = c(qq(ar), qq(pr_)), `Rank correlation between the two values` = sprintf("%.3f", c(cor(both$area_m, both$area_s, method = "spearman"), cor(pb$pop_m, pb$pop_s, method = "spearman"))), check.names = FALSE)
out$t1 <- t1; out$t2 <- t2; out$per <- per; print(t1); print(t2)
cmp_t <- md_table(data.frame(Rule = out$compare$rule, `Tornadoes paired` = f0(out$compare$paired), `Tornadoes with a usable swath` = f0(out$compare$usable), `Agreement at overlap` = pc(out$compare$agreement), `Median of SPC area share divided by survey area share` = sprintf("%.2f", out$compare$median_ratio), check.names = FALSE))
txt <- paste(c("**Four pairing rules.** These are the alternatives tested; agreement changes little between them. Agreement at overlap is the number of tornado-ZCTA pairs exposed in both layers divided by the number exposed in either layer, for the tornadoes with a usable swath under the rule; the last column is the median, over the pairs exposed in both layers, of the SPC area share divided by the survey area share.", "", cmp_t, "",
  "**Which ZCTAs are exposed.** For the paired tornadoes with a usable swath. *Tornadoes*: those with at least one exposed ZCTA in either layer. *Pairs*: tornado-ZCTA pairs exposed in the SPC layer, in the survey layer, and in both. *SPC pairs also in survey*: pairs in both divided by SPC pairs. *Survey pairs also in SPC*: pairs in both divided by survey pairs. *Agreement*: pairs in both divided by pairs in either layer. *Tornadoes with identical ZCTAs*: the share of tornadoes whose list of exposed ZCTAs is the same in both layers.", "", md_table(t1), "",
  "**How large the shares are.** For the tornado-ZCTA pairs present in both layers (for the population row, those with a population share above 0 in both). *Median*: of the SPC share divided by the survey share. *Percentiles*: the 10th and 90th percentile of that ratio. *Rank correlation*: Spearman correlation between the SPC share and the survey share.", "", md_table(t2)), collapse = "\n")
writeLines(txt, "data-raw/survey/comparison_tables.md"); saveRDS(out, qa_out("survey_comparison.rds")); log("done 45")
