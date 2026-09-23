using Test
import ProgressMeter.ncalls

function testfunc15(n, dt, tsleep)
    result = @showprogress dt=dt @distributed (+) for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
        end
        i ^ 2
    end
    @test result == sum(abs2.(1:n))
end

println("Testing @showprogress macro on distributed for loop with reducer")
testfunc15(3000, 0.01, 0.001)

function testfunc16(n, dt, tsleep)
    @showprogress dt=dt desc="Description: " @distributed for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
        end
        i ^ 2
    end
end

println("Testing @showprogress macro on distributed for loop without reducer")
testfunc16(3000, 0.01, 0.001)

function testfunc16cb(N, dt, tsleep)
    @showprogress dt=dt @distributed for i in N
        if rand() < 0.7
            sleep(tsleep)
        end
        200 < i < 400 && continue
        i > 1500 && break
        i ^ 2
    end
end

println("Testing @showprogress macro on distributed for loop with continue")
testfunc16cb(1:1000, 0.01, 0.002)

println("Testing @showprogress macro on distributed for loop with break")
testfunc16cb(1000:2000, 0.01, 0.003)

function testfunc16d(n, dt, tsleep)
    @showprogress Distributed.@distributed for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
        end
        i ^ 2
    end
end

println("Testing @showprogress macro on Distributed.@distributed")
testfunc16d(3000, 0.01, 0.001)


println("testing `@showprogress @distributed` in global scope")
@showprogress @distributed for i in 1:10
    sleep(0.1)
    i^2
end

println("testing `@showprogress @distributed (+)` in global scope") #243
result = @showprogress @distributed (+) for i in 1:10
    sleep(0.1)
    i^2
end
@test result == sum(abs2, 1:10)

procs = addprocs(2)
wp = WorkerPool(procs)
@everywhere using ProgressMeter

@testset "pmap tests" begin
    println("Testing pmap")

    vals = progress_map(1:10, mapfun=pmap) do x
        sleep(0.1)
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    @test_throws RemoteException progress_map(1:10, mapfun=pmap) do x
        if x > 3
            error("intentional error")
        end
        return x^2
    end
    println()

    @test ncalls(pmap, +, 1:10, 1:100) == 10
    @test ncalls(pmap, +, wp, 1:10) == 10

    # a custom mapfun that runs f on workers still reaches the progress display
    myworkermap(f, x) = pmap(f, x)
    ProgressMeter.ncalls(::typeof(myworkermap), ::Function, args...) = ProgressMeter.ncalls_map(args...)
    p = Progress(10; output=devnull)
    vals = progress_map(x->x^2, 1:10; mapfun=myworkermap, progress=p)
    @test vals == map(x->x^2, 1:10)
    @test p.counter == 10

    vals = @showprogress pmap(1:10) do x
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    vals = @showprogress pmap(wp, 1:10) do x
        x^2
    end
    @test vals == map(x->x^2, 1:10)

    # function passed by name
    function testfun(x)
        return x^2
    end
    vals = @showprogress pmap(testfun, 1:10)
    @test vals == map(testfun, 1:10)
    vals = @showprogress pmap(testfun, wp, 1:10)
    @test vals == map(testfun, 1:10)

    # multiple args
    vals = @showprogress pmap((x,y)->x*y, 1:10, 2:11)
    @test vals == map((x,y)->x*y, 1:10, 2:11)

    # Progress args
    vals = @showprogress dt=0.1 desc="Computing" pmap(testfun, 1:10)
    @test vals == map(testfun, 1:10)

    # named vector arg
    a = collect(1:10)
    vals = @showprogress pmap(x->x^2, a)
    @test vals == map(x->x^2, a)

    # global variable in do
    C = 10
    vals = @showprogress pmap(1:10) do x
        return C*x
    end
    @test vals == map(x->C*x, 1:10)

    # keyword arguments
    vals = @showprogress pmap(x->x^2, 1:100, batch_size=10)
    @test vals == map(x->x^2, 1:100)
    # with semicolon
    vals = @showprogress pmap(x->x^2, 1:100; batch_size=10)
    @test vals == map(x->x^2, 1:100)

    # pipe + pmap
    sumvals = @showprogress pmap(testfun, 1:10) |> sum
    @test sumvals == sum(map(testfun, 1:10))
end

rmprocs(procs)
