# LIST ---

"""
    listinteger_caster(l :: Vector{<:Number})

Cast a vector of generic Number type to concrete Int64 type. 

Numbers are floored.
"""
function listinteger_caster(l::Vector{<:Any})::Vector{Int}
    if isempty(l)
        return Int[]
    end
    return floor.(Int, l)
end

"""
    listfloat_caster(l :: Vector{<:Number})

Cast a vector of generic Number type to concrete Float64 type. 

"""
function listfloat_caster(l::Vector{<:Any})::Vector{Float64}
    if isempty(l)
        return Float64[]
    end
    return convert.(Float64, l)
end

"""
    liststring_caster(l :: Vector{<:Any})

Cast a vector of generic Number type to concrete Float64 type. 

"""
function liststring_caster(l::Vector{<:Any})
    if isempty(l)
        return String[]
    end
    return string.(l)
end


"""
    listtuple_identity(l::Vector{Tuple{T,T}}) where {T}

Returns the identity of each el in l.
"""
function listtuple_identity(l::Vector{Tuple{T,T}}) where {T}
    return identity.(l)
end

# ELEMENTS ---

"""
    bool_to_int_caster(b::Bool)::Int

Returns 1 or 0.
"""
function bool_to_int_caster(b::Bool)::Int
    return Int(b)
end

"""
    integer_caster(i::Number)

Returns the floored number.
"""
function integer_caster(i::Number)::Int
    return clamp(floor(Int, i), MIN_INT[], MAX_INT[])
end

"""
    float_caster(i::Number)

Returns the number as Float64
"""
function float_caster(n::Number)
    return clamp(convert(Float64, n), MIN_FLOAT[], MAX_FLOAT[])
end

"""
    string_caster(s::Any)

Returns the element as a string
"""
function string_caster(s::Any)
    return string(s)
end
