# Run from the package root: Rscript data-raw/qa/13_counts.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf)}); options(width=150)
load("data/tornado_exposure.rda"); load("data/tornado_tracks.rda")
raw <- read.csv(qa_spc_csv()) %>% filter(yr>=1996, sg==1) %>% mutate(tornado_id=paste(yr,om,sep="_")) %>% group_by(tornado_id) %>% summarise(mag=first(mag), .groups="drop")
# tornadoes that share a year and om in SPC are suffixed _1/_2 in the package: match them on the unsuffixed id
tt <- st_drop_geometry(tornado_tracks) %>% mutate(raw_id=sub("^((2001_56)|(2002_506))_[12]$", "\\1", tornado_id)) %>% left_join(raw, by=c("raw_id"="tornado_id"))
tt$rating <- ifelse(tt$mag == -9, "unknown", ifelse(tt$mag == 0, "EF0", ifelse(tt$mag >= 1, "EF1+", NA)))
tt$in_exp <- tt$tornado_id %in% tornado_exposure$tornado_id; tt$pt <- tt$track_type != "line"
cat("tornadoes by rating group:\n"); print(tt %>% group_by(rating) %>% summarise(tornadoes=n(), point_tracks=sum(pt), pct_point=round(100*mean(pt),1), no_ZCTA=sum(!in_exp), pct_no_ZCTA=round(100*mean(!in_exp),2)) %>% as.data.frame(), row.names=FALSE)
cat("\nall:", nrow(tt), "tornadoes; points", sum(tt$pt), sprintf("(%.1f%%)", 100*mean(tt$pt)), "; no-ZCTA", sum(!tt$in_exp), sprintf("(%.2f%%)", 100*mean(!tt$in_exp)), "\n")
cat("exposure rows by magnitude:\n"); print(table(tornado_exposure$magnitude, useNA="ifany"))
cat("EF count (tornadoes) 0..5 and unknown:\n"); print(table(factor(ifelse(tt$mag==-9,NA,tt$mag)), useNA="ifany"))
cat("exposure rows:", nrow(tornado_exposure), "; tornadoes in exposure:", n_distinct(tornado_exposure$tornado_id), "\n")
cat("area_prop_affected quantiles (all):", paste(signif(quantile(tornado_exposure$area_prop_affected, c(.01,.05,.25,.5,.75,.9,.99,1)),3), collapse=" "), "\n")
for (th in c(.01,.05,.1,.5)) cat(sprintf("rows >= %s: %d (%.2f%%)\n", th, sum(tornado_exposure$area_prop_affected>=th), 100*mean(tornado_exposure$area_prop_affected>=th)))
cat("rows < 1e-6:", sum(tornado_exposure$area_prop_affected<1e-6), "; ==1:", sum(tornado_exposure$area_prop_affected==1), "; width imputed:", sum(tornado_tracks$width_imputed), "\n")
cat("Mayfield loss:", tornado_exposure$property_loss_tornado_total[tornado_exposure$tornado_id=="2021_2112102054-01"][1], "\n")
cat("file sizes (KB): "); print(round(file.size(c("data/tornado_exposure.rda","data/tornado_tracks.rda"))/1024))
