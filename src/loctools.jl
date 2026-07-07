# =============================================================================
# Facility Location Optimization
# =============================================================================

# Build n×m sparse allocation matrix W where W[i,j]=1 if facility i serves customer j
function _build_alloc(y, C)
    n, m = size(C)
    all(1 .<= y .<= n) || error("Facility indices y must be in range 1:$n")
    alloc = [y[argmin(C[y, j])] for j in 1:m]
    return sparse(alloc, 1:m, 1.0, n, m)
end

"""
    ufladd(k, C; y=Int[], p=nothing) -> (Vector{Int}, Float64, SparseMatrixCSC)

Greedy ADD construction heuristic for uncapacitated facility location.

Iteratively opens the facility giving the greatest cost reduction until no improvement
is possible (or `p` facilities are open).

# Arguments
- `k`: Fixed cost. Scalar (same cost at every site) or length-`n` vector, `k[i]` = cost
  of opening a facility at candidate site `i`.
- `C`: `n`×`m` variable-cost matrix over `n` candidate sites and `m` customers; `C[i,j]`
  = cost of serving customer `j` from site `i`.
- `y`: initial set of open sites (default: empty — start from scratch).
- `p`: cap on the number of open facilities (default: `nothing`, no cap).

# Returns
- `(y, TC, W)`: open-facility site indices; total cost `TC = sum(k[y]) + sum(C[allocated])`;
  and the `n`×`m` sparse allocation matrix `W`, `W[i,j] = 1` if customer `j` is served by
  facility `i`.

# Example
Example 8.8 in Francis, *Facility Layout and Location*, 2nd ed. (Daskin, *Network and
Discrete Location*, 1995, Fig. 7.2).

```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y, TC, W = ufladd(k, C)
(y, TC)

# output

([2, 6], 32.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8; M.S. Daskin, *Network and Discrete Location*, 1995,
  Fig. 7.2. Ported from Matlog `ufladd`.
"""
function ufladd(k, C; y = Int[], p::Union{Int, Nothing} = nothing)
    if k isa Number
        k = fill(k, size(C, 1))
    end
    fTC(y) = sum(k[y]) + sum(minimum(C[y, :], dims=1))
    TCᵒ = isempty(y) ? Inf : fTC(y)
    N = 1:size(C, 1)
    done = false
    while !done
        TC, i = Inf, nothing
        for i′ = setdiff(N, y)
            TC′ = fTC(vcat(y, i′))
            if TC′ < TC
                TC, i = TC′, i′
            end
        end
        if (p === nothing && TC < TCᵒ) || (p isa Int && length(y) < p)
            TCᵒ, y = TC, push!(y, i)
        else
            done = true
        end
    end
    return y, float(TCᵒ), _build_alloc(y, C)
end

