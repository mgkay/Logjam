# common_helpers.jl -- two test-side helpers that two v0.3.0 test files each defined, with the same body, so that a full
# run redefined them and printed a method-redefinition warning (the v0.3.0 verifier's cosmetic warnings, MakePlan D2).
# Moved here verbatim in PCV WP8 (Logjam v0.3.1), with each file's note, so that each is defined once; every test file
# that uses one includes this file once, guarded by the name it needs.

# From test/test_datatools.jl (K2a) and test/test_osm.jl:
# a call that throws is a wrong answer here, not a test error: report `nothing`
_attempt(f) = try f() catch; nothing end

# From test/test_roadtools.jl:
# the NaN-separated line coordinates of a location sequence along shortest paths: what `Logjam.rte2lines`
# computed until v0.3.0, kept here as a test-side helper (the extension carries the same body privately)
# and test/test_integration.jl, whose note ends instead:
# computed until v0.3.0, kept here as a test-side helper (plotroute! traces its legs with `tracepath` itself)
function _test_rte2lines(route, P, dfN)
    x_out, y_out = Float64[], Float64[]
    for k in 1:length(route)-1
        path = tracepath(P[route[k]], route[k], route[k+1])
        append!(x_out, dfN.LON[path]); push!(x_out, NaN)
        append!(y_out, dfN.LAT[path]); push!(y_out, NaN)
    end
    return x_out, y_out
end
