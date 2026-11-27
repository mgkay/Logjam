# test_boxes_v031.jl -- added by PCV WP10 of Logjam v0.3.1 (X7: a city's and a state's box, MakePlan D3; X8: the
# empirical aggregate distance, MakePlan D8). Test spec Sec. 6. Equality is `===` (bit for bit) where marked and `==`
# elsewhere; the tolerances are D3's, Raleigh's box within 0.05 degrees of Nominatim's on every side, and test spec
# Sec. 6's relative 1e-14 against MATLAB's dagg.m, also used for the two closed forms at the branch boundary (26r/23
# and 546r/480, the formula's value at a point, equal to rounding), and one unit in the last place between the
# empirical distance at d = 0, 2r/3 as 2.5's equation writes it, and the default's floor, (2/3)·r. The evidence:
#   1. the place boxes (data/usplacebox, made by tools/v0_3_1/make_placebox.jl from the Census TIGER/Line 2020 place
#      shapefiles): exactly `usplace()`'s keys, one row each, sorted; the CSV the script's output byte for byte (its
#      SHA-256, printed on two runs) and the .jls that CSV read back; every box contains its place's `usplace()`
#      point, all 31,617; Raleigh's box against the Nominatim box CR 28 recorded;
#   2. `mapbbox(name; state, place)`: every county of `uscounty()` gives, bit for bit, the box `mapbbox` gave it at
#      the branch's start, or throws the same error (test/data/county_boxes_f3f0c1b.csv, saved by
#      tools/v0_3_1/save_county_boxes.jl before WP10 changed `mapbbox`); "Durham" in North Carolina is the county,
#      and the city (PLFIP 19000) with `place = true`; a name no county has gives the place; the matching rules (case,
#      the designator, an exact name preferred); every name two places share in a state is an error naming them;
#      every place by its own name gives its own box; `xexpand` and `yexpand` act on a place's box as on a county's;
#   3. `mapbbox(state)`: for every state of `usstate()`, the extent of its counties' boxes, each Lecture 4.2's Code
#      block 3 run on the county's block groups (copied below as text), and so containing each of them;
#   4. `dgca(...; method = :empirical)`: `==` to 2.5's @eq-daemp copied as text on 2.5's Example 4 and 5 inputs, by
#      both of dgca's methods and in another unit; against MATLAB's ise754/dagg.m run on the same distances
#      (test/oracles/dagg_matlab.csv, tools/v0_3_1/make_oracles_v031.m), relative 1e-14 wherever dagg.m applies one
#      case, and where it applies both (d/r from 0.8378 to 1: its second statement tests the matrix its first has
#      changed) its value the second case applied to the first's, above 2.5's equation, which Logjam follows; the
#      branch boundary as dagg.m draws it (26r/23 at d = r, 546r/480 the limit from below); d_a > d for d >= r;
#      2r/3 at d = 0; a zero area; and the default method `===` to v0.3.0's body, copied as text.
# A lecture's definition is copied here as text, with its .qmd file and lines; no companion script is run.

using Test
using Logjam
using DataFrames
using CSV
using Random

# SHA is in every environment Logjam is in but not a dependency of the test target (test_geodata_v031.jl, Sec. 4)
const _BX_SHA = Base.require(Base.PkgId(Base.UUID("ea8e919c-243c-51af-8825-aaa63cd721ce"), "SHA"))
_bx_sha(b) = bytes2hex(_BX_SHA.sha256(b))
_bx_lf(path) = (b = read(path); b[b .!= UInt8('\r')])          # the file as committed: a Windows checkout may add CRs

# data/usplacebox.csv's SHA-256, printed by tools/v0_3_1/make_placebox.jl on two runs (Julia 1.12.6)
const _BX_PLACEBOX_SHA = "39d6c7345c7f795a6cd87b0780202c8677155d05fda1e4f3ebbad7e109ea816b"

# a place's box as the table holds it, ((LONmin, LONmax), (LATmin, LATmax))
function _bx_placebox(stfip, plfip)
    B = Logjam._table("usplacebox")
    j = only(findall((B.STFIP .== stfip) .& (B.PLFIP .== plfip)))
    return ((B.LONmin[j], B.LONmax[j]), (B.LATmin[j], B.LATmax[j]))
