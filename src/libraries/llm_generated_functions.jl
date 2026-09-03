############################
# Generated Function Types
############################

abstract type AbstractGeneratedFunctionClient end

"""
    GeneratedFunctionSpec(name, argument_names, input_types, output_type, body; description = "")

Structured description of one LLM-proposed function. The `body` string is only
the inside of the function; MAGE renders the typed function signature and the
keyword-bound callable names itself.

Example: `GeneratedFunctionSpec(:sum_plus_one, [:x1, :x2], [Int, Int], Int, "return x1 + x2 + 1")`
"""
struct GeneratedFunctionSpec
    name::Symbol
    argument_names::Vector{Symbol}
    input_types::Vector{DataType}
    output_type::DataType
    body::String
    description::String
    function GeneratedFunctionSpec(
            name::Symbol,
            argument_names::Vector{Symbol},
            input_types::Vector{DataType},
            output_type::DataType,
            body::AbstractString;
            description::AbstractString = "",
        )
        @assert !isempty(argument_names) "Generated functions must declare at least one argument."
        @assert length(argument_names) == length(input_types) "Argument names and input types must have the same length."
        @assert length(unique(argument_names)) == length(argument_names) "Argument names must be unique."
        @assert !isempty(strip(String(body))) "Generated function body cannot be empty."
        return new(
            name,
            copy(argument_names),
            copy(input_types),
            output_type,
            String(body),
            String(description),
        )
    end
end

"""
    GeneratedFunctionValidationReport

Detailed result of validating one generated function candidate against MAGE's
arity, type, dispatch, runtime, and sample-execution constraints.

Example: a rejected report carries `accepted = false` and a non-empty `errors` list.
"""
struct GeneratedFunctionValidationReport
    accepted::Bool
    compile_ok::Bool
    arity_ok::Bool
    input_types_ok::Bool
    output_type_ok::Bool
    dispatch_ok::Bool
    runtime_ok::Bool
    mean_runtime_seconds::Float64
    sample_outputs::Vector{Any}
    errors::Vector{String}
    stacktrace::String
end

"""
    GeneratedFunctionArtifact

Compiled representation of one generated function. The stored `source` is the
exact Julia code evaluated, and `function_like` is the callable object MAGE
will later wrap in a normal `FunctionWrapper`.

Example: after validation succeeds, this artifact can be installed into a `MetaLibrary`.
"""
struct GeneratedFunctionArtifact
    spec::GeneratedFunctionSpec
    source::String
    keyword_bindings::Dict{Symbol, Any}
    module_name::Symbol
    function_like::AbstractFunction
end

"""
    GeneratedFunctionAttempt

One synthesis-loop attempt pairing the candidate spec, optional compiled
artifact, and the resulting validation report.

Example: a repair loop stores several attempts so later inspection can explain failures.
"""
struct GeneratedFunctionAttempt
    spec::GeneratedFunctionSpec
    artifact::Union{Nothing, GeneratedFunctionArtifact}
    report::GeneratedFunctionValidationReport
end

"""
    GeneratedFunctionSynthesisResult

Final result of an iterative generate/repair loop. `accepted_artifact` is only
present when one candidate passed validation.

Example: if every repair fails, `accepted_artifact === nothing` and `attempts` explains why.
"""
struct GeneratedFunctionSynthesisResult
    accepted_artifact::Union{Nothing, GeneratedFunctionArtifact}
    attempts::Vector{GeneratedFunctionAttempt}
end

"""
    SourceBackedFunction

Callable function-like object backed by dynamically evaluated Julia source. It
stores the exact source, declared signature, and keyword-bound helper callables
so MAGE can inspect and call it without exposing anonymous wrapper internals to
the prompting layer.

`cached_kw_pairs` is `keyword_bindings` pre-converted to the `NamedTuple` shape
the call operator needs, computed once here at construction rather than on
every call -- `keyword_bindings` itself never changes after construction (see
`compile_generated_function`, the only place `SourceBackedFunction` is built),
so rebuilding the same `NamedTuple` from it on every single invocation was
pure repeated work. NOT safe to share this `NamedTuple` (or the underlying
namespace objects it holds) across *different* `SourceBackedFunction`s, even
ones installed into the same `MetaLibrary`: `generated_function_bindings`
rebuilds a fresh namespace snapshot on every call, so a function only ever
sees whichever sibling functions were installed strictly before it -- see the
loader loop in `load_accepted_llm_functions!`.

Example: installed generated functions in a `MetaLibrary` use this wrapper as their callable core.
"""
mutable struct SourceBackedFunction <: AbstractFunction
    name::Symbol
    source::String
    argument_names::Vector{Symbol}
    input_types::Vector{DataType}
    output_type::DataType
    runtime_fn::Function
    keyword_bindings::Dict{Symbol, Any}
    cached_kw_pairs::NamedTuple
    module_name::Symbol
end

"""
    GeneratedFunctionNameDispatcher(name, callables)

Local dispatcher used inside one generated-function namespace when several
callables intentionally share the same readable name. It behaves like a small
method table keyed by runtime argument types.

Example: if `fns_returning_float.reduce_length` exists for both strings and images, the
namespace exposes a single property whose dispatcher picks the compatible
underlying callable at call time.
"""
struct GeneratedFunctionNameDispatcher
    name::Symbol
    callables::Vector{Any}
end

"""
    GeneratedFunctionNamespace(name, callables)

Namespace object exposed to generated Julia code through keyword arguments such
as `fns_returning_intensity_img` or `fns_returning_float`. Inside the generated body the LLM can
write expressions like:

```julia
tmp = fns_returning_intensity_img.laplacian3_image2D(x1)
score = fns_returning_float.region_mean_10p(x1, 0.5, 0.5)
```

Each namespace keeps one readable callable name per library.
"""
mutable struct GeneratedFunctionNamespace
    name::Symbol
    callables::Dict{Symbol, Any}
end

function (dispatcher::GeneratedFunctionNameDispatcher)(inputs...)
    for callable in dispatcher.callables
        if applicable(callable, inputs...)
            return callable(inputs...)
        end
    end
    throw(MethodError(dispatcher, Tuple{map(typeof, inputs)...}))
end

function Base.which(dispatcher::GeneratedFunctionNameDispatcher, t::Type{<:Tuple})
    for callable in dispatcher.callables
        try
            return Base.which(callable, t)
        catch
        end
    end
    throw(MethodError(dispatcher, t))
end

############################
# Client Interface
############################

"""
    LlamaCppGeneratedFunctionClient

Persistent Julia-side chat client for one local `llama-server` instance. This
backend speaks the OpenAI-compatible `/v1/chat/completions` API exposed by
`llama.cpp`, which also supports JSON-schema constrained output and multimodal
`image_url` content parts.
"""
mutable struct LlamaCppGeneratedFunctionClient <: AbstractGeneratedFunctionClient
    model_name::String
    host::String
    keep_alive::String
    think::Bool
    temperature::Float64
    max_new_tokens::Int
    system_prompt::String
    max_arity::Int
    input_type_aliases::Dict{String, DataType}
    output_type_aliases::Dict{String, DataType}
    messages::Vector{Dict{String, Any}}
    last_prompt::String
    last_request_payload::Dict{String, Any}
    last_response_payload::Dict{String, Any}
    last_raw_response::String
    last_elapsed_seconds::Float64
end

"""
    GeminiGeneratedFunctionClient

Generated-function client for Google Gemini's `generateContent` API. It keeps
the same observable fields as the llama.cpp client so runner-side orchestration
can log prompts, responses, timings, and attempts without provider branches.
"""
mutable struct GeminiGeneratedFunctionClient <: AbstractGeneratedFunctionClient
    model_name::String
    host::String
    api_key::String
    keep_alive::String
    think::Bool
    temperature::Float64
    max_new_tokens::Int
    system_prompt::String
    max_arity::Int
    input_type_aliases::Dict{String, DataType}
    output_type_aliases::Dict{String, DataType}
    messages::Vector{Dict{String, Any}}
    last_prompt::String
    last_request_payload::Dict{String, Any}
    last_response_payload::Dict{String, Any}
    last_raw_response::String
    last_elapsed_seconds::Float64
    min_request_interval_seconds::Float64
    last_request_started_at::Float64
    service_tier::String
end

"""
    OpenAICompatibleGeneratedFunctionClient

Generated-function client for hosted APIs that implement OpenAI-style
`/chat/completions`, such as RAGaRenn/Open WebUI instances.
"""
mutable struct OpenAICompatibleGeneratedFunctionClient <: AbstractGeneratedFunctionClient
    model_name::String
    host::String
    api_key::String
    keep_alive::String
    think::Bool
    temperature::Float64
    max_new_tokens::Int
    system_prompt::String
    max_arity::Int
    input_type_aliases::Dict{String, DataType}
    output_type_aliases::Dict{String, DataType}
    messages::Vector{Dict{String, Any}}
    last_prompt::String
    last_request_payload::Dict{String, Any}
    last_response_payload::Dict{String, Any}
    last_raw_response::String
    last_elapsed_seconds::Float64
    min_request_interval_seconds::Float64
    last_request_started_at::Float64
end

function _llama_cpp_url(client::LlamaCppGeneratedFunctionClient, endpoint::AbstractString)::String
    return string(rstrip(client.host, '/'), endpoint)
end

function _gemini_url(client::GeminiGeneratedFunctionClient)::String
    base = isempty(client.host) ? "https://generativelanguage.googleapis.com" : rstrip(client.host, '/')
    return string(base, "/v1beta/models/", client.model_name, ":generateContent")
end

function _openai_compatible_url(client::OpenAICompatibleGeneratedFunctionClient)::String
    return string(rstrip(client.host, '/'), "/chat/completions")
end

function _build_llm_type_alias_table(allowed_types::Vector{DataType})::Dict{String, DataType}
    alias_table = Dict{String, DataType}()
    for allowed_type in unique(allowed_types)
        alias_table[string(allowed_type)] = allowed_type
    end
    return alias_table
end

function _find_first_allowed_type(
        allowed_types::Vector{DataType},
        predicate::Function,
    )::Union{Nothing, DataType}
    for allowed_type in allowed_types
        predicate(allowed_type) && return allowed_type
    end
    return nothing
end

