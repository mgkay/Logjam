# =============================================================================
# Offline tests of osm_roads and its translation (no network): a small committed OpenStreetMap
# extract, test/data/osm_fixture.osm, translated by the extension's own `_osm_tables_from_xml`, which is the
# step `osm_roads` runs on an Overpass response, and a stand-in for the Overpass server (the extension's
# `_post_impl` and `_sleep_impl`). The networked tests are in test_osm_network.jl (LOGJAM_NETWORK_TESTS).
# Tagged [ID]; see tools/v0_3_0/run_against.jl. (K2a, test spec Sec. 2; K9.)
# =============================================================================
using Test
using LightOSM
using HTTP, JSON3
using Logjam
using DataFrames, CSV, Graphs

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
_attempt(f) = try f() catch; nothing end

@testset "OSM offline fixture" begin
    dfN, dfL = _fixture_tables()
    @test nrow(dfN) > 0 && nrow(dfL) > 0                    # control: the extract translates
    @test "Second St" in dfL.NAME                          # control: an ordinary street is there

    @testset "[CR 21] osm_roads uses a way's posted maxspeed" begin
        main = dfL[dfL.NAME .== "Main St", :]
        @test nrow(main) > 0
        # CR 21: v0.2.8 never read maxspeed: Main St (tertiary, posted 35 mph) got the class default 30; fixed in K9
        @test all(main.SPEED .== 35)
        @test all(dfL[dfL.NAME .== "Mid Ave", :SPEED] .== 30)  # control: no maxspeed, the class default
    end

    @testset "[CR 34] osm_roads drops roads closed to motor vehicles" begin
        # CR 34: LightOSM's :drive filter drops only motor_vehicle=no, motorcar=no and access=private, so a
        # way tagged vehicle=no (Gated Drive) or access=no (Closed Road) reached the network; fixed in K9
        closed = any(n -> n in ("Gated Drive", "Closed Road"), dfL.NAME)
        @test !closed
    end

    @testset "[CR 24] osm_roads output types are stable and an unknown class is handled" begin
        # a class not in the speed table (highway=crossing) is read as residential: FCLASS 7, SPEED 25
        cr = dfL[dfL.NAME .== "Crossing Way", :]
        # CR 24: v0.2.8 gave the unknown class the residential codes; handled = given its own code or skipped (skipped); fixed in K9
        @test !any(r -> r.FCLASS == 7 && r.SPEED == 25, eachrow(cr)) && nrow(cr) == 0
        # a fresh call and the cached CSVs read back must have the same column types
        mktempdir() do tmp
            bbox = (-78.641, -78.636, 35.779, 35.784)
            np, lp = Logjam._osm_cache_path(bbox, tmp)
            CSV.write(np, dfN)
            CSV.write(lp, dfL)
            cN, cL = _quiet(() -> osm_roads(bbox; cache_dir = tmp))
            @test nrow(cL) == nrow(dfL)                    # control: the cache was read
            # CR 24: v0.2.8's read-back had SOURCE::String3 (and NAME::Union{Missing,String} when a name is blank); fixed in K9
            @test eltype.(eachcol(cL)) == eltype.(eachcol(dfL)) &&
                  eltype.(eachcol(cN)) == eltype.(eachcol(dfN))
        end
    end

    @testset "[CR 23] osm_roads accepts mapbbox's box and the grid snap stays inside the requested box" begin
        mktempdir() do tmp
            flat = (-78.641, -78.636, 35.779, 35.784)
            np, lp = Logjam._osm_cache_path(flat, tmp)
            CSV.write(np, dfN)
            CSV.write(lp, dfL)
            bb = mapbbox([-78.641, -78.636], [35.779, 35.784])      # ((xmin, xmax), (ymin, ymax))
            got = _attempt(() -> _quiet(() -> osm_roads(bb; cache_dir = tmp)))
            # CR 23: v0.2.8 had no method for mapbbox's pair of tuples (MethodError); fixed in K9
            @test got !== nothing && nrow(got[2]) == nrow(dfL)
        end
        # a box whose edges lie on the 0.05 degree grid must not gain a cell: v0.2.8 turned xmax = -78.60 into -78.55
        onbox = (-78.70, -78.60, 35.70, 35.85)
        snapped = Logjam._osm_snap_bbox(onbox)
        # CR 23: floor/ceil in floating point; fixed in K9
        @test all(isapprox.(snapped, onbox; atol = 1e-9))
        # control: an off-grid box is widened outward, by less than one cell
        off = (-78.63, -78.57, 35.72, 35.83)
        sn = Logjam._osm_snap_bbox(off)
        @test sn[1] <= off[1] && sn[2] >= off[2] && sn[3] <= off[3] && sn[4] >= off[4]
        @test all(abs.(collect(sn) .- collect(off)) .< 0.05 + 1e-9)
    end
