# Run from the package root: Rscript data-raw/qa/11f_nws_plot_paths.R
source("data-raw/qa/helpers.R")
suppressMessages({library(sf); library(ggplot2); library(gridExtra)}); sf_use_s2(FALSE)
g <- readRDS(qa_out("dat_geoms.rds"))
mk <- function(nm, title) { x <- g[[nm]]; sw <- if (!is.null(x$swath)) st_sf(layer="NWS surveyed damage swath", geometry=x$swath) else NULL
  mp <- st_sf(layer="Modeled path polygon", geometry=st_sfc(x$mpoly[[1]], crs=5070)); ml <- st_sf(layer="Modeled straight line", geometry=x$model); sv <- st_sf(layer="NWS surveyed centerline", geometry=x$surv)
  p <- ggplot() + { if (!is.null(sw)) geom_sf(data=sw, aes(fill=layer), color=NA, alpha=.55) } + geom_sf(data=mp, aes(fill=layer), color="#b2182b", alpha=.25, linewidth=.3) + geom_sf(data=ml, aes(color=layer), linewidth=.7) + geom_sf(data=sv, aes(color=layer), linewidth=.7) +
    scale_fill_manual(values=c("NWS surveyed damage swath"="#2166ac", "Modeled path polygon"="#b2182b"), name=NULL) + scale_color_manual(values=c("Modeled straight line"="#b2182b", "NWS surveyed centerline"="black"), name=NULL) + ggtitle(title) + theme_minimal(base_size=8) + theme(legend.position="bottom", legend.box="vertical", axis.text=element_text(size=5), plot.title=element_text(size=8))
  p }
pl <- list(mk("Mayfield","Mayfield KY 2021 (2021_2112102054-01)"), mk("Tuscaloosa-Birmingham","Tuscaloosa-Birmingham AL 2011"), mk("Moore","Moore OK 2013"))
png(qa_out("path_validation.png"), width=1500, height=600, res=130); grid.arrange(grobs=pl, ncol=3); dev.off()
