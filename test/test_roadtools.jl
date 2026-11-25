# Tests for RoadTools functions

using Test
using Logjam
using DataFrames
# the NaN-separated line coordinates of a location sequence along shortest paths: what `Logjam.rte2lines`
# computed until v0.3.0, kept here as a test-side helper (the extension carries the same body privately)
function _test_rte2lines(route, P, dfN)
    x_out, y_out = Float64[], Float64[]
    for k in 1:length(route)-1
        path = tracepath(P[route[k]], route[k], route[k+1])
        append!(x_out, dfN.LON[path]); push!(x_out, NaN)
        append!(y_out, dfN.LAT[path]); push!(y_out, NaN)
    end
    return x_out, y_out
end
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
            dfN_conn, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)

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
            _, dfL_on = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)
            _, dfL_off = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=false)

            @test nrow(dfL_on) > nrow(dfL_off)
            nf_off = filter(r -> r.SRC <= 3 && r.DST <= 3, dfL_off)
            @test nrow(nf_off) == 0
        end

        @testset "C. two NF points" begin
            x′ = [-78.3, -78.7]
            y′ = [35.3, 35.7]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)

            nf_links = filter(r -> r.SRC <= 2 && r.DST <= 2, dfL_conn)
            @test nrow(nf_links) == 1
            @test Set([nf_links.SRC[1], nf_links.DST[1]]) == Set([1, 2])
            raw = dgc((-78.3, 35.3), (-78.7, 35.7))
            @test nf_links.DIST[1] ≈ 1.3 * raw
        end

        @testset "D. single NF point" begin
            x′ = [-78.5]
            y′ = [35.5]
            _, dfL_on = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)
            _, dfL_off = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=false)
            @test nrow(dfL_on) == nrow(dfL_off)
        end

        @testset "E. collinear NF points" begin
            # 4 points along a line (no true triangles)
            x′ = [-78.0, -78.5, -79.0, -79.5]
            y′ = [35.0, 35.0, 35.0, 35.0]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)

            nf_links = filter(r -> r.SRC <= 4 && r.DST <= 4, dfL_conn)
            @test nrow(nf_links) >= 3  # chain: 1-2, 2-3, 3-4 at minimum
        end

        @testset "F. no duplicate arcs" begin
            x′ = [-78.2, -78.8, -78.5]
            y′ = [35.2, 35.8, 35.5]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)

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

    @testset "cropnetwork - return order regression" begin
        dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.5, -79.0, -79.5, -80.0], LAT = [35.0, 35.2, 35.4, 35.6, 35.8])
        dfL = DataFrame(SRC = [1, 2, 3, 4], DST = [2, 3, 4, 5], DIST = fill(10.0, 4))
        dfN_out, dfL_out = cropnetwork(dfN, dfL, [-79.5, -78.5], [35.2, 35.6])
        @test "IDX" in names(dfN_out)
        @test "SRC" in names(dfL_out)
        @test "DST" in names(dfL_out)
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

        # Legacy API with explicit weights: deprecated, and still gives the answer. Under Pkg.test the
        # deprecation warns (--depwarn=yes) and `@test_deprecated` checks it; elsewhere it prints nothing.
        if Base.JLOptions().depwarn == 1
            D, P = @test_deprecated shortestpaths(g_simple, weights, 4)
        else
            D, P = shortestpaths(g_simple, weights, 4)
        end

        # Distance from 1 to 4 should be 10 + 20 + 15 = 45
        @test D[1, 4] ≈ 45.0
        @test tracepath(P[1], 1, 4) == [1, 2, 3, 4]
    end

    @testset "[N28] shortestpaths(g, n) takes any simple weighted graph, and the weights are the graph's" begin
        # an undirected SimpleWeightedGraph (Lecture 4.1, Code block 57's thinned Interstates)
        gu = SimpleWeightedGraphs.SimpleWeightedGraph([1, 2, 3], [2, 3, 1], [1.0, 2.0, 5.0])
        Du, Pu = shortestpaths(gu, 3)
        @test Du == [0.0 1.0 3.0; 1.0 0.0 2.0; 3.0 2.0 0.0]
        @test tracepath(Pu[1], 1, 3) == [1, 2, 3]
        # the legacy three-argument form on the same graph gives the same distances
        D3 = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            shortestpaths(gu, weights(gu), 3)[1]
        end
        @test D3 == Du
        # a directed graph: one-way arcs make the distances differ by direction
        gd = SimpleWeightedGraphs.SimpleWeightedDiGraph([1, 2, 3], [2, 3, 1], [1.0, 2.0, 5.0])
        Dd, _ = shortestpaths(gd, 3)
        @test Dd[1, 3] == 3.0 && Dd[3, 1] == 5.0
        # more sources than nodes is refused, not an out-of-range
        @test_throws ArgumentError shortestpaths(gd, 4)
        # the example of v0.2.8 built `weights + weights'` from the links of a network that lists both
        # directions (OpenStreetMap's, or any DIR 1 pair), which doubles each weight: the graph's own weights
        # give the distance of the links, not twice it
        dfL = DataFrame(SRC = [1, 2, 2, 3], DST = [2, 1, 3, 2], DIST = [10.0, 10.0, 20.0, 20.0], DIR = [1, 1, 1, 1])
        g = links2graph(dfL)
        @test shortestpaths(g, 3)[1][1, 3] == 30.0
        W = sparse(dfL.SRC, dfL.DST, dfL.DIST, 3, 3)
        @test (W + W')[1, 2] == 20.0                                            # the doubling, for the record
        D2 = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            shortestpaths(g, W + W', 3)[1]
        end
        @test D2[1, 3] == 60.0                                                  # v0.2.8's example, twice the miles
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

    @testset "dists - edge cases" begin
        # Single point vs single point
        X1 = [0.0 0.0]
        X2 = [3.0 4.0]
        D = dists(X1, X2)
        @test D[1,1] ≈ 5.0

        # Distance to self is zero
        X = [1.0 2.0; 3.0 4.0]
        D = dists(X, X)
        @test D[1,1] ≈ 0.0
        @test D[2,2] ≈ 0.0

        # Geographic distance symmetry
        cities = [-78.64 35.78; -122.42 37.77]
        D = dists(cities, cities, :mi)
        @test D[1,2] ≈ D[2,1] atol=0.1

        # An integer p above 2 is the lp metric (N19, K5): (3³ + 4³)^(1/3) here
        @test dists(X1, X2, 3)[1,1] ≈ 91^(1 / 3)
        # Invalid integer metric
        @test_throws ErrorException dists(X1, X2, 0)

        # Invalid symbol metric
        @test_throws ErrorException dists(X1, X2, :invalid)
    end

end  # @testset "RoadTools"

# =============================================================================
# K2a: wrong-answer tests (test spec Sec. 2) and pin-today tests (Sec. 7).
# Each testset is tagged [ID]; tools/v0_3_0/run_against.jl records its outcome in
# baselines/sc2-outcomes.csv. A `@test_broken` names the component whose commit flips it to `@test`.
# =============================================================================

@testset "[N6] after thin, node IDs are 1:n in row order and a drawn path uses the named nodes' coordinates" begin
    # a path 1-2-3-4 with a branch 2-5; node 3 has degree 2 and is merged away
    dfN = DataFrame(IDX = 1:5, LON = [0.0, 1.0, 2.0, 3.0, 1.0], LAT = [0.0, 0.0, 0.0, 0.0, 1.0])
    dfL = DataFrame(SRC = [1, 2, 3, 2], DST = [2, 3, 4, 5], DIST = fill(1.0, 4))
    nodes, links = thin(dfN, dfL)
    @test nrow(nodes) == 4                                  # control: node 3 is gone
    # N6: v0.2.8 left IDX = [1, 2, 4, 5]; thin now numbers the nodes it keeps 1:n
    @test nodes.IDX == 1:nrow(nodes)
    # the path from the node at (0, 0) to the node at (3, 0), drawn through the thinned network
    i1 = nodes.IDX[findfirst(==(0.0), nodes.LON)]
    i4 = nodes.IDX[findfirst(==(3.0), nodes.LON)]
    g = links2graph(links)
    _, P = shortestpaths(g, nv(g) >= 4 ? 4 : nv(g))
    x, y = _test_rte2lines([i1, i4], P, nodes)
    # N6: v0.2.8 drew [0, 1, 1]: the row positions of the path's vertices belong to other nodes
    @test x[1:end-1] == [0.0, 1.0, 3.0]
    @test y[1:end-1] == [0.0, 0.0, 0.0]
end

@testset "[CR 17] links2graph keeps the shorter of two parallel links, honors DIR = -1, keeps a zero time" begin
    # parallel links 1-2 of 5.0 and 3.0: v0.2.8 summed them (8.0)
    g = links2graph(DataFrame(SRC = [1, 1], DST = [2, 2], DIST = [5.0, 3.0]))
    @test weights(g)[1, 2] == 3.0 && weights(g)[2, 1] == 3.0
    # DIR = -1 is a one-way link from DST to SRC
    g = links2graph(DataFrame(SRC = [1], DST = [2], DIST = [4.0], DIR = [-1]))
    @test weights(g)[2, 1] == 4.0 && weights(g)[1, 2] == 0.0
    @test has_edge(g, 2, 1) && !has_edge(g, 1, 2)
    # a zero travel time is a link, not a missing one: node 3 stays reachable at no extra time
    g = links2graph(DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [1.0, 0.0]))
    @test nv(g) == 3
    @test isapprox(Graphs.dijkstra_shortest_paths(g, 1).dists[3], 1.0)
    @test isapprox(Graphs.dijkstra_shortest_paths(g, 3).dists[1], 1.0)
    # control: a plain two-way link and a DIR = 1 one-way link
    g = links2graph(DataFrame(SRC = [1], DST = [2], DIST = [4.0], DIR = [1]))
    @test weights(g)[1, 2] == 4.0 && weights(g)[2, 1] == 0.0
    # parallel links keep the shorter in each direction separately, and a zero link beside a longer one
    g = links2graph(DataFrame(SRC = [1, 2, 1], DST = [2, 1, 2], DIST = [5.0, 3.0, 0.0], DIR = [1, 1, 1]))
    @test weights(g)[1, 2] == 0.0 && weights(g)[2, 1] == 3.0
    @test Graphs.dijkstra_shortest_paths(g, 1).dists[2] == 0.0           # the zero link is an arc
end

@testset "[CR 18] thin gives the same network whatever the node order" begin
    # a ring of six nodes at unit distance: v0.2.8's result depends on the order its queue visits the nodes
    function ringnet(perm)
        n = 6
        ang = [2pi * (i - 1) / n for i in 1:n]
        N = DataFrame(IDX = perm, LON = cos.(ang), LAT = sin.(ang))
        L = DataFrame(SRC = perm, DST = [perm[mod1(i + 1, n)] for i in 1:n], DIST = fill(1.0, n))
        return N, L
    end
    perms = [[1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1], [3, 1, 6, 2, 5, 4], [2, 4, 6, 1, 3, 5],
             [5, 3, 1, 6, 4, 2], [4, 6, 2, 5, 1, 3]]
    shapes = Set{Tuple{Int,Vector{Float64}}}()
    for p in perms
        N, L = ringnet(p)
        Nt, Lt = thin(N, L)
        push!(shapes, (nrow(Nt), sort(Lt.DIST)))
    end
    # CR 18: v0.2.8 gave (3 nodes, [1, 2, 3]), (3, [2, 2, 2]) and (2, [2]) for these labelings; thin now visits the
    # nodes in the order of the rows of dfN, which these labelings leave alone
    @test length(shapes) == 1
end

@testset "[CR 25] thin on a network with one link per direction keeps both directions" begin
    # node 2 is a sink: 1 -> 2 and 3 -> 2 only; 1 <-> 3 are joined by two one-way links of 5.0
    dfN = DataFrame(IDX = [1, 2, 3], LON = [0.0, 1.0, 2.0], LAT = [0.0, 1.0, 0.0])
    dfL = DataFrame(SRC = [1, 3, 1, 3], DST = [2, 2, 3, 1], DIST = [1.0, 1.0, 5.0, 5.0], DIR = [1, 1, 1, 1])
    nodes, links = thin(dfN, dfL)
    D = shortestpaths(links2graph(links), 3)[1]
    # CR 25: v0.2.8 merged the one-way chain 3 -> 2 <- 1 as if it ran 3 -> 1 (distance 2.0, and 1 -> 3 is
    # not 5.0 where the second link was dropped); node 2 is a sink, not a pass-through, so it stays
    @test D[1, 3] == 5.0 && D[3, 1] == 5.0
    @test nrow(nodes) == 3 && nrow(links) == 4
end

@testset "[S1] pin: network functions read their columns by position (his 10/11 ruling)" begin
    # nodes and links whose columns are not called IDX/LON/LAT or SRC/DST/DIST
    dfN = DataFrame(NODE = [10, 20, 30, 40, 50], X = [-78.6, -78.5, -78.6, -78.5, -70.0],
                    Y = [35.7, 35.7, 35.8, 35.8, 40.0])
    dfL = DataFrame(A = [10, 20, 30, 10], B = [20, 40, 40, 30], MINUTES = [60.0, 45.0, 30.0, 20.0])
    n2, l2 = prune_reindex(dfN, dfL)                        # node 50 is on no link
    @test names(n2) == ["NODE", "X", "Y"]
    @test n2.NODE == 1:4
    @test sort(unique(vcat(l2.A, l2.B))) == 1:4
    g = links2graph(l2; weight = 3)                         # the third column, whatever it is called
    @test weights(g)[1, 2] == 60.0 && weights(g)[2, 1] == 60.0
    n3, l3 = addconnectors(n2, l2, [-78.55], [35.75]; add_nf_nf = false)
    @test names(n3)[1:3] == ["NODE", "X", "Y"] && names(l3)[1:3] == ["A", "B", "MINUTES"]
    @test nrow(n3) == nrow(n2) + 1 && nrow(l3) > nrow(l2)
    @test n3.NODE == 1:nrow(n3)
    t1, t2 = thin(n2, l2)                                   # reads SRC, DST, DIST and IDX by position too
    @test names(t2) == ["A", "B", "MINUTES", "MERGED"] && names(t1) == ["NODE", "X", "Y"]
end

@testset "[S1] cropnetwork reads its columns by position and takes prune_reindex's column keywords" begin
    # K8: v0.2.8's cropnetwork read r.LON, r.LAT, r.IDX, r.SRC and r.DST by name
    dfN = DataFrame(NODE = [10, 20, 30, 40, 50], X = [-78.6, -78.5, -78.6, -78.5, -70.0],
                    Y = [35.7, 35.7, 35.8, 35.8, 40.0])
    dfL = DataFrame(A = [10, 20, 30, 10, 40], B = [20, 40, 40, 30, 50], MINUTES = [60.0, 45.0, 30.0, 20.0, 5.0])
    cn, cl = cropnetwork(dfN, dfL, [-78.6, -78.5], [35.7, 35.8]; xexpand = 0.1, yexpand = 0.1)
    @test names(cn) == ["NODE", "X", "Y"] && names(cl) == ["A", "B", "MINUTES"]
    @test cn.NODE == 1:4                                     # node 50 is outside the box
    @test nrow(cl) == 4 && sort(cl.MINUTES) == [20.0, 30.0, 45.0, 60.0]
    # the same table with its columns in another order, named
    dfN2 = select(dfN, :Y, :NODE, :X)
    dfL2 = select(dfL, :MINUTES, :B, :A)
    cn2, cl2 = cropnetwork(dfN2, dfL2, [-78.6, -78.5], [35.7, 35.8]; xexpand = 0.1, yexpand = 0.1,
                           src_col = :A, dst_col = :B, node_col = :NODE, x_col = :X, y_col = :Y)
    @test cn2.NODE == 1:4 && nrow(cl2) == 4
    @test sort(Matrix(cl2[:, [:A, :B]]); dims = 1) == sort(Matrix(cl[:, [:A, :B]]); dims = 1)
    # a view is accepted
    cn3, cl3 = cropnetwork(view(dfN, :, :), view(dfL, :, :), [-78.6, -78.5], [35.7, 35.8])
    @test nrow(cn3) == 4 && nrow(cl3) == 4
end

@testset "[N16] addconnectors adds no new-node to new-node connectors unless asked (D8)" begin
    # (a fifth node off the center: four nodes on a square lie on one circle, and a point in the square can
    # then be joined to either diagonal's triangles, one choice from one call to the next)
    dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.0, -79.0, -79.0, -78.5], LAT = [35.0, 36.0, 35.0, 36.0, 35.6])
    dfL = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0], DIR = [0, 1, 0])
    x′, y′ = [-78.2, -78.8, -78.5], [35.2, 35.8, 35.5]
    # v0.2.8 defaulted to add_nf_nf = true (4.1 Code block 40 passes it explicitly now)
    _, L0 = addconnectors(dfN, dfL, x′, y′)
    _, Loff = addconnectors(dfN, dfL, x′, y′; add_nf_nf = false)
    _, Lon = addconnectors(dfN, dfL, x′, y′; add_nf_nf = true)
    @test isequal(L0, Loff)
    @test count(r -> r.SRC <= 3 && r.DST <= 3, eachrow(L0)) == 0
    @test count(r -> r.SRC <= 3 && r.DST <= 3, eachrow(Lon)) == 3
    @test nrow(Lon) == nrow(Loff) + 3
    # the road links are the same either way
    @test count(r -> r.SRC > 3 && r.DST > 3, eachrow(L0)) == nrow(dfL)
