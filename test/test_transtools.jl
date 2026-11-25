using Test
using Logjam
using DataFrames

@testset "Transportation Economics (transtools)" begin

    @testset "rate_ltl" begin
        # Test single shipment (example from docstring)
        r = rate_ltl(0.5, 8.0, 250.0)
        @test r > 0
        @test r < 5.0  # Reasonable range for $/ton-mi (can be high for small shipments)
        @test !isinf(r)

        # Test vectorized inputs
        q_vec = [0.5, 1.0, 2.0]
        s_vec = [8.0, 10.0, 12.0]
        d_vec = [250.0, 500.0, 800.0]
        r_vec = rate_ltl(q_vec, s_vec, d_vec)
        @test length(r_vec) == 3
        @test all(r_vec .> 0)

        # Test clamping of small values
        r_small = rate_ltl(0.01, 8.0, 10.0)  # Below min weight and distance
        @test !isinf(r_small)  # Should clamp, not error

        # Test out-of-bounds returns Inf
        r_heavy = rate_ltl(6.0, 8.0, 250.0)  # q > 5 tons
        @test isinf(r_heavy)

        r_long = rate_ltl(1.0, 8.0, 4000.0)  # d > 3354 miles
        @test isinf(r_long)

        r_cube = rate_ltl(5.0, 2.0, 250.0)  # 2000*5/2 = 5000 > 650 ft³
        @test isinf(r_cube)

        # Test PPI adjustment
        r_base = rate_ltl(1.0, 10.0, 500.0; ppi=104.2)
        r_adj = rate_ltl(1.0, 10.0, 500.0; ppi=120.0)
        @test r_adj > r_base  # Higher PPI → higher rate
    end

    @testset "rate_ltl struct-form (T1.1)" begin
        sh_nt = (f=10_000, s=4.444, a=0.10, v=25_000, h=0.30, d=500)
        sh_df = DataFrame([sh_nt])[1, :]
        ppi_ltl = 104.2
        # T1.1a: NamedTuple (ppi now a keyword with default)
        @test rate_ltl(1.0, sh_nt; ppi=ppi_ltl) ≈ rate_ltl(1.0, sh_nt.s, sh_nt.d; ppi=ppi_ltl) rtol=1e-4
        # T1.1b: DataFrameRow
        @test rate_ltl(1.0, sh_df; ppi=ppi_ltl) ≈ rate_ltl(1.0, sh_nt.s, sh_nt.d; ppi=ppi_ltl) rtol=1e-4
    end

    @testset "mincharge_tl" begin
        # T0.1: default ppi → 45.0
        @test mincharge_tl() ≈ 45.0

        # T0.2: explicit default ppi → 45.0
        @test mincharge_tl(; ppi=102.7) ≈ 45.0

        # T0.3: adjusted ppi → proportional result
        @test mincharge_tl(; ppi=108.6) ≈ 45.0 * (108.6 / 102.7) rtol=1e-4
    end

    @testset "mincharge_tl struct-form (T1.5)" begin
        tr = (r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7)
        # T1.5a: struct-form matches scalar with same ppi
        @test mincharge_tl(tr) ≈ mincharge_tl(; ppi=tr.ppi) rtol=1e-4
        # T1.5b: tr.r is not read — changing r does not affect result
        tr_alt = (r=99.9, Kwt=tr.Kwt, Kcu=tr.Kcu, ppi=tr.ppi)
        @test mincharge_tl(tr_alt) == mincharge_tl(tr)
    end

    @testset "mincharge_ltl" begin
        # Test zero distance
        mc = mincharge_ltl(0.0)
        @test mc == 0.0

        # Test typical distances
        mc_250 = mincharge_ltl(250.0)
        mc_500 = mincharge_ltl(500.0)
        @test mc_500 > mc_250  # Longer distance → higher minimum

        # Test upper bound
        @test_throws ErrorException mincharge_ltl(4000.0)  # d > 3354

        # Test PPI adjustment
        mc_base = mincharge_ltl(250.0; ppi=104.2)
        mc_adj = mincharge_ltl(250.0; ppi=120.0)
        @test mc_adj > mc_base
    end

    @testset "charge_tl" begin
        # Scalar arg order is (q, s, d) as of v0.2.7.
        # Test single truckload (within capacity)
        c = charge_tl(10.0, 8.0, 500.0)
        @test c > 0
        @test c ≈ max(2.00 * 500.0, 45.0)  # Should be distance-based, not minimum

        # Test minimum charge applies for short distances
        c_short = charge_tl(10.0, 8.0, 10.0)
        @test c_short >= 45.0

        # Test multiple trucks needed
        # 30 tons at 8 lb/ft³: q_max = min(25, 8*2750/2000) = min(25, 11) = 11 tons
        # Need ceil(30/11) = 3 trucks
        c_multi = charge_tl(30.0, 8.0, 500.0)
        c_single = charge_tl(10.0, 8.0, 500.0)
        @test c_multi > 2 * c_single  # At least 2x more

        # Test cube-limited vs weight-limited
        c_light = charge_tl(10.0, 5.0, 500.0)   # Cube-limited: 5*2750/2000 = 6.875 tons
        c_heavy = charge_tl(10.0, 20.0, 500.0)  # Weight-limited: 20*2750/2000 = 27.5, so 25 tons
        @test c_light > c_heavy  # Need more trucks when cube-limited
    end

    @testset "charge_tl struct-form (T1.2)" begin
        sh_nt = (f=10_000, s=4.444, a=0.10, v=25_000, h=0.30, d=500)
        sh_df = DataFrame([sh_nt])[1, :]
        tr = (r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7)
        # T1.2a: NamedTuple (scalar reference uses (q, s, d) order)
        @test charge_tl(1.0, sh_nt, tr) ≈ charge_tl(1.0, sh_nt.s, sh_nt.d; r=tr.r, Kwt=tr.Kwt, Kcu=tr.Kcu, ppi=tr.ppi) rtol=1e-4
        # T1.2b: DataFrameRow
        @test charge_tl(1.0, sh_df, tr) ≈ charge_tl(1.0, sh_nt.s, sh_nt.d; r=tr.r, Kwt=tr.Kwt, Kcu=tr.Kcu, ppi=tr.ppi) rtol=1e-4
    end

    @testset "charge_ltl" begin
        # Scalar arg order is (q, s, d) as of v0.2.7.
        # Test typical shipment
        c = charge_ltl(0.5, 8.0, 250.0)
        @test c > 0
        @test !isinf(c)

        # Test minimum charge applies
        r = rate_ltl(0.1, 10.0, 100.0)
        c_calc = r * 0.1 * 100.0
        c_actual = charge_ltl(0.1, 10.0, 100.0)
        mc = mincharge_ltl(100.0)
        @test c_actual >= mc  # Should be at least minimum

        # Test out-of-bounds returns Inf
        c_invalid = charge_ltl(6.0, 8.0, 250.0)
        @test isinf(c_invalid)
    end

    @testset "charge_ltl struct-form (T1.3)" begin
        sh_nt = (f=10_000, s=4.444, a=0.10, v=25_000, h=0.30, d=500)
        sh_df = DataFrame([sh_nt])[1, :]
        ppi_ltl = 104.2
        # T1.3a: NamedTuple (ppi now a keyword; scalar reference uses (q, s, d))
        @test charge_ltl(1.0, sh_nt; ppi=ppi_ltl) ≈ charge_ltl(1.0, sh_nt.s, sh_nt.d; ppi=ppi_ltl) rtol=1e-4
        # T1.3b: DataFrameRow
        @test charge_ltl(1.0, sh_df; ppi=ppi_ltl) ≈ charge_ltl(1.0, sh_nt.s, sh_nt.d; ppi=ppi_ltl) rtol=1e-4
    end

    @testset "maxpayld" begin
        # Kwt/Kcu are now keywords with defaults (25.0, 2750.0).
        # Test weight-limited
        q = maxpayld(25.0)
        @test q == 25.0  # High density → weight limit

        # Test cube-limited
        q = maxpayld(8.0)
        @test q ≈ 8.0 * 2750.0 / 2000.0  # Low density → cube limit
        @test q == 11.0

        # Test explicit keywords
        @test maxpayld(8.0; Kwt=25.0, Kcu=2750.0) == 11.0

        # Test vectorized
        s_vec = [5.0, 10.0, 20.0, 30.0]
        q_vec = maxpayld(s_vec; Kwt=25.0, Kcu=2750.0)
        @test length(q_vec) == 4
        @test q_vec[1] < 25.0  # Cube-limited
        @test q_vec[4] == 25.0  # Weight-limited
    end

    @testset "maxpayld struct-form (T1.4)" begin
        sh_nt = (f=10_000, s=4.444, a=0.10, v=25_000, h=0.30, d=500)
        sh_df = DataFrame([sh_nt])[1, :]
        tr = (r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7)
        # T1.4a: NamedTuple (exact equality — pure arithmetic)
        @test maxpayld(sh_nt, tr) == maxpayld(sh_nt.s; Kwt=tr.Kwt, Kcu=tr.Kcu)
        # T1.4b: DataFrameRow
        @test maxpayld(sh_df, tr) == maxpayld(sh_nt.s; Kwt=tr.Kwt, Kcu=tr.Kcu)
    end

    @testset "totlogcost" begin
        # Test typical case
        q = 5.0
        c = 450.0
        f = 100.0
        a = 0.5
        v = 1000.0
        h = 0.25

        tlc = totlogcost(q, c, f, a, v, h)
        TC = c * f / q  # 450 * 100 / 5 = 9000
        IC = q * a * v * h  # 5 * 0.5 * 1000 * 0.25 = 625
        @test tlc ≈ TC + IC
        @test tlc ≈ 9625.0

        # Test zero cost
        tlc_zero = totlogcost(5.0, 0.0, 100.0, 0.5, 1000.0, 0.25)
        @test tlc_zero == 625.0  # Only inventory cost

        # Test vectorized
        q_vec = [1.0, 5.0, 10.0]
        tlc_vec = totlogcost(q_vec, 450.0, 100.0, 0.5, 1000.0, 0.25)
        @test length(tlc_vec) == 3
        @test all(tlc_vec .> 0)

        # Test params method with NamedTuple
        params = (f=100.0, a=0.5, v=1000.0, h=0.25)
        tlc_params = totlogcost(q, c, params)
        @test tlc_params ≈ tlc  # Should match scalar form

        # Test params method with aggshmt output
        df = DataFrame(
            f = [100.0, 200.0, 150.0],
            s = [8.0, 10.0, 6.0],
            v = [1000.0, 1500.0, 800.0],
            h = [0.25, 0.25, 0.25],
            a = [0.5, 0.5, 0.5]
        )
        agg = aggshmt(df)
        tlc_agg = totlogcost(5.0, 450.0, agg)
        tlc_scalar = totlogcost(5.0, 450.0, agg.f, agg.a, agg.v, agg.h)
        @test tlc_agg ≈ tlc_scalar
    end

    @testset "aggshmt" begin
        # Test with f column
        df = DataFrame(
            f = [100.0, 200.0, 150.0],
            s = [8.0, 10.0, 6.0],
            v = [1000.0, 1500.0, 800.0],
            h = [0.25, 0.25, 0.25],
            a = [0.5, 0.5, 0.5]
        )

        agg = aggshmt(df)
        @test agg.f ≈ 450.0  # Sum of demands
        @test agg.s > 0  # Harmonic mean
        @test agg.v > 0  # Weighted average
        @test agg.h ≈ 0.25
        @test agg.a ≈ 0.5

        # Harmonic mean should be between min and max
        @test minimum(df.s) <= agg.s <= maximum(df.s)

        # Test with q column (no f)
        df_q = DataFrame(
            q = [10.0, 20.0, 15.0],
            s = [8.0, 10.0, 6.0],
            v = [1000.0, 1500.0, 800.0],
            h = [0.25, 0.25, 0.25],
            a = [0.5, 0.5, 0.5]
        )

        # (the v0.2.8 assertion here, `agg_q.f ≈ 45.0`, encoded finding N2's defect: an invented
        # `f`. It is corrected to the Matlog value in the [N2] testset at the end of this file.)
        agg_q = aggshmt(df_q)
        @test agg_q.s > 0
    end

    @testset "docstring numerics (R6)" begin
        # Values re-run from current code; each would fail on the stale docstrings.
        # Scalar charge_tl/charge_ltl use (q, s, d) order as of v0.2.7 — the
        # C1-fixed numerics are preserved by reordering the arguments.
        @test rate_ltl(0.5, 8.0, 250.0) ≈ 1.9906 atol=1e-3
        @test mincharge_ltl(250.0) ≈ 47.10 atol=1e-2
        @test mincharge_ltl(500.0) ≈ 50.84 atol=1e-2
        @test charge_tl(25.0, 8.0, 500.0) == 3000.0
        @test charge_tl(30.0, 8.0, 500.0) == 3000.0
        @test charge_tl(10.0, 8.0, 500.0) == 1000.0
        @test charge_ltl(0.5, 8.0, 250.0) ≈ 248.83 atol=1e-2
        @test charge_ltl(2.0, 10.0, 500.0) ≈ 859.31 atol=1e-2
    end

    @testset "minTLC (T2)" begin
        # Lecture-accurate fixtures (from 3-tran-3.jl):
        #   uwt=40 lb, ucu=9 ft³ => s=40/9; f=20 ton/yr; d=532 mi;
        #   ppiTL=131.0; rTL=2.00*131/102.7; alpha=1.0; ppiLTL=177.4
        # NOTE: test-spec-unit.md §T2 listed different fixture values
        # (f=10_000, s=4.444, a=0.10, r=2.00, ppi=102.7, d=500, ppi_ltl=104.2)
        # that do NOT reproduce the idea.md Q14-Q19 acceptance numerics.
        # The correct fixtures below reproduce all acceptance values to rtol=1e-4.
        ppiTL_lec = 131.0
        sh_lec = (f=20.0, s=40/9, a=1.0, v=25_000.0, h=0.30, d=532.0)
        tr_lec = (r=2.00*ppiTL_lec/102.7, Kwt=25.0, Kcu=2750.0, ppi=ppiTL_lec)
        ppi_ltl_lec = 177.4

        # T2.1 TL-only: minTLC(sh_lec, tr_lec)
        @testset "T2.1 TL-only" begin
            result = minTLC(sh_lec, tr_lec)
            @test result.qᵒ ≈ 1.9024 rtol=1e-4
            @test result.TLCᵒ ≈ 28_536.25 rtol=1e-4
            @test result.isLTL === false
        end

        # T2.2 LTL-only: minTLC(sh_lec, nothing, ppi_ltl_lec)
        @testset "T2.2 LTL-only" begin
            result = minTLC(sh_lec, nothing, ppi_ltl_lec)
            @test result.qᵒ ≈ 0.7622 rtol=1e-4
            @test result.isLTL === true
        end

        # T2.3 Both (TL wins at v=25k)
        @testset "T2.3 Both, TL wins (v=25k)" begin
            result = minTLC(sh_lec, tr_lec, ppi_ltl_lec)
            @test result.qᵒ ≈ 1.9024 rtol=1e-4
            @test result.TLCᵒ ≈ 28_536.25 rtol=1e-4
            @test result.isLTL === false
        end

        # T2.4 Both (LTL wins at v=85k)
        # Note: idea.md Q17 displays qᵒLTL=0.2735 (4 decimal places).
        # Actual computed value is 0.27354...; using 0.27354 here to satisfy rtol=1e-4.
        @testset "T2.4 Both, LTL wins (v=85k)" begin
            sh_85k = merge(sh_lec, (v=85_000.0,))
            result = minTLC(sh_85k, tr_lec, ppi_ltl_lec)
            @test result.qᵒ ≈ 0.27354 rtol=1e-4
            @test result.TLCᵒ ≈ 47_801.01 rtol=1e-4
            @test result.isLTL === true
        end

        # T2.5 Degenerate: neither tr nor ppi
        @testset "T2.5 Degenerate" begin
            result = minTLC(sh_lec)
            @test result.qᵒ === nothing
            @test result.TLCᵒ === Inf
            @test result.isLTL === false
        end
    end

    # =========================================================================
    # C3 — Interface + cross-regime tests (I1, I2, I3, I5)
    # =========================================================================

    @testset "I1 scalar arg order (q, s, d)" begin
        # charge_tl/charge_ltl scalar signature standardized on (q, s, d),
        # following the sh field sequence; rate_ltl already conformed. The
        # C1-fixed numerics are preserved by reordering the passed arguments.
        @test charge_tl(25.0, 8.0, 500.0) == 3000.0    # q=25, s=8, d=500
        @test charge_tl(30.0, 8.0, 500.0) == 3000.0
        @test charge_tl(10.0, 8.0, 500.0) == 1000.0
        @test charge_ltl(0.5, 8.0, 250.0) ≈ 248.83 atol=1e-2
        @test charge_ltl(2.0, 10.0, 500.0) ≈ 859.31 atol=1e-2
        @test rate_ltl(0.5, 8.0, 250.0) ≈ 1.9906 atol=1e-3

        # Swapping s and d changes the result — guards against silent regression
        # to the old (q, d, s) order.
        @test charge_tl(25.0, 500.0, 8.0) != charge_tl(25.0, 8.0, 500.0)
        @test charge_ltl(0.5, 250.0, 8.0) != charge_ltl(0.5, 8.0, 250.0)
    end

    @testset "I2 struct-form keyword ppi + maxpayld keyword defaults" begin
        sh_nt = (f=20.0, s=40/9, a=1.0, v=25_000.0, h=0.30, d=532.0)
        sh_df = DataFrame([sh_nt])[1, :]

        # rate_ltl / charge_ltl struct forms take ppi as a keyword with default.
        @test rate_ltl(1.0, sh_nt) == rate_ltl(1.0, sh_nt.s, sh_nt.d; ppi=104.2)
        @test rate_ltl(1.0, sh_nt; ppi=177.4) == rate_ltl(1.0, sh_nt.s, sh_nt.d; ppi=177.4)
        @test charge_ltl(1.0, sh_nt) == charge_ltl(1.0, sh_nt.s, sh_nt.d; ppi=104.2)
        @test charge_ltl(1.0, sh_nt; ppi=177.4) == charge_ltl(1.0, sh_nt.s, sh_nt.d; ppi=177.4)
        # DataFrameRow parity
        @test charge_ltl(1.0, sh_df; ppi=177.4) == charge_ltl(1.0, sh_nt.s, sh_nt.d; ppi=177.4)

        # maxpayld keyword defaults match charge_tl's (Kwt=25.0, Kcu=2750.0).
        @test maxpayld(8.0) == maxpayld(8.0; Kwt=25.0, Kcu=2750.0)
        @test maxpayld(8.0) == 11.0
        @test maxpayld(sh_nt.s) == maxpayld(sh_nt.s; Kwt=25.0, Kcu=2750.0)
    end

    @testset "I3 aggshmt complete-sh pass-through + chains into minTLC" begin
        # Two shipments sharing a lane (same d).
        df = DataFrame(
            f = [100.0, 200.0],
            s = [8.0, 12.0],
            v = [1000.0, 1500.0],
            h = [0.25, 0.30],
            a = [0.5, 0.6],
            d = [532.0, 532.0]
        )
        agg = aggshmt(df)

        @test agg.f == 300.0                                    # sum of demand
        @test agg.s ≈ 300.0 / (100/8 + 200/12)                 # total-wt / total-vol
        @test agg.v ≈ (100*1000 + 200*1500) / 300              # demand-weighted mean
        @test agg.h ≈ (100*0.25 + 200*0.30) / 300
        @test agg.a ≈ (100*0.5 + 200*0.6) / 300
        @test agg.d == 532.0                                   # d passed through from sh[1]

        # Output is a complete sh that chains directly into minTLC / maxpayld
        # with no intervening combine.
        tr = (r=2.00*131/102.7, Kwt=25.0, Kcu=2750.0, ppi=131.0)
        res = minTLC(agg, tr, 177.4)
        @test res.qᵒ !== nothing
        @test isfinite(res.TLCᵒ)
        @test maxpayld(agg, tr) == maxpayld(agg.s; Kwt=tr.Kwt, Kcu=tr.Kcu)
    end

    @testset "I5 cross-regime sh/tr field isolation" begin
        # A fully-populated sh (b,e,q,s,f,v,h,a,d) and tr (b,e,Kwt,Kcu,r,ppi).
        sh_full = DataFrame(
            b = [1, 2, 3],
            e = [4, 5, 6],
            q = [1.0, 1.0, 1.0],
            s = [8.0, 10.0, 6.0],
            f = [20.0, 20.0, 20.0],
            v = [25_000.0, 25_000.0, 25_000.0],
            h = [0.30, 0.30, 0.30],
            a = [1.0, 1.0, 1.0],
            d = [532.0, 532.0, 532.0]
        )
        tr_full = (b=[1], e=[1], Kwt=25.0, Kcu=2750.0, r=2.00*131/102.7, ppi=131.0)

        # --- Transport regime reads sh.{f,q,s,a,v,h,d}, tr.{r,Kwt,Kcu,ppi};
        #     the b,e fields must be ignored. ---
        row    = sh_full[2, :]
        sh_min = (f=row.f, s=row.s, a=row.a, v=row.v, h=row.h, d=row.d)          # no b,e
        tr_min = (r=tr_full.r, Kwt=tr_full.Kwt, Kcu=tr_full.Kcu, ppi=tr_full.ppi) # no b,e

        @test charge_tl(1.0, row, tr_full) == charge_tl(1.0, sh_min, tr_min)
        @test charge_ltl(1.0, row; ppi=177.4) == charge_ltl(1.0, sh_min; ppi=177.4)
        r_full = minTLC(row, tr_full, 177.4)
        r_min  = minTLC(sh_min, tr_min, 177.4)
        @test r_full.qᵒ ≈ r_min.qᵒ
        @test r_full.TLCᵒ ≈ r_min.TLCᵒ
        @test r_full.isLTL === r_min.isLTL

        # --- Routing regime reads sh.{b,e}, tr.{b,e}; the r,ppi,Kwt,... fields
        #     must be ignored. ---
        locs = [-78.6 35.8; -80.8 35.2; -79.0 36.1; -77.5 35.5;
                -81.0 35.0; -78.0 36.0; -79.5 35.6]
        C   = dists(locs, locs, :mi)
        rte = [1, 1, 2, 2, 3, 3]
        sh_be = DataFrame(b=sh_full.b, e=sh_full.e)   # only b,e
        tr_be = (b=tr_full.b, e=tr_full.e)            # only b,e

        @test rte2loc(rte, sh_full, tr_full) == rte2loc(rte, sh_be, tr_be)
        @test rteTC(rte, sh_full, C, tr_full) == rteTC(rte, sh_be, C, tr_be)
    end
