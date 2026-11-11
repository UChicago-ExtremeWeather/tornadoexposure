# Run from the package root:  Rscript data-raw/qa/51_dat_st_louis_extract.R [output.gpkg]
# Extracts the St. Louis tornado event of 15 to 17 May 2025 (NWS office LSX) from every layer of the live NWS Damage Assessment Toolkit service, with all fields, at full
# resolution (no generalization, no maxAllowableOffset, no geometryPrecision) and in the service's native spatial reference (nothing is reprojected).
# Writes one GeoPackage (default ~/tornadoexposure-st-louis-dat.gpkg, outside the repository) and a text file beside it with the queries, access date and counts.
suppressMessages({library(sf); library(jsonlite); library(dplyr)})
args <- commandArgs(TRUE); out <- if (length(args)) args[1] else path.expand("~/tornadoexposure-st-louis-dat.gpkg")
svc <- "https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer"
meta <- fromJSON(paste0(svc, "?f=json"), simplifyVector = FALSE); lay <- data.frame(id = vapply(meta$layers, `[[`, 1L, "id"), name = vapply(meta$layers, `[[`, "", "name"))
t0 <- "stormdate >= timestamp '2025-05-15 00:00:00' AND stormdate < timestamp '2025-05-18 00:00:00'"
q <- function(i, where, geom = NULL) {   # all pages; esri JSON in the native spatial reference
  res <- list(); off <- 0
  repeat {
    p <- list(where = where, outFields = "*", returnGeometry = "true", f = "json", resultOffset = off, resultRecordCount = 2000)
    if (!is.null(geom)) p <- c(p, list(geometry = geom, geometryType = "esriGeometryEnvelope", inSR = 4326, spatialRel = "esriSpatialRelIntersects"))
    u <- httr::GET(paste0(svc, "/", i, "/query"), query = p); j <- httr::content(u, as = "text", encoding = "UTF-8"); f <- tempfile(fileext = ".json"); writeLines(j, f)
    js <- fromJSON(j, simplifyVector = FALSE); if (!is.null(js$error)) stop(js$error$message)
    n <- length(js$features); if (n) res[[length(res) + 1]] <- st_read(f, quiet = TRUE)
    if (!isTRUE(js$exceededTransferLimit) || n == 0) break; off <- off + n }
  if (length(res)) do.call(rbind, res) else NULL }
lines <- q(1, paste0("wfo = 'LSX' AND ", t0))
bb <- st_bbox(lines); env <- paste(bb[["xmin"]] - 0.05, bb[["ymin"]] - 0.05, bb[["xmax"]] + 0.05, bb[["ymax"]] + 0.05, sep = ",")
points <- q(0, paste0("office = 'LSX' AND ", t0)); polys <- q(2, t0, env)
q_pts_bbox <- q(0, t0, env)
cat("native spatial reference of the returned geometries:", st_crs(lines)$input, "\n")
# the service stores dates as milliseconds since 1970-01-01 UTC; they are kept as received, and a readable UTC copy is added next to each date field
datef <- function(i) vapply(Filter(function(f) f$type == "esriFieldTypeDate", fromJSON(paste0(svc, "/", i, "?f=json"), simplifyVector = FALSE)$fields), `[[`, "", "name")
addutc <- function(x, i) { for (f in intersect(datef(i), names(x))) x[[paste0(f, "_utc")]] <- format(as.POSIXct(as.numeric(x[[f]]) / 1000, origin = "1970-01-01", tz = "UTC"), "%Y-%m-%d %H:%M:%S"); x }
lines <- addutc(lines, 1); points <- addutc(points, 0); polys <- addutc(polys, 2); q_pts_bbox <- addutc(q_pts_bbox, 0)
for (nm in c("lines", "points", "polygons")) { x <- get(if (nm == "polygons") "polys" else nm); if (!is.null(x)) { st_write(x, out, layer = paste0("dat_", nm), delete_layer = TRUE, quiet = TRUE) } }
fmt <- function(x) if (is.null(x)) "none" else as.character(nrow(x))
txt <- c(paste("File:", out), paste("Access date:", format(Sys.time(), "%Y-%m-%d %H:%M %Z")), paste("Service:", svc), paste("Layers of the service:", paste(lay$id, lay$name, collapse = "; ")),
 "Date fields are stored as received (milliseconds since 1970-01-01 UTC); a readable copy named <field>_utc is added beside each.", "Spatial reference: the service's native reference, WGS 84 (EPSG:4326); nothing was reprojected. No maxAllowableOffset, geometryPrecision or other generalization parameter was sent; all fields were requested (outFields=*).", "",
 paste0("Query lines (layer 1): where wfo = 'LSX' AND ", t0), paste0("Query points (layer 0): where office = 'LSX' AND ", t0),
 paste0("Query polygons (layer 2, which has no office field): where ", t0, " and the envelope xmin,ymin,xmax,ymax = ", env, " (the extent of the LSX lines plus 0.05 degrees), spatialRel intersects"),
 paste("Points inside the same envelope without the office filter (for comparison):", fmt(q_pts_bbox)), "", paste("Counts: lines", fmt(lines), "; points", fmt(points), "; polygons", fmt(polys)), "",
 paste("Fields of lines:", paste(setdiff(names(lines), "geometry"), collapse = ", ")), paste("Fields of points:", paste(setdiff(names(points), "geometry"), collapse = ", ")), paste("Fields of polygons:", paste(setdiff(names(polys), "geometry"), collapse = ", ")))
writeLines(txt, sub("\\.gpkg$", "_queries.txt", out)); cat(txt, sep = "\n")
saveRDS(list(lines = lines, points = points, polys = polys, pts_bbox = q_pts_bbox), file.path(tempdir(), "dat_st_louis.rds")); saveRDS(list(lines = lines, points = points, polys = polys, pts_bbox = q_pts_bbox), "/tmp/dat/dat_st_louis.rds")
