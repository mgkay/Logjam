# MapTools - Functions for creating geographical maps using the Makie ecosystem

"""
    WORLD_LIMITS

A constant defining the geographical limits for a world map projection.

- The first tuple specifies the longitude limits in degrees: `(-180, 180)`.
- The second tuple specifies the latitude limits in degrees: `(-75, 75)`.
"""
const WORLD_LIMITS = ((-180, 180), (-75, 75))

"""
    US_LIMITS

A constant defining the geographical limits for a map projection of the contiguous United States.

- The first tuple specifies the longitude limits in degrees: `(-180, -65)`.
- The second tuple specifies the latitude limits in degrees: `(15, 72)`.
"""
const US_LIMITS = ((-180, -65), (15, 72))

"""
    CUS_LIMITS

A constant defining the geographical limits for a map projection of the contiguous United States (excluding Alaska and Hawaii).

- The first tuple specifies the longitude limits in degrees: `(-125, -65)`.
- The second tuple specifies the latitude limits in degrees: `(24, 50)`.
"""
const CUS_LIMITS = ((-125, -65), (24, 50))

# Cache for geographic data (loaded on first use)
const _countries_cache = Ref{Union{Nothing, Tuple}}(nothing)
const _usstates_cache = Ref{Union{Nothing, Tuple}}(nothing)
const _faf5interstate_cache = Ref{Union{Nothing, Tuple}}(nothing)

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
"""
function usstates()
    if isnothing(_usstates_cache[])
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        _usstates_cache[] = open(deserialize, joinpath(data_dir, "usstates.jls"))
    end
    return _usstates_cache[]
end

"""
    faf5interstateroads() -> Tuple{Vector, Vector}

Load and cache FAF5 interstate road coordinates from serialized data.

Returns polyline vectors (x, y) with NaN separators for interstate highways
derived from the Freight Analysis Framework version 5 (FAF5) network.
"""
function faf5interstateroads()
    if isnothing(_faf5interstate_cache[])
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        _faf5interstate_cache[] = open(deserialize, joinpath(data_dir, "faf5_interstate_roads.jls"))
    end
    return _faf5interstate_cache[]
end

"""
    makemap(x::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}} = nothing,
            y::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}} = nothing;
            region::Symbol = :World, backend::Symbol = :CairoMakie,
            xexpand::Real = 0.3, yexpand::Real = 0.1, doRoadbkgd::Bool = true, maxroadlatspan::Real = 30.0) -> Figure, GeoAxis, Vector, Tuple

Creates map visualization for predefined or user-defined region of interest. 
    
The map can focus on different predefined regions (the world, U.S., or continental U.S.) or a user-defined region of interest that contains a set of longitude-latitude points. Provides Mercator projection of geographical features such as country borders, U.S. state borders, and roads using `GeoMakie`.

# Arguments
- `x`: Optional set of at least two longitudes to define the region of interest; if `nothing`, defaults to a pre-defined region based on the `region` parameter.
- `y`: Optional set of at least two latitudes to define the region of interest; if `nothing`, defaults to a pre-defined region based on the `region` parameter.
- `region::Symbol`: Specifies the region to focus on. Options include:
    - `:World`: Default. Focuses on the entire world.
    - `:US`: Focuses on the United States.
    - `:CUS`: Focuses on the continental U.S. without showing country borders.
- `backend::Symbol`: Specifies the rendering backend. Options are:
    - `:CairoMakie`: Default. Uses CairoMakie for rendering.
    - `:GLMakie`: Uses GLMakie for interactive rendering. Requires `using GLMakie` before calling.
- `xexpand::Float64`: Expansion factor for the x-axis limits. Default is `0.3`.
- `yexpand::Float64`: Expansion factor for the y-axis limits. Default is `0.1`.
- `doRoadbkgd::Bool`: Whether to include roads as background features if maximum latitude span is less than `maxroadlatspan`. Default is `true`.
- `maxroadlatspan::Float64`: Maximum latitude span for displaying roads. Default is `30.0`° (allows continental US coverage with FAF5 interstate network).
- `showgrid::Bool`: Whether to display grid lines and coordinate labels. Default is `false`.

