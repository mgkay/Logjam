# LogjamMakieExt: plotting that needs only Makie, not GeoMakie. Loaded whenever Makie is, so with CairoMakie alone and
# with GeoMakie. Built in v0.3.1's WP7a:
# - `aligntext(ax, x, y, labels; ...)`, a label placer that reads the drawn figure (D1, CR 52, CR 61, CR 3), declared
#   and documented in core beside `aligntext(x, y)` (src/maptools.jl), which it leaves unchanged;
# - in WP8, a precompile workload for it (D12), at the end of this file;
# - in WP7a-2, from his review of WP7a's pictures (Jacksonville on 5.2's maps): a label never moves farther from its
#   point only to clear a base line that grazes it, and no base line crosses a label's text to bring it nearer;
#   distance as seen; the labels' moves taken largest first (see _place).
# It is review D's round-three placer (makeLogjam/plans/v0_3_0/recon/refactor-D/placer2.jl and refactor-D-plotting.md,
# "Rounds two and three"), ported: the same obstacles, costs, candidates, fine-grid fallback and search, without the
# prototype's simulated annealing (off by default there, and the only thing in it that drew a random number), so the
# placement is a function of the figure alone.
# - in WP7b (D2, MAP16, CR 50, CR 61): `plotroute!`'s three methods, moved here from LogjamMapExt as they were (they
#   make no GeoMakie call, so they draw on a plain `Axis` with CairoMakie alone), with `names`, `loads` and `number`;
#   `plotshmt!`; the stops' labels and the route numbers placed by `aligntext(ax, ...)` and placed again when a later
#   `plotroute!` or `plotshmt!` call adds to the axis. Declared and documented in core (src/maptools.jl). The
#   schematics (WP7c) come later.
module LogjamMakieExt

import Logjam
using Makie: Makie, text!
using DataFrames: AbstractDataFrame

# =============================================================================
# Geometry, in the pixels of the axis's scene (its viewport's lower-left corner is the origin)
# =============================================================================
struct _Box
    x0::Float64
    x1::Float64
    y0::Float64
    y1::Float64
end
_shift(b::_Box, dx, dy) = _Box(b.x0 + dx, b.x1 + dx, b.y0 + dy, b.y1 + dy)
_grow(b::_Box, m) = _Box(b.x0 - m, b.x1 + m, b.y0 - m, b.y1 + m)
_hit(a::_Box, b::_Box) = a.x0 < b.x1 && b.x0 < a.x1 && a.y0 < b.y1 && b.y0 < a.y1
_boxdist(p, b::_Box) = hypot(max(b.x0 - p[1], 0, p[1] - b.x1), max(b.y0 - p[2], 0, p[2] - b.y1))
_unionbox(bs) = _Box(minimum(b.x0 for b in bs), maximum(b.x1 for b in bs),
                     minimum(b.y0 for b in bs), maximum(b.y1 for b in bs))

# Does the segment a-b meet box B? (Liang-Barsky)
function _segbox(a, b, B::_Box)
    t0, t1 = 0.0, 1.0
    dx, dy = b[1] - a[1], b[2] - a[2]
    for (p, q) in ((-dx, a[1] - B.x0), (dx, B.x1 - a[1]), (-dy, a[2] - B.y0), (dy, B.y1 - a[2]))
        if p == 0
            q < 0 && return false
        else
            r = q / p
            if p < 0
                r > t1 && return false
                t0 = max(t0, r)
            else
                r < t0 && return false
                t1 = min(t1, r)
            end
        end
    end
    return true
end

# =============================================================================
# Reading the figure
# =============================================================================
_attr(p, k, d = nothing) = haskey(p.attributes, k) ? getproperty(p, k)[] : d
function _px(p)
    k = :logjam_aligntext_px
    haskey(p.attributes, k) || Makie.register_projected_positions!(p; output_space = :pixel, output_name = k)
    return getproperty(p, k)[]
end
function _alpha(c)
    try
        col = Makie.to_color(c)
        return col isa Makie.Colors.Colorant ? Float64(Makie.Colors.alpha(col)) : 1.0
    catch
        return 1.0
    end
end
_opacity(p) = (a = _attr(p, :alpha, 1.0); (a isa Real ? Float64(a) : 1.0) * _alpha(_attr(p, :color)))

# The ink boxes of each string of a Text plot, one per text line, relative to its anchor with no offset (glyph origins
# are relative to the anchor), in pixels. A rotated glyph contributes the box around its rotated ink.
function _inkboxes(tp)
    blocks, origins, exts = tp.text_blocks[], tp.glyph_origins[], tp.glyph_extents[]
    scales, gidx, rots = tp.text_scales[], tp.glyphindices[], tp.text_rotation[]
    out = Vector{Vector{_Box}}(undef, length(blocks))
    for (b, r) in enumerate(blocks)
        rects = Tuple{_Box, Float64}[]
        fs = 1.0
        for i in r
            gidx[i] == 0 && continue
            ink = exts[i].ink_bounding_box
            o, w = Makie.origin(ink), Makie.widths(ink)
            (w[1] <= 0 || w[2] <= 0) && continue
            s, u = scales[i], origins[i]
            fs = max(fs, Float64(s[2]))
            q = rots[i]
            if q isa Makie.Quaternion && abs(q[4]) < 0.9999
                cs = [q * Makie.Vec3f((o[1] + cx * w[1]) * s[1], (o[2] + cy * w[2]) * s[2], 0)
                      for (cx, cy) in ((0, 0), (1, 0), (1, 1), (0, 1))]
                push!(rects, (_Box(u[1] + minimum(c[1] for c in cs), u[1] + maximum(c[1] for c in cs),
                                   u[2] + minimum(c[2] for c in cs), u[2] + maximum(c[2] for c in cs)),
                              Float64(u[2])))
                continue
            end
            push!(rects, (_Box(u[1] + o[1] * s[1], u[1] + (o[1] + w[1]) * s[1],
                               u[2] + o[2] * s[2], u[2] + (o[2] + w[2]) * s[2]), Float64(u[2])))
        end
        groups = Vector{Vector{_Box}}()          # text lines, by baseline within half a font size
        lastbase = NaN
        for (bx, base) in sort(rects; by = x -> -x[2])
            if !isempty(groups) && abs(lastbase - base) < 0.5fs
                push!(groups[end], bx)
            else
                push!(groups, [bx])
                lastbase = base
            end
        end
        out[b] = [_unionbox(g) for g in groups]
    end
    return out
end

struct _Seg
    a::NTuple{2, Float64}
    b::NTuple{2, Float64}
    hw::Float64          # half the line width
    w::Float64           # the cost of crossing it: a data line's or a base layer's
    group::Int           # the top-level plot it belongs to, charged once
