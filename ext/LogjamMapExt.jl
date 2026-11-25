module LogjamMapExt

# The map functions, loaded by GeoMakie alone (C5). Written against Makie through GeoMakie, which reexports it: no
# backend is loaded here, so the figures this draws are drawn by whichever of CairoMakie or GLMakie the caller loaded
# (the course loads CairoMakie, and a figure is created without one). Logjam declares each function and keeps its
# docstring (src/maptools.jl, src/Logjam.jl); this adds the methods.

using Logjam
using GeoMakie
using GeoMakie: Makie
using DataFrames
import Logjam: makemap, plotroads!, plotroute!, dcf

# =============================================================================
# dcf: display the current figure
# =============================================================================
function dcf()
    display(Makie.current_figure())
    return nothing
end

# =============================================================================
# One zoom rule for the road layers of makemap and plotroads!: the map's latitude span, in degrees
# =============================================================================
_zoom(latspan) = latspan <= 10 ? :close : latspan <= 20 ? :mid : :far

# makemap's Interstate layer is drawn up to this span, and by zoom with this opacity and width
const _INTERSTATE_MAXLATSPAN = 30.0
const _INTERSTATE_STYLE = (close = (alpha = 0.2, linewidth = 0.6), mid = (alpha = 0.25, linewidth = 0.5),
                           far = (alpha = 0.35, linewidth = 0.3))

# =============================================================================
# The road network on a small map (S22, S23): a map 150 miles across or less draws the FAF5 network, cropped to the map
# =============================================================================

# the FCLASS tier (1 to 5) of a link: the Interstate is 1, a class of 5 or more, or of 0, is 5
_fclasstier(fc) = fc <= 0 ? 5 : (fc >= 5 ? 5 : fc)

# S23: one hue, as Lecture 2.5 draws it by hand ("Same hue as makemap's own roads, so the two layers look alike"), and
# every stroke below alpha 0.35, the course figure gate's muted base (`FAINT_ALPHA`, figure_labels.jl); 2.5's own
# network is 0.45, over it, so that number is not copied. The classes differ by width, the Interstate the heaviest.
# There is no casing: a second, wider stroke of the same hue under each class would be a second stroke to keep below 0.35.
const _NETWORK_HUE = :steelblue
const _NETWORK_ALPHA = 0.3
const _NETWORK_WIDTHS = (1.4, 1.0, 0.7, 0.5, 0.3)         # class 1 (Interstate) to class 5 (local, and any class 5 or more)
const _NETWORK_LAYERS = (:class1, :class2, :class3, :class4, :class5)

# does the segment from (x1, y1) to (x2, y2) meet the closed box [xmin, xmax] x [ymin, ymax]? (Liang and Barsky's clip)
function _meetsbox(x1, y1, x2, y2, xmin, xmax, ymin, ymax)
    dx, dy = x2 - x1, y2 - y1
    t0, t1 = 0.0, 1.0
    for (p, q) in ((-dx, x1 - xmin), (dx, xmax - x1), (-dy, y1 - ymin), (dy, ymax - y1))
        if p == 0
            q < 0 && return false
        else
            t = q / p
            if p < 0
                t > t1 && return false
                t > t0 && (t0 = t)
            else
                t < t0 && return false
                t < t1 && (t1 = t)
            end
        end
    end
    return true
end

# The ramps of an interchange are not drawn (his ruling of 2026-11-21, on S22's pictures): at this scale they pile up
# into blotches. FAF5 tells them only by name, as Lecture 4.1's make_faf5_interstate.jl reads them: a ramp, a
# collector-distributor lane or a turn lane. "CONNECTOR" alone also names real roads ("AIRPORT CONNECTOR"), so only the
# connector-distributor lane is read; a missing name is not a ramp. 137,156 of FAF5's 483,530 links.
const _RAMP_NAME = r"\bRAMPS?\b|(COLLECTOR|CONNECTOR)\s*/\s*DISTRIBUTOR|\bC/D LANE\b|\bTURN LANE\b"
_isramp(name) = !ismissing(name) && occursin(_RAMP_NAME, uppercase(string(name)))

