# faf5net.jl -- the derived FAF5 road network (CR 19), part one: what route a link carries, which links are
# Interstates, and what a ramp is (PCV N1). Internal: nothing here is exported or public. The derivation
# (tools/v0_3_2/make_faf5net.jl, N2) builds on these functions, and from N4 the map's road layer reads the same ramp
# rule, so the derivation and the map agree on what a ramp is. Until then the map keeps v0.3.0's rule
# (ext/LogjamMapExt.jl), which is the first part of the one here.
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
# A direction letter ends some SIGNs ("I 93 N" and "I 93 S", the two carriageways of one road); in "MO N" the letter is
# the route itself, so a direction follows a token with a digit. A designating NAME may end in NB, SB, EB or WB.
const _SIGN_DIR = r"^(.*\d\S*) [NSEW]$"
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
unified ("FL 429" and "SR 429" are both "SR 429"), a direction letter is dropped ("I 93 N" and "I 93 S" are both
"I 93"; "I 496 EB" is "I 496"), and a Business route stays its own route ("I 40 B" is not "I 40"). A NAME that is not
a route designation is the key as written, in upper case. A link with neither SIGN nor NAME carries no route
(`nothing`).
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
    return _unifyprefix(replace(n, _NAME_DIR => ""))
end

# ---------------------------------------------------------------------------------------------------------------------
# The Interstate flag
# ---------------------------------------------------------------------------------------------------------------------

# Exactly an Interstate designation: "I", a number, an optional letter (35E, 69C) and an optional direction letter;
# a NAME may write "INTERSTATE" or a hyphen and end in a two-letter direction. Never a Business route ("I 40 B").
const _I_SIGN = r"^I \d+[A-Z]?(?: [NSEW])?$"
const _I_NAME = r"^(?:I|INTERSTATE)[ -]?\d+[A-Z]?(?: [NSEW]B?)?$"
const _BUSINESS_SIGN = r" (?:B|BUS|BUSINESS)(?: [NSEW]B?)?$"

"""
    _isinterstate(sign, name, fclass) -> Bool

Whether a FAF5 link is an Interstate (his ruling RN3, 2026-11-22): its SIGN is exactly an Interstate designation ("I",
a number, an optional letter suffix as in 35E, an optional direction letter), or, on a class 1 link, its NAME is.
Never a Business route. I-296 in Grand Rapids, signed US 131 and named "I 296", is found by its NAME.
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
# "COLLECTOR/DISTRBUTOR", "COLLECTION/DISTRIBUTION"); "DOWNTOWN DISTRIBUTOR" is a road. And a system ramp named
# "X TO Y" where both sides are route designations ("I 96 EB TO I 696 EB", "I 15 SB TO I 515 / US 95 NB");
# "GOING TO THE SUN HWY" is a road.
const _CD_ANY_SPELLING = r"COLLE\w*\s*/\s*DIST\w*"
const _DESIG_TOKEN = "(?:I|US|CR|FM|M|SR|" * join(_STATE_CODES, "|") * ")[ -]?\\d+[A-Z]?(?: B| BUS)?" *
                     "(?: (?:[NSEW]B?|IL|OL))?"
const _DESIG_LIST = "/?$_DESIG_TOKEN(?: ?/ ?$_DESIG_TOKEN)*"
const _TO_RAMP = Regex("^$_DESIG_LIST TO $_DESIG_LIST\$")

# The three parts of the name rule, each on its own so the counts of each can be reported.
_isramp_v030(name) = !ismissing(name) && occursin(_RAMP_WORDS, uppercase(string(name)))
_isramp_cd(name) = (n = _keytext(name); n !== nothing && occursin(_CD_ANY_SPELLING, n))
_isramp_to(name) = (n = _keytext(name); n !== nothing && occursin(_TO_RAMP, n))

"""
    _isramp_name(name) -> Bool

Whether a FAF5 link's NAME marks a ramp (his ruling RN4, 2026-11-22): v0.3.0's rule (a ramp, a collector-distributor
lane, a turn lane), a collector-distributor lane however it is spelled, or "X TO Y" where both sides are route
designations. CONNECTOR names are roads; a missing name is not a ramp by name (`_ramp_links` adds the structural test).
"""
_isramp_name(name) = _isramp_v030(name) || _isramp_cd(name) || _isramp_to(name)

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

Whether each link of `L` is a ramp (his ruling RN4, 2026-11-22): its NAME marks one (`_isramp_name`), or it passes the
structural test, applied by cluster. Unnamed one-way links (no SIGN and no NAME, any class) form clusters with the
named ramps they touch; a cluster whose links lie within 0.75 mi of each other (the largest distance between two of
its nodes) and that touches two or more routes (`_route`), at least one of them on a class 1 or 2 link, makes its
unnamed links ramps. The test never reaches a named link.
"""
function _ramp_links(N, L)
    T = _topology(N, L)
    named = [_isramp_name(x) for x in L.NAME]
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
