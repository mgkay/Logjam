# Transportation Economics (transtools)

Rate estimation and cost analysis for LTL (less-than-truckload) and TL (truckload) freight transportation using empirically-derived models.

## Overview

The transportation economics module provides tools for:

- **Rate Estimation**: Predict LTL rates using nonlinear regression models fitted to industry data
- **Charge Calculation**: Compute total transport charges including minimum charge handling
- **Mode Selection**: Compare TL vs LTL costs and automatically select optimal mode
- **Total Logistics Cost**: Analyze trade-offs between transportation and inventory costs
- **Batch Processing**: Process multiple shipments with automatic mode selection

All rate models are based on empirical data covering 55,800 origin-destination pairs across the continental United States.

## Functions

### Rate Functions

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

## Examples

### Basic LTL Rate Estimation

```julia
using Logjam

# Estimate LTL rate for a 1000 lb shipment
q = 0.5  # tons (1000 lb)
s = 8.0  # lb/ft³ (density)
d = 250.0  # miles

rate = rate_ltl(q, s, d)
println("LTL rate: \$", round(rate, digits=3), "/ton-mi")

# Calculate total charge (rate × weight × distance, or minimum charge)
charge = charge_ltl(q, d, s)
println("Total LTL charge: \$", round(charge, digits=2))

# Check minimum charge for this distance
min_charge = mincharge_ltl(d)
println("Minimum charge: \$", round(min_charge, digits=2))
```

### TL vs LTL Comparison

```julia
using Logjam

# Compare TL and LTL for increasing shipment weights
weights = [0.5, 1.0, 2.0, 5.0, 10.0, 15.0, 20.0]
distance = 500.0
density = 10.0

println("Weight (tons) | LTL Charge | TL Charge | Better Mode")
println("-------------|-----------|----------|------------")

for q in weights
    c_ltl = charge_ltl(q, distance, density)
    c_tl = charge_tl(q, distance, density)
    better = c_tl < c_ltl ? "TL" : "LTL"

    println(rpad(q, 13), "| ",
            rpad("\$" * string(round(c_ltl, digits=2)), 10), "| ",
            rpad("\$" * string(round(c_tl, digits=2)), 9), "| ",
            better)
end
```

**Output:**
```
Weight (tons) | LTL Charge | TL Charge | Better Mode
-------------|-----------|----------|------------
0.5          | $72.34    | $1000.00 | LTL
1.0          | $102.15   | $1000.00 | LTL
2.0          | $144.89   | $1000.00 | LTL
5.0          | $257.82   | $1000.00 | LTL
10.0         | Inf       | $1000.00 | TL
15.0         | Inf       | $1000.00 | TL
20.0         | Inf       | $1000.00 | TL
```

### Batch Processing with Mode Selection

```julia
using Logjam, DataFrames

# Define multiple shipments
shipments = DataFrame(
    weight = [0.5, 2.0, 5.0, 15.0, 30.0],
    density = [8.0, 10.0, 12.0, 15.0, 18.0],
    distance = [250.0, 500.0, 800.0, 1200.0, 1500.0]
)

# Auto-select TL vs LTL for each shipment
results = transport_costs(shipments; mode=:auto)

# Display results
println(results[:, [:weight, :distance, :mode, :cost, :rate]])
```

**Output:**
```
5×5 DataFrame
 Row │ weight   distance  mode    cost      rate
     │ Float64  Float64   Symbol  Float64   Float64
─────┼────────────────────────────────────────────────
   1 │     0.5     250.0  ltl      67.28   0.538240
   2 │     2.0     500.0  ltl     144.89   0.144890
   3 │     5.0     800.0  ltl     281.47   0.070367
   4 │    15.0    1200.0  tl     2400.0    0.133333
   5 │    30.0    1500.0  tl     9000.0    0.200000
```

### PPI Adjustment for Different Years

```julia
using Logjam

# LTL PPI values (source: BLS)
ppi_2004 = 104.2  # Base year
ppi_2010 = 118.4
ppi_2020 = 156.2
ppi_2025 = 175.0  # Hypothetical

# Same shipment, different years
q, s, d = 1.0, 10.0, 500.0

charge_2004 = charge_ltl(q, d, s; ppi=ppi_2004)
charge_2010 = charge_ltl(q, d, s; ppi=ppi_2010)
charge_2020 = charge_ltl(q, d, s; ppi=ppi_2020)
charge_2025 = charge_ltl(q, d, s; ppi=ppi_2025)

println("2004: \$", round(charge_2004, digits=2))
println("2010: \$", round(charge_2010, digits=2), " (+",
        round(100*(charge_2010/charge_2004 - 1), digits=1), "%)")
println("2020: \$", round(charge_2020, digits=2), " (+",
        round(100*(charge_2020/charge_2004 - 1), digits=1), "%)")
println("2025: \$", round(charge_2025, digits=2), " (+",
        round(100*(charge_2025/charge_2004 - 1), digits=1), "%)")
```

