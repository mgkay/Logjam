using Test
using Logjam
using SparseArrays
using Random

@testset "Facility Location (loctools)" begin

    # Test data: 3x3 symmetric cost matrix
    k = [10.0, 10.0, 15.0]
    C = [0.0 3.0 7.0;
         3.0 0.0 4.0;
         7.0 4.0 0.0]

    @testset "ufladd" begin
        # Test with scalar k
        y, TC = ufladd(10.0, C)
        @test length(y) > 0
        @test TC < Inf
        @test all(i -> 1 <= i <= 3, y)

        # Test with vector k (don't assert specific solution, heuristic may vary)
        y, TC = ufladd(k, C)
        @test length(y) > 0
        @test TC < Inf
        @test all(i -> 1 <= i <= 3, y)

        # Test with p parameter (fixed number of facilities)
        y, TC = ufladd(k, C; p=2)
        @test length(y) == 2
        @test TC < Inf

        # Test with initial solution
        y, TC = ufladd(k, C; y=[1])
        @test 1 ∈ y
        @test TC < Inf
    end

    @testset "ufldrop" begin
        # Test starting from all facilities
        y, TC = ufldrop(k, C)
        @test length(y) > 0
        @test TC < Inf
        @test all(i -> 1 <= i <= 3, y)

        # Test with p parameter
        y, TC = ufldrop(k, C; p=2)
        @test length(y) == 2
        @test TC < Inf

        # Test with initial solution
        y, TC = ufldrop(k, C; y=[1, 2, 3])
        @test length(y) > 0
        @test TC < Inf
    end

    @testset "uflxchg" begin
        # Test exchange improvement
        y_init = [1, 3]
        y, TC = uflxchg(k, C, y_init)
        @test length(y) == length(y_init)
        @test TC < Inf
        @test all(i -> 1 <= i <= 3, y)

        # TC should be <= initial TC (improvement or same)
        fTC(y) = sum(k[y]) + sum(minimum(C[y, :], dims=1))
        @test TC <= fTC(y_init)
    end

    @testset "ufl" begin
        # Test hybrid heuristic with verbose output
        y, TC = ufl(k, C; verbose=true)
        @test length(y) > 0
        @test TC < Inf
        @test all(i -> 1 <= i <= 3, y)

        # Test with verbose=false
        y_quiet, TC_quiet = ufl(k, C; verbose=false)
        @test length(y_quiet) > 0
        @test TC_quiet < Inf

        # Regression: Set comparison uses value equality (!=), not identity (!==)
        # With identity check, ufl would always run an extra iteration
        y1, TC1 = ufl(k, C; verbose=false)
        y2, TC2 = ufl(k, C; verbose=false)
        @test Set(y1) == Set(y2)  # Deterministic heuristic produces same result
        @test TC1 == TC2
    end

    @testset "uflxchg no aliasing (R5 core)" begin
        # Regression: uflxchg used to mutate and return the SAME object it was
        # passed, which made ufl's ADD/DROP refinement branch dead code.
        y_in = [1, 3]
        y_out, _, _ = uflxchg(k, C, y_in)
        @test y_out !== y_in        # returns a fresh vector, never the caller's
        @test y_in == [1, 3]        # caller's vector left untouched
    end

    @testset "ufl refinement branch runs (R5)" begin
        # Instance where a single ADD+EXCHANGE pass is suboptimal but the
        # ADD/DROP refinement improves it. Pre-fix, ufl == single ADD+EXCHANGE
        # (refinement was unreachable), so this would fail.
        kR = fill(4.0, 4)
        CR = [0.0 8.0 9.0 5.0;
              8.0 0.0 5.0 1.0;
              6.0 4.0 0.0 8.0;
              4.0 4.0 5.0 0.0]
        ya, _, _ = ufladd(kR, CR)
        _, TCx, _ = uflxchg(kR, CR, ya)   # single ADD+EXCHANGE (pre-fix ufl result)
        yf, TCf, _ = ufl(kR, CR; verbose=false)
        @test TCf <= TCx
        @test TCf < TCx                    # refinement branch executed and improved
        @test TCf ≈ 13.0
        @test TCx ≈ 14.0
    end

    @testset "docstring numerics (R6)" begin
        # ufl docstring example — value re-run from the fixed code.
        y_ex, TC_ex, _ = ufl([10, 10, 15], [0 3 7; 3 0 4; 7 4 0]; verbose=false)
        @test TC_ex == 17
        @test Set(y_ex) == Set([2])
        # d2 docstring example.
        @test d2([1, 2, 3], [4, 6, 2]) ≈ 5.0990 atol=1e-4
    end

    @testset "pmedian" begin
        # Test p-median with p=2
        y, TC = pmedian(2, C; verbose=true)
        @test length(y) == 2
        @test TC < Inf
        @test all(i -> 1 <= i <= 3, y)

        # Test error for invalid p
        @test_throws ErrorException pmedian(0, C; verbose=false)
        @test_throws ErrorException pmedian(4, C; verbose=false)

        # Test with verbose=false
        y_quiet, TC_quiet = pmedian(2, C; verbose=false)
        @test length(y_quiet) == 2
    end

    @testset "randX" begin
        # Test with 2D points
        P = [0.0 0.0; 2.0 0.0; 2.0 3.0]
        X = randX(P, 5)
        @test size(X) == (5, 2)
        @test all(0 .<= X[:, 1] .<= 2)
        @test all(0 .<= X[:, 2] .<= 3)

        # Test with single point
        P_single = [1.0 2.0]
        X = randX(P_single, 3)
        @test size(X) == (3, 2)
        @test all(X[:, 1] .== 1.0)
        @test all(X[:, 2] .== 2.0)

        # Test default n=1
        X = randX(P)
        @test size(X) == (1, 2)

        # Test error cases
        @test_throws ErrorException randX(P, 0)
        @test_throws ErrorException randX(zeros(0, 2), 1)  # Empty matrix
    end

    @testset "Larger problem" begin
        # Test with larger problem
        n, m = 10, 20
        k_large = fill(100.0, n)
        C_large = rand(n, m) .* 10

        # Test all methods complete without error
        y1, TC1 = ufladd(k_large, C_large)
        @test length(y1) > 0
        @test TC1 < Inf

        y2, TC2 = ufldrop(k_large, C_large)
        @test length(y2) > 0
        @test TC2 < Inf

        y3, TC3 = ufl(k_large, C_large; verbose=false)
        @test length(y3) > 0
        @test TC3 < Inf

        # Hybrid should be at least as good as ADD alone
        @test TC3 <= TC1
    end

    @testset "Allocation Matrix Output" begin
        k = [10.0, 10.0, 15.0]
        C = [0.0 3.0 7.0 10.0;
             3.0 0.0 4.0 8.0;
             7.0 4.0 0.0 5.0]

        @testset "ufladd returns W" begin
            y, TC, W = ufladd(k, C)
            @test size(W) == (3, 4)
            @test issparse(W)
            @test all(sum(W, dims=1) .== 1)
            @test all(sum(W[setdiff(1:3, y), :], dims=2) .== 0)
        end

        @testset "ufldrop returns W" begin
            y, TC, W = ufldrop(k, C)
            @test size(W) == (3, 4)
            @test issparse(W)
            @test all(sum(W, dims=1) .== 1)
        end

        @testset "uflxchg returns W" begin
            y, TC, W = uflxchg(k, C, [1, 2])
            @test size(W) == (3, 4)
            @test issparse(W)
            @test all(sum(W, dims=1) .== 1)
        end

        @testset "ufl returns W" begin
            y, TC, W = ufl(k, C; verbose=false)
            @test size(W) == (3, 4)
            @test issparse(W)
            @test all(sum(W, dims=1) .== 1)
        end

        @testset "pmedian returns W" begin
            y, TC, W = pmedian(2, C; verbose=false)
            @test size(W) == (3, 4)
            @test issparse(W)
            @test all(sum(W, dims=1) .== 1)
            @test sum(sum(W, dims=2) .> 0) == 2
        end

        @testset "Backward compatibility" begin
            y, TC = ufl(k, C; verbose=false)
            @test length(y) > 0
            @test TC < Inf
        end

        @testset "Allocation correctness" begin
            y, TC, W = ufl(k, C; verbose=false)
            for j in 1:4
                facility_idx = findfirst(W[:, j] .> 0)
                @test facility_idx !== nothing
                @test facility_idx in y
                @test C[facility_idx, j] == minimum(C[y, j])
            end
        end
    end

    @testset "ala (alternating location–allocation)" begin
        # Demand points (Euclidean coordinates) shared across the ala tests.
        P = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0]
        w = [1.0, 1.0, 1.0, 1.0]

        @testset "N1: orphan relocation" begin
            Random.seed!(20270705)
            # Facility 3 starts far away and would never be nearest → orphaned.
            X0 = [0.2 0.2; 0.8 0.8; 100.0 100.0]
            X, TC, W = ala(X0, w, P; dist=2)
            @test size(X, 1) == 3                      # all facilities retained
            @test size(W) == (3, 4)
            @test !any(vec(sum(W, dims=2)) .== 0)      # no all-zero (orphaned) row
            @test all(sum(W, dims=1) .≈ 1.0)           # every demand point allocated once
            @test TC < Inf
        end

        @testset "N2: custom alloc/locate handles honored" begin
            # Custom allocate forces a fixed partition: facilities {1,2} serve {1,2}/{3,4}.
            Wfixed = sparse([1, 1, 2, 2], [1, 2, 3, 4], w, 2, 4)
            myalloc = X -> (Wfixed, sum(Wfixed .* dists(X, P, 2)))
            # Custom locate always parks every facility at the origin.
            mylocate = (W, X) -> zeros(size(X))
            X0 = [50.0 50.0; -50.0 -50.0]
            X, TC, W = ala(X0, w, P; dist=2, alloc=myalloc, locate=mylocate)
            @test W == Wfixed                          # custom allocation honored
            @test all(X .== 0.0)                        # custom locate honored
        end

        @testset "N3: nruns returns best-of" begin
            X0 = [0.9 0.1; 0.1 0.9]
            Random.seed!(4242)
            _, TC1, _ = ala(X0, w, P; dist=2, nruns=1)
            Random.seed!(4242)
            _, TC5, _ = ala(X0, w, P; dist=2, nruns=5)
            # Run 1 is identical (same seed, same X0), extra runs can only improve.
            @test TC5 <= TC1 + 1e-9
        end

        @testset "NC-cities smoke (great-circle)" begin
            Random.seed!(1)
            # Raleigh, Charlotte, Greensboro, Wilmington (LON, LAT) with population weights.
            Pnc = [-78.64 35.78; -80.84 35.23; -79.79 36.07; -77.94 34.23]
            wnc = [469.0, 897.0, 299.0, 123.0]
            X0 = [-78.6 35.8; -80.0 35.5]
            X, TC, W = ala(X0, wnc, Pnc)               # dist=:mi default
            @test size(X) == (2, 2)
            @test size(W) == (2, 4)
            @test issparse(W)
            @test !any(vec(sum(W, dims=2)) .== 0)
            @test TC > 0 && TC < Inf
        end
    end
end
