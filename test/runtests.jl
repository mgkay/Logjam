using Logjam
using Test
using CairoMakie
using GeoMakie

include("test_loctools.jl")
include("test_transtools.jl")
include("test_maptools.jl")
include("test_datatools.jl")
include("test_roadtools.jl")
include("test_routetools.jl")
include("test_integration.jl")
include("test_aligntext_duplicates.jl")
include("test_plottools.jl")
include("test_geocode.jl")

if haskey(ENV, "LOGJAM_NETWORK_TESTS")
    include("test_osm.jl")
    include("test_nominatim.jl")
end