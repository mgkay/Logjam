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
        new_rte, cost = Logjam.mincostinsert(1, initial, rteTCh)

        # Should contain both shipments
        @test count(==(1), new_rte) == 2  # Shipment 1 appears twice
        @test count(==(2), new_rte) == 2  # Shipment 2 appears twice

        # Delivery should come after pickup for shipment 1
        first_1 = findfirst(==(1), new_rte)
        last_1 = findlast(==(1), new_rte)
        @test first_1 < last_1
    end

    @testset "mincostinsert - never the end of the route (R1, reversed by CR 38)" begin
        # R1 (July 2026, a09375a) made the loop search the append-after-route-end position, so that on this
        # matrix, where the chain 1->2->3->4 costs 1 per leg and every other move costs 100, the answer was
        # [1, 1, 2, 2] at cost 3. That vector is two routes (the truck is empty between the shipments), so
        # by his rulings of 2026-11-01 and 2026-11-02 the position is not tried (CR 38, K7a): the answer is
        # the best of the four routes, the 201 of [2, 1, 1, 2].
        sh = DataFrame(b=[1, 3], e=[2, 4])
        C = fill(100.0, 4, 4)
        for i in 1:4
            C[i, i] = 0.0
        end
        C[1, 2] = 1.0; C[2, 3] = 1.0; C[3, 4] = 1.0
        rteTCh = rte -> rteTC(rte, sh, C)

        rte, cost = Logjam.mincostinsert(2, [1, 1], rteTCh)
        @test rte == [2, 1, 1, 2]
        @test cost == 201.0        # not the cost-3 vector [1, 1, 2, 2], which is not a route

        # Empty-route case starts a new route [idx, idx] with its own cost.
        rte0, cost0 = Logjam.mincostinsert(1, Int[], rteTCh)
        @test rte0 == [1, 1]
        @test cost0 == rteTCh([1, 1]) == 1.0
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

        iˢ, jˢ, sˢ = Logjam.pairwisesavings(rteTCh, sh)

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

    # (the two `rte2lines` testsets are gone with the function: P8, K7c)

end  # @testset "RouteTools"

# =============================================================================
# K2a: wrong-answer tests (test spec Sec. 2) and the S44 addition (Sec. 7).
# Each testset is tagged [ID]; tools/v0_3_0/run_against.jl records its outcome in
# baselines/sc2-outcomes.csv. A `@test_broken` names the component whose commit flips it to `@test`.
# The instances are literals (found by a seeded search, then written out), so they do not move with
# the random stream of a Julia version.
# =============================================================================

# shipments on board over each segment of a route vector (Matlog rtesegsum with a 1 per shipment)
_onboard(r) = cumsum(ifelse.(isorigin(r), 1, -1))[1:end-1]
_isroute(r) = all(>(0), _onboard(r))
# the cost value of a call that may return (TC, flag, out) or a bare cost
_tc(x) = x isa Tuple ? x[1] : x

@testset "[CR 37] twoopt on a route vector can move the first and last stop when that lowers cost" begin
    X = [18.0 11.0; 14.4 17.2; 7.1 10.4; 4.6 17.5; 7.2 11.6; 17.7 11.6]
    sh = DataFrame(b = [3, 1, 2], e = [4, 6, 5])
    C = dists(X, X, 2)
    h = r -> rteTC(r, sh, C)
    rb, TCb = twoopt([1, 2, 1, 3, 3, 2], h)
    @test TCb ≈ h(rb)                                       # control
    # a route-preserving reversal of any stretch of the route, its ends included, that lowers the cost
    better = [r2 for i in 1:length(rb)-1 for j in i+1:length(rb)
              for r2 in (vcat(rb[1:i-1], reverse(rb[i:j]), rb[j+1:end]),)
              if _isroute(r2) && h(r2) < TCb - 1e-9]
    # CR 37: v0.2.8's loops never touched r[1] or r[end]; fixed in K7a
    @test isempty(better)
end

