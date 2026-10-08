```@meta
CurrentModule = UTCGP
```

# Scalar Decisions and Motion

The locator libraries turn images into numbers: where the ball is, where the
paddle is, how big an object is. Those numbers still have to become a
*decision* — move up or down, which object to follow, where the ball will be
in five frames. With only `+ − × ÷`, `tanh` and `relu`, evolution has to
rebuild `abs`, `min` or "is a bigger than b" from scratch every time.

These two bundles give it those building blocks directly. Every operator takes
numbers and returns a `Float64`, with at most three inputs.

| Getter | Bundles |
|:--|:--|
| `get_extension_decision_nb()` | `bundle_number_decision`, `bundle_number_motion` |

## A worked example: playing Pong

Two consecutive frames. The ball moves up and to the right; the right paddle
must decide whether to go up or down. Every step below is a single MAGE
operator, so an evolved program can express the whole chain.

```@setup decision
using UTCGP
include(joinpath(dirname(pathof(UTCGP)), "..", "docs", "gallery_helpers.jl"))
O = UTCGP.number_objectFromImg
D = UTCGP.number_decision
assets = g_assets("decision")

function pong(ball; left = 40, right = 55)
    v = fill(0.1, 80, 120)
    for r in 2:6:76
        v[r:r+2, 60] .= 0.35                              # net (below threshold 0.5)
    end
    v[left-5:left+5, 6:7] .= 0.8                          # left paddle
    v[right-5:right+5, 113:114] .= 0.8                    # right paddle
    v[ball[1]:ball[1]+1, ball[2]:ball[2]+1] .= 1.0        # ball
    return v
end
previous_frame = g_intensity(pong((40, 50)))
frame = g_intensity(pong((32, 58)))
g_save(assets, "previous.png", g_up(g_canvas(previous_frame), 3))
```

```@example decision
ball_x0, ball_y0 = O.obj_x_smallest(previous_frame), O.obj_y_smallest(previous_frame)
ball_x, ball_y = O.obj_x_smallest(frame), O.obj_y_smallest(frame)
paddle_x, paddle_y = O.obj_x_rightmost(frame), O.obj_y_rightmost(frame)

vx = ball_x - ball_x0                        # speed, per frame
vy = ball_y - ball_y0
frames_left = (paddle_x - ball_x) / vx       # frames until the ball reaches the paddle

target_y = D.number_bounce(ball_y, vy, frames_left)   # where it will cross, after bouncing
action = D.number_toward(target_y, paddle_y, 0.03)    # -1 up, 0 stay, +1 down

(ball_y = round(ball_y, digits = 3), vy = round(vy, digits = 3),
 frames_left = round(frames_left, digits = 1), target_y = round(target_y, digits = 3),
 paddle_y = round(paddle_y, digits = 3), action = action)
```

```@setup decision
let canvas = g_up(g_canvas(frame), 3)
    for k in 0:0.1:frames_left
        x = ball_x + vx * k
        y = D.number_reflect01(ball_y + vy * k)
        g_dot!(canvas, 1 + y * 79 + 0.5, 1 + x * 119 + 0.5, 3)
    end
    g_cross!(canvas, ball_x0, ball_y0, 3; color = G_BLUE, lines = false)
    g_cross!(canvas, ball_x, ball_y, 3; lines = false)
    g_cross!(canvas, paddle_x, target_y, 3; color = G_GREEN)
    g_save(assets, "pong_plan.png", canvas)
end
```

| Previous frame | Current frame and plan |
|:--:|:--:|
| ![Previous frame](../assets/fns/decision/previous.png) | ![Plan](../assets/fns/decision/pong_plan.png) |

Blue is the ball in the previous frame, red the ball now, the green dots the
path `number_bounce` predicts (it reflects off the top wall), and the green
crosshair the point where the ball will reach the paddle's column. The paddle
is below that point, so `number_toward` returns `-1`: move up.

## Shaping one number