end

# the fixture's tables as a saved tile pair for the box `flat`, in a fresh folder
function _save_pair(dir, flat, dfN, dfL)
    np, lp = Logjam._osm_cache_path(flat, dir)
    CSV.write(np, dfN)
    CSV.write(lp, dfL)
    return np, lp
end

@testset "[CR 23] [CR 35] [C6] the box osm_roads takes, the crop, and the box methods" begin
    dfN, dfL = _fixture_tables()
    flat = (-78.641, -78.636, 35.779, 35.784)
    box = ((-78.641, -78.636), (35.779, 35.784))

    @testset "osm_roads takes mapbbox's box, and still the four numbers" begin
        mktempdir() do tmp
            _save_pair(tmp, flat, dfN, dfL)
            bb = mapbbox([-78.641, -78.636], [35.779, 35.784])
            @test bb == box
            a = _quiet(() -> osm_roads(bb; cache_dir = tmp))
            b = _quiet(() -> osm_roads(flat; cache_dir = tmp))
            @test nrow(a[2]) == nrow(dfL) && nrow(a[1]) == nrow(dfN)
            @test isequal(a[1], b[1]) && isequal(a[2], b[2])         # the same call either way
        end
    end

    @testset "crop = true is the box asked for, as 4.2 and a homework crop it by hand" begin
        mktempdir() do tmp
            _save_pair(tmp, flat, dfN, dfL)
            x, y = [-78.6396, -78.6384], [35.7803, 35.7817]            # points inside the fixture's tile
            bb = mapbbox(x, y; xexpand = 0.5, yexpand = 0.5)
            hand = cropnetwork(dfN, dfL, x, y; xexpand = 0.5, yexpand = 0.5)       # Lecture 4.2, Code block 2
            got = _quiet(() -> osm_roads(bb; cache_dir = tmp, crop = true))
            @test isequal(got[1], hand[1]) && isequal(got[2], hand[2])
            @test 0 < nrow(got[1]) < nrow(dfN)                                     # control: it cropped
            @test all(bb[1][1] .<= got[1].LON .<= bb[1][2]) && all(bb[2][1] .<= got[1].LAT .<= bb[2][2])
            whole = _quiet(() -> osm_roads(bb; cache_dir = tmp))                   # crop = false: the tile
            @test nrow(whole[1]) == nrow(dfN)
        end
    end

    @testset "cropnetwork(N, L, bb) and mapbbox(bb; xexpand, yexpand)" begin
        N = DataFrame(IDX = 1:4, LON = [0.0, 1.0, 2.0, 3.0], LAT = [0.0, 0.0, 0.0, 0.0])
        L = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [1.0, 1.0, 1.0])
        N2, L2 = cropnetwork(N, L, ((0.5, 2.5), (-1.0, 1.0)))
        @test (N2.LON, L2.SRC, L2.DST) == ([1.0, 2.0], [1], [2])
        # the box is the box: no expansion unless asked, and the asked expansion is mapbbox's
        N3, L3 = cropnetwork(N, L, ((1.0, 2.0), (-1.0, 1.0)); xexpand = 0.5)
        @test N3.LON == [1.0, 2.0] && nrow(L3) == 1
        N3, L3 = cropnetwork(N, L, ((1.0, 2.0), (-1.0, 1.0)); xexpand = 1.5)
        @test N3.LON == [0.0, 1.0, 2.0, 3.0] && nrow(L3) == 3
        @test cropnetwork(N, L, ((0.5, 2.5), (-1.0, 1.0))) == cropnetwork(N, L, [0.5, 2.5], [-1.0, 1.0]; xexpand = 0, yexpand = 0)
        # the column keywords stay
        Nr = rename(N, :IDX => :id, :LON => :x, :LAT => :y)
        Lr = rename(L, :SRC => :a, :DST => :b)
        N4, L4 = cropnetwork(Nr, Lr, ((0.5, 2.5), (-1.0, 1.0)))
        @test N4.x == [1.0, 2.0]
        @test mapbbox(((-80.0, -78.0), (35.0, 36.0)); xexpand = 0.5, yexpand = 0.25) == ((-81.0, -77.0), (34.75, 36.25))
        @test mapbbox(((-80.0, -78.0), (35.0, 36.0))) == ((-80.0, -78.0), (35.0, 36.0))
        x, y = [-78.6758, -78.6696], [35.7706, 35.7876]
        bb = mapbbox(x, y)
        @test mapbbox(bb; xexpand = 2, yexpand = 0.5) == mapbbox(x, y; xexpand = 2, yexpand = 0.5)   # 4.2's Code block 2
    end

    @testset "the grid snap keeps an edge on a grid line, and widens any other outward" begin
        for onbox in ((-78.70, -78.60, 35.70, 35.85), (-78.65, -78.55, 35.75, 35.80), (-79.0, -78.0, 35.0, 36.0))
            @test all(isapprox.(Logjam._osm_snap_bbox(onbox), onbox; atol = 1e-9))
        end
        @test all(isapprox.(Logjam._osm_snap_bbox((-78.60, -78.60, 35.75, 35.75)), (-78.6, -78.55, 35.75, 35.8); atol = 1e-9))  # a point is one tile
        @test Logjam._osm_snap_bbox(((-78.70, -78.60), (35.70, 35.85))) == Logjam._osm_snap_bbox((-78.70, -78.60, 35.70, 35.85))
        # an edge just off a line is widened to the next line, as before
        @test all(isapprox.(Logjam._osm_snap_bbox((-78.6999, -78.5999, 35.7001, 35.8499)), (-78.7, -78.55, 35.7, 35.85); atol = 1e-9))
        # Lecture 4.2's two boxes (Ex. 1: the two buildings, xexpand 2, yexpand 0.5) are off the grid and give the
        # tiles of the committed cache
        b1 = mapbbox([-78.6758457, -78.6695716], [35.7706306, 35.7875615]; xexpand = 2, yexpand = 0.5)
        @test all(isapprox.(Logjam._osm_snap_bbox(b1), (-78.7, -78.65, 35.75, 35.8); atol = 1e-9))
        @test basename(Logjam._osm_cache_path(b1, "data")[1]) == "osm_w-78.7_e-78.65_s35.75_n35.8_nodes.csv"
        @test basename(Logjam._osm_cache_path(b1, "data")[2]) == "osm_w-78.7_e-78.65_s35.75_n35.8_links.csv"
    end
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

