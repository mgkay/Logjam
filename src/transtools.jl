# =============================================================================
# Transportation Economics
# =============================================================================

"""
    Logjam.shtr

The `sh` and `tr` contract: the fields of a shipment `sh` and of a truck `tr`, which the transport and the
routing functions share. The value lists the fields of each, `shtr.sh` and `shtr.tr`; this docstring is the
contract, and `?Logjam.shtr` shows it.

`sh` is one shipment, a `NamedTuple` or a `DataFrameRow`, or a table of shipments, a `DataFrame` with one row for
each shipment; `tr` is one truck, a `NamedTuple` (or a `DataFrameRow`). They are one abstraction across the two
modules: a routing `sh` may carry only `b` and `e`, a transport `sh` the economic fields, and a row with all of
them works in both, because each function reads only its own fields (the cross-regime test `I5`). The fields
both modules read (`Kwt`, `Kcu`, `s`, `d`) are the same quantities in both, so `sh` and `tr` are not renamed by
module.

# Row, column or table

- A function of **one shipment** takes `sh` as a row: `charge_tl(q, sh, tr)`, `charge_ltl(q, sh)`,
  `rate_ltl(q, sh)`, `maxpayld(sh, tr)`, `totlogcost(q, c, sh)` and `minTLC(sh, tr, ppi_ltl)`, each of which
  also takes the fields as scalars. Two of them also take the table, or its column, with one result for each
  row: `maxpayld(sh, tr)`, or `maxpayld(sh.s, tr)` on the densities alone, returns the vector of maximum
  payloads, and `minTLC(sh, tr, ppi_ltl)` returns the table with `qᵒ`, `TLCᵒ` and `isLTL` added.
  `charge_tl(d, tr)` and `mincharge_tl(tr)` take the truck alone.
- A function of **a set of shipments** takes `sh` as the table, one row for each shipment: `aggshmt(sh)`, which
  aggregates the rows into one, and, in routing, `rteTC(rte, sh, C, tr)`, `rte2loc(rte, sh, tr)`,
  `pairwisesavings(h, sh)`, `savings(h, sh)` and `sh2rte(sh, R)`, where a route is a vector of row numbers of
  `sh`.

# Read when present

A field a function reads is used when `sh` or `tr` has it. An absent field takes the default the function
documents, the scalar method's or Matlog's: a `tr` without `Kwt`, `Kcu` or `maxTC` is an uncapacitated truck to
`rteTC`, which then returns the sum of the segment costs, and `charge_tl(d, tr)` derives `r` from `ppi` as the
scalar `charge_tl` does. A field with no default is required, and its absence is an error from the function
that reads it. A field a function does not read is ignored, so one row or table passes through the transport
and the routing calls without projection. Each method's docstring names the fields it reads.

# Fields of `sh`

| Field | Meaning | Read by |
|:--|:--|:--|
| `b`, `e` | begin (pickup) and end (delivery) location index | routing: `rte2loc`, `rteTC` |
| `f` | annual demand (ton/yr) | transport |
| `q` | shipment weight (ton) | `aggshmt` when there is no `f`; `rteTC`, against `Kwt` |
| `s` | density (lb/ft³) | transport; with `q`, `rteTC` against `Kcu` |
| `a` | inventory fraction, origin and destination (`α` in the lectures' prose) | transport |
| `v` | unit value (\\\$/ton) | transport |
| `h` | holding cost rate (1/yr) | transport |
| `d` | distance (mi) | transport |
| `tL`, `tU` | time to load, to unload | `rteTC(...; full = true)` |
| `tbmin`, `tbmax`, `temin`, `temax` | time windows of the pickup and the delivery | `rteTC(...; full = true)` |
| `avh` | demand-weighted mean of `a·v·h`, attached by `aggshmt` | `totlogcost`, `minTLC`, when present |
| `qmax` | maximum payload (ton), the column `maxpayld(sh, tr)` fills | none |
| `qᵒ`, `TLCᵒ`, `isLTL` | minimum-TLC size (ton), its TLC (\\\$/yr), whether LTL is selected, attached by `minTLC` | none |

# Fields of `tr`

| Field | Meaning | Read by |
|:--|:--|:--|
| `b`, `e` | depot begin and end location (default route ends) | routing: `rte2loc`, `rteTC` |
| `Kwt` | weight capacity (ton) | `maxpayld`, `charge_tl(q, sh, tr)`; `rteTC` checks each load mix |
| `Kcu` | cube capacity (ft³) | `maxpayld`, `charge_tl(q, sh, tr)`; `rteTC` checks each load mix |
| `maxTC` | maximum cost of a route | `rteTC`, which returns `Inf` for a dearer route |
| `r` | TL rate per loaded mile (\\\$/mi), at the index `ppi` | transport |
| `ppi` | TL Producer Price Index at the rate's date | `mincharge_tl(tr)` and the functions that call it |
| `tbmin`, `tbmax`, `temin`, `temax` | time windows at the depot | `rteTC(...; full = true)` |

The LTL index is a separate scalar at the call site (`ppi_ltl`, or `ppi =` in `charge_ltl`), since LTL and TL
are different carriers.

# Example

The fields of a truck, and one truck used by both modules: Lecture 3.3's carrier, priced over 532 mi by the
transport functions and given a weight capacity that `rteTC` would check:

```jldoctest
tr = (r = 2.00*131.0/102.7, Kwt = 25, Kcu = 2750, ppi = 131.0)
(Logjam.shtr.tr, round(charge_tl(532, tr); digits = 2), maxpayld((s = 40/9,), tr))

# output

((:b, :e, :Kwt, :Kcu, :maxTC, :r, :ppi, :tbmin, :tbmax, :temin, :temax), 1357.2, 6.111111111111112)
```
"""
const shtr = (sh = (:b, :e, :f, :q, :s, :a, :v, :h, :d, :tL, :tU, :tbmin, :tbmax, :temin, :temax, :avh,
                    :qmax, :qᵒ, :TLCᵒ, :isLTL),
              tr = (:b, :e, :Kwt, :Kcu, :maxTC, :r, :ppi, :tbmin, :tbmax, :temin, :temax))

