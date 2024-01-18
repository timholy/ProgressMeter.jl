using Test
using Distributed
import ProgressMeter.ncalls

procs = addprocs(2)
wp = WorkerPool(procs)
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

    # test ncalls
    @test ncalls(map, (+, 1:10)) == 10
    @test ncalls(pmap, (+, 1:10, 1:100)) == 10
    @test ncalls(pmap, (+, wp, 1:10)) == 10
    @test ncalls(reduce, (+, 1:10)) == 10
    @test ncalls(mapreduce, (+, +, 1:10, (1:10)')) == 10
    @test ncalls(mapfoldl, (+, +, 1:10, (1:10)')) == 10
    @test ncalls(mapfoldr, (+, +, 1:10, (1:10)')) == 10
    @test ncalls(foreach, (+, 1:10)) == 10
    @test ncalls(broadcast, (+, 1:10, 1:10)) == 10
    @test ncalls(broadcast, (+, 1:8, (1:7)', 1)) == 8*7
    @test ncalls(broadcast, (+, 1:3, (1:5)', ones(1,1,2))) == 3*5*2
    @test ncalls(broadcast!, (+, zeros(10,8))) == 80
    @test ncalls(broadcast!, (+, zeros(10,8,7), 1:10)) == 10*8*7

    @test ncalls(map, (time,)) == 1
    @test ncalls(foreach, (time,)) == 1
    @test ncalls(broadcast, (time,)) == 1
    @test ncalls(broadcast!, (time, [1])) == 1
    @test ncalls(mapreduce, (time, +)) == 1

    @test_throws DimensionMismatch ncalls(broadcast, (+, 1:10, 1:100))
    @test_throws DimensionMismatch ncalls(broadcast, (+, 1:100, 1:10))

    # @showprogress
    vals = @showprogress map(1:10) do x
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    vals = @showprogress asyncmap(1:10) do x
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    vals = @showprogress pmap(1:10) do x
        return x^2
    end
    @test vals == map(x->x^2, 1:10)

    vals = @showprogress pmap(wp, 1:10) do x
        x^2
    end
    @test vals == map(x->x^2, 1:10)

    val = @showprogress reduce(1:10) do x, y
        return x + y
    end
    @test val == reduce((x, y)->x+y, 1:10)

    val = @showprogress mapreduce(+, 1:10) do x
        return x^2
    end
    @test val == mapreduce(x->x^2, +, 1:10)
    
    val = @showprogress mapfoldl(-, 1:10) do x
        return x^2
    end
    @test val == mapfoldl(x->x^2, -, 1:10)

    val = @showprogress mapfoldr(-, 1:10) do x
        return x^2
    end
    @test val == mapfoldr(x->x^2, -, 1:10)

    @showprogress foreach(1:10) do x
        print(x)
    end

    val = @showprogress broadcast(1:10, (1:10)') do x,y
        return x+y
    end
    @test val == broadcast(+, 1:10, (1:10)')

    A = zeros(10,8)
    @showprogress broadcast!(A, 1:10, (1:8)') do x,y
        return x+y
    end
    @test A == broadcast(+, 1:10, (1:8)')

    @showprogress broadcast!(A, 1:10) do x
        return x
    end
    @test A == repeat(1:10, 1, 8)



    # function passed by name
    function testfun(x)
        return x^2
    end
    vals = @showprogress map(testfun, 1:10)
    @test vals == map(testfun, 1:10)
    vals = @showprogress pmap(testfun, 1:10)
    @test vals == map(testfun, 1:10)
    vals = @showprogress pmap(testfun, wp, 1:10)
    @test vals == map(testfun, 1:10)
    val = @showprogress reduce(+, 1:10)
    @test val == reduce(+, 1:10)
    val = @showprogress mapreduce(testfun, +, 1:10)
    @test val == mapreduce(testfun, +, 1:10)
    val = @showprogress mapfoldl(testfun, -, 1:10)
    @test val == mapfoldl(testfun, -, 1:10)
    val = @showprogress mapfoldr(testfun, -, 1:10)
    @test val == mapfoldr(testfun, -, 1:10)
    @showprogress foreach(print, 1:10)
    println()
    val = @showprogress broadcast(+, 1:10, (1:12)')
    @test val == broadcast(+, 1:10, (1:12)')
    @showprogress broadcast!(+, A, 1:10, 1:10, (1:8)', 3)
    @test A == broadcast(+, 1:10, 1:10, (1:8)', 3)

    # test function with no arg
    function constfun()
        return 42
    end
    @test broadcast(constfun) == @showprogress broadcast(constfun)
    #@test mapreduce(constfun, error) == @showprogress mapreduce(constfun, error) # julia 1.2+


    # #136: make sure mid progress shows up even without sleep
    println("Verify that intermediate progress is displayed:")
    @showprogress map(1:100) do i
        A = rand(10000,1000)
        sum(A)
    end

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
