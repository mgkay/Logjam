using Logjam
using Documenter

# The data artifacts are lazy: on a fresh machine the first call that reads one downloads it, and Pkg's
# "Downloading artifact" lines would print inside that docstring example and fail its doctest. Read both here first.
faf5nodes(); usrdnodemap()

DocMeta.setdocmeta!(Logjam, :DocTestSetup, :(using Logjam); recursive=true)

makedocs(;
    modules=[Logjam],
    authors="Michael G. Kay <kay@ncsu.edu>",
    sitename="Logjam",
    format=Documenter.HTML(;
        canonical="https://mgkay.github.io/Logjam",
        edit_link="main",   # Updated to "main" from "master"
# edit_link="https://github.com/mgkay/Logjam/blob/main/", # to fix source button in docs
        assets=String[],
        # the one page holds every docstring (about 290 KiB generated at v0.3.0, 401 KiB at v0.3.1); Documenter's defaults
        # (100 warn, 200 error) stop the build
        size_threshold_warn=500 * 2^10,
        size_threshold=600 * 2^10,
    ),
    checkdocs = :public, # every exported or `public` name needs an @docs entry (D10 makes lecture functions `public`)
    doctest = true,    # Enable doctest for jldoctest blocks
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mgkay/Logjam",
    branch="gh-pages",  # Ensure gh-pages branch is set correctly
    devbranch="main",   # Updated to "main" from "master"
    forcepush=true,
)
