# test_map_k11c_pins.jl -- what the course sees of its default-road `makemap` calls and of the four map-extension
# functions' declarations, pinned from the code at 2e6a7a8 (PCV K11c, plan principle 9; K11a's pins are
# test_map_pins.jl and K11b's test_map_line_pins.jl). The values were measured on the unchanged code, before C5 (the
# extensions) and S22 (the road network on a small map). A call the course makes today keeps returning what it
# returned then; only a case named in K11CPIN_MOVED may differ, and each one is named in the commit that moves it.
#
# What C5 could move on the course's path, `using CairoMakie, GeoMakie` and then each map function: the figure and
# base-layer pins of test_map_pins.jl and test_map_line_pins.jl, the `plotroute!` tests (test_plotroute.jl) and the
# `dcf` smoke test (test_plottools.jl) already hold it, all drawn after exactly that `using` line, and they stay as
# they are. What those do not hold is the declaration the course's `logjam_kwargs` reads (apparatus.jl:136-139),
# `Base.kwarg_decl(first(methods(f)))`; it is pinned here, and C5 moves it.
#
# No case touches the network or a file outside the package, and none renders a picture.

using Test
using Logjam
using CairoMakie
using GeoMakie

include(joinpath(@__DIR__, "k11c_pin_cases.jl"))

# case name => ruled ID that moves it. kwarg_decl_*: C5 declares the functions in core and adds their methods, with real
# keywords, in the map extension, so the first method of `plotroads!` and `plotroute!` no longer lists only `kwargs...`,
# and the first method of `makemap`, one of the methods its default positional arguments made and so listing "...", is
# the no-argument method with the keywords written out (the new lists are in test_extensions_c5.jl).
const K11CPIN_MOVED = Dict("kwarg_decl_makemap" => "MAP (C5)", "kwarg_decl_plotroads!" => "MAP (C5)",
                           "kwarg_decl_plotroute!" => "MAP (C5)",
                           # S22: a map 150 miles across or less draws the FAF5 network where it drew the Interstates
                           "dwt_clinics_0.25" => "S22", "triangle_node_box" => "S22", "synthetic_tall_149" => "S22",
                           "synthetic_wide_149" => "S22",
                           # N4 (CR 19): a map over 150 miles across draws Logjam's U.S. road network cropped to the map
                           # (classes 1 to 3 up to 10 degrees of latitude, its Interstates up to 30) where it drew every
                           # Interstate polyline, so the road layer's point count moves; the label, the opacity and the
                           # Interstate's width stay. The layers are pinned again in test_map_tiers.jl (T5.6).
                           "nc_cities_default" => "N4", "nc_cities_xe0.2" => "N4", "carolinas_xe0.1" => "N4",
                           "nc_counties_xe0.05" => "N4", "nc_counties_xe0.1" => "N4", "popco_xe0.04" => "N4",
                           "popco_default" => "N4", "high_point_goldsboro" => "N4", "synthetic_tall_151" => "N4",
                           "synthetic_wide_151" => "N4")

_k11cpin_moved(name) = haskey(K11CPIN_MOVED, name) && (@info("K11c pin $name moved under $(K11CPIN_MOVED[name])"); true)

const K11C_ROADS_CLOSE = ("Interstate Roads", 246969, 0.2, 0.6, "solid")
const K11C_ROADS_MID = ("Interstate Roads", 246969, 0.25, 0.5, "solid")
const K11C_STATES = ("US State Borders", 3642, 1.0, 0.75, "solid")

# the drawn extent in miles (Lecture 2.5's measure, on the box the axis was given), and the base layers as drawn
const K11CPIN_EXPECTED = Dict(
    "nc_cities_default"    => (extent = 266.1748, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "nc_cities_xe0.2"      => (extent = 232.908, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "carolinas_xe0.1"      => (extent = 462.8983, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "nc_counties_xe0.05"   => (extent = 517.7356, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "nc_counties_xe0.1"    => (extent = 564.7641, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "dwt_clinics_0.25"     => (extent = 53.0325, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "popco_xe0.04"         => (extent = 1152.5188, layers = Tuple[K11C_ROADS_MID, K11C_STATES]),
    "popco_default"        => (extent = 1674.8649, layers = Tuple[K11C_ROADS_MID, K11C_STATES]),
    "high_point_goldsboro" => (extent = 163.3051, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "triangle_node_box"    => (extent = 80.5999, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "synthetic_tall_149"   => (extent = 149.0, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "synthetic_tall_151"   => (extent = 151.0, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "synthetic_wide_149"   => (extent = 148.9955, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
    "synthetic_wide_151"   => (extent = 150.9953, layers = Tuple[K11C_ROADS_CLOSE, K11C_STATES]),
)

@testset "default-road makemap calls are pinned: drawn extent and base layers" begin
    cases = vcat(k11cpin_cases(), k11cpin_synthetic())
    @test length(cases) == length(K11CPIN_EXPECTED)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(K11CPIN_EXPECTED, name)
            haskey(K11CPIN_EXPECTED, name) || continue
            want = K11CPIN_EXPECTED[name]
            fig, ax = thunk()
            @test isapprox(k11c_extent(ax.limits[]), want.extent; atol = 5e-4)     # the measure does not depend on S22
            _k11cpin_moved(name) && continue
            @test mmpin_describe(fig, ax).layers == want.layers
        end
    end
end

# the default-road shapes at or under Lecture 2.5's `CLOSE` of 150 miles are these two (a lecture figure, 2.7's
# clinics, and a probe); every other shape in the table is over 150 miles across
@testset "which course shapes are 150 miles across or less" begin
    close = sort!([name for (name, v) in K11CPIN_EXPECTED if v.extent <= 150.0 && !startswith(name, "synthetic")])
    @test close == ["dwt_clinics_0.25", "triangle_node_box"]
    @test K11CPIN_EXPECTED["high_point_goldsboro"].extent > 150.0
end

# `Base.kwarg_decl(first(methods(f)))`, which the course's `logjam_kwargs` (apparatus.jl:136-139) prints as a rung's
# keyword list. Today the first method of `makemap` has a keyword list that reads "...", and `plotroads!` and
# `plotroute!` list only `kwargs...` (their forwarding stubs); `osm_roads` is defined in core with its keywords. C5
# declares the functions in core and adds the methods in the extension, so the three lists move.
const K11CPIN_KWARGS = Dict(
    "makemap"    => ["..."],
    "plotroads!" => ["kwargs..."],
    "plotroute!" => ["kwargs..."],
    "osm_roads"  => ["cache_dir", "crop", "force_download", "verbose", "highways"],
)

@testset "the keyword declarations the course's logjam_kwargs reads are pinned" begin
    for (name, f) in (("makemap", makemap), ("plotroads!", plotroads!), ("plotroute!", plotroute!), ("osm_roads", osm_roads))
        @testset "$name" begin
            _k11cpin_moved("kwarg_decl_" * name) && continue
            @test String.(Base.kwarg_decl(first(methods(f)))) == K11CPIN_KWARGS[name]
        end
    end
end
