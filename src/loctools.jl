# =============================================================================
# Facility Location Optimization
# =============================================================================

# Build n×m sparse allocation matrix W where W[i,j]=1 if facility i serves customer j.
# `y` is read in index order, so with a sorted `y` a tie goes to the lowest site (Matlog's `argmin`).
function _build_alloc(y, C)
    n, m = size(C)
    all(1 .<= y .<= n) || error("Facility indices y must be in range 1:$n")
    Cy = C[y, :]
    alloc = [y[argmin(@view Cy[:, j])] for j in 1:m]
    return sparse(alloc, 1:m, 1.0, n, m)
end

# Input checks of the UFL family, ported from Matlog (N13). `fn` names the caller in the message.
function _ufl_k(fn, k, n)
    if k isa Number
        k >= 0 || error("$fn: `k` must be non-negative.")
        return fill(k, n)
    end
    kv = vec(k)
    length(kv) == n || error("$fn: `k` must be a scalar or have one entry per row of `C` (n = $n; got $(length(kv))).")
    all(>=(0), kv) || error("$fn: `k` must be non-negative.")
    return kv
end

# A fresh Vector{Int} of the caller's sites, so no routine ever grows or reorders the caller's `y` (CR 5).
function _ufl_y(fn, y, n)
    yv = collect(Int, y)
    all(i -> 1 <= i <= n, yv) || error("$fn: `y` must contain site indices between 1 and $n.")
    allunique(yv) || error("$fn: `y` must not repeat a site.")
    return yv
end

_ufl_p(fn, p, n) = (p === nothing || 1 <= p <= n) || error("$fn: `p` must be between 1 and $n.")

# Cheapest and second-cheapest open site for every EF (columns of `Cy`, one row per open site), and the
# row of the cheapest: dropping or swapping out a site costs only the EFs it was serving (Matlog's c1).
function _best2(Cy)
    r, m = size(Cy)
    c1, c2, idx = fill(Inf, m), fill(Inf, m), zeros(Int, m)
    for j in 1:m, a in 1:r
        c = Cy[a, j]
        if c < c1[j]
            c2[j] = c1[j]; c1[j] = c; idx[j] = a
        elseif c < c2[j]
            c2[j] = c
        end
    end
    return c1, c2, idx
end

# Total cost of the open sites `y`: fixed costs plus each EF served by its cheapest open site.
_ufl_cost(k, C, y) = sum(k[y]) + sum(minimum(C[y, :], dims = 1))

"""
    ufladd(k, C; y=Int[], p=nothing) -> (Vector{Int}, Float64, SparseMatrixCSC)

Greedy ADD construction heuristic for uncapacitated facility location.

Iteratively opens the new facility (NF) giving the greatest cost reduction until no
improvement is possible. With `p`, it opens NFs until **exactly** `p` are open, whether or not
each one lowers the cost (Matlog: "add exactly `p` NFs").

# Arguments
- `k`: Fixed cost. Scalar (same cost at every NF site) or length-`n` vector, `k[i]` = cost
  of opening an NF at candidate site `i`. Must be non-negative.
- `C`: `n`×`m` variable-cost matrix over `n` candidate NF sites and `m` existing facilities
  (EFs); `C[i,j]` = cost of serving EF `j` from an NF at site `i`.
- `y`: indices of the initially-open NF sites (default: empty — start from scratch). The
  caller's vector is never changed.
- `p`: the number of NFs to open (default: `nothing`, no target: add while the cost falls).
  This is a target and not a cap: the call opens `p` sites even where the cost rises.
  Must be between 1 and `n`.

# Returns
- `(y, TC, W)`: indices of the open NF sites, **sorted**; total cost
  `TC = sum(k[y]) + sum(C[allocated])`; and the `n`×`m` sparse allocation matrix `W`,
  `W[i,j] = 1` if EF `j` is served by the NF at site `i` (a tie goes to the lower site index).

An error is thrown for a `k` of the wrong length or with a negative entry, a `y` that is out of
range or repeats a site, and a `p` outside `1:n`.

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

Starting from the open site `y = [1]` on the same data (Matlog's `ufladd(k, C, 1)`): the sites
come back sorted and the caller's `y0` is left as it was.

```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y0 = [1]
y, TC, W = ufladd(k, C; y = y0)
(y0, y, TC)

# output

([1], [1, 4], 32.0)
```

`p = 3` opens exactly three sites, one more than the unconstrained ADD stops at (Matlog's
`ufladd(k, C, [], 3)`):

```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y, TC, W = ufladd(k, C; p = 3)
(y, TC)

# output

([2, 4, 6], 32.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8; M.S. Daskin, *Network and Discrete Location*, 1995,
  Fig. 7.2. Ported from Matlog `ufladd`.
"""
function ufladd(k, C; y = Int[], p::Union{Int, Nothing} = nothing)
    n, m = size(C)
    k = _ufl_k(:ufladd, k, n)
    y = _ufl_y(:ufladd, y, n)                  # a copy: the caller's `y` is never grown (CR 5)
    _ufl_p(:ufladd, p, n)
    c1 = fill(Inf, m)                          # cheapest open site for each EF (Matlog's c1)
    for i in y
        c1 = min.(c1, @view C[i, :])
    end
    ksum = sum(k[y])
    TCᵒ = isempty(y) ? Inf : ksum + sum(c1)
    closed = setdiff(1:n, y)
    while true
        TC, i = Inf, 0
        for i′ in closed
            TC′ = ksum + k[i′] + sum(min.(c1, @view C[i′, :]))
            if TC′ < TC
                TC, i = TC′, i′
            end
        end
        i == 0 && break
        if (p === nothing && TC < TCᵒ) || (p isa Int && length(y) < p)
            push!(y, i)
            ksum += k[i]
            c1 = min.(c1, @view C[i, :])
            TCᵒ = TC
            deleteat!(closed, findfirst(==(i), closed))
        else
            break
        end
    end
    sort!(y)
    return y, float(TCᵒ), _build_alloc(y, C)
