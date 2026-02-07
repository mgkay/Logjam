# RoadTools - Functions for working with road networks

# =============================================================================
# Distance Calculation
# =============================================================================

"""
    dgc(xyÃ¢â€šÂ, xyÃ¢â€šâ€š; unit=:mi) -> Float64

Calculate the great circle distance between two points.

Uses the haversine formula to compute the shortest distance over the Earth's surface
between two points specified by longitude-latitude coordinates.

# Arguments
- `xyÃ¢â€šÂ`: Tuple or vector of (longitude, latitude) for the first point.
- `xyÃ¢â€šâ€š`: Tuple or vector of (longitude, latitude) for the second point.
- `unit`: Distance unit, either `:mi` (miles, default) or `:km` (kilometers).

# Returns
- Great circle distance in the specified unit.

# Example
```julia
# Distance from Raleigh to Charlotte
dgc((-78.6382, 35.7796), (-80.8431, 35.2271))  # Ã¢â€°Ë† 130 miles
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
    dists(X1, X2, p=2; unit=:mi) -> Matrix{Float64}

Compute distance matrix between two point sets using specified metric.

**Replaces**: `Dgc` with unified interface supporting all metrics.

# Arguments
- `X1`: m×n matrix of m points in n dimensions
- `X2`: k×n matrix of k points in n dimensions
- `p`: Distance metric
  - `1`: Rectilinear (Manhattan) distance
  - `2`: Euclidean distance (default)
  - `:mi`, `:km`, `:rad`: Great circle distance (requires n=2, lon-lat coordinates)
- `unit`: Alternative way to specify geographic distance (e.g., `dists(X1, X2; unit=:mi)`)

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
D = dists(cities, dc; unit=:km)          # Kilometers (alternative syntax)
```

See also: [`dgc`](@ref), [`d1`](@ref), [`d2`](@ref)
"""
dists(X1::AbstractMatrix, X2::AbstractMatrix) = [d2(i, j) for i in eachrow(X1), j in eachrow(X2)]  # Default: Euclidean distance

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

# =============================================================================
# Network Manipulation
# =============================================================================

"""
    prune_reindex(dfL::DataFrame, dfN::DataFrame;
                  src_col=1, dst_col=2, node_col=1) -> Tuple{DataFrame, DataFrame}

Prune network to common vertices and reindex node IDs sequentially.

Removes any nodes that don't appear in links and any links that reference
non-existent nodes. Then reindexes all node IDs to be sequential starting from 1.

# Arguments
- `dfL`: Links DataFrame with columns [SRC, DST, ...].
- `dfN`: Nodes DataFrame with columns [IDX, ...].
- `src_col`: Source-node column in `dfL` (index or symbol, default `1`).
- `dst_col`: Destination-node column in `dfL` (index or symbol, default `2`).
- `node_col`: Node-ID column in `dfN` (index or symbol, default `1`).

# Returns
- Tuple of (pruned_links, pruned_nodes) DataFrames with sequential node IDs.

# Example
```julia
dfL, dfN = faf5links(), faf5nodes()
# Filter to North Carolina
dfL_nc = filter(r -> r.STFIP == 37, dfL)
dfN_nc = filter(r -> r.STATEID == 37, dfN)
# Prune and reindex
dfL_nc, dfN_nc = prune_reindex(dfL_nc, dfN_nc)
```
"""
function prune_reindex(dfL::DataFrame, dfN::DataFrame;
                       src_col::Union{Int,Symbol}=1,
                       dst_col::Union{Int,Symbol}=2,
                       node_col::Union{Int,Symbol}=1)
    # Find vertices common to both links and nodes
    link_vertices = union(Set(dfL[:, src_col]), Set(dfL[:, dst_col]))
    node_vertices = Set(dfN[:, node_col])
    vtx = collect(intersect(link_vertices, node_vertices))
    sort!(vtx)

    # Prune rows in dfL and dfN based on common vertices
    vtx_set = Set(vtx)
    dfL_out = filter(row -> (row[src_col] in vtx_set) && (row[dst_col] in vtx_set), dfL)
    dfN_out = filter(row -> row[node_col] in vtx_set, dfN)

    # Create mapping: old ID â†’ new sequential ID
    vtx_map = Dict(v => i for (i, v) in enumerate(vtx))

    # Reindex SRC and DST columns in links
    dfL_out = copy(dfL_out)
    dfL_out[!, src_col] = [vtx_map[v] for v in dfL_out[:, src_col]]
    dfL_out[!, dst_col] = [vtx_map[v] for v in dfL_out[:, dst_col]]

    # Reindex IDX column in nodes
    dfN_out = copy(dfN_out)
    dfN_out[!, node_col] = [vtx_map[v] for v in dfN_out[:, node_col]]
    sort!(dfN_out, node_col)

    return dfL_out, dfN_out
