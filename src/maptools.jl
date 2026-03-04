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
fig, ax = makemap()
display(fig)

# Create a U.S. map with GLMakie backend (requires `using GLMakie` first)
using GLMakie
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
function makemap(x::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}} = nothing,
                 y::Union{Nothing, AbstractVector{<:Real}, NTuple{2, <:Real}} = nothing;
                 region::Symbol = :World, backend::Symbol = :CairoMakie,
                 xexpand::Real = 0.3, yexpand::Real = 0.1,
                 doRoadbkgd::Bool = true, maxroadlatspan::Real = 30.0)

    # Enforce that x and y must have at least two elements if they are vectors
    if x isa AbstractVector && length(x) < 2
        throw(ArgumentError("x must be vector with at least two elements if not nothing."))
    end
    if y isa AbstractVector && length(y) < 2
        throw(ArgumentError("y must be vector with at least two elements if not nothing."))
    end

    # Activate the appropriate backend for rendering the map
    if backend == :GLMakie
        if _glmakie_available[]
            _glmakie_activate[]()  # Use GLMakie for rendering
        else
            error("GLMakie backend requested but GLMakie is not loaded. Add `using GLMakie` first.")
        end
    elseif backend == :CairoMakie
        CairoMakie.activate!()  # Use CairoMakie for rendering
    else
        error("Unknown backend specified, choose :GLMakie or :CairoMakie.")
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
        # Check if the region falls within the continental U.S. or broader U.S. limits
        if isinbbox(limits0, CUS_LIMITS)
            doCountryborder, doUSborder = false, true  # Show only U.S. borders
        elseif isinbbox(limits0, US_LIMITS)
            doUSborder = true  # Show both country and U.S. borders
        end
    end
    
    # Create a figure and a geographical axis using the Mercator projection
    fig = Figure()
    ax = GeoAxis(fig[1, 1]; dest="+proj=merc", limits=limits, autolimitaspect = nothing)
    ax.xgridstyle, ax.ygridstyle = :dot, :dot  # Set grid style for the axis

    hborders = []  # Initialize an empty array to hold border handles

    # Add roads as background if specified and within latitude span limits
    if doRoadbkgd
        latspan = abs(limits[2][2] - limits[2][1])
        if latspan <= maxroadlatspan
            # Adjust opacity based on zoom level (lighter when zoomed in)
            road_alpha = latspan > 20 ? 0.35 : (latspan > 10 ? 0.25 : 0.2)
            road_lw = latspan > 20 ? 0.3 : (latspan > 10 ? 0.5 : 0.6)
            push!(hborders, lines!(ax, faf5interstateroads()..., color=(:steelblue, road_alpha),
                linewidth=road_lw, label="Interstate Roads"))
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
    aligntext(x::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}},
              y::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}};
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
function aligntext(x::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}},
                   y::Union{Real, AbstractVector{<:Real}, Tuple{Vararg{Real}}};
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
                idx = collect(reduce(union, [Set(t) for t in IJ]))
                filter!(j -> j > 0, idx)   # Remove ghost vertices
                d = [d2(unique_pts[ui], unique_pts[j]) for j in idx]
                sidx = sortperm(d)
                d, idx = d[sidx], idx[sidx]
                if (d[2]/d[1] > mindistratio) ||
                    (length(d) > 2 ? (d[3]/(d[1] + d[2]) > mindistratio) : false)
                    base_angles[ui] = arcang(unique_pts[ui], unique_pts[idx[1]]) - 180
                else
                    ang = [arcang(unique_pts[ui], unique_pts[j]) for j in idx]
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

        return :align => alignout, :offset => offsetout
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
```jldoctest
julia> bbox = ((0, 10), (0, 15));

julia> isptinbbox((5, 10), bbox)  # inside
true

julia> isptinbbox((15, 10), bbox)  # outside
false
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

"""
    alloclines(W, hub_xy, spoke_xy; tol=sqrt(eps())) -> (X, Y)

Convert allocation matrix to NaN-separated line segments for visualization.

Creates line segments connecting hubs to their allocated spokes. Returns one
vector of coordinates per hub, enabling per-hub formatting (e.g., different colors).

# Arguments
- `W`: n×m allocation matrix where W[i,j] indicates allocation weight from hub i to spoke j.
- `hub_xy`: n×2 matrix of hub coordinates [lon, lat] or [x, y].
- `spoke_xy`: m×2 matrix of spoke coordinates [lon, lat] or [x, y].
- `tol`: Threshold for nonzero allocation (default: √eps ≈ 1.5e-8).

# Returns
- `(X, Y)`: Tuple of `Vector{Vector{Float64}}`, each of length n (one per hub).
  `X[i]` and `Y[i]` contain NaN-separated coordinates for hub i's allocation lines.

# Example
```julia
k = [100.0, 100.0, 150.0]
C = [0 3 7 10; 3 0 4 8; 7 4 0 5]
y, TC, W = ufl(k, C; verbose=false)

