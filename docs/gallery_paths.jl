# Rich HTML returned by @example bypasses Documenter's Markdown link rewriting.
# Paths must match docs/make.jl's prettyurls setting; index.md stays at the root.
g_asset_prefix(; library_page = true) = get(ENV, "CI", "false") == "true" ?
    (library_page ? "../../assets/fns" : "../assets/fns") :
    (library_page ? "../assets/fns" : "assets/fns")

g_raw_gallery(html::AbstractString) =
    HTML(replace(html, "../assets/fns/" => g_asset_prefix() * "/"))

# Different pages can use identically named sandbox modules. Allocate a fresh
# namespace when this helper is included; explicit asset_tag values stay stable
# across builds (the volume pages provide them).
using UUIDs: uuid4
const G_VIEWER_NAMESPACE = "viewer_" * string(uuid4())
g_viewer_tag() = G_VIEWER_NAMESPACE

"Add stable links to generated operator headings, which bypass Documenter's heading pass."
function g_operator_anchors(html::AbstractString)
    return replace(html, r"<h3><code>(region_\w+)</code></h3>" =>
        s"<h3 id=\"\1\"><code>\1</code></h3>")
end
