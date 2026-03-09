module LogjamMapExt

using Logjam
using CairoMakie
using GeoMakie
using DataFrames

function __init__()
    Logjam._geomakie_available[] = true
    Logjam._makemap_impl[] = _makemap_impl
    Logjam._plotroads_impl[] = _plotroads_impl
    Logjam._plotroute_impl[] = _plotroute_impl
end

# =============================================================================
# makemap implementation
# =============================================================================
function _makemap_impl(x::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}} = nothing,
                       y::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}} = nothing;
                       region::Symbol = :World, backend::Symbol = :CairoMakie,
                       xexpand::Real = 0.3, yexpand::Real = 0.1,
                       doRoadbkgd::Bool = true, maxroadlatspan::Real = 30.0,
                       showgrid::Bool = false)

    # Enforce that x and y must have at least two elements if they are vectors
    if x isa AbstractVector && length(x) < 2
        throw(ArgumentError("x must be vector with at least two elements if not nothing."))
    end
    if y isa AbstractVector && length(y) < 2
        throw(ArgumentError("y must be vector with at least two elements if not nothing."))
    end

    # Activate the appropriate backend for rendering the map
    if backend == :GLMakie
        if Logjam._glmakie_available[]
            Logjam._glmakie_activate[]()  # Use GLMakie for rendering
        else
            error("GLMakie backend requested but GLMakie is not loaded. Add `using GLMakie` first.")
        end
    elseif backend == :CairoMakie
        CairoMakie.activate!()  # Use CairoMakie for rendering
    else
        error("Unknown backend specified, choose :GLMakie or :CairoMakie.")
    end

    # Define a helper function to check if one bounding box (bbox0) is within another (bbox)
    function isinbbox(bbox0, bbox)
        ((xmin0, xmax0), (ymin0, ymax0)) = bbox0
        ((xmin, xmax), (ymin, ymax)) = bbox
        return xmin0 >= xmin && xmax0 <= xmax && ymin0 >= ymin && ymax0 <= ymax
    end

    # Initialize border drawing flags
    doCountryborder, doUSborder = true, false

    # Determine the map limits based on the specified region or coordinates
    if isnothing(x) && isnothing(y)
        # Use predefined limits based on the region
        if region == :World
            limits = Logjam.WORLD_LIMITS
        elseif region == :US
            limits = Logjam.US_LIMITS
            doUSborder = true
        elseif region == :CUS
            limits = Logjam.CUS_LIMITS
            doCountryborder, doUSborder = false, true
        end
    else
        # Calculate map limits based on provided coordinates with optional expansion
        limits, limits0 = Logjam.mapbbox(x, y, xexpand=xexpand, yexpand=yexpand)
        # Check if the region falls within the continental U.S. or broader U.S. limits
        if isinbbox(limits0, Logjam.CUS_LIMITS)
            doCountryborder, doUSborder = false, true
        elseif isinbbox(limits0, Logjam.US_LIMITS)
            doUSborder = true
        end
    end

    # Create a figure and a geographical axis using the Mercator projection
    fig = Figure()
    ax = GeoAxis(fig[1, 1]; dest="+proj=merc", limits=limits, autolimitaspect=nothing,
                 xgridvisible=showgrid, ygridvisible=showgrid,
                 xticklabelsvisible=showgrid, yticklabelsvisible=showgrid,
                 xticksvisible=showgrid, yticksvisible=showgrid)
    if showgrid
        ax.xgridstyle, ax.ygridstyle = :dot, :dot
    end

    hborders = []

    # Add roads as background if specified and within latitude span limits
    if doRoadbkgd
        latspan = abs(limits[2][2] - limits[2][1])
        if latspan <= maxroadlatspan
            road_alpha = latspan > 20 ? 0.35 : (latspan > 10 ? 0.25 : 0.2)
            road_lw = latspan > 20 ? 0.3 : (latspan > 10 ? 0.5 : 0.6)
            push!(hborders, lines!(ax, Logjam.faf5interstateroads()..., color=(:steelblue, road_alpha),
                linewidth=road_lw, label="Interstate Roads"))
        end
    end

    # Add U.S. state borders if specified
    if doUSborder
        push!(hborders, lines!(ax, Logjam.usstates()..., color=:blue, linewidth=.75,
            label="US State Borders"))
        if doCountryborder
            hborders[end].linestyle = :dash
            hborders[end].alpha = 0.5
        end
    end

    # Add country borders if specified
    if doCountryborder
        push!(hborders, lines!(ax, Logjam.countries()..., color=:blue, linewidth=.75,
            label="Country Borders"))
    end

    return fig, ax, hborders, limits
