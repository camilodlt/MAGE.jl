using UTCGP
using Documenter

DocMeta.setdocmeta!(UTCGP, :DocTestSetup, :(using UTCGP); recursive = true)

makedocs(;
    modules = [UTCGP],
    authors = "Camilo De La Torre <camilo.de-la-torre@ut-capitole.fr> and contributors",
    repo = "https://github.com/camilodlt/MAGE.jl/blob/{commit}{path}#{line}",
    sitename = "MAGE.jl",
    # Every docstring in UTCGP must appear somewhere in the manual. Do not lower
    # this to :none -- that is what let ~190 docstrings drift out of the docs.
    checkdocs = :exports,
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://camilodlt.github.io/MAGE.jl",
        repolink = "https://github.com/camilodlt/MAGE.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Examples" => ["sr_example.md"],
        "Manual" => [
            "Model Config" => "config.md",
            "Genome and Nodes" => "genome.md",
            "Libraries" => "libraries.md",
            "Programs" => "programs.md",
            "Mutations" => "mutations.md",
            "Crossover" => "crossover.md",
            "Fitters and Callbacks" => "fitters.md",
            "Endpoints and Tracking" => "endpoints.md",
            "Image Types" => "image_types.md",
        ],
        "Advanced" => [
            "Automatically Defined Functions" => "adf.md",
            "GraphMAGE" => "graphmage.md",
            "Generated Functions" => "generated_functions.md",
            "Search Networks" => "search_networks.md",
            "Package Extensions" => "extensions.md",
        ],
        "Function Libraries" => [
            "Bundle Catalogue" => "libraries/catalogue.md",
            "Bool Lib" => "libraries/bool.md",
            "Element Lib" => "libraries/element.md",
            "String Lib" => "libraries/string.md",
            "Number Lib" => "libraries/number.md",
            "Float Lib" => "libraries/float.md",
            "Integer Lib" => "libraries/integer.md",
            "Image Lib" => "libraries/image.md",
            "Vector Generic Lib" => "libraries/list_generic.md",
            "Vector Number Lib" => "libraries/list_number.md",
            "Vector Integer Lib" => "libraries/list_integer.md",
            "Vector String Lib" => "libraries/list_string.md",
            "Vector Tuple{T,T} Lib" => "libraries/list_tuple.md",
        ],
        "API Index" => "api.md",
    ],
)

deploydocs(; repo = "github.com/camilodlt/MAGE.jl.git", devbranch = "main")
