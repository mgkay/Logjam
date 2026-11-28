"""
# Logjam

Logistics toolkit for facility location, transportation costing, freight road networks,
route optimization, U.S. geographic data, and GeoMakie visualizations.

The manual lists every function by topic with its docstring, and `?name` shows one. The topics
and their names:

- **Facility location:** `ufladd`, `ufldrop`, `uflxchg`, `ufl`, `pmedian`, `ala`, `wcentroid`, `randX`.
- **Transportation economics:** `rate_ltl`, `charge_tl`, `charge_ltl`, `mincharge_tl`, `mincharge_ltl`,
  `maxpayld`, `qmax_ltl`, `totlogcost`, `aggshmt`, `minTLC`; the fields of a shipment `sh` and a truck `tr`,
  which the routing functions share, are `?Logjam.shtr`.
- **Distances:** `dgc`, `dgca`, `d1`, `d2`, `dists`.
- **Road networks:** `thin`, `addconnectors`, `links2graph`, `shortestpaths`, `tracepath`, `pathroads`,
  `x2ln`, `cropnetwork`, `prune_reindex`, and `osm_roads` for OpenStreetMap (a download needs LightOSM), which
  `joinroads` joins to the U.S. road network.
- **Routing:** `segcost`, `rteTC`, `rte2loc`, `isorigin`, `rte2ldmx`, `rtesegsum`, `rte2idx`, `sh2rte`,
  `mincostinsert`, `twoopt`, `pairwisesavings`, `savings`.
- **Data and geocoding:** `usplace`, `usstate`, `uscounty`, `uscentract`, `uscenblkgrp`, `uszcta5`,
  `uszcta3`, `uscbsa`, `uscsa`, `st2fips`, `fips2st`, `faf5nodes`, `faf5links`, `usrdnode`, `usrdlink`,
  `usrdnodemap`, `loc2lonlat`, `lonlat2loc`, `lonlat`.
- **Maps** (GeoMakie): `makemap`, `mapbbox`, `aligntext`, `alloclines`, `plotroads!`, `plotroute!`, `dcf`,
  and the constants `WORLD_LIMITS`, `US_LIMITS`, `CUS_LIMITS`.
- **Display:** `prt`, `snapvals`, `thousands`.
- **Public, not exported** (called as `Logjam.name`, so a script's own function of the name does not collide):
  `scanTW`, `usstates`, the inventory measures `poissoncdf`, `pi0`, `qbar` and `poissarr`, `shtr`, the `sh` and
  `tr` contract, and the models `TSP` (with `subtours`) and `binpack`, which need JuMP and HiGHS.

## Dependencies

Always loaded: `Serialization`, `Artifacts`, `LazyArtifacts`, `Random`, `DataFrames`, `CSV`,
`DelaunayTriangulation`, `Graphs`, `SimpleWeightedGraphs`, `SparseArrays`, `Optim`.

Weak dependencies, which activate an extension when loaded: `GeoMakie` (with `CairoMakie` to render)
for maps; `Makie`, which CairoMakie loads, for `aligntext(ax, x, y, labels)`; `HTTP` and `JSON3` for
street-address geocoding with Nominatim; `LightOSM` to download an OpenStreetMap road network; `JuMP` and
`HiGHS` together for `TSP`, `binpack`, and `snapvals` on JuMP variables.
"""
module Logjam

# Import all required packages
using Artifacts
using LazyArtifacts
using Serialization
using Random: Xoshiro, AbstractRNG, default_rng, randexp
using DataFrames
using CSV
using DelaunayTriangulation
using Graphs
using SimpleWeightedGraphs
using SparseArrays
using Optim
using PrecompileTools: @setup_workload, @compile_workload

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
export usrdnode, usrdlink, usrdnodemap    # the road network derived from FAF5, its nodes, links and node map (CR 19, RD1)
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
export joinroads    # an OpenStreetMap network joined to the U.S. road network at its box's edge (CR 19, RD3; the name kept in his interface review, RN36)

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
public shtr    # the sh and tr contract (transtools.jl): its docstring is the contract, so ?Logjam.shtr shows it, and its value lists the fields (B11; the name provisional, D7)
public poissoncdf, pi0, qbar, poissarr    # the inventory measures (invtools.jl): Lectures 6.2's and 6.3's definitions, `pi0` and `qbar` with 6.2's reorder-point forms as three-argument methods; not exported, since each body is a lecture's lesson and the lectures define the names (E1, D10)
public TSP, subtours    # Lecture 5.1's TSP formulation, solved round by round, and the cycles of a successor vector (routetools.jl; CR 45): `TSP`'s method is LogjamJuMPExt's (JuMP and HiGHS), `subtours` is core's; not exported, since each body is a lecture's lesson and Lectures 5.1 and 5.3 define the names (D10)
public binpack    # Lecture 2.7's bin packing model (loctools.jl; E3): its method is LogjamJuMPExt's (JuMP and HiGHS); not exported, since the body is the lecture's lesson and Lectures 2.7 and 5.3 define the name (D10)

