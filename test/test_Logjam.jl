# test_Logjam.jl -- the tests of src/Logjam.jl, one test file per source file (PCV WP8 of Logjam v0.3.1).
# Each section below was moved verbatim from the test file its marker names, under that file's own header,
# which says which component added it. No assertion changed. A testset taken out of a wrapper that held the
# tests of several modules sits in a wrapper of the same name with this module's name before it.

# ==== moved from test/test_packaging.jl, its lines 1-77 ====
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

# ==== moved from test/test_extensions_c5.jl, its lines 1-169 ====
# test_extensions_c5.jl -- the extensions, five become three (PCV K11c, MAP, C5): every function is declared in core with
# its docstring, and the extension adds methods. LogjamMapExt (triggered by GeoMakie alone) holds `makemap`,
# `plotroads!`, `plotroute!` and `dcf`; LogjamOSMExt the download; LogjamNominatimExt is unchanged. A call made without
# the extension is a MethodError that carries a hint.

using Test
using Logjam
using DataFrames

const _MAPEXT = Base.get_extension(Logjam, :LogjamMapExt)
const _OSMEXT = Base.get_extension(Logjam, :LogjamOSMExt)
const _NOMEXT = Base.get_extension(Logjam, :LogjamNominatimExt)

@testset "[C5] three extensions; every extension function declared in core with its docstring" begin
    @testset "the extensions are the three, and the CairoMakie one is gone" begin
        @test _MAPEXT !== nothing && _OSMEXT !== nothing && _NOMEXT !== nothing
        @test Base.get_extension(Logjam, :LogjamCairoMakieExt) === nothing
        @test !isfile(joinpath(pkgdir(Logjam), "ext", "LogjamCairoMakieExt.jl"))
        # v0.3.1 adds two (X2): LogjamJuMPExt (JuMP and HiGHS) and LogjamMakieExt (Makie); the three of C5 are unchanged
        @test sort!([f for f in readdir(joinpath(pkgdir(Logjam), "ext")) if endswith(f, ".jl")]) ==
              ["LogjamJuMPExt.jl", "LogjamMakieExt.jl", "LogjamMapExt.jl", "LogjamNominatimExt.jl", "LogjamOSMExt.jl"]
    end

    @testset "the methods are the extension's; core holds none of them" begin
        # WP7b (v0.3.1; X2, MAP16): plotroute!'s three methods moved to LogjamMakieExt, which GeoMakie loads too, so they
        # are that extension's now; v0.3.0's copy of this file fails here for plotroute! (a baseline addition, X2)
        for f in (makemap, plotroads!, dcf)
            @test !isempty(methods(f))
            @test all(m -> m.module === _MAPEXT, methods(f))
        end
        @test !isempty(methods(plotroute!))
        @test all(m -> m.module === Base.get_extension(Logjam, :LogjamMakieExt), methods(plotroute!))
        @test length(methods(makemap)) == 7            # (), (x), (x, y) from the default arguments, (bb), (cell, x, y), (cell, bb), (cell)
        @test length(methods(plotroute!)) == 3 && length(methods(plotroads!)) == 1 && length(methods(dcf)) == 1
        @test all(m -> m.module === _OSMEXT, methods(Logjam._osm_download)) && length(methods(Logjam._osm_download)) == 1
    end

    @testset "no forwarding Ref is left but Nominatim's pair" begin
        for s in (:_makemap_impl, :_plotroads_impl, :_plotroute_impl, :_dcf_impl, :_geomakie_available, :_cairomakie_available,
                  :_cairomakie_activate, :_osm_available)
            @test !isdefined(Logjam, s)
        end
        @test isdefined(Logjam, :_nominatim_available) && isdefined(Logjam, :_nominatim_geocode)
        @test Logjam._osm_download isa Function                                              # a declared function, not a Ref
        @test !isdefined(_MAPEXT, :_makemap_impl) && !isdefined(_MAPEXT, :_plotroads_impl) && !isdefined(_MAPEXT, :_plotroute_impl)
    end

    @testset "the docstrings are in core, none in the extensions" begin
        meta = Base.Docs.meta(Logjam)
        for s in (:makemap, :plotroads!, :plotroute!, :dcf)
            @test haskey(meta, Base.Docs.Binding(Logjam, s))
        end
        b = Base.Docs.Binding(Logjam, :makemap)
        @test length(meta[b].order) == 3                      # the declaration (makemap(x, y)'s), makemap(bb) and makemap(cell, x, y)
        # the apparatus' own reading (apparatus.jl `docline`): the first docstring of the binding is the one for `makemap(x, y)`
        first_doc = join(string.(meta[b].docs[meta[b].order[1]].text), "")
        @test startswith(first_doc, "    makemap(x = nothing, y = nothing;") && occursin("Create a map of a predefined region", first_doc)
        for ext in (_MAPEXT, _OSMEXT)
            @test isempty(Base.Docs.meta(ext))
        end
    end

    @testset "the declarations the course's logjam_kwargs reads, after C5" begin
        kw(f) = String.(Base.kwarg_decl(first(methods(f))))
        @test kw(plotroads!) == ["show_connectors"]
        @test kw(plotroute!) == ["color", "linewidth", "linestyle", "arrows", "arrow_at", "arrow_size", "arrow_every"]
        # the first method of makemap is the no-argument one, written out with the keywords (default arguments made it a
        # method whose list read "...", so `logjam_kwargs(Logjam, :makemap)` was empty)
        @test kw(makemap) == ["region", "xexpand", "yexpand", "roads", "borders", "size", "showgrid", "doRoadbkgd"]
        @test kw(osm_roads) == ["cache_dir", "crop", "force_download", "verbose", "highways"]
        # and every other method of makemap lists the keywords it takes, but the one-argument method the default `y`
        # makes, which forwards to the two-argument one and lists "..."
        lists = [Base.kwarg_decl(m) for m in methods(makemap)]
        @test count(l -> l == [Symbol("...")], lists) == 1
        @test all(l -> l == [Symbol("...")] || (:roads in l && :borders in l && :showgrid in l), lists)
    end

    @testset "no method ambiguity in Logjam or in any of the three extensions" begin
        @test isempty(Test.detect_ambiguities(Logjam, _MAPEXT, _OSMEXT, _NOMEXT))
    end

    @testset "the cell methods take a Makie.GridPosition, and a figure's first position is one" begin
        fig = GeoMakie.Makie.Figure()
        r = makemap(fig[1, 2], [-79.0, -78.0], [35.0, 36.0]; roads = false)
        @test r.fig === fig
        @test_throws MethodError makemap(5, [-79.0, -78.0], [35.0, 36.0])            # not a cell
        @test_throws MethodError makemap("fig[1, 1]"; roads = false)
        sub = fig[2, 1][1, 1]                                                         # a cell of a nested layout
        @test sub isa GeoMakie.Makie.GridSubposition
        @test_throws MethodError makemap(sub, [-79.0, -78.0], [35.0, 36.0])           # a GridSubposition is not accepted (principle 8)
    end
