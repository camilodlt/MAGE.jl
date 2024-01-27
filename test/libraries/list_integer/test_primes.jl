using UTCGP: bundle_listinteger_primes
using UTCGP.listinteger_primes: int_divisors

@testset "Primes" begin
    @test begin
        # bundle import
        length(bundle_listinteger_primes) == 1 &&
            _unique_names_in_bundle(bundle_listinteger_primes)
    end
    # DIVISORS
    @test begin
        int_divisors(1) == [1] &&
            int_divisors(-5) == [1, 5] &&
            int_divisors(10) == [1, 2, 5, 10]
    end
end
