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
    @test all(issubset(names(df), ["STFIP", "COFIP", "NAME", "ST", "LAT", "LON", "POP", "ALAND", "AWATER", "CBSA"]))
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
    @test all(issubset(names(df), ["STFIP", "COFIP", "TRFIP", "BGFIP", "LAT", "LON", "POP", "ALAND", "AWATER"]))
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
    @test all(issubset(names(df), ["CBSA", "NAME", "LAT", "LON", "POP", "ALAND", "AWATER", "M_MSA", "CSA", "ISCUS"]))
end

# Test for uscsa function
@testset "uscsa function tests" begin
    df = uscsa()
    @test isa(df, DataFrame)
    @test !isempty(df)
    @test all(issubset(names(df), ["CSA", "NAME", "LAT", "LON", "POP", "ALAND", "AWATER"]))
end

# Test for st2fips function
@testset "st2fips function tests" begin
    @test st2fips(:NC) == 37
    @test st2fips(:NY) == 36
    @test_throws ArgumentError st2fips(:XX)
end

# Test for fips2st function
@testset "fips2st function tests" begin
    @test fips2st(37) == :NC
    @test fips2st(36) == :NY
    @test fips2st(72) == :PR
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

@testset "faf5interstate function tests" begin
    x, y = faf5interstate()
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
    @test r.status == "OK"
    @test -79.5 < r.lon < -78.0   # LON range for Raleigh
    @test 35.5 < r.lat < 36.0     # LAT range for Raleigh

    # Not found
    r2 = loc2lonlat("Nonexistent City XYZ", state=:NC)
    @test r2.status == "FAIL"
end

# Test for lonlat2loc function (replaces lonlat2name)
@testset "lonlat2loc basic tests" begin
    cities = usplace()

    # --- Schema test: all expected columns present ---
    xy = [-78.6382 35.7796]  # near Raleigh, NC
    result = lonlat2loc(xy, cities)
    @test isa(result, DataFrame)
    @test nrow(result) == 1
    for col in ["idx", "name", "st", "dist", "bearing", "dir", "desc"]
        @test col in names(result)
    end

    # --- In-city threshold behavior ---
    @test startswith(result.desc[1], "in ")
    @test result.name[1] == "Raleigh"
    @test result.st[1] == "NC"

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
    @test res_vec.name == result.name[1]

    # --- Multi-row matrix input ---
    xy_multi = [-78.6382 35.7796; -80.8431 35.2271]  # Raleigh, Charlotte
    res_multi = lonlat2loc(xy_multi, cities)
    @test nrow(res_multi) == 2
    @test res_multi.name[1] == "Raleigh"
    @test res_multi.name[2] == "Charlotte"

    # --- Invalid input ---
    @test_throws ArgumentError lonlat2loc([1.0, 2.0, 3.0], cities)
end

# ─── H1: mat2df ───────────────────────────────────────────────────
@testset "mat2df" begin
    @testset "basic conversion" begin
        df = mat2df([1 2; 3 4], ["A", "B"])
        @test isa(df, DataFrame)
        @test names(df) == ["A", "B"]
        @test df.A == [1, 3]
        @test df.B == [2, 4]
    end

    @testset "with row labels" begin
        df = mat2df([1 2; 3 4], ["A", "B"]; rows=["r1", "r2"])
        @test names(df) == ["", "A", "B"]
        @test df[!, ""] == ["r1", "r2"]
    end

    @testset "single-element matrix" begin
        df = mat2df(reshape([42], 1, 1), ["X"])
        @test size(df) == (1, 1)
        @test df.X[1] == 42
    end

    @testset "mismatched cols" begin
        @test_throws ArgumentError mat2df([1 2; 3 4], ["A"])
    end

    @testset "mismatched rows" begin
        @test_throws ArgumentError mat2df([1 2; 3 4], ["A", "B"]; rows=["r1"])
    end
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

    @testset "reshape method" begin
        result = snapvals([1.0, 2.0, 3.0, 4.0], 2, 2)
        @test size(result) == (2, 2)
        @test result == [1.0 3.0; 2.0 4.0]
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


# ─── Relocated: isptinbbox (from maptools) ────────────────────────
@testset "isptinbbox relocated" begin
    bbox = ((-180, 180), (-90, 90))
    @test isptinbbox((0, 0), bbox) == true
    @test isptinbbox((200, 100), bbox) == false
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
