# test_geocode.jl -- the tests of src/geocode.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_datatools.jl, its lines 1-2, 165-224 ====
using Test
using DataFrames

# Test for loc2lonlat function (replaces name2lonlat)
@testset "loc2lonlat basic tests" begin
    # Basic lookup with state filter
    r = loc2lonlat("Raleigh", state=:NC)
    @test r.GC_STATUS == "OK"
    @test -79.5 < r.LON < -78.0   # LON range for Raleigh
    @test 35.5 < r.LAT < 36.0     # LAT range for Raleigh

    # Not found: with no state nothing answers; with one the ladder ends at the state (GC)
    @test loc2lonlat("Nonexistent City XYZ").GC_STATUS == "FAIL"
    r2 = loc2lonlat("Nonexistent City XYZ", state=:NC)
    @test (r2.GC_SOURCE, r2.GC_STATUS) == ("STATE", "PARTIAL")
end

# Test for lonlat2loc function (replaces lonlat2name)
@testset "lonlat2loc basic tests" begin
    cities = usplace()

    # --- Schema test: all expected columns present ---
    xy = [-78.6382 35.7796]  # near Raleigh, NC
    result = lonlat2loc(xy, cities)
    @test isa(result, DataFrame)
    @test nrow(result) == 1
    for col in ["idx", "NAME", "ST", "dist", "bearing", "dir", "desc"]
        @test col in names(result)
    end

    # --- In-city threshold behavior ---
    @test startswith(result.desc[1], "in ")
    @test result.NAME[1] == "Raleigh"
    @test result.ST[1] == :NC   # ST is now a Symbol (matches usplace().ST)

    # --- Bearing range: 0 <= bearing < 2pi ---
    @test 0.0 <= result.bearing[1] < 2pi

    # --- Cardinal direction and description format ---
    # Use large-city filter so test point is far from nearest match
    big = filter(r -> r.POP > 100_000 && r.ISCUS, cities)
    # Point ~50 mi east of Raleigh (same lat, shifted lon)
    xy_east = [-77.8 35.7796]
    res_east = lonlat2loc(xy_east, big)
    # Should not be "in" city (beyond threshold)
    @test occursin(" mi ", res_east.desc[1])
    @test occursin(" of ", res_east.desc[1])

    # --- Vector input (single [LON, LAT]) ---
    res_vec = lonlat2loc([-78.6382, 35.7796], cities)
    @test res_vec.NAME == result.NAME[1]

    # --- Multi-row matrix input ---
    xy_multi = [-78.6382 35.7796; -80.8431 35.2271]  # Raleigh, Charlotte
    res_multi = lonlat2loc(xy_multi, cities)
    @test nrow(res_multi) == 2
    @test res_multi.NAME[1] == "Raleigh"
    @test res_multi.NAME[2] == "Charlotte"

    # --- Invalid input ---
    @test_throws ArgumentError lonlat2loc([1.0, 2.0, 3.0], cities)
end

# ==== moved from test/test_dist_geo_pins.jl, its lines 1-24 ====
# test_dist_geo_pins.jl -- value equality of the course's distance and geocoding calls against the
# committed fixture (PCV K5, plan principle 9). A call the course makes today keeps returning what it
# returned at v0.2.8. Only a case named for a ruled item (N1_, N5_, N7_, N8_, N19_, CR26_, S3_, S14_,
# S15_) may differ, and each fixture update is named in its commit. Regenerate with
# tools/v0_3_0/make_dist_geo_pins.jl. No case touches the network.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "dist_geo_pin_helpers.jl"))

@testset "distance and geocoding calls are pinned value for value" begin
    fixture = dgpin_read()
    cases = dgpin_cases()
    @test length(fixture) == length(cases)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(fixture, name)
            haskey(fixture, name) || continue
            @test dgpin_run(thunk) == fixture[name]
        end
    end
end

# ==== moved from test/test_k12_pins.jl, its lines 1-24, 173-209 ====
# test_k12_pins.jl -- what the course gets today from the calls K12's new functions replace or sit beside, pinned from
# the code at 4e7ce94 (PCV K12, plan principle 9). Every value below was measured on the unchanged code, before K12
# added `randtour`, `disk`, `sfcpos`, `tspspfillcur`, `lonlat`, integer ZIPs, `usstate`, the `usstates` declaration and
# the county box. A call the course makes today keeps returning what it returned then; only a case named in K12PIN_MOVED
# may differ, and each one is named in the commit that moves it. (Logjam's own `randtour`, `disk`, `sfcpos` and
# `tspspfillcur` were removed before the release, rulings RTE27, IN1 and IN3; the lecture's definitions are what is pinned.)
#
# What is pinned: the lecture definitions themselves (Lecture 5.1's `randtour`, `disk`, `sfcpos`, `tspspfillcur`, Lecture
# 4.2's Code block 3), run as text in a scratch module that has done `using Logjam` first, their outputs on the
# course's own inputs and seeds, and the global random stream after each seeded draw (the next `rand()`); the
# `hcat(df.LON, df.LAT)` the course writes at three sites; `loc2lonlat` on string ZIPs; and `Logjam.usstates()`.
# Draws that `randperm` makes differ between Julia 1.12 and 1.13 (the generator's stream is the same, `randperm`'s use of
# it is not), so those values are pinned per version and compared with the lecture's definition only on another.
#
# No case touches the network or a file outside the package, and none renders a picture.

using Test
using Logjam
using DataFrames
using Random

isdefined(@__MODULE__, :ORACLE_DIR) || include("oracle_helpers.jl")
isdefined(@__MODULE__, :LECTURE51_SFC) || include("lecture51_code.jl")
isdefined(@__MODULE__, :LECTURE42_COUNTY_BOX) || include("lecture42_code.jl")
isdefined(@__MODULE__, :K12PIN_MOVED) || include(joinpath(@__DIR__, "k12_helpers.jl"))   # WP8: defined once

# ---- the hcat the course writes -----------------------------------------------------------------------------------
@testset "[K12 pin] hcat(df.LON, df.LAT) at three course sites" begin
    @test !_k12pin_moved("hcat")
    # Lecture 2.3, Code block 2 (2-loc-3.qmd:289-294): the NC cities over 100,000
    df = filter(r -> r.STFIP == st2fips(:NC) && r.POP > 100_000, usplace())
    select!(df, :NAME, :LON, :LAT, :POP)
    P = hcat(df.LON, df.LAT)
    @test size(P) == (10, 2) && eltype(P) == Float64
    @test P[1, :] == [-78.819011, 35.78145] && _k12_fnv(P) == 0x1f9052710d782adb
    # Lecture 5.1, Code block 27 (5-rte-1.qmd:2449): the 100 NC counties
    dc = filter(r -> r.STFIP == st2fips(:NC), uscounty())
    X = hcat(dc.LON, dc.LAT)
    @test size(X) == (100, 2) && eltype(X) == Float64
    @test X[1, :] == [-79.413154, 36.071544] && _k12_fnv(X) == 0x513ab69247baf81e
    # Lecture 2.6, Code block (2-loc-6.qmd:499-500): the 3-digit ZIP areas
    z = filter(r -> r.ISCUS && r.POP > 0, uszcta3())
    Z = hcat(z.LON, z.LAT)
    @test size(Z) == (882, 2) && eltype(Z) == Float64
    @test Z[1, :] == [-72.57315772581423, 42.2125312208976] && _k12_fnv(Z) == 0xcb551bc70dba970b
end

@testset "[K12 pin] loc2lonlat on string ZIPs (the POSTALCODE tier), which the integer methods must equal" begin
    @test !_k12pin_moved("loc2lonlat_zip")
    r = loc2lonlat(["27601", "02139", "10001", "90210"])
    @test r.INPUT == ["27601", "02139", "10001", "90210"]
    @test r.LON == [-78.634563, -71.102336, -73.997298, -118.41463]
    @test r.LAT == [35.773661, 42.362391, 40.750649, 34.100517]
    @test r.GC_SOURCE == fill("POSTALCODE", 4) && r.GC_STATUS == fill("OK", 4)
    @test r.GC_UNCERT == [0.5071433604381534, 0.46857559255316794, 0.2971160409138231, 1.23309811391261]
    @test loc2lonlat("27601") == (LON = -78.634563, LAT = 35.773661, GC_SOURCE = "POSTALCODE",
                                  GC_UNCERT = 0.5071433604381534, GC_STATUS = "OK")
    @test loc2lonlat("02139") == (LON = -71.102336, LAT = 42.362391, GC_SOURCE = "POSTALCODE",
                                  GC_UNCERT = 0.46857559255316794, GC_STATUS = "OK")
    f = loc2lonlat("00501")                                   # a ZIP not in the table
    @test (f.GC_STATUS, f.GC_SOURCE, ismissing(f.LON), ismissing(f.LAT)) == ("FAIL", "", true, true)
end

# ==== moved from test/test_k12_functions.jl, its lines 1-14, 48-155, 266-301 ====
# test_k12_functions.jl -- the small functions K12 adds, each tested against the course definition it takes the place of
# (PCV K12, plan principles 8 and 9). The pins of what the course gets today are test_k12_pins.jl, whose case
# values and lecture texts this file reuses: a function that equals the lecture's definition on the lecture's inputs
# and seeds, and leaves the global stream where the lecture's leaves it, gives back every pinned value.

using Test
using Logjam
using DataFrames
using Random

isdefined(@__MODULE__, :K12PIN_MOVED) || include("k12_helpers.jl")
isdefined(@__MODULE__, :ORACLE_DIR) || include("oracle_helpers.jl")
isdefined(@__MODULE__, :LECTURE51_SFC) || include("lecture51_code.jl")
isdefined(@__MODULE__, :LECTURE42_COUNTY_BOX) || include("lecture42_code.jl")

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

# ==== moved from test/test_geocode.jl, its lines 1-892 ====
# =============================================================================
# Tests for geocode.jl — Core geocoding (no network dependency)
# =============================================================================
using DataFrames

