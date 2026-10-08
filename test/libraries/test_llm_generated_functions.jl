using UTCGP

struct MockGeneratedFunctionClient <: UTCGP.AbstractGeneratedFunctionClient
    initial::UTCGP.GeneratedFunctionSpec
    repaired::UTCGP.GeneratedFunctionSpec
end

function UTCGP.generate_function_spec(
        client::MockGeneratedFunctionClient,
        ::AbstractString,
        ;
        encoded_images::Vector{String} = String[],
    )::UTCGP.GeneratedFunctionSpec
    return client.initial
end

function UTCGP.repair_function_spec(
        client::MockGeneratedFunctionClient,
        ::AbstractString,
        ::UTCGP.GeneratedFunctionSpec,
        ::UTCGP.GeneratedFunctionValidationReport,
        ;
        encoded_images::Vector{String} = String[],
    )::UTCGP.GeneratedFunctionSpec
    return client.repaired
end

function _llm_generated_function_fixture()
    fallback_int = () -> 0
    bundle_int = FunctionBundle(fallback_int)
    add = FunctionWrapper((x::Int, y::Int, args...) -> x + y, :add, nothing, fallback_int)
    identity_int = FunctionWrapper((x::Int, args...) -> x, :identity_int, nothing, fallback_int)
    push!(bundle_int.functions, [identity_int, add]...)

    fallback_float = () -> 0.0
    bundle_float = FunctionBundle(fallback_float)
    identity_float = FunctionWrapper((x::Float64, args...) -> x, :identity_float, nothing, fallback_float)
    push!(bundle_float.functions, [identity_float]...)

    ml = UTCGP.MetaLibrary([Library([bundle_int]), Library([bundle_float])])
    ma = modelArchitecture([Int, Float64], [1, 2], [Int, Float64], [Int], [1])
    nc = nodeConfig(4, 1, 3, 2)

    return (; ml, ma, nc, add, identity_int)
end

