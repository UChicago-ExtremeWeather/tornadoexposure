# Run from the package root: Rscript data-raw/qa/05_ncei_loss_check.R
source("data-raw/qa/helpers.R")
suppressMessages({library(dplyr)}); options(width=170)
raw <- read.csv(qa_spc_csv(), stringsAsFactors=FALSE) %>% mutate(tornado_id=paste(yr,om,sep="_"))
parse_dmg <- function(x) { m <- c(K=1e3, M=1e6, B=1e9); n <- suppressWarnings(as.numeric(sub("[KMB]$","",x))); u <- sub("^[0-9.]+","",x); ifelse(x=="" | is.na(n), NA, n*ifelse(u %in% names(m), m[u], 1)) }
dir <- qa_cache("ncei")
get_ev <- function(y) { f <- qa_ncei_file(y); d <- read.csv(f, stringsAsFactors=FALSE, colClasses="character"); d <- d[d$EVENT_TYPE=="Tornado",]; for (v in c("BEGIN_LAT","BEGIN_LON","END_LAT","END_LON","DEATHS_DIRECT","DEATHS_INDIRECT","INJURIES_DIRECT","INJURIES_INDIRECT","TOR_LENGTH","TOR_WIDTH")) d[[v]] <- as.numeric(d[[v]]); d$prop <- parse_dmg(d$DAMAGE_PROPERTY); d$crop <- parse_dmg(d$DAMAGE_CROPS); d }
cmp <- function(id, pad=0.12) {
  s <- raw %>% filter(tornado_id==id, sg==1)
  cat("\n=====", id, "=====\nSPC (whole-track record):\n"); print(s %>% select(st, date, mag, fat, inj, loss, len, wid, slat, slon, elat, elon), row.names=FALSE)
  base <- sub("-[0-9]+$","", s$om); seg <- raw %>% filter(yr==s$yr, sub("-[0-9]+$","",om)==base, sg!=1)
  if (nrow(seg)) { cat("SPC state-segment rows with the same base om:\n"); print(seg %>% select(om, st, sn, sg, mag, fat, inj, loss, len, wid), row.names=FALSE) }
  ev <- get_ev(s$yr); lon <- range(c(s$slon, s$elon)); lat <- range(c(s$slat, s$elat))
  near <- ev %>% filter(BEGIN_LAT >= lat[1]-pad, BEGIN_LAT <= lat[2]+pad, BEGIN_LON >= lon[1]-pad, BEGIN_LON <= lon[2]+pad, substr(BEGIN_YEARMONTH,1,6)==format(as.Date(s$date), "%Y%m"), abs(as.integer(BEGIN_DAY)-as.integer(format(as.Date(s$date), "%d"))) <= 1)
  cat("NCEI Storm Events tornado events within the path box on that date (+-1 day):", nrow(near), "\n")
  print(near %>% arrange(BEGIN_DATE_TIME) %>% transmute(EVENT_ID, EPISODE_ID, STATE, CZ_NAME, BEGIN_DATE_TIME, TOR_F_SCALE, BEGIN_LAT, BEGIN_LON, END_LAT, END_LON, TOR_LENGTH, TOR_WIDTH, dth=DEATHS_DIRECT, dth_ind=DEATHS_INDIRECT, inj=INJURIES_DIRECT, DAMAGE_PROPERTY), row.names=FALSE)
  cat(sprintf("NCEI totals over these events: direct deaths %d, indirect deaths %d, direct injuries %d, property damage %s (NA events: %d), crop damage %s; sum of TOR_LENGTH %.1f mi\n", sum(near$DEATHS_DIRECT), sum(near$DEATHS_INDIRECT), sum(near$INJURIES_DIRECT), format(sum(near$prop, na.rm=TRUE), big.mark=",", scientific=FALSE), sum(is.na(near$prop)), format(sum(near$crop, na.rm=TRUE), big.mark=",", scientific=FALSE), sum(near$TOR_LENGTH, na.rm=TRUE)))
  invisible(near) }
a <- cmp("2021_2112102054-01"); b <- cmp("2011_1104271719-01")

# numbers quoted in data-raw/known_issues.md (read by check_documented_claims.R)
# The NCEI county segments of the Mayfield tornado: start at the segment that begins at SPC's start point and follow the segments whose
# beginning coincides (within 0.001 degrees) with the end of one already taken. (The box around the path also holds other tornadoes.)
spc <- raw %>% filter(tornado_id == "2021_2112102054-01", sg == 1)
a$key <- seq_len(nrow(a)); took <- which(abs(a$BEGIN_LAT - spc$slat) < 0.001 & abs(a$BEGIN_LON - spc$slon) < 0.001); first <- took[1]
repeat { nxt <- setdiff(which(vapply(seq_len(nrow(a)), function(i) any(abs(a$BEGIN_LAT[i] - a$END_LAT[took]) < 0.001 & abs(a$BEGIN_LON[i] - a$END_LON[took]) < 0.001), TRUE)), took); if (!length(nxt)) break; took <- c(took, nxt) }
seg <- a[took, ]
ev301829 <- b[b$EVENT_ID == "301829", ]
saveRDS(list(mayfield_segments = nrow(seg), mayfield_last_end_lat = seg$END_LAT[which.max(seg$BEGIN_DATE_TIME == max(seg$BEGIN_DATE_TIME))], spc_end_lat = spc$elat, mayfield_deaths = sum(seg$DEATHS_DIRECT), mayfield_injuries = sum(seg$INJURIES_DIRECT),
             mayfield_first_segment_damage = a$prop[first], mayfield_first_segment_cz = a$CZ_NAME[first], mayfield_first_segment_state = a$STATE[first],
             mayfield_ef4_damage_missing = all(is.na(seg$prop[seg$TOR_F_SCALE == "EF4"])), mayfield_n_ef4 = sum(seg$TOR_F_SCALE == "EF4"),
             e301829_deaths = ev301829$DEATHS_DIRECT, e301829_injuries = ev301829$INJURIES_DIRECT, e301829_damage = ev301829$prop), qa_out("documented_05.rds"))
