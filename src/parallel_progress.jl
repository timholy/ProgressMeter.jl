
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
    return ParallelProgress(Progress(n; kw...))
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
            while !has_finished(progress) && !has_finished(pp)
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
                end
            end
        catch err
            println()
            # channel closed should only happen from Base.close(pp), which isn't an error
            if err != Base.closed_exception()
                bt = catch_backtrace()
                showerror(stderr, err, bt)
                println()
            end
        finally
            close(pp)
        end
    end
    return pp
end


"""
    FakeChannel()

fake RemoteChannel that doesn't put anything anywhere (for allowing overshoot)
"""
struct FakeChannel end
Base.close(::FakeChannel) = nothing
Base.isready(::FakeChannel) = false
Distributed.put!(::FakeChannel, _...) = nothing

struct MultipleChannel
    channel
    id
end
Distributed.put!(mc::MultipleChannel, x) = put!(mc.channel, (mc.id, x...))

mutable struct MultipleProgress
    channel
    amount::Int
end

Base.getindex(mp::MultipleProgress, n) = ParallelProgress.(MultipleChannel.(Ref(mp.channel), n))
Base.lastindex(mp::MultipleProgress) = mp.amount

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
julia> p = MultipleProgress(fill(10,5); desc="global ", kws=[(desc="task \$i ",) for i in 1:5])
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
function MultipleProgress(progresses::AbstractVector{Progress}; 
                          count_finishes=false, kwmain=(), kw...)
    main_length = count_finishes ? length(progresses) : sum(p->p.n, progresses)
    mainprogress = Progress(main_length; kwmain...)
    return MultipleProgress(progresses, mainprogress; count_finishes=count_finishes, kw...)
end

function MultipleProgress(
        progresses::AbstractVector{<:AbstractProgress},
        mainprogress::AbstractProgress;
        count_finishes = false,
        count_overshoot = false,
        auto_reset_timer = true
    )
    channel = RemoteChannel(() -> Channel{NTuple{4,Any}}(1024))
    mp = MultipleProgress(channel, length(progresses))
    @async runMultipleProgress(progresses, mainprogress, mp;
        count_finishes=count_finishes, 
        count_overshoot=count_overshoot, 
        auto_reset_timer=auto_reset_timer)
    return mp
end

function runMultipleProgress(
        progresses::AbstractVector{<:AbstractProgress},
        mainprogress::AbstractProgress,
        mp::MultipleProgress;
        count_finishes = false,
        count_overshoot = false,
        auto_reset_timer = true
    )
    for p in progresses
        p.offset = -1
    end

    channel = mp.channel
    taken_offsets = Set{Int}()        
    max_offsets = 1
    try
        # we must make sure that 2 progresses aren't updated at the same time, 
        # that's why we use only one Channel
        while !has_finished(mainprogress) && !all(has_finished, progresses)
            
            p, f, args, kwt = take!(channel)

            # main progressbar
            if p == 0
                if f == PP_CANCEL
                    mainprogress.counter = mainprogress.n
                    cancel(mainprogress, args...; kwt...)
                    break
                elseif f == PP_UPDATE
                    if !isempty(args) && args[1] == (:)
                        update!(mainprogress, mainprogress.counter, args[2:end]...; kwt...)
                    else
                        update!(mainprogress, args...; kwt...)
                    end
                elseif f == PP_NEXT
                    next!(mainprogress, args...; kwt...)
                elseif f == PP_FINISH
                    finish!(mainprogress, args...; kwt...)
                    break
                end
            else

                # first time calling progress p
                if progresses[p].offset == -1
                    # find first available offset
                    offset = 1
                    while offset ∈ taken_offsets
                        offset += 1
                    end
                    max_offsets = max(max_offsets, offset)
                    progresses[p].offset = offset
                    if auto_reset_timer
                        progresses[p].tinit = progresses[p].tsecond = progresses[p].tlast = time()
                    end
                    push!(taken_offsets, offset)
                end

                if f == PP_NEXT
                    if count_overshoot || !has_finished(progresses[p])
                        next!(progresses[p], args...; kwt...)
                        next!(mainprogress)
                    end
                else
                    prev_p_value = progresses[p].counter
                    
                    if f == PP_FINISH
                        finish!(progresses[p], args...; kwt...)
                    elseif f == PP_CANCEL
                        #finish!(progresses[p])
                        cancel(progresses[p], args...; kwt...)
                        progresses[p].counter = progresses[p].n
                    elseif f == PP_UPDATE
                        if !isempty(args)
                            value = args[1]
                            value == (:) && (value = progresses[p].counter)
                            !count_overshoot && (value = min(value, progresses[p].n))
                            update!(progresses[p], value, args[2:end]...; kwt...)
                        else
                            update!(progresses[p]; kwt...)
                        end
                    end

                    update!(mainprogress, 
                            mainprogress.counter - prev_p_value + progresses[p].counter)
                end

                if has_finished(progresses[p])
                    delete!(taken_offsets, progresses[p].offset)
                end
            end
        end
    catch err
        # channel closed should only happen from Base.close(mp), which isn't an error
        if err != Base.closed_exception()
            bt = catch_backtrace()
            println()
            showerror(stderr, err, bt)
            println()
        end
    finally
        print("\n" ^ max_offsets)
        # progress with offset 0 adds automatically a line break when finished (#215)
        if !has_finished(mainprogress) || mainprogress.enabled == false
            println()
        end
        close(mp)
    end
end



"""
    close(p::Union{ParallelProgress,MultipleProgress})

empties and closes the channel of the progress and replaces it with a `FakeChannel` to allow overshoot

"""
function Base.close(p::Union{ParallelProgress,MultipleProgress})
    channel = p.channel
    p.channel = FakeChannel()
    while isready(channel) # empty channel to avoid waiting `put!`
        take!(channel)
    end
    close(channel)
end

has_finished(p::Progress) = p.counter >= p.n
has_finished(p::ProgressThresh) = p.triggered
has_finished(p::ProgressUnknown) = p.done
has_finished(p::ParallelProgress) = isfakechannel(p.channel)
has_finished(p::MultipleProgress) = isfakechannel(p.channel)
isfakechannel(_) = false
isfakechannel(::FakeChannel) = true
isfakechannel(mc::MultipleChannel) = isfakechannel(mc.channel)
