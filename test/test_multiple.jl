using Distributed
using ProgressMeter: FakeChannel

nworkers() == 1 && addprocs(4)
@everywhere using ProgressMeter

@testset "MultipleProgress() tests" begin

    procs = nworkers()
    procs == 1 && @info "incomplete tests: nworkers() == 1"
    @test all([@fetchfrom w @isdefined(ProgressMeter) for w in workers()])

    println("Testing MultipleProgress")
    println("Testing update!")
    p = MultipleProgress([100])
    for _ in 1:25
        sleep(0.05)
        next!(p[1])
    end
    update!(p[1], 75)
    for _ in 76:99
        sleep(0.05)
        next!(p[1])
    end
    sleep(0.1)
    @test !(p.channel isa FakeChannel) # ParallelProgress not finished yet
    next!(p[1])
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished

    function test_MP_finished(lengths, finish; kwargs...)
        n = length(lengths)
        p = MultipleProgress(lengths; kwargs...)
        for _ in 1:100
            sleep(0.01)
            for i in 1:n
                next!(p[i])
            end
        end
        finish && finish!(p[0])
        sleep(0.1)
        for i in 1:n
            @test p[i].channel.channel isa FakeChannel 
        end
    end

    println("Testing MultipleProgress with custom titles and color")
    test_MP_finished([100, 100], false; 
                     desc="yellow  ", color=:yellow, 
                     kws=[(desc="red " , color=:red ),
                          (desc="yellow too ", )])

    println("Testing over-shooting and under-shooting")
    test_MP_finished([10, 110], true; dt=0.01)

    println("Testing over-shooting with count_overshoot")
    test_MP_finished([10, 190], false; count_overshoot=true, dt=0.01)

    println("Testing rapid over-shooting")
    p = MultipleProgress([10]; dt=0.01, count_overshoot=true)
    next!(p[1])
    sleep(0.1)
    for i in 1:10000
        next!(p[1])
    end
    sleep(0.1)
    @test p[1].channel.channel isa FakeChannel # ParallelProgress finished

    println("Testing early cancel")
    p = MultipleProgress([100, 80])
    for _ in 1:50
        sleep(0.02)
        next!(p[1])
        next!(p[2])
    end
    cancel(p[1])
    finish!(p[2])
    sleep(0.1)
    @test p[1].channel.channel isa FakeChannel # ParallelProgress finished

    println("Testing early global cancel")
    p = MultipleProgress([100, 80])
    for _ in 1:50
        sleep(0.02)
        next!(p[1])
        next!(p[2])
    end
    cancel(p[0])
    sleep(0.1)
    @test p[2].channel.channel isa FakeChannel # ParallelProgress finished

    println("Testing bar remplacement with $procs workers and pmap")
    lengths = rand(20:40, 2*procs)
    p = MultipleProgress(lengths; dt=0.01, kws=[(desc=" task $i   ",) for i in 1:2*procs])
    ids = pmap(1:2*procs) do ip
        for _ in 1:lengths[ip]
            sleep(0.05)
            next!(p[ip])
        end
        myid()
    end
    sleep(0.1)
    @test length(unique(ids)) == procs
    @test p[1].channel.channel isa FakeChannel # finished

    println("Testing changing color with next! and update!")
    p = MultipleProgress([100,100])
    for i in 1:100
        sleep(0.01)
        if i == 25
            next!(p[1], :red)
            next!(p[2])
        elseif i == 50
            next!(p[1])
            update!(p[2], 51, :blue)
        else
            if i == 75
                update!(p[0], :, :yellow)
            end
            next!(p[1])
            next!(p[2])
        end
    end
    sleep(0.1)
    @test p[1].channel.channel isa FakeChannel

    println("Testing changing desc with next! and update!")
    p = MultipleProgress([100,100])
    for i in 1:100
        sleep(0.05)
        if i == 25
            next!(p[1], desc="25% done ")
            next!(p[2])
        elseif i == 50
            next!(p[1])
            update!(p[2], 51, desc="50% done ")
        else
            if i == 75
                update!(p[0], desc="75% done ")
            end
            next!(p[1])
            next!(p[2])
        end
    end
    sleep(0.1)
    @test p[1].channel.channel isa FakeChannel # ParallelProgress finished

    println("Update and finish all")
    p = MultipleProgress([100,100,100])
    for i in 1:100
        rand() < 0.5 && next!(p[1])
        rand() < 0.3 && next!(p[2])
        rand() < 0.1 && next!(p[3])
        sleep(0.02)
    end
    update!.(p[0:end], :, :red)
    sleep(0.5)
    finish!.(p[1:end])
    sleep(0.1)
    @test p[1].channel.channel isa FakeChannel # ParallelProgress finished

    println("Testing without main progressmeter and closing without finish")
    p = MultipleProgress([100,100,100], mainprogress=false)
    update!(p[0], 10, :red, desc="I shouldn't exist ")
    for i in 1:100
        rand() < 0.5 && next!(p[1], desc="task a ")
        rand() < 0.3 && next!(p[2], desc="task b ")
        rand() < 0.1 && next!(p[3], desc="task c ")
        sleep(0.02)
    end
    sleep(0.1)
    @test !(p.channel isa FakeChannel) # ParallelProgress not finished yet
    close(p)
    @test p.channel isa FakeChannel # ParallelProgress finished
    print("\n"^3)


    println("Testing with showvalues (doesn't really work)")
    p = MultipleProgress([100,100])
    for i in 1:100
        sleep(0.02)
        next!(p[1]; showvalues = Dict(:i=>i))
        next!(p[2]; showvalues = [i=>i, "longstring"=>"WXYZ"^i])
    end
    sleep(0.1)
    @test p.channel isa FakeChannel # ParallelProgress finished
end