end

# =============================================================================
# K2a: wrong-answer tests (test spec Sec. 2) and pin-today tests (Sec. 7).
# Each testset is tagged [ID]; tools/v0_3_0/run_against.jl records its outcome in
# baselines/sc2-outcomes.csv. A `@test_broken` names the component whose commit flips it to `@test`.
# =============================================================================

@testset "[N2] aggshmt on q without f returns the summed q and invents no f (Matlog aggshmt.m)" begin
    df_q = DataFrame(q = [10.0, 20.0, 15.0], s = [8.0, 10.0, 6.0], v = [1000.0, 1500.0, 800.0],
                     h = [0.25, 0.25, 0.25], a = [0.5, 0.5, 0.5])
    agg_q = aggshmt(df_q)
    # N2: v0.2.8 returns the first shipment's q (10.0) and fabricates f = 45.0 (fixed in K6)
    @test agg_q.q ≈ 45.0
    @test !haskey(agg_q, :f)
end

@testset "[N3] charge_tl applies the TL minimum per shipment, not per truck (chapter master.tex:562, 738; Matlog transcharge.m)" begin
    # q = 30 t at 30 lb/ft3 needs two trucks (q_max = 25); r d = 20 is below MC_TL = 45; one shipment pays 45
    # N3: v0.2.8 returns 90.0 (fixed in K6)
    @test charge_tl(30.0, 30.0, 10.0) == 45.0
    @test charge_tl(30.0, 8.0, 5.0) == 45.0                # three trucks (q_max = 11), 3 x 10 = 30 < 45
    @test charge_tl(30.0, 8.0, 500.0) == 3000.0            # above the minimum the charge is per truck, as before
    @test charge_tl(30.0, 30.0, 30.0) == 120.0             # two trucks over 30 mi: 2 x 2 x 30 = 120 > 45
    @test charge_tl(0.0, 30.0, 10.0) == 0.0                # no truck, no minimum
    @test charge_tl(10.0, 8.0, 500.0) == 1000.0            # control: one truck above the minimum
