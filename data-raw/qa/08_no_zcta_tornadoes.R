# Run from the package root: Rscript data-raw/qa/08_no_zcta_tornadoes.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf); library(ggplot2)})
options(width=140, tigris_use_cache=TRUE, timeout=600); sf_use_s2(FALSE)
load("data/tornado_tracks.rda"); load("data/tornado_exposure.rda")
raw <- read.csv(qa_spc_csv()) %>% mutate(tornado_id=paste(yr,om,sep="_"))
no <- tornado_tracks[!tornado_tracks$tornado_id %in% tornado_exposure$tornado_id,] %>% left_join(raw %>% filter(sg==1) %>% distinct(tornado_id,.keep_all=TRUE) %>% select(tornado_id,yr,st,mag,len,wid,slat,slon,elat,elon), by="tornado_id")
cat("no-ZCTA tornadoes:", nrow(no), " by type:"); print(table(no$track_type)); cat("by magnitude:"); print(table(no$mag)); cat("by decade vintage:"); print(table(cut(no$yr,c(1995,2009,2019,2025),labels=c("2000v","2010v","2020v"))))
st <- tigris::states(cb=TRUE, year=2020, progress_bar=FALSE) %>% st_transform(5070) %>% st_make_valid()
vint <- function(y) ifelse(y<2010,2000,ifelse(y<2020,2010,2020))
zs <- lapply(c(2000,2010,2020), function(v) tigris::zctas(year=v, progress_bar=FALSE) %>% st_transform(5070) %>% st_make_valid())
names(zs) <- c(2000,2010,2020)
zs <- lapply(zs, function(z) st_simplify(z, dTolerance=100)); st <- st_simplify(st, dTolerance=100)
message("simplified")
g5 <- st_transform(no, 5070)
win <- function(g, km) st_as_sfc(st_bbox(st_buffer(g, km*1000)), crs=5070)
no$on_land <- NA; no$dist_land_km <- NA; no$near_km <- NA; no$hit_other <- FALSE; no$gap_share <- NA
for (i in seq_len(nrow(no))) {
  g <- st_geometry(g5[i,]); w <- win(g, 15)
  stw <- st_geometry(st[st_intersects(w, st, sparse=FALSE)[1,],])
  landw <- if (length(stw)) st_union(st_intersection(stw, w)) else st_sfc(st_polygon(), crs=5070)
  no$on_land[i] <- length(stw)>0 && any(st_intersects(g, landw, sparse=FALSE))
  no$dist_land_km[i] <- if (length(stw)) as.numeric(st_distance(g, landw))/1000 else NA
  zv <- zs[[as.character(vint(no$yr[i]))]]
  zw <- zv[st_intersects(w, zv, sparse=FALSE)[1,],]
  no$near_km[i] <- if (nrow(zw)) min(as.numeric(st_distance(g, zw)))/1000 else Inf
  for (v in names(zs)) if (v != as.character(vint(no$yr[i]))) { zo <- zs[[v]]; if (any(st_intersects(g, zo, sparse=FALSE))) no$hit_other[i] <- TRUE }
  b <- st_buffer(g, 3000); l <- st_intersection(landw, b)
  if (length(l) && !all(st_is_empty(l))) { la <- as.numeric(sum(st_area(l))); covd <- if (nrow(zw)) sum(as.numeric(st_area(st_intersection(l, st_union(st_geometry(zw)))))) else 0; no$gap_share[i] <- 1 - covd/la }
  if (i %% 20 == 0) message("done ", i)
}
cat("\ntrack intersects state land (cb shoreline):", sum(no$on_land), " not:", sum(!no$on_land), "\n")
cat("intersects ZCTA in another vintage:", sum(no$hit_other), "\n")
cat("nearest own-vintage ZCTA (km): "); print(signif(quantile(no$near_km, c(0,.1,.25,.5,.75,.9,1), na.rm=TRUE),3))
cat("distance to land (km) for off-land ones: "); print(signif(summary(no$dist_land_km[!no$on_land]),3))
cat("on-land: share of land within 3 km of track not covered by any ZCTA:\n"); print(signif(summary(no$gap_share[no$on_land]),3))
no$cat <- ifelse(!no$on_land, "offshore/water", ifelse(!is.na(no$gap_share) & no$gap_share>.5,"on land, uncovered gap","on land, mostly covered"))
print(table(no$cat, no$track_type))
write.csv(st_drop_geometry(no) %>% select(tornado_id, yr, st, mag, track_type, len, wid, slat, slon, elat, elon, on_land, dist_land_km, near_km, hit_other, gap_share, cat), qa_out("no_zcta.csv"), row.names=FALSE)
print(st_drop_geometry(no) %>% arrange(cat) %>% group_by(cat) %>% slice_head(n=4) %>% ungroup() %>% select(tornado_id, st, mag, track_type, slat, slon, elat, elon, near_km, gap_share, cat) %>% mutate(across(where(is.numeric), ~round(.x,2))))
# maps: 2 per category
set.seed(1); samp <- no %>% group_by(cat) %>% slice_sample(n=2) %>% ungroup()
pan <- list()
for (i in seq_len(nrow(samp))) {
  g <- st_geometry(st_transform(samp[i,], 5070)); w <- win(g, 8)
  z <- zs[[as.character(vint(samp$yr[i]))]]
  zz <- st_intersection(st_geometry(z[st_intersects(w, z, sparse=FALSE)[1,],]), w)
  ll <- st_intersection(st_geometry(st[st_intersects(w, st, sparse=FALSE)[1,],]), w)
  lab <- paste0(samp$tornado_id[i], " ", samp$st[i], ": ", samp$cat[i])
  pan[[i]] <- rbind(st_sf(lab=lab, layer="state land", geometry=ll), if (length(zz)) st_sf(lab=lab, layer="ZCTA", geometry=zz), st_sf(lab=lab, layer="path polygon", geometry=st_buffer(g, samp$wid[i]*0.9144/2 + 0.1)), st_sf(lab=lab, layer="track", geometry=g))
}
P <- do.call(rbind, pan)
p <- ggplot() + geom_sf(data=P[P$layer=="state land",], fill="grey92", color=NA) + geom_sf(data=P[P$layer=="ZCTA",], fill="#9ecae1", alpha=.6, color="steelblue") + geom_sf(data=P[P$layer %in% c("path polygon","track"),], aes(color=layer), fill="red", linewidth=1) + facet_wrap(~lab, ncol=3) + theme_minimal(base_size=8) + theme(axis.text=element_blank(), legend.position="bottom")
ggsave(qa_out("no_zcta_maps.png"), p, width=11, height=7, dpi=110)

# numbers quoted in data-raw/known_issues.md (read by check_documented_claims.R)
saveRDS(list(n = nrow(no), hit_other_vintage = sum(no$hit_other), on_land = sum(no$on_land), not_on_land = sum(!no$on_land)), qa_out("documented_08.rds"))
