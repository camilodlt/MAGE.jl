using LRUCache

abstract type AbstractCacheConfig end

struct CacheConfig <: AbstractCacheConfig
    cache_size::Int
    cache_key_type::DataType
    cache_value_type::DataType
end

struct NoCacheConfig <: AbstractCacheConfig end

function _create_fn_cache(cache_config::CacheConfig)
    return LRU{cache_config.cache_key_type, cache_config.cache_value_type}(; maxsize = cache_config.cache_size)
end

_create_fn_cache(cache_config::NoCacheConfig) = nothing

export CacheConfig, NoCacheConfig
