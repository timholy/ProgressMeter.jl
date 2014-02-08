import ProgressMeter

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
    for i = 1:int(floor(n/2))
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
    for i = int(ceil(n/2)):n
        sleep(tsleep)
        ProgressMeter.next!(p, :red)
    end
end

println("Testing changing the bar color")
testfunc5(107, 0.01, 0.01, "Computing...", 50)
println("")
println("All tests complete")