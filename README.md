# Logjam

![LogjamLogo](docs/assets/LogjamLogo.png)

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://mgkay.github.io/Logjam/)

Logjam is a Julia package providing tools and data for logistics engineering tasks. It enables users to work with U.S. geographical data and FAF5 road networks, create maps using GeoMakie, and create multi-stop routes using savings-based construction and 2-opt improvement heuristics.

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

Key functions used:
- `cropnetwork`: Extracts a subnetwork within a bounding box
- `addconnectors`: Adds demand points to the road network
- `links2graph`: Converts links to a weighted directed graph
- `shortestpaths`: Computes shortest path distances and parent pointers
- `savings`: Constructs routes using a savings-based insertion heuristic
- `twoopt`: Improves routes using 2-opt local search
- `rte2loc`: Converts shipment sequence to location sequence
- `rte2lines`: Converts locations to plottable coordinates via network paths
