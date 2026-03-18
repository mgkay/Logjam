```@meta
CurrentModule = Logjam
```

# Logjam

Logjam is a Julia package for logistics engineering, providing tools for:
- **Facility Location**: Discrete optimization algorithms for facility location problems, including Uncapacitated Facility Location (UFL) and *p*-Median construction and improvement heuristics.
- **Transportation Costing**: Formulas for estimating LTL & TL freight rates, calculating minimum charges, and evaluating total logistics costs (TLC).
- **Network Analysis**: Routing and topology tools for the FAF5 highway network and OpenStreetMap road networks, including shortest paths and automatic facility connectors.
- **Vehicle Routing**: Algorithms for multi-stop route optimization, featuring savings-based construction and local search improvement methods.
- **Spatial Data**: A gazetteer of U.S. administrative boundaries and points, including Cities, Counties, ZIP codes (3- and 5-digit), Census tracts, and CBSA/CSA definitions.
- **Geocoding**: Forward geocoding (`loc2lonlat`) from place names, postal codes, or street addresses to coordinates, and reverse geocoding (`lonlat2loc`) from coordinates to nearest named places. Street-address geocoding uses the Nominatim API via an optional extension.
- **Distance Metrics**: Unified distance calculation utilities supporting Rectilinear (*L*₁), Euclidean (*L*₂), and Great Circle (Haversine) metrics.
- **Mapping**: Geographic visualization with GeoMakie, including FCLASS-based road network rendering with OSM Carto-inspired styling, route overlays, and facility location plots.

## Extensions

Logjam uses CairoMakie by default for rendering maps. Three optional extensions are available:

### GLMakie Extension

For interactive display, load GLMakie before Logjam:

```julia
using GLMakie  # Triggers LogjamGLMakieExt extension
using Logjam

fig, ax = makemap(region=:US, backend=:GLMakie)
```

### OSM Extension

For OpenStreetMap road network functionality (`osm_roads`, `stitchnetworks`), load LightOSM and NearestNeighbors before Logjam:

```julia
using LightOSM, NearestNeighbors  # Triggers LogjamOSMExt extension
using Logjam

bbox = mapbbox(stops_lon, stops_lat; xexpand=0.1, yexpand=0.1)
nodes, links = osm_roads((bbox[1]..., bbox[2]...))
```

### Nominatim Extension

For street-address geocoding via the OpenStreetMap Nominatim API, load HTTP and JSON3 before Logjam:

```julia
using HTTP, JSON3  # Triggers LogjamNominatimExt extension
using Logjam

stops = DataFrame(STREET=["123 Main St"], CITY=["Raleigh"], STATE=[:NC])
gc = loc2lonlat(stops)  # Geocodes via Nominatim with city/state fallback
```

```@index
```

## Map Functions

Functions for creating geographical maps and visualizing road networks using the Makie ecosystem.

### Constants

```@docs
WORLD_LIMITS
US_LIMITS
CUS_LIMITS
```

### Map Creation

```@docs
makemap
mapbbox
aligntext
isptinbbox
alloclines
```

### Road and Route Visualization

```@docs
plotroads!
plotroute!
```

## Data Functions

Functions for working with U.S. geographical and statistical data.

### Geographic Data

```@docs
usplace
uscounty
uscentract
uscenblkgrp
uszcta5
uszcta3
uscbsa
uscsa
```

### FIPS Conversion

```@docs
st2fips
fips2st
```

### Geocoding

```@docs
loc2lonlat
lonlat2loc
```

### FAF5 Road Network Data

```@docs
faf5nodes
faf5links
faf5interstate
```

## Display and Formatting

Functions for formatted output and figure display.

```@docs
prt
dcf
mat2df
snapvals
```

## Distance Functions

Functions for calculating distances between points using various metrics.

```@docs
dgc
d1
d2
dists
```

## Road Network Functions

Functions for building, manipulating, and routing on road networks. Compatible with both FAF5 and OpenStreetMap data sources.

```@docs
prune_reindex
thin
addconnectors
links2graph
x2ln
cropnetwork
shortestpaths
tracepath
```

### OSM Functions

Functions for downloading and integrating OpenStreetMap road networks. Requires the OSM extension (`using LightOSM, NearestNeighbors`).

```@docs
osm_roads
stitchnetworks
```

## Routing Functions

Functions for vehicle routing problems, including pickup-and-delivery and capacitated VRP.

### Route Cost and Representation

```@docs
segcost
rteTC
isorigin
rte2loc
```

### Route Construction and Improvement

```@docs
mincostinsert
pairwisesavings
savings
twoopt
```

## Location Functions

Discrete facility location optimization using construction and improvement heuristics.

### Construction Heuristics

```@docs
ufladd
ufldrop
```

### Improvement Heuristics

```@docs
uflxchg
```

### Hybrid Methods

```@docs
ufl
pmedian
```

### Utility Functions

```@docs
randX
```

## Transportation Functions

Rate estimation and cost analysis for LTL and TL freight transportation.

### Rate and Charge Functions

```@docs
rate_ltl
charge_tl
charge_ltl
mincharge_tl
mincharge_ltl
maxpayld
```

### Total Logistics Cost

```@docs
totlogcost
aggshmt
transport_costs
```
