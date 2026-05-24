# About the ```tornadoexposure``` package

# How to use the ```tornadoexposure``` package

## Set-up

## Data

## Functions

### Getting ZCTA-level exposure data (```get_data```)
| Feature | Data Type | Description |
|---------|-----------|-------------|
| tornado_id | | |
| date |||
| year |||
| month |||
| day |||
| magnitude |||
| total_injury |||
| total_fatality |||
| tornado_area_m2 |||
| geometry |||



### Mapping ZCTA-level exposures (```map_exposure```)
![](figures/joplin_count_singleyr.png)

#### Exposure characteristics
The ```tornadoexposure``` package supports ZCTA-level aggregation and mapping of the following exposure characteristics across input years:

##### Tornado Count
![](figures/joplin_count.png)
##### Average Magnitude
![](figures/joplin_mag.png)
##### Total Fatalities (per tornado)
![](figures/joplin_fat.png)
##### Total Injuries (per tornado)
![](figures/joplin_inj.png)

### Mapping tornado tracks (```add_tracks```)
Finally, tornado tracks can be overlaid on any ZCTA-level exposure map created by ```map_exposure```.
![](figures/joplin_mag_tracks.png)
