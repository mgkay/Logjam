# DataTools - Functions for working with U.S. geographical and statistical data: the census and FAF5 tables
# and the FIPS codes. Split in v0.3.1 (A10): display is displaytools.jl, geometry geomtools.jl.

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

# The census tables, each read from its file once per session and kept here (A10). `_table(name)` is the table itself,
# for Logjam's own lookups, which only read it (the geocoder's place, ZIP code, county and state tiers); every public
# loader returns a copy of it, so a caller may change what it gets (add a column, filter in place) without changing
# what the next call gets. The lock is for tasks that call at once.
const _TABLES = Dict{String, DataFrame}()
const _TABLES_LOCK = ReentrantLock()

_table(name::AbstractString) = lock(() -> get!(() -> loaddata(name), _TABLES, name), _TABLES_LOCK)

"""
    usplace() -> DataFrame

Returns DataFrame containing U.S. place data.

Geographic and population data for each place in the U.S., where each place is a city, town, or census-designated place (CDP). The latitude-longitude of each place represents a central location interior to the place and not its center of population.  Does not include U.S. territories. The file is read once per session and each call returns a copy, so the table may be changed freely.

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
    return copy(_table("usplace"))
end

"""
    uscounty() -> DataFrame

Returns DataFrame containing U.S. county-level data.

Geographic and population data for each U.S. county, including latitude-longitude coordinates representing the center of population of the county. Does not include U.S. territories. The file is read once per session and each call returns a copy, so the table may be changed freely.

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
    return copy(_table("uscounty"))
end

# The state table is aggregated from `uscounty()` once per session and kept here; each call returns a copy.
const _usstate_cache = Ref{Union{Nothing, DataFrame}}(nothing)
const _usstate_lock = ReentrantLock()

function _build_usstate()
    c = _table("uscounty")
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

Geographic and population data for each U.S. census tract, including latitude-longitude coordinates representing the center of population of the tract. Does not include U.S. territories. The file is read once per session and each call returns a copy, so the table may be changed freely.

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
    return copy(_table("uscentract"))
end

"""
    uscenblkgrp() -> DataFrame

Returns DataFrame containing U.S. census block group-level data.

Geographic and population data for each U.S. census block group, including latitude-longitude coordinates representing the center of population of the block group.  Does not include U.S. territories. The file is read once per session and each call returns a copy, so the table may be changed freely.

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
    return copy(_table("uscenblkgrp"))
end

"""
    uszcta5() -> DataFrame

Returns DataFrame containing U.S. 5-digit ZIP Code Tabulation Area (ZCTA5) data.

Geographic and population data for each U.S. 5-digit ZIP Code Tabulation Area (ZCTA5). The latitude-longitude of each ZCTA5 represents a central location within the ZCTA5 and not its center of population. The table covers the 50 states and the District of Columbia and, of the territories, only the 40 Puerto Rico ZCTA5s whose codes begin with 009 (`ZCTA5` 901 to 987), each with `ISCUS = false`; Puerto Rico's other ZCTA5s (006xx and 007xx) are not included (X6; until v0.3.1 this said that no territory was included). The file is read once per session and each call returns a copy, so the table may be changed freely.

# Columns
- `ZCTA5`: Integer (<= 5 digits) representing the ZIP Code Tabulation Area (ZCTA5) code.
- `LON`: Float representing an interior longitude of ZCTA5.
- `LAT`: Float representing an interior latitude of ZCTA5.
- `POP`: Integer representing population of ZCTA5.
- `ALAND`: Float representing land area of ZCTA5 in square miles.
- `AWATER`: Float representing water area of ZCTA5 in square miles.
- `ISCUS`: Boolean indicating whether ZCTA5 is within continental U.S. (true or false).
- `STFIP`: Integer representing the state FIPS code of the state that holds the largest share of the ZCTA5's land (v0.3.1).

# State (`STFIP`)
A ZCTA5 can cross a state line: 137 of these do. `STFIP` is the state holding the largest share of the ZCTA5's land
area, the land of its parts in each county, from [3], summed by state (a county's state is the first two digits of its
GEOID). A ZCTA5 with no land would take the state holding the largest share of its water area, and a tie the smaller
FIPS code; the file has neither. Puerto Rico's 40 ZCTA5s are 72. [`fips2st`](@ref) gives the state's symbol. The column
was added in v0.3.1 as the last one, so every column before it is as it was (MakePlan D4; made by
`tools/v0_3_1/make_zcta_stfip.jl`).

# Sources
Geographic data derived from [1]. Population data derived from [2]. `ISCUS` determined from `LAT` and `LON`. `STFIP` determined from [3].

1. U.S. Census Bureau, 2023 Gazetteer Files, [2023_Gaz_zcta_national.txt](https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2023_Gazetteer/2023_Gaz_zcta_national.zip)

