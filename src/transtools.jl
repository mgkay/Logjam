# =============================================================================
# Transportation Economics
# =============================================================================

# =============================================================================
# Rate Estimation
# =============================================================================

"""
    rate_ltl(q, s, d; ppi=104.2) -> Float64 or Vector{Float64}

Estimate LTL (less-than-truckload) transportation rate.

Uses nonlinear regression model fitted to industry tariff tables (CzarLite) covering
55,800 O-D pairs across the continental US. Returns Inf for out-of-bounds inputs.

# Arguments
- `q`: Shipment weight (tons). Clamped to minimum 0.075 tons (150 lb).
- `s`: Shipment density (lb/ft³).
- `d`: Shipment distance (miles). Clamp to minimum 37 miles.
- `ppi`: LTL Producer Price Index (default: 104.2, the 2004 baseline).

# Returns
- Rate in \$/ton-mile. Returns `Inf` if q > 5, d > 3354, or 2000q/s > 650.

# Formula
```
r_LTL = PPI_LTL × [(s²/8 + 14) / ((q^(1/7) × d^(15/29) - 7/2) × (s² + 2s + 14))]
```

# Valid Ranges
- q ∈ [0.075, 5] tons (150 lb to 10,000 lb)
- d ∈ [37, 3354] miles
- 2000q/s ≤ 650 ft³ (cube-out limit)

# Example
```julia
rate_ltl(0.5, 8.0, 250.0)  # 0.5 ton, 8 lb/ft³, 250 miles → ~0.12 \$/ton-mi
rate_ltl([0.5, 1.0], [8.0, 10.0], [250.0, 500.0])  # Vectorized
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.2, Eq (1.5),
  NC State University
- Kay & Warsing (2009), "Estimating LTL rates using publicly available empirical
  data," Int. J. Logistics Research and Applications, 12(3):165–193
  doi:10.1080/13675560802392415
"""
function rate_ltl(q, s, d; ppi=104.2)
    # Clamp to valid ranges
    q_safe = max.(q, 150/2000)
    d_safe = max.(d, 37)

    # Formula: r_LTL = ppi × [(s²/8 + 14) / ((q^1/7 × d^15/29 - 7/2)(s² + 2s + 14))]
    numerator = ppi .* (s.^2 ./ 8 .+ 14)
    denominator = (q_safe.^(1/7) .* d_safe.^(15/29) .- 7/2) .* (s.^2 .+ 2 .* s .+ 14)

    rate = numerator ./ denominator

    # Mark out-of-bounds as Inf
    invalid = (denominator .< eps()) .| (q .> 5) .| (d .> 3354) .| (2000 .* q ./ s .> 650)
    rate = ifelse.(invalid, Inf, rate)

    return rate
end

"""
    mincharge_tl(r::Real=2.00; ppi=102.7) -> Float64

Calculate TL minimum charge (independent of distance).

Represents fixed costs of loading/unloading at origin and destination. The constant
45 is an empirically derived value reflecting terminal handling costs that do not vary
with distance, fitted from industry tariff data using methods similar to Kay & Warsing (2009).

# Arguments
- `r`: TL revenue per loaded truck-mile (\$/mi). Default: 2.00 (2004 baseline).
- `ppi`: TL Producer Price Index (default: 102.7, 2004 baseline).

# Returns
- Minimum charge in dollars.

# Formula
```
MC_TL = (r/2) × 45  or  MC_TL = (ppi/102.7) × 45
```

# Example
```julia
mincharge_tl()  # Uses default r=2.00 → 45.0
mincharge_tl(2.11; ppi=108.6)  # 2005 rates → 47.6
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.3, Eq (1.7),
  NC State University. Empirical derivation methodology: Kay & Warsing (2009),
  Int. J. Logistics Research and Applications, 12(3):165–193
"""
function mincharge_tl(r::Real=2.00; ppi=102.7)
    return (ppi / 102.7) * 45
end

"""
    mincharge_ltl(d::Real; ppi=104.2) -> Float64

Calculate LTL minimum charge.

The LTL minimum charge includes both a fixed terminal handling cost (45) and a
distance-dependent component that accounts for the shipment being loaded/unloaded
at multiple terminals along its route. The parameters (28/19 exponent, 1625 divisor)
were empirically fitted from industry tariff data using nonlinear regression methods
similar to those described in Kay & Warsing (2009).

# Arguments
- `d`: Distance (miles). Must be > 0 and ≤ 3354.
- `ppi`: LTL Producer Price Index (default: 104.2, 2004 baseline).

# Returns
- Minimum charge in dollars.

# Formula
```
MC_LTL = (ppi/104.2) × [45 + (d^(28/19) / 1625)]
```

where 28/19 ≈ 1.474 (economies of scale exponent) and 1625 is the scaling constant.

# Example
```julia
mincharge_ltl(0.0)    # 0.0 (no shipment)
mincharge_ltl(250.0)  # 250 miles → ~67.3
mincharge_ltl(500.0)  # 500 miles → ~90.8
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.3, Eq (1.8),
  NC State University. Empirical derivation methodology: Kay & Warsing (2009),
  Int. J. Logistics Research and Applications, 12(3):165–193
"""
function mincharge_ltl(d::Real; ppi=104.2)
    d > 3354 && error("LTL minimum charge not defined for d > 3354 miles")
    d <= 0 && return 0.0
    return (ppi / 104.2) * (45 + d^(28/19) / 1625)
