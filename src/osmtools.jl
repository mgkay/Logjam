# =============================================================================
# OSM Tools — OpenStreetMap integration for Logjam
# Reading a saved tile pair is here, in core. Downloading is in LogjamOSMExt, which
# loads when LightOSM is (`using LightOSM`).
# =============================================================================

# --- The one class table: OSM highway tag, typical US speed (mph), FHWA code, description ---
# Each OSM highway class has a through-route and a "_link" variant. Through-routes are the
# mainline road; links are the ramps/slip roads connecting to them (tighter geometry, lower
# posted speed). The speeds are typical US defaults, used where an OSM `maxspeed` tag is
# missing; the FHWA codes are for compatibility with the FAF5 FCLASS column.
# `OSM_SPEED_DEFAULTS`, `OSM_FCLASS` and the table in `osm_roads`' docstring are all made
# from this one table.
const OSM_CLASSES = Tuple{String,Int,Int,String}[
    ("motorway",       65, 1, "Interstate"),
    ("motorway_link",  45, 1, "Interstate ramp"),
    ("trunk",          55, 2, "Freeway/Expressway"),
    ("trunk_link",     35, 2, "Freeway ramp"),
    ("primary",        45, 3, "Principal Arterial"),
    ("primary_link",   30, 3, "Principal Arterial slip"),
    ("secondary",      35, 4, "Minor Arterial"),
    ("secondary_link", 25, 4, "Minor Arterial connector"),
    ("tertiary",       30, 5, "Major Collector"),
    ("tertiary_link",  20, 5, "Major Collector connector"),
    ("residential",    25, 7, "Local"),
    ("living_street",  15, 7, "Local (shared space)"),
    ("unclassified",   25, 6, "Minor Collector"),
    ("road",           25, 6, "Minor Collector (fallback)"),
]
const OSM_SPEED_DEFAULTS = Dict{String,Int}(c[1] => c[2] for c in OSM_CLASSES)
const OSM_FCLASS = Dict{String,Int}(c[1] => c[3] for c in OSM_CLASSES)

# the markdown table of `OSM_CLASSES`, for `osm_roads`' docstring
function _osm_class_table()
    rows = ["| $(c[1]) | $(c[2]) | $(c[3]) | $(c[4]) |" for c in OSM_CLASSES]
    return join(["| OSM highway tag | Speed (mph) | FHWA code | FHWA description |",
                 "|:----------------|------------:|----------:|:-----------------|", rows...], "\n")
end

# A box larger than this many square miles is a request the public Overpass server may refuse or be slow
# over (CR 29). The warning, its message and the docstring all say this one number.
const _OSM_AREA_WARN_MI2 = 300

# the grid, in degrees of longitude and latitude, that `osm_roads` downloads and saves by
const _OSM_SNAP_DEG = 0.05
const _OSM_SNAP_TOL = 1e-6      # in cells: an edge this close to a grid line is on it

# the area of a box (xmin, xmax, ymin, ymax) in square miles, at the box's own latitude
function _osm_area_mi2(bb::Tuple{Real,Real,Real,Real})
    xmin, xmax, ymin, ymax = bb
    mpd = dgc((0, 0), (0, 1))                          # miles in a degree of latitude
    return (ymax - ymin) * mpd * (xmax - xmin) * mpd * cosd((ymin + ymax) / 2)
end

# The columns of a saved pair and the types they are read as (CR 24): the types a download returns, so a
# table is the same either way. A pair saved before v0.3.0 has none of the last three columns of the links
# (CR 21, CR 34) and reads back exactly as it did.
const _OSM_NODE_TYPES = ["IDX" => Int, "LON" => Float64, "LAT" => Float64, "SOURCE" => String]
const _OSM_LINK_TYPES = ["SRC" => Int, "DST" => Int, "DIST" => Float64, "SPEED" => Int, "FCLASS" => Int,
                         "DIR" => Int, "NAME" => Union{Missing,String}, "SOURCE" => String,
                         "MAXSPEED" => Union{Missing,Int}, "ACCESS" => Union{Missing,String},
                         "CONDITIONAL" => Union{Missing,String}]

function _osm_read_table(path::AbstractString, spec)
    header = split(readline(path), ',')
    types = Dict{String,Type}(c => T for (c, T) in spec if c in header)
    return CSV.read(path, DataFrame; types = types, stringtype = String)
