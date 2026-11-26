# test_joinroads.jl -- an OpenStreetMap network joined to the U.S. road network at its box's edge (CR 19, his ruling
# RD3, PCV N3b; the box a required argument and the routes to Greensboro and Winston-Salem by his rulings RN22 and
# RN21). T4.6 on synthetic networks (a national road crossing the box edge, a road ending inside, a one-way pair, a link
# passing through the box, FAF5's class 0, a road with no street of an adjacent class at the edge) and on Lecture 4.2's
# larger Raleigh pair joined to usrdnode() and usrdlink(), read from the lecture's committed data through
# LOGJAM_LECTURE_DATA, no network; T4.7 for the joined table. The expected Raleigh numbers are N3b's measurements.

using Test
using Logjam
using DataFrames
using Graphs, SimpleWeightedGraphs

const _JR = joinroads                   # the one place the tests name it (the name kept in his interface review, RN36)

# A network built road by road in longitude and latitude; a node is made the first time a road names its point.
struct _JRNet
    pts::Vector{Tuple{Float64,Float64}}
    rows::Vector{Tuple{Int,Int,Int,Int,Int,Union{Missing,String}}}   # (SRC, DST, DIR, FCLASS, SPEED, NAME)
end
_JRNet() = _JRNet(Tuple{Float64,Float64}[], Tuple{Int,Int,Int,Int,Int,Union{Missing,String}}[])
_jrnode!(n, p) = (i = findfirst(==(p), n.pts); i === nothing ? (push!(n.pts, p); length(n.pts)) : i)
_jrat(n, p) = findfirst(==(p), n.pts)
# a street as osm_roads gives one: a link for each way it can be driven, each with DIR 1
function _jrstreet!(n, pts; fc, speed, name = missing, oneway = false)
    for i in 1:length(pts)-1
        a, b = _jrnode!(n, pts[i]), _jrnode!(n, pts[i+1])
        push!(n.rows, (a, b, 1, fc, speed, name))
        oneway || push!(n.rows, (b, a, 1, fc, speed, name))
    end
end
# a national link, its DIR as usrdlink writes it
_jrlink!(n, p, q; fc, speed, dir = 0, name = missing) = push!(n.rows, (_jrnode!(n, p), _jrnode!(n, q), dir, fc, speed, name))
_jrdist(n, r) = dgc(n.pts[r[1]], n.pts[r[2]])

function _jrosm(n)
    N = DataFrame(IDX = collect(1:length(n.pts)), LON = first.(n.pts), LAT = last.(n.pts), SOURCE = fill("OSM", length(n.pts)))
    L = DataFrame(SRC = [r[1] for r in n.rows], DST = [r[2] for r in n.rows], DIST = [_jrdist(n, r) for r in n.rows],
                  SPEED = [r[5] for r in n.rows], FCLASS = [r[4] for r in n.rows], DIR = [r[3] for r in n.rows],
                  NAME = Union{Missing,String}[r[6] for r in n.rows], SOURCE = fill("OSM", length(n.rows)))
    return N, L
end
# the national tables in usrdnode's and usrdlink's shape: node numbers from 1001, as FAF5's are not 1 to n
function _jrnational(n)
    m = length(n.rows)
    N = DataFrame(IDX = 1000 .+ collect(1:length(n.pts)), LON = first.(n.pts), LAT = last.(n.pts), SOURCE = fill("FAF5", length(n.pts)))
    d = [_jrdist(n, r) for r in n.rows]; v = [r[5] for r in n.rows]
    L = DataFrame(SRC = [1000 + r[1] for r in n.rows], DST = [1000 + r[2] for r in n.rows], DIST = d, SPEED = v,
                  FCLASS = [r[4] for r in n.rows], DIR = [r[3] for r in n.rows], NAME = Union{Missing,String}[r[6] for r in n.rows],
                  SOURCE = fill("FAF5", m), SIGN = Union{Missing,String}[r[6] for r in n.rows],
                  TYPE = Union{Missing,String}[r[4] == 1 ? "I" : missing for r in n.rows], INTERSTATE = [r[4] == 1 for r in n.rows],
                  AB_TIME = 60 .* d ./ v .* 1.01, BA_TIME = 60 .* d ./ v .* 1.02, STFIP = fill(37, m), COFIP = fill(37183, m),
                  URBAN = Union{Missing,Int}[fill(1, m)...])
    return N, L
