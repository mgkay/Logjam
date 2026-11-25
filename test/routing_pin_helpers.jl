# routing_pin_helpers.jl -- run a pinned routing case and read or write the fixture (PCV K7a).
# Kept apart from test_routing_pins.jl so tools/v0_3_0/make_routing_pins.jl can load it without
# running tests.

include(joinpath(@__DIR__, "routing_pin_cases.jl"))

const RTPIN_FIXTURE = joinpath(@__DIR__, "fixtures", "routing_pins.tsv")

function rtpin_run(thunk)
    try
        s = thunk()
        return s isa AbstractString ? String(s) : _rp(s)
    catch e
        return "ERR:" * string(nameof(typeof(e)))
    end
end

# the fixture: one line per case, `name TAB value`, the value escaped
function rtpin_read(path = RTPIN_FIXTURE)
    d = Dict{String,String}()
    for l in eachline(path)
        (isempty(l) || startswith(l, "#")) && continue
        name, v = split(l, '\t')
        d[String(name)] = unescape_string(v)
    end
    return d
end

function rtpin_write(results, path = RTPIN_FIXTURE)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, "# routing pins: name TAB value (escaped); see test/routing_pin_cases.jl\n")
        for (name, v) in results
            write(io, name, '\t', escape_string(v), '\n')
        end
    end
end