"""
    ufldrop(k, C; y=nothing, p=nothing) -> (Vector{Int}, Float64, SparseMatrixCSC)

Greedy DROP construction heuristic for uncapacitated facility location.

Starts with every facility open and iteratively closes the one giving the greatest cost
reduction until no improvement is possible (or `p` remain).

# Arguments
- `k`: Fixed cost. Scalar (same cost at every site) or length-`n` vector, `k[i]` = cost
  of opening a facility at candidate site `i`.
- `C`: `n`×`m` variable-cost matrix over `n` candidate sites and `m` customers; `C[i,j]`
  = cost of serving customer `j` from site `i`.
- `y`: initial set of open sites (default: all sites open).
- `p`: target number of open facilities (default: `nothing`, drop until no improvement).

# Returns
- `(y, TC, W)`: open-facility site indices; total cost `TC = sum(k[y]) + sum(C[allocated])`;
  and the `n`×`m` sparse allocation matrix `W`, `W[i,j] = 1` if customer `j` is served by
  facility `i`.

# Example
Example 8.8 in Francis, *Facility Layout and Location*, 2nd ed. (Daskin, *Network and
Discrete Location*, 1995, Fig. 7.3). DROP stops at a different local optimum than ADD.

```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y, TC, W = ufldrop(k, C)
(y, TC)

# output

([2, 4, 6], 32.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8; M.S. Daskin, *Network and Discrete Location*, 1995,
  Fig. 7.3. Ported from Matlog `ufldrop`.
"""
function ufldrop(k, C; y = nothing, p::Union{Int, Nothing} = nothing)
    if k isa Number
        k = fill(k, size(C, 1))
    end
    fTC(y) = sum(k[y]) + sum(minimum(C[y, :], dims=1))
    if y === nothing
        y = collect(1:size(C, 1))
    end
    TCᵒ = fTC(y)
    done = false
    while !done && length(y) > 1
        TC, i = Inf, nothing
        for i′ in y
            TC′ = fTC(setdiff(y, i′))
            if TC′ < TC
                TC, i = TC′, i′
            end
        end
        if (p === nothing && TC < TCᵒ) || (p isa Int && length(y) > p)
            TCᵒ, y = TC, setdiff(y, i)
        else
            done = true
        end
    end
    return y, float(TCᵒ), _build_alloc(y, C)
end

"""
    uflxchg(k, C, y) -> (Vector{Int}, Float64, SparseMatrixCSC)

Pairwise EXCHANGE improvement heuristic for uncapacitated facility location.

Steepest-descent swaps (close one open facility, open one closed) from a starting set `y`
until a local optimum is reached. The swap preserves the number of open facilities, so
`y` sets the cardinality.

# Arguments
- `k`: Fixed cost. Scalar (same cost at every site) or length-`n` vector (see [`ufladd`](@ref)).
- `C`: `n`×`m` variable-cost matrix over `n` candidate sites and `m` customers; `C[i,j]`
  = cost of serving customer `j` from site `i`.
- `y`: starting set of open sites (required — exchange improves *this* set).

# Returns
- `(y, TC, W)`: improved open-facility site indices; total cost
  `TC = sum(k[y]) + sum(C[allocated])`; and the `n`×`m` sparse allocation matrix `W`,
  `W[i,j] = 1` if customer `j` is served by facility `i`.

# Example
Improve the ADD solution to Example 8.8 (Francis, 2nd ed.; Daskin, Fig. 7.5): the swap
takes the starting set `[2, 6]` (TC 32.0) to `[3, 6]` (TC 31.0).

```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y0, _, _ = ufladd(k, C)          # ADD gives the starting set
y, TC, W = uflxchg(k, C, y0)
(y0, y, TC)

# output

([2, 6], [3, 6], 31.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8; M.S. Daskin, *Network and Discrete Location*, 1995,
  Fig. 7.5. Ported from Matlog `uflxchg`.
"""
function uflxchg(k, C, y::Vector{Int})
    if k isa Number
        k = fill(k, size(C, 1))
    end
    y = copy(y)  # work on a fresh vector: never alias/mutate the caller's y
    fTC(y) = sum(k[y]) + sum(minimum(C[y, :], dims=1))
    N = 1:size(C, 1)
    TCᵒ = fTC(y)
    done = false

    # Helper function to swap facilities
    function swap!(y::Vector{Int}, i::Int, j::Int)
        deleteat!(y, findfirst(==(i), y))
        push!(y, j)
    end

    function revert!(y::Vector{Int}, i::Int, j::Int)
        deleteat!(y, findfirst(==(j), y))
        push!(y, i)
    end

    while length(y) > 1 && !done
        TC, i, j = Inf, nothing, nothing
        for i′ in y
            for j′ in setdiff(N, y)
                swap!(y, i′, j′)
                TC′ = fTC(y)
                if TC′ < TC
                    TC, i, j = TC′, i′, j′
                end
                revert!(y, i′, j′)
            end
        end
        if TC < TCᵒ
            TCᵒ = TC
            swap!(y, i, j)
        else
            done = true
        end
    end
    return y, float(TCᵒ), _build_alloc(y, C)
