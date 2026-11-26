# test_transtools_v031.jl -- added by PCV WP4 of Logjam v0.3.1 (B6, B9, B10, B11): the transport methods of
# src/transtools.jl that take a table, a column of densities or a truck alone, the LTL estimate's domain named once,
# and the sh/tr contract bound to `Logjam.shtr`. Test spec Sec. 3, with the WP4 brief's correction (`charge_tl(d,
# tr)` is review B's B9, `max(r·d, mincharge_tl(tr))`, not the shipment form at a full load). Equality is `==`, or
# `===` where marked bit-identical; no tolerance is used anywhere in this file. The evidence:
#   1. maxpayld(s::AbstractVector, tr), maxpayld(sh::AbstractDataFrame, tr): the scalar rule maxpayld(s; Kwt, Kcu)
#      at each density, and the lectures' `[maxpayld(row, tr) for row in eachrow(sh)]`, on Lecture 3.3's and 3.4's
#      shipment tables and on densities 0.1 to 50 lb/ft³;
#   2. minTLC(sh::AbstractDataFrame, ...): the row form on each row, as Lectures 3.3 and 3.4 add the columns with
#      `transform!(sh, AsTable(:) => ByRow(r -> minTLC(r, tr, ppiLTL)) => AsTable)` and as a released homework key
#      (HW 3, Q4) builds them row by row; the input table unchanged;
#   3. charge_tl(d, tr): Lecture 5.2's hand-written `max(2.00 d, mincharge_tl())` (Ex. 9, its 30 shipments, their
#      route charge and its pairwise savings), the homework key's closed-form TL size, minTLC's TL branch where it
#      charges one truck, and the shipment form at a full load (Lecture 4.3's `cTL`);
#   4. the LTL constants (B10): their values and types, and v0.3.0's transport bodies, copied below as text, against
#      the current functions bit for bit (`===`) on the inputs above and on grids through every bound;
#   5. Logjam.shtr (B11): public and not exported, its docstring found by Docs.doc and naming every field the
#      contract lists.

using Test
using Logjam
using DataFrames
using CSV

# ---- v0.3.0's transport bodies, verbatim (src/transtools.jl at the v0.3.0 tag fd0f1f3, which fa34e71 left
# unchanged: rate_ltl :128-144, qmax_ltl :177, mincharge_tl :210-212 and :221, mincharge_ltl :260-264, the zero
# tolerance :271-272, charge_tl :375-383 and :394, charge_ltl :447-453 and :464, maxpayld :490-492 and :501,
# totlogcost :569-581, _transportcost :586-587, _avh :590-596, minTLC :808-833), with the literals B10 names.
# The reference for "no value moves": each is compared with the current function by `===`. ----
module TrV030
using DataFrames
using Optim: optimize
function rate_ltl(q, s, d; ppi=104.2)
    # Clamp to valid ranges
    q_safe = max.(q, 150/2000)
    d_safe = max.(d, 37)

    # Formula: r_LTL = ppi × [(s²/8 + 14) / ((q^1/7 × d^15/29 - 7/2)(s² + 2s + 14))]
    numerator = ppi .* (s.^2 ./ 8 .+ 14)
    denominator = (q_safe.^(1/7) .* d_safe.^(15/29) .- 7/2) .* (s.^2 .+ 2 .* s .+ 14)

    rate = numerator ./ denominator

    # Mark out-of-bounds as Inf
    invalid = (denominator .< eps()) .| (q .> 5) .| (d .> 3354) .| (2000 .* q ./ s .> 650)
    rate = ifelse.(invalid, Inf, rate)

    return rate
end
rate_ltl(q, sh::Union{NamedTuple, DataFrames.DataFrameRow}; ppi=104.2) = rate_ltl(q, sh.s, sh.d; ppi=ppi)
qmax_ltl(s) = min.(5.0, 650 .* s ./ 2000)
function mincharge_tl(; ppi=102.7)
    return (ppi / 102.7) * 45
end
mincharge_tl(tr::Union{NamedTuple, DataFrames.DataFrameRow}) = mincharge_tl(; ppi=tr.ppi)
function mincharge_ltl(d::Real; ppi=104.2)
    d > 3354 && error("LTL minimum charge not defined for d > 3354 miles")
    d <= 0 && return 0.0
    return (ppi / 104.2) * (45 + d^(28/19) / 1625)
end
const _TOL0 = 1e-4
_is0(x) = abs(x) < _TOL0
function charge_tl(q, s, d; r=nothing, Kwt=25.0, Kcu=2750.0, ppi=102.7)
    # nothing to ship (within 1e-4 ton, TRN3), or nowhere to ship it (N4, CR 15)
    (_is0(q) || d == 0) && return 0.0
    rate = r === nothing ? 2.00 * ppi / 102.7 : r     # derived from ppi only when r is not passed (D5)
    q_max = min(Kwt, s * Kcu / 2000)
    num_trucks = ceil(Int, q / q_max)
    mc = _is0(d) ? 0.0 : mincharge_tl(; ppi=ppi)      # no minimum within 1e-4 mi (TRN3, Matlog's mincharge)
    return max(num_trucks * (rate * d), mc)           # one minimum per shipment (N3)
