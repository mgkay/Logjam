using Logjam
using Test
using CairoMakie
using GeoMakie

# Draw figures but never open an image viewer. Outside an IDE or notebook, CairoMakie's `display`
# writes a temporary display.png and opens it in the system viewer, so dcf's smoke test
# (test_LogjamMapExt.jl, from test_plottools.jl) left one Photos window open per suite run.
CairoMakie.activate!(visible = false)

# One test file per source file (PCV WP8 of Logjam v0.3.1): test_<name>.jl holds the tests of src/<name>.jl or
# ext/<name>.jl, moved there verbatim from the files the components added, each section under its old file's header.
# The shared pin cases, oracle readers, lecture texts and helpers are included by the files that use them, each once.
# The order keeps the constraints the old list had: geocode before anything loads HTTP and JSON3 (the Nominatim
# extension), the extension checks after LightOSM, HTTP and JSON3 are loaded, and JuMP and HiGHS last.
#
# Each file runs through `_runfile`, which then writes out what the file printed, stdout before stderr. When the
# suite's output goes to a file, Julia buffers each stream in blocks of 32 KiB, so the warnings and notes on stderr
# were written in one block at the first full block of stdout, wherever it fell: until WP8 between the `x2ln tests`
# header and its row, after WP8's moves inside a header line. Flushed file by file, a summary is never cut.
_runfile(f) = (include(f); flush(stdout); flush(stderr); nothing)

_runfile("test_doctests.jl")       # the docstrings' jldoctest blocks
_runfile("test_loctools.jl")       # facility location; its properties and Matlog oracles; WP3's ala forms and alignments
_runfile("test_disttools.jl")      # distances; their properties and oracles; WP3's metric kernel; WP10's empirical dgca
_runfile("test_transtools.jl")     # transport costing; the K6 pins; properties and oracles; WP4's tables and contract
_runfile("test_maptools.jl")       # mapbbox, aligntext(x, y), usstates; K12's county box; WP10's place and state boxes; WP7b's ldlabel
_runfile("test_datatools.jl")      # the census and FAF5 tables; K11b's FAF5 table pins; K12's usstate; WP5's loaders and STFIP
_runfile("test_place_labels.jl")   # PL: usplace()'s LABEL column and datatools.jl's _place_label, a file of its own (PL's brief)
_runfile("test_displaytools.jl")   # prt, snapvals, thousands; the K4 prt pins and K14's decimals per column
_runfile("test_geomtools.jl")      # alloclines
_runfile("test_roadtools.jl")      # road networks; the K8 pins; the line builders; connectors, links2graph, thin, pathroads
_runfile("test_faf5net.jl")        # the derived FAF5 network (N1, N2, N3)
_runfile("test_routetools.jl")     # routing; the K7a pins; K7a, K7b; K12's Lecture 5.1 pins; properties, oracles; WP6
_runfile("test_integration.jl")    # the README example workflows, across modules
_runfile("test_LogjamMapExt.jl")   # makemap, plotroads!, dcf; the K11a, K11b and K11c map pins; S22; N4's tiers; v0.3.0's plotroute! pins (plotroute! is LogjamMakieExt's since WP7b)
_runfile("test_geocode.jl")        # loc2lonlat, lonlat2loc, lonlat; the K5 pins; K12's lonlat; WP5's batch driver and keywords
_runfile("test_osmtools.jl")       # joinroads; osm_roads' box, crop and saved pairs (loads HTTP + JSON3: after test_geocode.jl)
_runfile("test_LogjamOSMExt.jl")   # the OSM extension: the fixture's translation, the request and retry, loading (offline)
_runfile("test_invtools.jl")       # WP1's inventory measures
_runfile("test_Logjam.jl")         # exports and public names; the extensions and the hint (needs all three extensions loaded)

# WP2 (v0.3.1): every file above ran without JuMP and HiGHS, so without the optimization extension. They are loaded
# here, by `import` so that Main gains none of their names, and LogjamJuMPExt with them, for the file that tests it.
@testset "[WP2] the files above ran without the optimization extension" begin
    @test Base.get_extension(Logjam, :LogjamJuMPExt) === nothing
end
import JuMP, HiGHS
_runfile("test_LogjamJuMPExt.jl")  # WP2: TSP, subtours, binpack, snapvals on JuMP variables; fresh processes
_runfile("test_LogjamMakieExt.jl") # WP7a: aligntext(ax, x, y, labels); WP7b: plotroute!, plotshmt!; WP7c: the schematics; fresh processes with CairoMakie alone

if haskey(ENV, "LOGJAM_NETWORK_TESTS")
    _runfile("test_osm_network.jl")
    _runfile("test_LogjamNominatimExt.jl")
end
