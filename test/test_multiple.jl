using Distributed
using ProgressMeter: has_finished, isfakechannel

@testset "MultipleProgress() tests" begin

    np = nworkers()
    np == 1 && @info "incomplete tests: nworkers() == 1"
    @test all([@fetchfrom w @isdefined(ProgressMeter) for w in workers()])

    println("Testing MultipleProgress")

    c = Channel(10)
    @test !isfakechannel(c)
    close(c)

    println("Testing update!")
    p = MultipleProgress([Progress(100)])
    for _ in 1:5
        sleep(0.2)
        next!(p[1])
    end
    update!(p[1], 95)
    for _ in 96:99
        sleep(0.2)
        next!(p[1])
    end
    @test !waitfor(()->isfakechannel(p.channel))
    @test !isfakechannel(p[1].channel)
    @test !has_finished(p)
    next!(p[1])
    @test waitfor(()->isfakechannel(p.channel))
    @test isfakechannel(p[1].channel)
    @test has_finished(p)

    println("Testing MultipleProgress with custom titles and color")
    p = MultipleProgress(
        [Progress(10; color=:red, desc=" red "), 
         Progress(10; desc=" default color ")],
        kwmain=(desc="yellow ", color=:yellow)
    )
    for _ in 1:9
        sleep(0.1)
        next!.(p[1:2])
    end
    @test !waitfor(()->has_finished(p))
    next!.(p[1:2])
    @test waitfor(()->has_finished(p))

    println("Testing with Dicts, :main changes to red")
    p = MultipleProgress(
        Dict(:a => Progress(10, desc="task :a "),
             :b => Progress(10, desc="task :b ")),
        kwmain=(desc=":main ",)
    )
    @test p.main == :main
    for _ in 1:9
        sleep(0.1)
        next!(p[:a])
        next!(p[:b])
    end
    update!(p[:main], 18, color=:red)
    @test !has_finished(p)
    next!(p[:a])
    next!(p[:b])
    @test waitfor(()->has_finished(p))

    println("Testing forbidden main keys")
    @test_throws ErrorException MultipleProgress(
        Dict(:main => Progress(10, desc="task :a "),
             :b => Progress(10, desc="task :b ")),
    )
    @test_throws ErrorException MultipleProgress(
        Dict(0 => Progress(10, desc="task :a "),
             1 => Progress(10, desc="task :b ")),
    )
    @test_throws ErrorException MultipleProgress(
        Dict(:a => Progress(10, desc="task :a "),
             :b => Progress(10, desc="task :b "));
        main=:a
    )

    println("Testing adding same key twice (should display error)")
    p = MultipleProgress(; main="main", auto_close=false)
    p["a"] = Progress(10; color=:red)
    for i in 1:10
        sleep(0.1)
        next!(p["a"])
    end
    @test !waitfor(()->has_finished(p))
    println()
    p["a"] = Progress(100)
    @test waitfor(()->has_finished(p); tmax=5tmax)

    println("Testing over-shooting and under-shooting")
    p = MultipleProgress(Progress.([5, 14]), count_overshoot=false)
    for _ in 1:10
        sleep(0.1)
        next!.(p[1:2])
    end
    finish!(p[2])
    @test waitfor(()->has_finished(p))

    println("Testing over-shooting with count_overshoot")
    p = MultipleProgress(Progress.([5, 15]), count_overshoot=true)
    next!.(p[1:2])
    sleep(0.1)
    next!.(p[1:2])
    for _ in 1:15
        sleep(0.1)
        next!(p[2])
    end
    next!(p[2])
    @test waitfor(()->has_finished(p))

    println("Testing rapid over-shooting")
    p = MultipleProgress([Progress(10)], count_overshoot=true)
    next!(p[1])
    sleep(0.1)
    pmap(1:10000) do _
        next!(p[1])
    end
    @test waitfor(()->has_finished(p))

    println("Testing early cancel")
    p = MultipleProgress(Progress.([10, 8]))
    for _ in 1:5
        sleep(0.2)
        next!(p[1])
        next!(p[2])
    end
    cancel(p[1])
    finish!(p[2])
    @test waitfor(()->has_finished(p))

    println("Testing early cancel main progress")
    p = MultipleProgress(Progress.([10, 8]))
    for _ in 1:5
        sleep(0.2)
        next!(p[1])
        next!(p[2])
    end
    cancel(p[0])
    @test waitfor(()->has_finished(p))

    println("Testing early finish main progress")
    p = MultipleProgress(Progress.([10, 8]))
    for _ in 1:5
        sleep(0.2)
        next!(p[1])
        next!(p[2])
    end
    finish!(p[0])
    @test waitfor(()->has_finished(p))

    println("Testing next! on main progress")
    p = MultipleProgress([Progress(10)])
    for _ in 1:9
        sleep(0.02)
        next!(p[1])
    end
    next!(p[0])
    @test waitfor(()->has_finished(p))

    println("Testing bar remplacement with $np workers and pmap")
    lengths = rand(6:10, 2*np)
    progresses = [Progress(lengths[i], desc=" task $i ") for i in 1:2np]
    p = MultipleProgress(progresses)
    ids = pmap(1:2*np) do ip
        for _ in 1:lengths[ip]
            sleep(0.2)
            next!(p[ip])
        end
        myid()
    end
    @test waitfor(()->has_finished(p))
    @test length(unique(ids)) == np

    println("Testing changing color with next! and update!")
    p = MultipleProgress(Progress.([12,12]))
    for i in 1:12
        sleep(0.01)
        if i == 3
            next!(p[1], color=:red)
            next!(p[2])
        elseif i == 6
            next!(p[1])
            update!(p[2], 51, color=:blue)
        else
            if i == 9
                next!(p[0]; color=:yellow, step=0)
            end
            next!(p[1])
            next!(p[2])
        end
    end
    @test waitfor(()->has_finished(p))

    println("Testing changing desc with next! and update!")
    p = MultipleProgress(Progress.([10,10,10]))
    for i in 1:10
        sleep(0.5)
        if i == 2
            next!(p[1], desc="20% done ")
            next!.(p[2:3])
        elseif i == 4
            next!.(p[[1,3]])
            update!(p[2], 5, desc="40% done ")
        else
            if i == 6
                update!(p[0], desc="60% done ")
            elseif i == 8
                update!(p[3], desc="80% done ")
            end
            next!.(p[1:3])
        end
    end
    @test waitfor(()->has_finished(p))

    println("Update and finish all")
    p = MultipleProgress(Progress.([10,10,10]))
    for i in 1:100
        rand() < 0.9 && next!(p[1])
        rand() < 0.8 && next!(p[2])
        rand() < 0.7 && next!(p[3])
        sleep(0.2)
    end
    next!.(p[0:3], color=:red, step=0)
    sleep(0.5)
    finish!.(p[1:3])
    @test waitfor(()->has_finished(p))

    println("Testing without main progressmeter and offset 0 finishes last")
    p = MultipleProgress(Progress.([10,10,10]), kwmain=(enabled=false,))
    update!(p[0], 1, color=:red, desc="I shouldn't exist ")
    for i in 1:8
        next!(p[1], desc="task a ")
        rand() < 0.9 && next!(p[2], desc="task b ")
        rand() < 0.8 && next!(p[3], desc="task c ")
        sleep(0.2)
    end
    @test !waitfor(()->has_finished(p))
    finish!.(p[3:-1:1])
    @test waitfor(()->has_finished(p))

    println("Testing without main progressmeter and offset 0 finishes first (#215)")
    p = MultipleProgress(Progress.([10,10,10]), kwmain=(enabled=false,))
    update!(p[0], 1, color=:red, desc="I shouldn't exist ")
    for i in 1:9
        next!(p[1], desc="task a ")
        rand() < 0.9 && next!(p[2], desc="task b ")
        rand() < 0.8 && next!(p[3], desc="task c ")
        sleep(0.2)
    end
    finish!.(p[1:3])
    @test waitfor(()->has_finished(p))

    println("Testing early close (should not display error)")
    p = MultipleProgress([Progress(10, desc="Close test")])
    for i in 1:3
        sleep(0.1)
        next!(p[1])
    end
    close(p)
    @test waitfor(()->has_finished(p))

    println("Testing errors in MultipleProgress (should display error)")
    p = MultipleProgress(Progress.([10]), kwmain=(desc="Error test", color=:red))
    for i in 1:3
        sleep(0.1)
        next!(p[1])
    end
    next!(p[1], 1)
    @test waitfor(()->has_finished(p);tmax=10tmax)

    println("Testing with showvalues (doesn't really work)")
    p = MultipleProgress(Progress.([10,10]))
    for i in 1:10
        sleep(0.2)
        next!(p[1]; showvalues = Dict(:i=>i))
        next!(p[2]; showvalues = [i=>i, "longstring"=>"WXYZ"^i])
    end
    @test waitfor(()->has_finished(p))
    print("\n"^5)

    println("Testing with enabled=false")
    p = MultipleProgress(Progress.([100, 100]), Progress(200); enabled = false)
    @test has_finished(p)
    next!.(p[0:2])
    update!.(p[0:2])
    finish!.(p[0:2])
    cancel.(p[0:2])
    close(p)
    p[3] = Progress(100)

    println("Testing MultipleProgress with ProgressUnknown as mainprogress")
    p = MultipleProgress([Progress(10), ProgressUnknown(),ProgressThresh(0.1)]; count_finishes=false)
    for i in 1:10
        sleep(0.2)
        next!(p[1])
        next!(p[2])
        update!(p[3], 1/i)
    end
    @test !waitfor(()->has_finished(p))
    finish!(p[2])
    @test waitfor(()->has_finished(p))

    println("Testing MultipleProgress with count_finishes")
    p = MultipleProgress([ProgressUnknown(), Progress(5), ProgressThresh(0.5)]; 
                         count_finishes=true, kwmain=(dt=0, desc="Tasks finished "))
    update!(p[0], 0)
    for i in 1:10
        sleep(0.2)
        next!(p[1])
        next!(p[2])
        update!(p[3], 1/i)
    end
    @test !has_finished(p)
    finish!(p[1])
    @test waitfor(()->has_finished(p))

    N = 4*np
    println("Testing adding $N progresses with $np workers")
    p = MultipleProgress(Progress(N, desc="tasks done "); count_finishes=true)
    @test !has_finished(p)
    pmap(1:N) do ip
        L = rand(20:50)
        p[ip] = Progress(L, desc=" $(string(ip,pad=2)) (id=$(myid())) ")
        for _ in 1:L
            sleep(0.05)
            next!(p[ip])
        end
    end
    @test waitfor(()->has_finished(p))

    N = 4*np
    println("Testing adding $N mixed progresses with $np workers")
    p = MultipleProgress(ProgressUnknown(spinner=true))
    pmap(1:N) do ip
        L = rand(20:50)
        if ip%3 == 0
            p[ip] = Progress(L, desc=" $(string(ip,pad=2)) (id=$(myid())) ")
        elseif ip%3 == 1
            p[ip] = ProgressUnknown(desc=" $(string(ip,pad=2)) (id=$(myid())) ", spinner=true)
        else
            p[ip] = ProgressThresh(1/L, desc=" $(string(ip,pad=2)) (id=$(myid())) ")
        end
        for i in 1:L
            sleep(0.05)
            if ip%3 == 2
                update!(p[ip], 1/i)
            else
                next!(p[ip])
            end
        end
        ip%3 == 1 && finish!(p[ip])
    end
    finish!(p[0])
    @test waitfor(()->has_finished(p))
end