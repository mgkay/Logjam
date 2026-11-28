# test_roadtools.jl -- the tests of src/roadtools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_road_pins.jl, its lines 1-95 ====
# test_road_pins.jl -- value equality of the course's road-network calls against the committed fixture
# (PCV K8, plan principle 9). A call the course makes today keeps returning what it returned at v0.2.8
# (the fixture was written from the code at b769154, whose roadtools.jl is unchanged from v0.2.8's).
# Only a case listed in RDPIN_MOVED may differ, and each fixture update is named in its commit.
# Regenerate with tools/v0_3_0/make_road_pins.jl. No case touches the network.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "road_pin_helpers.jl"))

@testset "road-network calls are pinned value for value" begin
    fixture = rdpin_read()
    cases = rdpin_cases()
    @test length(fixture) == length(cases)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(fixture, name)
            haskey(fixture, name) || continue
            got = rdpin_run(thunk)
            if startswith(got, "SKIPPED")
                @info "road pin $name skipped: $got"
            else
                @test got == fixture[name]
            end
        end
    end
end

# Code block 30's draw is the one the cases take (on the Julia the course is pinned to)
@testset "Lecture 4.2's Code block 30 draws the indices the OSM pins take" begin
    bg = _rd_osm_bg()
    @test nrow(bg) == 75 && all(<=(75), _RD_OSM_DRAW) && allunique(_RD_OSM_DRAW)
    if VERSION < v"1.13"
        Random.seed!(754)
        @test randperm(nrow(bg))[1:22] == _RD_OSM_DRAW
    else
        @info "Random.seed!(754); randperm draws another set on Julia $VERSION: the pins take 1.12's"
    end
end

# Lecture 4.2's committed OpenStreetMap cache, read back through osm_roads as the lecture's own calls read it, gives the
# numbers the lecture prints (Code blocks 2 to 7 and 33; where its data folder is reachable). PCV K9, principle 9.
@testset "Lecture 4.2's committed cache reads back as the lecture prints it" begin
    if !_rd_have_osm()
        @info "4.2's cache not reachable (LOGJAM_LECTURE_DATA): skipped"
    else
        x, y = _RD_OSM_X, _RD_OSM_Y
        bb = _rd_osm_bb1()
        @test round.(bb[1], digits = 3) == (-78.688, -78.657) && round.(bb[2], digits = 3) == (35.762, 35.796)
        dfN0, dfL0 = _rd_osm_read(bb)
        @test (nrow(dfN0), nrow(dfL0)) == (10674, 18927)                    # data/README-osm.md
        dfN, dfL = cropnetwork(dfN0, dfL0, x, y; xexpand = 2, yexpand = 0.5)
        @test (nrow(dfN), nrow(dfL)) == (4726, 8000)                         # Code block 2
        # the same crop, asked of osm_roads (the box passed as mapbbox returns it, no splat)
        cN, cL = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            osm_roads(bb; cache_dir = _RD_LECTURE_DATA, crop = true)
        end
        @test isequal(cN, dfN) && isequal(cL, dfL)
        # Code block 4's class table: links, miles, speeds
        S = [(f, count(==(f), dfL.FCLASS), round(sum(dfL.DIST[dfL.FCLASS .== f]), digits = 1),
              join(sort(unique(dfL.SPEED[dfL.FCLASS .== f])), ", ")) for f in sort(unique(dfL.FCLASS))]
        @test S == [(3, 863, 10.1, "30, 45"), (4, 1195, 13.5, "25, 35"), (5, 1321, 14.5, "20, 30"),
                    (6, 754, 8.0, "25"), (7, 3867, 54.4, "25")]
        # Code block 5
        arcs = Set(zip(dfL.SRC, dfL.DST))
        oneway = count(((s, d),) -> (d, s) ∉ arcs, zip(dfL.SRC, dfL.DST))
        @test round(100 * count(==(7), dfL.FCLASS) / nrow(dfL), digits = 1) == 48.3
        @test round(100 * oneway / nrow(dfL), digits = 1) == 23.8
        @test round(Int, 5280 * _rd_median(dfL.DIST)) == 39
        @test all(==(1), dfL.DIR)
        # Code blocks 6 and 7: the two graphs, and each route's miles and minutes
        Nc, Lc = addconnectors(dfN, dfL, x, y; add_nf_nf = false)
        @test (nrow(Nc), nrow(Lc)) == (4728, 8006)
        con = isequal.(Lc.SOURCE, "CONNECTOR")
        tmin = [c ? 60d / 20 : 60d / v for (c, d, v) in zip(con, Lc.DIST, Lc.SPEED)]
        gD, gT = _rd_graph(Lc, Lc.DIST), _rd_graph(Lc, tmin)
        D, PD = shortestpaths(gD, 2)
        T, PT = shortestpaths(gT, 2)
        Wd, Wt = weights(gD), weights(gT)
        R = [(round(round(sum(segcost(tracepath(P[i], i, j), Wd)), digits = 3), digits = 2),
              round(sum(segcost(tracepath(P[i], i, j), Wt)), digits = 2)) for (i, j) in ((1, 2), (2, 1)) for P in (PD, PT)]
        @test R == [(1.91, 4.08), (2.12, 3.87), (2.0, 3.9), (2.01, 3.89)]    # Out and Back, Shortest and Fastest
        # Ex. 3, Code blocks 31 and 33: the 22 points' box, its cell pair, the driving minutes among them
        U = _rd_osm_U()
        NU, LU = cropnetwork(_rd_osm_read(_rd_osm_bb3())..., U.LON, U.LAT; xexpand = 0.1, yexpand = 0.1)
        NU, LU = addconnectors(NU, LU, U.LON, U.LAT; add_nf_nf = false)
        cU = isequal.(LU.SOURCE, "CONNECTOR")
        tU = [c ? 60d / 20 : 60d / v for (c, d, v) in zip(cU, LU.DIST, LU.SPEED)]
        TU, PU = shortestpaths(_rd_graph(LU, tU), nrow(U))
        @test round(sum(TU[1:22, 1:22]) / (22 * 21), digits = 2) == 6.46
        @test all(isfinite, TU[1:22, 1:22])
    end
end

# ==== moved from test/test_line_builders.jl, its lines 1-155 ====
# test_line_builders.jl -- the line builders as one family (PCV K11b, MAP, C8): x2ln(i, j, x), tracepath(P, i, j) and
# tracepath(P, seq), each equal to what the course writes by hand today. The course's own calls of x2ln(g, x) and
# tracepath(P[i], i, j) are pinned in test_road_pins.jl and test_map_line_pins.jl.

using Test
using Logjam
using DataFrames
using Random
using SimpleWeightedGraphs
using Graphs

# a connected network of n nodes: a chain, then random extra links; DIR drawn from {0, 0, 0, 1, -1} so that some links are one-way
function _lb_network(rng, n; extra = 2n)
    SRC = collect(1:n-1); DST = collect(2:n)
    for _ in 1:extra
        a, b = rand(rng, 1:n), rand(rng, 1:n)
        a == b && continue
        push!(SRC, a); push!(DST, b)
    end
    DIST = round.(10 .* rand(rng, length(SRC)) .+ 1, digits = 3)
    DIR = vcat(zeros(Int, n - 1), rand(rng, [0, 0, 0, 1, -1], length(SRC) - (n - 1)))
    return DataFrame(SRC = SRC, DST = DST, DIST = DIST, DIR = DIR)
end

# the course's idiom, 5-rte-1.qmd:2682-2684 and 5-rte-3.qmd:3731-3734
function _lb_idiom(P, seq)
    legs = zip(seq[1:end-1], seq[2:end])
    path = reduce(vcat, [tracepath(P[i], i, j)[1:end-1] for (i, j) in legs])
    push!(path, seq[end])
    return path
end

# the segments a NaN-separated coordinate vector draws, each as an unordered pair of endpoints
function _lb_segments(xs, ys)
    segs = Set{Tuple}()
    for k in 1:3:length(xs)
        a, b = (xs[k], ys[k]), (xs[k+1], ys[k+1])
        push!(segs, a <= b ? (a, b) : (b, a))
    end
    return segs
end

@testset "[MAP, C8] the line builders as one family" begin

    @testset "x2ln(i, j, x): the links' own index columns draw the lines" begin
        @test isequal(x2ln([1, 2, 3], [2, 3, 1], [-78.0, -79.0, -80.0]), [-78.0, -79.0, NaN, -79.0, -80.0, NaN, -80.0, -78.0, NaN])
        @test x2ln([1, 2], [2, 1], [1.0, 2.0]) isa Vector{Float64}
        @test x2ln(1:2, 2:3, 1:3) isa Vector{Float64}                    # ranges and integer coordinates
        @test isequal(x2ln(1:2, 2:3, 1:3), [1.0, 2.0, NaN, 2.0, 3.0, NaN])
        @test x2ln(Int[], Int[], [1.0, 2.0]) == Float64[]
        @test_throws ArgumentError x2ln([1, 2], [2], [1.0, 2.0])
        @test_throws BoundsError x2ln([1], [3], [1.0, 2.0])
        # Lecture 5.2's sh2ln(sh, x) (Code block 9, 5-rte-2.qmd:637-638), exactly
        sh2ln(sh, x) = vcat(collect([x[b], x[e], NaN] for (b, e) in zip(sh.b, sh.e))...)
        sh = DataFrame(b = [1, 2, 6, 3], e = [4, 5, 1, 2])
        x = [-78.1, -79.3, -80.2, -81.0, -77.7, -82.4]
        @test isequal(x2ln(sh.b, sh.e, x), sh2ln(sh, x))
        @test isequal(x2ln(sh.b, sh.e, x .+ 1), sh2ln(sh, x .+ 1))
    end

    @testset "x2ln(i, j, x) draws the segments of x2ln(g, x), Lecture 4.1's drawing graph" begin
        rng = Xoshiro(754)
        for n in (6, 15), trial in 1:3
            L = _lb_network(rng, n)
            lon, lat = round.(-80 .+ 3 .* rand(rng, n), digits = 4), round.(35 .+ 2 .* rand(rng, n), digits = 4)
            g = SimpleWeightedGraph(L.SRC, L.DST, L.DIST; combine = min)  # 4-net-1.qmd:1099, `gR`; 4-net-2.qmd:314, `street`
            old = (x2ln(g, lon), x2ln(g, lat))
            new = (x2ln(L.SRC, L.DST, lon), x2ln(L.SRC, L.DST, lat))
            @test _lb_segments(new...) == _lb_segments(old...)           # the same lines; the graph has one edge for a pair
            @test length(new[1]) == 3 * nrow(L) && length(old[1]) == 3 * ne(g)
            @test all(isnan, new[1][3:3:end]) && all(isnan, new[2][3:3:end])
        end
        # where no pair is repeated and the links are in the graph's order, the two vectors are identical
        L = DataFrame(SRC = [1, 1, 2, 3], DST = [2, 3, 4, 4], DIST = [1.0, 2.0, 3.0, 4.0])
        lon = [-78.0, -79.0, -80.0, -81.0]
        g = SimpleWeightedGraph(L.SRC, L.DST, L.DIST)
        @test isequal(x2ln(L.SRC, L.DST, lon), x2ln(g, lon))
        # the existing method is untouched
        @test isequal(x2ln(g, lon), vcat(map(e -> [lon[Graphs.src(e)], lon[Graphs.dst(e)], NaN], Graphs.edges(g))...))
    end

    @testset "tracepath(P, i, j) is tracepath(P[i], i, j)" begin
        rng = Xoshiro(41)
        for n in (5, 12), trial in 1:3
            L = _lb_network(rng, n)
            D, P = shortestpaths(links2graph(L), n)
            for i in 1:n, j in 1:n
                if isfinite(D[i, j])
                    @test tracepath(P, i, j) == tracepath(P[i], i, j)
                else
                    @test_throws ArgumentError tracepath(P, i, j)
                    @test_throws ArgumentError tracepath(P[i], i, j)
                end
            end
        end
        P = [[0, 1, 2, 3], [2, 0, 2, 3], [2, 3, 0, 3], [2, 3, 4, 0]]
        @test tracepath(P, 1, 4) == [1, 2, 3, 4] && tracepath(P, 4, 1) == [4, 3, 2, 1]
        @test tracepath(P, 2, 2) == [2]
        @test tracepath(P, 1, 4) isa Vector{Int}
        # a parent vector of another integer type
        P32 = [Int32.(p) for p in P]
        @test tracepath(P32, 1, 4) == [1, 2, 3, 4] && tracepath(P32, 1, 4) isa Vector{Int}
        @test_throws BoundsError tracepath(P, 5, 1)
        @test_throws ArgumentError tracepath([[0, 0, 0]], 1, 3)          # unreachable: the parent is 0
    end

    @testset "tracepath(P, seq) is the course's reduce(vcat, ...) idiom plus the last node" begin
        rng = Xoshiro(2026)
        for n in (6, 14), trial in 1:4
            L = _lb_network(rng, n)
            D, P = shortestpaths(links2graph(L), n)
            ok = findall(i -> all(isfinite, D[i, :]), 1:n)               # locations that reach all others
            length(ok) >= 3 || continue
            for _ in 1:10
                seq = rand(rng, ok, rand(rng, 2:8))
                all(k -> isfinite(D[seq[k], seq[k+1]]), 1:length(seq)-1) || continue
                @test tracepath(P, seq) == _lb_idiom(P, seq)
            end
        end
        P = [[0, 1, 2, 3, 4], [2, 0, 2, 3, 4], [2, 3, 0, 3, 4], [2, 3, 4, 0, 4], [2, 3, 4, 5, 0]]
        @test tracepath(P, [1, 4, 2, 5]) == [1, 2, 3, 4, 3, 2, 3, 4, 5]
        # a junction is one node, not two
        @test tracepath(P, [1, 3, 5]) == [1, 2, 3, 4, 5]
        @test tracepath(P, [1, 3, 5]) == vcat(tracepath(P, 1, 3), tracepath(P, 3, 5)[2:end])
        # a leg from a location to itself adds no node; a location repeated in a row is one node
        @test tracepath(P, [1, 1, 3]) == [1, 2, 3]
        @test tracepath(P, [2, 2, 2]) == [2]
        # one location is that node, none is no path; a closed tour starts and ends at its first location
        @test tracepath(P, [3]) == [3] && tracepath(P, Int[]) == Int[]
        @test tracepath(P, [1, 3, 1]) == [1, 2, 3, 2, 1]
        @test tracepath(P, [1, 3, 1]) isa Vector{Int}
        @test tracepath(P, 1:3) == [1, 2, 3]                             # any integer vector
        @test_throws ArgumentError tracepath([[0, 0], [0, 0]], [1, 2])    # a leg that cannot be traced
        # Lecture 5.1's tour: the closed sequence of Code block 37, whose push!(path, path[1]) is seq[end] = seq[1]
        tour = [1, 4, 2, 5, 3, 1]
        path = reduce(vcat, [tracepath(P[i], i, j)[1:end-1] for (i, j) in zip(tour[1:end-1], tour[2:end])])
        push!(path, path[1])
        @test tracepath(P, tour) == path
    end

    @testset "the methods are not ambiguous with one another" begin
        ms = collect(methods(tracepath))
        @test length(ms) == 3
        for a in ms, b in ms
            a === b && continue
            @test !Base.isambiguous(a, b)
        end
        @test Base.which(tracepath, Tuple{Vector{Int}, Int, Int}).sig == Tuple{typeof(tracepath), Vector{Int}, Int, Int}
        @test Base.which(tracepath, Tuple{Vector{Vector{Int}}, Int, Int}) != Base.which(tracepath, Tuple{Vector{Int}, Int, Int})
        @test Base.which(tracepath, Tuple{Vector{Vector{Int}}, Vector{Int}}) != Base.which(tracepath, Tuple{Vector{Vector{Int}}, Int, Int})
        ms = collect(methods(x2ln))
        @test length(ms) == 2
        @test !Base.isambiguous(ms[1], ms[2])
    end
