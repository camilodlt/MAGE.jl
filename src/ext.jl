"""
    make_cma_nodes!(args...)

Turn part of a genome's constants into CMA-ES-optimised
[`ConstantNode`](@ref)s.

Stub: the real method is provided by the `MAGE_PYCMA` package extension. Load
`MAGE_PYCMA` (which bridges to Python's `cma`) before calling it, or this
errors.

See also [`get_cma_nodes`](@ref), [`mutate_cma!`](@ref).
"""
make_cma_nodes!(args...) = @error "Should load MAGE_PYCMA to be olverloaded"

"""
    get_cma_nodes(args...)

Return the CMA-ES-backed [`ConstantNode`](@ref)s of a genome.

Stub; requires the `MAGE_PYCMA` package extension. See
[`make_cma_nodes!`](@ref).
"""
get_cma_nodes(args...) = @error "Should load MAGE_PYCMA to be olverloaded"

"""
    mutate_cma!(args...)

Ask the CMA-ES optimiser for the next set of constant values and write them into
the genome's [`ConstantNode`](@ref)s.

This is the numerical half of the search: the graph structure evolves through
the usual mutation operators while the constants it uses are tuned by CMA-ES.

Stub; requires the `MAGE_PYCMA` package extension. See
[`make_cma_nodes!`](@ref).
"""
mutate_cma!(args...) = @error "Should load MAGE_PYCMA to be olverloaded"

"""
    llm_generated_function_client_backend(args...)

Return a readable backend name such as `\"ollama\"` for one generated-function
client.

Example: `llm_generated_function_client_backend(client)` may return `\"ollama\"`.
"""
llm_generated_function_client_backend(args...) = @error "No generated-function LLM backend is available for this client."

"""
    llm_generated_function_client_status(args...)

Extension hook returning one small status summary for a concrete generated-function
client. This keeps runtime-specific readiness checks out of UTCGP's core.

Example: an Ollama-backed client may report its model name and local host.
"""
llm_generated_function_client_status(args...) = @error "No generated-function LLM backend is available for this client."

export make_cma_nodes!, get_cma_nodes, mutate_cma!
export llm_generated_function_client_backend, llm_generated_function_client_status
