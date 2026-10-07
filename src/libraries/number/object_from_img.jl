"""
Object locators and descriptors: image → scalar, computed on the 8-connected
foreground objects of a mask.

# Bundles

- [`bundle_number_objectLocateFromImg`](@ref)
- [`bundle_number_objectDescribeFromImg`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.
"""
module number_objectFromImg

using ..UTCGP: FunctionBundle, append_method!
using ..UTCGP: SImageND, IntensityPixel, BinaryPixel
using ..image2D_object_common:
    ObjectTable,
    IsSet,
    AtLeast,
    clamp_unit,
    object_table,
    unit_x,
    unit_y,
    area_fraction,
    width_fraction,
    height_fraction,
    elongation,
    circularity,
    extent,
    orientation,
    distance2_to,
    SELECTOR_FUNCTIONS,
    SELECTOR_DESCRIPTIONS,
    select_rank_area,
    select_nearest,
    select_like,
    select_by_mean

fallback(args...) = return 0.0

"""
    bundle_number_objectLocateFromImg

Where is the object with property X? Each operator labels the 8-connected
objects of a mask, selects one, and returns its centroid as a normalised
coordinate in `[0, 1]` (`x` = column, `y` = row, the `region_*` convention).
Empty masks return `0.5`.

Inputs: a binary mask, or an intensity map thresholded at `0.5` (or at an
explicit threshold, given as the last argument).

- `obj_x_<sel>` / `obj_y_<sel>`: fixed selectors — `largest`, `smallest`,
  `second_largest`, `most_elongated`, `most_circular`, `most_rectangular`,
  `widest`, `tallest`, `topmost`, `leftmost`, `most_central`,
  `most_isolated`, … and their opposites.
- `obj_*_brightest` / `obj_*_darkest`: `(mask, source)` selects by the mean of
  `source` over each object.
- `obj_*_rank_area`: `(mask, k)` picks the object at relative area rank `k`.
- `obj_*_like_<prop>`: `(mask, v)` picks the object whose property is closest
  to `v`, e.g. `obj_x_like_area(mask, 0.002)` finds a ball-sized object.
- `obj_*_nearest`: `(mask, s)` or `(mask, x, y)` picks the object closest to a
  point — feed it a previous position to track an object.
- `obj_dx_<a>_<b>` / `obj_dy_<a>_<b>`: signed offset between two selected
  objects, in `[-1, 1]`.
"""
bundle_number_objectLocateFromImg = FunctionBundle(fallback)

"""
    bundle_number_objectDescribeFromImg

What does the selected object look like? Same selection rules and inputs as
[`bundle_number_objectLocateFromImg`](@ref), but returning a descriptor of the
selected object instead of its position, so the value does not depend on
where the object is. Empty masks return `0.0`.

- `obj_<desc>_<sel>` and `obj_<desc>_nearest` with `<desc>` one of `area`
  (fraction of image pixels), `width` and `height` (bounding box as a fraction
  of the image side), `elongation` (`1 − sqrt(λmin / λmax)`), `circularity`
  (`1` for a disk), `extent` (area over bounding-box area) and `orientation`
  (principal-axis angle mapped to `[0, 1]`, `0.5` horizontal, `0` and `1`
  vertical, `0.5` for shapes without an axis).
- `obj_count`: number of objects.
- `obj_dist_nearest`: distance from a point to the nearest object centroid,
  normalised to `[0, 1]`.
"""
bundle_number_objectDescribeFromImg = FunctionBundle(fallback)

