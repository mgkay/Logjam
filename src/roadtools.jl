# RoadTools - Functions for working with road networks
# =============================================================================
# Network columns, read by position (his 10/11 ruling, S1)
# =============================================================================

# The name of column `c` of `df` as a Symbol, whether `c` is a position or a name.
_colsym(df::AbstractDataFrame, c::Integer) = Symbol(names(df)[c])
_colsym(df::AbstractDataFrame, c::Union{Symbol,AbstractString}) = Symbol(c)

# The columns a network function reads, resolved once (C9): the links' source, destination and distance (or
# other weight), and the nodes' ID, longitude and latitude. The defaults are the positions of every
# network of the course (nodes IDX, LON, LAT; links SRC, DST, DIST), so a table with other column names
# works unchanged. `N` may be `nothing` for a function that reads the links alone.
function _netcols(N::Union{AbstractDataFrame,Nothing}, L::AbstractDataFrame;
                  src_col = 1, dst_col = 2, dist_col = 3, node_col = 1, x_col = 2, y_col = 3)
    return (src = _colsym(L, src_col), dst = _colsym(L, dst_col), dist = _colsym(L, dist_col),
            node = N === nothing ? nothing : _colsym(N, node_col),
            x = N === nothing ? nothing : _colsym(N, x_col),
            y = N === nothing ? nothing : _colsym(N, y_col))
end

# =============================================================================
# Network Manipulation
# =============================================================================

"""
    prune_reindex(dfN::AbstractDataFrame, dfL::AbstractDataFrame;
                  src_col=1, dst_col=2, node_col=1) -> Tuple{DataFrame, DataFrame}

Prune network to common vertices and reindex node IDs sequentially.

Removes any nodes that don't appear in links and any links that reference
non-existent nodes. Then reindexes all node IDs to be sequential starting from 1.

# Arguments
- `dfN`: Nodes DataFrame with columns [IDX, ...].
- `dfL`: Links DataFrame with columns [SRC, DST, ...].
- `src_col`: Source-node column in `dfL` (position or name, default `1`).
- `dst_col`: Destination-node column in `dfL` (position or name, default `2`).
- `node_col`: Node-ID column in `dfN` (position or name, default `1`).

# Returns
- Tuple of (pruned_nodes, pruned_links) DataFrames with sequential node IDs.

# Example
```julia
dfN, dfL = faf5nodes(), faf5links()
# Filter to North Carolina
dfL_nc = filter(r -> r.STFIP == 37, dfL)
dfN_nc = filter(r -> r.STATEID == 37, dfN)
# Prune and reindex
dfN_nc, dfL_nc = prune_reindex(dfN_nc, dfL_nc)
```
"""
function prune_reindex(dfN::AbstractDataFrame, dfL::AbstractDataFrame;
                       src_col::Union{Integer,Symbol,AbstractString}=1,
                       dst_col::Union{Integer,Symbol,AbstractString}=2,
                       node_col::Union{Integer,Symbol,AbstractString}=1)
    # Find vertices common to both links and nodes
    link_vertices = union(Set(dfL[:, src_col]), Set(dfL[:, dst_col]))
    node_vertices = Set(dfN[:, node_col])
    vtx = collect(intersect(link_vertices, node_vertices))
    sort!(vtx)

    # Prune rows in dfL and dfN based on common vertices
    vtx_set = Set(vtx)
    dfL_out = filter(row -> (row[src_col] in vtx_set) && (row[dst_col] in vtx_set), dfL)
    dfN_out = filter(row -> row[node_col] in vtx_set, dfN)

    # Create mapping: old ID → new sequential ID
    vtx_map = Dict(v => i for (i, v) in enumerate(vtx))

    # Reindex SRC and DST columns in links
    dfL_out = copy(dfL_out)
    dfL_out[!, src_col] = [vtx_map[v] for v in dfL_out[:, src_col]]
    dfL_out[!, dst_col] = [vtx_map[v] for v in dfL_out[:, dst_col]]

    # Reindex IDX column in nodes
    dfN_out = copy(dfN_out)
    dfN_out[!, node_col] = [vtx_map[v] for v in dfN_out[:, node_col]]
    sort!(dfN_out, node_col)

    return dfN_out, dfL_out
end

# =============================================================================
# The connector search: an exact local point location (C1, CR 62, CR 27)
# =============================================================================

const _CONNECTOR_K = 16                                   # nodes triangulated around a point, to start
const _CONNECTOR_KERNEL = DelaunayTriangulation.AdaptiveKernel()   # exact incircle and orientation tests

# The network's nodes and what the search builds from them only when it needs it: the triangulation of
# the whole network (for a point outside its hull, or when the nearest nodes never suffice) and its hull.
mutable struct _ConnectorSearch
    x::Vector{Float64}
    y::Vector{Float64}
    tri::Any
    hull::Any
end
_ConnectorSearch(x, y) = _ConnectorSearch(x, y, nothing, nothing)

function _whole_triangulation!(S::_ConnectorSearch)
    S.tri === nothing && (S.tri = DelaunayTriangulation.triangulate(collect(zip(S.x, S.y)); rng = _tri_rng()))
    return S.tri
end

# The network nodes of the whole triangulation's triangle that holds q (a ghost vertex dropped), ascending.
_whole_connector_nodes(tri, q) =
    sort!(filter(v -> v > 0, collect(DelaunayTriangulation.brute_force_search(tri, q))))

# Is q outside the convex hull of the network's nodes? (exact orientation tests on the hull's edges)
function _outside_hull!(S::_ConnectorSearch, q)
    if S.hull === nothing
        S.hull = DelaunayTriangulation.get_vertices(
            DelaunayTriangulation.convex_hull(collect(zip(S.x, S.y))))
    end
    h = S.hull                                            # counterclockwise, closed
    for m in 1:(length(h) - 1)
        a, b = (S.x[h[m]], S.y[h[m]]), (S.x[h[m+1]], S.y[h[m+1]])
        DelaunayTriangulation.is_negatively_oriented(
            DelaunayTriangulation.triangle_orientation(_CONNECTOR_KERNEL, a, b, q)) && return true
    end
    return false
end

# Does the circumcircle of the counterclockwise triangle (a, b, c) of nodes hold no other node strictly
# inside? One pass over the nodes with the exact predicate. A triangle whose circle is empty is a triangle of
# the Delaunay triangulation of the whole network.
function _empty_circle(S::_ConnectorSearch, a, b, c)
    pa, pb, pc = (S.x[a], S.y[a]), (S.x[b], S.y[b]), (S.x[c], S.y[c])
    for m in eachindex(S.x)
        (m == a || m == b || m == c) && continue
        DelaunayTriangulation.is_inside(DelaunayTriangulation.point_position_relative_to_circle(
            _CONNECTOR_KERNEL, pa, pb, pc, (S.x[m], S.y[m]))) && return false
    end
    return true
end

