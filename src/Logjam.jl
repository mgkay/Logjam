"""
# Logjam

A Julia package providing tools and data for logistics engineering tasks.

## Overview
The `Logjam` package provides geographic visualization using GeoMakie and the Makie ecosystem,
U.S. geographical and statistical data access, map creation with Mercator projections,
and text alignment tools for map annotations.

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

## Map Functions
- `makemap`: Creates a map visualization for predefined or user-defined regions.
- `mapbbox`: Calculates bounding box for geographic coordinates with optional expansion.
- `aligntext`: Determines text alignment and offset positions for map labels.
- `isptinbbox`: Checks if a point lies within a bounding box.

## Constants
- `WORLD_LIMITS`: Geographical limits for world map projections.
- `US_LIMITS`: Geographical limits for U.S. map projections.
- `CUS_LIMITS`: Geographical limits for continental U.S. map projections.

## Dependencies
- `Serialization`: For loading pre-serialized geographic data.
- `DataFrames`: For tabular data representation.
- `GeoMakie`, `CairoMakie`: For creating and rendering maps.
- `GLMakie` (optional): For interactive map display.
- `DelaunayTriangulation`: For triangulation in text alignment functions.
"""
module Logjam

# Import all required packages
using Serialization
using DataFrames
using GeoMakie, CairoMakie
using DelaunayTriangulation

# GLMakie extension support (set by LogjamGLMakieExt when GLMakie is loaded)
const _glmakie_available = Ref{Bool}(false)
const _glmakie_activate = Ref{Any}(nothing)

# Export data functions
export usplace, uscounty, uscentract, uscenblkgrp, uszcta5, uszcta3
export uscbsa, uscsa, st2fips, fips2st

# Export map functions and constants
export makemap, mapbbox, aligntext, isptinbbox
export WORLD_LIMITS, US_LIMITS, CUS_LIMITS

# Include component files
include("datatools.jl")
include("maptools.jl")

end # module Logjam
