library(tidyverse)
library(sf)
library(tictoc)
library(tmap)
library(FNN)

# NEW VERSION OF label_od which only labels TRUE based on od pairs that existed in x/12 months. will run with 6/12 months

od_combined_filtered <- read_csv('../data/od_home_combined_filtered.csv') # all od, filtered to my placekey_subset
od_2018 <- od_combined_filtered %>% filter(date_range_start < '2019-01-01') # restrict to 2018
od_combined_filtered <- NA # memory cleanup
habitual <- od_2018 %>% group_by(placekey, visitor_home_cbgs) %>% summarize(months_present = n()) # set up grouping by placekey/bg pair to keep only those that are habitual
habitual_6mo <- habitual %>% filter(months_present >= 6) %>% mutate(od_pair = paste(visitor_home_cbgs, placekey, sep='-')) # keep od pairs that exist in 6/12 months
habitual_10mo <- habitual %>% filter(months_present >= 10) %>% mutate(od_pair = paste(visitor_home_cbgs, placekey, sep='-')) # keep of pairs that exist in 10/12 months

expansions <- st_read('../data/all_expansions_ncdot_data.shp') # get expansion data with which to label

# wrap the labeling code in a function
process_chunk <- function(file_index, expansions, habitual_tbl) {

#####################################
########## READ ROUTES ##############
#####################################
# code to take a small chunk
# routes_small <- st_read('../data/paths/NC_2018_unique_od_filtered_paths_500000.gpkg',
#                   query = "SELECT * FROM data LIMIT 1000 OFFSET 0")

tic('read 500k')
routes <- st_read(paste0('../data/paths/NC_2018_unique_od_filtered_paths_', file_index, '.gpkg'))
toc() #77 seconds. not bad!!!

#####################################
########## KEEP HABITUAL ############
#####################################

routes <- routes %>% mutate(od_pair = paste(home_bg, placekey, sep='-'))
habitual_routes <- routes %>% filter(od_pair %in% habitual_tbl$od_pair)

#####################################
######## JOIN EXPANSIONS ############
#####################################

tic('find which intersect') #4 minutes without largest = TRUE. 83 minutes with largest = TRUE
contracts_labeled <- st_join(habitual_routes, expansions) # if there are multiple matches in expansions, there are multiple rows, so I use largest=TRUE
# if largest = TRUE, return x features augmented with the fields of y that have the largest overlap with each of the features of x; see https://github.com/r-spatial/sf/issues/578
toc()

#####################################
### DROP ROUTES, SET DEST GEOM ######
#####################################

tic('destination-level')
dest_labeled <- contracts_labeled %>% st_drop_geometry() %>% st_as_sf(coords=c("poi_x", "poi_y"))
toc()

#####################################
######### WRITE TO GPKG ##############
#####################################

write_sf(dest_labeled, paste0('../data/path_expansion_overlap/NC_2018_habitual_od_filtered_path_expansion_overlap_', file_index, '.gpkg'))

#####################################
###### COUNT ROUTES BY DEST #########
#####################################

count_notempty <- function(stuff) {
  return(sum(!is.na(stuff)))
}

over_0 <- function(stuff) {
  return(stuff > 0)
}

prefixed <- dest_labeled %>% mutate(CntrctN = paste0('C_', CntrctN))

tic('time to pivot') #1.3
pivoted <- prefixed %>% pivot_wider(names_from = CntrctN, values_from = home_bg) # less than a second
toc()

tic('group and find present/absent') # 62 seconds
count_routes <- pivoted %>% group_by(placekey) %>% summarise(across(starts_with("C_"), count_notempty, .names = "numroutes_{.col}")) %>%
  mutate(across(starts_with("numroutes_"), over_0, .names = "present_{str_replace(.col, 'numroutes_', '')}")) # lets me use the column name but drop the numroutes_ part
toc()
# count_routes is only 5.5 mb when saved as gpkg!!! yahoo

return(count_routes)
# at this stage, the length(unique(count_routes$placekey)) is equal to nrow(count_routes) - makes sense given grouping!

#END FUNCTION
}

#####################################
#### COMBINE 15 LABELED FILES #######
#####################################


# two options: bind rows directly
# count_routes <- process_chunk('500000')
# for (file_index in c('1000000', '1500000', '2000000', '2500000', '3000000', '3500000', '4000000', '4500000',
#                      '5000000', '5500000', '6000000', '6500000', '7000000', '7352717')) {
#   count_routes <- bind_rows(count_routes, process_chunk(file_index))
# }

# or assemble in list first
labels_list <- vector("list", 15)
i <- 1
for (file_index in c('500000', '1000000', '1500000', '2000000', '2500000', '3000000', '3500000', '4000000', '4500000',
           '5000000', '5500000', '6000000', '6500000', '7000000', '7352717')) {
  count_routes <- process_chunk(file_index, expansions, habitual_6mo)
  labels_list[[i]] <- count_routes
  i <- i + 1
}