end

# ==== moved from test/test_map_line_pins.jl, its lines 1-13, 248-268 ====
# test_map_line_pins.jl -- what the course sees of `plotroads!`, the base-layer styles `makemap` draws, the FAF5
# tables and `tracepath`, pinned from the code at 83c799b (PCV K11b, plan principle 9; K11a's own pins are
# test_map_pins.jl). The values below were measured on the unchanged code, before K11b's C4 (`makemap`'s interface),
# C8 (the line builders) and C12 (cached FAF5 tables) changed it. A call the course makes today keeps returning
# what it returned then; only a case named in MLPIN_MOVED may differ, and each one is named in the commit that moves it.
#
# No case touches the network or a file outside the package, and none renders a picture.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie
isdefined(@__MODULE__, :MLPIN_MOVED) || include(joinpath(@__DIR__, "map_line_pin_helpers.jl"))   # WP8: defined once

# ---- tracepath on the course's idiom -------------------------------------------------------------------------
# `tracepath(P[i], i, j)` (4-net-1.qmd:1480, 1585; 4-net-2.qmd:271, 941) and the tour along the roads,
# `reduce(vcat, [tracepath(P[i], i, j)[1:end-1] for (i, j) in legs])` then the last node (5-rte-1.qmd:2682-2684,
# 5-rte-3.qmd:3731-3734), on a six-node network with no ties among its shortest paths.
@testset "tracepath(P[i], i, j) on the course's idiom is pinned" begin
    if !_mlpin_moved("tracepath_idiom")
        links = DataFrame(SRC = [1, 2, 3, 4, 2, 5], DST = [2, 3, 4, 5, 5, 6], DIST = [10.0, 20.0, 15.0, 5.0, 41.0, 7.0], DIR = [0, 0, 0, 0, 0, 0])
        D, P = shortestpaths(links2graph(links), 6)
        @test P == [[0, 1, 2, 3, 4, 5], [2, 0, 2, 3, 4, 5], [2, 3, 0, 3, 4, 5], [2, 3, 4, 0, 4, 5], [2, 3, 4, 5, 0, 5], [2, 3, 4, 5, 6, 0]]
        @test tracepath(P[1], 1, 6) == [1, 2, 3, 4, 5, 6]
        @test tracepath(P[6], 6, 1) == [6, 5, 4, 3, 2, 1]
        @test tracepath(P[3], 3, 3) == [3]                                  # origin == dest is the one node
        @test tracepath(P[2], 2, 1) == [2, 1]
        @test_throws ArgumentError tracepath([0, 1, 0], 1, 3)               # unreachable
        legs = zip([1, 3, 6, 2], [3, 6, 2, 1])
        path = reduce(vcat, [tracepath(P[i], i, j)[1:end-1] for (i, j) in legs])
        push!(path, 1)
        @test path == [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1]
    end
end

# ==== moved from test/test_roadtools.jl, its lines 1-792 ====
# Tests for RoadTools functions

using Test
using Logjam
using DataFrames
# `_test_rte2lines`, the line coordinates of a location sequence along shortest paths, is in
# common_helpers.jl with its note, defined once for this file and test_integration.jl (WP8)
isdefined(@__MODULE__, :_test_rte2lines) || include(joinpath(@__DIR__, "common_helpers.jl"))
using Graphs
using SparseArrays
using SimpleWeightedGraphs

