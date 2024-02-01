module UTCGP

NANO_ARRAY = parse(Int, get(ENV, "UTCGP_NANO_ARRAY", "100"))
SMALL_ARRAY = parse(Int, get(ENV, "UTCGP_SMALL_ARRAY", "1000"))
BIG_ARRAY = parse(Int, get(ENV, "UTCGP_BIG_ARRAY", "10000"))
CONSTRAINED = get(ENV, "UTCGP_CONSTRAINED", "") == "yes"
println("CONSTRAINED STATE = $CONSTRAINED ")

abstract type AbstractCallable end

include("element_nodes/element_nodes.jl")

export CGPElement, AbstractElement
export FUNCTION, CONNEXION, PARAMETER, TYPE, INPUT, OUTPUT
export NodeElementTypes
export get_node_element_value
export set_node_lowest_bound
export set_node_highest_bound
export set_node_position
export set_node_freeze_state
export set_node_unfreeze_state
export set_node_element_type
export set_node_value

include("element_nodes/random_from_node_element.jl")
export random_element_value
export initialize_node_element!
include("nodes/nodes.jl")
export initialize_node!
export node_to_vector
include("nodes/make_node.jl")
export make_output_node
export make_evolvable_node
export NodeMaterial
export AbstractNode, InputNode, OutputNode, CGPNode
export reset_node_value!, set_node_value!, get_node_value
# export initialize, get_node_id
export extract_connexions_types_from_node,
    extract_connexions_from_node, extract_function_from_node
export set_node_element_value!
export extract_parameters_from_node

# FN RELATED
include("libraries/function.jl")
include("libraries/bundle.jl")
include("libraries/meta_library.jl")
export FunctionBundle
export add_bundle_to_library!
export unpack_bundles_in_library!
export list_functions_names
export update_caster!
export update_fallback!

export Library
export MetaLibrary

# CONFIG 
include("config/config.jl")
export runConf
export modelArchitecture
export nodeConfig

# GENOME 
include("genome/genome.jl")
export SharedInput
export SingleGenome
export UTGenome

include("genome/make_genome.jl")

export make_evolvable_utgenome
export make_evolvable_single_genome
include("genome/utils_genome.jl")
export initialize_genome!

# POPULATION
include("population/population.jl")
export Population

# METRICS 
include("metrics_trackers/individual_loss_tracker.jl")

# PROGRAMS 
include("programs/programs.jl")
include("programs/decode.jl")
include("programs/free_decode.jl")
include("programs/evaluate.jl")

# MUTATIONS
include("mutations/utils_mutation.jl")
export where_to_mutate
export mutate_per_allele!
export mutate_one_element_from_node!
export get_active_nodes
export get_active_node_material

include("mutations/correct_all_nodes.jl")
export correct_all_nodes!
include("mutations/standard_mutation.jl")
export standard_mutate!
include("mutations/mt_mutation.jl")
export free_mutate!
include("mutations/numbered_mutation.jl")
export numbered_mutation!
include("mutations/decreasing_mutation.jl")
include("mutations/new_material_mutation.jl")
export new_material_mutation!
# FUNCTIONS

# Libraries

# -- Caster
include("libraries/casters.jl")
export listinteger_caster
export listfloat_caster
export float_caster
export integer_caster
export string_caster

# -- Element 
include("libraries/element/pick_element.jl")
import .element_pick: bundle_element_pick
export bundle_element_pick

include("libraries/element/conditional.jl")
import .element_conditional: bundle_element_conditional
export bundle_element_conditional

# -- String
include("libraries/string/grep.jl")
import .str_grep: bundle_string_grep
export bundle_string_grep

include("libraries/string/paste.jl")
import .str_paste: bundle_string_paste
export bundle_string_paste

import .str_paste: bundle_string_concat_list_string
export bundle_string_concat_list_string

include("libraries/string/conditional.jl")
import .str_conditional: bundle_string_conditional
export bundle_string_conditional

include("libraries/string/caps.jl")
import .str_caps: bundle_string_caps
export bundle_string_caps

include("libraries/string/basic.jl")
import .str_basic: bundle_string_basic
export bundle_string_basic

include("libraries/string/parse.jl")
import .str_parse: bundle_string_parse
export bundle_string_parse

# -- List Generic 

include("libraries/list_generic/basic.jl")
import .listgeneric_basic: bundle_listgeneric_basic, bundle_listgeneric_basic_factory
export bundle_listgeneric_basic
export bundle_listgeneric_basic_factory

include("libraries/list_generic/subset.jl")
import .listgeneric_subset: bundle_listgeneric_subset, bundle_listgeneric_subset_factory
export bundle_listgeneric_subset
export bundle_listgeneric_subset_factory

include("libraries/list_generic/make_lists.jl")
import .listgeneric_makelist:
    bundle_listgeneric_makelist, bundle_listgeneric_makelist_factory
export bundle_listgeneric_makelist
export bundle_listgeneric_makelist_factory

