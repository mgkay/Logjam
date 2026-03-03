# Tests for RoadTools functions

using Test
using Logjam
using DataFrames
using Graphs
using SparseArrays
using SimpleWeightedGraphs

@testset "RoadTools" begin

    @testset "dgc - Great Circle Distance" begin
        # Raleigh to Charlotte (approximately 130 miles)
        raleigh = (-78.6382, 35.7796)
        charlotte = (-80.8431, 35.2271)
        d_mi = dgc(raleigh, charlotte)
        @test 125 < d_mi < 135  # Should be approximately 130 miles

        # Same distance in kilometers
        d_km = dgc(raleigh, charlotte; unit=:km)
        @test 200 < d_km < 220  # Should be approximately 210 km

        # Verify km > mi (since km is smaller unit)
        @test d_km > d_mi

        # Zero distance (same point)
        @test dgc(raleigh, raleigh) ≈ 0.0 atol=1e-10

        # NYC to LA (approximately 2450 miles)
        nyc = (-74.006, 40.7128)
        la = (-118.2437, 34.0522)
        d_cross = dgc(nyc, la)
        @test 2400 < d_cross < 2500

        # Error cases
        @test_throws Exception dgc((1,), (1, 2))  # Wrong length
        @test_throws Exception dgc(raleigh, charlotte; unit=:ft)  # Invalid unit
    end

    @testset "dists - Distance Matrix" begin
        # Three NC cities
        origins = [-78.6 35.8; -80.8 35.2; -79.0 36.1]  # Raleigh, Charlotte, Durham
        dests = [-77.0 35.0; -78.5 36.0]  # Two destinations

        # Test great circle distance (replaces Dgc)
        D_gc = dists(origins, dests, :mi)
        @test size(D_gc) == (3, 2)
        @test all(D_gc .>= 0)  # All distances non-negative

        # Diagonal of square matrix should be zeros
        D_square = dists(origins, origins, :mi)
        @test size(D_square) == (3, 3)
        for i in 1:3
            @test D_square[i, i] ≈ 0.0 atol=1e-10
        end

        # Symmetry
        @test D_square[1, 2] ≈ D_square[2, 1] atol=1e-10

        # Test Euclidean distance (default)
        D_eucl = dists(origins, dests)
        @test size(D_eucl) == (3, 2)
        @test all(D_eucl .>= 0)

        # Test Euclidean with explicit p=2
        D_eucl2 = dists(origins, dests, 2)
        @test D_eucl ≈ D_eucl2

        # Test Manhattan distance
        D_manh = dists(origins, dests, 1)
        @test size(D_manh) == (3, 2)
        @test all(D_manh .>= D_eucl)  # Manhattan >= Euclidean

        # Test kilometers
        D_km = dists(origins, dests, :km)
        @test D_km ≈ D_gc .* 1.60934 atol=0.1  # mi to km conversion
    end

    @testset "prune_reindex" begin
        # Create simple test network
        # Nodes: 10, 20, 30, 40 (non-sequential)
        # Links: 10-20, 20-30, 30-40
        dfN = DataFrame(
            IDX = [10, 20, 30, 40, 50],  # Node 50 has no links
            LON = [-78.0, -79.0, -80.0, -81.0, -82.0],
            LAT = [35.0, 35.5, 36.0, 35.5, 35.0]
        )
        dfL = DataFrame(
            SRC = [10, 20, 30],
            DST = [20, 30, 40],
            DIST = [10.0, 15.0, 12.0]
        )

        dfN_out, dfL_out = prune_reindex(dfN, dfL)

        # Node 50 should be removed (no links)
        @test nrow(dfN_out) == 4

        # Node IDs should now be 1, 2, 3, 4
        @test sort(dfN_out.IDX) == [1, 2, 3, 4]

        # Links should reference new IDs
        @test minimum(dfL_out.SRC) >= 1
        @test maximum(dfL_out.DST) <= 4

        # Same number of links
        @test nrow(dfL_out) == 3

        # Total distance preserved
        @test sum(dfL_out.DIST) ≈ sum(dfL.DIST)
    end

    @testset "prune_reindex - custom column order" begin
        dfN = DataFrame(
            NAME = ["A", "B", "C", "D", "E"],
            IDX = [10, 20, 30, 40, 50],
            LON = [-78.0, -79.0, -80.0, -81.0, -82.0],
            LAT = [35.0, 35.5, 36.0, 35.5, 35.0]
        )
        dfL = DataFrame(
            LINKID = [101, 102, 103],
            SRC = [10, 20, 30],
            DST = [20, 30, 40],
            DIST = [10.0, 15.0, 12.0]
        )

        dfN_out, dfL_out = prune_reindex(dfN, dfL; src_col=:SRC, dst_col=:DST, node_col=:IDX)

        @test nrow(dfN_out) == 4
        @test sort(dfN_out.IDX) == [1, 2, 3, 4]
        @test minimum(dfL_out.SRC) >= 1
        @test maximum(dfL_out.DST) <= 4
        @test sum(dfL_out.DIST) ≈ sum(dfL.DIST)
    end

    @testset "thin - Degree-2 Node Removal" begin
        # Create chain network: 1 - 2 - 3 - 4
        # Node 2 and 3 are degree-2 and should be removed
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -79.0, -80.0, -81.0],
            LAT = [35.0, 35.0, 35.0, 35.0]
        )
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 15.0, 12.0]
        )

        dfN_thin, dfL_thin = thin(dfN, dfL)

        # Should reduce to single link 1-4
        @test nrow(dfL_thin) == 1
        @test nrow(dfN_thin) == 2

        # Total distance preserved
        @test sum(dfL_thin.DIST) ≈ sum(dfL.DIST)

        # Endpoints should be 1 and 4
        endpoints = union(Set(dfL_thin.SRC), Set(dfL_thin.DST))
        @test endpoints == Set([1, 4])
    end

    @testset "thin - must_match constraint" begin
        # Create chain with different attributes
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -79.0, -80.0, -81.0],
            LAT = [35.0, 35.0, 35.0, 35.0]
        )
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 15.0, 12.0],
            FCLASS = [1, 2, 2]  # Different class at node 2
        )

        # Without must_match, should thin fully
        dfN_thin1, dfL_thin1 = thin(dfN, dfL)
        @test nrow(dfL_thin1) == 1

        # With must_match=["FCLASS"], should preserve node 2
        dfN_thin2, dfL_thin2 = thin(dfN, dfL; must_match=["FCLASS"])
        @test nrow(dfL_thin2) == 2  # Two links remain
        @test nrow(dfN_thin2) == 3  # Three nodes remain
    end

    @testset "thin - self-loop prevention" begin
        # Create a triangle (beltway scenario)
        # All nodes have degree 2, but thinning would create self-loops
        dfN = DataFrame(
            IDX = [1, 2, 3],
            LON = [-78.0, -79.0, -78.5],
            LAT = [35.0, 35.0, 35.5]
        )
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 1],
            DIST = [10.0, 10.0, 10.0]
        )

        dfN_thin, dfL_thin = thin(dfN, dfL)

        # No self-loops should exist
        for row in eachrow(dfL_thin)
            @test row.SRC != row.DST
        end
    end

    @testset "thin - keep_index" begin
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -79.0, -80.0, -81.0],
            LAT = [35.0, 35.0, 35.0, 35.0]
        )
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 15.0, 12.0]
        )

        dfN_thin, dfL_thin, merge_log = thin(dfN, dfL; keep_index=true)

        # merge_log should exist and track original indices
        @test !isempty(merge_log)

        # Each merged link should reference original link indices
        for (new_idx, orig_indices) in merge_log
            @test all(1 .<= orig_indices .<= 3)
        end
    end

    @testset "thin - aggregation" begin
        dfN = DataFrame(
            IDX = [1, 2, 3],
            LON = [-78.0, -79.0, -80.0],
            LAT = [35.0, 35.0, 35.0]
        )
        dfL = DataFrame(
            SRC = [1, 2],
            DST = [2, 3],
            DIST = [10.0, 15.0],
            SPEED = [65, 55]  # Different speeds
        )

        # Use minimum speed aggregation
        _, dfL_thin = thin(dfN, dfL; agg=Dict("SPEED" => minimum))

        @test nrow(dfL_thin) == 1
        @test dfL_thin.SPEED[1] == 55  # Minimum of 65 and 55
        @test dfL_thin.DIST[1] == 25.0  # Sum of distances
    end

    @testset "links2graph" begin
        dfL = DataFrame(
            SRC = [1, 2, 3, 1],
            DST = [2, 3, 4, 3],
            DIST = [10.0, 15.0, 12.0, 20.0]
        )

        g = links2graph(dfL)

        @test Graphs.nv(g) == 4
        # Directed graph: 4 links * 2 directions = 8 edges
        @test Graphs.ne(g) == 8
        @test Graphs.has_edge(g, 1, 2)
        @test Graphs.has_edge(g, 2, 1)  # Reverse edge
        @test Graphs.has_edge(g, 2, 3)
        @test Graphs.has_edge(g, 3, 4)
        @test Graphs.has_edge(g, 1, 3)
    end

    @testset "x2ln" begin
        # Simple 3-node graph: 1-2, 2-3
        g = Graphs.SimpleGraph(3)
        Graphs.add_edge!(g, 1, 2)
        Graphs.add_edge!(g, 2, 3)

        x = [1.0, 2.0, 3.0]  # Node x-coordinates

        x_ln = x2ln(g, x)

        # Should have pattern: [x1, x2, NaN, x2, x3, NaN]
        @test length(x_ln) == 6
        @test count(isnan, x_ln) == 2  # Two NaN separators
    end

    @testset "addconnectors - basic" begin
        # Create simple 4-node network
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -78.0, -79.0, -79.0],
            LAT = [35.0, 36.0, 35.0, 36.0],
            ZONE = ["N1", "N2", "N3", "N4"]
        )
        dfL = DataFrame(
            SRC = [1, 2, 1],
            DST = [2, 4, 3],
            DIST = [69.0, 69.0, 54.0],  # Approximate great circle distances
            SPEED = [55, 60, 50],
            DIR = [0, 1, 0]
        )

        # Add one demand point
        x′ = [-78.5]
        y′ = [35.5]

        dfN_conn, dfL_conn = addconnectors(dfN, dfL, x′, y′)

        # Demand point should be node 1, network nodes shifted to 2-5
        @test nrow(dfN_conn) == 5
        @test dfN_conn.IDX[1] == 1  # Demand point is first

        # Should have original links + connectors (with added SOURCE column)
        @test nrow(dfL_conn) > nrow(dfL)
        @test names(dfL_conn) == [names(dfL); "SOURCE"]
        @test names(dfN_conn) == names(dfN)
        @test dfL_conn.SPEED[1:nrow(dfL)] == dfL.SPEED
        @test dfL_conn.DIR[1:nrow(dfL)] == dfL.DIR
        @test all(ismissing, dfL_conn.SPEED[(nrow(dfL) + 1):end])
        @test all(dfL_conn.DIR[(nrow(dfL) + 1):end] .== 0)
        @test ismissing(dfN_conn.ZONE[1])
        @test dfN_conn.ZONE[2:end] == dfN.ZONE

        # Connector links should connect node 1 to nearby network nodes
        connector_links = filter(r -> r.SRC == 1 || r.DST == 1, dfL_conn)
        @test nrow(connector_links) >= 1
    end

    @testset "addconnectors - multiple demand points" begin
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -78.0, -79.0, -79.0],
            LAT = [35.0, 36.0, 35.0, 36.0]
        )
        dfL = DataFrame(
            SRC = [1, 2, 1],
            DST = [2, 4, 3],
            DIST = [69.0, 69.0, 54.0]
        )

        # Add three demand points
        x′ = [-78.2, -78.8, -78.5]
        y′ = [35.2, 35.8, 35.5]

        dfN_conn, dfL_conn = addconnectors(dfN, dfL, x′, y′)

        # Demand points should be nodes 1, 2, 3
        @test nrow(dfN_conn) == 7  # 3 demand + 4 network
        @test dfN_conn.IDX[1:3] == [1, 2, 3]

        # Network nodes shifted by 3
        @test dfN_conn.IDX[4:7] == [4, 5, 6, 7]
    end

    @testset "addconnectors - custom column order" begin
        dfN = DataFrame(
            NAME = ["N1", "N2", "N3", "N4"],
            IDX = [10, 20, 30, 40],
            LON = [-78.0, -78.0, -79.0, -79.0],
            LAT = [35.0, 36.0, 35.0, 36.0]
        )
        dfL = DataFrame(
            LINKID = [1001, 1002, 1003],
            SRC = [10, 20, 10],
            DST = [20, 40, 30],
            DIST = [69.0, 69.0, 54.0],
            SPEED = [55, 60, 50]
        )

        x_prime = [-78.5]
        y_prime = [35.5]
        dfN_conn, dfL_conn = addconnectors(
            dfN, dfL, x_prime, y_prime;
            src_col=:SRC, dst_col=:DST, dist_col=:DIST,
            node_col=:IDX, x_col=:LON, y_col=:LAT
        )

        @test names(dfL_conn) == [names(dfL); "SOURCE"]
        @test names(dfN_conn) == names(dfN)
        @test dfN_conn.IDX[1] == 1
        @test Set(dfN_conn.IDX[2:end]) == Set(2:5)
        @test all(v -> v in Set(dfN_conn.IDX), dfL_conn.SRC)
        @test all(v -> v in Set(dfN_conn.IDX), dfL_conn.DST)
        @test dfL_conn.SPEED[1:nrow(dfL)] == dfL.SPEED
        @test all(ismissing, dfL_conn.SPEED[(nrow(dfL) + 1):end])
    end

    @testset "addconnectors - NF-NF connectors" begin
        # Shared network for all sub-tests
        dfN_nf = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -78.0, -79.0, -79.0],
            LAT = [35.0, 36.0, 35.0, 36.0]
        )
        dfL_nf = DataFrame(
            SRC = [1, 2, 1],
            DST = [2, 4, 3],
            DIST = [69.0, 69.0, 54.0],
            DIR = [0, 1, 0]
        )

        @testset "A. three NF points (triangle)" begin
            x′ = [-78.2, -78.8, -78.5]
            y′ = [35.2, 35.8, 35.5]
            dfN_conn, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′)

            # NF-NF links: both endpoints in 1:3
            nf_links = filter(r -> r.SRC <= 3 && r.DST <= 3, dfL_conn)
            @test nrow(nf_links) == 3  # 3 points → 3 Delaunay edges

            # DIR = 0 for all NF-NF connectors
            @test all(nf_links.DIR .== 0)

            # Circuity applied: check edge (1,3)
            nf13 = filter(r -> Set([r.SRC, r.DST]) == Set([1, 3]), dfL_conn)
            @test nrow(nf13) == 1
            raw = dgc((-78.2, 35.2), (-78.5, 35.5))
            @test nf13.DIST[1] ≈ 1.3 * raw
        end

        @testset "B. disabled with add_nf_nf=false" begin
            x′ = [-78.2, -78.8, -78.5]
            y′ = [35.2, 35.8, 35.5]
            _, dfL_on = addconnectors(dfN_nf, dfL_nf, x′, y′)
            _, dfL_off = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=false)

            @test nrow(dfL_on) > nrow(dfL_off)
            nf_off = filter(r -> r.SRC <= 3 && r.DST <= 3, dfL_off)
            @test nrow(nf_off) == 0
        end

        @testset "C. two NF points" begin
            x′ = [-78.3, -78.7]
            y′ = [35.3, 35.7]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′)

            nf_links = filter(r -> r.SRC <= 2 && r.DST <= 2, dfL_conn)
            @test nrow(nf_links) == 1
            @test Set([nf_links.SRC[1], nf_links.DST[1]]) == Set([1, 2])
            raw = dgc((-78.3, 35.3), (-78.7, 35.7))
            @test nf_links.DIST[1] ≈ 1.3 * raw
        end

        @testset "D. single NF point" begin
            x′ = [-78.5]
            y′ = [35.5]
            _, dfL_on = addconnectors(dfN_nf, dfL_nf, x′, y′)
            _, dfL_off = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=false)
            @test nrow(dfL_on) == nrow(dfL_off)
        end

        @testset "E. collinear NF points" begin
            # 4 points along a line (no true triangles)
            x′ = [-78.0, -78.5, -79.0, -79.5]
            y′ = [35.0, 35.0, 35.0, 35.0]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′)

            nf_links = filter(r -> r.SRC <= 4 && r.DST <= 4, dfL_conn)
            @test nrow(nf_links) >= 3  # chain: 1-2, 2-3, 3-4 at minimum
        end

        @testset "F. no duplicate arcs" begin
            x′ = [-78.2, -78.8, -78.5]
            y′ = [35.2, 35.8, 35.5]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′)

            nf_links = filter(r -> r.SRC <= 3 && r.DST <= 3, dfL_conn)
            edges = Set([Set([r.SRC, r.DST]) for r in eachrow(nf_links)])
            @test length(edges) == nrow(nf_links)  # no duplicates
        end
    end

    @testset "cropnetwork" begin
        # Create a larger network
        dfN = DataFrame(
            IDX = 1:10,
            LON = [-78.0, -78.5, -79.0, -79.5, -80.0, -80.5, -81.0, -81.5, -82.0, -82.5],
            LAT = [35.0, 35.2, 35.4, 35.6, 35.8, 36.0, 36.2, 36.4, 36.6, 36.8]
        )
        dfL = DataFrame(
            SRC = [1, 2, 3, 4, 5, 6, 7, 8, 9],
            DST = [2, 3, 4, 5, 6, 7, 8, 9, 10],
            DIST = fill(10.0, 9)
        )

        # Crop to region around nodes 3-7 (LON ~ -79 to -81, LAT ~ 35.4 to 36.2)
        x = [-79.5, -80.5]
        y = [35.6, 36.0]

        dfN_crop, dfL_crop = cropnetwork(dfN, dfL, x, y)

        # Should have fewer nodes than original
        @test nrow(dfN_crop) < nrow(dfN)
        @test nrow(dfN_crop) >= 2  # At least 2 nodes

        # Node IDs should be sequential starting from 1
        @test minimum(dfN_crop.IDX) == 1

        # Links should reference valid nodes
        max_node = maximum(dfN_crop.IDX)
        @test all(dfL_crop.SRC .<= max_node)
        @test all(dfL_crop.DST .<= max_node)
    end

    # --- Return-order regression tests (V7) ---

    @testset "prune_reindex - return order regression" begin
        dfN = DataFrame(IDX = [1, 2, 3], LON = [-78.0, -79.0, -80.0], LAT = [35.0, 35.5, 36.0])
        dfL = DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [10.0, 15.0])
        dfN_out, dfL_out = prune_reindex(dfN, dfL)
        @test "IDX" in names(dfN_out)
        @test "SRC" in names(dfL_out)
        @test "DST" in names(dfL_out)
    end

    @testset "addconnectors - return order regression" begin
        dfN = DataFrame(IDX = [1, 2, 3, 4], LON = [-78.0, -78.0, -79.0, -79.0], LAT = [35.0, 36.0, 35.0, 36.0])
        dfL = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0])
        dfN_out, dfL_out = addconnectors(dfN, dfL, [-78.5], [35.5])
        @test "IDX" in names(dfN_out)
        @test "SRC" in names(dfL_out)
        @test "DST" in names(dfL_out)
    end

    @testset "thin - return order regression" begin
        dfN = DataFrame(IDX = [1, 2, 3, 4], LON = [-78.0, -79.0, -80.0, -81.0], LAT = [35.0, 35.0, 35.0, 35.0])
        dfL = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [10.0, 15.0, 12.0])
        dfN_out, dfL_out = thin(dfN, dfL)
        @test "IDX" in names(dfN_out)
        @test "SRC" in names(dfL_out)
        dfN_out2, dfL_out2, ml = thin(dfN, dfL; keep_index=true)
        @test "IDX" in names(dfN_out2)
        @test "SRC" in names(dfL_out2)
        @test ml isa Dict
    end

    @testset "cropnetwork - return order regression" begin
        dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.5, -79.0, -79.5, -80.0], LAT = [35.0, 35.2, 35.4, 35.6, 35.8])
        dfL = DataFrame(SRC = [1, 2, 3, 4], DST = [2, 3, 4, 5], DIST = fill(10.0, 4))
        dfN_out, dfL_out = cropnetwork(dfN, dfL, [-79.5, -78.5], [35.2, 35.6])
        @test "IDX" in names(dfN_out)
        @test "SRC" in names(dfL_out)
        @test "DST" in names(dfL_out)
    end

    @testset "links2graph - weighted directed graph" begin
        # Create simple 4-node chain
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 20.0, 15.0]
        )

        # Default: uses column 3 (DIST), bidirectional
        g = links2graph(dfL)

        # Should return a SimpleWeightedDiGraph
        @test g isa SimpleWeightedGraphs.SimpleWeightedDiGraph

        # Should have 4 nodes
        @test Graphs.nv(g) == 4

        # Bidirectional: each link creates 2 directed edges
        @test Graphs.ne(g) == 6  # 3 links * 2 directions

        # Check edge weights (SimpleWeightedGraphs uses weights[dst, src] for edge src→dst)
        @test g.weights[2, 1] ≈ 10.0  # Edge FROM 1 TO 2
        @test g.weights[1, 2] ≈ 10.0  # Edge FROM 2 TO 1 (reverse)
    end

    @testset "links2graph - named weight column" begin
        dfL = DataFrame(
            SRC = [1, 2],
            DST = [2, 3],
            DIST = [10.0, 20.0],
            COST = [100.0, 200.0]
        )

        # Use named column
        g = links2graph(dfL, weight=:COST)

        # SimpleWeightedGraphs uses weights[dst, src] for edge src→dst
        @test g.weights[2, 1] ≈ 100.0  # Edge FROM 1 TO 2
        @test g.weights[3, 2] ≈ 200.0  # Edge FROM 2 TO 3
    end

    @testset "links2graph - one-way roads" begin
        dfL = DataFrame(
            SRC = [1, 2],
            DST = [2, 3],
            DIST = [10.0, 20.0],
            DIR = [1, 0]  # First link one-way, second bidirectional
        )

        g = links2graph(dfL)

        # Note: SimpleWeightedGraphs uses transposed convention: weights[dst, src] = weight from src to dst
        # First link: one-way A→B only (edge from 1 to 2)
        @test g.weights[2, 1] ≈ 10.0  # Edge FROM 1 TO 2
        @test g.weights[1, 2] ≈ 0.0   # No edge FROM 2 TO 1

        # Second link: bidirectional (edges 2↔3)
        @test g.weights[3, 2] ≈ 20.0  # Edge FROM 2 TO 3
        @test g.weights[2, 3] ≈ 20.0  # Edge FROM 3 TO 2
    end

    @testset "links2graph - asymmetric weights" begin
        dfL = DataFrame(
            SRC = [1, 2],
            DST = [2, 3],
            AB_TIME = [10.0, 20.0],
            BA_TIME = [15.0, 25.0]
        )

        g = links2graph(dfL, ab_weight=:AB_TIME, ba_weight=:BA_TIME)

        # Note: SimpleWeightedGraphs uses transposed convention: weights[dst, src] = weight from src to dst
        # Forward edges use AB_TIME (A→B)
        @test g.weights[2, 1] ≈ 10.0  # Edge FROM 1 TO 2
        @test g.weights[3, 2] ≈ 20.0  # Edge FROM 2 TO 3

        # Reverse edges use BA_TIME (B→A)
        @test g.weights[1, 2] ≈ 15.0  # Edge FROM 2 TO 1
        @test g.weights[2, 3] ≈ 25.0  # Edge FROM 3 TO 2
    end

    @testset "links2graph - no reindex when dense" begin
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 20.0, 15.0]
        )

        g, id_map, inv_map = links2graph(dfL; return_map=true)

        @test Graphs.nv(g) == 4
        @test id_map[1] == 1
        @test id_map[2] == 2
        @test inv_map[1] == 1
        @test inv_map[2] == 2
    end

    @testset "links2graph - auto reindex for sparse IDs" begin
        dfL = DataFrame(
            SRC = [10, 20],
            DST = [20, 40],
            DIST = [5.0, 7.0]
        )

        g, id_map, inv_map = links2graph(dfL; return_map=true)

        @test Graphs.nv(g) == 3
        @test id_map[10] == 1
        @test id_map[20] == 2
        @test id_map[40] == 3
        @test inv_map[1] == 10
        @test inv_map[2] == 20
        @test inv_map[3] == 40
    end

    @testset "links2graph - auto reindex by max_id_threshold" begin
        dfL = DataFrame(
            SRC = [100, 200],
            DST = [200, 300],
            DIST = [5.0, 7.0]
        )

        g, id_map, inv_map = links2graph(dfL; return_map=true,
            sparse_ratio=1_000, max_id_threshold=150)

        @test Graphs.nv(g) == 3
        @test id_map[100] == 1
        @test id_map[200] == 2
        @test id_map[300] == 3
        @test inv_map[1] == 100
        @test inv_map[2] == 200
        @test inv_map[3] == 300
    end

    @testset "links2graph - string IDs in auto mode" begin
        dfL = DataFrame(
            SRC = ["NodeA", "NodeB"],
            DST = ["NodeB", "NodeC"],
            DIST = [1.0, 2.0]
        )

        g, id_map, inv_map = links2graph(dfL; return_map=true)

        @test Graphs.nv(g) == 3
        @test id_map["NodeA"] == 1
        @test id_map["NodeC"] == 3
        @test inv_map[2] == "NodeB"
    end

    @testset "links2graph - mixed IDs in auto mode" begin
        dfL = DataFrame(
            SRC = Any[1, "NodeA"],
            DST = Any["NodeA", 2],
            DIST = [1.0, 2.0]
        )

        g, id_map, inv_map = links2graph(dfL; return_map=true)

        @test Graphs.nv(g) == 3
        @test length(id_map) == 3
        @test haskey(id_map, 1)
        @test haskey(id_map, "NodeA")
        @test haskey(id_map, 2)
        @test inv_map[id_map[1]] == 1
        @test inv_map[id_map["NodeA"]] == "NodeA"
        @test inv_map[id_map[2]] == 2
    end

    @testset "links2graph - custom src/dst columns" begin
        dfL = DataFrame(
            LINKID = [1001, 1002],
            SRC = [10, 20],
            DST = [20, 40],
            DIST = [5.0, 7.0]
        )

        g, id_map, inv_map = links2graph(
            dfL; return_map=true, reindex=true, src_col=:SRC, dst_col=:DST
        )

        @test Graphs.nv(g) == 3
        @test id_map[10] == 1
        @test id_map[40] == 3
        @test inv_map[2] == 20
    end

    @testset "links2graph - explicit reindex=false" begin
        dfL = DataFrame(
            SRC = [10, 20],
            DST = [20, 40],
            DIST = [5.0, 7.0]
        )

        g = links2graph(dfL; reindex=false)

        @test Graphs.nv(g) == 40
    end

    @testset "shortestpaths - weighted graph (new API)" begin
        # Create simple 4-node graph: 1-2-3-4 (chain)
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 20.0, 15.0]
        )

        g = links2graph(dfL)

        # New API: no separate weights needed
        D, P = shortestpaths(g, 2)

        # D should be 2x2
        @test size(D) == (2, 2)

        # Diagonal should be zero
        @test D[1, 1] ≈ 0.0
        @test D[2, 2] ≈ 0.0

        # D[1,2] should be 10 (direct edge)
        @test D[1, 2] ≈ 10.0

        # D[2,1] should also be 10 (symmetric)
        @test D[2, 1] ≈ 10.0

        # P should have 2 parent vectors
        @test length(P) == 2

        # Parent of node 2 from node 1 should be 1
        @test P[1][2] == 1
    end

    @testset "shortestpaths - path reconstruction (new API)" begin
        # 4-node graph with chain structure
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 20.0, 15.0]
        )

        g = links2graph(dfL)
        D, P = shortestpaths(g, 4)

        # Distance from 1 to 4 should be 10 + 20 + 15 = 45
        @test D[1, 4] ≈ 45.0

        # Trace path from 1 to 4 using parents
        path = [4]
        curr = 4
        while P[1][curr] != 0
            curr = P[1][curr]
            push!(path, curr)
        end
        reverse!(path)

        @test path == [1, 2, 3, 4]
    end

    @testset "shortestpaths - explicit weights (legacy API)" begin
        # 4-node graph with chain structure
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 20.0, 15.0]
        )

        # Create undirected graph for legacy API test
        max_node = maximum(vcat(dfL.SRC, dfL.DST))
        g_simple = Graphs.SimpleGraph(max_node)
        for row in eachrow(dfL)
            Graphs.add_edge!(g_simple, row.SRC, row.DST)
        end

        # Create symmetric weight matrix
        n = Graphs.nv(g_simple)
        I = vcat(dfL.SRC, dfL.DST)
        J = vcat(dfL.DST, dfL.SRC)
        V = vcat(dfL.DIST, dfL.DIST)
        weights = sparse(I, J, V, n, n)

        # Legacy API with explicit weights
        D, P = shortestpaths(g_simple, weights, 4)

        # Distance from 1 to 4 should be 10 + 20 + 15 = 45
        @test D[1, 4] ≈ 45.0
    end

    @testset "tracepath" begin
        # Chain graph: 1→2→3→4
        parents = [0, 1, 2, 3]

        @test tracepath(parents, 1, 4) == [1, 2, 3, 4]
        @test tracepath(parents, 1, 3) == [1, 2, 3]
        @test tracepath(parents, 1, 2) == [1, 2]

        # origin == dest
        @test tracepath(parents, 1, 1) == [1]
        @test tracepath(parents, 3, 3) == [3]

        # Unreachable destination (parents[dest] == 0)
        parents_disc = [0, 1, 0, 0]  # node 3,4 unreachable
        @test_throws ArgumentError tracepath(parents_disc, 1, 3)
        @test_throws ArgumentError tracepath(parents_disc, 1, 4)

        # Reachable node 2 still works
        @test tracepath(parents_disc, 1, 2) == [1, 2]
    end

end  # @testset "RoadTools"