end

# =============================================================================
# plotroads! implementation
# =============================================================================
function _plotroads_impl(ax, dfL::DataFrame, dfN::DataFrame;
                         show_connectors::Bool = false)
    # 1. Input validation
    nrow(dfL) > 0 || throw(ArgumentError("dfL must have at least one row"))
    nrow(dfN) > 0 || throw(ArgumentError("dfN must have at least one row"))
    ncol(dfL) >= 2 || throw(ArgumentError("dfL must have at least 2 columns (SRC, DST)"))
    ncol(dfN) >= 3 || throw(ArgumentError("dfN must have at least 3 columns (IDX, LON, LAT)"))

    # Get column references by position
    src_vals = dfL[:, 1]
    dst_vals = dfL[:, 2]
    node_ids = dfN[:, 1]
    node_lons = dfN[:, 2]
    node_lats = dfN[:, 3]

    # Validate node reference integrity
    node_id_set = Set(node_ids)
    orphaned_src = findall(src -> src ∉ node_id_set, src_vals)
    !isempty(orphaned_src) && throw(ArgumentError(
        "dfL has $(length(orphaned_src)) links with SRC not in dfN.IDX (first: row $(orphaned_src[1]))"))

    orphaned_dst = findall(dst -> dst ∉ node_id_set, dst_vals)
    !isempty(orphaned_dst) && throw(ArgumentError(
        "dfL has $(length(orphaned_dst)) links with DST not in dfN.IDX (first: row $(orphaned_dst[1]))"))

    # Validate coordinate bounds
    bad_lon = findall(lon -> lon < -180 || lon > 180, node_lons)
    !isempty(bad_lon) && throw(ArgumentError(
        "dfN has $(length(bad_lon)) nodes with LON out of bounds [-180,180] (first: row $(bad_lon[1]))"))

    bad_lat = findall(lat -> lat < -90 || lat > 90, node_lats)
    !isempty(bad_lat) && throw(ArgumentError(
        "dfN has $(length(bad_lat)) nodes with LAT out of bounds [-90,90] (first: row $(bad_lat[1]))"))

    # 2. Build node lookup dictionary
    node_lookup = Dict(node_ids[i] => (node_lons[i], node_lats[i]) for i in 1:nrow(dfN))

    # 3. Add SOURCE column if missing (backward compatibility)
    has_source = "SOURCE" in names(dfL)
    source_col = has_source ? dfL.SOURCE : fill(missing, nrow(dfL))

    # 4. Filter connectors if hidden
    dfL_active = dfL
    if !show_connectors
        keep_mask = [coalesce(s, "FAF5") != "CONNECTOR" for s in source_col]
        dfL_active = dfL[keep_mask, :]
        source_col = has_source ? dfL_active.SOURCE : fill(missing, nrow(dfL_active))
    end

    # 5. FCLASS-based categorization
    has_fclass = "FCLASS" in names(dfL_active)
    fclass_col = has_fclass ? dfL_active.FCLASS : fill(missing, nrow(dfL_active))

    tier_colors = Dict(
        1 => (fill=(0.60, 0.70, 0.82), casing=(0.35, 0.42, 0.52)),
        2 => (fill=(0.72, 0.82, 0.72), casing=(0.45, 0.55, 0.40)),
        3 => (fill=(0.90, 0.82, 0.70), casing=(0.65, 0.52, 0.30)),
        4 => (fill=(0.92, 0.90, 0.80), casing=(0.60, 0.58, 0.48)),
        5 => (fill=(0.95, 0.95, 0.95), casing=(0.65, 0.65, 0.65)),
    )

    tier_widths = Dict(
        1 => (close=1.8,  mid=1.2, far=0.4),
        2 => (close=2.0,  mid=1.0, far=0.3),
        3 => (close=1.6,  mid=0.7, far=0.2),
        4 => (close=1.2,  mid=0.5, far=0.15),
        5 => (close=0.8,  mid=0.3, far=0.1),
    )

    tier_alphas = Dict(
        1 => (close=0.8, mid=0.5, far=0.3),
        2 => (close=0.7, mid=0.4, far=0.25),
        3 => (close=0.6, mid=0.35, far=0.2),
        4 => (close=0.5, mid=0.3, far=0.15),
        5 => (close=0.4, mid=0.25, far=0.1),
    )

    # 6. Categorize links into FCLASS tiers and build polylines
    tiers = [1, 2, 3, 4, 5]
    polylines = Dict(t => (Float64[], Float64[]) for t in tiers)
    connector_polylines = (Float64[], Float64[])

    src_active = dfL_active[:, 1]
    dst_active = dfL_active[:, 2]

    for i in 1:nrow(dfL_active)
        source = coalesce(source_col[i], "FAF5")

        if source == "CONNECTOR"
            src_lon, src_lat = node_lookup[src_active[i]]
            dst_lon, dst_lat = node_lookup[dst_active[i]]
            push!(connector_polylines[1], src_lon, dst_lon, NaN)
            push!(connector_polylines[2], src_lat, dst_lat, NaN)
            continue
        end

        fc = has_fclass && !ismissing(fclass_col[i]) ? fclass_col[i] : 5
        tier = fc <= 0 ? 5 : (fc >= 5 ? 5 : fc)

        src_lon, src_lat = node_lookup[src_active[i]]
        dst_lon, dst_lat = node_lookup[dst_active[i]]

        push!(polylines[tier][1], src_lon, dst_lon, NaN)
        push!(polylines[tier][2], src_lat, dst_lat, NaN)
    end

    # 7. Compute adaptive styling and render
    limits = ax.limits[]
    latspan = abs(limits[2][2] - limits[2][1])
    handles = Dict{Symbol, Any}()

    if latspan <= 10
        for tier in reverse(tiers)
            x_coords, y_coords = polylines[tier]
            length(x_coords) > 0 || continue
            w = tier_widths[tier]
            α = tier_alphas[tier]
            r, g, b = tier_colors[tier].casing
            h = lines!(ax, x_coords, y_coords;
                       linewidth=w.close + 1.2,
                       color=RGBf(r, g, b), alpha=α.close, linecap=:round)
            handles[Symbol("casing_", tier)] = h
        end
        for tier in reverse(tiers)
            x_coords, y_coords = polylines[tier]
            length(x_coords) > 0 || continue
            w = tier_widths[tier]
            α = tier_alphas[tier]
            r, g, b = tier_colors[tier].fill
            h = lines!(ax, x_coords, y_coords;
                       linewidth=w.close,
                       color=RGBf(r, g, b), alpha=α.close, linecap=:round)
            handles[Symbol("fill_", tier)] = h
        end
    elseif latspan <= 20
        for tier in reverse(tiers)
            x_coords, y_coords = polylines[tier]
            length(x_coords) > 0 || continue
            w = tier_widths[tier]
            α = tier_alphas[tier]
            r, g, b = tier_colors[tier].fill
            h = lines!(ax, x_coords, y_coords;
                       linewidth=w.mid,
                       color=RGBf(r, g, b), alpha=α.mid, linecap=:round)
            handles[Symbol("fill_", tier)] = h
        end
    else
        for tier in reverse(tiers)
            x_coords, y_coords = polylines[tier]
            length(x_coords) > 0 || continue
            w = tier_widths[tier]
            α = tier_alphas[tier]
            r, g, b = tier_colors[tier].fill
            h = lines!(ax, x_coords, y_coords;
                       linewidth=w.far,
                       color=RGBf(r, g, b), alpha=α.far, linecap=:round)
            handles[Symbol("fill_", tier)] = h
        end
    end

    if length(connector_polylines[1]) > 0
        h = lines!(ax, connector_polylines[1], connector_polylines[2];
                   linewidth=0.3, color=(:gray55, 0.15), linestyle=:dash, linecap=:round)
        handles[:connector] = h
    end

    return handles
