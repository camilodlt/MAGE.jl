# -*- coding::utf-8 -*-
using Debugger
import ThreadPools
using MethodAnalysis
using IOCapture

# MAXTIME = parse(Float64, get(ENV, "UTCGP_MAXTIME", "0.5"))

"""
    @timeout(seconds, expr_to_run, expr_when_fails)

Simple macro to run an expression with a timeout of `seconds`. If the `expr_to_run` fails to finish in `seconds` seconds, `expr_when_fails` is returned.

# Example
```julia
x = @timeout 1 begin
    sleep(1.1)
    println("done")
    1
end "failed"

```
"""
# macro timeoutm(seconds, expr_to_run, expr_when_fails)
#     quote
#         #tsk = @task $(esc(expr_to_run))
#         #schedule(tsk)
#         # tsk = Threads.@spawn $(esc(expr_to_run))
#         # println("$(Threads.threadid(tsk))")
#         UTCGP_RESULT = []
#         tsk = @async Threads.@threads for i = 1:1
#             # tsk = @async ThreadPools.@bthreads for i = 1:1
#             r = $(esc(expr_to_run))
#             # print(r)
#             push!(UTCGP_RESULT, r)
#         end
#         # print(UTCGP_RESULT)
#         id = Threads.threadid(tsk)
#         # println("$(Threads.threadid(tsk))")

#         t = Timer($(esc(seconds))) do timer
#             try

#                 # print(UTCGP_RESULT)
#                 new_id = Threads.threadid(tsk)
#                 if new_id != id
#                     @error "TASK DO NOT HAVE THE SAME ID"
#                 end
#                 # istaskdone(tsk) || schedule(tsk, ErrorException("stop"), error = true) # Base.throwto(tsk, InterruptException())
#                 # schedule(stop, :stop, error = true)
#                 istaskdone(tsk) || Base.throwto(tsk, InterruptException())
#                 GC.gc()
#             catch e
#                 @info e
#             end
#         end
#         try
#             # println("Fetch")
#             # r = fetch(tsk)
#             # close(t)
#             # print(r)
#             fetch(tsk)
#             UTCGP_RESULT[1]

#         catch
#             # println("Fails")
#             $(esc(expr_when_fails))
#             # close(t)
#             # r
#             # nothing
#         end
#     end
# end
# macro timeout_working(seconds, expr_to_run, expr_when_fails)
#     quote
#         UTCGP_RESULT = []
#         tsk = @async ThreadPools.@bthreads for i = 1:1
#             r = $(esc(expr_to_run))
#             # print(r)
#             push!(UTCGP_RESULT, r)
#         end
#         id = Threads.threadid(tsk)
#         t = Timer($(esc(seconds))) do timer
#             try
#                 new_id = Threads.threadid(tsk)
#                 if new_id != id
#                     @error "TASK DO NOT HAVE THE SAME ID"
#                 end
#                 istaskdone(tsk) || Base.throwto(tsk, InterruptException())
#                 GC.gc()
#             catch e
#                 @info e
#             end
#         end
#         try
#             fetch(tsk)
#             UTCGP_RESULT[1]
#         catch
#             $(esc(expr_when_fails))
#         end
#     end
# end

# function timeout(seconds, expr_ok, expr_bad)
#     UTCGP_RESULT = []
#     tsk = @async ThreadPools.@bthreads for i = 1:1
#         @info "Spawning task to worker"
#         r = expr_ok()
#         push!(UTCGP_RESULT, r)
#     end
#     id = Threads.threadid(tsk)
#     @info "Task has id $id"
#     t = Timer(seconds) do timer
#         @info "Time is up"
#         try
#             new_id = Threads.threadid(tsk)
#             if new_id != id
#                 @error "TASK DO NOT HAVE THE SAME ID"
#             end
#             @info "Killing task"
#             istaskdone(tsk) || Base.throwto(tsk, InterruptException())
#             @info "Task killed"
#             #GC.gc()
#             #@warn "GC"
#         catch e
#             @info e
#         end
#     end
#     try
#         #@warn "Fetching data"
#         fetch(tsk)
#         @info "Task is fetched"
#         close(t)
#         return UTCGP_RESULT[1]
#     catch
#         @info "Giving bad return"
#         close(t)
#         return expr_bad()
#     end
# end

# function timeout2(seconds, expr_ok, expr_bad)
#     UTCGP_RESULT = []
#     # tsk = ThreadPools.@tspawnat 2 begin
#     #     @info "Spawning task to worker"
#     #     push!(UTCGP_RESULT, expr_ok())
#     # end
#     tsk = @async ThreadPools.@bthreads for i = 1:1
#         push!(UTCGP_RESULT, expr_ok())
#     end

#     id = Threads.threadid(tsk)
#     @info "Task has id $id"
#     t = Timer(seconds) do timer
#         @info "Time is up"
#         try
#             new_id = Threads.threadid(tsk)
#             if new_id != id
#                 @error "TASK DO NOT HAVE THE SAME ID"
#             end
#             @info "Killing task"
#             istaskdone(tsk) || schedule(tsk, InterruptException(), error = true)
#             @info "Task killed"
#             #GC.gc()
#             #@warn "GC"
#         catch e
#             @info e
#         end
#     end
#     try
#         #@warn "Fetching data"
#         wait(tsk)
#         @info "Task is fetched"
#         close(t)
#         return UTCGP_RESULT[1]
#     catch
#         @info "Giving bad return"
#         if !istaskfailed(tsk)
#             schedule(tsk, InterruptException(), error = true)
#         end
#         close(t)
#         return expr_bad()
#     end
# end


