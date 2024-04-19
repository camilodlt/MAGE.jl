# -*- coding::utf-8 -*-
using Debugger
import ThreadPools

MAXTIME = parse(Float64, get(ENV, "UTCGP_MAXTIME", "0.5"))

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
    chromosomes_types::Vector{<:DataType},
    metalibrary::MetaLibrary,
)::Any
    calling_node = nothing
    @assert length(program) > 0
    @info "Program Length $(length(program))"
    for (ith_operation, operation) in enumerate(program)
        fn, calling_node, inputs = (operation.fn, operation.calling_node, operation.inputs)
        if calling_node.value === nothing
            # Only calc if the node is nothing. If not it means that
            # the value was already computed. No need to recompute twice.
            inputs_values = []
            for operationInput in inputs
                node = extract_input_node_from_operationInput(operationInput)
                push!(inputs_values, get_node_value(node))
            end
            # println("Going to calculate : $(fn.name)")
            t = @elapsed res = evaluate_fn_wrapper(fn, inputs_values)
            if t > 0.1
                @warn "$(fn.name) took $t seconds with inputs sizes : $(length.(inputs_values)). Types $(typeof.(inputs_values))"
                println(
                    "$(fn.name) took $t seconds with inputs sizes : $(length.(inputs_values)). Types $(typeof.(inputs_values))",
                )
                @show CONSTRAINED
                GC.gc()
                if isdefined(Main, :Infiltrator)
                    Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
                end
            end
            s = length.(inputs_values)
            if length(s[1]) >= 1 && s[1][1] > 1000
                @show length.(inputs_values)
                @show fn.name
                @show UTCGP.CONSTRAINED
                println(
                    "$(fn.name) took $t seconds with inputs sizes : $(length.(inputs_values)). Types $(typeof.(inputs_values))",
                )
                @show CONSTRAINED
                GC.gc()
                if isdefined(Main, :Infiltrator)
                    Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
                end
                println(size.(res))
            end
            # println("Elapsed $t with fn : $(fn.name) with inputs : $inputs_values")
            set_node_value!(calling_node, res)
        end
    end
    @assert calling_node isa OutputNode "Last node is not Output Node?"
    return calling_node.value
end

function evaluate_individual_programs(
    individual_programs::IndividualPrograms,
    chromosomes_types::Vector{<:DataType},
    metalibrary::MetaLibrary,
)::Vector{<:Any}
    # @bp
    outputs = []
    for (ith_program, program) in enumerate(individual_programs)
        output = evaluate_program(program, chromosomes_types, metalibrary)
        push!(outputs, output)
    end
    return identity.(outputs)
end

function evaluate_population_programs(
    population_programs::PopulationPrograms,
    model_architecture::modelArchitecture,
    metalibrary::MetaLibrary,
)#::Vector{Vector{<:Any}}
    n_individuals = length(population_programs)
    @assert n_individuals > 0 "No individuals to evaluate"
    pop_outputs = []
    for (ith_individual, individual_programs) in enumerate(population_programs)
        @info "Evaluating individal $ith_individual"
        push!(
            pop_outputs,
            evaluate_individual_programs(
                individual_programs,
                model_architecture.chromosomes_types,
                metalibrary,
            ),
        )
    end
    # Specify the types 
    for i in eachindex(pop_outputs)
        pop_outputs[i] = identity.(pop_outputs[i])
    end
    pop_outputs = identity.(pop_outputs)
    return pop_outputs
end