end

@testset "[N4] charge_ltl at q = 0 is 0 (chapter master.tex:708-710; Matlog transcharge.m)" begin
    # N4: v0.2.8 returns the LTL minimum, 50.84 (fixed in K6)
    @test charge_ltl(0.0, 10.0, 500.0) == 0.0
    @test charge_tl(0.0, 10.0, 500.0) == 0.0               # control: the TL side already does
end

@testset "[CR 14] aggshmt with unequal h keeps the inventory term of the original shipments (via avh)" begin
    df = DataFrame(f = [100.0, 200.0], s = [8.0, 10.0], v = [1000.0, 1500.0],
                   h = [0.10, 0.30], a = [0.5, 0.5], d = [532.0, 532.0])
    agg = aggshmt(df)
    q = 2.0
    # the shipments' own inventory terms: q_i = q f_i / F, each q_i a_i v_i h_i; with c = 0 only that term is left
    IC = sum((q * df.f[i] / sum(df.f)) * df.a[i] * df.v[i] * df.h[i] for i in 1:2)
    # CR 14: v0.2.8 multiplied three separately weighted means (311.11, not 333.33); fixed in K6 (avh)
    @test totlogcost(q, 0.0, agg) ≈ IC rtol = 1e-9
    @test agg.f == 300.0                                    # control: the demand still sums
