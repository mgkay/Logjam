# DistTools - Distance calculation functions

"""
    dgc(xy₁, xy₂; unit=:mi) -> Float64

Calculate the great circle distance between two points.

Uses the haversine formula to compute the shortest distance over the Earth's surface
between two points specified by longitude-latitude coordinates.

# Arguments
- `xy₁`: Tuple or vector of (longitude, latitude) for the first point.
- `xy₂`: Tuple or vector of (longitude, latitude) for the second point.
- `unit`: Distance unit, either `:mi` (miles, default) or `:km` (kilometers).

# Returns
- Great circle distance in the specified unit.

# Example
```julia
# Distance from Raleigh to Charlotte
dgc((-78.6382, 35.7796), (-80.8431, 35.2271))  # ≈ 130 miles
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
```julia
d1([0, 0], [3, 4])  # Returns 7.0
d1([1, 2, 3], [4, 6, 2])  # Returns 8.0
```
"""
d1(x₁, x₂) = sum(abs.(x₁ .- x₂))

"""
    d2(x₁, x₂) -> Float64

Calculate Euclidean (L₂) distance between two points.

# Arguments
- `x₁`: First point (vector or tuple).
- `x₂`: Second point (same dimension as x₁).

# Returns
- Euclidean distance: √(Σ(x₁ᵢ - x₂ᵢ)²).

# Example
```julia
d2([0, 0], [3, 4])  # Returns 5.0
d2([1, 2, 3], [4, 6, 2])  # Returns 6.0
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
  - `1`: Rectilinear (Manhattan) distance
  - `2`: Euclidean distance (default)
  - `:mi`, `:km`, `:rad`: Great circle distance (requires n=2, lon-lat coordinates)

# Returns
- `D`: m×k matrix where D[i,j] = distance from X1[i,:] to X2[j,:]

# Examples
```julia
# Euclidean (default)
X1 = [0.0 0.0; 10.0 0.0]
X2 = [5.0 0.0; 5.0 5.0]
D = dists(X1, X2)  # 2×2 matrix

# Manhattan distance
D = dists(X1, X2, 1)

# Great circle distance (lon-lat coordinates)
cities = [-78.64 35.78; -122.42 37.77]  # Raleigh, SF
dc = [-77.04 38.91]                      # Washington DC
D = dists(cities, dc, :mi)               # Statute miles
D = dists(cities, dc, :km)               # Kilometers
```

See also: [`dgc`](@ref), [`d1`](@ref), [`d2`](@ref)
"""
dists(X1::AbstractMatrix, X2::AbstractMatrix) = [d2(i, j) for i in eachrow(X1), j in eachrow(X2)]

# Integer p: Manhattan (p=1) or Euclidean (p=2)
function dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Int)
    p == 1 && return [d1(i, j) for i in eachrow(X1), j in eachrow(X2)]
    p == 2 && return [d2(i, j) for i in eachrow(X1), j in eachrow(X2)]
    error("For integer p, only p=1 (rectilinear) and p=2 (Euclidean) supported. Use p=:mi/:km/:rad for geographic.")
end

# Symbol p: Geographic distance
function dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Symbol)
    p ∈ [:mi, :km, :rad] || error("Geographic distance requires p ∈ [:mi, :km, :rad]")
    return [dgc(i, j; unit=p) for i in eachrow(X1), j in eachrow(X2)]
end