end
charge_tl(q, sh::Union{NamedTuple, DataFrames.DataFrameRow}, tr) = charge_tl(q, sh.s, sh.d; r=tr.r, Kwt=tr.Kwt, Kcu=tr.Kcu, ppi=tr.ppi)
function charge_ltl(q, s, d; ppi=104.2)
    # nothing to ship (within 1e-4 ton, TRN4), or nowhere to ship it (N4, CR 15)
    (_is0(q) || d == 0) && return 0.0
    r = rate_ltl(q, s, d; ppi=ppi)
    isinf(r) && return Inf
    return max(r * q * d, _is0(d) ? 0.0 : mincharge_ltl(d; ppi=ppi))   # no minimum within 1e-4 mi (TRN4)
end
charge_ltl(q, sh::Union{NamedTuple, DataFrames.DataFrameRow}; ppi=104.2) = charge_ltl(q, sh.s, sh.d; ppi=ppi)
function maxpayld(s; Kwt=25.0, Kcu=2750.0)
    return min.(Kwt, s .* Kcu ./ 2000)
end
maxpayld(sh::Union{NamedTuple, DataFrames.DataFrameRow}, tr) = maxpayld(sh.s; Kwt=tr.Kwt, Kcu=tr.Kcu)
function totlogcost(q, c, f, a, v, h)
    IC = max.(q, 0) .* a .* v .* h
    return _transportcost(q, c, f) .+ IC
end
function totlogcost(q, c, p)
    if hasproperty(p, :avh) && !ismissing(p.avh)
        return _transportcost(q, c, p.f) .+ max.(q, 0) .* p.avh
    end
    return totlogcost(q, c, p.f, p.a, p.v, p.h)
end
_transportcost(q, c, f) =
    ifelse.((abs.(c) .< eps()) .| iszero.(c .* f), 0.0, ifelse.(q .<= 0, Inf, c .* f ./ q))
function _avh(p)
    if hasproperty(p, :avh)
        x = getproperty(p, :avh)
        ismissing(x) || return x
    end
    return p.a * p.v * p.h
end
function minTLC(sh, tr_pos=nothing, ppi_pos=nothing; tr=nothing, ppi_ltl=nothing)
    (tr_pos !== nothing && tr !== nothing) &&
        throw(ArgumentError("minTLC: the carrier is given both positionally and as `tr =`"))
    (ppi_pos !== nothing && ppi_ltl !== nothing) &&
        throw(ArgumentError("minTLC: the LTL PPI is given both positionally and as `ppi_ltl =`"))
    tr = tr === nothing ? tr_pos : tr
    ppi = ppi_ltl === nothing ? ppi_pos : ppi_ltl
    qᵒ, TLCᵒ, isLTL = nothing, Inf, false
    # CR 15, TRN3: a shipment over zero distance (within 1e-4 mi) costs nothing, so it is sized 0 and its TLC is 0
    (tr !== nothing || ppi !== nothing) && _is0(sh.d) && return (qᵒ = 0.0, TLCᵒ = 0.0, isLTL = false)
    if tr !== nothing
        qTL = min(sqrt((sh.f * max(tr.r*sh.d, mincharge_tl(tr))) / _avh(sh)),   # a·v·h, or an aggregate's avh (CR 14)
                  maxpayld(sh, tr))
        TLCtl = totlogcost(qTL, charge_tl(qTL, sh, tr), sh)
        qᵒ, TLCᵒ = qTL, TLCtl
    end
    if ppi !== nothing && 150/2000 < qmax_ltl(sh.s)      # bracket guard: below 0.231 lb/ft³ there is no LTL size
        qLTL = optimize(q -> totlogcost(q, charge_ltl(q, sh; ppi=ppi), sh),
                        150/2000, qmax_ltl(sh.s)).minimizer
        TLCltl = totlogcost(qLTL, charge_ltl(qLTL, sh; ppi=ppi), sh)
        if TLCltl < TLCᵒ
            qᵒ, TLCᵒ, isLTL = qLTL, TLCltl, true
        end
    end
    return (qᵒ = qᵒ, TLCᵒ = TLCᵒ, isLTL = isLTL)
end
end # module TrV030

# ---- the course's inputs, built as the course builds them --------------------------------------------------------

# Lecture 3.3, Ex. 1(l) (3-transport/3-tran-3.qmd): Code block 1 (:189-197), the lane and the PPIs (:310-312, :442),
# the product (:902-904, v raised to 85,000 at :1460), Code blocks 12 (:1536-1537) and 13 (:1566-1567)
function _wp4_l33()
    uwt = 40; ucu = 9; s = uwt/ucu; Kwt = 25; Kcu = 2750
    f = 20; d = 532; ppiTL = 131.0; rTL = 2.00ppiTL/102.7; ppiLTL = 177.4
    α = 1; v = 85000; h = 0.3
    tr = (r = rTL, Kwt = Kwt, Kcu = Kcu, ppi = ppiTL)
    sh = DataFrame(f = f, s = s, a = α, v = v, h = h, d = d)
    push!(sh, first(sh))                     # duplicate the row
    sh[2, [:f, :s, :v]] = [80, 32.16, 5000]  # patch the second product
    return sh, tr, ppiLTL
end

