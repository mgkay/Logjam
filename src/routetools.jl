# RouteTools - Functions for vehicle routing problems

# =============================================================================
# Route Cost Calculations
# =============================================================================

"""
    segcost(loc, C) -> Vector

Calculate the cost of each segment in a location sequence.

Returns a vector of costs for traveling between consecutive locations.

# Arguments
- `loc`: Vector of location indices representing a sequence of stops.
- `C`: Cost matrix where C[i,j] is the cost from location i to location j.

# Returns
- Vector of segment costs of length `length(loc) - 1`.

# Example
```jldoctest
julia> C = [0 10 20; 10 0 15; 20 15 0];    # 3x3 cost matrix

julia> loc = [1, 2, 3, 1];                 # Tour visiting all nodes

julia> segcost(loc, C)
3-element Vector{Int64}:
 10
 15
 20
```
"""
segcost(loc, C) = map(i -> C[loc[i], loc[i+1]], 1:length(loc) - 1)

# `rteTC`, the total cost of a route, is defined with the checks it carries below (after `scanTW`).

# =============================================================================
# Route Representation
# =============================================================================

"""
    isorigin(rte) -> Vector{Bool}

Determine which positions in a route are origins (first occurrence).

For routes with pickup-delivery pairs, each shipment index appears twice.
This function identifies which occurrence is the pickup (origin).

# Arguments
- `rte`: Route as a vector of shipment indices.

# Returns
- Boolean vector where `true` indicates first occurrence (origin/pickup).

# Example
```jldoctest
julia> rte = [1, 2, 1, 3, 2, 3];    # Pickup 1, pickup 2, deliver 1, pickup 3, deliver 2, deliver 3

julia> isorigin(rte)               # true, true, false, true, false, false
6-element Vector{Bool}:
 1
 1
 0
 1
 0
 0
```
"""
isorigin(rte) = begin
    seen = Set{eltype(rte)}()
    [i ∉ seen ? (push!(seen, i); true) : false for i in rte]
end

"""
    rte2loc(rte, sh, tr = (;)) -> Vector
    rte2loc(R, sh, tr = (;)) -> Vector{Vector}

Convert a route to a location sequence, or each route of a vector of routes `R`, such as `savings`
returns, to its own.

Maps shipment indices in a route to their actual node locations,
using pickup location for origins and delivery location for destinations.

# Arguments
- `rte`: Route as a vector of shipment indices. `R`: a vector of routes.
- `sh`: Shipments table with columns `b` (begin/pickup) and `e` (end/delivery) node indices.
- `tr`: Named tuple with the truck's locations `(b=start_nodes, e=end_nodes)`, each a node or a
  vector of nodes, put before and after the route's own; each is read only if `tr` has it, so a
  truck with only a capacity, `(Kwt = 25,)`, adds nothing (it threw a `FieldError` in v0.2.8). Default
  `(;)`.

# Returns
- Vector of node indices representing the physical locations visited. With the default `tr` it is
  a `Vector{Int}` when `sh.b` and `sh.e` are integer columns (v0.2.8 returned a `Vector{Any}`, N20).

# Example
```jldoctest
julia> using DataFrames

julia> sh = DataFrame(b=[10, 20], e=[15, 25]);    # 2 shipments

julia> rte = [1, 2, 1, 2];                         # Pickup both, then deliver both

julia> rte2loc(rte, sh)
4-element Vector{Int64}:
 10
 20
 15
 25
```

A vector of routes gives a location sequence for each, as Lecture 5.3's `[rte2loc(r, shcw, tr) for r in R1]`
(Code block 4) does:

```jldoctest
julia> using DataFrames

julia> sh = DataFrame(b = [10, 20], e = [15, 25]);

julia> rte2loc([[1, 1], [2, 2]], sh, (b = 1, e = 1))
2-element Vector{Vector{Int64}}:
 [1, 10, 15, 1]
 [1, 20, 25, 1]
```

# Notes
- A route that leaves the truck's location, returns to it, and leaves again (a depot route with
  two trips, `tr.b == tr.e`) is returned as it is, and `rteTC` prices it. Matlog's `rte2loc`
  returns `NaN` for it, and the checked route cost `rteTC(...; full = true)` refuses it with the exit flag -1
  (Matlog's rule, `Logjam._isdegenerate`).
"""
rte2loc(rte, sh, tr = (;)) = _rte2loc(rte, sh.b, sh.e, tr)
rte2loc(R::AbstractVector{<:AbstractVector{<:Integer}}, sh, tr = (;)) = [rte2loc(r, sh, tr) for r in R]

# the kernel over typed columns (a function barrier: `sh.b` of a DataFrame is not inferable); the truck's
# locations are read only when `tr` has them, as Matlog's rte2loc reads them with `isfield`
function _rte2loc(rte, b, e, tr)
    loc = ifelse.(isorigin(rte), b[rte], e[rte])
    return vcat(get(tr, :b, empty(loc)), loc, get(tr, :e, empty(loc)))
end

# the cost of each segment of a location sequence
_rtesegcost(loc, C) = [loc[i] == loc[i+1] ? zero(eltype(C)) : C[loc[i], loc[i+1]] for i in 1:length(loc)-1]

# Matlog's degenerate location vector (rte2loc.m): with the truck's begin and end the same location, a
# route that is at that location, leaves it, comes back and leaves again is more than one route. `loc`
# is the route's own location sequence, without the truck's. A route that starts there and ends there
# (leave once, return once) is not degenerate, nor is one that never visits it.
function _isdegenerate(loc, tr)
    (haskey(tr, :b) && haskey(tr, :e) && tr.b == tr.e && !isempty(tr.b)) || return false
    k = filter(!=(0), diff(loc .== tr.b))
    return length(k) > 2 || (length(k) == 2 && k != [-1, 1])
end

# =============================================================================
# What is on board: one scan behind rtesegsum, rtesegid, rte2ldmx and the empty-truck test
# =============================================================================

# The one scan of a route: which of its stops are loadings, the first appearance of each shipment. A
# shipment number indexes a Bool vector as long as the range of the route's shipment numbers, so a scan
# builds no Set (a Set per call was 0.5 microsecond on 60 stops, the cost of 2-opt's empty-truck test).
# Everything that is on board over a segment is read from it.
function _isload(rte::AbstractVector)
    n = length(rte)
    isL = Vector{Bool}(undef, n)
    n == 0 && return isL
    lo, hi = extrema(rte)
    seen = fill(false, hi - lo + 1)
    for k in 1:n
        i = rte[k] - lo + 1
        isL[k] = !seen[i]
        seen[i] = true
    end
    return isL
end

# a shipment is on board over every segment of the route vector r (the truck is never empty between
# stops): all(>(0), rtesegsum(r)), without the sums
function _loaded_throughout(r::AbstractVector)
    isL = _isload(r)
    onboard = 0
    for k in 1:length(r)-1
        onboard += isL[k] ? 1 : -1
        onboard > 0 || return false
    end
    return true
end

"""
    rtesegsum(rte, x = ones) -> Vector

The sum of a value of each shipment over each segment of a route: Matlog's `rtesegsum`, the cumulative
sum of `x` over the shipments on board, added at a shipment's loading and subtracted at its unloading.

With the default `x`, a 1 for each shipment, it is the number of shipments on the truck over each
segment; with each shipment's weight it is the weight on board. A route is a vector in which the truck
is never empty over a segment, so `all(>(0), rtesegsum(rte))` tests that a vector is a route, which is
how route 2-opt skips a reversal that leaves the truck empty between shipments (Lecture 5.2, Code
block 4).

# Arguments
- `rte`: Route, a vector of shipment numbers, the first appearance of each a loading and the second its
  unloading. Any route: it need not be normalized (Matlog's `rtesegsum` refuses an unnormalized one).
- `x`: (optional) a value for each shipment, **indexed by shipment number**: `x[k]` for shipment `k`.
  It may be longer than the largest shipment number.

# Returns
- A vector of length `length(rte) - 1`, one value for each segment between consecutive stops. Its
  element type is that of `x` (an integer vector for the default).

# Example
```jldoctest
julia> rtesegsum([1, 2, 1, 3, 2, 3], [10, 10, 10])    # Lecture 5.3 Ex. 3: tons on board, 10 t each
5-element Vector{Int64}:
 10
 20
 10
 20
 10

julia> rtesegsum([1, 1, 2, 2, 3, 3])                  # shipments on board: the truck is empty twice
5-element Vector{Int64}:
 1
 0
 1
 0
 1
```

# Notes
- Source: Matlog's `rtesegsum.m` and Lecture 5.2's Code block 4 (Lecture 5.3's Code block 3), whose
  `rtesegsum(r, x)` it equals on the lectures' routes. Matlog's `xsh` is indexed by shipment number
  too, but only for a normalized route and with exactly one value for each shipment. The lectures' own
  definition, written after `using Logjam`, still runs.
"""
function rtesegsum(rte::AbstractVector{<:Integer}, x::AbstractVector)
    isL = _isload(rte)
    T = promote_type(eltype(x), Int)
    v = Vector{T}(undef, length(rte))
    for k in eachindex(rte)
        xk = convert(T, x[rte[k]])
        v[k] = isL[k] ? xk : -xk
    end
    y = cumsum(v)                 # over every stop and then the last dropped, as the lectures' cumsum is,
    isempty(y) || pop!(y)         # since for floats cumsum is not a left-to-right sum and its bits depend on the length
    return y
end
rtesegsum(rte::AbstractVector{<:Integer}) = rtesegsum(rte, ones(Int, maximum(rte; init = 0)))