# =============================================================================
# Rate Estimation
# =============================================================================

# B10: the domain of the LTL estimate (Kay & Warsing 2009; Freight Transport, Sec. 1.5.2), named once. `rate_ltl`
# clamps a weight and a distance up to the minimums and is Inf beyond the maximums or the cube; `qmax_ltl` is the
# smaller of the weight and cube bounds at a density; `mincharge_ltl` is undefined beyond the distance; `minTLC`
# searches LTL sizes from the minimum weight to `qmax_ltl`. Each keeps its literal's value and type (5.0 is a
# Float64, as `qmax_ltl` returned it; 37, 650 and 3354 are integers), so no result moves.
const _LTL_MIN_WEIGHT = 150/2000    # ton (150 lb)
const _LTL_MAX_WEIGHT = 5.0         # ton (10,000 lb)
const _LTL_MAX_CUBE = 650           # ft³, the cube-out limit
const _LTL_MIN_DIST = 37            # mi
const _LTL_MAX_DIST = 3354          # mi

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
- Rate in \\\$/ton-mile. Returns `Inf` if q > 5, d > 3354, or 2000q/s > 650.

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
    q_safe = max.(q, _LTL_MIN_WEIGHT)
    d_safe = max.(d, _LTL_MIN_DIST)

    # Formula: r_LTL = ppi × [(s²/8 + 14) / ((q^1/7 × d^15/29 - 7/2)(s² + 2s + 14))]
    numerator = ppi .* (s.^2 ./ 8 .+ 14)
    denominator = (q_safe.^(1/7) .* d_safe.^(15/29) .- 7/2) .* (s.^2 .+ 2 .* s .+ 14)

    rate = numerator ./ denominator

    # Mark out-of-bounds as Inf
    invalid = (denominator .< eps()) .| (q .> _LTL_MAX_WEIGHT) .| (d .> _LTL_MAX_DIST) .| (2000 .* q ./ s .> _LTL_MAX_CUBE)
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
    qmax_ltl(s) -> Float64 or Vector{Float64}

Largest shipment (tons) for which the LTL rate estimate is defined at density `s` (lb/ft³):
`min(5, 650·s/2000)`, the smaller of the 5-ton (10,000 lb) weight ceiling and the 650 ft³
cube-out limit ([`rate_ltl`](@ref) is `Inf` above either). It is the upper end of the search
[`minTLC`](@ref) makes over LTL shipment sizes, and the bound a lecture that searches over
LTL sizes has to respect.

# Example
Lecture 3.2, Example 1(e): the 40 lb, 9 ft³ product has a cube bound of 1.44 ton, and a
dense product (40 lb/ft³) is held to the 5-ton ceiling:

```jldoctest
(round(qmax_ltl(40/9); digits = 2), qmax_ltl(40.0))

# output

(1.44, 5.0)
```
"""
qmax_ltl(s) = min.(_LTL_MAX_WEIGHT, _LTL_MAX_CUBE .* s ./ 2000)

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
    d > _LTL_MAX_DIST && error("LTL minimum charge not defined for d > $(_LTL_MAX_DIST) miles")
    d <= 0 && return 0.0
    return (ppi / 104.2) * (45 + d^(28/19) / 1625)
end

# TRN3, TRN4: Matlog's zero tolerance, `tol0 = 1e-4` in `transcharge.m` and `mincharge.m`, tested as `is0`
# does, `abs(x) < tol0` (strict), in the variable's own unit (ton, mile). A shipment weight within it of zero is
# charged nothing (`transcharge`, on `q`); a distance within it of zero carries no minimum charge (`mincharge`,
# on `d`, TL and LTL), so the charge there is the loaded-mile part alone. The one tolerance of `charge_tl`,
# `charge_ltl` and `minTLC`.
const _TOL0 = 1e-4
_is0(x) = abs(x) < _TOL0

"""
    charge_tl(q, s, d; r=nothing, Kwt=25.0, Kcu=2750.0, ppi=102.7) -> Float64

Calculate TL transport charge (combining distance cost and minimum charge).

