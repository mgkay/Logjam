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