# The network nodes a new point at q is joined to: the corners of the triangle of the whole network's
# Delaunay triangulation that holds q (the two nodes of a hull edge for a point outside the hull), ascending.
# Triangulate the k nodes nearest q (k = 16 at first, doubled as needed), take the triangle that holds q, and
# accept it when its circumcircle is empty; otherwise try twice as many nodes. A point outside the hull of
# the network, and a network too small for k, use the whole triangulation.
function _connector_nodes(S::_ConnectorSearch, q::Tuple{Float64,Float64}; k::Int = _CONNECTOR_K)
    x, y = S.x, S.y
    n = length(x)
    d2 = [(x[i] - q[1])^2 + (y[i] - q[2])^2 for i in 1:n]
    k = min(k, n)
    while true
        k >= n && return _whole_connector_nodes(_whole_triangulation!(S), q)
        idx = sort!(partialsortperm(d2, 1:k))
        tri = try
            DelaunayTriangulation.triangulate([(x[i], y[i]) for i in idx]; rng = _tri_rng())
        catch
            nothing                                       # the k nearest nodes are collinear
        end
        if tri !== nothing
            t = DelaunayTriangulation.find_triangle(tri, q; rng = _tri_rng())
            if all(>(0), t)
                a, b, c = idx[t[1]], idx[t[2]], idx[t[3]]
                if DelaunayTriangulation.is_negatively_oriented(DelaunayTriangulation.triangle_orientation(
                       _CONNECTOR_KERNEL, (x[a], y[a]), (x[b], y[b]), (x[c], y[c])))
                    b, c = c, b
                end
                _empty_circle(S, a, b, c) && return sort!([a, b, c])
            elseif _outside_hull!(S, q)
                return _whole_connector_nodes(_whole_triangulation!(S), q)
            end
        end
        k = min(2k, n)
    end
end

"""
    addconnectors(dfN::AbstractDataFrame, dfL::AbstractDataFrame,
                  x_prime::AbstractVector, y_prime::AbstractVector;
                  circuity::Real=1.3, add_nf_nf::Bool=false, speed=nothing,
                  src_col=1, dst_col=2, dist_col=3,
                  node_col=1, x_col=2, y_col=3) -> Tuple{DataFrame, DataFrame}

Add connector links from demand points to a road network.

Each new point is joined to the three network nodes at the corners of the triangle that contains it,
in the Delaunay triangulation of the network's nodes (Lecture 4.1, Sec. 4, "Add connectors"), or to the
two nodes of the hull edge facing it when it lies outside every triangle. The triangle is found by an
exact point location that does not triangulate the whole network: the triangle of the point's 16
nearest nodes (doubling the number as needed) that contains it, accepted only when its circumcircle
holds no other network node, which makes it a triangle of the whole network's triangulation. The
connectors are the same as the whole triangulation gives, and the search takes the same code path at
every size of network (a crop of 8,691 nodes and the 95,699-node OpenStreetMap tile of Lecture 4.2
alike). A point outside the network's hull is the one case that uses the whole triangulation.

Demand points are assigned node IDs 1:n, and existing network nodes are
shifted by n (i.e., old node 1 becomes n+1).

**The links' distance column must be a distance, in miles** (the third column of `dfL`, `DIST` in FAF5 and
OpenStreetMap): a connector's value there is the great circle distance times `circuity`, so a table whose
third column holds minutes would mix the two. A graph of travel times is built from the distances
with `links2graph(L; weight = :time)`, which needs each connector's speed, the `speed` below.

# Arguments
- `dfN`: Nodes DataFrame with columns [IDX, LON, LAT, ...].
- `dfL`: Links DataFrame with columns [SRC, DST, DIST, ...].
- `x_prime`: Demand point longitudes (any vector, a view included).
- `y_prime`: Demand point latitudes.
- `circuity`: Circuity factor for connector distances (default 1.3).
- `add_nf_nf`: If `true`, also add direct connectors between neighboring demand points, from a Delaunay
  triangulation of the demand points, each at `circuity` times the great circle distance (default `false`:
  when the road distance between two new points is wanted, a connector between them is only an estimate
  that can become the shortest route, as in Lecture 4.1's Code block 45 and its annotation 1; Matlog
  leaves the choice to the caller too).
- `speed`: The speed in mph of the connectors, written to their `SPEED` column (added to the links if
  the table has none; `missing` on the road links then). With `nothing` (default) a connector has no
  speed. `links2graph(...; weight = :time)` reads it, so Lecture 4.2's `60d / 20` for a connector at
  20 mph is `speed = 20`.
- `src_col`, `dst_col`, `dist_col`: Link columns for source, destination, and distance.
- `node_col`, `x_col`, `y_col`: Node columns for node ID, longitude, and latitude.

# Returns
- Tuple of (new_nodes, new_links) DataFrames with connectors added.
- All input columns are preserved. Connector rows populate SRC/DST/DIST
  (and set `DIR`/`ONEWAY` to `0` when present); additional columns are `missing`.
  A `SOURCE` column marks the connectors with `"CONNECTOR"` (it is `missing` on the road links).

# Example
A square of four network nodes with a fifth near its center, and two new points, joined as Lecture 4.1's
Code block 40 joins its six: each new point to the three nodes of the triangle that holds it
(`isequal` selects the connectors, since `SOURCE` is `missing` on the road links).

```jldoctest
using DataFrames
nodes = DataFrame(IDX = 1:5, LON = [-78.0, -78.0, -79.0, -79.0, -78.5],
                  LAT = [35.0, 36.0, 35.0, 36.0, 35.6])
links = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 57.0])
N, L = addconnectors(nodes, links, [-78.5, -78.5], [35.2, 35.9]; speed = 20)
conn = L[isequal.(L.SOURCE, "CONNECTOR"), :]
(N.IDX, [(r.SRC, r.DST) for r in eachrow(conn)], collect(skipmissing(conn.SPEED)))

# output

([1, 2, 3, 4, 5, 6, 7], [(1, 3), (1, 5), (1, 7), (2, 4), (2, 6), (2, 7)], [20, 20, 20, 20, 20, 20])
```
"""
function addconnectors(dfN::AbstractDataFrame, dfL::AbstractDataFrame,
                       x_prime::AbstractVector, y_prime::AbstractVector;
                       circuity::Real=1.3,
                       add_nf_nf::Bool=false,
                       speed=nothing,
                       src_col::Union{Integer,Symbol,AbstractString}=1,
                       dst_col::Union{Integer,Symbol,AbstractString}=2,
                       dist_col::Union{Integer,Symbol,AbstractString}=3,
                       node_col::Union{Integer,Symbol,AbstractString}=1,
                       x_col::Union{Integer,Symbol,AbstractString}=2,
                       y_col::Union{Integer,Symbol,AbstractString}=3)
    n = length(x_prime)
    length(y_prime) == n || error("x_prime and y_prime must have the same length")
    speed === nothing || (speed isa Real && speed > 0) ||
        throw(ArgumentError("speed is the connectors' speed in mph, a positive number, not $(repr(speed))"))
    c = _netcols(dfN, dfL; src_col, dst_col, dist_col, node_col, x_col, y_col)

    # Copy base coordinates
    x = Float64.(dfN[:, c.x])
    y = Float64.(dfN[:, c.y])
    node_ids = copy(dfN[:, c.node])

    # Build connector links (demand node i -> neighboring network node j+n), each point's triangle
    # found by an exact local point location
    b_conn = Int[]
    e_conn = Int[]
    d_conn = Float64[]
    search = _ConnectorSearch(x, y)
    for i = 1:n
        q = (Float64(x_prime[i]), Float64(y_prime[i]))
        for j in _connector_nodes(search, q)
            push!(b_conn, i)
            push!(e_conn, n + j)
            push!(d_conn, circuity * dgc(q, (x[j], y[j])))
        end
    end

    # Phase 2: NF-to-NF connectors via Delaunay triangulation of demand points
    if add_nf_nf && n >= 2
        if n == 2
            # Two points: connect directly (Delaunay requires >= 3)
            push!(b_conn, 1); push!(e_conn, 2)
            push!(d_conn, circuity * dgc((x_prime[1], y_prime[1]), (x_prime[2], y_prime[2])))
        else
            # Triangulate NF points and extract Delaunay neighbor edges
            nf_pts = collect(zip(Float64.(x_prime), Float64.(y_prime)))
            nf_edges_ok = true
            try
                tri_nf = triangulate(nf_pts; rng = _tri_rng())
                seen = Set{Tuple{Int,Int}}()
                for i in 1:n
                    IJ = get_adjacent2vertex(tri_nf, i)
                    idx = collect(reduce(union, [Set(t) for t in IJ]))
                    filter!(j -> j > 0, idx)  # remove ghost vertices
                    for j in idx
                        edge = minmax(i, j)
                        if edge ∉ seen
                            push!(seen, edge)
                            push!(b_conn, i); push!(e_conn, j)
                            push!(d_conn, circuity * dgc(nf_pts[i], nf_pts[j]))
                        end
                    end
                end
            catch
                nf_edges_ok = false
            end
            if !nf_edges_ok
                # Fallback for degenerate cases (e.g., collinear points):
                # sort by distance from first point and connect as a chain
                order = sortperm([dgc(nf_pts[1], nf_pts[i]) for i in 1:n])
                for k in 1:(length(order)-1)
                    i, j = order[k], order[k+1]
                    push!(b_conn, i); push!(e_conn, j)
                    push!(d_conn, circuity * dgc(nf_pts[i], nf_pts[j]))
                end
            end
        end
    end

    # Existing links: keep all columns, remap node ids to n+1:n+m
    m_nodes = nrow(dfN)
    node_map = Dict(node_ids[i] => (n + i) for i in 1:m_nodes)
    links_existing = copy(dfL)
    links_existing[!, c.src] = [node_map[v] for v in links_existing[:, c.src]]
    links_existing[!, c.dst] = [node_map[v] for v in links_existing[:, c.dst]]

    # Connector links: preserve schema, fill non-topology attributes as missing
    m = length(b_conn)
    link_cols = names(dfL)
    links_conn = DataFrame()
    for name in link_cols
        s = Symbol(name)
        u = uppercase(String(name))
        if s == c.src
            links_conn[!, s] = b_conn
        elseif s == c.dst
            links_conn[!, s] = e_conn
        elseif s == c.dist
            links_conn[!, s] = d_conn
        elseif u == "DIR" || u == "ONEWAY"
            links_conn[!, s] = zeros(Int, m)
        elseif speed !== nothing && u == "SPEED"
            links_conn[!, s] = fill(speed, m)
        else
            links_conn[!, s] = Vector{Missing}(missing, m)
        end
    end
    # a speed for the connectors of a table with no SPEED column: a column of their own
    if speed !== nothing && !any(name -> uppercase(String(name)) == "SPEED", link_cols)
        links_conn[!, :SPEED] = fill(speed, m)
    end

    # Add SOURCE column for connector identification
    if !("SOURCE" in link_cols)
        links_existing[!, :SOURCE] = fill(missing, nrow(links_existing))
    end
    links_conn[!, :SOURCE] = fill("CONNECTOR", m)

    dfL_out = vcat(links_existing, links_conn; cols=:union)

    # Existing nodes: keep all columns, remap node ids to n+1:n+m
    nodes_existing = copy(dfN)
    nodes_existing[!, c.node] = collect((n + 1):(n + m_nodes))

    # Demand nodes: preserve schema, fill non-coordinate attributes as missing
    node_cols = names(dfN)
    nodes_demand = DataFrame()
    for name in node_cols
        s = Symbol(name)
        if s == c.node
            nodes_demand[!, s] = collect(1:n)
        elseif s == c.x
            nodes_demand[!, s] = collect(x_prime)
        elseif s == c.y
            nodes_demand[!, s] = collect(y_prime)
        else
            nodes_demand[!, s] = Vector{Missing}(missing, n)
        end
    end
    dfN_out = vcat(nodes_demand, nodes_existing; cols=:union)

    return dfN_out, dfL_out
