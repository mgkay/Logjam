# test_LogjamMakieExt.jl -- the tests of ext/LogjamMakieExt.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it. A section marked
# "added by" was written after WP8, by the work package it names.

# ==== moved from test/test_aligntext_ax.jl, its lines 1-264 ====
# test_aligntext_ax.jl -- added by PCV WP7a of Logjam v0.3.1 (D1, MAP1): `aligntext(ax, x, y, labels; ...)`, the label
# placer that reads the drawn figure, in LogjamMakieExt (which Makie triggers, so CairoMakie alone loads it). Test spec
# Sec. 9. Synthetic figures only: the course's label check on review D's 16 lecture figures is a report
# (makeLogjam/plans/v0_3_1/measurements/wp7a/), not a test, and runs no lecture code here.
#   1. the return is the splat pairs for `text!`, in order, carrying back each size-setting keyword given; `text!` draws
#      them where they were placed, and the call leaves the axis as it was;
#   2. determinism: the same placement on two runs and with `verbose` on or off; no random number drawn; the default
#      prints nothing and `verbose = true` one line per flagged label;
#   3. what it reads: a data line through a point, the axis edge, another label; a label boxed in by data lines is
#      flagged, boxed in by base layers is flagged as touching a base layer only (MAP1: each of makemap's layer labels,
#      the close tier's unlabeled classes, a makemap's own layers);
#   4. `fix` by name, by index and as a Dict pins exactly, and the others are placed around a pin; `prefer` as
#      documented (:outward the side aligntext(x, y) chooses, :imhof northeast first, :near no side);
#   5. errors; an empty set of labels;
#   6. the declarations: aligntext(x, y) is core's and keeps its method, the axis method is the extension's, both
#      docstrings in core, the keywords listed, no ambiguity;
#   7. a fresh process: LogjamMakieExt loads with CairoMakie alone, without GeoMakie (so no LogjamMapExt), and places on
#      an Axis.

using Test
using Logjam
using CairoMakie
using GeoMakie        # for the one makemap case; every other figure here is a plain Axis
using Random

const _WP7A_MX = Base.get_extension(Logjam, :LogjamMakieExt)
const _WP7A_MK = CairoMakie.Makie

# a plain axis with fixed limits, its decorations hidden
function _wp7a_axis(; size = (400, 300), limits = (0, 10, 0, 10))
    fig = Figure(; size)
    ax = Axis(fig[1, 1]; limits)
    hidedecorations!(ax)
    return fig, ax
end

# what f prints, and its value
function _wp7a_capture(f)
    mktemp() do path, io
        v = redirect_stdout(f, io)
        flush(io)
        return v, read(path, String)
    end
end

# a dense grid of lines over the whole axis, about 6 px apart, so no label fits anywhere near a point
function _wp7a_grid!(ax; kw...)
    xs, ys = Float64[], Float64[]
    for v in 0:0.15:10
        append!(xs, [v, v, NaN]); append!(ys, [0, 10, NaN])
    end
    lines!(ax, xs, ys; kw...)
    xs, ys = Float64[], Float64[]
    for v in 0:0.2:10
        append!(xs, [0, 10, NaN]); append!(ys, [v, v, NaN])
    end
    lines!(ax, xs, ys; kw...)
end

