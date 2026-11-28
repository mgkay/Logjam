# test_invtools.jl -- the tests of src/invtools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_invtools.jl, its lines 1-379 ====
# test_invtools.jl -- added by PCV WP1 of Logjam v0.3.1 (E1, X4): the inventory measures of src/invtools.jl,
# `Logjam.poissoncdf`, `Logjam.pi0` and `Logjam.qbar` (Lecture 6.2's reorder-point forms `pi0rp` and `qbarrp` as
# their three-argument methods), and `Logjam.poissarr`. Test spec Sec. 2; the evidence, each judged as it says:
#   1. equality (`==`) with the lectures' own definitions, copied below verbatim into two modules with their
#      .qmd lines cited, on the lectures' inputs and on the spec's grids;
#   2. the cells of the ISE 453 F25 spreadsheet Inventory.xlsx, sheets [BS Pois] and [RP Pois]
#      (test/data/inventory_xlsx_cells.csv), compared with isapprox(rtol = 1e-12): Excel computes to 15
#      significant digits. A fraction out of stock, 1 - F, is compared as its complement F, which is what both
#      the sheet and Logjam compute before subtracting from one (exactly, F being at least 1/2): far in the tail
#      the subtraction turns F's last place into a relative 8e-12 ([RP Pois] C12, 1 - F(6; 0.75); WP1 ruling).
#      [RP Pois] tabulates Lecture 6.2's cycle forms, which the three-argument methods average over the levels
#      instead (6.2, @eq-rp-pi0 and @eq-rp-qbar): those cells are compared with the base-stock measures they are,
#      and the departure of the average from the cycle form is asserted as its own test (DEPARTURE);
#   3. the properties of Sec. 2, pi0 >= 0 to one unit in the last place of 1 (WP1 ruling: F rounds to 1 + 2^-52
#      far in the tail, at 6.3's Ex. 6 means, so the lectures' pi0 there is -2.2e-16 too);
#   4. poissarr: equal to Lecture 6.3's definition under the same seeded stream (three seeds, vector and scalar
#      rates); and against MATLAB's poissarr.m fed the same recorded draws (test/oracles/poissarr_matlab.csv,
#      written by tools/v0_3_1/make_oracles_v031.m from test/oracles/poissarr_streams.csv): the same arrivals kept
#      and the same draws taken, exactly, and arrival times within rtol 1e-14 (WP1 ruling: Julia's cumsum, which
#      6.3's definition and Logjam's use, adds pairwise where MATLAB's adds in order; measured 5 units in the last
#      place at most), with a transcription that adds in order equal to MATLAB's exactly;
#   5. a Kolmogorov-Smirnov check of poissarr's counts against the Poisson cdf at a fixed seed, a regression
#      only, never the evidence.

using Test
using Logjam
using Random

# ---- Lecture 6.2's definitions, verbatim: 6-inventory/6-inv-2.qmd:867-875 (Code block 9), :1096-1097 (the
# base-stock model's implementation for Poisson demand) and :2193-2194 (the reorder-point model's) ----
module InvLecture62
function poissoncdf(j, μ)
    pℓ = exp(-μ)                  # Pr(D_L = 0)
    F = pℓ                        # F(0; μ)
    for ℓ in 1:j
        pℓ *= μ/ℓ                 # Pr(D_L = ℓ), from Pr(D_L = ℓ - 1)
        F += pℓ                   # F(ℓ; μ), from F(ℓ - 1; μ)
    end
    return F
end
pi0(qmax, μ) = qmax == 0 ? 1.0 : 1 - poissoncdf(qmax - 1, μ)  # <1>
qbar(qmax, μ) = sum(poissoncdf(j, μ) for j in 0:qmax-1; init = 0.0)
pi0rp(qo, qmin, μ) = sum(pi0(qmin + ℓ, μ) for ℓ in 1:qo)/qo   # <1>
qbarrp(qo, qmin, μ) = sum(qbar(qmin + ℓ, μ) for ℓ in 1:qo)/qo
end

