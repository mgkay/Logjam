# make_routing_pins.jl -- write the value fixture of the course's routing calls
# (PCV K7a, principle 9).
#
#   julia +1.12.6 --check-bounds=yes --project=<repo> tools/v0_3_0/make_routing_pins.jl [--write [--id <ID>]]
#
# Run with --check-bounds=yes, as Pkg.test does. A route 2-opt that meets a tie (reversing all the
# deliveries of a depot route changes the cost by zero in exact arithmetic) keeps or drops the change
# by the rounding of the machine's order of summation, so five cases of the route 2-opt end at a
# different route without the flag (5.2's Ex. 3 and 5.3's depot routes, HW 5 Q1 and Q5).
#
# Runs every case of test/routing_pin_cases.jl through the CURRENT code and compares with the
# committed fixture test/fixtures/routing_pins.tsv. Without --write it only lists the cases whose
# value differs, which is the diff to name in a commit. With --write it rewrites the fixture (a first
# run, with no fixture yet, creates it). A rewrite that changes an existing row needs `--id <ID>`, the
# ruled ID of the commit, and every differing case must be listed in RPIN_MOVED under that ID; any
# other difference is refused, because a pinned case moves only in the commit named for the ruled ID.
# Offline: no case reaches the network.

using Logjam
using DataFrames

include(joinpath(dirname(dirname(@__DIR__)), "test", "routing_pin_helpers.jl"))

write_it = "--write" in ARGS
id = let k = findfirst(==("--id"), ARGS); k === nothing ? nothing : ARGS[k+1]; end
old = isfile(RTPIN_FIXTURE) ? rtpin_read() : Dict{String,String}()
results = [(name, rtpin_run(thunk)) for (name, thunk) in rtpin_cases()]

moved = String[]
added = String[]
for (name, v) in results
    if !haskey(old, name)
        push!(added, name)
    elseif old[name] != v
        push!(moved, name)
    end
end
println(length(results), " cases; ", length(moved), " moved, ", length(added), " new")
for n in moved
    println("  moved: ", n, "   (", get(RPIN_MOVED, n, "NOT LISTED in RPIN_MOVED"), ")")
end
for n in added
    println("  new:   ", n)
end
if write_it
    # a case may be listed under several IDs ("CR37_CR54+CR39"): it moves in the commit of each
    unlisted = [n for n in moved if !(id in split(get(RPIN_MOVED, n, ""), "+"))]
    if !isempty(unlisted)
        println("REFUSED: not listed under --id ", id, ": ", join(unlisted, ", "))
        exit(1)
    end
    rtpin_write(results)
    println("fixture written: ", RTPIN_FIXTURE)
end
