# routing_pin_cases.jl -- the routing calls the course makes today, as pin cases (PCV K7a, plan
# principle 9). Every case is a (name, thunk) pair; the thunk returns one line of text, the value encoded
# to 12 significant digits. The calls and the inputs come from the course's released lectures and
# homework (read only): Lecture 5.1's tour 2-opt (the saved sequences of Matlog's traces, Ex. 3's six
# nodes, an NC location sequence), Lecture 5.2 Ex. 1, 2, 3, 6(a) and 8, Lecture 5.3's Clarke-Wright
# example and its 30 NC shipments, HW 5's Q1 (Ajax's 100 customers) and the 2008 qual's four shipments.
#
# `mincostinsert`, `twoopt` on tours and on route vectors, `savings`, `pairwisesavings`, `rteTC`,
# `rte2loc` and `isorigin` are called exactly as the course calls them. A case whose value a ruled item
# moves is listed in RPIN_MOVED with the ID of the commit that moves it; the fixture row is rewritten in
# that commit and the message lists the case. Any other case must keep its value.
#
# Stand-ins, said once: HW 5's Q1 road-time matrix is the great-circle distance times 1.2 at 45 mph
# (the key builds it from the FAF5 network, which K5 and K8 cover); the capacity cost handle is the
# key's own, verbatim, without the `rteTC_vrp` schedule. The distance matrices of the
# oracle cases are MATLAB's own, so the cases do not depend on a distance formula.

using Logjam
using DataFrames

isdefined(@__MODULE__, :ORACLE_DIR) || include(joinpath(@__DIR__, "oracle_helpers.jl"))   # _readoracle, _ivec, _fvec, _sc, _cells

# ---- encoding ------------------------------------------------------------------------------
_rp(x::Missing) = "missing"
_rp(x::Bool) = string(x)
_rp(x::Integer) = string(x)
_rp(x::AbstractFloat) = isfinite(x) ? repr(round(Float64(x); sigdigits = 12)) : repr(Float64(x))   # 12 digits: last-place differences under --check-bounds=yes
_rp(x::Symbol) = ":" * String(x)
_rp(x::AbstractString) = repr(String(x))
_rp(x::Nothing) = "nothing"
_rp(x::Tuple) = "(" * join((_rp(v) for v in x), ",") * ")"
# A named tuple is encoded as the tuple of its values: `mincostinsert`, `twoopt` and `pairwisesavings`
# return `(rte, TC)`, `(i, j, s)` as named tuples since K7c (V rule 2, ruled), which
# destructure and index as the tuples of v0.2.8 did, so a pin compares the values and not the container.
# The names are asserted in test_routetools.jl.
_rp(x::NamedTuple) = _rp(Tuple(x))
_rp(x::AbstractArray) = string(size(x)) * "[" * join((_rp(v) for v in x), ",") * "]"

# a case whose value a ruled item moves: name => the ID of the commit that moves it. Filled in as the
# items land; the generator refuses to rewrite a differing row that is not listed here.
const RPIN_MOVED = Dict{String,String}(
    # CR 38: mincostinsert no longer tries i = j = m + 1 ([..., k, k], not a route)
    "sg_p24_qual08_mincostinsert_pairs" => "CR38",
    "l52_ex8_mincostinsert_chain" => "CR38",
    "l52_ex8_insert_and_improve" => "CR38",
    # CR 37, CR 54: twoopt of a route vector reverses over every stop, ends included, and skips a
    # reversal that empties the truck (the course's own twoopt_rte; these cases call the export)
    "l52_ex1_twoopt_route" => "CR37_CR54",
    "l52_ex2_twoopt_route_from_insertion" => "CR37_CR54",
    "l52_ex2_twoopt_route_from_identity" => "CR37_CR54",
    "l52_ex2_twoopt_route_from_random" => "CR37_CR54",
    "l53_vrp_capacity_savings_twoopt" => "CR37_CR54+CR39",
    "l53_vrp_maxTC_savings_twoopt" => "CR37_CR54+CR39",
    # CR 39: savings makes Matlog's three merges and none that does not save; the formed routes come
    # first and the shipments in no merge follow as routes of their own (CR 57 then drops those)
    "l53_cw_savings_twoopt" => "CR39",
    "l53_vrp_nocap_pairwisesavings_savings" => "CR39",
    "l53_vrp_nocap_twoopt_route" => "CR39",
    "l52_ex8_savings_twoopt" => "CR39+CR57",
    "hw5q1_savings_twoopt" => "CR39+CR57",
    # CR 57: savings returns the routes it forms only; a shipment in no merge is on none of them
    # CR 42: rteTC reads Kwt, Kcu and maxTC on the truck (Inf for a route that breaks one, and for a depot
    # route that returns to the depot midway); CR 43: no cost between two stops at one location (a plain
    # rteTC, which has no limit on the truck, still prices a route that returns to its depot midway)
    "rtc_cw_truck_shapes" => "CR42",
    "rtc_53_capacity_fields_ignored" => "CR42",
    "rtc_53_nonzero_diagonal_time_matrix" => "CR42+CR43",
)