@testset "RoadTools" begin

    @testset "dgc - Great Circle Distance" begin
        # Raleigh to Charlotte (approximately 130 miles)
        raleigh = (-78.6382, 35.7796)
        charlotte = (-80.8431, 35.2271)
        d_mi = dgc(raleigh, charlotte)
        @test 125 < d_mi < 135  # Should be approximately 130 miles

        # Same distance in kilometers
        d_km = dgc(raleigh, charlotte; unit=:km)
        @test 200 < d_km < 220  # Should be approximately 210 km

        # Verify km > mi (since km is smaller unit)
        @test d_km > d_mi

        # Zero distance (same point)
        @test dgc(raleigh, raleigh) ≈ 0.0 atol=1e-10

        # NYC to LA (approximately 2450 miles)
        nyc = (-74.006, 40.7128)
        la = (-118.2437, 34.0522)
        d_cross = dgc(nyc, la)
        @test 2400 < d_cross < 2500

        # Error cases
        @test_throws Exception dgc((1,), (1, 2))  # Wrong length
        @test_throws Exception dgc(raleigh, charlotte; unit=:ft)  # Invalid unit
    end

    @testset "dists - Distance Matrix" begin
        # Three NC cities
        origins = [-78.6 35.8; -80.8 35.2; -79.0 36.1]  # Raleigh, Charlotte, Durham
        dests = [-77.0 35.0; -78.5 36.0]  # Two destinations

        # Test great circle distance (replaces Dgc)
        D_gc = dists(origins, dests, :mi)
        @test size(D_gc) == (3, 2)
        @test all(D_gc .>= 0)  # All distances non-negative

        # Diagonal of square matrix should be zeros
        D_square = dists(origins, origins, :mi)
        @test size(D_square) == (3, 3)
        for i in 1:3
            @test D_square[i, i] ≈ 0.0 atol=1e-10
        end

        # Symmetry
        @test D_square[1, 2] ≈ D_square[2, 1] atol=1e-10

        # Test Euclidean distance (default)
        D_eucl = dists(origins, dests)
        @test size(D_eucl) == (3, 2)
        @test all(D_eucl .>= 0)

        # Test Euclidean with explicit p=2
        D_eucl2 = dists(origins, dests, 2)
        @test D_eucl ≈ D_eucl2

        # Test Manhattan distance
        D_manh = dists(origins, dests, 1)
        @test size(D_manh) == (3, 2)
        @test all(D_manh .>= D_eucl)  # Manhattan >= Euclidean

        # Test kilometers
        D_km = dists(origins, dests, :km)
        @test D_km ≈ D_gc .* 1.60934 atol=0.1  # mi to km conversion
    end

    @testset "prune_reindex" begin
        # Create simple test network
        # Nodes: 10, 20, 30, 40 (non-sequential)
        # Links: 10-20, 20-30, 30-40
        dfN = DataFrame(
            IDX = [10, 20, 30, 40, 50],  # Node 50 has no links
            LON = [-78.0, -79.0, -80.0, -81.0, -82.0],
            LAT = [35.0, 35.5, 36.0, 35.5, 35.0]
        )
        dfL = DataFrame(
            SRC = [10, 20, 30],
            DST = [20, 30, 40],
            DIST = [10.0, 15.0, 12.0]
        )

        dfN_out, dfL_out = prune_reindex(dfN, dfL)

        # Node 50 should be removed (no links)
        @test nrow(dfN_out) == 4

        # Node IDs should now be 1, 2, 3, 4
        @test sort(dfN_out.IDX) == [1, 2, 3, 4]

        # Links should reference new IDs
        @test minimum(dfL_out.SRC) >= 1
        @test maximum(dfL_out.DST) <= 4

        # Same number of links
        @test nrow(dfL_out) == 3

        # Total distance preserved
        @test sum(dfL_out.DIST) ≈ sum(dfL.DIST)
    end

    @testset "prune_reindex - custom column order" begin
        dfN = DataFrame(
            NAME = ["A", "B", "C", "D", "E"],
            IDX = [10, 20, 30, 40, 50],
            LON = [-78.0, -79.0, -80.0, -81.0, -82.0],
            LAT = [35.0, 35.5, 36.0, 35.5, 35.0]
        )
        dfL = DataFrame(
            LINKID = [101, 102, 103],
            SRC = [10, 20, 30],
            DST = [20, 30, 40],
            DIST = [10.0, 15.0, 12.0]
        )

        dfN_out, dfL_out = prune_reindex(dfN, dfL; src_col=:SRC, dst_col=:DST, node_col=:IDX)

        @test nrow(dfN_out) == 4
        @test sort(dfN_out.IDX) == [1, 2, 3, 4]
        @test minimum(dfL_out.SRC) >= 1
        @test maximum(dfL_out.DST) <= 4
        @test sum(dfL_out.DIST) ≈ sum(dfL.DIST)
    end

    @testset "links2graph" begin
        dfL = DataFrame(
            SRC = [1, 2, 3, 1],
            DST = [2, 3, 4, 3],
            DIST = [10.0, 15.0, 12.0, 20.0]
        )

        g = links2graph(dfL)

        @test Graphs.nv(g) == 4
        # Directed graph: 4 links * 2 directions = 8 edges
        @test Graphs.ne(g) == 8
        @test Graphs.has_edge(g, 1, 2)
        @test Graphs.has_edge(g, 2, 1)  # Reverse edge
        @test Graphs.has_edge(g, 2, 3)
        @test Graphs.has_edge(g, 3, 4)
        @test Graphs.has_edge(g, 1, 3)
    end

    @testset "x2ln" begin
        # Simple 3-node graph: 1-2, 2-3
        g = Graphs.SimpleGraph(3)
        Graphs.add_edge!(g, 1, 2)
        Graphs.add_edge!(g, 2, 3)

        x = [1.0, 2.0, 3.0]  # Node x-coordinates

        x_ln = x2ln(g, x)

        # Should have pattern: [x1, x2, NaN, x2, x3, NaN]
        @test length(x_ln) == 6
        @test count(isnan, x_ln) == 2  # Two NaN separators
    end

    @testset "addconnectors - basic" begin
        # Create simple 4-node network
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -78.0, -79.0, -79.0],
            LAT = [35.0, 36.0, 35.0, 36.0],
            ZONE = ["N1", "N2", "N3", "N4"]
        )
        dfL = DataFrame(
            SRC = [1, 2, 1],
            DST = [2, 4, 3],
            DIST = [69.0, 69.0, 54.0],  # Approximate great circle distances
            SPEED = [55, 60, 50],
            DIR = [0, 1, 0]
        )

        # Add one demand point
        x′ = [-78.5]
        y′ = [35.5]

        dfN_conn, dfL_conn = addconnectors(dfN, dfL, x′, y′)

        # Demand point should be node 1, network nodes shifted to 2-5
        @test nrow(dfN_conn) == 5
        @test dfN_conn.IDX[1] == 1  # Demand point is first

        # Should have original links + connectors (with added SOURCE column)
        @test nrow(dfL_conn) > nrow(dfL)
        @test names(dfL_conn) == [names(dfL); "SOURCE"]
        @test names(dfN_conn) == names(dfN)
        @test dfL_conn.SPEED[1:nrow(dfL)] == dfL.SPEED
        @test dfL_conn.DIR[1:nrow(dfL)] == dfL.DIR
        @test all(ismissing, dfL_conn.SPEED[(nrow(dfL) + 1):end])
        @test all(dfL_conn.DIR[(nrow(dfL) + 1):end] .== 0)
        @test ismissing(dfN_conn.ZONE[1])
        @test dfN_conn.ZONE[2:end] == dfN.ZONE

        # Connector links should connect node 1 to nearby network nodes
        connector_links = filter(r -> r.SRC == 1 || r.DST == 1, dfL_conn)
        @test nrow(connector_links) >= 1
    end

    @testset "addconnectors - multiple demand points" begin
        dfN = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -78.0, -79.0, -79.0],
            LAT = [35.0, 36.0, 35.0, 36.0]
        )
        dfL = DataFrame(
            SRC = [1, 2, 1],
            DST = [2, 4, 3],
            DIST = [69.0, 69.0, 54.0]
        )

        # Add three demand points
        x′ = [-78.2, -78.8, -78.5]
        y′ = [35.2, 35.8, 35.5]

        dfN_conn, dfL_conn = addconnectors(dfN, dfL, x′, y′)

        # Demand points should be nodes 1, 2, 3
        @test nrow(dfN_conn) == 7  # 3 demand + 4 network
        @test dfN_conn.IDX[1:3] == [1, 2, 3]

        # Network nodes shifted by 3
        @test dfN_conn.IDX[4:7] == [4, 5, 6, 7]
    end

    @testset "addconnectors - custom column order" begin
        dfN = DataFrame(
            NAME = ["N1", "N2", "N3", "N4"],
            IDX = [10, 20, 30, 40],
            LON = [-78.0, -78.0, -79.0, -79.0],
            LAT = [35.0, 36.0, 35.0, 36.0]
        )
        dfL = DataFrame(
            LINKID = [1001, 1002, 1003],
            SRC = [10, 20, 10],
            DST = [20, 40, 30],
            DIST = [69.0, 69.0, 54.0],
            SPEED = [55, 60, 50]
        )

        x_prime = [-78.5]
        y_prime = [35.5]
        dfN_conn, dfL_conn = addconnectors(
            dfN, dfL, x_prime, y_prime;
            src_col=:SRC, dst_col=:DST, dist_col=:DIST,
            node_col=:IDX, x_col=:LON, y_col=:LAT
        )

        @test names(dfL_conn) == [names(dfL); "SOURCE"]
        @test names(dfN_conn) == names(dfN)
        @test dfN_conn.IDX[1] == 1
        @test Set(dfN_conn.IDX[2:end]) == Set(2:5)
        @test all(v -> v in Set(dfN_conn.IDX), dfL_conn.SRC)
        @test all(v -> v in Set(dfN_conn.IDX), dfL_conn.DST)
        @test dfL_conn.SPEED[1:nrow(dfL)] == dfL.SPEED
        @test all(ismissing, dfL_conn.SPEED[(nrow(dfL) + 1):end])
    end

    @testset "addconnectors - NF-NF connectors" begin
        # Shared network for all sub-tests
        dfN_nf = DataFrame(
            IDX = [1, 2, 3, 4],
            LON = [-78.0, -78.0, -79.0, -79.0],
            LAT = [35.0, 36.0, 35.0, 36.0]
        )
        dfL_nf = DataFrame(
            SRC = [1, 2, 1],
            DST = [2, 4, 3],
            DIST = [69.0, 69.0, 54.0],
            DIR = [0, 1, 0]
        )

        @testset "A. three NF points (triangle)" begin
            x′ = [-78.2, -78.8, -78.5]
            y′ = [35.2, 35.8, 35.5]
            dfN_conn, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)

            # NF-NF links: both endpoints in 1:3
            nf_links = filter(r -> r.SRC <= 3 && r.DST <= 3, dfL_conn)
            @test nrow(nf_links) == 3  # 3 points → 3 Delaunay edges

            # DIR = 0 for all NF-NF connectors
            @test all(nf_links.DIR .== 0)

            # Circuity applied: check edge (1,3)
            nf13 = filter(r -> Set([r.SRC, r.DST]) == Set([1, 3]), dfL_conn)
            @test nrow(nf13) == 1
            raw = dgc((-78.2, 35.2), (-78.5, 35.5))
            @test nf13.DIST[1] ≈ 1.3 * raw
        end

        @testset "B. disabled with add_nf_nf=false" begin
            x′ = [-78.2, -78.8, -78.5]
            y′ = [35.2, 35.8, 35.5]
            _, dfL_on = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)
            _, dfL_off = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=false)

            @test nrow(dfL_on) > nrow(dfL_off)
            nf_off = filter(r -> r.SRC <= 3 && r.DST <= 3, dfL_off)
            @test nrow(nf_off) == 0
        end

        @testset "C. two NF points" begin
            x′ = [-78.3, -78.7]
            y′ = [35.3, 35.7]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)

            nf_links = filter(r -> r.SRC <= 2 && r.DST <= 2, dfL_conn)
            @test nrow(nf_links) == 1
            @test Set([nf_links.SRC[1], nf_links.DST[1]]) == Set([1, 2])
            raw = dgc((-78.3, 35.3), (-78.7, 35.7))
            @test nf_links.DIST[1] ≈ 1.3 * raw
        end

        @testset "D. single NF point" begin
            x′ = [-78.5]
            y′ = [35.5]
            _, dfL_on = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)
            _, dfL_off = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=false)
            @test nrow(dfL_on) == nrow(dfL_off)
        end

        @testset "E. collinear NF points" begin
            # 4 points along a line (no true triangles)
            x′ = [-78.0, -78.5, -79.0, -79.5]
            y′ = [35.0, 35.0, 35.0, 35.0]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)

            nf_links = filter(r -> r.SRC <= 4 && r.DST <= 4, dfL_conn)
            @test nrow(nf_links) >= 3  # chain: 1-2, 2-3, 3-4 at minimum
        end

        @testset "F. no duplicate arcs" begin
            x′ = [-78.2, -78.8, -78.5]
            y′ = [35.2, 35.8, 35.5]
            _, dfL_conn = addconnectors(dfN_nf, dfL_nf, x′, y′; add_nf_nf=true)

            nf_links = filter(r -> r.SRC <= 3 && r.DST <= 3, dfL_conn)
            edges = Set([Set([r.SRC, r.DST]) for r in eachrow(nf_links)])
            @test length(edges) == nrow(nf_links)  # no duplicates
        end
    end

    @testset "cropnetwork" begin
        # Create a larger network
        dfN = DataFrame(
            IDX = 1:10,
            LON = [-78.0, -78.5, -79.0, -79.5, -80.0, -80.5, -81.0, -81.5, -82.0, -82.5],
            LAT = [35.0, 35.2, 35.4, 35.6, 35.8, 36.0, 36.2, 36.4, 36.6, 36.8]
        )
        dfL = DataFrame(
            SRC = [1, 2, 3, 4, 5, 6, 7, 8, 9],
            DST = [2, 3, 4, 5, 6, 7, 8, 9, 10],
            DIST = fill(10.0, 9)
        )

        # Crop to region around nodes 3-7 (LON ~ -79 to -81, LAT ~ 35.4 to 36.2)
        x = [-79.5, -80.5]
        y = [35.6, 36.0]

        dfN_crop, dfL_crop = cropnetwork(dfN, dfL, x, y)

        # Should have fewer nodes than original
        @test nrow(dfN_crop) < nrow(dfN)
        @test nrow(dfN_crop) >= 2  # At least 2 nodes

        # Node IDs should be sequential starting from 1
        @test minimum(dfN_crop.IDX) == 1

        # Links should reference valid nodes
        max_node = maximum(dfN_crop.IDX)
        @test all(dfL_crop.SRC .<= max_node)
        @test all(dfL_crop.DST .<= max_node)
    end

    # --- Return-order regression tests (V7) ---

    @testset "prune_reindex - return order regression" begin
        dfN = DataFrame(IDX = [1, 2, 3], LON = [-78.0, -79.0, -80.0], LAT = [35.0, 35.5, 36.0])
        dfL = DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [10.0, 15.0])
        dfN_out, dfL_out = prune_reindex(dfN, dfL)
        @test "IDX" in names(dfN_out)
        @test "SRC" in names(dfL_out)
        @test "DST" in names(dfL_out)
    end

    @testset "addconnectors - return order regression" begin
        dfN = DataFrame(IDX = [1, 2, 3, 4], LON = [-78.0, -78.0, -79.0, -79.0], LAT = [35.0, 36.0, 35.0, 36.0])
        dfL = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0])
        dfN_out, dfL_out = addconnectors(dfN, dfL, [-78.5], [35.5])
        @test "IDX" in names(dfN_out)
        @test "SRC" in names(dfL_out)
        @test "DST" in names(dfL_out)
    end

    @testset "cropnetwork - return order regression" begin
        dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.5, -79.0, -79.5, -80.0], LAT = [35.0, 35.2, 35.4, 35.6, 35.8])
        dfL = DataFrame(SRC = [1, 2, 3, 4], DST = [2, 3, 4, 5], DIST = fill(10.0, 4))
        dfN_out, dfL_out = cropnetwork(dfN, dfL, [-79.5, -78.5], [35.2, 35.6])
        @test "IDX" in names(dfN_out)
        @test "SRC" in names(dfL_out)
        @test "DST" in names(dfL_out)
    end

    @testset "shortestpaths - weighted graph (new API)" begin
        # Create simple 4-node graph: 1-2-3-4 (chain)
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 20.0, 15.0]
        )

        g = links2graph(dfL)

        # New API: no separate weights needed
        D, P = shortestpaths(g, 2)

        # D should be 2x2
        @test size(D) == (2, 2)

        # Diagonal should be zero
        @test D[1, 1] ≈ 0.0
        @test D[2, 2] ≈ 0.0

        # D[1,2] should be 10 (direct edge)
        @test D[1, 2] ≈ 10.0

        # D[2,1] should also be 10 (symmetric)
        @test D[2, 1] ≈ 10.0

        # P should have 2 parent vectors
        @test length(P) == 2

        # Parent of node 2 from node 1 should be 1
        @test P[1][2] == 1
    end

    @testset "shortestpaths - path reconstruction (new API)" begin
        # 4-node graph with chain structure
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 20.0, 15.0]
        )

        g = links2graph(dfL)
        D, P = shortestpaths(g, 4)

        # Distance from 1 to 4 should be 10 + 20 + 15 = 45
        @test D[1, 4] ≈ 45.0

        # Trace path from 1 to 4 using parents
        path = [4]
        curr = 4
        while P[1][curr] != 0
            curr = P[1][curr]
            push!(path, curr)
        end
        reverse!(path)

        @test path == [1, 2, 3, 4]
    end

    @testset "shortestpaths - explicit weights (legacy API)" begin
        # 4-node graph with chain structure
        dfL = DataFrame(
            SRC = [1, 2, 3],
            DST = [2, 3, 4],
            DIST = [10.0, 20.0, 15.0]
        )

        # Create undirected graph for legacy API test
        max_node = maximum(vcat(dfL.SRC, dfL.DST))
        g_simple = Graphs.SimpleGraph(max_node)
        for row in eachrow(dfL)
            Graphs.add_edge!(g_simple, row.SRC, row.DST)
        end

        # Create symmetric weight matrix
        n = Graphs.nv(g_simple)
        I = vcat(dfL.SRC, dfL.DST)
        J = vcat(dfL.DST, dfL.SRC)
        V = vcat(dfL.DIST, dfL.DIST)
        weights = sparse(I, J, V, n, n)

        # Legacy API with explicit weights: deprecated, and still gives the answer. Under Pkg.test the
        # deprecation warns (--depwarn=yes) and `@test_deprecated` checks it; elsewhere it prints nothing.
        if Base.JLOptions().depwarn == 1
            D, P = @test_deprecated shortestpaths(g_simple, weights, 4)
        else
            D, P = shortestpaths(g_simple, weights, 4)
        end

        # Distance from 1 to 4 should be 10 + 20 + 15 = 45
        @test D[1, 4] ≈ 45.0
        @test tracepath(P[1], 1, 4) == [1, 2, 3, 4]
    end

    @testset "[N28] shortestpaths(g, n) takes any simple weighted graph, and the weights are the graph's" begin
        # an undirected SimpleWeightedGraph (Lecture 4.1, Code block 57's thinned Interstates)
        gu = SimpleWeightedGraphs.SimpleWeightedGraph([1, 2, 3], [2, 3, 1], [1.0, 2.0, 5.0])
        Du, Pu = shortestpaths(gu, 3)
        @test Du == [0.0 1.0 3.0; 1.0 0.0 2.0; 3.0 2.0 0.0]
        @test tracepath(Pu[1], 1, 3) == [1, 2, 3]
        # the legacy three-argument form on the same graph gives the same distances
        D3 = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            shortestpaths(gu, weights(gu), 3)[1]
        end
        @test D3 == Du
        # a directed graph: one-way arcs make the distances differ by direction
        gd = SimpleWeightedGraphs.SimpleWeightedDiGraph([1, 2, 3], [2, 3, 1], [1.0, 2.0, 5.0])
        Dd, _ = shortestpaths(gd, 3)
        @test Dd[1, 3] == 3.0 && Dd[3, 1] == 5.0
        # more sources than nodes is refused, not an out-of-range
        @test_throws ArgumentError shortestpaths(gd, 4)
        # the example of v0.2.8 built `weights + weights'` from the links of a network that lists both
        # directions (OpenStreetMap's, or any DIR 1 pair), which doubles each weight: the graph's own weights
        # give the distance of the links, not twice it
        dfL = DataFrame(SRC = [1, 2, 2, 3], DST = [2, 1, 3, 2], DIST = [10.0, 10.0, 20.0, 20.0], DIR = [1, 1, 1, 1])
        g = links2graph(dfL)
        @test shortestpaths(g, 3)[1][1, 3] == 30.0
        W = sparse(dfL.SRC, dfL.DST, dfL.DIST, 3, 3)
        @test (W + W')[1, 2] == 20.0                                            # the doubling, for the record
        D2 = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            shortestpaths(g, W + W', 3)[1]
        end
        @test D2[1, 3] == 60.0                                                  # v0.2.8's example, twice the miles
    end

    @testset "tracepath" begin
        # Chain graph: 1→2→3→4
        parents = [0, 1, 2, 3]

        @test tracepath(parents, 1, 4) == [1, 2, 3, 4]
        @test tracepath(parents, 1, 3) == [1, 2, 3]
        @test tracepath(parents, 1, 2) == [1, 2]

        # origin == dest
        @test tracepath(parents, 1, 1) == [1]
        @test tracepath(parents, 3, 3) == [3]

        # Unreachable destination (parents[dest] == 0)
        parents_disc = [0, 1, 0, 0]  # node 3,4 unreachable
        @test_throws ArgumentError tracepath(parents_disc, 1, 3)
        @test_throws ArgumentError tracepath(parents_disc, 1, 4)

        # Reachable node 2 still works
        @test tracepath(parents_disc, 1, 2) == [1, 2]
    end

    @testset "dists - edge cases" begin
        # Single point vs single point
        X1 = [0.0 0.0]
        X2 = [3.0 4.0]
        D = dists(X1, X2)
        @test D[1,1] ≈ 5.0

        # Distance to self is zero
        X = [1.0 2.0; 3.0 4.0]
        D = dists(X, X)
        @test D[1,1] ≈ 0.0
        @test D[2,2] ≈ 0.0

        # Geographic distance symmetry
        cities = [-78.64 35.78; -122.42 37.77]
        D = dists(cities, cities, :mi)
        @test D[1,2] ≈ D[2,1] atol=0.1

        # An integer p above 2 is the lp metric (N19, K5): (3³ + 4³)^(1/3) here
        @test dists(X1, X2, 3)[1,1] ≈ 91^(1 / 3)
        # Invalid integer metric
        @test_throws ErrorException dists(X1, X2, 0)

        # Invalid symbol metric
        @test_throws ErrorException dists(X1, X2, :invalid)
    end

end  # @testset "RoadTools"

# =============================================================================
# K2a: wrong-answer tests (test spec Sec. 2) and pin-today tests (Sec. 7).
# Each testset is tagged [ID]; tools/v0_3_0/run_against.jl records its outcome in
# baselines/sc2-outcomes.csv. A `@test_broken` names the component whose commit flips it to `@test`.
# =============================================================================

@testset "[N6] after thin, node IDs are 1:n in row order and a drawn path uses the named nodes' coordinates" begin
    # a path 1-2-3-4 with a branch 2-5; node 3 has degree 2 and is merged away
    dfN = DataFrame(IDX = 1:5, LON = [0.0, 1.0, 2.0, 3.0, 1.0], LAT = [0.0, 0.0, 0.0, 0.0, 1.0])
    dfL = DataFrame(SRC = [1, 2, 3, 2], DST = [2, 3, 4, 5], DIST = fill(1.0, 4))
    nodes, links = thin(dfN, dfL)
    @test nrow(nodes) == 4                                  # control: node 3 is gone
    # N6: v0.2.8 left IDX = [1, 2, 4, 5]; thin now numbers the nodes it keeps 1:n
    @test nodes.IDX == 1:nrow(nodes)
    # the path from the node at (0, 0) to the node at (3, 0), drawn through the thinned network
    i1 = nodes.IDX[findfirst(==(0.0), nodes.LON)]
    i4 = nodes.IDX[findfirst(==(3.0), nodes.LON)]
    g = links2graph(links)
    _, P = shortestpaths(g, nv(g) >= 4 ? 4 : nv(g))
    x, y = _test_rte2lines([i1, i4], P, nodes)
    # N6: v0.2.8 drew [0, 1, 1]: the row positions of the path's vertices belong to other nodes
    @test x[1:end-1] == [0.0, 1.0, 3.0]
    @test y[1:end-1] == [0.0, 0.0, 0.0]
end

@testset "[CR 17] links2graph keeps the shorter of two parallel links, honors DIR = -1, keeps a zero time" begin
    # parallel links 1-2 of 5.0 and 3.0: v0.2.8 summed them (8.0)
    g = links2graph(DataFrame(SRC = [1, 1], DST = [2, 2], DIST = [5.0, 3.0]))
    @test weights(g)[1, 2] == 3.0 && weights(g)[2, 1] == 3.0
    # DIR = -1 is a one-way link from DST to SRC
    g = links2graph(DataFrame(SRC = [1], DST = [2], DIST = [4.0], DIR = [-1]))
    @test weights(g)[2, 1] == 4.0 && weights(g)[1, 2] == 0.0
    @test has_edge(g, 2, 1) && !has_edge(g, 1, 2)
    # a zero travel time is a link, not a missing one: node 3 stays reachable at no extra time
    g = links2graph(DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [1.0, 0.0]))
    @test nv(g) == 3
    @test isapprox(Graphs.dijkstra_shortest_paths(g, 1).dists[3], 1.0)
    @test isapprox(Graphs.dijkstra_shortest_paths(g, 3).dists[1], 1.0)
    # control: a plain two-way link and a DIR = 1 one-way link
    g = links2graph(DataFrame(SRC = [1], DST = [2], DIST = [4.0], DIR = [1]))
    @test weights(g)[1, 2] == 4.0 && weights(g)[2, 1] == 0.0
    # parallel links keep the shorter in each direction separately, and a zero link beside a longer one
    g = links2graph(DataFrame(SRC = [1, 2, 1], DST = [2, 1, 2], DIST = [5.0, 3.0, 0.0], DIR = [1, 1, 1]))
    @test weights(g)[1, 2] == 0.0 && weights(g)[2, 1] == 3.0
    @test Graphs.dijkstra_shortest_paths(g, 1).dists[2] == 0.0           # the zero link is an arc
end

@testset "[CR 18] thin gives the same network whatever the node order" begin
    # a ring of six nodes at unit distance: v0.2.8's result depends on the order its queue visits the nodes
    function ringnet(perm)
        n = 6
        ang = [2pi * (i - 1) / n for i in 1:n]
        N = DataFrame(IDX = perm, LON = cos.(ang), LAT = sin.(ang))
        L = DataFrame(SRC = perm, DST = [perm[mod1(i + 1, n)] for i in 1:n], DIST = fill(1.0, n))
        return N, L
    end
    perms = [[1, 2, 3, 4, 5, 6], [6, 5, 4, 3, 2, 1], [3, 1, 6, 2, 5, 4], [2, 4, 6, 1, 3, 5],
             [5, 3, 1, 6, 4, 2], [4, 6, 2, 5, 1, 3]]
    shapes = Set{Tuple{Int,Vector{Float64}}}()
    for p in perms
        N, L = ringnet(p)
        Nt, Lt = thin(N, L)
        push!(shapes, (nrow(Nt), sort(Lt.DIST)))
    end
    # CR 18: v0.2.8 gave (3 nodes, [1, 2, 3]), (3, [2, 2, 2]) and (2, [2]) for these labelings; thin now visits the
    # nodes in the order of the rows of dfN, which these labelings leave alone
    @test length(shapes) == 1
end

@testset "[CR 25] thin on a network with one link per direction keeps both directions" begin
    # node 2 is a sink: 1 -> 2 and 3 -> 2 only; 1 <-> 3 are joined by two one-way links of 5.0
    dfN = DataFrame(IDX = [1, 2, 3], LON = [0.0, 1.0, 2.0], LAT = [0.0, 1.0, 0.0])
    dfL = DataFrame(SRC = [1, 3, 1, 3], DST = [2, 2, 3, 1], DIST = [1.0, 1.0, 5.0, 5.0], DIR = [1, 1, 1, 1])
    nodes, links = thin(dfN, dfL)
    D = shortestpaths(links2graph(links), 3)[1]
    # CR 25: v0.2.8 merged the one-way chain 3 -> 2 <- 1 as if it ran 3 -> 1 (distance 2.0, and 1 -> 3 is
    # not 5.0 where the second link was dropped); node 2 is a sink, not a pass-through, so it stays
    @test D[1, 3] == 5.0 && D[3, 1] == 5.0
    @test nrow(nodes) == 3 && nrow(links) == 4
end

@testset "[S1] pin: network functions read their columns by position (his 10/11 ruling)" begin
    # nodes and links whose columns are not called IDX/LON/LAT or SRC/DST/DIST
    dfN = DataFrame(NODE = [10, 20, 30, 40, 50], X = [-78.6, -78.5, -78.6, -78.5, -70.0],
                    Y = [35.7, 35.7, 35.8, 35.8, 40.0])
    dfL = DataFrame(A = [10, 20, 30, 10], B = [20, 40, 40, 30], MINUTES = [60.0, 45.0, 30.0, 20.0])
    n2, l2 = prune_reindex(dfN, dfL)                        # node 50 is on no link
    @test names(n2) == ["NODE", "X", "Y"]
    @test n2.NODE == 1:4
    @test sort(unique(vcat(l2.A, l2.B))) == 1:4
    g = links2graph(l2; weight = 3)                         # the third column, whatever it is called
    @test weights(g)[1, 2] == 60.0 && weights(g)[2, 1] == 60.0
    n3, l3 = addconnectors(n2, l2, [-78.55], [35.75]; add_nf_nf = false)
    @test names(n3)[1:3] == ["NODE", "X", "Y"] && names(l3)[1:3] == ["A", "B", "MINUTES"]
    @test nrow(n3) == nrow(n2) + 1 && nrow(l3) > nrow(l2)
    @test n3.NODE == 1:nrow(n3)
    t1, t2 = thin(n2, l2)                                   # reads SRC, DST, DIST and IDX by position too
    @test names(t2) == ["A", "B", "MINUTES", "MERGED"] && names(t1) == ["NODE", "X", "Y"]
end

@testset "[S1] cropnetwork reads its columns by position and takes prune_reindex's column keywords" begin
    # K8: v0.2.8's cropnetwork read r.LON, r.LAT, r.IDX, r.SRC and r.DST by name
    dfN = DataFrame(NODE = [10, 20, 30, 40, 50], X = [-78.6, -78.5, -78.6, -78.5, -70.0],
                    Y = [35.7, 35.7, 35.8, 35.8, 40.0])
    dfL = DataFrame(A = [10, 20, 30, 10, 40], B = [20, 40, 40, 30, 50], MINUTES = [60.0, 45.0, 30.0, 20.0, 5.0])
    cn, cl = cropnetwork(dfN, dfL, [-78.6, -78.5], [35.7, 35.8]; xexpand = 0.1, yexpand = 0.1)
    @test names(cn) == ["NODE", "X", "Y"] && names(cl) == ["A", "B", "MINUTES"]
    @test cn.NODE == 1:4                                     # node 50 is outside the box
    @test nrow(cl) == 4 && sort(cl.MINUTES) == [20.0, 30.0, 45.0, 60.0]
    # the same table with its columns in another order, named
    dfN2 = select(dfN, :Y, :NODE, :X)
    dfL2 = select(dfL, :MINUTES, :B, :A)
    cn2, cl2 = cropnetwork(dfN2, dfL2, [-78.6, -78.5], [35.7, 35.8]; xexpand = 0.1, yexpand = 0.1,
                           src_col = :A, dst_col = :B, node_col = :NODE, x_col = :X, y_col = :Y)
    @test cn2.NODE == 1:4 && nrow(cl2) == 4
    @test sort(Matrix(cl2[:, [:A, :B]]); dims = 1) == sort(Matrix(cl[:, [:A, :B]]); dims = 1)
    # a view is accepted
    cn3, cl3 = cropnetwork(view(dfN, :, :), view(dfL, :, :), [-78.6, -78.5], [35.7, 35.8])
    @test nrow(cn3) == 4 && nrow(cl3) == 4
end

@testset "[N16] addconnectors adds no new-node to new-node connectors unless asked (D8)" begin
    # (a fifth node off the center: four nodes on a square lie on one circle, and a point in the square can
    # then be joined to either diagonal's triangles, one choice from one call to the next)
    dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.0, -79.0, -79.0, -78.5], LAT = [35.0, 36.0, 35.0, 36.0, 35.6])
    dfL = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0], DIR = [0, 1, 0])
    x′, y′ = [-78.2, -78.8, -78.5], [35.2, 35.8, 35.5]
    # v0.2.8 defaulted to add_nf_nf = true (4.1 Code block 40 passes it explicitly now)
    _, L0 = addconnectors(dfN, dfL, x′, y′)
    _, Loff = addconnectors(dfN, dfL, x′, y′; add_nf_nf = false)
    _, Lon = addconnectors(dfN, dfL, x′, y′; add_nf_nf = true)
    @test isequal(L0, Loff)
    @test count(r -> r.SRC <= 3 && r.DST <= 3, eachrow(L0)) == 0
    @test count(r -> r.SRC <= 3 && r.DST <= 3, eachrow(Lon)) == 3
    @test nrow(Lon) == nrow(Loff) + 3
    # the road links are the same either way
    @test count(r -> r.SRC > 3 && r.DST > 3, eachrow(L0)) == nrow(dfL)