# ---- Lecture 6.3's definitions, verbatim: 6-inventory/6-inv-3.qmd:534-564 (Code block 3, `poissarr`),
# :1061-1066 (Code block 11, `tct`, for 6.3's mean demand during a lead time), :1439-1447 (Code block 16,
# `poissoncdf`, "Lecture 6.2's, repeated") and :1456-1457 (the make-to-stock model's `pi0` and `qbar`) ----
module InvLecture63
using Random                        # for randexp, exponential draws
function poissarr(lmb, n = 1)
    # lmb = n-element vector of arrival rates, where lmb[i] is the rate
    #       for time period i
    #   n = number of periods, if scalar lmb
    #   t = vector of variates, where t[j] between [(i-1), i) correspond
    #       to period i arrivals
    if n > 1 && length(lmb) > 1
        error("\"n\" > 1 only for scalar \"lmb\".")
    end
    lmax = maximum(lmb)             # the peak rate
    t = cumsum(randexp(ceil(Int, n*1.25*length(lmb)*lmax))/lmax)  # <1>
    done = false
    while !done
        if t[end] > n*length(lmb)
            done = true
            t = t[t .< n*length(lmb)]
        else                        # extend by a quarter as many
            more = ceil(Int, n*0.25*length(lmb)*lmax)
            t = [t; t[end] .+ cumsum(randexp(more)/lmax)]
        end
    end
    if !isempty(t) && length(lmb) > 1   # Thin if nonhomogeneous
        rnd = rand(length(t))
        for i in 1:length(lmb)
            t[(i - 1 .<= t .< i) .& (rnd .> lmb[i]/lmax)] .= NaN  # <2>
        end
        t = t[.!isnan.(t)]
    end
    return t
end
function tct(m; ra = ra, te = te, ca2 = ca2, ce2 = ce2)
    u = ra*te/m                 # utilization
    u < 1 || error("utilization $u: $m machine(s) cannot keep up") # <1>
    CTq = ((ca2 + ce2)/2)*(u^(sqrt(2(m + 1)) - 1)/(m*(1 - u)))*te
    return CTq + te             # hr, cycle time in queue and in process
end
function poissoncdf(j, μ)
    pℓ = exp(-μ)                  # Pr(D_L = 0)
    F = pℓ                        # F(0; μ)
    for ℓ in 1:j
        pℓ *= μ/ℓ                 # Pr(D_L = ℓ), from Pr(D_L = ℓ - 1)
        F += pℓ                   # F(ℓ; μ), from F(ℓ - 1; μ)
    end
    return F
end
pi0(qmax, μ) = qmax == 0 ? 1.0 : 1 - poissoncdf(qmax - 1, μ)  # <1>
qbar(qmax, μ) = sum(poissoncdf(j, μ) for j in 0:qmax-1; init = 0.0)
end

# ---- the lectures' inputs: each mean demand during a lead time μ, as the lecture computes it ----
# 6.2: ra = 6 a period and te = 1/8 (6-inv-2.qmd:882-884), and the pooled warehouse's 9ra (:2642-2643).
# 6.3: Ex. 5, rd = 3, y = 1, t0 = 10/60, A = 1, ca2 = 1, ce2 = c02 = 0, one machine, μ = ra*tct(m)
# (6-inv-3.qmd:1836-1853); Ex. 6, rd = 10, machines 2 to 5 and the search beyond (:1905-1915, :1956-1960,
# :1459-1460), here 2 to 8.
const INV_MU = let
    ra = 6; te = 1/8; μ = ra*te
    rapool = 9ra; μpool = rapool*te
    te63 = (10/60)/1
    μ5 = (3/1)*InvLecture63.tct(1; ra = 3/1, te = te63, ca2 = 1, ce2 = 0)
    μ6 = [(10/1)*InvLecture63.tct(m; ra = 10/1, te = te63, ca2 = 1, ce2 = 0) for m in 2:8]
    [(:L62, μ), (:L62pool, μpool), (:L63ex5, μ5), [(Symbol("L63ex6m$m"), μ6[m - 1]) for m in 2:8]...]
