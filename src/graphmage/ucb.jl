############################
# GraphMAGE: UCB formula
############################

"""
    ucb_score(node, parent_visits, c)

Standard UCB1, generalized from single-parent MCTS to a graph: `node`'s
`visits`/`reward_sum` are already the sum over *every* path that ever reached
it (see `backpropagate!`), so the formula itself does not need to know how
many parents `node` has. Unvisited nodes return `Inf` to force exploration.
"""
function ucb_score(node::GraphMAGENode, parent_visits::Int, c::Float64)::Float64
    node.visits == 0 && return Inf
    return node.reward_sum / node.visits + c * sqrt(log(max(parent_visits, 1)) / node.visits)
end

"""
    annealed_c(c0, c_final, frac)

Linear interpolation from `c0` (`frac = 0`) to `c_final` (`frac = 1`) given an
already-computed progress fraction (clamped to `[0, 1]`), used only when
`GraphMAGEConfig.anneal_ucb` is set so the search shifts toward exploitation
as the budget is consumed.
"""
function annealed_c(c0::Float64, c_final::Float64, frac::Float64)::Float64
    return c0 + (c_final - c0) * clamp(frac, 0.0, 1.0)
end

"""
    annealed_c(c0, c_final, t, T)

Iteration-count convenience form: progress fraction is `t / T`. Do not use
this when `GraphMAGEConfig.time_budget_minutes` is set with a large dummy
`n_expansions` (the recommended way to combine a time budget with an
otherwise-unreachable expansion cap) -- `t / T` would then stay near 0 for
the entire run and never actually anneal; `run_graphmage` calls the
`frac`-based method directly with an elapsed-time fraction in that case.
"""
function annealed_c(c0::Float64, c_final::Float64, t::Int, T::Int)::Float64
    T <= 1 && return c_final
    return annealed_c(c0, c_final, t / T)
end