end

"""
    addconnectors(dfL::DataFrame, dfN::DataFrame, x_prime::Vector, y_prime::Vector;
                  circuity::Real=1.3, src_col=1, dst_col=2, dist_col=3,
                  node_col=1, x_col=2, y_col=3) -> Tuple{DataFrame, DataFrame}

Add connector links from demand points to a road network.

Uses Delaunay triangulation to efficiently find nearby network nodes for each
demand point, then creates connector links with estimated distances.

Demand points are assigned node IDs 1:n, and existing network nodes are
shifted by n (i.e., old node 1 becomes n+1).

# Arguments
- `dfL`: Links DataFrame with columns [SRC, DST, DIST, ...].
- `dfN`: Nodes DataFrame with columns [IDX, LON, LAT, ...].
- `x_prime`: Vector of demand point longitudes.
- `y_prime`: Vector of demand point latitudes.
- `circuity`: Circuity factor for connector distances (default 1.3).
- `src_col`, `dst_col`, `dist_col`: Link columns for source, destination, and distance.
- `node_col`, `x_col`, `y_col`: Node columns for node ID, longitude, and latitude.

# Returns
- Tuple of (new_links, new_nodes) DataFrames with connectors added.
- All input columns are preserved. Connector rows populate SRC/DST/DIST
  (and set `DIR`/`ONEWAY` to `0` when present); additional columns are `missing`.

# Example
```julia
dfL, dfN = faf5links(), faf5nodes()
# Define warehouse locations
warehouses_lon = [-78.9, -80.2, -79.5]
warehouses_lat = [35.8, 35.9, 36.1]
# Add connectors
dfL_conn, dfN_conn = addconnectors(dfL, dfN, warehouses_lon, warehouses_lat)
```
"""
function addconnectors(dfL::DataFrame, dfN::DataFrame, x_prime::Vector, y_prime::Vector;
                       circuity::Real=1.3,
                       src_col::Union{Int,Symbol}=1,
                       dst_col::Union{Int,Symbol}=2,
                       dist_col::Union{Int,Symbol}=3,
                       node_col::Union{Int,Symbol}=1,
                       x_col::Union{Int,Symbol}=2,
                       y_col::Union{Int,Symbol}=3)
    n = length(x_prime)
    length(y_prime) == n || error("x_prime and y_prime must have the same length")

    # Copy base coordinates
    x = copy(dfN[:, x_col])
    y = copy(dfN[:, y_col])
    node_ids = copy(dfN[:, node_col])

    # Build Delaunay triangulation for nearest-neighbor candidates
    tri = DelaunayTriangulation.triangulate(collect(zip(x, y)))

    # Build connector links (demand node i -> neighboring network node j+n)
    b_conn = Int[]
    e_conn = Int[]
    d_conn = Float64[]
    for i = 1:n
        t = DelaunayTriangulation.brute_force_search(tri, (x_prime[i], y_prime[i]))
        t = filter(v -> v > 0, t)  # remove ghost vertices
        for j in t
            push!(b_conn, i)
            push!(e_conn, n + j)
            push!(d_conn, circuity * dgc((x_prime[i], y_prime[i]), (x[j], y[j])))
        end
    end

    # Existing links: keep all columns, remap node ids to n+1:n+m
    m_nodes = nrow(dfN)
    node_map = Dict(node_ids[i] => (n + i) for i in 1:m_nodes)
    links_existing = copy(dfL)
    links_existing[!, src_col] = [node_map[v] for v in links_existing[:, src_col]]
    links_existing[!, dst_col] = [node_map[v] for v in links_existing[:, dst_col]]

    # Connector links: preserve schema, fill non-topology attributes as missing
    m = length(b_conn)
    link_cols = names(dfL)
    src_name = src_col isa Int ? names(dfL)[src_col] : String(src_col)
    dst_name = dst_col isa Int ? names(dfL)[dst_col] : String(dst_col)
    dist_name = dist_col isa Int ? names(dfL)[dist_col] : String(dist_col)
    links_conn = DataFrame()
    for name in link_cols
        s = Symbol(name)
        u = uppercase(String(name))
        if name == src_name
            links_conn[!, s] = b_conn
        elseif name == dst_name
            links_conn[!, s] = e_conn
        elseif name == dist_name
            links_conn[!, s] = d_conn
        elseif u == "DIR" || u == "ONEWAY"
            links_conn[!, s] = zeros(Int, m)
        else
            links_conn[!, s] = Vector{Missing}(missing, m)
        end
    end
    dfL_out = vcat(links_existing, links_conn; cols=:union)

    # Existing nodes: keep all columns, remap node ids to n+1:n+m
    nodes_existing = copy(dfN)
    nodes_existing[!, node_col] = collect((n + 1):(n + m_nodes))

    # Demand nodes: preserve schema, fill non-coordinate attributes as missing
    node_cols = names(dfN)
    node_name = node_col isa Int ? names(dfN)[node_col] : String(node_col)
    x_name = x_col isa Int ? names(dfN)[x_col] : String(x_col)
    y_name = y_col isa Int ? names(dfN)[y_col] : String(y_col)
    nodes_demand = DataFrame()
    for name in node_cols
        s = Symbol(name)
        if name == node_name
            nodes_demand[!, s] = collect(1:n)
        elseif name == x_name
            nodes_demand[!, s] = x_prime
        elseif name == y_name
            nodes_demand[!, s] = y_prime
        else
            nodes_demand[!, s] = Vector{Missing}(missing, n)
        end
    end
    dfN_out = vcat(nodes_demand, nodes_existing; cols=:union)

    return dfL_out, dfN_out
