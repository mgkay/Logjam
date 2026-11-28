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
# A label never moves farther from its point only to clear a base layer. The figure is Jacksonville's on 5.2's maps in
# miniature, in pixels (a 400 x 300 axis filling its figure): data lines on every side of the point but the northeast,
# and a base layer 12 px east of it, so the northeast spots out to 19 px touch the base layer and the only clear spot
# within `maxgap` is the diagonal 24 px out. Synthetic: no lecture data.
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

@testset "WP7a-2 (v0.3.1) a label stays beside its point: a nearer spot touching a base layer beats a clear one farther out" begin
    fig, ax = _wp7a2_coast(base = true)
    q = _WP7A_MX._aligntext(ax, [200.0], [150.0], ["Jacksonville"]; fontsize = 14)
    fig0, ax0 = _wp7a2_coast(base = false)
    q0 = _WP7A_MX._aligntext(ax0, [200.0], [150.0], ["Jacksonville"]; fontsize = 14)
    # the same line as a data line: the label goes out to the clear diagonal, 24 px, touching nothing
    @test q0.align == [(:left, :bottom)] && hypot(q0.offset[1]...) >= 24 && isempty(q0.flagged)
    # as a base layer: the label stays nearer, northeast, touching the base layer and nothing else (flagged as such)
    @test q.align == [(:left, :bottom)] && hypot(q.offset[1]...) < 24
    @test length(q.flagged) == 1 && q.flagged[1].touches == ["a base layer"]
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
