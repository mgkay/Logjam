# test_maptools.jl -- the tests of src/maptools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_maptools.jl, its lines 1-68 ====
using Test

# Test for WORLD_LIMITS, US_LIMITS, and CUS_LIMITS constants
@test WORLD_LIMITS == ((-180, 180), (-75, 75))
@test US_LIMITS == ((-180, -65), (15, 72))
@test CUS_LIMITS == ((-125, -65), (24, 50))

# Test for mapbbox function
@testset "mapbbox tests" begin
    x = [-80.0, -75.0, -78.0]
    y = [35.0, 40.0, 38.0]
    result = mapbbox(x, y, xexpand=0.1, yexpand=0.1)

    # M4.1: returns one nested box ((xmin,xmax),(ymin,ymax)), not a 2-tuple of boxes
    @test length(result) == 2
    @test result[1] isa Tuple
    @test result[1][1] isa Real
    @test result[2] isa Tuple
    @test result[2][1] isa Real
    # Expanded box differs from the raw extent
    @test result[1] != (-80.0, -75.0)  # x limits should be expanded
    @test result[2] != (35.0, 40.0)    # y limits should be expanded
end

@testset "mapbbox all-NaN input" begin
    x = [NaN, NaN]
    y = [NaN, NaN]
    @test_throws ArgumentError mapbbox(x, y)
end

# Test for aligntext function
@testset "aligntext tests" begin
    x = [1.0, 2.0]
    y = [3.0, 4.0]
    result = aligntext(x, y)

    align_result = first(result)   # This will give you the `:align` => alignout Pair
    offset_result = last(result)   # This will give you the `:offset` => offsetout Pair
    
    @test align_result.first == :align  # Ensure the first Pair is the :align one
    @test length(align_result.second) == 2  # Now, check the length of the align array
    
    @test offset_result.first == :offset  # Ensure the second Pair is the :offset one
    @test length(offset_result.second) == 2  # Now, check the length of the offset array

    # idx keyword: single index returns scalar align/offset
    r1 = aligntext(x, y; idx=1)
    a1, o1 = first(r1), last(r1)
    @test a1.first == :align
    @test a1.second isa Tuple{Symbol,Symbol}
    @test o1.second isa Tuple{Real,Real}
    # Should match the full result at index 1
    @test a1.second == align_result.second[1]
    @test o1.second == offset_result.second[1]

    # idx keyword: vector index returns vectors
    r12 = aligntext(x, y; idx=[1,2])
    a12 = first(r12)
    @test length(a12.second) == 2

    # idx with more points: alignment considers all points
    x3 = [0.0, 1.0, 0.5]
    y3 = [0.0, 0.0, 1.0]
    full = Dict(aligntext(x3, y3))
    sub = Dict(aligntext(x3, y3; idx=1))
    @test sub[:align] == full[:align][1]
    @test sub[:offset] == full[:offset][1]
end

# ==== moved from test/test_k12_pins.jl, its lines 1-24, 210-236 ====
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

# ---- Lecture 4.2's Code block 3: Wake County's box -----------------------------------------------------------------
@testset "[K12 pin] Lecture 4.2's Code block 3: Wake County's box from its block groups" begin
    @test !_k12pin_moved("wake_box")
    m = lecture42_module()
    @test nrow(getfield(m, :B)) == 597
    @test getfield(m, :mpd) == 69.09322176332552
    @test getfield(m, :bbW) == (-78.97544182356803, -78.27350863429567, 35.52318408209017, 36.080417439618664)
    @test getfield(m, :wide) == 39.334750975714485
    @test getfield(m, :high) == 38.50104794563882
    @test round.(getfield(m, :bbW), digits = 3) == (-78.975, -78.274, 35.523, 36.080)    # what the lecture prints
    @test (round(Int, getfield(m, :wide)), round(Int, getfield(m, :high))) == (39, 39)
end

