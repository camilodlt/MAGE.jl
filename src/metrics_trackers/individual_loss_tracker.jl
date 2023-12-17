# # -*- coding: utf-8 -*-

using Statistics

abstract type AbstractIndLossTracker end
abstract type AbstractGenLossTracker end


"""
individual i : [loss_x_1, loss_x_2, ..., loss_x_n]
where n is the number of samples in the data.

In words: each individual has a fitness value for every data sample.

During inference steps, the method `add_pop_loss_to_ind_tracker`
adds losses to the store.
    => so that each ind_i = [numbers]

Before elite selection, the method `resolves_ind_loss_tracker`
takes the mean per individual.
    => so that each ind_i = number
"""
struct IndividualLossTracker <: AbstractIndLossTracker
    store::Dict{Int,Vector{<:Number}}
    function IndividualLossTracker()
        return new(Dict{Int,Float64}())
    end
end


Base.size(ind_tracker::AbstractIndLossTracker) = length(ind_tracker.store)
Base.length(ind_tracker::AbstractIndLossTracker) = length(ind_tracker.store)
Base.getindex(ind_tracker::AbstractIndLossTracker, k::Int) = ind_tracker.store[k]
Base.setindex!(ind_tracker::AbstractIndLossTracker, value::Float64, k::Int) =
    (ind_tracker.store[k] = value)



function add_loss_to_ind_tracker!(
    individual_loss_tracker::IndividualLossTracker,
    id::Int,
    loss::Float64,
)
    if !(id in individual_loss_tracker.store)
        individual_loss_tracker[id] = Vector{Float64}()
        push!(individual_loss_tracker.store[id], loss)
    end
end

function add_pop_loss_to_ind_tracker!(
    individual_loss_tracker::IndividualLossTracker,
    losses::Vector{float},
)
    for (ith_individual, loss_value) in enumerate(losses)
        add_loss_to_ind_tracker!(individual_loss_tracker, ith_individual, loss_value)
    end
end

function resolve_ind_loss_tracker(individual_loss_tracker::IndividualLossTracker)
    Vector{Float64}
    mean_prog_length_per_individual = Float64[]
    # Mean loss per program
    for ind_id in individual_loss_tracker
        mean_loss_over_batch = mean(individual_loss_tracker[ind_id])
        push!(mean_prog_length_per_individual, mean_loss_over_batch)
    end
    return mean_prog_length_per_individual
end

# ######################################
# # GENERATIONS TRACKER
# ######################################


"""
iteration i : nb
i goes from 0 to the total nb of generations computed.

The tracked value per iteration is the best loss (elite loss)
"""
struct GenerationLossTracker <: AbstractGenLossTracker
    store::Dict{Int,Vector{<:Number}}
    function GenerationLossTracker()
        return new(Dict{Int,Float64}())
    end

end


function affect_fitness_to_loss_tracker!(
    generations_loss_tracker::GenerationLossTracker,
    id::Int,
    loss::Float64,
)
    generations_loss_tracker.store[id] = loss
end
