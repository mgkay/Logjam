# road_pin_cases.jl -- the road-network calls the course makes today, as pin cases (PCV K8, plan
# principle 9). Every case is a (name, thunk) pair; the thunk returns one line of text, the value encoded to
# 12 significant digits. The calls and the inputs come from the course's released lectures (read only):
# Lecture 4.1 (Code blocks 32 to 35, 38, 40, 43 to 53, 56 and 57), Lecture 4.2's OpenStreetMap form (run on the
# committed OSM test fixture, since the lecture's own tile is not part of this repository), Lecture 5.1's
# Code block 35, Lecture 5.3's Code block 64, and the High Point to Goldsboro generator of Lecture 2.2.
#
# Where a lecture builds its graph by hand (4.1 Code block 45's two rules, `combine = min`), the case builds
# it by hand too, from the lecture's own lines, so that it pins what `addconnectors`, `cropnetwork`,
# `shortestpaths` and `tracepath` return and not what `links2graph` builds. The one course call of
# `links2graph` is 2.2's generator, pinned as the generator calls it.
#
# A case whose value a ruled item moves is listed in RDPIN_MOVED with the ID of the commit that moves it;
# the fixture row is rewritten in that commit and the message lists the case. Any other case must keep its
# value. Lecture 4.1's Interstate files are not part of this repository: the Raleigh rectangle of Code block
# 34 is committed as test/data/interstate_raleigh_{nodes,links}.csv (derived from FAF5), and the whole
# network's case runs only where the lecture's data folder is reachable.

using Logjam
using DataFrames
using Graphs
using SimpleWeightedGraphs
using SparseArrays
using Random
using CSV
using LightOSM

# ---- encoding ------------------------------------------------------------------------------
_rd(x::Missing) = "missing"
_rd(x::Bool) = string(x)
_rd(x::Integer) = string(x)
_rd(x::AbstractFloat) = isfinite(x) ? repr(round(Float64(x); sigdigits = 12)) : repr(Float64(x))
_rd(x::AbstractString) = repr(String(x))
_rd(x::Nothing) = "nothing"
_rd(x::Tuple) = "(" * join((_rd(v) for v in x), ",") * ")"
_rd(x::NamedTuple) = _rd(Tuple(x))
_rd(x::AbstractArray) = string(size(x)) * "[" * join((_rd(v) for v in x), ",") * "]"

# a case whose value a ruled item moves: name => the ID of the commit that moves it (several: "A+B")
const RDPIN_MOVED = Dict{String,String}()

# ---- the course's data and the lectures' own lines -----------------------------------------------
const _RD_MEMO = Dict{Any,Any}()
_rd_memo(f, key) = get!(f, _RD_MEMO, key)

# 4.1 Code block 43: the FAF5 network, nodes numbered from 1
_rd_faf() = _rd_memo(:faf) do
    prune_reindex(faf5nodes(), faf5links())
end
# 4.1 Code block 47: the NC cities over 100K
_rd_cities() = _rd_memo(:cities) do
    df = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
    select!(df, :NAME, :LAT, :LON, :POP)
end
# 5.1 Code block 35 and 5.3 Code block 64: the 100 NC counties' points
_rd_counties() = _rd_memo(:counties) do
    filter(r -> (r.STFIP == st2fips(:NC)), uscounty())
end

# the rows of a network's connectors, as (SRC, DST, DIST), in sorted order: the order of a point's three
# connectors is not the same from one run of v0.2.8 to the next (the triangle's vertices come back in
# whichever rotation the triangulation's search meets first), so the pin is of the set
_rd_isconn(L) = isequal.(L.SOURCE, "CONNECTOR")
_rd_conn(L) = sort([(r.SRC, r.DST, r.DIST) for r in eachrow(L[_rd_isconn(L), :])])
# 4.1 Code block 45, annotation 2: each link gives an arc in each direction it can be traveled, the shorter
# of parallel arcs is kept
function _rd_graph(L, tAB, tBA)
    fw, bw = L.DIR .!= -1, L.DIR .!= 1
    return SimpleWeightedDiGraph([L.SRC[fw]; L.DST[bw]], [L.DST[fw]; L.SRC[bw]],
                                 [tAB[fw]; tBA[bw]]; combine = min)
end
_rd_graph(L, w) = _rd_graph(L, w, w)
# 4.1 Code block 51: a link's minutes, FAF5's free-flow time or 60 d / v, a connector at 20 mph
_rd_mins(t, v, d) = t > 0 ? t : 60d / v
function _rd_times(L)
    con = _rd_isconn(L)
    tAB = [c ? 60d / 20 : _rd_mins(t, v, d) for (c, t, v, d) in zip(con, L.AB_TIME, L.SPEED, L.DIST)]
    tBA = [c ? 60d / 20 : _rd_mins(t, v, d) for (c, t, v, d) in zip(con, L.BA_TIME, L.SPEED, L.DIST)]
    return tAB, tBA
end
# a matrix and a few of its entries, and the size and nodes of the paths from the first nodes
function _rd_dp(D, P, n)
    paths = [tracepath(P[i], i, j) for i in 1:n, j in 1:n if i != j && isfinite(D[i, j])]
    return (size(D), sum(D[isfinite.(D)]), sum(D[isfinite.(D)] .^ 2), count(!isfinite, D), D[1, 2],
            D[2, 1], sum(length, paths), sum(sum, paths), tracepath(P[1], 1, 2))
end

# 4.1 Code block 38's seven cities and Code block 40's six new nodes
const _RD_A7 = [1 2 31; 1 3 25; 1 4 36; 1 7 42; 2 4 64; 2 5 100; 2 7 60;
                3 4 14; 3 6 29; 3 7 49; 4 5 43; 4 6 21; 5 6 39; 6 7 69]