@testset "WP7a (v0.3.1) aligntext(ax, x, y, labels): the label placer in LogjamMakieExt" begin
    @test _WP7A_MX !== nothing

    @testset "1. the return is the splat pairs for text!, and text! draws them where they were placed" begin
        fig, ax = _wp7a_axis()
        x, y = [2.0, 5.0, 8.0], [5.0, 6.0, 5.0]
        scatter!(ax, x, y)
        n0 = length(ax.scene.plots)
        r = aligntext(ax, x, y, ["West", "Middle", "East"]; fontsize = 14, font = :bold)
        @test length(ax.scene.plots) == n0                        # the temporary label plot is gone
        @test r isa Tuple && all(p -> p isa Pair{Symbol}, r)
        @test [p.first for p in r] == [:text, :align, :offset, :fontsize, :font]
        @test r[1].second == ["West", "Middle", "East"]
        @test r[2].second isa Vector{Tuple{Symbol, Symbol}} && length(r[2].second) == 3
        @test r[3].second isa Vector{NTuple{2, Float64}} && length(r[3].second) == 3
        @test r[4].second == 14 && r[5].second == :bold
        tp = text!(ax, x, y; color = :black, r...)                # color to text!, the rest from the splat
        @test tp isa _WP7A_MK.Text && length(ax.scene.plots) == n0 + 1
        @test [Tuple(_WP7A_MK.sv_getindex(tp.align[], i)) for i in 1:3] == r[2].second
        @test [(o = _WP7A_MK.sv_getindex(tp.offset[], i); (Float64(o[1]), Float64(o[2]))) for i in 1:3] == r[3].second  # Makie stores the offset as a 3-vector
        # with no size-setting keyword the splat is the three pairs alone; each one given comes back, in order
        r0 = aligntext(ax, x, y, ["a", "b", "c"])
        @test [p.first for p in r0] == [:text, :align, :offset]
        r5 = aligntext(ax, x, y, ["a", "b\nc", "d"]; fontsize = 12, font = :regular, lineheight = 1.1,
                       justification = :center, rotation = 0.0)
        @test [p.first for p in r5] == [:text, :align, :offset, :fontsize, :font, :lineheight, :justification, :rotation]
        @test [p.second for p in r5[4:end]] == [12, :regular, 1.1, :center, 0.0]
        # one label, and a two-line label, are placed and drawn
        r1 = aligntext(ax, [5.0], [2.0], ["Asheville\n(L2)"])
        @test length(r1[2].second) == 1 && text!(ax, [5.0], [2.0]; r1...) isa _WP7A_MK.Text
    end

    @testset "2. deterministic: two runs, verbose on or off, no random number drawn; verbose prints only flags" begin
        function make()
            fig, ax = _wp7a_axis()
            lines!(ax, [0.0, 10.0], [5.0, 5.0]; color = :red)     # a data line
            x, y = [2.0, 4.0, 6.0, 8.0, 5.0], [5.0, 6.0, 4.0, 5.0, 8.0]
            scatter!(ax, x, y)
            return fig, ax, x, y, ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
        end
        f1, a1, x, y, L = make()
        f2, a2, _, _, _ = make()
        r1, r2 = aligntext(a1, x, y, L), aligntext(a2, x, y, L)
        @test r1 == r2
        (rv, out), (rq, out0) = _wp7a_capture(() -> aligntext(a1, x, y, L; verbose = true)),
                                _wp7a_capture(() -> aligntext(a1, x, y, L))
        @test rv == rq == r1
        @test out0 == "" && out == ""                              # nothing flagged here, so nothing printed
        @test isempty(_WP7A_MX._aligntext(a1, x, y, L).flagged)
        Random.seed!(7); s = rand(3)
        Random.seed!(7); aligntext(a1, x, y, L); @test rand(3) == s
    end

    @testset "3. what it reads: a data line, the axis edge, another label; boxed in, flagged" begin
        # a data line through the point: the label sits above or below it, touching nothing
        fig, ax = _wp7a_axis()
        lines!(ax, [0.0, 10.0], [5.0, 5.0]; color = :red, linewidth = 1.5)
        q = _WP7A_MX._aligntext(ax, [5.0], [5.0], ["Alpha"])
        @test q.align[1][2] in (:bottom, :top) && isempty(q.flagged)
        # at the axis's right edge the label goes to the left of its point, inside the axis
        fig, ax = _wp7a_axis()
        q = _WP7A_MX._aligntext(ax, [9.7], [5.0], ["Rightmost"])
        @test q.align[1][1] === :right && isempty(q.flagged)
        # a label already drawn where this one would go (northeast, first under :imhof) is avoided
        fig, ax = _wp7a_axis()
        text!(ax, 5.0, 5.0; text = "XXXXXX", align = (:left, :bottom), offset = (3, 3))
        q = _WP7A_MX._aligntext(ax, [5.0], [5.0], ["Y"]; prefer = :imhof)
        @test q.align[1] != (:left, :bottom) && isempty(q.flagged)
        # boxed in by data lines: flagged, and verbose = true prints exactly one line, naming it
        fig, ax = _wp7a_axis()
        _wp7a_grid!(ax; color = :gray, linewidth = 0.5)
        q = _WP7A_MX._aligntext(ax, [5.0], [5.0], ["Boxed"])
        @test length(q.flagged) == 1 && q.flagged[1].label == 1 && "a data line" in q.flagged[1].touches
        (r, out) = _wp7a_capture(() -> aligntext(ax, [5.0], [5.0], ["Boxed"]; verbose = true))
        lines_out = split(chomp(out), '\n')
        @test length(lines_out) == 1 && occursin("\"Boxed\"", lines_out[1]) && occursin("a data line", lines_out[1])
        @test r[2].second == q.align && r[3].second == q.offset
        # boxed in by a base layer, under each of makemap's layer labels: touching a base layer, never a data line
        for name in ("FAF5 Roads", "Major Roads", "Interstate Roads", "US State Borders", "Country Borders")
            fig, ax = _wp7a_axis()
            _wp7a_grid!(ax; color = :gray, linewidth = 0.5, label = name)
            q = _WP7A_MX._aligntext(ax, [5.0], [5.0], ["Boxed"])
            @test length(q.flagged) == 1 && "a base layer" in q.flagged[1].touches && !("a data line" in q.flagged[1].touches)
        end
    end

    @testset "3. base layers (MAP1): the close tier's unlabeled classes, and a makemap's own layers" begin
        fig, ax = _wp7a_axis()
        c = (:steelblue, 0.5)
        lines!(ax, [0.0, 1.0], [0.0, 1.0]; color = :black)                    # data, another color
        lines!(ax, [0.0, 1.0], [0.0, 1.0]; color = c)                         # data: a plot between it and the layer
        lines!(ax, [0.0, 1.0], [1.0, 0.0]; color = :red)
        lines!(ax, [0.0, 1.0], [0.0, 1.0]; color = c)                         # class 3, unlabeled
        lines!(ax, [0.0, 1.0], [0.0, 1.0]; color = c)                         # class 2, unlabeled
        lines!(ax, [0.0, 1.0], [0.0, 1.0]; color = c, label = "FAF5 Roads")   # class 1, the heaviest, labeled
        lines!(ax, [0.0, 1.0], [0.0, 1.0]; color = c)                         # after it: data
        @test _WP7A_MX._basemask(ax.scene.plots) == [false, false, false, true, true, true, false]
        # makemap's layers, on a map 150 miles across or less with its roads opaque enough to be obstacles
        r = makemap([-78.9, -78.5], [35.7, 35.9]; roads = (; alpha = 0.5))
        layers = [p for p in (values(r.layers.roads)..., r.layers.states, r.layers.countries) if p !== nothing]
        @test length(layers) >= 2
        mask = _WP7A_MX._basemask(r.ax.scene.plots)
        @test all(mask[findfirst(q -> q === p, r.ax.scene.plots)] for p in layers)
        # and the placer runs on the GeoAxis
        x, y = [-78.8, -78.6], [35.75, 35.85]
        scatter!(r.ax, x, y)
        a = aligntext(r.ax, x, y, ["West", "East"]; fontsize = 12)
        @test length(a[2].second) == 2 && text!(r.ax, x, y; a...) isa _WP7A_MK.Text
    end

    @testset "4. fix pins exactly, by name, by index or as a Dict; the others are placed around a pin" begin
        fig, ax = _wp7a_axis()
        x, y = [2.0, 5.0, 8.0], [5.0, 5.0, 5.0]
        L = ["Alpha", "Beta", "Gamma"]
        r = aligntext(ax, x, y, L; fix = ["Beta" => ((:right, :top), (-6, -6))])
        @test r[2].second[2] == (:right, :top) && r[3].second[2] == (-6.0, -6.0)
        r = aligntext(ax, x, y, L; fix = [3 => ((:center, :bottom), (0, 9)), 1 => ((:left, :center), (7.5, 0))])
        @test r[2].second[[1, 3]] == [(:left, :center), (:center, :bottom)] && r[3].second[[1, 3]] == [(7.5, 0.0), (0.0, 9.0)]
        r = aligntext(ax, x, y, L; fix = Dict("Gamma" => ((:right, :center), (-5, 0))))
        @test r[2].second[3] == (:right, :center) && r[3].second[3] == (-5.0, 0.0)
        r = aligntext(ax, x, y, L; fix = "Alpha" => ((:left, :top), (4, -4)))     # a single pair
        @test r[2].second[1] == (:left, :top)
        # a long label pinned east of its point, toward the next point: the next point's label is placed clear of it
        fig, ax = _wp7a_axis()
        q = _WP7A_MX._aligntext(ax, [5.0, 6.0], [5.0, 5.0], ["AAAAAAAA", "B"];
                                fix = [1 => ((:left, :center), (6, 0))])
        @test q.align[1] == (:left, :center) && q.offset[1] == (6.0, 0.0)
        @test isempty(q.flagged)
    end

    @testset "4. prefer: :outward the side aligntext(x, y) chooses, :imhof northeast first, :near no side" begin
        fig, ax = _wp7a_axis()
        x, y = [2.0, 8.0, 8.0, 2.0], [2.0, 2.0, 8.0, 8.0]        # a square's corners, nothing drawn
        L = ["SW", "SE", "NE", "NW"]
        out = aligntext(ax, x, y, L)                              # :outward, the default
        @test out[2].second == [(:right, :top), (:left, :top), (:left, :bottom), (:right, :bottom)]
        @test out[2].second == aligntext(x, y)[1].second           # the side aligntext(x, y) chooses
        @test aligntext(ax, x, y, L; prefer = :outward) == out
        im = aligntext(ax, x, y, L; prefer = :imhof)
        @test all(==((:left, :bottom)), im[2].second)
        nr = aligntext(ax, x, y, L; prefer = :near)
        @test all(==((:left, :center)), nr[2].second) && all(==((3.0, 0.0)), nr[3].second)
    end

    @testset "5. errors, and an empty set of labels" begin
        fig, ax = _wp7a_axis()
        x, y, L = [2.0, 5.0, 8.0], [5.0, 5.0, 5.0], ["A", "B", "C"]
        @test_throws ArgumentError aligntext(ax, [2.0, 5.0], y, L)
        @test_throws ArgumentError aligntext(ax, x, y, L; prefer = :west)
        @test_throws ArgumentError aligntext(ax, x, y, L; maxgap = 0)
        @test_throws ArgumentError aligntext(ax, x, y, L; maxgap = Inf)
        @test_throws ArgumentError aligntext(ax, x, y, L; fix = ["D" => ((:left, :center), (0, 0))])
        @test_throws ArgumentError aligntext(ax, x, y, L; fix = [4 => ((:left, :center), (0, 0))])
        @test_throws ArgumentError aligntext(ax, x, y, L; fix = ["A" => ((:left, :baseline), (0, 0))])
        @test_throws ArgumentError aligntext(ax, x, y, L; fix = ["A" => ((:left, :center), (0, Inf))])
        @test_throws ArgumentError aligntext(ax, x, y, L; fix = ["A" => ((:left, :center), (0, 0)), 1 => ((:left, :top), (1, 1))])
        @test_throws ArgumentError aligntext(ax, x, y, L; fix = [(:left, :center)])
        @test_throws MethodError aligntext(ax, x, y, L; color = :red)       # color goes to text!
        @test_throws ArgumentError aligntext(Axis3(fig[1, 2]), x, y, L)
        n0 = length(ax.scene.plots)
        r = aligntext(ax, Float64[], Float64[], String[])
        @test r[2].second == Tuple{Symbol, Symbol}[] && r[3].second == NTuple{2, Float64}[] && length(ax.scene.plots) == n0
    end

    @testset "6. the declarations: aligntext(x, y) core's and unchanged in place, the axis method the extension's" begin
        @test length(methods(aligntext)) == 2
        @test which(aligntext, Tuple{Vector{Float64}, Vector{Float64}}).module === Logjam
        @test which(aligntext, Tuple{Axis, Vector{Float64}, Vector{Float64}, Vector{String}}).module === _WP7A_MX
        @test aligntext(0.0, 0.0) == (:align => (:left, :bottom), :offset => (1, 1))   # its doctest's value
        meta = Base.Docs.meta(Logjam)
        b = Base.Docs.Binding(Logjam, :aligntext)
        @test length(meta[b].order) == 2
        docs = [join(string.(meta[b].docs[s].text), "") for s in meta[b].order]
        @test startswith(docs[1], "    aligntext(x::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}},")
        @test startswith(docs[2], "    aligntext(ax, x, y, labels; fontsize, font, lineheight, justification, rotation, maxgap = 30,")
        @test isempty(Base.Docs.meta(_WP7A_MX))
        m = which(aligntext, Tuple{Axis, Vector{Float64}, Vector{Float64}, Vector{String}})
        @test Base.kwarg_decl(m) == [:fontsize, :font, :lineheight, :justification, :rotation, :maxgap, :fix, :prefer, :verbose]
        @test isempty(Test.detect_ambiguities(Logjam, _WP7A_MX))
    end
end

# ==== added by PCV WP7a-2 of Logjam v0.3.1 (his review of WP7a's 5.2 maps: keep a label beside its point) ====
# A label never moves farther from its point only to clear a base line that grazes it, and never takes a spot where a
# base line crosses its text to be nearer. The figure is Jacksonville's on 5.2's maps in miniature, in pixels (a
# 400 x 300 axis filling its figure): data lines on every side of the point but the northeast, and a base layer 12 px
# east of it, so on the northeast diagonal the line crosses the label's text out to 15 px, grazes it (touching only the
# 2 px clearance) at 19 px, and the only clear spot within `maxgap` is 24 px out. Synthetic: no lecture data.
function _wp7a2_coast(; base::Bool)
    fig = Figure(size = (400, 300), figure_padding = 0)
    ax = Axis(fig[1, 1]; limits = (0, 400, 0, 300))
    hidedecorations!(ax); hidespines!(ax)
    for q in ((0, 150), (200, 300), (200, 0), (50, 300), (50, 0), (350, 0))    # rays west, north, south, NW, SW, SE
        lines!(ax, [200.0, q[1]], [150.0, q[2]]; color = :red, linewidth = 1)
    end
    lines!(ax, [230.0, 400.0], [150.0, 150.0]; color = :red, linewidth = 1)  # a route east, beyond the coast
    kw = base ? (; label = "US State Borders") : (;)                          # unlabeled, it is a data line
    lines!(ax, [212.0, 212.0], [0.0, 300.0]; color = :blue, linewidth = 1, kw...)
    scatter!(ax, [200.0], [150.0]; markersize = 12)
    return fig, ax
end

