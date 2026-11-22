# test_faf5net.jl -- the derived FAF5 road network (CR 19), on synthetic cases and on FAF5 as Logjam ships it. Part one
# (PCV N1): route keys, the Interstate flag, the ramp rule and the junctions (his rulings RN3 to RN10, RN17). Part two
# (PCV N2): the derivation (RN13 to RN19). Part three (PCV N3): the shipped data and its accessors (D7, RD1, RD2) and
# the checks of SC 1 (T1.3, T1.4), SC 3 (T3.1 to T3.3) and SC 4 (T4.1 to T4.5, T4.7). The expected FAF5 counts are N0's
# measurements where N0 measured the same thing, and N1's or N2's own otherwise (each says which).

using Test
using Logjam
using DataFrames
using Graphs, SimpleWeightedGraphs
using CairoMakie, GeoMakie            # the map extension, whose v0.3.0 ramp rule stays as it is until N4

const LJ = Logjam

# A FAF5-shaped link table from (SRC, DST, DIR, FCLASS, SIGN, NAME) rows.
function _fnlinks(rows)
    DataFrame(SRC = [r[1] for r in rows], DST = [r[2] for r in rows], DIR = [r[3] for r in rows],
              FCLASS = [r[4] for r in rows], SIGN = Union{Missing,String}[r[5] for r in rows],
              NAME = Union{Missing,String}[r[6] for r in rows], DIST = fill(0.1, length(rows)))
end

# A synthetic network laid out in meters east and north of a point near Raleigh: nodes are made as links name them.
struct _FNNet
    xy::Vector{Tuple{Float64,Float64}}
    rows::Vector{Tuple{Int,Int,Int,Int,Union{Missing,String},Union{Missing,String}}}
end
_FNNet() = _FNNet(Tuple{Float64,Float64}[], Tuple{Int,Int,Int,Int,Union{Missing,String},Union{Missing,String}}[])
_fnnode!(n, p) = (i = findfirst(==(p), n.xy); i === nothing ? (push!(n.xy, p); length(n.xy)) : i)
_fnlink!(n, a, b; dir = 0, fc = 3, sign = missing, name = missing) =
    push!(n.rows, (_fnnode!(n, a), _fnnode!(n, b), dir, fc, sign, name))
_fnroad!(n, pts; kw...) = foreach(i -> _fnlink!(n, pts[i], pts[i+1]; kw...), 1:length(pts)-1)
function _fntables(n; lon0 = -78.6, lat0 = 35.8)
    N = DataFrame(IDX = 1:length(n.xy), LON = [lon0 + x / (111320 * cosd(lat0)) for (x, _) in n.xy],
                  LAT = [lat0 + y / 110540 for (_, y) in n.xy])
    return N, _fnlinks(n.rows)
end
# a freeway along y = 0, its carriageways 30 m apart, eastbound on the north side, with nodes at the given x
function _fnfreeway!(n, xs; sign = "I 40", fc = 1)
    _fnroad!(n, [(x, 15.0) for x in xs]; dir = 1, fc, sign, name = sign)
    _fnroad!(n, [(x, -15.0) for x in reverse(xs)]; dir = 1, fc, sign, name = sign)
end
# a diamond at x = c: a two-way crossing road along x = c (`south` names its half south of the freeway) and four ramps
function _fndiamond!(n, c, sign; south = sign, unnamed = false)
    _fnroad!(n, [(c, 60.0), (c, 800.0)]; fc = 3, sign)
    _fnroad!(n, [(c, -800.0), (c, -60.0)]; fc = 3, sign = south)
    _fnlink!(n, (c, -60.0), (c, 60.0); fc = 3, sign = south == sign ? sign : missing)   # the bridge: no node on the freeway
    _fnlink!(n, (c - 300, 15.0), (c, 60.0); dir = 1, fc = 1, name = unnamed ? missing : "RAMP")
    _fnlink!(n, (c, 60.0), (c + 300, 15.0); dir = 1, fc = 1, name = "RAMP")
    _fnlink!(n, (c + 300, -15.0), (c, -60.0); dir = 1, fc = 1, name = "RAMP")
    _fnlink!(n, (c, -60.0), (c - 300, -15.0); dir = 1, fc = 1, name = "RAMP")
end
_fnjunctions(n) = (t = _fntables(n); r = LJ._ramp_links(t...); (r, LJ._junctions(t..., r)))

