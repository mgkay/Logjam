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
