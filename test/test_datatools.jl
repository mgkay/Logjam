using Test
include("../src/DataTools.jl")
using .DataTools
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
