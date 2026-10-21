# Known issues in the source data and the model

Numbers below were computed from the data built on 2026-10-12 (SPC file
`1950-2025_all_tornadoes.csv`, md5 in `provenance.txt`). They describe the
current build; run the scripts in `data-raw/qa/` again after the data change. No data are
changed to work around any of these items.

**Terms used on this page.**

* *Path polygon*: the area of a tornado's path as the package models it. For a line track it is the straight
  line from SPC's start point to its end point, buffered by half of SPC's width with flat ends. For a point
  track it is a disc.
* *Point track*: a tornado with no usable end point (start equal to end, or an end that is zero or missing).
  `track_type = "point_equal_area"`: SPC gives a length, and the disc, centered on the start point, has an area
  equal to length times width. `track_type = "point_half_width"`: the length is 0, and the disc has a radius of
  half the width. The direction is unknown.
* *Chord*: the straight-line distance between a tornado's start and end points.
* *Percentiles* (10th, 25th, 75th, 90th and 99th, with the median): they describe the spread of a distribution; none is a tested choice.
* *Vintage*: the Census Bureau ZCTA boundary file of the 2000, 2010 or 2020 census (the same name is used for
  the block data of that census). Tornadoes of 1996-2009 use 2000, 2010-2019 use 2010, and 2020 on use 2020.
* *Survey layer*: exposure computed from the damage swaths that National Weather Service offices surveyed
  (`get_survey_data()`). Its terms (`status` values, usable damage swath, swath filter) are defined in the section
  "Path accuracy" under "Values of `status`".

## Property loss (SPC `loss`)

