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
