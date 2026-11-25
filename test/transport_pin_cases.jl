# transport_pin_cases.jl -- the transport calls the course makes today, as pin cases (PCV K6,
# plan principle 9). Every case is a (name, thunk) pair; the thunk returns one line of text, the value
# encoded to 12 significant digits (see transport_pin_helpers.jl). The calls and the inputs come from
# the course's own lectures and homeworks (read only): Lecture 3.2 Ex. 1 and 2 (Raleigh to
# Gainesville, Raleigh to Detroit), 3.3 Ex. 1 and 2, 3.4 Ex. 1 (I-40) and Ex. 2 (Memphis) with its three
# inline implementations, 4.3 Ex. 6, HW 3 (Q2, Q4 with its own numbers, Q5 on the first four
# products and three retailers of its data), Project 3 (five products and three stores of its data, with the
# own `names(shIn)` projection) and HW 3's other call shapes.
#
# A name beginning with a ruled ID is a case whose value the ruled item moves; the fixture row is rewritten
# in the commit that moves it, and that commit names the ID. The IDs: N2, N3, N4, CR14, CR15, D5, N21, N31.
# Any other case must keep its value. Where a case reads an aggregate (aggshmt) the fields are picked by name,
# so the new `avh` field (CR 14) moves no pin by itself.
#
# Stand-ins, said once: the distances of the HW 3 Q5 and Project 3 mini-cases are typed numbers (the homeworks
# compute them from ZIP centroids, which K5's pins already cover); the products, flows, PPIs and carrying
# rates are the data files' own. HW 3 Q4's distance is its printed 1.2 * dists(Chicago, Austin).

using Logjam
using DataFrames
using Optim

# ---- encoding ------------------------------------------------------------------------------
_te(x::Missing) = "missing"
_te(x::Bool) = string(x)
_te(x::Integer) = string(x)
_te(x::AbstractFloat) = isfinite(x) ? repr(round(Float64(x); sigdigits = 12)) : repr(Float64(x))   # 12 digits: last-place differences under --check-bounds=yes
_te(x::Symbol) = ":" * String(x)
_te(x::AbstractString) = repr(String(x))
_te(x::Nothing) = "nothing"
_te(x::Tuple) = "(" * join((_te(v) for v in x), ",") * ")"
_te(x::NamedTuple) = "(" * join((string(k) * "=" * _te(v) for (k, v) in pairs(x)), ",") * ")"
_te(x::AbstractArray) = string(size(x)) * "[" * join((_te(v) for v in x), ",") * "]"
_te(df::DataFrame) = "df" * string(size(df)) * join(("|" * n * "=" * _te(df[!, n]) for n in names(df)), "")

# the fields of an aggregate that existed at v0.2.8, picked by name (so `avh` is not in the pin)
_aggfields(a, flds = (:f, :s, :a, :v, :h, :d)) =
    _te(Tuple(getproperty(a, k) for k in flds if hasproperty(a, k)))

# ---- Lecture 3.4's three inline implementations, copied as the reference (3-tran-4.qmd:927, 934, 1033) ------
# The only change is that `optimize` is called through Logjam, which already uses Optim.
function ref_c0(q, sh, tr, ppi = nothing)
    isapprox(sh.d, 0, atol = 1e-4) && return 0.0
    c = charge_tl(q, sh, tr)
    return ppi === nothing ? c : min(c, charge_ltl(q, sh; ppi = ppi))
end

function ref_tlc_uc(sh, tr, ppi = nothing)
    q = [isapprox(r.d, 0, atol = 1e-4) ? 0.0 : minTLC(r, tr, ppi).qᵒ
         for r in eachrow(sh)]
    TLC = sum(totlogcost(q[i], ref_c0(q[i], r, tr, ppi), r)
              for (i, r) in enumerate(eachrow(sh)))
    return (TLC = TLC, q = q)
end

function ref_tlc_xd(sh, tr, tmin, tmax, ppi = nothing)
    TLC(t) = sum(r -> totlogcost(r.f*t, ref_c0(r.f*t, r, tr, ppi), r),
                 eachrow(sh))
    t = optimize(TLC, tmin, tmax).minimizer    # (b) below; (a), (c) above
    return (TLC = TLC(t), t = t, q = sh.f*t)
end

# ---- the course's inputs, built the way the course builds them --------------------------------

# 3.4 Ex. 1 (Code blocks 2, 12, 13): the shipments of the I-40 example, and the carrier
function _ex34_shipments()
    uwt = [30, 120]; ucu = [10, 4]
    shS = DataFrame(f = [100, 380], s = uwt ./ ucu)
    pct = [20, 30, 50] / 100
    tr = (r = 2, Kwt = 25, Kcu = 2750, ppi = 102.7)
    uval = [300, 450]
    shS.v = uval ./ (uwt / 2000)
    αS = 0
    shS.a .= αS + 0.5
    shC = DataFrame(f = sum(shS.f) * pct, s = sum(shS.f) ./ sum(shS.f ./ shS.s),
                    v = sum(shS.f .* shS.v) / sum(shS.f))
    shC.a .= 0.5
    sh = vcat(shS, shC)
    sh.h .= 0.3
    return sh, tr
end
const _P34 = [50, 150, 190, 270, 420]      # I-40 mile markers: suppliers 1:2, customers 3:5
_shd34(sh, x) = hcat(sh, DataFrame(d = float.(abs.(x .- _P34))))