* SPC loss of 0 means unknown, not $0 (NOAA's wording), so `property_loss_tornado_total`
  and `property_loss_allocated` are `NA` for those tornadoes (the raw value 0 stays in
  `tornado_tracks$loss_raw`). 19,567 of 38,027 tornadoes (51.5%) become `NA`: 7,418 of
  13,865 in 1996-2006 (53.5%) and 12,149 of 24,162 from 2007 (50.3%). In `tornado_exposure`
  that is 25,599 of 58,162 rows (44.0%; 19,126 of the 37,439 tornadoes with rows), and in
  `survey_exposure` 2,485 of 6,007 rows (1,325 of 2,937 tornadoes). For tornadoes with a known
  loss the allocated values sum to the total; for the others they are `NA`.
* Loss is incomplete even for the deadliest tornadoes. Since 2007, 28 of 108 EF4
  and EF5 tornadoes have no loss recorded (`NA`), and 3 of 29 tornadoes with at least 10 deaths (10 deaths is a cut-off chosen to show the deadliest tornadoes, not a tested choice).
  The Mayfield tornado `2021_2112102054-01` (57 deaths, 515 injuries) has loss
  25,000. NCEI's Storm Events database has the same deaths and injuries when its
  county segments are summed (57 and 515), with property damage blank for the
  EF4 segments; SPC's 25,000 is the damage NCEI lists for the first (Obion, TN)
  segment. `2011_1104271719-01` (EF5, 25 deaths) has 0 injuries and 0 loss in
  SPC and in NCEI (event 301829: 25 direct deaths, 0 injuries, 0.00K damage).
* Units: nonzero values are in millions of dollars through 2006 (yearly median
  at most 0.07, maximum 1,000) and whole dollars from 2007 (yearly median at
  least 50,000). The pipeline multiplies 1996-2006 by one million, keeps the raw
  value in `tornado_tracks$loss_raw` with `loss_raw_unit`, and stops if the break
  moves. The check stops the pipeline if a year before 2007 has a median above 1
  or a value above 10,000, or if a year from 2007 has a median below 10,000; these
  limits lie between the observed ranges, so they catch only a moved break. SPC
  re-coded 2007-2015 from millions to dollars between its 2024 and
  2025 releases (the 2025 value is one million times the 2024 value for matched
  tornadoes), so it can change again.
* Loss of the 588 tornadoes that intersect no ZCTA is not allocated: 18,571,000
  dollars (147 tornadoes with loss above 0), 0.043% of all loss.

## Coordinates

* 1996-2006 coordinates are rounded to 0.01 degrees (about 1.1 km of latitude); from 2007 they
  are rounded to 0.0001 degrees (about 11 m). A simulation that moves each coordinate by
  up to half its rounding step (20 replicates, 1,000 tornadoes per era: sample sizes of this simulation, not tested choices) changes
  the set of ZCTAs for 7.9% of 1996-2006 tornadoes per replicate (24.7% in at
  least one replicate) but 0.23% from 2007 (0.9% in at least one). At
  `area_thresh = 0.01` (an example value, not a recommendation), 9.95 of 153 exposed tornado-ZCTA pairs (6.5%) flip per
  replicate before 2007 and 0.45 of 310 (0.15%) from 2007. A sensitivity
  analysis restricted to 2007 onward is recommended.
* From 2007 the reported length is close to the straight-line distance (`len_ratio` is
  above 1.5 for 1.1% of line tracks from 2007 against 21.9% in 1996-2006; see below), which
  suggests that it is computed from the coordinates, so `len_ratio` cannot independently
  validate modern coordinates.

<!-- path-accuracy:start -->
## Path accuracy (straight line, one width)

SPC records only a start point, an end point and one width for each tornado, so the package draws every tornado as a straight line between the two
points, buffered by half the width. Real tornado paths curve and their width varies along the track. Point tracks (no usable end point) are discs, and their
direction is unknown.

**What SPC's width means.** NWS instructions for Storm Data define the path width entered for a tornado as the maximum width.
NWSI 10-1605 ([current text, 26 July 2021](https://www.weather.gov/media/directives/010_pdfs/pd01016005curr.pdf)), section 47.7
"Determining Path Length and Width": "Path length (in miles and tenths of miles) and maximum path width (in yards) will be indicated for all
tornadoes, including each member of families of tornadoes, or for all segments of multi-segmented tornadoes." The archived text of
6 January 2003 ([archived appendix](https://www.weather.gov/media/directives/010_pdfs_archived/pd01016005a_incomplete.pdf)), section 31
"Tornado (C)": "Path width in the entry header is the maximum width over the entire path, or of each segment in a multi-segment tornado."
SPC compiles its database from Storm Data. SPC's current description
([SPC_severe_database_description.pdf](https://www.spc.noaa.gov/wcm/data/SPC_severe_database_description.pdf)) gives only "Width in yards", and an
older SPC format document ([torforma.doc](https://www.spc.noaa.gov/wcm/torforma.doc)) describes a mean width ("Mean tornado path width ... The mean
width along the entire track is reported"). This package treats `wid` as the maximum width. Two checks agree with that. For the 2,941 tornadoes with a usable swath, the modeled path area, built from `wid`, is a median of 1.21 times the surveyed swath area (10th to 90th percentile 0.40 to 2.20), which is consistent with a maximum width held along the whole path where the real width varies. For Joplin, SPC gives 1,600 yards (0.91 mile) and the NWS Service Assessment says the path was up to 1 mile wide. These checks do not show which width SPC recorded for every tornado.

**Modeled versus surveyed paths.** The National Weather Service's [Damage Assessment Toolkit](https://apps.dat.noaa.gov/StormDamage/DamageViewer/) (DAT)
holds surveyed centerlines and damage swath polygons. The DAT describes its own data as preliminary. Four case studies of long, strong tornadoes that have a survey (they are among the longest and strongest, so their offsets are larger than typical; see the calibration below for all paired tornadoes):

| Tornado | Median / maximum distance from the surveyed centerline to the modeled line | Surveyed centerline farther than the modeled half-width | Modeled polygon vs surveyed swath | Surveyed swath inside the modeled polygon |
|---|---|---|---|---|
| Moore, OK 2013 | 1.25 / 5.21 km | 71% | 37.4 vs 18.5 km2 (2.0 times) | 21.3% |
| Mayfield, KY 2021 | 4.73 / 6.70 km | 96% | 626.9 vs 403.7 km2 (1.6 times) | 2.0% |
| Tuscaloosa-Birmingham, AL 2011 | 3.73 / 5.14 km | 90% | 306.8 vs 110.5 km2 (2.8 times) | 8.6% |
| Rainsville, AL 2011 | 1.56 / 3.11 km | 80% | 65.4 km2 vs no usable survey swath | n/a |

The modeled polygons are 1.6 to 2.8 times larger than the surveyed swaths in the cases with a usable swath (the width, treated as the maximum, is held along the whole path). For Joplin (2011) the survey layer has status `no_pair` and no survey GIS was found. The NWS [Service
Assessment](https://www.weather.gov/media/publications/assessments/Joplin_tornado.pdf) gives a path 22.1 miles long and up to 1 mile wide, with the EF4-EF5 portion about 6 miles long and generally one-half to three-quarters of a mile wide; SPC has a length of 21.62 miles and a width of 1,600 yards.

**Calibration across the paired tornadoes with a usable swath (line tracks).** The largest distance between the surveyed centerline and the modeled straight line, by straight-line (chord) length:

| Chord length | Tornadoes | Maximum offset, median (km) | Maximum offset, 90th percentile (km) | Maximum offset beyond the modeled half-width | Typical (median) offset beyond the half-width |
|---|---|---|---|---|---|
| under 5 mi | 1,860 | 0.11 | 0.53 | 62.2% | 46.6% |
| 5-20 mi | 880 | 0.65 | 1.71 | 89.8% | 66.9% |
| over 20 mi | 179 | 2.02 | 4.84 | 98.9% | 80.4% |
| all | 2,919 | 0.25 | 1.39 | 72.8% | 54.8% |

The maximum offset is about 4% of the chord length (median). An offset estimate based on the difference between `len` and the straight-line distance was tested against these surveys and was a weak predictor (rank correlation 0.39 to 0.48 by chord class), so it is not used.

**Modeled area against surveyed area.** For the 2,941 tornadoes with a usable swath, the modeled path polygon area divided by the surveyed swath area:

| Chord length | Tornadoes | 10th pct | 25th pct | Median | 75th pct | 90th pct | Modeled larger than surveyed |
|---|---|---|---|---|---|---|---|
| under 5 mi | 1,860 | 0.41 | 0.79 | 1.21 | 1.65 | 2.28 | 64.2% |
| 5-20 mi | 880 | 0.35 | 0.70 | 1.16 | 1.52 | 1.96 | 61.8% |
| over 20 mi | 179 | 0.65 | 1.01 | 1.37 | 1.80 | 2.56 | 75.4% |
| point track | 22 | 0.30 | 0.47 | 1.14 | 2.42 | 5.16 | 54.5% |
| all | 2,941 | 0.40 | 0.77 | 1.21 | 1.62 | 2.20 | 64.1% |

**Coverage.** The survey layer has a usable swath for 2,941 of the 24,162 SPC tornadoes since 2007 (12.2%), and a paired survey line for 10,671 (44.2%). Tornadoes with a usable swath are skewed toward stronger, longer and more recent ones: the median chord is 3.1 miles against 2.0 miles for all line tracks since 2007, and 6.1% are over 20 miles against 2.7%. By rating, year and chord length:

| Rating | SPC tornadoes since 2007 | Paired | Share paired | With a usable swath | Share with a usable swath |
|---|---|---|---|---|---|
| EF0 | 11,568 | 3,929 | 34.0% | 952 | 8.2% |
| EF1 | 8,306 | 4,578 | 55.1% | 1,319 | 15.9% |
| EF2 | 2,108 | 1,149 | 54.5% | 470 | 22.3% |
| EF3 | 526 | 286 | 54.4% | 162 | 30.8% |
| EF4 | 98 | 55 | 56.1% | 30 | 30.6% |
| EF5 | 10 | 5 | 50.0% | 3 | 30.0% |
| unknown | 1,546 | 669 | 43.3% | 5 | 0.3% |
| all | 24,162 | 10,671 | 44.2% | 2,941 | 12.2% |

| Year | SPC tornadoes since 2007 | Paired | Share paired | With a usable swath | Share with a usable swath |
|---|---|---|---|---|---|
| 2007 | 1,132 | 4 | 0.4% | 1 | 0.1% |
| 2008 | 1,704 | 25 | 1.5% | 1 | 0.1% |
| 2009 | 1,162 | 28 | 2.4% | 0 | 0.0% |
| 2010 | 1,302 | 56 | 4.3% | 0 | 0.0% |
| 2011 | 1,704 | 179 | 10.5% | 35 | 2.1% |
| 2012 | 948 | 112 | 11.8% | 47 | 5.0% |
| 2013 | 916 | 212 | 23.1% | 35 | 3.8% |
| 2014 | 928 | 341 | 36.7% | 117 | 12.6% |
| 2015 | 1,182 | 490 | 41.5% | 136 | 11.5% |
| 2016 | 976 | 468 | 48.0% | 161 | 16.5% |
| 2017 | 1,442 | 741 | 51.4% | 228 | 15.8% |
| 2018 | 1,138 | 580 | 51.0% | 190 | 16.7% |
| 2019 | 1,534 | 962 | 62.7% | 277 | 18.1% |
| 2020 | 1,090 | 757 | 69.4% | 222 | 20.4% |
| 2021 | 1,328 | 988 | 74.4% | 247 | 18.6% |
| 2022 | 1,167 | 912 | 78.1% | 256 | 21.9% |
| 2023 | 1,321 | 1,041 | 78.8% | 296 | 22.4% |
| 2024 | 1,805 | 1,559 | 86.4% | 384 | 21.3% |
| 2025 | 1,383 | 1,216 | 87.9% | 308 | 22.3% |
| all | 24,162 | 10,671 | 44.2% | 2,941 | 12.2% |

| Chord length | SPC tornadoes since 2007 | Paired | Share paired | With a usable swath | Share with a usable swath |
|---|---|---|---|---|---|
| under 5 mi | 16,312 | 7,384 | 45.3% | 1,860 | 11.4% |
| 5-20 mi | 4,724 | 2,746 | 58.1% | 880 | 18.6% |
| over 20 mi | 591 | 360 | 60.9% | 179 | 30.3% |
| point track | 2,535 | 181 | 7.1% | 22 | 0.9% |
| all | 24,162 | 10,671 | 44.2% | 2,941 | 12.2% |

The DAT has almost no surveys before 2011, so nothing here tests the 1996-2006 tracks.

**Why a rule is needed.** The survey database and SPC's database share no identifier, so each SPC tornado is paired with a survey line by comparing dates and paths. Survey lines that are exact copies of each other (same date, length and coordinates) are merged first: 11,624 lines became 11,410. Survey lines dated after 2025, the last year of the SPC data, are ignored.

**Date window.** The candidates for a tornado are the survey lines dated within 1 day of it. The value of 1 day does not come from an external source. It was tested at 0, 1 and 2 days (table below): 7,585 tornadoes are paired and 2,064 have a usable swath with 0 days, 10,671 and 2,941 with 1 day, and 10,698 and 2,942 with 2 days. One day was used because 0 days leaves 3,086 fewer tornadoes paired and 2 days adds only 27 (and 1 more usable swath). Dates differ by a day because of the time zone. The service stores the storm date as a date and time in UTC, and SPC records times in CST, six hours behind UTC (SPC database description, field 7, `tz`: "All times, except for ?=unknown and 9=GMT, were converted to 3=CST"). For 10,332 of the 10,671 pairs (96.8%) the survey date equals the UTC date of SPC's time, and 3,373 pairs (31.6%) have a survey date one day later than SPC's; of those, 3,262 (96.7%) have an SPC time of 18:00 CST (00:00 UTC) or later. The survey time of day equals SPC's time converted to UTC for 84.2% of the pairs (within one hour for 93.7%). Pairs one day apart are as close as pairs on the same date (table below), and only 25 pairs have a survey date one day earlier.

| Date window (days) | Candidate pairs | Tornadoes paired | Tornadoes with a usable swath |
|---|---|---|---|
| 0 | 274,297 | 7,585 | 2,064 |
| 1 | 574,168 | 10,671 | 2,941 |
| 2 | 717,289 | 10,698 | 2,942 |

| Pairs | Count | Median distance (km) | 90th percentile of the distance (km) | Median length ratio | Same state | With a usable swath |
|---|---|---|---|---|---|---|
| same date | 7,273 | 0.105 | 0.795 | 1.00 | 99.6% | 27.5% |
| date differs by 1 day | 3,398 | 0.119 | 0.761 | 1.00 | 99.5% | 27.8% |

**Distance.** The distance between a tornado and a survey line is measured in kilometers. Take 21 equally spaced points along each path, from its start to its end; the distance is the mean of the 21 distances between the points with the same number, with the survey line read in whichever direction (start to end, or end to start) gives the smaller mean. For an SPC point track, which has no direction, the distance is the distance from the point to the survey line.

**Pairing rule.** An SPC tornado is paired with its closest survey line when that line's closest tornado is also that tornado. Nothing else decides the pairing: there is no limit on the distance, no test on length or direction, no minimum length of survey line, and no tornado is left out as ambiguous. The reason is that this is the rule with the fewest steps: no value chosen by us (a distance limit, a length test) is imposed on the data.

**Counts.** Of the 11,410 survey lines, 10,671 are paired (93.5%); of the 24,162 SPC tornadoes since 2007, 10,671 are paired (44.2%).

**Limitation.** The rule has no cut-off, so a tornado with no real survey counterpart can be paired with a distant survey line: 226 of the 10,671 pairs (2.1%) have a survey line farther away than the larger of the SPC tornado's reported length and 0.1 mile (the shortest length assumed in SPC's older format description), 17 of them with a usable swath; the distance and length ratio of every pair are in `survey_matches`.

**Values of `status` in `survey_matches`.**

| Status | Meaning | Count |
|---|---|---|
| included | The tornado was paired with a survey line (its closest survey line, whose closest tornado is also this tornado) and the survey has a usable damage swath (below). It is in `survey_exposure` and `survey_tracks`. | 2,941 |
| no_swath | The tornado was paired with a survey line, but no rated damage polygon remains along the surveyed centerline after the swath filter, or the remaining polygons lie within 200 meters of under 50% of the centerline. No exposure is computed. | 7,730 (7,680 with no polygon left, 50 with polygons near under half of the centerline) |
| no_pair | No survey line is paired with the tornado: its closest survey line has another tornado that is closer to it, or no survey line is dated within 1 day of the tornado. | 13,491 (5,943 with no survey line dated within 1 day) |

**Terms.**

| Term | Rule | Count |
|---|---|---|
| Usable damage swath | The swath (the kept damage polygons, merged) lies within 200 meters of at least 50% of the length of the surveyed centerline (`swath_cover` of 0.5 or more). | 2,941 of the 10,671 paired tornadoes |
| Swath filter | Of the damage polygons that cross the surveyed centerline on the same date (within one day), keep those rated EF0 to EF5 whose area lies at least 90% within a distance from the centerline equal to the SPC path width plus 500 meters. | Of the 6,332 polygons crossing the centerlines of the paired tornadoes, 5,926 were kept; 2,991 tornadoes keep at least one |

**Swath filter.** The survey database has damage polygons, not one swath per tornado. For a paired tornado, the polygons that cross the surveyed centerline on the same date (within one day) are kept when they are rated EF0 to EF5 and at least 90% of their area lies within a distance from the centerline equal to the SPC path width plus 500 m (this removes polygons of neighboring tornadoes and straight-line wind). The kept polygons are merged into the swath, which is usable when it lies within 200 m of at least 50% of the centerline's length. None of the four values (90%, 500 m, 200 m, 50%) comes from an external source. Each was changed in turn (table below). The number of tornadoes with a usable swath is 2,941 with the values used and ranges from 2,909 to 2,952 across the alternatives; the largest loss is 32 tornadoes (500 m -> 250 m) and the largest gain 11 (500 m -> 1,000 m). For tornadoes with a usable swath under both settings the swath area does not change.

| Setting | Tornadoes with a usable swath | Gained | Lost | Median change in swath area (%) | 90th percentile of the absolute change (%) |
|---|---|---|---|---|---|
| baseline | 2,941 | 0 | 0 | 0.00 | 0.00 |
| 90% -> 80% | 2,947 | 6 | 0 | 0.00 | 0.00 |
| 90% -> 95% | 2,932 | 0 | 9 | 0.00 | 0.00 |
| 500 m -> 250 m | 2,909 | 0 | 32 | 0.00 | 0.00 |
| 500 m -> 1,000 m | 2,952 | 11 | 0 | 0.00 | 0.00 |
| 200 m -> 100 m | 2,933 | 0 | 8 | 0.00 | 0.00 |
| 200 m -> 400 m | 2,945 | 4 | 0 | 0.00 | 0.00 |
| 50% -> 40% | 2,947 | 6 | 0 | 0.00 | 0.00 |
| 50% -> 60% | 2,926 | 0 | 15 | 0.00 | 0.00 |

**Polygon resolution.** The damage polygons were fetched with the service's generalization set to 0.0002 degrees (about 20 m), and the polygons stored in `survey_tracks` for plotting and distances are simplified to 50 m (no outline point moves by more than 50 m). Against full-resolution polygons, the area of the 20 m swaths has a median change of -0.18% and a 90th percentile of the absolute change of 13.64% (largest 126.8%); no tornado changes usability. The 50 m polygons differ from the 20 m swaths by a median of -0.37% and a 90th percentile of 20.37% (largest 322.2%), which matters for small swaths. The exposure columns of `survey_exposure` come from the 20 m swaths, so only plots and `centroid_dist_km` use the simplified polygons.

| Comparison | Tornadoes | Median change in area (%) | 90th percentile of the absolute change (%) | Largest absolute change (%) |
|---|---|---|---|---|
| 20 m generalization versus full resolution | 2,941 | -0.18 | 13.64 | 126.8 |
| 50 m simplification versus 20 m swath | 2,941 | -0.37 | 20.37 | 322.2 |

**Four pairing rules.** These are the alternatives tested; agreement changes little between them. Agreement at overlap is the number of tornado-ZCTA pairs exposed in both layers divided by the number exposed in either layer, for the tornadoes with a usable swath under the rule; the last column is the median, over the pairs exposed in both layers, of the SPC area share divided by the survey area share.

| Rule | Tornadoes paired | Tornadoes with a usable swath | Agreement at overlap | Median of SPC area share divided by survey area share |
|---|---|---|---|---|
| Fixed total end-point difference of 0.10 degrees, survey lines of 2 miles or more, length and direction tests | 5,773 | 1,838 | 92.4% | 1.22 |
| The same without a minimum length | 9,838 | 2,799 | 93.5% | 1.23 |
| Each end within the larger of 1 km and 25% of the chord, no minimum length, length and direction tests | 9,729 | 2,803 | 93.3% | 1.23 |
| Closest survey line in both directions (the survey layer), no tests, no minimum length | 10,671 | 2,941 | 92.1% | 1.24 |

**Which ZCTAs are exposed.** For the paired tornadoes with a usable swath. *Tornadoes*: those with at least one exposed ZCTA in either layer. *Pairs*: tornado-ZCTA pairs exposed in the SPC layer, in the survey layer, and in both. *SPC pairs also in survey*: pairs in both divided by SPC pairs. *Survey pairs also in SPC*: pairs in both divided by survey pairs. *Agreement*: pairs in both divided by pairs in either layer. *Tornadoes with identical ZCTAs*: the share of tornadoes whose list of exposed ZCTAs is the same in both layers.

| Definition | Tornadoes | Pairs, SPC layer | Pairs, survey layer | Pairs in both | SPC pairs also in survey | Survey pairs also in SPC | Agreement | Tornadoes with identical ZCTAs |
|---|---|---|---|---|---|---|---|---|
| Overlap: any part of the ZCTA is inside the path (SPC) or the swath (survey) | 2,937 | 6,103 | 6,007 | 5,806 | 95.1% | 96.7% | 92.1% | 88.8% |

**How large the shares are.** For the tornado-ZCTA pairs present in both layers (for the population row, those with a population share above 0 in both). *Median*: of the SPC share divided by the survey share. *Percentiles*: the 10th and 90th percentile of that ratio. *Rank correlation*: Spearman correlation between the SPC share and the survey share.

| Share | Pairs in both layers | Median of SPC value divided by survey value | 10th to 90th percentile of that ratio | Rank correlation between the two values |
|---|---|---|---|---|
| Area share (ZCTA land area inside the path or swath) | 5,806 | 1.24 | 0.37 to 3.21 | 0.888 |
| Population share (ZCTA residents inside the path or swath) | 5,563 | 1.19 | 0.30 to 3.98 | 0.900 |

**What this means.** The straight-line path shifts and widens the modeled swath. Of the ZCTAs exposed in either layer, 92.1% are exposed in both, and 88.8% of the tornadoes have the same list of ZCTAs in both. The size of the shares differs more: for the pairs in both layers, the SPC area share is a median of 1.24 times the survey area share (10th to 90th percentile 0.37 to 3.21) and the SPC population share a median of 1.19 times the survey population share (0.30 to 3.98). Population shares follow where residents live. Distance-based exposure (`centroid_dist_km`) is a way to allow for this uncertainty; the offsets between modeled and surveyed paths are given above by tornado length, and a radius smaller than them cannot separate exposure from path-location error. If the error in a tornado's position is unrelated to the outcome being studied, it generally pulls estimated associations toward zero (non-differential misclassification of exposure); this was not tested with these data.

Notes on the analysis (`data-raw/qa/11c`, `44`, `45`, `46`): DAT swath polygons are linked to the surveyed centerline spatially, because the polygon layer has no usable link field. Polygons that cross the centerline on the same date can include straight-line wind swaths, multi-tornado polygons and zones of neighboring tornadoes, which would inflate the surveyed side, so the swath filter keeps only rated EF0-EF5 polygons with at least 90% of their area within a distance of the SPC path width plus 500 m of the centerline, and requires the swath to lie within 200 m of at least half of the centerline. The survey build was rerun against the live service on 2026-10-15.
<!-- path-accuracy:end -->

<!-- when-to-use:start -->
## When to use SPC and when to use the survey data

*`get_survey_data()` returns the same exposure definitions for the tornadoes in the survey layer (credit, preliminary status and terms are in its help page).*

* Use `get_data()` (SPC) as the main exposure. It covers every tornado from 1996 on one consistent definition, and it is the right choice for trends over time and for tornadoes with no survey.
* Use `get_survey_data()` as a sensitivity analysis, not a replacement. The two sources agree on which ZCTAs a path touches (92.1% of the ZCTAs exposed in either layer are exposed in both) and differ more in how large the shares are (the SPC area share is a median of 1.24 times the survey area share, 10th to 90th percentile 0.37 to 3.21), so an exposure defined by an area or population share is where the two layers differ most.
* Do not compare survey-based and SPC-based results across years without care. The share of SPC tornadoes with a usable swath rises from 0.04% in 2007-2010 to 19% to 22% in each year of 2020-2025, so a survey-only trend would mostly reflect coverage.
* A tornado with no survey line, or whose closest survey line has another tornado closer to it, is not in the layer (status `no_pair`: 13,491 of 24,162 SPC tornadoes since 2007); the layer pairs each tornado with its closest survey line without a cut-off (see Limitation above).
* Suggested sensitivity design: restrict to tornadoes that have a usable survey swath, compute exposure both ways, and compare the estimates paired.
<!-- when-to-use:end -->

<!-- distance:start -->
## Exposure definitions and distance exposure (centroid_dist_km)

A call uses exactly one exposure definition, and every row returned is an exposed ZCTA under it.

* **Overlap** (no threshold): the path polygon intersects the ZCTA. Any overlap counts, including very small ones.
* **Area share** (`area_thresh`): the share of the ZCTA's land area covered by the path. It depends on the size of the ZCTA as well as on how the path crossed it: the same path covers a large share of a small ZCTA and a small share of a large one.
* **Population share** (`pop_thresh`): the share of the ZCTA's residents inside the path. It follows where residents live, so a path through a dense town and the same area of farmland in one ZCTA have the same area share but very different population shares.
* **Centroid distance** (`centroid_dist_km`): the population-weighted centroid of the ZCTA lies within this many kilometers of the path. The path does not have to overlap the ZCTA.

**Joplin (2011_1105221634-01)** as an example: which of the ZCTAs starting with 648 qualify, with the distance from the path to each ZCTA's population-weighted centroid. A blank means the ZCTA does not qualify; ZCTAs the path overlaps have a positive `area_prop_affected`. ZCTAs more than 10 km from the path are not listed (17 more qualify at `centroid_dist_km = 25`). The thresholds and radii in the table (0.05 and 0.5 of the land area, 0.05 and 0.25 of the residents, 5, 10 and 25 km) are example values chosen to show how the set of ZCTAs changes; none is a recommendation.

| ZCTA | Centroid distance (km) | area_prop_affected | pop_prop_affected | overlap | area_thresh = 0.05 | area_thresh = 0.5 | pop_thresh = 0.05 | pop_thresh = 0.25 | centroid_dist_km = 5 | centroid_dist_km = 10 | centroid_dist_km = 25 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 64804 | 0.3 | 0.100 | 0.094 | yes | yes |  | yes |  | yes | yes | yes |
| 64840 | 0.3 | 0.140 | 0.270 | yes | yes |  | yes | yes | yes | yes | yes |
| 64841 | 5.6 | 0.000 | 0.000 |  |  |  |  |  |  | yes | yes |
| 64801 | 6.2 | 0.000 | 0.000 |  |  |  |  |  |  | yes | yes |
| 64844 | 7.3 | 0.039 | 0.028 | yes |  |  |  |  |  | yes | yes |

ZCTAs that qualify for this tornado, by definition: `overlap`: 3; `area_thresh = 0.05`: 2; `area_thresh = 0.5`: 0; `pop_thresh = 0.05`: 2; `pop_thresh = 0.25`: 1; `centroid_dist_km = 5`: 2; `centroid_dist_km = 10`: 5; `centroid_dist_km = 25`: 22. The `area_thresh = 0.5` call returns an empty result with a message because no ZCTA reaches that share (the largest `area_prop_affected` for this tornado is 0.14).

**Distance exposure in detail.**

* Distance is measured from the path polygon to the **population-weighted centroid** of the ZCTA (block internal points weighted by block population, for the ZCTA boundary vintage of the tornado's year). It is 0 when the centroid is inside the path. Distances are computed on demand, with no upper limit on the radius. Alaska, Hawaii and Puerto Rico use a local projection for distances (the 48 states use EPSG:5070); against spherical geodesic distances the largest relative difference was Alaska 0.6% (56 pairs), 48 states 1.5% (11370 pairs), Hawaii 1.3% (320 pairs), Puerto Rico 0.5% (2068 pairs), measured on all tornado paths in Alaska, Hawaii and Puerto Rico and a sample of 60 in the 48 states (the spherical reference itself differs from the ellipsoid by up to about 0.5%).
* **The distance set is not a superset of the overlap set.** A large ZCTA crossed at its edge can have its centroid far from the path. Widening the radius only adds ZCTAs, but it takes a radius of tens of kilometers before most overlapped pairs are included. Over all 1996-2025 tornadoes (the radii of 1, 5, 10, 25 and 50 km are a span chosen to show the range; none is a recommendation):

| Radius (km) | Rows returned | Tornadoes with no row | Share of overlap pairs within the radius | Share of rows outside the overlap set | No-ZCTA tornadoes that get a row | Time (s) |
|---|---|---|---|---|---|---|
|  1 | 5,526 | 33,324 | 9.1% | 3.9% | 9 of 588 | 9 |
|  5 | 37,638 | 16,181 | 45.9% | 29.1% | 155 of 588 | 17 |
| 10 | 104,918 | 5,348 | 76.4% | 57.6% | 308 of 588 | 32 |
| 25 | 506,696 | 339 | 98.1% | 88.7% | 533 of 588 | 119 |
| 50 | 1,778,467 | 13 | 99.8% | 96.7% | 581 of 588 | 362 |

  (Timings are for a nationwide 1996-2025 call on one core of the machine that built the data; a request with a smaller `geo_list` or `year_range` is much faster, and slow calls print an estimate first.) An empty result is not an error: a tornado with no ZCTA centroid inside the radius returns no rows, and the package says so in a message.
* **Choosing a radius.** Choose the radius to fit your question; no radius is recommended here. SPC gives only a start point, an end point and one width, and real paths curve, so the exposed location is uncertain. In the comparison with NWS surveys (section "Path accuracy"), the largest distance between the surveyed centerline and the modeled straight line has a median of 0.11 km for tornadoes under 5 miles, 0.65 km for 5 to 20 miles and 2.02 km for those over 20 miles, and a 90th percentile of 0.53, 1.71 and 4.84 km. The four case studies of long, strong tornadoes in that section are larger: the largest offset is Mayfield 6.7 km, Tuscaloosa-Birmingham 5.1 km, Moore 5.2 km, Rainsville 3.1 km (medians 4.7 km, 3.7 km, 1.2 km, 1.6 km), so they should not be read as typical. A radius smaller than these offsets cannot separate exposure from path-location error. The table above shows how much of the overlap set each radius captures.
* **Zero-resident ZCTAs** use the geometric centroid (`centroid_type = "geometric"`, or a point on the polygon surface if the geometric centroid falls outside): 55 in the 2000 vintage, 144 in the 2010 vintage, 143 in the 2020 vintage. A result containing any triggers a warning.
* **Centroids outside their own ZCTA.** A population-weighted centroid can fall outside its polygon (a crescent-shaped or multi-part ZCTA): 917 of 31,983 in 2000 (1.54% of residents); 776 of 32,976 in 2010 (1.31% of residents); 672 of 33,631 in 2020 (1.16% of residents). It is kept (it is the defined quantity) and flagged by `centroid_in_zcta`. How far outside: median 0.16, 0.18, 0.17 km, 99th percentile 3.5, 4.0, 2.9 km (vintages 2000, 2010, 2020).
* **Population versus geometric centroid.** For ZCTAs with residents the two centroids differ by a median of 1.37, 1.33, 1.29 km (90th percentile 5.4, 5.4, 5.4 km; maximum 267, 422, 420 km) in the 2000, 2010 and 2020 vintages. The largest differences are large Alaska ZCTAs and ZCTAs with far-flung parts (for example Anchorage 99503) where residents are concentrated in one place.
<!-- distance:end -->

<!-- moore-comparison:start -->
## Example: the Moore, Oklahoma tornado under SPC and under the survey

The 20 May 2013 Moore tornado (`2013_1305201356-01`, EF5) with the ZCTAs starting with 731, using `get_data()` and `get_survey_data()` with the overlap definition. The README shows the same call for the survey; the SPC path is a straight line of 13.85 miles, and the survey line is 17.5 miles (see "Path accuracy" for the end-point differences).

| ZCTA | Area share, SPC path | Area share, survey swath | Residents in path, SPC | Residents in swath, survey |
|---|---|---|---|---|
| 73160 | 0.198 | 0.077 | 10,562 | 5,810 |
| 73165 | 0.066 | 0.014 | 202 | 23 |
| 73170 | 0.183 | 0.179 | 6,446 | 3,458 |
| 73173 | not exposed | 0.014 | not exposed | 5 |

<!-- moore-comparison:end -->

<!-- population:start -->
## Population (`pop_affected`, `zcta_pop`, `pop_prop_affected`)

`pop_affected` is the estimated number of residents (total population, all ages) inside the modeled path within a ZCTA. Each census block of the ZCTA vintage keeps its population, which is allocated to the path by the share of the block's area inside the path (uniform density within a block, water included in the block polygon). Blocks are assigned to ZCTAs by their internal points, and `zcta_pop` is the sum of the populations of the blocks assigned to a ZCTA. Population is fixed at the census year within each decade (2000 blocks for years before 2010, 2010 blocks for 2010 to 2019, 2020 blocks from 2020). Sources: TIGER/Line tabulation blocks, with population from field `POP20` (2020) or the Census PL 94-171 redistricting files (2010 and 2000); URLs, sizes and checksums are in `data-raw/provenance_population.csv`.

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

**Integrity.** `pop_affected` never exceeds `zcta_pop`, `pop_prop_affected` is within 0 to 1, and for every tornado the residents in the exposure rows plus the residents in blocks assigned to no ZCTA equal the residents in the modeled path. `pop_prop_affected` is `NA` for 23 rows (`zcta_pop` is 0). Its median is 0.00035, its 90th percentile 0.0164 and its 99th percentile 0.153; 4,906 rows (8.4%) have `pop_affected` 0.

**Joplin (`2011_1105221634-01`).** The modeled path holds 4,411 residents (64804: 3,521; 64840: 760; 64844: 129). No survey GIS exists for Joplin. The straight modeled path can sit kilometers from the real one (see Path accuracy), and the residents it holds depend strongly on its sideways position: shifting the modeled polygon sideways changes them from 1,213 to 14,031 (3.2 times the unshifted 4,411, reached at a shift of 3.5 km to the left of the direction of travel, about north, toward the Joplin city center, which is about 5 km north of the modeled centerline). The unshifted estimate is therefore very uncertain, and a path displaced to the north would hold several times more residents; without a survey the true figure cannot be determined.

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

Every notice found about the data of the survey layer, with its wording and location. The contact e-mail addresses in the notices are omitted.

* **Service description** of the layer queried here (<https://services.dat.noaa.gov/arcgis/rest/services/nws_damageassessmenttoolkit/DamageViewer/FeatureServer>, field `serviceDescription`): "Welcome to the National Weather Service Damage Assessment Toolkit. Data on this interface is collected during NWS Post-Event Damage Assessments. While the data has been quality controlled, it is still considered preliminary. Official statistics for severe weather events can be found in the Storm Data publication, available from the National Centers for Environmental Information (NCEI) at: https://www.ncdc.noaa.gov/IPS/sd/sd.html Questions regarding this data can be addressed to: [address omitted]."
* **Copyright text** of the same service (field `copyrightText`): "NOAA National Weather Service". The three layers (0 to 2) have no description or copyright text of their own.
* **NOAA GeoPlatform item** for the same service (<https://www.arcgis.com/home/item.html?id=b6b9dd55450a4f64bcafb3cd6e005a5c>, owner `nws.dat_noaa`, shared publicly, url field equal to the service above): credit "NOAA/National Weather Service"; use constraint "All data is considered preliminary and unofficial. While the data has been quality controlled, it is still considered preliminary. Official statistics for severe weather events can be found in the Storm Data publication, available from the National Centers for Environmental Information (NCEI) at: https://www.ncdc.noaa.gov/IPS/sd/sd.html". The item gives no license. The item description adds "Service defaults to show data with 'stormdate' for the preceding two weeks."
* **Viewer** (<https://apps.dat.noaa.gov/StormDamage/DamageViewer/>): the page is a JavaScript application whose configuration could not be read (access denied), so any splash text it shows was not read. Its portal item (<https://www.arcgis.com/home/item.html?id=96a415322c174d78b5cd02fa68650cfd>) has the same "still considered preliminary" statement and adds: "This web application can be used to view and query the DAT database. In addition, data may be extracted as a shapefile or kmz file using the 'Extract' widget."
* **GeoPlatform page** (<https://disasters-geoplatform.hub.arcgis.com/pages/noaa-damage-assessment-toolkit-dat>, page item <https://www.arcgis.com/home/item.html?id=b2b1055dffbc4818a4dc185b72efe2a8>, last modified 18 April 2025, on the GeoPlatform Disasters site, not in the NOAA GeoPlatform organization): under "Access & Use Information": "Public: This dataset is intended for public access and use." Under "Disclaimers": "While the data has been quality controlled, it is still considered preliminary." Its links are the viewer above and a map service, `https://services.dat.noaa.gov/arcgis/rest/services/DamageAssessmentToolkit/DamageFlexViewer/MapServer`, which returns "Service not found" today and is not the service queried here (`nws_damageassessmenttoolkit/DamageViewer/FeatureServer`). The page therefore describes the Damage Assessment Toolkit dataset in general; it is not confirmed to refer to this service.
* **What was not found:** no notice sets terms of use, a license or a citation format for these data. The general NWS statement for NWS web pages (<https://www.weather.gov/disclaimer>) is about web pages and is not quoted here.

<!-- unchecked:start -->
## Numbers that no script recomputes

`data-raw/qa/check_documented_claims.R` matches 128 numbers or statements in the README, the help pages and this file against the data (section 3b covers the constants, ranges, definitions and examples stated in the README and the help pages, as checks of the data and the code). The numbers it cannot match to a computed value are hand-written; they are listed in `data-raw/qa/out/numbers_without_a_script.csv`. In the README and the help-page sources they are all of these kinds:

* example value or argument (run when the README is built or the examples are checked): 40
* unit or rounding constant (section 3b of this script): 30
* range endpoint or rule (section 3b of this script): 29
* zero as a value or rule (section 3b of this script): 21
* code or identifier: 11
* percentile label, cut-off or definition: 11
* list numbering in quoted source text: 2

In this file 259 numbers outside the generated sections are not matched: cut-offs and their rationale, dates, quoted source text, counts from earlier runs of the QA scripts, and values read from external documents. They are not checked by a script.
<!-- unchecked:end -->

## Point tracks

* 10,384 of 38,027 tornadoes (27.3%) have no usable end point (start equal to
  end, or an end that is zero or missing): 56.6% of 1996-2006 tornadoes and
  10.5% from 2007, 41.1% of EF0 and 10.0% of EF1 and above. They are drawn as
  discs (`track_type` `point_equal_area` or `point_half_width`).
* Rounding explains most early points (92% of early tornadoes with reported
  length of at most 0.5 mi have start and end in the same 0.01 degree cell), but
  not all: 1,278 of the 7,730 early `point_equal_area` tracks have a reported
  length of at least 1 mile, and 170 of the 2,535 from 2007 (the cut-offs of 0.5 and
  1 mile are chosen to describe the lengths, not tested choices).
* NCEI has no better end coordinates: 49 of 50 sampled EF1+ point tracks have the
  same start and end in NCEI (a random sample of 25 tracks before 2007 and 25 from
  2007; the sample size is not a tested choice).

## `len` and coordinates disagree

* `len_ratio` (straight distance over reported length) is above 1.5 for 21.9% of
  1996-2006 line tracks and 1.1% from 2007. The most extreme is
  `2023_2301121527-01` (GA, EF2): `len` 125.76 miles against a 31.6 mile chord
  (ratio 0.25); SPC's file does not show whether `len` or the coordinates are wrong.
  Coordinates are used for the geometry. The ratio of 1.5 is a cut-off chosen to
  describe how far `len` departs from the straight-line distance, not a tested choice.
* 95 of 38,023 start points fall in a different state from the reported state
  (68 before 2007), and 246 fall outside every state
  outline (Census cartographic boundaries).

<!-- no-zcta:start -->
## Tornadoes without a ZCTA

588 of 38,027 tornadoes (1.55%) have a path polygon that overlaps no ZCTA of their Census boundary year, so they have no rows in `tornado_exposure`. They stay in `tornado_tracks`, and their property loss is not assigned to any ZCTA. They fall in three categories, defined by rules:

* **Over water** (109): the path polygon does not touch state land in the Census cartographic boundary file of the states (2020, 1:500,000).
* **Over land, no ZCTA nearby** (393): the path polygon touches state land, and more than 50% of the land within 3 km of the path is not covered by any ZCTA of the tornado's boundary year (median share of that land not covered: 91%). The 3 km and 50% are values chosen to describe the cases, not tested choices.
* **On land, mostly covered** (86): the path polygon touches state land, and at most 50% of the land within 3 km of the path is not covered (median share not covered: 38%).

**By Census boundary year** (2000: 416, 2010: 119, 2020: 53) **and track type** (232 line, 351 point_equal_area, 5 point_half_width):

| Census boundary year | over water | over land, no ZCTA nearby | on land, mostly covered | Total |
|---|---|---|---|---|
| 2000 | 107 | 239 | 70 | 416 |
| 2010 |   2 | 104 | 13 | 119 |
| 2020 |   0 |  50 |  3 |  53 |

| Track type | over water | over land, no ZCTA nearby | on land, mostly covered | Total |
|---|---|---|---|---|
| point_equal_area | 95 | 186 | 70 | 351 |
| line | 11 | 205 | 16 | 232 |
| point_half_width |  3 |   2 |  0 |   5 |

**By state** (start point, top 10 of the states and territories):

| State | over water | over land, no ZCTA nearby | on land, mostly covered | Total |
|---|---|---|---|---|
| TX |  7 | 141 | 13 | 161 |
| FL | 54 |  60 | 21 | 135 |
| LA |  0 |  27 |  6 |  33 |
| NC | 14 |   6 |  3 |  23 |
| KS |  0 |  19 |  3 |  22 |
| MN |  1 |  12 |  2 |  15 |
| WI |  0 |  12 |  3 |  15 |
| WY |  0 |  14 |  0 |  14 |
| CA |  0 |   7 |  5 |  12 |
| OK |  0 |  10 |  1 |  11 |
| all other (33 states and territories) | 33 |  85 | 29 | 147 |

**Why there is no ZCTA.** The Census Bureau says that "Uninhabited areas (land and water areas) over two square miles are potentially left unassigned from 2020 ZCTA coverage" (https://www.census.gov/programs-surveys/geography/guidance/geo-areas/zctas.html). For the tornadoes of the 2020 boundary year, the connected area around the path that no ZCTA covers (measured in a window of 15 km around the path, so it can be larger) is shown below; the statement was checked for the 2020 file only, and the same numbers are given for the other boundary years without any claim about them.

| Census boundary year | Tornadoes | Uncovered area around the path over 2 square miles | Share | Median uncovered area (square miles) |
|---|---|---|---|---|
| 2000 | 416 | 412 | 99.0% | 172.6 |
| 2010 | 119 | 119 | 100.0% | 156.4 |
| 2020 |  53 | 53 | 100.0% | 179.8 |

**The 2000 file leaves out large water bodies.** The total area of the ZCTA polygons divided by the total land area was 1.010 in the 2000 file, against 1.023 in 2010 and 1.023 in 2020, and 277 of the 416 tornadoes without a ZCTA in the 2000 boundary year (66.6%) overlap a ZCTA of the 2010 or 2020 file:

| Census boundary year | ZCTA polygon area (million km2) | Land area ALAND (million km2) | Polygon area divided by land area |
|---|---|---|---|
| 2000 | 7.19 | 7.12 | 1.010 |
| 2010 | 7.60 | 7.43 | 1.023 |
| 2020 | 7.49 | 7.31 | 1.023 |

| Census boundary year | Tornadoes | Overlap a ZCTA of another boundary year | Share |
|---|---|---|---|
| 2000 | 416 | 277 | 66.6% |
| 2010 | 119 |  79 | 66.4% |
| 2020 |  53 |  38 | 71.7% |

**On land, mostly covered: a sample of 20 of the 86.** Of all 86, 70 are point tracks, 17 lie within 100 m of a ZCTA and 73 within 500 m (median 206 m), 79 overlap a ZCTA of another boundary year, and the median uncovered area around the path is 43.01 square miles (4 of them below 2 square miles). What is going on: these are mostly short or point paths (narrow polygons) that lie a short distance from the edge of a ZCTA, next to an unassigned area, and most land nearby is covered, so the polygon falls just outside the ZCTA edge; the ZCTA is close but the path polygon does not reach it. The same path overlaps a ZCTA of another boundary year in most cases, so the gap depends on the boundary file. The sample (random, seed 20):

| Tornado | State | Track type | Length (mi) | Width (yd) | Distance to nearest ZCTA (m) | Land within 3 km not covered | Uncovered area around the path (square miles) | Overlaps a ZCTA of another boundary year |
|---|---|---|---|---|---|---|---|---|
| 2001_262 | MN | point_equal_area | 2.00 |  25 | 355 | 9% | 1.08 | yes |
| 2006_627 | SC | point_equal_area | 0.10 |  10 | 117 | 24% | 27.58 | yes |
| 1996_826 | FL | point_equal_area | 0.10 |  30 | 199 | 28% | 9.46 | yes |
| 2000_313 | FL | point_equal_area | 0.20 |  10 | 260 | 37% | 300.21 | yes |
| 2006_623 | FL | point_equal_area | 1.00 |  50 | 203 | 9% | 151.02 | yes |
| 2003_830 | TX | point_equal_area | 0.30 | 100 | 756 | 43% | 27.36 | yes |
| 2002_283 | LA | point_equal_area | 0.20 |  20 | 297 | 46% | 151.21 | yes |
| 2008_0809010900-01 | FL | point_equal_area | 0.10 |  20 |  69 | 40% | 23.55 | yes |
| 2006_69 | CA | point_equal_area | 0.20 |  15 |  54 | 2% | 172.35 | yes |
| 1997_1028 | TX | point_equal_area | 0.10 |  23 | 123 | 23% | 17.61 | yes |
| 2010_1006161700-01 | MT | line | 1.00 |  75 | 104 | 40% | 131.61 | yes |
| 2021_2112052024-01 | KY | line | 0.29 |  25 | 425 | 22% | 16.01 | yes |
| 2004_216 | FL | point_equal_area | 0.50 |  30 | 136 | 15% | 194.78 | yes |
| 2011_1108081813-01 | WI | line | 1.21 |  20 | 268 | 35% | 5.24 | no |
| 2005_174 | FL | point_equal_area | 0.10 |  50 |  69 | 40% | 23.58 | yes |
| 1996_743 | FL | point_equal_area | 0.10 |  20 | 181 | 35% | 124.17 | yes |
| 2004_1607 | NC | point_equal_area | 2.00 |  30 | 250 | 15% | 41.52 | yes |
| 2001_1027 | NY | point_equal_area | 0.10 |  50 | 100 | 38% | 180.70 | yes |
| 1997_598 | FL | point_equal_area | 0.20 |  10 |  98 | 5% | 0.62 | yes |
| 2019_1906021548-01 | ID | line | 1.00 |  45 |   0 | 45% | 102.59 | yes |
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

A tornado in such an area has no exposure row for it. To estimate how many 1996-2009 tornadoes are affected, each missing ZCTA was placed at its Gazetteer internal point, as a disc with the official land area (222 codes) or a point (629 codes with no land area); 278 have no coordinates and cannot be placed. By this estimate 313 of 17,863 tornadoes (1.75%) reach a missing ZCTA: 279 of them also have a row for another ZCTA, so they lose only a pair, and 34 are among the 416 tornadoes of the 2000 vintage that intersect no ZCTA. The real areas are irregular and a disc around one point only approximates them, so the count is approximate; no error bound was computed. The 2010 and 2020 files contain none of the missing codes.
<!-- zcta2000-gap:end -->

## Identifiers and SPC revisions

* `tornado_id` is unique within a package version only. SPC changed its `om`
  numbering for 2007 onward between its 2024 and 2025 releases (all 8,873
  matched 2007+ tornadoes changed ids). Distinct tornadoes that share a year and
  `om` in SPC (`2001_56`, `2002_506`) are suffixed `_1` and `_2`.
* SPC revises records between releases. Comparing the 2024 and 2025 files for the
  whole-track records of EF1 and above from 1996 to 2024, matched by date and start latitude and
  longitude: 13,701 tornadoes matched; magnitude changed for 9, injuries for 18, fatalities for 2,
  `len` for 79 and `wid` for 22; loss changed for 2,619 (2,530 of them by exactly a factor of one
  million, the unit re-coding of 2007 to 2015). No record of 1996-2006 changed in any of these values or in its id
  (`data-raw/qa/39_spc_release_comparison.R`).

## Dependence on upstream data

* The shipped data (`data/tornado_exposure.rda` and `data/tornado_tracks.rda`) hold everything the functions need. Installing and using the package needs no upstream download, except that `map_exposure()` downloads ZCTA boundaries from the Census Bureau (through tigris) when it runs.
* A full rebuild reads the SPC tornado file (one URL, 9.2 MB), the Census ZCTA boundary files for 2000, 2010 and 2020 (through tigris), and, for population, the Census TIGER/Line tabulation blocks (2020: 10.3 GB in 52 files; 2010: 7.0 GB; 2000: 5.8 GB) and the PL 94-171 files (2010: 1.0 GB; 2000: 0.4 GB), 24.6 GB in all. The population downloads are cached outside the repository (see `pop_cache()` in `data-raw/population/population_functions.R`).
* A yearly update (`data-raw/update_data.R`) is much smaller than a rebuild. It downloads the SPC file (9,219,030 bytes), the 2020 ZCTA boundary file and the 2020 tabulation blocks of the states that the new year's tornadoes touch (the 52 files for all states are 10.3 GB; the largest, Texas, is 746 MB and the smallest, DC, 4.7 MB). With the block results cached by `data-raw/add_population.R` (outside the repository), only the blocks along the new paths are read; on a machine without that cache every touched state is processed in full (assigning each block to a ZCTA). The yearly update does not extend `zcta_centroids` or the NWS survey snapshot (see the header of `data-raw/update_data.R`).
* The survey layer is rebuilt by `data-raw/survey/build_survey.R`, which queries the live Damage Assessment Toolkit service (survey lines dated 2007 to 2025 and the damage polygons). The access date is in `data-raw/survey/access_date.txt`; the service can change, so a rebuild can differ from the stored layer.
* Raw downloads are not archived with the package or the repository, and are never committed. The manifest of every population download (URL, size, md5) is in `data-raw/provenance_population.csv`, and the md5 and size of each SPC download, with the years that came from it (`data-raw/provenance_years.csv`), and the software versions are in `data-raw/provenance.txt`, so a rebuild can check that it received the same files.
* Risk: a full rebuild depends on the Census Bureau and SPC keeping these URLs available and unchanged. If they move, disappear, or (for SPC) are revised, a rebuild will not reproduce the shipped data, although the shipped data stay valid. Yearly updates append only new years and leave stored years frozen, so they do not depend on old files remaining available.

## Ratings

* All ratings are kept: 20,531 EF0, 15,950 EF1-EF5 and 1,546 unknown (SPC code
  -9, stored as `NA`). No other magnitude code occurs. Ratings before 2007 are on
  the original Fujita scale.

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

<!-- fixed-settings:start -->
## Other fixed settings

Each value below is fixed in the code. For each: what it is, the value, how it was chosen, and what it changes.

* **Minimum path width (10 yards).** When SPC records a width of 0 or none, the package uses 10 yards (9.1 m) so that the path has an area; 10 yards is the minimum width in SPC's older format description. This affects 473 of 38,027 tornadoes. SPC's older format description (<https://www.spc.noaa.gov/wcm/torforma.doc>) says: "The minimum width is assumed to be 30 feet (ie = 3)", which is 10 yards. The current database description (<https://www.spc.noaa.gov/wcm/data/SPC_severe_database_description.pdf>, a scanned document) gives the width in yards and states no minimum. SPC widths are whole yards: the smallest nonzero width is 1 yard and 2,046 tornadoes have exactly 10 yards. With 5, 10 or 20 yards these 473 tornadoes have 606, 607, 609 ZCTA rows, and 460 of them have a ZCTA in each case; at 10 yards every one of their rows has `area_prop_affected` of 0.01 or less.
* **5 km margin when choosing census blocks (population).** The blocks a path covers are chosen in longitude and latitude, where a straight path drawn in the equal-area projection is curved; for the 24 line tracks among the 25 longest tracks the largest distance between the two is 1.13 km (median 0.29 km). Blocks within 5 km of the path are therefore taken as candidates, and the area of each block inside the path is then computed exactly, so the margin only has to be larger than that distance; a larger margin changes nothing except speed. Independent check: for 174 tornadoes (the 25 longest paths, 100 random line tracks of 10 miles or more, 25 random shorter lines and 25 point tracks; these sample sizes are not tested choices) the residents computed with no candidate selection at all differ from the stored `pop_affected` by at most 0 residents (0 of 813 rows differ by more than 1e-6).
* **10 km margin around state outlines.** Population is processed state by state, and the states a path touches are found from generalized state outlines widened by 10 km, because the outlines are generalized cartographic boundaries. In a sample of 3,089 tornadoes (the 100 longest and random others; the sample size is not a tested choice), 17 paths touch no outline without the margin and 2 with it (306 paths pick up an additional, neighboring state, which only costs time). The 2 paths with no state within 10 km have no exposure rows.
* **1.05 factor on the search radius (`centroid_dist_km`).** The spatial index is searched with a buffer of 1.05 times the radius, and the exact distance is then computed for the candidates only. The factor guards against the polygon approximation of a circular buffer. For 200 random line tracks (a sample size that is not a tested choice), a radius of 5 km gives 259, 259 and 259 ZCTA centroids within the radius with factors 1.00, 1.05 and 1.50, and a radius of 25 km gives 3,080, 3,081 and 3,081: without the margin 1 centroid is missed, and a larger margin than 1.05 finds nothing more.
* **Sanity limits in the update checks.** `data-raw/update_data.R` stops for review when a new record has a path length above 400 miles, a latitude outside 15 to 72 or a longitude outside -180 to -60. These are guards against corrupt records, not scientific values. In the data the longest path is 168.53 miles (`2021_2112102054-01`; 10 paths exceed 100 miles), latitudes run from 17.7212 to 61.13 and longitudes from -163.53 to -64.7151. The same script stops for a width outside 0 to 10,000 yards (the largest width in the data is 4,576 yards) and for known loss above 1e11 dollars (the largest in the data is 2,800,102,000 dollars).
* **Rounding tolerances (1e-6 and 1e-9).** The integrity checks accept differences of up to 1e-6 residents between `pop_affected` and `zcta_pop`, and up to 1e-9 on shares and proportions (1e-8 relative on allocated loss). They only absorb floating-point rounding. In the data the largest excess of `pop_affected` over `zcta_pop` is 0 residents, the largest departure of a tornado's shares from a sum of 1 is 2.22e-16, the largest `pop_prop_affected` minus 1 is 0, and the largest relative difference between allocated loss and the tornado total is 4.66e-16.
<!-- fixed-settings:end -->