end
_bx_plfip(st, name) = only(filter(r -> r.ST == st && r.NAME == name, usplace())).PLFIP
_bx_err(f) = try f(); nothing catch e; e end

# ---- 1. the place boxes ----------------------------------------------------------------------------------------------
@testset "[WP10 X7] usplacebox: one box for each usplace() row, the derivation's output" begin
    B = Logjam._table("usplacebox")
    p = usplace()
    @test names(B) == ["STFIP", "PLFIP", "LONmin", "LONmax", "LATmin", "LATmax"]
    @test eltype.(eachcol(B)) == [Int64, Int64, Float64, Float64, Float64, Float64]
    kb = collect(zip(B.STFIP, B.PLFIP))
    @test issorted(kb) && allunique(kb)
    @test kb == sort!(collect(zip(p.STFIP, p.PLFIP)))              # exactly usplace()'s keys
    @test nrow(B) == nrow(p) == 31617
    @test all(B.LONmin .<= B.LONmax) && all(B.LATmin .<= B.LATmax)
    # the CSV is make_placebox.jl's output byte for byte, and the .jls is that CSV read back
    csv = _bx_lf(joinpath(pkgdir(Logjam), "data", "usplacebox.csv"))
    @test _bx_sha(csv) == _BX_PLACEBOX_SHA
    back = CSV.read(IOBuffer(csv), DataFrame; ntasks = 1)
    @test isequal(back, B) && eltype.(eachcol(back)) == eltype.(eachcol(B))
    # every place's box contains its usplace() point (D3's invariant), all rows
    row = Dict(k => j for (j, k) in enumerate(kb))
    outside = Int[]
    for i in 1:nrow(p)
        j = row[(p.STFIP[i], p.PLFIP[i])]
        (B.LONmin[j] <= p.LON[i] <= B.LONmax[j] && B.LATmin[j] <= p.LAT[i] <= B.LATmax[j]) || push!(outside, i)
    end
    @test isempty(outside)
end

@testset "[WP10 X7] Raleigh's box is within 0.05 degrees of Nominatim's on every side (D3)" begin
    nominatim = (-78.8190, -78.4708, 35.7083, 35.9707)    # CR 28's record of Nominatim's boundingbox: xmin, xmax, ymin, ymax
    bb = mapbbox("Raleigh"; state = :NC)
    got = (bb[1][1], bb[1][2], bb[2][1], bb[2][2])
    @test all(abs.(got .- nominatim) .<= 0.05)
    @test got == (-78.818556, -78.470789, 35.70825, 35.970784)   # the .shp's box of place 37 55000, as the script read it
    @test bb == _bx_placebox(37, 55000)
end

# ---- 2. mapbbox(name; state, place) -----------------------------------------------------------------------------------
@testset "[WP10 X7] every county's box is the one it had at the branch's start, bit for bit" begin
    lines = filter(l -> !startswith(l, "#"), readlines(joinpath(@__DIR__, "data", "county_boxes_f3f0c1b.csv")))
    @test lines[1] == "STFIP,COFIP,ST,NAME,LONmin,LONmax,LATmin,LATmax,ERROR"
    rows = [split(l, ',') for l in lines[2:end]]
    c = uscounty()
    @test length(rows) == nrow(c) == 3143
    @test all(length.(rows) .== 9)
    @test [(parse(Int, f[1]), parse(Int, f[2]), Symbol(f[3]), String(f[4])) for f in rows] ==
          [(c.STFIP[i], c.COFIP[i], c.ST[i], String(c.NAME[i])) for i in 1:nrow(c)]
    differ, nbox, nerr = Int[], 0, 0
    for (i, f) in enumerate(rows)
        got = try mapbbox(String(c.NAME[i]); state = c.ST[i]) catch e; e end
        if isempty(f[9])
            want = ((parse(Float64, f[5]), parse(Float64, f[6])), (parse(Float64, f[7]), parse(Float64, f[8])))
            got === want || push!(differ, i)                    # `===` on a tuple of Float64 compares the bits
            nbox += 1
        else
            (got isa ArgumentError && sprint(showerror, got) == f[9]) || push!(differ, i)
            nerr += 1
        end
    end
    @test isempty(differ)
    @test (nbox, nerr) == (3131, 12)      # 12: the six names two counties share in a state ("Baltimore", MD, and so on)
    # the expansion of a county's box is unchanged too
    for (nm, st) in (("Wake", :NC), ("Durham", :NC), ("Los Angeles", :CA))
        bb = mapbbox(nm; state = st)
        @test mapbbox(nm; state = st, xexpand = 0.1, yexpand = 0.2) === mapbbox(bb; xexpand = 0.1, yexpand = 0.2)
        @test mapbbox(nm; state = st, place = false) === bb
    end
