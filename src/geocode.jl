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
    _normalize_zip(x) -> String

A ZIP code as the five-character string the geocoder works in (N7, N8), or `""` for none:
an integer (what CSV.jl reads a ZIP column as) is zero-padded to five digits, so `2139` is
`"02139"`; a whole-valued float is treated as an integer; a string of one to four digits is
padded the same way (a ZIP column that lost its zeros), and `"27601-1234"` keeps its first five
digits. Only the geocoder's own handling: the census tables keep their integer `ZCTA5` (S36).
"""
function _normalize_zip(x)
    (x === nothing || ismissing(x)) && return ""
    if x isa Integer
        return x < 0 ? string(x) : lpad(string(x), 5, '0')
    elseif x isa AbstractFloat
        isfinite(x) || return ""
        return (isinteger(x) && x >= 0) ? lpad(string(Int(x)), 5, '0') : string(x)
    end
    z = strip(String(x))
    m = match(r"^(\d{5})-\d{4}$", z)
    m === nothing || return String(m.captures[1])
    occursin(r"^\d{1,4}$", z) && return lpad(z, 5, '0')
    return String(z)
end

"""
    _preprocess_address(street, city, state, postalcode) -> NamedTuple

Clean and normalize address components. Returns (street, city, state, postalcode, is_pobox).
"""
function _preprocess_address(street, city, state, postalcode)
    s = (ismissing(street) || street === nothing) ? "" : strip(String(street))
    c = (ismissing(city) || city === nothing) ? "" : strip(String(city))
    st = (ismissing(state) || state === nothing) ? "" : strip(String(state))
    pc = _normalize_zip(postalcode)

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

# The grammar of an address string (N1). Everything is read from the END of the string, as a whole
# token, because that is where a US address puts it:
#
#   address := [ street "," ] [ city ] [ [","] state ] [ [","] zip ]
#   zip     := 5 digits [ "-" 4 digits ]            the LAST token, never the first digit run
#   state   := a spelled-out name (longest first)   "West Virginia" before "Virginia"
#            | a two-letter code                    a whole word, in the state table
#   street/city := what is left: with a comma, everything before the last comma is the street
#                  and what follows it the city; without one, a text that begins with a digit is
#                  a street and any other is a city.
#
# Whole words only: v0.2.8 read the last two LETTERS of the text as a state code, so
# "Atlanta, Georgia" parsed as Iowa ("ia") and every spelled-out state ending in a valid code
# ("Maryland", "Texas", "Maine", ...) moved the city to another state; and it took the FIRST five
# digits as the ZIP, so a five-digit street number lost the whole address.
const _state_names_longest = sort!(collect(keys(_state_names)); by = length, rev = true)
const _STATE_NAME_TAIL = Regex("(?:^|[\\s,])(" * join(_state_names_longest, "|") * ")\\s*\$", "i")
const _STATE_CODE_TAIL = r"(?:^|[\s,])([A-Za-z]{2})\s*$"
const _ZIP_TAIL = r"(?:^|[\s,])(\d{5})(?:-\d{4})?\s*$"

# the text before a match that began at byte `off`, without its trailing separators
_before(s::AbstractString, off::Integer) = rstrip(SubString(s, 1, thisind(s, off - 1)), [',', ' '])

"""
    _parse_address_string(s) -> NamedTuple

Parse a single address string into structured components, by the grammar above. Returns
`(street, city, state, postalcode, is_pobox)`.
"""
function _parse_address_string(s::AbstractString)
    s = strip(replace(String(s), r"\s+" => " "))
    isempty(s) && return _preprocess_address("", "", "", "")

    street = ""
    city = ""
    state = ""
    postalcode = ""

    # ZIP: the last token, five digits with an optional +4
    m = match(_ZIP_TAIL, s)
    if !isnothing(m)
        postalcode = m.captures[1]
        s = _before(s, m.offset)
    end

    # State: a spelled-out name first (longest first), else a two-letter code. A code is a whole
    # word after a comma; after a space only when it is capitalized as a code ("NC") or a ZIP
    # follows it, so a street suffix ("Ct") is not read as Connecticut.
    m = match(_STATE_NAME_TAIL, s)
    if !isnothing(m)
        state = String(_state_names[lowercase(m.captures[1])])
        s = _before(s, m.offset)
    else
        m = match(_STATE_CODE_TAIL, s)
        if !isnothing(m) && Symbol(uppercase(m.captures[1])) in keys(state_fips)
            tok = m.captures[1]
            comma_before = endswith(rstrip(SubString(s, 1, thisind(s, m.offset - 1))), ',') ||
                           occursin(',', m.match)
            if comma_before || tok == uppercase(tok) || !isempty(postalcode)
                state = uppercase(tok)
                s = _before(s, m.offset)
            end
        end
    end

    # Street and city from what is left
    s = String(s)
    idx = findlast(',', s)
    if !isnothing(idx)
        street = strip(s[1:prevind(s, idx)])
        city = strip(s[nextind(s, idx):end])
    elseif occursin(r"^\d", s)
        street = s
    else
        city = s
    end

    return _preprocess_address(street, city, state, postalcode)
end

# The state an address resolves in when the text and the caller's `state` keyword both name one: the
# keyword is never overridden by what the parser reads out of the text (N1); a disagreement is warned.
function _reconcile_state(parsed::AbstractString, given, text::AbstractString)
    g = (given === nothing || ismissing(given)) ? "" : strip(String(given))
    isempty(g) && return parsed
    isempty(parsed) && return given
    same = try
        _normalize_state(parsed) == _normalize_state(g)
    catch
        false
    end
    same || @warn "loc2lonlat: \"$text\" names the state $parsed but state = $given was passed; " *
                  "using $given."
    return given
end

# =============================================================================
# Tier Resolution
# =============================================================================

"""
    _uncertainty(aland) -> Float64

