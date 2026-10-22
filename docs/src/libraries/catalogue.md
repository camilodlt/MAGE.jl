```@meta
CurrentModule = MAGE
```

# Bundle Catalogue

Every [`FunctionBundle`](@ref) MAGE exports, with the operators it holds.

This page is generated from the package at documentation build time, so it can
never drift from the code. The prose description of what each group is *for*
lives in the bundle's own docstring — follow the bundle name to reach it — and
the pages under **Function Libraries** carry the worked examples.

!!! note "Reading the table"
    A bundle whose name ends in `_factory` holds functions of a type: calling an
    entry with a concrete type returns the method specialised for it. See
    [Libraries](@ref).

```@setup catalogue
using MAGE
using Markdown

# Render generated content as HTML so explicit bundle anchors survive.
# Cross-references inside generated Markdown are not resolved by Documenter;
# build those links from the shared inventory instead.
const PRETTY = get(ENV, "CI", "false") == "true"
page_url(page) = PRETTY ? "../$(page)/" : "$(page).html"

include(joinpath(dirname(pathof(MAGE)), "..", "docs", "bundle_inventory.jl"))

esc(s) = replace(String(s), "|" => "\\|", "[" => "\\[", "]" => "\\]")

io = IOBuffer()
listed = String[]
for (title, pages) in groups
    println(io, "## ", title, "\n")
    for (page, names_) in pages
        for name in names_
            sym = Symbol(name)
            isdefined(MAGE, sym) || continue
            bundle = getfield(MAGE, sym)
            bundle isa MAGE.FunctionBundle || continue
            push!(listed, name)
            url = string(page_url(page), "#", anchor_for(name))
            n = length(bundle)
            println(io, "`MAGEBUNDLEANCHOR", name, "`\n")
            println(io, "### [`", name, "`](", url, ")\n")
            println(io, n, n == 1 ? " operator." : " operators.", "\n")
            println(io, "| Fn | Description |")
            println(io, "|:---|:------------|")
            for w in bundle
                println(io, "| `", esc(w.name), "` | ", esc(w.description), " |")
            end
            println(io)
        end
    end
end

# Anything exported but not placed above: never silently drop it.
all_bundles = String[]
for n in names(MAGE)
    v = try getfield(MAGE, n) catch; continue end
    v isa MAGE.FunctionBundle && push!(all_bundles, String(n))
end
missing_ = sort(setdiff(all_bundles, listed))
if !isempty(missing_)
    println(io, "## Ungrouped\n")
    for name in missing_
        bundle = getfield(MAGE, Symbol(name))
        println(io, "`MAGEBUNDLEANCHOR", name, "`\n")
        println(io, "### `", name, "`\n")
        println(io, "| Fn | Description |")
        println(io, "|:---|:------------|")
        for w in bundle
            println(io, "| `", esc(w.name), "` | ", esc(w.description), " |")
        end
        println(io)
    end
end

catalogue_html = bundle_catalogue_html(String(take!(io)))
```

```@example catalogue
HTML(catalogue_html) # hide
```