end

# Each case is a fresh process, the way a lecture runs, started with this session's own flags so the precompiled
# packages match (as K10's test of LightOSM). A process that could draw runs CairoMakie.activate!(visible = false) first.
function _c5_child(code)
    out = IOBuffer()
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
    ok = success(pipeline(cmd; stdout = out, stderr = out))
    return ok, String(take!(out))
end

# every map function called as a script calls it, and what it throws without the extension: one line each, `name|type|hinted`
const _C5_PROBE = """
using DataFrames
function probe(name, f)
    try
        f()
        println(name, "|NOERROR|false")
    catch e
        println(name, "|", typeof(e), "|", occursin("Run: using CairoMakie, GeoMakie", sprint(showerror, e)))
    end
end
probe("makemap()", () -> makemap())
probe("makemap(x, y; roads)", () -> makemap([-79.0, -78.0], [35.0, 36.0]; roads = false))
probe("makemap(bb)", () -> makemap(((-79.0, -78.0), (35.0, 36.0))))
probe("makemap(region)", () -> makemap(region = :CUS))
probe("plotroads!", () -> plotroads!(nothing, DataFrame(IDX = [1], LON = [0.0], LAT = [0.0]), DataFrame(SRC = [1], DST = [1])))
probe("plotroute!(x, y)", () -> plotroute!(nothing, [-79.0, -78.0], [35.0, 36.0]))
probe("plotroute!(x, y; color)", () -> plotroute!(nothing, [-79.0, -78.0], [35.0, 36.0]; color = :blue))
probe("dcf", () -> dcf())
"""

