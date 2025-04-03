using CSV
using OSRM
using DataFrames
using Geodesy
using ArchGDAL
import GeoFormatTypes as GFT
using GeoDataFrames
using ThreadsX

root = dirname(@__FILE__)
p = joinpath(root, "..", "input", "NConly_2018_unique_od_filtered_coordinates.csv")
od_home = CSV.read(p, DataFrame, types=Dict(1=>String, 2=>Float64, 3=>Float64, 4=>String, 5=>Float64, 6=>Float64,))

#osm_path = joinpath(root, "..", "osrm_backend_nc", "north-carolina-latest.osm.pbf")
#OSRM.build(osm_path, OSRM.Profiles.Car, OSRM.Algorithm.MultiLevelDijkstra)

osrm_path = joinpath(root, "..", "osrm_backend_nc", "north-carolina-latest.osrm")
osrm = OSRMInstance(osrm_path, OSRM.Algorithm.MultiLevelDijkstra)


function run_routing_subset(startrow, endrow) # would have been more performance optimized to pass od_home instead of using global
    subset = od_home[startrow:endrow, :] # split original table into chunk based on start and end row indices
    subset.geom = ThreadsX.map(zip(subset.home_y, subset.home_x, subset.poi_y, subset.poi_x)) do (home_lat, home_lon, poi_lat, poi_lon) # used ThreadsX to multithread the map function without rewriting my code :)
        result = route(osrm, LatLon(home_lat, home_lon), LatLon(poi_lat, poi_lon)) # do this with every combination
        if !isempty(result) # to make sure that there's a value added to dataframe - fill in missing if no result
            geom = ArchGDAL.createlinestring()
            for latlon in first(result).geometry
                ArchGDAL.addpoint!(geom, latlon.lon, latlon.lat)
            end
            return geom
        else
            return missing
        end
    end
    # convert to GeoDataFrame - for "geoms" version
    metadata!(subset, "geometrycolumns", (:geom,))
    return subset
end

# test run with teeny dataset
# @time od_home_subset = run_routing_subset(1,100)
# output_path = joinpath("/Volumes/WD2Tb", "TEST.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

################################
######### RUN CHUNKS ##########
################################

# need to get to 7352717 rows
# already ran: [1,500000], [500001,1000000], [1000001,1500000], [1500001,2000000], [2000001,2500000], [2500001,3000000], [3000001,3500000], [3500001,4000000], [4000001,4500000], [4500001,5000000], [5000001,5500000], [5500001,6000000], SKIPPED 6-6.5 OOPS [6500001,7000000], [7000001,7352717]
for rowpair in [[6000000, 6500000]]
    println("starting iteration from")
    println(rowpair[1])
    @time od_home_subset = run_routing_subset(rowpair[1],rowpair[2])
    output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_"*string(rowpair[2])*".gpkg")
    # write to geopackage - for "geoms" version
    @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))
    od_home_subset = nothing # reset to free memory
    GC.gc()
end


################################
######### test code BELOW #######
################################

# home_lat = od_home[1, "home_y"]
# home_lon = od_home[1, "home_x"]
# poi_lat =  od_home[1, "poi_y"]
# poi_lon = od_home[1, "poi_x"]
# result = route(osrm, LatLon(home_lat, home_lon), LatLon(poi_lat, poi_lon))
# ann = first(result).legs[1].annotation.nodes

# started 9:55, killed 11:17
# od_home.geom = map(zip(od_home.home_y, od_home.home_x, od_home.poi_y, od_home.poi_x)) do (home_lat, home_lon, poi_lat, poi_lon)
#     result = route(osrm, LatLon(home_lat, home_lon), LatLon(poi_lat, poi_lon)) # do this with every combination
#     if !isempty(result) # to make sure that there's a value added to dataframe
#         geom = ArchGDAL.createlinestring()
#         for latlon in first(result).geometry
#             ArchGDAL.addpoint!(geom, latlon.lon, latlon.lat)
#         end
#         return geom
#     else
#         return missing
#     end
# end

# convert to GeoDataFrame - for "geoms" version
#metadata!(od_home, "geometrycolumns", (:geom,))

