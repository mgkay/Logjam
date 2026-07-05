# =============================================================================
# Transportation Economics
# =============================================================================

"""
Unified `sh`/`tr` field contract (transport + routing).

`sh` (a per-shipment `NamedTuple` or `DataFrameRow`) and `tr` (a per-carrier
`NamedTuple`) are ONE unified abstraction shared across the transport helpers
(`rate_ltl`, `charge_tl`, `charge_ltl`, `maxpayld`, `mincharge_tl`, `totlogcost`,
`minTLC`) and the routing helpers (`rteTC`, `rte2loc`, ...). They are
progressively-extended structures: a routing `sh`/`tr` may carry only `b,e`; a
transport `sh`/`tr` carries the economic fields; a fully-populated row carries
the superset and works in BOTH regimes, because each function reads only its own
field subset (the cross-regime test `I5` proves this isolation). Do NOT rename
`sh`/`tr` per regime — the shared fields (`Kwt`, `Kcu`, `s`, `d`) are the same
quantities in both modules.

# Per-shipment row (`sh`) — canonical superset

| Field | Meaning | Type | Read by | Notes |
|-------|---------|------|---------|-------|
| `b`     | Begin/pickup node index                    | Int    | routing | `rte2loc`, `rteTC` |
| `e`     | End/delivery node index                    | Int    | routing | `rte2loc`, `rteTC` |
| `f`     | Annual demand (tons/year)                  | Number | transport | |
| `q`     | Single-shipment weight (ton)               | Number | transport | aggregation weight when `f` absent |
| `s`     | Shipment density (lb/ft³)                  | Number | both (transport) | shared quantity |
| `a`     | Avg origin+destination inventory fraction  | Number | transport | ASCII; math notation `α` in prose |
| `v`     | Unit value (\$/ton)                         | Number | transport | |
| `h`     | Holding cost rate (1/yr)                   | Number | transport | |
| `d`     | Distance (mi)                              | Number | both (transport) | shared quantity |
| `qmax`  | Max payload (ton)                          | Number | — | attached by `maxpayld` |
| `qᵒ`    | Optimal shipment size (ton)                | Number | — | attached by `minTLC` |
| `TLCᵒ`  | Optimal total logistics cost (\$/yr)        | Number | — | attached by `minTLC` |
| `isLTL` | LTL chosen?                                | Bool   | — | attached by `minTLC` |

# Per-carrier (`tr`) — canonical superset

| Field | Meaning | Read by | Notes |
|-------|---------|---------|-------|
| `b`   | Depot start node(s)                        | routing | `rte2loc`, `rteTC` (default route ends) |
| `e`   | Depot end node(s)                          | routing | `rte2loc`, `rteTC` |
| `Kwt` | Weight capacity (ton)                      | transport | shared with routing capacity model |
| `Kcu` | Cube capacity (ft³)                        | transport | shared with routing capacity model |
| `r`   | TL per-mile rate (\$/mi), PPI-adjusted     | transport | |
| `ppi` | TL Producer Price Index at the rate date  | transport | used by `mincharge_tl` PPI-scaling |

# Field-subset reads

- **Routing** (`rteTC`, `rte2loc`) reads `sh.b`, `sh.e`, `tr.b`, `tr.e` only.
- **Transport** reads `sh.{f,q,s,a,v,h,d}` and `tr.{r,Kwt,Kcu,ppi}`.
- **Shared** across both: `tr.Kwt`, `tr.Kcu`, `sh.s`, `sh.d`.

LTL PPI is a separate scalar passed at the call site (LTL and TL are
conceptually different carriers, so LTL PPI is not bundled into `tr`).

# Reserved for v0.2.8+

Capacity/feasibility enforcement (`tr.maxTC`, `Xflg`/`out` returns from `rteTC`)
and time-window fields (`sh.tL`, `sh.tU`, `tr` time windows) are reserved for the
Routing-topic round and are NOT read by any v0.2.7 function. The field contract
is laid out now so that build-out — including future vehicle types as distinct
`tr` instances — stays additive and non-breaking.

Each struct-form overload's docstring lists exactly which `sh`/`tr` fields it
consumes; not every overload reads every field.
"""

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
rate_ltl(0.5, 8.0, 250.0)  # 0.5 ton, 8 lb/ft³, 250 miles → ≈1.9906 \$/ton-mi
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
    rate_ltl(q, sh::Union{NamedTuple,DataFrameRow}; ppi=104.2) -> Float64 or Vector{Float64}

