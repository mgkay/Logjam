# =============================================================================
# Facility Location Optimization
# =============================================================================

"""
    ufladd(k, C; y=Int[], p=nothing) -> (Vector{Int}, Float64)

Greedy ADD construction heuristic for uncapacitated facility location.

Iteratively adds facilities that provide the greatest cost reduction until no
improvement is possible or p facilities are selected.

# Arguments
- `k`: Fixed costs. Scalar (same cost for all) or vector (one per site).
- `C`: n×m cost matrix where C[i,j] is cost of serving customer j from facility i.
- `y`: Initial facility set (default: empty, start from scratch).
- `p`: Maximum facilities to select (default: nothing, no limit).

# Returns
- `(y, TC)`: Selected facility indices and total cost.

# Example
```julia
k = [10, 10, 10]
C = [2 5 4; 4 1 3; 5 4 2]
y, TC = ufladd(k, C)  # → ([1, 2], 21.0)
```

# References
- M.G. Kay, *Facility Location* (course notes), NC State University
"""
function ufladd(k, C; y = Int[], p::Union{Int, Nothing} = nothing)
    if k isa Number
        k = fill(k, size(C, 1))
    end
    fTC(y) = sum(k[y]) + sum(minimum(C[y, :], dims=1))
    TCᵒ = isempty(y) ? Inf : fTC(y)
    N = 1:size(C, 1)
    done = false
    while !done
        TC, i = Inf, nothing
        for i′ = setdiff(N, y)
            TC′ = fTC(vcat(y, i′))
            if TC′ < TC
                TC, i = TC′, i′
            end
        end
        if (p === nothing && TC < TCᵒ) || (p isa Int && length(y) < p)
            TCᵒ, y = TC, push!(y, i)
        else
            done = true
        end
    end
    return y, TCᵒ
end

"""
    ufldrop(k, C; y=nothing, p=nothing) -> (Vector{Int}, Float64)

Greedy DROP construction heuristic for uncapacitated facility location.

Starts with all facilities open and iteratively drops the one providing the
greatest cost reduction until no improvement or p facilities remain.

# Arguments
- `k`: Fixed costs. Scalar (same cost for all) or vector (one per site).
- `C`: n×m cost matrix where C[i,j] is cost of serving customer j from facility i.
- `y`: Initial facility set (default: all facilities).
- `p`: Target number of facilities (default: nothing, drop until no improvement).

# Returns
- `(y, TC)`: Selected facility indices and total cost.

# Example
```julia
k = [10, 10, 10]
C = [2 5 4; 4 1 3; 5 4 2]
y, TC = ufldrop(k, C)  # → ([1, 2], 21.0)
```

# References
- M.G. Kay, *Facility Location* (course notes), NC State University
"""
function ufldrop(k, C; y = nothing, p::Union{Int, Nothing} = nothing)
    if k isa Number
        k = fill(k, size(C, 1))
    end
    fTC(y) = sum(k[y]) + sum(minimum(C[y, :], dims=1))
    if y === nothing
        y = collect(1:size(C, 1))
    end
    TCᵒ = fTC(y)
    done = false
    while !done && length(y) > 1
        TC, i = Inf, nothing
        for i′ in y
            TC′ = fTC(setdiff(y, i′))
            if TC′ < TC
                TC, i = TC′, i′
            end
        end
        if (p === nothing && TC < TCᵒ) || (p isa Int && length(y) > p)
            TCᵒ, y = TC, setdiff(y, i)
        else
            done = true
        end
    end
    return y, TCᵒ
end

"""
    uflxchg(k, C, y) -> (Vector{Int}, Float64)

Pairwise EXCHANGE improvement heuristic for uncapacitated facility location.

Performs steepest descent pairwise swaps (close one facility, open another)
until local optimum is reached.

# Arguments
- `k`: Fixed costs. Scalar (same cost for all) or vector (one per site).
- `C`: n×m cost matrix where C[i,j] is cost of serving customer j from facility i.
- `y`: Initial facility set.

# Returns
- `(y, TC)`: Improved facility indices and total cost.

# Example
```julia
k = [10, 10, 10]
C = [2 5 4; 4 1 3; 5 4 2]
y, TC = uflxchg(k, C, [1, 3])  # Improve initial solution
```

# References
- M.G. Kay, *Facility Location* (course notes), NC State University
"""
function uflxchg(k, C, y::Vector{Int})
    if k isa Number
        k = fill(k, size(C, 1))
    end
    fTC(y) = sum(k[y]) + sum(minimum(C[y, :], dims=1))
    N = 1:size(C, 1)
    TCᵒ = fTC(y)
    done = false

    # Helper function to swap facilities
    function swap!(y::Vector{Int}, i::Int, j::Int)
        deleteat!(y, findfirst(==(i), y))
        push!(y, j)
    end

    function revert!(y::Vector{Int}, i::Int, j::Int)
        deleteat!(y, findfirst(==(j), y))
        push!(y, i)
    end

    while length(y) > 1 && !done
        TC, i, j = Inf, nothing, nothing
        for i′ in y
            for j′ in setdiff(N, y)
                swap!(y, i′, j′)
                TC′ = fTC(y)
                if TC′ < TC
                    TC, i, j = TC′, i′, j′
                end
                revert!(y, i′, j′)
            end
        end
        if TC < TCᵒ
            TCᵒ = TC
            swap!(y, i, j)
        else
            done = true
        end
    end
    return y, TCᵒ
