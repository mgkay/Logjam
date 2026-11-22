# faf5net.jl -- the derived FAF5 road network (CR 19), part one: what route a link carries, which links are
# Interstates, what a ramp is, and where the junctions are (PCV N1, his rulings RN3 to RN10). Internal: nothing here is
# exported or public. The derivation (tools/v0_3_2/make_faf5net.jl, N2) builds on these functions, and from N4 the
# map's road layer reads the same ramp rule, so the derivation and the map agree on what a ramp is. Until then the map
# keeps v0.3.0's rule (ext/LogjamMapExt.jl), which is the first part of the one here.
#
# The functions read FAF5-shaped tables: nodes with IDX, LON and LAT; links with SRC and DST (node IDX values), DIR (0
# two-way, 1 one-way from SRC to DST, -1 one-way from DST to SRC), FCLASS, SIGN and NAME (either may be missing). The
# whole network is handled alike: the lower 48, Alaska, Hawaii and Puerto Rico.

# ---------------------------------------------------------------------------------------------------------------------
# Route keys
# ---------------------------------------------------------------------------------------------------------------------

# FAF5 writes one state route under two prefixes, its state's postal code and "SR": Florida's 429 is "FL 429" by SIGN
# and "SR 429" by NAME, Virginia's 7 "VA 7" and "SR 7". The key writes every state route "SR".
const _STATE_CODES = ("AK", "AL", "AR", "AZ", "CA", "CO", "CT", "DC", "DE", "FL", "GA", "HI", "IA", "ID", "IL", "IN",
                      "KS", "KY", "LA", "MA", "MD", "ME", "MI", "MN", "MO", "MS", "MT", "NC", "ND", "NE", "NH", "NJ",
                      "NM", "NV", "NY", "OH", "OK", "OR", "PA", "PR", "RI", "SC", "SD", "TN", "TX", "UT", "VA", "VT",
                      "WA", "WI", "WV", "WY")
const _SR_WORDS = "SR|STATE ROUTE|STATE HWY|STATE HIGHWAY|STATE ROAD|" * join(_STATE_CODES, "|")
const _SR_PREFIX = Regex("^(?:$_SR_WORDS)[ -]?(?=\\d)")
const _I_PREFIX = r"^INTERSTATE[ -]?(?=\d)"
const _SYSTEM_PREFIX = r"^(I|US|CR|FM)[ -]?(?=\d)"
# A NAME that is a route designation: a system's prefix, a number with an optional letter (35E), an optional qualifier
# of up to three letters (B Business, P Bypass, L Loop) and an optional direction. Any other NAME is a road's own name.
const _NAME_DESIG = Regex("^(?:I|INTERSTATE|US|CR|FM|HWY|HIGHWAY|M|$_SR_WORDS)[ -]?\\d+[A-Z]?(?: [A-Z]{1,3})?" *
                          "(?: [NSEW]B?)?\$")
# A direction ends some Interstate SIGNs ("I 93 N" and "I 93 S", the two carriageways of one road) and is dropped there
# only (his ruling RN9, 2026-11-22): on any other route the letter names the route ("US 70 N" and "US 70 S" are two
# roads, "GA 204 S" is a spur). An Interstate NAME may end in NB, SB, EB or WB.
const _SIGN_DIR = r"^(I \S*\d\S*(?: B)?) [NSEW]$"
const _NAME_DIR = r" [NSEW]B?$"

# The text of a SIGN or NAME: upper case, spaces trimmed and runs of them made one; `nothing` when missing or blank.
function _keytext(x)
    (x === nothing || ismissing(x)) && return nothing
    t = uppercase(strip(replace(string(x), r"\s+" => " ")))
    return isempty(t) ? nothing : t
end

_unifyprefix(s) = replace(replace(replace(s, _SR_PREFIX => "SR "), _I_PREFIX => "I "), _SYSTEM_PREFIX => s"\1 ")