# Arguments
- `q`: Shipment weight (tons).
- `s`: Shipment density (lb/ft³).
- `d`: Distance (miles).
- `r`: TL rate per loaded truck-mile (\\\$/mi). When it is not passed it is derived
  from `ppi` as `2.00 * ppi / 102.7` (the \\\$2.00 of the 102.7 baseline, escalated
  with the index; 2.00 at the default `ppi`). A `r` that is passed is used as it is
  and never escalated again, so a caller that has already escalated it, as every
  lecture does (`r = 2.00*ppi/102.7`), gets that rate (D5).
- `Kwt`: Truck weight capacity (tons). Default: 25.0.
- `Kcu`: Truck effective cube capacity (ft³). Default: 2750.0.
- `ppi`: TL Producer Price Index. Default: 102.7.

# Returns
- Transport charge in dollars.

# Formula
```
c_TL = max(⌈q/q_max⌉ × r × d, MC_TL)
where q_max = min(Kwt, s × Kcu / 2000)
```

The TL minimum charge applies once to the shipment, not once to each truck: the
chapter defines the independent charge as `max{c_TL, MC_TL}` (N3). The charge is 0
when `q = 0` (no truck is sent) or `d = 0` (the product is already there), as the
chapter and Matlog's `transcharge` have it (N4, CR 15; ruling Q3, 2026-10-04).

**Zero tolerance (TRN3).** As in Matlog's `transcharge` and `mincharge`, a weight of less
than `1e-4` ton is charged nothing, and a distance of less than `1e-4` mi carries no
minimum charge, so the charge there is `⌈q/q_max⌉ × r × d` alone: a supplier that an
optimizer has placed `9e-9` mi from the facility costs about `2e-8` dollars a truck, not
the minimum charge. At exactly `1e-4` the minimum applies.

# Example
Lecture 3.2, Example 1(c): the 6-ton shipment (300 cartons of 40 lb, 9 ft³) from
Raleigh to Gainesville, 532 mi, at the January 2018 TL index of 131.0:

```jldoctest
round(charge_tl(6.0, 40/9, 532; r = 2.00*131.0/102.7, ppi = 131.0); digits = 2)

# output

1357.2
```

The same charge from the index alone: with no `r` the rate is `2.00 * ppi / 102.7`,
Lecture 3.2's `rTL = 2.00ppiTL/102.7`; a rate that is passed is used as it is:

```jldoctest
c = charge_tl(6.0, 40/9, 532; ppi = 131.0)
(round(c; digits = 2), c == charge_tl(6.0, 40/9, 532; r = 2.00*131.0/102.7, ppi = 131.0),
 charge_tl(6.0, 40/9, 532; r = 3.0, ppi = 131.0))

# output

(1357.2, true, 1596.0)
```

Cube-limited loads need more trucks (Lecture 3.2: `q_max` = 11 ton at 8 lb/ft³, so
30 ton is 3 trucks):

```jldoctest
(charge_tl(10.0, 8.0, 500.0), charge_tl(30.0, 8.0, 500.0))

# output

(1000.0, 3000.0)
```

Two trucks over 10 mi cost one minimum charge (45), not two, as in the chapter's
`max{c_TL, MC_TL}` (Freight Transport, the independent charge; Matlog `transcharge`):

```jldoctest
charge_tl(30.0, 30.0, 10.0)

# output

45.0
```

Matlog's zero tolerance (`transcharge` and `mincharge`, `tol0 = 1e-4`): a facility `9e-9` mi
from its supplier pays no minimum charge, a shipment of `9e-5` ton is charged nothing, and
`2e-4` mi is a distance that pays the minimum:

```jldoctest
(charge_tl(10.0, 8.0, 9e-9) < 1e-6, charge_tl(9e-5, 8.0, 500.0), charge_tl(10.0, 8.0, 2e-4))

# output

(true, 0.0, 45.0)
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.1, Eq (1.1-1.2),
  NC State University
"""
function charge_tl(q, s, d; r=nothing, Kwt=25.0, Kcu=2750.0, ppi=102.7)
    # nothing to ship (within 1e-4 ton, TRN3), or nowhere to ship it (N4, CR 15)
    (_is0(q) || d == 0) && return 0.0
    rate = _tlrate(r, ppi)                            # derived from ppi only when r is not passed (D5)
    q_max = min(Kwt, s * Kcu / 2000)
    num_trucks = ceil(Int, q / q_max)
    mc = _is0(d) ? 0.0 : mincharge_tl(; ppi=ppi)      # no minimum within 1e-4 mi (TRN3, Matlog's mincharge)
    return max(num_trucks * (rate * d), mc)           # one minimum per shipment (N3)
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

# the TL rate per loaded mile: `r` as given, or, when it is not, the $2.00 of the 102.7 baseline escalated with the
# index (D5); one expression for both `charge_tl` methods that derive it
_tlrate(r, ppi) = r === nothing ? 2.00 * ppi / 102.7 : r

"""
    charge_tl(d::Real, tr) -> Float64

The charge for one truckload over `d` miles, `max(r·d, MC_TL)`: the loaded miles at the truck's rate, or the TL
minimum charge if that is more (B9). It is the charge of a single truck, whatever it carries, which is what a
route's charge is in Lecture 5.2 (`max(2.00 d, MC_TL)` over the route's miles) and what `minTLC`'s TL branch
charges a shipment of at most one truckload. Reads `tr.r` and `tr.ppi`; when `tr` has no `r` (or `r = nothing`),
the rate is derived from `tr.ppi` as `2.00 * ppi / 102.7`, as in the shipment form below (D5). The minimum is
[`mincharge_tl`](@ref)`(tr)`, so `tr.ppi` is required.

The shipment form `charge_tl(q, s, d; ...)` on the same truck is the same charge whenever its `q`, at least
`1e-4` ton, fills at most one truck and `d` is at least `1e-4` mi. This form has no zero rule, so at `d = 0` it is
the minimum charge, as `max(r·d, MC_TL)` is, where the shipment form charges nothing (N4, TRN3).

# Example
Lecture 5.2, Ex. 9: at the base index, \\\$2.00 per loaded mile with the minimum charge of \\\$45, a truck sent
100 mi and one sent 10 mi; the same truck with its rate derived from the index:

```jldoctest
tr = (r = 2.00, ppi = 102.7)
(charge_tl(100.0, tr), charge_tl(10.0, tr), charge_tl(100.0, (ppi = 102.7,)))

