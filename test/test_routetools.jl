# test_routetools.jl -- the tests of src/routetools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_routing_pins.jl, its lines 1-24 ====
# test_routing_pins.jl -- value equality of the course's routing calls against the committed fixture
# (PCV K7a, plan principle 9). A call the course makes today keeps returning what it returned at v0.2.8
# (the fixture was written from the code at 97aeab2, unchanged from v0.2.8 in routetools.jl).
# Only a case listed in RPIN_MOVED may differ, and each fixture update is named in its commit.
# Regenerate with tools/v0_3_0/make_routing_pins.jl. No case touches the network.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "routing_pin_helpers.jl"))

@testset "routing calls are pinned value for value" begin
    fixture = rtpin_read()
    cases = rtpin_cases()
    @test length(fixture) == length(cases)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(fixture, name)
            haskey(fixture, name) || continue
            @test rtpin_run(thunk) == fixture[name]
        end
    end
end

# ==== moved from test/test_k12_pins.jl, its lines 1-24, 44-172 ====
# test_k12_pins.jl -- what the course gets today from the calls K12's new functions replace or sit beside, pinned from
# the code at 4e7ce94 (PCV K12, plan principle 9). Every value below was measured on the unchanged code, before K12
# added `randtour`, `disk`, `sfcpos`, `tspspfillcur`, `lonlat`, integer ZIPs, `usstate`, the `usstates` declaration and
# the county box. A call the course makes today keeps returning what it returned then; only a case named in K12PIN_MOVED
# may differ, and each one is named in the commit that moves it. (Logjam's own `randtour`, `disk`, `sfcpos` and
# `tspspfillcur` were removed before the release, rulings RTE27, IN1 and IN3; the lecture's definitions are what is pinned.)
#
# What is pinned: the lecture definitions themselves (Lecture 5.1's `randtour`, `disk`, `sfcpos`, `tspspfillcur`, Lecture
# 4.2's Code block 3), run as text in a scratch module that has done `using Logjam` first, their outputs on the
# course's own inputs and seeds, and the global random stream after each seeded draw (the next `rand()`); the
# `hcat(df.LON, df.LAT)` the course writes at three sites; `loc2lonlat` on string ZIPs; and `Logjam.usstates()`.
# Draws that `randperm` makes differ between Julia 1.12 and 1.13 (the generator's stream is the same, `randperm`'s use of
# it is not), so those values are pinned per version and compared with the lecture's definition only on another.
#
# No case touches the network or a file outside the package, and none renders a picture.

using Test
using Logjam
using DataFrames
using Random

isdefined(@__MODULE__, :ORACLE_DIR) || include("oracle_helpers.jl")
isdefined(@__MODULE__, :LECTURE51_SFC) || include("lecture51_code.jl")
isdefined(@__MODULE__, :LECTURE42_COUNTY_BOX) || include("lecture42_code.jl")
isdefined(@__MODULE__, :K12PIN_MOVED) || include(joinpath(@__DIR__, "k12_helpers.jl"))   # WP8: defined once

# ---- Lecture 5.1's randtour and disk: draws and the stream after them ---------------------------------------------
# (Logjam's own `randtour` was removed before the release, ruling RTE27; the lecture's definition is what is pinned.)
# version => (name => value): seed 2024 then `randtour(6)` (Code block 17) and the next draw; `randtour(100)` (Code
# block 28); the stream of Code blocks 17 and 18, 101 draws of `randtour(6)`; of Code blocks 28 and 30, 101 draws of
# `randtour(100)`.
const K12_RANDTOUR_PINS = Dict(
    (1, 12) => (t6 = [4, 5, 6, 3, 2, 1, 4], t6_next = 0.9387028493780337,
                t100_first5 = [79, 21, 44, 85, 33], t100_fnv = 0x4d3de7eb0bbb3eae, t100_next = 0.22508726580673843,
                s6_fnv = 0x1e87d5d6071975a0, s6_next = 0.804549742908579,
                s100_fnv = 0x7270fa0fe92d2e98, s100_next = 0.0517857300421628),
    (1, 13) => (t6 = [2, 1, 6, 3, 5, 4, 2], t6_next = 0.6279718282469421,
                t100_first5 = [16, 61, 85, 49, 87], t100_fnv = 0x431fd3a394e97391, t100_next = 0.5979243663887365,
                s6_fnv = 0xb1d234513cb29e27, s6_next = 0.03771720264773937,
                s100_fnv = 0x4378958d547cd456, s100_next = 0.06774925945267807),
)

@testset "[K12 pin] Lecture 5.1's randtour: the tours of its seeds and the stream after them" begin
    @test !_k12pin_moved("randtour")
    m = lecture51_module(LECTURE51_RANDTOUR)
    @test _k12_call(m, :randtour, 6) isa Vector{Int}
    p = get(K12_RANDTOUR_PINS, (VERSION.major, VERSION.minor), nothing)

    Random.seed!(2024)
    t6 = _k12_call(m, :randtour, 6)
    n6 = rand()
    @test length(t6) == 7 && t6[1] == t6[end] && sort(t6[1:6]) == 1:6        # a permutation with its first node repeated
    p === nothing || @test (t6, n6) == (p.t6, p.t6_next)

    Random.seed!(2024)
    t100 = _k12_call(m, :randtour, 100)
    n100 = rand()
    @test length(t100) == 101 && t100[1] == t100[end] && sort(t100[1:100]) == 1:100
    p === nothing || @test (t100[1:5], _k12_fnv(t100), n100) == (p.t100_first5, p.t100_fnv, p.t100_next)

    Random.seed!(2024)
    s6 = reduce(vcat, [_k12_call(m, :randtour, 6) for _ in 1:101])
    ns6 = rand()
    p === nothing || @test (_k12_fnv(s6), ns6) == (p.s6_fnv, p.s6_next)

    Random.seed!(2024)
    s100 = reduce(vcat, [_k12_call(m, :randtour, 100) for _ in 1:101])
    ns100 = rand()
    p === nothing || @test (_k12_fnv(s100), ns100) == (p.s100_fnv, p.s100_next)
end

@testset "[K12 pin] Lecture 5.1's disk: the points of its seeds and the stream after them" begin
    @test !_k12pin_moved("disk")
    m = lecture51_module(LECTURE51_DISK)

    Random.seed!(150)                                        # Code block 24's draw of two points
    d2 = _k12_call(m, :disk, 2)
    @test d2 == [0.5381022146876899 0.03250886468438763; 0.30127979264620874 -0.767481238809196]
    @test rand() == 0.32134164134444465

    Random.seed!(150)                                        # Code block 24's whole table of draws
    Pall = Matrix{Float64}[]
    for mm in (2, 5, 10, 20, 50, 100, 200)
        append!(Pall, [_k12_call(m, :disk, mm) for _ in 1:(1000 ÷ mm)])
    end
    @test length(Pall) == 885 && sum(size.(Pall, 1)) == 7000
    @test all(P -> all(sum(abs2, P; dims = 2) .< 1), Pall)
    @test _k12_fnv(reduce(vcat, Pall)) == 0x7d64c7767e6b2cec
    @test rand() == 0.15527645417329117

    Random.seed!(242)                                        # Code block 23: 300 points
    D300 = _k12_call(m, :disk, 300)
    @test _k12_fnv(D300) == 0x046d6036b15fdb98
    @test rand() == 0.705706198926476
    m2 = lecture51_module(LECTURE51_INLINE_DISK)             # Code block 23's own loop draws the same 300 points
    @test getfield(m2, :P) == D300
    @test rand() == 0.705706198926476                        # and leaves the stream in the same place
end

# ---- Lecture 5.1's sfcpos and tspspfillcur ------------------------------------------------------------------------
# the SFC Handout's 11 x 11 table of curve positions (Lecture 5.1's Code block 9, rows y = 1 down to 0, columns x = 0 to 1),
# to three decimals, halves away from zero as MATLAB rounds
const K12_SFC_HANDOUT = [0.250 0.254 0.265 0.298 0.309 0.438 0.441 0.452 0.485 0.496 0.500
                         0.246 0.257 0.271 0.292 0.305 0.434 0.445 0.458 0.479 0.493 0.504
                         0.235 0.229 0.279 0.283 0.333 0.423 0.417 0.467 0.471 0.521 0.515
                         0.202 0.208 0.158 0.154 0.354 0.390 0.396 0.596 0.592 0.542 0.548
                         0.191 0.180 0.167 0.146 0.132 0.379 0.618 0.604 0.583 0.570 0.559
                         0.188 0.184 0.173 0.140 0.129 0.375 0.621 0.610 0.577 0.566 0.563
                         0.059 0.070 0.083 0.104 0.118 0.871 0.632 0.646 0.667 0.680 0.691
                         0.048 0.042 0.092 0.096 0.896 0.860 0.854 0.654 0.658 0.708 0.702
                         0.015 0.021 0.971 0.967 0.917 0.827 0.833 0.783 0.779 0.729 0.735
                         0.004 0.993 0.979 0.958 0.945 0.816 0.805 0.792 0.771 0.757 0.746
                         0.000 0.996 0.985 0.952 0.941 0.813 0.809 0.798 0.765 0.754 0.750]

@testset "[K12 pin] Lecture 5.1's sfcpos and tspspfillcur: the handout, slide 238, eil51 and the NC cities" begin
    @test !_k12pin_moved("sfc")
    m = lecture51_module(LECTURE51_SFC)
    sp(x, y, k = 8) = _k12_call(m, :sfcpos, x, y, k)
    tsp(XY, k = 8) = _k12_call(m, :tspspfillcur, XY, k)
    eil51 = _readoracle("tsp_traces")["XY"]          # vrpnc1's 51 points, as makeRouting1.m reads them

    @testset "the handout's 121 cells (Code block 9), and the four points of slide 238 (Code block 8)" begin
        g = (0:10) ./ 10
        Θ = [sp(x, y) for y in reverse(g), x in g]
        @test round.(Θ, RoundNearestTiesAway, digits = 3) == K12_SFC_HANDOUT
        @test _k12_fnv(Θ) == 0xbc23e4bafd3c41ef
        XY4 = [0.8 0.8; 0.1 0.2; 0.3 0.7; 0.7 0.2]
        θ4 = [sp(XY4[i, 1], XY4[i, 2]) for i in 1:4]
        @test θ4 == [0.4705810546875, 0.0208282470703125, 0.1544189453125, 0.7830810546875]
        @test round.(θ4, digits = 3) == [0.471, 0.021, 0.154, 0.783]
        @test tsp(XY4) == [1, 4, 2, 3, 1]
    end

    @testset "eil51 (Matlog's vrpnc1): the tour MATLAB printed in the S17 diary" begin
        printed = [1, 7, 15, 26, 25, 24, 44, 8, 27, 9, 49, 28, 33, 2, 23, 32, 29, 4, 37, 36, 21, 30, 22, 3, 17,
                   12, 39, 10, 50, 51, 35, 31, 40, 34, 46, 11, 6, 13, 38, 18, 16, 45, 43, 20, 41, 42, 14, 19, 5,
                   48, 47, 1]
        @test tsp(eil51) == printed
    end

    @testset "the NC cities (Code block 4) and the 100 NC counties (Code block 33)" begin
        df = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
        @test tsp(hcat(df.LON, df.LAT)) == [1, 9, 5, 2, 3, 7, 6, 10, 4, 8, 1]
        dc = filter(r -> (r.STFIP == st2fips(:NC)), uscounty())
        XY = hcat(dc.LON, dc.LAT)
        t = tsp(XY)
        @test length(t) == 101 && t[1] == t[end] == 1 && sort(t[1:100]) == 1:100
        @test t[1:8] == [1, 13, 47, 21, 29, 34, 66, 24]
        @test _k12_fnv(t) == 0x1625e134f4248fe0
        D = dists(XY, XY, :mi)
        @test isapprox(sum(D[t[k], t[k + 1]] for k in 1:100), 2826.212979580854; rtol = 1e-12)
        @test _k12_fnv(tsp(XY, 4)) == 0xd214adc3154504c0
    end
end

# ==== moved from test/test_k12_functions.jl, its lines 1-14, 23-47 ====
# test_k12_functions.jl -- the small functions K12 adds, each tested against the course definition it takes the place of
# (PCV K12, plan principles 8 and 9). The pins of what the course gets today are test_k12_pins.jl, whose case
# values and lecture texts this file reuses: a function that equals the lecture's definition on the lecture's inputs
# and seeds, and leaves the global stream where the lecture's leaves it, gives back every pinned value.

using Test
using Logjam
using DataFrames
using Random

isdefined(@__MODULE__, :K12PIN_MOVED) || include("k12_helpers.jl")
isdefined(@__MODULE__, :ORACLE_DIR) || include("oracle_helpers.jl")
isdefined(@__MODULE__, :LECTURE51_SFC) || include("lecture51_code.jl")
isdefined(@__MODULE__, :LECTURE42_COUNTY_BOX) || include("lecture42_code.jl")

# ---- CR 47: randtour, disk, sfcpos and tspspfillcur were removed before the release -------------------------------
# (RTE27; IN1 and IN3, his inclusion rule of 2026-11-21: each is defined and used in Lecture 5.1 only). The lecture keeps
# its own definitions, which test_k12_pins.jl pins.
@testset "[K12] CR 47: randtour, disk, sfcpos and tspspfillcur are not in Logjam (RTE27, IN1, IN3)" begin
    for s in (:randtour, :disk, :sfcpos, :tspspfillcur)
        @test !isdefined(Logjam, s)
    end
end

# ---- names the course defines for itself (principle 9) --------------------------------------------------------
# a script that does `using Logjam` and then defines its own function, before using it, still runs and calls its own
# definition, on this Julia version; the definitions are Lecture 5.1's text, and Logjam has none of the four names
@testset "[K12] fresh process: Lecture 5.1's own randtour, disk, sfcpos and tspspfillcur run after using Logjam" begin
    code = "using Logjam\n" * LECTURE51_RANDTOUR * LECTURE51_DISK * LECTURE51_SFC * """
    Random.seed!(2024)
    t = randtour(6)
    println("own=", all(f -> parentmodule(f) === Main, (randtour, disk, sfcpos, tspspfillcur)))
    println("lib=", !any(s -> isdefined(Logjam, s), (:randtour, :disk, :sfcpos, :tspspfillcur)))
    println("run=", length(t) == 7, " ", size(disk(3)) == (3, 2), " ", tspspfillcur([0.8 0.8; 0.1 0.2; 0.3 0.7; 0.7 0.2]) == [1, 4, 2, 3, 1])
    """
    ok, out = _k12_child(code)
    @test ok
    @test occursin("own=true", out) && occursin("lib=true", out) && occursin("run=true true true", out)
end

# ==== moved from test/test_routetools.jl, its lines 1-855 ====
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

# ==== moved from test/test_routing_k7a.jl, its lines 1-378 ====
# test_routing_k7a.jl -- tests added by PCV K7a (routing procedures): principle 9 checks against the
# course's own stand-ins (Lecture 5.2's inline definitions, run in a scratch module after `using Logjam`,
# as K6 did for 3.4's), and the tests of each K7a item that the K2 testsets do not hold. Each testset is
# tagged with the ID of the item it belongs to.

using Test
using Logjam
using DataFrames
using Random

@isdefined(RPIN_SH30) || include(joinpath(@__DIR__, "routing_pin_cases.jl"))
@isdefined(LECTURE52_CODE) || include(joinpath(@__DIR__, "lecture52_code.jl"))

# a vector is a route when a shipment is on board over every segment (Matlog's rtesegsum with a 1 per shipment)
_k7_onboard(r) = cumsum(ifelse.(isorigin(r), 1, -1))[1:end-1]
_k7_isroute(r) = all(>(0), _k7_onboard(r))

@testset "K7a" begin

