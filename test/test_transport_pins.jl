# test_transport_pins.jl -- value equality of the course's transport calls against the committed fixture
# (PCV K6, plan principle 9). A call the course makes today keeps returning what it returned at v0.2.8.
# Only a case named for a ruled item (N2_, N3_, N4_, CR14_, CR15_, D5_, N21_, N31_) may differ, and each
# fixture update is named in its commit. Regenerate with tools/v0_3_0/make_transport_pins.jl.
# No case touches the network.

using Test
using Logjam
using DataFrames

include(joinpath(@__DIR__, "transport_pin_helpers.jl"))

@testset "transport calls are pinned value for value" begin
    fixture = trpin_read()
    cases = trpin_cases()
    @test length(fixture) == length(cases)
    for (name, thunk) in cases
        @testset "$name" begin
            @test haskey(fixture, name)
            haskey(fixture, name) || continue
            @test trpin_run(thunk) == fixture[name]
        end
    end
end
