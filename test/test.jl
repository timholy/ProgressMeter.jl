using Random: seed!

seed!(123)
#=
function testfunc(n, dt, tsleep)
    p = Progress(n; dt=dt)
    for i = 1:n
        sleep(tsleep)
        next!(p)
    end
end
println("Testing original interface...")
testfunc(107, 0.01, 0.01)


function testfunc2(n, dt, tsleep, desc, barlen)
    p = Progress(n; dt=dt, desc=desc, barlen=barlen)
    for i = 1:n
        sleep(tsleep)
        next!(p)
    end
end
println("Testing desc and progress bar")
testfunc2(107, 0.01, 0.01, "Computing...", 50)
println("Testing no desc and no progress bar")
testfunc2(107, 0.01, 0.01, "", 0)


function testfunc3(n, tsleep, desc)
    p = Progress(n; desc=desc)
    for i = 1:n
        sleep(tsleep)
        next!(p)
    end
end
println("Testing tty width...")
testfunc3(107, 0.02, "Computing (use tty width)...")
println("Testing no description...")
testfunc3(107, 0.02, "")




function testfunc4()  # test "days" format
    p = Progress(10000000, desc="Test...")
    for i = 1:105
        sleep(0.02)
        next!(p)
    end
end

println("Testing that not even 1% required...")
testfunc4()

function testfunc5A(n, dt, tsleep, desc, barlen)
    p = Progress(n; dt=dt, desc=desc, barlen=barlen)
    for i = 1:round(Int, floor(n/2))
        sleep(tsleep)
        next!(p)
    end
    for i = round(Int, ceil(n/2)):n
        sleep(tsleep)
        next!(p; color=:red)
    end
end

println("\nTesting changing the bar color")
testfunc5A(107, 0.01, 0.01, "Computing...", 50)

function testfunc5B(n, dt, tsleep, desc, barlen)
    p = Progress(n; dt=dt, desc=desc, barlen=barlen)
    for i = 1:n
        sleep(tsleep)
        next!(p)
        if i % 10 == 0
            stepnum = floor(Int, i/10) + 1
            update!(p, desc = "Step $stepnum...")
        end
    end
end

println("\nTesting changing the description")
testfunc5B(107, 0.01, 0.02, "Step 1...", 50)


function testfunc6(n, dt, tsleep)
    @showprogress dt=dt for i in 1:n
        if i == div(n, 2)
            break
        end
        if rand() < 0.7
            sleep(tsleep)
            continue
        end
    end
end

function testfunc6a(n, dt, tsleep)
    @showprogress dt=dt for i in 1:n, j in 1:n
        if i == div(n, 2)
            break
        end
        if rand() < 0.7
            sleep(tsleep)
            continue
        end
    end
end

println("Testing @showprogress macro on for loop")
testfunc6(3000, 0.01, 0.002)
testfunc6a(30, 0.01, 0.002)
=#

function testfunc7(n, dt, tsleep)
    s = @showprogress dt=dt desc="Calculating..." [(sleep(tsleep); z) for z in 1:n]
    @test s == [1:n;]
end

function testfunc7a(n, dt, tsleep)
    s = @showprogress dt=dt desc="Calculating..." [(sleep(tsleep); z) for z in 1:n, y in 1:n]
    @test s == [z for z in 1:n, y in 1:n]
end

function testfunc7b(A, dt, tsleep)
    s = @showprogress dt=dt desc="Calculating..." [(sleep(tsleep); z) for z in A]
    @test s == A
end

function testfunc7c(tsleep)
    s = @showprogress desc="inc should be 10% " [(sleep(tsleep); a+b+c) for a=1:10 for b=1:7 for c=1:3]
    @test s == [a+b+c for a=1:10 for b=1:7 for c=1:3]
end

function testfunc7d(tsleep)
    s = @showprogress desc="inc should be 10% " [(sleep(tsleep); a+b+c) for a=1:3,b=1:10 for c=1:a+b]
    @test s == [a+b+c for a=1:3,b=1:10 for c=1:a+b]
end