end

@testset "[S16] addconnectors' SOURCE column is present, marks the connectors and only them" begin
    # (a fifth node off the center: four nodes on a square lie on one circle, and a point in the square can
    # then be joined to either diagonal's triangles, one choice from one call to the next)
    dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.0, -79.0, -79.0, -78.5], LAT = [35.0, 36.0, 35.0, 36.0, 35.6])
    dfL = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0])
    x′, y′ = [-78.2, -78.8], [35.2, 35.8]
    for nf in (false, true)
        N2, L2 = addconnectors(dfN, dfL, x′, y′; add_nf_nf = nf)
        @test "SOURCE" in names(L2)
        con = isequal.(L2.SOURCE, "CONNECTOR")
        @test count(con) == nrow(L2) - nrow(dfL)
        @test all(ismissing, L2.SOURCE[.!con]) && all(L2.SOURCE[con] .== "CONNECTOR")
        # a connector has a new node (1 or 2) at one end, and the road links are the ones with no new node
        @test all(r -> r.SRC <= 2 || r.DST <= 2, eachrow(L2[con, :]))
        @test all(r -> r.SRC > 2 && r.DST > 2, eachrow(L2[.!con, :]))
    end
    # a table that already has a SOURCE column keeps it
    withsrc = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0], SOURCE = ["FAF5", "FAF5", "FAF5"])
    _, L3 = addconnectors(dfN, withsrc, x′, y′)
    @test all(L3.SOURCE[1:3] .== "FAF5") && all(L3.SOURCE[4:end] .== "CONNECTOR")
