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
    @test all(issubset(names(df), ["ZCTA5", "LAT", "LON", "POP", "ALAND", "AWATER", "ISCUS"]))
end

# Test for uszcta3 function
@testset "uszcta3 function tests" begin
    df = uszcta3()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["ZCTA3", "LAT", "LON", "POP", "ALAND", "AWATER", "ISCUS"]))
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
        @test names(df)[end] == "ISCUS"
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

# the road background the map functions draw (P8: the exported faf5interstate, 0 calls, duplicated it)
@testset "faf5interstateroads: the interstate polylines" begin
    @test !isdefined(Logjam, :faf5interstate)
    x, y = Logjam.faf5interstateroads()
    @test isa(x, Vector)
    @test isa(y, Vector)
    @test length(x) == length(y)
    @test !isempty(x)
    # Polyline vectors should contain NaN separators
    @test any(isnan, x)
    @test any(isnan, y)
    # Non-NaN values should be valid coordinates
    valid_x = filter(!isnan, x)
    valid_y = filter(!isnan, y)
    @test all(-180 .<= valid_x .<= 180)
    @test all(-90 .<= valid_y .<= 90)
end

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

# ─── H2: prt ──────────────────────────────────────────────────────
@testset "prt" begin
    @testset "integer matrix" begin
        # Should not error; output goes to stdout
        prt([1 2; 3 4])
    end

    @testset "fractional matrix" begin
        prt([0.1234 0.5678; 0.9012 0.3456])
    end

    @testset "mixed matrix with commas" begin
        prt([1.5 2000.75; 3.0 4500.25])
    end

    @testset "custom headers" begin
        prt([1.0 2.0; 3.0 4.0]; rows=["W1", "W2"], cols=["C1", "C2"])
    end

    @testset "NaN handling" begin
        prt([1.0 NaN; 3.0 4.0])
    end

    @testset "vector method" begin
        prt([1, 2, 3])
    end

    @testset "DataFrame method" begin
        df = DataFrame(A=[1, 2], B=[3.14, 2.72])
        prt(df)
    end

    @testset "empty matrix" begin
        prt(Matrix{Float64}(undef, 0, 0))
    end

    @testset "title keyword" begin
        prt([1 2; 3 4]; title="Test Title")
    end

    @testset "row_title keyword" begin
        prt([1 2; 3 4]; rows=["a", "b"], cols=["X", "Y"], row_title="ID")
    end

    @testset "row_title with vector method" begin
        prt([10, 20, 30]; rows=["A", "B", "C"], row_title="Item")
    end

    @testset "str=true returns string" begin
        s = prt([1 2; 3 4]; str=true)
        @test isa(s, String)
        @test !isempty(s)
        @test !occursin('─', s)        # separators stripped
        @test occursin("1", s)
        @test occursin("4", s)
    end

    @testset "str=false returns nothing" begin
        result = prt([1 2; 3 4])
        @test result === nothing
    end

    @testset "R3: sign preserved for values in (-1, 0)" begin
        # Regression: _formatfixed dropped the minus sign for magnitudes < 1
        # (trunc(Int, v) == 0), printing negatives as positive.
        # Each column of fractions shows the places its values have (PR): -0.50 and 0.75, -0.125 and 0.25.
        s = prt([-0.5 0.25; 0.75 -0.125]; str=true)
        @test occursin("-0.50", s)
        @test occursin("-0.125", s)
        # Positive values remain unsigned.
        @test occursin("0.250", s)
        @test !occursin("-0.250", s)
        # Internal helper directly.
        @test Logjam._formatfixed(-0.5, 4) == "-0.5000"
        @test Logjam._formatfixed(-0.125, 4) == "-0.1250"
        @test Logjam._formatfixed(0.5, 4) == "0.5000"
        @test Logjam._formatfixed(-1.5, 4) == "-1.5000"
    end

    @testset "str=true preserves alignment spaces" begin
        s = prt([1000 2; 3 4000]; str=true)
        @test occursin("1,000", s)
        @test occursin("4,000", s)
        @test occursin(' ', s)          # spaces preserved
    end

    @testset "str=true with custom headers" begin
        s = prt([1.5 2.5; 3.5 4.5]; rows=["a","b"], cols=["X","Y"], str=true)
        @test occursin("X", s)
        @test occursin("Y", s)
        @test occursin("a", s)
        @test occursin("b", s)
    end

    @testset "str=true vector method" begin
        s = prt([10, 20, 30]; str=true)
        @test isa(s, String)
        @test !occursin('─', s)
        @test occursin("10", s)
    end

    @testset "str=true DataFrame method" begin
        df = DataFrame(City=["Raleigh", "Charlotte"], Pop=[467665, 874579])
        s = prt(df; str=true)
        @test isa(s, String)
        @test !occursin('─', s)
        @test occursin("Raleigh", s)
        @test occursin("467,665", s)
    end

    @testset "str=true empty matrix" begin
        s = prt(Matrix{Float64}(undef, 0, 0); str=true)
        @test s == ""
    end
