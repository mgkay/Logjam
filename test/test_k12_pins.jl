# test_k12_pins.jl -- what the course gets today from the calls K12's new functions replace or sit beside, pinned from
# the code at 4e7ce94 (PCV K12, plan principle 9). Every value below was measured on the unchanged code, before K12
# added `randtour`, `disk`, `sfcpos`, `tspspfillcur`, `lonlat`, integer ZIPs, `usstate`, the `usstates` declaration and
# the county box. A call the course makes today keeps returning what it returned then; only a case named in K12PIN_MOVED
# may differ, and each one is named in the commit that moves it. (Logjam's own `randtour`, `disk`, `sfcpos` and
# `tspspfillcur` were removed before the release, rulings RTE27, IN1 and IN3; the lecture's definitions are what is pinned.)
#
# What is pinned: the lecture definitions themselves (Lecture 5.1's `randtour`, `disk`, `sfcpos`, `tspspfillcur`, Lecture
# 4.2's Code block 3), run as text in a scratch module that has done `using Logjam` first, their outputs on the
# course's own inputs and seeds, and the global random stream after each seeded draw (the next `rand()`); the
# `hcat(df.LON, df.LAT)` the course writes at three sites; `loc2lonlat` on string ZIPs; and `Logjam.usstates()`.
# Draws that `randperm` makes differ between Julia 1.12 and 1.13 (the generator's stream is the same, `randperm`'s use of
# it is not), so those values are pinned per version and compared with the lecture's definition only on another.
#
# No case touches the network or a file outside the package, and none renders a picture.

using Test
using Logjam
using DataFrames
using Random

include("oracle_helpers.jl")
isdefined(@__MODULE__, :LECTURE51_SFC) || include("lecture51_code.jl")
isdefined(@__MODULE__, :LECTURE42_COUNTY_BOX) || include("lecture42_code.jl")

# case name => ruled ID that moves it (none)
const K12PIN_MOVED = Dict{String, String}()

_k12pin_moved(name) = haskey(K12PIN_MOVED, name) && (@info("K12 pin $name moved under $(K12PIN_MOVED[name])"); true)

# FNV-1a over the bytes of an array: a checksum that is the same on every Julia version (`hash` is not)
function _k12_fnv(bytes)
    h = 0xcbf29ce484222325
    for b in bytes
        h = (h ⊻ UInt64(b)) * 0x00000100000001b3
    end
    return h
end
_k12_fnv(x::AbstractArray{Float64}) = _k12_fnv(reinterpret(UInt8, vec(collect(x))))
_k12_fnv(x::AbstractArray{Int}) = _k12_fnv(reinterpret(UInt8, vec(collect(x))))

# a function the scratch module defined, called from here
_k12_call(m::Module, name::Symbol, args...) = Base.invokelatest(getfield(m, name), args...)

# ---- Lecture 5.1's randtour and disk: draws and the stream after them ---------------------------------------------
# (Logjam's own `randtour` was removed before the release, ruling RTE27; the lecture's definition is what is pinned.)
# version => (name => value): seed 2024 then `randtour(6)` (Code block 17) and the next draw; `randtour(100)` (Code
# block 28); the stream of Code blocks 17 and 18, 101 draws of `randtour(6)`; of Code blocks 28 and 30, 101 draws of
# `randtour(100)`.
const K12_RANDTOUR_PINS = Dict(
    (1, 12) => (t6 = [4, 5, 6, 3, 2, 1, 4], t6_next = 0.9387028493780337,
                t100_first5 = [79, 21, 44, 85, 33], t100_fnv = 0x4d3de7eb0bbb3eae, t100_next = 0.22508726580673843,
                s6_fnv = 0x1e87d5d6071975a0, s6_next = 0.804549742908579,
                s100_fnv = 0x7270fa0fe92d2e98, s100_next = 0.0517857300421628),
    (1, 13) => (t6 = [2, 1, 6, 3, 5, 4, 2], t6_next = 0.6279718282469421,
                t100_first5 = [16, 61, 85, 49, 87], t100_fnv = 0x431fd3a394e97391, t100_next = 0.5979243663887365,
                s6_fnv = 0xb1d234513cb29e27, s6_next = 0.03771720264773937,
                s100_fnv = 0x4378958d547cd456, s100_next = 0.06774925945267807),
)

