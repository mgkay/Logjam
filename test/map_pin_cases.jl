# map_pin_cases.jl -- the course's makemap call shapes, and what each returns that a lecture sees
# (PCV K11a, plan principle 9). Used by test_map_pins.jl, which holds the values the unchanged code gave.
#
# What the course sees of a `makemap` call: the figure's size, the axis limits it was asked for and the projected
# extent the axis shows, and the base-layer plots it drew (their labels, point counts and styles). The calls are
# the shapes the lectures use (2.2, 2.3, 2.5, 2.6, 2.7, 3.4, 4.1, 4.2, 5.1, 5.2, 5.3), on shipped data (the NC
# cities of Lecture 5.2's tours) or on points set by hand, never on an examination's.

using Logjam
using DataFrames
using CairoMakie
using GeoMakie

# the NC cities over 100,000 people: README Example 4, Lecture 5.2 (`df.LON`, `df.LAT`)
mmpin_nc() = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())

# Lecture 4.2's first box, as `mapbbox` returns it (`4-net-2.qmd:319-320`, rounded to what the lecture prints)
const MMPIN_BB42 = ((-78.688, -78.657), (35.762, 35.796))

# what a lecture sees of a map: size, limits, projected extent (6 significant digits), base layers
function mmpin_describe(fig, ax)
    ext = ax.finallimits[]
    layers = Tuple[]
    for p in ax.scene.plots
        haskey(p.attributes, :label) || continue                 # GeoAxis's own two unlabeled plots are not the base layer
        c = p.color[]
        push!(layers, (string(p.label[]), length(p[1][]), round(Float64(Makie.Colors.alpha(Makie.to_color(c))), digits = 3), round(Float64(p.linewidth[]), digits = 3),
                       p.linestyle[] === nothing ? "solid" : "dashed"))
    end
    return (size = size(fig.scene),
            limits = ax.limits[],
            extent = (round.(Tuple(ext.origin), sigdigits = 6), round.(Tuple(ext.widths), sigdigits = 6)),
            layers = layers)
end

# name => thunk returning (fig, ax) from the call exactly as the course writes it
function mmpin_cases()
    nc = mmpin_nc()
    dc = ([-77.1, -76.9, -77.0], [38.8, 38.95, 38.9])                   # a city-sized frame, `xexpand = 0.04, yexpand = 0.04` (2.6)
    sac = ([-122.0, -121.0, -121.5], [38.0, 39.0, 38.5])
    return [
        "xy_default"           => () -> makemap(nc.LON, nc.LAT),                                       # 2.2, 4.1 (`makemap(N.LON[dijk], N.LAT[dijk])`)
        "xy_xexpand_0.1"       => () -> makemap(nc.LON, nc.LAT; xexpand = 0.1),                         # 2.3, 2.7
        "xy_xexpand_0.3"       => () -> makemap(nc.LON, nc.LAT; xexpand = 0.3),                         # 5.2 (`5-rte-2.qmd:634`)
        "xy_xexpand_0.05"      => () -> makemap(nc.LON, nc.LAT; xexpand = 0.05),                        # 5.1, 5.2, 5.3
        "xy_both_expands"      => () -> makemap(dc[1], dc[2]; xexpand = 0.04, yexpand = 0.04),          # 2.6
        "noroad_both_expands"  => () -> makemap(sac[1], sac[2]; doRoadbkgd = false, xexpand = 0.6, yexpand = 2.0),   # 4.1 (`4-net-1.qmd:1096` shape)
        "noroad_small_expands" => () -> makemap(nc.LON, nc.LAT; doRoadbkgd = false, xexpand = 0.02, yexpand = 0.02),  # 4.1 (`:1723`, `:1932` shape)
        "box_noroad_noexpand"  => () -> makemap(MMPIN_BB42[1], MMPIN_BB42[2]; doRoadbkgd = false, xexpand = 0, yexpand = 0),  # 4.2 (`4-net-2.qmd:319-320, 944-945`)
        "tuple_pair"           => () -> makemap((-80.0, -75.0), (35.0, 40.0); xexpand = 0.1),           # the NTuple{2} form
        "region_CUS"           => () -> makemap(region = :CUS),                                         # 2.3 (`makemap(region = :CUS)`)
        "region_US"            => () -> makemap(; region = :US),                                        # 2.5 (`makemap(; region = region)`)
        "region_World"         => () -> makemap(),                                                      # 2.3's first call
        "xy_hawaii_not_CUS"    => () -> makemap([-158.0, -155.0], [19.0, 22.0]),                        # US limits, not CUS
        "xy_outside_US"        => () -> makemap([2.0, 13.0], [48.0, 52.0]),                             # country borders only
    ]
end
