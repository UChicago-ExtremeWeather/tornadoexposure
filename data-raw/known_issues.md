<!-- intro:start -->
# Known issues in the source data and the derived tables

Numbers below were computed by the scripts in `data-raw/qa/` from the data built from the SPC file `1950-2025_all_tornadoes.csv` (accessed 2026-10-12, md5 and size in `provenance.txt`) and the NWS Damage Assessment Toolkit data queried on 2026-11-11. They describe the current build; run the scripts again after a data change. No data are changed to work around any of these items.

**Terms used on this page.**

* *Exposed*: a ZCTA is exposed by the SPC when the SPC line (the straight line from SPC's start point to its end point) crosses it, that is, a positive length of the line lies in it; for a tornado with no usable end point, when the ZCTA contains the start point. It is exposed by the NWS survey when a damage polygon of a linked NWS line covers some land in it.
* *Footprint*: the union of the damage polygons rated EF0 to EF5 that a linked DAT line touches (the polygon rule); it is cut into zones by the highest rating that covers each part.
* *Land-only shape*: a unit polygon (ZCTA or block) minus the Census water polygons inside it.
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
| `tornado_tracks` | SPC, one row per tornado (whole-track record): a line from the raw start to the raw end point, or a point at the start for a tornado with no usable end point; SPC's raw coordinates, length and width; loss as given and in dollars | 38,027 | 18 + geometry | 1.35 MB |
| `tornado_exposure` | one row per tornado and ZCTA that the SPC line crosses or a linked NWS polygon covers land in: line length and share, distances (`boundary_dist_km`, `centroid_dist_km`), ZCTA areas and population, and the DAT columns (area and residents by rating, damage point counts) | 57,407 | 49 | 2.58 MB |
| `dat_exposure_tract` | NWS columns only, one row per tornado and census tract that a linked NWS polygon covers land in: land-only area share and residents by rating, damage point counts | 8,005 | 29 | 0.37 MB |
| `dat_exposure_blockgroup` | as `dat_exposure_tract`, for census block groups | 12,308 | 29 | 0.52 MB |
| `zcta_centroids` | Census, one population-weighted centroid per ZCTA and boundary year, with the ZCTA's population, polygon area and land area | 98,932 | 10 | 2.90 MB |
| `dat_points` | NWS Damage Assessment Toolkit, every damage point, all fields, unmodified | 241,456 | 28 + geometry | 12.89 MB |
| `dat_lines` | NWS Damage Assessment Toolkit, every damage line (centerline of a surveyed track), all fields, unmodified | 13,021 | 32 + geometry | 3.09 MB |
| `dat_polygons` | NWS Damage Assessment Toolkit, every damage polygon, all fields, unmodified | 11,172 | 21 + geometry | 3.41 MB |
| `tornado_dat_link` | one row per DAT line linked to an SPC tornado, with every number that describes the link | 11,573 | 13 | 0.47 MB |
| `dat_polygon_line_link` | one row per DAT polygon and line dated within a day of each other: distance and the share of the line inside the polygon | 466,150 | 4 | 3.22 MB |

The files in `data/` add up to 31.56 MB. Census inputs (ZCTA boundaries, block populations and shapes, water polygons) are read when the data are built and are not shipped; maps and the boundary distance download the full TIGER/Line files (sizes in `?get_data` and `?map_exposure`).
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
| A tornado with no usable end point (end coordinates missing, 0 or equal to the start) is a POINT at the start; SPC's raw coordinates, length and width are kept | 10,384 tornadoes (27.3%): end 0 1, end equal to the start 10,383 | Yes: no end point is invented; such a tornado exposes only the ZCTA that contains the start point |
| A width of 0 or missing is never replaced; the width is not used to draw any shape | 473 tornadoes (138 lines, 335 points) | Nothing is changed |
| The SPC line is the straight line (straight in EPSG:5070) from SPC's start to SPC's end point; a ZCTA is exposed when a positive length of the line lies in it, and the share of the line in each ZCTA is measured in EPSG:5070 (the length of the whole line is measured on the sphere) | 27,643 line tornadoes, 46,711 SPC rows; 0 line-ZCTA pairs that touch at a point only (zero length) are not exposures | A line between two rounded points, not a damage path (section SPC exposure) |
| Coordinates are projected to EPSG:5070 for areas, lengths and overlays, to a regional CRS for distances (EPSG:5070 in the 48 states, EPSG:3338 Alaska, ESRI:102007 Hawaii, EPSG:32161 Puerto Rico) and to EPSG:4269 for block points; maps are drawn in EPSG:4326 | every geometry that is measured or intersected | Yes: projection |
| ZCTA polygons repaired with `st_make_valid()` (counted in EPSG:5070 as read) | 2000 file: 0 of 32,038; 2010 file: 1 of 33,120; 2020 file: 0 of 33,791 | Yes: repairing invalid geometry |
| Census block polygons repaired with `st_make_valid()` (counted over all blocks as read by the audit 52b; the DAT pipeline reads only the blocks of the tracts that the footprints reach and found 0 invalid) | invalid blocks: 2000: 0 of 8,262,363; 2010: 0 of 11,155,486; 2020: 0 of 8,174,955 | Yes: repairing invalid geometry |
| Intersections of lines with ZCTAs: the pieces of one line in one ZCTA are merged (their lengths are added) | 56,683 SPC rows (46,711 from a line, 9,972 from a start point; 0 start points lie in more than one ZCTA) | Yes: merging |
| A start point that lies in no ZCTA has no SPC row in `tornado_exposure` | 412 point tornadoes (they stay in `tornado_tracks`) | Yes: nothing is moved or invented |
| Land-only shapes: the Census water polygons (AREAWATER) are subtracted from each ZCTA polygon and from each block polygon the footprints reach; areas and residents use the result, and the unit polygons and water polygons themselves are not changed | ZCTAs with a water polygon inside: 2000: 28,528 of 32,038; 2010: 29,217 of 33,120; 2020: 29,352 of 33,791; blocks with a water polygon inside: 270,526 of 1,288,841 (blocks of the tracts the footprints reach); water polygons repaired: 0; the land-only ZCTA shape differs from `ALAND` by more than 1% for 281 (2000), 298 (2010) and 252 (2020) ZCTAs | Yes: subtracting Census water polygons from Census unit shapes; both areas and `ALAND` are shipped |
| A block whose land-only shape is empty (area at most 0.001 square meters) but that has residents: the residents are allocated by the share of the block polygon that a footprint zone covers, and the block takes no part in the area shares | 59,298 of 1,288,841 blocks of the tracts reached have no land (27 with a Census land area above 0); 52 hold residents (526), of which 32.6 are allocated to a footprint | Yes: a computed allocation rule, not a source value (section Land-only shapes) |
| DAT footprints: the polygons rated EF0 to EF5 that a linked line touches are cut into zones by the highest rating (union and difference of polygons); a polygon that is invalid is repaired for this computation only | 6,072 polygons, 3,048 tornadoes, 4,813 zones; 0 polygons repaired; polygons not used: 1,464 with another `efscale` and 254 with no date (they stay in `dat_polygons`) | Yes: merging polygons and repairing invalid geometry; the shipped polygons are not changed |
| `zcta_centroids`: longitude and latitude are as computed (not rounded) | 98,932 rows | Nothing is rounded |
| `zcta_centroids`: the geometric centroid of a ZCTA with no residents is replaced by a point on the polygon surface when it falls outside the polygon | 5 of 342 ZCTAs with no residents (sum over the three boundary years) | Yes: a computed centroid, not a source value; the type is `geometric` |
| Population: a block with an `NA` population stops the build | 0 `NA` ZCTA populations; the 2020 block field `POP20` is `NA` for 0 blocks | Nothing is replaced |
| Population: a duplicated GEOID in a block file stops the build | 0 duplicated GEOIDs in 27,592,804 blocks | Nothing is dropped |
| Population: the share of the land of a block covered by a footprint zone, and every area share, is not capped; the build stops if it is above 1 by more than 1e-9 | 167,060 zone-block pieces; the largest share is 1.00000000017 | Nothing is capped |
| Population: a block whose internal point lies in more than one ZCTA keeps only its first ZCTA (`!duplicated(GEOID)`) | 5 blocks (5 rows dropped) in 2000: 2, 2010: 3, 2020: 0 | Not allowed under the fidelity rule without approval: reported to the maintainer |
| DAT features: every feature of the three layers is kept, all fields, full resolution, in the service's spatial reference; no generalization, simplification, date filter, swath filter or field selection | points 241,456, lines 13,021, polygons 11,172 (equal to the counts the service reported); 2 empty point, 21 empty line and 185 empty polygon geometries and 41 + 1 + 254 features without a date are kept | Nothing is changed |
| DAT dates: the text of milliseconds since 1970 is stored as a number (same value) and a `_utc` column is added | 13 added columns | Yes: type conversion without loss; the raw values are kept |
| DAT strings are as the service gives them (no character is removed) | 3 event ids contain a soft hyphen (U+00AD) and keep it | Nothing is changed |
| `tornado_dat_link` and `dat_polygon_line_link` are computed on copies of the geometries projected to EPSG:5070; a polygon that is invalid is repaired for the computation only | 0 polygons repaired; the shipped features are not repaired | Yes: projection and repairing invalid geometry |
| Maps and boundary distances use the full TIGER/Line boundaries, not the generalized cartographic files | every map and every `boundary_dist_km` call | Nothing is generalized |

**The SPC line is not a damage boundary at fine scales.** The SPC line is a straight line from SPC's start to SPC's end. It does not follow the curve of a real path, so it is not the path of the damage at scales finer than a kilometer: for the 11,369 SPC line tornadoes linked to a DAT line, the largest distance from a vertex of the DAT centerline to the SPC line has a median of 0.23 km and a 90th percentile of 1.78 km, by length of the SPC line: under 5 miles (7,981 links): median 0.11 km, 90th percentile 0.90 km; 5 to 20 miles (2,955 links): median 0.63 km, 90th percentile 1.98 km; over 20 miles (433 links): median 1.90 km, 90th percentile 4.82 km.

**Area basis.** The DAT area shares divide by the area of the land-only shape of the unit (the unit polygon minus the Census water polygons), so numerator and denominator come from the same geometry and a share cannot exceed 1 except by floating-point error. The Census land area (`ALAND`) is shipped as `zcta_land_area_m2` and the polygon area as `zcta_polygon_area_m2`; the ZCTA polygons include inland and coastal water, so the polygon area is larger than the land area: it differs by more than 1% in 18,819 of 57,407 rows and by more than 10% in 2,326.

**NCEI.** NCEI's Storm Events database is built from the same NWS Storm Data as SPC and is not independent of it. For 23,874 SPC tornadoes of 2007 to 2025 matched to NCEI events (within 2 km of the SPC line, within a day) the rating is equal for 99.64 percent (`data-raw/qa/54b_ncei_comparison.R`).

<!-- fidelity:end -->

<!-- loss:start -->
## Property loss (SPC `loss`)

* SPC loss of 0 means unknown, not $0 (NOAA's wording), so `property_loss_tornado_total` and `property_loss_allocated` are `NA` for those tornadoes (the raw value 0 stays in `tornado_tracks$loss_raw`). 19,567 of 38,027 tornadoes (51.5%) become `NA`: 7,418 of 13,865 in 1996-2006 (53.5%) and 12,149 of 24,162 from 2007 (50.3%). In `tornado_exposure` that is 25,563 of 57,407 rows (44.5%; 19,103 of the 37,382 tornadoes with rows). For tornadoes with a known loss and an SPC row the allocated values sum to the total; for the others, and for the rows that only the NWS polygons expose, they are `NA`.
* Loss is incomplete even for the deadliest tornadoes. Since 2007, 28 of 108 EF4 and EF5 tornadoes have no loss recorded (`NA`), and 3 of 29 tornadoes with at least 10 deaths (10 deaths is a cut-off chosen to show the deadliest tornadoes, not a tested choice). The Mayfield tornado `2021_2112102054-01` (57 deaths, 515 injuries) has loss 25,000 dollars.
* Units: nonzero values are in millions of dollars through 2006 (yearly median at most 0.07, maximum 1,000) and whole dollars from 2007 (yearly median at least 50,000). The pipeline multiplies 1996-2006 by one million (an exact conversion; the build stops if a result is not a whole number of dollars up to floating-point error), keeps the raw value in `tornado_tracks$loss_raw` with `loss_raw_unit`, and stops if the break moves (limits in the table of constants below). SPC re-coded 2007-2015 from millions to dollars between its 2024 and 2025 releases, so it can change again.
* Loss of the 645 tornadoes with no SPC row is not allocated: 56,387,000 dollars (181 tornadoes with loss above 0), 0.129% of all loss.
* The allocation of a tornado's loss to its ZCTAs (`property_loss_allocated`) uses the share of the SPC line in each ZCTA, so it assumes that damage is spread evenly along the line and is an approximation (section SPC exposure). It is `NA` for the 724 rows that only the NWS polygons expose.
<!-- loss:end -->

<!-- coordinates:start -->
## Coordinates

* SPC gives 1996-2006 coordinates to 0.01 degrees (about 1.1 km of latitude); from 2007 to 0.0001 degrees (about 11 m). The package does not round or move any coordinate. A simulation that moves each coordinate by up to half its rounding step (20 replicates, 1,000 tornadoes per era: sample sizes of this simulation, not tested choices; points keep the ZCTA that contains the start, lines use the ZCTAs the straight line crosses) changes the set of ZCTAs for 7.0% of 1996-2006 tornadoes per replicate (23.9% in at least one replicate) but 0.16% from 2007 (0.7% in at least one). A sensitivity analysis restricted to 2007 onward is recommended.
* From 2007 the reported length is close to the straight-line distance (`len_ratio` is above 1.5 for 1.1% of line tracks from 2007 against 21.9% in 1996-2006), which suggests that it is computed from the coordinates, so `len_ratio` cannot independently validate modern coordinates.
<!-- coordinates:end -->

<!-- spc-line:start -->
## SPC exposure (`spc_exposed`, `line_km_in_zcta`, `line_share_of_tornado`, `property_loss_allocated`)

SPC records only a start point, an end point and one width for each tornado. The package draws only the straight line between the two points (straight in EPSG:5070) and builds no polygon from the width. Real tornado paths curve and their width varies along the track, and SPC's coordinates are rounded (section Coordinates). A ZCTA is exposed when a positive length of the line lies in it; a ZCTA that the line only touches at a point (zero length) is not exposed (0 line-ZCTA pairs in the build, counted in `out/process_tracks.log`). A tornado with no usable end point is a point at its start and exposes the ZCTA that contains the start point; a start point that lies in no ZCTA gives no SPC row.

**Line length and share.** `line_share_of_tornado` is the length of the line in the ZCTA divided by the length of the line in all the ZCTAs it reaches (both measured in EPSG:5070), so it sums to 1 over the SPC rows of a tornado; it is 1 for a point tornado. `line_km_in_zcta` is that share times `line_km`, the length of the whole line measured on the sphere (the measure that also gives `len_ratio`); for the 27,643 lines the 5070 length is between 0.9610 and 1.0401 times the spherical length (1st to 99th percentile 0.9927 to 1.0082). `line_km_outside_zcta` (in `tornado_tracks`) is `line_km` minus the kilometers in ZCTAs: 1,548 lines have more than 1e-6 km of their length in no ZCTA (water, areas that the Census assigns to no ZCTA; smaller values are floating-point residue, the largest is 4.3e-14 km).

**What SPC's width means.** NWS instructions for Storm Data define the path width entered for a tornado as the maximum width. NWSI 10-1605 ([current text, 26 July 2021](https://www.weather.gov/media/directives/010_pdfs/pd01016005curr.pdf)), section 47.7 "Determining Path Length and Width": "Path length (in miles and tenths of miles) and maximum path width (in yards) will be indicated for all tornadoes, including each member of families of tornadoes, or for all segments of multi-segmented tornadoes." The archived text of 6 January 2003 ([archived appendix](https://www.weather.gov/media/directives/010_pdfs_archived/pd01016005a_incomplete.pdf)), section 31 "Tornado (C)": "Path width in the entry header is the maximum width over the entire path, or of each segment in a multi-segment tornado." SPC compiles its database from Storm Data. SPC's current description ([SPC_severe_database_description.pdf](https://www.spc.noaa.gov/wcm/data/SPC_severe_database_description.pdf)) gives only "Width in yards". The package keeps `wid_yd` as given (a width of 0 is not replaced) and does not use it to draw anything.

**Comparison with the NWS damage polygons.** For the 3,042 tornadoes with a linked DAT line and at least one linked EF0 to EF5 polygon (`data-raw/qa/66_spc_vs_dat.R`), the SPC line and the polygons expose the same ZCTA in 5,896 tornado-ZCTA pairs, the line alone in 245 and the polygons alone in 724; the two sets agree for 85.9% (pairs in both over pairs in either), 86.0% for line tornadoes and 58.5% for the 25 tornadoes with no usable end point. Per tornado the median agreement is 100.0%; 2,643 tornadoes have identical sets and 7 have no ZCTA in common. The ZCTAs exposed only by the polygons are 6.80 km (median), 125.49 km (90th percentile) and 386.43 km (largest) from the SPC line. The accuracy of the NWS polygons has not been measured.

**Position.** For the 11,369 SPC line tornadoes linked to a DAT line, the largest distance from a vertex of the DAT centerline to the SPC line has a median of 0.23 km and a 90th percentile of 1.78 km (`data-raw/qa/46_path_accuracy.R`; every link counts, whatever its distance). By length of the SPC line: under 5 miles (7,981 links): median 0.11 km, 90th percentile 0.90 km; 5 to 20 miles (2,955 links): median 0.63 km, 90th percentile 1.98 km; over 20 miles (433 links): median 1.90 km, 90th percentile 4.82 km. A distance radius smaller than these values cannot separate exposure from path-location error.
<!-- spc-line:end -->

<!-- land:start -->
## Land-only shapes

Areas that are shares of a unit (the DAT area shares of `tornado_exposure`, `dat_exposure_tract` and `dat_exposure_blockgroup`) use land-only shapes: the unit polygon minus the Census water polygons (TIGER/Line AREAWATER, one file per county; TIGER2020 for the 2020 boundary year and TIGER2010 for the 2010 and 2000 boundary years, `data-raw/provenance_water.csv`) that lie inside it, computed in EPSG:5070 (`data-raw/land_functions.R`). Nothing is simplified or rounded: a land-only shape is the unit polygon with the part inside a water polygon removed. Invalid polygons are repaired with `st_make_valid()` and counted below.

**ZCTAs against the Census land area (`ALAND`).** The ratio is the area of the land-only shape divided by `ALAND`, for every ZCTA of each boundary year (3,234 water files, 1,138 MB for 2020; 3,234 files, 1,132 MB for 2010 and 2000; 2,256,912 and 2,302,418 water polygons, of which 0 were invalid and repaired; the ZCTA polygons repaired: 2000: 0, 2010: 1, 2020: 0):

| Boundary year | ZCTAs | With a water polygon inside | Ratio, 1st percentile | Ratio, median | Ratio, 99th percentile | Smallest ratio | Within 1% | Within 5% | Within 10% | More than 1% apart |
|---|---|---|---|---|---|---|---|---|---|---|
| 2000 | 32,038 | 28,528 | 0.9914 | 1.0000000 | 1.0000104 | 0.602 | 99.12% | 99.88% | 99.96% | 281 |
| 2010 | 33,120 | 29,217 | 0.9912 | 1.0000000 | 1.0000099 | 0.613 | 99.10% | 99.85% | 99.95% | 298 |
| 2020 | 33,791 | 29,352 | 0.9926 | 1.0000000 | 1.0000032 | 0.462 | 99.25% | 99.88% | 99.96% | 252 |

The land-only shape reproduces `ALAND` for 99.25% of the 2020 ZCTAs within 1%. The ZCTAs that differ by more than 1% (831 in all three boundary years, listed in `data-raw/qa/out/land_zcta_over1pct.csv`) are those where the Census counts water-feature area as land (dry lakes, tidal and coastal areas) or the reverse. The 20 largest differences in the 2020 boundary year:

| ZCTA | Census land area (m2) | Land-only shape (m2) | Ratio |
|---|---|---|---|
| 93562 | 231,804,783 | 107,158,060 | 0.462 |
| 99664 | 6,962,779,342 | 4,705,907,658 | 0.676 |
| 99801 | 5,699,104,433 | 4,139,486,125 | 0.726 |
| 93549 | 1,280,714,042 | 1,031,109,357 | 0.805 |
| 99566 | 24,385,142,667 | 20,174,007,173 | 0.827 |
| 01944 | 23,904,339 | 20,127,933 | 0.842 |
| 37134 | 101,323,916 | 85,712,691 | 0.846 |
| 92262 | 90,928,556 | 77,633,061 | 0.854 |
| 99568 | 2,277,443,276 | 1,946,403,653 | 0.855 |
| 38113 | 39,208,091 | 33,861,415 | 0.864 |
| 96104 | 616,682,391 | 537,628,430 | 0.872 |
| 37086 | 64,173,213 | 56,347,845 | 0.878 |
| 96110 | 305,476,121 | 269,330,249 | 0.882 |
| 99573 | 9,898,716,754 | 8,852,867,535 | 0.894 |
| 99574 | 8,526,432,958 | 7,679,622,470 | 0.901 |
| 98304 | 863,750,382 | 778,457,282 | 0.901 |
| 85323 | 45,943,633 | 41,831,712 | 0.911 |
| 98391 | 99,368,539 | 90,960,110 | 0.915 |
| 72073 | 294,486,363 | 273,049,725 | 0.927 |
| 32949 | 43,523,098 | 40,454,073 | 0.929 |

**Blocks against the block land area.** The same ratio for every block of the census tracts that the DAT footprints reach (the blocks of the tracts and block groups tables; the ratio is the land-only shape divided by the block's `ALAND`):

| Boundary year | Blocks of the tracts reached | Median ratio | Within 1% | Within 5% | Within 10% | More than 1% apart | More than 10% apart | No Census land, land shape above 0 | Land shape zero, residents above 0 |
|---|---|---|---|---|---|---|---|---|---|
| 2000 | 2,248 | 1.0000000 | 100.00% | 100.00% | 100.00% | 0 | 0 | 0 | 0 |
| 2010 | 627,152 | 1.0000000 | 99.77% | 99.93% | 99.97% | 1,331 | 180 | 0 | 0 |
| 2020 | 659,441 | 1.0000000 | 99.65% | 99.92% | 99.97% | 2,224 | 162 | 0 | 52 |

**Rule.** Residents are allocated by the share of each block's land-only shape that a footprint zone covers (people live on land), because the land-only block shape reproduces the block `ALAND` within 1% for 99.71% of these blocks and within 5% for 99.93%. The area shares of tracts and block groups divide by the sum of the land-only shapes of their blocks (the blocks of a tract or block group are the blocks with the same GEOID prefix).

**Blocks with no land.** A block whose land-only shape has an area of at most 0.001 square meters is treated as having no land: the subtraction leaves floating-point residue where a block boundary and a water boundary coincide (the largest residue is 1.37e-05 square meters; the smallest land-only shape of a block with Census land area is 1.11 square meters). 59,298 of the 1,288,841 blocks of the tracts the footprints reach have no land, 27 of them with a Census land area above 0. 52 of them hold residents (526 residents): these are allocated by the share of the block polygon that a zone covers (15 zone-block pieces, 32.6 residents in all). They take no part in the area shares.
<!-- land:end -->

<!-- dat-exposure:start -->
## DAT columns, tract and block-group tables

**Rule.** A DAT polygon belongs to a tornado when a DAT line linked to the tornado (`tornado_dat_link`) touches it (`dat_polygon_line_link`, `line_share_in_polygon` above 0: a zero test, not a cutoff; the share is the length of the line inside the polygon over the length of the line, computed on the polygon repaired with `st_make_valid()` where invalid). Only polygons rated EF0 to EF5 are used; a polygon with any other `efscale` stays in `dat_polygons` and is not used. A polygon with no date (254 of 11,172) is never linked, and a polygon with an empty geometry (185) touches nothing; both stay in `dat_polygons`. The rule is the same for every tornado and has no parameter.

**Counts.** 6,571 tornado-polygon pairs touch a linked line: 6,150 are rated EF0 to EF5 (6,072 polygons, 3,048 tornadoes) and 421 have another `efscale` (343 polygons; 1,464 of the 11,172 polygons in `dat_polygons` have an `efscale` other than EF0 to EF5):

| efscale of a touching polygon that is not used | Pairs |
|---|---|
| EFU | 7 |
| N/A | 1 |
| TSTM/Wind | 319 |
| UNKNOWN | 94 |

**Zones.** The polygons of different ratings overlap, so each tornado's footprint is cut into 4,813 zones by the highest rating that covers each part (a zone is the union of the polygons of one rating minus the union of the polygons rated higher); the zones do not overlap, so their areas add up to the area of the union and each part is counted once. 0 polygons were invalid and are repaired with `st_make_valid()` for this computation only (the shipped polygons are not repaired).

**Footprints with no ZCTA row.** 3,048 tornadoes have a footprint; 3,042 of them have at least one ZCTA with polygon land. The other 6 have zones that cover no land of any ZCTA of their boundary year (areas the ZCTA files do not cover); 4 of those have rows in `dat_exposure_tract` and `dat_exposure_blockgroup`, and 2 have no row in any table (the zones cover no land).

**Rows.** 56,683 rows are exposed by the SPC line; the linked polygons cover land in 6,620 tornado-ZCTA pairs, 5,896 of them also exposed by the line and 724 only by the polygons (`spc_exposed` `FALSE`; 289 tornadoes; the distance from the SPC line to their boundary has a median of 6.80 km, a 90th percentile of 125.49 km and a maximum of 386.43 km). 12,934 rows of linked tornadoes are exposed only by the line (`dat_exposed` `FALSE`, area and residents 0). Rows and tornadoes of the three tables:

| Table | Rows | Tornadoes |
|---|---|---|
| `tornado_exposure` | 57,407 | 37,382 |
| `dat_exposure_tract` | 8,005 | 3,046 |
| `dat_exposure_blockgroup` | 12,308 | 3,046 |

**DAT-only rows far from the SPC line.** Of the 724 DAT-only rows (`spc_exposed` `FALSE` and `dat_exposed` `TRUE`) in 289 tornadoes, for 246 tornadoes every such row lies within 5 km of the SPC line (`boundary_dist_km`); the others are farther: 379 rows (43 tornadoes) beyond 5 km, 256 (17) beyond 25 km and 112 (5) beyond 100 km, the farthest 386.43 km. These are probably wrong links or surveys of another tornado. No cutoff is applied: 5, 25 and 100 km are descriptive values, not recommendations, and `dat_link_dist_km` (the largest one-sided distance among the tornado's linked lines, from `tornado_dat_link`; `NA` where `dat_linked` is `FALSE`) and `boundary_dist_km` can be used to filter.

**By rating** (a part of the footprint is given the highest rating that covers it):

| Rating | Tornado-ZCTA rows with area | Residents |
|---|---|---|
| EF0 | 4,728 | 1,441,764 |
| EF1 | 3,642 | 793,846 |
| EF2 | 1,222 | 135,408 |
| EF3 | 446 | 61,063 |
| EF4 | 108 | 29,246 |
| EF5 | 2 | 25 |

**Residents.** 2,461,351 residents are in the covered land of the rows of `tornado_exposure`; 0 more reside in blocks assigned to a ZCTA that has no row for the tornado, and 1 in blocks assigned to no ZCTA (they appear in the tract and block-group tables). The share of the land of a block covered by a zone is at most 1.00000000017 and no share is capped.

**Damage points.** 214,212 damage-point counts (a point counts once for each tornado within a day) are in the rows of linked tornadoes; the counts cover only the ZCTAs, tracts and block groups that have a row for the tornado. Points are counted by `efscale` as entered (`EF0` to `EF5`, `EFU`, `TSTM/Wind`, and all other values or none in `dat_points_other`). A point dated within a day of a tornado can belong to another tornado: `other_tornadoes_in_zcta_within_a_day` counts the other SPC tornadoes whose line crosses the ZCTA within a day.

<!-- dat-exposure:end -->

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

**Exposure.** The SPC line (36.6 km; 0.0 km of it lie in no ZCTA) crosses 12 ZCTAs (8 in Missouri, 4 in Illinois). The linked NWS polygons (EF1 and EF3) cover land in 13 ZCTAs; 9 are exposed by both, 3 only by the SPC line and 4 only by the NWS polygons (`spc_exposed` is `FALSE` there, and their SPC columns are `NA` except the distances). The polygons cover 6.80 percent of the land of the ZCTAs they reach, and 54,458 residents (EF3 part: 671, EF1 part: 25,550), by the highest rating that covers each part. 11,010 NWS damage points lie in these ZCTAs within a day. The table gives each ZCTA:

| ZCTA | SPC line | NWS polygons | Residents | Points | Boundary distance |
|---|---|---|---|---|---|
| 62025 | 8.22 km (share 0.225) | 0.0079 of the land (EF3 0.0000, EF1 0.0008) | 338 | 54 | 0.00 km |
| 62026 | 1.47 km (share 0.040) | 0.0034 of the land (EF3 0.0000, EF1 0.0000) | 0 | 1 | 0.00 km |
| 62040 | 9.70 km (share 0.265) | 0.0622 of the land (EF3 0.0000, EF1 0.0225) | 5,427 | 485 | 0.00 km |
| 62048 | 3.59 km (share 0.098) | 0.0150 of the land (EF3 0.0000, EF1 0.0128) | 0 | 10 | 0.00 km |
| 63105 | 1.61 km (share 0.044) | 0.4490 of the land (EF3 0.0000, EF1 0.3187) | 9,564 | 400 | 0.00 km |
| 63112 | 2.27 km (share 0.062) | 0.5447 of the land (EF3 0.0000, EF1 0.3244) | 10,558 | 870 | 0.00 km |
| 63115 | 2.64 km (share 0.072) | 0.5154 of the land (EF3 0.0110, EF1 0.2043) | 12,135 | 3803 | 0.00 km |
| 63120 | 0.72 km (share 0.020) | no | 0 | 0 | 0.00 km |
| 63124 | 0.05 km (share 0.001) | no | 0 | 7 | 0.00 km |
| 63130 | 3.18 km (share 0.087) | 0.0333 of the land (EF3 0.0000, EF1 0.0078) | 316 | 40 | 0.00 km |
| 63133 | 0.51 km (share 0.014) | no | 0 | 0 | 0.00 km |
| 63147 | 2.65 km (share 0.072) | 0.2105 of the land (EF3 0.0000, EF1 0.1326) | 16 | 98 | 0.00 km |
| 63107 | no | 0.2913 of the land (EF3 0.0000, EF1 0.1719) | 2,583 | 859 | 1.84 km |
| 63108 | no | 0.3921 of the land (EF3 0.0015, EF1 0.1872) | 5,966 | 1339 | 1.82 km |
| 63110 | no | 0.0910 of the land (EF3 0.0000, EF1 0.0487) | 29 | 78 | 1.66 km |
| 63113 | no | 0.6530 of the land (EF3 0.0693, EF1 0.3286) | 7,527 | 2966 | 0.60 km |

**NCEI.** NCEI's Storm Events database has three events for it: event 1262242 (ILLINOIS, EF1, 14.31 miles, 1035 yards); event 1262206 (MISSOURI, EF2, 2.3 miles, 500 yards); event 1262207 (MISSOURI, EF0, 6.61 miles, 1750 yards). NCEI is built from the same NWS Storm Data as SPC and is not independent.

A check of this case is in `data-raw/qa/check_data_integrity.R`.
<!-- st-louis:end -->

<!-- no-end-point:start -->
## Tornadoes with no usable end point

A tornado has no usable end point when SPC's end coordinates are missing, equal to 0, or equal to the start coordinates. 10,384 of the 38,027 tornadoes (27.3%) are of this kind (10,383 have an end equal to the start, 1 an end of 0 or missing). 7,849 of them (75.6%) are from 1996 to 2006 and 2,535 (24.4%) from 2007 on. The package draws each as a POINT at the start (`track_type = "point"`), keeps SPC's raw coordinates, length and width, and exposes only the ZCTA that contains the start point (the real path has an unknown direction and may extend up to the reported length from the start; `line_km_in_zcta` is `NA`). In `tornado_exposure` such a tornado has one SPC row, the ZCTA that contains the start point; 412 start points lie in no ZCTA and have no SPC row.

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

**Plain reading.** 81.4% of these tornadoes are EF0 (84.2% of those with a rating) and the median reported length is 0.20 mile, but SPC gives a length above 0 for 98.9% of them, 1,448 are 1 mile or longer, 117 are 5 miles or longer, and the longest is 80.0 miles, so they are not all brief touchdowns: the real path may extend up to the reported length from the start point in an unknown direction. The share follows the era more than the strength: between 1996-2006 and 2007 on it falls by 55 percentage points among EF0 tornadoes and 26 points among EF1 to EF5, while within 1996-2006 it differs by 44 points between EF0 and EF1 to EF5 (15 points from 2007 on). Coordinates before 2007 are rounded to 0.01 degrees, so start and end points of short tornadoes often coincide.
<!-- no-end-point:end -->

<!-- distance:start -->
## Exposure definitions and distance exposure

A call uses one exposure definition. The default returns the rows of `tornado_exposure`: the ZCTAs that a positive length of the SPC line lies in (the ZCTA that contains the start point, for a tornado with no usable end point) and the ZCTAs in which a linked NWS polygon covers land. `centroid_dist_km` and `boundary_dist_km` are measured from the SPC line (the start point for a tornado with no usable end point) and have no upper limit; a ZCTA with a positive `boundary_dist_km` is not crossed by the line.

**Joplin, Missouri, 22 May 2011** (`2011_1105221634-01`, EF5, 3 ZCTAs crossed by the SPC line: 64804 64840 64844), with the ZCTAs starting with 647, 648 or 649 (the radii are examples, not recommendations):

| Definition | ZCTAs | ZCTA codes |
|---|---|---|
| exposed (default) | 3 | 64804 64840 64844 |
| centroid_dist_km = 1 | 0 |  |
| centroid_dist_km = 5 | 2 | 64804 64840 |
| centroid_dist_km = 10 | 5 | 64801 64804 64840 64841 64844 |
| boundary_dist_km = 1 | 3 | 64804 64840 64844 |
| boundary_dist_km = 5 | 6 | 64801 64804 64840 64844 64850 64862 |

**Nationwide centroid-distance query** (every tornado, every ZCTA of each boundary year, one core; `seconds` is the time of the query and is the basis of the time estimate that `get_data()` prints for large requests):

| Radius (km) | Tornado-ZCTA rows | Tornadoes without a row | Seconds | SPC-exposed pairs with the centroid within the radius | Rows that are not SPC-exposed pairs |
|---|---|---|---|---|---|
| 1 | 4,843 | 33,767 | 4 | 8.2% | 4.6% |
| 5 | 36,736 | 16,408 | 11 | 45.4% | 30.0% |
| 10 | 103,695 | 5,419 | 24 | 76.3% | 58.3% |
| 25 | 504,343 | 343 | 103 | 98.0% | 89.0% |
| 50 | 1,774,382 | 13 | 352 | 99.8% | 96.8% |

The result of a centroid-distance call is not a superset of the SPC-exposed set: a large ZCTA crossed at its edge can have a centroid farther than the radius, as the share of exposed pairs within each radius shows. The distance from the SPC line to the centroid is measured in a projection that suits the region (EPSG:5070 in the 48 states, EPSG:3338 in Alaska, ESRI:102007 in Hawaii, EPSG:32161 in Puerto Rico).
<!-- distance:end -->

<!-- population:start -->
## Population (`zcta_pop`, `dat_pop_affected` and the tract and block-group residents)

`zcta_pop` is the sum of the populations of the census blocks assigned to a ZCTA (total population, all ages), with blocks assigned to ZCTAs by their internal points. `dat_pop_affected` and its parts by rating are the residents in the land covered by the linked NWS polygons: each block keeps its population, which is allocated by the share of the block's land-only shape that the polygons cover (uniform density on the land of a block), and the residents of the blocks assigned to a ZCTA are added up. Tract and block-group residents are the sums over the blocks of the unit (the first 11 or 12 digits of the block GEOID). Population is fixed at the census year within each decade (2000 blocks for years before 2010, 2010 blocks for 2010 to 2019, 2020 blocks from 2020). Sources: TIGER/Line tabulation blocks, with population from field `POP20` (2020) or the Census PL 94-171 redistricting files (2010 and 2000); URLs, sizes and checksums are in `data-raw/provenance_population.csv`.

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
| 2000 | IL | 4,000 | 3,954 | 100.00% | 1.000 | 46 | 100.0% |
| 2000 | MA | 4,000 | 3,926 | 100.00% | 1.000 | 74 | 100.0% |
| 2000 | MO | 4,000 | 3,970 | 100.00% | 1.000 | 30 | 100.0% |
| 2000 | NJ | 4,000 | 3,924 | 100.00% | 1.000 | 76 | 100.0% |
| 2000 | TX | 4,000 | 3,738 | 100.00% | 1.000 | 262 | 100.0% |
| 2010 | CA | 4,000 | 3,729 | 100.00% | 1.000 | 271 | 100.0% |
| 2010 | IL | 4,000 | 3,982 | 100.00% | 1.000 | 18 | 100.0% |
| 2010 | MA | 4,000 | 3,979 | 100.00% | 1.000 | 21 | 100.0% |
| 2010 | MO | 4,000 | 4,000 | 100.00% | 1.000 | 0 | n/a |
| 2010 | NJ | 4,000 | 3,964 | 100.00% | 1.000 | 36 | 100.0% |
| 2010 | TX | 4,000 | 3,820 | 100.00% | 1.000 | 180 | 100.0% |
| 2020 | CA | 4,000 | 3,863 | 100.00% | 1.000 | 137 | 100.0% |
| 2020 | IL | 4,000 | 4,000 | 100.00% | 1.000 | 0 | n/a |
| 2020 | MA | 4,000 | 3,987 | 100.00% | 1.000 | 13 | 100.0% |
| 2020 | MO | 4,000 | 4,000 | 100.00% | 1.000 | 0 | n/a |
| 2020 | NJ | 4,000 | 3,995 | 100.00% | 1.000 | 5 | 100.0% |
| 2020 | TX | 4,000 | 3,904 | 100.00% | 1.000 | 96 | 100.0% |

**Blocks whose internal point lies in two ZCTAs.** 5 blocks (all blocks of the three boundary years, `52b_block_validity_duplicates.R`) have an internal point on the boundary of two ZCTAs; the assignment keeps the first ZCTA (`!duplicated(GEOID)`), which the fidelity rule does not allow without approval, so it is reported (section What is and is not done to the source data).

**Integrity of the residents.** For the 19,554 rows of the 10,659 linked tornadoes, `dat_pop_affected` never exceeds `zcta_pop` (up to floating-point error), the parts by rating add up to the total, and no share of a block is capped: the largest share of the land of a block covered by a polygon zone is 1.00000000017 (the build stops above 1 by more than 1e-9). The blocks of the tracts that the footprints reach number 1,288,841 (167,060 polygon-block pieces); 52 blocks have residents and no land in their land-only shape (their 526 residents are allocated by the share of the block polygon covered, section Land-only shapes). Residents in a block assigned to a ZCTA that has no row for the tornado (the polygons cover land in the block's tract but no land in the ZCTA) are not in `tornado_exposure`: 0 residents in all; residents in blocks assigned to no ZCTA: 1. 2020 block counts have disclosure-avoidance noise added by the Census Bureau, which is larger for small areas.
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

645 of 38,027 tornadoes (1.70%) have no SPC row in tornado_exposure (the SPC line crosses no ZCTA of their Census boundary year, or the start point lies in none). All 645 have no row at all (no linked NWS polygon covers land in a ZCTA either). They stay in `tornado_tracks`, and their property loss is not assigned to any ZCTA. They fall in three categories, defined by rules:

* **Over water** (115): the track does not touch state land in the Census cartographic boundary file of the states (2020, 1:500,000).
* **Over land, no ZCTA nearby** (397): the track touches state land, and more than 50% of the land within 3 km of the path is not covered by any ZCTA of the tornado's boundary year (median share of that land not covered: 91%). The 3 km and 50% are values chosen to describe the cases, not tested choices.
* **On land, mostly covered** (133): the track touches state land, and at most 50% of the land within 3 km of the path is not covered (median share not covered: 35%).

**By Census boundary year** (2000: 472, 2010: 119, 2020: 54) **and track type** (233 line, 412 point):

| Census boundary year | over water | over land, no ZCTA nearby | on land, mostly covered | Total |
|---|---|---|---|---|
| 2000 | 113 | 243 | 116 | 472 |
| 2010 |   2 | 104 |  13 | 119 |
| 2020 |   0 |  50 |   4 |  54 |

| Track type | over water | over land, no ZCTA nearby | on land, mostly covered | Total |
|---|---|---|---|---|
| point | 104 | 192 | 116 | 412 |
| line |  11 | 205 |  17 | 233 |

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
| all other (36 states and territories) | 36 |  86 | 48 | 170 |

**Why there is no ZCTA.** The Census Bureau says that "Uninhabited areas (land and water areas) over two square miles are potentially left unassigned from 2020 ZCTA coverage" (https://www.census.gov/programs-surveys/geography/guidance/geo-areas/zctas.html). For the tornadoes of the 2020 boundary year, the connected area around the path that no ZCTA covers (measured in a window of 15 km around the path, so it can be larger) is shown below; the statement was checked for the 2020 file only, and the same numbers are given for the other boundary years without any claim about them.

| Census boundary year | Tornadoes | Uncovered area around the path over 2 square miles | Share | Median uncovered area (square miles) |
|---|---|---|---|---|
| 2000 | 472 | 412 | 99.0% | 172.6 |
| 2010 | 119 | 119 | 100.0% | 156.4 |
| 2020 |  54 | 53 | 100.0% | 179.8 |

**The 2000 file leaves out large water bodies.** The total area of the ZCTA polygons divided by the total land area was 1.010 in the 2000 file, against 1.023 in 2010 and 1.023 in 2020, and 328 of the 472 tornadoes without a ZCTA in the 2000 boundary year (69.5%) overlap a ZCTA of the 2010 or 2020 file:

| Census boundary year | ZCTA polygon area (million km2) | Land area ALAND (million km2) | Polygon area divided by land area |
|---|---|---|---|
| 2000 | 7.19 | 7.12 | 1.010 |
| 2010 | 7.60 | 7.43 | 1.023 |
| 2020 | 7.49 | 7.31 | 1.023 |

| Census boundary year | Tornadoes | Overlap a ZCTA of another boundary year | Share |
|---|---|---|---|
| 2000 | 472 | 328 | 69.5% |
| 2010 | 119 |  79 | 66.4% |
| 2020 |  54 |  39 | 72.2% |

**On land, mostly covered: a sample of 20 of the 133.** Of all 133, 116 have no usable end point (they are points), 57 lie within 100 m of a ZCTA and 120 within 500 m (median 130 m), 124 overlap a ZCTA of another boundary year, and the median uncovered area around the path is NA square miles (4 of them below 2 square miles). What is going on: these are mostly short or point paths (narrow polygons) that lie a short distance from the edge of a ZCTA, next to an unassigned area, and most land nearby is covered, so the polygon falls just outside the ZCTA edge; the ZCTA is close but the path polygon does not reach it. The same path overlaps a ZCTA of another boundary year in most cases, so the gap depends on the boundary file. The sample (random, seed 20):

| Tornado | State | Track type | Length (mi) | Width (yd) | Distance to nearest ZCTA (m) | Land within 3 km not covered | Uncovered area around the path (square miles) | Overlaps a ZCTA of another boundary year |
|---|---|---|---|---|---|---|---|---|
| 2007_0709221200-01 | CA | point | 0.10 |  15 |    3 | 9% | NA | yes |
| 2012_1203171630-01 | CA | point | 0.01 |  50 |  311 | 27% | 73.34 | yes |
| 2020_2003171525-01 | TX | line | 0.07 |  35 |  259 | 43% | 97.29 | yes |
| 2006_1072 | FL | point | 0.30 |  50 |  125 | 37% | 29.86 | no |
| 1998_34 | IA | point | 0.20 |  30 |    4 | 5% | NA | yes |
| 2005_822 | IA | point | 0.10 |  25 | 1135 | 39% | 14.83 | yes |
| 2001_789 | IA | point | 0.60 |  35 |    0 | 4% | NA | yes |
| 2000_270 | AR | point | 2.00 |  30 |  184 | 44% | NA | yes |
| 1999_553 | AL | point | 0.10 |  50 |   29 | 1% | NA | yes |
| 2002_219 | AR | line | 1.50 |  50 |   11 | 46% | NA | yes |
| 2001_262 | MN | point | 2.00 |  25 |  355 | 9% | 1.08 | yes |
| 2014_1405310830-01 | SC | line | 0.11 |  30 |   10 | 0% | 165.70 | yes |
| 2008_0801101310-01 | LA | point | 0.25 |  30 |    0 | 15% | NA | yes |
| 1997_73 | TX | point | 0.20 |  20 |  362 | 43% | 58.73 | yes |
| 2003_696 | TX | point | 1.50 |  50 |  362 | 43% | 59.85 | yes |
| 2009_0911062330-01 | OR | point | 0.09 |  80 |    3 | 9% | NA | no |
| 2001_1085 | TX | point | 0.50 |  30 |   41 | 5% | NA | yes |
| 2000_1074 | FL | point | 0.50 |  80 |   68 | 22% | NA | yes |
| 2003_830 | TX | point | 0.30 | 100 |  756 | 43% | 27.36 | yes |
| 2004_216 | FL | point | 0.50 |  30 |  136 | 15% | 194.78 | yes |
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

A tornado in such an area has no exposure row for it. To estimate how many 1996-2009 tornadoes are affected, each missing ZCTA was placed at its Gazetteer internal point, as a disc with the official land area (222 codes) or a point (629 codes with no land area); 278 have no coordinates and cannot be placed. By this estimate 310 of 17,863 tornadoes (1.74%) reach a missing ZCTA: 276 of them also have a row for another ZCTA, so they lose only a pair, and 34 are among the 472 tornadoes of the 2000 vintage that intersect no ZCTA. The real areas are irregular and a disc around one point only approximates them, so the count is approximate; no error bound was computed. The 2010 and 2020 files contain none of the missing codes.
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

Unknown ratings (`magnitude` is `NA`): 1,546 of 38,027 tornadoes. There are none in 1996 to 2006, 21 in 2007 (1.9% of that year), none in 2008 to 2015, and some in every year from 2016 to 2025: 17 to 268 a year (1.5% to 20.3% of the tornadoes of the year). Counts of EF0 tornadoes are comparable across years only if unknown ratings are included, and this matters from 2016 on. Tornadoes per year by rating:

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
* A full rebuild reads the SPC tornado file (one URL, 9.2 MB), the full TIGER/Line ZCTA files for 2000, 2010 and 2020 (through tigris), and, for population and land-only shapes, the Census TIGER/Line water polygons (2.3 GB, 6468 files, `data-raw/provenance_water.csv`) and the Census TIGER/Line tabulation blocks (2020: 11.4 GB; 2010: 7.0 GB; 2000: 5.8 GB) and the PL 94-171 files (1.0 GB for 2010 and 0.4 GB for 2000), 26.4 GB in all (367 files, listed with size and md5 in `data-raw/provenance_population.csv`). The population downloads are cached outside the repository (see `pop_cache()` in `data-raw/population/population_functions.R`).
* A yearly update (`data-raw/update_data.R`) is much smaller than a rebuild: the SPC file and the ZCTA boundary file of the boundary year. The DAT data are fetched whole again (`data-raw/dat/fetch_dat.R`, then `data-raw/dat/build_dat.R` and `data-raw/dat/build_dat_exposure.R`, which reads the tabulation blocks of the states the DAT footprints touch and the water polygons): the service can change, so a rebuild can differ from the stored DAT datasets, and the link tables and DAT columns are rebuilt from the new fetch.
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
| share tolerance (`block_pass()`, `build_dat_exposure.R`) | largest share of the land of a block, ZCTA or unit covered by the footprint above 1 that is treated as floating-point error | 1e-9 | the largest share found is 1 plus floating-point error | the build stops above it; a share is never capped |
| polygon rule (`footprint_pairs()`) | a DAT polygon belongs to a tornado when a linked line touches it, and only polygons rated EF0 to EF5 are used | `line_share_in_polygon` above 0; efscale EF0 to EF5 | a zero test, not a cutoff; the other values of `efscale` are not damage ratings | which polygons make up a tornado's footprint (section DAT columns) |
| damage-point window (`build_dat_exposure.R`) | a damage point counts for a tornado when its UTC date is within this many days of the tornado's date | 1 day | the same window as the link, for the same reason | the `dat_points_*` columns |
| link window (`data-raw/dat/pairing_functions.R`) | DAT lines and SPC tornadoes are candidates when dated within this many days | 1 day | SPC uses local dates and the DAT date is the UTC date of `stormdate`, so the same event can be a day apart | a line is linked only to a tornado within a day |
| link sample points (`n_samples`) | equally spaced points along each path for the index-aligned distance | 21 | a point every 5% of the length | defines `index_aligned_dist_km` and `one_sided_dist_km` |
| distance index factor (`.distance_pairs()`) | oversize factor of the buffer used to pick candidate pairs before exact distances | 1.05 | the index uses a buffer in a projection | no pair within the radius is missed; exact distances decide |
| display notes (`R/`) | a message is printed above these sizes | more than 2,000 damage points; a distance call estimated at 20 seconds or more | a note for large requests | no result changes |
<!-- settings:end -->

<!-- unchecked:start -->
## Numbers that no script recomputes

`data-raw/qa/check_documented_claims.R` matches 48 numbers or statements in the help pages, the README and the code against the data (the generated blocks of this file are written by the QA scripts from the data). In this file 63 numbers outside the generated blocks are not matched: quoted source text of external documents, dates and urls, and values read from external documents. They are listed in `data-raw/qa/out/numbers_without_a_script.csv` and are not checked by a script.
<!-- unchecked:end -->