Each plot shows the output (vertical) against the first input (horizontal),
both from `-1.5` to `1.5`; grid lines every `0.5`, darker axes at `0`.

```@setup decision
plots = [
    ("abs", [(x -> D.number_abs(x), G_RED)]),
    ("sign", [(x -> D.number_sign(x), G_RED)]),
    ("clamp01", [(x -> D.number_clamp01(x), G_RED)]),
    ("clamp", [(x -> D.number_clamp(x, -0.5, 1.0), G_RED)]),
    ("step", [(x -> D.number_step(x), G_RED), (x -> D.number_step(x, 0.5), G_BLUE)]),
    ("deadzone", [(x -> D.number_deadzone(x, 0.5), G_RED)]),
    ("band", [(x -> D.number_band(x, -0.5, 0.5), G_RED)]),
    ("smoothstep", [(x -> D.number_smoothstep(x, -1.0, 1.0), G_RED)]),
    ("min_max", [(x -> D.number_min(x, 0.5), G_RED), (x -> D.number_max(x, 0.5), G_BLUE)]),
    ("mean", [(x -> D.number_mean(x, 1.0), G_RED)]),
    ("gt_lt", [(x -> D.number_gt(x, 0.5), G_RED), (x -> D.number_lt(x, 0.5) - 0.02, G_BLUE)]),
    ("closer", [(x -> D.number_closer(x, 1.0, 0.0), G_RED)]),
    ("toward", [(x -> D.number_toward(0.0, x), G_RED), (x -> D.number_toward(0.0, x, 0.5) + 0.03, G_BLUE)]),
    ("lerp", [(t -> D.number_lerp(-1.0, 1.0, t), G_RED)]),
]
for (name, curves) in plots
    g_save(assets, "plot_$(name).png", g_plot(curves))
end
g_save(assets, "plot_wrap01.png", g_plot([(x -> D.number_wrap01(x), G_RED)]; ylim = (-0.5, 1.5)))
g_save(assets, "plot_reflect01.png", g_plot([(x -> D.number_reflect01(x), G_RED)]; xlim = (-1.0, 3.0), ylim = (-0.5, 1.5)))
g_save(assets, "plot_bounce.png", g_plot([(t -> D.number_bounce(0.2, 0.7, t), G_RED), (t -> D.number_extrapolate(0.2, 0.7, t), G_BLUE)]; xlim = (0.0, 3.0), ylim = (-0.5, 2.5)))
g_save(assets, "plot_sin_cos.png", g_plot([(t -> D.number_sin(t), G_RED), (t -> D.number_cos(t), G_BLUE)]; xlim = (0.0, 1.5)))
```

| Operator | Call plotted | Plot | What it is for |
|:--|:--|:--:|:--|
| `number_abs` | `number_abs(a)` | ![abs](../assets/fns/decision/plot_abs.png) | distance regardless of direction |
| `number_sign` | `number_sign(a)` | ![sign](../assets/fns/decision/plot_sign.png) | direction only: `-1`, `0`, `1` |
| `number_clamp01` | `number_clamp01(a)` | ![clamp01](../assets/fns/decision/plot_clamp01.png) | keep a coordinate inside the image |
| `number_clamp` | `number_clamp(a, -0.5, 1.0)` | ![clamp](../assets/fns/decision/plot_clamp.png) | limit to any range (bounds in any order) |
| `number_step` | red `number_step(a)`, blue `number_step(a, 0.5)` | ![step](../assets/fns/decision/plot_step.png) | yes/no: is `a` at least `t`? |
| `number_deadzone` | `number_deadzone(a, 0.5)` | ![deadzone](../assets/fns/decision/plot_deadzone.png) | ignore small errors so a controller does not jitter |
| `number_band` | `number_band(a, -0.5, 0.5)` | ![band](../assets/fns/decision/plot_band.png) | yes/no: is `a` inside a range? |
| `number_smoothstep` | `number_smoothstep(a, -1, 1)` | ![smoothstep](../assets/fns/decision/plot_smoothstep.png) | a soft version of `step` |

