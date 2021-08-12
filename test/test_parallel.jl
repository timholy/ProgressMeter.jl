using Distributed
using ProgressMeter: FakeChannel

nworkers() == 1 && addprocs(4)
@everywhere using ProgressMeter

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
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing update!")
    prog = Progress(100)
    p = ParallelProgress(prog)
    for _ in 1:25
        sleep(0.05)
        next!(p)
    end
    update!(p, 75)
    for _ in 76:100
        sleep(0.05)
        next!(p)
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing over-shooting")
    p = ParallelProgress(10)
    for _ in 1:100
        sleep(0.01)
        next!(p)
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing under-shooting")
    p = ParallelProgress(200)
    for _ in 1:100
        sleep(0.01)
        next!(p)
    end
    finish!(p)
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing rapid over-shooting")
    p = ParallelProgress(100)
    next!(p)
    sleep(0.1)
    for _ in 1:10000
        next!(p)
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing early cancel")
    p = ParallelProgress(100)
    for _ in 1:50
        sleep(0.02)
        next!(p)
    end
    cancel(p)
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing across $np workers with @distributed")
    n = 20 #per core
    p = ParallelProgress(n*np)
    @sync @distributed for _ in 1:n*np
        sleep(0.05)
        next!(p)
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing across $np workers with pmap")
    n = 20
    p = ParallelProgress(n*np)
    ids = pmap(1:n*np) do i
        sleep(0.05)
        next!(p)
        return myid()
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished
    @test length(unique(ids)) == np

    println("Testing changing color with next! and update!")
    p = ParallelProgress(100)
    for i in 1:100
        sleep(0.05)
        if i == 25
            next!(p, :red)
        elseif i == 50
            update!(p, 51, :blue)
        else
            next!(p)
        end
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing changing desc with next! and update!")
    p = ParallelProgress(100)
    for i in 1:100
        sleep(0.05)
        if i == 25
            next!(p, desc="25% done ")
        elseif i == 50
            update!(p, 51, desc="50% done ")
        else
            next!(p)
        end
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing with showvalues")
    p = ParallelProgress(100)
    for i in 1:100
        sleep(0.02)
        if i < 50
            next!(p; showvalues=Dict(:i => i, "longstring" => "ABCD"^i))
        else
            next!(p; showvalues=() -> [(:i, "$i"), ("halfdone", true)])
        end
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing with ProgressUnknown")
    p = ParallelProgress(ProgressUnknown())
    for i in 1:100
        sleep(0.02)
        next!(p)
    end
    sleep(0.5)
    update!(p, 200)
    sleep(0.5)
    @test !(p.channel isa FakeChannel) # ParallelProgress not finished
    finish!(p)
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    println("Testing with ProgressThresh")
    p = ParallelProgress(ProgressThresh(10))
    for i in 100:-1:0
        sleep(0.02)
        update!(p, i)
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished
end
