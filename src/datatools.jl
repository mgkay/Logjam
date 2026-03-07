# DataTools - Functions for working with U.S. geographical and statistical data

"""
    loaddata(fn::String) -> Any

Loads and returns data from a serialized file in the "data" directory.

The function attempts to deserialize the specified file with a `.jls` extension. If an error occurs during loading, the function prints an error message and rethrows the exception.

- `fn`: String representing the filename (without extension) of the data to be loaded.
"""
function loaddata(fn)
    try
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        return open(deserialize, joinpath(data_dir, fn * ".jls"))
    catch e
        println("Failed to load data: ", e)
        throw(e)
    end
end

"""
    usplace() -> DataFrame

Returns DataFrame containing U.S. place data.

Geographic and population data for each place in the U.S., where each place is a city, town, or census-designated place (CDP). The latitude-longitude of each place represents a central location interior to the place and not its center of population.  Does not include U.S. territories.

# Columns
- `STFIP`: Integer representing state FIPS (Federal Information Processing Standards) code.
- `PLFIP`: Integer representing place FIPS code.
- `NAME`: String containing name of place (city, town, or CDP).
- `ST`: Symbol representing state abbreviation (e.g., :AL for Alabama).
- `LAT`: Float representing an interior latitude of place.
- `LON`: Float representing an interior longitude of place.
- `POP`: Integer representing population of place.
- `ALAND`: Float representing land area of place in square miles.
- `AWATER`: Float representing water area of place in square miles.
- `LSAD`: Integer representing legal/statistical area description code (e.g., 25 for a place).
- `FUNCSTAT`: String representing functional status of place (e.g., A for active).
- `CBSA`: Integer or None representing Core-Based Statistical Area code associated with place.
- `ISCUS`: Boolean indicating whether place is within continental U.S. (true or false).

# Sources
Geographic data derived from [1], population data from [2], and `CBSA` from [3]. `ICUS` determined from `LAT` and `LON`.

1.  U.S. Census Bureau, 2020 Gazetteer Files, [2020_Gaz_place_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_place_national.zip)

2. U.S. Census Bureau, 2020 Census Demographic and Housing Characteristics File (DHC), [DECENNIALDHC2020.P1](https://data.census.gov/table/DECENNIALDHC2020.P1?t=Populations%20and%20People&g=010XX00US\$1600000)

3. U.S. Census Bureau, Principal cities of metropolitan and micropolitan statistical areas, [list2_2023.xls](https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list2_2023.xlsx)
"""
function usplace()
    return loaddata("usplace")
end

"""
    uscounty() -> DataFrame

Returns DataFrame containing U.S. county-level data.

Geographic and population data for each U.S. county, including latitude-longitude coordinates representing the center of population of the county. Does not include U.S. territories.

# Columns
- `STFIP`: Integer representing state FIPS (Federal Information Processing Standards) code.
- `COFIP`: Integer representing county FIPS code.
- `NAME`: String containing name of county.
- `ST`: Symbol representing state abbreviation (e.g., :AL for Alabama).
- `LAT`: Float representing latitude of county center of population.
- `LON`: Float representing longitude of county center of population.
- `POP`: Integer representing population of county.
- `ALAND`: Float representing land area of county in square miles.
- `AWATER`: Float representing water area of county in square miles.
- `CBSA`: Integer or None representing Core-Based Statistical Area code associated with county.

# Sources
Area data from [1], population and center of population data from [2], and CBSA data from [3].

1. U.S. Census Bureau, 2020 Gazetteer Files, [2020_Gaz_county_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_county_national.zip)

2. U.S. Census Bureau, Centers of Population, [CenPop2020_Mean_CO.txt](https://www2.census.gov/geo/docs/reference/cenpop2020/county/CenPop2020_Mean_CO.txt)

3. U.S. Census Bureau, Core based statistical areas (CBSAs), metropolitan divisions, and combined statistical areas (CSAs), [list1_2023.xls](https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list1_2023.xlsx)
"""
function uscounty()
    return loaddata("uscounty")
