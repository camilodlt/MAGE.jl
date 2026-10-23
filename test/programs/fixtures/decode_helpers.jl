using Test, Random, MAGE

if !isdefined(@__MODULE__, :_deterministic_program)
function _deterministic_program()
    # A program that sums the first and second input then divides by x1. 
    # so for x1 = 1, y2 = 1 => identity((1+1)/1)
    model_arch = modelArchitecture([Int, Int], [1, 1], [Int], [Int], [1])
    bundles_int = [bundle_integer_basic, bundle_number_arithmetic]
    bundles_int = [deepcopy(b) for b in bundles_int]
    update_caster!.(bundles_int, integer_caster)
    update_fallback!.(bundles_int, () -> 0)
    mini_lib_int = Library(bundles_int)
    ml = MetaLibrary([mini_lib_int])
    nc = nodeConfig(3, 1, 3, 2)
    shared_inputs, ut_genome = make_evolvable_utgenome(model_arch, ml, nc)
    initialize_genome!(ut_genome)
    ut_genome[1][1][1].value = 3 # fn to number_sum
    ut_genome[1][1][2].value = 1 # connects to x1
    ut_genome[1][1][4].value = 2 # connects to x2 

    # Div (x4 = x3/x1)
    ut_genome[1][2][1].value = 6 # fn to number_div
    ut_genome[1][2][2].value = 3 # connects to x3
    ut_genome[1][2][4].value = 1 # connects to x1 

    # Div (x5 = id(x4))
    ut_genome[1][3][1].value = 1 # fn to identity
    ut_genome[1][3][2].value = 4 # connects to x3

    # out points to last node (5)
    ut_genome.output_nodes[1][1].value = 1 # identity
    ut_genome.output_nodes[1][2].value = 5 # last node

    (ut_genome, model_arch, ml, shared_inputs, nc)
end

function _install_deterministic_adf()
    genome, model_arch, ml, inputs, nc = _deterministic_program()
    registry = ADFRegistry()
    slots = extend_fn_lib_adf!(ml[1], registry, Int, 2; fallback = () -> 0)
    replace_adf_slot!(registry, slots[1].slot_id, genome, inputs, model_arch, ml; name = :adf_sum_div)
    return (; genome, model_arch, ml, inputs, registry, slots)
end

function _adf_calling_genome(adf_fn_index::Int)
    genome, model_arch, ml, inputs, nc = _deterministic_program()

    genome[1][1][1].value = adf_fn_index
    genome[1][1][2].value = 1
    genome[1][1][4].value = 2
    genome.output_nodes[1][1].value = 1
    genome.output_nodes[1][2].value = 3

    return genome, model_arch, inputs
end

function cache_fixture(; typed=false, n=100)
    types = typed ? [Float64, Int] : [Float64]
    arch = modelArchitecture(typed ? [Float64, Int] : [Float64, Float64], [1, typed ? 2 : 1], types,
        typed ? [Float64, Int, Float64] : [Float64, Float64], typed ? [1,2,1] : [1,1])
    bundles = deepcopy.([bundle_float_basic, bundle_number_arithmetic])
    update_caster!.(bundles, float_caster)
    update_fallback!.(bundles, ()->0.0)
    libs = [Library(bundles)]
    if typed
        ib = deepcopy.([bundle_integer_basic, bundle_number_arithmetic])
        update_caster!.(ib, integer_caster)
        update_fallback!.(ib, ()->0)
        push!(libs, Library(ib))
    end
    ml = MetaLibrary(libs)
    shared, genome = make_evolvable_utgenome(arch, ml, nodeConfig(n,1,2,2))
    initialize_genome!(genome)
    # A guaranteed two-node active chain, with the rest randomly initialized.
    for row in eachindex(types)
        genome[row][1][1].value = 1
        genome[row][1][2].value = row
        genome[row][2][1].value = 1
        genome[row][2][2].value = 3
        genome[row][2][3].value = row
    end
    for output in genome.output_nodes
        output[2].value = 4
    end
    correct_all_nodes!(genome,arch,ml,shared)
    return (; arch, ml, shared, genome)
end

end
