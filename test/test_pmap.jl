using Base.Test
addprocs(2)
@everywhere using ProgressMeter

println("Testing pmap")
vals = 1:10
p = Progress(length(vals))
@test pmap(x->begin sleep(1); x*2 end, p, vals)[1] == vals[1]*2

println("Testing pmap with do block")
pmap(p, vals) do x
    sleep(1)
    x*2
end

println("Testing pmap with kwargs")
vals = 1:10
p = Progress(length(vals))
@test pmap(x->begin sleep(.1); x*2 end, p, vals, batch_size=5)[1] == vals[1]*2

println("Testing pmap with multiple lists")
vals2 = 10:-1:1
p = Progress(length(vals))
@test pmap(+, p, vals, vals2) == 11*ones(Int,length(vals))

println("Testing pmap with callback passing")
vals = 1:10
@test pmap((cb, x) -> begin sleep(.1); cb(1); x*2 end, Progress(length(vals)),vals,passcallback=true)[1] == vals[1]*2
