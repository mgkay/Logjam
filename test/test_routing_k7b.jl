# test_routing_k7b.jl -- tests added by PCV K7b (the route cost and the location sequence): principle 9
# checks against Lecture 5.3's own inline definitions (run in a scratch module after `using Logjam`, as
# K7a did for 5.2's), and the tests of each K7b item that the K2 testsets do not hold. Each testset is
# tagged with the IDs of the items it belongs to.

using Test
using Logjam
using DataFrames
using Random

@isdefined(RPIN_SH30) || include(joinpath(@__DIR__, "routing_pin_cases.jl"))
@isdefined(LECTURE53_CODE) || include(joinpath(@__DIR__, "lecture53_code.jl"))

# 5.3's NC30 instance with MATLAB's distances: makeRouting3.m's 30 shipments from the depot (node 1)
function _k7b_nc30()
    d = _readoracle("routing_53_vrp"); D = d["D"]; n = size(D, 1) - 1
    q, s = _fvec(d, "q"), _fvec(d, "s")
    return (; d, D, n, q, s, sh = DataFrame(b = fill(1, n), e = 2:n+1, q = q, s = s))
end

# the checked route cost as 5.3's `TC, Xflg, out = rteTC_vrp(...)` is called
_vrp(args...) = Tuple(rteTC(args...; full = true))

# two outputs of the checked route cost agree: the cost and flag exactly (the same additions in the same
# order), every column of `out` to 1e-9 (infinite window bounds equal)
function _k7b_same(a, b; tol = 1e-9)
    (TCa, fa, oa), (TCb, fb, ob) = a, b
    (isequal(TCa, TCb) || isapprox(TCa, TCb; atol = tol, rtol = tol)) && fa == fb || return false
    names(oa) == names(ob) && size(oa) == size(ob) || return false
    return all(all(isapprox.(Float64.(oa[!, c]), Float64.(ob[!, c]); atol = tol, rtol = tol)) for c in names(oa))
end

# routes of 1 to `kmax` of the 30 customers: loaded in one order and unloaded in the same, in the reverse,
# and in a shuffle (which often returns to the depot midway)
function _k7b_routes(rng, kmax; nroutes = 150)
    R = Vector{Int}[]
    for _ in 1:nroutes
        idx = randperm(rng, 30)[1:rand(rng, 1:kmax)]
        push!(R, vcat(idx, idx), vcat(idx, reverse(idx)), shuffle(rng, vcat(idx, idx)))
    end
    return R
end

@testset "K7b" begin

@testset "[P9, N20] rte2loc and isorigin are typed and return the values they returned" begin
    sh = DataFrame(b = [10, 20], e = [15, 25])
    rte = [1, 2, 1, 2]
    @test rte2loc(rte, sh) isa Vector{Int}                       # v0.2.8: Vector{Any}
    @test rte2loc(rte, sh) == [10, 20, 15, 25]
    @test rte2loc(rte, sh, (b = 3, e = 4)) isa Vector{Int}
    @test rte2loc(rte, sh, (b = 3, e = 4)) == [3, 10, 20, 15, 25, 4]
    @test rte2loc(rte, sh, (b = [3], e = [4])) isa Vector{Int}
    @test rte2loc(rte, sh, (b = [], e = [])) == [10, 20, 15, 25]    # a truck given as empty `Any` vectors still works
    @test isorigin(rte) isa Vector{Bool} && isorigin(rte) == [true, true, false, false]
    @test isorigin(Int[]) == Bool[]
    @test isorigin(["a", "b", "a", "b"]) == [true, true, false, false]   # any hashable label
    # the course's own calls, from the pins: every location sequence equal to the pinned one is checked by
    # test_routing_pins.jl; here the element type of a depot route and of a truck given as scalars
    @test eltype(rte2loc([1, 2, 2, 1], DataFrame(b = [1, 1], e = [2, 3]), (b = 1, e = 1))) == Int
end

