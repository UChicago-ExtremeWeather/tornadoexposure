# Run from the package root: Rscript data-raw/qa/12_ncei_point_tracks.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr); library(sf)}); options(width=170, timeout=600)
load("data/tornado_tracks.rda")
tt <- st_drop_geometry(tornado_tracks) %>% mutate(year=as.integer(substr(tornado_id,1,4)))
raw <- read.csv(qa_spc_csv()) %>% filter(yr>=1996, sg==1, mag>=1) %>% mutate(tornado_id=paste(yr,om,sep="_")) %>% filter(!duplicated(tornado_id) & !duplicated(tornado_id, fromLast=TRUE)) %>% select(tornado_id, st, date, slat, slon, elat, elon, len, wid, mag)
pe <- tt %>% select(tornado_id, track_type, year) %>% filter(track_type=="point_equal_area") %>% inner_join(raw, by="tornado_id")
set.seed(909)
smp <- bind_rows(pe %>% filter(year<=2006) %>% slice_sample(n=25), pe %>% filter(year>=2007) %>% slice_sample(n=25)) %>% mutate(era=ifelse(year<=2006,"1996-2006","2007+"))
cat("sample:", nrow(smp), " years:", paste(sort(unique(smp$year)), collapse=" "), "\n")
idx <- readLines(qa_ncei_index()); files <- regmatches(idx, regexpr("StormEvents_details-ftp_v1.0_d[0-9]{4}_c[0-9]{8}.csv.gz", idx)); files <- unique(files)
dir.create(qa_cache("ncei"), showWarnings=FALSE)
for (y in sort(unique(smp$year))) { f <- files[grepl(paste0("_d", y, "_"), files)]; dest <- file.path(qa_cache("ncei"), f)
  if (!file.exists(dest)) download.file(paste0("https://www.ncei.noaa.gov/pub/data/swdi/stormevents/csvfiles/", f), dest, mode="wb", quiet=TRUE) }
cat("downloaded MB:", round(sum(file.size(list.files(qa_cache("ncei"), full.names=TRUE)))/1e6,1), "\n")
state_name <- setNames(toupper(c(state.name, "District of Columbia", "Puerto Rico")), c(state.abb, "DC", "PR"))
ev <- bind_rows(lapply(sort(unique(smp$year)), function(y) { f <- list.files(qa_cache("ncei"), pattern=paste0("_d", y, "_"), full.names=TRUE)
  d <- read.csv(f, stringsAsFactors=FALSE, colClasses="character"); d <- d[d$EVENT_TYPE=="Tornado", c("EVENT_ID","STATE","BEGIN_YEARMONTH","BEGIN_DAY","BEGIN_LAT","BEGIN_LON","END_LAT","END_LON","TOR_LENGTH","TOR_WIDTH","TOR_F_SCALE","BEGIN_LOCATION")]
  d$year <- y; d })) %>% mutate(across(c(BEGIN_LAT,BEGIN_LON,END_LAT,END_LON,TOR_LENGTH,TOR_WIDTH), as.numeric), date=sprintf("%s-%02d", substr(BEGIN_YEARMONTH,1,4), 0) )
ev$ymd <- paste0(substr(ev$BEGIN_YEARMONTH,1,4), "-", substr(ev$BEGIN_YEARMONTH,5,6), "-", sprintf("%02d", as.integer(ev$BEGIN_DAY)))
cat("NCEI tornado events in those years:", nrow(ev), "; with non-missing begin lat/lon:", sum(!is.na(ev$BEGIN_LAT) & !is.na(ev$BEGIN_LON)), "; with non-missing end lat/lon:", sum(!is.na(ev$END_LAT)&!is.na(ev$END_LON)), "\n")
# match: same state, same date, begin within 0.05 deg (SPC early coords rounded to 0.01)
res <- lapply(seq_len(nrow(smp)), function(i) { s <- smp[i,]; c <- ev[ev$STATE==state_name[[s$st]] & ev$ymd==s$date & !is.na(ev$BEGIN_LAT) & abs(ev$BEGIN_LAT-s$slat)<=0.05 & abs(ev$BEGIN_LON-s$slon)<=0.05, ]
  if (!nrow(c)) return(data.frame(tornado_id=s$tornado_id, matched=FALSE)); c <- c[which.min(abs(c$BEGIN_LAT-s$slat)+abs(c$BEGIN_LON-s$slon)),]
  data.frame(tornado_id=s$tornado_id, matched=TRUE, ncei_blat=c$BEGIN_LAT, ncei_blon=c$BEGIN_LON, ncei_elat=c$END_LAT, ncei_elon=c$END_LON, ncei_len=c$TOR_LENGTH, ncei_wid=c$TOR_WIDTH) })
r <- left_join(smp %>% select(tornado_id, era, year, st, mag, spc_len=len, spc_wid=wid, slat, slon, elat, elon), bind_rows(res), by="tornado_id") %>% mutate(
  end_present = !is.na(ncei_elat) & !is.na(ncei_elon) & !(ncei_elat==0 & ncei_elon==0),
  dlat=abs(ncei_elat-ncei_blat), dlon=abs(ncei_elon-ncei_blon), dist_deg=sqrt(dlat^2+dlon^2), distinct_end = end_present & dist_deg > 0.0005)
print(r %>% group_by(era) %>% summarise(sampled=n(), matched=sum(matched), end_coords_present=sum(end_present, na.rm=TRUE), distinct_end=sum(distinct_end, na.rm=TRUE), distinct_end_gt_0.01deg=sum(dist_deg>0.01, na.rm=TRUE)))
cat("\nfull table (matched only):\n"); print(r %>% filter(matched) %>% transmute(tornado_id, era, st, mag, spc_len, ncei_len, spc_wid, ncei_wid, dist_deg=round(dist_deg,4), distinct_end) %>% as.data.frame(), row.names=FALSE)
cat("\nof distinct-end matches: NCEI TOR_LENGTH vs SPC len correlation / median ratio: "); d <- r %>% filter(distinct_end, !is.na(ncei_len), spc_len>0); cat(nrow(d), "rows; median ncei/spc len:", signif(median(d$ncei_len/d$spc_len),3), "\n")
cat("implied NCEI start-end geodesic length (mi) vs NCEI TOR_LENGTH for distinct ends:\n")
if (nrow(d)) { g <- sapply(seq_len(nrow(d)), function(i) as.numeric(sf::st_distance(sf::st_sfc(sf::st_point(c(d$ncei_blon[i], d$ncei_blat[i])), sf::st_point(c(d$ncei_elon[i], d$ncei_elat[i])), crs=4326))[1,2])/1609.344); print(signif(summary(g/d$ncei_len),3)) }
saveRDS(r, qa_out("d9_result.rds"))
