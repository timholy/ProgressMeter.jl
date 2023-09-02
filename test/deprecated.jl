println("Testing deprecated @showprogress syntax")

# positional arguments
@test_deprecated @showprogress 0.01 "Red:" 40 :red stderr for i=1:15
    sleep(0.1)
end
# mixed cases
@test_deprecated @showprogress "Blue: " color=:blue for i=1:10
    sleep(0.1)
end
@test_deprecated @showprogress color=:yellow "Yellow: " showspeed=true for i=1:10
    sleep(0.1)
end
@test_deprecated @showprogress "Invisible: " enabled=false for i=1:10
    sleep(0.1)
end

@test_deprecated @showprogress 0.05 "Red:" 40 :red stderr map(x->(sleep(0.01);x^2), 1:100)
@test_deprecated @showprogress color=:yellow "Yellow: " showspeed=true map(x->(sleep(0.01);x^2), 1:100)
@test_deprecated @showprogress "Invisible: " enabled=false map(x->(sleep(0.01);x^2), 1:100)

println("Testing deprecated Progress building")

@test_deprecated begin
    local p = Progress(10, 23, "ABC", 47, :red, stdout)
    @test p.n == 10
    @test p.dt == 23
    @test p.desc == "ABC"
    @test p.barlen == 47
    @test p.color == :red
    @test p.output == stdout
end

@test_deprecated begin
    local p = Progress(10, "ABC", 23)
    @test p.n == 10
    @test p.desc == "ABC"
    @test p.offset == 23
end

@test_deprecated begin 
    local p = ProgressThresh(0.1, 23, "ABC", :red, stdout)
    @test p.thresh == 0.1
    @test p.dt == 23
    @test p.desc == "ABC"
    @test p.color == :red
    @test p.output == stdout
end

@test_deprecated begin
    local p = ProgressThresh(0.1, "ABC", 23)
    @test p.thresh == 0.1
    @test p.desc == "ABC"
    @test p.offset == 23
end

@test_deprecated begin 
    local p = ProgressUnknown(23, "ABC", :red, stdout)
    @test p.dt == 23
    @test p.desc == "ABC"
    @test p.color == :red
    @test p.output == stdout
end

@test_deprecated begin
    local p = ProgressUnknown("ABC")
    @test p.desc == "ABC"
end

println("Testing deprecated updating")

p = Progress(10; dt=0)
next!(p)
@test_deprecated next!(p, :red)
sleep(0.5)
@test_deprecated update!(p, 5, :blue)
sleep(0.5)
@test_deprecated cancel(p, "Oops!", :green)

p = ProgressUnknown(dt=0)
next!(p)
@test_deprecated next!(p, :red)
sleep(0.5)
@test_deprecated update!(p, 5, :blue)
sleep(0.5)
@test_deprecated cancel(p, "Oops!", :green)

p = ProgressThresh(0.1; dt=0)
update!(p, 0.9)
@test_deprecated update!(p, 0.5, :blue)
sleep(0.5)
@test_deprecated cancel(p, "Oops!", :green)
