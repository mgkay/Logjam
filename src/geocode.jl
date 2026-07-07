# =============================================================================
# Geocoding — loc2lonlat and lonlat2loc
# =============================================================================

# State full-name to abbreviation mapping (for preprocessing)
const _state_names = Dict(
    "alabama" => :AL, "alaska" => :AK, "arizona" => :AZ, "arkansas" => :AR,
    "california" => :CA, "colorado" => :CO, "connecticut" => :CT, "delaware" => :DE,
    "florida" => :FL, "georgia" => :GA, "hawaii" => :HI, "idaho" => :ID,
    "illinois" => :IL, "indiana" => :IN, "iowa" => :IA, "kansas" => :KS,
    "kentucky" => :KY, "louisiana" => :LA, "maine" => :ME, "maryland" => :MD,
    "massachusetts" => :MA, "michigan" => :MI, "minnesota" => :MN,
    "mississippi" => :MS, "missouri" => :MO, "montana" => :MT, "nebraska" => :NE,
    "nevada" => :NV, "new hampshire" => :NH, "new jersey" => :NJ,
    "new mexico" => :NM, "new york" => :NY, "north carolina" => :NC,
    "north dakota" => :ND, "ohio" => :OH, "oklahoma" => :OK, "oregon" => :OR,
    "pennsylvania" => :PA, "rhode island" => :RI, "south carolina" => :SC,
    "south dakota" => :SD, "tennessee" => :TN, "texas" => :TX, "utah" => :UT,
    "vermont" => :VT, "virginia" => :VA, "washington" => :WA,
    "west virginia" => :WV, "wisconsin" => :WI, "wyoming" => :WY,
    "district of columbia" => :DC
)

# Reverse: abbreviation to full name
const _state_abbrev_set = Set(values(_state_names))

# Designator suffixes to strip during name matching
const _designator_suffixes = ["cdp", "municipality", "afb", "city", "town",
                               "village", "borough", "plantation"]

"""
    _tighten(v) -> Vector

Convert `Vector{Union{T,Missing}}` to `Vector{T}` when no values are missing.
"""
_tighten(v::AbstractVector{Union{T,Missing}}) where T = any(ismissing, v) ? v : collect(T, v)
_tighten(v::AbstractVector) = v

# =============================================================================
# Name Matching Engine
# =============================================================================

"""
    _normalize_name(s) -> String

Lowercase and strip trailing geographic designators (CDP, municipality, etc.).
"""
function _normalize_name(s::AbstractString)
    n = strip(lowercase(s))
    for suffix in _designator_suffixes
        pat = " " * suffix
        if endswith(n, pat)
            n = strip(n[1:end-length(pat)])
            break
        end
    end
    return n
end

"""
    _normalize_state(st) -> Symbol

Convert state input (Symbol, String abbreviation, or full name) to Symbol.
"""
function _normalize_state(st)
    isnothing(st) && return nothing
    if st isa Symbol
        st in keys(state_fips) && return st
        # Try as lowercase full name
        s = lowercase(String(st))
        haskey(_state_names, s) && return _state_names[s]
        throw(ArgumentError("Unknown state: $st"))
    end
    s = strip(String(st))
    # Try as 2-letter abbreviation
    sym = Symbol(uppercase(s))
    sym in keys(state_fips) && return sym
    # Try as full name
    s_lower = lowercase(s)
    haskey(_state_names, s_lower) && return _state_names[s_lower]
    throw(ArgumentError("Unknown state: $st"))
end