# ---- usstates ---------------------------------------------------------------------------------------------------
@testset "[K12 pin] Logjam.usstates(), as Lecture 5.1 (5-rte-1.qmd:818) and the four Lecture 2.2 generators call it" begin
    @test !_k12pin_moved("usstates")
    x, y = Logjam.usstates()
    @test (typeof(x), typeof(y)) == (Vector{Float64}, Vector{Float64})
    @test (length(x), length(y)) == (3642, 3642)
    @test (count(isnan, x), count(isnan, y)) == (103, 103)
    @test (_k12_fnv(x), _k12_fnv(y)) == (0xbd5dfc034f397b93, 0x73b1dce3c71f5e75)
    @test extrema(filter(!isnan, x)) == (-188.9049072265625, -65.62680053710938)
    @test extrema(filter(!isnan, y)) == (17.929555892944336, 71.35163116455078)
    @test isequal(Logjam.usstates(), (x, y))                             # a later call returns what the first did
    @test findall(isnan, x) == findall(isnan, y)                         # the separators sit together
end

# ==== moved from test/test_k12_functions.jl, its lines 1-14, 215-265 ====
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

# ==== moved from test/test_aligntext_duplicates.jl, its lines 1-102 ====
# Test cases for aligntext duplicate point handling
#
# When multiple labels share the same coordinates, they should all receive
# different alignments to avoid overlapping each other.

using Test
using Logjam

@testset "aligntext duplicate point handling" begin

    # Test: Simple duplicate points - should distribute evenly
    @testset "two labels at same location get opposite alignments" begin
        x = [-83.37, -84.0, -83.37, -85.0]  # indices 1 and 3 are duplicates
        y = [42.493, 43.0, 42.493, 44.0]

        result = aligntext(x, y)
        aligns = result[1].second
        offsets = result[2].second

        @test length(aligns) == 4
        @test length(offsets) == 4

        # Indices 1 and 3 are at same location - should have different alignments
        @test aligns[1] != aligns[3]
    end

    # Test: Three labels at same location
    @testset "three labels at same location get distributed alignments" begin
        x = [-83.0, -83.0, -83.0, -85.0]  # indices 1,2,3 are duplicates
        y = [42.0, 42.0, 42.0, 44.0]

        result = aligntext(x, y)
        aligns = result[1].second

        @test length(aligns) == 4
        # All three at same location should have different alignments
        @test length(unique([aligns[1], aligns[2], aligns[3]])) >= 2
    end

    # Test: Larger dataset with duplicates at indices 11 and 47
    @testset "larger dataset with duplicates" begin
        x = collect(range(-85.0, -80.0, length=50))
        y = collect(range(40.0, 45.0, length=50))
        # Set indices 11 and 47 to identical coordinates
        x[11] = -83.37
        y[11] = 42.493
        x[47] = -83.37
        y[47] = 42.493

        result = aligntext(x, y)
        aligns = result[1].second
        offsets = result[2].second

        @test length(aligns) == 50
        @test length(offsets) == 50
        # Duplicates should have different alignments
        @test aligns[11] != aligns[47]
    end

    # Test: All points at same location
    @testset "all points at same location" begin
        x = [-83.0, -83.0, -83.0, -83.0]
        y = [42.0, 42.0, 42.0, 42.0]

        result = aligntext(x, y)
        aligns = result[1].second

        @test length(aligns) == 4
        # Should distribute around compass (90° apart for 4 points)
        @test length(unique(aligns)) >= 2  # At least some different alignments
    end

    # Test: Two points at same location (edge case)
    @testset "two duplicate points only" begin
        x = [-83.37, -83.37]
        y = [42.493, 42.493]

        result = aligntext(x, y)
        aligns = result[1].second

        @test length(aligns) == 2
        # Should be opposite alignments (180° apart)
        @test aligns[1] != aligns[2]
    end

    # Test: No duplicates should work normally
    @testset "no duplicates works normally" begin
        x = [-78.6382, -80.8431, -79.7919, -80.2442]
        y = [35.7796, 35.2271, 36.0726, 36.0999]

        result = aligntext(x, y)
        @test result[1].first == :align
        @test length(result[1].second) == 4
    end

    # Test: Single point
    @testset "single point" begin
        result = aligntext([-83.0], [42.0])
        @test result[1].second == (:left, :bottom)
    end

