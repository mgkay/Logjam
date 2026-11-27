# test_routing_v031.jl -- added by PCV WP6 of Logjam v0.3.1 (E2): the `verbose` keyword of `twoopt` and
# `mincostinsert`, Matlog's `dodisp` (refactor E, R2). Test spec Sec. 7, with the WP6 brief's correction: Matlog's
# `twoopt.m` and `mincostinsert.m` are not the oracle for the traces, since v0.3.0 ruled that Logjam's insertion
# follows the F24 loop (CR 38) and its 2-opt the lecture's (K7a), so Matlog's traces differ by design. The oracle
# is each lecture's own printing definition, copied below as text with its `.qmd` lines cited and run on the
# lecture's inputs with `stdout` captured. Equality is `==`, on the captured strings (byte for byte) and on the
# returned values; no tolerance is used anywhere in this file. The evidence:
#   1. Lecture 5.1, Code block 15 (`twoopt_prt`) on Ex. 3's tour and arc costs (Code blocks 12 to 14): its 20 lines
#      against `twoopt(π, πTCh; verbose = true)`, the call of Code block 16 with the keyword, and against
#      `twoopt(π, D; verbose = true)`, the matrix method;
#   2. Lecture 5.2, Code block 17 (`mincostinsert_prt`) on Ex. 1's costs (Code blocks 2 and 16): each insertion's
#      lines (4 and 13) against `mincostinsert(...; verbose = true)`, and the whole cell's 21 lines against the
#      same cell with Logjam's call in the place of the lecture's;
#   3. the two definitions against Logjam's on seeded random tours, matrices and routes; the route 2-opt's trace
#      against the routes Lecture 5.2's `twoopt_rte` (test/lecture52_code.jl) costs, in order; the methods for a
#      vector of routes against each route's own trace;
#   4. `verbose = false`, the default: nothing printed, and every public method and kernel `==` to v0.3.0's
#      bodies, copied below as text, on every input above.
# The routing doctests (DOC: every example of src/routetools.jl a `jldoctest`) run in test_doctests.jl.

using Test
using Logjam
using DataFrames
using Random

@isdefined(LECTURE52_CODE) || include(joinpath(@__DIR__, "lecture52_code.jl"))

# ---- v0.3.0's 2-opt and insertion, verbatim (src/routetools.jl at the v0.3.0 tag fd0f1f3, which e1f745b left
# unchanged: twoopt :747-750, _twoopt :753, _twoopt_out :757-760, the methods for a vector of routes :852-859,
# _twoopt_route :872-890, _twoopt_tour :893-915, twoopt(π, C) :956-990, mincostinsert :1045-1048, _mincostinsert
# :1051-1066). The helpers they call are Logjam's own, unchanged since that tag. The reference for "returns
# exactly what it returned": each is compared with the current function by `==`. ----
module RtV030
using Logjam: segcost, _loaded_throughout, _isroutevec, _order_ties, _narrow

function twoopt(r, rTCh)
    rte, TC = _twoopt_out(r, rTCh)
    return (rte = rte, TC = TC)
end

_twoopt(r, rTCh) = _isroutevec(r) ? _twoopt_route(r, rTCh) : _twoopt_tour(r, rTCh)

function _twoopt_out(r, rTCh)
    rte, TC = _twoopt(r, rTCh)
    return (_isroutevec(r) ? _order_ties(rte, rTCh) : rte), TC
end

function twoopt(R::AbstractVector{<:AbstractVector{<:Integer}}, rTCh)
    res = [_twoopt_out(r, rTCh) for r in R]
    return (rte = map(first, res), TC = _narrow(map(x -> x[2], res)))
end
function twoopt(R::AbstractVector{<:AbstractVector{<:Integer}}, C::AbstractMatrix)
    res = [twoopt(π, C) for π in R]
    return (rte = map(first, res), TC = _narrow(map(x -> x[2], res)))
end

