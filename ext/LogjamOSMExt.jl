module LogjamOSMExt

using Logjam
using LightOSM
using NearestNeighbors
using DataFrames
using CSV
using Graphs
using Statistics: mean

function __init__()
    Logjam._osm_available[] = true
    Logjam._osm_download[] = _osm_roads_impl
    Logjam._osm_stitch[] = _stitchnetworks_impl
end

# =============================================================================
# osm_roads implementation
# =============================================================================
function _osm_roads_impl(bbox::Tuple{Real,Real,Real,Real};
                         cache_dir::String=".", force_download::Bool=false)
    xmin, xmax, ymin, ymax = bbox

    # --- Bounding box size warning ---
    area_deg2 = (xmax - xmin) * (ymax - ymin)
    if area_deg2 > Logjam._OSM_AREA_WARN_DEG2
        area_mi2 = round(area_deg2 * 4800; digits=0)  # rough deg²→mi² at mid-latitudes
        @warn "Large bounding box (~$(area_mi2) sq mi). Overpass query may be slow or fail. " *
              "Consider reducing the region size."
    end

    # --- Check cache ---
    nodes_path, links_path = Logjam._osm_cache_path(bbox, cache_dir)
    if !force_download && isfile(nodes_path) && isfile(links_path)
        @info "Loading cached OSM data: $nodes_path"
        dfN = CSV.read(nodes_path, DataFrame)
        dfL = CSV.read(links_path, DataFrame)
        return dfN, dfL
    end

    # --- Download from Overpass ---
    @info "Downloading OSM roads for bbox: ($xmin, $xmax, $ymin, $ymax)"
    local g
    try
        g = LightOSM.graph_from_download(
            :bbox;
            minlat=ymin, maxlat=ymax, minlon=xmin, maxlon=xmax,
            network_type=:drive,
            weight_type=:distance,
            graph_type=:light,
            largest_connected_component=true,
        )
    catch e
        error("Overpass query failed for bbox ($xmin, $xmax, $ymin, $ymax). " *
              "Check internet connection or try a smaller region. Original error: $e")
    end

    @info "  OSM nodes: $(length(g.nodes)), edges: $(Graphs.ne(g.graph))"

    # --- Translate to DataFrames ---
    dfN, dfL = _osm2dataframes(g)

    # --- Save cache ---
    mkpath(cache_dir)
    CSV.write(nodes_path, dfN)
    CSV.write(links_path, dfL)
    @info "  Cached: $nodes_path, $links_path"

    return dfN, dfL
end

# =============================================================================
# OSMGraph → Logjam DataFrames translation
# =============================================================================
function _osm2dataframes(g)
    # --- Nodes DataFrame ---
    n = length(g.index_to_node)
    idx = Vector{Int}(undef, n)
    lon = Vector{Float64}(undef, n)
    lat = Vector{Float64}(undef, n)

    for (vertex_idx, node_id) in g.index_to_node
        loc = g.nodes[node_id].location
        idx[vertex_idx] = vertex_idx
        lon[vertex_idx] = loc.lon    # Logjam convention: (LON, LAT)
        lat[vertex_idx] = loc.lat
    end
    dfN = DataFrame(IDX=idx, LON=lon, LAT=lat, SOURCE=fill("OSM", n))

    # --- Links DataFrame ---
    edges_list = collect(Graphs.edges(g.graph))
    m = length(edges_list)

    src_vec    = Vector{Int}(undef, m)
    dst_vec    = Vector{Int}(undef, m)
    dist_vec   = Vector{Float64}(undef, m)
    speed_vec  = Vector{Int}(undef, m)
    fclass_vec = Vector{Int}(undef, m)
    dir_vec    = fill(1, m)
    name_vec   = Vector{String}(undef, m)

    km_to_mi = 0.621371

    for (i, e) in enumerate(edges_list)
        u, v = Graphs.src(e), Graphs.dst(e)
        src_vec[i] = u
        dst_vec[i] = v

        # Distance from LightOSM weight matrix (km → miles)
        dist_vec[i] = g.weights[u, v] * km_to_mi

        # Look up way for highway class
        node_u = g.index_to_node[u]
        node_v = g.index_to_node[v]
        hw_class = "road"
        road_name = ""
        if haskey(g.edge_to_way, [node_u, node_v])
            way_id = g.edge_to_way[[node_u, node_v]]
            tags = g.ways[way_id].tags
            hw_class = get(tags, "highway", "road")
            road_name = get(tags, "name", "")
        end

        speed_vec[i] = get(Logjam.OSM_SPEED_DEFAULTS, hw_class, 25)
        fclass_vec[i] = get(Logjam.OSM_FCLASS, hw_class, 7)
        name_vec[i] = road_name
    end

    dfL = DataFrame(
        SRC=src_vec, DST=dst_vec, DIST=dist_vec,
        SPEED=speed_vec, FCLASS=fclass_vec, DIR=dir_vec,
        NAME=name_vec, SOURCE=fill("OSM", m),
    )

    @info "  Nodes DataFrame: $(nrow(dfN)) rows, Links DataFrame: $(nrow(dfL)) rows"
    return dfN, dfL
