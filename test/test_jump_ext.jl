# test_jump_ext.jl -- added by PCV WP2 of Logjam v0.3.1 (CR 45, E3, SV, X3): the optimization extension,
# LogjamJuMPExt, which JuMP and HiGHS load together. Test spec Sec. 8. The oracle is each lecture's own definition,
# copied below as text with its `.qmd` lines cited and run, after `using Logjam` as the lecture runs it, beside
# Logjam's on the lecture's inputs:
#   1. `Logjam.subtours` against Lecture 5.1's (5-routing/5-rte-1.qmd:682-695): `==` on every permutation of n <= 7
#      and on the successor vectors of 5.1's rounds;
#   2. `Logjam.TSP` against Lecture 5.1's (5-rte-1.qmd:697-731) and Lecture 5.3's copy (5-routing/5-rte-3.qmd:902-949)
#      on 5.1's matrices (Ex. 2's ten cities, Ex. 3(d)'s six nodes, Ex. 4(c)'s 100 counties, Code block 24's random
#      instances) and 5.3's (Code block 10's 31 points): the cost `isapprox(rtol = 1e-9)` (HiGHS's `mip_rel_gap = 0`),
#      the tour one cycle and equal up to rotation and reversal, and each round's subtours `==`;
#   3. `Logjam.binpack` against Lecture 2.7's (2-location/2-loc-7.qmd:2260-2281) and Lecture 5.3's copy
#      (5-rte-3.qmd:2662-2683) on their inputs (2.7's Ex. 8 and Code blocks 28 and 29, 5.3's Code block 49): the bin
#      count `==`, every object in exactly one bin, no bin over its capacity, the return's fields 2.7's;
#   4. `snapvals` on JuMP variables `==` to `snapvals(value.(x))` on ISE 361 F25-style models (Lecture 4.3's
#      production-inventory model, which is ISE 361 F25's 5-MIP-4 cell 16, on its Ex. 3; Lecture 2.7's Code block 2;
#      2.7's bin packing model), and the numeric method unchanged;
#   5. isolation, in fresh processes: Logjam loads without JuMP and HiGHS and `TSP` and `binpack` are then a
#      MethodError whose hint says `using JuMP, HiGHS`; with both loaded, in either order, the extension is loaded.
# runtests.jl imports JuMP and HiGHS just before including this file, so every file before it ran without them.
# Not run here, for the suite's time (each measured once in WP2's build): 5.1 Ex. 4(d)'s road-mile TSP (about 17 s
# to build the network and 95 s a solve), Code block 24's m = 50 beyond its first two instances (about 2 s an
# instance), and Code block 29's 1% and 5% gaps (about 7 to 10 s a solve).

using Test
using Logjam
using DataFrames
using Random
using CSV
import JuMP, HiGHS

@isdefined(LECTURE51_DISK) || include(joinpath(@__DIR__, "lecture51_code.jl"))

const _WP2_JEXT = Base.get_extension(Logjam, :LogjamJuMPExt)

# ---- the lectures' definitions, verbatim; only each block's `# Model:` or `# Code block` title line is left out ----

# Lecture 5.1 Sec. 2's implementation rung, 5-routing/5-rte-1.qmd:681-731
const WP2_L51_TSP = raw"""
using JuMP, HiGHS
function subtours(succ)                # the cycles of a successor vector
    S, seen = Vector{Vector{Int}}(), falses(length(succ))
    for k ∈ eachindex(succ)
        seen[k] && continue
        Sₖ, i = Int[], k
        while !seen[i]                 # follow the arcs back to k
            seen[i] = true
            push!(Sₖ, i)
            i = succ[i]
        end
        push!(S, Sₖ)
    end
    return S
end

function TSP(c)
    size(c, 1) == size(c, 2) ||        # assumption (a): each pair's cost
        error("arc costs must be a square matrix")
    V = 1:size(c, 1)
    model = Model(HiGHS.Optimizer)
    @variable(model, x[i ∈ V, j ∈ V; i ≠ j], Bin)    # no arc i to i
    @objective(model, Min,
               sum(c[i, j] * x[i, j] for i ∈ V, j ∈ V if i ≠ j))
    @constraint(model, leave[i ∈ V],
                sum(x[i, j] for j ∈ V if j ≠ i) == 1)          # (a)
    @constraint(model, enter[j ∈ V],
                sum(x[i, j] for i ∈ V if i ≠ j) == 1)          # (b)

    set_silent(model)
    set_attribute(model, "mip_rel_gap", 0.0)                     # <1>
    rounds = []
    while true
        optimize!(model)
        termination_status(model) == JuMP.OPTIMAL ||
            error(termination_status(model))
        succ = [findfirst(j -> j ≠ i && value(x[i, j]) > 0.5, V)  # <2>
                for i ∈ V]             # the node after each node
        S = subtours(succ)
        push!(rounds, (TC = objective_value(model), S = S))
        if length(S) == 1              # a single tour: done
            return (TC = objective_value(model), tour = [S[1]; S[1][1]],
                    rounds = rounds)
        end
        for Sₖ ∈ S                     # (c), for each subtour found
            @constraint(model,                                   # <3>
                sum(x[i, j] for i ∈ Sₖ, j ∈ Sₖ if i ≠ j) ≤ length(Sₖ) - 1,
                base_name = "singletour")
        end
    end
end
"""