hubs = [-80.0 35.0; -78.0 36.0; -79.0 35.5]
spokes = [-80.5 35.2; -78.5 35.8; -79.2 36.1; -78.0 35.0]

X, Y = alloclines(W, hubs, spokes)

# Per-hub coloring
colors = [:red, :blue, :green]
for i in eachindex(X)
    lines!(ax, X[i], Y[i], color=colors[i])
end

# Or single-shot plotting (concatenate all hubs)
lines!(ax, reduce(vcat, X), reduce(vcat, Y))
```
"""
function alloclines(W::AbstractMatrix, hub_xy::AbstractMatrix, spoke_xy::AbstractMatrix;
                    tol::Real=sqrt(eps(Float64)))
    n, m = size(W)
    size(hub_xy, 1) == n || throw(ArgumentError("hub_xy must have $n rows to match W"))
    size(spoke_xy, 1) == m || throw(ArgumentError("spoke_xy must have $m rows to match W"))
    size(hub_xy, 2) == 2 || throw(ArgumentError("hub_xy must be an n×2 matrix"))
    size(spoke_xy, 2) == 2 || throw(ArgumentError("spoke_xy must be an m×2 matrix"))

    X = [Float64[] for _ in 1:n]
    Y = [Float64[] for _ in 1:n]

    for i in 1:n
        for j in 1:m
            if abs(W[i, j]) > tol
                append!(X[i], [hub_xy[i, 1], spoke_xy[j, 1], NaN])
                append!(Y[i], [hub_xy[i, 2], spoke_xy[j, 2], NaN])
            end
        end
    end

    return X, Y
end

"""
    plotroads!(ax::GeoAxis, dfL::DataFrame, dfN::DataFrame;
               show_connectors::Bool = false) -> Vector{Lines}

Overlay road networks on GeoAxis with adaptive zoom-based styling.

Renders roads from DataFrames with automatic differentiation by SOURCE category
(FAF5/OSM/CONNECTOR) and interstate status (FCLASS==1). Uses unified gray color
palette with adaptive linewidth and alpha based on zoom level.

# Arguments
- `ax::GeoAxis`: Geographic axis from `makemap()` or manual creation.
- `dfL::DataFrame`: Links with required SRC (col 1), DST (col 2); optional SOURCE, FCLASS.
- `dfN::DataFrame`: Nodes with required IDX (col 1), LON (col 2), LAT (col 3).
- `show_connectors::Bool`: Whether to render CONNECTOR links (default: false).

# Returns
- `Vector{Lines}`: Handles to plotted line objects, ordered as [FAF5_interstate, FAF5_other, OSM, CONNECTOR] (empty categories omitted).

# Styling
Roads are styled adaptively based on latitude span (latspan = max_lat - min_lat):
- **latspan > 20°** (CONUS-scale): Thin lines, lower alpha (zoomed out)
- **10° < latspan ≤ 20°** (Regional): Medium lines, medium alpha
- **latspan ≤ 10°** (City/state): Thick lines, higher alpha (zoomed in)

All roads use unified `:gray55` color with differentiation via linewidth and alpha.
Interstates (FCLASS==1 within FAF5) are thicker than other roads at each zoom level.

# Data Requirements
- `dfL` must have at least 2 columns: SRC, DST (node IDs as integers)
- `dfN` must have at least 3 columns: IDX, LON, LAT (coordinates in WGS84)
- Optional `dfL.SOURCE`: "FAF5", "OSM", or "CONNECTOR" (missing treated as "FAF5")
- Optional `dfL.FCLASS`: Integer functional class (1 = interstate, FAF5 only)

# Examples
```julia
using Logjam, GeoMakie

