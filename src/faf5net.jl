# faf5net.jl -- the derived FAF5 road network (CR 19). Part one: what route a link carries, which links are
# Interstates, what a ramp is, and where the junctions are (PCV N1, his rulings RN3 to RN10, RN12 as narrowed by RN17).
# Part two: the derivation itself (PCV N2, his rulings RN13 to RN19), `_faf5net`, which tools/v0_3_1/make_faf5net.jl
# runs to write the shipped files. Part three (PCV N3, his rulings RD1 and RD2, D7): how those files are written, and
# the three exported accessors, `usrdnode`, `usrdlink` and `usrdnodemap`, which read them from the `faf5net` artifact;
# everything else here is internal. From N4 the map's road layer reads the same ramp rule, so the derivation and the
# map agree on what a ramp is. Until then the map keeps v0.3.0's rule (ext/LogjamMapExt.jl), which is the first part
# of the one here.
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
# On a link whose SIGN is an Interstate designation by the flag's sign test, "X TO Y" is a ramp only when both sides
# are route designations (RN12 as narrowed by RN17): FAF5 signs "I 95 NB APPROACH TO I 80" as I 95, the Interstate's own
# carriageway, while "I 95 SB TO I 476 NB" (signed I 476) and "I 581 NB TO I 81 NB" (signed I 581) are the terminal
# ramps of an Interstate that ends. The name rule's other words reach every link ("SYSTEM RAMP - I 35 NB" is signed
# I 35 and is a ramp).
const _CD_ANY_SPELLING = r"COLLE\w*\s*/\s*DIST\w*"
const _DESIG_TOKEN = "(?:I [AH]\\d+|(?:I|US|CR|FM|M|SR|" * join(_STATE_CODES, "|") * ")[ -]?\\d+[A-Z]?)" *
                     "(?: B| BUS)?(?: (?:[NSEW]B?|IL|OL))?"
const _DESIG_SIDE = Regex("^/?$_DESIG_TOKEN(?: ?/ ?$_DESIG_TOKEN)*\$")

# The three parts of the name rule, each on its own so the counts of each can be reported.
_isramp_v030(name) = !ismissing(name) && occursin(_RAMP_WORDS, uppercase(string(name)))
_isramp_cd(name) = (n = _keytext(name); n !== nothing && occursin(_CD_ANY_SPELLING, n))
function _isramp_to(name, dir, sign = missing)
    coalesce(dir != 0, false) || return false
    n = _keytext(name)
    n === nothing && return false
    s = _keytext(sign)
    both = s !== nothing && occursin(_I_SIGN, s)
    for m in eachmatch(r" TO ", n)
        a = SubString(n, 1, prevind(n, m.offset)); b = SubString(n, m.offset + 4)
        da, db = occursin(_DESIG_SIDE, a), occursin(_DESIG_SIDE, b)
        (both ? da && db : da || db) && return true
    end
    return false
end

"""
    _isramp_name(name, dir, sign = missing) -> Bool

Whether a FAF5 link's NAME (with its DIR, 0 for two-way, and its SIGN) marks a ramp (his rulings RN4, RN10, RN12 and
RN17, 2026-11-22): v0.3.0's rule (a ramp, a collector-distributor lane, a turn lane), a collector-distributor lane
however it is spelled, or "X TO Y" on a one-way link with a route designation on at least one side, or on both sides
when the link's SIGN is an Interstate designation. CONNECTOR names are roads; a missing name is not a ramp by name
(`_ramp_links` adds the structural test).
"""
_isramp_name(name, dir, sign = missing) = _isramp_v030(name) || _isramp_cd(name) || _isramp_to(name, dir, sign)

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
    named = [_isramp_name(L.NAME[k], L.DIR[k], L.SIGN[k]) for k in 1:T.nL]
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

# ---------------------------------------------------------------------------------------------------------------------
# The derivation (PCV N2, his rulings of round n2: RN13 to RN19)
# ---------------------------------------------------------------------------------------------------------------------

const _PAIR_ENDS = 2.0                  # miles: N0's bound between the facing ends of a route's two directions
const _FUZZY_ENDS = 0.5                 # miles: ends at two different junctions this close count as one end (RN13)
const _SEP_FAST = 1000.0                # meters: rule C, a pair of classes 0 to 2 (RN5)
const _SEP_SLOW = 100.0                 # meters: rule C, a pair of classes 3 and up, with a NAME in common (RN5, RN16)
const _FRONTAGE = r"FRONTAGE|SERVICE|ACCESS RD"   # a frontage or service road pair stays one-way (RN5)
const _TWO_SIDED = 120                  # degrees: a route's one-way links this far apart at a junction are both directions
const _TURN_BACK = 135                  # degrees: a link in and a link out this far apart turn back on each other
const _M_PER_MI = 1609.344
const _MI_PER_DEG = _EARTH_MI * pi / 180

_bearing(T, a, b) = atand(T.lat[b] - T.lat[a], (T.lon[b] - T.lon[a]) * cosd(T.lat[a]))
_angle(x, y) = abs(mod(x - y + 180, 360) - 180)

# RN15: every ramp cluster (a connected component of ramp links) that meets no junction becomes a junction of its own
# (kind :ramp, its node the member nearest the members' center), and one that meets exactly one junction joins it. An
# interchange with an unnamed road and a rest area are such clusters.
function _rampjunctions(T, J, isramp)
    cl = copy(J.cl); site = copy(J.site); kind = copy(J.kind)
    comp, nc = _components(T, isramp)
    mem = [Int[] for _ in 1:nc]
    for v in 1:T.nN
        comp[v] > 0 && push!(mem[comp[v]], v)
    end
    for c in 1:nc
        js = unique(cl[v] for v in mem[c] if cl[v] > 0)
        if isempty(js)
            push!(kind, :ramp); push!(site, argmin(v -> dgc(_center(T, mem[c]), (T.lon[v], T.lat[v])), mem[c]))
            cl[mem[c]] .= length(site)
        elseif length(js) == 1
            for v in mem[c]
                cl[v] == 0 && (cl[v] = js[1])
            end
        end
    end
    return (; cl, site, kind)