end

# ==== moved from test/test_boxes_v031.jl, its lines 1-265 ====
# test_boxes_v031.jl -- added by PCV WP10 of Logjam v0.3.1 (X7: a city's and a state's box, MakePlan D3; X8: the
# empirical aggregate distance, MakePlan D8). Test spec Sec. 6. Equality is `===` (bit for bit) where marked and `==`
# elsewhere; the tolerances are D3's, Raleigh's box within 0.05 degrees of Nominatim's on every side, and test spec
# Sec. 6's relative 1e-14 against MATLAB's dagg.m, also used for the two closed forms at the branch boundary (26r/23
# and 546r/480, the formula's value at a point, equal to rounding), and one unit in the last place between the
# empirical distance at d = 0, 2r/3 as 2.5's equation writes it, and the default's floor, (2/3)·r. The evidence:
#   1. the place boxes (data/usplacebox, made by tools/v0_3_1/make_placebox.jl from the Census TIGER/Line 2020 place
#      shapefiles): exactly `usplace()`'s keys, one row each, sorted; the CSV the script's output byte for byte (its
#      SHA-256, printed on two runs) and the .jls that CSV read back; every box contains its place's `usplace()`
#      point, all 31,617; Raleigh's box against the Nominatim box CR 28 recorded;
#   2. `mapbbox(name; state, place)`: every county of `uscounty()` gives, bit for bit, the box `mapbbox` gave it at
#      the branch's start, or throws the same error (test/data/county_boxes_f3f0c1b.csv, saved by
#      tools/v0_3_1/save_county_boxes.jl before WP10 changed `mapbbox`); "Durham" in North Carolina is the county,
#      and the city (PLFIP 19000) with `place = true`; a name no county has gives the place; the matching rules (case,
#      the designator, an exact name preferred); every name two places share in a state is an error naming them;
#      every place by its own name gives its own box; `xexpand` and `yexpand` act on a place's box as on a county's;
#   3. `mapbbox(state)`: for every state of `usstate()`, the extent of its counties' boxes, each Lecture 4.2's Code
#      block 3 run on the county's block groups (copied below as text), and so containing each of them;
#   4. `dgca(...; method = :empirical)`: `==` to 2.5's @eq-daemp copied as text on 2.5's Example 4 and 5 inputs, by
#      both of dgca's methods and in another unit; against MATLAB's ise754/dagg.m run on the same distances
#      (test/oracles/dagg_matlab.csv, tools/v0_3_1/make_oracles_v031.m), relative 1e-14 wherever dagg.m applies one
#      case, and where it applies both (d/r from 0.8378 to 1: its second statement tests the matrix its first has
#      changed) its value the second case applied to the first's, above 2.5's equation, which Logjam follows; the
#      branch boundary as dagg.m draws it (26r/23 at d = r, 546r/480 the limit from below); d_a > d for d >= r;
#      2r/3 at d = 0; a zero area; and the default method `===` to v0.3.0's body, copied as text.
# A lecture's definition is copied here as text, with its .qmd file and lines; no companion script is run.

using Test
using Logjam
using DataFrames
using CSV
using Random

# SHA is in every environment Logjam is in but not a dependency of the test target (test_geodata_v031.jl, Sec. 4)
const _BX_SHA = Base.require(Base.PkgId(Base.UUID("ea8e919c-243c-51af-8825-aaa63cd721ce"), "SHA"))
_bx_sha(b) = bytes2hex(_BX_SHA.sha256(b))
_bx_lf(path) = (b = read(path); b[b .!= UInt8('\r')])          # the file as committed: a Windows checkout may add CRs

# data/usplacebox.csv's SHA-256, printed by tools/v0_3_1/make_placebox.jl on two runs (Julia 1.12.6)
const _BX_PLACEBOX_SHA = "39d6c7345c7f795a6cd87b0780202c8677155d05fda1e4f3ebbad7e109ea816b"