end
# the levels each lecture evaluates, where they go beyond the spec's grids (6.2's pooled search, 0:2round(Int, 54))
_inv_qmaxs(tag) = tag === :L62pool ? (0:108) : (0:30)

# ---- a test-only generator that returns recorded draws in order (the MATLAB oracle's streams) ----
mutable struct InvRecordedRNG <: Random.AbstractRNG
    e::Vector{Float64}   # standard exponentials, returned by randexp
    ie::Int
    u::Vector{Float64}   # uniforms on [0, 1), returned by rand
    iu::Int
end
InvRecordedRNG(e, u) = InvRecordedRNG(e, 0, u, 0)
function Random.randexp(r::InvRecordedRNG)
    r.ie < length(r.e) || error("the recorded exponentials ran out")
    r.ie += 1
    return r.e[r.ie]
end
Random.randexp(r::InvRecordedRNG, ::Type{Float64}) = Random.randexp(r)
function Random.rand(r::InvRecordedRNG, ::Random.SamplerTrivial{Random.CloseOpen01{Float64}})
    r.iu < length(r.u) || error("the recorded uniforms ran out")
    r.iu += 1
    return r.u[r.iu]
end

# MATLAB's poissarr.m as Logjam's body with one change, `cumsum` adding in order as MATLAB's does, so a
# comparison with the oracle isolates the order of addition (the oracle's stubs divide by the peak rate as
# Logjam does)
function _inv_poissarr_inorder(lmb, n, rng)
    cs(v) = (s = similar(v); a = zero(eltype(v)); for i in eachindex(v); a += v[i]; s[i] = a; end; s)
    lmax = maximum(lmb)
    t = cs(randexp(rng, ceil(Int, n*1.25*length(lmb)*lmax))/lmax)
    done = false
    while !done
        if t[end] > n*length(lmb)
            done = true
            t = t[t .< n*length(lmb)]
        else
            more = ceil(Int, n*0.25*length(lmb)*lmax)
            t = [t; t[end] .+ cs(randexp(rng, more)/lmax)]
        end
    end
    if !isempty(t) && length(lmb) > 1
        rnd = rand(rng, length(t))
        for i in 1:length(lmb)
            t[(i - 1 .<= t .< i) .& (rnd .> lmb[i]/lmax)] .= NaN
        end
        t = t[.!isnan.(t)]
    end
    return t
end

# a file of "@name,nrows,ncols" blocks ("#" lines are comments), as test/oracles/*.csv
function _inv_readblocks(path)
    d = Dict{String,Matrix{Float64}}()
    lines = readlines(path)
    i = 1
    while i <= length(lines)
        if startswith(lines[i], "@")
            nm, r, c = split(lines[i][2:end], ',')
            r, c = parse(Int, r), parse(Int, c)
            M = Matrix{Float64}(undef, r, c)
            for a in 1:r
                M[a, :] = parse.(Float64, split(lines[i + a], ','))
            end
            d[String(nm)] = M
            i += r + 1
        else
            i += 1
        end
    end
    return d
end
# the sum of the low 32 bits of each value's IEEE representation (exact; the oracle writes the same sum)
_inv_lowbits(x) = sum(Float64(reinterpret(UInt64, v) & 0xffffffff) for v in x)

# the spreadsheet fixture: sheet, cell, quantity, j, qo, value
function _inv_xlsx_cells()
    rows = NamedTuple[]
    for l in readlines(joinpath(@__DIR__, "data", "inventory_xlsx_cells.csv"))
        (startswith(l, "#") || startswith(l, "sheet,")) && continue
        s = split(l, ',')
        push!(rows, (sheet = String(s[1]), cell = String(s[2]), quantity = String(s[3]),
                     j = isempty(s[4]) ? -1 : parse(Int, s[4]), qo = isempty(s[5]) ? -1 : parse(Int, s[5]),
                     value = parse(Float64, s[6])))
    end
    return rows
end