# write to geopackage - for "geoms" version
#p_output = joinpath(root, "..", "output", "odpaths_2018-01-filtered.gpkg")
#GeoDataFrames.write(p_output, od_home; crs=GFT.EPSG(4326))

# small = first(od_home, 100)
# two tests with small
# function geoms_small()
# small.geom = ThreadsX.map(zip(small.home_y, small.home_x, small.poi_y, small.poi_x)) do (home_lat, home_lon, poi_lat, poi_lon)
#     result = route(osrm, LatLon(home_lat, home_lon), LatLon(poi_lat, poi_lon)) # do this with every combination
#     if !isempty(result) # to make sure that there's a value added to dataframe
#         geom = ArchGDAL.createlinestring()
#         for latlon in first(result).geometry
#             ArchGDAL.addpoint!(geom, latlon.lon, latlon.lat)
#         end
#         return geom
#     else
#         return missing
#     end
# end
# end

# @time geoms_small() # 2.664556 seconds 0.303792 seconds #0.15 seconds

# function nodes_small()
#     small.nodes = ThreadsX.map(zip(small.home_y, small.home_x, small.poi_y, small.poi_x)) do (home_lat, home_lon, poi_lat, poi_lon)
#         result = route(osrm, LatLon(home_lat, home_lon), LatLon(poi_lat, poi_lon)) # do this with every combination
#         if !isempty(result) # to make sure that there's a value added to dataframe
#             return first(result).legs[1].annotation.nodes
#         else
#             return missing
#         end
#     end
# end
# @time nodes_small() #0.31142 seconds #0.167174 seconds #0.14 seconds # definitely faster # even faster with ThreadsX.map

# small_output = joinpath(root, "..", "output", "odpaths_test.csv")
# CSV.write(small_output, small)
# test_read = CSV.read(small_output, DataFrame)

# real go
# function run_routing()
# od_home.nodes = ThreadsX.map(zip(od_home.home_y, od_home.home_x, od_home.poi_y, od_home.poi_x)) do (home_lat, home_lon, poi_lat, poi_lon)
#     result = route(osrm, LatLon(home_lat, home_lon), LatLon(poi_lat, poi_lon)) # do this with every combination
#     if !isempty(result) # to make sure that there's a value added to dataframe
#         return first(result).legs[1].annotation.nodes
#     else
#         return missing
#     end
# end
# end

# @time run_routing()

# #write to 
# output_path = joinpath(root, "..", "output", "NC_2018_unique_od_filtered_paths.csv")
# CSV.write(output_path, od_home)

# breaking into sequential bits to not run out of memory

################################
######### OLD INEFFICIENT ##########
################################

# @time od_home_subset = run_routing_subset(1,1000000)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_1mil.gpkg") #13 minutes!!!
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326)) # 19 minutes... much longer than the generation part

# cleanup time
# od_home_subset = nothing

# @time od_home_subset = run_routing_subset(1000001,2000000) #15/16 minutes
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_2mil.gpkg") 
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326)) # minutes

# # cleanup time
# od_home_subset = nothing

# @time od_home_subset = run_routing_subset(2000001,2500000)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_2_5mil.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

# # cleanup time
# od_home_subset = nothing

# @time od_home_subset = run_routing_subset(2500001,3000000)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_3mil.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

# # cleanup time
# od_home_subset = nothing

# @time od_home_subset = run_routing_subset(3000001,4000000)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_4mil.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

# # cleanup time
# od_home_subset = nothing


# @time od_home_subset = run_routing_subset(4000001,5000000)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_5mil.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

# # cleanup time
# od_home_subset = nothing


# @time od_home_subset = run_routing_subset(5000001,6000000)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_6mil.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

# # cleanup time
# od_home_subset = nothing


# @time od_home_subset = run_routing_subset(6000001,7000000)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_7mil.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

# # cleanup time
# od_home_subset = nothing


# @time od_home_subset = run_routing_subset(7000001,8000000)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_8mil.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

# # cleanup time
# od_home_subset = nothing


# @time od_home_subset = run_routing_subset(8000001,8287564)
# output_path = joinpath("/Volumes/WD2Tb", "NC_2018_unique_od_filtered_paths_9mil.gpkg")
# # write to geopackage - for "geoms" version
# @time GeoDataFrames.write(output_path, od_home_subset; crs=GFT.EPSG(4326))

