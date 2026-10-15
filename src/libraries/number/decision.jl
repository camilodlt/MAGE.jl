"""
Scalar decision and motion helpers: turn positions and offsets into choices.

# Bundles

- [`bundle_number_decision`](@ref)
- [`bundle_number_motion`](@ref)

The exhaustive, always-current list of operators in each bundle is on the
[Bundle Catalogue](@ref) page.

These are plain functions on numbers (no factory): every input is converted
to `Float64` and extra trailing inputs are ignored.

# Example: a Pong paddle controller

```julia
D = UTCGP.number_decision
ball_y, paddle_y = 0.30, 0.55
D.number_toward(ball_y, paddle_y)          # -1.0: move the paddle up
D.number_toward(0.54, paddle_y, 0.02)      #  0.0: within the dead zone, stay
D.number_bounce(0.9, 0.3, 1.0)             #  0.8: 0.9 + 0.3 = 1.2 bounces back off 1
```
"""
module number_decision

using ..UTCGP: FunctionBundle, append_method!

# Returned by the bundles when no method matches the inputs.
fallback(args...) = return 0.0

"""
    bundle_number_decision

Shape, compare and choose between numbers. Every operator returns a `Float64`.

- Shaping: `number_abs`, `number_sign`, `number_clamp01`, `number_clamp`,
  `number_step`, `number_deadzone`, `number_band`, `number_smoothstep`.
- Comparing and choosing: `number_min`, `number_max`, `number_mean`,
  `number_median3`, `number_gt`, `number_lt`, `number_closer`,
  `number_argmax3`.
- Acting: `number_toward` (`-1`, `0` or `1` to move `current` towards
  `target`) and `number_lerp`.
"""
bundle_number_decision = FunctionBundle(fallback)

"""
    bundle_number_motion

Geometry and kinematics on normalised coordinates: `number_dist`,
`number_angle`, `number_sin`, `number_cos`, `number_wrap01`,
`number_reflect01`, `number_extrapolate` and `number_bounce`, which predicts
where a point moving at constant speed ends up after bouncing between the
borders `0` and `1` (a Pong ball).
"""
bundle_number_motion = FunctionBundle(fallback)

"Every operator computes in `Float64`, whatever number type it is given."
@inline _float(x::Number) = Float64(x)

# ---------------------------------------------------------------------------
# Shaping
# ---------------------------------------------------------------------------

"""
    number_abs(a, args...)

`|a|`. Example: `number_abs(-0.3) == 0.3`.
"""
number_abs(a::Number, args...) = abs(_float(a))

"""
    number_sign(a, args...)

`-1.0`, `0.0` or `1.0`. Example: `number_sign(-0.3) == -1.0`.
"""
number_sign(a::Number, args...) = sign(_float(a))

"""
    number_clamp01(a, args...)

`a` clamped to `[0, 1]`.
"""
number_clamp01(a::Number, args...) = clamp(_float(a), 0.0, 1.0)

"""
    number_clamp(a, lo, hi, args...)

`a` clamped to `[min(lo, hi), max(lo, hi)]`.
Example: `number_clamp(0.9, 0.6, 0.2) == 0.6` (the bounds may come in any order).
"""
function number_clamp(a::Number, lo::Number, hi::Number, args...)
    lower, upper = minmax(_float(lo), _float(hi))      # sort the bounds
    return clamp(_float(a), lower, upper)
end

"""
    number_step(a, [t], args...)

`1.0` when `a >= t` (default `0`), else `0.0`.
Example: `number_step(0.4, 0.5) == 0.0`, `number_step(0.4) == 1.0`.
"""
number_step(a::Number, t::Number, args...) = _float(a) >= _float(t) ? 1.0 : 0.0   # with a threshold
number_step(a::Number, args...) = _float(a) >= 0.0 ? 1.0 : 0.0                     # threshold 0

"""
    number_deadzone(a, w, args...)

`0.0` while `|a| < |w|`, otherwise `a`. Stops a controller from jittering
around its target.

Example: `number_deadzone(0.03, 0.05) == 0.0`, `number_deadzone(-0.2, 0.05) == -0.2`.
"""
number_deadzone(a::Number, w::Number, args...) = abs(_float(a)) < abs(_float(w)) ? 0.0 : _float(a)

