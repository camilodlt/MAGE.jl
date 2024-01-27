using UTCGP: liststring_broadcast
using UTCGP: bundle_liststring_broadcast

@testset "Broadcast" begin
    @test begin
        # module is importable ... 
        length(bundle_liststring_broadcast) == 2 &&
            _unique_names_in_bundle(bundle_liststring_broadcast)
    end

    # REVERSE
    @test begin
        s = ["hello", "olleh"]
        liststring_broadcast.reverse_broadcast(s) == ["olleh", "hello"] && s[1] == "hello"
    end

    # NUMBERS AS STRINGS
    @test begin
        s = [1, 12.12]
        liststring_broadcast.numbers_to_string(s) == ["1.0", "12.12"] && s[1] == 1
    end
end
