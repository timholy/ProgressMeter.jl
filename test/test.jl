import ProgressMeter

function testfunc(n, dt, tsleep)
    p = ProgressMeter.Progress(n, dt)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end

testfunc(107, 0.01, 0.01)


function testfunc2(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end

testfunc2(107, 0.01, 0.01, "Computing...", 50)


