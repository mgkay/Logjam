# test_loctools.jl -- the tests of src/loctools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_loctools.jl, its lines 1-918 ====
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

# ==== moved from test/test_properties.jl, its lines 1-16, 27-122, 282-283 ====
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

@testset "loctools: properties" begin

# ---------------------------------------------------------------------------------------------
@testset "UFL family: returned cost = cost recomputed from the returned solution" begin
    rng = Random.Xoshiro(20261119)
    allok = Dict(f => true for f in (:add, :drop, :xchg, :ufl, :pmedian))
    sorted = Dict(f => true for f in (:add, :drop, :xchg, :ufl, :pmedian))
    addmut = xchgmut = dropmut = locopt = true
    for _ in 1:25
        n, m = rand(rng, 4:7), rand(rng, 4:8)
        C = float.(rand(rng, 1:40, n, m))
        k = float.(rand(rng, 20:120, n))

        ya, TCa, Wa = ufladd(k, C)
        allok[:add] &= _close(TCa, _ufl_cost(k, C, ya)) && _close(TCa, sum(k[ya]) + sum(Wa .* C))
        sorted[:add] &= issorted(ya)

        yd, TCd, Wd = ufldrop(k, C)
        allok[:drop] &= _close(TCd, _ufl_cost(k, C, yd)) && _close(TCd, sum(k[yd]) + sum(Wd .* C))
        sorted[:drop] &= issorted(yd)

        y0 = sort(randperm(rng, n)[1:rand(rng, 2:n)])
        ycopy = copy(y0)
        yx, TCx, Wx = uflxchg(k, C, y0)
        allok[:xchg] &= _close(TCx, _ufl_cost(k, C, yx)) && _close(TCx, sum(k[yx]) + sum(Wx .* C))
        sorted[:xchg] &= issorted(yx)
        xchgmut &= (y0 == ycopy)
        # local optimality (N24's documented exception: no swap is tried with one open site)
        if length(yx) > 1
            locopt &= !any(_ufl_cost(k, C, replace(yx, i => j)) < TCx - 1e-9
                           for i in yx for j in setdiff(1:n, yx))
        end
        # never worse than the start
        allok[:xchg] &= TCx <= _ufl_cost(k, C, y0) + 1e-9

        # ADD from a caller's set; the set must come back untouched
        ys = [rand(rng, 1:n)]
        yscopy = copy(ys)
        ufladd(k, C; y = ys)
        addmut &= (ys == yscopy)
        # DROP from a caller's set
        yd0 = collect(1:n); yd0copy = copy(yd0)
        ufldrop(k, C; y = yd0)
        dropmut &= (yd0 == yd0copy)

        yu, TCu, Wu = _mute_stdout(() -> ufl(k, C; verbose = false))
        allok[:ufl] &= _close(TCu, _ufl_cost(k, C, yu)) && _close(TCu, sum(k[yu]) + sum(Wu .* C))
        sorted[:ufl] &= issorted(yu)

        p = rand(rng, 1:n)
        yp, TCp, Wp = pmedian(p, C; verbose = false)
        allok[:pmedian] &= length(yp) == p && _close(TCp, sum(minimum(C[yp, :], dims = 1))) &&
                           _close(TCp, sum(Wp .* C))
        sorted[:pmedian] &= issorted(yp)
    end
    @test allok[:add]
    @test allok[:drop]
    @test allok[:xchg]
    @test allok[:ufl]
    @test allok[:pmedian]
    @test sorted[:drop]                       # ufldrop's setdiff happens to sort
    @test dropmut
    @test xchgmut
    # index sets returned sorted: CR 6 (decided 2026-08-29), fixed in K3 (pmedian sorts because uflxchg does)
    @test sorted[:add]
    @test sorted[:xchg]
    @test sorted[:ufl]
    @test sorted[:pmedian]
    # ufladd mutated the caller's y: CR 5, fixed in K3
    @test addmut
    # FINDING F1 = N32 (found by this test): v0.2.8's uflxchg moved elements of y to the end (swap!/revert!)
    # while `for i′ in y` was iterating over y, so candidate swaps were skipped and the returned set was
    # not a 1-swap local optimum, which its docstring promises. Fixed in K3 (scan the set as it stands).
    @test locopt
