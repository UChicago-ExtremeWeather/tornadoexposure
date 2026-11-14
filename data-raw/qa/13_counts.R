# Run from the package root: Rscript data-raw/qa/13_counts.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf)}); options(width=150)
load("data/tornado_exposure.rda"); load("data/tornado_tracks.rda")
raw <- read.csv(qa_spc_csv()) %>% filter(yr>=1996, sg==1) %>% mutate(tornado_id=paste(yr,om,sep="_")) %>% group_by(tornado_id) %>% summarise(mag=first(mag), .groups="drop")
# tornadoes that share a year and om in SPC are suffixed _1/_2 in the package: match them on the unsuffixed id
tt <- st_drop_geometry(tornado_tracks) %>% mutate(raw_id=sub("^((2001_56)|(2002_506))_[12]$", "\\1", tornado_id)) %>% left_join(raw, by=c("raw_id"="tornado_id"))
tt$rating <- ifelse(tt$mag == -9, "unknown", ifelse(tt$mag == 0, "EF0", ifelse(tt$mag >= 1, "EF1+", NA)))
tt$in_exp <- tt$tornado_id %in% tornado_exposure$tornado_id[tornado_exposure$spc_exposed]; tt$pt <- tt$track_type == "point"
cat("tornadoes by rating group:\n"); print(tt %>% group_by(rating) %>% summarise(tornadoes=n(), point_tracks=sum(pt), pct_point=round(100*mean(pt),1), no_ZCTA=sum(!in_exp), pct_no_ZCTA=round(100*mean(!in_exp),2)) %>% as.data.frame(), row.names=FALSE)
cat("\nall:", nrow(tt), "tornadoes; points", sum(tt$pt), sprintf("(%.1f%%)", 100*mean(tt$pt)), "; no-ZCTA", sum(!tt$in_exp), sprintf("(%.2f%%)", 100*mean(!tt$in_exp)), "\n")
cat("exposure rows by magnitude:\n"); print(table(tornado_exposure$magnitude, useNA="ifany"))
cat("EF count (tornadoes) 0..5 and unknown:\n"); print(table(factor(ifelse(tt$mag==-9,NA,tt$mag)), useNA="ifany"))
cat("exposure rows:", nrow(tornado_exposure), "; tornadoes in exposure:", n_distinct(tornado_exposure$tornado_id), "\n")
cat("SPC rows:", sum(tornado_exposure$spc_exposed), "; DAT-only rows:", sum(!tornado_exposure$spc_exposed), "; width 0:", sum(tornado_tracks$wid_yd==0, na.rm=TRUE), "\n")
cat("Mayfield loss:", tornado_exposure$property_loss_tornado_total[tornado_exposure$tornado_id=="2021_2112102054-01"][1], "\n")
cat("file sizes (KB): "); print(round(file.size(list.files("data", full.names = TRUE))/1024))