# Lecture 3.4, Ex. 1 (3-transport/3-tran-4.qmd): Code block 2 (:232-238), the I-40 mile markers of Code block 5
# (:369), the suppliers and customers (:466), Code block 12 (:1083-1093) and Code block 13's `shd(x)` (:1101)
function _wp4_l34_ex1()
    tr0 = (r = 2, Kwt = 25, Kcu = 2750)
    uwt = [30, 120]; ucu = [10, 4]
    shS = DataFrame(f = [100, 380], s = uwt./ucu)
    pct = [20, 30, 50]/100
    sh0 = vcat(shS, DataFrame(f = sum(shS.f)*pct, s = sum(shS.f)./sum(shS.f./shS.s)))
    P = [50 150 190 270 420]'
    idxin, idxout = 1:2, 3:5
    tr = (r = 2, Kwt = 25, Kcu = 2750, ppi = 102.7)
    uval = [300, 450]
    shS.v = uval./(uwt/2000)
    αS = 0
    shS.a .= αS + 0.5
    shC = DataFrame(f = sum(shS.f)*pct, s = sum(shS.f)./sum(shS.f./shS.s), v = sum(shS.f.*shS.v)/sum(shS.f))
    shC.a .= 0.5
    sh = vcat(shS, shC)
    sh.h .= 0.3
    shd(x) = hcat(sh, DataFrame(d = [d1.(x, P[idxin]); d1.(x, P[idxout])]))
    return (; tr0, sh0, tr, sh, shd)
end

# Lecture 3.4, Ex. 2 (3-transport/3-tran-4.qmd): Code block 18 (:1257-1271), Code block 20 (:1300-1308), Code
# block 21's shD (:1324-1332) and Code block 22's sh2 (:1362-1374); places by loc2lonlat, as the lecture has them
function _wp4_l34_ex2()
    S = [loc2lonlat(c; state = st) for (c, st) in zip(["Rochester", "Orlando", "San Antonio"], [:NY, :FL, :TX])]
    SXY = [getindex.(S, :LON) getindex.(S, :LAT)]
    C = [loc2lonlat(c; state = st) for (c, st) in zip(["Portland", "Tucson", "Denver", "Milwaukee"], [:OR, :AZ, :CO, :WI])]
    CXY = [getindex.(C, :LON) getindex.(C, :LAT)]
    DC = loc2lonlat("Memphis"; state = :TN)
    DCXY = [DC.LON DC.LAT]
    ppiTL = 131.0; ppiLTL = 177.4
    tr2 = (r = 2ppiTL/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL)
    fS2 = [500, 75, 300]; pct2 = [20, 35, 25, 20]/100; sS2 = [32, 3, 12]; v2 = [50_000, 25_000, 10_000]
    αS = 0; αC = 0.5
    F2 = fS2 * pct2'
    S2 = repeat(sS2, 1, size(CXY, 1))
    V2 = repeat(v2, 1, size(CXY, 1))
    D2 = dists(SXY, CXY, :mi) * 1.2
    shD = DataFrame(f = F2[:], s = S2[:], a = αS + αC, v = V2[:], h = 0.3, d = D2[:])
    shS2 = DataFrame(f = fS2, s = sS2, a = αS + 0.5, v = v2)
    shC2 = DataFrame(f = sum(shS2.f)*pct2, s = sum(shS2.f)./sum(shS2.f./shS2.s), a = αC,
                     v = sum(shS2.f.*shS2.v)/sum(shS2.f))
    sh2 = vcat(shS2, shC2)
    sh2.h .= 0.3
    sh2.d = dists(DCXY, [SXY; CXY], :mi)[:] * 1.2
    return (; tr2, ppiTL, ppiLTL, shD, sh2)
end

# A released homework key (HW 3, Q4): its three products between Chicago and Austin, and its carrier and PPIs
function _wp4_hw_q4()
    ppiTL, ppiLTL = 162.1, 203.7
    tr = (r = 2ppiTL/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL)
    C = loc2lonlat("Chicago"; state = :IL)
    A = loc2lonlat("Austin"; state = :TX)
    d = 1.2dists([C.LON C.LAT], [A.LON A.LAT], :mi)[1]
    cu = [2, 6, 12]; wt = [16, 150, 40]; uc = [500, 200, 100]; sv = [50, 180, 80]; ud = [720, 120, 480]
    xh = (uc .- sv)./uc
    sh4 = DataFrame(f = ud.*wt/2000, s = wt./cu, a = 0.5, v = 2000uc./wt, h = 0.05 .+ 0.06 .+ xh, d = d)
    return sh4, tr, ppiTL, ppiLTL
end

# Lecture 5.2, Ex. 9 (5-routing/5-rte-2.qmd): Code block 41's 54 locations and road miles (:2287, :2293-2294; the
# file is test/data/shmtNC30-xy.csv) and Code block 50's 30 shipments (:2787-2792)
function _wp4_l52_ex9()
    xy = CSV.read(joinpath(@__DIR__, "data", "shmtNC30-xy.csv"), DataFrame)
    X30 = Matrix(xy[:, [:x, :y]])
    D30 = dists(X30, X30, :mi) * 1.2
    shL = DataFrame(
        b = [15, 26, 23, 53, 35, 30, 39, 33, 34, 3, 9, 8, 29, 34, 38,
             32, 18, 17, 4, 4, 7, 30, 33, 22, 6, 19, 16, 8, 37, 14],
        e = [19, 27, 18, 51, 30, 36, 33, 35, 38, 10, 2, 12, 39, 29, 37,
             36, 22, 13, 1, 9, 15, 34, 39, 15, 11, 14, 21, 5, 32, 13])
    dL = [D30[b, e] for (b, e) in zip(shL.b, shL.e)]
    return shL, D30, dL
