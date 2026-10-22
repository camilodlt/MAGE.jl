# Streaming image mean benchmark

Julia 1.13.2; CPU: `tigerlake`; default threads: 2.

Julia optimization level: 2.

Before = the former general-summary algorithm, retained in this script.
Recorded on 2026-10-22 with default optimization (`-O2`), two default threads, one interactive thread and one OpenBLAS thread. Other validation jobs were running concurrently.

Reproduce with [streaming_image_mean_benchmark.jl](streaming_image_mean_benchmark.jl) in an environment containing this checkout and BenchmarkTools. Every timed result is consumed by a reference to prevent dead-code elimination. Each row also asserts bit-for-bit equality between the old algorithm and the streaming operator.

Times are medians of 11 warmed calls, without coverage or forced bounds checks.
Fresh-task bytes exclude task creation and compilation; each task starts without scratch buffers.
Warmed bytes reuse any existing scratch buffers. Inputs are created before measurement.
These observations depend on hardware and load; they are not timing guarantees.

| Storage | Shape | Selection | Before µs | After µs | Speedup | Fresh bytes before / after | Warm bytes before / after |
|:--|:--|:--|--:|--:|--:|--:|--:|
| N0f8 | 224×224 | whole | 59.82 | 57.51 | 1.04× | 3048 / 0 | 0 / 0 |
| N0f8 | 224×224 | inside | 38.28 | 56.48 | 0.68× | 3048 / 0 | 0 / 0 |
| N0f8 | 224×224 | outside | 39.68 | 28.77 | 1.38× | 3048 / 0 | 0 / 0 |
| N0f8 | 224×224 | difference | 74.6 | 61.89 | 1.21× | 3048 / 0 | 0 / 0 |
| N0f8 | 224×224 | empty ROI | 14.49 | 11.94 | 1.21× | 3048 / 0 | 0 / 0 |
| N0f16 | 224×224 | whole | 251.45 | 61.0 | 4.12× | 103440 / 0 | 0 / 0 |
| N0f16 | 224×224 | inside | 133.69 | 29.05 | 4.6× | 103440 / 0 | 0 / 0 |
| N0f16 | 224×224 | outside | 134.39 | 30.85 | 4.36× | 103440 / 0 | 0 / 0 |
| N0f16 | 224×224 | difference | 260.04 | 45.09 | 5.77× | 103440 / 0 | 0 / 0 |
| N0f16 | 224×224 | empty ROI | 13.4 | 12.91 | 1.04× | 103440 / 0 | 0 / 0 |
| Float32 | 224×224 | whole | 196.11 | 55.91 | 3.51× | 404496 / 0 | 0 / 0 |
| Float32 | 224×224 | inside | 106.95 | 32.0 | 3.34× | 404496 / 0 | 0 / 0 |
| Float32 | 224×224 | outside | 104.68 | 33.23 | 3.15× | 404496 / 0 | 0 / 0 |
| Float32 | 224×224 | difference | 214.11 | 39.32 | 5.44× | 404496 / 0 | 0 / 0 |
| Float32 | 224×224 | empty ROI | 14.66 | 15.17 | 0.97× | 404496 / 0 | 0 / 0 |
| Float64 | 224×224 | whole | 162.29 | 55.3 | 2.93× | 404496 / 0 | 0 / 0 |
| Float64 | 224×224 | inside | 89.29 | 29.22 | 3.06× | 404496 / 0 | 0 / 0 |
| Float64 | 224×224 | outside | 86.62 | 37.17 | 2.33× | 404496 / 0 | 0 / 0 |
| Float64 | 224×224 | difference | 197.12 | 37.33 | 5.28× | 404496 / 0 | 0 / 0 |
| Float64 | 224×224 | empty ROI | 14.98 | 14.76 | 1.02× | 404496 / 0 | 0 / 0 |
| N0f8 | 224×224×3 | whole | 179.62 | 177.55 | 1.01× | 3048 / 0 | 0 / 0 |
| N0f8 | 224×224×3 | inside | 438.64 | 397.59 | 1.1× | 3048 / 0 | 0 / 0 |
| N0f8 | 224×224×3 | outside | 397.36 | 708.63 | 0.56× | 3048 / 0 | 0 / 0 |
| N0f8 | 224×224×3 | difference | 920.92 | 444.15 | 2.07× | 3048 / 0 | 0 / 0 |
| N0f8 | 224×224×3 | empty ROI | 690.62 | 633.09 | 1.09× | 3048 / 0 | 0 / 0 |
| N0f16 | 224×224×3 | whole | 740.13 | 184.2 | 4.02× | 304144 / 0 | 0 / 0 |
| N0f16 | 224×224×3 | inside | 785.94 | 399.46 | 1.97× | 304144 / 0 | 0 / 0 |
| N0f16 | 224×224×3 | outside | 787.33 | 460.18 | 1.71× | 304144 / 0 | 0 / 0 |
| N0f16 | 224×224×3 | difference | 1322.6 | 421.65 | 3.14× | 304144 / 0 | 0 / 0 |
| N0f16 | 224×224×3 | empty ROI | 355.47 | 331.57 | 1.07× | 304144 / 0 | 0 / 0 |
| Float32 | 224×224×3 | whole | 621.34 | 182.57 | 3.4× | 1211336 / 0 | 0 / 0 |
| Float32 | 224×224×3 | inside | 799.37 | 410.89 | 1.95× | 1207312 / 0 | 0 / 0 |
| Float32 | 224×224×3 | outside | 733.54 | 416.33 | 1.76× | 1207312 / 0 | 0 / 0 |
| Float32 | 224×224×3 | difference | 1449.76 | 390.92 | 3.71× | 1207312 / 0 | 0 / 0 |
| Float32 | 224×224×3 | empty ROI | 364.48 | 337.06 | 1.08× | 1207312 / 0 | 0 / 0 |
| Float64 | 224×224×3 | whole | 517.0 | 178.52 | 2.9× | 1207312 / 0 | 0 / 0 |
| Float64 | 224×224×3 | inside | 567.96 | 377.64 | 1.5× | 1207312 / 0 | 0 / 0 |
| Float64 | 224×224×3 | outside | 580.8 | 381.82 | 1.52× | 1207312 / 0 | 0 / 0 |
| Float64 | 224×224×3 | difference | 1149.86 | 406.5 | 2.83× | 1207312 / 0 | 0 / 0 |
| Float64 | 224×224×3 | empty ROI | 342.89 | 327.31 | 1.05× | 1207312 / 0 | 0 / 0 |
| N0f8 | 128×128×128 | whole | 2482.78 | 2516.51 | 0.99× | 3048 / 0 | 0 / 0 |
| N0f8 | 128×128×128 | inside | 5832.66 | 5528.91 | 1.05× | 3048 / 0 | 0 / 0 |
| N0f8 | 128×128×128 | outside | 5905.64 | 5681.94 | 1.04× | 3048 / 0 | 0 / 0 |
| N0f8 | 128×128×128 | difference | 11874.04 | 6075.5 | 1.95× | 3048 / 0 | 0 / 0 |
| N0f8 | 128×128×128 | empty ROI | 4848.85 | 5297.29 | 0.92× | 3048 / 0 | 0 / 0 |
| N0f16 | 128×128×128 | whole | 13495.2 | 2891.46 | 4.67× | 4201416 / 0 | 0 / 0 |
| N0f16 | 128×128×128 | inside | 12448.5 | 6613.16 | 1.88× | 4197392 / 0 | 0 / 0 |
| N0f16 | 128×128×128 | outside | 11941.58 | 6279.9 | 1.9× | 4197392 / 0 | 0 / 0 |
| N0f16 | 128×128×128 | difference | 21753.7 | 6733.9 | 3.23× | 4197392 / 0 | 0 / 0 |
| N0f16 | 128×128×128 | empty ROI | 5316.7 | 4868.28 | 1.09× | 4197392 / 0 | 0 / 0 |
| Float32 | 128×128×128 | whole | 9532.68 | 2446.77 | 3.9× | 16784328 / 0 | 0 / 0 |
| Float32 | 128×128×128 | inside | 11439.11 | 6664.76 | 1.72× | 16780304 / 0 | 0 / 0 |
| Float32 | 128×128×128 | outside | 11033.55 | 6305.55 | 1.75× | 16780304 / 0 | 0 / 0 |
| Float32 | 128×128×128 | difference | 21683.13 | 6663.81 | 3.25× | 16780304 / 0 | 0 / 0 |
| Float32 | 128×128×128 | empty ROI | 5146.96 | 5046.59 | 1.02× | 16780304 / 0 | 0 / 0 |
| Float64 | 128×128×128 | whole | 8804.51 | 2818.88 | 3.12× | 16780304 / 0 | 0 / 0 |
| Float64 | 128×128×128 | inside | 9306.09 | 6068.68 | 1.53× | 16780304 / 0 | 0 / 0 |
| Float64 | 128×128×128 | outside | 9429.13 | 6313.9 | 1.49× | 16780304 / 0 | 0 / 0 |
| Float64 | 128×128×128 | difference | 18993.7 | 6675.83 | 2.85× | 16780304 / 0 | 0 / 0 |
| Float64 | 128×128×128 | empty ROI | 4815.53 | 5074.33 | 0.95× | 16780304 / 0 | 0 / 0 |

Empty-ROI timings remain dominated by scanning the mask and do not consistently improve under load; the streaming path still removes the sample-buffer allocation in those cases.

## N0f8 ROI follow-up

The broad run above contained an apparent N0f8 inside-ROI slowdown. A focused
follow-up used five rounds of 200 samples, alternating which implementation
ran first. It covered checkerboard, random and half-plane binary masks on a
224×224 N0f8 image. All six cases improved in this repeated comparison.
Reproduce with [streaming_image_mean_roi_benchmark.jl](streaming_image_mean_roi_benchmark.jl).
The original broad-run rows are retained above rather than discarded.

| ROI | Selection | Median before µs | Median after µs | Speedup |
|:--|:--|--:|--:|--:|
| checkerboard | inside | 35.32 | 27.22 | 1.30× |
| checkerboard | outside | 35.48 | 26.50 | 1.34× |
| random | inside | 180.84 | 146.66 | 1.23× |
| random | outside | 180.50 | 148.55 | 1.22× |
| half-plane | inside | 36.41 | 30.13 | 1.21× |
| half-plane | outside | 36.85 | 29.39 | 1.25× |