end

# RN13 (i): a junction's node is on its main road, the member touching a routed link of the junction's lowest FCLASS
# that lies nearest the members' center (ties to the first member).
function _mainsites(T, L, J, isramp, rid)
    best = fill(typemax(Int), T.nN)
    for k in 1:T.nL
        (isramp[k] || rid[k] == 0) && continue
        for v in (T.S[k], T.D[k])
            best[v] = min(best[v], L.FCLASS[k])
        end
    end
    mem = [Int[] for _ in eachindex(J.site)]
    for v in 1:T.nN
        J.cl[v] > 0 && push!(mem[J.cl[v]], v)
    end
    site = copy(J.site)
    for c in eachindex(mem)
        b = minimum(best[v] for v in mem[c])
        b == typemax(Int) && continue
        ctr = _center(T, mem[c])
        site[c] = argmin(v -> dgc(ctr, (T.lon[v], T.lat[v])), [v for v in mem[c] if best[v] == b])
    end
    return (; cl = J.cl, site, kind = J.kind)
end

# The (junction, route) pairs where both directions of the route meet the junction: two of the route's one-way links
# at its members run more than 120 degrees apart.
function _twosided(T, J, ow, rid, tl, hd, off, adj)
    br = [Dict{Int,Vector{Float64}}() for _ in eachindex(J.site)]
    for v in 1:T.nN
        c = J.cl[v]; c == 0 && continue
        for k in view(adj, off[v]:off[v+1]-1)
            ow[k] && push!(get!(br[c], rid[k], Float64[]), _bearing(T, tl[k], hd[k]))
        end
    end
    two = Set{Tuple{Int,Int}}()
    for c in eachindex(br), (r, b) in br[c]
        any(_angle(b[i], b[j]) > _TWO_SIDED for i in eachindex(b) for j in i+1:lastindex(b)) && push!(two, (c, r))
    end
    return two
end

"""
    _stretches(T, L, isramp, rid, J, off, adj) -> NamedTuple

Each route's one-way links (not ramps) as stretches from stop to stop (RN13, D1: 4.1's junction-to-junction search per
route). A stretch follows its route's one-way links in the direction of travel through every node that is not a stop
for that route. A stop for route r: a member of a junction both directions of r meet (`_twosided`); or any other node
where r's one-way links are not exactly one in and one out (a branch, an end), where r also has a two-way link (the road
becomes undivided), or where the one in and the one out turn back on each other (more than 135 degrees). A junction
only one direction of r meets is passed. A loop of one route with no stop is one stretch (`cyc`). The end identity is
the junction for a stop in a two-sided junction, else 0.
"""
function _stretches(T, L, isramp, rid, J, off, adj)
    nL = T.nL
    ow = [!isramp[k] && rid[k] != 0 && L.DIR[k] != 0 for k in 1:nL]
    tl = [L.DIR[k] == -1 ? T.D[k] : T.S[k] for k in 1:nL]
    hd = [L.DIR[k] == -1 ? T.S[k] : T.D[k] for k in 1:nL]
    two = _twosided(T, J, ow, rid, tl, hd, off, adj)
    stopid(v, r) = (c = J.cl[v]; c > 0 && (c, r) in two ? c : 0)
    function isstop(v, r)
        stopid(v, r) > 0 && return true
        nin = 0; nout = 0; kin = 0; kout = 0
        for k in view(adj, off[v]:off[v+1]-1)
            (rid[k] == r && !isramp[k]) || continue
            ow[k] || return true
            hd[k] == v && (nin += 1; kin = k)
            tl[k] == v && (nout += 1; kout = k)
        end
        (nin == 1 && nout == 1 && kin != kout) || return true
        return _angle(_bearing(T, tl[kin], hd[kin]), _bearing(T, tl[kout], hd[kout])) > _TURN_BACK
    end
    function outlink(v, r)
        for k in view(adj, off[v]:off[v+1]-1)
            ow[k] && rid[k] == r && tl[k] == v && return k
        end
        return 0
    end
    used = falses(nL); st = Vector{Int}[]; cyc = Bool[]
    for pass in 1:2                     # from every stop first; then the loops no stop reaches
        for k in 1:nL
            (ow[k] && !used[k]) || continue
            pass == 1 && !isstop(tl[k], rid[k]) && continue
            seq = [k]; used[k] = true
            while pass == 2 || !isstop(hd[seq[end]], rid[k])
                nx = outlink(hd[seq[end]], rid[k])
                (nx == 0 || used[nx]) && break
                push!(seq, nx); used[nx] = true
            end
            push!(st, seq); push!(cyc, pass == 2)
        end
    end
    path = [[tl[seq[1]]; [hd[k] for k in seq]] for seq in st]
    R = [rid[seq[1]] for seq in st]
    i0 = [cyc[i] ? 0 : stopid(path[i][1], R[i]) for i in eachindex(st)]
    i1 = [cyc[i] ? 0 : stopid(path[i][end], R[i]) for i in eachindex(st)]
    return (; st, path, R, i0, i1, cyc, two)
end

# The opposing stretches of one route whose end identities match crosswise (equal, or two different junctions within
# 0.5 mi, RN13), the facing ends within 2 mi of each other, each the other's best by the sum of the two end distances
# (ties to the lower stretch number). Stretches with `skip` take no part.
function _pairstretches(T, path, R, i0, i1, skip, cl)
    nst = length(path); h = _PAIR_ENDS
    same(a, b, x, y) = a == b || (cl[x] > 0 && cl[y] > 0 && cl[x] != cl[y] && _dmi(T, x, y) <= _FUZZY_ENDS)
    grid = Dict{Tuple{Int,NTuple{3,Int}},Vector{Int}}()
    for i in 1:nst
        skip[i] && continue
        s = path[i][1]
        push!(get!(grid, (R[i], _cube(_xyz(T.lon[s], T.lat[s]), h)), Int[]), i)
    end
    best = zeros(Int, nst); bsc = fill(Inf, nst)
    for i in 1:nst
        skip[i] && continue
        s, e = path[i][1], path[i][end]
        q = _cube(_xyz(T.lon[e], T.lat[e]), h)
        for dx in -1:1, dy in -1:1, dz in -1:1, j in get(grid, (R[i], (q[1] + dx, q[2] + dy, q[3] + dz)), Int[])
            j == i && continue
            (same(i1[i], i0[j], e, path[j][1]) && same(i0[i], i1[j], s, path[j][end])) || continue
            d1 = _dmi(T, e, path[j][1]); d1 <= h || continue
            d2 = _dmi(T, s, path[j][end]); d2 <= h || continue
            sc = d1 + d2
            (sc < bsc[i] || (sc == bsc[i] && j < best[i])) && (bsc[i] = sc; best[i] = j)
        end
    end
    return [(i, best[i]) for i in 1:nst if best[i] > i && best[best[i]] == i]
