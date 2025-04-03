######### this file is for the average distance model - aggregated at destination level, lose info about counts

library(tidyverse)
library(sf)
library(tictoc)

# get coordinates for the placekeys of interest
poi_info <- read_csv('../data/poi_info/NC_monthlypatterns_poi_info_2018-01.csv') %>% select(placekey, longitude, latitude) %>% 
  st_as_sf(coords = c("longitude", "latitude"), crs=st_crs(4326))
placekeys <- read_csv('../data/poi_subset_placekeys_naics_borderlabel.csv')

convert_coords <- function(state) {
  state <- state %>% mutate(blockgroup = paste0(STATEFP, COUNTYFP, TRACTCE, BLKGRPCE))
  state <- st_as_sf(state, coords = c("LONGITUDE", "LATITUDE"), crs=st_crs(4326))
  return(state)
}
nc_bg <- convert_coords(read_csv('https://www2.census.gov/geo/docs/reference/cenpop2010/blkgrp/CenPop2010_Mean_BG37.txt', show_col_types = FALSE)) %>% select(blockgroup)


# getting actually-existing interactions to minimize the distances i have to find
od_home_tibble <- read_csv('../data/od_home_combined_filtered.csv')

no_duplicates <- od_home_tibble %>% select(visitor_home_cbgs, placekey) %>% distinct()

unique_coords <- left_join(no_duplicates, poi_info, by="placekey") %>% mutate(visitor_home_cbgs = as.character(visitor_home_cbgs)) %>% left_join(nc_bg, by = c('visitor_home_cbgs' = 'blockgroup'))

# find the distances
tic('time for 22 million distances')
dists <- st_distance(unique_coords$geometry.x, unique_coords$geometry.y, by_element = TRUE)
toc()

# add to the unique coordinate table and save to file
unique_coords$dist <- dists
write_csv(unique_coords, '../data/unique_od_coords_dist.csv')

# add distances to od_home_tibble
tic('join big to big')
od_home_dists <- od_home_tibble %>% mutate(visitor_home_cbgs = as.character(visitor_home_cbgs)) %>% left_join(unique_coords %>% select(visitor_home_cbgs, placekey, dist), by=c('placekey', 'visitor_home_cbgs'))
toc()

write_csv(od_home_dists, '../data/od_home_combined_filtered_dists.csv')