function evaluate_program(
        program::Program,
        chromosomes_types::Vector{<:T},
        metalibrary::MetaLibrary,
    )::Any where {T <: Type}
    calling_node = nothing
    @assert length(program) > 0
    @debug "Program Length $(length(program))"

    @timeit_debug to "Eval Prog. loop" begin
        # _run_op.(program, Ref(program.program_inputs))
        si = program.program_inputs
        for operation in program
            _run_op(operation, si)
        end
        calling_node = program.program[end].calling_node
    end

    @assert calling_node isa OutputNode "Last node is not Output Node?"
    return get_node_value(calling_node)
end

function _run_op(::AbstractOperation, ::SharedInput)
    throw("NOT IMPLEMENTED")
end

function _run_op(operation::Operation, program_inputs::SharedInput)
    # operation = program[idx_op]
    fn, calling_node, inputs = (operation.fn, operation.calling_node, operation.inputs)
    return if calling_node.value === nothing
        @timeit_debug to "Extract inputs for eval" inputs_values =
            _extract_inputs_for_eval(inputs, program_inputs)

        fname = fn.name
        @debug "Evaluating $fname"

        # if inputs_values == [Any[]]
        # if isdefined(Main, :Infiltrator)
        # Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        # end
        # end
        @timeit_debug to "Calc res" res = evaluate_fn_wrapper(fn, inputs_values)

        if res != "" && eltype(res) != String && eltype(res) != Int && res isa Vector
            if isdefined(Main, :Infiltrator)
                Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
            end
        end

        @timeit_debug to "Calc set res" t = @elapsed set_node_value!(calling_node, res)
    end
end

@inline function _extract_input_for_eval(input::OperationInput, program_inputs::SharedInput)
    R_node = _extract_input_node_from_operationInput(program_inputs, input)
    node = @unwrap_or R_node throw(
        ErrorException("Could not extract the input from operation."),
    )
    return get_node_value(node)
end

@inline function _extract_inputs_for_eval(
        inputs::Vector{OperationInput},
        program_inputs::SharedInput,
    )::Vector
    inputs_values =
        ntuple(i -> _extract_input_for_eval(inputs[i], program_inputs), length(inputs))
    return collect(inputs_values)
end

function evaluate_individual_programs(
        individual_programs::IndividualPrograms,
        chromosomes_types::Vector{<:T},
        metalibrary::MetaLibrary,
    )::Vector{<:Any} where {T <: Type}
    # slow
    # @timeit_debug to "eval_ind_progs. slow" begin
    #     outputs = []
    #     for (ith_program, program) in enumerate(individual_programs)
    #         output = evaluate_program(program, chromosomes_types, metalibrary)
    #         push!(outputs, output)
    #     end
    #     outputs = identity.(outputs)
    # end
    @timeit_debug to "eval_ind_progs. eval each prog" @inbounds begin
        outs = ntuple(
            i -> evaluate_program(individual_programs[i], chromosomes_types, metalibrary),
            length(individual_programs.programs),
        )
        ind_outputs = collect(outs)
    end
    return ind_outputs
end

function eval_and_reset(
        idx_ind::Int,
        population_programs::PopulationPrograms,
        model_architecture::modelArchitecture,
        metalibrary::MetaLibrary,
    )
    ind_p = population_programs[idx_ind]
    o = evaluate_individual_programs(
        ind_p,
        model_architecture.chromosomes_types,
        metalibrary,
    )
    reset_programs!(ind_p)
    return o
end
function eval_and_reset_with_time(
        idx_ind::Int,
        population_programs::PopulationPrograms,
        model_architecture::modelArchitecture,
        metalibrary::MetaLibrary,
    )
    ind_p = population_programs[idx_ind]
    t = @elapsed o = evaluate_individual_programs(
        ind_p,
        model_architecture.chromosomes_types,
        metalibrary,
    )
    reset_programs!(ind_p)
    return (o, t)
end

function evaluate_population_programs(
        population_programs::PopulationPrograms,
        model_architecture::modelArchitecture,
        metalibrary::MetaLibrary,
    )
    n_individuals = length(population_programs)
    @assert n_individuals > 0 "No individuals to evaluate"
    @timeit_debug to "evaluate_population_programs. Eval inds Tuple" begin
        os = ntuple(
            i ->
            eval_and_reset(i, population_programs, model_architecture, metalibrary),
            length(population_programs),
        )
        pop_outputs = collect(os)
        UTCGP.reset_programs!(population_programs)
    end
    return pop_outputs
end

function evaluate_population_programs_with_time(
        population_programs::PopulationPrograms,
        model_architecture::modelArchitecture,
        metalibrary::MetaLibrary,
    )
    n_individuals = length(population_programs)
    @assert n_individuals > 0 "No individuals to evaluate"
    @timeit_debug to "evaluate_population_programs. Eval inds Tuple" begin
        os = ntuple(
            i -> eval_and_reset_with_time(
                i,
                population_programs,
                model_architecture,
                metalibrary,
            ),
            length(population_programs),
        )
        pop_outputs = collect(os)
        UTCGP.reset_programs!(population_programs)
    end
    return collect(ntuple(i -> os[i][1], n_individuals)),
        collect(ntuple(i -> os[i][2], n_individuals))


end
