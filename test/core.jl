# test durationstring output at borders
@test ProgressMeter.durationstring(0.9) == "0:00:00"
@test ProgressMeter.durationstring(1.0) == "0:00:01"
@test ProgressMeter.durationstring(59.9) == "0:00:59"
@test ProgressMeter.durationstring(60.0) == "0:01:00"
@test ProgressMeter.durationstring(60*60 - 0.1) == "0:59:59"
@test ProgressMeter.durationstring(60*60) == "1:00:00"
@test ProgressMeter.durationstring(60*60*24 - 0.1) == "23:59:59"
@test ProgressMeter.durationstring(60*60*24) == "1 days, 0:00:00"
@test ProgressMeter.durationstring(60*60*24*10 - 0.1) == "9 days, 23:59:59"
@test ProgressMeter.durationstring(60*60*24*10) == "10.00 days"

@test ProgressMeter.Progress(5, "Progress:", Int16(5)).offset == 5
@test ProgressMeter.ProgressThresh(0.2, "Progress:", Int16(5)).offset == 5

# test speed string formatting
for ns in [1, 9, 10, 99, 100, 999, 1_000, 9_999, 10_000, 99_000, 100_000, 999_999, 1_000_000, 9_000_000, 10_000_000, 99_999_000, 1_234_567_890, 1_234_567_890 * 10, 1_234_567_890 * 100, 1_234_567_890 * 1_000, 1_234_567_890 * 10_000, 1_234_567_890 * 100_000, 1_234_567_890 * 1_000_000, 1_234_567_890 * 10_000_000]
    sec = ns / 1_000_000_000
    try
        @test length(ProgressMeter.speedstring(sec)) == 11
    catch
        @error "ns = $ns caused $(ProgressMeter.speedstring(sec)) (not length 11)"
        throw()
    end
end

# Performance test (from #171)
function prog_perf(n)
    prog = Progress(n)
    x = 0.0
    for i in 1:n
        x += rand()
        next!(prog)
    end
    return x
end

function noprog_perf(n)
    x = 0.0
    for i in 1:n
        x += rand()
    end
    return x
end

if !parse(Bool, get(ENV, "CI", "false")) # CI environment is too unreliable for performance tests 
    prog_perf(10^7)
    noprog_perf(10^7)
    @time prog_perf(10^7)
    @time noprog_perf(10^7)
    @test @elapsed(prog_perf(10^7)) < 9*@elapsed(noprog_perf(10^7))
end

# Avoid a NaN due to the estimated print time compensation
# https://github.com/timholy/ProgressMeter.jl/issues/209
prog = Progress(10)
prog.check_iterations = 999
t = time()
prog.tlast = t
@test ProgressMeter.calc_check_iterations(prog, t) == 999
