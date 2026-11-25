# test_map_tiers.jl -- makemap's road layer in the tiers of his answer to Q2 (PCV N4, CR 19; MakePlan D8; test spec SC 5,
# T5.1 to T5.6). `roads = :auto` draws, on the box as drawn:
#   close     150 miles across or less (S22's measure, tested first): the FAF5 network, every class 1 to 5, ramps by
#             name left out, five Lines (S22, S23; unchanged by N4: drawn from the derived network its density proxy
#             rose, so the stop rule holds it back for his ruling);
#   regional  otherwise, at most 10 degrees of latitude: Logjam's U.S. road network (usrdlink), classes 1 to 3, one Lines;
#   national  otherwise, at most 30 degrees: that network's INTERSTATE links, one Lines;
#   none      more than 30 degrees: nothing.
# Runs after test_map_pins.jl, test_map_line_pins.jl and test_map_k11c_pins.jl, whose expected values and moved-cases
# dicts T5.6 reads.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie

include(joinpath(@__DIR__, "k11c_pin_cases.jl"))       # includes map_pin_cases.jl: mmpin_describe, mmpin_cases, k11c_*

const _T5_EXT = Base.get_extension(Logjam, :LogjamMapExt)
const _T5_RGB = [0.275, 0.51, 0.706]                    # :steelblue
_t5_rgb(p) = (c = Makie.to_color(p.color[]); round.(Float64[Makie.Colors.red(c), Makie.Colors.green(c), Makie.Colors.blue(c)], digits = 3))
_t5_alpha(p) = Float64(p.alpha[]) * Float64(Makie.Colors.alpha(Makie.to_color(p.color[])))
_t5_plots(r) = r === nothing ? Any[] : r isa NamedTuple ? Any[p for p in values(r) if p !== nothing] : Any[r]

# an independent test of "the segment meets the box": an end inside, or a crossing of one of the four edges
function _t5_meets(a, b, box)
    (xmin, xmax), (ymin, ymax) = box
    inside(p) = xmin <= p[1] <= xmax && ymin <= p[2] <= ymax
    (inside(a) || inside(b)) && return true
    orient(p, q, r) = sign((q[1] - p[1]) * (r[2] - p[2]) - (q[2] - p[2]) * (r[1] - p[1]))
    onseg(p, q, r) = min(p[1], q[1]) <= r[1] <= max(p[1], q[1]) && min(p[2], q[2]) <= r[2] <= max(p[2], q[2])
    function cross(p1, p2, p3, p4)
        d1, d2, d3, d4 = orient(p3, p4, p1), orient(p3, p4, p2), orient(p1, p2, p3), orient(p1, p2, p4)
        d1 != d2 && d3 != d4 && return true
        (d1 == 0 && onseg(p3, p4, p1)) || (d2 == 0 && onseg(p3, p4, p2)) || (d3 == 0 && onseg(p1, p2, p3)) || (d4 == 0 && onseg(p1, p2, p4))
    end
    corners = ((xmin, ymin), (xmax, ymin), (xmax, ymax), (xmin, ymax))
    return any(cross(a, b, corners[i], corners[mod1(i + 1, 4)]) for i in 1:4)
end

# each link's two ends, as four vectors, and the links whose segment meets a box (a bounding-box test, then _t5_meets)
function _t5_ends(N, L)
    xy = Dict(N.IDX .=> zip(N.LON, N.LAT))
    a, b = [xy[s] for s in L.SRC], [xy[d] for d in L.DST]
    return (x1 = first.(a), y1 = last.(a), x2 = first.(b), y2 = last.(b))
end
function _t5_crop(e, box)
    (xmin, xmax), (ymin, ymax) = box
    return [i for i in eachindex(e.x1) if !(max(e.x1[i], e.x2[i]) < xmin || min(e.x1[i], e.x2[i]) > xmax ||
                                            max(e.y1[i], e.y2[i]) < ymin || min(e.y1[i], e.y2[i]) > ymax) &&
                                          _t5_meets((e.x1[i], e.y1[i]), (e.x2[i], e.y2[i]), box)]
end
_t5_seg(e, i) = ((e.x1[i], e.y1[i]), (e.x2[i], e.y2[i]))

