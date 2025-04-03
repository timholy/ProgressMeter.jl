using Distributed
using ProgressMeter: has_finished

nworkers() == 1 && addprocs(4)
@everywhere using ProgressMeter

# additional time before checking if progressbar has finished during CI
if get(ENV, "CI", "false") == "true"
    dt = 0.1
    tmax = 5
else
    dt = 0.1
    tmax = 1
end

function waitfor(f; tmax=tmax, dt=dt)
    t0 = time()
    while time() - t0 < tmax
        f() && return true
        sleep(dt)
    end
    return false
end

@testset "ParallelProgress() tests" begin

    np = nworkers()
    np == 1 && @info "incomplete tests: nworkers() == 1"
    @test all([@fetchfrom w @isdefined(ProgressMeter) for w in workers()])

    println("Testing ParallelProgress")
    println("Testing simultaneous updates")
    p = ParallelProgress(100)
    @sync for _ in 1:10
        @async for _ in 1:10
            sleep(0.1)
            next!(p)
        end
    end
    @test waitfor(()->has_finished(p))

    println("Testing update!")
    prog = Progress(100)
    p = ParallelProgress(prog)
    for _ in 1:5
        sleep(0.3)
        next!(p)
    end
    update!(p, 95)
    for _ in 96:100
        sleep(0.3)
        next!(p)
    end
    @test waitfor(()->has_finished(p))

    println("Testing over-shooting")
    p = ParallelProgress(10)
    for _ in 1:100
        sleep(0.01)
        next!(p)
    end
    @test waitfor(()->has_finished(p))

    println("Testing under-shooting")
    p = ParallelProgress(200)
    for _ in 1:10
        sleep(0.1)
        next!(p)
    end
    finish!(p)
    @test waitfor(()->has_finished(p))

    println("Testing rapid over-shooting")
    p = ParallelProgress(10)
    next!(p)
    sleep(0.1)
    for _ in 1:10000
        next!(p)
    end
    @test waitfor(()->has_finished(p))

    println("Testing early cancel")
    p = ParallelProgress(10)
    for _ in 1:5
        sleep(0.2)
        next!(p)
    end
    cancel(p)
    @test waitfor(()->has_finished(p))

    println("Testing across $np workers with @distributed")
    n = 10 #per core
    p = ParallelProgress(n*np)
    @sync @distributed for _ in 1:n*np
        sleep(0.2)
        next!(p)
    end
    @test waitfor(()->has_finished(p))

    println("Testing across $np workers with @distributed and reduce")
    n = 10 #per core
    p = ParallelProgress(n*np)
    res = @distributed (+) for i in 1:n*np
        sleep(0.2)
        next!(p)
        i^2
    end
    @test res == sum(i->i^2, 1:n*np)
    @test waitfor(()->has_finished(p))

    println("Testing across $np workers with pmap")
    n = 10
    p = ParallelProgress(n*np)
    ids = pmap(1:n*np) do i
        sleep(0.2)
        next!(p)
        return myid()
    end
    @test waitfor(()->has_finished(p))
    @test length(unique(ids)) == np

    println("Testing changing color with next! and update!")
    p = ParallelProgress(10)
    for i in 1:10
        sleep(0.5)
        if i == 3
            next!(p; color=:red)
        elseif i == 6
            update!(p, 7; color=:blue)
        else
            next!(p)
        end
    end
    @test waitfor(()->has_finished(p))

    println("Testing changing desc with next! and update!")
    p = ParallelProgress(10)
    for i in 1:10
        sleep(0.5)
        if i == 3
            next!(p; desc="30% done ")
        elseif i == 6
            update!(p, 7; desc="60% done ")
        else
            next!(p)
        end
    end
    @test waitfor(()->has_finished(p))

    println("Testing with showvalues")
    p = ParallelProgress(20)
    for i in 1:20
        sleep(0.1)
        # if i < 10
            next!(p; showvalues=Dict(:i => i, "longstring" => "ABCD"^i))
        # else #? lazy broken?
        #     next!(p; showvalues=() -> [(:i, "$i"), ("halfdone", true)])
        # end
    end
    @test waitfor(()->has_finished(p))

    println("Testing with ProgressUnknown")
    p = ParallelProgress(ProgressUnknown())
    for i in 1:10
        sleep(0.2)
        next!(p)
    end
    sleep(0.5)
    update!(p, 200)
    @test !waitfor(()->has_finished(p))
    finish!(p)
    @test waitfor(()->has_finished(p))

    println("Testing with ProgressThresh")
    p = ParallelProgress(ProgressThresh(10))
    for i in 20:-1:0
        sleep(0.2)
        update!(p, i)
    end
    @test waitfor(()->has_finished(p))

    println("Testing early close (should not display error)")
    p = ParallelProgress(10; desc="Close test")
    for i in 1:3
        sleep(0.1)
        next!(p)
    end
    @test !waitfor(()->has_finished(p))
    close(p)
    @test waitfor(()->has_finished(p))

    println("Testing errors in ParallelProgress (should display error)")
    @test_throws MethodError next!(Progress(10), 1)
    p = ParallelProgress(10, desc="Error test", color=:red)
    for i in 1:3
        sleep(0.1)
        next!(p)
    end
    next!(p, 1)
    @test waitfor(()->has_finished(p); tmax=10tmax)
    sleep(1)
end
