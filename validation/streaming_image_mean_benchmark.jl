# Run in an environment containing this checkout, ImageCore and BenchmarkTools:
# julia --project=/path/to/environment validation/streaming_image_mean_benchmark.jl
# Print Markdown to stdout; this is a benchmark, not a CI timing assertion.
using MAGE, ImageCore, Random, Statistics, BenchmarkTools

const ST = MAGE.number_intensityStatsFromImg
const MEAN_BENCHMARK_RESULT = Ref(0.0)

# Preserve the previous algorithm as the comparison: build the general summary,
# read its mean, and (for difference) repeat independently for the other region.
summary_mean(image) = ST._summary(image.img, ST._All()).mean
function summary_mean(image, roi)
    mask, predicate = ST._roi(image, roi)
    return ST._summary(image.img, ST._Inside(mask, predicate)).mean
end
function summary_mean_out(image, roi)
    mask, predicate = ST._roi(image, roi)
    return ST._summary(image.img, ST._Outside(mask, predicate)).mean
end
summary_mean_diff(image, roi) = summary_mean(image, roi) - summary_mean_out(image, roi)

cold_bytes(fn::F, args::A) where {F,A<:Tuple} =
    fetch(@async @allocated (MEAN_BENCHMARK_RESULT[] = fn(args...)))
function measure(fn::F, args::A; samples=11) where {F,A<:Tuple}
    fn(args...)
    cold_bytes(fn, args) # compile the fresh-task measurement helper
    first_use_bytes = cold_bytes(fn, args)
    # Consume every result: at -O2 a pure N0f8/N0f16 mean whose value is unused
    # can otherwise be eliminated, producing a meaningless near-zero timing.
    trial = @benchmark MEAN_BENCHMARK_RESULT[] = $fn($args...) samples=samples evals=1
    return (seconds=median(trial).time / 1e9, cold=first_use_bytes, warm=trial.memory)
end

println("# Streaming image mean benchmark\n")
println("Julia ", VERSION, "; CPU: `", Sys.CPU_NAME, "`; default threads: ", Threads.nthreads(), ".\n")
println("Julia optimization level: ", Base.JLOptions().opt_level, ".\n")
println("Before = the former general-summary algorithm, retained in this script.")
println("Times are medians of 11 warmed calls, without coverage or forced bounds checks.")
println("Fresh-task bytes exclude task creation and compilation; each task starts without scratch buffers.")
println("Warmed bytes reuse any existing scratch buffers. Inputs are created before measurement.")
println("These observations depend on hardware and load; they are not timing guarantees.\n")
println("| Storage | Shape | Selection | Before µs | After µs | Speedup | Fresh bytes before / after | Warm bytes before / after |")
println("|:--|:--|:--|--:|--:|--:|--:|--:|")
rng = MersenneTwister(20261022)
for dims in ((224,224), (224,224,3), (128,128,128))
    values = rand(rng, dims...)
    spatial = [isodd(r+c) for r in 1:dims[1], c in 1:dims[2]]
    roi = SImageND(BinaryPixel.(spatial))
    empty_roi = SImageND(BinaryPixel.(falses(dims[1:2])))
    for storage in (N0f8, N0f16, Float32, Float64)
        image = SImageND(IntensityPixel{storage}.(values))
        for (label, old, new, args) in (
            ("whole", summary_mean, ST.stat_mean, (image,)),
            ("inside", summary_mean, ST.stat_mean, (image,roi)),
            ("outside", summary_mean_out, ST.stat_mean_out, (image,roi)),
            ("difference", summary_mean_diff, ST.stat_mean_diff, (image,roi)),
            ("empty ROI", summary_mean, ST.stat_mean, (image,empty_roi)),
        )
            @assert old(args...) === new(args...)
            GC.gc()
            before = measure(old, args)
            after = measure(new, args)
            println("| ",storage," | ",join(dims,'×')," | ",label," | ",
                round(before.seconds*1e6;digits=2)," | ",round(after.seconds*1e6;digits=2)," | ",
                round(before.seconds/after.seconds;digits=2),"× | ",before.cold," / ",after.cold,
                " | ",before.warm," / ",after.warm," |")
            flush(stdout)
        end
    end
end
