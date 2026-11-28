# test_datatools.jl -- the tests of src/datatools.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_datatools.jl, its lines 1-164, 611-632 ====
using Test
using DataFrames

# Test for usplace function
@testset "usplace function tests" begin
    df = usplace()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["STFIP", "PLFIP", "NAME", "ST", "LAT", "LON", "POP", "ALAND", "AWATER", "LSAD", "FUNCSTAT", "CBSA", "ISCUS"]))
end

# Test for uscounty function
@testset "uscounty function tests" begin
    df = uscounty()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["STFIP", "COFIP", "NAME", "ST", "LAT", "LON", "POP", "ALAND", "AWATER", "CBSA", "ISCUS"]))
end

# Test for uscentract function
@testset "uscentract function tests" begin
    df = uscentract()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["STFIP", "COFIP", "TRFIP", "ST", "LAT", "LON", "POP", "ALAND", "AWATER", "ISCUS"]))
end

# Test for uscenblkgrp function
@testset "uscenblkgrp function tests" begin
    df = uscenblkgrp()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["STFIP", "COFIP", "TRFIP", "BGFIP", "LAT", "LON", "POP", "ALAND", "AWATER", "ISCUS"]))
end

# Test for uszcta5 function
@testset "uszcta5 function tests" begin
    df = uszcta5()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["ZCTA5", "LAT", "LON", "POP", "ALAND", "AWATER", "ISCUS", "STFIP"]))   # STFIP appended in v0.3.1 (D4)
end

# Test for uszcta3 function
@testset "uszcta3 function tests" begin
    df = uszcta3()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["ZCTA3", "LAT", "LON", "POP", "ALAND", "AWATER", "ISCUS", "STFIP"]))   # STFIP appended in v0.3.1 (D4)
end

# Test for uscbsa function
@testset "uscbsa function tests" begin
    df = uscbsa()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["CBSA", "NAME", "LAT", "LON", "POP", "ALAND", "AWATER", "IS_MSA", "CSA", "ISCUS"]))

    # G4.1: M_MSA::String replaced by IS_MSA::Bool; Metropolitan count preserved
    @test "IS_MSA" in names(df)
    @test eltype(df.IS_MSA) == Bool
    @test count(df.IS_MSA) == 382
    @test !("M_MSA" in names(df))
end

# Test for uscsa function
@testset "uscsa function tests" begin
    df = uscsa()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["CSA", "NAME", "LAT", "LON", "POP", "ALAND", "AWATER", "ISCUS"]))
end

# G1.1: census loaders are LON-first (LON column precedes LAT column)
@testset "census LON-first column order (G1.1)" begin
    loaders = [usplace, uscounty, uscentract, uscenblkgrp,
               uszcta5, uszcta3, uscbsa, uscsa]
    for loader in loaders
        df = loader()
        cols = names(df)
        ilon = findfirst(==("LON"), cols)
        ilat = findfirst(==("LAT"), cols)
        @test ilon !== nothing
        @test ilat !== nothing
        @test ilon < ilat
    end
end

# G2.1: uscentract().ST is a Symbol column with a known :NC value
@testset "uscentract ST Symbol (G2.1)" begin
    df = uscentract()
    @test eltype(df.ST) <: Symbol
    @test any(df.ST .== :NC)
end

# G3.1: uscsa().NAME is a plain String column with no missing values
@testset "uscsa NAME String (G3.1)" begin
    df = uscsa()
    @test eltype(df.NAME) == String
    @test count(ismissing, df.NAME) == 0
end

# v0.2.9: every US-prefixed census loader carries ISCUS::Bool as its final column
# (uniform schema — guards against the pre-0.2.9 hit-or-miss inconsistency)
@testset "ISCUS uniform across census loaders (v0.2.9)" begin
    loaders = [usplace, uscounty, uscentract, uscenblkgrp,
               uszcta5, uszcta3, uscbsa, uscsa]
    for loader in loaders
        df = loader()
        @test "ISCUS" in names(df)
        @test eltype(df.ISCUS) == Bool
        # ISCUS ends the v0.2.9 schema; on the ZIP tables v0.3.1 appends STFIP after it (D4)
        @test names(df)[end] == "ISCUS" || (loader in (uszcta5, uszcta3) && names(df)[end-1:end] == ["ISCUS", "STFIP"])
    end