# CR 58 (K7c): a route the exported mincostinsert, twoopt or savings returns lists the
# lower-numbered of two neighboring loadings (or unloadings) first when they trade places at exactly the same
# cost. Only the order moves; every cost in these cases is unchanged (the commit checked each).
for n in ("l52_ex2_mincostinsert_chain", "l52_ex2_savings", "l52_ex2_twoopt_route_from_insertion",
          "l52_ex2_twoopt_route_from_random", "l52_ex3_savings_and_twoopt", "l53_cw_savings_twoopt",
          "l53_vrp_nocap_pairwisesavings_savings", "l53_vrp_nocap_twoopt_route", "l53_vrp_capacity_savings_twoopt",
          "l53_vrp_maxTC_savings_twoopt", "l52_ex8_mincostinsert_chain", "l52_ex8_savings_twoopt",
          "l52_ex8_insert_and_improve", "hw5q1_savings_twoopt")
    RPIN_MOVED[n] = haskey(RPIN_MOVED, n) ? RPIN_MOVED[n] * "+CR58" : "CR58"
end

# ---- the course's data --------------------------------------------------------------------------
function _rp_matrix(file, cols)
    rows = [split(l, ",") for l in filter(!isempty, readlines(joinpath(@__DIR__, "data", file))[2:end])]
    return [parse(Float64, r[c]) for r in rows, c in cols]
end
_rp_xy54() = _rp_matrix("shmtNC30-xy.csv", 1:2)            # 5.2 Ex. 8: 54 places
# 5.2 Ex. 8: the 30 shipments, and the first start of its randomized insertion
const RPIN_SH30 = DataFrame(
    b = [15, 26, 23, 53, 17, 3, 39, 47, 44, 45, 43, 8, 29, 34, 38, 41, 18, 40, 1, 11, 7, 30, 33, 22, 20, 19, 16, 48, 37, 14],
    e = [42, 27, 40, 51, 32, 27, 50, 28, 35, 10, 2, 12, 39, 52, 24, 36, 27, 13, 5, 4, 6, 49, 9, 25, 46, 31, 21, 10, 54, 13])
const RPIN_L30 = [10, 2, 9, 14, 18, 29, 6, 12, 27, 30, 1, 22, 17, 15, 5, 11, 19, 16, 8, 26, 28, 20, 25, 13, 24, 23, 7, 3, 4, 21]
_rp_D30() = (X = _rp_xy54(); dists(X, X, :mi) * 1.2)

# 5.3 Ex. 1's Clarke-Wright example (5-rte-3.qmd:472-478, Code block 4)
const RPIN_CCW = [ 0  40  48  38  33  48
                  40   0  87  46  65  75
                  48  87   0  67  41  47
                  38  46  67   0  70  34
                  33  65  41  70   0  69
                  48  75  47  34  69   0]
const RPIN_QCW = [0, 8, 5, 4, 7, 6]
const RPIN_KCW = 15