@testset "[C5] fresh processes: what loads the map extension, and what a call without it says" begin
    names = ["makemap()", "makemap(x, y; roads)", "makemap(bb)", "makemap(region)", "plotroads!", "plotroute!(x, y)",
             "plotroute!(x, y; color)", "dcf"]
    parse_out(out) = Dict(split(l, '|')[1] => (split(l, '|')[2], split(l, '|')[3] == "true") for l in split(out, '\n') if count('|', l) == 2)

    @testset "using Logjam alone: every map function is a MethodError with the hint" begin
        ok, out = _c5_child("using Logjam; " * _C5_PROBE * "println(\"ext=\", Base.get_extension(Logjam, :LogjamMapExt) !== nothing)")
        @test ok && occursin("ext=false", out)
        got = parse_out(out)
        for n in names
            @test get(got, n, ("", false)) == ("MethodError", true)
        end
    end

    @testset "using Logjam, CairoMakie (no GeoMakie): the extension is not loaded, the hint names both" begin
        ok, out = _c5_child("using Logjam, CairoMakie; CairoMakie.activate!(visible = false); " * _C5_PROBE *
                            "println(\"ext=\", Base.get_extension(Logjam, :LogjamMapExt) !== nothing)")
        @test ok && occursin("ext=false", out)
        got = parse_out(out)
        # WP7b (v0.3.1; X2, MAP16): plotroute! is the Makie extension's, which CairoMakie loads, so here its probe
        # reaches the method, whose `lines!` on `nothing` finds no figure: not a MethodError, and no hint. v0.3.0's copy
        # of this file fails here for its two plotroute! probes (a baseline addition, X2). A plain Axis is drawn on with
        # CairoMakie alone in test_LogjamMakieExt.jl.
        for n in names
            startswith(n, "plotroute!") && continue
            @test get(got, n, ("", false)) == ("MethodError", true)
        end
        for n in ("plotroute!(x, y)", "plotroute!(x, y; color)")
            @test haskey(got, n) && got[n][1] != "MethodError" && got[n][1] != "NOERROR"
        end
    end

    draw = """
    ext = Base.get_extension(Logjam, :LogjamMapExt)
    r = makemap([-79.0, -78.0], [35.0, 36.0])
    fig = Figure()
    c = makemap(fig[1, 1], [-79.0, -78.0], [35.0, 36.0]; roads = false)
    h = plotroute!(r.ax, [-79.0, -78.0], [35.0, 36.0])
    println("ext=", ext !== nothing, " fig=", r.fig isa Figure, " ax=", r.ax isa GeoAxis, " layers=",
            join([string(k) for (k, v) in pairs(r.layers) if v !== nothing], ","), " cell=", c.fig === fig,
            " route=", h.lines isa Lines, " ", haskey(h, :arrows))
    """
    want = "ext=true fig=true ax=true layers=roads,states cell=true route=true true"

    @testset "using GeoMakie, Logjam: the extension loads and a figure is created, with no backend" begin
        ok, out = _c5_child("using GeoMakie, Logjam; " * draw)
        @test ok && occursin(want, out)
    end

    @testset "the course's using CairoMakie, GeoMakie, in both orders, with Logjam first or after" begin
        for line in ("using CairoMakie, GeoMakie; using Logjam", "using GeoMakie, CairoMakie; using Logjam",
                     "using Logjam; using CairoMakie, GeoMakie", "using Logjam, GeoMakie, CairoMakie")
            ok, out = _c5_child(line * "; CairoMakie.activate!(visible = false); " * draw *
                                "; dcf(); println(\"dcf ok \", size(r.fig.scene))")
            @test ok && occursin(want, out) && occursin("dcf ok (600, 450)", out)
        end
    end
end