"""
    _route(sign, name) -> Union{String, Nothing}

The route a FAF5 link carries, as one key per road: its SIGN when it has one, else its NAME. State-route prefixes are
unified ("FL 429" and "SR 429" are both "SR 429"); a direction is dropped from an Interstate only ("I 93 N" and
"I 93 S" are both "I 93", "I 496 EB" is "I 496"; "US 70 N" and "US 70 S" stay two routes, RN9); and a Business route
stays its own route ("I 40 B" is not "I 40"). A NAME that is not a route designation is the key as written, in upper
case. A link with neither SIGN nor NAME carries no route (`nothing`).
"""
function _route(sign, name)
    s = _keytext(sign)
    if s !== nothing
        m = match(_SIGN_DIR, s)
        return _unifyprefix(m === nothing ? s : String(m.captures[1]))
    end
    n = _keytext(name)
    n === nothing && return nothing
    occursin(_NAME_DESIG, n) || return n
    n = _unifyprefix(n)
    return startswith(n, "I ") ? replace(n, _NAME_DIR => "") : n
end

# ---------------------------------------------------------------------------------------------------------------------
# The Interstate flag
# ---------------------------------------------------------------------------------------------------------------------

# Exactly an Interstate designation: "I", a number, an optional letter (35E, 69C) and an optional direction letter;
# or Alaska's and Hawaii's lettered numbers (I A1 to A4, I H1, H2, H201, H3; RN8). A NAME may write "INTERSTATE" or a
# hyphen and end in a two-letter direction. Never a Business route ("I 40 B").
const _I_SIGN = r"^I (?:\d+[A-Z]?|[AH]\d+)(?: [NSEW])?$"
const _I_NAME = r"^(?:I|INTERSTATE)[ -]?(?:\d+[A-Z]?|[AH]-?\d+)(?: [NSEW]B?)?$"
const _BUSINESS_SIGN = r" (?:B|BUS|BUSINESS)(?: [NSEW]B?)?$"

"""
    _isinterstate(sign, name, fclass) -> Bool

Whether a FAF5 link is an Interstate (his rulings RN3 and RN8, 2026-11-22): its SIGN is exactly an Interstate
designation ("I", a number, an optional letter suffix as in 35E, an optional direction letter; or Alaska's and
Hawaii's lettered numbers, I A1 to A4 and I H1, H2, H201, H3), or, on a class 1 link, its NAME is. Never a Business
route. I-296 in Grand Rapids, signed US 131 and named "I 296", is found by its NAME.
"""
function _isinterstate(sign, name, fclass)
    s = _keytext(sign)
    if s !== nothing
        occursin(_I_SIGN, s) && return true
        occursin(_BUSINESS_SIGN, s) && return false
    end
    n = _keytext(name)
    return n !== nothing && coalesce(fclass == 1, false) && occursin(_I_NAME, n)
end

# ---------------------------------------------------------------------------------------------------------------------
# Ramps by name
# ---------------------------------------------------------------------------------------------------------------------

# v0.3.0's rule (the map extension's `_RAMP_NAME`, his ruling of 2026-11-21): a ramp, a collector-distributor lane or a
# turn lane. "CONNECTOR" alone names real roads ("AIRPORT CONNECTOR").
const _RAMP_WORDS = r"\bRAMPS?\b|(COLLECTOR|CONNECTOR)\s*/\s*DISTRIBUTOR|\bC/D LANE\b|\bTURN LANE\b"
# RN4's two additions (2026-11-22). A collector-distributor lane however FAF5 spells it ("COLLECCTOR/DISTRIBUTOR",
# "COLLECTOR/DISTRBUTOR", "COLLECTION/DISTRIBUTION"); "DOWNTOWN DISTRIBUTOR" is a road. And a ramp named "X TO Y" (as
# RN10 widened it): a one-way link with a route designation on at least one side ("I 96 EB TO I 696 EB",
# "GRAND RIVER RD TO I 69 EB"); with none on either side it is a road ("GOING TO THE SUN HWY", "DIBC PLAZA TO CANADA").
const _CD_ANY_SPELLING = r"COLLE\w*\s*/\s*DIST\w*"
const _DESIG_TOKEN = "(?:I [AH]\\d+|(?:I|US|CR|FM|M|SR|" * join(_STATE_CODES, "|") * ")[ -]?\\d+[A-Z]?)" *
                     "(?: B| BUS)?(?: (?:[NSEW]B?|IL|OL))?"
