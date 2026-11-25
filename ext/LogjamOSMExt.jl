module LogjamOSMExt

# The OpenStreetMap download for `osm_roads` (CR 21, 22, 24, 29, 34): the Overpass request, its retries, and the
# translation of the response to Logjam's two tables. Reading a saved tile pair is in core (osmtools.jl).

using Logjam
using LightOSM
using DataFrames
using Graphs

# the same User-Agent as LogjamNominatimExt: it names the package, never a person
const _user_agent = "Logjam.jl (educational use; https://github.com/mgkay/Logjam)"
const _OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# the network and the clock behind Refs, so a test can stand in for the server and not wait
_overpass_post(query::AbstractString) = begin
    r = LightOSM.HTTP.post(_OVERPASS_URL, ["User-Agent" => _user_agent], query;
                           status_exception = false, connect_timeout = 30, readtimeout = 600)
    (status = Int(r.status), body = String(r.body))
end
const _post_impl = Ref{Any}(_overpass_post)
const _sleep_impl = Ref{Any}(sleep)

# =============================================================================
# The Overpass request (CR 22, CR 29)
# =============================================================================
const _RETRY_STATUS = (429, 502, 503, 504)

# timeout (s) and maxsize (bytes) sized to the box, declared so that the public server admits the query: it
# admits a query only if its declared time and memory fit in half of what is free (CR 29's observation: a tile
# of about 116 sq mi was refused three times at the defaults and admitted at once declaring [timeout:90]
# [maxsize:134217728]; these two lines give 89 s and 2^27 bytes for it)
function _osm_sizing(area_mi2::Real)
    timeout = round(Int, clamp(60 + 0.25 * area_mi2, 60, 180))
    maxsize = 2^26 * clamp(ceil(Int, area_mi2 / 60), 1, 16)
    return timeout, maxsize
end

# LightOSM's own query for the box and the drivable network, with the declared sizes in place of its
# [timeout:180], and the class pre-filter (CR 29) as a second condition on `highway`
function _osm_query(bb::NTuple{4,Float64}; highways = nothing)
    xmin, xmax, ymin, ymax = bb
    timeout, maxsize = _osm_sizing(Logjam._osm_area_mi2(bb))
    r6(v) = round(v; digits = 6)                      # the snapped edges, without the arithmetic's last bits
    q = LightOSM.overpass_bbox_network_query([r6(ymin), r6(xmin), r6(ymax), r6(xmax)], :drive, false, :xml)
    occursin("[timeout:180]", q) || error("LightOSM's Overpass query has changed form: $q")
    q = replace(q, "[timeout:180]" => "[timeout:$timeout][maxsize:$maxsize]"; count = 1)
    if highways !== nothing
        q = replace(q, "way[\"highway\"]" => "way[\"highway\"][\"highway\"~\"^($(join(highways, '|')))\$\"]"; count = 1)
    end
    return q
end

# the response of one query, retried after a pause (30 s, then 60, then 120) when the server is busy (429,
# 502, 503, 504), as Overpass asks; any other answer is an error
function _osm_fetch(query::AbstractString; retries::Int = 3, pause::Real = 30, verbose::Bool = false)
    for k in 0:retries
        r = try
            _post_impl[](query)
        catch e
            error("Overpass request failed: $(sprint(showerror, e)). Check the Internet connection.")
        end
        if r.status == 200
            if occursin("<remark>", r.body) && occursin("runtime error", r.body)
                m = match(r"<remark>\s*(.*?)\s*</remark>"s, r.body)
                error("Overpass could not answer the query: ", m === nothing ? "runtime error" : m.captures[1],
                      " Try a smaller region, or a class filter (`highways`).")
            end
            return r.body
        end
        if r.status in _RETRY_STATUS && k < retries
            wait = pause * 2^k
            verbose && @info "Overpass answered HTTP $(r.status); trying again in $(wait) s"
            _sleep_impl[](wait)
            continue
        end
        error("Overpass answered HTTP $(r.status)", r.status in _RETRY_STATUS ?
              " after $(retries + 1) tries. The server is busy: try again later, or a smaller region." : ".")
    end
end

# the time now, UTC, as an ISO 8601 string (Dates is not a dependency)
function _utcnow()
    t = floor(Int, time())
    days, secs = fldmod(t, 86400)
    z = days + 719468
    era = fld(z, 146097)
    doe = z - era * 146097
    yoe = fld(doe - fld(doe, 1460) + fld(doe, 36524) - fld(doe, 146096), 365)
    y = yoe + era * 400
    doy = doe - (365 * yoe + fld(yoe, 4) - fld(yoe, 100))
    mp = fld(5 * doy + 2, 153)
    d = doy - fld(153 * mp + 2, 5) + 1
    m = mp < 10 ? mp + 3 : mp - 9
    y += m <= 2
    h, mi, s = secs ÷ 3600, (secs % 3600) ÷ 60, secs % 60
    return string(y, "-", lpad(m, 2, '0'), "-", lpad(d, 2, '0'), "T", lpad(h, 2, '0'), ":", lpad(mi, 2, '0'), ":",
                  lpad(s, 2, '0'), "Z")