end

_median(x) = (s = sort(x); n = length(s); isodd(n) ? s[(n+1)÷2] : (s[n÷2] + s[n÷2+1]) / 2)

# The distance (miles) from node v to the segment from a to b, on a plane through v (N0's measure).
function _pseg(T, v, a, b)
    c = cosd(T.lat[v])
    ax = (T.lon[a] - T.lon[v]) * c * _MI_PER_DEG; ay = (T.lat[a] - T.lat[v]) * _MI_PER_DEG
    bx = (T.lon[b] - T.lon[v]) * c * _MI_PER_DEG; by = (T.lat[b] - T.lat[v]) * _MI_PER_DEG
    dx = bx - ax; dy = by - ay; l2 = dx * dx + dy * dy
    t = l2 == 0 ? 0.0 : clamp(-(ax * dx + ay * dy) / l2, 0.0, 1.0)
    return hypot(ax + t * dx, ay + t * dy)
end

# The median separation (meters) of two stretches: from up to 60 evenly spaced nodes of the first to the second's line.
function _separation(T, pa, pb)
    n = length(pa)
    sel = n <= 60 ? (1:n) : round.(Int, range(1, n, length = 60))
    return _median(sort!([minimum(_pseg(T, pa[i], pb[s], pb[s+1]) for s in 1:length(pb)-1) for i in sel]) .* _M_PER_MI)
end

# A stretch's class, the FCLASS most of its links have (ties to the lower class).
function _stretchclass(L, seq)
    cs = sort([L.FCLASS[k] for k in seq])
    best, bc, i = cs[1], 0, 1
    while i <= length(cs)
        j = i
        while j < length(cs) && cs[j+1] == cs[i]
            j += 1
        end
        j - i + 1 > bc && (best = cs[i]; bc = j - i + 1)
        i = j + 1
    end
    return best
end

# Each route key's text, by number.
function _routekeys(L, rid)
    keys = fill("", maximum(rid; init = 0))
    for k in eachindex(rid)
        r = rid[k]
        (r == 0 || !isempty(keys[r])) && continue
        keys[r] = _route(L.SIGN[k], L.NAME[k])
    end
    return keys
end

"""
    _carriageways(T, L, isramp, rid, J, off, adj, rkey) -> NamedTuple

The stretches (`_stretches`), their pairs (`_pairstretches`) and rule C's verdict on each pair (D3, RN5, RN16): a pair
of classes 0 to 2 (the lower of the two stretches' classes) is one divided road when its median separation is at most
1,000 m; a pair of classes 3 and up when it is at most 100 m and the two sides have a NAME in common; a frontage or
service road pair never. Of an accepted pair the shorter stretch is kept (D1; ties to the first). A stretch with both
ends in one junction lies inside it (`inside`) and takes no part.
"""
function _carriageways(T, L, isramp, rid, J, off, adj, rkey)
    S = _stretches(T, L, isramp, rid, J, off, adj)
    chains, path, R, i0, i1 = S.st, S.path, S.R, S.i0, S.i1
    inside = [i0[i] > 0 && i0[i] == i1[i] for i in eachindex(chains)]
    pairs = _pairstretches(T, path, R, i0, i1, inside .| S.cyc, J.cl)
    cls = [_stretchclass(L, seq) for seq in chains]
    len = [sum(L.DIST[k] for k in seq) for seq in chains]
    nameset(seq) = sort!(unique!([n for n in (_keytext(L.NAME[k]) for k in seq) if n !== nothing]))
    np = length(pairs)
    sep = zeros(np); pcls = zeros(Int, np); same = falses(np); front = falses(np); accept = falses(np)
    keep = zeros(Int, np); drop = zeros(Int, np)
    for (q, (i, j)) in enumerate(pairs)
        sep[q] = _separation(T, path[i], path[j])
        pcls[q] = min(cls[i], cls[j])
        a, b = nameset(chains[i]), nameset(chains[j])
        same[q] = !isempty(intersect(a, b))
        front[q] = any(x -> occursin(_FRONTAGE, x), [rkey[R[i]]; a; b])
        accept[q] = !front[q] && (pcls[q] <= 2 ? sep[q] <= _SEP_FAST : (sep[q] <= _SEP_SLOW && same[q]))
        keep[q], drop[q] = len[i] <= len[j] ? (i, j) : (j, i)
    end
    return (; chains, path, R, i0, i1, inside, cyc = S.cyc, two = S.two, cls, len, pairs, sep, pcls, same, front, accept,
            keep, drop)
end