end

@testset "[CR 15] charge_tl and minTLC at d = 0 are 0 (Q3 ruling 2026-10-04; Matlog)" begin
    sh0 = (f = 20.0, s = 8.0, a = 0.5, v = 1000.0, h = 0.25, d = 0.0)
    tr = (r = 2.0, Kwt = 25.0, Kcu = 2750.0, ppi = 102.7)
    # CR 15: v0.2.8 charges the TL minimum (45.0) and sizes the shipment by it (fixed in K6)
    @test charge_tl(10.0, 8.0, 0.0) == 0.0
    @test isapprox(minTLC(sh0, tr).TLCᵒ, 0.0; atol = 1e-9)
    @test charge_ltl(0.5, 8.0, 0.0) == 0.0                  # control: LTL is already 0 at d = 0
end

@testset "[S6] pin: positional minTLC(sh, tr, ppi) keeps working (about 40 course calls)" begin
    sh = (f = 20.0, s = 40 / 9, a = 1.0, v = 25_000.0, h = 0.30, d = 532.0)
    tr = (r = 2.00 * 131.0 / 102.7, Kwt = 25.0, Kcu = 2750.0, ppi = 131.0)
    both = minTLC(sh, tr, 177.4)                           # the docstring's example
    @test isapprox(both.qᵒ, 1.9024; atol = 5e-5)
    @test isapprox(both.TLCᵒ, 28_536.25; atol = 0.005)
    @test both.isLTL == false
    tl = minTLC(sh, tr)
    ltl = minTLC(sh, nothing, 177.4)
    @test tl.isLTL == false && ltl.isLTL == true
    @test both.TLCᵒ == min(tl.TLCᵒ, ltl.TLCᵒ)
