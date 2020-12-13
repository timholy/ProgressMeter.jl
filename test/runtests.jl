using ProgressMeter
using Test

if get(ENV, "CI", "false") == "true"
    using InteractiveUtils
    display(versioninfo())   # among other things, this shows the number of threads
end

include("core.jl")
include("test.jl")
include("test_showvalues.jl")
include("test_map.jl")
include("test_float.jl")
include("test_threads.jl")


println("")
println("All tests complete")