# output

(200.0, 45.0, 200.0)
```

Lecture 3.3's truck from Raleigh to Gainesville, 532 mi at the January 2018 TL index of 131.0, is the charge of
a full truckload (Lecture 4.3's `cTL`, the shipment form at `q = qmax`):

```jldoctest
tr = (r = 2.00*131.0/102.7, Kwt = 25, Kcu = 2750, ppi = 131.0)
c = charge_tl(532, tr)
(round(c; digits = 2), c == charge_tl(maxpayld(40/9; Kwt = 25, Kcu = 2750), 40/9, 532; r = tr.r, ppi = 131.0))

# output

(1357.2, true)
```
"""
charge_tl(d::Real, tr) = max(_tlrate(hasproperty(tr, :r) ? tr.r : nothing, tr.ppi) * d, mincharge_tl(tr))

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

The charge is 0 when `q = 0` or `d = 0` (the chapter's `MC_LTL = 0` for `q = 0`; Matlog's
`transcharge`), where v0.2.8 charged the minimum for a zero-weight shipment (N4). Matlog's zero
tolerance applies as in [`charge_tl`](@ref) (TRN4): a weight of less than `1e-4` ton is charged
nothing, and a distance of less than `1e-4` mi carries no minimum charge, so the charge there is
`r_LTL × q × d` alone.

# Example
Lecture 3.2, Example 1(d): 15 cartons of 40 lb, 9 ft³ from Raleigh to Gainesville, 532 mi,
at the January 2018 LTL index of 177.4:

```jldoctest
round(charge_ltl(15 * 40/2000, 40/9, 532; ppi = 177.4); digits = 2)

# output

602.81
```

Nothing shipped costs nothing, as in Matlog's `transcharge`:

```jldoctest
charge_ltl(0.0, 10.0, 500.0)

# output

0.0
```

# References
- M.G. Kay (2023), Freight Transport (course notes), Section 1.5.2 and 1.5.3,
  Eq (1.5) and (1.8), NC State University
"""
function charge_ltl(q, s, d; ppi=104.2)
    # nothing to ship (within 1e-4 ton, TRN4), or nowhere to ship it (N4, CR 15)
    (_is0(q) || d == 0) && return 0.0
    r = rate_ltl(q, s, d; ppi=ppi)
    isinf(r) && return Inf
    return max(r * q * d, _is0(d) ? 0.0 : mincharge_ltl(d; ppi=ppi))   # no minimum within 1e-4 mi (TRN4)
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

"""
    maxpayld(s::Real, tr) -> Float64
    maxpayld(s::AbstractVector, tr) -> Vector
    maxpayld(sh::AbstractDataFrame, tr) -> Vector

The maximum payload on the truck `tr` of one density `s` (lb/ft³), `maxpayld(s; Kwt = tr.Kwt, Kcu = tr.Kcu)`, so
the scalar, vector and table forms all take the truck (D7, TRN2). And of each shipment, from a vector of densities `s`
or from the table `sh`, whose column `s` it reads (B6): element `i` is `maxpayld(s[i]; Kwt = tr.Kwt, Kcu = tr.Kcu)`, so the
table form equals `[maxpayld(row, tr) for row in eachrow(sh)]`, the row form applied to each row. Reads `tr.Kwt`
and `tr.Kcu`, both required, as the row form does. Each element is the scalar rule computed on its own density,
so a range of densities gives the scalar rule's value at each one (the keyword form `maxpayld(s; Kwt, Kcu)` on a
range does the range's own arithmetic, which can differ in the last place).

# Example
Lecture 3.4, Ex. 1 (Code block 2): the two suppliers' products and the aggregate shipped to the three
customers, on a truck of 25 ton and 2,750 ft³:

```jldoctest
using DataFrames
tr = (r = 2, Kwt = 25, Kcu = 2750)
shS = DataFrame(f = [100, 380], s = [30, 120] ./ [10, 4])
sh = vcat(shS, DataFrame(f = sum(shS.f)*[20, 30, 50]/100, s = sum(shS.f)./sum(shS.f./shS.s)))
sh.qmax = maxpayld(sh, tr)
(round.(sh.qmax; digits = 4), sh.qmax == [maxpayld(row, tr) for row in eachrow(sh)])

