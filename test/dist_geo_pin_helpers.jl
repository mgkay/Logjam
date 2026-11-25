# dist_geo_pin_helpers.jl -- run a pinned distance or geocoding case and read or write the fixture
# (PCV K5). Kept apart from test_dist_geo_pins.jl so tools/v0_3_0/make_dist_geo_pins.jl can load it
# without running tests.

include(joinpath(@__DIR__, "dist_geo_pin_cases.jl"))

const DGPIN_FIXTURE = joinpath(@__DIR__, "fixtures", "dist_geo_pins.tsv")

function dgpin_run(thunk)
    try
        s = thunk()
        return s isa AbstractString ? String(s) : _e(s)
    catch e
        return "ERR:" * string(nameof(typeof(e)))
    end
end

# the fixture: one line per case, `name TAB value`, the value escaped
function dgpin_read(path = DGPIN_FIXTURE)
    d = Dict{String,String}()
    for l in eachline(path)
        (isempty(l) || startswith(l, "#")) && continue
        name, v = split(l, '\t')
        d[String(name)] = unescape_string(v)
    end
    return d
end

function dgpin_write(results, path = DGPIN_FIXTURE)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, "# distance and geocoding pins: name TAB value (escaped); see test/dist_geo_pin_cases.jl\n")
        for (name, v) in results
            write(io, name, '\t', escape_string(v), '\n')
        end
    end
end