function testfunc7e(tsleep)
    s = @showprogress desc="inc should be 10% " [(sleep(tsleep); a+b) for a=1:29,b=1:10 if b>a]
    @test s == [a+b for a=1:29,b=1:10 if b>a]
end

function testfunc7f(tsleep)
    s = @showprogress desc="inc should be 10% " [(sleep(tsleep); a+b) for a=1:10 for b=1:29 if b<a]
    @test s == [a+b for a=1:10 for b=1:29 if b<a]
end

function testfunc7g()
    s = @showprogress [(q,d,n,p) for q=0:25:100 for d=0:10:100-q for n=0:5:100-q-d for p=100-q-d-n]
    @test s == [(q,d,n,p) for q=0:25:100 for d=0:10:100-q for n=0:5:100-q-d for p=100-q-d-n]
end

println("Testing @showprogress macro on comprehension")
testfunc7(25, 0.1, 0.1)
testfunc7a(5, 0.1, 0.1)
testfunc7b(rand(3,4), 0.1, 0.1) #290
testfunc7c(0.01)
testfunc7d(0.01)
testfunc7e(0.01) #267
testfunc7f(0.01)
testfunc7g() #58


function testfunc8(n, dt, tsleep)
    @showprogress dt=dt for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
            continue
        end
        for j in 1:10
            if j % 2 == 0
                continue
            end
        end
        while rand(Bool)
            continue
        end
        while true
            break
        end
    end
end

println("Testing @showprogress macro on a for loop with inner loops containing continue and break statements")
testfunc8(1000, 0.01, 0.001)


function testfunc9(n, dt, tsleep)
    s = @showprogress dt=dt desc="Calculating..." Float64[(sleep(tsleep); z) for z in 1:n]
    @test s == [1:n;]
end

function testfunc9a(n, dt, tsleep)
    s = @showprogress dt=dt desc="Calculating..." Float64[(sleep(tsleep); z) for z in 1:n, y in 1:n]
    @test s == [z for z in 1:n, y in 1:n]
end

function testfunc9b(A, dt, tsleep)
    s = @showprogress dt=dt desc="Calculating..." Float64[(sleep(tsleep); z) for z in A]
    @test s == Float64[A;]
end

function testfunc9c(tsleep)
    s = @showprogress desc="inc should be 10% " Float64[(sleep(tsleep); a+b+c) for a=1:17,c=1:10 if c<a for b=1:3 if b<a]
    @test s == Float64[a+b+c for a=1:17,c=1:10 if c<a for b=1:3 if b<a]
end

println("Testing @showprogress macro on typed comprehension")
testfunc9(100, 0.1, 0.01)
testfunc9a(10, 0.1, 0.01)
testfunc9b(rand(Float32,3,4), 0.1, 0.01) #290
testfunc9c(0.01)

function testfunc10(n, k, dt, tsleep)
    p = Progress(n; dt=dt)
    for i = 1:k
        sleep(tsleep)
        next!(p)
    end
    finish!(p)
end
println("Testing under-shooting progress with finish!...")
testfunc10(107, 105, 0.01, 0.01)
println("Testing over-shooting progress with finish!...")
testfunc10(107, 111, 0.01, 0.01)

function testfunc11(n, dt, tsleep)
    p = Progress(n, dt=dt)
    for i = 1:n÷2
        sleep(tsleep)
        next!(p)
    end
    sleep(tsleep)
    update!(p, 0)
    for i = 1:n
        sleep(tsleep)
        next!(p)
    end
end
println("Testing update! to 0...")
testfunc11(6, 0.01, 0.3)

function testfunc13()
    @showprogress dt=1 for i=1:10
        return
    end
end

println("Testing @showprogress macro on loop ending with return statement")
testfunc13()

function testfunc13a()
    n = 30
    # no keyword arguments
    p = Progress(n)
    for i in 1:n
        sleep(0.05)
        next!(p)
    end
    # full keyword arguments
    start = 15
    p = Progress(n; dt=0.01, desc="", color=:red, output=stderr, barlen=40, start = start)
    for i in 1:n-start
        sleep(0.05)
        next!(p)
    end
end