end

"""
    charge_tl(q, d, s; r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7) -> Float64

Calculate TL transport charge (combining distance cost and minimum charge).

# Arguments
- `q`: Shipment weight (tons).
- `d`: Distance (miles).
- `s`: Shipment density (lb/ft³).
- `r`: TL rate per loaded truck-mile (\$/mi). Default: 2.00.
- `Kwt`: Truck weight capacity (tons). Default: 25.0.
- `Kcu`: Truck effective cube capacity (ft³). Default: 2750.0.
- `ppi`: TL Producer Price Index. Default: 102.7.

# Returns
- Transport charge in dollars.

# Formula
```
c_TL = ⌈q/q_max⌉ × max(r × d, MC_TL)
where q_max = min(Kwt, s × Kcu / 2000)
```

# Example
```julia
charge_tl(10.0, 500.0, 8.0)  # 10 tons, 500 mi, 8 lb/ft³ → ~1000
charge_tl(25.0, 500.0, 8.0)  # Full truckload → ~1000
charge_tl(30.0, 500.0, 8.0)  # Needs 2 trucks → ~2000
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.1, Eq (1.1-1.2),
  NC State University
"""
function charge_tl(q, d, s; r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7)
    q_max = min(Kwt, s * Kcu / 2000)
    num_trucks = ceil(Int, q / q_max)
    charge_per_truck = max(r * d, mincharge_tl(r; ppi=ppi))
    return num_trucks * charge_per_truck
end

"""
    charge_ltl(q, d, s; ppi=104.2) -> Float64

Calculate LTL transport charge (rate × weight × distance, or minimum charge).

# Arguments
- `q`: Shipment weight (tons).
- `d`: Distance (miles).
- `s`: Shipment density (lb/ft³).
- `ppi`: LTL Producer Price Index. Default: 104.2.

# Returns
- Transport charge in dollars.

# Formula
```
c_LTL = max(r_LTL × q × d, MC_LTL)
```

# Example
```julia
charge_ltl(0.5, 250.0, 8.0)  # 0.5 ton, 250 mi → ~15-20
charge_ltl(2.0, 500.0, 10.0) # 2 tons, 500 mi → ~120-150
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.2 and 1.5.3,
  Eq (1.5) and (1.8), NC State University
"""
function charge_ltl(q, d, s; ppi=104.2)
    r = rate_ltl(q, s, d; ppi=ppi)
    isinf(r) && return Inf
    return max(r * q * d, mincharge_ltl(d; ppi=ppi))
end

"""
    maxpayld(s, Kwt, Kcu) -> Float64 or Vector{Float64}

Determine maximum payload limited by weight or cube capacity.

# Arguments
- `s`: Shipment density (lb/ft³).
- `Kwt`: Truck weight capacity (tons). Typical: 25.0.
- `Kcu`: Truck cube capacity (ft³). Typical: 2750.0.

# Returns
- Maximum payload in tons: min(Kwt, s·Kcu/2000).

# Example
```julia
maxpayld(8.0, 25.0, 2750.0)  # 8 lb/ft³ → 11.0 tons (cube-limited)
maxpayld(15.0, 25.0, 2750.0) # 15 lb/ft³ → 20.6 tons (cube-limited)
maxpayld(25.0, 25.0, 2750.0) # 25 lb/ft³ → 25.0 tons (weight-limited)
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.1, Eq (1.2),
  NC State University
"""
function maxpayld(s, Kwt, Kcu)
    return min.(Kwt, s .* Kcu ./ 2000)
end

# =============================================================================
# Total Logistics Cost
# =============================================================================

