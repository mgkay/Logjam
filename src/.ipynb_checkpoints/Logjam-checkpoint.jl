"""
# Logjam

A Julia package providing tools and data for logistics engineering tasks.

## Overview
The `Logjam` package provides geographic visualization using GeoMakie and the Makie ecosystem,
U.S. geographical and statistical data access, map creation with Mercator projections,
road network functions, and text alignment tools for map annotations.

## Data Functions
- `usplace`: Returns DataFrame of U.S. place data (cities, towns, CDPs).
- `uscounty`: Returns DataFrame of U.S. county data.
- `uscentract`: Returns DataFrame of U.S. Census Tract data.
- `uscenblkgrp`: Returns DataFrame of U.S. Census Block Group data.
- `uszcta5`: Returns DataFrame of U.S. ZIP Code Tabulation Area (5-digit) data.
- `uszcta3`: Returns DataFrame of U.S. ZIP Code Tabulation Area (3-digit) data.
- `uscbsa`: Returns DataFrame of U.S. Core-Based Statistical Area (CBSA) data.
- `uscsa`: Returns DataFrame of U.S. Combined Statistical Area (CSA) data.
- `st2fips`: Converts state abbreviations to FIPS codes.
- `fips2st`: Converts FIPS codes to state abbreviations.
- `faf5nodes`: Returns DataFrame of FAF5 road network nodes.
- `faf5links`: Returns DataFrame of FAF5 road network links.
- `faf5interstate`: Returns interstate polyline vectors for map backgrounds.

## Map Functions
- `makemap`: Creates a map visualization for predefined or user-defined regions.
- `mapbbox`: Calculates bounding box for geographic coordinates with optional expansion.
- `aligntext`: Determines text alignment and offset positions for map labels.
- `isptinbbox`: Checks if a point lies within a bounding box.

## Road Network Functions
- `dgc`: Great circle distance between two points.
- `Dgc`: Great circle distance matrix between point sets.
- `prune_reindex`: Prune network to common vertices and reindex.
- `thin`: Remove degree-2 nodes from network.
- `addconnectors`: Add demand point connectors to road network.
- `links2graph`: Convert links DataFrame to Graphs.jl SimpleGraph.
- `x2ln`: Convert graph edges to line coordinates for plotting.

## Routing Functions
- `segcost`: Calculate segment costs in a location sequence.
- `rteTC`: Total route cost for pickup-delivery routes.
- `isorigin`: Identify pickup positions in a route.
- `rte2loc`: Convert route to location sequence.
- `twoopt`: 2-opt route improvement procedure.
- `mincostinsert`: Insert shipment at minimum cost position.
- `pairwisesavings`: Calculate savings for shipment pairs.
- `savings`: Savings-ordered insertion heuristic for PDP route construction.

## Constants
- `WORLD_LIMITS`: Geographical limits for world map projections.
- `US_LIMITS`: Geographical limits for U.S. map projections.
- `CUS_LIMITS`: Geographical limits for continental U.S. map projections.

## Dependencies
- `Serialization`: For loading pre-serialized geographic data.
- `DataFrames`, `CSV`: For tabular data representation.
- `GeoMakie`, `CairoMakie`: For creating and rendering maps.
- `GLMakie` (optional): For interactive map display.
- `DelaunayTriangulation`: For triangulation in text alignment and addconnectors.
- `Graphs`: For graph-based network operations.
"""
module Logjam

# Import all required packages
using Serialization
using DataFrames
using CSV
using GeoMakie, CairoMakie
using DelaunayTriangulation
using Graphs

# GLMakie extension support (set by LogjamGLMakieExt when GLMakie is loaded)
const _glmakie_available = Ref{Bool}(false)
const _glmakie_activate = Ref{Any}(nothing)

# Export data functions
export usplace, uscounty, uscentract, uscenblkgrp, uszcta5, uszcta3
export uscbsa, uscsa, st2fips, fips2st
export faf5nodes, faf5links, faf5interstate, loadcsvdata

# Export map functions and constants
export makemap, mapbbox, aligntext, isptinbbox
export WORLD_LIMITS, US_LIMITS, CUS_LIMITS

# Export road network functions
export dgc, Dgc, prune_reindex, thin, thin_stats, addconnectors
export links2graph, x2ln

# Export routing functions
export segcost, rteTC, isorigin, rte2loc
export twoopt, mincostinsert, pairwisesavings, savings

# Include component files
include("datatools.jl")
include("maptools.jl")
include("roadtools.jl")
include("routetools.jl")

end # module Logjam