end

# Test for st2fips function
@testset "st2fips function tests" begin
    @test st2fips(:NC) == 37
    @test st2fips(:NY) == 36
    @test st2fips.([:NC, :NY]) == [37, 36]   # docstring broadcast example
    @test_throws ArgumentError st2fips(:XX)
end

# Test for fips2st function
@testset "fips2st function tests" begin
    @test fips2st(37) == :NC
    @test fips2st(36) == :NY
    @test fips2st(72) == :PR
    @test fips2st.(37:39) == [:NC, :ND, :OH]   # docstring broadcast example
    @test_throws ArgumentError fips2st(99)
end

# Test for FAF5 road network functions
@testset "faf5nodes function tests" begin
    df = faf5nodes()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test "IDX" in names(df)
    @test "LON" in names(df)
    @test "LAT" in names(df)
    # Check that coordinates are in valid range
    @test all(-180 .<= df.LON .<= 180)
    @test all(-90 .<= df.LAT .<= 90)
end

@testset "faf5links function tests" begin
    df = faf5links()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test "SRC" in names(df)
    @test "DST" in names(df)
    @test "DIST" in names(df)
    # Check positive distances
    @test all(df.DIST .>= 0)
end

# the Interstate polylines the map drew above 150 miles (P8: the exported faf5interstate, 0 calls, duplicated them) are
# retired with their data file (CR 19, N4): makemap draws Logjam's U.S. road network (usrdlink) there instead
@testset "faf5interstateroads and its data file are retired (N4)" begin
    @test !isdefined(Logjam, :faf5interstate)
    @test !isdefined(Logjam, :faf5interstateroads) && !isdefined(Logjam, :_faf5interstate_cache)
    @test !isfile(joinpath(pkgdir(Logjam), "data", "faf5_interstate_roads.jls"))
end

# C12 (PCV K11b): faf5nodes() and faf5links() read their file once per session and return copies. The values, the
# column kinds and that each call returns a table of its own are pinned from the code before the change, in
# test_map_line_pins.jl; these check the cache itself.
@testset "[MAP, C12] faf5nodes() and faf5links() read their file once and return copies" begin
    n1, l1 = faf5nodes(), faf5links()
    cn, cl = Logjam._faf5nodes_cache[], Logjam._faf5links_cache[]
    @test cn isa DataFrame && cl isa DataFrame
    n2, l2 = faf5nodes(), faf5links()
    @test Logjam._faf5nodes_cache[] === cn && Logjam._faf5links_cache[] === cl      # read once: the cache is not replaced
    @test isequal(n1, n2) && isequal(l1, l2) && isequal(n1, cn) && isequal(l1, cl)     # `==` is missing where a cell is
    @test n1 !== cn && n1 !== n2 && l1 !== cl && l1 !== l2                           # a table of its own for each call
    @test n1.LON !== cn.LON && n1.LON !== n2.LON && l1.DIST !== cl.DIST              # columns copied, not shared
    # changing a result changes neither the cache nor the next call
    l1.DIST .= 0.0; l1.SIGN[1] = "changed"; n1.LAT .= 0.0
    select!(n2, [:IDX, :LON]); deleteat!(l2, 1:5)
    @test isequal(faf5links(), cl) && isequal(faf5nodes(), cn)
    @test names(faf5nodes()) == names(cn) && nrow(faf5links()) == nrow(cl)
    # calls from tasks at once get the same table
    got = fetch.([Threads.@spawn(faf5links()) for _ in 1:4])
    @test all(g -> isequal(g, cl) && g !== cl, got)
end