@testset "LLM Generated Functions" begin
    @testset "Compile, validate, install, and dispatch" begin
        fixture = _llm_generated_function_fixture()
        ml = fixture.ml
        ma = fixture.ma
        nc = fixture.nc

        spec = GeneratedFunctionSpec(
            :sum_plus_one,
            [:x1, :x2],
            [Int, Int],
            Int,
            "return fns_returning_int.add(x1, x2) + 1";
            description = "",
        )

        bindings = generated_function_bindings(ml, ma)
        @test haskey(bindings, :image_values)
        @test haskey(bindings, :image_values_float64)
        @test haskey(bindings, :rewrap_like)
        @test haskey(bindings, :fns_returning_int)
        source = render_generated_function_source(spec, bindings)
        @test occursin("function sum_plus_one", source)
        @test occursin("fns_returning_int", source)
        @test occursin("fns_returning_int.add", source)

        artifact, report = validate_generated_function(
            spec,
            ma,
            nc,
            [(1, 2), (10, 5)];
            keyword_bindings = bindings,
            max_mean_runtime_seconds = 1.0,
        )

        @test !isnothing(artifact)
        @test report.accepted
        @test report.dispatch_ok
        @test artifact.function_like(2, 3) == 6
        @test which(artifact.function_like, Tuple{Int, Int}).nargs == 4
        @test which(artifact.function_like, Tuple{Int, Int, Float64}).nargs == 4
        @test_throws MethodError which(artifact.function_like, Tuple{Int})
        @test_throws MethodError which(artifact.function_like, Tuple{Float64, Int})

        library_idx, fn_idx, wrapper = install_generated_function!(ml, ma, artifact)
        @test library_idx == 1
        @test ml[library_idx][fn_idx].name == :sum_plus_one
        @test wrapper.description == UTCGP._sanitize_wrapper_description(:sum_plus_one, spec.description)
        @test wrapper.fn.source == artifact.source
        @test wrapper.fn(3, 4) == 8
    end

    @testset "Generated functions compose through named callables" begin
        fixture = _llm_generated_function_fixture()
        ml = fixture.ml
        ma = fixture.ma
        nc = fixture.nc

        first_spec = GeneratedFunctionSpec(
            :sum_two_ints,
            [:x1, :x2],
            [Int, Int],
            Int,
            "return fns_returning_int.add(x1, x2)";
            description = "Adds two integer inputs.",
        )
        base_bindings = generated_function_bindings(ml, ma)
        first_artifact, first_report = validate_generated_function(
            first_spec,
            ma,
            nc,
            [(1, 2), (7, 9)];
            keyword_bindings = base_bindings,
            max_mean_runtime_seconds = 1.0,
        )
        @test first_report.accepted
        install_generated_function!(ml, ma, first_artifact)

        composed_spec = GeneratedFunctionSpec(
            :double_sum_two_ints,
            [:x1, :x2],
            [Int, Int],
            Int,
            "tmp = fns_returning_int.sum_two_ints(x1, x2)\nreturn fns_returning_int.add(tmp, tmp)";
            description = "Doubles the sum produced by sum_two_ints.",
        )
        composed_bindings = generated_function_bindings(ml, ma)
        @test haskey(composed_bindings, :fns_returning_int)
        @test haskey(composed_bindings[:fns_returning_int].callables, :sum_two_ints)
        composed_artifact, composed_report = validate_generated_function(
            composed_spec,
            ma,
            nc,
            [(2, 3), (4, 5)];
            keyword_bindings = composed_bindings,
            max_mean_runtime_seconds = 1.0,
        )

        @test !isnothing(composed_artifact)
        @test composed_report.accepted
        @test composed_report.dispatch_ok
        @test composed_artifact.function_like(2, 3) == 10
        @test which(composed_artifact.function_like, Tuple{Int, Int}).nargs == 4
        @test which(composed_artifact.function_like, Tuple{Int, Int, Float64}).nargs == 4
    end

    @testset "Namespace dispatch handles same readable name with multiple methods" begin
        dispatcher = UTCGP.GeneratedFunctionNameDispatcher(
            :reduce_length,
            Any[
                (x::String, args...) -> length(x),
                (x::Int, args...) -> x,
            ],
        )

        @test dispatcher("abcd") == 4
        @test dispatcher(7) == 7
        @test which(dispatcher, Tuple{String}).nargs >= 3
    end

    @testset "Rejects illegal signatures" begin
        fixture = _llm_generated_function_fixture()
        ml = fixture.ml
        ma = fixture.ma
        nc = fixture.nc
        bindings = generated_function_bindings(ml, ma)

        too_wide = GeneratedFunctionSpec(
            :too_wide,
            [:a, :b, :c, :d],
            [Int, Int, Int, Int],
            Int,
            "return a + b + c + d",
        )
        _, wide_report = validate_generated_function(
            too_wide,
            ma,
            nc,
            [(1, 2, 3, 4)];
            keyword_bindings = bindings,
        )
        @test !wide_report.accepted
        @test !wide_report.arity_ok

        bad_output = GeneratedFunctionSpec(
            :bad_output,
            [:a],
            [Int],
            String,
            "return string(a)",
        )
        _, output_report = validate_generated_function(
            bad_output,
            ma,
            nc,
            [(1,)];
            keyword_bindings = bindings,
        )
        @test !output_report.accepted
        @test !output_report.output_type_ok
    end

    @testset "Rejects duplicate generated-function names at install time" begin
        fixture = _llm_generated_function_fixture()
        ml = fixture.ml
        ma = fixture.ma
        nc = fixture.nc
        bindings = generated_function_bindings(ml, ma)

        duplicate_spec = GeneratedFunctionSpec(
            :fresh_name_at_compile,
            [:x1, :x2],
            [Int, Int],
            Int,
            "return fns_returning_int.add(x1, x2)";
            description = "Adds two ints with a temporary name.",
        )
        artifact, report = validate_generated_function(
            duplicate_spec,
            ma,
            nc,
            [(1, 2), (3, 4)];
            keyword_bindings = bindings,
            max_mean_runtime_seconds = 1.0,
        )
        @test report.accepted

        artifact = GeneratedFunctionArtifact(
            GeneratedFunctionSpec(
                :add,
                artifact.spec.argument_names,
                artifact.spec.input_types,
                artifact.spec.output_type,
                artifact.spec.body;
                description = artifact.spec.description,
            ),
            artifact.source,
            artifact.keyword_bindings,
            artifact.module_name,
            artifact.function_like,
        )

        @test_throws AssertionError install_generated_function!(ml, ma, artifact)
    end

    @testset "llama.cpp client parses structured function specs" begin
        fixture = _llm_generated_function_fixture()
        ma = fixture.ma
        nc = fixture.nc
        client = make_llm_generated_function_client(
            model_name = "ggml-org/gemma-4-E4B-it-GGUF",
            model_architecture = ma,
            node_config = nc,
            host = "http://127.0.0.1:8080",
        )

        @test llm_generated_function_client_backend(client) == "llama_cpp"
        parsed = UTCGP._parse_generated_function_spec(
            client,
            """
            {"name":"typed_sum","argument_names":["x1","x2"],"input_types":["Int64","Int64"],"output_type":"Int64","body":"return x1 + x2","description":"Adds two typed integers."}
            """,
        )
        @test parsed.name == :typed_sum
        @test parsed.argument_names == [:x1, :x2]
        @test parsed.input_types == [Int, Int]
        @test parsed.output_type == Int
        @test parsed.body == "return x1 + x2"
        @test parsed.description == "Adds two typed integers."
    end

    @testset "Iterative repair loop" begin
        fixture = _llm_generated_function_fixture()
        ml = fixture.ml
        ma = fixture.ma
        nc = fixture.nc
        bindings = generated_function_bindings(ml, ma)

        broken = GeneratedFunctionSpec(
            :repair_me,
            [:x1, :x2],
            [Int, Int],
            Int,
            "return missing_helper(x1, x2)",
        )
        repaired = GeneratedFunctionSpec(
            :repair_me,
            [:x1, :x2],
            [Int, Int],
            Int,
            "return fns_returning_int.add(x1, x2)",
        )
        client = MockGeneratedFunctionClient(broken, repaired)

        result = synthesize_validated_function(
            client,
            "sum two ints",
            ma,
            nc,
            [(2, 5), (10, 11)];
            keyword_bindings = bindings,
            max_attempts = 2,
            max_mean_runtime_seconds = 1.0,
        )

        @test !isnothing(result.accepted_artifact)
        @test length(result.attempts) == 2
        @test !result.attempts[1].report.accepted
        @test result.attempts[2].report.accepted
        @test result.accepted_artifact.function_like(4, 7) == 11
    end
end