end

# =============================================================================
# plotroute! implementations (multiple dispatch via single Ref)
# =============================================================================

# Base rendering: coordinate vectors
function _plotroute_impl(ax, lx::AbstractVector{<:Real}, ly::AbstractVector{<:Real};
                         color=:red, linewidth=2,
                         show_markers=true,
                         origin_color=:green, dest_color=:blue,
                         markersize=10)
    handles = Any[]
    push!(handles, lines!(ax, lx, ly; color=color, linewidth=linewidth))
    if show_markers
        valid = findall(!isnan, lx)
        if !isempty(valid)
            push!(handles, scatter!(ax, [lx[valid[1]]], [ly[valid[1]]];
                                    color=origin_color, markersize=markersize))
            push!(handles, scatter!(ax, [lx[valid[end]]], [ly[valid[end]]];
                                    color=dest_color, markersize=markersize))
        end
    end
    return handles
end

# Single path by node indices
function _plotroute_impl(ax, path::Vector{Int}, dfN::DataFrame;
                         color=:red, linewidth=2,
                         show_markers=true,
                         origin_color=:green, dest_color=:blue,
                         markersize=10)
    _plotroute_impl(ax, dfN.LON[path], dfN.LAT[path];
                    color=color, linewidth=linewidth,
                    show_markers=show_markers,
                    origin_color=origin_color, dest_color=dest_color,
                    markersize=markersize)