end

# ─── H3: snapvals ────────────────────────────────────────────────
@testset "snapvals" begin
    @testset "near-integer snapping" begin
        result = snapvals([2.9999999997, 1.0000000003, 0.5])
        @test result ≈ [3.0, 1.0, 0.5]
    end

    @testset "near-zero snapping" begin
        result = snapvals([1e-12, -1e-12, 0.5])
        @test result ≈ [0.0, 0.0, 0.5]
    end

    @testset "custom tolerance" begin
        result = snapvals([1.1]; atol=0.2)
        @test result ≈ [1.0]
    end

    @testset "empty array" begin
        result = snapvals(Float64[])
        @test isempty(result)
    end

    @testset "already-integer values" begin
        result = snapvals([1.0, 2.0, 3.0])
        @test result == [1.0, 2.0, 3.0]
    end

    @testset "values far from integers unchanged" begin
        result = snapvals([1.3, 2.7, 0.5])
        @test result == [1.3, 2.7, 0.5]
    end
end


# ─── isptinbbox is removed (P8, 0 course calls) ────────────────────
@testset "isptinbbox is gone" begin
    @test !isdefined(Logjam, :isptinbbox)
end

# ─── Relocated: alloclines (from maptools) ────────────────────────
@testset "alloclines relocated" begin
    using SparseArrays
    hubs = [-80.0 35.0; -78.0 36.0]
    spokes = [-80.5 35.2; -78.5 35.8; -79.2 36.1]
    W = sparse([1, 1, 2], [1, 2, 3], [1.0, 1.0, 1.0], 2, 3)
    X, Y = alloclines(W, hubs, spokes)
    @test length(X) == 2
    @test X isa Vector{Vector{Float64}}
end

# =============================================================================
# K2a: wrong-answer tests (test spec Sec. 2). Tagged [ID]; see tools/v0_3_0/run_against.jl.
# =============================================================================

# a call that throws is a wrong answer here, not a test error: report `nothing`
_attempt(f) = try f() catch; nothing end

# =============================================================================
# K4: display (WP3). prt: CR 2, CR 32, N11, N12, S13 and keyword parity; thousands: CR 8 / R6 / S12.
# =============================================================================

@testset "[CR 2] prt prints a value of 1e300 without throwing" begin
    # CR 2: no value converts to Int64; the value's own digits print at any magnitude (fixed in K4)
    @test _attempt(() -> Logjam.prt([1e300 1.0]; str = true)) isa String
    @test _attempt(() -> Logjam.prt([1e300 2.5]; str = true)) isa String
    @test _attempt(() -> Logjam.prt([1e6 2.5]; str = true)) isa String      # control: a large but Int64-sized value
end

