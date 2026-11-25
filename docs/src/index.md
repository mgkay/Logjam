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

The sections below follow the order of the course: location, transportation, distances, road networks, routing, data and geocoding, maps, and display. Each opens with what its functions are for, and where an example can run offline when the manual is built, it is run and its output shown.

## Extensions

Logjam draws maps with GeoMakie and the Makie backend the caller loads, CairoMakie in the course (`makemap` leaves the active backend's settings as the caller set them). Three optional extensions are available:

### Map Extension

`makemap`, `plotroads!`, `plotroute!` and `dcf` are the map extension's, which GeoMakie loads (`using CairoMakie, GeoMakie`; CairoMakie draws). Called without it, each is a `MethodError` that says what to load.

```julia
using CairoMakie, GeoMakie        # Triggers LogjamMapExt extension
using Logjam
```

### OSM Extension

To download OpenStreetMap road networks (`osm_roads`), load LightOSM before Logjam:

```julia
using LightOSM                    # Triggers LogjamOSMExt extension
using Logjam

bbox = mapbbox(stops_lon, stops_lat; xexpand=0.1, yexpand=0.1)
nodes, links = osm_roads(bbox; cache_dir = "osm")  # saved there; read from there next time, without LightOSM
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

### Continuous Location

```@docs
ala
wcentroid
```

### Utility Functions

```@docs
randX
```

## Transportation Functions

Rate estimation and cost analysis for LTL and TL freight transportation. Lecture 3.3's Example 1 sizes a
shipment of 20 tons a year of a \$25,000-a-ton, 40-lb, 9-ft³ product moved 532 miles at the January 2018
PPIs (TL 131.0, LTL 177.4); `minTLC` finds the size that minimizes the total logistics cost and the mode
that goes with it:

```@example transport
using Logjam
sh = (f=20.0, s=40/9, a=1.0, v=25_000.0, h=0.30, d=532.0)
tr = (r=2.00*131.0/102.7, Kwt=25.0, Kcu=2750.0, ppi=131.0)
result = minTLC(sh, tr, 177.4)
(round(result.qᵒ; digits = 4), round(result.TLCᵒ; digits = 2), result.isLTL)
```

The shipment and truck are the `sh` and `tr` of the contract set out at the end of this section, [the `sh` and `tr` contract](@ref The-sh-and-tr-contract).

### Rate and Charge Functions

```@docs
rate_ltl
charge_tl
charge_ltl
mincharge_tl
mincharge_ltl
maxpayld
qmax_ltl
```

### Total Logistics Cost

```@docs
totlogcost
aggshmt
minTLC
```

### The `sh` and `tr` contract

A function of one shipment takes `sh` as a row (a `NamedTuple` or a `DataFrameRow`) and a function of a set of
shipments takes the table, one row for each shipment; a truck `tr` is a `NamedTuple`. The same `sh` and `tr`
serve the transport functions and the routing functions: each reads the fields it needs, a field it reads is
used when it is present, and a field it does not read is ignored. The reading, field by field:

| Field of `sh` | Meaning | Read by |
|:--|:--|:--|
| `b`, `e` | begin and end location index | routing (`rte2loc`, `rteTC`) |
| `f`, `q` | annual demand (ton/yr); shipment weight (ton) | transport; `q` also by `rteTC` against `Kwt` |
| `s` | density (lb/ft³) | transport; with `q`, `rteTC` against `Kcu` |
| `a`, `v`, `h` | inventory fraction, unit value (\$/ton), holding rate (1/yr) | transport |
| `d` | distance (mi) | transport |
| `tL`, `tU`, `tbmin`, `tbmax`, `temin`, `temax` | loading and unloading times, time windows | `rteTC(...; full = true)` |
| `avh` | demand-weighted mean of `a·v·h`, attached by `aggshmt` | `totlogcost`, `minTLC` when present |
| `qmax`, `qᵒ`, `TLCᵒ`, `isLTL` | attached by `maxpayld` and `minTLC` | none |

| Field of `tr` | Meaning | Read by |
|:--|:--|:--|
| `b`, `e` | depot begin and end location | `rte2loc`, `rteTC` |
| `Kwt`, `Kcu` | weight (ton) and cube (ft³) capacity | `maxpayld`; `rteTC` checks each load mix |
| `maxTC` | maximum cost of a route | `rteTC` |
| `r`, `ppi` | TL rate per mile (\$/mi) and its PPI | transport |
| `tbmin`, `tbmax`, `temin`, `temax` | time windows at the depot | `rteTC(...; full = true)` |

Where a function documents a default for an absent field, it is used (a truck with none of `Kwt`, `Kcu`,
`maxTC` is uncapacitated, and a plain `rteTC` is the sum of the segment costs); a field with no default is
required. The LTL PPI is a separate scalar at the call site, since LTL and TL are different carriers.

## Distance Functions

Functions for calculating distances between points using various metrics. The great-circle distance from
Raleigh to Charlotte, the pair the `dgc` docstring uses:

```@example distance
using Logjam
round(dgc((-78.6382, 35.7796), (-80.8431, 35.2271)); digits = 1)
```

```@docs
dgc
dgca
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
pathroads
```

### OSM Functions

Functions for downloading OpenStreetMap road networks. Downloading requires the OSM extension (`using LightOSM`); reading a saved copy does not.

```@docs
osm_roads
_osm_cache_path
_osm_snap_bbox
```

## Routing Functions

Functions for vehicle routing problems, including pickup-and-delivery and capacitated VRP.

### Route Cost and Representation

```@docs
segcost
rteTC
isorigin
rte2loc
rte2ldmx
scanTW
rtesegsum
rte2idx
sh2rte
```

### Route Construction and Improvement

```@docs
mincostinsert
pairwisesavings
savings
twoopt
```

## Data Functions

Functions for working with U.S. geographical and statistical data. Lecture 5.2's Code block 5 gives each
shipment's origin and destination by zip code, and the zip codes' centroids give the distance matrix the
routing procedures look into; `loc2lonlat` finds them (here by integer, as a column read from a file gives
them) and `lonlat` hands the result to the distance functions as the matrix of coordinates they take:

```@example data
using Logjam
zips = [27606, 32606, 48234, 27518]
size(lonlat(loc2lonlat(zips)))
```

### Geographic Data

```@docs
usstate
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
lonlat
```

### FAF5 Road Network Data

```@docs
faf5nodes
faf5links
```

## Map Functions

Functions for creating geographical maps and visualizing road networks using the Makie ecosystem. They need
the map extension (`using CairoMakie, GeoMakie`), so the manual lists them without running them.

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
alloclines
usstates
```

### Road and Route Visualization

```@docs
plotroads!
plotroute!
```

## Display and Formatting

Functions for formatted output and figure display.

```@docs
prt
dcf
snapvals
thousands
```

## The Module

```@docs
Logjam
```