@testset "[K12 pin] Lecture 5.1's randtour: the tours of its seeds and the stream after them" begin
    @test !_k12pin_moved("randtour")
    m = lecture51_module(LECTURE51_RANDTOUR)
    @test _k12_call(m, :randtour, 6) isa Vector{Int}
    p = get(K12_RANDTOUR_PINS, (VERSION.major, VERSION.minor), nothing)

    Random.seed!(2024)
    t6 = _k12_call(m, :randtour, 6)
    n6 = rand()
    @test length(t6) == 7 && t6[1] == t6[end] && sort(t6[1:6]) == 1:6        # a permutation with its first node repeated
    p === nothing || @test (t6, n6) == (p.t6, p.t6_next)

    Random.seed!(2024)
    t100 = _k12_call(m, :randtour, 100)
    n100 = rand()
    @test length(t100) == 101 && t100[1] == t100[end] && sort(t100[1:100]) == 1:100
    p === nothing || @test (t100[1:5], _k12_fnv(t100), n100) == (p.t100_first5, p.t100_fnv, p.t100_next)

    Random.seed!(2024)
    s6 = reduce(vcat, [_k12_call(m, :randtour, 6) for _ in 1:101])
    ns6 = rand()
    p === nothing || @test (_k12_fnv(s6), ns6) == (p.s6_fnv, p.s6_next)

    Random.seed!(2024)
    s100 = reduce(vcat, [_k12_call(m, :randtour, 100) for _ in 1:101])
    ns100 = rand()
    p === nothing || @test (_k12_fnv(s100), ns100) == (p.s100_fnv, p.s100_next)
end

@testset "[K12 pin] Lecture 5.1's disk: the points of its seeds and the stream after them" begin
    @test !_k12pin_moved("disk")
    m = lecture51_module(LECTURE51_DISK)

    Random.seed!(150)                                        # Code block 24's draw of two points
    d2 = _k12_call(m, :disk, 2)
    @test d2 == [0.5381022146876899 0.03250886468438763; 0.30127979264620874 -0.767481238809196]
    @test rand() == 0.32134164134444465

    Random.seed!(150)                                        # Code block 24's whole table of draws
    Pall = Matrix{Float64}[]
    for mm in (2, 5, 10, 20, 50, 100, 200)
        append!(Pall, [_k12_call(m, :disk, mm) for _ in 1:(1000 ÷ mm)])
    end
    @test length(Pall) == 885 && sum(size.(Pall, 1)) == 7000
    @test all(P -> all(sum(abs2, P; dims = 2) .< 1), Pall)
    @test _k12_fnv(reduce(vcat, Pall)) == 0x7d64c7767e6b2cec
    @test rand() == 0.15527645417329117

    Random.seed!(242)                                        # Code block 23: 300 points
    D300 = _k12_call(m, :disk, 300)
    @test _k12_fnv(D300) == 0x046d6036b15fdb98
    @test rand() == 0.705706198926476
    m2 = lecture51_module(LECTURE51_INLINE_DISK)             # Code block 23's own loop draws the same 300 points
    @test getfield(m2, :P) == D300
    @test rand() == 0.705706198926476                        # and leaves the stream in the same place
end

# ---- Lecture 5.1's sfcpos and tspspfillcur ------------------------------------------------------------------------
# the SFC Handout's 11 x 11 table of curve positions (Lecture 5.1's Code block 9, rows y = 1 down to 0, columns x = 0 to 1),
# to three decimals, halves away from zero as MATLAB rounds
const K12_SFC_HANDOUT = [0.250 0.254 0.265 0.298 0.309 0.438 0.441 0.452 0.485 0.496 0.500
                         0.246 0.257 0.271 0.292 0.305 0.434 0.445 0.458 0.479 0.493 0.504
                         0.235 0.229 0.279 0.283 0.333 0.423 0.417 0.467 0.471 0.521 0.515
                         0.202 0.208 0.158 0.154 0.354 0.390 0.396 0.596 0.592 0.542 0.548
                         0.191 0.180 0.167 0.146 0.132 0.379 0.618 0.604 0.583 0.570 0.559
                         0.188 0.184 0.173 0.140 0.129 0.375 0.621 0.610 0.577 0.566 0.563
                         0.059 0.070 0.083 0.104 0.118 0.871 0.632 0.646 0.667 0.680 0.691
                         0.048 0.042 0.092 0.096 0.896 0.860 0.854 0.654 0.658 0.708 0.702
                         0.015 0.021 0.971 0.967 0.917 0.827 0.833 0.783 0.779 0.729 0.735
                         0.004 0.993 0.979 0.958 0.945 0.816 0.805 0.792 0.771 0.757 0.746
                         0.000 0.996 0.985 0.952 0.941 0.813 0.809 0.798 0.765 0.754 0.750]

