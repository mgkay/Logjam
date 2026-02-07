# Facility Location (loctools)

Discrete facility location optimization using construction and improvement heuristics for uncapacitated facility location (UFL) and p-median problems.

## Overview

The facility location module provides fast heuristics for solving discrete location problems:

- **Construction heuristics**: Build solutions from scratch (ADD, DROP)
- **Improvement heuristics**: Refine existing solutions (EXCHANGE)
- **Hybrid methods**: Combine multiple approaches for high-quality solutions (UFL)
- **p-median**: Fixed number of facilities, no setup costs

All algorithms support custom cost matrices and flexible constraint handling.

## Functions

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

## Problem Formulation

### Uncapacitated Facility Location (UFL)

Given:
- `n` potential facility sites with fixed costs `k[i]`
- `m` customers with known demand
- Cost matrix `C[i,j]` for serving customer `j` from facility `i`

Minimize:
```
TC = Σᵢ kᵢyᵢ + Σⱼ min{C[i,j] : yᵢ = 1}
```

where `yᵢ ∈ {0,1}` indicates whether facility `i` is open.

### p-Median Problem

Select exactly `p` facilities (no fixed costs) to minimize total transportation cost:

```
TC = Σⱼ min{C[i,j] : i ∈ selected facilities}
```

## Examples

### Basic UFL Problem

```julia
using Logjam

# Define problem: 3 potential sites, 3 customers
k = [10.0, 10.0, 15.0]  # Fixed facility costs
C = [0.0 3.0 7.0;       # Transport costs
     3.0 0.0 4.0;
     7.0 4.0 0.0]

# Solve using hybrid heuristic
facilities, total_cost = ufl(k, C)
println("Open facilities: ", facilities)
println("Total cost: \$", total_cost)
```

**Output:**
```
  Add: 13.0
 Xchg: 13.0
Open facilities: [1, 2]
Total cost: $13.0
```

### Comparing Construction Heuristics

```julia
# ADD heuristic (start empty, add facilities)
y_add, TC_add = ufladd(k, C)

# DROP heuristic (start full, drop facilities)
y_drop, TC_drop = ufldrop(k, C)

# EXCHANGE improvement
y_improved, TC_improved = uflxchg(k, C, y_add)

println("ADD:      ", y_add, " → \$", TC_add)
println("DROP:     ", y_drop, " → \$", TC_drop)
println("EXCHANGE: ", y_improved, " → \$", TC_improved)
```

### p-Median Problem

```julia
# Select exactly 2 facilities (no fixed costs)
facilities, cost = pmedian(2, C; verbose=false)
println("Selected facilities: ", facilities)
println("Total transport cost: \$", cost)
```

### Realistic Problem: Distribution Center Location

```julia
using Logjam, DataFrames

# Load 20 major U.S. cities
cities = usplace()
sort!(cities, :POP, rev=true)
top20 = cities[1:20, :]

# Potential DC locations: 5 largest cities
dc_coords = top20[1:5, [:LON, :LAT]]

# Customer locations: all 20 cities
cust_coords = top20[:, [:LON, :LAT]]

# Compute transport costs (great circle distance)
C = dists(dc_coords, cust_coords, :mi)

# Fixed costs: $100k per DC
k = fill(100_000.0, 5)

# Solve
facilities, total_cost = ufl(k, C)
println("Open DCs in: ", top20[facilities, :NAME])
println("Total annual cost: \$", round(total_cost, digits=2))
```

### Generating Random Test Problems

```julia
using Logjam

# Generate random facility and customer locations
n_facilities = 10
n_customers = 50

# Random coordinates in [0,100] × [0,100]
P = rand(n_facilities + n_customers, 2) .* 100

facility_coords = P[1:n_facilities, :]
customer_coords = P[n_facilities+1:end, :]

# Compute Euclidean distance matrix
C = dists(facility_coords, customer_coords, 2)

# Random fixed costs between 50 and 150
k = 50 .+ rand(n_facilities) .* 100

# Solve
facilities, cost = ufl(k, C)
println("Selected ", length(facilities), " out of ", n_facilities, " facilities")

# Generate additional random points within same bounding box
new_points = randX(P, 10)
```