# Lecture 5.3's Code block 9, "the TSP formulation of Lecture 5.1", 5-routing/5-rte-3.qmd:901-949
const WP2_L53_TSP = raw"""
using JuMP, HiGHS
function subtours(succ)                # the cycles of a successor vector
    S, seen = Vector{Vector{Int}}(), falses(length(succ))
    for k ∈ eachindex(succ)
        seen[k] && continue
        Sₖ, i = Int[], k
        while !seen[i]                 # follow the arcs back to k
            seen[i] = true
            push!(Sₖ, i)
            i = succ[i]
        end
        push!(S, Sₖ)
    end
    return S
end
function TSP(c)
    size(c, 1) == size(c, 2) ||        # assumption (a): each pair's cost
        error("arc costs must be a square matrix")
    V = 1:size(c, 1)
    model = Model(HiGHS.Optimizer)
    @variable(model, x[i ∈ V, j ∈ V; i ≠ j], Bin)    # no arc i to i
    @objective(model, Min,
               sum(c[i, j] * x[i, j] for i ∈ V, j ∈ V if i ≠ j))
    @constraint(model, leave[i ∈ V],
                sum(x[i, j] for j ∈ V if j ≠ i) == 1)          # (a)
    @constraint(model, enter[j ∈ V],
                sum(x[i, j] for i ∈ V if i ≠ j) == 1)          # (b)
    set_silent(model)
    set_attribute(model, "mip_rel_gap", 0.0)
    rounds = []
    while true
        optimize!(model)
        termination_status(model) == JuMP.OPTIMAL ||
            error(termination_status(model))
        succ = [findfirst(j -> j ≠ i && value(x[i, j]) > 0.5, V)
                for i ∈ V]             # the node after each node
        S = subtours(succ)
        push!(rounds, (TC = objective_value(model), S = S))
        if length(S) == 1              # a single tour: done
            return (TC = objective_value(model), tour = [S[1]; S[1][1]],
                    rounds = rounds)
        end
        for Sₖ ∈ S                     # (c), for each subtour found
            @constraint(model,
                sum(x[i, j] for i ∈ Sₖ, j ∈ Sₖ if i ≠ j) ≤ length(Sₖ) - 1,
                base_name = "singletour")
        end
    end
end
"""

# Lecture 2.7 Sec. 4's implementation rung, 2-location/2-loc-7.qmd:2260-2281 (2.7 loads JuMP and HiGHS earlier)
const WP2_L27_BINPACK = raw"""
function binpack(v, V; tlim = 60.0, gap = 1e-4)
    M = 1:length(v)
    bp = Model(HiGHS.Optimizer)
    set_silent(bp)
    set_time_limit_sec(bp, tlim)           # give up after this long
    set_attribute(bp, "mip_rel_gap", gap)  # or once this close
    @variable(bp, y[M], Bin)
    @variable(bp, x[M, M], Bin)
    @objective(bp, Min, sum(y))
    @constraint(bp, capacity[i ∈ M],       # (a)
                V * y[i] >= sum(v[j] * x[i, j] for j ∈ M))
    @constraint(bp, assignment[j ∈ M],     # (b)
                sum(x[i, j] for i ∈ M) == 1)
    optimize!(bp)
    xᵒ, yᵒ = snapvals(value.(x)), snapvals(value.(y))
    used = findall(==(1.0), yᵒ)
    bins = [findall(==(1.0), xᵒ[i, :]) for i ∈ used]
    res = (bins = bins, used = Int(objective_value(bp)),
           status = termination_status(bp), gap = relative_gap(bp),
           secs = solve_time(bp))
    return res
end
"""

