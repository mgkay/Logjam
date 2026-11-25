# test_k12_functions.jl -- the small functions K12 adds, each tested against the course definition it takes the place of
# (PCV K12, plan principles 8 and 9). The pins of what the course gets today are test_k12_pins.jl, whose case
# values and lecture texts this file reuses: a function that equals the lecture's definition on the lecture's inputs
# and seeds, and leaves the global stream where the lecture's leaves it, gives back every pinned value.

using Test
using Logjam
using DataFrames
using Random

isdefined(@__MODULE__, :K12PIN_MOVED) || include("test_k12_pins.jl")
include("oracle_helpers.jl")
isdefined(@__MODULE__, :LECTURE51_SFC) || include("lecture51_code.jl")
isdefined(@__MODULE__, :LECTURE42_COUNTY_BOX) || include("lecture42_code.jl")

# One fresh process per call, the way a lecture runs, started with this session's own flags (as test_extensions_c5.jl).
function _k12_child(code)
    out = IOBuffer()
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
    ok = success(pipeline(cmd; stdout = out, stderr = out))
    return ok, String(take!(out))
end

# ---- CR 47: randtour, disk, sfcpos and tspspfillcur were removed before the release -------------------------------
# (RTE27; IN1 and IN3, his inclusion rule of 2026-11-21: each is defined and used in Lecture 5.1 only). The lecture keeps
# its own definitions, which test_k12_pins.jl pins.
@testset "[K12] CR 47: randtour, disk, sfcpos and tspspfillcur are not in Logjam (RTE27, IN1, IN3)" begin
    for s in (:randtour, :disk, :sfcpos, :tspspfillcur)
        @test !isdefined(Logjam, s)
    end
end

# ---- names the course defines for itself (principle 9) --------------------------------------------------------
# a script that does `using Logjam` and then defines its own function, before using it, still runs and calls its own
# definition, on this Julia version; the definitions are Lecture 5.1's text, and Logjam has none of the four names
@testset "[K12] fresh process: Lecture 5.1's own randtour, disk, sfcpos and tspspfillcur run after using Logjam" begin
    code = "using Logjam\n" * LECTURE51_RANDTOUR * LECTURE51_DISK * LECTURE51_SFC * """
    Random.seed!(2024)
    t = randtour(6)
    println("own=", all(f -> parentmodule(f) === Main, (randtour, disk, sfcpos, tspspfillcur)))
    println("lib=", !any(s -> isdefined(Logjam, s), (:randtour, :disk, :sfcpos, :tspspfillcur)))
    println("run=", length(t) == 7, " ", size(disk(3)) == (3, 2), " ", tspspfillcur([0.8 0.8; 0.1 0.2; 0.3 0.7; 0.7 0.2]) == [1, 4, 2, 3, 1])
    """
    ok, out = _k12_child(code)
    @test ok
    @test occursin("own=true", out) && occursin("lib=true", out) && occursin("run=true true true", out)
end

# ---- LL (A1): lonlat and integer ZIPs ----------------------------------------------------------------------------
@testset "[K12] LL: lonlat is exported and documented; loc2lonlat takes integer ZIPs" begin
    @test Base.isexported(Logjam, :lonlat) && isdefined(Logjam, :lonlat)
    @test !occursin("No documentation found", string(Base.Docs.doc(Logjam.lonlat)))
    @test length(methods(Logjam.lonlat)) == 3
    @test isempty(Test.detect_ambiguities(Logjam))
end