@testset "[C3] [R9] [S18] a saved pair reads in core, silently, and nothing is written unless asked" begin
    dfN, dfL = _fixture_tables()
    flat = (-78.641, -78.636, 35.779, 35.784)
    bb = ((-78.641, -78.636), (35.779, 35.784))

    # Reading needs no LightOSM; the extension is loaded in this process, so what a miss says without it (a
    # MethodError of `_osm_download` that carries the hint "Run: using LightOSM") is tested in a fresh process, in
    # "[K10] the OSM extension loads on LightOSM alone" below.
    @testset "a saved pair is read, and nothing is downloaded" begin
        mktempdir() do tmp
            _save_pair(tmp, flat, dfN, dfL)
            _with_overpass([_ok()]) do queries, waits
                a = _quiet(() -> osm_roads(bb; cache_dir = tmp))
                @test nrow(a[1]) == nrow(dfN) && nrow(a[2]) == nrow(dfL)
                @test isempty(queries)
            end
        end
    end

    @testset "the default writes nothing; cache_dir is a folder, as the lectures pass it" begin
        mktempdir() do tmp
            cd(tmp) do
                _with_overpass([_ok()]) do queries, waits
                    a = _quiet(() -> osm_roads(bb))
                    @test length(queries) == 1 && nrow(a[1]) > 0
                    @test isempty(readdir(tmp))                                       # v0.2.8 wrote the pair here
                    _quiet(() -> osm_roads(bb))
                    @test length(queries) == 2                                        # and so no cache was read
                end
            end
        end
    end

    @testset "a call is silent unless verbose = true" begin
        mktempdir() do tmp
            _with_overpass([_ok()]) do queries, waits
                @test_logs osm_roads(bb; cache_dir = tmp)                             # a download
                @test_logs osm_roads(bb; cache_dir = tmp)                             # a read: 4.2 printed this twice
                @test_logs (:info, r"Loading cached OSM data") osm_roads(bb; cache_dir = tmp, verbose = true)
                @test_logs (:info, r"Downloading OSM roads") match_mode = :any osm_roads(bb; cache_dir = tmp, verbose = true,
                                                                                         force_download = true)
            end
        end
    end

    @testset "the saved pair is written, read back, and force_download goes again" begin
        mktempdir() do tmp
            _with_overpass([_ok()]) do queries, waits
                a = _quiet(() -> osm_roads(bb; cache_dir = tmp))
                @test length(queries) == 1
                b = _quiet(() -> osm_roads(bb; cache_dir = tmp))
                @test length(queries) == 1                                            # read, not downloaded
                @test nrow(b[1]) == nrow(a[1]) && nrow(b[2]) == nrow(a[2])
                _quiet(() -> osm_roads(bb; cache_dir = tmp, force_download = true))
                @test length(queries) == 2
                @test_throws ArgumentError osm_roads(((-78.636, -78.641), (35.779, 35.784)); cache_dir = tmp)
            end
        end
    end

    @testset "a pair saved before v0.3.0 reads back as it did; the types are declared (CR 24)" begin
        mktempdir() do tmp
            old8 = dfL[:, 1:8]                                  # a pair as v0.2.8 saved it: eight columns
            _save_pair(tmp, flat, dfN, old8)
            a = _quiet(() -> osm_roads(bb; cache_dir = tmp))
            @test names(a[1]) == ["IDX", "LON", "LAT", "SOURCE"]
            @test names(a[2]) == ["SRC", "DST", "DIST", "SPEED", "FCLASS", "DIR", "NAME", "SOURCE"]
            @test eltype.(eachcol(a[1])) == [Int, Float64, Float64, String]
            @test eltype.(eachcol(a[2])) == [Int, Int, Float64, Int, Int, Int, Union{Missing,String}, String]
            @test a[2] == old8
            # SOURCE read as String, not String3, and a blank name is `missing`, as 4.2 tests with ismissing
            L2 = copy(old8)
            L2[1, :NAME] = ""
            np, lp = _save_pair(tmp, (-70.0, -69.9, 40.0, 40.1), dfN, L2)
            b = _quiet(() -> osm_roads((-70.0, -69.9, 40.0, 40.1); cache_dir = tmp))
            @test ismissing(b[2].NAME[1]) && !any(ismissing, b[2].NAME[2:end])
            # a pair saved by v0.3.0 has the three columns more, with their types
            _save_pair(tmp, (-71.0, -70.9, 40.0, 40.1), dfN, dfL)
            c = _quiet(() -> osm_roads((-71.0, -70.9, 40.0, 40.1); cache_dir = tmp))
            @test names(c[2]) == names(dfL) && eltype.(eachcol(c[2])) == eltype.(eachcol(dfL))
            @test isequal(c[2], dfL)
        end
    end

    @testset "a box over the size limit warns before a download, and a read does not" begin
        big = ((-85.0, -80.0), (25.0, 30.0))
        # the extension's request stands in for the server, as everywhere here: its answer is the fixture, whatever the box
        _with_overpass([_ok()]) do queries, waits
            @test_logs (:warn, r"Large bounding box") match_mode = :any osm_roads(big)
            @test length(queries) == 1
            @test_logs osm_roads(bb)                                                  # a small box: no warning
            mktempdir() do tmp
                _save_pair(tmp, (-85.0, -80.0, 25.0, 30.0), dfN, dfL)
                @test_logs osm_roads(big; cache_dir = tmp)                           # read from a saved pair: none
            end
        end
        @test Logjam._OSM_AREA_WARN_MI2 == 300
        # Raleigh's 4.2 tiles (0.2 by 0.15 degrees: about 115 sq mi) and its whole city (about 150) are under it
        @test 100 < Logjam._osm_area_mi2((-78.75, -78.55, 35.7, 35.85)) < 130
    end

    @testset "one class table makes the speeds, the classes and the docstring's table" begin
        @test Logjam.OSM_SPEED_DEFAULTS == Dict(c[1] => c[2] for c in Logjam.OSM_CLASSES)
        @test Logjam.OSM_FCLASS == Dict(c[1] => c[3] for c in Logjam.OSM_CLASSES)
        @test length(Logjam.OSM_CLASSES) == 14 && length(Logjam.OSM_SPEED_DEFAULTS) == 14
        # the values of v0.2.8, which 4.2's class table prints
        for (hw, mph, fc) in (("motorway", 65, 1), ("primary_link", 30, 3), ("secondary", 35, 4),
                              ("tertiary_link", 20, 5), ("living_street", 15, 7), ("road", 25, 6))
            @test Logjam.OSM_SPEED_DEFAULTS[hw] == mph && Logjam.OSM_FCLASS[hw] == fc
        end
        rows = split(Logjam._osm_class_table(), "\n")
        @test length(rows) == 2 + length(Logjam.OSM_CLASSES)
        for (row, c) in zip(rows[3:end], Logjam.OSM_CLASSES)
            @test row == "| $(c[1]) | $(c[2]) | $(c[3]) | $(c[4]) |"
        end
        doc = sprint(show, MIME("text/plain"), @doc(osm_roads))
        @test all(c -> occursin(c[1], doc) && occursin(c[4], doc), Logjam.OSM_CLASSES)    # the docstring prints the table
        src = read(joinpath(pkgdir(Logjam), "src", "osmtools.jl"), String)
        @test occursin("\$(_osm_class_table())", src)                                # ... by generating it
    end

    @testset "the generator's two helpers are public" begin
        @test Base.ispublic(Logjam, :_osm_cache_path) && Base.ispublic(Logjam, :_osm_snap_bbox)
        # the arguments make_osm_raleigh.jl passes: the flat box and a folder
        b1 = mapbbox([-78.6758457, -78.6695716], [35.7706306, 35.7875615]; xexpand = 2, yexpand = 0.5)
        np, lp = Logjam._osm_cache_path((b1[1]..., b1[2]...), "data")
        @test np == joinpath("data", "osm_w-78.7_e-78.65_s35.75_n35.8_nodes.csv")
        @test lp == joinpath("data", "osm_w-78.7_e-78.65_s35.75_n35.8_links.csv")
        @test all(isapprox.(Logjam._osm_snap_bbox((b1[1]..., b1[2]...)), (-78.7, -78.65, 35.75, 35.8); atol = 1e-9))
    end