end

"""
    uscentract() -> DataFrame

Returns DataFrame containing U.S. census tract-level data.

Geographic and population data for each U.S. census tract, including latitude-longitude coordinates representing the center of population of the tract. Does not include U.S. territories.

# Columns
- `STFIP`: Integer representing state FIPS (Federal Information Processing Standards) code.
- `COFIP`: Integer representing county FIPS code.
- `TRFIP`: Integer representing census tract FIPS code.
- `ST`: Symbol representing state abbreviation (e.g., :AL for Alabama).
- `LAT`: Float representing latitude of census tract center of population.
- `LON`: Float representing longitude of census tract center of population.
- `POP`: Integer representing population of census tract.
- `ALAND`: Float representing land area of census tract in square miles.
- `AWATER`: Float representing water area of census tract in square miles.
- `ISCUS`: Boolean indicating whether census tract is within continental U.S. (true or false).

# Sources
Area data from [1]. Population and center of population data from [2].

1. U.S. Census Bureau, 2020 Gazetteer Files, [2020_Gaz_tract_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_tract_national.zip)

2. U.S. Census Bureau, Centers of Population, [CenPop2020_Mean_TR.txt](https://www2.census.gov/geo/docs/reference/cenpop2020/tract/CenPop2020_Mean_TR.txt)
"""
function uscentract()
    return loaddata("uscentract")
end

"""
    uscenblkgrp() -> DataFrame

Returns DataFrame containing U.S. census block group-level data.

Geographic and population data for each U.S. census block group, including latitude-longitude coordinates representing the center of population of the block group.  Does not include U.S. territories.

# Columns
- `STFIP`: Integer representing state FIPS (Federal Information Processing Standards) code.
- `COFIP`: Integer representing county FIPS code.
- `TRFIP`: Integer representing census tract FIPS code.
- `BGFIP`: Integer representing census block group FIPS code.
- `LAT`: Float representing latitude of block group center of population.
- `LON`: Float representing longitude of block group center of population.
- `POP`: Integer representing population of block group.
- `ALAND`: Float representing land area of block group in square miles.
- `AWATER`: Float representing water area of block group in square miles.

# Sources
Area data from [1]. Population and center of population data from [2].

1. U.S. Census Bureau, TIGER/Line Shapefiles for 2020 Census Block Groups, [https://www2.census.gov/geo/tiger/TIGER2020/BG/]

2. U.S. Census Bureau, Centers of Population, [CenPop2020_Mean_BG.txt](https://www2.census.gov/geo/docs/reference/cenpop2020/blockgroup/CenPop2020_Mean_BG.txt)
"""
function uscenblkgrp()
    return loaddata("uscenblkgrp")
end

"""
    uszcta5() -> DataFrame

Returns DataFrame containing U.S. 5-digit ZIP Code Tabulation Area (ZCTA5) data.

Geographic and population data for each U.S. 5-digit ZIP Code Tabulation Area (ZCTA5). The latitude-longitude of each ZCTA5 represents a central location within the ZCTA5 and not its center of population. Does not include U.S. territories.

# Columns
- `ZCTA5`: Integer (<= 5 digits) representing the ZIP Code Tabulation Area (ZCTA5) code.
- `LAT`: Float representing an interior latitude of ZCTA5.
- `LON`: Float representing an interior longitude of ZCTA5.
- `POP`: Integer representing population of ZCTA5.
- `ALAND`: Float representing land area of ZCTA5 in square miles.
- `AWATER`: Float representing water area of ZCTA5 in square miles.
- `ISCUS`: Boolean indicating whether ZCTA5 is within continental U.S. (true or false).

# Sources
Geographic data derived from [1]. Population data derived from [2]. `ISCUS` determined from `LAT` and `LON`.

1. U.S. Census Bureau, 2023 Gazetteer Files, [2023_Gaz_zcta_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2023_Gazetteer/2023_Gaz_zcta_national.zip)

2. U.S. Census Bureau, 2020 Census Demographic and Housing Characteristics File (DHC), [DECENNIALDHC2020.P1](https://data.census.gov/table?t=Populations%20and%20People&g=010XX00US\$8600000)
"""
function uszcta5()
    return loaddata("uszcta5")
