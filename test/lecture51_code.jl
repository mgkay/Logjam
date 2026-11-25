# lecture51_code.jl -- Lecture 5.1's own small functions, as its code blocks define them, kept as text so a test can
# evaluate them in a scratch module AFTER `using Logjam` (principle 9: a name Logjam newly exports must not break the
# lecture that defines it, in the order the lecture runs it; PCV K12).
#
# The text is 5-routing/5-rte-1.qmd's: the spacefilling curve rung (`sfcpos`, `tspspfillcur`, :900-928), the multi-start
# rung's `randtour` (:1273), Code block 24's `disk` (:2267-2276) and Code block 23's inline rejection loop
# (:2094-2103). Only the `# Model:` comment lines are dropped. Julia, not Logjam, owns every name below, so the test
# runs the definitions after `using Logjam` and calls them. (Logjam's own copies of the four were removed before the
# release, rulings RTE27, IN1 and IN3; these definitions are what test_k12_pins.jl pins.)

const LECTURE51_SFC = raw"""
function sfcpos(x, y, k = 8)
    if k == 0
        return 0.5                     # center of the last square
    end
    VN = [0 1; 3 2]                    # order the quadrants are visited
    q = VN[min(floor(Int, 2x + 1), 2), min(floor(Int, 2y + 1), 2)]
    s = sfcpos(2abs(x - 0.5), 2abs(y - 0.5), k - 1)  # within q
    if q == 1 || q == 3
        s = 1 - s                      # quadrants 1 and 3 run backward
    end
    θ = (q + s - 0.5) / 4
    return θ - floor(θ)
end

function tspspfillcur(XY, k = 8)
    x = XY[:, 1]
    y = XY[:, 2]
    if any(XY .< 0) || any(XY .> 1)    # scale to the unit square,
        w = max(maximum(x) - minimum(x), maximum(y) - minimum(y))
        x = (x .- minimum(x)) ./ w     # keeping the aspect ratio
        y = (y .- minimum(y)) ./ w
    end
    θ = sfcpos.(x, y, k)
    loc = sortperm(θ)                  # points in curve order
    i1 = findfirst(loc .== 1)
    return [loc[i1:end]; loc[1:i1-1]; 1]
end
"""

const LECTURE51_RANDTOUR = raw"""
using Random
randtour(n) = (tour = randperm(n); push!(tour, tour[1]))
"""

const LECTURE51_DISK = raw"""
function disk(m)                     # m points uniform in the unit disk,
    P = Matrix{Float64}(undef, 0, 2) # by rejection from the square
    while size(P, 1) < m
        p = 2 .* rand(1, 2) .- 1                  # <1>
        if sum(p .^ 2) < 1
            P = [P; p]
        end
    end
    return P
end
"""

# Code block 23's loop, seeded as the block seeds it, leaves its 300 points in `P`
const LECTURE51_INLINE_DISK = raw"""
Random.seed!(242)
mpts = 300                             # customers in the circle
P = Matrix{Float64}(undef, 0, 2)
while size(P, 1) < mpts                # uniform in the unit disk,
    global P                           # a script's `while`: soft scope
    p = 2 .* rand(1, 2) .- 1           # by rejection from the square
    if sum(p .^ 2) < 1
        P = [P; p]
    end
end
"""

# A scratch module that has done `using Logjam` and `using Random`, then runs the given lecture text, as a lecture does.
function lecture51_module(texts...)
    m = Module(:Lecture51)
    Core.eval(m, :(using Logjam))
    Core.eval(m, :(using Random))
    for t in texts
        include_string(m, t, "5-rte-1.qmd")
    end
    return m
end