# output

([4.125, 25.0, 14.3478, 14.3478, 14.3478], true)
```

On densities alone, the cube limits a truck below 18.18 lb/ft³ and the weight above it:

```jldoctest
maxpayld([8.0, 15.0, 25.0], (Kwt = 25, Kcu = 2750))

# output

3-element Vector{Float64}:
 11.0
 20.625
 25.0
```

One density on the truck, as Lecture 3.4's Code block 29 computes the payload of its average class-100
product, 10 lb/ft³, there written `maxpayld(s3; Kwt = tr3.Kwt, Kcu = tr3.Kcu)`:

```jldoctest
maxpayld(10, (Kwt = 25, Kcu = 2750))

# output

13.75
```
"""
maxpayld(s::Real, tr) = maxpayld(s; Kwt = tr.Kwt, Kcu = tr.Kcu)
function maxpayld(s::AbstractVector, tr)
    Kwt, Kcu = tr.Kwt, tr.Kcu
    return [maxpayld(x; Kwt = Kwt, Kcu = Kcu) for x in s]   # the scalar rule at each density: a range broadcast as a range differs in the last place
end
maxpayld(sh::AbstractDataFrame, tr) = maxpayld(sh.s, tr)

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
- `c`: Transport charge per shipment (\\\$).
- `f`: Annual demand (tons/year).
- `a`: Inventory fraction (0-D correction, typically 0.5).
- `v`: Product value (\\\$/ton).
- `h`: Annual holding cost rate (fraction, e.g., 0.25 = 25%/year).
- `params`: Any object with fields `.f`, `.a`, `.v`, `.h` (e.g., NamedTuple
  from [`aggshmt`](@ref) or a DataFrameRow). When it also has a field `avh`
  (as an [`aggshmt`](@ref) result does), the inventory term is `q·avh`, the
  aggregate's own demand-weighted `a·v·h`, instead of `q·a·v·h` from the
  separately averaged `a`, `v` and `h`; the two differ when `h`, `a` and `v`
  are not alike across the aggregated shipments (CR 14).

# Returns
- Total logistics cost (\\\$/year).

# Edge cases
- `q = 0` (or less) with a positive charge `c` and demand `f` returns `Inf`: a shipment of
  no size cannot carry the demand (v0.2.8 returned 4.5e19, `c·f` over `eps()`; N31). With
  `c = 0` (a shipment that costs nothing, as at `d = 0`) or `f = 0` the transport term is 0.

# Example
Lecture 3.3, Example 2 (Code block 16): 200 ton/yr of a \\\$5,000/ton material,
shipped 750 mi in full 15-ton truckloads at \\\$2.00 per loaded mile, carried at
`h = 0.11 + 0.3/1.5`, with constant production and use (`a = 1`):

```jldoctest
qmax = maxpayld(10; Kwt = 24, Kcu = 3000)
c = charge_tl(qmax, 10, 750; r = 2, Kwt = 24, Kcu = 3000)
round(totlogcost(qmax, c, 200, 1, 5000, 0.11 + 0.3/1.5); digits = 2)

# output

43250.0
```

An aggregate of products with different carrying rates, valued by its own `avh`
(ISE 453 S20 ICA 7-8, the case recorded in change request CR 14: 150 ton/yr at
\\\$90,000 and `h` = 0.30, 30 ton/yr at \\\$25,000 and `h` = 0.23, `a` = 1; a 2-ton
shipment with no transport charge costs 2 × 23,458.33):

```jldoctest
using DataFrames
agg = aggshmt(DataFrame(f = [150, 30], a = 1, v = [90_000, 25_000], h = [0.30, 0.23]))
round(totlogcost(2.0, 0.0, agg); digits = 2)

# output