end

"""
    thin(dfN::AbstractDataFrame, dfL::AbstractDataFrame) -> Tuple{DataFrame, DataFrame}

Thin a road network: remove its degree-2 nodes, replacing the two arcs at each with one whose cost is
their sum, and where that leaves two arcs between the same nodes in the same direction keep the one of
minimum cost (Lecture 4.1, Sec. 4, "Thin"; Matlog's `thin`). The procedure repeats until no node can be
removed, so a chain of any length becomes one link and a loop such as a beltway between two junctions
is eliminated.

A node is removed when its neighbors are two other nodes and it is passed through in every direction it
is used: two-way (an arc each way to each neighbor), or one-way (one arc in from one neighbor and one out
to the other). So a one-way chain is merged as a one-way chain, and a network with one link per
direction of travel, as OpenStreetMap's, keeps both of its directions (CR 25). Links are read as arcs by
`DIR` (0 two-way, 1 from `SRC` to `DST`, -1 from `DST` to `SRC`); a network with no `DIR` column is two-way.
The result does not depend on how the nodes are numbered: the nodes are visited in the order of the rows
of `dfN` (CR 18).

Columns are read by position: the first column of `dfN` is the node ID, and the first three of `dfL` are the
source, the destination and the distance.

# Arguments
- `dfN`: Nodes DataFrame with columns [IDX, LON, LAT, ...]. The IDs are integers, in any order.
- `dfL`: Links DataFrame with columns [SRC, DST, DIST, ...].

# Returns
- `(N, L)`, the thinned nodes and links, whatever the input (the number of values returned never
  changes): `N` holds the nodes that remain on a link and `L` the links. **The nodes of `N` are
  numbered `1:n` in the order they had, and `SRC` and `DST` are renumbered to match** (N6), so the
  tables are ready for `links2graph`, `addconnectors` and drawing a path by row, with no `prune_reindex`.
- `L` has every column of `dfL`, and one more, `MERGED`: the rows of `dfL` that make up each link, in
  order along the road. The distance of a merged link is the sum of its parts; every other column, a speed
  or a name, is that of its first link, and `DIR` is 0 for a link that can be traveled both ways.

# Example
Lecture 4.1, Code block 32, the schematic of I-40 around Raleigh (F24 slide 209): every degree-2 node
between the two junctions, and the whole Beltline, thin to one arc of 70.

```jldoctest
using DataFrames
XY0 =[1.33 -6.70; 1.27 -7.89; 1.67 -7.28; 2.97 -7.78; 4.05 -7.27; 4.45 -6.68;
       4.83 -7.91; 5.53 -6.62; 5.62 -7.66; 6.41 -7.47; 6.59 -6.79; 7.07 -7.86]
A0 = [1 3 5; 2 3 5; 3 4 20; 4 5 15; 5 6 10; 6 8 15; 8 9 15; 5 7 15;
      7 9 10; 9 10 10; 10 11 5; 10 12 5]
N0 = DataFrame(IDX = 1:12, X = XY0[:, 1], Y = XY0[:, 2])
L0 = DataFrame(SRC = A0[:, 1], DST = A0[:, 2], DIST = A0[:, 3])
tN0, tL0 = thin(N0, L0)
(tN0.IDX, tL0.SRC, tL0.DST, tL0.DIST)

# output

([1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 4], [3, 3, 4, 5, 6], [5, 5, 70, 5, 5])
```
"""
function thin(dfN::AbstractDataFrame, dfL::AbstractDataFrame)
    ncol(dfL) >= 3 || throw(ArgumentError("dfL must have at least 3 columns (SRC, DST, DIST)"))
    ncol(dfN) >= 3 || throw(ArgumentError("dfN must have at least 3 columns (IDX, LON, LAT)"))
    c = _netcols(dfN, dfL)

    # nodes: the row of each node ID
    ids = dfN[!, c.node]
    eltype(ids) <: Integer || throw(ArgumentError("the node IDs (first column of dfN) must be integers"))
    nn = nrow(dfN)
    row_of = Dict{Int,Int}()
    sizehint!(row_of, nn)
    for (r, id) in enumerate(ids)
        haskey(row_of, id) && throw(ArgumentError("node ID $id appears twice in the first column of dfN"))
        row_of[id] = r
    end

    # links as arcs on rows: an arc for each direction a link can be traveled (DIR 0 both, 1 forward
    # only, -1 backward only)
    m = nrow(dfL)
    T = eltype(dfL[!, c.dist])
    (T <: Real) || throw(ArgumentError("the weight (third column of dfL) must be numeric with no missing values"))
    s_id, d_id, w = dfL[!, c.src], dfL[!, c.dst], dfL[!, c.dist]
    dir = hasproperty(dfL, :DIR) ? dfL[!, :DIR] : zeros(Int, m)
    src = Vector{Int}(undef, m)
    dst = Vector{Int}(undef, m)
    for i in 1:m
        haskey(row_of, s_id[i]) && haskey(row_of, d_id[i]) ||
            throw(ArgumentError("link $i joins a node that is not in dfN"))
        src[i], dst[i] = row_of[s_id[i]], row_of[d_id[i]]
    end

    # the arcs (typed vectors), and for each node its out- and in-arcs by neighbor
    a_src = Int[]; a_dst = Int[]; a_w = T[]; a_members = Vector{Vector{Int}}()
    a_alive = Bool[]
    outs = [Dict{Int,Int}() for _ in 1:nn]
    ins = [Dict{Int,Int}() for _ in 1:nn]
    protected = falses(nn)                               # a node with a self-loop is not removed
    loops = Int[]

    function addarc!(u::Int, v::Int, wt, members::Vector{Int})
        e = get(outs[u], v, 0)
        if e != 0
            wt < a_w[e] || return                        # of parallel arcs the shorter is kept
            a_alive[e] = false
        end
        push!(a_src, u); push!(a_dst, v); push!(a_w, wt); push!(a_members, members); push!(a_alive, true)
        outs[u][v] = length(a_src)
        ins[v][u] = length(a_src)
        return
    end
    for i in 1:m
        u, v = src[i], dst[i]
        if u == v
            push!(loops, i); protected[u] = true
            continue
        end
        dir[i] == -1 || addarc!(u, v, w[i], [i])
        dir[i] == 1 || addarc!(v, u, w[i], [i])
    end

    # remove the degree-2 nodes, in row order, until none is left: a node whose neighbors are two other
    # nodes and that is passed through in every direction it is used
    function dropnode!(v::Int)
        for (u, e) in outs[v]
            a_alive[e] = false; delete!(ins[u], v)
        end
        for (u, e) in ins[v]
            a_alive[e] = false; delete!(outs[u], v)
        end
        empty!(outs[v]); empty!(ins[v])
    end
    queue = collect(1:nn)
    queued = trues(nn)
    head = 1
    while head <= length(queue)
        v = queue[head]; head += 1
        queued[v] = false
        protected[v] && continue
        nb = union(keys(outs[v]), keys(ins[v]))
        length(nb) == 2 || continue
        a, b = collect(nb)
        if haskey(outs[v], a) && haskey(ins[v], a) && haskey(outs[v], b) && haskey(ins[v], b)
            av, vb, bv, va = ins[v][a], outs[v][b], ins[v][b], outs[v][a]     # two-way pass-through
            new1 = (a, b, a_w[av] + a_w[vb], vcat(a_members[av], a_members[vb]))
            new2 = (b, a, a_w[bv] + a_w[va], vcat(a_members[bv], a_members[va]))
            dropnode!(v)
            addarc!(new1...)
            addarc!(new2...)
        elseif length(ins[v]) == 1 && length(outs[v]) == 1
            p = only(keys(ins[v])); q = only(keys(outs[v]))          # one-way pass-through p -> v -> q
            ein, eout = ins[v][p], outs[v][q]
            new1 = (p, q, a_w[ein] + a_w[eout], vcat(a_members[ein], a_members[eout]))
            dropnode!(v)
            addarc!(new1...)
        else
            continue
        end
        for u in (a, b)
            queued[u] || (push!(queue, u); queued[u] = true)
        end
    end
    # the links that remain: an arc and its reverse arc over the same links and of the same weight are one
    # two-way link; any other arc is a one-way link
    has_dir = hasproperty(dfL, :DIR)
    forward(e) = src[a_members[e][1]] == a_src[e]        # first link traveled from its SRC to its DST?
    done = falses(length(a_src))
    base = Int[]; lsrc = Int[]; ldst = Int[]; lw = T[]; ldir = Int[]; lmem = Vector{Int}[]
    for e in 1:length(a_src)
        (a_alive[e] && !done[e]) || continue
        done[e] = true
        u, v = a_src[e], a_dst[e]
        f = get(outs[v], u, 0)
        if f != 0 && !done[f] && a_w[f] == a_w[e] && sort(a_members[f]) == sort(a_members[e])
            done[f] = true
            x = forward(e) || !forward(f) ? e : f        # the arc that runs the way its first link does
            push!(base, a_members[x][1]); push!(lsrc, a_src[x]); push!(ldst, a_dst[x])
            push!(lw, a_w[x]); push!(ldir, 0); push!(lmem, a_members[x])
        elseif length(a_members[e]) == 1                 # an unmerged one-way link keeps its own orientation
            r = a_members[e][1]
            push!(base, r); push!(lsrc, src[r]); push!(ldst, dst[r]); push!(lw, a_w[e])
            push!(ldir, a_src[e] == src[r] ? 1 : -1); push!(lmem, a_members[e])
        else
            push!(base, a_members[e][1]); push!(lsrc, u); push!(ldst, v); push!(lw, a_w[e])
            push!(ldir, 1); push!(lmem, a_members[e])
        end
    end
    has_dir || all(==(0), ldir) || error("thin: a one-way arc remains in a network with no DIR column")
    for r in loops
        push!(base, r); push!(lsrc, src[r]); push!(ldst, dst[r]); push!(lw, w[r])
        push!(ldir, has_dir ? Int(dir[r]) : 0); push!(lmem, [r])
    end
    order = sortperm(minimum.(lmem))
    base, lsrc, ldst, lw, ldir, lmem = base[order], lsrc[order], ldst[order], lw[order], ldir[order], lmem[order]

    # the nodes still on a link, numbered from 1 in row order
    keep = falses(nn)
    keep[lsrc] .= true; keep[ldst] .= true
    newid = cumsum(keep)
    L = dfL[base, :]
    L[!, c.src] = newid[lsrc]
    L[!, c.dst] = newid[ldst]
    L[!, c.dist] = lw
    has_dir && (L[!, :DIR] = ldir)
    L[!, :MERGED] = lmem
    N = dfN[keep, :]
    N[!, c.node] = collect(1:nrow(N))
    return N, L
