# RouteTools - Functions for vehicle routing problems

# =============================================================================
# Route Cost Calculations
# =============================================================================

"""
    segcost(loc, C) -> Vector

Calculate the cost of each segment in a location sequence.

Returns a vector of costs for traveling between consecutive locations.

# Arguments
- `loc`: Vector of location indices representing a sequence of stops.
- `C`: Cost matrix where C[i,j] is the cost from location i to location j.

# Returns
- Vector of segment costs of length `length(loc) - 1`.

# Example
```julia
C = [0 10 20; 10 0 15; 20 15 0]  # 3x3 cost matrix
loc = [1, 2, 3, 1]               # Tour visiting all nodes
segcost(loc, C)                  # Returns [10, 15, 20]
```
"""
segcost(loc, C) = map(i -> C[loc[i], loc[i+1]], 1:length(loc) - 1)

"""
    rteTC(rte, sh, C, tr=(b=[], e=[])) -> Float64

Calculate the total cost of a route.

Converts the route to a location sequence and sums all segment costs.

# Arguments
- `rte`: Route as a vector of shipment indices (each appears twice: pickup and delivery).
- `sh`: Shipments table with columns `b` (begin/pickup) and `e` (end/delivery) node indices.
- `C`: Cost matrix where C[i,j] is the cost from location i to location j.
- `tr`: Named tuple with depot locations `(b=start_nodes, e=end_nodes)`. Default empty.

# Returns
- Total route cost as the sum of all segment costs.

# Example
```julia
using DataFrames
C = Dgc(nodes[:, [:LON, :LAT]], nodes[:, [:LON, :LAT]])
sh = DataFrame(b=[1,2,3], e=[4,5,6])  # 3 shipments
rte = [1, 1, 2, 2, 3, 3]              # Visit each shipment sequentially
cost = rteTC(rte, sh, C)
```
"""
rteTC(rte, sh, C, tr=(b=[], e=[])) = sum(segcost(rte2loc(rte, sh, tr), C))

# =============================================================================
# Route Representation
# =============================================================================

"""
    isorigin(rte) -> Vector{Bool}

Determine which positions in a route are origins (first occurrence).

For routes with pickup-delivery pairs, each shipment index appears twice.
This function identifies which occurrence is the pickup (origin).

# Arguments
- `rte`: Route as a vector of shipment indices.

# Returns
- Boolean vector where `true` indicates first occurrence (origin/pickup).

# Example
```julia
rte = [1, 2, 1, 3, 2, 3]  # Pickup 1, pickup 2, deliver 1, pickup 3, deliver 2, deliver 3
isorigin(rte)             # Returns [true, true, false, true, false, false]
```
"""
isorigin(rte) = begin
    seen = Set()
    [i ∉ seen ? (push!(seen, i); true) : false for i in rte]
end

"""
    rte2loc(rte, sh, tr=(b=[], e=[])) -> Vector

Convert a route to a location sequence.

Maps shipment indices in a route to their actual node locations,
using pickup location for origins and delivery location for destinations.

# Arguments
- `rte`: Route as a vector of shipment indices.
- `sh`: Shipments table with columns `b` (begin/pickup) and `e` (end/delivery) node indices.
- `tr`: Named tuple with depot locations `(b=start_nodes, e=end_nodes)`. Default empty.

# Returns
- Vector of node indices representing the physical locations visited.

# Example
```julia
using DataFrames
sh = DataFrame(b=[10, 20], e=[15, 25])  # 2 shipments
rte = [1, 2, 1, 2]                       # Pickup both, then deliver both
rte2loc(rte, sh)                         # Returns [10, 20, 15, 25]
```
"""
rte2loc(rte, sh, tr=(b=[], e=[])) =
    vcat(tr.b, ifelse.(isorigin(rte), sh[rte, :b], sh[rte, :e]), tr.e)

# =============================================================================
# Route Improvement Procedures
# =============================================================================

"""
    twoopt(r, rTCh) -> Tuple{Vector, Float64}

Improve a route using the 2-opt neighborhood search.

The 2-opt algorithm iteratively reverses segments of the route to reduce
total cost. It continues until no improving moves are found.

# Arguments
- `r`: Initial route as a vector (can be TSP tour or shipment sequence).
- `rTCh`: Function that calculates route cost: `rTCh(route) -> cost`.

# Returns
- Tuple of (improved_route, total_cost).

# Example
```julia
C = [0 10 25 20; 10 0 15 30; 25 15 0 10; 20 30 10 0]
rTCh = r -> sum(C[r[i], r[i+1]] for i in 1:length(r)-1)
initial = [1, 2, 3, 4, 1]
improved, cost = twoopt(initial, rTCh)
```

# Notes
- For TSP: route should start and end at same node (depot).
- For pickup-delivery: ensure feasibility is maintained by the cost function.
"""
function twoopt(r, rTCh)
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

# =============================================================================
# Route Construction Procedures
# =============================================================================