end

"""
    thin(dfL::DataFrame, dfN::DataFrame;
         agg::Dict{String, Function} = Dict(),
         must_match::Vector{String} = String[],
         keep_index::Bool = false,
         verbose::Bool = false)

Remove degree-2 nodes from a road network, merging their incident links.

When a node has exactly two neighbors, it can often be removed by merging
the two incident links into a single link. This simplifies the network
while preserving connectivity and total distance.

# Arguments
- `dfL`: Links DataFrame with columns [SRC, DST, DIST, ...].
- `dfN`: Nodes DataFrame with columns [IDX, LON, LAT, ...].
- `agg`: Dict mapping column names to aggregation functions (default: keep first value).
         Example: `Dict("SPEED" => minimum, "NHS" => maximum)`.
         Note: DIST is always summed regardless of this parameter.
- `must_match`: Vector of column names that must match for merging to occur.
                If attributes differ, the degree-2 node is preserved.
                Example: `["FCLASS", "STFIP"]`.
- `keep_index`: If true, returns merge log tracking which original links were combined.
- `verbose`: If true, prints thinning statistics (nodes, links, distance reduction).

# Returns
- If `keep_index=false`: `(thinned_links, thinned_nodes)` tuple.
- If `keep_index=true`: `(thinned_links, thinned_nodes, merge_log)` tuple
  where `merge_log` is a Dict mapping new link index to vector of original link indices.

# Example
```julia
# Simple thinning (distance only)
dfL_thin, dfN_thin = thin(dfL, dfN)

# Conservative: require functional class to match
dfL_thin, dfN_thin = thin(dfL, dfN; must_match=["FCLASS"])

# Custom aggregation with verbose output
dfL_thin, dfN_thin = thin(dfL, dfN;
    agg=Dict("SPEED" => minimum, "NHS" => maximum),
    must_match=["STFIP"], verbose=true)
```
"""
function thin(dfL::DataFrame, dfN::DataFrame;
              agg::AbstractDict{String, <:Function} = Dict{String, Function}(),
              must_match::Vector{String} = String[],
              keep_index::Bool = false,
              verbose::Bool = false)

    # Validate inputs
    @assert ncol(dfL) >= 3 "dfL must have at least 3 columns (SRC, DST, DIST)"
    @assert ncol(dfN) >= 3 "dfN must have at least 3 columns (IDX, LON, LAT)"

    # Get column names
    src_col = names(dfL)[1]
    dst_col = names(dfL)[2]
    dist_col = names(dfL)[3]
    idx_col = names(dfN)[1]

    # Validate must_match columns exist
    for col in must_match
        if !(col in names(dfL))
            error("must_match column '$col' not found in links DataFrame")
        end
    end

    # Work with copies to avoid modifying originals
    links = copy(dfL)
    if keep_index
        links[!, :_orig_idx] = [[i] for i in 1:nrow(links)]
    end

    # Build mutable edge store and adjacency once, then update incrementally.
    cols = names(links)
    edges = Dict{Int, Dict{String, Any}}()
    adj = Dict{Any, Set{Int}}()

    for (i, row) in enumerate(eachrow(links))
        erow = Dict{String, Any}()
        for c in cols
            erow[c] = row[c]
        end
        edges[i] = erow
        s, d = erow[src_col], erow[dst_col]
        push!(get!(adj, s, Set{Int}()), i)
        push!(get!(adj, d, Set{Int}()), i)
    end

    next_edge_id = Ref(nrow(links) + 1)

    other_end(edge::Dict{String, Any}, node) = edge[src_col] == node ? edge[dst_col] : edge[src_col]

    function remove_edge!(eid::Int)
        if !haskey(edges, eid)
            return
        end
        e = edges[eid]
        s, d = e[src_col], e[dst_col]
        if haskey(adj, s)
            delete!(adj[s], eid)
        end
        if haskey(adj, d)
            delete!(adj[d], eid)
        end
        delete!(edges, eid)
    end

    function add_edge!(erow::Dict{String, Any})
        eid = next_edge_id[]
        next_edge_id[] += 1
        edges[eid] = erow
        s, d = erow[src_col], erow[dst_col]
        push!(get!(adj, s, Set{Int}()), eid)
        push!(get!(adj, d, Set{Int}()), eid)
        return eid
    end

    function attrs_compatible(edge1::Dict{String, Any}, edge2::Dict{String, Any})
        if isempty(must_match)
            return true
        end
        for col in must_match
            if !isequal(edge1[col], edge2[col])
                return false
            end
        end
        return true
    end

    function merge_edges(edge1::Dict{String, Any}, edge2::Dict{String, Any}, through_node)
        node_a = other_end(edge1, through_node)
        node_b = other_end(edge2, through_node)
        new_row = Dict{String, Any}()
        for col in cols
            if col == src_col
                new_row[col] = node_a
            elseif col == dst_col
                new_row[col] = node_b
            elseif col == dist_col
                new_row[col] = edge1[col] + edge2[col]
            elseif col == "_orig_idx" && keep_index
                new_row[col] = vcat(edge1[col], edge2[col])
            elseif haskey(agg, col)
                new_row[col] = agg[col]([edge1[col], edge2[col]])
            else
                new_row[col] = edge1[col]
            end
        end
        return new_row, node_a, node_b
    end

    function find_direct_edge(node_a, node_b, skip1::Int, skip2::Int)
        for eid in get(adj, node_a, Set{Int}())
            if eid == skip1 || eid == skip2 || !haskey(edges, eid)
                continue
            end
            e = edges[eid]
            if other_end(e, node_a) == node_b
                return eid
            end
        end
        return nothing
    end

    # Queue of candidate degree-2 nodes.
    queue = Any[node for (node, eids) in adj if length(eids) == 2]
    qidx = 1

    while qidx <= length(queue)
        node = queue[qidx]
        qidx += 1

        node_edges = get(adj, node, Set{Int}())
        if length(node_edges) != 2
            continue
        end

        eids = collect(node_edges)
        eid1, eid2 = eids[1], eids[2]
        if !(haskey(edges, eid1) && haskey(edges, eid2))
            continue
        end

        edge1, edge2 = edges[eid1], edges[eid2]
        neighbor1 = other_end(edge1, node)
        neighbor2 = other_end(edge2, node)

        if neighbor1 == neighbor2
            continue
        end

        if !attrs_compatible(edge1, edge2)
            continue
        end

        new_dist = edge1[dist_col] + edge2[dist_col]
        existing_eid = find_direct_edge(neighbor1, neighbor2, eid1, eid2)
        if !isnothing(existing_eid)
            existing_edge = edges[existing_eid]
            if !(new_dist < existing_edge[dist_col])
                continue
            end
            existing_neighbors = (existing_edge[src_col], existing_edge[dst_col])
            remove_edge!(existing_eid)
            append!(queue, [existing_neighbors[1], existing_neighbors[2]])
        end

        merged, node_a, node_b = merge_edges(edge1, edge2, node)
        remove_edge!(eid1)
        remove_edge!(eid2)
        add_edge!(merged)

        append!(queue, [node, node_a, node_b])
    end

    # Rebuild links DataFrame from active edge store.
    edge_ids_sorted = sort!(collect(keys(edges)))
    rows = Vector{NamedTuple}(undef, length(edge_ids_sorted))
    for (k, eid) in enumerate(edge_ids_sorted)
        e = edges[eid]
        rows[k] = (; (Symbol(c) => e[c] for c in cols)...)
    end
    links = DataFrame(rows)

    # Build merge_log if requested
    merge_log = Dict{Int, Vector{Int}}()
    if keep_index
        for (i, row) in enumerate(eachrow(links))
            merge_log[i] = row[:_orig_idx]
        end
        select!(links, Not(:_orig_idx))
    end

    # Prune nodes to only those appearing in remaining links
    remaining_nodes = union(Set(links[:, src_col]), Set(links[:, dst_col]))
    nodes_out = filter(row -> row[idx_col] in remaining_nodes, dfN)

    # Print statistics if verbose
    if verbose
        orig_dist = sum(dfL[:, dist_col])
        thin_dist = sum(links[:, dist_col])
        println("Thinning Statistics:")
        println("  Nodes: $(nrow(dfN)) â†’ $(nrow(nodes_out)) " *
                "(-$(nrow(dfN) - nrow(nodes_out)), " *
                "$(round(100*(1 - nrow(nodes_out)/nrow(dfN)), digits=1))%)")
        println("  Links: $(nrow(dfL)) â†’ $(nrow(links)) " *
                "(-$(nrow(dfL) - nrow(links)), " *
                "$(round(100*(1 - nrow(links)/nrow(dfL)), digits=1))%)")
        println("  Total distance: $(round(orig_dist, digits=1)) â†’ " *
                "$(round(thin_dist, digits=1)) mi " *
                "($(round(100*thin_dist/orig_dist, digits=1))%)")
    end

    if keep_index
        return links, nodes_out, merge_log
    else
        return links, nodes_out
    end
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
using Graphs
g = SimpleGraph(5)
add_edge!(g, 1, 2); add_edge!(g, 2, 3)
lon = [-78.0, -79.0, -80.0, -81.0, -82.0]
lat = [35.0, 35.5, 36.0, 35.5, 35.0]
x_line = x2ln(g, lon)
y_line = x2ln(g, lat)
lines!(ax, x_line, y_line)
```
"""
function x2ln(g, x)
    vcat(map(e -> [x[Graphs.src(e)], x[Graphs.dst(e)], NaN], Graphs.edges(g))...)
end

"""
    links2graph(dfL::DataFrame; weight=3, ab_weight=nothing, ba_weight=nothing,
                dir_col=:DIR, oneway_val=1) -> SimpleWeightedDiGraph

Convert a links DataFrame to a directed weighted graph.

Creates a `SimpleWeightedDiGraph` where edge weights come from the specified column.
By default, roads are bidirectional unless marked as one-way via `dir_col`.

# Arguments
- `dfL`: Links DataFrame with columns [SRC, DST, weight_col, ...].
- `weight`: Weight column - either column index (default 3) or column name symbol.
- `ab_weight`: Optional symbol for Aâ†’B weight column (overrides `weight` for forward edges).
- `ba_weight`: Optional symbol for Bâ†’A weight column (overrides `weight` for reverse edges).
- `dir_col`: Column symbol indicating directionality (default `:DIR`).
- `oneway_val`: Value in `dir_col` that indicates one-way Aâ†’B only (default `1`).

# Returns
- `SimpleWeightedDiGraph` with weighted directed edges.

# Examples
```julia
# Load FAF5 road network
links = faf5links()