@testset "[CR 42] the degenerate-location rule: a depot route that returns to the depot midway is more than one route" begin
    # Matlog's rte2loc.m: with the truck's begin and end the same location, a location sequence that is at
    # that location, leaves it and is back and leaves again is NaN (degenerate); `Logjam._isdegenerate`
    # takes the route's own sequence (without the truck's two)
    tr = (b = 1, e = 1)
    sh = DataFrame(b = [1, 1, 1], e = [2, 3, 4])
    deg(r, t = tr) = Logjam._isdegenerate(rte2loc(r, sh), t)
    @test !deg([1, 2, 3, 3, 2, 1])               # loaded at the depot, delivered: leaves once, returns once
    @test !deg([1, 1])                           # one shipment: depot, then its customer
    @test !deg([1, 2, 2, 1])
    @test deg([1, 1, 2, 2])                      # 1 -> 2, back to the depot, 1 -> 3: two trips
    @test deg([1, 1, 2, 3, 3, 2])                # a second trip with a delivery before the last loading
    @test !deg([1, 2, 3, 3, 2, 1], (b = 1, e = 4))    # the truck's ends differ: the rule does not apply
    @test !deg([1, 1, 2, 2], (Kwt = 25,))             # a truck without locations
    @test !deg([1, 1, 2, 2], (b = 1,))
    # the sequence ends at the depot but never leaves... or starts away and passes it: Matlog's k = [1, -1]
    sh2 = DataFrame(b = [2, 1], e = [3, 4])
    @test Logjam._isdegenerate(rte2loc([1, 2, 2, 1], sh2), tr) == true      # 2 -> 1 -> 4 -> 3: through the depot midway
    # a vector truck location (the 5.2 form `(b = [1], e = [1])`) is read the same
    @test deg([1, 1, 2, 2], (b = [1], e = [1]))
    @test !deg([1, 2, 3, 3, 2, 1], (b = [1], e = [1]))
end

@testset "[P9, CR 42, CR 59, S8] rteTC(...; full = true) equals Lecture 5.3's rteTC_vrp on the course's inputs" begin
    m = lecture53_module(:L53_a)
    m′ = lecture53_module(:L53_b; scanfirst = true)               # HW 5's key defines scanTW first
    lec(args...) = lecture53_call(m, :rteTC_vrp, args...)
    lec′(args...) = lecture53_call(m′, :rteTC_vrp, args...)
    flags = Int[]
    chk(r, sh, C, tr) = (a = _vrp(r, sh, C, tr); b = lec(r, sh, C, tr);
                         push!(flags, a[2]); _k7b_same(a, b) && _k7b_same(a, lec′(r, sh, C, tr)))
    # slide 254 (5.3 Ex. 4): the route and its six orders
    T5 = zeros(4, 4); T5[1, 2] = 1; T5[2, 3] = 2; T5[3, 4] = 1; T5[4, 1] = 1
    sh5 = DataFrame(b = 1, e = [2, 3, 4], tU = 0.0, temin = [8, 12, 15], temax = [11, 14, 18])
    tr5 = (b = 1, e = 1, tbmin = 6, tbmax = 18, temin = 18, temax = 24)
    for p in ([1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1])
        @test chk([p; p], sh5, T5, tr5)
    end
    @test _vrp([1, 2, 3, 1, 2, 3], sh5, T5, tr5)[1:2] == (8.0, 1)
    # 5.3 Ex. 3: the 60 routes of three 10 t shipments on a 25 t truck, load mix by load mix
    d1 = _readoracle("routing_52_ex1")
    sh3 = DataFrame(b = _ivec(d1, "b"), e = _ivec(d1, "e"), q = [10, 10, 10])
    r60 = unique(shuffle.(Ref(Xoshiro(1)), fill([1, 1, 2, 2, 3, 3], 4000)))
    r60 = [r for r in r60 if all(>(0), cumsum(ifelse.(isorigin(r), 1, -1))[1:end-1])]
    @test length(r60) == 60
    for r in r60
        @test chk(r, sh3, d1["D"], (Kwt = 25,))
    end
    # the routes that fit load mix by load mix are those whose weight on board never passes 25 t (the lecture
    # counts them by `rtesegsum` as well, "again by the peaks")
    @test count(r -> isfinite(_vrp(r, sh3, d1["D"], (Kwt = 25,))[1]), r60) ==
          count(r -> maximum(cumsum(10 .* ifelse.(isorigin(r), 1, -1))[1:end-1]) <= 25, r60)
    # 5.3 Ex. 2 to 4 and 6 on NC30: capacity, maxTC, windows with loading and unloading, the time matrix
    # with five minutes on its diagonal (Ex. 6)
    c = _k7b_nc30(); rng = Xoshiro(20261120)
    trc = (b = 1, e = 1, Kwt = 25, Kcu = 2750)
    sh6 = DataFrame(b = fill(1, c.n), e = 2:c.n+1, q = c.q, s = c.s, tU = c.q * 30/60,
                    temin = [fill(7, 15); fill(13, 15)], temax = [fill(17, 15); fill(23, 15)])
    T6 = c.D / 50 .+ 5/60
    sh7 = copy(sh6); sh7.tL = fill(0.1, c.n); sh7.tbmin = fill(6.0, c.n); sh7.tbmax = fill(20.0, c.n)
    R = _k7b_routes(rng, 12)
    for r in R
        @test chk(r, c.sh, c.D, trc)                                       # Ex. 2
        @test chk(r, c.sh, c.D, merge(trc, (maxTC = 600,)))                # Ex. 4
        @test chk(r, c.sh, c.D, merge(trc, (Kcu = 400,)))                  # a cube that binds
        @test chk(r, c.sh, c.D, (Kwt = 25.0,))                             # no truck locations
        @test chk(r, sh6, T6, trc)                                         # Ex. 6
        @test chk(r, sh6, T6, merge(trc, (maxTC = 10,)))
        @test chk(r, sh7, T6, merge(trc, (tbmin = 5, tbmax = 12, temin = 14, temax = 26)))
        @test chk(r, sh6, T6, (Kwt = 25,))
    end
    # the instances reach every exit flag, so the comparison is not vacuous
    @test Set(flags) == Set([1, -1, -2, -3, -4, -5])
    # a vector of routes
    Rv = R[1:60]
    a, b = _vrp(Rv, sh6, T6, trc), lec(Rv, sh6, T6, trc)
    @test a[2] == b[2] && all(_k7b_same((a[1][i], a[2][i], a[3][i]), (b[1][i], b[2][i], b[3][i])) for i in 1:60)