end

"""
    uszcta3() -> DataFrame

Returns DataFrame containing U.S. 3-digit ZIP Code Tabulation Area (ZCTA3) data.

Geographic and population data for each U.S. 3-digit ZIP Code Tabulation Area (ZCTA3). The latitude-longitude of each ZCTA3 represents its approximate center of population. ZCTA3s are approximated by aggregating ZCTA5s: summing population and areas, and approximating the center of population by calculating the population-weighted centroid of the ZCTA5s' interior locations. Does not include U.S. territories.

# Columns
- `ZCTA3`: Integer (<= 3 digits) representing the 3-digit ZIP Code Tabulation Area (ZCTA3) code.
- `LAT`: Float representing latitude of ZCTA3 approximate center of population.
- `LON`: Float representing longitude of ZCTA3 approximate center of population.
- `POP`: Integer representing population of ZCTA3.
- `ALAND`: Float representing land area of ZCTA3 in square miles.
- `AWATER`: Float representing water area of ZCTA3 in square miles.
- `ISCUS`: Boolean indicating whether ZCTA3 is within continental U.S. (true or false).

# Sources
All data derived from `uszcta5`.
"""
function uszcta3()
    return loaddata("uszcta3")
end

"""
    uscbsa() -> DataFrame

Returns DataFrame containing U.S. Core-Based Statistical Area (CBSA) data.

Geographic and population data for each U.S. CBSA. The latitude-longitude of each CBSA represents its center of population. CBSA geographic and populations are determiend by aggregating its constituent counties: summing population and areas, and determining the center of population by calculating the population-weighted centroid of the county centers of population. Does not include U.S. territories.

# Columns
- `CBSA`: Integer representing Core-Based Statistical Area code.
- `NAME`: String containing name of CBSA.
- `LAT`: Float representing latitude of CBSA center of population.
- `LON`: Float representing longitude of CBSA center of population.
- `POP`: Integer representing population of CBSA.
- `ALAND`: Float representing land area of CBSA in square miles.
- `AWATER`: Float representing water area of CBSA in square miles.
- `M_MSA`: String indicating whether CBSA is a Metropolitan Statistical Area or a Micropolitan Statistical Area.
- `CSA`: Integer or None representing Combined Statistical Area code if CBSA is part of a CSA.
- `ISCUS`: Boolean indicating whether CBSA is within continental U.S. (true or false).

# Sources
CBSA delineations and classifications from [1]. Geographic and population data from `uscounty()`.

1. U.S. Census Bureau, Core based statistical areas (CBSAs), metropolitan divisions, and combined statistical areas (CSAs), [list1_2023.xls](https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list1_2023.xlsx)
"""
function uscbsa()
    return loaddata("uscbsa")
end

"""
    uscsa() -> DataFrame

Returns DataFrame containing U.S. Combined Statistical Area (CSA) data.

Geographic and population data for each U.S. CSA. The latitude-longitude of each CSA represents its center of population. CSA geographic and populations are determined by aggregating its constituent CBSAs: summing population and areas, and determining the center of population by calculating the population-weighted centroid of the CBSA centers of population. Does not include U.S. territories.

# Columns
- `CSA`: Integer representing Combined Statistical Area code.
- `NAME`: String containing name of CSA.
- `LAT`: Float representing latitude of CSA center of population.
- `LON`: Float representing longitude of CSA center of population.
- `POP`: Integer representing population of CSA.
- `ALAND`: Float representing land area of CSA in square miles.
- `AWATER`: Float representing water area of CSA in square miles.

# Sources
CSA delineations and classifications from [1]. Geographic and population data from `uscbsa()`.

1. U.S. Census Bureau, 2023 Combined Statistical Area (CSA) Codes, [list2_2023.xls](https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2020/delineation-files/list2_2023.xls)
"""
function uscsa()
    return loaddata("uscsa")