function _build_valid_generated_function_example(
        model_architecture::modelArchitecture,
    )::String
    allowed_input_types = _allowed_input_types(model_architecture)
    allowed_output_types = _allowed_output_types(model_architecture)

    intensity_input_type = _find_first_allowed_type(allowed_input_types, allowed_type -> begin
        allowed_type <: SizedImage && (_get_image_pixel_type(allowed_type) <: IntensityPixel)
    end)
    binary_input_type = _find_first_allowed_type(allowed_input_types, allowed_type -> begin
        allowed_type <: SizedImage && (_get_image_pixel_type(allowed_type) <: BinaryPixel)
    end)
    float_output_type = _find_first_allowed_type(allowed_output_types, allowed_type -> begin
        allowed_type <: Base.AbstractFloat
    end)

    if !isnothing(intensity_input_type) && !isnothing(binary_input_type) && !isnothing(float_output_type)
        return """
{"name":"outer_inner_intensity_gap","argument_names":["x1","x2","x3"],"input_types":["$(intensity_input_type)","$(binary_input_type)","$(binary_input_type)"],"output_type":"$(float_output_type)","body":"cell_union = image_values(x2) .| image_values(x3)\\nouter_cell = cell_union .& .!image_values(x2)\\nimg = image_values_float64(x1)\\nouter_values = img[outer_cell]\\ninner_values = img[image_values(x2)]\\nouter_mean = isempty(outer_values) ? 0.0 : mean(outer_values)\\ninner_mean = isempty(inner_values) ? 0.0 : mean(inner_values)\\nreturn outer_mean - inner_mean","description":"Measures the intensity gap between an outer cell ring and the inner masked region."}
"""
    end

    fallback_input_type = string(first(allowed_input_types))
    fallback_output_type = string(first(allowed_output_types))
    return """
{"name":"simple_centered_difference","argument_names":["x1","x2"],"input_types":["$(fallback_input_type)","$(fallback_input_type)"],"output_type":"$(fallback_output_type)","body":"return x1 - x2","description":"Computes a simple difference between two same-typed inputs."}
"""
end

function _build_invalid_generated_function_examples()::String
    return """
Invalid response example:
```julia
function calculate_mean_intensity(x1)
    return mean(x1)
end
```

Invalid response example:
Here is a useful function:
{"name":"some_fn","argument_names":["x1"],"input_types":["Float64"],"output_type":"Float64","body":"return x1","description":"Identity."}
"""
end

function _build_generated_function_system_prompt(
        model_architecture::modelArchitecture,
        node_config::nodeConfig,
    )::String
    allowed_input_types = join(string.(_allowed_input_types(model_architecture)), ", ")
    allowed_output_types = join(string.(_allowed_output_types(model_architecture)), ", ")
    valid_example = _build_valid_generated_function_example(model_architecture)
    invalid_examples = _build_invalid_generated_function_examples()
    return """
You are writing one Julia function for MAGE (a typed Cartesian Genetic Programming extension).
Return exactly one JSON object.
Do not return markdown.
Do not return code fences.
Do not return prose before or after the JSON object.
Do not return a docstring.
Do not return a full Julia function definition.
Do not return explanations.
The JSON fields must be:
- name: string
- argument_names: array of strings
- input_types: array of strings
- output_type: string
- body: string
- description: string

Valid response example:
$(valid_example)

$(invalid_examples)

Rules:
- The body is only the inside of the Julia function.
- The body must not include the `function ... end` wrapper.
- argument_names and input_types must have the same length.
- The function arity must be between 1 and $(node_config.arity).
- input_types must come only from: $(allowed_input_types)
- output_type must come only from: $(allowed_output_types)
- The generated body may use normal Julia language constructs such as local variables, indexing, broadcasting, arithmetic, comparisons, conditionals, and loops.
- The generated body may also call the readable callable names provided in the user prompt context through namespace objects such as fns_returning_intensity_img.some_function(...), fns_returning_binary_img.some_function(...), fns_returning_segment_img.some_function(...), fns_returning_int.some_function(...), or fns_returning_float.some_function(...).
- When calling a provided helper or library function, be mindful of its declared return type.
- Do not include imports, module declarations, or full function signatures.
- The description should explain the function semantically, not repeat raw source code.
"""
end

"""
    make_llm_generated_function_client(; model_name, model_architecture, node_config, ...)

Construct one `llama.cpp` generated-function client speaking to a local
`llama-server` OpenAI-compatible endpoint.

Example: `make_llm_generated_function_client(model_name = "ggml-org/gemma-4-E4B-it-GGUF", model_architecture = ma, node_config = nc)`
"""
function make_llm_generated_function_client(;
        model_name::AbstractString,
        model_architecture::modelArchitecture,
        node_config::nodeConfig,
        provider::AbstractString = "llama_cpp",
        host::AbstractString = "http://127.0.0.1:8080",
        api_key::AbstractString = get(ENV, "GEMINI_API_KEY", ""),
        keep_alive::AbstractString = "10m",
        think::Bool = true,
        temperature::Real = 0.0,
        max_new_tokens::Integer = 1536,
        min_request_interval_seconds::Real = 0.0,
        gemini_service_tier::AbstractString = "",
        system_prompt::AbstractString = _build_generated_function_system_prompt(model_architecture, node_config),
    )::AbstractGeneratedFunctionClient
    input_type_alias_table = _build_llm_type_alias_table(vcat(model_architecture.inputs_types, model_architecture.chromosomes_types))
    output_type_alias_table = _build_llm_type_alias_table(model_architecture.chromosomes_types)
    provider_name = lowercase(String(provider))
    if provider_name in ("gemini", "google_gemini")
        isempty(api_key) && error("Gemini provider requires GEMINI_API_KEY or llm_api_key.")
        return GeminiGeneratedFunctionClient(
            String(model_name),
            String(host),
            String(api_key),
            String(keep_alive),
            think,
            Float64(temperature),
            Int(max_new_tokens),
            String(system_prompt),
            node_config.arity,
            input_type_alias_table,
            output_type_alias_table,
            Dict{String, Any}[],
            "",
            Dict{String, Any}(),
            Dict{String, Any}(),
            "",
            0.0,
            Float64(min_request_interval_seconds),
            0.0,
            String(gemini_service_tier),
        )
    end
    if provider_name in ("openai_compatible", "openai-compatible", "openai", "ragarenn")
        isempty(api_key) && error("$(provider) provider requires llm_api_key or a provider-specific environment key.")
        return OpenAICompatibleGeneratedFunctionClient(
            String(model_name),
            String(host),
            String(api_key),
            String(keep_alive),
            think,
            Float64(temperature),
            Int(max_new_tokens),
            String(system_prompt),
            node_config.arity,
            input_type_alias_table,
            output_type_alias_table,
            Dict{String, Any}[],
            "",
            Dict{String, Any}(),
            Dict{String, Any}(),
            "",
            0.0,
            Float64(min_request_interval_seconds),
            0.0,
        )
    end
    provider_name in ("llama_cpp", "llama.cpp", "llama") || error("Unknown generated-function LLM provider $(provider).")
    return LlamaCppGeneratedFunctionClient(
        String(model_name),
        String(host),
        String(keep_alive),
        think,
        Float64(temperature),
        Int(max_new_tokens),
        String(system_prompt),
        node_config.arity,
        input_type_alias_table,
        output_type_alias_table,
        Dict{String, Any}[],
        "",
        Dict{String, Any}(),
        Dict{String, Any}(),
        "",
        0.0,
    )
end

llm_generated_function_client_backend(::LlamaCppGeneratedFunctionClient) = "llama_cpp"
llm_generated_function_client_backend(::GeminiGeneratedFunctionClient) = "gemini"
llm_generated_function_client_backend(::OpenAICompatibleGeneratedFunctionClient) = "openai_compatible"

function _build_llama_cpp_function_spec_schema(client::LlamaCppGeneratedFunctionClient)::Dict{String, Any}
    allowed_input_type_names = sort!(collect(keys(client.input_type_aliases)))
    allowed_output_type_names = sort!(collect(keys(client.output_type_aliases)))
    return Dict(
        "type" => "object",
        "properties" => Dict(
            "name" => Dict("type" => "string"),
            "argument_names" => Dict(
                "type" => "array",
                "items" => Dict("type" => "string"),
                "minItems" => 1,
                "maxItems" => client.max_arity,
            ),
            "input_types" => Dict(
                "type" => "array",
                "items" => Dict("type" => "string", "enum" => allowed_input_type_names),
                "minItems" => 1,
                "maxItems" => client.max_arity,
            ),
            "output_type" => Dict("type" => "string", "enum" => allowed_output_type_names),
            "body" => Dict("type" => "string"),
            "description" => Dict("type" => "string"),
        ),
        "required" => ["name", "argument_names", "input_types", "output_type", "body", "description"],
    )
end

function _build_generated_function_spec_schema(client::AbstractGeneratedFunctionClient)::Dict{String, Any}
    allowed_input_type_names = sort!(collect(keys(client.input_type_aliases)))
    allowed_output_type_names = sort!(collect(keys(client.output_type_aliases)))
    return Dict(
        "type" => "object",
        "properties" => Dict(
            "name" => Dict("type" => "string"),
            "argument_names" => Dict(
                "type" => "array",
                "items" => Dict("type" => "string"),
                "minItems" => 1,
                "maxItems" => client.max_arity,
            ),
            "input_types" => Dict(
                "type" => "array",
                "items" => Dict("type" => "string", "enum" => allowed_input_type_names),
                "minItems" => 1,
                "maxItems" => client.max_arity,
            ),
            "output_type" => Dict("type" => "string", "enum" => allowed_output_type_names),
            "body" => Dict("type" => "string"),
            "description" => Dict("type" => "string"),
        ),
        "required" => ["name", "argument_names", "input_types", "output_type", "body", "description"],
    )
end

function _post_llama_cpp_chat_request(
        client::LlamaCppGeneratedFunctionClient,
        request_payload::Dict{String, Any},
    )::Tuple{Dict{String, Any}, String, Float64}
    request_buffer = IOBuffer(JSON.json(request_payload))
    response_io = IOBuffer()
    started_at = time()
    # Large multimodal prompts against CPU- or hybrid-hosted llama.cpp models can
    # spend minutes in prompt processing before the first response bytes are sent.
    # Julia Downloads has a separate low-speed abort (20s at <1 B/s) that is not
    # controlled by the request timeout; disable it explicitly for this path.
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, info) -> begin
        Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_TIME, 0)
        Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_LIMIT, 0)
    end
    response = Downloads.request(
        _llama_cpp_url(client, "/v1/chat/completions");
        method = "POST",
        headers = ["Content-Type" => "application/json"],
        input = request_buffer,
        output = response_io,
        timeout = 3600.0,
        downloader = downloader,
    )
    elapsed_seconds = time() - started_at
    raw_response_text = String(take!(response_io))
    response.status == 200 || error("llama.cpp request failed with status $(response.status): $(raw_response_text)")
    return JSON.parse(raw_response_text), raw_response_text, elapsed_seconds
