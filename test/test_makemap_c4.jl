# test_makemap_c4.jl -- makemap's interface (PCV K11b, MAP, C4; CR 46, CR 56): one implementation that draws into a cell,
# `size`, the `roads` and `borders` keywords, the (; fig, ax, layers) return, and doRoadbkgd as a deprecated alias.
# The calls the course makes are pinned in test_map_pins.jl and test_map_line_pins.jl, from the code before this change;
# these tests check that the new forms give the same figures, and what is new.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie

include(joinpath(@__DIR__, "map_pin_cases.jl"))

const _C4_INK = colorant"#252525"          # Lecture 5.3's ink

# the labeled base-layer plots of an axis: label => (RGBA, alpha attribute, linewidth, dashed?, points)
function _c4_layers(ax)
    out = Pair[]
    for p in ax.scene.plots
        haskey(p.attributes, :label) || continue
        c = Makie.to_color(p.color[])
        push!(out, string(p.label[]) => (round.(Float64[Makie.Colors.red(c), Makie.Colors.green(c), Makie.Colors.blue(c), Makie.Colors.alpha(c)], digits = 4),
                                         round(Float64(p.alpha[]), digits = 4), round(Float64(p.linewidth[]), digits = 4),
                                         p.linestyle[] !== nothing, length(p[1][])))
    end
    return out
end
_c4_labels(ax) = first.(_c4_layers(ax))

# Lecture 5.3, Code block 7 (5-rte-3.qmd:813-823, 840-845): the lecture's own basemap and fitmap!
function _c4_basemap(x, y; roads = false)
    fig, ax = makemap(x, y; xexpand = 0.02, yexpand = 0.12, doRoadbkgd = roads)
    for p in ax.scene.plots
        Makie.to_color(p.color[]).alpha < 1 && continue
        p.color, p.linewidth = (_C4_INK, 0.45), 1.5
    end
    return fig, ax
end
function _c4_fitmap!(fig, ax)
    lim = ax.finallimits[]
    resize!(fig, 600, round(Int, 600 * lim.widths[2] / lim.widths[1]) + 10)
    return fig
end

