"""
# Logjam

Logistics toolkit for facility location, transportation costing, freight road networks,
route optimization, U.S. geographic data, and GeoMakie visualizations.

The manual lists every function by topic with its docstring, and `?name` shows one. The topics
and their names:

- **Facility location:** `ufladd`, `ufldrop`, `uflxchg`, `ufl`, `pmedian`, `ala`, `wcentroid`, `randX`.
- **Transportation economics:** `rate_ltl`, `charge_tl`, `charge_ltl`, `mincharge_tl`, `mincharge_ltl`,
  `maxpayld`, `qmax_ltl`, `totlogcost`, `aggshmt`, `minTLC`.
- **Distances:** `dgc`, `dgca`, `d1`, `d2`, `dists`.
- **Road networks:** `thin`, `addconnectors`, `links2graph`, `shortestpaths`, `tracepath`, `pathroads`,
  `x2ln`, `cropnetwork`, `prune_reindex`, and `osm_roads` for OpenStreetMap (a download needs LightOSM).
- **Routing:** `segcost`, `rteTC`, `rte2loc`, `isorigin`, `rte2ldmx`, `rtesegsum`, `rte2idx`, `sh2rte`,
  `mincostinsert`, `twoopt`, `pairwisesavings`, `savings`.
- **Data and geocoding:** `usplace`, `usstate`, `uscounty`, `uscentract`, `uscenblkgrp`, `uszcta5`,
  `uszcta3`, `uscbsa`, `uscsa`, `st2fips`, `fips2st`, `faf5nodes`, `faf5links`, `loc2lonlat`,
  `lonlat2loc`, `lonlat`.
- **Maps** (GeoMakie): `makemap`, `mapbbox`, `aligntext`, `alloclines`, `plotroads!`, `plotroute!`, `dcf`,
  and the constants `WORLD_LIMITS`, `US_LIMITS`, `CUS_LIMITS`.
- **Display:** `prt`, `snapvals`, `thousands`.
- **Public, not exported** (called as `Logjam.name`, so a script's own function of the name does not collide):
  `scanTW`, `usstates`.

## Dependencies

Always loaded: `Serialization`, `Artifacts`, `LazyArtifacts`, `Random`, `DataFrames`, `CSV`,
`DelaunayTriangulation`, `Graphs`, `SimpleWeightedGraphs`, `SparseArrays`, `Optim`.

Weak dependencies, which activate an extension when loaded: `GeoMakie` (with `CairoMakie` to render)
for maps; `HTTP` and `JSON3` for street-address geocoding with Nominatim; `LightOSM` to download an
OpenStreetMap road network.
"""
module Logjam

# Import all required packages
using Artifacts
using LazyArtifacts
using Serialization
using Random: Xoshiro, AbstractRNG
using DataFrames
using CSV
using DelaunayTriangulation
using Graphs
using SimpleWeightedGraphs
using SparseArrays
using Optim

# DelaunayTriangulation's `triangulate` and `find_triangle` draw from the global random stream unless given an
# `rng`, which makes the triangle chosen among cocircular nodes vary from run to run and advances the caller's
# stream. Every call here passes a generator of its own, a fresh one each time, so the answer depends on the
# points alone and the global stream is left where it was.
_tri_rng() = Xoshiro(0)

# Three extensions (C5). The map extension (LogjamMapExt, triggered by GeoMakie) adds the methods of `makemap`,
# `plotroads!`, `plotroute!` and `dcf`, and the OSM extension (LogjamOSMExt, triggered by LightOSM) the method of
# `_osm_download`; each function is declared in core, with its docstring, so a call made without its extension is a
# MethodError and `__init__` (below) says what to load. The one Ref left is Nominatim's query function, which
# LogjamNominatimExt (HTTP + JSON3) sets and the tests swap to stand in for the network.
const _nominatim_available = Ref{Bool}(false)
const _nominatim_geocode = Ref{Any}(nothing)

# Export facility location functions
export ufladd, ufldrop, uflxchg, ufl, pmedian, randX, ala, wcentroid