@testset "[P9, CR 38] Logjam.mincostinsert equals Lecture 5.2's mincostinsert_rte on the course's inputs" begin
    m = lecture52_module(:L52_mci)
    mci_rte(args...) = lecture52_call(m, :mincostinsert_rte, args...)
    # every ordered pair of the 2008 qual's four shipments (one-truck charge, as 5.2 Ex. 9)
    for (sh, D) in ((RPIN_SHG, RPIN_DG),)
        h = _onetruck(sh, D)
        n = nrow(sh)
        for i in 1:n, j in 1:n
            i == j && continue
            @test Tuple(mincostinsert(i, [j, j], h)) == mci_rte(i, [j, j], h)
        end
        # the chain 1, 2, ..., n built by insertion, each step
        a = b = [1, 1]
        for k in 2:n
            a = mincostinsert(k, a, h)[1]
            b = mci_rte(k, b, h)[1]
            @test a == b
        end
    end
    # 5.2 Ex. 6(a): the three-shipment route
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    @test Tuple(mincostinsert(2, [1, 1], h6)) == ([1, 2, 2, 1], 310) == mci_rte(2, [1, 1], h6)
    @test Tuple(mincostinsert(3, [1, 2, 2, 1], h6)) == ([3, 1, 2, 2, 1, 3], 430) == mci_rte(3, [1, 2, 2, 1], h6)
    # 5.2 Ex. 8: the first start of randomized insertion, 1,630.35 (his loop), every step
    D = _rp_D30()
    h = r -> rteTC(r, RPIN_SH30, D)
    a = b = [RPIN_L30[1], RPIN_L30[1]]
    for k in RPIN_L30[2:end]
        prev = a
        a = Logjam._mincostinsert(k, prev, h)[1]                  # the search; the export lists its ties in increasing order (CR 58)
        b = mci_rte(k, b, h)[1]
        @test a == b && mincostinsert(k, prev, h).rte == Logjam._order_ties(a, h)
    end
    # Matlog's makeRouting2.m Example 1 (six cities): the chain of the lecture's first example
    d = _readoracle("routing_52_ex1")
    sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"))
    h1 = r -> rteTC(r, sh, d["D"])
    @test Tuple(mincostinsert(2, [1, 1], h1)) == mci_rte(2, [1, 1], h1)
    @test Tuple(mincostinsert(3, _ivec(d, "r12"), h1)) == mci_rte(3, _ivec(d, "r12"), h1)
    # a route cost that is Inf off a feasible route (5.3): the same route and the same Inf
    hinf = r -> rteTC(r, RPIN_SHG, RPIN_DG) > 300 ? Inf : rteTC(r, RPIN_SHG, RPIN_DG)
    @test Tuple(mincostinsert(2, [1, 1], hinf)) == mci_rte(2, [1, 1], hinf)
    @test isinf(mincostinsert(4, [1, 2, 2, 1, 3, 3], hinf)[2]) == isinf(mci_rte(4, [1, 2, 2, 1, 3, 3], hinf)[2])
end

@testset "[CR 38] mincostinsert never returns a vector that is not a route" begin
    # every position it considers is a route, so the best of them is one; the two left out are the front
    # and the end ([k, k, r...] and [r..., k, k]) even when one of them is the cheapest of the m(m+3)/2
    D = [0.0 1 1 1; 1 0 1 1; 1 1 0 1; 1 1 1 0]
    sh = DataFrame(b = [1, 1], e = [2, 2])      # both shipments load at 1, unload at 2
    h = r -> rteTC(r, sh, D, (b = Int[], e = Int[]))
    r, TC = mincostinsert(2, [1, 1], h)
    @test _k7_isroute(r) && TC ≈ h(r)
    # the counts of Eq. insert-count: m(m + 3)/2 - 1 routes are evaluated
    for m in (2, 4, 6, 10)
        rte = repeat(1:m ÷ 2, inner = 2)
        n = Ref(0)
        Logjam._mincostinsert(m ÷ 2 + 1, rte, r -> (n[] += 1; float(length(r))))      # the loops; the export adds CR 58's pass
        @test n[] == m * (m + 3) ÷ 2 - 1
    end
    # a cost that prefers the end: the end is still not taken
    prefer_end = r -> -float(findlast(==(7), r))   # cheapest when 7 is last; positions are routes only
    r, TC = mincostinsert(7, [1, 1], prefer_end)
    @test _k7_isroute(r)
end

@testset "[CR 37, CR 54, D9] twoopt tells a route vector from a tour by the vector (every element twice)" begin
    # the rule: a route vector has every element exactly twice; a tour returns to its first element and
    # visits the others once, so it is never a route vector (except the degenerate [a, a])
    @test Logjam._isroutevec([1, 1]) && Logjam._isroutevec([1, 2, 1, 2]) && Logjam._isroutevec([3, 1, 2, 2, 1, 3])
    @test !Logjam._isroutevec([1, 2, 3, 4, 1]) && !Logjam._isroutevec([1, 2, 1]) && !Logjam._isroutevec(Int[])
    @test !Logjam._isroutevec([1, 5, 2, 6, 4, 3, 1])
    # the course's twoopt of a location sequence (5.1) is the closed tour's: ends fixed, unchanged
    C = [0 10 25 20; 10 0 15 30; 25 15 0 10; 20 30 10 0]
    rTCh = r -> sum(C[r[i], r[i+1]] for i in 1:length(r)-1)
    t, TC = twoopt([1, 3, 2, 4, 1], rTCh)
    @test t[1] == t[end] == 1 && TC == rTCh(t) && sort(t) == [1, 1, 2, 3, 4]
    # a route is improved from either end: this vector's best reversal moves its first stop
    sh = DataFrame(b = [1, 2], e = [3, 4])
    D = [0.0 5 1 9; 5 0 9 1; 1 9 0 5; 9 1 5 0]
    h = r -> rteTC(r, sh, D)
    r, TCr = twoopt([2, 1, 1, 2], h)
    @test _k7_isroute(r) && TCr == h(r) <= h([2, 1, 1, 2])
    # docstring example: Lecture 5.2 Ex. 6(a)'s shipments
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    r6, TC6 = twoopt([1, 2, 3, 1, 2, 3], h6)
    @test _k7_isroute(r6) && TC6 == h6(r6) && TC6 <= h6([1, 2, 3, 1, 2, 3])
end

@testset "[CR 37, CR 54] route twoopt: a route in, a route out, no improving route-preserving reversal left" begin
    rng = Random.Xoshiro(20261120)
    ok_route = ok_cost = ok_perm = ok_nomut = ok_opt = true
    for _ in 1:30
        k = rand(rng, 2:6)
        X = rand(rng, 2k, 2) .* 30
        C = dists(X, X, 2)
        perm = randperm(rng, 2k)
        sh = DataFrame(b = perm[1:k], e = perm[k+1:2k])
        h = r -> rteTC(r, sh, C)
        # a random route: shuffle until the vector is one (a route needs the shipments on board throughout)
        r0 = shuffle(rng, vcat(1:k, 1:k))
        while !_k7_isroute(r0)
            r0 = shuffle(rng, vcat(1:k, 1:k))
        end
        r0copy = copy(r0)
        r, TC = twoopt(r0, h)
        ok_route &= _k7_isroute(r)
        ok_cost &= isapprox(TC, h(r); rtol = 1e-9)
        ok_perm &= sort(r) == sort(r0)
        ok_nomut &= r0 == r0copy
        m = length(r)
        ok_opt &= !any(_k7_isroute(vcat(r[1:i-1], reverse(r[i:j]), r[j+1:end])) &&
                       h(vcat(r[1:i-1], reverse(r[i:j]), r[j+1:end])) < TC - 1e-9
                       for i in 1:m-1 for j in i+1:m)
    end
    @test ok_route && ok_cost && ok_perm && ok_nomut
    @test ok_opt
end

