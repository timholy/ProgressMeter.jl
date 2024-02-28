for ijulia_behavior in [:warn, :clear, :append]

ProgressMeter.ijulia_behavior(ijulia_behavior)

# For testing lazy-showvalue too
lazy_no_lazy(values) = (rand() < 0.5) ? values : () -> values

println("Testing showvalues with a Dict (2 values)")
function testfunc1(n, dt, tsleep, desc, barlen)
    p = Progress(n; dt=dt, desc=desc, barlen=barlen)
    for i = 1:n
        sleep(tsleep)
        values = Dict(:i => i, :halfdone => (i >= n/2))
        next!(p; showvalues = lazy_no_lazy(values))
    end
end
testfunc1(50, 1, 0.2, "progress  ", 70)

println("Testing showvalues with an Array of tuples (4 values)")
function testfunc2(n, dt, tsleep, desc, barlen)
    p = Progress(n; dt=dt, desc=desc, barlen=barlen)
    for i = 1:n
        sleep(tsleep)
        values = [(:i, i), (:constant, "foo"), (:isq, i^2), (:large, 2^i)]
        next!(p; showvalues = lazy_no_lazy(values))
    end
end
testfunc2(30, 1, 0.2, "progress  ", 60)

println("Testing showvalues when types of names differ (3 values)")
function testfunc3(n, dt, tsleep, desc, barlen)
    p = Progress(n; dt=dt, desc=desc, barlen=barlen)
    for i = 1:n
        sleep(tsleep)
        values = [(:i, i*10), ("constant", "foo"), 
            ("foobar", round(i*tsleep, digits=4))]
        next!(p; showvalues = lazy_no_lazy(values))
    end
end
testfunc3(30, 1, 0.2, "progress  ", 70)

println("Testing progress with showing values when num values to print changes between iterations")
function testfunc4(n, dt, tsleep, desc, barlen)
    p = Progress(n; dt=dt, desc=desc, barlen=barlen)
    for i = 1:n
        sleep(tsleep)
        values_pool = [(:i, i*10), ("constant", "foo"), 
            ("foobar", round(i*tsleep, digits=4))]
        values = values_pool[randn(3) .< 0.5]
        next!(p; showvalues = lazy_no_lazy(values))
    end
end
testfunc4(30, 1, 0.2, "opt steps  ", 70)

println("Testing showvalues with changing number of lines")
prog = Progress(50)
for i in 1:50
    values = Dict(:left => 100 - i,
                    :message => repeat("0123456789", (i%10 + 1)*15),
                    :final => "this comes after")
    update!(prog, i; showvalues = lazy_no_lazy(values))
    sleep(0.1)
end

println("Testing showvalues with a different color (1 value)")
function testfunc5(n, dt, tsleep, desc, barlen)
    p = Progress(n; dt=dt, desc=desc, barlen=barlen)
    for i = 1:n
        sleep(tsleep)
        values = [(:large, 2^i)]
        next!(p; showvalues = lazy_no_lazy(values), 
            valuecolor = :yellow)
    end
end
testfunc5(10, 1, 0.2, "progress  ", 40)

println("Testing showvalues with threshold-based progress")
prog = ProgressThresh(1e-5; desc="Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    values = Dict(:margin => abs(val - 1e-5))
    update!(prog, val; showvalues = lazy_no_lazy(values))
    sleep(0.1)
end

println("Testing showvalues with online progress")
prog = ProgressUnknown(desc="Entries read:")
for title in ["a", "b", "c", "d", "e"]
    values = Dict(:title => title)
    next!(prog; showvalues = lazy_no_lazy(values))
    sleep(0.5)
end
finish!(prog)


println("Testing showvalues with early cancel")
prog = Progress(100; dt=1, desc="progress: ", barlen=70)
for i in 1:50
    values = Dict(:left => 100 - i)
    update!(prog, i; showvalues = lazy_no_lazy(values))
    sleep(0.1)
end
cancel(prog)


println("Testing showvalues with truncate")
prog = Progress(50; dt=1, desc="progress: ")
for i in 1:50
    values = Dict(:left => 100 - i, :message => repeat("0123456789", i))
    update!(prog, i; 
        showvalues = lazy_no_lazy(values), truncate_lines = true)
    sleep(0.1)
end

end # if