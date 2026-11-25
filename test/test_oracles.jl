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

include(joinpath(@__DIR__, "oracle_helpers.jl"))   # _readoracle, _oclose, _try, _has, _transcharge, ...

# Matlog's rteTC (capacity, maxTC, time windows; returns TC, Xflg, out; CR 42, MakePlan D6/D9) is
# `rteTC(rte, sh, C, tr; full = true)` (K7b: one route cost function, his ruling of 2026-11-20).
# Call: CHECKED_RTETC(rte, sh, C, tr) -> (TC, Xflg, out) with `sh`, `tr` as below.
const CHECKED_RTETC = (rte, sh, C, tr) -> Tuple(Logjam.rteTC(rte, sh, C, tr; full = true))

@testset "oracles" begin

# =============================================================================================
@testset "oracle: UFL family, Example 8.8 (Matlog help text)" begin
    d = _readoracle("ufl_ex88")
    k, C = _fvec(d, "k"), d["C"]
    cmp(pre, y, TC, W) = (set = sort(y) == _ivec(d, pre * "_y"),
                          order = y == _ivec(d, pre * "_y"),
                          TC = _oclose(TC, _sc(d, pre * "_TC")),
                          X = (Matrix(W) .> 0) == (d[pre * "_X"] .> 0))
    r = cmp("ufl", _oquiet(() -> ufl(k, C; verbose = false))...)
    @test r.set; @test r.TC; @test r.X; @test r.order
    r = cmp("ufladd", ufladd(k, C)...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("ufladd45", ufladd(k, C; y = [4, 5])...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("ufldrop", ufldrop(k, C)...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("ufldrop36", ufldrop(k, C; y = collect(3:6))...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("uflxchg", uflxchg(k, C, _ivec(d, "xchg_y0"))...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("pmedian2", pmedian(2, C; verbose = false)...)
    @test r.set; @test r.TC; @test r.X
end

# =============================================================================================
@testset "oracle: UFL family, 12 seeded random instances (rng(20261119) in MATLAB, inputs saved)" begin
    d = _readoracle("ufl_random")
    ninst = Int(_sc(d, "ninst"))
    fns = (:ufl, :ufladd, :ufldrop, :uflxchg, :pmedian)
    # per function and per quantity, did every instance agree?
    res = Dict((f, q) => Bool[] for f in fns for q in (:set, :order, :TC, :X))
    bad = Dict((f, q) => Int[] for f in fns for q in (:set, :order, :TC, :X))
    for i in 1:ninst
        k, C, y0 = _fvec(d, "k_$i"), d["C_$i"], _ivec(d, "y0_$i")
        p = Int(_sc(d, "p_$i"))
        out = Dict(:ufl => _oquiet(() -> ufl(k, C; verbose = false)),
                   :ufladd => ufladd(k, C), :ufldrop => ufldrop(k, C),
                   :uflxchg => uflxchg(k, C, copy(y0)), :pmedian => pmedian(p, C; verbose = false))
        for f in fns
            y, TC, W = out[f]
            pre = "$(f)_$i"
            vals = (set = sort(y) == _ivec(d, pre * "_y"), order = y == _ivec(d, pre * "_y"),
                    TC = _oclose(TC, _sc(d, pre * "_TC")),
                    X = (Matrix(W) .> 0) == (d[pre * "_X"] .> 0))
            for q in (:set, :order, :TC, :X)
                push!(res[(f, q)], vals[q])
                vals[q] || push!(bad[(f, q)], i)
            end
        end
    end
    ok(f, q) = all(res[(f, q)])
    @test ok(:ufl, :set) && ok(:ufl, :TC) && ok(:ufl, :X)
    @test ok(:ufladd, :set) && ok(:ufladd, :TC) && ok(:ufladd, :X)
    @test ok(:ufldrop, :set) && ok(:ufldrop, :TC) && ok(:ufldrop, :X) && ok(:ufldrop, :order)
    @test ok(:pmedian, :set) && ok(:pmedian, :TC)
    # The sites come back in MATLAB's sorted order only by luck: ufl, ufladd, uflxchg and pmedian return
    # them in the order they were added or swapped in (instances 3 and 9 for ufl, 2 and 8 for ufladd,
    # 3, 4, 6, 7, 10, 11 for uflxchg, 4-11 for pmedian). CR 6 (decided 2026-08-29: sort), K3.
    @test ok(:ufl, :order)                     # flipped in K3 (CR 6)
    @test ok(:ufladd, :order)                  # flipped in K3 (ufladd commit)
    @test ok(:uflxchg, :order)
    @test ok(:pmedian, :order)
    # pmedian's allocation matrix differs in instance 7 only, where two open sites tie for an EF and the
    # unsorted site vector breaks the tie differently from MATLAB's sorted one: the same cause, CR 6, K3
    @test all(res[(:pmedian, :X)][i] for i in 1:ninst if i != 7)
    @test res[(:pmedian, :X)][7]               # flipped in K3 (CR 6): sorted sites break the tie as MATLAB does
    # uflxchg agrees with MATLAB on 11 of 12 instances. Instance 6 (start y0 = [1, 3]) ends at
    # TC 122 where MATLAB reaches 113: uflxchg swaps and reverts inside `for i′ in y`, so `deleteat!` and
    # `push!` reorder the vector being iterated and candidate swaps are skipped (K2a finding F1, now N32).
    # A copy-scanning uflxchg reproduces MATLAB's set and cost on all 12 instances (checked in K2b).
    # N32, flipped in K3: all twelve instances agree with MATLAB.
    for q in (:set, :TC, :X)
        @test all(res[(:uflxchg, q)][i] for i in 1:ninst if i != 6)
        @test res[(:uflxchg, q)][6]
    end
end

# =============================================================================================
@testset "oracle: ala, help Example 1 (three NFs for the NC cities, start saved)" begin
    d = _readoracle("ala_nc")
    P, w, X0 = d["P"], _fvec(d, "w"), d["X0"]
    # p = 2 (Euclidean): the same metric, so a cost oracle at 1e-9. The locate step is a different solver
    # (Optim here, Matlog's minisumloc there), so the NF coordinates agree only to about 1e-6 and are not
    # compared; the allocation (an index result) and the cost are.
    X, TC, W = _oquiet(() -> ala(X0, w, P; dist = 2, verbose = false))
    @test (Matrix(W) .> 0) == (d["e2_W"] .> 0)
    @test _oclose(TC, _sc(d, "e2_TC"))
    # p = 'mi': DEPARTURE (D7). Logjam's constant radius 3958.75 mi against Matlog's latitude-dependent
    # 3963.34 - 13.35|sin(lat)| gives a cost that differs by up to the 0.08% of N15; the allocation is the
    # same and the cost is asserted within GC_RADIUS_RTOL (relative 1e-3), not at 1e-9.
    X, TC, W = _oquiet(() -> ala(X0, w, P; dist = :mi, verbose = false))
    @test (Matrix(W) .> 0) == (d["mi_W"] .> 0)
    @test _oclose(TC, _sc(d, "mi_TC"); rtol = GC_RADIUS_RTOL)
    @test !_oclose(TC, _sc(d, "mi_TC"))        # and it is a difference, not agreement (D7)
end

# =============================================================================================
@testset "oracle: dists, help examples and seeded lp distances" begin
    d = _readoracle("dists")
    x1, x2, X2 = d["x1"], d["x2"], d["X2"]
    @test dists(x1, x2, 1) == d["d_x1_x2_p1"]
    @test dists(x1, X2, 1) == d["d_x1_X2_p1"]
    @test dists(X2, X2, 1) == d["D_X2_X2_p1"]
    Xr, Yr = d["Xr"], d["Yr"]
    @test _oclose(dists(Xr, Yr, 1), d["D_p1"])
    @test _oclose(dists(Xr, Yr, 2), d["D_p2"])
    @test _oclose(dists(Xr, Yr, 3.0), d["D_p3"])
    @test _oclose(dists(Xr, Yr, Inf), d["D_pInf"])
    # dists(X, Y, 3) with an Integer p threw at v0.2.8 (the integer method accepted only 1 and 2) while the
    # same call with 3.0 worked: N19, `dists(X, Y, p::Integer)` forwards to the real method (K5)
    @test _oclose(dists(Xr, Yr, 3), d["D_p3"])
    # help text: Raleigh to Gainesville, 475.9923 mi. DEPARTURE (D7): the constant radius gives 476.309
    # (relative 6.7e-4); asserted within GC_RADIUS_RTOL (relative 1e-3). dgc is the same sphere (DST1).
    ral, gai = d["ral"], d["gai"]
    dd = dists(ral, gai, :mi)[1, 1]
    @test _oclose(dd, _sc(d, "d_ral_gai_mi"); rtol = GC_RADIUS_RTOL)
    @test !_oclose(dd, _sc(d, "d_ral_gai_mi"))
    @test _oclose(_sc(d, "d_ral_gai_mi"), 475.9923; rtol = 1e-7)     # the help text's own figure
    @test _oclose(dgc(vec(ral), vec(gai); unit = :mi), _sc(d, "d_ral_gai_mi"); rtol = GC_RADIUS_RTOL)
    @test dgc(vec(ral), vec(gai); unit = :mi) == dd
end

# =============================================================================================
@testset "oracle: great circle, Matlog dists(X,Y,'mi') on nccity" begin
    d = _readoracle("dgc_nccity")
    XY = d["XY"]
    # the arc itself is the same haversine: an oracle at 1e-9
    @test _oclose(dists(XY, XY, :rad), d["D_rad"])
    # DEPARTURE (D7): the constant radius against Matlog's latitude-dependent one, asserted within
    # GC_RADIUS_RTOL (relative 1e-3; the measured maximum over these cities is 8.5e-4, N15's 0.08%), as a
    # difference and not an agreement
    for (u, key) in ((:mi, "D_mi"), (:km, "D_km"))
        D = dists(XY, XY, u)
        @test _oclose(D, d[key]; rtol = GC_RADIUS_RTOL)
        @test !_oclose(D, d[key])
    end
    # dgc, point by point, is the same sphere (DST1, DST2): within GC_RADIUS_RTOL of Matlog's matrices, and
    # Matlog's own arc times the sphere's radius (3958.75 mi, 6371.00 km) at 1e-9
    n = size(XY, 1)
    gc(u) = [dgc(XY[i, :], XY[j, :]; unit = u) for i in 1:n, j in 1:n]
    @test _oclose(gc(:mi), d["D_mi"]; rtol = GC_RADIUS_RTOL)
    @test _oclose(gc(:km), d["D_km"]; rtol = GC_RADIUS_RTOL)
    @test _oclose(gc(:mi), d["D_rad"] .* 3958.75)
    @test _oclose(gc(:km), d["D_rad"] .* 6371.00)
end

# =============================================================================================
@testset "oracle: transport, makeFrghtTrans1.m Questions 1-10" begin
    d = _readoracle("transport_ft1")
    s, dd, Kwt, Kcu = _sc(d, "s"), _sc(d, "d"), _sc(d, "Kwt"), _sc(d, "Kcu")
    ppiTL, ppiLTL = _sc(d, "ppiTL"), _sc(d, "ppiLTL")
    tr = _tr(_sc(d, "r"), Kwt, Kcu, ppiTL)
    sh = (s = s, d = dd)
    qmax = maxpayld(sh, tr)
    @test _oclose(qmax, _sc(d, "qmax"))
    @test _oclose(charge_tl(_sc(d, "q"), sh, tr), _sc(d, "cTL"))
    @test _oclose(charge_tl(_sc(d, "qTL"), sh, tr), _sc(d, "cTL_qTL"))
    @test _oclose(charge_ltl(_sc(d, "qLTL"), sh; ppi = ppiLTL), _sc(d, "cLTL"))
    @test _oclose(rate_ltl(_sc(d, "qLTL"), s, dd; ppi = ppiLTL), _sc(d, "rLTL"))
    @test _oclose(mincharge_tl(; ppi = ppiTL), _sc(d, "MC_TL"))
    @test _oclose(mincharge_ltl(dd; ppi = ppiLTL), _sc(d, "MC_LTL"))
    # c0h(q) = transcharge(q, sh, tr, ppiLTL) over a grid of sizes, with the mode it selects
    for (q, c, isl) in zip(_fvec(d, "qgrid"), _fvec(d, "c0_grid"), _fvec(d, "isLTL_grid"))
        cj, lj = _transcharge(q, sh, tr, ppiLTL)
        @test _oclose(cj, c)
        @test lj == (isl == 1)
    end
end

@testset "oracle: transport, makeFrghtTrans2.m Questions 11-21" begin
    d = _readoracle("transport_ft2")
    ppiTL, ppiLTL = _sc(d, "ppiTL"), _sc(d, "ppiLTL")
    tr = _tr(_sc(d, "r"), _sc(d, "Kwt"), _sc(d, "Kcu"), ppiTL)
    sh = (f = _sc(d, "f"), s = _sc(d, "s"), a = _sc(d, "a"), v = _sc(d, "v"), h = _sc(d, "h"), d = _sc(d, "d"))
    qmax = maxpayld(sh, tr)
    @test _oclose(qmax, _sc(d, "qmax"))
    # Question 15: all-FTL total logistics cost
    @test _oclose(totlogcost(qmax, charge_tl(qmax, sh, tr), sh), _sc(d, "Q15_TLC"))
    # Question 16: TL only
    r = minTLC(sh, tr)
    @test _oclose(r.qᵒ, _sc(d, "Q16_q")) && _oclose(r.TLCᵒ, _sc(d, "Q16_TLC")) && r.isLTL == false
    @test _oclose(totlogcost(r.qᵒ, charge_tl(r.qᵒ, sh, tr), sh), _sc(d, "Q16_TLC2"))
    # Question 17: LTL only (the LTL size is a one-dimensional minimization: Optim here, fminbnd there)
    # A NOTE ON THE LTL SIZE q. Matlog finds it with fminbnd (default TolX 1e-4), Logjam with Optim's Brent
    # search, and the two argmins differ by about 2e-5 (relative) on this flat objective, while the
    # COSTS they reach agree to about 1e-11. The test spec fixes a tolerance for costs (1e-9), not for an
    # optimizer's argmin, so the LTL q is not asserted anywhere below; every LTL cost is, at 1e-9.
    r = minTLC(sh, nothing, ppiLTL)
    @test _oclose(r.TLCᵒ, _sc(d, "Q17_TLC")) && r.isLTL == true
    # Questions 18-19: TL against LTL, the second at a value that changes the answer
    r = minTLC(sh, tr, ppiLTL)
    @test _oclose(r.TLCᵒ, _sc(d, "Q18_TLC")) && r.isLTL == (_sc(d, "Q18_isLTL") == 1)
    @test _oclose(r.qᵒ, _sc(d, "Q18_q"))                    # TL won: the closed form
    c0 = charge_tl(r.qᵒ, sh, tr)
    @test _oclose(c0, _sc(d, "Q18_c0"))
    @test _oclose(totlogcost(r.qᵒ, c0, sh), _sc(d, "Q18_TLC2"))
    sh19 = merge(sh, (v = _sc(d, "Q19_v"),))
    r = minTLC(sh19, tr, ppiLTL)
    @test _oclose(r.TLCᵒ, _sc(d, "Q19_TLC")) && r.isLTL == (_sc(d, "Q19_isLTL") == 1)
    @test _oclose(totlogcost(r.qᵒ, charge_ltl(r.qᵒ, sh19; ppi = ppiLTL), sh19), r.TLCᵒ)
    # Questions 20-21: two products, each independently, then their aggregate
    rows = [(f = d["two_f"][i], s = d["two_s"][i], a = d["two_a"][i], v = d["two_v"][i], h = d["two_h"][i], d = d["two_d"][i]) for i in 1:2]
    rs = [minTLC(r, tr, ppiLTL) for r in rows]
    @test _oclose([r.TLCᵒ for r in rs], _fvec(d, "Q20_TLC"))
    @test _oclose([r.qᵒ for r in rs], _fvec(d, "Q20_q"))      # both TL: the closed form
    @test [r.isLTL for r in rs] == (_fvec(d, "Q20_isLTL") .== 1)
    @test _oclose([maxpayld(r, tr) for r in rows], _fvec(d, "Q20_qmax"))
    ash = aggshmt(DataFrame(rows))
    for (fld, key) in ((:f, "agg_f"), (:s, "agg_s"), (:a, "agg_a"), (:v, "agg_v"), (:h, "agg_h"), (:d, "agg_d"))
        @test _oclose(getproperty(ash, fld), _sc(d, key))
    end
    @test _oclose(maxpayld(ash, tr), _sc(d, "agg_qmax"))
    ra = minTLC(ash, tr)
    @test _oclose(ra.qᵒ, _sc(d, "Q21_q")) && _oclose(ra.TLCᵒ, _sc(d, "Q21_TLC")) && ra.isLTL == (_sc(d, "Q21_isLTL") == 1)
end

@testset "oracle: transport, makeFrghtTrans3.m Examples A and B" begin
    d = _readoracle("transport_ft3")
    # Example A: aggshmt of the two suppliers, the customers' shares of it, maxpayld
    trA = _tr(2.0, 25.0, 2750.0, 102.7)
    fS = [100.0, 380.0]
    shS = DataFrame(f = fS, s = [30, 120] ./ [10, 4])
    agg = aggshmt(shS)
    pct = [20, 30, 50] / 100
    @test _oclose(vcat(shS.f, agg.f .* pct), _fvec(d, "A_f"))
    @test _oclose(vcat(shS.s, fill(agg.s, 3)), _fvec(d, "A_s"))
    @test _oclose(maxpayld(vcat(shS.s, fill(agg.s, 3)); Kwt = 25.0, Kcu = 2750.0), _fvec(d, "A_qmax"))
    shS2 = DataFrame(f = fS, s = shS.s, a = 0.5, v = [300, 450] ./ ([30, 120] ./ 2000), h = 0.3)
    agg2 = aggshmt(shS2)
    cust = [(f = agg2.f * p, s = agg2.s, a = agg2.a, v = agg2.v, h = agg2.h) for p in pct]
    sup = [(f = r.f, s = r.s, a = r.a, v = r.v, h = r.h) for r in eachrow(shS2)]
    allsh = vcat(sup, cust)
    for (fld, key) in ((:v, "A2_v"), (:a, "A2_a"), (:h, "A2_h"), (:s, "A2_s"), (:f, "A2_f"))
        @test _oclose([getproperty(r, fld) for r in allsh], _fvec(d, key))
    end
    # The total logistics cost functions at MATLAB's saved location x (Statesville, where supplier 2 sits:
    # its shipment distance is exactly 0 at x = 150 and 9e-9 at the fminsearch argmin DCtc). Shipment
    # distances d are saved. Matlog charges nothing at d = 0 (CR 15, decided Q3: the chapter's reading),
    # so supplier 2's transport cost is 0 there and, sized by it, its TLC is 0. Until CR 15 (K6) Logjam charged the 45 TL
    # minimum at d = 0 and sizes the shipment by it: the supplier's term is 28,809 for FTL (684 of it
    # transport, the rest inventory) and 8,772 for TL rather than 28,125 and 0. CR 15 / N4, K6.
    # The other four shipments are compared in the sum at 1e-9 (the FTL inventory term of the zero-distance
    # shipment is added by formula: it does not depend on the charge). The TL-only comparison is made at
    # x = 150 only, where d is exactly 0; the FTL sum at DCtc rounds the 9e-9 to 0 first (below).
    dvec, dvec150 = _fvec(d, "A2_d"), _fvec(d, "A2_d150")
    mkrows(dv) = [merge(allsh[i], (d = dv[i],)) for i in eachindex(allsh)]
    rows, rows150 = mkrows(dvec), mkrows(dvec150)
    z = findall(<(1e-4), dvec)                      # the zero-distance shipments: supplier 2 only
    @test z == [2] && findall(<(1e-4), dvec150) == [2]
    o = setdiff(eachindex(rows), z)
    qm = [maxpayld(r, trA) for r in rows]
    tlcf(i) = totlogcost(qm[i], charge_tl(qm[i], rows[i], trA), rows[i])
    icf(i) = qm[i] * rows[i].a * rows[i].v * rows[i].h
    @test _oclose(sum(tlcf(i) for i in o) + sum(icf(i) for i in z), _sc(d, "A_TLCftl_at_DCtc"))
    # CR 15, K6: with the zero-distance shipment charged nothing, the whole sum agrees. Matlog's mincharge reads the
    # saved 9e-9 mi at DCtc as 0 (is0, tol0 = 1e-4; Lecture 3.4's c0 does the same with atol 1e-4), so there is no
    # minimum charge and the charge is the loaded-mile 2 x 9e-9. Before TRN3 charge_tl was exact at 0 only, and the
    # distances below 1e-4 were set to 0 before the call; that comparison stands, and since TRN3 the saved
    # distances reach charge_tl as they are and give Matlog's sum too, supplier 2's charge Matlog's own.
    rowsz = mkrows(ifelse.(dvec .< 1e-4, 0.0, dvec))
    @test _oclose(sum(totlogcost(qm[i], charge_tl(qm[i], rowsz[i], trA), rowsz[i]) for i in eachindex(rowsz)), _sc(d, "A_TLCftl_at_DCtc"))
    @test _oclose(sum(tlcf(i) for i in eachindex(rows)), _sc(d, "A_TLCftl_at_DCtc"))                    # TRN3
    @test charge_tl(qm[2], rows[2], trA) == ceil(Int, qm[2] / maxpayld(rows[2], trA)) * (trA.r * dvec[2])   # TRN3
    @test _oclose(sum(minTLC(rows150[i], trA).TLCᵒ for i in o), _sc(d, "A_TLCtl_at_150"))
    @test _oclose(sum(minTLC(r, trA).TLCᵒ for r in rows150), _sc(d, "A_TLCtl_at_150"))   # CR 15, K6
    # Example B part 1: 12 direct shipments (distances saved, so the distance formula is not compared)
    trB = _tr(2 * (_sc(d, "B_ppiTL") / 102.7), 25.0, 2750.0, _sc(d, "B_ppiTL"))
    ppiL = _sc(d, "B_ppiLTL")
    nB = size(d["B_f"], 2)
    rowsB = [(f = d["B_f"][i], s = d["B_s"][i], a = d["B_a"][i], v = d["B_v"][i], h = d["B_h"][i], d = d["B_d"][i]) for i in 1:nB]
    @test _oclose([maxpayld(r, trB) for r in rowsB], _fvec(d, "B_qmax1"))
    rb = [minTLC(r, trB, ppiL) for r in rowsB]
    @test _oclose([r.TLCᵒ for r in rb], _fvec(d, "B_TLC1"))
    @test [r.isLTL for r in rb] == (_fvec(d, "B_isLTL1") .== 1)
    # the TL-only sizes are a closed form: exact; the LTL-only costs are an optimum: 1e-9 on the cost
    rt = [minTLC(r, trB) for r in rowsB]
    @test _oclose([r.TLCᵒ for r in rt], _fvec(d, "B_TLCtl"))
    @test _oclose([r.qᵒ for r in rt], _fvec(d, "B_qtl"))
    # LTL only. FINDING F2 (new, in no CR or N entry): where the LTL optimum sits at the cube-out bound
    # min(5, 650 s/2000) (8 of the 12 shipments), MATLAB's fminbnd at minTLC's default TolX (1e-4) stops 1e-5
    # to 1e-4 ton short of it, so Matlog's own minTLC cost is HIGH by 5.8e-7 to 7.0e-6 (relative): the
    # optimizer's tolerance, not the model's answer (B_TLCltl_default, B_qltl_default). The oracle B_TLCltl,
    # B_qltl is the converged optimum, the same cost and bracket with fminbnd at TolX = 1e-12
    # (tools/v0_3_0/make_oracles.m), and Logjam's Optim search, which ends within 3e-8 ton of the bound, agrees
    # with it to the 1e-9 of rule 4. Logjam is never worse than Matlog's own default-TolX number.
    rl = [minTLC(r, nothing, ppiL) for r in rowsB]
    ref, qref = _fvec(d, "B_TLCltl"), _fvec(d, "B_qltl")
    refD = _fvec(d, "B_TLCltl_default")                              # what Matlog's minTLC itself returns
    qUB = [min(5, 650 * r.s / 2000) for r in rowsB]
    atbound = qref .>= qUB .- 1e-3
    @test count(atbound) == 8
    @test all(_oclose(rl[i].TLCᵒ, ref[i]) for i in findall(.!atbound))
    @test all(rl[i].TLCᵒ <= refD[i] * (1 + 1e-9) for i in 1:nB)      # one-sided, rule 4's 1e-9
    @test all(_oclose(rl[i].TLCᵒ, ref[i]) for i in findall(atbound)) # F2, flipped by K6: the converged oracle
    @test all(rl[i].TLCᵒ <= ref[i] * (1 + 1e-9) for i in 1:nB)
    # part 3 (perfect cross-docking): the cost at MATLAB's saved common interval t3
    t3 = _sc(d, "C3_t3")
    nC = size(d["C3_f"], 2)
    rowsC = [(f = d["C3_f"][i], s = d["C3_s"][i], a = d["C3_a"][i], v = d["C3_v"][i], h = d["C3_h"][i], d = d["C3_d"][i]) for i in 1:nC]
    @test _oclose([maxpayld(r, trB) for r in rowsC], _fvec(d, "C3_qmax"))
    qs = [r.f * t3 for r in rowsC]
    out = [_transcharge(qs[i], rowsC[i], trB, ppiL) for i in 1:nC]
    @test _oclose([totlogcost(qs[i], out[i][1], rowsC[i]) for i in 1:nC], _fvec(d, "C3_TLC_at_t3"))
    @test [o[2] for o in out] == (_fvec(d, "C3_isLTL") .== 1)
end

# =============================================================================================
@testset "oracle: transport edges (N2, N3, N4, CR 14, CR 15, D5)" begin
    d = _readoracle("transport_edge")
    # N3: one TL minimum per shipment. Matlog: max(ceil(30/25)*10*2, 45) = 45; Logjam charges the minimum
    # per truck, 2 x 45 = 90 (until N3, K6).
    @test _sc(d, "N3_c") == 45
    @test _oclose(charge_tl(30, 30, 10; r = 2.0, Kwt = 25.0, Kcu = 2750.0), _sc(d, "N3_c"))
    # N4: no charge at q = 0. TL is already 0 (no truck); LTL charges its minimum. N4, K6.
    @test _oclose(charge_tl(0, 30, 200), _sc(d, "q0_TL"))
    @test _oclose(charge_ltl(0, 30, 200), _sc(d, "q0_LTL"))
    # CR 15: no charge at d = 0. TL charges the 45 minimum; LTL is already 0 (mincharge_ltl(0) = 0).
    # The TL case is flipped by CR 15 / N4, K6.
    @test _oclose(charge_ltl(5, 30, 0), _sc(d, "d0_LTL"))
    @test _sc(d, "d0_mincharge_TL") == 0
    @test _oclose(charge_tl(5, 30, 0), _sc(d, "d0_TL"))
    # D5: with `r` passed and no `ppi`, Matlog takes ppiTL = 102.7 (r/2), so its minimum is 45 (r/2) =
    # 57.4; Logjam keeps the default ppi 102.7 and charges 45 (D5: an explicit r is never re-escalated
    # internally). DEPARTURE, asserted as a difference; Matlog's value is recovered by passing the ppi.
    r = _sc(d, "D5_r")
    @test _oclose(_sc(d, "D5_ppiTL"), 102.7 * (r / 2))
    @test charge_tl(5, 10, 10; r = r) == 45
    @test !_oclose(charge_tl(5, 10, 10; r = r), _sc(d, "D5_c"))
    @test _oclose(charge_tl(5, 10, 10; r = r, ppi = _sc(d, "D5_ppiTL")), _sc(d, "D5_c"))
    # N2: aggshmt on shipments with q and no f sums q and invents no f (Matlog); s, v, h, a are the
    # q-weighted means. (Until N2, K6, Logjam summed q into an invented `f` and left q as the first shipment's.)
    sh = DataFrame(q = _fvec(d, "N2_q"), s = _fvec(d, "N2_s"), v = _fvec(d, "N2_v"), h = _fvec(d, "N2_h"), a = _fvec(d, "N2_a"))
    ag = aggshmt(sh)
    @test _oclose(ag.s, _sc(d, "N2_agg_s")) && _oclose(ag.v, _sc(d, "N2_agg_v")) &&
          _oclose(ag.h, _sc(d, "N2_agg_h")) && _oclose(ag.a, _sc(d, "N2_agg_a"))
    @test _oclose(ag.q, _sc(d, "N2_agg_q")) && !haskey(ag, :f)
    # CR 14 (DEPARTURE): Matlog averages a, v and h separately, so for unequal h its aggregate's inventory
    # term q*a*v*h is not the sum of the shipments' terms. Logjam adds `avh` (K6) and totlogcost uses it:
    # the Matlog value is then not reproduced. The separate means are still oracles.
    shu = DataFrame(f = _fvec(d, "U_f"), s = _fvec(d, "U_s"), v = _fvec(d, "U_v"), h = _fvec(d, "U_h"),
                    a = _fvec(d, "U_a"), d = fill(_sc(d, "U_d"), 2))
    au = aggshmt(shu)
    @test _oclose(au.f, _sc(d, "U_agg_f")) && _oclose(au.s, _sc(d, "U_agg_s")) && _oclose(au.v, _sc(d, "U_agg_v")) &&
          _oclose(au.h, _sc(d, "U_agg_h")) && _oclose(au.a, _sc(d, "U_agg_a"))
    tlcu = totlogcost(_sc(d, "U_q"), _sc(d, "U_c"), au)
    # Today Logjam reproduces Matlog's value; after K6 (CR 14, S37) the aggregate's cost is the sum over the
    # originals, which differs from Matlog's (flipped to @test by K6). (The avh value itself
    # is asserted in test_transtools.jl.)
    @test !_oclose(tlcu, _sc(d, "U_TLC"))
end

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
