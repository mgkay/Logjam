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
        @test r.status == "OK"
        @test r.source == "PLACE"
        @test r.lon ≈ cities[findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities)), :LON]
        @test r.lat ≈ cities[findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities)), :LAT]
        # Verify uncertainty
        idx = findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities))
        @test r.uncert ≈ 0.45 * sqrt(cities[idx, :ALAND])
    end

    # ── T2: Place lookup — case insensitive ──────────────────────────────
    @testset "T2: Case insensitive" begin
        r1 = loc2lonlat("Raleigh", state=:NC)
        r2 = loc2lonlat("raleigh", state=:NC)
        r3 = loc2lonlat("RALEIGH", state=:NC)
        @test r1.lon == r2.lon == r3.lon
        @test r1.lat == r2.lat == r3.lat
    end

    # ── T3: Partial prefix match ─────────────────────────────────────────
    @testset "T3: Partial prefix" begin
        r = loc2lonlat("ral", state=:NC)
        @test r.status == "OK"
        @test r.source == "PLACE"
        # Should resolve to Raleigh (unique prefix starting with "ral" in NC)
        r_full = loc2lonlat("Raleigh", state=:NC)
        @test r.lon == r_full.lon
    end

    # ── T4: Ambiguous partial match ──────────────────────────────────────
    @testset "T4: Ambiguous partial" begin
        # "spring" matches Springfield, Spring Hill, etc. across many states
        r = loc2lonlat("spring")
        @test r.status == "FAIL"
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
            @test r.status == "OK"
            @test r.lon ≈ cities[cdp_idx, :LON]
        end
    end

    # ── T6: Postal code lookup ───────────────────────────────────────────
    @testset "T6: Postal code" begin
        r = loc2lonlat("27601")
        @test r.status == "OK"
        @test r.source == "POSTALCODE"
        idx = findfirst(==(27601), zips.ZCTA5)
        if !isnothing(idx)
            @test r.lon ≈ zips[idx, :LON]
            @test r.lat ≈ zips[idx, :LAT]
            @test r.uncert ≈ 0.45 * sqrt(zips[idx, :ALAND])
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
        r = loc2lonlat("xyzzyplugh", state=:NC)
        @test r.status == "FAIL"
        @test ismissing(r.lon)
        @test ismissing(r.lat)
    end

    # ── T13: Uncertainty formula ─────────────────────────────────────────
    @testset "T13: Uncertainty formula" begin
        # Place tier
        r = loc2lonlat("Raleigh", state=:NC)
        idx = findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities))
        @test r.uncert ≈ 0.45 * sqrt(cities[idx, :ALAND])

        # Postal code tier
        r = loc2lonlat("27601")
        idx = findfirst(==(27601), zips.ZCTA5)
        @test r.uncert ≈ 0.45 * sqrt(zips[idx, :ALAND])
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
        @test hasproperty(r, :status)
        @test r.status isa AbstractString
        @test r.status in ["OK", "PARTIAL", "FAIL"]

        # Direct check of the fixed helper: state === nothing behaves like missing.
        pp = Logjam._preprocess_address("123 Main St", "Raleigh", nothing, nothing)
        @test pp.state == ""
        @test pp.street == "123 Main St"
        @test pp.city == "Raleigh"
    end

    # ── E2: State as full name ───────────────────────────────────────────
    @testset "E2: State full name" begin
        r = loc2lonlat("Raleigh", state="North Carolina")
        @test r.status == "OK"
        @test r.source == "PLACE"
        r2 = loc2lonlat("Raleigh", state=:NC)
        @test r.lon == r2.lon
    end

    # ── E3: Country parameter ────────────────────────────────────────────
    @testset "E3: Country parameter" begin
        r = loc2lonlat("Raleigh", state=:NC, country=:US)
        @test r.status == "OK"
    end

    # ── lonlat2loc scalar pair method ──────────────────────────────────
    @testset "lonlat2loc scalar pair" begin
        idx = findfirst(row -> row.NAME == "Raleigh" && row.ST == :NC, eachrow(cities))
        lon, lat = cities[idx, :LON], cities[idx, :LAT]
        r = lonlat2loc(lon, lat, cities)
        @test occursin("in Raleigh", r.desc)
        # Should match vector method
        r2 = lonlat2loc([lon, lat], cities)
        @test r.name == r2.name
        @test r.dist == r2.dist
    end

    # ── lonlat2loc vector pair method ────────────────────────────────
    @testset "lonlat2loc vector pair" begin
        x = [-78.6382, -80.8431]
        y = [35.7796, 35.2271]
        result = lonlat2loc(x, y, cities)
        @test result isa DataFrame
        @test nrow(result) == 2
        @test result.name[1] == "Raleigh"
        @test result.name[2] == "Charlotte"
        # Should match matrix method
        result2 = lonlat2loc(hcat(x, y), cities)
        @test result.name == result2.name
        @test result.dist == result2.dist
    end

    # ── lonlat2loc vector pair length mismatch ───────────────────────
    @testset "lonlat2loc vector pair mismatch" begin
        @test_throws ArgumentError lonlat2loc([1.0, 2.0], [3.0], cities)
    end

    # ── lonlat2loc DataFrame method ──────────────────────────────────────
    @testset "lonlat2loc DataFrame" begin
        df_in = DataFrame(LON=[-78.6382, -80.8431], LAT=[35.7796, 35.2271])
        result = lonlat2loc(df_in, cities)
        @test hasproperty(result, :GC_DESC)
        @test hasproperty(result, :GC_NAME)
        @test nrow(result) == 2
    end

end