end

"""
    ufl(k, C; verbose=true) -> (Vector{Int}, Float64, SparseMatrixCSC)

Hybrid UFL heuristic combining ADD, EXCHANGE, and DROP.

Iterates ADD → EXCHANGE → (ADD vs DROP, take best) until no improvement. Typically finds
a better solution than any single procedure alone. With the default `verbose=true`, prints
the per-step `Add`/`Xchg`/`Drop` cost trace.

# Arguments
- `k`: Fixed cost. Scalar (same cost at every site) or length-`n` vector (see [`ufladd`](@ref)).
- `C`: `n`×`m` variable-cost matrix over `n` candidate sites and `m` customers; `C[i,j]`
  = cost of serving customer `j` from site `i`.
- `verbose`: print the per-step cost trace (default: `true`).

# Returns
- `(y, TC, W)`: best open-facility site indices found; total cost
  `TC = sum(k[y]) + sum(C[allocated])`; and the `n`×`m` sparse allocation matrix `W`,
  `W[i,j] = 1` if customer `j` is served by facility `i`.

# Example
Example 8.8 in Francis, *Facility Layout and Location*, 2nd ed. The hybrid improves on ADD
(32.0) and DROP (32.0) alone.

```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y, TC, W = ufl(k, C; verbose=false)
(y, TC)

# output

([3, 6], 31.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8; M.S. Daskin, *Network and Discrete Location*, 1995.
  Ported from Matlog `ufl`.
"""
function ufl(k, C; verbose = true)
    y′, TC′, _ = ufladd(k, C)
    verbose && println("  Add: ", TC′)
    y, TC = y′, TC′
    done = false
    while !done
        y, TC, _ = uflxchg(k, C, y′)
        verbose && println(" Xchg: ", TC)
        if Set(y) != Set(y′)
            y′, TC′, _ = ufladd(k, C; y)
            verbose && println("  Add: ", TC′)
            y′′, TC′′, _ = ufldrop(k, C; y)
            verbose && println(" Drop: ", TC′′)
            if TC′′ < TC′
                y′, TC′ = y′′, TC′′
            end
            if TC′ >= TC
                done = true
            end
        else
            done = true
        end
    end
    return y, float(TC), _build_alloc(y, C)
end

"""
    pmedian(p, C; verbose=true) -> (Vector{Int}, Float64, SparseMatrixCSC)

p-median facility location: open exactly `p` facilities (no fixed costs) to minimize total
assignment cost. Uses [`ufladd`](@ref) with `k=0` to select `p`, then [`uflxchg`](@ref) to
improve.

# Arguments
- `p`: number of facilities to open.
- `C`: `n`×`m` variable-cost matrix over `n` candidate sites and `m` customers; `C[i,j]`
  = cost of serving customer `j` from site `i`.
- `verbose`: print the selection trace (default: `true`).

# Returns
- `(y, TC, W)`: the `p` open-facility site indices; total cost `TC = sum(C[allocated])`
  (transport only, no fixed costs); and the `n`×`m` sparse allocation matrix `W`,
  `W[i,j] = 1` if customer `j` is served by facility `i`.

# Example
Same cost matrix as Example 8.8 (Francis, 2nd ed.), with fixed costs dropped.

```jldoctest
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y, TC, W = pmedian(2, C; verbose=false)
(y, TC)

# output

([6, 3], 13.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8 (cost matrix). Ported from Matlog `pmedian`.
"""
function pmedian(p, C; verbose = true)
    1 <= p <= size(C, 1) || error("p must be between 1 and $(size(C, 1))")
    y = ufladd(0, C; p = p)[1]
    verbose && println(" p-median ADD: $(p) facilities selected")
    return uflxchg(0, C, y)
end

# =============================================================================
# Alternating Location–Allocation
# =============================================================================

