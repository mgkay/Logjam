# test_map_line_pins.jl -- what the course sees of `plotroads!`, the base-layer styles `makemap` draws, the FAF5
# tables and `tracepath`, pinned from the code at 83c799b (PCV K11b, plan principle 9; K11a's own pins are
# test_map_pins.jl). The values below were measured on the unchanged code, before K11b's C4 (`makemap`'s interface),
# C8 (the line builders) and C12 (cached FAF5 tables) changed it. A call the course makes today keeps returning
# what it returned then; only a case named in MLPIN_MOVED may differ, and each one is named in the commit that moves it.
#
# No case touches the network or a file outside the package, and none renders a picture.

using Test
using Logjam
using DataFrames
using CairoMakie
using GeoMakie

# case name => ruled ID that moves it. N4 (CR 19): the road layer of a map spanning more than 20 and at most 30 degrees of
# latitude is drawn at opacity 0.3, not 0.35 (S23: every stroke below 0.35); its width, 0.3, stays. Pinned again in
# test_map_tiers.jl (T5.6).
# N4b (RN26): the regional tier's road layer is labeled "Major Roads", not "Interstate Roads"; the regional frames and the
# spans of 9 and 10 degrees move under that alone (the national tier keeps its label). Pinned again in test_map_tiers.jl.
const MLPIN_MOVED = Dict{String, String}("layers_CUS_map" => "N4", "road_tier_20.5" => "N4", "road_tier_29.99" => "N4",
                                         "road_tier_30.0" => "N4", "layers_NC_frame" => "N4b (RN26)",
                                         "layers_Hawaii_frame" => "N4b (RN26)", "layers_Europe_frame" => "N4b (RN26)",
                                         "road_tier_9.0" => "N4b (RN26)", "road_tier_10.0" => "N4b (RN26)")

_mlpin_moved(name) = haskey(MLPIN_MOVED, name) && (@info("line pin $name moved under $(MLPIN_MOVED[name])"); true)

# ---- plotroads! on Lecture 2.5's call shape ------------------------------------------------------------------
# `for (k, v) in plotroads!(ax, faf5nodes(), faf5links())` (2-loc-5.qmd:175), on a map from `makemap(...; doRoadbkgd = false)`:
# the keys, each plot's point count, color (RGB), alpha, linewidth, cap and style, and the order the plots are drawn in.
function _mlpin_roads_describe(ax, h)
    rows = Tuple[]
    for k in sort!(collect(keys(h)); by = string)
        p = h[k]
        c = Makie.to_color(p.color[])
        push!(rows, (string(k), length(p[1][]),
                     round.(Float64[Makie.Colors.red(c), Makie.Colors.green(c), Makie.Colors.blue(c)], digits = 3),
                     round(Float64(p.alpha[]), digits = 3), round(Float64(p.linewidth[]), digits = 3), string(p.linecap[]),
                     p.linestyle[] === nothing ? "solid" : "dashed"))
    end
    order = sort!(collect(keys(h)); by = k -> findfirst(q -> q === h[k], ax.scene.plots))
    return rows, [string(k) for k in order]
end