function testfunc13b()
    # same with keyword arguments only
    @showprogress dt=0.01 color=:red output=stderr barlen=40 for i=1:15
        sleep(0.1)
    end
end

println("Testing keyword arguments")
testfunc13a()
testfunc13b()

function testfunc14(barglyphs)
    n = 30
    # with the string constructor
    p = Progress(n, barglyphs=BarGlyphs(barglyphs))
    for i in 1:n
        sleep(0.05)
        next!(p)
    end
    # with the 5 char constructor
    chars = (barglyphs...,)
    p = Progress(n, barglyphs=BarGlyphs(chars...))
    for i in 1:n
        sleep(0.05)
        next!(p)
    end
    p = Progress(n, dt=0.01, desc="",
                               color=:red, output=stderr, barlen=40,
                               barglyphs=BarGlyphs(barglyphs))
    for i in 1:n
        sleep(0.05)
        next!(p)
    end
end

println("Testing custom bar glyphs")
testfunc14("[=> ]")
@test_throws ErrorException testfunc14("gklelt")

# Threshold-based progress reports
println("Testing threshold-based progress")
prog = ProgressThresh(1e-5; desc="Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    update!(prog, val)
    sleep(0.1)
end
# issue #166
@test ProgressThresh(1.0f0; desc = "Desc: ") isa ProgressThresh{Float32}

# Threshold-based progress reports with increment=false
println("Testing threshold-based progress with increment=false")
prog = ProgressThresh(1e-5, desc="Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    update!(prog, val; increment=false)
    @test prog.counter == 0
    sleep(0.1)
end
colors = [:red, :blue, :green]
prog = ProgressThresh(1e-5, desc="Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    update!(prog, val; color=rand(colors), increment=false)
    @test prog.counter == 0
    sleep(0.1)
end

# ProgressUnknown progress reports
println("Testing progress unknown")
prog = ProgressUnknown(desc="Reading entry:")
for _ in 1:10
    next!(prog)
    sleep(0.1)
end
finish!(prog)

prog = ProgressUnknown(desc="Reading entry:")
for k in 1:2:20
    update!(prog, k)
    sleep(0.1)
end

colors = [:red, :blue, :green]
prog = ProgressUnknown(desc="Reading entry:")
for k in 1:2:20
    update!(prog, k; color=rand(colors))
    sleep(0.1)
end
finish!(prog)

prog = ProgressUnknown(desc="Reading entry:", spinner=true)
for _ in 1:10
    next!(prog)
    sleep(0.1)
end
finish!(prog)

prog = ProgressUnknown(desc="Reading entry:", spinner=true)
for _ in 1:10
    next!(prog)
    sleep(0.1)
end
finish!(prog, spinner='✗')

myspinner = ['🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘']
prog = ProgressUnknown(desc="Custom spinner:", spinner=true)
for val in 1:10
    next!(prog, spinner=myspinner)
    sleep(0.1)
end
finish!(prog, spinner='🌞')

prog = ProgressUnknown(desc="Custom spinner:", spinner=true)
for val in 1:10
    next!(prog, spinner="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    sleep(0.1)
end
finish!(prog)

println("Testing fractional bars")
for front in (['▏','▎','▍','▌','▋','▊', '▉'], ['▁' ,'▂' ,'▃' ,'▄' ,'▅' ,'▆', '▇'], ['░', '▒', '▓',])
    p = Progress(100, dt=0.01, barglyphs=BarGlyphs('|','█',front,' ','|'), barlen=10)
    for i in 1:100
        next!(p)
        sleep(0.02)
    end
end

function testfunc15(n, dt, tsleep)
    result = @showprogress dt=dt @distributed (+) for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
        end
        i ^ 2
    end
    @test result == sum(abs2.(1:n))
end

println("Testing @showprogress macro on distributed for loop with reducer")
testfunc15(3000, 0.01, 0.001)

function testfunc16(n, dt, tsleep)
    @showprogress dt=dt desc="Description: " @distributed for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
        end
        i ^ 2
    end
end

println("Testing @showprogress macro on distributed for loop without reducer")
testfunc16(3000, 0.01, 0.001)

function testfunc16cb(N, dt, tsleep)
    @showprogress dt=dt @distributed for i in N
        if rand() < 0.7
            sleep(tsleep)
        end
        200 < i < 400 && continue
        i > 1500 && break
        i ^ 2
    end
end

println("Testing @showprogress macro on distributed for loop with continue")
testfunc16cb(1:1000, 0.01, 0.002)

println("Testing @showprogress macro on distributed for loop with break")
testfunc16cb(1000:2000, 0.01, 0.003)

function testfunc16d(n, dt, tsleep)
    @showprogress Distributed.@distributed for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
        end
        i ^ 2
    end
end

println("Testing @showprogress macro on Distributed.@distributed")
testfunc16d(3000, 0.01, 0.001)


println("testing `@showprogress @distributed` in global scope")
@showprogress @distributed for i in 1:10
    sleep(0.1)
    i^2
end

println("testing `@showprogress @distributed (+)` in global scope") #243
result = @showprogress @distributed (+) for i in 1:10
    sleep(0.1)
    i^2
end
@test result == sum(abs2, 1:10)




function testfunc17()
    n = 30
    p = Progress(n, start=15)
    for i in 15+1:30
        sleep(0.1)
        next!(p)
    end
end

println("Testing start offset")
testfunc17()

# speed display option
function testfunc18A(n, dt, tsleep; start=15)
    p = Progress(n; dt=dt, start=start, showspeed=true)
    for i in start+1:start+n
        sleep(tsleep)
        next!(p)
    end
end

function testfunc18B(n, dt, tsleep)
    p = ProgressUnknown(; dt=dt, showspeed=true)
    for _ in 1:n
        sleep(tsleep)
        next!(p)
    end
    finish!(p)
end

function testfunc18C()
    p = ProgressThresh(1e-5; desc="Minimizing:", showspeed=true)
    for val in 10 .^ range(2, stop=-6, length=20)
        update!(p, val)
        sleep(0.1)
    end
end

println("Testing speed display")
testfunc18A(1_000, 0.01, 0.002)
testfunc18B(1_000, 0.01, 0.002)
testfunc18C()

function testfunc19()
    p = ProgressThresh(1e-5; desc="Minimizing:", showspeed=true)
    for val in 10 .^ range(2, stop=-6, length=20)
        update!(p, val; increment=false)
        sleep(0.1)
    end
end
println("Testing speed display with no update")
testfunc19()

function testfunc20(r, p)
    for i in r
        sleep(0.03)
        update!(p, i)
    end
    cancel(p; keep=true)
end
println("Testing early cancel")
testfunc20(1:50, Progress(100))
testfunc20(1:50, ProgressUnknown())
testfunc20(50:-1:1, ProgressThresh(0))
println("Testing early cancel with offset 1 and keep")
testfunc20(1:50, Progress(100, offset=1))
testfunc20(1:50, ProgressUnknown(offset=1))
testfunc20(50:-1:1, ProgressThresh(0, offset=1))

function testfunc21()
    p = Progress(10; desc="length 10:")
    for i in 1:5
        next!(p)
        sleep(0.2)
    end
    update!(p; max_steps = 100, desc="now 100:")
    sleep(0.5)
    @test p.n == 100
    for i in 6:100
        next!(p)
        sleep(0.05)
    end
end

println("Testing updating max_steps")
testfunc21()

function testfunc22()
    p = ProgressThresh(0.1; desc="thresh 0.1:")
    for i in 1:5
        update!(p, 1/i)
        sleep(0.2)
    end
    update!(p; thresh=0.01, desc="now 0.01:")
    sleep(0.5)
    @test p.thresh == 0.01
    for i in 6:101
        update!(p, 1/i)
        sleep(0.05)
    end
end

println("Testing updating thresh")
testfunc22()

function testfunc23(N, range, dt, tsleep)
    p = Progress(N; dt=dt)
    for i in range
        update!(p, i; showvalues=[:percentage => 100.0*i/N])
        sleep(tsleep)
    end
end
println("Testing rounding (#300)")
testfunc23(1000, [980;982;985;989;995;999;1000], 0.1, 1)
