library(tidyverse)
library(sf)
library(tictoc)

od <- read_csv('../data/od_home_combined_filtered_dists.csv')
placekeys <- read_csv('../data/poi_subset_placekeys_naics_borderlabel.csv')
placekeys_noborder <- placekeys %>% filter(near_border == FALSE)

# remove destinations near borders
od <- od %>% filter(placekey %in% placekeys_noborder$placekey)

route_labels <- read_sf('../data/dest_level_labeling/placekey_habitual_labels_nn.gpkg') %>% select(placekey.x, ends_with("blend"))  %>% rename('placekey' = 'placekey.x')

tic('how long to join?') # 41 sec
labeled_od <- od %>% left_join(route_labels, by='placekey')
toc()

colnames(labeled_od) <- gsub('present_', '', gsub('_blend', '', colnames(labeled_od)))

# figuring out a new way to do the expansion columns (combo of present and date)
expansion_dates <- st_read('../data/all_expansions_ncdot_data.shp') %>% 
  select(CntrctN, date) %>% 
  st_drop_geometry() %>%
  mutate(CntrctN = paste0('C_', CntrctN)) %>%
  deframe() # making this a named list so I can use it in my new cool mutate across

tic('create all expansion columns') # 10 sec
expansions_od <- labeled_od %>%
  select(-C_NA) %>%
  mutate(
    across(
      .cols = starts_with('C_'),
      .fns = ~ .x & (date_range_start > as.Date(expansion_dates[[cur_column()]])),
      .names = '{.col}_expanded'
    )
  )
toc()

write_csv(expansions_od, '../data/alldata_nozeros.csv')