# Default: use column 3 (DIST) for symmetric weights
g = links2graph(links)

# Asymmetric weights using FAF5 travel times
g = links2graph(links, ab_weight=:AB_TIME, ba_weight=:BA_TIME)
```

# Notes
- Roads are bidirectional by default. One-way roads are identified when
  `dir_col` exists and equals `oneway_val`.
- For FAF5 data, `DIR=1` indicates one-way (Aâ†’B only), `DIR=0` is bidirectional.
- Edges with zero or negative weights are skipped.
"""
function _links2graph_core(dfL::DataFrame;
                           weight::Union{Int,Symbol}=3,
                           ab_weight::Union{Symbol,Nothing}=nothing,
                           ba_weight::Union{Symbol,Nothing}=nothing,
                           dir_col::Symbol=:DIR,
                           oneway_val=1)

    # Determine which columns to use for weights
    use_asymmetric = !isnothing(ab_weight) || !isnothing(ba_weight)

    if use_asymmetric
        # Asymmetric mode: use specified columns
        ab_col = isnothing(ab_weight) ? weight : ab_weight
        ba_col = isnothing(ba_weight) ? weight : ba_weight

        # Validate columns exist
        if ab_col isa Symbol && !(ab_col in propertynames(dfL))
            error("Column :$ab_col not found in DataFrame.")
        end
        if ba_col isa Symbol && !(ba_col in propertynames(dfL))
            error("Column :$ba_col not found in DataFrame.")
        end

        w_ab = dfL[!, ab_col]
        w_ba = dfL[!, ba_col]
    else
        # Symmetric mode: use single weight column for both directions
        if weight isa Symbol && !(weight in propertynames(dfL))
            error("Weight column :$weight not found in DataFrame.")
        end
        w_ab = dfL[!, weight]
        w_ba = w_ab  # Same reference for symmetric
    end

    # Access SRC and DST columns (positional)
    src_col = dfL[:, 1]
    dst_col = dfL[:, 2]

    # Check for direction column
    has_dir = dir_col in propertynames(dfL)
    d_col = has_dir ? dfL[!, dir_col] : nothing

    # Pre-allocate edge vectors (estimate 2 edges per row for bidirectional)
    n_est = 2 * nrow(dfL)
    src_vec = Vector{Int}()
    dst_vec = Vector{Int}()
    wgt_vec = Vector{Float64}()
    sizehint!(src_vec, n_est)
    sizehint!(dst_vec, n_est)
    sizehint!(wgt_vec, n_est)

    # Build edges
    for i in 1:nrow(dfL)
        u, v = src_col[i], dst_col[i]

        # Forward edge (A â†’ B) with AB weight
        val_ab = Float64(w_ab[i])
        if val_ab > 1e-10
            push!(src_vec, u)
            push!(dst_vec, v)
            push!(wgt_vec, val_ab)
        end

        # Reverse edge (B â†’ A) with BA weight, unless one-way
        is_oneway = has_dir && (d_col[i] == oneway_val)
        if !is_oneway
            val_ba = use_asymmetric ? Float64(w_ba[i]) : val_ab
            if val_ba > 1e-10
                push!(src_vec, v)
                push!(dst_vec, u)
                push!(wgt_vec, val_ba)
            end
        end
    end

    return SimpleWeightedGraphs.SimpleWeightedDiGraph(src_vec, dst_vec, wgt_vec)
end

# =============================================================================
# Network Construction with Optional Auto-Reindex
# =============================================================================

"""
    links2graph(dfL::DataFrame; weight=3, ab_weight=nothing, ba_weight=nothing,
                dir_col=:DIR, oneway_val=1, reindex=:auto, return_map=false,
                sparse_ratio=10, max_id_threshold=500_000,
                src_col=1, dst_col=2) -> SimpleWeightedDiGraph or (SimpleWeightedDiGraph, Dict, Dict)

Convert a links DataFrame to a directed weighted graph, with optional auto-reindexing.

This method can reindex sparse or non-sequential node IDs to avoid creating very
large graphs with many unused vertices.

# Arguments
- `dfL`: Links DataFrame with columns [SRC, DST, weight_col, ...].
- `weight`, `ab_weight`, `ba_weight`, `dir_col`, `oneway_val`: Same as core graph conversion.
- `reindex`: `:auto` (default), `true`, or `false`.
  - `:auto` reindexes if node IDs are non-integer, or if
    `maximum(node_id) > max_id_threshold`, or
    `maximum(node_id) > sparse_ratio * n_unique_ids`.
  - `true` always reindexes.
  - `false` never reindexes (requires integer node IDs).
- `return_map`: If `true`, returns `(graph, id_map, inv_map)`.
  - `id_map`: `Dict{ID,Int}` mapping old IDs to new IDs.
  - `inv_map`: `Dict{Int,ID}` mapping new IDs to old IDs.
  - When reindexing is not performed, these maps are identity maps.
- `sparse_ratio`: Threshold for `:auto` reindexing. Default `10`.
- `max_id_threshold`: Absolute max node ID threshold for `:auto` reindexing. Default `500_000`.
- `src_col`, `dst_col`: Source and destination columns (index or symbol). Defaults to 1 and 2.

# Returns
- `SimpleWeightedDiGraph`, or a tuple with mapping dictionaries if `return_map=true`.
"""
function links2graph(dfL::DataFrame;
                     weight::Union{Int,Symbol}=3,
                     ab_weight::Union{Symbol,Nothing}=nothing,
                     ba_weight::Union{Symbol,Nothing}=nothing,
                     dir_col::Symbol=:DIR,
                     oneway_val=1,
                     reindex::Union{Symbol,Bool}=:auto,
                     return_map::Bool=false,
                     sparse_ratio::Real=10,
                     max_id_threshold::Real=500_000,
                     src_col::Union{Int,Symbol}=1,
                     dst_col::Union{Int,Symbol}=2)

    src_ids = dfL[:, src_col]
    dst_ids = dfL[:, dst_col]
    node_id_type = promote_type(eltype(src_ids), eltype(dst_ids))
    node_id_set = Set{node_id_type}()
    for v in src_ids
        push!(node_id_set, v)
    end
    for v in dst_ids
        push!(node_id_set, v)
    end
    node_ids = collect(node_id_set)

    do_reindex = false
    node_ids_eltype = eltype(node_ids)

    if reindex == true
        do_reindex = true
    elseif reindex == false
        if !(node_ids_eltype <: Integer)
            error("Non-integer node IDs require reindexing. Use reindex=true or reindex=:auto.")
        end
        do_reindex = false
    elseif reindex == :auto
        if node_ids_eltype <: Integer
            max_id = maximum(node_ids)
            n_unique = length(node_ids)
            do_reindex = (max_id > max_id_threshold) || (max_id > sparse_ratio * n_unique)
        else
            do_reindex = true
        end
    else
        error("Invalid reindex option. Use :auto, true, or false.")
    end

    function normalize_links_df(df_in)
        if src_col == 1 && dst_col == 2
            return df_in, weight
        end

        orig_names = names(df_in)
        weight_sym = weight isa Int ? Symbol(orig_names[weight]) : weight
        src_name = src_col isa Int ? orig_names[src_col] : String(src_col)
        dst_name = dst_col isa Int ? orig_names[dst_col] : String(dst_col)
        keep = [n for n in orig_names if n != src_name && n != dst_name]
        df_out = DataFrame()
        df_out[!, :SRC] = df_in[!, src_col]
        df_out[!, :DST] = df_in[!, dst_col]
        for n in keep
            df_out[!, Symbol(n)] = df_in[!, n]
        end
        return df_out, weight_sym
    end

    if !do_reindex
        df_graph, weight_sym = normalize_links_df(dfL)
        g = _links2graph_core(df_graph;
            weight=weight_sym, ab_weight=ab_weight, ba_weight=ba_weight,
            dir_col=dir_col, oneway_val=oneway_val)
        if return_map
            id_map = Dict{eltype(node_ids), eltype(node_ids)}(v => v for v in node_ids)
            inv_map = Dict{eltype(node_ids), eltype(node_ids)}(v => v for v in node_ids)
            return g, id_map, inv_map
        end
        return g
    end

    sort_ids = try
        sort(collect(node_ids))
    catch e
        if e isa MethodError || e isa ArgumentError
            # Fallback for mixed/incomparable ID types: preserve first-seen order.
            seen = Set{Any}()
            ordered = Any[]
            for v in src_ids
                if !(v in seen)
                    push!(seen, v)
                    push!(ordered, v)
                end
            end
            for v in dst_ids
                if !(v in seen)
                    push!(seen, v)
                    push!(ordered, v)
                end
            end
            ordered
        else
            rethrow(e)
        end
    end
    id_map = Dict{eltype(sort_ids), Int}(id => i for (i, id) in enumerate(sort_ids))
    inv_map = Dict{Int, eltype(sort_ids)}(i => id for (i, id) in enumerate(sort_ids))

    dfL_re = copy(dfL)
    dfL_re[!, src_col] = [id_map[v] for v in src_ids]
    dfL_re[!, dst_col] = [id_map[v] for v in dst_ids]

    df_graph, weight_sym = normalize_links_df(dfL_re)
    g = _links2graph_core(df_graph;
        weight=weight_sym, ab_weight=ab_weight, ba_weight=ba_weight,
        dir_col=dir_col, oneway_val=oneway_val)

    if return_map
        return g, id_map, inv_map
    end
    @warn "links2graph reindexed node IDs. Pass return_map=true to get the ID mapping."
    return g
end

# =============================================================================
# Network Cropping and Shortest Paths
# =============================================================================

"""
    cropnetwork(nodes::DataFrame, links::DataFrame, x, y;
                xexpand=0.1, yexpand=0.1) -> Tuple{DataFrame, DataFrame}

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

# Returns
- Tuple of (cropped_links, cropped_nodes) with sequential node IDs.

# Example
```julia
nodes, links = faf5nodes(), faf5links()
cities = filter(r -> r.ST == :NC && r.POP > 100_000, usplace())
links_nc, nodes_nc = cropnetwork(nodes, links, cities.LON, cities.LAT)
```
"""
function cropnetwork(nodes::DataFrame, links::DataFrame, x, y;
                     xexpand::Real=0.1, yexpand::Real=0.1)
    # Get bounding box with expansion
    ((xmin, xmax), (ymin, ymax)), _ = mapbbox(x, y; xexpand=xexpand, yexpand=yexpand)

    # Filter nodes within bounding box
    nodes_sub = filter(r -> (r.LON >= xmin) && (r.LON <= xmax) &&
                            (r.LAT >= ymin) && (r.LAT <= ymax), nodes)

    # Get valid node IDs
    valid_ids = Set(nodes_sub.IDX)

    # Filter links to those connecting valid nodes
    links_sub = filter(r -> (r.SRC in valid_ids) && (r.DST in valid_ids), links)

    # Prune and reindex
    return prune_reindex(links_sub, nodes_sub)
end

"""
    shortestpaths(g, weights, n::Int) -> Tuple{Matrix{Float64}, Vector{Vector{Int}}}

Compute shortest path distances and parent pointers from the first n nodes.

Uses Dijkstra's algorithm to compute shortest paths from each of the first n nodes
to all other nodes in the graph. Returns both the distance matrix and parent vectors
for path reconstruction.

# Arguments
- `g`: A Graphs.jl graph object.
- `weights`: Edge weight matrix (sparse or dense) where weights[i,j] is the cost from i to j.
- `n`: Number of source nodes to compute paths from (typically the number of demand points).

# Returns
- `D`: nÃ—n distance matrix where D[i,j] is the shortest distance from node i to node j.
- `P`: Vector of parent vectors for path reconstruction. P[i][j] gives the predecessor
       of node j on the shortest path from node i.

# Example
```julia
using Graphs, SparseArrays