end

@testset "[WP10 X7] mapbbox(name; state, place): a county first, then a place (D3)" begin
    # "Durham", NC: the county by default, the city of Durham (PLFIP 19000) with place = true
    d = mapbbox("Durham"; state = :NC)
    @test d === ((-79.02299880542887, -78.70670497613263), (35.86443470186037, 36.258072038495634))
    @test _bx_plfip(:NC, "Durham") == 19000
    dp = mapbbox("Durham"; state = :NC, place = true)
    @test dp == _bx_placebox(37, 19000) && dp != d
    @test dp isa Tuple{Tuple{Float64, Float64}, Tuple{Float64, Float64}}     # the shape mapbbox returns
    # a name that matches no county gives the place
    @test mapbbox("Raleigh"; state = :NC) == mapbbox("Raleigh"; state = :NC, place = true) == _bx_placebox(37, 55000)
    @test mapbbox("Cary"; state = :NC) == _bx_placebox(37, 10740)
    # ignoring case and spaces, and a state as a string or a full name, as for a county
    @test mapbbox("  RALEIGH "; state = "North Carolina") == mapbbox("raleigh"; state = "NC") == _bx_placebox(37, 55000)
    # the name without its designator: "city" or "town" given, or a CDP's without "CDP"
    @test mapbbox("Raleigh city"; state = :NC) == _bx_placebox(37, 55000)
    @test mapbbox("Cary town"; state = :NC) == _bx_placebox(37, 10740)
    durcdp = _bx_plfip(:CA, "Durham CDP")
    @test mapbbox("Durham CDP"; state = :CA) == mapbbox("Durham"; state = :CA) == mapbbox("durham cdp"; state = :CA) ==
          _bx_placebox(6, durcdp)
    # an exact name is preferred: Burbank, CA is the city, not Burbank CDP
    @test mapbbox("Burbank"; state = :CA) == _bx_placebox(6, _bx_plfip(:CA, "Burbank"))
    @test mapbbox("Burbank CDP"; state = :CA) == _bx_placebox(6, _bx_plfip(:CA, "Burbank CDP"))
    # a capitalized word of a name is part of it: "Kansas City" is matched, "Kansas" is not
    @test mapbbox("Kansas City"; state = :MO) == _bx_placebox(29, _bx_plfip(:MO, "Kansas City"))
    e = _bx_err(() -> mapbbox("Kansas"; state = :MO))
    @test e isa ArgumentError && occursin("no county or place named \"Kansas\" in MO", e.msg)
    # place = true reaches a place whose name two counties share ("Baltimore": the county and the independent city)
    e = _bx_err(() -> mapbbox("Baltimore"; state = :MD))
    @test e isa ArgumentError && e.msg == "mapbbox: \"Baltimore\" names 2 counties in MD."
    @test mapbbox("Baltimore"; state = :MD, place = true) == _bx_placebox(24, _bx_plfip(:MD, "Baltimore"))
    # with place = true a county's name that is no place's is an error; so is a name that is neither
    e = _bx_err(() -> mapbbox("Wake"; state = :NC, place = true))
    @test e isa ArgumentError && occursin("no place named \"Wake\" in NC", e.msg)
    e = _bx_err(() -> mapbbox("Wakee"; state = :NC))
    @test e isa ArgumentError && occursin("no county or place named \"Wakee\" in NC", e.msg)
    @test _bx_err(() -> mapbbox("Raleigh")) isa ArgumentError                     # no state
    @test _bx_err(() -> mapbbox("Raleigh"; state = :XX)) isa ArgumentError
    @test _bx_err(() -> mapbbox(" "; state = :NC, place = true)) isa ArgumentError
    # xexpand and yexpand act on a place's box exactly as on a county's: mapbbox(bb; xexpand, yexpand)
    for (nm, st, pl) in (("Raleigh", :NC, false), ("Durham", :NC, true), ("Durham", :CA, false))
        bb = mapbbox(nm; state = st, place = pl)
        @test mapbbox(nm; state = st, place = pl, xexpand = 0.1, yexpand = 0.2) === mapbbox(bb; xexpand = 0.1, yexpand = 0.2)
        @test mapbbox(nm; state = st, place = pl, xexpand = 2, yexpand = 0.5) === mapbbox(bb; xexpand = 2, yexpand = 0.5)
    end
    @test isempty(Test.detect_ambiguities(Logjam))
