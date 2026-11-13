# tornadoexposure
`tornadoexposure` provides ZCTA-level tornado exposure data for the United States, 1996 to
2025, ready to use without assembling it from raw sources. A ZCTA (ZIP Code Tabulation Area) is the
Census Bureau's approximation of a ZIP code area. The tornado records come from the NOAA Storm Prediction Center
(SPC) and are combined with Census Bureau ZCTA boundaries and block populations; the National Weather Service (NWS)
damage surveys are included unmodified and linked to the SPC tornadoes. In each call you choose how a
ZCTA counts as exposed: the tornado touched it, the modeled path covers a given share of its area or residents, or
its centroid or boundary is within a given distance of the SPC line. The data are bundled, so only maps and
boundary distances need an internet connection.

## Set-up
```r
remotes::install_github("UChicago-ExtremeWeather/tornadoexposure")
library(tornadoexposure)
```

## What the package provides
From the SPC (every tornado from 1996 on):

* `spc_records` (38,953 rows): the complete SPC record, every column and every row (whole-track rows, state segments and continuing county records), as SPC gives them.
* `tornado_tracks` (38,027 rows): one row per tornado. The geometry is the straight line from SPC's start to its end point, or a point at the start for a tornado with no usable end point (`track_type` is `"line"` or `"point"`; end coordinates missing, 0 or equal to the start: 10,384 tornadoes, 27.3%). SPC's raw coordinates, length and width stay as given; loss is given as SPC gives it and in dollars.
* `tornado_exposure` (57,754 rows): one row per tornado and ZCTA touched, with the distance from the SPC line to the ZCTA boundary and to its population-weighted centroid, and the `modeled_*` columns (the modeled path polygon: the SPC line at SPC's width).

From the NWS Damage Assessment Toolkit (DAT), every feature the service holds, with every field, at full resolution and unmodified:

* `dat_lines` (13,021), `dat_polygons` (11,172) and `dat_points` (241,456).
* `tornado_dat_link` (11,573 rows): the DAT lines linked to SPC tornadoes, with every number that describes the link. `dat_polygon_line_link` (466,150 rows): the distance between each polygon and each line dated within a day, and the share of the line inside the polygon.

From the Census Bureau:

* `zcta_centroids` (98,932 rows): population-weighted centroids and areas, per ZCTA and Census boundary year (2000, 2010, 2020). Full TIGER/Line ZCTA boundaries and block populations are used to build the tables and are not shipped.

The main variables of `tornado_exposure` (all are described in `?tornado_exposure`):

| Variable | Description |
|---|---|
| `tornado_id`, `date`, `year` | SPC year and SPC's record number for the tornado, joined (e.g. `2011_1105221634-01`); date |
| `magnitude` | EF rating 0 to 5 (the original Fujita scale before 2007), `NA` if unknown |
| `total_injury`, `total_fatality` | whole-tornado totals, repeated on each ZCTA row |
| `property_loss_tornado_total` / `modeled_property_loss_allocated` | SPC loss in dollars, whole tornado / the part assigned to the ZCTA by `modeled_area_share_of_tornado`; `NA` if SPC recorded 0: 19,567 of 38,027 tornadoes |
| `ZCTA` | five-character ZCTA code |
| `boundary_dist_km`, `centroid_dist_km` | distance in km from the SPC line (or start point) to the ZCTA boundary (0 if touched) and to its population-weighted centroid |
| `modeled_area_prop` | modeled path area inside the ZCTA divided by the area of the full ZCTA polygon (not capped) |
| `modeled_area_share_of_tornado` | share of the tornado's modeled path area that lies in this ZCTA |
| `modeled_pop_affected`, `modeled_pop_prop` | residents in the modeled path (fractional, because blocks are split by area); ratio to `zcta_pop` |
| `zcta_polygon_area_m2`, `zcta_land_area_m2`, `zcta_pop` | area of the full ZCTA polygon, Census land area (`ALAND`), residents |

The `modeled_*` columns come from a straight line at SPC's single width, which this package treats as the maximum width (NWS instructions define it so;
sources in `data-raw/known_issues.md`). They are approximations, not a damage boundary: against the NWS damage polygons of the linked survey line (the 2,947 tornadoes with a usable damage swath; the comparison is defined in `data-raw/known_issues.md`), the modeled path area is
a median of 1.18 times the polygon area (10th to 90th percentile 0.41 to 2.03), the modeled area share of a ZCTA is
1.21 times (0.37 to 2.99), the resident share 1.16 times (0.29 to 3.60),
and the two sets of ZCTAs agree for 91.7% (pairs in both over pairs in either). They are noisy for any single tornado.

