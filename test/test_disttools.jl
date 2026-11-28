# test_disttools.jl -- the tests of src/disttools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_disttools.jl, its lines 1-190 ====
using Test
using Logjam

@testset "Distance Tools (disttools)" begin

    @testset "N4: dgca area-adjusted great-circle" begin
        # Facilities and demand points (LON, LAT).
        X  = [-78.64 35.78; -80.84 35.23]     # Raleigh, Charlotte
        Xa = [-79.79 36.07; -77.94 34.23]     # Greensboro, Wilmington

        # Raw great-circle distances (re-run from dgc) for cross-checks.
        gc = [dgc(X[i, :], Xa[j, :]) for i in 1:2, j in 1:2]

        # Column 1 area 0 → floor 0 → equals dgc; column 2 area 500 mi²
        # (floor ≈ 8.41 mi) never dominates these >100 mi distances → equals dgc.
        D = dgca(X, Xa, [0.0, 500.0])
        @test size(D) == (2, 2)
        @test D ≈ gc rtol=1e-6                      # dgc dominates everywhere here

        # a = 0 ⇒ exactly dgc (known 2-point value to rtol=1e-6).
        @test D[1, 1] ≈ 67.39045612963626 rtol=1e-6
        @test D[2, 1] ≈ 82.72590695377839 rtol=1e-6

        # Area dominates: a = 1e7 mi² ⇒ floor ≈ 1189.4 mi > any dgc here.
        floor1 = (2 / 3) * sqrt(1e7 / π)
        D2 = dgca(X, Xa, [1e7, 0.0])
        @test D2[1, 1] ≈ floor1 rtol=1e-6           # floor overrides dgc
        @test D2[2, 1] ≈ floor1 rtol=1e-6
        @test D2[1, 2] ≈ gc[1, 2] rtol=1e-6         # column 2 (a=0) still dgc
        @test D2[2, 2] ≈ gc[2, 2] rtol=1e-6

        # No circuity applied: element equals the plain max, not scaled.
        @test D2[1, 1] ≈ max(gc[1, 1], floor1) rtol=1e-6

        # unit passthrough (km) equals dgc where area is 0.
        Dkm = dgca(X, Xa, [0.0, 0.0]; unit=:km)
        @test Dkm[1, 1] ≈ dgc(X[1, :], Xa[1, :]; unit=:km) rtol=1e-6

        # Input validation.
        @test_throws ErrorException dgca(X, Xa, [1.0])      # length mismatch
        @test_throws ErrorException dgca(X, Xa, [-1.0, 1.0]) # negative area
    end

    @testset "N5: dists lₚ / Chebychev" begin
        X1 = [0.0 0.0; 1.0 2.0]
        X2 = [3.0 4.0; -1.0 5.0]

        # Chebychev (p=Inf) = maximum(abs, Δ).
        DInf = dists(X1, X2, Inf)
        for i in 1:2, j in 1:2
            @test DInf[i, j] ≈ maximum(abs, X1[i, :] .- X2[j, :]) rtol=1e-6
        end

        # General lₚ (p=3.0) = (Σ|Δ|³)^(1/3).
        D3 = dists(X1, X2, 3.0)
        for i in 1:2, j in 1:2
            expected = sum(abs.(X1[i, :] .- X2[j, :]) .^ 3)^(1 / 3)
            @test D3[i, j] ≈ expected rtol=1e-6
        end

        # p=2.0 (real) agrees with Euclidean; p=1.0 with Manhattan.
        @test dists(X1, X2, 2.0) ≈ dists(X1, X2, 2) rtol=1e-6
        @test dists(X1, X2, 1.0) ≈ dists(X1, X2, 1) rtol=1e-6

        # Existing Int methods unchanged.
        D1 = dists(X1, X2, 1)
        D2m = dists(X1, X2, 2)
        @test D1[1, 1] ≈ 7.0 rtol=1e-6              # |3|+|4|
        @test D2m[1, 1] ≈ 5.0 rtol=1e-6             # √(9+16)

        # Ordering: for a fixed pair, l₁ ≥ l₂ ≥ l₃ ≥ l∞.
        @test D1[1, 1] ≥ D2m[1, 1] ≥ D3[1, 1] ≥ DInf[1, 1]

        # p < 1 is not a metric → error.
        @test_throws ErrorException dists(X1, X2, 0.5)
    end

    @testset "S1.1: d1 Float64 return contract" begin
        # Integer inputs must still return Float64 (declared return type).
        @test d1([0, 0], [3, 4]) isa Float64
        @test d1([0, 0], [3, 4]) == 7.0
    end
end

# =============================================================================
# K2a: wrong-answer test (test spec Sec. 2). Tagged [ID]; see tools/v0_3_0/run_against.jl.
# =============================================================================