end

@testset "[S2] addconnectors' speed fills the connectors' SPEED, and the default call is unchanged (R4)" begin
    # (a fifth node off the center: four nodes on a square lie on one circle, and a point in the square can
    # then be joined to either diagonal's triangles, one choice from one call to the next)
    dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.0, -79.0, -79.0, -78.5], LAT = [35.0, 36.0, 35.0, 36.0, 35.6])
    withspeed = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0], SPEED = [55, 60, 50])
    x′, y′ = [-78.2, -78.8], [35.2, 35.8]
    # the default call: a connector's SPEED is missing, as before
    _, L0 = addconnectors(dfN, withspeed, x′, y′)
    @test all(ismissing, L0.SPEED[4:end]) && L0.SPEED[1:3] == [55, 60, 50]
    # speed = 20 (Lecture 4.2's connector speed): the connectors carry it, the road links keep theirs
    _, L1 = addconnectors(dfN, withspeed, x′, y′; speed = 20)
    con = isequal.(L1.SOURCE, "CONNECTOR")
    @test all(L1.SPEED[con] .== 20) && L1.SPEED[.!con] == [55, 60, 50]
    @test eltype(L1.SPEED) == Int
    @test isequal(select(L1, Not(:SPEED)), select(L0, Not(:SPEED)))          # nothing else changes
    # a table with no SPEED column gets one: missing on the road links
    nospeed = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0])
    _, L2 = addconnectors(dfN, nospeed, x′, y′; speed = 20)
    c2 = isequal.(L2.SOURCE, "CONNECTOR")
    @test all(L2.SPEED[c2] .== 20) && all(ismissing, L2.SPEED[.!c2])
    _, L2b = addconnectors(dfN, nospeed, x′, y′)
    @test !("SPEED" in names(L2b))                                           # no speed, no column
    # a real speed is wanted
    @test_throws ArgumentError addconnectors(dfN, withspeed, x′, y′; speed = 0)
    @test_throws ArgumentError addconnectors(dfN, withspeed, x′, y′; speed = "fast")
    # a fractional speed is allowed; the column then holds Float64
    _, L3 = addconnectors(dfN, withspeed, x′, y′; speed = 17.5)
    @test all(L3.SPEED[isequal.(L3.SOURCE, "CONNECTOR")] .== 17.5)
end