end

# =============================================================================
# Visualization Helpers
# =============================================================================

"""
    x2ln(g, x) -> Vector{Float64}

Convert graph edges to NaN-separated line coordinates for plotting.

Given a graph `g` and coordinate vector `x`, produces a vector suitable for
plotting all edges as lines with NaN separators.

# Arguments
- `g`: A Graphs.jl graph object.
- `x`: Vector of coordinates (e.g., longitudes or latitudes) indexed by vertex.

# Returns
- Vector with pattern [x[src], x[dst], NaN, x[src], x[dst], NaN, ...].

# Example
```julia
using Graphs, CairoMakie, GeoMakie
g = SimpleGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 2, 3)
lon = [-78.0, -79.0, -80.0]
lat = [35.0, 37.0, 36.0]
x_line = x2ln(g, lon)
y_line = x2ln(g, lat)
fig, ax = makemap(x_line, y_line)
lines!(ax, x_line, y_line)
fig
```
"""
function x2ln(g, x)
    vcat(map(e -> [x[Graphs.src(e)], x[Graphs.dst(e)], NaN], Graphs.edges(g))...)
end

"""
    x2ln(i, j, x) -> Vector{Float64}

Convert the links from `i[k]` to `j[k]` to NaN-separated line coordinates for plotting, with no graph to build.

`i` and `j` are vectors of indices of the same length, the links' `SRC` and `DST` of a network or the shipments'
`b` and `e` of a routing problem, and `x` is the vector of coordinates (longitudes or latitudes) they index. The result
is `[x[i[1]], x[j[1]], NaN, x[i[2]], x[j[2]], NaN, ...]`: one line segment for each link, in the order of the links.
It draws the same lines as `x2ln(g, x)` does for the graph `g` of those links, except that a pair of nodes joined by
more than one link has a segment for each, where the graph has one edge.

# Example
Lecture 4.1's Code block 34 draws the Interstate links around Raleigh through a graph built only to draw them,
`gR = SimpleWeightedGraph(rL.SRC, rL.DST, rL.DIST)` and `x2ln(gR, rN.LON)`; the links' own columns do it directly:

```jldoctest
SRC, DST = [1, 2, 3], [2, 3, 1]                   # a table's links (rL.SRC, rL.DST)
LON = [-78.0, -79.0, -80.0]                       # the nodes' longitudes (rN.LON)
println(x2ln(SRC, DST, LON))

# output

[-78.0, -79.0, NaN, -79.0, -80.0, NaN, -80.0, -78.0, NaN]
```

```julia
lines!(ax, x2ln(rL.SRC, rL.DST, rN.LON), x2ln(rL.SRC, rL.DST, rN.LAT); color = supc, linewidth = 1)
```

Lecture 5.2's Code block 9 defines `sh2ln(sh, x)` to draw each shipment from its origin to its destination; with the
shipments' index columns it is `x2ln(sh.b, sh.e, x)`:

```julia
lines!(ax, x2ln(sh.b, sh.e, x), x2ln(sh.b, sh.e, y), color=:red)     # was sh2ln(sh, x), sh2ln(sh, y)
```
"""
function x2ln(i::AbstractVector{<:Integer}, j::AbstractVector{<:Integer}, x::AbstractVector{<:Real})
    length(i) == length(j) || throw(ArgumentError("i and j must have the same length; got $(length(i)) and $(length(j))"))
    out = Vector{Float64}(undef, 3 * length(i))
    for (k, (a, b)) in enumerate(zip(i, j))
        out[3k-2] = x[a]
        out[3k-1] = x[b]
        out[3k] = NaN
    end
    return out