end

@testset "zero charge at q = 0 or d = 0, in every form (N4, CR 15)" begin
    sh0 = (f = 20.0, s = 8.0, a = 0.5, v = 1000.0, h = 0.25, d = 0.0)
    tr = (r = 2.0, Kwt = 25.0, Kcu = 2750.0, ppi = 102.7)
    @test charge_tl(0.0, 8.0, 500.0) == 0.0 && charge_tl(10.0, 8.0, 0.0) == 0.0
    @test charge_ltl(0.0, 8.0, 500.0) == 0.0 && charge_ltl(0.5, 8.0, 0.0) == 0.0
    @test charge_tl(10.0, sh0, tr) == 0.0                                   # struct forms read d the same way
    @test charge_ltl(0.5, sh0) == 0.0
    @test charge_tl(10.0, (s = 8.0, d = 1e-9), tr) == 1 * (2.0 * 1e-9)      # within 1e-4 mi no minimum, r·d alone (TRN3; was 45)
    # minTLC at d = 0 is "ship nothing" in every call mode; the degenerate call is unchanged
    for res in (minTLC(sh0, tr), minTLC(sh0, nothing, 104.2), minTLC(sh0, tr, 104.2))
        @test res == (qᵒ = 0.0, TLCᵒ = 0.0, isLTL = false)
    end
    @test minTLC(sh0).qᵒ === nothing && minTLC(sh0).TLCᵒ === Inf
    # a shipment with distance still sizes and costs as before
    sh = merge(sh0, (d = 532.0,))
    @test minTLC(sh, tr).qᵒ > 0 && isfinite(minTLC(sh, tr).TLCᵒ) && minTLC(sh, tr).TLCᵒ > 0
    # the lecture's own c0 guard (3.4) is not needed for the exact zero but still agrees
    c0(q, sh, tr, ppi = nothing) = (isapprox(sh.d, 0, atol = 1e-4) ? 0.0 : (c = charge_tl(q, sh, tr); ppi === nothing ? c : min(c, charge_ltl(q, sh; ppi = ppi))))
    @test c0(5.0, sh0, tr) == charge_tl(5.0, sh0, tr) == 0.0
end

