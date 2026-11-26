# test_invtools.jl -- added by PCV WP1 of Logjam v0.3.1 (E1, X4): the inventory measures of src/invtools.jl,
# `Logjam.poissoncdf` and `Logjam.qbar` (Lecture 6.2's reorder-point form `qbarrp` as its three-argument method).
# Test spec Sec. 2; the evidence, each judged as it says:
#   1. equality (`==`) with the lectures' own definitions, copied below verbatim into two modules with their
#      .qmd lines cited, on the lectures' inputs and on the spec's grids;
#   2. the cells of the ISE 453 F25 spreadsheet Inventory.xlsx, sheets [BS Pois] and [RP Pois]
#      (test/data/inventory_xlsx_cells.csv), compared with isapprox(rtol = 1e-12): Excel computes to 15
#      significant digits. [RP Pois] tabulates Lecture 6.2's cycle forms (@eq-rp-safety, @eq-rp-qbar-cycle), which
#      the three-argument method averages over the levels instead (6.2, @eq-rp-qbar), so no cell of the sheet
#      holds it: its safety-stock column is compared with the base-stock measure it is;
#   3. the properties of Sec. 2.

using Test
using Logjam

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

# ---- Lecture 6.3's definitions, verbatim: 6-inventory/6-inv-3.qmd:1061-1066 (Code block 11, `tct`, for 6.3's
# mean demand during a lead time), :1439-1447 (Code block 16, `poissoncdf`, "Lecture 6.2's, repeated") and
# :1456-1457 (the make-to-stock model's `pi0` and `qbar`) ----
module InvLecture63
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

@testset "[WP1] inventory measures (E1)" begin

@testset "public, not exported; qbar by the number of arguments" begin
    for s in (:poissoncdf, :qbar)
        @test Base.ispublic(Logjam, s) && !Base.isexported(Logjam, s)
    end
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
        @test all(Logjam.qbar(q, μ) == L2.qbar(q, μ) for q in qs)
        @test all(Logjam.qbar(q, μ) == L3.qbar(q, μ) for q in qs)
        # reorder point, qo = 1 to 20 and qmin = 0 to 20 (6.2's examples, qo = 1 to 11 and qmin = 0 to 11, inside)
        @test all(Logjam.qbar(qo, qmin, μ) == L2.qbarrp(qo, qmin, μ) for qo in 1:20, qmin in 0:20)
    end
    # the values 6.2 quotes, to the places it quotes them
    μ = INV_MU[1][2]
    @test round(Logjam.poissoncdf(3, μ), digits = 5) == 0.99271                     # Ex. 2(b)
    @test round(Logjam.qbar(3, μ), digits = 5) == 2.2585                            # Ex. 3(a)
    @test round(Logjam.qbar(5, 2, μ), digits = 5) == 4.25198                        # Ex. 7(a)
end

@testset "the ISE 453 F25 spreadsheet, [BS Pois] and [RP Pois]" begin
    rows = _inv_xlsx_cells()
    @test length(rows) == 138
    xcell(sheet, q) = only(r.value for r in rows if r.sheet == sheet && r.quantity == q)
    near(a, b) = isapprox(a, b; rtol = 1e-12)
    for sheet in ("BS Pois", "RP Pois")
        @test xcell(sheet, "mu") == 6*(1/8)                    # D3 = D1*D2, the lecture's μ exactly
    end
    μ = xcell("BS Pois", "mu")
    # [BS Pois], qmax = 0 to 6: column B, F(qmax); column D, qbar (D5 = 0)
    bs = [r for r in rows if r.sheet == "BS Pois" && r.quantity in ("F", "qbar")]
    @test length(bs) == 14
    for r in bs
        @test near(r.quantity == "F" ? Logjam.poissoncdf(r.j, μ) : Logjam.qbar(r.j, μ), r.value)
    end
    # [RP Pois], qmin = 0 to 6: column B, F(qmin); column D, the safety stock, base stock's qbar at qmin (D6 = 0)
    rp = [r for r in rows if r.sheet == "RP Pois" && r.quantity in ("F", "qsafety")]
    @test length(rp) == 14
    for r in rp
        @test near(r.quantity == "F" ? Logjam.poissoncdf(r.j, μ) : Logjam.qbar(r.j, μ), r.value)
    end
end

@testset "properties" begin
    for (_, μ) in INV_MU
        F = [Logjam.poissoncdf(j, μ) for j in 0:40]
        @test issorted(F)                                         # nondecreasing in j
        @test 1 - Logjam.poissoncdf(ceil(Int, 4μ + 30), μ) < 1e-12
        @test issorted([Logjam.qbar(q, μ) for q in 0:30])         # nondecreasing in qmax
        # the reorder-point method with qo = 1 is the base-stock method at qmin + 1
        @test all(Logjam.qbar(1, k, μ) == Logjam.qbar(k + 1, μ) for k in 0:20)
    end
end

end
