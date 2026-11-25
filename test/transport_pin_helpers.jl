# transport_pin_helpers.jl -- run a pinned transport case and read or write the fixture (PCV K6).
# Kept apart from test_transport_pins.jl so tools/v0_3_0/make_transport_pins.jl can load it without
# running tests.

include(joinpath(@__DIR__, "transport_pin_cases.jl"))

const TRPIN_FIXTURE = joinpath(@__DIR__, "fixtures", "transport_pins.tsv")

function trpin_run(thunk)
    try
        s = thunk()
        return s isa AbstractString ? String(s) : _te(s)
    catch e
        return "ERR:" * string(nameof(typeof(e)))
    end
end

# the fixture: one line per case, `name TAB value`, the value escaped
function trpin_read(path = TRPIN_FIXTURE)
    d = Dict{String,String}()
    for l in eachline(path)
        (isempty(l) || startswith(l, "#")) && continue
        name, v = split(l, '\t')
        d[String(name)] = unescape_string(v)
    end
    return d
end

function trpin_write(results, path = TRPIN_FIXTURE)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, "# transport pins: name TAB value (escaped); see test/transport_pin_cases.jl\n")
        for (name, v) in results
            write(io, name, '\t', escape_string(v), '\n')
        end
    end
end