end

@testset "[P9, CR 42, S8] Logjam.scanTW equals Lecture 5.3's scanTW" begin
    m = lecture53_module(:L53_scan)
    rng = Xoshiro(7)
    for _ in 1:300
        n = rand(rng, 2:9)
        t = [0.0; rand(rng, n - 1) * 3]; u = rand(rng, n) * 0.5
        ℓ = cumsum(rand(rng, n) * 2); h = ℓ .+ rand(rng, n) * 3
        rand(rng) < 0.3 && (ℓ[rand(rng, 1:n)] = -Inf); rand(rng) < 0.3 && (h[rand(rng, 1:n)] = Inf)
        a, b = Logjam.scanTW(t, u, ℓ, h), lecture53_call(m, :scanTW, t, u, ℓ, h)
        @test isequal(a, b)
    end
    @test Logjam.scanTW([0, 1, 2, 1, 1], zeros(5), [6, 8, 12, 15, 18], [18, 11, 14, 18, 24])[1] == 8
end

@testset "[S8] the hours-of-service wrapper of 5.3's Code block 37 reads the checked cost's out" begin
    c = _k7b_nc30()
    sh6 = DataFrame(b = fill(1, c.n), e = 2:c.n+1, q = c.q, s = c.s, tU = c.q * 30/60,
                    temin = [fill(7, 15); fill(13, 15)], temax = [fill(17, 15); fill(23, 15)])
    T6 = c.D / 50 .+ 5/60; tr = (b = 1, e = 1, Kwt = 25, Kcu = 2750)
    m = lecture53_module(:L53_hos)
    function hos(f)                     # 5.3 Code block 37
        return function (rte)
            TT, _, out = f(rte, sh6, T6, tr)
            isinf(TT) && return Inf
            drive = sum(out.Cost)
            return drive > 11 || TT > 14 ? Inf : TT
        end
    end
    h1, h2 = hos(_vrp), hos((a...) -> lecture53_call(m, :rteTC_vrp, a...))
    R = _k7b_routes(Xoshiro(3), 8; nroutes = 100)
    @test all(isequal(h1(r), h2(r)) || isapprox(h1(r), h2(r); atol = 1e-9) for r in R)    # to 1e-9; the same routes feasible
    @test any(isinf, h1.(R)) && any(isfinite, h1.(R))
    @test any(r -> isfinite(h1(r)) && sum(_vrp(r, sh6, T6, tr)[3].Cost) > 5, R)
    # the columns of out are the contract
    out = _vrp([1, 2, 1, 2], sh6, T6, tr)[3]
    @test names(out) == ["Rte", "Loc", "Cost", "Arrive", "Wait", "TWmin", "Start", "LU", "Depart", "TWmax", "Total"]
    @test names(_vrp([1, 2, 2, 1], c.sh, c.D, tr)[3]) == ["Rte", "Loc", "Cost"]
    @test names(_vrp([1, 2, 2, 1], sh6[:, [:b, :e, :tU]], T6, tr)[3]) == ["Rte", "Loc", "Cost", "LU"]