end

# ---- links2graph ---------------------------------------------------------------------------

# One weight per link and direction, as vectors: `weight` is a column of `dfL` (position or name), a
# `(forward, backward)` pair of columns or vectors, a vector, or `:time`.
function _link_weights(dfL::AbstractDataFrame, weight, c)
    m = nrow(dfL)
    col(x) = x isa AbstractVector ? x :
             (x isa Integer || x isa Symbol || x isa AbstractString) ? dfL[!, _colsym(dfL, x)] :
             throw(ArgumentError("weight must be a column, a (forward, backward) pair, a vector or :time, not $(repr(x))"))
    fab, fba = if weight isa Tuple
        length(weight) == 2 || throw(ArgumentError("a weight pair is (forward, backward)"))
        col(weight[1]), col(weight[2])
    else
        v = col(weight)
        v, v
    end
    (length(fab) == m && length(fba) == m) || throw(ArgumentError("a weight vector needs one value for each of the $m links"))
    return fab, fba
end

# Lecture 4.1's time rule (Code block 51): a link's minutes in a direction are FAF5's free-flow time there
# when it is positive, else 60 d / v at the link's SPEED v; a connector carries the SPEED that
# `addconnectors(...; speed)` gave it. `AB_TIME` and `BA_TIME` are absent from an OpenStreetMap network, which
# then has 60 d / v throughout. Only the directions a link can be traveled are computed.
function _link_minutes(dfL::AbstractDataFrame, dist, dir)
    m = nrow(dfL)
    spd = hasproperty(dfL, :SPEED) ? dfL[!, :SPEED] : fill(missing, m)
    tAB = hasproperty(dfL, :AB_TIME) ? dfL[!, :AB_TIME] : fill(missing, m)
    tBA = hasproperty(dfL, :BA_TIME) ? dfL[!, :BA_TIME] : fill(missing, m)
    function minutes(t, i)
        (!ismissing(t) && t > 0) && return Float64(t)
        v = spd[i]
        (!ismissing(v) && v > 0) || throw(ArgumentError(
            "link $i has no positive travel time and no positive SPEED: for a connector, pass " *
            "`speed` (mph) to addconnectors; otherwise fill the link's SPEED or give weight a column"))
        return 60 * dist[i] / v
    end
    wab = [dir[i] != -1 ? minutes(tAB[i], i) : 0.0 for i in 1:m]
    wba = [dir[i] != 1 ? minutes(tBA[i], i) : 0.0 for i in 1:m]
    return wab, wba
end

# The weights as Float64, each one a nonnegative number in the direction the link is traveled.
function _arc_weights(w::AbstractVector, used::AbstractVector{Bool}, which::AbstractString)
    out = zeros(Float64, length(w))
    for i in findall(used)
        x = w[i]
        (!ismissing(x) && x isa Real && isfinite(x) && x >= 0) || throw(ArgumentError(
            "the $which weight of link $i is $(repr(x)); it must be a nonnegative number"))
        out[i] = x
    end
    return out
end

# The direction of each link: 0 two-way, 1 from SRC to DST only, -1 from DST to SRC only.
function _link_dirs(dfL::AbstractDataFrame)
    hasproperty(dfL, :DIR) || return zeros(Int, nrow(dfL))
    d = dfL[!, :DIR]
    for (i, x) in enumerate(d)
        (!ismissing(x) && x in (-1, 0, 1)) || throw(ArgumentError(
            "DIR of link $i is $(repr(x)): 0 (two-way), 1 (from SRC to DST) or -1 (from DST to SRC)"))
    end
    return Int.(d)
end

