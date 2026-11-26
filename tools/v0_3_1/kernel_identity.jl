# kernel_identity.jl -- the bit-identity harness of the shared metric kernel (Logjam v0.3.1, PCV WP3, DK, review A5).
#
#   julia --project=<Logjam> tools/v0_3_1/kernel_identity.jl save    <file>   # before the kernel: the branch's start
#   julia --project=<Logjam> tools/v0_3_1/kernel_identity.jl compare <file>   # after it is wired in
#
# `save` runs every case below and writes its output to <file> (Serialization, one record per case, in order);
# `compare` runs the same cases on the code as it now is and compares each output with the saved one by `===`
# on every element (a sparse W by its size and its `findnz` triples, a table by its column names and columns,
# an error by its type and the first line of its message). It prints the number of cases and of elements
# compared, and every case that differs with its first differing element, and exits 1 if any does. A record
# saved by one Julia version is compared only on that version: the elementary functions and the optimizer may
# differ between versions, the kernel may not.
#
# What is run (MakePlan D2: "WP3's shared metric kernel must leave dists, ala and dgca bit-identical"):
#   - dists with every metric it accepts: nothing (the default), 1, 2, an integer p (3), the real p 1.0, 2.0, 1.5
#     and 3.0, Inf, and the great circle in :mi, :km and :rad (positionally and as `unit`); on the inputs of the
#     distance pins (test/dist_geo_pin_cases.jl), the Matlog oracles (test/oracles/dists.csv, dgc_nccity.csv), and
#     seeded random point sets up to 3000 points: lon-lat boxes, 1 to 20 dimensions, integer, Int32 and Float32
#     coordinates, adjoints, a single point (the vector form), no columns, a 1-column set against a 3-column one
#     (which the general metric broadcasts), and edge values (equal, antipodal and polar points, zeros, 1e300,
#     1e-300, NaN);
#   - dgc, which shares the great-circle arithmetic, on the pins' inputs and 20,000 seeded pairs;
#   - ala's locate step, through `ala` with a fixed start and a fixed allocation (a caller's `alloc` that never
#     changes W, so every step after the first is the default locate), for dist = 1, 2, Inf, :mi, :km, :rad and
#     the real 1.0 and 2.0 (which allocate by the general metric and locate by d1 and d2); and `ala` with its
#     default allocate on seeded starts; on 1-, 2- and 3-dimensional sets up to 3000 points, on the pins' and the
#     oracle's inputs, and on Lecture 2.3's I-40 corridor and Carolinas examples (Code blocks 12, 14 and 16);
#   - dgca on the pins' inputs and seeded sets up to 3000 points, each unit, zero areas, one row at a time;
#   - lonlat2loc on the pins' inputs (it calls dists).
# Afterwards it prints the time and allocation of dists at m = 3000 (3000 points against 3000) for 2, 1, 3.0,
# Inf and :mi: reported, not asserted.

using Logjam, Random, Serialization, SparseArrays, DataFrames, Printf

const MODE = length(ARGS) >= 1 ? ARGS[1] : ""
const FILE = length(ARGS) >= 2 ? ARGS[2] : ""
MODE in ("save", "compare") && !isempty(FILE) ||
    error("usage: kernel_identity.jl save|compare <file>")

const ORACLES = joinpath(@__DIR__, "..", "..", "test", "oracles")

# ---- inputs -------------------------------------------------------------------------------------------------
function readoracle(name)               # "@name,nrows,ncols" blocks, as test/oracle_helpers.jl reads them
    d = Dict{String,Matrix{Float64}}()
    lines = readlines(joinpath(ORACLES, name * ".csv"))
    i = 1
    while i <= length(lines)
        if startswith(lines[i], "@")
            nm, r, c = split(lines[i][2:end], ',')
            r, c = parse(Int, r), parse(Int, c)
            d[String(nm)] = permutedims(reduce(hcat, [parse.(Float64, split(lines[i + a], ',')) for a in 1:r]))
            i += r + 1
        else
            i += 1
        end
    end
    return d
end

lonlat(rng, m) = hcat(-125 .+ 58 .* rand(rng, m), 25 .+ 24 .* rand(rng, m))            # the lower 48's box
globe(rng, m) = hcat(-180 .+ 360 .* rand(rng, m), -90 .+ 180 .* rand(rng, m))
ncp() = (p = usplace(); nc = p[p.ST .== :NC, :]; nc = nc[sortperm(nc.POP; rev = true)[1:8], :]; (nc, [nc.LON nc.LAT]))
place(name, st) = (p = usplace(); r = p[(p.NAME .== name) .& (p.ST .== st), :]; [r.LON[1], r.LAT[1]])

