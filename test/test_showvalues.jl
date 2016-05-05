println("Testing showvalues with a Dict (2 values)")
function testfunc1(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p; showvalues = Dict(:i => i, :halfdone => (i >= n/2)))
    end
end
testfunc1(50, 1, 0.2, "progress  ", 70)

println("Testing showvalues with an Array of tuples (4 values)")
function testfunc2(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p; showvalues = [(:i, i), 
            (:constant, "foo"), (:isq, i^2), (:large, 2^i)])
    end
end
testfunc2(30, 1, 0.2, "progress  ", 60)

println("Testing showvalues when types of names differ (3 values)")
function testfunc3(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p; showvalues = [(:i, i*10), ("constant", "foo"), 
            ("foobar", round(i*tsleep, 4))])
    end
end
testfunc3(30, 1, 0.2, "progress  ", 70)

println("Testing progress with showing values when num values to print changes between iterations")
function testfunc4(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        values = [(:i, i*10), ("constant", "foo"), ("foobar", round(i*tsleep, 4))]
        ProgressMeter.next!(p; showvalues = values[randn(3) .< 0.5])
    end
end
testfunc4(30, 1, 0.2, "opt steps  ", 70)

println("Testing showvalues with a different color (1 value)")
function testfunc5(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p; showvalues = [(:large, 2^i)], valuecolor = :yellow)
    end
end
testfunc5(10, 1, 0.2, "progress  ", 40)

println("Testing showvalues with threshold-based progress")
prog = ProgressMeter.ProgressThresh(1e-5, "Minimizing:")
for val in logspace(2, -6, 20)
    ProgressMeter.update!(prog, val; showvalues = Dict(:margin => abs(val - 1e-5)))
    sleep(0.1)
end


println("Testing showvalues with early cancel")
prog = ProgressMeter.Progress(100, 1, "progress: ", 70)
for i in 1:50
    ProgressMeter.update!(prog, i; showvalues = Dict(:left => 100 - i))
    sleep(0.1)
end
ProgressMeter.cancel(prog)