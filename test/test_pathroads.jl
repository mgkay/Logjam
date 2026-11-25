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
