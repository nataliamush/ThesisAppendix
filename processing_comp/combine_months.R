library(tidyverse)
library(tictoc)


#################################
##### read + clean OD data ######
#################################

od_months <- list.files('../data/od_home/')
od_months_full <- paste0('../data/od_home/', od_months)
subset_placekeys <- read_csv('../data/poi_subset_placekeys.csv')
read_and_filter <- function(file, col_types) {
  tbl <- read_csv(file, col_types = col_types)
  subset <- tbl %>% filter_at(vars(placekey), any_vars(. %in% subset_placekeys$placekey))
  return(subset)
}

tables <- lapply(od_months_full, read_and_filter, col_types = 'cciD') #col type abbrev here https://readr.tidyverse.org/articles/readr.html
combined_od <- bind_rows(tables) #104 million. 104,433,868

# clean up memory
rm(tables)

#nrow(unique(combined_od[c('placekey', 'visitor_home_cbgs')])) # 32 million. 32,293,289

nc_origins <- combined_od %>% filter(grepl("^37", visitor_home_cbgs)) # 92 million. 92,345,126
# nrow(unique(nc_origins[c('placekey', 'visitor_home_cbgs')])) # 22 million. 22,633,494. times 60 months is .. 1 billion, yikes

# clean up memory
rm(combined_od)
gc()

#save to drive for the future
write_csv(nc_origins, '../data/od_home_combined_filtered.csv')