# TRN3, TRN4 (ruled 2026-11-21): Matlog's zero tolerance, tol0 = 1e-4 (ton, mile), tested as Matlog's is0 does,
# abs(x) < tol0. transcharge.m zeroes the charge of a weight within it (on q); mincharge.m drops the minimum
# charge for a distance within it (on d, TL and LTL), leaving the loaded-mile part. minTLC treats a distance
# within it as CR 15's zero distance.
@testset "TRN3, TRN4: Matlog's zero tolerance of 1e-4 ton and 1e-4 mi (transcharge, mincharge)" begin
    tr = (r = 2.0, Kwt = 25.0, Kcu = 2750.0, ppi = 102.7)
    @test Logjam._TOL0 == 1e-4                                          # the one tolerance
    # a facility an optimizer has put on its supplier, 9e-9 mi away: no minimum charge, only r·d per truck,
    # which is 0 to the cent's ten-thousandth (q_max is 11 ton at 8 lb/ft^3)
    @test charge_tl(10.0, 8.0, 9e-9) == 1 * (2.0 * 9e-9)
    @test charge_tl(30.0, 8.0, 9e-9) == 3 * (2.0 * 9e-9)
    @test isapprox(charge_tl(10.0, 8.0, 9e-9), 0.0; atol = 1e-6)
    @test isapprox(charge_tl(10.0, (s = 8.0, d = 9e-9), tr), 0.0; atol = 1e-6)
    @test charge_ltl(0.5, 8.0, 9e-9) == rate_ltl(0.5, 8.0, 9e-9) * 0.5 * 9e-9
    @test isapprox(charge_ltl(0.5, 8.0, 9e-9), 0.0; atol = 1e-6)
    @test isapprox(charge_ltl(0.5, (s = 8.0, d = 9e-9)), 0.0; atol = 1e-6)
    # the boundary: is0 is strict, so 1e-4 mi is a distance and pays the minimum; just over it, as before
    @test charge_tl(10.0, 8.0, prevfloat(1e-4)) == 1 * (2.0 * prevfloat(1e-4))
    @test charge_tl(10.0, 8.0, 1e-4) == 45.0
    @test charge_tl(10.0, 8.0, 1.0001e-4) == 45.0
    @test charge_ltl(0.5, 8.0, 1e-4) == mincharge_ltl(1e-4)
    @test charge_ltl(0.5, 8.0, 1.0001e-4) == mincharge_ltl(1.0001e-4)
    # a weight within 1e-4 ton is charged nothing; one just over it pays as before
    @test charge_tl(9e-5, 8.0, 500.0) == 0.0
    @test charge_ltl(9e-5, 8.0, 500.0) == 0.0
    @test charge_tl(prevfloat(1e-4), 8.0, 500.0) == 0.0
    @test charge_tl(1e-4, 8.0, 500.0) == 1000.0                         # one truck, 2.00 x 500 mi
    @test charge_tl(1.0001e-4, 8.0, 500.0) == 1000.0
    @test charge_ltl(1.0001e-4, 8.0, 500.0) == mincharge_ltl(500.0)     # the LTL minimum, as before
    # minTLC: a shipment within 1e-4 mi is shipped nothing in every call mode (CR 15 with the tolerance)
    sh = (f = 20.0, s = 8.0, a = 0.5, v = 1000.0, h = 0.25, d = 9e-9)
    for res in (minTLC(sh, tr), minTLC(sh, nothing, 104.2), minTLC(sh, tr, 104.2), minTLC(sh; tr = tr))
        @test res == (qᵒ = 0.0, TLCᵒ = 0.0, isLTL = false)
    end
    # just over the tolerance it sizes and costs as before: the TL closed form, with the minimum charge
    sh1 = merge(sh, (d = 2e-4,))
    q1 = min(sqrt(sh1.f * max(tr.r * sh1.d, mincharge_tl(tr)) / (sh1.a * sh1.v * sh1.h)), maxpayld(sh1, tr))
    r1 = minTLC(sh1, tr)
    @test r1.qᵒ ≈ q1 rtol = 1e-12
    @test r1.TLCᵒ ≈ totlogcost(q1, charge_tl(q1, sh1, tr), sh1) rtol = 1e-12
    @test r1.TLCᵒ > 100 && r1.isLTL == false
end

@testset "aggshmt writes the total into its base field (N2)" begin
    dq = DataFrame(q = [10.0, 20.0, 15.0], s = [8.0, 10.0, 6.0], v = [1000.0, 1500.0, 800.0],
                   h = [0.25, 0.25, 0.30], a = [0.5, 0.5, 0.5], d = [100.0, 100.0, 100.0])
    aq = aggshmt(dq)
    @test aq.q == 45.0 && !hasproperty(aq, :f)
    @test aq.s ≈ 45.0 / sum(dq.q ./ dq.s)                     # the same means as with f as the base
    @test aq.v ≈ sum(dq.q .* dq.v) / 45.0
    @test aq.h ≈ sum(dq.q .* dq.h) / 45.0 && aq.d == 100.0
    # the same data with the weights named f: identical means, the total in f, q passed through
    df = rename(dq, :q => :f)
    af = aggshmt(df)
    @test af.f == 45.0 && !hasproperty(af, :q)
    @test (af.s, af.v, af.h, af.a) == (aq.s, aq.v, aq.h, aq.a)
    # f and q both present: f is the weight base and q is the first shipment's, as before
    both = hcat(df, DataFrame(q = [1.0, 2.0, 3.0]))
    ab = aggshmt(both)
    @test ab.f == 45.0 && ab.q == 1.0
end

