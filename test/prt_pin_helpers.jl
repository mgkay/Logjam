# prt_pin_helpers.jl -- run a pinned `prt` case and read or write the fixture (PCV K4).
# Kept apart from test_prt_pins.jl so tools/v0_3_0/make_prt_pins.jl can load it without running tests.

include(joinpath(@__DIR__, "prt_pin_cases.jl"))

const PRT_PIN_FIXTURE = joinpath(@__DIR__, "fixtures", "prt_pins.tsv")

_pin_err(e) = "ERR:" * string(nameof(typeof(e)))

# the case's two outputs: the `str = true` string and what is printed to stdout (an error is "ERR:<type>")
function prt_pin_run(arg, kw::NamedTuple)
    s = try
        Logjam.prt(arg; kw..., str = true)
    catch e
        _pin_err(e)
    end
    path = tempname()
    out = try
        try
            open(path, "w") do io
                redirect_stdout(io) do
                    Logjam.prt(arg; kw...)
                end
            end
            read(path, String)
        finally
            rm(path; force = true)
        end
    catch e
        _pin_err(e)
    end
    return (s isa AbstractString ? String(s) : string(s), out)
end

# the fixture: one line per case, `name TAB str TAB stdout`, both strings escaped
function prt_pin_read(path = PRT_PIN_FIXTURE)
    d = Dict{String,Tuple{String,String}}()
    for l in eachline(path)
        (isempty(l) || startswith(l, "#")) && continue
        name, s, o = split(l, '\t')
        d[String(name)] = (unescape_string(s), unescape_string(o))
    end
    return d
end

function prt_pin_write(results, path = PRT_PIN_FIXTURE)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, "# prt pins: name TAB str=true output TAB stdout output (escaped); see test/prt_pin_cases.jl\n")
        for (name, (s, o)) in results
            write(io, name, '\t', escape_string(s), '\t', escape_string(o), '\n')
        end
    end
end