"""
    number_band(a, lo, hi, args...)

`1.0` when `a` lies between `lo` and `hi` (any order), else `0.0`.
Example: `number_band(0.5, 0.7, 0.3) == 1.0`.
"""
function number_band(a::Number, lo::Number, hi::Number, args...)
    lower, upper = minmax(_float(lo), _float(hi))
    return lower <= _float(a) <= upper ? 1.0 : 0.0
end

"""
    number_smoothstep(a, lo, hi, args...)

Smooth `0 → 1` transition as `a` goes from `lo` to `hi` (cubic Hermite);
`0.5` when `lo == hi`.

Example with `lo = 0`, `hi = 1`: `a = 0 → 0`, `0.25 → 0.156`, `0.5 → 0.5`,
`0.75 → 0.844`, `1 → 1`; flat at both ends, steepest in the middle.
"""
function number_smoothstep(a::Number, lo::Number, hi::Number, args...)
    lower, upper = _float(lo), _float(hi)
    lower == upper && return 0.5                         # no range: halfway
    t = clamp((_float(a) - lower) / (upper - lower), 0.0, 1.0)   # where a lies between the bounds, 0 to 1
    return t * t * (3.0 - 2.0t)                          # 3t² − 2t³
end

# ---------------------------------------------------------------------------
# Comparing and choosing
# ---------------------------------------------------------------------------

"""
    number_min(a, b, args...)

The smaller of `a` and `b`.
"""
number_min(a::Number, b::Number, args...) = min(_float(a), _float(b))

"""
    number_max(a, b, args...)

The larger of `a` and `b`.
"""
number_max(a::Number, b::Number, args...) = max(_float(a), _float(b))

"""
    number_mean(a, b, args...)

`(a + b) / 2`, e.g. the midpoint between two objects.
"""
number_mean(a::Number, b::Number, args...) = (_float(a) + _float(b)) / 2

"""
    number_median3(a, b, c, args...)

The middle value of three: a robust vote between three estimates.
"""
function number_median3(a::Number, b::Number, c::Number, args...)
    x, y, z = _float(a), _float(b), _float(c)
    return max(min(x, y), min(max(x, y), z))
end

"""
    number_gt(a, b, args...)

`1.0` when `a > b`, else `0.0`.
"""
number_gt(a::Number, b::Number, args...) = _float(a) > _float(b) ? 1.0 : 0.0

"""
    number_lt(a, b, args...)

`1.0` when `a < b`, else `0.0`.
"""
number_lt(a::Number, b::Number, args...) = _float(a) < _float(b) ? 1.0 : 0.0

"""
    number_closer(a, b, ref, args...)

Whichever of `a` and `b` is closer to `ref` (`a` on ties).
"""
number_closer(a::Number, b::Number, ref::Number, args...) =
    abs(_float(a) - _float(ref)) <= abs(_float(b) - _float(ref)) ? _float(a) : _float(b)

"""
    number_argmax3(a, b, c, args...)

Which of three values is largest, as `0.0`, `0.5` or `1.0` (first on ties).
Useful to pick one of three actions.
"""
function number_argmax3(a::Number, b::Number, c::Number, args...)
    x, y, z = _float(a), _float(b), _float(c)
    x >= y && x >= z && return 0.0
    y >= z && return 0.5
    return 1.0
end

# ---------------------------------------------------------------------------
# Acting
# ---------------------------------------------------------------------------

"""
    number_toward(target, current, [deadzone], args...)

Direction that moves `current` towards `target`: `1.0` when the target is
greater, `-1.0` when smaller, `0.0` when they are within `deadzone` (default
`0`). For example `number_toward(ball_y, paddle_y)` tells a paddle which way to
move.
"""
function number_toward(target::Number, current::Number, deadzone::Number, args...)
    d = _float(target) - _float(current)
    return abs(d) <= abs(_float(deadzone)) ? 0.0 : sign(d)
end
number_toward(target::Number, current::Number, args...) = sign(_float(target) - _float(current))

"""
    number_lerp(a, b, t, args...)

`a + t (b − a)`: `a` at `t = 0`, `b` at `t = 1`.
"""
number_lerp(a::Number, b::Number, t::Number, args...) = _float(a) + _float(t) * (_float(b) - _float(a))

# ---------------------------------------------------------------------------
# Motion and geometry
# ---------------------------------------------------------------------------

"""
    number_dist(dx, dy, args...)

Euclidean length `sqrt(dx² + dy²)`, e.g. the distance between two objects from
`obj_dx_*` and `obj_dy_*`.
"""
number_dist(dx::Number, dy::Number, args...) = hypot(_float(dx), _float(dy))

