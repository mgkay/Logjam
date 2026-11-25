using Test
using Logjam
using SparseArrays
using Random
using DataFrames

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
        y, TC = pmedian(2, C)
        @test length(y) == 2
        @test TC < Inf
        @test all(i -> 1 <= i <= 3, y)

        # Test error for invalid p
        @test_throws ErrorException pmedian(0, C)
        @test_throws ErrorException pmedian(4, C)

        # Test with verbose=false
        y_quiet, TC_quiet = pmedian(2, C)
        @test length(y_quiet) == 2
    end

    @testset "pmedian verbose keyword kept, default true, ufl's trace (D3, S38)" begin
        # The course calls pmedian(...; verbose = false) (2.7, verify_logjam.jl) and 2.4 relies on the default
        # (four calls). PR #14 removed the keyword; v0.3.0 keeps it, with v0.2.8's default `true` (one rule
        # for the family) and the trace format of ufl: the ADD cost, then the EXCHANGE cost.
        capture(f) = mktemp() do path, io
            r = redirect_stdout(f, io)
            flush(io)
            close(io)
            (r, read(path, String))
        end
        (y0, TC0, W0), out0 = capture(() -> pmedian(2, C))
        (y1, TC1, W1), out1 = capture(() -> pmedian(2, C; verbose = false))
        (y2, TC2, W2), out2 = capture(() -> pmedian(2, C; verbose = true))
        @test (y1, TC1, W1) == (y0, TC0, W0)
        @test (y2, TC2, W2) == (y0, TC0, W0)
        @test out0 == out2                                    # verbose = true is the default
        @test out1 == ""
        @test out2 == "  Add: 3.0
 Xchg: 3.0
"
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
            y, TC, W = pmedian(2, C)
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

        @testset "N1: an unused NF is moved to an EF and the EFs re-allocated (D4)" begin
            # NF 3 starts far away and is nearest to no EF: Matlog's repair moves it to a random EF
            # (v0.2.8 did so but returned the un-relocated X; PR #13 removed it; D4 restores it)
            X0 = [0.2 0.2; 0.8 0.8; 100.0 100.0]
            Random.seed!(1)
            X, TC, W = ala(X0, w, P; dist=2, verbose=false)
            @test size(X, 1) == 3
            @test size(W) == (3, 4)
            @test all(vec(sum(W, dims=2)) .> 0)            # every NF serves some EF
            @test all(sum(W, dims=1) .≈ 1.0)               # every EF still allocated once
            @test TC ≈ sum(W .* dists(X, P, 2))            # TC is the cost at the X returned
            @test all(X[3, :] .< 50)                       # NF 3 has left (100, 100)
        end

        @testset "N2: custom alloc/locate handles honored" begin
            # Custom allocate forces a fixed partition: facilities {1,2} serve {1,2}/{3,4}.
            Wfixed = sparse([1, 1, 2, 2], [1, 2, 3, 4], w, 2, 4)
            myalloc = X -> (Wfixed, sum(Wfixed .* dists(X, P, 2)))
            # Custom locate always parks every facility at the origin.
            mylocate = (W, X) -> zeros(size(X))
            X0 = [50.0 50.0; -50.0 -50.0]
            X, TC, W = ala(X0, w, P; dist=2, alloc=myalloc, locate=mylocate, verbose=false)
            @test W == Wfixed                          # custom allocation honored
            @test all(X .== 0.0)                        # custom locate honored
        end

        @testset "N3: nruns returns best-of" begin
            X0 = [0.9 0.1; 0.1 0.9]
            Random.seed!(4242)
            _, TC1, _ = ala(X0, w, P; dist=2, nruns=1, verbose=false)
            Random.seed!(4242)
            _, TC5, _ = ala(X0, w, P; dist=2, nruns=5, verbose=false)
            # Run 1 is identical (same seed, same X0), extra runs can only improve.
            @test TC5 <= TC1 + 1e-9
        end

        @testset "NC-cities smoke (great-circle)" begin
            Random.seed!(1)
            # Raleigh, Charlotte, Greensboro, Wilmington (LON, LAT) with population weights.
            Pnc = [-78.64 35.78; -80.84 35.23; -79.79 36.07; -77.94 34.23]
            wnc = [469.0, 897.0, 299.0, 123.0]
            X0 = [-78.6 35.8; -80.0 35.5]
            X, TC, W = ala(X0, wnc, Pnc; verbose=false)  # dist=:mi default
            @test size(X) == (2, 2)
            @test size(W) == (2, 4)
            @test issparse(W)
            @test !any(vec(sum(W, dims=2)) .== 0)
            @test TC > 0 && TC < Inf
        end
    end

    @testset "N6: wcentroid (weighted geographic centroid)" begin
        LON = [-78.64, -80.84, -79.79, -77.94]
        LAT = [35.78, 35.23, 36.07, 34.23]
        POP = [469.0, 897.0, 299.0, 123.0]

        # Known weighted centroid to rtol=1e-6 (values re-run from the formula).
        lon, lat = wcentroid(LON, LAT, POP)
        @test lon ≈ -79.88862287042834 rtol=1e-6
        @test lat ≈ 35.4459451901566 rtol=1e-6

        # Returned in (LON, LAT) order — longitude first, and negative (western hemisphere).
        @test lon < 0

        # Latitude is the plain weighted mean of latitudes.
        @test lat ≈ sum(POP .* LAT) / sum(POP) rtol=1e-6
        # Longitude uses cos(lat) weighting.
        cw = POP .* cosd.(LAT)
        @test lon ≈ sum(cw .* LON) / sum(cw) rtol=1e-6

        # Equal weights ⇒ cos-lat-corrected mean (still cos-weighted in longitude).
        lon2, lat2 = wcentroid([-78.0, -80.0], [35.0, 36.0], [1.0, 1.0])
        @test lat2 ≈ 35.5 rtol=1e-6
        c = cosd.([35.0, 36.0])
        @test lon2 ≈ sum(c .* [-78.0, -80.0]) / sum(c) rtol=1e-6

        # Zero total weight errors.
        @test_throws ErrorException wcentroid([-78.0, -80.0], [35.0, 36.0], [0.0, 0.0])

        # Grouped combine: one row per group, columns LON/LAT populated.
        df = DataFrame(
            k   = [:A, :A, :B, :B],
            LON = LON,
            LAT = LAT,
            POP = POP,
        )
        g = combine(groupby(df, :k), [:LON, :LAT, :POP] => wcentroid => [:LON, :LAT])
        @test nrow(g) == 2                             # one row per group
        @test Set(names(g)) == Set(["k", "LON", "LAT"])
        # Group A centroid matches a direct wcentroid call on its rows.
        lonA, latA = wcentroid(LON[1:2], LAT[1:2], POP[1:2])
        rA = g[g.k .== :A, :]
        @test rA.LON[1] ≈ lonA rtol=1e-6
        @test rA.LAT[1] ≈ latA rtol=1e-6
    end

    @testset "S1.2: TC Float64 return contract (integer k/C)" begin
        # Integer fixtures — TC must be promoted to Float64 for all UFL-family fns.
        ki = [10, 10, 15]
        Ci = [0 3 7; 3 0 4; 7 4 0]
        @test ufladd(ki, Ci)[2] isa Float64
        @test ufldrop(ki, Ci)[2] isa Float64
        @test uflxchg(ki, Ci, [1, 3])[2] isa Float64
        @test ufl(ki, Ci; verbose=false)[2] isa Float64
        @test pmedian(2, Ci)[2] isa Float64
    end