@testset "faf5net: route keys, the Interstate flag, ramps, junctions (N1)" begin
    @testset "_route: one key per road (RN9)" begin
        # state-route prefixes unified (N0's cases of one road under two keys)
        @test LJ._route("FL 429", missing) == LJ._route(missing, "SR 429") == "SR 429"
        for (a, b) in (("OR 99W", "SR 99W"), ("CO 7", "SR 7"), ("SR 7", "VA 7"), ("CA 68", "SR 68"), ("PA 611", "SR 611"))
            @test LJ._route(a, missing) == LJ._route(b, missing) == LJ._route(missing, b)
        end
        @test LJ._route(missing, "STATE HWY 7") == "SR 7"
        # a direction is dropped from an Interstate only; on any other route the letter names the route
        @test LJ._route("I 93 N", missing) == LJ._route("I 93 S", missing) == "I 93"
        @test LJ._route("I 270 S", missing) == "I 270"
        @test LJ._route(missing, "I 496 EB") == "I 496"
        @test LJ._route("US 70 N", missing) == "US 70 N" != LJ._route("US 70 S", missing)
        @test LJ._route("US 70 S", missing) != LJ._route("US 70", missing)
        @test LJ._route("NY 5 S", missing) == "SR 5 S" != LJ._route("NY 5", missing)
        @test LJ._route("GA 204 S", missing) == "SR 204 S"
        @test LJ._route("I 35E", missing) == "I 35E" != LJ._route("I 35W", missing)
        @test LJ._route("MO N", missing) == "MO N"
        # Business routes, and bypasses, are routes of their own
        @test LJ._route("I 40 B", missing) == "I 40 B" != LJ._route("I 40", missing)
        @test LJ._route("TX 71 P", missing) == "SR 71 P" != LJ._route("TX 71", missing)
        @test LJ._route(missing, "I 5 B NB") == "I 5 B"
        # SIGN first, then NAME; a NAME that is not a designation is the road's own name
        @test LJ._route("US 131", "I 296") == "US 131"
        @test LJ._route(missing, "I-296") == "I 296"
        @test LJ._route(missing, "N Rampart  St") == "N RAMPART ST"
        @test LJ._route(missing, "INTERSTATE 40") == "I 40"
        @test LJ._route(missing, missing) === nothing
        @test LJ._route("", "  ") === nothing
    end

    @testset "_isinterstate (RN3, RN8, T2.10)" begin
        @test LJ._isinterstate("US 131", "I 296", 1)                  # I-296, found by its NAME on a class 1 link
        @test !LJ._isinterstate("US 131", "I 296", 2)                 # NAME counts only on class 1
        @test LJ._isinterstate(missing, "I 496 EB", 1)
        @test !LJ._isinterstate("I 40 B", missing, 3)                  # never a Business route
        @test !LJ._isinterstate("I 40 B", "I 40", 1)
        @test !LJ._isinterstate("I 20E B", missing, 2)
        @test LJ._isinterstate("I 93 N", missing, 1) && LJ._isinterstate("I 93 S", missing, 1)
        @test LJ._route("I 93 N", missing) == LJ._route("I 93 S", missing)
        @test LJ._isinterstate("I 35E", missing, 1) && LJ._isinterstate("I 480N", missing, 1)
        for s in ("I A1", "I A4", "I H1", "I H2", "I H201", "I H3")      # Alaska's and Hawaii's (RN8)
            @test LJ._isinterstate(s, missing, 1)
        end
        @test LJ._isinterstate(missing, "I H1", 1) && !LJ._isinterstate("I HA1", missing, 1)
        @test !LJ._isinterstate("US 50", "JOHN HANSON HWY", 1)         # I-595, which FAF5 has only as US 50
        @test !LJ._isinterstate(missing, "I 270 - LOCAL LANES", 1)     # not exactly a designation
        @test !LJ._isinterstate(missing, missing, 1)
    end

    @testset "_isramp_name (RN4, RN10, T2.8)" begin
        for n in ("I 96 EB TO I 696 EB", "COLLECCTOR/DISTRIBUTOR", "I 80 COLLECCTOR/DISTRIBUTOR LANE",
                  "I 75 NB COLLECTOR/DISTRBUTOR LANE", "I 75 WB COLLECTION/DISTRIBUTION LANE",
                  "I 15 SB TO I 515 / US 95 NB", "I 395 SB TO I 95 NB/I 495 IL", "I 5 B NB TO I 90 EB",
                  "CR 200 TO US 27 NB", "RAMP", "I 40 EB RAMP", "COLLECTOR/DISTRIBUTOR LANE", "RI 4 CONNECTOR/DISTRIBUTOR LANE",
                  "TURN LANE", "i 96 eb to i 696 eb",
                  "GRAND RIVER RD TO I 69 EB", "I 196 EB TO CHICAGO DR", "DIBC INSPECTION TO I 75 SB", "I 82 WB TO I !82 EB")
            @test LJ._isramp_name(n, 1) && LJ._isramp_name(n, -1)
        end
        for n in ("GOING TO THE SUN HWY", "DIBC PLAZA TO CANADA", "AIRPORT CONNECTOR", "DOWNTOWN DISTRIBUTOR", "N RAMPART ST",
                  "I-70 EB TURNAROUND/SERVICE ROAD", "", missing)
            @test !LJ._isramp_name(n, 1) && !LJ._isramp_name(n, 0)
        end
        # "X TO Y" is a ramp only on a one-way link; the other parts of the rule do not look at the direction
        @test !LJ._isramp_name("I 96 EB TO I 696 EB", 0) && !LJ._isramp_name("GRAND RIVER RD TO I 69 EB", 0)
        @test LJ._isramp_name("I 40 EB RAMP", 0) && LJ._isramp_name("I 80 COLLECCTOR/DISTRIBUTOR LANE", 0)
        # T2.11: on a link signed as an Interstate, "X TO Y" is a ramp only when both sides are designations (RN12 as
        # narrowed by RN17); the rule's other words reach every link
        @test LJ._isramp_name("I 95 NB APPROACH TO I 80", 1) && !LJ._isramp_name("I 95 NB APPROACH TO I 80", 1, "I 95")
        @test LJ._isramp_name("I 95 SB to I 476 NB", 1, "I 476") && LJ._isramp_name("I 581 NB to I 81 NB", 1, "I 581")
        @test LJ._isramp_name("I 96 EB TO I 696 EB", 1, "I 93 N") && !LJ._isramp_name("GRAND RIVER RD TO I 69 EB", 1, "I 69")
        @test LJ._isramp_name("GRAND RIVER RD TO I 69 EB", 1, "US 1") && !LJ._isramp_name("I 95 SB to I 476 NB", 0, "I 476")
        @test LJ._isramp_name("SYSTEM RAMP - I 35 NB", 1, "I 35") && LJ._isramp_name("I 80 COLLECCTOR/DISTRIBUTOR LANE", 1, "I 80")
        @test LJ._isramp_name("I 96 EB TO I 696 EB", 1, "US 1") && LJ._isramp_name("I 96 EB TO I 696 EB", 1, "I 40 B")
        @test LJ._isramp_name("I 96 EB TO I 696 EB", 1, missing) && LJ._isramp_name("I 96 EB TO I 696 EB", 1, " ")
        # the map keeps v0.3.0's rule until N4, and it is the first part of the rule here
        ext = Base.get_extension(Logjam, :LogjamMapExt)
        @test ext._RAMP_NAME.pattern == LJ._RAMP_WORDS.pattern
        @test ext._isramp("I 40 EB RAMP") && !ext._isramp("I 96 EB TO I 696 EB")
    end

    @testset "_ramp_links: the structural test, by cluster (RN4, T2.8)" begin
        # A freeway (I 40, class 1, two one-way carriageways) crossed by US 1 (class 3, two-way) without a shared node;
        # SR 50 (class 3) to the north. Far to the west, a city block: MAIN ST and ELM ST (class 4).
        N = DataFrame(IDX = 1:20,
                      LON = [-78.62, -78.61, -78.60, -78.62, -78.61, -78.60, -78.61, -78.61, -78.608, -78.62,
                             -78.63, -78.598, -78.597, -80.000, -79.999, -79.998, -80.000, -79.999, -79.998, -78.605],
                      LAT = [35.800, 35.800, 35.800, 35.7995, 35.7995, 35.7995, 35.790, 35.810, 35.803, 35.815,
                             35.815, 35.798, 35.797, 35.200, 35.200, 35.200, 35.201, 35.201, 35.201, 35.797])
        L = _fnlinks([
            (1, 2, 1, 1, "I 40", "I 40"), (2, 3, 1, 1, "I 40", "I 40"),       # 1, 2: eastbound
            (6, 5, 1, 1, "I 40", "I 40"), (5, 4, 1, 1, "I 40", "I 40"),       # 3, 4: westbound
            (7, 9, 0, 3, "US 1", missing), (9, 8, 0, 3, "US 1", missing),     # 5, 6: US 1
            (10, 11, 0, 3, "SR 50", missing),                                  # 7: SR 50
            (2, 9, 1, 3, missing, missing),                                    # 8: unnamed one-way, I 40 to US 1, 0.2 mi: a ramp
            (3, 8, 0, 3, missing, missing),                                    # 9: unnamed but two-way: not a ramp
            (1, 10, 1, 3, missing, missing),                                   # 10: unnamed one-way, I 40 to SR 50, 1.04 mi: too long
            (5, 7, 1, 3, missing, "MAIN ST"),                                  # 11: named, so never structural
            (6, 12, 1, 1, missing, "RAMP"),                                    # 12: a named ramp ...
            (12, 13, 1, 4, missing, missing), (13, 20, 1, 4, missing, missing),  # 13, 14: ... unnamed links beyond it
            (20, 9, 0, 3, "US 1", missing),                                    # 15: US 1 again, where they end
            (14, 15, 0, 4, missing, "MAIN ST"), (15, 16, 0, 4, missing, "MAIN ST"),   # 16, 17: city block
            (17, 18, 0, 4, missing, "ELM ST"), (18, 19, 0, 4, missing, "ELM ST"),     # 18, 19
            (15, 18, 1, 4, missing, missing),                                  # 20: unnamed one-way between two class 4 streets
        ])
        r = LJ._ramp_links(N, L)
        @test r isa Vector{Bool} && length(r) == nrow(L)
        @test r[8]                                  # touches I 40 (class 1) and US 1, within 0.75 mi
        @test !r[9]                                 # two-way
        @test !r[10]                                # its cluster spans more than 0.75 mi
        @test !r[11]                                # named
        @test r[12] && r[13] && r[14]               # the named ramp by name; the unnamed links with it, by cluster
        @test !r[20]                                # a city block touching only class 4 streets
        @test !any(r[[1:7; 15:19]])                 # the roads
        # the same unnamed link joined to a class 2 road is a ramp; to class 3 to 5 only, it is not
        L2 = copy(L); L2.FCLASS[1:4] .= 2
        @test LJ._ramp_links(N, L2)[8]
        L3 = copy(L); L3.FCLASS[1:4] .= 4; L3.FCLASS[12] = 4
        @test !LJ._ramp_links(N, L3)[8] && !LJ._ramp_links(N, L3)[13]
        @test_throws ArgumentError LJ._ramp_links(N[1:19, :], L)    # a link to a node the table lacks
    end

    @testset "_junctions: T2.7's synthetic cases (RN6, RN7)" begin
        # a diamond is one junction; its unnamed off-ramp is found by the structural test
        n = _FNNet(); _fnfreeway!(n, [-2000.0, -300.0, 300.0, 2000.0]); _fndiamond!(n, 0.0, "SR 54"; unnamed = true)
        r, J = _fnjunctions(n)
        @test count(r) == 4
        @test length(J.site) == 1 && J.kind == [:interchange] && J.cl[J.site[1]] == 1
        @test count(>(0), J.cl) == 6                   # the four freeway nodes and the two terminals the ramps join
        cl, site = J                                   # destructures as (cl, site)
        @test cl === J.cl && site === J.site
        # a diamond whose crossing road changes name at the freeway (an unnamed bridge between): its two halves share
        # only I 40, and are one junction by RN6's 0.25 mi (their centers 60 m apart)
        n = _FNNet(); _fnfreeway!(n, [-2000.0, -300.0, 300.0, 2000.0]); _fndiamond!(n, 0.0, "SR 54"; south = "MAIN ST")
        @test length(_fnjunctions(n)[2].site) == 1
        # a cloverleaf, its loops and its outer connections ("I 40 EB TO US 1 NB") separate clusters, is one junction
        n = _FNNet(); _fnfreeway!(n, [-2000.0, -400.0, -150.0, 150.0, 400.0, 2000.0])
        _fnroad!(n, [(15.0, y) for y in (-2000.0, -400.0, -150.0, 150.0, 400.0, 2000.0)]; dir = 1, fc = 2, sign = "US 1")
        _fnroad!(n, [(-15.0, y) for y in (2000.0, 400.0, 150.0, -150.0, -400.0, -2000.0)]; dir = 1, fc = 2, sign = "US 1")
        for (f, l, x) in (((150.0, 15.0), (200.0, 200.0), (-15.0, 150.0)), ((-150.0, -15.0), (-200.0, -200.0), (15.0, -150.0)),
                          ((-150.0, 15.0), (-200.0, 200.0), (15.0, 150.0)), ((150.0, -15.0), (200.0, -200.0), (-15.0, -150.0)))
            _fnlink!(n, f, l; dir = 1, fc = 1, name = "RAMP"); _fnlink!(n, l, x; dir = 1, fc = 1, name = "RAMP")
        end
        for (a, b) in (((-400.0, 15.0), (15.0, -400.0)), ((15.0, 400.0), (400.0, 15.0)), ((400.0, -15.0), (-15.0, 400.0)),
                       ((-15.0, -400.0), (-400.0, -15.0)))
            _fnlink!(n, a, b; dir = 1, fc = 1, name = "I 40 EB TO US 1 NB")
        end
        r, J = _fnjunctions(n)
        @test count(r) == 12 && length(J.site) == 1 && J.kind == [:interchange]
        # two interchanges 1.0 mi apart with different crossings stay two (RN6; 4.1's 1.5 mi merge alone joined them)
        n = _FNNet(); _fnfreeway!(n, [-2000.0, -300.0, 300.0, 1309.0, 1909.0, 4000.0])
        _fndiamond!(n, 0.0, "SR 54"); _fndiamond!(n, 1609.0, "US 1")
        @test length(_fnjunctions(n)[2].site) == 2
        # two ramps between the same two roads, their centers 1.1 mi apart, share both routes and are one junction (RN6)
        n = _FNNet(); _fnfreeway!(n, [-2000.0, -300.0, 1750.0, 3000.0])
        _fnroad!(n, [(-2000.0, 60.0), (0.0, 60.0), (1450.0, 60.0), (3000.0, 60.0)]; fc = 3, sign = "US 1")
        _fnlink!(n, (-300.0, 15.0), (0.0, 60.0); dir = 1, fc = 1, name = "RAMP")
        _fnlink!(n, (1450.0, 60.0), (1750.0, 15.0); dir = 1, fc = 1, name = "RAMP")
        @test length(_fnjunctions(n)[2].site) == 1
        # a divided at-grade crossing is one junction of two nodes
        n = _FNNet()
        _fnroad!(n, [(-2000.0, 15.0), (0.0, 15.0), (2000.0, 15.0)]; dir = 1, fc = 3, sign = "US 64")
        _fnroad!(n, [(2000.0, -15.0), (0.0, -15.0), (-2000.0, -15.0)]; dir = 1, fc = 3, sign = "US 64")
        _fnroad!(n, [(0.0, -2000.0), (0.0, -15.0), (0.0, 15.0), (0.0, 2000.0)]; fc = 4, sign = "SR 50")
        J = _fnjunctions(n)[2]
        @test length(J.site) == 1 && J.kind == [:atgrade] && count(>(0), J.cl) == 2
        # a downtown couplet with two street names, 100 m apart: each crossing its own, none joining the carriageways
        n = _FNNet()
        _fnroad!(n, [(-50.0, -1000.0), (-50.0, 0.0), (-50.0, 200.0), (-50.0, 1000.0)]; dir = 1, fc = 3, name = "SPRING ST")
        _fnroad!(n, [(50.0, 1000.0), (50.0, 200.0), (50.0, 0.0), (50.0, -1000.0)]; dir = 1, fc = 3, name = "PEACHTREE ST")
        _fnroad!(n, [(-500.0, 0.0), (-50.0, 0.0), (50.0, 0.0), (500.0, 0.0)]; fc = 4, name = "A ST")
        _fnroad!(n, [(-500.0, 200.0), (-50.0, 200.0), (50.0, 200.0), (500.0, 200.0)]; fc = 4, name = "B ST")
        J = _fnjunctions(n)[2]
        @test length(J.site) == 4 && all(==(:atgrade), J.kind) && all(c -> count(==(c), J.cl) == 1, 1:4)
        # an undivided crossing of two two-way roads is an ordinary node, not a junction (RN7)
        n = _FNNet()
        _fnroad!(n, [(-1000.0, 0.0), (0.0, 0.0), (1000.0, 0.0)]; fc = 3, sign = "US 64")
        _fnroad!(n, [(0.0, -1000.0), (0.0, 0.0), (0.0, 1000.0)]; fc = 4, sign = "SR 50")
        @test isempty(_fnjunctions(n)[2].site)
        # a freeway joining another without ramps, its two carriageway nodes 300 m apart, is one junction (RN7)
        n = _FNNet()
        _fnroad!(n, [(-3000.0, 15.0), (0.0, 15.0), (3000.0, 15.0)]; dir = 1, fc = 1, sign = "I 40")
        _fnroad!(n, [(3000.0, -15.0), (300.0, -15.0), (-3000.0, -15.0)]; dir = 1, fc = 1, sign = "I 40")
        _fnroad!(n, [(-3000.0, 1500.0), (0.0, 15.0)]; dir = 1, fc = 1, sign = "I 85")
        _fnroad!(n, [(300.0, -15.0), (-3000.0, 1470.0)]; dir = 1, fc = 1, sign = "I 85")
        J = _fnjunctions(n)[2]
        @test length(J.site) == 1 && J.kind == [:interchange] && count(>(0), J.cl) == 2
    end

    @testset "on FAF5 as Logjam ships it" begin
        N = faf5nodes(); L = faf5links()
        sgn = String.(coalesce.(L.SIGN, "")); nm = uppercase.(String.(coalesce.(L.NAME, "")))

        # the name rule, part by part
        v030 = LJ._isramp_v030.(L.NAME); cd = LJ._isramp_cd.(L.NAME); to = LJ._isramp_to.(L.NAME, L.DIR)
        named = LJ._isramp_name.(L.NAME, L.DIR, L.SIGN)
        to12 = LJ._isramp_to.(L.NAME, L.DIR, L.SIGN)
        toN0 = [!v030[k] && occursin(r"\bTO\b", nm[k]) for k in eachindex(nm)]
        println("  faf5net ramps by name: v0.3.0 rule ", count(v030), "; C/D however spelled, beyond it ", count(cd .& .!v030),
                "; X TO Y, beyond it ", count(to .& .!v030), " of N0's ", count(toN0), " TO names, ", count(to12 .& .!v030),
                " with RN17's both-sides rule on Interstate-signed links; all ", count(named))
        @test count(v030) == 137_156                          # N0, and v0.3.0's map filter
        @test count(cd .& .!v030) == 35                       # N1: four misspelt names; N0's 50 also held 9 turnarounds and 6 DOWNTOWN DISTRIBUTOR
        @test sort(unique(nm[cd .& .!v030])) == ["I 75 NB COLLECTOR/DISTRBUTOR LANE", "I 75 WB COLLECTION/DISTRIBUTION LANE",
                                                 "I 80 COLLECCTOR/DISTRIBUTOR LANE", "US 3 COLLECTOR/DISTRBUTOR LANE"]
        @test count(toN0) == 337                              # N0
        @test count(to .& .!v030) == count(to .& toN0) == 333 # N1: one-way, a designation on one side at least (RN10)
        @test sort(unique(nm[toN0 .& .!to])) == ["DIBC PLAZA TO CANADA", "GOING TO THE SUN HWY"]
        # T2.11 (RN17): of the X TO Y links signed as Interstates, only the three "I 95 NB APPROACH TO I 80" have a side
        # that is no designation, and they alone stop being ramps; the terminal ramps where I-476 ends at I-95 and I-581
        # at I-81, signed with the ending Interstate, stay ramps (RN12 as worded took all thirteen)
        @test count(to12 .& .!v030) == 330
        rn17 = to .& .!to12 .& .!v030
        @test sort(unique(zip(sgn[rn17], nm[rn17]))) == [("I 95", "I 95 NB APPROACH TO I 80")] && count(rn17) == 3
        @test !any(named[rn17])
        term = [(s == "I 476" || s == "I 581") && occursin(" TO ", n) for (s, n) in zip(sgn, nm)]
        @test count(term) == 10 && all(named[term])
        @test count(named) == 137_156 + 35 + 330
        @test !any(named[nm .== "DOWNTOWN DISTRIBUTOR"])

        # the structural test
        isr = LJ._ramp_links(N, L)
        st = isr .& .!named
        println("  faf5net ramps by the structural test: ", count(st), " (by class ",
                join(["$c: $(count(st .& (L.FCLASS .== c)))" for c in sort(unique(L.FCLASS))], ", "), "); ramps in all ", count(isr))
        @test count(st) == 2_272                              # N1 (N0 measured classes 1 and 2 only, by another cluster)
        @test count(isr) == 139_793                           # N2, RN17 (N1: 139,796; RN12 as worded 139,783)
        @test all(LJ._keytext(L.SIGN[k]) === nothing && LJ._keytext(L.NAME[k]) === nothing && L.DIR[k] != 0 for k in findall(st))

        # the Interstate flag
        fl = [LJ._isinterstate(L.SIGN[k], L.NAME[k], L.FCLASS[k]) for k in 1:nrow(L)]
        bus = occursin.(r"^I \S+ B$", sgn)
        lettered = occursin.(r"^I [AH]\d+$", sgn)
        byname = fl .& .!startswith.(sgn, "I ")
        println("  faf5net Interstate flag: ", count(fl), " links, ", count(byname), " by NAME alone, ", count(lettered),
                " Alaska's and Hawaii's lettered; not flagged: ", count(bus), " Business Interstate links")
        @test count(bus) == 855 && !any(fl[bus])              # N0: 855 Business Interstate links
        @test count(lettered) == 584 && all(fl[lettered])     # RN8: I A1 to A4 (389 links), I H1, H2, H201, H3 (195)
        @test count(byname) == 21                             # N0: I-296 (20 links) and one "I 496 EB"
        @test count(fl .& (sgn .== "US 131") .& (nm .== "I 296")) == 20
        @test all(fl[occursin.(r"^I \S+ [NSEW]$", sgn)])      # N0: 41 links with a direction suffix
        @test count(fl) == 81_489
        @test count(startswith.(sgn, "I ") .& .!fl) == 855    # every Interstate SIGN but the Business routes

        # N0's 588 crossings where one road met itself under two keys (a one-way class 2 or 3 link meeting a link of
        # another key, with another node of the same pair of keys, the keys sharing a number): the 268 that differ
        # only in a state-route prefix are one key now; the rest are different roads (Business, Bypass, Alternate,
        # Loop and split routes, frontage and service roads, a US route beside a state route of the same number).
        row = Dict(N.IDX[v] => v for v in 1:nrow(N))
        key0 = [isempty(sgn[k]) ? nm[k] : sgn[k] for k in eachindex(sgn)]
        at = [Int[] for _ in 1:nrow(N)]
        for k in 1:nrow(L)
            push!(at[row[L.SRC[k]]], k); push!(at[row[L.DST[k]]], k)
        end
        ent = Set{Tuple{String,String,Int}}()
        for v in 1:nrow(N)
            dv = Set{String}(); ot = Set{String}()
            for j in at[v]
                (v030[j] || isempty(key0[j])) && continue
                push!(ot, key0[j])
                L.FCLASS[j] in (2, 3) && L.DIR[j] != 0 && push!(dv, key0[j])
            end
            for a in dv, b in ot
                a == b || push!(ent, (minmax(a, b)..., v))
            end
        end
        npair = Dict{Tuple{String,String},Int}()
        for (a, b, _) in ent
            npair[(a, b)] = get(npair, (a, b), 0) + 1
        end
        num(s) = (m = match(r"^[A-Z]{2,3} (\d+[A-Z]?)\b", s); m === nothing ? "" : m.captures[1])
        cases = [(a, b) for (a, b, _) in ent if npair[(a, b)] >= 2 && !isempty(num(a)) && num(a) == num(b)]
        same(a, b) = LJ._route(a, missing) == LJ._route(b, missing) || LJ._route(missing, a) == LJ._route(missing, b)
        pfx(s) = (m = match(r"^([A-Z]{2,3}) ", s); m === nothing ? "" : m.captures[1])
        srp = Set([LJ._STATE_CODES...; "SR"])
        state = [(a, b) for (a, b) in cases if pfx(a) in srp && pfx(b) in srp && pfx(a) != pfx(b) &&
                 replace(a, r"^[A-Z]{2,3} " => "") == replace(b, r"^[A-Z]{2,3} " => "")]
        println("  faf5net route keys: of N0's ", length(cases), " crossings of one road under two keys, ", count(p -> same(p...), cases),
                " are one key now, all ", length(state), " that differ only in a state-route prefix")
        @test length(cases) == 588                            # N0
        @test length(state) == 268 && count(p -> same(p...), cases) == 268 && all(p -> same(p...), state)
        @test !same("US 30", "US 30 B") && !same("TX 71", "TX 71 P") && !same("DE 13", "US 13") && !same("SR 99 N", "SR 99 S")

        # the junctions
        J = LJ._junctions(N, L, isr)
        nc = length(J.site)
        @test length(J.cl) == nrow(N) && length(J.kind) == nc && all(in((:interchange, :atgrade)), J.kind)
        @test all(J.cl[J.site[c]] == c for c in 1:nc)         # every junction's node is one of its members
        @test sort(unique(J.cl[J.cl .> 0])) == 1:nc
        mem = [Int[] for _ in 1:nc]
        for v in eachindex(J.cl)
            J.cl[v] > 0 && push!(mem[J.cl[v]], v)
        end
        T = LJ._topology(N, L)
        ag = [c for c in 1:nc if J.kind[c] == :atgrade && length(mem[c]) > 1]
        agext = maximum(LJ._dmi(T, a, b) for c in ag for a in mem[c] for b in mem[c]) * 1609.344
        # Interstate junctions in the lower 48 (4.1's scope): members touching links of two or more Interstate routes
        rid = LJ._routeids(L, isr)
        low48 = .!in.(L.STFIP, Ref((2, 15, 72)))
        Ir = [Int[] for _ in 1:nc]
        for k in findall(fl .& low48)
            rid[k] == 0 && continue
            for v in (T.S[k], T.D[k])
                c = J.cl[v]; c == 0 && continue
                rid[k] in Ir[c] || push!(Ir[c], rid[k])
            end
        end
        nI = count(r -> length(r) >= 2, Ir)
        println("  faf5net junctions: ", nc, " (interchange ", count(==(:interchange), J.kind), ", at-grade ", count(==(:atgrade), J.kind),
                "); nodes in junctions ", count(>(0), J.cl), "; at-grade clusters of 2+ nodes ", length(ag), ", widest ",
                round(agext, digits = 1), " m; Interstate junctions in the lower 48 ", nI, " (Lecture 4.1's network: 754)")
        @test nc == 22_579                                    # N2, RN17 (N1: 22,579; RN12 as worded 22,580)
        @test count(==(:interchange), J.kind) == 15_914 && count(==(:atgrade), J.kind) == 6_665
        @test count(>(0), J.cl) == 156_172                    # N2, RN17 (N1: 156,175; RN12 as worded 156,168)
        @test agext < 400                                     # 150 m within one route pair, chained: 302.9 m at most (N1)
        @test nI == 857                                       # N2, RN17 (N1: 858); 4.1's 754 (N0), its clusters under RN6 788
    end
