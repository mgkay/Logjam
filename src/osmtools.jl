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

# =============================================================================
# Joining an OpenStreetMap network to the U.S. road network (CR 19, his ruling RD3, PCV N3b)
# =============================================================================

# The classes a national road is joined to. FAF5's FCLASS, which `usrdlink` keeps, is the FHWA functional class, and
# `osm_roads` gives each OpenStreetMap highway tag its FHWA class by `OSM_CLASSES`, so the two networks share one scale:
# a national road of class c joins an OpenStreetMap road of class c - 1, c or c + 1. A national code outside 1 to 7
# (FAF5's 0, which is no FHWA class) joins any class.
_join_classes(c) = (!ismissing(c) && 1 <= c <= 7) ? (max(1, c - 1):min(7, c + 1)) : (1:7)

# The miles within which an OpenStreetMap node of an adjacent class is looked for, around the point where a national
# link meets the box edge (PCV N3b: at most 0.21 mi was needed on Lecture 4.2's two Raleigh boxes).
const _JOIN_RADIUS = 0.5

# the correspondence as a markdown table, for `joinroads`' docstring: made from `OSM_CLASSES` and `_join_classes`
function _join_class_table()
    span(r) = length(r) == 2 ? "$(first(r)), $(last(r))" : "$(first(r)) to $(last(r))"
    rows = String[]
    for c in 1:7
        tags = [t[1] for t in OSM_CLASSES if t[3] == c]
        push!(rows, "| $c | $(first(t[4] for t in OSM_CLASSES if t[3] == c)) | $(join(tags, ", ")) | $(span(_join_classes(c))) |")
    end
    push!(rows, "| any other (FAF5's 0) | none | none | $(span(_join_classes(0))) |")
    return join(["| National FCLASS | FHWA class | OpenStreetMap highway tags of that FCLASS | OpenStreetMap FCLASS joined |",
                 "|:----------------|:-----------|:------------------------------------------|:----------------------------|", rows...], "\n")
end

# The part [t0, t1] of the segment from p to q (p + t (q - p), 0 <= t <= 1) inside the closed box (x0, x1, y0, y1), by
# Liang and Barsky's clipping, or `nothing` when the segment misses the box.
function _join_clip(px, py, qx, qy, box)
    x0, x1, y0, y1 = box
    dx, dy = qx - px, qy - py
    t0, t1 = 0.0, 1.0
    for (p, q) in ((-dx, px - x0), (dx, x1 - px), (-dy, py - y0), (dy, y1 - py))
        if p == 0
            q < 0 && return nothing
        else
            r = q / p
            p < 0 ? (t0 = max(t0, r)) : (t1 = min(t1, r))
        end
    end
    return t0 <= t1 ? (t0, t1) : nothing
end

# the box as (xmin, xmax, ymin, ymax), from `mapbbox`'s form or the four numbers. It is required (his ruling RN22): an
# uncropped tile's ways run past the tile's edge, so the nodes' extent, the default until then, joined at the wrong
# places with no error (PCV N3b: 18 of 31 connectors to a road of a class not adjacent on 4.2's larger Raleigh tile).
function _join_box(box)
    b = box isa Tuple{Tuple{Real,Real},Tuple{Real,Real}} ? (box[1]..., box[2]...) : box
    (b isa Tuple{Real,Real,Real,Real} && b[1] <= b[2] && b[3] <= b[4]) ||
        throw(ArgumentError("the box bb must be ((xmin, xmax), (ymin, ymax)), as mapbbox returns it, or (xmin, xmax, ymin, ymax), " *
                            "with xmin <= xmax and ymin <= ymax; got $(repr(box))"))
    return Float64.(b)
end

const _JOIN_NODE_COLS = ("IDX", "LON", "LAT")
const _JOIN_LINK_COLS = ("SRC", "DST", "DIST", "SPEED", "FCLASS", "DIR", "NAME", "SOURCE")   # osm_roads' first eight

