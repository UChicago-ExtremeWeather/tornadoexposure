# Aggregates a feature across ZCTAs: returns one row per ZCTA with a `value`.
generate_feature <- function(exposed_zctas,
                             feature = c("tornado_id", "magnitude",
                                         "total_fatality", "total_injury")) {
  feature <- match.arg(feature)
  z <- exposed_zctas$ZCTA
  value <- switch(
    feature,
    magnitude = tapply(exposed_zctas$magnitude, z,
                       function(x) if (all(is.na(x))) NA_real_ else mean(x, na.rm = TRUE)),
    tornado_id = tapply(exposed_zctas$tornado_id, z,
                        function(x) length(unique(x))),
    tapply(as.numeric(exposed_zctas[[feature]]), z, sum, na.rm = TRUE)
  )
  data.frame(ZCTA = names(value), value = as.numeric(value),
             stringsAsFactors = FALSE)
}

.feature_labels <- c(
  tornado_id = "Number of tornadoes",
  magnitude = "Average magnitude (EF)",
  total_fatality = "Fatalities (sum of tornado totals)",
  total_injury = "Injuries (sum of tornado totals)"
)

.map_layers <- c("zcta", "tract", "block_group", "spc_tracks", "dat_lines",
                 "dat_polygons", "dat_points")

.year_label <- function(year_range) {
  if (min(year_range) == max(year_range)) {
    as.character(min(year_range))
  } else {
    paste0(min(year_range), "-", max(year_range))
  }
}

# colors of the DAT damage polygons and points by efscale (values the service gives that are not
# EF0 to EF5 are drawn in their own colors: EFU, TSTM/Wind, and everything else in grey)
.ef_colors <- c(EF0 = "#fee08b", EF1 = "#fdae61", EF2 = "#f46d43", EF3 = "#d53e4f",
                `EF3+` = "#b2182b", EF4 = "#9e0142", EF5 = "#5e4fa2", EFU = "#6baed6",
                `TSTM/Wind` = "#74c476", other = "grey60")
.ef_class <- function(x) ifelse(x %in% names(.ef_colors), x, "other")

# Tract or block-group boundaries (full TIGER/Line) that intersect the box of `bnd`
.sub_boundaries <- function(bnd, layer, year) {
  stt <- tigris::states(cb = TRUE, year = 2020, progress_bar = FALSE)
  hit <- stt$STATEFP[lengths(sf::st_intersects(sf::st_transform(stt, sf::st_crs(bnd)),
                                               sf::st_as_sfc(sf::st_bbox(bnd)))) > 0]
  message("The ", if (layer == "tract") "tract" else "block group", " layer downloads the full TIGER/Line files of ",
          length(hit), " state(s) (tens to a few hundred MB each), cached by tigris.")
  fn <- if (layer == "tract") tigris::tracts else tigris::block_groups
  out <- do.call(rbind, lapply(hit, function(s) {
    x <- fn(state = s, year = year, cb = FALSE, progress_bar = FALSE)
    x[lengths(sf::st_intersects(sf::st_transform(x, sf::st_crs(bnd)), sf::st_as_sfc(sf::st_bbox(bnd)))) > 0, "geometry"]
  }))
  out
}

