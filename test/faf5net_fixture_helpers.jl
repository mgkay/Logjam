# faf5net_fixture_helpers.jl -- the small extract of SC 1's T1.3 (PCV N3): FAF5 as Logjam ships it, cut to a box around
# Raleigh, and the network the derivation makes of it. The box, the cut, the reader and the bytes the driver would
# write. Kept apart from test_faf5net.jl so tools/v0_3_2/make_faf5net_fixture.jl can load it without running tests.

using Logjam
using DataFrames
using CSV

const FN_FIXTURE_DIR = joinpath(@__DIR__, "fixtures", "faf5net_raleigh")

# (lon, lat): downtown Raleigh and its Beltline, so the extract holds Interstate interchanges (I-40, I-440), divided
# US routes (US 1, US 64, US 70, US 401 with its McDowell and Dawson couplet), at-grade junctions and city streets
const FN_RALEIGH_BOX = ((-78.72, -78.58), (35.73, 35.83))

# The FAF5 link columns the derivation reads (`Logjam._faf5net`), with their types as read back from the extract
const FN_EXTRACT_LINK_TYPES = ["SRC" => Int, "DST" => Int, "DIST" => Float64, "DIR" => Int, "FCLASS" => Int,
                               "SIGN" => Union{Missing,String}, "NAME" => Union{Missing,String}, "SPEED" => Int,
                               "AB_SPEED" => Float64, "BA_SPEED" => Float64, "AB_TIME" => Float64, "BA_TIME" => Float64,
                               "STFIP" => Int, "COFIP" => Int, "URBAN" => Union{Missing,Int}]
const FN_EXTRACT_NODE_TYPES = ["IDX" => Int, "LON" => Float64, "LAT" => Float64]
const FN_EXTRACT = ("faf5_nodes.csv", "faf5_links.csv")
const FN_DERIVED = ("faf5net_nodes.csv", "faf5net_links.csv", "faf5net_nodemap.csv")

# FAF5 cut to the box: the links with both ends inside it, and the nodes those links use
function fn_cut(N, L; box = FN_RALEIGH_BOX)
    (x0, x1), (y0, y1) = box
    inside = Set{Int}(N.IDX[(x0 .<= N.LON .<= x1) .& (y0 .<= N.LAT .<= y1)])
    Lx = L[in.(L.SRC, Ref(inside)) .& in.(L.DST, Ref(inside)), first.(FN_EXTRACT_LINK_TYPES)]
    used = Set{Int}([Lx.SRC; Lx.DST])
    Nx = N[in.(N.IDX, Ref(used)), first.(FN_EXTRACT_NODE_TYPES)]
    return Nx, Lx
end

# A table's bytes as Logjam._faf5net_csv writes it (the driver's writer); `four = ()` writes every number exactly
fn_bytes(df; kw...) = (io = IOBuffer(); Logjam._faf5net_csv(io, df; kw...); take!(io))

# The extract's two files, every number written exactly
fn_extract_bytes(Nx, Lx) = (fn_bytes(Nx; four = ()), fn_bytes(Lx; four = ()))

function fn_read_extract(dir = FN_FIXTURE_DIR)
    rd(f, spec) = CSV.read(joinpath(dir, f), DataFrame; types = Dict{String,Type}(spec), stringtype = String, pool = false)
    return rd(FN_EXTRACT[1], FN_EXTRACT_NODE_TYPES), rd(FN_EXTRACT[2], FN_EXTRACT_LINK_TYPES)
end

# The derived network of an extract, as the bytes of its three files, written as the driver writes the shipped ones
function fn_derived_bytes(N, L)
    R = Logjam._faf5net(N, L)
    return Tuple(fn_bytes(df) for df in (R.nodes, R.links, R.nodemap))
end
