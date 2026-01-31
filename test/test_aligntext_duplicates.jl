# Test cases for aligntext duplicate point handling
#
# When multiple labels share the same coordinates, they should all receive
# different alignments to avoid overlapping each other.

using Test
using Logjam

@testset "aligntext duplicate point handling" begin

    # Test: Simple duplicate points - should distribute evenly
    @testset "two labels at same location get opposite alignments" begin
        x = [-83.37, -84.0, -83.37, -85.0]  # indices 1 and 3 are duplicates
        y = [42.493, 43.0, 42.493, 44.0]

        result = aligntext(x, y)
        aligns = result[1].second
        offsets = result[2].second

        @test length(aligns) == 4
        @test length(offsets) == 4

        # Indices 1 and 3 are at same location - should have different alignments
        @test aligns[1] != aligns[3]
    end

    # Test: Three labels at same location
    @testset "three labels at same location get distributed alignments" begin
        x = [-83.0, -83.0, -83.0, -85.0]  # indices 1,2,3 are duplicates
        y = [42.0, 42.0, 42.0, 44.0]

        result = aligntext(x, y)
        aligns = result[1].second

        @test length(aligns) == 4
        # All three at same location should have different alignments
        @test length(unique([aligns[1], aligns[2], aligns[3]])) >= 2
    end

    # Test: Larger dataset with duplicates at indices 11 and 47
    @testset "larger dataset with duplicates" begin
        x = collect(range(-85.0, -80.0, length=50))
        y = collect(range(40.0, 45.0, length=50))
        # Set indices 11 and 47 to identical coordinates
        x[11] = -83.37
        y[11] = 42.493
        x[47] = -83.37
        y[47] = 42.493

        result = aligntext(x, y)
        aligns = result[1].second
        offsets = result[2].second

        @test length(aligns) == 50
        @test length(offsets) == 50
        # Duplicates should have different alignments
        @test aligns[11] != aligns[47]
    end

    # Test: All points at same location
    @testset "all points at same location" begin
        x = [-83.0, -83.0, -83.0, -83.0]
        y = [42.0, 42.0, 42.0, 42.0]

        result = aligntext(x, y)
        aligns = result[1].second

        @test length(aligns) == 4
        # Should distribute around compass (90° apart for 4 points)
        @test length(unique(aligns)) >= 2  # At least some different alignments
    end

    # Test: Two points at same location (edge case)
    @testset "two duplicate points only" begin
        x = [-83.37, -83.37]
        y = [42.493, 42.493]

        result = aligntext(x, y)
        aligns = result[1].second

        @test length(aligns) == 2
        # Should be opposite alignments (180° apart)
        @test aligns[1] != aligns[2]
    end

    # Test: No duplicates should work normally
    @testset "no duplicates works normally" begin
        x = [-78.6382, -80.8431, -79.7919, -80.2442]
        y = [35.7796, 35.2271, 36.0726, 36.0999]

        result = aligntext(x, y)
        @test result[1].first == :align
        @test length(result[1].second) == 4
    end

    # Test: Single point
    @testset "single point" begin
        result = aligntext([-83.0], [42.0])
        @test result[1].second == (:left, :bottom)
    end

end