# ==== moved from test/test_map_line_pins.jl, its lines 1-13, 187-247 ====
# test_map_line_pins.jl -- what the course sees of `plotroads!`, the base-layer styles `makemap` draws, the FAF5
# tables and `tracepath`, pinned from the code at 83c799b (PCV K11b, plan principle 9; K11a's own pins are
# test_map_pins.jl). The values below were measured on the unchanged code, before K11b's C4 (`makemap`'s interface),
# C8 (the line builders) and C12 (cached FAF5 tables) changed it. A call the course makes today keeps returning
# what it returned then; only a case named in MLPIN_MOVED may differ, and each one is named in the commit that moves it.
#
# No case touches the network or a file outside the package, and none renders a picture.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie
isdefined(@__MODULE__, :MLPIN_MOVED) || include(joinpath(@__DIR__, "map_line_pin_helpers.jl"))   # WP8: defined once

# ---- the FAF5 tables -----------------------------------------------------------------------------------------
# A checksum of a column: FNV-1a over the column's values in order (integers and floats by their 64 bits, strings by
# their bytes, a missing by a marker), so a change to any value or to the order changes it.
const _MLPIN_FNV_PRIME = 0x00000100000001b3
_mlpin_mix(h::UInt64, x::UInt64) = (h ⊻ x) * _MLPIN_FNV_PRIME
_mlpin_mix(h::UInt64, v::Integer) = _mlpin_mix(h, reinterpret(UInt64, Int64(v)))
_mlpin_mix(h::UInt64, v::AbstractFloat) = _mlpin_mix(h, reinterpret(UInt64, Float64(v)))
_mlpin_mix(h::UInt64, ::Missing) = _mlpin_mix(h, "<missing>")
function _mlpin_mix(h::UInt64, s::AbstractString)
    for b in codeunits(s)
        h = _mlpin_mix(h, UInt64(b))
    end
    return _mlpin_mix(h, UInt64(0xff))
end
function _mlpin_colsum(col)
    h = 0xcbf29ce484222325
    for v in col
        h = _mlpin_mix(h, v)
    end
    return string(h, base = 16)
end
# a column's kind: Int64, Float64 or String, with a "?" when it can hold a missing
_mlpin_kind(T) = (nonmissingtype(T) <: AbstractString ? "String" : string(nonmissingtype(T))) * (Missing <: T ? "?" : "")
_mlpin_table(df) = (size = size(df), names = names(df), kinds = [_mlpin_kind(eltype(c)) for c in eachcol(df)],
                    sums = [_mlpin_colsum(c) for c in eachcol(df)], missings = [count(ismissing, c) for c in eachcol(df)])

const MLPIN_FAF5NODES = (size = (344998, 10),
    names = ["IDX", "LON", "LAT", "ENTRY_EXIT", "EXIT_NUM", "INTERCHANGE", "FACILITY_TYPE", "FACILITY_NAME", "STATEID", "FAFID"],
    kinds = ["Int64", "Float64", "Float64", "String?", "String?", "String?", "String?", "String?", "Int64", "Int64"],
    sums = ["6b3aebb8b846557d", "4a958dc40e2a898d", "84ff8720cb07404a", "60b10316d13d1d8d", "b2ba03681c6ce1ad", "9df270cb6fc10912", "a4add17fdde1bcda", "2b2d0ba73a38d503", "1267def9b11825bd", "1267def9b11825bd"],
    missings = [0, 0, 0, 343440, 343928, 343434, 340054, 340052, 0, 0])
