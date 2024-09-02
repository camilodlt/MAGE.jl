
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ # 
# ########### TEST RUN CONF GA ########### # 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ # 

@testset "GA RunConf" begin
    # Normal
    @test begin
        r = RunConfGA(10, 10, 2, 0.1, 0.2, 1)
        true
    end
    # Bad
    @test_throws AssertionError begin
        r = RunConfGA(-1, 10, 2, 0.1, 0.2, 1)
    end
    @test_throws AssertionError begin
        r = RunConfGA(10, -1, 2, 0.1, 0.2, 1)
    end
    @test_throws AssertionError begin
        r = RunConfGA(10, 1, -2, 0.1, 0.2, 1)
    end
    @test_throws AssertionError begin
        r = RunConfGA(10, 1, 11, 0.1, 0.2, 1)
    end
    @test_throws AssertionError begin
        r = RunConfGA(10, 1, 2, 0.1, 0.2, -1)
    end
end

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ # 
# ########### TEST POP CALLBACK ########## # 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ # 
@testset "GA Pop Callback" begin
    (ind, model_arch, ml, shared_inputs, nc) = _deterministic_program()
    ind2 = deepcopy(ind)
    ind2[1][1][1].value = 2 # change the fn 
    pop = UTCGP.Population([ind, ind2])
    r = RunConfGA(10, 10, 2, 0.1, 0.2, 1)
    gen = 1

    # ARGUMENTS
    @test begin # can make args
        fitness = [1.0, 2.3]
        GA_POP_ARGS(pop, gen, r, model_arch, nc, ml, fitness)
        true
    end
    @test_throws AssertionError begin # not enough fitnesses
        fitness = [1.0]
        GA_POP_ARGS(pop, gen, r, model_arch, nc, ml, fitness)
        true
    end
    @test_throws AssertionError begin # two much fitnesses 
        fitness = [1.0, 1.0, 1.0]
        GA_POP_ARGS(pop, gen, r, model_arch, nc, ml, fitness)
        true
    end

    # CALLBACK
    @test begin
        r = RunConfGA(2, 1, 1, 0.1, 0.2, 1) # total pop : 3. Tournament of 1 out of 2 possible elites
        fitness = [1.0, 2.3]
        args = GA_POP_ARGS(pop, gen, r, model_arch, nc, ml, fitness)
        new_pop = @unwrap_or ga_population_callback(args) nothing
        hs = general_hasher_sha.(new_pop)
        length(new_pop) == 3 && (hs[3] == hs[1] || hs[3] == hs[2]) && hs[1] != hs[2]
    end

    # TOURNAMENT
    @test begin # Best in elite is the first of the tournament of 2
        r = RunConfGA(2, 1, 2, 0.1, 0.2, 1)
        fitness = [1.0, 2.3]
        args = GA_POP_ARGS(pop, gen, r, model_arch, nc, ml, fitness)
        new_pop = @unwrap_or ga_population_callback(args) nothing
        hs = general_hasher_sha.(new_pop)
        length(new_pop) == 3 && hs[3] == hs[1] && hs[1] != hs[2]
    end
    @test begin # Best in elite is the second of the tournament of 2
        r = RunConfGA(2, 1, 2, 0.1, 0.2, 1)
        fitness = [1.0, 0.3]
        args = GA_POP_ARGS(pop, gen, r, model_arch, nc, ml, fitness)
        new_pop = @unwrap_or ga_population_callback(args) nothing
        hs = general_hasher_sha.(new_pop)
        length(new_pop) == 3 && hs[3] == hs[2] && hs[1] != hs[2]
    end
    @test begin # Making the selection a lot of times gives almost 50-50%
        r = RunConfGA(2, 1, 1, 0.1, 0.2, 1)
        fitness = [1.0, 0.3]
        args = GA_POP_ARGS(pop, gen, r, model_arch, nc, ml, fitness)
        _first = []
        _second = []
        for i = 1:2000
            new_pop = @unwrap_or ga_population_callback(args) nothing
            hs = general_hasher_sha.(new_pop)
            hs[3] == hs[1] ? push!(_first, true) : push!(_second, true)

        end
        s_1 = sum(_first)
        s_2 = sum(_second)
        s_1 > 940 && s_1 < 1060 && s_2 > 940 && s_2 < 1060
    end
end

@testset "GA Population Mutation" begin
    (ind, model_arch, ml, shared_inputs, nc) = _deterministic_program()
    ind2 = deepcopy(ind)
    ind2[1][1][1].value = 2 # change the fn 
    pop = UTCGP.Population([ind, ind2])
    hs_init = general_hasher_sha.(pop)
    r = RunConfGA(1, 1, 1, 1.1, 0.2, 1) # the first will be the elite. The second will be mutated
    gen = 1
    args = GA_MUTATION_ARGS(pop, gen, r, model_arch, nc, ml, shared_inputs)
    # Mutation 
    @test begin
        new_pop = @unwrap_or ga_numbered_new_material_mutation_callback(args) return false
        hs = general_hasher_sha.(new_pop)
        hs[1] == hs_init[1] && hs[2] != hs_init[1] && hs[2] != hs_init[2]
    end

