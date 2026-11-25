# DistTools - Distance calculation functions

"""
    dgc(xy₁, xy₂; unit=:mi) -> Float64

Calculate the great circle distance between two points.

Uses the haversine formula to compute the shortest distance over the Earth's surface
between two points specified by longitude-latitude coordinates, on a sphere of constant
radius, 3958.75 mi or 6371.00 km.

# Arguments
- `xy₁`: Tuple or vector of (longitude, latitude) for the first point.
- `xy₂`: Tuple or vector of (longitude, latitude) for the second point.
- `unit`: Distance unit — `:mi` (miles, default), `:km` (kilometers), or `:rad` (radians of arc).

# Returns
- Great circle distance in the specified unit.

# Matlog's Earth model
Matlog's `dists` uses a latitude-dependent radius instead of the sphere's. The two differ by
less than 0.1% at the latitudes of North Carolina (Raleigh to Charlotte, 129.759 mi on the
sphere and 129.655 mi with Matlog's radius), below the precision of any data the course uses,
so a Matlog or 2022 MATLAB great-circle number agrees with `dgc` to about three significant
figures. The arc itself (`unit = :rad`) is the same in both.

# Example
Distance from Raleigh to Charlotte (rounded for a stable, cross-platform doctest — the
raw `Float64` carries full precision).

```jldoctest
round(dgc((-78.6382, 35.7796), (-80.8431, 35.2271)); digits=1)

# output

129.8
```
"""
function dgc(xy1, xy2; unit=:mi)
    length(xy1) == length(xy2) == 2 || error("Inputs must have length 2.")
    unit in [:mi, :km, :rad] || error("Unit must be :mi, :km, or :rad")

    dx, dy = xy2[1] - xy1[1], xy2[2] - xy1[2]
    a = sind(dy / 2)^2 + cosd(xy1[2]) * cosd(xy2[2]) * sind(dx / 2)^2
    dist_rad = 2 * asin(min(sqrt(a), 1.0))

    # Convert to requested unit
    if unit == :rad
        return dist_rad
    elseif unit == :mi
        return dist_rad * 3958.75
    else  # :km
        return dist_rad * 6371.00
    end
end

# N5: a vector against a 1×k row (or any two arrays of different shape) used to broadcast silently:
# d1([0, 0], [3 4]) was 14.0 and d2 gave 7.07. Arrays must have the same shape; anything else
# (tuples, ranges) must have the same length.
function _samepoint(x₁, x₂, f::Symbol)
    ok = (x₁ isa AbstractArray && x₂ isa AbstractArray) ? size(x₁) == size(x₂) : length(x₁) == length(x₂)
    ok || throw(DimensionMismatch(
        "$f: the two points must have the same shape (got $(x₁ isa AbstractArray ? size(x₁) : length(x₁)) " *
        "and $(x₂ isa AbstractArray ? size(x₂) : length(x₂))); a row of a matrix is `P[i, :]`, not `P[i:i, :]`."))
    return nothing
end

"""
    d1(x₁, x₂) -> Float64

Calculate rectilinear (Manhattan, L₁) distance between two points.

# Arguments
- `x₁`: First point (vector or tuple).
- `x₂`: Second point (same dimension as x₁).

# Returns
- Sum of absolute differences: Σ|x₁ᵢ - x₂ᵢ|.

Throws `DimensionMismatch` when the two points differ in shape, for example a vector against
a 1×k row (`P[i:i, :]`) such as `d1([0, 0], [3 4])`, which broadcasting would otherwise turn
into a wrong number (N5).

# Example
```jldoctest
(d1([0, 0], [3, 4]), d1([1, 2, 3], [4, 6, 2]))

# output

(7.0, 8.0)
```
"""
function d1(x₁, x₂)
    _samepoint(x₁, x₂, :d1)
    return float(sum(abs.(x₁ .- x₂)))
end

"""
    d2(x₁, x₂) -> Float64

Calculate Euclidean (L₂) distance between two points.

# Arguments
- `x₁`: First point (vector or tuple).
- `x₂`: Second point (same dimension as x₁).

# Returns
- Euclidean distance: √(Σ(x₁ᵢ - x₂ᵢ)²).

Throws `DimensionMismatch` when the two points differ in shape, as [`d1`](@ref) does (N5).

# Example
```jldoctest
d2([0, 0], [3, 4])

# output

5.0
```
"""
function d2(x₁, x₂)
    _samepoint(x₁, x₂, :d2)
    return sqrt(sum((x₁ .- x₂).^2))
end