end

@testset "[CR 22] [CR 29] the request, the retry, the User-Agent, the sidecar and the class filter" begin
    bb = ((-78.641, -78.636), (35.779, 35.784))
    tile = (-78.65, -78.6, 35.75, 35.8)

    @testset "a busy server is asked again after 30 s, then 60, then 120" begin
        _with_overpass([(status = 504, body = ""), (status = 429, body = ""), _ok()]) do queries, waits
            dfN, dfL, prov = _quiet(() -> Logjam._osm_download(tile))
            @test length(queries) == 3 && waits == [30, 60]
            @test nrow(dfN) > 0 && nrow(dfL) > 0
        end
        _with_overpass([(status = 503, body = "")]) do queries, waits
            err = try _quiet(() -> Logjam._osm_download(tile)); nothing catch e e end
            @test err isa ErrorException && occursin("503", err.msg) && occursin("busy", err.msg)
            @test length(queries) == 4 && waits == [30, 60, 120]                      # the first try and three more
        end
        for st in (502, 429)
            _with_overpass([(status = st, body = ""), _ok()]) do queries, waits
                _quiet(() -> Logjam._osm_download(tile))
                @test length(queries) == 2 && waits == [30]
            end
        end
        _with_overpass([(status = 400, body = "bad query")]) do queries, waits
            err = try _quiet(() -> Logjam._osm_download(tile)); nothing catch e e end
            @test err isa ErrorException && occursin("400", err.msg)
            @test length(queries) == 1 && isempty(waits)                              # no retry of a bad request
        end
        remark = "<osm><remark> runtime error: Query timed out in \"query\" at line 4 after 91 seconds. </remark></osm>"
        _with_overpass([_ok(remark)]) do queries, waits
            err = try _quiet(() -> Logjam._osm_download(tile)); nothing catch e e end
            @test err isa ErrorException && occursin("timed out", err.msg)
        end
        _with_overpass([_ok("<osm></osm>")]) do queries, waits                        # E1: no roads in the box
            err = try _quiet(() -> Logjam._osm_download(tile)); nothing catch e e end
            @test err isa ErrorException && occursin("No drivable roads", err.msg)
        end
    end

    @testset "the query declares a time and memory limit sized to the box" begin
        @test _OSM_EXT._osm_sizing(116) == (89, 2^27)                                 # CR 29's observation
        @test _OSM_EXT._osm_sizing(1) == (60, 2^26)
        @test _OSM_EXT._osm_sizing(10_000) == (180, 2^30)
        @test _OSM_EXT._osm_sizing(100)[2] <= _OSM_EXT._osm_sizing(200)[2] <= _OSM_EXT._osm_sizing(400)[2]
        q = _OSM_EXT._osm_query(tile)
        @test occursin(r"\[timeout:\d+\]\[maxsize:\d+\]", q) && !occursin("[timeout:180]", q)
        @test occursin("[bbox:35.75,-78.65,35.8,-78.6]", q)                            # south, west, north, east
        @test !occursin("~\"^(", q)                                                   # no class filter
        qh = _OSM_EXT._osm_query(tile; highways = ["motorway", "trunk"])
        @test occursin("[\"highway\"~\"^(motorway|trunk)\$\"]", qh)
    end

    @testset "the User-Agent is the Nominatim extension's, and names no person" begin
        nom = Base.get_extension(Logjam, :LogjamNominatimExt)
        @test nom !== nothing && _OSM_EXT._user_agent == nom._user_agent
        @test occursin("Logjam", _OSM_EXT._user_agent) && !occursin("@", _OSM_EXT._user_agent)
    end

    @testset "a provenance file is written beside a downloaded pair, and a read does not need it" begin
        mktempdir() do tmp
            _with_overpass([_ok()]) do queries, waits
                a = _quiet(() -> osm_roads(bb; cache_dir = tmp))
                files = sort(readdir(tmp))
                @test length(files) == 3
                @test files == ["osm_w-78.65_e-78.6_s35.75_n35.8_links.csv", "osm_w-78.65_e-78.6_s35.75_n35.8_nodes.csv",
                                "osm_w-78.65_e-78.6_s35.75_n35.8_provenance.csv"]
                @test all(f -> occursin(r"^osm_.*\.csv$", f), files)                  # the homework's ignore line covers it
                prov = CSV.read(joinpath(tmp, files[3]), DataFrame)
                d = Dict(zip(prov.KEY, prov.VALUE))
                @test d["osm_base"] == "2026-10-12T16:31:21Z"
                @test occursin(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", d["fetched"])
                @test d["tile"] == "-78.65, -78.6, 35.75, 35.8" && d["highways"] == "all"
                @test d["nodes"] == string(nrow(a[1])) && d["links"] == string(nrow(a[2]))
                @test d["links_closed_to_vehicles_dropped"] == "8" && d["links_of_unknown_class_dropped"] == "2" &&
                      d["links_not_strongly_connected_dropped"] == "0"                 # what the fixture's rules dropped
                @test occursin("ODbL", d["licence"]) && occursin("OpenStreetMap contributors", d["licence"])
                @test d["logjam"] == string(pkgversion(Logjam))
                rm(joinpath(tmp, files[3]))                                           # 4.2's tiles have no sidecar
                b = _quiet(() -> osm_roads(bb; cache_dir = tmp))
                @test length(queries) == 1 && nrow(b[2]) == nrow(a[2])
                @test !isfile(joinpath(tmp, files[3]))                                # and a read does not write one
            end
        end
    end

    @testset "a class filter names its tile, and a default call keeps the old names" begin
        @test Logjam._osm_cache_path(bb, "d")[1] == joinpath("d", "osm_w-78.65_e-78.6_s35.75_n35.8_nodes.csv")
        @test Logjam._osm_cache_path(bb, "d"; highways = ["motorway", "trunk"])[1] ==
              joinpath("d", "osm_w-78.65_e-78.6_s35.75_n35.8_hw-motorway+trunk_nodes.csv")
        all14 = first.(Logjam.OSM_CLASSES)
        long = Logjam._osm_cache_path(bb, "d"; highways = all14)[2]
        @test occursin(r"_hw-[0-9a-f]{8}_links\.csv$", long)
        @test long == Logjam._osm_cache_path(bb, "d"; highways = all14)[2]            # the same every time
        mktempdir() do tmp
            _with_overpass([_ok()]) do queries, waits
                _quiet(() -> osm_roads(bb; cache_dir = tmp, highways = ["trunk", "motorway", "trunk"]))
                @test occursin("^(motorway|trunk)\$", only(queries))                 # sorted, each once
                @test any(f -> occursin("_hw-motorway+trunk_", f), readdir(tmp))
                @test !any(f -> occursin(r"s35.8_(nodes|links)", f), readdir(tmp))   # no default-named pair
                _quiet(() -> osm_roads(bb; cache_dir = tmp, highways = ["motorway", "trunk"]))
                @test length(queries) == 1                                            # the filtered pair is read
                _quiet(() -> osm_roads(bb; cache_dir = tmp))
                @test length(queries) == 2                                            # the default call is not satisfied by it
            end
        end
        @test_throws ArgumentError osm_roads(bb; highways = String[])
        @test_throws ArgumentError osm_roads(bb; highways = ["crossing"])
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

@testset "[CR 21] [CR 24] [CR 34] the translation of an Overpass response" begin
    @testset "a posted maxspeed, in mph (CR 21)" begin
        ms = _OSM_EXT._osm_maxspeed
        @test ms("35 mph") == 35 && ms("35mph") == 35 && ms("30 MPH") == 30
        @test ms("50") == 31 && ms("50 km/h") == 31 && ms("100 kmh") == 62   # no unit: km/h, as OpenStreetMap reads it
        @test ms("25.5 km/h") == 16
        @test all(ismissing, ms.(["none", "signals", "walk", "", "0", "25;35", "35 mph;45 mph", "variable"]))
    end

    @testset "the access tags a car's rules read (CR 34)" begin
        acc = _OSM_EXT._osm_access
        @test isequal(acc(Dict("vehicle" => "no", "bus" => "yes")), ("no", missing))
        @test isequal(acc(Dict("motorcar" => "yes", "access" => "no")), ("yes", missing))      # the most specific wins
        @test isequal(acc(Dict("motor_vehicle" => "Destination ", "access" => "no")), ("destination", missing))
        @test isequal(acc(Dict("access" => "private", "vehicle:conditional" => "yes @ (17:00-09:00)")),
                      ("private", "yes @ (17:00-09:00)"))
        @test isequal(acc(Dict("highway" => "residential")), (missing, missing))
        @test all(a -> a in _OSM_EXT._CLOSED, ("no", "private", "agricultural", "forestry", "emergency", "psv"))
        @test !any(a -> a in _OSM_EXT._CLOSED, ("yes", "destination", "permissive", "designated", "delivery"))
        raw = _OSM_EXT._osm_raw_tags(_osm_xml(_syn_nodes, [(1, [1, 2], ["highway" => "service", "maxspeed" => "35 mph",
                                       "vehicle:conditional" => "no @ (Sa & Su)", "name" => "x"])]))
        @test raw == Dict("1" => Dict("maxspeed" => "35 mph", "vehicle:conditional" => "no @ (Sa & Su)"))
    end

    @testset "the synthetic extract: each rule, and the links that remain" begin
        dfN, dfL, info = _quiet(() -> _OSM_EXT._osm_tables_from_xml(_osm_xml(_syn_nodes, _syn_ways)))
        @test names(dfN) == ["IDX", "LON", "LAT", "SOURCE"]
        @test names(dfL) == ["SRC", "DST", "DIST", "SPEED", "FCLASS", "DIR", "NAME", "SOURCE", "MAXSPEED", "ACCESS", "CONDITIONAL"]
        # four nodes (1 to 4) and the loop's eight links; the closed ways, the crossing and the one-way stub are gone
        @test dfN.IDX == 1:4 && sort(dfN.LON) ≈ [-78.6 + 0.001k for k in 1:4]
        @test sort(unique(dfL.NAME)) == ["A & B St", "Sec Blvd", "Tert Ave", "Unc Rd"]
        @test nrow(dfL) == 8 && all(==(1), dfL.DIR) && all(==("OSM"), dfL.SOURCE) && all(dfL.DIST .> 0)
        @test all(in(1:4), dfL.SRC) && all(in(1:4), dfL.DST)
        @test info == (closed = 4, unknown = 2, notstrong = 1)                  # Gate, Farm: 2 each; Cross: 2; Stub: 1 left
        row(nm) = dfL[findfirst(==(nm), dfL.NAME), :]
        @test row("A & B St").SPEED == 31 && row("A & B St").MAXSPEED == 31 && row("A & B St").FCLASS == 7
        @test row("Tert Ave").SPEED == 25 && row("Tert Ave").MAXSPEED == 25 && row("Tert Ave").FCLASS == 5      # posted, not class 30
        @test row("Tert Ave").ACCESS == "yes"
        @test row("Sec Blvd").SPEED == 35 && ismissing(row("Sec Blvd").MAXSPEED) && row("Sec Blvd").FCLASS == 4   # "none": the class
        @test row("Sec Blvd").CONDITIONAL == "no @ (Mo-Fr 07:00-09:00)" && ismissing(row("Sec Blvd").ACCESS)
        @test row("Unc Rd").SPEED == 30 && row("Unc Rd").ACCESS == "destination" && row("Unc Rd").FCLASS == 6
        @test ismissing(row("A & B St").CONDITIONAL)
        # stable types, the same as a saved pair reads back as (CR 24)
        @test eltype.(eachcol(dfN)) == [Int, Float64, Float64, String]
        @test eltype.(eachcol(dfL)) == [Int, Int, Float64, Int, Int, Int, Union{Missing,String}, String,
                                        Union{Missing,Int}, Union{Missing,String}, Union{Missing,String}]
    end

    @testset "a node that cannot reach the rest, or be reached, is dropped with its links (CR 24)" begin
        # a one-way spur out (1 to 5) and a one-way spur in (6 to 1) hang off a two-way pair; neither can be a trip's end
        nodes = [(k, -78.6 + 0.001k, 35.7) for k in 1:6]
        ways = [(1, [1, 2], ["highway" => "residential", "name" => "Core St"]),
                (2, [1, 5], ["highway" => "residential", "name" => "Out St", "oneway" => "yes"]),
                (3, [6, 1], ["highway" => "residential", "name" => "In St", "oneway" => "yes"])]
        dfN, dfL, info = _quiet(() -> _OSM_EXT._osm_tables_from_xml(_osm_xml(nodes, ways)))
        @test nrow(dfN) == 2 && sort(unique(dfL.NAME)) == ["Core St"] && nrow(dfL) == 2
        @test info.notstrong == 2
        # every remaining node reaches every other: the graph of the links is strongly connected
        g = Graphs.SimpleDiGraph(nrow(dfN))
        foreach(r -> Graphs.add_edge!(g, r.SRC, r.DST), eachrow(dfL))
        @test Graphs.is_strongly_connected(g)
    end

    @testset "the fixture: the rules of CR 21, CR 24 and CR 34" begin
        dfN, dfL, info = _quiet(() -> _OSM_EXT._osm_tables_from_xml(_OSM_FIXTURE_TEXT))
        @test info == (closed = 8, unknown = 2, notstrong = 0)
        @test sort(unique(dfL.NAME)) == ["Main St", "Mid Ave", "North Link", "Second St", "Third St", "West Ave"]
        @test nrow(dfN) == 10 && nrow(dfL) == 22                                 # nodes 1 to 10; 11 and 12 are on no road left
        @test all(dfL[dfL.NAME .== "Main St", :SPEED] .== 35)
        @test all(dfL[dfL.NAME .== "Mid Ave", :SPEED] .== 30) && all(ismissing, dfL[dfL.NAME .== "Mid Ave", :MAXSPEED])
    end
end

@testset "[P8] stitchnetworks is removed (0 course calls)" begin
    @test !isdefined(Logjam, :stitchnetworks)
    @test !(:stitchnetworks in names(Logjam))
    @test !isdefined(Logjam, :_osm_stitch)
    @test !isdefined(Base.get_extension(Logjam, :LogjamOSMExt), :_stitchnetworks_impl)
end

# [K10] LogjamOSMExt is triggered by LightOSM alone (it no longer uses NearestNeighbors, which only stitchnetworks
# did). Lecture 4.2 and a homework's key write `using LightOSM, NearestNeighbors` (principle 9): that line must
# still load the extension. Each case is a fresh process, the way a lecture runs, started with this session's own
# flags so the precompiled packages match.
@testset "[K10] the OSM extension loads on LightOSM alone and on the line the course writes" begin
    dfN, dfL = _fixture_tables()
    flat = (-78.641, -78.636, 35.779, 35.784)
    child(code, args...) = begin
        out = IOBuffer()
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code $(collect(args))`
        ok = success(pipeline(cmd; stdout = out, stderr = out))
        (ok, String(take!(out)))
    end
    load_and_read = "dir = ARGS[1]; using Logjam, DataFrames; " *
                    "ext = Base.get_extension(Logjam, :LogjamOSMExt); " *
                    "N, L = osm_roads((-78.641, -78.636, 35.779, 35.784); cache_dir = dir); " *
                    "println(\"ext=\", ext !== nothing, \" nodes=\", nrow(N), \" links=\", nrow(L))"
    mktempdir() do tmp
        _save_pair(tmp, flat, dfN, dfL)
        want = "ext=true nodes=$(nrow(dfN)) links=$(nrow(dfL))"
        for using_line in ("using LightOSM", "using LightOSM, NearestNeighbors", "using NearestNeighbors, LightOSM")
            ok, out = child(using_line * "; " * load_and_read, tmp)
            @test ok
            @test occursin(want, out)
        end
        # without LightOSM the extension is not loaded, a saved pair still reads, and a miss names `using LightOSM`
        ok, out = child(load_and_read, tmp)
        @test ok && occursin("ext=false nodes=$(nrow(dfN)) links=$(nrow(dfL))", out)
        # (C5) the miss is a MethodError of `_osm_download` that carries a hint, with a `cache_dir` and without
        miss = "using Logjam; try; osm_roads((-70.0, -69.9, 40.0, 40.1); cache_dir = ARGS[1]); " *
               "catch e; println(\"TYPE: \", typeof(e)); println(\"MSG: \", sprint(showerror, e)); end"
        ok, out = child(miss, tmp)
        @test ok && occursin("TYPE: MethodError", out) && occursin("Run: using LightOSM", out) && !occursin("NearestNeighbors", out)
        miss2 = "using Logjam; try; osm_roads(((-70.0, -69.9), (40.0, 40.1))); " *
                "catch e; println(\"TYPE: \", typeof(e)); println(\"MSG: \", sprint(showerror, e)); end"
        ok, out = child(miss2, tmp)
        @test ok && occursin("TYPE: MethodError", out) && occursin("Run: using LightOSM", out)
        # and with the extension loaded, the same MethodError carries no hint: a wrong argument is not a missing package
        loaded = "using LightOSM, Logjam; try; Logjam._osm_download(1; verbose = true); " *
                 "catch e; println(\"TYPE: \", typeof(e)); println(\"MSG: \", sprint(showerror, e)); end"
        ok, out = child(loaded, tmp)
        @test ok && occursin("TYPE: MethodError", out) && !occursin("Run: using LightOSM", out)
    end
end
