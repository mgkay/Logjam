# RoadTools - Functions for working with road networks

# =============================================================================
# Distance Calculation
# =============================================================================

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
function dgc(xy₁, xy₂; unit=:mi)
    length(xy₁) == length(xy₂) == 2 || error("Inputs must have length 2.")
    unit in [:mi, :km] || error("Unit must be :mi or :km")

    Δx, Δy = xy₂[1] - xy₁[1], xy₂[2] - xy₁[2]
    a = sind(Δy / 2)^2 + cosd(xy₁[2]) * cosd(xy₂[2]) * sind(Δx / 2)^2
    2 * asin(min(sqrt(a), 1.0)) * (unit == :mi ? 3958.75 : 6371.00)
end

"""
    Dgc(X₁, X₂; unit=:mi) -> Matrix{Float64}

Calculate great circle distance matrix between two sets of points.

Computes pairwise distances between all points in X₁ and all points in X₂.

# Arguments
- `X₁`: Matrix or DataFrame where each row is (longitude, latitude).
- `X₂`: Matrix or DataFrame where each row is (longitude, latitude).
- `unit`: Distance unit, either `:mi` (miles, default) or `:km` (kilometers).

# Returns
- Matrix of distances where element [i,j] is the distance from X₁[i,:] to X₂[j,:].

# Example
```julia
# Distance matrix between 3 origins and 4 destinations
origins = [-78.6 35.8; -80.8 35.2; -79.0 36.1]
dests = [-77.0 35.0; -78.0 36.0; -79.5 35.5; -81.0 35.0]
D = Dgc(origins, dests)
```
"""
Dgc(X₁, X₂; unit=:mi) = [dgc(collect(i), collect(j); unit=unit) for i in eachrow(X₁), j in eachrow(X₂)]

# =============================================================================
# Network Manipulation
# =============================================================================

"""
    prune_reindex(dfL::DataFrame, dfN::DataFrame) -> Tuple{DataFrame, DataFrame}

Prune network to common vertices and reindex node IDs sequentially.

Removes any nodes that don't appear in links and any links that reference
non-existent nodes. Then reindexes all node IDs to be sequential starting from 1.

# Arguments
- `dfL`: Links DataFrame with columns [SRC, DST, ...] (first two columns are node IDs).
- `dfN`: Nodes DataFrame with columns [IDX, ...] (first column is node ID).

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
function prune_reindex(dfL::DataFrame, dfN::DataFrame)
    # Find vertices common to both links and nodes
    link_vertices = union(Set(dfL[:, 1]), Set(dfL[:, 2]))
    node_vertices = Set(dfN[:, 1])
    vtx = collect(intersect(link_vertices, node_vertices))
    sort!(vtx)

    # Prune rows in dfL and dfN based on common vertices
    vtx_set = Set(vtx)
    dfL_out = filter(row -> (row[1] in vtx_set) && (row[2] in vtx_set), dfL)
    dfN_out = filter(row -> row[1] in vtx_set, dfN)

    # Create mapping: old ID → new sequential ID
    vtx_map = Dict(v => i for (i, v) in enumerate(vtx))

    # Reindex SRC and DST columns in links
    dfL_out = copy(dfL_out)
    dfL_out[!, 1] = [vtx_map[v] for v in dfL_out[:, 1]]
    dfL_out[!, 2] = [vtx_map[v] for v in dfL_out[:, 2]]

    # Reindex IDX column in nodes
    dfN_out = copy(dfN_out)
    dfN_out[!, 1] = [vtx_map[v] for v in dfN_out[:, 1]]
    sort!(dfN_out, 1)

    return dfL_out, dfN_out
end

"""
    addconnectors(dfL::DataFrame, dfN::DataFrame, x′::Vector, y′::Vector;
                  circuity::Real=1.3) -> Tuple{DataFrame, DataFrame}

Add connector links from demand points to a road network.

Uses Delaunay triangulation to efficiently find nearby network nodes for each
demand point, then creates connector links with estimated distances.

Demand points are assigned node IDs 1:n, and existing network nodes are
shifted by n (i.e., old node 1 becomes n+1).

