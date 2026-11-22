# test_faf5net.jl -- the derived FAF5 road network (CR 19), part one (PCV N1): route keys, the Interstate flag (RN3)
# and the ramp rule (RN4), on synthetic cases and on FAF5 as Logjam ships it. The expected FAF5 counts are N0's
# measurements where N0 measured the same thing, and N1's own otherwise (each says which).

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

@testset "faf5net: route keys, the Interstate flag, ramps (N1)" begin
    @testset "_route: one key per road" begin
        # state-route prefixes unified (N0's cases of one road under two keys)
        @test LJ._route("FL 429", missing) == LJ._route(missing, "SR 429") == "SR 429"
        for (a, b) in (("OR 99W", "SR 99W"), ("CO 7", "SR 7"), ("SR 7", "VA 7"), ("CA 68", "SR 68"), ("PA 611", "SR 611"))
            @test LJ._route(a, missing) == LJ._route(b, missing) == LJ._route(missing, b)
        end
        @test LJ._route(missing, "STATE HWY 7") == "SR 7"
        # direction letters dropped; a letter suffix is part of the route
        @test LJ._route("I 93 N", missing) == LJ._route("I 93 S", missing) == "I 93"
        @test LJ._route(missing, "I 496 EB") == "I 496"
        @test LJ._route("I 35E", missing) == "I 35E" != LJ._route("I 35W", missing)
        @test LJ._route("MO N", missing) == "MO N"                     # the letter is the route itself
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

    @testset "_isinterstate (RN3, T2.10)" begin
        @test LJ._isinterstate("US 131", "I 296", 1)                  # I-296, found by its NAME on a class 1 link
        @test !LJ._isinterstate("US 131", "I 296", 2)                 # NAME counts only on class 1
        @test LJ._isinterstate(missing, "I 496 EB", 1)
        @test !LJ._isinterstate("I 40 B", missing, 3)                  # never a Business route
        @test !LJ._isinterstate("I 40 B", "I 40", 1)
        @test !LJ._isinterstate("I 20E B", missing, 2)
        @test LJ._isinterstate("I 93 N", missing, 1) && LJ._isinterstate("I 93 S", missing, 1)
        @test LJ._route("I 93 N", missing) == LJ._route("I 93 S", missing)
        @test LJ._isinterstate("I 35E", missing, 1) && LJ._isinterstate("I 480N", missing, 1)
        @test !LJ._isinterstate("US 50", "JOHN HANSON HWY", 1)         # I-595, which FAF5 has only as US 50
        @test !LJ._isinterstate("I H1", missing, 1)                    # RN3 as ruled: "I", then a number
        @test !LJ._isinterstate(missing, "I 270 - LOCAL LANES", 1)     # not exactly a designation
        @test !LJ._isinterstate(missing, missing, 1)
    end

    @testset "_isramp_name (RN4, T2.8)" begin
        for n in ("I 96 EB TO I 696 EB", "COLLECCTOR/DISTRIBUTOR", "I 80 COLLECCTOR/DISTRIBUTOR LANE",
                  "I 75 NB COLLECTOR/DISTRBUTOR LANE", "I 75 WB COLLECTION/DISTRIBUTION LANE",
                  "I 15 SB TO I 515 / US 95 NB", "I 395 SB TO I 95 NB/I 495 IL", "I 5 B NB TO I 90 EB",
                  "CR 200 TO US 27 NB", "RAMP", "I 40 EB RAMP", "COLLECTOR/DISTRIBUTOR LANE", "RI 4 CONNECTOR/DISTRIBUTOR LANE",
                  "TURN LANE", "i 96 eb to i 696 eb")
            @test LJ._isramp_name(n)
        end
        for n in ("GOING TO THE SUN HWY", "AIRPORT CONNECTOR", "DOWNTOWN DISTRIBUTOR", "N RAMPART ST",
                  "I 196 EB TO CHICAGO DR", "I-70 EB TURNAROUND/SERVICE ROAD", "", missing)
            @test !LJ._isramp_name(n)
        end
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

    @testset "on FAF5 as Logjam ships it" begin
        N = faf5nodes(); L = faf5links()
        sgn = String.(coalesce.(L.SIGN, "")); nm = uppercase.(String.(coalesce.(L.NAME, "")))

        # the name rule, part by part
        v030 = LJ._isramp_v030.(L.NAME); cd = LJ._isramp_cd.(L.NAME); to = LJ._isramp_to.(L.NAME)
        named = LJ._isramp_name.(L.NAME)
        toN0 = [!v030[k] && occursin(r"\bTO\b", nm[k]) for k in eachindex(nm)]
        println("  faf5net ramps by name: v0.3.0 rule ", count(v030), "; C/D however spelled, beyond it ", count(cd .& .!v030),
                "; X TO Y, beyond it ", count(to .& .!v030), " of N0's ", count(toN0), " TO names; all ", count(named))
        @test count(v030) == 137_156                          # N0, and v0.3.0's map filter
        @test count(cd .& .!v030) == 35                       # N1: four misspelt names; N0's 50 also held 9 turnarounds and 6 DOWNTOWN DISTRIBUTOR
        @test sort(unique(nm[cd .& .!v030])) == ["I 75 NB COLLECTOR/DISTRBUTOR LANE", "I 75 WB COLLECTION/DISTRIBUTION LANE",
                                                 "I 80 COLLECCTOR/DISTRIBUTOR LANE", "US 3 COLLECTOR/DISTRBUTOR LANE"]
        @test count(toN0) == 337                              # N0
        @test count(to .& .!v030) == count(to .& toN0) == 304 # N1: both sides route designations (RN4)
        @test count(named) == 137_156 + 35 + 304
        @test !any(named[nm .== "GOING TO THE SUN HWY"]) && !any(named[nm .== "DOWNTOWN DISTRIBUTOR"])

        # the structural test
        isr = LJ._ramp_links(N, L)
        st = isr .& .!named
        println("  faf5net ramps by the structural test: ", count(st), " (by class ",
                join(["$c: $(count(st .& (L.FCLASS .== c)))" for c in sort(unique(L.FCLASS))], ", "), "); ramps in all ", count(isr))
        @test count(st) == 2_272                              # N1 (N0 measured classes 1 and 2 only, by another cluster)
        @test count(isr) == 139_767
        @test all(LJ._keytext(L.SIGN[k]) === nothing && LJ._keytext(L.NAME[k]) === nothing && L.DIR[k] != 0 for k in findall(st))

        # the Interstate flag
        fl = [LJ._isinterstate(L.SIGN[k], L.NAME[k], L.FCLASS[k]) for k in 1:nrow(L)]
        bus = occursin.(r"^I \S+ B$", sgn)
        byname = fl .& .!startswith.(sgn, "I ")
        println("  faf5net Interstate flag: ", count(fl), " links, ", count(byname), " by NAME alone; not flagged: ",
                count(bus), " Business Interstate links, ", count(occursin.(r"^I [AH]\d+$", sgn)), " signed I A1 to A4, I H1 to H3")
        @test count(bus) == 855 && !any(fl[bus])              # N0: 855 Business Interstate links
        @test count(byname) == 21                             # N0: I-296 (20 links) and one "I 496 EB"
        @test count(fl .& (sgn .== "US 131") .& (nm .== "I 296")) == 20
        @test all(fl[occursin.(r"^I \S+ [NSEW]$", sgn)])      # N0: 41 links with a direction suffix
        @test count(fl) == 80_905

        # N0's 588 crossings where one road met itself under two keys (a one-way class 2 or 3 link meeting a link of
        # another key, with another node of the same pair of keys, the keys sharing a number): state-route prefixes
        # are unified; the rest are different roads (Business, Bypass, Alternate and Loop routes, frontage and
        # service roads, a US route beside a state route of the same number).
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
                " are one key now, among them all ", length(state), " that differ only in a state-route prefix")
        @test length(cases) == 588                            # N0
        @test count(p -> same(p...), cases) == 281            # N1
        @test length(state) == 268 && all(p -> same(p...), state)
        @test !same("US 30", "US 30 B") && !same("TX 71", "TX 71 P") && !same("DE 13", "US 13")
    end
end
