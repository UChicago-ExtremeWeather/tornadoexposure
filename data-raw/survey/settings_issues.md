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
