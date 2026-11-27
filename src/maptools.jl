# MapTools - Functions for creating geographical maps using the Makie ecosystem

"""
    WORLD_LIMITS

A constant defining the geographical limits for a world map projection.

- The first tuple specifies the longitude limits in degrees: `(-180, 180)`.
- The second tuple specifies the latitude limits in degrees: `(-75, 75)`.

```jldoctest
WORLD_LIMITS

# output

((-180, 180), (-75, 75))
```
"""
const WORLD_LIMITS = ((-180, 180), (-75, 75))

"""
    US_LIMITS

A constant defining the geographical limits for a map projection of the United States,
including Alaska and Hawaii (the longitude range reaches to `-180` to cover the Aleutians).

- The first tuple specifies the longitude limits in degrees: `(-180, -65)`.
- The second tuple specifies the latitude limits in degrees: `(15, 72)`.

```jldoctest
US_LIMITS

# output

((-180, -65), (15, 72))
```
"""
const US_LIMITS = ((-180, -65), (15, 72))

"""
    CUS_LIMITS

A constant defining the geographical limits for a map projection of the contiguous United States (excluding Alaska and Hawaii).

- The first tuple specifies the longitude limits in degrees: `(-125, -65)`.
- The second tuple specifies the latitude limits in degrees: `(24, 50)`.

```jldoctest
CUS_LIMITS

# output

((-125, -65), (24, 50))
```
"""
const CUS_LIMITS = ((-125, -65), (24, 50))

# Cache for geographic data (loaded on first use)
const _countries_cache = Ref{Union{Nothing, Tuple}}(nothing)
const _usstates_cache = Ref{Union{Nothing, Tuple}}(nothing)

"""
    countries() -> Tuple{Vector, Vector}

Load and cache country border coordinates from serialized data.
"""
function countries()
    if isnothing(_countries_cache[])
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        _countries_cache[] = open(deserialize, joinpath(data_dir, "countries.jls"))
    end
    return _countries_cache[]
end

"""
    usstates() -> Tuple{Vector, Vector}

Load and cache U.S. state border coordinates from serialized data.

Returns the polylines of the state borders as two vectors `(x, y)` of longitude and latitude, the borders
separated by `NaN`, to be drawn with `lines!(ax, usstates()...)`: the call Lecture 5.1 makes to draw the borders on a
plain axis (`Logjam.usstates()`) and four of the Lecture 2.2 figure generators make. The file is read once per
session and each call returns a copy, so the vectors may be changed freely. Not exported, so the name does not
collide with a script's own; `public`, reached as `Logjam.usstates()`. (The state table of the census ladder is
[`usstate`](@ref), a different function.)

# Example
```jldoctest
x, y = Logjam.usstates()
(length(x) == length(y), count(isnan, x) == count(isnan, y))

# output

(true, true)
```
"""
function usstates()
    if isnothing(_usstates_cache[])
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        _usstates_cache[] = open(deserialize, joinpath(data_dir, "usstates.jls"))
    end
    return map(copy, _usstates_cache[])
end

# makemap's argument types: points (or none) and the box `mapbbox` returns
const _MapPoints = Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}}
const _MapBox = Tuple{Tuple{<:Real, <:Real}, Tuple{<:Real, <:Real}}

# What a layer keyword may be, checked here (core) so that every method reports the same error; the drawing is the
# extension's.
const _MAP_ROAD_KEYS = (:color, :alpha, :linewidth)
const _MAP_BORDER_KEYS = (:color, :linewidth)

function _maplayer(name, value, keys)
    value isa NamedTuple || return value
    bad = [k for k in Base.keys(value) if k ∉ keys]
    isempty(bad) || throw(ArgumentError("makemap's `$name` takes $(join(("`$k`" for k in keys), ", ", " and ")) " *
                                        "but not $(join(("`$k`" for k in bad), ", ", " or "))"))
    return value
end

function _maproads(roads, doRoadbkgd)
    if doRoadbkgd !== nothing
        roads === nothing || throw(ArgumentError("makemap takes `roads` or its deprecated alias `doRoadbkgd`, not both"))
        doRoadbkgd isa Bool || throw(ArgumentError("`doRoadbkgd` is true or false; got $(repr(doRoadbkgd))"))
        Base.depwarn("makemap's `doRoadbkgd` is deprecated: `doRoadbkgd = false` is `roads = false`, and " *
                     "`doRoadbkgd = true` is `roads = :auto`, the default.", :makemap)
        return doRoadbkgd ? :auto : false
    end
    (roads === nothing || roads === :auto) && return :auto
    roads === false && return false
    roads isa NamedTuple && return _maplayer("roads", roads, _MAP_ROAD_KEYS)
    throw(ArgumentError("makemap's `roads` is :auto, false or a NamedTuple of `color`, `alpha` and `linewidth`; got $(repr(roads))"))
end

function _mapborders(borders)
    (borders === true || borders === false) && return borders
    borders isa NamedTuple && return _maplayer("borders", borders, _MAP_BORDER_KEYS)
    throw(ArgumentError("makemap's `borders` is true, false or a NamedTuple of `color` and `linewidth`; got $(repr(borders))"))
end

# `size` is the figure's, so only a method that creates the figure takes it: (width, height) or (width, :auto)
function _mapsize(size, target)
    if target !== nothing
        size === nothing || throw(ArgumentError("`size` is the figure's, and makemap(cell, ...) draws into a figure that already " *
                                                "exists: give `Figure(size = ...)` the size, or `resize!` it"))
        return nothing
    end
    size === nothing && return (600, 450)
    (size isa Tuple{Real, Real} && all(>(0), size) && all(isfinite, size)) && return (round(Int, size[1]), round(Int, size[2]))
    (size isa Tuple{Real, Symbol} && size[1] > 0 && isfinite(size[1]) && size[2] === :auto) && return (round(Int, size[1]), :auto)
    throw(ArgumentError("makemap's `size` is (width, height) or (width, :auto), in pixels; got $(repr(size))"))
end

# `xexpand` and `yexpand` are keywords of the box methods only to be refused: the box is drawn as given
function _nobboxexpand(who, xexpand, yexpand)
    for (k, v) in ((:xexpand, xexpand), (:yexpand, yexpand))
        v === nothing || throw(ArgumentError("$who draws the box as given and takes no `$k`; expand the box first, with " *
                                             "`mapbbox(bb; $k = ...)`, or pass the box's x and y to makemap with `$k`"))
    end
end

# S22: how far across a map is decides what `roads = :auto` draws. The measure is Lecture 2.5's `extent`
# (2-loc-5.qmd:160-164) on the box as drawn, the one `makemap` hands the axis after `xexpand` and `yexpand`: the larger
# of the box's north-south and east-west great-circle extents through its center, in miles (`dgc`'s default unit). A map is
# close when that is at most `_MAP_CLOSE_MILES`, 2.5's `CLOSE` and `<=`; the regions `:World`, `:US` and `:CUS` are
# never close, by their size.
const _MAP_CLOSE_MILES = 150.0