end

@testset "[S16] addconnectors' SOURCE column is present, marks the connectors and only them" begin
    # (a fifth node off the center: four nodes on a square lie on one circle, and a point in the square can
    # then be joined to either diagonal's triangles, one choice from one call to the next)
    dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.0, -79.0, -79.0, -78.5], LAT = [35.0, 36.0, 35.0, 36.0, 35.6])
    dfL = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0])
    x′, y′ = [-78.2, -78.8], [35.2, 35.8]
    for nf in (false, true)
        N2, L2 = addconnectors(dfN, dfL, x′, y′; add_nf_nf = nf)
        @test "SOURCE" in names(L2)
        con = isequal.(L2.SOURCE, "CONNECTOR")
        @test count(con) == nrow(L2) - nrow(dfL)
        @test all(ismissing, L2.SOURCE[.!con]) && all(L2.SOURCE[con] .== "CONNECTOR")
        # a connector has a new node (1 or 2) at one end, and the road links are the ones with no new node
        @test all(r -> r.SRC <= 2 || r.DST <= 2, eachrow(L2[con, :]))
        @test all(r -> r.SRC > 2 && r.DST > 2, eachrow(L2[.!con, :]))
    end
    # a table that already has a SOURCE column keeps it
    withsrc = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0], SOURCE = ["FAF5", "FAF5", "FAF5"])
    _, L3 = addconnectors(dfN, withsrc, x′, y′)
    @test all(L3.SOURCE[1:3] .== "FAF5") && all(L3.SOURCE[4:end] .== "CONNECTOR")