end

@testset "[WP10 X7] a name two places share in a state is an ArgumentError naming them" begin
    for (nm, st, members) in (("Kailua", :HI, ["Kailua CDP"]), ("St. Anthony", :MN, ["St. Anthony"]),
                              ("Oakwood village", :OH, ["Oakwood village"]))
        p = filter(r -> r.ST == st && r.NAME in members, usplace())
        @test nrow(p) == 2
        e = _bx_err(() -> mapbbox(nm; state = st))
        @test e isa ArgumentError && occursin("\"$nm\" names 2 places in $st", e.msg) &&
              all(occursin("\"$(r.NAME)\" (PLFIP $(r.PLFIP))", e.msg) for r in eachrow(p))
    end
    # every name that two or more places of a state share, as usplace() writes it (ignoring case): 81 of them
    p = usplace()
    g = groupby(transform(p, :NAME => ByRow(lowercase) => :q), [:ST, :q])
    shared = [sub for sub in g if nrow(sub) > 1]
    @test length(shared) == 81
    bad = Tuple{Symbol, String}[]
    for sub in shared
        e = _bx_err(() -> mapbbox(sub.NAME[1]; state = sub.ST[1], place = true))
        (e isa ArgumentError && occursin("names $(nrow(sub)) places in $(sub.ST[1])", e.msg) &&
         all(occursin("(PLFIP $pl)", e.msg) for pl in sub.PLFIP)) || push!(bad, (sub.ST[1], sub.NAME[1]))
    end
    @test isempty(bad)
end

@testset "[WP10 X7] every place by its own name gives its own box" begin
    p = usplace()
    q = lowercase.(p.NAME)
    n = Dict{Tuple{Symbol, String}, Int}()
    for i in 1:nrow(p)
        n[(p.ST[i], q[i])] = get(n, (p.ST[i], q[i]), 0) + 1
    end
    cq = Set(zip(uscounty().ST, lowercase.(uscounty().NAME)))
    B = Logjam._table("usplacebox")
    boxof = Dict((B.STFIP[j], B.PLFIP[j]) => ((B.LONmin[j], B.LONmax[j]), (B.LATmin[j], B.LATmax[j])) for j in 1:nrow(B))
    bad, ncounty, nplace = Int[], 0, 0
    for i in 1:nrow(p)
        n[(p.ST[i], q[i])] == 1 || continue                     # the names two places share are the testset above
        box = boxof[(p.STFIP[i], p.PLFIP[i])]
        mapbbox(p.NAME[i]; state = p.ST[i], place = true) == box || push!(bad, i)
        # without place = true, a name that is also a county's gives the county; any other, the place
        if (p.ST[i], replace(q[i], r"\s+county$" => "")) in cq
            ncounty += 1
        else
            mapbbox(p.NAME[i]; state = p.ST[i]) == box || push!(bad, i)
            nplace += 1
        end
    end
    @test isempty(bad)
    @test ncounty + nplace == nrow(p) - sum(v for v in values(n) if v > 1)
    @test ncounty > 0 && nplace > 30_000
end

# ---- 3. mapbbox(state) ------------------------------------------------------------------------------------------------
# Lecture 4.2's Code block 3 (4-networks/4-net-2.qmd:160-165), as text: a county's box from its block groups `B`
function _bx_lecture42(B)
    mpd = dgc((0, 0), (0, 1))                 # miles in a degree of latitude
    rad = sqrt.(B.ALAND ./ π)                 # radius as a disk, mi
    dlon = rad ./ (mpd .* cosd.(B.LAT))       # that radius in degrees of lon
    dlat = rad ./ mpd                         # and of lat
    bbW = (minimum(B.LON .- dlon), maximum(B.LON .+ dlon),
           minimum(B.LAT .- dlat), maximum(B.LAT .+ dlat))
    return bbW
