# test_prt_pins.jl -- byte equality of `prt` against the committed fixture (PCV K4, plan principle 9).
# A call the course makes today keeps printing what it printed. Only a case named for a ruled item
# (CR2_, CR32_, N11_, N12_, S13_), or listed in PRT_PIN_MOVED (PR, K14), may differ from v0.2.8's output,
# and each fixture update is named in its commit. Regenerate with tools/v0_3_0/make_prt_pins.jl.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "prt_pin_helpers.jl"))

@testset "prt output is pinned byte for byte" begin
    fixture = prt_pin_read()
    cases = prt_pin_cases()
    @test length(fixture) == length(cases)
    for (name, arg, kw) in cases
        @testset "$name" begin
            @test haskey(fixture, name)
            haskey(fixture, name) || continue
            s, out = prt_pin_run(arg, kw)
            @test s == fixture[name][1]
            @test out == fixture[name][2]
        end
    end
end
