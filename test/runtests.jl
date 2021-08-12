import ProgressMeter
using Test

# include("core.jl")
# include("test.jl")
# include("test_showvalues.jl")
# include("test_map.jl")
# include("test_float.jl")
# include("test_threads.jl")
include("test_parallel.jl")
#include("test_parallel_update.jl")

println("")
println("All tests complete")