const _DESIG_SIDE = Regex("^/?$_DESIG_TOKEN(?: ?/ ?$_DESIG_TOKEN)*\$")

# The three parts of the name rule, each on its own so the counts of each can be reported.
_isramp_v030(name) = !ismissing(name) && occursin(_RAMP_WORDS, uppercase(string(name)))
_isramp_cd(name) = (n = _keytext(name); n !== nothing && occursin(_CD_ANY_SPELLING, n))
function _isramp_to(name, dir)
    coalesce(dir != 0, false) || return false
    n = _keytext(name)
    n === nothing && return false
    for m in eachmatch(r" TO ", n)
        a = SubString(n, 1, prevind(n, m.offset)); b = SubString(n, m.offset + 4)
        (occursin(_DESIG_SIDE, a) || occursin(_DESIG_SIDE, b)) && return true
    end
    return false
end

"""
    _isramp_name(name, dir) -> Bool

Whether a FAF5 link's NAME (with its DIR, 0 for two-way) marks a ramp (his rulings RN4 and RN10, 2026-11-22): v0.3.0's
rule (a ramp, a collector-distributor lane, a turn lane), a collector-distributor lane however it is spelled, or
"X TO Y" on a one-way link with a route designation on at least one side. CONNECTOR names are roads; a missing name is
not a ramp by name (`_ramp_links` adds the structural test).
"""
_isramp_name(name, dir) = _isramp_v030(name) || _isramp_cd(name) || _isramp_to(name, dir)

# ---------------------------------------------------------------------------------------------------------------------
# Topology
# ---------------------------------------------------------------------------------------------------------------------

# Each link's two nodes as rows of N, and the nodes' coordinates.
function _topology(N, L)
    nN, nL = nrow(N), nrow(L)
    row = Dict{Int,Int}(Int(N.IDX[v]) => v for v in 1:nN)
    S = Vector{Int}(undef, nL); D = Vector{Int}(undef, nL)
    for k in 1:nL
        s = get(row, Int(L.SRC[k]), 0); d = get(row, Int(L.DST[k]), 0)
        (s == 0 || d == 0) && throw(ArgumentError("link $k joins a node that is not in the node table"))
        S[k] = s; D[k] = d
    end
    return (; nN, nL, S, D, lon = Float64.(N.LON), lat = Float64.(N.LAT))
end

# Each link's route as a number (0 for a ramp or a link that carries none); equal numbers are equal `_route` keys.
function _routeids(L, isramp)
    ids = Dict{String,Int}(); seen = Dict{Tuple{Any,Any},Int}()
    rid = zeros(Int, nrow(L))
    for k in 1:nrow(L)
        isramp[k] && continue
        key = (L.SIGN[k], L.NAME[k])
        rid[k] = get!(seen, key) do
            r = _route(key...)
            r === nothing ? 0 : get!(ids, r, length(ids) + 1)
        end
    end
    return rid
end

# Union-find over 1:n; the smaller root wins, so a set's root is its smallest member and every labeling is the same
# from run to run.
_uf(n) = collect(1:n)
function _root!(p, x)
    while p[x] != x
        p[x] = p[p[x]]
        x = p[x]
    end
    return x
end
function _join!(p, a, b)
    ra, rb = _root!(p, a), _root!(p, b)
    ra == rb && return p
    ra < rb ? (p[rb] = ra) : (p[ra] = rb)
    return p
end

