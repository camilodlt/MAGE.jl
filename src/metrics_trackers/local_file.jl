using DataStructures: OrderedDict
using JSON

struct jsonTracker <: AbstractCallable
    run::Dict
    file::IOStream
    train_metrics::OrderedDict
    test_metrics::OrderedDict
    function jsonTracker(run::Dict, file::IOStream)
        return new(run, file, OrderedDict(), OrderedDict())
    end
end

struct jsonTestTracker <: AbstractCallable
    tracker::jsonTracker
    endpoint_callback::Type{<:BatchEndpoint}
    x_test::Any
    y_test::Any
end

struct repeatJsonTracker <: AbstractCallable
    tracker::jsonTracker
end

function (json_tracker::jsonTracker)(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    programs::PopulationPrograms,
    best_loss::Float64,
    best_program::IndividualPrograms,
    elite_idx::Int,
)
    l = convert(Float32, best_loss)
    json_tracker.train_metrics[generation] = l
    s = Dict("data" => "train", "iteration" => generation, "loss" => l)
    write(json_tracker.file, JSON.json(s), "\n")
end

function (json_test_tracker::jsonTestTracker)(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    shared_inputs::SharedInput,
    programs::PopulationPrograms,
    best_loss::Float64,
    best_program::IndividualPrograms,
    elite_idx::Int,
)
    M_individual_loss_tracker = IndividualLossTracker()
    for ith_x = 1:length(json_test_tracker.x_test)
        # unpack input nodes
        x, y = json_test_tracker.x_test[ith_x], json_test_tracker.y_test[ith_x]
        input_nodes = [
            InputNode(value, pos, pos, model_architecture.inputs_types_idx[pos]) for
            (pos, value) in enumerate(x)
        ]
        # append input nodes to pop
        replace_shared_inputs!(shared_inputs, input_nodes) # update 
        outputs = evaluate_individual_programs(
            best_program,
            model_architecture.chromosomes_types,
            meta_library,
        )
        # Endpoint results
        fitness = json_test_tracker.endpoint_callback([outputs], y) # batch of 1 ind
        fitness_values = get_endpoint_results(fitness)
        add_pop_loss_to_ind_tracker!(M_individual_loss_tracker, fitness_values)  # appends the loss for the ith x sample to the
        reset_genome!(population[elite_idx])
    end
    [reset_genome!(g) for g in population]
    ind_performances = resolve_ind_loss_tracker(M_individual_loss_tracker)
    json_test_tracker.tracker.test_metrics[generation] = ind_performances
    @warn "Test Fitness : $ind_performances"
    s = Dict("data" => "test", "iteration" => generation, "loss" => ind_performances)
    write(json_test_tracker.tracker.file, JSON.json(s), "\n")
end

function (json_tracker::repeatJsonTracker)(
    ind_performances::Union{Vector{<:Number},Vector{Vector{<:Number}}},
    population::Population,
    generation::Int,
    run_config::runConf,
    model_architecture::modelArchitecture,
    node_config::nodeConfig,
    meta_library::MetaLibrary,
    programs::PopulationPrograms,
    best_loss::Float64,
    best_program::IndividualPrograms,
    elite_idx::Int,
)
    total_gens = run_config.generations
    left = total_gens - generation
    last_loss = best_loss
    last_test_metric = json_tracker.tracker.test_metrics[generation]
    for i in collect(1:left)
        gen = i + generation
        println("Repeating metric of last best loss for epoch : $gen")
        l = convert(Float32, last_loss)
        json_tracker.tracker.train_metrics[gen] = l
        json_tracker.tracker.test_metrics[gen] = last_test_metric
        s_train = Dict("data" => "train", "iteration" => gen, "loss" => l)
        s_test = Dict("data" => "test", "iteration" => gen, "loss" => last_test_metric)
        write(json_tracker.tracker.file, JSON.json(s_train), "\n")
        write(json_tracker.tracker.file, JSON.json(s_test), "\n")
    end
end

function save_json_tracker(tracker::jsonTracker)
    s = Dict("params" => tracker.run)
    write(tracker.file, JSON.json(s))
end
