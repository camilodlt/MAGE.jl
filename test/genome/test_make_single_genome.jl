using UTCGP
using Test


@testset "Make Single Genome" begin
    # SIZE OF CHROMOSOME
    @test begin
        genome = make_evolvable_single_genome(1, 1, 1, 1, 1, 2, 2)
        length(genome.chromosome) == 1
    end
    @test begin
        genome = make_evolvable_single_genome(2, 2, 1, 1, 1, 2, 2)
        length(genome.chromosome) == 2
    end
    @test begin
        genome = make_evolvable_single_genome(2, 2, 1, 1, 1, 2, 2)
        length(genome.chromosome[1]) == 5 # 1 fn, 2 con,t
    end


    # OFFSET 
    @test begin
        # 4 inputs (1,2,3,4)
        # 4 nodes (5,6,7,8)
        genome = make_evolvable_single_genome(4, 2, 4, 1, 1, 2, 2)
        chr = genome.chromosome
        x_positions = [node.x_position for node in chr]
        x_positions == [5, 6, 7, 8]
    end
    @test begin
        # 0 inputs ()
        # 4 nodes (2,3,4,5)
        genome = make_evolvable_single_genome(4, 2, 1, 1, 1, 2, 2)
        chr = genome.chromosome
        x_positions = [node.x_position for node in chr]
        x_positions == [2, 3, 4, 5]
    end
    @test begin
        # 4 inputs 
        # 4 nodes 
        genome = make_evolvable_single_genome(4, 2, 4, 1, 1, 2, 2)
        chr = genome.chromosome
        x_r_positions = [node.x_real_position for node in chr]
        x_r_positions == [1, 2, 3, 4]
    end

    @test begin
        # 4 inputs 
        # 4 nodes 
        genome = make_evolvable_single_genome(4, 2, 4, 1, 1, 2, 2)
        chr = genome.chromosome
        max_allowed_con = []
        for node in chr
            con = extract_connexions_from_node(node)[1]
            push!(max_allowed_con, con.highest_bound)
        end
        max_allowed_con == [4, 5, 6, 7]
    end
end

