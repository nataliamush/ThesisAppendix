library(sf)
library(tmap)
library(tictoc)
library(tidyverse)
library(tmap)

#actually, OSRM data cleaning - getting just the coordinates of the block group placekey pairs

# block group centroids
# DO NOT NEED ALL THESE STATES because I only have streets inside NC - so won't be able to route to these
#locals_only <- c(37, 51, 54, 21, 47, 01, 13, 45) #mb better as strings to keep 01 correct

# from https://www.census.gov/geographies/reference-files/time-series/geo/centers-population.html
convert_coords <- function(state) {
  state <- state %>% mutate(blockgroup = paste0(STATEFP, COUNTYFP, TRACTCE, BLKGRPCE))
  state <- st_as_sf(state, coords = c("LONGITUDE", "LATITUDE"), crs=st_crs(32616))
  return(state)
}

nc_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG37.txt', show_col_types = FALSE)) # FLAG!!! THIS IS 2010
# al_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG01.txt', show_col_types = FALSE))
# va_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG51.txt', show_col_types = FALSE))
# wv_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG54.txt', show_col_types = FALSE))
# ky_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG21.txt', show_col_types = FALSE))
# tn_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG47.txt', show_col_types = FALSE))
# ga_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG13.txt', show_col_types = FALSE))
# sc_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG45.txt', show_col_types = FALSE))
# all_bg <- rbind(nc_bg, al_bg, va_bg, wv_bg, ky_bg, tn_bg, ga_bg, sc_bg)

subset <- read_csv('../input/poi_subset_placekeys.csv')

od_home1 <- read_csv('../output/NC_2018_unique_od_filtered.csv', col_types = 'cc') %>% 
  mutate(visitor_home_cbgs = case_when(
    visitor_home_cbgs=='510190501001' ~ '515150501001',
    visitor_home_cbgs=='510190501002' ~ '515150501002',
    visitor_home_cbgs=='510190501003' ~ '515150501003',
    visitor_home_cbgs=='510190501004' ~ '515150501004',
    visitor_home_cbgs=='510190501005' ~ '515150501005',
    TRUE ~ visitor_home_cbgs))

# some very silly block group changes: https://appliedgeographic.com/MethodologyStatements_2015/DatabaseOverview2015A.pdf
# need to replace 510190501002, which doesn't exist in the 2010 data, with  515150501002, its prior value
#Tract 51515050100 became 51019050100
#BG 515150501001 became 510190501001
#BG 515150501002 became 510190501002
#BG 515150501003 became 510190501003
#BG 515150501004 became 510190501004
#BG 515150501005 became 510190501005

poi1 <- read_csv('../input/NC_monthlypatterns_poi_info_2018-01.csv') %>% filter(placekey %in% subset$placekey) %>% select(placekey, longitude, latitude)
od_home1 <- left_join(od_home1, poi1, by='placekey') %>% 
  st_as_sf(coords = c("longitude", "latitude"), crs=st_crs(4326)) # Geodetic CRS:  WGS 84
# check:
# od_home1 %>% filter(st_is_empty(geometry))
# returns 0 rows - got destination coordinates for all points

# nearby_origins <- od_home1 %>% filter(substr(visitor_home_cbgs,1,2) %in% locals_only) #oh baby, now its only 8 million
# this is if I only want to use NC origins - WHICH I DO
nearby_origins <- od_home1 %>% filter(substr(visitor_home_cbgs,1,2) == 37)

#in next line use nc_bg or all_bg based on what you're trying to do
with_home <- nearby_origins %>% left_join(nc_bg %>% as.data.frame(), by=c('visitor_home_cbgs'='blockgroup'), suffix=c('.poi', '.bg')) # Geodetic CRS:  WGS 84

home_xy <- with_home$geometry.bg %>% st_coordinates() 
poi_xy <- with_home$geometry.poi %>% st_coordinates()

od_coordinates <- tibble(home_bg = with_home$visitor_home_cbgs, home_x = home_xy[,1], home_y = home_xy[,2], placekey = with_home$placekey, poi_x = poi_xy[,1], poi_y = poi_xy[,2])

write_csv(od_coordinates, '../output/NConly_2018_unique_od_filtered_coordinates.csv')
# previous version - with nearby state origins - is called NCnearby_2018_unique_od_filtered_coordinates.csv