function _twoopt_route(r, rTCh)
    m = length(r)
    rᵒ, TCᵒ = copy(r), rTCh(r)
    done = false
    while !done
        done = true
        for i = 1:m-1, j = i+1:m
            r′ = vcat(rᵒ[1:i-1], reverse(rᵒ[i:j]), rᵒ[j+1:end])
            _loaded_throughout(r′) || continue
            TC = rTCh(r′)
            if TC < TCᵒ
                rᵒ, TCᵒ = r′, TC
                done = false
                break
            end
        end
    end
    return rᵒ, TCᵒ
end

function _twoopt_tour(r, rTCh)
    rᵒ, TCᵒ = copy(r), rTCh(r)
    done = false
    while !done
        done = true
        for i = 1:length(r)-2
            for j = i+2:min(length(r)-1, length(r)+i-3)
                r′ = vcat(r[1:i], reverse(r[i+1:j]), r[j+1:end])
                TC = rTCh(r′)
                if TC < TCᵒ
                    rᵒ, TCᵒ = r′, TC
                    done = false
                    break
                end
            end
            if done == false
                break
            end
        end
        r = copy(rᵒ)
    end
    return rᵒ, TCᵒ
end

function twoopt(π::AbstractVector, C::AbstractMatrix)
    _isroutevec(π) && throw(ArgumentError(
        "twoopt(π, C) takes a closed tour; a route vector's cost is not a sum of arc costs, so use twoopt(r, rTCh)"))
    n = length(π)
    πᵒ = collect(π)
    sym = all(C[i, j] == C[j, i] for j in axes(C, 2) for i in 1:j)
    F = zeros(n)                  # F[k + 1]: cost of the forward arcs 1..k; B[k + 1] the backward ones
    B = zeros(n)
    done = false
    while !done
        done = true
        if !sym
            for k in 1:n-1
                F[k+1] = F[k] + C[πᵒ[k], πᵒ[k+1]]
                B[k+1] = B[k] + C[πᵒ[k+1], πᵒ[k]]
            end
        end
        for i = 1:n-2
            for j = i+2:min(n-1, n+i-3)
                a, b, c, d = πᵒ[i], πᵒ[i+1], πᵒ[j], πᵒ[j+1]
                Δ = C[a, c] + C[b, d] - C[a, b] - C[c, d]
                if !sym             # the stretch's arcs i+1 .. j-1 run the other way
                    Δ += (B[j] - B[i+1]) - (F[j] - F[i+1])
                end
                if Δ < 0
                    reverse!(πᵒ, i + 1, j)
                    done = false
                    break
                end
            end
            done || break
        end
    end
    return (rte = πᵒ, TC = sum(segcost(πᵒ, C)))
end

function mincostinsert(idx, rte::AbstractVector, rteTCh)
    rte′, TC = _mincostinsert(idx, rte, rteTCh)
    return (rte = _order_ties(rte′, rteTCh), TC = TC)
end

function _mincostinsert(idx, rte, rteTCh)
    if isempty(rte)
        return [idx, idx], rteTCh([idx, idx])
    end
    rteᵒ, TCᵒ = copy(rte), Inf
    for i = 1:length(rte)
        for j = max(2,i):length(rte) + 1
            rte′ = vcat(rte[1:i-1], idx, rte[i:j-1], idx, rte[j:end])
            TC = rteTCh(rte′)
            if TC < TCᵒ
                rteᵒ, TCᵒ = rte′, TC
            end
        end
    end
    return rteᵒ, TCᵒ
end
end # module RtV030

# ---- Lecture 5.1, Ex. 3 (5-routing/5-rte-1.qmd), verbatim: the tour of Code block 12 (:1130), the arc costs of
# Code block 13 (:1607-1613), the tour's cost of Code block 14 (:1621), and the printing 2-opt of Code block 15
# (:1632-1658), whose call (:1660) the test makes. ----
const E2_L51_INPUTS = raw"""
π = [1:6; 1]
D = [
     0     8     6     9     1     5
     3     0     1     5     4     2
     9     2     0     3     1     1
     8     2     1     0    10     6
     6     7    10     1     0    10
     6     2     5     2     1     0]
πTCh(π) = sum(segcost(π, D))
"""

