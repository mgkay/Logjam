# make_transport_pins.jl -- write the value fixture of the course's transport calls
# (PCV K6, principle 9).
#
#   julia +1.12.6 --project=<repo> tools/v0_3_0/make_transport_pins.jl [--write]
#
# Runs every case of test/transport_pin_cases.jl through the CURRENT code and compares with the
# committed fixture test/fixtures/transport_pins.tsv. Without --write it only lists the cases whose
# value differs, which is the diff to name in a commit (each must carry a ruled ID: N2_, N3_, N4_,
# CR14_, CR15_, D5_, N21_, N31_). With --write it rewrites the fixture (a first run creates it).
# Offline: no case reaches the network.

using Logjam
using DataFrames

include(joinpath(dirname(dirname(@__DIR__)), "test", "transport_pin_helpers.jl"))

write_it = "--write" in ARGS
old = isfile(TRPIN_FIXTURE) ? trpin_read() : Dict{String,String}()
results = [(name, trpin_run(thunk)) for (name, thunk) in trpin_cases()]

changed = String[]
for (name, v) in results
    haskey(old, name) && old[name] == v || push!(changed, name)
end
println(length(results), " cases; ", length(changed), " differ from the fixture")
for n in changed
    println("  ", n, haskey(old, n) ? "" : "   (new)")
end
if write_it
    trpin_write(results)
    println("fixture written: ", TRPIN_FIXTURE)
end