@testset "[K12] LL: lonlat(df) is the hcat(df.LON, df.LAT) the course writes, at three sites" begin
    # Lecture 2.3 Code block 2 (2-loc-3.qmd:289-294)
    df = filter(r -> r.STFIP == st2fips(:NC) && r.POP > 100_000, usplace())
    select!(df, :NAME, :LON, :LAT, :POP)
    P = lonlat(df)
    @test P == hcat(df.LON, df.LAT) && P isa Matrix{Float64} && size(P) == (10, 2)
    @test _k12_fnv(P) == 0x1f9052710d782adb                                  # the pinned hcat, bit for bit
    # Lecture 5.1 Code block 27 (5-rte-1.qmd:2449)
    dc = filter(r -> r.STFIP == st2fips(:NC), uscounty())
    X = lonlat(dc)
    @test X == hcat(dc.LON, dc.LAT) && size(X) == (100, 2) && _k12_fnv(X) == 0x513ab69247baf81e
    # Lecture 2.6 (2-loc-6.qmd:499-500)
    z = filter(r -> r.ISCUS && r.POP > 0, uszcta3())
    Z = lonlat(z)
    @test Z == hcat(z.LON, z.LAT) && size(Z) == (882, 2) && _k12_fnv(Z) == 0xcb551bc70dba970b
    # the distance functions take it as it is: Lecture 2.3's `dists(P, P, :mi)`
    @test dists(lonlat(df), lonlat(df), :mi) == dists(hcat(df.LON, df.LAT), hcat(df.LON, df.LAT), :mi)
    # a view of a table, a table of integers, and a table of Float32
    @test lonlat(@view df[2:4, :]) == P[2:4, :]
    @test lonlat(DataFrame(LON = [1, 2], LAT = [3, 4])) == [1.0 3.0; 2.0 4.0]
    @test eltype(lonlat(DataFrame(LON = Float32[1, 2], LAT = Float32[3, 4]))) == Float64
    @test size(lonlat(DataFrame(LON = Float64[], LAT = Float64[]))) == (0, 2)
    # a missing coordinate is an error that names its row; so is a table without the columns
    miss = DataFrame(LON = [1.0, missing, 3.0], LAT = [4.0, 5.0, missing])
    e = try lonlat(miss); nothing catch err; err end
    @test e isa ArgumentError && occursin("row 2", e.msg) && occursin("missing", e.msg)
    e = try lonlat(DataFrame(LON = [1.0, 2.0], LAT = [missing, 5.0])); nothing catch err; err end
    @test e isa ArgumentError && occursin("row 1", e.msg)
    @test_throws ArgumentError lonlat(DataFrame(X = [1.0], Y = [2.0]))
    @test lonlat(DataFrame(LON = Union{Missing, Float64}[1.0, 2.0], LAT = [3.0, 4.0])) == [1.0 3.0; 2.0 4.0]    # a Union column with no missing
end

@testset "[K12] LL: lonlat(row) and lonlat(v) are the lecture's [c.LON, c.LAT] and [getindex.(S, :LON) getindex.(S, :LAT)]" begin
    # a DataFrameRow, and the named tuples wcentroid and loc2lonlat return (Lecture 2.2 `optimize(TC, [w.LON, w.LAT])`,
    # Lecture 4.1 `[c.LON, c.LAT]`)
    df = filter(r -> r.STFIP == st2fips(:NC), uscounty())
    @test lonlat(df[3, :]) == [df.LON[3], df.LAT[3]] && lonlat(df[3, :]) isa Vector{Float64}
    @test lonlat(first(eachrow(df))) == [df.LON[1], df.LAT[1]]
    w = wcentroid(df.LON, df.LAT, df.POP)
    @test lonlat(w) == [w.LON, w.LAT]
    c = loc2lonlat("Memphis"; state = :TN)
    @test lonlat(c) == [c.LON, c.LAT]
    @test lonlat((LON = 1, LAT = 2)) == [1.0, 2.0]
    @test_throws ArgumentError lonlat((LON = missing, LAT = 2.0))
    @test_throws ArgumentError lonlat((X = 1.0, Y = 2.0))
    # Lecture 3.4 Code block 18 (3-tran-4.qmd:1254-1271)
    Scity = ["Rochester", "Orlando", "San Antonio"]; Sst = [:NY, :FL, :TX]
    S = [loc2lonlat(c; state = st) for (c, st) in zip(Scity, Sst)]
    SXY = [getindex.(S, :LON) getindex.(S, :LAT)]
    @test lonlat(S) == SXY && lonlat(S) isa Matrix{Float64} && size(SXY) == (3, 2)
    Ccity = ["Portland", "Tucson", "Denver", "Milwaukee"]; Cst = [:OR, :AZ, :CO, :WI]
    C = [loc2lonlat(c; state = st) for (c, st) in zip(Ccity, Cst)]
    @test lonlat(C) == [getindex.(C, :LON) getindex.(C, :LAT)]
    DC = loc2lonlat("Memphis"; state = :TN)
    @test lonlat(DC) == vec([DC.LON DC.LAT])
    # the same list through the table the vector method returns
    @test lonlat(loc2lonlat(Scity; state = Sst)) == SXY
    # a vector of named tuples of different types (a place not found has missing coordinates), and the empty vector
    mixed = [c, loc2lonlat("Xyzzy")]
    e = try lonlat(mixed); nothing catch err; err end
    @test e isa ArgumentError && occursin("element 2", e.msg)
    @test size(lonlat(typeof(c)[])) == (0, 2)
    @test_throws ArgumentError lonlat([(LON = 1.0, LAT = 2.0), (X = 1,)])
end

