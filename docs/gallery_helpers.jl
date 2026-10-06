# Drawing helpers shared by the library gallery pages. Each page's `@setup`
# block includes this file, then renders its own images with these functions.

using UTCGP
using FileIO
using Images
using ImageCore: N0f8, N0f16

const G_RED = RGB{Float64}(0.92, 0.12, 0.12)
const G_BLUE = RGB{Float64}(0.12, 0.45, 1.0)
const G_GREEN = RGB{Float64}(0.1, 0.8, 0.3)
const G_GRID = RGB{Float64}(0.82, 0.84, 0.88)
const G_AXIS = RGB{Float64}(0.45, 0.48, 0.55)
const G_PALETTE = [
    RGB{Float64}(0, 0, 0), RGB{Float64}(0.9, 0.6, 0.0), RGB{Float64}(0.35, 0.7, 0.9),
    RGB{Float64}(0.0, 0.6, 0.5), RGB{Float64}(0.95, 0.9, 0.25), RGB{Float64}(0.0, 0.45, 0.7),
    RGB{Float64}(0.8, 0.4, 0.0), RGB{Float64}(0.8, 0.6, 0.7),
]

g_repo_root() = normpath(joinpath(dirname(pathof(UTCGP)), ".."))

"Asset directories (source and build) for a page, created on demand."
function g_assets(page::AbstractString)
    dirs = [joinpath(g_repo_root(), "docs", d, "assets", "fns", page) for d in ("src", "build")]
    foreach(mkpath, dirs)
    return dirs
end

g_save(dirs, name, canvas) = foreach(d -> save(joinpath(d, name), canvas), dirs)

g_intensity(values, ::Type{T} = N0f8) where {T} = SImageND(IntensityPixel{T}.(clamp.(Float64.(values), 0.0, 1.0)))
g_binary(values) = SImageND(BinaryPixel.(Bool.(values)))
g_segment(values) = SImageND(SegmentPixel.(Int.(values)))

g_gray(values) = RGB{Float64}.(Gray.(clamp.(values, 0.0, 1.0)))
g_canvas(img::SizedImage{S,<:IntensityPixel}) where {S} = g_gray(Float64.(reinterpret(img.img)))
g_canvas(img::SizedImage{S,<:BinaryPixel}) where {S} = g_gray(Float64.(reinterpret(img.img)))
g_canvas(img::SizedImage{S,<:SegmentPixel}) where {S} =
    [G_PALETTE[mod1(Int(p.pixel) + 1, length(G_PALETTE))] for p in img.img]
g_up(canvas, scale) = repeat(canvas, inner = (scale, scale))

g_blend(a, b, t) = RGB{Float64}(a.r + t * (b.r - a.r), a.g + t * (b.g - a.g), a.b + t * (b.b - a.b))

"Crosshair at normalised `(x, y)` on a canvas upscaled by `scale` (either may be `nothing`)."
function g_cross!(canvas, x, y, scale; color = G_RED, lines = true)
    H, W = size(canvas)
    h, w = H ÷ scale, W ÷ scale
    px(u, n) = round(Int, (u * (n - 1)) * scale + (scale + 1) / 2)
    c = x === nothing ? nothing : clamp(px(x, w), 1, W)
    r = y === nothing ? nothing : clamp(px(y, h), 1, H)
    if lines
        c === nothing || (canvas[:, c] .= g_blend.(canvas[:, c], color, 0.85))
        r === nothing || (canvas[r, :] .= g_blend.(canvas[r, :], color, 0.85))
    end
    if r !== nothing && c !== nothing
        for d in -5:5, e in -1:1
            canvas[clamp(r + d, 1, H), clamp(c + e, 1, W)] = color
            canvas[clamp(r + e, 1, H), clamp(c + d, 1, W)] = color
        end
    end
    return canvas
end

"Outline of the pixel box `r0:r1, c0:c1` (original coordinates) on an upscaled canvas."
function g_rect!(canvas, r0, r1, c0, c1, scale; color = G_GREEN)
    H, W = size(canvas)
    R0, R1 = clamp((r0 - 1) * scale + 1, 1, H), clamp(r1 * scale, 1, H)
    C0, C1 = clamp((c0 - 1) * scale + 1, 1, W), clamp(c1 * scale, 1, W)
    canvas[R0:R1, C0] .= color
    canvas[R0:R1, C1] .= color
    canvas[R0, C0:C1] .= color
    canvas[R1, C0:C1] .= color
    return canvas
end

"Dot of radius 2 at pixel position `(row, col)` (original coordinates)."
function g_dot!(canvas, row, col, scale; color = G_GREEN)
    H, W = size(canvas)
    r = round(Int, (row - 0.5) * scale)
    c = round(Int, (col - 0.5) * scale)
    for dr in -2:2, dc in -2:2
        canvas[clamp(r + dr, 1, H), clamp(c + dc, 1, W)] = color
    end
    return canvas
end