_rd_net7() = _rd_memo(:net7) do
    gso = loc2lonlat("Greensboro"; state = :NC)
    C7 = filter(r -> r.POP > 30_000 && dgc([gso.LON, gso.LAT], [r.LON, r.LAT]) < 50, usplace())
    sort!(C7, [:ST, :NAME])
    N7 = DataFrame(IDX = 1:nrow(C7), LON = C7.LON, LAT = C7.LAT)
    L7 = DataFrame(SRC = _RD_A7[:, 1], DST = _RD_A7[:, 2], DIST = _RD_A7[:, 3])
    (N7, L7)
end
const _RD_X1 = [-79.990, -80.308, -79.629, -79.899, -79.554, -79.143]
const _RD_Y1 = [35.921, 35.736, 35.894, 36.206, 36.232, 36.321]

# 4.1 Code block 32's schematic of I-40 around Raleigh
const _RD_XY0 = [1.33 -6.70; 1.27 -7.89; 1.67 -7.28; 2.97 -7.78; 4.05 -7.27;
                 4.45 -6.68; 4.83 -7.91; 5.53 -6.62; 5.62 -7.66; 6.41 -7.47;
                 6.59 -6.79; 7.07 -7.86]
const _RD_A0 = [1 3 5; 2 3 5; 3 4 20; 4 5 15; 5 6 10; 6 8 15; 8 9 15; 5 7 15;
                7 9 10; 9 10 10; 10 11 5; 10 12 5]

# 4.1 Code block 31's Interstate files, cut to Code block 34's rectangle (test/data, derived from FAF5)
_rd_raleigh() = _rd_memo(:raleigh) do
    d = joinpath(@__DIR__, "data")
    (DataFrame(CSV.File(joinpath(d, "interstate_raleigh_nodes.csv"))),
     DataFrame(CSV.File(joinpath(d, "interstate_raleigh_links.csv"))))
end
const _RD_RRAL = [-79.2618 35.2497; -78.1964 36.1762]

# the whole Interstate network of 4.1's Code block 31: only where the lecture's data folder is reachable
const _RD_LECTURE_DATA = get(ENV, "LOGJAM_LECTURE_DATA", "")      # unset: the cases that need it are skipped
_rd_have_interstates() = !isempty(_RD_LECTURE_DATA) && isfile(joinpath(_RD_LECTURE_DATA, "interstate_links.csv"))

# a thinned network, by what is invariant under renumbering: the node and link counts, the distances
_rd_thinshape(tN, tL) = (nrow(tN), nrow(tL), sort(tL[:, 3]), sum(tL[:, 3]))

# the OSM test fixture, translated the way osm_roads translates a download (test_osm.jl)
const _RD_OSM_EXT = Base.get_extension(Logjam, :LogjamOSMExt)
_rd_osm() = _rd_memo(:osm) do
    N, L, _ = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        _RD_OSM_EXT._osm_tables_from_xml(read(joinpath(@__DIR__, "data", "osm_fixture.osm"), String))
    end
    # LightOSM keeps its nodes in a Dict, whose order differs from one Julia version to the next, and the
    # pinned connectors name nodes: number the nodes by position (longitude, then latitude) and sort the
    # links, so the pins are the same on every version
    o = sortperm(collect(zip(N.LON, N.LAT)))
    newid = Dict(N[o[k], 1] => k for k in eachindex(o))
    N2 = N[o, :]
    N2[!, 1] = collect(1:nrow(N2))
    L2 = copy(L)
    L2[!, 1] = [newid[v] for v in L.SRC]
    L2[!, 2] = [newid[v] for v in L.DST]
    sort!(L2, [:SRC, :DST, :DIST, :SPEED, :FCLASS, :DIR, :NAME])
    (N2, L2)
end

# ---- OpenStreetMap (PCV K9): Lecture 4.2's two calls of osm_roads and what is computed from them ------------
# The committed cache read is Lecture 4.2's Code block 2 (Ex. 1's box) and Code block 31 (Ex. 3's box); both read
# a pair of tiles from the lecture's data folder (read only), so those cases run only where it is reachable
# (LOGJAM_LECTURE_DATA). The boxes need no tile: they come from the geocoded addresses the lecture's cache
# holds (Code block 1) and the draw of Code block 30, so the generator's two internal calls are pinned in CI.
const _RD_OSM_X = [-78.6758457, -78.6695716]     # Fitts-Woolard Hall, D. H. Hill Library (data/geocode_cache.csv)
const _RD_OSM_Y = [35.7706306, 35.7875615]
const _RD_OSM_C0 = (-78.6390995, 35.7803975)     # the State Capitol (Code block 30's c0)
const _RD_OSM_TILE1 = "osm_w-78.7_e-78.65_s35.75_n35.8"
const _RD_OSM_TILE2 = "osm_w-78.75_e-78.55_s35.7_n35.85"
_rd_have_osm() = !isempty(_RD_LECTURE_DATA) && all(isfile(joinpath(_RD_LECTURE_DATA, t * s)) for t in (_RD_OSM_TILE1, _RD_OSM_TILE2),
                     s in ("_nodes.csv", "_links.csv"))
