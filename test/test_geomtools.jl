# test_geomtools.jl -- the tests of src/geomtools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_maptools.jl, its lines 1-1, 123-199 ====
using Test

# Test for alloclines function
@testset "alloclines tests" begin
    using SparseArrays

    hubs = [-80.0 35.0; -78.0 36.0]
    spokes = [-80.5 35.2; -78.5 35.8; -79.2 36.1]

    @testset "basic functionality" begin
        W = sparse([1, 1, 2], [1, 2, 3], [1.0, 1.0, 1.0], 2, 3)
        X, Y = alloclines(W, hubs, spokes)

        @test length(X) == 2  # One per hub
        @test length(Y) == 2
        @test X isa Vector{Vector{Float64}}
        # Hub 1 serves spokes 1,2 → 6 values (2 segments × 3)
        @test length(X[1]) == 6
        # Hub 2 serves spoke 3 → 3 values (1 segment × 3)
        @test length(X[2]) == 3
    end

    @testset "threshold filtering" begin
        W = [1.0 1e-10 0.5; 0.0 1.0 0.5]
        # Default threshold filters out 1e-10
        X1, Y1 = alloclines(W, hubs, spokes)
        @test length(X1[1]) == 6  # hub 1: spokes 1,3
        @test length(X1[2]) == 6  # hub 2: spokes 2,3

        # Lower threshold includes near-zero
        X2, Y2 = alloclines(W, hubs, spokes; tol=1e-12)
        @test length(X2[1]) == 9  # hub 1: spokes 1,2,3
    end

    @testset "dimension validation" begin
        W = sparse([1], [1], [1.0], 2, 3)
        bad_hubs = [-80.0 35.0]  # 1 row, need 2
        @test_throws ArgumentError alloclines(W, bad_hubs, spokes)

        bad_spokes = [-80.5 35.2; -78.5 35.8]  # 2 rows, need 3
        @test_throws ArgumentError alloclines(W, hubs, bad_spokes)

        bad_coords = [-80.0 35.0 0.0; -78.0 36.0 0.0]  # 3 columns
        @test_throws ArgumentError alloclines(W, bad_coords, spokes)
    end

    @testset "empty allocation" begin
        W = spzeros(2, 3)
        X, Y = alloclines(W, hubs, spokes)
        @test length(X) == 2
        @test isempty(X[1])
        @test isempty(X[2])
    end

    @testset "concatenation with reduce(vcat, ...)" begin
        W = sparse([1, 1, 2], [1, 2, 3], [1.0, 1.0, 1.0], 2, 3)
        X, Y = alloclines(W, hubs, spokes)
        xflat = reduce(vcat, X)
        yflat = reduce(vcat, Y)
        @test length(xflat) == 9  # 3 segments × 3 values
        @test sum(isnan.(xflat)) == 3
    end

    @testset "integration with ufl" begin
        k = [10.0, 10.0, 15.0]
        C = [0.0 3.0 7.0; 3.0 0.0 4.0; 7.0 4.0 0.0]
        y, TC, W = ufl(k, C; verbose=false)

        hub_xy = [-80.0 35.0; -78.0 36.0; -79.0 35.5]
        spoke_xy = [-80.5 35.2; -78.5 35.8; -79.2 36.1]

        X, Y = alloclines(W, hub_xy, spoke_xy)
        @test length(X) == 3
        # Total segments should equal number of customers (3)
        total_segments = sum(count(isnan, x) for x in X)
        @test total_segments == 3
    end
end

# ==== moved from test/test_datatools.jl, its lines 1-2, 374-390 ====
using Test
using DataFrames


# ─── isptinbbox is removed (P8, 0 course calls) ────────────────────
@testset "isptinbbox is gone" begin
    @test !isdefined(Logjam, :isptinbbox)
end

# ─── Relocated: alloclines (from maptools) ────────────────────────
@testset "alloclines relocated" begin
    using SparseArrays
    hubs = [-80.0 35.0; -78.0 36.0]
    spokes = [-80.5 35.2; -78.5 35.8; -79.2 36.1]
    W = sparse([1, 1, 2], [1, 2, 3], [1.0, 1.0, 1.0], 2, 3)
    X, Y = alloclines(W, hubs, spokes)
    @test length(X) == 2
    @test X isa Vector{Vector{Float64}}
end

# ==== moved from test/test_plottools.jl, its lines 1-4, 101-140 ====
using Test
using DataFrames
using Graphs
using SparseArrays

# plotroute! is tested in test_plotroute.jl (PCV K11a, D2)

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