# two limit pairs or extents equal to `rtol` (the pins' limits are rounded, their extents to 6 significant digits)
_t5_close(a, b; rtol) = all(isapprox(a[i][j], b[i][j]; rtol = rtol, atol = 0) for i in 1:2, j in 1:2)

# the drawn segments of a plot, each a two-point piece between NaN separators, with the width of its first point
function _t5_pieces(p)
    pts = p[1][]
    w = p.linewidth[]
    out = Tuple{NTuple{2, Float64}, NTuple{2, Float64}, Float64}[]
    @assert length(pts) % 3 == 0
    for i in 1:3:length(pts)
        a, b = pts[i], pts[i + 1]
        @assert isnan(pts[i + 2][1])
        push!(out, ((Float64(a[1]), Float64(a[2])), (Float64(b[1]), Float64(b[2])), Float64(w isa AbstractVector ? w[i] : w)))
    end
    return out
end

# ---- the density proxy (map spec, T5.5) ----------------------------------------------------------------------------
# The largest number of drawn segments meeting any 5-by-5-pixel cell of the axis's viewport (figure units): each segment,
# projected by the axis's own transform and clipped to the viewport (Liang and Barsky), is counted once in every cell it
# passes through (Amanatides and Woo's traversal).
function _t5_proxy(ax, plots; cs = 5.0)
    tf = Makie.transform_func(ax)
    fl = ax.finallimits[]
    o, wd = Makie.origin(fl), Makie.widths(fl)
    W, H = Float64.(Makie.widths(ax.scene.viewport[]))
    topix(x, y) = (p = Makie.apply_transform(tf, Makie.Point2d(x, y)); ((p[1] - o[1]) / wd[1] * W, (p[2] - o[2]) / wd[2] * H))
    nx, ny = max(1, ceil(Int, W / cs)), max(1, ceil(Int, H / cs))
    cnt = zeros(Int, nx, ny); last = zeros(Int, nx, ny)
    id = 0
    for p in plots
        pts = p[1][]
        for k in 1:length(pts)-1
            all(isfinite, (pts[k][1], pts[k][2], pts[k+1][1], pts[k+1][2])) || continue
            x0, y0 = topix(pts[k][1], pts[k][2]); x1, y1 = topix(pts[k+1][1], pts[k+1][2])
            dx, dy = x1 - x0, y1 - y0
            t0, t1, miss = 0.0, 1.0, false
            for (pp, q) in ((-dx, x0), (dx, W - x0), (-dy, y0), (dy, H - y0))
                if pp == 0
                    q < 0 && (miss = true)
                else
                    t = q / pp
                    if pp < 0
                        t > t1 && (miss = true); t > t0 && (t0 = t)
                    else
                        t < t0 && (miss = true); t < t1 && (t1 = t)
                    end
                end
            end
            miss && continue
            id += 1
            u0, v0, u1, v1 = (x0 + t0 * dx) / cs, (y0 + t0 * dy) / cs, (x0 + t1 * dx) / cs, (y0 + t1 * dy) / cs
            i, j = clamp(floor(Int, u0), 0, nx - 1), clamp(floor(Int, v0), 0, ny - 1)
            ie, je = clamp(floor(Int, u1), 0, nx - 1), clamp(floor(Int, v1), 0, ny - 1)
            du, dv = u1 - u0, v1 - v0
            si, sj = du > 0 ? 1 : -1, dv > 0 ? 1 : -1
            tx = du == 0 ? Inf : ((si > 0 ? i + 1 : i) - u0) / du
            ty = dv == 0 ? Inf : ((sj > 0 ? j + 1 : j) - v0) / dv
            dtx, dty = du == 0 ? Inf : si / du, dv == 0 ? Inf : sj / dv
            last[i+1, j+1] == id || (last[i+1, j+1] = id; cnt[i+1, j+1] += 1)
            for _ in 1:(abs(ie - i) + abs(je - j))
                tx < ty ? (i += si; tx += dtx) : (j += sj; ty += dty)
                (0 <= i < nx && 0 <= j < ny) || break
                last[i+1, j+1] == id || (last[i+1, j+1] = id; cnt[i+1, j+1] += 1)
            end
        end
    end
    return maximum(cnt)