# the tagged row above holds only assertions that FAIL on v0.2.8 (a throw is a wrong answer there, run_against.jl);
# the digits themselves are checked here
@testset "prt prints the value's own digits at any magnitude (CR 2)" begin
    row1 = split(Logjam.prt([1e300 1.0]; str = true), '\n')[2]
    digs = split(row1, "  ")[2]
    @test replace(digs, "," => "") == string(BigInt(1e300))                  # the float's own 301 digits, grouped
    @test length(replace(digs, "," => "")) == 301
    @test Logjam._commasep(BigInt(10)^40) == "10,000,000,000,000,000,000,000,000,000,000,000,000,000"
    @test Logjam._formatfixed(1e300, 2) == Logjam._commasep(BigInt(1e300)) * ".00"
    @test Logjam._formatfixed(typemax(Int64), 0) == "9,223,372,036,854,775,807"
    @test Logjam._commasep(typemin(Int64)) == "-9,223,372,036,854,775,808"
    # an Int above 2^53 keeps its last digit (it went through Float64 before)
    @test occursin("9,007,199,254,740,993", Logjam.prt([9007199254740993 1; 2 3]; str = true))
    @test occursin("10,000,000,000,000,000,000", Logjam.prt(DataFrame(s = ["a"], v = [1e19]); str = true))
end

@testset "[CR 32] prt on an all-numeric DataFrame with missing prints" begin
    df = DataFrame(A = [1.0, missing, 3.5], B = [1, 2, 3])
    @test _attempt(() -> Logjam.prt(df; str = true)) isa String
    @test _attempt(() -> Logjam.prt(DataFrame(A = [1.0, 2.0], B = [1, 2]); str = true)) isa String   # control
end

@testset "prt prints missing as blank, like NaN, on every path (CR 32)" begin
    df = DataFrame(A = [1.0, missing, 3.5], B = [1, 2, 3])
    # missing is blank, like NaN, in the all-numeric, mixed, vector and matrix paths
    @test Logjam.prt(df; str = true) == "      A  B\n1  1.00  1\n2        2\n3  3.50  3\n"
    @test Logjam.prt(df; str = true) == Logjam.prt(DataFrame(A = [1.0, NaN, 3.5], B = [1, 2, 3]); str = true)
    @test Logjam.prt(DataFrame(s = ["a", "b"], v = [1.5, missing]); str = true) ==
          Logjam.prt(DataFrame(s = ["a", "b"], v = [1.5, NaN]); str = true)
    @test !occursin("missing", Logjam.prt(DataFrame(s = ["a", "b"], v = [1.5, missing]); str = true))
    @test Logjam.prt(Union{Missing,Float64}[1.0, missing, 3.5]; str = true) == Logjam.prt([1.0, NaN, 3.5]; str = true)
    @test Logjam.prt(Union{Missing,Float64}[1.0 missing; 3.0 4.5]; str = true) == Logjam.prt([1.0 NaN; 3.0 4.5]; str = true)
    @test Logjam.prt(DataFrame(a = [1, missing, 3]); str = true) == Logjam.prt(DataFrame(a = [1, NaN, 3]); str = true)
end

@testset "prt at fracdig or allfrac of 5 or more prints no scientific notation (N11)" begin
    @test Logjam.prt([1.000001 2.5]; fracdig = 6, str = true) == "          1         2\n1  1.000001  2.500000\n"
    @test occursin("12.00001", Logjam.prt([12.00001 2.5]; fracdig = 5, str = true))
    s = Logjam.prt([0.00001 0.5; 0.25 0.125]; allfrac = 5, str = true)
    @test occursin("0.00001", s)
    @test !occursin('e', s)
    @test occursin("0.0000123", Logjam.prt([0.0000123 0.5]; allfrac = 7, str = true))
    for fd in 0:12
        @test !occursin('e', Logjam.prt([1.0000000123 2.5; 1234.5 0.000000123]; fracdig = fd, allfrac = fd, str = true))
    end
    @test Logjam._formatfixed(1.000001, 6) == "1.000001"
    @test Logjam._formatfixed(1234567.0000012, 7) == "1,234,567.0000012"
    @test Logjam._formatfixed(0.5, 20) == "0.5" * "0"^19
end