end
struct _Obs
    box::_Box
    w::Float64
    group::Int
end

# Base layers (MAP1): `makemap`'s road and border layers, recognized by the plot labels the map extension gives them
# (ext/LogjamMapExt.jl), so a label may touch one at a low cost and never crosses a data line to avoid one. The close
# tier's road classes are five plots of one color drawn one after the other, and only the last, the heaviest class,
# carries "FAF5 Roads": the unlabeled plots of its color drawn just before it are its other classes.
const _BASE_LABELS = ("FAF5 Roads", "Major Roads", "Interstate Roads", "US State Borders", "Country Borders")
_plotlabel(p) = haskey(p.attributes, :label) ? p.label[] : nothing
_isbaselabel(p) = (l = _plotlabel(p); l !== nothing && string(l) in _BASE_LABELS)
_unlabeled(p) = (l = _plotlabel(p); l === nothing || isempty(string(l)))
function _basemask(plots)
    base = [_isbaselabel(p) for p in plots]
    for (k, p) in enumerate(plots)
        (p isa Makie.Lines && string(_plotlabel(p)) == "FAF5 Roads") || continue
        j = k - 1
        while j >= 1 && plots[j] isa Makie.Lines && _unlabeled(plots[j]) &&
              isequal(_attr(plots[j], :color), _attr(p, :color))
            base[j] = true
            j -= 1
        end
    end
    return base
end

# Every stroke, marker and other label in the axis, in pixels, as obstacles. A data line, a marker and a label cost
# 1000 (near-hard: a label goes out to the fallback radius rather than cross one), a base layer 40. On a map (any axis
# but a plain `Axis`) a stroke fainter than 0.35 is the muted base and is no obstacle, as the course's label check has it.
function _obstacles(ax, targets; wline = 1000.0, wbase = 40.0, wmark = 1000.0, wtext = 1000.0, faint = 0.35)
    scene = ax.scene
    ismap = !(ax isa Makie.Axis)
    decor = hasproperty(ax, :elements) ? Set{UInt}(objectid(v) for v in values(ax.elements)) : Set{UInt}()
    segs, obs = _Seg[], _Obs[]
    group = Ref(0)
    function walk(p, wl)
        _attr(p, :visible, true) || return
        if p isa Makie.Text
            any(t -> t === p, targets) && return
            anchors = Makie.register_markerspace_positions!(p)[]
            offs = p.offset[]
            for (b, bs) in enumerate(_inkboxes(p))
                a = anchors[b]
                any(isnan, a) && continue
                o = Makie.sv_getindex(offs, b)
                for bx in bs
                    push!(obs, _Obs(_shift(bx, a[1] + o[1], a[2] + o[2]), wtext, group[]))
                end
            end
        elseif p isa Makie.Lines || p isa Makie.LineSegments
            op = _opacity(p)
            (op <= 0 || (ismap && op < faint)) && return
            pts = _px(p)
            lw = _attr(p, :linewidth, 1.0)
            step = p isa Makie.LineSegments ? 2 : 1
            for i in 1:step:length(pts)-1
                a, b = pts[i], pts[i+1]
                (any(isnan, a) || any(isnan, b)) && continue
                hw = Float64(lw isa AbstractVector ? lw[min(i, end)] : lw) / 2
                push!(segs, _Seg((Float64(a[1]), Float64(a[2])), (Float64(b[1]), Float64(b[2])), hw, wl, group[]))
            end
        elseif p isa Makie.Scatter
            pts = _px(p)
            ms = _attr(p, :markersize, 9.0)
            mk = _attr(p, :marker, :circle)
            sw = Float64(_attr(p, :strokewidth, 0.0))
            (_opacity(p) <= 0 && sw <= 0) && return
            for (i, c) in enumerate(pts)
                any(isnan, c) && continue
                s = ms isa AbstractVector ? ms[min(i, end)] : ms
                s = s isa Number ? Float64(s) : Float64(maximum(s))
                m = mk isa AbstractVector ? mk[min(i, end)] : mk
                r = m === :circle ? 0.36s : (m isa Type && m <: Makie.Circle) || m isa Makie.Circle ? 0.5s :
                    m isa Char ? 0.15s : 0.45s
                r += sw / 2
                push!(obs, _Obs(_Box(c[1] - r, c[1] + r, c[2] - r, c[2] + r), wmark, group[]))
            end
        else
            for c in p.plots
                walk(c, wl)
            end
        end
    end
    plots = scene.plots
    base = _basemask(plots)
    for (k, p) in enumerate(plots)
        objectid(p) in decor && continue
        group[] += 1
        walk(p, base[k] ? wbase : wline)
    end
    w, h = Float64.(Makie.widths(scene.viewport[]))
    return segs, obs, w, h
end

# A uniform grid over the viewport, so that a candidate box tests only the strokes and obstacles near it.
struct _Grid
    cell::Float64
    nx::Int
    ny::Int
    segs::Vector{Vector{Int}}
    obs::Vector{Vector{Int}}
end
function _Grid(segs, obs, w, h; cell = 24.0)
    nx, ny = max(1, ceil(Int, w / cell)), max(1, ceil(Int, h / cell))
    S = [Int[] for _ in 1:nx*ny]
    O = [Int[] for _ in 1:nx*ny]
    cl(v, n) = clamp(floor(Int, v / cell) + 1, 1, n)
    for (k, s) in enumerate(segs)
        x0, x1 = minmax(s.a[1], s.b[1])
        y0, y1 = minmax(s.a[2], s.b[2])
        (x1 < -cell || x0 > w + cell || y1 < -cell || y0 > h + cell) && continue
        for i in cl(x0 - s.hw, nx):cl(x1 + s.hw, nx), j in cl(y0 - s.hw, ny):cl(y1 + s.hw, ny)
            B = _Box((i - 1) * cell, i * cell, (j - 1) * cell, j * cell)
            _segbox(s.a, s.b, _grow(B, s.hw + 1)) && push!(S[(j-1)*nx+i], k)
        end
    end
    for (k, o) in enumerate(obs)
        for i in cl(o.box.x0, nx):cl(o.box.x1, nx), j in cl(o.box.y0, ny):cl(o.box.y1, ny)
            push!(O[(j-1)*nx+i], k)
        end
    end
    return _Grid(cell, nx, ny, S, O)
end

# The nine alignments a candidate can take: E NE N NW W SW S SE of the point, and on it.
const _DIRS = [(:left, :center), (:left, :bottom), (:center, :bottom), (:right, :bottom),
               (:right, :center), (:right, :top), (:center, :top), (:left, :top), (:center, :center)]