@testset "WP7a-2 (v0.3.1) a label stays beside its point: a spot a base line grazes beats one it crosses nearer in and a clear one farther out" begin
    fig, ax = _wp7a2_coast(base = true)
    q = _WP7A_MX._aligntext(ax, [200.0], [150.0], ["Jacksonville"]; fontsize = 14)
    fig0, ax0 = _wp7a2_coast(base = false)
    q0 = _WP7A_MX._aligntext(ax0, [200.0], [150.0], ["Jacksonville"]; fontsize = 14)
    # the same line as a data line: the label goes out to the clear diagonal, 24 px, touching nothing
    @test q0.align == [(:left, :bottom)] && hypot(q0.offset[1]...) >= 24 && isempty(q0.flagged)
    # the three kinds of spot on the northeast diagonal: the line crosses the text at 7 and 15 px, grazes it at 19 px,
    # and the spot 24 px out is clear
    tp = text!(ax, [200.0], [150.0]; text = ["Jacksonville"], fontsize = 14, align = [(:left, :center)],
               offset = [(0.0, 0.0)])
    D = _WP7A_MX._Drawing(ax, tp)
    delete!(ax, tp)
    ne(r) = _WP7A_MX._static(D, 1, _WP7A_MX._Cand(2, (round(r * 0.7071; digits = 1), round(r * 0.7071; digits = 1)), r))
    @test all(t -> t.hard == 0 && t.base > 0 && t.bcross == 1, (ne(7.0), ne(15.0)))
    @test ne(19.0).hard == 0 && ne(19.0).base > 0 && ne(19.0).bcross == 0
    @test ne(24.0).hard == 0 && ne(24.0).base == 0
    # as a base layer: the spot it only grazes wins, nearer than the clear diagonal, and the spots nearer in, where the
    # line crosses the text, lose
    @test q.align == [(:left, :bottom)] && q.offset == [(13.4, 13.4)]
    @test all(u -> !("a data line" in u.touches), q.flagged)
    # nearer as seen, too: from the point to the label's nearest ink
    seen(ax, q) = (tp = text!(ax, [200.0], [150.0]; text = ["Jacksonville"], fontsize = 14, align = q.align,
                              offset = q.offset);
                   D = _WP7A_MX._Drawing(ax, tp);
                   c = _WP7A_MX._Cand(_WP7A_MX._dirof(q.align[1]), q.offset[1], hypot(q.offset[1]...));
                   s = _WP7A_MX._seen(D, 1, c); delete!(ax, tp); s)
    @test seen(ax, q) < seen(ax0, q0)
    # and the public call gives the same placement, deterministic
    r = aligntext(ax, [200.0], [150.0], ["Jacksonville"]; fontsize = 14)
    @test r[2].second == q.align && r[3].second == q.offset
end

@testset "WP7a (v0.3.1) a fresh process: LogjamMakieExt loads with CairoMakie alone, without GeoMakie" begin
    code = """
    using Logjam
    println("before=", Base.get_extension(Logjam, :LogjamMakieExt) !== nothing)
    using CairoMakie
    CairoMakie.activate!(visible = false)
    fig = Figure(size = (400, 300)); ax = Axis(fig[1, 1]; limits = (0, 10, 0, 10))
    x, y = [2.0, 8.0, 8.0, 2.0], [2.0, 2.0, 8.0, 8.0]
    r = aligntext(ax, x, y, ["SW", "SE", "NE", "NW"])
    tp = text!(ax, x, y; r...)
    println("makie=", Base.get_extension(Logjam, :LogjamMakieExt) !== nothing,
            " map=", Base.get_extension(Logjam, :LogjamMapExt) !== nothing,
            " geomakie=", isdefined(Main, :GeoMakie), " text=", tp isa CairoMakie.Makie.Text, " align=", r[2].second)
    """
    out = IOBuffer()
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
    ok = success(pipeline(cmd; stdout = out, stderr = out))
    s = String(take!(out))
    @test ok
    @test occursin("before=false", s)
    @test occursin("makie=true map=false geomakie=false text=true " *
                   "align=[(:right, :top), (:left, :top), (:left, :bottom), (:right, :bottom)]", s)
end

# ==== added by PCV WP7b of Logjam v0.3.1 (D2, MAP16, CR 50, CR 61): plotroute! in this extension, its stops and route
# numbers, and plotshmt! ====
# Test spec Sec. 11. Synthetic figures, and the lectures' own names and shipment tables for the label strings:
#   1. the declarations: plotroute!'s three methods and plotshmt!'s two are this extension's, each docstring in core,
#      the first method's keywords v0.3.0's (the course's logjam_kwargs reads them), no ambiguity; without names, loads
#      or number every return is v0.3.0's (; lines, arrows), and a v0.3.0 call draws the same lines and arrowheads on an
#      axis that holds Logjam's labels as on one that does not. The v0.3.0 pins themselves are test_LogjamMapExt.jl's
#      (with GeoMakie), unchanged; 6 below draws them on a plain Axis in a process with CairoMakie alone;
#   2. names and loads: a dot and a label at each stop, once, in the order the route first visits it; the text == Lectures
#      5.2's and 5.3's citylabel (copied as text), loads alone `ldlabel`, names alone the name; on a GeoAxis too;
#   3. number: one per route, `true` "1" to "n", strings as given, each in its route's color, anchored at the centroid of
#      its stops with the truck's locations left out;
#   4. Logjam's labels are placed again when a later plotroute! or plotshmt! call adds to the axis, and only then: the
#      placement aligntext(ax, ...) gives on the figure as it then stands; a label plot deleted is forgotten;
#   5. plotshmt!: one arrowhead per shipment on both methods; `bend` bows each shipment to the left of its travel; the
#      routes method draws a route of more than one shipment as a route and a single-shipment route as a shipment, and
#      with the truck's locations every route as a route; the checks;
#   6. a fresh process with CairoMakie alone (no GeoMakie, so no LogjamMapExt): every method draws, on a plain Axis,
#      exactly what it draws in this process with GeoMakie loaded.

using Test
using Logjam
using CairoMakie
using GeoMakie
using DataFrames

const _WP7B_MX = Base.get_extension(Logjam, :LogjamMakieExt)
const _WP7B_MK = CairoMakie.Makie

# Lectures 5.2's and 5.3's city labels, as text: the six cities (5-routing/5-rte-2.qmd:581-582), `ldlabel` (Code block
# 1, 5-rte-2.qmd:207-214) and `citylabel` (5-rte-2.qmd:641; 5-rte-3.qmd:1574 is the same line)
const _WP7B_CITYLABEL = raw"""
City = ["Raleigh", "Athens", "Asheville", "Jacksonville", "Savannah",
        "Gainesville"]
# the shipments loaded (L) and unloaded (U) at location i: (L1,2:U3)
function ldlabel(i, sh)
    L, U = findall(==(i), sh.b), findall(==(i), sh.e)
    parts = [isempty(L) ? "" : "L" * join(L, ","),
             isempty(U) ? "" : "U" * join(U, ",")]
    s = join(filter(!isempty, parts), ":")
    return isempty(s) ? "" : "($s)"
end
citylabel(i, sh) = City[i] * "\n" * ldlabel(i, sh)
"""
function _wp7b_citylabels()
    m = Module(:WP7bCity)
    Core.eval(m, :(using Logjam))
    Core.eval(m, :(using DataFrames))
    foreach(ex -> ex isa LineNumberNode || Core.eval(m, ex), Meta.parseall(_WP7B_CITYLABEL).args)
    return m
end
const _WP7B_LEC = _wp7b_citylabels()
_wp7b_city() = Base.invokelatest(getfield, _WP7B_LEC, :City)
_wp7b_citylabel(i, sh) = Base.invokelatest(getfield(_WP7B_LEC, :citylabel), i, sh)

# six locations on a plain axis, laid out as 5.2's cities lie (synthetic coordinates), and 5.2's shipments
const _WP7B_XY = [8.0 8.5; 3.0 5.0; 4.0 8.0; 6.0 1.5; 7.0 3.5; 5.0 0.8]
_wp7b_sh() = DataFrame(b = [1, 3, 5], e = [2, 4, 6])           # 5.2's Ex. 2 (5-rte-2.qmd:593)
_wp7b_shR() = DataFrame(b = ones(Int, 5), e = [2:6;])          # 5.2's shR (5-rte-2.qmd:1925)

function _wp7b_axis(; size = (500, 450), limits = (0, 10, 0, 10))
    fig = Figure(; size)
    ax = Axis(fig[1, 1]; limits)
    hidedecorations!(ax)
    return fig, ax
end
_wp7b_pts(p) = [(Float64(q[1]), Float64(q[2])) for q in p[1][]]
_wp7b_place(tp) = ([Tuple(_WP7B_MK.sv_getindex(tp.align[], i)) for i in eachindex(tp.input_text[])],
                   [(o = _WP7B_MK.sv_getindex(tp.offset[], i); (Float64(o[1]), Float64(o[2]))) for i in eachindex(tp.input_text[])])