# Export transportation economics functions
export rate_ltl, charge_tl, charge_ltl, mincharge_tl, mincharge_ltl, maxpayld, qmax_ltl
export totlogcost, aggshmt, minTLC

# Export data functions
export usstate    # one row per state, aggregated from uscounty(): Lecture 2.5's ladder (CR 12)
export usplace, uscounty, uscentract, uscenblkgrp, uszcta5, uszcta3
export uscbsa, uscsa, st2fips, fips2st
export faf5nodes, faf5links
export loc2lonlat, lonlat2loc
export lonlat    # a table's, row's or geocoded places' coordinates as [lon, lat] or an n x 2 matrix (A1, LL)

# Export data helper functions (H1–H3) and relocated functions
export prt, snapvals, thousands
export alloclines

# Export map functions and constants
export makemap, mapbbox, aligntext, plotroads!, plotroute!
export WORLD_LIMITS, US_LIMITS, CUS_LIMITS

# Export helper functions (H7)
export dcf

# Export road network functions (including H5–H6)
export dgc, d1, d2, dgca, dists, prune_reindex, thin, addconnectors
export links2graph, x2ln, cropnetwork, shortestpaths, tracepath, pathroads

# Export OSM functions (a download requires the LightOSM extension)
export osm_roads

# Export routing functions
export segcost, rteTC, isorigin, rte2loc
export twoopt, savings, mincostinsert, pairwisesavings
export rte2ldmx    # the shipments on board at each load mix (CR 59); `rteTC` carries Matlog's checks (CR 42, D6)
export rtesegsum    # what is on board over each segment of a route (CR 53); `rtesegid` is internal (IN5)
export rte2idx, sh2rte        # the shipments of a route; a route of its own for each shipment on none (CR 53)

# Public API (accessible as Logjam.func, not auto-imported into namespace)
public scanTW    # Lecture 5.3's time-window scan (routetools.jl), the implementation rung of a model; not exported, so the lecture's own `scanTW` does not collide (CR 42, D10)
public usstates    # the state borders as NaN-separated polylines (maptools.jl); Lecture 5.1 and four Lecture 2.2 generators call it qualified (C12, V6); not exported, so it does not collide with `usstate`
public _osm_cache_path, _osm_snap_bbox    # the tile files and the tile of a box (osmtools.jl); Lecture 4.2's data generator reports its boxes' tiles with them, so they are public (S18)

# Include component files
include("loctools.jl")
include("transtools.jl")
include("datatools.jl")
include("maptools.jl")
include("disttools.jl")
include("roadtools.jl")
include("faf5net.jl")      # the derived FAF5 road network (CR 19): route keys, the Interstate flag, ramps; internal
include("routetools.jl")
include("osmtools.jl")
include("geocode.jl")

"""
    dcf()

Display current figure. Requires `using CairoMakie, GeoMakie`.
"""
function dcf end

# The hint a MethodError carries when a function whose methods an extension adds is called without it (C5): the map
# functions and `dcf` need GeoMakie (and CairoMakie to draw), a download needs LightOSM. Silent for any other error,
# and for these functions once their extension is loaded, when a MethodError is a wrong argument.
function _extension_hint(io, exc, argtypes, kwargs)
    f = exc.f === Core.kwcall ? exc.args[2] : exc.f
    if f in (makemap, plotroads!, plotroute!, dcf) && Base.get_extension(Logjam, :LogjamMapExt) === nothing
        print(io, "\n$(nameof(f)) needs the map extension, which GeoMakie loads. Run: using CairoMakie, GeoMakie")
    elseif f === _osm_download && Base.get_extension(Logjam, :LogjamOSMExt) === nothing
        print(io, "\nosm_roads downloads a box that is not saved in `cache_dir` with the OpenStreetMap extension. ",
              "Run: using LightOSM")
    end
    return nothing
end

function __init__()
    Base.Experimental.register_error_hint(_extension_hint, MethodError)
end

end # module Logjam