end

# Define the mapping of state symbols to FIPS codes (as integers)
const state_fips = Dict(
    :AL => 1, :AK => 2, :AZ => 4, :AR => 5, :CA => 6,
    :CO => 8, :CT => 9, :DE => 10, :FL => 12, :GA => 13,
    :HI => 15, :ID => 16, :IL => 17, :IN => 18, :IA => 19,
    :KS => 20, :KY => 21, :LA => 22, :ME => 23, :MD => 24,
    :MA => 25, :MI => 26, :MN => 27, :MS => 28, :MO => 29,
    :MT => 30, :NE => 31, :NV => 32, :NH => 33, :NJ => 34,
    :NM => 35, :NY => 36, :NC => 37, :ND => 38, :OH => 39,
    :OK => 40, :OR => 41, :PA => 42, :RI => 44, :SC => 45,
    :SD => 46, :TN => 47, :TX => 48, :UT => 49, :VT => 50,
    :VA => 51, :WA => 53, :WV => 54, :WI => 55, :WY => 56,
    :DC => 11, :AS => 60, :GU => 66, :MP => 69, :PR => 72,
    :VI => 78
)

# Convert state symbol to FIPS code
"""
    st2fips(state::Symbol) -> Integer

Convert a two-character symbol for US states and territories to its corresponding FIPS code.

Valid two-character symbols of the state or territory are
$(join(sort(collect(keys(state_fips))), ", "))

# Examples
```jldoctest
julia> st2fips(:NC)
37

julia> st2fips.([:NC, :NY])
2-element Vector{Int64}:
 37
 36
```
"""
function st2fips(state::Symbol)
    if state in keys(state_fips)
        return state_fips[state]
    else
        error_message = "Error: '$state' is not a valid US state or territory symbol."
        throw(ArgumentError(error_message))
    end
end

# Reverse mapping: FIPS code to state symbol
const fips_state = Dict(v => k for (k, v) in state_fips)

"""
    fips2st(fips::Integer) -> Symbol

Convert a FIPS code to its corresponding two-character state or territory symbol.

Valid FIPS codes are: $(join(sort(collect(keys(fips_state))), ", "))

# Arguments
- `fips`: An integer representing the FIPS code.

# Returns
- A `Symbol` representing the two-character state or territory abbreviation.

# Throws
- `ArgumentError` if the FIPS code is not valid.

# Examples
```jldoctest
julia> fips2st(37)
:NC

julia> fips2st(36)
:NY

julia> fips2st.(37:39)
3-element Vector{Symbol}:
 :NC
 :ND
 :OH
```
"""
function fips2st(fips::Integer)
    if fips in keys(fips_state)
        return fips_state[fips]
    else
        throw(ArgumentError("Error: '$fips' is not a valid US state or territory FIPS code."))
    end
end

# =============================================================================
# FAF5 Road Network Data
# =============================================================================

"""
    loadcsvdata(fn::String) -> DataFrame

Loads and returns data from a CSV file in the "data" directory.

- `fn`: String representing the filename (without extension) of the data to be loaded.
"""
function loadcsvdata(fn)
    try
        data_dir = joinpath(dirname(@__FILE__), "..", "data")
        return CSV.read(joinpath(data_dir, fn * ".csv"), DataFrame)
    catch e
        println("Failed to load CSV data: ", e)
        throw(e)
    end
end

