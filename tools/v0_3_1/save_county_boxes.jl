# save_county_boxes.jl -- the box `mapbbox(name; state)` gives every county of `uscounty()`, saved before WP10
# changed `mapbbox` (Logjam v0.3.1, PCV WP10, MakePlan D3; test spec Sec. 6, "every county in uscounty() gives a box
# === to the branch's start").
#
#   julia +1.12.6 --project=<Logjam> tools/v0_3_1/save_county_boxes.jl <output file>
#
# For each row of `uscounty()`, in its order, it calls `mapbbox(NAME; state = ST)` with the county's name as the
# table writes it and its state's Symbol, and writes one line: STFIP, COFIP, ST, NAME and the box's four bounds,
# each float in Julia's shortest form that reads back as the same Float64 (`repr`), so `parse(Float64, s) === x`. A
# call that throws (a name two counties share in one state, as "Baltimore" in Maryland does) writes no bounds and
# the error's type and message, so the test can check that the call still throws exactly that. LF line endings, no
# time stamp; the same bytes every run.
#
# Run once at f3f0c1b (the branch's head when WP10 began; src/maptools.jl is unchanged there since the release
# branch's start 7e66734, and WP3's kernel and WP5's loader left dgc and the census tables value for value as they
# were), before any WP10 change to src/, writing test/data/county_boxes_f3f0c1b.csv; test/test_boxes_v031.jl reads it.

using Logjam, DataFrames, SHA

length(ARGS) == 1 || error("usage: save_county_boxes.jl <output file>")
out = ARGS[1]

c = uscounty()
io = IOBuffer()
println(io, "# The box mapbbox(NAME; state = ST) gave each county of uscounty() at f3f0c1b, before WP10 changed mapbbox")
println(io, "# (tools/v0_3_1/save_county_boxes.jl). Floats in Julia's shortest round-trip form; a call that threw has")
println(io, "# no bounds and its error in ERROR.")
println(io, "STFIP,COFIP,ST,NAME,LONmin,LONmax,LATmin,LATmax,ERROR")
nerr = 0
for r in eachrow(c)
    name = String(r.NAME)
    occursin(',', name) && error("a county name with a comma: $name")
    bb = try
        mapbbox(name; state = r.ST)
    catch e
        e
    end
    if bb isa Exception
        global nerr += 1
        msg = sprint(showerror, bb)                  # "ArgumentError: ..."
        occursin(',', msg) && error("an error message with a comma: $msg")
        println(io, join((r.STFIP, r.COFIP, r.ST, name, "", "", "", "", msg), ','))
    else
        println(io, join((r.STFIP, r.COFIP, r.ST, name, repr(bb[1][1]), repr(bb[1][2]), repr(bb[2][1]), repr(bb[2][2]), ""), ','))
    end
end
b = take!(io)
write(out, b)
println("wrote ", out, ": ", nrow(c), " counties, ", nerr, " calls that threw, ", length(b), " bytes, sha256 ",
        bytes2hex(sha256(b)))
