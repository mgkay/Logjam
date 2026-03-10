# Integration tests for the README example workflow

using Test
using Logjam
using DataFrames
using Graphs

@testset "NC Cities Routing Integration" begin

    @testset "Full workflow - 10 cities, 5 shipments" begin
        # Step 1: Load and filter NC cities with population > 100k
        cities = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
        @test nrow(cities) == 10

        # Step 2: Define shipments (west-to-east flow)
        # Origins: Charlotte, Concord, Winston-Salem, High Point, Greensboro
        # Destinations: Raleigh, Durham, Cary, Fayetteville, Wilmington
        shipments = DataFrame(
            b = [2, 3, 10, 7, 6],
            e = [8, 4, 1, 5, 9]
        )
        @test nrow(shipments) == 5

        # Step 3: Load and crop FAF5 network
        nodes_full, links_full = faf5nodes(), faf5links()
        nodes_crop, links_crop = cropnetwork(nodes_full, links_full, cities.LON, cities.LAT)

        @test nrow(nodes_crop) > 0
        @test nrow(links_crop) > 0

        # Step 4: Add connectors for cities
        nodes_conn, links_conn = addconnectors(nodes_crop, links_crop, cities.LON, cities.LAT)

        # Cities should now be nodes 1-10
        @test nrow(nodes_conn) == nrow(nodes_crop) + nrow(cities)
        @test nodes_conn.IDX[1:10] == collect(1:10)

        # Step 5: Build graph and compute shortest paths (undirected for this workflow)
        g = links2graph(links_conn; dir_col=:__NO_DIR__)
        dist_mat, parents = shortestpaths(g, nrow(cities))

        @test size(dist_mat) == (10, 10)
        @test length(parents) == 10

        # Diagonal should be zeros
        for i in 1:10
            @test dist_mat[i, i] ≈ 0.0 atol=1e-10
        end

        # Distance matrix should be symmetric
        for i in 1:10, j in i+1:10
            @test dist_mat[i, j] ≈ dist_mat[j, i] atol=1e-6
        end

        # Step 6: Solve routing problem
        cost_fn(r) = rteTC(r, shipments, dist_mat)

        initial_routes = savings(cost_fn, shipments)
        @test !isempty(initial_routes)

        # All shipments should be covered
        all_shipments = Set{Int}()
        for rte in initial_routes
            union!(all_shipments, unique(rte))
        end
        @test all_shipments == Set(1:5)

        # With west-to-east flow, should get single combined route
        @test length(initial_routes) == 1

        # Step 7: Improve with 2-opt
        final_route, final_cost = twoopt(initial_routes[1], cost_fn)

        @test final_cost <= cost_fn(initial_routes[1])
        @test final_cost > 0
        @test length(unique(final_route)) == 5  # All 5 shipments

        # Step 8: Convert to location sequence
        loc_seq = rte2loc(final_route, shipments)

        # Should visit pickup and delivery for each shipment
        @test length(loc_seq) == 10  # 5 pickups + 5 deliveries

        # All 10 cities should be visited
        @test Set(loc_seq) == Set(1:10)

        # Step 9: Convert to plottable lines
        lx, ly = Logjam.rte2lines(loc_seq, parents, nodes_conn)

        @test length(lx) == length(ly)
        @test length(lx) > 10  # Should have many points (full paths)

        # Should have NaN separators between segments
        @test count(isnan, lx) == 9  # 9 segments for 10 locations
    end

    @testset "Route visits all cities" begin
        cities = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())

        shipments = DataFrame(
            b = [2, 3, 10, 7, 6],
            e = [8, 4, 1, 5, 9]
        )

        # Verify shipments cover all 10 cities
        origins = Set(shipments.b)
        destinations = Set(shipments.e)
        all_cities_in_shipments = union(origins, destinations)

        @test length(all_cities_in_shipments) == 10
        @test all_cities_in_shipments == Set(1:10)

        # No city is both origin and destination
        @test isempty(intersect(origins, destinations))
    end

end  # @testset "NC Cities Routing Integration"

@testset "README Example 4 — Visualization Integration" begin
    using GeoMakie

    # Load and filter NC cities (mirrors README Example 4)
    cities = filter(r -> (r.STFIP == st2fips(:NC)) && (r.POP > 100_000), usplace())
    shipments = DataFrame(b = [2, 3, 10, 7, 6], e = [8, 4, 1, 5, 9])

    # Build network
    nodes_base, links_base = cropnetwork(faf5nodes(), faf5links(), cities.LON, cities.LAT)
    nodes, links = addconnectors(nodes_base, links_base, cities.LON, cities.LAT)
    g = links2graph(links)
    dist_mat, parents = shortestpaths(g, nrow(cities))

    # Solve route
    cost_fn(r) = rteTC(r, shipments, dist_mat)
    initial_routes = savings(cost_fn, shipments)
    final_route, cost = twoopt(initial_routes[1], cost_fn)

    @testset "makemap with data coordinates" begin
        fig, ax, hborders, limits = makemap(cities.LON, cities.LAT)
        @test fig isa Figure
        @test ax isa GeoAxis
        @test limits isa Tuple
    end

    @testset "plotroads! returns Dict with tier keys" begin
        fig, ax = makemap(cities.LON, cities.LAT)
        handles = plotroads!(ax, nodes, links)
        @test handles isa Dict{Symbol, Any}
        @test haskey(handles, :fill_1)  # FAF5 has interstates
        @test length(handles) >= 2
    end

    @testset "plotroute! renders route" begin
        fig, ax = makemap(cities.LON, cities.LAT)
        plotroads!(ax, nodes, links)
        route_handles = plotroute!(ax, final_route, shipments, parents, nodes;
                                   color=:red, linewidth=2.5, show_markers=false)
        @test length(route_handles) == 1  # line only, no markers
    end

    @testset "full README Example 4 pipeline" begin
        fig, ax = makemap(cities.LON, cities.LAT)
        handles = plotroads!(ax, nodes, links)
        plotroute!(ax, final_route, shipments, parents, nodes;
                   color=:red, linewidth=2.5, show_markers=false)
        scatter!(ax, cities.LON, cities.LAT, color=:blue, markersize=10)
        text!(ax, cities.LON, cities.LAT, text=cities.NAME;
              aligntext(cities.LON, cities.LAT)...)
        ax.title = "Integration Test — README Example 4"

        # Verify figure has content
        @test length(ax.scene.plots) >= 4  # roads + route + scatter + text
        @test handles isa Dict{Symbol, Any}
    end
end
