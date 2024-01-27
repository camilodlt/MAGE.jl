
struct AIM_LossEpoch <: AbstractCallable
    run::Any
end

struct AIM_RepeatLastLossES <: AbstractCallable
    run::Any
end


function (aim_struct::AIM_LossEpoch)(
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
    l = convert(Float32, best_loss)
    aim_struct.run.track(l, name = "loss", step = generation)
end

function (aim_struct::AIM_RepeatLastLossES)(
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
    for i in collect(1:left)
        gen = i + generation
        println("Repeating Aim of last best loss for epoch : $gen")
        l = convert(Float32, best_loss)
        aim_struct.run.track(l, name = "loss", step = gen)
    end
end


struct Wandb_LossEpoch <: AbstractCallable
    wandb_log::Any
end

function (wandb_struct::Wandb_LossEpoch)(
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
    Wandb.log(wandb_struct.wandb_log, Dict("generation" => generation, "loss" => best_loss))
end