all_labels <- labels_list[[1]]
for (i in 2:15) {
  all_labels <- bind_rows(all_labels, labels_list[[i]])
}

#write_sf(all_labels, '../data/dest_level_labeling/habitual_labels_ungrouped.gpkg') # don't want to lose this

# 139223 observations
# length(unique(all_labels$placekey)) # 50531 placekeys get labeled based on having 6mo+ habitual travel
# to correctly label all destinations, need to pull destinations from poi_info probably, filtered by poi_subset_placekeys

all_labels <- read_sf('../data/dest_level_labeling/habitual_labels_ungrouped.gpkg')

nas_filled <- all_labels %>% mutate(across(starts_with("numroutes"), \(x) replace_na(x, 0))) %>% 
  mutate(across(starts_with("present"), \(x) replace_na(x, FALSE)))

grouped <- nas_filled %>% group_by(placekey) %>% 
  summarise(across(starts_with("numroutes"), sum),
            across(starts_with("present"), any))

write_sf(grouped, '../data/dest_level_labeling/placekey_level_labels_habitual.gpkg') # this will only be for the habitual OD pairs. need to relabel the *whole* POI set with these nearest neighbours

# 6mo+ labeling is SO much better

#####################################
##### NEAREST NEIGHBOR RELABEL ######
#####################################

# only reading 2018 Jan because that contains all the poi_subset placekeys, and I just need to get the coordinates
subset <- read_csv('../data/poi_subset_placekeys.csv')
poi_info <- read_csv('../data/poi_info/NC_monthlypatterns_poi_info_2018-01.csv') %>% 
  filter(placekey %in% subset$placekey) %>%
  select(placekey, latitude, longitude) %>% st_as_sf(coords=c("longitude", "latitude"))
# for some reason, zzw-222@665-zjj-k9f has a latitude of 43.6, putting it canada? even though its address is NC. will likely need to drop, leaving for now

# try knn
label_indices <- grouped %>% st_coordinates()
all_pts <- poi_info %>% st_coordinates()

tic('get knn') # so fast! 0.263
knn_result <- get.knnx(label_indices, all_pts, k=7) # result is a list, first value is matrix of size nrow(all_pts) x k with the indices from grouped of nearest neighbors
toc()

knn_indices <- knn_result[[1]]

poi_with_neighbor_indices <- poi_info %>% cbind(knn_indices)

# one row per POI-neighbor pair (# poi times 7 rows)
long_neighbors <- poi_with_neighbor_indices %>% pivot_longer(starts_with("X"), values_to = 'index', names_to = 'neighbor') %>% mutate(index = as.character(index))

#add an index column to my labeled data so I can join
grouped_index <- grouped %>% rownames_to_column('index') %>% st_drop_geometry()

#join labeled data to each neighbor
poi_with_neighbor_labels <- long_neighbors %>% left_join(grouped_index, by='index')

# define a Mode function: https://stackoverflow.com/questions/2547402/how-to-find-the-statistical-mode
Mode <- function(x) {
  ux <- unique(x)
  ux[which.max(tabulate(match(x, ux)))]
}

# group by POI to summarize the 7 neighbor's info for each
tic('get majority label') # 549 seconds, 9 min
poi_relabeled <- poi_with_neighbor_labels %>% group_by(placekey.x) %>% summarize(across(starts_with("present_"), Mode, .names = "{.col}_relabeled"))
toc()

# fill in the pre-existing labels where we have them - don't want those TRUEs to get overwritten
labels_and_relabels <- poi_relabeled %>% left_join(grouped %>% st_drop_geometry(), by=c('placekey.x' = 'placekey'))
# dropping the numroutes
labels_and_relabels <- labels_and_relabels %>% select(-starts_with('numroutes')) %>% 
  mutate(across(starts_with("present"), \(x) replace_na(x, FALSE))) # should be safe to fill NAs with FALSE 

# update: apply across all present_ column pairs
presence_cols <- names(labels_and_relabels)[grepl("relabeled", names(labels_and_relabels))]
presence_cols <- str_replace(presence_cols, "_relabeled", "")

tic('get all new labels')
for (colname in presence_cols) {
  labels_and_relabels[[paste0(colname, "_blend")]] <- (labels_and_relabels[[colname]] | labels_and_relabels[[paste0(colname, "_relabeled")]]) # add true if either col is true
}
toc()

#write_sf(labels_and_relabels, '../data/dest_level_labeling/placekey_habitual_labels_nn.gpkg') # saving the nearest-neighbor relabeled version

# tmap_mode('view')
# tm_shape(labels_and_relabels %>% filter(present_C_DC00320_blend)) + tm_dots(c("present_C_DC00320_relabeled","present_C_DC00320_blend")) +
#                               tm_facets(as.layers = TRUE)
# 
# tm_shape(labels_and_relabels) + tm_dots("present_C_DC00320_relabeled")