# a place's box as the table holds it, ((LONmin, LONmax), (LATmin, LATmax))
function _bx_placebox(stfip, plfip)
    B = Logjam._table("usplacebox")
    j = only(findall((B.STFIP .== stfip) .& (B.PLFIP .== plfip)))
    return ((B.LONmin[j], B.LONmax[j]), (B.LATmin[j], B.LATmax[j]))
end
_bx_plfip(st, name) = only(filter(r -> r.ST == st && r.NAME == name, usplace())).PLFIP
_bx_err(f) = try f(); nothing catch e; e end

# ---- 1. the place boxes ----------------------------------------------------------------------------------------------
@testset "[WP10 X7] usplacebox: one box for each usplace() row, the derivation's output" begin
    B = Logjam._table("usplacebox")
    p = usplace()
    @test names(B) == ["STFIP", "PLFIP", "LONmin", "LONmax", "LATmin", "LATmax"]
    @test eltype.(eachcol(B)) == [Int64, Int64, Float64, Float64, Float64, Float64]
    kb = collect(zip(B.STFIP, B.PLFIP))
    @test issorted(kb) && allunique(kb)
    @test kb == sort!(collect(zip(p.STFIP, p.PLFIP)))              # exactly usplace()'s keys
    @test nrow(B) == nrow(p) == 31617
    @test all(B.LONmin .<= B.LONmax) && all(B.LATmin .<= B.LATmax)
    # the CSV is make_placebox.jl's output byte for byte, and the .jls is that CSV read back
    csv = _bx_lf(joinpath(pkgdir(Logjam), "data", "usplacebox.csv"))
    @test _bx_sha(csv) == _BX_PLACEBOX_SHA
    back = CSV.read(IOBuffer(csv), DataFrame; ntasks = 1)
    @test isequal(back, B) && eltype.(eachcol(back)) == eltype.(eachcol(B))
    # every place's box contains its usplace() point (D3's invariant), all rows
    row = Dict(k => j for (j, k) in enumerate(kb))
    outside = Int[]
    for i in 1:nrow(p)
        j = row[(p.STFIP[i], p.PLFIP[i])]
        (B.LONmin[j] <= p.LON[i] <= B.LONmax[j] && B.LATmin[j] <= p.LAT[i] <= B.LATmax[j]) || push!(outside, i)
    end
    @test isempty(outside)
end

@testset "[WP10 X7] Raleigh's box is within 0.05 degrees of Nominatim's on every side (D3)" begin
    nominatim = (-78.8190, -78.4708, 35.7083, 35.9707)    # CR 28's record of Nominatim's boundingbox: xmin, xmax, ymin, ymax
    bb = mapbbox("Raleigh"; state = :NC)
    got = (bb[1][1], bb[1][2], bb[2][1], bb[2][2])
    @test all(abs.(got .- nominatim) .<= 0.05)
    @test got == (-78.818556, -78.470789, 35.70825, 35.970784)   # the .shp's box of place 37 55000, as the script read it
    @test bb == _bx_placebox(37, 55000)
end

