using Test
include("../src/MapTools.jl")
using .MapTools
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

# Test for makemap function (this will test if makemap runs without errors)
@testset "makemap tests" begin
    fig, ax, hborders, limits = makemap(region=:World)
    @test fig isa Figure
    @test ax isa GeoAxis
end