@testset "Geocoding — loc2lonlat & lonlat2loc" begin

    cities = usplace()
    counties = uscounty()
    zips = uszcta5()

    # ── T1: Place lookup — known city ────────────────────────────────────
    @testset "T1: Place lookup — known city" begin
        r = loc2lonlat("Raleigh", state=:NC)
        @test r.GC_STATUS == "OK"
        @test r.GC_SOURCE == "PLACE"
        @test r.LON ≈ cities[findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities)), :LON]
        @test r.LAT ≈ cities[findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities)), :LAT]
        # Verify uncertainty
        idx = findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities))
        @test r.GC_UNCERT ≈ (2 / 3) * sqrt(cities[idx, :ALAND] / π)     # R2/S3: dgca's constant
    end

    # ── T2: Place lookup — case insensitive ──────────────────────────────
    @testset "T2: Case insensitive" begin
        r1 = loc2lonlat("Raleigh", state=:NC)
        r2 = loc2lonlat("raleigh", state=:NC)
        r3 = loc2lonlat("RALEIGH", state=:NC)
        @test r1.LON == r2.LON == r3.LON
        @test r1.LAT == r2.LAT == r3.LAT
    end

    # ── T3: Partial prefix match ─────────────────────────────────────────
    @testset "T3: Partial prefix" begin
        r = loc2lonlat("ral", state=:NC)
        @test r.GC_STATUS == "OK"
        @test r.GC_SOURCE == "PLACE"
        # Should resolve to Raleigh (unique prefix starting with "ral" in NC)
        r_full = loc2lonlat("Raleigh", state=:NC)
        @test r.LON == r_full.LON
    end

    # ── T4: Ambiguous partial match ──────────────────────────────────────
    @testset "T4: Ambiguous partial" begin
        # "spring" matches Springfield, Spring Hill, etc. across many states
        r = loc2lonlat("spring")
        @test r.GC_STATUS == "FAIL"
    end

    # ── T5: Suffix stripping (CDP) ───────────────────────────────────────
    @testset "T5: Suffix stripping" begin
        # Find a known CDP in the data
        cdp_idx = findfirst(row -> endswith(row.NAME, " CDP"), eachrow(cities))
        if !isnothing(cdp_idx)
            cdp_name = cities[cdp_idx, :NAME]
            cdp_st = cities[cdp_idx, :ST]
            base_name = replace(cdp_name, " CDP" => "")
            r = loc2lonlat(base_name, state=cdp_st)
            @test r.GC_STATUS == "OK"
            @test r.LON ≈ cities[cdp_idx, :LON]
        end
    end

    # ── T6: Postal code lookup ───────────────────────────────────────────
    @testset "T6: Postal code" begin
        r = loc2lonlat("27601")
        @test r.GC_STATUS == "OK"
        @test r.GC_SOURCE == "POSTALCODE"
        idx = findfirst(==(27601), zips.ZCTA5)
        if !isnothing(idx)
            @test r.LON ≈ zips[idx, :LON]
            @test r.LAT ≈ zips[idx, :LAT]
            @test r.GC_UNCERT ≈ (2 / 3) * sqrt(zips[idx, :ALAND] / π)       # R2/S3: dgca's constant
        end
    end

    # ── T7: County lookup via DataFrame ──────────────────────────────────
    @testset "T7: County lookup" begin
        df = DataFrame(COUNTY=["Wake"], STATE=[:NC])
        result = loc2lonlat(df; county=:COUNTY)
        @test result.GC_SOURCE[1] == "COUNTY"
        @test result.GC_STATUS[1] in ["OK", "PARTIAL"]
        idx = findfirst(row -> row.NAME == "Wake" && row.ST == :NC, eachrow(counties))
        if !isnothing(idx)
            @test result.LON[1] ≈ counties[idx, :LON]
        end
    end

    # ── T8: Vector input — common state ──────────────────────────────────
    @testset "T8: Vector input cities" begin
        result = loc2lonlat(["Raleigh", "Durham", "Chapel Hill"], state=:NC)
        @test result isa DataFrame
        @test nrow(result) == 3
        @test all(result.GC_SOURCE .== "PLACE")
        @test all(result.GC_STATUS .== "OK")
        @test all(.!ismissing.(result.LON))
    end

    # ── T9: Vector input — postal codes ──────────────────────────────────
    @testset "T9: Vector input postcodes" begin
        result = loc2lonlat(["27601", "27708"])
        @test result isa DataFrame
        @test nrow(result) == 2
        @test all(result.GC_SOURCE .== "POSTALCODE")
    end

    # ── T10: DataFrame input — city+state ────────────────────────────────
    @testset "T10: DataFrame city+state" begin
        df = DataFrame(CITY=["Raleigh", "Durham"], STATE=[:NC, :NC])
        result = loc2lonlat(df)
        @test hasproperty(result, :LON)
        @test hasproperty(result, :LAT)
        @test hasproperty(result, :GC_SOURCE)
        @test hasproperty(result, :GC_UNCERT)
        @test hasproperty(result, :GC_STATUS)
        @test nrow(result) == 2
        @test all(result.GC_STATUS .== "OK")
    end

    # ── T11: DataFrame input — custom column names ───────────────────────
    @testset "T11: Custom column names" begin
        df = DataFrame(town=["Raleigh"], st=[:NC])
        result = loc2lonlat(df; city=:town, state=:st)
        @test result.GC_SOURCE[1] == "PLACE"
        @test result.GC_STATUS[1] == "OK"
    end

    # ── T12: Invalid input ───────────────────────────────────────────────
    @testset "T12: Invalid input" begin
        # with no state nothing is found; with one the ladder ends at the state (GC), as "xyzzyplugh, NC" does
        r = loc2lonlat("xyzzyplugh")
        @test r.GC_STATUS == "FAIL"
        @test ismissing(r.LON)
        @test ismissing(r.LAT)
        r = loc2lonlat("xyzzyplugh", state=:NC)
        @test (r.GC_SOURCE, r.GC_STATUS) == ("STATE", "PARTIAL")
        @test r.LON == loc2lonlat("xyzzyplugh, NC").LON
    end

    # ── T13: Uncertainty formula ─────────────────────────────────────────
    @testset "T13: Uncertainty formula" begin
        # Place tier
        r = loc2lonlat("Raleigh", state=:NC)
        idx = findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities))
        @test r.GC_UNCERT ≈ (2 / 3) * sqrt(cities[idx, :ALAND] / π)     # R2/S3: dgca's constant

        # Postal code tier
        r = loc2lonlat("27601")
        idx = findfirst(==(27601), zips.ZCTA5)
        @test r.GC_UNCERT ≈ (2 / 3) * sqrt(zips[idx, :ALAND] / π)       # R2/S3: dgca's constant
    end

    # ── T14: Address preprocessing — unit stripping ──────────────────────
    @testset "T14: Unit stripping" begin
        parsed = Logjam._parse_address_string("123 Main St Apt 4B, Raleigh, NC 27601")
        @test parsed.street == "123 Main St"
        @test parsed.city == "Raleigh"
        @test parsed.state == "NC"
        @test parsed.postalcode == "27601"
        @test !parsed.is_pobox
    end

    # ── T15: Address preprocessing — P.O. Box ────────────────────────────
    @testset "T15: P.O. Box detection" begin
        parsed = Logjam._parse_address_string("PO Box 123, Raleigh, NC 27601")
        @test parsed.is_pobox
        @test isempty(parsed.street)
        @test parsed.city == "Raleigh"
        @test parsed.postalcode == "27601"
    end

    # ── T16: Address string parsing ──────────────────────────────────────
    @testset "T16: Address parsing" begin
        parsed = Logjam._parse_address_string("123 Main St, Raleigh, NC 27601")
        @test parsed.street == "123 Main St"
        @test parsed.city == "Raleigh"
        @test parsed.state == "NC"
        @test parsed.postalcode == "27601"
    end

    # ── T17: lonlat2loc — point inside city ──────────────────────────────
    @testset "T17: lonlat2loc — in city" begin
        # Use Raleigh's own coordinates — should be "in Raleigh"
        idx = findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities))
        xy = [cities[idx, :LON], cities[idx, :LAT]]
        r = lonlat2loc(xy, cities)
        @test occursin("in Raleigh", r.desc)
    end

    # ── T18: lonlat2loc — point outside city ─────────────────────────────
    @testset "T18: lonlat2loc — outside city" begin
        # Point far from any city center
        r = lonlat2loc([-79.5, 36.5], cities)
        @test occursin("mi", r.desc) || occursin("in", r.desc)
    end

    # ── T19: lonlat2loc — area-based radius ──────────────────────────────
    @testset "T19: Area-based in radius" begin
        # Verify that the threshold is area-based, not fixed
        idx_ral = findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities))
        r_ral = sqrt(cities[idx_ral, :ALAND] / π)
        # Find a small town
        small = findfirst(row -> row.ALAND < 1.0 && row.ALAND > 0.0, eachrow(cities))
        if !isnothing(small)
            r_small = sqrt(cities[small, :ALAND] / π)
            @test r_ral > r_small  # Larger city = larger radius
        end
    end

    # ── E1: Missing fields in DataFrame ──────────────────────────────────
    @testset "E1: Missing fields" begin
        df = DataFrame(
            CITY=[missing, "Raleigh", missing],
            STATE=[missing, :NC, :NC],
            POSTALCODE=["27601", missing, missing]
        )
        result = loc2lonlat(df)
        @test result.GC_STATUS[1] == "OK"       # postal code resolves
        @test result.GC_STATUS[2] == "OK"        # city+state resolves
        @test result.GC_STATUS[3] in ["PARTIAL", "FAIL"]  # state only or fail
    end

    # ── R2: Address without recognizable state (regression) ──────────────
    @testset "R2: Address with no state does not crash" begin
        # Regression: an address string with no recognizable state used to hit
        # String(::Nothing) inside _preprocess_address and throw a MethodError.
        # It must now return a NamedTuple with a status field.
        r = loc2lonlat("123 Main St, Raleigh")
        @test hasproperty(r, :GC_STATUS)
        @test r.GC_STATUS isa AbstractString
        @test r.GC_STATUS in ["OK", "PARTIAL", "FAIL"]

        # Direct check of the fixed helper: state === nothing behaves like missing.
        pp = Logjam._preprocess_address("123 Main St", "Raleigh", nothing, nothing)
        @test pp.state == ""
        @test pp.street == "123 Main St"
        @test pp.city == "Raleigh"
    end

    # ── E2: State as full name ───────────────────────────────────────────
    @testset "E2: State full name" begin
        r = loc2lonlat("Raleigh", state="North Carolina")
        @test r.GC_STATUS == "OK"
        @test r.GC_SOURCE == "PLACE"
        r2 = loc2lonlat("Raleigh", state=:NC)
        @test r.LON == r2.LON
    end

    # ── I4: geocode casing/type contract (v0.2.7 breaking) ───────────────
    @testset "I4: geocode casing + ST type" begin
        # loc2lonlat scalar: the same field names as the vector and DataFrame methods' columns (R7/S14)
        r = loc2lonlat("Raleigh", state=:NC)
        for f in (:LON, :LAT, :GC_SOURCE, :GC_UNCERT, :GC_STATUS)
            @test hasproperty(r, f)
        end
        @test keys(r) == (:LON, :LAT, :GC_SOURCE, :GC_UNCERT, :GC_STATUS)
        @test !hasproperty(r, :lon)
        @test !hasproperty(r, :lat)
        for f in (:source, :uncert, :status)         # v0.2.8's scalar names
            @test !hasproperty(r, f)
        end

        # lonlat2loc scalar: NAME, ST UPPERCASE; ST is a Symbol matching usplace().
        res = lonlat2loc([r.LON, r.LAT], cities)
        for f in (:NAME, :ST, :dist, :bearing, :dir, :desc)
            @test hasproperty(res, f)
        end
        @test !hasproperty(res, :name)
        @test !hasproperty(res, :st)
        @test res.NAME == "Raleigh"
        @test res.ST isa Symbol
        @test res.ST == :NC

        # Naive equality against the census DataFrame must now match.
        matched = filter(row -> row.ST == res.ST, usplace())
        @test nrow(matched) > 0
        @test all(matched.ST .== :NC)

        # matrix form: the Symbol rule holds in the returned columns.
        mat = lonlat2loc([r.LON r.LAT], cities)
        @test eltype(mat.ST) == Symbol
        @test mat.ST[1] == :NC

        # Coordinate values themselves are unchanged (only names/types changed).
        idx = findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities))
        @test r.LON ≈ cities[idx, :LON]
        @test r.LAT ≈ cities[idx, :LAT]
    end

    # ── N14: the cache file is written only where asked, only when an entry is added ──
    @testset "N14: geocode cache written only to a named file, only on a new entry" begin
        # A stand-in for the Nominatim extension, so the ADDRESS tier adds entries with no
        # network: each query returns a new longitude, so a re-query is visible.
        calls = Ref(0)
        failon = Ref("")
        function fake_geocode(street, city, state, pc; country = :US)
            street == failon[] && throw(Base.IOError("network unreachable (test)", 0))
            calls[] += 1
            return (lon = -78.0 - calls[] / 1000, lat = 35.5)
        end
        saved = (Logjam._nominatim_available[], Logjam._nominatim_geocode[])
        Logjam._nominatim_available[] = true
        Logjam._nominatim_geocode[] = fake_geocode
        nlines(path) = length(readlines(path))
        try
            mktempdir() do tmp
                # Default cache = nothing: an entry is added in memory, no file anywhere.
                work = mkdir(joinpath(tmp, "work"))
                cd(work) do
                    loc2lonlat("Raleigh", state=:NC)
                    r = loc2lonlat("10 Main St, Raleigh, NC")
                    @test r.GC_SOURCE == "ADDRESS"
                    loc2lonlat(["11 Main St, Raleigh, NC", "27601"])
                    loc2lonlat(DataFrame(STREET=["12 Main St"], CITY=["Raleigh"], STATE=[:NC]))
                end
                @test calls[] == 3
                @test isempty(readdir(work))

                # A named file that nothing is added to is never created (nor its folder).
                path = joinpath(tmp, "sub", "geocode_cache.csv")
                loc2lonlat("Raleigh", state=:NC; cache=path)
                loc2lonlat("27601"; cache=path)
                loc2lonlat(DataFrame(CITY=["Durham"], STATE=[:NC]); cache=path)
                @test !ispath(dirname(path))

                # First entry: folder and file created, header plus one row.
                r1 = loc2lonlat("20 Main St, Raleigh, NC"; cache=path)
                @test calls[] == 4
                @test isfile(path)
                @test nlines(path) == 2
                @test startswith(readline(path), "KEY,LON,LAT,SOURCE,UNCERT")

                # A cached address is read, not re-queried, and the file is untouched.
                before = read(path)
                r1b = loc2lonlat("20 Main St, Raleigh, NC"; cache=path)
                @test calls[] == 4
                @test (r1b.LON, r1b.LAT, r1b.GC_SOURCE) == (r1.LON, r1.LAT, "ADDRESS")
                @test read(path) == before

                # A new address is appended: earlier bytes kept, one header only.
                loc2lonlat("21 Main St, Raleigh, NC"; cache=path)
                @test read(path)[1:length(before)] == before
                @test nlines(path) == 3

                # Vector form: one load, new entries appended once; the cached one reused.
                v = loc2lonlat(["20 Main St, Raleigh, NC", "22 Main St, Raleigh, NC",
                                "23 Main St, Raleigh, NC"]; cache=path)
                @test calls[] == 7
                @test v.LON[1] == r1.LON
                @test nlines(path) == 5

                # DataFrame form appends the same way.
                loc2lonlat(DataFrame(STREET=["24 Main St"], CITY=["Raleigh"], STATE=[:NC]);
                           cache=path)
                @test nlines(path) == 6
                @test count(l -> startswith(l, "KEY,"), readlines(path)) == 1

                # force_download re-queries and appends; the later row wins on reading.
                rf = loc2lonlat("20 Main St, Raleigh, NC"; cache=path, force_download=true)
                @test calls[] == 9
                @test rf.LON != r1.LON
                @test nlines(path) == 7
                @test loc2lonlat("20 Main St, Raleigh, NC"; cache=path).LON == rf.LON

                # A header-only file (as v0.2.8 left behind) is appended to, no second header.
                path0 = joinpath(tmp, "old_cache.csv")
                write(path0, "KEY,LON,LAT,SOURCE,UNCERT\n")
                loc2lonlat("30 Main St, Raleigh, NC"; cache=path0)
                @test nlines(path0) == 2
                @test count(l -> startswith(l, "KEY,"), readlines(path0)) == 1

                # Entries resolved before an error are still written.
                path1 = joinpath(tmp, "err_cache.csv")
                failon[] = "41 Main St"
                @test_throws Base.IOError loc2lonlat(["40 Main St, Raleigh, NC",
                                                      "41 Main St, Raleigh, NC"]; cache=path1)
                failon[] = ""
                @test nlines(path1) == 2
                @test occursin("40 main st", read(path1, String))

                # `cache` names a file; a folder is refused, as is passing both keywords.
                @test_throws ArgumentError loc2lonlat("50 Main St, Raleigh, NC"; cache=tmp)
                @test_throws ArgumentError loc2lonlat("50 Main St, Raleigh, NC";
                                                      cache=path, cache_dir=tmp)

                # Deprecated cache_dir = dir means cache = joinpath(dir, "geocode_cache.csv").
                olddir = joinpath(tmp, "olddir")
                @test_deprecated loc2lonlat("60 Main St, Raleigh, NC"; cache_dir=olddir)
                @test isfile(joinpath(olddir, "geocode_cache.csv"))
                @test nlines(joinpath(olddir, "geocode_cache.csv")) == 2
            end
        finally
            Logjam._nominatim_available[], Logjam._nominatim_geocode[] = saved
        end
    end

