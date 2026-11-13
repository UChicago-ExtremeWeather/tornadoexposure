<!-- intro:start -->
# Known issues in the source data and the model

Numbers below were computed by the scripts in `data-raw/qa/` from the data built from the SPC file `1950-2025_all_tornadoes.csv` (accessed 2026-10-12, md5 and size in `provenance.txt`) and the NWS Damage Assessment Toolkit data queried on 2026-11-11. They describe the current build; run the scripts again after a data change. No data are changed to work around any of these items.

**Terms used on this page.**

* *Modeled path polygon*: the area of a tornado's path as the package models it: the straight line from SPC's start point to its end point, buffered by half of SPC's width with flat ends. It exists only for a line track with a positive width.
* *No usable end point*: SPC's end coordinates are missing, 0, or equal to the start. The tornado is a point at its start (`track_type = "point"`); its direction and extent are unknown.
* *Chord*: the straight-line distance between a tornado's start and end points.
* *Percentiles* (10th, 25th, 75th, 90th and 99th, with the median): they describe the spread of a distribution; none is a tested choice.
* *Boundary year*: the Census Bureau ZCTA boundary file of the 2000, 2010 or 2020 census (the column of `zcta_centroids` is named `vintage`). Tornadoes of 1996-2009 use 2000, 2010-2019 use 2010, and 2020 on use 2020.
* *DAT*: the National Weather Service Damage Assessment Toolkit; `dat_points`, `dat_lines` and `dat_polygons` are its features, as the service gives them.
<!-- intro:end -->

<!-- provides:start -->
## What the package provides

| Dataset | Contents | Rows | Columns | File size (xz) |
|---|---|---|---|---|
| `spc_records` | SPC, every tornado record from 1996 on, every column and every row (all `sg`), as SPC gives them | 38,953 | 32 | 0.77 MB |
| `tornado_tracks` | SPC, one row per tornado (whole-track record): a line from the raw start to the raw end point, or a point at the start for a tornado with no usable end point; SPC's raw coordinates, length and width; loss as given and in dollars | 38,027 | 17 + geometry | 1.30 MB |
| `tornado_exposure` | one row per tornado and ZCTA touched: distances (`boundary_dist_km`, `centroid_dist_km`), the `modeled_*` columns, ZCTA polygon and land area, ZCTA population | 57,754 | 22 | 3.07 MB |
| `zcta_centroids` | Census, one population-weighted centroid per ZCTA and boundary year, with the ZCTA's population, polygon area and land area | 98,932 | 9 | 2.48 MB |
| `dat_points` | NWS Damage Assessment Toolkit, every damage point, all fields, unmodified | 241,456 | 28 + geometry | 12.89 MB |
| `dat_lines` | NWS Damage Assessment Toolkit, every damage line (centerline of a surveyed track), all fields, unmodified | 13,021 | 32 + geometry | 3.09 MB |
| `dat_polygons` | NWS Damage Assessment Toolkit, every damage polygon, all fields, unmodified | 11,172 | 21 + geometry | 3.41 MB |
| `tornado_dat_link` | one row per DAT line linked to an SPC tornado, with every number that describes the link | 11,573 | 13 | 0.47 MB |
| `dat_polygon_line_link` | one row per DAT polygon and line dated within a day of each other: distance and the share of the line inside the polygon | 466,150 | 4 | 3.22 MB |

The files in `data/` add up to 30.69 MB. Census inputs (ZCTA boundaries, block populations) are read when the data are built and are not shipped; maps and the boundary distance download the full TIGER/Line files (sizes in `?get_data` and `?map_exposure`).
<!-- provides:end -->

<!-- fidelity:start -->
## What is and is not done to the source data

The aim of the package is the highest quality of data on tornadoes, changed as little as possible. Allowed operations on source geometry are a coordinate transformation (projection), merging polygons and repairing invalid geometry, and each is listed below with the number of features it touches. No source geometry or coordinate is simplified, generalized, rounded, snapped, thinned or truncated, and no source value is capped, imputed or replaced: where a transformation is needed, the raw value is kept in its own column.

| Operation | What it touches | Allowed |
|---|---|---|
| SPC records before 1996 are not used | 36,003 of 74,956 rows of the SPC file | Yes: the package starts in 1996 (inherited from the original package; no reason is documented) |
| `spc_records`: every SPC column and every row from 1996 on, as SPC gives them (the time of day stays text); the column `tornado_id` is added | 38,953 rows, 31 SPC columns; `tornado_id` is `NA` for 718 segment rows whose year and `om` match no whole-track row or several | Yes: nothing is dropped; the added column is an identifier |
| Identifiers shared by two tornadoes are renamed `_1`, `_2` | 4 records (2001_56_1, 2001_56_2, 2002_506_1, 2002_506_2) | Yes: an identifier, not a source value; the raw `om` stays in `spc_records` |
| Loss in millions of dollars (before 2007) is converted to dollars (`loss` times 1e6) | 6,447 nonzero values; the largest difference between the stored dollars and the exact product is 4.66e-10 dollars (the build stops if a value is not a whole number of dollars up to floating-point error) | Yes: an exact unit conversion; the raw value and unit are kept in `loss_raw` and `loss_raw_unit` |
| A loss of 0 becomes `NA` in `property_loss_tornado_total` | 19,567 tornadoes | Yes: NOAA says 0 does not mean $0; the raw value is kept in `loss_raw` |
| A tornado with no usable end point (end coordinates missing, 0 or equal to the start) is a POINT at the start; SPC's raw coordinates, length and width are kept | 10,384 tornadoes (27.3%): end 0 1, end equal to the start 10,383 | Yes: no end point is invented; no shape is modeled for them |
| A width of 0 or missing is never replaced | 473 tornadoes (138 lines, 335 points) | Nothing is changed; a line with a width of 0 has no modeled path polygon (its ZCTAs are those that a positive length of the line lies in, 277 rows) and its `modeled_*` columns are `NA` |
| The modeled path of a line with a positive width is the straight line from SPC's start to SPC's end, buffered by half of SPC's width with flat ends | 27,505 tornadoes | A model, not a source geometry: it is not a damage boundary (section Modeled columns) |
| Coordinates are projected to EPSG:5070 for areas, to a regional CRS for distances (EPSG:5070 in the 48 states, EPSG:3338 Alaska, ESRI:102007 Hawaii, EPSG:32161 Puerto Rico) and to EPSG:4269 for block points; maps are drawn in EPSG:4326 | every geometry that is measured or intersected | Yes: projection |
| ZCTA polygons repaired with `st_make_valid()` (counted in EPSG:5070 as read) | 2000 file: 0 of 32,038; 2010 file: 1 of 33,120; 2020 file: 0 of 33,791 | Yes: repairing invalid geometry |
| Census block polygons repaired with `st_make_valid()` (counted over all blocks as read; the pipeline repairs only the blocks near a path) | invalid blocks: 2000: 0 of 8,262,363; 2010: 0 of 11,155,486; 2020: 0 of 8,174,955 | Yes: repairing invalid geometry |
| Intersections of paths with ZCTAs: pieces of one tornado in one ZCTA are merged; pieces that are not polygons are dropped for a modeled path | 0 pieces of exactly zero area; 57,754 tornado-ZCTA rows (47,505 from a path polygon, 277 from a centerline, 9,972 from a start point; 0 start points lie in more than one ZCTA) | Yes: merging polygons |
| A start point that lies in no ZCTA has no row in `tornado_exposure` | 412 point tornadoes (they stay in `tornado_tracks`) | Yes: nothing is moved or invented |
| `modeled_area_prop` is the modeled intersection divided by the area of the full ZCTA polygon, not capped | 47,505 rows; 1 row above 1 (by 6.18e-13, floating-point error); `zcta_polygon_area_m2` differs from `zcta_land_area_m2` (ALAND) by more than 1% in 18,929 of 57,754 rows, by more than 10% in 2,335 and by more than 50% in 268 | Nothing is changed or capped; both areas are shipped |
| `zcta_centroids`: longitude and latitude are as computed (not rounded) | 98,932 rows | Nothing is rounded |
| `zcta_centroids`: the geometric centroid of a ZCTA with no residents is replaced by a point on the polygon surface when it falls outside the polygon | 5 of 342 ZCTAs with no residents (sum over the three boundary years) | Yes: a computed centroid, not a source value; the type is `geometric` |
| Population: a block with an `NA` population stops the build | 0 `NA` ZCTA populations; the 2020 block field `POP20` is `NA` for 0 blocks | Nothing is replaced |
| Population: a duplicated GEOID in a block file stops the build | 0 duplicated GEOIDs in 27,592,804 blocks | Nothing is dropped |
| Population: the share of a block inside a path is not capped; the build stops if it is above 1 by more than 1e-9 | 454,038 path-block pieces; 29,385 above 1 (largest 1.00000000008, floating-point error) | Nothing is capped |
| Population: a block whose internal point lies in more than one ZCTA keeps only its first ZCTA (`!duplicated(GEOID)`) | 5 blocks (5 rows dropped) in 2000: 2, 2010: 3, 2020: 0 | Not allowed under the fidelity rule without approval: reported to the maintainer |
| DAT features: every feature of the three layers is kept, all fields, full resolution, in the service's spatial reference; no generalization, simplification, date filter, swath filter or field selection | points 241,456, lines 13,021, polygons 11,172 (equal to the counts the service reported); 2 empty point, 21 empty line and 185 empty polygon geometries and 41 + 1 + 254 features without a date are kept | Nothing is changed |
| DAT dates: the text of milliseconds since 1970 is stored as a number (same value) and a `_utc` column is added | 13 added columns | Yes: type conversion without loss; the raw values are kept |
| DAT strings are as the service gives them (no character is removed) | 3 event ids contain a soft hyphen (U+00AD) and keep it | Nothing is changed |
| `tornado_dat_link` and `dat_polygon_line_link` are computed on copies of the geometries projected to EPSG:5070; a polygon that is invalid is repaired for the computation only | 0 polygons repaired; the shipped features are not repaired | Yes: projection and repairing invalid geometry |
| Maps and boundary distances use the full TIGER/Line boundaries, not the generalized cartographic files | every map and every `boundary_dist_km` call | Nothing is generalized |

