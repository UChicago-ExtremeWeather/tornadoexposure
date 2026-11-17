# tornadoexposure

`tornadoexposure` provides ZCTA-level tornado exposure data for the United States, 1996 to 2025, ready to use without assembling it from raw sources. A ZCTA (ZIP Code Tabulation Area) is the Census Bureau's approximation of a ZIP code area.

The package combines two tornado data sources with Census Bureau geography:

1. **SPC tornado records** (NOAA Storm Prediction Center): one record per tornado, with a start point, an end point and a width.
2. **NWS damage surveys** (NOAA National Weather Service Damage Assessment Toolkit, "DAT"): the NWS's own survey lines, damage polygons and damage points.

Both are described below. Data are bundled with the package, so only maps and boundary distances need an internet connection.

## Set-up
```r
remotes::install_github("UChicago-ExtremeWeather/tornadoexposure")
library(tornadoexposure)
```

## The two data sources

| | SPC tornado records | NWS damage surveys (DAT) |
|---|---|---|
| Provider | NOAA Storm Prediction Center | NOAA National Weather Service |
| What it describes | Every tornado, as a start point, end point and width | Where NWS surveyors mapped damage, as lines, polygons and points |
| Coverage | Every tornado from 1996 | Surveys do not cover every tornado. Coverage grows from a few tornadoes in 2007 to most in 2025 |
| Rating, injuries, fatalities, loss | Yes | Rating only (`efscale`) |
| Geometry in this package | A straight line from start to end, or a point at the start when there is no usable end point | Unmodified NWS shapes |
| Main tables | `spc_records`, `tornado_tracks` | `dat_lines`, `dat_polygons`, `dat_points` |

**SPC.** The package draws only the straight line between SPC's start and end points. It draws no polygon from the width. A tornado whose end is missing, 0 or equal to the start is stored as a point at its start (10,384 tornadoes, 27.3%).

**DAT.** Every feature the service holds is included at full resolution with every field. The DAT data are preliminary.

**Linking them.** `tornado_dat_link` links each DAT line to an SPC tornado and reports every number that describes the link (no cutoff applied). A DAT polygon belongs to a tornado when a linked DAT line touches it. Only polygons rated EF0 to EF5 are used.

## What the package provides

**Exposure table**

* `tornado_exposure` (57,407 rows, 37,382 tornadoes): one row per tornado and ZCTA exposed by either source. SPC columns describe the line, DAT columns describe the linked NWS polygons (`NA` for a tornado with no linked DAT line).
* `dat_exposure_tract` (8,005 rows) and `dat_exposure_blockgroup` (12,308 rows): DAT columns only, for census tracts and block groups. There are no SPC columns because SPC positions are not accurate enough to say which tract or block group a tornado crossed.

**SPC**

* `spc_records` (38,953 rows): the complete SPC record, every column and every row.
* `tornado_tracks` (38,027 rows): one row per tornado, with geometry.

**DAT**

* `dat_lines` (13,021), `dat_polygons` (11,172), `dat_points` (241,456).
* `tornado_dat_link` (11,573 rows) and `dat_polygon_line_link` (466,150 rows).

**Census**

* `zcta_centroids` (98,932 rows): population-weighted centroids and areas by ZCTA and boundary year (2000, 2010, 2020).

### Key variables in `tornado_exposure`
Full definitions are in `?tornado_exposure`.

