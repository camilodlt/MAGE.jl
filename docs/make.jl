using Documenter, DocumenterVitepress

using UTCGP

makedocs(;
    modules = [UTCGP],
    authors = "Camilo De La Torre",
    repo = "https://github.com/camilodlt/MAGE.jl",
    sitename = "UTCGP.jl",
    draft = false,
    source = "src",
    build = "build",
    format = DocumenterVitepress.MarkdownVitepress(
        repo = "https://github.com/camilodlt/MAGE.jl",
        devurl = "dev",
        deploy_url = "https://github.com/camilodlt/MAGE.jl",
    ),
    pages = [
        "Home" => "index.md"
        "Libraries" => ["libraries.md", "libraries/image2D/segmentation.md"]
    ],
    warnonly = true,
)

# deploydocs(; repo = "github.com/YourGithubUsername/MAGE.jl", push_preview = true)