46916.67
```
"""
function totlogcost(q, c, f, a, v, h)
    IC = max.(q, 0) .* a .* v .* h
    return _transportcost(q, c, f) .+ IC
end

# CR 14: an aggregate carries its own inventory coefficient `avh`; a missing `avh` (a column
# filled by `vcat(...; cols = :union)`) falls back to a·v·h. B10: the row's own `avh` is `_avh`'s; without one the
# six-argument form multiplies q·a·v·h left to right, as it always has, rather than q·(a·v·h), which `_avh`'s
# product would give and which can differ in the last place
function totlogcost(q, c, p)
    _hasavh(p) && return _transportcost(q, c, p.f) .+ max.(q, 0) .* _avh(p)
    return totlogcost(q, c, p.f, p.a, p.v, p.h)
end

# the annual transport cost c·f/q: 0 when c is 0 or f is 0 (nothing is paid), Inf for a positive charge
# with a shipment size of 0 or less (N31; v0.2.8 divided by max(q, eps()) and returned 4.5e18). Works
# for scalars and arrays.
_transportcost(q, c, f) =
    ifelse.((abs.(c) .< eps()) .| iszero.(c .* f), 0.0, ifelse.(q .<= 0, Inf, c .* f ./ q))

# the inventory coefficient of a shipment row: a·v·h, or the aggregate's own `avh` when the row has one that is not
# missing (CR 14)
_hasavh(p) = hasproperty(p, :avh) && !ismissing(getproperty(p, :avh))
_avh(p) = _hasavh(p) ? getproperty(p, :avh) : p.a * p.v * p.h

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

The result also carries `avh`, the aggregate's inventory coefficient
`Σ fᵢ aᵢ vᵢ hᵢ / Σ fᵢ` (the demand-weighted mean of each product's own `a·v·h`), always
present when the table has `a`, `v` and `h` (CR 14). [`totlogcost`](@ref) and
[`minTLC`](@ref) use it in place of the product of the separately averaged `a`, `v` and
`h`, which is wrong when those differ across the products (Matlog's `aggshmt` and the ISE 453
sheets average them separately; this is a recorded departure). When `h` and `a` are alike
across the shipments, or `v` is, the two agree. `avh` is computed from the rows
aggregated: a hand-edited `a`, `v` or `h` in the result (`merge(agg, (v = ...))`) does not
update it, so pass a new `avh` as well, or drop the field with `Base.structdiff(agg, (avh = 0,))`.
Selecting columns by name with `names(other_table)` or combining with a table that has no
`avh` column drops or rejects it: see `NEWS.md` (v0.3.0, CR 14).

# Arguments
- `df`: DataFrame with columns `:f` (demand), `:s` (density), `:v` (value),
        `:h` (holding rate), `:a` (inventory fraction), and typically `:d`
        (distance). If `:f` is missing, `:q` is the weight base: the total is
        written back to `q`, and no `f` is added (Matlog's `aggshmt.m`, Note 1; N2).

# Returns
- NamedTuple: first-row fields with the weight base (`f`, or `q`), `s, v, h, a`
  recomputed, `avh` added, and `d` (plus any other fields) carried through from
  `df[1, :]`.

# Example
Lecture 3.3, Example 1(m): the two products of Examples 1(a) and 1(l), shipped
together from Raleigh to Gainesville (Code block 14):

```jldoctest
using DataFrames
sh = DataFrame(f = [20, 80], s = [40/9, 32.16], a = 1, v = [25000, 5000], h = 0.3, d = 532)
agg = aggshmt(sh)
(agg.f, round(agg.s; digits = 2), round(agg.v; digits = 2), agg.d)

# output

(100, 14.31, 9000.0, 532)
```

The inventory coefficient of products with different carrying rates is the
demand-weighted mean of their own `a·v·h`, not the product of the separate means
(ISE 453 S20 ICA 7-8, recorded in change request CR 14: 150 ton/yr at \\\$90,000 and
`h` = 0.30, 30 ton/yr at \\\$25,000 and `h` = 0.23, `a` = 1):

```jldoctest
using DataFrames
agg = aggshmt(DataFrame(f = [150, 30], a = 1, v = [90_000, 25_000], h = [0.30, 0.23]))
(round(agg.avh; digits = 2), round(agg.a * agg.v * agg.h; digits = 2))

# output

(23458.33, 22826.39)
```

With shipment sizes `q` and no demand `f`, the sizes are summed into `q` (the Matlog
`aggshmt` example used for the `N2_agg_q` oracle in `test/oracles/transport_edge.csv`):

```jldoctest
using DataFrames
df = DataFrame(q = [10.0, 20.0, 15.0], s = [8.0, 10.0, 6.0], v = [1000.0, 1500.0, 800.0],
               h = [0.25, 0.25, 0.25], a = [0.5, 0.5, 0.5])
agg = aggshmt(df)
(agg.q, hasproperty(agg, :f))

# output

