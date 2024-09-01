using Logjam
using Documenter

DocMeta.setdocmeta!(Logjam, :DocTestSetup, :(using Logjam); recursive=true)

makedocs(;
    modules=[Logjam],
    authors="Michael G. Kay <kay@ncsu.edu>",
    sitename="Logjam.jl",
    format=Documenter.HTML(;
        canonical="https://mgkay.github.io/Logjam.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mgkay/Logjam.jl",
    devbranch="master",
)
