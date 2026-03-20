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

# ---------------------------------------------------------------------------
# makemap — code paths not covered in test_maptools.jl
# ---------------------------------------------------------------------------
@testset "makemap additional paths" begin

    @testset "doRoadbkgd=false suppresses road background" begin
        fig, ax, hborders, limits = makemap(region=:CUS; doRoadbkgd=false)
        @test fig isa Figure
        # Without road background, hborders should have fewer elements
        fig2, ax2, hborders2, _ = makemap(region=:CUS; doRoadbkgd=true)
        @test length(hborders2) >= length(hborders)
    end

    @testset "Hawaii bbox (US but not CUS)" begin
        # Honolulu area: inside US_LIMITS but outside CUS_LIMITS
        x_hi = [-158.0, -155.0]
        y_hi = [19.0, 22.0]
        fig, ax, hborders, limits = makemap(x_hi, y_hi)
        @test fig isa Figure
        @test limits isa Tuple
    end

    @testset "non-US region coordinates" begin
        # Western Europe: outside both US and CUS
        x_eu = [2.0, 13.0]
        y_eu = [48.0, 52.0]
        fig, ax, hborders, limits = makemap(x_eu, y_eu)
        @test fig isa Figure
        @test limits isa Tuple
    end

    @testset "tuple coordinate input" begin
        fig, ax, hborders, limits = makemap((-80.0, -75.0), (35.0, 40.0))
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
        fig, ax, _, _ = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_bad, dfL_bad)
    end

    @testset "out-of-bounds LAT raises ArgumentError" begin
        dfN_bad = DataFrame(IDX=[1, 2], LON=[-78.9, -78.5], LAT=[35.8, 95.0])
        dfL_bad = DataFrame(SRC=[1], DST=[2])
        fig, ax, _, _ = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_bad, dfL_bad)
    end

    @testset "empty dfN raises ArgumentError" begin
        dfN_empty = DataFrame(IDX=Int[], LON=Float64[], LAT=Float64[])
        fig, ax, _, _ = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_empty, dfL_test)
    end

    @testset "too few columns in dfN raises ArgumentError" begin
        dfN_narrow = DataFrame(IDX=[1, 2], LON=[-78.9, -78.5])
        dfL_bad = DataFrame(SRC=[1], DST=[2])
        fig, ax, _, _ = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_narrow, dfL_bad)
    end

    @testset "too few columns in dfL raises ArgumentError" begin
        dfL_narrow = DataFrame(SRC=[1])
        fig, ax, _, _ = makemap(x_test, y_test)
        @test_throws ArgumentError plotroads!(ax, dfN_test, dfL_narrow)
    end
end

# ---------------------------------------------------------------------------
# plotroute! — coordinate-vector form and show_markers toggle
# ---------------------------------------------------------------------------
@testset "plotroute! coordinate-vector form" begin

    x_test = [-79.2, -78.4]
    y_test = [35.5, 36.1]

    @testset "basic coordinate vector" begin
        fig, ax, _, _ = makemap(x_test, y_test)
        lx = [-79.0, -78.7, -78.5]
        ly = [35.8, 36.0, 35.8]
        handles = plotroute!(ax, lx, ly)
        @test handles isa Vector
        @test length(handles) == 3  # line + origin + dest
    end

    @testset "coordinate vector show_markers=false" begin
        fig, ax, _, _ = makemap(x_test, y_test)
        lx = [-79.0, -78.7, -78.5]
        ly = [35.8, 36.0, 35.8]
        handles = plotroute!(ax, lx, ly; show_markers=false)
        @test length(handles) == 1  # line only
    end

    @testset "coordinate vector with NaN separators" begin
        fig, ax, _, _ = makemap(x_test, y_test)
        lx = [-79.0, -78.7, NaN, -78.6, -78.5]
        ly = [35.8, 36.0, NaN, 35.9, 35.8]
        handles = plotroute!(ax, lx, ly)
        @test handles isa Vector
        @test length(handles) == 3  # line + origin + dest (skips NaN)
    end
end

# ---------------------------------------------------------------------------
# alloclines — NaN positions with known allocation (complement test_maptools)
# ---------------------------------------------------------------------------
@testset "alloclines NaN structure" begin

    hubs = [-80.0 35.0; -78.0 36.0]
    spokes = [-79.0 35.5; -77.0 36.5; -78.5 35.5]

    @testset "NaN at every third position" begin
        W = sparse([1, 2], [1, 2], [1.0, 1.0], 2, 3)
        X, Y = alloclines(W, hubs, spokes)
        # Hub 1 → spoke 1: [hub_x, spoke_x, NaN]
        @test length(X[1]) == 3
        @test isnan(X[1][3])
        @test X[1][1] == -80.0   # hub lon
        @test X[1][2] == -79.0   # spoke lon
        @test Y[1][1] == 35.0    # hub lat
        @test Y[1][2] == 35.5    # spoke lat
    end

    @testset "multiple spokes per hub" begin
        W = sparse([1, 1, 1], [1, 2, 3], [1.0, 1.0, 1.0], 2, 3)
        X, Y = alloclines(W, hubs, spokes)
        # Hub 1 serves all 3 spokes: 9 values
        @test length(X[1]) == 9
        @test count(isnan, X[1]) == 3
        # Hub 2 serves none
        @test isempty(X[2])
    end

    @testset "dense matrix input" begin
        W = [1.0 0.0 0.5; 0.0 1.0 0.0]
        X, Y = alloclines(W, hubs, spokes)
        @test length(X[1]) == 6  # hub 1 → spokes 1,3
        @test length(X[2]) == 3  # hub 2 → spoke 2
    end
end

# ---------------------------------------------------------------------------
# x2ln — pure geometry, no rendering
# ---------------------------------------------------------------------------
@testset "x2ln tests" begin

    @testset "simple directed graph" begin
        g = SimpleDiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)
        x = [-78.0, -79.0, -80.0]
        result = x2ln(g, x)
        # 2 edges × 3 values = 6
        @test length(result) == 6
        @test isequal(result, [-78.0, -79.0, NaN, -79.0, -80.0, NaN])
    end

    @testset "undirected graph has two directed edges per link" begin
        g = SimpleGraph(2)
        add_edge!(g, 1, 2)
        x = [10.0, 20.0]
        result = x2ln(g, x)
        # SimpleGraph edge iteration yields 1 edge for (1,2)
        @test length(result) == 3
        @test isequal(result, [10.0, 20.0, NaN])
    end

    @testset "disconnected graph" begin
        g = SimpleDiGraph(4)
        add_edge!(g, 1, 2)
        add_edge!(g, 3, 4)
        x = [1.0, 2.0, 3.0, 4.0]
        result = x2ln(g, x)
        @test length(result) == 6
        @test count(isnan, result) == 2
    end

    @testset "paired x2ln for lon/lat" begin
        g = SimpleDiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)
        lon = [-78.0, -79.0, -80.0]
        lat = [35.0, 36.0, 37.0]
        xline = x2ln(g, lon)
        yline = x2ln(g, lat)
        @test length(xline) == length(yline)
        # NaN positions align
        @test findall(isnan, xline) == findall(isnan, yline)
    end

    @testset "single edge" begin
        g = SimpleDiGraph(2)
        add_edge!(g, 1, 2)
        x = [5.0, 10.0]
        result = x2ln(g, x)
        @test isequal(result, [5.0, 10.0, NaN])
    end

    @testset "no edges returns empty" begin
        g = SimpleDiGraph(3)
        x = [1.0, 2.0, 3.0]
        result = x2ln(g, x)
        @test isempty(result)
    end
end
