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

@test Progress(5, desc="Progress:", offset=Int16(5)).offset == 5
@test ProgressThresh(0.2, desc="Progress:", offset=Int16(5)).offset == 5

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

# Performance test (from #171, #323)
function prog_perf(n; dt=0.1, enabled=true, force=false, safe_lock=false)
    prog = Progress(n; dt, enabled, safe_lock)
    x = 0.0
    for i in 1:n
        x += rand()
        next!(prog; force)
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

println("Performance tests...")

#precompile
noprog_perf(10)
prog_perf(10)
prog_perf(10; safe_lock=true)
prog_perf(10; dt=9999)
prog_perf(10; enabled=false)
prog_perf(10; enabled=false, safe_lock=true)
prog_perf(10; force=true)

noprog_threaded(2*Threads.nthreads())
prog_threaded(2*Threads.nthreads())
prog_threaded(2*Threads.nthreads(); safe_lock=true)
prog_threaded(2*Threads.nthreads(); dt=9999)
prog_threaded(2*Threads.nthreads(); enabled=false)
prog_threaded(2*Threads.nthreads(); force=true)

N = 10^8
N_force = 1000
t_noprog = (@elapsed noprog_perf(N))/N
t_prog = (@elapsed prog_perf(N))/N
t_lock = (@elapsed prog_perf(N; safe_lock=1))/N
t_detect = (@elapsed prog_perf(N; safe_lock=2))/N
t_noprint = (@elapsed prog_perf(N; dt=9999))/N
t_disabled = (@elapsed prog_perf(N; enabled=false))/N
t_disabled_lock = (@elapsed prog_perf(N; enabled=false, safe_lock=1))/N
t_force = (@elapsed prog_perf(N_force; force=true))/N_force

Nth = Threads.nthreads() * 10^6
Nth_force = Threads.nthreads() * 100
th_noprog = (@elapsed noprog_threaded(Nth))/Nth
th_detect = (@elapsed prog_threaded(Nth))/Nth
th_lock = (@elapsed prog_threaded(Nth; safe_lock=1))/Nth
th_noprint = (@elapsed prog_threaded(Nth; dt=9999))/Nth
th_disabled = (@elapsed prog_threaded(Nth; enabled=false))/Nth
th_force = (@elapsed prog_threaded(Nth_force; force=true))/Nth_force

println("Performance results:")
println("without progress:     ", ProgressMeter.speedstring(t_noprog))
println("with no lock:         ", ProgressMeter.speedstring(t_prog))
println("with no printing:     ", ProgressMeter.speedstring(t_noprint))
println("with disabled:        ", ProgressMeter.speedstring(t_disabled))
println("with lock:            ", ProgressMeter.speedstring(t_lock))
println("with automatic lock:  ", ProgressMeter.speedstring(t_detect))
println("with lock, disabled:  ", ProgressMeter.speedstring(t_disabled_lock))
println("with force:           ", ProgressMeter.speedstring(t_force))
println()
println("Threaded performance results: ($(Threads.nthreads()) threads)")
println("without progress:     ", ProgressMeter.speedstring(th_noprog))
println("with automatic lock:  ", ProgressMeter.speedstring(th_detect))
println("with forced lock:     ", ProgressMeter.speedstring(th_lock))
println("with no printing:     ", ProgressMeter.speedstring(th_noprint))
println("with disabled:        ", ProgressMeter.speedstring(th_disabled))
println("with force:           ", ProgressMeter.speedstring(th_force))

if get(ENV, "CI", "false") == "false" # CI environment is too unreliable for performance tests 
    @test t_prog < 9*t_noprog
end


# Avoid a NaN due to the estimated print time compensation
# https://github.com/timholy/ProgressMeter.jl/issues/209
prog = Progress(10)
prog.check_iterations = 999
t = time()
prog.tlast = t
@test ProgressMeter.calc_check_iterations(prog, t) == 999

# Test ProgressWrapper
A = rand(3,5,7,11)
prog = Progress(length(A))
wrap = ProgressMeter.ProgressWrapper(A, prog)

@test Base.IteratorSize(wrap) == Base.IteratorSize(A)
@test Base.IteratorEltype(wrap) == Base.IteratorEltype(A)
@test axes(wrap) == axes(A)
@test size(wrap) == size(A)
@test length(wrap) == length(A)
@test eltype(wrap) == eltype(A)
@test collect(wrap) == collect(A)

# Test setproperty! on ProgressCore
prog = Progress(10)
prog.desc = "New description" # in ProgressCore
@test prog.desc == "New description"
prog.n = UInt128(20) # in Progress
@test prog.n == 20
prog.offset = Int8(5) # in ProgressCore
@test prog.offset == 5

# Test safe_lock option, initialization and execution. 
function simple_sum(n; safe_lock = true)
    p = Progress(n; safe_lock)
    s = 0.0
    for i in 1:n
        s += sin(i)^2
        next!(p)
    end
    return s
end
p = Progress(10)
@test (p.safe_lock) == 2*(Threads.nthreads() > 1)
p = Progress(10; safe_lock = false)
@test p.safe_lock == false
@test simple_sum(10; safe_lock = true) ≈ simple_sum(10; safe_lock = false)


# Brute-force thread safety

function test_thread(N)
    p = Progress(N)
    Threads.@threads for _ in 1:N
        next!(p)
    end
end

println("Brute-forcing thread safety... ($(Threads.nthreads()) threads)")
@time for i in 1:10^5
    test_thread(Threads.nthreads())
end


