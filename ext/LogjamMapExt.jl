module LogjamMapExt

# The map functions, loaded by GeoMakie alone (C5). Written against Makie through GeoMakie, which reexports it: no
# backend is loaded here, so the figures this draws are drawn by whichever of CairoMakie or GLMakie the caller loaded
# (the course loads CairoMakie, and a figure is created without one). Logjam declares each function and keeps its
# docstring (src/maptools.jl, src/Logjam.jl); this adds the methods. `plotroute!`, which makes no GeoMakie call, moved
# to the Makie extension in v0.3.1 (WP7b, MAP16), which GeoMakie loads too.

using Logjam
using GeoMakie
using GeoMakie: Makie
using DataFrames
import Logjam: makemap, plotroads!, dcf

# =============================================================================
# dcf: display the current figure
# =============================================================================
# Deprecated in v0.3.1 (WP9, MAP17), removed in v0.4.0: it still displays the current figure, and `Base.depwarn` prints
# its message only when Julia runs with `--depwarn=yes` (as `Pkg.test` does), so a script's output is unchanged.
function dcf()
    Base.depwarn("`dcf()` is deprecated and is removed in Logjam v0.4.0: end the cell with the figure, `fig`, " *
                 "or call `display(current_figure())`.", :dcf)
    display(Makie.current_figure())
    return nothing
end

# =============================================================================
# One zoom rule for the road layers of makemap and plotroads!: the map's latitude span, in degrees
# =============================================================================
_zoom(latspan) = latspan <= 10 ? :close : latspan <= 20 ? :mid : :far

# =============================================================================
# makemap's road layer, in the tiers of his answer to Q2 (MakePlan D8), told apart by `Logjam._maproadtier` on the box
# as drawn:
#   :close     150 miles across or less (S22's measure, tested first): the FAF5 network as published, every class, 1 to
#              5, as `plotroads!` groups them, every link core's ramp rule calls a ramp left out (RN23), as five Lines, one
#              for each class (S22, S23);
#   :regional  otherwise, at most 10 degrees of latitude: Logjam's U.S. road network (`usrdlink`, derived from FAF5; CR
#              19, N4), classes 1 to 3 (Interstates, other freeways and expressways, other principal arterials), as one
#              Lines labeled "Major Roads", the classes by width (RN24);
#   :national  otherwise, at most 30 degrees: the U.S. road network's links flagged `INTERSTATE`, as one Lines;
#   :none      more than 30 degrees: nothing.
# Each is cropped to the box (every link whose segment meets it, so the roads run to the frame). The close tier stays
# FAF5's (N4): drawn from the derived network, its collapsed interchanges were stars of straight stubs at 20 miles across
# and its density proxy rose, so it draws FAF5's own links with the ramps core finds left out (RN23, option b). The
# derived network has no ramp (its derivation drops them, D2).
# =============================================================================

# the FCLASS tier (1 to 5) of a link: the Interstate is 1, a class of 5 or more, or of 0, is 5
_fclasstier(fc) = fc <= 0 ? 5 : (fc >= 5 ? 5 : fc)

# S23: one hue, as Lecture 2.5 draws it by hand ("Same hue as makemap's own roads, so the two layers look alike"), and
# every stroke below alpha 0.35, the course figure gate's muted base (`FAINT_ALPHA`, figure_labels.jl, which files a
# stroke apart only when it is fainter than 0.35); 2.5's own network is 0.45, over it, so that number is not copied. The
# classes differ by width, the Interstate the heaviest. There is no casing: a second, wider stroke of the same hue under
# each class would be a second stroke to keep below 0.35.
const _NETWORK_HUE = :steelblue
const _NETWORK_ALPHA = 0.3
const _NETWORK_WIDTHS = (1.4, 1.0, 0.7, 0.5, 0.3)         # class 1 (Interstate) to class 5 (local, and any class 5 or more)
const _NETWORK_LAYERS = (:class1, :class2, :class3, :class4, :class5)

# The regional and national tiers' steps by latitude span (`_zoom`), the Interstate's opacity and width (RN24, RN25). The
# regional tier is always `close` (10 degrees or less), the national `mid` or `far`. v0.3.0 drew both carriageways of a
# divided Interstate, two strokes that overlap at these scales and read darker than one, so one line, which now stands for
# both, is wider and more opaque than either was, and every opacity stays below 0.35 (S23), so width does the work (the
# `far` step's 0.3 is RN25's). The numbers are N4b's, chosen from measured ink: the mean ink on the Interstate's pixels in
# the saved picture, against v0.3.0's picture of the same map, within 10 percent on North Carolina, the Southeast, a
# Virginia-to-Maryland box, the continental U.S. and a 17-degree box. Classes 2 and 3 of the regional tier, beneath the
# Interstate, are thinner, in these ratios of its width (classes 1, 2 and 3), and a stroke thinner than a pixel carries
# less ink, so they are fainter as well: the layer is one color, since a color for each point (one opacity for each class)
# breaks Lecture 5.3's `to_color(p.color[]).alpha`, which reads the color of every plot.
const _INTERSTATE_STYLE = (close = (alpha = 0.32, linewidth = 0.7), mid = (alpha = 0.32, linewidth = 0.85),
                           far = (alpha = 0.3, linewidth = 0.8))
const _MAJOR_WIDTHS = (1.0, 0.3, 0.15)

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

# The ramps of an interchange are not drawn on the close tier (his ruling of 2026-11-21, on S22's pictures, and RN23): at
# this scale they pile up into blotches. Which links are ramps is core's one rule (`Logjam._ramp_links`, D2), computed
# once with the tier's link ends below.