# the 2008 qual's four shipments
const RPIN_DG = [  0  21 132 146 204 221 230 209
                  21   0 111 124 183 199 210 190
                 132 111   0  19  73  89 110  98
                 146 124  19   0  59  79 110 102
                 204 183  73  59   0  29  83  90
                 221 199  89  79  29   0  58  71
                 230 210 110 110  83  58   0  26
                 209 190  98 102  90  71  26   0]
const RPIN_SHG = DataFrame(b = [1, 2, 3, 5], e = [6, 4, 7, 8])
# 5.2 Ex. 6(a): three shipments at $1 a mile
const RPIN_D6 = [  0 300  30 280  60 335
                 300   0 280  30 335  60
                  30 280   0 250  90 340
                 280  30 250   0 340  90
                  60 335  90 340   0 275
                 335  60 340  90 275   0]
const RPIN_SH6 = DataFrame(b = [1, 3, 5], e = [2, 4, 6])

# HW 5 Q1 (Ajax): the customers, the shipments, the tractor-trailer, the route cost of the key (verbatim)
function _hw5q1()
    da = _rp_matrix("hw5data-ajax.csv", 1:4)               # lat, lon, wt, cu
    dms(d, m, s) = d + m/60 + s/3600
    XY = [-dms(84, 18, 55) dms(33, 50, 55); da[:, 2] da[:, 1]]
    tra = (b = 1, e = 1, Kwt = 25, Kcu = 2750)
    sha = DataFrame(b = 1, e = 2:size(XY, 1), q = da[:, 3] / 2000, s = da[:, 3] ./ da[:, 4])
    sha.tU = fill(15/60, nrow(sha))
    tL = 30/60
    Ta = 1.2dists(XY, XY, :mi) / 45                         # h; stand-in for the FAF5 road times
    function rTTa(rte, T = Ta)
        idx = unique(rte)
        TT = rteTC(rte, sha, T, tra) + sum(sha.tU[idx])
        wtfeas = sum(sha.q[idx]) <= tra.Kwt
        cufeas = sum(2000sha.q[idx] ./ sha.s[idx]) <= tra.Kcu
        tmfeas = TT + tL <= 12
        return wtfeas && cufeas && tmfeas ? TT : Inf
    end
    return (; sha, tra, Ta, rTTa)
end

# a route cost with a capacity, as 5.3's Code block 4 closes it
function _cw()
    shcw = DataFrame(b = ones(Int, 5), e = [2:6;], q = RPIN_QCW[2:6])
    tr = (b = 1, e = 1)
    h(rte) = (TC = rteTC(rte, shcw, RPIN_CCW, tr); sum(shcw.q[unique(rte)]) <= RPIN_KCW ? TC : Inf)
    return (; shcw, tr, h)
end

# makeRouting3.m's 30 NC shipments from the depot, with weight and cube (Exs. 2 and 4), optionally maxTC
function _vrp53(withmax = false)
    d = _readoracle("routing_53_vrp"); n = size(d["D"], 1) - 1
    q, s = _fvec(d, "q"), _fvec(d, "s")
    sh = DataFrame(b = fill(1, n), e = 2:n+1, q = q, s = s)
    tr = (b = [1], e = [1]); D = d["D"]; mx = withmax ? _sc(d, "ex4_maxTC") : Inf
    function h(r)
        idx = unique(r); TC = rteTC(r, sh, D, tr)
        return sum(q[idx]) <= 25 && sum(2000 .* q[idx] ./ s[idx]) <= 2750 && TC <= mx ? TC : Inf
    end
    return (; sh, h)
end

# one-truck charge as 5.2 Ex. 9 writes it
_onetruck(sh, D) = r -> max(2.00 * rteTC(r, sh, D), 45.0)

# insert the shipments of L in order by Logjam's mincostinsert, as 5.2 Ex. 2 does (r starts as [L[1], L[1]])
function _mci_chain(L, h)
    r = [L[1], L[1]]
    for k in L[2:end]
        r = mincostinsert(k, r, h)[1]
    end
    return r
