# # -*- coding: utf-8 -*-

using Statistics
using DataStructures: OrderedDict
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
    store::OrderedDict{Int,Vector{<:Number}}
    function IndividualLossTracker()
        return new(Dict{Int,Float64}())
    end
end


Base.size(ind_tracker::AbstractIndLossTracker) = length(ind_tracker.store)
Base.length(ind_tracker::AbstractIndLossTracker) = length(ind_tracker.store)
Base.getindex(ind_tracker::AbstractIndLossTracker, k::Int) = ind_tracker.store[k]
Base.setindex!(ind_tracker::AbstractIndLossTracker, value::Any, k::Int) =
    (ind_tracker.store[k] = value)


function add_loss_to_ind_tracker!(
    individual_loss_tracker::IndividualLossTracker,
    id::Int,
    loss::Float64,
)
    if !(haskey(individual_loss_tracker.store, id))
        individual_loss_tracker.store[id] = Vector{Float64}()
    end
    push!(individual_loss_tracker.store[id], loss)
end

function add_pop_loss_to_ind_tracker!(
    individual_loss_tracker::IndividualLossTracker,
    losses::Vector{Float64},
)
    for (ith_individual, loss_value) in enumerate(losses)
        add_loss_to_ind_tracker!(individual_loss_tracker, ith_individual, loss_value)
    end
end

function resolve_ind_loss_tracker(individual_loss_tracker::IndividualLossTracker)
    # Vector{Float64}
    mean_prog_length_per_individual = Float64[]
    # Mean loss per program
    for ind_id in individual_loss_tracker.store
        mean_loss_over_batch = mean(individual_loss_tracker[ind_id[1]])
        push!(mean_prog_length_per_individual, mean_loss_over_batch)
    end
    return mean_prog_length_per_individual
end


"""
Multi Threaded Loss tracker

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
struct IndividualLossTrackerMT <: AbstractIndLossTracker
    store::Array{Float64,2}
    n_individuals::Int
    n_samples::Int
    function IndividualLossTrackerMT(n_individuals, n_samples)
        store = Array{Float64}(undef, n_individuals, n_samples)
        return new(store, n_individuals, n_samples)
    end
end

function Base.view(t::IndividualLossTrackerMT, r::Base.AbstractUnitRange)
    view(t.store, r)
end

function Base.view(t::IndividualLossTrackerMT, inds...)
    view(t.store, inds...)
end

"""

Puts a loss for every individual on a single sample
"""
function add_pop_loss_to_ind_tracker!(
    individual_loss_tracker_view::SubArray{Float64,2},
    col_nb::Int,
    losses::Vector{Float64},
)
    individual_loss_tracker_view[:, col_nb] = losses
end

function resolve_ind_loss_tracker(individual_loss_tracker::IndividualLossTrackerMT)
    fitness_per_individual = mean(individual_loss_tracker.store, dims = 2)
    return fitness_per_individual[:, 1] # a vector where each element is an individual final fitness
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
    store::OrderedDict{Int,Vector{<:Number}}
    function GenerationLossTracker()
        return new(Dict{Int,Float64}())
    end

end

Base.size(gen_tracker::AbstractGenLossTracker) = length(gen_tracker.store)
Base.length(gen_tracker::AbstractGenLossTracker) = length(gen_tracker.store)
Base.getindex(gen_tracker::AbstractGenLossTracker, k::Int) = gen_tracker.store[k]

function affect_fitness_to_loss_tracker!(
    generations_loss_tracker::GenerationLossTracker,
    id::Int,
    loss::Float64,
)

    if !(haskey(generations_loss_tracker.store, id))
        generations_loss_tracker.store[id] = Vector{Float64}()
    end
    push!(generations_loss_tracker.store[id], loss)
end


struct GenerationMultiObjectiveLossTracker <: AbstractGenLossTracker
    pareto_front::OrderedDict{Int,Vector{Vector{<:Number}}}
    function GenerationMultiObjectiveLossTracker()
        return new(OrderedDict{Int,Vector{Vector{<:Number}}}())
    end

end

Base.size(gen_tracker::GenerationMultiObjectiveLossTracker) =
    length(gen_tracker.pareto_front)
Base.length(gen_tracker::GenerationMultiObjectiveLossTracker) =
    length(gen_tracker.pareto_front)
Base.getindex(gen_tracker::GenerationMultiObjectiveLossTracker, k::Int) =
    gen_tracker.pareto_front[k]

function affect_fitness_to_loss_tracker!(
    generations_mo_loss_tracker::GenerationMultiObjectiveLossTracker,
    id::Int,
    pareto_front::Vector{Vector{Float64}},
)
    generations_mo_loss_tracker.pareto_front[id] = deepcopy(pareto_front)
end