## Functions
All functions take named arguments; every row returned is an exposed ZCTA. The examples use the Joplin, Missouri
tornado (EF5, 22 May 2011) and the Moore, Oklahoma tornado (20 May 2013).

### `get_data()`
Returns a data frame with one row per exposed tornado-ZCTA pair.

* `geo_list`: ZCTAs or prefixes of 1 to 5 digits, as strings (`"648"`).
* `year_range`: years, for example `2011` or `2010:2015`.
* `magnitude`: ratings to keep (default all, including unknown). `1:5` keeps EF1 and above and drops unknown ratings; `c(1:5, NA)` keeps unknown ones too; `5` keeps only EF5.
* `area_thresh`, `pop_thresh`: the share (a proportion from 0 to 1; 0 is not allowed) of the ZCTA's area or residents that the modeled path must cover. They do not evaluate tornadoes with no modeled path shape.
* `centroid_dist_km`, `boundary_dist_km`: a positive number of km, with no upper limit; the ZCTA's population-weighted centroid (the average location of its residents, from census block locations weighted by population), or its boundary (full TIGER/Line polygon; a download of 524 MB for 2010 boundaries, cached), must be within this distance of the SPC line (or of the start point).

Use at most one of the last four (none means that the tornado touched the ZCTA). Every call prints how many tornadoes in the request have no usable end point (they are points, and the modeled columns are `NA`). Joplin, 2011, under

```r
get_data(geo_list = "648", year_range = 2011, magnitude = 5)[
  c("ZCTA", "modeled_area_prop")]
#>    ZCTA modeled_area_prop
#> 1 64804             0.100
#> 2 64840             0.144
#> 3 64844             0.039
```

```r
get_data(geo_list = "648", year_range = 2011, magnitude = 5,
         area_thresh = 0.05)[c("ZCTA", "modeled_area_prop")]
#>    ZCTA modeled_area_prop
#> 1 64804             0.100
#> 2 64840             0.144
```

```r
get_data(geo_list = "648", year_range = 2011, magnitude = 5,
         pop_thresh = 0.05)[c("ZCTA", "modeled_pop_prop")]
#>    ZCTA modeled_pop_prop
#> 1 64804            0.094
#> 2 64840            0.270
```

```r
get_data(geo_list = "648", year_range = 2011, magnitude = 5,
         centroid_dist_km = 10)[c("ZCTA", "centroid_dist_km")]
#>    ZCTA centroid_dist_km
#> 1 64801            6.895
#> 2 64804            1.075
#> 3 64840            1.019
#> 4 64841            6.378
#> 5 64844            8.022
```

```r
get_data(geo_list = "648", year_range = 2011, magnitude = 5,
         boundary_dist_km = 5)[c("ZCTA", "boundary_dist_km")]
#> Boundary distances use the full TIGER/Line ZCTA boundaries of 2010: a national file of about 524 MB, downloaded once and cached by tigris.
#>    ZCTA boundary_dist_km
#> 1 64801            2.494
#> 2 64804            0.000
#> 3 64840            0.000
#> 4 64844            0.000
#> 5 64850            1.177
#> 6 64862            3.028
```

The thresholds (0.05, 10 km and 5 km) are examples, not recommendations.

The centroid result includes ZCTAs the path did not touch (64801 and 64841 here), because the definition uses the centroid. Several full ZCTAs and years in one call (Moore area, EF4 and EF5 tornadoes of 2010 to 2013):

```r
get_data(geo_list = c("73160", "73165", "73170"), year_range = 2010:2013, magnitude = 4:5)[
  c("ZCTA", "date", "magnitude", "modeled_area_prop")]
#>    ZCTA       date magnitude modeled_area_prop
#> 1 73160 2010-05-10         4             0.167
#> 2 73165 2010-05-10         4             0.183
#> 3 73170 2011-05-24         4             0.020
#> 4 73160 2013-05-20         5             0.195
#> 5 73165 2013-05-20         5             0.059
#> 6 73170 2013-05-20         5             0.179
```

To save a result as a file, wrap the call in `write.csv()`:

```r
write.csv(get_data(geo_list = c("73160", "73165", "73170"), year_range = 2010:2013, magnitude = 4:5),
          "moore.csv", row.names = FALSE)
```

