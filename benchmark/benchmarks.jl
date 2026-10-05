using BenchmarkTools
using ProgressMeter

# Performance test (from #171, #323)
function prog_perf(n; dt=0.1, enabled=true, force=false, safe_lock=0)
    prog = Progress(n; dt, enabled, safe_lock)
    x = 0.0
    for i in 1:n
        x += rand()
        next!(prog; force)
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

function prog_threaded(n; dt=0.1, enabled=true, force=false, safe_lock=2)
    prog = Progress(n; dt, enabled, safe_lock)
    x = Threads.Atomic{Float64}(0.0)
    Threads.@threads for i in 1:n
        Threads.atomic_add!(x, rand())
        next!(prog; force)
    end
    return x
end

function noprog_threaded(n)
    x = Threads.Atomic{Float64}(0.0)
    Threads.@threads for i in 1:n
        Threads.atomic_add!(x, rand())
    end
    return x
end

const SUITE = BenchmarkGroup()
SUITE["singlethreaded"] = BenchmarkGroup()
SUITE["threaded"] = BenchmarkGroup()

N = 10^6
N_force = 100

Nth = Threads.nthreads() * 10^5
Nth_force = Threads.nthreads() * 100

SUITE["singlethreaded"]["without progress"] = @benchmarkable noprog_perf(N)
SUITE["singlethreaded"]["with progress"] = @benchmarkable prog_perf(N)
SUITE["singlethreaded"]["with lock"] = @benchmarkable prog_perf(N; safe_lock=1)
SUITE["singlethreaded"]["with automatic lock"] = @benchmarkable prog_perf(N; safe_lock=2)
SUITE["singlethreaded"]["with no printing"] = @benchmarkable prog_perf(N; dt=9999.9)
SUITE["singlethreaded"]["with disabled"] = @benchmarkable prog_perf(N; enabled=false)
SUITE["singlethreaded"]["with lock, disabled"] = @benchmarkable prog_perf(N; enabled=false, safe_lock=1)
SUITE["singlethreaded"]["with force"] = @benchmarkable prog_perf(N_force; force=true)

SUITE["threaded"]["without progress"] = @benchmarkable noprog_threaded(Nth)
SUITE["threaded"]["with automatic lock"] = @benchmarkable prog_threaded(Nth)
SUITE["threaded"]["with forced lock"] = @benchmarkable prog_threaded(Nth; safe_lock=1)
SUITE["threaded"]["with no printing"] = @benchmarkable prog_threaded(Nth; dt=9999.9)
SUITE["threaded"]["with disabled"] = @benchmarkable prog_threaded(Nth; enabled=false)
SUITE["threaded"]["with force"] = @benchmarkable prog_threaded(Nth_force; force=true)