"""
    number_angle(dx, dy, args...)

Direction of `(dx, dy)` as a fraction of a turn in `[0, 1)`: `0` points to
`+x`, `0.25` to `+y` (down in image coordinates).
"""
function number_angle(dx::Number, dy::Number, args...)
    θ = atan(_float(dy), _float(dx))                     # angle in radians, in (−π, π]
    return mod(θ / 2π, 1.0)                              # → fraction of a turn in [0, 1)
end

"""
    number_sin(turns, args...)

`sin(2π · turns)`: the input is a fraction of a turn, as from `number_angle`.
"""
number_sin(a::Number, args...) = sinpi(2 * _float(a))

"""
    number_cos(turns, args...)

`cos(2π · turns)`.
"""
number_cos(a::Number, args...) = cospi(2 * _float(a))

"""
    number_wrap01(a, args...)

`a` wrapped into `[0, 1)`: leaving at `1` re-enters at `0` (wrap-around
playfields).
"""
number_wrap01(a::Number, args...) = isfinite(_float(a)) ? mod(_float(a), 1.0) : 0.0

"""
    number_reflect01(a, args...)

`a` folded into `[0, 1]` by bouncing off both borders: `1.2 → 0.8`,
`-0.3 → 0.3`, `2.5 → 0.5`.
"""
function number_reflect01(a::Number, args...)
    x = _float(a)
    isfinite(x) || return 0.0
    m = mod(x, 2.0)                  # the motion repeats every 2 (out to 1 and back to 0)
    return m <= 1.0 ? m : 2.0 - m    # second half of the period: coming back from 1
end

"""
    number_extrapolate(p, v, t, args...)

`p + v · t`: where a point at `p` moving at speed `v` will be after time `t`.
"""
number_extrapolate(p::Number, v::Number, t::Number, args...) = _float(p) + _float(v) * _float(t)

"""
    number_bounce(p, v, t, args...)

`number_reflect01(p + v · t)`: the position after time `t` of a point bouncing
between `0` and `1`. With `p` the ball's y, `v` its y-speed (e.g. the
difference of `obj_y_smallest` over two frames) and `t` the time to reach the
paddle, this predicts where to put the paddle.
"""
number_bounce(p::Number, v::Number, t::Number, args...) = number_reflect01(_float(p) + _float(v) * _float(t))

# ---------------------------------------------------------------------------
# Registration
#
# (function name, description shown in the Bundle Catalogue). Every function
# above is registered under its own name in one of the two bundles.
# ---------------------------------------------------------------------------

for (name, description) in (
        (:number_abs, "Absolute value."),
        (:number_sign, "Sign: -1, 0 or 1."),
        (:number_clamp01, "Clamp to [0, 1]."),
        (:number_clamp, "Clamp between two bounds."),
        (:number_step, "1 when a >= t (default 0), else 0."),
        (:number_deadzone, "0 inside |a| < |w|, a otherwise."),
        (:number_band, "1 when a lies between two bounds, else 0."),
        (:number_smoothstep, "Smooth 0 to 1 transition between two bounds."),
        (:number_min, "Smaller of two values."),
        (:number_max, "Larger of two values."),
        (:number_mean, "Midpoint of two values."),
        (:number_median3, "Middle of three values."),
        (:number_gt, "1 when a > b, else 0."),
        (:number_lt, "1 when a < b, else 0."),
        (:number_closer, "Whichever of a and b is closer to ref."),
        (:number_argmax3, "Index (0, 0.5, 1) of the largest of three values."),
        (:number_toward, "Direction (-1, 0, 1) moving current towards target, with optional deadzone."),
        (:number_lerp, "Linear interpolation between a and b."),
    )
    append_method!(bundle_number_decision, getfield(@__MODULE__, name), name; description = description)
end

for (name, description) in (
        (:number_dist, "Euclidean length of (dx, dy)."),
        (:number_angle, "Direction of (dx, dy) as a fraction of a turn."),
        (:number_sin, "Sine of a fraction of a turn."),
        (:number_cos, "Cosine of a fraction of a turn."),
        (:number_wrap01, "Wrap into [0, 1)."),
        (:number_reflect01, "Fold into [0, 1] by bouncing off both borders."),
        (:number_extrapolate, "Position p + v t."),
        (:number_bounce, "Position after time t of a point bouncing between 0 and 1."),
    )
    append_method!(bundle_number_motion, getfield(@__MODULE__, name), name; description = description)
end

end