Struct-form overload of [`rate_ltl`](@ref). Unpacks `sh.s, sh.d` and dispatches
to the scalar form `rate_ltl(q, sh.s, sh.d; ppi=ppi)`. `sh` may be a `NamedTuple`
or `DataFrameRow`; `ppi` is the LTL Producer Price Index keyword (default 104.2).
Dispatch is safe because `sh` is typed.
"""
rate_ltl(q, sh::Union{NamedTuple, DataFrames.DataFrameRow}; ppi=104.2) = rate_ltl(q, sh.s, sh.d; ppi=ppi)

"""
    mincharge_tl(; ppi=102.7) -> Float64

Calculate TL minimum charge (independent of distance).

Represents fixed costs of loading/unloading at origin and destination. The constant
45 is an empirically derived value reflecting terminal handling costs that do not vary
with distance, fitted from industry tariff data using methods similar to Kay & Warsing (2009).

# Arguments
- `ppi`: TL Producer Price Index (default: 102.7, 2004 baseline).

# Returns
- Minimum charge in dollars.

# Formula
```
MC_TL = (ppi/102.7) × 45
```

# Example
```julia
mincharge_tl()  # Uses default ppi=102.7 → 45.0
mincharge_tl(; ppi=108.6)  # 2005 rates → 47.6
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.3, Eq (1.7),
  NC State University. Empirical derivation methodology: Kay & Warsing (2009),
  Int. J. Logistics Research and Applications, 12(3):165–193
"""
function mincharge_tl(; ppi=102.7)
    return (ppi / 102.7) * 45
end

"""
    mincharge_tl(tr::Union{NamedTuple,DataFrameRow}) -> Float64

Struct-form overload of [`mincharge_tl`](@ref). Reads `tr.ppi` only and dispatches
to `mincharge_tl(; ppi=tr.ppi)`. Note: `tr.r` is NOT read by this overload (per
MakePlan §4.D1); `tr` may be a `NamedTuple` or `DataFrameRow` with a `ppi` field.
"""
mincharge_tl(tr::Union{NamedTuple, DataFrames.DataFrameRow}) = mincharge_tl(; ppi=tr.ppi)

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
mincharge_ltl(250.0)  # 250 miles → ≈47.10
mincharge_ltl(500.0)  # 500 miles → ≈50.84
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
    charge_tl(q, s, d; r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7) -> Float64

Calculate TL transport charge (combining distance cost and minimum charge).

# Arguments
- `q`: Shipment weight (tons).
- `s`: Shipment density (lb/ft³).
- `d`: Distance (miles).
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
charge_tl(10.0, 8.0, 500.0)  # 10 tons, 8 lb/ft³, 500 mi → 1000
charge_tl(25.0, 8.0, 500.0)  # Cube-limited: needs 3 trucks → 3000
charge_tl(30.0, 8.0, 500.0)  # Cube-limited: needs 3 trucks → 3000
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.1, Eq (1.1-1.2),
  NC State University
"""
function charge_tl(q, s, d; r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7)
    q_max = min(Kwt, s * Kcu / 2000)
    num_trucks = ceil(Int, q / q_max)
    charge_per_truck = max(r * d, mincharge_tl(; ppi=ppi))
    return num_trucks * charge_per_truck
end

"""
    charge_tl(q, sh::Union{NamedTuple,DataFrameRow}, tr) -> Float64

Struct-form overload of [`charge_tl`](@ref). Unpacks `sh.s, sh.d` and
`tr.r, tr.Kwt, tr.Kcu, tr.ppi`, dispatches to
`charge_tl(q, sh.s, sh.d; r=tr.r, Kwt=tr.Kwt, Kcu=tr.Kcu, ppi=tr.ppi)`.
`sh` may be a `NamedTuple` or `DataFrameRow`. Unpacking by field name makes this
overload independent of the scalar positional order.
"""
charge_tl(q, sh::Union{NamedTuple, DataFrames.DataFrameRow}, tr) = charge_tl(q, sh.s, sh.d; r=tr.r, Kwt=tr.Kwt, Kcu=tr.Kcu, ppi=tr.ppi)

"""
    charge_ltl(q, s, d; ppi=104.2) -> Float64

Calculate LTL transport charge (rate × weight × distance, or minimum charge).

# Arguments
- `q`: Shipment weight (tons).
- `s`: Shipment density (lb/ft³).
- `d`: Distance (miles).
- `ppi`: LTL Producer Price Index. Default: 104.2.

# Returns
- Transport charge in dollars.

# Formula
```
c_LTL = max(r_LTL × q × d, MC_LTL)
```

# Example
```julia
charge_ltl(0.5, 8.0, 250.0)  # 0.5 ton, 8 lb/ft³, 250 mi → ≈248.83
charge_ltl(2.0, 10.0, 500.0) # 2 tons, 10 lb/ft³, 500 mi → ≈859.31
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.2 and 1.5.3,
  Eq (1.5) and (1.8), NC State University