end

function _post_gemini_chat_request(
        client::GeminiGeneratedFunctionClient,
        request_payload::Dict{String, Any},
        retry_index::Int = 0,
    )::Tuple{Dict{String, Any}, String, Float64}
    if client.last_request_started_at > 0.0 && client.min_request_interval_seconds > 0.0
        seconds_since_last_request = time() - client.last_request_started_at
        sleep_seconds = client.min_request_interval_seconds - seconds_since_last_request
        if sleep_seconds > 0.0
            @info "Throttling Gemini request" sleep_seconds min_request_interval_seconds = client.min_request_interval_seconds
            sleep(sleep_seconds)
        end
    end
    request_buffer = IOBuffer(JSON.json(request_payload))
    response_io = IOBuffer()
    started_at = time()
    client.last_request_started_at = started_at
    downloader = Downloads.Downloader()
    downloader.easy_hook = (easy, info) -> begin
        Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_TIME, 0)
        Downloads.Curl.setopt(easy, Downloads.Curl.CURLOPT_LOW_SPEED_LIMIT, 0)
    end
    response = try
        Downloads.request(
            _gemini_url(client);
            method = "POST",
            headers = ["Content-Type" => "application/json", "x-goog-api-key" => client.api_key],
            input = request_buffer,
            output = response_io,
            timeout = 3600.0,
            downloader = downloader,
        )
    catch err
        if retry_index < 8 && err isa Downloads.RequestError
            sleep_seconds = min(300.0, max(client.min_request_interval_seconds, 10.0) * 2.0^retry_index)
            @warn "Gemini request failed at transport layer; retrying after backoff" retry_index sleep_seconds error = sprint(showerror, err)
            sleep(sleep_seconds)
            return _post_gemini_chat_request(client, request_payload, retry_index + 1)
        end
        rethrow()
    end
    elapsed_seconds = time() - started_at
    raw_response_text = String(take!(response_io))
    if response.status == 429
        retry_delay = _gemini_retry_delay_seconds(raw_response_text)
        sleep_seconds = max(retry_delay, client.min_request_interval_seconds, 1.0)
        @warn "Gemini request hit quota; retrying after delay" sleep_seconds raw_response = raw_response_text
        sleep(sleep_seconds)
        return _post_gemini_chat_request(client, request_payload, retry_index + 1)
    end
    if response.status in (500, 502, 503, 504) && retry_index < 8
        sleep_seconds = min(300.0, max(client.min_request_interval_seconds, 10.0) * 2.0^retry_index)
        @warn "Gemini request hit transient server error; retrying after backoff" status = response.status retry_index sleep_seconds raw_response = raw_response_text
        sleep(sleep_seconds)
        return _post_gemini_chat_request(client, request_payload, retry_index + 1)
    end
    response.status == 200 || error("Gemini request failed with status $(response.status): $(raw_response_text)")
    return JSON.parse(raw_response_text), raw_response_text, elapsed_seconds
end

function _post_openai_compatible_chat_request(
        client::OpenAICompatibleGeneratedFunctionClient,
        request_payload::Dict{String, Any},
    )::Tuple{Dict{String, Any}, String, Float64}
    if client.last_request_started_at > 0.0 && client.min_request_interval_seconds > 0.0
        seconds_since_last_request = time() - client.last_request_started_at
        sleep_seconds = client.min_request_interval_seconds - seconds_since_last_request
        if sleep_seconds > 0.0
            @info "Throttling OpenAI-compatible request" sleep_seconds min_request_interval_seconds = client.min_request_interval_seconds
            sleep(sleep_seconds)
        end
    end
    request_buffer = IOBuffer(JSON.json(request_payload))
    response_io = IOBuffer()
    started_at = time()
    client.last_request_started_at = started_at
    response = Downloads.request(
        _openai_compatible_url(client);
        method = "POST",
        headers = ["Content-Type" => "application/json", "Authorization" => "Bearer $(client.api_key)"],
        input = request_buffer,
        output = response_io,
        timeout = 3600.0,
    )
    elapsed_seconds = time() - started_at
    raw_response_text = String(take!(response_io))
    response.status == 200 || error("OpenAI-compatible request failed with status $(response.status): $(raw_response_text)")
    return JSON.parse(raw_response_text), raw_response_text, elapsed_seconds
end

function _gemini_retry_delay_seconds(raw_response_text::AbstractString)::Float64
    try
        payload = JSON.parse(String(raw_response_text))
        details = get(get(payload, "error", Dict{String, Any}()), "details", Any[])
        for detail in details
            detail isa AbstractDict || continue
            retry_delay = get(detail, "retryDelay", nothing)
            retry_delay isa AbstractString || continue
            matched = match(r"^([0-9]+(?:\.[0-9]+)?)s$", retry_delay)
            isnothing(matched) || return parse(Float64, matched.captures[1])
        end
    catch
    end
    return 0.0
end

function _build_generated_function_client_status(
        client::AbstractGeneratedFunctionClient,
    )::Dict{Symbol, Any}
    return Dict{Symbol, Any}(
        :backend => llm_generated_function_client_backend(client),
        :model_name => client.model_name,
        :host => client.host,
        :keep_alive => client.keep_alive,
        :think => client.think,
        :temperature => client.temperature,
        :max_new_tokens => client.max_new_tokens,
        :history_length => length(client.messages),
    )
end

function llm_generated_function_client_status(
        client::LlamaCppGeneratedFunctionClient,
    )::Dict{Symbol, Any}
    status = _build_generated_function_client_status(client)
    try
        read(Downloads.download(_llama_cpp_url(client, "/")))
        status[:reachable] = true
    catch err
        status[:reachable] = false
        status[:error] = sprint(showerror, err)
    end
    return status
end

function llm_generated_function_client_status(
        client::GeminiGeneratedFunctionClient,
    )::Dict{Symbol, Any}
    status = _build_generated_function_client_status(client)
    status[:reachable] = !isempty(client.api_key)
    status[:host] = isempty(client.host) ? "https://generativelanguage.googleapis.com" : client.host
    status[:api_key_present] = !isempty(client.api_key)
    return status
end

function llm_generated_function_client_status(
        client::OpenAICompatibleGeneratedFunctionClient,
    )::Dict{Symbol, Any}
    status = _build_generated_function_client_status(client)
    status[:api_key_present] = !isempty(client.api_key)
    status[:reachable] = !isempty(client.api_key)
    return status
end

function _base64_png_data_url(encoded_image::AbstractString)::String
    return "data:image/png;base64," * String(encoded_image)
end

function _gemini_json_schema(schema::Dict{String, Any})::Dict{String, Any}
    function convert_schema(value)
        return value
    end
    function convert_schema(value::Dict)
        converted = Dict{String, Any}()
        for (key, raw_child) in value
            converted[String(key)] = convert_schema(raw_child)
        end
        return converted
    end
    function convert_schema(value::Vector)
        return Any[convert_schema(child) for child in value]
    end
    return convert_schema(schema)
end

function _gemini_part_from_text(text::AbstractString)::Dict{String, Any}
    return Dict{String, Any}("text" => String(text))
end

function _gemini_part_from_png_base64(encoded_image::AbstractString)::Dict{String, Any}
    return Dict{String, Any}(
        "inlineData" => Dict(
            "mimeType" => "image/png",
            "data" => String(encoded_image),
        ),
    )
end

function _gemini_content_from_message(message::Dict{String, Any})::Dict{String, Any}
    role = String(get(message, "role", "user"))
    gemini_role = role == "assistant" ? "model" : "user"
    content = get(message, "content", "")
    parts = Any[]
    if content isa AbstractString
        push!(parts, _gemini_part_from_text(content))
    elseif content isa AbstractVector
        for part in content
            part isa AbstractDict || continue
            part_type = String(get(part, "type", ""))
            if part_type == "text"
                push!(parts, _gemini_part_from_text(String(get(part, "text", ""))))
            elseif part_type == "image_url"
                image_url = get(get(part, "image_url", Dict{String, Any}()), "url", "")
                prefix = "data:image/png;base64,"
                startswith(String(image_url), prefix) && push!(parts, _gemini_part_from_png_base64(String(image_url)[lastindex(prefix)+1:end]))
            end
        end
    end
    return Dict{String, Any}("role" => gemini_role, "parts" => parts)
end

function _build_llama_cpp_user_message(
        prompt::AbstractString;
        encoded_images::Vector{String} = String[],
    )::Dict{String, Any}
    if isempty(encoded_images)
        return Dict{String, Any}(
            "role" => "user",
            "content" => String(prompt),
        )
    end
    content_parts = Any[
        Dict("type" => "text", "text" => String(prompt)),
    ]
    for encoded_image in encoded_images
        push!(content_parts, Dict(
            "type" => "image_url",
            "image_url" => Dict("url" => _base64_png_data_url(encoded_image)),
        ))
    end
    return Dict{String, Any}(
        "role" => "user",
        "content" => content_parts,
    )
end

function _build_llama_cpp_message_history(client::LlamaCppGeneratedFunctionClient)::Vector{Dict{String, Any}}
    chat_history = Dict{String, Any}[]
    push!(chat_history, Dict("role" => "system", "content" => client.system_prompt))
    append!(chat_history, client.messages)
    return chat_history
end

function _build_llama_cpp_chat_request(
        client::LlamaCppGeneratedFunctionClient,
    )::Dict{String, Any}
    request_payload = Dict(
        "model" => client.model_name,
        "messages" => _build_llama_cpp_message_history(client),
        "stream" => false,
        "response_format" => Dict(
            "type" => "json_object",
            "schema" => _build_llama_cpp_function_spec_schema(client),
        ),
        "temperature" => client.temperature,
        "max_tokens" => client.max_new_tokens,
    )
    if !client.think
        request_payload["chat_template_kwargs"] = Dict("enable_thinking" => false)
    end
    return request_payload
end

function _llama_cpp_chat!(
        client::LlamaCppGeneratedFunctionClient,
        prompt::AbstractString,
        ;
        encoded_images::Vector{String} = String[],
    )::String
    client.last_prompt = String(prompt)
    push!(client.messages, _build_llama_cpp_user_message(prompt; encoded_images = encoded_images))
    request_payload = _build_llama_cpp_chat_request(client)
    client.last_request_payload = deepcopy(request_payload)
    response_payload, raw_response_text, elapsed_seconds = _post_llama_cpp_chat_request(client, request_payload)
    client.last_response_payload = response_payload
    client.last_raw_response = raw_response_text
    client.last_elapsed_seconds = elapsed_seconds
    @info "llama.cpp chat response" elapsed_seconds raw_response = raw_response_text
    @assert haskey(response_payload, "choices") "llama.cpp chat response did not contain choices: $(JSON.json(response_payload))"
    choices = response_payload["choices"]
    @assert !isempty(choices) "llama.cpp chat response contained no choices: $(JSON.json(response_payload))"
    choice = first(choices)
    @assert haskey(choice, "message") "llama.cpp choice did not contain message: $(JSON.json(choice))"
    message = choice["message"]
    @assert haskey(message, "content") "llama.cpp choice message did not contain content: $(JSON.json(message))"
    content = String(message["content"])
    push!(client.messages, Dict("role" => "assistant", "content" => content))
    return content