# (name, measure(table, id), wording). Properties are in [0, 1], so `obj_*_like_<prop>(mask, v)` can target them.
const _PROPERTIES = (
    (:area, area_fraction, "area fraction"),
    (:width, width_fraction, "bounding-box width fraction"),
    (:height, height_fraction, "bounding-box height fraction"),
    (:elongation, elongation, "elongation"),
    (:circularity, circularity, "moment circularity"),
    (:extent, extent, "extent"),
)
"Descriptors returned by `obj_<desc>_<sel>`: the properties plus orientation."
const _DESCRIPTORS = (_PROPERTIES..., (:orientation, orientation, "orientation"))
"(name, normalised centroid coordinate `(table, id) -> [0, 1]`, wording)."
const _COORDINATES = ((:x, unit_x, "column (x)"), (:y, unit_y, "row (y)"))
"Selector pairs `(a, b)` of the `obj_dx_<a>_<b>` / `obj_dy_<a>_<b>` offsets."
const _PAIRS = ((:smallest, :largest), (:smallest, :most_elongated), (:second_largest, :largest))

"`measure(t, id)` for the selected object, or `empty` when no object was selected (`id == 0`)."
@inline _result(measure::F, t::ObjectTable, id::Int, empty::Float64) where {F} =
    id == 0 ? empty : Float64(measure(t, id))

"Object table of a binary mask."
_mask_table(mask) = object_table(mask.img, IsSet())
"Object table of an intensity map thresholded at `threshold` (clamped to `[0, 1]`)."
_intensity_table(img, threshold) = object_table(img.img, AtLeast(clamp_unit(threshold)))

"Binary 2D image."
const _Mask = SImageND{S,T,2,C} where {S,T<:BinaryPixel,C}
"Intensity 2D image."
const _Intensity = SImageND{S,T,2,C} where {S,T<:IntensityPixel,C}
"Image whose values are averaged over objects (`obj_*_brightest`, `obj_*_darkest`)."
const _Source = SImageND{S,T,2,C} where {S,T<:Union{IntensityPixel,BinaryPixel},C}

"""
Define the three single-image methods of an operator whose value is
`compute(table)`: `(mask)`, `(img)` at threshold 0.5 and `(img, threshold)`.
"""
macro _single_input(name, compute)
    name, compute = esc(name), esc(compute)
    return quote
        $name(mask::_Mask, args...) = $compute(_mask_table(mask))
        $name(img::_Intensity, args...) = $compute(_intensity_table(img, 0.5))
        $name(img::_Intensity, threshold::Number, args...) =
            $compute(_intensity_table(img, threshold))
    end
end

"""
Methods with one scalar parameter `v` (default `0.5`): `(mask)`,
`(mask, v)`, `(img)`, `(img, v)` and `(img, v, threshold)`.
"""
macro _parametric_input(name, compute)
    name, compute = esc(name), esc(compute)
    return quote
        $name(mask::_Mask, args...) = $compute(_mask_table(mask), 0.5)
        $name(mask::_Mask, v::Number, args...) = $compute(_mask_table(mask), clamp_unit(v))
        $name(img::_Intensity, args...) = $compute(_intensity_table(img, 0.5), 0.5)
        $name(img::_Intensity, v::Number, args...) =
            $compute(_intensity_table(img, 0.5), clamp_unit(v))
        $name(img::_Intensity, v::Number, threshold::Number, args...) =
            $compute(_intensity_table(img, threshold), clamp_unit(v))
    end
end

"""
Methods taking a point: `(mask)` (image centre), `(mask, s)` with
`x = y = s`, `(mask, x, y)`, and the same for intensity at threshold 0.5.
"""
macro _point_input(name, compute)
    name, compute = esc(name), esc(compute)
    return quote
        $name(mask::_Mask, args...) = $compute(_mask_table(mask), 0.5, 0.5)
        $name(mask::_Mask, s::Number, args...) =
            (u = clamp_unit(s); $compute(_mask_table(mask), u, u))
        $name(mask::_Mask, x::Number, y::Number, args...) =
            $compute(_mask_table(mask), clamp_unit(x), clamp_unit(y))
        $name(img::_Intensity, args...) = $compute(_intensity_table(img, 0.5), 0.5, 0.5)
        $name(img::_Intensity, s::Number, args...) =
            (u = clamp_unit(s); $compute(_intensity_table(img, 0.5), u, u))
        $name(img::_Intensity, x::Number, y::Number, args...) =
            $compute(_intensity_table(img, 0.5), clamp_unit(x), clamp_unit(y))
    end