end

# =============================================================================
# K2a: wrong-answer tests (test spec Sec. 2) and pin-today tests (Sec. 7).
# Each testset is tagged [ID]; tools/v0_3_0/run_against.jl records its outcome in
# baselines/sc2-outcomes.csv. A `@test_broken` names the component whose commit flips it to `@test`.
# =============================================================================

@testset "[CR 4] ala on the orphan instance: every facility allocated, and TC = the cost at the returned X (D4)" begin
    # three tight clusters of four points and six new facilities: some start has a facility that draws no demand
    centres = [0.0 0.0; 50.0 0.0; 25.0 40.0]
    offs = [-0.3 -0.2; 0.1 0.3; 0.25 -0.1; -0.15 0.2]
    P = vcat([centres[c:c, :] .+ offs for c in 1:3]...)
    w = ones(12)
    tc_ok, all_alloc = true, true
    for seed in 1:40
        Random.seed!(seed)
        X, TC, W = redirect_stdout(devnull) do
            ala(randX(P, 6), w, P; dist = 2)
        end
        tc_ok &= isapprox(TC, sum(W .* dists(X, P, 2)); rtol = 1e-9)
        all_alloc &= all(i -> sum(W[i, :]) > 0, 1:6)
    end
    # TC at the returned X: v0.2.8 relocates an orphan inside the allocate step and returns the un-relocated
    # X, so the two disagree (CR 4). origin/main already fixed this (PR #13, by removal), so it is a plain
    # @test here and the v0.2.8 run is what shows it failing.
    @test tc_ok
    # every returned facility has an allocation: main left an orphan alone (CR 9); D4 restores Matlog's
    # repair with the cost always at the returned X; fixed in K3
    @test all_alloc
end

