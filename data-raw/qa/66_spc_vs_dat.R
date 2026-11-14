# Run from the package root, after data-raw/dat/build_dat_exposure.R:  Rscript data-raw/qa/66_spc_vs_dat.R
# Compares the ZCTAs that the SPC line crosses (spc_exposed) with the ZCTAs that the linked NWS damage polygons cover land in (dat_exposed) in tornado_exposure.
# Tornadoes compared: those with a linked DAT line and at least one footprint polygon (EF0 to EF5 polygon touched by a linked line; at least one row with dat_exposed TRUE). No other filter is used.
# Quantities: pairs (tornado, ZCTA) in both sets, in the SPC set only and in the DAT set only; the agreement is pairs in both over pairs in either, over all tornadoes together; the same
# per tornado (median, and the number of tornadoes with identical sets); and the same for line tornadoes and for tornadoes with no usable end point separately.
# Output: data-raw/qa/out/spc_vs_dat.rds and rows spc_vs_dat_* in data-raw/readme/numbers.csv.
source("data-raw/qa/helpers.R"); suppressMessages({library(dplyr); library(sf)})
for (f in list.files("data", pattern = "[.]rda$", full.names = TRUE)) load(f)
d <- tornado_exposure; ids <- unique(d$tornado_id[d$dat_exposed %in% TRUE]); x <- d[d$tornado_id %in% ids, ]
x$cls <- ifelse(x$spc_exposed & x$dat_exposed, "both", ifelse(x$spc_exposed, "spc_only", "dat_only"))
agg <- function(y) { t <- table(factor(y$cls, c("both", "spc_only", "dat_only"))); c(tornadoes = length(unique(y$tornado_id)), both = t[["both"]], spc_only = t[["spc_only"]], dat_only = t[["dat_only"]], agreement_pct = 100 * t[["both"]] / sum(t)) }
per <- x %>% group_by(tornado_id, track_type) %>% summarise(both = sum(cls == "both"), either = n(), agree = both / either, identical_sets = all(cls == "both"), .groups = "drop")
R <- list(all = agg(x), line = agg(x[x$track_type == "line", ]), point = agg(x[x$track_type == "point", ]), per_tornado_median = median(per$agree), per_tornado_identical = sum(per$identical_sets), per_tornado_n = nrow(per),
          per_tornado_none_in_common = sum(per$both == 0), footprint_tornadoes_by_type = table(per$track_type), dat_only_boundary_dist_km = quantile(x$boundary_dist_km[x$cls == "dat_only"], c(.5, .9, .99, 1), names = FALSE))
saveRDS(R, qa_out("spc_vs_dat.rds")); print(R)
nm <- c(spc_vs_dat_n = R$all[["tornadoes"]], spc_vs_dat_both = R$all[["both"]], spc_vs_dat_spc_only = R$all[["spc_only"]], spc_vs_dat_dat_only = R$all[["dat_only"]], spc_vs_dat_agreement_pct = R$all[["agreement_pct"]],
        spc_vs_dat_agreement_line_pct = R$line[["agreement_pct"]], spc_vs_dat_agreement_point_pct = R$point[["agreement_pct"]], spc_vs_dat_point_n = R$point[["tornadoes"]], spc_vs_dat_per_tornado_median_pct = 100 * R$per_tornado_median,
        spc_vs_dat_identical_n = R$per_tornado_identical, spc_vs_dat_none_in_common_n = R$per_tornado_none_in_common, spc_vs_dat_dat_only_dist_median_km = R$dat_only_boundary_dist_km[1], spc_vs_dat_dat_only_dist_p90_km = R$dat_only_boundary_dist_km[2], spc_vs_dat_dat_only_dist_max_km = R$dat_only_boundary_dist_km[4])
f <- "data-raw/readme/numbers.csv"; n <- read.csv(f, stringsAsFactors = FALSE); n <- n[!grepl("^modeled_vs_dat_", n$name) & !n$name %in% names(nm), ]
write.csv(rbind(n, data.frame(name = names(nm), value = unname(nm), source = "66")), f, row.names = FALSE)
