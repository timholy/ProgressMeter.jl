module ProgressMeterDistributedExt

using Distributed
using ProgressMeter
using ProgressMeter: ncalls_map, showprogress_process_args

progress_channel(bufflen) = RemoteChannel(() -> Channel{Bool}(bufflen), 1)

ProgressMeter.progress_pmap(args...; kwargs...) = progress_map(args...; mapfun=pmap, kwargs...)

ProgressMeter.ncalls(::typeof(pmap), ::Function, args...) = ncalls_map(args...)
ProgressMeter.ncalls(::typeof(pmap), ::Function, ::AbstractWorkerPool, args...) = ncalls_map(args...)

"""
Equivalent of @showprogress for a distributed for loop.
```
result = @showprogress @distributed (+) for i = 1:50
    sleep(0.1)
    i^2
end
```
"""
function showprogressdistributed(args...)
    if length(args) < 1
        throw(ArgumentError("@showprogress @distributed requires at least 1 argument"))
    end
    progressargs = args[1:end-1]
    expr = Base.remove_linenums!(args[end])

    distargs = filter(x -> !(x isa LineNumberNode), expr.args[2:end])
    na = length(distargs)
    if na == 1
        loop = distargs[1]
    elseif na == 2
        reducer = distargs[1]
        loop = distargs[2]
    else
        println("$distargs $na")
        throw(ArgumentError("wrong number of arguments to @distributed"))
    end
    if loop.head !== :for
        throw(ArgumentError("malformed @distributed loop"))
    end
    var = loop.args[1].args[1]
    r = loop.args[1].args[2]
    body = loop.args[2]

    # Interpolate Distributed's bindings: unescaped names in the expansion
    # resolve in ProgressMeter, which does not import Distributed.
    if na == 1
        # would be nice to do this with @sync @distributed but @sync is broken
        # https://github.com/JuliaLang/julia/issues/28979
        compute = quote
            waiting = $Distributed.@distributed for $(esc(var)) = $(esc(r))
                $(esc(body))
                put!(ch, true)
            end
            wait(waiting)
            nothing
        end
    else
        compute = quote
            $Distributed.@distributed $(esc(reducer)) for $(esc(var)) = $(esc(r))
                x = $(esc(body))
                put!(ch, true)
                x
            end
        end
    end

    quote
        let n = length($(esc(r)))
            p = Progress(n, $(showprogress_process_args(progressargs)...))
            ch = $RemoteChannel(() -> Channel{Bool}(n))

            @async while take!(ch) next!(p) end
            results = $compute
            put!(ch, false)
            finish!(p)
            results
        end
    end
end

end # module