end

# The city: streets in the box lon -78.70 to -78.60, lat 35.75 to 35.85 (its nodes' extent). A divided freeway along lat
# 35.80, its eastbound carriageway on the north, with a diamond's ramps to a two-way arterial along lon -78.65; local
# streets along lat 35.76 and 35.84 and lon -78.69; a divided trunk road entering from the south near lon -78.61.
function _jrcity()
    n = _JRNet()
    xs = [-78.70, -78.68, -78.66, -78.64, -78.62, -78.60]
    _jrstreet!(n, [(x, 35.8003) for x in xs]; fc = 1, speed = 65, name = "Freeway", oneway = true)
    _jrstreet!(n, [(x, 35.7997) for x in reverse(xs)]; fc = 1, speed = 65, name = "Freeway", oneway = true)
    _jrstreet!(n, [(-78.66, 35.8003), (-78.65, 35.79)]; fc = 1, speed = 45, oneway = true)            # the ramps
    _jrstreet!(n, [(-78.65, 35.81), (-78.64, 35.8003)]; fc = 1, speed = 45, oneway = true)
    _jrstreet!(n, [(-78.64, 35.7997), (-78.65, 35.81)]; fc = 1, speed = 45, oneway = true)
    _jrstreet!(n, [(-78.65, 35.79), (-78.66, 35.7997)]; fc = 1, speed = 45, oneway = true)
    _jrstreet!(n, [(-78.65, y) for y in [35.75, 35.76, 35.77, 35.79, 35.81, 35.83, 35.84, 35.85]]; fc = 3, speed = 45, name = "Main Ave")
    blocks = [round(-78.70 + 0.01i, digits = 2) for i in 0:10]
    _jrstreet!(n, [(x, 35.76) for x in blocks]; fc = 7, speed = 25, name = "First St")
    _jrstreet!(n, [(x, 35.84) for x in blocks]; fc = 7, speed = 25, name = "Ninth St")
    _jrstreet!(n, [(-78.69, y) for y in [35.75, 35.76, 35.84, 35.85]]; fc = 7, speed = 25, name = "Side St")
    _jrstreet!(n, [(-78.6097, 35.75), (-78.6097, 35.755), (-78.61, 35.76)]; fc = 2, speed = 55, name = "Trunk Rd", oneway = true)
    _jrstreet!(n, [(-78.61, 35.76), (-78.6103, 35.755), (-78.6103, 35.75)]; fc = 2, speed = 55, name = "Trunk Rd", oneway = true)
    return n
end

# The national roads around it (named by letter in the comments of the testset).
const _JR_PT = Dict('A' => (-79.00, 35.80), 'B' => (-78.80, 35.80), 'C' => (-78.65, 35.80), 'D' => (-78.50, 35.80),
                    'E' => (-78.30, 35.80), 'F' => (-78.65, 35.95), 'G' => (-78.65, 35.82), 'H' => (-78.62, 35.82),
                    'J' => (-78.6105, 35.76), 'K' => (-78.6105, 35.70), 'M' => (-78.6095, 35.70), 'Q' => (-78.6095, 35.76),
                    'R' => (-78.72, 35.79), 'S' => (-78.67, 35.72), 'T' => (-78.69, 35.90), 'U' => (-78.69, 35.84))
