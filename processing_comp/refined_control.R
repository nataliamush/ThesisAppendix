library(tidyverse)
library(data.table)
library(tigris)
library(tmap)
library(ggpubr)

######## spatial data needed to narrow the study area

### expansions not near the border
borders <- states() %>% filter(NAME %in% c("Virginia", "Tennessee", "Georgia", "South Carolina"))
borders_buff <- borders %>% st_buffer(dist = 35000) %>% st_union() %>% st_make_valid() %>% st_transform(4326) %>% st_as_sf() %>% mutate(near_border = TRUE)
all_expansions <- read_sf('../data/all_expansions_ncdot_data.shp')
all_expansions <- all_expansions %>% st_join(borders_buff) %>% mutate(near_border = replace_na(near_border, FALSE))
inner_expansions <- all_expansions %>% filter(near_border == FALSE)

# all points with their served/not served labels
grouped <- read_sf('../data/dest_level_labeling/placekey_habitual_labels_nn.gpkg')
st_crs(grouped) <- 4326 # https://stackoverflow.com/questions/61286108/error-in-cpl-transformx-crs-aoi-pipeline-reverse-ogrcreatecoordinatetrans

# a couple of the expansions never show up in the data - eliminate those
present_inner_expansions <- inner_expansions %>% filter(paste0('present_C_', inner_expansions$CntrctN, '_blend') %in% names(grouped))

# my actual data don't contain the border destinations, so removing from these data to limit how much computation I need to do
placekeys_border <- read_csv('../data/poi_subset_placekeys_naics_borderlabel.csv') %>% 
  select(placekey, near_border) 
grouped <- grouped %>%
  left_join(placekeys_border, by=c('placekey.x' = 'placekey')) %>%
  filter(!near_border)

#these are the points that have at least one expansion that affects them
any_true <- grouped %>% select(-present_C_NA_blend) %>% 
  mutate(some_true = if_any(ends_with('blend'), I)) %>% 
  filter(some_true)

#just a vis sanity check
tm1 <- tm_shape(any_true) + tm_dots(col='blue') + tm_shape(inner_expansions) + tm_lines('red')
points_seg <- tmap_grob(tm1)

######## Now step through each expansion and find the distance that captures 95% of its corresponding points 
all_buffers <- vector("list", nrow(present_inner_expansions))
for (i in 1:length(present_inner_expansions$CntrctN)) {
 cntrct <- present_inner_expansions$CntrctN[i]
 true_column <- paste0('present_C_', cntrct, '_blend')
 one_points <- grouped %>% filter(!!sym(true_column))
 one_segment <- present_inner_expansions %>% filter(CntrctN == cntrct)
 dists <- st_distance(one_points, one_segment)
 threshold <- quantile(dists, .95)
 one_buff <- st_buffer(one_segment, threshold)
 all_buffers[[i]] <- one_buff
}
combined_buffers <- rbindlist(all_buffers) %>% st_as_sf()
merged_buffers <- combined_buffers %>% st_union() %>% st_sf() %>% st_make_valid()
tm_shape(merged_buffers) + tm_polygons()

###### Now I can find the list of placekeys from inside this area
refined_placekeys <- grouped %>% st_filter(merged_buffers)

# the full dataset that needs to be restricted to just the area of interest
expansions_od <- fread('../data/alldata_nozeros.csv')
refined_control_alldata <- expansions_od %>% filter(placekey %in% refined_placekeys$placekey.x)

#fwrite(refined_control_alldata, '../data/alldata_nozeros_refinedcontrol.csv')

# get aggregated values.
# tic('time to group this big ass dataset, but slightly smaller than the full state version') # 9 min w the weighted quantiles
dest_agg <- refined_control_alldata  %>%
  group_by(placekey, date_range_start) %>% # dest level, time level
  summarize(avg_dist = weighted.mean(dist, count),
            perc25 = weighted_quantile(dist, count, c(0.25)),
            perc50 = weighted_quantile(dist, count, c(0.5)),
            perc75 = weighted_quantile(dist, count, c(0.75)),
            total_count = sum(count),
            vmt = sum(dist*count),
            across(ends_with('expanded'), first)) # expanded should be the same for each dest/time pair, take the first one
toc()

# write_csv(dest_agg, '../data/alldata_nozeros_refinedcontrol_destgrouped.csv')

### POST PROBLEMS RETRO

### visualize labels
for_vis <- refined_placekeys %>% select(-present_C_NA_blend) %>% 
  mutate(some_true = if_any(ends_with('blend'), I)) %>% 
  filter(some_true) %>% pivot_longer(ends_with('blend'), names_to = 'segment', values_to = 'affected') %>%
  filter(affected == TRUE)
tm_shape(for_vis) + tm_dots(col='segment')

# check how many placekeys associated with each
test <- refined_placekeys %>% pivot_longer(ends_with('_blend')) %>% 
  group_by(name) %>% summarize(affected = sum(value)) %>% 
  arrange(desc(affected)) %>% 
  filter(name != 'present_C_NA_blend')

over_500 <- (test %>% filter(affected >= 500))$name

tm_shape(for_vis %>% filter(segment %in% over_500)) + tm_dots(col='segment')

### Make four-panel figure

nc <- counties('NC', cb=TRUE)
carteret <- nc %>% filter(NAME=="Carteret")

threshold <-tm_shape(nc, bbox = st_bbox(carteret)) + tm_borders() +  
                         tm_shape(combined_buffers) + tm_polygons(alpha=0.75, lwd=2) + 
                         tm_shape(any_true) + tm_dots(col='red') + tm_scale_bar() + tm_credits("A", position=c("right", "top"))
all_segmentbuffers <- tm_shape(nc) + tm_borders(lwd=0.5) + 
                                  tm_shape(combined_buffers) + tm_polygons(alpha=0.75, lwd=2) + 
                                  tm_scale_bar(position = c("left", "bottom")) + tm_credits("B", position=c("right", "top"))
dissolved <- tm_shape(nc) + tm_borders(lwd=0.5) + 
                         tm_shape(merged_buffers) + tm_polygons(alpha=0.75, lwd=2) + 
                         tm_scale_bar(position = c("left", "bottom")) + tm_credits("C", position=c("right", "top"))
pointskept <-tm_shape(nc) + tm_borders(lwd=0.5) + 
  tm_shape(refined_placekeys) + tm_dots(alpha = 0.2) +
                          tm_scale_bar(position = c("left", "bottom")) + tm_credits("D", position=c("right", "top"))
fourpanel <- tmap_arrange(threshold, all_segmentbuffers, dissolved, pointskept) 

tmap_save(fourpanel, "../figures/fourpanel.jpg")
