# lecture52_code.jl -- Lecture 5.2's own routing functions, as its code blocks define them, kept as text
# so a test can evaluate them in a scratch module AFTER `using Logjam` (principle 9: a name Logjam newly
# exports must not break the lecture that defines it, in the order the lecture runs it; PCV K7a).
#
# The text is 5-routing/5-rte-2.qmd's: Code block 4 (`rtesegsum`), the minimum cost insertion rung
# (`mincostinsert_rte`, :938), the modified two-opt rung (`twoopt_rte`, :1160), insert and improve
# (`insertimprove`, :1211), the randomized savings rung (`randreorder`, `savings_ijs`, `randsavings`,
# :2131-2175), Code block 49 (`rte2idx`, `sh2rte`) and load formation (`loadform`, :2709). Only the
# `# Model:` comment lines are dropped. Julia, not Logjam, owns every name below, so the test runs the
# definitions after `using Logjam` and calls them.

const LECTURE52_CODE = raw"""
rtesegsum(r, x) = cumsum(x[r] .* ifelse.(isorigin(r), 1, -1))[1:end-1]

function mincostinsert_rte(idx, rte, rteTCh)
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

function twoopt_rte(r, rTCh)
    rᵒ, TCᵒ = copy(r), rTCh(r)
    done = false
    while !done
        done = true
        for i = 1:length(r)-1, j = i+1:length(r)
            r′ = vcat(r[1:i-1], reverse(r[i:j]), r[j+1:end])
            all(>(0), rtesegsum(r′, ones(maximum(r′)))) || continue
            TC = rTCh(r′)
            if TC < TCᵒ
                rᵒ, TCᵒ = r′, TC
                done = false
                break
            end
        end
        r = copy(rᵒ)
    end
    return rᵒ, TCᵒ
end

function insertimprove(L, rTCh)
    r = [L[1], L[1]]
    for k in L[2:end]
        r = mincostinsert_rte(k, r, rTCh)[1]
        r = twoopt_rte(r, rTCh)[1]
    end
    return r, rTCh(r)
end

function randreorder(ijs, p)            # each pair moved with prob. p
    mv = rand(length(ijs[1])) .< p
    return Tuple([v[.!mv]; v[mv]] for v in ijs)
end

function savings_ijs(rteTCh, sh, ijs)   # Logjam's savings, list given
    TC = nothing
    rte = [[i, i] for i in 1:nrow(sh)]
    inr = [1:nrow(sh);]
    iˢ, jˢ = ijs
    for (i, j) in zip(iˢ, jˢ)
        if inr[i] != inr[j]
            inr_src, inr_tgt =
                length(rte[inr[i]]) < length(rte[inr[j]]) ?
                (inr[i], inr[j]) : (inr[j], inr[i])
            rte′ = copy(rte[inr_tgt])
            idx_src = unique(rte[inr_src])
            for k in idx_src
                rte′, TC = mincostinsert(k, rte′, rteTCh)
                isinf(TC) && break
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

function randsavings(rteTCh, sh; p = 0.1, nruns = 30)
    ijs = pairwisesavings(rteTCh, sh)
    rteᵒ, TCᵒ = nothing, Inf
    for k = 1:nruns
        rte = savings_ijs(rteTCh, sh, randreorder(ijs, p))
        rte = [twoopt_rte(r, rteTCh)[1] for r in rte]
        TC = sum(rteTCh.(rte))
        if TC < TCᵒ
            rteᵒ, TCᵒ = rte, TC
        end
    end
    return rteᵒ, TCᵒ
end

rte2idx(r::AbstractVector{<:Integer}) = r[isorigin(r)]
rte2idx(R::AbstractVector{<:AbstractVector}) = rte2idx.(R)
function sh2rte(idx, R)
    idx1 = setdiff(idx, rte2idx(reduce(vcat, R; init = Int[])))
    return [R; [[k, k] for k in idx1]], idx1
end

function loadform(rteTCh, sh)
    R = [twoopt_rte(r, rteTCh)[1] for r in savings(rteTCh, sh)
         if length(r) > 2]                  # multi-shipment routes
    return sh2rte(1:nrow(sh), R)    # the others, single-shipment routes
end
"""

# a scratch module that does what the lecture does: `using Logjam`, then the definitions in the order the
# lecture runs them. Returns the module; call its functions with `lecture52_call` (new world age).
function lecture52_module(name::Symbol; with = ("using Logjam", "using DataFrames", "using Random"))
    m = Module(name)
    for u in with
        Core.eval(m, Meta.parse(u))
    end
    for ex in Meta.parseall(LECTURE52_CODE).args
        ex isa LineNumberNode || Core.eval(m, ex)
    end
    return m
end
lecture52_call(m::Module, f::Symbol, args...; kw...) = Base.invokelatest(getfield(m, f), args...; kw...)
