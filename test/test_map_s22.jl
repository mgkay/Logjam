# test_map_s22.jl -- the road network on a small map (PCV K11c, S22 and S23). `roads = :auto` on a map 150 miles across
# or less draws the FAF5 network, cropped to the map, in one hue and below alpha 0.35; above 150 miles the layers are
# K11b's (pinned in test_map_pins.jl, test_map_line_pins.jl and test_map_k11c_pins.jl).

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie

include(joinpath(@__DIR__, "k11c_pin_cases.jl"))

# every plot of the network layer: the five class plots of `layers.roads`, in class order
_s22_plots(roads) = [p for p in (roads.class1, roads.class2, roads.class3, roads.class4, roads.class5) if p !== nothing]
_s22_alpha(p) = Float64(p.alpha[]) * Float64(Makie.Colors.alpha(Makie.to_color(p.color[])))
_s22_rgb(p) = (c = Makie.to_color(p.color[]); round.(Float64[Makie.Colors.red(c), Makie.Colors.green(c), Makie.Colors.blue(c)], digits = 3))

# an independent test of "the segment meets the box": an end inside, or a crossing of one of the four edges
function _s22_meets(a, b, box)
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

@testset "[S22] [S23] the road network on a small map" begin
    N, L = faf5nodes(), faf5links()
    xy = Dict(N.IDX .=> zip(N.LON, N.LAT))

    @testset "the measure: the larger great-circle extent through the box's center, in miles, at most 150.0" begin
        @test Logjam._MAP_CLOSE_MILES == 150.0
        box = ((-79.0, -78.0), (35.0, 36.0))
        @test Logjam._mapextent(box) == k11c_extent(box)
        @test Logjam._mapextent(((-79.0, -78.9), (35.0, 37.0))) ≈ dgc([-78.95, 35.0], [-78.95, 37.0])    # tall: north-south governs
        @test Logjam._mapextent(((-80.0, -77.0), (35.4, 35.6))) ≈ dgc([-80.0, 35.5], [-77.0, 35.5])      # wide: east-west governs
        @test Logjam._mapisclose(k11c_tall(149.0)) && !Logjam._mapisclose(k11c_tall(151.0))
        @test Logjam._mapisclose(k11c_wide(149.0)) && !Logjam._mapisclose(k11c_wide(151.0))
        @test !Logjam._mapisclose(WORLD_LIMITS) && !Logjam._mapisclose(CUS_LIMITS) && !Logjam._mapisclose(US_LIMITS)
    end

    @testset "a close map draws the network; a map over 150 miles draws the Interstate layer as before" begin
        for name in ("synthetic_tall_149", "synthetic_wide_149")
            fig, ax, layers = Dict(k11cpin_synthetic())[name]()
            @test layers.roads isa NamedTuple && keys(layers.roads) == (:class1, :class2, :class3, :class4, :class5)
            @test all(p -> p isa Makie.Lines, _s22_plots(layers.roads))
            @test !any(p -> haskey(p.attributes, :label) && string(p.label[]) == "Interstate Roads", ax.scene.plots)
        end
        for name in ("synthetic_tall_151", "synthetic_wide_151")
            fig, ax, layers = Dict(k11cpin_synthetic())[name]()
            @test layers.roads isa Makie.Lines && string(layers.roads.label[]) == "Interstate Roads"
        end
        for r in (:World, :US, :CUS)                          # region maps are never close
            fig, ax, layers = makemap(region = r)
            @test !(layers.roads isa NamedTuple)
        end
    end

    @testset "the style: one hue, every stroke below alpha 0.35, the classes by width" begin
        bb = ((-79.2, -78.4), (35.5, 36.1))                                  # about 55 miles across
        @test Logjam._mapisclose(bb)
        fig, ax, layers = makemap(bb)
        plots = _s22_plots(layers.roads)
        @test length(plots) == 5
        @test all(p -> _s22_rgb(p) == [0.275, 0.51, 0.706], plots)            # :steelblue, the Interstate layer's hue
        @test all(p -> 0 < _s22_alpha(p) < 0.35, plots)                       # the course figure gate's FAINT_ALPHA
        @test all(p -> _s22_alpha(p) == 0.3f0 || _s22_alpha(p) ≈ 0.3, plots)
        w = [Float64(p.linewidth[]) for p in plots]
        @test issorted(w; rev = true) && allunique(w)                         # the Interstate heaviest
        @test isapprox(w, [1.4, 1.0, 0.7, 0.5, 0.3]; rtol = 1e-6)             # Makie keeps a width as a Float32
        # no casing, no other stroke: the network is these five plots
        @test count(p -> p isa Makie.Lines && p ∈ plots, ax.scene.plots) == 5
        # drawn Interstate on top: the heavier the class, the later it is drawn
        order = [findfirst(q -> q === p, ax.scene.plots) for p in plots]
        @test issorted(order; rev = true)
    end

    @testset "the crop: every link whose segment meets the box and is not a ramp is drawn, in its own class, and no other" begin
        tier(fc) = (fc <= 0 || fc >= 5) ? 5 : fc                              # plotroads!'s grouping, written out
        # a ramp by its name, written out independently of the extension's pattern
        isramp(nm) = !ismissing(nm) && (u = uppercase(string(nm));
            any(w -> occursin(Regex("\\b$w\\b"), u), ("RAMP", "RAMPS", "C/D LANE", "TURN LANE")) ||
            occursin("COLLECTOR/DISTRIBUTOR", replace(u, " " => "")) || occursin("CONNECTOR/DISTRIBUTOR", replace(u, " " => "")))
        @test count(isramp, L.NAME) == 137156                                 # FAF5 as shipped
        @test !isramp("N RAMPART ST") && !isramp("AIRPORT CONNECTOR") && isramp("SYSTEM RAMP - I 35 NB") &&
              isramp("CA 65 NB CONNECTOR/DISTRIBUTOR LANE") && isramp("I 405 COLLECTOR/DISTRIBUTOR LANE")
        nramps = 0
        for bb in (((-79.2, -78.4), (35.5, 36.1)), ((-78.80, -78.50), (35.70, 35.90)), ((-79.0, -78.9), (35.0, 36.4)))
            Logjam._mapisclose(bb) || continue
            fig, ax, layers = makemap(bb)
            drawn = [Set{Tuple{NTuple{2, Float64}, NTuple{2, Float64}}}() for _ in 1:5]
            for (k, name) in enumerate((:class1, :class2, :class3, :class4, :class5))
                p = layers.roads[name]
                p === nothing && continue
                pts = p[1][]
                for i in 1:3:length(pts)
                    a, b = pts[i], pts[i + 1]
                    @test isnan(pts[i + 2][1]) && isnan(pts[i + 2][2])
                    push!(drawn[k], ((a[1], a[2]), (b[1], b[2])))
                end
            end
            want = [Set{Tuple{NTuple{2, Float64}, NTuple{2, Float64}}}() for _ in 1:5]
            for i in 1:nrow(L)
                a, b = xy[L.SRC[i]], xy[L.DST[i]]
                _s22_meets(a, b, bb) || continue
                if isramp(L.NAME[i])
                    nramps += 1
                else
                    push!(want[tier(L.FCLASS[i])], (a, b))
                end
            end
            @test drawn == want
            @test all(!isempty, want[1:3])
            # the roads run to the frame: some drawn segment has an end outside the box
            all_drawn = reduce(union, drawn)
            @test any(s -> !(bb[1][1] <= s[1][1] <= bb[1][2] && bb[2][1] <= s[1][2] <= bb[2][2]) ||
                           !(bb[1][1] <= s[2][1] <= bb[1][2] && bb[2][1] <= s[2][2] <= bb[2][2]), all_drawn)
        end
        @test nramps > 0                                                      # control: the boxes do hold ramps, left out
    end

    @testset "roads = false draws nothing; a NamedTuple restyles the network" begin
        bb = ((-79.2, -78.4), (35.5, 36.1))
        fig, ax, layers = makemap(bb; roads = false)
        @test layers.roads === nothing
        fig, ax, layers = makemap(bb; roads = (; color = :red, alpha = 0.2, linewidth = 2.0))
        plots = _s22_plots(layers.roads)
        @test all(p -> _s22_rgb(p) == [1.0, 0.0, 0.0] && _s22_alpha(p) ≈ 0.2, plots)
        @test Float64[p.linewidth[] for p in plots] ≈ 2.0 .* [1.0, 1 / 1.4, 0.7 / 1.4, 0.5 / 1.4, 0.3 / 1.4]
        fig, ax, layers = makemap(bb; roads = (; alpha = 0.5))              # an explicit request is the user's
        @test all(p -> _s22_alpha(p) ≈ 0.5 && _s22_rgb(p) == [0.275, 0.51, 0.706], _s22_plots(layers.roads))
        fig, ax, layers = makemap(bb; roads = :auto)
        @test layers.roads isa NamedTuple
    end

    @testset "the network reads the cached FAF5 tables and changes neither" begin
        n, l = Logjam._faf5tables()
        @test n === Logjam._faf5nodes_cache[] && l === Logjam._faf5links_cache[]       # the tables themselves, not copies
        before = (size(n), size(l), sum(n.LON), sum(n.LAT), sum(l.DIST), sum(l.FCLASS), sum(l.SRC))
        makemap(((-79.2, -78.4), (35.5, 36.1)))
        makemap(((-78.8, -78.5), (35.7, 35.9)); roads = (; color = :red))
        @test (size(n), size(l), sum(n.LON), sum(n.LAT), sum(l.DIST), sum(l.FCLASS), sum(l.SRC)) == before
        @test faf5nodes() !== n && isequal(faf5nodes(), n)                              # faf5nodes() still returns a copy
    end

    @testset "the cell methods and the points' form draw the same network" begin
        bb = ((-79.2, -78.4), (35.5, 36.1))
        a = makemap(bb)
        fig = Figure()
        b = makemap(fig[1, 1], bb)
        c = makemap([bb[1][1], bb[1][2]], [bb[2][1], bb[2][2]]; xexpand = 0, yexpand = 0)
        npts(r) = [p === nothing ? 0 : length(p[1][]) for p in (r.layers.roads.class1, r.layers.roads.class2, r.layers.roads.class3, r.layers.roads.class4, r.layers.roads.class5)]
        @test npts(a) == npts(b) == npts(c)
        @test sum(npts(a)) > 0
    end
    @testset "the course's default-road shapes: the network exactly when the map is 150 miles across or less" begin
        for (name, thunk) in vcat(k11cpin_cases(), k11cpin_synthetic())
            @testset "" begin
                fig, ax, layers = thunk()
                miles = k11c_extent(ax.limits[])
                @test (layers.roads isa NamedTuple) == (miles <= 150.0)
                if miles <= 150.0
                    @test string(layers.roads.class1.label[]) == "FAF5 Roads"
                else
                    @test layers.roads isa Makie.Lines && string(layers.roads.label[]) == "Interstate Roads"
                end
            end
        end
        # a synthetic 12-mile box with 2.6's keywords (map_pin_cases.jl, "xy_both_expands"; 2.6's own call is 1,152 miles across and unchanged): the pin that S22 moves holds its
        # size, limits and borders, and draws the network where it drew the Interstates
        dc = ([-77.1, -76.9, -77.0], [38.8, 38.95, 38.9])
        fig, ax, layers = makemap(dc[1], dc[2]; xexpand = 0.04, yexpand = 0.04)
        @test size(fig.scene) == (600, 450)
        @test all(isapprox.(vcat(collect.(ax.limits[])...), [-77.108, -76.892, 38.794, 38.956]; rtol = 1e-12))
        @test layers.roads isa NamedTuple && layers.states isa Makie.Lines && layers.countries === nothing
        @test mmpin_describe(fig, ax).layers[end] == ("US State Borders", 3642, 1.0, 0.75, "solid")
    end
end
