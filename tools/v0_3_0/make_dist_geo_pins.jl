# make_dist_geo_pins.jl -- write the value fixture of the course's distance and geocoding calls
# (PCV K5, principle 9).
#
#   julia +1.12.6 --project=<repo> tools/v0_3_0/make_dist_geo_pins.jl [--write [--id <ID>]]
#
# Runs every case of test/dist_geo_pin_cases.jl through the CURRENT code and compares with the
# committed fixture test/fixtures/dist_geo_pins.tsv. Without --write it only lists the cases whose
# value differs, which is the diff to name in a commit (each must carry a ruled ID: N1_, N5_, N7_,
# N8_, N19_, CR26_, S3_, S14_, S15_ in its name, or be listed in DGPIN_MOVED under the ID of the commit
# that moves it). With --write it rewrites the fixture (a first run creates it, new cases are added without
# an ID, and a case that is gone is dropped). A rewrite that changes an existing row needs `--id <ID>` (K14:
# GC), and every differing case must be listed in DGPIN_MOVED under that ID.
# Offline: no case reaches the network.

using Logjam
using DataFrames

include(joinpath(dirname(dirname(@__DIR__)), "test", "dist_geo_pin_helpers.jl"))

write_it = "--write" in ARGS
id = let k = findfirst(==("--id"), ARGS); k === nothing ? nothing : ARGS[k+1]; end
old = isfile(DGPIN_FIXTURE) ? dgpin_read() : Dict{String,String}()
results = [(name, dgpin_run(thunk)) for (name, thunk) in dgpin_cases()]

moved = String[]
added = String[]
for (name, v) in results
    if !haskey(old, name)
        push!(added, name)
    elseif old[name] != v
        push!(moved, name)
    end
end
gone = setdiff(keys(old), first.(results))
println(length(results), " cases; ", length(moved), " moved, ", length(added), " new, ", length(gone), " gone")
for n in moved
    println("  moved: ", n, "   (", get(DGPIN_MOVED, n, "NOT LISTED in DGPIN_MOVED"), ")")
end
for n in added
    println("  new:   ", n)
end
for n in sort(collect(gone))
    println("  gone:  ", n)
end
if write_it
    unlisted = [n for n in moved if !(id in split(get(DGPIN_MOVED, n, ""), "+"))]
    if !isempty(unlisted)
        println("REFUSED: not listed under --id ", id, ": ", join(unlisted, ", "))
        exit(1)
    end
    dgpin_write(results)
    println("fixture written: ", DGPIN_FIXTURE)
end
