
@testset "ProgressThreads tests" begin
    threads = Threads.nthreads()
    println("Testing Progress() with Threads.@threads across $threads threads")
    (Threads.nthreads() == 1) && @info "Threads.nthreads() == 1, so Threads.@threads test is suboptimal"
    n = 20 #per thread
    threadsUsed = Int[]
    vals = ones(n*threads)
    p = ProgressMeter.Progress(n*threads)
    Threads.@threads for i = 1:(n*threads)
        !in(Threads.threadid(), threadsUsed) && push!(threadsUsed, Threads.threadid())
        vals[i] = 0
        sleep(0.1)
        ProgressMeter.next!(p)
    end
    @test !any(vals .== 1) #Check that all elements have been iterated
    @test length(threadsUsed) == threads #Ensure that all threads are used


    println("Testing ProgressUnknown() with Threads.@threads across $threads threads")
    trigger = 100.0
    prog = ProgressMeter.ProgressUnknown("Attepts at exceeding trigger:")
    vals = Float64[]
    threadsUsed = Int[]
    Threads.@threads for _ in 1:1000
        !in(Threads.threadid(), threadsUsed) && push!(threadsUsed, Threads.threadid())
        push!(vals, rand())
        valssum = sum(vals)
        if sum(vals) <= trigger
            ProgressMeter.next!(prog)
        elseif !prog.done
            ProgressMeter.finish!(prog)
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
    prog = ProgressMeter.ProgressThresh(thresh, "Minimizing:")
    vals = fill(300.0, 1)
    threadsUsed = Int[]
    Threads.@threads for _ in 1:100000
        !in(Threads.threadid(), threadsUsed) && push!(threadsUsed, Threads.threadid())
        push!(vals, -rand())
        valssum = sum(vals)
        if valssum > thresh
            ProgressMeter.update!(prog, valssum)
        else
            ProgressMeter.finish!(prog)
            break
        end
        sleep(0.1*rand())
    end
    @test sum(vals) <= thresh
    @test length(threadsUsed) == threads #Ensure that all threads are used


    @static if VERSION >= v"1.3.0-rc1" #Threads.@spawn not available before 1.3
        if (Threads.nthreads() > 1)
            threads = Threads.nthreads() - 1
            println("Testing Progress() with Threads.@spawn across $threads threads")
            n = 20 #per thread
            tasks = Vector{Task}(undef, threads)
            threadsUsed = Int[]
            vals = ones(n*threads)
            p = ProgressMeter.Progress(n*threads)
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
            #@test length(threadsUsed) == threads #Ensure that all threads are used (unreliable for @spawn)
        else
            @info "Threads.nthreads() == 1, so Threads.@spawn tests cannot be meaningfully tested"
        end
    end
end