end

# the lectures' way of adding the three columns (3-tran-3.qmd:1569-1570, 3-tran-4.qmd:1333-1334, :1375-1376)
_wp4_lecture_transform!(sh, tr, ppi) = transform!(sh, AsTable(:) => ByRow(r -> minTLC(r, tr, ppi)) => AsTable)

# every column equal (==), with the same names in the same order and the same element types
_wp4_sametable(a, b) = names(a) == names(b) && all(a[!, n] == b[!, n] for n in names(a)) &&
                       eltype.(eachcol(a)) == eltype.(eachcol(b))

@testset "WP4 (v0.3.1): transport tables, one truckload, the LTL constants, the sh/tr contract" begin

    l33sh, l33tr, l33ppi = _wp4_l33()
    e1 = _wp4_l34_ex1()
    e2 = _wp4_l34_ex2()
    sh4, tr4, ppiTL4, ppiLTL4 = _wp4_hw_q4()

    @testset "B6: maxpayld(s::AbstractVector, tr) is the scalar rule at each density" begin
        for tr in ((Kwt = 25, Kcu = 2750), (Kwt = 25.0, Kcu = 2750.0), (Kwt = 24, Kcu = 3000),   # 3.3 Ex. 2's truck
                   (r = 2, Kwt = 25, Kcu = 2750, ppi = 102.7))
            for s in (0.1:0.1:50, collect(0.1:0.1:50), [1, 4, 8, 18, 19, 50], Float32[3.5, 40.0])
                m = maxpayld(s, tr)
                @test m isa Vector
                @test length(m) == length(s)
                @test m == [maxpayld(x; Kwt = tr.Kwt, Kcu = tr.Kcu) for x in s]
                @test m == [maxpayld(row, tr) for row in eachrow(DataFrame(s = s))]
                @test m == [TrV030.maxpayld(x; Kwt = tr.Kwt, Kcu = tr.Kcu) for x in s]
                @test eltype(m) == typeof(maxpayld(first(s); Kwt = tr.Kwt, Kcu = tr.Kcu))
            end
        end
        # on a range, each element is the scalar rule's (the keyword form broadcasts the range as a range, and
        # differs in the last place on some of these densities; the keyword form itself is unchanged)
        r = 0.1:0.1:50
        @test maxpayld(r, (Kwt = 25, Kcu = 2750)) == [maxpayld(x; Kwt = 25, Kcu = 2750) for x in r]
        @test maxpayld(r; Kwt = 25, Kcu = 2750) == TrV030.maxpayld(r; Kwt = 25, Kcu = 2750)
        @test maxpayld(Float64[], (Kwt = 25, Kcu = 2750)) == Float64[]
        @test maxpayld(Float64[], (Kwt = 25, Kcu = 2750)) isa Vector{Float64}
        # Kwt and Kcu are required, as in the row form
        @test_throws Exception maxpayld([8.0], (Kwt = 25,))
        @test_throws Exception maxpayld((s = 8.0,), (Kwt = 25,))
    end

    @testset "B6: maxpayld(sh::AbstractDataFrame, tr) equals the lectures' row-by-row comprehension" begin
        # 3.3 Code block 13 (:1568)
        @test maxpayld(l33sh, l33tr) == [maxpayld(row, l33tr) for row in eachrow(l33sh)]
        # 3.4 Code block 2 (:239), with its carrier of no ppi
        @test maxpayld(e1.sh0, e1.tr0) == [maxpayld(row, e1.tr0) for row in eachrow(e1.sh0)]
        # 3.4 Code block 14 (:1115), at the DC's mile 150 and three other miles, and Code block 24 (:1498)
        for x in (0, 150, 222.5, 450)
            shx = e1.shd(x)
            @test maxpayld(shx, e1.tr) == [maxpayld(r, e1.tr) for r in eachrow(shx)]
        end
        @test maxpayld(e1.sh, e1.tr) == [maxpayld(r, e1.tr) for r in eachrow(e1.sh)]
        # 3.4 Code blocks 21 and 22 (:1332, :1374)
        @test maxpayld(e2.shD, e2.tr2) == [maxpayld(r, e2.tr2) for r in eachrow(e2.shD)]
        @test maxpayld(e2.sh2, e2.tr2) == [maxpayld(r, e2.tr2) for r in eachrow(e2.sh2)]
        # 5.3 Code block 41's broadcast (5-rte-3.qmd:2443), on 3.4's table
        @test maxpayld(e2.shD, e2.tr2) == maxpayld.(eachrow(e2.shD), Ref(e2.tr2))
        # a homework key's products
        @test maxpayld(sh4, tr4) == [maxpayld(r, tr4) for r in eachrow(sh4)]
        # the column alone, and a view of the table
        @test maxpayld(e2.shD.s, e2.tr2) == maxpayld(e2.shD, e2.tr2)
        @test maxpayld(view(e2.shD, 2:5, :), e2.tr2) == maxpayld(e2.shD, e2.tr2)[2:5]
        # the table is not changed
        before = copy(e2.shD)
        maxpayld(e2.shD, e2.tr2)
        @test e2.shD == before
    end

    @testset "B6: minTLC(sh::AbstractDataFrame, ...) equals the row form on each row, as the lectures add it" begin
        # 3.3 Code block 13 (:1568-1570): the lecture's table, and the new form on the same input
        lec = copy(l33sh)
        lec.qmax = [maxpayld(row, l33tr) for row in eachrow(lec)]
        new_in = copy(lec)
        _wp4_lecture_transform!(lec, l33tr, l33ppi)
        snapshot = copy(new_in)
        out = minTLC(new_in, l33tr, l33ppi)
        @test _wp4_sametable(out, lec)
        @test _wp4_sametable(new_in, snapshot)                   # the input is not mutated
        @test names(new_in) == ["f", "s", "a", "v", "h", "d", "qmax"]
        @test out[!, :f] !== new_in[!, :f]                      # its columns are copies
        @test out.isLTL == [true, false]                        # Ex. 1(k)'s product LTL, the second TL
        # 3.4 Code blocks 21 and 22 (:1332-1334, :1374-1376)
        for sh in (e2.shD, e2.sh2)
            lec = copy(sh)
            lec.qmax = [maxpayld(r, e2.tr2) for r in eachrow(lec)]
            new_in = copy(lec)
            _wp4_lecture_transform!(lec, e2.tr2, e2.ppiLTL)
            snapshot = copy(new_in)
            @test _wp4_sametable(minTLC(new_in, e2.tr2, e2.ppiLTL), lec)
            @test _wp4_sametable(new_in, snapshot)
        end
        # 3.4 Ex. 1's I-40 shipments, as tlc_uc sizes them (:935), at a DC on a supplier (mile 150, a zero distance)
        for x in (0, 150, 222.5)
            shx = e1.shd(x)
            out = minTLC(shx, e1.tr, nothing)
            rows = [minTLC(r, e1.tr, nothing) for r in eachrow(shx)]
            @test out.qᵒ == [r.qᵒ for r in rows]
            @test out.TLCᵒ == [r.TLCᵒ for r in rows]
            @test out.isLTL == [r.isLTL for r in rows]
            @test out[:, names(shx)] == shx
        end
        @test minTLC(e1.shd(150), e1.tr).qᵒ[2] == 0.0               # the DC on supplier 2: nothing shipped
        # a released homework key (HW 3, Q4): `ind = [minTLC(r, tr, ppiLTL) for r in eachrow(sh4)]`
        ind = [minTLC(r, tr4, ppiLTL4) for r in eachrow(sh4)]
        out = minTLC(sh4, tr4, ppiLTL4)
        @test out.qᵒ == [x.qᵒ for x in ind]
        @test out.TLCᵒ == [x.TLCᵒ for x in ind]
        @test out.isLTL == [x.isLTL for x in ind]
        @test out[:, names(sh4)] == sh4
    end

    @testset "B6: minTLC on a table, every call mode of the row form" begin
        sh, tr, p = e2.shD, e2.tr2, e2.ppiLTL
        both = minTLC(sh, tr, p)
        @test _wp4_sametable(minTLC(sh; tr = tr, ppi_ltl = p), both)
        @test _wp4_sametable(minTLC(sh, tr; ppi_ltl = p), both)
        tl = minTLC(sh, tr)
        @test tl.qᵒ == [minTLC(r, tr).qᵒ for r in eachrow(sh)]
        @test tl.TLCᵒ == [minTLC(r, tr).TLCᵒ for r in eachrow(sh)]
        @test !any(tl.isLTL)
        @test _wp4_sametable(minTLC(sh; tr = tr), tl)
        ltl = minTLC(sh, nothing, p)
        @test ltl.qᵒ == [minTLC(r, nothing, p).qᵒ for r in eachrow(sh)]
        @test ltl.TLCᵒ == [minTLC(r, nothing, p).TLCᵒ for r in eachrow(sh)]
        @test _wp4_sametable(minTLC(sh; ppi_ltl = p), ltl)
        none = minTLC(sh)
        @test all(isnothing, none.qᵒ) && all(==(Inf), none.TLCᵒ) && !any(none.isLTL)
        # the same argument both ways is the row form's ArgumentError, on any table, an empty one too
        @test_throws ArgumentError minTLC(sh, tr, p; ppi_ltl = p)
        @test_throws ArgumentError minTLC(sh, tr; tr = tr)
        @test_throws ArgumentError minTLC(sh[1:0, :], tr, p; ppi_ltl = p)
        # a second call replaces the columns in their places, as the lecture's transform! does run twice
        lec = copy(sh)
        _wp4_lecture_transform!(lec, tr, p)
        lec2 = copy(lec)
        _wp4_lecture_transform!(lec2, tr, 2p)
        @test _wp4_sametable(minTLC(lec, tr, 2p), lec2)
        # a view gives a new DataFrame of its rows
        v = minTLC(view(sh, 3:6, :), tr, p)
        @test v isa DataFrame
        @test _wp4_sametable(v, both[3:6, :])
        # an empty table gives an empty table with the three columns
        z = minTLC(sh[1:0, :], tr, p)
        @test nrow(z) == 0 && names(z) == [names(sh); ["qᵒ", "TLCᵒ", "isLTL"]]
        # the row form is unchanged for a row (it never received a table: a DataFrame there was an error)
        @test minTLC(first(eachrow(sh)), tr, p) == minTLC(NamedTuple(first(eachrow(sh))), tr, p)
    end

    @testset "B9: charge_tl(d, tr) is max(r·d, mincharge_tl(tr)), Lecture 5.2's one-truckload charge" begin
        shL, D30, dL = _wp4_l52_ex9()
        # Code block 50 (5-rte-2.qmd:2793): c₀ = max.(2.00 .* dL, mincharge_tl())   # = charge_tl, one truckload
        c₀ = max.(2.00 .* dL, mincharge_tl())
        for tr in ((r = 2.00, ppi = 102.7), (ppi = 102.7,), (r = nothing, ppi = 102.7),
                   (r = 2.00, Kwt = 25, Kcu = 2750, ppi = 102.7))
            @test charge_tl.(dL, Ref(tr)) == c₀
        end
        # Code block 52 (:2833): the route charge, on every one-shipment route and every pair's two orders
        tr = (r = 2.00, ppi = 102.7)
        rTCLh(rte) = max(2.00 * rteTC(rte, shL, D30), mincharge_tl())
        rTCLb(rte) = charge_tl(rteTC(rte, shL, D30), tr)
        n = nrow(shL)
        @test all(rTCLb([k, k]) == rTCLh([k, k]) == c₀[k] for k in 1:n)
        @test all(rTCLb(rte) == rTCLh(rte) for i in 1:n for j in i+1:n for rte in ([i, j, i, j], [i, i, j, j], [j, i, i, j]))
        # and the pairwise savings on it (:2835) are the same, element for element
        @test pairwisesavings(rTCLb, shL) == pairwisesavings(rTCLh, shL)
        # a truck given as a DataFrameRow, with the rate derived from its index
        trdf = DataFrame(r = [2.00, 3.0], ppi = [102.7, 131.0])
        @test charge_tl(150.0, trdf[1, :]) == max(2.00 * 150.0, mincharge_tl())
        @test charge_tl(150.0, trdf[2, :]) == max(3.0 * 150.0, mincharge_tl(; ppi = 131.0))
        # the minimum when the miles are few, and at d = 0 (no zero rule: max(r·0, MC_TL) is MC_TL)
        @test charge_tl(10.0, tr) == 45.0
        @test charge_tl(0, tr) == mincharge_tl(tr) == 45.0
        @test charge_tl(0.0, (r = 2.00*131.0/102.7, ppi = 131.0)) == mincharge_tl(; ppi = 131.0)
        # ppi is required (mincharge_tl(tr) reads it)
        @test_throws Exception charge_tl(100.0, (r = 2.00,))
    end

    @testset "B9: charge_tl(d, tr) is the homework key's closed form and minTLC's TL branch, one truck" begin
        # a released homework key (HW 3, Q4), its closed-form TL size of material 2:
        #   qcf = min(sqrt(r2.f*max(tr.r*r2.d, mincharge_tl(; ppi = ppiTL)) / (r2.a*r2.v*r2.h)), maxpayld(r2, tr))
        for r2 in eachrow(sh4)
            @test charge_tl(r2.d, tr4) == max(tr4.r*r2.d, mincharge_tl(; ppi = ppiTL4))
            qcf = min(sqrt(r2.f*max(tr4.r*r2.d, mincharge_tl(; ppi = ppiTL4)) / (r2.a*r2.v*r2.h)), maxpayld(r2, tr4))
            @test min(sqrt(r2.f*charge_tl(r2.d, tr4) / (r2.a*r2.v*r2.h)), maxpayld(r2, tr4)) == qcf
            @test minTLC(r2, tr4).qᵒ == qcf
        end
        # minTLC's TL branch (src/transtools.jl, `max(tr.r*sh.d, mincharge_tl(tr))`): its size, and its charge, which
        # is one truck's because the TL size never exceeds a truckload, on every row of 3.3, 3.4 and the key
        tables = [(l33sh, l33tr), (e1.shd(0), e1.tr), (e1.shd(222.5), e1.tr), (e2.shD, e2.tr2), (e2.sh2, e2.tr2),
                  (sh4, tr4)]
        for (sh, tr) in tables, row in eachrow(sh)
            res = minTLC(row, tr)                                   # TL only
            @test res.qᵒ == min(sqrt(row.f * charge_tl(row.d, tr) / (row.a * row.v * row.h)), maxpayld(row, tr))
            @test res.qᵒ <= maxpayld(row, tr)
            @test charge_tl(res.qᵒ, row, tr) == charge_tl(row.d, tr)
            @test res.TLCᵒ == totlogcost(res.qᵒ, charge_tl(row.d, tr), row)
        end
    end

    @testset "B9: charge_tl(d, tr) is the shipment form at a full load, and a distinct method" begin
        # Lecture 4.3, Code block 31 (4-networks/4-net-3.qmd:1724-1733): one truck's charge on 3.3's lane
        uwt, ucu = 40, 9; s = uwt/ucu; Kwt, Kcu = 25, 2750
        qmax = maxpayld(s; Kwt = Kwt, Kcu = Kcu); d = 532
        ppiTL, ppiLTL = 131.0, 177.4; rTL = 2.00ppiTL/102.7
        cTL = charge_tl(qmax, s, d; r = rTL, Kwt = Kwt, Kcu = Kcu, ppi = ppiTL)
        @test charge_tl(d, (r = rTL, Kwt = Kwt, Kcu = Kcu, ppi = ppiTL)) == cTL
        @test round(cTL; digits = 2) == 1357.2
        # at every distance from 1e-4 mi up, a full load, and any load of one truck, is the same charge
        for tr in ((r = rTL, Kwt = 25, Kcu = 2750, ppi = ppiTL), (Kwt = 25, Kcu = 2750, ppi = 102.7),
                   (r = 2, Kwt = 25, Kcu = 2750, ppi = 102.7))
            rr = hasproperty(tr, :r) ? tr.r : nothing
            bad = [(q, d) for d in [1e-4; 0.5; 1:1:3000; 3354.0] for q in (maxpayld(s; Kwt = tr.Kwt, Kcu = tr.Kcu), 1.0, 1e-4)
                   if charge_tl(d, tr) != charge_tl(q, s, d; r = rr, Kwt = tr.Kwt, Kcu = tr.Kcu, ppi = tr.ppi)]
            @test isempty(bad)
        end
        # the zero rule is the shipment form's alone (N4, TRN3): at d = 0 it charges nothing
        @test charge_tl(qmax, s, 0; r = rTL, ppi = ppiTL) == 0.0
        @test charge_tl(0, (r = rTL, ppi = ppiTL)) == mincharge_tl(; ppi = ppiTL)
        # distinct by arity: the two-argument method is the only one for (Real, Any), and no call of the existing
        # forms reaches it
        @test length(methods(charge_tl, (Real, Any))) == 1
        m2 = which(charge_tl, (Float64, NamedTuple))
        @test m2.sig == Tuple{typeof(charge_tl), Real, Any}
        @test which(charge_tl, (Float64, Float64, Float64)) !== m2
        @test which(charge_tl, (Int, Float64, Int)) === which(charge_tl, (Float64, Float64, Float64))
        @test which(charge_tl, (Float64, NamedTuple, NamedTuple)) !== m2
        @test charge_tl(6.0, 40/9, 532; r = 2.00*131.0/102.7, ppi = 131.0) ===
              TrV030.charge_tl(6.0, 40/9, 532; r = 2.00*131.0/102.7, ppi = 131.0)
        @test charge_tl(6.0, (s = 40/9, d = 532), (r = rTL, Kwt = 25, Kcu = 2750, ppi = ppiTL)) ===
              TrV030.charge_tl(6.0, (s = 40/9, d = 532), (r = rTL, Kwt = 25, Kcu = 2750, ppi = ppiTL))
    end

    @testset "no ambiguity among maxpayld, minTLC and charge_tl" begin
        amb = Test.detect_ambiguities(Logjam)
        fns = (:maxpayld, :minTLC, :charge_tl)
        @test isempty(filter(p -> p[1].name in fns || p[2].name in fns, amb))
    end

    @testset "B10: the LTL constants, named once, keep the literals' values and types" begin
        @test Logjam._LTL_MIN_WEIGHT === 150/2000
        @test Logjam._LTL_MAX_WEIGHT === 5.0
        @test Logjam._LTL_MAX_CUBE === 650
        @test Logjam._LTL_MIN_DIST === 37
        @test Logjam._LTL_MAX_DIST === 3354
        @test_throws ErrorException("LTL minimum charge not defined for d > 3354 miles") mincharge_ltl(3355.0)
    end

    @testset "B10: v0.3.0's transport bodies and the current ones agree bit for bit" begin
        # rate_ltl and charge_ltl through every bound of the LTL domain: weight (the 150 lb clamp, 5 ton), distance
        # (the 37 mi clamp, 3354 mi), cube (650 ft³), in Int, Float64 and Float32; each pair `===`
        qs = Any[0.0, 0.01, 150/2000, 0.1, 0.5, 1, 2.5, 4.999999, 5, 5.0, 5.000001, 6, Float32(0.3)]
        ss = Any[0.2, 150/650, 0.25, 1, 2.6, 3, 4.444444, 10, 15.38, 15.4, 32.16, 50, Float32(8)]
        ds = Any[0, 1e-5, 1e-4, 10, 36.9, 37, 37.1, 250, 532, 1000.0, 3354, 3354.0, 3354.5, 4000, Float32(500)]
        bad = [(q, s, d) for q in qs for s in ss for d in ds
               if !(rate_ltl(q, s, d) === TrV030.rate_ltl(q, s, d) &&
                    rate_ltl(q, s, d; ppi = 177.4) === TrV030.rate_ltl(q, s, d; ppi = 177.4) &&
                    charge_ltl(q, s, d; ppi = 177.4) === TrV030.charge_ltl(q, s, d; ppi = 177.4))]
        @test isempty(bad)
        q64, s64 = Float64.(qs), Float64.(ss)
        @test isequal(rate_ltl(q64, s64, fill(532.0, 13)), TrV030.rate_ltl(q64, s64, fill(532.0, 13)))
        @test isequal(rate_ltl(q64, 10.0, Float64.(ds[1:13])), TrV030.rate_ltl(q64, 10.0, Float64.(ds[1:13])))
        # qmax_ltl: a scalar `===`, a vector and a range `isequal` (the range does its own arithmetic in both)
        bad = [s for s in Any[ss; 0.0; 0.1; 15.384615384615385; 100; collect(1:40); Float32(15.4)]
               if !(qmax_ltl(s) === TrV030.qmax_ltl(s))]
        @test isempty(bad)
        @test isequal(qmax_ltl(collect(0.1:0.1:50)), TrV030.qmax_ltl(collect(0.1:0.1:50)))
        @test isequal(qmax_ltl(0.1:0.1:50), TrV030.qmax_ltl(0.1:0.1:50))
        bad = [d for d in Any[0, -1, 1e-5, 37, 250.0, 532, 3354, 3354.0]
               if !(mincharge_ltl(d) === TrV030.mincharge_ltl(d) &&
                    mincharge_ltl(d; ppi = 177.4) === TrV030.mincharge_ltl(d; ppi = 177.4))]
        @test isempty(bad)
        # totlogcost on a row with and without its own avh and with a missing avh; _avh the same
        rows = Any[(f = 20, a = 1, v = 25_000, h = 0.3), (f = 20.0, a = 0.5, v = 85_000.0, h = 0.31),
                   (f = 150.0, a = 1, v = 9000.0, h = 0.28, avh = 23458.333333333332),
                   (f = 150.0, a = 1, v = 9000.0, h = 0.28, avh = missing)]
        bad = [(p, q, c) for p in rows for q in (0, 0.1274, 1.9024, 6.111111111111112, 25) for c in (0.0, 45.0, 1357.2)
               if !(totlogcost(q, c, p) === TrV030.totlogcost(q, c, p) && Logjam._avh(p) === TrV030._avh(p))]
        @test isempty(bad)
        # charge_tl with its rate derived from ppi (one expression now, `_tlrate`)
        bad = [(d, ppi) for d in (0.5, 10.0, 532, 3000.0) for ppi in (102.7, 131.0, 162.1)
               if !(charge_tl(6.0, 40/9, d; ppi = ppi) === TrV030.charge_tl(6.0, 40/9, d; ppi = ppi))]
        @test isempty(bad)
        # minTLC, every mode, on every row of the tables above and on Lecture 3.3's aggregate (an avh row)
        for (sh, tr, p) in [(l33sh, l33tr, l33ppi), (e1.shd(0), e1.tr, nothing), (e1.shd(150), e1.tr, nothing),
                            (e2.shD, e2.tr2, e2.ppiLTL), (e2.sh2, e2.tr2, e2.ppiLTL), (sh4, tr4, ppiLTL4)]
            bad = [i for (i, row) in enumerate(eachrow(sh))
                   if !(minTLC(row, tr, p) === TrV030.minTLC(row, tr, p) &&
                        minTLC(row, nothing, 177.4) === TrV030.minTLC(row, nothing, 177.4) &&
                        minTLC(row; tr = tr) === TrV030.minTLC(row; tr = tr))]
            @test isempty(bad)
        end
        agg = aggshmt(l33sh)
        @test minTLC(agg, l33tr, l33ppi) === TrV030.minTLC(agg, l33tr, l33ppi)
        @test minTLC(agg, l33tr) === TrV030.minTLC(agg, l33tr)
        @test minTLC((f = 20.0, s = 0.2, a = 1.0, v = 25_000.0, h = 0.3, d = 532.0), l33tr, l33ppi) ===
              TrV030.minTLC((f = 20.0, s = 0.2, a = 1.0, v = 25_000.0, h = 0.3, d = 532.0), l33tr, l33ppi)
    end

    @testset "B11: the sh/tr contract is Logjam.shtr's docstring" begin
        @test Base.ispublic(Logjam, :shtr)
        @test !Base.isexported(Logjam, :shtr)
        @test Docs.hasdoc(Logjam, :shtr)
        txt = string(Docs.doc(Docs.Binding(Logjam, :shtr)))
        @test !isempty(txt)
        @test !occursin("No documentation found", txt)
        @test occursin("The `sh` and `tr` contract", txt)
        @test occursin("Row, column or table", txt) && occursin("Read when present", txt)
        @test !occursin("Reserved for v0.2.8", txt)
        # every field the contract lists (v0.3.0's text, K13), named in the docstring and in the value
        shfields = (:b, :e, :f, :q, :s, :a, :v, :h, :d, :tL, :tU, :tbmin, :tbmax, :temin, :temax, :avh,
                    :qmax, :qᵒ, :TLCᵒ, :isLTL)
        trfields = (:b, :e, :Kwt, :Kcu, :maxTC, :r, :ppi, :tbmin, :tbmax, :temin, :temax)
        @test Logjam.shtr.sh == shfields
        @test Logjam.shtr.tr == trfields
        for f in union(shfields, trfields)
            @test occursin("`$(f)`", txt)
        end
        # the new forms are named in it
        for form in ("maxpayld(sh.s, tr)", "minTLC(sh, tr, ppi_ltl)", "charge_tl(d, tr)", "sh2rte(sh, R)")
            @test occursin(form, txt)
        end
        # the contract is no longer a bare string: the file has one copy of its text, the docstring
        src = read(joinpath(pkgdir(Logjam), "src", "transtools.jl"), String)
        @test count("Row, column or table", src) == 1
        @test !occursin("Unified `sh`/`tr` field contract", src)
    end
end