end

# OUTPUT MUTATION only mutates the output node of non elite progs
@testset "GA Output Mutation" begin
    (ind, model_arch, ml, shared_inputs, nc) = _deterministic_program()
    ind2 = deepcopy(ind)
    ind2[1][1][1].value = 2 # change the fn 
    pop = UTCGP.Population([ind, ind2])
    hs_init = general_hasher_sha.(pop)
    gen = 1

    # Output is not mutated
    @test begin
        r = RunConfGA(1, 1, 1, 1.1, 0.0, 1) # Prob of mutation is 0
        args = GA_MUTATION_ARGS(pop, gen, r, model_arch, nc, ml, shared_inputs)
        new_pop = @unwrap_or ga_output_mutation_callback(args) return false
        hs = general_hasher_sha.(new_pop)
        hs[1] == hs_init[1] && hs[2] == hs_init[2]
    end

    # Sure output is mutated (at some point the connection will be mutated)
    # since the fn is freezed and the connection spans between [1,1]
    @test begin
        r = RunConfGA(1, 1, 1, 1.1, 1.1, 1) # Prob of mutation is 1.
        args = GA_MUTATION_ARGS(pop, gen, r, model_arch, nc, ml, shared_inputs)
        eq_state = []
        diff_state = []
        for i = 1:200
            new_pop = @unwrap_or ga_output_mutation_callback(args) return false
            hs = general_hasher_sha.(new_pop)
            push!(eq_state, hs[1] == hs_init[1])
            push!(diff_state, hs[2] != hs_init[2])
        end
        # the first one never changed. 
        # Only the second one can change
        sum(eq_state) == length(eq_state) && sum(diff_state) > 1
    end
end


# Selection
# Select the pop_elite best
@testset "GA selection" begin
    (ind, model_arch, ml, shared_inputs, nc) = _deterministic_program()
    # another ind
    ind2 = deepcopy(ind)
    ind2[1][1][1].value = 2 # change the fn 
    # another ind
    ind3 = deepcopy(ind2)
    ind3[1][1][1].value = 4 # change the fn 
    pop = UTCGP.Population([ind, ind3, ind2])
    gen = 1

    @test begin # Select the best in pop. One is the absolute best. The other has eq f as the parent
        fitnesses = [1.0, 1.0, 0.93] # with this fitness and μ = 2, we should pick the third (bc best) & the second (bc the order is reversed) 
        r = RunConfGA(2, 1, 1, 1.1, 0.0, 1) # 2 parent, 1 children
        args = GA_SELECTION_ARGS(
            fitnesses,
            pop,
            gen,
            r,
            model_arch,
            nc,
            ml,
            UTCGP.PopulationPrograms(UTCGP.IndividualPrograms[]),
        )
        indices_best = @unwrap_or ga_elite_selection_callback(args) return false
        length(indices_best) == 2 && 3 in indices_best && 2 in indices_best
    end

    @test begin
        fitnesses = [1.0, 1.1, 0.93] # with this fitness and μ = 2, we should pick the third (bc best) & the first  
        r = RunConfGA(2, 1, 1, 1.1, 0.0, 1) # 2 parent, 1 children
        args = GA_SELECTION_ARGS(
            fitnesses,
            pop,
            gen,
            r,
            model_arch,
            nc,
            ml,
            UTCGP.PopulationPrograms(UTCGP.IndividualPrograms[]),
        )
        indices_best = @unwrap_or ga_elite_selection_callback(args) return false
        length(indices_best) == 2 && 3 in indices_best && 1 in indices_best
    end

    @test begin # Child has preference over parent
        r = RunConfGA(1, 2, 1, 1.1, 0.0, 1) # 1 parent, 2 children
        fitnesses = [1.0, 1.1, 1.0] # parent and last children have the same F. The child has preference. 
        args = GA_SELECTION_ARGS(
            fitnesses,
            pop,
            gen,
            r,
            model_arch,
            nc,
            ml,
            UTCGP.PopulationPrograms(UTCGP.IndividualPrograms[]),
        )
        indices_best = @unwrap_or ga_elite_selection_callback(args) return false
        length(indices_best) == 1 && 3 in indices_best
    end

    @test begin # Parent is selected if is the only best
        r = RunConfGA(1, 2, 1, 1.1, 0.0, 1) # 1 parent, 2 children
        fitnesses = [1.0, 1.1, 1.1] # the parent is the best 
        args = GA_SELECTION_ARGS(
            fitnesses,
            pop,
            gen,
            r,
            model_arch,
            nc,
            ml,
            UTCGP.PopulationPrograms(UTCGP.IndividualPrograms[]),
        )
        indices_best = @unwrap_or ga_elite_selection_callback(args) return false
        length(indices_best) == 1 && indices_best == [1]
    end
end
