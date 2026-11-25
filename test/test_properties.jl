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

const _RTOL = 1e-9
_close(a, b) = isapprox(a, b; rtol = _RTOL, atol = 1e-9)

# a function that prints (ala, ufl) is run with its output discarded
_mute_stdout(f) = redirect_stdout(f, devnull)

# cost of an open-site set y: fixed costs plus each EF served by its cheapest open site
_ufl_cost(k, C, y) = sum(k[y]) + sum(minimum(C[y, :], dims = 1))

@testset "properties" begin

# ---------------------------------------------------------------------------------------------
@testset "UFL family: returned cost = cost recomputed from the returned solution" begin
    rng = Random.Xoshiro(20261119)
    allok = Dict(f => true for f in (:add, :drop, :xchg, :ufl, :pmedian))
    sorted = Dict(f => true for f in (:add, :drop, :xchg, :ufl, :pmedian))
    addmut = xchgmut = dropmut = locopt = true
    for _ in 1:25
        n, m = rand(rng, 4:7), rand(rng, 4:8)
        C = float.(rand(rng, 1:40, n, m))
        k = float.(rand(rng, 20:120, n))

        ya, TCa, Wa = ufladd(k, C)
        allok[:add] &= _close(TCa, _ufl_cost(k, C, ya)) && _close(TCa, sum(k[ya]) + sum(Wa .* C))
        sorted[:add] &= issorted(ya)

        yd, TCd, Wd = ufldrop(k, C)
        allok[:drop] &= _close(TCd, _ufl_cost(k, C, yd)) && _close(TCd, sum(k[yd]) + sum(Wd .* C))
        sorted[:drop] &= issorted(yd)

        y0 = sort(randperm(rng, n)[1:rand(rng, 2:n)])
        ycopy = copy(y0)
        yx, TCx, Wx = uflxchg(k, C, y0)
        allok[:xchg] &= _close(TCx, _ufl_cost(k, C, yx)) && _close(TCx, sum(k[yx]) + sum(Wx .* C))
        sorted[:xchg] &= issorted(yx)
        xchgmut &= (y0 == ycopy)
        # local optimality (N24's documented exception: no swap is tried with one open site)
        if length(yx) > 1
            locopt &= !any(_ufl_cost(k, C, replace(yx, i => j)) < TCx - 1e-9
                           for i in yx for j in setdiff(1:n, yx))
        end
        # never worse than the start
        allok[:xchg] &= TCx <= _ufl_cost(k, C, y0) + 1e-9

        # ADD from a caller's set; the set must come back untouched
        ys = [rand(rng, 1:n)]
        yscopy = copy(ys)
        ufladd(k, C; y = ys)
        addmut &= (ys == yscopy)
        # DROP from a caller's set
        yd0 = collect(1:n); yd0copy = copy(yd0)
        ufldrop(k, C; y = yd0)
        dropmut &= (yd0 == yd0copy)

        yu, TCu, Wu = _mute_stdout(() -> ufl(k, C; verbose = false))
        allok[:ufl] &= _close(TCu, _ufl_cost(k, C, yu)) && _close(TCu, sum(k[yu]) + sum(Wu .* C))
        sorted[:ufl] &= issorted(yu)

        p = rand(rng, 1:n)
        yp, TCp, Wp = pmedian(p, C; verbose = false)
        allok[:pmedian] &= length(yp) == p && _close(TCp, sum(minimum(C[yp, :], dims = 1))) &&
                           _close(TCp, sum(Wp .* C))
        sorted[:pmedian] &= issorted(yp)
    end
    @test allok[:add]
    @test allok[:drop]
    @test allok[:xchg]
    @test allok[:ufl]
    @test allok[:pmedian]
    @test sorted[:drop]                       # ufldrop's setdiff happens to sort
    @test dropmut
    @test xchgmut
    # index sets returned sorted: CR 6 (decided 2026-08-29), fixed in K3 (pmedian sorts because uflxchg does)
    @test sorted[:add]
    @test sorted[:xchg]
    @test sorted[:ufl]
    @test sorted[:pmedian]
    # ufladd mutated the caller's y: CR 5, fixed in K3
    @test addmut
    # FINDING F1 = N32 (found by this test): v0.2.8's uflxchg moved elements of y to the end (swap!/revert!)
    # while `for i′ in y` was iterating over y, so candidate swaps were skipped and the returned set was
    # not a 1-swap local optimum, which its docstring promises. Fixed in K3 (scan the set as it stands).
    @test locopt
end