const E2_L51_TWOOPT_PRT = raw"""
function twoopt_prt(π, πTCh)
    πᵒ, TCᵒ = copy(π), πTCh(π)
    println("*", TCᵒ, ": ", πᵒ)
    done = false
    while !done
        done = true
        for i = 1:length(π)-2
            for j = i+2:min(length(π)-1, length(π)+i-3)
                π′ = vcat(π[1:i], reverse(π[i+1:j]), π[j+1:end])
                TC = πTCh(π′)
                if TC < TCᵒ
                    πᵒ, TCᵒ = π′, TC
                    println("*", TCᵒ, ": ", πᵒ)
                    done = false
                    break
                else
                    println(" ", TC, ": ", π′)
                end
            end
            if done == false
                break
            end
        end
        π = copy(πᵒ)
    end
    return πᵒ, TCᵒ
end
"""

# ---- Lecture 5.2, Ex. 1 (5-routing/5-rte-2.qmd), verbatim: the network and shipments of Code block 2
# (:415-423), the hidden cell's check of its costs (:431-436), Ex. 1's costs again in Code block 16 (:990-992),
# and Code block 17, the printing insertion (:1004-1017) and its two calls (:1019-1026). ----
const E2_L52_SETUP = raw"""
using Graphs, SimpleWeightedGraphs
i = [1, 3, 5, 1, 4, 1, 6]              # one end of each road
j = [2, 4, 6, 3, 2, 5, 2]              # its other end
w = [300, 250, 275, 30, 30, 60, 60]    # its miles
g = SimpleWeightedGraph(i, j, w)       # a network of two-way roads
D, _ = shortestpaths(g, weights(g), nv(g))  # from every location  # <1>
D = Int.(D)                            # whole miles
sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6])  # origin, destination
D
@assert D == [  0  300   30  280   60  335
              300    0  280   30  335   60
               30  280    0  250   90  340
              280   30  250    0  340   90
               60  335   90  340    0  275
              335   60  340   90  275    0]
D1 = Int.(shortestpaths(g, weights(g), nv(g))[1])  # g of Code block 2
sh1 = DataFrame(b = [1, 3, 5], e = [2, 4, 6])
rTD1h(rte) = rteTC(rte, sh1, D1);
"""

const E2_L52_MINCOSTINSERT_PRT = raw"""
function mincostinsert_prt(idx, rte, rteTCh)
    rteᵒ, TCᵒ = copy(rte), Inf
    for i = 1:length(rte)
        for j = max(2,i):length(rte) + 1
            rte′ = vcat(rte[1:i-1], idx, rte[i:j-1], idx, rte[j:end])
            TC = rteTCh(rte′)
            println(i,",",j,": ",rte′, " = ", TC)
            if TC < TCᵒ
                rteᵒ, TCᵒ = rte′, TC
            end
        end
    end
    return rteᵒ, TCᵒ
end
"""

const E2_L52_CALLS = raw"""
# insert shmt 2 route into shmt 1 route
rte12, TD12 = mincostinsert_prt(2, [1, 1], rTD1h)
@show rte12
@show TD12
# insert shmt 3 route into shmt 1&2 route
rte123, TD123 = mincostinsert_prt(3, rte12, rTD1h)
@show rte123
@show TD123;
"""

# The lectures' modules: `using Logjam` (and 5.2's `using DataFrames`, its setup cell :77), then the text. Code
# block 2 and 16's three-argument `shortestpaths` is deprecated; its warning (printed only under --depwarn=yes,
# on stderr) is silenced, and nothing the lecture prints is touched.
const E2_L51 = Module(:E2Lecture51)
Core.eval(E2_L51, :(using Logjam))
include_string(E2_L51, E2_L51_INPUTS, "5-rte-1.qmd")
include_string(E2_L51, E2_L51_TWOOPT_PRT, "5-rte-1.qmd")