@testset "[K12] LL: loc2lonlat takes integer ZIPs and returns what the string call returns" begin
    @test loc2lonlat(27601) == loc2lonlat("27601")
    @test loc2lonlat(2139) == loc2lonlat("02139")                            # zero-padded, as the DataFrame method pads
    @test loc2lonlat(2139) == (LON = -71.102336, LAT = 42.362391, GC_SOURCE = "POSTALCODE",
                               GC_UNCERT = 0.46857559255316794, GC_STATUS = "OK")
    @test loc2lonlat(UInt16(2139)) == loc2lonlat("02139") && loc2lonlat(Int32(27601)) == loc2lonlat("27601")
    zs = [27601, 2139, 10001, 90210]
    @test loc2lonlat(zs).INPUT == ["27601", "02139", "10001", "90210"]
    @test loc2lonlat(zs) == loc2lonlat(["27601", "02139", "10001", "90210"])  # the pinned string call
    @test loc2lonlat(view(zs, 2:3)) == loc2lonlat(["02139", "10001"])        # any AbstractVector
    @test isequal(loc2lonlat(1:3), loc2lonlat(["00001", "00002", "00003"]))  # a range of integers (not in the table: missing)
    @test isequal(loc2lonlat(Int[]), loc2lonlat(String[]))
    # the keywords are the string methods'
    @test loc2lonlat(27601; state = :NC) == loc2lonlat("27601"; state = :NC)
    @test loc2lonlat([27601, 2139]; state = [:NC, :MA]) == loc2lonlat(["27601", "02139"]; state = [:NC, :MA])
    # the DataFrame method pads the same ZIP the same way
    @test loc2lonlat(DataFrame(POSTALCODE = [2139])).LON == [loc2lonlat(2139).LON]
    # a ZIP that is not in the table is FAIL, and lonlat then stops at its row
    f = loc2lonlat(501)
    @test (f.GC_STATUS, ismissing(f.LON)) == ("FAIL", true)
    e = try lonlat(loc2lonlat([27601, 501, 2139])); nothing catch err; err end
    @test e isa ArgumentError && occursin("row 2", e.msg)
    @test_throws ArgumentError loc2lonlat(100000)
    @test_throws ArgumentError loc2lonlat(-1)
    @test_throws ArgumentError loc2lonlat([27601, 123456])
    # a homework locates ZIPs by `leftjoin` with uszcta5; lonlat(loc2lonlat(zips)) is the same matrix
    z5 = uszcta5()[!, [:ZCTA5, :LON, :LAT]]
    key(zips) = (df = leftjoin(DataFrame(ZCTA5 = zips), z5; on = :ZCTA5, order = :left); Float64.([df.LON df.LAT]))
    zD = [20002, 26149, 36317]; zC = [30669, 32606, 30733, 23830, 23061]; zP = [28124, 27101, 37421, 27513]
    for zips in (zD, zC, zP)
        @test lonlat(loc2lonlat(zips)) == key(zips)
    end
    @test dists(lonlat(loc2lonlat(zD)), lonlat(loc2lonlat(zC)), :mi) == dists(key(zD), key(zC), :mi)
end

