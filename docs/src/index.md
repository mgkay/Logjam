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

The sections below follow the order of the course: location, transportation, distances, road networks, routing, inventory, data and geocoding, maps, and display. Each opens with what its functions are for, and where an example can run offline when the manual is built, it is run and its output shown.

## Extensions

Logjam draws maps with GeoMakie and the Makie backend the caller loads, CairoMakie in the course (`makemap` leaves the active backend's settings as the caller set them). Five optional extensions are available:

### Map Extension

`makemap`, `plotroads!` and `dcf` are the map extension's, which GeoMakie loads (`using CairoMakie, GeoMakie`; CairoMakie draws). Called without it, each is a `MethodError` that says what to load.

```julia
using CairoMakie, GeoMakie        # Triggers LogjamMapExt extension
using Logjam
```

### Makie Extension

`aligntext(ax, x, y, labels)`, which places labels clear of everything drawn in an axis, and the route and shipment drawing `plotroute!` and `plotshmt!` are the Makie extension's, which Makie loads: CairoMakie alone is enough, and GeoMakie loads it too. They work on a plain `Axis` and on the `GeoAxis` of `makemap`. Called without it, `plotroute!` and `plotshmt!` are each a `MethodError` that says what to load.

```julia
using CairoMakie                  # Triggers LogjamMakieExt extension
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

### Optimization Extension

`Logjam.TSP` (Lecture 5.1's TSP formulation) and `Logjam.binpack` (Lecture 2.7's bin packing model) solve their models with HiGHS through JuMP, and `snapvals` reads a solved model's variables, when JuMP and HiGHS are both loaded. Called without them, `TSP` and `binpack` are each a `MethodError` that says what to load. `Logjam.subtours`, which `TSP` calls, needs neither.

```julia
using JuMP, HiGHS                 # Triggers LogjamJuMPExt extension
using Logjam

r = Logjam.TSP(C)                 # C, a square matrix of arc costs
r.TC, r.tour
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

### Bin Packing

Lecture 2.7's bin packing model, solved by HiGHS: it needs the optimization extension (`using JuMP, HiGHS`), so the manual shows its example without running it.

```@docs
binpack
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

The fields of a shipment `sh` and a truck `tr`, shared by the transport and the routing functions, are the
docstring of `Logjam.shtr`, so `?Logjam.shtr` shows them at the REPL:

```@docs
shtr
```

## Distance Functions

Functions for calculating distances between points using various metrics. The great-circle distance from
Raleigh to Charlotte, the pair the `dgc` docstring uses:

```@example distance
using Logjam
round(dgc((-78.6382, 35.7796), (-80.8431, 35.2271)); digits = 1)
```

`dgca` adjusts a distance to a demand point that stands for a region of known area, by Lecture 2.5's floor
(`method = :max`, the default) or its empirical average distance (`method = :empirical`).

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

An OpenStreetMap network joins the U.S. road network (below, under Data Functions) at the edge of its box, for routes that start or end on a city's streets and run beyond them:

```@docs
joinroads
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

### The TSP as a MILP

Lecture 5.1's formulation of the traveling salesman problem, solved one round of subtour constraints at a time. `TSP` needs the optimization extension (`using JuMP, HiGHS`), so the manual shows its example without running it; `subtours` needs nothing.

```@docs
TSP
subtours
```

## Inventory Functions

The Poisson measures of Lecture 6.2's base-stock and reorder-point models and Lecture 6.3's arrival process, each
the lecture's own definition. They are public but not exported, so they are called as `Logjam.pi0` and so on, and
a lecture's own definition of the name does not collide with them.

```@docs
poissoncdf
pi0
qbar
poissarr
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

### U.S. Road Network

Logjam's U.S. road network is derived from FAF5 and differs from it in that each stretch of road between two junctions is one link, the two carriageways of a divided road one two-way link, each interchange and divided-highway intersection one node with its ramps gone, and each link carries an Interstate flag, so the Interstates are a subset of it.

```@docs
usrdlink
usrdnode
usrdnodemap
```

## Map Functions

Functions for creating geographical maps and visualizing road networks using the Makie ecosystem. `makemap` and
`plotroads!` need the map extension (`using CairoMakie, GeoMakie`) and `aligntext(ax, x, y, labels)` the Makie
extension (`using CairoMakie`), so the manual lists them without running them; `mapbbox` and `aligntext(x, y)` need
neither.

### Constants

```@docs
WORLD_LIMITS
US_LIMITS
CUS_LIMITS
```

### Map Creation

`mapbbox` gives the box a map is drawn in, offline and without the map extension: around a set of points, of a
county (Lecture 4.2's construction from the Census block groups), of a city, town or other Census place (the extent
of its 2020 polygon), or of a state (the extent of its counties' boxes). Raleigh's, and North Carolina's:

```@example boxes
using Logjam
mapbbox("Raleigh"; state = :NC), mapbbox(:NC)
```

`aligntext` has two methods. `aligntext(x, y)` chooses each label's side from the points alone, by the angles to
its neighbors, and needs no extension. `aligntext(ax, x, y, labels)` reads the figure as drawn, each label's ink and
every line, marker and other label in the axis, places the labels clear of them, and returns the keyword arguments
`text!` splats; it needs Makie (the Makie extension), and names any label it could not place clear of everything
when called with `verbose = true`.

```@docs
makemap
mapbbox
aligntext
alloclines
usstates
```

### Road and Route Visualization

`plotroute!` draws a route and `plotshmt!` shipments, each with an arrowhead to show its direction, on a plain `Axis`
or a map; with `names` or `loads` they mark and label each stop, its loads written by `ldlabel`, and `plotroute!`'s
`number` numbers several routes, all placed by `aligntext(ax, ...)` and placed again when a later call adds to the
axis. Drawn as schematics, in Matlog `pplot`'s `'NumNode'` style, `plotshmt!` (`node_numbers`, `node_size`, `bend`
and `bend_at` for each shipment, `shmt_labels`) and a single route's `plotroute!` (`node_numbers`, `bend` for each leg,
`label`) put each location in a numbered circle, cut the curves at its edge with the arrowhead's tip on it, and write
labels along the curves. `ldlabel` needs no extension:

```@example ldlabel
using Logjam, DataFrames
sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6])     # Lecture 5.2's three shipments of Ex. 2
ldlabel(sh)
```

```@docs
plotroads!
plotroute!
plotshmt!
ldlabel
```

## Display and Formatting

Functions for formatted output and figure display. `dcf` is deprecated and is removed in v0.4.0: end a cell with the
figure itself (`fig`), or call `display(current_figure())`.

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