@testset "[P9, CR 37, CR 54] Logjam.twoopt on a route vector equals Lecture 5.2's twoopt_rte on the course's inputs" begin
    m = lecture52_module(:L52_twoopt)
    same(r, h) = (x = lecture52_call(m, :twoopt_rte, r, h); Tuple(twoopt(r, h)) == (Logjam._order_ties(x[1], h), x[2]))    # CR 58: ties in increasing order
    # 5.2 Ex. 8: routes of insertion and of savings, and a route of every start
    D = _rp_D30(); h = r -> rteTC(r, RPIN_SH30, D)
    @test same(_mci_chain(RPIN_L30, h), h)
    for r in savings(h, RPIN_SH30)
        @test same(r, h)
    end
    # Matlog's makeRouting2.m Examples 2 and 3 as shipments
    d = _readoracle("routing_52_ex2"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"))
    tr = (b = _ivec(d, "tr_b"), e = _ivec(d, "tr_e")); h2 = r -> rteTC(r, sh, d["D"], tr)
    for st in ("mci_r1", "r0_in", "rr_in")
        @test same(_ivec(d, st), h2)
    end
    d = _readoracle("routing_52_ex3"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"))
    h3 = r -> rteTC(r, sh, d["D"], (b = [1], e = [1]))
    @test same(_cells(d, "sav_r")[1], h3)
    # 5.3: the Clarke-Wright example and the 30 shipments with the truck's limits (an Inf route cost)
    c = _cw()
    for r in savings(c.h, c.shcw)
        @test same(r, c.h)
    end
    for withmax in (false, true)
        v = _vrp53(withmax)
        for r in savings(v.h, v.sh)
            @test same(r, v.h)
        end
    end
    # HW 5 Q1: the key's route-time handle
    q1 = _hw5q1()
    for r in savings(q1.rTTa, q1.sha)
        @test same(r, q1.rTTa)
    end
    # the 2008 qual's four shipments, one truck
    for (sh, D) in ((RPIN_SHG, RPIN_DG),)
        hh = _onetruck(sh, D)
        @test same(_mci_chain(collect(1:nrow(sh)), hh), hh)
        for r in savings(hh, sh)
            @test same(r, hh)
        end
    end
end

@testset "[CR 39] savings never merges unless the merge saves: seeded instances, with a depot and a capacity" begin
    rng = Random.Xoshiro(20261121)
    ok_total = ok_cover = ok_routes = ok_cap = true
    nmerged = 0
    for t in 1:80
        k = rand(rng, 4:10)
        if isodd(t)                              # pickup-delivery pairs among 2k places
            X = rand(rng, 2k, 2) .* 25
            C = dists(X, X, 2)
            perm = randperm(rng, 2k)
            sh = DataFrame(b = perm[1:k], e = perm[k+1:2k])
            tr = (b = Int[], e = Int[])
            q = ones(k)
            h = r -> rteTC(r, sh, C, tr)
        else                                     # a depot, k customers, a capacity of three loads
            X = rand(rng, k + 1, 2) .* 25
            C = dists(X, X, 2)
            sh = DataFrame(b = fill(1, k), e = 2:k+1)
            tr = (b = [1], e = [1])
            q = rand(rng, 1:3, k)
            h = r -> (c = rteTC(r, sh, C, tr); sum(q[unique(r)]) <= 5 ? c : Inf)
        end
        R = savings(h, sh)
        alone = setdiff(1:k, reduce(vcat, R; init = Int[]))            # the shipments on no formed route
        ok_cover &= sort(vcat(reduce(vcat, R; init = Int[]), [s for s in alone for _ in 1:2])) == sort(vcat(1:k, 1:k))
        ok_routes &= all(_k7_isroute, R) || !isodd(t)     # depot routes load, then unload
        ok_total &= sum(h.(R); init = 0.0) + sum(h([s, s]) for s in alone; init = 0.0) <= sum(h([i, i]) for i in 1:k) + 1e-9
        ok_cap &= all(isfinite, h.(R))
        nmerged += length(R)
    end
    @test ok_cover && ok_total && ok_cap && ok_routes
    @test nmerged > 40                           # the instances do merge, so the test is not vacuous
    # the property is per merge: no formed route costs more than its shipments shipped independently
    D = [0.0 1 9 9; 1 0 9 9; 9 9 0 1; 9 9 1 0]
    sh = DataFrame(b = [1, 3], e = [2, 4])       # two far-apart pairs: joining them costs 9 more than apart
    h = r -> rteTC(r, sh, D)
    @test savings(h, sh) == Vector{Int}[]        # no pair saves, so no route is formed (CR 57)
    @test pairwisesavings(h, sh) == (i = Int[], j = Int[], s = Float64[])
end

@testset "[CR 40] savings(...; ijs): a savings list of one's own" begin
    # the keyword takes the tuple pairwisesavings returns, in the order given, or Matlog's IJS matrix
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    ijs6 = pairwisesavings(h6, RPIN_SH6)
    @test savings(h6, RPIN_SH6; ijs = ijs6) == savings(h6, RPIN_SH6) == [[3, 1, 2, 2, 1, 3]]
    @test savings(h6, RPIN_SH6; ijs = hcat(ijs6...)) == savings(h6, RPIN_SH6)
    @test savings(h6, RPIN_SH6; ijs = ([1], [2], [240.0])) == [[1, 2, 2, 1]]       # shipment 3 is on no route
    @test savings(h6, RPIN_SH6; ijs = (Int[], Int[], Float64[])) == Vector{Int}[]
    # the list is the caller's, taken as given and not sorted again: the pair (2, 3) first forms the
    # route of shipments 2 and 3, and shipment 1 is then inserted into it by the pair (1, 2)
    Rrev = savings(h6, RPIN_SH6; ijs = ([2, 1], [3, 2], [95.0, 240.0]))
    @test sort(reduce(vcat, Rrev)) == [1, 1, 2, 2, 3, 3] && length(Rrev) == 1
    @test Rrev != savings(h6, RPIN_SH6) || h6(Rrev[1]) == 430
    @test_throws ArgumentError savings(h6, RPIN_SH6; ijs = ([1], [4], [1.0]))     # shipment 4 does not exist
    @test_throws ArgumentError savings(h6, RPIN_SH6; ijs = ([1, 2], [2], [1.0]))
    # P9: on the instances whose savings did not move (CR 39 moves the others), `savings(...; ijs)` is the
    # course's `savings_ijs(rteTCh, sh, ijs)` of Lecture 5.2 with its single-shipment routes filtered out,
    # as Ex. 9 and `loadform` filter them (`if length(r) > 2`, which CR 57 makes unnecessary)
    m = lecture52_module(:L52_savings)
    formed(R) = [r for r in R if length(r) > 2]
    for (sh, h) in ((RPIN_SH6, h6), (RPIN_SHG, _onetruck(RPIN_SHG, RPIN_DG)))
        ijs = pairwisesavings(h, sh)
        @test savings(h, sh; ijs = ijs) == formed(lecture52_call(m, :savings_ijs, h, sh, ijs))
    end
    # and where CR 39 moves the result, the stand-in is the old merge rule and differs, 5.2's Ex. 8 for one
    D = _rp_D30(); h = r -> rteTC(r, RPIN_SH30, D)
    ijs = pairwisesavings(h, RPIN_SH30)
    @test savings(h, RPIN_SH30; ijs = ijs) != formed(lecture52_call(m, :savings_ijs, h, RPIN_SH30, ijs))
    @test sum(h.(savings(h, RPIN_SH30; ijs = ijs))) <= sum(h([k, k]) for k in 1:nrow(RPIN_SH30))   # it saves
    # Lecture 5.2's own randomized savings (its randreorder, savings_ijs and randsavings) runs after `using
    # Logjam`, which exports none of those names (RTE11: Logjam's randreorder was removed before the release)
    @test !isdefined(Logjam, :randreorder)
    Random.seed!(5)
    rr, TCr = lecture52_call(m, :randsavings, h, RPIN_SH30; p = 0.1, nruns = 3)
    @test TCr == sum(h.(rr)) && isfinite(TCr)
    # Matlog's randomized savings, as 5.2's randsavings runs it, on Logjam's savings and twoopt with the
    # lecture's own randreorder (a tuple, which savings' ijs takes)
    function randsavings_logjam(rteTCh, sh; p = 0.1, nruns = 5)
        ijs = pairwisesavings(rteTCh, sh)
        best, TCbest = nothing, Inf
        for _ in 1:nruns
            R = savings(rteTCh, sh; ijs = lecture52_call(m, :randreorder, ijs, p))
            R = [twoopt(r, rteTCh)[1] for r in R]
            TC = sum(rteTCh.(R))
            TC < TCbest && ((best, TCbest) = (R, TC))
        end
        return best, TCbest
    end
    Random.seed!(5)
    Rb, TCb = randsavings_logjam(h, RPIN_SH30)
    alone30 = setdiff(1:30, reduce(vcat, Rb; init = Int[]))          # on no formed route (CR 57)
    @test isfinite(TCb) && sort(vcat(reduce(vcat, Rb; init = Int[]), [s for s in alone30 for _ in 1:2])) == sort(vcat(1:30, 1:30))
end

@testset "[CR 41] pairwisesavings(...; TC1): the independent cost of each shipment" begin
    h6 = r -> rteTC(r, RPIN_SH6, RPIN_D6)
    base = pairwisesavings(h6, RPIN_SH6)
    @test Tuple(base) == ([1, 1, 2], [2, 3, 3], [240.0, 180.0, 95.0])             # Lecture 5.2 Ex. 6(a)
    # the default is rteTC([k, k]): giving it changes nothing, as in Matlog's third argument
    TC1 = [h6([k, k]) for k in 1:3]
    @test TC1 == [300, 250, 275]
    @test pairwisesavings(h6, RPIN_SH6; TC1 = TC1) == base
    # another independent cost moves each savings by the change in the two it enters: s = TC1[i] + TC1[j] - c_ij
    i, j, s = pairwisesavings(h6, RPIN_SH6; TC1 = TC1 .+ [0, 40, 100])
    @test Set(zip(i, j)) == Set([(1, 2), (1, 3), (2, 3)])
    sd = Dict(zip(zip(i, j), s))
    @test sd[(1, 2)] == 240 + 40 && sd[(1, 3)] == 180 + 100 && sd[(2, 3)] == 95 + 40 + 100
    @test issorted(s; rev = true)
    # a pair whose savings are negative at the default is positive with a higher independent cost
    D = [0.0 1 9 9; 1 0 9 9; 9 9 0 1; 9 9 1 0]
    sh = DataFrame(b = [1, 3], e = [2, 4])
    h = r -> rteTC(r, sh, D)
    @test pairwisesavings(h, sh) == (i = Int[], j = Int[], s = Float64[])
    @test Tuple(pairwisesavings(h, sh; TC1 = [20.0, 20.0])) == ([1], [2], [20 + 20 - 19.0])   # the best route, (1, 2, 2, 1), costs 19
    @test_throws ArgumentError pairwisesavings(h, sh; TC1 = [1.0])
    # Matlog's makeRouting2.m Example 1 passes the shipments' direct distances as TC1 (`pairwisesavings(rTDh, sh, [sh.d])`)
    d = _readoracle("routing_52_ex1")
    shE = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"))
    hE = r -> rteTC(r, shE, d["D"])
    ii, jj, ss = pairwisesavings(hE, shE; TC1 = _fvec(d, "d"))
    @test Set(zip(ii, jj)) == Set((Int(a), Int(b)) for (a, b) in zip(d["IJS"][:, 1], d["IJS"][:, 2]))
    @test _oclose(ss, d["IJS"][:, 3])
end

@testset "[CR 48, S19] twoopt(π, C): the delta-cost method makes the general method's changes in its order" begin
    # S19: the tour argument of the new method is named π (his 5.1 rename)
    m = which(twoopt, (AbstractVector, AbstractMatrix))
    @test m.sig == Tuple{typeof(twoopt), AbstractVector, AbstractMatrix}
    @test :π in Base.method_argnames(m)
    # 5.1's traces (Matlog's tsp2opt tours) and Ex. 3's asymmetric six nodes, against the general method
    d = _readoracle("tsp_traces"); C = d["C"]
    for nm in ("sfc", "ch", "nn1", "nnb", "rnd1", "rnd2")
        loc0 = _ivec(d, nm * "_loc0")
        @test twoopt(loc0, C) == twoopt(loc0, π -> sum(segcost(π, C)))
    end
    D6 = d["six_D"]
    @test twoopt(_ivec(d, "six_loc0"), D6) == twoopt(_ivec(d, "six_loc0"), π -> sum(segcost(π, D6)))
    # seeded random instances, symmetric and asymmetric: the same tour and cost every time
    rng = Random.Xoshiro(20261120)
    same_sym = same_asym = true
    for _ in 1:60
        n = rand(rng, 6:30)
        X = rand(rng, n, 2) .* 30
        Cs = dists(X, X, 2)
        Ca = rand(rng, n, n) .* 10
        for k in 1:n
            Ca[k, k] = 0.0
        end
        t0 = vcat(1, shuffle(rng, 2:n), 1)
        same_sym &= twoopt(t0, Cs) == twoopt(t0, π -> sum(segcost(π, Cs)))
        same_asym &= twoopt(t0, Ca) == twoopt(t0, π -> sum(segcost(π, Ca)))
    end
    @test same_sym && same_asym
    # the input is not modified, and the returned cost is the tour's
    t0 = [1, 4, 2, 5, 3, 1]; t0copy = copy(t0)
    Cm = dists(rand(rng, 5, 2) .* 10, rand(rng, 5, 2) .* 10, 2)
    t, TC = twoopt(t0, Cm)
    @test t0 == t0copy && TC == sum(segcost(t, Cm))
    # a route vector has no arc-cost matrix form
    @test_throws ArgumentError twoopt([1, 2, 1, 2], Cm)
    # a short tour has no move; twoopt of three stops is the tour itself
    @test Tuple(twoopt([1, 2, 3, 1], [0 1 9; 1 0 1; 9 1 0])) == ([1, 2, 3, 1], 11)
    # the cost is O(m^2) a scan: 400 random points from a random start take well under a second
    # (the general method takes minutes at this size, CR 48)
    n = 400
    X = rand(rng, n, 2)
    Cb = dists(X, X, 2)
    tb = vcat(1, shuffle(rng, 2:n), 1)
    twoopt(vcat(tb[1:8], tb[1]), Cb)                        # compile
    local tr
    tdelta = @elapsed (tr = twoopt(tb, Cb))
    @test tr[2] ≈ sum(segcost(tr[1], Cb))
    @test tdelta < 20.0                                     # a regression bound with ten-fold margin
end

@testset "[S20] route twoopt on 5.2's NC route vector finishes in seconds" begin
    # S20: the route-vector 2-opt of the NC 30 shipments took 2.5 s against 0.1 s for 5.1's closed-tour
    # 2-opt of the location sequence. A regression bound, not a benchmark: ten times that measurement
    # for the route, so a slow machine passes and an accidental O(m^4) does not (K7a measured 0.8 s from
    # the identity route [1:30; 1:30], whose cost falls from 6,931 to 1,710 mi, and 0.04 s for the tour).
    D = _rp_D30(); h = r -> rteTC(r, RPIN_SH30, D)
    r0 = vcat(1:30, 1:30)
    twoopt([1, 2, 1, 2, 3, 3], h)                           # compile first
    local r, TC
    t = @elapsed ((r, TC) = twoopt(r0, h))
    @test TC == h(r) && TC < h(r0) / 3
    @test t < 25.0
    # the closed tour of the 31 locations of the same instance, for the ratio the record states
    X = _rp_xy54()[1:30, :]; C = dists(X, X, :mi)
    tour = vcat(1:30, 1)
    twoopt(tour, π -> sum(segcost(π, C)))
    t_tour = @elapsed twoopt(tour, π -> sum(segcost(π, C)))
    @test t_tour < 25.0
end

end  # @testset "K7a"

# ==== moved from test/test_routing_k7b.jl, its lines 1-321 ====
# test_routing_k7b.jl -- tests added by PCV K7b (the route cost and the location sequence): principle 9
# checks against Lecture 5.3's own inline definitions (run in a scratch module after `using Logjam`, as
# K7a did for 5.2's), and the tests of each K7b item that the K2 testsets do not hold. Each testset is
# tagged with the IDs of the items it belongs to.

using Test
using Logjam
using DataFrames
using Random

@isdefined(RPIN_SH30) || include(joinpath(@__DIR__, "routing_pin_cases.jl"))
@isdefined(LECTURE53_CODE) || include(joinpath(@__DIR__, "lecture53_code.jl"))

# 5.3's NC30 instance with MATLAB's distances: makeRouting3.m's 30 shipments from the depot (node 1)
function _k7b_nc30()
    d = _readoracle("routing_53_vrp"); D = d["D"]; n = size(D, 1) - 1
    q, s = _fvec(d, "q"), _fvec(d, "s")
    return (; d, D, n, q, s, sh = DataFrame(b = fill(1, n), e = 2:n+1, q = q, s = s))
end

# the checked route cost as 5.3's `TC, Xflg, out = rteTC_vrp(...)` is called
_vrp(args...) = Tuple(rteTC(args...; full = true))

# two outputs of the checked route cost agree: the cost and flag exactly (the same additions in the same
# order), every column of `out` to 1e-9 (infinite window bounds equal)
function _k7b_same(a, b; tol = 1e-9)
    (TCa, fa, oa), (TCb, fb, ob) = a, b
    (isequal(TCa, TCb) || isapprox(TCa, TCb; atol = tol, rtol = tol)) && fa == fb || return false
    names(oa) == names(ob) && size(oa) == size(ob) || return false
    return all(all(isapprox.(Float64.(oa[!, c]), Float64.(ob[!, c]); atol = tol, rtol = tol)) for c in names(oa))
end

# routes of 1 to `kmax` of the 30 customers: loaded in one order and unloaded in the same, in the reverse,
# and in a shuffle (which often returns to the depot midway)
function _k7b_routes(rng, kmax; nroutes = 150)
    R = Vector{Int}[]
    for _ in 1:nroutes
        idx = randperm(rng, 30)[1:rand(rng, 1:kmax)]
        push!(R, vcat(idx, idx), vcat(idx, reverse(idx)), shuffle(rng, vcat(idx, idx)))
    end
    return R
end

@testset "K7b" begin

@testset "[P9, N20] rte2loc and isorigin are typed and return the values they returned" begin
    sh = DataFrame(b = [10, 20], e = [15, 25])
    rte = [1, 2, 1, 2]
    @test rte2loc(rte, sh) isa Vector{Int}                       # v0.2.8: Vector{Any}
    @test rte2loc(rte, sh) == [10, 20, 15, 25]
    @test rte2loc(rte, sh, (b = 3, e = 4)) isa Vector{Int}
    @test rte2loc(rte, sh, (b = 3, e = 4)) == [3, 10, 20, 15, 25, 4]
    @test rte2loc(rte, sh, (b = [3], e = [4])) isa Vector{Int}
    @test rte2loc(rte, sh, (b = [], e = [])) == [10, 20, 15, 25]    # a truck given as empty `Any` vectors still works
    @test isorigin(rte) isa Vector{Bool} && isorigin(rte) == [true, true, false, false]
    @test isorigin(Int[]) == Bool[]
    @test isorigin(["a", "b", "a", "b"]) == [true, true, false, false]   # any hashable label
    # the course's own calls, from the pins: every location sequence equal to the pinned one is checked by
    # test_routing_pins.jl; here the element type of a depot route and of a truck given as scalars
    @test eltype(rte2loc([1, 2, 2, 1], DataFrame(b = [1, 1], e = [2, 3]), (b = 1, e = 1))) == Int
end

@testset "[CR 42] the degenerate-location rule: a depot route that returns to the depot midway is more than one route" begin
    # Matlog's rte2loc.m: with the truck's begin and end the same location, a location sequence that is at
    # that location, leaves it and is back and leaves again is NaN (degenerate); `Logjam._isdegenerate`
    # takes the route's own sequence (without the truck's two)
    tr = (b = 1, e = 1)
    sh = DataFrame(b = [1, 1, 1], e = [2, 3, 4])
    deg(r, t = tr) = Logjam._isdegenerate(rte2loc(r, sh), t)
    @test !deg([1, 2, 3, 3, 2, 1])               # loaded at the depot, delivered: leaves once, returns once
    @test !deg([1, 1])                           # one shipment: depot, then its customer
    @test !deg([1, 2, 2, 1])
    @test deg([1, 1, 2, 2])                      # 1 -> 2, back to the depot, 1 -> 3: two trips
    @test deg([1, 1, 2, 3, 3, 2])                # a second trip with a delivery before the last loading
    @test !deg([1, 2, 3, 3, 2, 1], (b = 1, e = 4))    # the truck's ends differ: the rule does not apply
    @test !deg([1, 1, 2, 2], (Kwt = 25,))             # a truck without locations
    @test !deg([1, 1, 2, 2], (b = 1,))
    # the sequence ends at the depot but never leaves... or starts away and passes it: Matlog's k = [1, -1]
    sh2 = DataFrame(b = [2, 1], e = [3, 4])
    @test Logjam._isdegenerate(rte2loc([1, 2, 2, 1], sh2), tr) == true      # 2 -> 1 -> 4 -> 3: through the depot midway
    # a vector truck location (the 5.2 form `(b = [1], e = [1])`) is read the same
    @test deg([1, 1, 2, 2], (b = [1], e = [1]))
    @test !deg([1, 2, 3, 3, 2, 1], (b = [1], e = [1]))
end

@testset "[P9, CR 42, CR 59, S8] rteTC(...; full = true) equals Lecture 5.3's rteTC_vrp on the course's inputs" begin
    m = lecture53_module(:L53_a)
    m′ = lecture53_module(:L53_b; scanfirst = true)               # HW 5's key defines scanTW first
    lec(args...) = lecture53_call(m, :rteTC_vrp, args...)
    lec′(args...) = lecture53_call(m′, :rteTC_vrp, args...)
    flags = Int[]
    chk(r, sh, C, tr) = (a = _vrp(r, sh, C, tr); b = lec(r, sh, C, tr);
                         push!(flags, a[2]); _k7b_same(a, b) && _k7b_same(a, lec′(r, sh, C, tr)))
    # slide 254 (5.3 Ex. 4): the route and its six orders
    T5 = zeros(4, 4); T5[1, 2] = 1; T5[2, 3] = 2; T5[3, 4] = 1; T5[4, 1] = 1
    sh5 = DataFrame(b = 1, e = [2, 3, 4], tU = 0.0, temin = [8, 12, 15], temax = [11, 14, 18])
    tr5 = (b = 1, e = 1, tbmin = 6, tbmax = 18, temin = 18, temax = 24)
    for p in ([1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1])
        @test chk([p; p], sh5, T5, tr5)
    end
    @test _vrp([1, 2, 3, 1, 2, 3], sh5, T5, tr5)[1:2] == (8.0, 1)
    # 5.3 Ex. 3: the 60 routes of three 10 t shipments on a 25 t truck, load mix by load mix
    d1 = _readoracle("routing_52_ex1")
    sh3 = DataFrame(b = _ivec(d1, "b"), e = _ivec(d1, "e"), q = [10, 10, 10])
    r60 = unique(shuffle.(Ref(Xoshiro(1)), fill([1, 1, 2, 2, 3, 3], 4000)))
    r60 = [r for r in r60 if all(>(0), cumsum(ifelse.(isorigin(r), 1, -1))[1:end-1])]
    @test length(r60) == 60
    for r in r60
        @test chk(r, sh3, d1["D"], (Kwt = 25,))
    end
    # the routes that fit load mix by load mix are those whose weight on board never passes 25 t (the lecture
    # counts them by `rtesegsum` as well, "again by the peaks")
    @test count(r -> isfinite(_vrp(r, sh3, d1["D"], (Kwt = 25,))[1]), r60) ==
          count(r -> maximum(cumsum(10 .* ifelse.(isorigin(r), 1, -1))[1:end-1]) <= 25, r60)
    # 5.3 Ex. 2 to 4 and 6 on NC30: capacity, maxTC, windows with loading and unloading, the time matrix
    # with five minutes on its diagonal (Ex. 6)
    c = _k7b_nc30(); rng = Xoshiro(20261120)
    trc = (b = 1, e = 1, Kwt = 25, Kcu = 2750)
    sh6 = DataFrame(b = fill(1, c.n), e = 2:c.n+1, q = c.q, s = c.s, tU = c.q * 30/60,
                    temin = [fill(7, 15); fill(13, 15)], temax = [fill(17, 15); fill(23, 15)])
    T6 = c.D / 50 .+ 5/60
    sh7 = copy(sh6); sh7.tL = fill(0.1, c.n); sh7.tbmin = fill(6.0, c.n); sh7.tbmax = fill(20.0, c.n)
    R = _k7b_routes(rng, 12)
    for r in R
        @test chk(r, c.sh, c.D, trc)                                       # Ex. 2
        @test chk(r, c.sh, c.D, merge(trc, (maxTC = 600,)))                # Ex. 4
        @test chk(r, c.sh, c.D, merge(trc, (Kcu = 400,)))                  # a cube that binds
        @test chk(r, c.sh, c.D, (Kwt = 25.0,))                             # no truck locations
        @test chk(r, sh6, T6, trc)                                         # Ex. 6
        @test chk(r, sh6, T6, merge(trc, (maxTC = 10,)))
        @test chk(r, sh7, T6, merge(trc, (tbmin = 5, tbmax = 12, temin = 14, temax = 26)))
        @test chk(r, sh6, T6, (Kwt = 25,))
    end
    # the instances reach every exit flag, so the comparison is not vacuous
    @test Set(flags) == Set([1, -1, -2, -3, -4, -5])
    # a vector of routes
    Rv = R[1:60]
    a, b = _vrp(Rv, sh6, T6, trc), lec(Rv, sh6, T6, trc)
    @test a[2] == b[2] && all(_k7b_same((a[1][i], a[2][i], a[3][i]), (b[1][i], b[2][i], b[3][i])) for i in 1:60)
end

@testset "[P9, CR 42, S8] Logjam.scanTW equals Lecture 5.3's scanTW" begin
    m = lecture53_module(:L53_scan)
    rng = Xoshiro(7)
    for _ in 1:300
        n = rand(rng, 2:9)
        t = [0.0; rand(rng, n - 1) * 3]; u = rand(rng, n) * 0.5
        ℓ = cumsum(rand(rng, n) * 2); h = ℓ .+ rand(rng, n) * 3
        rand(rng) < 0.3 && (ℓ[rand(rng, 1:n)] = -Inf); rand(rng) < 0.3 && (h[rand(rng, 1:n)] = Inf)
        a, b = Logjam.scanTW(t, u, ℓ, h), lecture53_call(m, :scanTW, t, u, ℓ, h)
        @test isequal(a, b)
    end
    @test Logjam.scanTW([0, 1, 2, 1, 1], zeros(5), [6, 8, 12, 15, 18], [18, 11, 14, 18, 24])[1] == 8
end

@testset "[S8] the hours-of-service wrapper of 5.3's Code block 37 reads the checked cost's out" begin
    c = _k7b_nc30()
    sh6 = DataFrame(b = fill(1, c.n), e = 2:c.n+1, q = c.q, s = c.s, tU = c.q * 30/60,
                    temin = [fill(7, 15); fill(13, 15)], temax = [fill(17, 15); fill(23, 15)])
    T6 = c.D / 50 .+ 5/60; tr = (b = 1, e = 1, Kwt = 25, Kcu = 2750)
    m = lecture53_module(:L53_hos)
    function hos(f)                     # 5.3 Code block 37
        return function (rte)
            TT, _, out = f(rte, sh6, T6, tr)
            isinf(TT) && return Inf
            drive = sum(out.Cost)
            return drive > 11 || TT > 14 ? Inf : TT
        end
    end
    h1, h2 = hos(_vrp), hos((a...) -> lecture53_call(m, :rteTC_vrp, a...))
    R = _k7b_routes(Xoshiro(3), 8; nroutes = 100)
    @test all(isequal(h1(r), h2(r)) || isapprox(h1(r), h2(r); atol = 1e-9) for r in R)    # to 1e-9; the same routes feasible
    @test any(isinf, h1.(R)) && any(isfinite, h1.(R))
    @test any(r -> isfinite(h1(r)) && sum(_vrp(r, sh6, T6, tr)[3].Cost) > 5, R)
    # the columns of out are the contract
    out = _vrp([1, 2, 1, 2], sh6, T6, tr)[3]
    @test names(out) == ["Rte", "Loc", "Cost", "Arrive", "Wait", "TWmin", "Start", "LU", "Depart", "TWmax", "Total"]
    @test names(_vrp([1, 2, 2, 1], c.sh, c.D, tr)[3]) == ["Rte", "Loc", "Cost"]
    @test names(_vrp([1, 2, 2, 1], sh6[:, [:b, :e, :tU]], T6, tr)[3]) == ["Rte", "Loc", "Cost", "LU"]
end

@testset "[S44] a full-cube maxpayld load is not flagged over capacity" begin
    C = [0.0 10.0; 10.0 0.0]; tr = (b = 1, e = 1, Kwt = 25.0, Kcu = 2750.0)
    for s in (5.0, 7.0, 8.0, 11.3, 13.7, 25.0, 40.0, 100 / 3)
        sh = DataFrame(b = [1], e = [2], q = [maxpayld(s)], s = [s])
        @test _vrp([1, 1], sh, C, tr)[2] == 1
    end
    sh = DataFrame(b = [1], e = [2], q = [1.001 * maxpayld(8.0)], s = [8.0])
    @test _vrp([1, 1], sh, C, tr)[1:2] == (Inf, -3)
    @test _vrp([1, 1], DataFrame(b = [1], e = [2], q = [25.0], s = [100.0]), C, tr)[2] == 1      # 25 t, weight-limited
    @test _vrp([1, 1], DataFrame(b = [1], e = [2], q = [25.0 + 1e-9], s = [100.0]), C, tr)[2] == -2
end

@testset "[CR 42] maxTC is checked on cost plus loading before the scans, and does not bound a windowed route's duration" begin
    # one customer, 2 h away (T), 1 h to unload, a window that opens at 10: travel plus unloading is
    # 2 + 1 + 2 = 5 h, within maxTC = 9, but the route's time with its wait is longer
    T = [0.0 2.0; 2.0 0.0]
    sh = DataFrame(b = [1], e = [2], tU = [1.0], temin = [10.0], temax = [14.0])
    tr = (b = 1, e = 1, maxTC = 9.0)
    TC, Xflg, out = _vrp([1, 1], sh, T, tr)
    @test Xflg == 1 && TC == 5.0                     # the scans leave the route's time at its travel and unloading (no wait: it can start later)
    @test _vrp([1, 1], sh, T, (b = 1, e = 1, maxTC = 4.9))[1:2] == (Inf, -4)
    # a window that holds the route up: the depot's window forces the start
    tr2 = (b = 1, e = 1, maxTC = 9.0, tbmin = 0.0, tbmax = 0.0)
    TC2, Xflg2, out2 = _vrp([1, 1], sh, T, tr2)
    @test Xflg2 == 1 && TC2 > 5 && TC2 <= 9 + 100  # waits for the window: past the travel and unloading it was tested on
    @test TC2 == sum(out2.Total)
end

@testset "[P9, D10] Lecture 5.3's own rteTC_vrp, rte2ldmx and scanTW still run after `using Logjam`, in either order" begin
    m = lecture53_module(:L53_after)
    sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6], q = [10, 10, 10])
    D = RPIN_D6
    @test lecture53_call(m, :rteTC_vrp, [1, 2, 1, 3, 2, 3], sh, D, (Kwt = 25,))[1:2] == (1075.0, 1)
    @test lecture53_call(m, :rte2ldmx, [1, 2, 1, 3, 2, 3]) == [[1, 2], [2, 3]]
    @test getfield(m, :rte2ldmx) !== Logjam.rte2ldmx && getfield(m, :scanTW) !== Logjam.scanTW
    @test !isdefined(Logjam, :rteTC_vrp)             # one route cost function: no second name
    # Logjam's names used first (the exported ones), then the lecture defines its own
    m2 = Module(:L53_call_first)
    Core.eval(m2, :(using Logjam)); Core.eval(m2, :(using DataFrames))
    @test Core.eval(m2, :(rte2ldmx([1, 2, 3, 3, 2, 1]))) == [[1, 2, 3]]
    @test Core.eval(m2, :(rteTC([1, 1], DataFrame(b = [1], e = [2]), [0.0 3.0; 3.0 0.0]))) == 3.0
    for ex in Meta.parseall(LECTURE53_CODE).args
        ex isa LineNumberNode || Core.eval(m2, ex)
    end
    @test lecture53_call(m2, :rteTC_vrp, [1, 2, 1, 3, 2, 3], sh, D, (Kwt = 25,))[1:2] == (1075.0, 1)
    # scanTW is public and not exported (the lecture's own is the implementation rung of a model)
    @test Base.ispublic(Logjam, :scanTW) && !Base.isexported(Logjam, :scanTW)
    @test Base.isexported(Logjam, :rte2ldmx) && Base.isexported(Logjam, :rteTC)