"""
    Logjam.rtesegid(rte) -> Vector{Vector{Int}}

Internal: not exported and not `public` (ruling IN5), so it is called as `Logjam.rtesegid`.

The shipments on board over each segment of a route, Matlog's `rtesegid`: for each segment between
consecutive stops, the shipments that have been loaded and not yet unloaded, in **increasing shipment
order**.

# Arguments
- `rte`: Route, a vector of shipment numbers, the first appearance of each a loading and the second its
  unloading. Any route, normalized or not.

# Returns
- A vector of length `length(rte) - 1`; element `k` is the sorted vector of the shipments on board over
  segment `k`. Matlog returns the same as an `m x (2m - 1)` logical matrix with a row for each
  shipment of a normalized route; the shipments of column `k` are `findall(L[:, k])`.

# Example
```jldoctest
julia> Logjam.rtesegid([1, 2, 1, 3, 2, 3])        # Lecture 5.3's load mix figure: two load mixes, {1, 2} and {2, 3}
5-element Vector{Vector{Int64}}:
 [1]
 [1, 2]
 [2]
 [2, 3]
 [3]
```

# Notes
- Source: Matlog's `rtesegid.m`; the sets are those Lecture 5.3's load mix figure draws over each
  segment of a route (its `onboard(k)`).
- `rte2ldmx` lists the sets at the peaks of this list, in the order loaded.
"""
function rtesegid(rte::AbstractVector{<:Integer})
    isL = _isload(rte)
    on = Int[]
    L = Vector{Vector{Int}}(undef, max(length(rte) - 1, 0))
    for k in eachindex(L)
        i = searchsortedfirst(on, rte[k])
        isL[k] ? insert!(on, i, rte[k]) : deleteat!(on, i)
        L[k] = copy(on)
    end
    return L
end

# =============================================================================
# The shipments of a route, and the routes of a set of shipments
# =============================================================================

"""
    rte2idx(rte) -> Vector
    rte2idx(R) -> Vector{Vector}

The shipments on a route, in the order they are loaded, Matlog's `rte2idx`: `rte[isorigin(rte)]`. For a
vector of routes `R` it is the vector of those, one for each route.

# Arguments
- `rte`: Route, a vector of shipment numbers, the first appearance of each a loading.
- `R`: A vector of routes.

# Example
```jldoctest
julia> rte2idx([23, 15, 6, 23, 27, 17, 24, 27, 15, 17, 6, 24])    # Matlog's help example
6-element Vector{Int64}:
 23
 15
  6
 27
 17
 24

julia> rte2idx([[1, 2, 1, 2], [3, 3]])                              # a vector of routes
2-element Vector{Vector{Int64}}:
 [1, 2]
 [3]
```

# Notes
- Source: Matlog's `rte2idx.m` and Lecture 5.2's Code block 49, whose two methods it is. A lecture
  that defines its own `rte2idx` after `using Logjam` still runs.
"""
rte2idx(rte::AbstractVector{<:Integer}) = rte[isorigin(rte)]
rte2idx(R::AbstractVector{<:AbstractVector{<:Integer}}) = rte2idx.(R)

"""
    sh2rte(idx, R = []) -> (rte = R′, idx1 = idx1)
    sh2rte(sh, R) -> (rte = R′, idx1 = idx1)

Make a route of its own for each shipment that is on no route, Matlog's `sh2rte`: the single-shipment
route `[k, k]` is added after the routes of `R` for each shipment `k` of `idx` that no route of `R`
carries. It is the step after `savings`, which returns only the routes it forms (CR 57), and it makes
the whole set of shipments one vector of routes, each shipment on exactly one, a single-shipment route
standing for a shipment shipped independently (Lecture 5.2, Ex. 9).

# Arguments
- `idx`: The shipments, a vector of shipment numbers; a shipment table `sh` stands for `1:nrow(sh)`.
- `R`: (optional) the existing routes, a vector of routes. Default none.

# Returns
- The named tuple `(rte, idx1)`, which destructures as `R, idx1 = sh2rte(...)`: `rte` is the routes of
  `R` followed by the routes added, and `idx1` the **shipments** that were added a route (not the
  positions of the routes), in increasing order, as Matlog's `setdiff` returns them.

# Example
```jldoctest
julia> R, idx1 = sh2rte(1:5, [[1, 2, 1, 2]]);      # Lecture 5.2 Code block 49: 1 and 2 on one route

julia> idx1
3-element Vector{Int64}:
 3
 4
 5

julia> R
4-element Vector{Vector{Int64}}:
 [1, 2, 1, 2]
 [3, 3]
 [4, 4]
 [5, 5]
```

# Notes
- Source: Matlog's `sh2rte.m` (`sh2rte(sh, rte)` is its second form, the shipments of the table) and
  Lecture 5.2's Code block 49, whose `sh2rte(idx, R)` it equals on the lecture's inputs.
  With `twoopt(R, rTCh)` it is Lecture 5.2's load formation in two lines:
  `R, TC = twoopt(savings(rteTCh, sh), rteTCh); R, idx1 = sh2rte(sh, R)`. Matlog's optional third argument, a cost handle used only to print the routes
  added, is left out. `idx1` is sorted, as MATLAB's `setdiff` is; the lecture's definition returns
  `idx`'s own order, the same for `1:n`.
- A shipment on a route of `R` is not checked to be on only one.
"""
function sh2rte(idx::AbstractVector{<:Integer}, R::AbstractVector{<:AbstractVector{<:Integer}})
    idx1 = sort!(setdiff(idx, reduce(vcat, R; init = Int[])))
    return (rte = [R; [[k, k] for k in idx1]], idx1 = idx1)
end
sh2rte(idx::AbstractVector{<:Integer}) = sh2rte(idx, Vector{Int}[])
sh2rte(sh::AbstractDataFrame, R = Vector{Int}[]) = sh2rte(1:nrow(sh), R)

# =============================================================================
# The checked route cost (Matlog's rteTC), under the name Lecture 5.3 gives it
# =============================================================================

"""
    rte2ldmx(rte) -> Vector{Vector{Int}}

The shipments on board at each **load mix** of a route: the set carried between a loading and the
next unloading, Matlog's `rte2ldmx` (the general branch of `rte2ldmx.m`).

A truck's capacity is checked on each load mix, not on the route's total. On a route whose
shipments are loaded at different places the truck is never loaded with all of them at once, so
the whole route's weight is the wrong test; on a depot route, where everything is loaded first,
there is one load mix and the two tests agree (Lecture 5.3 Sec. 3). `rteTC` uses it for its
capacity check.

# Arguments
- `rte`: Route, a vector of shipment indices, the first appearance of each a loading and the
  second its unloading.

# Returns
- A vector with one vector of shipment indices for each load mix, in the order they are loaded;
  the shipments of a mix are in the order loaded, less those unloaded since.

# Example
```jldoctest
julia> rte2ldmx([1, 2, 3, 3, 2, 1])      # Lecture 5.3 Ex. 3: all three loaded, then all unloaded
1-element Vector{Vector{Int64}}:
 [1, 2, 3]

julia> rte2ldmx([1, 2, 1, 3, 2, 3])      # the same shipments, two load mixes
2-element Vector{Vector{Int64}}:
 [1, 2]
 [2, 3]
```

# Notes
- Source: Lecture 5.3's `rte2ldmx` (Code block 15), Matlog's `rte2ldmx.m`. It is read from the same
  scan as `rtesegsum`, the shipments on board over the segment at each peak.
"""
function rte2ldmx(rte::AbstractVector)
    isL, on, ld = _isload(rte), Int[], Vector{Int}[]
    for i in 1:length(rte)-1
        isL[i] ? push!(on, rte[i]) : filter!(!=(rte[i]), on)
        isL[i] && !isL[i+1] && push!(ld, copy(on))
    end
    return ld
end

"""
    Logjam.scanTW(t, u, ℓ, h) -> (TC, a, b, c)

The three scans that find a route's least time within its time windows, Lecture 5.3's
implementation of the time-window scan (slide 254's rows a, b, c); `rteTC(...; full = true)` calls it for a route
with time windows.

For the stops `k = 1, ..., n` of a location sequence (the first and last the truck's location):
`t[k]` is the travel time into stop `k` (`t[1] = 0`), `u[k]` the loading or unloading time there,
`ℓ[k]` the opening and `h[k]` the closing of its window (`-Inf` and `Inf` for none).

- **a**, the forward scan, starts at the opening of the first stop's window and finds the earliest
  each stop can be served, waiting where a window has not opened; the service must end by `h[k]`,
  and a stop for which it cannot makes the route infeasible.
- **b**, the reverse scan, goes back from the last stop's earliest time and finds the latest each
  stop can be served; `b[1]` is the latest the route can start.
- **c**, the forward scan again from `b[1]`, is the schedule, with the waits made as late as possible.

# Returns
- `(TC, a, b, c)`: `TC = a[n] + u[n] - b[1]`, the route's least time, its earliest finish less its
  latest start; `NaN` when no stop has a window (all `ℓ = -Inf`), which `rteTC` replaces by the
  sum of travel and service times. `(Inf, a, a, a)` when a window closes before the stop can be served.

# Example
```jldoctest
julia> t = [0, 1, 2, 1, 1]; lo = [6, 8, 12, 15, 18]; hi = [18, 11, 14, 18, 24];

julia> TC, a, b, c = Logjam.scanTW(t, zeros(5), lo, hi);

julia> TC, c
(8.0, [10.0, 11.0, 13.0, 15.0, 18.0])
```

# Notes
- Source: Lecture 5.3 Ex. 4's data (slide 254) and Code block 28. **Declared `public`, not
  exported** (D10): the scan is the implementation rung of a model Lecture 5.3 teaches, so the
  lecture's own `scanTW`, defined after `using Logjam`, does not collide with it.
- The additions are made left to right, `a[k-1] + u[k-1] + t[k]`: the order of addition is part of
  the contract (a different order moves a windowed route's time in the last places and, through
  `isinf`, can move which route is feasible).
"""
function scanTW(t, u, ℓ, h)
    n = length(t)
    a = zeros(n); a[1] = ℓ[1]
    for k in 2:n
        a[k] = max(a[k-1] + u[k-1] + t[k], ℓ[k])
        a[k] + u[k] > h[k] && return Inf, a, a, a
    end
    b = zeros(n); b[n] = a[n]
    for k in n-1:-1:1
        b[k] = min(b[k+1] - t[k+1] - u[k], h[k] - u[k])
    end
    c = zeros(n); c[1] = b[1]
    for k in 2:n
        c[k] = max(c[k-1] + u[k-1] + t[k], ℓ[k])
    end
    return a[n] + u[n] - b[1], a, b, c
