using UTCGP: listinteger_caster

@testset begin
    # VECTOR INT
    @test begin
        res = listinteger_caster([])
        isempty(res) && typeof(res) == Vector{Int64}
    end
    @test begin
        res = listinteger_caster([1, 1, 2])
        typeof(res) == Vector{Int64} && res[1] === 1
    end
    @test begin
        res = listinteger_caster([1.12, 1.13, 2.13])
        typeof(res) == Vector{Int64} && res[1] === 1
    end
end
