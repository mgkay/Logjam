# Packaging / exports / extension-isolation tests (C4, test spec P1/P2)

@testset "Packaging" begin
    # ── P1: new location/distance functions are exported ──
    exported = names(Logjam)
    @test :ala in exported
    @test :dgca in exported
    @test :wcentroid in exported

    # ── P2: extension isolation — no stray [deps] promotion; extensions resolve ──
    projfile = joinpath(pkgdir(Logjam), "Project.toml")
    @test isfile(projfile)

    # Dependency-free scan of Project.toml section membership.
    function _section_names(path, section)
        found = String[]
        cur = ""
        for line in eachline(path)
            s = strip(line)
            if startswith(s, "[") && endswith(s, "]")
                cur = s
            elseif cur == "[$section]" && occursin(" = ", s)
                push!(found, strip(split(s, " = ")[1]))
            end
        end
        return Set(found)
    end

    deps     = _section_names(projfile, "deps")
    weakdeps = _section_names(projfile, "weakdeps")
    @test !isempty(weakdeps)
    # A weakdep silently promoted to [deps] would break extension isolation.
    @test isempty(intersect(deps, weakdeps))

    # The map extension (triggered by GeoMakie alone, C5; CairoMakie and GeoMakie are loaded in runtests) must
    # activate on the resolved test environment — proves Pkg.test resolves the weakdeps — and CairoMakie, a weakdep
    # that triggers nothing, is still declared, so that its compat cap keeps binding a course environment (K10).
    @test Base.get_extension(Logjam, :LogjamMapExt) !== nothing
    @test Base.get_extension(Logjam, :LogjamCairoMakieExt) === nothing
    @test "CairoMakie" in weakdeps

    # ── P3: the Nominatim extension loads (HTTP + JSON3 are in the test target) ──
    # Loaded here, after test_geocode.jl, because with it loaded an address-tier lookup
    # queries the network; the offline geocoding tests must run without it. No query is
    # sent here: this checks only that the extension precompiles and registers itself.
    @eval Main using HTTP, JSON3
    @test Base.get_extension(Logjam, :LogjamNominatimExt) !== nothing
    @test Logjam._nominatim_available[]

    # ── P4: the extension passes the match's house number (CR 26), checked on canned responses ──
    ext = Base.get_extension(Logjam, :LogjamNominatimExt)
    house = """[{"lon":"-78.6758457","lat":"35.7706306","display_name":"Fitts-Woolard Hall, 915, Partners Way, Raleigh","importance":0.31,"address":{"building":"Fitts-Woolard Hall","house_number":"915","road":"Partners Way"}}]"""
    road  = """[{"lon":"-78.6997617","lat":"35.7957255","display_name":"Hillsborough Street, Raleigh, Wake County","importance":0.4,"address":{"road":"Hillsborough Street","city":"Raleigh"}}]"""
    for body in (house, Vector{UInt8}(codeunits(house)))
        m = ext._parse_response(body)
        @test (m.lon, m.lat, m.house_number) == (-78.6758457, 35.7706306, "915")
        @test m.display_name == "Fitts-Woolard Hall, 915, Partners Way, Raleigh" && m.importance == 0.31
    end
    m = ext._parse_response(road)
    @test m.house_number == "" && m.lon == -78.6997617
    @test ext._parse_response("[]") === missing
    @test ext._parse_response("""[{"lon":"-78.6","lat":"35.8"}]""").house_number == ""   # no address block at all
    # the whole path, through loc2lonlat, from the response body to STREET/PARTIAL and ADDRESS/OK
    saved = Logjam._nominatim_geocode[]
    try
        Logjam._nominatim_geocode[] = (args...; kwargs...) -> ext._parse_response(road)
        r = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            loc2lonlat("9999 Hillsborough St, Raleigh, NC 27607")
        end
        @test (r.GC_SOURCE, r.GC_STATUS) == ("STREET", "PARTIAL")
        Logjam._nominatim_geocode[] = (args...; kwargs...) -> ext._parse_response(house)
        r = loc2lonlat("915 Partners Way, Raleigh, NC 27606")
        @test (r.GC_SOURCE, r.GC_STATUS, r.GC_UNCERT) == ("ADDRESS", "OK", 0.0)
    finally
        Logjam._nominatim_geocode[] = saved
    end
end