end

function _build_gemini_chat_request(
        client::GeminiGeneratedFunctionClient,
        schema::Dict{String, Any},
    )::Dict{String, Any}
    payload = Dict{String, Any}(
        "systemInstruction" => Dict("parts" => Any[_gemini_part_from_text(client.system_prompt)]),
        "contents" => Any[_gemini_content_from_message(message) for message in client.messages],
        "generationConfig" => Dict(
            "temperature" => client.temperature,
            "maxOutputTokens" => client.max_new_tokens,
            "responseMimeType" => "application/json",
            "responseJsonSchema" => _gemini_json_schema(schema),
        ),
    )
    if client.think
        payload["generationConfig"]["thinkingConfig"] = Dict("includeThoughts" => false)
    end
    if !isempty(strip(client.service_tier))
        payload["service_tier"] = strip(client.service_tier)
    end
    return payload
end

function _extract_gemini_text(response_payload::Dict{String, Any})::String
    candidates = get(response_payload, "candidates", Any[])
    isempty(candidates) && error("Gemini response contained no candidates: $(JSON.json(response_payload))")
    content = get(first(candidates), "content", Dict{String, Any}())
    parts = get(content, "parts", Any[])
    texts = String[]
    for part in parts
        part isa AbstractDict || continue
        haskey(part, "text") && push!(texts, String(part["text"]))
    end
    joined = join(texts, "\n")
    isempty(strip(joined)) && error("Gemini returned an empty assistant message instead of a JSON object.")
    return joined
end

function _gemini_chat!(
        client::GeminiGeneratedFunctionClient,
        prompt::AbstractString,
        schema::Dict{String, Any};
        encoded_images::Vector{String} = String[],
    )::String
    client.last_prompt = String(prompt)
    push!(client.messages, _build_llama_cpp_user_message(prompt; encoded_images = encoded_images))
    request_payload = _build_gemini_chat_request(client, schema)
    client.last_request_payload = deepcopy(request_payload)
    response_payload, raw_response_text, elapsed_seconds = _post_gemini_chat_request(client, request_payload)
    client.last_response_payload = response_payload
    client.last_raw_response = raw_response_text
    client.last_elapsed_seconds = elapsed_seconds
    @info "Gemini chat response" elapsed_seconds raw_response = raw_response_text
    content = _extract_gemini_text(response_payload)
    push!(client.messages, Dict("role" => "assistant", "content" => content))
    return content
end

function _build_openai_compatible_chat_request(
        client::OpenAICompatibleGeneratedFunctionClient,
        schema::Dict{String, Any},
    )::Dict{String, Any}
    request_payload = Dict{String, Any}(
        "model" => client.model_name,
        "messages" => vcat(
            Any[Dict("role" => "system", "content" => client.system_prompt)],
            client.messages,
        ),
        "stream" => false,
        "response_format" => Dict("type" => "json_object", "schema" => schema),
        "temperature" => client.temperature,
        "max_tokens" => client.max_new_tokens,
    )
    return request_payload
end

function _extract_openai_compatible_text(response_payload::Dict{String, Any})::String
    choices = get(response_payload, "choices", Any[])
    isempty(choices) && error("OpenAI-compatible response contained no choices: $(JSON.json(response_payload))")
    message = get(first(choices), "message", Dict{String, Any}())
    content = String(get(message, "content", ""))
    isempty(strip(content)) && error("The model returned an empty assistant message instead of a JSON object.")
    return content
end

function _openai_compatible_chat!(
        client::OpenAICompatibleGeneratedFunctionClient,
        prompt::AbstractString,
        schema::Dict{String, Any};
        encoded_images::Vector{String} = String[],
    )::String
    client.last_prompt = String(prompt)
    push!(client.messages, _build_llama_cpp_user_message(prompt; encoded_images = encoded_images))
    request_payload = _build_openai_compatible_chat_request(client, schema)
    client.last_request_payload = deepcopy(request_payload)
    response_payload, raw_response_text, elapsed_seconds = _post_openai_compatible_chat_request(client, request_payload)
    client.last_response_payload = response_payload
    client.last_raw_response = raw_response_text
    client.last_elapsed_seconds = elapsed_seconds
    @info "OpenAI-compatible chat response" elapsed_seconds raw_response = raw_response_text
    content = _extract_openai_compatible_text(response_payload)
    push!(client.messages, Dict("role" => "assistant", "content" => content))
    return content
end

function chat_json_schema!(
        client::LlamaCppGeneratedFunctionClient,
        system_prompt::AbstractString,
        user_prompt::AbstractString,
        schema::Dict{String, Any};
        encoded_images::Vector{String} = String[],
    )::String
    client.system_prompt = String(system_prompt)
    empty!(client.messages)
    client.last_prompt = String(user_prompt)
    push!(client.messages, _build_llama_cpp_user_message(user_prompt; encoded_images = encoded_images))
    request_payload = Dict(
        "model" => client.model_name,
        "messages" => vcat(
            Any[Dict("role" => "system", "content" => client.system_prompt)],
            client.messages,
        ),
        "stream" => false,
        "response_format" => Dict("type" => "json_object", "schema" => schema),
        "temperature" => client.temperature,
        "max_tokens" => client.max_new_tokens,
    )
    if !client.think
        request_payload["chat_template_kwargs"] = Dict("enable_thinking" => false)
    end
    client.last_request_payload = deepcopy(request_payload)
    response_payload, raw_response_text, elapsed_seconds = _post_llama_cpp_chat_request(client, request_payload)
    client.last_response_payload = response_payload
    client.last_raw_response = raw_response_text
    client.last_elapsed_seconds = elapsed_seconds
    @info "llama.cpp chat response" elapsed_seconds raw_response = raw_response_text
    choice = first(response_payload["choices"])
    message = choice["message"]
    content = String(get(message, "content", ""))
    isempty(strip(content)) && error("The model returned an empty assistant message instead of a JSON object.")
    push!(client.messages, Dict("role" => "assistant", "content" => content))
    return content
end

function chat_json_schema!(
        client::GeminiGeneratedFunctionClient,
        system_prompt::AbstractString,
        user_prompt::AbstractString,
        schema::Dict{String, Any};
        encoded_images::Vector{String} = String[],
    )::String
    client.system_prompt = String(system_prompt)
    empty!(client.messages)
    return _gemini_chat!(client, user_prompt, schema; encoded_images = encoded_images)
end

function chat_json_schema!(
        client::OpenAICompatibleGeneratedFunctionClient,
        system_prompt::AbstractString,
        user_prompt::AbstractString,
        schema::Dict{String, Any};
        encoded_images::Vector{String} = String[],
    )::String
    client.system_prompt = String(system_prompt)
    empty!(client.messages)
    return _openai_compatible_chat!(client, user_prompt, schema; encoded_images = encoded_images)
end

function _extract_generated_json_text(raw_response::AbstractString)::String
    stripped = strip(String(raw_response))
    isempty(stripped) && error("The model returned an empty assistant message instead of a JSON object.")

    startswith(stripped, "```") && begin
        lines = split(stripped, '\n')
        if length(lines) >= 3 && startswith(strip(lines[1]), "```") && strip(lines[end]) == "```"
            stripped = join(lines[2:end-1], "\n") |> strip
            startswith(lowercase(stripped), "json\n") && (stripped = strip(stripped[6:end]))
        end
    end

    try
        JSON.parse(stripped)
        return stripped
    catch
    end

    first_brace = findfirst(==('{'), stripped)
    last_brace = findlast(==('}'), stripped)
    if !isnothing(first_brace) && !isnothing(last_brace) && first_brace <= last_brace
        candidate = stripped[first_brace:last_brace]
        JSON.parse(candidate)
        return candidate
    end

    error("Could not extract a JSON object from the model response: $(repr(stripped))")
end

function _parse_generated_function_spec(
        client::AbstractGeneratedFunctionClient,
        raw_json::AbstractString,
    )::GeneratedFunctionSpec
    payload = JSON.parse(_extract_generated_json_text(raw_json))
    input_type_names = String.(payload["input_types"])
    input_types = DataType[]
    for name in input_type_names
        @assert haskey(client.input_type_aliases, name) "Unknown generated input type alias $(name)."
        push!(input_types, client.input_type_aliases[name])
    end
    output_type_name = String(payload["output_type"])
    @assert haskey(client.output_type_aliases, output_type_name) "Unknown generated output type alias $(output_type_name)."
    output_type = client.output_type_aliases[output_type_name]
    argument_names = Symbol.(String.(payload["argument_names"]))
    return GeneratedFunctionSpec(
        Symbol(payload["name"]),
        argument_names,
        input_types,
        output_type,
        String(payload["body"]);
        description = String(payload["description"]),
    )
end

function _render_repair_prompt(
        original_prompt::AbstractString,
        previous_spec::GeneratedFunctionSpec,
        report::GeneratedFunctionValidationReport,
    )::String
    io = IOBuffer()
    println(io, "Your previous candidate did not validate. Produce one corrected JSON object only.")
    println(io, "Do not repeat prior explanations. Fix the candidate using the validation feedback below.")
    println(io)
    println(io, "Exact rejection reason")
    if isempty(report.errors)
        println(io, "(no explicit errors were recorded)")
    else
        for err in report.errors
            println(io, "- ", err)
        end
    end
    if !isempty(report.stacktrace)
        println(io)
        println(io, "Stacktrace")
        println(io, report.stacktrace)
    end
    println(io)
    println(io, "Previous candidate")
    println(io, JSON.json(Dict(
        "name" => string(previous_spec.name),
        "argument_names" => string.(previous_spec.argument_names),
        "input_types" => string.(previous_spec.input_types),
        "output_type" => string(previous_spec.output_type),
        "body" => previous_spec.body,
        "description" => previous_spec.description,
    )))
    println(io)
    println(io, "Validation feedback")
    println(io, JSON.json(Dict(
        "accepted" => report.accepted,
        "compile_ok" => report.compile_ok,
        "arity_ok" => report.arity_ok,
        "input_types_ok" => report.input_types_ok,
        "output_type_ok" => report.output_type_ok,
        "dispatch_ok" => report.dispatch_ok,
        "runtime_ok" => report.runtime_ok,
        "mean_runtime_seconds" => report.mean_runtime_seconds,
        "errors" => report.errors,
        "stacktrace" => report.stacktrace,
    )))
    println(io)
    print(io, "Return one corrected JSON object only.")
    return String(take!(io))
