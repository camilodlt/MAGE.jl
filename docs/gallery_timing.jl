# Included once in each Documenter example sandbox. The returned gallery value
# is the first call's actual result; only subsequent, warmed calls are measured.
using Markdown
import Statistics

const G_TIMINGS = NamedTuple[]
const G_INPUT_IDS = IdDict{Any,Int}()
const G_INPUT_NAMES = IdDict{Any,String}()

"Name an input before measuring it, so readers can match its image and timing row."
g_name!(image::UTCGP.SizedImage, name) = (G_INPUT_NAMES[image.img] = string(name); image)
const G_TIMING_KEYS = Set{Tuple{Any,String}}()

function g_argument(arg)
    if arg isa UTCGP.SizedImage
        id = get!(G_INPUT_IDS, arg.img) do
            length(G_INPUT_IDS) + 1
        end
        name = get(G_INPUT_NAMES, arg.img, "image")
        return "$name #$id"
    end
    return replace(repr(arg), "|" => "\\|", "\n" => " ")
end

"""
    g_call(fn, args...; label = nothing)

Run the actual operator through `invokelatest` and record warmed timings for
this function/input combination. Factory creation, loading, drawing and PNG
encoding are excluded. These helpers are for deterministic, non-mutating
examples; do not use them to benchmark random or stateful operators.

The first call supplies the example output and is excluded from measurements.
Collect up to `MAGE_DOC_TIMING_SAMPLES` samples (default 3, range 1–20). Stop
sampling an expensive case after 0.1 s of measured work. This bounds repeats,
not individual calls: it is not a timeout. Input identities are retained only for the lifetime of the example sandbox.
"""
function g_call(@nospecialize(fn), args...; label = nothing)
    # The operator itself runs through invokelatest. Compiling this logging
    # wrapper again for every generated function/type only slows docs builds.
    @nospecialize args
    result = Base.invokelatest(fn, args...)
    # Factory-generated names contain their entire concrete image type.
    name = label === nothing ? first(split(string(nameof(fn)), r"_S(?:ImageND|Image2D|Image3D|izedImage)"; limit = 2)) : String(label)
    inputs = join(g_argument.(args), "; ")
    key = (fn, inputs)
    if !(key in G_TIMING_KEYS)
        samples = clamp(parse(Int, get(ENV, "MAGE_DOC_TIMING_SAMPLES", "3")), 1, 20)
        times, bytes = Float64[], Int[]
        for _ in 1:samples
            measurement = @timed Base.invokelatest(fn, args...)
            push!(times, measurement.time)
            push!(bytes, measurement.bytes)
            sum(times) >= 0.1 && break
        end
        output = result isa UTCGP.SizedImage ? "$(join(size(result), '×')), $(eltype(result.img))" : string(typeof(result))
        scalar_args = result isa Number && all(a -> a isa Real, args) ? args : nothing
        push!(G_TIMINGS, (; name, inputs, output, scalar_args, median = Statistics.median(times), maximum = maximum(times),
                           bytes = Statistics.median(bytes), samples = length(times)))
        push!(G_TIMING_KEYS, key)
    end
    return result
end

"Wrap a factory-produced operator so every example call records its timing."
struct GTimedFunction{F}
    fn::F
end
(f::GTimedFunction)(args...) = g_call(f.fn, args...)
g_call(f::GTimedFunction, args...; kwargs...) = g_call(f.fn, args...; kwargs...)
g_timed(fn) = GTimedFunction(fn)
g_timed(fn::GTimedFunction) = fn

"Argument ranges of the numeric calls used to draw a scalar plot."
function g_scalar_ranges(cases)
    n = length(first(cases).scalar_args)
    n == 0 && return "no arguments"
    return join([begin
        values = [t.scalar_args[k] for t in cases]
        finite = filter(isfinite, values)
        specials = unique(repr.(filter(x -> !isfinite(x), values)))
        range = isempty(finite) ? "" : minimum(finite) == maximum(finite) ?
            repr(first(finite)) : "[$(repr(minimum(finite))), $(repr(maximum(finite)))]"
        "arg$k: " * join(filter(!isempty, vcat([range], specials)), ", ")
    end for k in 1:n], "; ")
end

"Render actual measurements, with image metadata listed once and scalar plot calls grouped."
function g_timings()
    io = IOBuffer()
    println(io, "Julia `$(VERSION)`; $(Sys.CPU_NAME); $(Threads.nthreads()) Julia thread(s); optimisation level $(Base.JLOptions().opt_level).\n")
    println(io, "Times are warmed wall-clock measurements of the actual calls above, including `invokelatest` and allocations. ",
        "Loading, factory generation and image rendering are excluded. CPU load and garbage collection affect these values. ",
        "The maximum is the slowest observed sample, **not a worst-case bound**.\n")
    if !isempty(G_INPUT_IDS)
        println(io, "| Input | Dimensions | Pixel storage |")
        println(io, "|:--|:--|:--|")
        for (pixels, id) in sort(collect(G_INPUT_IDS); by = last)
            name = replace(get(G_INPUT_NAMES, pixels, "image"), "|" => "\\|", "\n" => " ")
            println(io, "| $name #$id | $(join(size(pixels), '×')) | `$(eltype(pixels))` |")
        end
        println(io)
    end
    println(io, "Numeric-only plot calls of the same operator and arity are grouped: argument ranges cover the sampled values, ",
        "the median is the median of the per-case medians, and the maximum covers every observed sample. ",
        "Image calls keep a row for each input/parameter combination.\n")
    groups = Vector{Vector{NamedTuple}}()
    scalar_groups = Dict{Tuple{String,Int,String},Int}()
    for t in G_TIMINGS
        if t.scalar_args === nothing
            push!(groups, [t])
        else
            key = (t.name, length(t.scalar_args), t.output)
            index = get!(scalar_groups, key) do
                push!(groups, NamedTuple[])
                length(groups)
            end
            push!(groups[index], t)
        end
    end
    println(io, "| Operator | Inputs | Output | Median (µs) | Observed max (µs) | Allocated bytes (median) | Cases / samples |")
    println(io, "|:--|:--|:--|--:|--:|--:|--:|")
    for cases in groups
        t = first(cases)
        inputs = length(cases) == 1 ? t.inputs : g_scalar_ranges(cases)
        typical = Statistics.median([c.median for c in cases])
        slowest = maximum(c.maximum for c in cases)
        bytes = Statistics.median([c.bytes for c in cases])
        samples = sum(c.samples for c in cases)
        println(io, "| `$(t.name)` | $inputs | $(t.output) | $(round(typical * 1e6; digits = 2)) | ",
            "$(round(slowest * 1e6; digits = 2)) | $(round(Int, bytes)) | $(length(cases)) / $samples |")
    end
    isempty(G_TIMINGS) && println(io, "| No measured calls | | | | | | |")
    # Markdown emits an align attribute on every cell. One CSS rule expresses
    # the same layout without multiplying page size across hundreds of rows.
    html = sprint(show, MIME"text/html"(), Markdown.parse(String(take!(io))))
    html = replace(html, r" align=\"(?:left|right)\"" => "")
    html = replace(html, "&#123;" => "{", "&#125;" => "}", "&#40;" => "(",
                   "&#41;" => ")", "&#91;" => "[", "&#93;" => "]")
    style = "<style>.mage-timings td:nth-child(n+4),.mage-timings th:nth-child(n+4){text-align:right}</style>"
    return HTML(style * "<div class=\"mage-timings\">" * html * "</div>")
end