@testset "[CR 5] ufladd(k, C; y) leaves the caller's y unchanged" begin
    k = [8, 8, 10, 8, 9, 8]
    C = [ 0  3  7 10  6  4
          3  0  4  7  6  7
          7  4  0  3  6  8
         10  7  3  0  7  8
          6  6  6  7  0  2
          4  7  8  8  2  0]
    y0 = [1]
    y, TC, W = ufladd(k, C; y = y0)
    @test length(y) > 1                    # control: the call did add sites
    # CR 5: v0.2.8 push!es onto the caller's vector (y0 becomes the result); fixed in K3 by copying y
    @test y0 == [1]
end

@testset "[S5] pin: the default randX stream equals the locked draws (HW 1 Q5, lecture 2.3)" begin
    # Literal copies of K1's locked draws (baselines/v0_2_8/randx-draws/), recorded at v0.2.8 on Julia 1.12.6:
    # `Random.seed!(s)` and then the lecture's own randX call. v0.3.0's optional `rng` keyword must leave
    # the default stream byte-identical.
    Random.seed!(2073)                     # HW 1 Q5: randX([2 1; 10 7], 10)
    X = randX([2.0 1.0; 10.0 7.0], 10)
    hw1_q5 = [8.259746419726905 6.164815570217012
              6.531983023539856 1.7874693378219046
              7.894160209160504 2.9438679451498255
              8.507788632095755 5.409548282561159
              3.9072091570147176 6.595524125523864
              9.249095003244022 1.0285778599622277
              8.633136602825289 4.5776220760716555
              7.4330003058598155 5.789609402550104
              6.930933697488088 1.6938455841262872
              8.675951412208548 6.145424845672632]
    @test X == hw1_q5

    # lecture 2.3: the NC and SC places over 10,000 people, seed 8345, randX(Pb, 2)
    dfb = filter(r -> r.STFIP in st2fips.([:NC, :SC]) && r.POP > 10_000, usplace())
    Pb = hcat(dfb.LON, dfb.LAT)
    Random.seed!(8345)
    X23 = randX(Pb, 2)
    @test X23 == [-79.0625165241962 34.606732379026106
                  -76.37016494196897 35.85908335253167]
end

@testset "[S43] pin: ala with a caller-fixed locate keeps that facility (HW 1 Q6(c))" begin
    P = [1.0 1.0; 2.0 5.0; 6.0 2.0; 7.0 7.0; 3.0 3.0; 8.0 1.0; 5.0 5.0; 2.0 8.0]
    w = [3.0, 1.0, 2.0, 5.0, 4.0, 2.0, 1.0, 3.0]
    fixed = [3.0 4.0]
    function weiszfeld(Pj, wj, x)
        for _ in 1:200
            d = [max(sqrt(sum((x .- Pj[j, :]) .^ 2)), 1e-12) for j in 1:size(Pj, 1)]
            x = vec(sum((wj ./ d) .* Pj; dims = 1)) ./ sum(wj ./ d)
        end
        return x
    end
    function locfixed(W, X)                 # facility 1 stays where the caller put it
        Xn = copy(X)
        Xn[1, :] = vec(fixed)
        for i in 2:size(X, 1)
            J = findall(!iszero, W[i, :])
            isempty(J) || (Xn[i, :] = weiszfeld(P[J, :], [W[i, j] for j in J], X[i, :]))
        end
        return Xn
    end
    ok = true
    for seed in 1:30
        Random.seed!(seed)
        X, TC, W = redirect_stdout(devnull) do
            ala(vcat(fixed, randX(P, 2)), w, P; dist = 2, locate = locfixed)
        end
        ok &= X[1, :] == vec(fixed)
    end
    @test ok
end

# =============================================================================
# K3 (WP2), the UFL family: CR 5 and CR 6 (ufladd, ufldrop), N13 (input checks, `p` meaning) and N23
# (incremental column minima, same results). Reference = v0.2.8's naive algorithms, rewritten here.
# =============================================================================

