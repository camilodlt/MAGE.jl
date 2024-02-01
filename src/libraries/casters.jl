d_neg = "-100000"
d_pos = "100000"

MIN_INT = parse(Int, get(ENV, "UTCGP_MIN_INT", d_neg))
MAX_INT = parse(Int, get(ENV, "UTCGP_MAX_INT", d_pos))
MIN_FLOAT = parse(Int, get(ENV, "UTCGP_MIN_FLOAT", d_neg))
MAX_FLOAT = parse(Int, get(ENV, "UTCGP_MAX_FLOAT", d_pos))

println("Caster: Min Int : $MIN_INT")
println("Caster: Max Int : $MAX_INT")
# LIST ---

"""
    listinteger_caster(l :: Vector{<:Number})

Cast a vector of generic Number type to concrete Int64 type. 

Numbers are floored.
"""
function listinteger_caster(l::Vector{<:Any})::Vector{Int}
    if isempty(l)
        return Int.([])
    end
    return floor.(Int, l)
end

"""
    listfloat_caster(l :: Vector{<:Number})

Cast a vector of generic Number type to concrete Float64 type. 

"""
function listfloat_caster(l::Vector{<:Any})
    if isempty(l)
        return Float64.([])
    end
    return convert.(Float64, l)
end

"""
    liststring_caster(l :: Vector{<:Any})

Cast a vector of generic Number type to concrete Float64 type. 

"""
function liststring_caster(l::Vector{<:Any})
    if isempty(l)
        return String.([])
    end
    return string.(l)
end


"""
    liststring_caster(l :: Vector{<:Any})

Returns the identity of each el in l.
"""
function listtuple_identity(l::Vector{Tuple{T,T}}) where {T}
    return identity.(l)
end

# ELEMENTS ---
"""
    integer_caster(i::Number)

Returns the floored number.
"""
function integer_caster(i::Number)::Int
    return clamp(floor(Int, i), MIN_INT, MAX_INT)
end

"""
    float_caster(i::Number)

Returns the number as Float64
"""
function float_caster(n::Number)
    return clamp(convert(Float64, n), MIN_FLOAT, MAX_FLOAT)
end

"""
    string_caster(s::Any)

Returns the element as a string
"""
function string_caster(s::Any)
    return string(s)
end