# 3.4 Ex. 2 (Code blocks 18, 20 to 23): the places come from the package's place table
function _trplace(name, st)
    p = usplace()
    r = p[(p.NAME .== name) .& (p.ST .== st), :]
    return [r.LON[1], r.LAT[1]]
end
function _ex34_memphis()
    ppiTL, ppiLTL = 131.0, 177.4
    tr2 = (r = 2ppiTL/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL)
    SXY = permutedims(hcat(_trplace("Rochester", :NY), _trplace("Orlando", :FL), _trplace("San Antonio", :TX)))
    CXY = permutedims(hcat(_trplace("Portland", :OR), _trplace("Tucson", :AZ), _trplace("Denver", :CO),
                           _trplace("Milwaukee", :WI)))
    DCXY = permutedims(hcat(_trplace("Memphis", :TN)))
    fS2 = [500, 75, 300]
    pct2 = [20, 35, 25, 20] / 100
    sS2 = [32, 3, 12]
    v2 = [50_000, 25_000, 10_000]
    αS, αC = 0, 0.5
    F2 = fS2 * pct2'
    S2 = repeat(sS2, 1, size(CXY, 1))
    V2 = repeat(v2, 1, size(CXY, 1))
    D2 = dists(SXY, CXY, :mi) * 1.2
    shD = DataFrame(f = F2[:], s = S2[:], a = αS + αC, v = V2[:], h = 0.3, d = D2[:])
    shD.qmax = [maxpayld(r, tr2) for r in eachrow(shD)]
    shS2 = DataFrame(f = fS2, s = sS2, a = αS + 0.5, v = v2)
    shC2 = DataFrame(f = sum(shS2.f) * pct2, s = sum(shS2.f) ./ sum(shS2.f ./ shS2.s), a = αC,
                     v = sum(shS2.f .* shS2.v) / sum(shS2.f))
    sh2 = vcat(shS2, shC2)
    sh2.h .= 0.3
    sh2.d = dists(DCXY, [SXY; CXY], :mi)[:] * 1.2
    sh2.qmax = [maxpayld(r, tr2) for r in eachrow(sh2)]
    return (; tr2, ppiLTL, shD, sh2, αS, idxin2 = 1:length(fS2))
end

# HW 3 Q4, with its own numbers
function _hw3_q4()
    ppiTL, ppiLTL = 162.1, 203.7
    tr = (r = 2ppiTL/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL)
    d = 1168.618368673098                      # 1.2 * dists(Chicago, Austin), as the key prints it
    cu = [2, 6, 12]; wt = [16, 150, 40]; uc = [500, 200, 100]; sv = [50, 180, 80]; ud = [720, 120, 480]
    xh = (uc .- sv) ./ uc
    sh4 = DataFrame(f = ud .* wt / 2000, s = wt ./ cu, a = 0.5, v = 2000uc ./ wt,
                    h = 0.05 .+ 0.06 .+ xh, d = d)
    return sh4, tr, ppiLTL
end

# HW 3 Q5 on the first four products and three retailers of its data files
function _hw3_q5()
    ppiTL, ppiLTL = 162.1, 203.7
    tr = (r = 2ppiTL/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL)
    cu = [0.8889, 1, 0.6667, 0.6667]; wt = [7.8435, 6.6003, 2.5858, 0.8865]
    uc = [63.28, 4, 6.69, 31.5]; sv = [47.75, 2.85, 3.78, 29.07]
    UD = [251 497 319; 126 32 150; 386 1591 1572; 1192 1071 406]
    F = wt .* UD / 2000
    s = wt ./ cu
    v = 2000uc ./ wt
    h = 0.05 .+ 0.06 .+ (uc .- sv) ./ uc
    αS, αC = 0, 0.5
    dS, dR = [550.0, 120.0, 880.0, 15.0], [210.0, 40.0, 700.0]      # stand-in distances
    shS = DataFrame(f = vec(sum(F; dims = 2)), s = s, a = αS + 0.5, v = v, h = h, d = dS)
    shR = DataFrame([aggshmt(DataFrame(f = F[:, j], s = s, a = αC, v = v, h = h, d = dR[j]))
                     for j in 1:size(F, 2)])
    return (; tr, ppiLTL, F, s, v, h, αS, αC, dR, shS, shR)
end

# Project 3 (its own definitions) on the first five products and three stores of its data
function _proj3()
    ppiTL, ppiLTL = 207.644, 306.839
    tr = (r = 2ppiTL/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL)
    cube = [2.6667, 1.3333, 0.8889, 0.8889, 2.6667]; wt = [12.3374, 39.4301, 4.5871, 18.5189, 5.2957]
    cost = [108.06, 64.09, 80.19, 69.42, 132.99]; clear = [73.64, 61.19, 70.94, 50.83, 105.25]
    UD = [201 157 165; 8 18 17; 505 67 174; 405 96 268; 63 67 7]
    s = wt ./ cube
    v = 2000 .* cost ./ wt
    h = 0.05 .+ 0.06 .+ (cost .- clear) ./ cost
    F = UD .* wt ./ 2000
    αS, αC = 0, 0.5
    dS, dC = [300.0, 450.0, 800.0, 150.0, 1200.0], [15.0, 120.0, 400.0]      # stand-in distances (store 1 is near the DC)
    shIn = DataFrame(f = vec(sum(F, dims = 2)), s = s, a = αS, v = v, h = h, d = dS)
    shOut = DataFrame([aggshmt(DataFrame(f = F[:, j], s = s, a = αC, v = v, h = h, d = dC[j]))
                       for j in 1:3])[:, names(shIn)]
    return (; tr, ppiLTL, F, s, v, h, shIn, shOut, αS, αC, dC)