const METRICS = Any[nothing, 1, 2, 3, 1.0, 2.0, 1.5, 3.0, Inf, :mi, :km, :rad]
const LP = Any[1, 2, 3, 1.0, 2.0, 1.5, 3.0, Inf]                      # the metrics that take any dimension
mname(p) = p === nothing ? "default" : repr(p)

# ---- the cases ----------------------------------------------------------------------------------------------
function cases()
    C = Tuple{String,Function}[]
    add(name, f) = push!(C, (name, f))

    # dists: the pins' inputs (test/dist_geo_pin_cases.jl)
    add("pin dists_p_1_2_inf", () -> [dists([0 0], [4 3], p) for p in (1, 2, Inf)])
    add("pin dists_default_p2", () -> dists([0.0 0.0; 10.0 0.0], [5.0 0.0; 5.0 5.0]))
    add("pin dists_p3_real", () -> dists([0.0 0.0; 1.0 2.0], [3.0 1.0; 2.0 2.0], 3.0))
    add("pin dists_p_inf", () -> dists([0.0 0.0; 1.0 2.0], [3.0 1.0; 2.0 2.0], Inf))
    add("pin dists_p_half_err", () -> dists([0.0 0.0], [1.0 1.0], 0.5))
    add("pin dists_int_matrix_p1", () -> (P = [1 2; 3 5; 8 1]; dists(P, P, 1)))
    add("pin dists_column_matrices", () -> dists(reshape([2.0, 5.0], :, 1), reshape([1.0, 3.0, 8.0], :, 1), 1))
    add("pin dists_adjoint_point", () -> dists([-79.0, 35.5]', [-80.0 35.0; -82.0 36.0], :mi)[:])
    add("pin dists_mi_km_rad", () -> (P = ncp()[2]; (dists(P, P, :mi), dists(P, P, :km), dists(P, P, :rad))))
    add("pin dists_rad_row_vs_matrix", () -> (P = ncp()[2]; R = [-78.659 35.8219]; (vec(dists(R, P, :rad)), vec(dists(R, P, :mi)))))
    add("pin dists_row_slice_hw5", () -> (P = ncp()[2]; maximum(dists(P[1:1, :], P, :mi))))
    add("pin dists_p_1_2_inf_nc", () -> (P = ncp()[2]; (dists(P, P, 1), dists(P, P, 2), dists(P, P, Inf))))
    add("pin dists_err_symbol", () -> dists([0.0 0.0], [1.0 1.0], :ft))
    add("pin S15_dists_vec_vs_matrix_p2", () -> dists([0.0, 0.0], [3.0 4.0; 6.0 8.0], 2))
    add("pin S15_dists_vec_vs_matrix_mi", () -> dists([-79.0, 35.5], ncp()[2], :mi))
    add("pin S15_dists_unit_keyword", () -> (P = ncp()[2]; dists(P, P; unit = :mi)))
    add("pin N19_dists_integer_p3", () -> dists([0.0 0.0; 1.0 2.0], [3.0 1.0; 2.0 2.0], 3))
    add("pin N19_dists_integer_p5", () -> dists([0.0 0.0; 1.0 2.0], [3.0 1.0; 2.0 2.0], 5))
    add("pin dists_both_p_and_unit_err", () -> dists([0.0 0.0], [1.0 1.0], :mi; unit = :km))

    # dists: the Matlog oracles' inputs
    add("oracle dists", () -> (d = readoracle("dists");
        (dists(d["x1"], d["x2"], 1), dists(d["x1"], d["X2"], 1), dists(d["X2"], d["X2"], 1), dists(d["ral"], d["gai"], :mi),
         [dists(d["Xr"], d["Yr"], p) for p in METRICS])))
    add("oracle dgc_nccity", () -> (XY = readoracle("dgc_nccity")["XY"]; [dists(XY, XY, p) for p in METRICS]))

    # dists: seeded random sets, every metric
    for p in METRICS
        add("rand lonlat 3000x500 $(mname(p))", () -> (r = Xoshiro(3000); dists(lonlat(r, 3000), lonlat(r, 500), p)))
        add("rand globe 200x300 $(mname(p))", () -> (r = Xoshiro(200); dists(globe(r, 200), globe(r, 300), p)))
        add("rand vector form $(mname(p))", () -> (r = Xoshiro(17); dists(vec(lonlat(r, 1)), lonlat(r, 400), p)))
        add("rand 1x1 $(mname(p))", () -> (r = Xoshiro(1); dists(lonlat(r, 1), lonlat(r, 1), p)))
        add("rand adjoint $(mname(p))", () -> (r = Xoshiro(5); dists(permutedims(lonlat(r, 30))', lonlat(r, 40), p)))
        add("rand float32 $(mname(p))", () -> (r = Xoshiro(32); dists(Float32.(lonlat(r, 60)), Float32.(lonlat(r, 50)), p)))
        add("rand int $(mname(p))", () -> (r = Xoshiro(64); dists(rand(r, -90:90, 70, 2), rand(r, -90:90, 60, 2), p)))
        add("rand view rows $(mname(p))", () -> (r = Xoshiro(9); A = lonlat(r, 100); dists(view(A, 1:2:100, :), view(A, 2:2:100, :), p)))
        p === nothing || add("rand unit kw $(mname(p))", () -> (r = Xoshiro(3); A = lonlat(r, 50); p isa Symbol ? dists(A, A; unit = p) : dists(A, A, p)))
    end
    for p in (2, :mi)
        add("rand lonlat 3000x3000 $(mname(p))", () -> (r = Xoshiro(33); dists(lonlat(r, 3000), lonlat(r, 3000), p)))
    end
    for p in LP, d in (1, 3, 5, 15, 16, 17, 20)
        add("rand dim $d $(mname(p))", () -> (r = Xoshiro(100 + d); dists(randn(r, 90, d) .* 7, randn(r, 80, d) .* 7, p)))
    end
    for p in LP
        add("rand int32 $(mname(p))", () -> (r = Xoshiro(320); dists(Int32.(rand(r, -9:9, 20, 3)), Int32.(rand(r, -9:9, 25, 3)), p)))
        add("rand int8 $(mname(p))", () -> (r = Xoshiro(321); dists(Int8.(rand(r, -100:100, 20, 2)), Int8.(rand(r, -100:100, 25, 2)), p)))
        add("rand int dim 17 $(mname(p))", () -> (r = Xoshiro(322); dists(rand(r, -99:99, 20, 17), rand(r, -99:99, 15, 17), p)))
        add("rand mixed int float $(mname(p))", () -> (r = Xoshiro(323); dists(rand(r, -9:9, 20, 2), randn(r, 25, 2), p)))
        add("no columns $(mname(p))", () -> dists(zeros(3, 0), zeros(4, 0), p))
        add("no rows $(mname(p))", () -> (dists(zeros(0, 2), ones(4, 2), p), dists(ones(3, 2), zeros(0, 2), p)))
        add("1 column against 3 $(mname(p))", () -> dists([1.0 2.0]', [1.0 2.0 3.0; -1.0 0.5 4.0], p))
        add("2 columns against 3 $(mname(p))", () -> dists(ones(2, 2), ones(3, 3), p))
        add("edge values $(mname(p))", () -> (A = [0.0 -0.0; 1e300 -1e300; 1e-300 2e-300; 1.0 NaN; Inf 0.0; 3.0 4.0];
                                                dists(A, A, p)))
    end
    for p in (:mi, :km, :rad)
        add("gc edge $(mname(p))", () -> (A = [0.0 0.0; 180.0 0.0; -180.0 0.0; 0.0 90.0; 0.0 -90.0; 179.9 10.0; -179.9 10.0;
                                               90.0 45.0; -90.0 -45.0; 1e-12 0.0; 0.0 1e-12; 37 -91; 400.0 10.0];
                                          dists(A, A, p)))
        add("gc 1 column err $(mname(p))", () -> dists(ones(2, 1), ones(3, 1), p))
        add("gc 3 columns err $(mname(p))", () -> dists(ones(2, 3), ones(3, 3), p))
        add("gc mismatch err $(mname(p))", () -> dists(ones(2, 2), ones(3, 3), p))
    end

    # dgc: the pins' inputs and seeded pairs
    add("pin dgc", () -> (a = (-78.6382, 35.7796); b = (-80.8431, 35.2271);
        (dgc(a, b), dgc(a, b; unit = :km), dgc(a, b; unit = :rad), dgc([-78.659, 35.8219], [-80.8431, 35.2271]),
         dgc((-78.6, 35.8), [-80.8, 35.2]), dgc((0, 0), (0, 1)), dgc([0, 0], [0, 1]), dgc((0.0, 0.0), (180.0, 0.0)),
         dgc((10.0, 20.0), (10.0, 20.0)))))
    add("pin dgc_errs", () -> [(try dgc([1, 2, 3], [1, 2, 3]) catch e e.msg end), (try dgc([1, 2], [1, 3]; unit = :ft) catch e e.msg end)])
    for u in (:mi, :km, :rad)
        add("rand dgc $(mname(u))", () -> (r = Xoshiro(7); A = globe(r, 20000); B = globe(r, 20000);
                                            [dgc((A[i, 1], A[i, 2]), B[i, :]; unit = u) for i in 1:20000]))
    end
    add("rand dgc int", () -> (r = Xoshiro(8); [dgc(rand(r, -180:180, 2), rand(r, -90:90, 2)) for _ in 1:1000]))

    # dgca: the pins' inputs and seeded sets
    add("pin dgca_docstring", () -> dgca([-78.64 35.78; -80.84 35.23], [-79.79 36.07; -77.94 34.23], [0.0, 500.0]))
    add("pin dgca_docstring_2", () -> dgca([-78.64 35.78; -80.84 35.23], [-79.79 36.07; -78.90 35.99], [0.0, 5000.0]))
    add("pin dgca_nc_places", () -> ((nc, P) = ncp(); dgca(P, P, nc.ALAND)))
    add("pin dgca_one_by_one", () -> ((nc, P) = ncp(); dgca(P[1:1, :], P[2:2, :], [nc.ALAND[2]])[1]))
    add("pin dgca_unit_km", () -> ((nc, P) = ncp(); dgca(P, P, nc.ALAND; unit = :km)))
    add("pin dgca_floor_binds", () -> dgca([-78.64 35.78], [-78.65 35.79], [4000.0]))
    add("pin dgca_zero_area", () -> dgca([-78.64 35.78], [-79.79 36.07], [0.0]))
    add("pin dgca_err_negative", () -> dgca([-78.64 35.78], [-79.79 36.07], [-1.0]))
    add("pin dgca_err_length", () -> dgca([-78.64 35.78], [-79.79 36.07], [1.0, 2.0]))
    for u in (:mi, :km, :rad, 2, 1)
        add("rand dgca $(mname(u))", () -> (r = Xoshiro(55); X = lonlat(r, 100); Xa = lonlat(r, 500);
                                             a = 3000 .* rand(r, 500) .* (rand(r, 500) .> 0.1); dgca(X, Xa, a; unit = u)))
    end
    add("rand dgca 3000x1000", () -> (r = Xoshiro(56); X = lonlat(r, 3000); Xa = lonlat(r, 1000);
                                       dgca(X, Xa, 1000 .* rand(r, 1000))))
    add("rand dgca one by one", () -> (r = Xoshiro(57); X = lonlat(r, 40); Xa = lonlat(r, 40); a = 2000 .* rand(r, 40);
                                        [dgca(X[i:i, :], Xa[j:j, :], [a[j]])[1] for i in 1:40, j in 1:40]))

    # lonlat2loc (calls dists): the pins' inputs
    add("pin lonlat2loc", () -> (c = usplace(); big = c[c.POP .> 100000, :];
        (lonlat2loc([-78.6382, 35.7796], c), lonlat2loc([-78.6 35.8; -80.8 35.2; -82.5 35.6], c), lonlat2loc([-90.0 35.1], big))))

    # ala: a fixed start and a fixed allocation, so every step after the first is the default locate
    function fixedalloc(P, n, w, dist)
        m = size(P, 1)
        Wf = sparse([(j - 1) % n + 1 for j in 1:m], 1:m, w, n, m)
        return X -> (Wf, sum(Wf .* dists(X, P, dist)))
    end
    for dist in Any[1, 2, Inf, :mi, :km, :rad, 1.0, 2.0]
        add("ala fixed alloc lonlat 3000 $(mname(dist))", () -> (r = Xoshiro(41); P = lonlat(r, 3000); w = 1 .+ 99 .* rand(r, 3000);
            X0 = lonlat(r, 4); ala(X0, w, P; dist, alloc = fixedalloc(P, 4, w, dist), verbose = false)))
        add("ala default lonlat 200 $(mname(dist))", () -> (r = Xoshiro(42); P = lonlat(r, 200); w = 1 .+ 99 .* rand(r, 200);
            X0 = lonlat(r, 3); ala(X0, w, P; dist, nruns = 3, rng = Xoshiro(43), verbose = false)))
        dist isa Symbol && continue
        add("ala fixed alloc 1-D $(mname(dist))", () -> (r = Xoshiro(44); P = 500 .* rand(r, 300, 1); w = rand(r, 1:9, 300);
            ala(500 .* rand(r, 3, 1), float(w), P; dist, alloc = fixedalloc(P, 3, float(w), dist), verbose = false)))
        add("ala default 3-D $(mname(dist))", () -> (r = Xoshiro(45); P = randn(r, 150, 3); w = rand(r, 150);
            ala(randn(r, 4, 3), w, P; dist, nruns = 2, rng = Xoshiro(46), verbose = false)))
        add("ala default int P $(mname(dist))", () -> (r = Xoshiro(47); P = rand(r, 0:100, 60, 2); w = rand(r, 1:5, 60);
            ala([10.0 10.0; 90.0 90.0], w, P; dist, verbose = false)))
    end
    # ala: the pins' inputs (test/test_loctools.jl), the oracle's, the docstring's and Lecture 2.3's
    P4, w4 = [0.0 0.0; 1.0 0.0; 0.0 1.0; 1.0 1.0], [1.0, 1.0, 1.0, 1.0]
    add("pin ala orphan repair", () -> (Random.seed!(1); ala([0.2 0.2; 0.8 0.8; 100.0 100.0], w4, P4; dist = 2, verbose = false)))
    add("pin ala nruns", () -> (Random.seed!(4242); ala([0.9 0.1; 0.1 0.9], w4, P4; dist = 2, nruns = 5, verbose = false)))
    add("pin ala nc cities", () -> (Random.seed!(1); ala([-78.6 35.8; -80.0 35.5], [469.0, 897.0, 299.0, 123.0],
                                                          [-78.64 35.78; -80.84 35.23; -79.79 36.07; -77.94 34.23]; verbose = false)))
    add("pin ala inf", () -> ala([0.2 0.2; 0.8 0.8], w4, P4; dist = Inf, verbose = false))
    add("pin ala rng", () -> ala([0.2 0.2; 0.8 0.8], w4, P4; dist = 2, nruns = 6, verbose = false, rng = Xoshiro(9)))
    add("oracle ala_nc", () -> begin
        d = readoracle("ala_nc")
        P, w, X0 = d["P"], vec(d["w"]), d["X0"]
        (ala(X0, w, P; dist = 2, verbose = false), ala(X0, w, P; dist = :mi, verbose = false))
    end)
    add("docstring ala nc 2 runs", () -> ala([-78.6 35.8; -80.0 35.5; -82.0 35.6], [469.0, 897.0, 299.0, 123.0, 94.0, 208.0],
        [-78.64 35.78; -80.84 35.23; -79.79 36.07; -77.94 34.23; -82.55 35.60; -78.88 35.05]; nruns = 2, rng = Xoshiro(7), verbose = false))
    PI40 = [50 150 190 220 270 295 420]'                                 # 2-loc-3.qmd:1071-1073
    wI40 = collect(1:7)
    add("lecture 2.3 code block 12", () -> (ala([0.0; 200.0;;], float(wI40), float(PI40); dist = 1, verbose = false),
                                            ala([200.0; 500.0;;], float(wI40), float(PI40); dist = 1, verbose = false)))
    add("lecture 2.3 code blocks 14 and 16", () -> begin                  # 2-loc-3.qmd:1460-1464, 1473-1474, 1505-1514
        df = filter(r -> r.STFIP in st2fips.([:NC, :SC]) && r.POP > 10_000, usplace())
        P = hcat(df.LON, df.LAT); w = float(df.POP); nef = size(P, 1)
        allocate(D, w) = (α = [argmin(c) for c in eachcol(D)]; (α, sum(sparse(α, 1:size(D, 2), w, size(D)...) .* D)))
        function alloc36(X)
            D = dists(X, P, :mi)
            α, = allocate(D, w)
            α[1:3] .= 1
            α[4:6] .= 2
            Wc = sparse(α, 1:nef, w, size(X, 1), nef)
            return Wc, sum(Wc .* D)
        end
        Random.seed!(8345); a = ala(randX(P, 2), w, P; nruns = 5, verbose = false)
        Random.seed!(8345); b = ala(randX(P, 2), w, P; alloc = alloc36, nruns = 5, verbose = false)
        (a, b)
    end)
    return C
end

# ---- running and comparing ----------------------------------------------------------------------------------
struct Err
    T::String
    msg::String
end
firstline(s) = first(split(s, '\n'))
runcase(f) = try
    f()
catch e
    Err(string(typeof(e)), firstline(sprint(showerror, e)))
end

# (equal, elements compared, where the first difference is)
function same(a, b, at = "")
    if a isa Err || b isa Err
        return (a isa Err && b isa Err && a.T == b.T && a.msg == b.msg, 1, at)
    elseif a isa SparseMatrixCSC
        b isa SparseMatrixCSC && size(a) == size(b) || return (false, 0, at * " (sparse shape)")
        return same(findnz(a), findnz(b), at * " findnz")
    elseif a isa AbstractDataFrame
        b isa AbstractDataFrame && names(a) == names(b) || return (false, 0, at * " (table columns)")
        return same(Tuple(collect(eachcol(a))), Tuple(collect(eachcol(b))), at * " table")
    elseif a isa AbstractArray
        (b isa AbstractArray && typeof(a) == typeof(b) && size(a) == size(b)) ||
            return (false, 0, at * " (array type or size: $(typeof(a)) $(size(a)) vs $(typeof(b)) $(size(b)))")
        if isbitstype(eltype(a))                         # numbers: one pass, no strings built
            for i in eachindex(a)
                a[i] === b[i] || return (false, i, at * "[$i] ($(repr(a[i])) vs $(repr(b[i])))")
            end
            return (true, length(a), at)
        end
        n = 0
        for i in eachindex(a)
            ok, k, w = same(a[i], b[i], at * "[$i]")
            ok || return (false, n + k, w)
            n += k
        end
        return (true, n, at)
    elseif a isa Union{Tuple,NamedTuple}
        (typeof(a) == typeof(b)) || return (false, 0, at * " (tuple type)")
        n = 0
        for (i, (x, y)) in enumerate(zip(values(a), values(b)))
            ok, k, w = same(x, y, at * ".$i")
            ok || return (false, n + k, w)
            n += k
        end
        return (true, n, at)
    else
        return (a === b, 1, a === b ? at : at * " ($(repr(a)) vs $(repr(b)))")
    end
end

function main()
    C = cases()
    if MODE == "save"
        open(FILE, "w") do io
            serialize(io, (julia = string(VERSION), ncases = length(C)))
            for (name, f) in C
                serialize(io, (name, runcase(f)))
            end
        end
        @printf("saved %d cases to %s (Julia %s)\n", length(C), FILE, VERSION)
    else
        bad, total = String[], 0
        open(FILE, "r") do io
            hdr = deserialize(io)
            hdr.julia == string(VERSION) || error("saved on Julia $(hdr.julia), comparing on $VERSION")
            hdr.ncases == length(C) || error("saved $(hdr.ncases) cases, now $(length(C))")
            for (name, f) in C
                name0, v0 = deserialize(io)
                name0 == name || error("case order: saved $name0, now $name")
                ok, n, w = same(v0, runcase(f))
                total += n
                ok || (push!(bad, "$name: first difference at$w"); println("DIFFERS  ", name, ": first difference at", w))
            end
        end
        @printf("compared %d cases, %d elements, on Julia %s: %s\n", length(C), total, VERSION,
                isempty(bad) ? "=== on every element" : "$(length(bad)) cases differ")
    end

    # timing: dists at m = 3000 (reported, not asserted)
    r = Xoshiro(2026)
    X1, X2 = lonlat(r, 3000), lonlat(r, 3000)
    for p in (2, 1, 3.0, Inf, :mi)
        dists(X1[1:5, :], X2[1:5, :], p)
        t = minimum(@elapsed(dists(X1, X2, p)) for _ in 1:3)
        a = @allocated dists(X1, X2, p)
        @printf("timing dists 3000x3000 p = %-4s  %.3f s  %8.1f MiB\n", repr(p), t, a / 2^20)
    end
    MODE == "compare" && exit(isempty(bad) ? 0 : 1)
end

main()