end

# ---------------------------------------------------------------------------------------------------------------------
# Part two (PCV N2): the derivation, his rulings RN13 to RN19 (T2.1 to T2.11, T4.7)
# ---------------------------------------------------------------------------------------------------------------------

# A synthetic network with every column the derivation reads: DIST by great circle, 60 mph, times in minutes.
function _fnfull(n)
    N, L = _fntables(n)
    L.DIST = [dgc((N.LON[s], N.LAT[s]), (N.LON[d], N.LAT[d])) for (s, d) in zip(L.SRC, L.DST)]
    L.SPEED = fill(60, nrow(L)); L.AB_SPEED = fill(60.0, nrow(L)); L.BA_SPEED = fill(60.0, nrow(L))
    L.AB_TIME = copy(L.DIST); L.BA_TIME = copy(L.DIST)
    L.STFIP = fill(37, nrow(L)); L.COFIP = fill(37183, nrow(L)); L.URBAN = Union{Missing,Int}[fill(99999, nrow(L))...]
    return N, L
end
_fnderive(n) = (t = _fnfull(n); (t..., LJ._faf5net(t...)))
_fnat(n, p) = findfirst(==(p), n.xy)                          # a synthetic node's IDX by its position

# One derivation of FAF5 as Logjam ships it, shared by N2's checks and N3's (T3.1, T4.3), so the suite derives once;
# released at the end of this file
const _FN_FAF5 = Ref{Any}(nothing)
function _fnfaf5()
    if _FN_FAF5[] === nothing
        N = faf5nodes(); L = faf5links()
        _FN_FAF5[] = (; N, L, R = LJ._faf5net(N, L))
    end
    return _FN_FAF5[]