_rd_osm_bb1() = mapbbox(_RD_OSM_X, _RD_OSM_Y; xexpand = 2, yexpand = 0.5)     # Code block 2
# Code block 30: the 22 drivers and passengers, a draw of block groups within 3 mi of the Capitol. The lecture
# draws with `Random.seed!(754); randperm(75)[1:22]`, which gives another draw on Julia 1.13 than on 1.12 (the
# version the course is pinned to, and the one the committed cells were downloaded for), so the case takes the
# indices 1.12 draws, and test_road_pins.jl checks that 1.12 still draws them
const _RD_OSM_DRAW = [6, 31, 54, 69, 38, 34, 50, 22, 29, 46, 42, 57, 7, 59, 48, 65, 60, 55, 49, 62, 67, 56]
function _rd_osm_bg()
    bg = filter(r -> dgc(_RD_OSM_C0, (r.LON, r.LAT)) <= 3, uscenblkgrp())
    sort!(bg, [:TRFIP, :BGFIP])
    return bg
end
function _rd_osm_U()
    bg = _rd_osm_bg()
    k = _RD_OSM_DRAW
    DataFrame(ROLE = [fill("driver", 12); fill("passenger", 10)], ID = [string.("D", 1:12); string.("P", 1:10)],
              LON = bg.LON[k], LAT = bg.LAT[k])
end
_rd_osm_bb3() = (U = _rd_osm_U(); mapbbox(U.LON, U.LAT; xexpand = 0.1, yexpand = 0.1))   # Code block 31
# the course's call, as 4.2 writes it (the splat): a tile pair of the lecture's data folder, read through osm_roads
function _rd_osm_read(bb)
    Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        osm_roads((bb[1]..., bb[2]...); cache_dir = _RD_LECTURE_DATA)
    end
end
# what a pair of OSM tables holds, by value: the sizes, the sums, the NAME pattern, the class and speed columns
function _rd_osm_values(dfN, dfL)
    cs = Dict{Tuple{Int,Int},Int}()
    for (f, s) in zip(dfL.FCLASS, dfL.SPEED)
        cs[(f, s)] = get(cs, (f, s), 0) + 1
    end
    nm = collect(skipmissing(dfL.NAME))
    return (nrow(dfN), nrow(dfL), names(dfN), names(dfL), sum(dfN.IDX), sum(dfN.LON), sum(dfN.LAT),
            sum(dfL.SRC), sum(dfL.DST), sum(dfL.DIST), sum(dfL.SPEED), sum(dfL.FCLASS), sum(dfL.DIR),
            count(ismissing, dfL.NAME), count(isempty, nm), length(unique(nm)), first(nm), last(nm),
            sort(unique(String.(dfN.SOURCE))), sort(unique(String.(dfL.SOURCE))),
            [(k..., v) for (k, v) in sort(collect(cs))])
end
_rd_osm_types(dfN, dfL) = (names(dfN), string.(eltype.(eachcol(dfN))), names(dfL), string.(eltype.(eachcol(dfL))))
# Statistics' median (Statistics is not in the test environment)
_rd_median(v) = (s = sort(v); n = length(s); isodd(n) ? s[(n + 1) ÷ 2] : (s[n ÷ 2] + s[n ÷ 2 + 1]) / 2)
# Code block 8: the streets along a path, numbered in order (4.2's own definition)
function _rd_osm_streets(p, L)
    k = Dict(zip(zip(L.SRC, L.DST), 1:nrow(L)))
    lk(u, v) = get(k, (u, v), get(k, (v, u), 0))
    nm = [L.NAME[lk(u, v)] for (u, v) in zip(p, p[2:end])]
    t = findall(!ismissing, nm)
    a = [i for i in eachindex(t) if i == 1 || nm[t[i]] != nm[t[i-1]]]
    b = [a[2:end] .- 1; length(t)]
    return (collect(eachindex(a)), nm[t[a]], string.(t[a], "-", t[b]))
end

# seeded random nodes and points, for the connector search
function _rd_random_net(n, m; seed = 754)
    rng = MersenneTwister(seed)
    N = DataFrame(IDX = 1:n, LON = -79.0 .+ 0.5 .* rand(rng, n), LAT = 35.0 .+ 0.5 .* rand(rng, n))
    ia = rand(rng, 1:n, 3n)
    ib = [(a + rand(rng, 1:5) - 1) % n + 1 for a in ia]
    keep = ia .!= ib
    L = DataFrame(SRC = ia[keep], DST = ib[keep],
                  DIST = [dgc((N.LON[a], N.LAT[a]), (N.LON[b], N.LAT[b])) for (a, b) in zip(ia[keep], ib[keep])])
    x = -79.05 .+ 0.6 .* rand(rng, m)         # some outside the nodes' hull
    y = 34.95 .+ 0.6 .* rand(rng, m)
    return N, L, x, y
end

