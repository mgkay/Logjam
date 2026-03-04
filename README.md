# Logjam

![LogjamLogo](docs/assets/LogjamLogo.png)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mgkay.github.io/Logjam/)

Logjam is a Julia package for logistics engineering, providing tools for:
* **Facility Location**: Discrete optimization algorithms for facility location problems, including Uncapacitated Facility Location (UFL) and *p*-Median construction and improvement heuristics.
* **Transportation Costing**: Formulas for estimating LTL & TL freight rates, calculating minimum charges, and evaluating total logistics costs (TLC).
* **Network Analysis**: Routing and topology tools for the FAF5 highway network, including shortest paths and automatic facility connectors.
* **Vehicle Routing**: Algorithms for multi-stop route optimization, featuring savings-based construction and local search improvement methods.
* **Spatial Data**: A gazetteer of U.S. administrative boundaries and points, including Cities, Counties, ZIP codes (3- and 5-digit), Census tracts, and CBSA/CSA definitions.
* **Distance Metrics**: Unified distance calculation utilities supporting Rectilinear (*L*₁), Euclidean (*L*₂), and Great Circle (Haversine) metrics.
* **Mapping**: Plotting recipes and helper functions for mapping spatial data using GeoMakie.

## Installation

To install Logjam, use the following command in your Julia REPL:

```julia
using Pkg
Pkg.add(url="https://github.com/mgkay/Logjam.git")
```

## Dependencies

Logjam uses CairoMakie by default for rendering maps. For interactive display with GLMakie, load it before calling `makemap`:

```julia
using GLMakie  # Optional: enables backend=:GLMakie
using Logjam
```

For OpenStreetMap road network functionality (`osm_roads`, `stitchnetworks`), load the OSM extension packages before Logjam. The extension activates automatically when both are present:

```julia
using LightOSM, NearestNeighbors  # Optional: enables OSM functions
using Logjam
```

## Worked Examples