end

@testset "[P9, CR 42, D6] one rteTC: a plain call returns the cost alone, and what it returned unless a limit is on the truck" begin
    c = _k7b_nc30()
    tr = (b = 1, e = 1)
    r = vcat(1:c.n, 1:c.n)
    # no limit fields: v0.2.8's value, exactly (sum of the segment costs), a bare number
    @test rteTC(r, c.sh, c.D, tr) === sum(segcost(rte2loc(r, c.sh, tr), c.D))
    @test rteTC(r, c.sh, c.D) === sum(segcost(rte2loc(r, c.sh), c.D))
    # a route that returns to the depot midway is priced by a plain call with no limit on the truck
    @test isfinite(rteTC([1, 1, 2, 2], DataFrame(b = [1, 1], e = [2, 3]), [0 5 7; 5 0 4; 7 4 0], tr))
    @test rteTC([1, 1], DataFrame(b = [1], e = [2], q = [30.0], s = [8.0]), [0.0 10.0; 10.0 0.0],
                (b = Int[], e = Int[], Kwt = 25.0, Kcu = 2750.0); full = true).Xflg == -2   # an empty truck location is no degenerate route
    @test_throws ArgumentError rteTC([1, 1], DataFrame(b = [1], e = [2], q = [3.0]), [0.0 1.0; 1.0 0.0], (b = 1, e = 1, Kcu = 100))
    # a limit on the truck is read: capacity, cube, maxTC and the degenerate route are Inf
    @test isinf(rteTC(r, c.sh, c.D, merge(tr, (Kwt = 25, Kcu = 2750))))
    @test isfinite(rteTC([1, 1], c.sh, c.D, merge(tr, (Kwt = 25, Kcu = 2750))))
    @test isinf(rteTC([1, 1], c.sh, c.D, merge(tr, (maxTC = 1.0,))))
    @test isinf(rteTC([1, 1, 2, 2], DataFrame(b = [1, 1], e = [2, 3]), [0 5 7; 5 0 4; 7 4 0], merge(tr, (Kwt = 25,))))
    # loading and unloading times and windows are read only with full = true
    sh = DataFrame(b = [1], e = [2], tU = [3.0], temin = [10.0], temax = [14.0])
    T = [0.0 2.0; 2.0 0.0]
    @test rteTC([1, 1], sh, T, tr) == 4.0
    @test rteTC([1, 1], sh, T, tr; full = true).TC > 4.0
    # full = true is a named tuple that destructures as 5.3's `TC, Xflg, out = rteTC_vrp(...)`
    TC, Xflg, out = rteTC([1, 1], sh, T, tr; full = true)
    @test Xflg == 1 && out isa DataFrame && TC == rteTC([1, 1], sh, T, tr; full = true).TC
    # a vector of routes: the method does not take a route (a vector of integers) for one
    R = [[1, 1], [1, 2, 2, 1]]
    sh2 = DataFrame(b = [1, 1], e = [2, 3])
    D3 = [0 5 7; 5 0 4; 7 4 0]
    @test rteTC(R, sh2, D3, tr) == [rteTC(r, sh2, D3, tr) for r in R]
    f = rteTC(R, sh2, D3, tr; full = true)
    @test f.TC == [rteTC(r, sh2, D3, tr; full = true).TC for r in R] && f.Xflg == [1, 1] && length(f.out) == 2
end

@testset "[P9, N20, CR 42] the default truck is (;), the travel cost is today's sum bit for bit, the route-set method is not ambiguous" begin
    C = rand(Xoshiro(2), 4, 4) * 10
    for i in 1:4; C[i, i] = 0.0; end
    sh = DataFrame(b = [1, 3], e = [2, 4])
    for r in ([1, 1], [1, 2, 2, 1], [1, 2, 1, 2], [2, 1, 1, 2], [1, 2, 1, 2]),
        tr in ((;), (b = 1, e = 1), (b = [1], e = [1]), (b = Int[], e = Int[]), (Kwt = 25,), (b = 4,))
        s = sum(segcost(rte2loc(r, sh, tr), C))
        f = rteTC(r, sh, C, tr; full = true)
        # a route that returns to a depot truck's depot midway (b = e) is refused by full = true, flag -1
        @test f.Xflg == 1 ? f.TC === s : (isinf(f.TC) && f.Xflg == -1 && haskey(tr, :b))
        f.Xflg == 1 || continue
        @test rteTC(r, sh, C, tr) === s                           # plain, no limit (or a limit that is met)
        @test f.TC === s                                          # full = true: the same sum, bit for bit
    end
    @test rteTC([1, 2, 2, 1], sh, C) === sum(segcost(rte2loc([1, 2, 2, 1], sh), C))
    # a truck with a capacity only: rte2loc reads no b and e (v0.2.8: FieldError), as 5.3's tr3 = (Kwt = 25,)
    @test rte2loc([1, 2, 2, 1], sh, (Kwt = 25,)) == rte2loc([1, 2, 2, 1], sh) isa Vector{Int}
    @test rte2loc([1, 2, 2, 1], sh, (b = 4,)) == vcat(4, rte2loc([1, 2, 2, 1], sh))
    @test rte2loc([1, 2, 2, 1], sh, (e = 4,)) == vcat(rte2loc([1, 2, 2, 1], sh), 4)
    # the route-set method does not make the route method ambiguous
    amb = Test.detect_ambiguities(Logjam)
    @test !any(p -> any(m -> m.name == :rteTC, p), amb)
    @test rteTC([[1, 1], [2, 2]], sh, C, (b = 1, e = 1)) == [rteTC([1, 1], sh, C, (b = 1, e = 1)), rteTC([2, 2], sh, C, (b = 1, e = 1))]
    @test rteTC([1, 1], sh, C) isa Float64                         # a route (vector of integers) is a route
end

@testset "[CR 43] a same-location segment costs nothing, and the multi-trip route is decided" begin
    C = [5.0 10.0 7.0; 10.0 5.0 4.0; 7.0 4.0 5.0]            # a positive diagonal (a stop time)
    sh = DataFrame(b = [1, 1], e = [2, 3])
    tr = (b = 1, e = 1)
    # route (1, 2, 2, 1): 1 -> 1 -> 3 -> 2 -> 1 with the truck's ends: the first segment is at one location
    @test rteTC([1, 2, 2, 1], sh, C, tr) == 7.0 + 4.0 + 10.0
    @test rteTC([1, 2, 2, 1], sh, C, tr; full = true).TC == 7.0 + 4.0 + 10.0
    @test rteTC([1, 2, 2, 1], sh, C, merge(tr, (Kwt = 25,))) == 7.0 + 4.0 + 10.0
    # a zero diagonal moves nothing (every pinned course call); a nonzero one is charged no more
    @test rteTC([1, 1], sh, C) == 10.0
    # the decision CR 43 asks for: a route that returns to its depot midway is PRICED by a plain call with no
    # limit on the truck (as v0.2.8 did) and REFUSED, flag -1, with full = true or a limit on the truck
    mt = [1, 1, 2, 2]
    @test isfinite(rteTC(mt, sh, C, tr))
    @test rteTC(mt, sh, C, tr; full = true).Xflg == -1 && isinf(rteTC(mt, sh, C, tr; full = true).TC)
    @test isinf(rteTC(mt, sh, C, merge(tr, (Kwt = 25,))))
end

@testset "[CR 59] rte2ldmx lists the shipments on board at each load mix" begin
    @test rte2ldmx([1, 2, 3, 3, 2, 1]) == [[1, 2, 3]]
    @test rte2ldmx([1, 2, 1, 3, 2, 3]) == [[1, 2], [2, 3]]
    @test rte2ldmx([1, 1]) == [[1]]
    @test rte2ldmx([1, 1, 2, 2]) == [[1], [2]]
    @test rte2ldmx([1, 2, 2, 1]) == [[1, 2]]
    @test rte2ldmx(Int[]) == Vector{Int}[]
    # the loads of a route of 5.3's Ex. 3 add up: every shipment is on board at some mix
    @test sort(unique(reduce(vcat, rte2ldmx([3, 1, 2, 2, 1, 3])))) == [1, 2, 3]