"""
function charge_ltl(q, s, d; ppi=104.2)
    r = rate_ltl(q, s, d; ppi=ppi)
    isinf(r) && return Inf
    return max(r * q * d, mincharge_ltl(d; ppi=ppi))
end

"""
    charge_ltl(q, sh::Union{NamedTuple,DataFrameRow}; ppi=104.2) -> Float64

Struct-form overload of [`charge_ltl`](@ref). Unpacks `sh.s, sh.d` and dispatches
to `charge_ltl(q, sh.s, sh.d; ppi=ppi)`. `sh` may be a `NamedTuple` or
`DataFrameRow`; `ppi` is the LTL Producer Price Index keyword (default 104.2).
Unpacking by field name makes this overload independent of the scalar positional
order; dispatch is safe because `sh` is typed.
"""
charge_ltl(q, sh::Union{NamedTuple, DataFrames.DataFrameRow}; ppi=104.2) = charge_ltl(q, sh.s, sh.d; ppi=ppi)

"""
    maxpayld(s; Kwt=25.0, Kcu=2750.0) -> Float64 or Vector{Float64}

Determine maximum payload limited by weight or cube capacity.

# Arguments
- `s`: Shipment density (lb/ft³).
- `Kwt`: Truck weight capacity (tons). Default: 25.0 (matches `charge_tl`).
- `Kcu`: Truck cube capacity (ft³). Default: 2750.0 (matches `charge_tl`).

# Returns
- Maximum payload in tons: min(Kwt, s·Kcu/2000).

