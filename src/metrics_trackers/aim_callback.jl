
struct AIM_LossEpoch <: AbstractCallable
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
    aim_struct.run.track(best_loss, name="loss", step=generation)
end


struct Wandb_LossEpoch <: AbstractCallable
    wandb_log
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