function _mapextent(box)
    (x0, x1), (y0, y1) = box
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    return max(dgc([xm, y0], [xm, y1]), dgc([x0, ym], [x1, ym]))
end

_mapisclose(box) = _mapextent(box) <= _MAP_CLOSE_MILES

# CR 19, N4 (his answer to Q2, MakePlan D8): which tier of the road network `roads = :auto` draws on a map of `box`, the
# box as drawn. The close test comes first; the wider tiers are the box's latitude span in degrees, as v0.3.0's
# Interstate layer measured it, so a continental map still draws its Interstates. They nest in that order (150 miles is
# about 2.2 degrees of latitude).
const _MAP_REGIONAL_LATSPAN = 10.0
const _MAP_NATIONAL_LATSPAN = 30.0

function _maproadtier(box)
    _mapisclose(box) && return :close
    latspan = abs(box[2][2] - box[2][1])
    latspan <= _MAP_REGIONAL_LATSPAN && return :regional
    latspan <= _MAP_NATIONAL_LATSPAN && return :national
    return :none
end

# makemap, plotroads!, plotroute! and dcf are declared here, with their docstrings, and given their methods by the map
# extension (ext/LogjamMapExt.jl, which GeoMakie triggers), so that the manual builds and `?makemap` answers without
# Makie. Called without the extension, each is a MethodError with a hint (`__init__` in Logjam.jl). The argument
# checks above are core's, so that every method reports the same error; the drawing is the extension's.

"""
    makemap(x = nothing, y = nothing; region = :World, xexpand = 0.3, yexpand = 0.1, roads = :auto, borders = true,
            size = (600, 450), showgrid = false) -> (; fig, ax, layers)

Create a map of a predefined region or of the box around a set of longitude-latitude points, in Mercator projection with
`GeoMakie`, with roads, U.S. state borders and country borders behind it. Requires
`using CairoMakie, GeoMakie`. The box alone is `makemap(bb)`; a map in a cell of a figure that exists is
`makemap(cell, x, y)` (see their docstrings).

# Arguments
- `x`, `y`: at least two longitudes and two latitudes, or `nothing` for a predefined `region`. The map shows their box
  (`mapbbox`), made `xexpand` and `yexpand` times larger on each side.
- `region`: with no `x` and `y`, `:World` (default), `:US` or `:CUS`, the continental U.S.
- `xexpand`, `yexpand`: the fraction of the box's width and height added on each side. Defaults `0.3` and `0.1`.
- `roads`: the road layer. `:auto` (default) draws one of four tiers by the size of the box as drawn (after `xexpand`
  and `yexpand`), each cropped to the map (every link whose segment meets the box, so the roads run to the frame), in
  `:steelblue`. (1) A map **150 miles across or less**, the larger of its north-south and east-west great-circle
  extents through the center of the box, in miles, draws the FAF5 network (`faf5links`) at opacity 0.3, the classes
  (`FCLASS` 1 to 5, as `plotroads!` groups them) at widths 1.4, 1.0, 0.7, 0.5 and 0.3, the Interstate on top; no
  connectors, and no ramps, since an interchange's ramps pile up into a blotch at this scale. A ramp is a link that the
  rule `faf5net` applies to FAF5 calls one: its name marks one (a ramp, a collector-distributor lane in any of its
  spellings, a turn lane, or "X TO Y" on a one-way link), or it belongs to a cluster of unnamed one-way links, within
  three quarters of a mile of each other, that joins two routes at an interchange. (2) A larger map that spans **at
  most 10 degrees of latitude** draws Logjam's U.S. road network (`usrdlink`, derived from FAF5, with no ramps and one
  line for each divided road), its classes 1 to 3 (Interstates, other freeways and expressways, other principal
  arterials), labeled "Major Roads", the Interstate at opacity 0.32 and width 0.7, wider and more opaque than v0.3.0's
  two overlapping carriageways each were so that one line reads as they did, and classes 2 and 3 thinner, and so
  fainter, beneath it (widths 0.3 and 0.15 times the Interstate's), the Interstate on top. (3) A map
  that spans **at most 30 degrees** draws that network's Interstates (`INTERSTATE`), labeled "Interstate Roads", at
  opacity and width 0.32 and 0.85 up to 20 degrees, 0.3 and 0.8 up to 30. (4) A map of more than 30 degrees draws no
  roads. `region = :World` and `:US` draw none and `:CUS` the Interstates. `false` draws no roads. A `NamedTuple` of
  `color`, `alpha` (the opacity, which multiplies a color's own) and `linewidth` restyles whichever tier `:auto` would
  draw: `color` replaces the hue, `alpha` the opacity, and `linewidth` the Interstate's width, the other classes of (1)
  and (2) keeping their ratios to it.
- `borders`: the border layers, in blue at width 0.75. `true` (default) draws the U.S. state borders and the country borders
  that the map's place calls for (below); `false` draws neither; a `NamedTuple` of `color` and `linewidth` draws the same
  layers with those attributes.
- `size`: the figure's size in pixels, `(width, height)`. `(width, :auto)` takes the height that fits the map: `width`
  times the height-to-width ratio of the map's projected limits, plus 10, as Lecture 5.3's `fitmap!` fits it. The default,
  `(600, 450)`, is Makie's own.
- `showgrid`: draw grid lines and coordinate labels. Default `false`.

# Returns
A `NamedTuple` `(; fig, ax, layers)`: the `Figure`, the `GeoAxis`, and `layers`, a `NamedTuple` of the base-layer plots
drawn, each a `Lines`: `roads`, `states` and `countries`, `nothing` for a layer not drawn. `roads` of a map 150 miles
across or less is itself a `NamedTuple` of the network's five `Lines`, `class1` (the Interstate) to `class5`, `nothing`
for a class with no link in the map; on tiers (2) and (3) it is one `Lines`, labeled "Major Roads" on tier (2) and
"Interstate Roads" on tier (3), with a width for each point on tier (2) (its class's), and empty where the map holds no
road of the network. `fig, ax = makemap(...)`
takes the first two, as it takes the first two of any tuple.

# Behavior
- A map that lies within the continental U.S. limits (`CUS_LIMITS`) is drawn with U.S. state borders only, one within the U.S.
  limits (`US_LIMITS`) with state borders, dashed and half as opaque, and country borders, and any other with country
  borders only. `region = :CUS` is drawn like the first, `:US` like the second and `:World` like the third.
- Draws with the active Makie backend and leaves its settings (`px_per_unit`, `visible`, the image type) as the caller set
  them, so `CairoMakie.activate!(px_per_unit = 2)` before the call is all a map needs.
- `doRoadbkgd` is a deprecated alias: `doRoadbkgd = false` is `roads = false` and `doRoadbkgd = true` is `roads = :auto`. It
  warns only under `--depwarn=yes`, and giving it together with `roads` throws an `ArgumentError`. `roadcolor`, `roadalpha`
  and `maxroadlatspan` are gone: `roadcolor = :steelblue, roadalpha = 0.5` is `roads = (; color = :steelblue, alpha = 0.5)`.

Roads are FAF5's, or derived from FAF5 (`usrdlink`): https://geodata.bts.gov/datasets/usdot::freight-analysis-framework-faf5-network-links/about. U.S. state borders are derived from https://raw.githubusercontent.com/PublicaMundi/MappingAPI/master/data/geojson/us-states.json. Country borders are derived from https://github.com/PublicaMundi/MappingAPI/blob/master/data/geojson/countries.geojson.

# Examples
Lecture 2.3 draws the world, the continental U.S. and the box around a set of points (`df.LON`, `df.LAT`; here three
points set by hand), each its own call:

```julia-repl
using CairoMakie, GeoMakie
fig, ax = makemap()                          # the world
fig, ax = makemap(region = :CUS)             # the continental U.S.
x = [-84.0, -83.0, -82.0]; y = [41.0, 42.0, 43.0]
fig, ax = makemap(x, y; xexpand = 0.1)       # the points' box, enlarged a tenth on each side
scatter!(ax, x, y, markersize = 12, color = :red)
```

Lecture 4.1's Code block 34 draws the Interstates around Raleigh with no road layer behind them and resizes the figure
afterward; the call is now one line:

```julia
# was: fig, ax = makemap(rN.LON, rN.LAT; doRoadbkgd = false, xexpand = 0.05, yexpand = 0.05); resize!(fig, 400, 420)
fig, ax = makemap(rN.LON, rN.LAT; roads = false, xexpand = 0.05, yexpand = 0.05, size = (400, 420))
```

Lecture 5.3's Code block 7 draws the map around the points with `basemap`, restyles its borders gray, and fits the
figure's height to the map with `fitmap!`; with `borders` and `size` that is one call:

```julia
fig, ax = makemap(x, y; xexpand = 0.02, yexpand = 0.12, roads = false,
                  borders = (; color = (ink, 0.45), linewidth = 1.5), size = (600, :auto))
```

README Example 2 restyles the road layer:

```julia
fig, ax = makemap(x, y; roads = (; color = :steelblue, alpha = 0.5))
```

Lecture 2.5's `dotmap` (`2-loc-5.qmd:166-185`) draws the FAF5 network behind a metropolitan map by hand: it switches the
road layer off with `doRoadbkgd = !close` where `close` is 150 miles across or less, then draws `plotroads!` over the map
in `:steelblue` with each stroke's opacity reset. A map that close now draws the network itself, in that hue and below
opacity 0.35:

```julia
# was: fig, ax = makemap(lon, lat; xexpand = 0.02, yexpand = 0.02, doRoadbkgd = !close); plotroads!(ax, faf5nodes(), faf5links())
fig, ax, layers = makemap(lon, lat; xexpand = 0.02, yexpand = 0.02)   # layers.roads.class1 is the Interstate's Lines
```
"""
function makemap end