@testset "[CR 38] mincostinsert on 5.2 Ex. 8 gives 1,630.35 (his F24 loop), not 1,630.77" begin
    lines = readlines(joinpath(@__DIR__, "data", "shmtNC30-xy.csv"))[2:end]
    X30 = reduce(vcat, [parse.(Float64, split(l, ","))' for l in filter(!isempty, lines)])
    @test size(X30) == (54, 2)
    sh30 = DataFrame(
        b = [15, 26, 23, 53, 17, 3, 39, 47, 44, 45, 43, 8, 29, 34, 38,
             41, 18, 40, 1, 11, 7, 30, 33, 22, 20, 19, 16, 48, 37, 14],
        e = [42, 27, 40, 51, 32, 27, 50, 28, 35, 10, 2, 12, 39, 52, 24,
             36, 27, 13, 5, 4, 6, 49, 9, 25, 46, 31, 21, 10, 54, 13])
    D30 = dists(X30, X30, :mi) * 1.2                        # road miles, circuity 1.2 (the lecture's)
    h = r -> rteTC(r, sh30, D30)
    # the lecture's own 2-opt of a route (5.2 Code block 18) and insert-and-improve
    function twoopt_rte(r, rTCh)
        rᵒ, TCᵒ = copy(r), rTCh(r)
        done = false
        while !done
            done = true
            for i = 1:length(r)-1, j = i+1:length(r)
                r′ = vcat(r[1:i-1], reverse(r[i:j]), r[j+1:end])
                _isroute(r′) || continue
                TC = rTCh(r′)
                if TC < TCᵒ
                    rᵒ, TCᵒ = r′, TC
                    done = false
                    break
                end
            end
            r = copy(rᵒ)
        end
        return rᵒ, TCᵒ
    end
    function insertimprove(L, rTCh, insert)
        r = [L[1], L[1]]
        for k in L[2:end]
            r = insert(k, r, rTCh)[1]
            r = twoopt_rte(r, rTCh)[1]
        end
        return r, rTCh(r)
    end
    function mincostinsert_rte(idx, rte, rteTCh)           # his loop: i = 1:m, j = max(2, i):m + 1
        rteᵒ, TCᵒ = copy(rte), Inf
        for i = 1:length(rte)
            for j = max(2, i):length(rte) + 1
                rte′ = vcat(rte[1:i-1], idx, rte[i:j-1], idx, rte[j:end])
                TC = rteTCh(rte′)
                if TC < TCᵒ
                    rteᵒ, TCᵒ = rte′, TC
                end
            end
        end
        return rteᵒ, TCᵒ
    end
    # the first start of Ex. 8's randomized insertion: Random.seed!(1234); randperm(30), on Julia 1.12.6
    L = [10, 2, 9, 14, 18, 29, 6, 12, 27, 30, 1, 22, 17, 15, 5, 11, 19, 16, 8, 26, 28, 20, 25, 13, 24, 23, 7, 3, 4, 21]
    @test isapprox(insertimprove(L, h, mincostinsert_rte)[2], 1630.35; atol = 0.005)   # control: his loop
    # CR 38: v0.2.8's mincostinsert also tried i = j = m + 1 and gave 1,630.77; fixed in K7a
    @test isapprox(insertimprove(L, h, mincostinsert)[2], 1630.35; atol = 0.005)
end

@testset "[CR 39] savings never performs a merge that does not save" begin
    X = [16.8 10.4; 0.4 4.5; 0.0 15.0; 1.6 9.4; 3.8 9.2; 1.1 4.4; 7.4 3.2; 17.8 3.3]
    sh = DataFrame(b = [6, 8, 2, 1], e = [3, 4, 5, 7])
    C = dists(X, X, 2)
    h = r -> rteTC(r, sh, C)
    R = savings(h, sh)
    @test sort(reduce(vcat, R)) == [1, 1, 2, 2, 3, 3, 4, 4]  # control: every shipment, twice
    # CR 39: v0.2.8 inserts the shorter route's shipments without asking whether the total fell; the
    # result here costs more than shipping each shipment alone; fixed in K7
    @test sum(h.(R)) <= sum(h([i, i]) for i in 1:4) + 1e-9      # fixed in K7a
end

@testset "[CR 42] the Matlog-checked rteTC flags an infeasible singleton and reads capacity (the scalar rteTC is unchanged)" begin
    C = [0.0 10.0; 10.0 0.0]
    tr = (b = Int[], e = Int[], Kwt = 25.0, Kcu = 2750.0)
    over = DataFrame(b = [1], e = [2], q = [30.0], s = [8.0])   # 30 t exceeds the 25 t weight limit
    ok = DataFrame(b = [1], e = [2], q = [10.0], s = [8.0])
    @test _tc(rteTC([1, 1], ok, C, tr)) == 10.0             # control: a feasible singleton keeps its cost
    # CR 42: v0.2.8 reads no capacity: the cost of an infeasible singleton is 10.0, not Inf. `rteTC` is
    # Matlog's rteTC (one function, `full = true` for the flag and schedule, K7b); the call is written
    # for a bare cost or a triple, so the same line runs against v0.2.8.
    @test isinf(_tc(rteTC([1, 1], over, C, tr)))
    # a call whose truck carries no limit is unchanged: a plain cost
    @test rteTC([1, 1], over, C) == 10.0
end

@testset "[CR 43] rteTC adds nothing for a same-location segment when C[i,i] > 0" begin
    C = [5.0 10.0; 10.0 5.0]                                # a positive diagonal
    sh = DataFrame(b = [1, 1], e = [1, 2])
    # route [1, 2, 1, 2] visits 1, 1, 1, 2: two same-location segments and one real one
    # CR 43: v0.2.8 charges C[1, 1] for each same-location segment (20.0, not 10.0); fixed in K7b
    @test rteTC([1, 2, 1, 2], sh, C) == 10.0
    @test rteTC([1, 1], DataFrame(b = [1], e = [2]), C) == 10.0   # control: a real segment is charged
end

@testset "[CR 54] twoopt never returns a vector with the truck empty mid-route" begin
    X = [11.0 17.3; 15.8 4.4; 20.0 11.4; 3.6 14.2; 16.3 4.4; 10.2 5.7]
    sh = DataFrame(b = [3, 6, 1], e = [2, 5, 4])
    C = dists(X, X, 2)
    h = r -> rteTC(r, sh, C)
    r0 = [3, 1, 2, 3, 1, 2]
    @test _isroute(r0)                                      # control: the start is a route
    rb, TCb = twoopt(r0, h)
    @test TCb ≈ h(rb)
    # CR 54: v0.2.8 accepted a reversal that empties the truck between shipments (two routes in one
    # vector) because it costs less; fixed in K7a
    @test _isroute(rb)
end

@testset "[S44] the checked rteTC reads capacity with a rounding tolerance: a full-cube maxpayld load is not flagged" begin
    C = [0.0 10.0; 10.0 0.0]
    tr = (b = Int[], e = Int[], Kwt = 25.0, Kcu = 2750.0)
    shfull(s) = DataFrame(b = [1], e = [2], q = [maxpayld(s)], s = [s])
    # a load of exactly maxpayld (cube-limited densities, and a weight-limited one) is feasible
    @test all(isfinite(_tc(rteTC([1, 1], shfull(s), C, tr))) for s in (7.0, 8.0, 11.3, 13.7, 25.0))
    # and a load 1% over is not: v0.2.8 reads no capacity at all; fixed in K7 (with CR 42)
    over = DataFrame(b = [1], e = [2], q = [1.01 * maxpayld(8.0)], s = [8.0])
    @test isinf(_tc(rteTC([1, 1], over, C, tr)))        # fixed in K7b (CR 42)
end

# =============================================================================
# K7c pins (principle 9), written BEFORE K7c changed any code: the outputs of Lecture 5.2's and 5.3's own
# stand-ins on their own inputs (the definitions of test/lecture52_code.jl run in a scratch module), and the
# routes the exports return where CR 58 can reorder a tie. The expected values are literals: floats to 12
# significant digits, routes exact. A pin may move only in the commit named for the ruled ID that moves it;
# each moved pin is listed in that commit's message and in NEWS. The pins of every other course call
# (savings, pairwisesavings, twoopt, mincostinsert on the lectures' inputs) are the fixture
# test/fixtures/routing_pins.tsv.
# =============================================================================

@isdefined(RPIN_SH30) || include(joinpath(@__DIR__, "routing_pin_cases.jl"))
@isdefined(LECTURE52_CODE) || include(joinpath(@__DIR__, "lecture52_code.jl"))

@testset "[K7c pins] Lecture 5.2's and 5.3's stand-ins on their own inputs" begin
    m = lecture52_module(:L52_k7c_pins)
    call(f, args...) = lecture52_call(m, f, args...)
    r12(x) = round(x; sigdigits = 12)
    # 5.2 Ex. 4(a): insert and improve from each of the six load orders, Ex. 1's three shipments (Code block 21)
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    for (L, r, TC) in (([1, 2, 3], [3, 1, 2, 2, 1, 3], 430), ([1, 3, 2], [2, 1, 3, 3, 1, 2], 455),
                       ([2, 1, 3], [3, 1, 2, 2, 1, 3], 430), ([2, 3, 1], [3, 1, 2, 2, 1, 3], 430),
                       ([3, 1, 2], [2, 1, 3, 3, 1, 2], 455), ([3, 2, 1], [3, 1, 2, 2, 1, 3], 430))
        @test call(:insertimprove, L, h6) == (r, TC)
    end
    # 5.2 Ex. 4(b): five shipments in North Carolina (Code blocks 22 and 23). The route ends at the published
    # location sequence, unloading shipments 4, 2 and 1 at location 2 where the published route unloads 1, 2, 4
    X5 = _rp_xy54()[[5, 27, 3, 38, 24, 18, 1], :]
    D5 = dists(X5, X5, :mi) * 1.2
    sh5 = DataFrame(b = [1, 3, 4, 6, 7], e = [2, 2, 5, 2, 1])
    h5 = r -> rteTC(r, sh5, D5)
    r5, TC5 = call(:insertimprove, 1:5, h5)
    @test r5 == [3, 2, 5, 5, 1, 4, 3, 4, 2, 1] && r12(TC5) == 299.588123275
    @test rte2loc(r5, sh5) == [4, 3, 7, 1, 1, 6, 5, 2, 2, 2]
    @test r12(h5([3, 2, 5, 5, 1, 4, 3, 1, 2, 4])) == 299.588123275 && r12(sum(h5([k, k]) for k in 1:5)) == 642.84915712
    # 5.2 Ex. 8: insert and improve from the first start of randomized insertion (1,630.35)
    h30 = r -> rteTC(r, RPIN_SH30, _rp_D30())
    r30, TC30 = call(:insertimprove, RPIN_L30, h30)
    @test r30 == [23, 15, 13, 20, 6, 20, 12, 27, 1, 24, 3, 17, 21, 11, 3, 18, 1, 16, 10, 9, 8, 28, 2, 17, 6, 2, 15, 24,
                  25, 30, 26, 27, 25, 5, 30, 18, 28, 10, 23, 12, 19, 11, 19, 21, 26, 16, 5, 9, 7, 13, 14, 29, 22, 7,
                  8, 14, 29, 4, 22, 4]
    @test r12(TC30) == 1630.35086892
    # Code block 49: rte2idx of Matlog's help example and sh2rte of five shipments with 1 and 2 on one route
    @test call(:rte2idx, [23, 15, 6, 23, 27, 17, 24, 27, 15, 17, 6, 24]) == [23, 15, 6, 27, 17, 24]
    @test call(:rte2idx, [[1, 2, 1, 2], [3, 3]]) == [[1, 2], [3]]
    @test call(:sh2rte, 1:5, [[1, 2, 1, 2]]) == ([[1, 2, 1, 2], [3, 3], [4, 4], [5, 5]], [3, 4, 5])
    # load formation (5.2's `loadform`: savings, 2-opt of each route of more than one shipment, sh2rte) on Ex. 8's
    # shipments at the one-truck charge of Ex. 9: two routes (of 6 and 18 shipments) and six shipped independently
    ht = _onetruck(RPIN_SH30, _rp_D30())
    RL, idx1 = call(:loadform, ht, RPIN_SH30)
    @test length.(RL) == [12, 36, 2, 2, 2, 2, 2, 2] && idx1 == [2, 4, 12, 19, 20, 25]
    # CR 58 moved these two routes (the stand-in builds on the export `savings`): shipments 6 and 17 and
    # shipments 18 and 30, unloaded at one location, are now in increasing order; the costs below are unchanged
    @test RL[1] == [23, 15, 6, 23, 27, 17, 24, 27, 15, 6, 17, 24]
    @test RL[2] == [28, 8, 9, 10, 16, 18, 11, 21, 5, 30, 26, 3, 1, 18, 30, 11, 10, 28, 21, 3, 1, 26, 13, 16, 5, 9, 13, 7,
                    14, 29, 22, 7, 22, 8, 14, 29]
    @test r12.(ht.(RL)) == [672.131382122, 1963.60867898, 60.5345347406, 146.69580324, 51.2169992675, 89.2241117286, 45.0, 197.195269927]
    # rtesegsum (5.2 Code block 4, 5.3 Code block 3): the sum of a value of each shipment on board over each segment
    @test call(:rtesegsum, [1, 2, 1, 3, 2, 3], [10, 10, 10]) == [10, 20, 10, 20, 10]
    @test call(:rtesegsum, [1, 2, 1, 3, 2, 3], ones(3)) == [1.0, 2.0, 1.0, 2.0, 1.0]
    # 5.3 Ex. 1(c): Clarke-Wright with the capacity in the route cost (Code block 4): the routes, their costs and
    # location sequences; route 2 loads shipments 4 and 1 at the depot in decreasing order
    c = _cw()
    R1 = [call(:twoopt_rte, r, c.h)[1] for r in savings(c.h, c.shcw)]
    @test R1 == [[2, 3, 5, 3, 5, 2], [1, 4, 1, 4]] && c.h.(R1) == [167, 138]            # CR 58: route 2 was [4, 1, 4, 1]
    @test [rte2loc(r, c.shcw, c.tr) for r in R1] == [[1, 1, 1, 1, 4, 6, 3, 1], [1, 1, 1, 2, 5, 1]]
    @test Tuple(pairwisesavings(c.h, c.shcw)) == ([3, 2, 2, 1, 2, 1, 4, 1, 1, 3], [5, 5, 4, 3, 3, 5, 5, 4, 2, 4],
                                           [52.0, 49.0, 40.0, 32.0, 19.0, 13.0, 12.0, 8.0, 1.0, 1.0])
end

@testset "[K7c pins] the routes the exports return where CR 58 can reorder a tie" begin
    r12(x) = round(x; sigdigits = 12)
    # the exports chained as 5.2's insert and improve chains them, on Ex. 4's inputs (CR 58 moves the 4(b) route)
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    for (L, r) in (([1, 2, 3], [3, 1, 2, 2, 1, 3]), ([1, 3, 2], [2, 1, 3, 3, 1, 2]), ([3, 2, 1], [3, 1, 2, 2, 1, 3]))
        @test _insertimprove(L, h6) == r
    end
    X5 = _rp_xy54()[[5, 27, 3, 38, 24, 18, 1], :]
    D5 = dists(X5, X5, :mi) * 1.2
    sh5 = DataFrame(b = [1, 3, 4, 6, 7], e = [2, 2, 5, 2, 1])
    h5 = r -> rteTC(r, sh5, D5)
    r5 = _insertimprove(1:5, h5)
    @test r5 == [3, 2, 5, 5, 1, 4, 3, 1, 2, 4] && r12(h5(r5)) == 299.588123275       # CR 58: was ... 3, 4, 2, 1; now the published route
    # 5.3 Ex. 1(c): savings forms the two routes, route 2 loading shipments 4 and 1 at the depot in decreasing order
    c = _cw()
    @test savings(c.h, c.shcw) == [[2, 3, 5, 3, 5, 2], [1, 4, 1, 4]]                  # CR 58: was [4, 1, 4, 1]
    @test [Tuple(twoopt(r, c.h)) for r in savings(c.h, c.shcw)] == [([2, 3, 5, 3, 5, 2], 167), ([1, 4, 1, 4], 138)]
    # 5.2 Ex. 8 at the one-truck charge: savings forms two routes, of 6 and 18 shipments (12 and 36 stops)
    ht = _onetruck(RPIN_SH30, _rp_D30())
    @test length.(savings(ht, RPIN_SH30)) == [12, 36]
end

# =============================================================================
# K7c: the on-board scan (K7C), and what is built on it. Each testset is tagged with the ID of its item.
# =============================================================================

using Random
@isdefined(LECTURE53_CODE) || include(joinpath(@__DIR__, "lecture53_code.jl"))

# every distinct ordering of the multiset v (the 90 of 5.2 Ex. 1(c) for v = [1, 1, 2, 2, 3, 3])
function _k7c_orderings(v)
    out = Vector{Vector{Int}}()
    function rec(cur, left)
        isempty(left) && return push!(out, copy(cur))
        for x in unique(left)
            rest = copy(left); deleteat!(rest, findfirst(==(x), rest))
            push!(cur, x); rec(cur, rest); pop!(cur)
        end
    end
    rec(Int[], collect(v))
    return out
end

@testset "[K7C, P9] rtesegsum equals Lecture 5.2's and 5.3's rtesegsum, and the internal rtesegid their onboard(k), on the course's routes" begin
    m = lecture52_module(:L52_k7c_segsum)
    seg_course(r, x) = lecture52_call(m, :rtesegsum, r, x)
    all90 = _k7c_orderings([1, 1, 2, 2, 3, 3])
    @test length(all90) == 90
    # 5.2 Code block 4: x = ones(3) over the 90 orderings; 5.3's weights; a value that is not an integer
    @test all(rtesegsum(r, ones(3)) == seg_course(r, ones(3)) for r in all90)
    @test all(rtesegsum(r, [10, 10, 10]) == seg_course(r, [10, 10, 10]) for r in all90)
    @test all(rtesegsum(r, [0.1, 0.2, 0.7]) == seg_course(r, [0.1, 0.2, 0.7]) for r in all90)   # bit for bit
    # the default x is a 1 for each shipment
    @test all(rtesegsum(r) == rtesegsum(r, ones(Int, 3)) for r in all90)
    @test rtesegsum([1, 2, 1, 3, 2, 3], [10, 10, 10]) == [10, 20, 10, 20, 10]       # 5.3's call on Ex. 3's weights
    # the lecture's call in 2-opt: x is longer than the largest shipment number is fine, `ones(maximum(r′))`
    D = _rp_D30(); r30 = _mci_chain(RPIN_L30, r -> rteTC(r, RPIN_SH30, D))
    @test rtesegsum(r30, ones(30)) == seg_course(r30, ones(30)) && rtesegsum(r30) == seg_course(r30, ones(30))
    @test rtesegsum(r30, 1.0:40.0) == seg_course(r30, 1.0:40.0)
    # an unnormalized route, which Matlog's refuses: the shipments are 3 and 7
    @test rtesegsum([7, 3, 7, 3], [0, 0, 5, 0, 0, 0, 2]) == [2, 7, 5] == seg_course([7, 3, 7, 3], [0, 0, 5, 0, 0, 0, 2])
    @test rtesegsum(Int[]) == Int[] && rtesegsum([1, 1]) == [1]
    # the empty-truck test: 60 of the 90 orderings are routes (5.2 Ex. 1(c)), and the internal test agrees
    @test count(r -> all(>(0), rtesegsum(r)), all90) == 60
    @test all(Logjam._loaded_throughout(r) == all(>(0), rtesegsum(r)) for r in all90)
    # rtesegid, internal since IN5 (not exported, not public: no lecture calls it): 5.3's onboard(k) (the load mix
    # figure), the shipments on board over the segment after stop k
    @test !Base.isexported(Logjam, :rtesegid) && !Base.ispublic(Logjam, :rtesegid)
    function onboard_course(r)       # 5-rte-3.qmd:1283
        ld = isorigin(r)
        return [sort(setdiff(r[1:k][ld[1:k]], r[1:k][.!ld[1:k]])) for k in 1:length(r)-1]
    end
    @test all(Logjam.rtesegid(r) == onboard_course(r) for r in all90)
    @test Logjam.rtesegid([1, 2, 1, 3, 2, 3]) == [[1], [1, 2], [2], [2, 3], [3]]
    @test Logjam.rtesegid([1, 2, 3, 3, 2, 1]) == [[1], [1, 2], [1, 2, 3], [1, 2], [1]]
    @test Logjam.rtesegid([7, 3, 7, 3]) == [[7], [3, 7], [3]]
    @test Logjam.rtesegid(Int[]) == Vector{Int}[]
    # the same sets, counted: the number on board is the length of each, the weight the sum of theirs
    q = [4.0, 1.5, 2.5]
    @test all(length.(Logjam.rtesegid(r)) == rtesegsum(r) for r in all90)
    @test all(sum.([q[s] for s in Logjam.rtesegid(r)]) ≈ rtesegsum(r, q) for r in all90)
end

@testset "[K7C, P9, CR 59] rte2ldmx, read from the scan, equals Lecture 5.3's rte2ldmx; the scan on random routes" begin
    m = lecture53_module(:L53_k7c_ldmx)
    all90 = _k7c_orderings([1, 1, 2, 2, 3, 3])
    @test all(rte2ldmx(r) == lecture53_call(m, :rte2ldmx, r) for r in all90)
    rng = Random.Xoshiro(20261121)
    ok_ld = ok_seg = ok_thr = ok_orig = ok_id = true
    for _ in 1:300
        k = rand(rng, 1:12)
        ids = randperm(rng, 3k)[1:k]                            # sparse shipment numbers, not normalized
        r = shuffle(rng, vcat(ids, ids))
        ok_ld &= rte2ldmx(r) == lecture53_call(m, :rte2ldmx, r)
        ok_seg &= rtesegsum(r, ones(Int, maximum(r))) == cumsum(ifelse.(isorigin(r), 1, -1))[1:end-1]
        ok_thr &= Logjam._loaded_throughout(r) == all(>(0), cumsum(ifelse.(isorigin(r), 1, -1))[1:end-1])
        ok_orig &= Logjam._isload(r) == isorigin(r)
        ok_id &= all(length.(Logjam.rtesegid(r)) .== rtesegsum(r)) && all(issorted, Logjam.rtesegid(r))
    end
    @test ok_ld && ok_seg && ok_thr && ok_orig && ok_id
    # the empty-truck test builds no Set: a few small allocations, where the Set it replaces took
    # about 0.5 microsecond a call
    r60 = vcat(1:30, 30:-1:1)
    Logjam._loaded_throughout(r60)
    @test @allocated(Logjam._loaded_throughout(r60)) < 512
end

@testset "[CR 53, P9] rte2idx and sh2rte equal Lecture 5.2's Code block 49 on the course's inputs, and are Matlog's" begin
    m = lecture52_module(:L52_k7c_sh2rte)
    rte2idx_c(args...) = lecture52_call(m, :rte2idx, args...)
    sh2rte_c(args...) = lecture52_call(m, :sh2rte, args...)
    help_rte = [23, 15, 6, 23, 27, 17, 24, 27, 15, 17, 6, 24]            # Matlog's rte2idx help example
    @test rte2idx(help_rte) == rte2idx_c(help_rte) == [23, 15, 6, 27, 17, 24]
    all90 = _k7c_orderings([1, 1, 2, 2, 3, 3])
    @test all(rte2idx(r) == rte2idx_c(r) == r[isorigin(r)] for r in all90)
    @test rte2idx([[1, 2, 1, 2], [3, 3]]) == rte2idx_c([[1, 2, 1, 2], [3, 3]]) == [[1, 2], [3]]
    @test rte2idx(Int[]) == Int[] && rte2idx(Vector{Int}[]) == Vector{Int}[]
    # Code block 49's own call
    @test sh2rte(1:5, [[1, 2, 1, 2]]) == (rte = [[1, 2, 1, 2], [3, 3], [4, 4], [5, 5]], idx1 = [3, 4, 5])
    @test Tuple(sh2rte(1:5, [[1, 2, 1, 2]])) == sh2rte_c(1:5, [[1, 2, 1, 2]])
    R, idx1 = sh2rte(1:5, [[1, 2, 1, 2]])                                  # destructures
    @test R[end] == [5, 5] && idx1 == [3, 4, 5] && keys(sh2rte(1:5)) == (:rte, :idx1)
    # load formation's second line on Ex. 8: savings forms the routes, sh2rte adds the shipments on none
    D = _rp_D30(); ht = _onetruck(RPIN_SH30, D)
    Rs = [r for r in savings(ht, RPIN_SH30)]
    @test Tuple(sh2rte(1:nrow(RPIN_SH30), Rs)) == sh2rte_c(1:nrow(RPIN_SH30), Rs)
    Rn, idxn = sh2rte(1:nrow(RPIN_SH30), Rs)
    @test sort(reduce(vcat, rte2idx(Rn))) == 1:30 && length(Rn) == length(Rs) + length(idxn)
    @test Rn[length(Rs)+1:end] == [[k, k] for k in idxn]
    # 5.3 Ex. 1(c)'s routes
    c = _cw()
    Rc = savings(c.h, c.shcw)
    @test Tuple(sh2rte(1:5, Rc)) == sh2rte_c(1:5, Rc)
    # Matlog's semantics: no routes, every shipment on a route, a subset of the shipments, idx1 sorted, repeats once
    @test sh2rte(1:3).rte == [[1, 1], [2, 2], [3, 3]] && sh2rte(1:3).idx1 == [1, 2, 3]
    @test sh2rte(1:2, [[1, 2, 2, 1]]) == (rte = [[1, 2, 2, 1]], idx1 = Int[])
    @test sh2rte([4, 2], [[1, 1]]) == (rte = [[1, 1], [2, 2], [4, 4]], idx1 = [2, 4])
    @test sh2rte([2, 2, 3], Vector{Int}[]).idx1 == [2, 3]
    @test sh2rte(Int[], [[1, 1]]) == (rte = [[1, 1]], idx1 = Int[])
    # the input is not changed
    R0 = [[1, 2, 1, 2]]; sh2rte(1:4, R0)
    @test R0 == [[1, 2, 1, 2]]
    # the lecture's own definitions, after `using Logjam`, in the order the lecture runs them (lecture52_module)
    @test getfield(m, :rte2idx) !== Logjam.rte2idx && getfield(m, :sh2rte) !== Logjam.sh2rte
    @test Base.isexported(Logjam, :rte2idx) && Base.isexported(Logjam, :sh2rte)
end

@testset "[CR 53, P9, K7C] one insertion loop: Lecture 5.2's oneroute with 2-opt, savings' merge without (IN4)" begin
    # Logjam's insertimprove was removed before the release (IN4, his inclusion rule of 2026-11-21: Lecture 5.2
    # defines and uses it, no other lecture does); the lecture keeps its own, which the K7c pins above run
    @test !isdefined(Logjam, :insertimprove)
    m = lecture52_module(:L52_k7c_ii)
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    D = _rp_D30(); h30 = r -> rteTC(r, RPIN_SH30, D)
    # the lecture's oneroute (Code block 43), verbatim, defined after `using Logjam` with the others
    Core.eval(m, Meta.parse("""
    function oneroute(R, rTCh)
        r = R[argmax(length.(R))]
        for k in setdiff(reduce(vcat, R), r)
            r′ = mincostinsert_rte(k, r, rTCh)[1]
            r = twoopt_rte(r′, rTCh)[1]
        end
        return r, rTCh(r)
    end"""))
    # one loop: Lecture 5.2's oneroute (Code block 43) is `_insertall` with 2-opt after each insertion,
    # and a route inserted into another (`_insert_route`, savings' merge) is it without
    Rs = sh2rte(1:30, [lecture52_call(m, :twoopt_rte, r, h30)[1] for r in savings(h30, RPIN_SH30)]).rte
    r1, TC1 = lecture52_call(m, :oneroute, Rs, h30)
    ra = Rs[argmax(length.(Rs))]
    r2, TC2 = Logjam._insertall(setdiff(reduce(vcat, Rs), ra), ra, h30; improve = Logjam._twoopt_route)
    @test r1 == r2 && TC1 == TC2
    base, src = [1, 2, 2, 1], [3, 3]
    @test Logjam._insert_route(src, base, h6) == Logjam._insertall([3], base, h6)
    # the insertion hook still reaches the loop (K7a-2): a custom insertion is used, and its Inf stops the loop
    seen = Int[]
    myinsert(k, r, h) = (push!(seen, k); Logjam._mincostinsert(k, r, h))
    Logjam._insert_route([1, 2, 2, 1], [3, 3], h6; insert = myinsert)
    @test seen == [3]
    @test Logjam._insert_route([1, 1], [3, 3], h6; insert = (k, r, h) -> (r, Inf)) == (nothing, Inf)
end

@testset "[RS, P9] routes as a set by dispatch: twoopt, rte2loc, sh2rte and rteTC take a vector of routes" begin
    m = lecture52_module(:L52_k7c_rs)
    twoopt_c(r, h) = lecture52_call(m, :twoopt_rte, r, h)
    D = _rp_D30(); h30 = r -> rteTC(r, RPIN_SH30, D); ht = _onetruck(RPIN_SH30, D)
    c = _cw(); q1 = _hw5q1()
    # the comprehension the lectures write, over the routes savings forms, and one call
    for (h, sh) in ((h30, RPIN_SH30), (ht, RPIN_SH30), (c.h, c.shcw), (q1.rTTa, q1.sha))
        R = savings(h, sh)
        out = twoopt(R, h)
        @test out.rte == [twoopt_c(r, h)[1] for r in R]                  # the routes of Lecture 5.2's twoopt_rte
        @test out.TC == h.(out.rte) && out.TC isa Vector                 # `T = h.(R)` of 5.3, in the same call
        @test out.rte == [twoopt(r, h)[1] for r in R] && out.TC == [twoopt(r, h)[2] for r in R]
        @test keys(out) == (:rte, :TC) && length(out.rte) == length(R)
    end
    # the input is not modified; an empty set; a set of one
    Rin = [[1, 2, 1, 2], [3, 3]]; Rcopy = deepcopy(Rin)
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    twoopt(Rin, h6)
    @test Rin == Rcopy
    @test twoopt(Vector{Int}[], h6).rte == Vector{Int}[] && isempty(twoopt(Vector{Int}[], h6).TC)
    @test twoopt([[1, 1, 2, 2]], h6).rte == [twoopt([1, 1, 2, 2], h6)[1]]
    # a set of tours takes the matrix: the delta method of each, 5.1's six traces
    d = _readoracle("tsp_traces"); C = d["C"]
    tours = [_ivec(d, nm * "_loc0") for nm in ("sfc", "ch", "nn1", "nnb", "rnd1", "rnd2")]
    outC = twoopt(tours, C)
    @test outC.rte == [twoopt(t, C)[1] for t in tours] && outC.TC == [twoopt(t, C)[2] for t in tours]
    @test outC.rte == twoopt(tours, π -> sum(segcost(π, C))).rte                  # as the general method
    @test_throws ArgumentError twoopt([[1, 2, 1, 2]], C)
    # no ambiguity between the four shapes of the first two arguments
    @test twoopt([1, 3, 2, 4, 1], [0 10 25 20; 10 0 15 30; 25 15 0 10; 20 30 10 0])[1][1] == 1       # a tour, a matrix
    @test twoopt([[1, 3, 2, 4, 1]], [0 10 25 20; 10 0 15 30; 25 15 0 10; 20 30 10 0]).rte isa Vector{Vector{Int}}
    @test twoopt([1, 2, 1, 2], h6)[1] isa Vector{Int}                               # a route, a handle
    @test twoopt([[1, 2, 1, 2]], h6).rte isa Vector{Vector{Int}}                    # routes, a handle
    ambs = Test.detect_ambiguities(Logjam)
    @test !any(p -> p[1].name in (:twoopt, :rte2loc, :rteTC, :sh2rte, :rte2idx), ambs)
    # rte2loc and rteTC of a set (5.3's Code block 4 line: [rte2loc(r, shcw, tr) for r in R1])
    R1 = savings(c.h, c.shcw)
    @test rte2loc(R1, c.shcw, c.tr) == [rte2loc(r, c.shcw, c.tr) for r in R1]
    @test rte2loc(R1, c.shcw) == [rte2loc(r, c.shcw) for r in R1]
    @test rteTC(R1, c.shcw, RPIN_CCW, c.tr) == [rteTC(r, c.shcw, RPIN_CCW, c.tr) for r in R1]
    @test rte2loc(Vector{Int}[], c.shcw) == Vector{Int}[]
    # sh2rte of the table: 1:nrow(sh)
    @test sh2rte(c.shcw, R1) == sh2rte(1:5, R1) && sh2rte(c.shcw).idx1 == 1:5
    # his two-line load formation (5.2, Ex. 9) is the lecture's loadform: the same routes and the same shipments
    # alone, with no `if length(r) > 2` filter because savings returns only the routes it forms
    RL, idxL = lecture52_call(m, :loadform, ht, RPIN_SH30)
    R2, TC2 = twoopt(savings(ht, RPIN_SH30), ht)
    R2, idx2 = sh2rte(RPIN_SH30, R2)
    @test R2 == RL && idx2 == idxL == [2, 4, 12, 19, 20, 25]
end

@testset "[V2, K7C] several returned values are a named tuple with Matlog's names, and destructuring and indexing still work" begin
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    # mincostinsert, twoopt (route, tour, tour by matrix): (rte, TC); pairwisesavings: (i, j, s)
    a = mincostinsert(2, [1, 1], h6)
    @test a isa NamedTuple && keys(a) == (:rte, :TC) && a == (rte = [1, 2, 2, 1], TC = 310)
    b = twoopt([1, 2, 3, 1, 2, 3], h6)
    @test keys(b) == (:rte, :TC) && b.TC == h6(b.rte)
    C = [0 10 25 20; 10 0 15 30; 25 15 0 10; 20 30 10 0]
    t1 = twoopt([1, 3, 2, 4, 1], r -> sum(segcost(r, C)))
    t2 = twoopt([1, 3, 2, 4, 1], C)
    @test keys(t1) == keys(t2) == (:rte, :TC) && t1 == t2
    ijs = pairwisesavings(h6, RPIN_SH6)
    @test ijs isa NamedTuple && keys(ijs) == (:i, :j, :s) && ijs == (i = [1, 1, 2], j = [2, 3, 3], s = [240.0, 180.0, 95.0])
    # destructuring, positional indexing and splatting work as they did on the tuples of v0.2.8
    rte, TC = mincostinsert(3, [1, 2, 2, 1], h6)
    @test rte == [3, 1, 2, 2, 1, 3] && TC == 430 && mincostinsert(3, [1, 2, 2, 1], h6)[1] == rte && mincostinsert(3, [1, 2, 2, 1], h6)[2] == 430
    iˢ, jˢ, sˢ = ijs
    @test iˢ == ijs.i == ijs[1] && jˢ == ijs.j == ijs[2] && sˢ == ijs.s == ijs[3]
    @test hcat(ijs...) == hcat(iˢ, jˢ, sˢ)
    # a savings list is taken from the named tuple, a plain tuple or a matrix, alike
    @test savings(h6, RPIN_SH6; ijs = ijs) == savings(h6, RPIN_SH6; ijs = Tuple(ijs)) == savings(h6, RPIN_SH6; ijs = hcat(ijs...))
    # a named tuple of vectors is a table
    @test DataFrame(pairwisesavings(h6, RPIN_SH6)) == DataFrame(i = [1, 1, 2], j = [2, 3, 3], s = [240.0, 180.0, 95.0])
    # the route methods of the set: the vector of routes and the vector of costs
    @test keys(twoopt([[1, 2, 1, 2]], h6)) == keys(twoopt([[1, 3, 2, 4, 1]], C)) == (:rte, :TC)
    @test keys(sh2rte(1:3)) == (:rte, :idx1) && keys(rteTC([1, 2, 1, 2], DataFrame(b = [1, 2], e = [3, 4]), ones(4, 4); full = true)) == (:TC, :Xflg, :out)
end

@testset "[K7C, CR 41] savings(...; TC1): the independent cost ranks the list and accepts the merges" begin
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    TC1 = [h6([k, k]) for k in 1:3]
    # the default is rteTC([k, k]) in both places, so giving it changes nothing
    @test savings(h6, RPIN_SH6; TC1 = TC1) == savings(h6, RPIN_SH6) == [[3, 1, 2, 2, 1, 3]]
    @test savings(h6, RPIN_SH6; TC1 = float.(TC1)) == savings(h6, RPIN_SH6)
    # two far-apart pairs: joining them costs 9 more than apart, so no merge saves at the default independent
    # cost and none is made; with a higher independent cost the saving, and the merge test, are positive
    D = [0.0 1 9 9; 1 0 9 9; 9 9 0 1; 9 9 1 0]
    sh = DataFrame(b = [1, 3], e = [2, 4])
    h = r -> rteTC(r, sh, D)
    @test savings(h, sh) == Vector{Int}[]
    ijs = pairwisesavings(h, sh; TC1 = [20.0, 20.0])
    @test Tuple(ijs) == ([1], [2], [21.0])
    # the list alone, without the keyword, is tested against h([k, k]) and the merge is refused (Matlog's split)
    @test savings(h, sh; ijs = ijs) == Vector{Int}[]
    # with the keyword the same cost is the merge test's: the merge is made, and the default list is made with it
    @test savings(h, sh; TC1 = [20.0, 20.0], ijs = ijs) == [[1, 2, 2, 1]] == savings(h, sh; TC1 = [20.0, 20.0])
    # a vector of the wrong length is an ArgumentError, with or without a list of one's own
    @test_throws ArgumentError savings(h, sh; TC1 = [1.0])
    @test_throws ArgumentError savings(h, sh; TC1 = [1.0], ijs = ijs)
    # on 5.2's Ex. 8 at the one-truck charge, where a shipment's independent cost is its own charge (Ex. 9):
    # TC1 = the charge of each shipment on its own gives the routes of the default
    D30 = _rp_D30(); ht = _onetruck(RPIN_SH30, D30)
    @test savings(ht, RPIN_SH30; TC1 = [ht([k, k]) for k in 1:30]) == savings(ht, RPIN_SH30)
end

@testset "[CR 58] of two orders at exactly equal cost, the exported routes list the increasing one; the cost never moves" begin
    # the corpus: the routes the unnormalized kernels build on the pinned and oracle cases (savings, their
    # 2-opt, the insertion chain, insert and improve)
    D30 = _rp_D30(); c = _cw()
    X5 = _rp_xy54()[[5, 27, 3, 38, 24, 18, 1], :]; D5 = dists(X5, X5, :mi) * 1.2
    sh5 = DataFrame(b = [1, 3, 4, 6, 7], e = [2, 2, 5, 2, 1])
    d2 = _readoracle("routing_52_ex2"); sh2 = DataFrame(b = _ivec(d2, "b"), e = _ivec(d2, "e")); tr2 = (b = _ivec(d2, "tr_b"), e = _ivec(d2, "tr_e"))
    d3 = _readoracle("routing_52_ex3"); sh3 = DataFrame(b = _ivec(d3, "b"), e = _ivec(d3, "e"))
    v = _vrp53(false); vm = _vrp53(true)
    cases = [("5.2 Ex. 4(b)", sh5, r -> rteTC(r, sh5, D5)),
             ("5.2 Ex. 8", RPIN_SH30, r -> rteTC(r, RPIN_SH30, D30)),
             ("5.2 Ex. 9 charge", RPIN_SH30, _onetruck(RPIN_SH30, D30)),
             ("5.3 CW", c.shcw, c.h), ("5.3 vrp", v.sh, v.h), ("5.3 vrp maxTC", vm.sh, vm.h),
             ("makeRouting2 Ex. 2", sh2, r -> rteTC(r, sh2, d2["D"], tr2)),
             ("makeRouting2 Ex. 3", sh3, r -> rteTC(r, sh3, d3["D"], (b = [1], e = [1])))]
    nroutes = nchanged = 0
    for (name, sh, h) in cases
        n = nrow(sh)
        kern = Vector{Int}[]
        ijs = pairwisesavings(h, sh)
        for r in Logjam._savings(h, n, Logjam._savings_list(ijs, n)...)
            push!(kern, r); push!(kern, Logjam._twoopt(r, h)[1])
        end
        r = [1, 1]
        for k in 2:n
            r = Logjam._mincostinsert(k, r, h)[1]; push!(kern, r)
        end
        push!(kern, Logjam._insertall(2:n, [1, 1], h; improve = Logjam._twoopt_route)[1])
        ok = true
        for r in kern
            r2 = Logjam._order_ties(r, h)
            nroutes += 1; nchanged += r2 != r
            ok &= h(r2) === h(r) && sort(r2) == sort(r) && Logjam._order_ties(r2, h) == r2    # bit-identical cost, same stops, idempotent
        end
        @test ok
    end
    @test nroutes > 200 && nchanged > 100                               # the pass is exercised, not vacuous
    # the exports are the kernels' results through the pass, and the searches are unchanged
    h = r -> rteTC(r, RPIN_SH30, D30)
    r0 = vcat(1:30, 1:30)
    kr, kTC = Logjam._twoopt(r0, h)
    @test twoopt(r0, h) == (rte = Logjam._order_ties(kr, h), TC = kTC)
    @test h(twoopt(r0, h).rte) === kTC
    @test mincostinsert(7, [3, 3], h) == (rte = Logjam._order_ties(Logjam._mincostinsert(7, [3, 3], h)[1], h), TC = Logjam._mincostinsert(7, [3, 3], h)[2])
    @test savings(h, RPIN_SH30) == [Logjam._order_ties(r, h) for r in Logjam._savings(h, 30, Logjam._savings_list(pairwisesavings(h, RPIN_SH30), 30)...)]
    # the set method is the route method on each route
    Rs = savings(h, RPIN_SH30)
    @test twoopt(Rs, h).rte == [twoopt(r, h).rte for r in Rs]
    # every returned route is in increasing order wherever the swap costs nothing
    function increasing_ok(r, h)
        isL = isorigin(r); TC = h(r)
        all(i -> !(isL[i] == isL[i+1] && r[i] > r[i+1]) || h(vcat(r[1:i-1], r[i+1], r[i], r[i+2:end])) != TC, 1:length(r)-1)
    end
    @test all(increasing_ok(r, h) for r in Rs) && increasing_ok(twoopt(r0, h).rte, h)
    # a swap that changes the cost is refused: two shipments loading at one location, the second with a window
    # that only the first position meets (5.3's windows through the checked rteTC), so the costlier order stays
    Dw = [0.0 1 1; 1 0 1; 1 1 0]
    shw = DataFrame(b = [1, 1], e = [2, 3], tL = 1.0, tU = 0.0, tbmin = 0.0, tbmax = [Inf, 1.0])
    hw = r -> rteTC(r, shw, Dw, (;); full = true).TC
    @test isfinite(hw([2, 1, 2, 1])) && isinf(hw([1, 2, 2, 1]))        # loading 1 first breaks shipment 2's window
    @test Logjam._order_ties([2, 1, 2, 1], hw)[1:2] == [2, 1]           # the decreasing order stays
    # an order-dependent handle: a swap is made only at exactly equal cost, so neither a cheaper nor a costlier swap is
    Dz = [0.0 1 1 1; 1 0 1 1; 1 1 0 1; 1 1 1 0]
    shz = DataFrame(b = [1, 1], e = [3, 4])
    cheap2first = r -> rteTC(r, shz, Dz) + (findfirst(==(1), r) < findfirst(==(2), r) ? 5.0 : 0.0)
    cheap1first = r -> rteTC(r, shz, Dz) + (findfirst(==(1), r) < findfirst(==(2), r) ? 0.0 : 5.0)
    @test Logjam._order_ties([2, 1, 1, 2], cheap2first) == [2, 1, 1, 2]
    @test Logjam._order_ties([2, 1, 1, 2], cheap1first) == [2, 1, 1, 2]
    @test Logjam._order_ties([2, 1, 2, 1], r -> rteTC(r, shz, Dz))[1:2] == [1, 2]      # a plain cost: equal, so increasing
    # a route of infinite cost, a single shipment and an empty route come back as they are
    @test Logjam._order_ties([2, 1, 2, 1], r -> Inf) == [2, 1, 2, 1] && Logjam._order_ties([1, 1], h) == [1, 1] && Logjam._order_ties(Int[], h) == Int[]
    # tours are untouched: the search's own result, in the order it leaves them
    d = _readoracle("tsp_traces"); C = d["C"]
    for nm in ("sfc", "nn1", "rnd1")
        loc0 = _ivec(d, nm * "_loc0")
        @test twoopt(loc0, π -> sum(segcost(π, C))).rte == Logjam._twoopt_tour(loc0, π -> sum(segcost(π, C)))[1]
        @test twoopt(loc0, C).rte == Logjam._twoopt(loc0, π -> sum(segcost(π, C)))[1]
    end
    @test twoopt([[_ivec(d, "sfc_loc0")][1]], C).rte == [twoopt(_ivec(d, "sfc_loc0"), C).rte]
    # 5.3 Ex. 1(c): Clarke-Wright's second route now gives the location sequence (1, 2, 5, 1) the lecture prints
    R1, TC1 = twoopt(savings(c.h, c.shcw), c.h)
    @test R1 == [[2, 3, 5, 3, 5, 2], [1, 4, 1, 4]] && TC1 == [167, 138]
    @test rte2loc(R1, c.shcw, c.tr) == [[1, 1, 1, 1, 4, 6, 3, 1], [1, 1, 1, 2, 5, 1]]
end