"""
    dists(X1, X2[, p]; unit) -> Matrix{Float64}
    dists(x, X2[, p]; unit) -> Vector{Float64}

Compute distance matrix between two point sets using specified metric.

**Replaces**: `Dgc` with unified interface supporting all metrics.

# Arguments
- `X1`: m×n matrix of m points in n dimensions
- `x`: a single point, a vector of n coordinates, in place of `X1`
- `X2`: k×n matrix of k points in n dimensions
- `p`: Distance metric (default: `2`)
  - `1`: Rectilinear (Manhattan, l₁) distance
  - `2`: Euclidean (l₂) distance (default)
  - real `p ≥ 1` (incl. `Inf`): general lₚ metric `(Σ|Δ|ᵖ)^(1/p)`; `Inf` gives the
    Chebychev (l∞) distance `maximum(abs, Δ)`; an integer `p` such as `3` is the same
    metric as `3.0` (N19)
  - `:mi`, `:km`, `:rad`: Great circle distance (requires n=2, lon-lat coordinates);
    `:rad` returns radians of arc
- `unit`: a synonym for `p` when `p` is a great-circle unit, so that `dists(X1, X2; unit = :mi)`
  is `dists(X1, X2, :mi)` and reads like [`dgc`](@ref) and [`dgca`](@ref) (S15). Passing both
  `p` and `unit` is an error.

# Returns
- `D`: m×k matrix where D[i,j] = distance from X1[i,:] to X2[j,:]
- for a single point `x`, the length-k vector of its distances to the rows of `X2` (S15), so
  `dists(x, X2, :mi)` replaces `vec(dists(reshape(x, 1, :), X2, :mi))`

Integer `p ∈ {1,2}` dispatches to the specialized l₁/l₂ computation; any other real value
(e.g. `1.5`, `3`, `3.0`, `Inf`) uses the general lₚ one. `p < 1` errors (not a metric).

# Formulation
For ``x, y \\in \\mathbb{R}^n`` and metric parameter ``p``,

```math
d_p(x,y) = \\Big(\\sum_{t=1}^{n} |x_t - y_t|^{p}\\Big)^{1/p}, \\quad p \\in [1,\\infty);
\\qquad d_\\infty(x,y) = \\max_{t} |x_t - y_t| \\;\\text{(Chebychev)} .
```

The symbol forms ``:mi``/``:km`` return the great-circle distance on the sphere in the
named unit, and ``:rad`` returns radians of arc.

# Examples
Euclidean (default):

```jldoctest
X1 = [0.0 0.0; 10.0 0.0]
X2 = [5.0 0.0; 5.0 5.0]
dists(X1, X2)

# output

2×2 Matrix{Float64}:
 5.0  7.07107
 5.0  7.07107
```

Great-circle distance from lon-lat coordinates (rounded for a stable doctest):

```jldoctest
cities = [-78.64 35.78; -122.42 37.77]   # Raleigh, San Francisco
dc = [-77.04 38.91]                       # Washington, DC
round.(dists(cities, dc, :mi); digits=1)  # statute miles

# output

2×1 Matrix{Float64}:
  233.4
 2434.8
```

Other metrics follow the same call form: `dists(X1, X2, 1)` (Manhattan), `dists(X1, X2,
3.0)` (general lₚ), `dists(X1, X2, Inf)` (Chebychev), and `:km`/`:rad` for great-circle in
kilometers or radians.

See also: [`dgc`](@ref), [`d1`](@ref), [`d2`](@ref)
"""
function dists(X1::AbstractMatrix, X2::AbstractMatrix, p=nothing; unit=nothing)
    return _dists(X1, X2, _metric(p, unit))
end

# S15: one point against a point set returns a vector of distances.
function dists(x::AbstractVector, X2::AbstractMatrix, p=nothing; unit=nothing)
    return vec(_dists(reshape(x, 1, :), X2, _metric(p, unit)))
end

# The metric from `p` and its synonym `unit` (default: Euclidean).
function _metric(p, unit)
    p === nothing || unit === nothing ||
        throw(ArgumentError("dists: pass the metric as `p` or as `unit`, not both."))
    unit === nothing && return p === nothing ? 2 : p
    unit isa Symbol ||
        throw(ArgumentError("dists: `unit` must be :mi, :km or :rad (got $(repr(unit)))."))
    return unit
end

# Euclidean, the default
_dists(X1::AbstractMatrix, X2::AbstractMatrix, ::Nothing) = _dists(X1, X2, 2)

# Integer p: Manhattan (p=1), Euclidean (p=2), any other integer the general lₚ metric (N19)
function _dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Integer)
    if p == 1
        D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            D[i, j] = d1(@view(X1[i, :]), @view(X2[j, :]))
        end
        return D
    elseif p == 2
        D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            D[i, j] = d2(@view(X1[i, :]), @view(X2[j, :]))
        end
        return D
    else
        return _dists(X1, X2, float(p))
    end
end

# Symbol p: Geographic distance
function _dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Symbol)
    p ∈ [:mi, :km, :rad] || error("Geographic distance requires p ∈ [:mi, :km, :rad]")
    D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
    @inbounds for j in axes(X2, 1), i in axes(X1, 1)
        D[i, j] = dgc(@view(X1[i, :]), @view(X2[j, :]); unit=p)
    end
    return D
