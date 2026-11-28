# LogjamJuMPExt: the methods that need JuMP and HiGHS, loaded when both are (X2). Built in v0.3.1's WP2:
# - `TSP`, Lecture 5.1's TSP formulation solved round by round (CR 45);
# - `binpack`, Lecture 2.7's bin packing model (E3);
# - `snapvals` on JuMP variables, reading their values itself, as ISE 361 F25 calls it (SV, X3).
# Each function is declared in core with its docstring (`TSP` in routetools.jl, `binpack` in loctools.jl, `snapvals`
# in displaytools.jl), so a call made without this extension is a MethodError that says what to load. `subtours`,
# which `TSP` calls and which needs neither package, is core's.
module LogjamJuMPExt

using Logjam: Logjam, subtours, snapvals
using JuMP: JuMP, Model, @variable, @objective, @constraint, set_silent, set_attribute, set_time_limit_sec,
            optimize!, termination_status, objective_value, value, relative_gap, solve_time
using HiGHS: HiGHS

# Lecture 5.1 Sec. 2's implementation rung (5-rte-1.qmd:697-731; 5.3's copy 5-rte-3.qmd:916-949), in its order.
# Changed from the lecture's text: `c` is typed; the two input checks are `ArgumentError`s, the second (two nodes or
# more) new, since with one node the assignment problem is infeasible and with none the loop would not end; and
# `rounds` is a typed vector of the same `(TC, S)` tuples where the lecture's is `[]`.
function Logjam.TSP(c::AbstractMatrix)
    size(c, 1) == size(c, 2) ||        # assumption (a): each pair's cost
        throw(ArgumentError("arc costs must be a square matrix"))
    size(c, 1) ≥ 2 || throw(ArgumentError("a tour needs two nodes or more"))
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
    set_attribute(model, "mip_rel_gap", 0.0)    # prove the tour optimal, not within HiGHS's default 0.01%
    rounds = @NamedTuple{TC::Float64, S::Vector{Vector{Int}}}[]
    while true
        optimize!(model)
        termination_status(model) == JuMP.OPTIMAL ||
            error(termination_status(model))
        succ = [findfirst(j -> j ≠ i && value(x[i, j]) > 0.5, V)  # a solved binary can be 0.9999999
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

# Lecture 2.7's bin packing model (2-loc-7.qmd:2260-2281; 5.3's copy 5-rte-3.qmd:2662-2683), in its order.
# Changed from the lecture's text: `v` and `V` are typed, and assumption (b), no object larger than a bin, is an
# `ArgumentError` where the lecture's model would be infeasible and `value` would throw.
function Logjam.binpack(v::AbstractVector{<:Real}, V::Real; tlim::Real = 60.0, gap::Real = 1e-4)
    isempty(v) || maximum(v) ≤ V ||
        throw(ArgumentError("an object of size $(maximum(v)) is larger than a bin of $V"))
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

# snapvals on JuMP variables (SV, X3): the values read here, then the numeric method, unchanged, so that
# `snapvals(x) == snapvals(value.(x))` for an array of variables. For one variable `value.(x)` is a number, which the
# numeric method does not take (it calls `Array`), so its value is snapped as a one-element array and returned alone.
Logjam.snapvals(x::AbstractArray{<:JuMP.AbstractVariableRef}; atol::Real = 1e-8) = snapvals(value.(x); atol = atol)
Logjam.snapvals(x::JuMP.AbstractVariableRef; atol::Real = 1e-8) = only(snapvals([value(x)]; atol = atol))

end # module