@testset "prt rounding carries into the whole part and never prints a negative zero" begin
    @test Logjam._formatfixed(1.996, 2) == "2.00"
    @test Logjam._formatfixed(0.996, 2) == "1.00"
    @test Logjam._formatfixed(999.9996, 3) == "1,000.000"
    @test Logjam._formatfixed(1999.996, 2) == "2,000.00"
    @test Logjam._formatfixed(-1.996, 2) == "-2.00"
    @test Logjam._formatfixed(-0.001, 2) == "0.00"
    @test Logjam._formatfixed(-0.0, 2) == "0.00"
    @test Logjam._formatfixed(-0.4, 0) == "0"
    @test Logjam._formatfixed(-0.5, 4) == "-0.5000"
    @test Logjam._formatfixed(-999999.9999, 2) == "-1,000,000.00"
    @test !occursin("-0.00", Logjam.prt([-0.001 0.5; 2.5 -0.4]; str = true))
    @test !occursin("-0.00", Logjam.prt([-0.00001 0.00002; 0.5 0.25]; str = true))
    @test Logjam.prt([1.996 0.99996; 2.5 0.5]; str = true) == "      1       2\n1  2.00  1.0000\n2  2.50  0.5000\n"
end

@testset "prt on text columns that are not String (N12)" begin
    sym = DataFrame(ST = [:NC, :VA], POP = [1, 2])
    @test Logjam.prt(sym; str = true) == Logjam.prt(DataFrame(ST = ["NC", "VA"], POP = [1, 2]); str = true)
    @test occursin("NC", Logjam.prt(sym; str = true))
    @test Logjam.prt(DataFrame(a = Union{Missing,String}["x", "y"], v = [1.5, 2.0]); str = true) ==
          Logjam.prt(DataFrame(a = ["x", "y"], v = [1.5, 2.0]); str = true)
    # a missing in a text column is blank
    @test Logjam.prt(DataFrame(a = Union{Missing,String}["x", missing], v = [1.5, 2.0]); str = true) ==
          "  a     v\n  x  1.50\n     2.00\n"
    @test Logjam.prt(DataFrame(ST = [:NC, :VA]); str = true) == "  ST\n  NC\n  VA\n"
    # text in a matrix or a vector
    @test Logjam.prt(Any["a" 1.5; "b" 2.5]; str = true) == "   1     2\n1  a  1.50\n2  b  2.50\n"
    @test occursin("b", Logjam.prt(["a", "b"]; str = true))
end

@testset "prt prints a Bool as true or false (S13)" begin
    # 3.3 Code block 13: minTLC's isLTL column
    @test Logjam.prt(DataFrame(x = [1.5, 2.25], isLTL = [true, false]); str = true) ==
          "      x  isLTL\n1  1.50   true\n2  2.25  false\n"
    @test Logjam.prt(DataFrame(s = ["a", "b"], f = [true, false]); str = true) == "  s      f\n  a   true\n  b  false\n"
    @test Logjam.prt([true false; false true]; str = true) == "       1      2\n1   true  false\n2  false   true\n"
    @test Logjam.prt([true, false, true]; str = true) == "        \n1   true\n2  false\n3   true\n"
    # a Bool takes no part in digit detection: the other column's digits are its own
    @test Logjam.prt(DataFrame(x = [3.14159, 2.0], b = [true, false]); str = true) ==
          "      x      b\n1  3.14   true\n2  2.00  false\n"
end