# ---- the cases ---------------------------------------------------------------------------
function rdpin_cases()
    cases = Pair{String,Function}[]
    add(name, f) = push!(cases, name => f)

    # the FAF5 network, pruned and reindexed (4.1 Code block 43), and the Wake County crop (Code block 44)
    add("faf5_prune_reindex", () -> begin
        N, L = _rd_faf()
        _rd((nrow(N), nrow(L), maximum(N.IDX), sum(L.DIST), sum(N.LON), sum(L.SRC), sum(L.DST)))
    end)
    add("l41_cb44_wake_prune_reindex", () -> begin
        N, L = _rd_faf()
        NW, LW = prune_reindex(N, filter(r -> r.STFIP == 37 && r.COFIP == 37183, L))
        _rd((nrow(NW), nrow(LW), maximum(NW.IDX), sum(LW.DIST), sum(LW.SRC), sum(LW.DST)))
    end)

    # 4.1 Code block 45: two points, their connectors, and the shortest path between them
    add("l41_cb45_wake_two_points", () -> begin
        N, L = _rd_faf()
        NW, LW = prune_reindex(N, filter(r -> r.STFIP == 37 && r.COFIP == 37183, L))
        XY2 = [-78.75864529722959 35.74329140697632; -78.70352644371913 35.866083946889844]
        NW2, LW2 = addconnectors(NW, LW, XY2[:, 1], XY2[:, 2]; add_nf_nf = false)
        g = _rd_graph(LW2, LW2.DIST)
        D, P = shortestpaths(g, 2)
        _rd((nrow(NW2), nrow(LW2), _rd_conn(LW2), nv(g), ne(g), _rd_dp(D, P, 2)))
    end)

    # 4.1 Code blocks 47 to 49: the ten NC cities' road distances
    add("l41_cb48_ten_cities_distances", () -> begin
        N, L = _rd_faf()
        df = _rd_cities()
        Nc, Lc = cropnetwork(N, L, df.LON, df.LAT)
        Nc2, Lc2 = addconnectors(Nc, Lc, df.LON, df.LAT; add_nf_nf = false)
        g = _rd_graph(Lc2, Lc2.DIST)
        D, P = shortestpaths(g, nrow(df))
        _rd((nrow(df), nrow(Nc), nrow(Lc), nrow(Nc2), nrow(Lc2), _rd_conn(Lc2), nv(g), ne(g),
             _rd_dp(D, P, nrow(df))))
    end)
    # 4.1 Code block 51: the same cities' travel times
    add("l41_cb51_ten_cities_times", () -> begin
        N, L = _rd_faf()
        df = _rd_cities()
        Nc, Lc = cropnetwork(N, L, df.LON, df.LAT)
        Nc, Lc = addconnectors(Nc, Lc, df.LON, df.LAT; add_nf_nf = false)
        tAB, tBA = _rd_times(Lc)
        gT = _rd_graph(Lc, tAB, tBA)
        T, PT = shortestpaths(gT, nrow(df))
        _rd((sum(tAB), sum(tBA), nv(gT), ne(gT), _rd_dp(T, PT, nrow(df))))
    end)
    # 4.1 Code block 53: High Point to Goldsboro, shortest and fastest
    add("l41_cb53_high_point_goldsboro", () -> begin
        N, L = _rd_faf()
        hp = loc2lonlat("High Point"; state = :NC)
        gb = loc2lonlat("Goldsboro"; state = :NC)
        X, Y = [hp.LON, gb.LON], [hp.LAT, gb.LAT]
        N3, L3 = cropnetwork(N, L, X, Y; xexpand = 0.2, yexpand = 0.5)
        N3, L3 = addconnectors(N3, L3, X, Y; add_nf_nf = false)
        t3AB, t3BA = _rd_times(L3)
        g3, g3T = _rd_graph(L3, L3.DIST), _rd_graph(L3, t3AB, t3BA)
        pD = tracepath(Graphs.dijkstra_shortest_paths(g3, 1).parents, 1, 2)
        pF = tracepath(Graphs.dijkstra_shortest_paths(g3T, 1).parents, 1, 2)
        miD = sum.(segcost.([pD, pF], Ref(weights(g3))))
        minT = sum.(segcost.([pD, pF], Ref(weights(g3T))))
        _rd((nrow(N3), nrow(L3), _rd_conn(L3), pD, pF, miD, minT))
    end)

    # 4.1 Code block 38: seven cities pruned two ways, and Code block 40: six new nodes joined to them
    add("l41_cb38_seven_cities_prune_crop", () -> begin
        N7, L7 = _rd_net7()
        aN, aL = prune_reindex(N7, filter(r -> r.DIST < 35, L7))
        R7 = [-80.6085 35.5897; -79.6971 36.2184]
        cN, cL = cropnetwork(N7, L7, R7[:, 1], R7[:, 2]; xexpand = 0, yexpand = 0)
        _rd((aN.IDX, aN.LON, Matrix(aL), cN.IDX, cN.LON, Matrix(cL)))
    end)
    add("l41_cb40_seven_cities_nf_true", () -> begin
        N7, L7 = _rd_net7()
        N8, L8 = addconnectors(N7, L7, _RD_X1, _RD_Y1; add_nf_nf = true)
        isc = _rd_isconn(L8)
        _rd((nrow(N8), nrow(L8), N8.IDX, _rd_conn(L8), count(isc .& (L8.DST .> 6)),
             count(isc .& (L8.DST .<= 6))))
    end)
    # D8, N16: the bare call (4.1 Code block 40 as it stands) adds the new-node connectors
    add("l41_cb40_seven_cities_default_call", () -> begin
        N7, L7 = _rd_net7()
        N8, L8 = addconnectors(N7, L7, _RD_X1, _RD_Y1)
        isc = _rd_isconn(L8)
        _rd((nrow(N8), nrow(L8), _rd_conn(L8), count(isc .& (L8.DST .> 6)), count(isc .& (L8.DST .<= 6))))
    end)
    RDPIN_MOVED["l41_cb40_seven_cities_default_call"] = "D8_N16"

    # 4.1 Code block 32: the schematic of I-40 around Raleigh, thinned. The counts and distances are what
    # the slide states (one arc of 70); the node numbers are what N6 renumbers
    add("l41_cb32_schematic_thin_shape", () -> begin
        N0 = DataFrame(IDX = 1:size(_RD_XY0, 1), X = _RD_XY0[:, 1], Y = _RD_XY0[:, 2])
        L0 = DataFrame(SRC = _RD_A0[:, 1], DST = _RD_A0[:, 2], DIST = _RD_A0[:, 3])
        tN0, tL0 = thin(N0, L0)
        _rd((_rd_thinshape(tN0, tL0), string(eltype(tL0.DIST))))
    end)
    add("l41_cb32_schematic_thin_ids", () -> begin
        N0 = DataFrame(IDX = 1:size(_RD_XY0, 1), X = _RD_XY0[:, 1], Y = _RD_XY0[:, 2])
        L0 = DataFrame(SRC = _RD_A0[:, 1], DST = _RD_A0[:, 2], DIST = _RD_A0[:, 3])
        tN0, tL0 = thin(N0, L0)
        _rd((tN0.IDX, tN0.X, tL0.SRC, tL0.DST, tL0.DIST))
    end)
    RDPIN_MOVED["l41_cb32_schematic_thin_ids"] = "N6_CR18_CR25"
    # thin's other cases move with it: label-independent (CR 18) and direction-aware (CR 25), the nodes it keeps
    # numbered 1:n (N6). Whole Interstate network: 621 nodes and 1,024 links become 600 and 989. The Raleigh cut's
    # intersections (Code block 56), a triangle of three junctions, thin to the one link between two of them, as
    # Matlog's thin does
    RDPIN_MOVED["l41_cb35_interstates_thin"] = "N6_CR18_CR25"
    RDPIN_MOVED["l41_cb56_57_raleigh_intersections"] = "N6_CR18_CR25"

    # 4.1 Code block 34: the Interstates inside the Raleigh rectangle (committed cut), cropped, thinned
    add("l41_cb34_raleigh_crop_thin", () -> begin
        dfN, dfL = _rd_raleigh()
        rN, rL = cropnetwork(dfN, dfL, _RD_RRAL[:, 1], _RD_RRAL[:, 2]; xexpand = 0, yexpand = 0)
        trN, trL = thin(rN, rL)
        _rd((nrow(rN), nrow(rL), sum(rL.DIST), _rd_thinshape(trN, trL)))
    end)
    # Code block 35 on the same cut: thin with the nodes' original indices, then prune_reindex
    add("l41_cb35_raleigh_thin_then_reindex", () -> begin
        dfN, dfL = _rd_raleigh()
        tN, tL = thin(dfN, dfL)
        rN, rL = prune_reindex(tN, tL)
        _rd((_rd_thinshape(tN, tL), nrow(rN), nrow(rL), sum(rL.DIST), maximum(rN.IDX)))
    end)
    # Code blocks 56 and 57: the cut reindexed, its ends removed, thinned again, and all-pairs hours
    add("l41_cb56_57_raleigh_intersections", () -> begin
        dfN, dfL = _rd_raleigh()
        iN, iL = prune_reindex(dfN, dfL)
        while true
            deg = [count(==(k), [iL.SRC; iL.DST]) for k in 1:nrow(iN)]
            all(>(1), deg) && break
            iN, iL = prune_reindex(iN, filter(r -> deg[r.SRC] > 1 && deg[r.DST] > 1, iL))
        end
        iN, iL = prune_reindex(thin(iN, iL)...)
        gI = SimpleWeightedGraph(iL.SRC, iL.DST, iL.DIST ./ 60; combine = min)
        T, _ = shortestpaths(gI, weights(gI), nv(gI))
        _rd((nrow(iN), nrow(iL), sum(iL.DIST), nv(gI), ne(gI), sum(T), maximum(T)))
    end)
    # the whole Interstate network of Code block 35 (where the lecture's data folder is reachable)
    add("l41_cb35_interstates_thin", () -> begin
        _rd_have_interstates() || return "SKIPPED: lecture data not reachable"
        d = _RD_LECTURE_DATA
        dfN = DataFrame(CSV.File(joinpath(d, "interstate_nodes.csv")))
        dfL = DataFrame(CSV.File(joinpath(d, "interstate_links.csv")))
        tN, tL = thin(dfN, dfL)
        rN, rL = prune_reindex(tN, tL)
        _rd((nrow(dfN), nrow(dfL), _rd_thinshape(tN, tL), nrow(rN), nrow(rL), maximum(tN.IDX), maximum(rN.IDX)))
    end)

    # 2.2's generator (make_circuity_road_vs_gc.jl): FAF5 around High Point and Goldsboro, the pair added with
    # the default call, links2graph, the doubled-sparse weight matrix and the three-argument shortestpaths
    add("l22_generator_circuity_verbatim", () -> begin
        A = first(filter(r -> r.NAME == "High Point" && r.ST == :NC, usplace()))
        B = first(filter(r -> r.NAME == "Goldsboro" && r.ST == :NC, usplace()))
        XY = [A.LON A.LAT; B.LON B.LAT]
        dfN, dfL = faf5nodes(), faf5links()
        dfN, dfL = cropnetwork(dfN, dfL, [minimum(XY[:, 1]) - 0.7, maximum(XY[:, 1]) + 0.7],
                               [minimum(XY[:, 2]) - 0.5, maximum(XY[:, 2]) + 0.5])
        dfNc, dfLc = addconnectors(dfN, dfL, XY[:, 1], XY[:, 2])
        g = links2graph(dfLc)
        nv_ = Graphs.nv(g)
        W = sparse(dfLc.SRC, dfLc.DST, dfLc.DIST, nv_, nv_)
        W = W + W'
        D, P = shortestpaths(g, W, 2)
        _rd((nrow(dfN), nrow(dfL), D[1, 2], D[1, 2] / dgc(XY[1, :], XY[2, :]), length(tracepath(P[1], 1, 2))))
    end)
    # the same crop on the graph's own weights, which is what CR 17 changes from 137.57 to 137.47
    add("l22_generator_links2graph_weights", () -> begin
        A = first(filter(r -> r.NAME == "High Point" && r.ST == :NC, usplace()))
        B = first(filter(r -> r.NAME == "Goldsboro" && r.ST == :NC, usplace()))
        XY = [A.LON A.LAT; B.LON B.LAT]
        dfN, dfL = faf5nodes(), faf5links()
        dfN, dfL = cropnetwork(dfN, dfL, [minimum(XY[:, 1]) - 0.7, maximum(XY[:, 1]) + 0.7],
                               [minimum(XY[:, 2]) - 0.5, maximum(XY[:, 2]) + 0.5])
        dfNc, dfLc = addconnectors(dfN, dfL, XY[:, 1], XY[:, 2]; add_nf_nf = false)
        g = links2graph(dfLc)
        D, P = shortestpaths(g, 2)
        _rd((nv(g), ne(g), D[1, 2], D[2, 1], length(tracepath(P[1], 1, 2))))
    end)
    RDPIN_MOVED["l22_generator_links2graph_weights"] = "CR17"
    # the 137.66 that the generator's own matrix gives and the same pair against the hand-built graph
    add("l22_generator_hand_built_graph", () -> begin
        A = first(filter(r -> r.NAME == "High Point" && r.ST == :NC, usplace()))
        B = first(filter(r -> r.NAME == "Goldsboro" && r.ST == :NC, usplace()))
        XY = [A.LON A.LAT; B.LON B.LAT]
        dfN, dfL = faf5nodes(), faf5links()
        dfN, dfL = cropnetwork(dfN, dfL, [minimum(XY[:, 1]) - 0.7, maximum(XY[:, 1]) + 0.7],
                               [minimum(XY[:, 2]) - 0.5, maximum(XY[:, 2]) + 0.5])
        dfNc, dfLc = addconnectors(dfN, dfL, XY[:, 1], XY[:, 2]; add_nf_nf = false)
        g = _rd_graph(dfLc, dfLc.DIST)
        D, P = shortestpaths(g, 2)
        _rd((nv(g), ne(g), D[1, 2], D[2, 1], length(tracepath(P[1], 1, 2))))
    end)

    # 5.1 Code block 35: road distances between the 100 NC county points; 5.3 Code block 64: their minutes
    add("l51_cb35_county_road_distances", () -> begin
        N, L = _rd_faf()
        df = _rd_counties()
        Nc, Lc = cropnetwork(N, L, df.LON, df.LAT)
        Nc2, Lc2 = addconnectors(Nc, Lc, df.LON, df.LAT; add_nf_nf = false)
        g = _rd_graph(Lc2, Lc2.DIST)
        Dr, Pr = shortestpaths(g, nrow(df))
        _rd((nrow(df), nrow(Nc), nrow(Lc), nrow(Nc2), nrow(Lc2), _rd_conn(Lc2), nv(g), ne(g),
             _rd_dp(Dr, Pr, nrow(df))))
    end)
    add("l53_cb64_county_road_minutes", () -> begin
        N, L = _rd_faf()
        dfc = _rd_counties()
        Nc, Lc = cropnetwork(N, L, dfc.LON, dfc.LAT)
        Nc, Lc = addconnectors(Nc, Lc, dfc.LON, dfc.LAT; add_nf_nf = false)
        tAB, tBA = _rd_times(Lc)
        gT = _rd_graph(Lc, tAB, tBA)
        Tmin, PT = shortestpaths(gT, nrow(dfc))
        _rd((sum(tAB), sum(tBA), nv(gT), ne(gT), maximum(Tmin), _rd_dp(Tmin, PT, nrow(dfc))))
    end)

    # 4.2's form on the OSM fixture: the points joined, the two graphs of Code block 6, both directions
    add("l42_cb6_osm_fixture_two_graphs", () -> begin
        dfN, dfL = _rd_osm()
        # the two points sit in triangles that the fixture's lattice of nodes (four of them on one circle in
        # places) leaves no choice about: a point in a quadrilateral of four cocircular nodes is joined to the
        # corners of whichever triangle the triangulation's randomized insertion order happens to make. The
        # lattice is the fixture's ten nodes that CR 21/24/34 leave (nodes 1 to 9 and the one above the third
        # row, 10); the only cells with no choice are the two above that row, and the points are fixed in them
        # (the fractions of the extent that did this for the twelve nodes of v0.2.8 land in a square cell)
        x = [-78.6392, -78.6384]
        y = [35.7821, 35.7822]
        Nc, Lc = addconnectors(dfN, dfL, x, y; add_nf_nf = false)
        con = _rd_isconn(Lc)
        tmin = [c ? 60d / 20 : 60d / v for (c, d, v) in zip(con, Lc.DIST, Lc.SPEED)]
        gD, gT = _rd_graph(Lc, Lc.DIST), _rd_graph(Lc, tmin)
        D, PD = shortestpaths(gD, 2)
        T, PT = shortestpaths(gT, 2)
        _rd((nrow(dfN), nrow(dfL), nrow(Nc), nrow(Lc), _rd_conn(Lc), nv(gD), ne(gD), _rd_dp(D, PD, 2),
             _rd_dp(T, PT, 2)))
    end)

    # ---- K9: Lecture 4.2's reads of the committed OpenStreetMap cache --------------------------------------
    # Code block 2: Ex. 1's box, its tile pair read through osm_roads (the call as the lecture splats it)
    add("l42_cb2_tile1_read_values", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        dfN, dfL = _rd_osm_read(_rd_osm_bb1())
        _rd(_rd_osm_values(dfN, dfL))
    end)
    # the column element types of the read: CR 24 gives SOURCE one declared type (v0.2.8: String3 from CSV's inference)
    add("l42_cb2_tile1_read_types", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        dfN, dfL = _rd_osm_read(_rd_osm_bb1())
        _rd(_rd_osm_types(dfN, dfL))
    end)
    RDPIN_MOVED["l42_cb2_tile1_read_types"] = "CR24"
    # the two tile files the call reads and their sizes
    add("l42_cb2_tile1_files", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        np, lp = Logjam._osm_cache_path((_rd_osm_bb1()[1]..., _rd_osm_bb1()[2]...), _RD_LECTURE_DATA)
        _rd((basename(np), basename(lp), filesize(np), filesize(lp)))
    end)
    # Code blocks 2 to 7 on it: the crop to the box, the class table, the one-way counts, the two graphs of
    # Code block 6, and the routes out and back with the streets each follows (Code blocks 7 and 8)
    add("l42_ex1_crop_graphs_routes", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        x, y = _RD_OSM_X, _RD_OSM_Y
        dfN, dfL = _rd_osm_read(_rd_osm_bb1())
        dfN, dfL = cropnetwork(dfN, dfL, x, y; xexpand = 2, yexpand = 0.5)
        cs = Dict{Tuple{Int,Int},Int}()
        for (f, s) in zip(dfL.FCLASS, dfL.SPEED)
            cs[(f, s)] = get(cs, (f, s), 0) + 1
        end
        arcs = Set(zip(dfL.SRC, dfL.DST))
        oneway = count(((s, d),) -> (d, s) ∉ arcs, zip(dfL.SRC, dfL.DST))
        Nc, Lc = addconnectors(dfN, dfL, x, y; add_nf_nf = false)
        con = isequal.(Lc.SOURCE, "CONNECTOR")
        tmin = [c ? 60d / 20 : 60d / v for (c, d, v) in zip(con, Lc.DIST, Lc.SPEED)]
        gD, gT = _rd_graph(Lc, Lc.DIST), _rd_graph(Lc, tmin)
        D, PD = shortestpaths(gD, 2)
        T, PT = shortestpaths(gT, 2)
        Wd, Wt = weights(gD), weights(gT)
        routes = Any[]
        for (i, j) in ((1, 2), (2, 1)), P in (PD, PT)
            p = tracepath(P[i], i, j)
            push!(routes, (sum(segcost(p, Wd)), sum(segcost(p, Wt)), p, _rd_osm_streets(p, Lc)))
        end
        _rd((_rd_osm_values(dfN, dfL), [(k..., v) for (k, v) in sort(collect(cs))], oneway,
             round(100 * count(==(7), dfL.FCLASS) / nrow(dfL), digits = 1), round(100 * oneway / nrow(dfL), digits = 1),
             round(Int, 5280 * _rd_median(dfL.DIST)), all(==(1), dfL.DIR), nrow(Nc), nrow(Lc), _rd_conn(Lc),
             nv(gD), ne(gD), routes...))
    end)
    # the printed numbers of the lecture that the call feeds, as the lecture shows them (4.2's page, Ex. 1)
    add("l42_ex1_printed_numbers", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        x, y = _RD_OSM_X, _RD_OSM_Y
        dfN, dfL = cropnetwork(_rd_osm_read(_rd_osm_bb1())..., x, y; xexpand = 2, yexpand = 0.5)
        Nc, Lc = addconnectors(dfN, dfL, x, y; add_nf_nf = false)
        con = isequal.(Lc.SOURCE, "CONNECTOR")
        tmin = [c ? 60d / 20 : 60d / v for (c, d, v) in zip(con, Lc.DIST, Lc.SPEED)]
        gD, gT = _rd_graph(Lc, Lc.DIST), _rd_graph(Lc, tmin)
        D, PD = shortestpaths(gD, 2)
        T, PT = shortestpaths(gT, 2)
        Wd, Wt = weights(gD), weights(gT)
        R = [(round(sum(segcost(tracepath(P[i], i, j), Wd)), digits = 2),
              round(sum(segcost(tracepath(P[i], i, j), Wt)), digits = 2)) for (i, j) in ((1, 2), (2, 1)) for P in (PD, PT)]
        _rd((nrow(dfN), nrow(dfL), nrow(Nc), nrow(Lc), R))
    end)
    # Code block 31 (Ex. 3): the 22 points' box, its tile pair, the crop, the connectors, the driving minutes
    add("l42_cb31_tile2_read_values", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        dfN, dfL = _rd_osm_read(_rd_osm_bb3())
        _rd(_rd_osm_values(dfN, dfL))
    end)
    add("l42_cb31_tile2_read_types", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        dfN, dfL = _rd_osm_read(_rd_osm_bb3())
        _rd(_rd_osm_types(dfN, dfL))
    end)
    RDPIN_MOVED["l42_cb31_tile2_read_types"] = "CR24"
    add("l42_cb31_tile2_files", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        bb = _rd_osm_bb3()
        np, lp = Logjam._osm_cache_path((bb[1]..., bb[2]...), _RD_LECTURE_DATA)
        _rd((basename(np), basename(lp), filesize(np), filesize(lp)))
    end)
    add("l42_ex3_crop_connectors_minutes", () -> begin
        _rd_have_osm() || return "SKIPPED: lecture data not reachable"
        U = _rd_osm_U()
        drv, pas = findall(==("driver"), U.ROLE), findall(==("passenger"), U.ROLE)
        NU, LU = cropnetwork(_rd_osm_read(_rd_osm_bb3())..., U.LON, U.LAT; xexpand = 0.1, yexpand = 0.1)
        nc, lc = nrow(NU), nrow(LU)
        NU, LU = addconnectors(NU, LU, U.LON, U.LAT; add_nf_nf = false)
        cU = isequal.(LU.SOURCE, "CONNECTOR")
        tU = [c ? 60d / 20 : 60d / v for (c, d, v) in zip(cU, LU.DIST, LU.SPEED)]
        gU = _rd_graph(LU, tU)
        TU, PU = shortestpaths(gU, nrow(U))
        C = TU[drv, pas]
        nU = nrow(U)
        _rd((nc, lc, nrow(NU), nrow(LU), _rd_conn(LU), nv(gU), ne(gU), U.LON, U.LAT, C,
             sum(TU[1:nU, 1:nU]) / (nU * (nU - 1)), round.(C, digits = 1)))
    end)
    # the generator's two internal calls (make_osm_raleigh.jl: the boxes, `_osm_cache_path`, `_osm_snap_bbox`)
    add("l42_generator_internal_calls", () -> begin
        out = Any[]
        for b in (_rd_osm_bb1(), _rd_osm_bb3())
            bb = (b[1]..., b[2]...)
            np, lp = Logjam._osm_cache_path(bb, "data")
            # the paths come from joinpath, so the separator is the platform's; the pin holds them with "/"
            push!(out, (b, Logjam._osm_snap_bbox(bb), replace(np, '\\' => '/'), replace(lp, '\\' => '/')))
        end
        _rd(out)
    end)
    # the grid snap on edges that are on the grid (CR 23: v0.2.8 gains a cell on some) and off it
    add("osm_snap_on_grid_edges", () -> begin
        _rd(Tuple(Logjam._osm_snap_bbox(b) for b in
                  ((-78.70, -78.60, 35.70, 35.85), (-78.65, -78.55, 35.75, 35.80), (-78.75, -78.50, 35.70, 35.85),
                   (-79.0, -78.0, 35.0, 36.0), (-78.60, -78.60, 35.75, 35.75))))
    end)
    RDPIN_MOVED["osm_snap_on_grid_edges"] = "CR23"
    add("osm_snap_off_grid_edges", () -> begin
        _rd(Tuple(Logjam._osm_snap_bbox(b) for b in
                  ((-78.688, -78.657, 35.762, 35.796), (-78.63, -78.57, 35.72, 35.83), (-78.641, -78.636, 35.779, 35.784),
                   (-82.45, -82.20, 29.55, 29.75), (-85.0, -80.0, 25.0, 30.0))))
    end)
    # the OSM test fixture translated by the extension (the step osm_roads runs after a download): by value
    # and by type. CR 21 (the posted maxspeed), CR 34 (ways closed to vehicles), CR 24 (the unknown class,
    # the types) move it
    add("osm_fixture_translation_tables", () -> begin
        dfN, dfL = _rd_osm()
        _rd((names(dfN), Matrix(dfN), names(dfL), Matrix(dfL)))
    end)
    add("osm_fixture_translation_types", () -> begin
        dfN, dfL = _rd_osm()
        _rd(_rd_osm_types(dfN, dfL))
    end)
    RDPIN_MOVED["osm_fixture_translation_tables"] = "CR21+CR24+CR34"
    RDPIN_MOVED["osm_fixture_translation_types"] = "CR21+CR24+CR34"
    RDPIN_MOVED["l42_cb6_osm_fixture_two_graphs"] = "CR21+CR24+CR34"
    # the fixture's tables written as a cache pair and read back through osm_roads(bbox; cache_dir): the flat box
    add("osm_fixture_cache_roundtrip", () -> begin
        dfN, dfL = _rd_osm()
        mktempdir() do tmp
            flat = (-78.641, -78.636, 35.779, 35.784)
            np, lp = Logjam._osm_cache_path(flat, tmp)
            CSV.write(np, dfN)
            CSV.write(lp, dfL)
            cN, cL = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
                osm_roads(flat; cache_dir = tmp)
            end
            _rd((_rd_osm_values(cN, cL), _rd_osm_types(cN, cL), basename(np), basename(lp)))
        end
    end)
    RDPIN_MOVED["osm_fixture_cache_roundtrip"] = "CR21+CR24+CR34"

    # the connector search itself, on seeded random nodes: some points inside the hull and some outside
    add("random_net_connectors_100", () -> begin
        N, L, x, y = _rd_random_net(100, 40)
        N2, L2 = addconnectors(N, L, x, y; add_nf_nf = false)
        _rd((nrow(N2), nrow(L2), _rd_conn(L2)))
    end)
    add("random_net_connectors_3000", () -> begin
        N, L, x, y = _rd_random_net(3000, 60)
        N2, L2 = addconnectors(N, L, x, y; add_nf_nf = false)
        _rd((nrow(N2), nrow(L2), _rd_conn(L2)))
    end)
    add("random_net_connectors_nf_true", () -> begin
        N, L, x, y = _rd_random_net(500, 12)
        N2, L2 = addconnectors(N, L, x, y; add_nf_nf = true)
        _rd((nrow(N2), nrow(L2), _rd_conn(L2)))
    end)

    # shortestpaths and tracepath on a small directed graph, in the forms the course calls
    add("shortestpaths_tracepath_small", () -> begin
        g = SimpleWeightedDiGraph([1, 1, 2, 3, 4, 2], [2, 3, 4, 4, 1, 3], [1.0, 4.0, 2.0, 1.0, 3.0, 1.5]; combine = min)
        D, P = shortestpaths(g, 4)
        W = weights(g)
        D2, P2 = shortestpaths(g, W, 4)
        _rd((D, P, D2, P2, tracepath(P[1], 1, 4), tracepath(P[2], 2, 1)))
    end)
    return cases
end