"""
    makemap(bb; region = :World, roads = :auto, borders = true, size = (600, 450), showgrid = false) -> (; fig, ax, layers)
    makemap(cell, bb; region = :World, roads = :auto, borders = true, showgrid = false) -> (; fig, ax, layers)

Create a map of exactly the box `bb = ((xmin, xmax), (ymin, ymax))`, the shape `mapbbox` returns, with no expansion.
`makemap(bb; ...)` is `makemap(bb[1], bb[2]; xexpand = 0, yexpand = 0, ...)` and takes the keywords `makemap(x, y)` takes
(`roads`, `borders`, `size`, `showgrid`, `region`, and the deprecated `doRoadbkgd`), with the same return; `makemap(cell, bb)`
draws it in a cell. `xexpand` and `yexpand` are not keywords of these methods (`mapbbox` expands a box:
`makemap(mapbbox(x, y; xexpand = 0.3))`) and throw an `ArgumentError`. `roads = :auto` draws one of four tiers by the
box's size, as `makemap(x, y)` says, each cropped to the box: the FAF5 network when it is 150 miles across or less;
classes 1 to 3 of Logjam's U.S. road network (`usrdlink`) when it is larger and spans at most 10 degrees of latitude;
that network's Interstates up to 30 degrees; no roads beyond that. `layers.roads` is then a `NamedTuple` of the
network's five `Lines` (`class1` to `class5`) or one `Lines`.

# Example
Lecture 4.2 draws the whole of a box it has just downloaded, with no roads behind it and no margin:

```julia
using CairoMakie, GeoMakie
bb = ((-78.688, -78.657), (35.762, 35.796))    # Lecture 4.2's first box, as `mapbbox` returns it
fig, ax = makemap(bb; roads = false)           # was makemap(bb[1], bb[2]; doRoadbkgd = false, xexpand = 0, yexpand = 0)
```

Lecture 2.5's `dotmap` (`2-loc-5.qmd:170`) draws the map around its points with a fiftieth of margin on each side, and
the FAF5 network behind it where the points are 150 miles across or less; as a box, with the default road layer:

```julia
fig, ax, layers = makemap(mapbbox(lon, lat; xexpand = 0.02, yexpand = 0.02))   # the network, if the box is that close
```
"""
makemap(bb::_MapBox)

"""
    makemap(cell, x, y; region = :World, xexpand = 0.3, yexpand = 0.1, roads = :auto, borders = true, showgrid = false) -> (; fig, ax, layers)
    makemap(cell; region = :World, roads = :auto, borders = true, showgrid = false) -> (; fig, ax, layers)

Draw a map in `cell`, a position in the layout of a figure that exists, such as `fig[1, 2]` or `fig[2, 1:2]`, so that
one figure holds several maps. The keywords are those of `makemap(x, y)` except `size`, which the figure has already
(`Figure(size = ...)` or `resize!`) and which throws an `ArgumentError` here. `makemap(cell; region = ...)` draws a
predefined region.

The return is `(; fig, ax, layers)` as for `makemap(x, y)`, where `fig` is the figure that holds `cell`
(`Makie.get_figure(cell)`), the same for every map drawn into it, and `ax` and `layers` are those of the map in `cell`.

# Example
Lecture 5.1's Code block 7 draws three frames of one figure, each on plain axes with the state borders added by hand; each
frame is a map in its cell:

```julia
(xl, yl) = mapbbox(df.LON, df.LAT; xexpand = 0.14, yexpand = 0.16)
fig = Figure(size = (687, 640))
cells = [fig[1, 1], fig[1, 2], fig[2, 1:2]]
for k in 1:3
    makemap(cells[k], ((xl[1] - 0.3, xl[2] + 0.3), yl); roads = false, borders = (; color = (bluec, 0.6)))
end
```
"""
makemap(cell, x::_MapPoints, y::_MapPoints)