# The end points and class of each FAF5 link, in the order of `faf5links()`, read from the cached tables on the first
# map that needs them and kept (about 16 MB), so that a crop is a pass over four plain vectors and not a lookup of every
# link's two nodes in the node table on each call (a crop that did that took 0.14 to 0.17 s; this one 0.5 to 0.8 ms).
# The FAF5 tables have no `SOURCE` column and no connector; `plotroads!` hides a connector if a table has one.
const _LINKENDS = Ref{Any}(nothing)

function _linkends()
    isnothing(_LINKENDS[]) || return _LINKENDS[]
    N, L = Logjam._faf5tables()
    lon = fill(NaN, maximum(N.IDX))
    lat = fill(NaN, maximum(N.IDX))
    lon[N.IDX] = N.LON
    lat[N.IDX] = N.LAT
    x1, y1, x2, y2 = lon[L.SRC], lat[L.SRC], lon[L.DST], lat[L.DST]
    tier = Int8.(_fclasstier.(L.FCLASS))
    tier[.!isfinite.(x1 .+ y1 .+ x2 .+ y2)] .= 0              # a link to a node the table lacks (none: plotroads! refuses one)
    tier[_isramp.(L.NAME)] .= 0                                # a ramp (above); tier 0 is never drawn
    _LINKENDS[] = (; x1, y1, x2, y2, tier)
    return _LINKENDS[]
end

# The FAF5 links whose segment meets the box (so the roads run to the frame's edge), as NaN-separated polylines for each
# class 1 to 5.
_networkcrop(limits) = (e = _linkends(); _cropends(e.x1, e.y1, e.x2, e.y2, e.tier, limits))

# (a function of its own so that the loop is compiled for the vectors' types, which the Ref that holds them does not say)
function _cropends(x1::Vector{Float64}, y1::Vector{Float64}, x2::Vector{Float64}, y2::Vector{Float64}, tier::Vector{Int8}, limits)
    (xmin, xmax), (ymin, ymax) = limits
    polylines = [(Float64[], Float64[]) for _ in 1:5]
    for i in eachindex(x1)
        tier[i] == 0 && continue
        (max(x1[i], x2[i]) < xmin || min(x1[i], x2[i]) > xmax || max(y1[i], y2[i]) < ymin || min(y1[i], y2[i]) > ymax) && continue
        _meetsbox(x1[i], y1[i], x2[i], y2[i], xmin, xmax, ymin, ymax) || continue
        k = tier[i]
        push!(polylines[k][1], x1[i], x2[i], NaN)
        push!(polylines[k][2], y1[i], y2[i], NaN)
    end
    return polylines
end

# The network as five plots, lightest class first so the Interstate is on top; `over` is `roads`' NamedTuple, if any:
# `color` replaces the hue, `alpha` the opacity of every class, and `linewidth` the Interstate's width, the other
# classes keeping their ratios to it. The heaviest class drawn carries the label. Returns `(; class1, ..., class5)`,
# `nothing` for a class with no link in the box.
function _networkroads!(ax, limits, over)
    hue, alpha = get(over, :color, _NETWORK_HUE), get(over, :alpha, _NETWORK_ALPHA)
    scale = get(over, :linewidth, _NETWORK_WIDTHS[1]) / _NETWORK_WIDTHS[1]
    polylines = _networkcrop(limits)
    heaviest = findfirst(k -> !isempty(polylines[k][1]), 1:5)
    handles = Any[nothing, nothing, nothing, nothing, nothing]
    for k in 5:-1:1
        x, y = polylines[k]
        isempty(x) && continue
        handles[k] = k == heaviest ?
            lines!(ax, x, y; color = (hue, alpha), linewidth = scale * _NETWORK_WIDTHS[k], label = "FAF5 Roads") :
            lines!(ax, x, y; color = (hue, alpha), linewidth = scale * _NETWORK_WIDTHS[k])
    end
    return NamedTuple{_NETWORK_LAYERS}(Tuple(handles))
end

# =============================================================================
# makemap: the figure's own position, or a cell of a figure that exists (`fig[1, 2]`, `fig[2, 1:2]`). The cell is a
# `Makie.GridPosition`; a `GridSubposition` (`fig[1, 1][1, 2]`, a cell of a nested layout) is not accepted, since no
# lecture draws a map in one (principle 8), as K11b's check refused it too.
# =============================================================================
const _MapPoints = Logjam._MapPoints
const _MapBox = Logjam._MapBox