# Lecture 5.3's Code block 48, "the bin packing model of Lecture 2.7", 5-routing/5-rte-3.qmd:2662-2683
const WP2_L53_BINPACK = raw"""
function binpack(v, V; tlim = 60.0, gap = 1e-4)
    M = 1:length(v)
    bp = Model(HiGHS.Optimizer)
    set_silent(bp)
    set_time_limit_sec(bp, tlim)           # give up after this long
    set_attribute(bp, "mip_rel_gap", gap)  # or once this close
    @variable(bp, y[M], Bin)
    @variable(bp, x[M, M], Bin)
    @objective(bp, Min, sum(y))
    @constraint(bp, capacity[i ∈ M],       # (a)
                V * y[i] >= sum(v[j] * x[i, j] for j ∈ M))
    @constraint(bp, assignment[j ∈ M],     # (b)
                sum(x[i, j] for i ∈ M) == 1)
    optimize!(bp)
    xᵒ, yᵒ = snapvals(value.(x)), snapvals(value.(y))
    used = findall(==(1.0), yᵒ)
    bins = [findall(==(1.0), xᵒ[i, :]) for i ∈ used]
    res = (bins = bins, used = Int(objective_value(bp)),
           status = termination_status(bp), gap = relative_gap(bp),
           secs = solve_time(bp))
    return res
end
"""

# A scratch module that has done `using Logjam`, `using DataFrames` and `using JuMP, HiGHS`, as the lectures have by
# the time they define these, then runs the given lecture text.
function _wp2_lecture(name::Symbol, texts...)
    m = Module(name)
    Core.eval(m, :(using Logjam))
    Core.eval(m, :(using DataFrames))
    Core.eval(m, :(using JuMP, HiGHS))
    for t in texts
        include_string(m, t, string(name))
    end
    return m
end
# a lecture's function, read and called in the latest world (the module's definitions are newer than the caller)
_wp2_fn(m::Module, f::Symbol) = Base.invokelatest(getglobal, m, f)
_wp2_call(m::Module, f::Symbol, args...; kw...) = Base.invokelatest(_wp2_fn(m, f), args...; kw...)

# the code of a definition, without its comments' Quarto annotation markers (`# <1>`), trailing spaces or blank lines
_wp2_code(t) = [rstrip(replace(l, r"#\s*<\d+>\s*$" => "")) for l in split(t, '\n') if !isempty(strip(l))]

# a closed tour, equal up to its starting node and its direction
function _wp2_sametour(a, b)
    ra, rb = a[1:end-1], b[1:end-1]
    length(ra) == length(rb) || return false
    n = length(ra)
    return any(circshift(rb, k) == ra || circshift(reverse(rb), k) == ra for k in 0:n-1)
end
# a closed tour that visits every one of n nodes once
_wp2_onecycle(t, n) = t[1] == t[end] && sort(t[1:end-1]) == 1:n
# the successor vector whose cycles are S
function _wp2_succ(S)
    succ = zeros(Int, sum(length, S))
    for C in S, k in eachindex(C)
        succ[C[k]] = C[mod1(k + 1, length(C))]
    end
    return succ
end
# every permutation of 1:n
function _wp2_perms(n)
    n == 0 && return [Int[]]
    out = Vector{Int}[]
    for p in _wp2_perms(n - 1), k in 0:n-1
        push!(out, [p[1:k]; n; p[k+1:end]])
    end
    return out
end

# Logjam's TSP and a lecture's on one matrix: what each test below asks of the pair
function _wp2_tsppair(lec, c)
    J = Logjam.TSP(c)
    L = _wp2_call(lec, :TSP, c)
    n = size(c, 1)
    tourcost(t) = sum(c[t[k], t[k+1]] for k in 1:length(t)-1)
    return (J = J, L = L,
            cost = isapprox(J.TC, L.TC; rtol = 1e-9),
            tour = _wp2_sametour(J.tour, L.tour),
            cycle = _wp2_onecycle(J.tour, n) && isapprox(tourcost(J.tour), J.TC; rtol = 1e-9),
            rounds = [rd.S for rd in J.rounds] == [rd.S for rd in L.rounds] &&
                     all(isapprox(a.TC, b.TC; rtol = 1e-9) for (a, b) in zip(J.rounds, L.rounds)))
end

