using Test

# Smoke test for H7 (dcf)
@testset "dcf smoke test" begin
    # Create a figure so current_figure() has something to display
    fig = Figure()
    Axis(fig[1,1])
    # dcf should not error when a figure exists
    dcf()
    @test true
end
