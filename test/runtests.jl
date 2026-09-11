using ProgressMeter
using Test

if get(ENV, "CI", "false") == "true"
    using InteractiveUtils
    display(versioninfo())   # among other things, this shows the number of threads
end

@testset "Without Distributed" begin
    @test Base.get_extension(ProgressMeter, :ProgressMeterDistributedExt) === nothing
    @test progress_map(x -> x^2, 1:10) == map(x -> x^2, 1:10)
    @test_throws ArgumentError @macroexpand @showprogress @distributed for i in 1:10 end
end

using Distributed

@testset "Core" begin
    include("core.jl")
    include("test.jl")
end
@testset "Show Values" begin
    include("test_showvalues.jl")
end
@testset "Mapping" begin
    include("test_map.jl")
end
@testset "Float" begin
    include("test_float.jl")
end
@testset "Threading" begin
    include("test_threads.jl")
end
@testset "Deprecated" begin
    include("deprecated.jl")
end
