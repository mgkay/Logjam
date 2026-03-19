"""
# Logjam

Logistics toolkit for facility location, transportation costing, freight road networks,
route optimization, U.S. geographic data, and GeoMakie visualizations.

## Overview
The `Logjam` package provides comprehensive tools for logistics engineering and operations
research, including facility location optimization, transportation economics, freight road
networks, route optimization, U.S. geographic data, and map visualization.

## Facility Location Functions
- `ufladd`: Greedy ADD construction heuristic for UFL.
- `ufldrop`: Greedy DROP construction heuristic for UFL.
- `uflxchg`: Pairwise EXCHANGE improvement heuristic.
- `ufl`: Hybrid UFL heuristic (ADD + DROP + EXCHANGE).
- `pmedian`: p-median facility location (fixed number of facilities).
- `randX`: Generate random points within bounding box.

## Transportation Economics Functions
- `rate_ltl`: Estimate LTL transportation rate (\$/ton-mi).
- `charge_tl`: Calculate TL transport charge.
- `charge_ltl`: Calculate LTL transport charge.
- `mincharge_tl`: TL minimum charge.
- `mincharge_ltl`: LTL minimum charge.
- `maxpayld`: Maximum truck payload (weight or cube limited).
- `totlogcost`: Total logistics cost (transport + inventory).
- `aggshmt`: Aggregate shipments into equivalent single shipment.
- `transport_costs`: Batch calculate transport costs with mode selection.

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
- `loc2lonlat`: Forward geocoding — addresses, cities, postal codes, counties to coordinates.
- `lonlat2loc`: Reverse geocoding — coordinates to nearest place with area-based "in" radius.

## Map Functions
- `makemap`: Creates a map visualization for predefined or user-defined regions.
- `mapbbox`: Calculates bounding box for geographic coordinates with optional expansion.
- `aligntext`: Determines text alignment and offset positions for map labels.
- `isptinbbox`: Checks if a point lies within a bounding box.
- `alloclines`: Convert allocation matrix to NaN-separated line segments for visualization.
- `plotroads!`: Overlay road networks on GeoAxis with adaptive zoom-based styling.

## Road Network Functions
- `dgc`: Great circle distance between two points.
- `d1`: Rectilinear (Manhattan) distance between two points.
- `d2`: Euclidean distance between two points.
- `dists`: Unified distance matrix (replaces Dgc, supports all metrics).
- `prune_reindex`: Prune network to common vertices and reindex.
- `thin`: Remove degree-2 nodes from network (use `verbose=true` for statistics).
- `addconnectors`: Add demand point connectors to road network.
- `links2graph`: Convert links DataFrame to weighted directed graph.
- `x2ln`: Convert graph edges to line coordinates for plotting.
- `cropnetwork`: Crop road network to bounding box of coordinates.
- `shortestpaths`: Compute shortest path distances and parent pointers.

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
- `Graphs`, `SimpleWeightedGraphs`: For graph-based network operations.
"""
module Logjam

# Import all required packages
using Artifacts
using LazyArtifacts
using Serialization
using DataFrames
using CSV
using DelaunayTriangulation
using Graphs
using SimpleWeightedGraphs
using SparseArrays

# CairoMakie extension support (set by LogjamCairoMakieExt)
const _cairomakie_available = Ref{Bool}(false)
const _cairomakie_activate = Ref{Any}(nothing)
const _dcf_impl = Ref{Any}(nothing)

# Map extension support (set by LogjamMapExt when CairoMakie + GeoMakie loaded)
const _geomakie_available = Ref{Bool}(false)
const _makemap_impl = Ref{Any}(nothing)
const _plotroads_impl = Ref{Any}(nothing)
const _plotroute_impl = Ref{Any}(nothing)

# GLMakie extension support (set by LogjamGLMakieExt when GLMakie is loaded)
const _glmakie_available = Ref{Bool}(false)
const _glmakie_activate = Ref{Any}(nothing)

# OSM extension support (set by LogjamOSMExt when LightOSM + NearestNeighbors are loaded)
const _osm_available = Ref{Bool}(false)
const _osm_download = Ref{Any}(nothing)
const _osm_stitch = Ref{Any}(nothing)

# Nominatim extension support (set by LogjamNominatimExt when HTTP + JSON3 are loaded)
const _nominatim_available = Ref{Bool}(false)
const _nominatim_geocode = Ref{Any}(nothing)

# Export facility location functions
export ufladd, ufldrop, uflxchg, ufl, pmedian, randX

# Export transportation economics functions
export rate_ltl, charge_tl, charge_ltl, mincharge_tl, mincharge_ltl, maxpayld
export totlogcost, aggshmt, transport_costs

# Export data functions
export usplace, uscounty, uscentract, uscenblkgrp, uszcta5, uszcta3
export uscbsa, uscsa, st2fips, fips2st
export faf5nodes, faf5links, faf5interstate
export loc2lonlat, lonlat2loc

# Export data helper functions (H1–H3) and relocated functions
export mat2df, prt, snapvals
export isptinbbox, alloclines

# Export map functions and constants
export makemap, mapbbox, aligntext, plotroads!, plotroute!
export WORLD_LIMITS, US_LIMITS, CUS_LIMITS

# Export helper functions (H7)
export dcf

# Export road network functions (including H5–H6)
export dgc, d1, d2, dists, prune_reindex, thin, addconnectors
export links2graph, x2ln, cropnetwork, shortestpaths, tracepath

# Export OSM functions (require LightOSM + NearestNeighbors extension)
export osm_roads, stitchnetworks

# Export routing functions
export segcost, rteTC, isorigin, rte2loc
export twoopt, savings, mincostinsert, pairwisesavings

# Public API (accessible as Logjam.func, not auto-imported into namespace)
public rte2lines

# Include component files
include("loctools.jl")
include("transtools.jl")
include("datatools.jl")
include("maptools.jl")
include("disttools.jl")
include("roadtools.jl")
include("routetools.jl")
include("osmtools.jl")
include("geocode.jl")

# ─── Stub functions for CairoMakie extension (H7, H8) ───

"""
    dcf()

Display current figure. Requires `using CairoMakie`.
"""
function dcf()
    if _cairomakie_available[]
        _dcf_impl[]()
    else
        error("dcf() requires CairoMakie. Run: using CairoMakie")
    end
end

end # module Logjam