end

"""
    generate_function_spec(client, prompt)

Ask one client for an initial candidate function.

Example: a mock client can return a fixed `GeneratedFunctionSpec` for tests.
"""
function generate_function_spec(
        ::AbstractGeneratedFunctionClient,
        ::AbstractString,
        ;
        encoded_images::Vector{String} = String[],
    )::GeneratedFunctionSpec
    throw(MethodError(generate_function_spec, (AbstractGeneratedFunctionClient, AbstractString)))
end

function generate_function_spec(
        client::LlamaCppGeneratedFunctionClient,
        prompt::AbstractString,
        ;
        encoded_images::Vector{String} = String[],
    )::GeneratedFunctionSpec
    response = _llama_cpp_chat!(client, prompt; encoded_images = encoded_images)
    return _parse_generated_function_spec(client, response)
end

function generate_function_spec(
        client::GeminiGeneratedFunctionClient,
        prompt::AbstractString,
        ;
        encoded_images::Vector{String} = String[],
    )::GeneratedFunctionSpec
    response = _gemini_chat!(
        client,
        prompt,
        _build_generated_function_spec_schema(client);
        encoded_images = encoded_images,
    )
    return _parse_generated_function_spec(client, response)
end

function generate_function_spec(
        client::OpenAICompatibleGeneratedFunctionClient,
        prompt::AbstractString,
        ;
        encoded_images::Vector{String} = String[],
    )::GeneratedFunctionSpec
    response = _openai_compatible_chat!(
        client,
        prompt,
        _build_generated_function_spec_schema(client);
        encoded_images = encoded_images,
    )
    return _parse_generated_function_spec(client, response)
end

"""
    repair_function_spec(client, prompt, previous_spec, report)

Ask one client to repair a rejected candidate using the collected validation
feedback.

Example: a mock client can return a corrected body after one failing attempt.
"""
function repair_function_spec(
        ::AbstractGeneratedFunctionClient,
        ::AbstractString,
        ::GeneratedFunctionSpec,
        ::GeneratedFunctionValidationReport,
        ;
        encoded_images::Vector{String} = String[],
    )::GeneratedFunctionSpec
    throw(MethodError(repair_function_spec, (AbstractGeneratedFunctionClient, AbstractString, GeneratedFunctionSpec, GeneratedFunctionValidationReport)))
end

function repair_function_spec(
        client::LlamaCppGeneratedFunctionClient,
        prompt::AbstractString,
        previous_spec::GeneratedFunctionSpec,
        report::GeneratedFunctionValidationReport,
        ;
        encoded_images::Vector{String} = String[],
    )::GeneratedFunctionSpec
    # The original multimodal user turn is already present in client.messages.
    # Do not resend images on repair turns.
    response = _llama_cpp_chat!(client, _render_repair_prompt(prompt, previous_spec, report); encoded_images = String[])
    return _parse_generated_function_spec(client, response)
end

function repair_function_spec(
        client::GeminiGeneratedFunctionClient,
        prompt::AbstractString,
        previous_spec::GeneratedFunctionSpec,
        report::GeneratedFunctionValidationReport,
        ;
        encoded_images::Vector{String} = String[],
    )::GeneratedFunctionSpec
    response = _gemini_chat!(
        client,
        _render_repair_prompt(prompt, previous_spec, report),
        _build_generated_function_spec_schema(client);
        encoded_images = String[],
    )
    return _parse_generated_function_spec(client, response)
end

function repair_function_spec(
        client::OpenAICompatibleGeneratedFunctionClient,
        prompt::AbstractString,
        previous_spec::GeneratedFunctionSpec,
        report::GeneratedFunctionValidationReport,
        ;
        encoded_images::Vector{String} = String[],
    )::GeneratedFunctionSpec
    response = _openai_compatible_chat!(
        client,
        _render_repair_prompt(prompt, previous_spec, report),
        _build_generated_function_spec_schema(client);
        encoded_images = String[],
    )
    return _parse_generated_function_spec(client, response)
end

############################
# Source Rendering
############################

const GENERATED_FUNCTION_MODULE_COUNTER = Base.RefValue(0)

function _generated_module_name(name::Symbol)::Symbol
    GENERATED_FUNCTION_MODULE_COUNTER[] += 1
    return Symbol("GeneratedMAGEFn_", name, "_", GENERATED_FUNCTION_MODULE_COUNTER[])
end

function _indent_generated_body(body::AbstractString)::String
    return join(("    " * line for line in split(String(body), '\n')), "\n")
end

function _render_generated_kwarg_clause(keyword_bindings::AbstractDict{Symbol, Any})::String
    if isempty(keyword_bindings)
        return ""
    end
    # Example returned object:
    #   Dict(
    #       :image_values => generated_function_image_values,
    #       :fns_returning_intensity_img => GeneratedFunctionNamespace(...),
    #       :fns_returning_float => GeneratedFunctionNamespace(...),
    #   )
    # We only need the readable keyword names here because the generated source
    # will see them as namespace objects:
    #   function new_fn(x1::Img, args...; image_values, fns_returning_intensity_img, fns_returning_float)
    kw_names = sort!(collect(keys(keyword_bindings)); by = String)
    return "; " * join(string.(kw_names), ", ")
end

"""
    render_generated_function_source(spec, keyword_bindings = Dict())

Render the exact Julia source evaluated for one generated function. The
rendered signature uses typed arguments, trailing `args...`, and keyword names
for every callable binding exposed to the LLM. This lets generated code say
`sobelx_image2D(img)` even if the underlying MAGE wrapper stores an anonymous
callable in `fn_wrapper.fn`.

Example: `render_generated_function_source(spec, generated_function_bindings(ml, ma))`
"""
function render_generated_function_source(
        spec::GeneratedFunctionSpec,
        keyword_bindings::AbstractDict{Symbol, Any} = Dict{Symbol, Any}(),
    )::String
    typed_args = [
        string(arg_name, "::", repr(input_type)) for
            (arg_name, input_type) in zip(spec.argument_names, spec.input_types)
    ]
    args_txt = join(vcat(typed_args, ["args..."]), ", ")
    kwargs_txt = _render_generated_kwarg_clause(keyword_bindings)
    body_txt = _indent_generated_body(spec.body)
    return """
function $(spec.name)($(args_txt)$(kwargs_txt))::$(repr(spec.output_type))
$(body_txt)
end
"""
end

function _default_generated_description(
        spec::GeneratedFunctionSpec,
        keyword_bindings::AbstractDict{Symbol, Any},
    )::String
    clean = strip(spec.description)
    return isempty(clean) ? render_generated_function_source(spec, keyword_bindings) : clean
end

############################
# Binding Collection
############################

function generated_function_image_values(image_like)::AbstractArray
    return reinterpret(image_like.img)
end

function generated_function_image_values_float64(image_like)::Matrix{Float64}
    return Float64.(generated_function_image_values(image_like))
end

function _cast_generated_image_values_like(reference_image, raw_values::AbstractArray)
    image_pixel_wrapper_type = _get_image_pixel_type(reference_image)
    image_storage_type = _get_image_type(reference_image)

    if image_pixel_wrapper_type <: BinaryPixel
        return Bool.(raw_values .> 0.5)
    elseif image_pixel_wrapper_type <: SegmentPixel
        return round.(image_storage_type, raw_values)
    else
        return image_storage_type.(clamp.(raw_values, 0.0, 1.0))
    end
end

function generated_function_rewrap_like(reference_image, raw_values::AbstractArray)
    image_shape_type = _get_image_tuple_size(typeof(reference_image))
    image_pixel_wrapper_type = _get_image_pixel_type(reference_image)
    cast_values = _cast_generated_image_values_like(reference_image, raw_values)
    return SImageND(image_pixel_wrapper_type.(cast_values), image_shape_type)
end

function int_matrix_to_segmented_SImage2D(int_matrix::AbstractMatrix{<:Integer})
    return SImageND(SegmentPixel.(Int64.(int_matrix)))
end

function float_matrix_to_intensity_SImage2D(float_matrix::AbstractMatrix{<:Real})
    values = Float64.(float_matrix)
    if any(value -> !isfinite(value) || value < 0.0 || value > 1.0, values)
        throw(ArgumentError("float_matrix_to_intensity_SImage2D requires finite values in [0, 1]."))
    end
    return SImageND(IntensityPixel.(N0f8.(values)))
end

function bool_matrix_to_binary_SImage2D(bool_matrix::AbstractMatrix{Bool})
    return SImageND(BinaryPixel.(bool_matrix))
end

function _generated_function_builtin_bindings()::Dict{Symbol, Any}
    return Dict{Symbol, Any}(
        :image_values => generated_function_image_values,
        :image_values_float64 => generated_function_image_values_float64,
        :rewrap_like => generated_function_rewrap_like,
        :int_matrix_to_segmented_SImage2D => int_matrix_to_segmented_SImage2D,
        :float_matrix_to_intensity_SImage2D => float_matrix_to_intensity_SImage2D,
        :bool_matrix_to_binary_SImage2D => bool_matrix_to_binary_SImage2D,
    )
end

# TODO: these legacy names (intensity_img_fns, binary_img_fns, segment_img_fns,
# float_fns, int_fns) are kept only as aliases for older accepted LLM function
# manifests generated before the fns_returning_* naming convention. Once every
# accepted manifest in use has been regenerated/migrated to the canonical
# fns_returning_* names, remove this function and its call site entirely.
function _add_legacy_generated_function_aliases!(bindings::Dict{Symbol, Any})::Dict{Symbol, Any}
    alias_map = Dict{Symbol, Symbol}(
        :intensity_img_fns => :fns_returning_intensity_img,
        :binary_img_fns => :fns_returning_binary_img,
        :segment_img_fns => :fns_returning_segment_img,
        :float_fns => :fns_returning_float,
        :int_fns => :fns_returning_int,
    )
    for (alias_name, canonical_name) in alias_map
        haskey(bindings, alias_name) && continue
        haskey(bindings, canonical_name) || continue
        bindings[alias_name] = bindings[canonical_name]
    end
    return bindings
end

Base.propertynames(namespace::GeneratedFunctionNamespace; private::Bool = false) =
    collect(keys(namespace.callables))