end

"""
    ufl(k, C; verbose=true) -> (Vector{Int}, Float64)

Hybrid UFL heuristic combining ADD, DROP, and EXCHANGE procedures.

Iterates through ADD → EXCHANGE → (ADD vs DROP, take best) until no improvement.
Typically produces high-quality solutions for uncapacitated facility location problems.

# Arguments
- `k`: Fixed costs. Scalar (same cost for all) or vector (one per site).
- `C`: n×m cost matrix where C[i,j] is cost of serving customer j from facility i.
- `verbose`: Print iteration costs (default: true).

# Returns
- `(y, TC)`: Best facility indices and total cost.

# Example
```julia
k = [10, 10, 15]
C = [0 3 7; 3 0 4; 7 4 0]
y, TC = ufl(k, C)  # Prints: Add: 13.0, Xchg: 13.0
```

# References
- M.G. Kay, *Facility Location* (course notes), NC State University
"""
function ufl(k, C; verbose = true)
    y′, TC′ = ufladd(k, C)
    verbose && println("  Add: ", TC′)
    y, TC = y′, TC′
    done = false
    while !done
        y, TC = uflxchg(k, C, y′)
        verbose && println(" Xchg: ", TC)
        if Set(y) !== Set(y′)
            y′, TC′ = ufladd(k, C; y)
            verbose && println("  Add: ", TC′)
            y′′, TC′′ = ufldrop(k, C; y)
            verbose && println(" Drop: ", TC′′)
            if TC′′ < TC′
                y′, TC′ = y′′, TC′′
            end
            if TC′ >= TC
                done = true
            end
        else
            done = true
        end
    end
    return y, TC
end

"""
    pmedian(p, C; verbose=true) -> (Vector{Int}, Float64)

p-median facility location (fixed number of facilities, no fixed costs).

Selects exactly p facilities to minimize total transportation cost. Uses ufladd
with k=0 to select p facilities, then uflxchg to improve the solution.

# Arguments
- `p`: Number of facilities to select.
- `C`: n×m cost matrix where C[i,j] is cost of serving customer j from facility i.
- `verbose`: Print iteration costs (default: true).

# Returns
- `(y, TC)`: Selected facility indices and total cost.

# Example
```julia
C = [0 3 7; 3 0 4; 7 4 0]
y, TC = pmedian(2, C; verbose=false)  # Select 2 facilities
```

# References
- M.G. Kay, *Facility Location* (course notes), NC State University
"""
function pmedian(p, C; verbose = true)
    1 <= p <= size(C, 1) || error("p must be between 1 and $(size(C, 1))")
    y = ufladd(0, C; p = p)[1]
    verbose && println(" p-median ADD: $(p) facilities selected")
    return uflxchg(0, C, y)
end

# =============================================================================
# Utility Functions
# =============================================================================

"""
    randX(P::AbstractMatrix, n::Int=1) -> Matrix

Generate n random points within the bounding box of point set P.

Useful for generating random facility locations for optimization problems.

# Arguments
- `P`: m×d matrix of m points in d dimensions.
- `n`: Number of random points to generate (default: 1).

# Returns
- n×d matrix of random points, uniformly distributed within min/max of each dimension.

# Example
```julia
P = [0 0; 2 0; 2 3]
X = randX(P, 5)  # 5 random points in [0,2] × [0,3]
```
"""
function randX(P::AbstractMatrix, n::Int=1)
    n >= 1 || error("n must be positive")
    size(P, 1) >= 1 || error("P must have at least one point")

    if size(P, 1) == 1
        return repeat(P, n)
    else
        mins = minimum(P, dims=1)
        ranges = maximum(P, dims=1) - mins
        return mins .+ rand(n, size(P, 2)) .* ranges
    end
end