# Kolmogorov-Smirnov statistic of integer counts against the Poisson cdf with mean λ: the largest gap between
# the empirical cdf and Logjam.poissoncdf over k = 0 to the largest count (both cdfs step at the integers)
function _inv_ksd(c, λ)
    N = length(c)
    return maximum(abs(count(<=(k), c)/N - Logjam.poissoncdf(k, λ)) for k in 0:maximum(c))
end

@testset "[WP1] inventory measures (E1)" begin

@testset "public, not exported; pi0 and qbar by the number of arguments" begin
    for s in (:poissoncdf, :pi0, :qbar, :poissarr)
        @test Base.ispublic(Logjam, s) && !Base.isexported(Logjam, s)
    end
    @test hasmethod(Logjam.pi0, Tuple{Int,Float64}) && hasmethod(Logjam.pi0, Tuple{Int,Int,Float64})
    @test hasmethod(Logjam.qbar, Tuple{Int,Float64}) && hasmethod(Logjam.qbar, Tuple{Int,Int,Float64})
end

@testset "equal to Lecture 6.2's and 6.3's definitions" begin
    L2, L3 = InvLecture62, InvLecture63
    @test INV_MU[1][2] == 0.75 && INV_MU[3][2] == 0.75    # 6.2's 6*(1/8); 6.3's Ex. 5, 3*tct(1), is 0.75 too
    for (tag, μ) in INV_MU
        # poissoncdf, j = 0 to 40
        @test all(Logjam.poissoncdf(j, μ) == L2.poissoncdf(j, μ) for j in 0:40)
        @test all(Logjam.poissoncdf(j, μ) == L3.poissoncdf(j, μ) for j in 0:40)
        # base stock, qmax = 0 to 30 (6.2's pooled warehouse, 0 to 108)
        qs = _inv_qmaxs(tag)
        @test all(Logjam.pi0(q, μ) == L2.pi0(q, μ) for q in qs)
        @test all(Logjam.qbar(q, μ) == L2.qbar(q, μ) for q in qs)
        @test all(Logjam.pi0(q, μ) == L3.pi0(q, μ) for q in qs)
        @test all(Logjam.qbar(q, μ) == L3.qbar(q, μ) for q in qs)
        # reorder point, qo = 1 to 20 and qmin = 0 to 20 (6.2's examples, qo = 1 to 11 and qmin = 0 to 11, inside)
        @test all(Logjam.pi0(qo, qmin, μ) == L2.pi0rp(qo, qmin, μ) for qo in 1:20, qmin in 0:20)
        @test all(Logjam.qbar(qo, qmin, μ) == L2.qbarrp(qo, qmin, μ) for qo in 1:20, qmin in 0:20)
    end
    # the values 6.2 quotes, to the places it quotes them
    μ = INV_MU[1][2]
    @test round(Logjam.poissoncdf(3, μ), digits = 5) == 0.99271                     # Ex. 2(b)
    @test round(Logjam.pi0(3, μ), digits = 5) == 0.04051                            # Ex. 3(a)
    @test round(Logjam.qbar(3, μ), digits = 5) == 2.2585
    @test round(Logjam.pi0(5, 2, μ), digits = 5) == 0.0098                          # Ex. 7(a)
    @test round(Logjam.qbar(5, 2, μ), digits = 5) == 4.25198
end