function Base.getproperty(namespace::GeneratedFunctionNamespace, name::Symbol)
    if name === :name || name === :callables
        return getfield(namespace, name)
    end
    return get(namespace.callables, name) do
        throw(ErrorException("Unknown generated-function namespace binding $(name) inside $(namespace.name)."))
    end
end

function _generated_function_library_namespace_name(output_type::DataType, library_index::Int)::Symbol
    if output_type <: SizedImage
        image_pixel_wrapper_type = _get_image_pixel_type(output_type)
        if image_pixel_wrapper_type <: IntensityPixel
            return :fns_returning_intensity_img
        elseif image_pixel_wrapper_type <: BinaryPixel
            return :fns_returning_binary_img
        elseif image_pixel_wrapper_type <: SegmentPixel
            return :fns_returning_segment_img
        end
    elseif output_type <: Base.AbstractFloat
        return :fns_returning_float
    elseif output_type <: Integer
        return :fns_returning_int
    end
    return Symbol("library_", library_index, "_fns")
end

function _build_generated_function_namespace(
        namespace_name::Symbol,
        library::AbstractLibrary,
    )::GeneratedFunctionNamespace
    grouped_callables = Dict{Symbol, Vector{Any}}()
    for wrapper in library
        push!(get!(grouped_callables, wrapper.name, Any[]), wrapper.fn)
    end
    callables = Dict{Symbol, Any}()
    for (callable_name, callable_group) in grouped_callables
        if length(callable_group) == 1
            callables[callable_name] = only(callable_group)
        else
            callables[callable_name] = GeneratedFunctionNameDispatcher(callable_name, callable_group)
        end
    end
    return GeneratedFunctionNamespace(namespace_name, callables)
end

"""
    generated_function_bindings(library)

Collect the readable callable names that generated source may refer to. The
values are the underlying wrapper callables, not the wrappers themselves.

Returned object shape:
```julia
Dict(
    :add => add_wrapper.fn,
    :sobelx_image2D => sobel_wrapper.fn,
)
```

Example: `generated_function_bindings(lib)[:add] === lib[:add].fn`
"""
function generated_function_bindings(library::AbstractLibrary)::Dict{Symbol, Any}
    bindings = Dict{Symbol, Any}()
    for wrapper in library
        @assert !haskey(bindings, wrapper.name) "Duplicate generated-function binding $(wrapper.name) inside one library."
        bindings[wrapper.name] = wrapper.fn
    end
    return bindings
end

"""
    generated_function_bindings(meta_library, model_architecture)

Collect generated-function keyword bindings for one `MetaLibrary`. Built-in
image helpers stay flat, while per-library callables are exposed through
explicit namespace objects such as `fns_returning_intensity_img`, `fns_returning_int`, and `fns_returning_float`.

Example: use this dictionary when one generated function may compose existing
MAGE helpers without ambiguity across output libraries.
"""
function generated_function_bindings(
        meta_library::AbstractMetaLibrary,
        model_architecture::modelArchitecture,
    )::Dict{Symbol, Any}
    bindings = _generated_function_builtin_bindings()
    for (library_index, library) in enumerate(meta_library)
        output_type = model_architecture.chromosomes_types[library_index]
        namespace_name = _generated_function_library_namespace_name(output_type, library_index)
        @assert !haskey(bindings, namespace_name) "Duplicate generated-function namespace $(namespace_name) across the MetaLibrary."
        bindings[namespace_name] = _build_generated_function_namespace(namespace_name, library)
    end
    return _add_legacy_generated_function_aliases!(bindings)
end

############################
# Compilation
############################

"""
    (f::SourceBackedFunction)(inputs...)

Default call path -- always uses `Val{true}` (`Base.invokelatest`). See
`_call_runtime_fn`'s docstring for the compile-time `Val{true}`/`Val{false}`
choice and why `Val{false}` isn't wired up as the default anywhere yet.
"""
function (f::SourceBackedFunction)(inputs...)
    return _call_runtime_fn(f, Val(true), inputs...)
end

"""
    _call_runtime_fn(f, ::Val{UseInvokeLatest}, inputs...)

Compile-time choice (via `Val`, so each branch compiles to a direct call with
no runtime branch) between:
- `Val{true}`: `Base.invokelatest(f.runtime_fn, ...)` -- always correct,
  the current/default behavior.
- `Val{false}`: calls `f.runtime_fn(...)` directly, skipping `invokelatest`'s
  small remaining per-call overhead (~32 bytes/call measured -- most of the
  original per-call cost was `f.cached_kw_pairs`'s one-time construction,
  already fixed; this is what's left).

Whether `Val{false}` is safe wasn't obvious going in. A sequential,
single-threaded test (define fn1, call it, define fn2 afterward, call fn2
through the same already-compiled call-operator specialization without
invokelatest) succeeded -- each generated function lives in its own fresh
anonymous module, so `f.runtime_fn` is always a type Julia has never seen
before at this call site, not a new method bolted onto an existing generic
function some other caller already has a stale view of, which is the classic
scenario `invokelatest` guards against. A follow-up concurrency stress test
(24 functions, each validated once with `Val{true}`, then 20 million calls
across `Threads.nthreads()` threads using `Val{false}`) also passed clean: no
errors, no incorrect results. Neither test rules out a rarer race that only
manifests over a long real run under real allocation pressure -- so the two
call sites intentionally stay split by role rather than both switching to
`Val{false}`: `SourceBackedFunction`'s default call operator (used by
`validate_generated_function`'s load/validate call, `artifact.function_like(...)`)
keeps `Val{true}`, while the actual evaluation path (`_invoke_fn` in
`function.jl`, used by `call_fn_wrap`/`safe_call` during GA search) is wired
to `Val{false}` via a specialized `_invoke_fn(fn::SourceBackedFunction, ...)`
method below. If a future run's crash implicates this specifically, that's
the method to revert.
"""
function _call_runtime_fn(f::SourceBackedFunction, ::Val{true}, inputs...)
    # f.cached_kw_pairs is keyword_bindings pre-converted to keyword-argument
    # shape once at construction (see SourceBackedFunction's docstring), for example:
    #   Dict(:image_values => generated_function_image_values,
    #        :fns_returning_intensity_img => GeneratedFunctionNamespace(...))
    # becomes the keyword set:
    #   (; image_values = generated_function_image_values,
    #      fns_returning_intensity_img = GeneratedFunctionNamespace(...))
    #
    # The generated Julia function is then called as:
    #   runtime_fn(inputs...; image_values = ..., fns_returning_intensity_img = ...)
    # so the body can simply write:
    #   return fns_returning_intensity_img.sobelx_image2D(img)
    return Base.invokelatest(f.runtime_fn, inputs...; f.cached_kw_pairs...)
end

function _call_runtime_fn(f::SourceBackedFunction, ::Val{false}, inputs...)
    return f.runtime_fn(inputs...; f.cached_kw_pairs...)
end

"""
    _invoke_fn(fn::SourceBackedFunction, inputs...)

The evaluation-path specialization of `_invoke_fn` (generic fallback defined
in `function.jl`, called from `call_fn_wrap`/`safe_call`): routes through
`_call_runtime_fn`'s `Val{false}` (no `invokelatest`) branch rather than the
default call operator's `Val{true}` -- see `_call_runtime_fn`'s docstring for
why the evaluation path and the load/validate path are deliberately split.
"""
@inline _invoke_fn(fn::SourceBackedFunction, inputs...) = _call_runtime_fn(fn, Val(false), inputs...)

"""
    Base.which(f::SourceBackedFunction, t::Type{<:Tuple})

Delegate compatibility checks to the compiled inner Julia method. This keeps
mutation, decode, and runtime dispatch aligned on one source of truth.
"""
function Base.which(f::SourceBackedFunction, t::Type{<:Tuple})
    return which(f.runtime_fn, t)
end

function Base.which(f::SourceBackedFunction, t::Tuple)
    return which(f.runtime_fn, Tuple{t...})
end

"""
    Base.hasmethod(f::SourceBackedFunction, t::Type{<:Tuple})

Mirror the `which(...)`-based dispatch contract for generated functions.
"""
function Base.hasmethod(f::SourceBackedFunction, t::Type{<:Tuple})
    try
        which(f, t)
        return true
    catch
        return false
    end
end

function Base.hasmethod(f::SourceBackedFunction, t::Tuple)
    try
        which(f, t)
        return true
    catch
        return false
    end
end

"""
    compile_generated_function(spec; keyword_bindings = Dict())

Compile one generated-function spec into a callable `SourceBackedFunction`.
Callable names are supplied as Julia keyword arguments so the generated body can
refer to them directly using the wrapper names.

Example keyword map:
```julia
Dict(
    :add => add_wrapper.fn,
    :sobelx_image2D => sobel_wrapper.fn,
)
```

Example: `compile_generated_function(spec; keyword_bindings = generated_function_bindings(ml))`
"""
function compile_generated_function(
        spec::GeneratedFunctionSpec;
        keyword_bindings::AbstractDict{Symbol, Any} = Dict{Symbol, Any}(),
    )::GeneratedFunctionArtifact
    declared_argument_names = Set(spec.argument_names)
    for binding_name in keys(keyword_bindings)
        @assert !(binding_name in declared_argument_names) "Generated function argument $(binding_name) conflicts with one callable binding name."
        @assert binding_name != spec.name "Generated function name $(spec.name) conflicts with one callable binding name."
    end

    source = render_generated_function_source(spec, keyword_bindings)
    module_name = _generated_module_name(spec.name)
    module_ref = Module(module_name)
    # Generated source is evaluated in a fresh module, so it does not inherit
    # UTCGP type aliases / pixel names used in rendered signatures.
    Core.eval(module_ref, :(using UTCGP))
    Core.eval(module_ref, :(using Statistics))
    Core.eval(module_ref, :(using ImageCore: N0f8))
    for type_name in (
            :SImageND,
            :SImage2D,
            :SImage3D,
            :IntensityPixel,
            :BinaryPixel,
            :SegmentPixel,
        )
        Core.eval(module_ref, :(const $(type_name) = UTCGP.$(type_name)))
    end
    # The rendered source already declares keyword names such as:
    #   function my_fn(x1::Int, args...; add, sobelx_image2D)::Int
    # so include_string only needs to define the function. The actual callable
    # values are supplied later by SourceBackedFunction(...)(inputs...).
    Base.include_string(module_ref, source, string(module_name, ".jl"))
    runtime_fn = getfield(module_ref, spec.name)
    stored_keyword_bindings = Dict{Symbol, Any}(keyword_bindings)
    function_like = SourceBackedFunction(
        spec.name,
        source,
        copy(spec.argument_names),
        copy(spec.input_types),
        spec.output_type,
        runtime_fn,
        stored_keyword_bindings,
        (; (name => callable for (name, callable) in stored_keyword_bindings)...),
        module_name,
    )
    return GeneratedFunctionArtifact(
        spec,
        source,
        Dict{Symbol, Any}(keyword_bindings),
        module_name,
        function_like,
    )