@testset "[K12 pin] Lecture 5.1's sfcpos and tspspfillcur: the handout, slide 238, eil51 and the NC cities" begin
    @test !_k12pin_moved("sfc")
    m = lecture51_module(LECTURE51_SFC)
    sp(x, y, k = 8) = _k12_call(m, :sfcpos, x, y, k)
    tsp(XY, k = 8) = _k12_call(m, :tspspfillcur, XY, k)
    eil51 = _readoracle("tsp_traces")["XY"]          # vrpnc1's 51 points, as makeRouting1.m reads them

    @testset "the handout's 121 cells (Code block 9), and the four points of slide 238 (Code block 8)" begin
        g = (0:10) ./ 10
        Θ = [sp(x, y) for y in reverse(g), x in g]
        @test round.(Θ, RoundNearestTiesAway, digits = 3) == K12_SFC_HANDOUT
        @test _k12_fnv(Θ) == 0xbc23e4bafd3c41ef
        XY4 = [0.8 0.8; 0.1 0.2; 0.3 0.7; 0.7 0.2]
        θ4 = [sp(XY4[i, 1], XY4[i, 2]) for i in 1:4]
        @test θ4 == [0.4705810546875, 0.0208282470703125, 0.1544189453125, 0.7830810546875]
        @test round.(θ4, digits = 3) == [0.471, 0.021, 0.154, 0.783]
        @test tsp(XY4) == [1, 4, 2, 3, 1]
    end

    @testset "eil51 (Matlog's vrpnc1): the tour MATLAB printed in the S17 diary" begin
        printed = [1, 7, 15, 26, 25, 24, 44, 8, 27, 9, 49, 28, 33, 2, 23, 32, 29, 4, 37, 36, 21, 30, 22, 3, 17,
                   12, 39, 10, 50, 51, 35, 31, 40, 34, 46, 11, 6, 13, 38, 18, 16, 45, 43, 20, 41, 42, 14, 19, 5,
                   48, 47, 1]
        @test tsp(eil51) == printed
    end

    @testset "the NC cities (Code block 4) and the 100 NC counties (Code block 33)" begin
        df = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
        @test tsp(hcat(df.LON, df.LAT)) == [1, 9, 5, 2, 3, 7, 6, 10, 4, 8, 1]
        dc = filter(r -> (r.STFIP == st2fips(:NC)), uscounty())
        XY = hcat(dc.LON, dc.LAT)
        t = tsp(XY)
        @test length(t) == 101 && t[1] == t[end] == 1 && sort(t[1:100]) == 1:100
        @test t[1:8] == [1, 13, 47, 21, 29, 34, 66, 24]
        @test _k12_fnv(t) == 0x1625e134f4248fe0
        D = dists(XY, XY, :mi)
        @test isapprox(sum(D[t[k], t[k + 1]] for k in 1:100), 2826.212979580854; rtol = 1e-12)
        @test _k12_fnv(tsp(XY, 4)) == 0xd214adc3154504c0
    end
end

