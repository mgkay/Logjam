"""
# MapTools

A module for creating geographical maps using the Makie ecosystem.

## Overview
The `MapTools` module provides a collection of tools and utilities that enable users to create detailed map visualizations, define and manipulate geographical regions, calculate bounding boxes, align text labels, and check if points lie within specific geographical boundaries.
   
## Exported Functions
- `makemap`: Creates a map visualization for predefined or user-defined regions of interest with various customizable options.
- `mapbbox`: Calculates the bounding box for a set of geographic coordinates with optional expansion.
- `aligntext`: Determines the best alignment and offset positions for text labels on a map based on point arrangements.
- `isptinbbox`: Checks if a given point lies within a specified bounding box.

## Constants
- `WORLD_LIMITS`: Defines geographical limits for world map projections.
- `US_LIMITS`: Defines geographical limits for map projections of the contiguous United States.
- `CUS_LIMITS`: Defines geographical limits for map projections of the continental United States (excluding Alaska and Hawaii).

## Dependencies
The module depends on the following packages:
- `Serialization`: For loading pre-serialized geographic data.
- `GeoMakie`, `GLMakie`, `CairoMakie`: For creating and rendering maps.
- `DelaunayTriangulation`: For triangulation in text alignment functions.
"""
module MapTools

# Import packages used in the module
using Serialization, GeoMakie, GLMakie, CairoMakie
using DelaunayTriangulation

# Exported functions
export WORLD_LIMITS, US_LIMITS, CUS_LIMITS
export makemap, mapbbox, aligntext, isptinbbox

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