end

end  # @testset "K7b"

# ==== moved from test/test_properties.jl, its lines 1-16, 27-27, 141-234, 282-283 ====
# Property tests (test spec Sec. 3; PCV K2a). Seeded random instances, small enough to run in seconds.
#
# What is proved for every function that returns a solution: the cost it returns is the cost of the
# solution it returns, index sets come back sorted, sequences come back in route order, local
# optimality holds where the docstring claims it, a caller's input is not mutated, and zero in gives
# zero out. A property the current code fails is `@test_broken` with a comment naming the change
# request (CR) or finding (N) that fixes it and the component (K3-K9) whose commit flips it to `@test`.
#
# Tolerances (test spec rule 4, fixed in advance): exact equality for integer and index results;
# relative 1e-9 for costs computed from the same input.

using Test
using Logjam
using Random
using SparseArrays
using DataFrames
isdefined(@__MODULE__, :_ufl_cost) || include(joinpath(@__DIR__, "property_helpers.jl"))   # WP8: defined once

@testset "routetools: properties" begin

# ---------------------------------------------------------------------------------------------
@testset "routing: cost, order, local optimality, no mutation" begin
    onboard(r) = cumsum(ifelse.(isorigin(r), 1, -1))[1:end-1]
    isroute(r) = all(>(0), onboard(r))
    rng = Random.Xoshiro(531)

    # rteTC is the sum of the cost-matrix entries of the location sequence, recomputed independently
    ok_rteTC = true
    for _ in 1:10
        k = rand(rng, 2:5)
        X = rand(rng, 2k, 2) .* 30
        C = dists(X, X, 2)
        perm = randperm(rng, 2k)
        sh = DataFrame(b = perm[1:k], e = perm[k+1:2k])
        r = shuffle(rng, vcat(1:k, 1:k))
        loc = Int[]
        seen = Set{Int}()
        for s in r
            push!(loc, s in seen ? sh.e[s] : sh.b[s]); push!(seen, s)
        end
        ok_rteTC &= _close(rteTC(r, sh, C), sum(C[loc[i], loc[i+1]] for i in 1:length(loc)-1))
    end
    @test ok_rteTC

    # mincostinsert: returned cost = cost of the returned route; the old route is a subsequence in the
    # same order (a sequence is never reordered); each shipment twice, loaded before unloaded
    ok_ins, ok_ins_route = true, true
    for _ in 1:10
        k = rand(rng, 2:5)
        X = rand(rng, 2k, 2) .* 30
        C = dists(X, X, 2)
        perm = randperm(rng, 2k)
        sh = DataFrame(b = perm[1:k], e = perm[k+1:2k])
        h = r -> rteTC(r, sh, C)
        rte = Int[]
        for idx in 1:k
            old = copy(rte)
            rte, TC = mincostinsert(idx, rte, h)
            ok_ins &= _close(TC, h(rte)) && count(==(idx), rte) == 2 &&
                      filter(!=(idx), rte) == old
            ok_ins_route &= isroute(rte)
        end
    end
    @test ok_ins
    # CR 38: v0.2.8's search also tried loading and unloading after the last stop, which is not a route; fixed in K7a
    @test ok_ins_route

    # twoopt on tours (depot at both ends): returned cost = cost of the tour, a permutation of the
    # input, ends unchanged, input not mutated, and no interior reversal improves (local optimality)
    ok_2opt, nomut_2opt, perm_2opt = true, true, true
    for _ in 1:10
        n = rand(rng, 5:9)
        X = rand(rng, n, 2) .* 30
        C = dists(X, X, 2)
        h = r -> sum(C[r[i], r[i+1]] for i in 1:length(r)-1)
        t0 = vcat(1, shuffle(rng, 2:n), 1)
        t0copy = copy(t0)
        t, TC = twoopt(t0, h)
        ok_2opt &= _close(TC, h(t)) && t[1] == 1 && t[end] == 1
        nomut_2opt &= (t0 == t0copy)
        perm_2opt &= sort(t) == sort(t0)
        len = length(t)
        ok_2opt &= !any(h(vcat(t[1:i-1], reverse(t[i:j]), t[j+1:end])) < TC - 1e-9
                        for i in 2:len-2 for j in i+1:len-1)
    end
    @test ok_2opt
    @test nomut_2opt
    @test perm_2opt

    # savings (CR 57, K7a): returns the routes it FORMS only, as Matlog's does. Each shipment is on at most one
    # formed route, twice, each formed route a route of two or more shipments; the formed routes plus one
    # single-shipment route for each shipment on none cover every shipment; and the construction never costs
    # more than shipping every shipment on its own route (each merge must save: CR 39)
    ok_part, ok_nowaste = true, true
    for _ in 1:60
        k = rand(rng, 3:5)
        X = rand(rng, 2k, 2) .* 20
        C = dists(X, X, 2)
        perm = randperm(rng, 2k)
        sh = DataFrame(b = perm[1:k], e = perm[k+1:2k])
        h = r -> rteTC(r, sh, C)
        R = savings(h, sh)
        formed = reduce(vcat, (unique(r) for r in R); init = Int[])
        alone = setdiff(1:k, formed)
        covered = vcat(reduce(vcat, R; init = Int[]), [s for s in alone for _ in 1:2])
        ok_part &= allunique(formed) && all(r -> length(r) >= 4 && all(c -> c == 2, values(Dict(x => count(==(x), r) for x in r))), R) &&
                   sort(covered) == sort(vcat(1:k, 1:k)) && all(isroute, R)
        ok_nowaste &= sum(h.(R); init = 0.0) + sum(h([s, s]) for s in alone; init = 0.0) <= sum(h([i, i]) for i in 1:k) + 1e-9
    end
    @test ok_part
    # CR 39 (v0.2.8's savings merged without checking that the merge saves), fixed in K7a
    @test ok_nowaste
end

end  # properties

# ==== moved from test/test_oracles.jl, its lines 1-36, 38-38, 390-749 ====
# Oracle tests (test spec Sec. 4; PCV K2b). The data in test/oracles/*.csv is written by
# tools/v0_3_0/make_oracles.m (MATLAB R2025a, Matlog V18 on the path), each file headed by the MATLAB call
# that produced it. Nothing here is computed by MATLAB at test time.
#
# Tolerances (test spec rule 4, fixed in advance, never chosen after a result):
#   - exact equality for integer and index results (sites, routes, route positions, flags);
#   - relative 1e-9 for costs computed from the same inputs (`_oclose`; an absolute floor of 1e-12 only
#     guards comparisons with an exact zero);
#   - a great-circle distance in miles or kilometers against Matlog's only as the documented difference (D7):
#     Logjam's dgc keeps the sphere (DST1, DST2) where Matlog's `dists` uses a latitude-dependent radius, so the
#     two agree within the named tolerance GC_RADIUS_RTOL (relative 1e-3, oracle_helpers.jl; charge SC 4) and
#     are asserted to differ at 1e-9; the arc (radians), and Matlog's arc times the sphere's radius, at 1e-9.
# Routing oracles take MATLAB's distance matrix as input, so they compare independent of distance formulas.
#
# A comparison the current code fails, or cannot make because the function does not exist yet, is
# `@test_broken` with a comment naming its ID (CR n, N n, D n, S n) and the K component whose commit flips
# it to `@test`. A Matlog output the plan deliberately departs from is NOT an oracle for that quantity: the
# departure is asserted as its own test and named (DEPARTURE).
#
# Skipped, with the reason (the generator's header lists the same): Matlog ala Examples 3-4 (the `trans`
# transportation solver has no Logjam counterpart); makeRouting4 route-mode minTLC and Example 3 (CR 44,
# declined; Shapley allocation); makeFrghtTrans3 Example C (random multistart sweep) and Example B parts
# 4-6 (an optimizer's argmin is not compared: the cost functions are compared AT the saved MATLAB argmin);
# rtenorm (no Logjam port is planned under that name).

using Test
using Logjam
using DataFrames
using SparseArrays

isdefined(@__MODULE__, :ORACLE_DIR) || include(joinpath(@__DIR__, "oracle_helpers.jl"))   # _readoracle, _oclose, _try, _has, _transcharge, ...

# Matlog's rteTC (capacity, maxTC, time windows; returns TC, Xflg, out; CR 42, MakePlan D6/D9) is
# `rteTC(rte, sh, C, tr; full = true)` (K7b: one route cost function, his ruling of 2026-11-20).
# Call: CHECKED_RTETC(rte, sh, C, tr) -> (TC, Xflg, out) with `sh`, `tr` as below.
const CHECKED_RTETC = (rte, sh, C, tr) -> Tuple(Logjam.rteTC(rte, sh, C, tr; full = true))

@testset "routetools: oracles" begin

# =============================================================================================
# Routing. Every oracle takes MATLAB's distance (or time) matrix as input. Routes are compared as the
# physical tour they drive: the location sequence with runs of the same location collapsed. That is an
# exact integer comparison, and it leaves out only the order of shipments delivered at one location, which
# MATLAB and Julia break differently when two orders cost the same to the last bit (CR 58 is the plan item
# that normalizes it, K7); `rteTC` skips same-location segments, so the cost cannot tell them apart.
function _tour(rte, sh, tr = (b = Int[], e = Int[]))
    loc = rte2loc(rte, sh, tr)
    return loc[vcat(true, diff(loc) .!= 0)]
end
_tours(rs, sh, tr = (b = Int[], e = Int[])) = Set(Tuple(_tour(r, sh, tr)) for r in rs)

# Matlog V18 mincostinsert.m's mincostshmtinsert for an unsigned route (K7a-2): `i = 1:m + 1`, `j = i:m + 1`, a
# `j` skipped when `j > 1 && isduploc(j-1)`, `isduploc = [false; loc[1:end-1] .== loc[2:end]]` over
# `loc = rte2loc(rte, sh)`. Logjam's own `mincostinsert` follows his F24 loop instead (CR 38: `i = 1:m`,
# `j = max(2, i):m + 1`, no skip), so `savings` is run here with this insertion through the internal hook
# `Logjam._savings(...; insert)` (no public keyword, principle 8) to reproduce MATLAB's routes exactly.
function _matlog_insert(sh)
    return function (idx, rte, h)
        loc = rte2loc(rte, sh)
        isduploc = [false; loc[1:end-1] .== loc[2:end]]
        m = length(rte); best, TCb = copy(rte), Inf
        for i in 1:m+1, j in i:m+1
            j > 1 && isduploc[j-1] && continue
            r = vcat(rte[1:i-1], idx, rte[i:j-1], idx, rte[j:end])
            TC = h(r)
            TC < TCb && ((best, TCb) = (r, TC))
        end
        return best, TCb
    end
end
# The checked route cost as a handle that adds the segment costs IN ORDER, as MATLAB's `sum` does for a short
# vector (Julia's `sum` of a vector is blocked and differs in the last places, and a 2-opt tie, a reversal
# that is a zero change in exact arithmetic, is decided by those places: K7a). `rteTC` itself sums with `sum`,
# as v0.2.8 did, so a handle that reproduces MATLAB's routes tie for tie sums `out.Cost` itself. No windows
# or loading times here, so the cost is the sum of the segment costs; an infeasible route is Inf.
function _inorder_h(sh, C, tr)
    return function (rte)
        TC, Xflg, out = CHECKED_RTETC(rte, sh, C, tr)
        return Xflg == 1 ? foldl(+, out.Cost) : Inf
    end
end
function _savings_matlog(h, sh)
    n = nrow(sh)
    iˢ, jˢ = Logjam._savings_list(pairwisesavings(h, sh), n)
    return Logjam._savings(h, n, iˢ, jˢ; insert = _matlog_insert(sh))
end

@testset "oracle: route utilities, Matlog help examples" begin
    d = _readoracle("route_examples")
    rte = _ivec(d, "rte2idx_in")
    @test Bool.(isorigin(rte)) == (vec(d["isorigin_out"]) .== 1)
    @test rte[isorigin(rte)] == _ivec(d, "rte2idx_out")      # rte2idx's definition in its help text
    shE = DataFrame(b = _ivec(d, "ex1_b"), e = _ivec(d, "ex1_e"))
    @test rte2loc(_ivec(d, "ex1_rte"), shE) == _ivec(d, "ex1_loc")
    @test _oclose(rteTC(_ivec(d, "ex1_rte"), shE, d["ex1_C"]), _sc(d, "ex1_TC"))       # TC = 22
    # The ports (CR 53, CR 59; MakePlan D-g: under their Matlog names, K7; rtesegid internal since IN5). Matlog's shapes: rte2idx
    # -> index vector; rte2ldmx -> vector of load-mix vectors; rtesegsum -> vector of length 2m - 1; rtesegid
    # -> m x (2m - 1) Bool matrix (restated below as one set per segment); sh2rte(idx, routes) ->
    # (routes with a single-shipment route added for each shipment in none, those shipments' indices).
    rte = _ivec(d, "rte2idx_in")
    @test Logjam.rte2idx(rte) == _ivec(d, "rte2idx_out")                              # CR 53, K7c
    rte = _ivec(d, "ld_in")
    @test [Int.(vec(x)) for x in rte2ldmx(rte)] == _cells(d, "ld")                 # CR 59, K7b
    rte = _ivec(d, "seg_in")
    @test _oclose(Logjam.rtesegsum(rte, _fvec(d, "seg_xsh")), _fvec(d, "rtesegsum_out"))          # CR 53, K7c
    # Matlog's m x (2m - 1) logical matrix, restated as one set of shipments on board for each segment
    # (the ruled shape, K7C): column k lists the shipments of segment k
    Lseg = d["rtesegid_out"]
    @test Logjam.rtesegid(rte) == [findall(Lseg[:, k] .> 0) for k in 1:size(Lseg, 2)]         # CR 53, K7c
    let                                                                                  # CR 53, K7c
        rout, idx1 = Logjam.sh2rte(_ivec(d, "sh2rte_idx"), _cells(d, "sh2rte_in"))
        @test rout == _cells(d, "sh2rte_out") && idx1 == _ivec(d, "sh2rte_idx1")
    end
end

@testset "oracle: rteTC with capacity, maxTC and time windows (CR 42)" begin
    d = _readoracle("route_timewindows")
    # `CHECKED_RTETC(rte, sh, C, tr)` -> (TC, Xflg, out), Matlog's rteTC, is not built yet (CR 42, D6: under
    # its own name, K7). `out` is read by field name: Rte Loc Cost Arrive Wait TWmin Start LU Depart TWmax Total.
    flds = (:Rte, :Loc, :Cost, :Arrive, :Wait, :TWmin, :Start, :LU, :Depart, :TWmax, :Total)
    function tw_ok(pre, sh, C, tr, rte)
        TC, Xflg, out = CHECKED_RTETC(rte, sh, C, tr)
        return _oclose(TC, _sc(d, pre * "_TC")) && Xflg == _sc(d, pre * "_Xflg") &&
               all(_oclose(getproperty(out, f), d["$(pre)_out_$f"]) for f in flds)
    end
    # rteTC help Example 2 and makeRouting3 Example 5
    sh2 = DataFrame(b = _ivec(d, "h2_b"), e = _ivec(d, "h2_e"), tbmin = _fvec(d, "h2_tbmin"), tbmax = _fvec(d, "h2_tbmax"))
    tr2 = (b = _ivec(d, "h2_tr_b"), e = _ivec(d, "h2_tr_e"), tbmin = _sc(d, "h2_tr_tbmin"), tbmax = _sc(d, "h2_tr_tbmax"),
           temin = _sc(d, "h2_tr_temin"), temax = _sc(d, "h2_tr_temax"))
    sh5 = DataFrame(b = _ivec(d, "e5_b"), e = _ivec(d, "e5_e"), tU = _fvec(d, "e5_tU"), temin = _fvec(d, "e5_temin"), temax = _fvec(d, "e5_temax"))
    tr5 = (b = _ivec(d, "e5_tr_b"), e = _ivec(d, "e5_tr_e"), tbmin = _sc(d, "e5_tr_tbmin"), tbmax = _sc(d, "e5_tr_tbmax"),
           temin = _sc(d, "e5_tr_temin"), temax = _sc(d, "e5_tr_temax"))
    @test tw_ok("h2", sh2, d["h2_C"], tr2, _ivec(d, "h2_rte"))      # CR 42, K7b
    @test tw_ok("e5", sh5, d["e5_T"], tr5, _ivec(d, "e5_rte"))
    # The scalar rteTC is unchanged by the plan (D6): it sums the segment costs of the location sequence and
    # reads no time window, so it returns 5 (= 1 + 2 + 1 + 1) where Matlog's checked one, which adds the
    # waiting, returns 8. Asserted as its own test, so the departure survives K7.
    @test _oclose(rteTC(_ivec(d, "h2_rte"), sh2, d["h2_C"], (b = [1], e = [1])), 5.0)
    @test _sc(d, "h2_TC") == 8