end

# =============================================================================
# K2a: wrong-answer tests (test spec Sec. 2) and pin-today tests (Sec. 7). No network: the address
# tier is a stub where one is needed. Tagged [ID]; see tools/v0_3_0/run_against.jl.
# =============================================================================

# run `f` with the Nominatim hook set as given (nothing = extension absent) and log output discarded
function _with_nominatim(f, hook)
    saved = (Logjam._nominatim_available[], Logjam._nominatim_geocode[])
    try
        Logjam._nominatim_available[] = hook !== nothing
        hook === nothing || (Logjam._nominatim_geocode[] = hook)
        return Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())
    finally
        Logjam._nominatim_available[], Logjam._nominatim_geocode[] = saved
    end
end

# the bounding box of a state's county centroids, widened by half a degree
function _state_box(st::Symbol)
    c = uscounty()
    s = c[c.ST .== st, :]
    return (minimum(s.LON) - 0.5, maximum(s.LON) + 0.5, minimum(s.LAT) - 0.5, maximum(s.LAT) + 0.5)
end
# as `_with_nominatim`, but returns (logs, result) so a warning can be checked
function _nominatim_logs(f, hook)
    saved = (Logjam._nominatim_available[], Logjam._nominatim_geocode[])
    try
        Logjam._nominatim_available[] = hook !== nothing
        hook === nothing || (Logjam._nominatim_geocode[] = hook)
        return Test.collect_test_logs(f)
    finally
        Logjam._nominatim_available[], Logjam._nominatim_geocode[] = saved
    end
end
_inbox(r, box) =!ismissing(r.LON) && box[1] <= r.LON <= box[2] && box[3] <= r.LAT <= box[4]

@testset "[N1] the address parser: spelled-out states, an explicit state=, a five-digit street number" begin
    # the 16 spelled-out names that v0.2.8 misreads through their last two letters (recon N1)
    cases = [("Sacramento", "California", :CA), ("Atlanta", "Georgia", :GA),
             ("Pittsburgh", "Pennsylvania", :PA), ("Richmond", "Virginia", :VA),
             ("Charleston", "West Virginia", :WV), ("Houston", "Texas", :TX),
             ("Wichita", "Kansas", :KS), ("Little Rock", "Arkansas", :AR),
             ("Birmingham", "Alabama", :AL), ("Tulsa", "Oklahoma", :OK),
             ("Baltimore", "Maryland", :MD), ("Providence", "Rhode Island", :RI),
             ("Milwaukee", "Wisconsin", :WI), ("Albuquerque", "New Mexico", :NM),
             ("Columbia", "Missouri", :MO), ("Portland", "Maine", :ME)]
    right = Bool[]
    for (city, name, st) in cases
        r = _with_nominatim(() -> loc2lonlat("$city, $name"), nothing)
        push!(right, _inbox(r, _state_box(st)))
    end
    # N1: v0.2.8 puts all sixteen in another state (IA, AS, MA, ND, IN, CO, RI, NE)
    @test all(right)
    @test _inbox(_with_nominatim(() -> loc2lonlat("Atlanta, Georgia"), nothing), _state_box(:GA))
    @test _inbox(_with_nominatim(() -> loc2lonlat("Tulsa, Oklahoma"), nothing), _state_box(:OK))

    # an explicit state= is never overridden by what the parser reads out of the text
    r = _with_nominatim(() -> loc2lonlat("123 Main St, Richmond"; state = :VA), nothing)
    @test _inbox(r, _state_box(:VA))

    # a five-digit street number is not a ZIP: city and state survive
    r = _with_nominatim(() -> loc2lonlat("10420 Falls of Neuse Rd, Raleigh, NC 27614"), nothing)
    @test _inbox(r, _state_box(:NC))
    # control: the plain street address keeps its city and state
    r = _with_nominatim(() -> loc2lonlat("123 Main St, Raleigh, NC"), nothing)
    @test _inbox(r, _state_box(:NC))
    @test abs(r.LON - (-78.64)) < 0.3 && abs(r.LAT - 35.78) < 0.3
end

@testset "N1: the address grammar (street, city, state, ZIP read from the end, whole tokens)" begin
    P(s) = (p = Logjam._parse_address_string(s); (p.street, p.city, p.state, p.postalcode))
    # the course's addresses parse as they did (their cache keys depend on it)
    @test P("1 E Edenton St, Raleigh, NC 27601") == ("1 E Edenton St", "Raleigh", "NC", "27601")
    @test P("2 Broughton Dr, Raleigh, NC 27695") == ("2 Broughton Dr", "Raleigh", "NC", "27695")
    @test P("915 Partners Way, Raleigh, NC 27606") == ("915 Partners Way", "Raleigh", "NC", "27606")
    @test P("Raleigh, NC") == ("", "Raleigh", "NC", "")
    @test P("Raliegh, NC") == ("", "Raliegh", "NC", "")
    @test P("Roanoke Rapids, NC") == ("", "Roanoke Rapids", "NC", "")
    # a five-digit street number is not the ZIP; the ZIP is the last token
    @test P("10420 Falls of Neuse Rd, Raleigh, NC 27614") == ("10420 Falls of Neuse Rd", "Raleigh", "NC", "27614")
    @test P("12345 Main St, Raleigh, NC") == ("12345 Main St", "Raleigh", "NC", "")
    @test P("10420 Falls of Neuse Rd, Raleigh, NC 27614-1234") == ("10420 Falls of Neuse Rd", "Raleigh", "NC", "27614")
    # every spelled-out state name, none through its last two letters; the longest name wins
    for (name, sym) in Logjam._state_names
        @test P("Springfield, $name") == ("", "Springfield", String(sym), "")
        @test P("1 Main St, Springfield, $(uppercase(name)) 12345") == ("1 Main St", "Springfield", String(sym), "12345")
    end
    @test P("Charleston, West Virginia") == ("", "Charleston", "WV", "")
    @test P("Richmond, Virginia") == ("", "Richmond", "VA", "")
    @test P("New York, New York") == ("", "New York", "NY", "")
    @test P("Washington, District of Columbia") == ("", "Washington", "DC", "")
    # a code is a whole word: the last two letters of a city or a spelled-out name are not a state
    @test P("Raleigh, Miami") == ("Raleigh", "Miami", "", "")
    @test P("Houston, Texas") == ("", "Houston", "TX", "")
    @test P("Kansas City, MO") == ("", "Kansas City", "MO", "")
    @test P("Atlanta, GA") == ("", "Atlanta", "GA", "")
    # a code after a space: capitalized as a code, or followed by a ZIP; a street suffix is not a state
    @test P("Raleigh NC 27601") == ("", "Raleigh", "NC", "27601")
    @test P("raleigh nc 27601") == ("", "raleigh", "NC", "27601")
    @test P("Raleigh NC") == ("", "Raleigh", "NC", "")
    @test P("123 Oak Ct") == ("123 Oak Ct", "", "", "")
    @test P("Raleigh, nc") == ("", "Raleigh", "NC", "")
    # no state, no ZIP
    @test P("123 Main St, Raleigh") == ("123 Main St", "Raleigh", "", "")
    @test P("123 Main St") == ("123 Main St", "", "", "")
    @test P("Raleigh") == ("", "Raleigh", "", "")
    @test P("") == ("", "", "", "")
    # P.O. box and secondary units still come out of the street
    @test Logjam._parse_address_string("PO Box 5, Raleigh, NC 27601").is_pobox
    @test P("123 Main St Apt 4B, Raleigh, NC 27601") == ("123 Main St", "Raleigh", "NC", "27601")
end

@testset "N1: an explicit state= is never overridden by the text" begin
    # the text names Virginia, the caller says North Carolina: the caller wins, with a warning
    logs, r = _nominatim_logs(() -> loc2lonlat("Raleigh, VA"; state = :NC), nothing)
    @test _inbox(r, _state_box(:NC))
    @test any(l -> l.level >= Base.CoreLogging.Warn && occursin("VA", string(l.message)) &&
                   occursin("NC", string(l.message)), logs)
    # the same state twice is no disagreement: no warning
    logs, r = _nominatim_logs(() -> loc2lonlat("Raleigh, NC"; state = "North Carolina"), nothing)
    @test _inbox(r, _state_box(:NC))
    @test !any(l -> l.level >= Base.CoreLogging.Warn, logs)
    # no state in the text: the keyword supplies it (for a place, an address and a batch)
    @test _inbox(_with_nominatim(() -> loc2lonlat("Richmond"; state = :VA), nothing), _state_box(:VA))
    @test _inbox(_with_nominatim(() -> loc2lonlat("123 Main St, Richmond"; state = :VA), nothing), _state_box(:VA))
    df = _with_nominatim(() -> loc2lonlat(["Richmond", "123 Main St, Richmond"]; state = :VA), nothing)
    @test all(i -> _inbox((LON = df.LON[i], LAT = df.LAT[i]), _state_box(:VA)), 1:2)
    # the state in the text is used when no keyword is given
    @test _inbox(_with_nominatim(() -> loc2lonlat("Richmond, VA"), nothing), _state_box(:VA))
end

@testset "N7, N8: ZIPs are zero-padded strings inside the geocoder; numeric ZIP columns are accepted" begin
    z5 = uszcta5()
    row(z) = z5[findfirst(==(z), z5.ZCTA5), :]
    # N7: a leading zero geocodes, on the plain-string path, in a batch, and as the ZIP tier of an address
    r = _with_nominatim(() -> loc2lonlat("02139"), nothing)
    @test r.GC_STATUS == "OK" && r.GC_SOURCE == "POSTALCODE"
    @test (r.LON, r.LAT) == (row(2139).LON, row(2139).LAT)
    v = _with_nominatim(() -> loc2lonlat(["02139", "27601", "01001"]), nothing)
    @test v.GC_STATUS == ["OK", "OK", "OK"]
    @test v.LON == [row(2139).LON, row(27601).LON, row(1001).LON]
    a = _with_nominatim(() -> loc2lonlat("1 Main St, Zzyzx, MA 02139"), nothing)
    @test a.GC_SOURCE == "POSTALCODE" && a.LON == row(2139).LON
    # every ZCTA below 10000 (7.6% of the population, 2,485 codes at the pinned tables) geocodes to its own row
    low = sort(z5.ZCTA5[z5.ZCTA5 .< 10000])
    @test length(low) > 2000
    all_low = _with_nominatim(() -> loc2lonlat(lpad.(string.(low), 5, '0')), nothing)
    @test all(==("OK"), all_low.GC_STATUS)
    @test all_low.LON == [row(z).LON for z in low] && all_low.LAT == [row(z).LAT for z in low]
    # N8: a numeric ZIP column (CSV.jl reads one as Int64) is accepted, with and without a missing
    d_int = _with_nominatim(() -> loc2lonlat(DataFrame(POSTALCODE = [2139, 27601])), nothing)
    @test d_int.GC_SOURCE == ["POSTALCODE", "POSTALCODE"] && d_int.LON == [row(2139).LON, row(27601).LON]
    d_miss = _with_nominatim(() -> loc2lonlat(DataFrame(POSTALCODE = [2139, missing])), nothing)
    @test d_miss.GC_STATUS == ["OK", "FAIL"]
    d_flt = _with_nominatim(() -> loc2lonlat(DataFrame(POSTALCODE = [27601.0, 2139.0])), nothing)
    @test d_flt.LON == [row(27601).LON, row(2139).LON]
    d_str = _with_nominatim(() -> loc2lonlat(DataFrame(POSTALCODE = ["2139", "27601-1234"])), nothing)
    @test d_str.LON == [row(2139).LON, row(27601).LON]            # a text column that lost its zero; a ZIP+4
    # the column is read, not rewritten: the caller's table is unchanged
    df0 = DataFrame(POSTALCODE = [2139, 27601])
    _with_nominatim(() -> loc2lonlat(df0), nothing)
    @test df0.POSTALCODE == [2139, 27601] && eltype(df0.POSTALCODE) == Int
    # the helper
    nz = Logjam._normalize_zip
    @test nz(2139) == "02139" && nz(27601) == "27601" && nz(501) == "00501" && nz(0) == "00000"
    @test nz(2139.0) == "02139" && nz(missing) == "" && nz(nothing) == "" && nz(NaN) == ""
    @test nz("2139") == "02139" && nz(" 27601 ") == "27601" && nz("27601-1234") == "27601" && nz("K1A 0B1") == "K1A 0B1"
    # S36: the census tables keep integer ZIP codes after all that, and their values
    @test eltype(uszcta5().ZCTA5) <: Integer && eltype(uszcta3().ZCTA3) <: Integer
    @test 2139 in uszcta5().ZCTA5 && !any(x -> x isa AbstractString, uszcta5().ZCTA5)
end