@testset "prt keyword parity across the three methods" begin
    df = DataFrame(site = ["a", "b"], v = [1.23456, 2.5], p = [0.123456, 0.5])
    dn = DataFrame(a = [1.5, 2.5], b = [10, 20])
    # fracdig and allfrac reach the mixed-frame path, which hard-coded 2 and 4
    @test Logjam.prt(df; str = true) == "  site     v       p\n     a  1.23  0.1235\n     b  2.50  0.5000\n"
    @test Logjam.prt(df; fracdig = 2, allfrac = 4, str = true) == Logjam.prt(df; str = true)
    @test Logjam.prt(df; fracdig = 3, allfrac = 5, str = true) ==
          "  site      v        p\n     a  1.235  0.12346\n     b  2.500  0.50000\n"
    @test Logjam.prt(df; fracdig = 6, allfrac = 6, str = true) ==
          "  site         v         p\n     a  1.234560  0.123456\n     b  2.500000  0.500000\n"
    @test Logjam.prt(dn; fracdig = 3, str = true) == "       a   b\n1  1.500  10\n2  2.500  20\n"
    # an all-numeric frame is numbered, a frame with text is not; rows and row_title apply to either
    @test Logjam.prt(dn; str = true) == "      a   b\n1  1.50  10\n2  2.50  20\n"
    @test Logjam.prt(dn; rows = ["u", "v"], row_title = "r", str = true) == "r     a   b\nu  1.50  10\nv  2.50  20\n"
    @test Logjam.prt(df; rows = ["u", "v"], row_title = "r", str = true) ==
          "r  site     v       p\nu     a  1.23  0.1235\nv     b  2.50  0.5000\n"
    @test Logjam.prt(dn; title = "T", str = true) == "T\n" * Logjam.prt(dn; str = true)
    # the vector method takes fracdig and allfrac
    @test Logjam.prt([1.23456, 2.5]; fracdig = 3, str = true) == "        \n1  1.235\n2  2.500\n"
    @test Logjam.prt([0.123456, 0.5]; allfrac = 5, str = true) == "          \n1  0.12346\n2  0.50000\n"
    # every call form the course uses keeps working (the pinned corpus holds the exact output)
    @test Logjam.prt([1.0, 2.0]; rows = ["a", "b"], row_title = "r", title = "t", str = true) isa String
    @test Logjam.prt([1 2; 3 4]; rows = ["a", "b"], cols = ["X", "Y"], row_title = "ID", title = "t", fracdig = 3, allfrac = 5, str = true) isa String
end