"""
    _match_name(query, df, name_col; st=nothing, st_col=:ST) -> Int

Case-insensitive name matching with priority: exact → prefix → substring.
Returns row index. Throws if no match or ambiguous match.
"""
function _match_name(query::AbstractString, df::DataFrame, name_col::Symbol;
                     st=nothing, st_col::Symbol=:ST)
    q = _normalize_name(query)
    isempty(q) && throw(ArgumentError("Empty query string"))

    st_sym = _normalize_state(st)

    # Build candidate pool (filtered by state if provided)
    if !isnothing(st_sym) && hasproperty(df, st_col)
        mask = [r[st_col] == st_sym for r in eachrow(df)]
    else
        mask = trues(nrow(df))
    end

    # Normalize all reference names
    ref_names = [_normalize_name(String(df[i, name_col])) for i in 1:nrow(df)]

    # Phase 1: Exact match
    exact = [i for i in 1:nrow(df) if mask[i] && ref_names[i] == q]
    length(exact) == 1 && return exact[1]
    if length(exact) > 1
        _throw_ambiguous(q, exact, df, name_col, st_col)
    end

    # Phase 2: Prefix match
    prefix = [i for i in 1:nrow(df) if mask[i] && startswith(ref_names[i], q)]
    length(prefix) == 1 && return prefix[1]
    if length(prefix) > 1
        _throw_ambiguous(q, prefix, df, name_col, st_col)
    end

    # Phase 3: Substring match
    sub = [i for i in 1:nrow(df) if mask[i] && occursin(q, ref_names[i])]
    length(sub) == 1 && return sub[1]
    if length(sub) > 1
        _throw_ambiguous(q, sub, df, name_col, st_col)
    end

    # No match
    state_msg = isnothing(st_sym) ? "" : " in state $st_sym"
    throw(ArgumentError("No match for '$query'$state_msg"))
end

function _throw_ambiguous(q, indices, df, name_col, st_col)
    n = min(length(indices), 10)
    candidates = if hasproperty(df, st_col)
        join(["$(df[i, name_col]), $(df[i, st_col])" for i in indices[1:n]], "; ")
    else
        join(["$(df[i, name_col])" for i in indices[1:n]], "; ")
    end
    extra = length(indices) > 10 ? " (and $(length(indices)-10) more)" : ""
    throw(ArgumentError(
        "Multiple matches for '$q': $candidates$extra — refine input or provide state"
    ))
end

# =============================================================================
# Address Preprocessing
# =============================================================================

"""
    _preprocess_address(street, city, state, postalcode) -> NamedTuple

Clean and normalize address components. Returns (street, city, state, postalcode, is_pobox).
"""
function _preprocess_address(street, city, state, postalcode)
    s = (ismissing(street) || street === nothing) ? "" : strip(String(street))
    c = (ismissing(city) || city === nothing) ? "" : strip(String(city))
    st = (ismissing(state) || state === nothing) ? "" : strip(String(state))
    pc = (ismissing(postalcode) || postalcode === nothing) ? "" : strip(String(postalcode))

    is_pobox = false

    # Strip secondary units from street
    if !isempty(s)
        s = replace(s, r"[,\s]*(apt|suite|ste|unit|bldg|fl|floor|rm|room|dept)\s*\.?\s*\S*$"i => "")
        s = replace(s, r"\s*#\s*\S+$" => "")
        s = strip(s)

        # Detect P.O. Box
        if occursin(r"^\s*(p\.?\s*o\.?\s*box|post\s*office\s*box)\s"i, s)
            is_pobox = true
            s = ""
        end
    end

    # Normalize state
    if !isempty(st)
        try
            st_sym = _normalize_state(st)
            st = String(st_sym)
        catch
            # Leave as-is if unrecognized
        end
    end

    # Clean whitespace
    s = replace(s, r"\s{2,}" => " ")
    c = replace(c, r"\s{2,}" => " ")

    return (street=s, city=c, state=st, postalcode=pc, is_pobox=is_pobox)
end

"""
    _parse_address_string(s) -> NamedTuple

Parse a single address string into structured components.
"""
function _parse_address_string(s::AbstractString)
    s = strip(s)
    isempty(s) && return (street="", city="", state="", postalcode="")

    street = ""
    city = ""
    state = ""
    postalcode = ""

    # Extract 5-digit postal code
    m = match(r"\b(\d{5})\b", s)
    if !isnothing(m)
        postalcode = m.captures[1]
        s = strip(replace(s, m.match => ""; count=1))
    end

    # Extract state abbreviation (2 uppercase letters at end, or after last comma)
    m = match(r",?\s*([A-Za-z]{2})\s*$", s)
    if !isnothing(m)
        candidate = uppercase(m.captures[1])
        sym = Symbol(candidate)
        if sym in keys(state_fips)
            state = candidate
            s = strip(s[1:m.offset-1])
        end
    end

    # If no state found, try full state name at end
    if isempty(state)
        s_lower = lowercase(s)
        for (name, sym) in _state_names
            if endswith(s_lower, name)
                state = String(sym)
                s = strip(s[1:end-length(name)])
                s = rstrip(s, [',', ' '])
                break
            end
        end
    end

    # Split remaining on last comma: street before, city after
    idx = findlast(',', s)
    if !isnothing(idx)
        street = strip(s[1:idx-1])
        city = strip(s[idx+1:end])
    else
        # No comma — could be just a city name or just a street
        # If it contains a number at the start, treat as street
        if occursin(r"^\d", s)
            street = s
        else
            city = s
        end
    end

    return _preprocess_address(street, city, state, postalcode)
