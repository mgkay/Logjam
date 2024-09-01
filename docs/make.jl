using Logjam
using Documenter

DocMeta.setdocmeta!(Logjam, :DocTestSetup, :(using Logjam); recursive=true)

makedocs(;
    modules=[Logjam],
    authors="Michael G. Kay <kay@ncsu.edu>",
    sitename="Logjam.jl",
    format=Documenter.HTML(;
        canonical="https://mgkay.github.io/Logjam.jl",
        edit_link="main",   # Updated to "main" from "master"
        assets=String[],
    ),
    checkdocs = :none, # Disable the missing docstrings check
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mgkay/Logjam.jl",
    branch="gh-pages",  # Ensure gh-pages branch is set correctly
    devbranch="main",   # Updated to "main" from "master"
)