### `map_exposure()`
One map function. It takes the same arguments as `get_data()` and draws the layers named in `layers`: ZCTA, tract and block-group boundaries, SPC tracks, the NWS damage lines, damage polygons (colored by EF rating) and damage points, and, only on a map that has a DAT layer and labeled "modeled width, not a damage boundary", the modeled path rectangle (`"spc_path"`). `feature` fills the ZCTAs with a summary of the exposures: `"tornado_id"`
maps the number of tornadoes, `"magnitude"` the average rating, `"total_fatality"` and `"total_injury"` the sums. The injury and fatality columns hold whole-tornado totals repeated on each ZCTA row, so these sums are not totals of people: do not add the columns across ZCTAs for a count of people. Tornadoes with no usable end point are drawn as points.

```r
map_exposure(geo_list = "648", year_range = 2011, feature = "tornado_id")
#> Maps use the full TIGER/Line ZCTA boundaries of 2010: a national file of about 524 MB, downloaded once and cached by tigris.
```

![](figures/map-count-1.png)

Boundaries are the full TIGER/Line files and are downloaded from the Census Bureau the first time. The first `map_exposure()` call (2011 here) downloads a file of 524 MB and took about 17 seconds in testing; later calls use the cache. Years before 2010 use the 2000 boundaries (680 MB) and 2020 on the 2020 boundaries (528 MB). The function prints a note when a request is large or needs a large download.

### The NWS surveys and the St. Louis tornado of 16 May 2025
The National Weather Service surveyed the St. Louis tornado as two separate tornadoes from one storm circulation (an EF3 that lifted just north of Granite City and an EF1 that touched down just south of that point); SPC's file of 24 April 2026 predates that update of 15 May 2026 and holds one record. `tornado_dat_link` links that SPC record to both DAT lines, and `map_exposure()` draws the SPC line over them:

```r
tornado_dat_link[tornado_dat_link$tornado_id == "2025_2505161339-01",
  c("dat_line_id", "index_aligned_dist_km", "one_sided_dist_km", "rule")]
#>       dat_line_id index_aligned_dist_km one_sided_dist_km               rule
#> 10957     2671572                 8.989             1.294     mutual_closest
#> 10958     2671973                 9.105             1.478 attached_to_paired
```

```r
map_exposure(geo_list = c("62025", "62026", "62040", "62048", "63105", "63112", "63113", "63115", "63117",
                          "63120", "63124", "63130", "63133", "63147"),
             year_range = 2025, magnitude = 2,
             layers = c("zcta", "spc_tracks", "dat_polygons", "dat_lines"))
#> Maps use the full TIGER/Line ZCTA boundaries of 2020: a national file of about 528 MB, downloaded once and cached by tigris.
```

![](figures/map-stl-1.png)

## What is and is not done to the source data
The data start in 1996, as the original package did; SPC's file begins in 1950 and no reason for the 1996 start is documented. The package never rounds, snaps, simplifies, generalizes, caps or imputes a source value or geometry: SPC's coordinates, length, width, rating, injuries, deaths and loss are as SPC gives them (the loss in dollars is an exact conversion, and the raw value is kept), the DAT features are as the service gives them (dates are kept as milliseconds with a UTC copy), and the Census inputs are used as published. The operations that are applied, each with the number of records or features it touches, are listed in `data-raw/known_issues.md` (section "What is and is not done to the source data"): projection, merging polygons and repairing invalid geometry.

A modeled path is a straight line at SPC's single width. It is not a damage boundary at scales finer than a kilometer: the largest distance between the surveyed centerline and the SPC line has a median of 0.23 km and a 90th percentile of 1.78 km for the 11,369 line tornadoes linked to a survey line (`data-raw/known_issues.md`, section "Modeled columns", gives the values by length).

## Limitations
Numbers for each point, and how they were computed: `data-raw/known_issues.md`.

* Each modeled path is a straight line from SPC's start point to its end point, drawn with SPC's width (`wid`), which this package treats as the maximum width (NWS instructions for Storm Data define the width entered
  as the maximum; source in `data-raw/known_issues.md`). Real paths also curve and their width varies (see the comparison with the NWS damage polygons above).
* Coordinates before 2007 are given by SPC to 0.01 degrees (about 1.1 km of latitude); from 2007 they have
  0.0001 degrees (about 11 m). In a simulation that moves the coordinates by the rounding amount (1,000 tornadoes per period), the list of ZCTAs
  changes for 4.2% of tornadoes before 2007 and 0.2% from 2007 (per replicate).