@testset "avh: always on the aggregate, and through the DataFrame round trip (CR 14, R10/S37)" begin
    # HW 3's Q4 data, three products with different carrying rates
    ppiTL, ppiLTL = 162.1, 203.7
    tr = (r = 2ppiTL/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL)
    cu = [2, 6, 12]; wt = [16, 150, 40]; uc = [500, 200, 100]; sv = [50, 180, 80]; ud = [720, 120, 480]
    sh4 = DataFrame(f = ud .* wt / 2000, s = wt ./ cu, a = 0.5, v = 2000uc ./ wt,
                    h = 0.05 .+ 0.06 .+ (uc .- sv) ./ uc, d = 1168.618368673098)
    avh_of(df, idx) = sum(df.f[idx] .* df.a[idx] .* df.v[idx] .* df.h[idx]) / sum(df.f[idx])
    for idx in ([1], [1, 2], [2, 3], [1, 2, 3])
        ag = aggshmt(sh4[idx, :])
        @test ag.avh ≈ avh_of(sh4, idx) rtol = 1e-12            # present for one row or several
    end
    @test aggshmt(sh4[[1], :]).avh == sh4.a[1] * sh4.v[1] * sh4.h[1]
    # with unequal h the cost of the aggregate is the sum of the products' own inventory terms
    ag = aggshmt(sh4[[1, 2], :])
    @test totlogcost(3.0, 0.0, ag) ≈ 3.0 * avh_of(sh4, [1, 2]) rtol = 1e-12
    @test totlogcost(3.0, 0.0, ag) > totlogcost(3.0, 0.0, ag.f, ag.a, ag.v, ag.h)   # the separate means understated it
    # the key's own by-product construction, `merge(a, (v = vh, h = 1.0))`, is the same cost by either route
    for idx in ([1, 2], [1, 3], [2, 3], [1, 2, 3])
        a = aggshmt(sh4[idx, :])
        vh = sum(sh4.f[idx] .* sh4.v[idx] .* sh4.h[idx]) / a.f
        @test minTLC(a, tr).TLCᵒ ≈ minTLC(merge(a, (v = vh, h = 1.0)), tr).TLCᵒ rtol = 1e-12
        @test minTLC(a, tr, ppiLTL).TLCᵒ ≈ minTLC(merge(a, (v = vh, h = 1.0)), tr, ppiLTL).TLCᵒ rtol = 1e-9
    end
    # a row that has no avh is costed from a, v, h as before (NamedTuple and DataFrameRow forms)
    row = (f = 75, s = 12, a = 1, v = 12_000, h = 0.3, d = 625)
    @test totlogcost(2.0, 100.0, row) == totlogcost(2.0, 100.0, row.f, row.a, row.v, row.h)
    @test totlogcost(2.0, 100.0, DataFrame([row])[1, :]) == totlogcost(2.0, 100.0, row)
    @test totlogcost(2.0, 100.0, merge(row, (avh = missing,))) == totlogcost(2.0, 100.0, row)   # a missing avh falls back
    # a stale avh after a hand edit is the caller's: dropping it restores a·v·h
    stale = merge(ag, (v = 1.0,))
    @test stale.avh == ag.avh
    @test !hasproperty(Base.structdiff(stale, (avh = 0,)), :avh)

    # Q5's shapes: the retailers' mixes by aggshmt, then stacked under the suppliers' shipments
    F = [30.0 10.0; 5.0 40.0; 20.0 20.0]                          # product x retailer, ton/yr
    shS = DataFrame(f = vec(sum(F; dims = 2)), s = sh4.s, a = 0.5, v = sh4.v, h = sh4.h, d = [300.0, 200.0, 100.0])
    shR = DataFrame([aggshmt(DataFrame(f = F[:, j], s = sh4.s, a = 0.5, v = sh4.v, h = sh4.h, d = [150.0, 90.0][j]))
                     for j in 1:2])
    @test "avh" in names(shR) && !("avh" in names(shS))
    # (1) as HW 3 writes it (`vcat(shS, DataFrame([byproduct(j) ...]))`): the column sets differ, so it stops
    @test_throws ArgumentError vcat(shS, shR)
    # (2) the one-line fix: keep the columns both tables have
    s2 = vcat(shS, shR; cols = :intersect)
    @test names(s2) == names(shS) && nrow(s2) == 5
    # (3) a projection `shC[:, names(shS)]` drops avh silently: the deliveries stay on the separate averages
    s3 = vcat(shS, shR[:, names(shS)])
    @test s3 == s2
    r = s3[4, :]
    @test totlogcost(1.0, 50.0, r) == totlogcost(1.0, 50.0, r.f, r.a, r.v, r.h)
    # (4) cols = :union keeps avh; the suppliers' rows have none (missing) and are costed from a, v, h
    s4 = vcat(shS, shR; cols = :union)
    @test ismissing(s4.avh[1]) && !ismissing(s4.avh[4]) && nrow(s4) == 5
    @test totlogcost(1.0, 50.0, s4[1, :]) == totlogcost(1.0, 50.0, shS[1, :])
    @test totlogcost(1.0, 50.0, s4[4, :]) == totlogcost(1.0, 50.0, shR[1, :])
    @test minTLC(s4[1, :], tr).TLCᵒ == minTLC(shS[1, :], tr).TLCᵒ
    @test minTLC(s4[5, :], tr).TLCᵒ ≈ minTLC(shR[2, :], tr).TLCᵒ rtol = 1e-12
    # the deliveries valued by avh cost more than on the separate averages, as in HW 3 Q4
    @test minTLC(shR[1, :], tr).TLCᵒ > minTLC(NamedTuple(shR[1, [:f, :s, :a, :v, :h, :d]]), tr).TLCᵒ
end

@testset "charge_tl derives r from ppi only when r is not passed (D5)" begin
    ppi = 131.0
    r = 2.00ppi / 102.7                                       # the lectures' own escalation
    @test charge_tl(10.0, 8.0, 500.0; ppi = ppi) == charge_tl(10.0, 8.0, 500.0; r = r, ppi = ppi)
    @test charge_tl(10.0, 8.0, 500.0; ppi = ppi) ≈ r * 500
    @test charge_tl(10.0, 8.0, 500.0) == 1000.0                # default ppi: r = 2.00, as before
    @test charge_tl(10.0, 8.0, 500.0; r = 2.0, ppi = ppi) == 1000.0   # a passed r is never re-escalated
    @test charge_tl(6.0, 40/9, 532; r = r, Kwt = 25, Kcu = 2750, ppi = ppi) ≈ 1357.1957156767282   # 3.2 Ex. 1(c)
    tr = (r = 3.0, Kwt = 25, Kcu = 2750, ppi = 131.0)         # the struct form passes tr.r, so it is never derived
    @test charge_tl(10.0, (s = 8.0, d = 500.0), tr) == 1500.0
    # the minimum follows ppi in both cases
    @test charge_tl(10.0, 8.0, 5.0; ppi = ppi) == mincharge_tl(; ppi = ppi)
end