# Logjam's binpack and a lecture's on one instance
function _wp2_binpair(lec, v, V; kw...)
    J = Logjam.binpack(v, V; kw...)
    L = _wp2_call(lec, :binpack, v, V; kw...)
    return (J = J, L = L,
            count = J.used == L.used && length(J.bins) == J.used,
            once = sort(reduce(vcat, J.bins; init = Int[])) == collect(eachindex(v)),
            fits = all(sum(v[b]) ≤ V for b in J.bins),
            fields = keys(J) == keys(L) == (:bins, :used, :status, :gap, :secs),
            same = J.bins == L.bins && J.status == L.status)
end

# ---- the lectures' inputs ----

# Lecture 5.1 Ex. 2: Code block 4's cities (5-rte-1.qmd:507-509) and Code block 5's great circle distances (:539-540)
function _wp2_nc10()
    df = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
    P = hcat(df.LON, df.LAT)
    return dists(P, P, :mi)
end
# Lecture 5.1 Ex. 3: Code block 13's arc costs (5-rte-1.qmd:1607-1613)
const WP2_D6 = [0     8     6     9     1     5
                3     0     1     5     4     2
                9     2     0     3     1     1
                8     2     1     0    10     6
                6     7    10     1     0    10
                6     2     5     2     1     0]
# Lecture 5.1 Ex. 4: Code block 25's counties (5-rte-1.qmd:2374) and Code block 27's distances (:2449-2450)
function _wp2_nc100()
    df = filter(r -> (r.STFIP == st2fips(:NC)), uscounty())
    XY = hcat(df.LON, df.LAT)
    return dists(XY, XY, :mi)
end
# Lecture 5.1 Code block 24 (5-rte-1.qmd:2278-2284): the DC at the center and m customers drawn by `disk`
# (test/lecture51_code.jl's copy of :2267-2276) after `Random.seed!(150)`, for each m in turn; Euclidean distances.
# The global stream is put back where it was.
function _wp2_disks(lec51)
    saved = copy(Random.default_rng())
    Random.seed!(150)
    Ds = Dict{Int,Vector{Matrix{Float64}}}()
    for m in (2, 5, 10, 20, 50)                # the lecture's m to 50, the last the TSP is solved for
        reps = 1000 ÷ m
        Ps = [[0.0 0.0; _wp2_call(lec51, :disk, m)] for _ in 1:reps]
        Ds[m] = [dists(P, P, 2) for P in Ps]
    end
    copy!(Random.default_rng(), saved)
    return Ds
end
# Lecture 5.3 Code block 6 (5-rte-3.qmd:794-798): the depot, shipment 1's destination (e1 = 42), then the 30
# shipments' origins, b of 5-routing/data/shmtNC30-sh.csv, among the 54 places (test/data/shmtNC30-xy.csv); road
# miles as great circle miles times 1.2
function _wp2_nc31()
    xy = CSV.read(joinpath(@__DIR__, "data", "shmtNC30-xy.csv"), DataFrame)
    e1 = 42
    b = [15, 26, 23, 53, 17, 3, 39, 47, 44, 45, 43, 8, 29, 34, 38, 41, 18, 40, 1, 11, 7, 30, 33, 22, 20, 19, 16, 48,
         37, 14]
    X = Matrix(xy[[e1; b], [:x, :y]])
    return dists(X, X, :mi) * 1.2
end
# Lecture 2.7 Ex. 8: Code block 30's twenty sizes (2-loc-7.qmd:2384-2386), as its `prt(vB')` prints them
const WP2_VB = [2, 4, 4, 5, 4, 3, 3, 3, 1, 5, 5, 4, 2, 3, 1, 4, 1, 2, 1, 3]
# Lecture 2.7 Code blocks 28 and 29 (2-loc-7.qmd:2301-2303, :2333-2334): m objects of sizes 1 to 5 after
# `Random.seed!(9)`; the global stream is put back where it was
function _wp2_seed9(m)
    saved = copy(Random.default_rng())
    Random.seed!(9)
    v = rand(1:5, m)
    copy!(Random.default_rng(), saved)
    return v
end
# Lecture 5.3 Ex. 6: the ten route times of @tbl-ffd-steps, by route (5-rte-3.qmd:2565-2576, printed to two
# decimals; Code block 44 computes them from the routes), and Code block 46's loading time (:2615-2616)
const WP2_TJ = [7.11, 5.03, 2.50, 2.32, 3.27, 0.92, 4.12, 3.77, 1.65, 1.61]
const WP2_TL = 20/60