@testset "[MAP, C4] makemap's interface" begin
    nc = mmpin_nc()

    @testset "the return is (; fig, ax, layers), and fig, ax = makemap(...) still destructures" begin
        r = makemap(nc.LON, nc.LAT)
        @test r isa NamedTuple && keys(r) == (:fig, :ax, :layers)
        @test r.fig isa Figure && r.ax isa GeoAxis
        fig, ax = makemap(nc.LON, nc.LAT)                       # every course call destructures two
        @test fig isa Figure && ax isa GeoAxis
        fig, ax, layers = makemap(nc.LON, nc.LAT)               # and a third takes the layers
        @test keys(layers) == (:roads, :states, :countries)
        @test layers.roads isa Lines && layers.states isa Lines && layers.countries === nothing
        @test all(p -> any(q -> q === p, ax.scene.plots), (layers.roads, layers.states))     # the plots drawn, by identity
        @test string(layers.roads.label[]) == "Interstate Roads" && string(layers.states.label[]) == "US State Borders"
        @test layers.states.linestyle[] === nothing
        # a layer not drawn is nothing
        r = makemap(region = :World)
        @test r.layers.roads === nothing && r.layers.states === nothing && r.layers.countries isa Lines
        r = makemap(region = :CUS)
        @test r.layers.roads isa Lines && r.layers.states isa Lines && r.layers.countries === nothing
        r = makemap(region = :US)
        @test r.layers.roads === nothing && r.layers.states isa Lines && r.layers.countries isa Lines
        @test r.layers.states.linestyle[] !== nothing && r.layers.states.alpha[] == 0.5
    end

    @testset "roads = :auto is the default layer; false is doRoadbkgd = false" begin
        for (x, y, kw) in ((nc.LON, nc.LAT, (;)), (nc.LON, nc.LAT, (xexpand = 0.05,)), ([-122.0, -121.0, -121.5], [38.0, 39.0, 38.5], (xexpand = 0.6, yexpand = 2.0)),
                           ([-100.0, -90.0], [20.0, 50.5], (xexpand = 0, yexpand = 0)))
            a, b = makemap(x, y; kw...), makemap(x, y; roads = :auto, kw...)
            @test _c4_layers(a.ax) == _c4_layers(b.ax)
            @test a.ax.limits[] == b.ax.limits[]
            c, d = makemap(x, y; doRoadbkgd = false, kw...), makemap(x, y; roads = false, kw...)
            @test _c4_layers(c.ax) == _c4_layers(d.ax)
            @test "Interstate Roads" ∉ _c4_labels(d.ax) && d.layers.roads === nothing
            e = makemap(x, y; doRoadbkgd = true, kw...)
            @test _c4_layers(e.ax) == _c4_layers(a.ax)
        end
        @test _c4_layers(makemap(region = :CUS, roads = :auto).ax) == _c4_layers(makemap(region = :CUS).ax)
    end

    @testset "roads = (; color, alpha, linewidth) overrides attributes of that layer" begin
        base = _c4_layers(makemap(nc.LON, nc.LAT).ax)[1][2]                    # the Interstate layer: 0.2, 0.6
        @test base[1] ≈ [0.2745, 0.5098, 0.7059, 0.2] atol = 1e-4
        @test base[3] == 0.6
        r = makemap(nc.LON, nc.LAT; roads = (; color = :steelblue, alpha = 0.5))   # README Example 2
        l = _c4_layers(r.ax)[1][2]
        @test l[1] ≈ [0.2745, 0.5098, 0.7059, 0.5] atol = 1e-4
        @test l[3] == 0.6 && l[5] == base[5]
        l = _c4_layers(makemap(nc.LON, nc.LAT; roads = (; color = :red)).ax)[1][2]   # the zoom's alpha stays
        @test l[1] == [1.0, 0.0, 0.0, 0.2] && l[3] == 0.6
        l = _c4_layers(makemap(nc.LON, nc.LAT; roads = (; linewidth = 2)).ax)[1][2]
        @test l[1] ≈ base[1] atol = 1e-4
        @test l[3] == 2.0
        l = _c4_layers(makemap(region = :CUS; roads = (; alpha = 0.9, linewidth = 1.0)).ax)[1][2]   # far zoom: 0.35 and 0.3 otherwise
        @test l[1][4] == 0.9 && l[3] == 1.0
        @test _c4_layers(makemap(nc.LON, nc.LAT; roads = (;)).ax) == _c4_layers(makemap(nc.LON, nc.LAT).ax)   # no override: :auto's
        # the layer is still the Interstate skeleton, drawn up to 30 degrees of span, with every point
        @test _c4_layers(makemap(nc.LON, nc.LAT; roads = (; color = :red)).ax)[1][2][5] == base[5]
        @test "Interstate Roads" ∉ _c4_labels(makemap(region = :US; roads = (; color = :red)).ax)
        @test "Interstate Roads" ∉ _c4_labels(makemap([-100.0, -90.0], [20.0, 50.5]; xexpand = 0, yexpand = 0, roads = (; color = :red)).ax)
        @test "Interstate Roads" ∈ _c4_labels(makemap([-100.0, -90.0], [20.0, 50.0]; xexpand = 0, yexpand = 0, roads = (; color = :red)).ax)
    end

    @testset "borders = true | false | (; color, linewidth)" begin
        @test _c4_layers(makemap(nc.LON, nc.LAT; borders = true).ax) == _c4_layers(makemap(nc.LON, nc.LAT).ax)
        for kw in ((region = :World,), (region = :US,), (region = :CUS,))
            r = makemap(; borders = false, kw...)
            @test r.layers.states === nothing && r.layers.countries === nothing
            @test all(l -> l ∉ ("US State Borders", "Country Borders"), _c4_labels(r.ax))
        end
        @test _c4_labels(makemap(nc.LON, nc.LAT; borders = false).ax) == ["Interstate Roads"]
        # a color and a width, on each layer drawn; the dashed, half-opaque state layer where both draw
        r = makemap([-158.0, -155.0], [19.0, 22.0]; roads = false, borders = (; color = :red, linewidth = 2))
        L = Dict(_c4_layers(r.ax))
        @test L["US State Borders"][1] == [1.0, 0.0, 0.0, 1.0] && L["US State Borders"][3] == 2.0 && L["US State Borders"][4] && L["US State Borders"][2] == 0.5
        @test L["Country Borders"][1] == [1.0, 0.0, 0.0, 1.0] && L["Country Borders"][3] == 2.0 && !L["Country Borders"][4]
        # only a color: the width stays
        L = Dict(_c4_layers(makemap(region = :US; borders = (; color = :red)).ax))
        @test L["Country Borders"][1] == [1.0, 0.0, 0.0, 1.0] && L["Country Borders"][3] == 0.75
        # Lecture 5.3's basemap restyles the borders by looping over ax.scene.plots; the keyword gives the same layers
        x, y = nc.LON, nc.LAT
        old = _c4_layers(_c4_basemap(x, y)[2])
        new = _c4_layers(makemap(x, y; xexpand = 0.02, yexpand = 0.12, roads = false, borders = (; color = (_C4_INK, 0.45), linewidth = 1.5)).ax)
        @test new == old && length(new) == 1 && new[1][1] == "US State Borders"
        old = _c4_layers(_c4_basemap(x, y; roads = true)[2])
        new = _c4_layers(makemap(x, y; xexpand = 0.02, yexpand = 0.12, borders = (; color = (_C4_INK, 0.45), linewidth = 1.5)).ax)
        @test [l for l in new if l[1] == "US State Borders"] == [l for l in old if l[1] == "US State Borders"]
        @test [l for l in new if l[1] == "Interstate Roads"] == [l for l in old if l[1] == "Interstate Roads"]   # the roads stay faded
    end

    @testset "size: (width, height), the default, and (width, :auto) fits the height to the map" begin
        @test size(makemap(nc.LON, nc.LAT).fig.scene) == (600, 450)
        @test size(makemap(nc.LON, nc.LAT; size = (600, 450)).fig.scene) == (600, 450)
        @test size(makemap(nc.LON, nc.LAT; size = (400, 420)).fig.scene) == (400, 420)      # Lecture 4.1's resize!(fig, 400, 420)
        @test size(makemap(nc.LON, nc.LAT; size = (687.0, 300)).fig.scene) == (687, 300)
        # = resize! after the call: the same figure, size and limits
        a = makemap(nc.LON, nc.LAT; xexpand = 0.05, size = (900, 500))
        b = makemap(nc.LON, nc.LAT; xexpand = 0.05); resize!(b.fig, 900, 500)
        @test size(a.fig.scene) == size(b.fig.scene) && a.ax.limits[] == b.ax.limits[] && _c4_layers(a.ax) == _c4_layers(b.ax)
        # (width, :auto) is Lecture 5.3's fitmap!: the height from the projected aspect of the limits, plus 10
        x, y = nc.LON, nc.LAT
        fig, ax = _c4_basemap(x, y)
        _c4_fitmap!(fig, ax)
        r = makemap(x, y; xexpand = 0.02, yexpand = 0.12, roads = false, size = (600, :auto))
        @test size(r.fig.scene) == size(fig.scene)
        @test size(r.fig.scene)[1] == 600 && size(r.fig.scene)[2] != 450
        for (xx, yy, kw) in ((x, y, (xexpand = 0.05,)), ([-122.0, -121.0], [38.0, 39.0], (;)), (nothing, nothing, (region = :CUS,)))
            r = makemap(xx, yy; kw..., size = (500, :auto))
            lim = r.ax.finallimits[]
            @test size(r.fig.scene) == (500, round(Int, 500 * lim.widths[2] / lim.widths[1]) + 10)
        end
        @test size(makemap(region = :World; size = (600, :auto)).fig.scene)[2] < 450          # a wide map is short
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; size = (600, :fit))
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; size = 600)
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; size = (0, 300))
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; size = (:auto, 300))
    end

    @testset "layer keywords are checked: an unknown attribute or value is an ArgumentError" begin
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; roads = (; colour = :red))
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; roads = (; linestyle = :dash))
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; roads = :always)
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; roads = true)
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; borders = (; alpha = 0.5))
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; borders = :blue)
        @test_throws MethodError makemap(nc.LON, nc.LAT; roadcolor = :red)                 # removed (0 course calls)
        @test_throws MethodError makemap(nc.LON, nc.LAT; roadalpha = 0.5)
        @test_throws MethodError makemap(nc.LON, nc.LAT; maxroadlatspan = 40.0)
        @test_throws MethodError makemap(nc.LON, nc.LAT; roadcolor = :red, roadalpha = 0.5)
    end

    @testset "doRoadbkgd is a deprecated alias, silent unless Julia runs with --depwarn=yes" begin
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; doRoadbkgd = false, roads = false)
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; doRoadbkgd = true, roads = :auto)
        @test_throws ArgumentError makemap(nc.LON, nc.LAT; doRoadbkgd = 1)
        if Base.JLOptions().depwarn == 1                                        # Pkg.test: warns once for each call
            @test_deprecated makemap(nc.LON, nc.LAT; doRoadbkgd = false)
        elseif Base.JLOptions().depwarn == 0
            @test_logs makemap(nc.LON, nc.LAT; doRoadbkgd = false)
        end
        # and prints nothing to stdout under any option
        mktemp() do path, io
            redirect_stdout(io) do
                makemap(nc.LON, nc.LAT; doRoadbkgd = false)
                makemap(nc.LON, nc.LAT; roads = (; color = :red, alpha = 0.3), borders = (; color = :gray), size = (500, :auto))
                makemap(Figure()[1, 1], nc.LON, nc.LAT)
            end
            flush(io)
            @test filesize(path) == 0
        end
        @test_logs makemap(nc.LON, nc.LAT; roads = false, borders = (; linewidth = 1), size = (400, 300))   # no log, no matter the options
    end

    @testset "makemap(cell, ...) draws into a cell of a figure that exists" begin
        fig = Figure(size = (900, 400))
        r1 = makemap(fig[1, 1], nc.LON, nc.LAT; xexpand = 0.05)
        r2 = makemap(fig[1, 2]; region = :CUS)
        @test r1.fig === fig && r2.fig === fig                                  # fig is the figure that holds the cell
        @test r1.ax isa GeoAxis && r2.ax isa GeoAxis && r1.ax !== r2.ax
        @test size(fig.scene) == (900, 400)                                     # the figure is not resized or replaced
        @test contents(fig[1, 1]) == [r1.ax] && contents(fig[1, 2]) == [r2.ax]
        # the map in the cell is the map the figure-creating call draws
        s1 = makemap(nc.LON, nc.LAT; xexpand = 0.05)
        @test r1.ax.limits[] == s1.ax.limits[] && _c4_layers(r1.ax) == _c4_layers(s1.ax)
        s2 = makemap(region = :CUS)
        @test r2.ax.limits[] == s2.ax.limits[] && _c4_layers(r2.ax) == _c4_layers(s2.ax)
        @test keys(r1.layers) == (:roads, :states, :countries) && r1.layers.roads isa Lines
        # the layer keywords and the box
        r3 = makemap(fig[2, 1:2], ((-80.0, -75.0), (35.0, 40.0)); roads = false, borders = (; color = (:blue, 0.6)))
        @test r3.ax.limits[] == ((-80.0, -75.0), (35.0, 40.0)) && r3.layers.roads === nothing
        @test Dict(_c4_layers(r3.ax))["US State Borders"][1] == [0.0, 0.0, 1.0, 0.6]
        @test _c4_layers(makemap(Figure()[1, 1], WORLD_LIMITS).ax) == _c4_layers(makemap(WORLD_LIMITS).ax)
        # a cell of a nested layout
        f2 = Figure()
        g = GridLayout(f2[1, 1])
        r4 = makemap(g[2, 1], nc.LON, nc.LAT; roads = false)
        @test r4.fig === f2 && contents(g[2, 1]) == [r4.ax]
        # what a cell does not take
        @test_throws ArgumentError makemap(fig[3, 1], nc.LON, nc.LAT; size = (300, 300))
        @test_throws ArgumentError makemap(fig[3, 1]; region = :US, size = (300, 300))
        @test_throws ArgumentError makemap(fig[3, 1], ((-80.0, -75.0), (35.0, 40.0)); xexpand = 0.1)
        @test_throws MethodError makemap(:not_a_cell, nc.LON, nc.LAT)       # C5: the cell is typed Makie.GridPosition, so these are MethodErrors
        @test_throws MethodError makemap(fig, nc.LON, nc.LAT)               # (they were ArgumentErrors the extension checked)
        @test_throws ArgumentError makemap(fig[3, 1]; roads = :nope)
    end

    @testset "the methods are not ambiguous with one another" begin
        ms = collect(methods(makemap))
        @test length(ms) >= 7
        for a in ms, b in ms
            a === b && continue
            @test !Base.isambiguous(a, b)
        end
        # each call shape reaches the method meant
        box = ((-80.0, -75.0), (35.0, 40.0))
        f = Figure()
        @test Base.which(makemap, Tuple{typeof(box)}).sig == Base.which(makemap, Tuple{Tuple{Tuple{Int, Int}, Tuple{Int, Int}}}).sig
        @test Base.which(makemap, Tuple{Vector{Float64}, Vector{Float64}}) != Base.which(makemap, Tuple{typeof(f[1, 1]), Vector{Float64}, Vector{Float64}})
        @test Base.which(makemap, Tuple{typeof(f[1, 1]), typeof(box)}) != Base.which(makemap, Tuple{Tuple{Float64, Float64}, Tuple{Float64, Float64}})
        @test Base.which(makemap, Tuple{typeof(f[1, 1])}) != Base.which(makemap, Tuple{typeof(box)})
        @test size(makemap((-80.0, -75.0), (35.0, 40.0); xexpand = 0.1).fig.scene) == (600, 450)       # the tuple pair: two ranges
    end
end