# The connected components of the links with `member[k]`: a component number for every node (0 on no such link),
# numbered by each component's smallest node, and the count.
function _components(T, member)
    p = _uf(T.nN); on = falses(T.nN)
    for k in 1:T.nL
        member[k] || continue
        _join!(p, T.S[k], T.D[k]); on[T.S[k]] = on[T.D[k]] = true
    end
    comp = zeros(Int, T.nN); num = zeros(Int, T.nN); nc = 0
    for v in 1:T.nN
        on[v] || continue
        r = _root!(p, v)
        num[r] == 0 && (nc += 1; num[r] = nc)
        comp[v] = num[r]
    end
    return comp, nc
end

_dmi(T, a, b) = dgc((T.lon[a], T.lat[a]), (T.lon[b], T.lat[b]))

# The largest distance (miles) between two of the nodes, exact when it is near `cap`: a box whose diagonal is at most
# `cap` holds no two nodes farther apart than that, and in one whose diagonal is more than cap * sqrt(2) two nodes are
# farther apart than `cap`; between the two every pair is measured.
function _extent(T, nodes, cap)
    lo1, hi1 = extrema(T.lon[v] for v in nodes); lo2, hi2 = extrema(T.lat[v] for v in nodes)
    diag = dgc((lo1, lo2), (hi1, hi2))
    (diag <= cap || diag > cap * sqrt(2) + 1e-9) && return diag
    m = 0.0
    for i in eachindex(nodes), j in i+1:lastindex(nodes)
        m = max(m, _dmi(T, nodes[i], nodes[j]))
    end
    return m
end

# ---------------------------------------------------------------------------------------------------------------------
# Ramps: the name rule and the structural test
# ---------------------------------------------------------------------------------------------------------------------

const _RAMP_EXTENT = 0.75               # miles: N0's 99th percentile of named-ramp length (RN4)

"""
    _ramp_links(N, L) -> Vector{Bool}

Whether each link of `L` is a ramp (his rulings RN4 and RN10, 2026-11-22): its NAME marks one (`_isramp_name`), or it
passes the structural test, applied by cluster. Unnamed one-way links (no SIGN and no NAME, any class) form clusters
with the named ramps they touch; a cluster whose links lie within 0.75 mi of each other (the largest distance between
two of its nodes) and that touches two or more routes (`_route`), at least one of them on a class 1 or 2 link, makes
its unnamed links ramps. The test never reaches a named link.
"""
function _ramp_links(N, L)
    T = _topology(N, L)
    named = [_isramp_name(L.NAME[k], L.DIR[k]) for k in 1:T.nL]
    rid = _routeids(L, named)
    unnamed = [!named[k] && rid[k] == 0 && coalesce(L.DIR[k] != 0, false) for k in 1:T.nL]
    comp, nc = _components(T, named .| unnamed)
    r1 = zeros(Int, nc); two = falses(nc); fast = falses(nc)
    for k in 1:T.nL
        rid[k] == 0 && continue
        for v in (T.S[k], T.D[k])
            c = comp[v]; c == 0 && continue
            if r1[c] == 0
                r1[c] = rid[k]
            elseif r1[c] != rid[k]
                two[c] = true
            end
            coalesce(L.FCLASS[k] in (1, 2), false) && (fast[c] = true)
        end
    end
    members = [Int[] for _ in 1:nc]
    for v in 1:T.nN
        comp[v] > 0 && push!(members[comp[v]], v)
    end
    ok = [two[c] && fast[c] && _extent(T, members[c], _RAMP_EXTENT) <= _RAMP_EXTENT for c in 1:nc]
    isramp = copy(named)
    for k in 1:T.nL
        unnamed[k] && ok[comp[T.S[k]]] && (isramp[k] = true)
    end
    return isramp
end

# ---------------------------------------------------------------------------------------------------------------------
# Junctions
# ---------------------------------------------------------------------------------------------------------------------

const _RMERGE = 1.5                     # miles: 4.1's seed radius for one interchange's clusters
const _RANY = 0.25                      # miles: a seed this close takes a cluster whatever routes they share (RN6)
const _ATGRADE = 150 / 1609.344         # miles: N0's at-grade radius within one route pair (rule C)
const _EARTH_MI = 3958.75               # dgc's sphere