**The modeled path is not a damage boundary at fine scales.** A modeled path is a straight line from SPC's start to SPC's end, drawn at SPC's single width. It does not follow the curve of a real path or its changing width, so it is not a damage boundary at scales finer than a kilometer: for the 11,369 SPC line tornadoes linked to a DAT line, the largest distance from a vertex of the DAT centerline to the SPC line has a median of 0.23 km and a 90th percentile of 1.78 km, by length of the SPC line: under 5 miles (7,981 links): median 0.11 km, 90th percentile 0.90 km; 5 to 20 miles (2,955 links): median 0.63 km, 90th percentile 1.98 km; over 20 miles (433 links): median 1.90 km, 90th percentile 4.82 km.

**Area basis.** `modeled_area_prop` is the modeled intersection with the full ZCTA polygon divided by the area of that polygon, so numerator and denominator come from the same geometry and the proportion cannot exceed 1 except by floating-point error. The Census land area (`ALAND`) is shipped as `zcta_land_area_m2`; the ZCTA polygons include inland and coastal water, so the polygon area is larger than the land area: it differs by more than 1% in 18,929 of 57,754 rows and by more than 10% in 2,335. The package does not ship a land-only area share.

**NCEI.** NCEI's Storm Events database is built from the same NWS Storm Data as SPC and is not independent of it. For 23,874 SPC tornadoes of 2007 to 2025 matched to NCEI events (within 2 km of the SPC line, within a day) the rating is equal for 99.64 percent (`data-raw/qa/54b_ncei_comparison.R`).

<!-- fidelity:end -->

<!-- loss:start -->
## Property loss (SPC `loss`)

