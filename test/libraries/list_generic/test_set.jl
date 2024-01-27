using UTCGP: bundle_listgeneric_set
using UTCGP.listgeneric_set: intersect_
using UTCGP.listgeneric_set: left_join

@testset "Set" begin
    @test begin
        # bundle import
        length(bundle_listgeneric_set) == 2 &&
            _unique_names_in_bundle(bundle_listgeneric_set)
    end

    # INTERSECT
    @test begin # works on string
        a = ["1", "2"]
        b = ["2", "3"]
        intersect_(a, b) == ["2"]
    end
    @test begin # works on int
        a = [1, 2]
        b = [2, 3]
        intersect_(a, b) == [2]
    end
    @test_throws MethodError begin # diff types
        # on specific type ...
        a = [1, 2]
        b = ["2", "3"]
        intersect_(a, b)
    end

    # LEFT JOIN  
    @test begin # works on string
        a = ["1", "2", "2"]
        b = ["2"]
        left_join(a, b) == ["2", "2"]
    end
    @test begin # works on int
        a = [1, 2, 3, 3]
        b = [2, 3]
        left_join(a, b) == [2, 3, 3]
    end
    @test_throws MethodError begin # diff types
        a = [1, 2]
        b = ["2", "3"]
        left_join(a, b)
    end

end