end

@testset "[WP10 X7] mapbbox(state) is the extent of its counties' boxes, for every state" begin
    c, b = uscounty(), uscenblkgrp()
    # each county's block groups, in the table's order, as 4.2's `filter` takes them
    g = groupby(b, [:STFIP, :COFIP]; sort = false)
    lec = Dict((k.STFIP, k.COFIP) => _bx_lecture42(sub) for (k, sub) in pairs(g))
    @test length(lec) == nrow(c)
    # 4.2's box is mapbbox(county; state)'s, reordered, for every county a name reaches
    differ = Int[]
    for i in 1:nrow(c)
        bb = try mapbbox(String(c.NAME[i]); state = c.ST[i]) catch; nothing end
        bb === nothing && continue                               # the 12 that share a name (the testset above)
        l = lec[(c.STFIP[i], c.COFIP[i])]
        bb === ((l[1], l[2]), (l[3], l[4])) || push!(differ, i)
    end
    @test isempty(differ)
    S = usstate()
    @test nrow(S) == 51
    notext, notin = Symbol[], Symbol[]
    for st in S.ST
        sb = mapbbox(st)
        boxes = [mapbbox(((l[1], l[2]), (l[3], l[4]))) for (k, l) in lec if k[1] == st2fips(st)]   # as mapbbox(county; state) gives each
        @test length(boxes) == count(==(st), c.ST)
        ext = ((minimum(x[1][1] for x in boxes), maximum(x[1][2] for x in boxes)),
               (minimum(x[2][1] for x in boxes), maximum(x[2][2] for x in boxes)))
        sb == ext || push!(notext, st)
        all(sb[1][1] <= x[1][1] && x[1][2] <= sb[1][2] && sb[2][1] <= x[2][1] && x[2][2] <= sb[2][2] for x in boxes) ||
            push!(notin, st)
    end
    @test isempty(notext)
    @test isempty(notin)
    # the shape, the expansion, and what is not a state
    nc = mapbbox(:NC)
    @test nc isa Tuple{Tuple{Float64, Float64}, Tuple{Float64, Float64}}
    @test mapbbox(:NC; xexpand = 0.1, yexpand = 0.2) === mapbbox(nc; xexpand = 0.1, yexpand = 0.2)
    @test mapbbox(:DC) == mapbbox("District of Columbia"; state = :DC)            # one county
    @test _bx_err(() -> mapbbox(:PR)) isa ArgumentError                            # a territory: no counties
    @test _bx_err(() -> mapbbox(:XX)) isa ArgumentError
end

# ---- 4. dgca(...; method = :empirical) (X8, MakePlan D8) ---------------------------------------------------------------
# Lecture 2.5's @eq-daemp (2-location/2-loc-5.qmd:1307-1314), as text: r = √(a/π) (@eq-radius, 2.5 Sec. 5), d the
# distance from the point to the region's centroid, d < r the first case and every other d the second
_bx_daemp(d, r) = d < r ? 2r/3 + d/48 + 9d^2/(20r) : d + 3r^2/(23d)

# v0.3.0's dgca, as text (the v0.3.0 tag fd0f1f3, src/disttools.jl:277 and :339-341), which 7e66734 left unchanged
_bx_dgca_v030(X, Xa, a; unit = :mi) = max.(dists(X, Xa, unit), reshape((x -> (2 / 3) * sqrt(x / π)).(a), 1, :))
_bx_bitsame(A, B) = size(A) == size(B) && all(x === y for (x, y) in zip(A, B))

function _bx_readblocks(path)          # "@name,nrows,ncols" blocks, as test/oracle_helpers.jl reads them
    d = Dict{String, Matrix{Float64}}()
    lines = readlines(path)
    i = 1
    while i <= length(lines)
        if startswith(lines[i], "@")
            nm, r, c = split(lines[i][2:end], ',')
            r, c = parse(Int, r), parse(Int, c)
            M = Matrix{Float64}(undef, r, c)
            for k in 1:r
                M[k, :] = parse.(Float64, split(lines[i + k], ','))
            end
            d[String(nm)] = M
            i += r + 1
        else
            i += 1
        end
    end
    return d
