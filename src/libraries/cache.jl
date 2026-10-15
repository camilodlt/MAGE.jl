using LRUCache

abstract type AbstractCacheConfig end

"""
    CacheConfig(cache_size::Int, cache_key_type::DataType, cache_value_type::DataType)

Ask a [`FunctionWrapper`](@ref) to memoise its calls in an LRU cache of at most
`cache_size` entries.

Worth it for expensive, frequently repeated calls — image filters over a fixed
dataset, say — where the same `(function, arguments)` pair recurs across
individuals and generations.

```julia
FunctionWrapper(fn, :blur, caster, fallback; cache_config = CacheConfig(1000, Tuple, Any))
```

The default is [`NoCacheConfig`](@ref).
"""
struct CacheConfig <: AbstractCacheConfig
    cache_size::Int
    cache_key_type::DataType
    cache_value_type::DataType
end

"""
    NoCacheConfig()

Default cache policy: a [`FunctionWrapper`](@ref) carrying it recomputes every
call. See [`CacheConfig`](@ref) for the memoising alternative.
"""
struct NoCacheConfig <: AbstractCacheConfig end

function _create_fn_cache(cache_config::CacheConfig)
    return LRU{cache_config.cache_key_type, cache_config.cache_value_type}(; maxsize = cache_config.cache_size)
end

_create_fn_cache(cache_config::NoCacheConfig) = nothing

export CacheConfig, NoCacheConfig