const _MLPIN_TIERS_CLOSE = Tuple[
    ("casing_1", 511119, [0.35, 0.42, 0.52], 0.6, 1.6, "2", "solid"), ("casing_2", 209499, [0.45, 0.55, 0.4], 0.5, 1.5, "2", "solid"),
    ("casing_3", 378978, [0.65, 0.52, 0.3], 0.4, 1.3, "2", "solid"), ("casing_4", 185919, [0.6, 0.58, 0.48], 0.35, 1.1, "2", "solid"),
    ("casing_5", 165075, [0.65, 0.65, 0.65], 0.3, 0.9, "2", "solid"),
    ("fill_1", 511119, [0.6, 0.7, 0.82], 0.6, 1.0, "2", "solid"), ("fill_2", 209499, [0.72, 0.82, 0.72], 0.5, 0.9, "2", "solid"),
    ("fill_3", 378978, [0.9, 0.82, 0.7], 0.4, 0.7, "2", "solid"), ("fill_4", 185919, [0.92, 0.9, 0.8], 0.35, 0.5, "2", "solid"),
    ("fill_5", 165075, [0.95, 0.95, 0.95], 0.3, 0.3, "2", "solid"),
]
const _MLPIN_ORDER_CLOSE = ["casing_5", "casing_4", "casing_3", "casing_2", "casing_1", "fill_5", "fill_4", "fill_3", "fill_2", "fill_1"]
const _MLPIN_TIERS_MID = Tuple[
    ("fill_1", 511119, [0.6, 0.7, 0.82], 0.4, 0.7, "2", "solid"), ("fill_2", 209499, [0.72, 0.82, 0.72], 0.35, 0.6, "2", "solid"),
    ("fill_3", 378978, [0.9, 0.82, 0.7], 0.25, 0.4, "2", "solid"), ("fill_4", 185919, [0.92, 0.9, 0.8], 0.2, 0.3, "2", "solid"),
    ("fill_5", 165075, [0.95, 0.95, 0.95], 0.15, 0.15, "2", "solid"),
]
const _MLPIN_TIERS_FAR = Tuple[
    ("fill_1", 511119, [0.6, 0.7, 0.82], 0.25, 0.25, "2", "solid"), ("fill_2", 209499, [0.72, 0.82, 0.72], 0.2, 0.2, "2", "solid"),
    ("fill_3", 378978, [0.9, 0.82, 0.7], 0.15, 0.12, "2", "solid"), ("fill_4", 185919, [0.92, 0.9, 0.8], 0.1, 0.08, "2", "solid"),
    ("fill_5", 165075, [0.95, 0.95, 0.95], 0.08, 0.05, "2", "solid"),
]
const _MLPIN_ORDER_FILL = ["fill_5", "fill_4", "fill_3", "fill_2", "fill_1"]

# name => (call, latitude span of the axis, expected rows, expected draw order)
const MLPIN_ROADS = [
    ("metro_close",    () -> makemap([-78.9, -78.5], [35.6, 36.0]; xexpand = 0.02, yexpand = 0.02, doRoadbkgd = false), _MLPIN_TIERS_CLOSE, _MLPIN_ORDER_CLOSE),
    ("region_close",   () -> makemap([-84.0, -76.0], [33.0, 40.0]; xexpand = 0.02, yexpand = 0.02, doRoadbkgd = false), _MLPIN_TIERS_CLOSE, _MLPIN_ORDER_CLOSE),
    ("eastern_mid",    () -> makemap([-90.0, -70.0], [28.0, 44.0]; xexpand = 0.0, yexpand = 0.0, doRoadbkgd = false), _MLPIN_TIERS_MID, _MLPIN_ORDER_FILL),
    ("region_CUS_far", () -> makemap(region = :CUS, doRoadbkgd = false), _MLPIN_TIERS_FAR, _MLPIN_ORDER_FILL),
]

@testset "plotroads! on Lecture 2.5's call shape is pinned: keys, styles, point counts, draw order" begin
    dfN, dfL = faf5nodes(), faf5links()
    for (name, thunk, rows, order) in MLPIN_ROADS
        @testset "$name" begin
            _mlpin_moved("plotroads_" * name) && continue
            fig, ax = thunk()
            h = plotroads!(ax, dfN, dfL)
            @test h isa Dict{Symbol, Any}
            got, gorder = _mlpin_roads_describe(ax, h)
            @test got == rows
            @test gorder == order
        end
    end

    @testset "it iterates as k => v pairs and v.color can be reassigned, as dotmap does" begin
        if !_mlpin_moved("plotroads_dotmap_loop")
            fig, ax = makemap([-78.9, -78.5], [35.6, 36.0]; xexpand = 0.02, yexpand = 0.02, doRoadbkgd = false)
            n = 0
            for (k, v) in plotroads!(ax, dfN, dfL)                # 2-loc-5.qmd:175-178
                v.color = (:steelblue, startswith(String(k), "casing") ? 0.12 : 0.45)
                n += 1
                c = Makie.to_color(v.color[])
                @test Makie.Colors.alpha(c) ≈ (startswith(String(k), "casing") ? 0.12 : 0.45) atol = 1e-6
            end
            @test n == 10
            @test first(plotroads!(ax, dfN, dfL)) isa Pair{Symbol, Any}
        end
    end

    @testset "a small table: connectors hidden unless asked, drawn dashed when shown" begin
        if !_mlpin_moved("plotroads_connectors")
            fig, ax = makemap([-78.9, -78.5], [35.6, 36.0]; doRoadbkgd = false)
            dn = DataFrame(IDX = 1:4, LON = [-78.8, -78.7, -78.6, -78.55], LAT = [35.7, 35.8, 35.9, 35.95])
            dl = DataFrame(SRC = [1, 2, 3], DST = [2, 3, 4], FCLASS = [1, 3, 6], SOURCE = ["FAF5", "OSM", "CONNECTOR"])
            h = plotroads!(ax, dn, dl)
            @test sort!(string.(keys(h))) == ["casing_1", "casing_3", "fill_1", "fill_3"]
            h = plotroads!(ax, dn, dl; show_connectors = true)
            @test sort!(string.(keys(h))) == ["casing_1", "casing_3", "connector", "fill_1", "fill_3"]
            r, _ = _mlpin_roads_describe(ax, h)
            @test r[3] == ("connector", 3, [0.549, 0.549, 0.549], 1.0, 0.3, "2", "dashed")
            @test r[4] == ("fill_1", 3, [0.6, 0.7, 0.82], 0.6, 1.0, "2", "solid")
        end
    end
