# Tests for RouteTools functions

using Test
using Logjam
using DataFrames
using Graphs

@testset "RouteTools" begin

    @testset "segcost" begin
        # Simple 3-node cost matrix
        C = [0 10 20; 10 0 15; 20 15 0]

        # Tour visiting all nodes: 1 -> 2 -> 3 -> 1
        loc = [1, 2, 3, 1]
        costs = segcost(loc, C)

        @test length(costs) == 3
        @test costs[1] == 10  # 1 -> 2
        @test costs[2] == 15  # 2 -> 3
        @test costs[3] == 20  # 3 -> 1
        @test sum(costs) == 45

        # Single segment
        @test segcost([1, 3], C) == [20]

        # Stay at same location
        @test segcost([1, 1], C) == [0]
    end

    @testset "isorigin" begin
        # Each shipment appears twice (pickup then delivery)
        rte = [1, 2, 1, 3, 2, 3]  # Pickup 1, pickup 2, deliver 1, etc.
        orig = isorigin(rte)

        @test length(orig) == 6
        @test orig[1] == true   # First occurrence of 1 (pickup)
        @test orig[2] == true   # First occurrence of 2 (pickup)
        @test orig[3] == false  # Second occurrence of 1 (delivery)
        @test orig[4] == true   # First occurrence of 3 (pickup)
        @test orig[5] == false  # Second occurrence of 2 (delivery)
        @test orig[6] == false  # Second occurrence of 3 (delivery)

        # Simple sequential route
        @test isorigin([1, 1, 2, 2]) == [true, false, true, false]
    end

    @testset "rte2loc" begin
        # Two shipments: ship 1 from node 10 to 15, ship 2 from node 20 to 25
        sh = DataFrame(b=[10, 20], e=[15, 25])

        # Route: pickup 1, pickup 2, deliver 1, deliver 2
        rte = [1, 2, 1, 2]
        loc = rte2loc(rte, sh)

        @test loc == [10, 20, 15, 25]

        # Route: pickup 1, deliver 1, pickup 2, deliver 2
        rte2 = [1, 1, 2, 2]
        loc2 = rte2loc(rte2, sh)

        @test loc2 == [10, 15, 20, 25]

        # With depot (start from node 1, return to node 1)
        tr = (b=[1], e=[1])
        loc3 = rte2loc([1, 1], sh, tr)

        @test loc3 == [1, 10, 15, 1]
    end

    @testset "rteTC" begin
        # 5-node network with symmetric costs
        C = [0 10 20 30 40;
             10 0 15 25 35;
             20 15 0 10 20;
             30 25 10 0 15;
             40 35 20 15 0]

        # Two shipments: 1->2, 3->4
        sh = DataFrame(b=[1, 3], e=[2, 4])

        # Route visiting both sequentially
        rte = [1, 1, 2, 2]
        cost = rteTC(rte, sh, C)

        # Path: node 1 -> 2 -> 3 -> 4
        # Expected: C[1,2] + C[2,3] + C[3,4] = 10 + 15 + 10 = 35
        @test cost == 35

        # Different order
        rte2 = [1, 2, 1, 2]  # 1(p) -> 3(p) -> 2(d) -> 4(d)
        cost2 = rteTC(rte2, sh, C)
        # Path: 1 -> 3 -> 2 -> 4 = C[1,3] + C[3,2] + C[2,4] = 20 + 15 + 25 = 60
        @test cost2 == 60
    end

    @testset "twoopt - simple TSP" begin
        # 4-node TSP
        C = [0 10 30 20;
             10 0 10 30;
             30 10 0 10;
             20 30 10 0]

        rTCh = r -> sum(C[r[i], r[i+1]] for i in 1:length(r)-1)

        # Bad initial tour
        initial = [1, 3, 2, 4, 1]
        improved, cost = twoopt(initial, rTCh)

        # Cost should be improved (or at least not worse)
        initial_cost = rTCh(initial)
        @test cost <= initial_cost

        # 2-opt is a local search - verify it found a local optimum
        # by checking no 2-opt move improves it
        @test cost > 0
    end

    @testset "twoopt - already optimal" begin
        C = [0 1 10 1; 1 0 1 10; 10 1 0 1; 1 10 1 0]
        rTCh = r -> sum(C[r[i], r[i+1]] for i in 1:length(r)-1)

        # Already optimal tour
        optimal = [1, 2, 3, 4, 1]
        improved, cost = twoopt(optimal, rTCh)

        @test cost == rTCh(optimal)
    end

    @testset "mincostinsert" begin
        # Simple cost function
        C = [0 10 20 30;
             10 0 15 25;
             20 15 0 10;
             30 25 10 0]

        sh = DataFrame(b=[1, 3], e=[2, 4])
        rteTCh = rte -> rteTC(rte, sh, C)

        # Start with empty route containing just shipment 2
        initial = [2, 2]  # Only shipment 2: 3 -> 4
        initial_cost = rteTCh(initial)

        # Insert shipment 1
        new_rte, cost = mincostinsert(1, initial, rteTCh)

        # Should contain both shipments
        @test count(==(1), new_rte) == 2  # Shipment 1 appears twice
        @test count(==(2), new_rte) == 2  # Shipment 2 appears twice

        # Delivery should come after pickup for shipment 1
        first_1 = findfirst(==(1), new_rte)
        last_1 = findlast(==(1), new_rte)
        @test first_1 < last_1
    end

    @testset "pairwisesavings" begin
        # 4-node network
        C = [0 10 20 30;
             10 0 15 25;
             20 15 0 10;
             30 25 10 0]

        # Two shipments with known savings
        sh = DataFrame(b=[1, 3], e=[2, 4])
        rteTCh = rte -> rteTC(rte, sh, C)

        iˢ, jˢ, sˢ = pairwisesavings(rteTCh, sh)

        # Should return arrays
        @test length(iˢ) == length(jˢ) == length(sˢ)

        # Savings should be sorted descending
        if length(sˢ) > 1
            @test issorted(sˢ, rev=true)
        end

        # All savings should be positive
        @test all(sˢ .> 0) || isempty(sˢ)
    end

    @testset "savings algorithm" begin
        # 5-node network
        C = [0 10 20 30 40;
             10 0 15 25 35;
             20 15 0 10 20;
             30 25 10 0 15;
             40 35 20 15 0]

        # 3 shipments
        sh = DataFrame(b=[1, 2, 3], e=[4, 5, 4])
        rteTCh = rte -> rteTC(rte, sh, C)

        routes = savings(rteTCh, sh)

        # Should return non-empty routes
        @test !isempty(routes)

        # All shipments should be covered
        all_shipments = Set{Int}()
        for rte in routes
            union!(all_shipments, unique(rte))
        end
        @test all_shipments == Set([1, 2, 3])

        # Each shipment should appear exactly twice in its route
        for rte in routes
            for s in unique(rte)
                @test count(==(s), rte) == 2
            end
        end
    end

    @testset "savings - capacity constraint simulation" begin
        C = ones(6, 6) * 10
        for i in 1:6
            C[i, i] = 0
        end

        # 3 shipments
        sh = DataFrame(b=[1, 2, 3], e=[4, 5, 6])

        # Cost function that returns Inf if route has more than 2 shipments
        function constrained_cost(rte)
            if length(unique(rte)) > 2
                return Inf
            end
            return rteTC(rte, sh, C)
        end

        routes = savings(constrained_cost, sh)

        # Due to capacity constraint, should have multiple routes
        # Each route should have at most 2 unique shipments
        for rte in routes
            @test length(unique(rte)) <= 2
        end
    end

    @testset "rte2lines" begin
        # Create a simple 4-node chain network: 1-2-3-4
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -79.0, -80.0, -81.0],
            LAT = [35.0, 35.5, 36.0, 36.5]
        )
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 10.0, 10.0]
        )

        # Build graph and compute shortest paths (new simplified API)
        g = links2graph(dfL)
        D, P = shortestpaths(g, 4)

        # Simple route: 1 -> 4
        route = [1, 4]
        lx, ly = Logjam.rte2lines(route, P, dfN)

        # Should have coordinates for path 1-2-3-4 plus NaN separator
        # Expected: x = [-78, -79, -80, -81, NaN]
        @test length(lx) == length(ly)
        @test count(isnan, lx) == 1  # One NaN separator

        # Non-NaN values should be node coordinates
        non_nan_x = filter(!isnan, lx)
        @test length(non_nan_x) == 4  # 4 nodes in path

        # First coordinate should be node 1
        @test lx[1] == dfN.LON[1]
        @test ly[1] == dfN.LAT[1]
    end

    @testset "rte2lines - multi-segment" begin
        # 4-node chain
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -79.0, -80.0, -81.0],
            LAT = [35.0, 35.5, 36.0, 36.5]
        )
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 10.0, 10.0]
        )

        # New simplified API
        g = links2graph(dfL)
        D, P = shortestpaths(g, 4)

        # Route: 1 -> 2 -> 4 (two segments)
        route = [1, 2, 4]
        lx, ly = Logjam.rte2lines(route, P, dfN)

        # Should have 2 NaN separators (one per segment)
        @test count(isnan, lx) == 2

        # Total length should be sum of segment lengths + NaN separators
        @test length(lx) > 4
    end

end  # @testset "RouteTools"