end

"""
    rteTC(rte, sh, C, tr = (;); full = false) -> Float64
    rteTC(rte, sh, C, tr; full = true) -> (TC, Xflg, out)
    rteTC(R, sh, C, tr; full = false) -> Vector, or with `full = true` (TC, Xflg, out) of vectors

The total cost of a route, Matlog's `rteTC` ported whole: the sum of the costs between the stops of
the route's location sequence, with the truck's capacity, a maximum cost and, when asked for, loading
and unloading times and time windows checked. A vector of routes `R` (a vector of vectors) is costed
route by route.

With `full = false`, the default, it returns the cost alone, `Inf` for a route that breaks a limit the
truck carries (see Notes). With `full = true` it returns the named tuple `(TC, Xflg, out)`, which
destructures as `TC, Xflg, out = rteTC(...; full = true)`: the cost, an exit flag naming the
constraint a route violates, and a table of the route's stops. The cost handle `savings` and `twoopt`
take is `rte -> rteTC(rte, sh, C, tr)`; for a schedule it is `rte -> rteTC(rte, sh, C, tr; full = true).TC`.

# Arguments
- `rte`: Route, a vector of shipment indices (first appearance a loading, second an unloading).
- `sh`: Shipments table. Columns `b`, `e` (locations, required). Optional columns: `q` (weight, tons)
  and `s` (density, lb/ft³; with `Kcu`) for capacity; **with `full = true`** also `tL`, `tU` (time to
  load, to unload) added to the route's time, and `tbmin`, `tbmax` (earliest and latest time a
  loading begins) and `temin`, `temax` (earliest and latest time an unloading ends), the shipment's
  time windows.
- `C`: Matrix of costs or times between locations. The cost between two stops at the same
  location is 0 whatever `C[i, i]` is, as Matlog's ("costs `C(i,i)` ignored").
- `tr`: Truck, a named tuple, every field optional: `b`, `e` (the truck's begin and end locations,
  put at the route's ends); `Kwt` (tons), `Kcu` (ft³) capacities, checked on each load mix; `maxTC`,
  the maximum total cost of a route; **with `full = true`** `tbmin`, `tbmax`, `temin`, `temax`, the
  truck's windows (at its `b` and its `e`, and at the stops at them).
- `full`: (keyword) `false` the cost alone; `true` the cost, flag and table.

# Returns
- `TC`: the total cost: the costs between stops plus, with `full = true`, the loading and unloading
  times, added in order from the left; **with time windows (`full = true`), the route's least time**,
  its waiting included (`scanTW`); `Inf` for an infeasible route.
- `Xflg`: `1` feasible; `-1` a depot route (`tr.b == tr.e`) that returns to its depot midway, which is
  more than one route (Matlog's degenerate location vector); `-2` weight over `tr.Kwt` at some load mix;
  `-3` cube over `tr.Kcu` at some load mix (2000 ∑ q/s, with a rounding tolerance of `0.01√eps()`, so
  a load of exactly `maxpayld` is not over); `-4` the cost over `tr.maxTC`, which is tested on travel
  plus loading and unloading **before** the time-window scans, so it does not bound a windowed
  route's duration; `-5` a time window cannot be met.
- `out`: a `DataFrame` with one row per stop (the truck's first and last included, given `tr.b`), empty
  for an infeasible route. Columns `Rte` (the route, 0 at the truck's ends), `Loc` (locations), `Cost`
  (travel time into each stop, 0 for the first and for a stop at the previous location) and, if any
  `tL` or `tU` is given, `LU`. **With a window** (any of the four fields, on `sh` or on `tr`) it holds
  the schedule: `Arrive`, `Wait`, `TWmin`, `Start`, `LU`, `Depart`, `TWmax`, `Total` (travel + wait +
  loading and unloading). **The columns are part of the interface** (S8): a limit that is not built in
  is added by a route cost that wraps this one and reads `out`, as Lecture 5.3's hours of service
  does (`sum(out.Cost)` is the driving, the returned `TC` the time on duty).

# Example
```jldoctest
julia> using DataFrames

julia> # Lecture 5.3 Ex. 4 (slide 254): a route 1 -> 2 -> 3 -> 4 -> 1 with a window at each customer
       T = zeros(4, 4); T[1, 2] = 1; T[2, 3] = 2; T[3, 4] = 1; T[4, 1] = 1;

julia> sh = DataFrame(b = 1, e = [2, 3, 4], tU = 0.0, temin = [8, 12, 15], temax = [11, 14, 18]);

julia> tr = (b = 1, e = 1, tbmin = 6, tbmax = 18, temin = 18, temax = 24);

julia> TC, Xflg, out = rteTC([1, 2, 3, 1, 2, 3], sh, T, tr; full = true);

julia> TC, Xflg, out.Start, out.Wait    # leave at 10, an hour's wait at customer 4, two at the depot
(8.0, 1, [10.0, 10.0, 10.0, 10.0, 11.0, 13.0, 15.0, 18.0], [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 2.0])
```

```jldoctest
julia> using DataFrames

julia> # Lecture 5.3 Ex. 3's weights (10 t each) and truck (25 t) on 5.2 Ex. 6(a)'s costs
       D = [  0 300  30 280  60 335
            300   0 280  30 335  60
             30 280   0 250  90 340
            280  30 250   0 340  90
             60 335  90 340   0 275
            335  60 340  90 275   0];

julia> sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6], q = [10, 10, 10]);

julia> rteTC([1, 2, 1, 3, 2, 3], sh, D, (Kwt = 25,))     # two load mixes of 20 t
1075

julia> rteTC([1, 2, 3, 3, 2, 1], sh, D, (Kwt = 25,))     # one load mix of 30 t: refused
Inf

julia> rteTC([1, 2, 3, 3, 2, 1], sh, D, (Kwt = 25,); full = true).Xflg
-2
```

# Notes
- Source: Matlog's `rteTC.m` and Lecture 5.3's inline `rteTC_vrp` (Code block 15; the time windows' scan,
  Code block 28), which `full = true` is, to 1e-9 on the lecture's inputs. `scanTW` and `rte2ldmx`
  are the lecture's other functions: `rte2ldmx` is exported (CR 59), `scanTW` is `public`, so the
  lecture's inline copies of all three, defined after `using Logjam`, still run.
- **Same-location segments (CR 43).** A segment between two stops at one location costs 0, whatever
  `C[i, i]` is (Matlog: "costs `C(i,i)` ignored"); v0.2.8 charged `C[i, i]` for each. It matters only
  for a matrix with a nonzero diagonal, such as a time matrix that carries a stop time (5.3 Ex. 6's
  `D/50 .+ 5/60`). **A route that returns to its depot midway (two trips)** is priced by a plain call
  with no limit on the truck, as v0.2.8 priced it, and refused (`Inf`, flag -1) when a limit is on
  the truck or with `full = true`: Matlog's `rte2loc` makes it infeasible and Logjam's callers have
  never been told they could not form one, so the plain call allows it by this documented decision.
- **What a plain call reads.** A call whose `sh` and `tr` carry none of the checked fields returns
  exactly what `rteTC` returned in v0.2.8 (the sum of the segment costs) except for a same-location
  segment on a matrix with a nonzero diagonal. A plain call (`full = false`) reads a truck's `Kwt` and `Kcu`
  (with `q` and `s` on `sh`) and `maxTC`, and applies Matlog's degenerate-location test (flag -1)
  when one of the three is on the truck; it returns `Inf` for a route that breaks one. **Loading and
  unloading times and time windows are read only with `full = true`**, because they change the cost
  of every route, and a call that passes a `tU` column today (HW 5 Q1's key adds `tU` itself) must
  keep its value.
- With `full = true` every check applies. The travel cost is the `sum` of the segment costs on every
  path (v0.2.8's summation: a different order of addition moves the last places, and a 2-opt tie is
  decided by them), so `TC` equals `sum(segcost(rte2loc(rte, sh, tr), C))` bit for bit when `sh` has
  no time fields; the lecture's inline `rteTC_vrp` adds left to right and agrees to 1e-9. The window
  scans add left to right (`scanTW`; with `+=` in a different order 5.3's NC30 windows case moves
  from 40.95 to 43.39 h).
- With no `tr.b` the route is its own location sequence and the truck's windows do not apply.
- A shipment in a time window must name the window on the end that matters: a loading's `tbmin`/`tbmax`,
  an unloading's `temin`/`temax`; a field left out is `-Inf` or `Inf`.
"""
function rteTC(rte, sh, C, tr = (;); full::Bool = false)
    # the checks on `tr` first: for a NamedTuple they are free at compile time
    lim = haskey(tr, :Kwt) || haskey(tr, :Kcu) || haskey(tr, :maxTC)
    if !full && !lim
        return _rtetc_plain(rte, sh.b, sh.e, C, tr)
    end
    TC, Xflg, out = _rteTC_checked(rte, sh, C, tr, full)
    return full ? (TC = TC, Xflg = Xflg, out = out) : TC
end
function rteTC(R::AbstractVector{<:AbstractVector{<:Integer}}, sh, C, tr = (;); full::Bool = false)
    v = [rteTC(r, sh, C, tr; full = full) for r in R]
    full || return v
    return (TC = [x.TC for x in v], Xflg = [x.Xflg for x in v], out = [x.out for x in v])
end

# a call with no limit on the truck: the sum of the segment costs, as v0.2.8 summed them
_rtetc_plain(rte, b, e, C, tr) = sum(_rtesegcost(_rte2loc(rte, b, e, tr), C))