# Point-to-point distance for a single (LON,LAT) pair under the `ala` metric.
function _aladist(x, y, dist)
    if dist isa Symbol
        return dgc(x, y; unit=dist)
    elseif dist == 1
        return d1(x, y)
    elseif dist == 2
        return d2(x, y)
    else
        error("ala: `dist` must be :mi, :km, :rad, 1, or 2 (got $(repr(dist))).")
    end
end

# Default allocate: assign each demand point to its nearest new facility, build a
# sparse n×m weight matrix, and relocate any orphaned (all-zero-row) facility to a
# random demand point until every facility is used (mirrors ala.m `default_alloc`).
function _ala_alloc(X, w, P, dist)
    m = length(w)
    Xw = copy(X)
    wf = Float64.(collect(w))
    local W, D
    done = false
    while !done
        D = dists(Xw, P, dist)                       # n×m distance matrix
        assign = [argmin(@view D[:, j]) for j in 1:m]
        W = sparse(assign, 1:m, wf, size(Xw, 1), m)
        idx0 = findall(iszero, vec(sum(W, dims=2)))  # unallocated facilities
        if isempty(idx0)
            done = true
        else                                          # relocate orphans to random EFs
            perm = sortperm(rand(size(P, 1)))
            Xw[idx0, :] = P[perm[1:length(idx0)], :]
        end
    end
    return W, sum(W .* D)
end

# Default locate: per-facility continuous minisum. For each facility, minimise the
# weighted sum of distances to its allocated demand points via `Optim.optimize`.
function _ala_locate(W, X, dist, P)
    Xnew = copy(X)
    for i in axes(W, 1)
        J = findall(!iszero, @view W[i, :])
        isempty(J) && continue
        wi = [W[i, j] for j in J]
        x0 = Vector{Float64}(@view X[i, :])
        f(x) = sum(wi[k] * _aladist(x, @view(P[J[k], :]), dist) for k in eachindex(J))
        Xnew[i, :] = optimize(f, x0).minimizer
    end
    return Xnew
end

# One alternating location–allocation descent from a single start.
function _ala_run(X, alloc_fn, locate_fn)
    W, TC = alloc_fn(X)
    done = false
    while !done
        X1 = locate_fn(W, X)
        W1, TC1 = alloc_fn(X1)
        if TC1 < TC
            TC, X, W = TC1, X1, W1
        else
            done = true
        end
    end
    return X, TC, W
end

