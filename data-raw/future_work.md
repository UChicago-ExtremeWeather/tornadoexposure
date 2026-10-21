# Future work

Ideas that are not in the package.

## Survey layer: a centerline-only tier

Many tornadoes were paired with a National Weather Service survey line, but only the ones
with a usable damage swath are in the survey layer. The others (status
`"no_swath"` in `survey_matches`) have a surveyed centerline only. A second
`path_source` value could apply SPC's width (treated as the maximum width) to the surveyed centerline
instead of SPC's straight line. It was left out because it mixes two path sources
in one layer, and because the comparison with the surveys shows that the width,
not the centerline, is the larger source of difference between modeled and surveyed
paths (see "Path accuracy" in `known_issues.md`). Counts come from
`survey_matches` (`status`, `n_polygons_used` and `swath_cover`).
