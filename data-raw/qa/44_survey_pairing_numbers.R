# Run from the package root after data-raw/survey/build_survey.R:  caffeinate -i Rscript data-raw/qa/44_survey_pairing_numbers.R   (progress: data-raw/qa/out/44.log)
# Tests of the settings of the survey layer and the numbers for its documentation, all computed here:
#   * the date window (0, 1 and 2 days) under the mutual-closest pairing
#   * the swath filter (each of its four values changed in turn) and the resolution of the damage polygons
#   * counts of the pairing and of the status values, and the pairs whose survey line is farther away than the tornado is long
# Writes data-raw/qa/out/survey_layer_numbers.rds; the text is written from it by 44b_survey_pairing_text.R.
suppressMessages({library(sf); library(dplyr)}); sf_use_s2(FALSE); options(width = 220)
source("data-raw/qa/helpers.R"); source("data-raw/survey/pairing_functions.R")
log <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S"), " ", paste0(...)); cat(m, "\n"); cat(m, "\n", file = qa_out("44.log"), append = TRUE) }
for (f in c("tornado_tracks", "survey_matches", "survey_tracks", "tornado_exposure")) load(file.path("data", paste0(f, ".rda")))
ctx <- survey_context(); list2env(ctx, environment()); sm <- survey_matches
f0 <- function(x) format(x, big.mark = ",", trim = TRUE); pc <- function(x, d = 1) sprintf(paste0("%.", d, "f%%"), 100 * x)
md_table <- function(d) paste(c(paste0("| ", paste(names(d), collapse = " | "), " |"), paste0("|", paste(rep("---", ncol(d)), collapse = "|"), "|"), apply(d, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))), collapse = "\n")
out <- list()
# ---- pairs for each date window -----------------------------------------------------------------------------------------------------------------
pairs_for <- function(window) { pr <- candidate_distances(Du, Tt, sp, sv, window); M <- mutual_closest(pr)
  us <- vapply(seq_len(nrow(M)), function(r) is_usable(swath_of(sw, M$i[r], M$k[r], Tt$wid_yd)), logical(1)); list(M = M, usable = us, n_cand = nrow(pr)) }
win <- lapply(0:2, function(w) { log("date window ", w, " day(s)"); pairs_for(w) })
out$window <- data.frame(days = 0:2, candidate_pairs = vapply(win, `[[`, 0, "n_cand"), paired = vapply(win, function(x) nrow(x$M), 0L), usable = vapply(win, function(x) sum(x$usable), 0L))
stopifnot(out$window$paired[2] == sum(sm$status != "no_pair"), out$window$usable[2] == sum(sm$status == "included")); print(out$window)
# ---- the final pairs ----------------------------------------------------------------------------------------------------------------------------------------
M <- win[[2]]$M
base <- lapply(seq_len(nrow(M)), function(r) swath_of(sw, M$i[r], M$k[r], Tt$wid_yd)); base_usable <- vapply(base, is_usable, TRUE); base_area <- vapply(base, function(s) s$area_km2, 0)
variants <- list(baseline = list(), `90% -> 80%` = list(frac = .8), `90% -> 95%` = list(frac = .95), `500 m -> 250 m` = list(margin = 250), `500 m -> 1,000 m` = list(margin = 1000), `200 m -> 100 m` = list(cover_dist = 100), `200 m -> 400 m` = list(cover_dist = 400), `50% -> 40%` = list(covmin = .4), `50% -> 60%` = list(covmin = .6))
has <- which(vapply(base, function(s) s$n_raw > 0, TRUE)); log("swath filter variants for ", length(has), " pairs with a polygon crossing the centerline")
var_res <- lapply(names(variants), function(n) { v <- variants[[n]]; covmin <- if (is.null(v$covmin)) 0.5 else v$covmin; v$covmin <- NULL
  u <- rep(FALSE, nrow(M)); a <- rep(NA_real_, nrow(M))
  for (r in has) { s <- do.call(swath_of, c(list(sw, M$i[r], M$k[r], Tt$wid_yd), v)); u[r] <- is_usable(s, covmin); a[r] <- s$area_km2 }
  both <- u & base_usable; ch <- 100 * (a[both] / base_area[both] - 1)
  data.frame(setting = n, usable = sum(u), gained = sum(u & !base_usable), lost = sum(!u & base_usable), median_area_change_pct = round(median(ch), 2), p90_abs_area_change_pct = round(quantile(abs(ch), .9), 2)) })
out$swath_filter <- bind_rows(var_res); stopifnot(out$swath_filter$usable[1] == sum(base_usable)); print(out$swath_filter)
# ---- resolution ---------------------------------------------------------------------------------------------------------------------------------------------------
Pf <- readRDS(qa_out("dat_polys_2007_full.rds")); swf <- swath_setup(Du, sv, Pf)
ur <- which(base_usable); full <- lapply(ur, function(r) swath_of(swf, M$i[r], M$k[r], Tt$wid_yd)); fa <- vapply(full, function(s) s$area_km2, 0); fu <- vapply(full, is_usable, TRUE)
chf <- 100 * (base_area[ur][fu] / fa[fu] - 1)
S5 <- st_transform(survey_tracks, 5070); sa <- as.numeric(st_area(S5)) / 1e6; names(sa) <- survey_tracks$tornado_id
ids <- Tt$tornado_id[M$k[ur]]; chs <- 100 * (sa[ids] / sm$swath_km2[match(ids, sm$tornado_id)] - 1)
out$resolution <- data.frame(comparison = c("20 m generalization versus full resolution", "50 m simplification versus 20 m swath"), tornadoes = c(sum(fu), length(chs)), median_change_pct = round(c(median(chf), median(chs)), 3),
  p90_abs_change_pct = round(c(quantile(abs(chf), .9), quantile(abs(chs), .9)), 3), max_abs_change_pct = round(c(max(abs(chf)), max(abs(chs))), 1)); out$resolution_usable_in_one_only <- sum(!fu)
print(out$resolution)
# ---- counts -------------------------------------------------------------------------------------------------------------------------------------------------------------
n_copies_lines <- nrow(F$lines) - nrow(Du); n_tornadoes_with_copies <- sum(Du$n_copies > 1)
n_pairs <- nrow(M); n_lines <- nrow(Du); st <- table(factor(sm$status, c("included", "no_swath", "no_pair")))
spc_len_km <- pmax(Tt$len_mi[M$k], 0.1) * 1.609344; far <- M$dist_km > spc_len_km; far_usable <- far & base_usable
out$counts <- list(lines_fetched = nrow(F$lines), lines_distinct = n_lines, copies = n_copies_lines, polygons = nrow(P), candidate_pairs = win[[2]]$n_cand, pairs = n_pairs, lines_paired = n_pairs, lines_unpaired = n_lines - n_pairs,
  tornadoes = nrow(Tt), status = st, no_candidate = sum(sm$status == "no_pair" & sm$n_candidates_tornado == 0), far = sum(far), far_usable = sum(far_usable), fetch_date = F$date, long_lines = sum(sp$is_line))
saveRDS(out, qa_out("survey_layer_numbers.rds")); print(out$counts)
log("done 44")