* SPC loss of 0 means unknown, not $0 (NOAA's wording), so `property_loss_tornado_total` and `modeled_property_loss_allocated` are `NA` for those tornadoes (the raw value 0 stays in `tornado_tracks$loss_raw`). 19,567 of 38,027 tornadoes (51.5%) become `NA`: 7,418 of 13,865 in 1996-2006 (53.5%) and 12,149 of 24,162 from 2007 (50.3%). In `tornado_exposure` that is 25,426 of 57,754 rows (44.0%; 19,104 of the 37,383 tornadoes with rows). For tornadoes with a known loss and a modeled path the allocated values sum to the total; for the others they are `NA`.
* Loss is incomplete even for the deadliest tornadoes. Since 2007, 28 of 108 EF4 and EF5 tornadoes have no loss recorded (`NA`), and 3 of 29 tornadoes with at least 10 deaths (10 deaths is a cut-off chosen to show the deadliest tornadoes, not a tested choice). The Mayfield tornado `2021_2112102054-01` (57 deaths, 515 injuries) has loss 25,000 dollars.
* Units: nonzero values are in millions of dollars through 2006 (yearly median at most 0.07, maximum 1,000) and whole dollars from 2007 (yearly median at least 50,000). The pipeline multiplies 1996-2006 by one million (an exact conversion; the build stops if a result is not a whole number of dollars up to floating-point error), keeps the raw value in `tornado_tracks$loss_raw` with `loss_raw_unit`, and stops if the break moves (limits in the table of constants below). SPC re-coded 2007-2015 from millions to dollars between its 2024 and 2025 releases, so it can change again.
* Loss of the 644 tornadoes that touch no ZCTA is not allocated: 56,387,000 dollars (181 tornadoes with loss above 0), 0.129% of all loss.
* The allocation of a tornado's loss to its ZCTAs (`modeled_property_loss_allocated`) uses the modeled area share, so it is an approximation (section Modeled columns). It is `NA` for the 10,249 rows of tornadoes with no modeled path.
<!-- loss:end -->

<!-- coordinates:start -->
## Coordinates

* SPC gives 1996-2006 coordinates to 0.01 degrees (about 1.1 km of latitude); from 2007 to 0.0001 degrees (about 11 m). The package does not round or move any coordinate. A simulation that moves each coordinate by up to half its rounding step (20 replicates, 1,000 tornadoes per era: sample sizes of this simulation, not tested choices; points keep the ZCTA that contains the start, lines use the modeled path) changes the set of ZCTAs for 4.2% of 1996-2006 tornadoes per replicate (13.9% in at least one replicate) but 0.23% from 2007 (0.9% in at least one). A sensitivity analysis restricted to 2007 onward is recommended.
* From 2007 the reported length is close to the straight-line distance (`len_ratio` is above 1.5 for 1.1% of line tracks from 2007 against 21.9% in 1996-2006), which suggests that it is computed from the coordinates, so `len_ratio` cannot independently validate modern coordinates.
<!-- coordinates:end -->

<!-- modeled:start -->
## Modeled columns (the `modeled_*` columns of `tornado_exposure`)

SPC records only a start point, an end point and one width for each tornado, so the modeled path is the straight line between the two points, buffered by half the width. Real tornado paths curve and their width varies along the track. A tornado with no usable end point has no modeled path, and neither has a line with a width of 0 or missing: their `modeled_*` columns are `NA`.

**What SPC's width means.** NWS instructions for Storm Data define the path width entered for a tornado as the maximum width. NWSI 10-1605 ([current text, 26 July 2021](https://www.weather.gov/media/directives/010_pdfs/pd01016005curr.pdf)), section 47.7 "Determining Path Length and Width": "Path length (in miles and tenths of miles) and maximum path width (in yards) will be indicated for all tornadoes, including each member of families of tornadoes, or for all segments of multi-segmented tornadoes." The archived text of 6 January 2003 ([archived appendix](https://www.weather.gov/media/directives/010_pdfs_archived/pd01016005a_incomplete.pdf)), section 31 "Tornado (C)": "Path width in the entry header is the maximum width over the entire path, or of each segment in a multi-segment tornado." SPC compiles its database from Storm Data. SPC's current description ([SPC_severe_database_description.pdf](https://www.spc.noaa.gov/wcm/data/SPC_severe_database_description.pdf)) gives only "Width in yards", and an older SPC format document ([torforma.doc](https://www.spc.noaa.gov/wcm/torforma.doc)) describes a mean width ("Mean tornado path width ... The mean width along the entire track is reported"). This package treats `wid` as the maximum width.

**Comparison with the NWS damage polygons.** For the 2,947 line tornadoes with a modeled path and a usable damage swath (`data-raw/qa/66_modeled_vs_dat.R`; the comparison swath of a linked DAT line is the union of the full-resolution polygons that cross the line on a date within one day, are rated EF0 to EF5, and have at least 90% of their area within SPC's width plus 500 m of the line, and it is usable when it lies within 200 m of at least half of the line; these four settings define which polygons count as this tornado's and change the comparison, not any shipped data), the modeled path area is a median of 1.18 times the area of the swath (10th to 90th percentile 0.41 to 2.03), consistent with a maximum width held along the whole path where the real width varies. Per tornado and ZCTA present in both, the modeled area share is 1.21 times the share computed from the polygons (0.37 to 2.99) and the modeled resident share 1.16 times (0.29 to 3.60); the two sets of ZCTAs agree for 91.7% (pairs in both over pairs in either). The modeled columns are noisy for any single tornado and are approximations, not a damage boundary. The accuracy of the NWS polygons has not been measured.

**Position.** For the 11,369 SPC line tornadoes linked to a DAT line, the largest distance from a vertex of the DAT centerline to the SPC line has a median of 0.23 km and a 90th percentile of 1.78 km (`data-raw/qa/46_path_accuracy.R`; every link counts, whatever its distance). By length of the SPC line: under 5 miles (7,981 links): median 0.11 km, 90th percentile 0.90 km; 5 to 20 miles (2,955 links): median 0.63 km, 90th percentile 1.98 km; over 20 miles (433 links): median 1.90 km, 90th percentile 4.82 km. A distance threshold smaller than these values cannot separate exposure from path-location error.
<!-- modeled:end -->

<!-- dat:start -->
## NWS damage-survey data (DAT)

The three layers of the Damage Assessment Toolkit service were fetched whole on 2026-11-11 (no date filter, all fields, full resolution, EPSG:4326). The counts below equal the counts the service reported. Operations on the features: none.

| Layer | Features | Empty geometry | No stormdate | Dated before 2007 | Size of the service's response |
|---|---|---|---|---|---|
| Damage points | 241,456 | 2 | 41 | 834 | 152.4 MB |
| Damage lines | 13,021 | 21 | 1 | 63 | 16.7 MB |
| Damage polygons | 11,172 | 185 | 254 | 119 | 16.1 MB |

**Dates.** The service gives dates as milliseconds since 1970-01-01 UTC, as text; they are stored as numbers with a `_utc` copy. The earliest `stormdate` is 1855-05-22 and the latest 2026-11-03; features before 1996 cannot be linked to an SPC tornado.

**Rating field.** The values of `efscale` are those the survey teams entered. Polygons: `EF1` 3,903, `EF0` 3,591, `EF2` 1,596, `TSTM/Wind` 1,254, `EF3` 506, `UNKNOWN` 147, `EF4` 101, `N/A` 47, `EF5` 11, `EFU` 11, `EF3+` 4, `Tropical` 1. Lines: `EF1` 5,435, `EF0` 4,584, `EF2` 1,291, `UNKNOWN` 535, `EFU` 347, `EF3` 342, `TSTM/Wind` 339, `EF4` 71, `N/A` 68, `EF5` 6, `EF3+` 2, `Tropical` 1. Points: `EF0` 88,438, `EF1` 82,989, `TSTM/Wind` 41,213, `EF2` 16,855, `EF3` 3,750, `N/A` 2,671, `UNKNOWN` 1,603, `Tropical` 1,354, `EFU` 1,271, `EF4` 1,012, `EF3+` 144, `EF5` 98, `(missing)` 49, `Scripts disabled` 6, `Correction` 1, `Extensions disabled` 1, `Null` 1.

**`event_id`** is free text. Filled: points 100,763 of 241,456 (42%), lines 8,595 of 13,021 (66%), polygons 5,947 of 11,172 (53%). Only 3% of the line values are numbers, and 1,000 line values are repeated. Of the 14,045 distinct values, 1 equals the event id of a tornado in NCEI's Storm Events database (2007 to 2025): it is not an NCEI event id and it does not link the layers reliably, so the package does not use it.

**By year, with the SPC tornadoes that have a linked survey line** (a survey is not available for every tornado; coverage grows over the years):

| Year | DAT points | DAT lines | DAT polygons | SPC tornadoes | with a linked line | Share |
|---|---|---|---|---|---|---|
| 2007 | 15 | 4 | 4 | 1,132 | 4 | 0.4% |
| 2008 | 103 | 26 | 24 | 1,704 | 25 | 1.5% |
| 2009 | 113 | 29 | 0 | 1,162 | 28 | 2.4% |
| 2010 | 984 | 62 | 9 | 1,302 | 56 | 4.3% |
| 2011 | 5,217 | 214 | 255 | 1,704 | 179 | 10.5% |
| 2012 | 2,308 | 128 | 139 | 948 | 112 | 11.8% |
| 2013 | 11,834 | 220 | 353 | 916 | 212 | 23.1% |
| 2014 | 8,196 | 438 | 713 | 928 | 341 | 36.7% |
| 2015 | 9,355 | 540 | 600 | 1,182 | 490 | 41.5% |
| 2016 | 9,092 | 503 | 407 | 976 | 468 | 48.0% |
| 2017 | 16,674 | 778 | 807 | 1,442 | 741 | 51.4% |
| 2018 | 11,941 | 626 | 563 | 1,138 | 580 | 51.0% |
| 2019 | 16,838 | 1,010 | 797 | 1,534 | 962 | 62.7% |
| 2020 | 18,034 | 797 | 612 | 1,090 | 757 | 69.4% |
| 2021 | 14,135 | 1,136 | 721 | 1,328 | 991 | 74.6% |
| 2022 | 13,552 | 991 | 781 | 1,167 | 912 | 78.1% |
| 2023 | 20,021 | 1,142 | 953 | 1,321 | 1,041 | 78.8% |
| 2024 | 27,465 | 1,692 | 1,388 | 1,805 | 1,559 | 86.4% |
| 2025 | 32,587 | 1,312 | 911 | 1,383 | 1,216 | 87.9% |
| 2026 | 22,117 | 1,309 | 762 | 0 | 0 | none (no SPC tornadoes) |

**The link table.** 11,573 of 13,021 lines are linked to 10,704 tornadoes, by these rules:

| Rule | Links |
|---|---|
| attached_to_paired | 869 |
| mutual_closest | 10,704 |

Distribution of the link numbers (median / 90th percentile / 99th percentile / maximum): index-aligned distance 0.13 / 1.52 / 215.69 / 1748.19 km; one-sided distance 0.10 / 0.88 / 215.63 / 1747.78 km; length ratio (DAT length over SPC length) 1.00 / 1.07 / 8.70 / 2109.00; `same_state` is FALSE for 187 links. The same numbers for the mutual-closest links only: index-aligned distance 0.11 / 0.80 / 8.01 / 1469.34 km. `tornado_dat_link` has no cutoff, so a link can be to a line far from the tornado; filter on the distance columns for your purpose.

**Polygons and lines.** `dat_polygon_line_link` has 466,150 rows (7,410 with the line touching the polygon). 6,415 of the 11,172 polygons touch a linked line; polygons are nested by rating, so they overlap one another (the sum of the polygon areas is larger than the area they cover).

**Linkage not made.** 1,448 lines are in no link: 21 have an empty geometry, 1 have no date, and the rest have no SPC tornado within a day, or their one-sided nearest tornado has no mutual-closest line. Damage points are not linked to tornadoes by any rule.

<!-- dat:end -->

<!-- st-louis:start -->
## A worked example: the St. Louis tornado of 16 May 2025

SPC's 2025 file (released 24 April 2026) has one whole-track record for the tornado, `2025_2505161339-01`: 23.22 miles, a width of 1,750 yards, rating 2, 38 injuries and 4 deaths, from 38.6440, -90.3468 to 38.7971, -89.9733 (Missouri into Illinois). `spc_records` also holds the other rows of the record: `2505161339-01` (sg 1, MO, 23.22 miles, rating 2); `2505161339-02` (sg 2, MO, 8.91 miles, rating 2); `2505161339-03` (sg 2, IL, 14.31 miles, rating 1).

The National Weather Service surveyed it as two separate tornadoes from one storm circulation: an EF3 that lifted just north of Granite City, Illinois, and an EF1 that touched down just south of that point ([Updated Damage Assessment for May 16, 2025 St. Louis Tornado](https://www.weather.gov/lsx/STLTornado); reported by [STLPR on 15 May 2026](https://www.stlpr.org/news-briefs/2026-05-15/may-16-tornado-reached-1-8-miles-wide)). SPC's file of 24 April 2026 predates that update of 15 May 2026, so it holds one record with rating 2.

**What the package holds.** The DAT lines are in `dat_lines` and are both linked to the one SPC record in `tornado_dat_link`: DAT line 2671572 (EF1, 11.64 miles, width 0 yards; rule `mutual_closest`, index-aligned distance 8.99 km, one-sided distance 1.29 km, length ratio 0.50); DAT line 2671973 (EF3, 12.29 miles, width 3,168 yards; rule `attached_to_paired`, index-aligned distance 9.11 km, one-sided distance 1.48 km, length ratio 0.53). Relationship `one_to_many`. The damage polygons that touch these lines (`dat_polygon_line_link`, `line_share_in_polygon` above 0) number 9 (ratings EF0 3, EF1 3, EF2 1, EF3 2). `map_exposure()` draws the SPC line over the two DAT tornadoes (the call is in the README).

**Exposure.** The modeled path touches 14 ZCTAs (10 in Missouri, 4 in Illinois); the modeled path area is 58.3 km2 for the SPC width of 1,750 yards.

**NCEI.** NCEI's Storm Events database has three events for it: event 1262242 (ILLINOIS, EF1, 14.31 miles, 1035 yards); event 1262206 (MISSOURI, EF2, 2.3 miles, 500 yards); event 1262207 (MISSOURI, EF0, 6.61 miles, 1750 yards). NCEI is built from the same NWS Storm Data as SPC and is not independent.

A check of this case is in `data-raw/qa/check_data_integrity.R`.
<!-- st-louis:end -->

<!-- no-end-point:start -->
## Tornadoes with no usable end point

A tornado has no usable end point when SPC's end coordinates are missing, equal to 0, or equal to the start coordinates. 10,384 of the 38,027 tornadoes (27.3%) are of this kind (10,383 have an end equal to the start, 1 an end of 0 or missing). 7,849 of them (75.6%) are from 1996 to 2006 and 2,535 (24.4%) from 2007 on. The package draws each as a POINT at the start (`track_type = "point"`), keeps SPC's raw coordinates, length and width, and models no path shape: the `modeled_*` columns are `NA` (the real path has an unknown direction and may extend up to the reported length from the start). In `tornado_exposure` such a tornado has one row, the ZCTA that contains the start point; 412 start points lie in no ZCTA and have no row.

**By rating.**

| Rating | All tornadoes | No usable end point | Share of this rating | Share of all such tornadoes |
|---|---|---|---|---|
| EF0 | 20,531 | 8,448 | 41.1% | 81.4% |
| EF1 | 11,825 | 1,393 | 11.8% | 13.4% |
| EF2 | 3,123 | 178 | 5.7% | 1.7% |
| EF3 | 830 | 17 | 2.0% | 0.2% |
| EF4 | 157 | 0 | 0.0% | 0.0% |
| EF5 | 15 | 0 | 0.0% | 0.0% |
| unknown | 1,546 | 348 | 22.5% | 3.4% |

**Reported length** (SPC's `len`, in miles; median 0.20, 90th percentile 1.00, longest 80.0; 10,265 of 10,384 (98.9%) have a length above 0):

| Reported length | Tornadoes | Share |
|---|---|---|
| 0 (reported length is zero) | 119 | 1.1% |
| above 0 and under 0.5 mile | 7,233 | 69.7% |
| 0.5 to under 1 mile | 1,584 | 15.3% |
| 1 to under 5 miles | 1,331 | 12.8% |
| 5 miles or more | 117 | 1.1% |

**Injuries and deaths.** These tornadoes account for 1,221 of 28,386 injuries (4.3%) and 38 of 2,196 deaths (1.7%); 27 of them have at least one death.

**Reported width.** SPC's width (`wid`, yards) is 0 or missing for 335 of these tornadoes (3.2%); for the others the median is 30 yards and the 90th percentile 100 yards. A width is never replaced.

**By year.**

| Years | Tornadoes | No usable end point | Share |
|---|---|---|---|
| 1996 | 1,173 | 700 | 59.7% |
| 1997-2001 | 6,201 | 3,798 | 61.2% |
| 2002-2006 | 6,491 | 3,351 | 51.6% |
| 2007-2010 | 5,300 | 971 | 18.3% |
| 2011-2015 | 5,678 | 600 | 10.6% |
| 2016-2020 | 6,180 | 516 | 8.3% |
| 2021-2025 | 7,004 | 448 | 6.4% |

**By era and rating** (share of tornadoes with no usable end point):

| Era | EF0 | EF1 to EF5 | Unknown |
|---|---|---|---|
| 1996-2006 | 72.2% | 28.1% | none |
| 2007 on | 17.1% | 1.9% | 22.5% |

**Plain reading.** 81.4% of these tornadoes are EF0 and the median reported length is 0.20 mile, but SPC gives a length above 0 for 98.9% of them, 1,448 are 1 mile or longer, 117 are 5 miles or longer, and the longest is 80.0 miles, so they are not all brief touchdowns: the real path may extend up to the reported length from the start point in an unknown direction. The share follows the era more than the strength: between 1996-2006 and 2007 on it falls by 55 percentage points among EF0 tornadoes and 26 points among EF1 to EF5, while within 1996-2006 it differs by 44 points between EF0 and EF1 to EF5 (15 points from 2007 on). Coordinates before 2007 are rounded to 0.01 degrees, so start and end points of short tornadoes often coincide.
<!-- no-end-point:end -->

<!-- distance:start -->
## Exposure definitions and distance exposure

A call uses one exposure definition. The *touched* definition (the default) returns the ZCTAs that the modeled path polygon overlaps, that a positive length of the SPC line lies in when SPC gives no width, or that contain the start point of a tornado with no usable end point. `area_thresh` and `pop_thresh` apply to the `modeled_*` shares and do not evaluate tornadoes with no modeled path. `centroid_dist_km` and `boundary_dist_km` are measured from the SPC line (the start point for a tornado with no usable end point) and have no upper limit.

**Joplin, Missouri, 22 May 2011** (`2011_1105221634-01`, EF5, 3 ZCTAs touched: 64804 64840 64844), with the ZCTAs starting with 647, 648 or 649 (the radii and thresholds are examples, not recommendations):

| Definition | ZCTAs | ZCTA codes |
|---|---|---|
| touched (default) | 3 | 64804 64840 64844 |
| area_thresh = 0.05 | 2 | 64804 64840 |
| area_thresh = 0.1 | 1 | 64840 |
| pop_thresh = 0.05 | 2 | 64804 64840 |
| centroid_dist_km = 1 | 0 |  |
| centroid_dist_km = 5 | 2 | 64804 64840 |
| centroid_dist_km = 10 | 5 | 64801 64804 64840 64841 64844 |
| boundary_dist_km = 1 | 3 | 64804 64840 64844 |
| boundary_dist_km = 5 | 6 | 64801 64804 64840 64844 64850 64862 |

**Nationwide centroid-distance query** (every tornado, every ZCTA of each boundary year, one core; `seconds` is the time of the query and is the basis of the time estimate that `get_data()` prints for large requests):

| Radius (km) | Tornado-ZCTA rows | Tornadoes without a row | Seconds | Touched pairs with the centroid within the radius | Rows that are not touched pairs |
|---|---|---|---|---|---|
| 1 | 4,843 | 33,767 | 4 | 8.1% | 3.9% |
| 5 | 36,736 | 16,408 | 11 | 45.0% | 29.2% |
| 10 | 103,695 | 5,419 | 25 | 76.0% | 57.7% |
| 25 | 504,343 | 343 | 100 | 98.0% | 88.8% |
| 50 | 1,774,382 | 13 | 338 | 99.8% | 96.8% |

The result of a centroid-distance call is not a superset of the touched set: a large ZCTA crossed at its edge can have a centroid farther than the radius, as the share of touched pairs within each radius shows. The distance from the SPC line to the centroid is measured in a projection that suits the region (EPSG:5070 in the 48 states, EPSG:3338 in Alaska, ESRI:102007 in Hawaii, EPSG:32161 in Puerto Rico).
<!-- distance:end -->

<!-- population:start -->
## Population (`modeled_pop_affected`, `zcta_pop`, `modeled_pop_prop`)

`modeled_pop_affected` is the estimated number of residents (total population, all ages) inside the modeled path within a ZCTA. Each census block of the ZCTA vintage keeps its population, which is allocated to the path by the share of the block's area inside the path (uniform density within a block, water included in the block polygon). Blocks are assigned to ZCTAs by their internal points, and `zcta_pop` is the sum of the populations of the blocks assigned to a ZCTA. Population is fixed at the census year within each decade (2000 blocks for years before 2010, 2010 blocks for 2010 to 2019, 2020 blocks from 2020). Sources: TIGER/Line tabulation blocks, with population from field `POP20` (2020) or the Census PL 94-171 redistricting files (2010 and 2000); URLs, sizes and checksums are in `data-raw/provenance_population.csv`.

| Vintage | Blocks | Resident population in the blocks | Blocks assigned to no ZCTA | Residents in those blocks |
|---|---|---|---|---|
| 2000 | 8,262,363 | 285,230,516 | 299,581 (3.63%) | 43,957 (0.015%) |
| 2010 | 11,155,486 | 312,471,327 | 325,609 (2.92%) | 8,333 (0.003%) |
| 2020 | 8,174,955 | 334,735,155 | 144,394 (1.77%) | 8,569 (0.003%) |

**Block-to-ZCTA assignment against the official 2020 relationship file.** Of 8,174,955 blocks in the 50 states, DC and Puerto Rico, 8,030,561 have the same ZCTA in the Census Bureau's 2020 ZCTA-to-block relationship file and our assignment, 144,394 are assigned to no ZCTA in both, and 0 disagree (0 residents). `zcta_pop` is identical under both assignments for 100.00% of the 33,774 ZCTAs.

**`zcta_pop` against official ZCTA populations** (Census Gazetteer files, which need no API key; the 2020 Gazetteer has no population and the API needs a key, so 2020 is checked only through the relationship file above). 2010: 33,120 ZCTAs compared; identical `zcta_pop` for 33,119 (99.997%); largest absolute difference 3 residents; total difference -3 residents. 2000: 31,996 ZCTAs compared; identical `zcta_pop` for 31,996 (100.000%); largest absolute difference 0 residents; total difference 0 residents.

**Whole-block and internal-point checks.** ZCTAs are built from whole blocks, so a block assigned to a ZCTA by its internal point should lie almost entirely inside it, and a block assigned to none should lie outside every ZCTA. Random samples of blocks:

| Vintage | State | Blocks sampled | Assigned to a ZCTA | Assigned: at least 99% of area inside the ZCTA | Assigned: minimum share inside | Unassigned: blocks sampled | Unassigned: share with at most 1% of area inside any ZCTA |
|---|---|---|---|---|---|---|---|
| 2000 | CA | 4,000 | 3,767 | 100.00% | 1.000 | 233 | 100.0% |
| 2000 | IL | 4,000 | 3,973 | 100.00% | 1.000 | 27 | 100.0% |
| 2000 | MA | 4,000 | 3,937 | 100.00% | 1.000 | 63 | 100.0% |
| 2000 | MO | 4,000 | 3,963 | 100.00% | 1.000 | 37 | 100.0% |
| 2000 | NJ | 4,000 | 3,913 | 100.00% | 1.000 | 87 | 100.0% |
| 2000 | TX | 4,000 | 3,739 | 100.00% | 1.000 | 261 | 100.0% |
| 2010 | CA | 4,000 | 3,729 | 100.00% | 1.000 | 271 | 100.0% |
| 2010 | IL | 4,000 | 3,982 | 100.00% | 1.000 | 18 | 100.0% |
| 2010 | MA | 4,000 | 3,979 | 100.00% | 1.000 | 21 | 100.0% |
| 2010 | MO | 4,000 | 4,000 | 100.00% | 1.000 | 0 | n/a |
| 2010 | NJ | 4,000 | 3,964 | 100.00% | 1.000 | 36 | 100.0% |
| 2010 | TX | 4,000 | 3,817 | 100.00% | 1.000 | 183 | 100.0% |
| 2020 | CA | 4,000 | 3,835 | 100.00% | 1.000 | 165 | 100.0% |
| 2020 | IL | 4,000 | 3,998 | 100.00% | 1.000 | 2 | 100.0% |
| 2020 | MA | 4,000 | 3,986 | 100.00% | 1.000 | 14 | 100.0% |
| 2020 | MO | 4,000 | 4,000 | 100.00% | 1.000 | 0 | n/a |
| 2020 | NJ | 4,000 | 3,992 | 100.00% | 1.000 | 8 | 100.0% |
| 2020 | TX | 4,000 | 3,896 | 100.00% | 1.000 | 104 | 100.0% |

**Integrity.** `modeled_pop_affected` never exceeds `zcta_pop`, `modeled_pop_prop` is not capped and is at most 1 (any excess over 1 is floating-point error), and for every tornado the residents in the exposure rows plus the residents in blocks assigned to no ZCTA equal the residents in the modeled path. `modeled_pop_prop` is `NA` for 23 rows (`zcta_pop` is 0). Its median is 0.00064, its 90th percentile 0.0206 and its 99th percentile 0.168; 3,060 rows (6.4%) have `modeled_pop_affected` 0.

**Joplin (`2011_1105221634-01`).** The modeled path holds 4,411 residents (64804: 3,521; 64840: 760; 64844: 129). No survey GIS exists for Joplin. The straight modeled path can sit kilometers from the real one (see Modeled columns), and the residents it holds depend strongly on its sideways position: shifting the modeled polygon sideways changes them from 1,213 to 14,031 (3.2 times the unshifted 4,411, reached at a shift of 3.5 km to the left of the direction of travel, about north, toward the Joplin city center, which is about 5 km north of the modeled centerline). The unshifted estimate is therefore very uncertain, and a path displaced to the north would hold several times more residents; without a survey the true figure cannot be determined.

**Block versus block group, tornadoes from 2020 on** (the minimum residents of 1, 100 and 1,000 are a span chosen to show how the comparison changes with the size of the population; "within 25%" and "within a factor of 2" describe the comparison and are not tested choices). The Census Bureau adds noise to 2020 block counts (differential privacy) and recommends aggregating. The residents in the modeled path computed from block groups instead of blocks (block-group population allocated by area share):

| Residents in the path (blocks) at least | Tornadoes | Median block-group / block | Interquartile range | Within 25% | Within a factor of 2 | Rank correlation |
|---|---|---|---|---|---|---|
| 1 | 4,887 | 0.99 | 0.68 to 1.51 | 36.2% | 69.8% | 0.902 |
| 100 | 1,281 | 0.92 | 0.71 to 1.09 | 56.4% | 85.6% | 0.904 |
| 1,000 | 279 | 0.94 | 0.85 to 1.02 | 83.2% | 97.5% | 0.942 |

This shows how much the uniform-density assumption and the block resolution matter; it is not a measurement of the noise itself, which cannot be isolated without noise-free data.
<!-- population:end -->

## 2020 block populations contain added noise

The 2020 block populations carry noise added by the Census Bureau's disclosure avoidance system. The Bureau's handbook ([Disclosure Avoidance for the 2020 Census: An Introduction](https://www2.census.gov/library/publications/decennial/2020/2020-census-disclosure-avoidance-handbook.pdf), November 2021, PDF page 25) says: "The amount of noise added to statistics does not depend on population or geographic size, so block-level data are most affected by disclosure avoidance procedures." The size of the noise in a single block was not measured here. Blocks of 2000 and 2010 were not protected this way.


## How the Census Bureau asks to be cited

The Census Bureau's citation guidance ([https://www.census.gov/about/policies/citation.html](https://www.census.gov/about/policies/citation.html)) gives this format for data and geographic products: "Author/s, 'Table or File Name/Number,' Full Product Name, Vintage, <URL>, accessed on date." Its TIGER/Line example is: "U.S. Census Bureau, 'tl_2023_us_state', TIGER/Line Shapefiles, 2023, https://www2.census.gov/geo/tiger/TIGER2023/STATE/, accessed on [date]". The Bureau's ZCTA guidance page ([https://www.census.gov/programs-surveys/geography/guidance/geo-areas/zctas.html](https://www.census.gov/programs-surveys/geography/guidance/geo-areas/zctas.html)) gives no citation instructions of its own. `inst/CITATION` and the README follow the format above.


## Notices about the Damage Assessment Toolkit data (read 21 October 2026)

Every notice found about the DAT data (`dat_points`, `dat_lines`, `dat_polygons`), with its wording and location. The contact e-mail addresses in the notices are omitted.

* **Service description** of the layer queried here (<https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer>, field `serviceDescription`): "Welcome to the National Weather Service Damage Assessment Toolkit. Data on this interface is collected during NWS Post-Event Damage Assessments. While the data has been quality controlled, it is still considered preliminary. Official statistics for severe weather events can be found in the Storm Data publication, available from the National Centers for Environmental Information (NCEI) at: https://www.ncdc.noaa.gov/IPS/sd/sd.html Questions regarding this data can be addressed to: [address omitted]."
* **Copyright text** of the same service (field `copyrightText`): "NOAA National Weather Service". The three layers (0 to 2) have no description or copyright text of their own.
* **NOAA GeoPlatform item** for the same service (<https://www.arcgis.com/home/item.html?id=b6b9dd55450a4f64bcafb3cd6e005a5c>, owner `nws.dat_noaa`, shared publicly, url field equal to the service above): credit "NOAA/National Weather Service"; use constraint "All data is considered preliminary and unofficial. While the data has been quality controlled, it is still considered preliminary. Official statistics for severe weather events can be found in the Storm Data publication, available from the National Centers for Environmental Information (NCEI) at: https://www.ncdc.noaa.gov/IPS/sd/sd.html". The item gives no license. The item description adds "Service defaults to show data with 'stormdate' for the preceding two weeks."
* **Viewer** (<https://apps.dat.noaa.gov/StormDamage/DamageViewer/>): the page is a JavaScript application whose configuration could not be read (access denied), so any splash text it shows was not read. Its portal item (<https://www.arcgis.com/home/item.html?id=96a415322c174d78b5cd02fa68650cfd>) has the same "still considered preliminary" statement and adds: "This web application can be used to view and query the DAT database. In addition, data may be extracted as a shapefile or kmz file using the 'Extract' widget."
* **GeoPlatform page** (<https://disasters-geoplatform.hub.arcgis.com/pages/noaa-damage-assessment-toolkit-dat>, page item <https://www.arcgis.com/home/item.html?id=b2b1055dffbc4818a4dc185b72efe2a8>, last modified 18 April 2025, on the GeoPlatform Disasters site, not in the NOAA GeoPlatform organization): under "Access & Use Information": "Public: This dataset is intended for public access and use." Under "Disclaimers": "While the data has been quality controlled, it is still considered preliminary." Its links are the viewer above and a map service, `https://services.dat.noaa.gov/arcgis/rest/services/DamageAssessmentToolkit/DamageFlexViewer/MapServer`, which returns "Service not found" today and is not the service queried here (`nws_damageassessmenttoolkit/DamageViewer/FeatureServer`). The page therefore describes the Damage Assessment Toolkit dataset in general (its stewards describe it as intended for public access and use and as preliminary); its map service link is an older address that no longer exists, so the page does not name the service queried here.
* **What was not found:** no notice sets terms of use, a license or a citation format for these data (no license text was found; the package does not claim that the data are in the public domain). The general NWS statement for NWS web pages (<https://www.weather.gov/disclaimer>) is about web pages and is not quoted here.


<!-- no-zcta:start -->
## Tornadoes without a ZCTA

644 of 38,027 tornadoes (1.69%) touch no ZCTA of their Census boundary year (the modeled path polygon overlaps none, the SPC line lies in none, or the start point lies in none), so they have no rows in `tornado_exposure`. They stay in `tornado_tracks`, and their property loss is not assigned to any ZCTA. They fall in three categories, defined by rules:

* **Over water** (115): the track does not touch state land in the Census cartographic boundary file of the states (2020, 1:500,000).
* **Over land, no ZCTA nearby** (397): the track touches state land, and more than 50% of the land within 3 km of the path is not covered by any ZCTA of the tornado's boundary year (median share of that land not covered: 91%). The 3 km and 50% are values chosen to describe the cases, not tested choices.
* **On land, mostly covered** (132): the track touches state land, and at most 50% of the land within 3 km of the path is not covered (median share not covered: 35%).

**By Census boundary year** (2000: 471, 2010: 119, 2020: 54) **and track type** (232 line, 412 point):

| Census boundary year | over water | over land, no ZCTA nearby | on land, mostly covered | Total |
|---|---|---|---|---|
| 2000 | 113 | 243 | 115 | 471 |
| 2010 |   2 | 104 |  13 | 119 |
| 2020 |   0 |  50 |   4 |  54 |

| Track type | over water | over land, no ZCTA nearby | on land, mostly covered | Total |
|---|---|---|---|---|
| point | 104 | 192 | 116 | 412 |
| line |  11 | 205 |  16 | 232 |

**By state** (start point, top 10 of the states and territories):

| State | over water | over land, no ZCTA nearby | on land, mostly covered | Total |
|---|---|---|---|---|
| TX |  7 | 143 | 18 | 168 |
| FL | 56 |  60 | 32 | 148 |
| LA |  0 |  27 |  7 |  34 |
| NC | 15 |   6 |  5 |  26 |
| KS |  0 |  19 |  3 |  22 |
| MN |  1 |  13 |  3 |  17 |
| WY |  0 |  14 |  2 |  16 |
| OK |  0 |  10 |  5 |  15 |
| WI |  0 |  12 |  3 |  15 |
| CA |  0 |   7 |  7 |  14 |
| all other (36 states and territories) | 36 |  86 | 47 | 169 |

**Why there is no ZCTA.** The Census Bureau says that "Uninhabited areas (land and water areas) over two square miles are potentially left unassigned from 2020 ZCTA coverage" (https://www.census.gov/programs-surveys/geography/guidance/geo-areas/zctas.html). For the tornadoes of the 2020 boundary year, the connected area around the path that no ZCTA covers (measured in a window of 15 km around the path, so it can be larger) is shown below; the statement was checked for the 2020 file only, and the same numbers are given for the other boundary years without any claim about them.

| Census boundary year | Tornadoes | Uncovered area around the path over 2 square miles | Share | Median uncovered area (square miles) |
|---|---|---|---|---|
| 2000 | 471 | 412 | 99.0% | 172.6 |
| 2010 | 119 | 119 | 100.0% | 156.4 |
| 2020 |  54 | 53 | 100.0% | 179.8 |

**The 2000 file leaves out large water bodies.** The total area of the ZCTA polygons divided by the total land area was 1.010 in the 2000 file, against 1.023 in 2010 and 1.023 in 2020, and 327 of the 471 tornadoes without a ZCTA in the 2000 boundary year (69.4%) overlap a ZCTA of the 2010 or 2020 file:

| Census boundary year | ZCTA polygon area (million km2) | Land area ALAND (million km2) | Polygon area divided by land area |
|---|---|---|---|
| 2000 | 7.19 | 7.12 | 1.010 |
| 2010 | 7.60 | 7.43 | 1.023 |
| 2020 | 7.49 | 7.31 | 1.023 |

| Census boundary year | Tornadoes | Overlap a ZCTA of another boundary year | Share |
|---|---|---|---|
| 2000 | 471 | 327 | 69.4% |
| 2010 | 119 |  79 | 66.4% |
| 2020 |  54 |  39 | 72.2% |

**On land, mostly covered: a sample of 20 of the 132.** Of all 132, 116 have no usable end point (they are points), 56 lie within 100 m of a ZCTA and 119 within 500 m (median 131 m), 123 overlap a ZCTA of another boundary year, and the median uncovered area around the path is NA square miles (4 of them below 2 square miles). What is going on: these are mostly short or point paths (narrow polygons) that lie a short distance from the edge of a ZCTA, next to an unassigned area, and most land nearby is covered, so the polygon falls just outside the ZCTA edge; the ZCTA is close but the path polygon does not reach it. The same path overlaps a ZCTA of another boundary year in most cases, so the gap depends on the boundary file. The sample (random, seed 20):

| Tornado | State | Track type | Length (mi) | Width (yd) | Distance to nearest ZCTA (m) | Land within 3 km not covered | Uncovered area around the path (square miles) | Overlaps a ZCTA of another boundary year |
|---|---|---|---|---|---|---|---|---|
| 2008_0811052012-01 | OK | point | 0.50 |  75 |   6 | 30% | NA | yes |
| 2014_1405310830-01 | SC | line | 0.11 |  30 |  10 | 0% | 165.70 | yes |
| 2021_2112052024-01 | KY | line | 0.29 |  25 | 425 | 22% | 16.01 | yes |
| 2006_69 | CA | point | 0.20 |  15 |  54 | 2% | 172.35 | yes |
| 1998_34 | IA | point | 0.20 |  30 |   4 | 5% | NA | yes |
| 2005_192 | OK | point | 0.10 |  30 |  42 | 40% | NA | yes |
| 2001_789 | IA | point | 0.60 |  35 |   0 | 4% | NA | yes |
| 2000_270 | AR | point | 2.00 |  30 | 184 | 44% | NA | yes |
| 1999_553 | AL | point | 0.10 |  50 |  29 | 1% | NA | yes |
| 2002_212 | MA | point | 0.40 |  75 |  30 | 1% | NA | yes |
| 2001_262 | MN | point | 2.00 |  25 | 355 | 9% | 1.08 | yes |
| 2015_1505191607-01 | TX | line | 0.76 | 100 | 226 | 50% | 215.60 | yes |
| 2008_0806131210-01 | FL | point | 0.05 |  10 |   0 | 4% | NA | yes |
| 1997_73 | TX | point | 0.20 |  20 | 362 | 43% | 58.73 | yes |
| 2003_830 | TX | point | 0.30 | 100 | 756 | 43% | 27.36 | yes |
| 2009_0905241412-01 | CO | point | 0.10 |  50 | 268 | 42% | 24.12 | yes |
| 2001_1085 | TX | point | 0.50 |  30 |  41 | 5% | NA | yes |
| 2000_1074 | FL | point | 0.50 |  80 |  68 | 22% | NA | yes |
| 2003_1013 | KS | point | 0.10 |  80 | 505 | 34% | 17.18 | yes |
| 2004_1606 | NC | point | 0.30 |  20 | 132 | 13% | 36.14 | yes |
<!-- no-zcta:end -->

## ZCTA vintages

* The same code can cover a different area across vintages. Among exposed codes
  present in both files, land area changed by more than 10% for 35.9% of codes
  from 2000 to 2010 and 19.7% from 2010 to 2020. 88 exposed 2000-vintage codes
  (132 rows) do not exist in the 2010 file, 7 exposed 2010-vintage codes (7
  rows) do not exist in the 2020 file, and 79 exposed codes (120 rows) are not in
  the 2020 file. The change of 10% is a cut-off chosen to describe the difference, not a
  tested choice.

<!-- zcta-vintage-overlap:start -->
## ZCTA codes can cover different areas in different vintages

Define the overlap ratio of a code as the area of the intersection of its two polygons divided by the area of their union (1 means the same area, 0 no overlap at all). The ratios 0.9, 0.5 and 0.1 are a span chosen to show how much codes change, not tested choices. A ratio below 0.9 means the two polygons differ by more than about 10% of their combined area, so it includes small boundary adjustments. Of the 32,923 codes that are in both the 2010 and the 2020 boundary files, 17,927 (54.5%) have a ratio below 0.9, 8.2% below 0.5 and 1.2% below 0.1 (35 have no overlap at all). Between 2000 and 2010 the shares are 79.7% below 0.9 (25,011 of 31,378 codes), 15.9% below 0.5 and 2.3% below 0.1. Among the codes that have at least one exposure row, the 2010 to 2020 share below 0.9 is 50.7%. So the same code in 2010 and in 2020 may not be the same place; compare ZCTA-level results across vintages with care.

<!-- zcta-vintage-overlap:end -->

<!-- zcta2000-gap:start -->
## The 2000 ZCTA gap

The official 2000 ZCTA list (Census Gazetteer) has 33,125 ZCTAs, but the 2000 boundary file has 32,038 polygons. 1,129 official ZCTAs have no polygon (and 42 polygons have no official entry). 329 of the missing codes are three-digit placeholders ending in `XX` (for example `997XX`), which stand for areas with no five-digit ZCTA. The missing ZCTAs hold 43,913 residents in the official counts (0.015% of the population; 870 have none and 761 have no land area), which matches the 43,957 residents in 2000 blocks assigned to no ZCTA, but 22.3% of the official land area (mostly a few very large placeholder areas in Alaska and Nevada).

A tornado in such an area has no exposure row for it. To estimate how many 1996-2009 tornadoes are affected, each missing ZCTA was placed at its Gazetteer internal point, as a disc with the official land area (222 codes) or a point (629 codes with no land area); 278 have no coordinates and cannot be placed. By this estimate 310 of 17,863 tornadoes (1.74%) reach a missing ZCTA: 276 of them also have a row for another ZCTA, so they lose only a pair, and 34 are among the 471 tornadoes of the 2000 vintage that intersect no ZCTA. The real areas are irregular and a disc around one point only approximates them, so the count is approximate; no error bound was computed. The 2010 and 2020 files contain none of the missing codes.
<!-- zcta2000-gap:end -->

<!-- identifiers:start -->
## Identifiers and SPC revisions

* `tornado_id` is unique within a package version only. SPC changed its `om` numbering for 2007 onward between its 2024 and 2025 releases (all 8,873 matched 2007+ tornadoes changed ids). Distinct tornadoes that share a year and `om` in SPC (2001_56_1, 2001_56_2, 2002_506_1, 2002_506_2) are suffixed `_1` and `_2`; `spc_records$tornado_id` carries the same ids.
* SPC revises records between releases. Comparing the 2024 and 2025 files for the whole-track records of EF1 and above from 1996 to 2024, matched by date and start latitude and longitude: 13,701 tornadoes matched; magnitude changed for 9, injuries for 18, fatalities for 2, `len` for 79 and `wid` for 22; loss changed for 2,619 (2,530 of them by exactly a factor of one million, the unit re-coding of 2007 to 2015). 0 records of 1996-2006 changed in any of these values or in their id (`data-raw/qa/39_spc_release_comparison.R`). Stored years are frozen; an update appends only new years.
<!-- identifiers:end -->

<!-- ratings:start -->
## Ratings

* All ratings are kept: 20,531 EF0, 15,950 EF1-EF5 and 1,546 unknown (SPC code -9, stored as `NA`). No other magnitude code occurs (the build stops on one). Ratings before 2007 are on the original Fujita scale.
<!-- ratings:end -->

<!-- special-cases:start -->
## Ratings by year, special tracks and territories

Unknown ratings (`magnitude` is `NA`) are absent before 2007 (0 unknown ratings in 1996 to 2006) and grow after: 1,546 of 24,162 tornadoes from 2007 on (6.4%). Counts of EF0 tornadoes are therefore not comparable across years unless unknown ratings are included. Tornadoes per year by rating:

| year | EF0 | EF1 to EF5 | unknown | share unknown |
|---|---|---|---|---|
| 1996 | 743 | 430 | 0 | 0.0% |
| 1997 | 743 | 405 | 0 | 0.0% |
| 1998 | 883 | 541 | 0 | 0.0% |
| 1999 | 830 | 509 | 0 | 0.0% |
| 2000 | 723 | 352 | 0 | 0.0% |
| 2001 | 810 | 405 | 0 | 0.0% |
| 2002 | 623 | 311 | 0 | 0.0% |
| 2003 | 891 | 483 | 0 | 0.0% |
| 2004 | 1,216 | 601 | 0 | 0.0% |
| 2005 | 815 | 448 | 0 | 0.0% |
| 2006 | 686 | 417 | 0 | 0.0% |
| 2007 | 682 | 429 | 21 | 1.9% |
| 2008 | 983 | 721 | 0 | 0.0% |
| 2009 | 706 | 456 | 0 | 0.0% |
| 2010 | 778 | 524 | 0 | 0.0% |
| 2011 | 796 | 908 | 0 | 0.0% |
| 2012 | 577 | 371 | 0 | 0.0% |
| 2013 | 503 | 413 | 0 | 0.0% |
| 2014 | 511 | 417 | 0 | 0.0% |
| 2015 | 695 | 487 | 0 | 0.0% |
| 2016 | 530 | 415 | 31 | 3.2% |
| 2017 | 635 | 741 | 66 | 4.6% |
| 2018 | 627 | 494 | 17 | 1.5% |
| 2019 | 659 | 690 | 185 | 12.1% |
| 2020 | 464 | 520 | 106 | 9.7% |
| 2021 | 562 | 559 | 207 | 15.6% |
| 2022 | 408 | 604 | 155 | 13.3% |
| 2023 | 442 | 611 | 268 | 20.3% |
| 2024 | 594 | 955 | 256 | 14.2% |
| 2025 | 416 | 733 | 234 | 16.9% |

### Line tracks with a length of 0

3 line tracks have a reported length of 0 although their start and end coordinates are far apart (`1999_663`: 20.9 miles; `2004_391`: 2.8 miles; `2005_117`: 6.4 miles). These look like SPC data errors. `len_ratio` is `NA` for them, and the package draws them from the coordinates.

### Tornadoes that start outside the 48 states

44 tornadoes start outside the 48 states, by their start coordinates (24 Puerto Rico, 14 Hawaii, 4 Alaska, 2 US Virgin Islands). The Virgin Islands ZCTAs are not in the data (the block data cover the 50 states, DC and Puerto Rico), so the 2 Virgin Islands tornadoes have no exposure rows; they stay in `tornado_tracks`.
<!-- special-cases:end -->

<!-- dependence:start -->
## Dependence on upstream data

* The shipped data (`data/`) hold everything the functions need. Installing and using the package needs no upstream download, except that `map_exposure()` downloads boundaries from the Census Bureau (through tigris) when it runs and `get_data(boundary_dist_km = )` downloads the full TIGER/Line ZCTA file of the boundary year (the sizes are in the help pages).
* A full rebuild reads the SPC tornado file (one URL, 9.2 MB), the full TIGER/Line ZCTA files for 2000, 2010 and 2020 (through tigris), and, for population, the Census TIGER/Line tabulation blocks (2020: 11.4 GB; 2010: 7.0 GB; 2000: 5.8 GB) and the PL 94-171 files (1.0 GB for 2010 and 0.4 GB for 2000), 26.4 GB in all (367 files, listed with size and md5 in `data-raw/provenance_population.csv`). The population downloads are cached outside the repository (see `pop_cache()` in `data-raw/population/population_functions.R`).
* A yearly update (`data-raw/update_data.R`) is much smaller than a rebuild: the SPC file, the ZCTA boundary file of the boundary year and the tabulation blocks of the states that the new year's tornadoes touch; with the block results cached by `data-raw/add_population.R` only the blocks along the new paths are read. The DAT data are fetched whole again (`data-raw/dat/fetch_dat.R`, then `data-raw/dat/build_dat.R`): the service can change, so a rebuild can differ from the stored DAT datasets, and the link tables are rebuilt from the new fetch.
* Raw downloads are not archived with the package or the repository, and are never committed. The md5 and size of each SPC download, with the years that came from it (`data-raw/provenance_years.csv`), the manifest of every population download and the software versions (`data-raw/provenance.txt`) let a rebuild check that it reads the same files; the DAT fetch is described by `data-raw/dat/fetch/fetch_summary.rds` (count the service reported, features read, size, time; git-ignored) and its date in `data-raw/dat/access_date.txt`.
* Risk: a full rebuild depends on the Census Bureau, SPC and the DAT service keeping their URLs available and unchanged. If they move, disappear, or (for SPC and the DAT service) are revised, a rebuild will not reproduce the shipped data, although the shipped data stay valid. Yearly updates append only new years to the SPC tables and leave stored years frozen.
<!-- dependence:end -->

<!-- settings:start -->
## Constants of the package

Every constant in the code that is not a source value, with its definition, value, reason and effect. None was tuned to make a result look better.

| Constant (file) | Definition | Value | Reason | Effect |
|---|---|---|---|---|
| `first_year` (`data-raw/pipeline_functions.R`) | first year of the data | 1996 | inherited from the original package; no reason is documented | tornadoes before 1996 are not in the package |
| loss break year, guard limits (`spc_clean()`) | the year SPC's loss changes from millions to dollars, and the yearly median and maximum limits that detect a moved break | 2007; median at most 1 and maximum at most 10,000 (millions) before; median at least 10,000 (dollars) from | the observed ranges (before 2007: median at most 0.07, maximum 1,000; from 2007: median at least 50,000) lie on both sides of the limits | the build stops if the break moves; no value changes |
| exact-conversion tolerance (`spc_clean()`) | largest relative difference between the converted loss and a whole number of dollars | 1e-9 | floating-point error | the build stops if a value is not a whole number of dollars |
| sanity limits of the update (`check_new_rows()`) | latitude, longitude, width, length, loss | latitude 15 to 72, longitude -180 to -60, width 0 to 10,000 yards, length 0 to 400 miles, known loss with a median of at least 10,000 and a maximum below 1e11 dollars | corrupt records fall outside; the extremes in the data lie well inside | the update stops and writes nothing; no value changes |
| block share tolerance (`block_shares()`) | largest share of a block inside a path above 1 that is treated as floating-point error | 1e-9 | the largest share found is 1 plus floating-point error | the build stops above it; a share is never capped |
| candidate-block margin (`pop_aff_cached()`) | distance by which the paths are buffered before choosing the blocks to intersect | 5 km | the paths are straight in EPSG:5070 but curved in longitude/latitude (up to about 1 km for the longest paths) | a block that a path touches is never missed (checked by `data-raw/qa/35_population_candidate_check.R`) |
| link window (`data-raw/dat/pairing_functions.R`) | DAT lines and SPC tornadoes are candidates when dated within this many days | 1 day | SPC uses local dates and the DAT date is the UTC date of `stormdate`, so the same event can be a day apart | a line is linked only to a tornado within a day |
| link sample points (`n_samples`) | equally spaced points along each path for the index-aligned distance | 21 | a point every 5% of the length | defines `index_aligned_dist_km` and `one_sided_dist_km` |
| distance index factor (`.distance_pairs()`) | oversize factor of the buffer used to pick candidate pairs before exact distances | 1.05 | the index uses a buffer in a projection | no pair within the radius is missed; exact distances decide |
| display notes (`R/`) | a message is printed above these sizes | more than 2,000 damage points; a distance call estimated at 20 seconds or more | a note for large requests | no result changes |
<!-- settings:end -->

<!-- unchecked:start -->
## Numbers that no script recomputes

`data-raw/qa/check_documented_claims.R` matches 34 numbers or statements in the help pages, the README and the code against the data (the generated blocks of this file are written by the QA scripts from the data). In this file 63 numbers outside the generated blocks are not matched: quoted source text of external documents, dates and urls, and values read from external documents. They are listed in `data-raw/qa/out/numbers_without_a_script.csv` and are not checked by a script.
<!-- unchecked:end -->