end

@testset "oracle: TSP loc sequences, makeRouting1.m (tsp2opt) and 5.1 Ex. 3" begin
    d = _readoracle("tsp_traces")
    C = d["C"]
    h = π -> sum(segcost(π, C))
    # Logjam's twoopt, run on the saved construction sequence, reaches Matlog's tsp2opt tour and cost
    # exactly. K7a's delta-cost method (CR 48, `twoopt(π, C)`) passes the same data.
    for nm in ("sfc", "ch", "nn1", "nnb", "rnd1", "rnd2")
        loc0 = _ivec(d, nm * "_loc0")
        @test _oclose(h(loc0), _sc(d, nm * "_TC0"))
        π, TC = twoopt(loc0, h)
        @test π == _ivec(d, nm * "_loc")
        @test _oclose(TC, _sc(d, nm * "_TC"))
        πδ, TCδ = twoopt(loc0, C)
        @test πδ == _ivec(d, nm * "_loc")
        @test _oclose(TCδ, _sc(d, nm * "_TC"))
    end
    # 5.1 Ex. 3 (slide 240's trace): six nodes, asymmetric D, from the tour 1-2-3-4-5-6-1; the cost of the
    # start is 38 and 2-opt ends at 1-5-4-2-3-6-1, cost 12
    D6 = d["six_D"]
    h6 = π -> sum(segcost(π, D6))
    @test h6(_ivec(d, "six_loc0")) == _sc(d, "six_TC0") == 38
    π, TC = twoopt(_ivec(d, "six_loc0"), h6)
    @test π == _ivec(d, "six_loc") == [1, 5, 4, 2, 3, 6, 1]
    @test TC == _sc(d, "six_TC") == 12
    πδ, TCδ = twoopt(_ivec(d, "six_loc0"), D6)              # the delta-cost method, an asymmetric matrix
    @test πδ == [1, 5, 4, 2, 3, 6, 1] && TCδ == 12
end

@testset "oracle: routing, makeRouting2.m Example 1 (6 cities)" begin
    d = _readoracle("routing_52_ex1")
    D = d["D"]
    sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"))
    h = rte -> rteTC(rte, sh, D)
    @test _oclose(sum(h([i, i]) for i in 1:3), _sc(d, "TD_indep"))
    @test rte2loc([1, 2, 2, 1], sh) == _ivec(d, "loc_r1")
    @test _oclose(h([1, 2, 2, 1]), _sc(d, "rteTC_1221"))
    @test _oclose([h([1, 1]), h([2, 2]), h([3, 3])], d["rTD_set1"])
    @test _oclose([h([1, 1, 2, 2]), h([3, 3])], d["rTD_set2"])
    @test _oclose([h([1, 2, 2, 1]), h([3, 3])], d["rTD_set3"])
    @test _oclose([h([1, 2, 1, 2]), h([3, 3])], d["rTD_set4"])
    @test _oclose(h([1, 2, 3, 1, 2, 3]), _sc(d, "rTD_123123"))
    r12, TD12 = mincostinsert(2, [1, 1], h)
    @test r12 == _ivec(d, "r12") && _oclose(TD12, _sc(d, "TD12"))
    r123, TD123 = mincostinsert(3, r12, h)
    @test r123 == _ivec(d, "r123") && _oclose(TD123, _sc(d, "TD123"))
    @test _oclose(h([1, 1]) + h([2, 2]) - TD12, _sc(d, "s12"))
    i, j, s = pairwisesavings(h, sh)
    # the pairs and their savings, in non-increasing order of saving (ties are not an oracle: MATLAB lists
    # pairs by column, Logjam by row)
    @test Set(zip(i, j)) == Set((Int(a), Int(b)) for (a, b) in zip(d["IJS"][:, 1], d["IJS"][:, 2]))
    @test _oclose(s, d["IJS"][:, 3])
    @test issorted(s; rev = true)
    @test savings(h, sh) == _cells(d, "rsav")
end

@testset "oracle: routing, makeRouting2.m Example 2 (8-city TSP as shipments)" begin
    d = _readoracle("routing_52_ex2")
    D = d["D"]
    sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"))
    tr = (b = _ivec(d, "tr_b"), e = _ivec(d, "tr_e"))
    h = rte -> rteTC(rte, sh, D, tr)
    r1 = [1, 1]
    for i in 2:nrow(sh)
        r1 = mincostinsert(i, r1, h)[1]
    end
    # CR 58: of two equal-cost orders the route lists the increasing one, which turns this symmetric tour
    # around; so MATLAB's tour, driven in either direction, as the file's other symmetric-tie oracles do
    tmci, tm = _tour(r1, sh, tr), _tour(_ivec(d, "mci_r1"), sh, tr)
    @test tmci == tm || tmci == reverse(tm)
    @test _oclose(h(r1), _sc(d, "mci_TD1"))
    mloc = [1; _ivec(d, "mci_loc"); 1]; mloc = mloc[vcat(true, diff(mloc) .!= 0)]       # MATLAB's location sequence, runs collapsed
    @test tmci == mloc || tmci == reverse(mloc)
    rs = savings(h, sh)
    ts, tsm = only(_tours(rs, sh, tr)), only(_tours(_cells(d, "sav_r4"), sh, tr))      # CR 58: up to direction
    @test length(rs) == 1 && (ts == tsm || ts == reverse(tsm))
    @test _oclose(sum(h(r) for r in rs), _sc(d, "sav_TD4"))
    # twoopt on a route vector. Matlog's loop reverses r(i:j) over every position, ends included; v0.2.8's
    # `twoopt` kept the first and last element where they were (CR 37) and ended higher: 150.379 against
    # 148.628 from the mincostinsert route, 152.806 against 148.628 from [1:n 1:n], and 152.806 against
    # 150.379 from the seeded random route. Checked in K2b: a copy of Matlog's loop run on Logjam's `rteTC`
    # reproduces all three MATLAB routes and costs. K7a (CR 37, CR 54) flipped all three.
    for (st, rr, tdk) in (("mci_r1", "twoopt_r2", "twoopt_TD2"), ("r0_in", "r0_r5", "r0_TD5"),
                          ("rr_in", "rr_r5", "rr_TD5"))
        r, TC = twoopt(_ivec(d, st), h)
        @test _oclose(TC, _sc(d, tdk)) && _tour(r, sh, tr) == _tour(_ivec(d, rr), sh, tr)
    end
    # (Matlog's insertimprove runs of this example, ii_* and iir_*, stay in the file: Logjam's insertimprove was
    # removed before the release, ruling IN4, and Lecture 5.2 keeps its own.)
end

@testset "oracle: routing, makeRouting2.m Example 3 (51-city TSP as shipments)" begin
    d = _readoracle("routing_52_ex3")
    D = d["D"]
    sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"))
    tr = (b = [1], e = [1])
    h = rte -> rteTC(rte, sh, D, tr)
    rs = savings(h, sh)
    ms = _cells(d, "sav_r")
    @test length(rs) == length(ms) == 1
    @test _tours(rs, sh, tr) == _tours(ms, sh, tr)
    @test _oclose(sum(h(r) for r in rs), sum(d["sav_TD"]))
    # twoopt(savings(...)): from MATLAB's own savings route, v0.2.8's twoopt ended at 452.689 where MATLAB
    # reaches 446.612 (CR 37: the ends were never moved). K7a fixed the neighborhood, and MATLAB's route is
    # a local optimum of it: the same call from MATLAB's final route changes nothing. The exact route that a
    # run from the savings route ends at is NOT an oracle: the first move that gets MATLAB there reverses a
    # stretch of stops at one location, which changes the cost by 0 in exact arithmetic and by about 1e-13
    # in floating point, so whether a strict `<` takes it depends on the order of summation (it is taken
    # with `--check-bounds=yes` and not without, and the cost handle rounded to 9 places, on which the tie
    # is exact, stays at 452.689). Found in K7a; the end result is not reproducible by any rule.
    m2 = _cells(d, "sav2opt_r")
    r, TC = twoopt(ms[1], h)
    @test _isroute(r) && _oclose(TC, h(r)) && TC <= sum(d["sav_TD"])
    # K7b retried the strict oracle (K7a-1) with a route cost that has Matlog's degenerate-location rule (the
    # checked rteTC) and adds its segments in order, as MATLAB's `sum` does (`_inorder_h`): the run ends at
    # MATLAB's COST, 446.612, and at MATLAB's tour up to its direction.
    rd, TCd = twoopt(ms[1], _inorder_h(sh, D, tr))
    @test _isroute(rd) && _oclose(h(rd), sum(d["sav2opt_TD"]))
    # the strict oracle, with the in-order handle: MATLAB's tour, driven in either direction (the distances are
    # symmetric, so a tour and its reverse cost the same and 2-opt's tie between them is one of the ties above)
    t1, t2 = only(_tours([rd], sh, tr)), only(_tours(m2, sh, tr))
    @test t1 == t2 || t1 == reverse(t2)
    rm, TCm = Logjam._twoopt(m2[1], r -> round(h(r); digits = 9))      # the search itself: MATLAB's route is a local optimum of it
    @test rm == m2[1] && _oclose(h(rm), sum(d["sav2opt_TD"]))
end

@testset "oracle: routing, makeRouting3.m vehicle routing on the 30 NC shipments" begin
    d = _readoracle("routing_53_vrp")
    D = d["D"]
    n = size(D, 1) - 1
    q, s = _fvec(d, "q"), _fvec(d, "s")
    tr = (b = [1], e = [1])
    # Example 1, no constraints. Matlog's savings gives a route of 1271.57 and 2-opt takes it to 1151.13.
    # Logjam's savings (the shipment-by-shipment insertion, without Matlog's merge cases: CR 39) ends at
    # 1205.50, and its twoopt from MATLAB's savings route reaches 1181.34 (CR 37). Checked in K2b: the
    # savings LISTS are identical (below), and running Logjam's merge loop on MATLAB's own list still gives
    # 1205.50, so the difference is the merge rule; a copy of Matlog's 2-opt loop with Matlog's rte2loc
    # degenerate-location rule reproduces MATLAB's final route from MATLAB's savings route. K7 flips both.
    sh1 = DataFrame(b = fill(1, n), e = 2:n+1)
    h1 = rte -> rteTC(rte, sh1, D, tr)
    ms = _cells(d, "ex1_sav_r"); m1 = _cells(d, "ex1_r")
    @test length(ms) == length(m1) == 1
    @test _oclose(h1(ms[1]), sum(d["ex1_sav_TD"]))          # Logjam's rteTC prices MATLAB's route the same
    i1, j1, s1 = pairwisesavings(h1, sh1)                   # 434 pairs: the same list as Matlog's IJS
    M = d["ex1_IJS"]
    @test Set(zip(i1, j1)) == Set((Int(a), Int(b)) for (a, b) in zip(M[:, 1], M[:, 2])) && _oclose(s1, M[:, 3])
    rs = savings(h1, sh1)
    # `savings` has Matlog's three merge cases and the must-save test (CR 39) and reproduces MATLAB's routes
    # on makeRouting2.m Examples 1 to 3 (above); here it ends at 1205.50, not MATLAB's 1271.57. The
    # difference is Matlog's `mincostinsert` (K7a-2, found by swapping the insertion inside Logjam's merge
    # code): it skips a delivery directly after a stop at the location of the stop before it, which on a
    # depot route (every pickup at location 1) forbids delivering first, so MATLAB's savings route is the
    # WORSE one (the skip is a defect in mincostinsert.m, ruled 2026-11-21); Logjam's `mincostinsert` (CR 38) has no such skip and `savings` keeps it. So:
    # (a) Logjam's own route is shorter than MATLAB's, and (b) the same merge code run with Matlog's
    # insertion (the internal hook, `_matlog_insert`) returns MATLAB's route exactly.
    @test _isroute(rs[1]) && length(rs) == 1 && h1(rs[1]) < sum(d["ex1_sav_TD"])
    @test isapprox(h1(rs[1]), 1205.50; atol = 0.005)
    rsm = _savings_matlog(h1, sh1)
    @test _tours(rsm, sh1, tr) == _tours(ms, sh1, tr)
    @test isapprox(sum(h1(r) for r in rsm), 1271.57; atol = 0.005) && _oclose(sum(h1(r) for r in rsm), sum(d["ex1_sav_TD"]))
    r, TC = twoopt(ms[1], h1)
    # CR 37 is fixed (K7a). From MATLAB's savings route the plain-cost handle's end route is a summation-order
    # accident: the trajectories part at the reversal of the whole delivery tail, (i, j) = (31, 60), a tie
    # whose floating-point gain is 2.3e-13 (1133.10 without `--check-bounds=yes`, 1151.13 with it, 1181.34
    # with ties exact; found in K7a). K7b retried the strict oracle as originally written (K7a-1): with a route
    # cost that has Matlog's degenerate-location rule (the checked rteTC: a depot route that returns to the
    # depot midway costs Inf, as Matlog's rte2loc gives NaN, so the tail reversal is refused) and adds its
    # segments in order, as MATLAB's `sum` does (`_inorder_h`), the run from MATLAB's savings route ends at
    # MATLAB's route, 1151.13, on Julia 1.12.6 and 1.13, in a plain run and under `--check-bounds=yes`.
    # Without the in-order sum the end route still depends on the platform, as in K7a.
    @test _isroute(r) && _oclose(TC, h1(r)) && TC <= sum(d["ex1_sav_TD"])      # the plain handle: a route, not worse
    rd, TCd = twoopt(ms[1], _inorder_h(sh1, D, tr))
    @test _tours([rd], sh1, tr) == _tours(m1, sh1, tr) && _oclose(TCd, sum(d["ex1_TD"]))      # strict
    rm, TCm = Logjam._twoopt(m1[1], r -> round(h1(r); digits = 9))     # the search itself: MATLAB's route is a local optimum of it
    @test rm == m1[1] && _oclose(h1(rm), sum(d["ex1_TD"]))
    # the TSP procedure on the same matrix: nearest neighbor, then 2-opt of the loc sequence
    loc = _ivec(d, "tsp_nn_loc")
    @test _oclose(sum(segcost(loc, D)), _sc(d, "tsp_nn_TD"))
    π, TC = twoopt(loc, p -> sum(segcost(p, D)))
    @test π == _ivec(d, "tsp_2opt_loc") && _oclose(TC, _sc(d, "tsp_2opt_TD"))
    # Examples 2-4 and 6 need capacity, maxTC and time windows in rteTC: CHECKED_RTETC (CR 42, K7). The
    # weights and cubes of Example 2's routes are computed here from MATLAB's routes with isorigin, which
    # exists, and show the routes respect Kwt = 25 and Kcu = 2750.
    r2 = _cells(d, "ex2_r")
    Wt = [sum(q[r[isorigin(r)]]) for r in r2]
    Cube = [sum((2000 .* q ./ s)[r[isorigin(r)]]) for r in r2]
    @test _oclose(Wt, d["ex2_Wt"]) && _oclose(Cube, d["ex2_Cube"])
    @test all(Wt .<= 25) && all(Cube .<= 2750)
    # Expected call of the checked rteTC: (rte, sh, C, tr) -> (TC, Xflg, out); the route cost handle is its
    # first output; savings and twoopt then run on it. The routes are compared as tours, their costs at 1e-9.
    function vrp_ok(ex, sh, C, tr; wrap = identity)
        # the cost handle adds in order, as MATLAB's does (`_inorder_h`), so every tie falls as it does there
        hi = _inorder_h(sh, C, tr)
        h = rte -> wrap(hi(rte))
        # Matlog's savings returns formed routes only (CR 57); run with Matlog's insertion (the hook, K7a-2),
        # without which Logjam's own insertion (CR 38) ends at other routes on all four of Exs. 2-4 and 6
        rs = filter(r -> length(r) > 2, _savings_matlog(h, sh))
        rs2 = [twoopt(r, h)[1] for r in rs]
        mr = _cells(d, ex * "_r")
        return _tours(rs2, sh, tr) == _tours(mr, sh, tr) && _oclose(sort([h(r) for r in rs2]), sort(_fvec(d, ex * "_TD")))
    end
    sh2 = DataFrame(b = fill(1, n), e = 2:n+1, q = q, s = s)
    trc = (b = [1], e = [1], Kwt = 25.0, Kcu = 2750.0)
    @test vrp_ok("ex2", sh2, D, trc)                                                  # Ex. 2: capacity (CR 42, K7b)
    @test vrp_ok("ex3", sh2, D, trc; wrap = c -> c > _sc(d, "ex3_maxdist") ? Inf : c)   # Ex. 3: myrteTC
    @test vrp_ok("ex4", sh2, D, merge(trc, (maxTC = _sc(d, "ex4_maxTC"),)))           # Ex. 4: tr.maxTC
    sh6 = DataFrame(b = fill(1, n), e = 2:n+1, q = q, s = s, tU = _fvec(d, "ex6_tU"), temin = _fvec(d, "ex6_temin"), temax = _fvec(d, "ex6_temax"))
    let                                                                                 # Ex. 6: time windows
        h = rte -> CHECKED_RTETC(rte, sh6, d["ex6_T"], trc)[1]
        hr = rte -> round(h(rte); digits = 9)                  # ties exact, as in vrp_ok
        rs2 = [twoopt(r, hr)[1] for r in filter(r -> length(r) > 2, _savings_matlog(h, sh6))]
        mr = _cells(d, "ex6_r")
        @test _tours(rs2, sh6, trc) == _tours(mr, sh6, trc) && _oclose(sort([h(r) for r in rs2]), sort(_fvec(d, "ex6_TC")))
    end
