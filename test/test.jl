import ProgressMeter
using Random: srand
using Test

srand(123)

function testfunc(n, dt, tsleep)
    p = ProgressMeter.Progress(n, dt)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end
println("Testing original interface...")
testfunc(107, 0.01, 0.01)


function testfunc2(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end
println("Testing desc and progress bar")
testfunc2(107, 0.01, 0.01, "Computing...", 50)
println("Testing no desc and no progress bar")
testfunc2(107, 0.01, 0.01, "", 0)


function testfunc3(n, tsleep, desc)
    p = ProgressMeter.Progress(n, desc)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end
println("Testing tty width...")
testfunc3(107, 0.02, "Computing (use tty width)...")
println("Testing no description...")
testfunc3(107, 0.02, "")




function testfunc4()  # test "days" format
    p = ProgressMeter.Progress(10000000, "Test...")
    for i = 1:105
        sleep(0.02)
        ProgressMeter.next!(p)
    end
end

println("Testing that not even 1% required...")
testfunc4()


function testfunc5(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:round(Int, floor(n/2))
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
    for i = round(Int, ceil(n/2)):n
        sleep(tsleep)
        ProgressMeter.next!(p, :red)
    end
end

println("\nTesting changing the bar color")
testfunc5(107, 0.01, 0.01, "Computing...", 50)


function testfunc6(n, dt, tsleep)
    ProgressMeter.@showprogress dt for i in 1:n
        if i == div(n, 2)
            break
        end
        if rand() < 0.7
            sleep(tsleep)
            continue
        end
    end
end

function testfunc6a(n, dt, tsleep)
    ProgressMeter.@showprogress dt for i in 1:n, j in 1:n
        if i == div(n, 2)
            break
        end
        if rand() < 0.7
            sleep(tsleep)
            continue
        end
    end
end

println("Testing @showprogress macro on for loop")
testfunc6(3000, 0.01, 0.002)
testfunc6a(30, 0.01, 0.002)


function testfunc7(n, dt, tsleep)
    s = ProgressMeter.@showprogress dt "Calculating..." [(sleep(tsleep); z) for z in 1:n]
    @test s == [1:n;]
end

function testfunc7a(n, dt, tsleep)
    s = ProgressMeter.@showprogress dt "Calculating..." [(sleep(tsleep); z) for z in 1:n, y in 1:n]
    @test s == [z for z in 1:n, y in 1:n]
end

println("Testing @showprogress macro on comprehension")
testfunc7(25, 0.1, 0.1)
testfunc7a(5, 0.1, 0.1)


function testfunc8(n, dt, tsleep)
    ProgressMeter.@showprogress dt for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
            continue
        end
        for j in 1:10
            if j % 2 == 0
                continue
            end
        end
        while rand(Bool)
            continue
        end
        while true
            break
        end
    end
end

println("Testing @showprogress macro on a for loop with inner loops containing continue and break statements")
testfunc8(3000, 0.01, 0.002)


function testfunc9(n, dt, tsleep)
    s = ProgressMeter.@showprogress dt "Calculating..." Float64[(sleep(tsleep); z) for z in 1:n]
    @test s == [1:n;]
end

function testfunc9a(n, dt, tsleep)
    s = ProgressMeter.@showprogress dt "Calculating..." Float64[(sleep(tsleep); z) for z in 1:n, y in 1:n]
    @test s == [z for z in 1:n, y in 1:n]
end

println("Testing @showprogress macro on typed comprehension")
testfunc9(100, 0.1, 0.01)
testfunc9a(10, 0.1, 0.01)


function testfunc10(n, k, dt, tsleep)
    p = ProgressMeter.Progress(n, dt)
    for i = 1:k
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
end
println("Testing under-shooting progress with finish!...")
testfunc10(107, 105, 0.01, 0.01)
println("Testing over-shooting progress with finish!...")
testfunc10(107, 111, 0.01, 0.01)


function testfunc13()
    ProgressMeter.@showprogress 1 for i=1:10
        return
    end
end

println("Testing @showprogress macro on loop ending with return statement")
testfunc13()

function testfunc13()
    n = 30
    # no keyword arguments
    p = ProgressMeter.Progress(n)
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
    # full keyword argumetns
    p = ProgressMeter.Progress(n, dt=0.01, desc="", color=:red, output=stderr, barlen=40)
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
end

println("Testing keyword arguments")
testfunc13()

function testfunc14(barglyphs)
    n = 30
    # with the string constructor
    p = ProgressMeter.Progress(n, barglyphs=ProgressMeter.BarGlyphs(barglyphs))
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
    # with the 5 char constructor
    chars = (barglyphs...,)
    p = ProgressMeter.Progress(n, barglyphs=ProgressMeter.BarGlyphs(chars...))
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
    p = ProgressMeter.Progress(n, dt=0.01, desc="",
                               color=:red, output=stderr, barlen=40,
                               barglyphs=ProgressMeter.BarGlyphs(barglyphs))
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
end

println("Testing custom bar glyphs")
testfunc14("[=> ]")
@test_throws ErrorException testfunc14("gklelt")

# Threshold-based progress reports
println("Testing threshold-based progress")
prog = ProgressMeter.ProgressThresh(1e-5, "Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    ProgressMeter.update!(prog, val)
    sleep(0.1)
end
