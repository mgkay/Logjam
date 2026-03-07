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

# Test for name2lonlat function
@testset "name2lonlat function tests" begin
    cities = usplace()

    # Basic lookup with state filter
    xy = name2lonlat("Raleigh", cities; st="NC")
    @test length(xy) == 2
    @test -79.5 < xy[1] < -78.0   # LON range for Raleigh
    @test 35.5 < xy[2] < 36.0     # LAT range for Raleigh

    # "City, ST" format parsing
    xy2 = name2lonlat("Raleigh, NC", cities)
    @test xy == xy2

    # Not found
    @test_throws ErrorException name2lonlat("Nonexistent City XYZ", cities)
end

# Test for lonlat2name function
@testset "lonlat2name function tests" begin
    cities = usplace()

    # --- Schema test: all expected columns present ---
    xy = [-78.6382 35.7796]  # near Raleigh, NC
    result = lonlat2name(xy, cities)
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
    res_east = lonlat2name(xy_east, big)
    # Should not be "in" city (beyond threshold)
    @test occursin(" mi ", res_east.desc[1])
    @test occursin(" of ", res_east.desc[1])

    # --- Vector input (single [LON, LAT]) ---
    res_vec = lonlat2name([-78.6382, 35.7796], cities)
    @test nrow(res_vec) == 1
    @test res_vec.name[1] == result.name[1]

    # --- Multi-row matrix input ---
    xy_multi = [-78.6382 35.7796; -80.8431 35.2271]  # Raleigh, Charlotte
    res_multi = lonlat2name(xy_multi, cities)
    @test nrow(res_multi) == 2
    @test res_multi.name[1] == "Raleigh"
    @test res_multi.name[2] == "Charlotte"

    # --- Invalid input ---
    @test_throws ArgumentError lonlat2name([1.0, 2.0, 3.0], cities)
end
