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
