# Logjam

![LogjamLogo](docs/assets/LogjamLogo.png)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mgkay.github.io/Logjam/)

Logjam is a Julia package for logistics and operations research, providing tools for:
- **Facility Location**: Discrete optimization (UFL, p-median) with construction and improvement heuristics
- **Transportation Economics**: LTL/TL rate estimation, minimum charges, and total logistics cost analysis
- **Freight Road Networks**: FAF5 highway network, shortest paths, distance matrices, and automatic connector generation
- **Route Optimization**: Multi-stop routing with savings-based construction and local search improvement
- **U.S. Geographic Data**: Built-in cities/counties/states datasets with population and coordinate information
- **Visualization**: Publication-quality maps and plots using GeoMakie

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

## Quick Start

### Facility Location Example

Solve an uncapacitated facility location (UFL) problem to optimally place facilities:

```julia
using Logjam

# Fixed costs and customer-facility transport costs
k = [10.0, 10.0, 15.0]  # Fixed facility costs
C = [0.0 3.0 7.0;       # Transport costs: facility i → customer j
     3.0 0.0 4.0;
     7.0 4.0 0.0]

# Find optimal facility locations
facilities, total_cost = ufl(k, C)
println("Open facilities: ", facilities)
println("Total cost: ", total_cost)

# Solve p-median (select exactly 2 facilities, no fixed costs)
facilities, total_cost = pmedian(2, C; verbose=false)
```

### Transportation Cost Example

Estimate LTL and TL transportation charges using empirically-derived rate models:

```julia
using Logjam

# Calculate LTL rate and charge
rate = rate_ltl(0.5, 8.0, 250.0)  # 0.5 tons, 8 lb/ft³, 250 miles
charge = charge_ltl(0.5, 250.0, 8.0)  # Total charge including minimum
println("LTL rate: \$", round(rate, digits=3), "/ton-mi")
println("LTL charge: \$", round(charge, digits=2))

# Calculate TL charge (automatically handles multiple trucks if needed)
tl_charge = charge_tl(10.0, 500.0, 8.0)  # 10 tons, 500 miles, 8 lb/ft³

# Batch process multiple shipments with mode selection
using DataFrames
shipments = DataFrame(
    weight = [0.5, 2.0, 15.0, 30.0],
    density = [8.0, 10.0, 12.0, 15.0],
    distance = [250.0, 500.0, 800.0, 1200.0]
)
results = transport_costs(shipments; mode=:auto)  # Auto-selects TL vs LTL
```

### Distance Matrix Example

Compute distance matrices using multiple metrics:

```julia
using Logjam

# City coordinates [LON, LAT]
cities = [-78.64 35.78;   # Raleigh, NC
          -122.42 37.77;  # San Francisco, CA
          -87.63 41.88]   # Chicago, IL

# Great circle (geodesic) distances in miles
D_miles = dists(cities, cities, :mi)

# Euclidean distances (planar approximation)
D_eucl = dists(cities, cities, 2)  # or just dists(cities, cities)

# Manhattan (rectilinear) distances
D_manh = dists(cities, cities, 1)
```

## Example Usage

Here's an example that demonstrates how to use Logjam to visualize cities in North Carolina with populations over 100,000:

```julia
using Logjam
using GeoMakie, DataFrames

# Filter U.S. place data for cities in North Carolina with populations over 100,000
df = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())

# Extract longitude, latitude, and city names from dataframe
x, y, name = df.LON, df.LAT, df.NAME

# Create and title a map figure and axis
fig, ax = makemap(x, y)
ax.title = "Cities in North Carolina with populations over 100,000"

# Plot cities as scatter points
scatter!(ax, x, y)

# Annotate the scatter plot with city names
text!(ax, x, y, text=name; aligntext(x, y)...)

# Display the map
display(fig);
```
In the above code, `st2fips`, `usplace`, `makemap`, and `aligntext` are Logjam functions. Use `fips2st` for the reverse lookup (FIPS code to state symbol).

![NC Cities Plot](docs/assets/nc_cities_plot.png)

## Routing Example

Logjam includes tools for vehicle routing problems. This example demonstrates a pickup-delivery problem (PDP) using the FAF5 road network to optimize routes across NC cities.

```julia
using Logjam
using GeoMakie, CairoMakie, DataFrames
using Graphs

# 1. Load NC cities with population > 100k
cities = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())

# 2. Define 5 shipments (west-to-east flow covering all 10 cities)
shipments = DataFrame(
    b = [2, 3, 10, 7, 6],   # Origins: Charlotte, Concord, Winston-Salem, High Point, Greensboro
    e = [8, 4, 1, 5, 9]     # Destinations: Raleigh, Durham, Cary, Fayetteville, Wilmington
)
```

**Shipment Manifest:**

| Shipment | Origin | Destination |
|:--------:|--------|-------------|
| 1 | Charlotte | Raleigh |
| 2 | Concord | Durham |
| 3 | Winston-Salem | Cary |
| 4 | High Point | Fayetteville |
| 5 | Greensboro | Wilmington |

```julia
# 3. Load FAF5 network and crop to region
nodes_full, links_full = faf5nodes(), faf5links()
links_conn, nodes_conn = cropnetwork(nodes_full, links_full, cities.LON, cities.LAT)
links_conn, nodes_conn = addconnectors(links_conn, nodes_conn, cities.LON, cities.LAT)

# 4. Compute network shortest paths
g = links2graph(links_conn)
dist_mat, parents = shortestpaths(g, nrow(cities))

# 5. Solve routing problem with savings heuristic + 2-opt improvement
cost_fn(r) = rteTC(r, shipments, dist_mat)
initial_routes = savings(cost_fn, shipments)
final_route, cost = twoopt(initial_routes[1], cost_fn)

# 6. Visualize the optimized route
fig, ax = makemap(cities.LON, cities.LAT; region=:US)
scatter!(ax, cities.LON, cities.LAT, color=:blue)
text!(ax, cities.LON, cities.LAT, text=cities.NAME; aligntext(cities.LON, cities.LAT)...)

loc_seq = rte2loc(final_route, shipments)
lx, ly = rte2lines(loc_seq, parents, nodes_conn)
lines!(ax, lx, ly, color=(:red, 0.6), linewidth=3)
ax.title = "Multi-Stop Route Constructed Using Savings and Improved Using TwoOpt\n(5 Shipments, 10 Cities)"
display(fig)
```

![NC Routing Plot](docs/assets/nc_routing_plot.png)

Logjam functions used:
- `addconnectors`: Adds demand points to the road network
- `cropnetwork`: Extracts a subnetwork within a bounding box
- `faf5links`: Loads FAF5 road network links
- `faf5nodes`: Loads FAF5 road network nodes
- `links2graph`: Converts links to a weighted directed graph
- `rte2lines`: Converts locations to plottable coordinates via network paths
- `rte2loc`: Converts shipment sequence to location sequence
- `rteTC`: Calculates total route cost
- `savings`: Constructs routes using a savings-based insertion heuristic
- `shortestpaths`: Computes shortest path distances and parent pointers
- `st2fips`: Converts state symbol to FIPS code
- `twoopt`: Improves routes using 2-opt local search
- `usplace`: Returns U.S. place (city) data