# The checks and, with `full`, the schedule. A plain call (`full = false`) reads capacity and maxTC only
# and returns `(TC, Xflg, nothing)`; the loading and unloading times and the windows are read only with `full`.
# The travel cost is `sum` of the segment costs on every path (v0.2.8's summation, so 2-opt ties fall as
# they did); the window scans add left to right (`scanTW`).
function _rteTC_checked(rte, sh, C, tr, full::Bool)
    noout = full ? DataFrame() : nothing
    isL = isorigin(rte)
    hasb, hase = !isempty(get(tr, :b, ())), !isempty(get(tr, :e, ()))   # the truck's begin and end locations
    istr = hasb && hase
    loc = _rte2loc(rte, sh.b, sh.e, tr)
    Xflg = 1
    istr && _isdegenerate(loc[2:end-1], tr) && (Xflg = -1)
    if Xflg > 0 && (haskey(tr, :Kwt) || haskey(tr, :Kcu)) && hasproperty(sh, :q)
        haskey(tr, :Kcu) && !hasproperty(sh, :s) &&
            throw(ArgumentError("Shipments must have a column \"s\" (density) for the cube capacity check."))
        for ld in rte2ldmx(rte)
            if haskey(tr, :Kwt) && sum(sh.q[ld]) > tr.Kwt
                Xflg = -2; break
            elseif haskey(tr, :Kcu) && 2000sum(sh.q[ld] ./ sh.s[ld]) >
                   tr.Kcu + 0.01sqrt(eps())
                Xflg = -3; break
            end
        end
    end
    Xflg < 0 && return Inf, Xflg, noout
    seg = _rtesegcost(loc, C)
    travel = sum(seg)
    if !full
        haskey(tr, :maxTC) && travel > tr.maxTC && return Inf, -4, noout
        return travel, 1, nothing
    end
    has(f) = hasproperty(sh, f)
    trhas(f) = haskey(tr, f)
    col(f, v) = has(f) ? float.(sh[rte, f]) : fill(v, length(rte))
    t = vcat(zero(eltype(C)), seg)
    tLU = ifelse.(isL, col(:tL, 0.0), col(:tU, 0.0))
    tLU = vcat(hasb ? [0.0] : Float64[], tLU, hase ? [0.0] : Float64[])
    TC = travel + sum(tLU)
    haskey(tr, :maxTC) && TC > tr.maxTC && return Inf, -4, noout
    R = vcat(hasb ? [0] : Int[], rte, hase ? [0] : Int[])
    tw = (:tbmin, :tbmax, :temin, :temax)
    if !any(f -> has(f) || trhas(f), tw)
        out = DataFrame(Rte = R, Loc = loc, Cost = t)
        (has(:tL) || has(:tU)) && (out.LU = tLU)
        return TC, Xflg, out
    end
    hasb == hase || throw(ArgumentError("Time windows need a truck with both locations, `b` and `e`, or neither."))
    lo = ifelse.(isL, col(:tbmin, -Inf), col(:temin, -Inf))
    hi = ifelse.(isL, col(:tbmax, Inf), col(:temax, Inf))
    if istr
        lo = [get(tr, :tbmin, -Inf); lo; get(tr, :temin, -Inf)]
        hi = [get(tr, :tbmax, Inf); hi; get(tr, :temax, Inf)]
        c = [1; findall(diff(loc) .!= 0) .+ 1]
        n = length(loc)
        for (ix, j) in ((2:c[2]-1, 1), (c[end]:n-1, n))
            lo[ix] = replace(lo[ix], -Inf => lo[j])
            hi[ix] = replace(hi[ix], Inf => hi[j])
        end
    end
    TC, _, _, s = scanTW(t, tLU, lo, hi)
    isinf(TC) && return Inf, -5, DataFrame()
    isnan(TC) && (TC = travel + sum(tLU))
    w = max.(0, [0; s[2:end] - s[1:end-1] - tLU[1:end-1] - t[2:end]])
    out = DataFrame(Rte = R, Loc = loc, Cost = t,
        Arrive = [0; s[2:end] - w[2:end]], Wait = w, TWmin = lo,
        Start = s, LU = tLU, Depart = s + tLU, TWmax = hi,
        Total = t + w + tLU)
    return TC, Xflg, out
end

# =============================================================================
# Route Improvement Procedures
# =============================================================================

"""
    twoopt(r, rTCh; verbose = false) -> (rte = improved route or tour, TC = its cost)

Improve a tour or a route with the first-improvement 2-opt procedure.

The procedure reverses a stretch of the vector, keeps the change if the total cost falls, and
starts the scan again from the new vector; it stops when a whole scan improves nothing.
`twoopt` runs one of two neighborhoods, and **which one is decided by the vector itself**:

- **A route vector** is one in which every element appears exactly twice, the first
  appearance a shipment's pickup and the second its delivery (the form `rteTC`, `rte2loc`
  and `mincostinsert` take). Its neighborhood is Matlog's `twoopt.m`: `i = 1:m - 1`,
  `j = i + 1:m` over the `m` stops, reversing `r[i:j]`, so the first and last stops can move,
  and **a reversal that leaves the truck empty between two shipments is never considered**,
  since such a vector is two routes and not one (as in Lecture 5.2's loops). The result is a
  route whenever the start is one. As in Matlog and in Lecture 5.2's `twoopt_rte`, a reversal
  is kept if its cost is strictly lower, so a change that is zero in exact arithmetic (all the
  deliveries of a depot route reversed) is kept or not by the `1e-13` rounding of the machine's
  order of summation; where such a tie arises, the route a run ends at can differ between
  computers, as it does for the lecture's own function.
- **Anything else is a tour**, a location sequence that returns to its first element
  (`r[1] == r[end]`), as in Lecture 5.1. Its neighborhood is the closed tour's: the first and
  last elements stay in place and `r[i+1:j]` is reversed for `i = 1:m - 2`,
  `j = i + 2:min(m - 1, m + i - 3)`. A tour is not a route vector, because a tour
  visits each location once and the depot twice, so no tour has every element twice except
  the degenerate `[a, a]`, on which neither neighborhood has a move.

# Arguments
- `r`: Initial route vector or tour.
- `rTCh`: Function that calculates the total cost of a whole vector: `rTCh(r) -> cost`. It may
  return `Inf` for a vector that violates a constraint; it need not be a sum of arc costs.
- `verbose`: (keyword) `true` prints each vector the procedure considers with its cost, as Lecture 5.1's
  `twoopt_prt` (Code block 15) prints them: first the start, `"*" TC ": " r`; then, in the order
  considered, `" " TC ": " r′` for a change that is not kept and `"*" TC ": " r′` for one that is, so
  the starred lines are the vectors the search moves through. Each line's cost is the one `rTCh`
  returned for its vector, and each line is printed with `println`. A route's reversal that leaves the
  truck empty is not considered, so it is not printed. Default `false`, which prints nothing.

# Returns
- The named tuple `(rte, TC)`, the improved vector and its total cost, which destructures as `r, TC = twoopt(r, rTCh)`. The input is not modified.

# Example
```jldoctest
julia> # A tour: 5.1's rule of a closed tour through four locations (Matlog's `tsp2opt` neighborhood)
       C = [0 10 25 20; 10 0 15 30; 25 15 0 10; 20 30 10 0];

julia> rTCh = r -> sum(C[r[i], r[i+1]] for i in 1:length(r)-1);

julia> improved, cost = twoopt([1, 2, 3, 4, 1], rTCh)
(rte = [1, 2, 3, 4, 1], TC = 55)

julia> twoopt([1, 3, 2, 4, 1], rTCh; verbose = true)    # every tour considered, a star on each kept
*90: [1, 3, 2, 4, 1]
*55: [1, 2, 3, 4, 1]
 90: [1, 3, 2, 4, 1]
 75: [1, 2, 4, 3, 1]
(rte = [1, 2, 3, 4, 1], TC = 55)
```

```jldoctest
julia> using DataFrames

julia> # A route: Lecture 5.2 Ex. 6(a)'s shipments (1 to 2, 3 to 4, 5 to 6) at one dollar a mile
       D = [  0 300  30 280  60 335
            300   0 280  30 335  60
             30 280   0 250  90 340
            280  30 250   0 340  90
             60 335  90 340   0 275
            335  60 340  90 275   0];

julia> sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6]);

julia> route, cost = twoopt([1, 2, 3, 1, 2, 3], r -> rteTC(r, sh, D))
(rte = [3, 1, 2, 2, 1, 3], TC = 430)
```

# Notes
- Matlog's `twoopt.m` has no check of its own and leaves the empty truck to the route cost;
  here a reversal that empties the truck is skipped, as Lecture 5.2's `twoopt_rte` skips it.
- For pickup-delivery with constraints: have `rTCh` return `Inf` for an infeasible route.
- **Order of ties (CR 58), routes only:** where two neighboring loadings, or two neighboring unloadings, can trade places at exactly the same cost, the returned route lists the lower-numbered shipment first (applied after the search, which is unchanged); a tour is returned as the search leaves it. The cost is never changed. The same holds for each route of a vector of routes.
- **The trace (`verbose = true`, E2)** is printed by the search itself, in the loop that finds the result, so
  for a tour its last starred line is the tour returned; for a route the order of ties is applied after the
  search, so the returned route can differ from the last starred line by the order of two tied shipments.
  On Lecture 5.1 Ex. 3 (`twoopt(π, πTCh; verbose = true)`) the output is the lecture's Code block 15, byte for
  byte. Printing changes nothing the search computes: the result is the same with `verbose` `true` or `false`.
"""
function twoopt(r, rTCh; verbose::Bool = false)
    rte, TC = _twoopt_out(r, rTCh; verbose)
    return (rte = rte, TC = TC)
end

# a route or a tour, by the vector itself (the kernels, which the exports and the set methods call)
_twoopt(r, rTCh; verbose::Bool = false) =
    _isroutevec(r) ? _twoopt_route(r, rTCh; verbose) : _twoopt_tour(r, rTCh; verbose)

# what the exported methods return: the kernel's result, a route put in increasing order of equal-cost
# ties (CR 58) after the search, a tour untouched
function _twoopt_out(r, rTCh; verbose::Bool = false)
    rte, TC = _twoopt(r, rTCh; verbose)
    return (_isroutevec(r) ? _order_ties(rte, rTCh) : rte), TC