"""
    _collapse(T, N, J, isramp, C, gone, off, adj) -> (img, rule)

The node each node of the network is collapsed to (D6), given which links go before collapsing (`gone`: ramps, the
longer stretch of each accepted pair, the stretches removed inside a junction). Returns each node's image (a row of
`N`) and the rule that set it: 0 itself, 1 its junction's node, 2 the facing ends of an accepted pair outside every
junction, 3 a node of a dropped stretch, 4 an inner node of a stretch removed inside a junction, 5 a node only ramps
touch, 6 a junction moved.

- A junction's members are one node, its site (`_mainsites`); the facing ends of each accepted pair join it (D3), never
  joining two junctions; facing ends outside every junction are one node, the member on a remaining link nearest the
  members' center (ties to the lower IDX).
- A junction that only the dropped direction meets moves to the kept stretch's node nearest its site (a node in no
  junction where there is one); one that lies on a stretch removed inside another junction moves to that junction's
  node; and one at the dropped end of a pair whose ends are two junctions (RN13's 0.5 mi) moves to the kept end's.
- A dropped stretch's inner nodes go to the nearest node of the stretch kept in its place, a removed inside stretch's
  inner nodes to its junction's node, and a node only ramps touch, outside every junction, to the nearest of the nodes
  its ramp cluster reaches that remain.
"""
function _collapse(T, N, J, isramp, C, gone, off, adj)
    nN = T.nN
    p = _uf(nN)
    for v in 1:nN
        J.cl[v] > 0 && _join!(p, v, J.site[J.cl[v]])
    end
    jr = zeros(Int, nN)                 # the junction of each set's root, 0 for none
    for v in 1:nN
        J.cl[v] > 0 && (jr[_root!(p, v)] = J.cl[v])
    end
    for (q, (i, j)) in enumerate(C.pairs)
        C.accept[q] || continue
        for (x, y) in ((C.path[i][1], C.path[j][end]), (C.path[i][end], C.path[j][1]))
            rx, ry = _root!(p, x), _root!(p, y)
            rx == ry && continue
            jx, jy = jr[rx], jr[ry]
            jx > 0 && jy > 0 && jx != jy && continue
            _join!(p, rx, ry); jr[_root!(p, rx)] = max(jx, jy)
        end
    end
    onlink = falses(nN)
    for k in 1:T.nL
        gone[k] || (onlink[T.S[k]] = onlink[T.D[k]] = true)
    end
    members = Dict{Int,Vector{Int}}()
    for v in 1:nN
        r = _root!(p, v)
        (r != v || J.cl[v] > 0) && push!(get!(members, r, Int[]), v)
    end
    img = collect(1:nN); rule = zeros(Int8, nN)
    for r in sort!(collect(keys(members)))
        m = members[r]; r in m || push!(m, r); sort!(m)
        js = unique(J.cl[v] for v in m if J.cl[v] > 0)
        if !isempty(js)
            s = J.site[js[1]]
        else
            ctr = _center(T, m)
            cand = filter(v -> onlink[v], m); isempty(cand) && (cand = m)
            s = argmin(v -> (dgc(ctr, (T.lon[v], T.lat[v])), N.IDX[v]), cand)
        end
        for v in m
            img[v] = s; rule[v] = isempty(js) ? 2 : 1
        end
    end
    near(v, cands) = argmin(w -> (dgc((T.lon[v], T.lat[v]), (T.lon[w], T.lat[w])), N.IDX[w]), cands)
    move = Dict{Int,Int}()              # a junction -> the node it moves to
    for (q, (i, j)) in enumerate(C.pairs)
        C.accept[q] || continue
        kp, dp = C.path[C.keep[q]], C.path[C.drop[q]]
        for v in dp[2:end-1]
            c = J.cl[v]
            (c == 0 || haskey(move, c)) && continue
            cand = [w for w in kp[2:end-1] if J.cl[w] == 0]
            isempty(cand) && (cand = kp)
            move[c] = near(J.site[c], cand)
        end
    end
    for (i, inside) in enumerate(C.inside)
        inside || continue
        c0 = J.cl[C.path[i][1]]
        for v in C.path[i][2:end-1]
            c = J.cl[v]
            (c == 0 || c == c0 || haskey(move, c)) && continue
            move[c] = J.site[c0]
        end
    end
    for (q, (i, j)) in enumerate(C.pairs)
        C.accept[q] || continue
        kp, dp = C.path[C.keep[q]], C.path[C.drop[q]]
        for (x, y) in ((kp[1], dp[end]), (kp[end], dp[1]))
            cx, cy = J.cl[x], J.cl[y]
            (cx > 0 && cy > 0 && cx != cy && !haskey(move, cy)) || continue
            move[cy] = J.site[cx]
        end
    end
    target = Dict{Int,Int}()            # an old image (a junction's node) -> its new one
    for c in sort!(collect(keys(move)))
        target[img[J.site[c]]] = img[move[c]]
    end
    function resolve(x)
        n = 0
        while haskey(target, x) && target[x] != x && n < 100
            x = target[x]; n += 1
        end
        return x
    end
    if !isempty(target)
        for v in 1:nN
            haskey(target, img[v]) && (img[v] = resolve(img[v]); rule[v] = 6)
        end
    end
    for (i, inside) in enumerate(C.inside)
        inside || continue
        s = img[J.site[J.cl[C.path[i][1]]]]
        for v in C.path[i][2:end-1]
            J.cl[v] == 0 && (img[v] = s; rule[v] = 4)
        end
    end
    for (q, (i, j)) in enumerate(C.pairs)
        C.accept[q] || continue
        cand = unique(C.path[C.keep[q]])
        for v in C.path[C.drop[q]][2:end-1]
            J.cl[v] == 0 && (img[v] = img[near(v, cand)]; rule[v] = 3)
        end
    end
    comp, nc = _components(T, isramp)
    reach = [Int[] for _ in 1:nc]
    for v in 1:nN
        comp[v] > 0 && onlink[v] && push!(reach[comp[v]], v)
    end
    for v in 1:nN
        (J.cl[v] == 0 && comp[v] > 0 && rule[v] == 0 && !onlink[v]) || continue
        all(k -> isramp[k], view(adj, off[v]:off[v+1]-1)) || continue
        cand = unique(img[w] for w in reach[comp[v]])
        isempty(cand) && continue
        img[v] = near(v, cand); rule[v] = 5
    end
    return img, rule
end

# A SIGN as the derived network writes it: FAF5's text, with an Interstate's direction letter dropped (RN9).
function _signtext(sign)
    s = _keytext(sign)
    s === nothing && return nothing
    m = match(_SIGN_DIR, s)
    return m === nothing ? s : String(m.captures[1])
end

# A US route ("US 1", "US 1 A", "US 70 B") and a state route ("SR 7", "NC 54", "MA 6A", Missouri's "MO AW", and in a
# NAME Michigan's "M 14" and "STATE HWY 7").
const _US_DESIG = r"^US[ -]?\d"
const _STATE_DESIG = Regex("^(?:SR|STATE ROUTE|STATE HWY|STATE HIGHWAY|STATE ROAD|M|" * join(_STATE_CODES, "|") *
                           ")(?: [A-Z\\d]|-?\\d)")

