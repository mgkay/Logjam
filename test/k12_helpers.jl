# k12_helpers.jl -- top-level helpers of test/test_k12_pins.jl and test/test_k12_functions.jl,
# moved here verbatim in PCV WP8 (Logjam v0.3.1): the tests that share them now sit in more than one file, one
# per source file, and each includes this file once, guarded by a name it defines, so that every helper is
# defined once.

# case name => ruled ID that moves it (none)
const K12PIN_MOVED = Dict{String, String}()

_k12pin_moved(name) = haskey(K12PIN_MOVED, name) && (@info("K12 pin $name moved under $(K12PIN_MOVED[name])"); true)

# FNV-1a over the bytes of an array: a checksum that is the same on every Julia version (`hash` is not)
function _k12_fnv(bytes)
    h = 0xcbf29ce484222325
    for b in bytes
        h = (h ⊻ UInt64(b)) * 0x00000100000001b3
    end
    return h
end
_k12_fnv(x::AbstractArray{Float64}) = _k12_fnv(reinterpret(UInt8, vec(collect(x))))
_k12_fnv(x::AbstractArray{Int}) = _k12_fnv(reinterpret(UInt8, vec(collect(x))))

# a function the scratch module defined, called from here
_k12_call(m::Module, name::Symbol, args...) = Base.invokelatest(getfield(m, name), args...)

# One fresh process per call, the way a lecture runs, started with this session's own flags (as test_extensions_c5.jl).
function _k12_child(code)
    out = IOBuffer()
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -e $code`
    ok = success(pipeline(cmd; stdout = out, stderr = out))
    return ok, String(take!(out))
end