end

# CR 58, applied to the route an exported function returns and never inside a search: two neighboring
# loadings, or two neighboring unloadings, that can trade places at exactly the same cost (`==` on the
# handle's cost) are listed lower-numbered first; repeated until no swap applies. The cost never changes
# (a swap is made only when it is equal); a route of infinite or undefined cost is returned as it is.
function _order_ties(r, rteTCh)
    r = copy(r)
    n = length(r)
    n < 2 && return r
    TC = rteTCh(r)
    isfinite(TC) || return r
    isL = _isload(r)
    changed = true
    while changed
        changed = false
        for i in 1:n-1
            (isL[i] == isL[i+1] && r[i] > r[i+1]) || continue
            r[i], r[i+1] = r[i+1], r[i]
            if rteTCh(r) == TC
                changed = true
            else
                r[i], r[i+1] = r[i+1], r[i]
            end
        end
    end
    return r
end

# a vector of results of one type: the costs of a vector of routes are `Int` where every route's is
_narrow(v) = isempty(v) ? v : convert(Vector{mapreduce(typeof, promote_type, v)}, v)

"""
    twoopt(R, rTCh; verbose = false) -> (rte = R′, TC = Vector)
    twoopt(R, C::AbstractMatrix; verbose = false) -> (rte = R′, TC = Vector)

2-opt of a set of routes: each route (or tour) of the vector `R` improved on its own, Matlog's `twoopt`
on a cell array of routes. The result is the named tuple of the vector of improved routes and the vector
of their costs, so the routes `savings` forms are improved by one call,
`R, TC = twoopt(savings(rteTCh, sh), rteTCh)`, where Lecture 5.3 writes
`R1 = [twoopt_rte(r, rTCh)[1] for r in savings(rTCh, sh)]` and then `TC = rTCh.(R1)`.

With a cost handle `rTCh` each element of `R` is a route (every element twice) or a tour, and is improved as
`twoopt(r, rTCh)` improves it. With a matrix `C` each element is a closed tour improved by the delta method
of `twoopt(π, C)`, whose cost is the sum of arc costs.

# Arguments
- `R`: A vector of routes, each a vector of integers. Not modified.
- `rTCh`: Function that calculates the total cost of one route, `rTCh(r) -> cost`, the handle `savings` takes.
- `C`: Square matrix of arc costs, for a vector of tours.
- `verbose`: (keyword) passed to each route's 2-opt, so `true` prints the trace of `twoopt(r, rTCh; verbose =
  true)` or `twoopt(π, C; verbose = true)` for each route in the order of `R`, one after another, each
  beginning with its starting route's starred line. Default `false`, which prints nothing.

# Returns
- The named tuple `(rte, TC)`, which destructures as `R, TC = twoopt(R, rTCh)`: the improved routes in the
  order of `R`, and the cost of each.

# Example
```jldoctest
julia> using DataFrames

julia> C = [ 0 40 48 38 33 48            # Lecture 5.3 Ex. 1(c): Clarke-Wright with a capacity of 15
            40  0 87 46 65 75
            48 87  0 67 41 47
            38 46 67  0 70 34
            33 65 41 70  0 69
            48 75 47 34 69  0];

julia> sh = DataFrame(b = ones(Int, 5), e = 2:6, q = [8, 5, 4, 7, 6]);

julia> tr = (b = 1, e = 1);

julia> h = rte -> (TC = rteTC(rte, sh, C, tr); sum(sh.q[unique(rte)]) <= 15 ? TC : Inf);

julia> R, TC = twoopt(savings(h, sh), h);

julia> R
2-element Vector{Vector{Int64}}:
 [2, 3, 5, 3, 5, 2]
 [1, 4, 1, 4]

julia> TC
2-element Vector{Int64}:
 167
 138
```

# Notes
- Source: Matlog's `twoopt.m` on a cell array, and the comprehension over `savings` that Lecture 5.2 and
  5.3 write (`[twoopt_rte(r, h)[1] for r in savings(h, sh)]`), whose routes it returns. A vector of
  routes is not a route (its elements are vectors), so these methods do not meet the route-or-tour test of
  `twoopt(r, rTCh)`.
- `twoopt(R, C)` throws `ArgumentError` for a route vector, as `twoopt(π, C)` does.
"""
function twoopt(R::AbstractVector{<:AbstractVector{<:Integer}}, rTCh; verbose::Bool = false)
    res = [_twoopt_out(r, rTCh; verbose) for r in R]
    return (rte = map(first, res), TC = _narrow(map(x -> x[2], res)))
end
function twoopt(R::AbstractVector{<:AbstractVector{<:Integer}}, C::AbstractMatrix; verbose::Bool = false)
    res = [twoopt(π, C; verbose) for π in R]
    return (rte = map(first, res), TC = _narrow(map(x -> x[2], res)))
end

# a route vector: every element exactly twice (first appearance the pickup)
function _isroutevec(r)
    isempty(r) && return false
    n = Dict{eltype(r),Int}()
    for x in r
        n[x] = get(n, x, 0) + 1
    end
    return all(==(2), values(n))
end

# Matlog's twoopt.m on one route, with the empty-truck vectors left out. `verbose` prints each route whose
# cost is computed, in Lecture 5.1's `twoopt_prt` form (E2); it changes nothing the search computes.
function _twoopt_route(r, rTCh; verbose::Bool = false)
    m = length(r)
    rᵒ, TCᵒ = copy(r), rTCh(r)
    verbose && println("*", TCᵒ, ": ", rᵒ)
    done = false
    while !done
        done = true
        for i = 1:m-1, j = i+1:m
            r′ = vcat(rᵒ[1:i-1], reverse(rᵒ[i:j]), rᵒ[j+1:end])
            _loaded_throughout(r′) || continue
            TC = rTCh(r′)
            if TC < TCᵒ
                rᵒ, TCᵒ = r′, TC
                verbose && println("*", TCᵒ, ": ", rᵒ)
                done = false
                break
            elseif verbose
                println(" ", TC, ": ", r′)
            end
        end
    end
    return rᵒ, TCᵒ
end

# the closed tour's neighborhood: the ends stay; v0.2.8's loops, unchanged. `verbose` prints what Lecture
# 5.1's `twoopt_prt` (Code block 15) prints, the same three `println`s at the same places in the same loop (E2).
function _twoopt_tour(r, rTCh; verbose::Bool = false)
    rᵒ, TCᵒ = copy(r), rTCh(r)
    verbose && println("*", TCᵒ, ": ", rᵒ)
    done = false
    while !done
        done = true
        for i = 1:length(r)-2
            for j = i+2:min(length(r)-1, length(r)+i-3)
                r′ = vcat(r[1:i], reverse(r[i+1:j]), r[j+1:end])
                TC = rTCh(r′)
                if TC < TCᵒ
                    rᵒ, TCᵒ = r′, TC
                    verbose && println("*", TCᵒ, ": ", rᵒ)
                    done = false
                    break
                elseif verbose
                    println(" ", TC, ": ", r′)
                end
            end
            if done == false
                break
            end
        end
        r = copy(rᵒ)
    end
    return rᵒ, TCᵒ
end