end

"Attach `doc` to the function `name` and register it in `bundle`."
function _register!(bundle, name::Symbol, description::String, doc::String)
    fn = getfield(@__MODULE__, name)
    @eval @doc $doc $name
    append_method!(bundle, fn, name; description = description)
end

"Docstring of an operator defined by `@_single_input`."
_single_doc(name, what) = """
    $name(mask, args...)
    $name(img, [threshold], args...)

$what Intensity inputs are thresholded at `threshold` (default `0.5`).
"""

# ---------------------------------------------------------------------------
# Locators
# ---------------------------------------------------------------------------

for (coord, coordinate_of, coord_doc) in _COORDINATES
    for (selector, select) in SELECTOR_FUNCTIONS
        name = Symbol(:obj_, coord, :_, selector)
        criterion = SELECTOR_DESCRIPTIONS[selector]
        @eval @_single_input $name (t -> _result($coordinate_of, t, $select(t), 0.5))
        _register!(bundle_number_objectLocateFromImg, name,
            "Normalised $coord_doc of the object with the $criterion.",
            _single_doc(name, "Normalised $coord_doc of the centroid of the object with the $criterion. Empty → `0.5`."))
    end

    for (selector, direction, criterion) in ((:brightest, 1.0, "greatest"), (:darkest, -1.0, "least"))
        name = Symbol(:obj_, coord, :_, selector)
        @eval begin
            $name(mask::_Mask, source::_Source, args...) =
                (t = _mask_table(mask); _result($coordinate_of, t, select_by_mean(t, source.img, $direction), 0.5))
            $name(saliency::_Intensity, source::_Source, args...) =
                (t = _intensity_table(saliency, 0.5); _result($coordinate_of, t, select_by_mean(t, source.img, $direction), 0.5))
            $name(saliency::_Intensity, source::_Source, threshold::Number, args...) =
                (t = _intensity_table(saliency, threshold); _result($coordinate_of, t, select_by_mean(t, source.img, $direction), 0.5))
        end
        _register!(bundle_number_objectLocateFromImg, name,
            "Normalised $coord_doc of the object with the $criterion mean source value.",
            """
                $name(mask, source, args...)
                $name(saliency, source, [threshold], args...)

            Normalised $coord_doc of the object whose mean `source` value is the
            $criterion. Empty → `0.5`.
            """)
    end

    name = Symbol(:obj_, coord, :_rank_area)
    @eval @_parametric_input $name ((t, k) -> _result($coordinate_of, t, select_rank_area(t, k), 0.5))
    _register!(bundle_number_objectLocateFromImg, name,
        "Normalised $coord_doc of the object at relative area rank k (0 smallest, 1 largest).",
        """
            $name(mask, [k], args...)
            $name(img, [k], [threshold], args...)

        Normalised $coord_doc of the object at relative area rank `k ∈ [0, 1]`
        (`0` smallest, `1` largest, default `0.5`). Empty → `0.5`.
        """)

    for (property, measure, property_doc) in _PROPERTIES
        name = Symbol(:obj_, coord, :_like_, property)
        @eval @_parametric_input $name ((t, v) -> _result($coordinate_of, t, select_like($measure, t, v), 0.5))
        _register!(bundle_number_objectLocateFromImg, name,
            "Normalised $coord_doc of the object whose $property_doc is closest to v.",
            """
                $name(mask, [v], args...)
                $name(img, [v], [threshold], args...)

            Normalised $coord_doc of the object whose $property_doc is closest to
            `v ∈ [0, 1]` (default `0.5`). Empty → `0.5`.
            """)
    end

    name = Symbol(:obj_, coord, :_nearest)
    @eval @_point_input $name ((t, x, y) -> _result($coordinate_of, t, select_nearest(t, x, y), 0.5))
    _register!(bundle_number_objectLocateFromImg, name,
        "Normalised $coord_doc of the object closest to a point.",
        """
            $name(mask_or_img, args...)
            $name(mask_or_img, s, args...)
            $name(mask_or_img, x, y, args...)

        Normalised $coord_doc of the object whose centroid is closest to
        `(x, y)` (`(s, s)`, or the image centre). Intensity inputs use threshold
        `0.5`. Chain it with its own output to track an object. Empty → `0.5`.
        """)