# ---- the hcat the course writes -----------------------------------------------------------------------------------
@testset "[K12 pin] hcat(df.LON, df.LAT) at three course sites" begin
    @test !_k12pin_moved("hcat")
    # Lecture 2.3, Code block 2 (2-loc-3.qmd:289-294): the NC cities over 100,000
    df = filter(r -> r.STFIP == st2fips(:NC) && r.POP > 100_000, usplace())
    select!(df, :NAME, :LON, :LAT, :POP)
    P = hcat(df.LON, df.LAT)
    @test size(P) == (10, 2) && eltype(P) == Float64
    @test P[1, :] == [-78.819011, 35.78145] && _k12_fnv(P) == 0x1f9052710d782adb
    # Lecture 5.1, Code block 27 (5-rte-1.qmd:2449): the 100 NC counties
    dc = filter(r -> r.STFIP == st2fips(:NC), uscounty())
    X = hcat(dc.LON, dc.LAT)
    @test size(X) == (100, 2) && eltype(X) == Float64
    @test X[1, :] == [-79.413154, 36.071544] && _k12_fnv(X) == 0x513ab69247baf81e
    # Lecture 2.6, Code block (2-loc-6.qmd:499-500): the 3-digit ZIP areas
    z = filter(r -> r.ISCUS && r.POP > 0, uszcta3())
    Z = hcat(z.LON, z.LAT)
    @test size(Z) == (882, 2) && eltype(Z) == Float64
    @test Z[1, :] == [-72.57315772581423, 42.2125312208976] && _k12_fnv(Z) == 0xcb551bc70dba970b
end

@testset "[K12 pin] loc2lonlat on string ZIPs (the POSTALCODE tier), which the integer methods must equal" begin
    @test !_k12pin_moved("loc2lonlat_zip")
    r = loc2lonlat(["27601", "02139", "10001", "90210"])
    @test r.INPUT == ["27601", "02139", "10001", "90210"]
    @test r.LON == [-78.634563, -71.102336, -73.997298, -118.41463]
    @test r.LAT == [35.773661, 42.362391, 40.750649, 34.100517]
    @test r.GC_SOURCE == fill("POSTALCODE", 4) && r.GC_STATUS == fill("OK", 4)
    @test r.GC_UNCERT == [0.5071433604381534, 0.46857559255316794, 0.2971160409138231, 1.23309811391261]
    @test loc2lonlat("27601") == (LON = -78.634563, LAT = 35.773661, GC_SOURCE = "POSTALCODE",
                                  GC_UNCERT = 0.5071433604381534, GC_STATUS = "OK")
    @test loc2lonlat("02139") == (LON = -71.102336, LAT = 42.362391, GC_SOURCE = "POSTALCODE",
                                  GC_UNCERT = 0.46857559255316794, GC_STATUS = "OK")
    f = loc2lonlat("00501")                                   # a ZIP not in the table
    @test (f.GC_STATUS, f.GC_SOURCE, ismissing(f.LON), ismissing(f.LAT)) == ("FAIL", "", true, true)
end

# ---- Lecture 4.2's Code block 3: Wake County's box -----------------------------------------------------------------
@testset "[K12 pin] Lecture 4.2's Code block 3: Wake County's box from its block groups" begin
    @test !_k12pin_moved("wake_box")
    m = lecture42_module()
    @test nrow(getfield(m, :B)) == 597
    @test getfield(m, :mpd) == 69.09322176332552
    @test getfield(m, :bbW) == (-78.97544182356803, -78.27350863429567, 35.52318408209017, 36.080417439618664)
    @test getfield(m, :wide) == 39.334750975714485
    @test getfield(m, :high) == 38.50104794563882
    @test round.(getfield(m, :bbW), digits = 3) == (-78.975, -78.274, 35.523, 36.080)    # what the lecture prints
    @test (round(Int, getfield(m, :wide)), round(Int, getfield(m, :high))) == (39, 39)
end

# ---- usstates ---------------------------------------------------------------------------------------------------
@testset "[K12 pin] Logjam.usstates(), as Lecture 5.1 (5-rte-1.qmd:818) and the four Lecture 2.2 generators call it" begin
    @test !_k12pin_moved("usstates")
    x, y = Logjam.usstates()
    @test (typeof(x), typeof(y)) == (Vector{Float64}, Vector{Float64})
    @test (length(x), length(y)) == (3642, 3642)
    @test (count(isnan, x), count(isnan, y)) == (103, 103)
    @test (_k12_fnv(x), _k12_fnv(y)) == (0xbd5dfc034f397b93, 0x73b1dce3c71f5e75)
    @test extrema(filter(!isnan, x)) == (-188.9049072265625, -65.62680053710938)
    @test extrema(filter(!isnan, y)) == (17.929555892944336, 71.35163116455078)
    @test isequal(Logjam.usstates(), (x, y))                             # a later call returns what the first did
    @test findall(isnan, x) == findall(isnan, y)                         # the separators sit together
end
