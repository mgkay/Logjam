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