function _jrnation()
    n = _JRNet(); P = _JR_PT
    for (a, b) in (('A', 'B'), ('B', 'C'), ('C', 'D'), ('D', 'E'))
        _jrlink!(n, P[a], P[b]; fc = 1, speed = 65, name = "I 40")                     # crossing the box edge twice
    end
    _jrlink!(n, P['F'], P['G']; fc = 3, speed = 55, name = "US 70")                    # a road ending inside
    _jrlink!(n, P['G'], P['H']; fc = 3, speed = 55, name = "US 70")
    _jrlink!(n, P['J'], P['K']; fc = 2, speed = 55, dir = 1, name = "US 1")            # a one-way pair: southbound out
    _jrlink!(n, P['M'], P['Q']; fc = 2, speed = 55, dir = 1, name = "US 1")            # and northbound in
    _jrlink!(n, P['R'], P['S']; fc = 4, speed = 45, name = "SR 1010")                  # through the box's corner
    _jrlink!(n, P['T'], P['U']; fc = 0, speed = 35)                                    # FAF5's class 0
    return n
end

# The distance in miles from a point in the box to its nearest edge, and whether a point is in the box.
_jredge(p, b) = min(dgc(p, (b[1], p[2])), dgc(p, (b[2], p[2])), dgc(p, (p[1], b[3])), dgc(p, (p[1], b[4])))
_jrin(p, b) = b[1] <= p[1] <= b[2] && b[3] <= p[2] <= b[4]
# whether any of 101 points along a link's straight line lies in the box (independent of the clipping joinroads does)
_jrmeets(p, q, b) = any(t -> _jrin((p[1] + t * (q[1] - p[1]), p[2] + t * (q[2] - p[2])), b), range(0, 1, length = 101))

# The connectors of a joined table, each with its OpenStreetMap end's classes and whether those include one its national
# road joins (`Logjam._join_classes`, the table of the docstring); a connector whose OSM end has none is a fallback.
function _jrconnectors(dfN, dfL)
    cls = Dict{Int,Set{Int}}()
    for k in findall(==("OSM"), dfL.SOURCE), v in (dfL.SRC[k], dfL.DST[k])
        push!(get!(cls, v, Set{Int}()), dfL.FCLASS[k])
    end
    C = dfL[dfL.SOURCE .== "CONNECTOR", :]
    C.OSMCLASSES = [get(cls, v, Set{Int}()) for v in C.DST]
    C.ADJACENT = [!isempty(intersect(c, Logjam._join_classes(f))) for (c, f) in zip(C.OSMCLASSES, C.FCLASS)]
    return C
end

# The links along a path of node numbers: for each arc, the link of the wanted SOURCE that can be driven along it.
function _jrpathlinks(L, p, source)
    arcs = Dict((p[i], p[i+1]) => i for i in 1:length(p)-1)
    ks = zeros(Int, length(p) - 1)
    for k in 1:nrow(L)
        isequal(L.SOURCE[k], source) || continue
        for (a, b, ok) in ((L.SRC[k], L.DST[k], L.DIR[k] != -1), (L.DST[k], L.SRC[k], L.DIR[k] != 1))
            i = get(arcs, (a, b), 0)
            ok && i > 0 && ks[i] == 0 && (ks[i] = k)
        end
    end
    return ks
end