"""
    aligntext(x::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}},
              y::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}};
              offsetamt::Real=1, mindistratio::Real=1.5, idx=nothing) -> Pair, Pair

Determines text alignment and offset positions for given points.

This function attempts to calculate the best alignment and offset positions for text labels based on the spatial arrangement of the points provided. It is particularly useful for positioning labels or annotations on a plot, ensuring that they do not overlap and remain readable. The function can handle various input formats for the points, including scalars, vectors, and tuples, and adjusts the text position to try to avoid collisions with nearby labels or graphical elements.

# Arguments
- `x`: Scalar, vector, or tuple representing the x-coordinates for the points.
- `y`: Scalar, vector, or tuple representing the y-coordinates for the points.
- `offsetamt`: Scalar value specifying the amount of offset to apply to the text labels. This controls the distance by which the text is shifted away from the point. Default is `1`.
- `mindistratio`: Scalar value that sets the minimum distance ratio used to decide the best alignment for text labels relative to adjacent points. Default is `1.5`.
- `idx`: Optional index or index vector. When provided, alignment is computed using all points but only results for the specified indices are returned. Useful for labeling a subset of points (e.g., a depot) while considering all points for placement.

# Returns
- `:align => alignout`: A `Pair` where `:align` is associated with an array of 2-tuples representing horizontal and vertical alignment symbols (e.g., `(:left, :bottom)`, `(:center, :top)`) corresponding to each point.
- `:offset => offsetout`: A `Pair` where `:offset` is associated with an array of 2-tuples representing the x and y offsets to be applied to the text labels for each point.

# Behavior
- **Single Point**: If only one point is provided, the function returns a default alignment (`:left`, `:bottom`) with the specified `offsetamt`.
- **Two Points**: If two points are provided, the function calculates the angle between the points and determines the best alignment and offset in both directions.
- **Three or More Points**: For three or more points, the function uses Delaunay triangulation to determine the optimal alignment by analyzing the angles and distances between adjacent points. It ensures that labels do not overlap and are well-positioned relative to each other.

# Example
A single point gets the default lower-left placement; multiple points return per-point
alignment/offset vectors (the output is discrete symbols and integer offsets):

```jldoctest
aligntext(0.0, 0.0)

# output

(:align => (:left, :bottom), :offset => (1, 1))
```

In a plot, splat the result straight into `text!` — for example, labeling the NC cities
over 100,000 population:

```julia
using CairoMakie, GeoMakie, DataFrames
df = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
x, y, name = df.LON, df.LAT, df.NAME
fig, ax = makemap(x, y)
scatter!(ax, x, y)
text!(ax, x, y, text=name; aligntext(x, y)...)  # note ";" and "..." for splatting
display(fig)
```
"""
function aligntext(x::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}},
                   y::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}};
                   offsetamt::Real=1, mindistratio::Real=1.5, idx=nothing)

    # Convert scalars to single-element vectors for consistent handling
    if x isa Real
        x = [x]
    end
    if y isa Real
        y = [y]
    end

    pts = [(x, y) for (x, y) in zip(x, y)]
    arcang(xy0, xy1) = atand(xy1[2] - xy0[2], xy1[1] - xy0[1])
    d2(xy0, xy1) = sqrt((xy1[1] - xy0[1])^2 + (xy1[2] - xy0[2])^2)

    if length(pts) == 1
        return (:align => (:left, :bottom), :offset => (offsetamt, offsetamt))
    else
        # Handle duplicate points: group by unique coordinates
        # Maps each unique coordinate to list of original indices
        coord_to_indices = Dict{Tuple{Float64,Float64}, Vector{Int}}()
        for (i, pt) in enumerate(pts)
            key = (Float64(pt[1]), Float64(pt[2]))
            if haskey(coord_to_indices, key)
                push!(coord_to_indices[key], i)
            else
                coord_to_indices[key] = [i]
            end
        end

        # Build unique points list and mapping
        unique_pts = Tuple{Float64,Float64}[]
        unique_idx_to_original = Int[]  # First original index for each unique point
        for (coord, indices) in coord_to_indices
            push!(unique_pts, coord)
            push!(unique_idx_to_original, first(indices))
        end
        n_unique = length(unique_pts)

        # Compute base angles for unique points
        base_angles = zeros(Float64, n_unique)

        if n_unique == 1
            # All points at same location - distribute evenly around compass
            base_angles[1] = 45.0  # Start at NE
        elseif n_unique == 2
            # Two unique locations
            ang = arcang(unique_pts[1], unique_pts[2])
            base_angles[1] = ang
            base_angles[2] = ang - 180
        else
            # Three or more unique points - use triangulation
            tri = triangulate(unique_pts; rng = _tri_rng())
            for ui in 1:n_unique
                IJ = get_adjacent2vertex(tri, ui)
                nbrs = collect(reduce(union, [Set(t) for t in IJ]))
                filter!(j -> j > 0, nbrs)   # Remove ghost vertices
                d = [d2(unique_pts[ui], unique_pts[j]) for j in nbrs]
                sidx = sortperm(d)
                d, nbrs = d[sidx], nbrs[sidx]
                if (d[2]/d[1] > mindistratio) ||
                    (length(d) > 2 ? (d[3]/(d[1] + d[2]) > mindistratio) : false)
                    base_angles[ui] = arcang(unique_pts[ui], unique_pts[nbrs[1]]) - 180
                else
                    ang = [arcang(unique_pts[ui], unique_pts[j]) for j in nbrs]
                    ang = sort(ang)
                    δ = diff([-180; ang; 180])
                    δ = [δ[2:end-1]; δ[1] + δ[end]]
                    idx_max = argmax(δ)
                    base_angles[ui] = ang[idx_max] + δ[idx_max]/2
                end
            end
        end

        # Create mapping from unique coord to its base angle
        coord_to_base_angle = Dict{Tuple{Float64,Float64}, Float64}()
        for (ui, coord) in enumerate(unique_pts)
            coord_to_base_angle[coord] = base_angles[ui]
        end

        # Assign alignments to all original points
        # For duplicates at same location, distribute evenly starting from base angle
        alignout = Vector{Tuple{Symbol,Symbol}}(undef, length(pts))
        offsetout = Vector{Tuple{Real,Real}}(undef, length(pts))

        for (coord, indices) in coord_to_indices
            base_ang = coord_to_base_angle[coord]
            n_at_loc = length(indices)
            angle_step = 360.0 / n_at_loc

            for (k, orig_idx) in enumerate(indices)
                # Distribute labels evenly around the base angle
                ang = mod(base_ang + (k - 1) * angle_step, 360.0)
                align, offset = bestfit(ang, offsetamt)
                alignout[orig_idx] = align
                offsetout[orig_idx] = offset
            end
        end

        if isnothing(idx)
            return :align => alignout, :offset => offsetout
        else
            return :align => alignout[idx], :offset => offsetout[idx]
        end
    end