* A tornado with no usable end point (start equal to end, or an end that is zero or missing) is a point at its start, because its direction is unknown: 10,384 tornadoes (27.3% of all). The real path may extend up to the reported length from the start in an unknown direction, so no path shape is modeled, the `modeled_*` columns are `NA`, and such a tornado has one row, the ZCTA that contains the start point. Most are EF0 and short, but SPC gives a length for nearly all of them and some are long (`data-raw/known_issues.md`, section "Tornadoes with no usable end point"). A width of 0 or missing (138 line tornadoes) is never replaced: such a line has no modeled path polygon and its `modeled_*` columns are `NA`.
* `modeled_pop_affected` counts the total residents (all ages) of the census blocks the modeled path covers, assuming residents are spread evenly over each block. It uses the 2000 census for tornadoes before 2010, the 2010 census for 2010 to 2019 and the 2020 census from 2020. The 2020 block counts have disclosure-avoidance noise added by the Census Bureau.
* Exposure uses the Census boundary year (2000, 2010 or 2020) that matches the tornado's year: 2000 before 2010, 2010 for 2010 to 2019, 2020 from 2020. The same ZCTA code can cover a different area in different boundary years: 8.2% of the codes in both the 2010 and 2020 files overlap by less than half (intersection over union).
* 644 tornadoes (1.7%) touch no ZCTA and have no rows in `tornado_exposure`: 115 are over water, 397 are over land with no ZCTA nearby, 132 are on land that is mostly covered by no ZCTA.
* Unknown ratings (`NA`) appear only from 2007: 1,546 tornadoes, 0 before 2007. EF0 counts across years are comparable only if unknown ratings are included: in 2023, 442 tornadoes are EF0 and 268 are unknown.
* SPC loss is `NA` where SPC recorded 0 (which NOAA says does not mean $0): 19,567 of
  38,027 tornadoes. SPC reports loss in millions of dollars before 2007 and in dollars from 2007; the package converts everything to dollars. The values are nominal (not adjusted for inflation).
* `tornado_id` is unique within a package version but is not stable across SPC releases from 2007 on.
* The DAT data are preliminary; the dataset is described by its stewards as intended for public access and use ([NOAA Damage Assessment Toolkit page](https://disasters-geoplatform.hub.arcgis.com/pages/noaa-damage-assessment-toolkit-dat)). No license text was found, and this package does not claim that the data are in the public domain. The accuracy of the NWS damage polygons has not been measured. Surveys do not cover every tornado (coverage grows from a few tornadoes in 2007 to most in 2025). `tornado_dat_link` has no cutoff: 474 of its 11,573 links have a one-sided distance above 5 km (an example, not a recommendation), so filter on the distance columns for your purpose.

## Citation
Data sources:

* NOAA Storm Prediction Center, [Severe Weather Database](https://www.spc.noaa.gov/wcm/) (accessed 2026-10-12).
* U.S. Census Bureau, TIGER/Line ZCTA boundary files for [2000](https://www2.census.gov/geo/tiger/TIGER2010/ZCTA5/2000/), [2010](https://www2.census.gov/geo/tiger/TIGER2010/ZCTA5/2010/) and [2020](https://www2.census.gov/geo/tiger/TIGER2020/ZCTA520/) (accessed 2026-10-12).
* U.S. Census Bureau, TIGER/Line tabulation block files ([2000](https://www2.census.gov/geo/tiger/TIGER2010/TABBLOCK/2000/), [2010](https://www2.census.gov/geo/tiger/TIGER2010/TABBLOCK/2010/), [2020](https://www2.census.gov/geo/tiger/TIGER2020/TABBLOCK20/)); the 2020 files also hold the 2020 block population (accessed 2026-10-12).
* U.S. Census Bureau, decennial population counts for 2000 and 2010 ([PL 94-171 redistricting files, 2000](https://www2.census.gov/census_2000/datasets/redistricting_file--pl_94-171/) and [2010](https://www2.census.gov/census_2010/01-Redistricting_File--PL_94-171/)) (accessed 2026-10-12).
* NOAA National Weather Service [Damage Assessment Toolkit](https://apps.dat.noaa.gov/StormDamage/DamageViewer/) (queried 2026-11-11).

To cite the package, use the DOI of the archived release:
**To cite the package, use https://doi.org/10.5281/zenodo.23544841**.
See `citation("tornadoexposure")`.

## Acknowledgements
This work was supported by the Institute for Climate and Sustainable Growth (ISCG) and the Center
for Climate, Health and Society (CHAS).
