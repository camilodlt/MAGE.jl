using Test
using UTCGP
using Random
rng = Random.seed!(123)



@testset "Standard M on node" begin
    # loops until one correct mutation is found
    @test begin
        # Assume we have 1 input ["begin", "end"]
        inp_n = InputNode(["begin", "end"], 1, 1, 1)
        si = SharedInput([inp_n])
        # Node to mutate
        el_1 = CGPElement(1, 2, 2, 1, 1, false, FUNCTION) # 2 fns
        el_2 = CGPElement(1, 1, 2, 1, 1, false, CONNEXION) # can only connect backwards
        el_3 = CGPElement(1, 1, 2, 1, 1, false, CONNEXION) # can only connect backwards
        el_4 = CGPElement(1, 1, 2, 1, 1, false, TYPE) # One type
        el_5 = CGPElement(1, 1, 2, 1, 1, false, TYPE) # One type        
        node = CGPNode(NodeMaterial([el_1, el_2, el_3, el_4, el_5]), nothing, 2, 1, 1)
        uni_type_genome = SingleGenome(1, [node])
        output_node = OutputNode(nothing, 3, 2, 1)
        ut_genome = UTGenome([uni_type_genome], [output_node])
        initialize_genome!(ut_genome)
        # set an incorrect node on purpose
        el_1.value = 3
        # config
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        ma = modelArchitecture([Vector{String}], [1], [Vector{String}], [String], [1])
        bundles_list_string = [
            bundle_listgeneric_basic,# identity_list, new_list
        ]
        # Libraries
        lib_list_str = Library(bundles_list_string)
        ml = MetaLibrary([lib_list_str])
        # test 
        before = node_to_vector(node)
        standard_mutate!(node, ma, lib_list_str, ut_genome, si)
        after = node_to_vector(node)
        before !== after

    end
    # loops until one correct mutation is found
    @test begin
        # Assume we have 1 input ["begin", "end"]
        inp_n = InputNode(["begin", "end"], 1, 1, 1)
        si = SharedInput([inp_n])
        # Node to mutate
        el_1 = CGPElement(1, 2, 2, 1, 1, false, FUNCTION) # 2 fns
        el_2 = CGPElement(1, 1, 2, 1, 1, false, CONNEXION) # can only connect backwards
        el_3 = CGPElement(1, 1, 2, 1, 1, false, CONNEXION) # can only connect backwards
        el_4 = CGPElement(1, 1, 2, 1, 1, false, TYPE) # One type
        el_5 = CGPElement(1, 1, 2, 1, 1, false, TYPE) # One type        
        node = CGPNode(NodeMaterial([el_1, el_2, el_3, el_4, el_5]), nothing, 2, 1, 1)
        uni_type_genome = SingleGenome(1, [node])
        output_node = OutputNode(nothing, 3, 2, 1)
        ut_genome = UTGenome([uni_type_genome], [output_node])
        initialize_genome!(ut_genome)
        # set an incorrect node on purpose
        el_1.value = 3
        # config
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        ma = modelArchitecture([Vector{String}], [1], [Vector{String}], [String], [1])
        bundles_list_string = [
            bundle_listgeneric_basic,# identity_list, new_list
        ]
        # Libraries
        lib_list_str = Library(bundles_list_string)
        ml = MetaLibrary([lib_list_str])
        # test 
        before = node_to_vector(node)
        standard_mutate!(node, ma, lib_list_str, ut_genome, si)
        after = node_to_vector(node)
        after[1] == 1 || after[1] == 2 # After the node is corrected, the fn must be 1 or 2. 
    end
end

@testset "Standard M on Single Genome" begin
    # loops until one correct mutation is found
    @test begin
        # Assume we have 1 input ["begin", "end"]
        inp_n = InputNode(["begin", "end"], 1, 1, 1)
        si = SharedInput([inp_n])
        # Node to mutate
        el_1 = CGPElement(1, 2, 2, 1, 1, false, FUNCTION) # 2 fns
        el_2 = CGPElement(1, 1, 2, 1, 1, false, CONNEXION) # can only connect backwards
        el_3 = CGPElement(1, 1, 2, 1, 1, false, CONNEXION) # can only connect backwards
        el_4 = CGPElement(1, 1, 2, 1, 1, false, TYPE) # One type
        el_5 = CGPElement(1, 1, 2, 1, 1, false, TYPE) # One type        
        node = CGPNode(NodeMaterial([el_1, el_2, el_3, el_4, el_5]), nothing, 2, 1, 1)
        uni_type_genome = SingleGenome(1, [node])
        output_node = OutputNode(nothing, 3, 2, 1)
        ut_genome = UTGenome([uni_type_genome], [output_node])
        initialize_genome!(ut_genome)
        # set an incorrect node on purpose
        el_1.value = 3
        # config
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        ma = modelArchitecture([Vector{String}], [1], [Vector{String}], [String], [1])
        bundles_list_string = [
            bundle_listgeneric_basic,# identity_list, new_list
        ]
        # Libraries
        lib_list_str = Library(bundles_list_string)
        ml = MetaLibrary([lib_list_str])
        # test 
        before = node_to_vector(node)
        standard_mutate!(uni_type_genome, rc, ma, lib_list_str, ut_genome, si)
        after = node_to_vector(node)
        after[1] == 1 || after[1] == 2 # After the node is corrected, the fn must be 1 or 2. 
    end
end

@testset "Standard M on UTGenome" begin
    # loops until one correct mutation is found
    @test begin
        # Assume we have 1 input ["begin", "end"]
        inp_n = InputNode(["begin", "end"], 1, 1, 1)
        si = SharedInput([inp_n])
        # Node to mutate
        el_1 = CGPElement(1, 2, 2, 1, 1, false, FUNCTION) # 2 fns
        el_2 = CGPElement(1, 1, 2, 1, 1, false, CONNEXION) # can only connect backwards
        el_3 = CGPElement(1, 1, 2, 1, 1, false, CONNEXION) # can only connect backwards
        el_4 = CGPElement(1, 1, 2, 1, 1, false, TYPE) # One type
        el_5 = CGPElement(1, 1, 2, 1, 1, false, TYPE) # One type        
        node = CGPNode(NodeMaterial([el_1, el_2, el_3, el_4, el_5]), nothing, 2, 1, 1)
        uni_type_genome = SingleGenome(1, [node])
        output_node = OutputNode(nothing, 3, 2, 1)
        ut_genome = UTGenome([uni_type_genome], [output_node])
        initialize_genome!(ut_genome)
        # set an incorrect node on purpose
        el_1.value = 3
        # config
        rc = runConf(10, 10, 0.99, 0.99) # almost sure that everything is mutated
        ma = modelArchitecture([Vector{String}], [1], [Vector{String}], [String], [1])
        bundles_list_string = [
            bundle_listgeneric_basic,# identity_list, new_list
        ]
        # Libraries
        lib_list_str = Library(bundles_list_string)
        ml = MetaLibrary([lib_list_str])
        # test 
        before = node_to_vector(node)
        standard_mutate!(ut_genome, rc, ma, ml, si)
        after = node_to_vector(node)
        after[1] == 1 || after[1] == 2 # After the node is corrected, the fn must be 1 or 2. 
    end
end
