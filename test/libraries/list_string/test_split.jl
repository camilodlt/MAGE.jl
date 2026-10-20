using MAGE

@testset "Split" begin
    @test begin
        import MAGE.liststring_split: split_string_to_vector
        split_string_to_vector("hello hello", " ") == ["hello", "hello"]
    end
    @test begin
        import MAGE.liststring_split: split_string_to_vector
        split_string_to_vector("hello hello", ".") == ["hello hello"]
    end

end
