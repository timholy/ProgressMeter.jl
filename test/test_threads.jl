
@testset "ProgressThreads tests" begin
    threads = Threads.nthreads()
    println("Testing ProgressThreads with Threads.@threads across $threads threads")
    (Threads.nthreads() == 1) && @info "Threads.nthreads() == 1, so Threads.@threads test is suboptimal"
    n = 20 #per thread
    threadsUsed = Int[]
    vals = ones(n*threads)
    p = ProgressMeter.ProgressThreads(n*threads)
    Threads.@threads for i = 1:(n*threads)
        !in(Threads.threadid(), threadsUsed) && push!(threadsUsed, Threads.threadid())
        vals[i] = 0
        sleep(0.1)
        ProgressMeter.next!(p)
    end
    @test !any(vals .== 1) #Check that all elements have been iterated
    @test length(threadsUsed) == threads #Ensure that all threads are used


    if (Threads.nthreads() > 1)
        threads = Threads.nthreads() - 1
        println("Testing ProgressThreads with Threads.@spawn across $threads threads")
        n = 20 #per thread
        tasks = Vector{Task}(undef, threads)
        threadsUsed = Int[]
        vals = ones(n*threads)
        p = ProgressMeter.ProgressThreads(n*threads)
        for t in 1:threads
            tasks[t] = Threads.@spawn for i in 1:n
                !in(Threads.threadid(), threadsUsed) && push!(threadsUsed, Threads.threadid())
                vals[(n*(t-1)) + i] = 0
                sleep(0.05 + (rand()*0.1))
                ProgressMeter.next!(p)
            end
        end
        wait.(tasks)
        @test !any(vals .== 1) #Check that all elements have been iterated
        @test length(threadsUsed) == threads #Ensure that all threads are used
    else
        @info "Threads.nthreads() == 1, so Threads.@spawn tests cannot be meaningfully tested"
    end
end
