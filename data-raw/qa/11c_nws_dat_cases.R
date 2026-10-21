# Run from the package root: Rscript data-raw/qa/11c_nws_dat_cases.R
source("data-raw/qa/helpers.R")
suppressMessages({library(sf); library(dplyr)}); options(width=170); sf_use_s2(FALSE)
source("R/path_polygon.R"); load("data/tornado_tracks.rda")
B <- "https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer"
qry <- function(layer, where, bbox=NULL) { u <- paste0(B,"/",layer,"/query?where=",URLencode(where, reserved=TRUE), if (!is.null(bbox)) sprintf("&geometry=%f,%f,%f,%f&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects", bbox[1],bbox[2],bbox[3],bbox[4]) else "", "&outFields=*&outSR=4326&returnGeometry=true&resultRecordCount=2000&f=geojson"); read_sf(u, quiet=TRUE) }
cases <- list(Joplin=c("2011_1105221634-01","2011-05-22"), Moore=c("2013_1305201356-01","2013-05-20"), Mayfield=c("2021_2112102054-01","2021-12-10"), `Tuscaloosa-Birmingham`=c("2011_1104271543-01","2011-04-27"), Rainsville=c("2011_1104271719-01","2011-04-27"))
out <- list(); geoms <- list(); cases_out <- list()
for (nm in names(cases)) { id <- cases[[nm]][1]; dt <- as.Date(cases[[nm]][2]); tr <- tornado_tracks[tornado_tracks$tornado_id==id,]; bb <- st_bbox(tr)
  box <- c(bb["xmin"]-.3, bb["ymin"]-.3, bb["xmax"]+.3, bb["ymax"]+.3)
  wh <- sprintf("stormdate >= timestamp '%s 00:00:00' AND stormdate < timestamp '%s 00:00:00'", dt-1, dt+2)
  L <- qry(1, wh, box); if (!nrow(L)) { cat("\n==", nm, ": no DAT survey line found\n"); next }
  spc <- st_coordinates(tr)[c(1,nrow(st_coordinates(tr))), 1:2]
  dd <- sapply(seq_len(nrow(L)), function(i) { cc <- st_coordinates(L[i,])[, 1:2, drop=FALSE]; a <- cc[1,]; b <- cc[nrow(cc),]; min(sqrt(sum((a-spc[1,])^2))+sqrt(sum((b-spc[2,])^2)), sqrt(sum((a-spc[2,])^2))+sqrt(sum((b-spc[1,])^2))) })
  line <- L[which.min(dd),]; cat("\n==", nm, id, "== DAT line:", line$event_id, "| EF", line$efscale, "| length", line$length, "mi | width", line$width, "yd | deaths", line$fatalities, "| injuries", line$injuries, "| wfo", line$wfo, "| endpoint mismatch (deg):", round(min(dd),3), "\n")
  PP <- qry(2, wh, box); lineg <- st_geometry(line)
  P <- if (nrow(PP)) PP[lengths(st_intersects(st_make_valid(st_geometry(PP)), lineg)) > 0, ] else PP
  # same swath filter as the survey layer (data-raw/survey/pairing_functions.R): rated EF0-EF5 zones with >= 90% of their area within the SPC path width (+500 m) of the centerline
  if (nrow(P)) { buf <- st_buffer(st_transform(lineg, 5070), tr$wid_yd*0.9144 + 500); P5x <- st_make_valid(st_transform(st_geometry(P), 5070))
    inb <- vapply(seq_len(nrow(P)), function(k) as.numeric(st_area(st_intersection(P5x[k], buf)))/as.numeric(st_area(P5x[k])), numeric(1))
    P <- P[P$efscale %in% paste0("EF", 0:5) & inb >= 0.9, ] }
  cat("  swath polygons in the box:", nrow(PP), "; intersecting the surveyed centerline:", nrow(P), if (nrow(P)) paste0("(EF zones: ", paste(sort(unique(P$efscale)), collapse=","), ")") else "", "\n")
  surv <- st_transform(st_cast(st_geometry(line), "LINESTRING"), 5070)
  mod_poly <- .path_polygon(tr, tr$wid_yd, tr$len_mi, tr$track_type); mod_line <- st_transform(st_geometry(tr), 5070)
  # sample the surveyed centerline every 250 m and the modeled line likewise
  smp <- function(g, step=250) { n <- max(2, ceiling(as.numeric(st_length(g))/step)+1); st_line_sample(g, n=n) %>% st_cast("POINT") }
  sp <- smp(surv); d_s2m <- as.numeric(st_distance(sp, mod_line)); mp <- smp(mod_line); d_m2s <- as.numeric(st_distance(mp, surv))/1000
  q <- function(x) signif(quantile(x/1000, c(.5,.9,1)), 3)
  cat(sprintf("  surveyed centerline %.1f mi (SPC straight chord %.1f mi, SPC len %.2f mi, DAT length %.2f mi); distance from surveyed centerline to modeled line (km): median %.2f, p90 %.2f, max %.2f; mean %.2f\n", as.numeric(st_length(surv))/1609.344, as.numeric(st_length(st_transform(tr,5070)))/1609.344, tr$len_mi, line$length, q(d_s2m)[1], q(d_s2m)[2], q(d_s2m)[3], mean(d_s2m)/1000))
  cat(sprintf("  distance from modeled line to surveyed centerline (km): median %.2f, p90 %.2f, max %.2f\n", quantile(d_m2s,.5), quantile(d_m2s,.9), max(d_m2s)))
  mod_half <- tr$wid_yd*0.9144/2/1000; cat(sprintf("  modeled half-width %.2f km; share of surveyed-centerline samples farther than that from the modeled line: %.0f%%\n", mod_half, 100*mean(d_s2m/1000 > mod_half)))
  if (nrow(P)) { sw <- st_union(st_make_valid(st_transform(st_geometry(P), 5070))); mp5 <- st_make_valid(mod_poly[[1]] %>% st_sfc(crs=5070)); inter <- as.numeric(st_area(st_intersection(sw, mp5)))
    cat(sprintf("  surveyed swath area %.1f km2 (union of polygons); modeled polygon %.1f km2 (ratio modeled/surveyed %.2f); share of surveyed swath inside modeled polygon: %.1f%%; share of modeled polygon inside surveyed swath: %.1f%%\n", as.numeric(st_area(sw))/1e6, as.numeric(st_area(mp5))/1e6, as.numeric(st_area(mp5))/as.numeric(st_area(sw)), 100*inter/as.numeric(st_area(sw)), 100*inter/as.numeric(st_area(mp5)))) }
  cases_out[[nm]] <- data.frame(case=nm, tornado_id=id, median_km=median(d_s2m)/1000, max_km=max(d_s2m)/1000, modeled_half_width_km=mod_half, pct_beyond_half_width=100*mean(d_s2m/1000 > mod_half),
    modeled_km2=as.numeric(st_area(st_sfc(mod_poly[[1]], crs=5070)))/1e6, swath_km2=if (nrow(P)) as.numeric(st_area(sw))/1e6 else NA_real_,
    pct_swath_in_modeled=if (nrow(P)) 100*inter/as.numeric(st_area(sw)) else NA_real_, n_polygons=nrow(P))
  geoms[[nm]] <- list(surv=surv, model=mod_line, mpoly=mod_poly, swath=if (nrow(P)) st_union(st_make_valid(st_transform(st_geometry(P), 5070))) else NULL)
}
saveRDS(geoms, qa_out("dat_geoms.rds")); saveRDS(do.call(rbind, cases_out), qa_out("dat_cases.rds"))
