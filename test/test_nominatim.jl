# =============================================================================
# Tests for LogjamNominatimExt — Nominatim geocoding (requires network)
# =============================================================================
using HTTP, JSON3   # trigger packages of LogjamNominatimExt (in the test target)
using DataFrames

@testset "Nominatim Extension" begin

    # A cache file in a temporary directory (cache = nothing would keep none)
    cache_file = joinpath(mktempdir(), "geocode_cache.csv")

    # ── TN1: Known address geocode ───────────────────────────────────────
    # An address whose house number OpenStreetMap carries comes back exact (ADDRESS, OK, uncertainty 0);
    # one whose number it lacks comes back as its street (STREET, PARTIAL, no uncertainty), never as the
    # address (CR 26). 2401 Westgate Dr, Durham, TN1's address before v0.3.0, is the second kind:
    # Nominatim matches Westgate Drive with no house number (checked 2026-11-21), so it is TN1b.
    @testset "TN1: Known address" begin
        r = loc2lonlat("500 Fayetteville St, Raleigh, NC 27601"; cache=cache_file)
        @test r.GC_STATUS == "OK"
        @test r.GC_SOURCE == "ADDRESS"
        @test !ismissing(r.LON)
        @test !ismissing(r.LAT)
        # downtown Raleigh: lon ≈ -78.64, lat ≈ 35.77
        @test -79.0 < r.LON < -78.3
        @test 35.5 < r.LAT < 36.0
        @test r.GC_UNCERT ≈ 0.0
    end

    @testset "TN1b: a house number OSM lacks gives the street, not the address (CR 26)" begin
        r = loc2lonlat("2401 Westgate Dr, Durham, NC 27705"; cache=cache_file)
        @test -80.0 < r.LON < -78.0
        @test 35.0 < r.LAT < 37.0
        if r.GC_SOURCE == "ADDRESS"   # OSM has since added the number
            @test r.GC_STATUS == "OK" && r.GC_UNCERT ≈ 0.0
        else
            @test r.GC_SOURCE == "STREET" && r.GC_STATUS == "PARTIAL" && ismissing(r.GC_UNCERT)
        end
    end

    # ── TN2: Rate limiting ───────────────────────────────────────────────
    @testset "TN2: Rate limiting" begin
        t0 = time()
        loc2lonlat("100 Main St, Raleigh, NC"; cache=cache_file, force_download=true)
        loc2lonlat("200 Main St, Raleigh, NC"; cache=cache_file, force_download=true)
        loc2lonlat("300 Main St, Raleigh, NC"; cache=cache_file, force_download=true)
        elapsed = time() - t0
        @test elapsed >= 2.0  # At least 2 seconds for 3 requests
    end

    # ── TN3: Cache persistence ───────────────────────────────────────────
    @testset "TN3: Cache" begin
        cache_file2 = joinpath(mktempdir(), "geocode_cache.csv")
        # First call — should hit API
        r1 = loc2lonlat("500 Fayetteville St, Raleigh, NC 27601"; cache=cache_file2)
        @test isfile(cache_file2)
        # Second call — should load from cache (much faster)
        t0 = time()
        r2 = loc2lonlat("500 Fayetteville St, Raleigh, NC 27601"; cache=cache_file2)
        elapsed = time() - t0
        @test elapsed < 1.0  # Should be near-instant from cache
        @test r1.LON == r2.LON
        @test r1.LAT == r2.LAT
    end

    # ── TN4: Failed address fallback ─────────────────────────────────────
    @testset "TN4: Fallback" begin
        df = DataFrame(
            STREET=["99999 Nonexistent Blvd"],
            CITY=["Raleigh"],
            STATE=["NC"]
        )
        result = loc2lonlat(df; cache=cache_file)
        @test result.GC_STATUS[1] in ["OK", "PARTIAL"]
        # Should fall back to place lookup
        if result.GC_SOURCE[1] == "PLACE"
            @test result.GC_STATUS[1] == "PARTIAL"
        end
    end

    # ── TN6: Batch with progress ─────────────────────────────────────────
    @testset "TN6: Batch" begin
        addrs = ["$(i)00 Main St, Raleigh, NC 27601" for i in 1:5]
        result = loc2lonlat(addrs; cache=cache_file)
        @test result isa DataFrame
        @test nrow(result) == 5
    end

    # ── TN7: Suite/unit stripped ─────────────────────────────────────────
    @testset "TN7: Unit stripped" begin
        parsed = Logjam._parse_address_string("123 Main St Suite 200, Raleigh, NC")
        @test !occursin("Suite", parsed.street)
        @test !occursin("suite", parsed.street)
    end

end