end

# ---------------------------------------------------------------------------------------------
@testset "ala: returned cost = cost of the returned X; start not mutated" begin
    rng = Random.Xoshiro(754)
    ok = true
    nomut = true
    for _ in 1:12
        m = rand(rng, 6:14)
        P = rand(rng, m, 2) .* 40
        w = rand(rng, m) .* 20 .+ 1
        n = rand(rng, 2:3)
        X0 = randX(P, n)
        X0copy = copy(X0)
        X, TC, W = _mute_stdout(() -> ala(X0, w, P; dist = 2))
        D = dists(X, P, 2)
        ok &= _close(TC, sum(W .* D))
        nomut &= (X0 == X0copy)
    end
    @test ok                                   # TC is computed at the X returned (true on main since PR #13)
    @test nomut
end

end  # properties

# ==== moved from test/test_oracles.jl, its lines 1-31, 38-134, 748-749 ====
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

@testset "loctools: oracles" begin

# =============================================================================================
@testset "oracle: UFL family, Example 8.8 (Matlog help text)" begin
    d = _readoracle("ufl_ex88")
    k, C = _fvec(d, "k"), d["C"]
    cmp(pre, y, TC, W) = (set = sort(y) == _ivec(d, pre * "_y"),
                          order = y == _ivec(d, pre * "_y"),
                          TC = _oclose(TC, _sc(d, pre * "_TC")),
                          X = (Matrix(W) .> 0) == (d[pre * "_X"] .> 0))
    r = cmp("ufl", _oquiet(() -> ufl(k, C; verbose = false))...)
    @test r.set; @test r.TC; @test r.X; @test r.order
    r = cmp("ufladd", ufladd(k, C)...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("ufladd45", ufladd(k, C; y = [4, 5])...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("ufldrop", ufldrop(k, C)...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("ufldrop36", ufldrop(k, C; y = collect(3:6))...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("uflxchg", uflxchg(k, C, _ivec(d, "xchg_y0"))...)
    @test r.set; @test r.TC; @test r.X
    r = cmp("pmedian2", pmedian(2, C; verbose = false)...)
    @test r.set; @test r.TC; @test r.X
end

# =============================================================================================
@testset "oracle: UFL family, 12 seeded random instances (rng(20261119) in MATLAB, inputs saved)" begin
    d = _readoracle("ufl_random")
    ninst = Int(_sc(d, "ninst"))
    fns = (:ufl, :ufladd, :ufldrop, :uflxchg, :pmedian)
    # per function and per quantity, did every instance agree?
    res = Dict((f, q) => Bool[] for f in fns for q in (:set, :order, :TC, :X))
    bad = Dict((f, q) => Int[] for f in fns for q in (:set, :order, :TC, :X))
    for i in 1:ninst
        k, C, y0 = _fvec(d, "k_$i"), d["C_$i"], _ivec(d, "y0_$i")
        p = Int(_sc(d, "p_$i"))
        out = Dict(:ufl => _oquiet(() -> ufl(k, C; verbose = false)),
                   :ufladd => ufladd(k, C), :ufldrop => ufldrop(k, C),
                   :uflxchg => uflxchg(k, C, copy(y0)), :pmedian => pmedian(p, C; verbose = false))
        for f in fns
            y, TC, W = out[f]
            pre = "$(f)_$i"
            vals = (set = sort(y) == _ivec(d, pre * "_y"), order = y == _ivec(d, pre * "_y"),
                    TC = _oclose(TC, _sc(d, pre * "_TC")),
                    X = (Matrix(W) .> 0) == (d[pre * "_X"] .> 0))
            for q in (:set, :order, :TC, :X)
                push!(res[(f, q)], vals[q])
                vals[q] || push!(bad[(f, q)], i)
            end
        end
    end
    ok(f, q) = all(res[(f, q)])
    @test ok(:ufl, :set) && ok(:ufl, :TC) && ok(:ufl, :X)
    @test ok(:ufladd, :set) && ok(:ufladd, :TC) && ok(:ufladd, :X)
    @test ok(:ufldrop, :set) && ok(:ufldrop, :TC) && ok(:ufldrop, :X) && ok(:ufldrop, :order)
    @test ok(:pmedian, :set) && ok(:pmedian, :TC)
    # The sites come back in MATLAB's sorted order only by luck: ufl, ufladd, uflxchg and pmedian return
    # them in the order they were added or swapped in (instances 3 and 9 for ufl, 2 and 8 for ufladd,
    # 3, 4, 6, 7, 10, 11 for uflxchg, 4-11 for pmedian). CR 6 (decided 2026-08-29: sort), K3.
    @test ok(:ufl, :order)                     # flipped in K3 (CR 6)
    @test ok(:ufladd, :order)                  # flipped in K3 (ufladd commit)
    @test ok(:uflxchg, :order)
    @test ok(:pmedian, :order)
    # pmedian's allocation matrix differs in instance 7 only, where two open sites tie for an EF and the
    # unsorted site vector breaks the tie differently from MATLAB's sorted one: the same cause, CR 6, K3
    @test all(res[(:pmedian, :X)][i] for i in 1:ninst if i != 7)
    @test res[(:pmedian, :X)][7]               # flipped in K3 (CR 6): sorted sites break the tie as MATLAB does
    # uflxchg agrees with MATLAB on 11 of 12 instances. Instance 6 (start y0 = [1, 3]) ends at
    # TC 122 where MATLAB reaches 113: uflxchg swaps and reverts inside `for i′ in y`, so `deleteat!` and
    # `push!` reorder the vector being iterated and candidate swaps are skipped (K2a finding F1, now N32).
    # A copy-scanning uflxchg reproduces MATLAB's set and cost on all 12 instances (checked in K2b).
    # N32, flipped in K3: all twelve instances agree with MATLAB.
    for q in (:set, :TC, :X)
        @test all(res[(:uflxchg, q)][i] for i in 1:ninst if i != 6)
        @test res[(:uflxchg, q)][6]
    end
end

# =============================================================================================
@testset "oracle: ala, help Example 1 (three NFs for the NC cities, start saved)" begin
    d = _readoracle("ala_nc")
    P, w, X0 = d["P"], _fvec(d, "w"), d["X0"]
    # p = 2 (Euclidean): the same metric, so a cost oracle at 1e-9. The locate step is a different solver
    # (Optim here, Matlog's minisumloc there), so the NF coordinates agree only to about 1e-6 and are not
    # compared; the allocation (an index result) and the cost are.
    X, TC, W = _oquiet(() -> ala(X0, w, P; dist = 2, verbose = false))
    @test (Matrix(W) .> 0) == (d["e2_W"] .> 0)
    @test _oclose(TC, _sc(d, "e2_TC"))
    # p = 'mi': DEPARTURE (D7). Logjam's constant radius 3958.75 mi against Matlog's latitude-dependent
    # 3963.34 - 13.35|sin(lat)| gives a cost that differs by up to the 0.08% of N15; the allocation is the
    # same and the cost is asserted within GC_RADIUS_RTOL (relative 1e-3), not at 1e-9.
    X, TC, W = _oquiet(() -> ala(X0, w, P; dist = :mi, verbose = false))
    @test (Matrix(W) .> 0) == (d["mi_W"] .> 0)
    @test _oclose(TC, _sc(d, "mi_TC"); rtol = GC_RADIUS_RTOL)
    @test !_oclose(TC, _sc(d, "mi_TC"))        # and it is a difference, not agreement (D7)
end

end # oracles

# ==== moved from test/test_location_v031.jl, its lines 1-28, 133-133, 210-463 ====
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
_dk_sameala(a, b) = a[1] == b[1] && a[2] == b[2] && a[3] == b[3]              # X, TC and W

@testset "WP3 (A5): ala resolves its metric as dists does" begin
    P = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0; 0.4 0.7]
    w = [1.0, 2.0, 1.0, 3.0, 2.0]
    X0 = [0.2 0.2; 0.8 0.8]
    for p in (3, 1.5, 3.0)                        # an error at v0.3.0 ("`dist` must be ... 1, 2, or Inf")
        X, TC, W = ala(X0, w, P; dist = p, verbose = false)
        @test TC == sum(W .* dists(X, P, p))      # the cost at the X returned, in the metric asked for
        # the locate step is the minisum of `dists`' own lₚ distance, one pair at a time
        Wl = sparse([1, 1, 2, 2, 2], 1:5, w, 2, 5)
        ref = copy(X0)
        for i in 1:2
            J = findall(!iszero, Wl[i, :])
            fl(x) = sum(Wl[i, J[t]] * dists(reshape(x, 1, :), P[J[t]:J[t], :], p)[1] for t in eachindex(J))
            ref[i, :] = optimize(fl, X0[i, :]).minimizer
        end
        @test Logjam._ala_locate(Wl, X0, Logjam._alakernel(p), P) == ref
    end
    # integer p is the real p, as in dists (N19)
    @test _dk_sameala(ala(X0, w, P; dist = 3, verbose = false), ala(X0, w, P; dist = 3.0, verbose = false))
    # `unit` is `dist`'s synonym for a great-circle unit; both, or a unit that is not one, is an error
    Pnc = [-78.64 35.78; -80.84 35.23; -79.79 36.07; -77.94 34.23]
    wnc = [469.0, 897.0, 299.0, 123.0]
    X0nc = [-78.6 35.8; -80.0 35.5]
    @test _dk_sameala(ala(X0nc, wnc, Pnc; unit = :km, verbose = false), ala(X0nc, wnc, Pnc; dist = :km, verbose = false))
    @test _dk_sameala(ala(X0nc, wnc, Pnc; verbose = false), ala(X0nc, wnc, Pnc; dist = :mi, verbose = false))
    @test_throws ArgumentError ala(X0nc, wnc, Pnc; dist = :mi, unit = :km, verbose = false)
    @test_throws ArgumentError ala(X0nc, wnc, Pnc; unit = 2, verbose = false)
    @test_throws ErrorException ala(X0, w, P; dist = 0.5, verbose = false)
    @test_throws ErrorException ala(X0, w, P; dist = :ft, verbose = false)
    # a caller's own allocate and locate never read the metric (as at v0.3.0)
    Wf = sparse([1, 1, 2, 2, 2], 1:5, w, 2, 5)
    @test ala(X0, w, P; dist = "unused", alloc = X -> (Wf, 1.0), locate = (W, X) -> X, verbose = false)[1] == X0
end

@testset "WP3 (A7): ala(X0, alloc, P), ala(n, w, P), ala(x, w, P) equal the calls the course writes" begin
    # 2.3's allocation (2-loc-3.qmd:180-185)
    function allocate(D, w)
        n, m = size(D)
        α = [argmin(c) for c in eachcol(D)]
        W = sparse(α, 1:m, w, n, m)
        return α, sum(W .* D)
    end
    # Lecture 2.3, Code blocks 13, 14 and 16 (2-loc-3.qmd:1460-1464, 1473-1474, 1505-1514)
    df = filter(r -> r.STFIP in st2fips.([:NC, :SC]) && r.POP > 10_000, usplace())
    select!(df, :NAME, :ST, :LAT, :LON, :POP)
    P = hcat(df.LON, df.LAT)
    w = float(df.POP)
    nef = size(P, 1)
    function alloc36(X)
        D = dists(X, P, :mi)
        α, = allocate(D, w)
        α[1:3] .= 1
        α[4:6] .= 2
        Wc = sparse(α, 1:nef, w, size(X, 1), nef)
        return Wc, sum(Wc .* D)
    end
    Random.seed!(8345); c_kw = ala(randX(P, 2), w, P; alloc = alloc36, nruns = 5, verbose = false)
    Random.seed!(8345); c_pos = ala(randX(P, 2), alloc36, P; nruns = 5, verbose = false)
    Random.seed!(8345); c_n = ala(2, alloc36, P; nruns = 5, verbose = false)
    @test _dk_sameala(c_pos, c_kw)                      # (i): the allocate function in w's place
    @test _dk_sameala(c_n, c_kw)                        # (i) with (ii)
    Random.seed!(8345); o_idiom = ala(randX(P, 2), w, P; nruns = 5, verbose = false)
    Random.seed!(8345); o_n = ala(2, w, P; nruns = 5, verbose = false)
    @test _dk_sameala(o_n, o_idiom)                     # (ii): the random start, the global stream
    @test _dk_sameala(ala(2, w, P; nruns = 5, rng = Xoshiro(8345), verbose = false),
                  (r = Xoshiro(8345); ala(randX(P, 2; rng = r), w, P; nruns = 5, rng = r, verbose = false)))
    @test _dk_sameala(ala(Int32(2), w, P; rng = Xoshiro(1), verbose = false), ala(2, w, P; rng = Xoshiro(1), verbose = false))
    # the trace is the idiom's too
    out(f) = mktemp() do path, io
        redirect_stdout(f, io); flush(io); close(io); read(path, String)
    end
    @test out(() -> (Random.seed!(8345); ala(2, w, P; nruns = 2))) == out(() -> (Random.seed!(8345); ala(randX(P, 2), w, P; nruns = 2)))
    @test out(() -> ala(randX(P, 2; rng = Xoshiro(3)), alloc36, P)) == out(() -> ala(randX(P, 2; rng = Xoshiro(3)), w, P; alloc = alloc36))

    # Lecture 3.4, Code blocks 20, 29 and 30 (3-tran-4.qmd:1300, 1617-1630, 1636-1655): the first three of its
    # twenty runs, with the allocate function in w's place and with the count as the start (P3 is CXY3 twice, so
    # randX(P3, n) draws in CXY3's box exactly as the lecture's randX(CXY3, n))
    ppiTL = 131.0
    z3 = filter(r -> r.ISCUS && r.POP > 100_000, uszcta3())
    CXY3 = Matrix(z3[:, [:LON, :LAT]])
    SXY3 = CXY3
    COGS = 44.04e9
    v3 = 7000
    f3 = COGS/v3
    s3 = 10
    tr3 = (r = 2ppiTL/102.7, Kwt = 25, Kcu = 2750, ppi = ppiTL)
    qmax3 = maxpayld(s3; Kwt = tr3.Kwt, Kcu = tr3.Kcu)
    fC3 = f3*(z3.POP/sum(z3.POP))
    fS3 = fill(f3/size(SXY3, 1), size(SXY3, 1))
    DCh(XY) = dists(XY, CXY3, :mi)*1.2
    function FC(XY)
        i = [argmin(c) for c in eachcol(DCh(XY))]
        return sparse(i, 1:length(fC3), fC3, size(XY, 1), length(fC3))
    end
    FS(XY) = (vec(sum(FC(XY), dims = 2))/sum(fC3)) * fS3'
    W3(XY) = [FS(XY) FC(XY)]*(tr3.r/qmax3)
    TCh(XY) = sum(W3(XY) .* [dists(SXY3, XY, :mi)'*1.2 DCh(XY)])
    alloc_h(XY) = (W3(XY), TCh(XY))
    P3 = [SXY3; CXY3]
    Random.seed!(9348567)
    lect = [ala(randX(CXY3, n), ones(size(P3, 1)), P3; alloc = alloc_h, nruns = 5, verbose = false) for n in 1:3]
    Random.seed!(9348567)
    pos = [ala(randX(CXY3, n), alloc_h, P3; nruns = 5, verbose = false) for n in 1:3]
    Random.seed!(9348567)
    cnt = [ala(n, alloc_h, P3; nruns = 5, verbose = false) for n in 1:3]
    @test all(_dk_sameala(pos[n], lect[n]) for n in 1:3)
    @test all(_dk_sameala(cnt[n], lect[n]) for n in 1:3)

    # Lecture 2.4, Code blocks 21 and 24 (2-loc-4.qmd:1176-1180, 1215-1216): the random multi-start
    zr = filter!(r -> r.ISCUS == true && r.POP > 0, uszcta3())
    select!(zr, :ZCTA3, :LAT, :LON, :POP)
    Pr = hcat(zr.LON, zr.LAT)
    wr = zr.POP
    Random.seed!(4161); Xa_idiom = ala(randX(Pr, 9), float(wr), Pr; nruns = 3, verbose = false)
    Random.seed!(4161); Xa_n = ala(9, float(wr), Pr; nruns = 3, verbose = false)
    @test _dk_sameala(Xa_n, Xa_idiom)
    # ... and an allocate function on the same centroids: 2.3's nearest allocation, held to a run of nine
    function near(X)
        α, TC = allocate(dists(X, Pr, :mi), float(wr))
        return sparse(α, 1:size(Pr, 1), float(wr), size(X, 1), size(Pr, 1)), TC
    end
    X0r = randX(Pr, 9; rng = Xoshiro(4161))
    @test _dk_sameala(ala(X0r, near, Pr; verbose = false), ala(X0r, float(wr), Pr; alloc = near, verbose = false))

    # the HW 1 key, Q6 (hw1-solution.jl:195-207, 212-222, 242, 251-252): one NF from Roanoke Rapids, and forty
    # random starts of two
    function name2lonlat(namein, df)
        nm = split(namein, ", ")
        idx = length(nm) == 1 ? findfirst(r -> r.NAME == nm[1], eachrow(df)) :
              findfirst(r -> r.NAME == nm[1] &&
                            r.ST == Symbol(nm[2]), eachrow(df))
        idx === nothing && error("'$namein' not found")
        collect(df[idx, [:LON, :LAT]])
    end
    xyChar = name2lonlat("Charlottesville, VA", usplace())
    xyRR   = name2lonlat("Roanoke Rapids, NC", usplace())
    stores = filter(r -> any(i -> r.STFIP == i, st2fips.([:NC, :SC, :VA])) &&
                         r.POP > 10_000 && r.LAT <= xyChar[2], usplace())
    Ph = hcat(stores.LON, stores.LAT)
    TD0, TC0 = sum(stores.POP .* [dgc(xyRR, p) for p in eachrow(Ph)]), 6.7e6
    rate = TC0 / TD0
    wh = rate .* stores.POP
    @test _dk_sameala(ala(xyRR, wh, Ph; verbose = false), ala(reshape(xyRR, 1, 2), wh, Ph; verbose = false))   # (iii)
    Random.seed!(754); runs_idiom = [ala(randX(Ph, 2), wh, Ph; verbose = false) for _ in 1:40]
    Random.seed!(754); runs_n = [ala(2, wh, Ph; verbose = false) for _ in 1:40]
    @test all(_dk_sameala(runs_n[i], runs_idiom[i]) for i in 1:40)

    # Lecture 2.2, Example 3 (2-loc-2.qmd:1271-1275) and Example 4 (1413-1415, 1548-1549, 1561): one NF from the
    # weighted centroid
    nc = filter(r -> r.STFIP == st2fips(:NC), usplace())
    c = wcentroid(nc.LON, nc.LAT, nc.POP)
    Pn = hcat(nc.LON, nc.LAT)
    @test _dk_sameala(ala([c.LON, c.LAT], nc.POP, Pn; verbose = false), ala(reshape([c.LON, c.LAT], 1, :), nc.POP, Pn; verbose = false))
    Detroit     = [-83.1022, 42.3830]
    Gainesville = [-82.3492, 29.6807]
    Memphis     = [-89.9666, 35.1090]
    P22 = permutedims(hcat(Detroit, Gainesville, Memphis))
    wTL = [40.0, 25.0, 35.0]
    c0 = wcentroid(P22[:, 1], P22[:, 2], wTL)
    @test _dk_sameala(ala([c0.LON, c0.LAT], wTL, P22; verbose = false), ala(reshape([c0.LON, c0.LAT], 1, :), wTL, P22; verbose = false))
    @test _dk_sameala(ala([c0.LON, c0.LAT], X -> (sparse(ones(Int, 3), 1:3, wTL, 1, 3), 0.0), P22; verbose = false),
                  ala(reshape([c0.LON, c0.LAT], 1, :), wTL, P22; alloc = X -> (sparse(ones(Int, 3), 1:3, wTL, 1, 3), 0.0), verbose = false))

    # no ambiguity among ala's methods or the other functions given methods here, and every existing call keeps
    # the method it had (the general one: X0 a matrix, w not a function)
    touched = (:ala, :wcentroid, :uflxchg, :lonlat2loc, :loc2lonlat, :dgca, :dists, :dgc)
    @test isempty(filter(a -> a[1].name in touched || a[2].name in touched, Test.detect_ambiguities(Logjam)))
    general = which(ala, Tuple{Any,Any,Any})
    for T in (Tuple{Matrix{Float64},Vector{Float64},Matrix{Float64}}, Tuple{Matrix{Float64},Vector{Int},Matrix{Int}},
              Tuple{typeof([100 300]'),Vector{Int},typeof([50 150 190]')}, Tuple{SubArray{Float64,2},Vector{Float64},Matrix{Float64}})
        @test which(ala, T) === general
    end
    @test which(ala, Tuple{Matrix{Float64},typeof(alloc36),Matrix{Float64}}) !== general
    @test which(wcentroid, Tuple{Vector{Float64},Vector{Float64},Vector{Float64}}).nargs == 4
    # what was an error at v0.3.0 and is a call form now
    @test_throws ErrorException ala(2, w[1:1], P[1:1, :]; verbose = false)   # still: more NFs than EFs
    @test_throws TypeError ala(2, w, P; rng = 7, verbose = false)            # rng typed, as LOC8
    @test_throws TypeError ala([-79.0, 35.0], w, P; rng = 7, verbose = false)
end

@testset "WP3 (A8): wcentroid(P, w) and uflxchg on any integer vector" begin
    # wcentroid(P, w) is wcentroid(P[:, 1], P[:, 2], w): Lecture 2.2's and 2.6's three cities (2-loc-2.qmd:1548-1549,
    # 1561; 2-loc-6.qmd:338-339, 351), 2.2's North Carolina places (1271, 1275), 2.5's block groups (2-loc-5.qmd:602,
    # 605)
    P22 = permutedims(hcat([-83.1022, 42.3830], [-82.3492, 29.6807], [-89.9666, 35.1090]))
    wTL = [40.0, 25.0, 35.0]
    @test wcentroid(P22, wTL) == wcentroid(P22[:, 1], P22[:, 2], wTL)
    nc = filter(r -> r.STFIP == st2fips(:NC), usplace())
    Pn = hcat(nc.LON, nc.LAT)
    @test wcentroid(Pn, nc.POP) == wcentroid(Pn[:, 1], Pn[:, 2], nc.POP) == wcentroid(nc.LON, nc.LAT, nc.POP)
    bg = filter(r -> r.STFIP == st2fips(:NC), uscenblkgrp())
    Pb = hcat(bg.LON, bg.LAT)
    @test wcentroid(Pb, bg.POP) == wcentroid(bg.LON, bg.LAT, bg.POP)
    @test wcentroid(Pb, bg.POP) isa NamedTuple{(:LON, :LAT)}
    @test_throws ArgumentError wcentroid(Pb[:, 1:1], bg.POP)

    # uflxchg on a range and on Int32 indices is the Vector{Int} call. Lecture 2.4's corridor (2-loc-4.qmd:459-463,
    # 775, 788-789), with ADD's {1, 3} as a step range
    P = reshape([50, 150, 220, 295, 420], :, 1)
    k = [150, 200, 150, 150, 200]
    r, f = 1, 1
    w = r * f
    C = w * dists(P, P, 1)
    yadd, _, _ = ufladd(k, C)
    @test yadd == [1, 3]                       # ADD's {3, 1}, returned sorted
    ref = uflxchg(k, C, yadd)
    @test uflxchg(k, C, 1:2:3) == ref
    @test uflxchg(k, C, Int32[1, 3]) == ref
    @test uflxchg(k, C, 3:-2:1) == uflxchg(k, C, [3, 1])
    @test uflxchg(k, C, 1:2) == uflxchg(k, C, [1, 2])
    # 2.4's EMCA (2-loc-4.qmd:964-975, 985-989)
    zip = [270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283,
           284, 285, 286, 287, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299]
    ncust = [7, 5, 6, 3, 5, 8, 5, 1, 3, 2, 8, 4, 9, 6, 1, 2, 3, 3, 4, 3, 3, 2, 11, 5, 7, 2, 4, 2]
    ud, uwt = 12e6, 15 / 2000
    fz = ud .* ncust ./ sum(ncust) .* uwt
    z = uszcta3()
    idx = [findfirst(==(zi), z.ZCTA3) for zi in zip]
    Pz = hcat(z.LON[idx], z.LAT[idx])
    Cz = (fz .* 0.25)' .* (1.2 .* dists(Pz, Pz, :mi))
    kz = 100_000.0
    yz, _, _ = ufladd(kz, Cz)
    @test uflxchg(kz, Cz, Int32.(yz)) == uflxchg(kz, Cz, yz)
    @test uflxchg(kz, Cz, UInt16.(yz)) == uflxchg(kz, Cz, yz)
    @test uflxchg(kz, Cz, 1:4) == uflxchg(kz, Cz, [1, 2, 3, 4])
    @test uflxchg(kz, Cz, view([9, 2, 14, 5], 1:3)) == uflxchg(kz, Cz, [9, 2, 14])
    # 2.6's Kudde (2-loc-6.qmd:493-501, 510-511, 541-551): ADD's start at the first fixed cost the lecture fits
    ubox = 24
    uwt6 = 35 / ubox
    udem = 1 / 100
    rton = 2.5523
    g = 1.2
    zk = filter(r -> r.ISCUS && r.POP > 0, uszcta3())
    Pk = hcat(zk.LON, zk.LAT)
    fk = float.(zk.POP) .* (udem * uwt6 / 2000)
    D = g .* dgca(Pk, Pk, zk.ALAND)
    Ck = rton .* (fk' .* D)
    f0 = 1e6 * uwt6 / 2000
    TPC0 = 2e6
    β = 0.85
    TPC(x) = TPC0 .* (x ./ f0) .^ β
    function fitk(fmax, fmin)
        x = collect(range(fmin, fmax; length = 2000))
        y = TPC(x)
        p = optimize(p -> sum((y .- (p[1] .+ p[2] .* x)) .^ 2), [0.0, 1.0])
        return Optim.minimizer(p)[1]   # the intercept is the fixed cost
    end
    kk = fill(fitk(sum(fk), minimum(fk)), size(Ck, 1))
    yk, _, _ = ufladd(kk, Ck)
    @test uflxchg(kk, Ck, Int32.(yk)) == uflxchg(kk, Ck, yk)
    @test uflxchg(kk, Ck, 1:3) == uflxchg(kk, Ck, [1, 2, 3])
    @test which(uflxchg, Tuple{Vector{Float64},Matrix{Float64},Vector{Int}}) === which(uflxchg, Tuple{Any,Any,UnitRange{Int}})
end
