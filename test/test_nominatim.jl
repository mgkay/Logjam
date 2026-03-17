# =============================================================================
# Tests for LogjamNominatimExt — Nominatim geocoding (requires network)
# =============================================================================

@testset "Nominatim Extension" begin

    # Use a temporary directory for cache tests
    cache_dir = mktempdir()

    # ── TN1: Known address geocode ───────────────────────────────────────
    @testset "TN1: Known address" begin
        r = loc2lonlat("2401 Westgate Dr, Durham, NC 27705"; cache_dir=cache_dir)
        @test r.status == "OK"
        @test r.source == "ADDRESS"
        @test !ismissing(r.lon)
        @test !ismissing(r.lat)
        # Durham, NC area: lon ≈ -79.0, lat ≈ 36.0
        @test -80.0 < r.lon < -78.0
        @test 35.0 < r.lat < 37.0
        @test r.uncert ≈ 0.0
    end

    # ── TN2: Rate limiting ───────────────────────────────────────────────
    @testset "TN2: Rate limiting" begin
        t0 = time()
        loc2lonlat("100 Main St, Raleigh, NC"; cache_dir=cache_dir, force_download=true)
        loc2lonlat("200 Main St, Raleigh, NC"; cache_dir=cache_dir, force_download=true)
        loc2lonlat("300 Main St, Raleigh, NC"; cache_dir=cache_dir, force_download=true)
        elapsed = time() - t0
        @test elapsed >= 2.0  # At least 2 seconds for 3 requests
    end

    # ── TN3: Cache persistence ───────────────────────────────────────────
    @testset "TN3: Cache" begin
        cache_dir2 = mktempdir()
        # First call — should hit API
        r1 = loc2lonlat("500 Fayetteville St, Raleigh, NC 27601"; cache_dir=cache_dir2)
        @test isfile(joinpath(cache_dir2, "geocode_cache.csv"))
        # Second call — should load from cache (much faster)
        t0 = time()
        r2 = loc2lonlat("500 Fayetteville St, Raleigh, NC 27601"; cache_dir=cache_dir2)
        elapsed = time() - t0
        @test elapsed < 1.0  # Should be near-instant from cache
        @test r1.lon == r2.lon
        @test r1.lat == r2.lat
    end

    # ── TN4: Failed address fallback ─────────────────────────────────────
    @testset "TN4: Fallback" begin
        df = DataFrame(
            STREET=["99999 Nonexistent Blvd"],
            CITY=["Raleigh"],
            STATE=["NC"]
        )
        result = loc2lonlat(df; cache_dir=cache_dir)
        @test result.GC_STATUS[1] in ["OK", "PARTIAL"]
        # Should fall back to place lookup
        if result.GC_SOURCE[1] == "PLACE"
            @test result.GC_STATUS[1] == "PARTIAL"
        end
    end

    # ── TN6: Batch with progress ─────────────────────────────────────────
    @testset "TN6: Batch" begin
        addrs = ["$(i)00 Main St, Raleigh, NC 27601" for i in 1:5]
        result = loc2lonlat(addrs; cache_dir=cache_dir)
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
