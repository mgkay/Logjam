using Test
using LightOSM, NearestNeighbors, Logjam
using DataFrames, Graphs, CSV
using CairoMakie, GeoMakie

const TEST_CACHE_DIR = raw"C:\Users\kay\Documents\cdev\log\makeLogjam\data"
const GAINESVILLE_BBOX = (-82.45, -82.20, 29.55, 29.75)

@testset "OSM2Logjam" begin

    # =========================================================================
    # T1: Extension Loading
    # =========================================================================
    @testset "T1: Extension Loading" begin
        @test Logjam._osm_available[] == true
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
        @test all(s -> s in values(Logjam.OSM_SPEED_DEFAULTS), dfL.SPEED)
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
    # T8: Large Region Warning
    # =========================================================================
    @testset "T8: Large Region Warning" begin
        # Test that the area threshold triggers a warning
        # Use a large bbox but pre-cache empty CSVs to avoid actual download
        big_bbox = (-85.0, -80.0, 25.0, 30.0)
        np, lp = Logjam._osm_cache_path(big_bbox, tempdir())
        CSV.write(np, DataFrame(IDX=Int[], LON=Float64[], LAT=Float64[], SOURCE=String[]))
        CSV.write(lp, DataFrame(SRC=Int[], DST=Int[], DIST=Float64[], SPEED=Int[],
                                FCLASS=Int[], DIR=Int[], NAME=String[], SOURCE=String[]))
        @test_warn "Large bounding box" osm_roads(big_bbox; cache_dir=tempdir())
        rm(np; force=true)
        rm(lp; force=true)
    end

    # =========================================================================
    # T9–T12: Network Stitching
    # =========================================================================
    local dfN_stitched, dfL_stitched
    @testset "T9: Stitching Basic Connectivity" begin
        dfN_faf = faf5nodes()
        dfL_faf = faf5links()
        dfN_fl, dfL_fl = cropnetwork(dfN_faf, dfL_faf, [-87.0, -80.0], [24.5, 31.0])
        dfL_fl.SOURCE = fill("FAF5", nrow(dfL_fl))
        dfN_fl.SOURCE = fill("FAF5", nrow(dfN_fl))

        dfN_stitched, dfL_stitched = stitchnetworks(dfN_fl, dfL_fl, dfN, dfL)

        sources = unique(dfL_stitched.SOURCE)
        @test "FAF5" in sources
        @test "OSM" in sources
        @test "CONNECTOR" in sources
        @test nrow(dfN_stitched) > nrow(dfN_fl)
        @test nrow(dfN_stitched) > nrow(dfN)
    end

    @testset "T10: FCLASS Filtering" begin
        conn = filter(row -> row.SOURCE == "CONNECTOR", dfL_stitched)
        @test nrow(conn) > 0
        @test all(conn.FCLASS .== 99)
    end

    @testset "T11: Directionality" begin
        conn = filter(row -> row.SOURCE == "CONNECTOR", dfL_stitched)
        @test all(d -> d in (0, 1), conn.DIR)
    end

    @testset "T12: Topology Validation" begin
        g = links2graph(dfL_stitched; weight=:DIST)
        @test nv(g) == nrow(dfN_stitched)
        @test ne(g) > 0

        # Find an OSM-interior node and a FAF5-interior node
        osm_nodes = filter(r -> r.SOURCE == "OSM", dfN_stitched)
        faf_nodes = filter(r -> r.SOURCE == "FAF5", dfN_stitched)
        @test nrow(osm_nodes) > 0
        @test nrow(faf_nodes) > 0
    end

    # =========================================================================
    # T14: Visualization (non-error check only)
    # =========================================================================
    @testset "T14: Visualization" begin
        lons = dfN_stitched.LON
        lats = dfN_stitched.LAT
        fig, ax = makemap(lons, lats)
        handles = plotroads!(ax, dfL_stitched, dfN_stitched)
        @test length(handles) > 0
    end

    # =========================================================================
    # E1: Empty Overpass Result
    # =========================================================================
    @testset "E1: Empty/Ocean Bbox" begin
        ocean_bbox = (-50.0, -49.99, 30.0, 30.01)  # Middle of Atlantic
        @test_throws ErrorException osm_roads(ocean_bbox; cache_dir=tempdir())
    end

    # =========================================================================
    # E3: Zero Eligible Stitch Points
    # =========================================================================
    @testset "E3: Zero Stitch Points" begin
        # Create a tiny fake base network far from Gainesville
        dfN_tiny = DataFrame(IDX=[1, 2], LON=[10.0, 10.1], LAT=[50.0, 50.1],
                             SOURCE=["FAF5", "FAF5"])
        dfL_tiny = DataFrame(SRC=[1], DST=[2], DIST=[5.0], SPEED=[65],
                             FCLASS=[1], DIR=[0], NAME=["test"], SOURCE=["FAF5"])
        dfN_r, dfL_r = stitchnetworks(dfN_tiny, dfL_tiny, dfN, dfL; tolerance_m=100)
        n_conn = count(dfL_r.SOURCE .== "CONNECTOR")
        @test n_conn == 0  # Too far apart
    end

end
