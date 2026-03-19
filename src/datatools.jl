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
        if startswith(fn, "faf5_")
            data_dir = artifact"faf5"
        else
            data_dir = joinpath(dirname(@__FILE__), "..", "data")
        end
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
# Helper Functions (H1–H4)
# =============================================================================

"""
    mat2df(X::AbstractMatrix, cols::AbstractVector; rows=nothing) -> DataFrame

Convert a matrix to a labeled DataFrame.

# Arguments
- `X`: Matrix of values.
- `cols`: Column names (length must equal `size(X, 2)`).
- `rows`: Optional row labels. If provided (length must equal `size(X, 1)`),
  inserted as the first column with a blank header.

# Example
```jldoctest
julia> mat2df([1 2; 3 4], ["A", "B"])
2×2 DataFrame
 Row │ A      B
     │ Int64  Int64
─────┼──────────────
   1 │     1      2
   2 │     3      4

julia> mat2df([1 2; 3 4], ["A", "B"]; rows=["r1", "r2"])
2×3 DataFrame
 Row │         A      B
     │ String  Int64  Int64
─────┼──────────────────────
   1 │ r1          1      2
   2 │ r2          3      4
```
"""
function mat2df(X::AbstractMatrix, cols::AbstractVector; rows::Union{Nothing, AbstractVector}=nothing)
    if length(cols) != size(X, 2)
        throw(ArgumentError("length(cols) = $(length(cols)) must equal size(X, 2) = $(size(X, 2))"))
    end
    if rows !== nothing && length(rows) != size(X, 1)
        throw(ArgumentError("length(rows) = $(length(rows)) must equal size(X, 1) = $(size(X, 1))"))
    end
    df = DataFrame(X, Symbol.(cols))
    if rows !== nothing
        insertcols!(df, 1, Symbol("") => rows)
    end
    return df
end

"""
    prt(X; rows, cols, title, fracdig, allfrac, row_title)

Pretty-print a matrix, vector, or DataFrame with smart formatting.

Formatted display with right-aligned columns. For matrices, applies smart per-column
digit detection inspired by MATLOG's `mdisp`: integer columns show 0 decimal places,
all-fractional columns (all values < 1) show `allfrac` decimal places, and mixed
columns show `fracdig` decimal places. NaN values display as blank. Numbers ≥ 1,000
include comma separators. The `row_title` keyword places a header in the
upper-left corner of the table (the row-label column header).

# Matrix method
    prt(X::AbstractMatrix; rows=1:size(X,1), cols=1:size(X,2), title="", fracdig=2, allfrac=4, row_title="", str=false)

# Vector method
    prt(v::AbstractVector; rows=1:length(v), title="", row_title="", str=false)

# DataFrame method
    prt(df::DataFrame; title="", str=false)

With `str=true`, returns the formatted table as a string (separator lines stripped)
instead of printing. Default behavior prints to stdout and returns `nothing`.

# Examples
```julia
julia> prt([1000 0.1234; 2000 0.5678])
──── ──── ────────
   1    2
──── ──── ────────
  1  1,000   0.1234
  2  2,000   0.5678
──── ──── ────────

julia> prt([1 2; 3 4]; rows=["a","b"], cols=["X","Y"], row_title="ID")
──── ──── ────
  ID    X    Y
──── ──── ────
   a    1    2
   b    3    4
──── ──── ────
```
"""
function prt(X::AbstractMatrix; rows=1:size(X, 1), cols=1:size(X, 2),
             title::AbstractString="", fracdig::Int=2, allfrac::Int=4,
             row_title::AbstractString="", str::Bool=false)
    m, n = size(X)
    if m == 0 || n == 0
        str && return ""
        println("Empty matrix")
        return nothing
    end

    # Smart per-column digit detection
    ndigs = Vector{Int}(undef, n)
    for j in 1:n
        col_vals = X[:, j]
        real_vals = filter(v -> !isnan(v) && !isinf(v), col_vals)

        if isempty(real_vals)
            ndigs[j] = fracdig
        elseif all(v -> v == round(v), real_vals)
            ndigs[j] = 0
        elseif all(v -> abs(v) < 1, real_vals)
            ndigs[j] = allfrac
        else
            ndigs[j] = fracdig
        end
    end

    formatter = (v, i, j) -> begin
        v isa Real || return string(v)
        isnan(v) && return ""
        isinf(v) && return string(v)
        nd = ndigs[j]
        rounded = round(v, digits=nd)
        nd == 0 ? _commasep(round(Int64, rounded)) : _formatfixed(rounded, nd)
    end

    # Display
    col_labels = string.(cols)
    row_lbls = string.(rows)

    if str
        buf = IOBuffer()
        io = IOContext(buf, :displaysize => (typemax(Int), typemax(Int)))
        _print_table(io, X; column_labels=col_labels, row_labels=row_lbls,
                     formatter=formatter, title=title, stubhead_label=row_title)
        return String(take!(buf))
    else
        io = IOContext(stdout, :displaysize => (typemax(Int), typemax(Int)))
        _print_table(io, X; column_labels=col_labels, row_labels=row_lbls,
                     formatter=formatter, title=title, stubhead_label=row_title)
        return nothing
    end
end

function prt(v::AbstractVector; rows=1:length(v), title::AbstractString="",
             row_title::AbstractString="", str::Bool=false)
    prt(reshape(v, :, 1); rows=rows, cols=[""], title=title, row_title=row_title, str=str)
end

