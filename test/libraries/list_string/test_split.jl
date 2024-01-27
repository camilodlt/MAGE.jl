using UTCGP
using Test

@testset "Split" begin
    @test begin
        import UTCGP.liststring_split: split_string_to_vector
        split_string_to_vector("hello hello", " ") == ["hello", "hello"]
    end
    @test begin
        import UTCGP.liststring_split: split_string_to_vector
        split_string_to_vector("hello hello", ".") == ["hello hello"]
    end

end
