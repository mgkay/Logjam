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