"""
    g_plot(curves; xlim, ylim, size) -> canvas

Line plot of `curves = [(f, color), ...]` on a light background with a grid at
every `0.5` and darker axes at `0`.
"""
function g_plot(curves; xlim = (-1.5, 1.5), ylim = (-1.5, 1.5), size = (150, 220))
    h, w = size
    canvas = fill(RGB{Float64}(1, 1, 1), h, w)
    col(x) = round(Int, 1 + (x - xlim[1]) / (xlim[2] - xlim[1]) * (w - 1))
    row(y) = round(Int, 1 + (ylim[2] - y) / (ylim[2] - ylim[1]) * (h - 1))
    for g in ceil(xlim[1] * 2)/2:0.5:xlim[2]
        canvas[:, clamp(col(g), 1, w)] .= g == 0 ? G_AXIS : G_GRID
    end
    for g in ceil(ylim[1] * 2)/2:0.5:ylim[2]
        canvas[clamp(row(g), 1, h), :] .= g == 0 ? G_AXIS : G_GRID
    end
    for (f, color) in curves
        previous = nothing
        for j in 1:w
            x = xlim[1] + (j - 1) / (w - 1) * (xlim[2] - xlim[1])
            y = Float64(f(x))
            r = clamp(row(y), 1, h)
            span = (previous !== nothing && abs(previous - r) <= h ÷ 3) ?
                   (min(previous, r):max(previous, r)) : (r:r)
            for rr in span, dr in -1:1, dc in -1:0
                canvas[clamp(rr + dr, 1, h), clamp(j + dc, 1, w)] = color
            end
            previous = r
        end
    end
    return canvas
end

g_call(fn, args...) = Base.invokelatest(fn, args...)
g_tag(v) = replace(string(v), "." => "", "-" => "m")

# ---------------------------------------------------------------------------
# Interactive volume viewer
# ---------------------------------------------------------------------------

using Base64: base64encode

const G_VIEWER_COUNT = Ref(0)

"PNG bytes of an RGB canvas, as a base64 data URI."
function g_png_uri(canvas)
    path = tempname() * ".png"
    save(path, canvas)
    uri = "data:image/png;base64," * base64encode(read(path))
    rm(path; force = true)
    return uri
end

"Display canvas of one volume slice (grey for intensity and binary, palette for segments)."
g_slice_canvas(slice::AbstractMatrix) = g_gray(Float64.(slice))     # pixels convert with Float64

"All slices along `axis`, upscaled and stacked vertically into one sprite strip."
function g_sprite(volume::AbstractArray{T,3}, axis::Int, scale::Int) where {T}
    n = size(volume, axis)
    slices = [g_up(g_slice_canvas(selectdim(volume, axis, k)), scale) for k in 1:n]
    return vcat(slices...), size(slices[1])
end

"""
    g_volume_viewer(volumes; scale = 4, title = "") -> HTML

An interactive viewer for one or more same-size volumes: one row per axis
(`z`, `y`, `x`), one column per volume, and one slider per row that moves all
volumes of that row together. `volumes` is a vector of `label => volume`
(`SImageND` or 3D array). Sprites are embedded as data URIs, or with
`assets = g_assets(page)` and `page` saved as asset files, and driven by a few
lines of inline JavaScript.
"""
function g_volume_viewer(volumes; scale::Int = 4, title::AbstractString = "", assets = nothing, page = "")
    G_VIEWER_COUNT[] += 1
    id = "volview$(G_VIEWER_COUNT[])"
    # With `assets` (from `g_assets(page)`), sprites are saved as files and
    # linked; the relative path depends on Documenter's pretty URLs (CI).
    prefix = get(ENV, "CI", "false") == "true" ? "../../assets/fns/$page/" : "../assets/fns/$page/"
    arrays = [(label, v isa SizedImage ? v.img : v) for (label, v) in volumes]
    dims = size(arrays[1][2])
    io = IOBuffer()
    print(io, """<div class="volume-viewer" id="$id" style="overflow-x:auto;margin:0.5em 0 1.5em 0;">""")
    isempty(title) || print(io, """<div style="font-weight:600;margin-bottom:0.3em;">$title</div>""")
    print(io, """<table style="border-collapse:collapse;border:none;"><tr><th style="border:none;"></th>""")
    for (label, _) in arrays
        print(io, """<th style="border:none;font-weight:500;font-size:0.85em;padding:2px 6px;">$label</th>""")
    end
    print(io, "</tr>")
    for (axis, name) in ((3, "z"), (1, "y"), (2, "x"))
        n = dims[axis]
        start = cld(n, 2)
        print(io, """<tr><td style="border:none;vertical-align:middle;padding-right:8px;white-space:nowrap;font-size:0.85em;">
            <b>$name</b> <span id="$(id)_$(name)_label">$start</span>/$n<br>
            <input type="range" min="1" max="$n" value="$start" id="$(id)_$(name)" style="width:110px;"
              oninput="(function(v){var root=document.getElementById('$id');
                root.querySelectorAll('.vv-$(name)').forEach(function(el){
                  el.style.backgroundPosition='0px -'+((v-1)*parseInt(el.dataset.h))+'px';});
                document.getElementById('$(id)_$(name)_label').textContent=v;})(this.value)">
            </td>""")
        for (column, (_, arr)) in enumerate(arrays)
            sprite, (h, w) = g_sprite(arr, axis, scale)
            uri = if assets === nothing
                g_png_uri(sprite)
            else
                file = "$(id)_$(name)_$(column).png"
                g_save(assets, file, sprite)
                prefix * file
            end
            print(io, """<td style="border:none;padding:2px;"><div class="vv-$(name)" data-h="$h"
                style="width:$(w)px;height:$(h)px;background-image:url($uri);background-repeat:no-repeat;
                background-position:0px -$((start - 1) * h)px;image-rendering:pixelated;"></div></td>""")
        end
        print(io, "</tr>")
    end
    print(io, "</table></div>")
    return HTML(String(take!(io)))
end