@testset "UFL family, K3: ufladd and ufldrop" begin
    ex88k = [8, 8, 10, 8, 9, 8]
    ex88C = [ 0  3  7 10  6  4
              3  0  4  7  6  7
              7  4  0  3  6  8
             10  7  3  0  7  8
              6  6  6  7  0  2
              4  7  8  8  2  0]

    ref_cost(k, C, y) = sum(k[y]) + sum(minimum(C[y, :], dims = 1))
    function ref_add(k, C; y = Int[], p = nothing)         # v0.2.8's ufladd, every candidate re-slices C
        y = copy(y)
        TCo = isempty(y) ? Inf : ref_cost(k, C, y)
        while true
            TC, i = Inf, nothing
            for i2 in setdiff(1:size(C, 1), y)
                TC2 = ref_cost(k, C, vcat(y, i2))
                TC2 < TC && ((TC, i) = (TC2, i2))
            end
            if (p === nothing && TC < TCo) || (p isa Int && length(y) < p)
                TCo = TC; push!(y, i)
            else
                break
            end
        end
        return sort(y), float(TCo)
    end
    function ref_drop(k, C; y = collect(1:size(C, 1)), p = nothing)   # v0.2.8's ufldrop
        y = copy(y)
        TCo = ref_cost(k, C, y)
        while length(y) > 1
            TC, i = Inf, nothing
            for i2 in y
                TC2 = ref_cost(k, C, setdiff(y, i2))
                TC2 < TC && ((TC, i) = (TC2, i2))
            end
            if (p === nothing && TC < TCo) || (p isa Int && length(y) > p)
                TCo = TC; y = setdiff(y, i)
            else
                break
            end
        end
        return sort(y), float(TCo)
    end

    @testset "N23: incremental column minima give v0.2.8's sets and costs" begin
        rng = Random.Xoshiro(23)
        same_add = same_drop = same_addy = same_dropy = same_addp = same_dropp = true
        for _ in 1:60
            n, m = rand(rng, 3:9), rand(rng, 3:12)
            C = float.(rand(rng, 1:40, n, m))
            k = float.(rand(rng, 5:60, n))
            ya, TCa, _ = ufladd(k, C)
            r = ref_add(k, C); same_add &= (ya, TCa) == r
            yd, TCd, _ = ufldrop(k, C)
            r = ref_drop(k, C); same_drop &= (yd, TCd) == r
            y0 = sort(randperm(rng, n)[1:rand(rng, 1:n-1)])
            y1, T1, _ = ufladd(k, C; y = y0)
            r = ref_add(k, C; y = y0); same_addy &= (y1, T1) == r
            y2, T2, _ = ufldrop(k, C; y = y0)
            r = ref_drop(k, C; y = y0); same_dropy &= (y2, T2) == r
            p = rand(rng, 1:n)
            y3, T3, _ = ufladd(k, C; p = p)
            r = ref_add(k, C; p = p); same_addp &= (y3, T3) == r && length(y3) == p
            y4, T4, _ = ufldrop(k, C; p = p)
            r = ref_drop(k, C; p = p); same_dropp &= (y4, T4) == r && length(y4) == p
        end
        @test same_add && same_drop
        @test same_addy && same_dropy
        @test same_addp && same_dropp
    end

    @testset "N13: p is a target, not a cap, and the inputs are checked" begin
        # Example 8.8: the unconstrained ADD stops at two sites (TC 32), p = 4 opens four (TC 37)
        y, TC, _ = ufladd(ex88k, ex88C)
        @test length(y) == 2 && TC == 32.0
        y, TC, _ = ufladd(ex88k, ex88C; p = 4)
        @test length(y) == 4 && TC == 37.0
        y, TC, _ = ufldrop(ex88k, ex88C; p = 4)
        @test y == [1, 2, 4, 6] && TC == 37.0
        for f in (ufladd, ufldrop)
            @test_throws ErrorException f(ex88k, ex88C; p = 0)
            @test_throws ErrorException f(ex88k, ex88C; p = 7)
            @test_throws ErrorException f(ex88k[1:5], ex88C)            # wrong length of k
            @test_throws ErrorException f(-ex88k, ex88C)                # negative k
            @test_throws ErrorException f(-1, ex88C)
            @test_throws ErrorException f(ex88k, ex88C; y = [0, 2])      # site out of range
            @test_throws ErrorException f(ex88k, ex88C; y = [2, 7])
            @test_throws ErrorException f(ex88k, ex88C; y = [2, 2])      # repeated site
        end
        # ufladd(-100, C) opened all six sites at TC -600 on v0.2.8
        @test_throws ErrorException ufladd(-100, ex88C)
        # a scalar k and a row vector k are the same k
        @test ufladd(8, ex88C)[1:2] == ufladd(fill(8, 6), ex88C)[1:2]
        @test ufladd([8 8 10 8 9 8], ex88C)[1:2] == ufladd(ex88k, ex88C)[1:2]
    end

    @testset "CR 6: ufladd and ufldrop return their sites sorted" begin
        y, _, W = ufladd(ex88k, ex88C; y = [6, 4])           # a warm start in descending order
        @test issorted(y)
        @test y == sort(y) && all(sum(W, dims = 1) .== 1)
        y, _, _ = ufldrop(ex88k, ex88C; y = [6, 4, 2, 1])
        @test issorted(y)
        # a tie in the allocation goes to the lower site, as with Matlog's sorted y
        Ct = [1.0 2.0; 1.0 2.0; 5.0 5.0]
        _, _, Wt = ufladd(0, Ct; p = 2)
        @test Matrix(Wt)[1, :] == [1.0, 1.0] && Matrix(Wt)[2, :] == [0.0, 0.0]
    end

    @testset "CR 5: the caller's y is never changed" begin
        y0 = [1]
        ufladd(ex88k, ex88C; y = y0)
        @test y0 == [1]
        y1 = [6, 1, 4, 2]
        ufldrop(ex88k, ex88C; y = y1)
        @test y1 == [6, 1, 4, 2]
        ya, _, _ = ufladd(ex88k, ex88C; y = y1)
        @test ya !== y1
        # ufl hands ADD's result to DROP: DROP starts from the set it was given
        yu, TCu, _ = ufl(ex88k, ex88C; verbose = false)
        @test (yu, TCu) == ([3, 6], 31.0)
    end
