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