end

# =============================================================================
# stitchnetworks implementation
# =============================================================================
function _stitchnetworks_impl(dfN_base::DataFrame, dfL_base::DataFrame,
                              dfN_osm::DataFrame, dfL_osm::DataFrame;
                              tolerance_m::Real=500, fclass_max::Int=3)

    # --- 1. Identify eligible base-network nodes ---
    has_fclass = "FCLASS" in names(dfL_base)
    if has_fclass
        eligible_links = filter(row -> row.FCLASS <= fclass_max, dfL_base)
    else
        eligible_links = dfL_base
    end
    if nrow(eligible_links) == 0
        @warn "No base-network links with FCLASS ≤ $fclass_max found."
        eligible_node_ids = Set(dfN_base.IDX)
    else
        eligible_node_ids = Set{Int}()
        for row in eachrow(eligible_links)
            push!(eligible_node_ids, row.SRC)
            push!(eligible_node_ids, row.DST)
        end
    end

    eligible_nodes = filter(row -> row.IDX in eligible_node_ids, dfN_base)
    if nrow(eligible_nodes) == 0
        @warn "No eligible base-network nodes found for stitching."
        dfN_combined = vcat(dfN_base, dfN_osm; cols=:union)
        dfL_combined = vcat(dfL_base, dfL_osm; cols=:union)
        return Logjam.prune_reindex(dfL_combined, dfN_combined)
    end

    # --- 2. Identify candidate OSM nodes (near boundary) ---
    osm_lons = dfN_osm.LON
    osm_lats = dfN_osm.LAT
    lon_range = maximum(osm_lons) - minimum(osm_lons)
    lat_range = maximum(osm_lats) - minimum(osm_lats)
    margin_lon = 0.1 * lon_range
    margin_lat = 0.1 * lat_range

    lon_min, lon_max = minimum(osm_lons), maximum(osm_lons)
    lat_min, lat_max = minimum(osm_lats), maximum(osm_lats)

    candidate_mask = (osm_lons .<= lon_min + margin_lon) .|
                     (osm_lons .>= lon_max - margin_lon) .|
                     (osm_lats .<= lat_min + margin_lat) .|
                     (osm_lats .>= lat_max - margin_lat)

    candidate_nodes = dfN_osm[candidate_mask, :]
    if nrow(candidate_nodes) == 0
        candidate_nodes = dfN_osm  # fallback: use all OSM nodes
    end

    # --- 3. Build KDTree over eligible base nodes ---
    # Convert lon/lat to approximate meters for distance comparison
    # Using a local flat-earth approximation centered on the region
    center_lat = mean(eligible_nodes.LAT)
    m_per_deg_lat = 111_320.0
    m_per_deg_lon = 111_320.0 * cosd(center_lat)

    base_coords = hcat(
        eligible_nodes.LON .* m_per_deg_lon,
        eligible_nodes.LAT .* m_per_deg_lat
    )'  # 2×N matrix

    tree = KDTree(base_coords)

    # --- 4. Find connections ---
    connector_rows = Dict{Symbol, Vector}(
        :SRC => Int[], :DST => Int[], :DIST => Float64[],
        :SPEED => Int[], :FCLASS => Int[], :DIR => Int[],
        :NAME => String[], :SOURCE => String[],
    )

    # Build a lookup: base node IDX → speed of best (lowest FCLASS) connected link
    has_speed_base = "SPEED" in names(eligible_links)
    has_dir_base = "DIR" in names(eligible_links)
    has_speed_osm = "SPEED" in names(dfL_osm)

    base_node_speed = Dict{Int, Int}()
    base_node_dir = Dict{Int, Int}()
    for row in eachrow(eligible_links)
        for nid in (row.SRC, row.DST)
            cur_fclass = has_fclass ? row.FCLASS : 99
            if !haskey(base_node_speed, nid) || cur_fclass < get(base_node_speed, nid, 99)
                base_node_speed[nid] = has_speed_base ? row.SPEED : 45
                base_node_dir[nid] = has_dir_base ? row.DIR : 0
            end
        end
    end

    osm_node_speed = Dict{Int, Int}()
    for row in eachrow(dfL_osm)
        for nid in (row.SRC, row.DST)
            if !haskey(osm_node_speed, nid)
                osm_node_speed[nid] = has_speed_osm ? row.SPEED : 25
            end
        end
    end

    # Max node ID offset for combining networks
    max_base_id = maximum(dfN_base.IDX)
    connected_base_nodes = Set{Int}()

    for cand_row in eachrow(candidate_nodes)
        cand_m = [cand_row.LON * m_per_deg_lon, cand_row.LAT * m_per_deg_lat]
        idxs = inrange(tree, cand_m, Float64(tolerance_m))

        if !isempty(idxs)
            # Take the nearest eligible node
            dists_m = [sqrt(sum((base_coords[:, j] .- cand_m).^2)) for j in idxs]
            best_j = idxs[argmin(dists_m)]
            base_node = eligible_nodes[best_j, :]

            # Skip if already connected to this base node
            if base_node.IDX in connected_base_nodes
                continue
            end

            # Grade separation: check if OSM node has layer != 0
            # (This is handled at download time by LightOSM filtering for :drive)
            # For FAF5 connections, grade separation is implicit in FCLASS filtering

            # Compute great-circle distance
            dist_mi = Logjam.dgc(
                (cand_row.LON, cand_row.LAT),
                (base_node.LON, base_node.LAT)
            )

            # Speed: lower of the two connected roads
            spd_base = get(base_node_speed, base_node.IDX, 45)
            spd_osm = get(osm_node_speed, cand_row.IDX, 25)
            conn_speed = min(spd_base, spd_osm)

            # Directionality: check base link direction
            dir_base = get(base_node_dir, base_node.IDX, 0)

            # Create connector edge(s)
            # OSM node ID needs offset to avoid collision with base network
            osm_id_offset = cand_row.IDX + max_base_id

            if dir_base == 1
                # Unidirectional: create one connector in each direction
                push!(connector_rows[:SRC], osm_id_offset)
                push!(connector_rows[:DST], base_node.IDX)
                push!(connector_rows[:DIST], dist_mi)
                push!(connector_rows[:SPEED], conn_speed)
                push!(connector_rows[:FCLASS], 99)
                push!(connector_rows[:DIR], 1)
                push!(connector_rows[:NAME], "")
                push!(connector_rows[:SOURCE], "CONNECTOR")

                push!(connector_rows[:SRC], base_node.IDX)
                push!(connector_rows[:DST], osm_id_offset)
                push!(connector_rows[:DIST], dist_mi)
                push!(connector_rows[:SPEED], conn_speed)
                push!(connector_rows[:FCLASS], 99)
                push!(connector_rows[:DIR], 1)
                push!(connector_rows[:NAME], "")
                push!(connector_rows[:SOURCE], "CONNECTOR")
            else
                # Bidirectional: single undirected connector
                push!(connector_rows[:SRC], osm_id_offset)
                push!(connector_rows[:DST], base_node.IDX)
                push!(connector_rows[:DIST], dist_mi)
                push!(connector_rows[:SPEED], conn_speed)
                push!(connector_rows[:FCLASS], 99)
                push!(connector_rows[:DIR], 0)
                push!(connector_rows[:NAME], "")
                push!(connector_rows[:SOURCE], "CONNECTOR")
            end

            push!(connected_base_nodes, base_node.IDX)
        end
    end

    n_connectors = length(connector_rows[:SRC])
    @info "  Created $n_connectors connector edges"

    # --- 5. Offset OSM node IDs and link references ---
    dfN_osm_offset = copy(dfN_osm)
    dfN_osm_offset.IDX .= dfN_osm_offset.IDX .+ max_base_id

    dfL_osm_offset = copy(dfL_osm)
    dfL_osm_offset.SRC .= dfL_osm_offset.SRC .+ max_base_id
    dfL_osm_offset.DST .= dfL_osm_offset.DST .+ max_base_id

    # --- 6. Combine DataFrames ---
    dfL_conn = DataFrame(connector_rows)
    dfN_combined = vcat(dfN_base, dfN_osm_offset; cols=:union)
    dfL_combined = vcat(dfL_base, dfL_osm_offset, dfL_conn; cols=:union)

    # prune_reindex for clean sequential IDs
    dfL_out, dfN_out = Logjam.prune_reindex(dfL_combined, dfN_combined)

    # --- 7. Topology validation ---
    if n_connectors == 0
        @warn "No connector edges created. Networks are disjoint. " *
              "Try increasing tolerance_m or fclass_max."
    else
        @info "  Combined network: $(nrow(dfN_out)) nodes, $(nrow(dfL_out)) links"
    end

    return dfN_out, dfL_out
end

end # module LogjamOSMExt
