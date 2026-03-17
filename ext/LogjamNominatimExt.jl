module LogjamNominatimExt

using Logjam
using HTTP
using JSON3

# Rate limiting: track last request time
const _last_request_time = Ref{Float64}(0.0)
const _min_request_interval = 1.0  # seconds (Nominatim policy)

const _user_agent = "Logjam.jl (educational use; https://github.com/ncsu-ise/Logjam.jl)"

function __init__()
    Logjam._nominatim_available[] = true
    Logjam._nominatim_geocode[] = _nominatim_geocode_impl
end

"""
    _rate_limit()

Enforce minimum interval between Nominatim API requests.
"""
function _rate_limit()
    now = time()
    elapsed = now - _last_request_time[]
    if elapsed < _min_request_interval
        sleep(_min_request_interval - elapsed)
    end
    _last_request_time[] = time()
end

"""
    _nominatim_geocode_impl(street, city, state, postalcode; country=:US)

Geocode a single address via Nominatim structured query.
Returns NamedTuple (lon, lat, display_name, importance) or missing.
Throws on network errors.
"""
function _nominatim_geocode_impl(street::AbstractString, city::AbstractString,
                                  state::AbstractString, postalcode::AbstractString;
                                  country::Symbol=:US)
    # Build query parameters
    params = Dict{String,String}(
        "format" => "jsonv2",
        "addressdetails" => "1",
        "limit" => "1"
    )

    # Add non-empty fields
    !isempty(street) && (params["street"] = street)
    !isempty(city) && (params["city"] = city)
    !isempty(state) && (params["state"] = state)
    !isempty(postalcode) && (params["postalcode"] = postalcode)

    # Country code
    cc = lowercase(String(country))
    params["countrycodes"] = cc

    # Rate limit
    _rate_limit()

    # Make request
    url = "https://nominatim.openstreetmap.org/search"
    headers = ["User-Agent" => _user_agent]

    local response
    try
        response = HTTP.get(url, headers; query=params, connect_timeout=10, readtimeout=30)
    catch e
        if e isa HTTP.Exceptions.ConnectError || e isa HTTP.Exceptions.TimeoutError
            throw(ErrorException("Network error connecting to Nominatim: $(sprint(showerror, e))"))
        end
        rethrow(e)
    end

    # Parse response
    results = JSON3.read(response.body)

    isempty(results) && return missing

    r = results[1]
    lon = parse(Float64, string(r.lon))
    lat = parse(Float64, string(r.lat))
    display_name = string(get(r, :display_name, ""))
    importance = Float64(get(r, :importance, 0.0))

    return (lon=lon, lat=lat, display_name=display_name, importance=importance)
end

end # module LogjamNominatimExt