@testset "[CR 26] address-tier fallback is reported, a failed lookup is cached, no house number is invented" begin
    # (a) a landmark Nominatim cannot find falls back to the city: the fallback is reported by a warning
    # that names the input and the tier used
    hook_none = (args...; kwargs...) -> missing
    logs, r = Test.collect_test_logs() do
        saved = (Logjam._nominatim_available[], Logjam._nominatim_geocode[])
        try
            Logjam._nominatim_available[] = true
            Logjam._nominatim_geocode[] = hook_none
            loc2lonlat("NC State Bell Tower, Raleigh, NC")
        finally
            Logjam._nominatim_available[], Logjam._nominatim_geocode[] = saved
        end
    end
    named = any(l -> l.level >= Base.CoreLogging.Warn &&
                     occursin("Bell Tower", string(l.message)) &&
                     (occursin("PLACE", string(l.message)) || occursin("city", lowercase(string(l.message)))), logs)
    # CR 26: v0.2.8 falls through silently (source = "PLACE", status = "PARTIAL" is all that says so)
    @test named

    # (b) a failed lookup is cached, so the same bad query is not sent twice (Nominatim policy)
    calls = Ref(0)
    hook_count = (args...; kwargs...) -> (calls[] += 1; missing)
    q = "NC State Bell Tower, Raleigh, NC"
    _with_nominatim(() -> loc2lonlat([q, q]), hook_count)
    @test calls[] == 1

    # (c) a match that has no house number is not reported as an exact ADDRESS/OK
    hook_road = (args...; kwargs...) -> (lon = -78.6997617, lat = 35.7957255,
                                         display_name = "Hillsborough Street, Raleigh, Wake County, North Carolina, 27607",
                                         importance = 0.4)
    r = _with_nominatim(() -> loc2lonlat("9999 Hillsborough St, Raleigh, NC 27607"), hook_road)
    # (read by either field spelling, so on v0.2.8 this is a wrong value, not a missing field: rule 2)
    src, st = hasproperty(r, :GC_SOURCE) ? (r.GC_SOURCE, r.GC_STATUS) : (r.source, r.status)
    @test !(src == "ADDRESS" && st == "OK")
    # control: the stub reaches the address tier at all
    @test st != "FAIL" && !ismissing(r.LON)
end

@testset "CR 26: the fallback warning, the negative cache, STREET matches, a bad state in a batch" begin
    warns(logs) = [string(l.message) for l in logs if l.level >= Base.CoreLogging.Warn]
    none = (args...; kwargs...) -> missing
    q = "NC State Bell Tower, Raleigh, NC"

    # (a) the warning names the input, why, and the tier; the answer is the city, as before
    logs, r = _nominatim_logs(() -> loc2lonlat(q), none)
    w = warns(logs)
    @test length(w) == 1 && occursin("Bell Tower", w[1]) && occursin("no match", w[1]) &&
          occursin("PLACE", w[1]) && occursin("city", w[1])
    @test (r.GC_SOURCE, r.GC_STATUS) == ("PLACE", "PARTIAL")
    @test r.LON == loc2lonlat("Raleigh", state = :NC).LON       # the same coordinates v0.2.8 returned
    # a lower tier other than the city is named too: a ZIP
    logs, r = _nominatim_logs(() -> loc2lonlat("1 Nowhere Rd, Zzyzx, NC 27601"), none)
    @test r.GC_SOURCE == "POSTALCODE" && any(x -> occursin("ZIP code", x) && occursin("Nowhere Rd", x), warns(logs))
    # extension absent: the warning says so, and names the input and the tier
    logs, r = _nominatim_logs(() -> loc2lonlat("1 E Edenton St, Raleigh, NC 27601"), nothing)
    w = warns(logs)
    @test length(w) == 1 && occursin("not loaded", w[1]) && occursin("Edenton", w[1]) && occursin("PLACE", w[1])
    # nothing found at any tier: FAIL, and the warning says so
    logs, r = _nominatim_logs(() -> loc2lonlat("1 Nowhere Rd"), none)
    @test r.GC_STATUS == "FAIL" && any(x -> occursin("FAIL", x) && occursin("Nowhere Rd", x), warns(logs))
    # no street, no address tier, no warning; an exact address, no warning
    logs, r = _nominatim_logs(() -> loc2lonlat("Raleigh, NC"), none)
    @test isempty(warns(logs))
    exact = (args...; kwargs...) -> (lon = -78.6, lat = 35.8, display_name = "915, Partners Way, Raleigh", importance = 0.4)
    logs, r = _nominatim_logs(() -> loc2lonlat("915 Partners Way, Raleigh, NC 27606"), exact)
    @test isempty(warns(logs)) && (r.GC_SOURCE, r.GC_STATUS) == ("ADDRESS", "OK")
    # a failed query that is not a definite "no match" is warned, not cached
    boom = (args...; kwargs...) -> error("bad response")
    logs, r = _nominatim_logs(() -> loc2lonlat(q), boom)
    @test (r.GC_SOURCE, r.GC_STATUS) == ("PLACE", "PARTIAL") && any(x -> occursin("failed", x), warns(logs))

    # (b) a failure is remembered: in one call, across calls through a cache file, and not by a network error
    calls = Ref(0)
    count_none = (args...; kwargs...) -> (calls[] += 1; missing)
    mktempdir() do tmp
        path = joinpath(tmp, "geocode_cache.csv")
        _with_nominatim(() -> loc2lonlat(q; cache = path), count_none)
        @test calls[] == 1
        @test occursin("NOTFOUND", read(path, String)) && occursin("nc state bell tower", lowercase(read(path, String)))
        r = _with_nominatim(() -> loc2lonlat(q; cache = path), count_none)      # a new call: read from the file
        @test calls[] == 1 && (r.GC_SOURCE, r.GC_STATUS) == ("PLACE", "PARTIAL")
        logs, _ = _nominatim_logs(() -> loc2lonlat(q; cache = path), count_none)  # a remembered failure is still a reported fallback
        @test any(x -> occursin("remembered", x) && occursin("Bell Tower", x), warns(logs)) && calls[] == 1
        _with_nominatim(() -> loc2lonlat([q, q, q]; cache = path), count_none)
        _with_nominatim(() -> loc2lonlat(DataFrame(STREET = ["NC State Bell Tower"], CITY = ["Raleigh"], STATE = ["NC"]); cache = path), count_none)
        @test calls[] == 1
        @test length(readlines(path)) == 2                                      # one header, one entry
        _with_nominatim(() -> loc2lonlat(q; cache = path, force_download = true), count_none)
        @test calls[] == 2                                                      # force_download asks again
        # a later success for the same key supersedes the remembered failure
        found = (args...; kwargs...) -> (lon = -78.67, lat = 35.77, display_name = "Bell Tower, 1, Hillsborough, Raleigh", importance = 0.4)
        r = _with_nominatim(() -> loc2lonlat(q; cache = path, force_download = true), found)
        @test (r.GC_SOURCE, r.GC_STATUS) == ("ADDRESS", "OK")
        @test _with_nominatim(() -> loc2lonlat(q; cache = path), count_none).LON == -78.67 && calls[] == 2
    end
    calls[] = 0
    netdown = (args...; kwargs...) -> (calls[] += 1; throw(Base.IOError("network unreachable (test)", 0)))
    @test_throws Base.IOError _with_nominatim(() -> loc2lonlat([q, q]), netdown)
    @test calls[] == 1                                                          # the error stops the call, caches nothing
    _with_nominatim(() -> loc2lonlat(q), count_none)
    @test calls[] == 2                                                          # and the next call asks again

    # (c) STREET: the street was found, the house number was not
    road = (args...; kwargs...) -> (lon = -78.6997617, lat = 35.7957255, display_name = "Hillsborough Street, Raleigh, Wake County", importance = 0.4)
    r = _with_nominatim(() -> loc2lonlat("9999 Hillsborough St, Raleigh, NC 27607"), road)
    @test (r.GC_SOURCE, r.GC_STATUS) == ("STREET", "PARTIAL") && ismissing(r.GC_UNCERT)
    @test (r.LON, r.LAT) == (-78.6997617, 35.7957255)                           # the street's coordinates, kept
    # the extension's own field decides when it is there
    with_hn(hn) = (args...; kwargs...) -> (lon = -78.6, lat = 35.8, display_name = "x", importance = 0.4, house_number = hn)
    @test _with_nominatim(() -> loc2lonlat("9999 Hillsborough St, Raleigh, NC"), with_hn("9999")).GC_SOURCE == "ADDRESS"
    @test _with_nominatim(() -> loc2lonlat("9999 Hillsborough St, Raleigh, NC"), with_hn("")).GC_SOURCE == "STREET"
    # a landmark or a street typed without a number claims none: exact, as before
    @test _with_nominatim(() -> loc2lonlat("Fitts-Woolard Hall, Raleigh, NC"), road).GC_SOURCE == "ADDRESS"
    @test _with_nominatim(() -> loc2lonlat("Hillsborough St, Raleigh, NC"), road).GC_STATUS == "OK"
    # a stand-in with neither house_number nor display_name has nothing to check against: exact
    bare = (args...; kwargs...) -> (lon = -78.6, lat = 35.8)
    @test _with_nominatim(() -> loc2lonlat("12 Main St, Raleigh, NC"), bare).GC_SOURCE == "ADDRESS"
    # the typed number is found as a whole part of the display name
    @test _with_nominatim(() -> loc2lonlat("1 E Edenton St, Raleigh, NC"),
        (args...; kwargs...) -> (lon = -78.6, lat = 35.8, display_name = "State Capitol, 1, East Edenton Street, Raleigh", importance = 0.1)).GC_SOURCE == "ADDRESS"
    @test _with_nominatim(() -> loc2lonlat("1 E Edenton St, Raleigh, NC"),
        (args...; kwargs...) -> (lon = -78.6, lat = 35.8, display_name = "East Edenton Street, 100, Raleigh", importance = 0.1)).GC_SOURCE == "STREET"
    # a STREET entry is cached and read back as STREET/PARTIAL, never promoted to an exact address
    mktempdir() do tmp
        path = joinpath(tmp, "geocode_cache.csv")
        _with_nominatim(() -> loc2lonlat("9999 Hillsborough St, Raleigh, NC 27607"; cache = path), road)
        @test occursin("STREET", read(path, String))
        r2 = _with_nominatim(() -> loc2lonlat("9999 Hillsborough St, Raleigh, NC 27607"; cache = path), (args...; kwargs...) -> error("sent"))
        @test (r2.GC_SOURCE, r2.GC_STATUS) == ("STREET", "PARTIAL") && ismissing(r2.GC_UNCERT) && r2.LON == r.LON
        # and in the vector form the table's uncertainty column holds missing for it
        v = _with_nominatim(() -> loc2lonlat(["9999 Hillsborough St, Raleigh, NC 27607", "Raleigh, NC"]; cache = path), (args...; kwargs...) -> error("sent"))
        @test v.GC_SOURCE == ["STREET", "PLACE"] && ismissing(v.GC_UNCERT[1]) && !ismissing(v.GC_UNCERT[2])
    end
    # the committed 4.2 cache (three exact addresses, no failure row) is read as before
    r3 = _with_nominatim(() -> loc2lonlat("1 E Edenton St, Raleigh, NC 27601"; cache = joinpath(@__DIR__, "fixtures", "geocode_cache_4net2.csv")),
                         (args...; kwargs...) -> error("sent"))
    @test (r3.GC_SOURCE, r3.GC_STATUS, r3.GC_UNCERT) == ("ADDRESS", "OK", 0.0) && r3.LON == -78.6390995

    # (d) one bad state no longer aborts a batch
    logs, df = _nominatim_logs(() -> loc2lonlat(DataFrame(CITY = ["Raleigh", "Durham", "Cary"], STATE = ["NC", "XX", "NC"])), nothing)
    @test df.GC_STATUS == ["OK", "FAIL", "OK"] && ismissing(df.LON[2]) && !ismissing(df.LON[3])
    @test any(x -> occursin("row 2", x) && occursin("XX", x), warns(logs))
    logs, df = _nominatim_logs(() -> loc2lonlat(["Raleigh, NC", "Durham, XX", "Cary, NC"]), nothing)
    @test df.GC_STATUS[1] == "OK" && df.GC_STATUS[3] == "OK"                    # "XX" is no state: the text is read without one
    logs, df = _nominatim_logs(() -> loc2lonlat(["Raleigh", "Durham"]; state = "XX"), nothing)
    @test df.GC_STATUS == ["FAIL", "FAIL"] && length(warns(logs)) == 2
    logs, df = _nominatim_logs(() -> loc2lonlat(DataFrame(STREET = ["1 Main St", "2 Main St"], CITY = ["Raleigh", "Raleigh"], STATE = ["ZZ", "NC"])), none)
    @test df.GC_STATUS[1] == "FAIL" && df.GC_STATUS[2] == "PARTIAL"
    # the scalar call is unchanged: a state that is not a state is an error the caller sees
    @test_throws ArgumentError _with_nominatim(() -> loc2lonlat("Raleigh"; state = "XX"), nothing)
end

@testset "[S3] GC_UNCERT equals (2/3) sqrt(a/pi) for a known area (R2; the dgca constant)" begin
    zips = uszcta5()
    row = zips[findfirst(==(27601), zips.ZCTA5), :]
    df = _with_nominatim(() -> loc2lonlat(["27601"]), nothing)
    expected = (2 / 3) * sqrt(row.ALAND / π)
    # S3: v0.2.8 returns 0.45 sqrt(a)
    @test df.GC_UNCERT[1] ≈ expected rtol = 1e-9
    @test df.GC_SOURCE[1] == "POSTALCODE"                    # control: the ZIP tier answered
end

