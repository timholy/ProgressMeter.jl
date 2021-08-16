using Distributed
using ProgressMeter: has_finished

nworkers() == 1 && addprocs(4)
@everywhere using ProgressMeter

@testset "MultipleProgress() tests" begin

    np = nworkers()
    np == 1 && @info "incomplete tests: nworkers() == 1"
    @test all([@fetchfrom w @isdefined(ProgressMeter) for w in workers()])

    println("Testing MultipleProgress")
    println("Testing update!")
    p = MultipleProgress([Progress(100)])
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
    @test !has_finished(p)
    next!(p[1])
    sleep(0.1)
    @test has_finished(p)


    # println("Testing MultipleProgress with custom titles and color")
    # p = MultipleProgress(
    #     [Progress(100; color=:red, desc=" red "), 
    #      Progress(100; desc=" default color ")],
    #     kwmain=(desc="yellow ", color=:yellow)
    # )
    # for _ in 1:99
    #     sleep(0.01)
    #     next!.(p[1:2])
    # end
    # sleep(0.1)
    # @test !has_finished(p)
    # next!.(p[1:2])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing over-shooting and under-shooting")
    # p = MultipleProgress(Progress.([50, 140]), count_overshoot=false)
    # for _ in 1:100
    #     sleep(0.01)
    #     next!.(p[1:2])
    # end
    # sleep(0.1)
    # @test !has_finished(p)
    # finish!(p[2])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing over-shooting with count_overshoot")
    # p = MultipleProgress(Progress.([52, 153]), count_overshoot=true)
    # next!.(p[1:2])
    # sleep(0.1)
    # next!.(p[1:2])
    # for _ in 1:200
    #     sleep(0.01)
    #     next!(p[2])
    # end
    # sleep(0.1)
    # @test !has_finished(p)
    # next!(p[2])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing rapid over-shooting")
    # p = MultipleProgress([Progress(10)], count_overshoot=true)
    # next!(p[1])
    # sleep(0.1)
    # for i in 1:10000
    #     next!(p[1])
    # end
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing early cancel")
    # p = MultipleProgress(Progress.([100, 80]))
    # for _ in 1:50
    #     sleep(0.02)
    #     next!(p[1])
    #     next!(p[2])
    # end
    # cancel(p[1])
    # finish!(p[2])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing early cancel main progress")
    # p = MultipleProgress(Progress.([100, 80]))
    # for _ in 1:50
    #     sleep(0.02)
    #     next!(p[1])
    #     next!(p[2])
    # end
    # cancel(p[0])
    # sleep(0.1)
    # @test has_finished(p)


    # println("Testing early finish main progress")
    # p = MultipleProgress(Progress.([100, 80]))
    # for _ in 1:50
    #     sleep(0.02)
    #     next!(p[1])
    #     next!(p[2])
    # end
    # finish!(p[0])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing next! on main progress")
    # p = MultipleProgress([Progress(100)])
    # for _ in 1:99
    #     sleep(0.02)
    #     next!(p[1])
    # end
    # sleep(0.1)
    # @test !has_finished(p)
    # next!(p[0])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing bar remplacement with $np workers and pmap")
    # lengths = rand(20:50, 2*np)
    # progresses = [Progress(lengths[i], desc=" task $i ") for i in 1:2np]
    # p = MultipleProgress(progresses)
    # ids = pmap(1:2*np) do ip
    #     for _ in 1:lengths[ip]
    #         sleep(0.05)
    #         next!(p[ip])
    #     end
    #     myid()
    # end
    # sleep(0.1)
    # @test length(unique(ids)) == np
    # @test has_finished(p)

    # println("Testing changing color with next! and update!")
    # p = MultipleProgress(Progress.([100,100]))
    # for i in 1:100
    #     sleep(0.01)
    #     if i == 25
    #         next!(p[1], :red)
    #         next!(p[2])
    #     elseif i == 50
    #         next!(p[1])
    #         update!(p[2], 51, :blue)
    #     else
    #         if i == 75
    #             update!(p[0], :, :yellow)
    #         end
    #         next!(p[1])
    #         next!(p[2])
    #     end
    # end
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing changing desc with next! and update!")
    # p = MultipleProgress(Progress.([100,100,100]))
    # for i in 1:100
    #     sleep(0.05)
    #     if i == 20
    #         next!(p[1], desc="20% done ")
    #         next!.(p[2:3])
    #     elseif i == 40
    #         next!.(p[[1,3]])
    #         update!(p[2], 41, desc="40% done ")
    #     else
    #         if i == 60
    #             update!(p[0], desc="60% done ")
    #         elseif i == 80
    #             update!(p[3], desc="80% done ")
    #         end
    #         next!.(p[1:3])
    #     end
    # end
    # sleep(0.1)
    # @test has_finished(p)

    # println("Update and finish all")
    # p = MultipleProgress(Progress.([100,100,100]))
    # for i in 1:100
    #     rand() < 0.5 && next!(p[1])
    #     rand() < 0.3 && next!(p[2])
    #     rand() < 0.1 && next!(p[3])
    #     sleep(0.02)
    # end
    # update!.(p[0:end], :, :red)
    # sleep(0.5)
    # finish!.(p[1:end])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing without main progressmeter and offset 0 finishes last")
    # p = MultipleProgress(Progress.([100,100,100]), kwmain=(enabled=false,))
    # update!(p[0], 10, :red, desc="I shouldn't exist ")
    # for i in 1:80
    #     next!(p[1], desc="task a ")
    #     rand() < 0.7 && next!(p[2], desc="task b ")
    #     rand() < 0.4 && next!(p[3], desc="task c ")
    #     sleep(0.02)
    # end
    # sleep(0.1)
    # @test !has_finished(p)
    # finish!.(p[end:-1:1])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing without main progressmeter and offset 0 finishes first (#215)")
    # p = MultipleProgress(Progress.([100,100,100]), kwmain=(enabled=false,))
    # update!(p[0], 10, :red, desc="I shouldn't exist ")
    # for i in 1:80
    #     next!(p[1], desc="task a ")
    #     rand() < 0.7 && next!(p[2], desc="task b ")
    #     rand() < 0.4 && next!(p[3], desc="task c ")
    #     sleep(0.02)
    # end
    # sleep(0.1)
    # @test !has_finished(p)
    # finish!.(p[1:end])
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing early close (should not display error)")
    # p = MultipleProgress([Progress(100, desc="Close test")])
    # for i in 1:30
    #     sleep(0.01)
    #     next!(p[1])
    # end
    # sleep(0.1)
    # @test !has_finished(p)
    # close(p)
    # sleep(0.1)
    # @test has_finished(p)

    # println("Testing errors in MultipleProgress (should display error)")
    # p = MultipleProgress(Progress.([100]), kwmain=(desc="Error test", color=:red))
    # for i in 1:30
    #     sleep(0.01)
    #     next!(p[1])
    # end
    # next!(p[1], 1)
    # sleep(2)
    # @test has_finished(p)

    println("Testing with showvalues (doesn't really work)")
    p = MultipleProgress(Progress.([100,100]))
    for i in 1:100
        sleep(0.02)
        next!(p[1]; showvalues = Dict(:i=>i))
        next!(p[2]; showvalues = [i=>i, "longstring"=>"WXYZ"^i])
    end
    sleep(0.1)
    @test has_finished(p)

    println("Testing MultipleProgress with ProgressUnknown")
    p = MultipleProgress([Progress(100), Progress(100)], ProgressUnknown(); count_finishes=false)
    for i in 1:100
        sleep(0.01)
        next!(p[1])
        rand() < 0.5 && next!(p[2])
    end
    sleep(0.1)
    @test !has_finished(p)
    finish!(p[2])
    sleep(0.1)
    @test has_finished(p)
end