"""
    ala(X0, w, P; dist=:mi, alloc=<default>, locate=<default>, nruns=1) -> (X, TC, W)

Alternating location–allocation for locating `n` new facilities among `m` weighted
demand points.

Starting from `n` facility locations `X0`, alternate two steps until the total cost
`TC` stops decreasing: **allocate** each demand point to its nearest facility, then
**locate** each facility at the continuous minisum of its allocated points. The default
allocate step relocates any orphaned (unused) facility to a random demand point so no
zero-weight facility persists.

# Formulation
Given demand points ``P = \\{P_j\\}_{j=1}^m``, weights ``w_j \\ge 0``, and ``n`` new
facilities, choose facility locations ``X = \\{X_i\\}_{i=1}^n \\subset \\mathbb{R}^2``
and allocation ``W \\in \\{0,1\\}^{n \\times m}`` to minimise

```math
\\min_{X,\\,W}\\; TC = \\sum_{j=1}^{m} w_j\\, d\\!\\left(X_{\\sigma(j)}, P_j\\right),
\\qquad \\sigma(j) = \\arg\\min_i d(X_i, P_j),
```

alternating

- **allocate:** ``\\sigma(j) = \\arg\\min_i d(X_i, P_j)`` (nearest facility);
- **locate:** ``X_i \\leftarrow \\arg\\min_{X} \\sum_{j:\\sigma(j)=i} w_j\\, d(X, P_j)``
  (per-facility minisum),

iterating until ``TC`` is non-decreasing.

**Orphan rule:** if ``\\{j : \\sigma(j) = i\\} = \\varnothing`` for some ``i``, relocate
``X_i`` to a random ``P_j`` and re-allocate; loop until every facility is used. The
distance ``d`` defaults to the great-circle distance ``d_{gc}`` (`dist=:mi`). With
`nruns` random starts, the minimum-`TC` solution is returned.

# Arguments
- `X0`: n×2 matrix of initial facility locations (LON, LAT).
- `w`: length-m vector of demand weights (`w_j ≥ 0`).
- `P`: m×2 matrix of demand-point locations (LON, LAT).
- `dist`: distance metric — `:mi` (default), `:km`, `:rad` (great-circle), or `1`/`2`
  (rectilinear/Euclidean).
- `alloc`: allocate handle `X -> (W, TC)` overriding the default nearest-facility
  allocation (e.g. for forced/constrained partitions).
- `locate`: locate handle `(W, X) -> X` overriding the default per-facility minisum.
- `nruns`: number of independent random restarts. Run 1 uses `X0`; runs 2…`nruns` use
  fresh `randX(P, n)` starts. The best (minimum-`TC`) result is returned.

# Returns
- `(X, TC, W)`: n×2 facility locations, total cost `TC`, and the n×m sparse allocation
  matrix `W` where `W[i,j]` is the weight facility `i` serves from demand point `j`.

# Example
Locate two facilities to serve four North Carolina cities. The `locate` step calls a
continuous optimizer and the orphan rule draws from the RNG, so `TC` is shown rounded and
may vary slightly across Optim/Julia versions.

```julia
P  = [-78.64 35.78; -80.84 35.23; -79.79 36.07; -77.94 34.23]  # Raleigh, Charlotte, Greensboro, Wilmington
w  = [469.0, 897.0, 299.0, 123.0]
X0 = [-78.6 35.8; -80.0 35.5]
X, TC, W = ala(X0, w, P)          # dist=:mi great-circle minisum
round(TC; digits=1)               # => 34194.6 (great-circle miles)
```

# References
- M.G. Kay, *Facility Location* (course notes), NC State University; Matlog `ala`.
"""
function ala(X0, w, P; dist=:mi, alloc=nothing, locate=nothing, nruns::Int=1)
    size(X0, 2) == size(P, 2) || error("ala: X0 and P must have the same number of columns.")
    length(w) == size(P, 1) || error("ala: length(w) must equal the number of rows in P.")
    n = size(X0, 1)
    n <= size(P, 1) || error("ala: number of facilities (n=$n) cannot exceed number of demand points (m=$(size(P, 1))).")
    nruns >= 1 || error("ala: nruns must be ≥ 1.")

    alloc_fn = alloc === nothing ? (X -> _ala_alloc(X, w, P, dist)) : alloc
    locate_fn = locate === nothing ? ((W, X) -> _ala_locate(W, X, dist, P)) : locate

    bestX = bestW = nothing
    bestTC = Inf
    for run in 1:nruns
        Xstart = run == 1 ? Matrix{Float64}(X0) : Matrix{Float64}(randX(P, n))
        X, TC, W = _ala_run(Xstart, alloc_fn, locate_fn)
        if TC < bestTC
            bestTC, bestX, bestW = TC, X, W
        end
    end
    return bestX, bestTC, bestW
end

# =============================================================================
# Utility Functions
# =============================================================================

