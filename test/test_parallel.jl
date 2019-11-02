
@testset "Testing ProgressThreads" begin
    !(Threads.nthreads() > 1) && @info "Threads.nthreads() == 1 so parallel tests cannot be meaningfully tested"
    n = 100
    p = ProgressThreads(n)
    vals = trues(n)
    Threads.@threads for i = 1:n
        vals[i] = false
        sleep(0.1)
        next!(p)
    end
    @test !any(vals)
end