end

# =============================================================================
# Tier Resolution
# =============================================================================

"""
    _uncertainty(aland) -> Float64

Compute distance uncertainty in miles: 0.45 * sqrt(ALAND).
"""
_uncertainty(aland) = 0.45 * sqrt(aland)

"""
    _resolve_place(name, state) -> NamedTuple or missing
"""
function _resolve_place(name::AbstractString, state)
    isempty(strip(name)) && return missing
    df = usplace()
    try
        idx = _match_name(name, df, :NAME; st=state, st_col=:ST)
        return (lon=df[idx, :LON], lat=df[idx, :LAT],
                aland=df[idx, :ALAND], source="PLACE")
    catch
        return missing
    end
end

"""
    _resolve_postalcode(code) -> NamedTuple or missing
"""
function _resolve_postalcode(code::AbstractString)
    pc = strip(code)
    # Must be 5-digit numeric
    occursin(r"^\d{5}$", pc) || return missing
    df = uszcta5()
    idx = findfirst(==(pc), string.(df.ZCTA5))
    isnothing(idx) && return missing
    return (lon=df[idx, :LON], lat=df[idx, :LAT],
            aland=df[idx, :ALAND], source="POSTALCODE")
end

"""
    _resolve_county(name, state) -> NamedTuple or missing
"""
function _resolve_county(name::AbstractString, state)
    isempty(strip(name)) && return missing
    df = uscounty()
    try
        idx = _match_name(name, df, :NAME; st=state, st_col=:ST)
        return (lon=df[idx, :LON], lat=df[idx, :LAT],
                aland=df[idx, :ALAND], source="COUNTY")
    catch
        return missing
    end
end

"""
    _resolve_state(name) -> NamedTuple or missing
"""
function _resolve_state(name)
    isnothing(name) && return missing
    st_sym = try
        _normalize_state(name)
    catch
        return missing
    end
    df = uscounty()
    mask = df.ST .== st_sym
    !any(mask) && return missing
    sub = df[mask, :]
    total_pop = sum(sub.POP)
    total_pop == 0 && return missing
    wlon = sum(sub.LON .* sub.POP) / total_pop
    wlat = sum(sub.LAT .* sub.POP) / total_pop
    total_aland = sum(sub.ALAND)
    return (lon=wlon, lat=wlat, aland=total_aland, source="STATE")
end

# =============================================================================
# Geocode Cache I/O
# =============================================================================

_cache_path(cache_dir) = joinpath(cache_dir, "geocode_cache.csv")

function _load_cache(cache_dir)
    path = _cache_path(cache_dir)
    cache = Dict{String,NamedTuple{(:lon,:lat,:source,:uncert),Tuple{Float64,Float64,String,Float64}}}()
    isfile(path) || return cache
    df = CSV.read(path, DataFrame)
    for r in eachrow(df)
        cache[r.KEY] = (lon=r.LON, lat=r.LAT, source=r.SOURCE, uncert=r.UNCERT)
    end
    return cache
end

function _save_cache(cache_dir, cache::Dict)
    path = _cache_path(cache_dir)
    keys_vec = collect(keys(cache))
    df = DataFrame(
        KEY = keys_vec,
        LON = [cache[k].lon for k in keys_vec],
        LAT = [cache[k].lat for k in keys_vec],
        SOURCE = [cache[k].source for k in keys_vec],
        UNCERT = [cache[k].uncert for k in keys_vec]
    )
    mkpath(cache_dir)
    CSV.write(path, df)
