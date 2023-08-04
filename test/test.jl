using Random: seed!

seed!(123)

function testfunc(n, dt, tsleep)
    p = ProgressMeter.Progress(n, dt)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end
println("Testing original interface...")
testfunc(107, 0.01, 0.01)


function testfunc2(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end
println("Testing desc and progress bar")
testfunc2(107, 0.01, 0.01, "Computing...", 50)
println("Testing no desc and no progress bar")
testfunc2(107, 0.01, 0.01, "", 0)


function testfunc3(n, tsleep, desc)
    p = ProgressMeter.Progress(n, desc)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end
println("Testing tty width...")
testfunc3(107, 0.02, "Computing (use tty width)...")
println("Testing no description...")
testfunc3(107, 0.02, "")




function testfunc4()  # test "days" format
    p = ProgressMeter.Progress(10000000, "Test...")
    for i = 1:105
        sleep(0.02)
        ProgressMeter.next!(p)
    end
end

println("Testing that not even 1% required...")
testfunc4()

function testfunc5A(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:round(Int, floor(n/2))
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
    for i = round(Int, ceil(n/2)):n
        sleep(tsleep)
        ProgressMeter.next!(p, :red)
    end
end

println("\nTesting changing the bar color")
testfunc5A(107, 0.01, 0.01, "Computing...", 50)

function testfunc5B(n, dt, tsleep, desc, barlen)
    p = ProgressMeter.Progress(n, dt, desc, barlen)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
        if i % 10 == 0
            stepnum = floor(Int, i/10) + 1
            ProgressMeter.update!(p, desc = "Step $stepnum...")
        end
    end
end

println("\nTesting changing the description")
testfunc5B(107, 0.01, 0.05, "Step 1...", 50)

function testfunc5C(n, dt, tsleep, desc, rate_format)
    p = ProgressMeter.Progress(n, dt, desc, rate_format)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end

println("\nTesting changing the progress rate format")
testfunc5C(107, 0.01, 0.05, "Computing...", EmptyRateFormat())
testfunc5C(107, 0.01, 0.05, "Computing...", PercentRateFormat())
testfunc5C(107, 0.01, 0.05, "Computing...", PercentRateFormat(2))
testfunc5C(107, 0.01, 0.05, "Computing...", FractionRateFormat())
testfunc5C(107, 0.01, 0.05, "Computing...", IntegerRateFormat())

function testfunc6(n, dt, tsleep)
    ProgressMeter.@showprogress dt for i in 1:n
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
    ProgressMeter.@showprogress dt for i in 1:n, j in 1:n
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


function testfunc7(n, dt, tsleep)
    s = ProgressMeter.@showprogress dt "Calculating..." [(sleep(tsleep); z) for z in 1:n]
    @test s == [1:n;]
end

function testfunc7a(n, dt, tsleep)
    s = ProgressMeter.@showprogress dt "Calculating..." [(sleep(tsleep); z) for z in 1:n, y in 1:n]
    @test s == [z for z in 1:n, y in 1:n]
end

println("Testing @showprogress macro on comprehension")
testfunc7(25, 0.1, 0.1)
testfunc7a(5, 0.1, 0.1)


function testfunc8(n, dt, tsleep)
    ProgressMeter.@showprogress dt for i in 1:n
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
testfunc8(3000, 0.01, 0.002)


function testfunc9(n, dt, tsleep)
    s = ProgressMeter.@showprogress dt "Calculating..." Float64[(sleep(tsleep); z) for z in 1:n]
    @test s == [1:n;]
end

function testfunc9a(n, dt, tsleep)
    s = ProgressMeter.@showprogress dt "Calculating..." Float64[(sleep(tsleep); z) for z in 1:n, y in 1:n]
    @test s == [z for z in 1:n, y in 1:n]
end

println("Testing @showprogress macro on typed comprehension")
testfunc9(100, 0.1, 0.01)
testfunc9a(10, 0.1, 0.01)


function testfunc10(n, k, dt, tsleep)
    p = ProgressMeter.Progress(n, dt)
    for i = 1:k
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
end
println("Testing under-shooting progress with finish!...")
testfunc10(107, 105, 0.01, 0.01)
println("Testing over-shooting progress with finish!...")
testfunc10(107, 111, 0.01, 0.01)

function testfunc11(n, dt, tsleep)
    p = ProgressMeter.Progress(n, dt)
    for i = 1:n÷2
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
    sleep(tsleep)
    ProgressMeter.update!(p, 0)
    for i = 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end
println("Testing update! to 0...")
testfunc11(6, 0.01, 0.3)

function testfunc13()
    ProgressMeter.@showprogress 1 for i=1:10
        return
    end
end

println("Testing @showprogress macro on loop ending with return statement")
testfunc13()

function testfunc13()
    n = 30
    # no keyword arguments
    p = ProgressMeter.Progress(n)
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
    # full keyword argumetns
    start = 15
    p = ProgressMeter.Progress(n, dt=0.01, desc="", color=:red, output=stderr, barlen=40, start = start)
    for i in 1:n-start
        sleep(0.1)
        ProgressMeter.next!(p)
    end
end

println("Testing keyword arguments")
testfunc13()

function testfunc14(barglyphs)
    n = 30
    # with the string constructor
    p = ProgressMeter.Progress(n, barglyphs=ProgressMeter.BarGlyphs(barglyphs))
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
    # with the 5 char constructor
    chars = (barglyphs...,)
    p = ProgressMeter.Progress(n, barglyphs=ProgressMeter.BarGlyphs(chars...))
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
    p = ProgressMeter.Progress(n, dt=0.01, desc="",
                               color=:red, output=stderr, barlen=40,
                               barglyphs=ProgressMeter.BarGlyphs(barglyphs))
    for i in 1:n
        sleep(0.1)
        ProgressMeter.next!(p)
    end
end

println("Testing custom bar glyphs")
testfunc14("[=> ]")
@test_throws ErrorException testfunc14("gklelt")

# Threshold-based progress reports
println("Testing threshold-based progress")
prog = ProgressMeter.ProgressThresh(1e-5, "Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    ProgressMeter.update!(prog, val)
    sleep(0.1)
end
# issue #166
@test ProgressMeter.ProgressThresh(1.0f0; desc = "Desc: ") isa ProgressMeter.ProgressThresh{Float32}

# Threshold-based progress reports with increment=false
println("Testing threshold-based progress")
prog = ProgressMeter.ProgressThresh(1e-5, "Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    ProgressMeter.update!(prog, val; increment=false)
    @test prog.counter == 0
    sleep(0.1)
end
colors = [:red, :blue, :green]
prog = ProgressMeter.ProgressThresh(1e-5, "Minimizing:")
for val in 10 .^ range(2, stop=-6, length=20)
    ProgressMeter.update!(prog, val, rand(colors); increment=false)
    @test prog.counter == 0
    sleep(0.1)
end

# ProgressUnknown progress reports
println("Testing progress unknown")
prog = ProgressMeter.ProgressUnknown("Reading entry:")
for _ in 1:10
    ProgressMeter.next!(prog)
    sleep(0.1)
end
ProgressMeter.finish!(prog)

prog = ProgressMeter.ProgressUnknown("Reading entry:")
for k in 1:2:20
    ProgressMeter.update!(prog, k)
    sleep(0.1)
end

colors = [:red, :blue, :green]
prog = ProgressMeter.ProgressUnknown("Reading entry:")
for k in 1:2:20
    ProgressMeter.update!(prog, k, rand(colors))
    sleep(0.1)
end
ProgressMeter.finish!(prog)

prog = ProgressMeter.ProgressUnknown("Reading entry:", spinner=true)
for _ in 1:10
    ProgressMeter.next!(prog)
    sleep(0.1)
end
ProgressMeter.finish!(prog)

prog = ProgressMeter.ProgressUnknown("Reading entry:", spinner=true)
for _ in 1:10
    ProgressMeter.next!(prog)
    sleep(0.1)
end
ProgressMeter.finish!(prog, spinner='✗')

myspinner = ['🌑', '🌒', '🌓', '🌔', '🌕', '🌖', '🌗', '🌘']
prog = ProgressUnknown("Custom spinner:", spinner=true)
for val in 1:10
    ProgressMeter.next!(prog, spinner=myspinner)
    sleep(0.1)
end
ProgressMeter.finish!(prog, spinner='🌞')

prog = ProgressUnknown("Custom spinner:", spinner=true)
for val in 1:10
    ProgressMeter.next!(prog, spinner="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")
    sleep(0.1)
end
ProgressMeter.finish!(prog)

println("Testing fractional bars")
for front in (['▏','▎','▍','▌','▋','▊', '▉'], ['▁' ,'▂' ,'▃' ,'▄' ,'▅' ,'▆', '▇'], ['░', '▒', '▓',])
    p = ProgressMeter.Progress(100, dt=0.01, barglyphs=ProgressMeter.BarGlyphs('|','█',front,' ','|'), barlen=10)
    for i in 1:100
        ProgressMeter.next!(p)
        sleep(0.02)
    end
end

function testfunc15(n, dt, tsleep)
    result = ProgressMeter.@showprogress dt @distributed (+) for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
        end
        i ^ 2
    end
    @test result == sum(abs2.(1:n))
end

println("Testing @showprogress macro on distributed for loop with reducer")
testfunc15(3000, 0.01, 0.002)

function testfunc16(n, dt, tsleep)
    ProgressMeter.@showprogress dt "Description: " @distributed for i in 1:n
        if rand() < 0.7
            sleep(tsleep)
        end
        i ^ 2
    end
end

println("Testing @showprogress macro on distributed for loop without reducer")
testfunc16(3000, 0.01, 0.002)

function testfunc17()
    n = 30
    p = ProgressMeter.Progress(n, start=15)
    for i in 15+1:30
        sleep(0.1)
        ProgressMeter.next!(p)
    end
end

println("Testing start offset")
testfunc17()

# speed display option
function testfunc18A(n, dt, tsleep; start=15)
    p = ProgressMeter.Progress(n; dt=dt, start=start, showspeed=true)
    for i in start+1:start+n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
end

function testfunc18B(n, dt, tsleep)
    p = ProgressMeter.ProgressUnknown(n; dt=dt, showspeed=true)
    for _ in 1:n
        sleep(tsleep)
        ProgressMeter.next!(p)
    end
    ProgressMeter.finish!(p)
end

function testfunc18C()
    p = ProgressMeter.ProgressThresh(1e-5; desc="Minimizing:", showspeed=true)
    for val in 10 .^ range(2, stop=-6, length=20)
        ProgressMeter.update!(p, val)
        sleep(0.1)
    end
end

println("Testing speed display")
testfunc18A(1_000, 0.01, 0.002)
testfunc18B(1_000, 0.01, 0.002)
testfunc18C()

function testfunc19()
    p = ProgressMeter.ProgressThresh(1e-5; desc="Minimizing:", showspeed=true)
    for val in 10 .^ range(2, stop=-6, length=20)
        ProgressMeter.update!(p, val; increment=false)
        sleep(0.1)
    end
end
println("Testing speed display with no update")
testfunc19()
