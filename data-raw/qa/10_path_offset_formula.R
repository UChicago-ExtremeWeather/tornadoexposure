# Run from the package root: Rscript data-raw/qa/10_path_offset_formula.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf)}); options(width=170)
load("data/tornado_tracks.rda")
raw <- read.csv(qa_spc_csv()) %>% filter(yr>=1996, sg==1) %>% mutate(tornado_id=paste(yr,om,sep="_")) %>% filter(!duplicated(tornado_id) & !duplicated(tornado_id, fromLast=TRUE)) %>% select(tornado_id, st, mag)
ln <- tornado_tracks[tornado_tracks$track_type=="line", ]
d <- st_drop_geometry(ln) %>% mutate(year=as.integer(substr(tornado_id,1,4)), era=ifelse(year<=2006,"1996-2006","2007+"), c_mi=as.numeric(st_length(ln))/1609.344, L=len_mi, half_km=wid_yd*0.9144/2/1000) %>% left_join(raw, by="tornado_id")
cat("line tracks:", nrow(d), "; with len > straight distance (s defined):", sum(d$L > d$c_mi), sprintf("(%.1f%%)", 100*mean(d$L > d$c_mi)), "; len <= straight distance:", sum(d$L <= d$c_mi), "\n")
d$s_mi <- ifelse(d$L > d$c_mi, sqrt(3*d$c_mi*(d$L-d$c_mi)/8), 0); d$s_km <- d$s_mi*1.609344
# allowance for the rounding of len (+-0.05 mi before 2007; +-0.005 mi from 2007): shrink L-c by the rounding step
rnd <- ifelse(d$year<=2006, 0.05, 0.005); d$s_adj_km <- 1.609344*ifelse(d$L-rnd > d$c_mi, sqrt(3*d$c_mi*(d$L-rnd-d$c_mi)/8), 0)
d$lenclass <- cut(d$L, c(-1,5,20,1e3), labels=c("under 5 mi","5-20 mi","over 20 mi"), right=FALSE)
q <- function(x) signif(quantile(x, c(.5,.75,.9,.95,.99,1)),3)
cat("\nOffset s (km), all line tracks with s defined (quantiles 50/75/90/95/99/100):\n"); print(q(d$s_km[d$s_km>0]))
cat("\nBy length class (all lines; share with s>0, share with s > path half-width):\n")
print(d %>% group_by(lenclass) %>% summarise(n=n(), pct_s_defined=round(100*mean(s_km>0),1), median_s_km=signif(median(s_km[s_km>0]),3), p90_s_km=signif(quantile(s_km[s_km>0],.9),3), max_s_km=signif(max(s_km),3), pct_s_gt_halfwidth=round(100*mean(s_km>half_km),1), pct_sadj_gt_halfwidth=round(100*mean(s_adj_km>half_km),1)) %>% as.data.frame(), row.names=FALSE)
cat("\nBy era:\n"); print(d %>% group_by(era) %>% summarise(n=n(), pct_s_defined=round(100*mean(s_km>0),1), median_s_km=signif(median(s_km[s_km>0]),3), p90_s_km=signif(quantile(s_km[s_km>0],.9),3), max_s_km=signif(max(s_km),3), pct_s_gt_halfwidth=round(100*mean(s_km>half_km),1), pct_sadj_gt_halfwidth=round(100*mean(s_adj_km>half_km),1)) %>% as.data.frame(), row.names=FALSE)
cat("\nBy era x length class: share with s > half-width (and after allowing for len rounding):\n")
print(d %>% group_by(era, lenclass) %>% summarise(n=n(), pct_s_gt_halfwidth=round(100*mean(s_km>half_km),1), pct_sadj_gt_halfwidth=round(100*mean(s_adj_km>half_km),1), median_s_km=signif(median(s_km[s_km>0]),3), .groups="drop") %>% as.data.frame(), row.names=FALSE)
cat(sprintf("\nOverall: s > half-width for %d of %d lines (%.1f%%); with rounding allowance %.1f%%; s > 1 km: %d (%.1f%%); s > 5 km: %d\n", sum(d$s_km>d$half_km), nrow(d), 100*mean(d$s_km>d$half_km), 100*mean(d$s_adj_km>d$half_km), sum(d$s_km>1), 100*mean(d$s_km>1), sum(d$s_km>5)))
cat("\n20 largest s:\n"); print(d %>% arrange(desc(s_km)) %>% head(20) %>% transmute(tornado_id, st, mag, year, c_mi=round(c_mi,1), len_mi=L, s_km=round(s_km,1), half_width_km=round(half_km,2), wid_yd) %>% as.data.frame(), row.names=FALSE)
cat("\n20 largest s among tornadoes with len_ratio between 0.5 and 1 (len is plausible vs the chord):\n"); print(d %>% filter(c_mi/L > .5) %>% arrange(desc(s_km)) %>% head(10) %>% transmute(tornado_id, st, mag, year, c_mi=round(c_mi,1), len_mi=L, s_km=round(s_km,1), half_width_km=round(half_km,2)) %>% as.data.frame(), row.names=FALSE)
j <- d[d$tornado_id=="2011_1105221634-01",]; cat(sprintf("\nJoplin: chord c=%.2f mi, len L=%.2f mi, s=%.2f mi = %.2f km; path half-width %.2f km\n", j$c_mi, j$L, j$s_mi, j$s_km, j$half_km))
# Joplin city center distance from the modeled centerline
cl <- st_transform(ln[ln$tornado_id=="2011_1105221634-01",], 5070); for (nm in list(c("Joplin city (37.0842, -94.5133, approximate)", 37.0842, -94.5133))) { p <- st_transform(st_sfc(st_point(c(as.numeric(nm[3]), as.numeric(nm[2]))), crs=4326), 5070); cat(nm[1], ": distance to modeled centerline", round(as.numeric(st_distance(p, cl))/1000, 2), "km\n") }
saveRDS(d, qa_out("pathgeom_d.rds"))