# Basic FAF5 plot
dfL, dfN = faf5links(), faf5nodes()
fig, ax = makemap(region=:CUS)
handles = plotroads!(ax, dfL, dfN)
display(fig)

# Customize interstate color
handles[1].color = (:darkblue, 0.7)

# With connectors
x_fac = [-80.0, -78.5]
y_fac = [35.5, 36.2]
dfN_conn, dfL_conn = addconnectors(dfN, dfL, x_fac, y_fac)
fig, ax = makemap(region=:CUS)
handles = plotroads!(ax, dfL_conn, dfN_conn; show_connectors=true)
handles[end].color = (:red, 0.5)  # Highlight connectors
display(fig)
```

# Notes
- Interstates are only detected in FAF5 roads (SOURCE=="FAF5" or missing) with FCLASS==1
- Connectors are hidden by default to avoid visual clutter from synthetic edges
- Returns handles in deterministic order for user customization
- Node lookup uses Dict to handle non-sequential OSM node IDs efficiently
"""
function plotroads!(ax, dfL::DataFrame, dfN::DataFrame;
                    show_connectors::Bool = false)
    # 1. Input validation
    nrow(dfL) > 0 || throw(ArgumentError("dfL must have at least one row"))
    nrow(dfN) > 0 || throw(ArgumentError("dfN must have at least one row"))
    ncol(dfL) >= 2 || throw(ArgumentError("dfL must have at least 2 columns (SRC, DST)"))
    ncol(dfN) >= 3 || throw(ArgumentError("dfN must have at least 3 columns (IDX, LON, LAT)"))

    # Get column references by position
    src_vals = dfL[:, 1]
    dst_vals = dfL[:, 2]
    node_ids = dfN[:, 1]
    node_lons = dfN[:, 2]
    node_lats = dfN[:, 3]

    # Validate node reference integrity
    node_id_set = Set(node_ids)
    orphaned_src = findall(src -> src ∉ node_id_set, src_vals)
    !isempty(orphaned_src) && throw(ArgumentError(
        "dfL has $(length(orphaned_src)) links with SRC not in dfN.IDX (first: row $(orphaned_src[1]))"))

    orphaned_dst = findall(dst -> dst ∉ node_id_set, dst_vals)
    !isempty(orphaned_dst) && throw(ArgumentError(
        "dfL has $(length(orphaned_dst)) links with DST not in dfN.IDX (first: row $(orphaned_dst[1]))"))

    # Validate coordinate bounds
    bad_lon = findall(lon -> lon < -180 || lon > 180, node_lons)
    !isempty(bad_lon) && throw(ArgumentError(
        "dfN has $(length(bad_lon)) nodes with LON out of bounds [-180,180] (first: row $(bad_lon[1]))"))

    bad_lat = findall(lat -> lat < -90 || lat > 90, node_lats)
    !isempty(bad_lat) && throw(ArgumentError(
        "dfN has $(length(bad_lat)) nodes with LAT out of bounds [-90,90] (first: row $(bad_lat[1]))"))

    # 2. Build node lookup dictionary
    node_lookup = Dict(node_ids[i] => (node_lons[i], node_lats[i]) for i in 1:nrow(dfN))

    # 3. Add SOURCE column if missing (backward compatibility)
    has_source = "SOURCE" in names(dfL)
    source_col = has_source ? dfL.SOURCE : fill(missing, nrow(dfL))

    # 4. Filter connectors if hidden
    dfL_active = dfL
    if !show_connectors
        keep_mask = [coalesce(s, "FAF5") != "CONNECTOR" for s in source_col]
        dfL_active = dfL[keep_mask, :]
        source_col = has_source ? dfL_active.SOURCE : fill(missing, nrow(dfL_active))
    end

    # 5. Detect interstates (within FAF5 only)
    has_fclass = "FCLASS" in names(dfL_active)
    fclass_col = has_fclass ? dfL_active.FCLASS : fill(missing, nrow(dfL_active))

    # 6. Categorize links and build polylines
    categories = ["FAF5_interstate", "FAF5_other", "OSM", "CONNECTOR"]
    polylines = Dict(cat => (Float64[], Float64[]) for cat in categories)

    # Reaccess filtered columns
    src_active = dfL_active[:, 1]
    dst_active = dfL_active[:, 2]

    for i in 1:nrow(dfL_active)
        source = coalesce(source_col[i], "FAF5")

        # Determine category
        if source == "FAF5" && has_fclass && !ismissing(fclass_col[i]) && fclass_col[i] == 1
            category = "FAF5_interstate"
        elseif source == "FAF5" || ismissing(source_col[i])
            category = "FAF5_other"
        elseif source == "OSM"
            category = "OSM"
        elseif source == "CONNECTOR"
            category = "CONNECTOR"
        else
            continue  # Unknown SOURCE value, skip
        end

        # Append coordinates with NaN separator
        src_lon, src_lat = node_lookup[src_active[i]]
        dst_lon, dst_lat = node_lookup[dst_active[i]]

        push!(polylines[category][1], src_lon, dst_lon, NaN)
        push!(polylines[category][2], src_lat, dst_lat, NaN)
    end

    # 7. Compute adaptive styling
    limits = ax.limits[]
    latspan = abs(limits[2][2] - limits[2][1])
    base_color = :gray55

    # Build style dictionary for each category
    styles = Dict{String, NamedTuple}()

    # FAF5 interstate
    lw = latspan > 20 ? 0.4 : (latspan > 10 ? 0.8 : 1.5)
    α = latspan > 20 ? 0.3 : (latspan > 10 ? 0.4 : 0.5)
    styles["FAF5_interstate"] = (linewidth=lw, color=(base_color, α))

    # FAF5 other
    lw = latspan > 20 ? 0.15 : (latspan > 10 ? 0.3 : 0.6)
    α = latspan > 20 ? 0.2 : (latspan > 10 ? 0.3 : 0.4)
    styles["FAF5_other"] = (linewidth=lw, color=(base_color, α))

    # OSM
    lw = latspan > 20 ? 0.1 : (latspan > 10 ? 0.2 : 0.35)
    α = latspan > 20 ? 0.15 : (latspan > 10 ? 0.2 : 0.3)
    styles["OSM"] = (linewidth=lw, color=(base_color, α))

    # CONNECTOR
    styles["CONNECTOR"] = (linewidth=0.3, color=(base_color, 0.15), linestyle=:dash)

    # 8. Render polylines
    handles = []
    for category in categories
        x_coords, y_coords = polylines[category]
        if length(x_coords) > 0
            style = styles[category]
            h = lines!(ax, x_coords, y_coords; style...)
            push!(handles, h)
        end
    end

    return handles
end

"""
    plotroute!(ax, lx, ly; kwargs...) → Vector

Base rendering method. Plots a route from coordinate vectors. `lx` and `ly` may
contain NaN separators (as produced by `rte2lines`) to represent multi-segment routes.
Origin and destination markers are placed at the first and last non-NaN points.

Returns a vector of plot handles: `[line_handle, origin_scatter, dest_scatter]`
(or `[line_handle]` when `show_markers=false`).

# Keyword arguments
- `color=:red`          – route line color
- `linewidth=2`         – route line width
- `show_markers=true`   – plot origin/destination scatter markers
- `origin_color=:green` – color of origin marker
- `dest_color=:blue`    – color of destination marker
- `markersize=10`       – marker size
"""
function plotroute!(ax, lx::AbstractVector{<:Real}, ly::AbstractVector{<:Real};
                    color=:red, linewidth=2,
                    show_markers=true,
                    origin_color=:green, dest_color=:blue,
                    markersize=10)
    handles = Any[]
    push!(handles, lines!(ax, lx, ly; color=color, linewidth=linewidth))
    if show_markers
        valid = findall(!isnan, lx)
        if !isempty(valid)
            push!(handles, scatter!(ax, [lx[valid[1]]], [ly[valid[1]]];
                                    color=origin_color, markersize=markersize))
            push!(handles, scatter!(ax, [lx[valid[end]]], [ly[valid[end]]];
                                    color=dest_color, markersize=markersize))
        end
    end
    return handles
end

"""
    plotroute!(ax, path::Vector{Int}, dfN::DataFrame; kwargs...) → Vector

Plot a route on a map axis. `path` is an ordered node-index sequence
(as returned by `tracepath`). Coordinates are looked up in `dfN.LON` / `dfN.LAT`.

# Keyword arguments
(see coordinate-vector method above)
"""
function plotroute!(ax, path::Vector{Int}, dfN::DataFrame;
                    color=:red, linewidth=2,
                    show_markers=true,
                    origin_color=:green, dest_color=:blue,
                    markersize=10)
    plotroute!(ax, dfN.LON[path], dfN.LAT[path];
               color=color, linewidth=linewidth,
               show_markers=show_markers,
               origin_color=origin_color, dest_color=dest_color,
               markersize=markersize)
end

"""
    plotroute!(ax, paths::Vector{Vector{Int}}, dfN::DataFrame; kwargs...) → Vector{Vector}

Multi-path variant. Each path is drawn in a different color (cycling through
`colors`). Returns a vector of handle vectors, one per path.

# Keyword arguments
- `colors=Makie.wong_colors()` – color palette to cycle through
- `linewidth=2`, `show_markers=true`, `markersize=10`
"""
function plotroute!(ax, paths::Vector{Vector{Int}}, dfN::DataFrame;
                    colors=Makie.wong_colors(), linewidth=2,
                    show_markers=true, markersize=10)
    all_handles = Vector{Any}[]
    for (i, path) in enumerate(paths)
        c = colors[mod1(i, length(colors))]
        h = plotroute!(ax, path, dfN;
                       color=c, linewidth=linewidth,
                       show_markers=show_markers,
                       origin_color=:green, dest_color=:blue,
                       markersize=markersize)
        push!(all_handles, h)
    end
    return all_handles
end

"""
    plotroute!(ax, route, shipments, parents, dfN; tr=..., kwargs...) → Vector

High-level method. Plots an optimized route directly from the solver output,
handling the full `rte2loc → rte2lines → render` pipeline internally.

# Arguments
- `route`: Route vector from `savings` or `twoopt`.
- `shipments::DataFrame`: Shipments with columns `b` (pickup) and `e` (delivery).
- `parents::Vector{Vector{Int}}`: Parent pointer matrix from `shortestpaths`.
- `dfN::DataFrame`: Nodes DataFrame with `LON` and `LAT` columns.

# Keyword arguments
- `tr=(b=Int[], e=Int[])` – terminal nodes for depot-return VRP (same as `rteTC`)
- plus all keyword arguments from the coordinate-vector method above
"""
function plotroute!(ax, route::AbstractVector{Int}, shipments::DataFrame,
                    parents::Vector{Vector{Int}}, dfN::DataFrame;
                    tr=(b=Int[], e=Int[]),
                    color=:red, linewidth=2,
                    show_markers=true,
                    origin_color=:green, dest_color=:blue,
                    markersize=10)
    loc_seq = rte2loc(route, shipments, tr)
    lx, ly = rte2lines(loc_seq, parents, dfN)
    plotroute!(ax, lx, ly;
               color=color, linewidth=linewidth,
               show_markers=show_markers,
               origin_color=origin_color, dest_color=dest_color,
               markersize=markersize)
end

"""
    plotroute!(ax, routes::Vector, shipments, parents, dfN; tr=..., kwargs...) → Vector{Vector}

Multi-route variant. Each route is drawn in a different color (cycling through `colors`).
All routes share the same `shipments`, `parents`, and optional terminal `tr`.
Returns a vector of handle vectors, one per route.

# Keyword arguments
- `colors=Makie.wong_colors()` – color palette to cycle through
- `tr=(b=Int[], e=Int[])` – shared terminal nodes (e.g., common depot)
- `linewidth=2`, `show_markers=true`, `markersize=10`
"""
function plotroute!(ax, routes::Vector{<:AbstractVector{Int}}, shipments::DataFrame,
                    parents::Vector{Vector{Int}}, dfN::DataFrame;
                    tr=(b=Int[], e=Int[]),
                    colors=Makie.wong_colors(),
                    linewidth=2, show_markers=true, markersize=10)
    all_handles = Vector{Any}[]
    for (i, route) in enumerate(routes)
        c = colors[mod1(i, length(colors))]
        h = plotroute!(ax, route, shipments, parents, dfN;
                       tr=tr, color=c, linewidth=linewidth,
                       show_markers=show_markers,
                       origin_color=:green, dest_color=:blue,
                       markersize=markersize)
        push!(all_handles, h)
    end
    return all_handles
end