@testset "S3: every area tier's uncertainty is the mean centroid distance of its area, dgca's constant" begin
    mean_dist(a) = (2 / 3) * sqrt(a / π)
    cities, counties, zips = usplace(), uscounty(), uszcta5()
    ral = cities[findfirst(r -> r.NAME == "Raleigh" && r.ST == :NC, eachrow(cities)), :]
    wake = counties[findfirst(r -> r.NAME == "Wake" && r.ST == :NC, eachrow(counties)), :]
    nc = counties[counties.ST .== :NC, :]
    z = zips[findfirst(==(27695), zips.ZCTA5), :]
    # place, ZIP: scalar, vector and DataFrame methods all give it
    @test _with_nominatim(() -> loc2lonlat("Raleigh"; state = :NC), nothing).GC_UNCERT ≈ mean_dist(ral.ALAND) rtol = 1e-12
    @test _with_nominatim(() -> loc2lonlat("27695"), nothing).GC_UNCERT ≈ mean_dist(z.ALAND) rtol = 1e-12
    v = _with_nominatim(() -> loc2lonlat(["Raleigh, NC", "27695"]), nothing)
    @test v.GC_UNCERT ≈ [mean_dist(ral.ALAND), mean_dist(z.ALAND)] rtol = 1e-12
    d = _with_nominatim(() -> loc2lonlat(DataFrame(CITY = ["Raleigh"], STATE = [:NC])), nothing)
    @test d.GC_UNCERT[1] ≈ mean_dist(ral.ALAND) rtol = 1e-12
    # county and state tiers
    c = _with_nominatim(() -> loc2lonlat(DataFrame(COUNTY = ["Wake"], STATE = [:NC])), nothing)
    @test c.GC_SOURCE == ["COUNTY"]
    @test c.GC_UNCERT[1] ≈ mean_dist(wake.ALAND) rtol = 1e-12
    s = _with_nominatim(() -> loc2lonlat(DataFrame(STATE = [:NC])), nothing)
    @test s.GC_SOURCE == ["STATE"]
    @test s.GC_UNCERT[1] ≈ mean_dist(sum(nc.ALAND)) rtol = 1e-12
    # the address tier's fallback carries the same uncertainty, and an exact address has none
    f = _with_nominatim(() -> loc2lonlat("1 E Edenton St, Raleigh, NC 27601"), nothing)
    @test f.GC_SOURCE == "PLACE"
    @test f.GC_UNCERT ≈ mean_dist(ral.ALAND) rtol = 1e-12
    @test _with_nominatim(() -> loc2lonlat("1 E Edenton St, Raleigh, NC 27601";
                           cache = joinpath(@__DIR__, "fixtures", "geocode_cache_4net2.csv")),
                          (args...; kwargs...) -> error("sent")).GC_UNCERT == 0.0
    # one constant: dgca floors a point against itself at the same value
    X = [ral.LON ral.LAT]
    @test dgca(X, X, [ral.ALAND])[1] ≈ _with_nominatim(() -> loc2lonlat("Raleigh"; state = :NC), nothing).GC_UNCERT rtol = 1e-12
    # 0.376 sqrt(a), not v0.2.8's 0.45 sqrt(a)
    @test _with_nominatim(() -> loc2lonlat("Raleigh"; state = :NC), nothing).GC_UNCERT / sqrt(ral.ALAND) ≈ 0.37613 atol = 1e-4
end

@testset "R7/S14: one set of GC_ field names on every method; state may be a vector" begin
    gcnames = (:GC_SOURCE, :GC_UNCERT, :GC_STATUS)
    # every method returns the GC_ names; the scalar method as a named tuple, the others as columns
    scalars = [_with_nominatim(() -> loc2lonlat("Raleigh"; state = :NC), nothing),     # PLACE
               _with_nominatim(() -> loc2lonlat("27601"), nothing),                    # POSTALCODE
               _with_nominatim(() -> loc2lonlat("Raleigh, NC"), nothing),
               _with_nominatim(() -> loc2lonlat("1 Main St, Raleigh, NC"), nothing),   # a fallback row
               _with_nominatim(() -> loc2lonlat("Zzyzx"; state = :NC), nothing),       # the state tier (GC)
               _with_nominatim(() -> loc2lonlat(""), nothing),
               _with_nominatim(() -> loc2lonlat("00000"), nothing)]
    for r in scalars
        @test keys(r) == (:LON, :LAT, :GC_SOURCE, :GC_UNCERT, :GC_STATUS)
    end
    v = _with_nominatim(() -> loc2lonlat(["Raleigh, NC"]), nothing)
    d = _with_nominatim(() -> loc2lonlat(DataFrame(CITY = ["Raleigh"], STATE = [:NC])), nothing)
    for t in (v, d), f in gcnames
        @test hasproperty(t, f)
    end
    # the scalar and the table agree field for field, so one unpacking serves both
    s = scalars[3]
    @test (s.LON, s.LAT, s.GC_SOURCE, s.GC_UNCERT, s.GC_STATUS) ==
          (v.LON[1], v.LAT[1], v.GC_SOURCE[1], v.GC_UNCERT[1], v.GC_STATUS[1])
    # the course's unpacking of a loop of scalars still reads LON and LAT by those names
    S = [_with_nominatim(() -> loc2lonlat(c; state = st), nothing) for (c, st) in zip(["Raleigh", "Athens"], [:NC, :GA])]
    @test [r.LON for r in S] == getindex.(S, :LON)
    @test getindex.(S, :GC_STATUS) == ["OK", "OK"]

    # state as a vector: one state per location, the same answers as one call each (5.2's call)
    City = ["Raleigh", "Athens", "Asheville", "Jacksonville", "Savannah", "Gainesville"]
    St = [:NC, :GA, :NC, :FL, :GA, :FL]
    each = [_with_nominatim(() -> loc2lonlat(c; state = s), nothing) for (c, s) in zip(City, St)]
    vec_ = _with_nominatim(() -> loc2lonlat(City; state = St), nothing)
    @test vec_.LON == [r.LON for r in each] && vec_.LAT == [r.LAT for r in each]
    @test vec_.GC_SOURCE == [r.GC_SOURCE for r in each] && vec_.GC_UNCERT == [r.GC_UNCERT for r in each]
    @test vec_.GC_STATUS == fill("OK", 6)
    @test vec_.INPUT == City
    # the states of Athens and Gainesville differ from their namesakes elsewhere: the vector matters
    @test _inbox((LON = vec_.LON[2], LAT = vec_.LAT[2]), _state_box(:GA))
    @test _inbox((LON = vec_.LON[6], LAT = vec_.LAT[6]), _state_box(:FL))
    # text states, strings, a missing entry (no state), and one state for all
    @test _with_nominatim(() -> loc2lonlat(["Raleigh", "Athens"]; state = ["NC", "GA"]), nothing).LON ==
          _with_nominatim(() -> loc2lonlat(["Raleigh", "Athens"]; state = [:NC, :GA]), nothing).LON
    mixed = _with_nominatim(() -> loc2lonlat(["Raleigh, NC", "Raleigh", "Raleigh"]; state = [missing, :NC, nothing]), nothing)
    @test mixed.GC_STATUS == ["OK", "OK", "FAIL"]       # no state for the last: "Raleigh" alone is ambiguous
    @test mixed.LON[1] == mixed.LON[2]
    @test _with_nominatim(() -> loc2lonlat(["Raleigh", "Durham"]; state = :NC), nothing).GC_STATUS == ["OK", "OK"]
    # a state in the text and a state vector: the vector's entry wins, as the keyword does (N1)
    w = _with_nominatim(() -> loc2lonlat(["Richmond, NC", "Richmond"]; state = [:VA, :VA]), nothing)
    @test all(i -> _inbox((LON = w.LON[i], LAT = w.LAT[i]), _state_box(:VA)), 1:2)
    # a vector of the wrong length is refused, and so is a vector for one location
    @test_throws ArgumentError loc2lonlat(["Raleigh", "Durham"]; state = [:NC])
    @test_throws ArgumentError loc2lonlat("Raleigh"; state = [:NC])
    # a bad state in the vector fails its row, not the call (CR 26)
    b = _with_nominatim(() -> loc2lonlat(["Raleigh", "Durham"]; state = [:NC, "XX"]), nothing)
    @test b.GC_STATUS == ["OK", "FAIL"]
end

@testset "GC: a plain string enters the same tier ladder as an address string" begin
    nom(f) = _with_nominatim(f, nothing)
    # the ruling's example: a misspelled plain name falls back to its state, as the comma form does
    # (Lecture 4.2's Code block 1 geocodes "Raliegh, NC")
    p = nom(() -> loc2lonlat("Raliegh"; state = :NC))
    c = nom(() -> loc2lonlat("Raliegh, NC"))
    @test (p.GC_SOURCE, p.GC_STATUS) == ("STATE", "PARTIAL")
    @test p == c
    @test !ismissing(p.LON) && !ismissing(p.GC_UNCERT)
    # the state may be a string, and a vector and a DataFrame agree with the scalar
    @test nom(() -> loc2lonlat("Raliegh"; state = "NC")) == p
    v = nom(() -> loc2lonlat(["Raliegh", "Raleigh"]; state = :NC))
    @test v.GC_SOURCE == ["STATE", "PLACE"] && v.GC_STATUS == ["PARTIAL", "OK"]
    @test v.LON[1] == p.LON && v.LAT[1] == p.LAT
    d = nom(() -> loc2lonlat(DataFrame(CITY = ["Raliegh", "Raleigh"], STATE = [:NC, :NC])))
    @test d.GC_SOURCE == v.GC_SOURCE && d.GC_STATUS == v.GC_STATUS
    # a name with no state and no match stays FAIL, and so does an empty string
    @test nom(() -> loc2lonlat("Raliegh")).GC_STATUS == "FAIL"
    @test nom(() -> loc2lonlat("Zzyzx")).GC_STATUS == "FAIL"
    @test nom(() -> loc2lonlat("")).GC_STATUS == "FAIL"
    # a name that matches several places is FAIL without a state; with one it falls back to the state,
    # as "spring, NC" does
    @test nom(() -> loc2lonlat("spring")).GC_STATUS == "FAIL"
    @test nom(() -> loc2lonlat("spring"; state = :NC)) == nom(() -> loc2lonlat("spring, NC"))
    @test nom(() -> loc2lonlat("spring"; state = :NC)).GC_SOURCE == "STATE"
    # a five-digit string is a postal code: found as before; one that is no ZIP falls back to the state keyword
    @test nom(() -> loc2lonlat("27601")).GC_SOURCE == "POSTALCODE"
    @test nom(() -> loc2lonlat("00000")).GC_STATUS == "FAIL"
    z = nom(() -> loc2lonlat("00000"; state = :NC))
    @test (z.GC_SOURCE, z.GC_STATUS) == ("STATE", "PARTIAL") && z.LON == p.LON
    # a found place is answered at its own tier, as at v0.2.8, with or without the state keyword
    @test nom(() -> loc2lonlat("Raleigh"; state = :NC)).GC_SOURCE == "PLACE"
    @test nom(() -> loc2lonlat("Raleigh"; state = :NC)).GC_STATUS == "OK"
    # the state is still checked: a scalar call with a state that is not a state throws
    @test_throws ArgumentError nom(() -> loc2lonlat("Raleigh"; state = "XX"))
    # the address tier is not reached for a plain string
    reached = Ref(false)
    spy = (args...; kwargs...) -> (reached[] = true; missing)
    _with_nominatim(() -> loc2lonlat("Raliegh"; state = :NC), spy)
    @test !reached[]
end

@testset "[S36] pin: the census tables keep integer ZCTA5 and ZCTA3 codes" begin
    @test eltype(uszcta5().ZCTA5) <: Integer
    @test eltype(uszcta3().ZCTA3) <: Integer
end

