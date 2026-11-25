# k11c_pin_cases.jl -- the course's `makemap` calls that use the default road layer, and what each draws today
# (PCV K11c, plan principle 9). Used by test_map_k11c_pins.jl, which holds the values the unchanged code gave.
#
# A call is listed once per shape; the files and lines that make it are in the comments. The data are Logjam's own
# (`usplace`, `uscounty`, `faf5nodes`) or, where a lecture's data file is the lecture's (2.6's and 2.7's), its
# bounding corners: `makemap`'s box depends on the extremes of the points and on nothing else, so two points at the
# corners draw the same box, and no lecture data file is copied into the package.

using Logjam
using DataFrames
using CairoMakie
using GeoMakie

include(joinpath(@__DIR__, "map_pin_cases.jl"))       # mmpin_nc, mmpin_describe

# Lecture 2.5's `extent` (2-loc-5.qmd:160-164): the larger of the north-south and the east-west great-circle extents
# through the center of the box, in miles
function k11c_extent(box)
    (x0, x1), (y0, y1) = box
    xm, ym = (x0 + x1) / 2, (y0 + y1) / 2
    return max(dgc([xm, y0], [xm, y1]), dgc([x0, ym], [x1, ym]))
end

# name => thunk returning (fig, ax) from the call as the course writes it
function k11cpin_cases()
    places = usplace()
    nc = mmpin_nc()
    carolinas = filter(r -> r.STFIP in st2fips.([:NC, :SC]) && r.POP > 10_000, places)
    counties = filter(r -> r.STFIP == st2fips(:NC), uscounty())
    dwt = ([-79.0993, -78.4972], [35.5762, 36.0879])               # 2.7's DWTclinics.csv: its corners
    popco = ([-123.029632, -103.18651], [32.137659, 47.582691])    # 2.6's PopcoData.csv: its corners
    city(name, st) = first(filter(r -> r.NAME == name && r.ST == st, places))
    hp, gb = city("High Point", :NC), city("Goldsboro", :NC)
    nodes = faf5nodes()
    inbox = (-79.4 .<= nodes.LON .<= -78.2) .& (35.4 .<= nodes.LAT .<= 36.3)
    return [
        # 2.2 `2-loc-2.qmd:1309` (and its companion .jl), make_nc_cities_minisum.jl:38, 2-Loc-3-cells.jl:111, 161
        "nc_cities_default"        => () -> makemap(nc.LON, nc.LAT),
        # 4.2 `4-net-2.qmd:1486`
        "nc_cities_xe0.2"          => () -> makemap(nc.LON, nc.LAT; xexpand = 0.2),
        # 2.3 `2-loc-3.qmd:1488`; 2-Loc-4-cells.jl:149 (staged: the same box with its own filter)
        "carolinas_xe0.1"          => () -> makemap(carolinas.LON, carolinas.LAT; xexpand = 0.1),
        # 5.1 `5-rte-1.qmd:2470, 2494, 2685`; 5.2 `5-rte-2.qmd:2046, 2075`; 5.3 `5-rte-3.qmd:3727`
        "nc_counties_xe0.05"       => () -> makemap(counties.LON, counties.LAT; xexpand = 0.05),
        # 2.7 `2-loc-7.qmd:2053`
        "nc_counties_xe0.1"        => () -> makemap(counties.LON, counties.LAT; xexpand = 0.1),
        # 2.7 `2-loc-7.qmd:2120`: the clinics are in Durham County
        "dwt_clinics_0.25"         => () -> makemap(dwt[1], dwt[2]; xexpand = 0.25, yexpand = 0.25),
        # 2.6 `2-loc-6.qmd:702`; 2-Loc-7-cells.jl:18 is the same points with the default expansion
        "popco_xe0.04"             => () -> makemap(popco[1], popco[2]; xexpand = 0.04, yexpand = 0.04),
        "popco_default"            => () -> makemap(popco[1], popco[2]),
        # 2.3's generator make_circuity_road_vs_gc.jl:65: High Point to Goldsboro, 163 miles across, just over the line
        "high_point_goldsboro"     => () -> makemap([hp.LON, gb.LON], [hp.LAT, gb.LAT]; xexpand = 0.22, yexpand = 0.22),
        # a probe (_probe-faf5-ex4.jl:59, `doRoadbkgd = true`): the Triangle's FAF5 nodes
        "triangle_node_box"        => () -> makemap(nodes.LON[inbox], nodes.LAT[inbox]; xexpand = 0.1, yexpand = 0.1),
    ]
end

# Two synthetic boxes around Raleigh drawn exactly as given, a hair under and over 150 miles across (a degree of
# latitude is 69.0966 miles on Logjam's sphere). The first pair is tall (north-south governs), the second wide.
const K11C_DEG = 3958.75 * pi / 180
k11c_tall(miles) = ((-79.0, -78.9), (35.0, 35.0 + miles / K11C_DEG))
k11c_wide(miles) = ((-80.0, -80.0 + miles / (K11C_DEG * cosd(35.5))), (35.4, 35.6))
function k11cpin_synthetic()
    return [
        "synthetic_tall_149"  => () -> makemap(k11c_tall(149.0)),
        "synthetic_tall_151"  => () -> makemap(k11c_tall(151.0)),
        "synthetic_wide_149"  => () -> makemap(k11c_wide(149.0)),
        "synthetic_wide_151"  => () -> makemap(k11c_wide(151.0)),
    ]
end
