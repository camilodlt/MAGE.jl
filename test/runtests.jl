using Test
using Pkg
using PyCall
using ForceImport

path = ENV["UTCGP_PYTHON"]
ENV["PYTHON"] = path

#Pkg.add("PyCall")
Pkg.build("PyCall")

#@testset failfast = true "UTCGP TEST" begin
@testset "UTCGP TEST" begin

    # @testset "node_element" begin
    #     include("element_nodes/test_element_node.jl")
    # end
    # @testset "random_element_node_element" begin
    #     include("element_nodes/test_random_from_node_element.jl")
    # end
    # @testset "Nodes" begin
    #     include("nodes/test_nodes.jl")
    #     include("nodes/test_make_nodes.jl")
    # end
    # @testset "Genome" begin
    #     # include("nodes/test_nodes.jl")
    #     include("genome/test_make_single_genome.jl")
    # end

    # @testset "Config" begin
    #     include("config/config.jl")
    # end

    # @testset "Library" begin
    #     include("meta_library/test_library.jl")
    # end
    # @testset "Meta_Library" begin
    #     include("meta_library/test_meta_library.jl")
    # end
    # @testset "Functions" begin
    #     @testset begin
    #         include("libraries/clone_bundle.jl")
    #     end
    # end
    # @testset "Mutations" begin
    #     @testset "Utils " begin
    #         include("mutations/test_utils_mutations.jl")
    #     end
    #     @testset "Standard Mutation" begin
    #         include("mutations/test_standard_mutation.jl")
    #     end
    #     @testset "Numbered Mutation" begin
    #         include("mutations/test_numbered_mutation.jl")
    #     end
    # end
    # @testset "Fitters" begin
    #     include("fitters/test_default_mutation.jl")
    # end
    # @testset "Endpoints" begin
    #     include("endpoints/test_levenshtein.jl")
    # end

    # CASTERS
    @testset "Casters" begin
        include("libraries/casters.jl")
    end
    # LIBS 
    @testset "String" begin
        include("libraries/string/grep.jl")
        include("libraries/string/paste.jl")
        include("libraries/string/test_conditional.jl")
        include("libraries/string/test_caps.jl")
        include("libraries/string/test_basic.jl")
        include("libraries/string/test_parse.jl")
    end

    # Vector Generic
    @testset "List Generic" begin
        include("libraries/list_generic/test_basic.jl")
        include("libraries/list_generic/test_make_lists.jl")
        include("libraries/list_generic/test_concat.jl")
        include("libraries/list_generic/test_subset.jl")
        include("libraries/list_generic/test_set.jl")
        include("libraries/list_generic/test_where.jl")
        include("libraries/list_generic/test_utils.jl")
    end

    @testset "List number" begin
        include("libraries/list_number/test_arithmetic.jl")
        include("libraries/list_number/test_algebraic.jl")
        include("libraries/list_number/test_recursive.jl")
        include("libraries/list_number/test_vectuples.jl")
        include("libraries/list_number/test_basic.jl")
    end
    @testset "List Integer" begin
        include("libraries/list_integer/test_iscond.jl")
        include("libraries/list_integer/test_string.jl")
        include("libraries/list_integer/test_primes.jl")
    end
    @testset "List String" begin
        include("libraries/list_string/test_split.jl")
        include("libraries/list_string/test_caps.jl")
        include("libraries/list_string/test_broadcast.jl")
    end

    @testset "List Tuple()" begin
        include("libraries/list_tuple/test_list_tuple_combinatorics.jl")
        include("libraries/list_tuple/test_list_tuple_mappings.jl")
    end

    @testset "Element" begin
        include("libraries/element/test_vector_interface.jl")
        include("libraries/element/test_conditional.jl")
    end

    @testset "Numbers" begin
        include("libraries/number/test_arithmetic.jl")
        include("libraries/number/test_reduce.jl")
    end
    @testset "Integers" begin
        include("libraries/integer/test_basic.jl")
        include("libraries/integer/test_find.jl")
        include("libraries/integer/test_modulo.jl")
        include("libraries/integer/test_cond.jl")
    end
    @testset "PSB2" begin
        include("problem_specific/test_basement.jl") #basement
        include("problem_specific/test_bouncing_balls.jl") #bouncing balls
        #bowling
        include("problem_specific/test_camel_case.jl")#camel case 
        include("problem_specific/test_coin_sums.jl")# coin sums 
        include("problem_specific/test_cut_vector.jl") # cutvector
        include("problem_specific/test_dice_game.jl")#dice game
        include("problem_specific/test_find_pair.jl")#find pair
        include("problem_specific/test_fizz_buzz.jl")#fizz buzz
        include("problem_specific/test_fuel_cost.jl")#fuel cost
        include("problem_specific/test_gcd.jl")#CGD
        include("problem_specific/test_indices_of_substring.jl")#Indices of substring
        include("problem_specific/test_leaders.jl")#leaders 
        include("problem_specific/test_luhn.jl")#Luhn
        include("problem_specific/test_mastermind.jl")#Mastermind
        include("problem_specific/test_middle_character.jl")#MiddleCharacter
        include("problem_specific/test_paired_digits.jl")#PairedDigits
        include("problem_specific/test_shopping_list.jl")#Shopping list
        include("problem_specific/test_snow_day.jl")#SnowDay
        include("problem_specific/test_solve_booleans.jl")#solve boolean 
        include("problem_specific/test_spin_words.jl")#spin worlds 
        include("problem_specific/test_square_digits.jl")#square digits 
        include("problem_specific/test_substitution_cipher.jl")#substitution cipher
        include("problem_specific/test_twitter.jl")#twitter 
        include("problem_specific/test_vec_dist.jl")#vector distance
    end
end
