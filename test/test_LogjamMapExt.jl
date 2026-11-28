# test_LogjamMapExt.jl -- the tests of ext/LogjamMapExt.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_maptools.jl, its lines 1-1, 69-122, 200-301 ====
using Test

# Test for makemap function
@testset "makemap tests" begin
    # Test different regions (M1: 2-tuple return)
    @testset "region=$region" for region in [:World, :US, :CUS]
        fig, ax = makemap(region=region)
        @test fig isa Figure
        @test ax isa GeoAxis
    end

    # Test with coordinate inputs
    @testset "coordinate inputs" begin
        x = [-80.0, -75.0, -78.0]
        y = [35.0, 40.0, 38.0]
        fig, ax = makemap(x, y)
        @test fig isa Figure
        @test ax isa GeoAxis
    end

    # M1.2, as C4 (PCV K11b): the road overlay is restyled by `roads = (; color, alpha)`; roadcolor and roadalpha are gone
    @testset "roads = (; color, alpha) restyles the overlay" begin
        x = [-80.0, -75.0, -78.0]
        y = [35.0, 40.0, 38.0]
        fig2, ax2 = makemap(x, y; roads = (; color = :red, alpha = 0.5))
        @test fig2 isa Figure
        @test ax2 isa GeoAxis
    end

    # Test showgrid keyword
    @testset "showgrid default off" begin
        fig, ax = makemap(region=:CUS)
        @test ax.xgridvisible[] == false
        @test ax.yticklabelsvisible[] == false
    end

    @testset "showgrid=true" begin
        fig, ax = makemap(region=:CUS; showgrid=true)
        @test ax.xgridvisible[] == true
        @test ax.yticklabelsvisible[] == true
    end

    # P8 (PCV K11a): the backend keyword and the GLMakie extension are removed (0 course calls)
    @testset "[P8] backend keyword is removed, with the GLMakie extension" begin
        @test_throws MethodError makemap(backend = :CairoMakie)
        @test_throws MethodError makemap(backend = :GLMakie)
        @test_throws MethodError makemap([-80.0, -75.0], [35.0, 40.0]; backend = :CairoMakie)
        @test !isdefined(Logjam, :_glmakie_available) && !isdefined(Logjam, :_glmakie_activate)
        @test Base.get_extension(Logjam, :LogjamGLMakieExt) === nothing
        proj = Base.parsed_toml(joinpath(pkgdir(Logjam), "Project.toml"))
        @test !haskey(get(proj, "weakdeps", Dict()), "GLMakie") && !haskey(get(proj, "extensions", Dict()), "LogjamGLMakieExt")
        @test !haskey(get(proj, "compat", Dict()), "GLMakie")
        @test !isfile(joinpath(pkgdir(Logjam), "ext", "LogjamGLMakieExt.jl"))
    end
end

# Smoke tests for plotroads! function
@testset "plotroads tests" begin
    using DataFrames

    # Shared fixture: small 4-node diamond network around Raleigh, NC
    dfN_test = DataFrame(
        IDX = [1, 2, 3, 4],
        LON = [-78.9, -78.5, -78.7, -79.1],
        LAT = [35.8, 35.8, 36.0, 35.6]
    )
    # Links: interstate (FCLASS=1) and other (FCLASS=2), plus a connector
    dfL_test = DataFrame(
        SRC    = [1, 2, 3, 1, 1],
        DST    = [2, 3, 4, 3, 4],
        DIST   = [1.0, 1.2, 1.5, 0.8, 1.1],
        FCLASS = [1, 1, 2, 2, 2],
        SOURCE = ["FAF5", "FAF5", "FAF5", "FAF5", "CONNECTOR"]
    )

    # Bounding box for makemap
    x_test = [-79.2, -78.4]
    y_test = [35.5, 36.1]

    @testset "basic render returns Dict" begin
        fig, ax = makemap(x_test, y_test)
        handles = plotroads!(ax, dfN_test, dfL_test)
        @test handles isa Dict{Symbol, Any}
        @test length(handles) > 0
    end

    @testset "handle keys without connectors" begin
        dfL_faf5 = filter(r -> r.SOURCE != "CONNECTOR", dfL_test)
        fig, ax = makemap(x_test, y_test)
        handles = plotroads!(ax, dfN_test, dfL_faf5)
        # Close zoom (<10° latspan): 2 tiers (FCLASS 1,2) with casing+fill each
        @test haskey(handles, :fill_1)
        @test haskey(handles, :fill_2)
        @test haskey(handles, :casing_1)
        @test haskey(handles, :casing_2)
        @test !haskey(handles, :connector)
        @test length(handles) == 4
    end

    @testset "handle keys with connectors" begin
        fig, ax = makemap(x_test, y_test)
        handles = plotroads!(ax, dfN_test, dfL_test; show_connectors=true)
        @test haskey(handles, :fill_1)
        @test haskey(handles, :casing_1)
        @test haskey(handles, :connector)
        @test length(handles) == 5
    end

    @testset "connectors hidden by default" begin
        fig, ax = makemap(x_test, y_test)
        handles = plotroads!(ax, dfN_test, dfL_test)
        @test !haskey(handles, :connector)
        @test length(handles) == 4
    end

    @testset "handle customization" begin
        fig, ax = makemap(x_test, y_test)
        handles = plotroads!(ax, dfN_test, dfL_test)
        # Verify handles are mutable Makie line objects
        handles[:fill_1].color = :darkblue
        @test true  # No error means customization works
    end

    @testset "empty dfL raises ArgumentError" begin
        dfL_empty = DataFrame(SRC=Int[], DST=Int[])
        fig, ax = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_test, dfL_empty)
    end

    @testset "orphan node reference raises ArgumentError" begin
        dfL_bad = DataFrame(SRC=[1, 99], DST=[2, 3], SOURCE=["FAF5", "FAF5"])
        fig, ax = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_test, dfL_bad)
    end

    @testset "no SOURCE column backward compat" begin
        dfL_nosrc = DataFrame(SRC=[1, 2, 3], DST=[2, 3, 4], DIST=[1.0, 1.2, 1.5])
        fig, ax = makemap(x_test, y_test)
        handles = plotroads!(ax, dfN_test, dfL_nosrc)
        # No SOURCE, no FCLASS → all tier 5; close zoom: casing_5 + fill_5 = 2
        @test length(handles) == 2
        @test haskey(handles, :fill_5)
        @test haskey(handles, :casing_5)
    end

    @testset "wide zoom has no casings" begin
        # latspan > 20° → no casing keys
        x_wide = [-125.0, -65.0]
        y_wide = [24.0, 50.0]
        fig, ax = makemap(x_wide, y_wide)
        handles = plotroads!(ax, dfN_test, dfL_test)
        @test haskey(handles, :fill_1)
        @test !haskey(handles, :casing_1)
    end
end

# plotroute! is tested in test_plotroute.jl (PCV K11a, D2)

# ==== moved from test/test_map_pins.jl, its lines 1-173 ====
# test_map_pins.jl -- what the course sees of its `makemap` calls, pinned from the code at 6df5d23 (v0.2.8's makemap
# and `_makemap_impl`, unchanged until PCV K11a; plan principle 9). A call the course makes today keeps returning
# the figure size, axis limits, projected extent and base layers it returned then. Only a case named in
# MMPIN_MOVED may differ, and each one is named in the commit that moves it.
#
# Written before K11a's removals (P8: `backend`, the GLMakie extension) and its `makemap(bb)` method, from the
# unchanged code. No case touches the network or a file outside the package.

using Test
using Logjam
using CairoMakie
using GeoMakie

isdefined(@__MODULE__, :mmpin_cases) || include(joinpath(@__DIR__, "map_pin_cases.jl"))