end

@testset "[N32] uflxchg returns a 1-swap local optimum (K2a's y0 = [1, 3] instance; MATLAB's [1, 5] at 113)" begin
    # n = 5 sites, m = 4 EFs: instance 6 of test/oracles/ufl_random.csv (tools/v0_3_0/make_oracles.m,
    # rng(20261119)); Matlog's uflxchg from y0 = [1, 3] reaches [1, 5] at TC 113. v0.2.8 swapped and
    # reverted inside `for i′ in y`, so deleteat!/push! reordered the vector under the loop, candidate
    # swaps were skipped, and it stopped at TC 122 with a better swap still open.
    k = [34, 111, 62, 86, 51]
    C = [ 2  21  15   5
         27  36  11  38
         38  11   8  17
         34   8  12   1
         19   6  34  16]
    cost(s) = sum(k[s]) + sum(minimum(C[s, :], dims = 1))
    y, TC, W = uflxchg(k, C, [1, 3])
    @test TC == cost(y)
    @test !any(cost(replace(y, i => j)) < TC for i in y for j in setdiff(1:5, y))   # no single swap lowers TC
    @test (y, TC) == ([1, 5], 113.0)
end

@testset "UFL family, K3: uflxchg and ufl" begin
    ex88k = [8, 8, 10, 8, 9, 8]
    ex88C = [ 0  3  7 10  6  4
              3  0  4  7  6  7
              7  4  0  3  6  8
             10  7  3  0  7  8
              6  6  6  7  0  2
              4  7  8  8  2  0]
    cost(k, C, y) = sum(k[y]) + sum(minimum(C[y, :], dims = 1))
    # a naive best-swap descent over a copy of y, re-slicing C for every candidate (the reference for N23/N32)
    function ref_xchg(k, C, y)
        y = copy(y)
        TCo = cost(k, C, y)
        while length(y) > 1
            TC, a, j = Inf, 0, 0
            for a2 in eachindex(y), j2 in setdiff(1:size(C, 1), y)
                y2 = copy(y); y2[a2] = j2
                TC2 = cost(k, C, y2)
                TC2 < TC && ((TC, a, j) = (TC2, a2, j2))
            end
            TC < TCo ? (TCo = TC; y[a] = j) : break
        end
        return sort(y), float(TCo)
    end

    @testset "N23, N32: uflxchg equals the naive best-swap descent" begin
        rng = Random.Xoshiro(32)
        same, localopt = true, true
        for _ in 1:80
            n, m = rand(rng, 3:9), rand(rng, 3:12)
            C = float.(rand(rng, 1:40, n, m))
            k = float.(rand(rng, 5:120, n))
            y0 = randperm(rng, n)[1:rand(rng, 2:n-1)]          # unsorted starts
            y, TC, _ = uflxchg(k, C, y0)
            same &= (y, TC) == ref_xchg(k, C, y0)
            localopt &= !any(cost(k, C, replace(y, i => j)) < TC for i in y for j in setdiff(1:n, y))
        end
        @test same
        @test localopt
    end

    @testset "N24: a single open site is returned as given (Matlog's rule)" begin
        y, TC, _ = uflxchg(ex88k, ex88C, [1])
        @test y == [1] && TC == cost(ex88k, ex88C, [1])
        @test cost(ex88k, ex88C, [5]) < TC             # a better single site exists, and is not found
    end

    @testset "CR 6, CR 5, N13: sorted sites, the caller's y kept, inputs checked" begin
        y0 = [6, 1, 3]
        y, _, _ = uflxchg(ex88k, ex88C, y0)
        @test issorted(y) && y0 == [6, 1, 3]
        @test_throws ErrorException uflxchg(ex88k, ex88C, [0, 2])
        @test_throws ErrorException uflxchg(ex88k, ex88C, [2, 7])
        @test_throws ErrorException uflxchg(ex88k, ex88C, [2, 2])
        @test_throws ErrorException uflxchg(ex88k[1:3], ex88C, [1, 2])
        @test_throws ErrorException uflxchg(-ex88k, ex88C, [1, 2])
        @test_throws ErrorException ufl(ex88k[1:3], ex88C; verbose = false)
        @test_throws ErrorException ufl(-ex88k, ex88C; verbose = false)
        @test issorted(ufl(ex88k, ex88C; verbose = false)[1])
    end
