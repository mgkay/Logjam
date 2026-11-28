using Documenter

# Run the docstring `jldoctest` blocks and verify their `# output` against live behavior
# on every PR. The dedicated `docs` CI job only runs on release tags, so without this the
# examples could silently drift between releases. `manual=false` restricts the run to
# docstrings (no `docs/src` manual pages needed here). See CONTRIBUTING for the
# examples-must-show-output convention.
@testset "doctests" begin
    # The data artifacts are lazy: on a fresh machine the first call that reads one downloads it, and Pkg's
    # "Downloading artifact" lines would print inside that docstring example and fail it. Read both here first.
    faf5nodes(); usrdnodemap()
    DocMeta.setdocmeta!(Logjam, :DocTestSetup, :(using Logjam); recursive=true)
    doctest(Logjam; manual=false)
end
