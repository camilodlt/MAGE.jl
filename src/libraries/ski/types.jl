"""
    SkiRegions{S}()

Owned region geometry for image size `S = Tuple{height,width}`. Labels are
Int32, bboxes use inclusive Julia indices, and `n` is the region count. `image`
and `intensity` reference the labeled image and optional intensity source.
Neither label maps nor referenced images are copied by derived operators.
"""
mutable struct SkiRegions{S<:Tuple}
    labels::Matrix{Int32}
    boxes::Vector{NTuple{4,Int}}
    n::Int
    counts::Vector{Int}
    image::Union{Nothing,SImageND{S}}
    intensity::Union{Nothing,SImageND{S}}
end
function SkiRegions{S}() where {S<:Tuple}
    h, w = S.parameters
    SkiRegions{S}(zeros(Int32, h, w), NTuple{4,Int}[], 0, Int[], nothing, nothing)
end

"""
    SkiVector{S}([values])

Size-typed scalar properties and Int32 region ids (`0` means no region).
`own` is this step's owned geometry buffer; `regions` references the geometry
actually used. Property calls label into `own`; derived calls share their
input's `regions`. Evaluator steps have distinct buffers for their lifetime,
and acyclic DAG execution keeps these references valid within one evaluation.
Retained outputs/caches can observe referenced buffers overwritten by a later
evaluation. Direct property calls without `out` allocate fresh owned geometry.
"""
mutable struct SkiVector{S<:Tuple} <: AbstractVector{Float64}
    values::Vector{Float64}
    ids::Vector{Int32}
    own::SkiRegions{S}
    regions::SkiRegions{S}
end
function SkiVector{S}() where {S<:Tuple}
    own = SkiRegions{S}()
    SkiVector{S}(Float64[], Int32[], own, own)
end
function SkiVector{S}(v::AbstractVector{<:Real}) where {S<:Tuple}
    out = SkiVector{S}()
    resize!(out.values, length(v))
    copyto!(out.values, v)
    resize!(out.ids, length(v))
    fill!(out.ids, 0)
    out
end
# Size-free constants remain useful for direct scalar-vector calculations.
SkiVector() = SkiVector{Tuple{0,0}}()
SkiVector(v::AbstractVector{<:Real}) = SkiVector{Tuple{0,0}}(v)
Base.size(v::SkiVector) = size(v.values)
Base.IndexStyle(::Type{<:SkiVector}) = IndexLinear()
Base.getindex(v::SkiVector, i::Int) = v.values[i]
Base.setindex!(v::SkiVector, x, i::Int) = (v.values[i] = x)
function Base.copy(v::SkiVector{S}) where {S}
    out = SkiVector{S}()
    resize!(out.values, length(v))
    resize!(out.ids, length(v))
    copyto!(out.values, v.values)
    copyto!(out.ids, v.ids)
    out.regions = v.regions
    out
end
# BufferPool registration lives with the type, like SImageND's image_utils.jl
# methods. _take_buffer! reuses one slot per index across evaluator generations.
_has_static_size(::Type{<:SkiVector}) = true
_new_buffer(::Type{SkiVector{S}}) where {S} = SkiVector{S}()