const MLPIN_FAF5LINKS = (size = (483530, 25),
    names = ["SRC", "DST", "DIST", "STFIP", "COFIP", "SPEED", "NHS", "SIGN", "NAME", "FCLASS", "URBAN", "AB_SPEED", "BA_SPEED", "AB_TIME", "BA_TIME", "AB_LANES", "BA_LANES", "DIR", "STRAHNET", "NHFN", "TOLL_TYPE", "TOLL_LINK", "BORDER_LINK", "FAFZONE", "STATUS"],
    kinds = ["Int64", "Int64", "Float64", "Int64", "Int64", "Int64", "Int64", "String?", "String?", "Int64", "Int64?", "Float64", "Float64", "Float64", "Float64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64"],
    sums = ["243c235cf38d51e8", "9002e4b393d3b973", "56d69e43bcb4bb3c", "5679e14f1251eae9", "6b291df2c012aaa1", "c1097f45a8cd0fc0", "c7119800158f324c", "48b68dea93374b0a", "ac1e14a791acf526", "d1ee499f29259c3a", "90727a59dccce0b9", "f8c837a2c4c4638f", "28acf4a8e83154", "9e08ff7d099f7387", "53bdeebb85c2b3b6", "a525fbd32be3e0a4", "cc579de8e90b930d", "336aeb10c85588e1", "6cd98b3bd6e9114f", "ce71afbc78865c4f", "239f9da6c6fd7c1f", "c3f8f56d007d5728", "55c050ace0ac4eca", "4cebd0932d71a30e", "ba15765f6cd9e71d"],
    missings = [0, 0, 0, 0, 0, 0, 0, 247001, 38692, 0, 1758, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

@testset "faf5nodes() and faf5links() are pinned: sizes, column names, kinds, per-column checksums" begin
    @testset "faf5nodes" begin
        _mlpin_moved("faf5nodes") || @test _mlpin_table(faf5nodes()) == MLPIN_FAF5NODES
    end
    @testset "faf5links" begin
        _mlpin_moved("faf5links") || @test _mlpin_table(faf5links()) == MLPIN_FAF5LINKS
    end
    @testset "each call returns a table of its own: changing one never changes the next" begin
        if !_mlpin_moved("faf5_fresh_copies")
            a = faf5links()
            a.DIST .= -1.0
            a.SIGN[1] = "changed"
            deleteat!(a, 1:10)
            b = faf5links()
            @test _mlpin_table(b) == MLPIN_FAF5LINKS
            @test a !== b
            n = faf5nodes()
            n.LON .= 0.0
            select!(n, [:IDX, :LON])
            @test _mlpin_table(faf5nodes()) == MLPIN_FAF5NODES
        end
    end
end

# ==== moved from test/test_k12_functions.jl, its lines 1-14, 156-214 ====
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

# ==== moved from test/test_geodata_v031.jl, its lines 1-25, 619-639, 711-825 ====
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

# ---- 3. one memoized loader and the name index (A10) ------------------------------------------------------------------
@testset "[WP5 A10] every census loader returns a copy: a changed table does not reach the next call" begin
    for f in (usplace, uscounty, uscentract, uscenblkgrp, uszcta5, uszcta3, uscbsa, uscsa, usstate)
        a, b = f(), f()
        @test a !== b && isequal(a, b) && all(c -> c[1] !== c[2], zip(eachcol(a), eachcol(b)))
        n, cols = nrow(b), names(b)
        a.LON .= 0.0                          # a column changed in place
        a[1, :POP] = -1                       # a cell
        a.NEWCOL = collect(1:n)               # a column added
        deleteat!(a, 1)                       # a row removed
        c = f()
        @test isequal(c, b) && names(c) == cols && nrow(c) == n && c.LON == b.LON
    end
    # the memoized table is the file's: read once, kept unchanged by the copies and by the geocoder's lookups
    loc2lonlat(["Raleigh", "Durham"]; state = :NC)
    for name in ("usplace", "uscounty", "uszcta5")
        @test isequal(Logjam._table(name), open(Logjam.deserialize, joinpath(pkgdir(Logjam), "data", name * ".jls")))
        @test Logjam._table(name) === Logjam._table(name)
    end
end

@testset "[WP5 X6] the ZIP tables hold Puerto Rico's 40 ZCTA5s that begin with 009, and their docstrings say so" begin
    z5, z3 = uszcta5(), uszcta3()
    pr = z5[z5.ZCTA5 .< 1000, :]
    @test nrow(pr) == 40 && extrema(pr.ZCTA5) == (901, 987) && !any(pr.ISCUS)
    @test z3.ZCTA3[z3.ZCTA3 .< 10] == [9] && !only(z3.ISCUS[z3.ZCTA3 .== 9])
    @test only(z3.POP[z3.ZCTA3 .== 9]) == sum(pr.POP)
    for f in (uszcta5, uszcta3)
        d = string(Docs.doc(f))
        @test occursin("Puerto Rico", d) && occursin("ISCUS = false", d) && !occursin("Does not include U.S. territories", d)
    end
end

# ---- 4. STFIP on the ZIP tables (MakePlan D4, X6) ----------------------------------------------------------------------
# SHA is in every environment Logjam is in (Random depends on it) but not a dependency of the test target, so it is
# reached by its package id, as tools/v0_3_1/make_faf5net.jl reaches CodecZlib.
const _GD_SHA = Base.require(Base.PkgId(Base.UUID("ea8e919c-243c-51af-8825-aaa63cd721ce"), "SHA"))
_gd_sha(b) = bytes2hex(_GD_SHA.sha256(b))
_gd_lf(path) = (b = read(path); b[b .!= UInt8('\r')])          # the file as committed: a Windows checkout may add CRs
_gd_csv(df) = (io = IOBuffer(); CSV.write(io, df); take!(io))

# the committed tables' SHA-256, printed by tools/v0_3_1/make_zcta_stfip.jl on two runs (Julia 1.12.6), and the
# SHA-256 of the v0.3.0 tables (fd0f1f3's data/uszcta5.csv and uszcta3.csv), which CSV.write of their columns gives
const _GD_ZCTA_SHA = Dict(
    "uszcta5" => (new = "fee98453f863f4ac6e93eaf7cbabf8a6ad5431d72ff139af32f616ba173e1adc",
                  old = "b3c56baefd7f08428a2158eaf9d45eedd798281ca4fee0adc2e4602b5a0b9752"),
    "uszcta3" => (new = "7c60ed0ff6859b6b33c7e91a5c2e7f2688fb66c873a165450765f1897881dcac",
                  old = "3e8a0f7af8fb1eb3dccddee63365572572ffb6795fb12889c6e12fb0c98a90c8"))
const _GD_EXTRACT_SHA = "8c442f6d4577b9ccdde6cd7dbc0a5f2cbefcee309eabf786766062503ddcfbc6"
const _GD_V030_TYPES = [Int64, Float64, Float64, Int64, Float64, Float64, Bool]

# the rule, as the script states it: the most land, else the most water; a tie to the smaller FIPS code
function _gd_pick(d::AbstractDict)
    sts = sort!(collect(keys(d)))
    k = sum(d[s][1] for s in sts) > 0 ? 1 : 2
    best = sts[1]
    for s in sts
        d[s][k] > d[best][k] && (best = s)
    end
    return best
end

@testset "[WP5 D4] STFIP is the last column of uszcta5 and uszcta3, and nothing else moved" begin
    data = joinpath(pkgdir(Logjam), "data")
    for (name, f, code) in (("uszcta5", uszcta5, :ZCTA5), ("uszcta3", uszcta3, :ZCTA3))
        df = f()
        @test names(df) == [String(code), "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS", "STFIP"]
        @test eltype(df.STFIP) == eltype(usplace().STFIP) == Int64
        @test !any(ismissing, df.STFIP) && all(s -> s in keys(Logjam.fips_state), df.STFIP)
        # the existing columns: v0.3.0's types, and the bytes of v0.3.0's CSV file
        old = select(df, Not(:STFIP))
        @test eltype.(eachcol(old)) == _GD_V030_TYPES
        @test _gd_sha(_gd_csv(old)) == _GD_ZCTA_SHA[name].old
        # the CSV is the script's output byte for byte, and the .jls is that CSV read back
        csv = _gd_lf(joinpath(data, name * ".csv"))
        @test _gd_sha(csv) == _GD_ZCTA_SHA[name].new
        back = CSV.read(IOBuffer(csv), DataFrame; ntasks = 1)
        @test isequal(back, df) && eltype.(eachcol(back)) == eltype.(eachcol(df))
    end
    # every ZIP of Puerto Rico in the tables, 009xx, is 72, outside the continental U.S.
    z5, z3 = uszcta5(), uszcta3()
    pr = filter(r -> 900 <= r.ZCTA5 <= 999, z5)
    @test nrow(pr) == 40 && all(==(72), pr.STFIP) && !any(pr.ISCUS)
    @test only(z3.STFIP[z3.ZCTA3 .== 9]) == 72
    @test count(==(72), z5.STFIP) == 40 && count(==(72), z3.STFIP) == 1
    # a few with no doubt: Raleigh's 27601, Cambridge's 02139, Beverly Hills' 90210
    @test [only(z5.STFIP[z5.ZCTA5 .== z]) for z in (27601, 2139, 90210)] == [37, 25, 6]
end

@testset "[WP5 D4] each cross-state ZCTA and each three-digit ZCTA follows the rule, from the committed extract" begin
    path = joinpath(@__DIR__, "data", "zcta_state_parts.csv")
    @test _gd_sha(_gd_lf(path)) == _GD_EXTRACT_SHA
    ex = CSV.read(path, DataFrame; comment = "#")
    parts = Dict{Int, Dict{Int, NTuple{2, Int}}}()
    for r in eachrow(ex)
        get!(parts, r.ZCTA5, Dict{Int, NTuple{2, Int}}())[r.STFIP] = (r.ALAND_M2, r.AWATER_M2)
    end
    z5, z3 = uszcta5(), uszcta3()
    st5 = Dict(zip(z5.ZCTA5, z5.STFIP))
    @test all(z -> haskey(st5, z), keys(parts))
    # five-digit: every ZCTA the extract shows in two or more states takes the state with the most land
    cross = [z for (z, d) in parts if length(d) > 1]
    @test length(cross) == 137
    @test all(st5[z] == _gd_pick(parts[z]) for z in cross)
    # a ZCTA in one state takes it
    @test all(st5[z] == only(keys(d)) for (z, d) in parts if length(d) == 1)
    # the rule's no-land branch and its tie, on made-up parts (the file has neither)
    @test _gd_pick(Dict(6 => (0, 5), 4 => (0, 9))) == 4 && _gd_pick(Dict(6 => (0, 9), 4 => (0, 5))) == 6
    @test _gd_pick(Dict(6 => (7, 0), 4 => (7, 0))) == 4 && _gd_pick(Dict(6 => (8, 0), 4 => (7, 99))) == 6
    # three-digit: members in one state give that state; members in more than one, the state with the most land
    # summed over the members' parts, every member of such a ZCTA being in the extract
    members = Dict{Int, Vector{Int}}()
    for z in z5.ZCTA5
        push!(get!(members, z ÷ 100, Int[]), z)
    end
    one, mixed, incomplete, wrong = 0, 0, Int[], Int[]
    for (c, s) in zip(z3.ZCTA3, z3.STFIP)
        m = members[c]
        if all(z -> !haskey(parts, z), m) && length(unique(st5[z] for z in m)) == 1
            one += 1
            s == st5[m[1]] || push!(wrong, c)
        else
            mixed += 1
            all(z -> haskey(parts, z), m) || (push!(incomplete, c); continue)
            agg = Dict{Int, NTuple{2, Int}}()
            for z in m, (st, v) in parts[z]
                a = get(agg, st, (0, 0)); agg[st] = (a[1] + v[1], a[2] + v[2])
            end
            s == _gd_pick(agg) || push!(wrong, c)
        end
    end
    @test (one, mixed) == (799, 91)
    @test isempty(incomplete)
    @test isempty(wrong)
end