"""
    _roadtype(signs, name, interstate) -> Union{String, Missing}

Matlog's road type letter (his ruling RD4; Matlog's `usrdlink` Type): "I" an Interstate (the flag), "U" a US route, "S"
a state route, "L" a road with a NAME and no route designation, `missing` (blank) otherwise: a Business Interstate, a
county or farm-to-market route, any other designation ("HWY 7"), an unnamed road. `signs` are the link's SIGNs (I over
U over S when it has several); a link with none is read by its NAME when the NAME is a designation.
"""
function _roadtype(signs, name, interstate)
    interstate && return "I"
    n = _keytext(name)
    des = !isempty(signs) ? signs : (n !== nothing && occursin(_NAME_DESIG, n)) ? [n] : String[]
    any(s -> occursin(_US_DESIG, s), des) && return "U"
    any(s -> occursin(_STATE_DESIG, s), des) && return "S"
    return isempty(des) && n !== nothing ? "L" : missing
end

# A link's travel time in its direction of travel (FAF5's AB_TIME or BA_TIME).
_traveltime(L, k) = L.DIR[k] == -1 ? L.BA_TIME[k] : L.AB_TIME[k]

"""
    _faf5net(N, L) -> (; nodes, links, nodemap, info)

The derived road network of a FAF5-shaped network (CR 19, PCV N2, his rulings RN13 to RN19), pure: `N` and `L` are
read, never changed. `N` has IDX, LON and LAT; `L` has SRC, DST, DIST, DIR, FCLASS, SIGN, NAME, SPEED, AB_SPEED,
BA_SPEED, AB_TIME, BA_TIME, STFIP, COFIP and URBAN, as `faf5nodes()` and `faf5links()` do.

1. Ramps (`_ramp_links`) and junctions (`_junctions`), every ramp cluster outside them a junction too (RN15), each
   junction's node on its main road (RN13).
2. Carriageways (`_carriageways`): each route's two directions paired from stop to stop and judged by rule C. Of an
   accepted pair the shorter stretch is kept, its links two-way (`DIR = 0`), and the other's links go; the kept link's
   own direction keeps FAF5's time and the other direction gets the dropped stretch's total time shared over the kept
   links by DIST (D5), so each stretch takes FAF5's time each way. A rejected or unpaired stretch keeps its direction
   and times. A stretch inside one junction goes, unless it is that junction's only link or another road meets one of
   its inner nodes (RN13).
3. Junctions collapse (`_collapse`, D1, D6): each becomes one node; ramps go; a link whose two ends become one node
   goes; of links on one pair of nodes with one route and the same directions the shortest stays.
4. Stubs (RN14): a link end that moves adds the great-circle distance it moved to DIST, and each direction's time
   grows in the same proportion (a link of DIST 0 adds the stub at FAF5's AB_SPEED and BA_SPEED).
5. Attributes (D11, RD4): links `SRC`, `DST` (FAF5 IDX, FAF5's direction), `DIST`, `SPEED`, `FCLASS` (the lower of the
   two carriageways'), `DIR`, `NAME`, `SOURCE` ("FAF5"), `SIGN` (the routes both carriageways carry, sorted and
   `;`-joined, RN2), `TYPE` (`_roadtype`), `INTERSTATE` (either carriageway, D9), `AB_TIME`, `BA_TIME`, `STFIP`,
   `COFIP`, `URBAN`; nodes `IDX`, `LON`, `LAT`, `SOURCE`; node map `FAF5_IDX`, `IDX`, every FAF5 node once, `IDX`
   missing for a node whose FAF5 component keeps no derived link (FAF5's components made only of ramps, RN19). DIST
   and the times are rounded to 4 decimals; every table is sorted by its keys.

`info` holds the intermediate results the tests and the report read (`C.inside` the stretches removed inside a
junction, `inside0` every stretch with both ends in one junction, the ones kept by RN13 included).
"""
function _faf5net(N, L)
    isramp = _ramp_links(N, L)
    T = _topology(N, L)
    rid = _routeids(L, isramp)
    J = _mainsites(T, L, _rampjunctions(T, _junctions(N, L, isramp), isramp), isramp, rid)
    off, adj = _incidence(T)
    rkey = _routekeys(L, rid)
    C = _carriageways(T, L, isramp, rid, J, off, adj, rkey)
    nL = T.nL
    role = zeros(Int, nL); gone = copy(isramp)          # role: 0 alone, q kept for accepted pair q, -q dropped
    for (i, inside) in enumerate(C.inside)
        inside && (gone[C.chains[i]] .= true)
    end
    for (q, (i, j)) in enumerate(C.pairs)
        C.accept[q] || continue
        role[C.chains[C.keep[q]]] .= q; role[C.chains[C.drop[q]]] .= -q
        gone[C.chains[C.drop[q]]] .= true
    end
    # RN13 (ii): a stretch inside one junction stays when the junction keeps no other link or a road meets its inner nodes
    other = zeros(Int, length(J.site))
    for k in 1:nL
        gone[k] && continue
        for v in (T.S[k], T.D[k])
            J.cl[v] > 0 && (other[J.cl[v]] += 1)
        end
    end
    inside0 = C.inside; inside = copy(inside0)
    for (i, ins) in enumerate(inside0)
        ins || continue
        seq = C.chains[i]
        cross = any(v -> any(k -> !(k in seq) && !isramp[k], view(adj, off[v]:off[v+1]-1)), C.path[i][2:end-1])
        if other[C.i0[i]] == 0 || cross
            inside[i] = false; gone[seq] .= false
        end
    end
    C = merge(C, (; inside))
    img, rule = _collapse(T, N, J, isramp, C, gone, off, adj)
    # the pair's other side, per accepted pair: its signs, flag, class and time; the kept side's length
    np = length(C.pairs)
    osign = [String[] for _ in 1:np]; oflag = falses(np); ocls = zeros(Int, np); otime = zeros(np); klen = zeros(np)
    for q in 1:np
        C.accept[q] || continue
        d = C.chains[C.drop[q]]
        osign[q] = unique!([s for s in (_signtext(L.SIGN[k]) for k in d) if s !== nothing])
        oflag[q] = any(k -> _isinterstate(L.SIGN[k], L.NAME[k], L.FCLASS[k]), d)
        ocls[q] = C.cls[C.drop[q]]
        otime[q] = sum(_traveltime(L, k) for k in d)
        klen[q] = C.len[C.keep[q]]
    end
    # the links, before duplicates
    a = zeros(Int, nL); b = zeros(Int, nL); dirc = zeros(Int, nL); alive = falses(nL)
    for k in 1:nL
        gone[k] && continue
        a[k], b[k] = img[T.S[k]], img[T.D[k]]
        a[k] == b[k] && continue
        alive[k] = true
        d = role[k] > 0 ? 0 : L.DIR[k]
        dirc[k] = d == 0 ? 0 : ((d == 1) == (a[k] < b[k]) ? 1 : -1)
    end
    # duplicates: one pair of nodes, one route, the same directions; the shortest stays (ties to the first)
    best = Dict{NTuple{4,Int},Int}()
    for k in 1:nL
        alive[k] || continue
        key = (min(a[k], b[k]), max(a[k], b[k]), rid[k], dirc[k])
        k0 = get(best, key, 0)
        if k0 == 0
            best[key] = k
        elseif L.DIST[k] < L.DIST[k0]
            alive[k0] = false; best[key] = k
        else
            alive[k] = false
        end
    end
    ks = findall(alive)
    sort!(ks, by = k -> (N.IDX[a[k]], N.IDX[b[k]], k))
    n = length(ks)
    SIGN = Vector{Union{Missing,String}}(missing, n); TYPE = Vector{Union{Missing,String}}(missing, n)
    INTERSTATE = falses(n); FCLASS = zeros(Int, n); DIR = zeros(Int, n); AB = zeros(n); BA = zeros(n)
    DIST = zeros(n); STUB = zeros(n)
    for (r, k) in enumerate(ks)
        q = abs(role[k])
        s = _signtext(L.SIGN[k])
        sg = s === nothing ? String[] : [s]
        fl = _isinterstate(L.SIGN[k], L.NAME[k], L.FCLASS[k])
        if q > 0
            sg = sort!(unique!([sg; osign[q]]))
            fl |= oflag[q]
            FCLASS[r] = min(L.FCLASS[k], ocls[q])
            rev = klen[q] > 0 ? otime[q] * L.DIST[k] / klen[q] : otime[q] / length(C.chains[C.keep[q]])
            AB[r], BA[r] = L.DIR[k] == -1 ? (rev, L.BA_TIME[k]) : (L.AB_TIME[k], rev)
        else
            FCLASS[r] = L.FCLASS[k]; DIR[r] = L.DIR[k]; AB[r] = L.AB_TIME[k]; BA[r] = L.BA_TIME[k]
        end
        isempty(sg) || (SIGN[r] = join(sg, ";"))
        INTERSTATE[r] = fl
        TYPE[r] = _roadtype(sg, L.NAME[k], fl)
        st = (a[k] == T.S[k] ? 0.0 : _dmi(T, T.S[k], a[k])) + (b[k] == T.D[k] ? 0.0 : _dmi(T, T.D[k], b[k]))
        d0 = Float64(L.DIST[k])
        if d0 > 0
            f = (d0 + st) / d0; AB[r] *= f; BA[r] *= f
        else
            L.AB_SPEED[k] > 0 && (AB[r] += 60st / L.AB_SPEED[k])
            L.BA_SPEED[k] > 0 && (BA[r] += 60st / L.BA_SPEED[k])
        end
        DIST[r] = d0 + st; STUB[r] = st
    end
    nm = Union{Missing,String}[ismissing(x) ? missing : String(x) for x in L.NAME[ks]]
    links = DataFrame(SRC = N.IDX[a[ks]], DST = N.IDX[b[ks]], DIST = round.(DIST, digits = 4), SPEED = L.SPEED[ks],
                      FCLASS = FCLASS, DIR = DIR, NAME = nm, SOURCE = fill("FAF5", n), SIGN = SIGN, TYPE = TYPE,
                      INTERSTATE = Vector{Bool}(INTERSTATE), AB_TIME = round.(AB, digits = 4), BA_TIME = round.(BA, digits = 4),
                      STFIP = L.STFIP[ks], COFIP = L.COFIP[ks], URBAN = L.URBAN[ks])
    used = falses(T.nN)
    for k in ks
        used[a[k]] = used[b[k]] = true
    end
    vs = sort!(findall(used), by = v -> N.IDX[v])
    nodes = DataFrame(IDX = N.IDX[vs], LON = Float64.(N.LON[vs]), LAT = Float64.(N.LAT[vs]), SOURCE = fill("FAF5", length(vs)))
    # RN19: a node whose FAF5 component keeps no derived link maps to no node
    fcomp, nfc = _components(T, trues(nL))
    kept = falses(nfc)
    for k in ks
        kept[fcomp[T.S[k]]] = true
    end
    order = sortperm(N.IDX)
    nodemap = DataFrame(FAF5_IDX = N.IDX[order],
                        IDX = Union{Missing,Int}[fcomp[v] > 0 && kept[fcomp[v]] ? N.IDX[img[v]] : missing for v in order])
    info = (; isramp, J, T, rid, rkey, C, inside0, role, gone, img, rule, ks, a, b, stub = STUB, fdist = Float64.(L.DIST[ks]),
            fcomp)
    return (; nodes, links, nodemap, info)
