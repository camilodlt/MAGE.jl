# Shared setup of the two 3D volume pages: the phantom, its mask and helpers.
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
assets = g_assets("volumes")
const N = 28
noise3(r, c, s, k) = 0.5 + 0.5 * sin(12.9898r + 78.233c + 37.719s + 4.1k)

"A CT-like phantom: body, organ with a cavity, a nodule and a wandering vessel."
function phantom(; nodule = true, organ = (8.0, 6.0, 7.0), vessel = true, cavity = true)
    v = zeros(N, N, N)
    for idx in CartesianIndices(v)
        r, c, s = Tuple(idx)
        y, x, z = r - 14.5, c - 14.5, s - 14.5
        if (y / 12)^2 + (x / 13)^2 + (z / 13)^2 > 1
            v[idx] = 0.02                                            # air
            continue
        end
        value = 0.25 + 0.06 * noise3(r, c, s, 1)                     # soft tissue
        in_organ = ((y + 2) / organ[1])^2 + ((x - 1) / organ[2])^2 + (z / organ[3])^2 <= 1
        in_organ && (value = 0.55 + 0.05 * noise3(r, c, s, 2))
        cavity && in_organ && (y + 2)^2 + (x + 2)^2 + (z - 1)^2 <= 4 && (value = 0.05)
        nodule && (y + 4)^2 + (x - 3)^2 + (z + 2)^2 <= 6.25 && (value = 0.92)
        if vessel
            cy = 7 + 2 * sin(z / 4)
            cx = -7 + 2 * cos(z / 5)
            (y - cy)^2 + (x - cx)^2 <= 2.2 && (value = 0.78)
        end
        v[idx] = value
    end
    return v
end

vol = g_intensity(phantom())
mask = g_binary(phantom() .>= 0.5)
I = typeof(vol)
B = typeof(mask)
I2 = typeof(g_intensity(zeros(N, N)))
B2 = typeof(g_binary(falses(N, N)))
iv(name) = bundle_image3DIntensity_volume_factory[name].fn(I)
bv(name) = bundle_image3DBinary_volume_factory[name].fn(B)
ib(name) = bundle_image3DIntensity_volume_basic_factory[name].fn(I)
bb(name) = bundle_image3DBinary_volume_basic_factory[name].fn(B)
to2(name) = bundle_image2DIntensity_fromVolume_factory[name].fn(I2)
to2b(name) = bundle_image2DBinary_fromVolume_factory[name].fn(B2)
call(f, args...) = Base.invokelatest(f, args...)
viewer(volumes; title = "") = g_volume_viewer(volumes; scale = 4, title = title, assets = assets, page = "volumes")
save2d(name, img; scale = 6) = g_save(assets, name, g_up(g_canvas(img), scale))