The distance uncertainty of a place, ZIP, county or state centroid, in miles: the mean distance
from the centroid to a random point of a disk of area `ALAND` (mi²), `(2/3)·√(ALAND/π)`, the
constant `dgca` floors its distances at (R2/S3). v0.2.8 returned `0.45·√ALAND`, which had no stated
basis and is 1.2 times larger.
"""
_uncertainty(aland) = _mean_zone_distance(aland)

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
    # the table's ZCTA5 is an integer (S36), so "02139" is 2139 (N7)
    idx = eltype(df.ZCTA5) <: Integer ? findfirst(==(parse(Int, pc)), df.ZCTA5) :
                                         findfirst(==(pc), string.(df.ZCTA5))
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

# The cache holds address-tier (Nominatim) results only: an exact ADDRESS, a STREET match (the street
# found, the house number not), and a remembered failure (NOTFOUND, stored as NaN), so that a query
# Nominatim could not answer is not sent again (CR 26). It lives in memory for one call
# and persists to a CSV file only when the caller names one (`cache = "path.csv"`); with
# the default `cache = nothing` no file is read or written. Entries found during a call
# are appended to the file once, when the call ends, and only if there are any, so a
# call that adds nothing never touches the file (finding N14).

const _GeocodeEntry = NamedTuple{(:lon, :lat, :source, :uncert),
                                 Tuple{Float64, Float64, String, Float64}}

struct _GeocodeCache
    path::Union{Nothing, String}              # CSV file, or nothing for in-memory only
    entries::Dict{String, _GeocodeEntry}
    added::Vector{String}                     # keys added this call, in order
end

# Resolve the `cache` keyword and the deprecated `cache_dir` keyword to a file path.
function _cache_file(cache, cache_dir)
    if cache_dir !== nothing
        cache === nothing || throw(ArgumentError(
            "loc2lonlat: pass `cache` or the deprecated `cache_dir`, not both."))
        Base.depwarn("loc2lonlat: `cache_dir = dir` is deprecated; use " *
                     "`cache = joinpath(dir, \"geocode_cache.csv\")`.", :loc2lonlat)
        return joinpath(String(cache_dir), "geocode_cache.csv")
    end
    cache === nothing && return nothing
    path = String(cache)
    isdir(path) && throw(ArgumentError(
        "loc2lonlat: `cache` names a file, not a directory; got the directory \"$path\". " *
        "Use, e.g., `cache = joinpath(\"$path\", \"geocode_cache.csv\")`."))
    return path
end

function _load_cache(path::Union{Nothing, AbstractString})
    entries = Dict{String, _GeocodeEntry}()
    if path !== nothing && isfile(path) && filesize(path) > 0
        df = CSV.read(path, DataFrame; types = Dict(:KEY => String, :SOURCE => String))
        num(x) = ismissing(x) ? NaN : Float64(x)      # a failed lookup (NOTFOUND) is stored as NaN
        for r in eachrow(df)                  # a later row for the same key wins
            entries[r.KEY] = (lon = num(r.LON), lat = num(r.LAT), source = r.SOURCE, uncert = num(r.UNCERT))
        end
    end
    return _GeocodeCache(path === nothing ? nothing : String(path), entries, String[])
end

function _store!(gc::_GeocodeCache, key::AbstractString, entry::_GeocodeEntry)
    gc.entries[key] = entry
    push!(gc.added, key)
    return gc
end

# Append this call's new entries to the cache file. Writes nothing when there is no file
# or nothing was added; writes the header only when the file is new or empty.
function _flush!(gc::_GeocodeCache)
    (gc.path === nothing || isempty(gc.added)) && return gc
    ks = gc.added
    df = DataFrame(
        KEY = ks,
        LON = [gc.entries[k].lon for k in ks],
        LAT = [gc.entries[k].lat for k in ks],
        SOURCE = [gc.entries[k].source for k in ks],
        UNCERT = [gc.entries[k].uncert for k in ks]
    )
    dir = dirname(gc.path)
    isempty(dir) || mkpath(dir)
    exists = isfile(gc.path) && filesize(gc.path) > 0
    CSV.write(gc.path, df; append = exists)
    empty!(gc.added)
    return gc
end

function _cache_key(street, city, state, postalcode)
    return lowercase(join([street, city, state, postalcode], "|"))
end

# =============================================================================
# loc2lonlat — Forward Geocoding
# =============================================================================

# One row of a batch: a state that is not a state aborted the whole call (CR 26); now that row is
# FAIL, with a warning naming it, and the rest are geocoded. A network error still stops the call.
function _batch_row(f, i::Integer, what)
    try
        return f()
    catch e
        e isa ArgumentError && startswith(e.msg, "Unknown state") || rethrow()
        @warn "loc2lonlat: row $i (\"$what\"): $(e.msg); no location returned (status FAIL)."
        return (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL")
    end
end

"""
    _is_postalcode(s) -> Bool

