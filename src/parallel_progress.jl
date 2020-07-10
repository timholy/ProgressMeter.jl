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
mutable struct ParallelProgress
    channel
end

const PP_NEXT = :next
const PP_CANCEL = :cancel
const PP_FINISH = :finish
const PP_UPDATE = :update

next!(pp::ParallelProgress, args...; kw...) = put!(pp.channel, (PP_NEXT, args, kw))
cancel(pp::ParallelProgress, args...; kw...) = put!(pp.channel, (PP_CANCEL, args, kw))
finish!(pp::ParallelProgress, args...; kw...) = put!(pp.channel, (PP_FINISH, args, kw))
update!(pp::ParallelProgress, args...; kw...) = put!(pp.channel, (PP_UPDATE, args, kw))

function ParallelProgress(n::Integer; kw...)
    channel = RemoteChannel(() -> Channel{Tuple}(n))
    progress = Progress(n; kw...)
    pp = ParallelProgress(channel)
    
    @async begin 
        while progress.counter < progress.n
            f, args, kw = take!(channel)
            if f == PP_NEXT
                next!(progress, args...; kw...)
            elseif f == PP_CANCEL
                cancel(progress, args...; kw...)
                break
            elseif f == PP_FINISH
                finish!(progress, args...; kw...)
                break
            elseif f == PP_UPDATE
                update!(progress, args...; kw...)
            else
                error("not recognized: $f")
            end
        end
        # empty channel before ending it
        while isready(pp.channel)
            take!(pp.channel)
        end
        pp.channel = FakeChannel()
    end

    return pp
end

# fake channel to allow over-shoot
struct FakeChannel end
Distributed.put!(::FakeChannel, x) = nothing

struct MultipleChannel
    channel
    id
end
Distributed.put!(mc::MultipleChannel, x) = put!(mc.channel, (mc.id, x...))


mutable struct MultipleProgress
    channel
    amount::Int
    lengths::Vector{Int}
end

Base.getindex(mp::MultipleProgress, n) = ParallelProgress.(MultipleChannel.(fill(mp.channel), n))
Base.lastindex(mp::MultipleProgress) = mp.amount
finish!(mp::MultipleProgress, args...; kw...) = finish!.(mp[1:end])
cancel(mp::MultipleProgress, args...; kw...) = cancel.(mp[1:end])

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
                          count_overshoot::Bool = false,
                          kws = [() for _ in lengths],
                          kw...)
    @assert length(lengths) == length(kws) "`length(lengths)` must be equal to `length(kws)`"
    amount = length(lengths)

    total_length = sum(lengths)
    main_progress = Progress(total_length; offset=0, kw...)
    progresses = Union{Progress,Nothing}[nothing for _ in 1:amount]
    taken_offsets = Set(Int[])
    channel = RemoteChannel(() -> Channel{Tuple}(max(2amount, 64)))

    max_offsets = 1

    mp = MultipleProgress(channel, amount, collect(lengths))

    # we must make sure that 2 progresses aren't updated at the same time, 
    # that's why we use only one Channel
    @async begin
        while main_progress.counter < total_length
            
            p, f, args, kw = take!(channel)

            # main progressbar
            if p == 0
                if f == PP_CANCEL
                    cancel(main_progress, args...; kw...)
                    break
                elseif f == PP_UPDATE
                    update!(main_progress, args...; kw...)
                elseif f == PP_NEXT
                    next!(main_progress, args...; kw...)
                elseif f == PP_FINISH
                    finish!(main_progress, args...; kw...)
                end
            else

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


                if f == PP_NEXT
                    if count_overshoot || progresses[p].counter < lengths[p]
                        next!(progresses[p], args...; kw...)
                        next!(main_progress)
                    end
                else
                    prev_p_value = progresses[p].counter
                    
                    if f == PP_FINISH
                        finish!(progresses[p], args...; kw...)
                    elseif f == PP_CANCEL
                        finish!(progresses[p])
                        cancel(progresses[p], args...; kw...)
                    elseif f == PP_UPDATE
                        if !count_overshoot && !isempty(args)
                            value = min(args[1], lengths[n])
                            update!(progresses[p], value, args[2:end]...; kw...)
                        else
                            update!(progresses[p], args...; kw...)
                        end
                        
                    end

                    update!(main_progress, 
                            main_progress.counter - prev_p_value + progresses[p].counter)
                end

                if progresses[p].counter >= lengths[p]
                    delete!(taken_offsets, progresses[p].offset)
                end
            end
        end
        while isready(mp.channel)
            take!(mp.channel)
        end
        mp.channel = FakeChannel()
        print("\n" ^ max_offsets)
    end

    return mp
end