@testset "P8: lonlat2loc's alternate methods and loc2lonlat's country keyword are removed" begin
    cities = usplace()
    lon, lat = -78.6382, 35.7796
    # the pair, the two vectors and the table of coordinates are gone
    @test_throws MethodError lonlat2loc(lon, lat, cities)
    @test_throws MethodError lonlat2loc([lon, -80.8431], [lat, 35.2271], cities)
    @test_throws MethodError lonlat2loc(DataFrame(LON = [lon], LAT = [lat]), cities)
    # what replaces them is the (xy, df) form the course calls, which says the same
    r = lonlat2loc([lon, lat], cities)
    @test r.NAME == "Raleigh" && occursin("in Raleigh", r.desc)
    t = lonlat2loc([lon -80.8431; lat 35.2271]', cities)
    @test t.NAME == ["Raleigh", "Charlotte"] && t.NAME[1] == r.NAME && t.dist[1] == r.dist
    df_in = DataFrame(LON = [lon, -80.8431], LAT = [lat, 35.2271])
    @test lonlat2loc([df_in.LON df_in.LAT], cities).NAME == t.NAME
    # every method of loc2lonlat has lost `country`; the tiers are all U.S.
    @test_throws MethodError loc2lonlat("Raleigh"; state = :NC, country = :US)
    @test_throws MethodError loc2lonlat(["Raleigh"]; state = :NC, country = :US)
    @test_throws MethodError loc2lonlat(DataFrame(CITY = ["Raleigh"], STATE = [:NC]); country = :US)
    @test !isdefined(Logjam, :_state_abbrev_set)
end

# ==== moved from test/test_location_v031.jl, its lines 1-28, 464-493 ====
# test_location_v031.jl -- added by PCV WP3 of Logjam v0.3.1 (DK: review A's A5, A7 and A8): the metric kernel
# shared by dists, ala's locate step and dgca; ala's call forms; and the point-set and table alignments of
# wcentroid, uflxchg, lonlat2loc, loc2lonlat and dgca. Test spec Sec. 4. Equality is `==` on every element, or
# `===` where marked bit-identical; no tolerance is used anywhere in this file. The evidence:
#   1. the kernel (A5): v0.3.0's distance bodies, copied below as text, against the current functions bit for bit
#      (`===`) on every metric and on seeded sets of 1 to 20 dimensions; ala's locate step against v0.3.0's with
#      `_aladist` (also for the real 1.0 and 2.0, which locate by d1 and d2). The full record, 333 cases and
#      40,784,366 elements up to 3000 points saved before the kernel was wired in, is
#      tools/v0_3_1/kernel_identity.jl's; this file keeps a fast part of it in the suite;
#   2. ala's metric (A5): `dist = 3` and `1.5` now locate (they were an error), and `unit` is `dist`'s synonym;
#   3. ala's call forms (A7), each `==` to the call the course writes today, on the course's inputs:
#      `ala(X0, alloc, P)` on Lecture 2.3's contract (Code block 16), 3.4's Lowe's network (Code block 30) and
#      2.4's centroids (Code block 21); `ala(n, w, P)` on 2.3's Code block 14, 2.4's Code block 24 and the HW 1
#      key's Q6(b); `ala(x, w, P)` on 2.2's Examples 3 and 4 (Code blocks 25 and 32) and the HW 1 key's Q6(a);
#      no ambiguity, and every existing call keeps its method;
#   4. the alignments (A8): wcentroid(P, w) on 2.2's and 2.5's points; uflxchg on a range and on Int32 indices on
#      2.4's corridor and EMCA and 2.6's Kudde; lonlat2loc(xy) on 3.4's points; a view of a table where a
#      DataFrame was required;
#   5. dgca(x, Xa, a) against the matrix method's row, on 2.5's North Carolina ZIP codes and EMCA's.
# A lecture's definition is copied here as text, with its .qmd file and line; no companion script is run.

using Test
using Logjam
using DataFrames
using SparseArrays
using Random
import Optim
using Optim: optimize

@testset "WP3 (A8): lonlat2loc defaults to usplace(), and a view of a table is a table" begin
    # Lecture 3.4, Code block 18 (3-tran-4.qmd:1257-1271, 1282): its suppliers, DC and customers, and Code block 26's
    # places over 50,000 (1555)
    Scity, Sst = ["Rochester", "Orlando", "San Antonio"], [:NY, :FL, :TX]
    S = [loc2lonlat(c; state = st) for (c, st) in zip(Scity, Sst)]
    SXY = [getindex.(S, :LON) getindex.(S, :LAT)]
    Ccity, Cst = ["Portland", "Tucson", "Denver", "Milwaukee"], [:OR, :AZ, :CO, :WI]
    C = [loc2lonlat(c; state = st) for (c, st) in zip(Ccity, Cst)]
    CXY = [getindex.(C, :LON) getindex.(C, :LAT)]
    DC = loc2lonlat("Memphis"; state = :TN)
    DCXY = [DC.LON DC.LAT]
    XY = vcat(SXY, DCXY, CXY)
    up = usplace()
    @test lonlat2loc(XY) == lonlat2loc(XY, up)
    @test all(lonlat2loc(XY[i, :]) == lonlat2loc(XY[i, :], up) for i in axes(XY, 1))
    big = filter(r -> r.POP > 50_000, usplace())
    @test lonlat2loc(XY[4, :]; threshold = 1.0) == lonlat2loc(XY[4, :], up; threshold = 1.0)
    # the table is positional, as 3.4 passes `big`; there is no `df` keyword (ruling WP3-3)
    @test_throws MethodError lonlat2loc(XY; df = big)
    @test length(methods(lonlat2loc)) == 4
    # a view where a DataFrame was required: the same answer as the DataFrame it shows
    mask = up.POP .> 50_000
    @test lonlat2loc(XY, view(up, mask, :)) == lonlat2loc(XY, up[mask, :])
    @test lonlat2loc(XY[1, :], view(up, mask, :)) == lonlat2loc(XY[1, :], up[mask, :])
    t = DataFrame(CITY = ["Raleigh", "Durham", "Chapel Hill", "Cary"], STATE = [:NC, :NC, :NC, :NC])
    @test loc2lonlat(view(t, 2:3, :)) == loc2lonlat(t[2:3, :])
    @test loc2lonlat(view(t, :, :)) == loc2lonlat(t)
    @test prt(view(t, 2:3, :); str = true) == prt(t[2:3, :]; str = true)
end

# ==== moved from test/test_geodata_v031.jl, its lines 1-618, 640-710 ====
# test_geodata_v031.jl -- added by PCV WP5 of Logjam v0.3.1 (GC rest: review A's A4, A6 and A10; ZCTA: D4; X6). Test spec Sec. 5.
# Equality is `==` (or `isequal`, where a column may hold `missing`) on every element, with the element types compared
# as well; no tolerance is used anywhere in this file. The evidence:
#   1. the batch driver (A4): v0.3.0's geocoder, its vector and DataFrame methods and the row resolver they call,
#      copied below as text, against the current methods on the same inputs, column for column, with the log records
#      (the progress line, the warnings) compared too; `_FAIL` and `_row` against the hand-written rows they replace;
#      the vector method on any vector of strings;
#   2. the column keywords (A6): each `*_col` gives what its old name gives; each old name is deprecated
#      (`@test_deprecated`) and, in a fresh process run with --depwarn=no, prints nothing; a state column that is
#      named and is not in the table is an `ArgumentError`, where v0.3.0 returned FAIL for every row; the literal
#      `state = ...` calls of src/geocode.jl's docstrings give v0.3.0's values;
#   3. the loader and the name index (A10): every census loader returns a copy that can be changed without reaching
#      the next call; the index finds the row (or raises the error) v0.3.0's scan of the whole table finds, for every
#      name of `usplace()` and `uscounty()`, with its state and with none, and for 200 variants of them, the scan
#      itself checked against v0.3.0's text on a sample; the Puerto Rico rows the ZIP docstrings now name (X6);
#   4. STFIP on the ZIP tables (MakePlan D4): the last column, an Int64, never missing; the columns before it v0.3.0's,
#      by type and by the SHA-256 of v0.3.0's CSV files; the CSV files the script's output byte for byte and the .jls
#      that CSV read back; Puerto Rico's 72; every cross-state ZCTA5 and every three-digit ZCTA recomputed by the rule
#      from the committed extract of the Census relationship file (test/data/zcta_state_parts.csv).

using Test
using Logjam
using DataFrames
using CSV
using Base.CoreLogging: with_logger, NullLogger    # Logging is not in the test environment (Pkg.test has no @stdlib)

# ---- v0.3.0's geocoder, verbatim (the v0.3.0 tag fd0f1f3, src/geocode.jl: _batch_row :478-486, _resolve_row
# :501-589, _loc2lonlat_one :741-759, the vector method :786-829, the DataFrame method :859-912, whose `df::DataFrame`
# A8 widened to `AbstractDataFrame` at 1d6657e; and the resolvers it calls, _match_name :87-128, _resolve_place
# :327-337, _resolve_postalcode :342-353, _resolve_county :358-368, _resolve_state :373-390). The reference for
# "the result tables equal": each is run beside the current method. The helpers WP5 does not change (address
# parsing, the cache, the fallback warning) are Logjam's own. ----
module GcV030
using DataFrames
using Logjam: usplace, uscounty, uszcta5, _normalize_name, _normalize_state, _throw_ambiguous, _uncertainty,
              _preprocess_address, _cache_key, _NOTFOUND, _row_from_entry, _nominatim_available,
              _nominatim_geocode, _entry_from_result, _store!, _notfound_entry, _fallback, _GeocodeCache,
              _load_cache, _cache_file, _flush!, _tighten, _is_postalcode, _parse_address_string, _reconcile_state

function _match_name(query::AbstractString, df::DataFrame, name_col::Symbol;
                     st=nothing, st_col::Symbol=:ST)
    q = _normalize_name(query)
    isempty(q) && throw(ArgumentError("Empty query string"))

    st_sym = _normalize_state(st)

    # Build candidate pool (filtered by state if provided)
    if !isnothing(st_sym) && hasproperty(df, st_col)
        mask = [r[st_col] == st_sym for r in eachrow(df)]
    else
        mask = trues(nrow(df))
    end

    # Normalize all reference names
    ref_names = [_normalize_name(String(df[i, name_col])) for i in 1:nrow(df)]

    # Phase 1: Exact match
    exact = [i for i in 1:nrow(df) if mask[i] && ref_names[i] == q]
    length(exact) == 1 && return exact[1]
    if length(exact) > 1
        _throw_ambiguous(q, exact, df, name_col, st_col)
    end

    # Phase 2: Prefix match
    prefix = [i for i in 1:nrow(df) if mask[i] && startswith(ref_names[i], q)]
    length(prefix) == 1 && return prefix[1]
    if length(prefix) > 1
        _throw_ambiguous(q, prefix, df, name_col, st_col)
    end

    # Phase 3: Substring match
    sub = [i for i in 1:nrow(df) if mask[i] && occursin(q, ref_names[i])]
    length(sub) == 1 && return sub[1]
    if length(sub) > 1
        _throw_ambiguous(q, sub, df, name_col, st_col)
    end

    # No match
    state_msg = isnothing(st_sym) ? "" : " in state $st_sym"
    throw(ArgumentError("No match for '$query'$state_msg"))
end

function _resolve_place(name::AbstractString, state)
    isempty(strip(name)) && return missing
    df = usplace()
    try
        idx = _match_name(name, df, :NAME; st=state, st_col=:ST)
        return (lon=df[idx, :LON], lat=df[idx, :LAT],
                aland=df[idx, :ALAND], source="PLACE")
    catch
        return missing
    end
end

function _resolve_postalcode(code::AbstractString)
    pc = strip(code)
    # Must be 5-digit numeric
    occursin(r"^\d{5}$", pc) || return missing
    df = uszcta5()
    # the table's ZCTA5 is an integer (S36), so "02139" is 2139 (N7)
    idx = eltype(df.ZCTA5) <: Integer ? findfirst(==(parse(Int, pc)), df.ZCTA5) :
                                         findfirst(==(pc), string.(df.ZCTA5))
    isnothing(idx) && return missing
    return (lon=df[idx, :LON], lat=df[idx, :LAT],
            aland=df[idx, :ALAND], source="POSTALCODE")
end

function _resolve_county(name::AbstractString, state)
    isempty(strip(name)) && return missing
    df = uscounty()
    try
        idx = _match_name(name, df, :NAME; st=state, st_col=:ST)
        return (lon=df[idx, :LON], lat=df[idx, :LAT],
                aland=df[idx, :ALAND], source="COUNTY")
    catch
        return missing
    end
end

function _resolve_state(name)
    isnothing(name) && return missing
    st_sym = try
        _normalize_state(name)
    catch
        return missing
    end
    df = uscounty()
    mask = df.ST .== st_sym
    !any(mask) && return missing
    sub = df[mask, :]
    total_pop = sum(sub.POP)
    total_pop == 0 && return missing
    wlon = sum(sub.LON .* sub.POP) / total_pop
    wlat = sum(sub.LAT .* sub.POP) / total_pop
    total_aland = sum(sub.ALAND)
    return (lon=wlon, lat=wlat, aland=total_aland, source="STATE")
end

function _batch_row(f, i::Integer, what)
    try
        return f()
    catch e
        e isa ArgumentError && startswith(e.msg, "Unknown state") || rethrow()
        @warn "loc2lonlat: row $i (\"$what\"): $(e.msg); no location returned (status FAIL)."
        return (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL")
    end
end

function _resolve_row(street, city, state, postalcode, county,
                      gc::_GeocodeCache, force_download)
    addr = _preprocess_address(street, city, state, postalcode)
    st_sym = isempty(addr.state) ? nothing : _normalize_state(addr.state)

    # Tier 1: Full address via Nominatim (if street present and not P.O. Box). `note` says why
    # the address tier did not answer, so that a lower tier's answer is reported as a fallback
    # naming the input and the tier (CR 26), never returned silently.
    note = nothing
    if !isempty(addr.street) && !addr.is_pobox
        key = _cache_key(addr.street, addr.city, addr.state, addr.postalcode)
        cached = !force_download && haskey(gc.entries, key) ? gc.entries[key] : nothing
        if cached !== nothing && cached.source != _NOTFOUND
            return _row_from_entry(cached)
        elseif cached !== nothing                    # a failed lookup, remembered
            note = "an earlier query found no match for it (remembered in the cache)"
        elseif _nominatim_available[]
            try
                result = _nominatim_geocode[](addr.street, addr.city, addr.state,
                                               addr.postalcode; country=:US)
                if !ismissing(result)
                    entry = _entry_from_result(result, addr.street)
                    _store!(gc, key, entry)
                    return _row_from_entry(entry)
                end
                _store!(gc, key, _notfound_entry)    # not found: never sent twice (Nominatim policy)
                note = "Nominatim found no match for it"
            catch e
                if e isa Base.IOError || (hasproperty(e, :msg) && occursin("network", lowercase(string(e))))
                    rethrow(e)
                end
                note = "the Nominatim query failed ($(nameof(typeof(e))))"   # not a definite "no match": not cached
            end
        else
            note = "the Nominatim extension is not loaded (install HTTP and JSON3 for address geocoding)"
        end
    end

    # Tier 2: City/place + state
    if !isempty(addr.city) && !isnothing(st_sym)
        result = _resolve_place(addr.city, st_sym)
        if !ismissing(result)
            status = isempty(addr.street) || addr.is_pobox ? "OK" : "PARTIAL"
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS=status))
        end
    end

    # Tier 3: Postal code
    pc = addr.postalcode
    if !isempty(pc)
        result = _resolve_postalcode(pc)
        if !ismissing(result)
            status = isempty(addr.street) ? "OK" : "PARTIAL"
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS=status))
        end
    end

    # Tier 4: County + state
    county_str = ismissing(county) ? "" : strip(String(county))
    if !isempty(county_str) && !isnothing(st_sym)
        result = _resolve_county(county_str, st_sym)
        if !ismissing(result)
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS="PARTIAL"))
        end
    end

    # Tier 5: State only
    if !isnothing(st_sym)
        result = _resolve_state(st_sym)
        if !ismissing(result)
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS="PARTIAL"))
        end
    end

    # Tier 2b: City without state (if not already tried)
    if !isempty(addr.city) && isnothing(st_sym)
        result = _resolve_place(addr.city, nothing)
        if !ismissing(result)
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS="OK"))
        end
    end

    return _fallback(note, addr, (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL"))
end

function _loc2lonlat_one(s::AbstractString, state, gc::_GeocodeCache,
                         force_download::Bool)
    s = strip(s)
    isempty(s) && return (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL")

    # Detect if it looks like an address (has commas or numbers)
    if !_is_postalcode(s) && occursin(r"[,\d]", s)
        parsed = _parse_address_string(s)
        st = _reconcile_state(parsed.state, state, s)
        return _resolve_row(parsed.street, parsed.city, st,
                            parsed.postalcode, missing, gc, force_download)
    end

    # A plain string enters the same ladder as an address (GC): a five-digit string as a postal code,
    # any other as a city, so a name that is not found falls back to its state, as the comma form does
    return _is_postalcode(s) ?
        _resolve_row("", "", state, s, missing, gc, force_download) :
        _resolve_row("", s, state, "", missing, gc, force_download)
end

function loc2lonlat(v::Vector{<:AbstractString}; state=nothing,
                    cache::Union{Nothing,AbstractString}=nothing,
                    cache_dir::Union{Nothing,AbstractString}=nothing,
                    force_download::Bool=false)
    n = length(v)
    if state isa AbstractVector && length(state) != n
        throw(ArgumentError("loc2lonlat: `state` has $(length(state)) entries for $n locations; " *
                            "pass one state or one per location."))
    end
    state_of(i) = state isa AbstractVector ? (ismissing(state[i]) ? nothing : state[i]) : state
    lons = Vector{Union{Float64,Missing}}(missing, n)
    lats = Vector{Union{Float64,Missing}}(missing, n)
    sources = Vector{String}(undef, n)
    uncerts = Vector{Union{Float64,Missing}}(missing, n)
    statuses = Vector{String}(undef, n)

    gc = _load_cache(_cache_file(cache, cache_dir))
    try
        for i in 1:n
            if i % 50 == 0
                @info "Geocoding progress: $i / $n"
            end
            r = _batch_row(i, v[i]) do
                _loc2lonlat_one(v[i], state_of(i), gc, force_download)
            end
            lons[i] = r.LON
            lats[i] = r.LAT
            sources[i] = r.GC_SOURCE
            uncerts[i] = r.GC_UNCERT
            statuses[i] = r.GC_STATUS
        end
    finally
        _flush!(gc)
    end

    return DataFrame(
        INPUT = v,
        LON = _tighten(lons),
        LAT = _tighten(lats),
        GC_SOURCE = sources,
        GC_UNCERT = _tighten(uncerts),
        GC_STATUS = statuses
    )
end

function loc2lonlat(df::AbstractDataFrame; street::Symbol=:STREET, city::Symbol=:CITY,
                    state::Symbol=:STATE, postalcode::Symbol=:POSTALCODE,
                    county::Symbol=:COUNTY,
                    cache::Union{Nothing,AbstractString}=nothing,
                    cache_dir::Union{Nothing,AbstractString}=nothing,
                    force_download::Bool=false)
    n = nrow(df)
    lons = Vector{Union{Float64,Missing}}(missing, n)
    lats = Vector{Union{Float64,Missing}}(missing, n)
    sources = fill("", n)
    uncerts = Vector{Union{Float64,Missing}}(missing, n)
    statuses = fill("", n)

    has_street = hasproperty(df, street)
    has_city = hasproperty(df, city)
    has_state = hasproperty(df, state)
    has_pc = hasproperty(df, postalcode)
    has_county = hasproperty(df, county)

    gc = _load_cache(_cache_file(cache, cache_dir))
    try
        for i in 1:n
            if i % 50 == 0
                @info "Geocoding progress: $i / $n"
            end

            s = has_street ? df[i, street] : missing
            c = has_city ? df[i, city] : missing
            st = has_state ? df[i, state] : missing
            pc = has_pc ? df[i, postalcode] : missing
            co = has_county ? df[i, county] : missing

            r = _batch_row(i, "$(s), $(c), $(st) $(pc)") do
                _resolve_row(s, c, st, pc, co, gc, force_download)
            end

            lons[i] = r.LON
            lats[i] = r.LAT
            sources[i] = r.GC_SOURCE
            uncerts[i] = r.GC_UNCERT
            statuses[i] = r.GC_STATUS
        end
    finally
        _flush!(gc)
    end

    result = copy(df)
    result.LON = _tighten(lons)
    result.LAT = _tighten(lats)
    result.GC_SOURCE = sources
    result.GC_UNCERT = _tighten(uncerts)
    result.GC_STATUS = statuses
    return result
end

# v0.3.0's scalar method, on the same row resolver (src/geocode.jl :726-738)
function loc2lonlat(s::AbstractString; state=nothing,
                    cache::Union{Nothing,AbstractString}=nothing,
                    cache_dir::Union{Nothing,AbstractString}=nothing,
                    force_download::Bool=false)
    state isa AbstractVector && throw(ArgumentError(
        "loc2lonlat: a single location takes one `state`; pass a vector of locations to give one state each."))
    gc = _load_cache(_cache_file(cache, cache_dir))
    try
        return _loc2lonlat_one(s, state, gc, force_download)
    finally
        _flush!(gc)
    end
end
end # module GcV030

# ---- helpers ----
# run `f` with the address tier absent (hook = nothing) or replaced by `hook`; returns its value and its log records
# at Info and above, as (level, message) pairs, the deprecations (group :depwarn) set apart
function _gd_run(f, hook = nothing)
    saved = (Logjam._nominatim_available[], Logjam._nominatim_geocode[])
    try
        Logjam._nominatim_available[] = hook !== nothing
        hook === nothing || (Logjam._nominatim_geocode[] = hook)
        logs, val = Test.collect_test_logs(f; min_level = Base.CoreLogging.Info)
        recs = [(l.level, l.message) for l in logs if l.group !== :depwarn]
        return val, recs
    finally
        Logjam._nominatim_available[], Logjam._nominatim_geocode[] = saved
    end
end

# run `f` with the address tier absent, so that no call can reach the network (the Nominatim extension is loaded by
# the time this file runs)
function _gd_offline(f)
    saved = Logjam._nominatim_available[]
    try
        Logjam._nominatim_available[] = false
        return f()
    finally
        Logjam._nominatim_available[] = saved
    end
end

# a stand-in for Nominatim: "Nowhere Rd" is not found (NOTFOUND), an "Elm St" is found without its house number
# (STREET), any other street with its number (ADDRESS); the position depends on the street, so two streets differ
function _gd_stub(street, city, state, postalcode; country = :US)
    occursin("Nowhere", street) && return missing
    h = sum(Int, codeunits(street)) % 97
    m = match(r"^\d+", street)
    return (lon = -78.6 - h / 1000, lat = 35.7 + h / 1000,
            house_number = occursin("Elm", street) || m === nothing ? "" : m.match)
end

# two results are the same table: the same names, element types and values, column for column
_gd_same(a::DataFrame, b::DataFrame) =
    names(a) == names(b) && eltype.(eachcol(a)) == eltype.(eachcol(b)) && all(isequal(a[!, n], b[!, n]) for n in names(a))
_gd_same(a::NamedTuple, b::NamedTuple) = keys(a) == keys(b) && typeof(a) == typeof(b) && isequal(a, b)

# old and new on one call: equal values and equal log records; for a call with a cache file, the two files' bytes too
function _gd_both(fold, fnew; hook = nothing, cached = false)
    if cached
        mktempdir() do d
            po, pn = joinpath(d, "old.csv"), joinpath(d, "new.csv")
            vo, lo = _gd_run(() -> fold(po), hook)
            vn, ln = _gd_run(() -> fnew(pn), hook)
            return _gd_same(vo, vn) && lo == ln && read(po) == read(pn) && isfile(pn)
        end
    else
        vo, lo = _gd_run(fold, hook)
        vn, ln = _gd_run(fnew, hook)
        return _gd_same(vo, vn) && lo == ln
    end
end

# ---- 1. the batch driver (A4) -----------------------------------------------------------------------------------------
@testset "[WP5 A4] _FAIL and _row are the rows they replace" begin
    @test Logjam._FAIL === (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL")
    for (f, args) in ((Logjam._resolve_place, ("Raleigh", :NC)), (Logjam._resolve_postalcode, ("27601",)),
                      (Logjam._resolve_county, ("Wake", :NC)), (Logjam._resolve_state, (:NC,)))
        result = f(args...)
        for status in ("OK", "PARTIAL")
            @test Logjam._row(result, status) === (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                                                    GC_UNCERT=Logjam._uncertainty(result.aland), GC_STATUS=status)
        end
    end
end

@testset "[WP5 A4] the vector method equals v0.3.0's, column for column, with its log records" begin
    for (v, kw) in (
            (["Raleigh", "Durham", "Chapel Hill"], (; state = :NC)),         # src/geocode.jl's example
            (["27601", "27708", "27514"], (;)),
            (["Raleigh, NC", "27695", "Zzyzx", ""], (;)),                       # one FAIL, one empty
            (["Raleigh", "Athens", "Asheville"], (; state = [:NC, :GA, :NC])),  # one state each
            (["Raleigh", "Durham", "Cary"], (; state = [:NC, "XX", missing])),  # a bad state: that row FAIL, warned
            (["Raliegh", "Raleigh"], (; state = :NC)),                           # the state tier (GC)
            (String[], (;)),                                                      # no rows
            (repeat(["27601", "Raleigh, NC", "Zzyzx"], 20), (;)))                 # 60 rows: the progress line at 50
        @test _gd_both(() -> GcV030.loc2lonlat(v; kw...), () -> loc2lonlat(v; kw...))
    end
    # addresses, with the address tier stood in for, and the cache file each writes
    v = ["10 Main St, Raleigh, NC 27601", "7 Elm St, Durham, NC", "5 Nowhere Rd, Cary, NC", "27695",
         "PO Box 5, Raleigh, NC 27601"]
    @test _gd_both(p -> GcV030.loc2lonlat(v; cache = p), p -> loc2lonlat(v; cache = p); hook = _gd_stub, cached = true)
    @test _gd_both(() -> GcV030.loc2lonlat(v), () -> loc2lonlat(v))           # the address tier absent: warned
    # the stub's ADDRESS, STREET and NOTFOUND are what this case is about
    r, _ = _gd_run(() -> loc2lonlat(v), _gd_stub)
    @test r.GC_SOURCE == ["ADDRESS", "STREET", "PLACE", "POSTALCODE", "PLACE"]
end

@testset "[WP5 A4] the vector method takes any vector of strings" begin
    v = ["Raleigh", "Durham", "Chapel Hill", "Cary"]
    r = loc2lonlat(v; state = :NC)
    @test _gd_same(loc2lonlat(view(v, 2:3); state = :NC), r[2:3, :])
    @test _gd_same(loc2lonlat(SubString.(v); state = :NC)[!, Not(:INPUT)], r[!, Not(:INPUT)])
    @test loc2lonlat(SubString.(v); state = :NC).INPUT == v
    @test loc2lonlat(view(v, 2:3); state = :NC).INPUT isa Vector{String}
    @test which(loc2lonlat, (Vector{String},)).sig == Tuple{typeof(loc2lonlat), AbstractVector{<:AbstractString}}
    @test which(loc2lonlat, (Vector{Int},)).sig == Tuple{typeof(loc2lonlat), AbstractVector{<:Integer}}
end

@testset "[WP5 A4] the DataFrame method equals v0.3.0's, column for column, with its log records" begin
    tables = [DataFrame(CITY = ["Raleigh", "Durham"], STATE = [:NC, :NC]),
              DataFrame(POSTALCODE = [27601, 2139, missing]),
              DataFrame(POSTALCODE = ["27601", "27695-1234", "2139"]),
              DataFrame(COUNTY = ["Wake", "Durham"], STATE = [:NC, :NC]),
              DataFrame(STATE = [:NC, :VA]),
              DataFrame(CITY = ["Raleigh", missing], STATE = [:NC, :NC], X = [7, 8]),
              DataFrame(CITY = ["Raleigh", "Durham", "Cary"], STATE = ["NC", "XX", "NC"]),
              DataFrame(CITY = ["Athens", "Portland", "Jacksonville"]),
              DataFrame(STREET = ["1 Main St", "2 Main St"], CITY = ["Raleigh", "Raleigh"], STATE = ["ZZ", "NC"]),
              DataFrame(CITY = repeat(["Raleigh", "Zzyzx"], 30), STATE = fill(:NC, 60)),
              DataFrame(LON = [1.0], CITY = ["Durham"], STATE = [:NC]),             # a LON column is replaced in place
              DataFrame(CITY = String[], STATE = Symbol[])]
    for t in tables
        @test _gd_both(() -> GcV030.loc2lonlat(t), () -> loc2lonlat(t))
    end
    big = DataFrame(CITY = ["Raleigh", "Durham", "Cary", "Apex"], STATE = fill(:NC, 4))
    @test _gd_both(() -> GcV030.loc2lonlat(view(big, 2:3, :)), () -> loc2lonlat(view(big, 2:3, :)))
    # other column names: v0.3.0's keywords against the `*_col` keywords
    t = DataFrame(addr = ["10 Main St", "7 Elm St", "5 Nowhere Rd", missing], town = ["Raleigh", "Durham", "Cary", "Apex"],
                  st = ["NC", "NC", "NC", "NC"], zip = [27601, missing, 27513, 27502], cty = ["Wake", "Durham", "Wake", "Wake"])
    @test _gd_both(p -> GcV030.loc2lonlat(t; street = :addr, city = :town, state = :st, postalcode = :zip,
                                          county = :cty, cache = p),
                   p -> loc2lonlat(t; street_col = :addr, city_col = :town, state_col = :st, postalcode_col = :zip,
                                   county_col = :cty, cache = p); hook = _gd_stub, cached = true)
    tc = DataFrame(cty = ["Wake", "Nowhere"], st = [:NC, :NC])
    @test _gd_both(() -> GcV030.loc2lonlat(tc; county = :cty, state = :st), () -> loc2lonlat(tc; county_col = :cty, state_col = :st))
end

# ---- 2. the column keywords (A6) --------------------------------------------------------------------------------------
@testset "[WP5 A6] each *_col keyword gives what its old name gives" begin
    t = DataFrame(addr = ["10 Main St", "7 Elm St"], town = ["Raleigh", "Durham"], st = ["NC", "NC"],
                  zip = [27601, 27701], cty = ["Wake", "Durham"])
    quiet(f) = with_logger(f, NullLogger())
    for (knew, kold, col) in ((:street_col, :street, :addr), (:city_col, :city, :town), (:state_col, :state, :st),
                              (:postalcode_col, :postalcode, :zip), (:county_col, :county, :cty))
        rnew, _ = _gd_run(() -> loc2lonlat(t; NamedTuple{(knew,)}((col,))...), _gd_stub)
        rold, _ = _gd_run(() -> quiet(() -> loc2lonlat(t; NamedTuple{(kold,)}((col,))...)), _gd_stub)
        @test _gd_same(rnew, rold)
    end
    # all five at once, old names, new names and the two mixed; a column named by a string
    all_new = (; street_col = :addr, city_col = :town, state_col = :st, postalcode_col = :zip, county_col = :cty)
    all_old = (; street = :addr, city = :town, state = :st, postalcode = :zip, county = :cty)
    rnew, _ = _gd_run(() -> loc2lonlat(t; all_new...), _gd_stub)
    @test _gd_same(rnew, first(_gd_run(() -> quiet(() -> loc2lonlat(t; all_old...)), _gd_stub)))
    @test _gd_same(rnew, first(_gd_run(() -> quiet(() -> loc2lonlat(t; street = :addr, city_col = :town, state = :st,
                                                                     postalcode_col = :zip, county = :cty)), _gd_stub)))
    @test _gd_same(rnew, first(_gd_run(() -> loc2lonlat(t; street_col = "addr", city_col = "town", state_col = "st",
                                                         postalcode_col = "zip", county_col = "cty"), _gd_stub)))
    # the stub found the first address, so the street column was read
    @test rnew.GC_SOURCE == ["ADDRESS", "STREET"]
    # the same keyword twice, by both names, is refused
    @test_throws ArgumentError loc2lonlat(t; city_col = :town, city = :town)
    @test_throws ArgumentError loc2lonlat(t; state_col = :st, state = :st)
end

@testset "[WP5 A6] each old name is deprecated, under Pkg.test's --depwarn=yes" begin
    t = DataFrame(addr = ["PO Box 5"], town = ["Raleigh"], st = [:NC], zip = [27601], cty = ["Wake"])   # no network
    _gd_offline() do
        # what each call gives with the new names
        rs = loc2lonlat(t; street_col = :addr, city_col = :town, state_col = :st)
        r = loc2lonlat(t; city_col = :town, state_col = :st)
        rz = loc2lonlat(t; city_col = :town, state_col = :st, postalcode_col = :zip)
        rc = loc2lonlat(t; city_col = :town, state_col = :st, county_col = :cty)
        if Base.JLOptions().depwarn == 1
            @test _gd_same(rs, @test_deprecated r"`street = :addr` is deprecated, use `street_col = :addr`" loc2lonlat(t; street = :addr, city_col = :town, state_col = :st))
            @test _gd_same(r, @test_deprecated r"`city = :town` is deprecated, use `city_col = :town`" loc2lonlat(t; city = :town, state_col = :st))
            @test _gd_same(r, @test_deprecated r"`state = :st` is deprecated, use `state_col = :st`" loc2lonlat(t; city_col = :town, state = :st))
            @test _gd_same(rz, @test_deprecated r"`postalcode = :zip` is deprecated, use `postalcode_col = :zip`" loc2lonlat(t; city_col = :town, state_col = :st, postalcode = :zip))
            @test _gd_same(rc, @test_deprecated r"`county = :cty` is deprecated, use `county_col = :cty`" loc2lonlat(t; city_col = :town, state_col = :st, county = :cty))
            # two old names in one call: one warning naming both
            @test_deprecated r"`city = :town`, `state = :st` are deprecated, use `city_col = :town`, `state_col = :st`" loc2lonlat(t; city = :town, state = :st)
        end
        # the new names, and no column keyword at all, warn of nothing
        @test_logs min_level = Base.CoreLogging.Warn loc2lonlat(t; city_col = :town, state_col = :st)
        @test_logs min_level = Base.CoreLogging.Warn loc2lonlat(DataFrame(CITY = ["Raleigh"], STATE = [:NC]))
    end
end

@testset "[WP5 A6] an old name prints nothing under --depwarn=no (a fresh process)" begin
    code = """
    using Logjam, DataFrames
    t = DataFrame(town = ["Raleigh"], st = [:NC], cty = ["Wake"])
    r = loc2lonlat(t; city = :town, state = :st, county = :cty)
    print("RESULT=", r.GC_SOURCE[1], ",", r.GC_STATUS[1])
    """
    child(flag) = (out = IOBuffer();
                   cmd = `$(Base.julia_cmd()) $flag --startup-file=no --project=$(Base.active_project()) -e $code`;
                   ok = success(pipeline(cmd; stdout = out, stderr = out)); (ok, String(take!(out))))
    ok, out = child("--depwarn=no")
    @test ok && out == "RESULT=PLACE,OK"
    # the check can fail: the same call under --depwarn=yes prints the deprecation
    ok, out = child("--depwarn=yes")
    @test ok && occursin("deprecated, use `city_col = :town`", out) && endswith(out, "RESULT=PLACE,OK")
end

@testset "[WP5 A6] a state column that is named and is not in the table is an ArgumentError" begin
    # review A's measurement: the vector method's `state` given to a table read `:GA` as a column, FAIL for every row
    t = DataFrame(CITY = ["Athens", "Portland", "Jacksonville"])
    old, _ = _gd_run(() -> GcV030.loc2lonlat(t; state = :GA))
    @test old.GC_STATUS == ["FAIL", "FAIL", "FAIL"]
    for kw in ((; state = :GA), (; state_col = :GA), (; state = "GA"), (; state_col = :ST), (; state_col = :STATE))
        e = try
            loc2lonlat(t; kw...)
            nothing
        catch err
            err
        end
        @test e isa ArgumentError
        @test occursin("names no column of the table (its columns are CITY)", e.msg) && occursin("`state_col`", e.msg)
    end
    e = try loc2lonlat(t; state = :GA); nothing catch err; err end
    @test occursin("To geocode every row in the state GA, add the column", e.msg)
    e = try loc2lonlat(t; state_col = :ST); nothing catch err; err end
    @test !occursin("To geocode every row", e.msg)                      # :ST is no state: no such hint
    # the state column given by default and absent is no error: the table has no state, as before
    z = DataFrame(POSTALCODE = [27601, 27695])
    @test _gd_both(() -> GcV030.loc2lonlat(z), () -> loc2lonlat(z))
    # a column keyword other than the state's that names no column is the part not given, as before
    @test _gd_both(() -> GcV030.loc2lonlat(z; city = :nope, street = :nope, county = :nope),
                   () -> loc2lonlat(z; city_col = :nope, street_col = :nope, county_col = :nope))
end

@testset "[WP5 A6] the literal `state = ...` calls of src/geocode.jl give v0.3.0's values" begin
    # every call in a docstring of src/geocode.jl that passes `state` (the string and vector methods, whose `state`
    # is a state and is unchanged); no DataFrame-method call in src/, the lectures or HW 1 to 5 passes `state`
    for (f, args, kw) in ((loc2lonlat, ("Raleigh",), (; state = :NC)), (loc2lonlat, ("Raliegh",), (; state = :NC)),
                          (loc2lonlat, ("Memphis",), (; state = :TN)), (loc2lonlat, ("27601",), (; state = :NC)))
        @test _gd_both(() -> GcV030.loc2lonlat(args...; kw...), () -> f(args...; kw...))
    end
    for (v, kw) in ((["Raleigh", "Durham", "Chapel Hill"], (; state = :NC)), (["Raleigh", "Durham"], (; state = :NC)),
                    (["Raleigh", "Athens", "Asheville"], (; state = [:NC, :GA, :NC])))
        @test _gd_both(() -> GcV030.loc2lonlat(v; kw...), () -> loc2lonlat(v; kw...))
    end
    @test _gd_both(() -> GcV030.loc2lonlat(DataFrame(addr = ["123 Main St"], town = ["Raleigh"], st = ["NC"]);
                                           street = :addr, city = :town, state = :st),
                   () -> loc2lonlat(DataFrame(addr = ["123 Main St"], town = ["Raleigh"], st = ["NC"]);
                                    street_col = :addr, city_col = :town, state_col = :st))
end

# v0.3.0's scan (GcV030._match_name) with its normalization of the table's names done once, outside the call: the
# same phases over the same rows in the same order, so the same row or the same error
function _gd_scan(query, df, ref_names, stv, st)
    q = Logjam._normalize_name(query)
    isempty(q) && throw(ArgumentError("Empty query string"))
    st_sym = Logjam._normalize_state(st)
    mask = isnothing(st_sym) ? trues(nrow(df)) : stv .== st_sym
    for keep in ((i -> ref_names[i] == q), (i -> startswith(ref_names[i], q)), (i -> occursin(q, ref_names[i])))
        hits = [i for i in 1:nrow(df) if mask[i] && keep(i)]
        length(hits) == 1 && return hits[1]
        length(hits) > 1 && Logjam._throw_ambiguous(q, hits, df, :NAME, :ST)
    end
    state_msg = isnothing(st_sym) ? "" : " in state $st_sym"
    throw(ArgumentError("No match for '$query'$state_msg"))
end

_gd_outcome(f) = try
    (:row, f())
catch e
    (:error, typeof(e), e isa ArgumentError ? e.msg : "")
end

# 200 variants of the names: case, accents, spacing, designators, prefixes and parts, states right and wrong
function _gd_variants(df)
    rng = Logjam.Xoshiro(20261126)
    accented = [i for i in 1:nrow(df) if any(c -> !isascii(c), df.NAME[i])]
    sts = [:NC, :CA, :TX, :NY, nothing]
    out = Tuple{String, Any}[]
    strip_accents(s) = Base.Unicode.normalize(s; stripmark = true)
    for k in 1:200
        i = k <= 20 && !isempty(accented) ? accented[mod1(k, length(accented))] : rand(rng, 1:nrow(df))
        n, st = df.NAME[i], df.ST[i]
        v = (uppercase(n), lowercase(n), titlecase(n), strip_accents(n), "  " * n * "  ", replace(n, " " => "  "),
             n * " city", n * " CDP", first(n, min(4, length(n))), n[nextind(n, 0, min(2, length(n))):end],
             replace(n, r"(?i) (city|town|village|cdp)$" => ""), n * "x")[mod1(k, 12)]
        push!(out, (v, k % 3 == 0 ? rand(rng, sts) : k % 3 == 1 ? st : nothing))
    end
    append!(out, [("", :NC), ("   ", nothing), ("Springfield", nothing), ("Springfield", :IL), ("Zzyzx", :CA),
                  ("ral", :NC), ("Raleigh", "XX"), ("Raleigh", "north carolina")])
    return out
end

@testset "[WP5 A10] the name index finds the rows v0.3.0's scan finds" begin
    for (name, df) in (("usplace", usplace()), ("uscounty", uscounty()))
        ix = Logjam._name_index(name)
        ref = [Logjam._normalize_name(String(x)) for x in df.NAME]
        @test ix.names == ref
        stv = df.ST
        same(q, st) = _gd_outcome(() -> Logjam._match_name(q, ix, df, :NAME; st = st, st_col = :ST)) ==
                      _gd_outcome(() -> _gd_scan(q, df, ref, stv, st))
        # every name of the table, with its state and with none
        @test all(same(df.NAME[i], df.ST[i]) for i in 1:nrow(df))
        @test all(same(df.NAME[i], nothing) for i in 1:nrow(df))
        # 200 variants
        vs = _gd_variants(df)
        @test length(vs) >= 200
        @test all(same(q, st) for (q, st) in vs)
        # and the scan above is v0.3.0's own on a sample (its normalization repeated in every call: about 25 ms)
        smp = vcat([(df.NAME[i], df.ST[i]) for i in 1:max(1, nrow(df) ÷ 100):nrow(df)], vs[1:40])
        @test all(_gd_outcome(() -> GcV030._match_name(q, df, :NAME; st = st, st_col = :ST)) ==
                  _gd_outcome(() -> _gd_scan(q, df, ref, stv, st)) for (q, st) in smp)
    end
    # the lookups the geocoder makes through the index give v0.3.0's answers
    for (q, st) in (("Raleigh", :NC), ("Springfield", nothing), ("Zzyzx", :CA), ("ral", :NC), ("Wake", :NC))
        @test isequal(Logjam._resolve_place(q, st), GcV030._resolve_place(q, st))
        @test isequal(Logjam._resolve_county(q, st), GcV030._resolve_county(q, st))
    end
    @test isequal(Logjam._resolve_postalcode("27601"), GcV030._resolve_postalcode("27601"))
    @test isequal(Logjam._resolve_state(:NC), GcV030._resolve_state(:NC))
end