# Each node's links (compressed: the links of node v are adj[off[v]:off[v+1]-1]).
function _incidence(T)
    off = zeros(Int, T.nN + 1)
    for k in 1:T.nL
        off[T.S[k]+1] += 1; off[T.D[k]+1] += 1
    end
    off[1] = 1
    for v in 1:T.nN
        off[v+1] += off[v]
    end
    adj = Vector{Int}(undef, 2T.nL); nxt = copy(off)
    for k in 1:T.nL
        adj[nxt[T.S[k]]] = k; nxt[T.S[k]] += 1
        adj[nxt[T.D[k]]] = k; nxt[T.D[k]] += 1
    end
    return off, adj
end

# A point on the sphere in miles, and its cube of side h: every point within an arc of h miles lies in one of the 27
# cubes around it, since a chord is never longer than its arc.
_xyz(lon, lat) = (_EARTH_MI * cosd(lat) * cosd(lon), _EARTH_MI * cosd(lat) * sind(lon), _EARTH_MI * sind(lat))
_cube(p, h) = (floor(Int, p[1] / h), floor(Int, p[2] / h), floor(Int, p[3] / h))
_center(T, nodes) = (sum(T.lon[v] for v in nodes) / length(nodes), sum(T.lat[v] for v in nodes) / length(nodes))

# The interchange clusters before merging, each with its members and its sorted routes: the connected components of
# ramp links that touch links of two or more routes, and (4.1's second rule, his ruling RN7) each other node where the
# main lines of two or more routes meet, a main line being a freeway or expressway carriageway (a one-way link of
# classes 0 to 2).
function _interchangeclusters(T, L, isramp, rid, off, adj)
    comp, nc = _components(T, isramp)
    routes = [Int[] for _ in 1:nc]
    for k in 1:T.nL
        rid[k] == 0 && continue
        for v in (T.S[k], T.D[k])
            c = comp[v]; c == 0 && continue
            rid[k] in routes[c] || push!(routes[c], rid[k])
        end
    end
    keep = [length(routes[c]) >= 2 for c in 1:nc]
    members = [Int[] for _ in 1:nc]
    for v in 1:T.nN
        comp[v] > 0 && keep[comp[v]] && push!(members[comp[v]], v)
    end
    members = members[keep]; routes = sort!.(routes[keep])
    for v in 1:T.nN
        comp[v] > 0 && keep[comp[v]] && continue
        rs = Int[]
        for k in view(adj, off[v]:off[v+1]-1)
            (rid[k] == 0 || coalesce(L.DIR[k] == 0, true) || !coalesce(0 <= L.FCLASS[k] <= 2, false)) && continue
            rid[k] in rs || push!(rs, rid[k])
        end
        length(rs) >= 2 && (push!(members, [v]); push!(routes, sort!(rs)))
    end
    return members, routes
end

# 4.1's merge, restricted (his ruling RN6): clusters in order of size, largest first (ties by smallest node); each
# joins the first seed within 1.5 mi of its center that shares two or more routes with it (the same crossing, as the
# at-grade rule keeps to one route pair), or the first within 0.25 mi whatever it shares, or becomes a seed. Returns
# the merged groups (cluster numbers) in seed order.
function _seedmerge(T, members, routes)
    ctr = [_center(T, m) for m in members]
    order = sort(eachindex(members), by = c -> (-length(members[c]), first(members[c])))
    grid = Dict{NTuple{3,Int},Vector{Int}}()
    seeds = Int[]; groups = Vector{Int}[]
    for c in order
        q = _cube(_xyz(ctr[c]...), _RMERGE); best = 0
        for dx in -1:1, dy in -1:1, dz in -1:1, s in get(grid, (q[1] + dx, q[2] + dy, q[3] + dz), Int[])
            (best == 0 || s < best) || continue
            d = dgc(ctr[c], ctr[seeds[s]])
            d <= _RMERGE || continue
            (d <= _RANY || length(intersect(routes[c], routes[seeds[s]])) >= 2) && (best = s)
        end
        if best == 0
            push!(seeds, c); push!(groups, [c]); push!(get!(grid, q, Int[]), length(seeds))
        else
            push!(groups[best], c)
        end
    end
    return groups
