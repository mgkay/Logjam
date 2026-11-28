# test_transtools.jl -- the tests of src/transtools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_transtools.jl, its lines 1-739 ====
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

# ==== moved from test/test_transport_pins.jl, its lines 1-24 ====
# test_transport_pins.jl -- value equality of the course's transport calls against the committed fixture
# (PCV K6, plan principle 9). A call the course makes today keeps returning what it returned at v0.2.8.
# Only a case named for a ruled item (N2_, N3_, N4_, CR14_, CR15_, D5_, N21_, N31_) may differ, and each
# fixture update is named in its commit. Regenerate with tools/v0_3_0/make_transport_pins.jl.
# No case touches the network.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "transport_pin_helpers.jl"))

@testset "transport calls are pinned value for value" begin
    fixture = trpin_read()
    cases = trpin_cases()
    @test length(fixture) == length(cases)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(fixture, name)
            haskey(fixture, name) || continue
            @test trpin_run(thunk) == fixture[name]
        end
    end
end

# ==== moved from test/test_properties.jl, its lines 1-16, 27-27, 123-140, 265-283 ====
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

@testset "transtools: properties" begin

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

# ==== moved from test/test_oracles.jl, its lines 1-31, 38-38, 185-389, 748-749 ====
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

@testset "transtools: oracles" begin

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

end # oracles

# ==== moved from test/test_transtools_v031.jl, its lines 1-549 ====
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