"""
    links2graph(dfL::AbstractDataFrame; weight = 3, src_col = 1, dst_col = 2) -> SimpleWeightedDiGraph

The graph of a road network: the one Lecture 4.1 builds by hand (Code block 45, annotation 2), by its two
rules. Each link gives an arc in each direction it can be traveled, and of parallel arcs, those joining the
same nodes in the same direction, the shorter is kept. A link of zero length stays an arc.

A link can be traveled from `SRC` to `DST` unless its `DIR` is `-1`, and from `DST` to `SRC` unless its
`DIR` is `1`; a network with no `DIR` column is two-way. The source and destination of a link are columns
1 and 2 of `dfL` and node IDs are `1:n` (the network functions leave them so; `prune_reindex` renumbers),
which this checks; the graph is never renumbered.

# Arguments
- `dfL`: Links DataFrame with columns [SRC, DST, weight, ...], read by position.
- `weight`: what each arc weighs, one of
  - a column, by position or name (default `3`, the distance `DIST`): both directions weigh the same;
  - a `(forward, backward)` pair of columns or vectors, as FAF5's `(:AB_TIME, :BA_TIME)`;
  - a vector with a value for each link;
  - `:time`, Lecture 4.1's rule (Code block 51), in minutes: the free-flow time `AB_TIME` forward and
    `BA_TIME` backward where positive, otherwise `60 * DIST / SPEED` at the link's `SPEED` in mph. A network
    with no time columns, such as OpenStreetMap's, has `60 * DIST / SPEED` throughout, and a connector
    needs the `speed` that `addconnectors` fills (`speed = 20` in the lectures). A link with neither a
    positive time nor a positive speed in a direction it is traveled throws an `ArgumentError`.
- `src_col`, `dst_col`: Source and destination columns (position or name, default `1` and `2`).

# Returns
- A `SimpleWeightedDiGraph` whose `weights` matrix holds the arc weights, so `shortestpaths(g, n)`
  needs nothing more.

# Example
Lecture 4.1, Code block 45 builds this graph for Wake County's roads and two new points; here, three
links with a one-way link and a parallel one:

```jldoctest
using Graphs, DataFrames
L = DataFrame(SRC = [1, 1, 2], DST = [2, 2, 3], DIST = [5.0, 3.0, 4.0], DIR = [0, 0, 1])
g = links2graph(L)
(ne(g), weights(g)[1, 2], weights(g)[2, 1], weights(g)[2, 3], weights(g)[3, 2])

# output

(3, 3.0, 3.0, 4.0, 0.0)
```

The minutes of FAF5's two time columns, and 60 d / v where a link has no time (Lecture 4.1, Code block 51):

```jldoctest
using Graphs, DataFrames
L = DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [30.0, 10.0], SPEED = [60, 20],
              AB_TIME = [28.0, 0.0], BA_TIME = [31.0, 0.0], DIR = [0, 0])
g = links2graph(L; weight = :time)
(weights(g)[1, 2], weights(g)[2, 1], weights(g)[2, 3])

# output

(28.0, 31.0, 30.0)
```
"""
function links2graph(dfL::AbstractDataFrame; weight = 3,
                     src_col::Union{Integer,Symbol,AbstractString} = 1,
                     dst_col::Union{Integer,Symbol,AbstractString} = 2)
    c = _netcols(nothing, dfL; src_col, dst_col)
    s, d = dfL[!, c.src], dfL[!, c.dst]
    eltype(s) <: Integer && eltype(d) <: Integer ||
        throw(ArgumentError("the node IDs (columns $(c.src) and $(c.dst) of dfL) must be integers"))
    dir = _link_dirs(dfL)
    wab, wba = if weight === :time
        _link_minutes(dfL, dfL[!, c.dist], dir)
    else
        _link_weights(dfL, weight, c)
    end
    # node IDs are 1:n (the network functions leave them so; prune_reindex renumbers)
    n = isempty(s) ? 0 : max(maximum(s), maximum(d))
    isempty(s) || min(minimum(s), minimum(d)) >= 1 ||
        throw(ArgumentError("node IDs must be 1:n; use prune_reindex first"))
    seen = falses(n)
    seen[s] .= true
    seen[d] .= true
    all(seen) || throw(ArgumentError("node IDs must be 1:n, but $(count(!, seen)) of 1:$n are on no link; use prune_reindex first"))
    fw, bw = dir .!= -1, dir .!= 1
    w1, w2 = _arc_weights(wab, fw, "forward"), _arc_weights(wba, bw, "backward")
    return SimpleWeightedGraphs.SimpleWeightedDiGraph([s[fw]; d[bw]], [d[fw]; s[bw]], [w1[fw]; w2[bw]];
                                                      combine = min)
end

# =============================================================================
# Network Cropping and Shortest Paths
# =============================================================================

"""
    cropnetwork(nodes::AbstractDataFrame, links::AbstractDataFrame, x, y;
                xexpand=0.1, yexpand=0.1,
                src_col=1, dst_col=2, node_col=1, x_col=2, y_col=3) -> Tuple{DataFrame, DataFrame}

Crop a road network to a bounding box defined by coordinates.

Filters nodes to those within the expanded bounding box of the given coordinates,
then filters links to those connecting remaining nodes, and reindexes.

# Arguments
- `nodes`: Nodes DataFrame with columns [IDX, LON, LAT, ...].
- `links`: Links DataFrame with columns [SRC, DST, ...].
- `x`: Vector of longitudes defining the region of interest.
- `y`: Vector of latitudes defining the region of interest.
- `xexpand`: Expansion factor for longitude bounds (default 0.1).
- `yexpand`: Expansion factor for latitude bounds (default 0.1).
- `src_col`, `dst_col`: Source and destination columns of `links` (position or name, default `1`, `2`).
- `node_col`, `x_col`, `y_col`: ID, longitude and latitude columns of `nodes` (default `1`, `2`, `3`).
  Like every network function, `cropnetwork` reads its columns by position, so a table whose columns
  are not called `IDX`, `LON`, `LAT`, `SRC`, `DST` needs no renaming (his 10/11 ruling, S1).

# Returns
- Tuple of (cropped_nodes, cropped_links) with sequential node IDs.

# Example
```julia
nodes, links = faf5nodes(), faf5links()
cities = filter(r -> r.ST == :NC && r.POP > 100_000, usplace())
nodes_nc, links_nc = cropnetwork(nodes, links, cities.LON, cities.LAT)
```
"""
function cropnetwork(nodes::AbstractDataFrame, links::AbstractDataFrame, x, y;
                     xexpand::Real=0.1, yexpand::Real=0.1,
                     src_col::Union{Integer,Symbol,AbstractString}=1,
                     dst_col::Union{Integer,Symbol,AbstractString}=2,
                     node_col::Union{Integer,Symbol,AbstractString}=1,
                     x_col::Union{Integer,Symbol,AbstractString}=2,
                     y_col::Union{Integer,Symbol,AbstractString}=3)
    c = _netcols(nodes, links; src_col, dst_col, node_col, x_col, y_col)
    # Get bounding box with expansion
    return _cropbox(nodes, links, mapbbox(x, y; xexpand=xexpand, yexpand=yexpand), c)
end

"""
    cropnetwork(nodes::AbstractDataFrame, links::AbstractDataFrame, bb;
                xexpand=0.0, yexpand=0.0,
                src_col=1, dst_col=2, node_col=1, x_col=2, y_col=3) -> Tuple{DataFrame, DataFrame}

Crop a road network to the box `bb = ((xmin, xmax), (ymin, ymax))`, as `mapbbox` returns it: the nodes
inside it, the links between them, and sequential node IDs. It is `cropnetwork(nodes, links, x, y)` for
the box itself, with no expansion unless `xexpand` or `yexpand` is given (`mapbbox(bb; xexpand, yexpand)`
widens it). `osm_roads(bb; crop = true)` crops the streets it returns this way. The column keywords are
those of the method for points.

# Example
Keep the part of a four-node road inside a box, as Lecture 4.2's Code block 2 keeps the streets inside
the box around its two buildings:

```jldoctest
using DataFrames
N = DataFrame(IDX = 1:4, LON = [0.0, 1.0, 2.0, 3.0], LAT = [0.0, 0.0, 0.0, 0.0])
L = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 1.0, 1.0])
N2, L2 = cropnetwork(N, L, ((0.5, 2.5), (-1.0, 1.0)))
(N2.LON, L2.SRC, L2.DST)

# output

([1.0, 2.0], [1], [2])
```
"""
function cropnetwork(nodes::AbstractDataFrame, links::AbstractDataFrame,
                     bb::Tuple{Tuple{Real,Real},Tuple{Real,Real}};
                     xexpand::Real=0.0, yexpand::Real=0.0,
                     src_col::Union{Integer,Symbol,AbstractString}=1,
                     dst_col::Union{Integer,Symbol,AbstractString}=2,
                     node_col::Union{Integer,Symbol,AbstractString}=1,
                     x_col::Union{Integer,Symbol,AbstractString}=2,
                     y_col::Union{Integer,Symbol,AbstractString}=3)
    c = _netcols(nodes, links; src_col, dst_col, node_col, x_col, y_col)
    return _cropbox(nodes, links, mapbbox(bb; xexpand=xexpand, yexpand=yexpand), c)
