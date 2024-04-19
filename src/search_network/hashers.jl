import Serialization: serialize, bytes2hex
import DuckDB
import DataStructures: OrderedDict
import SearchNetworks as sn
import DataFrames as df
import SHA


#####################
# HASHERS           #
#####################

# SERIALIZER --- --- 
"""
    general_serializer(element::T) where {T}

Serializes the element with `Serialization`.
"""
function general_serializer(element::T) where {T}
    write_iob = IOBuffer()
    serialize(write_iob, element)
    seekstart(write_iob)
    c = read(write_iob)
    return c
end

# GENERAL HASHER --- --- 
"""
    general_hasher_sha(element::T) where {T}

Serializes an element and then calculates the SHA256 of that serialization value. 
The hash is then transformed to hex values to make it shorter. 

An hash, in the form of an string, is returned. 

This method may be used to hash every element in the package. 
Also, it should be session persistent.
"""
function general_hasher_sha(element::T) where {T}
    s = general_serializer(element)
    return bytes2hex(sha256(s))
end


# EXPORTS # 
export general_serializer
export general_hasher_sha