end

function _cache_key(street, city, state, postalcode)
    return lowercase(join([street, city, state, postalcode], "|"))
end

# =============================================================================
# loc2lonlat — Forward Geocoding
# =============================================================================

"""
    _is_postalcode(s) -> Bool

Check if string looks like a 5-digit US postal code.
"""
_is_postalcode(s::AbstractString) = occursin(r"^\d{5}$", strip(s))

"""
    _resolve_row(street, city, state, postalcode, county, country, cache, force_download) -> NamedTuple

Resolve a single row through the tier hierarchy. Returns (lon, lat, source, uncert, status).
"""
function _resolve_row(street, city, state, postalcode, county, country, cache, force_download)
    addr = _preprocess_address(street, city, state, postalcode)
    st_sym = isempty(addr.state) ? nothing : _normalize_state(addr.state)

    # Check cache for address-tier queries
    if !isempty(addr.street) && !addr.is_pobox
        key = _cache_key(addr.street, addr.city, addr.state, addr.postalcode)
        if !force_download && haskey(cache, key)
            c = cache[key]
            return (LON=c.lon, LAT=c.lat, source=c.source, uncert=c.uncert, status="OK")
        end
    end

    # Tier 1: Full address via Nominatim (if street present and not P.O. Box)
    if !isempty(addr.street) && !addr.is_pobox
        if _nominatim_available[]
            try
                result = _nominatim_geocode[](addr.street, addr.city, addr.state,
                                               addr.postalcode; country=country)
                if !ismissing(result)
                    key = _cache_key(addr.street, addr.city, addr.state, addr.postalcode)
                    entry = (lon=result.lon, lat=result.lat, source="ADDRESS", uncert=0.0)
                    cache[key] = entry
                    return (LON=result.lon, LAT=result.lat, source="ADDRESS",
                            uncert=0.0, status="OK")
                end
            catch e
                if e isa Base.IOError || (hasproperty(e, :msg) && occursin("network", lowercase(string(e))))
                    rethrow(e)
                end
                # Nominatim returned nothing — fall through to lower tiers
            end
        else
            @warn "Nominatim extension not loaded. Install HTTP and JSON3 for address geocoding. Falling back to city/postalcode lookup."
        end
    end

    # Tier 2: City/place + state
    if !isempty(addr.city) && !isnothing(st_sym)
        result = _resolve_place(addr.city, st_sym)
        if !ismissing(result)
            status = isempty(addr.street) || addr.is_pobox ? "OK" : "PARTIAL"
            return (LON=result.lon, LAT=result.lat, source=result.source,
                    uncert=_uncertainty(result.aland), status=status)
        end
    end

    # Tier 3: Postal code
    pc = addr.postalcode
    if !isempty(pc)
        result = _resolve_postalcode(pc)
        if !ismissing(result)
            status = isempty(addr.street) ? "OK" : "PARTIAL"
            return (LON=result.lon, LAT=result.lat, source=result.source,
                    uncert=_uncertainty(result.aland), status=status)
        end
    end

    # Tier 4: County + state
    county_str = ismissing(county) ? "" : strip(String(county))
    if !isempty(county_str) && !isnothing(st_sym)
        result = _resolve_county(county_str, st_sym)
        if !ismissing(result)
            return (LON=result.lon, LAT=result.lat, source=result.source,
                    uncert=_uncertainty(result.aland), status="PARTIAL")
        end
    end

    # Tier 5: State only
    if !isnothing(st_sym)
        result = _resolve_state(st_sym)
        if !ismissing(result)
            return (LON=result.lon, LAT=result.lat, source=result.source,
                    uncert=_uncertainty(result.aland), status="PARTIAL")
        end
    end

    # Tier 2b: City without state (if not already tried)
    if !isempty(addr.city) && isnothing(st_sym)
        result = _resolve_place(addr.city, nothing)
        if !ismissing(result)
            return (LON=result.lon, LAT=result.lat, source=result.source,
                    uncert=_uncertainty(result.aland), status="OK")
        end
    end

    return (LON=missing, LAT=missing, source="", uncert=missing, status="FAIL")
end

