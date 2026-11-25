# test_connector_search.jl -- addconnectors' exact local point location (PCV K8: C1, CR 62, CR 27).
# Each new point's connectors are the corners of the triangle of the whole network's Delaunay triangulation
# that holds it, found from the triangulation of its 16 nearest nodes (doubled as needed) and accepted only
# when the triangle's circumcircle holds no other node. The properties below compare it with the
# triangulation of the whole network, on seeded random nodes and on the crops the course makes.

using Test
using Logjam
using DataFrames
using Random
import DelaunayTriangulation as DT

# the connectors by the whole network's triangulation (v0.2.8's method)
function _whole_nodes(x, y, qs)
    tri = DT.triangulate(collect(zip(x, y)))
    return [sort!(filter(v -> v > 0, collect(DT.brute_force_search(tri, q)))) for q in qs]
end
# the connectors by the local point location
_local_nodes(x, y, qs) = (S = Logjam._ConnectorSearch(collect(Float64, x), collect(Float64, y));
                          [Logjam._connector_nodes(S, (Float64(q[1]), Float64(q[2]))) for q in qs])

@testset "addconnectors: exact local point location (CR 62, CR 27, C1)" begin
    @testset "equals the whole triangulation on seeded random nodes, inside the hull and out" begin
        for (seed, n, m) in ((1, 20, 60), (2, 200, 200), (3, 3000, 300), (4, 5000, 100))
            rng = MersenneTwister(seed)
            x, y = rand(rng, n), rand(rng, n)
            qs = [(1.2 * rand(rng) - 0.1, 1.2 * rand(rng) - 0.1) for _ in 1:m]   # some outside the hull
            @test _local_nodes(x, y, qs) == _whole_nodes(x, y, qs)
        end
    end

    @testset "equals the whole triangulation on the crops of Lectures 4.1 and 5.1" begin
        N, L = prune_reindex(faf5nodes(), faf5links())
        cities = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())     # 4.1 Code block 47
        counties = filter(r -> r.STFIP == st2fips(:NC), uscounty())                          # 5.1 Code block 35
        for df in (cities, counties)
            Nc, _ = cropnetwork(N, L, df.LON, df.LAT)
            qs = collect(zip(df.LON, df.LAT))
            @test _local_nodes(Nc.LON, Nc.LAT, qs) == _whole_nodes(Nc.LON, Nc.LAT, qs)
        end
    end

    @testset "a network of fewer than 16 nodes, and a point outside it (4.1 Code block 40)" begin
        x = [0.0, 1.0, 0.0, 1.0, 0.5]
        y = [0.0, 0.0, 1.0, 1.0, 0.45]
        qs = [(0.5, 0.2), (0.2, 0.5), (0.5, 0.8), (0.8, 0.5), (2.0, 0.5)]
        @test _local_nodes(x, y, qs) == _whole_nodes(x, y, qs)
        @test all(length.(_local_nodes(x, y, qs[1:4])) .== 3)                # a triangle's three corners
        @test length(_local_nodes(x, y, qs[5:5])[1]) == 2                    # the two nodes of the hull edge
    end

    @testset "a lattice, where circles are shared by four nodes: the triangle holds the point and its circle is empty" begin
        gx = [float(i) for i in 0:19 for j in 0:19]
        gy = [float(j) for i in 0:19 for j in 0:19]
        rng = MersenneTwister(5)
        qs = [(19 * rand(rng), 19 * rand(rng)) for _ in 1:80]
        kernel = DT.AdaptiveKernel()
        for (q, t) in zip(qs, _local_nodes(gx, gy, qs))
            @test length(t) == 3
            a, b, c = ((gx[i], gy[i]) for i in t)
            # the corners are counterclockwise or clockwise in index order, so test either way round
            sgn = DT.is_positively_oriented(DT.triangle_orientation(kernel, a, b, c)) ? 1 : -1
            for (u, v) in ((a, b), (b, c), (c, a))
                o = DT.triangle_orientation(kernel, u, v, q)
                @test sgn == 1 ? !DT.is_negatively_oriented(o) : !DT.is_positively_oriented(o)
            end
            p, r, s = sgn == 1 ? (a, b, c) : (a, c, b)
            @test !any(m -> m != a && m != b && m != c &&
                            DT.is_inside(DT.point_position_relative_to_circle(kernel, p, r, s, (gx[m], gy[m]))),
                       eachindex(gx))
        end
    end

    @testset "cocircular nodes: one answer on every run, and the caller's random stream is not advanced (build record K9 to K10)" begin
        # a 2 by 5 lattice (every unit square has four nodes on a circle) and a 6 by 6 one (past the 16 nearest nodes'
        # first pass); which diagonal a point's triangle takes used to depend on the global stream
        for (nx, ny, qx, qy) in ((5, 2, [0.3, 1.3, 2.3, 3.3], fill(0.6, 4)),
                                 (6, 6, [0.5, 1.5, 2.5, 3.5, 4.5], [0.5, 1.5, 2.5, 3.5, 4.5]))
            x = Float64[i for j in 0:ny-1 for i in 0:nx-1]
            y = Float64[j for j in 0:ny-1 for i in 0:nx-1]
            N = DataFrame(IDX = 1:length(x), LON = x, LAT = y)
            L = DataFrame(SRC = [1], DST = [2], DIST = [1.0])
            conn(Lc) = [(r.SRC, r.DST) for r in eachrow(Lc[isequal.(Lc.SOURCE, "CONNECTOR"), :])]
            answers = Set(conn(addconnectors(N, L, qx, qy)[2]) for _ in 1:40)
            @test length(answers) == 1
            # draw, call, draw equals draw, draw
            Random.seed!(7)
            a = rand(2)
            Random.seed!(7)
            b1 = rand()
            addconnectors(N, L, qx, qy; add_nf_nf = true)
            b2 = rand()
            @test a == [b1, b2]
        end
    end

    @testset "addconnectors takes a view, and gives the same links as the vectors" begin
        N = DataFrame(IDX = 1:5, LON = [0.0, 1.0, 0.0, 1.0, 0.5], LAT = [0.0, 0.0, 1.0, 1.0, 0.45])
        L = DataFrame(SRC = [1, 2, 3], DST = [2, 4, 4], DIST = [69.0, 69.0, 69.0])
        px, py = [0.5, 0.2, 0.7], [0.2, 0.5, 0.8]
        N1, L1 = addconnectors(N, L, px, py; add_nf_nf = false)
        N2, L2 = addconnectors(N, L, view(px, :), view(py, :); add_nf_nf = false)
        @test isequal(N1, N2) && isequal(L1, L2)
        bigx, bigy = [9.0; px; 9.0], [9.0; py; 9.0]
        N3, L3 = addconnectors(N, L, view(bigx, 2:4), view(bigy, 2:4); add_nf_nf = false)
        @test isequal(N1, N3) && isequal(L1, L3)
    end
end