end

############################
# Validation
############################

function _allowed_input_types(model_architecture::modelArchitecture)::Vector{DataType}
    return unique(vcat(
        DataType[model_architecture.inputs_types...],
        DataType[model_architecture.chromosomes_types...],
    ))
end

function _allowed_output_types(model_architecture::modelArchitecture)::Vector{DataType}
    return unique(DataType[model_architecture.chromosomes_types...])
end

function _adapt_validation_sample(
        sample::Tuple,
        requested_input_types::Vector{DataType},
    )::Union{Tuple, Nothing}
    selected_values = Any[]

    for requested_type in requested_input_types
        matched_index = findfirst(eachindex(sample)) do sample_index
            sample[sample_index] isa requested_type
        end
        isnothing(matched_index) && return nothing
        push!(selected_values, sample[matched_index])
    end

    return Tuple(selected_values)
end

function _collect_generated_function_spec_errors(
        spec::GeneratedFunctionSpec,
        model_architecture::modelArchitecture,
        node_config::nodeConfig,
    )::Tuple{Bool, Bool, Bool, Vector{String}}
    errors = String[]

    arity_ok = 1 <= length(spec.input_types) <= node_config.arity
    arity_ok || push!(errors, "Arity $(length(spec.input_types)) violates nodeConfig.arity=$(node_config.arity).")

    allowed_inputs = _allowed_input_types(model_architecture)
    input_types_ok = all(input_type -> input_type in allowed_inputs, spec.input_types)
    input_types_ok || push!(errors, "Input types $(spec.input_types) must come from the model architecture type space $(allowed_inputs).")

    allowed_outputs = _allowed_output_types(model_architecture)
    output_type_ok = spec.output_type in allowed_outputs
    output_type_ok || push!(errors, "Output type $(spec.output_type) must be one chromosome type from $(allowed_outputs).")

    return arity_ok, input_types_ok, output_type_ok, errors
end

function _report_compile_failure(
        arity_ok::Bool,
        input_types_ok::Bool,
        output_type_ok::Bool,
        errors::Vector{String},
        err,
    )::GeneratedFunctionValidationReport
    push!(errors, sprint(showerror, err))
    return GeneratedFunctionValidationReport(
        false,
        false,
        arity_ok,
        input_types_ok,
        output_type_ok,
        false,
        false,
        Inf,
        Any[],
        errors,
        sprint(showerror, err, catch_backtrace()),
    )
end

function _report_runtime_failure(
        arity_ok::Bool,
        input_types_ok::Bool,
        output_type_ok::Bool,
        dispatch_ok::Bool,
        errors::Vector{String},
        outputs::Vector{Any},
        runtimes::Vector{Float64},
        err,
    )::GeneratedFunctionValidationReport
    push!(errors, sprint(showerror, err))
    return GeneratedFunctionValidationReport(
        false,
        true,
        arity_ok,
        input_types_ok,
        output_type_ok,
        dispatch_ok,
        false,
        isempty(runtimes) ? Inf : mean(runtimes),
        outputs,
        errors,
        sprint(showerror, err, catch_backtrace()),
    )
end

function _validate_generated_function_dispatch!(
        errors::Vector{String},
        function_like::SourceBackedFunction,
        model_architecture::modelArchitecture,
    )::Bool
    dispatch_ok = true
    exact_tuple_type = Tuple{function_like.input_types...}

    @info "Generated-function dispatch debug" name = function_like.name input_types = function_like.input_types output_type = function_like.output_type
    @info "methods(runtime_fn)" methods = sprint(show, methods(function_like.runtime_fn))

    exact_method = try
        which(function_like, exact_tuple_type)
    catch err
        push!(errors, "Exact dispatch check failed: $(sprint(showerror, err))")
        return false
    end
    @info "which(runtime_fn, exact_tuple)" tuple_type = exact_tuple_type method = sprint(show, which(function_like.runtime_fn, exact_tuple_type))

    if exact_method.nargs != length(function_like.input_types) + 2
        dispatch_ok = false
        push!(errors, "Exact dispatch reported nargs=$(exact_method.nargs), expected $(length(function_like.input_types) + 2).")
    end

    extra_tuple_type = Tuple{vcat(function_like.input_types, model_architecture.chromosomes_types[1])...}
    extra_method = try
        which(function_like, extra_tuple_type)
    catch err
        push!(errors, "Extra-argument dispatch check failed: $(sprint(showerror, err))")
        return false
    end
    @info "which(runtime_fn, extra_tuple)" tuple_type = extra_tuple_type method = sprint(show, which(function_like.runtime_fn, extra_tuple_type))

    if extra_method.nargs != length(function_like.input_types) + 2
        dispatch_ok = false
        push!(errors, "Extra-argument dispatch reported nargs=$(extra_method.nargs), expected $(length(function_like.input_types) + 2).")
    end

    too_short_type = isempty(function_like.input_types) ? Tuple{} : Tuple{function_like.input_types[1:(end - 1)]...}
    short_failed = false
    short_result = nothing
    try
        short_result = which(function_like, too_short_type)
    catch err
        short_failed = true
        @info "which(runtime_fn, too_short_tuple)" tuple_type = too_short_type error = sprint(showerror, err)
    end
    short_failed || @info("which(runtime_fn, too_short_tuple)", tuple_type = too_short_type, method = sprint(show, short_result))
    if !short_failed
        dispatch_ok = false
        push!(errors, "Too-short dispatch check unexpectedly succeeded for tuple $(too_short_type).")
    end

    allowed_inputs = _allowed_input_types(model_architecture)
    wrong_type = findfirst(t -> !(t <: function_like.input_types[1]), allowed_inputs)
    if !isnothing(wrong_type)
        wrong_tuple_type = Tuple{vcat([allowed_inputs[wrong_type]], function_like.input_types[2:end])...}
        wrong_failed = false
        wrong_result = nothing
        try
            wrong_result = which(function_like, wrong_tuple_type)
        catch err
            wrong_failed = true
            @info "which(runtime_fn, wrong_tuple)" tuple_type = wrong_tuple_type error = sprint(showerror, err)
        end
        wrong_failed || @info("which(runtime_fn, wrong_tuple)", tuple_type = wrong_tuple_type, method = sprint(show, wrong_result))
        if !wrong_failed
            dispatch_ok = false
            push!(errors, "Wrong-type dispatch check unexpectedly succeeded for tuple $(wrong_tuple_type).")
        end
    end

    return dispatch_ok
end

function _validate_generated_image_output_size!(
        errors::Vector{String},
        output,
        output_type::DataType,
    )::Nothing
    output_type <: SizedImage || return nothing
    output isa SizedImage || return nothing
    expected_shape_type = _get_image_tuple_size(output_type)
    expected_size = Tuple(expected_shape_type.parameters)
    observed_size = Tuple(size(output))
    if observed_size != expected_size
        push!(errors, "Image output size $(observed_size) does not match declared output size $(expected_size).")
    end
    return nothing
end

function _generated_function_output_summary_value(output)
    if output isa Number
        return Float64(output)
    elseif output isa SizedImage
        return mean(generated_function_image_values_float64(output))
    elseif output isa AbstractArray
        return mean(Float64.(output))
    end
    return nothing
end

function _validate_generated_function_pairwise_output_relation!(
        errors::Vector{String},
        outputs::Vector{Any},
        output_relation::Symbol,
    )::Nothing
    output_relation == :none && return nothing
    length(outputs) < 2 && begin
        push!(errors, "Pairwise output validation requires at least two validation samples.")
        return nothing
    end
    lhs = _generated_function_output_summary_value(outputs[1])
    rhs = _generated_function_output_summary_value(outputs[2])
    if lhs === nothing || rhs === nothing
        push!(errors, "Pairwise output validation could not derive comparable scalar summaries from the first two outputs.")
        return nothing
    end
    lhs_value = Float64(lhs)
    rhs_value = Float64(rhs)
    if output_relation == :first_greater_than_second
        lhs_value > rhs_value || push!(errors, "Pairwise output hypothesis expected the first validation output to be greater than the second, but got $(lhs_value) <= $(rhs_value).")
    elseif output_relation == :first_less_than_second
        lhs_value < rhs_value || push!(errors, "Pairwise output hypothesis expected the first validation output to be less than the second, but got $(lhs_value) >= $(rhs_value).")
    elseif output_relation == :first_different_from_second
        lhs_value != rhs_value || push!(errors, "Pairwise output hypothesis expected the first validation output to differ from the second, but both summaries were $(lhs_value).")
    else
        push!(errors, "Unknown pairwise output relation $(output_relation).")
    end
    return nothing
end