end
_mci_trace(L, h) = (r = [L[1], L[1]]; out = [r]; for k in L[2:end]; r = mincostinsert(k, r, h)[1]; push!(out, r); end; out)

# 5.2's insert and improve (mincostinsert then twoopt per shipment) on the two exports
function _insertimprove(L, h)
    r = [L[1], L[1]]
    for k in L[2:end]
        r = mincostinsert(k, r, h)[1]
        r = twoopt(r, _tl(h))[1]
    end
    return r
end

# The route 2-opt keeps a change whose cost is strictly lower, and reversing all the deliveries of a depot
# route changes the cost by zero in exact arithmetic and by about 1e-13 in floating point, so whether it is
# kept depends on the machine's order of summation (`--check-bounds=yes`, Julia 1.12 against 1.13). The
# cases below therefore run the route 2-opt on a cost rounded to 9 places, on which a tie is exact, and
# report each route's cost from the unrounded handle.
_tl(h) = r -> round(h(r); digits = 9)
_t2(r, h) = (rr = twoopt(r, _tl(h))[1]; (rr, h(rr)))
_twoopt_each(R, h) = [twoopt(r, _tl(h))[1] for r in R]
_loadform_like(h, sh) = (R = [twoopt(r, _tl(h))[1] for r in savings(h, sh) if length(r) > 2]; R)