end

# one edge to the grid: an edge on a grid line stays on it (`ceil(-78.60 / 0.05)` is `ceil(-1571.9999...)`,
# which took the line above, and the area downloaded doubled), any other is rounded outward
function _osm_snap(v::Real, up::Bool)
    q = v / _OSM_SNAP_DEG
    r = round(q)
    n = abs(q - r) < _OSM_SNAP_TOL ? r : (up ? ceil(q) : floor(q))
    return n * _OSM_SNAP_DEG
end

"""
    _osm_snap_bbox(bb) → snapped_bbox

Snap bounding box to a fixed grid ($(Logjam._OSM_SNAP_DEG)° steps), rounding
mins down and maxes up. This ensures nearby queries hit the same cache tile. `bb` is
`mapbbox`'s `((xmin, xmax), (ymin, ymax))` or the four numbers `(xmin, xmax, ymin, ymax)`;
the result is `(xmin, xmax, ymin, ymax)`. An edge that lies on a grid line (to within a
millionth of a cell) stays on it, so a box on the grid is not widened by a cell, and a box
of no width or height is one tile. `public`: the data generator of Lecture 4.2 reports the
tiles of its boxes with it.
"""
function _osm_snap_bbox(bbox::Tuple{Real,Real,Real,Real})
    xmin, xmax, ymin, ymax = bbox
    x0, x1, y0, y1 = _osm_snap(xmin, false), _osm_snap(xmax, true), _osm_snap(ymin, false), _osm_snap(ymax, true)
    s = _OSM_SNAP_DEG
    return (x0, x1 > x0 ? x1 : x0 + s, y0, y1 > y0 ? y1 : y0 + s)
end
_osm_snap_bbox(bb::Tuple{Tuple{Real,Real},Tuple{Real,Real}}) = _osm_snap_bbox((bb[1]..., bb[2]...))

# the class pre-filter as a part of a file name: the readable list when short, else a checksum of it
function _osm_hwtag(highways::AbstractVector{<:AbstractString})
    s = join(highways, "+")
    length(s) <= 48 && return s
    h = UInt32(0x811c9dc5)                              # FNV-1a, 32 bits (the same on every Julia)
    for b in codeunits(s)
        h = (h ⊻ UInt32(b)) * UInt32(0x01000193)
    end
    return string(h, base = 16, pad = 8)
end

# the name of a tile, from its snapped box; a call with no class filter has the names of v0.2.8, so the
# pairs saved before are found (CR 29)
function _osm_tile(bbox::Tuple{Real,Real,Real,Real}, highways)
    xmin, xmax, ymin, ymax = _osm_snap_bbox(bbox)
    r(x) = round(x; digits=2)
    tag = "osm_w$(r(xmin))_e$(r(xmax))_s$(r(ymin))_n$(r(ymax))"
    return highways === nothing ? tag : tag * "_hw-" * _osm_hwtag(highways)
end

"""
    _osm_cache_path(bb, cache_dir; highways = nothing) → (nodes_path, links_path)

Compute deterministic cache file paths from a snapped bounding box. `bb` is `mapbbox`'s box or the
four numbers. Filenames encode the grid-snapped coordinates for human readability:
`osm_w<xmin>_e<xmax>_s<ymin>_n<ymax>_nodes.csv` and `…_links.csv`. A call with a class filter
(`highways`) adds `_hw-<classes>` to the name; a call without one has the names of v0.2.8, so a pair
saved before is still found. A pair that `osm_roads` downloads has a provenance file beside it,
`osm_…_provenance.csv`. `public`: the data generator of Lecture 4.2 reports the files of its boxes with it.
"""
function _osm_cache_path(bbox::Tuple{Real,Real,Real,Real}, cache_dir::AbstractString; highways = nothing)
    tag = _osm_tile(bbox, highways)
    return joinpath(cache_dir, tag * "_nodes.csv"), joinpath(cache_dir, tag * "_links.csv")
end
_osm_cache_path(bb::Tuple{Tuple{Real,Real},Tuple{Real,Real}}, cache_dir::AbstractString; highways = nothing) =
    _osm_cache_path((bb[1]..., bb[2]...), cache_dir; highways)