end

"""
    mapbbox(x::Union{AbstractVector{<:Real}, Tuple{Vararg{Real}}},
            y::Union{AbstractVector{<:Real}, Tuple{Vararg{Real}}};
            xexpand::Real=0.0, yexpand::Real=0.0) -> Tuple

Calculates the bounding box for a set of geographic coordinates, with optional expansion along the x and y axes.

# Arguments
- `x`: A vector or tuple of x-coordinates (longitude values).
- `y`: A vector or tuple of y-coordinates (latitude values).
- `xexpand`: A `Float64` value (default = `0.0`) specifying the fractional expansion of the bounding box along the x-axis. For example, `xexpand=0.1` expands the bounding box by 10% on each side.
- `yexpand`: A `Float64` value (default = `0.0`) specifying the fractional expansion of the bounding box along the y-axis.

# Returns
- A single nested tuple of x-limits and y-limits after applying any expansions, in the form `((xmin, xmax), (ymin, ymax))`.

# Details
- The function first calculates the minimum and maximum values of `x` and `y`, ignoring any `NaN` values.
- It then applies the specified `xexpand` and `yexpand` to enlarge the bounding box.
- The x-limits are clamped to the range `[-180, 180]` to ensure valid longitude values.
- The y-limits are clamped to slightly above `-90` and slightly below `90` to ensure valid latitude values and avoid issues with map projections.
- Throws `ArgumentError` if `x` or `y` contains no non-`NaN` values.

# Example
Tight bounding box (no expansion):

```jldoctest
lon = [-78.6, -80.8, -82.5]
lat = [35.8, 35.2, 35.6]
mapbbox(lon, lat)

# output

((-82.5, -78.6), (35.2, 35.8))
```

Expanded 10% on each side for map padding:

```jldoctest
lon = [-78.6, -80.8, -82.5]
lat = [35.8, 35.2, 35.6]
mapbbox(lon, lat; xexpand=0.1, yexpand=0.1)

# output

((-82.89, -78.21), (35.14, 35.86))
```
"""
function mapbbox(x::Union{AbstractVector{<:Real}, Tuple{Vararg{Real}}},
                 y::Union{AbstractVector{<:Real}, Tuple{Vararg{Real}}};
                 xexpand::Real=0.0, yexpand::Real=0.0)
    
    # Check that x and y have the same length
    if length(x) != length(y)
        throw(ArgumentError("'x' and 'y' must have the same length."))
    end
    
    # Calculate the minimum and maximum x- and y-values, ignoring NaNs
    xvals = [x for x in x if !isnan(x)]
    yvals = [y for y in y if !isnan(y)]
    if isempty(xvals) || isempty(yvals)
        throw(ArgumentError("'x' and 'y' must contain at least one non-NaN value."))
    end
    (xmin, xmax) = extrema(xvals)
    (ymin, ymax) = extrema(yvals)

    # Calculate the expansion offsets based on the specified expansion factors
    xoffset = (xmax - xmin) * xexpand
    yoffset = (ymax - ymin) * yexpand
    xmin -= xoffset
    xmax += xoffset
    ymin -= yoffset
    ymax += yoffset

    # Ensure the x-limits stay within the valid longitude range [-180, 180]
    if xmin < -180
        xmin = -180
    end
    if xmax > 180
        xmax = 180
    end

    # Ensure the y-limits stay within the valid latitude range (-90, 90)
    if ymin <= -90
        ymin = max(-90 + sqrt(eps(Float64)), minimum(yvals))
    end
    if ymax >= 90
        ymax = min(90 - sqrt(eps(Float64)), maximum(yvals))
    end

    # Return the expanded limits
    return ((xmin, xmax), (ymin, ymax))
end

"""
    mapbbox(bb::Tuple{Tuple{Real,Real},Tuple{Real,Real}}; xexpand::Real=0.0, yexpand::Real=0.0) -> Tuple

Expands a box `bb = ((xmin, xmax), (ymin, ymax))`, as `mapbbox(x, y)` returns it, by `xexpand` times its width
and `yexpand` times its height on each side, with the same limits on longitude and latitude. With the default
expansion of zero it returns `bb` itself. `osm_roads` and `cropnetwork` take this box.

# Example
Widening a box as Lecture 4.2's Code block 2 widens the box around its two buildings (`xexpand = 2`,
`yexpand = 0.5`), here by a half and a quarter:

```jldoctest
bb = ((-80.0, -78.0), (35.0, 36.0))
mapbbox(bb; xexpand = 0.5, yexpand = 0.25)

# output

((-81.0, -77.0), (34.75, 36.25))
```
"""
mapbbox(bb::Tuple{Tuple{Real,Real},Tuple{Real,Real}}; xexpand::Real=0.0, yexpand::Real=0.0) =
    mapbbox(bb[1], bb[2]; xexpand=xexpand, yexpand=yexpand)