end

@testset "UFL family, K3: pmedian" begin
    ex88C = [ 0  3  7 10  6  4
              3  0  4  7  6  7
              7  4  0  3  6  8
             10  7  3  0  7  8
              6  6  6  7  0  2
              4  7  8  8  2  0]
    capture(f) = mktemp() do path, io
        r = redirect_stdout(f, io)
        flush(io)
        close(io)
        (r, read(path, String))
    end
    # a 5×6 integer instance (Random.Xoshiro(2026), found by search) where ADD and DROP end at different optima
    Cb = [ 4 15 14 20 11 11
          26 12 20  1  6 27
          16  2  1 22 30 27
          30 18 15 28 21  7
           6 29 11  2 10 13]

    @testset "D-2: construct = :both keeps the better of ADD → EXCHANGE and DROP → EXCHANGE" begin
        (ya, TCa, Wa), outa = capture(() -> pmedian(3, Cb))
        (yb, TCb, Wb), outb = capture(() -> pmedian(3, Cb; construct = :both))
        @test (ya, TCa) == ([3, 4, 5], 28.0)               # the default constructs from ADD alone
        @test (yb, TCb) == ([1, 2, 3], 25.0)               # DROP's optimum is cheaper and is kept
        @test sum(Wb .* Cb) == TCb                         # W is the allocation of the sites returned
        @test findall(>(0), vec(sum(Wb, dims = 2))) ⊆ yb
        @test outa == "  Add: 28.0\n Xchg: 28.0\n"
        @test outb == "  Add: 28.0\n Xchg: 28.0\n Drop: 25.0\n Xchg: 25.0\n"
        # :both can only help, and returns exactly the cheaper of the two on random instances
        rng = Random.Xoshiro(2)
        ok = true
        for _ in 1:40
            n, m = rand(rng, 4:8), rand(rng, 4:9)
            C = float.(rand(rng, 1:30, n, m))
            p = rand(rng, 1:n)
            ya, TCa, _ = pmedian(p, C; verbose = false)
            yb, TCb, Wb = pmedian(p, C; verbose = false, construct = :both)
            yd, TCd, _ = uflxchg(0, C, ufldrop(0, C; p = p)[1])
            ok &= TCb == min(TCa, TCd) && length(yb) == p && issorted(yb) && TCb <= TCa
            ok &= isapprox(TCb, sum(Wb .* C); rtol = 1e-9)
        end
        @test ok
        @test_throws ErrorException pmedian(2, ex88C; construct = :drop)
    end

    @testset "CR 6, N13: sorted sites; p between 1 and n" begin
        y, _, _ = pmedian(2, ex88C; verbose = false)
        @test y == [3, 6]                                  # was [6, 3] at v0.2.8
        @test_throws ErrorException pmedian(0, ex88C; verbose = false)
        @test_throws ErrorException pmedian(7, ex88C; verbose = false)
        @test pmedian(6, ex88C; verbose = false)[1] == collect(1:6)
        @test pmedian(1, ex88C; verbose = false)[1] == [2]
    end
end

# =============================================================================
# K3 (WP2), ala and randX: D4 (orphan repair, TC at the X returned), D3/S4 (the trace), S43 (a caller's
# own handles), S5 (the default stream; the rng keyword), N31 (dist = Inf).
# =============================================================================