Check if string looks like a 5-digit US postal code.
"""
_is_postalcode(s::AbstractString) = occursin(r"^\d{5}$", strip(s))

"""
    _resolve_row(street, city, state, postalcode, county, gc, force_download) -> NamedTuple

Resolve a single row through the tier hierarchy. Returns (lon, lat, source, uncert, status).
`gc` is the call's `_GeocodeCache`; an address-tier result is stored in it with `_store!`.
"""
function _resolve_row(street, city, state, postalcode, county,
                      gc::_GeocodeCache, force_download)
    addr = _preprocess_address(street, city, state, postalcode)
    st_sym = isempty(addr.state) ? nothing : _normalize_state(addr.state)

    # Tier 1: Full address via Nominatim (if street present and not P.O. Box). `note` says why
    # the address tier did not answer, so that a lower tier's answer is reported as a fallback
    # naming the input and the tier (CR 26), never returned silently.
    note = nothing
    if !isempty(addr.street) && !addr.is_pobox
        key = _cache_key(addr.street, addr.city, addr.state, addr.postalcode)
        cached = !force_download && haskey(gc.entries, key) ? gc.entries[key] : nothing
        if cached !== nothing && cached.source != _NOTFOUND
            return _row_from_entry(cached)
        elseif cached !== nothing                    # a failed lookup, remembered
            note = "an earlier query found no match for it (remembered in the cache)"
        elseif _nominatim_available[]
            try
                result = _nominatim_geocode[](addr.street, addr.city, addr.state,
                                               addr.postalcode; country=:US)
                if !ismissing(result)
                    entry = _entry_from_result(result, addr.street)
                    _store!(gc, key, entry)
                    return _row_from_entry(entry)
                end
                _store!(gc, key, _notfound_entry)    # not found: never sent twice (Nominatim policy)
                note = "Nominatim found no match for it"
            catch e
                if e isa Base.IOError || (hasproperty(e, :msg) && occursin("network", lowercase(string(e))))
                    rethrow(e)
                end
                note = "the Nominatim query failed ($(nameof(typeof(e))))"   # not a definite "no match": not cached
            end
        else
            note = "the Nominatim extension is not loaded (install HTTP and JSON3 for address geocoding)"
        end
    end

    # Tier 2: City/place + state
    if !isempty(addr.city) && !isnothing(st_sym)
        result = _resolve_place(addr.city, st_sym)
        if !ismissing(result)
            status = isempty(addr.street) || addr.is_pobox ? "OK" : "PARTIAL"
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS=status))
        end
    end

    # Tier 3: Postal code
    pc = addr.postalcode
    if !isempty(pc)
        result = _resolve_postalcode(pc)
        if !ismissing(result)
            status = isempty(addr.street) ? "OK" : "PARTIAL"
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS=status))
        end
    end

    # Tier 4: County + state
    county_str = ismissing(county) ? "" : strip(String(county))
    if !isempty(county_str) && !isnothing(st_sym)
        result = _resolve_county(county_str, st_sym)
        if !ismissing(result)
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS="PARTIAL"))
        end
    end

    # Tier 5: State only
    if !isnothing(st_sym)
        result = _resolve_state(st_sym)
        if !ismissing(result)
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS="PARTIAL"))
        end
    end

    # Tier 2b: City without state (if not already tried)
    if !isempty(addr.city) && isnothing(st_sym)
        result = _resolve_place(addr.city, nothing)
        if !ismissing(result)
            return _fallback(note, addr, (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                    GC_UNCERT=_uncertainty(result.aland), GC_STATUS="OK"))
        end
    end

    return _fallback(note, addr, (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL"))
end

# The source name of a cached failed lookup, and its entry (no position, no uncertainty).
const _NOTFOUND = "NOTFOUND"
const _notfound_entry = (lon = NaN, lat = NaN, source = _NOTFOUND, uncert = NaN)

# True when Nominatim's match carries the house number the caller typed (CR 26: a match on the street
# alone must not be reported as the address). The extension passes the match's `house_number`; where
# it is absent (an older extension, a stand-in) the typed number must appear as a whole comma-separated
# part of `display_name`, and with neither field there is nothing to check against. A street typed
# without a leading number (a landmark) claims none.
function _house_number_matched(result, street::AbstractString)
    m = match(r"^\s*(\d+[A-Za-z]?)\b", street)
    m === nothing && return true
    if hasproperty(result, :house_number)
        return !isempty(strip(string(result.house_number)))
    end
    hasproperty(result, :display_name) || return true
    dn = strip(string(result.display_name))
    isempty(dn) && return true
    return lowercase(m.captures[1]) in [lowercase(strip(t)) for t in split(dn, ',')]
end

# A Nominatim match as a cache entry: an exact address (ADDRESS, uncertainty 0), or, when the house
# number was not found, the street alone (STREET, uncertainty unknown).
function _entry_from_result(result, street::AbstractString)
    lon, lat = Float64(result.lon), Float64(result.lat)
    return _house_number_matched(result, street) ?
        (lon = lon, lat = lat, source = "ADDRESS", uncert = 0.0) :
        (lon = lon, lat = lat, source = "STREET", uncert = NaN)
end

# A cache entry as a row: an exact ADDRESS is OK, a STREET match is PARTIAL and has no uncertainty.
_row_from_entry(c) = (LON = c.lon, LAT = c.lat, GC_SOURCE = c.source,
                      GC_UNCERT = isnan(c.uncert) ? missing : c.uncert,
                      GC_STATUS = c.source == "ADDRESS" ? "OK" : "PARTIAL")

# A row from a lower tier after the address tier did not answer: warn, naming the input, why and
# the tier used (CR 26), then return the row unchanged.
function _fallback(note, addr, row)
    note === nothing && return row
    text = join(filter(!isempty, [addr.street, addr.city, strip(addr.state * " " * addr.postalcode)]), ", ")
    tier = Dict("PLACE" => "city", "POSTALCODE" => "ZIP code", "COUNTY" => "county",
                "STATE" => "state")
    if row.GC_STATUS == "FAIL"
        @warn "loc2lonlat: \"$text\": $note, and no lower tier found a location (status FAIL)."
    else
        @warn "loc2lonlat: \"$text\": $note; located at its $(get(tier, row.GC_SOURCE, row.GC_SOURCE)) " *
              "($(row.GC_SOURCE)), not its street (status $(row.GC_STATUS))."
    end
    return row
end

"""
    loc2lonlat(s::AbstractString; state=nothing, cache=nothing, force_download=false)

