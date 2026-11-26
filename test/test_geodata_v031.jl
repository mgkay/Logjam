# test_geodata_v031.jl -- added by PCV WP5 of Logjam v0.3.1 (GC rest: review A's A4 and A6). Test spec Sec. 5.
# Equality is `==` (or `isequal`, where a column may hold `missing`) on every element, with the element types compared
# as well; no tolerance is used anywhere in this file. The evidence:
#   1. the batch driver (A4): v0.3.0's geocoder, its vector and DataFrame methods and the row resolver they call,
#      copied below as text, against the current methods on the same inputs, column for column, with the log records
#      (the progress line, the warnings) compared too; `_FAIL` and `_row` against the hand-written rows they replace;
#      the vector method on any vector of strings;
#   2. the column keywords (A6): each `*_col` gives what its old name gives; each old name is deprecated
#      (`@test_deprecated`) and, in a fresh process run with --depwarn=no, prints nothing; a state column that is
#      named and is not in the table is an `ArgumentError`, where v0.3.0 returned FAIL for every row; the literal
#      `state = ...` calls of src/geocode.jl's docstrings give v0.3.0's values.

using Test
using Logjam
using DataFrames
using Base.CoreLogging: with_logger, NullLogger    # Logging is not in the test environment (Pkg.test has no @stdlib)

# ---- v0.3.0's geocoder, verbatim (the v0.3.0 tag fd0f1f3, src/geocode.jl: _batch_row :478-486, _resolve_row
# :501-589, _loc2lonlat_one :741-759, the vector method :786-829, the DataFrame method :859-912, whose `df::DataFrame`
# A8 widened to `AbstractDataFrame` at 1d6657e; and the resolvers it calls, _match_name :87-128, _resolve_place
# :327-337, _resolve_postalcode :342-353, _resolve_county :358-368, _resolve_state :373-390). The reference for
# "the result tables equal": each is run beside the current method. The helpers WP5 does not change (address
# parsing, the cache, the fallback warning) are Logjam's own. ----
module GcV030
using DataFrames
using Logjam: usplace, uscounty, uszcta5, _normalize_name, _normalize_state, _throw_ambiguous, _uncertainty,
              _preprocess_address, _cache_key, _NOTFOUND, _row_from_entry, _nominatim_available,
              _nominatim_geocode, _entry_from_result, _store!, _notfound_entry, _fallback, _GeocodeCache,
              _load_cache, _cache_file, _flush!, _tighten, _is_postalcode, _parse_address_string, _reconcile_state

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

