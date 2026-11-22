using Logjam
using Test
using CairoMakie
using GeoMakie

# Draw figures but never open an image viewer. Outside an IDE or notebook, CairoMakie's `display`
# writes a temporary display.png and opens it in the system viewer, so dcf's smoke test
# (test_plottools.jl) left one Photos window open per suite run.
CairoMakie.activate!(visible = false)

include("test_doctests.jl")
include("test_loctools.jl")
include("test_disttools.jl")
include("test_transtools.jl")
include("test_maptools.jl")
include("test_datatools.jl")
include("test_prt_pins.jl")    # byte-equality pins of prt's output (PCV K4, principle 9)
include("test_prt_columns.jl") # prt's decimals per column and Matlog's fractional-column rule (PCV K14, PR)
include("test_dist_geo_pins.jl")   # value pins of the course's distance and geocoding calls (PCV K5, principle 9)
include("test_transport_pins.jl")  # value pins of the course's transport calls (PCV K6, principle 9)
include("test_routing_pins.jl")    # value pins of the course's routing calls (PCV K7a, principle 9)
include("test_road_pins.jl")       # value pins of the course's road-network calls (PCV K8, principle 9)
include("test_map_pins.jl")        # what the course sees of its makemap calls, and that makemap leaves the caller's CairoMakie settings alone (PCV K11a, principle 9)
include("test_line_builders.jl")   # x2ln(i, j, x), tracepath(P, i, j), tracepath(P, seq) (PCV K11b, C8)
include("test_makemap_c4.jl")      # makemap's interface: cell, size, roads, borders, the return, doRoadbkgd (PCV K11b, C4)
include("test_map_line_pins.jl")   # plotroads!, makemap's base-layer styles, the FAF5 tables and tracepath on the course's idiom (PCV K11b, principle 9)
include("test_map_k11c_pins.jl")   # the default-road makemap calls' drawn extents and layers, and the map functions' declarations (PCV K11c, principle 9)
include("test_map_s22.jl")         # the road network on a small map: the measure, the crop, the style, layers.roads (PCV K11c, S22, S23)
include("test_k12_pins.jl")        # what the course gets today from the calls K12's functions replace: Lecture 5.1's randtour, disk, sfcpos, tspspfillcur, hcat(df.LON, df.LAT), string ZIPs, Wake's box, usstates (PCV K12, principle 9)
include("test_k12_functions.jl")   # the small functions K12 adds, each equal to the course definition it takes the place of (PCV K12, principles 8 and 9)
include("test_roadtools.jl")
include("test_connector_search.jl")  # K8: addconnectors' exact local point location against the whole triangulation
include("test_links2graph.jl")       # K8: links2graph equals the graph the lectures build by hand (S17, CR 17)
include("test_thin.jl")              # K8: thin on typed arcs, direction-aware, label-independent (CR 18, CR 25, N6)
include("test_pathroads.jl")         # K8: the roads along a path, equal to Lecture 4.2's streets (CR 30)
include("test_faf5net.jl")           # N1: the derived FAF5 network's route keys, Interstate flag and ramp rule (CR 19, RN3, RN4)
include("test_routetools.jl")
include("test_routing_k7a.jl")     # K7a: principle 9 checks against Lecture 5.2's stand-ins, per-item tests
include("test_routing_k7b.jl")     # K7b: the checked route cost, principle 9 checks against Lecture 5.3's definitions
include("test_integration.jl")
include("test_plotroute.jl")       # K11a: plotroute!'s three methods, arrowheads measured from the picture (D2, P8)
include("test_aligntext_duplicates.jl")
include("test_plottools.jl")
include("test_geocode.jl")
include("test_osm.jl")         # offline fixture; the networked tests are test_osm_network.jl
include("test_properties.jl")
include("test_oracles.jl")     # Matlog oracle data (test/oracles/*.csv, from tools/v0_3_0/make_oracles.m)
include("test_packaging.jl")   # loads HTTP + JSON3 (Nominatim ext.): keep after test_geocode.jl
include("test_extensions_c5.jl")   # the three extensions, every extension function declared in core, the hint, fresh processes (PCV K11c, MAP, C5); needs all three loaded

if haskey(ENV, "LOGJAM_NETWORK_TESTS")
    include("test_osm_network.jl")
    include("test_nominatim.jl")
end