"""
    faf5nodes() -> DataFrame

Returns DataFrame containing FAF5 road network nodes.

Physical road network nodes from the Freight Analysis Framework version 5 (FAF5).
Centroid nodes (artificial FAF zone connectors) are excluded.

# Columns
- `IDX`: Integer node identifier (non-sequential due to centroid removal).
- `LON`: Float representing longitude of node.
- `LAT`: Float representing latitude of node.
- `ENTRY_EXIT`: Entry/exit indicator for interchanges.
- `EXIT_NUM`: Exit number (if applicable).
- `INTERCHANGE`: Interchange name (if applicable).
- `FACILITY_TYPE`: Facility type code (port, airport, etc.).
- `FACILITY_NAME`: Facility name (if applicable).
- `STATEID`: Integer state FIPS code.
- `FAFID`: Integer FAF zone identifier.

# Sources
U.S. Department of Transportation, Bureau of Transportation Statistics,
Freight Analysis Framework (FAF5) Network,
https://geodata.bts.gov/datasets/usdot::freight-analysis-framework-faf5-network-nodes/about
"""
function faf5nodes()
    return loadcsvdata("faf5_nodes")
end

"""
    faf5links() -> DataFrame

Returns DataFrame containing FAF5 road network links.

Physical road network links from the Freight Analysis Framework version 5 (FAF5).
Links connecting to centroid nodes are excluded.

# Columns
- `SRC`: Integer source node ID.
- `DST`: Integer destination node ID.
- `DIST`: Float link distance in miles.
- `STFIP`: Integer state FIPS code.
- `COFIP`: Integer county FIPS code.
- `SPEED`: Integer posted speed limit (mph).
- `NHS`: Integer National Highway System code.
- `SIGN`: String signed route (e.g., "I 40", "US 1").
- `NAME`: String road name.
- `FCLASS`: Integer functional classification code.
- `URBAN`: String urban area code.
- `AB_SPEED`: Float final speed A→B direction (mph).
- `BA_SPEED`: Float final speed B→A direction (mph).
- `AB_TIME`: Float free-flow travel time A→B (minutes).
- `BA_TIME`: Float free-flow travel time B→A (minutes).
- `AB_LANES`: Integer lane count A→B direction.
- `BA_LANES`: Integer lane count B→A direction.
- `DIR`: Integer direction code.
- `STRAHNET`: Integer Strategic Highway Network code.
- `NHFN`: Integer National Highway Freight Network code.
- `TOLL_TYPE`: Integer toll classification.
- `TOLL_LINK`: Integer toll road indicator (0/1).
- `BORDER_LINK`: Integer border crossing indicator (0/1).
- `FAFZONE`: Integer FAF zone identifier.
- `STATUS`: Integer road status code.

# Sources
U.S. Department of Transportation, Bureau of Transportation Statistics,
Freight Analysis Framework (FAF5) Network,
https://geodata.bts.gov/datasets/usdot::freight-analysis-framework-faf5-network-links/about
"""
function faf5links()
    return loadcsvdata("faf5_links")
end

"""
    faf5interstate() -> Tuple{Vector{Float64}, Vector{Float64}}

Returns polyline vectors for FAF5 interstate road network.

Returns a tuple `(x, y)` of coordinate vectors with NaN separators between segments.
This format is directly compatible with Makie's `lines!()` function for plotting
road network backgrounds.

# Usage
```julia
x, y = faf5interstate()
lines!(ax, x, y, color=(:steelblue, 0.3), linewidth=0.5)
```

# Sources
Derived from FAF5 links where SIGN starts with "I " (interstate routes).
"""
function faf5interstate()
    return loaddata("faf5_interstate_roads")
end

# =============================================================================
# Geographic Name Lookup
# =============================================================================