end

# the nodes inside the box ((xmin, xmax), (ymin, ymax)), the links between them, renumbered
function _cropbox(nodes, links, box, c)
    ((xmin, xmax), (ymin, ymax)) = box

    # Filter nodes within bounding box
    lon, lat = nodes[!, c.x], nodes[!, c.y]
    inside = [(xmin <= lo <= xmax) && (ymin <= la <= ymax) for (lo, la) in zip(lon, lat)]
    nodes_sub = nodes[inside, :]

    # Get valid node IDs
    valid_ids = Set(nodes_sub[!, c.node])

    # Filter links to those connecting valid nodes
    keep = [(s in valid_ids) && (d in valid_ids) for (s, d) in zip(links[!, c.src], links[!, c.dst])]
    links_sub = links[keep, :]

    # Prune and reindex
    return prune_reindex(nodes_sub, links_sub; src_col = c.src, dst_col = c.dst, node_col = c.node)
end

"""
    shortestpaths(g::AbstractSimpleWeightedGraph, n::Integer) -> Tuple{Matrix{Float64}, Vector{Vector{Int}}}

Compute shortest path distances and parent pointers from the first n nodes.

Runs Dijkstra's procedure from each of the first `n` nodes of the weighted graph `g`, on the weights the
graph holds, and returns the distances between them and the predecessors of every node. `g` is any simple
weighted graph: the `SimpleWeightedDiGraph` of `links2graph`, or a `SimpleWeightedGraph` (undirected) such
as the one Lecture 4.1's Code block 57 builds from the thinned Interstates.

# Arguments
- `g`: A `SimpleWeightedDiGraph` or `SimpleWeightedGraph`.
- `n`: Number of source nodes to compute paths from (typically the number of demand points).

# Returns
- `D`: n×n distance matrix where D[i,j] is the shortest distance from node i to node j.
- `P`: Vector of parent vectors for path reconstruction. P[i][j] gives the predecessor
       of node j on the shortest path from node i.

# Example
Lecture 4.1, Code block 57: all-pairs hours between the intersections of a small undirected network.

```jldoctest
using SimpleWeightedGraphs
g = SimpleWeightedGraph([1, 2, 3], [2, 3, 1], [1.0, 2.0, 5.0])
D, P = shortestpaths(g, 3)
(D[1, 3], D[3, 1], tracepath(P[1], 1, 3))

# output

(3.0, 3.0, [1, 2, 3])
```

A road network of links, the last one-way, from `links2graph` (Lecture 4.1, Code block 45). The nodes
`addconnectors` puts first are the demand points, so `n` is how many of them there are.

```jldoctest
using DataFrames
links = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [10.0, 20.0, 15.0], DIR = [0, 0, 1])
D, P = shortestpaths(links2graph(links), 4)
(D[1, 4], D[4, 1], tracepath(P[1], 1, 4))

# output

(45.0, Inf, [1, 2, 3, 4])
```

# Notes
- The first n nodes are typically demand points added via `addconnectors`.
- Parent vectors give the physical path between two nodes with `tracepath`.
- `shortestpaths(g, weights, n)`, which took the weights as a separate matrix, is deprecated: put the
  weights in the graph (`links2graph`'s `weight`, or `SimpleWeightedDiGraph(I, J, W; combine = min)`).
"""
function shortestpaths(g::SimpleWeightedGraphs.AbstractSimpleWeightedGraph, n::Integer)
    n <= Graphs.nv(g) || throw(ArgumentError("n = $n is more than the $(Graphs.nv(g)) nodes of the graph"))
    D = zeros(n, n)
    P = Vector{Vector{Int}}(undef, n)
    for i in 1:n
        ds = Graphs.dijkstra_shortest_paths(g, i)
        D[i, :] = ds.dists[1:n]
        P[i] = ds.parents
    end
    return D, P
end

"""
    shortestpaths(g, weights, n::Integer) -> Tuple{Matrix{Float64}, Vector{Vector{Int}}}

**Deprecated.** The form that took the arc weights as a separate matrix. Put the weights in the graph
instead: `links2graph(links; weight)` builds it, and `shortestpaths(g, n)` runs on it. The method
still works.

# Arguments
- `g`: A Graphs.jl graph.
- `weights`: Edge weight matrix (sparse or dense) where weights[i,j] is the cost from i to j.
- `n`: Number of source nodes to compute paths from.

# Example
Where the weights are in the graph already, as Lecture 4.1's Code block 57 has them, the matrix is
`weights(g)` and the two forms give the same distances (not run as a doctest, since a deprecated call
warns):

```julia
using Graphs, SimpleWeightedGraphs
g = SimpleWeightedGraph([1, 2, 3], [2, 3, 1], [1.0, 2.0, 5.0])
D1, _ = shortestpaths(g, 3)                # the form to use
D2, _ = shortestpaths(g, weights(g), 3)    # deprecated; D2 == D1
```
"""
function shortestpaths(g, weights, n::Integer)
    Base.depwarn("`shortestpaths(g, weights, n)` is deprecated: put the weights in the graph " *
                 "(`links2graph(links; weight)`) and call `shortestpaths(g, n)`.", :shortestpaths)
    D = zeros(n, n)
    P = Vector{Vector{Int}}(undef, n)
    for i in 1:n
        ds = Graphs.dijkstra_shortest_paths(g, i, weights)
        D[i, :] = ds.dists[1:n]
        P[i] = ds.parents
    end
    return D, P
end

"""
    tracepath(parents::Vector{Int}, origin::Int, dest::Int) → Vector{Int}

Reconstruct a shortest-path node sequence from a Dijkstra parent vector.

Walk `parents` backwards from `dest` to `origin` and return the forward-ordered
node sequence.  Throws an `ArgumentError` if `dest` is unreachable from `origin`.

# Example
```julia
using Graphs

# Build a small network graph
dfN, dfL = faf5nodes(), faf5links()
dfN, dfL = cropnetwork(dfN, dfL, [-79.5, -78.5], [35.5, 36.0])
g = links2graph(dfL)
ds = Graphs.dijkstra_shortest_paths(g, 1)
path = tracepath(ds.parents, 1, 5)
```
"""
function tracepath(parents::Vector{Int}, origin::Int, dest::Int)
    return _tracepath(parents, origin, dest)
end

# the walk back from `dest` to `origin`, for a parent vector of any integer type
function _tracepath(parents::AbstractVector{<:Integer}, origin::Integer, dest::Integer)
    origin == dest && return [Int(origin)]
    parents[dest] == 0 && throw(ArgumentError("Node $dest is unreachable from node $origin"))
    path = [Int(dest)]
    curr = Int(dest)
    while curr != origin
        curr = Int(parents[curr])
        curr == 0 && throw(ArgumentError("Node $dest is unreachable from node $origin"))
        push!(path, curr)
    end
    return reverse!(path)
