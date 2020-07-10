using Distributed

if workers() != [1]
    rmprocs(workers())
end
addprocs(4)
@everywhere import ProgressMeter

@testset "ParallelProgress() tests" begin

    procs = nworkers()
    (procs == 1) && @info "incomplete tests: nworkers() == 1"
    @test all([@fetchfrom w @isdefined(ProgressMeter) for w in workers()])

    println("Testing simultaneous updates...")
    p = ProgressMeter.ParallelProgress(100)
    @sync for _ in 1:10
        @async for _ in 1:10
            sleep(0.1)
            ProgressMeter.next!(p)
        end
    end
    sleep(0.01)

    println("Testing over-shooting...")
    p = ProgressMeter.ParallelProgress(10)
    for _ in 1:100
        sleep(0.01)
        ProgressMeter.next!(p)
    end
    sleep(0.01)
    @test p.channel isa ProgressMeter.FakeChannel #ParallelProgress finished

    println("Testing under-shooting...")
    p = ProgressMeter.ParallelProgress(200)
    for _ in 1:100
        sleep(0.01)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
    sleep(0.01)
    @test p.channel isa ProgressMeter.FakeChannel #ParallelProgress finished

    println("Testing rapid over-shooting...")
    p = ProgressMeter.ParallelProgress(100)
    ProgressMeter.next!(p)
    sleep(0.1)
    for _ in 1:10000
        ProgressMeter.next!(p)
    end
    sleep(0.01)
    @test p.channel isa ProgressMeter.FakeChannel #ParallelProgress finished


    println("Testing early cancel...")
    p = ProgressMeter.ParallelProgress(100)
    for _ in 1:50
        sleep(0.02)
        ProgressMeter.next!(p)
    end
    ProgressMeter.cancel(p)
    sleep(0.01)
    @test p.channel isa ProgressMeter.FakeChannel #ParallelProgress finished



    println("Testing across $procs workers with @distributed...")
    n = 20 #per core
    p = ProgressMeter.ParallelProgress(n*procs)
    @sync @distributed for _ in 1:n*procs
        sleep(0.05)
        ProgressMeter.next!(p)
    end
    sleep(0.01)
    @test p.channel isa ProgressMeter.FakeChannel #ParallelProgress finished


    println("Testing across $procs workers with pmap...")
    n = 20
    p = ProgressMeter.ParallelProgress(n*procs)
    ids = pmap(1:n*procs) do i
        sleep(0.05)
        ProgressMeter.next!(p)
        return myid()
    end
    sleep(0.01)
    @test p.channel isa ProgressMeter.FakeChannel #ParallelProgress finished
    @test length(unique(ids)) == procs

end

@testset "MultipleProgress() tests" begin

    procs = nworkers()
    @test all([@fetchfrom w @isdefined(ProgressMeter) for w in workers()])

    function test_MP_finished(lengths, finish; kwargs...)
        n = length(lengths)
        p = ProgressMeter.MultipleProgress(lengths; kwargs...)
        for _ in 1:100
            sleep(0.01)
            for i in 1:n
                ProgressMeter.next!(p[i])
            end
        end
        finish && ProgressMeter.finish!(p)
        sleep(0.01)
        for i in 1:n
            @test p[i].channel.channel isa ProgressMeter.FakeChannel 
        end
    end

    println("Testing custom titles and color...")
    test_MP_finished([100, 100], false; 
                     desc="default ", color=:yellow, 
                     kws=[(desc=" task A ",), (desc=" task B ",)])

    println("Testing over-shooting and under-shooting...")
    test_MP_finished([10, 110], true; dt=0.01)

    println("Testing over-shooting with count_overshoot...")
    test_MP_finished([10, 190], false; count_overshoot=true, dt=0.01)


    println("Testing rapid over-shooting...")
    p = ProgressMeter.MultipleProgress([100]; dt=0.01, count_overshoot=true)
    ProgressMeter.next!(p[1])
    sleep(0.1)
    for _ in 1:10000
        ProgressMeter.next!(p[1])
    end
    sleep(0.01)
    @test p[1].channel.channel isa ProgressMeter.FakeChannel #ParallelProgress finished


    println("Testing early cancel...")
    p = ProgressMeter.MultipleProgress([100, 80])
    for _ in 1:50
        sleep(0.02)
        ProgressMeter.next!(p[1])
        ProgressMeter.next!(p[2])
    end
    ProgressMeter.cancel(p[1])
    ProgressMeter.finish!(p[2])
    sleep(0.1)
    @test p[1].channel.channel isa ProgressMeter.FakeChannel #ParallelProgress finished

    println("Testing early global cancel...")
    p = ProgressMeter.MultipleProgress([100, 80])
    for _ in 1:50
        sleep(0.02)
        ProgressMeter.next!(p[1])
        ProgressMeter.next!(p[2])
    end
    ProgressMeter.cancel(p)
    sleep(0.1)
    @test p[2].channel.channel isa ProgressMeter.FakeChannel #ParallelProgress finished

    println("Testing bar remplacement with $procs workers and pmap...")
    lengths = rand(20:40, 2*procs)
    p = ProgressMeter.MultipleProgress(lengths; dt=0.01, kws=[(desc=" task $i   ",) for i in 1:2*procs])
    ids = pmap(1:2*procs) do ip
        for _ in 1:lengths[ip]
            sleep(0.05)
            ProgressMeter.next!(p[ip])
        end
        myid()
    end
    sleep(0.01)
    @test length(unique(ids)) == procs
    @test p[1].channel.channel isa ProgressMeter.FakeChannel # finished

end