function _makemap(target, x, y; region, xexpand, yexpand, roads, borders, size, showgrid, doRoadbkgd)
    roads = Logjam._maproads(roads, doRoadbkgd)
    borders = Logjam._mapborders(borders)
    size = Logjam._mapsize(size, target)
    return _drawmap(target, x, y; region, xexpand, yexpand, roads, borders, size, showgrid)
end

# A region, or the box around points. The no-argument method is written out, not made by default arguments, so that
# the first method of `makemap` lists its keywords (`Base.kwarg_decl(first(methods(makemap)))`, which the course's
# `logjam_kwargs` reads).
function makemap(; region::Symbol = :World, xexpand::Real = 0.3, yexpand::Real = 0.1, roads = nothing, borders = true,
                 size = (600, 450), showgrid::Bool = false, doRoadbkgd = nothing)
    return _makemap(nothing, nothing, nothing; region, xexpand, yexpand, roads, borders, size, showgrid, doRoadbkgd)
end

function makemap(x::_MapPoints, y::_MapPoints = nothing;
                 region::Symbol = :World, xexpand::Real = 0.3, yexpand::Real = 0.1, roads = nothing, borders = true,
                 size = (600, 450), showgrid::Bool = false, doRoadbkgd = nothing)
    return _makemap(nothing, x, y; region, xexpand, yexpand, roads, borders, size, showgrid, doRoadbkgd)
end

function makemap(bb::_MapBox; region::Symbol = :World, roads = nothing, borders = true, size = (600, 450),
                 showgrid::Bool = false, doRoadbkgd = nothing, xexpand = nothing, yexpand = nothing)
    Logjam._nobboxexpand("makemap(bb)", xexpand, yexpand)
    return _makemap(nothing, bb[1], bb[2]; region, xexpand = 0, yexpand = 0, roads, borders, size, showgrid, doRoadbkgd)
end

function makemap(cell::Makie.GridPosition, x::_MapPoints, y::_MapPoints;
                 region::Symbol = :World, xexpand::Real = 0.3, yexpand::Real = 0.1, roads = nothing, borders = true,
                 size = nothing, showgrid::Bool = false, doRoadbkgd = nothing)
    return _makemap(cell, x, y; region, xexpand, yexpand, roads, borders, size, showgrid, doRoadbkgd)
end

function makemap(cell::Makie.GridPosition, bb::_MapBox; region::Symbol = :World, roads = nothing, borders = true,
                 size = nothing, showgrid::Bool = false, doRoadbkgd = nothing, xexpand = nothing, yexpand = nothing)
    Logjam._nobboxexpand("makemap(cell, bb)", xexpand, yexpand)
    return _makemap(cell, bb[1], bb[2]; region, xexpand = 0, yexpand = 0, roads, borders, size, showgrid, doRoadbkgd)
end

function makemap(cell::Makie.GridPosition; region::Symbol = :World, roads = nothing, borders = true, size = nothing,
                 showgrid::Bool = false, doRoadbkgd = nothing)
    return _makemap(cell, nothing, nothing; region, xexpand = 0.3, yexpand = 0.1, roads, borders, size, showgrid, doRoadbkgd)
end