(45.0, false)
```
"""
function aggshmt(df::DataFrame)
    # Weight base: f if available, otherwise q (Matlog Note 1); the total goes back into it (N2)
    wcol = hasproperty(df, :f) ? :f : :q
    weight = df[!, wcol]
    total = sum(weight)

    # Start from the first shipment so d and every other field pass through
    # unchanged (Matlog Note 3: aggregated shipments share one lane).
    upd = Dict{Symbol,Any}(wcol => total)
    hasproperty(df, :s) && (upd[:s] = total / sum(weight ./ df.s))   # total-wt/total-vol
    hasproperty(df, :v) && (upd[:v] = sum(weight ./ total .* df.v))  # demand-weighted mean
    hasproperty(df, :h) && (upd[:h] = sum(weight ./ total .* df.h))
    hasproperty(df, :a) && (upd[:a] = sum(weight ./ total .* df.a))
    # CR 14: the aggregate's own inventory coefficient, the demand-weighted mean of each product's a·v·h
    if hasproperty(df, :a) && hasproperty(df, :v) && hasproperty(df, :h)
        upd[:avh] = sum(weight ./ total .* (df.a .* df.v .* df.h))
    end

    return merge(NamedTuple(df[1, :]), (; upd...))
end

"""
    minTLC(sh; tr = nothing, ppi_ltl = nothing) -> NamedTuple
    minTLC(sh, tr, ppi_ltl) -> NamedTuple

Independent shipment size that minimises total logistics cost (TLC), checking
TL only, LTL only, or both modes depending on which arguments are provided. The
carrier and the LTL index are given by keyword (`tr`, `ppi_ltl`) or positionally, as in
`minTLC(sh, tr, ppi_ltl)`.

**The positional form is kept and unchanged** (about 40 course calls write it; this note is
its whole deprecation): its third argument is the *LTL* PPI, while `tr.ppi` is the TL PPI, and
the keyword form says which is which. Giving the same argument both ways is an `ArgumentError`.

# Call modes

- **TL-only** (`minTLC(sh, tr)` or `minTLC(sh; tr)`): Optimises over TL shipment size
  using the closed-form EOQ expression; no LTL index.
- **LTL-only** (`minTLC(sh, nothing, ppi)` or `minTLC(sh; ppi_ltl)`): Optimises over LTL
  shipment size using Optim.jl one-dimensional minimisation; no carrier.
- **Both** (`minTLC(sh, tr, ppi)` or `minTLC(sh; tr, ppi_ltl)`): Computes both optimal
  sizes and returns the mode with the lower TLC; `isLTL = true` iff LTL is selected.
- **Degenerate** (`minTLC(sh)` — neither provided): Returns
  `(qᵒ=nothing, TLCᵒ=Inf, isLTL=false)`.
- **Zero distance** (`sh.d` within `1e-4` mi of 0, Matlog's zero tolerance, with `tr` or
  `ppi` given): nothing is shipped, so the result is `(qᵒ=0.0, TLCᵒ=0.0, isLTL=false)` in
  every call mode (CR 15, TRN3; v0.2.8 sized the shipment by the TL minimum charge, and
  before TRN3 a distance such as the `9e-9` mi an optimizer leaves between a facility and
  its supplier was sized by it too).

# Arguments

- `sh`: Per-shipment parameters; a `NamedTuple` or `DataFrameRow` with fields
  `f` (demand, ton/yr), `s` (density, lb/ft³), `a` (inventory fraction), `v`
  (unit value, \\\$/ton), `h` (holding rate, 1/yr), `d` (distance, mi). A row with
  an `avh` field (an [`aggshmt`](@ref) result) is sized and costed with `avh` in place
  of `a·v·h` (CR 14).
- `tr`: Carrier `NamedTuple` with fields `r`, `Kwt`, `Kcu`, `ppi` (TL). Pass
  `nothing` (or leave out) for LTL-only mode.
- `ppi_ltl`: LTL Producer Price Index scalar (the third positional argument).
  Pass `nothing` (or leave out) for TL-only mode.

# Returns

`NamedTuple` with fields:
- `qᵒ`: Optimal shipment size (ton); `nothing` in the degenerate case.
- `TLCᵒ`: Minimum total logistics cost (\\\$/yr); `Inf` in the degenerate case.
- `isLTL`: `true` if LTL is selected, `false` if TL is selected (or degenerate).

# LTL search bounds

The Optim search for the LTL optimal `q` uses hard-coded bounds:
- Lower: `150/2000` ton (150 lb, the LTL minimum shipment weight).
- Upper: [`qmax_ltl`](@ref)`(sh.s)` = `min(5, 650·sh.s/2000)` ton — the smaller of the LTL
  weight ceiling (5 ton = 10,000 lb) and the density-derived cube-out limit (650 ft³ ×
  density converted to tons), following the ISE 754 lecture convention.

**Bracket guard.** For a density below `150/650` ≈ 0.231 lb/ft³ the upper bound
is below the lower one: no LTL shipment is possible, and the LTL option is left out as if
`ppi_ltl` were not given (Matlog does the same), where v0.2.8 stopped with an error from
the optimizer.

# Beyond the LTL estimate's range

`rate_ltl` is `Inf` beyond 3,354 mi, so no LTL size has a finite cost there and **no LTL option
exists: the call does not warn or throw**. LTL-only returns `(qᵒ=nothing, TLCᵒ=Inf, isLTL=false)`
and the both-modes call returns the TL result. Check `sh.d <= 3354` first where it matters.

# Example
Lecture 3.3, Example 1 (Code block 12): 20 ton/yr of a \\\$25,000/ton, 40 lb, 9 ft³ product
shipped 532 mi from Raleigh to Gainesville at the January 2018 PPIs (TL 131.0, LTL 177.4);
TL is selected. At \\\$85,000/ton (Example 1(k)) LTL is selected.

```jldoctest
sh = (f=20.0, s=40/9, a=1.0, v=25_000.0, h=0.30, d=532.0)
tr = (r=2.00*131.0/102.7, Kwt=25.0, Kcu=2750.0, ppi=131.0)
result = minTLC(sh, tr, 177.4)
(round(result.qᵒ; digits = 4), round(result.TLCᵒ; digits = 2), result.isLTL)

# output

(1.9024, 28536.25, false)
```

The keyword form is the same call:

```jldoctest
sh = (f=20.0, s=40/9, a=1.0, v=85_000.0, h=0.30, d=532.0)
tr = (r=2.00*131.0/102.7, Kwt=25.0, Kcu=2750.0, ppi=131.0)
result = minTLC(sh; tr = tr, ppi_ltl = 177.4)
(result == minTLC(sh, tr, 177.4), round(result.qᵒ; digits = 4), round(result.TLCᵒ; digits = 2), result.isLTL)

# output

