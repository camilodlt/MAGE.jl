ENV["JULIA_CONDAPKG_OFFLINE"] = "true"
ENV["JULIA_PYTHONCALL_EXE"] = "/home/irit/miniconda3/envs/pmlb/bin/python"

using Revise
using Random
using UTCGP
import DataFrames: DataFrame, nrow
using Pkg
using PythonCall
using MLJ

Random.seed!(1);
# println("The random seed is : $(seed_)")

# Pkg.build("PythonCall")
# using Logging
# using Dates: now
# import DataStructures: OrderedDict
# using UUIDs
# import DBInterface
# using CSV

# DATASET NAMES
pmlb = PythonCall.pyimport("pmlb")
dataset = pmlb.regression_dataset_names[1]
dataset = pyconvert(String, dataset)

X, y = pmlb.fetch_data(dataset, return_X_y = true, local_cache_dir = "datasets")
X = pyconvert(Array, X);
y = pyconvert(Array, y)

(Xtrain, Xval, Xtest), (ytrain, yval, ytest) =
    partition((X, y), 0.7, 0.15; shuffle = true, rng = 123, multi = true)

println("Length Train, val, test : $(length(Xtrain)), $(length(Xval)), $(length(Xval))")

###########
# LOSS FN #
###########
struct EndpointMAE <: UTCGP.BatchEndpoint
    fitness_results::Vector{Float64}
    function EndpointMAE(preds::Vector{<:Vector{<:Number}}, y::Number)
        res = Float64[]
        for ind_outputs in preds
            pred = ind_outputs[1]
            if isnan(pred)
                abs_diff = 2
            else
                abs_diff = convert(Float64, abs(pred - y))
            end
            if isnan(abs_diff)
                if isdefined(Main, :Infiltrator)
                    Main.infiltrate(@__MODULE__, Base.@locals, @__FILE__, @__LINE__)
                end
            end
            push!(res, abs_diff)
        end
        return new(res)
    end
end
endpoint = EndpointMAE

eval_stopper = eval_budget_early_stop(10_000)
main_dir = dirname(@__DIR__)

# TRAIN DATA --- ---- 
X_for_fitting = []
Y_for_fitting = []
for i in axes(Xtrain, 1)
    push!(X_for_fitting, Any[Xtrain[i, :]..., 1.0, 0.0, -1.0, 2.0])
    push!(Y_for_fitting, ytrain[i])
end

# TEST DATA --- ---- 
X_for_fitting_val = []
Y_for_fitting_val = []
for i in axes(Xval, 1)
    push!(X_for_fitting_val, Any[Xval[i, :]..., 1.0, 0.0, -1.0, 2.0])
    push!(Y_for_fitting_val, yval[i])
end

run_conf = runConf(10, 100, 1.1, 0.1)

# Bundles Integer
float_bundles = UTCGP.get_sr_float_bundles()

# Libraries
lib_float = Library(float_bundles)

# MetaLibrary
ml = MetaLibrary([lib_float])

### Model Architecture ###
n_inputs = length(X_for_fitting[1])
model_arch = modelArchitecture(
    [Float64 for _ = 1:n_inputs],
    [1 for _ = 1:n_inputs],
    [Float64],
    [Float64],
    [1],
)

### Node Config ###
N_nodes = 40
println("N Nodes : $N_nodes")
node_config = nodeConfig(N_nodes, 1, 2, n_inputs)

### Make UT GENOME ###
shared_inputs, ut_genome = make_evolvable_utgenome(model_arch, ml, node_config)
initialize_genome!(ut_genome)
correct_all_nodes!(ut_genome, model_arch, ml, shared_inputs)
set_node_element_value!(
    ut_genome.output_nodes[1][2],
    ut_genome.output_nodes[1][2].highest_bound,
)
set_node_freeze_state(ut_genome.output_nodes[1][2])


mutable struct CustomTracker <: UTCGP.AbstractCallable
    test_losses::Union{Nothing,Vector}
    best_ind::Union{UTGenome,Nothing}
    best_loss::Float64
    X::Any
    y::Any
end
val_tracker = CustomTracker([], nothing, Inf, X_for_fitting_val, Y_for_fitting_val)

function (ct::CustomTracker)(
    ind_performances,
    population,
    iteration,
    run_config,
    model_architecture,
    node_config,
    meta_library,
    shared_inputs,
    population_programs,
    best_loss,
    best_program,
    elite_idx,
    batch,
)
    # Calc val loss of best
    losses = Vector{Float64}(undef, length(ct.y))
    i = 1
    for (gt_x, gt_y) in zip(ct.X, ct.y)
        UTCGP.reset_programs!(best_program)
        input_nodes = [
            InputNode(value, pos, pos, model_architecture.inputs_types_idx[pos]) for
            (pos, value) in enumerate(gt_x)
        ]
        replace_shared_inputs!(best_program, input_nodes)
        outputs = UTCGP.evaluate_individual_programs(
            best_program,
            model_arch.chromosomes_types,
            meta_library,
        )
        output = outputs[1]
        if isnan(output)
            output = 0.0
        end
        losses[i] = abs(output - gt_y[1])
        i += 1
    end
    @show std(losses)
    UTCGP.reset_programs!(best_program)
    loss = mean(losses)
    push!(ct.test_losses, loss)
    if loss <= ct.best_loss
        # we have a new best
        ct.best_ind = population[elite_idx]
    end
    ct.best_loss = minimum(ct.test_losses)
    @info "VAL LOSS : $(ct.best_loss)"
end

best_genome, best_program, _ = UTCGP.fit(
    X_for_fitting,  # multi input
    Y_for_fitting,
    shared_inputs,
    ut_genome,
    model_arch,
    node_config,
    run_conf,
    ml,
    # Callbacks before training
    nothing,
    # Callbacks before step
    (:default_population_callback,),
    (:default_numbered_new_material_mutation_callback,), #[:default_numbered_mutation_callback],
    (:default_ouptut_mutation_callback,),
    (:default_decoding_callback,), #[:default_free_decoding_callback], #[:default_decoding_callback],
    # Endpoints
    endpoint,
    # STEP CALLBACK
    nothing,
    # Callbacks after step
    (:default_elite_selection_callback,),
    # Epoch Callback
    (val_tracker,),
    # Final callbacks ?
    (:default_early_stop_callback, eval_stopper), # 
    nothing,
    #repeat_metric_tracker # .. 
)

