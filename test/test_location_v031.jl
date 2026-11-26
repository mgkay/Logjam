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
_dk_sameala(a, b) = a[1] == b[1] && a[2] == b[2] && a[3] == b[3]              # X, TC and W

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

@testset "WP3 (A8): lonlat2loc defaults to usplace(), and a view of a table is a table" begin
    # Lecture 3.4, Code block 18 (3-tran-4.qmd:1257-1271, 1282): its suppliers, DC and customers, and Code block 26's
    # places over 50,000 (1555)
    Scity, Sst = ["Rochester", "Orlando", "San Antonio"], [:NY, :FL, :TX]
    S = [loc2lonlat(c; state = st) for (c, st) in zip(Scity, Sst)]
    SXY = [getindex.(S, :LON) getindex.(S, :LAT)]
    Ccity, Cst = ["Portland", "Tucson", "Denver", "Milwaukee"], [:OR, :AZ, :CO, :WI]
    C = [loc2lonlat(c; state = st) for (c, st) in zip(Ccity, Cst)]
    CXY = [getindex.(C, :LON) getindex.(C, :LAT)]
    DC = loc2lonlat("Memphis"; state = :TN)
    DCXY = [DC.LON DC.LAT]
    XY = vcat(SXY, DCXY, CXY)
    up = usplace()
    @test lonlat2loc(XY) == lonlat2loc(XY, up)
    @test all(lonlat2loc(XY[i, :]) == lonlat2loc(XY[i, :], up) for i in axes(XY, 1))
    big = filter(r -> r.POP > 50_000, usplace())
    @test lonlat2loc(XY[4, :]; threshold = 1.0) == lonlat2loc(XY[4, :], up; threshold = 1.0)
    # the table is positional, as 3.4 passes `big`; there is no `df` keyword (ruling WP3-3)
    @test_throws MethodError lonlat2loc(XY; df = big)
    @test length(methods(lonlat2loc)) == 4
    # a view where a DataFrame was required: the same answer as the DataFrame it shows
    mask = up.POP .> 50_000
    @test lonlat2loc(XY, view(up, mask, :)) == lonlat2loc(XY, up[mask, :])
    @test lonlat2loc(XY[1, :], view(up, mask, :)) == lonlat2loc(XY[1, :], up[mask, :])
    t = DataFrame(CITY = ["Raleigh", "Durham", "Chapel Hill", "Cary"], STATE = [:NC, :NC, :NC, :NC])
    @test loc2lonlat(view(t, 2:3, :)) == loc2lonlat(t[2:3, :])
    @test loc2lonlat(view(t, :, :)) == loc2lonlat(t)
    @test prt(view(t, 2:3, :); str = true) == prt(t[2:3, :]; str = true)
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
