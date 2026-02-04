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

    @testset "Dgc - Distance Matrix" begin
        # Three NC cities
        origins = [-78.6 35.8; -80.8 35.2; -79.0 36.1]  # Raleigh, Charlotte, Durham
        dests = [-77.0 35.0; -78.5 36.0]  # Two destinations

        D = Dgc(origins, dests)

        @test size(D) == (3, 2)
        @test all(D .>= 0)  # All distances non-negative

        # Diagonal of square matrix should be zeros
        D_square = Dgc(origins, origins)
        @test size(D_square) == (3, 3)
        for i in 1:3
            @test D_square[i, i] ≈ 0.0 atol=1e-10
        end

        # Symmetry
        @test D_square[1, 2] ≈ D_square[2, 1] atol=1e-10
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

        dfL_out, dfN_out = prune_reindex(dfL, dfN)

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

        dfL_thin, dfN_thin = thin(dfL, dfN)

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
        dfL_thin1, dfN_thin1 = thin(dfL, dfN)
        @test nrow(dfL_thin1) == 1

        # With must_match=["FCLASS"], should preserve node 2
        dfL_thin2, dfN_thin2 = thin(dfL, dfN; must_match=["FCLASS"])
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

        dfL_thin, dfN_thin = thin(dfL, dfN)

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

        dfL_thin, dfN_thin, merge_log = thin(dfL, dfN; keep_index=true)

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
        dfL_thin, _ = thin(dfL, dfN; agg=Dict("SPEED" => minimum))

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
            LAT = [35.0, 36.0, 35.0, 36.0]
        )
        dfL = DataFrame(
            SRC = [1, 2, 1],
            DST = [2, 4, 3],
            DIST = [69.0, 69.0, 54.0]  # Approximate great circle distances
        )

        # Add one demand point
        x′ = [-78.5]
        y′ = [35.5]

        dfL_conn, dfN_conn = addconnectors(dfL, dfN, x′, y′)

        # Demand point should be node 1, network nodes shifted to 2-5
        @test nrow(dfN_conn) == 5
        @test dfN_conn.IDX[1] == 1  # Demand point is first

        # Should have original links + connectors
        @test nrow(dfL_conn) > nrow(dfL)

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

        dfL_conn, dfN_conn = addconnectors(dfL, dfN, x′, y′)

        # Demand points should be nodes 1, 2, 3
        @test nrow(dfN_conn) == 7  # 3 demand + 4 network
        @test dfN_conn.IDX[1:3] == [1, 2, 3]

        # Network nodes shifted by 3
        @test dfN_conn.IDX[4:7] == [4, 5, 6, 7]
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

        dfL_crop, dfN_crop = cropnetwork(dfN, dfL, x, y)

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

end  # @testset "RoadTools"