## Comparing and choosing

Two-input operators, plotted with the second input fixed:

| Operator | Call plotted | Plot | What it is for |
|:--|:--|:--:|:--|
| `number_min`, `number_max` | red `number_min(a, 0.5)`, blue `number_max(a, 0.5)` | ![min max](../assets/fns/decision/plot_min_max.png) | the nearer / farther of two objects, a floor or ceiling |
| `number_mean` | `number_mean(a, 1.0)` | ![mean](../assets/fns/decision/plot_mean.png) | midpoint between two objects |
| `number_gt`, `number_lt` | red `number_gt(a, 0.5)`, blue `number_lt(a, 0.5)` | ![gt lt](../assets/fns/decision/plot_gt_lt.png) | comparisons as `1.0` / `0.0`, ready to multiply |
| `number_closer` | `number_closer(a, 1.0, 0.0)` | ![closer](../assets/fns/decision/plot_closer.png) | of two candidates, the one nearest a reference |
| `number_toward` | red `number_toward(0, a)`, blue with deadzone `0.5` | ![toward](../assets/fns/decision/plot_toward.png) | which way to move `a` to reach the target |
| `number_lerp` | `number_lerp(-1, 1, t)` | ![lerp](../assets/fns/decision/plot_lerp.png) | blend two values, e.g. aim between two objects |

Three-input choosers are easier to read as examples:

```@example decision
(
    median3 = D.number_median3(0.9, 0.1, 0.5),      # middle of three estimates
    argmax3_first = D.number_argmax3(0.9, 0.1, 0.5),   # 0.0: the first is largest
    argmax3_second = D.number_argmax3(0.1, 0.9, 0.5),  # 0.5: the second
    argmax3_third = D.number_argmax3(0.1, 0.2, 0.5),   # 1.0: the third
    closer = D.number_closer(0.1, 0.8, 0.6),           # 0.8 is closer to 0.6
)
```

## Motion and geometry

`bundle_number_motion` works on normalised coordinates and their differences.

| Operator | Call plotted | Plot | What it is for |
|:--|:--|:--:|:--|
| `number_wrap01` | `number_wrap01(a)` (vertical axis `-0.5` to `1.5`) | ![wrap](../assets/fns/decision/plot_wrap01.png) | playfields where leaving one side re-enters the other |
| `number_reflect01` | `number_reflect01(a)`, `a` from `-1` to `3` | ![reflect](../assets/fns/decision/plot_reflect01.png) | fold a position back between two walls |
| `number_bounce`, `number_extrapolate` | red `number_bounce(0.2, 0.7, t)`, blue `number_extrapolate(0.2, 0.7, t)`, `t` from `0` to `3` | ![bounce](../assets/fns/decision/plot_bounce.png) | where a moving object will be after `t` frames, with and without walls |
| `number_sin`, `number_cos` | red `number_sin(t)`, blue `number_cos(t)`, `t` in turns | ![sin cos](../assets/fns/decision/plot_sin_cos.png) | periodic patterns, components of a direction |

`number_dist` and `number_angle` turn an offset into a distance and a
direction (a fraction of a turn: `0` right, `0.25` down, `0.5` left, `0.75`
up):

```@example decision
dx = O.obj_dx_smallest_largest(g_binary(Float64.(reinterpret(frame.img)) .> 0.5))
dy = O.obj_dy_smallest_largest(g_binary(Float64.(reinterpret(frame.img)) .> 0.5))
(
    dist_3_4 = D.number_dist(0.3, 0.4),
    angle_right = D.number_angle(1.0, 0.0),
    angle_down = D.number_angle(0.0, 1.0),
    angle_up_left = D.number_angle(-1.0, -1.0),
    ball_to_paddle_distance = round(D.number_dist(dx, dy), digits = 3),
)
```

## Bundles

```@docs
UTCGP.number_decision
UTCGP.number_decision.bundle_number_decision
UTCGP.number_decision.bundle_number_motion
```