@testset "WP2 (v0.3.1): the optimization extension: TSP, subtours, binpack, snapvals on JuMP variables" begin

    l51 = _wp2_lecture(:WP2Lecture51, WP2_L51_TSP)
    l53 = _wp2_lecture(:WP2Lecture53, WP2_L53_TSP, WP2_L53_BINPACK)
    l27 = _wp2_lecture(:WP2Lecture27, WP2_L27_BINPACK)

    @testset "the extension is loaded, and each function is declared in core, public and not exported" begin
        @test _WP2_JEXT !== nothing
        for s in (:TSP, :subtours, :binpack)
            @test Base.ispublic(Logjam, s) && !Base.isexported(Logjam, s)
            @test haskey(Base.Docs.meta(Logjam), Base.Docs.Binding(Logjam, s))       # the docstring is core's
        end
        @test isempty(Base.Docs.meta(_WP2_JEXT))                                     # and none is the extension's
        @test length(methods(Logjam.TSP)) == 1 && all(m -> m.module === _WP2_JEXT, methods(Logjam.TSP))
        @test length(methods(Logjam.binpack)) == 1 && all(m -> m.module === _WP2_JEXT, methods(Logjam.binpack))
        @test length(methods(Logjam.subtours)) == 1 && all(m -> m.module === Logjam, methods(Logjam.subtours))
        @test String.(Base.kwarg_decl(only(methods(Logjam.binpack)))) == ["tlim", "gap"]
        # the lectures' own definitions, made after `using Logjam`, are their own (D10: not exported, no collision)
        @test parentmodule(_wp2_fn(l51, :TSP)) === l51 && parentmodule(_wp2_fn(l51, :subtours)) === l51
        @test parentmodule(_wp2_fn(l53, :TSP)) === l53 && parentmodule(_wp2_fn(l53, :binpack)) === l53 &&
              parentmodule(_wp2_fn(l27, :binpack)) === l27
        @test isempty(Test.detect_ambiguities(Logjam, _WP2_JEXT))
    end

    @testset "5.3's copies are 5.1's and 2.7's definitions" begin
        @test _wp2_code(WP2_L53_TSP) == _wp2_code(WP2_L51_TSP)
        @test _wp2_code(WP2_L53_BINPACK) == _wp2_code(WP2_L27_BINPACK)
    end

    @testset "subtours == Lecture 5.1's on every permutation of n ≤ 7" begin
        for n in 0:7
            ps = _wp2_perms(n)
            @test length(ps) == factorial(n) && allunique(ps)
            got = [Logjam.subtours(p) for p in ps]
            @test got == [_wp2_call(l51, :subtours, p) for p in ps]
            # each cycle follows the arcs, starts at its lowest node, and together they hold every node once
            @test all(zip(ps, got)) do (p, S)
                sort(reduce(vcat, S; init = Int[])) == 1:n && all(C -> C[1] == minimum(C), S) &&
                    all(C -> all(p[C[k]] == C[mod1(k + 1, length(C))] for k in eachindex(C)), S)
            end
        end
        @test Logjam.subtours([2, 1, 4, 5, 3]) == [[1, 2], [3, 4, 5]]     # the docstring's examples
        @test Logjam.subtours([3, 1, 4, 2]) == [[1, 3, 4, 2]]
        @test Logjam.subtours(Int32[2, 1]) == [[1, 2]] && Logjam.subtours(view([3, 1, 2], :)) == [[1, 3, 2]]
    end

    @testset "TSP == Lecture 5.1's on Ex. 2's ten cities, and subtours on its rounds" begin
        D = _wp2_nc10()
        r = _wp2_tsppair(l51, D)
        @test r.cost && r.tour && r.cycle && r.rounds
        @test round(r.J.TC, digits = 2) == 487.69          # the brute force of Code block 5 (5-rte-1.qmd:525-527)
        @test keys(r.J) == keys(r.L) == (:TC, :tour, :rounds) && all(rd -> keys(rd) == (:TC, :S), r.J.rounds)
        @test r.J.tour[1] == r.J.tour[end] == 1
        # each round a lower bound, rising to the optimum
        @test all(r.J.rounds[k+1].TC ≥ r.J.rounds[k].TC * (1 - 1e-9) for k in 1:length(r.J.rounds)-1)
        # subtours on the successor vectors of the lecture's own rounds
        for rd in r.L.rounds
            succ = _wp2_succ(rd.S)
            @test Logjam.subtours(succ) == _wp2_call(l51, :subtours, succ) == rd.S
        end
    end

    @testset "TSP == Lecture 5.1's on Ex. 3(d)'s six nodes, whose optimum is unique" begin
        r = _wp2_tsppair(l51, WP2_D6)
        @test r.cost && r.cycle && r.rounds
        @test r.J.tour == r.L.tour                         # asymmetric costs: the same tour, the same direction
        @test length(r.J.rounds) == 1                      # the assignment problem's solution is already a tour
    end

    @testset "TSP == Lecture 5.1's on Ex. 4(c)'s 100 counties" begin
        r = _wp2_tsppair(l51, _wp2_nc100())
        @test r.cost && r.tour && r.cycle && r.rounds
    end

    @testset "TSP == Lecture 5.1's on Code block 24's random instances" begin
        Ds = _wp2_disks(lecture51_module(LECTURE51_DISK))
        for m in (2, 5, 10, 20, 50)
            Dm = m == 50 ? Ds[m][1:2] : Ds[m]             # m = 50: the first two of its 20
            rs = [_wp2_tsppair(l51, D) for D in Dm]
            @test all(r -> r.cost, rs)
            @test all(r -> r.tour, rs)
            @test all(r -> r.cycle, rs)
            @test all(r -> r.rounds, rs)
        end
    end

    @testset "TSP == Lecture 5.3's copy on its 31 points" begin
        r = _wp2_tsppair(l53, _wp2_nc31())
        @test r.cost && r.tour && r.cycle && r.rounds
        @test round(r.J.TC, digits = 2) == 1131.60         # 5-rte-3.qmd:883-884, "the optimal tour by 5.1's TSP"
    end

    @testset "TSP's input checks, and a wrong argument is a MethodError without the hint" begin
        @test_throws ArgumentError Logjam.TSP([0 1 2; 1 0 3])
        @test_throws ArgumentError Logjam.TSP(zeros(1, 1))
        @test Logjam.TSP([0 1; 1 0]).TC == 2.0 && Logjam.TSP([0 1; 1 0]).tour == [1, 2, 1]
        e = try Logjam.TSP("not a matrix") catch err err end
        @test e isa MethodError && !occursin("using JuMP, HiGHS", sprint(showerror, e))
    end

    @testset "binpack == Lecture 2.7's on Ex. 8 and Code blocks 28 and 29" begin
        r = _wp2_binpair(l27, WP2_VB, 10)
        @test r.count && r.once && r.fits && r.fields && r.same
        @test r.J.used == 6 == ceil(Int, sum(WP2_VB) / 10)   # the caption: the counting bound is attained
        @test r.J.status == JuMP.OPTIMAL
        for m in (20, 50, 100, 200)                          # Code block 28
            r = _wp2_binpair(l27, _wp2_seed9(m), 10)
            @test r.count && r.once && r.fits && r.fields && r.same
        end
        r = _wp2_binpair(l27, _wp2_seed9(200), 10; gap = 0.02)   # Code block 29's 2%
        @test r.count && r.once && r.fits && r.fields && r.same
    end

    @testset "binpack == Lecture 5.3's copy on its route times" begin
        v, V = WP2_TJ .+ WP2_TL, 10 + WP2_TL                 # Code block 46 (5-rte-3.qmd:2616)
        r = _wp2_binpair(l53, v, V)
        @test r.count && r.once && r.fits && r.fields && r.same
        @test r.J.used == 4 == ceil(Int, sum(v) / V)         # the bound, and first-fit decreasing's 4 (@tbl-ffd-steps)
    end

    @testset "binpack's input check" begin
        @test_throws ArgumentError Logjam.binpack([3, 12], 10)
        @test Logjam.binpack([3, 7, 5], 10).used == 2
    end

    @testset "snapvals on JuMP variables == snapvals(value.(x)); the numeric method unchanged" begin
        # Lecture 4.3's production-inventory model (4-net-3.qmd:409-421, ISE 361 F25 5-MIP-4 cell 16) on its Ex. 3's
        # data (Code block 6, :942-953), its variables kept
        u = [50 0 50; 60 0 0]; d = [20, 10, 15]; cᵖ = [200, 800]; h = 0.3/12; cⁱ = cumsum(cᵖ)*h
        y⁰ = [0, 0]; yᵗ⁺¹ = [35, 0]; m, t = length(cᵖ), length(d)
        LBʸ = [y⁰ zeros(m, t-1) yᵗ⁺¹]; UBʸ = [y⁰ fill(Inf, m, t-1) yᵗ⁺¹]
        model = JuMP.Model(HiGHS.Optimizer)
        JuMP.@variable(model, 0 ≤ x[i=1:m, j=1:t] ≤ u[i,j])
        JuMP.@variable(model, LBʸ[i,j] ≤ y[i=1:m, j=1:t+1] ≤ UBʸ[i,j])
        JuMP.@objective(model, Min, sum(cᵖ[i]*x[i,j] for i=1:m, j=1:t) + sum(cⁱ[i]*y[i,j] for i=1:m, j=2:t+1))
        JuMP.@constraint(model, [i=1:m-1, j=1:t], -x[i,j] + x[i+1,j] - y[i,j] + y[i,j+1] == 0)
        JuMP.@constraint(model, [j=1:t], -x[m,j] - y[m,j] + y[m,j+1] == -d[j])
        JuMP.set_silent(model); JuMP.optimize!(model)
        @test JuMP.termination_status(model) == JuMP.OPTIMAL
        @test snapvals(x) == snapvals(JuMP.value.(x)) && snapvals(y) == snapvals(JuMP.value.(y))
        @test typeof(snapvals(x)) == typeof(snapvals(JuMP.value.(x))) == Matrix{Float64} && size(snapvals(y)) == (2, 4)
        @test snapvals(x; atol = 0.5) == snapvals(JuMP.value.(x); atol = 0.5)
        @test snapvals(y[2, 2]) === only(snapvals([JuMP.value(y[2, 2])])) === snapvals(y)[2, 2]

        # Lecture 2.7's Code block 2, node 0 of its branch and bound (2-loc-7.qmd:700-707), and its Code block 1's
        # call on two scalars (:690)
        lp = JuMP.Model(HiGHS.Optimizer)
        JuMP.@variable(lp, 0 <= x₁); JuMP.@variable(lp, 0 <= x₂)
        JuMP.@objective(lp, Max, 6x₁ + 8x₂)
        JuMP.@constraint(lp, 2x₁ + 3x₂ <= 11); JuMP.@constraint(lp, 2x₁ <= 7)
        JuMP.set_silent(lp); JuMP.optimize!(lp)
        @test snapvals([x₁, x₂]) == snapvals(JuMP.value.([x₁, x₂])) && snapvals([x₁, x₂]) ≈ [3.5, 4/3]
        @test snapvals(x₂) isa Float64 && snapvals(x₂) == only(snapvals([JuMP.value(x₂)]))
        @test snapvals(x₂; atol = 0.5) == 1.0 == only(snapvals([JuMP.value(x₂)]; atol = 0.5))
        # the same variables in a DenseAxisArray
        da = JuMP.Containers.DenseAxisArray([x₁, x₂], [:a, :b])
        @test snapvals(da) == snapvals(JuMP.value.(da)) == snapvals([x₁, x₂])

        # Lecture 2.7's bin packing model on Ex. 8, its binaries kept
        M = eachindex(WP2_VB)
        bp = JuMP.Model(HiGHS.Optimizer); JuMP.set_silent(bp)
        JuMP.@variable(bp, yb[M], Bin); JuMP.@variable(bp, xb[M, M], Bin)
        JuMP.@objective(bp, Min, sum(yb))
        JuMP.@constraint(bp, [i ∈ M], 10 * yb[i] >= sum(WP2_VB[j] * xb[i, j] for j ∈ M))
        JuMP.@constraint(bp, [j ∈ M], sum(xb[i, j] for i ∈ M) == 1)
        JuMP.optimize!(bp)
        @test snapvals(xb) == snapvals(JuMP.value.(xb)) && snapvals(yb) == snapvals(JuMP.value.(yb))
        @test Int.(snapvals(xb)) == Int.(snapvals(JuMP.value.(xb)))    # 4.3's and 4.4's `Int.(snapvals(value.(z)))`

        # values a solver leaves near an integer, held there: the numeric method's own pin, through variables
        fx = JuMP.Model(HiGHS.Optimizer); JuMP.set_silent(fx)
        JuMP.@variable(fx, z[1:3]); JuMP.fix.(z, [2.9999999997, 1e-12, 0.5]); JuMP.optimize!(fx)
        @test JuMP.value.(z) == [2.9999999997, 1e-12, 0.5]
        @test snapvals(z) == snapvals(JuMP.value.(z)) == [3.0, 0.0, 0.5]
        @test snapvals(z[1]) === 3.0 && snapvals(z[2]) === 0.0

        # what neither takes, neither takes: a SparseAxisArray (the TSP's x), whose values have no `size`
        sp = JuMP.Model(HiGHS.Optimizer); JuMP.set_silent(sp)
        JuMP.@variable(sp, 0 ≤ s[i ∈ 1:3, j ∈ 1:3; i ≠ j] ≤ 1); JuMP.optimize!(sp)
        @test_throws ErrorException snapvals(s)
        @test_throws ErrorException snapvals(JuMP.value.(s))

        # the numeric method is core's and returns what it returned
        @test which(snapvals, Tuple{Vector{Float64}}).module === Logjam
        @test which(snapvals, Tuple{typeof(x)}).module === _WP2_JEXT && which(snapvals, Tuple{typeof(x₁)}).module === _WP2_JEXT
        @test snapvals([2.9999999997, 1e-12, 0.5]) == [3.0, 0.0, 0.5]
        @test length(methods(snapvals)) == 3
    end
