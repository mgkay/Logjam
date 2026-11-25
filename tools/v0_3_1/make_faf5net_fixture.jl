# make_faf5net_fixture.jl -- write the small extract SC 1's T1.3 regenerates in CI (PCV N3): FAF5 as Logjam ships it,
# cut to a box around Raleigh (test/faf5net_fixture_helpers.jl), and the network the derivation makes of it.
#
#   julia +1.12.6 --project=<repo> tools/v0_3_1/make_faf5net_fixture.jl
#
# Writes test/fixtures/faf5net_raleigh/: faf5_nodes.csv and faf5_links.csv (the extract: the links with both ends in
# the box and the nodes they use, with the columns the derivation reads, every number written exactly), then reads them
# back and writes faf5net_nodes.csv, faf5net_links.csv and faf5net_nodemap.csv, derived from what was read, as the
# driver (tools/v0_3_1/make_faf5net.jl) writes the shipped files. test/test_faf5net.jl derives the extract again and
# compares the three files byte for byte, and cuts FAF5 again and compares the extract. Rerun only when the derivation
# changes on purpose; the commit that does says why.

include(joinpath(@__DIR__, "..", "..", "test", "faf5net_fixture_helpers.jl"))

function main()
    mkpath(FN_FIXTURE_DIR)
    Nx, Lx = fn_cut(faf5nodes(), faf5links())
    for (f, b) in zip(FN_EXTRACT, fn_extract_bytes(Nx, Lx))
        write(joinpath(FN_FIXTURE_DIR, f), b)
    end
    N, L = fn_read_extract()
    for (f, b) in zip(FN_DERIVED, fn_derived_bytes(N, L))
        write(joinpath(FN_FIXTURE_DIR, f), b)
    end
    println("extract: ", nrow(N), " nodes, ", nrow(L), " links")
    for f in (FN_EXTRACT..., FN_DERIVED...)
        println(lpad(filesize(joinpath(FN_FIXTURE_DIR, f)), 8), "  ", f)
    end
end

main()
