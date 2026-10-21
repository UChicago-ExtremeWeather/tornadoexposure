# Run from the package root: Rscript data-raw/qa/15_pop_whole_block_checks.R [states] [vintages]
# Whole-block and internal-point checks for the 2000 and 2010 vintages (and
# 2020). ZCTAs are built from whole blocks, so for a random sample of blocks per
# state the share of the block's area inside the ZCTA that holds its internal
# point should be about 100%, and a block whose internal point is in no ZCTA should
# have about 0% of its area inside any ZCTA.
source("data-raw/qa/helpers.R"); source("data-raw/population/population_functions.R")
suppressMessages({library(dplyr)})
args <- commandArgs(trailingOnly = TRUE)
chk_states <- if (length(args)) strsplit(args[1], ",")[[1]] else c("il", "nj", "ma", "ca", "tx", "mo")
chk_vint <- if (length(args) > 1) as.integer(strsplit(args[2], ",")[[1]]) else c(2010L, 2000L, 2020L)
n_sample <- 4000; set.seed(15)
states <- pop_states(); area_or0 <- function(g) { a <- sf::st_area(g); if (length(a) == 0) 0 else sum(as.numeric(a)) }
res <- list()
for (v in chk_vint) { zl <- zcta_layer(v)
  for (ab in chk_states) { st <- states[states$abb == ab, ]
    b <- read_blocks(v, st$state_code, st$dir_name, st$abb)
    pts <- sf::st_as_sf(data.frame(GEOID = b$GEOID, lon = b$lon, lat = b$lat), coords = c("lon", "lat"), crs = 4269)
    bb <- sf::st_as_sfc(sf::st_bbox(b)); zsub <- zl[lengths(sf::st_intersects(zl, bb)) > 0, ]
    j <- sf::st_join(pts, zsub, join = sf::st_intersects); j <- j[!duplicated(j$GEOID), ]; b$ZCTA <- j$ZCTA[match(b$GEOID, j$GEOID)]
    # sample populated blocks (population matters) and all-block sample
    smp <- b[sample(nrow(b), min(n_sample, nrow(b))), ]
    smp5 <- sf::st_transform(sf::st_make_valid(smp), 5070); z5 <- sf::st_transform(zsub, 5070)
    a_blk <- as.numeric(sf::st_area(smp5))
    zun <- sf::st_union(sf::st_geometry(z5))
    in_any <- vapply(seq_len(nrow(smp5)), function(i) area_or0(sf::st_intersection(sf::st_geometry(smp5)[i], zun)), numeric(1))
    in_own <- vapply(seq_len(nrow(smp5)), function(i) { z <- smp5$ZCTA[i]; if (is.na(z)) return(NA_real_); area_or0(sf::st_intersection(sf::st_geometry(smp5)[i], sf::st_geometry(z5)[z5$ZCTA == z][1])) }, numeric(1))
    assigned <- !is.na(smp5$ZCTA)
    res[[length(res) + 1]] <- data.frame(vintage = v, state = ab, sampled = nrow(smp5), assigned = sum(assigned), unassigned = sum(!assigned),
      own_ge99 = mean(in_own[assigned] / a_blk[assigned] >= .99), own_ge95 = mean(in_own[assigned] / a_blk[assigned] >= .95), own_min = min(in_own[assigned] / a_blk[assigned]),
      unassigned_le1 = if (any(!assigned)) mean(in_any[!assigned] / a_blk[!assigned] <= .01) else NA_real_, unassigned_max = if (any(!assigned)) max(in_any[!assigned] / a_blk[!assigned]) else NA_real_,
      pop_zero_share = mean(smp5$pop == 0, na.rm = TRUE))
    message(v, " ", ab, " done") } }
out <- bind_rows(res); print(as.data.frame(out %>% mutate(across(where(is.numeric), ~ round(.x, 4)))), row.names = FALSE)
saveRDS(out, qa_out(paste0("pop_whole_block_", paste(chk_vint, collapse = "_"), "_", paste(chk_states, collapse = "_"), ".rds")))
