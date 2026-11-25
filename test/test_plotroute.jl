# test_plotroute.jl -- plotroute!'s three methods, arrowheads on (PCV K11a, D2, P8).
# `plotroute!(ax, x, y)`, `plotroute!(ax, rte, sh, XY; tr, P)` and `plotroute!(ax, R, sh, XY; tr, P, colors)`
# replace the five methods of v0.2.8 (0 course calls) and their origin and destination markers.
#
# The arrowheads must point along the leg as drawn, so they are measured from the picture. A test draws the leg's
# two ends in colors of their own (magenta, orange) with `scatter!`, which Makie places itself, renders the figure,
# and compares the direction the red arrowhead points in with the direction from the magenta end to the orange one,
# on a plain Axis and on makemap's GeoAxis (Mercator), before and after a resize!. Synthetic routes and published
# data only: the NC cities of README Example 4 and its shipments.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie

const PR_TOL_DEG = 2.0       # a 50-pixel arrowhead's heading is measured to within about one degree

_pr_mean(v) = sum(v) / length(collect(v))

# ---- measuring a rendered figure ----------------------------------------------------------------------------------
_pr_isred(c) = c.r > 0.8 && c.g < 0.25 && c.b < 0.25
_pr_ismagenta(c) = c.r > 0.8 && c.b > 0.8 && c.g < 0.25
_pr_isorange(c) = c.r > 0.8 && 0.45 < c.g < 0.75 && c.b < 0.2

# the pixels a predicate picks, as their centroid (x to the right, y up the image) and their indices
function _pr_blob(img, pred)
    idx = findall(pred, img)
    isempty(idx) && return nothing
    return (_pr_mean(i[2] for i in idx), -_pr_mean(i[1] for i in idx), idx)
end

# the heading of a triangle-shaped blob: from its centroid to its farthest pixel (the tip), degrees
function _pr_heading(blob)
    cx, cy, idx = blob
    t = idx[argmax([hypot(i[2] - cx, -i[1] - cy) for i in idx])]
    return atand(-t[1] - cy, t[2] - cx)
end

_pr_img(fig) = collect(map(c -> CairoMakie.Makie.Colors.RGBA{Float64}(c), Makie.colorbuffer(fig)))
_pr_diff(a, b) = mod(a - b + 180, 360) - 180

# the arrowhead's heading against the leg's (magenta end to orange end), and where it sits along the leg
# (fraction of its length) and off it (pixels)
function _pr_measure(fig)
    img = _pr_img(fig)
    A, S, E = _pr_blob(img, _pr_isred), _pr_blob(img, _pr_ismagenta), _pr_blob(img, _pr_isorange)
    (A === nothing || S === nothing || E === nothing) && return nothing
    d = (E[1] - S[1], E[2] - S[2])
    L = hypot(d...)
    return (err = _pr_diff(_pr_heading(A), atand(d[2], d[1])),
            along = ((A[1] - S[1]) * d[1] + (A[2] - S[2]) * d[2]) / L^2,
            off = abs((A[1] - S[1]) * d[2] - (A[2] - S[2]) * d[1]) / L)
end

# a plain Axis or a makemap GeoAxis around a leg, its two ends marked in magenta and orange
function _pr_axis(kind, x, y)
    if kind == :axis
        fig = Figure(size = (600, 450))
        ax = Axis(fig[1, 1]; limits = ((minimum(x) - 1, maximum(x) + 1), (minimum(y) - 1, maximum(y) + 1)))
    else
        fig, ax = makemap(x, y; doRoadbkgd = false, xexpand = 0.3, yexpand = 0.3)
    end
    scatter!(ax, [x[1]], [y[1]]; color = :magenta, markersize = 14)
    scatter!(ax, [x[end]], [y[end]]; color = :orange, markersize = 14)
    return fig, ax
end

# the connected groups of pixels a predicate picks (8-neighbors): each is one drawn node
function _pr_groups(img, pred)
    todo, groups = Set(findall(pred, img)), Vector{CartesianIndex{2}}[]
    while !isempty(todo)
        seed = first(todo)
        delete!(todo, seed)
        group, queue = [seed], [seed]
        while !isempty(queue)
            c = pop!(queue)
            for dr in -1:1, dc in -1:1
                n = CartesianIndex(c[1] + dr, c[2] + dc)
                if n in todo
                    delete!(todo, n)
                    push!(group, n)
                    push!(queue, n)
                end
            end
        end
        push!(groups, group)
    end
    return [(_pr_mean(i[2] for i in g), -_pr_mean(i[1] for i in g)) for g in groups]