end

# Multi-path
function _plotroute_impl(ax, paths::Vector{Vector{Int}}, dfN::DataFrame;
                         colors=Makie.wong_colors(), linewidth=2,
                         show_markers=true, markersize=10)
    all_handles = Vector{Any}[]
    for (i, path) in enumerate(paths)
        c = colors[mod1(i, length(colors))]
        h = _plotroute_impl(ax, path, dfN;
                            color=c, linewidth=linewidth,
                            show_markers=show_markers,
                            origin_color=:green, dest_color=:blue,
                            markersize=markersize)
        push!(all_handles, h)
    end
    return all_handles
end

# High-level: route + shipments + parents
function _plotroute_impl(ax, route::AbstractVector{Int}, shipments::DataFrame,
                         parents::Vector{Vector{Int}}, dfN::DataFrame;
                         tr=(b=Int[], e=Int[]),
                         color=:red, linewidth=2,
                         show_markers=true,
                         origin_color=:green, dest_color=:blue,
                         markersize=10)
    loc_seq = Logjam.rte2loc(route, shipments, tr)
    lx, ly = Logjam.rte2lines(loc_seq, parents, dfN)
    _plotroute_impl(ax, lx, ly;
                    color=color, linewidth=linewidth,
                    show_markers=show_markers,
                    origin_color=origin_color, dest_color=dest_color,
                    markersize=markersize)
end

# Multi-route: routes + shipments + parents
function _plotroute_impl(ax, routes::Vector{<:AbstractVector{Int}}, shipments::DataFrame,
                         parents::Vector{Vector{Int}}, dfN::DataFrame;
                         tr=(b=Int[], e=Int[]),
                         colors=Makie.wong_colors(),
                         linewidth=2, show_markers=true, markersize=10)
    all_handles = Vector{Any}[]
    for (i, route) in enumerate(routes)
        c = colors[mod1(i, length(colors))]
        h = _plotroute_impl(ax, route, shipments, parents, dfN;
                            tr=tr, color=c, linewidth=linewidth,
                            show_markers=show_markers,
                            origin_color=:green, dest_color=:blue,
                            markersize=markersize)
        push!(all_handles, h)
    end
    return all_handles
end

end # module LogjamMapExt
