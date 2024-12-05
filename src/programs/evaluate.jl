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
)::Any where {T<:Type}
    calling_node = nothing
    @assert length(program) > 0
    @debug "Program Length $(length(program))"

    # @timeit_debug to "Eval Prog. slow" begin
    #     for (ith_operation, operation) in enumerate(program)
    #         fn, calling_node, inputs =
    #             (operation.fn, operation.calling_node, operation.inputs)
    #         if calling_node.value === nothing
    #             # Only calc if the node is nothing. If not it means that
    #             # the value was already computed. No need to recompute twice.
    #             inputs_values = []
    #             for operationInput in inputs
    #                 R_node = _extract_input_node_from_operationInput(
    #                     program.program_inputs,
    #                     operationInput,
    #                 )
    #                 node = @unwrap_or R_node throw(
    #                     ErrorException("Could not extract the input from operation."),
    #                 )
    #                 push!(inputs_values, get_node_value(node))
    #             end
    #             fname = fn.name
    #             @debug "Evaluating $fname"

    #             # if fname == :watershed_2D || fname == "watershed_2D"
    #             # @info "Watershed MI before" methodinstances(fn.fn)
    #             # @info "Watershed MI before" methodinstances(UTCGP.evaluate_fn_wrapper)
    #             # end

    #             # local allocs
    #             # local t
    #             # local res
    #             # c = IOCapture.capture() do
    #             #     @time allocs =
    #             #         @allocated t = @elapsed res = evaluate_fn_wrapper(fn, inputs_values)
    #             #     # allocs = @allocated t = @elapsed res = evaluate_fn_wrapper(fn, inputs_values)

    #             # end
    #             res = evaluate_fn_wrapper(fn, inputs_values)
    #             t = @elapsed set_node_value!(calling_node, res)

    #             # @info c.output
    #             # if fname == :watershed_2D || fname == "watershed_2D"
    #             #     # if isdefined(Main, :Infiltrator)
    #             #     #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    #             #     # end
    #             #     @info "$fname MI after:" methodinstances(fn.fn)
    #             #     @info "$fname Watershed MI after :" methodinstances(
    #             #         UTCGP.evaluate_fn_wrapper,
    #             #     )
    #             # end

    #             # mbs = allocs * 1e-6
    #             # @debug "Evaluation of $fname took $t time and $(mbs) allocs in MB"

    #             # if mbs > 100 # 9 mb
    #             #     n = now()
    #             #     @warn "Excessive Allocs for $fname with $(typeof.(inputs_values)) where $mbs MB. Time $t Seconds : $n. at $(Threads.threadid())"
    #             #     println(
    #             #         "Excessive Allocs for $fname with $(typeof.(inputs_values)) where $mbs MB. Time $t Seconds : $n. at $(Threads.threadid())",
    #             #     )
    #             #     # @show "Excessive $(fname) with $(typeof.(inputs_values)) $(mbs) at $(Threads.threadid())"
    #             # end
    #             # if mbs > 300
    #             #     # if isdefined(Main, :Infiltrator)
    #             #     #     Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    #             #     # end
    #             #     gct = @elapsed GC.gc(false)
    #             #     # @warn "Excessive Allocs for $fname where $mbs MB. Running GC. GC time : $gct"
    #             # end
    #             # if t > 0.5
    #             # @debug "$(fn.name) took $t seconds with inputs : $inputs_values. Types $(typeof.(inputs_values))"
    #             # @warn "$(fn.name) took $t seconds with inputs sizes : $(length.(inputs_values)). Types $(typeof.(inputs_values))"
    #             # println(
    #             #     "$(fn.name) took $t seconds with inputs sizes : $(length.(inputs_values)). Types $(typeof.(inputs_values))",
    #             # )
    #             # @show CONSTRAINED
    #             # GC.gc()
    #             # end

    #             # s = length.(inputs_values)
    #             # if length(s) >= 1 && s[1] > 1000
    #             #     @show length.(inputs_values)
    #             #     @show fn.name
    #             #     @show UTCGP.CONSTRAINED
    #             #     println(
    #             #         "$(fn.name) took $t seconds with inputs sizes : $(length.(inputs_values)). Types $(typeof.(inputs_values))",
    #             #     )
    #             #     @show CONSTRAINED
    #             #     GC.gc()
    #             #     if isdefined(Main, :Infiltrator)
    #             #         Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
    #             #     end
    #             #     println(size.(res))
    #             # end
    #             # println("Elapsed $t with fn : $(fn.name) with inputs : $inputs_values")
    #             # set_node_value!(calling_node, res)
    #         end
    #     end
    # end

    # @timeit_debug to "Eval Prog. slow" begin
    #     for (ith_operation, operation) in enumerate(program)
    #         fn, calling_node, inputs =
    #             (operation.fn, operation.calling_node, operation.inputs)
    #         if calling_node.value === nothing
    #             # Only calc if the node is nothing. If not it means that
    #             # the value was already computed. No need to recompute twice.
    #             @timeit_debug to "Extract inputs for eval" begin
    #                 inputs_values = []
    #                 for operationInput in inputs
    #                     R_node = _extract_input_node_from_operationInput(
    #                         program.program_inputs,
    #                         operationInput,
    #                     )
    #                     node = @unwrap_or R_node throw(
    #                         ErrorException("Could not extract the input from operation."),
    #                     )
    #                     push!(inputs_values, get_node_value(node))
    #                 end
    #             end
    #             fname = fn.name
    #             @debug "Evaluating $fname"
    #             @timeit_debug to "Calc res" res = evaluate_fn_wrapper(fn, inputs_values)
    #             @timeit_debug to "Calc set res" t =
    #                 @elapsed set_node_value!(calling_node, res)
    #         end
    #     end
    # end
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
    if calling_node.value === nothing
        @timeit_debug to "Extract inputs for eval" inputs_values =
            _extract_inputs_for_eval(inputs, program_inputs)

        fname = fn.name
        @debug "Evaluating $fname"

        @timeit_debug to "Calc res" res = evaluate_fn_wrapper(fn, inputs_values)
        # if isnothing(res)
        #     if isdefined(Main, :Infiltrator)
        #         Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
        #     end
        # end
        @timeit_debug to "Calc set res" t = @elapsed set_node_value!(calling_node, res)
    end
end

@inline function _extract_input_for_eval(input::OperationInput, program_inputs::SharedInput)
    R_node = _extract_input_node_from_operationInput(program_inputs, input)
    node = @unwrap_or R_node throw(
        ErrorException("Could not extract the input from operation."),
    )
    get_node_value(node)
end

@inline function _extract_inputs_for_eval(
    inputs::Vector{OperationInput},
    program_inputs::SharedInput,
)::Vector
    inputs_values =
        ntuple(i -> _extract_input_for_eval(inputs[i], program_inputs), length(inputs))
    collect(inputs_values)
end

function evaluate_individual_programs(
    individual_programs::IndividualPrograms,
    chromosomes_types::Vector{<:T},
    metalibrary::MetaLibrary,
)::Vector{<:Any} where {T<:Type}
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
    o
end

function evaluate_population_programs(
    population_programs::PopulationPrograms,
    model_architecture::modelArchitecture,
    metalibrary::MetaLibrary,
)#::Vector{Vector{<:Any}}
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
