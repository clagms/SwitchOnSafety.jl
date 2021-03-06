@testset "Veronese Lift" begin
    @test_throws DimensionMismatch permanent([1 2])
    @test_throws DimensionMismatch veroneselift([1 2], 3)
    @test_throws ArgumentError veroneselift([1 2; 3 4], 0)

    obtained = veroneselift([11 12; 21 22], 3)
    s3 = sqrt(3)
    expected = [11^3 s3*11^2*12 s3*11*12^2 12^3;
    s3*11^2*21 11*(11*22+2*21*12) 12*(2*11*22+21*12) s3*12^2*22;
    s3*11*21^2 21*(2*11*22+21*12) 22*(11*22+2*21*12) sqrt(3)*12*22^2;
    21^3 s3*21^2*22 s3*21*22^2 22^3]
    @test isapprox(obtained, expected)
end
