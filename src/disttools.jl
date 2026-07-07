# DistTools - Distance calculation functions

"""
    dgc(xy₁, xy₂; unit=:mi) -> Float64

Calculate the great circle distance between two points.

Uses the haversine formula to compute the shortest distance over the Earth's surface
between two points specified by longitude-latitude coordinates.

# Arguments
- `xy₁`: Tuple or vector of (longitude, latitude) for the first point.
- `xy₂`: Tuple or vector of (longitude, latitude) for the second point.
- `unit`: Distance unit — `:mi` (miles, default), `:km` (kilometers), or `:rad` (radians of arc).

# Returns
- Great circle distance in the specified unit.

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

"""
    d1(x₁, x₂) -> Float64

Calculate rectilinear (Manhattan, L₁) distance between two points.

# Arguments
- `x₁`: First point (vector or tuple).
- `x₂`: Second point (same dimension as x₁).

# Returns
- Sum of absolute differences: Σ|x₁ᵢ - x₂ᵢ|.

# Example
```jldoctest
(d1([0, 0], [3, 4]), d1([1, 2, 3], [4, 6, 2]))

# output

(7.0, 8.0)
```
"""
d1(x₁, x₂) = float(sum(abs.(x₁ .- x₂)))

"""
    d2(x₁, x₂) -> Float64

Calculate Euclidean (L₂) distance between two points.

# Arguments
- `x₁`: First point (vector or tuple).
- `x₂`: Second point (same dimension as x₁).

# Returns
- Euclidean distance: √(Σ(x₁ᵢ - x₂ᵢ)²).

# Example
```jldoctest
d2([0, 0], [3, 4])

# output

5.0
```
"""
d2(x₁, x₂) = sqrt(sum((x₁ .- x₂).^2))

"""
    dists(X1, X2[, p]) -> Matrix{Float64}

Compute distance matrix between two point sets using specified metric.

**Replaces**: `Dgc` with unified interface supporting all metrics.

# Arguments
- `X1`: m×n matrix of m points in n dimensions
- `X2`: k×n matrix of k points in n dimensions
- `p`: Distance metric (default: `2`)
  - `1`: Rectilinear (Manhattan, l₁) distance
  - `2`: Euclidean (l₂) distance (default)
  - real `p ≥ 1` (incl. `Inf`): general lₚ metric `(Σ|Δ|ᵖ)^(1/p)`; `Inf` gives the
    Chebychev (l∞) distance `maximum(abs, Δ)`
  - `:mi`, `:km`, `:rad`: Great circle distance (requires n=2, lon-lat coordinates);
    `:rad` returns radians of arc

# Returns
- `D`: m×k matrix where D[i,j] = distance from X1[i,:] to X2[j,:]

Integer `p ∈ {1,2}` dispatches to the specialized l₁/l₂ methods; any other real value
(e.g. `1.5`, `3.0`, `Inf`) uses the general lₚ method. `p < 1` errors (not a metric).

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
function dists(X1::AbstractMatrix, X2::AbstractMatrix)
    D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
    @inbounds for j in axes(X2, 1), i in axes(X1, 1)
        D[i, j] = d2(@view(X1[i, :]), @view(X2[j, :]))
    end
    return D
end

# Integer p: Manhattan (p=1) or Euclidean (p=2)
function dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Int)
    if p == 1
        D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            D[i, j] = d1(@view(X1[i, :]), @view(X2[j, :]))
        end
        return D
    elseif p == 2
        return dists(X1, X2)
    else
        error("For integer p, only p=1 (rectilinear) and p=2 (Euclidean) supported. Use p=:mi/:km/:rad for geographic.")
    end
end

# Symbol p: Geographic distance
function dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Symbol)
    p ∈ [:mi, :km, :rad] || error("Geographic distance requires p ∈ [:mi, :km, :rad]")
    D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
    @inbounds for j in axes(X2, 1), i in axes(X1, 1)
        D[i, j] = dgc(@view(X1[i, :]), @view(X2[j, :]); unit=p)
    end
    return D
end

# Real p (incl. Inf): general lₚ metric. p=Inf → Chebychev; finite p ≥ 1 → (Σ|Δ|ᵖ)^(1/p).
# Int p (1, 2) dispatches to the more specific method above; Symbol p is a distinct type,
# so this method never captures the geographic cases — dispatch stays unambiguous.
function dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Real)
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
Two facilities, two demand points (LON, LAT); demand areas in mi² (rounded for a stable
doctest):

```jldoctest
X  = [-78.64 35.78; -80.84 35.23]     # Raleigh, Charlotte
Xa = [-79.79 36.07; -77.94 34.23]     # Greensboro, Wilmington
a  = [0.0, 500.0]                     # Wilmington floored by a 500 mi² disk
round.(dgca(X, Xa, a); digits=1)      # 2×2 raw distances (no circuity)

# output

2×2 Matrix{Float64}:
 67.4  114.2
 82.7  178.6
```

See also: [`dgc`](@ref), [`dists`](@ref)
"""
function dgca(X::AbstractMatrix, Xa::AbstractMatrix, a::AbstractVector; unit=:mi)
    size(Xa, 1) == length(a) || error("dgca: length(a) must equal the number of rows in Xa.")
    all(a .>= 0) || error("dgca: areas a must be nonnegative.")
    D = dists(X, Xa, unit)                       # n×m great-circle distances
    floors = (2 / 3) .* sqrt.(a ./ π)            # length-m floor per demand point
    return max.(D, reshape(floors, 1, :))
end