### Total Logistics Cost Analysis

```julia
using Logjam

# Product parameters
v = 1000.0  # Value: $1000/ton
h = 0.25    # Holding cost: 25%/year
f = 100.0   # Annual demand: 100 tons/year
a = 0.5     # Inventory fraction (avg inventory = aq)

# Transportation parameters
distance = 500.0
density = 10.0

# Evaluate TLC for different shipment sizes
shipment_sizes = 1.0:1.0:20.0
tlc_values = Float64[]

for q in shipment_sizes
    c = charge_ltl(q, distance, density)
    isinf(c) && (c = charge_tl(q, distance, density))
    tlc = totlogcost(q, c, f, a, v, h)
    push!(tlc_values, tlc)
end

# Find optimal shipment size
optimal_q = shipment_sizes[argmin(tlc_values)]
min_tlc = minimum(tlc_values)

println("Optimal shipment size: ", optimal_q, " tons")
println("Minimum TLC: \$", round(min_tlc, digits=2), "/year")

# Plot TLC curve (requires plotting package)
using CairoMakie
fig = Figure()
ax = Axis(fig[1, 1], xlabel="Shipment Size (tons)", ylabel="Total Logistics Cost (\$/year)")
lines!(ax, collect(shipment_sizes), tlc_values)
scatter!(ax, [optimal_q], [min_tlc], color=:red, markersize=15)
display(fig)
```

### Aggregating Multiple Shipments

```julia
using Logjam, DataFrames

# Multiple products with different characteristics
products = DataFrame(
    f = [100.0, 200.0, 150.0],  # Annual demand (tons/year)
    s = [8.0, 10.0, 6.0],       # Density (lb/ft³)
    v = [1000.0, 1500.0, 800.0], # Value ($/ton)
    h = [0.25, 0.25, 0.25],      # Holding cost rate
    a = [0.5, 0.5, 0.5]          # Inventory fraction
)

# Aggregate into single equivalent product
agg = aggshmt(products)

println("Aggregated product:")
println("  Total demand: ", agg.f, " tons/year")
println("  Equivalent density: ", round(agg.s, digits=2), " lb/ft³")
println("  Weighted average value: \$", round(agg.v, digits=2), "/ton")

# Use aggregated parameters for TLC analysis
q = 10.0  # tons
c = charge_ltl(q, 500.0, agg.s)
tlc = totlogcost(q, c, agg.f, agg.a, agg.v, agg.h)
println("  TLC @ q=10: \$", round(tlc, digits=2), "/year")
```

### Cube vs Weight Limitations

```julia
using Logjam

# Analyze payload constraints
densities = 5.0:1.0:30.0
max_payloads = maxpayld.(densities, 25.0, 2750.0)

println("Density (lb/ft³) | Max Payload (tons) | Limiting Factor")
println("-----------------|-------------------|----------------")

for (s, q) in zip(densities, max_payloads)
    limiting = q < 25.0 ? "Cube" : "Weight"
    println(rpad(s, 17), "| ", rpad(round(q, digits=2), 18), "| ", limiting)
end
```

## Performance Tips

1. **Vectorization**: All functions support broadcasting for batch calculations
2. **PPI Updates**: Use current PPI values from BLS for accurate estimates
3. **Mode Selection**: Use `transport_costs(...; mode=:auto)` for automatic TL/LTL selection
4. **Out-of-Bounds**: Check for `Inf` results when estimating rates
5. **Aggregation**: Use `aggshmt` when multiple products share transport

## Model Validation

The LTL rate model was validated against CzarLite tariff data:
- **R² = 0.92**: Explains 92% of rate variation
- **Coverage**: 55,800 origin-destination pairs
- **Geography**: Continental United States
- **Base Year**: 2004 (PPI = 104.2 for LTL, 102.7 for TL)

For current rates, adjust PPI values to reflect inflation and market conditions.

## References

- M.G. Kay (2023), *Freight Transport* (course notes), Section 1.5, NC State University
- Kay, M.G. & Warsing, D.P. (2009), "Estimating LTL rates using publicly available empirical data," *International Journal of Logistics Research and Applications*, 12(3):165–193, doi:10.1080/13675560802392415
- Bureau of Labor Statistics, Producer Price Index for LTL and TL Transportation