"""
    makemap(x::Union{Nothing, AbstractVector{<:Real}, Tuple{Vararg{<:Real, 2}}} = nothing,
            y::Union{Nothing, AbstractVector{<:Real}, Tuple{Vararg{<:Real, 2}}} = nothing;
            region::Symbol = :World, backend::Symbol = :CairoMakie,
            xexpand::Real = 0.3, yexpand::Real = 0.1, doRoadbkgd::Bool = true, maxroadlatspan::Real = 2.5) -> Figure, GeoAxis, Vector, Tuple

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
    - `:GLMakie`: Uses GLMakie for rendering.
- `xexpand::Float64`: Expansion factor for the x-axis limits. Default is `0.3`.
- `yexpand::Float64`: Expansion factor for the y-axis limits. Default is `0.1`.
- `doRoadbkgd::Bool`: Whether to include roads as background features if maximum latitude span is less than `maxroadlatspan`. Default is `true`.
- `maxroadlatspan::Float64`: Maximum latitude span for displaying roads. Default is `2.5`°.

# Returns
- `fig::Figure`: The figure object containing the map.
- `ax::GeoAxis`: The axis object where the map is drawn.
- `hborders::Vector`: A vector of handles for the lines plotted on the map in the following order:
    - `hborders[1]`: NHS roads, if used (derived from: https://geodata.bts.gov/datasets/usdot::national-highway-system-nhs/explore).
    - `hborders[2]`: U.S. state borders, if used (derived from: https://raw.githubusercontent.com/PublicaMundi/MappingAPI/master/data/geojson/us-states.json)).
    - `hborders[3]`: Country borders, if used (derived from https://github.com/PublicaMundi/MappingAPI/blob/master/data/geojson/countries.geojson?short_path=b27f2ec)).
- `limits::Tuple`: The geographic limits (bounding box) used for the map.

# Behavior
- Automatically selects the appropriate region and borders based on the provided `x`, `y`, and `region` parameters.
- Chooses the rendering backend and activates it accordingly.
- Draws country borders, U.S. state borders, and National Highway System (NHS) roads depending on the specified options and region.
- If `x` and `y` are provided, calculates the bounding box with optional expansion and adjusts the map view accordingly. Expansion allows for better visualization around `x` and `y` points.

# Examples
```julia-repl
# Create a world map using CairoMakie
fig, ax = makemap()
display(fig)

# Create a U.S. map with GLMakie backend
fig, ax, hborders = makemap(region=:US, backend=:GLMakie)
display(fig)

# Create a map focused on a specific region with expanded limits
using GeoMakie   # Required for scatter! function
x = [-84.0, -83.0, -82.0]
y = [41.0, 42.0, 43.0]
fig, ax, hborders, limits = makemap(x, y)
scatter!(ax, x, y, markersize=12, color=:red)
println(limits)
display(fig)
```
"""
function makemap(x::Union{Nothing, AbstractVector{<:Real}, Tuple{Vararg{<:Real, 2}}} = nothing,
                 y::Union{Nothing, AbstractVector{<:Real}, Tuple{Vararg{<:Real, 2}}} = nothing;
                 region::Symbol = :World, backend::Symbol = :CairoMakie,
                 xexpand::Real = 0.3, yexpand::Real = 0.1, 
                 doRoadbkgd::Bool = true, maxroadlatspan::Real = 2.5)

    # Enforce that x and y must have at least two elements if they are vectors
    if x isa AbstractVector && length(x) < 2
        throw(ArgumentError("x must be vector with at least two elements if not nothing."))
    end
    if y isa AbstractVector && length(y) < 2
        throw(ArgumentError("y must be vector with at least two elements if not nothing."))
    end

    # Activate the appropriate backend for rendering the map
    if backend == :GLMakie
        GLMakie.activate!()  # Use GLMakie for rendering
    elseif backend == :CairoMakie
        CairoMakie.activate!()  # Use CairoMakie for rendering
    else
        error("Unknown backend specified, choose :GLMakie or :CairoMakie.")  # Error if an unsupported backend is specified
    end

    # Define a helper function to check if one bounding box (bbox0) is within another (bbox)
    function isinbbox(bbox0, bbox)
        ((xmin0, xmax0), (ymin0, ymax0)) = bbox0     
        ((xmin, xmax), (ymin, ymax)) = bbox
        return xmin0 >= xmin && xmax0 <= xmax && ymin0 >= ymin && ymax0 <= ymax
    end

    # Initialize border drawing flags
    doCountryborder, doUSborder = true, false

    # Determine the map limits based on the specified region or coordinates
    if isnothing(x)  && isnothing(y)
        # Use predefined limits based on the region
        if region == :World
            limits = WORLD_LIMITS  # World map limits
        elseif region == :US
            limits = US_LIMITS  # U.S. map limits
            doUSborder = true  # Enable U.S. borders
        elseif region == :CUS
            limits = CUS_LIMITS  # Continental U.S. map limits
            doCountryborder, doUSborder = false, true  # Enable only U.S. borders
        end
    else
        # Calculate map limits based on provided coordinates with optional expansion
        limits, limits0 = mapbbox(x, y, xexpand = xexpand, yexpand = yexpand)
        # Check if the region falls within the continental U.S. limits
        if isinbbox(limits0, CUS_LIMITS)
            doCountryborder, doUSborder = false, true  # Show only U.S. borders
        elseif isinbbox(limits0, CUS_LIMITS)
            doUSborder = true  # Show both country and U.S. borders
        end
    end
    
    # Create a figure and a geographical axis using the Mercator projection
    fig = Figure()
    ax = GeoAxis(fig[1, 1]; dest="+proj=merc", limits=limits, autolimitaspect = nothing)
    ax.xgridstyle, ax.ygridstyle = :dot, :dot  # Set grid style for the axis

    # Define helper functions to load pre-serialized geographic data
    function countries()
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        x, y = open(deserialize, joinpath(data_dir, "countries.jls"))
        return x, y  # Return coordinates for country borders
    end

    function usstates()
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        x, y = open(deserialize, joinpath(data_dir, "usstates.jls"))
        return x, y  # Return coordinates for U.S. state borders
    end

    function nhsroads()
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        x, y = open(deserialize, joinpath(data_dir, "nhsroads.jls"))
        return x, y  # Return coordinates for NHS roads
    end

    hborders = []  # Initialize an empty array to hold border handles

    # Add roads as background if specified and within latitude span limits
    if doRoadbkgd
        if abs(limits[2][2] - limits[2][1]) <= maxroadlatspan
            push!(hborders, lines!(ax, nhsroads()..., color=:grey, linewidth=.5,
                alpha=0.5, label="NHS Roads"))  # Add NHS roads to the map
        end
    end

    # Add U.S. state borders if specified
    if doUSborder
        push!(hborders, lines!(ax, usstates()..., color=:blue, linewidth=.75,
            label="US State Borders"))  # Add U.S. state borders to the map
        if doCountryborder
            hborders[end].linestyle = :dash  # Set line style to dashed for country borders
            hborders[end].alpha = 0.5  # Set transparency for the borders
        end
    end

    # Add country borders if specified
    if doCountryborder
        push!(hborders, lines!(ax, countries()..., color=:blue, linewidth=.75,
            label="Country Borders"))  # Add country borders to the map
    end

    return fig, ax, hborders, limits  # Return the figure, axis, border handles, and limits
end

