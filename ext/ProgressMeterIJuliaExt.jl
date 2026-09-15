module ProgressMeterIJuliaExt

using ProgressMeter, IJulia

# registered in `ProgressMeter.IJULIA_BACKEND` when this extension loads, so
# the hooks in ProgressMeter dispatch here instead of to the inert defaults
struct WithIJulia <: ProgressMeter.IJuliaBackend end

ProgressMeter.ijulia_loaded(::WithIJulia) = true
ProgressMeter.ijulia_running(::WithIJulia) = IJulia.inited::Bool
ProgressMeter.ijulia_clear_output(::WithIJulia) = (IJulia.clear_output(true); nothing)

# issue #76: circumvent IJulia I/O throttling.  only with a running kernel:
# `reset_stdio_count` dereferences the default kernel, which is `nothing` otherwise
if pkgversion(IJulia) < v"1.30"
    ProgressMeter.ijulia_reset_stdio(::WithIJulia) = (IJulia.inited && (IJulia.stdio_bytes[] = 0); nothing)
else
    ProgressMeter.ijulia_reset_stdio(::WithIJulia) = (IJulia.inited && IJulia.reset_stdio_count(); nothing)
end

function __init__()
    ProgressMeter.IJULIA_BACKEND[] = WithIJulia()
end

end # module