end

@testset "oracle: routing, makeRouting4.m Examples 1 and 2 (distance routes and independent minTLC)" begin
    d = _readoracle("routing_54")
    D = d["D"]
    sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"))
    h = rte -> rteTC(rte, sh, D)
    # Example 1: the route Matlog's insertimprove builds is MATLAB's saved r123, priced by Logjam's rteTC
    r123, rX = _ivec(d, "ii_r123"), _ivec(d, "rX_rte")
    @test _oclose(h(r123), _sc(d, "ii_TD123")) && _oclose(h(r123), _sc(d, "ii_rTD"))
    @test _oclose(h(rX), _sc(d, "rX_rTD"))
    # rte2ldmx: the two load mixes of the interleaved route and the single mix of rX (CR 59, K7)
    @test [Int.(vec(x)) for x in rte2ldmx(r123)] == _cells(d, "ii_ld") &&
          [Int.(vec(x)) for x in rte2ldmx(rX)] == _cells(d, "rX_ld")
    # independent TL/LTL: minTLC(sh,tr,[]) with tr = (r 2, Kwt 25, Kcu 2750), LTL ppi default 104.2
    tr = _tr(_sc(d, "tr_r"), _sc(d, "tr_Kwt"), _sc(d, "tr_Kcu"), 102.7 * (_sc(d, "tr_r") / 2))
    mkrows(pre, n) = [(f = d["$(pre)f"][i], s = d["$(pre)s"][i], a = d["$(pre)a"][i], v = d["$(pre)v"][i],
                       h = d["$(pre)h"][i], d = d["$(pre)d"][i]) for i in 1:n]
    rows = mkrows("", 3)
    rs = [minTLC(r, tr, 104.2) for r in rows]
    @test _oclose([r.TLCᵒ for r in rs], d["indep_TLC1"])
    @test [r.isLTL for r in rs] == (vec(d["indep_isLTL"]) .== 1)
    @test _oclose([r.qᵒ for r in rs], d["indep_q1"])          # all three are TL: the closed form
    # Example 2: 30 shipments (the LTL size is an optimizer's argmin and is not compared)
    n30 = size(d["n30_f"], 2)
    rows = mkrows("n30_", n30)
    rs = [minTLC(r, tr, 104.2) for r in rows]
    ref = vec(d["n30_TLC1"])
    @test _oclose([maxpayld(r, tr) for r in rows], d["n30_qmax"])
    @test [r.isLTL for r in rs] == (vec(d["n30_isLTL"]) .== 1)
    # FINDING F3 (new, in no CR or N entry): Matlog's minTLC sizes a TL shipment with
    # mincharge(d, tr.r), passing the rate where the PPI belongs (minTLC.m, line 111), so its minimum charge
    # is (2/102.7)*45 = 0.88 instead of 45 and the size ignores the minimum charge when r*d < 45; the
    # charge itself (transcharge) does use 45. Logjam sizes with max(r*d, MC), the chapter's formula, and
    # reaches a LOWER cost on the short shipments, those with r*d below the minimum charge (shipments 13 and
    # 20, 19.5 and 21.8 mi: 0.25% and 0.013% lower). A departure no plan item names; asserted as one.
    short = [tr.r * r.d < mincharge_tl(tr) for r in rows]
    @test findall(short) == [13, 20]
    @test all(_oclose(rs[i].TLCᵒ, ref[i]) for i in findall(.!short))
    @test all(rs[i].TLCᵒ < ref[i] for i in findall(short))
    @test !any(_oclose(rs[i].TLCᵒ, ref[i]) for i in findall(short))
end

end # oracles

# ==== moved from test/test_routing_v031.jl, its lines 1-515 ====
# test_routing_v031.jl -- added by PCV WP6 of Logjam v0.3.1 (E2): the `verbose` keyword of `twoopt` and
# `mincostinsert`, Matlog's `dodisp` (refactor E, R2). Test spec Sec. 7, with the WP6 brief's correction: Matlog's
# `twoopt.m` and `mincostinsert.m` are not the oracle for the traces, since v0.3.0 ruled that Logjam's insertion
# follows the F24 loop (CR 38) and its 2-opt the lecture's (K7a), so Matlog's traces differ by design. The oracle
# is each lecture's own printing definition, copied below as text with its `.qmd` lines cited and run on the
# lecture's inputs with `stdout` captured. Equality is `==`, on the captured strings (byte for byte) and on the
# returned values; no tolerance is used anywhere in this file. The evidence:
#   1. Lecture 5.1, Code block 15 (`twoopt_prt`) on Ex. 3's tour and arc costs (Code blocks 12 to 14): its 20 lines
#      against `twoopt(π, πTCh; verbose = true)`, the call of Code block 16 with the keyword, and against
#      `twoopt(π, D; verbose = true)`, the matrix method;
#   2. Lecture 5.2, Code block 17 (`mincostinsert_prt`) on Ex. 1's costs (Code blocks 2 and 16): each insertion's
#      lines (4 and 13) against `mincostinsert(...; verbose = true)`, and the whole cell's 21 lines against the
#      same cell with Logjam's call in the place of the lecture's;
#   3. the two definitions against Logjam's on seeded random tours, matrices and routes; the route 2-opt's trace
#      against the routes Lecture 5.2's `twoopt_rte` (test/lecture52_code.jl) costs, in order; the methods for a
#      vector of routes against each route's own trace;
#   4. `verbose = false`, the default: nothing printed, and every public method and kernel `==` to v0.3.0's
#      bodies, copied below as text, on every input above.
# The routing doctests (DOC: every example of src/routetools.jl a `jldoctest`) run in test_doctests.jl.

using Test
using Logjam
using DataFrames
using Random

@isdefined(LECTURE52_CODE) || include(joinpath(@__DIR__, "lecture52_code.jl"))

# ---- v0.3.0's 2-opt and insertion, verbatim (src/routetools.jl at the v0.3.0 tag fd0f1f3, which e1f745b left
# unchanged: twoopt :747-750, _twoopt :753, _twoopt_out :757-760, the methods for a vector of routes :852-859,
# _twoopt_route :872-890, _twoopt_tour :893-915, twoopt(π, C) :956-990, mincostinsert :1045-1048, _mincostinsert
# :1051-1066). The helpers they call are Logjam's own, unchanged since that tag. The reference for "returns
# exactly what it returned": each is compared with the current function by `==`. ----
module RtV030
using Logjam: segcost, _loaded_throughout, _isroutevec, _order_ties, _narrow

function twoopt(r, rTCh)
    rte, TC = _twoopt_out(r, rTCh)
    return (rte = rte, TC = TC)
end

_twoopt(r, rTCh) = _isroutevec(r) ? _twoopt_route(r, rTCh) : _twoopt_tour(r, rTCh)

function _twoopt_out(r, rTCh)
    rte, TC = _twoopt(r, rTCh)
    return (_isroutevec(r) ? _order_ties(rte, rTCh) : rte), TC
end

function twoopt(R::AbstractVector{<:AbstractVector{<:Integer}}, rTCh)
    res = [_twoopt_out(r, rTCh) for r in R]
    return (rte = map(first, res), TC = _narrow(map(x -> x[2], res)))
end
function twoopt(R::AbstractVector{<:AbstractVector{<:Integer}}, C::AbstractMatrix)
    res = [twoopt(π, C) for π in R]
    return (rte = map(first, res), TC = _narrow(map(x -> x[2], res)))
end

function _twoopt_route(r, rTCh)
    m = length(r)
    rᵒ, TCᵒ = copy(r), rTCh(r)
    done = false
    while !done
        done = true
        for i = 1:m-1, j = i+1:m
            r′ = vcat(rᵒ[1:i-1], reverse(rᵒ[i:j]), rᵒ[j+1:end])
            _loaded_throughout(r′) || continue
            TC = rTCh(r′)
            if TC < TCᵒ
                rᵒ, TCᵒ = r′, TC
                done = false
                break
            end
        end
    end
    return rᵒ, TCᵒ
end

function _twoopt_tour(r, rTCh)
    rᵒ, TCᵒ = copy(r), rTCh(r)
    done = false
    while !done
        done = true
        for i = 1:length(r)-2
            for j = i+2:min(length(r)-1, length(r)+i-3)
                r′ = vcat(r[1:i], reverse(r[i+1:j]), r[j+1:end])
                TC = rTCh(r′)
                if TC < TCᵒ
                    rᵒ, TCᵒ = r′, TC
                    done = false
                    break
                end
            end
            if done == false
                break
            end
        end
        r = copy(rᵒ)
    end
    return rᵒ, TCᵒ
end

function twoopt(π::AbstractVector, C::AbstractMatrix)
    _isroutevec(π) && throw(ArgumentError(
        "twoopt(π, C) takes a closed tour; a route vector's cost is not a sum of arc costs, so use twoopt(r, rTCh)"))
    n = length(π)
    πᵒ = collect(π)
    sym = all(C[i, j] == C[j, i] for j in axes(C, 2) for i in 1:j)
    F = zeros(n)                  # F[k + 1]: cost of the forward arcs 1..k; B[k + 1] the backward ones
    B = zeros(n)
    done = false
    while !done
        done = true
        if !sym
            for k in 1:n-1
                F[k+1] = F[k] + C[πᵒ[k], πᵒ[k+1]]
                B[k+1] = B[k] + C[πᵒ[k+1], πᵒ[k]]
            end
        end
        for i = 1:n-2
            for j = i+2:min(n-1, n+i-3)
                a, b, c, d = πᵒ[i], πᵒ[i+1], πᵒ[j], πᵒ[j+1]
                Δ = C[a, c] + C[b, d] - C[a, b] - C[c, d]
                if !sym             # the stretch's arcs i+1 .. j-1 run the other way
                    Δ += (B[j] - B[i+1]) - (F[j] - F[i+1])
                end
                if Δ < 0
                    reverse!(πᵒ, i + 1, j)
                    done = false
                    break
                end
            end
            done || break
        end
    end
    return (rte = πᵒ, TC = sum(segcost(πᵒ, C)))
end

function mincostinsert(idx, rte::AbstractVector, rteTCh)
    rte′, TC = _mincostinsert(idx, rte, rteTCh)
    return (rte = _order_ties(rte′, rteTCh), TC = TC)
end

function _mincostinsert(idx, rte, rteTCh)
    if isempty(rte)
        return [idx, idx], rteTCh([idx, idx])
    end
    rteᵒ, TCᵒ = copy(rte), Inf
    for i = 1:length(rte)
        for j = max(2,i):length(rte) + 1
            rte′ = vcat(rte[1:i-1], idx, rte[i:j-1], idx, rte[j:end])
            TC = rteTCh(rte′)
            if TC < TCᵒ
                rteᵒ, TCᵒ = rte′, TC
            end
        end
    end
    return rteᵒ, TCᵒ
end
end # module RtV030

# ---- Lecture 5.1, Ex. 3 (5-routing/5-rte-1.qmd), verbatim: the tour of Code block 12 (:1130), the arc costs of
# Code block 13 (:1607-1613), the tour's cost of Code block 14 (:1621), and the printing 2-opt of Code block 15
# (:1632-1658), whose call (:1660) the test makes. ----
const E2_L51_INPUTS = raw"""
π = [1:6; 1]
D = [
     0     8     6     9     1     5
     3     0     1     5     4     2
     9     2     0     3     1     1
     8     2     1     0    10     6
     6     7    10     1     0    10
     6     2     5     2     1     0]
πTCh(π) = sum(segcost(π, D))
"""

const E2_L51_TWOOPT_PRT = raw"""
function twoopt_prt(π, πTCh)
    πᵒ, TCᵒ = copy(π), πTCh(π)
    println("*", TCᵒ, ": ", πᵒ)
    done = false
    while !done
        done = true
        for i = 1:length(π)-2
            for j = i+2:min(length(π)-1, length(π)+i-3)
                π′ = vcat(π[1:i], reverse(π[i+1:j]), π[j+1:end])
                TC = πTCh(π′)
                if TC < TCᵒ
                    πᵒ, TCᵒ = π′, TC
                    println("*", TCᵒ, ": ", πᵒ)
                    done = false
                    break
                else
                    println(" ", TC, ": ", π′)
                end
            end
            if done == false
                break
            end
        end
        π = copy(πᵒ)
    end
    return πᵒ, TCᵒ
end
"""

# ---- Lecture 5.2, Ex. 1 (5-routing/5-rte-2.qmd), verbatim: the network and shipments of Code block 2
# (:415-423), the hidden cell's check of its costs (:431-436), Ex. 1's costs again in Code block 16 (:990-992),
# and Code block 17, the printing insertion (:1004-1017) and its two calls (:1019-1026). ----
const E2_L52_SETUP = raw"""
using Graphs, SimpleWeightedGraphs
i = [1, 3, 5, 1, 4, 1, 6]              # one end of each road
j = [2, 4, 6, 3, 2, 5, 2]              # its other end
w = [300, 250, 275, 30, 30, 60, 60]    # its miles
g = SimpleWeightedGraph(i, j, w)       # a network of two-way roads
D, _ = shortestpaths(g, weights(g), nv(g))  # from every location  # <1>
D = Int.(D)                            # whole miles
sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6])  # origin, destination
D
@assert D == [  0  300   30  280   60  335
              300    0  280   30  335   60
               30  280    0  250   90  340
              280   30  250    0  340   90
               60  335   90  340    0  275
              335   60  340   90  275    0]
D1 = Int.(shortestpaths(g, weights(g), nv(g))[1])  # g of Code block 2
sh1 = DataFrame(b = [1, 3, 5], e = [2, 4, 6])
rTD1h(rte) = rteTC(rte, sh1, D1);
"""

const E2_L52_MINCOSTINSERT_PRT = raw"""
function mincostinsert_prt(idx, rte, rteTCh)
    rteᵒ, TCᵒ = copy(rte), Inf
    for i = 1:length(rte)
        for j = max(2,i):length(rte) + 1
            rte′ = vcat(rte[1:i-1], idx, rte[i:j-1], idx, rte[j:end])
            TC = rteTCh(rte′)
            println(i,",",j,": ",rte′, " = ", TC)
            if TC < TCᵒ
                rteᵒ, TCᵒ = rte′, TC
            end
        end
    end
    return rteᵒ, TCᵒ
end
"""

