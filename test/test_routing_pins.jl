# test_routing_pins.jl -- value equality of the course's routing calls against the committed fixture
# (PCV K7a, plan principle 9). A call the course makes today keeps returning what it returned at v0.2.8
# (the fixture was written from the code at 97aeab2, unchanged from v0.2.8 in routetools.jl).
# Only a case listed in RPIN_MOVED may differ, and each fixture update is named in its commit.
# Regenerate with tools/v0_3_0/make_routing_pins.jl. No case touches the network.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "routing_pin_helpers.jl"))

@testset "routing calls are pinned value for value" begin
    fixture = rtpin_read()
    cases = rtpin_cases()
    @test length(fixture) == length(cases)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(fixture, name)
            haskey(fixture, name) || continue
            @test rtpin_run(thunk) == fixture[name]
        end
    end
end