"""
    mapbbox(name::AbstractString; state, place::Bool = false, xexpand::Real = 0.0, yexpand::Real = 0.0) -> Tuple

The box of a named county or place (a city, town or census-designated place), in the form `mapbbox(x, y)` returns,
`((xmin, xmax), (ymin, ymax))`, offline. `state` is required, since names repeat across states: a two-letter code, a
`Symbol` or a full name. `xexpand` and `yexpand` widen the box, a county's or a place's, as they do a box given to
`mapbbox`.

**Which box.** A name that matches a county of the state gives the county's box; a name that matches no county gives
the box of the place of that name. So a county comes first: `"Durham"` in North Carolina is Durham County, and
`place = true` asks for the place instead, the city of Durham, even where a county has the name (MakePlan D3, X7).

**A county's box** is the extent of the county's Census block groups, each widened by the radius of a disk of its
land area (`sqrt(ALAND / π)`, converted to degrees of longitude and latitude at the block group's latitude), which
reaches the county's edge where the block groups' points alone fall short of it. It is computed exactly as Lecture
4.2's Code block 3 computes Wake County's box, and is equal to its `bbW` (reordered), so `osm_roads` snaps it to the
same tile. The county is matched by its name in [`uscounty`](@ref), ignoring case, with or without a trailing
"County".

**A place's box** is the extent of the place's Census 2020 polygon, the bounding box the U.S. Census Bureau's
TIGER/Line 2020 place shapefile records for it, kept in `data/usplacebox.jls` for every place of
[`usplace`](@ref) (made by `tools/v0_3_1/make_placebox.jl`). It contains the place's `usplace()` point. The place is
matched by its name as `usplace()` writes it, ignoring case: a city's or a town's name alone (`"Raleigh"`), any other
place's with its designator (`"Durham CDP"`, `"Oakwood village"`). If no place has that name, the name is matched
without its designator: a trailing "city", "town", "CDP", "village", "borough" or "municipality" (any case) is
dropped from the name given, and "CDP", "village", "borough" or "municipality" from the place's, so `"Raleigh city"`
is Raleigh and `"Durham"` in California is Durham CDP; a capitalized word that is part of a name stays (`"Kansas
City"`). An exact name is always preferred to one matched without its designator.

**Errors.** An unknown state, a name that matches no county and no place (with `place = true`, no place), a name
that matches two counties (as `"Baltimore"` in Maryland does: the county and the independent city), or a name that
matches two places in the state, is an `ArgumentError` naming them.

# Examples
Lecture 4.2's Code block 3, Wake County, North Carolina, whose box is about 39 miles wide:

```jldoctest
bb = mapbbox("Wake"; state = :NC)
(round.(bb[1], digits = 3), round.(bb[2], digits = 3))

# output

((-78.975, -78.274), (35.523, 36.08))
```

Raleigh is no county, so its name gives the city's box; "Durham" gives Durham County, and the city of Durham with
`place = true`:

```jldoctest
r3(bb) = (round.(bb[1], digits = 3), round.(bb[2], digits = 3))
r3(mapbbox("Raleigh"; state = :NC)), r3(mapbbox("Durham"; state = :NC)), r3(mapbbox("Durham"; state = :NC, place = true))

# output

(((-78.819, -78.471), (35.708, 35.971)), ((-79.023, -78.707), (35.864, 36.258)), ((-79.007, -78.76), (35.866, 36.137)))
```

A map of a city: `makemap(mapbbox("Raleigh"; state = :NC); roads = false)` (with `using CairoMakie, GeoMakie`).
"""
function mapbbox(name::AbstractString; state = nothing, place::Bool = false, xexpand::Real = 0.0, yexpand::Real = 0.0)
    isnothing(state) && throw(ArgumentError(
        "mapbbox: a county or place name needs its `state`, as in mapbbox(\"Wake\"; state = :NC)."))
    st = _normalize_state(state)                       # an ArgumentError naming the state if it is not one
    q = lowercase(strip(String(name)))
    q = replace(q, r"\s+county$" => "")
    isempty(q) && throw(ArgumentError("mapbbox: the name is empty."))
    if !place                                          # a county first, exactly as before v0.3.1
        cty = _table("uscounty")
        hit = findall(i -> cty.ST[i] == st && lowercase(cty.NAME[i]) == q, 1:nrow(cty))
        length(hit) > 1 && throw(ArgumentError("mapbbox: \"$(strip(String(name)))\" names $(length(hit)) counties in $st."))
        if length(hit) == 1
            co = cty[hit[1], :]
            b = _table("uscenblkgrp")
            keep = (b.STFIP .== co.STFIP) .& (b.COFIP .== co.COFIP)
            any(keep) || throw(ArgumentError("mapbbox: no block groups for \"$(strip(String(name)))\" in $st."))
            return mapbbox(_countybox(b.LON[keep], b.LAT[keep], b.ALAND[keep]); xexpand, yexpand)
        end
    end
    return mapbbox(_placebox(name, st; county = !place); xexpand, yexpand)
end

# A county's box, Lecture 4.2's construction (4-net-2.qmd, Code block 3), from its block groups' points and land
# areas in the table's order: each block group's point widened by the radius of a disk of its land area, in degrees
# of longitude and latitude at its latitude, and the extent of those. `mapbbox(name; state)` and `mapbbox(state)`
# both build a county's box here, so a state's box is the extent of exactly the boxes its counties have.
function _countybox(lon::AbstractVector, lat::AbstractVector, aland::AbstractVector)
    mpd = dgc((0, 0), (0, 1))                          # miles in a degree of latitude
    rad = sqrt.(aland ./ π)                            # radius as a disk, mi
    dlon = rad ./ (mpd .* cosd.(lat))                  # that radius in degrees of lon
    dlat = rad ./ mpd                                  # and of lat
    return ((minimum(lon .- dlon), maximum(lon .+ dlon)), (minimum(lat .- dlat), maximum(lat .+ dlat)))
end

# The designators `usplace()` writes after a place's name (a city's or a town's it drops), and those a name given to
# `mapbbox` may end with; each is dropped, with the space before it, when a name is matched without its designator.
const _PLACE_DESIGNATORS = (" CDP", " village", " borough", " municipality")
const _PLACE_QUERY_DESIGNATORS = (" city", " town", " cdp", " village", " borough", " municipality")

function _dropsuffix(s::AbstractString, sufs)
    for suf in sufs
        endswith(s, suf) && return String(s[1:prevind(s, ncodeunits(s) - ncodeunits(suf) + 1)])
    end
    return String(s)
end

# The row of `usplace()` (its table, `_table("usplace")`) that `name` names in state `st`: the name as written,
# ignoring case; failing that, without its designator. `county` says whether a county was looked for first, for the
# error's wording.
function _placerow(name::AbstractString, st::Symbol; county::Bool = false)
    p = _table("usplace")
    rows = get(_name_index("usplace").bystate, st, Int[])
    nm = strip(String(name))
    q = lowercase(nm)
    hit = [i for i in rows if lowercase(p.NAME[i]) == q]
    if isempty(hit)
        qb = _dropsuffix(q, _PLACE_QUERY_DESIGNATORS)
        hit = [i for i in rows if lowercase(_dropsuffix(p.NAME[i], _PLACE_DESIGNATORS)) == qb]
    end
    isempty(hit) && throw(ArgumentError("mapbbox: no $(county ? "county or place" : "place") named \"$nm\" in $st."))
    if length(hit) > 1
        which = join(["\"$(p.NAME[i])\" (PLFIP $(p.PLFIP[i]))" for i in hit], ", ", " and ")
        throw(ArgumentError("mapbbox: \"$nm\" names $(length(hit)) places in $st: $which."))
    end
    return hit[1]
end