"""
    name2lonlat(name, df; st=nothing) -> Vector{Float64}

Convert city name to longitude-latitude coordinates.

Searches DataFrame for matching city name, optionally filtered by state.
Supports "City, ST" format parsing.

# Arguments
- `name`: City name string, or "City, ST" format.
- `df`: DataFrame with `:NAME`, `:ST`, `:LON`, `:LAT` columns (e.g., from usplace()).
- `st`: State abbreviation to filter search (default: nothing, search all states).

# Returns
- [LON, LAT] vector for the first matching city.

# Example
```julia
cities = usplace()
name2lonlat("Raleigh", cities; st="NC")
name2lonlat("Raleigh, NC", cities)  # Alternative format
```
"""
function name2lonlat(name::AbstractString, df::DataFrame; st=nothing)
    # Parse "City, ST" format
    if occursin(", ", name)
        parts = split(name, ", ")
        length(parts) == 2 || error("Invalid format: $name")
        name, st = parts[1], parts[2]
    end

    # Search with optional state filter (convert st to Symbol if needed)
    if isnothing(st)
        idx = findfirst(r -> r.NAME == name, eachrow(df))
    else
        st_sym = st isa Symbol ? st : Symbol(st)
        idx = findfirst(r -> r.NAME == name && r.ST == st_sym, eachrow(df))
    end

    isnothing(idx) && error("'$name' not found in DataFrame")

    return [df[idx, :LON], df[idx, :LAT]]
end

"""
    lonlat2name(XY, df; threshold=4.0) -> DataFrame

Find nearest cities to given coordinates (reverse geocoding).

# Arguments
- `XY`: n×2 matrix of [LON, LAT] coordinates, or single [LON, LAT] vector.
- `df`: DataFrame with `:NAME`, `:ST`, `:LON`, `:LAT` columns (e.g., from usplace()).
- `threshold`: Distance threshold (miles) for "in city" vs "X mi DIR of city" (default: 4.0).

# Returns
- DataFrame with columns:
  - `:idx` nearest city index
  - `:name` nearest city name
  - `:st` nearest city state abbreviation
  - `:dist` distance in miles
  - `:bearing` radians clockwise from north (0 to 2π)
  - `:dir` 8-point compass direction (`N`, `NE`, ..., `NW`)
  - `:desc` human-readable description

# Example
```julia
cities = usplace()
xy = [-78.6382 35.7796; -80.8431 35.2271]  # Raleigh, Charlotte
lonlat2name(xy, cities)
```
"""
function lonlat2name(XY, df::DataFrame; threshold=4.0)
    # Convert vector to 1x2 matrix
    if XY isa AbstractVector
        length(XY) == 2 || throw(ArgumentError("XY vector must have length 2 [LON, LAT]."))
        XY = reshape(XY, 1, 2)
    end

    # Compute distances to all cities
    city_coords = hcat(df.LON, df.LAT)
    D = dists(XY, city_coords, :mi)

    # Find nearest for each query point
    results = DataFrame(
        idx = Int[],
        name = String[],
        st = String[],
        dist = Float64[],
        bearing = Float64[],
        dir = String[],
        desc = String[]
    )

    dir_labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    for i in 1:size(D, 1)
        j = argmin(D[i, :])
        dist = D[i, j]
        st = String(df.ST[j])

        # Great-circle initial bearing from nearest city to query location
        lon1, lat1 = deg2rad(df.LON[j]), deg2rad(df.LAT[j])
        lon2, lat2 = deg2rad(XY[i, 1]), deg2rad(XY[i, 2])

        bearing = mod(
            atan(
                cos(lat2) * sin(lon2 - lon1),
                cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1)
            ),
            2pi
        )

        bearing_deg = rad2deg(bearing)
        dir_idx = (Int(floor((bearing_deg + 22.5) / 45.0)) % 8) + 1
        dir = dir_labels[dir_idx]

        desc = if dist < threshold
            "in " * String(df.NAME[j]) * ", " * st
        else
            string(round(dist, digits=1)) * " mi " * dir * " of " * String(df.NAME[j]) * ", " * st
        end

        push!(results, (
            idx=j,
            name=String(df.NAME[j]),
            st=st,
            dist=dist,
            bearing=bearing,
            dir=dir,
            desc=desc
        ))
    end

    return results
end