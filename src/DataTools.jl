"""
    DataTools

The `DataTools` module provides a set of functions and tools for working with U.S. geographical and statistical data.

# Exported Functions:
- `usplace`: Returns a DataFrame containing U.S. place data.
- `uscounty`: Returns a DataFrame containing U.S. county data.
- `uscentract`: Returns a DataFrame containing U.S. Census Tract data.
- `uscenblkgrp`: Returns a DataFrame containing U.S. Census Block Group data.
- `uszcta3`: Returns a DataFrame containing U.S. ZIP Code Tabulation Area (3-digit) data.
- `uszcta5`: Returns a DataFrame containing U.S. ZIP Code Tabulation Area (5-digit) data.
- `uscsa`: Returns a DataFrame containing U.S. Combined Statistical Area (CSA) data.
- `uscbsa`: Returns a DataFrame containing U.S. Core-Based Statistical Area (CBSA) data.
- `st2fips`: Converts state abbreviations to FIPS codes.

Usage:
```julia-repl
    using DataFrames
    df = usplace()
```
"""
module DataTools

# Import for data deserialization
using Serialization

# Exported functions
export usplace, uscounty, uscentract, uscenblkgrp, uszcta5, uszcta3
export uscbsa, uscsa, st2fips

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
- `ST`: String representing state abbreviation (e.g., AL for Alabama).
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
- `ST`: String representing state abbreviation (e.g., AL for Alabama).
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
- `ST`: String representing state abbreviation (e.g., AL for Alabama).
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
```julia-repl
julia> st2fips(:NC)
37

julia> st2fips.([:NC, :NY])
2-element Vector{Int64}:
37
36
```
"""
function st2fips(state::Symbol)
    try
        if state in keys(state_fips)
            return state_fips[state]
        else
            error_message = "Error: '$state' is not a valid US state or territory symbol."
            throw(ArgumentError(error_message))
        end
    catch e
        return throw(e)
    end
end

end # module DataTools