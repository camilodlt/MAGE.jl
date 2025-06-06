using UTCGP
using Documenter

DocMeta.setdocmeta!(UTCGP, :DocTestSetup, :(using UTCGP); recursive = true)

makedocs(;
    modules = [UTCGP],
    authors = "Camilo De La Torre <camilo.de-la-torre@ut-capitole.fr> and contributors",
    # repo = "https://github.com/camilodlt/UTCGP.jl/blob/{commit}{path}#{line}",
    sitename = "MAGE.jl",
    checkdocs = :none, #:exports,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://camilodlt.github.io/UTCGP.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Examples" => ["sr_example.md"],
        "Model Config" => "config.md",
        "Libraries" => "libraries.md",
        "Mutations" => "mutations.md",
        "Crossover" => "crossover.md",
        "Vector Generic Lib" => "libraries/list_generic.md",
        "Vector Number Lib" => "libraries/list_number.md",
        "Vector Integer Lib" => "libraries/list_integer.md",
        "Vector String Lib" => "libraries/list_string.md",
        "Vector Tuple{T,T}" => "libraries/list_tuple.md",
        "Element Lib" => "libraries/element.md",
        "String Lib" => "libraries/string.md",
        "Number Lib" => "libraries/number.md",
        "Integer Lib" => "libraries/integer.md",
    ],
)

# deploydocs(; repo = "github.com/camilodlt/UTCGP.jl.git", devbranch = "main")