const E2_L52_CALLS = raw"""
# insert shmt 2 route into shmt 1 route
rte12, TD12 = mincostinsert_prt(2, [1, 1], rTD1h)
@show rte12
@show TD12
# insert shmt 3 route into shmt 1&2 route
rte123, TD123 = mincostinsert_prt(3, rte12, rTD1h)
@show rte123
@show TD123;
"""

# The lectures' modules: `using Logjam` (and 5.2's `using DataFrames`, its setup cell :77), then the text. Code
# block 2 and 16's three-argument `shortestpaths` is deprecated; its warning (printed only under --depwarn=yes,
# on stderr) is silenced, and nothing the lecture prints is touched.
const E2_L51 = Module(:E2Lecture51)
Core.eval(E2_L51, :(using Logjam))
include_string(E2_L51, E2_L51_INPUTS, "5-rte-1.qmd")
include_string(E2_L51, E2_L51_TWOOPT_PRT, "5-rte-1.qmd")

const E2_L52 = Module(:E2Lecture52)
Core.eval(E2_L52, :(using Logjam, DataFrames))
Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
    include_string(E2_L52, E2_L52_SETUP, "5-rte-2.qmd")
end
include_string(E2_L52, E2_L52_MINCOSTINSERT_PRT, "5-rte-2.qmd")

# f's value and everything it printed to stdout, byte for byte (an IOStream, as test_location_v031.jl captures)
function _e2_out(f)
    mktemp() do path, io
        val = redirect_stdout(f, io)
        flush(io); close(io)
        return val, read(path, String)
    end
end
_e2_lines(s) = count(==('\n'), s)

# the lectures' printing functions and Logjam's, each called in the latest world (the definitions above are new)
_e2_twoopt_prt(π, h) = _e2_out(() -> Base.invokelatest(getfield(E2_L51, :twoopt_prt), π, h))
_e2_mci_prt(k, r, h) = _e2_out(() -> Base.invokelatest(getfield(E2_L52, :mincostinsert_prt), k, r, h))
_e2_lj(f, args...; kw...) = _e2_out(() -> Base.invokelatest(f, args...; kw...))

@testset "E2: twoopt(...; verbose = true) prints Lecture 5.1's Code block 15, byte for byte" begin
    π0 = getfield(E2_L51, :π)
    h = getfield(E2_L51, :πTCh)
    D = getfield(E2_L51, :D)
    @test π0 == [1, 2, 3, 4, 5, 6, 1]
    lec, lec_out = _e2_twoopt_prt(π0, h)
    @test _e2_lines(lec_out) == 20                                  # @tbl-twoopt-trace's rows
    @test startswith(lec_out, "*38: [1, 2, 3, 4, 5, 6, 1]\n")
    # the cost-handle method, as Code block 16 calls it, with the keyword
    lj, lj_out = _e2_lj(twoopt, π0, h; verbose = true)
    @test lj_out == lec_out
    @test (lj.rte, lj.TC) == lec
    # the matrix method: the delta search, each tour considered costed as the handle costs it, for the trace only
    ljC, ljC_out = _e2_lj(twoopt, π0, D; verbose = true)
    @test ljC_out == lec_out
    @test (ljC.rte, ljC.TC) == lec
    # a vector of one tour: the same lines, under each method
    @test _e2_lj(twoopt, [π0], h; verbose = true)[2] == lec_out
    @test _e2_lj(twoopt, [π0], D; verbose = true)[2] == lec_out
    @test π0 == [1, 2, 3, 4, 5, 6, 1]                                # not modified
end

@testset "E2: mincostinsert(...; verbose = true) prints Lecture 5.2's Code block 17, byte for byte" begin
    m = E2_L52
    h = getfield(m, :rTD1h)
    @test getfield(m, :D1) == getfield(m, :D)
    # the first insertion, shipment 2 into shipment 1's route: four routes
    lec1, lec1_out = _e2_mci_prt(2, [1, 1], h)
    @test _e2_lines(lec1_out) == 4
    lj1, lj1_out = _e2_lj(mincostinsert, 2, [1, 1], h; verbose = true)
    @test lj1_out == lec1_out
    @test (lj1.rte, lj1.TC) == lec1
    # the second, shipment 3 into the route the first made: thirteen routes
    lec2, lec2_out = _e2_mci_prt(3, lec1[1], h)
    @test _e2_lines(lec2_out) == 13
    lj2, lj2_out = _e2_lj(mincostinsert, 3, lj1.rte, h; verbose = true)
    @test lj2_out == lec2_out
    @test (lj2.rte, lj2.TC) == lec2
    # the whole cell, as the lecture runs it, and the same cell with Logjam's call in the lecture's place (the
    # call the lecture can make at the re-pin): the 17 routes and the four @show lines
    lj_calls = replace(E2_L52_CALLS,
        "mincostinsert_prt(2, [1, 1], rTD1h)" => "mincostinsert(2, [1, 1], rTD1h; verbose = true)",
        "mincostinsert_prt(3, rte12, rTD1h)" => "mincostinsert(3, rte12, rTD1h; verbose = true)")
    @test !occursin("mincostinsert_prt", lj_calls)
    cell_lec = _e2_out(() -> include_string(m, E2_L52_CALLS, "5-rte-2.qmd"))[2]
    cell_lj = _e2_out(() -> include_string(m, lj_calls, "5-rte-2.qmd"))[2]
    @test _e2_lines(cell_lec) == 21
    @test cell_lj == cell_lec
    @test endswith(cell_lec, "rte123 = [3, 1, 2, 2, 1, 3]\nTD123 = 430\n")
end

# ---- seeded inputs beyond the lectures': tours on integer (asymmetric and symmetric) and real matrices, routes
# of shipments on real distances, and insertions into them ----
function _e2_tours()
    rng = Xoshiro(6101)
    cases = Tuple{Vector{Int},Matrix}[]
    for k in 1:24
        n = rand(rng, 4:11)
        C = k % 3 == 0 ? rand(rng, n, n) : rand(rng, 0:60, n, n)
        k % 4 == 1 && (C = C + C')                                    # some symmetric
        for i in 1:n
            C[i, i] = 0
        end
        p = randperm(rng, n)
        push!(cases, ([p; p[1]], C))
    end
    return cases
end
function _e2_routes()
    rng = Xoshiro(6102)
    cases = Tuple{Vector{Int},Function,DataFrame,Matrix{Float64}}[]
    for k in 1:18
        m = rand(rng, 2:6)
        P = 100 .* rand(rng, 2m, 2)
        D = [hypot(P[a, 1] - P[b, 1], P[a, 2] - P[b, 2]) for a in 1:2m, b in 1:2m]
        sh = DataFrame(b = 1:m, e = m+1:2m)
        r = [randperm(rng, m); randperm(rng, m)]                     # every shipment loaded, then unloaded
        h = rte -> rteTC(rte, sh, D)
        push!(cases, (r, h, sh, D))
    end
    return cases
end
const E2_TOURS = _e2_tours()
const E2_ROUTES = _e2_routes()

@testset "E2: the tour traces equal Lecture 5.1's twoopt_prt on seeded tours" begin
    for (t, C) in E2_TOURS
        h = π -> sum(segcost(π, C))
        lec, lec_out = _e2_twoopt_prt(t, h)
        lj, lj_out = _e2_lj(twoopt, t, h; verbose = true)
        @test lj_out == lec_out
        @test (lj.rte, lj.TC) == lec
        if eltype(C) <: Integer                     # the delta decides as the whole cost does in exact arithmetic
            ljC, ljC_out = _e2_lj(twoopt, t, C; verbose = true)
            @test ljC_out == lec_out
            @test (ljC.rte, ljC.TC) == lec
        end
    end
end

@testset "E2: the insertion traces equal Lecture 5.2's mincostinsert_prt on seeded routes" begin
    for (r, h, sh, D) in E2_ROUTES
        m = nrow(sh)
        # shipment m left out of the route, then inserted (the route of the others, unloaded in its own order)
        r0 = filter(!=(m), r)
        isempty(r0) && continue
        lec, lec_out = _e2_mci_prt(m, r0, h)
        @test _e2_lines(lec_out) == length(r0) * (length(r0) + 3) ÷ 2 - 1    # 5.2's Eq. insert-count
        lj, lj_out = _e2_lj(mincostinsert, m, r0, h; verbose = true)
        @test lj_out == lec_out
        @test lj.TC == lec[2]
        @test lj.rte == Logjam._order_ties(lec[1], h)                       # CR 58 after the loop, as by default
    end
    # into an empty route the shipment goes as [k, k], outside the loops; the lecture's function prints nothing
    # for an empty route, and neither does Logjam's
    h = rte -> rteTC(rte, DataFrame(b = [1, 3], e = [2, 4]), [0 5 7 9; 5 0 4 6; 7 4 0 3; 9 6 3 0])
    @test _e2_mci_prt(1, Int[], h)[2] == ""
    v, out = _e2_lj(mincostinsert, 1, Int[], h; verbose = true)
    @test out == ""
    @test v == RtV030.mincostinsert(1, Int[], h)
end

@testset "E2: the route 2-opt's trace is every route Lecture 5.2's twoopt_rte costs, in order" begin
    L52 = lecture52_module(:E2Lecture52Rte)
    for (r, h, sh, D) in E2_ROUTES
        seen = Tuple{Vector{Int},Float64}[]
        rec = rte -> (c = h(rte); push!(seen, (copy(rte), c)); c)
        lecture52_call(L52, :twoopt_rte, r, rec)
        # the lines twoopt_prt's rule makes of those evaluations: the first is the start, and a later one is starred
        # when its cost is below the best so far
        io = IOBuffer()
        best = Inf
        for (k, (rte, c)) in enumerate(seen)
            star = k == 1 || c < best
            star && (best = c)
            println(io, star ? "*" : " ", c, ": ", rte)
        end
        expected = String(take!(io))
        lj, lj_out = _e2_lj(twoopt, r, h; verbose = true)
        @test lj_out == expected
        @test _e2_lines(lj_out) == length(seen)
        # its last starred line is the search's result (the export then orders ties, CR 58)
        last_star = filter(l -> startswith(l, "*"), split(chomp(lj_out), '\n'))[end]
        kr, kTC = Logjam._twoopt(r, h)
        @test last_star == string("*", kTC, ": ", kr)
        @test lj == twoopt(r, h)
    end
end

@testset "E2: a vector of routes prints each route's trace in turn" begin
    # routes: each case's route and its reverse (a route too: the last unloading is loaded first), on its handle
    for (r, h, _, _) in E2_ROUTES[1:6]
        R = [r, reverse(r)]
        v, out = _e2_lj(twoopt, R, h; verbose = true)
        @test out == join(_e2_lj(twoopt, x, h; verbose = true)[2] for x in R)
        @test v == twoopt(R, h)
    end
    # tours, under the cost handle and the matrix: three tours of the first integer case's nodes
    t1, C1 = first((t, C) for (t, C) in E2_TOURS if eltype(C) <: Integer)
    p = randperm(Xoshiro(6103), size(C1, 1))
    T = [t1, reverse(t1), [p; p[1]]]
    h1 = π -> sum(segcost(π, C1))
    for f in (h1, C1)
        v, out = _e2_lj(twoopt, T, f; verbose = true)
        @test out == join(_e2_lj(twoopt, t, f; verbose = true)[2] for t in T)
        @test v == twoopt(T, f)
    end
    # Lecture 5.3 Ex. 1(c) (the docstring's example): the savings routes under a capacity of 15, some costs Inf
    C = [ 0 40 48 38 33 48
         40  0 87 46 65 75
         48 87  0 67 41 47
         38 46 67  0 70 34
         33 65 41 70  0 69
         48 75 47 34 69  0]
    sh53 = DataFrame(b = ones(Int, 5), e = 2:6, q = [8, 5, 4, 7, 6])
    hq = rte -> (TC = rteTC(rte, sh53, C, (b = 1, e = 1)); sum(sh53.q[unique(rte)]) <= 15 ? TC : Inf)
    R53 = savings(hq, sh53)
    v, out = _e2_lj(twoopt, R53, hq; verbose = true)
    @test out == join(_e2_lj(twoopt, r, hq; verbose = true)[2] for r in R53)
    @test v == twoopt(R53, hq)
    @test v.TC == [167, 138]
end

@testset "E2: verbose = false, the default, prints nothing and returns what v0.3.0 returned" begin
    π0, h51, D51 = getfield(E2_L51, :π), getfield(E2_L51, :πTCh), getfield(E2_L51, :D)
    h52 = getfield(E2_L52, :rTD1h)
    calls = Any[]                                   # (Logjam's function, v0.3.0's, the arguments)
    push!(calls, (twoopt, RtV030.twoopt, (π0, h51)), (twoopt, RtV030.twoopt, (π0, D51)),
          (twoopt, RtV030.twoopt, ([π0, π0], h51)), (twoopt, RtV030.twoopt, ([π0], D51)),
          (twoopt, RtV030.twoopt, ([1, 2, 3, 1, 2, 3], h52)), (twoopt, RtV030.twoopt, ([1, 1, 2, 2, 3, 3], h52)),
          (mincostinsert, RtV030.mincostinsert, (2, [1, 1], h52)),
          (mincostinsert, RtV030.mincostinsert, (3, [1, 2, 2, 1], h52)),
          (mincostinsert, RtV030.mincostinsert, (3, Int[], h52)))
    for (t, C) in E2_TOURS
        push!(calls, (twoopt, RtV030.twoopt, (t, π -> sum(segcost(π, C)))), (twoopt, RtV030.twoopt, (t, C)))
    end
    for (r, h, sh, D) in E2_ROUTES
        m = nrow(sh)
        push!(calls, (twoopt, RtV030.twoopt, (r, h)), (twoopt, RtV030.twoopt, ([r, reverse(r)], h)),
              (mincostinsert, RtV030.mincostinsert, (m, filter(!=(m), r), h)))
    end
    C53 = [0 40 48 38 33 48; 40 0 87 46 65 75; 48 87 0 67 41 47; 38 46 67 0 70 34; 33 65 41 70 0 69; 48 75 47 34 69 0]
    sh53 = DataFrame(b = ones(Int, 5), e = 2:6, q = [8, 5, 4, 7, 6])
    hq = rte -> (TC = rteTC(rte, sh53, C53, (b = 1, e = 1)); sum(sh53.q[unique(rte)]) <= 15 ? TC : Inf)
    push!(calls, (twoopt, RtV030.twoopt, (savings(hq, sh53), hq)), (mincostinsert, RtV030.mincostinsert, (5, [1, 4, 1, 4], hq)))
    for (f, f030, args) in calls
        ref = Base.invokelatest(f030, args...)
        v0, out0 = _e2_lj(f, args...)                            # the default
        vf, outf = _e2_lj(f, args...; verbose = false)
        vt, _ = _e2_lj(f, args...; verbose = true)               # printing changes nothing computed
        @test out0 == "" && outf == ""
        @test v0 == ref && vf == ref && vt == ref
    end
    # the kernels that savings, pairwisesavings and the insertion hook run, called as they call them
    for (r, h, sh, D) in E2_ROUTES
        m = nrow(sh)
        @test _e2_out(() -> Logjam._twoopt(r, h)) == (RtV030._twoopt(r, h), "")
        @test _e2_out(() -> Logjam._twoopt_route(r, h)) == (RtV030._twoopt_route(r, h), "")
        @test _e2_out(() -> Logjam._mincostinsert(m, filter(!=(m), r), h)) == (RtV030._mincostinsert(m, filter(!=(m), r), h), "")
    end
    for (t, C) in E2_TOURS
        h = π -> sum(segcost(π, C))
        @test _e2_out(() -> Logjam._twoopt_tour(t, h)) == (RtV030._twoopt_tour(t, h), "")
    end
    # the procedures built on the kernels print nothing
    sh52 = getfield(E2_L52, :sh1)
    @test _e2_out(() -> savings(h52, sh52))[2] == ""
    @test _e2_out(() -> pairwisesavings(h52, sh52))[2] == ""
end
