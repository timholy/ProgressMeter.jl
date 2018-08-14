using Test
using ProgressMeter
using Distributed

@testset "map tests" begin
    vals = progress_map(1:10) do x
        sleep(0.1)
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    @test_throws CompositeException progress_map(1:10) do x
        if x > 3
            error("intentional error")
        end
        return x^2
    end
    println()

    vals = progress_map(1:10, mapfun=pmap) do x
        sleep(0.1)
        return x^2
    end
    @test vals == map(x->x^2, 1:10)
end