# ---- 2. mapbbox(name; state, place) -----------------------------------------------------------------------------------
@testset "[WP10 X7] every county's box is the one it had at the branch's start, bit for bit" begin
    lines = filter(l -> !startswith(l, "#"), readlines(joinpath(@__DIR__, "data", "county_boxes_f3f0c1b.csv")))
    @test lines[1] == "STFIP,COFIP,ST,NAME,LONmin,LONmax,LATmin,LATmax,ERROR"
    rows = [split(l, ',') for l in lines[2:end]]
    c = uscounty()
    @test length(rows) == nrow(c) == 3143
    @test all(length.(rows) .== 9)
    @test [(parse(Int, f[1]), parse(Int, f[2]), Symbol(f[3]), String(f[4])) for f in rows] ==
          [(c.STFIP[i], c.COFIP[i], c.ST[i], String(c.NAME[i])) for i in 1:nrow(c)]
    differ, nbox, nerr = Int[], 0, 0
    for (i, f) in enumerate(rows)
        got = try mapbbox(String(c.NAME[i]); state = c.ST[i]) catch e; e end
        if isempty(f[9])
            want = ((parse(Float64, f[5]), parse(Float64, f[6])), (parse(Float64, f[7]), parse(Float64, f[8])))
            got === want || push!(differ, i)                    # `===` on a tuple of Float64 compares the bits
            nbox += 1
        else
            (got isa ArgumentError && sprint(showerror, got) == f[9]) || push!(differ, i)
            nerr += 1
        end
    end
    @test isempty(differ)
    @test (nbox, nerr) == (3131, 12)      # 12: the six names two counties share in a state ("Baltimore", MD, and so on)
    # the expansion of a county's box is unchanged too
    for (nm, st) in (("Wake", :NC), ("Durham", :NC), ("Los Angeles", :CA))
        bb = mapbbox(nm; state = st)
        @test mapbbox(nm; state = st, xexpand = 0.1, yexpand = 0.2) === mapbbox(bb; xexpand = 0.1, yexpand = 0.2)
        @test mapbbox(nm; state = st, place = false) === bb
    end
end

@testset "[WP10 X7] mapbbox(name; state, place): a county first, then a place (D3)" begin
    # "Durham", NC: the county by default, the city of Durham (PLFIP 19000) with place = true
    d = mapbbox("Durham"; state = :NC)
    @test d === ((-79.02299880542887, -78.70670497613263), (35.86443470186037, 36.258072038495634))
    @test _bx_plfip(:NC, "Durham") == 19000
    dp = mapbbox("Durham"; state = :NC, place = true)
    @test dp == _bx_placebox(37, 19000) && dp != d
    @test dp isa Tuple{Tuple{Float64, Float64}, Tuple{Float64, Float64}}     # the shape mapbbox returns
    # a name that matches no county gives the place
    @test mapbbox("Raleigh"; state = :NC) == mapbbox("Raleigh"; state = :NC, place = true) == _bx_placebox(37, 55000)
    @test mapbbox("Cary"; state = :NC) == _bx_placebox(37, 10740)
    # ignoring case and spaces, and a state as a string or a full name, as for a county
    @test mapbbox("  RALEIGH "; state = "North Carolina") == mapbbox("raleigh"; state = "NC") == _bx_placebox(37, 55000)
    # the name without its designator: "city" or "town" given, or a CDP's without "CDP"
    @test mapbbox("Raleigh city"; state = :NC) == _bx_placebox(37, 55000)
    @test mapbbox("Cary town"; state = :NC) == _bx_placebox(37, 10740)
    durcdp = _bx_plfip(:CA, "Durham CDP")
    @test mapbbox("Durham CDP"; state = :CA) == mapbbox("Durham"; state = :CA) == mapbbox("durham cdp"; state = :CA) ==
          _bx_placebox(6, durcdp)
    # an exact name is preferred: Burbank, CA is the city, not Burbank CDP
    @test mapbbox("Burbank"; state = :CA) == _bx_placebox(6, _bx_plfip(:CA, "Burbank"))
    @test mapbbox("Burbank CDP"; state = :CA) == _bx_placebox(6, _bx_plfip(:CA, "Burbank CDP"))
    # a capitalized word of a name is part of it: "Kansas City" is matched, "Kansas" is not
    @test mapbbox("Kansas City"; state = :MO) == _bx_placebox(29, _bx_plfip(:MO, "Kansas City"))
    e = _bx_err(() -> mapbbox("Kansas"; state = :MO))
    @test e isa ArgumentError && occursin("no county or place named \"Kansas\" in MO", e.msg)
    # place = true reaches a place whose name two counties share ("Baltimore": the county and the independent city)
    e = _bx_err(() -> mapbbox("Baltimore"; state = :MD))
    @test e isa ArgumentError && e.msg == "mapbbox: \"Baltimore\" names 2 counties in MD."
    @test mapbbox("Baltimore"; state = :MD, place = true) == _bx_placebox(24, _bx_plfip(:MD, "Baltimore"))
    # with place = true a county's name that is no place's is an error; so is a name that is neither
    e = _bx_err(() -> mapbbox("Wake"; state = :NC, place = true))
    @test e isa ArgumentError && occursin("no place named \"Wake\" in NC", e.msg)
    e = _bx_err(() -> mapbbox("Wakee"; state = :NC))
    @test e isa ArgumentError && occursin("no county or place named \"Wakee\" in NC", e.msg)
    @test _bx_err(() -> mapbbox("Raleigh")) isa ArgumentError                     # no state
    @test _bx_err(() -> mapbbox("Raleigh"; state = :XX)) isa ArgumentError
    @test _bx_err(() -> mapbbox(" "; state = :NC, place = true)) isa ArgumentError
    # xexpand and yexpand act on a place's box exactly as on a county's: mapbbox(bb; xexpand, yexpand)
    for (nm, st, pl) in (("Raleigh", :NC, false), ("Durham", :NC, true), ("Durham", :CA, false))
        bb = mapbbox(nm; state = st, place = pl)
        @test mapbbox(nm; state = st, place = pl, xexpand = 0.1, yexpand = 0.2) === mapbbox(bb; xexpand = 0.1, yexpand = 0.2)
        @test mapbbox(nm; state = st, place = pl, xexpand = 2, yexpand = 0.5) === mapbbox(bb; xexpand = 2, yexpand = 0.5)
    end
    @test isempty(Test.detect_ambiguities(Logjam))
