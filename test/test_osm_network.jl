using Test
using LightOSM, Logjam
using DataFrames, Graphs, CSV
using CairoMakie, GeoMakie

# The folder the downloaded tiles are written to and read from. Environment-only: unset, the file is skipped
# (it also needs LOGJAM_NETWORK_TESTS, which runtests.jl reads, and it queries the public Overpass server).
const TEST_CACHE_DIR = get(ENV, "LOGJAM_TEST_CACHE_DIR", "")
const GAINESVILLE_BBOX = (-82.45, -82.20, 29.55, 29.75)

if isempty(TEST_CACHE_DIR)
    @info "test_osm_network.jl skipped: set LOGJAM_TEST_CACHE_DIR to a folder for the downloaded tiles"
else
@testset "OSM2Logjam" begin

    # =========================================================================
    # T1: Extension Loading
    # =========================================================================
    @testset "T1: Extension Loading" begin
        @test Base.get_extension(Logjam, :LogjamOSMExt) !== nothing
    end

    # =========================================================================
    # T3: OSM Download and Translation — Schema
    # =========================================================================
    local dfN, dfL
    @testset "T3: Schema Validation" begin
        dfN, dfL = osm_roads(GAINESVILLE_BBOX; cache_dir=TEST_CACHE_DIR)

        # Nodes schema
        @test "IDX" in names(dfN)
        @test "LON" in names(dfN)
        @test "LAT" in names(dfN)
        @test "SOURCE" in names(dfN)
        @test eltype(dfN.IDX) <: Integer
        @test eltype(dfN.LON) <: AbstractFloat
        @test eltype(dfN.LAT) <: AbstractFloat
        @test nrow(dfN) > 0
        @test !any(ismissing, dfN.IDX)
        @test !any(ismissing, dfN.LON)
        @test !any(ismissing, dfN.LAT)

        # Links schema
        @test "SRC" in names(dfL)
        @test "DST" in names(dfL)
        @test "DIST" in names(dfL)
        @test "SPEED" in names(dfL)
        @test "FCLASS" in names(dfL)
        @test "DIR" in names(dfL)
        @test "NAME" in names(dfL)
        @test "SOURCE" in names(dfL)
        @test eltype(dfL.SRC) <: Integer
        @test eltype(dfL.DST) <: Integer
        @test eltype(dfL.DIST) <: AbstractFloat
        @test nrow(dfL) > 0
        @test all(dfL.DIST .> 0)
        @test all(dfL.SOURCE .== "OSM")
        @test all(s -> s > 0, dfL.SPEED)           # a posted speed, else the class's
        @test all(f -> f in 1:7, dfL.FCLASS)
    end

    # =========================================================================
    # T4: Coordinate Swap
    # =========================================================================
    @testset "T4: Coordinate Swap" begin
        # Gainesville: ~29.65°N, ~82.32°W
        @test all(dfN.LON .< 0)   # Western hemisphere
        @test all(dfN.LAT .> 0)   # Northern hemisphere
        @test all(-83 .< dfN.LON .< -82)
        @test all(29 .< dfN.LAT .< 30)
    end

    # =========================================================================
    # T5: Pipeline Integration
    # =========================================================================
    @testset "T5: Pipeline Integration" begin
        g = links2graph(dfL; weight=:DIST)
        @test nv(g) == nrow(dfN)
        D, P = shortestpaths(g, 5)
        @test size(D) == (5, 5)
        @test all(D[i, i] == 0.0 for i in 1:5)
        @test all(isfinite.(D[1, 2:5]))
        @test all(D[1, 2:5] .> 0)
    end

    # =========================================================================
    # T6: CSV Caching — Write
    # =========================================================================
    @testset "T6: CSV Caching Write" begin
        nodes_path, links_path = Logjam._osm_cache_path(GAINESVILLE_BBOX, TEST_CACHE_DIR)
        @test isfile(nodes_path)
        @test isfile(links_path)
        @test filesize(nodes_path) > 0
        @test filesize(links_path) > 0
    end

    # =========================================================================
    # T7: CSV Caching — Read
    # =========================================================================
    @testset "T7: CSV Caching Read" begin
        dfN2, dfL2 = osm_roads(GAINESVILLE_BBOX; cache_dir=TEST_CACHE_DIR)
        @test nrow(dfN2) == nrow(dfN)
        @test nrow(dfL2) == nrow(dfL)
        @test sum(dfN2.LON) ≈ sum(dfN.LON)
    end

    # =========================================================================
    # T14: Visualization (non-error check only)
    # =========================================================================
    @testset "T14: Visualization" begin
        lons = dfN.LON
        lats = dfN.LAT
        fig, ax = makemap(lons, lats)
        handles = plotroads!(ax, dfN, dfL)
        @test length(handles) > 0
    end

    # =========================================================================
    # E1: Empty Overpass Result
    # =========================================================================
    @testset "E1: Empty/Ocean Bbox" begin
        ocean_bbox = (-50.0, -49.99, 30.0, 30.01)  # Middle of Atlantic
        @test_throws ErrorException osm_roads(ocean_bbox; cache_dir=tempdir())
    end

end
end