end

"""
    ufldrop(k, C; y=nothing, p=nothing) -> (Vector{Int}, Float64, SparseMatrixCSC)

Greedy DROP construction heuristic for uncapacitated facility location.

Starts with every new facility (NF) open and iteratively closes the one giving the greatest
cost reduction until no improvement is possible. With `p`, it closes NFs until **exactly** `p`
remain, whether or not each closure lowers the cost.

# Arguments
- `k`: Fixed cost. Scalar (same cost at every NF site) or length-`n` vector, `k[i]` = cost
  of opening an NF at candidate site `i`. Must be non-negative.
- `C`: `n`×`m` variable-cost matrix over `n` candidate NF sites and `m` existing facilities
  (EFs); `C[i,j]` = cost of serving EF `j` from an NF at site `i`.
- `y`: indices of the initially-open NF sites (default: all NF sites open). The caller's
  vector is never changed.
- `p`: the number of NFs to leave open (default: `nothing`, drop until no improvement).
  Must be between 1 and `n`.

# Returns
- `(y, TC, W)`: indices of the open NF sites, **sorted**; total cost
  `TC = sum(k[y]) + sum(C[allocated])`; and the `n`×`m` sparse allocation matrix `W`,
  `W[i,j] = 1` if EF `j` is served by the NF at site `i` (a tie goes to the lower site index).

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

`p = 4` stops at four open sites on the same data, at a higher cost than the unconstrained
DROP reaches (Matlog's `ufldrop(k, C, [], 4)`):

```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y, TC, W = ufldrop(k, C; p = 4)
(y, TC)

# output

([1, 2, 4, 6], 37.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8; M.S. Daskin, *Network and Discrete Location*, 1995,
  Fig. 7.3. Ported from Matlog `ufldrop`.
"""
function ufldrop(k, C; y = nothing, p::Union{Int, Nothing} = nothing)
    n, m = size(C)
    k = _ufl_k(:ufldrop, k, n)
    y = (y === nothing || isempty(y)) ? collect(1:n) : _ufl_y(:ufldrop, y, n)
    _ufl_p(:ufldrop, p, n)
    TCᵒ = _ufl_cost(k, C, y)
    while length(y) > 1
        c1, c2, idx = _best2(C[y, :])          # dropping site a costs only the EFs it serves
        ksum = sum(k[y])
        TC, a = Inf, 0
        for a′ in eachindex(y)
            TC′ = ksum - k[y[a′]] + sum(ifelse.(idx .== a′, c2, c1))
            if TC′ < TC
                TC, a = TC′, a′
            end
        end
        if (p === nothing && TC < TCᵒ) || (p isa Int && length(y) > p)
            TCᵒ = TC
            deleteat!(y, a)
        else
            break
        end
    end
    sort!(y)
    return y, float(TCᵒ), _build_alloc(y, C)
end