const E2_L52 = Module(:E2Lecture52)
Core.eval(E2_L52, :(using Logjam, DataFrames))
Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
    include_string(E2_L52, E2_L52_SETUP, "5-rte-2.qmd")
end
include_string(E2_L52, E2_L52_MINCOSTINSERT_PRT, "5-rte-2.qmd")

# f's value and everything it printed to stdout, byte for byte (an IOStream, as test_location_v031.jl captures)
function _e2_out(f)
    mktemp() do path, io
        val = redirect_stdout(f, io)
        flush(io); close(io)
        return val, read(path, String)
    end
end
_e2_lines(s) = count(==('\n'), s)

# the lectures' printing functions and Logjam's, each called in the latest world (the definitions above are new)
_e2_twoopt_prt(π, h) = _e2_out(() -> Base.invokelatest(getfield(E2_L51, :twoopt_prt), π, h))
_e2_mci_prt(k, r, h) = _e2_out(() -> Base.invokelatest(getfield(E2_L52, :mincostinsert_prt), k, r, h))
_e2_lj(f, args...; kw...) = _e2_out(() -> Base.invokelatest(f, args...; kw...))

@testset "E2: twoopt(...; verbose = true) prints Lecture 5.1's Code block 15, byte for byte" begin
    π0 = getfield(E2_L51, :π)
    h = getfield(E2_L51, :πTCh)
    D = getfield(E2_L51, :D)
    @test π0 == [1, 2, 3, 4, 5, 6, 1]
    lec, lec_out = _e2_twoopt_prt(π0, h)
    @test _e2_lines(lec_out) == 20                                  # @tbl-twoopt-trace's rows
    @test startswith(lec_out, "*38: [1, 2, 3, 4, 5, 6, 1]\n")
    # the cost-handle method, as Code block 16 calls it, with the keyword
    lj, lj_out = _e2_lj(twoopt, π0, h; verbose = true)
    @test lj_out == lec_out
    @test (lj.rte, lj.TC) == lec
    # the matrix method: the delta search, each tour considered costed as the handle costs it, for the trace only
    ljC, ljC_out = _e2_lj(twoopt, π0, D; verbose = true)
    @test ljC_out == lec_out
    @test (ljC.rte, ljC.TC) == lec
    # a vector of one tour: the same lines, under each method
    @test _e2_lj(twoopt, [π0], h; verbose = true)[2] == lec_out
    @test _e2_lj(twoopt, [π0], D; verbose = true)[2] == lec_out
    @test π0 == [1, 2, 3, 4, 5, 6, 1]                                # not modified
end

@testset "E2: mincostinsert(...; verbose = true) prints Lecture 5.2's Code block 17, byte for byte" begin
    m = E2_L52
    h = getfield(m, :rTD1h)
    @test getfield(m, :D1) == getfield(m, :D)
    # the first insertion, shipment 2 into shipment 1's route: four routes
    lec1, lec1_out = _e2_mci_prt(2, [1, 1], h)
    @test _e2_lines(lec1_out) == 4
    lj1, lj1_out = _e2_lj(mincostinsert, 2, [1, 1], h; verbose = true)
    @test lj1_out == lec1_out
    @test (lj1.rte, lj1.TC) == lec1
    # the second, shipment 3 into the route the first made: thirteen routes
    lec2, lec2_out = _e2_mci_prt(3, lec1[1], h)
    @test _e2_lines(lec2_out) == 13
    lj2, lj2_out = _e2_lj(mincostinsert, 3, lj1.rte, h; verbose = true)
    @test lj2_out == lec2_out
    @test (lj2.rte, lj2.TC) == lec2
    # the whole cell, as the lecture runs it, and the same cell with Logjam's call in the lecture's place (the
    # call the lecture can make at the re-pin): the 17 routes and the four @show lines
    lj_calls = replace(E2_L52_CALLS,
        "mincostinsert_prt(2, [1, 1], rTD1h)" => "mincostinsert(2, [1, 1], rTD1h; verbose = true)",
        "mincostinsert_prt(3, rte12, rTD1h)" => "mincostinsert(3, rte12, rTD1h; verbose = true)")
    @test !occursin("mincostinsert_prt", lj_calls)
    cell_lec = _e2_out(() -> include_string(m, E2_L52_CALLS, "5-rte-2.qmd"))[2]
    cell_lj = _e2_out(() -> include_string(m, lj_calls, "5-rte-2.qmd"))[2]
    @test _e2_lines(cell_lec) == 21
    @test cell_lj == cell_lec
    @test endswith(cell_lec, "rte123 = [3, 1, 2, 2, 1, 3]\nTD123 = 430\n")
