println("Testing floating normal progress bar (offset 4)")
function testfunc1(n, dt, tsleep, desc, barlen, offset)
    p = ProgressMeter.Progress(n, dt, desc, barlen, offset=offset)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
    print("\n" ^ 5)
end
testfunc1(50, 0.2, 0.2, "progress  ", 70, 4)

println("Testing floating normal progress bars with values and keep (2 levels)")
function testfunc2(n, dt, tsleep, desc, barlen)
    p1 = ProgressMeter.Progress(n, dt, desc, barlen, offset=0)
    p2 = ProgressMeter.Progress(n, dt, desc, barlen, offset=5)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p1; showvalues = [(:i, i),
            (:constant, "foo"), (:isq, i^2), (:large, 2^i)], keep=false)
        ProgressMeter.next!(p2; showvalues = [(:i, i),
            (:constant, "foo"), (:isq, i^2), (:large, 2^i)])
    end
    print("\n" ^ 10)
end
testfunc2(50, 0.2, 0.2, "progress  ", 70)

println("Testing floating normal progress bars with changing offset")
function testfunc3(n, dt, tsleep, desc, barlen)
    p1 = ProgressMeter.Progress(n, dt, desc, barlen, offset=0)
    p2 = ProgressMeter.Progress(n, dt, desc, barlen, offset=1)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p1; showvalues = [(:i, i) for _ in 1:i], keep=false)
        ProgressMeter.next!(p2; showvalues = [(:i, i),
            (:constant, "foo"), (:isq, i^2), (:large, 2^i)], offset = (p1.offset + p1.numprintedvalues))
    end
    print("\n" ^ (10 + 5))
end
testfunc3(10, 0.2, 0.5, "progress  ", 70)

println("Testing floating thresh progress bar (offset 2)")
function testfunc4(thresh, dt, tsleep, desc, offset)
    prog = ProgressMeter.ProgressThresh(thresh, dt, desc, offset=offset)
    for val in 10 .^ range(2, stop=-6, length=20)
        ProgressMeter.update!(prog, val)
        sleep(tsleep)
    end
    print("\n" ^ 3)
end
testfunc4(1e-5, 0.2, 0.2, "Minimizing: ", 2)

println("Testing floating in @showprogress macro (3 levels)")
function testfunc5(n, tsleep)
    ProgressMeter.@showprogress "Level 0 " for i in 1:n
        ProgressMeter.@showprogress " Level 1 " 1 for i2 in 1:n
            ProgressMeter.@showprogress "  Level 2 " 2 for i3 in 1:n
                sleep(tsleep)
            end
        end
    end
    print("\n" ^ 2)
end
testfunc5(5, 0.1)