end

# ---- the base layers makemap draws: color, alpha attribute, width, style, and the road layer's zoom tiers ----------
# (a width for each point, N4's regional road tier, reads as its widest, the Interstate's)
_mlpin_width(w) = w isa AbstractVector ? maximum(w) : w
function _mlpin_layers(ax)
    rows = Tuple[]
    for p in ax.scene.plots
        haskey(p.attributes, :label) || continue
        c = Makie.to_color(p.color[])
        push!(rows, (string(p.label[]),
                     round.(Float64[Makie.Colors.red(c), Makie.Colors.green(c), Makie.Colors.blue(c), Makie.Colors.alpha(c)], digits = 3),
                     round(Float64(p.alpha[]), digits = 3), round(Float64(_mlpin_width(p.linewidth[])), digits = 3),
                     p.linestyle[] === nothing ? "solid" : "dashed"))
    end
    return rows
end

# name => (call, expected layers: label, RGBA, `alpha` attribute, linewidth, style)
const MLPIN_LAYERS = [
    ("US_map",    () -> makemap(region = :US),
        Tuple[("US State Borders", [0.0, 0.0, 1.0, 1.0], 0.5, 0.75, "dashed"), ("Country Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("world_map", () -> makemap(),
        Tuple[("Country Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("CUS_map",   () -> makemap(region = :CUS),
        Tuple[("Interstate Roads", [0.275, 0.51, 0.706, 0.35], 1.0, 0.3, "solid"), ("US State Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("NC_frame",  () -> makemap([-80.0, -77.0], [35.0, 36.0]),
        Tuple[("Interstate Roads", [0.275, 0.51, 0.706, 0.2], 1.0, 0.6, "solid"), ("US State Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("Hawaii_frame", () -> makemap([-158.0, -155.0], [19.0, 22.0]),
        Tuple[("Interstate Roads", [0.275, 0.51, 0.706, 0.2], 1.0, 0.6, "solid"), ("US State Borders", [0.0, 0.0, 1.0, 1.0], 0.5, 0.75, "dashed"), ("Country Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
    ("Europe_frame", () -> makemap([2.0, 13.0], [48.0, 52.0]),
        Tuple[("Interstate Roads", [0.275, 0.51, 0.706, 0.2], 1.0, 0.6, "solid"), ("Country Borders", [0.0, 0.0, 1.0, 1.0], 1.0, 0.75, "solid")]),
]

@testset "makemap's base-layer styles are pinned: color, alpha attribute, width, style" begin
    for (name, thunk, want) in MLPIN_LAYERS
        @testset "$name" begin
            _mlpin_moved("layers_" * name) && continue
            fig, ax = thunk()
            @test _mlpin_layers(ax) == want
        end
    end
end

# the road layer's tiers by latitude span (limits (-100, -90) x (y0, y0 + span), no expansion): alpha and width, and nothing past 30 degrees
const MLPIN_ROAD_TIERS = [   # span, y0 => (road alpha, road linewidth) or nothing when no road layer is drawn
    (9.0, 30.0, (0.2, 0.6)), (10.0, 30.0, (0.2, 0.6)), (10.5, 30.0, (0.25, 0.5)), (20.0, 30.0, (0.25, 0.5)),
    (20.5, 30.0, (0.35, 0.3)), (29.99, 20.0, (0.35, 0.3)), (30.0, 20.0, (0.35, 0.3)), (30.5, 20.0, nothing),
]

@testset "makemap's road layer by latitude span: today's tiers, nothing above 30 degrees" begin
    for (span, y0, want) in MLPIN_ROAD_TIERS
        @testset "span $span" begin
            _mlpin_moved("road_tier_$span") && continue
            fig, ax = makemap([-100.0, -90.0], [y0, y0 + span]; xexpand = 0, yexpand = 0)
            roads = [r for r in _mlpin_layers(ax) if r[1] == "Interstate Roads"]
            if want === nothing
                @test isempty(roads)
            else
                @test length(roads) == 1
                @test (roads[1][2][4], roads[1][4]) == want
                @test roads[1][2][1:3] == [0.275, 0.51, 0.706]
            end
        end
    end
end

# ---- the FAF5 tables -----------------------------------------------------------------------------------------
# A checksum of a column: FNV-1a over the column's values in order (integers and floats by their 64 bits, strings by
# their bytes, a missing by a marker), so a change to any value or to the order changes it.
const _MLPIN_FNV_PRIME = 0x00000100000001b3
_mlpin_mix(h::UInt64, x::UInt64) = (h ⊻ x) * _MLPIN_FNV_PRIME
_mlpin_mix(h::UInt64, v::Integer) = _mlpin_mix(h, reinterpret(UInt64, Int64(v)))
_mlpin_mix(h::UInt64, v::AbstractFloat) = _mlpin_mix(h, reinterpret(UInt64, Float64(v)))
_mlpin_mix(h::UInt64, ::Missing) = _mlpin_mix(h, "<missing>")
function _mlpin_mix(h::UInt64, s::AbstractString)
    for b in codeunits(s)
        h = _mlpin_mix(h, UInt64(b))
    end
    return _mlpin_mix(h, UInt64(0xff))
end
function _mlpin_colsum(col)
    h = 0xcbf29ce484222325
    for v in col
        h = _mlpin_mix(h, v)
    end
    return string(h, base = 16)
end
# a column's kind: Int64, Float64 or String, with a "?" when it can hold a missing
_mlpin_kind(T) = (nonmissingtype(T) <: AbstractString ? "String" : string(nonmissingtype(T))) * (Missing <: T ? "?" : "")
_mlpin_table(df) = (size = size(df), names = names(df), kinds = [_mlpin_kind(eltype(c)) for c in eachcol(df)],
                    sums = [_mlpin_colsum(c) for c in eachcol(df)], missings = [count(ismissing, c) for c in eachcol(df)])

const MLPIN_FAF5NODES = (size = (344998, 10),
    names = ["IDX", "LON", "LAT", "ENTRY_EXIT", "EXIT_NUM", "INTERCHANGE", "FACILITY_TYPE", "FACILITY_NAME", "STATEID", "FAFID"],
    kinds = ["Int64", "Float64", "Float64", "String?", "String?", "String?", "String?", "String?", "Int64", "Int64"],
    sums = ["6b3aebb8b846557d", "4a958dc40e2a898d", "84ff8720cb07404a", "60b10316d13d1d8d", "b2ba03681c6ce1ad", "9df270cb6fc10912", "a4add17fdde1bcda", "2b2d0ba73a38d503", "1267def9b11825bd", "1267def9b11825bd"],
    missings = [0, 0, 0, 343440, 343928, 343434, 340054, 340052, 0, 0])
const MLPIN_FAF5LINKS = (size = (483530, 25),
    names = ["SRC", "DST", "DIST", "STFIP", "COFIP", "SPEED", "NHS", "SIGN", "NAME", "FCLASS", "URBAN", "AB_SPEED", "BA_SPEED", "AB_TIME", "BA_TIME", "AB_LANES", "BA_LANES", "DIR", "STRAHNET", "NHFN", "TOLL_TYPE", "TOLL_LINK", "BORDER_LINK", "FAFZONE", "STATUS"],
    kinds = ["Int64", "Int64", "Float64", "Int64", "Int64", "Int64", "Int64", "String?", "String?", "Int64", "Int64?", "Float64", "Float64", "Float64", "Float64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64", "Int64"],
    sums = ["243c235cf38d51e8", "9002e4b393d3b973", "56d69e43bcb4bb3c", "5679e14f1251eae9", "6b291df2c012aaa1", "c1097f45a8cd0fc0", "c7119800158f324c", "48b68dea93374b0a", "ac1e14a791acf526", "d1ee499f29259c3a", "90727a59dccce0b9", "f8c837a2c4c4638f", "28acf4a8e83154", "9e08ff7d099f7387", "53bdeebb85c2b3b6", "a525fbd32be3e0a4", "cc579de8e90b930d", "336aeb10c85588e1", "6cd98b3bd6e9114f", "ce71afbc78865c4f", "239f9da6c6fd7c1f", "c3f8f56d007d5728", "55c050ace0ac4eca", "4cebd0932d71a30e", "ba15765f6cd9e71d"],
    missings = [0, 0, 0, 0, 0, 0, 0, 247001, 38692, 0, 1758, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])

@testset "faf5nodes() and faf5links() are pinned: sizes, column names, kinds, per-column checksums" begin
    @testset "faf5nodes" begin
        _mlpin_moved("faf5nodes") || @test _mlpin_table(faf5nodes()) == MLPIN_FAF5NODES
    end
    @testset "faf5links" begin
        _mlpin_moved("faf5links") || @test _mlpin_table(faf5links()) == MLPIN_FAF5LINKS
    end
    @testset "each call returns a table of its own: changing one never changes the next" begin
        if !_mlpin_moved("faf5_fresh_copies")
            a = faf5links()
            a.DIST .= -1.0
            a.SIGN[1] = "changed"
            deleteat!(a, 1:10)
            b = faf5links()
            @test _mlpin_table(b) == MLPIN_FAF5LINKS
            @test a !== b
            n = faf5nodes()
            n.LON .= 0.0
            select!(n, [:IDX, :LON])
            @test _mlpin_table(faf5nodes()) == MLPIN_FAF5NODES
        end
    end
end

# ---- tracepath on the course's idiom -------------------------------------------------------------------------
# `tracepath(P[i], i, j)` (4-net-1.qmd:1480, 1585; 4-net-2.qmd:271, 941) and the tour along the roads,
# `reduce(vcat, [tracepath(P[i], i, j)[1:end-1] for (i, j) in legs])` then the last node (5-rte-1.qmd:2682-2684,
# 5-rte-3.qmd:3731-3734), on a six-node network with no ties among its shortest paths.
@testset "tracepath(P[i], i, j) on the course's idiom is pinned" begin
    if !_mlpin_moved("tracepath_idiom")
        links = DataFrame(SRC = [1, 2, 3, 4, 2, 5], DST = [2, 3, 4, 5, 5, 6], DIST = [10.0, 20.0, 15.0, 5.0, 41.0, 7.0], DIR = [0, 0, 0, 0, 0, 0])
        D, P = shortestpaths(links2graph(links), 6)
        @test P == [[0, 1, 2, 3, 4, 5], [2, 0, 2, 3, 4, 5], [2, 3, 0, 3, 4, 5], [2, 3, 4, 0, 4, 5], [2, 3, 4, 5, 0, 5], [2, 3, 4, 5, 6, 0]]
        @test tracepath(P[1], 1, 6) == [1, 2, 3, 4, 5, 6]
        @test tracepath(P[6], 6, 1) == [6, 5, 4, 3, 2, 1]
        @test tracepath(P[3], 3, 3) == [3]                                  # origin == dest is the one node
        @test tracepath(P[2], 2, 1) == [2, 1]
        @test_throws ArgumentError tracepath([0, 1, 0], 1, 3)               # unreachable
        legs = zip([1, 3, 6, 2], [3, 6, 2, 1])
        path = reduce(vcat, [tracepath(P[i], i, j)[1:end-1] for (i, j) in legs])
        push!(path, 1)
        @test path == [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1]
    end
end