"""
    twoopt(π, C::AbstractMatrix; verbose = false) -> (rte = improved tour, TC = its cost)

2-opt of a closed tour whose cost is the sum of its arc costs, each change evaluated by its
**delta**: the arcs removed against the arcs added, not the cost of the whole new tour.

`π` is a tour, a location sequence that returns to its first element (`π[1] == π[end]`), and
`C[a, b]` is the cost of the arc from location `a` to location `b`. The method makes the same
changes in the same order as `twoopt(π, rTCh)` with `rTCh = π -> sum(segcost(π, C))`, the
first-improvement procedure of Lecture 5.1, and returns the same tour and cost, but a change
costs O(1) where the general method's costs O(m), so a scan is O(m²) where it is O(m³): from a random
start through 500 points it takes 0.2 s, where CR 48 measured the general method at 100 s.
For a symmetric `C` the
delta of reversing `π[i+1:j]` is `C[a, c] + C[b, d] - C[a, b] - C[c, d]` with `a, b = π[i], π[i+1]`
and `c, d = π[j], π[j+1]`; for an asymmetric `C` it adds the difference between the reversed
stretch's backward and forward arcs, read from prefix sums kept for the scan.

# Arguments
- `π`: Initial tour, a vector of location indices with `π[1] == π[end]`. Not modified.
- `C`: Square matrix of arc costs, indexed by the locations of `π`.
- `verbose`: (keyword) `true` prints the trace `twoopt(π, rTCh; verbose = true)` prints with
  `rTCh = π -> sum(segcost(π, C))`: the start, then each tour considered with its cost, a star on each
  one kept. The search still decides by the delta; only for the printing is each tour considered built
  and its whole cost, `sum(segcost(π′, C))`, computed, so `verbose = true` costs O(m) a change, as the
  general method does. Default `false`, which builds and prints nothing.

# Returns
- The named tuple `(rte, TC)`: the improved tour and its cost, `sum(segcost(rte, C))`.

# Example
```jldoctest
julia> # 5.1 Ex. 3, slide 240's trace: six nodes, asymmetric arc costs, from the tour 1-2-3-4-5-6-1
       D = [0 8 6 9 1 5; 3 0 1 5 4 2; 9 2 0 3 1 1; 8 2 1 0 10 6; 6 7 10 1 0 10; 6 2 5 2 1 0];

julia> twoopt([1, 2, 3, 4, 5, 6, 1], D)
(rte = [1, 5, 4, 2, 3, 6, 1], TC = 12)

julia> twoopt([1, 2, 3, 4, 5, 6, 1], D; verbose = true)    # the trace of Lecture 5.1's Code block 15
*38: [1, 2, 3, 4, 5, 6, 1]
 39: [1, 3, 2, 4, 5, 6, 1]
*32: [1, 4, 3, 2, 5, 6, 1]
*31: [1, 3, 4, 2, 5, 6, 1]
 32: [1, 4, 3, 2, 5, 6, 1]
 31: [1, 2, 4, 3, 5, 6, 1]
*21: [1, 5, 2, 4, 3, 6, 1]
 21: [1, 2, 5, 4, 3, 6, 1]
 32: [1, 4, 2, 5, 3, 6, 1]
 31: [1, 3, 4, 2, 5, 6, 1]
*12: [1, 5, 4, 2, 3, 6, 1]
 34: [1, 4, 5, 2, 3, 6, 1]
 40: [1, 2, 4, 5, 3, 6, 1]
 39: [1, 3, 2, 4, 5, 6, 1]
 21: [1, 5, 2, 4, 3, 6, 1]
 30: [1, 5, 3, 2, 4, 6, 1]
 31: [1, 5, 6, 3, 2, 4, 1]
 13: [1, 5, 4, 3, 2, 6, 1]
 18: [1, 5, 4, 6, 3, 2, 1]
 20: [1, 5, 4, 2, 6, 3, 1]
(rte = [1, 5, 4, 2, 3, 6, 1], TC = 12)
```

# Notes
- Throws `ArgumentError` for a route vector (every element twice): a route's cost is not a sum of
  arc costs, so it takes a cost handle, `twoopt(r, rTCh)`.
- The neighborhood is the closed tour's: `π[1]` and `π[end]` stay, `i = 1:m - 2`,
  `j = i + 2:min(m - 1, m + i - 3)`.
- A change is kept only if its delta is below zero, as the general method keeps a change whose
  cost is strictly lower; a tie in exact arithmetic is decided by rounding, as there.
"""
function twoopt(π::AbstractVector, C::AbstractMatrix; verbose::Bool = false)
    _isroutevec(π) && throw(ArgumentError(
        "twoopt(π, C) takes a closed tour; a route vector's cost is not a sum of arc costs, so use twoopt(r, rTCh)"))
    n = length(π)
    πᵒ = collect(π)
    verbose && println("*", sum(segcost(πᵒ, C)), ": ", πᵒ)
    sym = all(C[i, j] == C[j, i] for j in axes(C, 2) for i in 1:j)
    F = zeros(n)                  # F[k + 1]: cost of the forward arcs 1..k; B[k + 1] the backward ones
    B = zeros(n)
    done = false
    while !done
        done = true
        if !sym
            for k in 1:n-1
                F[k+1] = F[k] + C[πᵒ[k], πᵒ[k+1]]
                B[k+1] = B[k] + C[πᵒ[k+1], πᵒ[k]]
            end
        end
        for i = 1:n-2
            for j = i+2:min(n-1, n+i-3)
                a, b, c, d = πᵒ[i], πᵒ[i+1], πᵒ[j], πᵒ[j+1]
                Δ = C[a, c] + C[b, d] - C[a, b] - C[c, d]
                if !sym             # the stretch's arcs i+1 .. j-1 run the other way
                    Δ += (B[j] - B[i+1]) - (F[j] - F[i+1])
                end
                if Δ < 0
                    reverse!(πᵒ, i + 1, j)
                    verbose && println("*", sum(segcost(πᵒ, C)), ": ", πᵒ)
                    done = false
                    break
                elseif verbose     # the tour the handle form would cost, for the trace only (E2)
                    π′ = vcat(πᵒ[1:i], reverse(πᵒ[i+1:j]), πᵒ[j+1:end])
                    println(" ", sum(segcost(π′, C)), ": ", π′)
                end
            end
            done || break
        end
    end
    return (rte = πᵒ, TC = sum(segcost(πᵒ, C)))
end

# =============================================================================
# Route Construction Procedures
# =============================================================================

"""
    mincostinsert(idx, rte, rteTCh; verbose = false) -> (rte = new route, TC = its cost)

Insert a shipment into a route at the minimum cost position.

For pickup-delivery problems, both the pickup and delivery must be inserted.
This function tries every position at which the result is a route, that is, a vector on
which a shipment is on board over every segment, and returns the best. For a route of
`m` stops the loops are `i = 1:m` for the pickup and `j = max(2, i):m + 1` for the
delivery: `m(m + 3)/2 - 1` positions, the count of Lecture 5.2's Eq. insert-count. Of the
`(m + 1)(m + 2)/2` ways to place two stops, two are left out: the new shipment loaded
and unloaded ahead of the first stop, and loaded and unloaded after the last stop, since
the truck would be empty between the new shipment and the route, which is two routes and
not one (Lecture 5.2's slide 248 crosses out the same rows).

# Arguments
- `idx`: Shipment index to insert.
- `rte`: Current route as a vector of shipment indices.
- `rteTCh`: Function that calculates route cost: `rteTCh(route) -> cost`.
- `verbose`: (keyword) `true` prints each route tried, in the order tried, as Lecture 5.2's
  `mincostinsert_prt` (Code block 17) prints it: `i "," j ": " route " = " TC`, the positions of the
  pickup and the delivery, the route and the cost `rteTCh` returned, printed with `println`. Into an empty
  route the shipment goes as `[idx, idx]`, a position outside the loops, and nothing is printed, as the
  lecture's function prints nothing for it. Default `false`, which prints nothing.

# Returns
- The named tuple `(rte, TC)`, the new route and its total cost, which destructures as `rte, TC = mincostinsert(...)`.

# Example
```jldoctest
julia> using DataFrames

julia> # Lecture 5.2 Ex. 6(a): three shipments at one dollar a mile (locations 1 to 2, 3 to 4, 5 to 6)
       D = [  0 300  30 280  60 335
            300   0 280  30 335  60
             30 280   0 250  90 340
            280  30 250   0 340  90
             60 335  90 340   0 275
            335  60 340  90 275   0];

julia> sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6]);

julia> rteTCh = rte -> rteTC(rte, sh, D);

julia> rte, cost = mincostinsert(2, [1, 1], rteTCh)
(rte = [1, 2, 2, 1], TC = 310)

julia> rte, cost = mincostinsert(3, rte, rteTCh)
(rte = [3, 1, 2, 2, 1, 3], TC = 430)

julia> mincostinsert(2, [1, 1], rteTCh; verbose = true)    # the four routes of Lecture 5.2's Code block 17
1,2: [2, 1, 2, 1] = 340
1,3: [2, 1, 1, 2] = 360
2,2: [1, 2, 2, 1] = 310
2,3: [1, 2, 1, 2] = 340
(rte = [1, 2, 2, 1], TC = 310)
```

# Notes
- Returns the route unchanged with cost `Inf` if no position has a finite cost (a route cost
  that is `Inf` off a feasible route, as in Lecture 5.3); test `isinf(cost)`.
- The pickup must occur before the delivery in the route.
- **Order of ties (CR 58):** where two neighboring loadings, or two neighboring unloadings, can trade places at exactly the same cost, the returned route lists the lower-numbered shipment first; the cost is never changed.
- Source of the loops: Lecture 5.2's `mincostinsert_rte`; Matlog's `mincostinsert.m` also tries the two positions left out here and leaves them to
  its route cost, which does not refuse them.
- **The trace (`verbose = true`, E2)** is printed in the loop that finds the result, so on Lecture 5.2's inputs
  (Code block 17's two insertions) it is the lecture's output byte for byte. The order of ties is applied after
  the loop, so the returned route can differ from the cheapest route printed by the order of two tied shipments.
  Printing changes nothing the loop computes: the result is the same with `verbose` `true` or `false`.
"""
function mincostinsert(idx, rte::AbstractVector, rteTCh; verbose::Bool = false)
    rte′, TC = _mincostinsert(idx, rte, rteTCh; verbose)
    return (rte = _order_ties(rte′, rteTCh), TC = TC)
end

# the loops of mincostinsert; `savings`, `pairwisesavings` and the insertion hook run this one. `verbose`
# prints each route tried in Lecture 5.2's `mincostinsert_prt` form (Code block 17, E2).
function _mincostinsert(idx, rte, rteTCh; verbose::Bool = false)
    if isempty(rte)
        return [idx, idx], rteTCh([idx, idx])
    end
    rteᵒ, TCᵒ = copy(rte), Inf
    for i = 1:length(rte)
        for j = max(2,i):length(rte) + 1
            rte′ = vcat(rte[1:i-1], idx, rte[i:j-1], idx, rte[j:end])
            TC = rteTCh(rte′)
            verbose && println(i, ",", j, ": ", rte′, " = ", TC)
            if TC < TCᵒ
                rteᵒ, TCᵒ = rte′, TC
            end
        end
    end
    return rteᵒ, TCᵒ
end

# The one insertion loop. The shipments `ks`, in order, each go into `rte` at its minimum cost position,
# `insert(k, route, rteTCh) -> (route, cost)`, and each insertion is followed by `improve(route, rteTCh) ->
# (route, cost)` when one is given: Lecture 5.2's `oneroute` (Code block 43) is this with 2-opt (the tests
# hold the two equal), a route inserted into another (`_insert_route`, `savings`) is this without. It stops
# with `(route, Inf)` as soon as a shipment has no finite position, the route being the one before that
# insertion, so no shipment is dropped from a route that is then given a finite cost. With no
# shipments to insert it returns `rte` and its cost.
function _insertall(ks, rte, rteTCh; insert = _mincostinsert, improve = nothing)
    isempty(ks) && return rte, rteTCh(rte)
    TC = Inf
    for k in ks
        rte′, TC = insert(k, rte, rteTCh)
        isinf(TC) && return rte, Inf
        rte = rte′
        improve === nothing || ((rte, TC) = improve(rte, rteTCh))
    end
    return rte, TC
end