"""
    loc2lonlat(s::AbstractString; state=nothing, country=:US,
               cache_dir=".", force_download=false)

Geocode a single location string. Accepts addresses, city names, postal codes.

Returns a named tuple `(LON, LAT, source, uncert, status)`. Geographic fields
are UPPERCASE (`LON`, `LAT`); metadata fields are lowercase.

# Examples
```julia
loc2lonlat("Raleigh", state=:NC)   # => (LON, LAT, source="PLACE", uncert, status="OK")
loc2lonlat("27601")                # => (LON, LAT, source="POSTALCODE", uncert, status="OK")
loc2lonlat("123 Main St, Raleigh, NC 27601")  # ADDRESS tier via Nominatim (needs HTTP+JSON3;
                                              # falls back to PLACE/POSTALCODE offline)
```
"""
function loc2lonlat(s::AbstractString; state=nothing, country::Symbol=:US,
                    cache_dir::AbstractString=".", force_download::Bool=false)
    s = strip(s)
    isempty(s) && return (LON=missing, LAT=missing, source="", uncert=missing, status="FAIL")

    cache = _load_cache(cache_dir)

    # Detect postal code
    if _is_postalcode(s)
        result = _resolve_postalcode(s)
        if !ismissing(result)
            return (LON=result.lon, LAT=result.lat, source=result.source,
                    uncert=_uncertainty(result.aland), status="OK")
        end
        return (LON=missing, LAT=missing, source="", uncert=missing, status="FAIL")
    end

    # Detect if it looks like an address (has commas or numbers)
    if occursin(r"[,\d]", s)
        parsed = _parse_address_string(s)
        st = !isempty(parsed.state) ? parsed.state : state
        result = _resolve_row(parsed.street, parsed.city, st,
                              parsed.postalcode, missing, country, cache, force_download)
        _save_cache(cache_dir, cache)
        return result
    end

    # Plain name — place lookup
    st_sym = _normalize_state(state)
    result = _resolve_place(s, st_sym)
    if !ismissing(result)
        return (LON=result.lon, LAT=result.lat, source=result.source,
                uncert=_uncertainty(result.aland), status="OK")
    end

    return (LON=missing, LAT=missing, source="", uncert=missing, status="FAIL")
end

"""
    loc2lonlat(v::Vector{<:AbstractString}; state=nothing, country=:US,
               cache_dir=".", force_download=false)

Geocode a vector of location strings. Auto-detects postal codes vs place names.

Returns a DataFrame with LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS columns.

# Examples
```julia
loc2lonlat(["Raleigh", "Durham", "Chapel Hill"], state=:NC)
# => DataFrame with columns INPUT, LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS
loc2lonlat(["27601", "27708", "27514"])
```
"""
function loc2lonlat(v::Vector{<:AbstractString}; state=nothing, country::Symbol=:US,
                    cache_dir::AbstractString=".", force_download::Bool=false)
    n = length(v)
    lons = Vector{Union{Float64,Missing}}(missing, n)
    lats = Vector{Union{Float64,Missing}}(missing, n)
    sources = Vector{String}(undef, n)
    uncerts = Vector{Union{Float64,Missing}}(missing, n)
    statuses = Vector{String}(undef, n)

    cache = _load_cache(cache_dir)
    cache_dirty = false

    for i in 1:n
        if i % 50 == 0
            @info "Geocoding progress: $i / $n"
        end
        r = loc2lonlat(v[i]; state=state, country=country,
                       cache_dir=cache_dir, force_download=force_download)
        lons[i] = r.LON
        lats[i] = r.LAT
        sources[i] = r.source
        uncerts[i] = r.uncert
        statuses[i] = r.status
    end

    return DataFrame(
        INPUT = v,
        LON = _tighten(lons),
        LAT = _tighten(lats),
        GC_SOURCE = sources,
        GC_UNCERT = _tighten(uncerts),
        GC_STATUS = statuses
    )
end

