using Test

# Smoke tests for H7 (dcf) and H8 (plotnetwork)
@testset "plotnetwork tests" begin
    @testset "basic 3-node network" begin
        C = [0 5 3; 5 0 2; 3 2 0]
        fig, xy = plotnetwork(C)
        @test fig isa Figure
        @test size(xy) == (3, 2)
    end

    @testset "asymmetric matrix" begin
        C = [0 4 0; 0 0 6; 7 0 0]
        fig, xy = plotnetwork(C)
        @test fig isa Figure
        @test size(xy) == (3, 2)
    end

    @testset "custom xy layout" begin
        C = [0 1; 1 0]
        xy_in = [0.0 0.0; 1.0 1.0]
        fig, xy_out = plotnetwork(C; xy=xy_in)
        @test xy_out == xy_in
    end

    @testset "no weights" begin
        C = [0 1; 1 0]
        fig, xy = plotnetwork(C; weights=false)
        @test fig isa Figure
    end

    @testset "custom labels" begin
        C = [0 1 0; 1 0 1; 0 1 0]
        fig, xy = plotnetwork(C; labels=["A", "B", "C"])
        @test fig isa Figure
    end

    @testset "empty matrix" begin
        C = Matrix{Float64}(undef, 0, 0)
        fig, xy = plotnetwork(C)
        @test fig isa Figure
        @test size(xy) == (0, 2)
    end

    @testset "single node" begin
        C = reshape([0], 1, 1)
        fig, xy = plotnetwork(C)
        @test fig isa Figure
        @test size(xy) == (1, 2)
    end
end

@testset "dcf smoke test" begin
    # Create a figure so current_figure() has something to display
    C = [0 1; 1 0]
    fig, _ = plotnetwork(C)
    # dcf should not error when a figure exists
    dcf()
    @test true
end
