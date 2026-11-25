# lecture42_code.jl -- Lecture 4.2's Code block 3 (a county's box from the Census block groups in it), as the lecture
# writes it (4-networks/4-net-2.qmd:157-171), kept as text so a test can evaluate it in a scratch module (PCV K12,
# principle 9, CR 28). Only the `@show` lines are dropped; the lecture shows the county as Wake, North Carolina.

const LECTURE42_COUNTY_BOX = raw"""
co = only(filter(r -> r.ST == :NC && r.NAME == "Wake", uscounty()))
B = filter(r -> r.STFIP == co.STFIP && r.COFIP == co.COFIP,
           uscenblkgrp())                 # Wake's block groups
mpd = dgc((0, 0), (0, 1))                 # miles in a degree of latitude
rad = sqrt.(B.ALAND ./ π)                 # radius as a disk, mi  # <1>
dlon = rad ./ (mpd .* cosd.(B.LAT))       # that radius in degrees of lon
dlat = rad ./ mpd                         # and of lat
bbW = (minimum(B.LON .- dlon), maximum(B.LON .+ dlon),
       minimum(B.LAT .- dlat), maximum(B.LAT .+ dlat))
wide = (bbW[2] - bbW[1]) * mpd * cosd((bbW[3] + bbW[4]) / 2)
high = (bbW[4] - bbW[3]) * mpd
"""

# A scratch module that has done `using Logjam` and `using DataFrames`, then runs Code block 3; `bbW`, `B`, `wide`,
# `high` are its globals.
function lecture42_module()
    m = Module(:Lecture42)
    Core.eval(m, :(using Logjam))
    Core.eval(m, :(using DataFrames))
    include_string(m, LECTURE42_COUNTY_BOX, "4-net-2.qmd")
    return m
end