end

@testset "[S2] addconnectors' speed fills the connectors' SPEED, and the default call is unchanged (R4)" begin
    # (a fifth node off the center: four nodes on a square lie on one circle, and a point in the square can
    # then be joined to either diagonal's triangles, one choice from one call to the next)
    dfN = DataFrame(IDX = 1:5, LON = [-78.0, -78.0, -79.0, -79.0, -78.5], LAT = [35.0, 36.0, 35.0, 36.0, 35.6])
    withspeed = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0], SPEED = [55, 60, 50])
    x′, y′ = [-78.2, -78.8], [35.2, 35.8]
    # the default call: a connector's SPEED is missing, as before
    _, L0 = addconnectors(dfN, withspeed, x′, y′)
    @test all(ismissing, L0.SPEED[4:end]) && L0.SPEED[1:3] == [55, 60, 50]
    # speed = 20 (Lecture 4.2's connector speed): the connectors carry it, the road links keep theirs
    _, L1 = addconnectors(dfN, withspeed, x′, y′; speed = 20)
    con = isequal.(L1.SOURCE, "CONNECTOR")
    @test all(L1.SPEED[con] .== 20) && L1.SPEED[.!con] == [55, 60, 50]
    @test eltype(L1.SPEED) == Int
    @test isequal(select(L1, Not(:SPEED)), select(L0, Not(:SPEED)))          # nothing else changes
    # a table with no SPEED column gets one: missing on the road links
    nospeed = DataFrame(SRC = [1, 2, 1], DST = [2, 4, 3], DIST = [69.0, 69.0, 54.0])
    _, L2 = addconnectors(dfN, nospeed, x′, y′; speed = 20)
    c2 = isequal.(L2.SOURCE, "CONNECTOR")
    @test all(L2.SPEED[c2] .== 20) && all(ismissing, L2.SPEED[.!c2])
    _, L2b = addconnectors(dfN, nospeed, x′, y′)
    @test !("SPEED" in names(L2b))                                           # no speed, no column
    # a real speed is wanted
    @test_throws ArgumentError addconnectors(dfN, withspeed, x′, y′; speed = 0)
    @test_throws ArgumentError addconnectors(dfN, withspeed, x′, y′; speed = "fast")
    # a fractional speed is allowed; the column then holds Float64
    _, L3 = addconnectors(dfN, withspeed, x′, y′; speed = 17.5)
    @test all(L3.SPEED[isequal.(L3.SOURCE, "CONNECTOR")] .== 17.5)
end

# ==== moved from test/test_connector_search.jl, its lines 1-108 ====
# test_connector_search.jl -- addconnectors' exact local point location (PCV K8: C1, CR 62, CR 27).
# Each new point's connectors are the corners of the triangle of the whole network's Delaunay triangulation
# that holds it, found from the triangulation of its 16 nearest nodes (doubled as needed) and accepted only
# when the triangle's circumcircle holds no other node. The properties below compare it with the
# triangulation of the whole network, on seeded random nodes and on the crops the course makes.

using Test
using Logjam
using DataFrames
using Random
import DelaunayTriangulation as DT

# the connectors by the whole network's triangulation (v0.2.8's method)
function _whole_nodes(x, y, qs)
    tri = DT.triangulate(collect(zip(x, y)))
    return [sort!(filter(v -> v > 0, collect(DT.brute_force_search(tri, q)))) for q in qs]
end
# the connectors by the local point location
_local_nodes(x, y, qs) = (S = Logjam._ConnectorSearch(collect(Float64, x), collect(Float64, y));
                          [Logjam._connector_nodes(S, (Float64(q[1]), Float64(q[2]))) for q in qs])