@testset "thousands: the one thousands-and-money formatter (CR 8)" begin
    # the amounts the lectures rendered wrongly, in one form (S12): 2 places, separators on the whole part
    @test thousands(1357.2; digits = 2) == "1,357.20"          # 3.2 "$1357.2", 4.3 "$1,357.2"
    @test thousands(57.4; digits = 2) == "57.40"               # 3.2 "$57.4"
    @test thousands(600.8; digits = 2) == "600.80"             # 3.2 "$600.8"
    @test thousands(64580.9; digits = 2) == "64,580.90"        # 4.4 "$64,580.9"
    @test thousands(184.2; digits = 2) == "184.20"             # 4.4 "$184.2"
    @test thousands(30.0; digits = 2) == "30.00"               # 4.4 "$30.0"
    @test thousands(10529.75; digits = 2) == "10,529.75"       # 6.3 "$10529.75"
    @test thousands(1124) == "1,124"                           # 2.5 "$1124"
    @test thousands(114620) == "114,620"                       # 2.5 "$114620"
    @test thousands(1124.0) == "1,124"
    @test thousands(4441.7314; digits = 2) == "4,441.73"       # 3.3's own comment
    @test thousands(300000000) == "300,000,000"                # 1.1's commafmt comment
    @test thousands(1357.24; digits = 1) == "1,357.2"          # 4.1's commas(round(x, digits = 1))
    @test thousands(5; digits = 2) == "5.00"
    @test thousands(0; digits = 2) == "0.00"
    @test thousands(999) == "999" && thousands(1000) == "1,000" && thousands(1234567890) == "1,234,567,890"
    # the group separator on the whole part only, and "{,}" for math mode (1.1's mnum)
    @test thousands(1234567; sep = "{,}") == "1{,}234{,}567"
    @test thousands(1234567.891; digits = 2, sep = "{,}") == "1{,}234{,}567.89"
    @test thousands(0.123456; digits = 5) == "0.12346"
    # a correct sign
    @test thousands(-1234.5; digits = 2) == "-1,234.50"
    @test thousands(-0.5; digits = 2) == "-0.50"
    @test thousands(-1234567) == "-1,234,567"
    @test thousands(-999999.999; digits = 2) == "-1,000,000.00"
    @test thousands(-0.001; digits = 2) == "0.00"              # never a negative zero
    @test thousands(-0.0) == "0"
    @test thousands(-64580.949; digits = 1) == "-64,580.9"
    # a rounding carry
    @test thousands(999.996; digits = 2) == "1,000.00"
    @test thousands(1999.996; digits = 2) == "2,000.00"
    @test thousands(0.9996; digits = 3) == "1.000"
    # a huge value prints its own digits
    @test thousands(BigInt(10)^30) == "1,000,000,000,000,000,000,000,000,000,000"
    @test thousands(1e300; digits = 2) == Logjam._commasep(BigInt(1e300)) * ".00"
    @test thousands(typemax(Int64)) == "9,223,372,036,854,775,807"
    @test thousands(typemin(Int64)) == "-9,223,372,036,854,775,808"
    @test thousands(1e15 + 0.5; digits = 1) == "1,000,000,000,000,000.5"       # past 2^50 / 10^digits the digits are exact
    @test thousands(1e15 + 0.125; digits = 2) == "1,000,000,000,000,000.12"
    @test thousands(2.0^60 + 256; digits = 3) == "1,152,921,504,606,847,232.000"
    @test !occursin('e', thousands(1.5e-7; digits = 9))
    @test thousands(1.5e-7; digits = 9) == "0.000000150"
    # other number types, and what is not a number
    @test thousands(Float32(1234.5); digits = 2) == "1,234.50"
    @test thousands(12345 // 10; digits = 1) == "1,234.5"
    @test thousands(big"1234567.5"; digits = 1) == "1,234,567.5"
    @test thousands(NaN) == "NaN" && thousands(Inf) == "Inf" && thousands(-Inf; digits = 2) == "-Inf"
    @test_throws ArgumentError thousands(1.5; digits = -1)
    @test_throws MethodError thousands("1234")
    # prt prints the same digits (one formatting core)
    @test occursin(thousands(1234567.891; digits = 2), Logjam.prt([1234567.891 0.5; 2.5 0.25]; str = true))
    # exported, and its name collides with nothing the course defines: a script that does `using Logjam`
    # and then defines its own function of the name still runs
    @test :thousands in names(Logjam)
    m = Module(:ThousandsCollide)
    Core.eval(m, :(using Logjam))
    Core.eval(m, :(thousands(x) = string("local:", x)))
    @test Core.eval(m, :(thousands(1234))) == "local:1234"
    # and in the unfavorable order: the exported name called first, a local definition after it
    m2 = Module(:ThousandsCollide2)
    Core.eval(m2, :(using Logjam))
    @test Core.eval(m2, :(thousands(1234))) == "1,234"
    Core.eval(m2, :(thousands(x) = string("local:", x)))
    @test Core.eval(m2, :(thousands(1234))) == "local:1234"
end

@testset "P8: mat2df is removed" begin
    @test !isdefined(Logjam, :mat2df)
    @test !(:mat2df in names(Logjam))
    # what replaces it: the DataFrame constructor, and insertcols! for the row labels
    @test DataFrame([1 2; 3 4], Symbol.(["A", "B"])) == DataFrame(A = [1, 3], B = [2, 4])
    @test insertcols!(DataFrame([1 2; 3 4], [:A, :B]), 1, :ID => ["r1", "r2"]) ==
          DataFrame(ID = ["r1", "r2"], A = [1, 3], B = [2, 4])
end

@testset "P8: snapvals(x, n, m) is removed; snapvals(x; atol) stays" begin
    @test_throws MethodError snapvals([1.0, 2.0, 3.0, 4.0], 2, 2)
    @test reshape(snapvals([1.0, 2.0, 3.0, 4.0]), 2, 2) == [1.0 3.0; 2.0 4.0]
    @test snapvals([2.9999999997, 1e-12, 0.5]) == [3.0, 0.0, 0.5]
    @test snapvals([2.9999, 1e-12]; atol = 1e-3) == [3.0, 0.0]
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