function prt(df::DataFrame; title::AbstractString="", str::Bool=false)
    # Separate string columns (used as row labels) from numeric columns
    str_cols = [c for c in names(df) if eltype(df[!, c]) <: AbstractString]
    num_cols = [c for c in names(df) if !(eltype(df[!, c]) <: AbstractString)]

    if isempty(num_cols)
        # All string columns — pass through without formatting
        if str
            buf = IOBuffer()
            io = IOContext(buf, :displaysize => (typemax(Int), typemax(Int)))
            _print_table(io, Matrix(df); column_labels=string.(names(df)), title=title)
            return String(take!(buf))
        else
            io = IOContext(stdout, :displaysize => (typemax(Int), typemax(Int)))
            _print_table(io, Matrix(df); column_labels=string.(names(df)), title=title)
            return nothing
        end
    elseif isempty(str_cols)
        # All numeric — use matrix prt with column names
        prt(Matrix(df); cols=names(df), title=title, str=str)
    else
        # Mixed: first string column as row labels, rest through matrix prt
        row_labels = df[!, str_cols[1]]
        remaining = [c for c in names(df) if c != str_cols[1]]
        num_remaining = [c for c in remaining if !(eltype(df[!, c]) <: AbstractString)]
        prt(Matrix(df[!, num_remaining]); rows=row_labels, cols=num_remaining, title=title, str=str)
    end
end

# Internal: lightweight table printer replacing PrettyTables
function _print_table(io::IO, X::AbstractMatrix;
                      column_labels::Vector{String}=String[],
                      row_labels::Vector{String}=String[],
                      formatter=nothing,
                      title::String="",
                      stubhead_label::String="")
    m, n = size(X)

    # Format all cells
    cells = Matrix{String}(undef, m, n)
    for j in 1:n, i in 1:m
        cells[i, j] = formatter !== nothing ? string(formatter(X[i, j], i, j)) : string(X[i, j])
    end

    # Column widths from data and headers
    col_widths = [maximum(length(cells[i, j]) for i in 1:m; init=0) for j in 1:n]
    if !isempty(column_labels)
        for j in 1:n
            col_widths[j] = max(col_widths[j], length(column_labels[j]))
        end
    end

    # Row label width
    has_rows = !isempty(row_labels)
    rl_width = 0
    if has_rows
        rl_width = maximum(length(l) for l in row_labels; init=0)
        if !isempty(stubhead_label)
            rl_width = max(rl_width, length(stubhead_label))
        end
    end

    # Title
    if !isempty(title)
        println(io, title)
    end

    # Header row
    if !isempty(column_labels)
        if has_rows
            print(io, lpad(stubhead_label, rl_width))
        end
        for j in 1:n
            print(io, "  ", lpad(column_labels[j], col_widths[j]))
        end
        println(io)
        # Separator
        total_w = sum(col_widths) + 2 * n + (has_rows ? rl_width : 0)
        println(io, '─'^total_w)
    end

    # Data rows
    for i in 1:m
        if has_rows
            print(io, lpad(row_labels[i], rl_width))
        end
        for j in 1:n
            print(io, "  ", lpad(cells[i, j], col_widths[j]))
        end
        println(io)
    end
end

# Internal: comma-separate an integer
function _commasep(n::Integer)
    s = string(abs(n))
    parts = String[]
    while length(s) > 3
        push!(parts, s[end-2:end])
        s = s[1:end-3]
    end
    push!(parts, s)
    result = join(reverse(parts), ",")
    return n < 0 ? "-" * result : result
end

# Internal: format with fixed decimal places and comma separators
function _formatfixed(v::Real, ndig::Int)
    intpart = trunc(Int64, v)
    fracpart = abs(v - intpart)
    fracstr = string(round(fracpart, digits=ndig))[2:end]  # ".xxxx"
    # Pad fractional part if needed
    while length(fracstr) - 1 < ndig
        fracstr *= "0"
    end
    # Truncate if too long
    fracstr = fracstr[1:min(ndig+1, length(fracstr))]
    return _commasep(intpart) * fracstr
end

"""
    snapvals(x; atol=1e-8) -> Array
    snapvals(x, n, m; atol=1e-8) -> Matrix

Snap near-integer and near-zero floating-point values in an array.

Designed for post-processing mathematical programming solutions where solvers
introduce small numerical artifacts (e.g., 2.9999999997 instead of 3, or
1.2e-12 instead of 0). Each element is rounded to the nearest integer if within
`atol`, and values that round to zero are set to exactly `0.0`.

**Caveat:** Snapping may cause constraint violations in some models. When snapped
values are used in further computation, verify feasibility — particularly for
models with big-M constraints where rounding a near-zero binary variable to 0
can violate the associated constraint by a large amount.

# Arguments
- `x`: Array of numeric values (typically from `value.(x)` after JuMP solve).
- `n`, `m`: Optional dimensions for reshaping the result.
- `atol`: Tolerance for snapping (default: `1e-8`).

# Example
```jldoctest
julia> snapvals([2.9999999997, 1e-12, 0.5])
3-element Vector{Float64}:
 3.0
 0.0
 0.5

julia> snapvals([1.0, 2.0, 3.0, 4.0], 2, 2)
2×2 Matrix{Float64}:
 1.0  3.0
 2.0  4.0
```
"""
function snapvals(x; atol::Real=1e-8)
    arr = Array(x)
    return map(arr) do v
        r = round(v)
        y = isapprox(v, r; atol=atol) ? r : v
        iszero(y) ? 0.0 : Float64(y)
    end
end

function snapvals(x, n::Int, m::Int; atol::Real=1e-8)
    return reshape(snapvals(x; atol=atol), n, m)
end


# =============================================================================
# Relocated Functions (from MapTools — pure computation, no plotting dependency)
# =============================================================================

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
    if !(pt isa Tuple || pt isa AbstractVector) || length(pt) != 2
        throw(ArgumentError("The point 'pt' must be a tuple or vector with exactly two elements (x, y)."))
    end
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