end

# the boxes of the tier tests (D8's shapes): wide-and-short and narrow-and-tall, a hair under and over each boundary
_t5_tall_deg(span) = ((-79.0, -78.0), (20.0, 20.0 + span))
_t5_wide_deg(span) = ((-125.0, -65.0), (20.0, 20.0 + span))

const _T5_NC = ((-84.4, -75.4), (33.8, 36.6))          # North Carolina's box, 2.8 degrees of latitude
const _T5_NATIONAL = ((-100.0, -90.0), (30.0, 41.0))    # 11 degrees: the national tier's mid step

@testset "[N4] makemap's road layer in tiers (CR 19, Q2, D8)" begin
    N, L = usrdnode(), usrdlink()
    dE = _t5_ends(N, L)
    fN, fL = faf5nodes(), faf5links()
    fE = _t5_ends(fN, fL)
    tierclass(fc) = (fc <= 0 || fc >= 5) ? 5 : fc

    @testset "the tier of a box: the close test first, then 10 and 30 degrees of latitude" begin
        @test Logjam._MAP_REGIONAL_LATSPAN == 10.0 && Logjam._MAP_NATIONAL_LATSPAN == 30.0
        @test Logjam._maproadtier(((-79.2, -78.4), (35.5, 36.1))) === :close
        @test Logjam._maproadtier(k11c_wide(151.0)) === :regional                  # 0.2 degrees tall, but over 150 miles
        @test Logjam._maproadtier(_T5_NC) === :regional
        @test Logjam._maproadtier(_T5_NATIONAL) === :national
        @test Logjam._maproadtier(CUS_LIMITS) === :national
        @test Logjam._maproadtier(US_LIMITS) === :none && Logjam._maproadtier(WORLD_LIMITS) === :none
    end

    @testset "T5.1 each tier draws exactly its classes" begin
        # regional: every derived link of class 1 to 3 whose segment meets the box, in its class's width, and no other
        fig, ax, layers = makemap(_T5_NC)
        p = layers.roads
        @test p isa Makie.Lines && string(p.label[]) == "Interstate Roads"
        w1 = 0.6
        width = Dict(1 => w1, 2 => w1 / 1.4, 3 => w1 * 0.7 / 1.4)
        drawn = Set((a, b, k) for (a, b, w) in _t5_pieces(p) for k in 1:3 if isapprox(w, width[k]; rtol = 1e-6))
        @test all(pc -> count(k -> isapprox(pc[3], width[k]; rtol = 1e-6), 1:3) == 1, _t5_pieces(p))   # one class's width each
        want = Set((_t5_seg(dE, i)..., tierclass(L.FCLASS[i])) for i in _t5_crop(dE, _T5_NC) if tierclass(L.FCLASS[i]) <= 3)
        @test drawn == want
        @test all(k -> any(d -> d[3] == k, drawn), 1:3)                             # all three classes are in the state
        # national: every INTERSTATE link whose segment meets the box, and no other
        for box in (_T5_NATIONAL, CUS_LIMITS)
            fig, ax, layers = makemap(box)
            got = Set((a, b) for (a, b, w) in _t5_pieces(layers.roads))
            want = Set(_t5_seg(dE, i) for i in _t5_crop(dE, box) if L.INTERSTATE[i])
            @test got == want && !isempty(want)
        end
        # none: nothing above 30 degrees
        @test makemap(_t5_tall_deg(30.5)).layers.roads === nothing
        @test makemap(region = :US).layers.roads === nothing
        # close: the FAF5 network as S22 draws it (test_map_s22.jl checks the crop link by link), five classes
        fig, ax, layers = makemap(((-81.0, -80.7), (35.1, 35.35)))                # Charlotte, about 20 miles across
        @test layers.roads isa NamedTuple && keys(layers.roads) == (:class1, :class2, :class3, :class4, :class5)
        inbox = _t5_crop(fE, ax.limits[])
        for (k, name) in enumerate(keys(layers.roads))
            got = Set((a, b) for (a, b, w) in _t5_pieces(layers.roads[name]))
            want = Set(_t5_seg(fE, i) for i in inbox if tierclass(fL.FCLASS[i]) == k && !Logjam._isramp_v030(fL.NAME[i]))
            @test got == want
        end
    end

    @testset "T5.2 D8's boundary shapes: wide-and-short and narrow-and-tall, a hair under and over each line" begin
        shape(r) = r.layers.roads === nothing ? :none : r.layers.roads isa NamedTuple ? :close :
                   _t5_alpha(r.layers.roads) ≈ 0.2 ? :regional : :national
        for (box, want) in ((k11c_tall(149.0), :close), (k11c_tall(151.0), :regional), (k11c_wide(149.0), :close),
                            (k11c_wide(151.0), :regional),
                            (_t5_tall_deg(9.99), :regional), (_t5_tall_deg(10.01), :national),
                            (_t5_wide_deg(9.99), :regional), (_t5_wide_deg(10.01), :national),
                            (_t5_tall_deg(29.99), :national), (_t5_tall_deg(30.01), :none),
                            (_t5_wide_deg(29.99), :national), (_t5_wide_deg(30.01), :none))
            @testset "$box" begin
                @test Logjam._maproadtier(box) === want
                @test shape(makemap(box)) === want
            end
        end
        # the narrow boxes really are narrow and the wide ones wide
        @test Logjam._mapextent(_t5_tall_deg(9.99)) > 150 && Logjam._mapextent(_t5_wide_deg(9.99)) > 2000
    end

    @testset "T5.3 no ramp is drawn, on any tier" begin
        # regional and national: no drawn segment is a FAF5 link core's ramp rule names (name, X TO Y, C/D spellings and
        # the structural cluster test; D2), in either direction (the derived network has none: T2.1, test_faf5net.jl)
        ramp = Logjam._ramp_links(fN, fL)
        rampseg = Set{Tuple{NTuple{2, Float64}, NTuple{2, Float64}}}()
        for i in findall(ramp)
            a, b = _t5_seg(fE, i)
            push!(rampseg, (a, b), (b, a))
        end
        @test length(rampseg) > 270_000
        for box in (_T5_NC, ((-90.5, -75.5), (28.0, 37.0)), _T5_NATIONAL, CUS_LIMITS)
            got = [(a, b) for (a, b, w) in _t5_pieces(makemap(box).layers.roads)]
            @test !isempty(got) && !any(in(rampseg), got)
        end
        # close: no link v0.3.0's name rule calls a ramp (the close tier's own rule), with a control: the boxes hold them
        nramps = 0
        for box in (((-81.0, -80.7), (35.1, 35.35)), ((-84.55, -84.25), (33.65, 33.9)), ((-79.2, -78.4), (35.5, 36.1)))
            r = makemap(box)
            got = Set((a, b) for p in _t5_plots(r.layers.roads) for (a, b, w) in _t5_pieces(p))
            named = [_t5_seg(fE, i) for i in _t5_crop(fE, box) if Logjam._isramp_v030(fL.NAME[i])]
            nramps += length(named)
            @test !any(in(got), named)
        end
        @test nramps > 0
    end

    @testset "T5.4 the style: one hue, every stroke below 0.35, the classes by width, the Interstate on top" begin
        for (box, alpha, w1) in ((((-79.2, -78.4), (35.5, 36.1)), 0.3, 1.4), (_T5_NC, 0.2, 0.6), (_T5_NATIONAL, 0.25, 0.5),
                                 (CUS_LIMITS, 0.3, 0.3), (_t5_tall_deg(29.99), 0.3, 0.3))
            @testset "$box" begin
                fig, ax, layers = makemap(box)
                plots = _t5_plots(layers.roads)
                @test !isempty(plots)
                @test all(p -> _t5_rgb(p) == _T5_RGB, plots)
                @test all(p -> 0 < _t5_alpha(p) < 0.35, plots)
                @test all(p -> isapprox(_t5_alpha(p), alpha; atol = 1e-6), plots)
                @test maximum(p -> maximum(p.linewidth[]), plots) ≈ w1
            end
        end
        # regional: one Lines, a width for each point, the class 3 pieces first and the Interstate's last
        fig, ax, layers = makemap(_T5_NC)
        w = Float64.(layers.roads.linewidth[])
        @test w isa Vector && length(w) == length(layers.roads[1][]) && issorted(w)
        @test sort(unique(round.(w, digits = 4))) == round.([0.3, 0.6 / 1.4, 0.6], digits = 4)
        # national: one Lines, one width; close: five, as S22 (test_map_s22.jl)
        @test makemap(_T5_NATIONAL).layers.roads.linewidth[] isa Real
        @test makemap(((-79.2, -78.4), (35.5, 36.1))).layers.roads isa NamedTuple
        # an empty map of a tier is a Lines with nothing in it (Western Europe: no road of the network)
        r = makemap([2.0, 13.0], [48.0, 52.0])
        @test r.layers.roads isa Makie.Lines && isempty(r.layers.roads[1][]) && r.layers.roads.linewidth[] ≈ 0.6
        # roads = (; color, alpha, linewidth): the hue, the opacity, the Interstate's width (the other classes in ratio)
        r = makemap(_T5_NC; roads = (; color = :red, alpha = 0.5, linewidth = 2.0))
        @test _t5_rgb(r.layers.roads) == [1.0, 0.0, 0.0] && _t5_alpha(r.layers.roads) ≈ 0.5
        @test sort(unique(round.(Float64.(r.layers.roads.linewidth[]), digits = 4))) == round.([2.0 * 0.7 / 1.4, 2.0 / 1.4, 2.0], digits = 4)
        r = makemap(_T5_NATIONAL; roads = (; color = :red, alpha = 0.5, linewidth = 2.0))
        @test _t5_rgb(r.layers.roads) == [1.0, 0.0, 0.0] && _t5_alpha(r.layers.roads) ≈ 0.5 && r.layers.roads.linewidth[] == 2.0
        # roads = false draws nothing on every tier
        for box in (((-79.2, -78.4), (35.5, 36.1)), _T5_NC, _T5_NATIONAL)
            @test makemap(box; roads = false).layers.roads === nothing
        end
        # the link ends are read once for each tier and kept
        e = _T5_EXT._linkends(:regional)
        @test _T5_EXT._linkends(:regional) === e && _T5_EXT._linkends(:national) !== e
        @test issubset((:close, :regional, :national), keys(_T5_EXT._LINKENDS))
        @test length(e.x1) == count(<=(3), tierclass.(L.FCLASS)) && length(_T5_EXT._linkends(:national).x1) == count(L.INTERSTATE)
        # the FAF5 tables and the derived network's are read, not changed
        n, l = Logjam._usrdnodes(), Logjam._usrdlinks()
        before = (size(n), size(l), sum(n.LON), sum(l.DIST), sum(l.FCLASS))
        makemap(_T5_NC); makemap(CUS_LIMITS; roads = (; color = :red))
        @test (size(n), size(l), sum(n.LON), sum(l.DIST), sum(l.FCLASS)) == before
    end

    # T5.5: the density proxy of every reference picture of the map spec (N4's picture page): name => (call, tier, the
    # proxy before N4 (v0.3.0's layer), the proxy now). The close tier must not rise; it is v0.3.0's layer still, and the
    # "before" of each close picture is computed again here from the FAF5 tables, so the rule holds on whatever the close
    # tier draws. The regional and national values are a record: classes 2 and 3 add roads; one line for each divided
    # road removes the second carriageway. (Drawn from the derived network, the close tier's proxies were 21, 22, 21, 11,
    # 19, 21, 20, 23 and 27 in the order below: Charlotte, Atlanta and the 12-mile box rose, which is why it is not.)
    mm, kc, sy = Dict(mmpin_cases()), Dict(k11cpin_cases()), Dict(k11cpin_synthetic())
    T5_PICTURES = [
        "s22_dwt_clinics"      => (kc["dwt_clinics_0.25"], :close, 27, 27),
        "s22_triangle_nodes"   => (kc["triangle_node_box"], :close, 29, 29),
        "s22_tall_149"         => (sy["synthetic_tall_149"], :close, 37, 37),
        "s22_wide_149"         => (sy["synthetic_wide_149"], :close, 21, 21),
        "charlotte_20mi"       => (() -> makemap(((-81.0, -80.7), (35.1, 35.35))), :close, 13, 13),
        "atlanta_20mi"         => (() -> makemap(((-84.55, -84.25), (33.65, 33.9))), :close, 17, 17),
        "raleigh_durham_55mi"  => (() -> makemap(((-79.2, -78.4), (35.5, 36.1))), :close, 26, 26),
        "triangle_triad_120mi" => (() -> makemap(((-79.9, -77.9), (35.2, 36.4))), :close, 31, 31),
        "xy_both_expands"      => (mm["xy_both_expands"], :close, 16, 16),
        "s22_tall_151"         => (sy["synthetic_tall_151"], :regional, 8, 13),
        "s22_wide_151"         => (sy["synthetic_wide_151"], :regional, 8, 10),
        "north_carolina"       => (() -> makemap(_T5_NC), :regional, 67, 57),
        "southeast_9deg"       => (() -> makemap(((-90.5, -75.5), (28.0, 37.0))), :regional, 134, 144),
        "xy_default"           => (mm["xy_default"], :regional, 50, 33),
        "xy_xexpand_0.1"       => (mm["xy_xexpand_0.1"], :regional, 50, 33),
        "xy_xexpand_0.05"      => (mm["xy_xexpand_0.05"], :regional, 29, 29),
        "tuple_pair"           => (mm["tuple_pair"], :regional, 114, 322),
        "xy_hawaii_not_CUS"    => (mm["xy_hawaii_not_CUS"], :regional, 47, 69),
        "xy_outside_US"        => (mm["xy_outside_US"], :regional, 0, 0),
        "nc_cities_xe0.2"      => (kc["nc_cities_xe0.2"], :regional, 50, 32),
        "carolinas_xe0.1"      => (kc["carolinas_xe0.1"], :regional, 94, 69),
        "nc_counties_xe0.05"   => (kc["nc_counties_xe0.05"], :regional, 92, 66),
        "nc_counties_xe0.1"    => (kc["nc_counties_xe0.1"], :regional, 103, 64),
        "high_point_goldsboro" => (kc["high_point_goldsboro"], :regional, 23, 21),
        "region_CUS"           => (mm["region_CUS"], :national, 948, 296),
        "popco_xe0.04"         => (kc["popco_xe0.04"], :national, 468, 96),
        "popco_default"        => (kc["popco_default"], :national, 446, 105),
        "region_US"            => (mm["region_US"], :none, 0, 0),
        "region_World"         => (mm["region_World"], :none, 0, 0),
    ]

    @testset "T5.5 the density proxy of every reference picture, before and after; the close tier does not rise" begin
        for (name, (thunk, tier, before, after)) in T5_PICTURES
            @testset "$name" begin
                r = thunk()
                @test Logjam._maproadtier(r.ax.limits[]) === tier
                got = (p = _t5_plots(r.layers.roads); isempty(p) ? 0 : _t5_proxy(r.ax, p))
                @test got == after
                if tier === :close
                    # v0.3.0's layer, again: FAF5 links meeting the box, ramps by name left out, on this axis (hidden)
                    keep = [i for i in _t5_crop(fE, r.ax.limits[]) if !Logjam._isramp_v030(fL.NAME[i])]
                    x = reduce(vcat, [[fE.x1[i], fE.x2[i], NaN] for i in keep])
                    y = reduce(vcat, [[fE.y1[i], fE.y2[i], NaN] for i in keep])
                    b = _t5_proxy(r.ax, [lines!(r.ax, x, y; visible = false)])
                    @test b == before
                    @test got <= b
                end
            end
        end
    end

    @testset "T5.6 every moved map pin is listed with its reason; the rest of it holds, and its road layer is pinned anew" begin
        roadrow(l) = l[1] == "Interstate Roads"
        # test_map_pins.jl: the road layer as N4 draws it (label, points, opacity, the Interstate's width, style)
        N4_MMPIN = Dict(
            "xy_default"        => ("Interstate Roads", 9840, 0.2, 0.6, "solid"),
            "xy_xexpand_0.1"    => ("Interstate Roads", 8223, 0.2, 0.6, "solid"),
            "xy_xexpand_0.3"    => ("Interstate Roads", 9840, 0.2, 0.6, "solid"),
            "xy_xexpand_0.05"   => ("Interstate Roads", 7689, 0.2, 0.6, "solid"),
            "tuple_pair"        => ("Interstate Roads", 34692, 0.2, 0.6, "solid"),
            "region_CUS"        => ("Interstate Roads", 81408, 0.3, 0.3, "solid"),
            "xy_hawaii_not_CUS" => ("Interstate Roads", 876, 0.2, 0.6, "solid"),
            "xy_outside_US"     => ("Interstate Roads", 0, 0.2, 0.6, "solid"),
        )
        @test sort([k for (k, v) in MMPIN_MOVED if v == "N4"]) == sort(collect(keys(N4_MMPIN)))
        for (name, thunk) in mmpin_cases()
            @testset "map pin $name" begin
                fig, ax = thunk()
                got, want = mmpin_describe(fig, ax), MMPIN_EXPECTED[name]
                frame = got.size == want.size && _t5_close(got.limits, want.limits; rtol = 1e-12) &&
                        _t5_close(got.extent, want.extent; rtol = 1e-5)
                same = frame && got.layers == want.layers
                same || @test haskey(MMPIN_MOVED, name)                   # a case that differs is listed
                if get(MMPIN_MOVED, name, "") == "N4"
                    @test !same                                           # and a case listed under N4 differs
                    @test frame                                           # in its road layer alone
                    @test filter(!roadrow, got.layers) == filter(!roadrow, want.layers)
                    @test only(filter(roadrow, got.layers)) == N4_MMPIN[name]
                end
            end
        end
        # test_map_k11c_pins.jl
        N4_K11C = Dict(
            "nc_cities_default" => 9840, "nc_cities_xe0.2" => 9237, "carolinas_xe0.1" => 20967, "nc_counties_xe0.05" => 18216,
            "nc_counties_xe0.1" => 19071, "popco_xe0.04" => 19014, "popco_default" => 24753, "high_point_goldsboro" => 4059,
            "synthetic_tall_151" => 420, "synthetic_wide_151" => 441)
        @test sort([k for (k, v) in K11CPIN_MOVED if v == "N4"]) == sort(collect(keys(N4_K11C)))
        for (name, thunk) in vcat(k11cpin_cases(), k11cpin_synthetic())
            @testset "K11c pin $name" begin
                fig, ax = thunk()
                got, want = mmpin_describe(fig, ax).layers, K11CPIN_EXPECTED[name].layers
                got == want || @test haskey(K11CPIN_MOVED, name)
                if get(K11CPIN_MOVED, name, "") == "N4"
                    @test got != want
                    @test filter(!roadrow, got) == filter(!roadrow, want)
                    old = only(filter(roadrow, want))
                    @test only(filter(roadrow, got)) == (old[1], N4_K11C[name], old[3], old[4], old[5])   # only the points move
                end
            end
        end
        # test_map_line_pins.jl: the far step's opacity, 0.35 before, 0.3 now; nothing else
        @test sort([k for (k, v) in MLPIN_MOVED if v == "N4"]) == ["layers_CUS_map", "road_tier_20.5", "road_tier_29.99", "road_tier_30.0"]
        for (name, thunk, want) in MLPIN_LAYERS
            got = _mlpin_layers(thunk()[2])
            got == want || @test haskey(MLPIN_MOVED, "layers_" * name)
            if get(MLPIN_MOVED, "layers_" * name, "") == "N4"
                @test filter(!roadrow, got) == filter(!roadrow, want)
                old = only(filter(roadrow, want))
                @test old[2][4] == 0.35 && only(filter(roadrow, got)) == (old[1], [old[2][1:3]; 0.3], old[3], old[4], old[5])
            end
        end
        for (span, y0, want) in MLPIN_ROAD_TIERS
            fig, ax = makemap([-100.0, -90.0], [y0, y0 + span]; xexpand = 0, yexpand = 0)
            roads = [r for r in _mlpin_layers(ax) if r[1] == "Interstate Roads"]
            got = isempty(roads) ? nothing : (roads[1][2][4], roads[1][4])
            got == want || @test haskey(MLPIN_MOVED, "road_tier_$span")
            get(MLPIN_MOVED, "road_tier_$span", "") == "N4" && @test want == (0.35, 0.3) && got == (0.3, 0.3)
        end
    end
end