The examples below are ordered for incremental capability building — each one introduces a focused set of Logjam functions that later examples build upon. The full capability set is described in the overview bullets above. All examples are available as a runnable Jupyter notebook: [logjam_examples.ipynb](https://github.com/mgkay/Logjam/blob/main/examples/logjam_examples.ipynb).

---

### Example 1 — Spatial Data

Logjam includes a built-in U.S. gazetteer covering cities (`usplace`), counties (`uscounty`), 3- and 5-digit ZIP codes (`uszcta3`, `uszcta5`), CBSAs (`uscbsa`), and CSAs (`uscsa`). All tables share a consistent schema: FIPS codes for joining, LON/LAT coordinates following the Logjam convention (longitude first), and population counts where available. This example demonstrates loading and filtering place data, FIPS code conversion, and geographic name lookup.

```julia
using Logjam
using DataFrames

# Load U.S. place data (cities, towns, CDPs) and inspect the schema
places = usplace()
display(first(places[:, [:NAME, :ST, :LON, :LAT, :POP, :ISCUS]], 4))
```

```
4×6 DataFrame
 Row │ NAME           ST   LON        LAT      POP       ISCUS
     │ String         Sym  Float64    Float64  Int64     Bool
─────┼───────────────────────────────────────────────────────────
   1 │ New York       :NY  -74.0059   40.7128  8336817   true
   2 │ Los Angeles    :CA  -118.2437  34.0522  3979576   true
   3 │ Chicago        :IL  -87.6298   41.8781  2693976   true
   4 │ Houston        :TX  -95.3698   29.7604  2304580   true
```

```julia
# FIPS conversion: state symbol ↔ FIPS code
fips_nc = st2fips(:NC)           # 37
sym_nc  = fips2st(fips_nc)       # :NC

# Filter to NC cities with population over 100,000
nc_large = filter(r -> r.STFIP == fips_nc && r.POP > 100_000, places)
println("$(nrow(nc_large)) NC cities with pop > 100k")

# Forward geocoding: city name to coordinates
raleigh_xy = name2lonlat("Raleigh, NC", places)   # [-78.64, 35.78]

# Reverse geocoding: coordinates to nearest named place
nearest = lonlat2name([-78.85 35.73], filter(r -> r.POP > 50_000 && r.ISCUS, places))
println("Nearest large city: $(nearest.name[1]) ($(round(nearest.dist[1]; digits=1)) mi)")

# Load continental US 3-digit ZIP centroids
z3 = filter(r -> r.ISCUS, uszcta3())
println("Continental US 3-digit ZIPs: $(nrow(z3))")
```

```
10 NC cities with pop > 100k
Nearest large city: Cary (6.4 mi)
Continental US 3-digit ZIPs: 899
```

**After-action.** The `ISCUS` flag is the standard filter for continental U.S. analysis — it removes Alaska, Hawaii, Puerto Rico, and other territories that would distort national maps. All coordinate columns follow the (LON, LAT) convention throughout Logjam, which means western longitudes are negative. The `st2fips` and `fips2st` functions enable joins between datasets that use different geographic identifiers. `lonlat2name` is used in later examples to reverse-geocode facility hub coordinates into interpretable city names, making model outputs readable without manual lookup. The `name2lonlat` function provides the inverse operation when building scenarios from named locations.

---

### Example 2 — Mapping

Logjam's `makemap` function creates GeoMakie map figures with automatic projection, region detection, and a FAF5 interstate highway background. This example maps NC cities and introduces the full mapping toolkit: `makemap` for the figure and axis, `scatter!` and `text!` for data, `aligntext` for automatic label positioning, and the `hborders` return value for customizing the built-in road overlay.

```julia
using Logjam
using GeoMakie, CairoMakie, DataFrames

# Load NC cities with population > 100,000
cities = filter(r -> r.STFIP == st2fips(:NC) && r.POP > 100_000, usplace())
x, y, name = cities.LON, cities.LAT, cities.NAME

# Create map — auto-fits region to data; draws FAF5 interstates by default.
# Returns: fig (Figure), ax (GeoAxis), hborders (road/border handles), limits (bbox).
fig, ax, hborders, limits = makemap(x, y)
ax.title = "North Carolina Cities with Population > 100,000"

# Customize the built-in interstate overlay (hborders[1])
hborders[1].color[] = (:steelblue, 0.5)

# Plot city locations and labels
scatter!(ax, x, y, color=:red, markersize=12)
text!(ax, x, y, text=name; aligntext(x, y)...)

display(fig)
```

![NC Cities Plot](docs/assets/nc_cities_plot.png)

**After-action.** `makemap` detects when coordinates fall within the continental U.S. and automatically overlays the FAF5 interstate network as a geographic reference. The `hborders` return value exposes the road and border line handles for post-hoc styling, as shown above for the interstate color. `aligntext(x, y)` returns a named tuple of keyword arguments (`:align`, `:offset`) that are splatted into `text!` via `...`, automatically positioning each label to avoid overlap with its marker.

---

### Example 3 — Facility Location

A classic strategic logistics problem: place a fixed number of distribution hubs to minimize total weighted distance to customers. Using U.S. 3-digit ZIP code centroids as demand points and population as demand weight, the *p*-median model selects six hubs that minimize total people-miles. This example introduces `dists` for distance matrix construction and `pmedian`, `alloclines`, and `lonlat2name` for the full facility location workflow.

```julia
using Logjam
using GeoMakie, CairoMakie, DataFrames

# Load continental US 3-digit ZIP code centroids
z3 = filter(r -> r.ISCUS, uszcta3())
XY = hcat(z3.LON, z3.LAT)

# Build population-weighted cost matrix: C[i,j] = distance(i,j) × population(j)
C = dists(XY, XY, :mi) .* z3.POP'

# Solve p-median: select 6 hubs minimizing total people-miles
y, TC, W = pmedian(6, C; verbose=false)

# Reverse-geocode hub coordinates to nearest large city
hubs = lonlat2name(XY[y, :], filter(r -> r.POP >= 50_000 && r.ISCUS, usplace()))

# Map: continental US with allocation lines and hub markers
fig, ax = makemap(region=:CUS)

colors = Makie.wong_colors()[1:6]
X, Y = alloclines(W, XY, XY)
for (ci, i) in enumerate(y)
    lines!(ax, X[i], Y[i], color=(colors[ci], 0.2), linewidth=0.8)
end

scatter!(ax, XY[:, 1], XY[:, 2], color=:red, markersize=3, strokewidth=0)
hub_xy = XY[y, :]
scatter!(ax, hub_xy[:, 1], hub_xy[:, 2], color=colors, markersize=18,
         strokewidth=3, strokecolor=:white)
text!(ax, hub_xy[:, 1], hub_xy[:, 2], text=hubs.name; aligntext(hub_xy[:, 1], hub_xy[:, 2])...)

ax.title = "Optimal Facility Locations (P-Median)\nSelected from 3-Digit ZIP Code Centroids (Population-Weighted)"
display(fig)
```

![Facility Location Plot](docs/assets/facloc_pmedian_plot.png)

**After-action.** `dists(XY, XY, :mi)` computes a full pairwise great-circle distance matrix in miles; the `:mi` symbol selects miles, `:km` selects kilometers, and `:gc` returns dimensionless radians. Broadcasting `.* z3.POP'` weights each column by the destination's population, converting the distance matrix into a cost matrix in people-miles. `pmedian` returns the hub indices `y`, total cost `TC`, and the allocation matrix `W` (a sparse indicator mapping each demand point to its nearest hub). `alloclines` converts `W` into NaN-separated line segment vectors per hub, which `lines!` renders efficiently without a loop per connection. `lonlat2name` reverse-geocodes the hub coordinates to the nearest large city, providing interpretable labels. For problems where the number of facilities is itself a decision, Logjam provides UFL heuristics — `ufladd`, `ufldrop`, `uflxchg`, and `ufl` — that optimize both facility selection and count.

---

### Example 4 — Network Analysis and Vehicle Routing

Road network routing in Logjam uses the FAF5 national freight highway network as the foundation. The standard pipeline — `cropnetwork` → `addconnectors` → `links2graph` → `shortestpaths` — prepares a network for any routing task. These two sub-examples demonstrate the pipeline at two scales and two routing problem types.

#### 4a. Large Scale: Multi-Stop Pickup-Delivery (FAF5 Network)

A pickup-delivery problem (PDP) is a routing problem where each shipment has a distinct origin and destination. This example routes five shipments across ten NC cities using the FAF5 highway network. The vehicle does not return to a starting depot — the route connects pickups and deliveries in the optimal sequence.

```julia
using Logjam
using GeoMakie, CairoMakie, DataFrames

# Load NC cities with population > 100,000
cities = filter(r -> r.STFIP == st2fips(:NC) && r.POP > 100_000, usplace())
```

**City Index** (alphabetical order from `filter`):

| Index | City | | Index | City |
|:-----:|------|---|:-----:|------|
| 1 | Cary | | 6 | Greensboro |
| 2 | Charlotte | | 7 | High Point |
| 3 | Concord | | 8 | Raleigh |
| 4 | Durham | | 9 | Wilmington |
| 5 | Fayetteville | | 10 | Winston-Salem |

```julia
# Define 5 shipments with distinct origins and destinations
shipments = DataFrame(
    b = [2, 3, 10, 7, 6],   # Pickup city index
    e = [8, 4,  1, 5, 9]    # Delivery city index
)
```

**Shipment Manifest:**

| Shipment | Origin | Destination |
|:--------:|--------|-------------|
| 1 | Charlotte (2) | Raleigh (8) |
| 2 | Concord (3) | Durham (4) |
| 3 | Winston-Salem (10) | Cary (1) |
| 4 | High Point (7) | Fayetteville (5) |
| 5 | Greensboro (6) | Wilmington (9) |

```julia
# Build road network: crop FAF5 to region, attach city connectors
nodes_base, links_base = cropnetwork(faf5nodes(), faf5links(), cities.LON, cities.LAT)
nodes, links = addconnectors(nodes_base, links_base, cities.LON, cities.LAT)

# Compute shortest paths between all city connector nodes
g = links2graph(links)
dist_mat, parents = shortestpaths(g, nrow(cities))

# Construct route with savings heuristic, then improve with 2-opt
cost_fn(r) = rteTC(r, shipments, dist_mat)
initial_routes = savings(cost_fn, shipments)
final_route, cost = twoopt(initial_routes[1], cost_fn)

# Map: NC region with road network overlay and optimized route
fig, ax = makemap(cities.LON, cities.LAT)
plotroads!(ax, links, nodes)

scatter!(ax, cities.LON, cities.LAT, color=:blue, markersize=10)
text!(ax, cities.LON, cities.LAT, text=cities.NAME; aligntext(cities.LON, cities.LAT)...)

# Reconstruct road-following path for each consecutive stop pair and plot
loc_seq = rte2loc(final_route, shipments)
full_path = Int[]
for k in 1:length(loc_seq)-1
    leg = tracepath(parents[loc_seq[k]], loc_seq[k], loc_seq[k+1])
    k == 1 ? append!(full_path, leg) : append!(full_path, leg[2:end])
end
plotroute!(ax, full_path, nodes; color=:red, linewidth=2.5, show_markers=false)

ax.title = "Multi-Stop PDP: Savings + 2-Opt\n(5 Shipments, 10 NC Cities, FAF5 Network)"
display(fig)
```

![NC Routing Plot](docs/assets/nc_routing_plot.png)

**After-action.** `cropnetwork` extracts the FAF5 subgraph whose bounding box contains the demand points, reducing graph size before solving. `addconnectors` appends artificial connector edges from each demand point to its nearest network node — without these, the demand points would not be reachable via shortest paths. `shortestpaths(g, nrow(cities))` computes shortest-path distances and parent pointers from the last `nrow(cities)` nodes (the connectors), returning a `dist_mat` ready for use as the routing cost matrix. `plotroads!` renders the road network with adaptive zoom-based styling — interstates appear thicker than local roads, and line weights scale with the map's latitude span. `savings` constructs an initial route by iteratively merging the most cost-saving shipment pair, then `twoopt` improves it by reversing sub-sequences. `rte2loc` converts the abstract route to a stop sequence; for each consecutive leg, `tracepath` reconstructs the road-following node sequence from the parent pointer vectors, and `plotroute!` renders the complete path with optional origin/destination markers.

---

#### 4b. Local Scale: Single-Hub Delivery (OSM Network)

> **Requires OSM extension:** load `LightOSM` and `NearestNeighbors` before `Logjam`.

In a single-hub vehicle routing problem (VRP), all deliveries originate from one depot and the vehicle returns to the depot after completing the route. This contrasts with the PDP in 4a, where shipments have distinct origins and the vehicle does not return to a start. This example downloads a local OpenStreetMap road network for Gainesville, FL and routes deliveries from a central depot to five locations.

```julia
using LightOSM, NearestNeighbors  # Must precede Logjam to activate OSM extension
using Logjam
using GeoMakie, CairoMakie, DataFrames

# Download OSM road network for Gainesville urban core
# Tight bbox chosen for CairoMakie resolution: (xmin, xmax, ymin, ymax)
bbox = (-82.365, -82.285, 29.625, 29.685)
nodes_osm, links_osm = osm_roads(bbox; cache_dir=joinpath(@__DIR__, "data"))
println("OSM network: $(nrow(nodes_osm)) nodes, $(nrow(links_osm)) links")

# Define depot and 5 delivery locations (LON, LAT)
depot_lon,  depot_lat  = -82.346, 29.648   # Near UF campus
dlv_lon = [-82.338, -82.325, -82.310, -82.330, -82.355]
dlv_lat = [ 29.660,  29.651,  29.643,  29.634,  29.638]

stops_lon = vcat(depot_lon, dlv_lon)
stops_lat = vcat(depot_lat, dlv_lat)
n_dlv = length(dlv_lon)

# Attach depot and delivery points to the OSM network
nodes, links = addconnectors(nodes_osm, links_osm, stops_lon, stops_lat)

# Compute shortest paths between all stops (depot = stop 1, deliveries = stops 2–6)
g = links2graph(links)
dist_mat, parents = shortestpaths(g, length(stops_lon))

# Formulate single-hub VRP: all shipments depart from depot (stop 1)
shipments = DataFrame(
    b = fill(1, n_dlv),        # All pickups at depot
    e = collect(2:n_dlv+1)    # Each delivery at a distinct stop
)
tr = (b=[1], e=[1])            # Route starts and ends at depot

# Construct and improve route
cost_fn(r) = rteTC(r, shipments, dist_mat, tr)
initial_routes = savings(cost_fn, shipments)
final_route, cost = twoopt(initial_routes[1], cost_fn)
println("Route cost: $(round(cost; digits=2)) miles")

# Map: local OSM network with optimized delivery route
fig, ax = makemap(stops_lon, stops_lat)
plotroads!(ax, links_osm, nodes_osm)

scatter!(ax, dlv_lon, dlv_lat, color=:blue, markersize=12, label="Delivery")
scatter!(ax, [depot_lon], [depot_lat], color=:green, markersize=16,
         marker=:rect, label="Depot")

# Reconstruct road-following path for each consecutive stop pair and plot
loc_seq = rte2loc(final_route, shipments, tr)
full_path = Int[]
for k in 1:length(loc_seq)-1
    leg = tracepath(parents[loc_seq[k]], loc_seq[k], loc_seq[k+1])
    k == 1 ? append!(full_path, leg) : append!(full_path, leg[2:end])
end
plotroute!(ax, full_path, nodes; color=(:red, 0.7), linewidth=2.5, show_markers=false)

ax.title = "Single-Hub VRP: Savings + 2-Opt\n(5 Deliveries, Gainesville FL, OSM Network)"
display(fig)
```

![Gainesville VRP Plot](docs/assets/gnv_osm_vrp_plot.png)

**After-action.** `osm_roads` downloads drivable roads from the OpenStreetMap Overpass API for the specified bounding box and caches results as CSV files — subsequent calls with the same (snapped) bbox load from cache rather than re-downloading. The tight bounding box is intentional: CairoMakie renders static images at fixed resolution, so a smaller geographic area produces sharper, more readable road detail. The `tr=(b=[1], e=[1])` argument to `rteTC` and `rte2loc` specifies that the route begins and ends at stop 1 (the depot), making this a proper VRP tour rather than an open path. Setting all pickup indices to 1 (the depot) means each shipment represents a depot-to-customer delivery; the savings heuristic still applies because it evaluates cost reductions from combining deliveries into a single tour. `rte2loc` returns the stop sequence as node indices; `tracepath` reconstructs the road-following path for each leg from the parent pointer vectors, and `plotroute!` renders the complete route. For scenarios requiring local OSM detail integrated with the national FAF5 network — for example, long-haul routing that transitions to city streets at the destination — Logjam's `stitchnetworks` function creates connector edges between the two networks, returning a unified graph compatible with the standard `links2graph` → `shortestpaths` pipeline.