const _DVEC = [(1.0, 0.0), (0.7071, 0.7071), (0.0, 1.0), (-0.7071, 0.7071),
               (-1.0, 0.0), (-0.7071, -0.7071), (0.0, -1.0), (0.7071, -0.7071), (0.0, 0.0)]
# Christensen, Marks and Shieber (1995) Fig. 1, after Imhof and Yoeli: NE, NW, SW, SE, E, N, W, S (lower is better),
# by the indices of _DIRS.
const _IMHOF = Dict(2 => 0, 4 => 1, 6 => 2, 8 => 3, 1 => 4, 3 => 5, 5 => 6, 7 => 7, 9 => 0)
_dirof(al) = findfirst(==(al), _DIRS)

struct _Drawing
    ax::Any
    tp::Any
    anchors::Vector{NTuple{2, Float64}}
    rel::Vector{Vector{Vector{_Box}}}    # rel[d][i]: label i's line boxes at alignment _DIRS[d], relative to its anchor
    segs::Vector{_Seg}
    obs::Vector{_Obs}
    grid::_Grid
    w::Float64
    h::Float64
end

_figureof(ax) = (p = ax.parent; p isa Makie.Figure ? p : nothing)

# The laid-out figure, read once: the labels' anchors, each label's ink at each alignment, and the obstacles.
function _Drawing(ax, tp)
    fig = _figureof(ax)
    fig === nothing || Makie.update_state_before_display!(fig)
    anchors = [(Float64(a[1]), Float64(a[2])) for a in Makie.register_markerspace_positions!(tp)[]]
    n = length(anchors)
    al0, of0 = tp.align[], tp.offset[]
    rel = Vector{Vector{Vector{_Box}}}(undef, length(_DIRS))
    for (d, a) in enumerate(_DIRS)
        tp.align = fill(a, n)
        tp.offset = fill((0.0, 0.0), n)
        rel[d] = _inkboxes(tp)
    end
    tp.align = al0
    tp.offset = of0
    segs, obs, w, h = _obstacles(ax, [tp])
    if fig !== nothing                   # a legend drawn inside the axis is an obstacle too
        o = Makie.origin(ax.scene.viewport[])
        for b in fig.content
            b isa Makie.Legend || continue
            bb = b.layoutobservables.computedbbox[]
            lo, wd = Makie.origin(bb), Makie.widths(bb)
            push!(obs, _Obs(_Box(lo[1] - o[1], lo[1] - o[1] + wd[1], lo[2] - o[2], lo[2] - o[2] + wd[2]), 1000.0, -1))
        end
    end
    return _Drawing(ax, tp, anchors, rel, segs, obs, _Grid(segs, obs, w, h), w, h)
end

struct _Cand
    d::Int                        # its alignment, an index of _DIRS
    off::NTuple{2, Float64}       # its offset, in pixels
    r::Float64                    # its distance from the point, in pixels
end

function _candidates(radii)
    C = _Cand[]
    for r in radii, d in (r == 0 ? (9:9) : (1:8))
        v = _DVEC[d]
        push!(C, _Cand(d, (round(r * v[1]; digits = 1), round(r * v[2]; digits = 1)), r))
    end
    return C
end

_boxes_at(D::_Drawing, i, c::_Cand) = [_shift(b, D.anchors[i][1] + c.off[1], D.anchors[i][2] + c.off[2]) for b in D.rel[c.d][i]]

