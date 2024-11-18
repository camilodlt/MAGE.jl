
function random_element_value(node_element::AbstractElement)::Int
    if node_element.is_freezed
        # return node_element.value ? node_element.value !== nothing : 1
        @assert node_element.value !== nothing "frozen node has not been used or init"
        return node_element.value
    else
        return rand((node_element.lowest_bound:node_element.highest_bound))
    end
end

function random_decreasing_element_value(node_element::AbstractElement)::Int
    if node_element.is_freezed
        # return node_element.value ? node_element.value !== nothing : 1
        @assert node_element.value !== nothing "frozen node has not been used or init"
        return node_element.value
    else
        if node_element.element_type == CONNEXION
            T = 100
            possible_values = collect(node_element.lowest_bound:node_element.highest_bound)
            ws = Weights(possible_values .+ T)
            return sample(possible_values, ws, 1)[1]
        else
            return rand((node_element.lowest_bound:node_element.highest_bound))
        end
    end
end

function initialize_node_element!(node_element::AbstractElement)
    if node_element.value === nothing
        if node_element.is_freezed
            set_node_element_value!(node_element, node_element.lowest_bound)
        else
            set_node_element_value!(node_element, random_element_value(node_element))
        end
    else
        print("Trying to init an already init node element. Init Ignored")
    end
end



# @overload
# def random_element_value_from_probs(
#     node_element: CGP_Element, temperature: int = 1
# ) -> int:
#     if node_element.freezed:
#         assert node_element.lowest_bound == node_element.highest_bound
#         return node_element.lowest_bound  # always lowest bound
#     else:
#         smooth_possibilities = np.arange(
#             node_element.lowest_bound
#             + temperature,  # to counteract the fact that without this
#             # the node 0 would always have a prob of 0
#             node_element.highest_bound + temperature + 1,
#         )  # 1, 3 => [1,2,3]

#         true_possibilities = np.arange(
#             node_element.lowest_bound, node_element.highest_bound + 1
#         )

#         probs = smooth_possibilities / np.sum(smooth_possibilities)
#         assert len(true_possibilities) == len(probs)
#         return np.random.choice(true_possibilities, p=probs)