@testset "WP7b (v0.3.1) plotroute! and plotshmt! in LogjamMakieExt: stops, route numbers, shipments" begin
    XY, City = _WP7B_XY, _wp7b_city()

    @testset "1. the declarations, and every call without the new keywords returns and draws what v0.3.0 did" begin
        @test length(methods(plotroute!)) == 3 && all(m -> m.module === _WP7B_MX, methods(plotroute!))
        @test length(methods(plotshmt!)) == 2 && all(m -> m.module === _WP7B_MX, methods(plotshmt!))
        @test parentmodule(ldlabel) === Logjam && length(methods(ldlabel)) == 2
        @test all(m -> m.module === Logjam, methods(ldlabel))
        meta = Base.Docs.meta(Logjam)
        for s in (:plotroute!, :plotshmt!, :ldlabel)
            @test haskey(meta, Base.Docs.Binding(Logjam, s))
        end
        @test isempty(Base.Docs.meta(_WP7B_MX))
        @test :plotshmt! in names(Logjam) && :ldlabel in names(Logjam)
        kw(T) = Base.kwarg_decl(which(plotroute!, T))
        @test Base.kwarg_decl(first(methods(plotroute!))) ==
              [:color, :linewidth, :linestyle, :arrows, :arrow_at, :arrow_size, :arrow_every]
        # (WP7c, D3, appends its keywords to this method's and to plotshmt!'s first method's lists below, as its brief
        # asks; WP7b's own keywords keep their places)
        @test kw(Tuple{Axis, Vector{Int}, DataFrame, Matrix{Float64}}) ==
              [:tr, :P, :color, :linewidth, :linestyle, :arrows, :arrow_at, :arrow_size, :arrow_every, :names, :loads,
               :bend, :bend_at, :node_numbers, :node_size, :label]
        @test kw(Tuple{Axis, Vector{Vector{Int}}, DataFrame, Matrix{Float64}}) ==
              [:tr, :P, :colors, :linewidth, :linestyle, :arrows, :arrow_at, :arrow_size, :arrow_every, :names, :loads, :number]
        @test Base.kwarg_decl(which(plotshmt!, Tuple{Axis, DataFrame, Matrix{Float64}})) ==
              [:bend, :color, :linewidth, :linestyle, :arrows, :arrow_at, :arrow_size, :names, :loads,
               :bend_at, :node_numbers, :node_size, :shmt_labels, :load_color, :load_font]
        @test Base.kwarg_decl(which(plotshmt!, Tuple{Axis, DataFrame, Matrix{Float64}, Vector{Vector{Int}}})) ==
              [:tr, :color, :colors, :linewidth, :linestyle, :arrows, :arrow_at, :arrow_size, :arrow_every, :names, :loads]
        @test isempty(Test.detect_ambiguities(Logjam, _WP7B_MX))
        # the returns without names, loads or number
        sh = _wp7b_sh()
        fig, ax = _wp7b_axis()
        @test keys(plotroute!(ax, XY[:, 1], XY[:, 2])) == (:lines, :arrows)
        @test keys(plotroute!(ax, [1, 2, 1, 3, 2, 3], sh, XY)) == (:lines, :arrows)
        @test keys(plotroute!(ax, [[1, 1], [2, 3, 2, 3]], sh, XY)) == (:lines, :arrows)
        @test keys(plotshmt!(ax, sh, XY)) == (:lines, :arrows)
        @test keys(plotshmt!(ax, sh, XY, [[1, 1], [2, 3, 2, 3]])) == (:lines, :arrows, :routes)
        # a v0.3.0 call draws the same on an axis that holds Logjam's labels as on one that does not
        function draw(labeled)
            fig, ax = _wp7b_axis()
            labeled && plotshmt!(ax, sh, XY; names = City, loads = true)
            h1 = plotroute!(ax, [1, 2, 1, 3, 2, 3], sh, XY; color = :green, arrow_at = 0.4)
            h3 = plotroute!(ax, [[1, 1], [2, 3, 2, 3]], sh, XY; arrow_every = 2)
            _WP7B_MK.update_state_before_display!(fig)
            return (_wp7b_pts(h1.lines), _wp7b_pts(h1.arrows), h1.arrows.rotation[],
                    [_wp7b_pts(l) for l in h3.lines], [_wp7b_pts(a) for a in h3.arrows])
        end
        @test draw(true) == draw(false)
    end

    @testset "2. names and loads: a dot and a label at each stop, once; the text is the lectures' citylabel" begin
        sh = _wp7b_sh()
        rte = [1, 2, 1, 3, 2, 3]
        stops = unique(rte2loc(rte, sh))
        @test stops == [1, 3, 2, 5, 4, 6]
        fig, ax = _wp7b_axis()
        h = plotroute!(ax, rte, sh, XY; names = City, loads = true)
        @test keys(h) == (:lines, :arrows, :markers, :labels)
        @test h.markers isa Scatter && _wp7b_pts(h.markers) == [(XY[i, 1], XY[i, 2]) for i in stops]
        @test h.labels isa _WP7B_MK.Text
        @test h.labels.input_text[] == [_wp7b_citylabel(i, sh) for i in stops]           # one per stop, 5.2's text
        @test _wp7b_pts(h.labels) == [(XY[i, 1], XY[i, 2]) for i in stops]
        # loads alone, names alone; a stop with nothing to show has no label (the truck's depot, here not a city with
        # a shipment); the truck's locations are stops
        h = plotroute!(ax, rte, sh, XY; loads = true)
        @test h.labels.input_text[] == [ldlabel(i, sh) for i in stops]
        h = plotroute!(ax, rte, sh, XY; names = City)
        @test h.labels.input_text[] == City[stops]
        tr = (b = [1], e = [1])
        shR = _wp7b_shR()
        r = [1, 2, 3, 4, 5, 1, 2, 3, 4, 5]
        h = plotroute!(ax, r, shR, XY; tr, names = City, loads = true)
        @test h.labels.input_text[] == [_wp7b_citylabel(i, shR) for i in unique(rte2loc(r, shR, tr))]
        @test first(h.labels.input_text[]) == "Raleigh\n(L1,2,3,4,5)"
        h = plotroute!(ax, [1, 1], DataFrame(b = [3], e = [4]), XY; tr = (b = [1], e = [1]), loads = true)
        @test h.labels.input_text[] == ["(L1)", "(U1)"] && length(h.markers[1][]) == 3   # the depot, 1, carries nothing
        # several routes: the stops of all, once
        R = [[1, 1], [2, 3, 2, 3]]
        h = plotroute!(ax, R, sh, XY; names = City, loads = true)
        @test keys(h) == (:lines, :arrows, :markers, :labels)
        @test h.labels.input_text[] == [_wp7b_citylabel(i, sh) for i in unique(reduce(vcat, rte2loc(R, sh)))]
        # names indexed by location, so a network's XY may have more rows than there are names
        @test_throws ArgumentError plotroute!(ax, rte, sh, XY; names = City[1:4])
        @test_throws ArgumentError plotroute!(ax, rte, sh, XY; names = "Raleigh")
        @test_throws ArgumentError plotroute!(Figure()[1, 1], rte, sh, XY; names = City)  # labels need an axis
        # on makemap's GeoAxis, with the lectures' own cities (5-rte-2.qmd:581-586)
        St = [:NC, :GA, :NC, :FL, :GA, :FL]
        loc = [loc2lonlat(c; state = s) for (c, s) in zip(City, St)]
        G = [[q.LON for q in loc] [q.LAT for q in loc]]
        fig, gax = makemap(G[:, 1], G[:, 2]; xexpand = 0.3, size = (600, 520))
        h = plotroute!(gax, rte, sh, G; names = City, loads = true)
        @test h.labels.input_text[] == [_wp7b_citylabel(i, sh) for i in stops] && length(h.labels.align[]) == 6
    end

    @testset "3. number: one per route, at the centroid of its stops, in its route's color" begin
        sh = _wp7b_sh()
        R = [[1, 2, 1, 2], [3, 3]]
        fig, ax = _wp7b_axis()
        h = plotroute!(ax, R, sh, XY; number = true)
        @test keys(h) == (:lines, :arrows, :numbers)
        @test h.numbers isa _WP7B_MK.Text && h.numbers.input_text[] == ["1", "2"]
        cen(loc) = (sum(XY[loc, 1]) / length(loc), sum(XY[loc, 2]) / length(loc))
        @test _wp7b_pts(h.numbers) == [cen([1, 3, 2, 4]), cen([5, 6])]
        @test _WP7B_MK.to_color.(h.numbers.color[]) == _WP7B_MK.to_color.(_WP7B_MK.wong_colors()[1:2])
        @test h.numbers.font[] == :bold && h.numbers.justification[] == :center
        h = plotroute!(ax, R, sh, XY; number = ["Route 1", "Route 2\n(Shmt 3)"], colors = [:green, :red])
        @test h.numbers.input_text[] == ["Route 1", "Route 2\n(Shmt 3)"]
        @test _WP7B_MK.to_color.(h.numbers.color[]) == _WP7B_MK.to_color.([:green, :red])
        # with the truck's locations, the depot is left out of the centroid; as often as the route visits a location
        tr = (b = [1], e = [1])
        h = plotroute!(ax, [[2, 2], [3, 3]], sh, XY; tr, number = true)
        @test _wp7b_pts(h.numbers) == [cen([3, 4]), cen([5, 6])]
        shR = _wp7b_shR()
        h = plotroute!(ax, [[1, 2, 1, 2]], shR, XY; number = true)                        # no truck: Raleigh counts twice
        @test _wp7b_pts(h.numbers) == [cen([1, 1, 2, 3])]
        # with names and loads too: labels first, then numbers
        h = plotroute!(ax, R, sh, XY; number = true, names = City, loads = true)
        @test keys(h) == (:lines, :arrows, :markers, :labels, :numbers)
        @test_throws ArgumentError plotroute!(ax, R, sh, XY; number = ["one"])
        @test_throws ArgumentError plotroute!(ax, R, sh, XY; number = :yes)
        @test_throws ArgumentError plotroute!(ax, [Int[]], sh, XY; number = true)          # nothing to number
    end

    @testset "4. Logjam's labels are placed again when a later Logjam call adds to the axis, and only then" begin
        # a shipment and its two ends' labels; then lines over the quadrant Alpha's label took, a plain Makie call first
        fig, ax = _wp7b_axis(size = (400, 300))
        sh = DataFrame(b = [1], e = [2])
        P = [5.0 5.0; 5.0 1.0]
        h = plotshmt!(ax, sh, P; names = ["Alpha", "Beta"])
        a0, o0 = _wp7b_place(h.labels)
        sx = a0[1][1] === :right ? (-1,) : a0[1][1] === :left ? (1,) : (-1, 1)        # west, east, or both
        sy = a0[1][2] === :top ? (-1,) : a0[1][2] === :bottom ? (1,) : (-1, 1)        # south, north, or both
        bx, by = Float64[], Float64[]
        for u in sx, v in sy, k in 1:12                            # horizontal strokes 0.1 apart over that quadrant
            append!(bx, [5.0 + u * 0.05, 5.0 + u * 2.0, NaN]); append!(by, fill(5.0 + v * (0.03 + 0.1k), 2)); push!(by, NaN)
        end
        lines!(ax, bx, by; color = :black)                         # not a Logjam call: nothing moves
        @test _wp7b_place(h.labels) == (a0, o0)
        plotroute!(ax, bx, by; color = :black, arrows = false)     # a Logjam call: Alpha moves, clear of every line
        a1, o1 = _wp7b_place(h.labels)
        @test (a1[1], o1[1]) != (a0[1], o0[1])
        # where it moved is what aligntext(ax, ...) gives on the figure as it now stands, the label plot hidden
        h.labels.visible[] = false
        q = _WP7B_MX._aligntext(ax, [5.0, 5.0], [5.0, 1.0], ["Alpha", "Beta"])
        h.labels.visible[] = true
        @test q.align == a1 && [Float32.(o) for o in q.offset] == [Float32.(o) for o in o1]   # Makie keeps offsets in Float32
        @test isempty(q.flagged)
        # deterministic: the same figure drawn again places the same
        fig2, ax2 = _wp7b_axis(size = (400, 300))
        h2 = plotshmt!(ax2, sh, P; names = ["Alpha", "Beta"])
        lines!(ax2, bx, by; color = :black)
        plotroute!(ax2, bx, by; color = :black, arrows = false)
        @test _wp7b_place(h2.labels) == (a1, o1)
        # route numbers are placed again too, and a label plot deleted is forgotten
        fig, ax = _wp7b_axis()
        s = _wp7b_sh()
        hn = plotroute!(ax, [[1, 2, 1, 2], [3, 3]], s, XY; number = true)
        hl = plotshmt!(ax, s, XY; names = City)
        @test length(_WP7B_MX._PLACED[ax]) == 2
        delete!(ax, hl.labels)
        plotroute!(ax, XY[[1, 6], 1], XY[[1, 6], 2])
        @test length(_WP7B_MX._PLACED[ax]) == 1 && _WP7B_MX._PLACED[ax][1].tp === hn.numbers
    end

    @testset "5. plotshmt!: one arrowhead per shipment, bowed by bend; the routes method" begin
        sh = DataFrame(b = [1, 3, 5, 2], e = [2, 4, 6, 2])                               # the last from 2 to 2
        fig, ax = _wp7b_axis()
        h = plotshmt!(ax, sh, XY)
        @test h.lines isa Lines && h.arrows isa Scatter
        @test length(h.arrows[1][]) == 3                                                 # none on the shipment of no length
        pts = _wp7b_pts(h.lines)
        @test length(pts) == 4 * 3                                                       # each two ends and a NaN
        @test pts[1:2] == [(XY[1, 1], XY[1, 2]), (XY[2, 1], XY[2, 2])] && all(isnan, pts[3])
        @test plotshmt!(ax, sh, XY; arrows = false).arrows === nothing
        # bend: each shipment a curve bowed to the left of its travel, its farthest point bend/2 of its length off the
        # chord (a quadratic curve's), the arrowhead on it
        for β in (0.25, -0.25)
            hb = plotshmt!(ax, sh[1:1, :], XY; bend = β)
            c = _wp7b_pts(hb.lines)[1:end-1]
            p, q = XY[1, :], XY[2, :]
            d = q .- p
            L = hypot(d...)
            off = [((x - p[1]) * d[2] - (y - p[2]) * d[1]) / L for (x, y) in c]           # right of travel is positive
            @test c[1] == (p[1], p[2]) && c[end] == (q[1], q[2]) && length(c) == 60
            @test isapprox(maximum(abs, off), abs(β) * L / 2; rtol = 1e-3)
            @test all(o -> sign(o) == -sign(β) || abs(o) < 1e-12, off)                   # bend > 0 bows left
            @test length(hb.arrows[1][]) == 1
        end
        # the routes method: a route of more than one shipment drawn as a route, a single-shipment route as a shipment
        s = _wp7b_sh()
        R = [[1, 2, 1, 2], [3, 3]]
        h = plotshmt!(ax, s, XY, R; colors = [:green])
        @test keys(h) == (:lines, :arrows, :routes)
        @test length(h.arrows[1][]) == 1 && _wp7b_pts(h.lines)[1:2] == [(XY[5, 1], XY[5, 2]), (XY[6, 1], XY[6, 2])]
        @test length(h.routes.lines) == 1 && length(h.routes.arrows[1][1][]) == 3
        @test _WP7B_MK.to_color(h.routes.lines[1].color[]) == _WP7B_MK.to_color(:green)
        # each single-shipment route as a shipment: one arrowhead per shipment
        h = plotshmt!(ax, s, XY, [[1, 1], [2, 2], [3, 3]])
        @test length(h.arrows[1][]) == 3 && isempty(h.routes.lines)
        # with the truck's locations, every route is a route
        h = plotshmt!(ax, s, XY, R; tr = (b = [1], e = [1]))
        @test length(h.routes.lines) == 2 && isempty(h.arrows[1][])
        # names and loads, as plotroute!'s
        h = plotshmt!(ax, s, XY; names = City, loads = true)
        @test keys(h) == (:lines, :arrows, :markers, :labels)
        @test h.labels.input_text[] == [_wp7b_citylabel(i, s) for i in [1, 2, 3, 4, 5, 6]]
        h = plotshmt!(ax, s, XY, R; loads = true)
        @test keys(h) == (:lines, :arrows, :routes, :markers, :labels)
        @test h.labels.input_text[] == [ldlabel(i, s) for i in [1, 3, 2, 4, 5, 6]]
        # the checks
        @test_throws ArgumentError plotshmt!(ax, s, [XY XY[:, 1]])
        @test_throws ArgumentError plotshmt!(ax, DataFrame(b = [1], e = [7]), XY)
        @test_throws ArgumentError plotshmt!(ax, DataFrame(o = [1], d = [2]), XY)
        @test_throws ArgumentError plotshmt!(ax, s, XY; arrow_at = 1.5)
        @test_throws ArgumentError plotshmt!(ax, s, XY; bend = Inf)
        @test_throws ArgumentError plotshmt!(ax, s, XY; names = City[1:3])
        @test_throws ArgumentError plotshmt!(ax, s, XY, R; arrow_every = 0)
    end