end

@testset "[S44] a full-cube maxpayld load is not flagged over capacity" begin
    C = [0.0 10.0; 10.0 0.0]; tr = (b = 1, e = 1, Kwt = 25.0, Kcu = 2750.0)
    for s in (5.0, 7.0, 8.0, 11.3, 13.7, 25.0, 40.0, 100 / 3)
        sh = DataFrame(b = [1], e = [2], q = [maxpayld(s)], s = [s])
        @test _vrp([1, 1], sh, C, tr)[2] == 1
    end
    sh = DataFrame(b = [1], e = [2], q = [1.001 * maxpayld(8.0)], s = [8.0])
    @test _vrp([1, 1], sh, C, tr)[1:2] == (Inf, -3)
    @test _vrp([1, 1], DataFrame(b = [1], e = [2], q = [25.0], s = [100.0]), C, tr)[2] == 1      # 25 t, weight-limited
    @test _vrp([1, 1], DataFrame(b = [1], e = [2], q = [25.0 + 1e-9], s = [100.0]), C, tr)[2] == -2
end

@testset "[CR 42] maxTC is checked on cost plus loading before the scans, and does not bound a windowed route's duration" begin
    # one customer, 2 h away (T), 1 h to unload, a window that opens at 10: travel plus unloading is
    # 2 + 1 + 2 = 5 h, within maxTC = 9, but the route's time with its wait is longer
    T = [0.0 2.0; 2.0 0.0]
    sh = DataFrame(b = [1], e = [2], tU = [1.0], temin = [10.0], temax = [14.0])
    tr = (b = 1, e = 1, maxTC = 9.0)
    TC, Xflg, out = _vrp([1, 1], sh, T, tr)
    @test Xflg == 1 && TC == 5.0                     # the scans leave the route's time at its travel and unloading (no wait: it can start later)
    @test _vrp([1, 1], sh, T, (b = 1, e = 1, maxTC = 4.9))[1:2] == (Inf, -4)
    # a window that holds the route up: the depot's window forces the start
    tr2 = (b = 1, e = 1, maxTC = 9.0, tbmin = 0.0, tbmax = 0.0)
    TC2, Xflg2, out2 = _vrp([1, 1], sh, T, tr2)
    @test Xflg2 == 1 && TC2 > 5 && TC2 <= 9 + 100  # waits for the window: past the travel and unloading it was tested on
    @test TC2 == sum(out2.Total)
end

@testset "[P9, D10] Lecture 5.3's own rteTC_vrp, rte2ldmx and scanTW still run after `using Logjam`, in either order" begin
    m = lecture53_module(:L53_after)
    sh = DataFrame(b = [1, 3, 5], e = [2, 4, 6], q = [10, 10, 10])
    D = RPIN_D6
    @test lecture53_call(m, :rteTC_vrp, [1, 2, 1, 3, 2, 3], sh, D, (Kwt = 25,))[1:2] == (1075.0, 1)
    @test lecture53_call(m, :rte2ldmx, [1, 2, 1, 3, 2, 3]) == [[1, 2], [2, 3]]
    @test getfield(m, :rte2ldmx) !== Logjam.rte2ldmx && getfield(m, :scanTW) !== Logjam.scanTW
    @test !isdefined(Logjam, :rteTC_vrp)             # one route cost function: no second name
    # Logjam's names used first (the exported ones), then the lecture defines its own
    m2 = Module(:L53_call_first)
    Core.eval(m2, :(using Logjam)); Core.eval(m2, :(using DataFrames))
    @test Core.eval(m2, :(rte2ldmx([1, 2, 3, 3, 2, 1]))) == [[1, 2, 3]]
    @test Core.eval(m2, :(rteTC([1, 1], DataFrame(b = [1], e = [2]), [0.0 3.0; 3.0 0.0]))) == 3.0
    for ex in Meta.parseall(LECTURE53_CODE).args
        ex isa LineNumberNode || Core.eval(m2, ex)
    end
    @test lecture53_call(m2, :rteTC_vrp, [1, 2, 1, 3, 2, 3], sh, D, (Kwt = 25,))[1:2] == (1075.0, 1)
    # scanTW is public and not exported (the lecture's own is the implementation rung of a model)
    @test Base.ispublic(Logjam, :scanTW) && !Base.isexported(Logjam, :scanTW)
    @test Base.isexported(Logjam, :rte2ldmx) && Base.isexported(Logjam, :rteTC)