function _batch_row(f, i::Integer, what)
    try
        return f()
    catch e
        e isa ArgumentError && startswith(e.msg, "Unknown state") || rethrow()
        @warn "loc2lonlat: row $i (\"$what\"): $(e.msg); no location returned (status FAIL)."
        return (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL")
    end
end

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

# v0.3.0's scalar method, on the same row resolver (src/geocode.jl :726-738)
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
end # module GcV030

# ---- helpers ----
# run `f` with the address tier absent (hook = nothing) or replaced by `hook`; returns its value and its log records
# at Info and above, as (level, message) pairs, the deprecations (group :depwarn) set apart
function _gd_run(f, hook = nothing)
    saved = (Logjam._nominatim_available[], Logjam._nominatim_geocode[])
    try
        Logjam._nominatim_available[] = hook !== nothing
        hook === nothing || (Logjam._nominatim_geocode[] = hook)
        logs, val = Test.collect_test_logs(f; min_level = Base.CoreLogging.Info)
        recs = [(l.level, l.message) for l in logs if l.group !== :depwarn]
        return val, recs
    finally
        Logjam._nominatim_available[], Logjam._nominatim_geocode[] = saved
    end
end

# run `f` with the address tier absent, so that no call can reach the network (the Nominatim extension is loaded by
# the time this file runs)
function _gd_offline(f)
    saved = Logjam._nominatim_available[]
    try
        Logjam._nominatim_available[] = false
        return f()
    finally
        Logjam._nominatim_available[] = saved
    end
end

# a stand-in for Nominatim: "Nowhere Rd" is not found (NOTFOUND), an "Elm St" is found without its house number
# (STREET), any other street with its number (ADDRESS); the position depends on the street, so two streets differ
function _gd_stub(street, city, state, postalcode; country = :US)
    occursin("Nowhere", street) && return missing
    h = sum(Int, codeunits(street)) % 97
    m = match(r"^\d+", street)
    return (lon = -78.6 - h / 1000, lat = 35.7 + h / 1000,
            house_number = occursin("Elm", street) || m === nothing ? "" : m.match)
end

# two results are the same table: the same names, element types and values, column for column
_gd_same(a::DataFrame, b::DataFrame) =
    names(a) == names(b) && eltype.(eachcol(a)) == eltype.(eachcol(b)) && all(isequal(a[!, n], b[!, n]) for n in names(a))
_gd_same(a::NamedTuple, b::NamedTuple) = keys(a) == keys(b) && typeof(a) == typeof(b) && isequal(a, b)

# old and new on one call: equal values and equal log records; for a call with a cache file, the two files' bytes too
function _gd_both(fold, fnew; hook = nothing, cached = false)
    if cached
        mktempdir() do d
            po, pn = joinpath(d, "old.csv"), joinpath(d, "new.csv")
            vo, lo = _gd_run(() -> fold(po), hook)
            vn, ln = _gd_run(() -> fnew(pn), hook)
            return _gd_same(vo, vn) && lo == ln && read(po) == read(pn) && isfile(pn)
        end
    else
        vo, lo = _gd_run(fold, hook)
        vn, ln = _gd_run(fnew, hook)
        return _gd_same(vo, vn) && lo == ln
    end
end

# ---- 1. the batch driver (A4) -----------------------------------------------------------------------------------------
@testset "[WP5 A4] _FAIL and _row are the rows they replace" begin
    @test Logjam._FAIL === (LON=missing, LAT=missing, GC_SOURCE="", GC_UNCERT=missing, GC_STATUS="FAIL")
    for (f, args) in ((Logjam._resolve_place, ("Raleigh", :NC)), (Logjam._resolve_postalcode, ("27601",)),
                      (Logjam._resolve_county, ("Wake", :NC)), (Logjam._resolve_state, (:NC,)))
        result = f(args...)
        for status in ("OK", "PARTIAL")
            @test Logjam._row(result, status) === (LON=result.lon, LAT=result.lat, GC_SOURCE=result.source,
                                                    GC_UNCERT=Logjam._uncertainty(result.aland), GC_STATUS=status)
        end
    end
end

@testset "[WP5 A4] the vector method equals v0.3.0's, column for column, with its log records" begin
    for (v, kw) in (
            (["Raleigh", "Durham", "Chapel Hill"], (; state = :NC)),         # src/geocode.jl's example
            (["27601", "27708", "27514"], (;)),
            (["Raleigh, NC", "27695", "Zzyzx", ""], (;)),                       # one FAIL, one empty
            (["Raleigh", "Athens", "Asheville"], (; state = [:NC, :GA, :NC])),  # one state each
            (["Raleigh", "Durham", "Cary"], (; state = [:NC, "XX", missing])),  # a bad state: that row FAIL, warned
            (["Raliegh", "Raleigh"], (; state = :NC)),                           # the state tier (GC)
            (String[], (;)),                                                      # no rows
            (repeat(["27601", "Raleigh, NC", "Zzyzx"], 20), (;)))                 # 60 rows: the progress line at 50
        @test _gd_both(() -> GcV030.loc2lonlat(v; kw...), () -> loc2lonlat(v; kw...))
    end
    # addresses, with the address tier stood in for, and the cache file each writes
    v = ["10 Main St, Raleigh, NC 27601", "7 Elm St, Durham, NC", "5 Nowhere Rd, Cary, NC", "27695",
         "PO Box 5, Raleigh, NC 27601"]
    @test _gd_both(p -> GcV030.loc2lonlat(v; cache = p), p -> loc2lonlat(v; cache = p); hook = _gd_stub, cached = true)
    @test _gd_both(() -> GcV030.loc2lonlat(v), () -> loc2lonlat(v))           # the address tier absent: warned
    # the stub's ADDRESS, STREET and NOTFOUND are what this case is about
    r, _ = _gd_run(() -> loc2lonlat(v), _gd_stub)
    @test r.GC_SOURCE == ["ADDRESS", "STREET", "PLACE", "POSTALCODE", "PLACE"]
end

@testset "[WP5 A4] the vector method takes any vector of strings" begin
    v = ["Raleigh", "Durham", "Chapel Hill", "Cary"]
    r = loc2lonlat(v; state = :NC)
    @test _gd_same(loc2lonlat(view(v, 2:3); state = :NC), r[2:3, :])
    @test _gd_same(loc2lonlat(SubString.(v); state = :NC)[!, Not(:INPUT)], r[!, Not(:INPUT)])
    @test loc2lonlat(SubString.(v); state = :NC).INPUT == v
    @test loc2lonlat(view(v, 2:3); state = :NC).INPUT isa Vector{String}
    @test which(loc2lonlat, (Vector{String},)).sig == Tuple{typeof(loc2lonlat), AbstractVector{<:AbstractString}}
    @test which(loc2lonlat, (Vector{Int},)).sig == Tuple{typeof(loc2lonlat), AbstractVector{<:Integer}}
end

@testset "[WP5 A4] the DataFrame method equals v0.3.0's, column for column, with its log records" begin
    tables = [DataFrame(CITY = ["Raleigh", "Durham"], STATE = [:NC, :NC]),
              DataFrame(POSTALCODE = [27601, 2139, missing]),
              DataFrame(POSTALCODE = ["27601", "27695-1234", "2139"]),
              DataFrame(COUNTY = ["Wake", "Durham"], STATE = [:NC, :NC]),
              DataFrame(STATE = [:NC, :VA]),
              DataFrame(CITY = ["Raleigh", missing], STATE = [:NC, :NC], X = [7, 8]),
              DataFrame(CITY = ["Raleigh", "Durham", "Cary"], STATE = ["NC", "XX", "NC"]),
              DataFrame(CITY = ["Athens", "Portland", "Jacksonville"]),
              DataFrame(STREET = ["1 Main St", "2 Main St"], CITY = ["Raleigh", "Raleigh"], STATE = ["ZZ", "NC"]),
              DataFrame(CITY = repeat(["Raleigh", "Zzyzx"], 30), STATE = fill(:NC, 60)),
              DataFrame(LON = [1.0], CITY = ["Durham"], STATE = [:NC]),             # a LON column is replaced in place
              DataFrame(CITY = String[], STATE = Symbol[])]
    for t in tables
        @test _gd_both(() -> GcV030.loc2lonlat(t), () -> loc2lonlat(t))
    end
    big = DataFrame(CITY = ["Raleigh", "Durham", "Cary", "Apex"], STATE = fill(:NC, 4))
    @test _gd_both(() -> GcV030.loc2lonlat(view(big, 2:3, :)), () -> loc2lonlat(view(big, 2:3, :)))
    # other column names: v0.3.0's keywords against the `*_col` keywords
    t = DataFrame(addr = ["10 Main St", "7 Elm St", "5 Nowhere Rd", missing], town = ["Raleigh", "Durham", "Cary", "Apex"],
                  st = ["NC", "NC", "NC", "NC"], zip = [27601, missing, 27513, 27502], cty = ["Wake", "Durham", "Wake", "Wake"])
    @test _gd_both(p -> GcV030.loc2lonlat(t; street = :addr, city = :town, state = :st, postalcode = :zip,
                                          county = :cty, cache = p),
                   p -> loc2lonlat(t; street_col = :addr, city_col = :town, state_col = :st, postalcode_col = :zip,
                                   county_col = :cty, cache = p); hook = _gd_stub, cached = true)
    tc = DataFrame(cty = ["Wake", "Nowhere"], st = [:NC, :NC])
    @test _gd_both(() -> GcV030.loc2lonlat(tc; county = :cty, state = :st), () -> loc2lonlat(tc; county_col = :cty, state_col = :st))
end

# ---- 2. the column keywords (A6) --------------------------------------------------------------------------------------
@testset "[WP5 A6] each *_col keyword gives what its old name gives" begin
    t = DataFrame(addr = ["10 Main St", "7 Elm St"], town = ["Raleigh", "Durham"], st = ["NC", "NC"],
                  zip = [27601, 27701], cty = ["Wake", "Durham"])
    quiet(f) = with_logger(f, NullLogger())
    for (knew, kold, col) in ((:street_col, :street, :addr), (:city_col, :city, :town), (:state_col, :state, :st),
                              (:postalcode_col, :postalcode, :zip), (:county_col, :county, :cty))
        rnew, _ = _gd_run(() -> loc2lonlat(t; NamedTuple{(knew,)}((col,))...), _gd_stub)
        rold, _ = _gd_run(() -> quiet(() -> loc2lonlat(t; NamedTuple{(kold,)}((col,))...)), _gd_stub)
        @test _gd_same(rnew, rold)
    end
    # all five at once, old names, new names and the two mixed; a column named by a string
    all_new = (; street_col = :addr, city_col = :town, state_col = :st, postalcode_col = :zip, county_col = :cty)
    all_old = (; street = :addr, city = :town, state = :st, postalcode = :zip, county = :cty)
    rnew, _ = _gd_run(() -> loc2lonlat(t; all_new...), _gd_stub)
    @test _gd_same(rnew, first(_gd_run(() -> quiet(() -> loc2lonlat(t; all_old...)), _gd_stub)))
    @test _gd_same(rnew, first(_gd_run(() -> quiet(() -> loc2lonlat(t; street = :addr, city_col = :town, state = :st,
                                                                     postalcode_col = :zip, county = :cty)), _gd_stub)))
    @test _gd_same(rnew, first(_gd_run(() -> loc2lonlat(t; street_col = "addr", city_col = "town", state_col = "st",
                                                         postalcode_col = "zip", county_col = "cty"), _gd_stub)))
    # the stub found the first address, so the street column was read
    @test rnew.GC_SOURCE == ["ADDRESS", "STREET"]
    # the same keyword twice, by both names, is refused
    @test_throws ArgumentError loc2lonlat(t; city_col = :town, city = :town)
    @test_throws ArgumentError loc2lonlat(t; state_col = :st, state = :st)
end

@testset "[WP5 A6] each old name is deprecated, under Pkg.test's --depwarn=yes" begin
    t = DataFrame(addr = ["PO Box 5"], town = ["Raleigh"], st = [:NC], zip = [27601], cty = ["Wake"])   # no network
    _gd_offline() do
        # what each call gives with the new names
        rs = loc2lonlat(t; street_col = :addr, city_col = :town, state_col = :st)
        r = loc2lonlat(t; city_col = :town, state_col = :st)
        rz = loc2lonlat(t; city_col = :town, state_col = :st, postalcode_col = :zip)
        rc = loc2lonlat(t; city_col = :town, state_col = :st, county_col = :cty)
        if Base.JLOptions().depwarn == 1
            @test _gd_same(rs, @test_deprecated r"`street = :addr` is deprecated, use `street_col = :addr`" loc2lonlat(t; street = :addr, city_col = :town, state_col = :st))
            @test _gd_same(r, @test_deprecated r"`city = :town` is deprecated, use `city_col = :town`" loc2lonlat(t; city = :town, state_col = :st))
            @test _gd_same(r, @test_deprecated r"`state = :st` is deprecated, use `state_col = :st`" loc2lonlat(t; city_col = :town, state = :st))
            @test _gd_same(rz, @test_deprecated r"`postalcode = :zip` is deprecated, use `postalcode_col = :zip`" loc2lonlat(t; city_col = :town, state_col = :st, postalcode = :zip))
            @test _gd_same(rc, @test_deprecated r"`county = :cty` is deprecated, use `county_col = :cty`" loc2lonlat(t; city_col = :town, state_col = :st, county = :cty))
            # two old names in one call: one warning naming both
            @test_deprecated r"`city = :town`, `state = :st` are deprecated, use `city_col = :town`, `state_col = :st`" loc2lonlat(t; city = :town, state = :st)
        end
        # the new names, and no column keyword at all, warn of nothing
        @test_logs min_level = Base.CoreLogging.Warn loc2lonlat(t; city_col = :town, state_col = :st)
        @test_logs min_level = Base.CoreLogging.Warn loc2lonlat(DataFrame(CITY = ["Raleigh"], STATE = [:NC]))
    end
end

@testset "[WP5 A6] an old name prints nothing under --depwarn=no (a fresh process)" begin
    code = """
    using Logjam, DataFrames
    t = DataFrame(town = ["Raleigh"], st = [:NC], cty = ["Wake"])
    r = loc2lonlat(t; city = :town, state = :st, county = :cty)
    print("RESULT=", r.GC_SOURCE[1], ",", r.GC_STATUS[1])
    """
    child(flag) = (out = IOBuffer();
                   cmd = `$(Base.julia_cmd()) $flag --startup-file=no --project=$(Base.active_project()) -e $code`;
                   ok = success(pipeline(cmd; stdout = out, stderr = out)); (ok, String(take!(out))))
    ok, out = child("--depwarn=no")
    @test ok && out == "RESULT=PLACE,OK"
    # the check can fail: the same call under --depwarn=yes prints the deprecation
    ok, out = child("--depwarn=yes")
    @test ok && occursin("deprecated, use `city_col = :town`", out) && endswith(out, "RESULT=PLACE,OK")
end

@testset "[WP5 A6] a state column that is named and is not in the table is an ArgumentError" begin
    # review A's measurement: the vector method's `state` given to a table read `:GA` as a column, FAIL for every row
    t = DataFrame(CITY = ["Athens", "Portland", "Jacksonville"])
    old, _ = _gd_run(() -> GcV030.loc2lonlat(t; state = :GA))
    @test old.GC_STATUS == ["FAIL", "FAIL", "FAIL"]
    for kw in ((; state = :GA), (; state_col = :GA), (; state = "GA"), (; state_col = :ST), (; state_col = :STATE))
        e = try
            loc2lonlat(t; kw...)
            nothing
        catch err
            err
        end
        @test e isa ArgumentError
        @test occursin("names no column of the table (its columns are CITY)", e.msg) && occursin("`state_col`", e.msg)
    end
    e = try loc2lonlat(t; state = :GA); nothing catch err; err end
    @test occursin("To geocode every row in the state GA, add the column", e.msg)
    e = try loc2lonlat(t; state_col = :ST); nothing catch err; err end
    @test !occursin("To geocode every row", e.msg)                      # :ST is no state: no such hint
    # the state column given by default and absent is no error: the table has no state, as before
    z = DataFrame(POSTALCODE = [27601, 27695])
    @test _gd_both(() -> GcV030.loc2lonlat(z), () -> loc2lonlat(z))
    # a column keyword other than the state's that names no column is the part not given, as before
    @test _gd_both(() -> GcV030.loc2lonlat(z; city = :nope, street = :nope, county = :nope),
                   () -> loc2lonlat(z; city_col = :nope, street_col = :nope, county_col = :nope))
end

@testset "[WP5 A6] the literal `state = ...` calls of src/geocode.jl give v0.3.0's values" begin
    # every call in a docstring of src/geocode.jl that passes `state` (the string and vector methods, whose `state`
    # is a state and is unchanged); no DataFrame-method call in src/, the lectures or HW 1 to 5 passes `state`
    for (f, args, kw) in ((loc2lonlat, ("Raleigh",), (; state = :NC)), (loc2lonlat, ("Raliegh",), (; state = :NC)),
                          (loc2lonlat, ("Memphis",), (; state = :TN)), (loc2lonlat, ("27601",), (; state = :NC)))
        @test _gd_both(() -> GcV030.loc2lonlat(args...; kw...), () -> f(args...; kw...))
    end
    for (v, kw) in ((["Raleigh", "Durham", "Chapel Hill"], (; state = :NC)), (["Raleigh", "Durham"], (; state = :NC)),
                    (["Raleigh", "Athens", "Asheville"], (; state = [:NC, :GA, :NC])))
        @test _gd_both(() -> GcV030.loc2lonlat(v; kw...), () -> loc2lonlat(v; kw...))
    end
    @test _gd_both(() -> GcV030.loc2lonlat(DataFrame(addr = ["123 Main St"], town = ["Raleigh"], st = ["NC"]);
                                           street = :addr, city = :town, state = :st),
                   () -> loc2lonlat(DataFrame(addr = ["123 Main St"], town = ["Raleigh"], st = ["NC"]);
                                    street_col = :addr, city_col = :town, state_col = :st))
end