@testset "joinroads: T4.6 on synthetic networks (RD3)" begin
    city = _jrcity(); nat = _jrnation()
    No, Lo = _jrosm(city); N, L = _jrnational(nat)
    bb = ((-78.70, -78.60), (35.75, 35.85))                                     # the city's box, as osm_roads takes it
    copies = deepcopy.((N, L, No, Lo, bb))
    dfN, dfL = _JR(N, L, No, Lo, bb)
    @test isequal((N, L, No, Lo, bb), copies)                                   # none of the five is changed
    b = (bb[1]..., bb[2]...)
    @test (minimum(No.LON), maximum(No.LON), minimum(No.LAT), maximum(No.LAT)) == b   # the streets fill it
    xy(v) = (dfN.LON[v], dfN.LAT[v])
    natpt(v) = only(c for (c, p) in _JR_PT if p == xy(v))                       # a national node's letter
    osmpt(v) = xy(v)

    @testset "the box: no national node or link inside it; OpenStreetMap's links all kept" begin
        @test sort(unique(dfL.SOURCE)) == ["CONNECTOR", "FAF5", "OSM"]
        f = findall(==("FAF5"), dfL.SOURCE)
        @test sort([string(natpt(dfL.SRC[k]), natpt(dfL.DST[k])) for k in f]) == ["AB", "DE"]
        @test !any(k -> _jrmeets(xy(dfL.SRC[k]), xy(dfL.DST[k]), b), f)
        @test all(v -> !_jrin(xy(v), b), findall(==("FAF5"), dfN.SOURCE))
        @test sort([natpt(v) for v in findall(==("FAF5"), dfN.SOURCE)]) == ['A', 'B', 'D', 'E', 'F', 'K', 'M', 'R', 'S', 'T']
        @test count(==("OSM"), dfL.SOURCE) == nrow(Lo) && count(==("OSM"), dfN.SOURCE) == nrow(No)
        @test dfN.IDX == 1:nrow(dfN) && all(in(1:nrow(dfN)), dfL.SRC) && all(in(1:nrow(dfN)), dfL.DST)   # numbered 1 to n
        @test Set([dfL.SRC; dfL.DST]) == Set(1:nrow(dfN))                                                 # every node on a link
        @test findall(==("FAF5"), dfN.SOURCE) == 1:10                                                     # the national nodes first
    end

    @testset "the connectors: at the edge, of an adjacent class, each way the national road is driven" begin
        C = _jrconnectors(dfN, dfL)
        got = sort([(natpt(r.SRC), osmpt(r.DST), r.DIR) for r in eachrow(C)])
        want = sort([('B', (-78.70, 35.8003), 1), ('B', (-78.70, 35.7997), -1),     # I 40 west: each carriageway its way
                      ('D', (-78.60, 35.7997), 1), ('D', (-78.60, 35.8003), -1),     # I 40 east
                      ('F', (-78.65, 35.85), 0),                                    # US 70, ending inside: the arterial, two-way
                      ('K', (-78.6103, 35.75), -1),                                 # US 1 southbound, out of the box only
                      ('M', (-78.6097, 35.75), 1),                                  # US 1 northbound, into it only
                      ('R', (-78.70, 35.76), 0), ('S', (-78.69, 35.75), 0),         # through the corner: both ends, local streets
                      ('T', (-78.69, 35.85), 0)])                                   # FAF5's class 0: any class
        @test got == want
        @test all(v -> !_jrin(xy(v), b), C.SRC) && all(v -> _jrin(xy(v), b), C.DST)
        @test maximum(_jredge(xy(v), b) for v in C.DST) <= Logjam._JOIN_RADIUS
        @test C.DIST ≈ [dgc(xy(s), xy(d)) for (s, d) in zip(C.SRC, C.DST)]
        # adjacent classes, but for the one road with no street of an adjacent class at the edge: counted as fallbacks
        @test sort([natpt(r.SRC) for r in eachrow(C) if !r.ADJACENT]) == ['R', 'S']
        # the slower road's speed, the national road's class and name
        sp = Dict(natpt(r.SRC) => r.SPEED for r in eachrow(C))
        @test (sp['B'], sp['F'], sp['K'], sp['R'], sp['T']) == (65, 45, 55, 25, 25)
        @test all(r -> r.FCLASS == Dict('B' => 1, 'D' => 1, 'F' => 3, 'K' => 2, 'M' => 2, 'R' => 4, 'S' => 4, 'T' => 0)[natpt(r.SRC)], eachrow(C))
        @test isequal(C.NAME[[natpt(v) == 'F' for v in C.SRC]], ["US 70"]) && all(ismissing, C.NAME[[natpt(v) == 'T' for v in C.SRC]])
        @test_logs (:info, r"8 national links and 6 national nodes dropped.*10 connectors for 8 link ends \(4 two-way\), 2 to a road") _JR(N, L, No, Lo, bb; verbose = true)
    end

    @testset "the columns (T4.7): osm_roads' first eight, then the national extras, missing off the national links" begin
        spec = Logjam._OSM_LINK_TYPES[1:8]
        @test names(dfL) == [first.(spec); names(L)[9:end]]
        @test eltype.(eachcol(dfL))[1:8] == last.(spec)
        V = vcat(dfL[:, 1:8], Lo[:, 1:8])
        @test nrow(V) == nrow(dfL) + nrow(Lo) && eltype.(eachcol(V)) == last.(spec)
        nat = dfL.SOURCE .== "FAF5"
        for c in names(L)[9:end]
            @test all(ismissing, dfL[.!nat, c]) && !any(ismissing, dfL[nat, c])
        end
        @test names(dfN) == ["IDX", "LON", "LAT", "SOURCE"]
    end

    @testset "routes on distance and on time, through the connectors" begin
        id(c) = findfirst(v -> dfN.SOURCE[v] == "FAF5" && xy(v) == _JR_PT[c], 1:nrow(dfN))
        for w in (3, :time)
            g = links2graph(dfL; weight = w)
            for (a, z, via) in (('A', 'E', (-78.70, 35.8003)), ('E', 'A', (-78.60, 35.7997)))
                p = tracepath(dijkstra_shortest_paths(g, id(a)).parents, id(a), id(z))
                src = [only(unique(dfL.SOURCE[k] for k in 1:nrow(dfL) if (dfL.SRC[k], dfL.DST[k]) in ((p[i], p[i+1]), (p[i+1], p[i])) &&
                       (dfL.DIR[k] == 0 || (dfL.DIR[k] == 1) == (dfL.SRC[k] == p[i])))) for i in 1:length(p)-1]
                @test src == ["FAF5"; "CONNECTOR"; fill("OSM", 5); "CONNECTOR"; "FAF5"] && xy(p[3]) == via   # on the freeway's carriageway
            end
            ds = dijkstra_shortest_paths(g, id('M')).dists
            @test isfinite(ds[id('F')]) && isfinite(dijkstra_shortest_paths(g, id('F')).dists[id('K')])    # the one-way pair, into and out of
        end
        # minutes: a national link's own times, 60 DIST / SPEED on a street and a connector
        W = weights(links2graph(dfL; weight = :time))
        k = findfirst(r -> r.SOURCE == "CONNECTOR" && r.DIR == 0, eachrow(dfL))
        @test W[dfL.SRC[k], dfL.DST[k]] ≈ 60 * dfL.DIST[k] / dfL.SPEED[k]
        k = findfirst(r -> r.SOURCE == "OSM", eachrow(dfL))
        @test W[dfL.SRC[k], dfL.DST[k]] ≈ 60 * dfL.DIST[k] / dfL.SPEED[k]
        k = findfirst(==("FAF5"), dfL.SOURCE)
        @test W[dfL.SRC[k], dfL.DST[k]] == dfL.AB_TIME[k] && W[dfL.DST[k], dfL.SRC[k]] == dfL.BA_TIME[k]
    end

    @testset "the box crops the streets to it (RN22: the box is required)" begin
        bb2 = ((-78.70, -78.62), (35.75, 35.85))                               # narrower than the streets
        jN, jL = _JR(N, L, No, Lo, bb2)
        b2 = (-78.70, -78.62, 35.75, 35.85)
        @test all(v -> _jrin((jN.LON[v], jN.LAT[v]), b2), findall(==("OSM"), jN.SOURCE))
        @test all(v -> !_jrin((jN.LON[v], jN.LAT[v]), b2), findall(==("FAF5"), jN.SOURCE))
        f = findall(==("FAF5"), jL.SOURCE)
        @test !any(k -> _jrmeets((jN.LON[jL.SRC[k]], jN.LAT[jL.SRC[k]]), (jN.LON[jL.DST[k]], jN.LAT[jL.DST[k]]), b2), f)
        @test count(==("FAF5"), jL.SOURCE) == 4                                  # A-B, D-E, and US 1's pair, now outside
        @test isequal(_JR(N, L, No, Lo, b2), (jN, jL))                         # the four numbers alike
        Nc, Lc = cropnetwork(No, Lo, bb2)
        @test isequal(_JR(N, L, Nc, Lc, bb2), (jN, jL))                         # the same as the streets cropped first
    end

    @testset "errors and the warning" begin
        @test_throws MethodError _JR(N, L, No, Lo)                              # no box (RN22)
        @test_throws ArgumentError _JR(N, select(L, Not(:SPEED)), No, Lo, bb)
        @test_throws ArgumentError _JR(N, L, select(No, Not(:LAT)), Lo, bb)
        @test_throws ArgumentError _JR(N, L, No, Lo, ((-78.6, -78.7), (35.75, 35.85)))
        @test_throws ArgumentError _JR(N, L, No, Lo, ((-80.0, -79.9), (35.0, 35.1)))       # no street in it
        @test_throws ArgumentError _JR(N, L, No, Lo, (-78.70, -78.60, 35.75))              # three numbers
        @test_throws ArgumentError _JR(N, L, No, Lo, bb; radius = -1)
        L2 = copy(L); L2.DIR[1] = 2
        @test_throws ArgumentError _JR(N, L2, No, Lo, bb)
        far = filter(r -> r.SRC in (1001, 1002) && r.DST in (1001, 1002), L)    # A-B alone: nothing crosses the edge
        @test_logs (:warn, r"not joined") _JR(N, far, No, Lo, bb)
    end