# A place's box, ((LONmin, LONmax), (LATmin, LATmax)), from `data/usplacebox.jls` (one row per `usplace()` row,
# sorted by STFIP and PLFIP)
function _placebox(name::AbstractString, st::Symbol; county::Bool = false)
    p = _table("usplace")
    i = _placerow(name, st; county)
    B = _table("usplacebox")
    r = searchsorted(B.STFIP, p.STFIP[i])                # the state's rows, then the place's among them
    k = r[searchsorted(view(B.PLFIP, r), p.PLFIP[i])]
    length(k) == 1 || error("mapbbox: no box for place ($(p.STFIP[i]), $(p.PLFIP[i])) in usplacebox")
    j = only(k)
    return ((B.LONmin[j], B.LONmax[j]), (B.LATmin[j], B.LATmax[j]))
end

"""
    mapbbox(state::Symbol; xexpand::Real = 0.0, yexpand::Real = 0.0) -> Tuple

The box of a state, in the form `mapbbox(x, y)` returns, `((xmin, xmax), (ymin, ymax))`, offline: the extent of the
boxes of its counties, each built as `mapbbox(county; state)` builds it (from the county's Census block groups,
Lecture 4.2's construction), so it contains every county's box and comes from the tables Logjam already ships (X7). The
state is its two-letter abbreviation as a `Symbol`, as `usstate().ST` writes it (`:NC`), one of the 50 states and
the District of Columbia; a territory, which [`usstate`](@ref) does not hold, is an `ArgumentError`. `xexpand` and
`yexpand` widen the box as they do a box given to `mapbbox`.

# Example
North Carolina's box, the extent of its 100 counties' boxes:

```jldoctest
bb = mapbbox(:NC)
(round.(bb[1], digits = 3), round.(bb[2], digits = 3))

# output

((-84.295, -75.447), (33.835, 36.595))
```

A map of a state: `makemap(mapbbox(:NC))` (with `using CairoMakie, GeoMakie`).
"""
function mapbbox(state::Symbol; xexpand::Real = 0.0, yexpand::Real = 0.0)
    st = _normalize_state(state)                       # an ArgumentError naming the state if it is not one
    cty = _table("uscounty")
    rows = findall(==(st), cty.ST)
    isempty(rows) && throw(ArgumentError("mapbbox: $st has no counties in uscounty(); a state's box is one of the 50 " *
                                         "states' or the District of Columbia's."))
    b = _table("uscenblkgrp")
    ins = findall(==(cty.STFIP[rows[1]]), b.STFIP)
    lon, lat, aland, cofip = b.LON[ins], b.LAT[ins], b.ALAND[ins], b.COFIP[ins]
    xmin, xmax, ymin, ymax = Inf, -Inf, Inf, -Inf
    for i in rows
        keep = cofip .== cty.COFIP[i]
        any(keep) || throw(ArgumentError("mapbbox: no block groups for $(cty.NAME[i]) in $st."))
        (x0, x1), (y0, y1) = mapbbox(_countybox(lon[keep], lat[keep], aland[keep]))   # the county's box, as mapbbox(county; state) gives it
        xmin, xmax, ymin, ymax = min(xmin, x0), max(xmax, x1), min(ymin, y0), max(ymax, y1)
    end
    return mapbbox(((xmin, xmax), (ymin, ymax)); xexpand, yexpand)
end

"""
    bestfit(ang, Δ) -> 2-Tuple, 2-Tuple

Determine the text alignment and offset for a given angle.

Helper function used by `aligntext` to determines the text alignment and offset for a given angle, `ang`, based on predefined angular ranges. The function calculates the horizontal and vertical alignment based on the angle and the offset `Δ` to ensure proper text placement. 

# Arguments
- `ang`: A `Real` value representing the angle in degrees. The angle is normalized to the range `[0, 360)` if it is negative.
- `Δ`: A `Real` value representing the base offset to be applied for alignment purposes.

# Returns
- A `Tuple` containing two elements:
  1. `(halign, valign)`: A pair of symbols representing the horizontal (`:left`, `:center`, `:right`) and vertical (`:top`, `:center`, `:bottom`) alignment.
  2. `(hoffset, voffset)`: A pair of numerical offsets corresponding to the horizontal and vertical alignments, calculated based on the input angle `ang` and the offset `Δ`.
"""
function bestfit(ang, Δ)
    # Normalize angle to be within the range [0, 360) degrees
    if ang < 0
        ang += 360    # Convert to range 0 to 360 degrees
    end
    
    # Define angular ranges corresponding to different compass directions
    rng = [ 0, 1, 3, 5, 7, 9,11,13,15,16]*22.5
    
    # Find the index of the range that the angle falls into
    # idx corresponds to a direction such as East, North-East, etc.
    idx = findfirst((ang .>= rng[1:9]) .& (ang .< rng[2:10]))
    
    # Determine horizontal alignment based on the angle's index
    if idx ∈ [4, 5, 6]
        halign = :right
    elseif idx ∈ [3, 7]
        halign = :center
    else
        halign = :left
    end
    
    # Determine vertical alignment based on the angle's index
    if idx ∈ [2, 3, 4]
        valign = :bottom
    elseif idx ∈ [1, 5, 9]
        valign = :center
    else
        valign = :top
    end
    
    # Initialize offsets for text placement
    hoffset, voffset = 0, 0
    
    # Define offsets for non-diagonal directions
    hΔ⁺, vΔ⁺ = Δ+3, Δ+2
    
    # Adjust horizontal offset based on alignment
    if valign == :center && halign == :left
        hoffset = hΔ⁺
    elseif valign == :center && halign == :right
        hoffset = -hΔ⁺
    elseif halign == :left
        hoffset = Δ
    elseif halign == :right
        hoffset = -Δ
    end
    
    # Adjust vertical offset based on alignment
    if halign == :center && valign == :bottom
        voffset = vΔ⁺
    elseif halign == :center && valign == :top
        voffset = -vΔ⁺
    elseif valign == :bottom
        voffset = Δ
    elseif valign == :top
        voffset = -Δ
    end
    
    # Return the determined alignment and offsets
    return (halign, valign), (hoffset, voffset)
end

