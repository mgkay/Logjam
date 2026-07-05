# Packaging / exports / extension-isolation tests (C4, test spec P1/P2)

@testset "Packaging" begin
    # ── P1: new location/distance functions are exported ──
    exported = names(Logjam)
    @test :ala in exported
    @test :dgca in exported
    @test :wcentroid in exported

    # ── P2: extension isolation — no stray [deps] promotion; extensions resolve ──
    projfile = joinpath(pkgdir(Logjam), "Project.toml")
    @test isfile(projfile)

    # Dependency-free scan of Project.toml section membership.
    function _section_names(path, section)
        found = String[]
        cur = ""
        for line in eachline(path)
            s = strip(line)
            if startswith(s, "[") && endswith(s, "]")
                cur = s
            elseif cur == "[$section]" && occursin(" = ", s)
                push!(found, strip(split(s, " = ")[1]))
            end
        end
        return Set(found)
    end

    deps     = _section_names(projfile, "deps")
    weakdeps = _section_names(projfile, "weakdeps")
    @test !isempty(weakdeps)
    # A weakdep silently promoted to [deps] would break extension isolation.
    @test isempty(intersect(deps, weakdeps))

    # The map extension (CairoMakie + GeoMakie, loaded in runtests) must activate
    # on the resolved test environment — proves Pkg.test resolves the weakdeps.
    @test Logjam._geomakie_available[]
end
