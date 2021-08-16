using ProgressMeter
using Test

if get(ENV, "CI", "false") == "true"
    using InteractiveUtils
    display(versioninfo())   # among other things, this shows the number of threads
end

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
@testset "Parallel" begin
    include("test_parallel.jl")
    include("test_multiple.jl")
end
