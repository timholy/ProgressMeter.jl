"""
`prog = ParallelProgress(n; kw...)`

works like `Progress` but can be used from other workers
Extra arguments after `update` or `cancel` are ignored

# Example:
```jldoctest
julia> using Distributed
julia> addprocs()
julia> @everywhere using ProgressMeter
julia> prog = ParallelProgress(10; desc="test ")
julia> pmap(1:10) do
           sleep(rand())
           next!(prog)
           return myid()
       end
```
"""
struct ParallelProgress{C}
    channel::C
    n::Int
end

const PP_NEXT = -1
const PP_FINISH = -2
const PP_CANCEL = -3

next!(pp::ParallelProgress) = put!(pp.channel, PP_NEXT)
finish!(pp::ParallelProgress) = put!(pp.channel, PP_FINISH)
cancel(pp::ParallelProgress, args...; kw...) = put!(pp.channel, PP_CANCEL)
update!(pp::ParallelProgress, counter, color = nothing) = put!(pp.channel, counter)

function ParallelProgress(n::Int; kw...)
    channel = RemoteChannel(() -> Channel{Int}(n))
    progress = Progress(n; kw...)
    
    @async while progress.counter < progress.n
        f = take!(channel)
        if f == PP_NEXT
            next!(progress)
        elseif f == PP_FINISH
            finish!(progress)
            break
        elseif f == PP_CANCEL
            cancel(progress)
            break
        elseif f >= 0
            update!(progress, f)
        end
    end
    return ParallelProgress(channel, n)
end

struct MultipleChannel{C}
    channel::C
    id
end
Distributed.put!(mc::MultipleChannel, x) = put!(mc.channel, (mc.id, x))


struct MultipleProgress{C}
    channel::C
    amount::Int
    lengths::Vector{Int}
end

Base.getindex(mp::MultipleProgress, n::Integer) = ParallelProgress(MultipleChannel(mp.channel, n), mp.lengths[n])
finish!(mp::MultipleProgress) = put!.([mp.channel], [(p, PP_FINISH) for p in 1:mp.amount])


"""
    prog = MultipleProgress(amount, lengths; kw...)

equivalent to 

    MultipleProgress(lengths*ones(T,amount); kw...)

"""
function MultipleProgress(amount::Integer, lengths::T; kw...) where T <: Integer
    MultipleProgress(lengths*ones(T,amount); kw...)
end


"""
    prog = MultipleProgress(lengths; kws, kw...)

generates one progressbar for each value in `lengths` and one for a global progressbar
 - `kw` arguments are applied on all progressbars
 - `kws[i]` arguments are applied on the i-th progressbar

# Example
```jldoctest
julia> using Distributed
julia> addprocs(2)
julia> @everywhere using ProgressMeter
julia> p = MultipleProgress(5,10; desc="global ", kws=[(desc="task \$i ",) for i in 1:5])
       pmap(1:5) do x
           for i in 1:10
               sleep(rand())
               next!(p[x])
           end
           sleep(0.01)
           myid()
       end
```
"""
function MultipleProgress(lengths::AbstractVector{<:Integer}; 
                          kws = [() for _ in lengths],
                          kw...)
    @assert length(lengths) == length(kws) "`length(lengths)` must be equal to `length(kws)`"
    amount = length(lengths)

    total_length = sum(lengths)
    main_progress = Progress(total_length; offset=0, kw...)
    progresses = Union{Progress,Nothing}[nothing for _ in 1:amount]
    taken_offsets = Set(Int[])
    channel = RemoteChannel(() -> Channel{Tuple{Int,Int}}(max(2amount, 64)))

    max_offsets = 1

    # we must make sure that 2 progresses aren't updated at the same time, 
    # that's why we use only one Channel
    @async begin
        while true
            
            (p, value) = take!(channel)

            # first time calling progress p
            if isnothing(progresses[p])
                # find first available offset
                offset = 1
                while offset in taken_offsets
                    offset += 1
                end
                max_offsets = max(max_offsets, offset)
                progresses[p] = Progress(lengths[p]; offset=offset, kw..., kws[p]...)
                push!(taken_offsets, offset)
            end

            if value == PP_NEXT
                next!(progresses[p])
                next!(main_progress)
            else
                prev_p_value = progresses[p].counter
                
                if value == PP_FINISH
                    finish!(progresses[p])
                elseif value == PP_CANCEL
                    cancel(progresses[p])
                elseif value >= 0
                    update!(progresses[p], value)
                end

                update!(main_progress, 
                        main_progress.counter - prev_p_value + progresses[p].counter)
            end

            if progresses[p].counter >= lengths[p]
                delete!(taken_offsets, progresses[p].offset)
            end

            main_progress.counter >= total_length && break
        end

        print("\n" ^ max_offsets)
    end

    return MultipleProgress(channel, amount, collect(lengths))
end