"""
    loc2lonlat(df::DataFrame; street=:STREET, city=:CITY, state=:STATE,
               postalcode=:POSTALCODE, county=:COUNTY, country=:US,
               cache_dir=".", force_download=false)

Geocode a DataFrame of addresses. Inspects which columns exist to determine
resolution tier per row.

Returns the input DataFrame with LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS appended.

# Examples
```julia
df = DataFrame(CITY=["Raleigh", "Durham"], STATE=[:NC, :NC])
loc2lonlat(df)   # => input df with LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS appended

df2 = DataFrame(addr=["123 Main St"], town=["Raleigh"], st=["NC"])
loc2lonlat(df2; street=:addr, city=:town, state=:st)
```
"""
function loc2lonlat(df::DataFrame; street::Symbol=:STREET, city::Symbol=:CITY,
                    state::Symbol=:STATE, postalcode::Symbol=:POSTALCODE,
                    county::Symbol=:COUNTY, country::Symbol=:US,
                    cache_dir::AbstractString=".", force_download::Bool=false)
    n = nrow(df)
    lons = Vector{Union{Float64,Missing}}(missing, n)
    lats = Vector{Union{Float64,Missing}}(missing, n)
    sources = fill("", n)
    uncerts = Vector{Union{Float64,Missing}}(missing, n)
    statuses = fill("", n)

    has_street = hasproperty(df, street)
    has_city = hasproperty(df, city)
    has_state = hasproperty(df, state)
    has_pc = hasproperty(df, postalcode)
    has_county = hasproperty(df, county)

    cache = _load_cache(cache_dir)

    for i in 1:n
        if i % 50 == 0
            @info "Geocoding progress: $i / $n"
        end

        s = has_street ? df[i, street] : missing
        c = has_city ? df[i, city] : missing
        st = has_state ? df[i, state] : missing
        pc = has_pc ? df[i, postalcode] : missing
        co = has_county ? df[i, county] : missing

        r = _resolve_row(s, c, st, pc, co, country, cache, force_download)

        lons[i] = r.LON
        lats[i] = r.LAT
        sources[i] = r.source
        uncerts[i] = r.uncert
        statuses[i] = r.status
    end

    _save_cache(cache_dir, cache)

    result = copy(df)
    result.LON = _tighten(lons)
    result.LAT = _tighten(lats)
    result.GC_SOURCE = sources
    result.GC_UNCERT = _tighten(uncerts)
    result.GC_STATUS = statuses
    return result
end

# =============================================================================
# lonlat2loc — Reverse Geocoding
# =============================================================================

"""
    _in_radius(aland) -> Float64

Compute "in" radius in miles: sqrt(ALAND / π).
"""
_in_radius(aland) = sqrt(aland / π)

"""
    lonlat2loc(lon::Real, lat::Real, df::DataFrame; threshold=nothing)

Find nearest place to a (lon, lat) coordinate pair (reverse geocoding).

Returns a named tuple with fields: NAME, ST, dist, bearing, dir, desc.
Geographic fields are UPPERCASE (`NAME`, `ST`; `ST isa Symbol`); metadata lowercase.

# Example
```julia
cities = usplace()
lonlat2loc(-78.6382, 35.7796, cities)
# => (NAME="Raleigh", ST=:NC, dist, bearing, dir, desc="in Raleigh, NC")
```
"""
function lonlat2loc(lon::Real, lat::Real, df::DataFrame; threshold=nothing)
    return lonlat2loc([lon, lat], df; threshold=threshold)
end

"""
    lonlat2loc(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, df::DataFrame; threshold=nothing)

Find nearest places to coordinate vectors (reverse geocoding).

Returns DataFrame with columns: idx, NAME, ST, dist, bearing, dir, desc (`ST isa Symbol`).

# Example
```julia
cities = usplace()
lonlat2loc([-78.6382, -80.8431], [35.7796, 35.2271], cities)
# => DataFrame with columns idx, NAME, ST, dist, bearing, dir, desc
```
"""
function lonlat2loc(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, df::DataFrame; threshold=nothing)
    length(x) == length(y) || throw(ArgumentError("x and y must have the same length"))
    return lonlat2loc(hcat(x, y), df; threshold=threshold)
end

