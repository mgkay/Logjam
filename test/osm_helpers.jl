# osm_helpers.jl -- top-level helpers of test/test_osm.jl,
# moved here verbatim in PCV WP8 (Logjam v0.3.1): the tests that share them now sit in more than one file, one
# per source file, and each includes this file once, guarded by a name it defines, so that every helper is
# defined once.

const _OSM_EXT = Base.get_extension(Logjam, :LogjamOSMExt)
const _OSM_FIXTURE = joinpath(@__DIR__, "data", "osm_fixture.osm")
const _OSM_FIXTURE_TEXT = read(_OSM_FIXTURE, String)

# the fixture, translated the way osm_roads translates a download
function _fixture_tables()
    N, L, _ = Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
        _OSM_EXT._osm_tables_from_xml(_OSM_FIXTURE_TEXT)
    end
    return N, L
end
_quiet(f) = Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())
isdefined(@__MODULE__, :_attempt) || include(joinpath(@__DIR__, "common_helpers.jl"))

# the fixture's tables as a saved tile pair for the box `flat`, in a fresh folder
function _save_pair(dir, flat, dfN, dfL)
    np, lp = Logjam._osm_cache_path(flat, dir)
    CSV.write(np, dfN)
    CSV.write(lp, dfL)
    return np, lp
end

# ---- the OSM extension with a stand-in for the Overpass server (no network) --------------------------------
# an Overpass-like answer: the fixture's ways, with the <meta> line the real server puts first
const _OSM_BODY = replace(_OSM_FIXTURE_TEXT,
    "<osm version=\"0.6\" generator=\"logjam-test-fixture\">" =>
    "<osm version=\"0.6\" generator=\"Overpass API\">\n  <meta osm_base=\"2026-10-12T16:31:21Z\"/>")
_ok(body = _OSM_BODY) = (status = 200, body = body)

# run `f(queries, waits)` with the extension's request and clock replaced: `replies` is what the server
# answers to the first, second, ... request (the last repeats), `queries` the requests it was sent, `waits`
# the pauses asked for
function _with_overpass(f, replies)
    queries, waits, k = String[], Float64[], Ref(0)
    old = (_OSM_EXT._post_impl[], _OSM_EXT._sleep_impl[])
    _OSM_EXT._post_impl[] = q -> (push!(queries, q); k[] += 1; replies[min(k[], length(replies))])
    _OSM_EXT._sleep_impl[] = s -> push!(waits, s)
    try
        return f(queries, waits)
    finally
        _OSM_EXT._post_impl[], _OSM_EXT._sleep_impl[] = old
    end
end

# ---- the translation of a response: posted speeds, roads closed to cars, unknown classes, connectivity --------
# an OSM extract made by the test: `nodes` are (id, lon, lat), `ways` are (id, [node ids], [tag => value, ...])
function _osm_xml(nodes, ways)
    esc(s) = replace(s, "&" => "&amp;", "\"" => "&quot;", "<" => "&lt;", ">" => "&gt;")
    io = IOBuffer()
    println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    println(io, "<osm version=\"0.6\" generator=\"test\">")
    for (id, lon, lat) in nodes
        println(io, "  <node id=\"$id\" lat=\"$lat\" lon=\"$lon\"/>")
    end
    for (id, refs, tags) in ways
        println(io, "  <way id=\"$id\">")
        foreach(r -> println(io, "    <nd ref=\"$r\"/>"), refs)
        for (k, v) in tags
            println(io, "    <tag k=\"$k\" v=\"$(esc(v))\"/>")
        end
        println(io, "  </way>")
    end
    println(io, "</osm>")
    return String(take!(io))
end
_syn_nodes = [(k, -78.6 + 0.001k, 35.7 + 0.001k) for k in 1:8]
_syn_ways = [
    (11, [1, 2], ["highway" => "residential", "name" => "A & B St", "maxspeed" => "50"]),            # 50 km/h
    (12, [2, 3], ["highway" => "tertiary", "name" => "Tert Ave", "maxspeed" => "25 mph",
                  "motorcar" => "yes", "access" => "no"]),                                           # motorcar beats access
    (13, [3, 4], ["highway" => "secondary", "name" => "Sec Blvd", "maxspeed" => "none",
                  "vehicle:conditional" => "no @ (Mo-Fr 07:00-09:00)"]),                              # a conditional rule
    (14, [4, 1], ["highway" => "unclassified", "name" => "Unc Rd", "maxspeed" => "30 mph",
                  "motor_vehicle" => "destination"]),
    (15, [1, 5], ["highway" => "residential", "name" => "Stub St", "oneway" => "yes"]),               # a way in, none out
    (16, [2, 6], ["highway" => "residential", "name" => "Gate St", "vehicle" => "no", "bus" => "yes"]),  # closed to cars
    (17, [3, 7], ["highway" => "residential", "name" => "Farm Rd", "access" => "agricultural"]),        # closed to cars
    (18, [4, 8], ["highway" => "crossing", "name" => "Cross Way"]),                                    # not a road class
]