"""
    uflxchg(k, C, y) -> (Vector{Int}, Float64, SparseMatrixCSC)

Pairwise EXCHANGE improvement heuristic for uncapacitated facility location.

Steepest-descent swaps — close one open new facility (NF), open one closed — from a starting
set `y` until a local optimum is reached: when it returns, no single swap of an open site for a
closed one lowers the total cost. The swap preserves the number of open NFs, so `y` sets the
cardinality.

With only one open site the procedure makes no swap and returns `y` as given, even where
another single site costs less. This is Matlog's rule (`uflxchg.m` starts its loop only when
`length(y) > 1`), so the local-optimality promise above holds for two or more open sites.
Use [`ufladd`](@ref) or [`pmedian`](@ref) to choose a single site.

# Arguments
- `k`: Fixed cost. Scalar (same cost at every NF site) or length-`n` vector (see [`ufladd`](@ref)).
- `C`: `n`×`m` variable-cost matrix over `n` candidate NF sites and `m` existing facilities
  (EFs); `C[i,j]` = cost of serving EF `j` from an NF at site `i`.
- `y`: indices of the starting open NF sites (required — exchange improves *this* set), any
  vector of integers: a range such as `2:3`, or `Int32` indices, as [`ufladd`](@ref) and
  [`ufldrop`](@ref) take theirs (v0.3.1, A8). The caller's vector is never changed.

# Returns
- `(y, TC, W)`: indices of the improved open NF sites, **sorted**; total cost
  `TC = sum(k[y]) + sum(C[allocated])`; and the `n`×`m` sparse allocation matrix `W`,
  `W[i,j] = 1` if EF `j` is served by the NF at site `i`.

Each pass scans every (open site, closed site) pair of the set it starts with and makes the
best swap, the first of equal ones in the order of `y` and then of the closed sites.

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

The starting set may be a range, here sites 1 to 2 (TC 37), improved to the same `[3, 6]`:

```jldoctest
k = [8, 8, 10, 8, 9, 8]
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y, TC, W = uflxchg(k, C, 1:2)
(y, TC)

# output

([3, 6], 31.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8; M.S. Daskin, *Network and Discrete Location*, 1995,
  Fig. 7.5. Ported from Matlog `uflxchg`.
"""
function uflxchg(k, C, y::AbstractVector{<:Integer})
    n, m = size(C)
    k = _ufl_k(:uflxchg, k, n)
    y = _ufl_y(:uflxchg, y, n)                 # a copy: the caller's `y` is never changed
    TCᵒ = _ufl_cost(k, C, y)
    while length(y) > 1                        # Matlog's guard (N24): no swap with a single open site
        c1, c2, idx = _best2(C[y, :])          # cost of the EFs an open site serves once it is closed
        ksum = sum(k[y])
        closed = setdiff(1:n, y)
        TC, a, j = Inf, 0, 0
        for a′ in eachindex(y)                 # scan the set as it stands: nothing moves during the scan
            c1a = ifelse.(idx .== a′, c2, c1)
            base = ksum - k[y[a′]]
            for j′ in closed
                TC′ = base + k[j′] + sum(min.(c1a, @view C[j′, :]))
                if TC′ < TC
                    TC, a, j = TC′, a′, j′
                end
            end
        end
        if TC < TCᵒ
            TCᵒ = TC
            y[a] = j                           # the new site takes the closed one's place
        else
            break
        end
    end
    sort!(y)
    return y, float(TCᵒ), _build_alloc(y, C)
end

"""
    ufl(k, C; verbose=true) -> (Vector{Int}, Float64, SparseMatrixCSC)

Hybrid UFL heuristic combining ADD, EXCHANGE, and DROP.

Iterates ADD → EXCHANGE → (ADD vs DROP, take best) until no improvement. Typically finds
a better solution than any single procedure alone. With the default `verbose=true`, prints
the per-step `Add`/`Xchg`/`Drop` cost trace, the one trace format of the location family
([`pmedian`](@ref) and [`ala`](@ref) print theirs the same way). The sites are returned sorted.

# Arguments
- `k`: Fixed cost. Scalar (same cost at every NF site) or length-`n` vector (see [`ufladd`](@ref)).
- `C`: `n`×`m` variable-cost matrix over `n` candidate new-facility (NF) sites and `m`
  existing facilities (EFs); `C[i,j]` = cost of serving EF `j` from an NF at site `i`.
- `verbose`: print the per-step cost trace (default: `true`).

# Returns
- `(y, TC, W)`: indices of the best open NF sites found, sorted; total cost
  `TC = sum(k[y]) + sum(C[allocated])`; and the `n`×`m` sparse allocation matrix `W`,
  `W[i,j] = 1` if EF `j` is served by the NF at site `i`.

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
y, TC, W = ufl(k, C)
(y, TC)

# output

  Add: 32.0
 Xchg: 31.0
  Add: 31.0
 Drop: 31.0
([3, 6], 31.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8; M.S. Daskin, *Network and Discrete Location*, 1995.
  Ported from Matlog `ufl`.
"""
function ufl(k, C; verbose = true)
    k = _ufl_k(:ufl, k, size(C, 1))
    y′, TC′, _ = ufladd(k, C)
    verbose && println("  Add: ", TC′)
    y, TC = y′, TC′
    done = false
    while !done
        y, TC, _ = uflxchg(k, C, y′)
        verbose && println(" Xchg: ", TC)
        if y != y′                       # the sites come back sorted, so `!=` compares the sets
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
    pmedian(p, C; verbose=true, construct=:add) -> (Vector{Int}, Float64, SparseMatrixCSC)

