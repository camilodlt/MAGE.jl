using UTCGP
using Documenter

DocMeta.setdocmeta!(UTCGP, :DocTestSetup, :(using UTCGP); recursive=true)

makedocs(;
    modules=[UTCGP],
    authors="Camilo De La Torre <camilo.de-la-torre@ut-capitole.fr> and contributors",
    repo="https://github.com/camilo/UTCGP.jl/blob/{commit}{path}#{line}",
    sitename="UTCGP.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://camilo.github.io/UTCGP.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/camilo/UTCGP.jl",
    devbranch="main",
)