end

# ---------------------------------------------------------------------------------------------------------------------
# The shipped files and their accessors (PCV N3, his rulings RD1 and RD2, D7, D11)
# ---------------------------------------------------------------------------------------------------------------------

# How the three files are written (tools/v0_3_1/make_faf5net.jl, and the regenerated extract of the tests), the same
# bytes from run to run, on Julia 1.12 and 1.13: a missing value an empty field; DIST and the times, which the derivation
# has rounded to 4 decimals, with exactly 4; any other number in its shortest form that reads back as the same value;
# text quoted when it holds a comma, a quote or a line break; LF line endings.
const _FAF5NET_FOUR = ("DIST", "AB_TIME", "BA_TIME")

# A value already rounded to 4 decimals, written with exactly 4, as C's "%.4f" writes it.
function _fixed4(x::Real)
    k = round(Int, Float64(x) * 10_000)
    neg = k < 0 || (k == 0 && signbit(x))
    k = abs(k)
    return string(neg ? "-" : "", k ÷ 10_000, '.', lpad(k % 10_000, 4, '0'))
end

function _csvfield(col, x, four)
    ismissing(x) && return ""
    x isa Bool && return x ? "true" : "false"
    x isa Integer && return string(x)
    x isa AbstractFloat && return col in four ? _fixed4(x) : string(Float64(x))
    s = string(x)
    return occursin(r"[,\"\r\n]", s) ? "\"" * replace(s, "\"" => "\"\"") * "\"" : s
