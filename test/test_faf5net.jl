# test_faf5net.jl -- the derived FAF5 road network (CR 19), part one (PCV N1): route keys, the Interstate flag, the
# ramp rule and the junctions (his rulings RN3 to RN10), on synthetic cases and on FAF5 as Logjam ships it. The expected
# FAF5 counts are N0's measurements where N0 measured the same thing, and N1's own otherwise (each says which).

using Test
using Logjam
using DataFrames
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
        named = LJ._isramp_name.(L.NAME, L.DIR)
        toN0 = [!v030[k] && occursin(r"\bTO\b", nm[k]) for k in eachindex(nm)]
        println("  faf5net ramps by name: v0.3.0 rule ", count(v030), "; C/D however spelled, beyond it ", count(cd .& .!v030),
                "; X TO Y, beyond it ", count(to .& .!v030), " of N0's ", count(toN0), " TO names; all ", count(named))
        @test count(v030) == 137_156                          # N0, and v0.3.0's map filter
        @test count(cd .& .!v030) == 35                       # N1: four misspelt names; N0's 50 also held 9 turnarounds and 6 DOWNTOWN DISTRIBUTOR
        @test sort(unique(nm[cd .& .!v030])) == ["I 75 NB COLLECTOR/DISTRBUTOR LANE", "I 75 WB COLLECTION/DISTRIBUTION LANE",
                                                 "I 80 COLLECCTOR/DISTRIBUTOR LANE", "US 3 COLLECTOR/DISTRBUTOR LANE"]
        @test count(toN0) == 337                              # N0
        @test count(to .& .!v030) == count(to .& toN0) == 333 # N1: one-way, a designation on one side at least (RN10)
        @test sort(unique(nm[toN0 .& .!to])) == ["DIBC PLAZA TO CANADA", "GOING TO THE SUN HWY"]
        @test count(named) == 137_156 + 35 + 333
        @test !any(named[nm .== "DOWNTOWN DISTRIBUTOR"])

        # the structural test
        isr = LJ._ramp_links(N, L)
        st = isr .& .!named
        println("  faf5net ramps by the structural test: ", count(st), " (by class ",
                join(["$c: $(count(st .& (L.FCLASS .== c)))" for c in sort(unique(L.FCLASS))], ", "), "); ramps in all ", count(isr))
        @test count(st) == 2_272                              # N1 (N0 measured classes 1 and 2 only, by another cluster)
        @test count(isr) == 139_796
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
        @test nc == 22_579                                    # N1
        @test count(==(:interchange), J.kind) == 15_914 && count(==(:atgrade), J.kind) == 6_665
        @test count(>(0), J.cl) == 156_175
        @test agext < 400                                     # 150 m within one route pair, chained: 302.9 m at most (N1)
        @test nI == 858                                       # N1; 4.1's 754 (N0), its own clusters under RN6's merge 788
    end
end
