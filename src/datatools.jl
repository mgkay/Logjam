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
        @error "Failed to load data" exception=(e, catch_backtrace())
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
- `LON`: Float representing an interior longitude of place.
- `LAT`: Float representing an interior latitude of place.
- `POP`: Integer representing population of place.
- `ALAND`: Float representing land area of place in square miles.
- `AWATER`: Float representing water area of place in square miles.
- `LSAD`: Integer representing legal/statistical area description code (e.g., 25 for a place).
- `FUNCSTAT`: String representing functional status of place (e.g., A for active).
- `CBSA`: Integer or None representing Core-Based Statistical Area code associated with place.
- `ISCUS`: Boolean indicating whether place is within continental U.S. (true or false).

# Sources
Geographic data derived from [1], population data from [2], and `CBSA` from [3]. `ISCUS` determined from `LAT` and `LON`.

1.  U.S. Census Bureau, 2020 Gazetteer Files, [2020_Gaz_place_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_place_national.zip)

2. U.S. Census Bureau, 2020 Census Demographic and Housing Characteristics File (DHC), [DECENNIALDHC2020.P1](https://data.census.gov/table/DECENNIALDHC2020.P1?t=Populations%20and%20People&g=010XX00US\$1600000)

3. U.S. Census Bureau, Principal cities of metropolitan and micropolitan statistical areas, [list2_2023.xls](https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list2_2023.xlsx)

# Example
```julia
df = usplace()
names(df)   # => ["STFIP", "PLFIP", "NAME", "ST", "LON", "LAT", "POP", "ALAND", "AWATER", "LSAD", "FUNCSTAT", "CBSA", "ISCUS"]  (LON precedes LAT)
filter(r -> r.ST == :NC, df)    # => 776 places in North Carolina
```
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
- `LON`: Float representing longitude of county center of population.
- `LAT`: Float representing latitude of county center of population.
- `POP`: Integer representing population of county.
- `ALAND`: Float representing land area of county in square miles.
- `AWATER`: Float representing water area of county in square miles.
- `CBSA`: Integer or None representing Core-Based Statistical Area code associated with county.
- `ISCUS`: Boolean indicating whether county is within continental U.S. (true or false).

# Sources
Area data from [1], population and center of population data from [2], and CBSA data from [3]. `ISCUS` determined from `LAT` and `LON`.

1. U.S. Census Bureau, 2020 Gazetteer Files, [2020_Gaz_county_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_county_national.zip)

2. U.S. Census Bureau, Centers of Population, [CenPop2020_Mean_CO.txt](https://www2.census.gov/geo/docs/reference/cenpop2020/county/CenPop2020_Mean_CO.txt)

3. U.S. Census Bureau, Core based statistical areas (CBSAs), metropolitan divisions, and combined statistical areas (CSAs), [list1_2023.xls](https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list1_2023.xlsx)

# Example
```julia
df = uscounty()
names(df)     # => ["STFIP", "COFIP", "NAME", "ST", "LON", "LAT", "POP", "ALAND", "AWATER", "CBSA", "ISCUS"]
first(df, 5)  # LON precedes LAT
```
"""
function uscounty()
    return loaddata("uscounty")
end

# The state table is aggregated from `uscounty()` once per session and kept here; each call returns a copy.
const _usstate_cache = Ref{Union{Nothing, DataFrame}}(nothing)
const _usstate_lock = ReentrantLock()

function _build_usstate()
    c = uscounty()
    g = groupby(c, :STFIP; sort = true)
    # a state's name from the geocoder's table of lowercase names ("district of columbia" -> "District of Columbia")
    nm = Dict(v => join([w == "of" ? w : uppercasefirst(w) for w in split(k)], " ") for (k, v) in _state_names)
    # the same aggregation the geocoder's STATE tier makes: the population-weighted mean of the county centers
    S = combine(g,
        :ST => first => :ST,
        [:LON, :POP] => ((lon, pop) -> sum(lon .* pop) / sum(pop)) => :LON,
        [:LAT, :POP] => ((lat, pop) -> sum(lat .* pop) / sum(pop)) => :LAT,
        :POP => sum => :POP,
        :ALAND => sum => :ALAND,
        :AWATER => sum => :AWATER)
    S.NAME = String[nm[st] for st in S.ST]
    S.ISCUS = Bool[lon >= CUS_LIMITS[1][1] && lon <= CUS_LIMITS[1][2] &&
                   lat >= CUS_LIMITS[2][1] && lat <= CUS_LIMITS[2][2] for (lon, lat) in zip(S.LON, S.LAT)]
    return select(S, :STFIP, :ST, :NAME, :LON, :LAT, :POP, :ALAND, :AWATER, :ISCUS)
end

"""
    usstate() -> DataFrame

Returns DataFrame containing U.S. state-level data, one row for each state and the District of Columbia,
the coarsest member of the census ladder (`usstate`, `uscounty`, `uszcta3`, `uszcta5`, `usplace`,
`uscentract`, `uscenblkgrp`). Does not include U.S. territories.

The table is aggregated from [`uscounty`](@ref) (no new data file), so it is consistent with the ladder: the
populations sum to the county total, the land and water areas are the sums of the counties', and the center of
population is the population-weighted mean of the county centers, as the `STATE` tier of [`loc2lonlat`](@ref) takes
it (and, because a county's center is the population-weighted mean of its block groups', the same point
`uscenblkgrp()` gives). The table is built once per session and each call returns a copy, so it may be changed freely.

# Columns
- `STFIP`: Integer representing state FIPS (Federal Information Processing Standards) code.
- `ST`: Symbol representing state abbreviation (e.g., :AL for Alabama).
- `NAME`: String containing name of state.
- `LON`: Float representing longitude of state center of population.
- `LAT`: Float representing latitude of state center of population.
- `POP`: Integer representing population of state.
- `ALAND`: Float representing land area of state in square miles.
- `AWATER`: Float representing water area of state in square miles.
- `ISCUS`: Boolean indicating whether the state's center of population is within continental U.S. (true or false);
  false for Alaska and Hawaii.

# Sources
Aggregated from `uscounty()`; see its sources. `ISCUS` determined from `LAT` and `LON`.

# Example
Lecture 2.5's ladder of data sources starts at places and its coarsest national source is the 3-digit ZIP areas;
a state table is coarser still, 51 rows:

```jldoctest
df = usstate()
(size(df, 1), sum(df.POP) == sum(uscounty().POP), names(df))

# output

(51, true, ["STFIP", "ST", "NAME", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS"])
```
"""
function usstate()
    t = lock(_usstate_lock) do
        isnothing(_usstate_cache[]) && (_usstate_cache[] = _build_usstate())
        _usstate_cache[]
    end
    return copy(t)
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
- `LON`: Float representing longitude of census tract center of population.
- `LAT`: Float representing latitude of census tract center of population.
- `POP`: Integer representing population of census tract.
- `ALAND`: Float representing land area of census tract in square miles.
- `AWATER`: Float representing water area of census tract in square miles.
- `ISCUS`: Boolean indicating whether census tract is within continental U.S. (true or false).

# Sources
Area data from [1]. Population and center of population data from [2].

1. U.S. Census Bureau, 2020 Gazetteer Files, [2020_Gaz_tract_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_tract_national.zip)

2. U.S. Census Bureau, Centers of Population, [CenPop2020_Mean_TR.txt](https://www2.census.gov/geo/docs/reference/cenpop2020/tract/CenPop2020_Mean_TR.txt)

# Example
```julia
df = uscentract()
names(df)   # => ["STFIP", "COFIP", "TRFIP", "ST", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS"]
filter(r -> r.ST == :NC, df)    # => 2655 census tracts in North Carolina (ST is a Symbol)
```
"""
function uscentract()
    return loaddata("uscentract")
end

"""
    uscenblkgrp() -> DataFrame

Returns DataFrame containing U.S. census block group-level data.

Geographic and population data for each U.S. census block group, including latitude-longitude coordinates representing the center of population of the block group.  Does not include U.S. territories.

Unlike the other census loaders, block groups carry no `NAME` or `ST` column: block groups have no common name, and are identified solely by their numeric FIPS codes. Recover the state from `STFIP` via [`fips2st`](@ref) if needed.

# Columns
- `STFIP`: Integer representing state FIPS (Federal Information Processing Standards) code.
- `COFIP`: Integer representing county FIPS code.
- `TRFIP`: Integer representing census tract FIPS code.
- `BGFIP`: Integer representing census block group FIPS code.
- `LON`: Float representing longitude of block group center of population.
- `LAT`: Float representing latitude of block group center of population.
- `POP`: Integer representing population of block group.
- `ALAND`: Float representing land area of block group in square miles.
- `AWATER`: Float representing water area of block group in square miles.
- `ISCUS`: Boolean indicating whether block group is within continental U.S. (true or false).

# Sources
Area data from [1]. Population and center of population data from [2]. `ISCUS` determined from `LAT` and `LON`.

1. U.S. Census Bureau, TIGER/Line Shapefiles for 2020 Census Block Groups, [https://www2.census.gov/geo/tiger/TIGER2020/BG/]

2. U.S. Census Bureau, Centers of Population, [CenPop2020_Mean_BG.txt](https://www2.census.gov/geo/docs/reference/cenpop2020/blockgroup/CenPop2020_Mean_BG.txt)

# Example
```julia
df = uscenblkgrp()
names(df)   # => ["STFIP", "COFIP", "TRFIP", "BGFIP", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS"]  (no NAME/ST)
nrow(df)                        # number of block groups
first(df, 5)                    # LON precedes LAT
```
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
- `LON`: Float representing an interior longitude of ZCTA5.
- `LAT`: Float representing an interior latitude of ZCTA5.
- `POP`: Integer representing population of ZCTA5.
- `ALAND`: Float representing land area of ZCTA5 in square miles.
- `AWATER`: Float representing water area of ZCTA5 in square miles.
- `ISCUS`: Boolean indicating whether ZCTA5 is within continental U.S. (true or false).

# Sources
Geographic data derived from [1]. Population data derived from [2]. `ISCUS` determined from `LAT` and `LON`.

1. U.S. Census Bureau, 2023 Gazetteer Files, [2023_Gaz_zcta_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2023_Gazetteer/2023_Gaz_zcta_national.zip)

2. U.S. Census Bureau, 2020 Census Demographic and Housing Characteristics File (DHC), [DECENNIALDHC2020.P1](https://data.census.gov/table?t=Populations%20and%20People&g=010XX00US\$8600000)

# Example
```julia
df = uszcta5()
names(df)     # => ["ZCTA5", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS"]
first(df, 5)  # LON precedes LAT
```
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
- `LON`: Float representing longitude of ZCTA3 approximate center of population.
- `LAT`: Float representing latitude of ZCTA3 approximate center of population.
- `POP`: Integer representing population of ZCTA3.
- `ALAND`: Float representing land area of ZCTA3 in square miles.
- `AWATER`: Float representing water area of ZCTA3 in square miles.
- `ISCUS`: Boolean indicating whether ZCTA3 is within continental U.S. (true or false).

# Sources
All data derived from `uszcta5`.

# Example
```julia
df = uszcta3()
names(df)     # => ["ZCTA3", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS"]
first(df, 5)  # LON precedes LAT
```
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
- `LON`: Float representing longitude of CBSA center of population.
- `LAT`: Float representing latitude of CBSA center of population.
- `POP`: Integer representing population of CBSA.
- `ALAND`: Float representing land area of CBSA in square miles.
- `AWATER`: Float representing water area of CBSA in square miles.
- `IS_MSA`: Boolean indicating whether CBSA is a Metropolitan Statistical Area (`true`) or a Micropolitan Statistical Area (`false`).
- `CSA`: Integer or None representing Combined Statistical Area code if CBSA is part of a CSA.
- `ISCUS`: Boolean indicating whether CBSA is within continental U.S. (true or false).

# Sources
CBSA delineations and classifications from [1]. Geographic and population data from `uscounty()`.

1. U.S. Census Bureau, Core based statistical areas (CBSAs), metropolitan divisions, and combined statistical areas (CSAs), [list1_2023.xls](https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list1_2023.xlsx)

# Example
```julia
df = uscbsa()
names(df)   # => ["CBSA", "NAME", "LON", "LAT", "POP", "ALAND", "AWATER", "IS_MSA", "CSA", "ISCUS"]
filter(r -> r.IS_MSA, df)       # => 382 of 918 are Metropolitan Statistical Areas (IS_MSA::Bool)
```
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
- `LON`: Float representing longitude of CSA center of population.
- `LAT`: Float representing latitude of CSA center of population.
- `POP`: Integer representing population of CSA.
- `ALAND`: Float representing land area of CSA in square miles.
- `AWATER`: Float representing water area of CSA in square miles.
- `ISCUS`: Boolean indicating whether CSA is within continental U.S. (true or false).

# Sources
CSA delineations and classifications from [1]. Geographic and population data from `uscbsa()`. `ISCUS` determined from `LAT` and `LON`.

1. U.S. Census Bureau, 2023 Combined Statistical Area (CSA) Codes, [list2_2023.xls](https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2020/delineation-files/list2_2023.xls)

# Example
```julia
df = uscsa()
names(df)     # => ["CSA", "NAME", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS"]
first(df, 5)  # LON precedes LAT; NAME::String
```
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
st2fips(:NC)

# output

37
```

Broadcasts over a collection: `st2fips.([:NC, :NY])` returns `[37, 36]`.
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
fips2st(37)

# output

:NC
```

Broadcasts over a range: `fips2st.(37:39)` returns `[:NC, :ND, :OH]`.
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

Loads and returns data from a CSV file. FAF5 files (names starting with `faf5_`)
are resolved via `LazyArtifacts` and downloaded on first use; all other files are
loaded from the bundled `data/` directory.

- `fn`: Filename without extension (e.g., `"faf5_nodes"`, `"usplace"`).
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
        @error "Failed to load CSV data" exception=(e, catch_backtrace())
        throw(e)
    end
end

# The FAF5 tables are read from their CSV files once per session (the first call of each takes 1 to 3 seconds, and
# every later call took as long again) and kept here; each call returns a copy, so a caller may change what it gets
# (add a column, filter in place) without changing what the next call gets. The lock is for tasks that call at once.
const _faf5nodes_cache = Ref{Union{Nothing, DataFrame}}(nothing)
const _faf5links_cache = Ref{Union{Nothing, DataFrame}}(nothing)
const _faf5_lock = ReentrantLock()

function _faf5cached(cache::Ref{Union{Nothing, DataFrame}}, name::String)
    return lock(_faf5_lock) do
        isnothing(cache[]) && (cache[] = loadcsvdata(name))
        cache[]
    end
end

_faf5copy(cache::Ref{Union{Nothing, DataFrame}}, name::String) = copy(_faf5cached(cache, name))

# The two tables themselves, not copies, for a caller that only reads them (makemap's network layer, S22): it must not
# change them.
_faf5tables() = (_faf5cached(_faf5nodes_cache, "faf5_nodes"), _faf5cached(_faf5links_cache, "faf5_links"))

"""
    faf5nodes() -> DataFrame

Returns DataFrame containing FAF5 road network nodes.

Physical road network nodes from the Freight Analysis Framework version 5 (FAF5).
Centroid nodes (artificial FAF zone connectors) are excluded. The file is read once per session and each
call returns a copy, so the table may be changed freely.

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

# Example
```julia
df = faf5nodes()
names(df)     # => ["IDX", "LON", "LAT", "ENTRY_EXIT", "EXIT_NUM", "INTERCHANGE", "FACILITY_TYPE", "FACILITY_NAME", "STATEID", "FAFID"]
first(df, 5)  # IDX, LON, LAT, ...
```
"""
function faf5nodes()
    return _faf5copy(_faf5nodes_cache, "faf5_nodes")
end

"""
    faf5links() -> DataFrame

Returns DataFrame containing FAF5 road network links.

Physical road network links from the Freight Analysis Framework version 5 (FAF5).
Links connecting to centroid nodes are excluded. The file is read once per session and each
call returns a copy, so the table may be changed freely.

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

# Example
```julia
df = faf5links()
names(df)     # => ["SRC", "DST", "DIST", "STFIP", "COFIP", "SPEED", "NHS", "SIGN", "NAME", "FCLASS", "URBAN", "AB_SPEED", "BA_SPEED", "AB_TIME", "BA_TIME", "AB_LANES", "BA_LANES", "DIR", "STRAHNET", "NHFN", "TOLL_TYPE", "TOLL_LINK", "BORDER_LINK", "FAFZONE", "STATUS"]
first(df, 5)  # SRC, DST, DIST, ...
```
"""
function faf5links()
    return _faf5copy(_faf5links_cache, "faf5_links")
end

# =============================================================================
# Helper Functions (H1–H4)
# =============================================================================

# The decimal places of `prt`'s `fracdig` and `allfrac`: one integer, or one entry for each column.
const _DigitSpec = Union{Integer, AbstractVector{<:Integer}, NamedTuple, AbstractDict}

"""
    prt(X; rows, cols, title, fracdig, allfrac, row_title, str)

Pretty-print a matrix, vector, or DataFrame with smart formatting.

Formatted display with right-aligned columns. Each column is formatted from its own values,
by the per-column digit rule of MATLOG's `mdisp`: integer columns show 0 decimal places, mixed
columns show `fracdig` decimal places (trailing zeros kept, so money keeps its cents), and a
column of fractions, all values below 1 in magnitude, shows at most `allfrac` decimal places:
the digits that are zero in every value of the column are dropped ("Ignore all 0 digits in
column of fractions", `mdisp.m`), so `0.45` and `0.449` print as `0.450` and `0.449`, and `0.5`
and `0.25` as `0.50` and `0.25`. Exactly: the column prints with the smallest `k` from 1 to
`allfrac` for which `abs(v) * 10.0^k` equals an integer in floating point for every finite
value `v` of the column, and with `allfrac` places when there is no such `k`. A `NaN` or `missing`
in the column leaves it at `allfrac` places, as in `mdisp`, and an `Inf` takes no part. Whole
parts of 1,000 or more get comma separators, and
a value of any magnitude prints its own digits (never scientific notation). `NaN` and `missing`
display as blank, `Inf` and `-Inf` as `Inf` and `-Inf`, a `Bool` as `true` or `false`, and any
other non-numeric value (a `String`, a `Symbol`) as its text. The `row_title` keyword places a
header in the upper-left corner of the table (the row-label column header).

# Decimal places per column
`fracdig` and `allfrac` are one integer for every column, or a specification for each:
- a vector with one entry per column, for the matrix and vector methods (a vector has one column);
- a `NamedTuple` or a `Dict` keyed by column name, for a DataFrame; a column it does not name
  keeps the default (2 and 4), and a name that is no column is an `ArgumentError`.

A column named in a `fracdig` specification shows that many places at most, whatever its values:
for a column of fractions too, unless `allfrac` names it as well, so `fracdig = (rmse = 5,)`
gives a column of small values five places. `allfrac` names only the columns of fractions.

# Matrix method
    prt(X::AbstractMatrix; rows=1:size(X,1), cols=1:size(X,2), title="", fracdig=2, allfrac=4, row_title="", str=false)

# Vector method
    prt(v::AbstractVector; rows=1:length(v), title="", fracdig=2, allfrac=4, row_title="", str=false)

# DataFrame method
    prt(df::AbstractDataFrame; rows=nothing, title="", fracdig=2, allfrac=4, row_title="", str=false)

A DataFrame column is text when its element type (ignoring `missing`) is a `String`, a `Symbol`,
a `Char` or any other non-numeric type, and numeric otherwise (`Bool` columns are numeric columns
that print `true` and `false`). A frame with only numeric columns prints with row numbers `1:nrow(df)`
as row labels, as a matrix does; a frame with any text column prints without row labels. `rows`
overrides either default.

With `str=true`, returns the formatted table as a string (separator lines stripped)
instead of printing. Default behavior prints to stdout and returns `nothing`.

# Examples
```jldoctest
prt([1000 0.1234; 2000 0.5678])

# output

       1       2
────────────────
1  1,000  0.1234
2  2,000  0.5678
```

```jldoctest
prt([1 2; 3 4]; rows=["a", "b"], cols=["X", "Y"], row_title="ID")

# output

ID  X  Y
────────
 a  1  2
 b  3  4
```

```jldoctest
using DataFrames
prt(DataFrame(site = ["a", "b"], cost = [1234.5, missing], open = [true, false]))

# output

  site      cost   open
───────────────────────
     a  1,234.50   true
     b            false
```

A column of fractions shows only the places its values have. These are the utilizations of
Lecture 2.7's Code block 18, each rounded to three places in the call:

```jldoctest
using DataFrames
prt(DataFrame(ZIP = [270, 272, 283], util = [0.857, 0.753, 0.691]))

# output

   ZIP   util
─────────────
1  270  0.857
2  272  0.753
3  283  0.691
```

A specification for each column names the places a column shows. This is Lecture 2.5's Code
block 13, whose `rmse` column of fractions needs five places to show its fifth digit (without the
specification it prints `0.0019`):

```jldoctest
using DataFrames
prt(DataFrame(linear = 0.0224, quadratic = 0.449, rmse = 0.00188); fracdig = (rmse = 5,))

# output

   linear  quadratic     rmse
─────────────────────────────
1  0.0224      0.449  0.00188
```
"""
function prt(X::AbstractMatrix; rows=1:size(X, 1), cols=1:size(X, 2),
             title::AbstractString="", fracdig::_DigitSpec=2, allfrac::_DigitSpec=4,
             row_title::AbstractString="", str::Bool=false)
    m, n = size(X)
    if m == 0 || n == 0
        str && return ""
        println("Empty matrix")
        return nothing
    end
    return _prt_table([view(X, :, j) for j in 1:n], string.(cols), string.(rows),
                      title, row_title, fracdig, allfrac, str)
end

function prt(v::AbstractVector; rows=1:length(v), title::AbstractString="",
             fracdig::_DigitSpec=2, allfrac::_DigitSpec=4,
             row_title::AbstractString="", str::Bool=false)
    prt(reshape(v, :, 1); rows=rows, cols=[""], title=title, fracdig=fracdig, allfrac=allfrac,
        row_title=row_title, str=str)
end

function prt(df::AbstractDataFrame; rows=nothing, title::AbstractString="",
             fracdig::_DigitSpec=2, allfrac::_DigitSpec=4,
             row_title::AbstractString="", str::Bool=false)
    nms = names(df)
    columns = [df[!, c] for c in nms]
    istext = [_istextcol(eltype(c)) for c in columns]
    allnumeric = !isempty(columns) && !any(istext)
    if allnumeric && nrow(df) == 0
        str && return ""
        println("Empty matrix")
        return nothing
    end
    # an all-numeric frame is numbered like a matrix; a frame with text columns is not
    rowlabels = rows === nothing ? (allnumeric ? string.(1:nrow(df)) : String[]) : string.(rows)
    return _prt_table(columns, string.(nms), rowlabels, title, row_title, fracdig, allfrac, str;
                      textcols = istext)
end

# Internal: the one pass behind every `prt` method. `columns` are the data columns; each is formatted
# from its own values (a text column as its text), then the table is laid out and printed or returned.
function _prt_table(columns, col_labels::Vector{String}, row_labels::Vector{String},
                    title::AbstractString, row_title::AbstractString,
                    fracdig::_DigitSpec, allfrac::_DigitSpec, str::Bool;
                    textcols = falses(length(columns)))
    n = length(columns)
    m = n == 0 ? 0 : length(columns[1])
    cells = Matrix{String}(undef, m, n)
    fd, fdnamed = _digitspec(fracdig, col_labels, 2, "fracdig")
    af, afnamed = _digitspec(allfrac, col_labels, 4, "allfrac")
    for j in 1:n
        # a column of fractions takes its `allfrac`; where `fracdig` names the column and `allfrac`
        # does not, the digits asked for in `fracdig` stand for it as well
        afj = afnamed[j] ? af[j] : fdnamed[j] ? fd[j] : af[j]
        nd = textcols[j] ? 0 : _coldigits(columns[j], fd[j], afj)
        for i in 1:m
            cells[i, j] = _fmtcell(columns[j][i], nd)
        end
    end
    if str
        buf = IOBuffer()
        io = IOContext(buf, :displaysize => (typemax(Int), typemax(Int)))
        _print_table(io, cells; column_labels=col_labels, row_labels=row_labels,
                     title=String(title), stubhead_label=String(row_title))
        raw = String(take!(buf))
        lines = split(raw, '\n')
        filtered = [l for l in lines if !isempty(l) && !all(c -> c == '─', l)]
        return join(filtered, '\n') * '\n'
    else
        io = IOContext(stdout, :displaysize => (typemax(Int), typemax(Int)))
        _print_table(io, cells; column_labels=col_labels, row_labels=row_labels,
                     title=String(title), stubhead_label=String(row_title))
        return nothing
    end
end

# Internal: a DataFrame column is text when its element type, ignoring `missing`, is not numeric
# (`Any` is left to the per-value rule, as a numeric-looking column).
function _istextcol(T::Type)
    S = nonmissingtype(T)
    return !(S <: Real) && S !== Any
end

# Internal: does a value take part in digit detection and numeric formatting? (`Bool` does not.)
_isnumcell(v) = v isa Real && !(v isa Bool)

# Internal: decimal places of a column, from the finite real values it holds, by Matlog's `mdisp`: none
# when they are all integers; `fracdig` when some value is 1 or more in magnitude; and for a column of
# fractions (all below 1) the smallest k from 1 to `allfrac` at which every value times 10^k is an
# integer in floating point ("Ignore all 0 digits in column of fractions"), `allfrac` when there is none.
# As in `mdisp`, a NaN (here also `missing`) in the column makes that test fail: `Xj == round(Xj)` is false
# for it, so the column keeps `allfrac` places; an Inf passes the test and takes no part.
function _coldigits(col, fracdig::Integer, allfrac::Integer)
    nreal = 0
    allint = true
    alllt1 = true
    blank = false
    for v in col
        if ismissing(v) || (_isnumcell(v) && isnan(v))
            blank = true
            continue
        end
        _isnumcell(v) && isfinite(v) || continue
        nreal += 1
        allint &= v == round(v)
        alllt1 &= abs(v) < 1
    end
    nreal == 0 && return Int(fracdig)
    allint && return 0
    alllt1 || return Int(fracdig)
    blank && return Int(allfrac)
    for k in 1:Int(allfrac)
        p = 10.0^k
        all(v -> (x = abs(v) * p; x == round(x)), (v for v in col if _isnumcell(v) && isfinite(v))) && return k
    end
    return Int(allfrac)
end

# Internal: the decimal places of each column from a `fracdig` or `allfrac` argument, and which columns it
# names. An integer is every column's and names none; a vector has one entry for each of the columns; a
# NamedTuple or Dict names some columns (by `Symbol` or `String`) and leaves the rest at `default`.
function _digitspec(spec, labels::Vector{String}, default::Integer, what::AbstractString)
    n = length(labels)
    if spec isa Integer
        return fill(Int(spec), n), falses(n)
    elseif spec isa AbstractVector
        length(spec) == n || throw(ArgumentError(
            "prt: `$what` has $(length(spec)) entries for $n columns; pass one integer, or one per column."))
        return Int.(spec), trues(n)
    end
    vals = fill(Int(default), n)
    named = falses(n)
    for (k, d) in pairs(spec)
        j = findfirst(==(String(k)), labels)
        j === nothing && throw(ArgumentError(
            "prt: `$what` names \"$k\", which is not a column (the columns are $(join(repr.(labels), ", ")))."))
        vals[j] = Int(d)
        named[j] = true
    end
    return vals, named
end

# Internal: one table cell. `nd` is the column's decimal places.
function _fmtcell(v, nd::Int)
    v isa Bool && return v ? "true" : "false"
    if v isa Real
        isnan(v) && return ""
        isinf(v) && return string(v)
        return _formatfixed(v, nd)
    end
    ismissing(v) && return ""
    return string(v)
end

# Internal: lightweight table printer replacing PrettyTables. `cells` holds the formatted text.
function _print_table(io::IO, cells::AbstractMatrix{String};
                      column_labels::Vector{String}=String[],
                      row_labels::Vector{String}=String[],
                      title::String="",
                      stubhead_label::String="")
    m, n = size(cells)

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

# Internal: insert `sep` between groups of three digits of a string of digits
function _groupdigits(s::AbstractString, sep::AbstractString)
    n = length(s)
    n <= 3 && return String(s)
    head = n % 3 == 0 ? 3 : n % 3
    io = IOBuffer()
    write(io, SubString(s, 1, head))
    i = head + 1
    while i <= n
        write(io, sep, SubString(s, i, i + 2))
        i += 3
    end
    return String(take!(io))
end

# Internal: comma-separate an integer of any size
function _commasep(n::Integer; sep::AbstractString=",")
    s = string(n)
    neg = startswith(s, "-")
    return (neg ? "-" : "") * _groupdigits(neg ? SubString(s, 2) : s, sep)
end

# Internal: format a real with `ndig` decimal places (trailing zeros kept) and `sep` between the groups
# of three digits of the whole part. The one formatting core of `prt` and `thousands`. No value is
# converted to a fixed-width integer, so the value's own digits print at any magnitude; the fraction is
# digits, never `string(float)`, so no scientific notation can appear; the value is rounded first so a
# carry (1.996 at 2 places) reaches the whole part; and a value that rounds to zero prints unsigned.
function _formatfixed(v::Real, ndig::Integer; sep::AbstractString=",")
    nd = max(Int(ndig), 0)
    if v isa Integer
        return _commasep(v; sep=sep) * (nd == 0 ? "" : "." * "0"^nd)
    end
    x = v isa AbstractFloat ? v : float(v)
    isfinite(x) || return string(x)
    # `round(x, digits)` is trusted while x * 10^nd stays well inside the 53-bit significand (2^50); past
    # that it would round a product that is itself inexact, so the digits are taken from x exactly instead
    trusted = nd == 0 || abs(x) * 10.0^nd < 2.0^50
    r = nd == 0 ? round(x) : trusted ? round(x, digits=nd) : x
    neg = r < 0
    a = abs(r)
    w = floor(a)
    whole = a < 2.0^62 ? Int64(w) : BigInt(w)
    fracstr = ""
    if nd > 0
        f = a - w
        if trusted && nd <= 15
            k = round(Int64, f * 10.0^nd)
            lim = Int64(10)^nd
        else
            k = round(BigInt, BigFloat(f) * big(10)^nd)
            lim = big(10)^nd
        end
        if k >= lim                                   # a carry out of the fraction
            k -= lim
            whole += 1
        end
        fracstr = "." * lpad(string(k), nd, '0')
    end
    return (neg ? "-" : "") * _groupdigits(string(whole), sep) * fracstr
end

"""
    thousands(x::Real; digits = 0, sep = ",") -> String

Format a number with thousands separators and a fixed number of decimal places.

`x` is rounded to `digits` decimal places (as `round(x; digits)` rounds) and printed with exactly
`digits` of them, trailing zeros kept. The whole part has `sep` between each group of three digits
and the decimal places have none. A negative amount has a leading `-`; an amount that rounds to zero
prints without one. A rounding carry reaches the whole part (`999.996` at 2 places is `"1,000.00"`),
and an integer or a float of any magnitude prints its own digits, never scientific notation. `NaN`
and `Inf` print as `"NaN"` and `"Inf"`.

This is the formatter `prt` uses for the numbers in its tables. It returns a `String` of the number
only: a currency symbol is written beside the call, in the text around it.

# Keywords
- `digits = 0`: decimal places. `0` gives a whole number (`commafmt(round(Int, x))` in Lecture 1.1,
  the `usd` helpers of Lectures 2.4 and 2.7, `com` of Lecture 2.5); `1` and `2` replace
  `commas(round(x, digits = 1))` (Lectures 4.1 to 6.3) and `usd(x)` (Lectures 3.2 to 3.4, 4.4).
- `sep = ","`: the group separator. `"{,}"` is Lecture 1.1's `mnum`, the thousands comma for math
  mode.

# Examples
The three values the course formats by hand: Lecture 1.1's `commafmt` comment, `300000000 -> "300,000,000"`;
Lecture 3.2's `usd`, whose comment is `1357 -> "1,357"` (here with its two decimals); and the one-decimal negative
of the form `commas(round(x, digits = 1))` that Lectures 4.1 to 6.3 print.

```jldoctest
thousands(300000000)
# output

"300,000,000"
```

```jldoctest
thousands(1357.2; digits = 2)

# output

"1,357.20"
```

```jldoctest
thousands(-64580.949; digits = 1)

# output

"-64,580.9"
```

```jldoctest
thousands(1234567; sep = "{,}")

# output

"1{,}234{,}567"
```
"""
function thousands(x::Real; digits::Integer=0, sep::AbstractString=",")
    digits >= 0 || throw(ArgumentError("digits must be nonnegative, got $digits"))
    return _formatfixed(x, digits; sep=sep)
end

"""
    snapvals(x; atol=1e-8) -> Array

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
- `atol`: Tolerance for snapping (default: `1e-8`).

# Example
```jldoctest
snapvals([2.9999999997, 1e-12, 0.5])

# output

3-element Vector{Float64}:
 3.0
 0.0
 0.5
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


# =============================================================================
# Relocated Functions (from MapTools — pure computation, no plotting dependency)
# =============================================================================

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
Each hub's segments are `[hub, spoke, NaN, hub, spoke, NaN, …]`; an unused hub yields an
empty vector.

```jldoctest
W = [1.0 0.0; 0.0 1.0]          # hub 1 serves spoke 1; hub 2 serves spoke 2
hubs = [0.0 0.0; 1.0 1.0]
spokes = [0.5 0.5; 2.0 2.0]
X, Y = alloclines(W, hubs, spokes)
X

# output

2-element Vector{Vector{Float64}}:
 [0.0, 0.5, NaN]
 [1.0, 2.0, NaN]
```

In practice `W` comes from an allocation solver, e.g. `_, _, W = ufl(k, C; verbose=false)`.
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