include("libraries/list_generic/list_concat.jl")
import .listgeneric_concat: bundle_listgeneric_concat, bundle_listgeneric_concat_factory
export bundle_listgeneric_concat
export bundle_listgeneric_concat_factory

include("libraries/list_generic/set.jl")
import .listgeneric_set: bundle_listgeneric_set, bundle_listgeneric_set_factory
export bundle_listgeneric_set
export bundle_listgeneric_set_factory

include("libraries/list_generic/where.jl")
import .listgeneric_where: bundle_listgeneric_where, bundle_listgeneric_where_factory
export bundle_listgeneric_where
export bundle_listgeneric_where_factory

include("libraries/list_generic/utils.jl")
import .listgeneric_utils: bundle_listgeneric_utils, bundle_listgeneric_utils_factory
export bundle_listgeneric_utils
export bundle_listgeneric_utils_factory

# -- List Number

include("libraries/list_number/arithmetic.jl")
import .listnumber_arithmetic: bundle_listnumber_arithmetic
export bundle_listnumber_arithmetic

include("libraries/list_number/algebraic.jl")
import .listnumber_algebraic: bundle_listnumber_algebraic
export bundle_listnumber_algebraic

include("libraries/list_number/recursive.jl")
import .listnumber_recursive: bundle_listnumber_recursive
export bundle_listnumber_recursive

include("libraries/list_number/from_tuples.jl")
import .listnumber_vectuples: bundle_listnumber_vectuples
export bundle_listnumber_vectuples

include("libraries/list_number/basic.jl")
import .listnumber_basic: bundle_listnumber_basic
export bundle_listnumber_basic

# -- List Integer
include("libraries/list_integer/is_conditions.jl")
import .listinteger_iscond: bundle_listinteger_iscond
export bundle_listinteger_iscond

include("libraries/list_integer/string.jl")
import .listinteger_string: bundle_listinteger_string
export bundle_listinteger_string

include("libraries/list_integer/primes.jl")
import .listinteger_primes: bundle_listinteger_primes
export bundle_listinteger_primes

# -- List String 
include("libraries/list_string/split.jl")
import .liststring_split: bundle_liststring_split
export bundle_liststring_split

include("libraries/list_string/caps.jl")
import .liststring_caps: bundle_liststring_caps
export bundle_liststring_caps

include("libraries/list_string/broadcast.jl")
import .liststring_broadcast: bundle_liststring_broadcast
export bundle_liststring_broadcast

# -- List Tuple
include("libraries/list_tuple/combinatorics.jl")
import .listtuple_combinatorics:
    bundle_listtuple_combinatorics, bundle_listtuple_combinatorics_factory
export bundle_listtuple_combinatorics
export bundle_listtuple_combinatorics_factory

include("libraries/list_tuple/mappings.jl")
import .listtuple_mappings: bundle_listtuple_mappings, bundle_listtuple_mappings_factory
export bundle_listtuple_mappings
export bundle_listtuple_mappings_factory

# -- Number

include("libraries/number/arithmetic.jl")
import .number_arithmetic: bundle_number_arithmetic
export bundle_number_arithmetic

include("libraries/number/reduce.jl")
import .number_reduce: bundle_number_reduce
export bundle_number_reduce

# --- FLOAT 

include("libraries/float/basic_float.jl")
import .float_basic: bundle_float_basic
export bundle_float_basic

# -- INTEGER

include("libraries/integer/basic_integer.jl")
import .integer_basic: bundle_integer_basic
export bundle_integer_basic

include("libraries/integer/find.jl")
import .integer_find: bundle_integer_find
export bundle_integer_find

include("libraries/integer/modulo.jl")
import .integer_modulo: bundle_integer_modulo
export bundle_integer_modulo

include("libraries/integer/cond.jl")
import .integer_cond: bundle_integer_cond
export bundle_integer_cond

# DEFAULT CALLBAKCS 
include("fitters/default_callbacks.jl")
export default_population_callback
export default_mutation_callback
export default_numbered_mutation_callback
export default_free_numbered_mutation_callback
export correct_all_nodes_callback
export default_numbered_new_material_mutation_callback

export default_ouptut_mutation_callback
export default_decoding_callback
export default_elite_selection_callback
export default_early_stop_callback
export default_free_mutation_callback
export default_free_decoding_callback

# ENDPOINTS
include("endpoints/endpoint_structs.jl")
export get_endpoint_results
include("endpoints/psb2_metrics.jl")
export EndpointBatchLevensthein
export EndpointBatchAbsDifference
export EndpointBatchVecDiff
include("metrics_trackers/aim_callback.jl")
export AIM_LossEpoch
# FIT
include("fitters/fit_utils.jl")
include("fitters/callbacks_callers.jl")
include("fitters/fit.jl")
export fit

# PRE MADE BUNDLES 
include("libraries/pre_made_libraries.jl")

# FILE TRACKING 
include("metrics_trackers/local_file.jl")

# Test utils
include("test_utils.jl")

end # 