# A box shrunk inward by m on every side, never past its center line.
function _shrink(b::_Box, m)
    cx, cy = (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2
    return _Box(min(b.x0 + m, cx), max(b.x1 - m, cx), min(b.y0 + m, cy), max(b.y1 - m, cy))
end

# How far inside a label's ink boxes a base line must reach to cross its text rather than graze it, in pixels. 0: a
# stroke that enters an ink box at all crosses, and one that touches only the clearance around the boxes grazes.
# Measured on the 16 label figures (WP7a-2, labelcheck-alternatives.tsv in makeLogjam's measurements/wp7a2/): every
# inset from 0.5 px up let a base line into the ink box of a label that was clear of it before, Tucson's on 3.4's map
# first, and 0 brings Jacksonville to the lecture's own spot all the same.
const _INSET = 0.0

# The static cost of label i at candidate c: what it crosses, and the axis edge, in two parts. `hard`: a data line
# charged once per plot crossed plus 1 per segment, a marker or other label once each, any part outside the axis 5000.
# `base`: a base layer charged once per plot touched (40), and `bsegs`, 1 per base segment touched. The whole is
# hard + base + bsegs (_scost). `bcross`: the base plots whose stroke reaches into a line box shrunk by `inset` (by
# default 0, so into the box at all), through the text; a base plot touched and not crossed only grazes the label,
# touching its `clear` margin. _place lets a graze that brings a label nearer cost only its bsegs, never a crossing
# (WP7a-2).
function _static(D::_Drawing, i, c::_Cand; clear = 2.0, wedge = 5000.0, inset = _INSET)
    bs = _boxes_at(D, i, c)
    cost = 0.0
    for b in bs
        (b.x0 < 1 || b.x1 > D.w - 1 || b.y0 < 1 || b.y1 > D.h - 1) && (cost += wedge)
    end
    G = D.grid
    cl(v, n) = clamp(floor(Int, v / G.cell) + 1, 1, n)
    seen = Set{Int}()
    seeno = Set{Int}()
    for b in bs
        bb = _grow(b, clear)
        for ii in cl(bb.x0, G.nx):cl(bb.x1, G.nx), jj in cl(bb.y0, G.ny):cl(bb.y1, G.ny)
            cellid = (jj - 1) * G.nx + ii
            for k in G.segs[cellid]
                k in seen && continue
                s = D.segs[k]
                _segbox(s.a, s.b, _grow(bb, s.hw)) && push!(seen, k)
            end
            for k in G.obs[cellid]
                k in seeno && continue
                _hit(bb, D.obs[k].box) && push!(seeno, k)
            end
        end
    end
    groups, bgroups = Dict{Int, Float64}(), Dict{Int, Float64}()
    crossed = Set{Int}()
    bsegs = 0.0
    for k in seen
        s = D.segs[k]
        if s.w >= 1000
            groups[s.group] = s.w
            cost += 1.0
        else
            bgroups[s.group] = s.w
            bsegs += 1.0
            if !(s.group in crossed) && any(b -> _segbox(s.a, s.b, _grow(_shrink(b, inset), s.hw)), bs)
                push!(crossed, s.group)
            end
        end
    end
    cost += sum(values(groups); init = 0.0)
    cost += sum((D.obs[k].w for k in seeno); init = 0.0)
    return (hard = cost, base = sum(values(bgroups); init = 0.0), bsegs = bsegs, bcross = length(crossed))
end
_scost(t) = t.hard + t.base + t.bsegs

# The distance of label i at candidate c as it is seen: from its point to the nearest ink of the label.
_seen(D::_Drawing, i, c::_Cand) = minimum(_boxdist(D.anchors[i], b) for b in _boxes_at(D, i, c))

# What label i touches at candidate c, in words, for the flag.
function _touches(D::_Drawing, i, c::_Cand; clear = 1.0)
    out = String[]
    bs = _boxes_at(D, i, c)
    any(b -> b.x0 < 1 || b.x1 > D.w - 1 || b.y0 < 1 || b.y1 > D.h - 1, bs) && push!(out, "the axis edge")
    for b in bs
        bb = _grow(b, clear)
        for s in D.segs
            _segbox(s.a, s.b, _grow(bb, s.hw)) && push!(out, s.w >= 1000 ? "a data line" : "a base layer")
        end
        for o in D.obs
            _hit(bb, o.box) && push!(out, "a marker or text")
        end
    end
    return unique(out)
end

# Place the labels of the Text plot in each drawing of `ds` (one placement shared by all). Every label starts at its
# best candidate on its own; then, one move at a time, the label whose move to its best place given the others lowers
# its cost most moves (another label costs 1000), until no move lowers any; so where two labels contend for a place,
# the one that loses less by moving gives way (WP7a-2: a sweep in a fixed order moved the other one, out to 14 px
# farther, on 2.3's nine-warehouse map). Deterministic: no random number is drawn, and ties go to the first label and
# candidate in a fixed order.
#   prefer = :outward  the side `aligntext(x, y)` chooses from the points is preferred, 1.5 per 45 degrees away
#            :imhof    the cartographic order NE, NW, SW, SE, E, N, W, S, 1.5 a rank
#            :near     no side preferred, and no cost for sitting nearer another labeled point
#   maxgap   the ordinary search radius, in pixels; beyond it, out to 2maxgap, only at a steep cost per pixel, so only to
#            clear a data line, a marker or a label (each 1000), never a base layer
#   fix      label index => candidate: pinned, and no other label may take its place
#   inset    how far inside a label's ink boxes a base line reaches before it crosses the text (_INSET, 0 px)
# A base layer (WP7a-2: his review of WP7a's 5.2 maps, then the first revision's pictures): a label never moves
# farther from its point only to clear a base line that merely grazes it, and never takes a spot where a base line
# crosses its text to be nearer. Distance is measured as it is seen, from the point to the label's nearest ink
# (_seen). A candidate that grazes a base layer (touching only the `clear` margin around its ink boxes) and touches
# nothing else costs the base layer's 40 if some candidate clear of everything, or the candidate the label takes on
# the full costs, is as near as it or nearer; otherwise the graze costs only its segments, 1 each. So the rule only
# ever brings a label nearer. A crossing costs the 40 always, as a contact did before WP7a-2.
function _place(ds::Vector{_Drawing}; prefer = :outward, xy = nothing, maxgap = 30, fix = nothing,
                radii = [3, 5, 7, 9, 12, 15, 19, 24, 30, 38, 48, 60, 75, 95, 120, 150],
                clear = 2.0, wdist = 1.0, wside = 1.5, wlabel = 1000.0, maxpass = 50, wassoc = 30.0,
                fallback = 2maxgap, far = prefer === :near ? 60 : 20, grid = 1, keep = 6, gclear = 1.0,
                inset = _INSET)
    D1 = ds[1]
    n = length(D1.anchors)
    C = _candidates(filter(<=(min(fallback, maximum(radii))), radii))
    fixed = Dict{Int, Int}()
    if fix !== nothing
        for (i, (a, o)) in sort!(collect(fix); by = first)
            push!(C, _Cand(_dirof(a), (Float64(o[1]), Float64(o[2])), hypot(o...)))
            fixed[i] = length(C)
        end
    end
    K = length(C)
    # preference: distance, and the side
    pref = zeros(n, K)
    sidepref = if prefer === :outward && xy !== nothing
        al = Logjam.aligntext(xy[1], xy[2])
        A = n == 1 ? [al[1].second] : al[1].second
        [_dirof(a) === nothing ? 2 : _dirof(a) for a in A]
    else
        fill(0, n)
    end
    rankof(i, c) = prefer === :imhof ? _IMHOF[c.d] :
                   (sidepref[i] > 0 && c.d <= 8) ? (Δ = mod(c.d - sidepref[i], 8); min(Δ, 8 - Δ)) : 0
    for i in 1:n, (k, c) in enumerate(C)
        # close is better, and past `far` px a label stops reading as its point's: steeply worse
        pref[i, k] = wdist * (c.r - first(radii)) + 4wdist * max(c.r - far, 0) +
                     6wdist * max(c.r - maxgap, 0) + wside * rankof(i, c)
    end
    fk = Set(values(fixed))
    for i in 1:n, k in 1:K       # a pinned label has only its pin; no other label may take a pin
        if haskey(fixed, i)
            k == fixed[i] || (pref[i, k] = Inf)
        elseif k in fk
            pref[i, k] = Inf
        end
    end
    # association (Imhof: a name clearly tied to its feature): a label nearer another labeled point than its own
    # reads as that point's
    function assoc(i, c)
        (prefer === :near || n == 1) && return 0.0
        p = 0.0
        for D in ds
            bs = _boxes_at(D, i, c)
            di = minimum(_boxdist(D.anchors[i], b) for b in bs)
            dj = minimum((_boxdist(D.anchors[j], b) for j in 1:n if j != i for b in bs); init = Inf)
            dj < di + 2 && (p += wassoc)
        end
        return p
    end
    for i in 1:n, (k, c) in enumerate(C)
        isinf(pref[i, k]) || (pref[i, k] += assoc(i, c))
    end
    T = [[_static(D, i, C[k]; clear, inset) for D in ds] for i in 1:n, k in 1:K]
    S = [isinf(pref[i, k]) ? Inf : sum(_scost, T[i, k]) for i in 1:n, k in 1:K]
    K0 = K
    # The fine-grid fallback (the course's label_place.jl): a label none of whose candidates within maxgap is clear of
    # everything, base layers included, searches every offset on a `grid`-px lattice within maxgap, nearest first, ties
    # by angle, its alignment the quadrant it points into, and keeps the first `keep` that clear everything by the
    # course check's 1 px. Only then may it settle for touching a base layer.
    if grid > 0
        step = maxgap <= 30 ? grid : max(grid, round(Int, maxgap / 30))
        lattice = sort([(dx, dy) for dx in -maxgap:step:maxgap for dy in -maxgap:step:maxgap
                        if first(radii) <= hypot(dx, dy) <= maxgap];
                       by = v -> (hypot(v...), mod(atan(v[2], v[1]), 2pi)))
        extra = Tuple{Int, _Cand, Float64, Float64}[]
        for i in 1:n
            haskey(fixed, i) && continue
            any(k -> C[k].r <= maxgap && !isinf(pref[i, k]) && S[i, k] == 0, 1:K) && continue
            found = 0
            for (dx, dy) in lattice
                a = (dx > 2 ? :left : dx < -2 ? :right : :center, dy > 2 ? :bottom : dy < -2 ? :top : :center)
                c = _Cand(_dirof(a), (Float64(dx), Float64(dy)), hypot(dx, dy))
                s = sum(D -> _scost(_static(D, i, c; clear = gclear)), ds)
                s == 0 || continue
                p = wdist * (c.r - first(radii)) + 4wdist * max(c.r - far, 0) + wside * rankof(i, c) + assoc(i, c)
                push!(extra, (i, c, s, p))
                (found += 1) >= keep && break
            end
        end
        if !isempty(extra)
            m = length(extra)
            append!(C, [e[2] for e in extra])
            P2, S2 = fill(Inf, n, m), fill(Inf, n, m)
            for (col, (i, c, s, p)) in enumerate(extra)
                P2[i, col], S2[i, col] = p, s
            end
            pref, S = hcat(pref, P2), hcat(S, S2)
            K = length(C)
        end
    end
    # A grazing base layer is never cleared at the price of distance (WP7a-2): a candidate that grazes a base layer,
    # crosses none and touches nothing else costs only its base segments where that brings the label nearer, as seen,
    # than every candidate clear of everything and than the candidate it takes on the full costs. A crossing keeps its
    # 40, and a label already crossed on the full costs is not drawn farther out to a graze.
    for i in 1:n
        seen = [isinf(pref[i, k]) ? Inf : maximum(_seen(D, i, C[k]) for D in ds) for k in 1:K]
        nearest = minimum((seen[k] for k in 1:K if S[i, k] == 0); init = Inf)
        nearest = min(nearest, seen[argmin(view(S, i, :) .+ view(pref, i, :))])
        for k in 1:K0
            isinf(pref[i, k]) && continue
            ts = T[i, k]
            (all(t -> t.hard == 0 && t.bcross == 0, ts) && any(t -> t.base > 0, ts) && seen[k] < nearest) || continue
            S[i, k] = sum(t -> t.bsegs, ts)
        end
    end
    cost = S .+ pref
    choice = [argmin(view(cost, i, :)) for i in 1:n]
    cur(D, i) = _boxes_at(D, i, C[choice[i]])
    function overlapcost(i, k)
        t = 0.0
        for D in ds
            bi = [_grow(b, clear / 2) for b in _boxes_at(D, i, C[k])]
            for j in 1:n
                j == i && continue
                bj = cur(D, j)
                any(_hit(a, _grow(b, clear / 2)) for a in bi, b in bj) && (t += wlabel)
            end
        end
        return t
    end
    total(i, k) = cost[i, k] + overlapcost(i, k)
    for _ in 1:maxpass*n          # one move at a time, the one that lowers its label's cost most
        gain, bi, bk = 1e-9, 0, 0
        for i in 1:n
            t0 = total(i, choice[i])
            for k in 1:K
                cost[i, k] >= t0 - gain && continue
                g = t0 - total(i, k)
                g > gain && ((gain, bi, bk) = (g, i, k))
            end
        end
        bi == 0 && break
        choice[bi] = bk
    end
    align = [_DIRS[C[choice[i]].d] for i in 1:n]
    offset = [C[choice[i]].off for i in 1:n]
    # what each label still touches, so the author looks at those and only those
    flagged = @NamedTuple{label::Int, touches::Vector{String}, r::Float64}[]
    for i in 1:n
        c = C[choice[i]]
        w = unique(reduce(vcat, [_touches(D, i, c; clear = gclear) for D in ds]))
        overlapcost(i, choice[i]) > 0 && push!(w, "another label")
        c.r > maxgap && push!(w, "beyond $(maxgap) px")
        isempty(w) || push!(flagged, (label = i, touches = w, r = c.r))
    end
    return (; align, offset, flagged)
end

# =============================================================================
# aligntext(ax, x, y, labels; ...)
# =============================================================================
const _SIZE_KEYS = (:fontsize, :font, :lineheight, :justification, :rotation)

# `fix` as label index => (alignment, offset), each alignment one of the nine and each offset two finite numbers
function _fixindex(fix, labels)
    fix === nothing && return nothing
    out = Dict{Int, Tuple{Tuple{Symbol, Symbol}, NTuple{2, Float64}}}()
    for p in (fix isa Pair ? (fix,) : fix)
        p isa Pair || throw(ArgumentError("aligntext's `fix` holds pairs, label => (align, offset), as " *
                                          "\"Charlotte\" => ((:right, :center), (-12, 4)); got $(repr(p))"))
        k, v = p.first, p.second
        i = if k isa Integer
            1 <= k <= length(labels) || throw(ArgumentError("aligntext's `fix` names label $k, and there are $(length(labels))"))
            Int(k)
        else
            j = findfirst(l -> isequal(l, k) || string(l) == string(k), labels)
            j === nothing && throw(ArgumentError("aligntext's `fix` names $(repr(k)), which is not one of the labels"))
            j
        end
        haskey(out, i) && throw(ArgumentError("aligntext's `fix` pins label $i, $(repr(labels[i])), twice"))
        ok = v isa Union{Tuple, AbstractVector} && length(v) == 2 && _dirof(Tuple(v[1])) !== nothing &&
             length(v[2]) == 2 && all(o -> o isa Real && isfinite(o), v[2])
        ok || throw(ArgumentError("aligntext's `fix` pins a label at (align, offset): align one of " *
                                  "$(join(repr.(_DIRS), ", ")), offset two finite numbers in pixels; got $(repr(v))"))
        out[i] = (Tuple(v[1]), (Float64(v[2][1]), Float64(v[2][2])))
    end
    return out
end

# The placement and what it leaves flagged; `aligntext(ax, ...)` returns its `pairs`. Internal, so that a harness can
# read the flags without parsing the printed lines.
function _aligntext(ax::Makie.AbstractAxis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, labels::AbstractVector;
                    fontsize = nothing, font = nothing, lineheight = nothing, justification = nothing, rotation = nothing,
                    maxgap::Real = 30, fix = nothing, prefer::Symbol = :outward, verbose::Bool = false)
    ax isa Makie.Axis3 && throw(ArgumentError("aligntext places labels on a 2-D axis (an Axis or a GeoAxis), not an Axis3"))
    n = length(labels)
    (length(x) == n && length(y) == n) ||
        throw(ArgumentError("aligntext: x, y and labels have $(length(x)), $(length(y)) and $n elements; each needs one per label"))
    prefer in (:outward, :imhof, :near) ||
        throw(ArgumentError("aligntext's `prefer` is :outward, :imhof or :near; got $(repr(prefer))"))
    (isfinite(maxgap) && maxgap >= 3) ||
        throw(ArgumentError("aligntext's `maxgap` is a number of pixels, at least 3; got $(repr(maxgap))"))
    mg = round(Int, maxgap)
    kw = (; (k => v for (k, v) in zip(_SIZE_KEYS, (fontsize, font, lineheight, justification, rotation)) if v !== nothing)...)
    fixi = _fixindex(fix, labels)
    if n == 0
        align, offset = Tuple{Symbol, Symbol}[], NTuple{2, Float64}[]
        flagged = @NamedTuple{label::Int, touches::Vector{String}, r::Float64}[]
    else
        tmp = text!(ax, x, y; text = labels, align = fill((:left, :center), n), offset = fill((0.0, 0.0), n), kw...)
        r = try
            _place([_Drawing(ax, tmp)]; prefer, xy = (x, y), maxgap = mg, fix = fixi)
        finally
            delete!(ax, tmp)
        end
        align, offset, flagged = r.align, r.offset, r.flagged
    end
    if verbose               # a drafting aid, printed only when asked: one line per flagged label
        for u in flagged
            println("aligntext: label ", u.label, ", ", repr(string(labels[u.label])), ", at ", repr(align[u.label]), ", ",
                    repr(offset[u.label]), " touches ", join(u.touches, ", "))
        end
    end
    pairs = (:text => labels, :align => align, :offset => offset, (k => v for (k, v) in Base.pairs(kw))...)
    return (; pairs, align, offset, flagged)
end

function Logjam.aligntext(ax::Makie.AbstractAxis, x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, labels::AbstractVector;
                          fontsize = nothing, font = nothing, lineheight = nothing, justification = nothing,
                          rotation = nothing, maxgap::Real = 30, fix = nothing, prefer::Symbol = :outward,
                          verbose::Bool = false)
    return _aligntext(ax, x, y, labels; fontsize, font, lineheight, justification, rotation, maxgap, fix, prefer,
                      verbose).pairs
end

# =============================================================================
# plotroute! (D2): three methods, arrowheads on. Moved here from LogjamMapExt in v0.3.1's WP7b (MAP16), the drawing
# as it was: no GeoMakie call is made, so the arrows are placed and turned from the axis's own transform and limits,
# on a GeoAxis or a plain Axis alike, and CairoMakie alone draws them.
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
    state = Makie.Observable(_arrowheads(ax, legs, at))
    Makie.onany((_...) -> (state[] = _arrowheads(ax, legs, at)), ax.finallimits, ax.scene.viewport)
    return Makie.scatter!(ax, Makie.lift(first, state); marker = :rtriangle, markersize = size,
                          rotation = Makie.lift(last, state), color = color, space = :pixel, strokewidth = 0,
                          inspectable = false)
end

# the line and its arrowheads; `legs` already holds only the legs that get one
function _drawroute!(ax, x, y, legs; color, linewidth, linestyle, arrows, arrow_at, arrow_size)
    hl = Makie.lines!(ax, x, y; color = color, linewidth = linewidth, linestyle = linestyle)
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

# v0.3.0's bodies of the first two methods, as they were; the public methods below draw through them, the several-route
# method through the one-route body, and then place what they label.
function _route_xy!(ax, x, y; color, linewidth, linestyle, arrows, arrow_at, arrow_size, arrow_every)
    length(x) == length(y) || throw(ArgumentError("x and y must have the same length; got $(length(x)) and $(length(y))"))
    _checkarrows(arrow_at, arrow_every)
    return _drawroute!(ax, x, y, _xylegs(x, y, arrow_every); color, linewidth, linestyle, arrows, arrow_at, arrow_size)
end

function _route_rte!(ax, rte, sh, XY; tr, P, color, linewidth, linestyle, arrows, arrow_at, arrow_size, arrow_every)
    size(XY, 2) == 2 || throw(ArgumentError("XY must have two columns (LON, LAT), one row for each location; got $(size(XY, 2))"))
    loc = Int.(Logjam.rte2loc(rte, sh, something(tr, (;))))
    if P === nothing
        return _route_xy!(ax, XY[loc, 1], XY[loc, 2]; color, linewidth, linestyle, arrows, arrow_at, arrow_size, arrow_every)
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

# =============================================================================
# The stops' labels and the route numbers (WP7b; CR 50, CR 61), placed by aligntext(ax, ...) and placed again when a
# later plotroute! or plotshmt! call adds to the axis
# =============================================================================

# The label plots Logjam has placed in each axis, with what placed them, so that a later drawing call can place them
# again: (; tp, x, y, labels, kw), `kw` the keywords given to `_aligntext`. Keyed weakly by the axis, so an axis that is
# gone takes its entries with it; a label plot deleted from its axis is forgotten at the next call.
const _PLACED = WeakKeyDict{Any, Vector{Any}}()

# the stops' labels at aligntext's defaults; the route numbers in bold, nearest their centroids, with no side preferred,
# out to 150 px (review D's round three, and WP7a's label check of 5.2's loads map and 5.3's route maps)
const _NUMBER_KW = (; font = :bold, justification = :center, prefer = :near, maxgap = 150)

# Place the labels at (x, y) with aligntext(ax, ...), draw them, and remember them for _placeagain!.
function _placelabels!(ax, x, y, labels; color = nothing, kw...)
    q = _aligntext(ax, x, y, labels; kw...)
    tp = color === nothing ? text!(ax, x, y; q.pairs...) : text!(ax, x, y; color = color, q.pairs...)
    push!(get!(() -> Any[], _PLACED, ax), (; tp, x, y, labels, kw = NamedTuple(kw)))
    return tp
end

# Place again every label plot placed earlier in this axis, in the order they were placed, each against everything
# now drawn: the plot is hidden while aligntext(ax, ...) places its labels, so it is not its own obstacle. A no-op on
# an axis with none, so a call without labels draws what it drew at v0.3.0.
function _placeagain!(ax)
    ax isa Makie.AbstractAxis || return nothing
    recs = get(_PLACED, ax, nothing)
    recs === nothing && return nothing
    filter!(r -> any(p -> p === r.tp, ax.scene.plots), recs)
    for r in recs
        vis = r.tp.visible[]
        r.tp.visible[] = false
        q = try
            _aligntext(ax, r.x, r.y, r.labels; r.kw...)
        finally
            r.tp.visible[] = vis
        end
        r.tp.align[] = q.align
        r.tp.offset[] = q.offset
    end
    return nothing
end

# A stop's label (CR 50): its name, its loads (`ldlabel`), or its name over its loads, as Lectures 5.2 and 5.3's
# `citylabel` writes it (`City[i] * "\n" * ldlabel(i, sh)`); "" for a stop with neither, which gets no label.
function _stoplabel(i, sh, names, loads)
    nm = names === nothing ? "" : string(names[i])
    ld = loads ? Logjam.ldlabel(i, sh) : ""
    return isempty(nm) ? ld : isempty(ld) ? nm : nm * "\n" * ld
end

# names, loads and number are checked before anything is drawn
function _checklabels(ax, stops, names, who)
    ax isa Makie.AbstractAxis ||
        throw(ArgumentError("$who places its labels and numbers in an axis, an Axis or a GeoAxis; got a $(typeof(ax))"))
    if names !== nothing
        names isa AbstractVector || throw(ArgumentError("$who's `names` is a vector with a name for each location; got a $(typeof(names))"))
        for i in stops
            checkbounds(Bool, names, i) ||
                throw(ArgumentError("$who's `names` has $(length(names)) names and no name for location $i"))
        end
    end
    return nothing
end

function _numbertexts(number, n)
    number === true && return string.(1:n)
    (number isa AbstractVector && length(number) == n) && return string.(number)
    throw(ArgumentError("plotroute!'s `number` is false, true or one string for each of the $n routes; got $(repr(number))"))
end

# The stops' markers, then every label placed earlier in the axis placed again (each now sees the new lines and
# markers), then the stops' own labels; `stops` holds each location once.
function _stops!(ax, stops, sh, XY, names, loads)
    x, y = Float64.(XY[stops, 1]), Float64.(XY[stops, 2])
    hm = Makie.scatter!(ax, x, y; color = Makie.wong_colors()[1])
    _placeagain!(ax)
    txt = [_stoplabel(i, sh, names, loads) for i in stops]
    keep = findall(!isempty, txt)
    tp = _placelabels!(ax, x[keep], y[keep], txt[keep])
    return (; markers = hm, labels = tp)
end

# The truck's own locations, left out of a route's centroid
_trucklocs(tr) = tr === nothing ? Int[] : Int.(vcat(get(tr, :b, Int[]), get(tr, :e, Int[])))

# Each route's number at the centroid of its stops (CR 61): the locations of its location sequence, each as often as
# the route visits it, the truck's own left out (Matlog's pplot, Lecture 5.3's rtelabels!), in its route's color.
function _numbers!(ax, R, sh, XY, tr, txt, cols)
    tl = _trucklocs(tr)
    cx, cy = Float64[], Float64[]
    for (k, r) in enumerate(R)
        loc = Int.(Logjam.rte2loc(r, sh, something(tr, (;))))
        isempty(loc) && throw(ArgumentError("route $k visits no location, so it has no place for its number"))
        s = filter(l -> !(l in tl), loc)
        isempty(s) && (s = loc)
        push!(cx, sum(Float64(XY[l, 1]) for l in s) / length(s))
        push!(cy, sum(Float64(XY[l, 2]) for l in s) / length(s))
    end
    return _placelabels!(ax, cx, cy, txt; color = cols, _NUMBER_KW...)
end

# any sequence of locations
function Logjam.plotroute!(ax, x::AbstractVector{<:Real}, y::AbstractVector{<:Real};
                           color = :red, linewidth = 2, linestyle = :solid,
                           arrows::Bool = true, arrow_at::Real = 0.55, arrow_size::Real = 12, arrow_every::Integer = 1)
    h = _route_xy!(ax, x, y; color, linewidth, linestyle, arrows, arrow_at, arrow_size, arrow_every)
    _placeagain!(ax)
    return h
end

# one route: its location sequence (`rte2loc`), straight from stop to stop, or along the network by `P`; with `names`
# or `loads`, its stops marked and labeled
function Logjam.plotroute!(ax, rte::AbstractVector{<:Integer}, sh::AbstractDataFrame, XY::AbstractMatrix{<:Real};
                           tr = nothing, P = nothing, color = :red, linewidth = 2, linestyle = :solid,
                           arrows::Bool = true, arrow_at::Real = 0.55, arrow_size::Real = 12, arrow_every::Integer = 1,
                           names = nothing, loads::Bool = false)
    labeled = names !== nothing || loads
    if labeled
        size(XY, 2) == 2 || throw(ArgumentError("XY must have two columns (LON, LAT), one row for each location; got $(size(XY, 2))"))
        stops = unique(Int.(Logjam.rte2loc(rte, sh, something(tr, (;)))))
        _checklabels(ax, stops, names, "plotroute!")
    end
    h = _route_rte!(ax, rte, sh, XY; tr, P, color, linewidth, linestyle, arrows, arrow_at, arrow_size, arrow_every)
    labeled || (_placeagain!(ax); return h)
    return (; h..., _stops!(ax, stops, sh, XY, names, loads)...)
end

# several routes, one color each; with `names` or `loads` their stops marked and labeled, with `number` each route
# numbered at the centroid of its stops
function Logjam.plotroute!(ax, R::AbstractVector{<:AbstractVector{<:Integer}}, sh::AbstractDataFrame, XY::AbstractMatrix{<:Real};
                           tr = nothing, P = nothing, colors = Makie.wong_colors(), linewidth = 2, linestyle = :solid,
                           arrows::Bool = true, arrow_at::Real = 0.55, arrow_size::Real = 12, arrow_every::Integer = 1,
                           names = nothing, loads::Bool = false, number = false)
    labeled, numbered = names !== nothing || loads, number !== false
    if labeled || numbered
        size(XY, 2) == 2 || throw(ArgumentError("XY must have two columns (LON, LAT), one row for each location; got $(size(XY, 2))"))
        stops = unique(reduce(vcat, [Int.(Logjam.rte2loc(r, sh, something(tr, (;)))) for r in R]; init = Int[]))
        _checklabels(ax, stops, names, "plotroute!")
        txt = numbered ? _numbertexts(number, length(R)) : String[]
    end
    hs = [_route_rte!(ax, rte, sh, XY; tr, P, color = colors[mod1(i, length(colors))], linewidth, linestyle,
                      arrows, arrow_at, arrow_size, arrow_every) for (i, rte) in enumerate(R)]
    h = (; lines = [h.lines for h in hs], arrows = [h.arrows for h in hs])
    s = labeled ? _stops!(ax, stops, sh, XY, names, loads) : (_placeagain!(ax); (;))
    numbered || return (; h..., s...)
    cols = [colors[mod1(i, length(colors))] for i in eachindex(R)]
    return (; h..., s..., numbers = _numbers!(ax, R, sh, XY, tr, txt, cols))
end

# =============================================================================
# plotshmt! (D2, Matlog's plotshmt): each shipment from its origin to its destination, one arrowhead each
# =============================================================================

# Each shipment's polyline: straight, or bowed to the left of its direction of travel by `bend` times its length (a
# quadratic curve whose control point is that far from the middle of the chord, as Lecture 5.2's `curvepts` draws its
# schematics' shipments), in the data's own units.
function _shmtlegs(sh, XY, bend; n = 60)
    legs = Tuple{Vector{Float64}, Vector{Float64}}[]
    for (b, e) in zip(sh.b, sh.e)
        p = (Float64(XY[b, 1]), Float64(XY[b, 2]))
        q = (Float64(XY[e, 1]), Float64(XY[e, 2]))
        if bend == 0 || p == q
            push!(legs, ([p[1], q[1]], [p[2], q[2]]))
        else
            c = ((p[1] + q[1]) / 2 - bend * (q[2] - p[2]), (p[2] + q[2]) / 2 + bend * (q[1] - p[1]))
            t = range(0, 1, length = n)
            push!(legs, ([(1 - s)^2 * p[1] + 2(1 - s) * s * c[1] + s^2 * q[1] for s in t],
                         [(1 - s)^2 * p[2] + 2(1 - s) * s * c[2] + s^2 * q[2] for s in t]))
        end
    end
    return legs
end

function _checkshmt(sh, XY)
    size(XY, 2) == 2 || throw(ArgumentError("XY must have two columns (LON, LAT), one row for each location; got $(size(XY, 2))"))
    for c in (:b, :e)
        c in propertynames(sh) || throw(ArgumentError("sh must have the columns b and e, each shipment's origin and destination"))
        bad = findfirst(i -> !(1 <= i <= size(XY, 1)), sh[!, c])
        bad === nothing || throw(ArgumentError("shipment $bad's $c, $(sh[bad, c]), is not a row of XY (1 to $(size(XY, 1)))"))
    end
end

# the shipments as one line, each separated from the next by NaN, and one arrowhead on each that has a length
function _shmt!(ax, sh, XY; bend, color, linewidth, linestyle, arrows, arrow_at, arrow_size)
    _checkarrows(arrow_at, 1)
    legs = _shmtlegs(sh, XY, bend)
    lx = reduce(vcat, [[l[1]; NaN] for l in legs]; init = Float64[])
    ly = reduce(vcat, [[l[2]; NaN] for l in legs]; init = Float64[])
    heads = [l for l in legs if !(all(==(l[1][1]), l[1]) && all(==(l[2][1]), l[2]))]
    return _drawroute!(ax, lx, ly, heads; color, linewidth, linestyle, arrows, arrow_at, arrow_size)
end

# each location a shipment begins or ends at, once, origin before destination, shipment by shipment
_shmtstops(sh) = unique(reduce(vcat, [[b, e] for (b, e) in zip(sh.b, sh.e)]; init = Int[]))

function Logjam.plotshmt!(ax, sh::AbstractDataFrame, XY::AbstractMatrix{<:Real};
                          bend::Real = 0, color = :red, linewidth = 2, linestyle = :solid,
                          arrows::Bool = true, arrow_at::Real = 0.55, arrow_size::Real = 12,
                          names = nothing, loads::Bool = false)
    _checkshmt(sh, XY)
    isfinite(bend) || throw(ArgumentError("bend is a finite fraction of a shipment's length; got $bend"))
    labeled = names !== nothing || loads
    stops = _shmtstops(sh)
    labeled && _checklabels(ax, stops, names, "plotshmt!")
    h = _shmt!(ax, sh, XY; bend, color, linewidth, linestyle, arrows, arrow_at, arrow_size)
    labeled || (_placeagain!(ax); return h)
    return (; h..., _stops!(ax, stops, sh, XY, names, loads)...)
end

# Matlog's plotshmt(sh, XY, rte): a route of more than one shipment drawn as a route, the shipment of a single-shipment
# route as an independent shipment; with the truck's own locations every route is a route
function Logjam.plotshmt!(ax, sh::AbstractDataFrame, XY::AbstractMatrix{<:Real},
                          R::AbstractVector{<:AbstractVector{<:Integer}};
                          tr = nothing, color = :red, colors = Makie.wong_colors(), linewidth = 2, linestyle = :solid,
                          arrows::Bool = true, arrow_at::Real = 0.55, arrow_size::Real = 12, arrow_every::Integer = 1,
                          names = nothing, loads::Bool = false)
    _checkshmt(sh, XY)
    _checkarrows(arrow_at, arrow_every)
    istruck = tr !== nothing && (haskey(tr, :b) || haskey(tr, :e))
    asroute = [istruck ? !isempty(r) : length(r) > 2 for r in R]
    single = [r[1] for (k, r) in enumerate(R) if !asroute[k] && length(r) == 2]
    Rm = R[asroute]
    labeled = names !== nothing || loads
    if labeled
        seq = [asroute[k] ? Int.(Logjam.rte2loc(r, sh, something(tr, (;)))) : (length(r) == 2 ? [sh.b[r[1]], sh.e[r[1]]] : Int[])
               for (k, r) in enumerate(R)]
        stops = unique(reduce(vcat, seq; init = Int[]))
        _checklabels(ax, stops, names, "plotshmt!")
    end
    s = _shmt!(ax, sh[single, :], XY; bend = 0, color, linewidth, linestyle, arrows, arrow_at, arrow_size)
    hs = [_route_rte!(ax, r, sh, XY; tr, P = nothing, color = colors[mod1(i, length(colors))], linewidth, linestyle,
                      arrows, arrow_at, arrow_size, arrow_every) for (i, r) in enumerate(Rm)]
    h = (; lines = s.lines, arrows = s.arrows, routes = (; lines = [h.lines for h in hs], arrows = [h.arrows for h in hs]))
    labeled || (_placeagain!(ax); return h)
    return (; h..., _stops!(ax, stops, sh, XY, names, loads)...)
end

# =============================================================================
# The precompile workload (D12, WP8 of v0.3.1)
# =============================================================================
# The first call of aligntext(ax, ...), compiled once while the extension's package image is built: a figure of Makie's
# own with no backend (so no window and no file), a line and markers through four points, and their labels. The
# placement is discarded, so no output changes.
using PrecompileTools: @setup_workload, @compile_workload
@setup_workload begin
    x, y = [1.0, 2.0, 3.0, 4.0], [1.0, 2.5, 1.5, 3.0]
    labels = ["A", "B", "C", "D"]
    @compile_workload begin
        fig = Makie.Figure(size = (400, 300))
        ax = Makie.Axis(fig[1, 1])
        Makie.lines!(ax, x, y)
        Makie.scatter!(ax, x, y)
        Logjam.aligntext(ax, x, y, labels)
    end
end

end # module
