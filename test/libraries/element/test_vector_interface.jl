@testset "Vector Interface" begin
    # BUNDLE
    @test begin
        # bundle import
        using UTCGP: bundle_element_pick
        length(bundle_element_pick) == 2 && _unique_names_in_bundle(bundle_element_pick)
    end
    # PICK ONE ELEMENT
    @test begin
        using UTCGP.element_pick: pick_element_from_vector
        # multitype, index at correct places
        vec = [1, 3.0, 132]
        pick_element_from_vector(vec, 1) == 1 &&
            pick_element_from_vector(vec, 2) == 3.0 &&
            pick_element_from_vector(vec, 3) == 132
    end
    @test_throws BoundsError begin
        using UTCGP.element_pick: pick_element_from_vector
        # incorrect index place 
        vec = [1, 3.0, 132]
        pick_element_from_vector(vec, 0)
    end
    @test_throws BoundsError begin
        using UTCGP.element_pick: pick_element_from_vector
        # incorrect index place 
        vec = [1, 3.0, 132]
        pick_element_from_vector(vec, 4)
    end

    # PICK FIRST ELEMENT

    # PICK LAST ELEMENT
    @test begin
        using UTCGP.element_pick: pick_last_element
        vec = [1, 3.0, 132]
        pick_last_element(vec) == 132
    end

    @test_throws BoundsError begin
        # There is no last, returns Bounds Error
        using UTCGP.element_pick: pick_last_element
        vec = []
        pick_last_element(vec)
    end
    # PICK MIDDLE ELEMENT

end