end

@testset "faf5net: the derivation (N2, RN13 to RN19)" begin
    @testset "T2.7: a diamond is one node, its ramps gone, the freeway one two-way link each side" begin
        n = _FNNet(); _fnfreeway!(n, [-2000.0, -300.0, 300.0, 2000.0]); _fndiamond!(n, 0.0, "SR 54")
        N, L, R = _fnderive(n)
        @test nrow(R.nodes) == 5 && nrow(R.links) == 4 && all(==(0), R.links.DIR)
        @test sort(R.links.SIGN) == ["I 40", "I 40", "SR 54", "SR 54"]
        @test count(==(:interchange), R.info.J.kind) == 1
        site = R.nodemap.IDX[_fnat(n, (300.0, 15.0))]
        @test all(r -> site in (r.SRC, r.DST), eachrow(R.links))   # every link meets the junction's one node
        @test site in [_fnat(n, p) for p in ((-300.0, 15.0), (300.0, 15.0), (-300.0, -15.0), (300.0, -15.0))]  # on the main road (RN13)
        @test sort(R.nodemap.FAF5_IDX) == N.IDX && all(in(Set(R.nodes.IDX)), R.nodemap.IDX)
        # the merged freeway link carries the dropped carriageway's time the other way, here equal to its own
        k = findfirst(r -> isequal(r.SIGN, "I 40") && _fnat(n, (-2000.0, 15.0)) in (r.SRC, r.DST), eachrow(R.links))
        @test k !== nothing && isapprox(R.links.BA_TIME[k], R.links.AB_TIME[k]; atol = 1e-3)
    end
    @testset "T2.7: a cloverleaf is one node, its twelve ramps gone, both freeways two-way" begin
        n = _FNNet(); _fnfreeway!(n, [-2000.0, -400.0, -150.0, 150.0, 400.0, 2000.0])
        _fnroad!(n, [(15.0, y) for y in (-2000.0, -400.0, -150.0, 150.0, 400.0, 2000.0)]; dir = 1, fc = 2, sign = "US 1", name = "US 1")
        _fnroad!(n, [(-15.0, y) for y in (2000.0, 400.0, 150.0, -150.0, -400.0, -2000.0)]; dir = 1, fc = 2, sign = "US 1", name = "US 1")
        for (f, l, x) in (((150.0, 15.0), (200.0, 200.0), (-15.0, 150.0)), ((-150.0, -15.0), (-200.0, -200.0), (15.0, -150.0)),
                          ((-150.0, 15.0), (-200.0, 200.0), (15.0, 150.0)), ((150.0, -15.0), (200.0, -200.0), (-15.0, -150.0)))
            _fnlink!(n, f, l; dir = 1, fc = 1, name = "RAMP"); _fnlink!(n, l, x; dir = 1, fc = 1, name = "RAMP")
        end
        for (a, b) in (((-400.0, 15.0), (15.0, -400.0)), ((15.0, 400.0), (400.0, 15.0)), ((400.0, -15.0), (-15.0, 400.0)),
                       ((-15.0, -400.0), (-400.0, -15.0)))
            _fnlink!(n, a, b; dir = 1, fc = 1, name = "I 40 EB TO US 1 NB")
        end
        N, L, R = _fnderive(n)
        @test count(R.info.isramp) == 12
        @test nrow(R.nodes) == 5 && nrow(R.links) == 4 && all(==(0), R.links.DIR)
        @test sort(R.links.SIGN) == ["I 40", "I 40", "US 1", "US 1"]
        @test sort(R.links.TYPE) == ["I", "I", "U", "U"] && count(R.links.INTERSTATE) == 2
    end
    @testset "T2.7: a divided at-grade crossing is one node and two two-way roads" begin
        n = _FNNet()
        _fnroad!(n, [(-2000.0, 15.0), (0.0, 15.0), (2000.0, 15.0)]; dir = 1, fc = 3, sign = "US 64", name = "US 64")
        _fnroad!(n, [(2000.0, -15.0), (0.0, -15.0), (-2000.0, -15.0)]; dir = 1, fc = 3, sign = "US 64", name = "US 64")
        _fnroad!(n, [(0.0, -2000.0), (0.0, -15.0), (0.0, 15.0), (0.0, 2000.0)]; fc = 4, sign = "SR 50")
        N, L, R = _fnderive(n)
        @test nrow(R.nodes) == 5 && nrow(R.links) == 4 && all(==(0), R.links.DIR)
        @test count(isequal("US 64"), R.links.SIGN) == 2 && count(isequal("SR 50"), R.links.SIGN) == 2
        # with no NAME on either side, classes 3 and up do not have "the same NAME" (rule C): both sides stay one-way
        n2 = _FNNet()
        _fnroad!(n2, [(-2000.0, 15.0), (0.0, 15.0), (2000.0, 15.0)]; dir = 1, fc = 3, sign = "US 64")
        _fnroad!(n2, [(2000.0, -15.0), (0.0, -15.0), (-2000.0, -15.0)]; dir = 1, fc = 3, sign = "US 64")
        _fnroad!(n2, [(0.0, -2000.0), (0.0, -15.0), (0.0, 15.0), (0.0, 2000.0)]; fc = 4, sign = "SR 50")
        @test count(!=(0), _fnderive(n2)[3].links.DIR) == 4
    end
    @testset "T2.7: a downtown couplet with two street names stays two one-way links" begin
        n = _FNNet()
        _fnroad!(n, [(-50.0, -1000.0), (-50.0, 0.0), (-50.0, 200.0), (-50.0, 1000.0)]; dir = 1, fc = 3, name = "SPRING ST")
        _fnroad!(n, [(50.0, 1000.0), (50.0, 200.0), (50.0, 0.0), (50.0, -1000.0)]; dir = 1, fc = 3, name = "PEACHTREE ST")
        _fnroad!(n, [(-500.0, 0.0), (-50.0, 0.0), (50.0, 0.0), (500.0, 0.0)]; fc = 4, name = "A ST")
        _fnroad!(n, [(-500.0, 200.0), (-50.0, 200.0), (50.0, 200.0), (500.0, 200.0)]; fc = 4, name = "B ST")
        N, L, R = _fnderive(n)
        sp = R.links[isequal.(R.links.NAME, "SPRING ST"), :]; pt = R.links[isequal.(R.links.NAME, "PEACHTREE ST"), :]
        @test nrow(sp) == 3 && nrow(pt) == 3 && all(==(1), sp.DIR) && all(==(1), pt.DIR)
        @test all(==("L"), R.links.TYPE)
    end
    @testset "RN15: a rest area on one carriageway is a junction the merged freeway passes" begin
        n = _FNNet(); _fnfreeway!(n, [-5000.0, -300.0, 300.0, 5000.0])
        _fnlink!(n, (-300.0, 15.0), (0.0, 150.0); dir = 1, fc = 1, name = "REST AREA RAMP")
        _fnlink!(n, (0.0, 150.0), (300.0, 15.0); dir = 1, fc = 1, name = "REST AREA RAMP")
        N, L, R = _fnderive(n)
        @test R.info.J.kind == [:ramp]
        @test nrow(R.nodes) == 3 && nrow(R.links) == 2 && all(==(0), R.links.DIR) && all(isequal("I 40"), R.links.SIGN)
    end
    @testset "RN15: an interchange with an unnamed road keeps the road connected" begin
        n = _FNNet(); _fnfreeway!(n, [-2000.0, -300.0, 300.0, 2000.0])
        _fnroad!(n, [(0.0, -800.0), (0.0, -60.0), (0.0, 60.0), (0.0, 800.0)]; fc = 5)   # no SIGN, no NAME
        _fnlink!(n, (-300.0, 15.0), (0.0, 60.0); dir = 1, fc = 1, name = "RAMP"); _fnlink!(n, (0.0, 60.0), (300.0, 15.0); dir = 1, fc = 1, name = "RAMP")
        _fnlink!(n, (300.0, -15.0), (0.0, -60.0); dir = 1, fc = 1, name = "RAMP"); _fnlink!(n, (0.0, -60.0), (-300.0, -15.0); dir = 1, fc = 1, name = "RAMP")
        N, L, R = _fnderive(n)
        @test count(==(:ramp), R.info.J.kind) == 2                 # the two halves of the diamond, one per carriageway
        pos = Dict(x => i for (i, x) in enumerate(R.nodes.IDX))
        p = LJ._uf(nrow(R.nodes))
        for r in eachrow(R.links)
            LJ._join!(p, pos[r.SRC], pos[r.DST])
        end
        @test length(unique(LJ._root!(p, i) for i in 1:nrow(R.nodes))) == 1
        @test count(ismissing, R.links.SIGN) == 2 && count(isequal("I 40"), R.links.SIGN) == 2
    end
    @testset "D5: each stretch takes FAF5's time each way" begin
        n = _FNNet()
        _fnroad!(n, [(-2000.0, 15.0), (-1000.0, 15.0), (0.0, 15.0), (2000.0, 15.0)]; dir = 1, fc = 1, sign = "I 40", name = "I 40")
        _fnroad!(n, [(2100.0, -15.0), (-2100.0, -15.0)]; dir = 1, fc = 1, sign = "I 40", name = "I 40")   # longer: dropped
        N, L = _fnfull(n)
        L.AB_TIME[4] = 5.0                                         # the westbound carriageway's one link: 5 minutes
        R = LJ._faf5net(N, L)
        @test nrow(R.links) == 3 && all(==(0), R.links.DIR)
        @test sum(R.links.BA_TIME) ≈ 5.0 atol = 1e-3              # shared over the three kept links by DIST
        @test sort(R.links.AB_TIME) ≈ sort(round.(L.AB_TIME[1:3], digits = 4))
        @test R.links.BA_TIME ./ R.links.DIST ≈ fill(5.0 / sum(L.DIST[1:3]), 3) rtol = 1e-3
    end

    @testset "on FAF5 as Logjam ships it" begin
        N, L, R = _fnfaf5()
        I = R.info; C = I.C; J = I.J
        nodes, links, nodemap = R.nodes, R.links, R.nodemap
        der = Set(nodes.IDX)
        # T2.4, T4.7: the columns, osm_roads' eight first, typed
        @test names(links) == ["SRC", "DST", "DIST", "SPEED", "FCLASS", "DIR", "NAME", "SOURCE", "SIGN", "TYPE", "INTERSTATE",
                               "AB_TIME", "BA_TIME", "STFIP", "COFIP", "URBAN"]
        @test names(links)[1:8] == first.(LJ._OSM_LINK_TYPES)[1:8]
        @test eltype.(eachcol(links)) == [Int, Int, Float64, Int, Int, Int, Union{Missing,String}, String, Union{Missing,String},
                                          Union{Missing,String}, Bool, Float64, Float64, Int, Int, Union{Missing,Int}]
        @test names(nodes) == ["IDX", "LON", "LAT", "SOURCE"] && names(nodemap) == ["FAF5_IDX", "IDX"]
        @test all(x -> ismissing(x) || x in ("I", "U", "S", "L"), links.TYPE)
        for (s, t) in (("I 40", "I"), ("US 1", "U"), ("NC 54", "S"))
            @test count(isequal(s), links.SIGN) > 0 && all(isequal(t), links.TYPE[isequal.(links.SIGN, s)])
        end
        @test all(x -> ismissing(x) || (v = split(x, ';'); issorted(v) && allunique(v)), links.SIGN)
        @test all(==("FAF5"), links.SOURCE) && all(in((-1, 0, 1)), links.DIR)
        @test issorted(collect(zip(links.SRC, links.DST))) && issorted(nodes.IDX) && issorted(nodemap.FAF5_IDX)
        flag(k) = LJ._isinterstate(L.SIGN[k], L.NAME[k], L.FCLASS[k])
        @test all(links.INTERSTATE[r] == (flag(k) || (q = abs(I.role[k]); q > 0 && any(flag, C.chains[C.drop[q]])))
                  for (r, k) in enumerate(I.ks))                  # D9: either carriageway
        # T2.1: no ramp survives
        @test !any(I.isramp[I.ks])
        # T2.2: each junction is one node
        first_img = zeros(Int, length(J.site)); ok = true
        for v in eachindex(J.cl)
            c = J.cl[v]; c == 0 && continue
            first_img[c] == 0 ? (first_img[c] = I.img[v]) : (ok &= first_img[c] == I.img[v])
        end
        @test ok
        # T2.3: an accepted pair's kept links two-way; a rejected pair's and an unpaired stretch's links one-way
        pos = Dict(k => r for (r, k) in enumerate(I.ks))
        inpair = falses(length(C.chains))
        for (i, j) in C.pairs
            inpair[i] = inpair[j] = true
        end
        @test all(links.DIR[pos[k]] == 0 for (q, _) in enumerate(C.pairs) if C.accept[q] for k in C.chains[C.keep[q]] if haskey(pos, k))
        @test all(links.DIR[pos[k]] != 0 for (q, (i, j)) in enumerate(C.pairs) if !C.accept[q] for k in [C.chains[i]; C.chains[j]] if haskey(pos, k))
        @test all(links.DIR[pos[k]] != 0 for i in eachindex(C.chains) if !inpair[i] for k in C.chains[i] if haskey(pos, k))
        # T2.5 (RN19): the node map covers every FAF5 node once; every IDX it gives is a derived node; the IDX is
        # missing exactly for the nodes of FAF5's components made only of ramps
        @test nrow(nodemap) == nrow(N) && allunique(nodemap.FAF5_IDX)
        @test all(x -> ismissing(x) || x in der, nodemap.IDX)
        T = I.T
        onlyramps = trues(maximum(I.fcomp))
        for k in 1:T.nL
            I.isramp[k] || (onlyramps[I.fcomp[T.S[k]]] = false)
        end
        rows = Dict(x => v for (v, x) in enumerate(N.IDX))
        miss = [rows[x] for x in nodemap.FAF5_IDX[ismissing.(nodemap.IDX)]]
        @test count(onlyramps) == 145 && length(miss) == 310 && all(v -> onlyramps[I.fcomp[v]], miss)
        @test count(v -> onlyramps[I.fcomp[v]], 1:nrow(N)) == 310
        # T2.9 (RN5, RN16): by the stretches through N0's start nodes
        row = Dict(N.IDX[v] => v for v in 1:nrow(N))
        qof = zeros(Int, length(C.chains))
        for (q, (i, j)) in enumerate(C.pairs)
            qof[i] = qof[j] = q
        end
        verdict(s, r) = [I.inside0[i] ? :inside : qof[i] == 0 ? :none : C.accept[qof[i]] ? :accept : :reject
                         for i in eachindex(C.path) if I.rkey[C.R[i]] == r && row[s] in C.path[i][1:end-1]]
        for (s, r) in ((1460024, "I 277"), (1458948, "I 277"), (1459254, "I 77"), (1459250, "I 77"), (1459505, "US 74"),
                       (1459511, "US 74"), (1170196, "I 20"), (1170199, "I 20"), (1180446, "I 75"), (1180702, "I 75"))
            v = verdict(s, r)
            @test !isempty(v) && all(in((:accept, :inside)), v)  # the freeways merge, or collapse into the junction
        end
        for (s, r) in ((1170994, "US 29"), (1170989, "US 19"), (1174060, "US 19"), (1116440, "SR 61"), (1117962, "SR 92"),
                       (539176, "I 35 FRONTAGE RD"), (521782, "I 410 FRONTAGE RD"))
            v = verdict(s, r)                                      # the couplets and the frontage roads stay one-way: no
            @test !isempty(v) && !(:accept in v)                   # pair accepted, and every link they keep one-way
            @test all(links.DIR[pos[k]] != 0 for i in eachindex(C.path) if I.rkey[C.R[i]] == r && row[s] in C.path[i][1:end-1]
                      for k in C.chains[i] if haskey(pos, k))
        end
        tal = [i for i in eachindex(C.chains) if isequal(L.SIGN[C.chains[i][1]], "FL 363") &&
               occursin(r"DUVAL|BRONOUGH", uppercase(coalesce(L.NAME[C.chains[i][1]], "")))]
        @test !isempty(tal) && all(i -> qof[i] > 0 && !C.accept[qof[i]], tal)
        @test verdict(1570829, "US 401") == [:accept] && verdict(1570821, "US 401") == [:accept]   # RN16's known cost
        # T2.6: counts by class, against FAF5's (printed for the report)
        for (lab, FC, DR, DS, S, D) in (("FAF5", L.FCLASS, L.DIR, L.DIST, L.SRC, L.DST),
                                        ("derived", links.FCLASS, links.DIR, links.DIST, links.SRC, links.DST))
            println("  faf5net ", lab, " by class (links, miles, one-way %, nodes): ", join(
                [(s = findall(x -> min(x, 5) == c, FC);
                  string(c == 5 ? "5+" : c, " ", length(s), " / ", round(Int, sum(DS[s]; init = 0.0)), " / ",
                         isempty(s) ? 0.0 : round(100count(!=(0), DR[s]) / length(s), digits = 1), " / ", length(unique([S[s]; D[s]]))))
                 for c in 0:5], "; "))
        end
        println("  faf5net derived: ", nrow(nodes), " nodes, ", nrow(links), " links; pairs ", length(C.pairs), " found, ",
                count(C.accept), " accepted; node map IDX missing ", count(ismissing, nodemap.IDX))
        @test nrow(nodes) == 145_722 && nrow(links) == 210_119    # N2 (the measured draft J + (i) + (ii) + fuzzy, under RN17)
        @test length(C.pairs) == 22_464 && count(C.accept) == 20_108
    end
