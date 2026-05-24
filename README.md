# About the ```tornadoexposure``` package

# How to use the ```tornadoexposure``` package

## Set-up

## Data
This package includes a built-in dataset called ```zcta_tracks```, which is a modified version of the [NOAA Tornado Tracks dataset](https://www.spc.noaa.gov/gis/svrgis/). The dataset retains only tornadoes recorded after 1995 with a magnitude greater than EF0. The raw coordinate data for the tornado tracks was converted into Linestring geometries, which provide the exact locations of and paths taken by each tornado. The data was then merged with ZCTA boundary shapefile data from the Census Bureau, accessed using the ```tigris``` package. The tornado track Linestring geometries were overlaid on top of the ZCTA boundaries to identify which ZCTAs were intersected by each tornado. Finally, the area of the tornado track was compared to the total area of each exposed ZCTA to determine the percentage of ZCTA land area directly affected by each tornado. 

## Functions
All functions in this package require a set of Zip Code Tabulation Area (ZCTA) codes and a range of years across which exposure data should be aggregated. 
ZCTA codes must be passed into the functions as a vector. ZCTA codes can be passed in as any 1-5 digit string of numbers, and the functions will match all ZCTAs that begin with that string of numbers (for instance, pass in the list ```c(6, 4, 2)``` to return exposures affecting all ZCTAs with codes that begin with 6, 4, or 2. Alternatively, pass in the list ```c(60304, 60637)``` to return exposures only affecting ZCTAs 60304 and 60637.) Input lists of ZCTA codes can contain codes of different lengths (eg. ```c(6, 90210, 486)``` would be acceptable input).
Years must be input as a range of integers. Ranges can be as small as a single year (eg. ```2011```) or as large as the full range of years included in the dataset (as of version 0.1.0, ```1996:2025```).

### Getting ZCTA-level exposure data (```get_data```)
This function lets you create a dataframe containing all exposures for a given set of ZCTAs and range of years. 

| Feature | Data Type | Description |
|---------|-----------|-------------|
| tornado_id | character | unique string identifying each tornado, comprised of the year of the tornado followed by its NOAA om id. Om are unique within years but not across years, which is why it was combined with year to create this id.|
| date | date | date in yyyy-mm-dd format |
| year | integer |  the year of the tornado |
| month | character | the month of the tornado in mm format |
| day | character | the day of the tornado in dd format |
| magnitude | integer | the magnitude of the tornado on the Enhanced Fujita (EF) scale. Magnitudes for storms recorded prior to the shift from F to EF in 2008 are converted to the EF scale. |
| total_injury | integer | The total number of injuries reported for a given tornado |
| total_fatality | integer | The total number of fatalities reported for a given tornado |
| area_pct_affected | integer | The percentage of the total ZCTA area that was directly affected by the tornado. |
| ZCTA | character | The 5 digit zip code tabulation area (ZCTA) code |
| geometry | LINESTRING [m] | A simple features geometry representing the path taken by a given tornado |


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