2. U.S. Census Bureau, 2020 Census Demographic and Housing Characteristics File (DHC), [DECENNIALDHC2020.P1](https://data.census.gov/table?t=Populations%20and%20People&g=010XX00US\$8600000)

3. U.S. Census Bureau, 2020 ZCTA to County Relationship File, [tab20_zcta520_county20_natl.txt](https://www2.census.gov/geo/docs/maps-data/data/rel2020/zcta520/tab20_zcta520_county20_natl.txt)

# Example
```julia
df = uszcta5()
names(df)     # => ["ZCTA5", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS", "STFIP"]
first(df, 5)  # LON precedes LAT
```

Three ZCTA5s and their states: 02861 lies 99.5% in Rhode Island and 0.5% in Massachusetts, 56144 87% in Minnesota and
13% in South Dakota:

```jldoctest
z = uszcta5()
[(zcta, fips2st(only(z.STFIP[z.ZCTA5 .== zcta]))) for zcta in (27601, 2861, 56144)]

# output

3-element Vector{Tuple{Int64, Symbol}}:
 (27601, :NC)
 (2861, :RI)
 (56144, :MN)
```
"""
function uszcta5()
    return copy(_table("uszcta5"))
end

"""
    uszcta3() -> DataFrame

Returns DataFrame containing U.S. 3-digit ZIP Code Tabulation Area (ZCTA3) data.

Geographic and population data for each U.S. 3-digit ZIP Code Tabulation Area (ZCTA3). The latitude-longitude of each ZCTA3 represents its approximate center of population. ZCTA3s are approximated by aggregating ZCTA5s: summing population and areas, and approximating the center of population by calculating the population-weighted centroid of the ZCTA5s' interior locations. The table covers the 50 states and the District of Columbia and, of the territories, only Puerto Rico's ZCTA3 `9` (009), aggregated from the 40 ZCTA5s of [`uszcta5`](@ref) that begin with 009, with `ISCUS = false` (X6; until v0.3.1 this said that no territory was included). The file is read once per session and each call returns a copy, so the table may be changed freely.

# Columns
- `ZCTA3`: Integer (<= 3 digits) representing the 3-digit ZIP Code Tabulation Area (ZCTA3) code.
- `LON`: Float representing longitude of ZCTA3 approximate center of population.
- `LAT`: Float representing latitude of ZCTA3 approximate center of population.
- `POP`: Integer representing population of ZCTA3.
- `ALAND`: Float representing land area of ZCTA3 in square miles.
- `AWATER`: Float representing water area of ZCTA3 in square miles.
- `ISCUS`: Boolean indicating whether ZCTA3 is within continental U.S. (true or false).
- `STFIP`: Integer representing the state FIPS code of the state that holds the most land of the ZCTA3's ZCTA5s (v0.3.1).

# State (`STFIP`)
`STFIP` is the state holding the most land summed over the ZCTA3's ZCTA5s, each ZCTA5's land counted in the state
that holds it, as for [`uszcta5`](@ref) (from the U.S. Census Bureau's 2020 ZCTA to County Relationship File); with
no land, the most water; a tie to the smaller FIPS code. 91 of the ZCTA3s have ZCTA5s in more than one state; for
each, counting every ZCTA5 wholly in its own `STFIP` gives the same state. Puerto Rico's ZCTA3 `9` is 72. The column
was added in v0.3.1 as the last one, so every column before it is as it was.

# Sources
All data derived from `uszcta5`.

# Example
```julia
df = uszcta3()
names(df)     # => ["ZCTA3", "LON", "LAT", "POP", "ALAND", "AWATER", "ISCUS", "STFIP"]
first(df, 5)  # LON precedes LAT
```
"""
function uszcta3()
    return copy(_table("uszcta3"))
end

"""
    uscbsa() -> DataFrame

Returns DataFrame containing U.S. Core-Based Statistical Area (CBSA) data.

Geographic and population data for each U.S. CBSA. The latitude-longitude of each CBSA represents its center of population. CBSA geographic and populations are determiend by aggregating its constituent counties: summing population and areas, and determining the center of population by calculating the population-weighted centroid of the county centers of population. Does not include U.S. territories. The file is read once per session and each call returns a copy, so the table may be changed freely.

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
    return copy(_table("uscbsa"))
end

"""
    uscsa() -> DataFrame

Returns DataFrame containing U.S. Combined Statistical Area (CSA) data.

Geographic and population data for each U.S. CSA. The latitude-longitude of each CSA represents its center of population. CSA geographic and populations are determined by aggregating its constituent CBSAs: summing population and areas, and determining the center of population by calculating the population-weighted centroid of the CBSA centers of population. Does not include U.S. territories. The file is read once per session and each call returns a copy, so the table may be changed freely.

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
    return copy(_table("uscsa"))
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
