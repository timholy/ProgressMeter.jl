for ijulia_behavior in [:warn, :clear, :append]

ProgressMeter.ijulia_behavior(ijulia_behavior)

# For testing lazy-showvalue too
lazy_no_lazy(values) = (rand() < 0.5) ? values : () -> values

println("Testing showvalues with a Dict (2 values)")
function testfunc1(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        values = Dict(:i => i, :halfdone => (i >= n/2))
        ProgressMeter.next!(p; showvalues = lazy_no_lazy(values))
    end
end
testfunc1(50, 1, 0.2, "progress  ", 70)

println("Testing showvalues with an Array of tuples (4 values)")
function testfunc2(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        values = [(:i, i), (:constant, "foo"), (:isq, i^2), (:large, 2^i)]
        ProgressMeter.next!(p; showvalues = lazy_no_lazy(values))
    end
end
testfunc2(30, 1, 0.2, "progress  ", 60)

println("Testing showvalues when types of names differ (3 values)")
function testfunc3(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        values = [(:i, i*10), ("constant", "foo"), 
            ("foobar", round(i*tsleep, digits=4))]
        ProgressMeter.next!(p; showvalues = lazy_no_lazy(values))
    end
end
testfunc3(30, 1, 0.2, "progress  ", 70)

println("Testing progress with showing values when num values to print changes between iterations")
function testfunc4(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        values_pool = [(:i, i*10), ("constant", "foo"), 
            ("foobar", round(i*tsleep, digits=4))]
        values = values_pool[randn(3) .< 0.5]
        ProgressMeter.next!(p; showvalues = lazy_no_lazy(values))
    end
end
testfunc4(30, 1, 0.2, "opt steps  ", 70)

println("Testing showvalues with changing number of lines")
prog = ProgressMeter.Progress(50)
for i in 1:50
    values = Dict(:left => 100 - i,
                    :message => repeat("0123456789", (i%10 + 1)*15),
                    :final => "this comes after")
    ProgressMeter.update!(prog, i; showvalues = lazy_no_lazy(values))
    sleep(0.1)
end

println("Testing showvalues with a different color (1 value)")
function testfunc5(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        values = [(:large, 2^i)]
        ProgressMeter.next!(p; showvalues = lazy_no_lazy(values), 
            valuecolor = :yellow)
    end
end
testfunc5(10, 1, 0.2, "progress  ", 40)

println("Testing showvalues with threshold-based progress")
prog = ProgressMeter.ProgressThresh(1e-5, "Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    values = Dict(:margin => abs(val - 1e-5))
    ProgressMeter.update!(prog, val; showvalues = lazy_no_lazy(values))
    sleep(0.1)
end

println("Testing showvalues with online progress")
prog = ProgressMeter.ProgressUnknown("Entries read:")
for title in ["a", "b", "c", "d", "e"]
    values = Dict(:title => title)
    ProgressMeter.next!(prog; showvalues = lazy_no_lazy(values))
    sleep(0.5)
end
ProgressMeter.finish!(prog)


println("Testing showvalues with early cancel")
prog = ProgressMeter.Progress(100, 1, "progress: ", 70)
for i in 1:50
    values = Dict(:left => 100 - i)
    ProgressMeter.update!(prog, i; showvalues = lazy_no_lazy(values))
    sleep(0.1)
end
ProgressMeter.cancel(prog)


println("Testing showvalues with truncate")
prog = ProgressMeter.Progress(50, 1, "progress: ")
for i in 1:50
    values = Dict(:left => 100 - i, :message => repeat("0123456789", i))
    ProgressMeter.update!(prog, i; 
        showvalues = lazy_no_lazy(values), truncate_lines = true)
    sleep(0.1)
end

println("Testing multi-line string")
p = ProgressMeter.Progress(10)
for iter in 1:10
    sleep(0.1)
    s = "line 1\nline 2\nline 3"
    next!(p; showvalues = [("lines", s)])
end

end # if