end

# The at-grade clusters: nodes where a one-way link of classes 0 to 3 meets a link of another route, joined to another
# such node of the same route pair within 150 m (pair-restricted, so a street grid does not chain), leaving out the
# nodes `taken` by an interchange. Returns the clusters' members, numbered by smallest node.
function _atgradeclusters(T, L, rid, off, adj, taken)
    r = _ATGRADE
    pairs = Dict{Tuple{Int,Int},Vector{Int}}()
    for v in 1:T.nN
        taken[v] && continue
        at = view(adj, off[v]:off[v+1]-1)
        for j in at
            (rid[j] == 0 || coalesce(L.DIR[j] == 0, true) || !coalesce(0 <= L.FCLASS[j] <= 3, false)) && continue
            for k in at
                (rid[k] == 0 || rid[k] == rid[j]) && continue
                vs = get!(pairs, minmax(rid[j], rid[k]), Int[])
                (isempty(vs) || last(vs) != v) && push!(vs, v)
            end
        end
    end
    p = _uf(T.nN); cand = falses(T.nN)
    for key in sort!(collect(keys(pairs)))
        vs = pairs[key]; cand[vs] .= true
        grid = Dict{NTuple{3,Int},Vector{Int}}()
        for v in vs
            push!(get!(grid, _cube(_xyz(T.lon[v], T.lat[v]), r), Int[]), v)
        end
        for v in vs
            q = _cube(_xyz(T.lon[v], T.lat[v]), r)
            for dx in -1:1, dy in -1:1, dz in -1:1, w in get(grid, (q[1] + dx, q[2] + dy, q[3] + dz), Int[])
                w > v && _dmi(T, v, w) <= r && _join!(p, v, w)
            end
        end
    end
    num = zeros(Int, T.nN); members = Vector{Int}[]
    for v in 1:T.nN
        cand[v] || continue
        rt = _root!(p, v)
        num[rt] == 0 && (push!(members, Int[]); num[rt] = length(members))
        push!(members[num[rt]], v)
    end
    return members
end

"""
    _junctions(N, L, isramp) -> (; cl, site, kind)

The junctions of a FAF5-shaped network, given which links are ramps (`_ramp_links`).

- Interchanges: the connected components of ramp links that touch links of two or more routes (`_route`), and the
  nodes where freeway or expressway carriageways (one-way links of classes 0 to 2) of two or more routes meet (RN7);
  merged by seed, largest first (Lecture 4.1's rule), a cluster joining a seed within 1.5 mi that shares two of its
  routes, or any seed within 0.25 mi (RN6).
- At-grade crossings: nodes where a one-way link of classes 0 to 3 (a divided road) meets a link of another route,
  merged with other such nodes of the same route pair within 150 m. Every other crossing is an ordinary node.

`cl[v]` is the junction of node `v` (a row of `N`), or 0; `site[c]` is junction `c`'s node, the member nearest the
members' center (4.1's rule); `kind[c]` is `:interchange` or `:atgrade`. Destructures as `cl, site = _junctions(...)`.
"""
function _junctions(N, L, isramp)
    T = _topology(N, L)
    off, adj = _incidence(T)
    rid = _routeids(L, isramp)
    members, routes = _interchangeclusters(T, L, isramp, rid, off, adj)
    cl = zeros(Int, T.nN); kind = Symbol[]; mem = Vector{Int}[]
    for g in _seedmerge(T, members, routes)
        push!(mem, sort!(reduce(vcat, members[g]))); push!(kind, :interchange)
        cl[last(mem)] .= length(mem)
    end
    for m in _atgradeclusters(T, L, rid, off, adj, cl .> 0)
        push!(mem, m); push!(kind, :atgrade)
        cl[m] .= length(mem)
    end
    site = [argmin(v -> dgc(_center(T, m), (T.lon[v], T.lat[v])), m) for m in mem]
    return (; cl, site, kind)
end