Geocode a single location string. Accepts addresses, city names, postal codes.

Returns a named tuple `(LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS)`: the same field names as
the columns the vector and DataFrame methods return (R7/S14). At v0.2.8 the scalar method's
metadata fields were lowercase `source`, `uncert` and `status`; `LON` and `LAT` never changed.
The names used below, `source`, `uncert` and `status`, are these fields without the `GC_`
prefix.

# Address strings
A string with a comma or a digit is read as an address, from the end: an optional five-digit
ZIP (or ZIP+4), then an optional state (a spelled-out name or a two-letter code, as a whole
word), then the city and street, split at the last comma. `"10420 Falls of Neuse Rd, Raleigh,
NC 27614"` is street `10420 Falls of Neuse Rd`, city Raleigh, state NC, ZIP 27614;
`"Atlanta, Georgia"` is Atlanta, GA. A `state` keyword is never overridden by what the text
says: where the two disagree the keyword is used, with a warning.

# Plain names and postal codes
A string with no comma and no digit is read as a city, and a five-digit string as a postal code, and
each enters the same tier ladder as an address string (GC), so a name that is not found falls back to
its state: `loc2lonlat("Raliegh"; state = :NC)` answers at the `STATE` tier with status `PARTIAL`, as
`loc2lonlat("Raliegh, NC")` does (Lecture 4.2's Code block 1 geocodes that one). With no `state`, a
name or ZIP that is not found is `FAIL`, and so is a name that matches several places.

# Source and status
`source` is the tier that answered: `ADDRESS` (Nominatim, house number found, `uncert = 0`),
`STREET` (Nominatim found the street but not the house number, status `PARTIAL`, `uncert`
missing: no house number is invented), `PLACE`, `POSTALCODE`, `COUNTY` or `STATE` (the census
tables). `status` is `OK` for an exact answer at the tier the input asked for, `PARTIAL` for
a coarser one, `FAIL` for none. When an address with a street is answered by a lower tier, a
warning names the input, why the address tier did not answer (not found, not loaded, or a
failed query) and the tier used, so a city centroid is never returned silently. In a vector
or DataFrame call a state that is not a state makes that row `FAIL` (with a warning) instead of
stopping the call.

# Uncertainty, and the three ways an area becomes a distance (N25)
`uncert` is in miles. An exact address has `0`. A place, ZIP, county or state centroid has
`(2/3)·√(a/π)` for its land area `a` in mi² (R2/S3): the mean distance from the centroid to a
uniformly random point of a disk of that area (radius `r = √(a/π)`, mean distance `2r/3`), the
same constant that floors [`dgca`](@ref). Two other conversions in the package differ on purpose:
[`lonlat2loc`](@ref) calls a point "in" a place within the full radius `√(a/π)` of its centroid
(the boundary of the equal-area disk, not the mean distance to it), and the `STATE` tier is the
plain population-weighted mean of the county centroids' longitudes and latitudes, not
[`wcentroid`](@ref)'s cosine-latitude weighting, with `a` the sum of the counties' land areas.
v0.2.8's `uncert` was `0.45·√a`, a constant with no stated basis, 1.2 times larger.

# Cache
Only street addresses sent to Nominatim (the `ADDRESS` and `STREET` tiers, which need
`using HTTP, JSON3`) are cached, with the queries it could not answer (stored as `NOTFOUND`,
so the same bad query is not sent twice, as Nominatim's usage policy asks); place,
postal-code, county and state lookups read the built-in tables and need no cache.
- `cache = nothing` (default): results are kept for this call only; no file is read or
  written.
- `cache = "path/to/geocode_cache.csv"`: entries already in that file are reused, and
  addresses resolved by this call are appended to it when the call ends. The file (and
  its folder) is created on the first entry; a call that adds nothing leaves it
  untouched.
- `force_download = true` queries Nominatim even for an address already in the cache
  (the new result is appended and supersedes the old one).
- `cache_dir = dir` is deprecated: it means `cache = joinpath(dir, "geocode_cache.csv")`.

# Examples
```julia
loc2lonlat("Raleigh", state=:NC)   # => (LON, LAT, GC_SOURCE="PLACE", GC_UNCERT, GC_STATUS="OK")
loc2lonlat("27601")                # => (LON, LAT, GC_SOURCE="POSTALCODE", GC_UNCERT, GC_STATUS="OK")
loc2lonlat("123 Main St, Raleigh, NC 27601")  # ADDRESS tier via Nominatim (needs HTTP+JSON3;
                                              # falls back to PLACE/POSTALCODE offline)
loc2lonlat("123 Main St, Raleigh, NC 27601"; cache = joinpath("data", "geocode_cache.csv"))
# => same result; the address is stored in data/geocode_cache.csv, so a re-run sends no query
```

A misspelled name falls back to its state, the tier Lecture 4.2's Code block 1 shows for `"Raliegh, NC"`:

```jldoctest
r = loc2lonlat("Raliegh"; state = :NC)
(r.GC_SOURCE, r.GC_STATUS)

# output

("STATE", "PARTIAL")
```
"""
function loc2lonlat(s::AbstractString; state=nothing,
                    cache::Union{Nothing,AbstractString}=nothing,
                    cache_dir::Union{Nothing,AbstractString}=nothing,
                    force_download::Bool=false)
    state isa AbstractVector && throw(ArgumentError(
        "loc2lonlat: a single location takes one `state`; pass a vector of locations to give one state each."))
    gc = _load_cache(_cache_file(cache, cache_dir))
    try
        return _loc2lonlat_one(s, state, gc, force_download)
    finally
        _flush!(gc)
    end
end

# One location string against an already-loaded cache `gc` (shared by the vector method).
function _loc2lonlat_one(s::AbstractString, state, gc::_GeocodeCache,
                         force_download::Bool)
    s = strip(s)
    isempty(s) && return (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL")

    # Detect if it looks like an address (has commas or numbers)
    if !_is_postalcode(s) && occursin(r"[,\d]", s)
        parsed = _parse_address_string(s)
        st = _reconcile_state(parsed.state, state, s)
        return _resolve_row(parsed.street, parsed.city, st,
                            parsed.postalcode, missing, gc, force_download)
    end

    # A plain string enters the same ladder as an address (GC): a five-digit string as a postal code,
    # any other as a city, so a name that is not found falls back to its state, as the comma form does
    return _is_postalcode(s) ?
        _resolve_row("", "", state, s, missing, gc, force_download) :
        _resolve_row("", s, state, "", missing, gc, force_download)
end

"""
    loc2lonlat(v::Vector{<:AbstractString}; state=nothing, cache=nothing, force_download=false)

Geocode a vector of location strings. Auto-detects postal codes vs place names.

Returns a DataFrame with LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS columns (the field names
of the single-string method's result too).

`state` is one state for every string, or a vector of states, one per string (R7/S14): the
call `loc2lonlat(City; state = St)` replaces `[loc2lonlat(c; state = s) for (c, s) in
zip(City, St)]`. An entry may be `missing` or `nothing` for no state. A vector of the wrong
length is an `ArgumentError`.

`cache` and `force_download` behave as in the single-string method: the cache file, if
one is named, is read once and the call's new address entries are appended once, at the
end (also when the call stops on an error, so entries already resolved are kept).

# Examples
```julia
loc2lonlat(["Raleigh", "Durham", "Chapel Hill"], state=:NC)
# => DataFrame with columns INPUT, LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS
loc2lonlat(["27601", "27708", "27514"])
loc2lonlat(["Raleigh", "Athens", "Asheville"]; state = [:NC, :GA, :NC])   # one state each
```
"""
function loc2lonlat(v::Vector{<:AbstractString}; state=nothing,
                    cache::Union{Nothing,AbstractString}=nothing,
                    cache_dir::Union{Nothing,AbstractString}=nothing,
                    force_download::Bool=false)
    n = length(v)
    if state isa AbstractVector && length(state) != n
        throw(ArgumentError("loc2lonlat: `state` has $(length(state)) entries for $n locations; " *
                            "pass one state or one per location."))
    end
    state_of(i) = state isa AbstractVector ? (ismissing(state[i]) ? nothing : state[i]) : state
    lons = Vector{Union{Float64,Missing}}(missing, n)
    lats = Vector{Union{Float64,Missing}}(missing, n)
    sources = Vector{String}(undef, n)
    uncerts = Vector{Union{Float64,Missing}}(missing, n)
    statuses = Vector{String}(undef, n)

    gc = _load_cache(_cache_file(cache, cache_dir))
    try
        for i in 1:n
            if i % 50 == 0
                @info "Geocoding progress: $i / $n"
            end
            r = _batch_row(i, v[i]) do
                _loc2lonlat_one(v[i], state_of(i), gc, force_download)
            end
            lons[i] = r.LON
            lats[i] = r.LAT
            sources[i] = r.GC_SOURCE
            uncerts[i] = r.GC_UNCERT
            statuses[i] = r.GC_STATUS
        end
    finally
        _flush!(gc)
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
    loc2lonlat(df::AbstractDataFrame; street=:STREET, city=:CITY, state=:STATE,
               postalcode=:POSTALCODE, county=:COUNTY,
               cache=nothing, force_download=false)

Geocode a DataFrame of addresses. Inspects which columns exist to determine
resolution tier per row. A view of a table (`view(df, rows, :)`, a `SubDataFrame`) is geocoded
as its rows are, and the result is a new `DataFrame` (v0.3.1, A8).

The `postalcode` column may be text or numeric: a ZIP read from a CSV file as an integer
(`2139`) is zero-padded to `"02139"` inside the geocoder (N7, N8). The census tables keep their
integer `ZCTA5` and `ZCTA3` codes.

Returns the input DataFrame with LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS appended.

`cache` and `force_download` behave as in the single-string method: the cache file, if
one is named, is read once and the call's new address entries are appended once, at the
end (also when the call stops on an error, so entries already resolved are kept).

# Examples
```julia
df = DataFrame(CITY=["Raleigh", "Durham"], STATE=[:NC, :NC])
loc2lonlat(df)   # => input df with LON, LAT, GC_SOURCE, GC_UNCERT, GC_STATUS appended

df2 = DataFrame(addr=["123 Main St"], town=["Raleigh"], st=["NC"])
loc2lonlat(df2; street=:addr, city=:town, state=:st)
```
"""
function loc2lonlat(df::AbstractDataFrame; street::Symbol=:STREET, city::Symbol=:CITY,
                    state::Symbol=:STATE, postalcode::Symbol=:POSTALCODE,
                    county::Symbol=:COUNTY,
                    cache::Union{Nothing,AbstractString}=nothing,
                    cache_dir::Union{Nothing,AbstractString}=nothing,
                    force_download::Bool=false)
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

    gc = _load_cache(_cache_file(cache, cache_dir))
    try
        for i in 1:n
            if i % 50 == 0
                @info "Geocoding progress: $i / $n"
            end

            s = has_street ? df[i, street] : missing
            c = has_city ? df[i, city] : missing
            st = has_state ? df[i, state] : missing
            pc = has_pc ? df[i, postalcode] : missing
            co = has_county ? df[i, county] : missing

            r = _batch_row(i, "$(s), $(c), $(st) $(pc)") do
                _resolve_row(s, c, st, pc, co, gc, force_download)
            end

            lons[i] = r.LON
            lats[i] = r.LAT
            sources[i] = r.GC_SOURCE
            uncerts[i] = r.GC_UNCERT
            statuses[i] = r.GC_STATUS
        end
    finally
        _flush!(gc)
    end

    result = copy(df)
    result.LON = _tighten(lons)
    result.LAT = _tighten(lats)
    result.GC_SOURCE = sources
    result.GC_UNCERT = _tighten(uncerts)
    result.GC_STATUS = statuses
    return result
end

# A five-digit ZIP as the string the geocoder works in, from an integer: a ZIP that lost its leading zeros (what
# CSV.jl reads a ZIP column as) is padded exactly as the DataFrame method's `postalcode` column is (`_normalize_zip`)
function _zip_string(z::Integer)
    0 <= z <= 99999 || throw(ArgumentError("loc2lonlat: $z is not a five-digit ZIP code (0 to 99999)."))
    return _normalize_zip(z)
end

"""
    loc2lonlat(zipcode::Integer; state=nothing, cache=nothing, cache_dir=nothing, force_download=false)
    loc2lonlat(zipcodes::AbstractVector{<:Integer}; state=nothing, cache=nothing, cache_dir=nothing,
               force_download=false)

Geocode ZIP codes given as integers, at the `POSTALCODE` tier: `loc2lonlat(27601)` is `loc2lonlat("27601")`
and `loc2lonlat(2139)` is `loc2lonlat("02139")`, the ZIP zero-padded to five digits as the DataFrame method
pads its `postalcode` column. The result is what the string call returns (a named tuple for one ZIP; for a
vector the DataFrame of the string-vector method, its `INPUT` column holding the padded strings), and the
keywords are the string methods'.

A ZIP column read from a file is integers (`CSV.jl` reads `02139` as `2139`), and so is a list of ZIPs such as
the four of Lecture 5.2's Code block 5 (`[27606, 32606, 48234, 27518]`): `loc2lonlat(zips)` locates them, where
`string.(zips)` would send `2139` to `"2139"`, which is not a ZIP. An integer outside 0 to 99999 is an
`ArgumentError`.

# Example
Hand [`lonlat`](@ref) the result for the matrix of coordinates the distance functions take, here for the four
zip codes of Lecture 5.2's Code block 5 (Raleigh, Gainesville, Detroit and Cary), whose centroids that lecture
reads from `uszcta5()`:

```jldoctest
zips = [27606, 32606, 48234, 27518]
size(lonlat(loc2lonlat(zips)))

# output

(4, 2)
```
"""
function loc2lonlat(zipcode::Integer; state=nothing,
                    cache::Union{Nothing,AbstractString}=nothing,
                    cache_dir::Union{Nothing,AbstractString}=nothing,
                    force_download::Bool=false)
    return loc2lonlat(_zip_string(zipcode); state, cache, cache_dir, force_download)
end

function loc2lonlat(zipcodes::AbstractVector{<:Integer}; state=nothing,
                    cache::Union{Nothing,AbstractString}=nothing,
                    cache_dir::Union{Nothing,AbstractString}=nothing,
                    force_download::Bool=false)
    return loc2lonlat(String[_zip_string(z) for z in zipcodes]; state, cache, cache_dir, force_download)
end

# =============================================================================
# lonlat — coordinates as the distance and location functions take them
# =============================================================================

"""
    lonlat(df::AbstractDataFrame) -> Matrix{Float64}
    lonlat(r::Union{DataFrameRow, NamedTuple}) -> Vector{Float64}
    lonlat(v::AbstractVector{<:NamedTuple}) -> Matrix{Float64}

The coordinates of a table, a row or a list of geocoded places, as `[lon, lat]` for one place and an `n × 2`
matrix (longitude first) for several: the form [`dists`](@ref), [`dgc`](@ref), [`ala`](@ref),
[`lonlat2loc`](@ref) and the other location functions take. It is the line the course writes at every
place it moves from a table to its distances.

- `lonlat(df)` takes the `LON` and `LAT` columns of any table: the `P = hcat(df.LON, df.LAT)` of Lecture 2.3's
  Code block 2, Lecture 5.1's Code block 27 and Lecture 2.6's `P = hcat(z.LON, z.LAT)`, and the table
  [`loc2lonlat`](@ref) returns for a vector of places.
- `lonlat(r)` takes a row of a table, or a named tuple with `LON` and `LAT` such as [`loc2lonlat`](@ref) returns
  for one place and [`wcentroid`](@ref) for a centroid: the `[w.LON, w.LAT]` Lecture 2.2 hands `optimize` and
  the `[c.LON, c.LAT]` of Lecture 4.1's `closest`.
- `lonlat(v)` takes a vector of such named tuples, one for each place: Lecture 3.4's Code block 18,
  `[getindex.(S, :LON) getindex.(S, :LAT)]` for the places `[loc2lonlat(c; state = st) for ...]` geocoded.

A place with a `missing` `LON` or `LAT`, which is what `loc2lonlat` returns for one it did not find, is an
`ArgumentError` that names the first such row, so a ZIP that was not found stops the call there where
`hcat(df.LON, df.LAT)` carries the `missing` into the distances. The result is always `Float64`.

# Example
Lecture 3.4's Code block 18 locates a supplier by `loc2lonlat` and takes its point (`[DC.LON DC.LAT]` is a row,
`lonlat(DC)` the vector the distance functions take):

```jldoctest
DC = loc2lonlat("Memphis"; state = :TN)
(lonlat(DC) == [DC.LON, DC.LAT], size(lonlat(loc2lonlat(["Raleigh", "Durham"]; state = :NC))))

# output

(true, (2, 2))
```
"""
function lonlat(df::AbstractDataFrame)
    for c in (:LON, :LAT)
        hasproperty(df, c) || throw(ArgumentError("lonlat: the table has no $c column."))
    end
    lon, lat = df.LON, df.LAT
    out = Matrix{Float64}(undef, length(lon), 2)
    for i in eachindex(lon, lat)
        _check_lonlat(lon[i], lat[i], "row $i")
        out[i, 1] = lon[i]
        out[i, 2] = lat[i]
    end
    return out
end

function lonlat(r::Union{DataFrameRow, NamedTuple})
    (hasproperty(r, :LON) && hasproperty(r, :LAT)) || throw(ArgumentError("lonlat: the row has no LON and LAT."))
    _check_lonlat(r.LON, r.LAT, "the place")
    return Float64[r.LON, r.LAT]
end

function lonlat(v::AbstractVector{<:NamedTuple})
    out = Matrix{Float64}(undef, length(v), 2)
    for (i, r) in enumerate(v)
        (hasproperty(r, :LON) && hasproperty(r, :LAT)) || throw(ArgumentError(
            "lonlat: element $i has no LON and LAT."))
        _check_lonlat(r.LON, r.LAT, "element $i")
        out[i, 1] = r.LON
        out[i, 2] = r.LAT
    end
    return out
end

function _check_lonlat(lon, lat, where_)
    (ismissing(lon) || ismissing(lat)) && throw(ArgumentError(
        "lonlat: $where_ has a missing LON or LAT (a place that was not found?)."))
    return nothing
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
    lonlat2loc(xy::AbstractVector, df::AbstractDataFrame; threshold=nothing)
    lonlat2loc(xy::AbstractVector; df=usplace(), threshold=nothing)

Find nearest place to a [LON, LAT] coordinate (reverse geocoding).

Uses area-based "in" radius by default: if within √(ALAND/π) of centroid,
reported as "in City"; otherwise "X mi DIR of City".

The places `df` are any table with `NAME`, `ST`, `LON` and `LAT` columns (and `ALAND` for the
"in" radius), a `DataFrame` or a view of one; given no table, they are [`usplace`](@ref)`()`, the
table the course passes at most of its calls (v0.3.1, A8).

Returns a named tuple with fields: NAME, ST, dist, bearing, dir, desc.
Geographic fields are UPPERCASE (`NAME`, `ST`; `ST isa Symbol`); metadata lowercase.

# Example
Lecture 2.2 names its optimum with `lonlat2loc(xᵒ, usplace()).desc`; with no table the call is
the same:

```jldoctest
xy = [-78.6382, 35.7796]
(lonlat2loc(xy).desc, lonlat2loc(xy) == lonlat2loc(xy, usplace()))

# output

("in Raleigh, NC", true)
```
"""
function lonlat2loc(xy::AbstractVector, df::AbstractDataFrame; threshold=nothing)
    length(xy) == 2 || throw(ArgumentError("xy must have length 2 [LON, LAT]"))
    XY = reshape(xy, 1, 2)
    result = lonlat2loc(XY, df; threshold=threshold)
    return (NAME=result.NAME[1], ST=result.ST[1], dist=result.dist[1],
            bearing=result.bearing[1], dir=result.dir[1], desc=result.desc[1])
end

lonlat2loc(xy::AbstractVector; df::AbstractDataFrame=usplace(), threshold=nothing) =
    lonlat2loc(xy, df; threshold=threshold)

"""
    lonlat2loc(XY::AbstractMatrix, df::AbstractDataFrame; threshold=nothing)
    lonlat2loc(XY::AbstractMatrix; df=usplace(), threshold=nothing)

Find nearest places to n×2 matrix of [LON LAT] coordinates, among the places `df` (by default
[`usplace`](@ref)`()`).

Returns DataFrame with columns: idx, NAME, ST, dist, bearing, dir, desc (`ST isa Symbol`).
"""
function lonlat2loc(XY::AbstractMatrix, df::AbstractDataFrame; threshold=nothing)
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

lonlat2loc(XY::AbstractMatrix; df::AbstractDataFrame=usplace(), threshold=nothing) =
    lonlat2loc(XY, df; threshold=threshold)