end

"""
    tracepath(P, i, j) -> Vector{Int}
    tracepath(P, seq) -> Vector{Int}

The node sequences of `shortestpaths`' parent vectors `P`, without indexing `P` by the origin.

`tracepath(P, i, j)` is `tracepath(P[i], i, j)`: the nodes of the shortest path from `i` to `j`, `i` first and `j` last,
and `[i]` when `i == j`. It throws an `ArgumentError` where `j` is unreachable from `i`.

`tracepath(P, seq)` is the path through a sequence of locations `seq` (a tour, or a route's `rte2loc`), each leg traced
along its shortest path: the nodes of `tracepath(P, seq[1], seq[2])`, then of `tracepath(P, seq[2], seq[3])`, and so on.
A location where one leg ends and the next begins is one node of the result, not two, and a leg from a location to itself
adds none; the result begins with `seq[1]` and ends with `seq[end]`. It is `[seq[1]]` for one location and `Int[]` for none.
It equals the course's `reduce(vcat, [tracepath(P[i], i, j)[1:end-1] for (i, j) in legs])` followed by `push!(path, seq[end])`.

# Example
Lecture 5.1's Code block 37 draws the optimal tour of the 100 NC counties along the roads, tracing each leg and dropping each
leg's last node before the next leg's first repeats it; Lecture 5.3's Code block 71 does the same for each route's
`rte2loc`:

```julia
# was: legs = zip(ncr.tour[1:end-1], ncr.tour[2:end])
#      path = reduce(vcat, [tracepath(Pr[i], i, j)[1:end-1] for (i, j) in legs]); push!(path, path[1])
path = tracepath(Pr, ncr.tour)
lines!(ax, Nc.LON[path], Nc.LAT[path]; color = redc, linewidth = 1.2)
```

```julia
path = tracepath(PT, rte2loc(r, shc, trc))       # was the reduce(vcat, ...) and push!(path, loc[end])
```

On a small network of links (the form of Lecture 4.1's Code block 57), the path through three locations:

```jldoctest
using DataFrames
links = DataFrame(SRC = [1, 2, 3, 4], DST = [2, 3, 4, 5], DIST = [10.0, 20.0, 15.0, 5.0], DIR = [0, 0, 0, 0])
D, P = shortestpaths(links2graph(links), 5)
(tracepath(P, 1, 4), tracepath(P, [1, 4, 2, 5]))

# output

([1, 2, 3, 4], [1, 2, 3, 4, 3, 2, 3, 4, 5])
```
"""
function tracepath(P::AbstractVector{<:AbstractVector{<:Integer}}, i::Integer, j::Integer)
    return _tracepath(P[i], i, j)
end

function tracepath(P::AbstractVector{<:AbstractVector{<:Integer}}, seq::AbstractVector{<:Integer})
    path = Int[]
    isempty(seq) && return path
    for k in 1:length(seq)-1
        leg = _tracepath(P[seq[k]], seq[k], seq[k+1])
        append!(path, @view leg[1:end-1])
    end
    push!(path, seq[end])
    return path
end

"""
    pathroads(p, L; name = :NAME, fallback = nothing, weight = 3, miles = false) -> DataFrame

The roads a path follows, in order, each road once for as long as the path stays on it: a numbered row
for each run of one name, with the steps it covers. Step `t` is the link from `p[t]` to `p[t+1]`, so a row
can be traced back into the path. It is Lecture 4.2's `streets` (Code block 8), for FAF5 and
OpenStreetMap links alike.

# Arguments
- `p`: The nodes of the path in order, as `tracepath` gives them.
- `L`: The links the path's graph was built from. `cropnetwork`, `thin` and `prune_reindex` renumber the
  nodes, so these must be the links, after any of them, whose graph `p` was found on.
- `name`: The column holding a link's road name (default `:NAME`).
- `fallback`: A column to read where `name` is `missing` or blank, such as FAF5's `:SIGN` ("I 40").
  A link with no name in either, a connector for one, is passed over without ending a run.
- `weight`: The column that picks among parallel links, the one of least weight, and that `miles` adds up
  (position or name, default `3`, the distance).
- `miles`: If `true`, a `Miles` column gives the weight along each run.

A step is read as the link from `p[t]` to `p[t+1]` that can be traveled that way: `SRC` to `DST` unless
its `DIR` is `-1`, or `DST` to `SRC` unless its `DIR` is `1`. A step along no link throws an `ArgumentError`.

# Returns
- A DataFrame with columns `Seg` (1, 2, ...), `Street` and `Steps` (the first and last step of the run,
  as `"3-7"`), and `Miles` with `miles = true`.

# Example
Lecture 4.2, Code block 8: a path along two streets, a connector at each end passed over.

```jldoctest
using DataFrames
L = DataFrame(SRC = [1, 2, 3, 4], DST = [2, 3, 4, 5], DIST = [0.5, 1.0, 2.0, 0.5],
              NAME = [missing, "Varsity Dr", "Varsity Dr", missing], DIR = [0, 1, 1, 0])
R = pathroads([1, 2, 3, 4, 5], L; miles = true)
(R.Seg, R.Street, R.Steps, R.Miles)

# output

([1], ["Varsity Dr"], ["2-3"], [3.0])
```
"""
function pathroads(p::AbstractVector{<:Integer}, L::AbstractDataFrame;
                   name = :NAME, fallback = nothing, weight = 3, miles::Bool = false)
    c = _netcols(nothing, L; dist_col = weight)
    nms = L[!, _colsym(L, name)]
    fbs = fallback === nothing ? nothing : L[!, _colsym(L, fallback)]
    dir = _link_dirs(L)
    w = L[!, c.dist]
    # the links of each ordered pair, in the direction they can be traveled
    byarc = Dict{Tuple{Int,Int},Vector{Int}}()
    for (i, (a, b)) in enumerate(zip(L[!, c.src], L[!, c.dst]))
        dir[i] != -1 && push!(get!(byarc, (a, b), Int[]), i)
        dir[i] != 1 && push!(get!(byarc, (b, a), Int[]), i)
    end
    label(i) = begin
        for col in (nms, fbs)
            col === nothing && continue
            x = col[i]
            (ismissing(x) || (x isa AbstractString && isempty(x))) || return String(x)
        end
        return missing
    end
    steps = length(p) - 1
    link = Vector{Int}(undef, max(steps, 0))
    for t in 1:steps
        cand = get(byarc, (p[t], p[t+1]), nothing)
        cand === nothing && throw(ArgumentError("step $t: no link can be traveled from node $(p[t]) to node $(p[t+1])"))
        link[t] = cand[argmin(w[cand])]            # of parallel links the least weight (the first of equals)
    end
    nm = [label(i) for i in link]
    t = findall(!ismissing, nm)                    # the steps with a name
    a = [i for i in eachindex(t) if i == 1 || nm[t[i]] != nm[t[i-1]]]
    b = isempty(a) ? Int[] : [a[2:end] .- 1; length(t)]     # each run's first and last named step
    out = DataFrame(Seg = collect(eachindex(a)), Street = String[nm[t[i]] for i in a],
                    Steps = String[string(t[i], "-", t[j]) for (i, j) in zip(a, b)])
    if miles
        # a run's weight: its steps, the unnamed ones in between included (a connector has no name)
        out.Miles = Float64[sum(Float64(w[link[s]]) for s in t[i]:t[j]) for (i, j) in zip(a, b)]
    end
    return out
end

# =============================================================================
# Graph Conversion Helpers (H5–H6)
# =============================================================================