# ---------------------------------------------------------------------------------------------
@testset "ala: returned cost = cost of the returned X; start not mutated" begin
    rng = Random.Xoshiro(754)
    ok = true
    nomut = true
    for _ in 1:12
        m = rand(rng, 6:14)
        P = rand(rng, m, 2) .* 40
        w = rand(rng, m) .* 20 .+ 1
        n = rand(rng, 2:3)
        X0 = randX(P, n)
        X0copy = copy(X0)
        X, TC, W = _mute_stdout(() -> ala(X0, w, P; dist = 2))
        D = dists(X, P, 2)
        ok &= _close(TC, sum(W .* D))
        nomut &= (X0 == X0copy)
    end
    @test ok                                   # TC is computed at the X returned (true on main since PR #13)
    @test nomut
end

# ---------------------------------------------------------------------------------------------
@testset "minTLC: returned cost = totlogcost at the returned size and mode" begin
    rng = Random.Xoshiro(361)
    ok = true
    tr = (r = 2.00 * 131.0 / 102.7, Kwt = 25.0, Kcu = 2750.0, ppi = 131.0)
    for _ in 1:12
        sh = (f = rand(rng, 5:60) * 1.0, s = rand(rng, 5:30) * 1.0, a = 0.5 + rand(rng) / 2,
              v = rand(rng, 500:30000) * 1.0, h = 0.1 + rand(rng) / 4, d = rand(rng, 80:900) * 1.0)
        for (t, p) in ((tr, nothing), (nothing, 177.4), (tr, 177.4))
            res = minTLC(sh, t, p)
            q = res.qᵒ
            c = res.isLTL ? charge_ltl(q, sh; ppi = p) : charge_tl(q, sh, t)
            ok &= _close(res.TLCᵒ, totlogcost(q, c, sh))
        end
    end
    @test ok
end

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

# ---------------------------------------------------------------------------------------------
@testset "metric axioms: d1, d2, dists (p = 1, 2, 3, Inf), dgc" begin
    rng = Random.Xoshiro(97)
    ok = Dict(:d1 => true, :d2 => true, :dists => true, :dgc => true)
    for _ in 1:30
        x, y, z = rand(rng, 3), rand(rng, 3), rand(rng, 3)
        for (name, d) in ((:d1, d1), (:d2, d2))
            ok[name] &= d(x, x) == 0 && d(x, y) >= 0 && d(x, y) == d(y, x) &&
                        d(x, z) <= d(x, y) + d(y, z) + 1e-12
        end
        X = rand(rng, 4, 2) .* 10
        for p in (1, 2, 3.0, Inf)
            D = dists(X, X, p)
            ok[:dists] &= all(D[i, i] == 0 for i in 1:4) && all(D .>= 0) && D == D' &&
                          all(D[i, k] <= D[i, j] + D[j, k] + 1e-12 for i in 1:4, j in 1:4, k in 1:4)
        end
        for unit in (:mi, :km, :rad)
            pts = [[-125 + 60rand(rng), 25 + 24rand(rng)] for _ in 1:3]
            a, b, c = pts
            ok[:dgc] &= dgc(a, a; unit) == 0 && dgc(a, b; unit) >= 0 &&
                        _close(dgc(a, b; unit), dgc(b, a; unit)) &&
                        dgc(a, c; unit) <= dgc(a, b; unit) + dgc(b, c; unit) + 1e-9
        end
    end
    @test ok[:d1]
    @test ok[:d2]
    @test ok[:dists]
    @test ok[:dgc]
end

# ---------------------------------------------------------------------------------------------
@testset "zero in, zero out" begin
    @test charge_tl(0.0, 8.0, 500.0) == 0.0
    @test charge_ltl(0.5, 8.0, 0.0) == 0.0              # mincharge_ltl(0) = 0
    @test charge_ltl(0.0, 8.0, 0.0) == 0.0
    # N4: charge_ltl at q = 0 charged the LTL minimum at v0.2.8 (fixed in K6)
    @test charge_ltl(0.0, 10.0, 500.0) == 0.0
    # CR 15: charge_tl and minTLC at d = 0 charged the TL minimum at v0.2.8 (fixed in K6)
    @test charge_tl(10.0, 8.0, 0.0) == 0.0
    sh0 = (f = 20.0, s = 8.0, a = 0.5, v = 1000.0, h = 0.25, d = 0.0)
    tr = (r = 2.0, Kwt = 25.0, Kcu = 2750.0, ppi = 102.7)
    @test isapprox(minTLC(sh0, tr).TLCᵒ, 0.0; atol = 1e-9)
    # totlogcost: q = 0 with a zero charge costs nothing; q = 0 with a positive charge is Inf (N31, K6)
    @test totlogcost(0.0, 0.0, 100.0, 0.5, 1000.0, 0.25) == 0.0
    @test totlogcost(0.0, 100.0, 100.0, 0.5, 1000.0, 0.25) == Inf
end

end  # properties
