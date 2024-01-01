

function all_eq_typed(a, b)
    conds = [i === j for (i, j) in zip(a, b)]
    return all(conds)
end