p-median facility location: open exactly `p` new facilities (NFs; no fixed costs) to minimize
total assignment cost. Constructs a set of `p` sites with [`ufladd`](@ref) (`k = 0`), then
improves it with [`uflxchg`](@ref). With `construct = :both` it also constructs from
[`ufldrop`](@ref) and improves that, and keeps the cheaper of the two (Matlog's `pmedian`).

# Arguments
- `p`: number of NFs to open, between 1 and `n`.
- `C`: `n`×`m` variable-cost matrix over `n` candidate NF sites and `m` existing facilities
  (EFs); `C[i,j]` = cost of serving EF `j` from an NF at site `i`.
- `verbose`: print the per-step cost trace, in the format of [`ufl`](@ref) (default: `true`,
  as at v0.2.8).
- `construct`: `:add` (default) improves ADD's `p` sites. With many candidate sites and few
  facilities (n ≫ p) DROP starts from all `n` sites and is the slow direction, so the default
  uses ADD alone. `:both` runs ADD → EXCHANGE and DROP → EXCHANGE and keeps the better; it can
  only improve the answer, and matters when `n` is close to `p`.

# Returns
- `(y, TC, W)`: indices of the `p` open NF sites, **sorted**; total cost `TC = sum(C[allocated])`
  (transport only, no fixed costs); and the `n`×`m` sparse allocation matrix `W`,
  `W[i,j] = 1` if EF `j` is served by the NF at site `i`.

# Example
Same cost matrix as Example 8.8 (Francis, 2nd ed.), with fixed costs dropped. The trace shows
the ADD cost (16) and then the EXCHANGE cost, which improves it to 13:

```jldoctest
C = [ 0  3  7 10  6  4
      3  0  4  7  6  7
      7  4  0  3  6  8
     10  7  3  0  7  8
      6  6  6  7  0  2
      4  7  8  8  2  0]
y, TC, W = pmedian(2, C)
(y, TC)

# output

  Add: 16.0
 Xchg: 13.0
([3, 6], 13.0)
```

`construct = :both` adds the DROP construction. On this 5×6 integer cost matrix (drawn once with
`Random.Xoshiro(2026)`, the instance of `test/test_loctools.jl`, in which ADD and DROP reach
different local optima) ADD → EXCHANGE stops at 28 and DROP → EXCHANGE at 25, which is kept:

```jldoctest
C = [ 4 15 14 20 11 11
     26 12 20  1  6 27
     16  2  1 22 30 27
     30 18 15 28 21  7
      6 29 11  2 10 13]
y, TC, W = pmedian(3, C; construct = :both)
(y, TC)

# output

  Add: 28.0
 Xchg: 28.0
 Drop: 25.0
 Xchg: 25.0
([1, 2, 3], 25.0)
```

# References
- R.L. Francis, L.F. McGinnis, J.A. White, *Facility Layout and Location: An Analytical
  Approach*, 2nd ed., Ex. 8.8 (cost matrix). Ported from Matlog `pmedian`, which prints
  `Add`, `Xchg`, `Drop`, `Xchg` and keeps the better of the two constructions.
"""
function pmedian(p, C; verbose = true, construct::Symbol = :add)
    n = size(C, 1)
    1 <= p <= n || error("p must be between 1 and $n")
    construct in (:add, :both) || error("pmedian: `construct` must be :add or :both (got $(repr(construct))).")
    y, TC, _ = ufladd(0, C; p = p)
    verbose && println("  Add: ", TC)
    y, TC, W = uflxchg(0, C, y)
    verbose && println(" Xchg: ", TC)
    if construct === :both
        y2, TC2, _ = ufldrop(0, C; p = p)
        verbose && println(" Drop: ", TC2)
        y2, TC2, W2 = uflxchg(0, C, y2)
        verbose && println(" Xchg: ", TC2)
        if TC2 < TC
            y, TC, W = y2, TC2, W2
        end
    end
    return y, TC, W
end

# =============================================================================
# Alternating Location–Allocation
# =============================================================================

# The metric kernel of `ala`'s locate step (A5), resolved once per call: the great circle for a unit, d1's
# arithmetic at `dist == 1` and d2's at `dist == 2` (also for the real 1.0 and 2.0, which `dists`, and so the
# allocate step, reads as the general metric: v0.3.0's `_aladist` did the same), the Chebychev distance at Inf
# (N31), and any other p ≥ 1 the general lₚ metric as `dists` computes it (new in v0.3.1; it was an error).
function _alakernel(dist)
    bad() = error("ala: `dist` must be :mi, :km, :rad or a real p ≥ 1 (got $(repr(dist))).")
    dist isa Symbol && return dist in (:mi, :km, :rad) ? _GC(dist) : bad()
    dist isa Real || bad()
    dist == 1 && return _L1()
    dist == 2 && return _L2()
    dist == Inf && return _Linf()
    p = dist isa Integer ? float(dist) : dist      # as `_dists` reads an integer p (N19)
    p >= 1 || bad()
    return _Lp(p)
end

# A draw from the caller's `rng`, or from the global stream exactly as v0.2.8 drew it (S5).
_rand(rng, dims...) = rng === nothing ? rand(dims...) : rand(rng, dims...)

# The orphan repair gives up after this many rounds (it would loop forever if two NFs could only ever
# sit on the same EF, e.g. n > the number of distinct EF locations).
const _ALA_MAXREPAIR = 1000

# Default allocate: assign each EF to its nearest NF and build the sparse n×m weight matrix. An NF that
# draws no demand (a zero row of `W`) is an orphan: with `repair` it is moved to a random EF and the EFs
# are re-allocated, until no NF is orphaned (Matlog's `default_alloc`; v0.2.8's draw, `sortperm(rand(m))`,
# is kept so a seeded run draws the same stream). Returns `(W, TC, X)` where `X` is the (possibly
# repaired) set of NF locations that `W` and `TC` belong to, so the cost is always the cost at the X
# returned (CR 4, D4).
function _ala_alloc(X, w, P, dist, rng, repair)
    m = length(w)
    Xw = Matrix{Float64}(X)
    wf = Float64.(collect(w))
    local W, D
    rounds = 0
    while true
        D = dists(Xw, P, dist)                          # n×m distance matrix (NF × EF)
        assign = [argmin(@view D[:, j]) for j in 1:m]
        W = sparse(assign, 1:m, wf, size(Xw, 1), m)
        idx0 = repair ? findall(iszero, vec(sum(W, dims=2))) : Int[]
        isempty(idx0) && break
        if (rounds += 1) > _ALA_MAXREPAIR
            @warn "ala: an NF is still allocated no EF after $_ALA_MAXREPAIR relocations; leaving it unused."
            break
        end
        perm = sortperm(_rand(rng, size(P, 1)))
        Xw[idx0, :] = P[perm[1:length(idx0)], :]
    end
    return W, sum(W .* D), Xw
end

# Default locate: per-NF continuous minisum. For each NF, minimise the weighted sum of
# distances to its allocated EFs via `Optim.optimize`. `k` is the resolved metric (`_alakernel`).
function _ala_locate(W, X, k, P)
    Xnew = copy(X)
    for i in axes(W, 1)
        J = findall(!iszero, @view W[i, :])
        isempty(J) && continue
        wi = [W[i, j] for j in J]
        x0 = Vector{Float64}(@view X[i, :])
        f(x) = sum(wi[t] * _pointdist(x, @view(P[J[t], :]), k) for t in eachindex(J))
        Xnew[i, :] = optimize(f, x0).minimizer
    end
    return Xnew
end

# One alternating location–allocation descent from a single start. `alloc_fn(X)` returns `(W, TC, X)`;
# `loc_cost(W, X)` is the cost of the allocation `W` at the located `X` (the locate step's cost), or
# `nothing` when a caller's own `alloc` makes that cost unknowable. With `verbose`, every allocate and
# every locate step prints its total cost (to four decimals, which hides the optimizer's last digits),
# in `ufl`'s format.
function _ala_run(X, alloc_fn, locate_fn, loc_cost, verbose)
    W, TC, X = alloc_fn(X)
    verbose && println(lpad("Alloc", 6), ": ", round(TC; digits=4))
    done = false
    while !done
        X1 = locate_fn(W, X)
        verbose && loc_cost !== nothing && println(lpad("Locate", 6), ": ", round(loc_cost(W, X1); digits=4))
        W1, TC1, X1 = alloc_fn(X1)
        verbose && println(lpad("Alloc", 6), ": ", round(TC1; digits=4))
        if TC1 < TC
            TC, X, W = TC1, X1, W1
        else
            done = true
        end
    end
    return X, TC, W
end

"""
    ala(X0, w, P; dist=:mi, unit, alloc=<default>, locate=<default>, nruns=1, verbose=true, rng=nothing) -> (X, TC, W)
    ala(X0, alloc::Function, P; dist=:mi, unit, locate, nruns, verbose, rng) -> (X, TC, W)
    ala(n::Integer, w, P; nruns, rng, ...) -> (X, TC, W)
    ala(x::AbstractVector, w, P; ...) -> (X, TC, W)

Alternating location–allocation: locate `n` new facilities (NFs) to serve `m` weighted
existing facilities (EFs).

Three more call forms (A7), each the first form on other arguments:
- `ala(X0, alloc, P)`: a caller's allocate function in the place of `w`, as Matlog's
  `ala(X0, alloc_h, P, p)`; it is `ala(X0, w, P; alloc)`, whose `w` the default allocate alone
  reads.
- `ala(n, w, P)`: `n` NFs from a random start, `ala(randX(P, n; rng), w, P; rng)`, so the
  generator (or, with none, the global stream) draws the start and then the restarts and the
  repair, exactly as the course's `ala(randX(P, n), w, P)` does after the same seed.
- `ala(x, w, P)`: one NF from the point `x`, a vector, as `ala(reshape(x, 1, :), w, P)`; a
  vector is one point here, as in [`dists`](@ref) (S15).
`ala(n, alloc, P)` and `ala(x, alloc, P)` combine them.

Starting from `n` NF locations `X0`, alternate two steps until the total cost `TC` stops
decreasing: **allocate** each EF to its nearest NF, then **locate** each NF at the continuous
minisum of its allocated EFs. An NF that no EF is nearest to (an orphan) is moved to a random
EF and the EFs are re-allocated, so every NF returned serves some EF (Matlog's `default_alloc`).
The returned `TC` and `W` are always those of the returned `X`.

# Formulation
Given EFs ``P = \\{P_j\\}_{j=1}^m``, weights ``w_j \\ge 0``, and ``n`` NFs, choose NF
locations ``X = \\{X_i\\}_{i=1}^n \\subset \\mathbb{R}^2`` and allocation
``W \\in \\{0,1\\}^{n \\times m}`` to minimise

```math
\\min_{X,\\,W}\\; TC = \\sum_{j=1}^{m} w_j\\, d\\!\\left(X_{\\sigma(j)}, P_j\\right),
\\qquad \\sigma(j) = \\arg\\min_i d(X_i, P_j),
```

alternating

- **allocate:** ``\\sigma(j) = \\arg\\min_i d(X_i, P_j)`` (nearest NF);
- **locate:** ``X_i \\leftarrow \\arg\\min_{X} \\sum_{j:\\sigma(j)=i} w_j\\, d(X, P_j)``
  (per-NF minisum),

iterating until ``TC`` is non-decreasing. If ``\\{j : \\sigma(j) = i\\} = \\varnothing`` for
some ``i``, ``X_i`` is relocated to a random ``P_j`` and the EFs are re-allocated, until every NF
is used. The distance ``d`` defaults to the great-circle distance ``d_{gc}`` (`dist=:mi`). With
`nruns` random starts, the minimum-`TC` result is returned.

# Arguments
- `X0`: n×2 matrix of initial NF locations (LON, LAT).
- `w`: length-m weight vector (`w_j ≥ 0`).
- `P`: m×2 matrix of EF locations (LON, LAT).
- `dist`: distance metric — `:mi` (default), `:km`, `:rad` (great-circle), or `1`/`2`/`Inf`
  (rectilinear/Euclidean/Chebyshev), or any real `p ≥ 1` (the lₚ metric, as [`dists`](@ref)
  computes it; v0.3.1, A5): what `dists` accepts.
- `unit`: a synonym for `dist` when it is a great-circle unit, as in `dists` (S15); passing both
  is an error.
- `alloc`: allocate handle `X -> (W, TC)` overriding the default nearest-NF allocation
  (e.g. for forced/constrained partitions).
- `locate`: locate handle `(W, X) -> X` overriding the default per-NF minisum.
- `nruns`: number of independent restarts. Run 1 uses `X0`; runs 2…`nruns` use fresh
  `randX(P, n)` starts. The best (minimum-`TC`) result is returned.
- `verbose`: print the cost trace (default: `true`); see below.
- `rng`: a random-number generator (any `AbstractRNG`) for the restarts and the orphan
  repair, as in `rng = Xoshiro(1)`. The default, `nothing`, draws from the global stream
  exactly as v0.2.8 did, so `Random.seed!(s)` before the call reproduces the same run; a
  generator passed here leaves the global stream untouched. The keyword is typed
  `Union{Nothing,AbstractRNG}`, so any other value is a `TypeError` at the call (LOC8).

A caller's own handle is never second-guessed. The orphan repair belongs to the default
allocate step, so it is skipped when `alloc` is given (a forced partition may leave an NF
empty on purpose) and when `locate` is given (a locate handle may hold an NF fixed, as in HW 1's
fixed facility, and the repair would otherwise move it).

# Trace
With `verbose = true`, every allocate and every locate step prints the total cost after the
step, in the format of [`ufl`](@ref)'s trace: `Alloc` after allocating, `Locate` after locating
(the allocation held, the NFs moved), and, when `nruns > 1`, a `k: TC = ...` line closing each
run and a `Final: TC = ...` line with the best. With a caller's `alloc` the `Locate` lines are
omitted, since only that handle can cost an allocation.

# Returns
- `(X, TC, W)`: n×2 NF locations, total cost `TC`, and the n×m sparse allocation matrix `W`
  where `W[i,j]` is the weight NF `i` serves from EF `j`.

# Example
Two NFs on the I-40 mile markers of Lecture 2.3's first location–allocation example, 1-D
rectilinear distance (`dist = 1`), from the starts 0 and 200. Each allocate and each locate step
prints its cost; the NFs settle on the markers 190 and 295, at a total cost of 1,340.

```jldoctest
P = [50 150 190 220 270 295 420]'          # I-40 mile markers
w = collect(1:7)                           # relative demand at each
X, TC, W = ala([0.0; 200.0;;], float(w), float(P); dist = 1)
(round.(vec(X)), round(TC))

# output

 Alloc: 2720.0
Locate: 1880.0
 Alloc: 1840.0
Locate: 1715.0
 Alloc: 1500.0
Locate: 1340.0
 Alloc: 1340.0
Locate: 1340.0
 Alloc: 1340.0
([190.0, 295.0], 1340.0)
```

The other call forms on the same corridor. A caller's allocation in the place of `w`, here a
contract that has the first five towns served by NF 1 and the last two by NF 2 (`W` carries the
weights, and only the locate step moves the NFs), costs more than the 1,340 above; one NF from
the point 200; and two NFs from a random start, which is the course's `randX` idiom drawn from
the same generator:

```jldoctest
using Random, SparseArrays
P = [50 150 190 220 270 295 420]'          # I-40 mile markers
w = collect(1:7)
Wc = sparse([1, 1, 1, 1, 1, 2, 2], 1:7, float(w), 2, 7)
contract(X) = (Wc, sum(Wc .* dists(X, P, 1)))
X, TC, W = ala([0.0; 200.0;;], contract, P; dist = 1, verbose = false)
x1, TC1, _ = ala([200.0], float(w), float(P); dist = 1, verbose = false)
r1, r2 = Xoshiro(1), Xoshiro(1)
a = ala(2, float(w), float(P); dist = 1, rng = r1, verbose = false)
b = ala(randX(P, 2; rng = r2), float(w), float(P); dist = 1, rng = r2, verbose = false)
(round.(vec(X)), round(TC), round.(vec(x1)), round(TC1), a == b)

# output

([220.0, 420.0], 1400.0, [270.0], 2100.0, true)
```

Locate three NFs to serve six North Carolina cities. With `nruns=2` restarts the runs land in
different local optima, so the minimum-`TC` result is returned. Each run prints its `Alloc` and
`Locate` steps as above and then a line of its own; pass `rng` for a reproducible run (exact
values depend on the Julia RNG version).

```julia
using Random
# Raleigh, Charlotte, Greensboro, Wilmington, Asheville, Fayetteville (LON, LAT)
P  = [-78.64 35.78; -80.84 35.23; -79.79 36.07; -77.94 34.23; -82.55 35.60; -78.88 35.05]
w  = [469.0, 897.0, 299.0, 123.0, 94.0, 208.0]    # ~population weights
X0 = [-78.6 35.8; -80.0 35.5; -82.0 35.6]          # three NF starts
X, TC, W = ala(X0, w, P; nruns=2, rng=Xoshiro(7))   # dist=:mi great-circle minisum
# prints, after each run's Alloc and Locate steps:
#   1: TC = 45055.8
#   2: TC = 39093.4
#   Final: TC = 39093.4
round(TC; digits=1)                 # => 39093.4
```

# References
- M.G. Kay, *Facility Location* (course notes), NC State University, Lecture 2.3 (the I-40
  example); Matlog `ala` and `default_alloc`.
"""
function ala(X0, w, P; dist=nothing, unit=nothing, alloc=nothing, locate=nothing, nruns::Int=1,
             verbose::Bool=true, rng::Union{Nothing,AbstractRNG}=nothing)
    return _ala(X0, w, P, dist, unit, alloc, locate, nruns, verbose, rng)
end

# A7 (v0.3.1): a caller's allocate in the place of `w` (Matlog's `ala(X0, alloc_h, P, p)`), a random start of
# `n` NFs, and one NF from a point; and the two combinations, which also keep the forms unambiguous.
function ala(X0, alloc::Function, P; dist=nothing, unit=nothing, locate=nothing, nruns::Int=1,
             verbose::Bool=true, rng::Union{Nothing,AbstractRNG}=nothing)
    return _ala(X0, nothing, P, dist, unit, alloc, locate, nruns, verbose, rng)
end

ala(n::Integer, w, P; rng::Union{Nothing,AbstractRNG}=nothing, kwargs...) =
    ala(randX(P, Int(n); rng), w, P; rng, kwargs...)
ala(n::Integer, alloc::Function, P; rng::Union{Nothing,AbstractRNG}=nothing, kwargs...) =
    ala(randX(P, Int(n); rng), alloc, P; rng, kwargs...)
ala(x::AbstractVector, w, P; kwargs...) = ala(reshape(x, 1, :), w, P; kwargs...)
ala(x::AbstractVector, alloc::Function, P; kwargs...) = ala(reshape(x, 1, :), alloc, P; kwargs...)

# The body of every form; `w` is `nothing` when the allocate step is the caller's.
function _ala(X0, w, P, dist, unit, alloc, locate, nruns, verbose, rng)
    size(X0, 2) == size(P, 2) || error("ala: X0 and P must have the same number of columns.")
    w === nothing || length(w) == size(P, 1) || error("ala: length(w) must equal the number of rows in P.")
    n = size(X0, 1)
    n <= size(P, 1) || error("ala: number of NFs (n=$n) cannot exceed number of EFs (m=$(size(P, 1))).")
    nruns >= 1 || error("ala: nruns must be ≥ 1.")
    # the metric as `dists` reads it (A5): `dist` or its synonym `unit`, the great circle in miles by default
    metric = dist === nothing && unit === nothing ? :mi : _metric(dist, unit; fn = :ala, pname = :dist)

    if alloc === nothing
        repair = locate === nothing
        alloc_fn = X -> _ala_alloc(X, w, P, metric, rng, repair)
        loc_cost = (W, X) -> sum(W .* dists(X, P, metric))
    else
        alloc_fn = X -> (r = alloc(X); (r[1], r[2], X))
        loc_cost = nothing
    end
    if locate === nothing
        k = _alakernel(metric)                      # resolved and checked once per call
        k isa _GC && size(P, 2) != 2 && error("Inputs must have length 2.")
        locate_fn = (W, X) -> _ala_locate(W, X, k, P)
    else
        locate_fn = locate
    end

    bestX = bestW = nothing
    bestTC = Inf
    for run in 1:nruns
        Xstart = run == 1 ? Matrix{Float64}(X0) : Matrix{Float64}(randX(P, n; rng))
        X, TC, W = _ala_run(Xstart, alloc_fn, locate_fn, loc_cost, verbose)
        verbose && nruns > 1 && println("  ", run, ": TC = ", round(TC; digits=1))
        if TC < bestTC
            bestTC, bestX, bestW = TC, X, W
        end
    end
    verbose && nruns > 1 && println("  Final: TC = ", round(bestTC; digits=1))
    return bestX, bestTC, bestW
end

# =============================================================================
# Utility Functions
# =============================================================================

"""
    randX(P::AbstractMatrix, n::Int=1; rng=nothing) -> Matrix

Generate n random points within the bounding box of point set P.

Useful for generating random facility locations for optimization problems.

# Arguments
- `P`: m×d matrix of m points in d dimensions.
- `n`: Number of random points to generate (default: 1).
- `rng`: a random-number generator (any `AbstractRNG`), as in `rng = Xoshiro(1)`. The default,
  `nothing`, draws from the global stream exactly as v0.2.8 did (`rand(n, d)`, all `n` first
  coordinates and then all `n` second ones), so `Random.seed!(s)` before the call reproduces the
  same points, the draws behind HW 1 Q5 and Lectures 2.3 and 2.4. A generator passed here leaves
  the global stream untouched. Typed `Union{Nothing,AbstractRNG}`, as `ala`'s is (LOC11).

# Returns
- n×d matrix of random points, uniformly distributed within min/max of each dimension.

# Example
`randX` draws from the RNG, so the coordinates vary run to run (and the exact stream is not
stable across Julia versions); only the shape is fixed. Seed for reproducibility within a
session, or pass a generator of your own.

```julia
using Random; Random.seed!(1)
P = [0 0; 2 0; 2 3]
X = randX(P, 5)      # 5 random points in [0,2] × [0,3]
size(X)              # => (5, 2)
```

With the same generator the points are the same, whatever the global stream does:

```jldoctest
using Random
P = [0 0; 2 0; 2 3]
randX(P, 5; rng = Xoshiro(1)) == randX(P, 5; rng = Xoshiro(1))

# output

true
```
"""
function randX(P::AbstractMatrix, n::Int=1; rng::Union{Nothing,AbstractRNG}=nothing)
    n >= 1 || error("n must be positive")
    size(P, 1) >= 1 || error("P must have at least one point")

    if size(P, 1) == 1
        return repeat(P, n)
    else
        mins = minimum(P, dims=1)
        ranges = maximum(P, dims=1) - mins
        return mins .+ _rand(rng, n, size(P, 2)) .* ranges
    end
end

"""
    wcentroid(LON, LAT, w) -> (LON, LAT)
    wcentroid(P::AbstractMatrix, w) -> (LON, LAT)

Weighted geographic centroid of points `(LON, LAT)` with weights `w`, corrected for
longitude convergence toward the poles by a `cos(lat)` factor. The points may also be given
as the n×2 matrix `P` the distance and location functions take, `wcentroid(P, w)` being
`wcentroid(P[:, 1], P[:, 2], w)` (v0.3.1, A8).

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
- `P`: in place of `LON` and `LAT`, an n×2 matrix of points (LON, LAT).
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

The same centroid from the matrix of points, the form of Lecture 2.2's and 2.6's
`c0 = wcentroid(P[:, 1], P[:, 2], wTL)`:

```jldoctest
P = [-78.64 35.78; -80.84 35.23; -79.79 36.07; -77.94 34.23]
r = wcentroid(P, [469.0, 897.0, 299.0, 123.0])
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

function wcentroid(P::AbstractMatrix, w)
    size(P, 2) == 2 || throw(ArgumentError("wcentroid: P must have two columns, LON and LAT (got $(size(P, 2)))."))
    return wcentroid(P[:, 1], P[:, 2], w)
end