@testset "addconnectors: exact local point location (CR 62, CR 27, C1)" begin
    @testset "equals the whole triangulation on seeded random nodes, inside the hull and out" begin
        for (seed, n, m) in ((1, 20, 60), (2, 200, 200), (3, 3000, 300), (4, 5000, 100))
            rng = MersenneTwister(seed)
            x, y = rand(rng, n), rand(rng, n)
            qs = [(1.2 * rand(rng) - 0.1, 1.2 * rand(rng) - 0.1) for _ in 1:m]   # some outside the hull
            @test _local_nodes(x, y, qs) == _whole_nodes(x, y, qs)
        end
    end

    @testset "equals the whole triangulation on the crops of Lectures 4.1 and 5.1" begin
        N, L = prune_reindex(faf5nodes(), faf5links())
        cities = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())     # 4.1 Code block 47
        counties = filter(r -> r.STFIP == st2fips(:NC), uscounty())                          # 5.1 Code block 35
        for df in (cities, counties)
            Nc, _ = cropnetwork(N, L, df.LON, df.LAT)
            qs = collect(zip(df.LON, df.LAT))
            @test _local_nodes(Nc.LON, Nc.LAT, qs) == _whole_nodes(Nc.LON, Nc.LAT, qs)
        end
    end

    @testset "a network of fewer than 16 nodes, and a point outside it (4.1 Code block 40)" begin
        x = [0.0, 1.0, 0.0, 1.0, 0.5]
        y = [0.0, 0.0, 1.0, 1.0, 0.45]
        qs = [(0.5, 0.2), (0.2, 0.5), (0.5, 0.8), (0.8, 0.5), (2.0, 0.5)]
        @test _local_nodes(x, y, qs) == _whole_nodes(x, y, qs)
        @test all(length.(_local_nodes(x, y, qs[1:4])) .== 3)                # a triangle's three corners
        @test length(_local_nodes(x, y, qs[5:5])[1]) == 2                    # the two nodes of the hull edge
    end

    @testset "a lattice, where circles are shared by four nodes: the triangle holds the point and its circle is empty" begin
        gx = [float(i) for i in 0:19 for j in 0:19]
        gy = [float(j) for i in 0:19 for j in 0:19]
        rng = MersenneTwister(5)
        qs = [(19 * rand(rng), 19 * rand(rng)) for _ in 1:80]
        kernel = DT.AdaptiveKernel()
        for (q, t) in zip(qs, _local_nodes(gx, gy, qs))
            @test length(t) == 3
            a, b, c = ((gx[i], gy[i]) for i in t)
            # the corners are counterclockwise or clockwise in index order, so test either way round
            sgn = DT.is_positively_oriented(DT.triangle_orientation(kernel, a, b, c)) ? 1 : -1
            for (u, v) in ((a, b), (b, c), (c, a))
                o = DT.triangle_orientation(kernel, u, v, q)
                @test sgn == 1 ? !DT.is_negatively_oriented(o) : !DT.is_positively_oriented(o)
            end
            p, r, s = sgn == 1 ? (a, b, c) : (a, c, b)
            @test !any(m -> m != a && m != b && m != c &&
                            DT.is_inside(DT.point_position_relative_to_circle(kernel, p, r, s, (gx[m], gy[m]))),
                       eachindex(gx))
        end
    end

    @testset "cocircular nodes: one answer on every run, and the caller's random stream is not advanced (build record K9 to K10)" begin
        # a 2 by 5 lattice (every unit square has four nodes on a circle) and a 6 by 6 one (past the 16 nearest nodes'
        # first pass); which diagonal a point's triangle takes used to depend on the global stream
        for (nx, ny, qx, qy) in ((5, 2, [0.3, 1.3, 2.3, 3.3], fill(0.6, 4)),
                                 (6, 6, [0.5, 1.5, 2.5, 3.5, 4.5], [0.5, 1.5, 2.5, 3.5, 4.5]))
            x = Float64[i for j in 0:ny-1 for i in 0:nx-1]
            y = Float64[j for j in 0:ny-1 for i in 0:nx-1]
            N = DataFrame(IDX = 1:length(x), LON = x, LAT = y)
            L = DataFrame(SRC = [1], DST = [2], DIST = [1.0])
            conn(Lc) = [(r.SRC, r.DST) for r in eachrow(Lc[isequal.(Lc.SOURCE, "CONNECTOR"), :])]
            answers = Set(conn(addconnectors(N, L, qx, qy)[2]) for _ in 1:40)
            @test length(answers) == 1
            # draw, call, draw equals draw, draw
            Random.seed!(7)
            a = rand(2)
            Random.seed!(7)
            b1 = rand()
            addconnectors(N, L, qx, qy; add_nf_nf = true)
            b2 = rand()
            @test a == [b1, b2]
        end
    end

    @testset "addconnectors takes a view, and gives the same links as the vectors" begin
        N = DataFrame(IDX = 1:5, LON = [0.0, 1.0, 0.0, 1.0, 0.5], LAT = [0.0, 0.0, 1.0, 1.0, 0.45])
        L = DataFrame(SRC = [1, 2, 3], DST = [2, 4, 4], DIST = [69.0, 69.0, 69.0])
        px, py = [0.5, 0.2, 0.7], [0.2, 0.5, 0.8]
        N1, L1 = addconnectors(N, L, px, py; add_nf_nf = false)
        N2, L2 = addconnectors(N, L, view(px, :), view(py, :); add_nf_nf = false)
        @test isequal(N1, N2) && isequal(L1, L2)
        bigx, bigy = [9.0; px; 9.0], [9.0; py; 9.0]
        N3, L3 = addconnectors(N, L, view(bigx, 2:4), view(bigy, 2:4); add_nf_nf = false)
        @test isequal(N1, N3) && isequal(L1, L3)
    end
end

# ==== moved from test/test_links2graph.jl, its lines 1-134 ====
# test_links2graph.jl -- links2graph is the graph the lectures build by hand (PCV K8: CR 17, NW/C2, S17).
# Lecture 4.1's Code block 45 (annotation 2) teaches the two rules: each link gives an arc in each direction it
# can be traveled, and of parallel arcs the shorter is kept (`combine = min`); a link of zero length stays an
# arc. Lectures 4.1, 4.2, 5.1 and 5.3 build the graph, by distance and by time, from the arc list. The
# equality tests below build each by the lecture's own lines and require the same arcs and the same weights,
# bit for bit.

using Test
using Logjam
using DataFrames
using Graphs
using SimpleWeightedGraphs
using SparseArrays

# the lectures' inputs and their hand-built graphs (test/road_pin_cases.jl), loaded once
isdefined(Main, :rdpin_cases) || include(joinpath(@__DIR__, "road_pin_helpers.jl"))

# the same arcs, and the same weights to the last bit
function _identical(g, h)
    gw, hw = g.weights, h.weights
    return nv(g) == nv(h) && ne(g) == ne(h) && gw.colptr == hw.colptr && gw.rowval == hw.rowval &&
           reinterpret(UInt64, gw.nzval) == reinterpret(UInt64, hw.nzval)
end

@testset "[S17] links2graph equals the graph the lectures build by hand, by distance and by time (CR 17, C2)" begin
    N, L = _rd_faf()                                           # 4.1 Code block 43

    @testset "by distance: Wake County's two points (4.1 Code block 45)" begin
        NW, LW = prune_reindex(N, filter(r -> r.STFIP == 37 && r.COFIP == 37183, L))
        XY2 = [-78.75864529722959 35.74329140697632; -78.70352644371913 35.866083946889844]
        NW2, LW2 = addconnectors(NW, LW, XY2[:, 1], XY2[:, 2]; add_nf_nf = false)
        gh = _rd_graph(LW2, LW2.DIST)
        g = links2graph(LW2)
        @test _identical(g, gh)
        @test shortestpaths(g, 2)[1] == shortestpaths(gh, 2)[1]
    end

    @testset "by distance and by time: the ten cities of 4.1 Code blocks 48 and 51" begin
        df = _rd_cities()
        Nc, Lc = cropnetwork(N, L, df.LON, df.LAT)
        Nc, Lc = addconnectors(Nc, Lc, df.LON, df.LAT; add_nf_nf = false, speed = 20)
        @test _identical(links2graph(Lc), _rd_graph(Lc, Lc.DIST))
        tAB, tBA = _rd_times(Lc)
        gt = links2graph(Lc; weight = :time)
        @test _identical(gt, _rd_graph(Lc, tAB, tBA))
        # the (forward, backward) pair of columns is the same graph where every time is positive
        @test _identical(links2graph(Lc; weight = (tAB, tBA)), gt)
    end

    @testset "by distance and by time: the 100 NC county points of 5.1 Code block 35 and 5.3 Code block 64" begin
        dfc = _rd_counties()
        Nc, Lc = cropnetwork(N, L, dfc.LON, dfc.LAT)
        Nc, Lc = addconnectors(Nc, Lc, dfc.LON, dfc.LAT; add_nf_nf = false, speed = 20)
        @test _identical(links2graph(Lc), _rd_graph(Lc, Lc.DIST))
        tAB, tBA = _rd_times(Lc)
        @test _identical(links2graph(Lc; weight = :time), _rd_graph(Lc, tAB, tBA))
    end

    @testset "4.2's form on the OSM fixture: one link per direction, no time columns, a connector at 20 mph" begin
        dfN, dfL = _rd_osm()
        x = [minimum(dfN.LON) + 0.4 * (maximum(dfN.LON) - minimum(dfN.LON)),
             minimum(dfN.LON) + 0.7 * (maximum(dfN.LON) - minimum(dfN.LON))]
        y = [minimum(dfN.LAT) + 0.7 * (maximum(dfN.LAT) - minimum(dfN.LAT)),
             minimum(dfN.LAT) + 0.45 * (maximum(dfN.LAT) - minimum(dfN.LAT))]
        Nc, Lc = addconnectors(dfN, dfL, x, y; add_nf_nf = false, speed = 20)
        con = _rd_isconn(Lc)
        tmin = [c ? 60d / 20 : 60d / v for (c, d, v) in zip(con, Lc.DIST, Lc.SPEED)]      # 4.2 Code block 6
        @test _identical(links2graph(Lc), _rd_graph(Lc, Lc.DIST))
        @test _identical(links2graph(Lc; weight = :time), _rd_graph(Lc, tmin))
        @test all(Lc.SPEED[con] .== 20)
    end
end

@testset "links2graph: weight forms" begin
    L = DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [30.0, 10.0], MINUTES = [31.0, 12.0],
                  AB_TIME = [28.0, 0.0], BA_TIME = [33.0, 0.0], SPEED = [60, 20], DIR = [0, 0])
    @test weights(links2graph(L))[1, 2] == 30.0                                  # the third column
    @test weights(links2graph(L; weight = :MINUTES))[2, 3] == 12.0               # a column by name
    @test weights(links2graph(L; weight = 4))[1, 2] == 31.0                      # a column by position
    g = links2graph(L; weight = (:AB_TIME, :BA_TIME))                            # FAF5's pair
    @test weights(g)[1, 2] == 28.0 && weights(g)[2, 1] == 33.0
    g = links2graph(L; weight = ([1.0, 2.0], [3.0, 4.0]))                        # a pair of vectors
    @test weights(g)[1, 2] == 1.0 && weights(g)[2, 1] == 3.0 && weights(g)[2, 3] == 2.0 && weights(g)[3, 2] == 4.0
    g = links2graph(L; weight = [7.0, 8.0])                                      # a vector
    @test weights(g)[1, 2] == 7.0 && weights(g)[3, 2] == 8.0
    g = links2graph(L; weight = :time)                                           # 4.1's rule, in minutes
    @test weights(g)[1, 2] == 28.0 && weights(g)[2, 1] == 33.0                   # FAF5's free-flow times
    @test weights(g)[2, 3] == 60 * 10.0 / 20 && weights(g)[3, 2] == 60 * 10.0 / 20   # 60 d / v where a time is 0
    # the time rule needs a positive time or a speed, in each direction a link is traveled
    miss = DataFrame(SRC = [1], DST = [2], DIST = [3.0], SPEED = [missing], AB_TIME = [missing], BA_TIME = [missing])
    @test_throws ArgumentError links2graph(miss; weight = :time)
    err = try links2graph(miss; weight = :time) catch e; e end
    @test occursin("speed", sprint(showerror, err)) && occursin("addconnectors", sprint(showerror, err))
    # a link traveled one way needs the time of that way only
    one = DataFrame(SRC = [1], DST = [2], DIST = [3.0], SPEED = [60], AB_TIME = [0.0], BA_TIME = [0.0], DIR = [1])
    @test weights(links2graph(one; weight = :time))[1, 2] == 60 * 3.0 / 60
    # a network with no time columns has 60 d / v throughout
    osm = DataFrame(SRC = [1, 2], DST = [2, 1], DIST = [0.5, 0.5], SPEED = [30, 15], DIR = [1, 1])
    g = links2graph(osm; weight = :time)
    @test weights(g)[1, 2] == 60 * 0.5 / 30 && weights(g)[2, 1] == 60 * 0.5 / 15
    # a column by name that is not there, a bad pair, a bad DIR
    @test_throws ArgumentError links2graph(L; weight = :NOPE)
    @test_throws ArgumentError links2graph(L; weight = (:DIST, :DIST, :DIST))
    @test_throws ArgumentError links2graph(L; weight = [1.0])
    @test_throws ArgumentError links2graph(DataFrame(SRC = [1], DST = [2], DIST = [1.0], DIR = [2]))
    @test_throws ArgumentError links2graph(DataFrame(SRC = [1], DST = [2], DIST = [-1.0]))
    @test_throws ArgumentError links2graph(DataFrame(SRC = [1], DST = [2], DIST = [missing]))
