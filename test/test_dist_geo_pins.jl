# test_dist_geo_pins.jl -- value equality of the course's distance and geocoding calls against the
# committed fixture (PCV K5, plan principle 9). A call the course makes today keeps returning what it
# returned at v0.2.8. Only a case named for a ruled item (N1_, N5_, N7_, N8_, N19_, CR26_, S3_, S14_,
# S15_) may differ, and each fixture update is named in its commit. Regenerate with
# tools/v0_3_0/make_dist_geo_pins.jl. No case touches the network.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "dist_geo_pin_helpers.jl"))

@testset "distance and geocoding calls are pinned value for value" begin
    fixture = dgpin_read()
    cases = dgpin_cases()
    @test length(fixture) == length(cases)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(fixture, name)
            haskey(fixture, name) || continue
            @test dgpin_run(thunk) == fixture[name]
        end
    end
end
