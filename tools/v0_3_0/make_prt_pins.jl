# make_prt_pins.jl -- write the byte-equality fixture of `prt` outputs (PCV K4, principle 9).
#
#   julia +1.12.6 --project=<repo> tools/v0_3_0/make_prt_pins.jl [--write [--id <ID>]]
#
# Runs every case of test/prt_pin_cases.jl through the CURRENT `prt` and compares with the committed
# fixture test/fixtures/prt_pins.tsv. Without --write it only lists the cases whose output differs, which
# is the diff to name in a commit (each must carry a ruled ID: CR2_, CR32_, N11_, N12_, S13_ in its name, or
# be listed in PRT_PIN_MOVED under the ID of the commit that moves it). With --write it rewrites the fixture
# (a first run creates it, and new cases are added without an ID). A rewrite that changes an existing row
# needs `--id <ID>` (K14: PR), and every differing case must be listed in PRT_PIN_MOVED under that ID.

using Logjam
using DataFrames

include(joinpath(dirname(dirname(@__DIR__)), "test", "prt_pin_helpers.jl"))

write_it = "--write" in ARGS
id = let k = findfirst(==("--id"), ARGS); k === nothing ? nothing : ARGS[k+1]; end
old = isfile(PRT_PIN_FIXTURE) ? prt_pin_read() : Dict{String,Tuple{String,String}}()
results = [(name, prt_pin_run(arg, kw)) for (name, arg, kw) in prt_pin_cases()]

moved = String[]
added = String[]
for (name, r) in results
    if !haskey(old, name)
        push!(added, name)
    elseif old[name] != r
        push!(moved, name)
    end
end
println(length(results), " cases; ", length(moved), " differ from the fixture, ", length(added), " new")
for n in moved
    println("  moved: ", n, "   (", get(PRT_PIN_MOVED, n, "NOT LISTED in PRT_PIN_MOVED"), ")")
end
for n in added
    println("  new:   ", n)
end
if write_it
    unlisted = [n for n in moved if !(id in split(get(PRT_PIN_MOVED, n, ""), "+"))]
    if !isempty(unlisted)
        println("REFUSED: not listed under --id ", id, ": ", join(unlisted, ", "))
        exit(1)
    end
    prt_pin_write(results)
    println("fixture written: ", PRT_PIN_FIXTURE)
end