end

# =============================================================================
# The download of one tile: the request, the tables, and what to say about them (CR 22)
# =============================================================================
function Logjam._osm_download(bb::NTuple{4,Float64}; highways = nothing, verbose::Bool = false)
    xmin, xmax, ymin, ymax = bb
    verbose && @info "Downloading OSM roads for the tile ($xmin, $xmax, $ymin, $ymax)"
    query = _osm_query(bb; highways)
    fetched = _utcnow()
    text = _osm_fetch(query; verbose)
    occursin("<way ", text) || error("No drivable roads found in the tile ($xmin, $xmax, $ymin, $ymax). " *
                                     "The region may be in water or contain no roads.")
    dfN, dfL, info = _osm_tables_from_xml(text; verbose)
    nrow(dfN) == 0 && error("No drivable roads found in the tile ($xmin, $xmax, $ymin, $ymax). " *
                            "The region may be in water or contain no roads.")
    m = match(r"<meta osm_base=\"([^\"]*)\"", text)
    prov = Pair{String,String}[
        "source" => "OpenStreetMap, from the Overpass API ($_OVERPASS_URL)",
        "fetched" => fetched,
        "osm_base" => m === nothing ? "" : String(m.captures[1]),
        "tile" => join(round.((xmin, xmax, ymin, ymax); digits = 6), ", "),
        "highways" => highways === nothing ? "all" : join(highways, " "),
        "nodes" => string(nrow(dfN)),
        "links" => string(nrow(dfL)),
        "links_closed_to_vehicles_dropped" => string(info.closed),
        "links_of_unknown_class_dropped" => string(info.unknown),
        "links_not_strongly_connected_dropped" => string(info.notstrong),
        "licence" => "(c) OpenStreetMap contributors. The data are available under the Open Database License " *
                     "(ODbL), https://opendatacommons.org/licenses/odbl/; see https://www.openstreetmap.org/copyright. " *
                     "These tables are a database derived from OpenStreetMap and are distributed under the ODbL.",
    ]
    return dfN, dfL, prov
end

# =============================================================================
# The response to two tables (CR 21, CR 24, CR 34)
# =============================================================================

# the tags of each way that the translation reads, as the XML has them: LightOSM replaces a way's `maxspeed`
# with its own km/h value (a default where there is none), so a posted speed is read from the text itself
const _WANTED_TAGS = Set(["maxspeed", "motorcar", "motor_vehicle", "vehicle", "access",
                          "motorcar:conditional", "motor_vehicle:conditional", "vehicle:conditional",
                          "access:conditional"])
_unxml(s) = replace(s, "&quot;" => "\"", "&apos;" => "'", "&lt;" => "<", "&gt;" => ">", "&amp;" => "&")
function _osm_raw_tags(text::AbstractString)
    raw = Dict{String,Dict{String,String}}()
    cur = nothing
    for line in eachline(IOBuffer(text))
        if startswith(lstrip(line), "<way ")
            m = match(r"<way id=\"([^\"]+)\"", line)
            cur = m === nothing ? nothing : get!(raw, String(m.captures[1]), Dict{String,String}())
        elseif cur !== nothing
            l = lstrip(line)
            if startswith(l, "<tag ")
                m = match(r"<tag k=\"([^\"]*)\" v=\"([^\"]*)\"", l)
                m !== nothing && m.captures[1] in _WANTED_TAGS &&
                    (cur[String(m.captures[1])] = _unxml(m.captures[2]))
            elseif startswith(l, "</way>")
                cur = nothing
            end
        end
    end
    return raw
end

# a posted `maxspeed` in mph, or `missing`: "35 mph" is 35; a number with no unit is km/h (OpenStreetMap's
# rule); "none", "signals", a list and the like are not a speed
function _osm_maxspeed(s::AbstractString)
    m = match(r"^\s*(\d+(?:\.\d+)?)\s*(mph|km/h|kmh|kph)?\s*$"i, s)
    m === nothing && return missing
    v = parse(Float64, m.captures[1])
    mph = m.captures[2] !== nothing && lowercase(m.captures[2]) == "mph" ? v : v / 1.609344
    return mph >= 1 ? round(Int, mph) : missing
end

# the values of an access tag that a car may not use
const _CLOSED = Set(["no", "private", "agricultural", "forestry", "emergency", "psv"])
const _ACCESS_KEYS = ("motorcar", "motor_vehicle", "vehicle", "access")   # the most specific first

# the value of the most specific access tag a car's rules look at, and the conditional rule of the most
# specific such key that has one (both `missing` where there is none)
function _osm_access(tags::AbstractDict)
    acc = missing
    for k in _ACCESS_KEYS
        if haskey(tags, k)
            acc = lowercase(strip(String(tags[k])))
            break
        end
    end
    cond = missing
    for k in _ACCESS_KEYS
        ck = k * ":conditional"
        if haskey(tags, ck)
            cond = String(tags[ck])
            break
        end
    end
    return acc, cond
end