end

@testset "links2graph: node IDs are 1:n and never renumbered; the removed options are gone" begin
    # IDs with a gap (node 2 is on no link) are refused, with the fix named
    sparse_ids = DataFrame(SRC = [1, 3], DST = [3, 4], DIST = [1.0, 2.0])
    err = try links2graph(sparse_ids) catch e; e end
    @test err isa ArgumentError && occursin("prune_reindex", sprint(showerror, err))
    @test_throws ArgumentError links2graph(DataFrame(SRC = [0, 1], DST = [1, 2], DIST = [1.0, 1.0]))
    @test_throws ArgumentError links2graph(DataFrame(SRC = ["a"], DST = ["b"], DIST = [1.0]))
    # after prune_reindex the same links are a graph on 1:n
    n, l = prune_reindex(DataFrame(IDX = [1, 3, 4], LON = [0.0, 1.0, 2.0], LAT = [0.0, 0.0, 0.0]), sparse_ids)
    @test nv(links2graph(l)) == 3
    # source and destination are columns 1 and 2, or named
    swapped = DataFrame(DIST = [1.0, 2.0], B = [2, 3], A = [1, 2])
    g = links2graph(swapped; src_col = :A, dst_col = :B, weight = 1)
    @test weights(g)[1, 2] == 1.0 && weights(g)[3, 2] == 2.0
    # the nine options of v0.2.8 are removed
    L = DataFrame(SRC = [1], DST = [2], DIST = [1.0])
    for kw in (:reindex, :return_map, :sparse_ratio, :max_id_threshold, :oneway_val, :dir_col, :ab_weight, :ba_weight)
        @test_throws MethodError links2graph(L; (kw => 1,)...)
    end
    # a SimpleWeightedDiGraph comes back, and shortestpaths needs nothing more
    g = links2graph(DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [1.0, 2.0]))
    @test g isa SimpleWeightedGraphs.SimpleWeightedDiGraph
    D, P = shortestpaths(g, 3)
    @test D[1, 3] == 3.0 && tracepath(P[1], 1, 3) == [1, 2, 3]
end

# ==== moved from test/test_thin.jl, its lines 1-172 ====
# test_thin.jl -- thin on typed arcs: direction-aware, independent of the node labels, node IDs 1:n
# (PCV K8: CR 18, CR 25, N6, C9). The degree-2 nodes of a road network are removed, the two arcs at each
# replaced by one of their summed cost, the shorter kept where that leaves parallel arcs (Matlog's `thin`).

using Test
using Logjam
using DataFrames
using Graphs
using SimpleWeightedGraphs
using Random
using CSV

@testset "thin: typed arcs, direction-aware, label-independent" begin
    @testset "a chain thins to one link, with the merge index as a column" begin
        dfN = DataFrame(IDX = 1:4, LON = [-78.0, -79.0, -80.0, -81.0], LAT = fill(35.0, 4))
        dfL = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [10.0, 15.0, 12.0], FCLASS = [1, 2, 3])
        N, L = thin(dfN, dfL)
        @test N isa DataFrame && L isa DataFrame
        @test nrow(L) == 1 && nrow(N) == 2
        @test N.IDX == [1, 2] && N.LON == [-78.0, -81.0]            # the nodes that remain, numbered 1:n
        @test (L.SRC[1], L.DST[1]) == (1, 2) && L.DIST[1] == 37.0
        @test L.MERGED == [[1, 2, 3]]                                # the rows of dfL, in order along the road
        @test L.FCLASS == [1]                                        # another column is the first link's
        @test names(L) == [names(dfL); "MERGED"]
        @test dfL.DIST == [10.0, 15.0, 12.0] && ncol(dfL) == 4        # the input is untouched
        # Lecture 4.1's Code block 32 integer costs stay integers
        _, L0 = thin(dfN, DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [10, 15, 12]))
        @test L0.DIST == [37] && eltype(L0.DIST) == Int
    end

    @testset "a triangle makes no self-loop, and the shorter parallel arc is kept" begin
        dfN = DataFrame(IDX = 1:3, LON = [-78.0, -79.0, -78.5], LAT = [35.0, 35.0, 35.5])
        dfL = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 1], DIST = [10.0, 10.0, 10.0])
        N, L = thin(dfN, dfL)
        @test all(L.SRC .!= L.DST)
        @test nrow(N) == 2 && nrow(L) == 1 && L.DIST == [10.0]
        # a longer way round does not replace a shorter direct link: node 1 goes first (the first row), and the
        # link 2-3 of 4.0 beats the 4.0 + 5.0 around through node 1
        dfL2 = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 1], DIST = [4.0, 4.0, 5.0])
        N2, L2 = thin(dfN, dfL2)
        @test nrow(L2) == 1 && L2.DIST == [4.0] && L2.MERGED == [[2]]
        @test (N2.LON, N2.LAT) == ([-79.0, -78.5], [35.0, 35.5])         # nodes 2 and 3 remain, numbered 1 and 2
    end

    @testset "the keywords of v0.2.8 are gone, and the return is always (N, L)" begin
        dfN = DataFrame(IDX = 1:3, LON = [0.0, 1.0, 2.0], LAT = [0.0, 0.0, 0.0])
        dfL = DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [1.0, 1.0])
        for kw in (:agg, :must_match, :keep_index, :verbose)
            @test_throws MethodError thin(dfN, dfL; (kw => nothing,)...)
        end
        r = thin(dfN, dfL)
        @test r isa Tuple && length(r) == 2
        @test thin(view(dfN, :, :), view(dfL, :, :)) isa Tuple          # views are accepted
    end

    @testset "one-way chains are merged one-way, two-way chains two-way, mixed nodes are kept" begin
        # a -> v -> b, one-way: v goes, the link a -> b is one-way
        dfN = DataFrame(IDX = 1:4, LON = 0.0:3.0, LAT = zeros(4))
        L1 = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 2.0, 3.0], DIR = [1, 1, 1])
        N1, M1 = thin(dfN, L1)
        @test nrow(M1) == 1 && (M1.SRC[1], M1.DST[1], M1.DIST[1], M1.DIR[1]) == (1, 2, 6.0, 1)
        # the same chain traveled the other way (DIR = -1): the link keeps its orientation and DIR -1
        L2 = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 2.0, 3.0], DIR = [-1, -1, -1])
        _, M2 = thin(dfN, L2)
        @test nrow(M2) == 1 && M2.DIR[1] == 1 && (M2.SRC[1], M2.DST[1]) == (2, 1)   # 4 -> 1 is the arc, now new nodes 2 -> 1
        # two-way links (DIR 0) merge to a two-way link
        L3 = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 2.0, 3.0], DIR = [0, 0, 0])
        _, M3 = thin(dfN, L3)
        @test nrow(M3) == 1 && M3.DIR == [0] && M3.DIST == [6.0] && (M3.SRC[1], M3.DST[1]) == (1, 2)
        # a node that is two-way to one neighbor and one-way to the other is not a pass-through: it stays
        L4 = DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [1.0, 1.0], DIR = [0, 1])
        N4, M4 = thin(DataFrame(IDX = 1:3, LON = 0.0:2.0, LAT = zeros(3)), L4)
        @test nrow(M4) == 2 && nrow(N4) == 3
        # a one-way sink (two links into a node) stays too
        L5 = DataFrame(SRC = [1, 3], DST = [2, 2], DIST = [1.0, 1.0], DIR = [1, 1])
        N5, M5 = thin(DataFrame(IDX = 1:3, LON = 0.0:2.0, LAT = zeros(3)), L5)
        @test nrow(M5) == 2 && nrow(N5) == 3
    end

    @testset "OpenStreetMap's form, a link per direction, thins each direction apart (CR 25)" begin
        dfN = DataFrame(IDX = 1:4, LON = 0.0:3.0, LAT = zeros(4))
        dfL = DataFrame(SRC = [1, 2, 3, 4, 3, 2], DST = [2, 3, 4, 3, 2, 1],
                        DIST = [1.0, 2.0, 3.0, 3.5, 2.5, 1.5], DIR = fill(1, 6))
        N, L = thin(dfN, dfL)
        @test nrow(N) == 2 && nrow(L) == 2
        @test sort(L.DIST) == [6.0, 7.5] && all(L.DIR .== 1)             # 1 -> 4 by 6.0 and 4 -> 1 by 7.5
        @test Set(zip(L.SRC, L.DST)) == Set([(1, 2), (2, 1)])
        @test sort(sort.(L.MERGED)) == [[1, 2, 3], [4, 5, 6]]
        # a two-way street in one direction only elsewhere on the network
        dfL2 = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 2.0, 3.0], DIR = [1, 1, 1])
        N2, L2 = thin(dfN, dfL2)
        @test nrow(L2) == 1 && L2.DIR == [1]
    end

    @testset "node IDs: any integers in, 1:n out; a bad table is refused" begin
        dfN = DataFrame(IDX = [10, 20, 30, 40], LON = 0.0:3.0, LAT = zeros(4))
        dfL = DataFrame(SRC = [10, 20, 30], DST = [20, 30, 40], DIST = [1.0, 1.0, 1.0])
        N, L = thin(dfN, dfL)
        @test N.IDX == 1:2 && sort([L.SRC[1], L.DST[1]]) == [1, 2]
        @test_throws ArgumentError thin(DataFrame(IDX = [1, 1, 2], LON = 0.0:2.0, LAT = zeros(3)),
                                       DataFrame(SRC = [1], DST = [2], DIST = [1.0]))      # an ID twice
        @test_throws ArgumentError thin(dfN, DataFrame(SRC = [10], DST = [99], DIST = [1.0]))  # an unknown node
        @test_throws ArgumentError thin(DataFrame(IDX = ["a", "b"], LON = 0.0:1.0, LAT = zeros(2)),
                                       DataFrame(SRC = ["a"], DST = ["b"], DIST = [1.0]))   # IDs that are not integers
        @test_throws ArgumentError thin(dfN[:, 1:2], dfL)
        @test_throws ArgumentError thin(dfN, dfL[:, 1:2])
    end

    @testset "a thinned network keeps the distances between its nodes, on seeded random networks" begin
        for seed in 1:6
            rng = MersenneTwister(seed)
            n = 60
            N = DataFrame(IDX = 1:n, LON = rand(rng, n), LAT = rand(rng, n))
            m = 90
            src = rand(rng, 1:n, m)
            dst = [mod1(a + rand(rng, 1:4), n) for a in src]                  # short hops: many degree-2 nodes
            dir = rand(rng, [0, 0, 0, 1, -1], m)
            L = DataFrame(SRC = src, DST = dst, DIST = round.(10 .* rand(rng, m); digits = 2), DIR = dir)
            L = L[L.SRC .!= L.DST, :]
            # the nodes on a link, in the graph's own numbering: prune_reindex first
            N0, L0 = prune_reindex(N, L)
            Nt, Lt = thin(N0, L0)
            @test Nt.IDX == 1:nrow(Nt)
            g0 = links2graph(L0)
            gt = links2graph(Lt)
            # a kept node is identified by its coordinates (random, so unique)
            where0 = Dict(zip(zip(N0.LON, N0.LAT), N0.IDX))
            kept = [where0[(lo, la)] for (lo, la) in zip(Nt.LON, Nt.LAT)]
            D0 = [Graphs.dijkstra_shortest_paths(g0, k).dists[kept] for k in kept]
            Dt = [Graphs.dijkstra_shortest_paths(gt, i).dists for i in 1:nrow(Nt)]
            @test all(isapprox.(reduce(hcat, D0), reduce(hcat, Dt); atol = 1e-9))
            # no node of the result is a pass-through, so it is thinned as far as it goes
            @test nrow(Nt) <= nrow(N0)
            Nt2, Lt2 = thin(Nt, Lt)
            @test nrow(Nt2) == nrow(Nt) && sort(Lt2.DIST) == sort(Lt.DIST)
        end
    end

    @testset "the result does not depend on how the nodes are labeled (CR 18)" begin
        for seed in 1:4
            rng = MersenneTwister(100 + seed)
            n = 40
            N = DataFrame(IDX = 1:n, LON = rand(rng, n), LAT = rand(rng, n))
            m = 70
            src = rand(rng, 1:n, m)
            dst = [mod1(a + rand(rng, 1:3), n) for a in src]
            L = DataFrame(SRC = src, DST = dst, DIST = round.(10 .* rand(rng, m); digits = 2),
                          DIR = rand(rng, [0, 0, 1, -1], m))
            L = L[L.SRC .!= L.DST, :]
            ref = nothing
            for _ in 1:4
                perm = randperm(rng, n)                                     # node k is labeled perm[k]
                Np = DataFrame(IDX = perm, LON = N.LON, LAT = N.LAT)
                Lp = DataFrame(SRC = perm[L.SRC], DST = perm[L.DST], DIST = L.DIST, DIR = L.DIR)
                Nt, Lt = thin(Np, Lp)
                shape = (Nt.LON, Nt.LAT, sort(collect(zip(Lt.DIST, Lt.DIR))))
                ref === nothing ? (ref = shape) : @test shape == ref
            end
        end
    end

    @testset "Lecture 4.1's Interstates around Raleigh (a committed cut of the lecture's data)" begin
        dfN = DataFrame(CSV.File(joinpath(@__DIR__, "data", "interstate_raleigh_nodes.csv")))
        dfL = DataFrame(CSV.File(joinpath(@__DIR__, "data", "interstate_raleigh_links.csv")))
        N, L = thin(dfN, dfL)                                              # Code block 35: IDs in the whole network
        @test N.IDX == 1:nrow(N) && maximum(L.SRC) <= nrow(N) && maximum(L.DST) <= nrow(N)
        @test sum(L.DIST) ≈ sum(dfL.DIST) atol = 1e-9                      # the miles are the same road
        @test (nrow(N), nrow(L)) == (11, 12)
        @test sum(length, L.MERGED) == nrow(dfL)                           # every original link is in one
        @test sort(vcat(L.MERGED...)) == 1:nrow(dfL)
    end