"""
    lonlat2loc(xy::AbstractVector, df::DataFrame; threshold=nothing)

Find nearest place to a [LON, LAT] coordinate (reverse geocoding).

Uses area-based "in" radius by default: if within √(ALAND/π) of centroid,
reported as "in City"; otherwise "X mi DIR of City".

Returns a named tuple with fields: NAME, ST, dist, bearing, dir, desc.
Geographic fields are UPPERCASE (`NAME`, `ST`; `ST isa Symbol`); metadata lowercase.

# Example
```julia
cities = usplace()
lonlat2loc([-78.6382, 35.7796], cities)
# => (NAME="Raleigh", ST=:NC, dist, bearing, dir, desc="in Raleigh, NC")
```
"""
function lonlat2loc(xy::AbstractVector, df::DataFrame; threshold=nothing)
    length(xy) == 2 || throw(ArgumentError("xy must have length 2 [LON, LAT]"))
    XY = reshape(xy, 1, 2)
    result = lonlat2loc(XY, df; threshold=threshold)
    return (NAME=result.NAME[1], ST=result.ST[1], dist=result.dist[1],
            bearing=result.bearing[1], dir=result.dir[1], desc=result.desc[1])
end

"""
    lonlat2loc(XY::AbstractMatrix, df::DataFrame; threshold=nothing)

Find nearest places to n×2 matrix of [LON LAT] coordinates.

Returns DataFrame with columns: idx, NAME, ST, dist, bearing, dir, desc (`ST isa Symbol`).
"""
function lonlat2loc(XY::AbstractMatrix, df::DataFrame; threshold=nothing)
    size(XY, 2) == 2 || throw(ArgumentError("XY must have 2 columns [LON, LAT]"))

    city_coords = hcat(df.LON, df.LAT)
    D = dists(XY, city_coords, :mi)

    has_aland = hasproperty(df, :ALAND)
    dir_labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    results = DataFrame(
        idx = Int[], NAME = String[], ST = Symbol[],
        dist = Float64[], bearing = Float64[],
        dir = String[], desc = String[]
    )

    for i in 1:size(D, 1)
        j = argmin(D[i, :])
        dist = D[i, j]
        st = df.ST[j]           # keep as Symbol (matches usplace().ST)
        name = String(df.NAME[j])

        # Bearing from nearest city to query point
        lon1, lat1 = deg2rad(df.LON[j]), deg2rad(df.LAT[j])
        lon2, lat2 = deg2rad(XY[i, 1]), deg2rad(XY[i, 2])
        bearing = mod(
            atan(cos(lat2) * sin(lon2 - lon1),
                 cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1)),
            2π
        )

        bearing_deg = rad2deg(bearing)
        dir_idx = (Int(floor((bearing_deg + 22.5) / 45.0)) % 8) + 1
        dir = dir_labels[dir_idx]

        # Determine "in" threshold
        thr = if isnothing(threshold)
            has_aland ? _in_radius(df.ALAND[j]) : 4.0
        else
            Float64(threshold)
        end

        desc = if dist < thr
            "in $name, $st"
        else
            "$(round(dist, digits=1)) mi $dir of $name, $st"
        end

        push!(results, (idx=j, NAME=name, ST=st, dist=dist,
                        bearing=bearing, dir=dir, desc=desc))
    end

    return results
end

"""
    lonlat2loc(df_in::DataFrame, df_ref::DataFrame;
               lon_col=:LON, lat_col=:LAT, threshold=nothing)

Reverse geocode coordinates from a DataFrame.

Returns the input DataFrame with location description columns appended.
"""
function lonlat2loc(df_in::DataFrame, df_ref::DataFrame;
                    lon_col::Symbol=:LON, lat_col::Symbol=:LAT,
                    threshold=nothing)
    hasproperty(df_in, lon_col) || throw(ArgumentError("Column $lon_col not found"))
    hasproperty(df_in, lat_col) || throw(ArgumentError("Column $lat_col not found"))

    XY = hcat(df_in[!, lon_col], df_in[!, lat_col])
    loc_df = lonlat2loc(XY, df_ref; threshold=threshold)

    result = copy(df_in)
    result.GC_NAME = loc_df.NAME
    result.GC_ST = loc_df.ST         # Symbol, matches usplace().ST
    result.GC_DIST = loc_df.dist
    result.GC_DIR = loc_df.dir
    result.GC_DESC = loc_df.desc
    return result
end
