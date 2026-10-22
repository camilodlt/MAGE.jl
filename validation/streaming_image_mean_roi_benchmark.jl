# Focused N0f8 ROI benchmark. Run in an environment containing this checkout
# and BenchmarkTools. Five alternating before/after rounds, 200 samples each.
# Every result is consumed; there are no CI timing thresholds.
using MAGE, ImageCore, Random, Statistics, BenchmarkTools
const ST = MAGE.number_intensityStatsFromImg
const sink = Ref(0.0)

function old_inside(image, roi)
    mask, predicate = ST._roi(image, roi)
    return ST._summary(image.img, ST._Inside(mask, predicate)).mean
end
function old_outside(image, roi)
    mask, predicate = ST._roi(image, roi)
    return ST._summary(image.img, ST._Outside(mask, predicate)).mean
end

rng = MersenneTwister(7)
image = SImageND(IntensityPixel{N0f8}.(rand(rng, 224, 224)))
for (label, bits) in (
    ("checkerboard", [isodd(r+c) for r in 1:224, c in 1:224]),
    ("random", rand(rng, Bool, 224, 224)),
    ("half-plane", [r <= 112 for r in 1:224, c in 1:224]),
)
    roi = SImageND(BinaryPixel.(bits))
    for (kind, before, after) in (
        ("inside", old_inside, ST.stat_mean),
        ("outside", old_outside, ST.stat_mean_out),
    )
        @assert before(image, roi) === after(image, roi)
        before_times = Float64[]
        after_times = Float64[]
        for round in 1:5
            order = iseven(round) ? ((after,after_times), (before,before_times)) :
                ((before,before_times), (after,after_times))
            for (fn, times) in order
                trial = @benchmark sink[] = $fn($image,$roi) samples=200 evals=1
                push!(times, median(trial).time / 1e3)
            end
        end
        println(label, " ", kind, " before_us=", before_times, " after_us=", after_times,
            " median_speedup=", median(before_times) / median(after_times))
        flush(stdout)
    end
end