end

# ==== moved from test/test_pathroads.jl, its lines 1-121 ====
# test_pathroads.jl -- pathroads, the roads along a path (PCV K8: CR 30). It is Lecture 4.2's `streets`
# (4-net-2.qmd, Code block 8), made to work on FAF5 and OpenStreetMap links alike: a numbered row for each run
# of one road name, with the steps it covers.

using Test
using Logjam
using DataFrames
using Graphs
using SimpleWeightedGraphs

isdefined(Main, :rdpin_cases) || include(joinpath(@__DIR__, "road_pin_helpers.jl"))

# Lecture 4.2, Code block 8, verbatim
function _streets42(p, L)
    k = Dict(zip(zip(L.SRC, L.DST), 1:nrow(L)))   # link of (SRC, DST)
    lk(u, v) = get(k, (u, v), get(k, (v, u), 0))  # either direction
    nm = [L.NAME[lk(u, v)] for (u, v) in zip(p, p[2:end])]
    t = findall(!ismissing, nm)                   # the steps with a name
    a = [i for i in eachindex(t) if i == 1 || nm[t[i]] != nm[t[i-1]]]
    b = [a[2:end] .- 1; length(t)]                # each run's first, last
    return DataFrame(Seg = eachindex(a), Street = nm[t[a]],
                     Steps = string.(t[a], "-", t[b]))
end
_same_roads(a, b) = a.Seg == b.Seg && a.Street == b.Street && a.Steps == b.Steps

@testset "pathroads: the roads along a path (CR 30)" begin
    @testset "equals Lecture 4.2's streets on 4.2's own form, by distance and by time" begin
        dfN, dfL = _rd_osm()
        lo, hi = extrema(dfN.LON); la, ha = extrema(dfN.LAT)
        npaths = 0
        for (fx, fy) in (([0.3, 0.7], [0.7, 0.45]), ([0.15, 0.85], [0.25, 0.75]), ([0.5, 0.2], [0.8, 0.3]),
                         ([0.9, 0.1], [0.5, 0.5]))
            x = lo .+ fx .* (hi - lo)
            y = la .+ fy .* (ha - la)
            Nc, Lc = addconnectors(dfN, dfL, x, y; add_nf_nf = false, speed = 20)
            for w in (:DIST, :time)
                g = links2graph(Lc; weight = w)
                for (i, j) in ((1, 2), (2, 1))
                    ds = Graphs.dijkstra_shortest_paths(g, i)
                    isfinite(ds.dists[j]) || continue
                    p = tracepath(ds.parents, i, j)
                    # two points joined to the same street nodes have a path of connectors only: no street to
                    # name, and Lecture 4.2's code has no answer there (it indexes an empty list). Where the
                    # fixture's lattice has four nodes on a circle, the triangle a point joins is a choice between
                    # two diagonals: addconnectors makes it the same on every run (K10, its triangulations take a
                    # generator of their own), but the shuffle that generator drives can differ from one Julia to
                    # the next, so which pair has no street is not asserted and the count of the others is a floor
                    nrow(pathroads(p, Lc)) == 0 && continue
                    @test _same_roads(_streets42(p, Lc), pathroads(p, Lc))
                    npaths += 1
                end
            end
        end
        @test npaths >= 8
    end

    @testset "a path along two roads, connectors at the ends passed over; Steps and Miles" begin
        L = DataFrame(SRC = [1, 2, 3, 4, 5, 6], DST = [2, 3, 4, 5, 6, 7], DIST = [0.5, 1.0, 2.0, 0.25, 0.75, 0.5],
                      NAME = [missing, "Varsity Dr", "Varsity Dr", "Western Blvd", "Western Blvd", missing],
                      DIR = [0, 1, 1, 1, 1, 0])
        R = pathroads(1:7, L)
        @test R.Seg == [1, 2] && R.Street == ["Varsity Dr", "Western Blvd"] && R.Steps == ["2-3", "4-5"]
        @test names(R) == ["Seg", "Street", "Steps"]
        R2 = pathroads([1, 2, 3, 4, 5, 6, 7], L; miles = true)
        @test names(R2) == ["Seg", "Street", "Steps", "Miles"] && R2.Miles == [3.0, 1.0]
        # a run continues across a step with no name
        L2 = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 1.0, 1.0],
                       NAME = ["Main St", missing, "Main St"], DIR = [0, 0, 0])
        @test pathroads([1, 2, 3, 4], L2).Steps == ["1-3"]
        @test pathroads([1, 2, 3, 4], L2; miles = true).Miles == [3.0]
        # the same name twice, apart, is two runs
        L3 = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 1.0, 1.0], NAME = ["A St", "B St", "A St"])
        @test pathroads([1, 2, 3, 4], L3).Street == ["A St", "B St", "A St"]
    end

    @testset "a link in either direction; parallel links: the one of least weight; DIR is respected" begin
        # FAF5's form: one link per road, a path may run against its SRC to DST
        L = DataFrame(SRC = [1, 2], DST = [2, 3], DIST = [1.0, 1.0], NAME = ["First", "Second"], DIR = [0, 0])
        @test pathroads([3, 2, 1], L).Street == ["Second", "First"]
        # two links between the same nodes: the shorter's name, whichever row comes last
        P = DataFrame(SRC = [1, 1], DST = [2, 2], DIST = [5.0, 3.0], NAME = ["Long Way", "Short Way"], DIR = [0, 0])
        @test pathroads([1, 2], P).Street == ["Short Way"]
        @test pathroads([1, 2], P[[2, 1], :]).Street == ["Short Way"]
        # a one-way link cannot be used against its direction: the parallel two-way link is the one
        D = DataFrame(SRC = [1, 1], DST = [2, 2], DIST = [1.0, 4.0], NAME = ["One Way", "Two Way"], DIR = [1, 0])
        @test pathroads([1, 2], D).Street == ["One Way"]
        @test pathroads([2, 1], D).Street == ["Two Way"]
        # DIR = -1 is traveled from DST to SRC
        M = DataFrame(SRC = [1], DST = [2], DIST = [1.0], NAME = ["Back Street"], DIR = [-1])
        @test pathroads([2, 1], M).Street == ["Back Street"]
        @test_throws ArgumentError pathroads([1, 2], M)
    end

    @testset "name, fallback and blank names (FAF5's SIGN, a cached CSV's missing)" begin
        L = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 1.0, 1.0],
                      NAME = ["Capital Blvd", "", missing], SIGN = ["US 1", "I 440", "I 440"], DIR = [0, 0, 0])
        @test pathroads(1:4, L).Street == ["Capital Blvd"]                                  # no fallback: blank and missing pass
        R = pathroads(1:4, L; fallback = :SIGN)
        @test R.Street == ["Capital Blvd", "I 440"] && R.Steps == ["1-1", "2-3"]
        @test pathroads(1:4, L; name = :SIGN).Street == ["US 1", "I 440"]
        @test pathroads(1:4, L; name = "SIGN").Steps == ["1-1", "2-3"]
    end

    @testset "weight picks among parallel links by the named column; a step with no link is refused" begin
        L = DataFrame(SRC = [1, 1], DST = [2, 2], DIST = [1.0, 9.0], MINUTES = [9.0, 1.0], NAME = ["Short", "Fast"])
        @test pathroads([1, 2], L).Street == ["Short"]
        @test pathroads([1, 2], L; weight = :MINUTES).Street == ["Fast"]
        @test pathroads([1, 2], L; weight = 4).Street == ["Fast"]
        err = try pathroads([1, 3], L) catch e; e end
        @test err isa ArgumentError && occursin("step 1", sprint(showerror, err))
    end

    @testset "an empty path, a path with no named road" begin
        L = DataFrame(SRC = [1], DST = [2], DIST = [1.0], NAME = [missing])
        for p in ([1], Int[], [1, 2])
            R = pathroads(p, L)
            @test nrow(R) == 0 && names(R) == ["Seg", "Street", "Steps"]
        end
        @test names(pathroads([1, 2], L; miles = true)) == ["Seg", "Street", "Steps", "Miles"]
    end
end

# ==== moved from test/test_plottools.jl, its lines 1-4, 141-205 ====
using Test
using DataFrames
using Graphs
using SparseArrays

# ---------------------------------------------------------------------------
# x2ln — pure geometry, no rendering
# ---------------------------------------------------------------------------
@testset "x2ln tests" begin

    @testset "simple directed graph" begin
        g = SimpleDiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)
        x = [-78.0, -79.0, -80.0]
        result = x2ln(g, x)
        # 2 edges × 3 values = 6
        @test length(result) == 6
        @test isequal(result, [-78.0, -79.0, NaN, -79.0, -80.0, NaN])
    end

    @testset "undirected graph has two directed edges per link" begin
        g = SimpleGraph(2)
        add_edge!(g, 1, 2)
        x = [10.0, 20.0]
        result = x2ln(g, x)
        # SimpleGraph edge iteration yields 1 edge for (1,2)
        @test length(result) == 3
        @test isequal(result, [10.0, 20.0, NaN])
    end

    @testset "disconnected graph" begin
        g = SimpleDiGraph(4)
        add_edge!(g, 1, 2)
        add_edge!(g, 3, 4)
        x = [1.0, 2.0, 3.0, 4.0]
        result = x2ln(g, x)
        @test length(result) == 6
        @test count(isnan, result) == 2
    end

    @testset "paired x2ln for lon/lat" begin
        g = SimpleDiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)
        lon = [-78.0, -79.0, -80.0]
        lat = [35.0, 36.0, 37.0]
        xline = x2ln(g, lon)
        yline = x2ln(g, lat)
        @test length(xline) == length(yline)
        # NaN positions align
        @test findall(isnan, xline) == findall(isnan, yline)
    end

    @testset "single edge" begin
        g = SimpleDiGraph(2)
        add_edge!(g, 1, 2)
        x = [5.0, 10.0]
        result = x2ln(g, x)
        @test isequal(result, [5.0, 10.0, NaN])
    end

    @testset "no edges returns empty" begin
        g = SimpleDiGraph(3)
        x = [1.0, 2.0, 3.0]
        result = x2ln(g, x)
        @test isempty(result)
    end
end