end

# 6. Each method drawn on a plain Axis of fixed size and limits, with every keyword, its plots read back as text. The
# same text in this process (GeoMakie loaded) and in a fresh process with CairoMakie alone.
const _WP7B_DRAW = raw"""
XY = [8.0 8.5; 3.0 5.0; 4.0 8.0; 6.0 1.5; 7.0 3.5; 5.0 0.8]
City = ["Raleigh", "Athens", "Asheville", "Jacksonville", "Savannah", "Gainesville"]
sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6])
N = [-79.0 35.0; -78.6 35.9; -78.0 35.2; -78.4 36.3; -79.4 36.2; -77.8 36.0]   # v0.3.0's traced-route network
P = [[0, 1, 2, 2, 4, 3], [2, 0, 2, 2, 4, 3], [2, 3, 0, 2, 4, 3]]
out = String[]
rec(n, p::Makie.Text) = push!(out, n * " text " * repr(p.input_text[]) * " " * repr(p.align[]) * " " * repr(p.offset[]))
rec(n, p::Makie.Lines) = push!(out, n * " lines " * repr([(q[1], q[2]) for q in p[1][]]))
rec(n, p::Makie.Scatter) = push!(out, n * " scatter " * repr([(q[1], q[2]) for q in p[1][]]) * " " * repr(p.rotation[]))
rec(n, ::Nothing) = push!(out, n * " nothing")
rec(n, v::AbstractVector) = foreach(((k, x),) -> rec("$n[$k]", x), enumerate(v))
rec(n, t::NamedTuple) = foreach(k -> rec("$n.$k", t[k]), keys(t))
fig = Figure(size = (500, 450)); ax = Axis(fig[1, 1]; limits = (0, 10, 0, 10)); hidedecorations!(ax)
fig2 = Figure(size = (500, 450)); ax2 = Axis(fig2[1, 1]; limits = (-80, -77, 34.5, 36.8)); hidedecorations!(ax2)
H = Any[]
push!(H, plotroute!(ax, XY[:, 1], XY[:, 2]; arrow_every = 2, arrow_size = 20))
push!(H, plotroute!(ax, [1.0, 2.0, NaN, 3.0, 3.0, 4.0], [1.0, 2.0, NaN, 2.0, 2.0, 1.0]; arrows = false))
push!(H, plotroute!(ax, [1, 2, 1, 3, 2, 3], sh, XY; color = :green, arrow_at = 0.4))
push!(H, plotroute!(ax, [1, 2, 3, 1, 2, 3], sh, XY; tr = (b = [1], e = [1]), linestyle = :dash))
push!(H, plotroute!(ax2, [1, 2, 1, 2], DataFrame(b = [1, 3], e = [3, 1]), N; P = P))
push!(H, plotroute!(ax, [[1, 1], [2, 3, 2, 3]], sh, XY; colors = [:red, :blue], linewidth = 3))
push!(H, plotshmt!(ax, sh, XY; bend = 0.2))
push!(H, plotshmt!(ax, sh, XY, [[1, 2, 1, 2], [3, 3]]))
push!(H, plotroute!(ax, [1, 2, 1, 3, 2, 3], sh, XY; names = City, loads = true))
push!(H, plotroute!(ax, [[1, 2, 1, 2], [3, 3]], sh, XY; number = ["Route 1", "Route 2\n(Shmt 3)"]))
push!(H, plotshmt!(ax, sh, XY; names = City))
Makie.update_state_before_display!(fig); Makie.update_state_before_display!(fig2)
foreach(((k, h),) -> rec("h$k", h), enumerate(H))
"""