# case name => ruled ID that moves it. makemap_activate_type: makemap no longer runs CairoMakie.activate!() (P8, K11a), so
# an image type the caller set (`type = "svg"`) stays; every lecture runs `activate!(px_per_unit = 2)`, which sets none.
# xy_both_expands: a synthetic 12-mile box with Lecture 2.6's keywords (2.6's own call is 1,152 miles across and unchanged), draws the FAF5 network where it drew the Interstates
# (S22, K11c); its size, limits and the state borders are pinned again in test_map_s22.jl.
# N4 (CR 19, his answer to Q2): a map over 150 miles across draws Logjam's U.S. road network (usrdlink) cropped to the
# map, classes 1 to 3 up to 10 degrees of latitude and its Interstates up to 30, where it drew all 82,323 Interstate
# polylines (246,969 points, both carriageways) whatever the map's place, so the road layer's point count moves; its
# label, opacity and Interstate width stay, but region_CUS's far step is 0.3, not 0.35 (S23: every stroke below 0.35).
# Each case's size, limits, extent and other layers are pinned again in test_map_tiers.jl (T5.6), with the road layer
# as it is drawn now.
# N4b (RN26): the regional tier's label is "Major Roads" (it was "Interstate Roads", which it kept through N4); the
# national tier (region_CUS) keeps "Interstate Roads". N4b (RN24): the Interstate's opacity and width on both tiers are
# measured against v0.3.0's picture (regional 0.32 and 0.7, national 0.32 and 0.85 up to 20 degrees, 0.3 and 0.8 above).
# The regional cases therefore move under all three, in that order.
const MMPIN_MOVED = Dict("makemap_activate_type" => "P8", "xy_both_expands" => "S22",
                         "xy_default" => "N4, N4b (RN26), N4b (RN24)", "xy_xexpand_0.1" => "N4, N4b (RN26), N4b (RN24)",
                         "xy_xexpand_0.3" => "N4, N4b (RN26), N4b (RN24)", "xy_xexpand_0.05" => "N4, N4b (RN26), N4b (RN24)",
                         "tuple_pair" => "N4, N4b (RN26), N4b (RN24)", "region_CUS" => "N4, N4b (RN24)",
                         "xy_hawaii_not_CUS" => "N4, N4b (RN26), N4b (RN24)", "xy_outside_US" => "N4, N4b (RN26), N4b (RN24)")