end

# ---------------------------------------------------------------------------------------------------------------------
# Part three (PCV N3): the shipped data and its accessors (D7, RD1, RD2); SC 1 (T1.3, T1.4), SC 3 (T3.1 to T3.3) and
# SC 4 (T4.1 to T4.5, T4.7). Every expected number is N0's or N2's measurement, or Lecture 4.1's published content.
# ---------------------------------------------------------------------------------------------------------------------

include("faf5net_fixture_helpers.jl")

# Lecture 4.1, as published: Code block 34's Raleigh rectangle (lon, lat), and the first row of Ex. 3's table of
# OSRM's routes from High Point to Goldsboro (#tbl-osrm, its fastest: miles, minutes; queried 2026-10-09)
const _FN_RRAL = [-79.2618 35.2497; -78.1964 36.1762]
const _FN_OSRM = (138.36, 180.4)

# N0's baseline, 4.1's committed Interstate network measured (test/fixtures/faf5net_baseline.tsv): name => value
function _fnbaseline()
    d = Dict{String,Float64}()
    for (i, l) in enumerate(eachline(joinpath(@__DIR__, "fixtures", "faf5net_baseline.tsv")))
        i == 1 && continue
        f = split(l, '\t'); d[String(f[1])] = parse(Float64, f[2])
    end
    return d