@testset "WP7b (v0.3.1) a fresh process with CairoMakie alone: every method draws what it draws with GeoMakie loaded" begin
    m = Module(:WP7bDraw)
    for u in (:(using Logjam), :(using CairoMakie), :(using DataFrames), :(const Makie = CairoMakie.Makie))
        Core.eval(m, u)
    end
    foreach(ex -> ex isa LineNumberNode || Core.eval(m, ex), Meta.parseall(_WP7B_DRAW).args)
    here = Base.invokelatest(getfield, m, :out)
    @test length(here) > 30
    # first with Logjam and DataFrames alone: plotshmt! is a MethodError whose hint names the Makie extension
    code = "using Logjam, DataFrames; try plotshmt!(nothing, DataFrame(b = [1], e = [2]), [0.0 0.0; 1.0 1.0]) catch e; " *
           "println(\"WP7B hint \", typeof(e), \" \", occursin(\"needs the Makie extension, which CairoMakie loads\", " *
           "sprint(showerror, e))) end; " *
           "using CairoMakie; CairoMakie.activate!(visible = false); const Makie = CairoMakie.Makie; " *
           _WP7B_DRAW * """
           println("WP7B ext makie=", Base.get_extension(Logjam, :LogjamMakieExt) !== nothing,
                   " map=", Base.get_extension(Logjam, :LogjamMapExt) !== nothing, " geomakie=", isdefined(Main, :GeoMakie),
                   " module=", all(m -> m.module === Base.get_extension(Logjam, :LogjamMakieExt), methods(plotroute!)))
           foreach(l -> println("WP7B ", l), out)
           """
    buf = IOBuffer()
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
    ok = success(pipeline(cmd; stdout = buf, stderr = buf))
    s = String(take!(buf))
    @test ok
    @test occursin("WP7B hint MethodError true", s)
    @test occursin("WP7B ext makie=true map=false geomakie=false module=true", s)
    there = [l[6:end] for l in split(s, '\n') if startswith(l, "WP7B ") && !startswith(l, "WP7B ext") &&
                                                 !startswith(l, "WP7B hint")]
    @test there == here
    ok || println(s)
end

# ==== added by PCV WP7c of Logjam v0.3.1 (D3 of review D's round three): the schematics, in Matlog pplot's NumNode
# style, as keywords of plotshmt!'s first method and plotroute!'s one-route method ====
# Test spec Sec. 11 ("NumNode schematics"). Synthetic figures, and Lecture 5.2's own curve copied as text; the course's
# label check on 5.2's three schematics is a report (makeLogjam/plans/v0_3_1/measurements/wp7c/), not a test:
#   1. the declarations: the new keywords follow WP7b's (the lists are pinned in WP7b's testset 1 above), the other
#      methods keep theirs; without the new keywords a call draws what WP7b's code draws: a bowed shipment's points
#      == WP7b's own `_shmtlegs` (copied as text from c49c66c), and the schematic path given a `bend` vector of equal
#      values draws the same lines, arrowheads, dots and labels as the plain path given the number;
#   2. node_numbers: one white circle per location at `node_size` (22 by default), its number centered at 13 points;
#      one arrowhead per shipment, its tip on its destination's circle, no point of a line inside a circle; the cut
#      redone after a resize; `arrow_at` given, the arrowhead partway along;
#   3. bend and bend_at as vectors: each curve == Lecture 5.2's `curvepts` with Code block 24's control point (copied as
#      text), bowed on its own side, its farthest point where `bend_at` puts it; the checks;
#   4. shmt_labels: "Shmt k", the word given, one string each; upright, anchored on its curve between 10 and 90 percent of
#      it, clear of everything (the placement the placer gives, at a cost under 40); placed again when a later Logjam
#      call adds to the axis, and not by a plain Makie call;
#   5. plotroute!'s one route: `bend` for each leg, `node_numbers` (no node drawn twice, the legs cut at the nodes
#      already drawn, at their size), `label` along the most bowed leg, `arrow_every`; `names` and `loads` with nodes
#      (no dots), `load_color` and `load_font`; the checks.

const _WP7C_MX = Base.get_extension(Logjam, :LogjamMakieExt)
const _WP7C_MK = CairoMakie.Makie

# WP7b's `_shmtlegs` (ext/LogjamMakieExt.jl at c49c66c), as text: the curve a scalar `bend` draws
const _WP7C_WP7B_LEGS = raw"""
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
"""
# Lecture 5.2's curve (Code block 1, 5-routing/5-rte-2.qmd:135-136) and Code block 24's control point
# (5-rte-2.qmd:1350-1351), as text
const _WP7C_CURVEPTS = raw"""
curvepts(p, c, q; n = 60) = [(1 - s)^2 .* p .+ 2(1 - s) * s .* c .+
                             s^2 .* q for s in range(0, 1, length = n)]
function bowed(p, q, bulge, along)
    nk = [-(q[2] - p[2]), q[1] - p[1]] ./ hypot((q .- p)...)
    c = p .+ along .* (q .- p) .+ bulge .* nk
    return curvepts(p, c, q)
end
"""
function _wp7c_module(src)
    m = Module(:WP7cText)
    foreach(ex -> ex isa LineNumberNode || Core.eval(m, ex), Meta.parseall(src).args)
    return m
end
const _WP7C_WP7B = _wp7c_module(_WP7C_WP7B_LEGS)
const _WP7C_LEC = _wp7c_module(_WP7C_CURVEPTS)

function _wp7c_axis(; size = (500, 450), limits = (0, 10, 0, 10))
    fig = Figure(; size)
    ax = Axis(fig[1, 1]; limits)
    hidedecorations!(ax)
    return fig, ax
end
_wp7c_pts(p) = [(Float64(q[1]), Float64(q[2])) for q in p[1][]]
# a Lines' points split at its NaNs, one piece for each shipment or leg drawn
function _wp7c_pieces(p)
    out, cur = Vector{NTuple{2, Float64}}[], NTuple{2, Float64}[]
    for q in _wp7c_pts(p)
        if any(isnan, q)
            isempty(cur) || push!(out, cur)
            cur = NTuple{2, Float64}[]
        else
            push!(cur, q)
        end
    end
    isempty(cur) || push!(out, cur)
    return out
end
# the axis's own pixels of a data point, after the figure's layout
function _wp7c_pix(fig, ax)
    _WP7C_MK.update_state_before_display!(fig)
    f = _WP7C_MX._pixelmap(ax)
    return (x, y) -> (p = f(x, y); (Float64(p[1]), Float64(p[2])))
end
_wp7c_d(a, b) = hypot(a[1] - b[1], a[2] - b[2])
# each arrowhead's tip, in pixels: Makie's :rtriangle has its tip 0.485 of its size ahead of its center
_wp7c_tips(h; size = 12) = [(Float64(c[1]) + 0.485size * cos(r), Float64(c[2]) + 0.485size * sin(r))
                            for (c, r) in zip(h.arrows[1][], h.arrows.rotation[])]
function _wp7c_angle(r)
    r isa Real && return Float64(r)
    v = r * _WP7C_MK.Vec3f(1, 0, 0)
    return Float64(atan(v[2], v[1]))
end
# where a point lies along a polyline in pixels, as a fraction of its length, and how far from it
function _wp7c_along(P, x)
    L = [0.0; cumsum([_wp7c_d(P[k], P[k-1]) for k in 2:length(P)])]
    best, at = Inf, 0.0
    for k in 2:length(P)
        a, b = P[k-1], P[k]
        d2 = (b[1] - a[1])^2 + (b[2] - a[2])^2
        t = d2 == 0 ? 0.0 : clamp(((x[1] - a[1]) * (b[1] - a[1]) + (x[2] - a[2]) * (b[2] - a[2])) / d2, 0, 1)
        d = _wp7c_d(x, (a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2])))
        d < best && ((best, at) = (d, (L[k-1] + t * (L[k] - L[k-1])) / L[end]))
    end
    return at, best
end