end

# Real p (incl. Inf): general lₚ metric. p=Inf → Chebychev; finite p ≥ 1 → (Σ|Δ|ᵖ)^(1/p).
# Integer p (1, 2 and the rest) dispatches to the more specific method above; Symbol p is a distinct
# type, so this method never captures the geographic cases — dispatch stays unambiguous.
function _dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Real)
    p >= 1 || error("dists: lₚ metric requires p ≥ 1 (got $p); p<1 is not a metric.")
    D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
    if isinf(p)
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            D[i, j] = maximum(abs, @view(X1[i, :]) .- @view(X2[j, :]))
        end
    else
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            Δ = @view(X1[i, :]) .- @view(X2[j, :])
            D[i, j] = sum(abs.(Δ) .^ p)^(1 / p)
        end
    end
    return D
end

# The mean distance from the centroid of a disk of area `a` to a uniformly random point in it:
# radius r = √(a/π), mean distance (2/3) r. The one constant behind `dgca`'s floor and
# `loc2lonlat`'s `GC_UNCERT` (R2/S3), in the units whose square is the unit of `a`.
_mean_zone_distance(a) = (2 / 3) * sqrt(a / π)

"""
    dgca(X, Xa, a; unit=:mi) -> Matrix{Float64}

Area-adjusted great-circle distance matrix between new-facility/point set `X` and
demand-point set `Xa`, floored by the mean centroid-to-random-point distance of a
disk of area `aⱼ`.

# Formulation
For points ``X = \\{X_i\\}_{i=1}^n`` and demand points ``Xa = \\{Xa_j\\}_{j=1}^m`` with
land areas ``a_j \\ge 0``,

```math
D^{aa}_{ij} \\;=\\; \\max\\!\\left\\{\\, d_{gc}(X_i, Xa_j),\\;\\; \\tfrac{2}{3}\\sqrt{a_j/\\pi}\\,\\right\\},
\\qquad i = 1..n,\\; j = 1..m .
```

The floor ``\\tfrac{2}{3}\\sqrt{a_j/\\pi}`` is the mean distance from the centroid to a
uniformly random point in a disk of area ``a_j`` (radius ``r_j=\\sqrt{a_j/\\pi}``, mean
centroid distance ``\\tfrac{2}{3}r_j``). It represents the intra-zone travel a demand
point still incurs when a facility is placed at its geographic center.

**No circuity:** the raw ``D^{aa}`` is returned; any circuity factor is applied by the
caller. Degenerate ``a_j = 0`` gives floor ``0``, so ``D^{aa}_{ij} = d_{gc}``.

# Arguments
- `X`: n×2 matrix of points (LON, LAT).
- `Xa`: m×2 matrix of demand points (LON, LAT).
- `a`: length-m vector of demand-point areas, in the areal unit whose square root matches
  `unit` (e.g. mi² for `unit=:mi`).
- `unit`: distance/area unit — `:mi` (default), `:km`, or `:rad`.

# Returns
- `D`: n×m matrix where `D[i,j] = max(dgc(X[i,:], Xa[j,:]; unit), (2/3)√(a[j]/π))`.

# Example
The call is Lecture 2.5's `Da = dgca(P, P, z.ALAND)`: points as (LON, LAT) rows and an area in mi² for each demand
point. Here two facilities and two demand points, with areas illustrative rather than
census values, chosen so that one distance is floored (rounded for a stable doctest). The
floor of the 5,000 mi² disk is ``\\tfrac{2}{3}\\sqrt{5000/\\pi} = 26.6`` mi, which exceeds
Raleigh's great-circle distance to Durham (20.6 mi) and is below Charlotte's (121.0 mi), so
Raleigh to Durham is the only entry raised to the floor:

```jldoctest
X  = [-78.64 35.78; -80.84 35.23]     # Raleigh, Charlotte
Xa = [-79.79 36.07; -78.90 35.99]     # Greensboro, Durham
a  = [0.0, 5000.0]                    # Durham floored by a 5,000 mi² disk
round.(dgca(X, Xa, a); digits=1)      # 2×2 raw distances (no circuity); Durham's 20.6 is raised to 26.6

# output

2×2 Matrix{Float64}:
 67.4   26.6
 82.7  121.0
```

See also: [`dgc`](@ref), [`dists`](@ref)
"""
function dgca(X::AbstractMatrix, Xa::AbstractMatrix, a::AbstractVector; unit=:mi)
    size(Xa, 1) == length(a) || error("dgca: length(a) must equal the number of rows in Xa.")
    all(a .>= 0) || error("dgca: areas a must be nonnegative.")
    D = dists(X, Xa, unit)                       # n×m great-circle distances
    floors = _mean_zone_distance.(a)             # length-m floor per demand point
    return max.(D, reshape(floors, 1, :))
end
