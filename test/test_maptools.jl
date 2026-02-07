using Test
using GeoMakie

# Test for WORLD_LIMITS, US_LIMITS, and CUS_LIMITS constants
@test WORLD_LIMITS == ((-180, 180), (-75, 75))
@test US_LIMITS == ((-180, -65), (15, 72))
@test CUS_LIMITS == ((-125, -65), (24, 50))

# Test for mapbbox function
@testset "mapbbox tests" begin
    x = [-80.0, -75.0, -78.0]
    y = [35.0, 40.0, 38.0]
    expanded_bbox, original_bbox = mapbbox(x, y, xexpand=0.1, yexpand=0.1)

    @test original_bbox == ((-80.0, -75.0), (35.0, 40.0))
    @test expanded_bbox[1] != original_bbox[1]  # x limits should be expanded
    @test expanded_bbox[2] != original_bbox[2]  # y limits should be expanded
end

@testset "mapbbox all-NaN input" begin
    x = [NaN, NaN]
    y = [NaN, NaN]
    @test_throws ArgumentError mapbbox(x, y)
end

# Test for aligntext function
@testset "aligntext tests" begin
    x = [1.0, 2.0]
    y = [3.0, 4.0]
    result = aligntext(x, y)

    align_result = first(result)   # This will give you the `:align` => alignout Pair
    offset_result = last(result)   # This will give you the `:offset` => offsetout Pair
    
    @test align_result.first == :align  # Ensure the first Pair is the :align one
    @test length(align_result.second) == 2  # Now, check the length of the align array
    
    @test offset_result.first == :offset  # Ensure the second Pair is the :offset one
    @test length(offset_result.second) == 2  # Now, check the length of the offset array
end

# Test for isptinbbox function
@testset "isptinbbox tests" begin
    bbox = ((-180, 180), (-90, 90))
    pt_inside = (0, 0)
    pt_outside = (200, 100)

    @test isptinbbox(pt_inside, bbox) == true
    @test isptinbbox(pt_outside, bbox) == false
end

# Test for makemap function
@testset "makemap tests" begin
    # Test different regions
    @testset "region=$region" for region in [:World, :US, :CUS]
        fig, ax, hborders, limits = makemap(region=region)
        @test fig isa Figure
        @test ax isa GeoAxis
        @test hborders isa Vector
        @test limits isa Tuple
    end

    # Test with coordinate inputs
    @testset "coordinate inputs" begin
        x = [-80.0, -75.0, -78.0]
        y = [35.0, 40.0, 38.0]
        fig, ax, hborders, limits = makemap(x, y)
        @test fig isa Figure
        @test ax isa GeoAxis
    end

    # Test invalid backend error message
    @testset "invalid backend error" begin
        @test_throws ErrorException makemap(backend=:InvalidBackend)
    end

    # Test GLMakie backend without loading GLMakie
    @testset "GLMakie not loaded error" begin
        if !Logjam._glmakie_available[]
            err = try
                makemap(backend=:GLMakie)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("GLMakie", err.msg)
        end
    end
end

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