"""
    validate_generated_function(spec, model_architecture, node_config, samples;
                                keyword_bindings = Dict(), max_mean_runtime_seconds = 0.05)

Validate one generated function candidate against MAGE's declared search-space
constraints and runtime behavior.

Example: `validate_generated_function(spec, ma, nc, [(1, 2), (3, 4)])`
"""
function validate_generated_function(
        spec::GeneratedFunctionSpec,
        model_architecture::modelArchitecture,
        node_config::nodeConfig,
        samples::Vector{<:Tuple};
        keyword_bindings::AbstractDict{Symbol, Any} = Dict{Symbol, Any}(),
        max_mean_runtime_seconds::Float64 = 0.05,
        require_distinct_sample_outputs::Bool = false,
        pairwise_output_relation::Symbol = :none,
    )::Tuple{Union{Nothing, GeneratedFunctionArtifact}, GeneratedFunctionValidationReport}
    arity_ok, input_types_ok, output_type_ok, errors = _collect_generated_function_spec_errors(spec, model_architecture, node_config)
    if !(arity_ok && input_types_ok && output_type_ok)
        return nothing, GeneratedFunctionValidationReport(
            false,
            false,
            arity_ok,
            input_types_ok,
            output_type_ok,
            false,
            false,
            Inf,
            Any[],
            errors,
            "",
        )
    end

    artifact = try
        compile_generated_function(spec; keyword_bindings = keyword_bindings)
    catch err
        return nothing, _report_compile_failure(arity_ok, input_types_ok, output_type_ok, errors, err)
    end

    dispatch_ok = _validate_generated_function_dispatch!(errors, artifact.function_like, model_architecture)
    outputs = Any[]
    runtimes = Float64[]

    for sample in samples
        adapted_sample = _adapt_validation_sample(sample, spec.input_types)
        if isnothing(adapted_sample)
            push!(errors, "Could not build a validation sample for requested input types $(spec.input_types) from available sample types $(typeof.(collect(sample))).")
            continue
        end
        try
            # Warm up once before timing so the measured runtime does not include
            # first-call compilation latency.
            artifact.function_like(adapted_sample...)
            elapsed = @elapsed output = artifact.function_like(adapted_sample...)
            push!(runtimes, elapsed)
            push!(outputs, output)
            if !(output isa spec.output_type)
                push!(errors, "Sample $(adapted_sample) returned $(typeof(output)), expected $(spec.output_type).")
            else
                _validate_generated_image_output_size!(errors, output, spec.output_type)
            end
        catch err
            return artifact, _report_runtime_failure(
                arity_ok,
                input_types_ok,
                output_type_ok,
                dispatch_ok,
                errors,
                outputs,
                runtimes,
                err,
            )
        end
    end

    mean_runtime_seconds = isempty(runtimes) ? 0.0 : mean(runtimes)
    runtime_ok = mean_runtime_seconds <= max_mean_runtime_seconds
    runtime_ok || push!(errors, "Mean runtime $(mean_runtime_seconds)s exceeded max_mean_runtime_seconds=$(max_mean_runtime_seconds)s.")
    pairwise_output_relation != :none && _validate_generated_function_pairwise_output_relation!(errors, outputs, pairwise_output_relation)
    require_distinct_sample_outputs && pairwise_output_relation == :none && _validate_generated_function_pairwise_output_relation!(errors, outputs, :first_different_from_second)

    accepted = isempty(errors) && dispatch_ok && runtime_ok
    return artifact, GeneratedFunctionValidationReport(
        accepted,
        true,
        arity_ok,
        input_types_ok,
        output_type_ok,
        dispatch_ok,
        runtime_ok,
        mean_runtime_seconds,
        outputs,
        errors,
        "",
    )
end

############################
# Installation
############################

"""
    generated_function_library_index(model_architecture, output_type)

Resolve the library index corresponding to one generated function output type.

Example: if `output_type == Int`, this returns the index of the `Int` chromosome library.
"""
function generated_function_library_index(
        model_architecture::modelArchitecture,
        output_type::DataType,
    )::Int
    idx = findfirst(==(output_type), model_architecture.chromosomes_types)
    @assert !isnothing(idx) "Could not find output type $(output_type) inside modelArchitecture.chromosomes_types."
    return idx
end

function _assert_generated_function_name_available(
        meta_library::AbstractMetaLibrary,
        model_architecture::modelArchitecture,
        name::Symbol,
    )::Nothing
    @assert name ∉ keys(_generated_function_builtin_bindings()) "Generated function name $(name) collides with a built-in helper binding."
    visible_callables = generated_function_bindings(meta_library, model_architecture)
    @assert name ∉ keys(visible_callables) "Generated function name $(name) collides with a namespace binding."
    for library in meta_library
        for wrapper in library
            @assert wrapper.name != name "Generated function name $(name) already exists in the visible callable namespace."
        end
    end
    return nothing
end

function add_function_wrapper_to_library!(
        library::ModularLibrary,
        wrapper::FunctionWrapper,
    )::Int
    push!(library.library, wrapper)
    idx = length(library.library)
    library.name_to_index[wrapper.name] = idx
    return idx
end

function add_function_wrapper_to_library!(
        library::AbstractLibrary,
        wrapper::FunctionWrapper,
    )::Int
    push!(library.library, wrapper)
    return length(library.library)
end

"""
    install_generated_function!(meta_library, model_architecture, artifact; description = artifact.source)

Wrap and insert one validated generated function into the library that matches
its declared output type.

Example: `install_generated_function!(ml, ma, artifact)` returns `(library_idx, fn_idx, wrapper)`.
"""
function install_generated_function!(
        meta_library::AbstractMetaLibrary,
        model_architecture::modelArchitecture,
        artifact::GeneratedFunctionArtifact;
        description::AbstractString = artifact.spec.description,
)::Tuple{Int, Int, FunctionWrapper}
    _assert_generated_function_name_available(meta_library, model_architecture, artifact.spec.name)
    library_idx = generated_function_library_index(model_architecture, artifact.spec.output_type)
    library = meta_library[library_idx]
    @assert length(library) > 0 "Target library cannot be empty."
    fallback = library[1].fallback
    wrapper = FunctionWrapper(
        artifact.function_like,
        artifact.spec.name,
        nothing,
        fallback;
        description = description,
    )
    fn_idx = add_function_wrapper_to_library!(library, wrapper)
    return library_idx, fn_idx, wrapper
end

############################
# Context Rendering
############################

"""
    render_generated_function_context(model_architecture, node_config, meta_library)

Render a readable prompt context describing the legal generated-function search
space for one run.

Example: pass this text to an external LLM before asking it for candidate functions.
"""
function render_generated_function_context(
        model_architecture::modelArchitecture,
        node_config::nodeConfig,
        meta_library::AbstractMetaLibrary;
        include_function_tables::Bool = true,
    )::String
    context_buffer = IOBuffer()
    println(context_buffer, "Generated function constraints")
    println(context_buffer, "- max_arity = $(node_config.arity)")
    println(context_buffer, "- allowed_input_types = $(_allowed_input_types(model_architecture))")
    println(context_buffer, "- allowed_output_types = $(_allowed_output_types(model_architecture))")
    println(context_buffer)
    println(context_buffer, "Image type guidance")
    println(context_buffer, "- MAGE images are wrapped objects. The raw matrix lives in x1.img, x2.img, ...")
    println(context_buffer, "- Intensity images store IntensityPixel{N0f8}; N0f8 behaves like numbers in [0, 1].")
    println(context_buffer, "- Binary images store BinaryPixel{Bool}; their raw matrix is boolean.")
    println(context_buffer, "- Segment images store SegmentPixel{Int}; their raw matrix is integer-valued segment ids.")
    println(context_buffer, "- If you need a numeric matrix, prefer image_values(img) or image_values_float64(img).")
    println(context_buffer, "- image_values(img) returns the raw matrix with its natural scalar type.")
    println(context_buffer, "- image_values_float64(img) returns Float64.(image_values(img)).")
    println(context_buffer, "- If you create a new image matrix and need to wrap it back like a reference image, use rewrap_like(reference_img, new_matrix).")
    println(context_buffer, "- rewrap_like handles output casting for intensity, binary, and segmented images and preserves the reference image size/type wrapper.")
    println(context_buffer, "- Use namespaced library helpers such as fns_returning_intensity_img.some_function(...), fns_returning_binary_img.some_function(...), fns_returning_segment_img.some_function(...), fns_returning_int.some_function(...), or fns_returning_float.some_function(...).")
    if include_function_tables
        println(context_buffer)
        println(context_buffer, "Available functions")
        append_generated_function_library_tables!(context_buffer, model_architecture, meta_library)
    end
    return String(take!(context_buffer))
end

"""
    append_generated_function_library_tables!(io, model_architecture, meta_library)

Append one markdown table per library so the LLM can see which callable names
exist, what each library returns, and the short semantic description attached
to each wrapper.

Example: each row looks like `| sobelx_image2D | SImageND | Horizontal edge response |`.
"""
function append_generated_function_library_tables!(
        io::IO,
        model_architecture::modelArchitecture,
        meta_library::AbstractMetaLibrary,
    )::Nothing
    for (library_index, library) in enumerate(meta_library)
        library_output_type = model_architecture.chromosomes_types[library_index]
        namespace_name = _generated_function_library_namespace_name(library_output_type, library_index)
        println(io, "## Library $(library_index) ($(namespace_name))")
        println(io, "| Fn | Return Type | Description |")
        println(io, "| --- | --- | --- |")
        for wrapper in library
            single_line_description = replace(wrapper.description, '\n' => ' ')
            println(io, "| $(wrapper.name) | $(library_output_type) | $(single_line_description) |")
        end
        library_index < length(meta_library) && println(io)
    end
    return nothing
end

############################
# Iterative Synthesis
############################

"""
    synthesize_validated_function(client, prompt, model_architecture, node_config, samples;
                                  keyword_bindings = Dict(), max_attempts = 3, max_mean_runtime_seconds = 0.05)

Run a generate/repair loop against one client until one candidate validates or
the retry budget is exhausted.

Example: tests use a mock client that fails once and then returns a corrected candidate.
"""
function synthesize_validated_function(
        client::AbstractGeneratedFunctionClient,
        prompt::AbstractString,
        model_architecture::modelArchitecture,
        node_config::nodeConfig,
        samples::Vector{<:Tuple};
        keyword_bindings::AbstractDict{Symbol, Any} = Dict{Symbol, Any}(),
        encoded_images::Vector{String} = String[],
        max_attempts::Int = 3,
        max_mean_runtime_seconds::Float64 = 0.05,
        on_attempt::Union{Nothing, Function} = nothing,
    )::GeneratedFunctionSynthesisResult
    @assert max_attempts >= 1 "synthesis loop requires at least one attempt."

    attempts = GeneratedFunctionAttempt[]
    candidate_spec = generate_function_spec(client, prompt; encoded_images = encoded_images)

    for attempt_index in 1:max_attempts
        artifact, report = validate_generated_function(
            candidate_spec,
            model_architecture,
            node_config,
            samples;
            keyword_bindings = keyword_bindings,
            max_mean_runtime_seconds = max_mean_runtime_seconds,
        )
        attempt = GeneratedFunctionAttempt(candidate_spec, artifact, report)
        push!(attempts, attempt)
        if on_attempt !== nothing
            Base.invokelatest(on_attempt, attempt_index, attempt)
        end

        if report.accepted
            return GeneratedFunctionSynthesisResult(artifact, attempts)
        end

        if attempt_index < max_attempts
            try
                candidate_spec = repair_function_spec(client, prompt, candidate_spec, report; encoded_images = encoded_images)
            catch err
                error(
                    "Repair attempt failed after validation rejection. " *
                    "Validation errors=$(repr(report.errors)), " *
                    "compile_ok=$(report.compile_ok), dispatch_ok=$(report.dispatch_ok), " *
                    "runtime_ok=$(report.runtime_ok), stacktrace=$(repr(report.stacktrace)). " *
                    "Underlying repair error: $(sprint(showerror, err))"
                )
            end
        end
    end

    return GeneratedFunctionSynthesisResult(nothing, attempts)
end
