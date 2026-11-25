# Helpers of test_oracles.jl (PCV K2b), kept in their own file so a scratch script can load them without
# running the tests. Names start with `_o` or `_` and are defined at top level of whatever includes this.

using Logjam
using DataFrames
using SparseArrays

const ORACLE_DIR = joinpath(@__DIR__, "oracles")

# reading a case file: "@name,nrows,ncols" blocks of comma-separated numbers; "#" lines are comments
function _readoracle(name)
    d = Dict{String,Matrix{Float64}}()
    lines = readlines(joinpath(ORACLE_DIR, name * ".csv"))
    i = 1
    while i <= length(lines)
        l = lines[i]
        if startswith(l, "@")
            nm, r, c = split(l[2:end], ',')
            r, c = parse(Int, r), parse(Int, c)
            M = Matrix{Float64}(undef, r, c)
            for a in 1:r
                M[a, :] = parse.(Float64, split(lines[i + a], ','))
            end
            d[String(nm)] = M
            i += r + 1
        else
            i += 1
        end
    end
    return d
end
_ivec(d, k) = Int.(vec(d[k]))
_fvec(d, k) = vec(d[k])
_sc(d, k) = d[k][1, 1]
_cells(d, nm) = [_ivec(d, "$(nm)_$i") for i in 1:Int(_sc(d, nm * "_n"))]

# The named tolerance (charge SC 4) for a great-circle number in miles or kilometers against Matlog's: Logjam's
# dgc keeps the sphere (3958.75 mi; DST1, DST2) where Matlog's dists uses a latitude-dependent radius, a
# difference below relative 1e-3 at the course's latitudes (N15 measured 0.08% to 0.085%). The same constant,
# with the same value, is defined in test_disttools.jl.
const GC_RADIUS_RTOL = 1e-3

# relative 1e-9 (test spec rule 4); atol only floors comparisons with an exact zero
function _oclose(a, b; rtol = 1e-9)
    a, b = vec(collect(a)), vec(collect(b))
    return length(a) == length(b) && all(isapprox.(a, b; rtol = rtol, atol = 1e-12))
end
# a missing method or keyword is a failed comparison, not an error, for the not-yet-built interfaces
_try(f) = try f() catch; false end
_has(s::Symbol) = isdefined(Logjam, s)
_oquiet(f) = redirect_stdout(f, devnull)

# Transport. sh is a NamedTuple (the unified sh/tr contract of transtools.jl), tr = (r, Kwt, Kcu, ppi).
_tr(r, Kwt, Kcu, ppi) = (r = r, Kwt = Kwt, Kcu = Kcu, ppi = ppi)
# Matlog's transcharge(q, sh, tr, ppiLTL): the cheaper of the two modes, and whether LTL is it; zero at q = 0
function _transcharge(q, sh, tr, ppiLTL)
    q == 0 && return (0.0, false)
    cTL = charge_tl(q, sh, tr)
    cLTL = charge_ltl(q, sh; ppi = ppiLTL)
    return cLTL < cTL ? (cLTL, true) : (cTL, false)
end