end

@testset "[P9, CR 42, D6] one rteTC: a plain call returns the cost alone, and what it returned unless a limit is on the truck" begin
    c = _k7b_nc30()
    tr = (b = 1, e = 1)
    r = vcat(1:c.n, 1:c.n)
    # no limit fields: v0.2.8's value, exactly (sum of the segment costs), a bare number
    @test rteTC(r, c.sh, c.D, tr) === sum(segcost(rte2loc(r, c.sh, tr), c.D))
    @test rteTC(r, c.sh, c.D) === sum(segcost(rte2loc(r, c.sh), c.D))
    # a route that returns to the depot midway is priced by a plain call with no limit on the truck
    @test isfinite(rteTC([1, 1, 2, 2], DataFrame(b = [1, 1], e = [2, 3]), [0 5 7; 5 0 4; 7 4 0], tr))
    @test rteTC([1, 1], DataFrame(b = [1], e = [2], q = [30.0], s = [8.0]), [0.0 10.0; 10.0 0.0],
                (b = Int[], e = Int[], Kwt = 25.0, Kcu = 2750.0); full = true).Xflg == -2   # an empty truck location is no degenerate route
    @test_throws ArgumentError rteTC([1, 1], DataFrame(b = [1], e = [2], q = [3.0]), [0.0 1.0; 1.0 0.0], (b = 1, e = 1, Kcu = 100))
    # a limit on the truck is read: capacity, cube, maxTC and the degenerate route are Inf
    @test isinf(rteTC(r, c.sh, c.D, merge(tr, (Kwt = 25, Kcu = 2750))))
    @test isfinite(rteTC([1, 1], c.sh, c.D, merge(tr, (Kwt = 25, Kcu = 2750))))
    @test isinf(rteTC([1, 1], c.sh, c.D, merge(tr, (maxTC = 1.0,))))
    @test isinf(rteTC([1, 1, 2, 2], DataFrame(b = [1, 1], e = [2, 3]), [0 5 7; 5 0 4; 7 4 0], merge(tr, (Kwt = 25,))))
    # loading and unloading times and windows are read only with full = true
    sh = DataFrame(b = [1], e = [2], tU = [3.0], temin = [10.0], temax = [14.0])
    T = [0.0 2.0; 2.0 0.0]
    @test rteTC([1, 1], sh, T, tr) == 4.0
    @test rteTC([1, 1], sh, T, tr; full = true).TC > 4.0
    # full = true is a named tuple that destructures as 5.3's `TC, Xflg, out = rteTC_vrp(...)`
    TC, Xflg, out = rteTC([1, 1], sh, T, tr; full = true)
    @test Xflg == 1 && out isa DataFrame && TC == rteTC([1, 1], sh, T, tr; full = true).TC
    # a vector of routes: the method does not take a route (a vector of integers) for one
    R = [[1, 1], [1, 2, 2, 1]]
    sh2 = DataFrame(b = [1, 1], e = [2, 3])
    D3 = [0 5 7; 5 0 4; 7 4 0]
    @test rteTC(R, sh2, D3, tr) == [rteTC(r, sh2, D3, tr) for r in R]
    f = rteTC(R, sh2, D3, tr; full = true)
    @test f.TC == [rteTC(r, sh2, D3, tr; full = true).TC for r in R] && f.Xflg == [1, 1] && length(f.out) == 2
end