_osm_tables_from_xml(text::AbstractString; verbose::Bool = false) = mktempdir() do dir
    path = joinpath(dir, "network.osm")
    write(path, text)
    g = _quiet(verbose) do
        LightOSM.graph_from_file(path; network_type = :drive, weight_type = :distance, graph_type = :light,
                                 largest_connected_component = false)
    end
    return _osm2dataframes(g, _osm_raw_tags(text); verbose)
end

_quiet(f, verbose) = verbose ? f() : Base.CoreLogging.with_logger(f, Base.CoreLogging.NullLogger())

# OSMGraph -> Logjam's tables. Nodes: IDX, LON, LAT, SOURCE. Links: SRC, DST, DIST (miles), SPEED (mph), FCLASS,
# DIR, NAME, SOURCE, and the three columns of v0.3.0: MAXSPEED (the posted speed, `missing` where none is posted;
# SPEED is it where there is one), ACCESS (the access tag that decides for a car) and CONDITIONAL (a conditional
# rule). A link on a way closed to cars (CR 34) or of a class not in the table (CR 24) is dropped, and the nodes
# are trimmed to the largest strongly connected set (CR 24).
function _osm2dataframes(g, raw = nothing; verbose::Bool = false)
    n = length(g.index_to_node)
    loc = Vector{Any}(undef, n)
    for (vertex_idx, node_id) in g.index_to_node
        loc[vertex_idx] = g.nodes[node_id].location
    end
    km_to_mi = 0.621371

    # one row per directed edge of the graph
    src, dst, dist, spd, fcl, name, mx, acc, cond = Int[], Int[], Float64[], Int[], Int[],
        Union{Missing,String}[], Union{Missing,Int}[], Union{Missing,String}[], Union{Missing,String}[]
    closed = unknown = 0
    for e in Graphs.edges(g.graph)
        u, v = Graphs.src(e), Graphs.dst(e)
        node_u, node_v = g.index_to_node[u], g.index_to_node[v]
        hw_class = "road"
        road_name = missing
        tags = Dict{String,Any}()
        posted = missing
        if haskey(g.edge_to_way, [node_u, node_v])
            way_id = g.edge_to_way[[node_u, node_v]]
            wtags = g.ways[way_id].tags
            hw_class = string(get(wtags, "highway", "road"))
            nm = get(wtags, "name", "")
            road_name = isempty(string(nm)) ? missing : string(nm)
            if raw !== nothing && haskey(raw, string(way_id))
                tags = raw[string(way_id)]
                posted = haskey(tags, "maxspeed") ? _osm_maxspeed(tags["maxspeed"]) : missing
            elseif raw === nothing
                tags = Dict{String,Any}(k => wtags[k] for k in _ACCESS_KEYS if haskey(wtags, k))
            end
        end
        a, c = _osm_access(tags)
        if !ismissing(a) && a in _CLOSED
            closed += 1
            continue
        end
        if !haskey(Logjam.OSM_FCLASS, hw_class)
            unknown += 1
            continue
        end
        push!(src, u); push!(dst, v)
        push!(dist, g.weights[u, v] * km_to_mi)             # LightOSM's weight matrix (km) to miles
        push!(spd, coalesce(posted, Logjam.OSM_SPEED_DEFAULTS[hw_class]))
        push!(fcl, Logjam.OSM_FCLASS[hw_class])
        push!(name, road_name); push!(mx, posted); push!(acc, a); push!(cond, c)
    end

    # the largest strongly connected set of the links that remain: a node that cannot reach the rest, or be
    # reached from it, is dropped with its links (a point joined to one would be at an infinite distance)
    notstrong = 0
    keep = trues(length(src))
    newid = zeros(Int, n)
    if !isempty(src)
        dg = Graphs.SimpleDiGraph(n)
        for (u, v) in zip(src, dst)
            Graphs.add_edge!(dg, u, v)
        end
        comps = Graphs.strongly_connected_components(dg)
        big = comps[argmax(length.(comps))]
        for (k, v) in enumerate(sort(big))
            newid[v] = k
        end
        keep = [newid[u] > 0 && newid[v] > 0 for (u, v) in zip(src, dst)]
        notstrong = count(!, keep)
    end
    nodes = findall(>(0), newid)
    nodes = nodes[sortperm(newid[nodes])]
    dfN = DataFrame(IDX = collect(1:length(nodes)), LON = [Float64(loc[v].lon) for v in nodes],
                    LAT = [Float64(loc[v].lat) for v in nodes], SOURCE = fill("OSM", length(nodes)))
    m = count(keep)
    dfL = DataFrame(SRC = newid[src[keep]], DST = newid[dst[keep]], DIST = dist[keep], SPEED = spd[keep],
                    FCLASS = fcl[keep], DIR = fill(1, m), NAME = name[keep], SOURCE = fill("OSM", m),
                    MAXSPEED = mx[keep], ACCESS = acc[keep], CONDITIONAL = cond[keep])
    verbose && @info "  Nodes DataFrame: $(nrow(dfN)) rows, Links DataFrame: $(nrow(dfL)) rows; dropped " *
                     "$closed closed to vehicles, $unknown of an unknown class, $notstrong not strongly connected"
    return dfN, dfL, (closed = closed, unknown = unknown, notstrong = notstrong)
end

end # module LogjamOSMExt
