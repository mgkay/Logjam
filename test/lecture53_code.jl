# lecture53_code.jl -- Lecture 5.3's own route cost, as its code blocks define it, kept as text so a test
# can evaluate it in a scratch module AFTER `using Logjam` (principle 9, D10: a name Logjam newly exports
# must not break the lecture that defines it, in the order the lecture runs it; PCV K7b).
#
# The text is 5-routing/5-rte-3.qmd's: Code block 15 (`rte2ldmx`, `rteTC_vrp` for a route and for a vector
# of routes, :1062-1131) and Code block 28 (`scanTW`, :1817-1833). Only the block-title comment lines are
# dropped. Julia, not Logjam, owns every name below, so the test runs the definitions after `using Logjam`
# and compares what they return with what Logjam's exports return.

const LECTURE53_CODE = raw"""
function rte2ldmx(rte)  # the shipments on board at each load mix
    isL, on, ld = isorigin(rte), Int[], Vector{Int}[]
    for i in 1:length(rte)-1
        isL[i] ? push!(on, rte[i]) : filter!(!=(rte[i]), on)
        isL[i] && !isL[i+1] && push!(ld, copy(on))  # a load mix
    end
    return ld
end

function rteTC_vrp(rte::AbstractVector{<:Integer}, sh, C, tr = (;))
    has(f) = hasproperty(sh, f)                 # a column of sh?
    col(f, v) = has(f) ? float.(sh[rte, f]) : fill(v, length(rte))
    isL, istr = isorigin(rte), haskey(tr, :b)   # truck's b and e?
    loc = rte2loc(rte, sh, istr ? tr : (b = [], e = []))
    Xflg = 1
    if istr && tr.b == tr.e        # back at the truck's location early:
        k = filter(!=(0), diff(loc[2:end-1] .== tr.b))  # two routes
        (length(k) > 2 || length(k) == 2 && k != [-1, 1]) && (Xflg = -1)
    end
    if Xflg > 0 && has(:q)                      # each load mix's
        for ld in rte2ldmx(rte)                 # weight and cube
            if haskey(tr, :Kwt) && sum(sh.q[ld]) > tr.Kwt
                Xflg = -2; break
            elseif haskey(tr, :Kcu) && 2000sum(sh.q[ld] ./ sh.s[ld]) >
                   tr.Kcu + 0.01sqrt(eps())     # a rounding tolerance
                Xflg = -3; break
            end
        end
    end
    Xflg < 0 && return Inf, Xflg, DataFrame()
    t = [k == 1 || loc[k] == loc[k-1] ? zero(eltype(C)) :
         C[loc[k-1], loc[k]] for k in eachindex(loc)]  # same place: 0
    tLU = ifelse.(isL, col(:tL, 0.0), col(:tU, 0.0))  # load, unload
    istr && (tLU = [0; tLU; 0])
    TC = foldl(+, t) + foldl(+, tLU)    # added in order, left to right
    haskey(tr, :maxTC) && TC > tr.maxTC && return Inf, -4, DataFrame()
    R = istr ? [0; rte; 0] : rte
    tw = (:tbmin, :tbmax, :temin, :temax)
    if !any(f -> has(f) || haskey(tr, f), tw)
        out = DataFrame(Rte = R, Loc = loc, Cost = t)  # no windows
        (has(:tL) || has(:tU)) && (out.LU = tLU)
        return TC, Xflg, out
    end
    lo = ifelse.(isL, col(:tbmin, -Inf), col(:temin, -Inf))  # windows
    hi = ifelse.(isL, col(:tbmax, Inf), col(:temax, Inf))
    if istr              # the truck's, also at stops at its b and its e
        lo = [get(tr, :tbmin, -Inf); lo; get(tr, :temin, -Inf)]
        hi = [get(tr, :tbmax, Inf); hi; get(tr, :temax, Inf)]
        c = [1; findall(diff(loc) .!= 0) .+ 1]  # where location changes
        n = length(loc)
        for (ix, j) in ((2:c[2]-1, 1), (c[end]:n-1, n))  # stops at b, e
            lo[ix] = replace(lo[ix], -Inf => lo[j])
            hi[ix] = replace(hi[ix], Inf => hi[j])
        end
    end
    TC, _, _, s = scanTW(t, tLU, lo, hi)        # Sec. 2's scan, its c
    isinf(TC) && return Inf, -5, DataFrame()
    isnan(TC) && (TC = sum(t) + sum(tLU))       # no window at all
    # the waits, from the schedule, none below 0 from rounding
    w = max.(0, [0; s[2:end] - s[1:end-1] - tLU[1:end-1] - t[2:end]])
    out = DataFrame(Rte = R, Loc = loc, Cost = t,
        Arrive = [0; s[2:end] - w[2:end]], Wait = w, TWmin = lo,
        Start = s, LU = tLU, Depart = s + tLU, TWmax = hi,
        Total = t + w + tLU)
    return TC, Xflg, out
end
function rteTC_vrp(R::AbstractVector{<:AbstractVector}, sh, C, tr = (;))
    v = [rteTC_vrp(r, sh, C, tr) for r in R]    # each route of R
    return first.(v), getindex.(v, 2), last.(v)
end

function scanTW(t, u, ℓ, h)  # time-window scans: route time, a, b, c
    n = length(t)
    a = zeros(n); a[1] = ℓ[1]            # forward: the earliest start
    for k in 2:n
        a[k] = max(a[k-1] + u[k-1] + t[k], ℓ[k])  # wait if early
        a[k] + u[k] > h[k] && return Inf, a, a, a  # its window closed
    end
    b = zeros(n); b[n] = a[n]            # reverse: the latest start
    for k in n-1:-1:1
        b[k] = min(b[k+1] - t[k+1] - u[k], h[k] - u[k])
    end
    c = zeros(n); c[1] = b[1]            # forward again: the schedule
    for k in 2:n
        c[k] = max(c[k-1] + u[k-1] + t[k], ℓ[k])  # waits made late
    end
    return a[n] + u[n] - b[1], a, b, c   # earliest finish less start
end
"""

# a scratch module that does what the lecture does: `using Logjam`, then the definitions in the order the
# lecture runs them (rte2ldmx and rteTC_vrp at Code block 15, scanTW at Code block 28). Returns the module;
# call its functions with `lecture53_call` (new world age). `scanfirst = true` defines `scanTW` before
# `rteTC_vrp`, the order of HW 5's own definitions.
function lecture53_module(name::Symbol; with = ("using Logjam", "using DataFrames"), scanfirst = false)
    m = Module(name)
    for u in with
        Core.eval(m, Meta.parse(u))
    end
    exs = [ex for ex in Meta.parseall(LECTURE53_CODE).args if !(ex isa LineNumberNode)]
    scanfirst && (exs = vcat(exs[end], exs[1:end-1]))      # scanTW is the last definition of the text
    for ex in exs
        Core.eval(m, ex)
    end
    return m
end
lecture53_call(m::Module, f::Symbol, args...; kw...) = Base.invokelatest(getfield(m, f), args...; kw...)
