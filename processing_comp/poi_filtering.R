### CODE COPIED FROM LONGLEAF on Oct 15, 2024. No changes made, just wanted to rerun on the same computer 
# that will be doing the big processing to make sure placekeys are exactly as expected

# nov 7, 2024 added a line to export the placekeys *and naics codes*, want to use this to partition the final combined dataset

# nov 8 added a line to add a flag for destinations within 30km of the border

library(tidyverse)
library(sf)
library(tigris)

# this part is filtering to categories that make sense
poi <- read_csv('../data/poi_info/NC_monthlypatterns_poi_info_2018-01.csv') %>% 
  st_as_sf(coords = c("longitude", "latitude"), crs=st_crs(4326)) # 204282 observations
codes <- c("^44", "^45", "^71", "^72", "^81") # removed 52 - no banks!!!!! sorry banks
codes_str <- paste(codes, collapse = "|")
categories_poi <- poi %>% filter(str_detect(naics_code,codes_str))
unique(categories_poi$top_category)

# this part is to avoid generating paths for locations that have a huge number of origin block groups but aren't important for analysis
# I think I should remove hotels (top_category = "Traveler Accommodation")
no_hotels <- categories_poi %>% filter(top_category != "Traveler Accommodation") # 175420 obs
# no stadiums - draw of those shouldn't be affected by traffic...I think I can plot these on top of my labeled stuff to confirm
no_sports <- no_hotels %>% filter(top_category != "Spectator Sports") #175309

# I really don't need anything in the airport
charlotte_airport <- st_sfc(st_point(c(-80.94285, 35.22056)),crs = st_crs(4326))
clt_buff <- st_buffer(charlotte_airport, 1000)
rdu <- st_sfc(st_point(c(-78.79391, 35.87706)), crs = st_crs(4326))
rdu_buff <- st_buffer(rdu, 1000)
near_clt <- no_sports %>% st_filter(y = clt_buff, .predicate = st_intersects)
near_rdu <- no_sports %>% st_filter(y = rdu_buff, .predicate = st_intersects)

no_airports <- no_sports %>% filter(!(placekey %in% near_clt$placekey) &
                                      !(placekey %in% near_rdu$placekey)) # 175138 obs

no_church <- no_airports %>% filter(sub_category != "Religious Organizations") #137629 big drop! can I justify?

# test final size of data - compare to 1,336,367. 995,365 with all of the above and dropping category 52 from initial filter
#od_home1 <- read_csv('../input/NC_monthlypatterns_od_home_2018-01.csv', col_types = 'ccic') %>% filter(placekey %in% no_church$placekey)

placekeys <- no_church %>% select(placekey, naics_code) %>% st_drop_geometry()
#write_csv(placekeys, '../data/poi_subset_placekeys_naics.csv') # replaced my old one. run on 9/25/2024 on longleaf, exact same code run on processing computer Oct 15, 2024

placekeys <- placekeys %>% select(placekey) # this is equivalent to what was run 9/25/2024
#write_csv(placekeys, '../data/poi_subset_placekeys.csv')

# adding tag about whether each placekey is within 30km of a border
borders <- states() %>% filter(NAME %in% c("Virginia", "Tennessee", "Georgia", "South Carolina"))
borders_buff <- borders %>% st_buffer(dist = 30000) %>% st_union() %>% st_make_valid() %>% st_transform(4326) %>% st_as_sf() %>% mutate(near_border = TRUE)

near_borders <- no_church %>% st_join(borders_buff) %>% select(placekey, naics_code, near_border) %>% st_drop_geometry() %>% mutate(near_border = replace_na(near_border, FALSE))
write_csv(near_borders, '../data/poi_subset_placekeys_naics_borderlabel.csv') # run 11/8/24