@testset "minTLC keyword form beside the positional form; qmax_ltl; the LTL bracket guard (S6, R5/S7)" begin
    sh = (f = 20.0, s = 40/9, a = 1.0, v = 25_000.0, h = 0.30, d = 532.0)
    tr = (r = 2.00 * 131.0 / 102.7, Kwt = 25.0, Kcu = 2750.0, ppi = 131.0)
    row = DataFrame([sh])[1, :]
    for s_ in (sh, row), v_ in (25_000.0, 85_000.0)
        s = s_ === sh ? merge(sh, (v = v_,)) : DataFrame([merge(sh, (v = v_,))])[1, :]
        # the same call every way: positional (kept), keyword, mixed
        @test minTLC(s, tr, 177.4) == minTLC(s; tr = tr, ppi_ltl = 177.4)
        @test minTLC(s, tr; ppi_ltl = 177.4) == minTLC(s, tr, 177.4)
        @test minTLC(s, nothing; ppi_ltl = 177.4) == minTLC(s, nothing, 177.4) == minTLC(s; ppi_ltl = 177.4)
        @test minTLC(s, tr) == minTLC(s; tr = tr)
    end
    @test minTLC(sh) == (qᵒ = nothing, TLCᵒ = Inf, isLTL = false) == minTLC(sh; tr = nothing, ppi_ltl = nothing)
    # the same argument both ways is an error, not a silent choice
    @test_throws ArgumentError minTLC(sh, tr; tr = tr)
    @test_throws ArgumentError minTLC(sh, tr, 177.4; ppi_ltl = 177.4)
    @test minTLC(sh; ppi_ltl = 177.4).isLTL == true
    # qmax_ltl: the bound rate_ltl is defined to, and the one minTLC searches up to
    @test qmax_ltl(40/9) ≈ 650 * (40/9) / 2000 && qmax_ltl(40.0) == 5.0 && qmax_ltl(8.0) == 2.6
    @test qmax_ltl([8.0, 40.0]) == [2.6, 5.0]
    for s in (0.5, 3.0, 8.0, 12.0, 40/9, 30.0, 60.0)
        qm = qmax_ltl(s)
        @test isfinite(rate_ltl(qm * (1 - 1e-9), s, 300.0))      # finite at the bound,
        @test isinf(rate_ltl(qm * (1 + 1e-6), s, 300.0))         # Inf just above it
    end
    # the optimum never sits above the bound
    for s in (3.0, 4.0, 12.0, 40.0)
        r = minTLC((f = 500.0, s = s, a = 0.5, v = 50_000.0, h = 0.3, d = 900.0); ppi_ltl = 177.4)
        @test r.isLTL && r.qᵒ <= qmax_ltl(s) + 1e-8
    end
    # bracket guard: below 150/650 lb/ft^3 no LTL size exists, and the LTL option is left out
    thin = (f = 20.0, s = 0.2, a = 1.0, v = 25_000.0, h = 0.30, d = 532.0)
    @test qmax_ltl(thin.s) < 150/2000
    @test minTLC(thin; ppi_ltl = 177.4) == (qᵒ = nothing, TLCᵒ = Inf, isLTL = false)
    both = minTLC(thin; tr = tr, ppi_ltl = 177.4)
    @test both == minTLC(thin; tr = tr) && both.isLTL == false
    # beyond the estimate's range (N31, documented): no LTL option, no warning, no error
    far = merge(sh, (d = 4000.0,))
    @test (@test_logs minTLC(far; ppi_ltl = 177.4)) == (qᵒ = nothing, TLCᵒ = Inf, isLTL = false)
    @test (@test_logs minTLC(far; tr = tr, ppi_ltl = 177.4)) == minTLC(far; tr = tr)
    # a lecture that defines its own qmax_ltl after `using Logjam` still runs (the name is exported)
    m = Module(:QmaxLtlCollide)
    Core.eval(m, :(using Logjam))
    Core.eval(m, :(qmax_ltl(s) = 650s / 2000))               # the lecture's own copy of the bound
    @test Core.eval(m, :(qmax_ltl(4.0))) == 1.3
    @test Core.eval(m, :(minTLC((f = 20.0, s = 40/9, a = 1.0, v = 25_000.0, h = 0.30, d = 532.0); ppi_ltl = 177.4))).isLTL
    m2 = Module(:QmaxLtlCollide2)                            # the other order: call the export, then define
    Core.eval(m2, :(using Logjam))
    @test Core.eval(m2, :(qmax_ltl(4.0))) == 1.3
    Core.eval(m2, :(qmax_ltl(s) = 650s / 2000))
    @test Core.eval(m2, :(qmax_ltl(4.0))) == 1.3
end

@testset "totlogcost: Inf for a shipment of no size with a positive charge (N31)" begin
    @test totlogcost(0.0, 100.0, 100.0, 0.5, 1000.0, 0.25) == Inf
    @test totlogcost(0.0, 100.0, (f = 100.0, a = 0.5, v = 1000.0, h = 0.25)) == Inf
    @test totlogcost(0.0, 100.0, (f = 100.0, a = 0.5, v = 1000.0, h = 0.25, avh = 125.0)) == Inf
    @test totlogcost(0.0, 0.0, 100.0, 0.5, 1000.0, 0.25) == 0.0         # nothing paid, nothing carried
    @test totlogcost(0.0, 100.0, 0.0, 0.5, 1000.0, 0.25) == 0.0         # no demand, nothing to carry
    @test totlogcost(-1.0, 100.0, 100.0, 0.5, 1000.0, 0.25) == Inf      # a negative size is not a shipment
    @test totlogcost([0.0, 5.0], 450.0, 100.0, 0.5, 1000.0, 0.25) == [Inf, 9625.0]   # element by element
    @test totlogcost(5.0, 450.0, 100.0, 0.5, 1000.0, 0.25) == 9625.0    # the ordinary call is unchanged
end

@testset "P8: transport_costs is removed" begin
    @test !isdefined(Logjam, :transport_costs)
    @test !(:transport_costs in names(Logjam))
    # what replaces it: the cheaper mode's charge of one shipment is the smaller of charge_tl and charge_ltl
    # (Matlog's transcharge, Lecture 3.4's own c0); Logjam.c0 itself was removed before the release (TRN13)
    @test !isdefined(Logjam, :c0) && !isdefined(Logjam, :tlc_uc) && !isdefined(Logjam, :tlc_xd)
end
