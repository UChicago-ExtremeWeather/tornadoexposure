# Run from the package root: Rscript data-raw/qa/08b_no_zcta_maps.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf); library(ggplot2)})
options(tigris_use_cache=TRUE, timeout=600); sf_use_s2(FALSE)
load("data/tornado_tracks.rda")
n <- read.csv(qa_out("no_zcta.csv")); 
set.seed(3); samp <- n %>% group_by(cat) %>% slice_sample(n=2) %>% ungroup() %>% filter(yr<2010)
cat(nrow(samp), "samples\n"); print(samp %>% select(tornado_id, st, track_type, cat, hit_other))
z00 <- tigris::zctas(year=2000, progress_bar=FALSE) %>% st_transform(5070) %>% st_make_valid()
z20 <- tigris::zctas(year=2020, progress_bar=FALSE) %>% st_transform(5070) %>% st_make_valid()
stt <- tigris::states(cb=TRUE, year=2020, progress_bar=FALSE) %>% st_transform(5070) %>% st_make_valid()
L <- list()
for (i in seq_len(nrow(samp))) {
  g <- st_geometry(st_transform(tornado_tracks[tornado_tracks$tornado_id==samp$tornado_id[i],], 5070))
  w <- st_as_sfc(st_bbox(st_buffer(g, 6000)), crs=5070)
  crop <- function(x) { y <- x[lengths(st_intersects(x, w))>0,]; if (nrow(y)) st_sf(geometry=st_collection_extract(st_intersection(st_geometry(y), w), "POLYGON")) else NULL }
  lab <- paste0(samp$tornado_id[i], " ", samp$st[i], " (", samp$track_type[i], ")")
  parts <- list(`state land (cb)`=crop(stt), `2000 ZCTA`=crop(z00), `2020 ZCTA`=crop(z20))
  for (nm in names(parts)) if (!is.null(parts[[nm]])) { parts[[nm]]$layer <- nm; parts[[nm]]$lab <- lab; L[[length(L)+1]] <- parts[[nm]] }
  tr <- st_sf(geometry=g); tr$layer <- "track"; tr$lab <- lab; L[[length(L)+1]] <- tr
  cat(lab, ":", sapply(parts, function(p) if (is.null(p)) 0 else nrow(p)), "\n")
}
P <- do.call(rbind, lapply(L, function(x) x[, c("layer","lab","geometry")]))
P$layer <- factor(P$layer, c("state land (cb)","2020 ZCTA","2000 ZCTA","track"))
saveRDS(P, qa_out("maps_P.rds"))
P <- P[!st_is_empty(P),]
mk <- function(l) { d <- P[P$lab==l,]; ggplot() + geom_sf(data=d[d$layer=="state land (cb)",], fill="grey93", color="grey60") +
  geom_sf(data=d[d$layer=="2020 ZCTA",], fill="#fdae6b", alpha=.35, color="#e6550d", linewidth=.3) +
  geom_sf(data=d[d$layer=="2000 ZCTA",], fill="#9ecae1", alpha=.45, color="#3182bd", linewidth=.3) +
  geom_sf(data=d[d$layer=="track",], color="red", size=2.5, linewidth=1.2) + ggtitle(l) + theme_minimal(base_size=8) + theme(axis.text=element_blank(), panel.grid=element_blank()) }
pl <- lapply(unique(P$lab), mk)
png(qa_out("no_zcta_maps2.png"), width=1100, height=720, res=110); gridExtra::grid.arrange(grobs=pl, ncol=3); dev.off()
