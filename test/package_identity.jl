@testset "Package identity and environment configuration" begin
    @test nameof(MAGE) == :MAGE
    @test basename(pathof(MAGE)) == "MAGE.jl"
    @test string(Base.PkgId(MAGE).uuid) == "956831e1-0a7a-492a-ae16-058c6128a9f2"
    try
        withenv(
            "MAGE_CONSTRAINED" => "yes",
            "MAGE_MIN_INT" => "-17", "MAGE_MAX_INT" => "29",
            "MAGE_MIN_FLOAT" => "-13", "MAGE_MAX_FLOAT" => "31",
            "MAGE_NANO_ARRAY" => "19", "MAGE_SMALL_ARRAY" => "113",
            "MAGE_BIG_ARRAY" => "997", "MAGE_SAFE_CALL" => "yes",
        ) do
            MAGE.__init__()
            @test MAGE.CONSTRAINED[]
            @test (MAGE.MIN_INT[], MAGE.MAX_INT[]) == (-17, 29)
            @test (MAGE.MIN_FLOAT[], MAGE.MAX_FLOAT[]) == (-13, 31)
            @test (MAGE.NANO_ARRAY[], MAGE.SMALL_ARRAY[], MAGE.BIG_ARRAY[]) == (19, 113, 997)
            @test MAGE.SAFE_CALL[]
        end
    finally
        # Restore the caller's environment-derived settings even after a failure.
        MAGE.__init__()
    end
end
