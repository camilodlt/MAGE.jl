using UTCGP
using Documenter

DocMeta.setdocmeta!(
    UTCGP,
    :DocTestSetup,
    :(using UTCGP; import UTCGP.list_generic_basic; import UTCGP.list_generic_subset);
    recursive = true,
)

makedocs(;
    modules = [UTCGP, UTCGP.list_generic_basic, UTCGP.list_generic_subset],
    authors = "Camilo De La Torre <camilo.de-la-torre@ut-capitole.fr> and contributors",
    repo = "https://github.com/camilo/UTCGP.jl/blob/{commit}{path}#{line}",
    sitename = "UTCGP.jl",
    checkdocs = :none, #:exports,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://camilo.github.io/UTCGP.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Model Config" => "config.md",
        "Libraries" => "libraries.md",
        "Mutations" => "mutations.md",
    ],
)

deploydocs(; repo = "github.com/camilo/UTCGP.jl", devbranch = "main")