"""
    pairwisesavings(rteTCh, sh; TC1 = nothing) -> (i = Vector{Int}, j = Vector{Int}, s = Vector{Float64})

Calculate savings from combining pairs of single-shipment routes.

The savings value represents cost reduction from serving two shipments
on one route instead of two separate routes.

# Arguments
- `rteTCh`: Function that calculates route cost: `rteTCh(route) -> cost`.
- `sh`: Shipments DataFrame (used to determine number of shipments via `nrow`).
- `TC1`: (keyword) the independent total cost of each shipment, a vector with one element
  per shipment, as Matlog's `pairwisesavings.m` takes it in its third argument. The default,
  `nothing`, is `rteTCh([k, k])` for shipment `k`, the cost of the shipment on a route of its
  own, and an unchanged call is unchanged. Pass it where the independent cost is not that: the
  savings of a total logistics cost (Lecture 5.2's load formation, 5.3's TLC routes) are measured
  from the cost of each shipment shipped on its own at its own best size and mode, which
  `minTLC` gives (LTL allowed) and which a route cost handle need not.

# Returns
- The named tuple `(i, j, s)`, the pairs and their savings sorted by savings (descending); it destructures as `iˢ, jˢ, sˢ = pairwisesavings(...)` and `ijs[3]` is `s`.

# Example
```jldoctest
julia> using DataFrames

julia> # Lecture 5.2 Ex. 6(a): three shipments at one dollar a mile (locations 1 to 2, 3 to 4, 5 to 6)
       D = [  0 300  30 280  60 335
            300   0 280  30 335  60
             30 280   0 250  90 340
            280  30 250   0 340  90
             60 335  90 340   0 275
            335  60 340  90 275   0];

julia> sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6]);

julia> rteTCh = rte -> rteTC(rte, sh, D);

julia> ijs = pairwisesavings(rteTCh, sh)     # Calculate pairwise savings (pairs with highest savings are first)
(i = [1, 1, 2], j = [2, 3, 3], s = [240.0, 180.0, 95.0])

julia> iˢ, jˢ, sˢ = ijs;     # destructures as the tuple of v0.2.8 did; ijs.s and ijs[3] are sˢ

julia> sˢ == ijs.s == ijs[3]
true

julia> # the same savings with the independent costs given: c(1) = 300, c(2) = 250, c(3) = 275
       pairwisesavings(rteTCh, sh; TC1 = [300, 250, 275])
(i = [1, 1, 2], j = [2, 3, 3], s = [240.0, 180.0, 95.0])
```

# Notes
- Only returns pairs with positive savings.
- Savings = TC1[i] + TC1[j] - cost(combined route), TC1[k] being cost([k,k]) by default.
"""
function pairwisesavings(rteTCh, sh; TC1 = nothing)
    n = nrow(sh)
    TC1 === nothing && (TC1 = [rteTCh([k, k]) for k in 1:n])
    length(TC1) == n || throw(ArgumentError("Independent shipment total cost must equal number of shipments."))
    iᵒ, jᵒ, sᵒ = Int[], Int[], Float64[]
    for i = 1:n-1
        for j = i+1:n
            s = TC1[i] + TC1[j] - _mincostinsert(i, [j, j], rteTCh)[2]
            s > 0 && (push!(iᵒ, i); push!(jᵒ, j); push!(sᵒ, s))
        end
    end
    sidx = sortperm(sᵒ, rev=true)
    return (i = iᵒ[sidx], j = jᵒ[sidx], s = sᵒ[sidx])
end

"""
    savings(rteTCh, sh; TC1 = nothing, ijs = pairwisesavings(rteTCh, sh; TC1)) -> Vector{Vector{Int}}

Construct routes for a Pickup and Delivery Problem (PDP) by the savings procedure of
Matlog's `savings.m`: the pairs of the savings list, largest saving first, are taken in turn, and
a pair joins routes only if the joined route costs less than the routes it replaces.

Unlike the standard Clarke-Wright algorithm (which concatenates routes at endpoints), a route is
joined to another by inserting its shipments, one at a time in the order they are loaded, into the
cheapest positions of the other with `mincostinsert`. For a pair `(i, j)` there are Matlog's three
cases:

1. Neither shipment is on a route: the shipments form a new route (the shorter of the two
   single-shipment routes is inserted into the longer; of equal length, into the costlier), kept if
   `c(i) + c(j) - c(route) > 0`, where `c(k)` is the cost of shipment `k` on a route of its own.
2. One is on a route: the other is inserted into it, kept if `c(k) + c(route) - c(new route) > 0`.
   A shipment already tried against a route that has not changed since is not tried again.
3. Both are on different routes: the shorter route is inserted into the longer, kept if the
   costs of the two routes exceed the cost of the combined one.

**A merge is never made unless it saves** (CR 39): v0.2.8 accepted a merge on the pair's saving
alone and could return routes that cost more than shipping each shipment by itself. The list is
passed over again until a pass makes no change or every shipment is on a route.

# Arguments
- `rteTCh`: Function that calculates route cost: `rteTCh(route) -> cost`.
          Should return `Inf` for infeasible routes (capacity, time windows, etc.); an insertion
          with no finite position is not made.
- `sh`: Shipments DataFrame where each row is a shipment requiring pickup and delivery.
- `TC1`: (keyword) the independent total cost of each shipment, a vector with one element per
  shipment, as in `pairwisesavings`. It is the cost the default savings list is made with **and** the
  `c(k)` of the merge tests above, so that a savings list and the merges it drives rank and accept on
  one cost. Matlog's `savings.m` has no such argument and tests each merge against `rteTCh([k, k])`,
  whatever cost its list was made with. The default, `nothing`, is `rteTCh([k, k])` for shipment `k`
  in both, and an unchanged call is unchanged.
- `ijs`: (keyword) the savings list, taken in the order given: the named tuple `(i, j, s)` that
  `pairwisesavings` returns (only the first two vectors are read; a plain tuple also works), or an `m x 3` matrix with a
  pair in each row, Matlog's `IJS`. The default is `pairwisesavings(rteTCh, sh)`, the pairs of
  positive saving, largest first. A list of your own is how the savings are changed before the
  routes are built, as Lecture 5.2's randomized savings does with its own `randreorder` (Matlog's
  `randreorder`; `makeRouting2.m` lines 148-153: `twoopt(savings(rTDh, sh, randreorder(IJS, 0.1)))`). A list with no pair gives
  no route.

# Returns
- Vector of the routes **formed**, each a vector of shipment indices, in the order they were
  formed; as in Matlog, **only the routes the procedure makes**. A shipment that no pair of the
  list joined to a route is on none of them, and is shipped on a route of its own, `[k, k]`,
  which the caller adds (Matlog's `sh2rte`; Lecture 5.2's `sh2rte(1:n, R)`). With v0.2.8's
  `savings` every shipment came back on a route, those in no saving as a single-shipment route
  among the routes formed (CR 57), so the index of a route said nothing about whether savings
  had formed it. No shipment is on more than one route.

# Example
```jldoctest
julia> using DataFrames

julia> # Lecture 5.2 Ex. 6(a): three shipments at one dollar a mile (locations 1 to 2, 3 to 4, 5 to 6);
       # the savings are 240, 180 and 95 and the route is (3, 1, 2, 2, 1, 3) at 430
       D = [  0 300  30 280  60 335
            300   0 280  30 335  60
             30 280   0 250  90 340
            280  30 250   0 340  90
             60 335  90 340   0 275
            335  60 340  90 275   0];

julia> sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6]);

julia> rteTCh = rte -> rteTC(rte, sh, D);

julia> routes = savings(rteTCh, sh)
1-element Vector{Vector{Int64}}:
 [3, 1, 2, 2, 1, 3]

julia> # the same list given by hand (Lecture 5.2's randomized savings does this with a reordered list)
       ijs = pairwisesavings(rteTCh, sh)
(i = [1, 1, 2], j = [2, 3, 3], s = [240.0, 180.0, 95.0])

julia> savings(rteTCh, sh; ijs = ijs)
1-element Vector{Vector{Int64}}:
 [3, 1, 2, 2, 1, 3]

julia> savings(rteTCh, sh; ijs = ([1], [2], [240.0]))   # one pair only: shipment 3 is on no route
1-element Vector{Vector{Int64}}:
 [1, 2, 2, 1]

julia> # the independent costs given: the list and the merge tests both use c(1) = 300, c(2) = 250, c(3) = 275
       savings(rteTCh, sh; TC1 = [300, 250, 275])
1-element Vector{Vector{Int64}}:
 [3, 1, 2, 2, 1, 3]
```

# Notes
- Constraints are enforced through `rteTCh` returning `Inf`.
- Each shipment appears exactly twice in its route (pickup and delivery).
- **Order of ties (CR 58):** in each returned route, where two neighboring loadings, or two neighboring unloadings, can trade places at exactly the same cost, the lower-numbered shipment is listed first; the cost is never changed.
- Matlog's `mincostinsert` also tries the positions ahead of the first stop and after the last,
  and skips a delivery directly after a stop at the same location as the one before; this
  function inserts with Logjam's `mincostinsert` (CR 38), which does neither, so a route cost
  that treats those positions differently (a depot route that must load before it unloads) can
  end at a different route from Matlog's.
"""
function savings(rteTCh, sh; TC1 = nothing, ijs = pairwisesavings(rteTCh, sh; TC1))
    n = nrow(sh)
    TC1 === nothing || length(TC1) == n || throw(ArgumentError("Independent shipment total cost must equal number of shipments."))
    iˢ, jˢ = _savings_list(ijs, n)
    return [_order_ties(r, rteTCh) for r in _savings(rteTCh, n, iˢ, jˢ; TC1)]
end

# the pairs of a savings list: the tuple (i, j, s) pairwisesavings returns (or anything whose first two
# elements are the vectors i and j), or an m x 3 matrix of Matlog's IJS
function _savings_list(ijs, n)
    if ijs isa AbstractMatrix
        size(ijs, 2) >= 2 || throw(ArgumentError("A savings list matrix needs a pair in each row (columns i, j, s)."))
        iˢ, jˢ = ijs[:, 1], ijs[:, 2]
    else
        length(ijs) >= 2 || throw(ArgumentError("A savings list is a tuple (i, j, s) or a matrix with a pair in each row."))
        iˢ, jˢ = ijs[1], ijs[2]
    end
    length(iˢ) == length(jˢ) || throw(ArgumentError("Incorrect savings list input: i and j differ in length."))
    iˢ, jˢ = Int.(collect(iˢ)), Int.(collect(jˢ))
    if !isempty(iˢ) && (min(minimum(iˢ), minimum(jˢ)) < 1 || max(maximum(iˢ), maximum(jˢ)) > n)
        throw(ArgumentError("Incorrect savings list input: a shipment index is outside 1:$n."))
    end
    return iˢ, jˢ