end

# Lecture 2.5's inputs to dgca: Example 4's North Carolina three-digit ZIP codes (Code block 15, 2-loc-5.qmd:1497-1498)
# and Example 5's EMCA ZIP centroids (Code block 19, 2-loc-5.qmd:1591-1601), each with its land areas
function _bx_lecture25()
    z = filter(r -> 270 <= r.ZCTA3 <= 289 && r.POP > 0, uszcta3())
    P = hcat(z.LON, z.LAT)
    zip = [270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283,
           284, 285, 286, 287, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299]
    zc = uszcta3()
    iz = [findfirst(==(zi), zc.ZCTA3) for zi in zip]
    Pz = hcat(zc.LON[iz], zc.LAT[iz])
    return ((P, z.ALAND), (Pz, zc.ALAND[iz]))
end

@testset "[WP10 X8] dgca(...; method = :empirical) is 2.5's @eq-daemp on 2.5's inputs" begin
    for (P, a) in _bx_lecture25()
        r = sqrt.(a ./ π)
        Dg = dists(P, P, :mi)
        want = [_bx_daemp(Dg[i, j], r[j]) for i in axes(P, 1), j in axes(P, 1)]
        De = dgca(P, P, a; method = :empirical)
        @test De == want
        @test De isa Matrix{Float64}
        # both methods of dgca take the keyword: one point is the matrix method's row
        @test all(dgca(P[i, :], P, a; method = :empirical) == De[i, :] for i in axes(P, 1))
        # another unit: the same formula on that unit's distances (a in its square)
        Dk = dists(P, P, :km)
        @test dgca(P, P, a; unit = :km, method = :empirical) == [_bx_daemp(Dk[i, j], r[j]) for i in axes(P, 1), j in axes(P, 1)]
        # every point is at d = 0 from itself, so the diagonal is 2r/3, (2/3)√(a/π) as the equation writes it, and the
        # default method's floor, (2/3)·√(a/π), to the last bit or one unit in it
        dg = [De[i, i] for i in axes(P, 1)]
        @test all(Dg[i, i] == 0 for i in axes(P, 1))
        @test dg == 2 .* sqrt.(a ./ π) ./ 3
        @test all(abs.(dg .- Logjam._mean_zone_distance.(a)) .<= eps.(dg))
        # the empirical distance is never below the default's: it adds to d outside the region and to 2r/3 inside it
        @test all(De .>= dgca(P, P, a))
    end
end

@testset "[WP10 X8] :empirical against MATLAB's ise754/dagg.m on the same distances (oracle)" begin
    O = _bx_readblocks(joinpath(@__DIR__, "oracles", "dagg_matlab.csv"))
    a, R, D, Da = vec(O["a"]), vec(O["R"]), O["D"], O["Da"]
    zc = uszcta3()
    # the oracle's areas are 2.5's as Logjam holds them, its radii Logjam's sqrt(a/π), bit for bit
    zk = Int.(vec(O["zcta3"]))
    @test a == [only(zc.ALAND[zc.ZCTA3 .== k]) for k in zk]
    @test sort(zk) == sort(unique(vcat(filter(r -> 270 <= r.ZCTA3 <= 289 && r.POP > 0, zc).ZCTA3, 290:299)))
    r = sqrt.(a ./ π)
    @test r == R
    @test size(D) == size(Da) == (83, length(a))
    # Logjam's formula on the oracle's distances: the kernel dgca(...; method = :empirical) applies to dists' matrix
    L = Logjam._daemp.(D, reshape(r, 1, :))
    @test L == _bx_daemp.(D, reshape(r, 1, :))
    # dagg.m's first statement replaces each d < r by the first case; its second then tests the matrix the first
    # changed, D(D>=R), so a d whose first case is r or more (d/r from 0.8378 to 1) takes the second case on top
    f1 = [D[i, j] < r[j] ? _bx_daemp(D[i, j], r[j]) : NaN for i in axes(D, 1), j in axes(D, 2)]
    both = (D .< reshape(r, 1, :)) .& (f1 .>= reshape(r, 1, :))
    one = .!both
    @test all(isapprox.(L[one], Da[one]; rtol = 1e-14))
    # where dagg.m applies both cases, its value is the second applied to the first, which 2.5's equation is not
    g(d, r) = d + 3r^2/(23d)
    @test all(isapprox(Da[i, j], g(f1[i, j], r[j]); rtol = 1e-14) for i in axes(D, 1), j in axes(D, 2) if both[i, j])
    @test all(L[both] .< Da[both])
    t = vec(O["t"])
    @test count(both) == 4 * length(a)                         # t = 0.85, 0.9, 0.95 and r - eps(r), each area
    @test all(0.8378 < D[i, j] / r[j] < 1 for i in axes(D, 1), j in axes(D, 2) if both[i, j])
