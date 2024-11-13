
using ProgressMeter
using Test

@testset "ProgressThreads tests" begin
    threads = Threads.nthreads()
    println("Testing Progress() with Threads.@threads across $threads threads")
    (Threads.nthreads() == 1) && @info "Threads.nthreads() == 1, so Threads.@threads test is suboptimal"
    n = 20 #per thread
    threadsUsed = fill(false, threads)
    vals = ones(n*threads)
    p = Progress(n*threads)
    Threads.@threads for i = 1:(n*threads)
        threadsUsed[Threads.threadid()] = true
        vals[i] = 0
        sleep(0.1)
        next!(p)
    end
    @test !any(vals .== 1) #Check that all elements have been iterated
    @test all(threadsUsed) #Ensure that all threads are used

    println("Testing high-contention progress updates")
    function test_high_contention_progress()
        n_threads = Threads.nthreads()
        n_iterations = n_threads * 1000
        p = Progress(n_iterations)
        total_updates = Threads.Atomic{Int}(0)
        
        # Add different workload patterns
        workload_patterns = [
            () -> sleep(0.0001),  # Constant load
            () -> sleep(0.0001 * rand()),  # Random load
            () -> sleep(0.001 * (sin(time()) + 1)),  # Periodic load
        ]
        
        Threads.@threads for i in 1:n_iterations
            next!(p)
            Threads.atomic_add!(total_updates, 1)
            workload_patterns[1 + (i % length(workload_patterns))]()
        end
        
        # Verify all expected updates occurred
        @test total_updates[] == n_iterations
        @test p.counter == n_iterations
    end
    test_high_contention_progress()


    println("Testing ProgressUnknown() with Threads.@threads across $threads threads")
    trigger = 100.0
    prog = ProgressUnknown(desc="Attempts at exceeding trigger:")
    vals = Float64[]
    threadsUsed = fill(false, threads)
    lk = ReentrantLock()
    Threads.@threads for _ in 1:1000
        threadsUsed[Threads.threadid()] = true
        valssum = lock(lk) do
            push!(vals, rand())
            return sum(vals)
        end
        if valssum <= trigger
            next!(prog)
        elseif !prog.done
            finish!(prog)
            break
        else
            break
        end
        sleep(0.1*rand())
    end
    @test sum(vals) > trigger
    @test length(threadsUsed) == threads #Ensure that all threads are used


    println("Testing ProgressThresh() with Threads.@threads across $threads threads")
    thresh = 1.0
    prog = ProgressThresh(thresh; desc="Minimizing:")
    vals = fill(300.0, 1)
    threadsUsed = fill(false, threads)
    Threads.@threads for _ in 1:100000
        threadsUsed[Threads.threadid()] = true
        valssum = lock(lk) do
            push!(vals, -rand())
            return sum(vals)
        end
        if valssum > thresh
            update!(prog, valssum)
        else
            finish!(prog)
            break
        end
        sleep(0.1*rand())
    end
    @test sum(vals) <= thresh
    @test length(threadsUsed) == threads #Ensure that all threads are used

    if (Threads.nthreads() > 1)
        threads = Threads.nthreads() - 1
        println("Testing Progress() with Threads.@spawn across $threads threads")
        n = 20 #per thread
        tasks = Vector{Task}(undef, threads)
        # threadsUsed = fill(false, threads)
        vals = ones(n*threads)
        p = Progress(n*threads)

        for t in 1:threads
            tasks[t] = Threads.@spawn for i in 1:n
                # threadsUsed[Threads.threadid()] = true
                vals[(n*(t-1)) + i] = 0
                sleep(0.05 + (rand()*0.1))
                next!(p)
            end
        end
        wait.(tasks)
        @test !any(vals .== 1) #Check that all elements have been iterated
        # @test all(threadsUsed) #Ensure that all threads are used (unreliable for @spawn)
    else
        @info "Threads.nthreads() == 1, so Threads.@spawn tests cannot be meaningfully tested"
    end

    println("Testing @showprogress on a Threads.@threads for loop")
    function test_threaded_for_loop(n, dt, tsleep)
        result = zeros(n)
        @showprogress dt=dt Threads.@threads for i in 1:n
            if rand() < 0.7
                sleep(tsleep)
            end
            result[i] = i ^ 2
        end
        @test sum(result) == sum(abs2.(1:n))
    end
    test_threaded_for_loop(3000, 0.01, 0.001)
end