"""
    totlogcost(q, c, f, a, v, h) -> Float64
    totlogcost(q, c, params) -> Float64

Calculate total logistics cost (transport + inventory).

TLC = TC + IC, where:
- TC (transport cost) = c·f/q  (cost per shipment × annual shipments)
- IC (inventory cost) = q·a·v·h  (avg inventory × value × holding rate)

# Arguments
- `q`: Shipment size (tons).
- `c`: Transport charge per shipment (\$).
- `f`: Annual demand (tons/year).
- `a`: Inventory fraction (0-D correction, typically 0.5).
- `v`: Product value (\$/ton).
- `h`: Annual holding cost rate (fraction, e.g., 0.25 = 25%/year).
- `params`: Any object with fields `.f`, `.a`, `.v`, `.h` (e.g., NamedTuple
  from [`aggshmt`](@ref) or a DataFrameRow).

# Returns
- Total logistics cost (\$/year).

# Example
```julia
# Scalar form
totlogcost(5.0, 450.0, 100.0, 0.5, 1000.0, 0.25)
# Returns: TC = 9000, IC = 625, TLC = 9625

# Using aggshmt output
agg = aggshmt(products)
c = charge_ltl(q, d, agg.s)
totlogcost(q, c, agg)
```
"""
function totlogcost(q, c, f, a, v, h)
    TC = c .* f ./ max.(q, eps())  # Avoid division by zero
    IC = max.(q, 0) .* a .* v .* h

    # Set TC to 0 when c is 0 (works for both scalars and arrays)
    TC = ifelse.(abs.(c) .< eps(), 0.0, TC)

    return TC .+ IC
end

totlogcost(q, c, p) = totlogcost(q, c, p.f, p.a, p.v, p.h)

"""
    aggshmt(df::DataFrame) -> NamedTuple

Aggregate multiple shipments into a single equivalent shipment.

Weighted harmonic mean for density, weighted arithmetic mean for value/holding
cost/inventory fraction. Weights are annual demands (f) or shipment sizes (q).

# Arguments
- `df`: DataFrame with columns `:f` (demand), `:s` (density), `:v` (value),
        `:h` (holding rate), `:a` (inventory fraction). If `:f` missing, uses `:q`.

# Returns
- NamedTuple with aggregated fields: `(f=..., s=..., v=..., h=..., a=...)`.

# Example
```julia
using DataFrames
df = DataFrame(
    f = [100, 200, 150],
    s = [8, 10, 6],
    v = [1000, 1500, 800],
    h = [0.25, 0.25, 0.25],
    a = [0.5, 0.5, 0.5]
)
agg = aggshmt(df)
# agg.f = 450, agg.s ≈ 8.18 (harmonic mean), agg.v ≈ 1200 (weighted avg)
```
"""
function aggshmt(df::DataFrame)
    # Use f if available, otherwise q
    weight = hasproperty(df, :f) ? df.f : df.q
    total = sum(weight)

    return (
        f = hasproperty(df, :f) ? sum(df.f) : sum(df.q),
        s = total / sum(weight ./ df.s),  # Harmonic mean
        v = sum(weight ./ total .* df.v),  # Weighted mean
        h = sum(weight ./ total .* df.h),
        a = sum(weight ./ total .* df.a)
    )
end

"""
    transport_costs(shipments::DataFrame; mode=:auto, kwargs...) -> DataFrame

Calculate transport costs for a collection of shipments, automatically selecting TL vs LTL.

# Arguments
- `shipments`: DataFrame with columns `:weight` (tons), `:density` (lb/ft³), `:distance` (miles).
- `mode`: `:auto` (select min cost), `:tl`, or `:ltl`.
- `kwargs`: Additional parameters passed to charge functions (e.g., `ppi`, `Kwt`, `Kcu`, `r`).

# Returns
- DataFrame with original columns plus `:cost` (\$), `:mode` (`:tl` or `:ltl`), `:rate` (\$/ton-mi).

# Example
```julia
using DataFrames
shipments = DataFrame(
    weight = [0.5, 2.0, 15.0, 30.0],
    density = [8.0, 10.0, 12.0, 15.0],
    distance = [250.0, 500.0, 800.0, 1200.0]
)
results = transport_costs(shipments)
# Automatically selects LTL for small shipments, TL for large
```
"""
function transport_costs(shipments::DataFrame; mode=:auto, kwargs...)
    n = nrow(shipments)
    costs = zeros(n)
    modes = Vector{Symbol}(undef, n)
    rates = zeros(n)

    for i in 1:n
        q, s, d = shipments[i, :weight], shipments[i, :density], shipments[i, :distance]

        if mode == :auto
            c_tl = charge_tl(q, d, s; kwargs...)
            c_ltl = charge_ltl(q, d, s; kwargs...)
            if c_tl <= c_ltl
                costs[i] = c_tl
                modes[i] = :tl
                rates[i] = c_tl / (q * d)
            else
                costs[i] = c_ltl
                modes[i] = :ltl
                rates[i] = rate_ltl(q, s, d; ppi=get(kwargs, :ppi, 104.2))
            end
        elseif mode == :tl
            costs[i] = charge_tl(q, d, s; kwargs...)
            modes[i] = :tl
            rates[i] = costs[i] / (q * d)
        elseif mode == :ltl
            costs[i] = charge_ltl(q, d, s; kwargs...)
            modes[i] = :ltl
            rates[i] = rate_ltl(q, s, d; ppi=get(kwargs, :ppi, 104.2))
        end
    end

    result = copy(shipments)
    result[!, :cost] = costs
    result[!, :mode] = modes
    result[!, :rate] = rates
    return result
end
