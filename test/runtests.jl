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
        end
    end
    @testset "Mutations" begin
        @testset "Utils " begin
            include("mutations/test_utils_mutations.jl")
        end
        @testset "Standard Mutation" begin
            include("mutations/test_standard_mutation.jl")
        end
    end

    @testset "Fitters" begin
        include("fitters/test_default_mutation.jl")
    end
end