function rtpin_cases()
    cases = Tuple{String,Function}[]
    add(name, f) = push!(cases, (name, f))

    # ---- Lecture 5.1: twoopt on a closed tour (a location sequence), which must not move ----------------
    for nm in ("sfc", "ch", "nn1", "nnb", "rnd1", "rnd2")
        add("l51_twoopt_tour_$nm", () -> (d = _readoracle("tsp_traces"); C = d["C"];
            _rp(twoopt(_ivec(d, nm * "_loc0"), π -> sum(segcost(π, C))))))
    end
    add("l51_ex3_six_node", () -> (d = _readoracle("tsp_traces"); D6_ = d["six_D"];
        _rp(twoopt(_ivec(d, "six_loc0"), π -> sum(segcost(π, D6_))))))
    add("l51_nc_location_sequence", () -> (X = _rp_xy54()[1:30, :]; C = dists(X, X, :mi);
        t0 = vcat(1, 2:2:30, 3:2:30, 1); _rp((t0, twoopt(t0, π -> sum(segcost(π, C)))))))
    add("l51_tour_two_stops", () -> _rp((twoopt([1, 2, 1], π -> sum(segcost(π, [0 5; 5 0]))),
                                         twoopt([1, 2, 3, 1], π -> sum(segcost(π, [0 1 9; 1 0 1; 9 1 0]))))))

    # ---- the route utilities ---------------------------------------------------------------------------
    add("util_isorigin_rte2loc", () -> (d = _readoracle("routing_52_ex1"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        rs = ([1, 1], [1, 2, 2, 1], [1, 2, 3, 1, 2, 3], [3, 1, 2, 2, 1, 3]);
        _rp(([isorigin(r) for r in rs], [rte2loc(r, sh) for r in rs]))))
    add("util_rte2loc_with_truck", () -> (sh = RPIN_SH30[[1, 4], :]; tr = (b = [1], e = [1]);
        _rp((rte2loc([1, 2, 1, 2], sh, tr), rte2loc([1, 2, 1, 2], sh, (b = 3, e = 4))))))
    add("util_rteTC_values", () -> (D = _rp_D30(); sh = RPIN_SH30;
        _rp((rteTC(RPIN_L30[1:4], sh, D), rteTC([1, 1], sh, D), rteTC([1, 2, 2, 1], sh, D), rteTC([1, 2, 1, 2], sh, D, (b = [1], e = [1]))))))

    # ---- Lecture 5.2 Ex. 1: six cities, three shipments --------------------------------------------------
    add("l52_ex1_rteTC", () -> (d = _readoracle("routing_52_ex1"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        h = r -> rteTC(r, sh, d["D"]);
        _rp([h(r) for r in ([1, 1], [2, 2], [3, 3], [1, 1, 2, 2], [1, 2, 2, 1], [1, 2, 1, 2], [1, 2, 3, 1, 2, 3])])))
    add("l52_ex1_mincostinsert_chain", () -> (d = _readoracle("routing_52_ex1"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        h = r -> rteTC(r, sh, d["D"]); r12 = mincostinsert(2, [1, 1], h); r123 = mincostinsert(3, r12[1], h);
        _rp((r12, r123, mincostinsert(1, Int[], h)))))
    add("l52_ex1_pairwisesavings", () -> (d = _readoracle("routing_52_ex1"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        _rp(pairwisesavings(r -> rteTC(r, sh, d["D"]), sh))))
    add("l52_ex1_savings", () -> (d = _readoracle("routing_52_ex1"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        _rp(savings(r -> rteTC(r, sh, d["D"]), sh))))
    add("l52_ex1_twoopt_route", () -> (d = _readoracle("routing_52_ex1"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        h = r -> rteTC(r, sh, d["D"]);
        _rp([_t2(r, h) for r in ([1, 2, 3, 1, 2, 3], [1, 2, 1, 3, 2, 3], [1, 2, 2, 1])])))

    # ---- Lecture 5.2 Ex. 2 and 3: a TSP as shipments, with the depot on the truck -----------------------
    add("l52_ex2_mincostinsert_chain", () -> (d = _readoracle("routing_52_ex2"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        tr = (b = _ivec(d, "tr_b"), e = _ivec(d, "tr_e")); h = r -> rteTC(r, sh, d["D"], tr);
        _rp(_mci_trace(collect(1:nrow(sh)), h))))
    add("l52_ex2_savings", () -> (d = _readoracle("routing_52_ex2"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        tr = (b = _ivec(d, "tr_b"), e = _ivec(d, "tr_e")); _rp(savings(r -> rteTC(r, sh, d["D"], tr), sh))))
    add("l52_ex2_pairwisesavings", () -> (d = _readoracle("routing_52_ex2"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        tr = (b = _ivec(d, "tr_b"), e = _ivec(d, "tr_e")); _rp(pairwisesavings(r -> rteTC(r, sh, d["D"], tr), sh))))
    for (st, tag) in (("mci_r1", "from_insertion"), ("r0_in", "from_identity"), ("rr_in", "from_random"))
        add("l52_ex2_twoopt_route_$tag", () -> (d = _readoracle("routing_52_ex2"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
            tr = (b = _ivec(d, "tr_b"), e = _ivec(d, "tr_e")); _rp(_t2(_ivec(d, st), r -> rteTC(r, sh, d["D"], tr)))))
    end
    add("l52_ex3_savings_and_twoopt", () -> (d = _readoracle("routing_52_ex3"); sh = DataFrame(b = _ivec(d, "b"), e = _ivec(d, "e"));
        tr = (b = [1], e = [1]); h = r -> rteTC(r, sh, d["D"], tr);
        rs = savings(h, sh); ms = _cells(d, "sav_r");
        _rp((rs, _t2(ms[1], h), _t2(rs[1], h)))))

    # ---- Lecture 5.2 Ex. 6(a) and the 2008 qual's four shipments ---------------------------
    add("l52_ex6a_pairwisesavings_savings", () -> (h = r -> rteTC(r, RPIN_SH6, RPIN_D6);
        _rp((pairwisesavings(h, RPIN_SH6), savings(h, RPIN_SH6)))))
    for (nm, sh, D) in (("sg_p24_qual08", RPIN_SHG, RPIN_DG),)
        add("$(nm)_pairwisesavings_savings", () -> (h = _onetruck(sh, D);
            _rp((pairwisesavings(h, sh), savings(h, sh), _loadform_like(h, sh)))))
        add("$(nm)_mincostinsert_pairs", () -> (h = _onetruck(sh, D); n = nrow(sh);
            _rp([mincostinsert(i, [j, j], h) for i in 1:n for j in 1:n if i != j])))
        add("$(nm)_mincostinsert_chain_twoopt", () -> (h = _onetruck(sh, D); r = _mci_chain(collect(1:nrow(sh)), h);
            _rp((r, h(r), _t2(r, h)))))
    end

    # ---- Lecture 5.3 Ex. 1, Clarke-Wright with the capacity in the route cost ------------------------------
    add("l53_cw_savings_twoopt", () -> (c = _cw(); _rp((pairwisesavings(c.h, c.shcw), savings(c.h, c.shcw),
                                                        _twoopt_each(savings(c.h, c.shcw), c.h)))))

    # ---- Lecture 5.3: the 30 NC shipments of makeRouting3.m, with and without the truck's limits ------------
    add("l53_vrp_nocap_pairwisesavings_savings", () -> (d = _readoracle("routing_53_vrp"); n = size(d["D"], 1) - 1;
        sh1 = DataFrame(b = fill(1, n), e = 2:n+1); h1 = r -> rteTC(r, sh1, d["D"], (b = [1], e = [1]));
        _rp((pairwisesavings(h1, sh1), savings(h1, sh1)))))
    add("l53_vrp_nocap_twoopt_route", () -> (d = _readoracle("routing_53_vrp"); n = size(d["D"], 1) - 1;
        sh1 = DataFrame(b = fill(1, n), e = 2:n+1); h1 = r -> rteTC(r, sh1, d["D"], (b = [1], e = [1]));
        ms = _cells(d, "ex1_sav_r"); _rp((_t2(ms[1], h1), _twoopt_each(savings(h1, sh1), h1)))))
    add("l53_vrp_capacity_savings_twoopt", () -> (v = _vrp53(); R = savings(v.h, v.sh);
        _rp((R, v.h.(R), _twoopt_each(R, v.h), _loadform_like(v.h, v.sh)))))
    add("l53_vrp_maxTC_savings_twoopt", () -> (v = _vrp53(true); R = savings(v.h, v.sh);
        _rp((R, v.h.(R), _twoopt_each(R, v.h)))))

    # ---- Lecture 5.2 Ex. 8: the 30 NC shipments ---------------------------
    add("l52_ex8_mincostinsert_chain", () -> (D = _rp_D30(); h = r -> rteTC(r, RPIN_SH30, D);
        r = _mci_chain(RPIN_L30, h); _rp((r, h(r)))))
    add("l52_ex8_pairwisesavings", () -> (D = _rp_D30(); _rp(pairwisesavings(r -> rteTC(r, RPIN_SH30, D), RPIN_SH30))))
    add("l52_ex8_savings_twoopt", () -> (D = _rp_D30(); h = r -> rteTC(r, RPIN_SH30, D);
        R = savings(h, RPIN_SH30); _rp((R, _twoopt_each(R, h)))))
    add("l52_ex8_insert_and_improve", () -> (D = _rp_D30(); h = r -> rteTC(r, RPIN_SH30, D);
        r = _insertimprove(RPIN_L30, h); _rp((r, h(r)))))

    # ---- HW 5 Q1 (Ajax's customers): the key's route-time handle with limits ---------------
    add("hw5q1_savings_twoopt", () -> (q = _hw5q1(); R = savings(q.rTTa, q.sha);
        _rp((R, q.rTTa.(R), _twoopt_each(R, q.rTTa)))))

    # ---- K7b: the route cost and the location sequence in every shape the course passes them -------------
    # 5.3 Ex. 1's depot routes (5-rte-3.qmd:642-649), the truck given with scalar and with vector locations
    # and with fields the scalar rteTC does not read; a route that returns to the depot midway (two trips)
    # is priced, not refused (the decision of CR 43: the scalar rteTC allows it).
    add("rtc_cw_truck_shapes", () -> (c = _cw(); rs = ([1, 1], [2, 2], [1, 2, 1, 2], [1, 2, 2, 1], [5, 4, 3, 5, 4, 3], [1, 1, 2, 2]);
        f(tr) = [rteTC(r, c.shcw, RPIN_CCW, tr) for r in rs];
        _rp((f((b = 1, e = 1)), f((b = [1], e = [1])), f((b = 1, e = 1, Kwt = 15)), f((b = 1, e = 1, maxTC = 10)),
             [rteTC(r, c.shcw, RPIN_CCW) for r in rs]))))
    add("rte2loc_truck_shapes", () -> (c = _cw(); r = [1, 2, 2, 1]; sh = c.shcw;
        _rp((rte2loc(r, sh), rte2loc(r, sh, (b = 1, e = 1)), rte2loc(r, sh, (b = [1], e = [1])), rte2loc(r, sh, (b = 1, e = 1, Kwt = 15)),
             rte2loc(r, sh, (b = Int[], e = Int[])), rte2loc(r, sh, (b = [], e = [])), rte2loc(r, sh, (b = 2, e = 6)),
             rte2loc([1, 1, 2, 2], sh, (b = 1, e = 1)), rte2loc(Int[], sh, (b = 1, e = 1))))))
    # 5.3 Ex. 2-4 (makeRouting3.m's 30 NC shipments): a capacity or maxTC on the truck is not read by rteTC,
    # which returns the distance all the same (Code block 12, 5-rte-3.qmd:996-1002)
    add("rtc_53_capacity_fields_ignored", () -> (d = _readoracle("routing_53_vrp"); D = d["D"]; n = size(D, 1) - 1;
        sh = DataFrame(b = fill(1, n), e = 2:n+1, q = _fvec(d, "q"), s = _fvec(d, "s"));
        rs = (vcat(1:n, 1:n), vcat(1:10, 1:10), [1, 2, 1, 2], [3, 3]);
        trc = (b = 1, e = 1, Kwt = 25, Kcu = 2750); trm = merge(trc, (maxTC = _sc(d, "ex4_maxTC"),));
        _rp(([rteTC(r, sh, D, trc) for r in rs], [rteTC(r, sh, D, trm) for r in rs], [rteTC(r, sh, D, (b = [1], e = [1])) for r in rs],
             [rteTC(r, sh, D) for r in rs]))))
    # 5.3 Ex. 4's route with time windows (5-rte-3.qmd:2064-2074, Code blocks 30 and 31): the window fields
    # of the shipments and of the truck are not read by rteTC; the six orders of its three customers
    add("rtc_54_window_fields_ignored", () -> (T5 = zeros(4, 4); T5[1, 2] = 1; T5[2, 3] = 2; T5[3, 4] = 1; T5[4, 1] = 1;
        sh5 = DataFrame(b = 1, e = [2, 3, 4], tU = 0.0, temin = [8, 12, 15], temax = [11, 14, 18]);
        tr5 = (b = 1, e = 1, tbmin = 6, tbmax = 18, temin = 18, temax = 24);
        ps = ([1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]);
        _rp(([rteTC([p; p], sh5, T5, tr5) for p in ps], rteTC([1, 2, 3, 1, 2, 3], sh5, T5), rte2loc([1, 2, 3, 1, 2, 3], sh5, tr5)))))
    # 5.3 Ex. 6's time matrix (5-rte-3.qmd:2154), `D/50 .+ 5/60`, has five minutes on its DIAGONAL; rteTC today
    # charges C[i, i] between two stops at one location (CR 43 moves this case)
    add("rtc_53_nonzero_diagonal_time_matrix", () -> (d = _readoracle("routing_53_vrp"); D = d["D"]; n = size(D, 1) - 1;
        q = _fvec(d, "q"); T = D / 50 .+ 5/60;
        sh = DataFrame(b = fill(1, n), e = 2:n+1, q = q, s = _fvec(d, "s"), tU = q * 30/60,
                       temin = [fill(7, 15); fill(13, 15)], temax = [fill(17, 15); fill(23, 15)]);
        rs = ([1, 1], [3, 3], [1, 2, 1, 2], [2, 1, 1, 2], [1, 2, 3, 1, 2, 3]); tr = (b = 1, e = 1, Kwt = 25, Kcu = 2750);
        _rp(([rteTC(r, sh, T, tr) for r in rs], [rteTC(r, sh, T) for r in rs], [rteTC(r, sh, T, (b = [1], e = [1])) for r in rs]))))
    return cases
end