# size, requested limits, projected extent (6 significant digits), base layers (label, points, alpha, linewidth, line style)
const MMPIN_EXPECTED = Dict(
    "xy_default" => (size = (600, 450), limits = ((-81.7145569, -77.0022001), (34.0198612, 36.2922268)), extent = ((-9.09642e6, 4.00756e6), (524577.0, 308049.0)), layers = Tuple[("Interstate Roads", 246969, 0.2, 0.6, "solid"), ("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "xy_xexpand_0.1" => (size = (600, 450), limits = ((-81.1255123, -77.5912447), (34.0198612, 36.2922268)), extent = ((-9.03085e6, 4.00756e6), (393433.0, 308049.0)), layers = Tuple[("Interstate Roads", 246969, 0.2, 0.6, "solid"), ("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "xy_xexpand_0.3" => (size = (600, 450), limits = ((-81.7145569, -77.0022001), (34.0198612, 36.2922268)), extent = ((-9.09642e6, 4.00756e6), (524577.0, 308049.0)), layers = Tuple[("Interstate Roads", 246969, 0.2, 0.6, "solid"), ("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "xy_xexpand_0.05" => (size = (600, 450), limits = ((-80.97825115, -77.73850585), (34.0198612, 36.2922268)), extent = ((-9.01446e6, 4.00756e6), (360647.0, 308049.0)), layers = Tuple[("Interstate Roads", 246969, 0.2, 0.6, "solid"), ("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "xy_both_expands" => (size = (600, 450), limits = ((-77.108, -76.892), (38.794, 38.956)), extent = ((-8.58362e6, 4.66543e6), (24045.0, 23070.0)), layers = Tuple[("Interstate Roads", 246969, 0.2, 0.6, "solid"), ("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "noroad_both_expands" => (size = (600, 450), limits = ((-122.6, -120.4), (36.0, 41.0)), extent = ((-1.36478e7, 4.2755e6), (244903.0, 708798.0)), layers = Tuple[("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "noroad_small_expands" => (size = (600, 450), limits = ((-80.88989446, -77.82686254), (34.17135224, 36.14073576)), extent = ((-9.00462e6, 4.02783e6), (340975.0, 266967.0)), layers = Tuple[("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "box_noroad_noexpand" => (size = (600, 450), limits = ((-78.688, -78.657), (35.762, 35.796)), extent = ((-8.75951e6, 4.24295e6), (3450.9, 4644.71)), layers = Tuple[("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "tuple_pair" => (size = (600, 450), limits = ((-80.5, -74.5), (34.5, 40.5)), extent = ((-8.96122e6, 4.07194e6), (667917.0, 839176.0)), layers = Tuple[("Interstate Roads", 246969, 0.2, 0.6, "solid"), ("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "region_CUS" => (size = (600, 450), limits = ((-125, -65), (24, 50)), extent = ((-1.39149e7, 2.73603e6), (6.67917e6, 3.67749e6)), layers = Tuple[("Interstate Roads", 246969, 0.35, 0.3, "solid"), ("US State Borders", 3642, 1.0, 0.75, "solid")]),
    "region_US" => (size = (600, 450), limits = ((-180, -65), (15, 72)), extent = ((-2.00375e7, 1.67815e6), (1.28017e7, 1.00343e7)), layers = Tuple[("US State Borders", 3642, 1.0, 0.75, "dashed"), ("Country Borders", 10947, 1.0, 0.75, "solid")]),
    "region_World" => (size = (600, 450), limits = ((-180, 180), (-75, 75)), extent = ((-2.00375e7, -1.28909e7), (4.0075e7, 2.57818e7)), layers = Tuple[("Country Borders", 10947, 1.0, 0.75, "solid")]),
    "xy_hawaii_not_CUS" => (size = (600, 450), limits = ((-158.9, -154.1), (18.7, 22.3)), extent = ((-1.76887e7, 2.10595e6), (534334.0, 425420.0)), layers = Tuple[("Interstate Roads", 246969, 0.2, 0.6, "solid"), ("US State Borders", 3642, 1.0, 0.75, "dashed"), ("Country Borders", 10947, 1.0, 0.75, "solid")]),
    "xy_outside_US" => (size = (600, 450), limits = ((-1.3, 16.3), (47.6, 52.4)), extent = ((-144715.0, 6.009e6), (1.95922e6, 829903.0)), layers = Tuple[("Interstate Roads", 246969, 0.2, 0.6, "solid"), ("Country Borders", 10947, 1.0, 0.75, "solid")]),
)

# two limit pairs or extents equal to 1e-9 relative (6 significant digits for the extent, which is rounded)
_mmpin_close(a, b; rtol) = all(isapprox(a[i][j], b[i][j]; rtol = rtol, atol = 0) for i in 1:2, j in 1:2)

@testset "makemap calls are pinned: size, limits, extent and base layers" begin
    cases = mmpin_cases()
    @test length(cases) == length(MMPIN_EXPECTED)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(MMPIN_EXPECTED, name)
            haskey(MMPIN_EXPECTED, name) || continue
            if haskey(MMPIN_MOVED, name)
                @info "map pin $name moved under $(MMPIN_MOVED[name])"
                continue
            end
            fig, ax = thunk()
            got, want = mmpin_describe(fig, ax), MMPIN_EXPECTED[name]
            @test got.size == want.size
            @test _mmpin_close(got.limits, want.limits; rtol = 1e-12)
            @test _mmpin_close(got.extent, want.extent; rtol = 1e-5)
            @test got.layers == want.layers
        end
    end
end

# 26 of 38 lecture `makemap` calls are followed by a resize!; the limits and the layers stay, the size follows
@testset "makemap figure survives resize!" begin
    fig, ax = makemap(mmpin_nc().LON, mmpin_nc().LAT; xexpand = 0.05)
    @test size(fig.scene) == (600, 450)
    resize!(fig, 900, 500)
    @test size(fig.scene) == (900, 500)
    @test _mmpin_close(ax.limits[], MMPIN_EXPECTED["xy_xexpand_0.05"].limits; rtol = 1e-12)
    @test [string(p.label[]) for p in ax.scene.plots if haskey(p.attributes, :label)] == ["Major Roads", "US State Borders"]   # N4b (RN26)
end

# The lectures from 3.2 on run `CairoMakie.activate!(px_per_unit = 2)` in their setup cell and then call makemap,
# which ran `CairoMakie.activate!()` on every call. Measured at 6df5d23 with CairoMakie 0.15.9, Makie 0.24.9: that
# call leaves px_per_unit, visible, inline and the active backend as the caller set them, and resets one thing, the
# image type to png (`activate!`'s default `type`). The course sets no type, so removing the call (K11a, P8) moves
# nothing a lecture sees. The type pin is the one K11a moves, as `makemap_activate_type` in MMPIN_MOVED: it is a
# mime-type state of CairoMakie that is left as the caller set it, which is the point.
_mmpin_screen() = Makie.merge_screen_config(CairoMakie.ScreenConfig, Dict{Symbol, Any}())
_mmpin_state() = (px_per_unit = _mmpin_screen().px_per_unit, visible = _mmpin_screen().visible,
                  inline = Makie.ALWAYS_INLINE_PLOTS[], backend = Makie.current_backend())
@testset "makemap leaves the caller's CairoMakie settings alone" begin
    orig = _mmpin_state()
    try
        CairoMakie.activate!(px_per_unit = 3, visible = false)       # the course sets px_per_unit = 2; 3 tells it from the default
        before = _mmpin_state()
        @test before.px_per_unit == 3 && before.visible == false
        fig, ax = makemap([-79.0, -78.0], [35.0, 36.0]; doRoadbkgd = false)
        @test _mmpin_state() == before                               # px_per_unit, visible, inline, backend
        @test size(Makie.colorbuffer(Figure(size = (200, 100)))) == (300, 600)    # px_per_unit 3 still draws at 3
        if isdefined(CairoMakie, :DISABLED_MIMES)
            @testset "makemap_activate_type" begin
                id = get(MMPIN_MOVED, "makemap_activate_type", "")
                CairoMakie.activate!(type = "svg", px_per_unit = 3, visible = false)
                svg = sort!(collect(CairoMakie.DISABLED_MIMES))
                makemap([-79.0, -78.0], [35.0, 36.0]; doRoadbkgd = false)
                after = sort!(collect(CairoMakie.DISABLED_MIMES))
                if isempty(id)
                    @test after == ["application/pdf", "image/svg+xml"] && after != svg    # today: makemap resets the type to png
                else
                    @test after == svg                                                     # moved: makemap leaves the type alone
                end
            end
        end
    finally
        CairoMakie.activate!(type = "png", px_per_unit = orig.px_per_unit, visible = orig.visible)
    end
end

# makemap(bb): the box method (PCV K11a, MAP, C6). `makemap(bb; doRoadbkgd = false)` is Lecture 4.2's
# `makemap(bb[1], bb[2]; doRoadbkgd = false, xexpand = 0, yexpand = 0)`, which the pins above hold.
@testset "[MAP] makemap(bb) draws the box mapbbox returns, with no expansion" begin
    want = MMPIN_EXPECTED["box_noroad_noexpand"]

    @testset "the figure and limits of 4.2's long form, against the pin" begin
        fig, ax = makemap(MMPIN_BB42; doRoadbkgd = false)
        got = mmpin_describe(fig, ax)
        @test got.limits == MMPIN_BB42                                   # the box, exactly
        @test got.size == want.size
        @test _mmpin_close(got.limits, want.limits; rtol = 1e-12)
        @test _mmpin_close(got.extent, want.extent; rtol = 1e-5)
        @test got.layers == want.layers
        # and equal to the long form it replaces, call for call
        fig2, ax2 = makemap(MMPIN_BB42[1], MMPIN_BB42[2]; doRoadbkgd = false, xexpand = 0, yexpand = 0)
        @test mmpin_describe(fig2, ax2) == got
    end

    @testset "mapbbox's box, and the box constants" begin
        nc = mmpin_nc()
        bb = mapbbox(nc.LON, nc.LAT; xexpand = 0.3, yexpand = 0.1)      # makemap(x, y)'s own expansion
        r1, r2 = makemap(bb), makemap(nc.LON, nc.LAT)                  # C4: the return is (; fig, ax, layers)
        @test mmpin_describe(r1.fig, r1.ax) == mmpin_describe(r2.fig, r2.ax)
        fig, ax = makemap(WORLD_LIMITS)                                  # a box of integers
        @test ax.limits[] == WORLD_LIMITS
        @test [string(p.label[]) for p in ax.scene.plots if haskey(p.attributes, :label)] == ["Country Borders"]
    end

    @testset "the other keywords are the vector method's" begin
        fig, ax = makemap(MMPIN_BB42; doRoadbkgd = false, showgrid = true)
        @test ax.xgridvisible[] == true
        fig, ax = makemap(((-80.5, -77.5), (35.0, 36.5)); roads = (; color = :red, alpha = 0.5))   # a box that draws the Interstates (S22: a box under 150 miles draws the network, in test_map_s22.jl)
        @test any(p -> haskey(p.attributes, :label) && string(p.label[]) == "Major Roads", ax.scene.plots)   # 3 degrees wide: the regional tier (N4b, RN26)
        @test_throws ArgumentError makemap(MMPIN_BB42; xexpand = 0.1)    # makemap(bb) never expands
        @test_throws ArgumentError makemap(MMPIN_BB42; yexpand = 0.1)
        @test_throws MethodError makemap(MMPIN_BB42; backend = :CairoMakie)
    end

    @testset "no ambiguity with the (x, y) forms" begin
        box = Base.which(makemap, Tuple{typeof(MMPIN_BB42)})
        xy = Base.which(makemap, Tuple{Tuple{Float64, Float64}, Tuple{Float64, Float64}})
        x1 = Base.which(makemap, Tuple{Tuple{Float64, Float64}})
        xv = Base.which(makemap, Tuple{Vector{Float64}, Vector{Float64}})
        @test box != xy && box != x1 && box != xv
        # the tuple pair is still two coordinate ranges, as pinned
        fig, ax = makemap((-80.0, -75.0), (35.0, 40.0); xexpand = 0.1)
        @test mmpin_describe(fig, ax).limits == MMPIN_EXPECTED["tuple_pair"].limits
    end
end

# ==== moved from test/test_makemap_c4.jl, its lines 1-248 ====
# test_makemap_c4.jl -- makemap's interface (PCV K11b, MAP, C4; CR 46, CR 56): one implementation that draws into a cell,
# `size`, the `roads` and `borders` keywords, the (; fig, ax, layers) return, and doRoadbkgd as a deprecated alias.
# The calls the course makes are pinned in test_map_pins.jl and test_map_line_pins.jl, from the code before this change;
# these tests check that the new forms give the same figures, and what is new.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie

isdefined(@__MODULE__, :mmpin_cases) || include(joinpath(@__DIR__, "map_pin_cases.jl"))

const _C4_INK = colorant"#252525"          # Lecture 5.3's ink

# the labeled base-layer plots of an axis: label => (RGBA, alpha attribute, linewidth, dashed?, points); a width for each
# point (N4's regional road tier) reads as its widest, the Interstate's (mmpin_width, map_pin_cases.jl)
function _c4_layers(ax)
    out = Pair[]
    for p in ax.scene.plots
        haskey(p.attributes, :label) || continue
        c = Makie.to_color(p.color[])
        push!(out, string(p.label[]) => (round.(Float64[Makie.Colors.red(c), Makie.Colors.green(c), Makie.Colors.blue(c), Makie.Colors.alpha(c)], digits = 4),
                                         round(Float64(p.alpha[]), digits = 4), round(Float64(mmpin_width(p.linewidth[])), digits = 4),
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
        @test string(layers.roads.label[]) == "Major Roads" && string(layers.states.label[]) == "US State Borders"   # N4b (RN26): NC's cities are the regional tier
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
            @test all(l -> l ∉ ("Interstate Roads", "Major Roads"), _c4_labels(d.ax)) && d.layers.roads === nothing
            e = makemap(x, y; doRoadbkgd = true, kw...)
            @test _c4_layers(e.ax) == _c4_layers(a.ax)
        end
        @test _c4_layers(makemap(region = :CUS, roads = :auto).ax) == _c4_layers(makemap(region = :CUS).ax)
    end

    @testset "roads = (; color, alpha, linewidth) overrides attributes of that layer" begin
        base = _c4_layers(makemap(nc.LON, nc.LAT).ax)[1][2]                    # the Interstate layer: 0.32, 0.7 (N4b, RN24)
        @test base[1] ≈ [0.2745, 0.5098, 0.7059, 0.32] atol = 1e-4
        @test base[3] == 0.7
        r = makemap(nc.LON, nc.LAT; roads = (; color = :steelblue, alpha = 0.5))   # README Example 2
        l = _c4_layers(r.ax)[1][2]
        @test l[1] ≈ [0.2745, 0.5098, 0.7059, 0.5] atol = 1e-4
        @test l[3] == 0.7 && l[5] == base[5]
        l = _c4_layers(makemap(nc.LON, nc.LAT; roads = (; color = :red)).ax)[1][2]   # the zoom's alpha stays
        @test l[1] == [1.0, 0.0, 0.0, 0.32] && l[3] == 0.7
        l = _c4_layers(makemap(nc.LON, nc.LAT; roads = (; linewidth = 2)).ax)[1][2]
        @test l[1] ≈ base[1] atol = 1e-4
        @test l[3] == 2.0
        l = _c4_layers(makemap(region = :CUS; roads = (; alpha = 0.9, linewidth = 1.0)).ax)[1][2]   # far zoom: 0.3 and 0.8 otherwise
        @test l[1][4] == 0.9 && l[3] == 1.0
        @test _c4_layers(makemap(nc.LON, nc.LAT; roads = (;)).ax) == _c4_layers(makemap(nc.LON, nc.LAT).ax)   # no override: :auto's
        # the layer is still the Interstate skeleton, drawn up to 30 degrees of span, with every point
        @test _c4_layers(makemap(nc.LON, nc.LAT; roads = (; color = :red)).ax)[1][2][5] == base[5]
        @test all(l -> l ∉ ("Interstate Roads", "Major Roads"), _c4_labels(makemap(region = :US; roads = (; color = :red)).ax))
        @test all(l -> l ∉ ("Interstate Roads", "Major Roads"), _c4_labels(makemap([-100.0, -90.0], [20.0, 50.5]; xexpand = 0, yexpand = 0, roads = (; color = :red)).ax))
        @test "Interstate Roads" ∈ _c4_labels(makemap([-100.0, -90.0], [20.0, 50.0]; xexpand = 0, yexpand = 0, roads = (; color = :red)).ax)
    end

    @testset "borders = true | false | (; color, linewidth)" begin
        @test _c4_layers(makemap(nc.LON, nc.LAT; borders = true).ax) == _c4_layers(makemap(nc.LON, nc.LAT).ax)
        for kw in ((region = :World,), (region = :US,), (region = :CUS,))
            r = makemap(; borders = false, kw...)
            @test r.layers.states === nothing && r.layers.countries === nothing
            @test all(l -> l ∉ ("US State Borders", "Country Borders"), _c4_labels(r.ax))
        end
        @test _c4_labels(makemap(nc.LON, nc.LAT; borders = false).ax) == ["Major Roads"]     # N4b (RN26)
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
        @test [l for l in new if l[1] == "Major Roads"] == [l for l in old if l[1] == "Major Roads"] && any(l -> l[1] == "Major Roads", new)   # the roads stay faded
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

# ==== moved from test/test_map_line_pins.jl, its lines 1-13, 31-186 ====
# test_map_line_pins.jl -- what the course sees of `plotroads!`, the base-layer styles `makemap` draws, the FAF5
# tables and `tracepath`, pinned from the code at 83c799b (PCV K11b, plan principle 9; K11a's own pins are
# test_map_pins.jl). The values below were measured on the unchanged code, before K11b's C4 (`makemap`'s interface),
# C8 (the line builders) and C12 (cached FAF5 tables) changed it. A call the course makes today keeps returning
# what it returned then; only a case named in MLPIN_MOVED may differ, and each one is named in the commit that moves it.
#
# No case touches the network or a file outside the package, and none renders a picture.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie
isdefined(@__MODULE__, :MLPIN_MOVED) || include(joinpath(@__DIR__, "map_line_pin_helpers.jl"))   # WP8: defined once

# ---- plotroads! on Lecture 2.5's call shape ------------------------------------------------------------------
# `for (k, v) in plotroads!(ax, faf5nodes(), faf5links())` (2-loc-5.qmd:175), on a map from `makemap(...; doRoadbkgd = false)`:
# the keys, each plot's point count, color (RGB), alpha, linewidth, cap and style, and the order the plots are drawn in.
function _mlpin_roads_describe(ax, h)
    rows = Tuple[]
    for k in sort!(collect(keys(h)); by = string)
        p = h[k]
        c = Makie.to_color(p.color[])
        push!(rows, (string(k), length(p[1][]),
                     round.(Float64[Makie.Colors.red(c), Makie.Colors.green(c), Makie.Colors.blue(c)], digits = 3),
                     round(Float64(p.alpha[]), digits = 3), round(Float64(p.linewidth[]), digits = 3), string(p.linecap[]),
                     p.linestyle[] === nothing ? "solid" : "dashed"))
    end
    order = sort!(collect(keys(h)); by = k -> findfirst(q -> q === h[k], ax.scene.plots))
    return rows, [string(k) for k in order]
end

const _MLPIN_TIERS_CLOSE = Tuple[
    ("casing_1", 511119, [0.35, 0.42, 0.52], 0.6, 1.6, "2", "solid"), ("casing_2", 209499, [0.45, 0.55, 0.4], 0.5, 1.5, "2", "solid"),
    ("casing_3", 378978, [0.65, 0.52, 0.3], 0.4, 1.3, "2", "solid"), ("casing_4", 185919, [0.6, 0.58, 0.48], 0.35, 1.1, "2", "solid"),
    ("casing_5", 165075, [0.65, 0.65, 0.65], 0.3, 0.9, "2", "solid"),
    ("fill_1", 511119, [0.6, 0.7, 0.82], 0.6, 1.0, "2", "solid"), ("fill_2", 209499, [0.72, 0.82, 0.72], 0.5, 0.9, "2", "solid"),
    ("fill_3", 378978, [0.9, 0.82, 0.7], 0.4, 0.7, "2", "solid"), ("fill_4", 185919, [0.92, 0.9, 0.8], 0.35, 0.5, "2", "solid"),
    ("fill_5", 165075, [0.95, 0.95, 0.95], 0.3, 0.3, "2", "solid"),
]
const _MLPIN_ORDER_CLOSE = ["casing_5", "casing_4", "casing_3", "casing_2", "casing_1", "fill_5", "fill_4", "fill_3", "fill_2", "fill_1"]
const _MLPIN_TIERS_MID = Tuple[
    ("fill_1", 511119, [0.6, 0.7, 0.82], 0.4, 0.7, "2", "solid"), ("fill_2", 209499, [0.72, 0.82, 0.72], 0.35, 0.6, "2", "solid"),
    ("fill_3", 378978, [0.9, 0.82, 0.7], 0.25, 0.4, "2", "solid"), ("fill_4", 185919, [0.92, 0.9, 0.8], 0.2, 0.3, "2", "solid"),
    ("fill_5", 165075, [0.95, 0.95, 0.95], 0.15, 0.15, "2", "solid"),
]
const _MLPIN_TIERS_FAR = Tuple[
    ("fill_1", 511119, [0.6, 0.7, 0.82], 0.25, 0.25, "2", "solid"), ("fill_2", 209499, [0.72, 0.82, 0.72], 0.2, 0.2, "2", "solid"),
    ("fill_3", 378978, [0.9, 0.82, 0.7], 0.15, 0.12, "2", "solid"), ("fill_4", 185919, [0.92, 0.9, 0.8], 0.1, 0.08, "2", "solid"),
    ("fill_5", 165075, [0.95, 0.95, 0.95], 0.08, 0.05, "2", "solid"),
]
const _MLPIN_ORDER_FILL = ["fill_5", "fill_4", "fill_3", "fill_2", "fill_1"]

# name => (call, latitude span of the axis, expected rows, expected draw order)
const MLPIN_ROADS = [
    ("metro_close",    () -> makemap([-78.9, -78.5], [35.6, 36.0]; xexpand = 0.02, yexpand = 0.02, doRoadbkgd = false), _MLPIN_TIERS_CLOSE, _MLPIN_ORDER_CLOSE),
    ("region_close",   () -> makemap([-84.0, -76.0], [33.0, 40.0]; xexpand = 0.02, yexpand = 0.02, doRoadbkgd = false), _MLPIN_TIERS_CLOSE, _MLPIN_ORDER_CLOSE),
    ("eastern_mid",    () -> makemap([-90.0, -70.0], [28.0, 44.0]; xexpand = 0.0, yexpand = 0.0, doRoadbkgd = false), _MLPIN_TIERS_MID, _MLPIN_ORDER_FILL),
    ("region_CUS_far", () -> makemap(region = :CUS, doRoadbkgd = false), _MLPIN_TIERS_FAR, _MLPIN_ORDER_FILL),
]

@testset "plotroads! on Lecture 2.5's call shape is pinned: keys, styles, point counts, draw order" begin
    dfN, dfL = faf5nodes(), faf5links()
    for (name, thunk, rows, order) in MLPIN_ROADS
        @testset "$name" begin
            _mlpin_moved("plotroads_" * name) && continue
            fig, ax = thunk()
            h = plotroads!(ax, dfN, dfL)
            @test h isa Dict{Symbol, Any}
            got, gorder = _mlpin_roads_describe(ax, h)
            @test got == rows
            @test gorder == order
        end
    end

    @testset "it iterates as k => v pairs and v.color can be reassigned, as dotmap does" begin
        if !_mlpin_moved("plotroads_dotmap_loop")
            fig, ax = makemap([-78.9, -78.5], [35.6, 36.0]; xexpand = 0.02, yexpand = 0.02, doRoadbkgd = false)
            n = 0
            for (k, v) in plotroads!(ax, dfN, dfL)                # 2-loc-5.qmd:175-178
                v.color = (:steelblue, startswith(String(k), "casing") ? 0.12 : 0.45)
                n += 1
                c = Makie.to_color(v.color[])
                @test Makie.Colors.alpha(c) ≈ (startswith(String(k), "casing") ? 0.12 : 0.45) atol = 1e-6
            end
            @test n == 10
            @test first(plotroads!(ax, dfN, dfL)) isa Pair{Symbol, Any}
        end
    end

    @testset "a small table: connectors hidden unless asked, drawn dashed when shown" begin
        if !_mlpin_moved("plotroads_connectors")
            fig, ax = makemap([-78.9, -78.5], [35.6, 36.0]; doRoadbkgd = false)
            dn = DataFrame(IDX = 1:4, LON = [-78.8, -78.7, -78.6, -78.55], LAT = [35.7, 35.8, 35.9, 35.95])
            dl = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], FCLASS = [1, 3, 6], SOURCE = ["FAF5", "OSM", "CONNECTOR"])
            h = plotroads!(ax, dn, dl)
            @test sort!(string.(keys(h))) == ["casing_1", "casing_3", "fill_1", "fill_3"]
            h = plotroads!(ax, dn, dl; show_connectors = true)
            @test sort!(string.(keys(h))) == ["casing_1", "casing_3", "connector", "fill_1", "fill_3"]
            r, _ = _mlpin_roads_describe(ax, h)
            @test r[3] == ("connector", 3, [0.549, 0.549, 0.549], 1.0, 0.3, "2", "dashed")
            @test r[4] == ("fill_1", 3, [0.6, 0.7, 0.82], 0.6, 1.0, "2", "solid")
        end
    end
end

# ---- the base layers makemap draws: color, alpha attribute, width, style, and the road layer's zoom tiers ----------
# (a width for each point, N4's regional road tier, reads as its widest, the Interstate's)
_mlpin_width(w) = w isa AbstractVector ? maximum(w) : w
function _mlpin_layers(ax)
    rows = Tuple[]
    for p in ax.scene.plots
        haskey(p.attributes, :label) || continue
        c = Makie.to_color(p.color[])
        push!(rows, (string(p.label[]),
                     round.(Float64[Makie.Colors.red(c), Makie.Colors.green(c), Makie.Colors.blue(c), Makie.Colors.alpha(c)], digits = 3),
                     round(Float64(p.alpha[]), digits = 3), round(Float64(_mlpin_width(p.linewidth[])), digits = 3),
                     p.linestyle[] === nothing ? "solid" : "dashed"))
    end
    return rows
end

# name => (call, expected layers: label, RGBA, `alpha` attribute, linewidth, style)
const MLPIN_LAYERS = [
    ("US_map",    () -> makemap(region = :US),
        Tuple[("US State Borders", [0.0, 0.0, 1.0, 1.0], 0.5, 0.75, "dashed"), ("Country Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("world_map", () -> makemap(),
        Tuple[("Country Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("CUS_map",   () -> makemap(region = :CUS),
        Tuple[("Interstate Roads", [0.275, 0.51, 0.706, 0.35], 1.0, 0.3, "solid"), ("US State Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("NC_frame",  () -> makemap([-80.0, -77.0], [35.0, 36.0]),
        Tuple[("Interstate Roads", [0.275, 0.51, 0.706, 0.2], 1.0, 0.6, "solid"), ("US State Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("Hawaii_frame", () -> makemap([-158.0, -155.0], [19.0, 22.0]),
        Tuple[("Interstate Roads", [0.275, 0.51, 0.706, 0.2], 1.0, 0.6, "solid"), ("US State Borders", [0.0, 0.0, 1.0, 1.0], 0.5, 0.75, "dashed"), ("Country Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("Europe_frame", () -> makemap([2.0, 13.0], [48.0, 52.0]),
        Tuple[("Interstate Roads", [0.275, 0.51, 0.706, 0.2], 1.0, 0.6, "solid"), ("Country Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
]

@testset "makemap's base-layer styles are pinned: color, alpha attribute, width, style" begin
    for (name, thunk, want) in MLPIN_LAYERS
        @testset "$name" begin
            _mlpin_moved("layers_" * name) && continue
            fig, ax = thunk()
            @test _mlpin_layers(ax) == want
        end
    end
end

# the road layer's tiers by latitude span (limits (-100, -90) x (y0, y0 + span), no expansion): alpha and width, and nothing past 30 degrees
const MLPIN_ROAD_TIERS = [   # span, y0 => (road alpha, road linewidth) or nothing when no road layer is drawn
    (9.0, 30.0, (0.2, 0.6)), (10.0, 30.0, (0.2, 0.6)), (10.5, 30.0, (0.25, 0.5)), (20.0, 30.0, (0.25, 0.5)),
    (20.5, 30.0, (0.35, 0.3)), (29.99, 20.0, (0.35, 0.3)), (30.0, 20.0, (0.35, 0.3)), (30.5, 20.0, nothing),
]

@testset "makemap's road layer by latitude span: today's tiers, nothing above 30 degrees" begin
    for (span, y0, want) in MLPIN_ROAD_TIERS
        @testset "span $span" begin
            _mlpin_moved("road_tier_$span") && continue
            fig, ax = makemap([-100.0, -90.0], [y0, y0 + span]; xexpand = 0, yexpand = 0)
            roads = [r for r in _mlpin_layers(ax) if r[1] == "Interstate Roads"]
            if want === nothing
                @test isempty(roads)
            else
                @test length(roads) == 1
                @test (roads[1][2][4], roads[1][4]) == want
                @test roads[1][2][1:3] == [0.275, 0.51, 0.706]
            end
        end
    end
end

# ==== moved from test/test_map_k11c_pins.jl, its lines 1-109 ====
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

isdefined(@__MODULE__, :k11cpin_cases) || include(joinpath(@__DIR__, "k11c_pin_cases.jl"))

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
                           # N4b (RN26): on the regional tier (every case below but Popco's two) the label is "Major Roads".
                           # N4b (RN24): the Interstate's opacity and width, regional 0.32 and 0.7, Popco's 0.32 and 0.85.
                           "nc_cities_default" => "N4, N4b (RN26), N4b (RN24)", "nc_cities_xe0.2" => "N4, N4b (RN26), N4b (RN24)",
                           "carolinas_xe0.1" => "N4, N4b (RN26), N4b (RN24)", "nc_counties_xe0.05" => "N4, N4b (RN26), N4b (RN24)",
                           "nc_counties_xe0.1" => "N4, N4b (RN26), N4b (RN24)", "popco_xe0.04" => "N4, N4b (RN24)",
                           "popco_default" => "N4, N4b (RN24)", "high_point_goldsboro" => "N4, N4b (RN26), N4b (RN24)",
                           "synthetic_tall_151" => "N4, N4b (RN26), N4b (RN24)", "synthetic_wide_151" => "N4, N4b (RN26), N4b (RN24)")

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

# ==== moved from test/test_map_s22.jl, its lines 1-189 ====
# test_map_s22.jl -- the road network on a small map (PCV K11c, S22 and S23). `roads = :auto` on a map 150 miles across
# or less draws the FAF5 network, cropped to the map, in one hue and below alpha 0.35; above 150 miles the layers are
# N4's tiers of the derived network (test_map_tiers.jl), K11b's before them (pinned in test_map_pins.jl,
# test_map_line_pins.jl and test_map_k11c_pins.jl, the cases N4 moved listed there).

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie

isdefined(@__MODULE__, :k11cpin_cases) || include(joinpath(@__DIR__, "k11c_pin_cases.jl"))

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
            @test !any(p -> haskey(p.attributes, :label) && string(p.label[]) in ("Interstate Roads", "Major Roads"), ax.scene.plots)
        end
        for name in ("synthetic_tall_151", "synthetic_wide_151")
            fig, ax, layers = Dict(k11cpin_synthetic())[name]()
            @test layers.roads isa Makie.Lines && string(layers.roads.label[]) == "Major Roads"   # N4b (RN26): regional
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
        # a ramp is a link core's one rule calls one (RN23, D2: the name rule, X TO Y, the C/D spellings and the structural
        # cluster test); v0.3.0's name rule, written out here independently, is the part of it every name catches
        ramp = Logjam._ramp_links(N, L)
        isname(nm) = !ismissing(nm) && (u = uppercase(string(nm));
            any(w -> occursin(Regex("\\b$w\\b"), u), ("RAMP", "RAMPS", "C/D LANE", "TURN LANE")) ||
            occursin("COLLECTOR/DISTRIBUTOR", replace(u, " " => "")) || occursin("CONNECTOR/DISTRIBUTOR", replace(u, " " => "")))
        @test count(isname, L.NAME) == 137156                                 # FAF5 as shipped
        @test !isname("N RAMPART ST") && !isname("AIRPORT CONNECTOR") && isname("SYSTEM RAMP - I 35 NB") &&
              isname("CA 65 NB CONNECTOR/DISTRIBUTOR LANE") && isname("I 405 COLLECTOR/DISTRIBUTOR LANE")
        @test all(ramp[isname.(L.NAME)]) && count(ramp) > 137156              # the core rule keeps v0.3.0's and adds to it
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
                if ramp[i]
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
                    @test layers.roads isa Makie.Lines && string(layers.roads.label[]) in ("Major Roads", "Interstate Roads")   # regional, national (N4b, RN26)
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

# ==== moved from test/test_map_tiers.jl, its lines 1-457 ====
# test_map_tiers.jl -- makemap's road layer in the tiers of his answer to Q2 (PCV N4, CR 19; MakePlan D8; test spec SC 5,
# T5.1 to T5.6). `roads = :auto` draws, on the box as drawn:
#   close     150 miles across or less (S22's measure, tested first): the FAF5 network, every class 1 to 5, every link
#             core's ramp rule calls a ramp left out (N4b, RN23), five Lines (S22, S23);
#   regional  otherwise, at most 10 degrees of latitude: Logjam's U.S. road network (usrdlink), classes 1 to 3, one Lines
#             labeled "Major Roads" (N4b, RN26);
#   national  otherwise, at most 30 degrees: that network's INTERSTATE links, one Lines;
#   none      more than 30 degrees: nothing.
# Runs after test_map_pins.jl, test_map_line_pins.jl and test_map_k11c_pins.jl, whose expected values and moved-cases
# dicts T5.6 reads.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie

isdefined(@__MODULE__, :k11cpin_cases) || include(joinpath(@__DIR__, "k11c_pin_cases.jl"))       # includes map_pin_cases.jl: mmpin_describe, mmpin_cases, k11c_*

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

# N4b (RN24, RN25): the Interstate's (opacity, width) at each of the latitude-span steps, from measured ink (the regional tier
# is `close`, the national `mid` and `far`), and classes 2 and 3 of the regional tier in these ratios of its width
const _T5_STYLE = (close = (0.32, 0.7), mid = (0.32, 0.85), far = (0.3, 0.8))
const _T5_CLASSW = (1.0, 0.3, 0.15)

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
        @test p isa Makie.Lines && string(p.label[]) == "Major Roads"                 # RN26
        w1 = _T5_STYLE.close[2]
        width = Dict(k => w1 * _T5_CLASSW[k] for k in 1:3)                          # classes 2 and 3 thinner (RN24)
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
        # close: the FAF5 network as S22 draws it (test_map_s22.jl checks the crop link by link), five classes, every link
        # core's ramp rule calls a ramp left out (RN23)
        fig, ax, layers = makemap(((-81.0, -80.7), (35.1, 35.35)))                # Charlotte, about 20 miles across
        @test layers.roads isa NamedTuple && keys(layers.roads) == (:class1, :class2, :class3, :class4, :class5)
        inbox = _t5_crop(fE, ax.limits[])
        ramp = Logjam._ramp_links(fN, fL)
        for (k, name) in enumerate(keys(layers.roads))
            got = Set((a, b) for (a, b, w) in _t5_pieces(layers.roads[name]))
            want = Set(_t5_seg(fE, i) for i in inbox if tierclass(fL.FCLASS[i]) == k && !ramp[i])
            @test got == want
        end
    end

    @testset "RN26 each tier's label" begin
        close = makemap(((-81.0, -80.7), (35.1, 35.35))).layers.roads
        labels = [string(p.label[]) for p in _t5_plots(close) if haskey(p.attributes, :label)]
        @test labels == ["FAF5 Roads"]                                              # the heaviest class carries it, as before
        @test string(close.class1.label[]) == "FAF5 Roads"
        @test string(makemap(_T5_NC).layers.roads.label[]) == "Major Roads"          # regional
        @test string(makemap(_T5_NATIONAL).layers.roads.label[]) == "Interstate Roads"   # national
        @test string(makemap(CUS_LIMITS).layers.roads.label[]) == "Interstate Roads"
    end

    @testset "T5.2 D8's boundary shapes: wide-and-short and narrow-and-tall, a hair under and over each line" begin
        # (the regional and national tiers' opacities are no longer told apart at 0.2 and 0.25, so the label tells them: RN26)
        shape(r) = r.layers.roads === nothing ? :none : r.layers.roads isa NamedTuple ? :close :
                   string(r.layers.roads.label[]) == "Major Roads" ? :regional : :national
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
        # close (RN23): no link core's ramp rule calls a ramp meets the drawn set, with a control: the boxes hold them
        nramps = 0
        for box in (((-81.0, -80.7), (35.1, 35.35)), ((-84.55, -84.25), (33.65, 33.9)), ((-79.2, -78.4), (35.5, 36.1)),
                    ((-79.9, -77.9), (35.2, 36.4)))
            r = makemap(box)
            got = Set((a, b) for p in _t5_plots(r.layers.roads) for (a, b, w) in _t5_pieces(p))
            inbox = _t5_crop(fE, box)
            # (a ramp link can share its two ends with a link that is not a ramp: FAF5 has such twins, and the twin is
            # drawn, so a ramp is read as drawn only if no link that is not a ramp lies on its segment)
            kept = Set(s for i in inbox if !ramp[i] for s in (_t5_seg(fE, i), reverse(_t5_seg(fE, i))))
            ramps = [_t5_seg(fE, i) for i in inbox if ramp[i] && _t5_seg(fE, i) ∉ kept]
            nramps += length(ramps)
            @test !isempty(got) && !any(in(got), ramps)
            # and v0.3.0's name rule, the part of it every name catches, is among them
            @test !any(in(got), [_t5_seg(fE, i) for i in _t5_crop(fE, box) if Logjam._isramp_v030(fL.NAME[i])])
        end
        @test nramps > 0
    end

    @testset "T5.4 the style: one hue, every stroke below 0.35, the classes by width, the Interstate on top" begin
        @test all(s -> 0 < s[1] < 0.35, _T5_STYLE) && _T5_STYLE.far[1] == 0.3                 # RN25: the 20-to-30 step's 0.3
        for (box, alpha, w1) in ((((-79.2, -78.4), (35.5, 36.1)), 0.3, 1.4), (_T5_NC, _T5_STYLE.close...),
                                 (_T5_NATIONAL, _T5_STYLE.mid...), (((-100.0, -90.0), (30.0, 50.0)), _T5_STYLE.mid...),
                                 (CUS_LIMITS, _T5_STYLE.far...), (_t5_tall_deg(29.99), _T5_STYLE.far...))
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
        w1 = _T5_STYLE.close[2]
        @test sort(unique(round.(w, digits = 4))) == round.(sort(w1 .* collect(_T5_CLASSW)), digits = 4)
        @test _T5_CLASSW[1] > _T5_CLASSW[2] > _T5_CLASSW[3] > 0                                # classes 2 and 3 thinner (RN24)
        @test Makie.to_color(layers.roads.color[]) isa Makie.Colorant     # one color, not one for each point: Lecture 5.3 reads `.alpha` of it
        # national: one Lines, one width; close: five, as S22 (test_map_s22.jl)
        @test makemap(_T5_NATIONAL).layers.roads.linewidth[] isa Real
        @test makemap(((-79.2, -78.4), (35.5, 36.1))).layers.roads isa NamedTuple
        # an empty map of a tier is a Lines with nothing in it (Western Europe: no road of the network)
        r = makemap([2.0, 13.0], [48.0, 52.0])
        @test r.layers.roads isa Makie.Lines && isempty(r.layers.roads[1][]) && r.layers.roads.linewidth[] ≈ _T5_STYLE.close[2]
        # roads = (; color, alpha, linewidth): the hue, the opacity, the Interstate's width (the other classes in ratio)
        r = makemap(_T5_NC; roads = (; color = :red, alpha = 0.5, linewidth = 2.0))
        @test _t5_rgb(r.layers.roads) == [1.0, 0.0, 0.0] && _t5_alpha(r.layers.roads) ≈ 0.5
        @test sort(unique(round.(Float64.(r.layers.roads.linewidth[]), digits = 4))) == round.(sort(2.0 .* collect(_T5_CLASSW)), digits = 4)
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
    # proxy before N4 (v0.3.0's layer), the proxy now). The close tier must not rise; it is FAF5's own links with core's
    # ramps left out (N4b, RN23), and the "before" of each close picture is computed again here from the FAF5 tables with
    # v0.3.0's name rule, so the rule holds on whatever the close tier draws. The regional and national values are a
    # record: classes 2 and 3 add roads; one line for each divided road removes the second carriageway. (Drawn from the
    # derived network, the close tier's proxies were 21, 22, 21, 11, 19, 21, 20, 23 and 27 in the order below: Charlotte,
    # Atlanta and the 12-mile box rose, which is why it is not.)
    mm, kc, sy = Dict(mmpin_cases()), Dict(k11cpin_cases()), Dict(k11cpin_synthetic())
    T5_PICTURES = [
        "s22_dwt_clinics"      => (kc["dwt_clinics_0.25"], :close, 27, 23),
        "s22_triangle_nodes"   => (kc["triangle_node_box"], :close, 29, 29),
        "s22_tall_149"         => (sy["synthetic_tall_149"], :close, 37, 37),
        "s22_wide_149"         => (sy["synthetic_wide_149"], :close, 21, 21),
        "charlotte_20mi"       => (() -> makemap(((-81.0, -80.7), (35.1, 35.35))), :close, 13, 12),
        "atlanta_20mi"         => (() -> makemap(((-84.55, -84.25), (33.65, 33.9))), :close, 17, 17),
        "raleigh_durham_55mi"  => (() -> makemap(((-79.2, -78.4), (35.5, 36.1))), :close, 26, 23),
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
        roadrow(l) = l[1] in ("Interstate Roads", "Major Roads")
        # the reasons a moved case carries (N4: the tiers; N4b: RN26, the regional label; RN24, the Interstate's opacity and width)
        isn4(v) = v == "N4" || startswith(v, "N4,")
        rn26(v) = occursin("N4b (RN26)", v)
        rn24(v) = occursin("N4b (RN24)", v)
        # test_map_pins.jl: the road layer as N4 and N4b draw it (label, points, opacity, the Interstate's width, style); the
        # regional tier's label is "Major Roads" (RN26), the national tier's "Interstate Roads"; opacity and width are RN24's
        reg(n) = ("Major Roads", n, _T5_STYLE.close..., "solid")
        N4_MMPIN = Dict(
            "xy_default"        => reg(9840),
            "xy_xexpand_0.1"    => reg(8223),
            "xy_xexpand_0.3"    => reg(9840),
            "xy_xexpand_0.05"   => reg(7689),
            "tuple_pair"        => reg(34692),
            "region_CUS"        => ("Interstate Roads", 81408, _T5_STYLE.far..., "solid"),
            "xy_hawaii_not_CUS" => reg(876),
            "xy_outside_US"     => reg(0),
        )
        @test sort([k for (k, v) in MMPIN_MOVED if isn4(v)]) == sort(collect(keys(N4_MMPIN)))
        @test all(((k, v),) -> !isn4(v) || (rn26(v) == (N4_MMPIN[k][1] == "Major Roads") && rn24(v)), MMPIN_MOVED)
        for (name, thunk) in mmpin_cases()
            @testset "map pin $name" begin
                fig, ax = thunk()
                got, want = mmpin_describe(fig, ax), MMPIN_EXPECTED[name]
                frame = got.size == want.size && _t5_close(got.limits, want.limits; rtol = 1e-12) &&
                        _t5_close(got.extent, want.extent; rtol = 1e-5)
                same = frame && got.layers == want.layers
                same || @test haskey(MMPIN_MOVED, name)                   # a case that differs is listed
                if isn4(get(MMPIN_MOVED, name, ""))
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
        @test sort([k for (k, v) in K11CPIN_MOVED if isn4(v)]) == sort(collect(keys(N4_K11C)))
        K11C_REGIONAL = ("nc_cities_default", "nc_cities_xe0.2", "carolinas_xe0.1", "nc_counties_xe0.05", "nc_counties_xe0.1",
                         "high_point_goldsboro", "synthetic_tall_151", "synthetic_wide_151")
        @test sort([k for (k, v) in K11CPIN_MOVED if rn26(v)]) == sort(collect(K11C_REGIONAL))
        @test all(((k, v),) -> !isn4(v) || rn24(v), K11CPIN_MOVED)
        for (name, thunk) in vcat(k11cpin_cases(), k11cpin_synthetic())
            @testset "K11c pin $name" begin
                fig, ax = thunk()
                got, want = mmpin_describe(fig, ax).layers, K11CPIN_EXPECTED[name].layers
                got == want || @test haskey(K11CPIN_MOVED, name)
                if isn4(get(K11CPIN_MOVED, name, ""))
                    @test got != want
                    @test filter(!roadrow, got) == filter(!roadrow, want)
                    regional = name in K11C_REGIONAL
                    # the points, the regional label, and the opacity and width (regional: close step; Popco's two: the mid step)
                    @test only(filter(roadrow, got)) == (regional ? "Major Roads" : "Interstate Roads", N4_K11C[name],
                                                         (regional ? _T5_STYLE.close : _T5_STYLE.mid)..., "solid")
                end
            end
        end
        # test_map_line_pins.jl: the road row of each moved case, pinned anew: (label, RGBA, `alpha` attribute, width, style)
        row(label, step) = (label, [0.275, 0.51, 0.706, step[1]], 1.0, step[2], "solid")
        N4_LAYERS = Dict("CUS_map" => row("Interstate Roads", _T5_STYLE.far), "NC_frame" => row("Major Roads", _T5_STYLE.close),
                         "Hawaii_frame" => row("Major Roads", _T5_STYLE.close), "Europe_frame" => row("Major Roads", _T5_STYLE.close))
        @test sort([k for (k, v) in MLPIN_MOVED if startswith(k, "layers_") && isn4(v)]) == ["layers_CUS_map"]
        @test sort([k for (k, v) in MLPIN_MOVED if startswith(k, "layers_")]) ==
              sort(["layers_" * n for n in keys(N4_LAYERS)])
        @test sort([k for (k, v) in MLPIN_MOVED if startswith(k, "road_tier_") && isn4(v)]) ==
              ["road_tier_20.5", "road_tier_29.99", "road_tier_30.0"]
        @test sort([k for (k, v) in MLPIN_MOVED if rn26(v)]) ==
              ["layers_Europe_frame", "layers_Hawaii_frame", "layers_NC_frame", "road_tier_10.0", "road_tier_9.0"]
        @test sort([k for (k, v) in MLPIN_MOVED if !rn24(v)]) == []
        for (name, thunk, want) in MLPIN_LAYERS
            got = _mlpin_layers(thunk()[2])
            got == want || @test haskey(MLPIN_MOVED, "layers_" * name)
            if haskey(MLPIN_MOVED, "layers_" * name)
                @test filter(!roadrow, got) == filter(!roadrow, want)
                @test only(filter(roadrow, got)) == N4_LAYERS[name]
            end
        end
        # the road layer by latitude span: (alpha, width) of each step, and the label of the tier
        for (span, y0, want) in MLPIN_ROAD_TIERS
            fig, ax = makemap([-100.0, -90.0], [y0, y0 + span]; xexpand = 0, yexpand = 0)
            roads = [r for r in _mlpin_layers(ax) if roadrow(r)]
            got = isempty(roads) ? nothing : (roads[1][2][4], roads[1][4])
            got == want || @test haskey(MLPIN_MOVED, "road_tier_$span")
            if haskey(MLPIN_MOVED, "road_tier_$span")
                step = span <= 10 ? _T5_STYLE.close : span <= 20 ? _T5_STYLE.mid : _T5_STYLE.far
                @test got == step && roads[1][1] == (span <= 10 ? "Major Roads" : "Interstate Roads")
            end
        end
    end
end

# ==== moved from test/test_plotroute.jl, its lines 1-274 ====
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

# ==== moved from test/test_plottools.jl, its lines 1-100 ====
using Test
using DataFrames
using Graphs
using SparseArrays

# Smoke test for dcf
@testset "dcf smoke test" begin
    fig = Figure()
    Axis(fig[1,1])
    dcf()
    @test true
end

# WP9 (v0.3.1, MAP17): dcf is deprecated and removed in v0.4.0. It still displays the current figure and returns
# nothing; its Base.depwarn names the replacements and the version, and prints only under --depwarn=yes (Pkg.test's
# setting, so here `@test_deprecated` sees the warning; under --depwarn=no it only runs the call).
@testset "[WP9] dcf is deprecated: it still displays, and its warning names fig and v0.4.0" begin
    fig = Figure()
    Axis(fig[1, 1])
    @test (@test_deprecated r"`dcf\(\)` is deprecated and is removed in Logjam v0\.4\.0" dcf()) === nothing
    @test (@test_deprecated r"end the cell with the figure, `fig`, or call `display\(current_figure\(\)\)`" dcf()) === nothing
    @test current_figure() === fig
    doc = string(@doc dcf)
    @test occursin("deprecated", doc) && occursin("v0.4.0", doc) && occursin("display(current_figure())", doc)
end

# ---------------------------------------------------------------------------
# makemap — code paths not covered in test_maptools.jl
# ---------------------------------------------------------------------------
@testset "makemap additional paths" begin

    @testset "doRoadbkgd toggle returns valid (Figure, GeoAxis)" begin
        # C3: hborders no longer returned; assert both paths yield a valid axis.
        fig, ax = makemap(region=:CUS; doRoadbkgd=false)
        @test fig isa Figure
        @test ax isa GeoAxis
        fig2, ax2 = makemap(region=:CUS; doRoadbkgd=true)
        @test fig2 isa Figure
        @test ax2 isa GeoAxis
    end

    @testset "Hawaii bbox (US but not CUS)" begin
        # Honolulu area: inside US_LIMITS but outside CUS_LIMITS
        x_hi = [-158.0, -155.0]
        y_hi = [19.0, 22.0]
        fig, ax = makemap(x_hi, y_hi)
        @test fig isa Figure
        @test ax isa GeoAxis
    end

    @testset "non-US region coordinates" begin
        # Western Europe: outside both US and CUS
        x_eu = [2.0, 13.0]
        y_eu = [48.0, 52.0]
        fig, ax = makemap(x_eu, y_eu)
        @test fig isa Figure
        @test ax isa GeoAxis
    end

    @testset "tuple coordinate input" begin
        fig, ax = makemap((-80.0, -75.0), (35.0, 40.0))
        @test fig isa Figure
        @test ax isa GeoAxis
    end
end

# ---------------------------------------------------------------------------
# plotroads! — additional validation tests
# ---------------------------------------------------------------------------
@testset "plotroads! additional" begin

    dfN_test = DataFrame(
        IDX = [1, 2, 3],
        LON = [-78.9, -78.5, -78.7],
        LAT = [35.8, 35.8, 36.0]
    )
    dfL_test = DataFrame(SRC=[1, 2], DST=[2, 3], SOURCE=["FAF5", "FAF5"])
    x_test = [-79.2, -78.4]
    y_test = [35.5, 36.1]

    @testset "out-of-bounds LON raises ArgumentError" begin
        dfN_bad = DataFrame(IDX=[1, 2], LON=[-78.9, 200.0], LAT=[35.8, 35.8])
        dfL_bad = DataFrame(SRC=[1], DST=[2])
        fig, ax = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_bad, dfL_bad)
    end

    @testset "out-of-bounds LAT raises ArgumentError" begin
        dfN_bad = DataFrame(IDX=[1, 2], LON=[-78.9, -78.5], LAT=[35.8, 95.0])
        dfL_bad = DataFrame(SRC=[1], DST=[2])
        fig, ax = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_bad, dfL_bad)
    end

    @testset "empty dfN raises ArgumentError" begin
        dfN_empty = DataFrame(IDX=Int[], LON=Float64[], LAT=Float64[])
        fig, ax = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_empty, dfL_test)
    end

    @testset "too few columns in dfN raises ArgumentError" begin
        dfN_narrow = DataFrame(IDX=[1, 2], LON=[-78.9, -78.5])
        dfL_bad = DataFrame(SRC=[1], DST=[2])
        fig, ax = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_narrow, dfL_bad)
    end

    @testset "too few columns in dfL raises ArgumentError" begin
        dfL_narrow = DataFrame(SRC=[1])
        fig, ax = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_test, dfL_narrow)
    end
end
