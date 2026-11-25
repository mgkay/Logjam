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