# ---- CR 12: usstate ----------------------------------------------------------------------------------------------
@testset "[K12] CR 12: usstate is one row per state, aggregated from uscounty" begin
    @test Base.isexported(Logjam, :usstate) && !occursin("No documentation found", string(Base.Docs.doc(Logjam.usstate)))
    S = usstate()
    C = uscounty()
    @test names(S) == ["STFIP", "ST", "NAME", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS"]
    @test nrow(S) == 51 && issorted(S.STFIP) && allunique(S.ST) && allunique(S.STFIP)
    @test eltype.(eachcol(S)) == [Int, Symbol, String, Float64, Float64, Int, Float64, Float64, Bool]
    @test Set(S.ST) == Set(C.ST) && all(st -> st2fips(st) in S.STFIP, S.ST)
    @test S.NAME[S.ST .== :NC] == ["North Carolina"] && S.NAME[S.ST .== :DC] == ["District of Columbia"]
    @test S.NAME[S.ST .== :WV] == ["West Virginia"]
    # the populations sum to the county total, state by state and overall; the areas likewise
    @test sum(S.POP) == sum(C.POP)
    @test all(r -> r.POP == sum(C.POP[C.STFIP .== r.STFIP]), eachrow(S))
    @test isapprox(sum(S.ALAND), sum(C.ALAND); rtol = 1e-12) && isapprox(sum(S.AWATER), sum(C.AWATER); rtol = 1e-12)
    @test all(r -> isapprox(r.ALAND, sum(C.ALAND[C.STFIP .== r.STFIP]); rtol = 1e-12), eachrow(S))
    # the centroid is the geocoder's STATE tier (the population-weighted mean of the county centers), bit for bit
    for st in (:NC, :NY, :TX, :DC, :AK)
        g = Logjam._resolve_state(st)
        r = S[S.ST .== st, :][1, :]
        @test (r.LON, r.LAT) == (g.lon, g.lat) && isapprox(r.ALAND, g.aland; rtol = 1e-12)
    end
    # and the centroid aggregated from the block groups (a county's center is the mean of its block groups')
    B = uscenblkgrp()
    for st in (:NC, :CA, :NY, :TX, :FL, :DC, :CT)
        b = B[B.STFIP .== st2fips(st), :]
        r = S[S.ST .== st, :][1, :]
        @test r.POP == sum(b.POP)
        # within 2e-4 degrees (about 50 feet of latitude): the published county centers are rounded to six places
        # and each is a mean of its block groups' rounded centers
        @test isapprox(r.LON, sum(b.LON .* b.POP) / sum(b.POP); atol = 2e-4)
        @test isapprox(r.LAT, sum(b.LAT .* b.POP) / sum(b.POP); atol = 2e-4)
    end
    # a copy: changing what a call returns does not change the next
    S.POP .= 0; select!(S, :ST)
    S2 = usstate()
    @test sum(S2.POP) == sum(C.POP) && ncol(S2) == 9
    @test usstate() !== usstate() && isequal(usstate(), usstate())
end

# ISCUS is "within continental U.S.": the box of CUS_LIMITS. The ZIP tables carry it too, and it is the ZIP prefix rule
# (the 3-digit prefixes outside the continental U.S.: 006-009 Puerto Rico and the Virgin Islands, 967-968 Hawaii and the
# Pacific, 995-999 Alaska): a guard on the shipped tables. (Both ZCTA tables carry 40 Puerto Rico ZCTAs, 009xx only,
# although their docstrings say they exclude territories: a v0.3.1 data item.)
@testset "[K12] ISCUS: the ZIP tables' flag is the prefix rule, and usstate's is false for Alaska and Hawaii only" begin
    outside(p) = (6 <= p <= 9) || (967 <= p <= 968) || (995 <= p <= 999)
    z5 = uszcta5()
    @test z5.ISCUS == .!outside.(z5.ZCTA5 .÷ 100)
    z3 = uszcta3()
    @test z3.ISCUS == .!outside.(z3.ZCTA3)
    @test any(z5.ISCUS) && any(.!z5.ISCUS) && any(z3.ISCUS) && any(.!z3.ISCUS)
    S = usstate()
    territories = [:AS, :GU, :MP, :PR, :VI]
    nonus = S.ST[.!S.ISCUS]
    @test sort(nonus) == sort(vcat([:AK, :HI], intersect(S.ST, territories)))     # Alaska, Hawaii and any territory the table carries
    @test all(S.ISCUS[in.(S.ST, Ref(nonus)) .== false])                    # the 48 contiguous states and DC
    @test count(S.ISCUS) == 49 && S.ISCUS[S.ST .== :DC] == [true]
end

# ---- CR 28: a county's box, offline ---------------------------------------------------------------------------------
@testset "[K12] CR 28: mapbbox(county; state) is Lecture 4.2's Wake box, in mapbbox's shape" begin
    m = lecture42_module()
    bbW = Base.invokelatest(getfield, m, :bbW)                       # (xmin, xmax, ymin, ymax), the lecture's order
    bb = mapbbox("Wake"; state = :NC)
    @test bb isa Tuple{Tuple{Float64, Float64}, Tuple{Float64, Float64}}
    @test (bb[1][1], bb[1][2], bb[2][1], bb[2][2]) == bbW             # bit for bit, reordered
    @test all(isapprox.([bb[1]..., bb[2]...], collect(bbW); rtol = 1e-12))
    @test (bb[1][1], bb[1][2], bb[2][1], bb[2][2]) == (-78.97544182356803, -78.27350863429567, 35.52318408209017, 36.080417439618664)
    # osm_roads snaps it to the tile 4.2's box snaps to, in either shape
    @test Logjam._osm_snap_bbox(bb) == Logjam._osm_snap_bbox(bbW)
    @test Logjam._osm_cache_path(bb, "d") == Logjam._osm_cache_path(bbW, "d")
    # the same county by another spelling, state as a string or a name
    @test mapbbox("wake county"; state = "NC") == bb && mapbbox("  Wake  "; state = "North Carolina") == bb
    # the expansion keywords widen it as they widen a box
    @test mapbbox("Wake"; state = :NC, xexpand = 0.1, yexpand = 0.2) == mapbbox(bb; xexpand = 0.1, yexpand = 0.2)
    # another county: its box contains the county's own center of population
    d = mapbbox("Durham"; state = :NC)
    du = only(filter(r -> r.ST == :NC && r.NAME == "Durham", uscounty()))
    @test d[1][1] < du.LON < d[1][2] && d[2][1] < du.LAT < d[2][2]
    # errors name what is wrong
    e = try mapbbox("Wakee"; state = :NC); nothing catch err; err end
    @test e isa ArgumentError && occursin("Wakee", e.msg) && occursin("NC", e.msg)
    e = try mapbbox("Wake"; state = :XX); nothing catch err; err end
    @test e isa ArgumentError && occursin("XX", e.msg)
    e = try mapbbox("Wake"; state = "Atlantis"); nothing catch err; err end
    @test e isa ArgumentError && occursin("Atlantis", e.msg)
    @test_throws ArgumentError mapbbox("Wake")
    @test_throws ArgumentError mapbbox("   "; state = :NC)
    # the existing methods are as they were
    @test mapbbox([-78.6, -80.8], [35.8, 35.2]) == ((-80.8, -78.6), (35.2, 35.8))
    @test mapbbox(bb) == bb
    @test isempty(Test.detect_ambiguities(Logjam))
end

# ---- C12: usstates is public, read once, and a copy for each call -----------------------------------------------
@testset "[K12] C12: usstates is public (not exported), returns a copy, and returns what it returned" begin
    @test Base.ispublic(Logjam, :usstates) && !Base.isexported(Logjam, :usstates)
    @test !occursin("No documentation found", string(Base.Docs.doc(Logjam.usstates)))
    x, y = Logjam.usstates()
    @test (_k12_fnv(x), _k12_fnv(y)) == (0xbd5dfc034f397b93, 0x73b1dce3c71f5e75)       # the pinned values
    @test (length(x), count(isnan, x)) == (3642, 103)
    x2, y2 = Logjam.usstates()
    @test x2 !== x && y2 !== y && isequal(x2, x) && isequal(y2, y)                     # a copy for each call
    fill!(x, 0.0); empty!(y)                                                           # changing a result ...
    x3, y3 = Logjam.usstates()
    @test _k12_fnv(x3) == 0xbd5dfc034f397b93 && length(y3) == 3642                    # ... does not change the next
    @test Logjam.usstates() isa Tuple{Vector{Float64}, Vector{Float64}}
    @test usstate() isa DataFrame && !isdefined(Main, :usstates)                       # usstate is exported, usstates is not
end

@testset "[K12] fresh process: a script that defines its own lonlat (a homework's own `lonlat`, a variable) still runs and calls its own" begin
    # a homework's one-line method `lonlat(df)`; the join of a table's `zip` column with uszcta5
    hw3 = """
    using Logjam, DataFrames
    z5 = uszcta5()[!, [:ZCTA5, :LON, :LAT]]
    lonlat(df) = leftjoin(rename(df, :zip => :ZCTA5), z5; on = :ZCTA5, order = :left)
    S = lonlat(DataFrame(zip = [27601, 2139]))
    println("hw3=", S isa DataFrame, " ", parentmodule(lonlat) === Main, " ", Logjam.lonlat !== lonlat)
    """
    # another homework's `function lonlat(zips)`, the coordinates of integer ZIPs as a matrix
    hw4 = """
    using Logjam, DataFrames
    z5 = uszcta5()[!, [:ZCTA5, :LON, :LAT]]
    function lonlat(zips)
        df = leftjoin(DataFrame(ZCTA5 = zips), z5; on = :ZCTA5, order = :left)
        @assert !any(ismissing, df.LON)
        return Float64.([df.LON df.LAT])
    end
    C = dists(lonlat([20002, 26149]), lonlat([30669, 32606, 30733]), :mi)
    println("hw4=", size(C) == (2, 3), " ", parentmodule(lonlat) === Main, " ", Logjam.lonlat !== lonlat)
    """
    # a generator that names a variable `lonlat` after `using Logjam` (two of the Location lectures' figure generators do)
    var = """
    using Logjam, DataFrames
    names_ = [(-78.6, 35.8), (-80.8, 35.2)]
    lonlat = first.(names_)
    println("var=", lonlat == [-78.6, -80.8], " ", Logjam.lonlat isa Function)
    """
    for (tag, code) in (("hw3", hw3), ("hw4", hw4), ("var", var))
        ok, out = _k12_child(code)
        @test ok
        @test occursin("$tag=true", out)
        tag == "var" || @test occursin("true true true", out)
    end
end