end

for (delta, coordinate_of, coord_doc) in ((:dx, unit_x, "column (x)"), (:dy, unit_y, "row (y)"))
    for (a, b) in _PAIRS
        name = Symbol(:obj_, delta, :_, a, :_, b)
        select_a = Dict(SELECTOR_FUNCTIONS)[a]
        select_b = Dict(SELECTOR_FUNCTIONS)[b]
        compute = t -> begin
            id_a = select_a(t)
            id_b = select_b(t)
            (id_a == 0 || id_b == 0) ? 0.0 : coordinate_of(t, id_a) - coordinate_of(t, id_b)
        end
        @eval @_single_input $name $compute
        _register!(bundle_number_objectLocateFromImg, name,
            "Signed $coord_doc offset from the $(SELECTOR_DESCRIPTIONS[b]) object to the $(SELECTOR_DESCRIPTIONS[a]) object.",
            _single_doc(name, "Signed normalised $coord_doc offset, in `[-1, 1]`, from the object with the $(SELECTOR_DESCRIPTIONS[b]) to the object with the $(SELECTOR_DESCRIPTIONS[a]). Empty → `0.0`."))
    end
end

# ---------------------------------------------------------------------------
# Descriptors
# ---------------------------------------------------------------------------

for (descriptor, measure, descriptor_doc) in _DESCRIPTORS
    for (selector, select) in SELECTOR_FUNCTIONS
        name = Symbol(:obj_, descriptor, :_, selector)
        criterion = SELECTOR_DESCRIPTIONS[selector]
        @eval @_single_input $name (t -> _result($measure, t, $select(t), 0.0))
        _register!(bundle_number_objectDescribeFromImg, name,
            "The $descriptor_doc of the object with the $criterion.",
            _single_doc(name, "The $descriptor_doc of the object with the $criterion. Empty → `0.0`."))
    end

    name = Symbol(:obj_, descriptor, :_nearest)
    @eval @_point_input $name ((t, x, y) -> _result($measure, t, select_nearest(t, x, y), 0.0))
    _register!(bundle_number_objectDescribeFromImg, name,
        "The $descriptor_doc of the object closest to a point.",
        """
            $name(mask_or_img, [s | x, y], args...)

        The $descriptor_doc of the object whose centroid is closest to `(x, y)`
        (`(s, s)`, or the image centre). Empty → `0.0`.
        """)
end

@_single_input obj_count (t -> Float64(t.n))
_register!(bundle_number_objectDescribeFromImg, :obj_count,
    "Number of 8-connected objects.",
    _single_doc(:obj_count, "Number of 8-connected foreground objects."))

"""
Distance from the normalised point `(x, y)` to the nearest object centroid,
over the diagonal of the unit square (`sqrt(2)`); `1` when there is no object.
"""
function _distance_to_nearest(t::ObjectTable, x::Float64, y::Float64)
    id = select_nearest(t, x, y)
    id == 0 && return 1.0
    return clamp(sqrt(distance2_to(t, id, x, y) / 2), 0.0, 1.0)
end
@_point_input obj_dist_nearest _distance_to_nearest
_register!(bundle_number_objectDescribeFromImg, :obj_dist_nearest,
    "Normalised distance from a point to the nearest object centroid.",
    """
        obj_dist_nearest(mask_or_img, [s | x, y], args...)

    Distance from `(x, y)` (`(s, s)`, or the image centre) to the nearest object
    centroid, divided by the image diagonal so it lies in `[0, 1]`. Empty →
    `1.0`.
    """)

end