end

_pr_cities() = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())   # README Example 4
_pr_shipments() = DataFrame(b = [2, 3, 10, 7, 6], e = [8, 4, 1, 5, 9])                   # README Example 4

@testset "plotroute!: three methods, arrowheads on (D2)" begin
    cities = _pr_cities()
    XY = [cities.LON cities.LAT]
    sh = _pr_shipments()

    @testset "three methods, dispatched on what is passed" begin
        @test length(methods(plotroute!)) == 3
        fig, ax = makemap(cities.LON, cities.LAT; doRoadbkgd = false)
        h1 = plotroute!(ax, XY[1:4, 1], XY[1:4, 2])
        h2 = plotroute!(ax, [1, 2], sh, XY)                         # one route: a vector of shipment indices
        h3 = plotroute!(ax, [[1, 2], [3, 4, 5]], sh, XY)            # several routes
        @test h1 isa NamedTuple && h2 isa NamedTuple && h3 isa NamedTuple
        @test keys(h1) == (:lines, :arrows) && keys(h2) == (:lines, :arrows) && keys(h3) == (:lines, :arrows)
        @test h1.lines isa Lines && h1.arrows isa Scatter
        @test h2.lines isa Lines && h2.arrows isa Scatter
        @test h3.lines isa Vector && length(h3.lines) == 2 && all(l -> l isa Lines, h3.lines)
        @test h3.arrows isa Vector && length(h3.arrows) == 2 && all(a -> a isa Scatter, h3.arrows)
    end

    @testset "(ax, x, y): a leg for each pair of points, one arrowhead each, none for a leg of no length" begin
        fig, ax = makemap([-80.0, -76.0], [34.0, 37.0]; doRoadbkgd = false)
        x = [-79.0, -78.0, -78.0, -77.0, -76.5]            # the second leg has no length: a location visited twice
        y = [35.0, 36.0, 36.0, 36.5, 35.5]
        h = plotroute!(ax, x, y)
        @test length(h.arrows[1][]) == 3                      # four legs, one of them without length
        @test [(p[1], p[2]) for p in h.lines[1][]] == collect(zip(x, y))   # the line is the points as given
        # NaN separates routes: no leg across it
        hn = plotroute!(ax, [-79.0, -78.0, NaN, -77.0, -76.5], [35.0, 36.0, NaN, 36.5, 35.5])
        @test length(hn.arrows[1][]) == 2
        # arrow_every: the first leg and every arrow_every-th after it
        xe, ye = collect(range(-79, -76.5, length = 7)), [35.0, 36.0, 35.2, 36.1, 35.3, 36.2, 35.4]
        @test length(plotroute!(ax, xe, ye; arrow_every = 1).arrows[1][]) == 6
        @test length(plotroute!(ax, xe, ye; arrow_every = 2).arrows[1][]) == 3        # legs 1, 3 and 5 of 6
        @test length(plotroute!(ax, xe, ye; arrow_every = 6).arrows[1][]) == 1
        # arrows off, and the checks
        hoff = plotroute!(ax, x, y; arrows = false)
        @test hoff.arrows === nothing && hoff.lines isa Lines
        @test_throws ArgumentError plotroute!(ax, x, y; arrow_at = 1.5)
        @test_throws ArgumentError plotroute!(ax, x, y; arrow_every = 0)
        @test_throws ArgumentError plotroute!(ax, x, y[1:end-1])
    end

    @testset "arrowheads point along the leg as drawn, before and after a resize!" begin
        legs = (([-80.0, -78.0], [35.0, 36.5]), ([-78.0, -80.0], [36.5, 35.0]), ([-80.0, -78.0], [36.5, 35.0]),
                ([-100.0, -75.0], [30.0, 47.0]))
        worst, n = 0.0, 0
        for kind in (:axis, :geoaxis), (x, y) in legs
            fig, ax = _pr_axis(kind, x, y)
            h = plotroute!(ax, x, y; color = :red, arrow_size = 50)
            h.lines.visible[] = false                                  # the arrowhead alone is red
            for (w, ht) in ((600, 450), (900, 300), (300, 700))
                resize!(fig, w, ht)
                m = _pr_measure(fig)
                @test m !== nothing
                m === nothing && continue
                worst, n = max(worst, abs(m.err)), n + 1
                @test abs(m.err) < PR_TOL_DEG
                @test isapprox(m.along, 0.55; atol = 0.03)             # arrow_at = 0.55 of the way along
                @test m.off < 1.5                                      # and on the leg
            end
        end
        @info "plotroute!: worst arrowhead heading error $(round(worst, digits = 2)) degrees over $n drawings (tolerance $PR_TOL_DEG)"
    end

    @testset "the arrowheads are turned again when a resize! changes the leg's slope on the screen" begin
        fig, ax = _pr_axis(:axis, [-80.0, -78.0], [35.0, 36.5])
        h = plotroute!(ax, [-80.0, -78.0], [35.0, 36.5])
        resize!(fig, 600, 450)
        before = h.arrows.rotation[][1]
        resize!(fig, 900, 300)
        after = h.arrows.rotation[][1]
        @test after < before                                           # a wider, flatter axis lowers the angle
    end

    @testset "the line on a GeoAxis is drawn straight between its ends, where the arrowhead was measured" begin
        x, y = [-100.0, -75.0], [30.0, 47.0]
        fig, ax = _pr_axis(:geoaxis, x, y)
        h = plotroute!(ax, x, y; color = :red, arrows = false, linewidth = 2)
        img = _pr_img(fig)
        S, E, L = _pr_blob(img, _pr_ismagenta), _pr_blob(img, _pr_isorange), _pr_blob(img, _pr_isred)
        d = (E[1] - S[1], E[2] - S[2])
        offs = [abs((-i[1] - S[2]) * d[1] - (i[2] - S[1]) * d[2]) / hypot(d...) for i in L[3]]
        @test maximum(offs) < 3                                        # image pixels (2 per figure pixel) off the chord
    end

    @testset "(ax, rte, sh, XY): the route's location sequence through rte2loc, with the truck's ends when tr is given" begin
        fig, ax = makemap(cities.LON, cities.LAT; doRoadbkgd = false)
        rte = [1, 2, 3, 1, 4, 2, 5, 3, 4, 5]                            # each shipment's pickup, then its delivery
        loc = rte2loc(rte, sh)
        @test loc == [2, 3, 10, 8, 7, 4, 6, 1, 5, 9]
        h = plotroute!(ax, rte, sh, XY)
        @test [(p[1], p[2]) for p in h.lines[1][]] == [(XY[l, 1], XY[l, 2]) for l in loc]
        @test length(h.arrows[1][]) == length(loc) - 1
        # tr is read when present: the depot at both ends adds a leg at each
        tr = (b = [1], e = [1])
        loc_tr = rte2loc(rte, sh, tr)
        ht = plotroute!(ax, rte, sh, XY; tr = tr)
        @test length(ht.lines[1][]) == length(loc_tr) == length(loc) + 2
        @test length(ht.arrows[1][]) == length(loc_tr) - 1
        # a truck that leaves and returns to the depot with nothing between gets no arrowhead on a leg of no length
        h0 = plotroute!(ax, Int[], sh, XY; tr = (b = [2], e = [2]))
        @test length(h0.lines[1][]) == 2 && length(h0.arrows[1][]) == 0
        # XY must be n x 2
        @test_throws ArgumentError plotroute!(ax, rte, sh, [XY XY[:, 1]])
    end

    @testset "(ax, rte, sh, XY; P): each leg is traced along the network; the line is the concatenated tracepath nodes" begin
        # a small network of six nodes and the parent vectors shortestpaths returns for the first three (the stops)
        N = [-79.0 35.0; -78.6 35.9; -78.0 35.2; -78.4 36.3; -79.4 36.2; -77.8 36.0]
        P = [[0, 1, 2, 2, 4, 3],      # from 1: 2 <- 1, 3 <- 2, 4 <- 2, 5 <- 4, 6 <- 3
             [2, 0, 2, 2, 4, 3],      # from 2
             [2, 3, 0, 2, 4, 3]]      # from 3
        shp = DataFrame(b = [1, 3], e = [3, 1])
        rte = [1, 2, 1, 2]            # pickup of shipment 1 (at 1), of 2 (at 3), delivery of 1 (at 3), of 2 (at 1)
        loc = rte2loc(rte, shp)
        @test loc == [1, 3, 3, 1]
        fig, ax = makemap(N[:, 1], N[:, 2]; doRoadbkgd = false)
        h = plotroute!(ax, rte, shp, N; P = P)
        # C8 (PCV K11b): the line is tracepath(P, loc), in which a junction node is one node, not two as K11a drew it
        want = tracepath(P, loc)
        @test want == vcat([tracepath(P[loc[k]], loc[k], loc[k+1])[1:end-1] for k in 1:length(loc)-1]..., loc[end])
        got = [(p[1], p[2]) for p in h.lines[1][]]
        @test got == [(N[i, 1], N[i, 2]) for i in want]
        @test length(h.arrows[1][]) == 2                                 # the leg from 3 to 3 has no length
        # the traced leg 1 -> 5 runs 1, 2, 4, 5: the arrowhead points along the segment it sits on, measured from the picture
        fig2, ax2 = makemap(N[:, 1], N[:, 2]; doRoadbkgd = false, xexpand = 0.3, yexpand = 0.3)
        scatter!(ax2, N[:, 1], N[:, 2]; color = :magenta, markersize = 10)
        h2 = plotroute!(ax2, [1, 1], DataFrame(b = [1], e = [5]), N; P = P, color = :red, arrow_size = 50, arrow_at = 0.35)
        h2.lines.visible[] = false
        img = _pr_img(fig2)
        A = _pr_blob(img, _pr_isred)
        nodes = _pr_groups(img, _pr_ismagenta)
        @test length(nodes) == 6
        # which drawn node is which: Mercator keeps the order of longitudes (the six differ), so west to east
        order = sortperm(N[:, 1])                                       # node indices by longitude, west to east
        drawn = sort(nodes; by = first)                                 # the drawn blobs, left to right
        pos = Dict(order[k] => drawn[k] for k in eachindex(order))      # node => its center in the picture
        leg = [pos[i] for i in (1, 2, 4, 5)]
        seg = [hypot(leg[k+1][1] - leg[k][1], leg[k+1][2] - leg[k][2]) for k in 1:3]
        target, k = 0.35 * sum(seg), 1
        while k < 3 && target > seg[k]
            target -= seg[k]
            k += 1
        end
        @test A !== nothing
        @test abs(_pr_diff(_pr_heading(A), atand(leg[k+1][2] - leg[k][2], leg[k+1][1] - leg[k][1]))) < PR_TOL_DEG
    end

    @testset "(ax, R, sh, XY): one color a route, from colors" begin
        fig, ax = makemap(cities.LON, cities.LAT; doRoadbkgd = false)
        R = [[1, 1], [2, 2], [3, 3]]                                      # one shipment each
        h = plotroute!(ax, R, sh, XY)
        cols = Makie.to_color.(Makie.wong_colors()[1:3])
        @test [Makie.to_color(l.color[]) for l in h.lines] == cols
        @test [Makie.to_color(a.color[]) for a in h.arrows] == cols
        h2 = plotroute!(ax, R, sh, XY; colors = [:red, :blue], linewidth = 3, linestyle = :dash, arrow_every = 2)
        @test [Makie.to_color(l.color[]) for l in h2.lines] == Makie.to_color.([:red, :blue, :red])
        @test all(l -> l.linewidth[] == 3, h2.lines)
        # each route is the one-route method: the same arrowheads as plotting it alone
        solo = plotroute!(ax, R[2], sh, XY; color = :blue, arrow_every = 2)
        @test h2.arrows[2][1][] == solo.arrows[1][]
    end

    @testset "removed calls and keywords fail (D2, P8)" begin
        fig, ax = makemap(cities.LON, cities.LAT; doRoadbkgd = false)
        nodes = DataFrame(IDX = 1:10, LON = cities.LON, LAT = cities.LAT)
        P = [fill(0, 10) for _ in 1:10]
        rte = [1, 6, 2, 7]
        @test_throws MethodError plotroute!(ax, rte, sh, P, nodes)                        # v0.2.8's (ax, rte, sh, P, dfN)
        @test_throws MethodError plotroute!(ax, [rte, [3, 8]], sh, P, nodes)              # and its several-route form
        @test_throws MethodError plotroute!(ax, [1, 2, 3], nodes)                         # (ax, path, dfN)
        @test_throws MethodError plotroute!(ax, [[1, 2], [3, 4]], nodes)                  # (ax, paths, dfN)
        @test_throws MethodError plotroute!(ax, rte, sh, XY; show_markers = false)
        @test_throws MethodError plotroute!(ax, cities.LON[1:3], cities.LAT[1:3]; show_markers = false)
        @test_throws MethodError plotroute!(ax, cities.LON[1:3], cities.LAT[1:3]; markersize = 10)
        @test_throws MethodError plotroute!(ax, cities.LON[1:3], cities.LAT[1:3]; origin_color = :green)
        @test_throws MethodError plotroute!(ax, cities.LON[1:3], cities.LAT[1:3]; dest_color = :blue)
        @test !isdefined(Logjam, :_rte2lines)
    end
end