@testset "[P9, N20, CR 42] the default truck is (;), the travel cost is today's sum bit for bit, the route-set method is not ambiguous" begin
    C = rand(Xoshiro(2), 4, 4) * 10
    for i in 1:4; C[i, i] = 0.0; end
    sh = DataFrame(b = [1, 3], e = [2, 4])
    for r in ([1, 1], [1, 2, 2, 1], [1, 2, 1, 2], [2, 1, 1, 2], [1, 2, 1, 2]),
        tr in ((;), (b = 1, e = 1), (b = [1], e = [1]), (b = Int[], e = Int[]), (Kwt = 25,), (b = 4,))
        s = sum(segcost(rte2loc(r, sh, tr), C))
        f = rteTC(r, sh, C, tr; full = true)
        # a route that returns to a depot truck's depot midway (b = e) is refused by full = true, flag -1
        @test f.Xflg == 1 ? f.TC === s : (isinf(f.TC) && f.Xflg == -1 && haskey(tr, :b))
        f.Xflg == 1 || continue
        @test rteTC(r, sh, C, tr) === s                           # plain, no limit (or a limit that is met)
        @test f.TC === s                                          # full = true: the same sum, bit for bit
    end
    @test rteTC([1, 2, 2, 1], sh, C) === sum(segcost(rte2loc([1, 2, 2, 1], sh), C))
    # a truck with a capacity only: rte2loc reads no b and e (v0.2.8: FieldError), as 5.3's tr3 = (Kwt = 25,)
    @test rte2loc([1, 2, 2, 1], sh, (Kwt = 25,)) == rte2loc([1, 2, 2, 1], sh) isa Vector{Int}
    @test rte2loc([1, 2, 2, 1], sh, (b = 4,)) == vcat(4, rte2loc([1, 2, 2, 1], sh))
    @test rte2loc([1, 2, 2, 1], sh, (e = 4,)) == vcat(rte2loc([1, 2, 2, 1], sh), 4)
    # the route-set method does not make the route method ambiguous
    amb = Test.detect_ambiguities(Logjam)
    @test !any(p -> any(m -> m.name == :rteTC, p), amb)
    @test rteTC([[1, 1], [2, 2]], sh, C, (b = 1, e = 1)) == [rteTC([1, 1], sh, C, (b = 1, e = 1)), rteTC([2, 2], sh, C, (b = 1, e = 1))]
    @test rteTC([1, 1], sh, C) isa Float64                         # a route (vector of integers) is a route
end

@testset "[CR 43] a same-location segment costs nothing, and the multi-trip route is decided" begin
    C = [5.0 10.0 7.0; 10.0 5.0 4.0; 7.0 4.0 5.0]            # a positive diagonal (a stop time)
    sh = DataFrame(b = [1, 1], e = [2, 3])
    tr = (b = 1, e = 1)
    # route (1, 2, 2, 1): 1 -> 1 -> 3 -> 2 -> 1 with the truck's ends: the first segment is at one location
    @test rteTC([1, 2, 2, 1], sh, C, tr) == 7.0 + 4.0 + 10.0
    @test rteTC([1, 2, 2, 1], sh, C, tr; full = true).TC == 7.0 + 4.0 + 10.0
    @test rteTC([1, 2, 2, 1], sh, C, merge(tr, (Kwt = 25,))) == 7.0 + 4.0 + 10.0
    # a zero diagonal moves nothing (every pinned course call); a nonzero one is charged no more
    @test rteTC([1, 1], sh, C) == 10.0
    # the decision CR 43 asks for: a route that returns to its depot midway is PRICED by a plain call with no
    # limit on the truck (as v0.2.8 did) and REFUSED, flag -1, with full = true or a limit on the truck
    mt = [1, 1, 2, 2]
    @test isfinite(rteTC(mt, sh, C, tr))
    @test rteTC(mt, sh, C, tr; full = true).Xflg == -1 && isinf(rteTC(mt, sh, C, tr; full = true).TC)
    @test isinf(rteTC(mt, sh, C, merge(tr, (Kwt = 25,))))
end

@testset "[CR 59] rte2ldmx lists the shipments on board at each load mix" begin
    @test rte2ldmx([1, 2, 3, 3, 2, 1]) == [[1, 2, 3]]
    @test rte2ldmx([1, 2, 1, 3, 2, 3]) == [[1, 2], [2, 3]]
    @test rte2ldmx([1, 1]) == [[1]]
    @test rte2ldmx([1, 1, 2, 2]) == [[1], [2]]
    @test rte2ldmx([1, 2, 2, 1]) == [[1, 2]]
    @test rte2ldmx(Int[]) == Vector{Int}[]
    # the loads of a route of 5.3's Ex. 3 add up: every shipment is on board at some mix
    @test sort(unique(reduce(vcat, rte2ldmx([3, 1, 2, 2, 1, 3])))) == [1, 2, 3]
end

end  # @testset "K7b"