end

# ---- seeded inputs beyond the lectures': tours on integer (asymmetric and symmetric) and real matrices, routes
# of shipments on real distances, and insertions into them ----
function _e2_tours()
    rng = Xoshiro(6101)
    cases = Tuple{Vector{Int},Matrix}[]
    for k in 1:24
        n = rand(rng, 4:11)
        C = k % 3 == 0 ? rand(rng, n, n) : rand(rng, 0:60, n, n)
        k % 4 == 1 && (C = C + C')                                    # some symmetric
        for i in 1:n
            C[i, i] = 0
        end
        p = randperm(rng, n)
        push!(cases, ([p; p[1]], C))
    end
    return cases
end
function _e2_routes()
    rng = Xoshiro(6102)
    cases = Tuple{Vector{Int},Function,DataFrame,Matrix{Float64}}[]
    for k in 1:18
        m = rand(rng, 2:6)
        P = 100 .* rand(rng, 2m, 2)
        D = [hypot(P[a, 1] - P[b, 1], P[a, 2] - P[b, 2]) for a in 1:2m, b in 1:2m]
        sh = DataFrame(b = 1:m, e = m+1:2m)
        r = [randperm(rng, m); randperm(rng, m)]                     # every shipment loaded, then unloaded
        h = rte -> rteTC(rte, sh, D)
        push!(cases, (r, h, sh, D))
    end
    return cases
end
const E2_TOURS = _e2_tours()
const E2_ROUTES = _e2_routes()

@testset "E2: the tour traces equal Lecture 5.1's twoopt_prt on seeded tours" begin
    for (t, C) in E2_TOURS
        h = π -> sum(segcost(π, C))
        lec, lec_out = _e2_twoopt_prt(t, h)
        lj, lj_out = _e2_lj(twoopt, t, h; verbose = true)
        @test lj_out == lec_out
        @test (lj.rte, lj.TC) == lec
        if eltype(C) <: Integer                     # the delta decides as the whole cost does in exact arithmetic
            ljC, ljC_out = _e2_lj(twoopt, t, C; verbose = true)
            @test ljC_out == lec_out
            @test (ljC.rte, ljC.TC) == lec
        end
    end
end

@testset "E2: the insertion traces equal Lecture 5.2's mincostinsert_prt on seeded routes" begin
    for (r, h, sh, D) in E2_ROUTES
        m = nrow(sh)
        # shipment m left out of the route, then inserted (the route of the others, unloaded in its own order)
        r0 = filter(!=(m), r)
        isempty(r0) && continue
        lec, lec_out = _e2_mci_prt(m, r0, h)
        @test _e2_lines(lec_out) == length(r0) * (length(r0) + 3) ÷ 2 - 1    # 5.2's Eq. insert-count
        lj, lj_out = _e2_lj(mincostinsert, m, r0, h; verbose = true)
        @test lj_out == lec_out
        @test lj.TC == lec[2]
        @test lj.rte == Logjam._order_ties(lec[1], h)                       # CR 58 after the loop, as by default
    end
    # into an empty route the shipment goes as [k, k], outside the loops; the lecture's function prints nothing
    # for an empty route, and neither does Logjam's
    h = rte -> rteTC(rte, DataFrame(b = [1, 3], e = [2, 4]), [0 5 7 9; 5 0 4 6; 7 4 0 3; 9 6 3 0])
    @test _e2_mci_prt(1, Int[], h)[2] == ""
    v, out = _e2_lj(mincostinsert, 1, Int[], h; verbose = true)
    @test out == ""
    @test v == RtV030.mincostinsert(1, Int[], h)
end

@testset "E2: the route 2-opt's trace is every route Lecture 5.2's twoopt_rte costs, in order" begin
    L52 = lecture52_module(:E2Lecture52Rte)
    for (r, h, sh, D) in E2_ROUTES
        seen = Tuple{Vector{Int},Float64}[]
        rec = rte -> (c = h(rte); push!(seen, (copy(rte), c)); c)
        lecture52_call(L52, :twoopt_rte, r, rec)
        # the lines twoopt_prt's rule makes of those evaluations: the first is the start, and a later one is starred
        # when its cost is below the best so far
        io = IOBuffer()
        best = Inf
        for (k, (rte, c)) in enumerate(seen)
            star = k == 1 || c < best
            star && (best = c)
            println(io, star ? "*" : " ", c, ": ", rte)
        end
        expected = String(take!(io))
        lj, lj_out = _e2_lj(twoopt, r, h; verbose = true)
        @test lj_out == expected
        @test _e2_lines(lj_out) == length(seen)
        # its last starred line is the search's result (the export then orders ties, CR 58)
        last_star = filter(l -> startswith(l, "*"), split(chomp(lj_out), '\n'))[end]
        kr, kTC = Logjam._twoopt(r, h)
        @test last_star == string("*", kTC, ": ", kr)
        @test lj == twoopt(r, h)
    end
end

@testset "E2: a vector of routes prints each route's trace in turn" begin
    # routes: each case's route and its reverse (a route too: the last unloading is loaded first), on its handle
    for (r, h, _, _) in E2_ROUTES[1:6]
        R = [r, reverse(r)]
        v, out = _e2_lj(twoopt, R, h; verbose = true)
        @test out == join(_e2_lj(twoopt, x, h; verbose = true)[2] for x in R)
        @test v == twoopt(R, h)
    end
    # tours, under the cost handle and the matrix: three tours of the first integer case's nodes
    t1, C1 = first((t, C) for (t, C) in E2_TOURS if eltype(C) <: Integer)
    p = randperm(Xoshiro(6103), size(C1, 1))
    T = [t1, reverse(t1), [p; p[1]]]
    h1 = π -> sum(segcost(π, C1))
    for f in (h1, C1)
        v, out = _e2_lj(twoopt, T, f; verbose = true)
        @test out == join(_e2_lj(twoopt, t, f; verbose = true)[2] for t in T)
        @test v == twoopt(T, f)
    end
    # Lecture 5.3 Ex. 1(c) (the docstring's example): the savings routes under a capacity of 15, some costs Inf
    C = [ 0 40 48 38 33 48
         40  0 87 46 65 75
         48 87  0 67 41 47
         38 46 67  0 70 34
         33 65 41 70  0 69
         48 75 47 34 69  0]
    sh53 = DataFrame(b = ones(Int, 5), e = 2:6, q = [8, 5, 4, 7, 6])
    hq = rte -> (TC = rteTC(rte, sh53, C, (b = 1, e = 1)); sum(sh53.q[unique(rte)]) <= 15 ? TC : Inf)
    R53 = savings(hq, sh53)
    v, out = _e2_lj(twoopt, R53, hq; verbose = true)
    @test out == join(_e2_lj(twoopt, r, hq; verbose = true)[2] for r in R53)
    @test v == twoopt(R53, hq)
    @test v.TC == [167, 138]
end

@testset "E2: verbose = false, the default, prints nothing and returns what v0.3.0 returned" begin
    π0, h51, D51 = getfield(E2_L51, :π), getfield(E2_L51, :πTCh), getfield(E2_L51, :D)
    h52 = getfield(E2_L52, :rTD1h)
    calls = Any[]                                   # (Logjam's function, v0.3.0's, the arguments)
    push!(calls, (twoopt, RtV030.twoopt, (π0, h51)), (twoopt, RtV030.twoopt, (π0, D51)),
          (twoopt, RtV030.twoopt, ([π0, π0], h51)), (twoopt, RtV030.twoopt, ([π0], D51)),
          (twoopt, RtV030.twoopt, ([1, 2, 3, 1, 2, 3], h52)), (twoopt, RtV030.twoopt, ([1, 1, 2, 2, 3, 3], h52)),
          (mincostinsert, RtV030.mincostinsert, (2, [1, 1], h52)),
          (mincostinsert, RtV030.mincostinsert, (3, [1, 2, 2, 1], h52)),
          (mincostinsert, RtV030.mincostinsert, (3, Int[], h52)))
    for (t, C) in E2_TOURS
        push!(calls, (twoopt, RtV030.twoopt, (t, π -> sum(segcost(π, C)))), (twoopt, RtV030.twoopt, (t, C)))
    end
    for (r, h, sh, D) in E2_ROUTES
        m = nrow(sh)
        push!(calls, (twoopt, RtV030.twoopt, (r, h)), (twoopt, RtV030.twoopt, ([r, reverse(r)], h)),
              (mincostinsert, RtV030.mincostinsert, (m, filter(!=(m), r), h)))
    end
    C53 = [0 40 48 38 33 48; 40 0 87 46 65 75; 48 87 0 67 41 47; 38 46 67 0 70 34; 33 65 41 70 0 69; 48 75 47 34 69 0]
    sh53 = DataFrame(b = ones(Int, 5), e = 2:6, q = [8, 5, 4, 7, 6])
    hq = rte -> (TC = rteTC(rte, sh53, C53, (b = 1, e = 1)); sum(sh53.q[unique(rte)]) <= 15 ? TC : Inf)
    push!(calls, (twoopt, RtV030.twoopt, (savings(hq, sh53), hq)), (mincostinsert, RtV030.mincostinsert, (5, [1, 4, 1, 4], hq)))
    for (f, f030, args) in calls
        ref = Base.invokelatest(f030, args...)
        v0, out0 = _e2_lj(f, args...)                            # the default
        vf, outf = _e2_lj(f, args...; verbose = false)
        vt, _ = _e2_lj(f, args...; verbose = true)               # printing changes nothing computed
        @test out0 == "" && outf == ""
        @test v0 == ref && vf == ref && vt == ref
    end
    # the kernels that savings, pairwisesavings and the insertion hook run, called as they call them
    for (r, h, sh, D) in E2_ROUTES
        m = nrow(sh)
        @test _e2_out(() -> Logjam._twoopt(r, h)) == (RtV030._twoopt(r, h), "")
        @test _e2_out(() -> Logjam._twoopt_route(r, h)) == (RtV030._twoopt_route(r, h), "")
        @test _e2_out(() -> Logjam._mincostinsert(m, filter(!=(m), r), h)) == (RtV030._mincostinsert(m, filter(!=(m), r), h), "")
    end
    for (t, C) in E2_TOURS
        h = π -> sum(segcost(π, C))
        @test _e2_out(() -> Logjam._twoopt_tour(t, h)) == (RtV030._twoopt_tour(t, h), "")
    end
    # the procedures built on the kernels print nothing
    sh52 = getfield(E2_L52, :sh1)
    @test _e2_out(() -> savings(h52, sh52))[2] == ""
    @test _e2_out(() -> pairwisesavings(h52, sh52))[2] == ""
end
