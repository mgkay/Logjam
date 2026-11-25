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

include(joinpath(@__DIR__, "map_pin_cases.jl"))

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
