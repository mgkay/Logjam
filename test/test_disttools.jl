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
end