# Arguments
- `dfL`: Links DataFrame with columns [SRC, DST, DIST, ...].
- `dfN`: Nodes DataFrame with columns [IDX, LON, LAT, ...].
- `x′`: Vector of demand point longitudes.
- `y′`: Vector of demand point latitudes.
- `circuity`: Circuity factor for connector distances (default 1.3).

# Returns
- Tuple of (new_links, new_nodes) DataFrames with connectors added.

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
function addconnectors(dfL::DataFrame, dfN::DataFrame, x′::Vector, y′::Vector;
                       circuity::Real=1.3)
    n = length(x′)
    length(y′) == n || error("x′ and y′ must have the same length")

    # Extract columns from input DataFrames
    b, e, d = copy(dfL[:, 1]), copy(dfL[:, 2]), copy(dfL[:, 3])
    idx, x, y = copy(dfN[:, 1]), copy(dfN[:, 2]), copy(dfN[:, 3])

    # Build Delaunay triangulation for efficient nearest-neighbor search
    tri = DelaunayTriangulation.triangulate(collect(zip(x, y)))

    # Create connector links
    b′, e′, d′ = Int[], Int[], Float64[]
    for i = 1:n
        # Find triangle containing the demand point
        t = DelaunayTriangulation.brute_force_search(tri, (x′[i], y′[i]))
        t = filter(v -> v > 0, t)  # Remove ghost vertices

        # Calculate distances to triangle vertices
        dᵢ = [circuity * dgc((x′[i], y′[i]), (x[j], y[j])) for j in t]

        # Create bidirectional connectors to each vertex
        for (k, j) in enumerate(t)
            push!(b′, i)           # From demand point
            push!(e′, j + n)       # To network node (shifted)
            push!(d′, dᵢ[k])
        end
    end

    # Shift existing node IDs by n
    b .+= n
    e .+= n
    idx .+= n

    # Combine original and connector links
    append!(b, b′)
    append!(e, e′)
    append!(d, d′)

    # Prepend demand points to nodes
    prepend!(idx, 1:n)
    prepend!(x, x′)
    prepend!(y, y′)

    # Build output DataFrames
    col_names_L = names(dfL)
    col_names_N = names(dfN)

    dfL_out = DataFrame(Symbol(col_names_L[1]) => b,
                        Symbol(col_names_L[2]) => e,
                        Symbol(col_names_L[3]) => d)

    dfN_out = DataFrame(Symbol(col_names_N[1]) => idx,
                        Symbol(col_names_N[2]) => x,
                        Symbol(col_names_N[3]) => y)

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

    # Build adjacency: node -> [(neighbor, link_idx), ...]
    function build_adjacency(links)
        adj = Dict{Int, Vector{Tuple{Int, Int}}}()
        for (i, row) in enumerate(eachrow(links))
            src, dst = row[src_col], row[dst_col]
            push!(get!(adj, src, Tuple{Int,Int}[]), (dst, i))
            push!(get!(adj, dst, Tuple{Int,Int}[]), (src, i))
        end
        return adj
    end

    # Merge two links through a degree-2 node
    function merge_links(link1_idx::Int, link2_idx::Int, through_node::Int)
        link1 = links[link1_idx, :]
        link2 = links[link2_idx, :]

        # Determine the two endpoint nodes (not the through_node)
        node_a = link1[src_col] == through_node ? link1[dst_col] : link1[src_col]
        node_b = link2[src_col] == through_node ? link2[dst_col] : link2[src_col]

        # Build merged link
        new_row = Dict{Symbol, Any}()
        for col in names(links)
            sym = Symbol(col)
            if col == src_col
                new_row[sym] = node_a
            elseif col == dst_col
                new_row[sym] = node_b
            elseif col == dist_col
                new_row[sym] = link1[col] + link2[col]
            elseif col == "_orig_idx" && keep_index
                new_row[sym] = vcat(link1[col], link2[col])
            elseif haskey(agg, col)
                new_row[sym] = agg[col]([link1[col], link2[col]])
            else
                new_row[sym] = link1[col]
            end
        end

        return new_row, node_a, node_b
    end

    # Check if must_match attributes are compatible
    function attrs_compatible(link1_idx::Int, link2_idx::Int)
        if isempty(must_match)
            return true
        end
        link1 = links[link1_idx, :]
        link2 = links[link2_idx, :]
        for col in must_match
            if !isequal(link1[col], link2[col])
                return false
            end
        end
        return true
    end

    # Main thinning loop
    changed = true
    iteration = 0
    max_iterations = nrow(links)

    while changed && iteration < max_iterations
        changed = false
        iteration += 1

        adj = build_adjacency(links)

        # Find degree-2 nodes
        deg2_nodes = [node for (node, neighbors) in adj if length(neighbors) == 2]

        # Track which links to remove
        links_to_remove = Set{Int}()
        new_links_to_add = Vector{Dict{Symbol, Any}}()

        for node in deg2_nodes
            neighbors = adj[node]

            # Skip if already processed in this iteration
            if neighbors[1][2] in links_to_remove || neighbors[2][2] in links_to_remove
                continue
            end

            link1_idx, link2_idx = neighbors[1][2], neighbors[2][2]
            neighbor1, neighbor2 = neighbors[1][1], neighbors[2][1]

            # Check must_match compatibility
            if !attrs_compatible(link1_idx, link2_idx)
                continue
            end

            # Check if there's already a direct link between neighbors
            neighbor1_adj = get(adj, neighbor1, Tuple{Int,Int}[])
            existing_link_idx = nothing
            for (n, lidx) in neighbor1_adj
                if n == neighbor2 && lidx != link1_idx && lidx != link2_idx
                    existing_link_idx = lidx
                    break
                end
            end

            # Don't merge if it would create a self-loop
            if neighbor1 == neighbor2
                continue
            end

            # Calculate new merged distance
            new_dist = links[link1_idx, dist_col] + links[link2_idx, dist_col]

            # Decide whether to merge
            should_merge = false
            if isnothing(existing_link_idx)
                should_merge = true
            elseif new_dist < links[existing_link_idx, dist_col]
                push!(links_to_remove, existing_link_idx)
                should_merge = true
            end

            if should_merge
                merged, _, _ = merge_links(link1_idx, link2_idx, node)
                push!(new_links_to_add, merged)
                push!(links_to_remove, link1_idx)
                push!(links_to_remove, link2_idx)
                changed = true
            end
        end

        # Apply changes
        if !isempty(links_to_remove)
            keep_mask = [!(i in links_to_remove) for i in 1:nrow(links)]
            links = links[keep_mask, :]

            for new_link in new_links_to_add
                push!(links, new_link; cols=:union)
            end
        end
    end

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
        println("  Nodes: $(nrow(dfN)) → $(nrow(nodes_out)) " *
                "(-$(nrow(dfN) - nrow(nodes_out)), " *
                "$(round(100*(1 - nrow(nodes_out)/nrow(dfN)), digits=1))%)")
        println("  Links: $(nrow(dfL)) → $(nrow(links)) " *
                "(-$(nrow(dfL) - nrow(links)), " *
                "$(round(100*(1 - nrow(links)/nrow(dfL)), digits=1))%)")
        println("  Total distance: $(round(orig_dist, digits=1)) → " *
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
- `ab_weight`: Optional symbol for A→B weight column (overrides `weight` for forward edges).
- `ba_weight`: Optional symbol for B→A weight column (overrides `weight` for reverse edges).
- `dir_col`: Column symbol indicating directionality (default `:DIR`).
- `oneway_val`: Value in `dir_col` that indicates one-way A→B only (default `1`).

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
- For FAF5 data, `DIR=1` indicates one-way (A→B only), `DIR=0` is bidirectional.
- Edges with zero or negative weights are skipped.
"""
function links2graph(dfL::DataFrame;
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

        # Forward edge (A → B) with AB weight
        val_ab = Float64(w_ab[i])
        if val_ab > 1e-10
            push!(src_vec, u)
            push!(dst_vec, v)
            push!(wgt_vec, val_ab)
        end

        # Reverse edge (B → A) with BA weight, unless one-way
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
- `D`: n×n distance matrix where D[i,j] is the shortest distance from node i to node j.
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
- `D`: n×n distance matrix where D[i,j] is the shortest distance from node i to node j.
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