"""
    aligntext(x::Union{Real, AbstractVector, Tuple{Vararg{Real}}}, 
              y::Union{Real, AbstractVector, Tuple{Vararg{Real}}};
              offsetamt::Real=1, mindistratio::Real=1.5) -> Pair, Pair

Determines text alignment and offset positions for given points.

This function attempts to calculate the best alignment and offset positions for text labels based on the spatial arrangement of the points provided. It is particularly useful for positioning labels or annotations on a plot, ensuring that they do not overlap and remain readable. The function can handle various input formats for the points, including scalars, vectors, and tuples, and adjusts the text position to try to avoid collisions with nearby labels or graphical elements.

# Arguments
- `x`: Scalar, vector, or tuple representing the x-coordinates for the points.
- `y`: Scalar, vector, or tuple representing the y-coordinates for the points.
- `offsetamt`: Scalar value specifying the amount of offset to apply to the text labels. This controls the distance by which the text is shifted away from the point. Default is `1`.
- `mindistratio`: Scalar value that sets the minimum distance ratio used to decide the best alignment for text labels relative to adjacent points. Default is `1.5`.

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
function aligntext(x::Union{Real, AbstractVector, Tuple{Vararg{Real}}}, 
                   y::Union{Real, AbstractVector, Tuple{Vararg{Real}}};
                   offsetamt::Real=1, mindistratio::Real=1.5)

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
        alignout, offsetout = [], []
        if length(pts) == 2
            ang = arcang(pts[1], pts[2])
            align, offset = bestfit(ang, offsetamt)
            push!(alignout, align)
            push!(offsetout, offset) 
            ang -= 180    # Reverse direction
            align, offset = bestfit(ang, offsetamt)
            push!(alignout, align)
            push!(offsetout, offset) 
        else
            tri = triangulate(pts)
            for i in 1:length(pts)
                IJ = get_adjacent2vertex(tri, i)
                idx = collect(reduce(union, [Set(t) for t in IJ]))
                filter!(j -> j > 0, idx)   # Remove ghost vertices
                d = [d2(pts[i], pts[j]) for j in idx]
                sidx = sortperm(d)
                d, idx = d[sidx], idx[sidx]
                if (d[2]/d[1] > mindistratio) || 
                    (length(d) > 2 ? (d[3]/(d[1] + d[2]) > mindistratio) : false)
                    ang = arcang(pts[i], pts[idx[1]]) - 180
                else
                    ang = [arcang(pts[i], pts[j]) for j in idx]
                    ang = sort(ang)
                    δ = diff([-180; ang; 180])
                    δ = [δ[2:end-1]; δ[1] + δ[end]]
                    idx = argmax(δ)
                    ang = ang[idx] + δ[idx]/2
                end
                align, offset = bestfit(ang, offsetamt)
                push!(alignout, align)
                push!(offsetout, offset)    
            end
        end
        return :align => alignout, :offset => offsetout
    end 
end

"""
    mapbbox(x::Union{AbstractVector{<:Real}, Tuple{Vararg{<:Real}}},
            y::Union{AbstractVector{<:Real}, Tuple{Vararg{<:Real}}};
            xexpand::Float64=0.0, yexpand::Float64=0.0) -> Tuple, Tuple

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
"""
function mapbbox(x::Union{AbstractVector{<:Real}, Tuple{Vararg{<:Real}}},
                 y::Union{AbstractVector{<:Real}, Tuple{Vararg{<:Real}}};
                 xexpand::Float64=0.0, yexpand::Float64=0.0)
    
    # Check that x and y have the same length
    if length(x) != length(y)
        throw(ArgumentError("'x' and 'y' must have the same length."))
    end
    
    # Calculate the minimum and maximum x- and y-values, ignoring NaNs
    (xmin, xmax) = extrema([x for x in x if !isnan(x)])
    (ymin, ymax) = extrema([y for y in y if !isnan(y)])

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
        ymin = max(-90 + sqrt(eps(Float64)), minimum([y for y in y if !isnan(y)]))
    end
    if ymax >= 90
        ymax = min(90 - sqrt(eps(Float64)), maximum([y for y in y if !isnan(y)]))
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
    isptinbbox(pt, bbox::Tuple{Union{Tuple{<:Real, <:Real}, AbstractVector{<:Real}},
                               Union{Tuple{<:Real, <:Real}, AbstractVector{<:Real}}}) -> Bool

Determines whether a given point lies within a specified bounding box.

# Arguments
- `pt`: A tuple or vector of exactly two elements representing the coordinates of the point `(x, y)`.
- `bbox`: A tuple of two tuples or arrays, each containing two elements representing the bounding box. The first tuple/array defines the x-limits `(xmin, xmax)` and the second tuple/array defines the y-limits `(ymin, ymax)`.

# Returns
- A `Bool` value:
  - `true` if the point `pt` lies within the bounding box `bbox`.
  - `false` otherwise.

# Example
```julia-repl
pt = (5, 10)
bbox = ((0, 10), (0, 15))
isptinbbox(pt, bbox)  # returns true

pt_outside = (15, 10)
isptinbbox(pt_outside, bbox)  # returns false

invalid_pt = (5,)
isptinbbox(invalid_pt, bbox)  # throws ArgumentError
```
"""
function isptinbbox(pt, bbox::Tuple{Union{Tuple{<:Real, <:Real}, AbstractVector{<:Real}},
                                    Union{Tuple{<:Real, <:Real}, AbstractVector{<:Real}}})
    # Ensure that pt is either a Tuple or an AbstractVector with exactly two elements
    if !(pt isa Tuple || pt isa AbstractVector) || length(pt) != 2
        throw(ArgumentError("The point 'pt' must be a tuple or vector with exactly two elements (x, y)."))
    end

    # Check if the point is within the bounding box
    return (pt[1] >= bbox[1][1] && pt[1] <= bbox[1][2] &&
    pt[2] >= bbox[2][1] && pt[2] <= bbox[2][2])
end

end # module MapTools
