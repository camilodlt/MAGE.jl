using Test

@testset "UTCGP TEST" begin

    @testset "node_element" begin
        include("element_nodes/test_element_node.jl")
    end
    @testset "random_element_node_element" begin
        include("element_nodes/test_random_from_node_element.jl")
    end
    @testset "Nodes" begin
        include("nodes/test_nodes.jl")
        include("nodes/test_make_nodes.jl")
    end
    @testset "Genome" begin
        # include("nodes/test_nodes.jl")
        include("genome/test_make_single_genome.jl")
    end

    @testset "Config" begin
        include("config/config.jl")
    end

    @testset "Library" begin
        include("meta_library/test_library.jl")
    end
    @testset "Meta_Library" begin
        include("meta_library/test_meta_library.jl")
    end
    @testset "Functions" begin
        @testset begin
            include("libraries/list_generic/test_basic.jl")
            include("libraries/clone_bundle.jl")
        end
    end
    @testset "Mutations" begin
        @testset "Utils " begin
            include("mutations/test_utils_mutations.jl")
        end
        @testset "Standard Mutation" begin
            include("mutations/test_standard_mutation.jl")
        end
        @testset "Numbered Mutation" begin
            include("mutations/test_numbered_mutation.jl")
        end


    end
    @testset "Fitters" begin
        include("fitters/test_default_mutation.jl")
    end
    @testset "Endpoints" begin
        include("endpoints/test_levenshtein.jl")
    end

    # LIBS 
    @testset "String" begin
        include("libraries/string/grep.jl")
        include("libraries/string/paste.jl")
        include("libraries/string/test_conditional.jl")
        include("libraries/string/test_caps.jl")
        include("libraries/string/test_basic.jl")
    end

    @testset "List Integer" begin
        include("libraries/list_integer/test_iscond.jl")
    end
    @testset "List String" begin
        include("libraries/list_string/test_split.jl")
    end

    @testset "Numbers" begin
        include("libraries/number/test_reduce.jl")
    end
    @testset "Integers" begin
        include("libraries/integer/test_find.jl")
    end
end