# `target` is nothing (a figure is created, at `size`) or the cell to draw in
function _drawmap(target, x::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}},
                  y::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}};
                  region::Symbol, xexpand::Real, yexpand::Real, roads, borders, size, showgrid::Bool)

    # Enforce that x and y must have at least two elements if they are vectors
    if x isa AbstractVector && length(x) < 2
        throw(ArgumentError("x must be vector with at least two elements if not nothing."))
    end
    if y isa AbstractVector && length(y) < 2
        throw(ArgumentError("y must be vector with at least two elements if not nothing."))
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
        else
            error("Unknown region :$region. Use :World, :US, or :CUS")
        end
    else
        # Calculate map limits based on provided coordinates with optional expansion
        limits = Logjam.mapbbox(x, y; xexpand=xexpand, yexpand=yexpand)
        # Raw (unexpanded) extent for the region-containment check; reuses mapbbox's
        # validation + NaN handling so the all-NaN ArgumentError guard is preserved.
        limits0 = Logjam.mapbbox(x, y)
        # Check if the region falls within the continental U.S. or broader U.S. limits
        if isinbbox(limits0, Logjam.CUS_LIMITS)
            doCountryborder, doUSborder = false, true
        elseif isinbbox(limits0, Logjam.US_LIMITS)
            doUSborder = true
        end
    end

    # The figure (Makie's own default size, 600 by 450, unless given) and a geographical axis in its cell, in Mercator
    if target === nothing
        fig = Figure(size = (size[1], size[2] === :auto ? 450 : size[2]))
        cell = fig[1, 1]
    else
        fig = Makie.get_figure(target)
        cell = target
    end
    ax = GeoAxis(cell; dest="+proj=merc", limits=limits, autolimitaspect=nothing,
                 xgridvisible=showgrid, ygridvisible=showgrid,
                 xticklabelsvisible=showgrid, yticklabelsvisible=showgrid,
                 xticksvisible=showgrid, yticksvisible=showgrid)
    if showgrid
        ax.xgridstyle, ax.ygridstyle = :dot, :dot
    end

    # The road layer, if wanted; a NamedTuple overrides attributes. A map 150 miles across or less (S22) draws the FAF5
    # network cropped to the map; a larger one the Interstates, if it is within the latitude span limit.
    hroads = nothing
    if roads !== false
        over = roads === :auto ? (;) : roads
        latspan = abs(limits[2][2] - limits[2][1])
        if Logjam._mapisclose(limits)
            hroads = _networkroads!(ax, limits, over)
        elseif latspan <= _INTERSTATE_MAXLATSPAN
            style = _INTERSTATE_STYLE[_zoom(latspan)]
            hroads = lines!(ax, Logjam.faf5interstateroads()...,
                            color = (get(over, :color, :steelblue), get(over, :alpha, style.alpha)),
                            linewidth = get(over, :linewidth, style.linewidth), label = "Interstate Roads")
        end
    end

    # U.S. state borders and country borders, if wanted; a NamedTuple overrides attributes
    hstates, hcountries = nothing, nothing
    if borders !== false
        over = borders === true ? (;) : borders
        bcolor, bwidth = get(over, :color, :blue), get(over, :linewidth, .75)
        if doUSborder
            hstates = lines!(ax, Logjam.usstates()..., color=bcolor, linewidth=bwidth, label="US State Borders")
            if doCountryborder
                hstates.linestyle = :dash
                hstates.alpha = 0.5
            end
        end
        if doCountryborder
            hcountries = lines!(ax, Logjam.countries()..., color=bcolor, linewidth=bwidth, label="Country Borders")
        end
    end

    # The height that fits the map, as Lecture 5.3's fitmap! fits it
    if target === nothing && size[2] === :auto
        lim = ax.finallimits[]
        resize!(fig, size[1], round(Int, size[1] * lim.widths[2] / lim.widths[1]) + 10)
    end

    return (; fig, ax, layers = (; roads = hroads, states = hstates, countries = hcountries))
end