end

_fnpct(x, b) = 100(x / b - 1)
_fnmins(t, v, d) = t > 0 ? t : 60d / v           # 4.1 Code block 51: FAF5's free-flow minutes, else 60 d / v

# 4.1 Code block 47: the NC places of more than 100,000 people
_fncities() = select!(filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace()), :NAME, :LAT, :LON, :POP)

# A cropped network's two graphs, 4.1 Code blocks 45 and 51: miles, and minutes (a connector at 20 mph)
function _fngraphs(Lc)
    con = isequal.(Lc.SOURCE, "CONNECTOR")
    tAB = [c ? 60d / 20 : _fnmins(t, v, d) for (c, t, v, d) in zip(con, Lc.AB_TIME, Lc.SPEED, Lc.DIST)]
    tBA = [c ? 60d / 20 : _fnmins(t, v, d) for (c, t, v, d) in zip(con, Lc.BA_TIME, Lc.SPEED, Lc.DIST)]
    fw, bw = Lc.DIR .!= -1, Lc.DIR .!= 1
    I, J = [Lc.SRC[fw]; Lc.DST[bw]], [Lc.DST[fw]; Lc.SRC[bw]]
    return (SimpleWeightedDiGraph(I, J, [Lc.DIST[fw]; Lc.DIST[bw]]; combine = min),
            SimpleWeightedDiGraph(I, J, [tAB[fw]; tBA[bw]]; combine = min))
end

# 4.1 Code blocks 48 and 51: miles on distance-weighted paths and minutes on time-weighted paths between the cities
function _fnrouting(N, L, df)
    N, L = prune_reindex(N, L)
    Nc, Lc = cropnetwork(N, L, df.LON, df.LAT)
    Nc, Lc = addconnectors(Nc, Lc, df.LON, df.LAT; add_nf_nf = false)
    g, gT = _fngraphs(Lc)
    return first(shortestpaths(g, nrow(df))), first(shortestpaths(gT, nrow(df)))
end

# 4.1 Code block 53 (Ex. 3): the shortest and the fastest route from High Point to Goldsboro, the miles and the minutes
# of each (as [shortest, fastest])
function _fnex3(N, L)
    N, L = prune_reindex(N, L)
    hp = loc2lonlat("High Point"; state = :NC); gb = loc2lonlat("Goldsboro"; state = :NC)
    X, Y = [hp.LON, gb.LON], [hp.LAT, gb.LAT]
    N3, L3 = cropnetwork(N, L, X, Y; xexpand = 0.2, yexpand = 0.5)
    N3, L3 = addconnectors(N3, L3, X, Y; add_nf_nf = false)
    g, gT = _fngraphs(L3)
    pD = tracepath(dijkstra_shortest_paths(g, 1).parents, 1, 2)
    pF = tracepath(dijkstra_shortest_paths(gT, 1).parents, 1, 2)
    return sum.(segcost.([pD, pF], Ref(weights(g)))), sum.(segcost.([pD, pF], Ref(weights(gT))))
end

# T1.4: what faf5nodes() and faf5links() returned at v0.3.0 (7b36241; datatools.jl and the faf5 artifact are unchanged
# since). Per column: its element type's name, whether it admits missing, its missing count, and its sum (a number
# column) or its total length in characters (a text column). Measured 2026-11-22 (PCV N3).
const _FN_V030 = Dict(
    "faf5nodes" => (344_998, [
        ("IDX", :Int64, false, 0, 334409109638), ("LON", :Float64, false, 0, -3.1928504788986996e7),
        ("LAT", :Float64, false, 0, 1.3084324648401154e7), ("ENTRY_EXIT", :String7, true, 343440, 7009),
        ("EXIT_NUM", :String7, true, 343928, 2511), ("INTERCHANGE", :String, true, 343434, 23899),
        ("FACILITY_TYPE", :String31, true, 340054, 75049), ("FACILITY_NAME", :String, true, 340052, 78336),
        ("STATEID", :Int64, false, 0, 0), ("FAFID", :Int64, false, 0, 0)]),
    "faf5links" => (483_530, [
        ("SRC", :Int64, false, 0, 471409459993), ("DST", :Int64, false, 0, 471569908184),
        ("DIST", :Float64, false, 0, 580314.2748923659), ("STFIP", :Int64, false, 0, 14344240),
        ("COFIP", :Int64, false, 0, 14390497912), ("SPEED", :Int64, false, 0, 23044907),
        ("NHS", :Int64, false, 0, 2869947), ("SIGN", :String15, true, 247001, 1167136),
        ("NAME", :String, true, 38692, 3248619), ("FCLASS", :Int64, false, 0, 1126237),
        ("URBAN", :Int64, true, 1758, 32141799454), ("AB_SPEED", :Float64, false, 0, 2.0773163042438976e7),
        ("BA_SPEED", :Float64, false, 0, 2.0453057968024906e7), ("AB_TIME", :Float64, false, 0, 775814.6647614709),
        ("BA_TIME", :Float64, false, 0, 777246.6249872458), ("AB_LANES", :Int64, false, 0, 931565),
        ("BA_LANES", :Int64, false, 0, 256178), ("DIR", :Int64, false, 0, 318378),
        ("STRAHNET", :Int64, false, 0, 636718), ("NHFN", :Int64, false, 0, 527224),
        ("TOLL_TYPE", :Int64, false, 0, 8396), ("TOLL_LINK", :Int64, false, 0, 1243),
        ("BORDER_LINK", :Int64, false, 0, 41), ("FAFZONE", :Int64, false, 0, 145409445),
        ("STATUS", :Int64, false, 0, 483562)]))