@testset "the ISE 453 F25 spreadsheet, [BS Pois] and [RP Pois]" begin
    rows = _inv_xlsx_cells()
    @test length(rows) == 138
    xcell(sheet, q) = only(r.value for r in rows if r.sheet == sheet && r.quantity == q)
    near(a, b) = isapprox(a, b; rtol = 1e-12)
    for sheet in ("BS Pois", "RP Pois")
        @test xcell(sheet, "mu") == 6*(1/8)                    # D3 = D1*D2, the lecture's μ exactly
    end
    μ, p, c, h, ra = (xcell("BS Pois", q) for q in ("mu", "p", "c", "h", "ra"))
    co = xcell("RP Pois", "co")
    @test xcell("RP Pois", "qomax") == ceil(Int, 2sqrt(2ra*co/(c*h)))   # 6.2's qomax (6-inv-2.qmd:2315)
    bs = [r for r in rows if r.sheet == "BS Pois" && r.j >= 0]
    rp = [r for r in rows if r.sheet == "RP Pois" && r.j >= 0]
    @test length(bs) == 28 && length(rp) == 98
    # [BS Pois], qmax = 0 to 6: F(qmax), pi0 (as its complement), qbar, and TP of the base-stock model with lost
    # sales (6.2's TP, 6-inv-2.qmd:1098-1099, with Logjam's measures)
    for r in bs
        q = r.j
        if r.quantity == "F"
            @test near(Logjam.poissoncdf(q, μ), r.value)
        elseif r.quantity == "pi0"
            @test near(1 - Logjam.pi0(q, μ), 1 - r.value)
        elseif r.quantity == "qbar"
            @test near(Logjam.qbar(q, μ), r.value)
        else
            @test near((p - c)*(1 - Logjam.pi0(q, μ))*ra - c*h*Logjam.qbar(q, μ), r.value)
        end
    end
    # [RP Pois], qmin = 0 to 6: F(qmin); the cycle form 1 - F(qmin) (as its complement), which is the
    # three-argument pi0 at qo = 1 and base stock's at qmin + 1; the safety stock, base stock's qbar at qmin; and
    # the cycle forms' total profit (6.2's @eq-rp-tp with @eq-rp-cycle, @eq-rp-qbar-cycle and @eq-rp-ro) from
    # Logjam's base-stock measures
    for r in rp
        k = r.j
        if r.quantity == "F"
            @test near(Logjam.poissoncdf(k, μ), r.value)
        elseif r.quantity == "pi0cycle"
            @test near(1 - Logjam.pi0(1, k, μ), 1 - r.value) && near(1 - Logjam.pi0(k + 1, μ), 1 - r.value)
        elseif r.quantity == "qsafety"
            @test near(Logjam.qbar(k, μ), r.value)
        else
            π0, qs = Logjam.pi0(k + 1, μ), Logjam.qbar(k, μ)
            @test near((p - c)*(1 - π0)*ra - c*h*(qs + r.qo/2) - co*(1 - π0)*ra/r.qo, r.value)
        end
    end
    # DEPARTURE: for qo >= 2 the three-argument pi0 is the average over the levels, below the cycle form the sheet
    # tabulates (6.2: the cycle form overstates the sales lost); at qo = 1 they are one
    cyc = Dict(r.j => r.value for r in rp if r.quantity == "pi0cycle")
    @test all(Logjam.pi0(qo, k, μ) < cyc[k] for qo in 2:11, k in 0:6)
end

@testset "properties" begin
    for (_, μ) in INV_MU
        F = [Logjam.poissoncdf(j, μ) for j in 0:40]
        @test issorted(F)                                         # nondecreasing in j
        @test 1 - Logjam.poissoncdf(ceil(Int, 4μ + 30), μ) < 1e-12
        P = [Logjam.pi0(q, μ) for q in 0:30]
        @test all(-eps(1.0) .<= P .<= 1) && issorted(P; rev = true)  # in [0, 1] to 1 ulp of 1, nonincreasing
        @test issorted([Logjam.qbar(q, μ) for q in 0:30])         # nondecreasing in qmax
        # the reorder-point methods with qo = 1 are the base-stock methods at qmin + 1
        @test all(Logjam.pi0(1, k, μ) == Logjam.pi0(k + 1, μ) for k in 0:20)
        @test all(Logjam.qbar(1, k, μ) == Logjam.qbar(k + 1, μ) for k in 0:20)
    end
end

