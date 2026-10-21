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