end

@testset "joinroads: T4.6 on Lecture 4.2's larger Raleigh pair and the U.S. road network (RD3, no network)" begin
    lec = get(ENV, "LOGJAM_LECTURE_DATA", "")
    tile = (-78.75, -78.55, 35.7, 35.85)                                         # 4.2 Ex. 3's tile (its data README)
    np, lp = isempty(lec) ? ("", "") : Logjam._osm_cache_path(tile, lec)
    if !(isfile(np) && isfile(lp))
        @info "Lecture 4.2 not reachable (LOGJAM_LECTURE_DATA): its Raleigh pair not joined"
    else
        bb = ((tile[1], tile[2]), (tile[3], tile[4]))                            # the box given to osm_roads (RN22)
        Nosm, Losm = osm_roads(bb; cache_dir = lec, crop = true)                 # the pair read, cropped to its tile
        N0, L0 = usrdnode(), usrdlink()
        _JR(N0, L0, Nosm, Losm, bb)                                              # compiled first, then timed
        t = @elapsed ((dfN, dfL) = _JR(N0, L0, Nosm, Losm, bb))
        b = tile
        # the whole tile, read without crop, joins as the pair cropped to it does (RN22)
        @test isequal(_JR(N0, L0, osm_roads(bb; cache_dir = lec)..., bb), (dfN, dfL))
        xy(v) = (dfN.LON[v], dfN.LAT[v])
        f = findall(==("FAF5"), dfL.SOURCE)
        C = _jrconnectors(dfN, dfL)
        nfb = count(!, C.ADJACENT); edge = maximum(_jredge(xy(v), b) for v in C.DST)
        println("  joinroads T4.6, 4.2's Raleigh pair (", nrow(Nosm), " nodes, ", nrow(Losm), " links) and usrdnode()/usrdlink(): ",
                round(t, digits = 2), " s; national links dropped ", nrow(L0) - length(f), ", nodes ", nrow(N0) - count(==("FAF5"), dfN.SOURCE),
                "; connectors ", nrow(C), " (two-way ", count(==(0), C.DIR), "), fallbacks ", nfb, ", farthest from the edge ",
                round(edge, digits = 3), " mi; joined ", nrow(dfN), " nodes, ", nrow(dfL), " links")
        @test sort(unique(dfL.SOURCE)) == ["CONNECTOR", "FAF5", "OSM"]
        @test dfN.IDX == 1:nrow(dfN) && all(in(1:nrow(dfN)), dfL.SRC) && all(in(1:nrow(dfN)), dfL.DST)
        # no national link inside the box survives: neither end inside, and no straight line through it
        near = [k for k in f if max(xy(dfL.SRC[k])[1], xy(dfL.DST[k])[1]) >= b[1] && min(xy(dfL.SRC[k])[1], xy(dfL.DST[k])[1]) <= b[2] &&
                                max(xy(dfL.SRC[k])[2], xy(dfL.DST[k])[2]) >= b[3] && min(xy(dfL.SRC[k])[2], xy(dfL.DST[k])[2]) <= b[4]]
        @test !any(k -> _jrmeets(xy(dfL.SRC[k]), xy(dfL.DST[k]), b), near)
        @test all(v -> !_jrin(xy(v), b), findall(==("FAF5"), dfN.SOURCE))
        @test count(==("OSM"), dfL.SOURCE) == nrow(Losm)
        # every connector at the box edge, from a national node outside it, joining roads of the same or an adjacent class
        @test all(v -> !_jrin(xy(v), b), C.SRC) && all(v -> dfN.SOURCE[v] == "FAF5", C.SRC) && all(v -> dfN.SOURCE[v] == "OSM", C.DST)
        @test edge <= Logjam._JOIN_RADIUS
        @test nfb == 0                                                           # N3b: none on this pair
        @test (nrow(C), count(==(0), C.DIR)) == (33, 5)                          # N3b: 19 link ends, 14 at divided streets
        # T4.7: the joined table stacks with osm_roads'
        spec = Logjam._OSM_LINK_TYPES[1:8]
        @test names(dfL)[1:8] == first.(spec) && eltype.(eachcol(dfL))[1:8] == last.(spec)
        @test eltype.(eachcol(vcat(dfL[:, 1:8], Losm[:, 1:8]))) == last.(spec)
        # Routes from 4.1's Raleigh point, inside the box, to its Greensboro, Winston-Salem and Charlotte (Code block 47's
        # places), on distance and on time: where each leaves the box, the national road it joins
        pl = filter(r -> r.STFIP == st2fips(:NC) && r.POP > 100_000, usplace())
        P = pl[[findfirst(==(c), pl.NAME) for c in ("Raleigh", "Greensboro", "Winston-Salem", "Charlotte")], [:NAME, :LON, :LAT]]
        @test _jrin((P.LON[1], P.LAT[1]), b) && !any(j -> _jrin((P.LON[j], P.LAT[j]), b), 2:4)
        Na, La = addconnectors(dfN, dfL, P.LON, P.LAT; speed = 20)
        inb(v) = _jrin((Na.LON[v], Na.LAT[v]), b)
        for (lab, w) in (("shortest", 3), ("fastest", :time))
            ds = dijkstra_shortest_paths(links2graph(La; weight = w), 1)
            for j in 2:4
                p = tracepath(ds.parents, 1, j)
                m = findfirst(i -> inb(p[i]) && !inb(p[i+1]), 1:length(p)-1)
                kc = only(k for k in _jrpathlinks(La, p[m:m+1], "CONNECTOR"))   # the crossing: one of joinroads' connectors
                kf = only(_jrpathlinks(La, p[m+1:m+2], "FAF5"))                   # and the national link after it
                @test kc > 0 && !ismissing(La.FCLASS[kc]) && kf > 0
                println("  joinroads T4.6: the ", lab, " route from Raleigh to ", P.NAME[j], " (", round(ds.dists[j], digits = 2),
                        w === :time ? " min" : " mi", ") leaves the box on ", coalesce(La.NAME[kc], "an unnamed road"), " (class ",
                        La.FCLASS[kc], "), then ", coalesce(La.SIGN[kf], "-"), La.INTERSTATE[kf] ? ", an Interstate" : ", not an Interstate")
                # RN21 (his ruling on round n3): the fastest routes to Greensboro and Winston-Salem leave the box on an
                # Interstate (I 40). Charlotte's is printed only: from every point N3b measured it leaves on US 1, a
                # freeway, by FAF5's own times, as the derived network alone routes it from downtown.
                lab == "fastest" && P.NAME[j] in ("Greensboro", "Winston-Salem") && @test La.INTERSTATE[kf] === true
            end
        end
    end
end