(true, 0.2735, 47801.01, true)
```

Beyond 3,354 mi there is no LTL option (the estimate's range, Kay & Warsing 2009):

```jldoctest
sh = (f=20.0, s=40/9, a=1.0, v=25_000.0, h=0.30, d=4000.0)
minTLC(sh; ppi_ltl = 177.4)

# output

(qᵒ = nothing, TLCᵒ = Inf, isLTL = false)
```
"""
function minTLC(sh, tr_pos=nothing, ppi_pos=nothing; tr=nothing, ppi_ltl=nothing)
    tr, ppi = _mintlc_modes(tr_pos, ppi_pos, tr, ppi_ltl)
    qᵒ, TLCᵒ, isLTL = nothing, Inf, false
    # CR 15, TRN3: a shipment over zero distance (within 1e-4 mi) costs nothing, so it is sized 0 and its TLC is 0
    (tr !== nothing || ppi !== nothing) && _is0(sh.d) && return (qᵒ = 0.0, TLCᵒ = 0.0, isLTL = false)
    if tr !== nothing
        qTL = min(sqrt((sh.f * max(tr.r*sh.d, mincharge_tl(tr))) / _avh(sh)),   # a·v·h, or an aggregate's avh (CR 14)
                  maxpayld(sh, tr))
        TLCtl = totlogcost(qTL, charge_tl(qTL, sh, tr), sh)
        qᵒ, TLCᵒ = qTL, TLCtl
    end
    if ppi !== nothing && _LTL_MIN_WEIGHT < qmax_ltl(sh.s)      # bracket guard: below 0.231 lb/ft³ there is no LTL size
        qLTL = optimize(q -> totlogcost(q, charge_ltl(q, sh; ppi=ppi), sh),
                        _LTL_MIN_WEIGHT, qmax_ltl(sh.s)).minimizer
        TLCltl = totlogcost(qLTL, charge_ltl(qLTL, sh; ppi=ppi), sh)
        if TLCltl < TLCᵒ
            qᵒ, TLCᵒ, isLTL = qLTL, TLCltl, true
        end
    end
    return (qᵒ = qᵒ, TLCᵒ = TLCᵒ, isLTL = isLTL)
end

# the carrier and the LTL index of a minTLC call, given positionally or by keyword but not both (S6)
function _mintlc_modes(tr_pos, ppi_pos, tr, ppi_ltl)
    (tr_pos !== nothing && tr !== nothing) &&
        throw(ArgumentError("minTLC: the carrier is given both positionally and as `tr =`"))
    (ppi_pos !== nothing && ppi_ltl !== nothing) &&
        throw(ArgumentError("minTLC: the LTL PPI is given both positionally and as `ppi_ltl =`"))
    return (tr === nothing ? tr_pos : tr), (ppi_ltl === nothing ? ppi_pos : ppi_ltl)
end

"""
    minTLC(sh::AbstractDataFrame, tr, ppi_ltl) -> DataFrame
    minTLC(sh::AbstractDataFrame; tr = nothing, ppi_ltl = nothing) -> DataFrame

The minimum-TLC shipment of every row of the table `sh` (B6): a new table, `sh`'s columns unchanged and in their
order, with the columns `qᵒ`, `TLCᵒ` and `isLTL` added, each row's values those of the row form
`minTLC(row, tr, ppi_ltl)` above. It is what a lecture writes as
`transform!(sh, AsTable(:) => ByRow(row -> minTLC(row, tr, ppi_ltl)) => AsTable)`, with `sh` itself left as it
was. The call modes are the row form's (TL only, LTL only, both; positional or keyword), and each row reads the
fields the row form reads. A `qᵒ`, `TLCᵒ` or `isLTL` column already in `sh`, from an earlier call, is replaced
in its place, as `transform!` replaces it.

# Example
Lecture 3.3, Ex. 1(l) (Code block 13): the \\\$85,000 product of Ex. 1(k) and a second product, 80 ton/yr of
Class 60 material (32.16 lb/ft³) worth \\\$5,000/ton, both shipped 532 mi at the January 2018 PPIs; the first is
selected LTL, the second TL:

```jldoctest
using DataFrames
tr = (r = 2.00*131.0/102.7, Kwt = 25, Kcu = 2750, ppi = 131.0)
sh = DataFrame(f = [20, 80], s = [40/9, 32.16], a = 1, v = [85_000, 5000], h = 0.3, d = 532)
res = minTLC(sh, tr, 177.4)
(names(res), round.(res.qᵒ; digits = 4), round.(res.TLCᵒ; digits = 2), res.isLTL)

# output

(["f", "s", "a", "v", "h", "d", "qᵒ", "TLCᵒ", "isLTL"], [0.2735, 8.5079], [47801.01, 25523.6], Bool[1, 0])
```
"""
function minTLC(sh::AbstractDataFrame, tr_pos = nothing, ppi_pos = nothing; tr = nothing, ppi_ltl = nothing)
    tr, ppi = _mintlc_modes(tr_pos, ppi_pos, tr, ppi_ltl)
    res = [minTLC(row, tr, ppi) for row in eachrow(sh)]
    out = DataFrame(sh; copycols = true)
    out.qᵒ = [x.qᵒ for x in res]
    out.TLCᵒ = [x.TLCᵒ for x in res]
    out.isLTL = [x.isLTL for x in res]
    return out
end
