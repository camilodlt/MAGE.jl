module LLM

import PythonCall
import UTCGP

"""
    PythonCallGeneratedFunctionClient

Concrete generated-function client scaffold loaded only when `PythonCall` is
available in the active environment. The struct stores only lightweight runtime
configuration so UTCGP's core remains independent from Python tooling.

Example: `UTCGP.make_llm_generated_function_client(model_name = "google/gemma-3-4b-it")`
returns one `PythonCallGeneratedFunctionClient` after this extension loads.
"""
struct PythonCallGeneratedFunctionClient <: UTCGP.AbstractGeneratedFunctionClient
    model_name::String
    system_prompt::String
    python_project::String
    max_new_tokens::Int
    temperature::Float64
end

"""
    UTCGP.make_llm_generated_function_client(; kwargs...)

Create one PythonCall-backed generated-function client configuration. This does
not load a model yet; it only establishes the extension-side object that future
runtime code will use.

Example: `UTCGP.make_llm_generated_function_client(model_name = "google/gemma-3-4b-it")`
"""
function UTCGP.make_llm_generated_function_client(;
        model_name::AbstractString,
        system_prompt::AbstractString = "",
        python_project::AbstractString = get(ENV, "PYTHON_JULIAPKG_PROJECT", ""),
        max_new_tokens::Integer = 512,
        temperature::Real = 0.0,
    )::PythonCallGeneratedFunctionClient
    return PythonCallGeneratedFunctionClient(
        String(model_name),
        String(system_prompt),
        String(python_project),
        Int(max_new_tokens),
        Float64(temperature),
    )
end

"""
    UTCGP.llm_generated_function_client_backend(client)

Return the readable backend identifier for one PythonCall-backed generated-function
client.

Example: `UTCGP.llm_generated_function_client_backend(client) == "pythoncall"`
"""
UTCGP.llm_generated_function_client_backend(::PythonCallGeneratedFunctionClient) = "pythoncall"

"""
    UTCGP.llm_generated_function_client_status(client)

Return one small status dictionary describing the extension-side client setup.
This is intentionally shallow for now: it exposes the configured project path and
sampling parameters without trying to initialize the Python runtime.

Example: `UTCGP.llm_generated_function_client_status(client)[:model_name]`
"""
function UTCGP.llm_generated_function_client_status(
        client::PythonCallGeneratedFunctionClient,
    )::Dict{Symbol, Any}
    return Dict(
        :backend => UTCGP.llm_generated_function_client_backend(client),
        :model_name => client.model_name,
        :python_project => client.python_project,
        :max_new_tokens => client.max_new_tokens,
        :temperature => client.temperature,
        :pythoncall_loaded => true,
    )
end

"""
    UTCGP.generate_function_spec(client, prompt)

Placeholder generation entrypoint for the PythonCall-backed extension. The real
runtime implementation will later live here, after the Python model stack and
prompt schema are wired.

Example: once implemented, this will return one `GeneratedFunctionSpec`.
"""
function UTCGP.generate_function_spec(
        ::PythonCallGeneratedFunctionClient,
        ::AbstractString,
    )::UTCGP.GeneratedFunctionSpec
    error("LLM extension scaffold loaded, but generate_function_spec is not implemented yet.")
end

"""
    UTCGP.repair_function_spec(client, prompt, previous_spec, report)

Placeholder repair entrypoint for the PythonCall-backed extension. The future
implementation will use the previous failed spec and validation report to ask the
local model for a corrected candidate.

Example: once implemented, this will return one repaired `GeneratedFunctionSpec`.
"""
function UTCGP.repair_function_spec(
        ::PythonCallGeneratedFunctionClient,
        ::AbstractString,
        ::UTCGP.GeneratedFunctionSpec,
        ::UTCGP.GeneratedFunctionValidationReport,
    )::UTCGP.GeneratedFunctionSpec
    error("LLM extension scaffold loaded, but repair_function_spec is not implemented yet.")
end

end