@testset "poissarr equals Lecture 6.3's definition under the same seeded stream" begin
    saved = copy(Random.default_rng())    # leave the global stream as the suite found it
    try
        # 6.3's two days of hourly rates (6-inv-3.qmd:804, :631), one period as ctqsim calls it; and scalar rates:
        # the barbershop's mean, 17.25 an hour (:813), for one hour and for the 8-hour day, and 2 for 3 periods
        cases = [([5, 7, 20, 32, 6, 15, 45, 12], ()), ([5, 7, 20, 30, 4, 10, 15, 5], ()),
                 (17.25, ()), (17.25, (8,)), (2, (3,))]
        for s in (1, 2, 3), (lmb, n) in cases
            Random.seed!(s); a = InvLecture63.poissarr(lmb, n...); after_a = rand()
            Random.seed!(s); b = Logjam.poissarr(lmb, n...); after_b = rand()
            c = Logjam.poissarr(lmb, n...; rng = Xoshiro(s))
            @test !isempty(a) && a == b && a == c
            @test after_a == after_b                              # the same number of draws taken
        end
        # the same argument check, the same error
        @test_throws ErrorException("\"n\" > 1 only for scalar \"lmb\".") Logjam.poissarr([1, 2], 2)
        @test_throws ErrorException("\"n\" > 1 only for scalar \"lmb\".") InvLecture63.poissarr([1, 2], 2)
    finally
        copy!(Random.default_rng(), saved)
    end
end

@testset "poissarr against MATLAB's poissarr.m on a recorded stream" begin
    S = _inv_readblocks(joinpath(@__DIR__, "oracles", "poissarr_streams.csv"))
    O = _inv_readblocks(joinpath(@__DIR__, "oracles", "poissarr_matlab.csv"))
    extended = 0
    for c in ("barbershop", "smallday", "scalar2n3", "scalar1", "vecslow")
        lmb, n = vec(S["$(c)_lmb"]), Int(S["$(c)_n"][1])
        @test vec(O["$(c)_lmb"]) == lmb && O["$(c)_n"][1] == n
        E, U = vec(S["$(c)_E"]), vec(S["$(c)_U"])
        # MATLAB read the recorded streams bit for bit
        @test _inv_lowbits(E) == O["$(c)_Ebits"][1] && _inv_lowbits(U) == O["$(c)_Ubits"][1]
        x = length(lmb) == 1 ? only(lmb) : lmb
        tm = vec(O["$(c)_t"])
        rng = InvRecordedRNG(E, U)
        t = Logjam.poissarr(x, n; rng)
        @test length(t) == length(tm)                             # the same arrivals kept
        @test rng.ie == O["$(c)_nE"][1] && rng.iu == O["$(c)_nU"][1]   # the same draws taken
        @test all(isapprox.(t, tm; rtol = 1e-14))                 # cumsum's order of addition (WP1 ruling)
        @test _inv_poissarr_inorder(x, n, InvRecordedRNG(E, U)) == tm   # adding in order, MATLAB's exactly
        extended += rng.ie > ceil(Int, n*1.25*length(lmb)*maximum(lmb))
    end
    @test extended >= 1                                           # the extension loop was compared too
end

@testset "poissarr: Kolmogorov-Smirnov regression (not the evidence)" begin
    # Statistic: D = max_k |F_N(k) - F(k; λ)|, the largest gap between the empirical cdf of N counts and the
    # Poisson cdf with mean λ (Logjam.poissoncdf). Threshold: 1.63/sqrt(N), the asymptotic Kolmogorov critical
    # value at the 1% level, conservative for a discrete distribution. Fixed seed Xoshiro(20261126).
    rng = Xoshiro(20261126)
    # 6.3's barbershop day (6-inv-3.qmd:804), N = 10,000 days: each hour's count against its own rate
    ra = [5, 7, 20, 32, 6, 15, 45, 12]
    N = 10_000
    C = zeros(Int, N, length(ra))
    for d in 1:N
        t = Logjam.poissarr(ra; rng)
        for i in eachindex(ra)
            C[d, i] = count(x -> i - 1 <= x < i, t)
        end
    end
    @test all(_inv_ksd(C[:, i], ra[i]) < 1.63/sqrt(N) for i in eachindex(ra))
    # one rate, 5 a period, for 8 periods, N = 10,000 days: 80,000 period counts pooled
    c5 = Int[]
    for d in 1:N
        t = Logjam.poissarr(5, 8; rng)
        append!(c5, [count(x -> i - 1 <= x < i, t) for i in 1:8])
    end
    @test _inv_ksd(c5, 5) < 1.63/sqrt(length(c5))
end

end