end

@testset "[WP10 X8] :empirical's branch boundary is dagg.m's; d_a > d outside the region" begin
    (P, a), (Pz, az) = _bx_lecture25()
    for ar in vcat(a, az, [1.0, 656.0, 5000.0])
        r = sqrt(ar / π)
        # at d = r the second case: 26r/23
        at = Logjam._daemp(r, r)
        @test at == r + 3r^2/(23r)
        @test isapprox(at, 26r / 23; rtol = 1e-14)
        # just below r the first case, whose limit is 546r/480 = 1.1375r: a step of about 0.6% that belongs to the formula
        d = prevfloat(r)
        below = Logjam._daemp(d, r)
        @test below == 2r/3 + d/48 + 9d^2/(20r)
        @test isapprox(below, 546r / 480; rtol = 1e-14)
        @test below > at
        # outside the region it keeps d_a > d (2.5: "a facility beyond a region still pays something for its spread")
        @test all(Logjam._daemp(t * r, r) > t * r for t in 1.0:0.01:100.0)
        # at d = 0, 2r/3
        @test Logjam._daemp(0.0, r) == 2r/3
        # through dgca: a point at distance d from a demand point of area ar
        x = [-78.64, 35.78]
        y = [-78.64, 35.78 + 0.5]
        dd = dgc(x, y)
        @test dgca(x, reshape(y, 1, 2), [ar]; method = :empirical) == [_bx_daemp(dd, r)]
    end
    # a zero area (a point): the distance itself, and 0 at d = 0, where the second case is 0/0
    @test Logjam._daemp(0.0, 0.0) === 0.0
    @test Logjam._daemp(5.0, 0.0) === 5.0
    X = [-78.64 35.78; -80.84 35.23]
    @test dgca(X, X, [0.0, 0.0]; method = :empirical) == dists(X, X, :mi)
end

@testset "[WP10 X8] dgca's default method is unchanged, bit for bit" begin
    (P, a), (Pz, az) = _bx_lecture25()
    rng = Random.Xoshiro(10)
    cases = Any[(P, P, a), (Pz, Pz, az), (P[1:5, :], Pz, az)]
    for m in (1, 7, 200)
        X = hcat(-125 .+ 58 .* rand(rng, m), 25 .+ 24 .* rand(rng, m))
        Xa = hcat(-125 .+ 58 .* rand(rng, 50), 25 .+ 24 .* rand(rng, 50))
        push!(cases, (X, Xa, 3000 .* rand(rng, 50) .* (rand(rng, 50) .> 0.2)))
    end
    for (X, Xa, aa) in cases, unit in (:mi, :km, :rad)
        v030 = _bx_dgca_v030(X, Xa, aa; unit)
        @test _bx_bitsame(dgca(X, Xa, aa; unit), v030)
        @test _bx_bitsame(dgca(X, Xa, aa; unit, method = :max), v030)
        @test _bx_bitsame(dgca(X[1, :], Xa, aa; unit, method = :max), vec(v030[1:1, :]))
    end
    @test_throws ArgumentError dgca(P, P, a; method = :exact)
    @test_throws ArgumentError dgca(P[1, :], P, a; method = "empirical")
    @test_throws ErrorException dgca(P, P, a[1:3]; method = :empirical)
    @test_throws ErrorException dgca(P, P, -a; method = :empirical)
end