"""
    mincostinsert(idx, rte, rteTCh) -> Tuple{Vector, Float64}

Insert a shipment into a route at the minimum cost position.

For pickup-delivery problems, both the pickup and delivery must be inserted.
This function tries all valid insertion positions and returns the best.

# Arguments
- `idx`: Shipment index to insert.
- `rte`: Current route as a vector of shipment indices.
- `rteTCh`: Function that calculates route cost: `rteTCh(route) -> cost`.

# Returns
- Tuple of (new_route, total_cost).

# Example
```julia
rteTCh = rte -> rteTC(rte, sh, C)
rte = [1, 1]          # Route with just shipment 1
rte, cost = mincostinsert(2, rte, rteTCh)  # Insert shipment 2
```

# Notes
- Returns `(route, Inf)` if no feasible insertion exists.
- The pickup must occur before the delivery in the route.
"""
function mincostinsert(idx, rte, rteTCh)
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

"""
    pairwisesavings(rteTCh, sh) -> Tuple{Vector{Int}, Vector{Int}, Vector{Float64}}

Calculate savings from combining pairs of single-shipment routes.

The savings value represents cost reduction from serving two shipments
on one route instead of two separate routes.

# Arguments
- `rteTCh`: Function that calculates route cost: `rteTCh(route) -> cost`.
- `sh`: Shipments DataFrame (used to determine number of shipments via `nrow`).

# Returns
- Tuple of (i_indices, j_indices, savings_values), sorted by savings (descending).

# Example
```julia
rteTCh = rte -> rteTC(rte, sh, C)
iˢ, jˢ, sˢ = pairwisesavings(rteTCh, sh)
# Pairs with highest savings are first
```

# Notes
- Only returns pairs with positive savings.
- Savings = cost([i,i]) + cost([j,j]) - cost(combined route).
"""
function pairwisesavings(rteTCh, sh)
    iᵒ, jᵒ, sᵒ = Int[], Int[], Float64[]
    for i = 1:nrow(sh)-1
        for j = i+1:nrow(sh)
            s = rteTCh([i, i]) + rteTCh([j, j]) - mincostinsert(i, [j, j], rteTCh)[2]
            s > 0 && (push!(iᵒ, i); push!(jᵒ, j); push!(sᵒ, s))
        end
    end
    sidx = sortperm(sᵒ, rev=true)
    return iᵒ[sidx], jᵒ[sidx], sᵒ[sidx]
end

"""
    savings(rteTCh, sh) -> Vector{Vector{Int}}

Construct routes for a Pickup and Delivery Problem (PDP) using a savings-ordered
insertion heuristic.

Unlike the standard Clarke-Wright algorithm (which concatenates routes at endpoints),
this function prioritizes merges based on savings values but executes them by
inserting all shipments from a source route into optimal positions within a
target route.

# Algorithm
1. Initialize a separate route for each shipment `[i, i]` (pickup, delivery).
2. Compute pairwise savings to prioritize merge attempts.
3. Iterate through pairs with highest savings:
   - Attempt to merge routes by inserting shipments from the shorter route
     into optimal positions in the longer route using `mincostinsert`.
   - If insertion satisfies constraints (finite cost), finalize the merge.

# Arguments
- `rteTCh`: Function that calculates route cost: `rteTCh(route) -> cost`.
          Should return `Inf` for infeasible routes (capacity, time windows, etc.).
- `sh`: Shipments DataFrame where each row is a shipment requiring pickup and delivery.

# Returns
- Vector of routes, where each route is a vector of shipment indices.

# Example
```julia
using DataFrames
sh = DataFrame(b=[1,2,3,4], e=[5,6,7,8])  # 4 shipments
C = Dgc(nodes, nodes)
rteTCh = rte -> rteTC(rte, sh, C)
routes = savings(rteTCh, sh)
```

# Notes
- This is a hybrid of savings-based prioritization and greedy insertion.
- Constraints are enforced through `rteTCh` returning `Inf`.
- Each shipment appears exactly twice in its route (pickup and delivery).
"""
function savings(rteTCh, sh)
    TC = nothing
    rte = [[i, i] for i in 1:nrow(sh)]
    inr = [1:nrow(sh);]
    iˢ, jˢ = pairwisesavings(rteTCh, sh)
    for (i, j) in zip(iˢ, jˢ)
        if inr[i] != inr[j]
            # Insert shmt from shorter (src) into longer (tgt) route
            inr_src, inr_tgt = length(rte[inr[i]]) < length(rte[inr[j]]) ?
                (inr[i], inr[j]) : (inr[j], inr[i])
            rte′ = copy(rte[inr_tgt])
            idx_src = unique(rte[inr_src])
            for k in idx_src
                rte′, TC = mincostinsert(k, rte′, rteTCh)
                if isinf(TC)
                    break
                end
            end
            if !isinf(TC)
                rte[inr_tgt] = rte′
                inr[idx_src] .= inr_tgt
                rte[inr_src] = []
            end
        end
    end
    return filter!(!isempty, rte)
end
