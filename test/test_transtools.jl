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
        # T1.1a: NamedTuple
        @test rate_ltl(1.0, sh_nt, ppi_ltl) ≈ rate_ltl(1.0, sh_nt.s, sh_nt.d; ppi=ppi_ltl) rtol=1e-4
        # T1.1b: DataFrameRow
        @test rate_ltl(1.0, sh_df, ppi_ltl) ≈ rate_ltl(1.0, sh_nt.s, sh_nt.d; ppi=ppi_ltl) rtol=1e-4
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
        # Test single truckload (within capacity)
        c = charge_tl(10.0, 500.0, 8.0)
        @test c > 0
        @test c ≈ max(2.00 * 500.0, 45.0)  # Should be distance-based, not minimum

        # Test minimum charge applies for short distances
        c_short = charge_tl(10.0, 10.0, 8.0)
        @test c_short >= 45.0

        # Test multiple trucks needed
        # 30 tons at 8 lb/ft³: q_max = min(25, 8*2750/2000) = min(25, 11) = 11 tons
        # Need ceil(30/11) = 3 trucks
        c_multi = charge_tl(30.0, 500.0, 8.0)
        c_single = charge_tl(10.0, 500.0, 8.0)
        @test c_multi > 2 * c_single  # At least 2x more

        # Test cube-limited vs weight-limited
        c_light = charge_tl(10.0, 500.0, 5.0)   # Cube-limited: 5*2750/2000 = 6.875 tons
        c_heavy = charge_tl(10.0, 500.0, 20.0)  # Weight-limited: 20*2750/2000 = 27.5, so 25 tons
        @test c_light > c_heavy  # Need more trucks when cube-limited
    end

    @testset "charge_tl struct-form (T1.2)" begin
        sh_nt = (f=10_000, s=4.444, a=0.10, v=25_000, h=0.30, d=500)
        sh_df = DataFrame([sh_nt])[1, :]
        tr = (r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7)
        # T1.2a: NamedTuple
        @test charge_tl(1.0, sh_nt, tr) ≈ charge_tl(1.0, sh_nt.d, sh_nt.s; r=tr.r, Kwt=tr.Kwt, Kcu=tr.Kcu, ppi=tr.ppi) rtol=1e-4
        # T1.2b: DataFrameRow
        @test charge_tl(1.0, sh_df, tr) ≈ charge_tl(1.0, sh_nt.d, sh_nt.s; r=tr.r, Kwt=tr.Kwt, Kcu=tr.Kcu, ppi=tr.ppi) rtol=1e-4
    end

    @testset "charge_ltl" begin
        # Test typical shipment
        c = charge_ltl(0.5, 250.0, 8.0)
        @test c > 0
        @test !isinf(c)

        # Test minimum charge applies
        r = rate_ltl(0.1, 10.0, 100.0)
        c_calc = r * 0.1 * 100.0
        c_actual = charge_ltl(0.1, 100.0, 10.0)
        mc = mincharge_ltl(100.0)
        @test c_actual >= mc  # Should be at least minimum

        # Test out-of-bounds returns Inf
        c_invalid = charge_ltl(6.0, 250.0, 8.0)
        @test isinf(c_invalid)
    end

    @testset "charge_ltl struct-form (T1.3)" begin
        sh_nt = (f=10_000, s=4.444, a=0.10, v=25_000, h=0.30, d=500)
        sh_df = DataFrame([sh_nt])[1, :]
        ppi_ltl = 104.2
        # T1.3a: NamedTuple
        @test charge_ltl(1.0, sh_nt, ppi_ltl) ≈ charge_ltl(1.0, sh_nt.d, sh_nt.s; ppi=ppi_ltl) rtol=1e-4
        # T1.3b: DataFrameRow
        @test charge_ltl(1.0, sh_df, ppi_ltl) ≈ charge_ltl(1.0, sh_nt.d, sh_nt.s; ppi=ppi_ltl) rtol=1e-4
    end

    @testset "maxpayld" begin
        # Test weight-limited
        q = maxpayld(25.0, 25.0, 2750.0)
        @test q == 25.0  # High density → weight limit

        # Test cube-limited
        q = maxpayld(8.0, 25.0, 2750.0)
        @test q ≈ 8.0 * 2750.0 / 2000.0  # Low density → cube limit
        @test q == 11.0

        # Test vectorized
        s_vec = [5.0, 10.0, 20.0, 30.0]
        q_vec = maxpayld(s_vec, 25.0, 2750.0)
        @test length(q_vec) == 4
        @test q_vec[1] < 25.0  # Cube-limited
        @test q_vec[4] == 25.0  # Weight-limited
    end

    @testset "maxpayld struct-form (T1.4)" begin
        sh_nt = (f=10_000, s=4.444, a=0.10, v=25_000, h=0.30, d=500)
        sh_df = DataFrame([sh_nt])[1, :]
        tr = (r=2.00, Kwt=25.0, Kcu=2750.0, ppi=102.7)
        # T1.4a: NamedTuple (exact equality — pure arithmetic)
        @test maxpayld(sh_nt, tr) == maxpayld(sh_nt.s, tr.Kwt, tr.Kcu)
        # T1.4b: DataFrameRow
        @test maxpayld(sh_df, tr) == maxpayld(sh_nt.s, tr.Kwt, tr.Kcu)
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

        agg_q = aggshmt(df_q)
        @test agg_q.f ≈ 45.0  # Uses q for weighting
    end

    @testset "transport_costs" begin
        # Test auto mode selection
        shipments = DataFrame(
            weight = [0.5, 2.0, 15.0, 30.0],
            density = [8.0, 10.0, 12.0, 15.0],
            distance = [250.0, 500.0, 800.0, 1200.0]
        )

        results = transport_costs(shipments; mode=:auto)
        @test nrow(results) == 4
        @test hasproperty(results, :cost)
        @test hasproperty(results, :mode)
        @test hasproperty(results, :rate)
        @test all(results.cost .> 0)
        @test all(results.mode .∈ Ref([:tl, :ltl]))
        @test all(results.rate .> 0)

        # Small shipments should tend toward LTL
        @test results.mode[1] == :ltl
        @test results.mode[2] == :ltl

        # Large shipments should tend toward TL
        @test results.mode[4] == :tl

        # Test forced TL mode
        results_tl = transport_costs(shipments; mode=:tl)
        @test all(results_tl.mode .== :tl)

        # Test forced LTL mode
        results_ltl = transport_costs(shipments; mode=:ltl)
        @test all(results_ltl.mode .== :ltl)

        # Test with custom PPI
        results_ppi = transport_costs(shipments; mode=:auto, ppi=120.0)
        @test all(results_ppi.cost .>= results.cost)  # Higher PPI → higher costs
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

    @testset "Integration: mode comparison" begin
        # Test that auto mode selects correctly
        q, d, s = 1.0, 500.0, 10.0

        c_tl = charge_tl(q, d, s)
        c_ltl = charge_ltl(q, d, s)

        shipments = DataFrame(weight=[q], density=[s], distance=[d])
        results = transport_costs(shipments; mode=:auto)

        if c_tl <= c_ltl
            @test results.mode[1] == :tl
            @test results.cost[1] ≈ c_tl
        else
            @test results.mode[1] == :ltl
            @test results.cost[1] ≈ c_ltl
        end
    end
end