end

# Each case is a fresh process, the way a lecture runs, started with this session's own flags so the precompiled
# packages match (as test_extensions_c5.jl's `_c5_child`).
function _wp2_child(code)
    out = IOBuffer()
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
    ok = success(pipeline(cmd; stdout = out, stderr = out))
    return ok, String(take!(out))
end

# each function called as a lecture calls it, and what it throws: one line each, `name|type|hinted`
const _WP2_PROBE = """
function probe(name, f)
    try
        f()
        println(name, "|NOERROR|false")
    catch e
        println(name, "|", typeof(e), "|", occursin("Run: using JuMP, HiGHS", sprint(showerror, e)))
    end
end
probe("TSP", () -> Logjam.TSP([0 1; 1 0]))
probe("binpack", () -> Logjam.binpack([1, 2], 3))
probe("binpack(; gap)", () -> Logjam.binpack([1, 2], 3; gap = 0.01))
println("subtours=", Logjam.subtours([2, 1, 3]))
println("snapvals=", snapvals([2.9999999997, 1e-12]))
println("ext=", Base.get_extension(Logjam, :LogjamJuMPExt) !== nothing)
"""

@testset "WP2 (v0.3.1) fresh processes: what loads the optimization extension, and what a call without it says" begin
    parse_out(out) = Dict(split(l, '|')[1] => (split(l, '|')[2], split(l, '|')[3] == "true")
                          for l in split(out, '\n') if count('|', l) == 2)
    names = ("TSP", "binpack", "binpack(; gap)")

    @testset "using Logjam alone: it loads, subtours and snapvals work, TSP and binpack are a MethodError with the hint" begin
        ok, out = _wp2_child("using Logjam; " * _WP2_PROBE)
        @test ok && occursin("ext=false", out)
        @test occursin("subtours=[[1, 2], [3]]", out) && occursin("snapvals=[3.0, 0.0]", out)
        got = parse_out(out)
        for n in names
            @test get(got, n, ("", false)) == ("MethodError", true)
        end
    end

    @testset "using Logjam, JuMP (no HiGHS): the extension is not loaded, and the hint names both" begin
        ok, out = _wp2_child("using Logjam, JuMP; " * _WP2_PROBE)
        @test ok && occursin("ext=false", out)
        got = parse_out(out)
        for n in names
            @test get(got, n, ("", false)) == ("MethodError", true)
        end
    end

    @testset "JuMP and HiGHS with Logjam, before it or after: the extension loads and the models solve" begin
        solve = """
        m = JuMP.Model(HiGHS.Optimizer); JuMP.set_silent(m); JuMP.@variable(m, 0 <= w[1:2] <= 1)
        JuMP.@objective(m, Max, sum(w)); JuMP.optimize!(m)
        println("TC=", Logjam.TSP([0 1; 1 0]).TC, " used=", Logjam.binpack([1, 2], 3).used, " sv=", snapvals(w))
        """
        for line in ("using JuMP, HiGHS, Logjam", "using Logjam; using HiGHS, JuMP")
            ok, out = _wp2_child(line * "; " * _WP2_PROBE * solve)
            @test ok && occursin("ext=true", out) && occursin("TC=2.0 used=1 sv=[1.0, 1.0]", out)
            got = parse_out(out)
            @test get(got, "TSP", ("", true)) == ("NOERROR", false) && get(got, "binpack", ("", true)) == ("NOERROR", false)
        end
    end
end