"""
    randX(P::AbstractMatrix, n::Int=1) -> Matrix

Generate n random points within the bounding box of point set P.

Useful for generating random facility locations for optimization problems.

# Arguments
- `P`: m×d matrix of m points in d dimensions.
- `n`: Number of random points to generate (default: 1).

# Returns
- n×d matrix of random points, uniformly distributed within min/max of each dimension.

# Example
`randX` draws from the RNG, so the coordinates vary run to run (and the exact stream is not
stable across Julia versions); only the shape is fixed. Seed for reproducibility within a
session.

```julia
using Random; Random.seed!(1)
P = [0 0; 2 0; 2 3]
X = randX(P, 5)      # 5 random points in [0,2] × [0,3]
size(X)              # => (5, 2)
```
"""
function randX(P::AbstractMatrix, n::Int=1)
    n >= 1 || error("n must be positive")
    size(P, 1) >= 1 || error("P must have at least one point")

    if size(P, 1) == 1
        return repeat(P, n)
    else
        mins = minimum(P, dims=1)
        ranges = maximum(P, dims=1) - mins
        return mins .+ rand(n, size(P, 2)) .* ranges
    end
end

"""
    wcentroid(LON, LAT, w) -> (LON, LAT)

Weighted geographic centroid of points `(LON, LAT)` with weights `w`, corrected for
longitude convergence toward the poles by a `cos(lat)` factor.

# Formulation
Given points ``\\{(\\text{lon}_i, \\text{lat}_i)\\}_{i=1}^N`` with weights ``w_i \\ge 0``
and ``\\sum_i w_i > 0``,

```math
\\overline{\\text{LAT}} = \\frac{\\sum_i w_i\\,\\text{lat}_i}{\\sum_i w_i},
\\qquad
\\overline{\\text{LON}} = \\frac{\\sum_i w_i \\cos(\\text{lat}_i)\\,\\text{lon}_i}
                              {\\sum_i w_i \\cos(\\text{lat}_i)} .
```

The ``\\cos(\\text{lat})`` weighting corrects for meridian convergence: a degree of
longitude spans less ground distance at higher latitudes, so higher-latitude points are
down-weighted in the longitude average. Domain: ``\\sum_i w_i > 0`` and
``\\text{lat} \\in (-90, 90)`` so ``\\cos(\\text{lat}) > 0``.

# Arguments
- `LON`: vector of longitudes (degrees).
- `LAT`: vector of latitudes (degrees, in ``(-90, 90)``).
- `w`: vector of nonnegative weights with ``\\sum_i w_i > 0``.

# Returns
- `(LON = ..., LAT = ...)`: the weighted centroid as a `NamedTuple`, longitude first
  (matching Logjam's LON–LAT order). Destructures as `lon, lat = wcentroid(...)` and
  composes directly with `combine(groupby(...), ... => wcentroid => [:LON, :LAT])`.

# Example
Population-weighted centroid of four NC cities (rounded for a stable, cross-platform
doctest — the raw `Float64`s carry full precision):

```jldoctest
r = wcentroid([-78.64, -80.84, -79.79, -77.94], [35.78, 35.23, 36.07, 34.23], [469.0, 897.0, 299.0, 123.0])
round.((r.LON, r.LAT); digits=4)

# output

(-79.8886, 35.4459)
```

Because it returns a `(LON, LAT)` NamedTuple, it composes directly with `combine` for a
per-group weighted centroid:

```julia
using DataFrames
df = DataFrame(
    k   = [:A, :A, :B, :B],
    LON = [-78.64, -80.84, -79.79, -77.94],
    LAT = [ 35.78,  35.23,  36.07,  34.23],
    POP = [469.0, 897.0, 299.0, 123.0],
)
combine(groupby(df, :k), [:LON, :LAT, :POP] => wcentroid => [:LON, :LAT])
```

See also: [`ala`](@ref), [`randX`](@ref)
"""
function wcentroid(LON, LAT, w)
    sw = sum(w)
    sw > 0 || error("wcentroid: sum of weights must be positive.")
    LATbar = sum(w .* LAT) / sw
    cw = w .* cosd.(LAT)
    scw = sum(cw)
    scw > 0 || error("wcentroid: sum of cos(lat)-weights must be positive (check lat range).")
    LONbar = sum(cw .* LON) / scw
    return (LON=LONbar, LAT=LATbar)
end