end

"""
    _faf5net_csv(io_or_path, df; four = ("DIST", "AB_TIME", "BA_TIME"))

Writes `df` as CSV the way the derived network's files are written: a header line, then one line per row, LF endings;
a missing value as an empty field; the columns named in `four` with exactly 4 decimals (their values already rounded
to 4); every other number in its shortest form that reads back as the same value; text quoted when it holds a comma,
a quote or a line break. `four = ()` writes every number exactly (the tests' FAF5 extract).
"""
function _faf5net_csv(io::IO, df; four = _FAF5NET_FOUR)
    cols = names(df)
    write(io, join(cols, ','), '\n')
    for r in 1:nrow(df)
        write(io, join((_csvfield(c, df[r, c], four) for c in cols), ','), '\n')
    end
    return nothing
end
_faf5net_csv(path::AbstractString, df; kw...) = open(io -> _faf5net_csv(io, df; kw...), path, "w")

# Each file's columns and their types as the derivation makes them (D11), read back as the same table.
const _USRD_NODE_TYPES = ["IDX" => Int, "LON" => Float64, "LAT" => Float64, "SOURCE" => String]
const _USRD_LINK_TYPES = ["SRC" => Int, "DST" => Int, "DIST" => Float64, "SPEED" => Int, "FCLASS" => Int, "DIR" => Int,
                          "NAME" => Union{Missing,String}, "SOURCE" => String, "SIGN" => Union{Missing,String},
                          "TYPE" => Union{Missing,String}, "INTERSTATE" => Bool, "AB_TIME" => Float64,
                          "BA_TIME" => Float64, "STFIP" => Int, "COFIP" => Int, "URBAN" => Union{Missing,Int}]
const _USRD_NODEMAP_TYPES = ["FAF5_IDX" => Int, "IDX" => Union{Missing,Int}]

# Read once per session from the `faf5net` artifact (lazy: downloaded on first use) and kept here, as the FAF5 tables
# are (C12); each accessor returns a copy, so a caller may change what it gets without changing what the next call
# gets. The lock is for tasks that call at once.
const _usrdnode_cache = Ref{Union{Nothing,DataFrame}}(nothing)
const _usrdlink_cache = Ref{Union{Nothing,DataFrame}}(nothing)
const _usrdnodemap_cache = Ref{Union{Nothing,DataFrame}}(nothing)
const _usrd_lock = ReentrantLock()

_usrdread(file, spec) = CSV.read(joinpath(artifact"faf5net", file), DataFrame; types = Dict{String,Type}(spec),
                                 stringtype = String, pool = false)

function _usrdcached(cache, file, spec)
    return lock(_usrd_lock) do
        isnothing(cache[]) && (cache[] = _usrdread(file, spec))
        cache[]
    end
end

_usrdnodes() = _usrdcached(_usrdnode_cache, "faf5net_nodes.csv", _USRD_NODE_TYPES)
_usrdlinks() = _usrdcached(_usrdlink_cache, "faf5net_links.csv", _USRD_LINK_TYPES)

# The limits of a `region`: `:CUS`, the continental U.S. as `makemap` names it (`CUS_LIMITS`).
function _usrdlimits(region)
    region === :CUS && return CUS_LIMITS
    throw(ArgumentError("region must be :CUS (the continental U.S., CUS_LIMITS) or nothing (the whole network); got $(repr(region))"))
end

# The classes `fclass` names: one integer or a collection of them.
function _usrdclasses(fclass)
    fclass isa Integer && return Set{Int}([fclass])
    ok = !(fclass isa AbstractString) && applicable(iterate, fclass) && all(x -> x isa Integer, fclass)
    ok || throw(ArgumentError("fclass must be an integer or a collection of integers (such as 1:3); got $(repr(fclass))"))
    return Set{Int}(fclass)
end

# The links of `L` (the derived network's link table, its nodes `N`) the keywords keep (RD2): the Interstates
# (`INTERSTATE`), the classes `fclass`, the links with both ends inside the region's limits; every one given.
function _usrdkeep(N, L, interstate::Bool, fclass, region)
    keep = trues(nrow(L))
    interstate && (keep .&= L.INTERSTATE)
    if fclass !== nothing
        cs = _usrdclasses(fclass)
        keep .&= in.(L.FCLASS, Ref(cs))
    end
    if region !== nothing
        (x0, x1), (y0, y1) = _usrdlimits(region)
        inside = Set{Int}(N.IDX[(x0 .<= N.LON .<= x1) .& (y0 .<= N.LAT .<= y1)])
        keep .&= in.(L.SRC, Ref(inside)) .& in.(L.DST, Ref(inside))
    end
    return keep
end

_usrdany(interstate, fclass, region) = interstate || fclass !== nothing || region !== nothing