#' Map tornado exposure across ZCTAs, with the SPC and NWS survey data
#'
#' One map function. It takes the same arguments as [get_data()] and draws the
#' layers named in `layers` for the tornadoes that `get_data()` returns. Everything is
#' drawn as stored (projected to longitude and latitude, nothing simplified). No
#' polygon is drawn from SPC's width.
#'
#' Layers:
#' * `"zcta"`, `"tract"`, `"block_group"`: full TIGER/Line boundaries of the Census
#'   boundary year closest to the middle of `year_range` (2000, 2010 or 2020).
#'   ZCTAs are filled with `feature` if it is given. The files are large downloads
#'   (a national ZCTA file of about 524 to 680 MB, tract and block-group files by
#'   state); the function says what it downloads.
#' * `"spc_tracks"`: SPC's straight line from the start to the end point, drawn in black on top of the other layers, or a cross at
#'   the start for a tornado with no usable end point.
#' * `"dat_lines"`, `"dat_polygons"`, `"dat_points"`: the NWS damage-survey
#'   centerlines linked to the tornadoes ([tornado_dat_link]), the damage polygons that
#'   touch those lines ([dat_polygon_line_link], `line_share_in_polygon` above 0,
#'   colored by EF rating) and the damage points dated within one day of a
#'   tornado that lie inside the box of those lines and polygons (colored by EF
#'   rating, including EFU and TSTM/Wind). The caption gives the link distances. The
#'   linked selection is a display choice, not a data rule; the complete layers are
#'   [dat_lines], [dat_polygons] and [dat_points].
#'
#' A message is printed when a request is large (more than 2,000 damage points) or
#' needs a large boundary download.
#'
#' @inheritParams get_data
#' @param feature Name of the feature to fill ZCTAs with: `"tornado_id"` (number of
#'   tornadoes), `"magnitude"` (average magnitude), `"total_fatality"` or
#'   `"total_injury"`. If `NULL` (default), the ZCTAs are not filled.
#' @param layers Character vector of layers to draw, from `"zcta"`, `"tract"`,
#'   `"block_group"`, `"spc_tracks"`, `"dat_lines"`, `"dat_polygons"` and
#'   `"dat_points"`. The default is `c("zcta", "spc_tracks")`.
#'
#' @return A ggplot object.
#'
#' @examples
#' \donttest{
#' # needs internet access to download boundaries
#' map_exposure(geo_list = "648", year_range = 2011, magnitude = 5, feature = "tornado_id")
#' map_exposure(geo_list = "648", year_range = 2011, magnitude = 5,
#'              layers = c("zcta", "spc_tracks", "dat_polygons", "dat_lines"))
#' }
#'
#' @export
map_exposure <- function(geography = "zcta", geo_list, year_range,
                         feature = NULL, magnitude = c(0:5, NA),
                         centroid_dist_km = NULL, boundary_dist_km = NULL,
                         layers = c("zcta", "spc_tracks")) {
  v <- .validate_args(
    "map_exposure", geography,
    geo_list = if (missing(geo_list)) NULL else geo_list,
    year_range = if (missing(year_range)) NULL else year_range,
    magnitude = magnitude,
    thresholds = list(centroid_dist_km = centroid_dist_km,
                      boundary_dist_km = boundary_dist_km)
  )
  if (!is.null(feature) &&
      (!is.character(feature) || length(feature) != 1L ||
       !feature %in% names(.feature_labels))) {
    stop("feature must be NULL or one of: ",
         paste0('"', names(.feature_labels), '"', collapse = ", "), ".",
         call. = FALSE)
  }
  if (!is.character(layers) || !all(layers %in% .map_layers)) {
    stop("layers must be from: ", paste0('"', .map_layers, '"', collapse = ", "), ".", call. = FALSE)
  }
  dat_layers <- intersect(layers, c("dat_lines", "dat_polygons", "dat_points"))
  if (!is.null(feature) && "dat_polygons" %in% layers) {
    stop('feature fills the ZCTAs and "dat_polygons" fills the damage polygons; use one of them.', call. = FALSE)
  }
  if (!is.null(feature) && !"zcta" %in% layers) layers <- c("zcta", layers)

  exposures <- .select_exposures(v)
  ids <- unique(exposures$tornado_id)
  year_plot <- .plot_vintage(v$year_range)
  need_zcta <- any(c("zcta", "tract", "block_group") %in% layers)
  boundary <- if (need_zcta) get_geometry(v$geo_list, v$year_range) else NULL
  boundary_ll <- if (!is.null(boundary)) sf::st_transform(boundary, 4326)

  p <- ggplot2::ggplot()
  if ("tract" %in% layers || "block_group" %in% layers) {
    for (lay in intersect(c("tract", "block_group"), layers)) {
      sb <- .sub_boundaries(boundary, lay, year_plot)
      p <- p + ggplot2::geom_sf(data = sf::st_transform(sb, 4326), fill = NA,
                                color = if (lay == "tract") "grey55" else "grey75", linewidth = 0.2)
    }
  }
  if ("zcta" %in% layers) {
    if (!is.null(feature) && nrow(exposures) > 0L) {
      fill <- generate_feature(exposures, feature)
      boundary_ll$value <- fill$value[match(boundary_ll$ZCTA, fill$ZCTA)]
      p <- p + ggplot2::geom_sf(data = boundary_ll, ggplot2::aes(fill = .data$value), color = "black") +
        scico::scale_fill_scico(palette = "lajolla", na.value = "transparent", direction = -1) +
        ggplot2::labs(fill = .feature_labels[[feature]])
    } else {
      p <- p + ggplot2::geom_sf(data = boundary_ll, fill = NA, color = "black")
    }
  }

  caption <- NULL
  tr <- NULL
  if (length(ids) > 0L) {
    tr <- .tracks()[match(ids, .tracks()$tornado_id), ]
    tr$magnitude <- exposures$magnitude[match(ids, exposures$tornado_id)]
  }

  # DAT features of the linked tornadoes
  dl <- NULL; dp <- NULL; dpt <- NULL
  if (length(dat_layers) > 0L && length(ids) > 0L) {
    lk <- tornadoexposure::tornado_dat_link
    lk <- lk[lk$tornado_id %in% ids, ]
    if (nrow(lk) == 0L) {
      message("None of the ", length(ids), " tornadoes has a linked NWS damage-survey line (see ?tornado_dat_link), so no DAT feature is drawn.")
    } else {
      dl <- tornadoexposure::dat_lines[match(lk$dat_line_id, tornadoexposure::dat_lines$objectid), ]
      pl <- tornadoexposure::dat_polygon_line_link
      pl <- pl[pl$dat_line_id %in% lk$dat_line_id & pl$line_share_in_polygon > 0, ]
      dp <- tornadoexposure::dat_polygons[tornadoexposure::dat_polygons$objectid %in% pl$dat_polygon_id, ]
      box <- sf::st_bbox(sf::st_union(c(sf::st_geometry(dl), sf::st_geometry(dp))))
      if ("dat_points" %in% layers) {
        pts <- tornadoexposure::dat_points
        day <- 86400000
        dts <- unique(as.numeric(as.Date(tr$date)) * day)
        ok <- !is.na(pts$stormdate) & vapply(pts$stormdate, function(x) any(abs(x - dts) <= day * 1.5), logical(1))
        pts <- pts[ok, ]
        xy <- sf::st_coordinates(pts)
        dpt <- pts[!sf::st_is_empty(pts) & xy[, 1] >= box[["xmin"]] & xy[, 1] <= box[["xmax"]] & xy[, 2] >= box[["ymin"]] & xy[, 2] <= box[["ymax"]], ]
        if (nrow(dpt) > 2000L) message("This map draws ", nrow(dpt), " damage points; drawing may take a while.")
      }
      one <- if (nrow(lk) <= 4L) paste0("tornado ", lk$tornado_id, " - DAT line ", lk$dat_line_id, ": index-aligned distance ",
                                         sprintf("%.2f", lk$index_aligned_dist_km), " km, one-sided ", sprintf("%.2f", lk$one_sided_dist_km), " km (", lk$rule, ")", collapse = "\n")
             else paste0(nrow(lk), " DAT lines linked to ", length(unique(lk$tornado_id)), " tornadoes; median index-aligned distance ",
                         sprintf("%.2f", stats::median(lk$index_aligned_dist_km)), " km")
      caption <- one
    }
  }
  if ("dat_polygons" %in% layers && !is.null(dp) && nrow(dp) > 0L) {
    dp$efclass <- factor(.ef_class(dp$efscale), levels = names(.ef_colors))
    p <- p + ggplot2::geom_sf(data = sf::st_transform(dp, 4326), ggplot2::aes(fill = .data$efclass), color = NA, alpha = 0.45) +
      ggplot2::scale_fill_manual(values = .ef_colors, name = "NWS damage polygon (EF)", drop = TRUE)
  }
  if (!is.null(dl) && "dat_lines" %in% layers) {
    p <- p + ggplot2::geom_sf(data = sf::st_transform(dl, 4326), color = "#08519c", linewidth = 0.6)
  }
  if (!is.null(dpt) && nrow(dpt) > 0L) {
    dpt$efclass <- .ef_class(dpt$efscale)
    p <- p + ggplot2::geom_sf(data = sf::st_transform(dpt, 4326), ggplot2::aes(color = .data$efclass), size = 0.6, alpha = 0.8) +
      ggplot2::scale_color_manual(values = .ef_colors, name = "NWS damage point (EF)")
  }
  if ("spc_tracks" %in% layers && !is.null(tr)) {
    ln <- tr[tr$track_type == "line", ]; pt <- tr[tr$track_type == "point", ]
    p <- p + .spc_layers(ln, pt)
  }
  title <- paste0("Tornado exposures, ", .year_label(v$year_range))
  subtitle <- if (v$definition == "exposed") {
    "Exposed = the SPC line crosses the ZCTA, or a linked NWS damage polygon covers land in it"
  } else if (v$definition == "centroid_dist_km") {
    paste0("ZCTA centroid within ", v$threshold, " km of the SPC line")
  } else {
    paste0("ZCTA boundary within ", v$threshold, " km of the SPC line")
  }
  p + ggplot2::labs(title = title, subtitle = subtitle, caption = caption) + ggplot2::theme_void() +
    ggplot2::theme(plot.caption = ggplot2::element_text(hjust = 0, size = 7), plot.caption.position = "plot")
}

# SPC lines (black) and start points (black crosses) so they stay visible over the DAT layers
.spc_layers <- function(ln, pt) {
  layers <- list()
  if (nrow(ln) > 0L) layers[[length(layers) + 1L]] <- ggplot2::geom_sf(data = sf::st_transform(ln, 4326), color = "black", linewidth = 0.8, inherit.aes = FALSE)
  if (nrow(pt) > 0L) layers[[length(layers) + 1L]] <- ggplot2::geom_sf(data = sf::st_transform(pt, 4326), color = "black", shape = 4, size = 2, inherit.aes = FALSE)
  layers
}
