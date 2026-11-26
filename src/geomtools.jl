# GeomTools - geometry for drawing: alloclines (split from datatools.jl in v0.3.1, A10)

# =============================================================================
# Relocated Functions (from MapTools — pure computation, no plotting dependency)
# =============================================================================

"""
    alloclines(W, hub_xy, spoke_xy; tol=sqrt(eps())) -> (X, Y)

Convert allocation matrix to NaN-separated line segments for visualization.

Creates line segments connecting hubs to their allocated spokes. Returns one
vector of coordinates per hub, enabling per-hub formatting (e.g., different colors).

# Arguments
- `W`: n×m allocation matrix where W[i,j] indicates allocation weight from hub i to spoke j.
- `hub_xy`: n×2 matrix of hub coordinates [lon, lat] or [x, y].
- `spoke_xy`: m×2 matrix of spoke coordinates [lon, lat] or [x, y].
- `tol`: Threshold for nonzero allocation (default: √eps ≈ 1.5e-8).

# Returns
- `(X, Y)`: Tuple of `Vector{Vector{Float64}}`, each of length n (one per hub).
  `X[i]` and `Y[i]` contain NaN-separated coordinates for hub i's allocation lines.

# Example
Each hub's segments are `[hub, spoke, NaN, hub, spoke, NaN, …]`; an unused hub yields an
empty vector.

```jldoctest
W = [1.0 0.0; 0.0 1.0]          # hub 1 serves spoke 1; hub 2 serves spoke 2
hubs = [0.0 0.0; 1.0 1.0]
spokes = [0.5 0.5; 2.0 2.0]
X, Y = alloclines(W, hubs, spokes)
X

# output

2-element Vector{Vector{Float64}}:
 [0.0, 0.5, NaN]
 [1.0, 2.0, NaN]
```

In practice `W` comes from an allocation solver, e.g. `_, _, W = ufl(k, C; verbose=false)`.
"""
function alloclines(W::AbstractMatrix, hub_xy::AbstractMatrix, spoke_xy::AbstractMatrix;
                    tol::Real=sqrt(eps(Float64)))
    n, m = size(W)
    size(hub_xy, 1) == n || throw(ArgumentError("hub_xy must have $n rows to match W"))
    size(spoke_xy, 1) == m || throw(ArgumentError("spoke_xy must have $m rows to match W"))
    size(hub_xy, 2) == 2 || throw(ArgumentError("hub_xy must be an n×2 matrix"))
    size(spoke_xy, 2) == 2 || throw(ArgumentError("spoke_xy must be an m×2 matrix"))

    X = [Float64[] for _ in 1:n]
    Y = [Float64[] for _ in 1:n]

    for i in 1:n
        for j in 1:m
            if abs(W[i, j]) > tol
                append!(X[i], [hub_xy[i, 1], spoke_xy[j, 1], NaN])
                append!(Y[i], [hub_xy[i, 2], spoke_xy[j, 2], NaN])
            end
        end
    end

    return X, Y
end