function _join_check(N, L, what)
    for (T, cols, t) in ((N, _JOIN_NODE_COLS, "nodes"), (L, _JOIN_LINK_COLS, "links"))
        miss = [c for c in cols if !(c in names(T))]
        isempty(miss) || throw(ArgumentError("the $what $t have no column $(join(miss, ", ")): the $t need " *
                                             "$(join(cols, ", ")), as $(what == "national" ? "usrdnode and usrdlink" : "osm_roads") return them"))
    end
    for (i, d) in enumerate(L.DIR)
        (!ismissing(d) && d in (-1, 0, 1)) ||
            throw(ArgumentError("DIR of $what link $i is $(repr(d)): 0 (two-way), 1 (from SRC to DST) or -1 (from DST to SRC)"))
    end
    for (i, (s, d)) in enumerate(zip(L.SRC, L.DST))
        (ismissing(s) || ismissing(d)) && throw(ArgumentError("$what link $i has a missing SRC or DST"))
    end
    return nothing
end

"""
    joinroads(N, L, Nosm, Losm, bb; radius = $(_JOIN_RADIUS), verbose = false) -> (dfN, dfL)

The U.S. road network with an OpenStreetMap network joined in, for routes that start or end on a city's streets and
run far beyond them: inside the box `bb` the OpenStreetMap streets replace the national roads, outside it the
national roads stay, and each national road that crosses the box edge is joined to the streets by a connector at the
edge. `N` and `L` are the national network as `usrdnode` and `usrdlink` return it (with any of their keywords), `Nosm`
and `Losm` the OpenStreetMap network as `osm_roads(bb)` returns it, and `bb` is the box given to `osm_roads`; none of
the five is changed.

1. Inside the box, every national node goes, and with it every national link with an end inside or whose straight line
   crosses the box.
2. Each national link that crossed the box edge is joined, at its end outside the box, by a connector to the
   OpenStreetMap node nearest the point where the link met the edge, on a road of the same or an adjacent class (the
   table below) that continues the link's direction of travel. When no such node lies within `radius` miles of that
   point, the connector goes to the nearest node on a road of any class that continues it, and is counted
   (`verbose`).
3. The national links left, the OpenStreetMap links and the connectors are stacked and renumbered with
   `prune_reindex`, so the nodes are numbered from 1 and the network is ready for `links2graph`.

# Arguments
- `N`, `L`: the national network: nodes with `IDX`, `LON`, `LAT`; links with `osm_roads`' first eight columns (`SRC`,
  `DST`, `DIST`, `SPEED`, `FCLASS`, `DIR`, `NAME`, `SOURCE`), which `usrdlink` has.
- `Nosm`, `Losm`: the OpenStreetMap network, the same columns.
- `bb`: the box inside which the OpenStreetMap streets replace the national roads, the box given to `osm_roads`:
  `((xmin, xmax), (ymin, ymax))` as `mapbbox` returns it, or the four numbers `(xmin, xmax, ymin, ymax)`. The
  OpenStreetMap network is cropped to it too, so that no road of either network lies where the other has one, and a
  whole tile read without `crop` joins as it does cropped to `bb`.

# Keywords
- `radius = $(_JOIN_RADIUS)`: miles, around the point where a national link meets the box edge, within which a node of
  an adjacent class is looked for.
- `verbose = false`: with `true`, report the national links and nodes dropped, the connectors made and how many of
  them went to a road of a class that is not adjacent.

# Classes
Both networks' `FCLASS` is the FHWA functional class: FAF5's, which `usrdlink` keeps (1 Interstate, 2 other freeway or
expressway, 3 other principal arterial, 4 minor arterial, 5 major collector, 6 minor collector, 7 local), and the one
`osm_roads` gives each OpenStreetMap highway tag (the table in its docstring). FAF5 also writes 0, which is no FHWA
class (its links are mostly unnamed, ramps, traffic circles and roads in Canada). A national road joins these classes:

$(_join_class_table())

# Connectors
A connector runs from the national link's node outside the box (`SRC`) to the OpenStreetMap node (`DST`). Its `DIST`
is the great circle distance between them (`dgc`), its `SPEED` the slower of the two roads' speeds, its `FCLASS` and
`NAME` the national road's, since it stands for the part of that road the box cut off, and its `SOURCE` is
`"CONNECTOR"`. It goes each way the national link can be traveled, to a node from which the OpenStreetMap road goes on
that way: into the box, a node with a link of an accepted class leading on, away from the national road; out of the
box, a node that such a link reaches from farther away. One node usually serves both ways, and the connector is
two-way (`DIR = 0`). Where the OpenStreetMap road is divided, so that each carriageway is one-way, the two ways are two
connectors, each one-way (`DIR = 1` into the box, `-1` out of it) to the carriageway of its direction, since a two-way
connector to one carriageway would lead against it. A one-way national link has its one connector.

# Returns
- `dfN`: nodes `IDX` (1 to n), `LON`, `LAT`, `SOURCE` (`"FAF5"` and `"OSM"`), the national nodes first.
- `dfL`: links with `osm_roads`' first eight columns, in its order, so `vcat` with an `osm_roads` table works; `SOURCE`
  is `"FAF5"`, `"OSM"` or `"CONNECTOR"`. The national network's other columns follow (`SIGN`, `TYPE`, `INTERSTATE`,
  `AB_TIME`, `BA_TIME`, `STFIP`, `COFIP`, `URBAN` from `usrdlink`), `missing` on the OpenStreetMap links and the
  connectors, and then any of the OpenStreetMap network's own (`MAXSPEED`, `ACCESS`, `CONDITIONAL` from a download),
  `missing` on the others. Since `AB_TIME` and `BA_TIME` are missing there, `links2graph(dfL; weight = :time)` times
  an OpenStreetMap link and a connector at `60 * DIST / SPEED` and a national link by its own times.

# Example
A national road running east through a box of streets, joined at both edges:

```jldoctest
julia> using DataFrames

julia> bb = ((-78.65, -78.55), (35.77, 35.83));

julia> N = DataFrame(IDX = 1:5, LON = [-79.4, -79.0, -78.6, -78.2, -77.8], LAT = 35.8, SOURCE = "FAF5");

julia> L = DataFrame(SRC = 1:4, DST = 2:5, DIST = 22.5, SPEED = 65, FCLASS = 1, DIR = 0, NAME = "I 40", SOURCE = "FAF5");

julia> Nosm = DataFrame(IDX = 1:5, LON = [-78.65, -78.6, -78.55, -78.6, -78.6], LAT = [35.8, 35.8, 35.8, 35.83, 35.77],
                        SOURCE = "OSM");

julia> Losm = DataFrame(SRC = [1, 2, 2, 3, 2, 4, 2, 5], DST = [2, 1, 3, 2, 4, 2, 5, 2], DIST = [2.8, 2.8, 2.8, 2.8, 2.1, 2.1, 2.1, 2.1],
                        SPEED = [65, 65, 65, 65, 25, 25, 25, 25], FCLASS = [1, 1, 1, 1, 7, 7, 7, 7], DIR = 1,
                        NAME = ["Freeway", "Freeway", "Freeway", "Freeway", "Main St", "Main St", "Main St", "Main St"], SOURCE = "OSM");

julia> dfN, dfL = joinroads(N, L, Nosm, Losm, bb);

julia> (nrow(dfN), [count(==(s), dfL.SOURCE) for s in ("FAF5", "OSM", "CONNECTOR")])
(9, [2, 8, 2])

julia> [(r.SRC, r.DST, r.DIR, round(r.DIST, digits = 1), r.SPEED) for r in eachrow(dfL) if r.SOURCE == "CONNECTOR"]
2-element Vector{Tuple{Int64, Int64, Int64, Float64, Int64}}:
 (2, 5, 0, 19.6, 65)
 (3, 7, 0, 19.6, 65)
```
"""
function joinroads(N::AbstractDataFrame, L::AbstractDataFrame, Nosm::AbstractDataFrame, Losm::AbstractDataFrame, bb;
                   radius::Real = _JOIN_RADIUS, verbose::Bool = false)
    _join_check(N, L, "national"); _join_check(Nosm, Losm, "OpenStreetMap")
    radius >= 0 || throw(ArgumentError("radius is in miles and cannot be negative; got $radius"))
    nrow(Nosm) > 0 || throw(ArgumentError("the OpenStreetMap network has no nodes"))
    nx, ny = Float64.(N.LON), Float64.(N.LAT)
    ox, oy = Float64.(Nosm.LON), Float64.(Nosm.LAT)
    bx = _join_box(bb)
    inbox(x, y) = bx[1] <= x <= bx[2] && bx[3] <= y <= bx[4]

    # the OpenStreetMap nodes in the box and the links between them; each node's links by the way they are traveled,
    # out of it and into it
    okeep = [inbox(ox[i], oy[i]) for i in eachindex(ox)]
    any(okeep) || throw(ArgumentError("no OpenStreetMap node lies in the box $bx"))
    orow = Dict(x => i for (i, x) in enumerate(Nosm.IDX))
    oa = [get(orow, x, 0) for x in Losm.SRC]; ob = [get(orow, x, 0) for x in Losm.DST]
    olink = [a > 0 && b > 0 && okeep[a] && okeep[b] for (a, b) in zip(oa, ob)]
    outs = [Int[] for _ in ox]; ins = [Int[] for _ in ox]
    for k in findall(olink)
        Losm.DIR[k] != -1 && (push!(outs[oa[k]], k); push!(ins[ob[k]], k))
        Losm.DIR[k] != 1 && (push!(outs[ob[k]], k); push!(ins[oa[k]], k))
    end

    # the national nodes inside, the links dropped, and each dropped link's ends outside: the node, the point where the
    # link meets the edge, and the ways it can be traveled from there (into the box, out of it)
    nrowof = Dict(x => i for (i, x) in enumerate(N.IDX))
    nin = [inbox(nx[i], ny[i]) for i in eachindex(nx)]
    drop = falses(nrow(L))
    ends = Tuple{Int,Int,Tuple{Float64,Float64},Bool,Bool}[]          # (link, node, edge point, into, out of)
    for k in 1:nrow(L)
        a, b = get(nrowof, L.SRC[k], 0), get(nrowof, L.DST[k], 0)
        (a > 0 && b > 0) || continue                                    # prune_reindex leaves such a link out
        t = _join_clip(nx[a], ny[a], nx[b], ny[b], bx)                  # the part of the link from a to b in the box
        t === nothing && continue
        drop[k] = true
        d = L.DIR[k]
        for (v, s, vsrc) in ((a, t[1], true), (b, t[2], false))        # a meets the edge at t0, b at t1
            nin[v] && continue
            p = (nx[a] + s * (nx[b] - nx[a]), ny[a] + s * (ny[b] - ny[a]))
            push!(ends, (k, v, p, vsrc ? d != -1 : d != 1, vsrc ? d != 1 : d != -1))
        end
    end

    # The fastest OpenStreetMap link at node u, of a class in `acc`, that continues a connector from national node v:
    # into the box, a link leaving u for a node farther from v; out of it, a link reaching u from a node farther from
    # v. 0 when u has none.
    function onward(u, v, into, acc)
        pv = (nx[v], ny[v]); du = dgc(pv, (ox[u], oy[u]))
        sp = 0
        for k in (into ? outs[u] : ins[u])
            coalesce(Losm.FCLASS[k] in acc, false) || continue
            w = oa[k] == u ? ob[k] : oa[k]
            dgc(pv, (ox[w], oy[w])) > du && (sp = max(sp, coalesce(Losm.SPEED[k], 0)))
        end
        return sp
    end
    # the OpenStreetMap nodes within r miles of the edge point p (every node when r is Inf), nearest first
    function near(p, r)
        cand = Tuple{Float64,Int}[]
        dy = r / 60; dx = r / (60 * max(cosd(p[2]), 0.05))             # a window wider than r miles, then dgc
        for u in eachindex(ox)
            okeep[u] || continue
            isfinite(r) && (abs(oy[u] - p[2]) > dy || abs(ox[u] - p[1]) > dx) && continue
            d = dgc(p, (ox[u], oy[u]))
            d <= r && push!(cand, (d, u))
        end
        return sort!(cand)
    end

    csrc = Int[]; cdst = Int[]; cdist = Float64[]; cspeed = Int[]; cclass = Int[]; cdir = Int[]
    cname = Union{Missing,String}[]
    nfall = 0; nnone = 0
    for (k, v, p, into, outof) in ends
        acc = _join_classes(L.FCLASS[k])
        cand = near(p, radius); every = nothing
        pick = Dict{Bool,Tuple{Int,Int,Bool}}()                         # way => (node, speed, by the fallback)
        for way in (true, false)
            (way ? into : outof) || continue
            u, sp = 0, 0
            for (_, x) in cand
                sp = onward(x, v, way, acc)
                sp > 0 && (u = x; break)
            end
            fb = u == 0
            if fb
                every === nothing && (every = near(p, Inf))
                for (_, x) in every
                    sp = onward(x, v, way, 1:7)
                    sp > 0 && (u = x; break)
                end
            end
            u == 0 ? (nnone += 1) : (pick[way] = (u, sp, fb))
        end
        both = haskey(pick, true) && haskey(pick, false) && pick[true][1] == pick[false][1]
        for (way, (u, sp, fb)) in sort!(collect(pick), by = first, rev = true)
            both && !way && continue
            push!(csrc, N.IDX[v]); push!(cdst, u); push!(cdist, dgc((nx[v], ny[v]), (ox[u], oy[u])))
            osp = both ? max(sp, pick[false][2]) : sp
            push!(cspeed, min(coalesce(L.SPEED[k], osp), osp)); push!(cclass, coalesce(L.FCLASS[k], 0))
            push!(cdir, both ? 0 : (way ? 1 : -1)); push!(cname, ismissing(L.NAME[k]) ? missing : String(L.NAME[k]))
            nfall += (fb || (both && pick[false][3]))
        end
    end

    # stacked: the OpenStreetMap node numbers moved past the national ones, then renumbered from 1
    off = (isempty(N.IDX) ? 0 : maximum(N.IDX)) - minimum(Nosm.IDX) + 1
    C = DataFrame(SRC = csrc, DST = Nosm.IDX[cdst] .+ off, DIST = cdist, SPEED = cspeed, FCLASS = cclass, DIR = cdir,
                  NAME = cname, SOURCE = fill("CONNECTOR", length(csrc)))
    Lo = Losm[olink, :]
    Lo.SRC = Lo.SRC .+ off; Lo.DST = Lo.DST .+ off
    No = Nosm[okeep, :]
    No.IDX = No.IDX .+ off
    dfL = vcat(L[.!drop, :], Lo, C; cols = :union)
    select!(dfL, [collect(_JOIN_LINK_COLS); setdiff(names(dfL), _JOIN_LINK_COLS)])
    dfN = vcat(N[.!nin, :], No; cols = :union)
    select!(dfN, [collect(_JOIN_NODE_COLS); setdiff(names(dfN), _JOIN_NODE_COLS)])
    if verbose
        @info "Joined: $(count(drop)) national links and $(count(nin)) national nodes dropped inside the box $bx; " *
              "$(length(csrc)) connectors for $(length(ends)) link ends ($(count(==(0), cdir)) two-way), $nfall to a road " *
              "of a class that is not adjacent (none adjacent within $radius mi of the edge)" *
              (nnone > 0 ? "; $nnone ways of travel with no OpenStreetMap road to continue them, not joined" : "")
    end
    isempty(csrc) && @warn "No national link crosses the edge of the box $bx, so the OpenStreetMap network is not joined to the national one."
    return prune_reindex(dfN, dfL; src_col = :SRC, dst_col = :DST, node_col = :IDX)
end