@testset "faf5net: the shipped data, its accessors and the checks (N3)" begin
    @testset "T1.4: faf5nodes() and faf5links() as v0.3.0 returned them" begin
        for (f, tbl) in (("faf5nodes", faf5nodes()), ("faf5links", faf5links()))
            n, cols = _FN_V030[f]
            @test nrow(tbl) == n && names(tbl) == first.(cols)
            for (c, T, u, nm, s) in cols
                v = tbl[!, c]; E = nonmissingtype(eltype(v))
                @test nameof(E) == T && (eltype(v) !== E) == u && count(ismissing, v) == nm
                if E <: AbstractFloat
                    @test isapprox(sum(skipmissing(v)), s; rtol = 1e-12)
                elseif E <: Integer
                    @test sum(skipmissing(v)) == s
                else
                    @test sum(length, skipmissing(v); init = 0) == s
                end
            end
        end
    end

    @testset "T1.3: a Raleigh extract of FAF5 derives to its committed files, byte for byte" begin
        N, L = fn_read_extract()
        @test (nrow(N), nrow(L)) == (214, 295)
        for (f, b) in zip(FN_DERIVED, fn_derived_bytes(N, L))
            @test b == read(joinpath(FN_FIXTURE_DIR, f))
        end
        # the extract is FAF5 as Logjam ships it, cut to the box, and reads back as the same values
        Nx, Lx = fn_cut(faf5nodes(), faf5links())
        for (f, b) in zip(FN_EXTRACT, fn_extract_bytes(Nx, Lx))
            @test b == read(joinpath(FN_FIXTURE_DIR, f))
        end
        @test isequal(N, Nx) && isequal(L, Lx)
    end

    @testset "D7, RD1, RD2: the faf5net artifact, read once, a copy per call" begin
        for f in (:usrdnode, :usrdlink, :usrdnodemap)
            @test Base.isexported(Logjam, f) && !occursin("No documentation found", string(Base.Docs.doc(getfield(Logjam, f))))
        end
        t1 = @elapsed (N0 = usrdnode(); L0 = usrdlink(); M0 = usrdnodemap())
        t2 = @elapsed (usrdnode(); usrdlink(); usrdnodemap())
        t3 = @elapsed usrdlink(interstate = true, region = :CUS)
        println("  faf5net accessors: first calls ", round(t1, digits = 2), " s (the files read), then ", round(1000t2),
                " ms for the three copies; usrdlink(interstate = true, region = :CUS) ", round(1000t3), " ms")
        # the shipped files are the derivation of FAF5 as Logjam ships it, value for value and type for type
        _, _, R = _fnfaf5()
        for (a, b) in ((N0, R.nodes), (L0, R.links), (M0, R.nodemap))
            @test isequal(a, b) && eltype.(eachcol(a)) == eltype.(eachcol(b))
        end
        @test (nrow(N0), nrow(L0), nrow(M0), count(ismissing, M0.IDX)) == (145_722, 210_119, 344_998, 310)
        # a copy per call: changing one leaves the next untouched
        N0.LON[1] = 0.0; L0.DIST[1] = -1.0; M0.IDX[1] = -1; push!(L0, copy(L0[2, :]))
        @test usrdnode().LON[1] != 0.0 && usrdlink().DIST[1] != -1.0 && usrdnodemap().IDX[1] != -1 && nrow(usrdlink()) == 210_119
        @test usrdlink(interstate = true).DIST !== usrdlink(interstate = true).DIST
    end

    @testset "T4.5: the keywords, and the Interstates of the lower 48 thinned (RD2); T3.3 reported" begin
        N0 = usrdnode(); L0 = usrdlink()
        (x0, x1), (y0, y1) = CUS_LIMITS
        incus = Set(N0.IDX[(x0 .<= N0.LON .<= x1) .& (y0 .<= N0.LAT .<= y1)])
        cus = in.(L0.SRC, Ref(incus)) .& in.(L0.DST, Ref(incus))
        for (kw, want) in (((interstate = true, region = :CUS), L0.INTERSTATE .& cus),
                           ((fclass = 1:3,), in.(L0.FCLASS, Ref(1:3))),
                           ((fclass = 2,), L0.FCLASS .== 2),
                           ((interstate = true,), L0.INTERSTATE),
                           ((region = :CUS,), cus),
                           ((interstate = true, fclass = [1, 2], region = :CUS), L0.INTERSTATE .& (L0.FCLASS .<= 2) .& (L0.FCLASS .>= 1) .& cus))
            Lk = usrdlink(; kw...); Nk = usrdnode(; kw...)
            @test nrow(Lk) > 0 && isequal(Lk, L0[want, :])                        # exactly the links the keywords name
            @test isequal(Nk, N0[in.(N0.IDX, Ref(Set([Lk.SRC; Lk.DST]))), :])     # exactly the nodes they use
        end
        @test isequal(usrdlink(fclass = 1), usrdlink(fclass = [1])) && isequal(usrdnode(fclass = 4), usrdnode(fclass = (4,)))
        @test isequal(usrdnode(interstate = false, fclass = nothing, region = nothing), N0)
        @test_throws ArgumentError usrdlink(region = :US)
        @test_throws ArgumentError usrdnode(region = "CUS")
        @test_throws ArgumentError usrdlink(fclass = "1")
        @test_throws ArgumentError usrdnode(fclass = 1.5)
        # 4.1's network: the Interstates of the lower 48, ready for thin
        NI = usrdnode(interstate = true, region = :CUS); LI = usrdlink(interstate = true, region = :CUS)
        @test all(LI.INTERSTATE) && all(in(incus), LI.SRC) && all(in(incus), LI.DST)
        tN, tL = thin(NI, LI)
        @test nrow(tN) > 0 && nrow(tL) > 0 && issubset([tL.SRC; tL.DST], 1:nrow(tN))
        tN2, tL2 = thin(select(NI, :IDX, :LON, :LAT), select(LI, :SRC, :DST, :DIST))   # every link two-way, as 4.1's files
        rN, rL = cropnetwork(select(NI, :IDX, :LON, :LAT), select(LI, :SRC, :DST, :DIST, :DIR), _FN_RRAL[:, 1], _FN_RRAL[:, 2];
                             xexpand = 0, yexpand = 0)
        trN, _ = thin(rN, rL)
        b = _fnbaseline()
        println("  faf5net lower-48 Interstates: ", nrow(NI), " nodes (", round(_fnpct(nrow(NI), b["nodes"]), digits = 1), "% against 4.1's ",
                Int(b["nodes"]), "), ", nrow(LI), " links (", round(_fnpct(nrow(LI), b["links"]), digits = 1), "% against ", Int(b["links"]),
                "): every interchange collapses, not only 4.1's ", Int(b["junctions"]), "; thinned ", nrow(tN), " / ", nrow(tL),
                " (every link two-way ", nrow(tN2), " / ", nrow(tL2), "; 4.1's ", Int(b["thin_nodes"]), " / ", Int(b["thin_links"]),
                "); Raleigh rectangle ", nrow(rN), " nodes (4.1's ", Int(b["raleigh_nodes"]), "), ", nrow(rL), " links, thinned ",
                nrow(trN), " (", Int(b["raleigh_thin_nodes"]), ")")
        # T3.3, report only: 4.1 Ex. 4's intersections (Code block 56: the ends removed until none is left, thinned again);
        # its terminals need a MIP solver (JuMP and HiGHS), which is not among Logjam's dependencies, so they are not run
        for (lab, (iN, iL)) in (("DIR kept", prune_reindex(tN, tL)), ("every link two-way", prune_reindex(tN2, tL2)))
            while true
                deg = zeros(Int, nrow(iN))
                foreach(x -> deg[x] += 1, [iL.SRC; iL.DST])
                all(>(1), deg) && break
                iN, iL = prune_reindex(iN, iL[(deg[iL.SRC] .> 1) .& (deg[iL.DST] .> 1), :])
            end
            iN, iL = prune_reindex(thin(iN, iL)...)
            println("  faf5net T3.3 (report only): 4.1 Ex. 4's intersections on the derived Interstates (", lab, "): ", nrow(iN),
                    " (4.1's ", Int(b["ex4_lecture_intersections"]), "); terminals not computed: Ex. 4's set covering needs JuMP and HiGHS")
            @test nrow(iN) > 0
        end
    end

    @testset "T4.7: the link table stacks with an osm_roads table (D11)" begin
        O = DataFrame([c => T[] for (c, T) in LJ._OSM_LINK_TYPES])
        push!(O, (1, 2, 0.25, 25, 4, 0, "HILLSBOROUGH ST", "OSM", 25, missing, missing))
        F = usrdlink(region = :CUS)[1:3, :]
        @test names(F)[1:8] == first.(LJ._OSM_LINK_TYPES)[1:8] && eltype.(eachcol(F))[1:8] == last.(LJ._OSM_LINK_TYPES)[1:8]
        V = vcat(F[:, 1:8], O[:, 1:8])
        @test nrow(V) == 4 && names(V) == names(O)[1:8] && eltype.(eachcol(V)) == last.(LJ._OSM_LINK_TYPES)[1:8]
        U = vcat(F, O; cols = :union)
        @test nrow(U) == 4 && names(U)[1:8] == names(O)[1:8] && U.SOURCE == ["FAF5", "FAF5", "FAF5", "OSM"]
    end

    @testset "T3.1, T3.2: the lower 48's Interstates against 4.1's network (RN11, RN18)" begin
        N, L, R = _fnfaf5()
        I = R.info; C = I.C; J = I.J
        nodes, links = R.nodes, R.links
        b = _fnbaseline()
        ks = findall(LJ._usrdkeep(nodes, links, true, nothing, :CUS))     # usrdlink(interstate = true, region = :CUS)
        mi0 = sum(I.fdist[ks]); mi = sum(links.DIST[ks])                  # without the stubs, and with them
        fl = [LJ._isinterstate(L.SIGN[k], L.NAME[k], L.FCLASS[k]) for k in 1:nrow(L)]
        acc = falses(length(C.chains))
        for (q, (i, j)) in enumerate(C.pairs)
            C.accept[q] && (acc[i] = acc[j] = true)
        end
        Ich = [i for i in eachindex(C.chains) if fl[C.chains[i][1]] && !C.inside[i] && !(L.STFIP[C.chains[i][1]] in (2, 15, 72))]
        un = sum(C.len[[i for i in Ich if !acc[i]]]; init = 0.0); cw = sum(C.len[Ich])
        println("  faf5net T3.1: lower-48 Interstate miles without stubs ", round(mi0, digits = 3), " (", round(_fnpct(mi0, b["miles"]), digits = 2),
                "% against 4.1's ", b["miles"], "; limit 5%), with stubs ", round(mi, digits = 3), " (", round(_fnpct(mi, b["miles"]), digits = 2),
                "%); unpaired Interstate carriageway ", round(un, digits = 1), " of ", round(cw, digits = 1), " mi (",
                round(100un / cw, digits = 2), "%; limit 1%)")
        @test abs(_fnpct(mi0, b["miles"])) <= 5
        @test un / cw <= 0.01
        # reported (RN11): junction nodes meeting the Interstate links of two or more routes
        jimg = Set(N.IDX[I.img[J.site[c]]] for c in eachindex(J.site))
        ir = Dict{Int,Set{String}}()
        for k in ks
            rs = ismissing(links.SIGN[k]) ? String[] : [String(s) for s in split(links.SIGN[k], ';') if occursin(LJ._I_SIGN, s)]
            for x in (links.SRC[k], links.DST[k])
                x in jimg && union!(get!(ir, x, Set{String}()), [something(LJ._route(s, missing), s) for s in rs])
            end
        end
        nj = count(v -> length(v) >= 2, values(ir))
        println("  faf5net T3.1 (RN11, reported): junctions ", Int(b["junctions"]), " by 4.1's rule, 788 by RN6's merge, ", nj, " derived")
        @test nj > 0
        # T3.2, the differences, listed: the unsigned Interstates, and 4.1's ramp and main-line rule against this one on
        # the lower 48's class 1 links (4.1: a main line is signed "I ..."; a ramp is unsigned as an Interstate and named
        # a ramp, a C/D lane, a connector or a turn lane, or unnamed)
        us = [r for r in ks if !any(s -> occursin(LJ._I_SIGN, s), split(coalesce(links.SIGN[r], ""), ';'))]
        sgn = String.(coalesce.(L.SIGN, "")); nm = uppercase.(String.(coalesce.(L.NAME, "")))
        low48 = .!in.(L.STFIP, Ref((2, 15, 72))); fc1 = L.FCLASS .== 1; isr = I.isramp
        main41 = fc1 .& startswith.(sgn, "I ") .& low48
        ramp41 = fc1 .& .!startswith.(sgn, "I ") .& low48 .& (occursin.(r"RAMP|COLLECTOR|DISTRIBUTOR|CONNECTOR|TURN LANE", nm) .| (nm .== ""))
        function ex(m)                                              # the three commonest (SIGN, NAME), with their counts
            cnt = Dict{Tuple{String,String},Int}()
            for k in findall(m)
                cnt[(sgn[k], nm[k])] = get(cnt, (sgn[k], nm[k]), 0) + 1
            end
            top = first(sort!(collect(cnt), by = x -> (-x[2], x[1])), 3)
            return join(["$(isempty(s) ? "-" : s) / $(isempty(t) ? "-" : t) ($c)" for ((s, t), c) in top], ", ")
        end
        for (lab, m) in (("4.1 main line, not flagged here (Business routes)", main41 .& .!fl .& .!isr),
                         ("4.1 main line, a ramp here (ramps signed as Interstates)", main41 .& isr),
                         ("flagged here, not a 4.1 main line (not class 1, or found by NAME)", fl .& low48 .& .!main41 .& .!isr),
                         ("4.1 ramp, a road here (CONNECTOR names, unnamed links outside the structural test)", ramp41 .& .!isr),
                         ("a ramp here, not a 4.1 ramp (class 1, not signed as an Interstate)", isr .& fc1 .& low48 .& .!startswith.(sgn, "I ") .& .!ramp41))
            println("  faf5net T3.2: ", lab, ": ", count(m), " links", count(m) > 0 ? "; e.g. " * ex(m) : "")
        end
        println("  faf5net T3.2: unsigned Interstates (flagged, no Interstate SIGN): ", length(us), " links; ",
                unique(zip(coalesce.(links.SIGN[us], ""), coalesce.(links.NAME[us], ""))))
        @test length(us) == 6                                       # N2: I-296, signed US 131
    end

    @testset "T4.3: components one to one, but FAF5's pieces made only of ramps (RN1, RN19)" begin
        N, L, R = _fnfaf5()
        I = R.info; T = I.T
        nodes, links, nodemap = R.nodes, R.links, R.nodemap
        pos = Dict(x => i for (i, x) in enumerate(nodes.IDX))
        p = LJ._uf(nrow(nodes))
        for k in 1:nrow(links)
            LJ._join!(p, pos[links.SRC[k]], pos[links.DST[k]])
        end
        cd = [LJ._root!(p, i) for i in 1:nrow(nodes)]
        rows = Dict(x => v for (v, x) in enumerate(N.IDX))
        nf = maximum(I.fcomp)
        f2d = [Set{Int}() for _ in 1:nf]; d2f = Dict{Int,Set{Int}}()
        for (fi, x) in zip(nodemap.FAF5_IDX, nodemap.IDX)
            c = I.fcomp[rows[fi]]
            (ismissing(x) || c == 0) && continue
            push!(f2d[c], cd[pos[x]]); push!(get!(d2f, cd[pos[x]], Set{Int}()), c)
        end
        onlyramps = trues(nf)
        for k in 1:T.nL
            I.isramp[k] || (onlyramps[I.fcomp[T.S[k]]] = false)
        end
        splits = count(s -> length(s) > 1, f2d); merges = count(s -> length(s) > 1, values(d2f)); noimg = findall(isempty, f2d)
        println("  faf5net T4.3: FAF5 ", nf, " components, derived ", length(unique(cd)), "; splits ", splits, ", merges ", merges,
                "; without an image ", length(noimg), ", FAF5's components made only of ramps ", count(onlyramps))
        @test nf == 171 && length(unique(cd)) == 26                 # N0: 171; N2: 26 = 171 less 145
        @test splits == 0 && merges == 0 && noimg == findall(onlyramps) && length(noimg) == 145
    end

    @testset "T4.1, T4.2: 4.1's ten NC cities, distances and times against FAF5 as published (RN19)" begin
        N, L, _ = _fnfaf5()
        df = _fncities(); n = nrow(df)
        @test n == 10
        D1, T1 = _fnrouting(N, L, df)
        D2, T2 = _fnrouting(usrdnode(), usrdlink(), df)
        for (lab, A, B, tol) in (("T4.1 distance", D2, D1, ((1, 5), (3, 10))), ("T4.2 time", T2, T1, ((3, 8), (5, 12))))
            npairs = 0
            for (band, sel, (mlim, elim)) in (("over 50 mi", (i, j) -> D1[i, j] > 50, tol[1]),
                                              ("50 mi or less", (i, j) -> D1[i, j] <= 50, tol[2]))
                idx = [(i, j) for i in 1:n for j in 1:n if i != j && sel(i, j)]
                e = [_fnpct(A[i, j], B[i, j]) for (i, j) in idx]
                w = argmax(abs.(e)); m = sum(abs.(e)) / length(e)
                npairs += length(e)
                println("  faf5net ", lab, ", ", length(e), " pairs ", band, ": mean |error| ", round(m, digits = 2), "% (limit ", mlim,
                        "%), worst ", round(e[w], digits = 2), "% ", df.NAME[idx[w][1]], " to ", df.NAME[idx[w][2]], " (limit ", elim, "%)")
                @test m <= mlim && abs(e[w]) <= elim
            end
            @test npairs == 90                                      # the 90 ordered pairs of ten cities
        end
    end

    @testset "T4.4: High Point to Goldsboro against 4.1 Ex. 3's OSRM route (no network)" begin
        N, L, _ = _fnfaf5()
        fD, fT = _fnex3(N, L)                                       # FAF5 as published, as Ex. 3 computes it
        dD, dT = _fnex3(usrdnode(), usrdlink())
        oD, oT = _FN_OSRM
        println("  faf5net T4.4: OSRM ", oD, " mi, ", oT, " min; FAF5's shortest route ", round(fD[1], digits = 3), " mi (",
                round(fD[1] - oD, digits = 3), "), ", round(fT[1], digits = 3), " min (", round(fT[1] - oT, digits = 3),
                "); the derived network's ", round(dD[1], digits = 3), " mi (", round(dD[1] - oD, digits = 3), "), ",
                round(dT[1], digits = 3), " min (", round(dT[1] - oT, digits = 3), "); fastest routes ", round(fD[2], digits = 1),
                " and ", round(dD[2], digits = 1), " mi")
        @test abs(dD[1] - oD) <= abs(fD[1] - oD)                    # miles: as close to OSRM as FAF5's are
        # Ex. 3's table, read from the lecture where it is reachable
        lec = get(ENV, "LOGJAM_LECTURE_DATA", "")
        qmd = isempty(lec) ? "" : normpath(joinpath(lec, "..", "4-net-1.qmd"))
        if isfile(qmd)
            ls = readlines(qmd)
            c = findfirst(l -> occursin("{#tbl-osrm}", l), ls)
            k = c === nothing ? nothing : findlast(l -> startswith(l, "| 1 |"), ls[1:c])
            m = k === nothing ? nothing : match(r"^\| 1 \| ([\d.]+) \| ([\d.]+) \|", ls[k])
            @test m !== nothing && parse.(Float64, m.captures) == collect(_FN_OSRM)
        else
            @info "Lecture 4.1 not reachable (LOGJAM_LECTURE_DATA): Ex. 3's OSRM table not re-read"
        end
    end
end

_FN_FAF5[] = nothing                    # the shared derivation, released