@testset "[N5] d1 and d2 of a vector against a 1xk row throw DimensionMismatch" begin
    # N5: v0.2.8 broadcasts the vector against the row: d1 gives 14.0 (not 7.0), d2 gives 7.07 (not 5.0); fixed in K5
    throws(T, f) = try f(); false catch e; e isa T end
    @test throws(DimensionMismatch, () -> d1([0, 0], [3 4]))
    @test throws(DimensionMismatch, () -> d2([0, 0], [3 4]))
    @test d1([0, 0], [3, 4]) == 7.0                          # control: the intended call is unchanged
    @test d2([0, 0], [3, 4]) == 5.0

    # the other shape mismatches, and the shapes that stay legal (principle 9: same-shape arrays, tuples)
    @test throws(DimensionMismatch, () -> d2([3 4], [0, 0]))             # row against vector, either order
    @test throws(DimensionMismatch, () -> d1([0, 0]', [3, 4]))           # an adjoint is a row
    @test throws(DimensionMismatch, () -> d2([0, 0], reshape([3, 4], 2, 1)))   # a column matrix is not a vector
    @test throws(DimensionMismatch, () -> d1([0, 0, 0], [3, 4]))
    @test d1([0 0], [3 4]) == 7.0 && d2([0 0], [3 4]) == 5.0             # row against row
    @test d1((0, 0), (3, 4)) == 7.0 && d2((0, 0), (3, 4)) == 5.0         # tuples
    P = [3.0 4.0; 6.0 8.0]
    @test d2([0.0, 0.0], P[1, :]) == 5.0                                 # a row of a matrix, P[i, :], is a vector
    @test d2(@view(P[2, :]), P[1, :]) == 5.0
    @test throws(DimensionMismatch, () -> d2([0.0, 0.0], P[1:1, :]))     # P[i:i, :] is the slip N5 catches
end

# =============================================================================
# K5: the distance changes (S15, N19, D7, N27). Each is its own testset, tagged with its ID.
# =============================================================================

@testset "S15: dists(x, X, p): one point returns a vector; unit = is a synonym for the metric" begin
    X = [-78.64 35.78; -80.84 35.23; -82.55 35.60]            # Raleigh, Charlotte, Asheville
    x = [-79.79, 36.07]                                       # Greensboro
    for p in (1, 2, 3, 3.0, Inf, :mi, :km, :rad)
        D = dists(x, X, p)
        @test D isa Vector{Float64} && length(D) == 3
        @test D == vec(dists(reshape(x, 1, 2), X, p))         # exactly the 1×k matrix, flattened
    end
    @test dists(x, X) == dists(x, X, 2)                       # the default metric is Euclidean
    @test dists(x, X, :mi)[1] == dgc(x, X[1, :])              # one great-circle distance
    # the call shapes the course writes today return the same numbers
    @test dists(x, X, :mi) == vec(dists(x', X, :mi)) == dists(reshape(x, 1, :), X, :mi)[:]
    # unit = is the metric when it is a great-circle unit, with or without a positional p
    @test dists(X, X; unit = :mi) == dists(X, X, :mi)
    @test dists(X, X; unit = :km) == dists(X, X, :km)
    @test dists(x, X; unit = :rad) == dists(x, X, :rad)
    @test dists(X, X) == dists(X, X, 2)                       # no keyword, no p: Euclidean, as before
    @test_throws ArgumentError dists(X, X, :mi; unit = :km)   # both spellings at once are refused
    @test_throws ArgumentError dists(X, X; unit = 1)          # unit is a great-circle unit
    @test_throws ErrorException dists(X, X; unit = :ft)       # an unknown unit is an error, as with p = :ft
end

@testset "N19: dists(X, Y, p::Integer) forwards to the real lp method" begin
    X1 = [0.0 0.0; 1.0 2.0]
    X2 = [3.0 4.0; -1.0 5.0]
    for p in (3, 4, 7, Int8(3), UInt(3))
        @test dists(X1, X2, p) == dists(X1, X2, float(p))
    end
    @test dists(X1, X2, 3)[1, 1] ≈ 91^(1 / 3) rtol = 1e-12     # (3³ + 4³)^(1/3)
    @test dists(X1, X2, 1) == dists(X1, X2, 1.0)               # 1 and 2 keep their own methods and values
    @test dists(X1, X2, 2) ≈ dists(X1, X2, 2.0) rtol = 1e-12
    @test_throws ErrorException dists(X1, X2, 0)               # an integer below 1 is not a metric either
    @test_throws ErrorException dists(X1, X2, -3)
end

# DST1, DST2 (ruled 2026-11-21): dgc keeps the sphere only and takes no Earth-model keyword. Matlog's
# latitude-dependent radius is not computed by Logjam; it is written out here, from the arc, only to show
# the difference dgc's docstring states. GC_RADIUS_RTOL is the named tolerance (charge SC 4) within which
# the sphere agrees with Matlog's radius: relative 1e-3, the 0.1% of the docstring (N15 measured 0.08%).
# oracle_helpers.jl defines the same constant with the same value for the MATLAB comparisons.
const GC_RADIUS_RTOL = 1e-3

@testset "DST1: dgc is the sphere only; Matlog's radius differs from it by under 0.1% in North Carolina" begin
    ral, clt = (-78.6382, 35.7796), (-80.8431, 35.2271)
    sph = dgc(ral, clt)
    @test sph ≈ 129.759 atol = 2e-3                           # N15's figure, the constant radius 3958.75 mi
    arc = dgc(ral, clt; unit = :rad)
    @test sph == arc * 3958.75                                # the sphere, in miles and in kilometers
    @test dgc(ral, clt; unit = :km) == arc * 6371.00
    @test dgc(clt, ral) == sph                                # symmetric in its two points
    # Matlog dists.m's radius, (3963.34 - 13.35 |sin(mean lat)|) mi, gives N15's other figure; the sphere is
    # within GC_RADIUS_RTOL of it here, and it is a difference, not an agreement
    s = abs(sin(deg2rad((ral[2] + clt[2]) / 2)))
    ml = arc * (3963.34 - 13.35 * s)
    @test ml ≈ 129.655 atol = 2e-3
    @test isapprox(sph, ml; rtol = GC_RADIUS_RTOL)
    @test !isapprox(sph, ml; rtol = 1e-9)
    # no keyword: `earth` is not accepted (DST1), on dgc or anywhere else (DST2)
    @test_throws MethodError dgc(ral, clt; earth = :matlog)
    @test_throws MethodError dgc(ral, clt; earth = :sphere)
    # dists keeps the same constant radius as dgc
    @test dists([ral[1] ral[2]], [clt[1] clt[2]], :mi)[1] == sph
end

@testset "N27: dgca's example exercises the floor" begin
    X  = [-78.64 35.78; -80.84 35.23]     # Raleigh, Charlotte
    Xa = [-79.79 36.07; -78.90 35.99]     # Greensboro, Durham
    a  = [0.0, 5000.0]
    floor = (2 / 3) * sqrt(5000 / π)
    D0 = dists(X, Xa, :mi)
    D = dgca(X, Xa, a)
    @test D0[1, 2] < floor < D0[2, 2]                         # the floor sits between Raleigh's and Charlotte's distances
    @test D[1, 2] == floor && D[1, 2] > D0[1, 2]              # Raleigh to Durham is floored
    @test D[2, 2] == D0[2, 2]                                 # Charlotte to Durham is not
    @test D[:, 1] == D0[:, 1]                                 # a = 0: no floor
    @test round.(D; digits = 1) == [67.4 26.6; 82.7 121.0]    # the doctest's matrix
end

# ==== moved from test/test_properties.jl, its lines 1-16, 27-27, 235-264, 282-283 ====
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

@testset "disttools: properties" begin

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

end  # properties

# ==== moved from test/test_oracles.jl, its lines 1-31, 38-38, 135-184, 748-749 ====
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

@testset "disttools: oracles" begin

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

end # oracles

# ==== moved from test/test_location_v031.jl, its lines 1-132, 134-209, 494-516 ====
# test_location_v031.jl -- added by PCV WP3 of Logjam v0.3.1 (DK: review A's A5, A7 and A8): the metric kernel
# shared by dists, ala's locate step and dgca; ala's call forms; and the point-set and table alignments of
# wcentroid, uflxchg, lonlat2loc, loc2lonlat and dgca. Test spec Sec. 4. Equality is `==` on every element, or
# `===` where marked bit-identical; no tolerance is used anywhere in this file. The evidence:
#   1. the kernel (A5): v0.3.0's distance bodies, copied below as text, against the current functions bit for bit
#      (`===`) on every metric and on seeded sets of 1 to 20 dimensions; ala's locate step against v0.3.0's with
#      `_aladist` (also for the real 1.0 and 2.0, which locate by d1 and d2). The full record, 333 cases and
#      40,784,366 elements up to 3000 points saved before the kernel was wired in, is
#      tools/v0_3_1/kernel_identity.jl's; this file keeps a fast part of it in the suite;
#   2. ala's metric (A5): `dist = 3` and `1.5` now locate (they were an error), and `unit` is `dist`'s synonym;
#   3. ala's call forms (A7), each `==` to the call the course writes today, on the course's inputs:
#      `ala(X0, alloc, P)` on Lecture 2.3's contract (Code block 16), 3.4's Lowe's network (Code block 30) and
#      2.4's centroids (Code block 21); `ala(n, w, P)` on 2.3's Code block 14, 2.4's Code block 24 and the HW 1
#      key's Q6(b); `ala(x, w, P)` on 2.2's Examples 3 and 4 (Code blocks 25 and 32) and the HW 1 key's Q6(a);
#      no ambiguity, and every existing call keeps its method;
#   4. the alignments (A8): wcentroid(P, w) on 2.2's and 2.5's points; uflxchg on a range and on Int32 indices on
#      2.4's corridor and EMCA and 2.6's Kudde; lonlat2loc(xy) on 3.4's points; a view of a table where a
#      DataFrame was required;
#   5. dgca(x, Xa, a) against the matrix method's row, on 2.5's North Carolina ZIP codes and EMCA's.
# A lecture's definition is copied here as text, with its .qmd file and line; no companion script is run.

using Test
using Logjam
using DataFrames
using SparseArrays
using Random
import Optim
using Optim: optimize

# ---- v0.3.0's distance bodies, verbatim (the v0.3.0 tag fd0f1f3, which 9b72994 left unchanged:
# src/disttools.jl dgc :39-55, _dists :224-272; src/loctools.jl _aladist :539-551, _ala_locate :590-601). The
# reference for "bit-identical": each is compared with the current function by `===`. ----
module DkV030
using Logjam: d1, d2
using Optim: optimize
function dgc(xy1, xy2; unit=:mi)
    length(xy1) == length(xy2) == 2 || error("Inputs must have length 2.")
    unit in [:mi, :km, :rad] || error("Unit must be :mi, :km, or :rad")

    dx, dy = xy2[1] - xy1[1], xy2[2] - xy1[2]
    a = sind(dy / 2)^2 + cosd(xy1[2]) * cosd(xy2[2]) * sind(dx / 2)^2
    dist_rad = 2 * asin(min(sqrt(a), 1.0))

    # Convert to requested unit
    if unit == :rad
        return dist_rad
    elseif unit == :mi
        return dist_rad * 3958.75
    else  # :km
        return dist_rad * 6371.00
    end
end
_dists(X1::AbstractMatrix, X2::AbstractMatrix, ::Nothing) = _dists(X1, X2, 2)
function _dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Integer)
    if p == 1
        D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            D[i, j] = d1(@view(X1[i, :]), @view(X2[j, :]))
        end
        return D
    elseif p == 2
        D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            D[i, j] = d2(@view(X1[i, :]), @view(X2[j, :]))
        end
        return D
    else
        return _dists(X1, X2, float(p))
    end
end
function _dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Symbol)
    p ∈ [:mi, :km, :rad] || error("Geographic distance requires p ∈ [:mi, :km, :rad]")
    D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
    @inbounds for j in axes(X2, 1), i in axes(X1, 1)
        D[i, j] = dgc(@view(X1[i, :]), @view(X2[j, :]); unit=p)
    end
    return D
end
function _dists(X1::AbstractMatrix, X2::AbstractMatrix, p::Real)
    p >= 1 || error("dists: lₚ metric requires p ≥ 1 (got $p); p<1 is not a metric.")
    D = Matrix{Float64}(undef, size(X1, 1), size(X2, 1))
    if isinf(p)
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            D[i, j] = maximum(abs, @view(X1[i, :]) .- @view(X2[j, :]))
        end
    else
        @inbounds for j in axes(X2, 1), i in axes(X1, 1)
            Δ = @view(X1[i, :]) .- @view(X2[j, :])
            D[i, j] = sum(abs.(Δ) .^ p)^(1 / p)
        end
    end
    return D
end
function _aladist(x, y, dist)
    if dist isa Symbol
        return dgc(x, y; unit=dist)
    elseif dist == 1
        return d1(x, y)
    elseif dist == 2
        return d2(x, y)
    elseif dist == Inf
        return float(maximum(abs.(x .- y)))          # Chebyshev, as `dists(X, Y, Inf)` (N31)
    else
        error("ala: `dist` must be :mi, :km, :rad, 1, 2, or Inf (got $(repr(dist))).")
    end
end
function _ala_locate(W, X, dist, P)
    Xnew = copy(X)
    for i in axes(W, 1)
        J = findall(!iszero, @view W[i, :])
        isempty(J) && continue
        wi = [W[i, j] for j in J]
        x0 = Vector{Float64}(@view X[i, :])
        f(x) = sum(wi[k] * _aladist(x, @view(P[J[k], :]), dist) for k in eachindex(J))
        Xnew[i, :] = optimize(f, x0).minimizer
    end
    return Xnew
end
end # module DkV030

_dk_bitsame(a, b) = typeof(a) == typeof(b) && size(a) == size(b) && all(a .=== b)
# the outcome of a call, a value or the error it raised (its type and message): Int8 coordinates wrap in d2's
# squares, and both versions then raise the same DomainError at the same pair
function _dk_outcome(f)
    try
        return f()
    catch e
        return (typeof(e), sprint(showerror, e))
    end
end
_dk_sameoutcome(a, b) = a isa AbstractArray ? (b isa AbstractArray && _dk_bitsame(a, b)) : a == b
_dk_box(r, m) = hcat(-125 .+ 58 .* rand(r, m), 25 .+ 24 .* rand(r, m))         # the lower 48's box

@testset "WP3 (A5): the metric kernel is bit-identical to v0.3.0's distances" begin
    metrics = Any[nothing, 1, 2, 3, 5, 1.0, 2.0, 1.5, 3.0, Inf, :mi, :km, :rad]
    r = Xoshiro(20261127)
    X1, X2 = _dk_box(r, 300), _dk_box(r, 200)
    for p in metrics
        @test _dk_bitsame(dists(X1, X2, p), DkV030._dists(X1, X2, p))
        @test _dk_bitsame(dists(X1[7, :], X2, p), vec(DkV030._dists(X1[7:7, :], X2, p)))
    end
    @test _dk_bitsame(dists(X1, X2; unit = :km), DkV030._dists(X1, X2, :km))
    # 1 to 20 dimensions: below 16 the kernel sums left to right, as Base's `sum` does there; from 16 it calls the
    # old expression itself
    for d in (1, 2, 3, 15, 16, 17, 20), p in Any[1, 2, 3, 1.5, Inf]
        A, B = randn(r, 40, d) .* 9, randn(r, 30, d) .* 9
        @test _dk_bitsame(dists(A, B, p), DkV030._dists(A, B, p))
    end
    # integer coordinates (Lecture 2.4's `dists(P, P, 1)`), small integers that `sum` widens, Float32, adjoints
    for p in Any[1, 2, 3, Inf]
        A, B = rand(r, -90:90, 25, 2), rand(r, -90:90, 20, 2)
        @test _dk_bitsame(dists(A, B, p), DkV030._dists(A, B, p))
        A8, B8 = Int8.(rand(r, -100:100, 25, 2)), Int8.(rand(r, -100:100, 20, 2))
        @test _dk_sameoutcome(_dk_outcome(() -> dists(A8, B8, p)), _dk_outcome(() -> DkV030._dists(A8, B8, p)))
        A32, B32 = Float32.(X1[1:20, :]), Float32.(X2[1:15, :])
        @test _dk_bitsame(dists(A32, B32, p), DkV030._dists(A32, B32, p))
        @test _dk_bitsame(dists(permutedims(X1[1:9, :])', X2, p), DkV030._dists(permutedims(X1[1:9, :])', X2, p))
    end
    # edge values; no columns; a 1-column set against a 3-column one, which the general metric broadcasts
    E = [0.0 -0.0; 1e300 -1e300; 1e-300 2e-300; 1.0 NaN; Inf 0.0; 3.0 4.0]
    for p in Any[1, 2, 3.0, Inf]
        @test _dk_bitsame(dists(E, E, p), DkV030._dists(E, E, p))
        @test _dk_bitsame(dists(zeros(3, 0), zeros(4, 0), p), DkV030._dists(zeros(3, 0), zeros(4, 0), p))
    end
    G = [0.0 0.0; 180.0 0.0; -180.0 0.0; 0.0 90.0; 0.0 -90.0; 179.9 10.0; -179.9 10.0; 1e-12 0.0]
    for u in (:mi, :km, :rad)
        @test _dk_bitsame(dists(G, G, u), DkV030._dists(G, G, u))
    end
    for p in (3.0, Inf)
        @test _dk_bitsame(dists([1.0 2.0]', [1.0 2.0 3.0; -1.0 0.5 4.0], p), DkV030._dists([1.0 2.0]', [1.0 2.0 3.0; -1.0 0.5 4.0], p))
    end
    # the errors of a mismatched shape are the ones the first pair raised
    @test_throws DimensionMismatch dists(ones(2, 1), ones(3, 3), 1)
    @test_throws DimensionMismatch dists(ones(2, 2), ones(3, 3), 3.0)
    @test_throws ErrorException dists(ones(2, 1), ones(3, 1), :mi)
    @test_throws ErrorException dists(ones(2, 2), ones(3, 3), :mi)
    # dgc shares the great-circle arithmetic
    gc = [(_dk_box(r, 1), _dk_box(r, 1)) for _ in 1:500]
    for u in (:mi, :km, :rad)
        @test all(dgc(a, b; unit = u) === DkV030.dgc(a, b; unit = u) for (a, b) in gc)
        @test all(dgc((a[1], a[2]), (b[1], b[2]); unit = u) === DkV030.dgc((a[1], a[2]), (b[1], b[2]); unit = u) for (a, b) in gc)
    end
    @test dgc((0, 0), (0, 1)) === DkV030.dgc((0, 0), (0, 1))
    # per pair, the kernel is d1, d2 and dgc
    for _ in 1:200
        x, y = randn(r, 2), randn(r, 2)
        @test Logjam._pointdist(x, y, Logjam._L1()) === d1(x, y)
        @test Logjam._pointdist(x, y, Logjam._L2()) === d2(x, y)
        @test Logjam._pointdist(x, y, Logjam._GC(:mi)) === dgc(x, y)
    end
    # dgca reaches the kernel through dists
    a = 3000 .* rand(r, 200) .* (rand(r, 200) .> 0.1)
    @test _dk_bitsame(dgca(X1, X2, a), max.(DkV030._dists(X1, X2, :mi), reshape((2 / 3) .* sqrt.(a ./ π), 1, :)))
    # ala's locate step, under every metric it took, on a fixed allocation
    P = _dk_box(r, 400)
    wP = 1 .+ 99 .* rand(r, 400)
    W = sparse([(j - 1) % 3 + 1 for j in 1:400], 1:400, wP, 3, 400)
    X0 = _dk_box(r, 3)
    for dist in Any[1, 2, Inf, :mi, :km, :rad, 1.0, 2.0]
        @test _dk_bitsame(Logjam._ala_locate(W, X0, Logjam._alakernel(dist), P), DkV030._ala_locate(W, X0, dist, P))
    end
    P1 = 500 .* rand(r, 60, 1)
    W1 = sparse([(j - 1) % 2 + 1 for j in 1:60], 1:60, rand(r, 60), 2, 60)
    for dist in Any[1, 2, Inf]
        @test _dk_bitsame(Logjam._ala_locate(W1, [100.0; 300.0;;], Logjam._alakernel(dist), P1),
                      DkV030._ala_locate(W1, [100.0; 300.0;;], dist, P1))
    end
end

@testset "WP3 (A5): dgca for one point is the matrix method's row" begin
    # Lecture 2.5, Code block 15 (2-loc-5.qmd:1497-1498, 1520): North Carolina's three-digit ZIP codes
    z = filter(r -> 270 <= r.ZCTA3 <= 289 && r.POP > 0, uszcta3())
    P = hcat(z.LON, z.LAT)
    Da = dgca(P, P, z.ALAND)
    @test all(dgca(P[i, :], P, z.ALAND) == Da[i, :] for i in axes(P, 1))
    @test dgca(P[3, :], P, z.ALAND) isa Vector{Float64}
    Dk = dgca(P, P, z.ALAND; unit = :km)
    @test all(dgca(P[i, :], P, z.ALAND; unit = :km) == Dk[i, :] for i in axes(P, 1))
    # EMCA's ZIP centroids (2-loc-5.qmd:1591-1601, 1609-1611), and Lecture 2.6's one-by-one form
    # (2-loc-6.qmd:922, `dgca(XDC[i:i, :], XZ[j:j, :], [a])[1]`)
    zip = [270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283,
           284, 285, 286, 287, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299]
    zc = uszcta3()
    iz = [findfirst(==(zi), zc.ZCTA3) for zi in zip]
    Pz = hcat(zc.LON[iz], zc.LAT[iz])
    az = zc.ALAND[iz]
    Dza = dgca(Pz, Pz, az)
    @test all(dgca(Pz[i, :], Pz, az) == Dza[i, :] for i in eachindex(zip))
    @test all(dgca(Pz[i, :], Pz[j:j, :], [az[j]])[1] == dgca(Pz[i:i, :], Pz[j:j, :], [az[j]])[1] for i in 1:5, j in 1:5)
    @test_throws ErrorException dgca(Pz[1, :], Pz, az[1:3])
end

# ==== moved from test/test_boxes_v031.jl, its lines 1-32, 266-413 ====
# test_boxes_v031.jl -- added by PCV WP10 of Logjam v0.3.1 (X7: a city's and a state's box, MakePlan D3; X8: the
# empirical aggregate distance, MakePlan D8). Test spec Sec. 6. Equality is `===` (bit for bit) where marked and `==`
# elsewhere; the tolerances are D3's, Raleigh's box within 0.05 degrees of Nominatim's on every side, and test spec
# Sec. 6's relative 1e-14 against MATLAB's dagg.m, also used for the two closed forms at the branch boundary (26r/23
# and 546r/480, the formula's value at a point, equal to rounding), and one unit in the last place between the
# empirical distance at d = 0, 2r/3 as 2.5's equation writes it, and the default's floor, (2/3)·r. The evidence:
#   1. the place boxes (data/usplacebox, made by tools/v0_3_1/make_placebox.jl from the Census TIGER/Line 2020 place
#      shapefiles): exactly `usplace()`'s keys, one row each, sorted; the CSV the script's output byte for byte (its
#      SHA-256, printed on two runs) and the .jls that CSV read back; every box contains its place's `usplace()`
#      point, all 31,617; Raleigh's box against the Nominatim box CR 28 recorded;
#   2. `mapbbox(name; state, place)`: every county of `uscounty()` gives, bit for bit, the box `mapbbox` gave it at
#      the branch's start, or throws the same error (test/data/county_boxes_f3f0c1b.csv, saved by
#      tools/v0_3_1/save_county_boxes.jl before WP10 changed `mapbbox`); "Durham" in North Carolina is the county,
#      and the city (PLFIP 19000) with `place = true`; a name no county has gives the place; the matching rules (case,
#      the designator, an exact name preferred); every name two places share in a state is an error naming them;
#      every place by its own name gives its own box; `xexpand` and `yexpand` act on a place's box as on a county's;
#   3. `mapbbox(state)`: for every state of `usstate()`, the extent of its counties' boxes, each Lecture 4.2's Code
#      block 3 run on the county's block groups (copied below as text), and so containing each of them;
#   4. `dgca(...; method = :empirical)`: `==` to 2.5's @eq-daemp copied as text on 2.5's Example 4 and 5 inputs, by
#      both of dgca's methods and in another unit; against MATLAB's ise754/dagg.m run on the same distances
#      (test/oracles/dagg_matlab.csv, tools/v0_3_1/make_oracles_v031.m), relative 1e-14 wherever dagg.m applies one
#      case, and where it applies both (d/r from 0.8378 to 1: its second statement tests the matrix its first has
#      changed) its value the second case applied to the first's, above 2.5's equation, which Logjam follows; the
#      branch boundary as dagg.m draws it (26r/23 at d = r, 546r/480 the limit from below); d_a > d for d >= r;
#      2r/3 at d = 0; a zero area; and the default method `===` to v0.3.0's body, copied as text.
# A lecture's definition is copied here as text, with its .qmd file and lines; no companion script is run.

using Test
using Logjam
using DataFrames
using CSV
using Random

# ---- 4. dgca(...; method = :empirical) (X8, MakePlan D8) ---------------------------------------------------------------
# Lecture 2.5's @eq-daemp (2-location/2-loc-5.qmd:1307-1314), as text: r = √(a/π) (@eq-radius, 2.5 Sec. 5), d the
# distance from the point to the region's centroid, d < r the first case and every other d the second
_bx_daemp(d, r) = d < r ? 2r/3 + d/48 + 9d^2/(20r) : d + 3r^2/(23d)

# v0.3.0's dgca, as text (the v0.3.0 tag fd0f1f3, src/disttools.jl:277 and :339-341), which 7e66734 left unchanged
_bx_dgca_v030(X, Xa, a; unit = :mi) = max.(dists(X, Xa, unit), reshape((x -> (2 / 3) * sqrt(x / π)).(a), 1, :))
_bx_bitsame(A, B) = size(A) == size(B) && all(x === y for (x, y) in zip(A, B))

function _bx_readblocks(path)          # "@name,nrows,ncols" blocks, as test/oracle_helpers.jl reads them
    d = Dict{String, Matrix{Float64}}()
    lines = readlines(path)
    i = 1
    while i <= length(lines)
        if startswith(lines[i], "@")
            nm, r, c = split(lines[i][2:end], ',')
            r, c = parse(Int, r), parse(Int, c)
            M = Matrix{Float64}(undef, r, c)
            for k in 1:r
                M[k, :] = parse.(Float64, split(lines[i + k], ','))
            end
            d[String(nm)] = M
            i += r + 1
        else
            i += 1
        end
    end
    return d
end

# Lecture 2.5's inputs to dgca: Example 4's North Carolina three-digit ZIP codes (Code block 15, 2-loc-5.qmd:1497-1498)
# and Example 5's EMCA ZIP centroids (Code block 19, 2-loc-5.qmd:1591-1601), each with its land areas
function _bx_lecture25()
    z = filter(r -> 270 <= r.ZCTA3 <= 289 && r.POP > 0, uszcta3())
    P = hcat(z.LON, z.LAT)
    zip = [270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283,
           284, 285, 286, 287, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299]
    zc = uszcta3()
    iz = [findfirst(==(zi), zc.ZCTA3) for zi in zip]
    Pz = hcat(zc.LON[iz], zc.LAT[iz])
    return ((P, z.ALAND), (Pz, zc.ALAND[iz]))
end

@testset "[WP10 X8] dgca(...; method = :empirical) is 2.5's @eq-daemp on 2.5's inputs" begin
    for (P, a) in _bx_lecture25()
        r = sqrt.(a ./ π)
        Dg = dists(P, P, :mi)
        want = [_bx_daemp(Dg[i, j], r[j]) for i in axes(P, 1), j in axes(P, 1)]
        De = dgca(P, P, a; method = :empirical)
        @test De == want
        @test De isa Matrix{Float64}
        # both methods of dgca take the keyword: one point is the matrix method's row
        @test all(dgca(P[i, :], P, a; method = :empirical) == De[i, :] for i in axes(P, 1))
        # another unit: the same formula on that unit's distances (a in its square)
        Dk = dists(P, P, :km)
        @test dgca(P, P, a; unit = :km, method = :empirical) == [_bx_daemp(Dk[i, j], r[j]) for i in axes(P, 1), j in axes(P, 1)]
        # every point is at d = 0 from itself, so the diagonal is 2r/3, (2/3)√(a/π) as the equation writes it, and the
        # default method's floor, (2/3)·√(a/π), to the last bit or one unit in it
        dg = [De[i, i] for i in axes(P, 1)]
        @test all(Dg[i, i] == 0 for i in axes(P, 1))
        @test dg == 2 .* sqrt.(a ./ π) ./ 3
        @test all(abs.(dg .- Logjam._mean_zone_distance.(a)) .<= eps.(dg))
        # the empirical distance is never below the default's: it adds to d outside the region and to 2r/3 inside it
        @test all(De .>= dgca(P, P, a))
    end
end

@testset "[WP10 X8] :empirical against MATLAB's ise754/dagg.m on the same distances (oracle)" begin
    O = _bx_readblocks(joinpath(@__DIR__, "oracles", "dagg_matlab.csv"))
    a, R, D, Da = vec(O["a"]), vec(O["R"]), O["D"], O["Da"]
    zc = uszcta3()
    # the oracle's areas are 2.5's as Logjam holds them, its radii Logjam's sqrt(a/π), bit for bit
    zk = Int.(vec(O["zcta3"]))
    @test a == [only(zc.ALAND[zc.ZCTA3 .== k]) for k in zk]
    @test sort(zk) == sort(unique(vcat(filter(r -> 270 <= r.ZCTA3 <= 289 && r.POP > 0, zc).ZCTA3, 290:299)))
    r = sqrt.(a ./ π)
    @test r == R
    @test size(D) == size(Da) == (83, length(a))
    # Logjam's formula on the oracle's distances: the kernel dgca(...; method = :empirical) applies to dists' matrix
    L = Logjam._daemp.(D, reshape(r, 1, :))
    @test L == _bx_daemp.(D, reshape(r, 1, :))
    # dagg.m's first statement replaces each d < r by the first case; its second then tests the matrix the first
    # changed, D(D>=R), so a d whose first case is r or more (d/r from 0.8378 to 1) takes the second case on top
    f1 = [D[i, j] < r[j] ? _bx_daemp(D[i, j], r[j]) : NaN for i in axes(D, 1), j in axes(D, 2)]
    both = (D .< reshape(r, 1, :)) .& (f1 .>= reshape(r, 1, :))
    one = .!both
    @test all(isapprox.(L[one], Da[one]; rtol = 1e-14))
    # where dagg.m applies both cases, its value is the second applied to the first, which 2.5's equation is not
    g(d, r) = d + 3r^2/(23d)
    @test all(isapprox(Da[i, j], g(f1[i, j], r[j]); rtol = 1e-14) for i in axes(D, 1), j in axes(D, 2) if both[i, j])
    @test all(L[both] .< Da[both])
    t = vec(O["t"])
    @test count(both) == 4 * length(a)                         # t = 0.85, 0.9, 0.95 and r - eps(r), each area
    @test all(0.8378 < D[i, j] / r[j] < 1 for i in axes(D, 1), j in axes(D, 2) if both[i, j])
end

@testset "[WP10 X8] :empirical's branch boundary is dagg.m's; d_a > d outside the region" begin
    (P, a), (Pz, az) = _bx_lecture25()
    for ar in vcat(a, az, [1.0, 656.0, 5000.0])
        r = sqrt(ar / π)
        # at d = r the second case: 26r/23
        at = Logjam._daemp(r, r)
        @test at == r + 3r^2/(23r)
        @test isapprox(at, 26r / 23; rtol = 1e-14)
        # just below r the first case, whose limit is 546r/480 = 1.1375r: a step of about 0.6% that belongs to the formula
        d = prevfloat(r)
        below = Logjam._daemp(d, r)
        @test below == 2r/3 + d/48 + 9d^2/(20r)
        @test isapprox(below, 546r / 480; rtol = 1e-14)
        @test below > at
        # outside the region it keeps d_a > d (2.5: "a facility beyond a region still pays something for its spread")
        @test all(Logjam._daemp(t * r, r) > t * r for t in 1.0:0.01:100.0)
        # at d = 0, 2r/3
        @test Logjam._daemp(0.0, r) == 2r/3
        # through dgca: a point at distance d from a demand point of area ar
        x = [-78.64, 35.78]
        y = [-78.64, 35.78 + 0.5]
        dd = dgc(x, y)
        @test dgca(x, reshape(y, 1, 2), [ar]; method = :empirical) == [_bx_daemp(dd, r)]
    end
    # a zero area (a point): the distance itself, and 0 at d = 0, where the second case is 0/0
    @test Logjam._daemp(0.0, 0.0) === 0.0
    @test Logjam._daemp(5.0, 0.0) === 5.0
    X = [-78.64 35.78; -80.84 35.23]
    @test dgca(X, X, [0.0, 0.0]; method = :empirical) == dists(X, X, :mi)
end

@testset "[WP10 X8] dgca's default method is unchanged, bit for bit" begin
    (P, a), (Pz, az) = _bx_lecture25()
    rng = Random.Xoshiro(10)
    cases = Any[(P, P, a), (Pz, Pz, az), (P[1:5, :], Pz, az)]
    for m in (1, 7, 200)
        X = hcat(-125 .+ 58 .* rand(rng, m), 25 .+ 24 .* rand(rng, m))
        Xa = hcat(-125 .+ 58 .* rand(rng, 50), 25 .+ 24 .* rand(rng, 50))
        push!(cases, (X, Xa, 3000 .* rand(rng, 50) .* (rand(rng, 50) .> 0.2)))
    end
    for (X, Xa, aa) in cases, unit in (:mi, :km, :rad)
        v030 = _bx_dgca_v030(X, Xa, aa; unit)
        @test _bx_bitsame(dgca(X, Xa, aa; unit), v030)
        @test _bx_bitsame(dgca(X, Xa, aa; unit, method = :max), v030)
        @test _bx_bitsame(dgca(X[1, :], Xa, aa; unit, method = :max), vec(v030[1:1, :]))
    end
    @test_throws ArgumentError dgca(P, P, a; method = :exact)
    @test_throws ArgumentError dgca(P[1, :], P, a; method = "empirical")
    @test_throws ErrorException dgca(P, P, a[1:3]; method = :empirical)
    @test_throws ErrorException dgca(P, P, -a; method = :empirical)
end