end

# Matlog's min cost insertion of route i into route j (mincostinsert.m): the shipments of the shorter route, in the order
# they are loaded, go one at a time into the longer route (equal lengths: into the costlier one);
# `nothing` and `Inf` when some shipment has no finite position
function _insert_route(rtei, rtej, rteTCh; insert = _mincostinsert)
    TCi, TCj = rteTCh(rtei), rteTCh(rtej)
    base, src = rtej, rtei
    if length(base) < length(src) || (length(base) == length(src) && TCj < TCi)
        base, src = rtei, rtej
    end
    rte, TC = _insertall(unique(src), base, rteTCh; insert)
    return isinf(TC) ? (nothing, Inf) : (rte, TC)
end

# Matlog's savings.m: the routes formed from the list (iˢ, jˢ), in the order formed. `insert` is the
# insertion `savings` makes its merges with, `insert(k, route, rteTCh) -> (route, cost)`; internal only
# (no public keyword, principle 8): `savings` passes Logjam's `mincostinsert` (CR 38), and the test
# suite passes Matlog's `mincostinsert.m` position set to reproduce MATLAB's routes (K7a-2).
function _savings(rteTCh, n, iˢ, jˢ; insert = _mincostinsert, TC1 = nothing)
    isempty(iˢ) && return Vector{Vector{Int}}()
    TC1 === nothing && (TC1 = [rteTCh([k, k]) for k in 1:n])      # a shipment on a route of its own
    inr = zeros(Int, n)                      # the route of each shipment, 0 for none
    rte = Union{Nothing,Vector{Int}}[]       # the routes; `nothing` for one absorbed by another
    TCr = Float64[]
    did = falses(n, n)                       # did[r, k]: shipment k already tried against route r
    Did = falses(n, n)                       # Did[r, s]: routes r and s already tried together
    nr = 0
    done = false
    while !done
        ischg = false
        for (ik, jk) in zip(iˢ, jˢ)
            if inr[ik] == 0 && inr[jk] == 0
                rij, TCij = _insert_route([ik, ik], [jk, jk], rteTCh; insert)
                if TC1[ik] + TC1[jk] - TCij > 0
                    nr += 1
                    push!(rte, rij); push!(TCr, TCij)
                    inr[ik] = nr; inr[jk] = nr
                    ischg = true
                end
            elseif (inr[ik] == 0) != (inr[jk] == 0)
                inr[ik] == 0 && ((ik, jk) = (jk, ik))        # ik is the one on a route
                r = inr[ik]
                if !did[r, jk]
                    rij, TCij = insert(jk, rte[r], rteTCh)
                    did[r, jk] = true
                    if TC1[jk] + TCr[r] - TCij > 0
                        rte[r] = rij; TCr[r] = TCij
                        inr[jk] = r
                        ischg = true
                        did[r, :] .= false
                        Did[r, :] .= false; Did[:, r] .= false
                    end
                end
            elseif inr[ik] != inr[jk] && !(Did[inr[ik], inr[jk]] || Did[inr[jk], inr[ik]])
                a, b = inr[ik], inr[jk]
                rij, TCij = _insert_route(rte[a], rte[b], rteTCh; insert)
                Did[a, b] = true; Did[b, a] = true
                if rij !== nothing && TCr[a] + TCr[b] - TCij > 0
                    inr[unique(rte[b])] .= a
                    rte[b] = nothing; TCr[b] = NaN
                    rte[a] = rij; TCr[a] = TCij
                    ischg = true
                end
            end
        end
        (!ischg || all(!=(0), inr)) && (done = true)
    end
    return Vector{Int}[r for r in rte if r !== nothing]
end

# =============================================================================
# The TSP as a MILP (CR 45): Lecture 5.1 Sec. 2's implementation rung. `subtours` needs nothing but Julia and is
# defined here; `TSP` needs JuMP and HiGHS, so it is declared here with its docstring and its method is the
# optimization extension's (LogjamJuMPExt). Both `public`, not exported (D10).
# =============================================================================

"""
    Logjam.subtours(succ) -> Vector{Vector{Int}}

The cycles of a successor vector: `succ[i]` is the node that follows node `i`, and each cycle is the nodes met by
following the arcs from its first node back to it, in that order. A single cycle is a tour; more than one are
**subtours**. `Logjam.TSP` calls it on each round's solution, whose successors are a permutation of the nodes.

The cycles are found in the order of their first nodes: the first starts at node 1, and each later one at the
lowest node not yet in a cycle.

# Arguments
- `succ`: the successor of each node `1, ..., n`, a permutation of `1:n` (not checked).

# Returns
- One vector of nodes for each cycle, each starting at its lowest node.

# Example
```jldoctest
julia> Logjam.subtours([2, 1, 4, 5, 3])      # 1 → 2 → 1, and 3 → 4 → 5 → 3
2-element Vector{Vector{Int64}}:
 [1, 2]
 [3, 4, 5]

julia> Logjam.subtours([3, 1, 4, 2])         # one cycle: a tour
1-element Vector{Vector{Int64}}:
 [1, 3, 4, 2]
```

# Notes
- Source: Lecture 5.1 Sec. 2's implementation rung (`5-rte-1.qmd`), with `TSP`, repeated by Lecture 5.3 (Code
  block 9); this is that definition (CR 45). **Declared `public`, not exported** (D10): a lecture's own
  `subtours`, defined after `using Logjam`, does not collide with it. It needs neither JuMP nor HiGHS, so it is
  available without the optimization extension.
"""
function subtours(succ::AbstractVector{<:Integer})
    S, seen = Vector{Vector{Int}}(), falses(length(succ))
    for k ∈ eachindex(succ)
        seen[k] && continue
        Sₖ, i = Int[], k
        while !seen[i]                 # follow the arcs back to k
            seen[i] = true
            push!(Sₖ, i)
            i = succ[i]
        end
        push!(S, Sₖ)
    end
    return S
end

"""
    Logjam.TSP(c) -> (TC, tour, rounds)

The optimal tour of a traveling salesman problem (TSP) on the arc costs `c`, by Lecture 5.1's math-programming
formulation (`@mdl-tsp`, the DFJ formulation): a binary `x[i, j]` for each arc `i ≠ j`, one if the tour goes from
node `i` directly to node `j`; minimize ``\\sum_{i,j} c_{ij} x_{ij}`` subject to (a) each node left once,
(b) each node entered once, and (c), single tour, ``\\sum_{i \\in S} \\sum_{j \\in S} x_{ij} \\le |S| - 1`` for each
subset ``S`` of the nodes, neither empty nor all of them.

Row (c) has one constraint for each subset, so the formulation is solved one round at a time (constraint
generation): rows (a) and (b) alone, the assignment problem, are solved first; `Logjam.subtours` finds the cycles
of the solution; row (c) is added for each of them, and the problem is solved again, until the solution is a single
tour. Each round solves the TSP with only some of its subtour constraints, so its cost is a lower bound on the
optimal tour's and the costs can only rise from round to round; the tour of the last round satisfies every subtour
constraint without their having been added, so it is optimal.

Needs JuMP and HiGHS: `using JuMP, HiGHS` loads the optimization extension that adds the method. Called without
them, it is a `MethodError` that says what to load. HiGHS solves each round silently with `mip_rel_gap = 0`, so
the tour is proved optimal rather than within HiGHS's default gap of 0.01%.

# Arguments
- `c`: square matrix of arc costs, `c[i, j]` the cost from node `i` to node `j`, for `n ≥ 2` nodes; symmetric or
  not. The diagonal is not read.

# Returns
A `NamedTuple` `(; TC, tour, rounds)`:
- `TC`: the optimal tour's cost, HiGHS's objective value (`Float64`).
- `tour`: the optimal tour as a location sequence, starting and ending at node 1.
- `rounds`: one `(; TC, S)` for each round, in order: the round's cost and its cycles, `Logjam.subtours` of its
  solution. The last round's `S` is the tour, as a single cycle.

Throws an `ArgumentError` for a matrix that is not square or has fewer than two nodes, and an `ErrorException`
naming HiGHS's termination status when a round does not end `OPTIMAL`.

# Example
Lecture 5.1's Ex. 2, the ten North Carolina cities of over 100,000 people under great circle distances, in three
rounds: the assignment problem's four subtours, then three, then the tour. (Shown, not run when the manual is built:
the manual's environment does not load JuMP and HiGHS.)

```julia-repl
julia> using JuMP, HiGHS, Logjam

julia> df = filter(r -> r.STFIP == st2fips(:NC) && r.POP > 100_000, usplace());

julia> P = hcat(df.LON, df.LAT);

julia> nc10 = Logjam.TSP(dists(P, P, :mi));

julia> round(nc10.TC, digits = 2), nc10.tour
(487.69, [1, 4, 6, 7, 10, 3, 2, 5, 9, 8, 1])

julia> [length(rd.S) for rd in nc10.rounds]      # the subtours of each round
3-element Vector{Int64}:
 4
 3
 1
```

# Notes
- Source: Lecture 5.1 Sec. 2's implementation rung (`5-rte-1.qmd`), which its Exs. 2, 3 and 4 solve, repeated by
  Lecture 5.3 (Code block 9) for the optimal tour of its 30 customers; this is that definition, the lecture's body
  in its order (CR 45). **Declared `public`, not exported** (D10): the body is the lecture's lesson, so a lecture's
  own `TSP`, defined after `using Logjam`, does not collide with it.
- HiGHS has no lazy-constraint callback, so each round is a new solve of one model that grows by the constraints
  added. Which subtours a round finds is the solution HiGHS returns, so the number of rounds can differ between
  HiGHS versions; the optimal cost cannot.
"""
function TSP end