| Variable | Description |
|---|---|
| `tornado_id`, `date`, `year` | SPC year and record number joined (e.g. `2011_1105221634-01`); date |
| `ZCTA` | Five-character ZCTA code |
| `magnitude` | EF rating 0 to 5 (original Fujita scale before 2007), `NA` if unknown |
| `total_injury`, `total_fatality` | Whole-tornado totals, repeated on each ZCTA row |
| `property_loss_tornado_total`, `property_loss_allocated` | SPC loss in nominal dollars for the whole tornado, and the part assigned to the ZCTA by `line_share_of_tornado`. `NA` where SPC recorded 0 |
| `spc_exposed`, `dat_exposed` | The SPC line crosses the ZCTA, and a linked NWS polygon covers land in it (`NA` without a link) |
| `line_km_in_zcta`, `line_share_of_tornado` | Kilometers of the line in the ZCTA, and its share of the whole line |
| `boundary_dist_km`, `centroid_dist_km` | Distance from the SPC line to the ZCTA boundary and to its population-weighted centroid |
| `dat_area_share`, `dat_area_share_ef0` to `_ef5` | Land-only share of the ZCTA covered by linked polygons, in all and by highest rating |
| `dat_pop_affected`, `dat_pop_ef0` to `_ef5` | Residents in that land, in all and by highest rating |
| `dat_points_ef0` to `_ef5`, `_efu`, `_wind`, `_other` | DAT damage points in the ZCTA dated within one day of the tornado, by `efscale` as entered |
| `other_tornadoes_in_zcta_within_a_day` | Other SPC tornadoes crossing the ZCTA within a day, to flag points that may belong to another tornado |

## Defining exposure
A ZCTA is exposed when the SPC line crosses it or a linked NWS polygon covers land in it. In each call you can instead require the ZCTA's population-weighted centroid or boundary to be within a distance of the SPC line. Use at most one of the two.

## Functions
All functions take named arguments. Examples use the Joplin, Missouri tornado (EF5, 22 May 2011).

### `get_data()`
Returns a data frame with one row per tornado-ZCTA pair.

* `geo_list`: ZCTAs or prefixes of 1 to 5 digits, as strings (`"648"`).
* `year_range`: years, for example `2011` or `2010:2015`.
* `magnitude`: ratings to keep (default all, including unknown). `1:5` keeps EF1 and above and drops unknown; `c(1:5, NA)` keeps unknown too.
* `centroid_dist_km`, `boundary_dist_km`: a positive distance in km, with no upper limit. Boundary distances download the full TIGER/Line boundaries (about 524 MB for 2010, cached).

Every call prints how many tornadoes in the request have no usable end point.

```r
get_data(geo_list = "648", year_range = 2011, magnitude = 5)[
  c("ZCTA", "spc_exposed", "dat_exposed", "line_km_in_zcta", "line_share_of_tornado")]
#>    ZCTA spc_exposed dat_exposed line_km_in_zcta line_share_of_tornado
#> 1 64804        TRUE          NA          16.952                 0.500
#> 2 64840        TRUE          NA          11.639                 0.343
#> 3 64844        TRUE          NA           5.297                 0.156
```

The DAT columns are `NA` because no NWS survey line is linked to the Joplin tornado.

```r
get_data(geo_list = "648", year_range = 2011, magnitude = 5, centroid_dist_km = 10)
get_data(geo_list = "648", year_range = 2011, magnitude = 5, boundary_dist_km = 5)
```

The distances are examples, not recommendations. To save a result:

```r
write.csv(get_data(geo_list = "648", year_range = 2011, magnitude = 5),
          "joplin.csv", row.names = FALSE)
```

### `map_exposure()`
Takes the same arguments as `get_data()` and draws the layers named in `layers`: `"zcta"`, tract and block-group boundaries, `"spc_tracks"`, `"dat_lines"`, `"dat_polygons"` (colored by EF rating) and damage points.

`feature` fills the ZCTAs: `"tornado_id"` maps the number of tornadoes, `"magnitude"` the average rating, `"total_fatality"` and `"total_injury"` the sums. Injury and fatality columns hold whole-tornado totals repeated on each ZCTA row, so these sums are not counts of people.

```r
map_exposure(geo_list = "648", year_range = 2011, feature = "tornado_id")
```

![](figures/map-count-1.png)

The first call downloads Census boundaries and caches them (2000 boundaries for years before 2010, 680 MB; 2010 for 2010 to 2019, 524 MB; 2020 from 2020, 528 MB).

### Example with both sources: St. Louis, 16 May 2025
The NWS surveyed this storm as two tornadoes (an EF3 and an EF1), while SPC's file holds one record. `tornado_dat_link` links the SPC record to both survey lines:

```r
tornado_dat_link[tornado_dat_link$tornado_id == "2025_2505161339-01",
  c("dat_line_id", "index_aligned_dist_km", "one_sided_dist_km", "rule")]
```

The SPC line crosses 12 ZCTAs and NWS polygons cover land in 13; 4 are exposed only by the polygons.

```r
map_exposure(geo_list = stl_z, year_range = 2025, magnitude = 2,
             layers = c("zcta", "spc_tracks", "dat_polygons", "dat_lines"))
```

![](figures/map-stl-1.png)

## Limitations
Counts and methods for each item are in `data-raw/known_issues.md`.

* **Straight lines.** The SPC line is straight from start to end. Real paths curve. `line_share_of_tornado` and `property_loss_allocated` assume damage is spread evenly along the line.
* **No usable end point.** 27.3% of tornadoes are stored as a point at the start. Such a tornado is exposed only in the ZCTA containing its start.
* **Coordinate precision.** Before 2007 SPC coordinates are rounded to 0.01 degrees (about 1.1 km of latitude); from 2007 to 0.0001 degrees (about 11 m). The list of exposed ZCTAs is sensitive to this before 2007.
* **Survey coverage.** DAT columns exist only for tornadoes with a linked survey line. Damage points are not linked to tornadoes by any rule.
* **Link quality.** `tornado_dat_link` has no cutoff. Filter on `one_sided_dist_km` and `dat_link_dist_km` for your purpose.
* **Unknown ratings.** 1,546 tornadoes have no rating (`NA`), mostly from 2016 on. Include them when comparing EF0 counts across years.
* **Loss.** SPC loss is `NA` where SPC recorded 0, which NOAA says does not mean $0. Values are nominal dollars.
* **Boundaries.** Exposure uses the Census boundary year matching the tornado year. The same ZCTA code can cover a different area across boundary years.
* **Population.** Residents are allocated from census blocks by the share of block land covered. 2020 counts include Census disclosure-avoidance noise.
* **`tornado_id`.** Unique within a package version, but not stable across SPC releases from 2007 on.
* **License.** No license text was found for the DAT data. This package does not claim they are in the public domain.

## Citation
To cite the package, use https://doi.org/10.5281/zenodo.23544841. See `citation("tornadoexposure")`.

Data sources:

* NOAA Storm Prediction Center, [Severe Weather Database](https://www.spc.noaa.gov/wcm/) (accessed 2026-10-12).
* NOAA National Weather Service [Damage Assessment Toolkit](https://apps.dat.noaa.gov/StormDamage/DamageViewer/) (queried 2026-11-11).
* U.S. Census Bureau, TIGER/Line ZCTA boundary files for [2000](https://www2.census.gov/geo/tiger/TIGER2010/ZCTA5/2000/), [2010](https://www2.census.gov/geo/tiger/TIGER2010/ZCTA5/2010/) and [2020](https://www2.census.gov/geo/tiger/TIGER2020/ZCTA520/) (accessed 2026-10-12).
* U.S. Census Bureau, TIGER/Line tabulation block files ([2000](https://www2.census.gov/geo/tiger/TIGER2010/TABBLOCK/2000/), [2010](https://www2.census.gov/geo/tiger/TIGER2010/TABBLOCK/2010/), [2020](https://www2.census.gov/geo/tiger/TIGER2020/TABBLOCK20/)); the 2020 files also hold block population (accessed 2026-10-12).
* U.S. Census Bureau, TIGER/Line water polygons ([2010](https://www2.census.gov/geo/tiger/TIGER2010/AREAWATER/), [2020](https://www2.census.gov/geo/tiger/TIGER2020/AREAWATER/)) (accessed 2026-11-12).
* U.S. Census Bureau, decennial population counts ([2000](https://www2.census.gov/census_2000/datasets/redistricting_file--pl_94-171/), [2010](https://www2.census.gov/census_2010/01-Redistricting_File--PL_94-171/)) (accessed 2026-10-12).

## Acknowledgements
This work was supported by the Institute for Climate and Sustainable Growth (ISCG) and the Center for Climate, Health and Society (CHAS).
