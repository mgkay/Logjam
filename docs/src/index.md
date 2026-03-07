```@meta
CurrentModule = Logjam
```

# Logjam

Logjam is a Julia package providing tools and data for logistics engineering tasks. It enables users to work with U.S. geographical data and FAF5 road networks, create maps using GeoMakie, and create multi-stop routes using savings-based construction and 2-opt improvement heuristics.

## GLMakie Extension

Logjam uses CairoMakie by default. GLMakie support is provided via a package extension that is automatically loaded when GLMakie is available. For interactive display, load GLMakie before Logjam:

```julia
using GLMakie  # Triggers LogjamGLMakieExt extension
using Logjam

fig, ax = makemap(region=:US, backend=:GLMakie)
```

```@index
```

## Map Functions

Functions for creating geographical maps using the Makie ecosystem.

### Constants

```@docs
WORLD_LIMITS
US_LIMITS
CUS_LIMITS
```

### Functions

```@docs
makemap
mapbbox
aligntext
bestfit
isptinbbox
alloclines
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
name2lonlat
lonlat2name
```

### FAF5 Road Network Data

```@docs
faf5nodes
faf5links
faf5interstate
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

Functions for working with road networks.

```@docs
prune_reindex
thin
addconnectors
links2graph
x2ln
cropnetwork
shortestpaths
```

## Routing Functions

Functions for vehicle routing problems.

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

### Route Visualization

```@docs
plotroute!
plotroads!
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