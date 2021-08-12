
mutable struct ParallelProgress <: AbstractProgress
    channel
end

const PP_NEXT = :next
const PP_CANCEL = :cancel
const PP_FINISH = :finish
const PP_UPDATE = :update

next!(pp::ParallelProgress, args...; kw...) = (put!(pp.channel, (PP_NEXT, args, kw)); nothing)
cancel(pp::ParallelProgress, args...; kw...) = (put!(pp.channel, (PP_CANCEL, args, kw)); nothing)
finish!(pp::ParallelProgress, args...; kw...) = (put!(pp.channel, (PP_FINISH, args, kw)); nothing)
update!(pp::ParallelProgress, args...; kw...) = (put!(pp.channel, (PP_UPDATE, args, kw)); nothing)

"""
`ParallelProgress(n; kw...)`

works like `Progress` but can be used from other workers

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
function ParallelProgress(n::Integer; kw...)
    return ParallelProgress(Progress(n; kw...); kw...)
end

"""
`ParallelProgress(p::AbstractProgress)`

wrapper around any `Progress`, `ProgressThresh` and `ProgressUnknown` that can be used 
from other workers

"""
function ParallelProgress(progress::AbstractProgress)
    channel = RemoteChannel(() -> Channel{NTuple{3,Any}}(1024))
    pp = ParallelProgress(channel)
    
    @async begin
        try
            while !has_finished(progress)
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
                    error("not recognized: $(repr(f))")
                end
            end
        catch e
            println("ERROR")
            println(e)
            println()
        finally
            close(pp)
        end
    end
    return pp
end

has_finished(p::Progress) = p.counter >= p.n
has_finished(p::ProgressThresh) = p.triggered
has_finished(p::ProgressUnknown) = p.done

"""
    FakeChannel()

fake RemoteChannel that doesn't put anything anywhere (for allowing overshoot)
"""
struct FakeChannel end
Distributed.put!(::FakeChannel, x) = nothing

struct MultipleChannel
    channel
    id
end
Distributed.put!(mc::MultipleChannel, x) = put!(mc.channel, (mc.id, x...))

mutable struct MultipleProgress <: AbstractProgress
    channel
    amount::Int
    lengths::Vector{Int}
end

Base.getindex(mp::MultipleProgress, n) = ParallelProgress.(MultipleChannel.(Ref(mp.channel), n))
Base.lastindex(mp::MultipleProgress) = mp.amount

"""
    MultipleProgress(amount, lengths; kw...)

equivalent to 

    MultipleProgress(fill(lengths, amount); kw...)

"""
function MultipleProgress(amount::Integer, lengths::Integer; kw...)
    MultipleProgress(fill(lengths, amount); kw...)
end

"""
    MultipleProgress(lengths; mainprogress=true, count_overshoot=false, kws, kw...)

generates one progressbar for each value in `lengths`
 - `kw` arguments are applied on all progressbars
 - `kws[i]` arguments are applied on the i-th progressbar
 - `mainprogress` adds a main progressmeter that sums the other ones
 - `count_overshoot`: overshooting progressmeters will be counted in the main progressmeter

use p[i] to access the i-th progressmeter, and p[0] to access the main one

# Example
```jldoctest
julia> using Distributed
julia> addprocs(2)
julia> @everywhere using ProgressMeter
julia> p = MultipleProgress(5, 10; desc="global ", kws=[(desc="task \$i ",) for i in 1:5])
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
                          count_overshoot = false,
                          mainprogress = true,
                          kws = [() for _ in lengths],
                          kw...)
    @assert length(lengths) == length(kws) "`length(lengths)` must be equal to `length(kws)`"
    amount = length(lengths)

    total_length = sum(lengths)
    main_progress = Progress(total_length; offset=0, enabled=mainprogress, kw...)
    progresses = Union{Progress,Nothing}[nothing for _ in 1:amount]
    taken_offsets = Set{Int}()
    mainprogress && push!(taken_offsets, 0)
    channel = RemoteChannel(() -> Channel{NTuple{4,Any}}(1024))

    max_offsets = 0

    mp = MultipleProgress(channel, amount, collect(lengths))

    # we must make sure that 2 progresses aren't updated at the same time, 
    # that's why we use only one Channel
    @async begin
        try
            while main_progress.counter < total_length
                
                p, f, args, kwt = take!(channel)

                # main progressbar
                if p == 0
                    if f == PP_CANCEL
                        mainprogress || cancel(main_progress, args...; kwt...)
                        break
                    elseif f == PP_UPDATE
                        if !isempty(args) && args[1] == (:)
                            update!(main_progress, main_progress.counter, args[2:end]...; kwt...)
                        else
                            update!(main_progress, args...; kwt...)
                        end
                    elseif f == PP_NEXT
                        next!(main_progress, args...; kwt...)
                    elseif f == PP_FINISH
                        finish!(main_progress, args...; kwt...)
                        break
                    end
                else

                    # first time calling progress p
                    if progresses[p] === nothing
                        # find first available offset
                        offset = 0
                        while offset in taken_offsets
                            offset += 1
                        end
                        max_offsets = max(max_offsets, offset)
                        progresses[p] = Progress(lengths[p]; offset=offset, kw..., kws[p]...)
                        push!(taken_offsets, offset)
                    end


                    if f == PP_NEXT
                        if count_overshoot || progresses[p].counter < lengths[p]
                            next!(progresses[p], args...; kwt...)
                            next!(main_progress)
                        end
                    else
                        prev_p_value = progresses[p].counter
                        
                        if f == PP_FINISH
                            finish!(progresses[p], args...; kwt...)
                        elseif f == PP_CANCEL
                            finish!(progresses[p])
                            cancel(progresses[p], args...; kwt...)
                        elseif f == PP_UPDATE
                            if !isempty(args)
                                value = args[1]
                                value == (:) && (value = progresses[p].counter)
                                !count_overshoot && (value = min(value, lengths[p]))
                                update!(progresses[p], value, args[2:end]...; kwt...)
                            else
                                update!(progresses[p]; kwt...)
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
        finally
            close(mp)
            print("\n" ^ max_offsets)
        end
    end

    return mp
end

function Base.close(p::Union{ParallelProgress,MultipleProgress})
    channel = p.channel
    p.channel = FakeChannel()
    while isready(channel)
        take!(channel)
    end
    close(channel)
end