# property_helpers.jl -- top-level helpers of test/test_properties.jl,
# moved here verbatim in PCV WP8 (Logjam v0.3.1): the tests that share them now sit in more than one file, one
# per source file, and each includes this file once, guarded by a name it defines, so that every helper is
# defined once.

const _RTOL = 1e-9
_close(a, b) = isapprox(a, b; rtol = _RTOL, atol = 1e-9)

# a function that prints (ala, ufl) is run with its output discarded
_mute_stdout(f) = redirect_stdout(f, devnull)

# cost of an open-site set y: fixed costs plus each EF served by its cheapest open site
_ufl_cost(k, C, y) = sum(k[y]) + sum(minimum(C[y, :], dims = 1))