end

@testset "[WP10 X7] a name two places share in a state is an ArgumentError naming them" begin
    for (nm, st, members) in (("Kailua", :HI, ["Kailua CDP"]), ("St. Anthony", :MN, ["St. Anthony"]),
                              ("Oakwood village", :OH, ["Oakwood village"]))
        p = filter(r -> r.ST == st && r.NAME in members, usplace())
        @test nrow(p) == 2
        e = _bx_err(() -> mapbbox(nm; state = st))
        @test e isa ArgumentError && occursin("\"$nm\" names 2 places in $st", e.msg) &&
              all(occursin("\"$(r.NAME)\" (PLFIP $(r.PLFIP))", e.msg) for r in eachrow(p))
    end
    # every name that two or more places of a state share, as usplace() writes it (ignoring case): 81 of them
    p = usplace()
    g = groupby(transform(p, :NAME => ByRow(lowercase) => :q), [:ST, :q])
    shared = [sub for sub in g if nrow(sub) > 1]
    @test length(shared) == 81
    bad = Tuple{Symbol, String}[]
    for sub in shared
        e = _bx_err(() -> mapbbox(sub.NAME[1]; state = sub.ST[1], place = true))
        (e isa ArgumentError && occursin("names $(nrow(sub)) places in $(sub.ST[1])", e.msg) &&
         all(occursin("(PLFIP $pl)", e.msg) for pl in sub.PLFIP)) || push!(bad, (sub.ST[1], sub.NAME[1]))
    end
    @test isempty(bad)
end

@testset "[WP10 X7] every place by its own name gives its own box" begin
    p = usplace()
    q = lowercase.(p.NAME)
    n = Dict{Tuple{Symbol, String}, Int}()
    for i in 1:nrow(p)
        n[(p.ST[i], q[i])] = get(n, (p.ST[i], q[i]), 0) + 1
    end
    cq = Set(zip(uscounty().ST, lowercase.(uscounty().NAME)))
    B = Logjam._table("usplacebox")
    boxof = Dict((B.STFIP[j], B.PLFIP[j]) => ((B.LONmin[j], B.LONmax[j]), (B.LATmin[j], B.LATmax[j])) for j in 1:nrow(B))
    bad, ncounty, nplace = Int[], 0, 0
    for i in 1:nrow(p)
        n[(p.ST[i], q[i])] == 1 || continue                     # the names two places share are the testset above
        box = boxof[(p.STFIP[i], p.PLFIP[i])]
        mapbbox(p.NAME[i]; state = p.ST[i], place = true) == box || push!(bad, i)
        # without place = true, a name that is also a county's gives the county; any other, the place
        if (p.ST[i], replace(q[i], r"\s+county$" => "")) in cq
            ncounty += 1
        else
            mapbbox(p.NAME[i]; state = p.ST[i]) == box || push!(bad, i)
            nplace += 1
        end
    end
    @test isempty(bad)
    @test ncounty + nplace == nrow(p) - sum(v for v in values(n) if v > 1)
    @test ncounty > 0 && nplace > 30_000