# =============================================================================
# plotroads!
# =============================================================================
function plotroads!(ax, dfN::DataFrame, dfL::DataFrame; show_connectors::Bool = false)
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
        1 => (close=1.0,  mid=0.7, far=0.25),
        2 => (close=0.9,  mid=0.6, far=0.2),
        3 => (close=0.7,  mid=0.4, far=0.12),
        4 => (close=0.5,  mid=0.3, far=0.08),
        5 => (close=0.3,  mid=0.15, far=0.05),
    )

    tier_alphas = Dict(
        1 => (close=0.6, mid=0.4, far=0.25),
        2 => (close=0.5, mid=0.35, far=0.2),
        3 => (close=0.4, mid=0.25, far=0.15),
        4 => (close=0.35, mid=0.2, far=0.1),
        5 => (close=0.3, mid=0.15, far=0.08),
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
        tier = _fclasstier(fc)

        src_lon, src_lat = node_lookup[src_active[i]]
        dst_lon, dst_lat = node_lookup[dst_active[i]]

        push!(polylines[tier][1], src_lon, dst_lon, NaN)
        push!(polylines[tier][2], src_lat, dst_lat, NaN)
    end

    # 7. Compute adaptive styling and render. The zoom is makemap's road layer's rule (_zoom): a casing under each
    # tier's fill at close zoom, the fill alone at mid and far zoom.
    limits = ax.limits[]
    latspan = abs(limits[2][2] - limits[2][1])
    zoom = _zoom(latspan)
    handles = Dict{Symbol, Any}()

    if zoom === :close
        for tier in reverse(tiers)
            x_coords, y_coords = polylines[tier]
            length(x_coords) > 0 || continue
            w = tier_widths[tier]
            α = tier_alphas[tier]
            r, g, b = tier_colors[tier].casing
            h = lines!(ax, x_coords, y_coords;
                       linewidth=w.close + 0.6,
                       color=RGBf(r, g, b), alpha=α.close, linecap=:round)
            handles[Symbol("casing_", tier)] = h
        end
    end
    for tier in reverse(tiers)
        x_coords, y_coords = polylines[tier]
        length(x_coords) > 0 || continue
        w = tier_widths[tier]
        α = tier_alphas[tier]
        r, g, b = tier_colors[tier].fill
        h = lines!(ax, x_coords, y_coords;
                   linewidth=getproperty(w, zoom),
                   color=RGBf(r, g, b), alpha=getproperty(α, zoom), linecap=:round)
        handles[Symbol("fill_", tier)] = h
    end

    if length(connector_polylines[1]) > 0
        h = lines!(ax, connector_polylines[1], connector_polylines[2];
                   linewidth=0.3, color=(:gray55, 0.15), linestyle=:dash, linecap=:round)
        handles[:connector] = h
    end

    return handles
end

# =============================================================================
# plotroute! (D2): three methods, arrowheads on. Makie only: no GeoMakie call is made here, so the arrows are
# placed and turned from the axis's own transform and limits, on a GeoAxis or a plain Axis alike.
# =============================================================================

# Where a point of the data space is drawn, in pixels of the axis: the axis's own transform (the identity on a plain
# `Axis`, Mercator on `makemap`'s `GeoAxis`), then the visible limits over the axis's viewport. Read at each call, so
# a `resize!` or new limits move the answer with the drawing.
function _pixelmap(ax)
    tf = Makie.transform_func(ax)
    fl = ax.finallimits[]
    o, w = Makie.origin(fl), Makie.widths(fl)
    W = Makie.widths(ax.scene.viewport[])
    return function (x, y)
        p = Makie.apply_transform(tf, Makie.Point2d(x, y))
        return Makie.Point2d((p[1] - o[1]) / w[1] * W[1], (p[2] - o[2]) / w[2] * W[2])
    end
end

# The arrowhead of each leg: its center `at` of the way along the leg as drawn (by length on the screen) and the
# angle the leg runs at there, on the screen. `legs` is one (x, y) pair of vectors for each leg.
function _arrowheads(ax, legs, at)
    topix = _pixelmap(ax)
    pos, rot = Makie.Point2f[], Float32[]
    for (lx, ly) in legs
        P = [topix(lx[k], ly[k]) for k in eachindex(lx)]
        seg = [hypot(P[k+1][1] - P[k][1], P[k+1][2] - P[k][2]) for k in 1:length(P)-1]
        total = sum(seg)
        if !(total > 0)                       # no length on the screen yet (before the first layout): no direction
            push!(pos, P[1]); push!(rot, 0f0)
            continue
        end
        target, k = at * total, 1
        while k < length(seg) && (target > seg[k] || seg[k] == 0)
            target -= seg[k]
            k += 1
        end
        s = seg[k] > 0 ? clamp(target / seg[k], 0.0, 1.0) : 1.0
        if seg[k] == 0                        # only repeated vertices from here on: the last stretch with a direction
            k = findlast(>(0), seg)
            s = 1.0
        end
        d = P[k+1] - P[k]
        push!(pos, Makie.Point2f(P[k] + s * d))
        push!(rot, Float32(atan(d[2], d[1])))
    end
    return pos, rot
end

# The arrowheads as one scatter plot in the axis's pixel space, turned and placed again whenever the viewport or the
# visible limits change.
function _drawarrows!(ax, legs; color, at, size)
    state = Observable(_arrowheads(ax, legs, at))
    onany((_...) -> (state[] = _arrowheads(ax, legs, at)), ax.finallimits, ax.scene.viewport)
    return scatter!(ax, lift(first, state); marker = :rtriangle, markersize = size, rotation = lift(last, state),
                    color = color, space = :pixel, strokewidth = 0, inspectable = false)
end

# the line and its arrowheads; `legs` already holds only the legs that get one
function _drawroute!(ax, x, y, legs; color, linewidth, linestyle, arrows, arrow_at, arrow_size)
    hl = lines!(ax, x, y; color = color, linewidth = linewidth, linestyle = linestyle)
    ha = arrows ? _drawarrows!(ax, legs; color = color, at = arrow_at, size = arrow_size) : nothing
    return (; lines = hl, arrows = ha)
end

function _checkarrows(arrow_at, arrow_every)
    0 <= arrow_at <= 1 || throw(ArgumentError("arrow_at must be in [0, 1], the fraction of a leg's length; got $arrow_at"))
    arrow_every >= 1 || throw(ArgumentError("arrow_every must be at least 1; got $arrow_every"))
end

# a leg is each pair of consecutive finite points; the arrow_every-th leg, counting from the first, gets an arrowhead
# unless it has no length (a location visited twice)
function _xylegs(x, y, every)
    legs, n = Tuple{Vector{Float64}, Vector{Float64}}[], 0
    for i in 1:length(x)-1
        all(isfinite, (x[i], y[i], x[i+1], y[i+1])) || continue
        n += 1
        (n - 1) % every == 0 || continue
        (x[i] == x[i+1] && y[i] == y[i+1]) && continue
        push!(legs, ([Float64(x[i]), Float64(x[i+1])], [Float64(y[i]), Float64(y[i+1])]))
    end
    return legs
end

# any sequence of locations
function plotroute!(ax, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                    color = :red, linewidth = 2, linestyle = :solid,
                    arrows::Bool = true, arrow_at::Real = 0.55, arrow_size::Real = 12, arrow_every::Integer = 1)
    length(x) == length(y) || throw(ArgumentError("x and y must have the same length; got $(length(x)) and $(length(y))"))
    _checkarrows(arrow_at, arrow_every)
    return _drawroute!(ax, x, y, _xylegs(x, y, arrow_every); color, linewidth, linestyle, arrows, arrow_at, arrow_size)
end

# one route: its location sequence (`rte2loc`), straight from stop to stop, or along the network by `P`
function plotroute!(ax, rte::AbstractVector{<:Integer}, sh::AbstractDataFrame, XY::AbstractMatrix{<:Real};
                    tr = nothing, P = nothing, color = :red, linewidth = 2, linestyle = :solid,
                    arrows::Bool = true, arrow_at::Real = 0.55, arrow_size::Real = 12, arrow_every::Integer = 1)
    size(XY, 2) == 2 || throw(ArgumentError("XY must have two columns (LON, LAT), one row for each location; got $(size(XY, 2))"))
    loc = Int.(Logjam.rte2loc(rte, sh, something(tr, (;))))
    if P === nothing
        return plotroute!(ax, XY[loc, 1], XY[loc, 2]; color, linewidth, linestyle, arrows, arrow_at, arrow_size, arrow_every)
    end
    _checkarrows(arrow_at, arrow_every)
    legs = Tuple{Vector{Float64}, Vector{Float64}}[]
    for k in 1:length(loc)-1                  # an arrowhead on each leg traced along the network
        path = Logjam.tracepath(P, loc[k], loc[k+1])
        lx, ly = Float64.(XY[path, 1]), Float64.(XY[path, 2])
        ((k - 1) % arrow_every == 0 && !(all(==(lx[1]), lx) && all(==(ly[1]), ly))) && push!(legs, (lx, ly))
    end
    path = length(loc) >= 2 ? Logjam.tracepath(P, loc) : Int[]     # the line: the legs end to end, a junction one node
    return _drawroute!(ax, Float64.(XY[path, 1]), Float64.(XY[path, 2]), legs; color, linewidth, linestyle, arrows, arrow_at, arrow_size)
end

# several routes, one color each
function plotroute!(ax, R::AbstractVector{<:AbstractVector{<:Integer}}, sh::AbstractDataFrame, XY::AbstractMatrix{<:Real};
                    tr = nothing, P = nothing, colors = Makie.wong_colors(), linewidth = 2, linestyle = :solid,
                    arrows::Bool = true, arrow_at::Real = 0.55, arrow_size::Real = 12, arrow_every::Integer = 1)
    hs = [plotroute!(ax, rte, sh, XY; tr, P, color = colors[mod1(i, length(colors))], linewidth, linestyle,
                     arrows, arrow_at, arrow_size, arrow_every) for (i, rte) in enumerate(R)]
    return (; lines = [h.lines for h in hs], arrows = [h.arrows for h in hs])
end

end # module LogjamMapExt