# Include component files
include("loctools.jl")
include("transtools.jl")
include("datatools.jl")      # the census and FAF5 tables, the FIPS codes (split in v0.3.1, A10)
include("displaytools.jl")   # prt, thousands, snapvals
include("geomtools.jl")      # alloclines
include("maptools.jl")
include("disttools.jl")
include("roadtools.jl")
include("faf5net.jl")      # the derived FAF5 road network (CR 19): its derivation (internal) and its accessors
include("routetools.jl")
include("osmtools.jl")
include("geocode.jl")
include("invtools.jl")     # the inventory measures of Lectures 6.2 and 6.3 (E1)

"""
    dcf()

Display current figure. Requires `using CairoMakie, GeoMakie`.
"""
function dcf end

# The hint a MethodError carries when a function whose methods an extension adds is called without it (C5): the map
# functions and `dcf` need GeoMakie (and CairoMakie to draw), a download needs LightOSM, `TSP` and `binpack` need JuMP
# and HiGHS together (WP2). Silent for any other error, and for these functions once their extension is loaded, when a
# MethodError is a wrong argument.
function _extension_hint(io, exc, argtypes, kwargs)
    f = exc.f === Core.kwcall ? exc.args[2] : exc.f
    if f in (makemap, plotroads!, plotroute!, dcf) && Base.get_extension(Logjam, :LogjamMapExt) === nothing
        print(io, "\n$(nameof(f)) needs the map extension, which GeoMakie loads. Run: using CairoMakie, GeoMakie")
    elseif f in (TSP, binpack) && Base.get_extension(Logjam, :LogjamJuMPExt) === nothing
        print(io, "\n$(nameof(f)) needs the optimization extension, which JuMP and HiGHS load together. ",
              "Run: using JuMP, HiGHS")
    elseif f === _osm_download && Base.get_extension(Logjam, :LogjamOSMExt) === nothing
        print(io, "\nosm_roads downloads a box that is not saved in `cache_dir` with the OpenStreetMap extension. ",
              "Run: using LightOSM")
    end
    return nothing
end

function __init__()
    Base.Experimental.register_error_hint(_extension_hint, MethodError)
end

# The precompile workload (D12, WP8 of v0.3.1): the first calls of `addconnectors`, through its local point location
# and its whole-triangulation fallback, and of `aligntext(x, y)`, compiled once while the package image is built, so a
# script's first call does not compile them. Synthetic points made here without random numbers: no network, no file
# read or written, no artifact, nothing drawn, and the results are discarded, so no function's output changes. The
# Makie extension compiles `aligntext(ax, ...)` the same way (ext/LogjamMakieExt.jl).
@setup_workload begin
    # 40 nodes on a jittered 8 x 5 grid, more than the 16 nearest the local search starts with; three links; one new
    # point inside the network and one outside its hull
    xs = [-79.0 + 0.1 * ((i - 1) % 8) + 0.013 * sin(3.0 * i) for i in 1:40]
    ys = [35.0 + 0.1 * ((i - 1) ÷ 8) + 0.011 * cos(2.0 * i) for i in 1:40]
    nodes = DataFrame(IDX = 1:40, LON = xs, LAT = ys)
    links = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], DIST = [6.0, 6.0, 6.0])
    px, py = [-78.66, -79.5], [35.21, 34.6]
    @compile_workload begin
        addconnectors(nodes, links, px, py)
        addconnectors(nodes, links, px, py; speed = 20)
        aligntext(xs[1:6], ys[1:6])
    end
end

end # module Logjam
