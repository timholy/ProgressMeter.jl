using Test
using Distributed
procs = addprocs(2)
@everywhere using ProgressMeter

@testset "map tests" begin
    println("Testing map functions")

    # basic
    vals = progress_map(1:10) do x
        sleep(0.1)
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    vals = progress_map(1:10, mapfun=pmap) do x
        sleep(0.1)
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    val = progress_map(1:10, mapfun=reduce) do x, y
        sleep(0.1)
        return x+y
    end
    @test val == reduce((x,y)->x+y, 1:10)

    # errors
    @test_throws ErrorException progress_map(1:10) do x
        if x > 3
            error("intentional error")
        end
        return x^2
    end
    println()

    @test_throws RemoteException progress_map(1:10, mapfun=pmap) do x
        if x > 3
            error("intentional error")
        end
        return x^2
    end
    println()

    @test_throws ErrorException progress_map(1:10, mapfun=reduce) do x, y
        if x > 3
            error("intentional error")
        end
        return x + y
    end
    println()

    # @showprogress
    vals = @showprogress map(1:10) do x
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    vals = @showprogress pmap(1:10) do x
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    val = @showprogress reduce(1:10) do x, y
        return x + y
    end
    @test val == reduce((x, y)->x+y, 1:10)
    
    # function passed by name
    function testfun(x)
        return x^2
    end
    vals = @showprogress map(testfun, 1:10)
    @test vals == map(testfun, 1:10)
    vals = @showprogress pmap(testfun, 1:10)
    @test vals == map(testfun, 1:10)
    val = @showprogress reduce(+, 1:10)
    @test val == reduce(+, 1:10)

    # #136: make sure mid progress shows up even without sleep
    println("Verify that intermediate progress is displayed:")
    @showprogress map(1:100) do i
        A = rand(10000,1000)
        sum(A)
    end

    # multiple args
    vals = @showprogress pmap((x,y)->x*y, 1:10, 2:11)
    @test vals == map((x,y)->x*y, 1:10, 2:11)



    # abstract worker pool arg
    wp = WorkerPool(procs)
    vals = @showprogress pmap(testfun, wp, 1:10)
    @test vals == map(testfun, 1:10)

    vals = @showprogress pmap(wp, 1:10) do x
        x^2
    end
    @test vals == map(testfun, 1:10)



    # Progress args
    vals = @showprogress 0.1 "Computing" pmap(testfun, 1:10)
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

    
    # pipes after map
    @showprogress map(testfun, 1:10) |> sum |> length

    # pipes after map do block
    vals = @showprogress map(1:10) do x
        sleep(.1)
        return x => x^2
    end |> Dict
    @test vals == Dict(x=>x^2 for x in 1:10)

    # pipe + pmap
    sumvals = @showprogress pmap(testfun, 1:10) |> sum
    @test sumvals == sum(map(testfun, 1:10))
    
end

rmprocs(procs)