# Returns
- `fig::Figure`: The figure object containing the map.
- `ax::GeoAxis`: The axis object where the map is drawn.
- `hborders::Vector`: A vector of handles for the lines plotted on the map in the following order:
    - `hborders[1]`: Interstate roads, if used (derived from FAF5: https://geodata.bts.gov/datasets/usdot::freight-analysis-framework-faf5-network-links/about).
    - `hborders[2]`: U.S. state borders, if used (derived from: https://raw.githubusercontent.com/PublicaMundi/MappingAPI/master/data/geojson/us-states.json)).
    - `hborders[3]`: Country borders, if used (derived from https://github.com/PublicaMundi/MappingAPI/blob/master/data/geojson/countries.geojson?short_path=b27f2ec)).
- `limits::Tuple`: The geographic limits (bounding box) used for the map.

# Behavior
- Automatically selects the appropriate region and borders based on the provided `x`, `y`, and `region` parameters.
- Chooses the rendering backend and activates it accordingly.
- Draws country borders, U.S. state borders, and FAF5 Interstate Highways depending on the specified options and region.
- If `x` and `y` are provided, calculates the bounding box with optional expansion and adjusts the map view accordingly. Expansion allows for better visualization around `x` and `y` points.

# Examples
```julia-repl
# Create a world map using CairoMakie
fig, ax, hborders, limits = makemap()

# Create a U.S. map
fig, ax, hborders, limits = makemap(region=:US)

# Create a map focused on a specific region with expanded limits
using GeoMakie   # Required for scatter! function
x = [-84.0, -83.0, -82.0]
y = [41.0, 42.0, 43.0]
fig, ax, hborders, limits = makemap(x, y)
scatter!(ax, x, y, markersize=12, color=:red)
fig
```
"""
function makemap(x::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}} = nothing,
                 y::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}} = nothing;
                 kwargs...)
    if _geomakie_available[]
        return _makemap_impl[](x, y; kwargs...)
    else
        error("makemap() requires CairoMakie and GeoMakie. Run: using CairoMakie, GeoMakie")
    end
end

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
```julia-repl
# Example: Cities in North Carolina with populaions over 100,000
using GeoMakie, DataFrames
df = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
x, y, name = df.LON, df.LAT, df.NAME
fig, ax = makemap(x, y)
scatter!(ax, x, y)
text!(ax, x, y, text=name; aligntext(x, y)...)  # Note ";" and "..." for splatting
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
            tri = triangulate(unique_pts)
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
            xexpand::Real=0.0, yexpand::Real=0.0) -> Tuple, Tuple

Calculates the bounding box for a set of geographic coordinates, with optional expansion along the x and y axes.

# Arguments
- `x`: A vector or tuple of x-coordinates (longitude values).
- `y`: A vector or tuple of y-coordinates (latitude values).
- `xexpand`: A `Float64` value (default = `0.0`) specifying the fractional expansion of the bounding box along the x-axis. For example, `xexpand=0.1` expands the bounding box by 10% on each side.
- `yexpand`: A `Float64` value (default = `0.0`) specifying the fractional expansion of the bounding box along the y-axis.

# Returns
- A tuple of x-limits and y-limits after applying any expansions, in the form `((xmin, xmax), (ymin, ymax))`.
- A tuple of the original x-limits and y-limits without any expansion.

# Details
- The function first calculates the minimum and maximum values of `x` and `y`, ignoring any `NaN` values.
- It then applies the specified `xexpand` and `yexpand` to enlarge the bounding box.
- The x-limits are clamped to the range `[-180, 180]` to ensure valid longitude values.
- The y-limits are clamped to slightly above `-90` and slightly below `90` to ensure valid latitude values and avoid issues with map projections.
- Throws `ArgumentError` if `x` or `y` contains no non-`NaN` values.
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

    # Store the original limits without any expansion
    limits0 = (xmin, xmax), (ymin, ymax)

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

    # Return the expanded limits and the original unexpanded limits
    return ((xmin, xmax), (ymin, ymax)), limits0
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
               show_connectors::Bool = false) -> Vector{Lines}

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
using GeoMakie

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
- Compatible with both CairoMakie and GLMakie backends
"""
function plotroads!(ax, dfN::DataFrame, dfL::DataFrame; kwargs...)
    if _geomakie_available[]
        return _plotroads_impl[](ax, dfN, dfL; kwargs...)
    else
        error("plotroads!() requires CairoMakie and GeoMakie. Run: using CairoMakie, GeoMakie")
    end
end

# plotroute! stubs — all methods dispatch through _plotroute_impl in LogjamMapExt

"""
    plotroute!(ax, lx, ly; kwargs...) → Vector

Base rendering method. Plots a route from coordinate vectors.
Requires `using CairoMakie, GeoMakie`.
"""
function plotroute!(ax, lx::AbstractVector{<:Real}, ly::AbstractVector{<:Real}; kwargs...)
    if _geomakie_available[]
        return _plotroute_impl[](ax, lx, ly; kwargs...)
    else
        error("plotroute!() requires CairoMakie and GeoMakie. Run: using CairoMakie, GeoMakie")
    end
end

function plotroute!(ax, path::Vector{Int}, dfN::DataFrame; kwargs...)
    if _geomakie_available[]
        return _plotroute_impl[](ax, path, dfN; kwargs...)
    else
        error("plotroute!() requires CairoMakie and GeoMakie. Run: using CairoMakie, GeoMakie")
    end
end

function plotroute!(ax, paths::Vector{Vector{Int}}, dfN::DataFrame; kwargs...)
    if _geomakie_available[]
        return _plotroute_impl[](ax, paths, dfN; kwargs...)
    else
        error("plotroute!() requires CairoMakie and GeoMakie. Run: using CairoMakie, GeoMakie")
    end
end

function plotroute!(ax, route::AbstractVector{Int}, shipments::DataFrame,
                    parents::Vector{Vector{Int}}, dfN::DataFrame; kwargs...)
    if _geomakie_available[]
        return _plotroute_impl[](ax, route, shipments, parents, dfN; kwargs...)
    else
        error("plotroute!() requires CairoMakie and GeoMakie. Run: using CairoMakie, GeoMakie")
    end
end

function plotroute!(ax, routes::Vector{<:AbstractVector{Int}}, shipments::DataFrame,
                    parents::Vector{Vector{Int}}, dfN::DataFrame; kwargs...)
    if _geomakie_available[]
        return _plotroute_impl[](ax, routes, shipments, parents, dfN; kwargs...)
    else
        error("plotroute!() requires CairoMakie and GeoMakie. Run: using CairoMakie, GeoMakie")
    end
end