end

# ---- 3. mapbbox(state) ------------------------------------------------------------------------------------------------
# Lecture 4.2's Code block 3 (4-networks/4-net-2.qmd:160-165), as text: a county's box from its block groups `B`
function _bx_lecture42(B)
    mpd = dgc((0, 0), (0, 1))                 # miles in a degree of latitude
    rad = sqrt.(B.ALAND ./ π)                 # radius as a disk, mi
    dlon = rad ./ (mpd .* cosd.(B.LAT))       # that radius in degrees of lon
    dlat = rad ./ mpd                         # and of lat
    bbW = (minimum(B.LON .- dlon), maximum(B.LON .+ dlon),
           minimum(B.LAT .- dlat), maximum(B.LAT .+ dlat))
    return bbW
end

@testset "[WP10 X7] mapbbox(state) is the extent of its counties' boxes, for every state" begin
    c, b = uscounty(), uscenblkgrp()
    # each county's block groups, in the table's order, as 4.2's `filter` takes them
    g = groupby(b, [:STFIP, :COFIP]; sort = false)
    lec = Dict((k.STFIP, k.COFIP) => _bx_lecture42(sub) for (k, sub) in pairs(g))
    @test length(lec) == nrow(c)
    # 4.2's box is mapbbox(county; state)'s, reordered, for every county a name reaches
    differ = Int[]
    for i in 1:nrow(c)
        bb = try mapbbox(String(c.NAME[i]); state = c.ST[i]) catch; nothing end
        bb === nothing && continue                               # the 12 that share a name (the testset above)
        l = lec[(c.STFIP[i], c.COFIP[i])]
        bb === ((l[1], l[2]), (l[3], l[4])) || push!(differ, i)
    end
    @test isempty(differ)
    S = usstate()
    @test nrow(S) == 51
    notext, notin = Symbol[], Symbol[]
    for st in S.ST
        sb = mapbbox(st)
        boxes = [mapbbox(((l[1], l[2]), (l[3], l[4]))) for (k, l) in lec if k[1] == st2fips(st)]   # as mapbbox(county; state) gives each
        @test length(boxes) == count(==(st), c.ST)
        ext = ((minimum(x[1][1] for x in boxes), maximum(x[1][2] for x in boxes)),
               (minimum(x[2][1] for x in boxes), maximum(x[2][2] for x in boxes)))
        sb == ext || push!(notext, st)
        all(sb[1][1] <= x[1][1] && x[1][2] <= sb[1][2] && sb[2][1] <= x[2][1] && x[2][2] <= sb[2][2] for x in boxes) ||
            push!(notin, st)
    end
    @test isempty(notext)
    @test isempty(notin)
    # the shape, the expansion, and what is not a state
    nc = mapbbox(:NC)
    @test nc isa Tuple{Tuple{Float64, Float64}, Tuple{Float64, Float64}}
    @test mapbbox(:NC; xexpand = 0.1, yexpand = 0.2) === mapbbox(nc; xexpand = 0.1, yexpand = 0.2)
    @test mapbbox(:DC) == mapbbox("District of Columbia"; state = :DC)            # one county
    @test _bx_err(() -> mapbbox(:PR)) isa ArgumentError                            # a territory: no counties
    @test _bx_err(() -> mapbbox(:XX)) isa ArgumentError
end