"""
    plotroads!(ax::GeoAxis, dfN::DataFrame, dfL::DataFrame;
               show_connectors::Bool = false) -> Dict{Symbol, Any}

Overlay road networks on GeoAxis with FCLASS-based styling inspired by OSM Carto.

Renders roads from DataFrames with differentiation by FCLASS (functional class).
FAF5 and OSM roads at the same FCLASS receive identical visual treatment. Uses
muted OSM Carto hues with adaptive zoom-based rendering: two-pass casing at
close zoom, single-line with hue tints at medium zoom, minimal at wide zoom.

# Arguments
- `ax::GeoAxis`: Geographic axis from `makemap()` or manual creation.
- `dfN::DataFrame`: Nodes with required IDX (col 1), LON (col 2), LAT (col 3).
- `dfL::DataFrame`: Links with required SRC (col 1), DST (col 2); optional SOURCE, FCLASS.
- `show_connectors::Bool`: Whether to render CONNECTOR links (default: false).

# Returns
- `Dict{Symbol, Any}`: Named handles to plotted line objects. Keys: `:fill_1` through
  `:fill_5` (by FCLASS tier), `:casing_1` through `:casing_5` (close zoom only),
  `:connector` (if shown). Only non-empty tiers are included.

# Styling
Roads are styled by FCLASS tier with zoom-adaptive rendering:
- **latspan > 20°** (CONUS-scale): Minimal single-line, faint (lw 0.25–0.05)
- **10° < latspan ≤ 20°** (Regional): Single-line with subtle hue tints (lw 0.7–0.15)
- **latspan ≤ 10°** (City/metro): Casing + fill with muted OSM Carto hues (lw 1.0–0.3)

FCLASS tiers: 1=Interstate (blue), 2=Freeway (green), 3=Arterial (warm yellow),
4=Collector (pale yellow), 5+=Local (white/gray). Colors are muted to serve as
background beneath overlaid data.

# Data Requirements
- `dfL` must have at least 2 columns: SRC, DST (node IDs as integers)
- `dfN` must have at least 3 columns: IDX, LON, LAT (coordinates in WGS84)
- Optional `dfL.SOURCE`: "FAF5", "OSM", or "CONNECTOR" (missing treated as "FAF5")
- Optional `dfL.FCLASS`: Integer functional class (1-7, per FHWA/OSM mapping)

# Examples
```julia
using CairoMakie, GeoMakie

# Basic FAF5 plot
dfN, dfL = faf5nodes(), faf5links()
fig, ax = makemap(region=:CUS)
handles = plotroads!(ax, dfN, dfL)
display(fig)

# Customize interstate fill color
handles[:fill_1].color = :darkblue

# Check available handles
keys(handles)  # e.g., [:fill_1, :fill_2, :casing_1, :casing_2, ...]
```

# Notes
- FCLASS-based styling applies uniformly to FAF5 and OSM roads
- Returns `Dict{Symbol, Any}` with keys `:fill_N`, `:casing_N` (N=1-5), `:connector`
- Casing keys only present at close zoom (latspan ≤ 10°)
- Connectors are hidden by default to avoid visual clutter from synthetic edges
- Node lookup uses Dict to handle non-sequential OSM node IDs efficiently
"""
function plotroads! end

# plotroute!: three methods, in LogjamMapExt (D2). Unlike v0.2.8's five, they take no markers (`show_markers`,
# `origin_color`, `dest_color`, `markersize`) and no `(ax, path, dfN)` forms: a removed call or keyword fails with a
# MethodError.

"""
    plotroute!(ax, x, y; color = :red, linewidth = 2, linestyle = :solid,
               arrows = true, arrow_at = 0.55, arrow_size = 12, arrow_every = 1) -> (; lines, arrows)
    plotroute!(ax, rte, sh, XY; tr = nothing, P = nothing, color = :red, ...) -> (; lines, arrows)
    plotroute!(ax, R, sh, XY; tr = nothing, P = nothing, colors = Makie.wong_colors(), ...) -> (; lines, arrows)

Draw a route on a map or any Makie axis, with an arrowhead partway along each leg to show the direction of travel.
Requires `using CairoMakie, GeoMakie`.

- `plotroute!(ax, x, y)` draws any sequence of locations, such as a tour, a path or a route's location sequence, as the
  line through the points `(x[i], y[i])`. A `NaN` separates one piece from the next.
- `plotroute!(ax, rte, sh, XY)` draws one route `rte`, a vector of shipment indices (each shipment's index twice, its
  pickup first, as `savings` and `twoopt` return it), through the location sequence `rte2loc(rte, sh, tr)`.
  `XY` is the `n×2` matrix of the locations' (`LON`, `LAT`), one row for each location. `tr` is the truck's `(b = ..., e = ...)`;
  where it is given the route begins and ends at its locations, as in `rteTC`. With `P`, the parent vectors `shortestpaths`
  returns, each leg is traced along the network (`tracepath`) and `XY`'s rows are the network's nodes, as in
  `[dfN.LON dfN.LAT]`; without it each leg is a straight line between its two locations.
- `plotroute!(ax, R, sh, XY)` draws several routes `R`, a vector of routes, one color from `colors` for each (cycled),
  each as the one-route method draws it.

An arrowhead sits `arrow_at` of the way along a leg, by its length as drawn (`0.55` is a little past the middle), on
every `arrow_every`-th leg from the first, `arrow_size` pixels long. A leg of no length (a location visited twice) has
none, and `arrows = false` draws none. A leg is each pair of consecutive locations, or with `P` the whole traced path
from one location to the next. The arrowheads point along the leg as it is drawn: their angle is computed from the axis's
own transform and limits, so it is right on a map (`makemap`'s Mercator `GeoAxis`) and on a plain `Axis`, and a
`resize!` turns them again. `plotroute!` makes no call to GeoMakie.

Returns the plots drawn as a `NamedTuple`: `lines` (the `Lines`) and `arrows` (the `Scatter` of the arrowheads, `nothing`
when `arrows = false`); for several routes each is a vector with one element for each route.

The origin and destination markers of v0.2.8 are gone: mark the stops with `scatter!`.

# Examples
README Example 4's route, drawn along the FAF5 network it was solved on:

```julia
using Logjam, CairoMakie, GeoMakie, DataFrames
cities = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
x, y = cities.LON, cities.LAT
sh = DataFrame(b = [2, 3, 10, 7, 6], e = [8, 4, 1, 5, 9])
dfN, dfL = addconnectors(cropnetwork(faf5nodes(), faf5links(), x, y)..., x, y)
D, P = shortestpaths(links2graph(dfL), nrow(cities))
rte, cost = twoopt(savings(r -> rteTC(r, sh, D), sh)[1], r -> rteTC(r, sh, D))
fig, ax = makemap(x, y)
plotroute!(ax, rte, sh, [dfN.LON dfN.LAT]; P = P, color = :red, linewidth = 2.5)
```

A tour, as Lecture 5.1 draws one, and a tour with an arrowhead on every second leg:

```julia
fig, ax = makemap(df.LON, df.LAT; xexpand = 0.05)
plotroute!(ax, df.LON[tour], df.LAT[tour]; color = :blue)
plotroute!(ax, df.LON[tour], df.LAT[tour]; arrow_every = 2)
```

Several routes, one color each, as README Example 5 draws its vehicles (`tr` is the depot):

```julia
plotroute!(ax, rte, sh, [dfN.LON dfN.LAT]; tr = (b = [1], e = [1]), P = P, linewidth = 2.5)
```

The migration from v0.2.8 is in the v0.3.0 release notes.
"""
function plotroute! end