# The end points and class of each link a tier draws, read on the first map of that tier and kept, so that a crop is a
# pass over four plain vectors and not a lookup of every link's two nodes in the node table on each call (a crop that
# did that took 0.14 to 0.17 s): the close tier from the cached FAF5 tables (about 16 MB), the regional and national
# tiers from the derived network's (`usrdnode`, `usrdlink`). A class of 0 marks a link not drawn: a ramp (core's rule) on the
# close tier, a link to a node the table lacks (none: plotroads! refuses one). The regional and national tiers keep their links
# lightest class first, the table's order within a class, so that one Lines draws the Interstate last, on top; the
# national tier's links are all class 1. The FAF5 tables have no `SOURCE` column and no connector; `plotroads!` hides a
# connector if a table has one.
const _LINKENDS = Dict{Symbol, Any}()
const _LINKENDS_LOCK = ReentrantLock()

_linkends(tier::Symbol) = lock(() -> get!(() -> _tierends(tier), _LINKENDS, tier), _LINKENDS_LOCK)

function _tierends(tier::Symbol)
    tier in (:close, :regional, :national) || throw(ArgumentError("no road tier $(repr(tier))"))
    N, L = tier === :close ? Logjam._faf5tables() : (Logjam._usrdnodes(), Logjam._usrdlinks())
    lon = fill(NaN, maximum(N.IDX))
    lat = fill(NaN, maximum(N.IDX))
    lon[N.IDX] = N.LON
    lat[N.IDX] = N.LAT
    cls = Int8.(_fclasstier.(L.FCLASS))
    if tier === :close
        k = collect(eachindex(cls))
        cls[Logjam._ramp_links(N, L)] .= 0
    else
        keep = tier === :regional ? cls .<= 3 : L.INTERSTATE
        tier === :national && (cls .= 1)
        k = reduce(vcat, [findall(keep .& (cls .== c)) for c in 5:-1:1])
    end
    x1, y1, x2, y2 = lon[L.SRC[k]], lat[L.SRC[k]], lon[L.DST[k]], lat[L.DST[k]]
    c = cls[k]
    c[.!isfinite.(x1 .+ y1 .+ x2 .+ y2)] .= 0
    return (; x1, y1, x2, y2, tier = c)
end

# The links of a tier whose segment meets the box (so the roads run to the frame's edge), as NaN-separated polylines for
# each class 1 to 5.
_networkcrop(tier::Symbol, limits) = (e = _linkends(tier); _cropends(e.x1, e.y1, e.x2, e.y2, e.tier, limits))

# (a function of its own so that the loop is compiled for the vectors' types, which the Dict that holds them does not say)
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

# The close tier as five plots (S22, S23), lightest class first so the Interstate is on top; `over` is `roads`'
# NamedTuple, if any: `color` replaces the hue, `alpha` the opacity of every class, and `linewidth` the Interstate's
# width, the other classes keeping their ratios to it. The heaviest class drawn carries the label. Returns
# `(; class1, ..., class5)`, `nothing` for a class with no link in the box.
function _networkroads!(ax, limits, over)
    hue, alpha = get(over, :color, _NETWORK_HUE), get(over, :alpha, _NETWORK_ALPHA)
    scale = get(over, :linewidth, _NETWORK_WIDTHS[1]) / _NETWORK_WIDTHS[1]
    polylines = _networkcrop(:close, limits)
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

# The regional and national tiers as one Lines, labeled "Major Roads" on the regional tier (RN26) and "Interstate Roads"
# on the national, as v0.3.0's Interstate layer was: the Interstate's opacity and width by `_zoom`'s step, `over`
# replacing the hue, the opacity and the Interstate's width; on the regional tier each segment has its class's width (a
# width for each point, classes 3, 2 and 1 in that order, so the Interstate is drawn last; CairoMakie strokes each
# NaN-separated piece of such a Lines on its own), classes 2 and 3 in `_MAJOR_WIDTHS` to the Interstate's (RN24). A box
# with no link in it draws an empty Lines at the Interstate's width, so `layers.roads` is a Lines on these tiers.
function _wideroads!(ax, tier, limits, over)
    style = _INTERSTATE_STYLE[_zoom(abs(limits[2][2] - limits[2][1]))]
    hue, alpha = get(over, :color, _NETWORK_HUE), get(over, :alpha, style.alpha)
    w1 = get(over, :linewidth, style.linewidth)
    polylines = _networkcrop(tier, limits)
    if tier === :national
        x, y = polylines[1]
        return lines!(ax, x, y; color = (hue, alpha), linewidth = w1, label = "Interstate Roads")
    end
    x, y, w = Float64[], Float64[], Float64[]
    for k in 3:-1:1
        append!(x, polylines[k][1])
        append!(y, polylines[k][2])
        append!(w, fill(w1 * _MAJOR_WIDTHS[k], length(polylines[k][1])))
    end
    return lines!(ax, x, y; color = (hue, alpha), linewidth = isempty(w) ? w1 : w, label = "Major Roads")
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

    # The road layer, if wanted; a NamedTuple overrides attributes. The tier the map's size calls for (above), cropped to
    # the map: FAF5's every class at 150 miles across or less, the derived network's classes 1 to 3 up to 10 degrees of
    # latitude and its Interstates up to 30, nothing beyond.
    hroads = nothing
    if roads !== false
        over = roads === :auto ? (;) : roads
        tier = Logjam._maproadtier(limits)
        if tier === :close
            hroads = _networkroads!(ax, limits, over)
        elseif tier !== :none
            hroads = _wideroads!(ax, tier, limits, over)
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

end # module LogjamMapExt