"""
    usrdlink(; interstate = false, fclass = nothing, region = nothing) -> DataFrame

Returns the links of Logjam's U.S. road network, derived from FAF5 (`faf5nodes`, `faf5links`, which stay as FAF5
publishes them) for long-distance routing and map backgrounds. Each stretch of road between two junctions is one link;
the two carriageways of a divided road are one two-way link, and a road that is genuinely one-way stays one-way; each
interchange and each divided-highway intersection is one node, and its ramps are gone; the nodes along each road are
kept, so it follows the road's course. The network is made by `tools/v0_3_1/make_faf5net.jl` and ships as a lazy
artifact, downloaded on first use. The file is read once per session and each call returns a copy, so the table may
be changed freely.

# Keywords
- `interstate`: `true` keeps only the Interstate links (`INTERSTATE`).
- `fclass`: one functional class or a collection of them (such as `1:3`) keeps only the links of those classes.
- `region`: `:CUS`, the continental U.S. as `makemap` names it (`CUS_LIMITS`), keeps only the links with both ends
  inside it; `nothing` (default) keeps the whole network, Alaska, Hawaii and Puerto Rico included.

A link is kept when it meets every keyword given. `usrdnode` with the same keywords returns the nodes the kept links
use, so the two tables are one network.

# Columns
The first eight are `osm_roads`' columns, in its order, so the two tables can be stacked with `vcat`.
- `SRC`, `DST`: the link's two nodes (`IDX` of `usrdnode`, FAF5's node numbers).
- `DIST`: miles. A divided road's is its shorter carriageway's; a link whose end was moved to its junction's node adds
  the straight-line distance moved.
- `SPEED`: FAF5's posted speed limit (mph).
- `FCLASS`: FAF5's functional class (1 Interstate, 2 other freeway or expressway, 3 other principal arterial, and so
  on), the lower of a divided road's two carriageways.
- `DIR`: 0 two-way, 1 one-way from `SRC` to `DST`, -1 one-way from `DST` to `SRC`.
- `NAME`: FAF5's road name (`missing` where it has none).
- `SOURCE`: `"FAF5"`.
- `SIGN`: the routes the road is signed as, sorted and joined by `;` (`missing` where it has none).
- `TYPE`: Matlog's road type: `"I"` an Interstate, `"U"` a U.S. route, `"S"` a state route, `"L"` a road with a name
  and no route, `missing` otherwise.
- `INTERSTATE`: `true` for an Interstate, Business routes excepted.
- `AB_TIME`, `BA_TIME`: free-flow minutes from `SRC` to `DST` and from `DST` to `SRC`, a divided road's from each of
  its carriageways; `links2graph(L; weight = :time)` reads them.
- `STFIP`, `COFIP`: state and county FIPS codes.
- `URBAN`: FAF5's urban area code (`missing` outside one).

# Sources
Derived from U.S. Department of Transportation, Bureau of Transportation Statistics, Freight Analysis Framework (FAF5)
Network (see `faf5links`).

# Example
```julia
L = usrdlink(interstate = true, region = :CUS)     # the Interstates of the lower 48
sum(L.DIST)                                        # their miles
N, L = prune_reindex(usrdnode(fclass = 1:3), usrdlink(fclass = 1:3))
g = links2graph(L; weight = :time)                 # minutes, each direction its own
```
"""
function usrdlink(; interstate::Bool = false, fclass = nothing, region = nothing)
    L = _usrdlinks()
    _usrdany(interstate, fclass, region) || return copy(L)
    return L[_usrdkeep(_usrdnodes(), L, interstate, fclass, region), :]
end

"""
    usrdnode(; interstate = false, fclass = nothing, region = nothing) -> DataFrame

Returns the nodes of Logjam's U.S. road network, derived from FAF5 (see `usrdlink`): with no keywords, every node;
with keywords, exactly the nodes the links `usrdlink` keeps with the same keywords use, so the two tables are one
network. The file is read once per session and each call returns a copy, so the table may be changed freely.

# Keywords
As `usrdlink`: `interstate = true` the Interstates, `fclass` one functional class or a collection of them, `region =
:CUS` the continental U.S. (`CUS_LIMITS`).

# Columns
- `IDX`: integer node identifier, FAF5's own node number (as in `faf5nodes`), so the numbers are not consecutive.
- `LON`: longitude of the node (FAF5's).
- `LAT`: latitude of the node (FAF5's).
- `SOURCE`: `"FAF5"`.

# Example
Lecture 4.1's Interstate network of the lower 48, then thinned:

```julia
N = usrdnode(interstate = true, region = :CUS)
L = usrdlink(interstate = true, region = :CUS)
tN, tL = thin(N, L)          # numbered from 1, ready for links2graph
```
"""
function usrdnode(; interstate::Bool = false, fclass = nothing, region = nothing)
    N = _usrdnodes()
    _usrdany(interstate, fclass, region) || return copy(N)
    L = _usrdlinks()
    keep = _usrdkeep(N, L, interstate, fclass, region)
    used = Set{Int}(view(L.SRC, keep)); union!(used, view(L.DST, keep))
    return N[in.(N.IDX, Ref(used)), :]
end

"""
    usrdnodemap() -> DataFrame

Returns the node map of Logjam's U.S. road network (`usrdnode`, `usrdlink`): one row for every FAF5 node
(`faf5nodes`), with the node of the network that stands for it. A node the network keeps maps to itself; each node of
an interchange or a divided-highway intersection maps to that junction's one node; a node of a dropped carriageway maps
to the nearest node of the carriageway kept in its place; a node that only ramps touch maps to the nearest kept node
its ramps reach. The 310 nodes of FAF5's 145 connected pieces made only of ramps keep no link, and their `IDX` is
`missing`. The file is read once per session and each call returns a copy.

# Columns
- `FAF5_IDX`: the FAF5 node (`IDX` of `faf5nodes`), each once, in increasing order.
- `IDX`: the node of `usrdnode` that stands for it, or `missing`.

# Example
```julia
M = usrdnodemap()
nrow(M) == nrow(faf5nodes())          # true: every FAF5 node, once
count(ismissing, M.IDX)               # 310: the nodes of FAF5's pieces made only of ramps
img = Dict(zip(M.FAF5_IDX, M.IDX))    # a FAF5 node's derived node, by its IDX
```
"""
usrdnodemap() = copy(_usrdcached(_usrdnodemap_cache, "faf5net_nodemap.csv", _USRD_NODEMAP_TYPES))