# Example
```julia
maxpayld(8.0)   # 8 lb/ft³ → 11.0 tons (cube-limited)
maxpayld(15.0)  # 15 lb/ft³ → 20.6 tons (cube-limited)
maxpayld(25.0)  # 25 lb/ft³ → 25.0 tons (weight-limited)
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.1, Eq (1.2),
  NC State University
"""
function maxpayld(s; Kwt=25.0, Kcu=2750.0)
    return min.(Kwt, s .* Kcu ./ 2000)
end

"""
    maxpayld(sh::Union{NamedTuple,DataFrameRow}, tr) -> Float64 or Vector{Float64}

Struct-form overload of [`maxpayld`](@ref). Unpacks `sh.s, tr.Kwt, tr.Kcu` and
dispatches to `maxpayld(sh.s; Kwt=tr.Kwt, Kcu=tr.Kcu)`. `sh` may be a `NamedTuple`
or `DataFrameRow`.
"""
maxpayld(sh::Union{NamedTuple, DataFrames.DataFrameRow}, tr) = maxpayld(sh.s; Kwt=tr.Kwt, Kcu=tr.Kcu)

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
using DataFrames
products = DataFrame(f=[100, 200], s=[8, 10], v=[1000, 1500], h=[0.25, 0.25], a=[0.5, 0.5])
agg = aggshmt(products)
q, d = 2.0, 300.0
c = charge_ltl(q, agg.s, d)
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

Follows Matlog `aggshmt.m` (Note 3): the aggregate copies the **first** shipment
(`df[1, :]`), then recomputes the aggregable fields — `f` (sum of demand), `s`
(total-weight / total-volume harmonic-style mean), and `v`/`h`/`a`
(demand-weighted arithmetic means). **Every other field — including the
distance `d` and any routing fields — is passed through unchanged from the first
shipment**, because aggregated shipments share one lane (no distance average).
The output is therefore a *complete* `sh` row that chains directly into
`maxpayld`/`minTLC` with no intervening `combine`.

# Arguments
- `df`: DataFrame with columns `:f` (demand), `:s` (density), `:v` (value),
        `:h` (holding rate), `:a` (inventory fraction), and typically `:d`
        (distance). If `:f` missing, uses `:q` as the weight base.

# Returns
- NamedTuple: first-row fields with `f, s, v, h, a` recomputed and `d` (plus any
  other fields) carried through from `df[1, :]`.

# Example
```julia
using DataFrames
df = DataFrame(
    f = [100, 200, 150],
    s = [8, 10, 6],
    v = [1000, 1500, 800],
    h = [0.25, 0.25, 0.25],
    a = [0.5, 0.5, 0.5],
    d = [532, 532, 532]
)
agg = aggshmt(df)
# agg.f = 450, agg.s ≈ 7.66 (total-wt/total-vol), agg.v ≈ 1178 (weighted avg),
# agg.d = 532 (passed through); minTLC(agg, tr) works directly.
```
"""
function aggshmt(df::DataFrame)
    # Weight base: use f if available, otherwise q (Matlog Note 1)
    weight = hasproperty(df, :f) ? df.f : df.q
    total = sum(weight)

    # Start from the first shipment so d and every other field pass through
    # unchanged (Matlog Note 3: aggregated shipments share one lane).
    upd = Dict{Symbol,Any}(:f => total)
    hasproperty(df, :s) && (upd[:s] = total / sum(weight ./ df.s))   # total-wt/total-vol
    hasproperty(df, :v) && (upd[:v] = sum(weight ./ total .* df.v))  # demand-weighted mean
    hasproperty(df, :h) && (upd[:h] = sum(weight ./ total .* df.h))
    hasproperty(df, :a) && (upd[:a] = sum(weight ./ total .* df.a))

    return merge(NamedTuple(df[1, :]), (; upd...))
end

"""
    minTLC(sh, tr=nothing, ppi=nothing) -> NamedTuple

Independent shipment size that minimises total logistics cost (TLC), checking
TL only, LTL only, or both modes depending on which arguments are provided.

# Call modes

- **TL-only** (`minTLC(sh, tr)`): Optimises over TL shipment size using the
  closed-form EOQ expression; `ppi` is `nothing`.
- **LTL-only** (`minTLC(sh, nothing, ppi)`): Optimises over LTL shipment size
  using Optim.jl one-dimensional minimisation; `tr` is `nothing`.
- **Both** (`minTLC(sh, tr, ppi)`): Computes both optimal sizes and returns
  the mode with the lower TLC; `isLTL = true` iff LTL wins.
- **Degenerate** (`minTLC(sh)` — neither provided): Returns
  `(qᵒ=nothing, TLCᵒ=Inf, isLTL=false)`.

# Arguments

- `sh`: Per-shipment parameters; a `NamedTuple` or `DataFrameRow` with fields
  `f` (demand, ton/yr), `s` (density, lb/ft³), `a` (inventory fraction), `v`
  (unit value, \$/ton), `h` (holding rate, 1/yr), `d` (distance, mi).
- `tr`: Carrier `NamedTuple` with fields `r`, `Kwt`, `Kcu`, `ppi` (TL). Pass
  `nothing` for LTL-only mode.
- `ppi`: LTL Producer Price Index scalar. Pass `nothing` for TL-only mode.

# Returns

`NamedTuple` with fields:
- `qᵒ`: Optimal shipment size (ton); `nothing` in the degenerate case.
- `TLCᵒ`: Minimum total logistics cost (\$/yr); `Inf` in the degenerate case.
- `isLTL`: `true` if LTL was chosen, `false` if TL was chosen (or degenerate).

# LTL search bounds

The Optim search for the LTL optimal `q` uses hard-coded bounds:
- Lower: `150/2000` ton (150 lb, the LTL minimum shipment weight).
- Upper: `min(5, 650·sh.s/2000)` ton — the smaller of the LTL weight ceiling
  (5 ton = 10,000 lb) and the density-derived cube-out limit (650 ft³ × density
  converted to tons), following the ISE 754 lecture convention.

# Example

```julia
sh = (f=20.0, s=40/9, a=1.0, v=25_000.0, h=0.30, d=532.0)
tr = (r=2.00*131.0/102.7, Kwt=25.0, Kcu=2750.0, ppi=131.0)
result = minTLC(sh, tr, 177.4)
# result.qᵒ ≈ 1.9024, result.TLCᵒ ≈ 28_536.25, result.isLTL == false
```
"""
function minTLC(sh, tr=nothing, ppi=nothing)
    qᵒ, TLCᵒ, isLTL = nothing, Inf, false
    if tr !== nothing
        qTL = min(sqrt((sh.f * max(tr.r*sh.d, mincharge_tl(tr))) / (sh.a*sh.v*sh.h)),
                  maxpayld(sh, tr))
        TLCtl = totlogcost(qTL, charge_tl(qTL, sh, tr), sh)
        qᵒ, TLCᵒ = qTL, TLCtl
    end
    if ppi !== nothing
        qLTL = optimize(q -> totlogcost(q, charge_ltl(q, sh; ppi=ppi), sh),
                        150/2000, min(5, 650sh.s/2000)).minimizer
        TLCltl = totlogcost(qLTL, charge_ltl(qLTL, sh; ppi=ppi), sh)
        if TLCltl < TLCᵒ
            qᵒ, TLCᵒ, isLTL = qLTL, TLCltl, true
        end
    end
    return (qᵒ = qᵒ, TLCᵒ = TLCᵒ, isLTL = isLTL)
end

"""
    transport_costs(shipments::DataFrame; mode=:auto, kwargs...) -> DataFrame

Calculate transport costs for a collection of shipments, automatically selecting TL vs LTL.

# Arguments
- `shipments`: DataFrame with columns `:q` (weight, tons), `:s` (density, lb/ft³),
  `:d` (distance, miles) — the canonical `sh` field names.
- `mode`: `:auto` (select min cost), `:tl`, or `:ltl`.
- `kwargs`: Additional parameters routed to the relevant charge function. `charge_tl`
  accepts `r`, `Kwt`, `Kcu`; `charge_ltl` accepts no capacity/rate parameters. The TL
  and LTL Producer Price Indices default to their own baselines (`ppi_tl=102.7`,
  `ppi_ltl=104.2`) and are applied separately; override either with `ppi_tl`/`ppi_ltl`,
  or pass a bare `ppi` to override both at once.

# Returns
- DataFrame with original columns plus `:cost` (\$), `:mode` (`:tl` or `:ltl`), `:rate` (\$/ton-mi).

# Example
```julia
using DataFrames
shipments = DataFrame(
    q = [0.5, 2.0, 15.0, 30.0],
    s = [8.0, 10.0, 12.0, 15.0],
    d = [250.0, 500.0, 800.0, 1200.0]
)
results = transport_costs(shipments)
# Automatically selects LTL for small shipments, TL for large
```
"""
function transport_costs(shipments::DataFrame; mode=:auto, kwargs...)
    kw = values(kwargs)
    # TL and LTL Producer Price Indices default to their own baselines (102.7 /
    # 104.2) and are applied separately; a bare `ppi` overrides both explicitly.
    ppi_tl  = haskey(kw, :ppi_tl)  ? kw.ppi_tl  : (haskey(kw, :ppi) ? kw.ppi : 102.7)
    ppi_ltl = haskey(kw, :ppi_ltl) ? kw.ppi_ltl : (haskey(kw, :ppi) ? kw.ppi : 104.2)
    # Route only the parameters each callee accepts: charge_tl takes r/Kwt/Kcu,
    # charge_ltl takes none of them (only ppi).
    tl_kw = NamedTuple(k => kw[k] for k in keys(kw) if k in (:r, :Kwt, :Kcu))

    n = nrow(shipments)
    costs = zeros(n)
    modes = Vector{Symbol}(undef, n)
    rates = zeros(n)

    for i in 1:n
        q, s, d = shipments[i, :q], shipments[i, :s], shipments[i, :d]

        if mode == :auto
            c_tl = charge_tl(q, s, d; ppi=ppi_tl, tl_kw...)
            c_ltl = charge_ltl(q, s, d; ppi=ppi_ltl)
            if c_tl <= c_ltl
                costs[i] = c_tl
                modes[i] = :tl
                rates[i] = c_tl / (q * d)
            else
                costs[i] = c_ltl
                modes[i] = :ltl
                rates[i] = rate_ltl(q, s, d; ppi=ppi_ltl)
            end
        elseif mode == :tl
            costs[i] = charge_tl(q, s, d; ppi=ppi_tl, tl_kw...)
            modes[i] = :tl
            rates[i] = costs[i] / (q * d)
        elseif mode == :ltl
            costs[i] = charge_ltl(q, s, d; ppi=ppi_ltl)
            modes[i] = :ltl
            rates[i] = rate_ltl(q, s, d; ppi=ppi_ltl)
        end
    end

    result = copy(shipments)
    result[!, :cost] = costs
    result[!, :mode] = modes
    result[!, :rate] = rates
    return result
end
