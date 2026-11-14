# Run from the package root: Rscript data-raw/qa/02_coordinate_rounding_analysis.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(tidyr)}); options(width=170)
R <- readRDS(qa_out("d2_results.rds")); S <- R$S; res <- R$res
S <- S %>% mutate(lenbin=cut(len_mi, c(-1,2,10,1e3), labels=c("<2 mi","2-10 mi",">10 mi"), right=FALSE), ttype=ifelse(track_type=="line","line","point"))
base <- res[["0"]]; reps <- setdiff(names(res), "0")
cat("sample: ", nrow(S), " tornadoes; replicates:", length(reps), "\n"); print(table(S$era, S$track_type)); print(table(S$era, S$lenbin))
cmp <- lapply(reps, function(r) { x <- full_join(base %>% rename(pb=share), res[[r]] %>% rename(pr=share), by=c("tornado_id","ZCTA")) %>% mutate(in_b=!is.na(pb), in_r=!is.na(pr), pb=coalesce(pb,0), pr=coalesce(pr,0), rep=as.integer(r)); x })
A <- bind_rows(cmp) %>% left_join(S %>% select(tornado_id, era, ttype, lenbin), by="tornado_id") %>% mutate(xor=in_b!=in_r)
nrep <- length(reps)
tor_all <- S %>% select(tornado_id, era, ttype, lenbin)
summ <- function(by) {
  grp <- by
  nt <- tor_all %>% group_by(across(all_of(grp))) %>% summarise(tornadoes=n(), .groups="drop")
  base_rows <- base %>% left_join(S %>% select(tornado_id, era, ttype, lenbin), by="tornado_id") %>% group_by(across(all_of(grp))) %>% summarise(base_rows=n(), .groups="drop")
  per_rep <- A %>% group_by(across(all_of(c(grp,"rep")))) %>% summarise(lost=sum(in_b & !in_r), gained=sum(!in_b & in_r), union=sum(in_b|in_r), .groups="drop")
  tc <- A %>% filter(xor) %>% group_by(across(all_of(c(grp,"rep"))), tornado_id) %>% summarise(.groups="drop") %>% group_by(across(all_of(c(grp,"rep")))) %>% summarise(n_changed=n(), .groups="drop")
  per_rep <- per_rep %>% left_join(tc, by=c(grp,"rep")) %>% mutate(n_changed=coalesce(n_changed,0L))
  anyrep <- A %>% filter(xor) %>% distinct(across(all_of(grp)), tornado_id) %>% group_by(across(all_of(grp))) %>% summarise(n_any=n(), .groups="drop")
  out <- per_rep %>% group_by(across(all_of(grp))) %>% summarise(lost=mean(lost), gained=mean(gained), union=mean(union), n_changed=mean(n_changed), .groups="drop") %>%
    left_join(nt, by=grp) %>% left_join(base_rows, by=grp) %>% left_join(anyrep, by=grp) %>% mutate(n_any=coalesce(n_any,0L)) %>%
    transmute(across(all_of(grp)), tornadoes, base_rows, `rows_lost_%`=round(100*lost/base_rows,2), `rows_gained_%`=round(100*gained/base_rows,2), `row_change_%(sym diff/union)`=round(100*(lost+gained)/union,2), `tornadoes_changed_%/rep`=round(100*n_changed/tornadoes,2), `tornadoes_changed_in_any_rep_%`=round(100*n_any/tornadoes,2))
  as.data.frame(out) }
era_tab <- summ("era"); saveRDS(era_tab, qa_out("coordinate_rounding_summary.rds"))   # read by check_documented_claims.R
cat("\n=== by era ===\n"); print(era_tab, row.names=FALSE)
cat("\n=== by era x track type (line vs point) ===\n"); print(summ(c("era","ttype")), row.names=FALSE)
cat("\n=== by era x length ===\n"); print(summ(c("era","lenbin")), row.names=FALSE)
cat("\n=== by era x track type x length ===\n"); print(summ(c("era","ttype","lenbin")), row.names=FALSE)
cat("\nline_share_of_tornado relative change among pairs present in baseline and replicate: median abs relative change by era\n")
print(as.data.frame(A %>% filter(in_b, in_r, pb>0) %>% mutate(rel=abs(pr/pb-1)) %>% group_by(era) %>% summarise(median_rel_change=round(median(rel),3), p90=round(quantile(rel,.9),3), share_over_50pct=round(mean(rel>.5),3))), row.names=FALSE)