@testset "WP7c (v0.3.1) the schematics: plotshmt! and plotroute! in pplot's NumNode style" begin
    XY, City = _WP7B_XY, _wp7b_city()
    sh = _wp7b_sh()

    @testset "1. the declarations; without the new keywords a call draws what WP7b's code draws" begin
        @test Base.kwarg_decl(first(methods(plotroute!))) ==
              [:color, :linewidth, :linestyle, :arrows, :arrow_at, :arrow_size, :arrow_every]      # v0.3.0's
        @test Base.kwarg_decl(which(plotroute!, Tuple{Axis, Vector{Vector{Int}}, DataFrame, Matrix{Float64}})) ==
              [:tr, :P, :colors, :linewidth, :linestyle, :arrows, :arrow_at, :arrow_size, :arrow_every, :names, :loads, :number]
        @test Base.kwarg_decl(which(plotshmt!, Tuple{Axis, DataFrame, Matrix{Float64}, Vector{Vector{Int}}})) ==
              [:tr, :color, :colors, :linewidth, :linestyle, :arrows, :arrow_at, :arrow_size, :arrow_every, :names, :loads]
        @test length(methods(plotroute!)) == 3 && length(methods(plotshmt!)) == 2
        @test isempty(Test.detect_ambiguities(Logjam, _WP7C_MX))
        # a scalar bend: the points WP7b's own code computes, bit for bit
        for β in (0.0, 0.2, -0.35, 1.0)
            fig, ax = _wp7c_axis()
            h = plotshmt!(ax, sh, XY; bend = β)
            want = Base.invokelatest(_WP7C_WP7B._shmtlegs, sh, XY, β)
            @test _wp7c_pieces(h.lines) == [collect(zip(l[1], l[2])) for l in want]
        end
        # the schematic path given a bend vector of equal values draws what the plain path draws given the number
        function draw(b)
            fig, ax = _wp7c_axis()
            h = plotshmt!(ax, sh, XY; bend = b, arrow_at = 0.4, names = City, loads = true)
            _WP7C_MK.update_state_before_display!(fig)
            return (keys(h), _wp7c_pts(h.lines), _wp7c_pts(h.arrows), h.arrows.rotation[], _wp7c_pts(h.markers),
                    h.labels.input_text[], h.labels.align[], h.labels.offset[])
        end
        @test isequal(draw(0.2), draw(fill(0.2, 3)))                       # isequal: the lines hold NaNs
        r1 = plotroute!(_wp7c_axis()[2], [1, 2, 1, 3, 2, 3], sh, XY)
        @test keys(r1) == (:lines, :arrows)
        @test keys(plotroute!(_wp7c_axis()[2], [1, 2, 1, 3, 2, 3], sh, XY; bend = 0, bend_at = 0.5)) == (:lines, :arrows)
    end

    @testset "2. node_numbers: a numbered circle per location, the curves cut at its edge, the tip on it" begin
        fig, ax = _wp7c_axis()
        h = plotshmt!(ax, sh, XY; bend = 0.15, node_numbers = true)
        @test keys(h) == (:lines, :arrows, :markers, :node_numbers)
        iscircle(m) = m === _WP7C_MK.Circle || m isa _WP7C_MK.Circle || (m isa Type && m <: _WP7C_MK.Circle)
        @test h.markers isa Scatter && iscircle(h.markers.marker[]) && all(==(22), h.markers.markersize[])
        @test _WP7C_MK.to_color(h.markers.color[]) == _WP7C_MK.to_color(:white) && h.markers.strokewidth[] == 1.5
        @test _wp7c_pts(h.markers) == [(XY[i, 1], XY[i, 2]) for i in 1:6]
        @test h.node_numbers isa _WP7C_MK.Text && h.node_numbers.input_text[] == string.(1:6)
        @test h.node_numbers.fontsize[] == 13 && h.node_numbers.align[] == (:center, :center)
        @test _wp7c_pts(h.node_numbers) == _wp7c_pts(h.markers)
        function cut_ok(fig, ax, h, sh, XY; r = 11.75, asize = 12)
            pix = _wp7c_pix(fig, ax)
            tips = _wp7c_tips(h; size = asize)
            ok = length(tips) == size(sh, 1)
            for (k, e) in enumerate(sh.e)
                ok &= isapprox(_wp7c_d(tips[k], pix(XY[e, 1], XY[e, 2])), r; atol = 1e-3)    # the tip on the circle
            end
            pieces = _wp7c_pieces(h.lines)
            ok &= length(pieces) == size(sh, 1)
            for (k, (b, e)) in enumerate(zip(sh.b, sh.e)), q in pieces[k]
                for i in (b, e)                                                           # no point inside a circle
                    ok &= _wp7c_d(pix(q...), pix(XY[i, 1], XY[i, 2])) >= r - 1e-6
                end
            end
            for (k, b) in enumerate(sh.b)                                                 # each piece begins on it
                ok &= isapprox(_wp7c_d(pix(pieces[k][1]...), pix(XY[b, 1], XY[b, 2])), r; atol = 1e-6)
            end
            return ok
        end
        @test cut_ok(fig, ax, h, sh, XY)
        resize!(fig, 700, 420)                                    # the cut and the tips follow the layout
        @test cut_ok(fig, ax, h, sh, XY)
        # node_size, and a larger arrowhead
        fig, ax = _wp7c_axis()
        h = plotshmt!(ax, sh, XY; node_numbers = true, node_size = 30, arrow_size = 16)
        @test all(==(30), h.markers.markersize[]) && cut_ok(fig, ax, h, sh, XY; r = 15.75, asize = 16)
        # arrow_at given: the arrowhead partway along, here halfway along a straight shipment, clear of both circles
        fig, ax = _wp7c_axis()
        h = plotshmt!(ax, sh, XY; node_numbers = true, arrow_at = 0.5)
        pix = _wp7c_pix(fig, ax)
        for (k, (b, e)) in enumerate(zip(sh.b, sh.e))
            c = h.arrows[1][][k]
            m = pix((XY[b, 1] + XY[e, 1]) / 2, (XY[b, 2] + XY[e, 2]) / 2)
            @test isapprox(Float64(c[1]), m[1]; atol = 1e-3) && isapprox(Float64(c[2]), m[2]; atol = 1e-3)
        end
        # a shipment from a location to itself: no line, no arrowhead, one node
        fig, ax = _wp7c_axis()
        h = plotshmt!(ax, DataFrame(b = [1, 2], e = [2, 2]), XY; node_numbers = true)
        @test length(h.arrows[1][]) == 1 && length(_wp7c_pieces(h.lines)) == 1 && h.node_numbers.input_text[] == ["1", "2"]
        # arrows = false; and an axis is needed
        @test plotshmt!(_wp7c_axis()[2], sh, XY; node_numbers = true, arrows = false).arrows === nothing
        @test_throws ArgumentError plotshmt!(Figure()[1, 1], sh, XY; node_numbers = true)
        @test_throws ArgumentError plotshmt!(_wp7c_axis()[2], sh, XY; node_numbers = true, node_size = 0)
    end

    @testset "3. bend and bend_at, one for each shipment: Lecture 5.2's curve, each on its own side" begin
        fig, ax = _wp7c_axis()
        β, α = [0.25, -0.2, 0.0], [0.5, 0.8, 0.9]
        h = plotshmt!(ax, sh, XY; bend = β, bend_at = α)
        pieces = _wp7c_pieces(h.lines)
        @test length(pieces) == 3 && length(pieces[1]) == 60 && length(pieces[2]) == 60 && length(pieces[3]) == 2
        @test length(h.arrows[1][]) == 3
        for k in 1:3
            p, q = XY[sh.b[k], :], XY[sh.e[k], :]
            L = hypot((q .- p)...)
            if β[k] != 0
                want = Base.invokelatest(_WP7C_LEC.bowed, p, q, β[k] * L, α[k])     # 5.2's bulge is in data units
                @test all(isapprox(collect(a), b; rtol = 1e-12, atol = 1e-12) for (a, b) in zip(pieces[k], want))
            end
            d = q .- p
            off = [((x - p[1]) * d[2] - (y - p[2]) * d[1]) / L for (x, y) in pieces[k]]  # right of travel is positive
            if β[k] == 0
                @test all(o -> abs(o) < 1e-12, off)
            else
                @test isapprox(maximum(abs, off), abs(β[k]) * L / 2; rtol = 1e-3)
                @test all(o -> sign(o) == -sign(β[k]) || abs(o) < 1e-12, off)
                # the farthest point lies (1 + 2 bend_at) / 4 of the way along the chord
                j = argmax(abs.(off))
                along = ((pieces[k][j][1] - p[1]) * d[1] + (pieces[k][j][2] - p[2]) * d[2]) / L^2
                @test isapprox(along, (1 + 2α[k]) / 4; atol = 0.02)
            end
        end
        # with node_numbers too, the vectors are taken shipment by shipment
        h = plotshmt!(_wp7c_axis()[2], sh, XY; bend = β, bend_at = α, node_numbers = true)
        @test length(h.arrows[1][]) == 3 && length(_wp7c_pieces(h.lines)) == 3
        # the checks
        ax = _wp7c_axis()[2]
        @test_throws ArgumentError plotshmt!(ax, sh, XY; bend = [0.1, 0.2])
        @test_throws ArgumentError plotshmt!(ax, sh, XY; bend = [0.1, Inf, 0.0])
        @test_throws ArgumentError plotshmt!(ax, sh, XY; bend_at = 1.5)
        @test_throws ArgumentError plotshmt!(ax, sh, XY; bend_at = [0.5, 0.5])
        @test_throws ArgumentError plotshmt!(ax, sh, XY; bend = [0.1, 0.1, 0.1], arrow_at = 2)
    end

    @testset "4. shmt_labels: along each curve, upright, clear, and placed again by a later Logjam call" begin
        fig, ax = _wp7c_axis()
        h = plotshmt!(ax, sh, XY; bend = 0.2, shmt_labels = true)
        @test keys(h) == (:lines, :arrows, :shmt_labels)
        tp = h.shmt_labels
        @test tp isa _WP7C_MK.Text && tp.input_text[] == ["Shmt 1", "Shmt 2", "Shmt 3"]
        @test _WP7C_MK.to_color(tp.color[]) == _WP7C_MK.to_color(:red) && tp.fontsize[] == 13
        @test plotshmt!(_wp7c_axis()[2], sh, XY; shmt_labels = "Shipment").shmt_labels.input_text[] ==
              ["Shipment 1", "Shipment 2", "Shipment 3"]
        @test plotshmt!(_wp7c_axis()[2], sh, XY; shmt_labels = ["a", "b", "c"]).shmt_labels.input_text[] == ["a", "b", "c"]
        pix = _wp7c_pix(fig, ax)
        pieces = _wp7c_pieces(h.lines)
        for k in 1:3
            φ = _wp7c_angle(_WP7C_MK.sv_getindex(tp.rotation[], k))
            @test abs(φ) <= pi / 2 + 1e-9                                                    # upright
            at, dist = _wp7c_along([pix(q...) for q in pieces[k]], pix(_wp7c_pts(tp)[k]...))
            @test dist < 1e-3 && 0.1 - 1e-9 <= at <= 0.9 + 1e-9                            # on its curve, 10 to 90 percent
        end
        # clear of everything: the placement the placer gives on the figure as it stands, the label hidden, costs under 40
        rec = only(r for r in _WP7C_MX._PLACED[ax] if r.tp === tp)
        tp.visible[] = false
        q = _WP7C_MX._curveplace(ax, rec.curves, rec.kw.sizes, rec.kw.outer)
        tp.visible[] = true
        @test all(<(40), q.costs)
        @test [Float32.(o) for o in q.offs] == [(o = _WP7C_MK.sv_getindex(tp.offset[], i); (Float32(o[1]), Float32(o[2]))) for i in 1:3]
        # a shipment and its label; strokes over the place the label took: a plain lines! moves nothing, a Logjam call
        # places it again, elsewhere, still clear
        fig, ax = _wp7c_axis()
        s1, P1 = DataFrame(b = [1], e = [2]), [2.0 5.0; 8.0 5.0]
        h = plotshmt!(ax, s1, P1; bend = 0.2, shmt_labels = true)
        a0, o0 = _wp7c_pts(h.shmt_labels), h.shmt_labels.offset[]
        c0 = a0[1]
        bx, by = Float64[], Float64[]
        for y in (c0[2] - 0.8):0.04:(c0[2] + 0.8)                  # horizontal strokes about 2 px apart around it
            append!(bx, [c0[1] - 1.2, c0[1] + 1.2, NaN]); append!(by, [y, y, NaN])
        end
        lines!(ax, bx, by; color = :black)
        @test _wp7c_pts(h.shmt_labels) == a0 && h.shmt_labels.offset[] == o0
        plotroute!(ax, bx, by; color = :black, arrows = false)
        @test (_wp7c_pts(h.shmt_labels), h.shmt_labels.offset[]) != (a0, o0)
        rec = only(r for r in _WP7C_MX._PLACED[ax] if r.tp === h.shmt_labels)
        h.shmt_labels.visible[] = false
        q = _WP7C_MX._curveplace(ax, rec.curves, rec.kw.sizes, rec.kw.outer)
        h.shmt_labels.visible[] = true
        @test all(<(40), q.costs) && [Float64.(Tuple(p)) for p in q.anchors] == _wp7c_pts(h.shmt_labels)
        # the checks
        ax = _wp7c_axis()[2]
        @test_throws ArgumentError plotshmt!(ax, sh, XY; shmt_labels = ["a"])
        @test_throws ArgumentError plotshmt!(ax, sh, XY; shmt_labels = 3)
    end

    @testset "5. plotroute!'s one route: bend for each leg, node_numbers, label; names and loads with nodes" begin
        s = DataFrame(b = [1, 3], e = [2, 4])
        P = [1.0 2.0; 9.0 2.0; 2.0 6.0; 8.0 6.0]                   # 5.2's pairwise-saving layout, stretched
        fig, ax = _wp7c_axis()
        hs = plotshmt!(ax, s, P; bend = 0.1, node_numbers = true, node_size = 30)
        hr = plotroute!(ax, [1, 2, 2, 1], s, P; color = :green, node_numbers = true, bend = [0, 0.4, 0],
                        label = "Shipments 1 and 2")
        @test keys(hr) == (:lines, :arrows, :markers, :node_numbers, :label)
        @test hr.markers === nothing && hr.node_numbers === nothing                   # every stop already has a node
        @test length(_WP7C_MX._NODES[ax]) == 1
        loc = [1, 3, 4, 2]                                                            # rte2loc([1, 2, 2, 1], s)
        pix = _wp7c_pix(fig, ax)
        tips = _wp7c_tips(hr)
        @test length(tips) == 3                                                       # one per leg
        @test all(isapprox(_wp7c_d(tips[k], pix(P[loc[k+1], 1], P[loc[k+1], 2])), 15.75; atol = 1e-3) for k in 1:3)
        pieces = _wp7c_pieces(hr.lines)
        @test length(pieces) == 3 && length(pieces[1]) == 2 && length(pieces[3]) == 2 && length(pieces[2]) > 10
        @test maximum(last, pieces[2]) > 6.0 + 0.9 * 0.4 * 6 / 2                      # the middle leg bowed up, by 0.4
        @test hr.label isa _WP7C_MK.Text && hr.label.input_text[] == ["Shipments 1 and 2"]
        @test _WP7C_MK.to_color(hr.label.color[]) == _WP7C_MK.to_color(:green)
        at, dist = _wp7c_along([pix(q...) for q in Base.invokelatest(_WP7C_LEC.bowed, P[3, :], P[4, :], 0.4 * 6.0, 0.5)],
                               pix(_wp7c_pts(hr.label)[1]...))
        @test dist < 1e-3 && 0.1 - 1e-9 <= at <= 0.9 + 1e-9                          # on the most bowed leg
        # a route on its own: its stops' nodes, in the order it first visits them; arrow_every; a straight route
        fig, ax = _wp7c_axis()
        h = plotroute!(ax, [1, 2, 2, 1], s, P; node_numbers = true, arrow_every = 2)
        @test h.node_numbers.input_text[] == ["1", "3", "4", "2"] && all(==(22), h.markers.markersize[])
        @test length(h.arrows[1][]) == 2
        tips = _wp7c_tips(h)
        pix = _wp7c_pix(fig, ax)
        @test all(isapprox(_wp7c_d(tips[j], pix(P[loc[k+1], 1], P[loc[k+1], 2])), 11.75; atol = 1e-3) for (j, k) in enumerate((1, 3)))
        # a bend alone: bowed legs, an arrowhead partway along each, one line through them
        h = plotroute!(_wp7c_axis()[2], [1, 2, 2, 1], s, P; bend = 0.2)
        @test keys(h) == (:lines, :arrows) && length(h.arrows[1][]) == 3 && length(_wp7c_pieces(h.lines)) == 1
        # names and loads with nodes: the circles are the markers, no dots
        fig, ax = _wp7c_axis()
        h = plotroute!(ax, [1, 2, 2, 1], s, P; node_numbers = true, loads = true)
        @test keys(h) == (:lines, :arrows, :markers, :node_numbers, :labels)
        m = h.markers.marker[]
        @test (m === _WP7C_MK.Circle || m isa _WP7C_MK.Circle || (m isa Type && m <: _WP7C_MK.Circle)) &&
              h.labels.input_text[] == [ldlabel(i, s) for i in loc]
        @test count(p -> p isa Scatter, ax.scene.plots) == 2                          # the circles and the arrowheads
        h = plotshmt!(_wp7c_axis()[2], s, P; node_numbers = true, names = ["A", "B", "C", "D"], loads = true,
                      load_color = :red, load_font = :bold, shmt_labels = true)
        @test keys(h) == (:lines, :arrows, :markers, :node_numbers, :shmt_labels, :labels)
        @test _WP7C_MK.to_color(h.labels.color[]) == _WP7C_MK.to_color(:red) && h.labels.font[] == :bold
        @test h.labels.input_text[] == ["A\n(L1)", "B\n(U1)", "C\n(L2)", "D\n(U2)"]
        # the checks
        ax = _wp7c_axis()[2]
        @test_throws ArgumentError plotroute!(ax, [1, 2, 2, 1], s, P; bend = [0.1, 0.2])        # three legs
        @test_throws ArgumentError plotroute!(ax, [1, 2, 2, 1], s, P; label = 3)
        @test_throws ArgumentError plotroute!(ax, [1, 2, 2, 1], s, P; bend_at = -0.1)
        @test_throws ArgumentError plotroute!(ax, [1, 1], DataFrame(b = [1], e = [2]), [0.0 0.0; 1.0 1.0];
                                              P = [[0, 1], [2, 0]], bend = 0.2)                # P traces its legs
    end
end