_osm_provenance_path(bbox::Tuple{Real,Real,Real,Real}, cache_dir::AbstractString; highways = nothing) =
    joinpath(cache_dir, _osm_tile(bbox, highways) * "_provenance.csv")

# the highway classes a filter names: sorted, each once, each one the class table knows
function _osm_highways(highways)
    highways === nothing && return nothing
    hw = sort(unique(String.(highways)))
    isempty(hw) && throw(ArgumentError("osm_roads: `highways` names no class; use `nothing` for every class."))
    bad = [h for h in hw if !haskey(OSM_FCLASS, h)]
    isempty(bad) || throw(ArgumentError("osm_roads: unknown highway class $(join(bad, ", ")); " *
                                        "the classes are $(join(sort(collect(keys(OSM_FCLASS))), ", "))."))
    return hw
end

"""
    osm_roads(bb; cache_dir = nothing, crop = false, force_download = false, verbose = false,
              highways = nothing) → (dfN, dfL)

The drivable roads of OpenStreetMap inside a bounding box, as Logjam's two network tables: read from a
saved pair in `cache_dir` if one is there, else downloaded from Overpass, the public OpenStreetMap
server. Reading a saved pair needs nothing but Logjam; a download needs
`using LightOSM`.

# Arguments
- `bb`: The box `((xmin, xmax), (ymin, ymax))` where x = longitude, y = latitude, as returned by
  `mapbbox`. The four numbers `(xmin, xmax, ymin, ymax)` are also accepted.

# Keywords
- `cache_dir = nothing`: A folder. A pair of CSV files for the box is read from it when it holds one,
  and saved there, with a provenance file, after a download. With `nothing`, nothing is read or written.
- `crop = false`: With `true`, the network is cropped to the box asked for, as
  `cropnetwork(dfN, dfL, bb)` does; otherwise it is the whole tile (see the notes).
- `force_download = false`: With `true`, a saved pair is ignored and the box is downloaded again.
- `verbose = false`: With `true`, say what is read, downloaded and saved.
- `highways = nothing`: With a vector of OpenStreetMap highway classes of the table below, such as
  `["motorway", "trunk"]`, download only roads of those classes; the saved pair's name then carries
  them. `nothing` downloads every drivable class.

# Returns
- `dfN::DataFrame`: Nodes with columns IDX (Int), LON (Float64), LAT (Float64), SOURCE (String).
- `dfL::DataFrame`: Links with columns SRC (Int), DST (Int), DIST (Float64, miles), SPEED (Int, mph),
  FCLASS (Int), DIR (Int), NAME (Union{Missing,String}), SOURCE (String). A download adds MAXSPEED
  (Union{Missing,Int}, the posted speed in mph, `missing` where none is posted), ACCESS (Union{Missing,String},
  the access tag that decides for a car) and CONDITIONAL (Union{Missing,String}, its conditional rule); a
  pair saved before v0.3.0 has no such columns and reads back without them. The types are the same from a
  download as from a saved pair. `NAME` is `missing` where OpenStreetMap has no name.

# Speed and class
`SPEED` is the posted `maxspeed` of the road where OpenStreetMap has one (`MAXSPEED`; a number with no
unit is read as km/h, as OpenStreetMap does, and `none`, `signals` or a list is not a speed), and
otherwise the typical US speed of the road's class. `FCLASS` is the FHWA functional class that
corresponds to the class. Both come from one table:

$(_osm_class_table())

A road of a class not in the table (a `crossing`, say) is not downloaded, and neither is a road whose
most specific access tag for a car (`motorcar`, `motor_vehicle`, `vehicle`, `access`, in that order) is
`no`, `private`, `agricultural`, `forestry`, `emergency` or `psv`; a conditional rule
(`vehicle:conditional` and the like) is kept in `CONDITIONAL`, not applied. Nodes that cannot reach the
rest of the network by the one-way links that are left, or be reached from it, are dropped with their
links, so every node reaches every other.

# Notes
- Downloads and saves whole tiles of a grid of $(Logjam._OSM_SNAP_DEG)° of longitude and latitude, every tile
  the box touches, so that nearby boxes share a download; the network returned is that tile unless
  `crop = true`.
- The saved pair is `osm_w<xmin>_e<xmax>_s<ymin>_n<ymax>_nodes.csv` and `…_links.csv`, named for the
  tile. The provenance file beside it, `osm_…_provenance.csv`, records the box, the fetch time, the
  data's timestamp, the class filter and the licence notice (© OpenStreetMap contributors, ODbL).
  Reading a pair does not need it.
- A box of more than $(Logjam._OSM_AREA_WARN_MI2) square miles draws a warning before a download: the public
  server may refuse it or be slow. The request declares a time and memory limit sized to the box, and
  is tried again after a pause when the server says it is busy.
- Coordinates are (LON, LAT), as everywhere in Logjam.

# Example
Lecture 4.2, Code block 2: the box around two buildings and the streets in it, read from a saved
pair (here a tiny one written first; the lecture's is the copy of Raleigh's streets in its `data`
folder).

```jldoctest
julia> using DataFrames, CSV

julia> bb = mapbbox([-78.6758, -78.6696], [35.7706, 35.7876]; xexpand = 2, yexpand = 0.5);

julia> dir = mktempdir();

julia> np, lp = Logjam._osm_cache_path(bb, dir);

julia> CSV.write(np, DataFrame(IDX = [1, 2], LON = [-78.67, -78.668], LAT = [35.78, 35.781], SOURCE = "OSM"));

julia> CSV.write(lp, DataFrame(SRC = [1], DST = [2], DIST = [0.1], SPEED = [25], FCLASS = [7], DIR = [1], NAME = ["Main St"], SOURCE = ["OSM"]));

julia> dfN, dfL = osm_roads(bb; cache_dir = dir, crop = true);

julia> (nrow(dfN), nrow(dfL), eltype(dfL.NAME))
(2, 1, Union{Missing, String})
```
"""
function osm_roads(bb::Tuple{Tuple{Real,Real},Tuple{Real,Real}};
                   cache_dir::Union{Nothing,AbstractString} = nothing, crop::Bool = false,
                   force_download::Bool = false, verbose::Bool = false,
                   highways::Union{Nothing,AbstractVector{<:AbstractString}} = nothing)
    (xmin, xmax), (ymin, ymax) = bb
    xmin <= xmax && ymin <= ymax ||
        throw(ArgumentError("osm_roads: the box must be ((xmin, xmax), (ymin, ymax)) with xmin <= xmax and ymin <= ymax."))
    hw = _osm_highways(highways)
    flat = (Float64(xmin), Float64(xmax), Float64(ymin), Float64(ymax))
    local dfN, dfL
    saved = false
    if cache_dir !== nothing && !force_download
        np, lp = _osm_cache_path(flat, cache_dir; highways = hw)
        if isfile(np) && isfile(lp)
            verbose && @info "Loading cached OSM data: $np"
            dfN = _osm_read_table(np, _OSM_NODE_TYPES)
            dfL = _osm_read_table(lp, _OSM_LINK_TYPES)
            saved = true
        end
    end
    if !saved
        tile = _osm_snap_bbox(flat)
        area = _osm_area_mi2(tile)
        area > _OSM_AREA_WARN_MI2 &&
            @warn "Large bounding box (~$(round(Int, area)) sq mi, over $(_OSM_AREA_WARN_MI2)). " *
                  "Overpass query may be slow or fail. Consider reducing the region size."
        dfN, dfL, prov = _osm_download(tile; highways = hw, verbose = verbose)
        if cache_dir !== nothing
            mkpath(cache_dir)
            np, lp = _osm_cache_path(flat, cache_dir; highways = hw)
            CSV.write(np, dfN)
            CSV.write(lp, dfL)
            pp = _osm_provenance_path(flat, cache_dir; highways = hw)
            prov = ["logjam" => string(pkgversion(Logjam)); prov]
            CSV.write(pp, DataFrame(KEY = first.(prov), VALUE = last.(prov)))
            verbose && @info "  Cached: $np, $lp, $pp"
        end
    end
    return crop ? cropnetwork(dfN, dfL, bb) : (dfN, dfL)
end

# The Overpass download of one tile, `_osm_download(tile; highways, verbose) -> (dfN, dfL, provenance)`: declared here,
# its method is LogjamOSMExt's (LightOSM), and without the extension a call is a MethodError that says what to load.
function _osm_download end

osm_roads(bb::Tuple{Real,Real,Real,Real}; kwargs...) =
    osm_roads(((bb[1], bb[2]), (bb[3], bb[4])); kwargs...)