# Load network and add 3 demand points
nodes, links = faf5nodes(), faf5links()
links, nodes = cropnetwork(nodes, links, [-79.0, -78.0], [35.5, 36.0])
locs_lon, locs_lat = [-78.5, -78.7, -78.3], [35.7, 35.8, 35.6]
links, nodes = addconnectors(links, nodes, locs_lon, locs_lat)

# Build graph and weight matrix
g = links2graph(links)
weights = sparse(links.SRC, links.DST, links.DIST, nv(g), nv(g))
weights = weights + weights'  # Make symmetric

# Compute paths from the 3 demand points
D, P = shortestpaths(g, weights, 3)
```

# Notes
- The first n nodes are typically demand points added via `addconnectors`.
- Parent vectors can be used with `rte2lines` to reconstruct physical paths.
"""
function shortestpaths(g, weights, n::Int)
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
    shortestpaths(g::SimpleWeightedDiGraph, n::Int) -> Tuple{Matrix{Float64}, Vector{Vector{Int}}}

Compute shortest path distances and parent pointers from the first n nodes.

This method works with `SimpleWeightedDiGraph` from `links2graph`, using the
graph's internal edge weights directly.

# Arguments
- `g`: A SimpleWeightedDiGraph from `links2graph`.
- `n`: Number of source nodes to compute paths from (typically the number of demand points).

# Returns
- `D`: nÃ—n distance matrix where D[i,j] is the shortest distance from node i to node j.
- `P`: Vector of parent vectors for path reconstruction. P[i][j] gives the predecessor
       of node j on the shortest path from node i.

# Example
```julia
# Load network and add demand points
nodes, links = faf5nodes(), faf5links()
links, nodes = cropnetwork(nodes, links, [-79.0, -78.0], [35.5, 36.0])
locs_lon, locs_lat = [-78.5, -78.7, -78.3], [35.7, 35.8, 35.6]
links, nodes = addconnectors(links, nodes, locs_lon, locs_lat)

# Build weighted graph and compute paths in two lines
g = links2graph(links)
D, P = shortestpaths(g, 3)  # Paths from the 3 demand points
```

# Notes
- The first n nodes are typically demand points added via `addconnectors`.
- Parent vectors can be used with `rte2lines` to reconstruct physical paths.
- This method uses the weights embedded in the graph, no separate matrix needed.
"""
function shortestpaths(g::SimpleWeightedGraphs.SimpleWeightedDiGraph, n::Int)
    D = zeros(n, n)
    P = Vector{Vector{Int}}(undef, n)
    for i in 1:n
        ds = Graphs.dijkstra_shortest_paths(g, i)
        D[i, :] = ds.dists[1:n]
        P[i] = ds.parents
    end
    return D, P
end

