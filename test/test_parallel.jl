using Distributed
using ProgressMeter: has_finished

nworkers() == 1 && addprocs(4)
@everywhere using ProgressMeter

# additional time before checking if progressbar has finished during CI
if get(ENV, "CI", "false") == "true"
    s = 0.1
else
    s = 1.0
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
    sleep(s)
    @test has_finished(p)

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
    sleep(s)
    @test has_finished(p)

    println("Testing over-shooting")
    p = ParallelProgress(10)
    for _ in 1:100
        sleep(0.01)
        next!(p)
    end
    sleep(s)
    @test has_finished(p)

    println("Testing under-shooting")
    p = ParallelProgress(200)
    for _ in 1:10
        sleep(0.1)
        next!(p)
    end
    finish!(p)
    sleep(s)
    @test has_finished(p)

    println("Testing rapid over-shooting")
    p = ParallelProgress(10)
    next!(p)
    sleep(0.1)
    for _ in 1:10000
        next!(p)
    end
    sleep(s)
    @test has_finished(p)

    println("Testing early cancel")
    p = ParallelProgress(10)
    for _ in 1:5
        sleep(0.2)
        next!(p)
    end
    cancel(p)
    sleep(s)
    @test has_finished(p)

    println("Testing across $np workers with @distributed")
    n = 10 #per core
    p = ParallelProgress(n*np)
    @sync @distributed for _ in 1:n*np
        sleep(0.2)
        next!(p)
    end
    sleep(s)
    @test has_finished(p)

    println("Testing across $np workers with pmap")
    n = 10
    p = ParallelProgress(n*np)
    ids = pmap(1:n*np) do i
        sleep(0.2)
        next!(p)
        return myid()
    end
    sleep(s)
    @test has_finished(p)
    @test length(unique(ids)) == np

    println("Testing changing color with next! and update!")
    p = ParallelProgress(10)
    for i in 1:10
        sleep(0.5)
        if i == 3
            next!(p, :red)
        elseif i == 6
            update!(p, 7, :blue)
        else
            next!(p)
        end
    end
    sleep(s)
    @test has_finished(p)

    println("Testing changing desc with next! and update!")
    p = ParallelProgress(10)
    for i in 1:10
        sleep(0.5)
        if i == 3
            next!(p, desc="30% done ")
        elseif i == 6
            update!(p, 7, desc="60% done ")
        else
            next!(p)
        end
    end
    sleep(s)
    @test has_finished(p)

    println("Testing with showvalues")
    p = ParallelProgress(20)
    for i in 1:20
        sleep(0.1)
        if i < 10
            next!(p; showvalues=Dict(:i => i, "longstring" => "ABCD"^i))
        else
            next!(p; showvalues=() -> [(:i, "$i"), ("halfdone", true)])
        end
    end
    sleep(s)
    @test has_finished(p)

    println("Testing with ProgressUnknown")
    p = ParallelProgress(ProgressUnknown())
    for i in 1:10
        sleep(0.2)
        next!(p)
    end
    sleep(0.5)
    update!(p, 200)
    sleep(5s)
    @test !has_finished(p)
    finish!(p)
    sleep(s)
    @test has_finished(p)

    println("Testing with ProgressThresh")
    p = ParallelProgress(ProgressThresh(10))
    for i in 20:-1:0
        sleep(0.2)
        update!(p, i)
    end
    sleep(s)
    @test has_finished(p)

    println("Testing early close (should not display error)")
    p = ParallelProgress(10, desc="Close test")
    for i in 1:3
        sleep(0.1)
        next!(p)
    end
    sleep(s)
    @test !has_finished(p)
    close(p)
    sleep(s)
    @test has_finished(p)

    println("Testing errors in ParallelProgress (should display error)")
    @test_throws MethodError next!(Progress(10), 1)
    p = ParallelProgress(10, desc="Error test", color=:red)
    for i in 1:3
        sleep(0.1)
        next!(p)
    end
    next!(p, 1)
    sleep(30s)
    @test has_finished(p)
end