@testset "ala, K3" begin
    P = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0]
    w = [1.0, 1.0, 1.0, 1.0]
    X0 = [0.2 0.2; 0.8 0.8; 100.0 100.0]               # NF 3 is nearest to no EF
    capture(f) = mktemp() do path, io
        r = redirect_stdout(f, io)
        flush(io)
        close(io)
        (r, read(path, String))
    end

    @testset "D4: an orphaned NF is moved to an EF and the EFs re-allocated; TC is the cost at the X returned" begin
        ok = true
        for seed in 1:20
            Random.seed!(seed)
            X, TC, W = ala(X0, w, P; dist = 2, verbose = false)
            ok &= all(vec(sum(W, dims = 2)) .> 0) && all(sum(W, dims = 1) .≈ 1.0)
            ok &= isapprox(TC, sum(W .* dists(X, P, 2)); rtol = 1e-9)
            ok &= all(X[3, :] .< 50)                    # NF 3 has left (100, 100)
        end
        @test ok
    end

    @testset "S5: the repair draws what v0.2.8's did, so a seeded run reproduces" begin
        # v0.2.8's default allocate, rewritten here: relocate orphans with sortperm(rand(m)) and loop
        function ref_alloc(X, w, P, dist)
            Xw = copy(X)
            local W, D
            while true
                D = dists(Xw, P, dist)
                assign = [argmin(@view D[:, j]) for j in 1:size(P, 1)]
                W = sparse(assign, 1:size(P, 1), Float64.(w), size(Xw, 1), size(P, 1))
                idx0 = findall(iszero, vec(sum(W, dims = 2)))
                isempty(idx0) && break
                perm = sortperm(rand(size(P, 1)))
                Xw[idx0, :] = P[perm[1:length(idx0)], :]
            end
            return W, sum(W .* D), Xw
        end
        same = true
        for seed in 1:20
            Random.seed!(seed)
            W1, TC1, X1 = Logjam._ala_alloc(X0, w, P, 2, nothing, true)
            Random.seed!(seed)
            W2, TC2, X2 = ref_alloc(X0, w, P, 2)
            same &= W1 == W2 && TC1 == TC2 && X1 == X2
            same &= rand() == (Random.seed!(seed); ref_alloc(X0, w, P, 2); rand())   # the same number of draws
        end
        @test same
    end

    @testset "S43: a caller's own alloc or locate is not second-guessed" begin
        stay = (W, X) -> X
        # a locate handle holds NF 3 where it is: the repair would move it, so it is skipped
        X, TC, W = ala(X0, w, P; dist = 2, locate = stay, verbose = false)
        @test X == X0 && sum(W[3, :]) == 0
        @test isapprox(TC, sum(W .* dists(X, P, 2)); rtol = 1e-9)
        # an alloc handle may leave an NF empty on purpose (a forced partition)
        Wf = sparse([1, 1, 2, 2], [1, 2, 3, 4], w, 3, 4)
        myalloc = X -> (Wf, sum(Wf .* dists(X, P, 2)))
        X, TC, W = ala(X0, w, P; dist = 2, alloc = myalloc, verbose = false)
        @test W == Wf && sum(W[3, :]) == 0
        @test X[3, :] == [100.0, 100.0]
    end

    @testset "S4, D3: every allocate and every locate step prints its cost, in ufl's format" begin
        X2 = [0.2 0.2; 0.8 0.8]
        (X, TC, W), out = capture(() -> ala(X2, w, P; dist = 2))          # verbose = true is the default
        lines = split(chomp(out), '\n')
        kinds = [strip(first(split(l, ':'))) for l in lines]
        @test all(occursin(r"^ *(Alloc|Locate): [0-9.e+-]+$", l) for l in lines)
        @test kinds[1:2:end] == fill("Alloc", length(kinds[1:2:end]))     # Alloc, then (Locate, Alloc) pairs
        @test kinds[2:2:end] == fill("Locate", length(kinds[2:2:end]))
        @test isodd(length(kinds)) && length(kinds) >= 3
        cost(l) = parse(Float64, strip(split(l, ':')[2]))
        W0 = sparse([argmin(dists(X2, P, 2)[:, j]) for j in 1:4], 1:4, w, 2, 4)
        @test isapprox(cost(lines[1]), sum(W0 .* dists(X2, P, 2)); atol = 1e-4)   # the first line is the cost at X0 (four decimals)
        @test all(cost(lines[i]) <= cost(lines[i - 1]) + 1e-4 for i in 2:2:length(lines))   # locating never costs more
        @test isapprox(minimum(cost.(lines[1:2:end])), TC; atol = 1e-4)    # the best allocate cost is the TC returned
        # the format of ufl: label right-aligned, a colon, the cost
        @test startswith(lines[1], " Alloc: ") && startswith(lines[2], "Locate: ")
        # nruns > 1 adds a line per run and the best
        Random.seed!(3)
        _, out3 = capture(() -> ala(X2, w, P; dist = 2, nruns = 3))
        @test count(occursin(r"^  [123]: TC = ", l) for l in split(out3, '\n')) == 3
        @test occursin(r"\n  Final: TC = [0-9.]+\n$", out3)
        # nruns = 1 prints no per-run line
        _, out1 = capture(() -> ala(X2, w, P; dist = 2))
        @test !occursin("TC =", out1)
        # verbose = false prints nothing
        _, out0 = capture(() -> ala(X2, w, P; dist = 2, nruns = 3, verbose = false))
        @test out0 == ""
        # a caller's alloc prints its Alloc lines and no Locate lines
        Wf = sparse([1, 1, 2, 2], [1, 2, 3, 4], w, 2, 4)
        myalloc = X -> (Wf, sum(Wf .* dists(X, P, 2)))
        _, outc = capture(() -> ala(X2, w, P; dist = 2, alloc = myalloc))
        @test !isempty(outc) && !occursin("Locate", outc) && occursin("Alloc", outc)
    end

    @testset "S5: the rng keyword (ala and randX); the default stream is the global one" begin
        Pr = [0.0 0.0; 2.0 0.0; 2.0 3.0]
        @test randX(Pr, 5; rng = Random.Xoshiro(3)) == randX(Pr, 5; rng = Random.Xoshiro(3))
        @test randX(Pr, 5; rng = Random.Xoshiro(3)) != randX(Pr, 5; rng = Random.Xoshiro(4))
        Xr = randX(Pr, 40; rng = Random.Xoshiro(1))
        @test all(0 .<= Xr[:, 1] .<= 2) && all(0 .<= Xr[:, 2] .<= 3) && size(Xr) == (40, 2)
        # no rng: exactly the global stream (rand(n, d)); rng = default_rng() is that stream
        Random.seed!(11); a = randX(Pr, 3)
        Random.seed!(11); b = randX(Pr, 3; rng = Random.default_rng())
        Random.seed!(11); c = [0.0 0.0] .+ rand(3, 2) .* [2.0 3.0]
        @test a == b == c
        # a passed generator leaves the global stream where it was
        Random.seed!(5); r1 = rand()
        Random.seed!(5); randX(Pr, 4; rng = Random.Xoshiro(1)); r2 = rand()
        @test r1 == r2
        # ala: the restarts and the repair draw from rng, whatever the global stream does
        X2 = [0.2 0.2; 0.8 0.8]
        Random.seed!(1); a1 = ala(X2, w, P; dist = 2, nruns = 6, verbose = false, rng = Random.Xoshiro(9))
        Random.seed!(2); a2 = ala(X2, w, P; dist = 2, nruns = 6, verbose = false, rng = Random.Xoshiro(9))
        @test a1[1] == a2[1] && a1[2] == a2[2]
        Random.seed!(5); r1 = rand()
        Random.seed!(5); ala(X0, w, P; dist = 2, nruns = 3, verbose = false, rng = Random.Xoshiro(9)); r2 = rand()
        @test r1 == r2
        # the default is the global stream, byte for byte
        Random.seed!(8); d1 = ala(X0, w, P; dist = 2, nruns = 4, verbose = false)
        Random.seed!(8); d2 = ala(X0, w, P; dist = 2, nruns = 4, verbose = false, rng = Random.default_rng())
        @test d1[1] == d2[1] && d1[2] == d2[2] && d1[3] == d2[3]
    end

    @testset "LOC8, LOC11: rng is typed Union{Nothing, AbstractRNG} on ala and randX" begin
        Pr = [0.0 0.0; 2.0 0.0; 2.0 3.0]
        # a value that is not a generator is refused at the call, naming the keyword; untyped, it failed later
        # (rng = 1 became a dimension of rand(1, 3, 2) and then a DimensionMismatch, rng = :seed a MethodError
        # inside Random), never naming rng
        @test_throws TypeError randX(Pr, 3; rng = 1)
        @test_throws TypeError randX(Pr, 3; rng = :seed)
        @test_throws TypeError ala([0.2 0.2; 0.8 0.8], w, P; dist = 2, nruns = 2, verbose = false, rng = 7)
        # nothing (the default) and any AbstractRNG are accepted, with the values of the untyped keyword
        Random.seed!(11); a = randX(Pr, 3; rng = nothing)
        Random.seed!(11); b = [0.0 0.0] .+ rand(3, 2) .* [2.0 3.0]
        @test a == b
        @test randX(Pr, 3; rng = Random.MersenneTwister(2)) == [0.0 0.0] .+ rand(Random.MersenneTwister(2), 3, 2) .* [2.0 3.0]
    end

    @testset "N31: ala accepts dist = Inf (Chebyshev)" begin
        X2 = [0.2 0.2; 0.8 0.8]
        X, TC, W = ala(X2, w, P; dist = Inf, verbose = false)
        @test isfinite(TC)
        @test isapprox(TC, sum(W .* dists(X, P, Inf)); rtol = 1e-9)
        # Chebyshev distance to the nearest of the four corners from the centre-ish points
        @test TC <= sum(w) * 1.0
        @test_throws ErrorException ala(X2, w, P; dist = :foo, verbose = false)
    end
end

# =============================================================================
# majority was removed before the release (IN2, his inclusion rule of 2026-11-21): Lecture 2.3 defines and uses
# it, no other lecture does, and the lecture keeps its own copy, which is its content (CR 1).
# =============================================================================

@testset "majority is not in Logjam (IN2)" begin
    @test !isdefined(Logjam, :majority)
end