end

# ---- the cases -----------------------------------------------------------------------------
function trpin_cases()
    cases = Tuple{String,Function}[]
    add(name, f) = push!(cases, (name, f))

    # ================= 3.2 Ex. 1: Raleigh to Gainesville =================
    s32, Kwt32, Kcu32, d32, ppiTL32, ppiLTL32 = 40/9, 25, 2750, 532, 131.0, 177.4
    rTL32 = 2.00ppiTL32/102.7
    add("l32_maxpayld", () -> _te(maxpayld(s32; Kwt = Kwt32, Kcu = Kcu32)))
    add("l32_charge_tl_300_cartons", () -> _te(charge_tl(300 * (40/2000), s32, d32; r = rTL32, Kwt = Kwt32, Kcu = Kcu32, ppi = ppiTL32)))
    add("l32_rate_ltl_15_cartons", () -> _te(rate_ltl(15 * (40/2000), s32, d32; ppi = ppiLTL32)))
    add("l32_charge_ltl_15_cartons", () -> _te(charge_ltl(15 * (40/2000), s32, d32; ppi = ppiLTL32)))
    add("l32_mincharges", () -> _te((mincharge_tl(; ppi = ppiTL32), mincharge_ltl(d32; ppi = ppiLTL32))))
    qs32 = [1/2000, 0.075, 0.1, 0.3, 0.5, 0.8, 1.0, 1.44, 1.45, 2.0, 5.0, 5.5, 6.0, 11.0, 11.5, 22.0, 27.5]
    add("l32_charge_tl_grid", () -> _te([charge_tl(q, s32, d32; r = rTL32, Kwt = Kwt32, Kcu = Kcu32, ppi = ppiTL32) for q in qs32]))
    add("l32_charge_ltl_grid", () -> _te([charge_ltl(q, s32, d32; ppi = ppiLTL32) for q in qs32]))
    add("l32_rate_ltl_grid", () -> _te([rate_ltl(q, s32, d32; ppi = ppiLTL32) for q in qs32]))
    add("l32_break_even", () -> (qmaxL = 650s32/2000;
        cTLh(q) = charge_tl(q, s32, d32; r = rTL32, Kwt = Kwt32, Kcu = Kcu32, ppi = ppiTL32);
        cLTLh(q) = charge_ltl(q, s32, d32; ppi = ppiLTL32);
        qI = optimize(q -> abs(cTLh(q) - cLTLh(q)), 0.075, qmaxL).minimizer;
        _te((qmaxL, qI, cTLh(qI), cLTLh(qI)))))
    # Ex. 2: Raleigh to Detroit
    s322, q322, d322, ppi322 = 126/4, 14*126/2000, 691, 184.6
    add("l32_ex2_detroit", () -> _te((maxpayld(s322; Kwt = Kwt32, Kcu = Kcu32), rate_ltl(q322, s322, d322; ppi = ppi322),
                                      charge_ltl(q322, s322, d322; ppi = ppi322))))
    add("l32_rate_ltl_vector", () -> _te(rate_ltl([0.5, 1.0, 2.0], [8.0, 10.0, 12.0], [250.0, 500.0, 800.0])))
    add("l32_rate_ltl_clamps_and_bounds", () -> _te((rate_ltl(0.01, 8.0, 10.0), rate_ltl(6.0, 8.0, 250.0),
                                                      rate_ltl(1.0, 8.0, 4000.0), rate_ltl(5.0, 2.0, 250.0))))
    add("charge_ltl_bounds", () -> _te((charge_ltl(6.0, 8.0, 250.0), charge_ltl(1.0, 8.0, 4000.0))))
    add("mincharge_ltl_beyond_range", () -> _te(mincharge_ltl(4000.0)))
    add("maxpayld_vector", () -> _te(maxpayld([5.0, 10.0, 20.0, 30.0]; Kwt = 25.0, Kcu = 2750.0)))
    add("charge_tl_docstring", () -> _te((charge_tl(10.0, 8.0, 500.0), charge_tl(25.0, 8.0, 500.0), charge_tl(30.0, 8.0, 500.0))))
    add("charge_ltl_docstring", () -> _te((charge_ltl(0.5, 8.0, 250.0), charge_ltl(2.0, 10.0, 500.0))))
    add("charge_tl_two_trucks_above_minimum", () -> _te(charge_tl(30.0, 8.0, 500.0)))
    add("charge_tl_one_truck_short_haul", () -> _te(charge_tl(10.0, 8.0, 10.0)))
    add("charge_tl_zero_q", () -> _te(charge_tl(0.0, 10.0, 500.0)))
    add("charge_ltl_zero_d", () -> _te(charge_ltl(0.5, 8.0, 0.0)))
    # the struct forms, Int and Float fields, NamedTuple and DataFrameRow
    shT = (f = 20.0, s = 40/9, a = 1.0, v = 25_000.0, h = 0.30, d = 532.0)
    trT = (r = rTL32, Kwt = 25.0, Kcu = 2750.0, ppi = ppiTL32)
    add("struct_forms_namedtuple", () -> _te((charge_tl(1.0, shT, trT), charge_ltl(1.0, shT; ppi = 177.4), rate_ltl(1.0, shT; ppi = 177.4), maxpayld(shT, trT))))
    add("struct_forms_dataframerow", () -> (row = DataFrame([shT])[1, :];
        _te((charge_tl(1.0, row, trT), charge_ltl(1.0, row; ppi = 177.4), rate_ltl(1.0, row; ppi = 177.4), maxpayld(row, trT)))))
    # the default call shapes (no r, ppi and Kwt at their defaults)
    add("charge_tl_defaults", () -> _te((charge_tl(10.0, 8.0, 500.0), charge_tl(30.0, 8.0, 500.0), charge_tl(10.0, 8.0, 10.0))))
    add("D5_charge_tl_ppi_without_r", () -> _te(charge_tl(10.0, 8.0, 500.0; ppi = 131.0)))              # v0.2.8: r stays 2.00
    add("charge_tl_ppi_without_r_short", () -> _te(charge_tl(10.0, 8.0, 10.0; ppi = 131.0)))
    add("charge_tl_r_and_ppi_passed", () -> _te(charge_tl(5.0, 10.0, 10.0; r = 3.0, ppi = 131.0)))        # an explicit r is never re-escalated (D5)
    add("charge_tl_r_passed_default_ppi", () -> _te(charge_tl(5.0, 10.0, 10.0; r = 3.0)))

    # ================= 3.3 Ex. 1: the minimum-TLC size =================
    f33, v33, h33, α33 = 20, 25_000, 0.3, 1
    ppiTL33, ppiLTL33 = 131.0, 177.4
    rTL33 = 2.00ppiTL33/102.7
    tr33 = (r = rTL33, Kwt = 25, Kcu = 2750, ppi = ppiTL33)
    shdf33() = DataFrame(f = f33, s = 40/9, a = α33, v = v33, h = h33, d = 532)
    add("l33_ftl_cost", () -> (qm = maxpayld(40/9; Kwt = 25, Kcu = 2750);
        c = charge_tl(qm, 40/9, 532; r = rTL33, Kwt = 25, Kcu = 2750, ppi = ppiTL33);
        _te((qm, c, totlogcost(qm, c, f33, α33, v33, h33)))))
    add("l33_min_charges_at_qmax", () -> (qm = 11.0;
        _te((charge_tl(qm, 40/9, 532; r = rTL33, Kwt = 25, Kcu = 2750, ppi = ppiTL33), charge_ltl(0.8, 40/9, 532; ppi = ppiLTL33)))))
    add("l33_minTLC_both_v25k", () -> _te(minTLC(first(shdf33()), tr33, ppiLTL33)))                        # Code block 12
    add("l33_minTLC_tl_v25k", () -> _te(minTLC(first(shdf33()), tr33)))
    add("l33_minTLC_ltl_v25k", () -> _te(minTLC(first(shdf33()), nothing, ppiLTL33)))
    add("l33_minTLC_namedtuple_v25k", () -> _te(minTLC(shT, tr33, ppiLTL33)))
    sh85 = merge(shT, (v = 85_000.0,))
    add("l33_minTLC_both_v85k", () -> _te(minTLC(sh85, tr33, ppiLTL33)))
    add("l33_minTLC_ltl_v85k", () -> _te(minTLC(sh85, nothing, ppiLTL33)))
    add("l33_minTLC_degenerate", () -> _te(minTLC(shT)))
    add("l33_totlogcost_forms", () -> (p = (f = 100.0, a = 0.5, v = 1000.0, h = 0.25);
        _te((totlogcost(5.0, 450.0, 100.0, 0.5, 1000.0, 0.25), totlogcost(5.0, 450.0, p), totlogcost(5.0, 0.0, 100.0, 0.5, 1000.0, 0.25),
             totlogcost([1.0, 5.0, 10.0], 450.0, 100.0, 0.5, 1000.0, 0.25)))))
    function l33_two_products()                                                                            # Code blocks 13 and 14
        sh = DataFrame(f = f33, s = 40/9, a = α33, v = v33, h = h33, d = 532)
        push!(sh, first(sh))
        sh[2, [:f, :s, :v]] = [80, 32.16, 5000]
        sh.qmax = [maxpayld(row, tr33) for row in eachrow(sh)]
        transform!(sh, AsTable(:) => ByRow(row -> minTLC(row, tr33, ppiLTL33)) => AsTable)
        return sh
    end
    add("l33_two_products_minTLC", () -> (sh = l33_two_products(); _te(sh[:, [:f, :s, :v, :qmax, :qᵒ, :TLCᵒ, :isLTL]])))
    add("l33_aggregate_fields", () -> (sh = l33_two_products(); _aggfields(aggshmt(sh[:, [:f, :s, :a, :v, :h, :d]]))))
    add("l33_aggregate_minTLC_tl", () -> (sh = l33_two_products(); ash = aggshmt(sh[:, [:f, :s, :a, :v, :h, :d]]);
        _te((maxpayld(ash, tr33), minTLC(ash, tr33)))))
    add("l33_aggregate_minTLC_both", () -> (sh = l33_two_products(); ash = aggshmt(sh[:, [:f, :s, :a, :v, :h, :d]]);
        _te(minTLC(ash, tr33, ppiLTL33))))
    # Ex. 2: the interval-constrained full truckload (Code blocks 16 and 17)
    d2_, s2_, Kwt2, Kcu2, r2_, f2_, v2_ = 750, 10, 24, 3000, 2, 200, 5000
    h2_ = 0.11 + 0.3/1.5
    add("l33_ex2_ftl", () -> (qm = maxpayld(s2_; Kwt = Kwt2, Kcu = Kcu2); c = charge_tl(qm, s2_, d2_; r = r2_, Kwt = Kwt2, Kcu = Kcu2);
        _te((qm, c, totlogcost(qm, c, f2_, 1, v2_, h2_)))))
    add("l33_ex2_two_weeks", () -> (qm = maxpayld(s2_; Kwt = Kwt2, Kcu = Kcu2); nF = f2_/qm; nmin = 1/(2*7/365.25);
        q = f2_/max(nF, nmin); c = charge_tl(q, s2_, d2_; r = r2_, Kwt = Kwt2, Kcu = Kcu2);
        _te((q, c, totlogcost(q, c, f2_, 1, v2_, h2_)))))

    # ================= 3.4 Ex. 1: the I-40 DC =================
    add("l34_ex1_shipments", () -> (sh = _ex34_shipments()[1]; tr = _ex34_shipments()[2]; _te(sh)))
    add("l34_ex1_uc_statesville", () -> (sh = _ex34_shipments()[1]; tr = _ex34_shipments()[2]; r = ref_tlc_uc(_shd34(sh, 150), tr); _te(r)))   # supplier B sits at d = 0
    add("l34_ex1_uc_off_site", () -> (sh = _ex34_shipments()[1]; tr = _ex34_shipments()[2]; r = ref_tlc_uc(_shd34(sh, 100), tr); _te(r)))
    add("l34_ex1_uc_grid", () -> (sh = _ex34_shipments()[1]; tr = _ex34_shipments()[2]; _te([ref_tlc_uc(_shd34(sh, x), tr).TLC for x in (0, 50, 100, 150, 151, 200, 270, 420, 450)])))
    add("l34_ex1_uc_costs", () -> (sh = _ex34_shipments()[1]; tr = _ex34_shipments()[2]; shUC = _shd34(sh, 150);
        shUC.qmax = [maxpayld(r, tr) for r in eachrow(shUC)]; shUC.qᵒ = ref_tlc_uc(shUC, tr).q;
        shUC.TLCᵒ = [totlogcost(r.qᵒ, ref_c0(r.qᵒ, r, tr), r) for r in eachrow(shUC)];
        _te(shUC[:, [:d, :qmax, :qᵒ, :TLCᵒ]])))
    add("l34_ex1_xd_statesville", () -> (sh = _ex34_shipments()[1]; tr = _ex34_shipments()[2]; shXD = _shd34(sh, 150);
        shXD.qmax = [maxpayld(r, tr) for r in eachrow(shXD)]; shXD[1:2, :a] .= 0;
        tmax = minimum(shXD.qmax[1:2] ./ shXD.f[1:2]); xd = ref_tlc_xd(shXD, tr, 1/365.25, tmax);
        _te((tmax, xd.TLC, xd.t, xd.q))))
    add("l34_ex1_ftl_statesville", () -> (sh = _ex34_shipments()[1]; tr = _ex34_shipments()[2]; shd = _shd34(sh, 150);
        qm = [maxpayld(r, tr) for r in eachrow(sh)];
        _te(sum(totlogcost(qm[i], ref_c0(qm[i], r, tr), r) for (i, r) in enumerate(eachrow(shd))))))
    add("CR15_l34_ex1_raw_charges_statesville", () -> (sh = _ex34_shipments()[1]; tr = _ex34_shipments()[2]; shd = _shd34(sh, 150);
        qm = [maxpayld(r, tr) for r in eachrow(sh)];                       # supplier B sits at d = 0: charge_tl itself, not c0
        _te([charge_tl(qm[i], r, tr) for (i, r) in enumerate(eachrow(shd))])))
    # Ex. 2: Memphis
    add("l34_ex2_direct", () -> (m = _ex34_memphis();
        res = [minTLC(r, m.tr2, m.ppiLTL) for r in eachrow(m.shD)]; _te((res, m.shD.qmax))))
    add("l34_ex2_uncoordinated", () -> (m = _ex34_memphis();
        res = [minTLC(r, m.tr2, m.ppiLTL) for r in eachrow(m.sh2)]; _te((res, m.sh2.d, m.sh2.qmax))))
    add("l34_ex2_uc_total", () -> (m = _ex34_memphis(); _te(ref_tlc_uc(m.sh2, m.tr2, m.ppiLTL))))
    add("l34_ex2_xd", () -> (m = _ex34_memphis(); shXD2 = m.sh2[:, :]; shXD2[m.idxin2, :a] .= m.αS;
        tmax2 = minimum(shXD2.qmax[m.idxin2] ./ shXD2.f[m.idxin2]);
        xd2 = ref_tlc_xd(shXD2, m.tr2, 1/365.25, tmax2, m.ppiLTL);
        qXD = xd2.q;
        TLCXD = [totlogcost(qXD[i], ref_c0(qXD[i], r, m.tr2, m.ppiLTL), r) for (i, r) in enumerate(eachrow(shXD2))];
        nLTL = count(((i, r),) -> ref_c0(qXD[i], r, m.tr2, m.ppiLTL) < charge_tl(qXD[i], r, m.tr2), enumerate(eachrow(shXD2)));
        _te((tmax2, xd2.TLC, xd2.t, qXD, TLCXD, nLTL))))

    # ================= 4.3 Ex. 6: Lecture 3.3's shipment again =================
    s43 = 40/9
    tr43 = (r = 2.00*131.0/102.7, Kwt = 25, Kcu = 2750, ppi = 131.0)
    add("l43_charge_tl_qmax", () -> _te(charge_tl(maxpayld(s43; Kwt = 25, Kcu = 2750), s43, 532; r = tr43.r, Kwt = 25, Kcu = 2750, ppi = 131.0)))
    add("l43_minTLC_v25k", () -> _te(minTLC((f = 20, s = s43, a = 1/2, v = 25000, h = 0.3, d = 532), tr43, 177.4)))
    add("l43_minTLC_v85k", () -> _te(minTLC((f = 20, s = s43, a = 1/2, v = 85000, h = 0.3, d = 532), tr43, 177.4)))

    # ================= HW 3 =================
    # Q2
    ppiTL2, ppiLTL2 = 162.1, 203.7
    trq2 = (r = 2ppiTL2/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL2)
    shq2 = (f = 75, s = 12, a = 1, v = 12_000, h = 0.3, d = 625)
    add("hw3_q2_minTLC", () -> _te((minTLC(shq2, trq2, ppiLTL2), minTLC(shq2, nothing, ppiLTL2).TLCᵒ, minTLC(shq2, trq2))))
    add("hw3_q2_one_week", () -> (cur = minTLC(shq2, trq2, ppiLTL2); nmin = 1/(7/365.25);
        q1wk = shq2.f/max(shq2.f/cur.qᵒ, nmin); cTL = charge_tl(q1wk, shq2, trq2); cLTL = charge_ltl(q1wk, shq2; ppi = ppiLTL2);
        _te((q1wk, cTL, cLTL, totlogcost(q1wk, min(cTL, cLTL), shq2)))))
    add("hw3_q2_grid_minimum", () -> (TLCq(q) = totlogcost(q, charge_tl(q, shq2, trq2), shq2);
        qs = range(0.1, maxpayld(shq2, trq2); length = 2000); _te((minimum(TLCq.(qs)), maxpayld(shq2, trq2)))))
    # Q4
    add("hw3_q4_shipments", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; p = _hw3_q4()[3]; _te(sh4)))
    add("hw3_q4_independent", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3]; _te([minTLC(r, tr, ppiL) for r in eachrow(sh4)])))
    add("hw3_q4_aggregate_fields", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3];
        _te([_aggfields(aggshmt(sh4[idx, :])) for idx in ([1, 2], [1, 3], [2, 3], [1, 2, 3])])))
    for (nm, idx) in (("12", [1, 2]), ("13", [1, 3]), ("23", [2, 3]), ("123", [1, 2, 3]))
        add("CR14_hw3_q4_aggshmt_TLC_$nm", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3]; _te(minTLC(aggshmt(sh4[idx, :]), tr))))
    end
    add("CR14_hw3_q4_cheapest_plan", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3]; ind = [minTLC(r, tr, ppiL) for r in eachrow(sh4)];
        ash = aggshmt(sh4[[2, 3], :]); ra = minTLC(ash, tr);
        _te((ra, ra.TLCᵒ + ind[1].TLCᵒ, sh4.f[2:3] .* ra.qᵒ ./ ash.f))))
    add("hw3_q4_by_product", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3];                                              # aggx: v h exact
        _te([(a = aggshmt(sh4[idx, :]); vh = sum(sh4.f[idx] .* sh4.v[idx] .* sh4.h[idx])/a.f;
              minTLC(merge(a, (v = vh, h = 1.0)), tr)) for idx in ([1, 2], [1, 3], [2, 3], [1, 2, 3])])))
    add("hw3_q4_closed_form_size", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3]; r2 = sh4[2, :];
        _te((min(sqrt(r2.f*max(tr.r*r2.d, mincharge_tl(; ppi = tr.ppi)) / (r2.a*r2.v*r2.h)), maxpayld(r2, tr)), minTLC(r2, tr, ppiL).qᵒ))))
    # Q5
    add("hw3_q5_shipments", () -> (q = _hw3_q5(); _te((q.shS, q.shR[:, names(q.shS)]))))
    add("hw3_q5_uc_projection", () -> (q = _hw3_q5(); sh5 = vcat(q.shS, q.shR[:, names(q.shS)]); _te(ref_tlc_uc(sh5, q.tr, q.ppiLTL))))
    add("hw3_q5_xd_projection", () -> (q = _hw3_q5(); sh5 = vcat(q.shS, q.shR[:, names(q.shS)]); idxin = 1:nrow(q.shS);
        shXD = copy(sh5); shXD[idxin, :a] .= q.αS; shXD.qmax = [maxpayld(r, q.tr) for r in eachrow(shXD)];
        tmax = minimum(shXD.qmax[idxin] ./ shXD.f[idxin]); xd = ref_tlc_xd(shXD, q.tr, 1/365.25, tmax, q.ppiLTL);
        _te((tmax, xd.TLC, xd.t))))
    byprod(q, j) = (ag = aggshmt(DataFrame(f = q.F[:, j], s = q.s, a = q.αC, v = q.v, h = q.h, d = q.dR[j]));
                    merge(ag, (v = sum(q.F[:, j] .* q.v .* q.h)/sum(q.F[:, j]), h = 1.0)))
    add("CR14_hw3_q5_by_product_vcat_as_the_key_writes_it", () -> (q = _hw3_q5();                           # HW 3 Q5's `shP` line
        shP = vcat(q.shS, DataFrame([byprod(q, j) for j in 1:size(q.F, 2)])); _te(ref_tlc_uc(shP, q.tr, q.ppiLTL))))
    add("hw3_q5_by_product_vcat_intersect", () -> (q = _hw3_q5();                                         # the same, with the one-line fix
        shP = vcat(q.shS, DataFrame([byprod(q, j) for j in 1:size(q.F, 2)]); cols = :intersect); _te(ref_tlc_uc(shP, q.tr, q.ppiLTL))))
    add("hw3_q5_by_product_xd", () -> (q = _hw3_q5(); shP = vcat(q.shS, DataFrame([byprod(q, j) for j in 1:size(q.F, 2)]); cols = :intersect);
        idxin = 1:nrow(q.shS); shPX = copy(shP); shPX[idxin, :a] .= q.αS;
        shPX.qmax = [maxpayld(r, q.tr) for r in eachrow(shPX)];
        tmax = minimum(shPX.qmax[idxin] ./ shPX.f[idxin]);
        xd = ref_tlc_xd(shPX, q.tr, 1/365.25, tmax, q.ppiLTL); _te((xd.TLC, xd.t))))
    # other aggregate shapes of HW 3
    add("ta_hw3_aggregate_subset_columns", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3]; a = aggshmt(sh4[[1, 2, 3], [:f, :s, :a, :v, :h, :d]]);
        _te((_aggfields(a), minTLC(a, tr).TLCᵒ > 0))))
    add("CR14_ta_hw3_aggregate_subset_columns_TLC", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3]; a = aggshmt(sh4[[1, 2, 3], [:f, :s, :a, :v, :h, :d]]);
        _te(minTLC(a, tr))))
    add("ta_hw3_minTLC_tl_only_namedtuple", () -> (sh4 = _hw3_q4()[1]; tr = _hw3_q4()[2]; ppiL = _hw3_q4()[3]; _te(minTLC((f = 2.0, s = 8.0, a = 0.5, v = 6000.0, h = 0.3, d = 400.0), tr))))

    # ================= Project 3 =================
    add("proj3_shipments", () -> (p = _proj3(); _te((p.shIn, p.shOut))))
    add("proj3_uc_in", () -> (p = _proj3(); shUC = copy(p.shIn); shUC.a .= p.αS + 0.5; _te(ref_tlc_uc(shUC, p.tr, p.ppiLTL))))
    add("proj3_uc_out_projection", () -> (p = _proj3(); _te(ref_tlc_uc(p.shOut, p.tr, p.ppiLTL))))
    add("proj3_xd_all", () -> (p = _proj3(); sh = vcat(p.shIn, p.shOut); qm = [maxpayld(r, p.tr) for r in eachrow(p.shIn)];
        tcap = minimum(qm ./ p.shIn.f); xd = ref_tlc_xd(sh, p.tr, 1/365.25, tcap, p.ppiLTL); _te((tcap, xd.TLC, xd.t))))
    add("proj3_minTLC_each_product", () -> (p = _proj3(); _te([minTLC(r, p.tr, p.ppiLTL) for r in eachrow(p.shIn)])))
    add("proj3_aggregate_delivery_fields", () -> (p = _proj3();
        _te([_aggfields(aggshmt(DataFrame(f = p.F[:, j], s = p.s, a = p.αC, v = p.v, h = p.h, d = p.dC[j]))) for j in 1:3])))
    add("CR14_proj3_aggregate_delivery_minTLC", () -> (p = _proj3();
        _te([minTLC(aggshmt(DataFrame(f = p.F[:, j], s = p.s, a = p.αC, v = p.v, h = p.h, d = p.dC[j])), p.tr, p.ppiLTL) for j in 1:3])))
    add("proj3_charge_per_delivery", () -> (p = _proj3(); _te([charge_tl(2.0, r, p.tr) for r in eachrow(p.shOut)])))
    add("proj3_ltl_vs_tl", () -> (p = _proj3(); _te([(ref_c0(1.5, r, p.tr, p.ppiLTL) < charge_tl(1.5, r, p.tr)) for r in eachrow(p.shOut)])))
    add("N3_proj3_near_store_multi_truck", () -> (p = _proj3(); r = p.shOut[1, :]; _te((r.d, maxpayld(r, p.tr), charge_tl(40.0, r, p.tr)))))
    add("proj3_far_store_multi_truck", () -> (p = _proj3(); r = p.shOut[3, :]; _te(charge_tl(40.0, r, p.tr))))

    # ================= findings and rulings: the cases a ruled item moves =================
    add("N3_charge_tl_two_trucks_short_haul", () -> _te(charge_tl(30.0, 30.0, 10.0)))                      # v0.2.8: 90.0
    add("N3_charge_tl_three_trucks_short_haul", () -> _te(charge_tl(30.0, 8.0, 5.0)))
    add("N3_charge_tl_two_trucks_default_r", () -> _te(charge_tl(30.0, 30.0, 20.0)))
    add("N4_charge_ltl_zero_q", () -> _te(charge_ltl(0.0, 10.0, 500.0)))                                  # v0.2.8: the minimum, 50.84
    add("N4_charge_ltl_zero_q_short", () -> _te(charge_ltl(0.0, 10.0, 100.0)))
    add("CR15_charge_tl_zero_d", () -> _te(charge_tl(10.0, 8.0, 0.0)))                                    # v0.2.8: the 45 minimum
    add("CR15_charge_tl_zero_d_struct", () -> _te(charge_tl(10.0, (s = 8.0, d = 0.0), (r = 2.0, Kwt = 25.0, Kcu = 2750.0, ppi = 102.7))))
    sh0 = (f = 20.0, s = 8.0, a = 0.5, v = 1000.0, h = 0.25, d = 0.0)
    tr0 = (r = 2.0, Kwt = 25.0, Kcu = 2750.0, ppi = 102.7)
    add("CR15_minTLC_zero_d_tl", () -> _te(minTLC(sh0, tr0)))
    add("CR15_minTLC_zero_d_both", () -> _te(minTLC(sh0, tr0, 104.2)))
    add("CR15_minTLC_zero_d_ltl", () -> _te(minTLC(sh0, nothing, 104.2)))
    add("N2_aggshmt_q_without_f", () -> (df = DataFrame(q = [10.0, 20.0, 15.0], s = [8.0, 10.0, 6.0], v = [1000.0, 1500.0, 800.0],
                                                         h = [0.25, 0.25, 0.25], a = [0.5, 0.5, 0.5]); a = aggshmt(df);
        _te((hasproperty(a, :f), hasproperty(a, :q) ? a.q : nothing, a.f))))
    add("aggshmt_q_without_f_means", () -> (df = DataFrame(q = [10.0, 20.0, 15.0], s = [8.0, 10.0, 6.0], v = [1000.0, 1500.0, 800.0],
                                                            h = [0.25, 0.25, 0.25], a = [0.5, 0.5, 0.5]); _aggfields(aggshmt(df), (:s, :v, :h, :a))))
    add("aggshmt_docstring", () -> (df = DataFrame(f = [100, 200, 150], s = [8, 10, 6], v = [1000, 1500, 800], h = [0.25, 0.25, 0.25],
                                                    a = [0.5, 0.5, 0.5], d = [532, 532, 532]); _aggfields(aggshmt(df))))
    add("aggshmt_passes_other_fields", () -> (df = DataFrame(f = [100.0, 200.0], s = [8.0, 12.0], v = [1000.0, 1500.0], h = [0.25, 0.30],
                                                              a = [0.5, 0.6], d = [532.0, 532.0], tag = ["x", "y"]); a = aggshmt(df);
        _te((a.tag, _aggfields(a)))))
    add("CR14_totlogcost_unequal_h_aggregate", () -> (df = DataFrame(f = [100.0, 200.0], s = [8.0, 10.0], v = [1000.0, 1500.0],
                                                                      h = [0.10, 0.30], a = [0.5, 0.5], d = [532.0, 532.0]);
        _te(totlogcost(2.0, 0.0, aggshmt(df)))))                                                          # v0.2.8: 311.11; the shipments' own terms sum to 333.33
    add("totlogcost_equal_h_aggregate", () -> (df = DataFrame(f = [100.0, 200.0, 150.0], s = [8.0, 10.0, 6.0], v = [1000.0, 1500.0, 800.0],
                                                                h = [0.25, 0.25, 0.25], a = [0.5, 0.5, 0.5]); a = aggshmt(df);
        _te((totlogcost(5.0, 450.0, a), totlogcost(5.0, 450.0, a.f, a.a, a.v, a.h)))))
    add("N31_totlogcost_zero_q_positive_charge", () -> _te(totlogcost(0.0, 100.0, 100.0, 0.5, 1000.0, 0.25)))   # v0.2.8: 4.5e18, not Inf
    add("totlogcost_zero_q_zero_charge", () -> _te(totlogcost(0.0, 0.0, 100.0, 0.5, 1000.0, 0.25)))
    add("N31_minTLC_ltl_beyond_range", () -> _te(minTLC((f = 20.0, s = 40/9, a = 1.0, v = 25_000.0, h = 0.30, d = 4000.0), nothing, 177.4)))
    add("N31_minTLC_both_beyond_range", () -> _te(minTLC((f = 20.0, s = 40/9, a = 1.0, v = 25_000.0, h = 0.30, d = 4000.0), tr33, 177.4)))
    add("minTLC_cube_bound_binds", () -> _te(minTLC((f = 500.0, s = 3.0, a = 0.5, v = 50_000.0, h = 0.3, d = 900.0), nothing, 177.4)))   # 650 s/2000 < 5
    add("minTLC_weight_bound_binds", () -> _te(minTLC((f = 500.0, s = 40.0, a = 0.5, v = 50_000.0, h = 0.3, d = 900.0), nothing, 177.4)))   # 5 ton ceiling

    return cases
end
