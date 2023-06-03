
mutable struct ParallelProgress <: AbstractProgress
    channel
end

@enum ProgressAction begin
    PP_NEXT
    PP_CANCEL
    PP_FINISH
    PP_UPDATE
    MP_ADD_THRESH
    MP_ADD_UNKNOWN
    MP_ADD_PROGRESS
end

next!(pp::ParallelProgress, args...; kw...) = (put!(pp.channel, (PP_NEXT, args, kw)); nothing)
cancel(pp::ParallelProgress, args...; kw...) = (put!(pp.channel, (PP_CANCEL, args, kw)); nothing)
finish!(pp::ParallelProgress, args...; kw...) = (put!(pp.channel, (PP_FINISH, args, kw)); nothing)
update!(pp::ParallelProgress, args...; kw...) = (put!(pp.channel, (PP_UPDATE, args, kw)); nothing)

"""
`ParallelProgress(n; kw...)`

works like `Progress` but can be used from other workers

# Example:
```julia
using Distributed
addprocs()
@everywhere using ProgressMeter
prog = ParallelProgress(10; desc="test ")
pmap(1:10) do i
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
    MultipleProgress(progresses::AbstractVector{<:AbstractProgress},
                     [mainprogress::AbstractProgress];
                     enabled = true,
                     auto_close = true,
                     count_finishes = false,
                     count_overshoot = false,
                     auto_reset_timer = true)

allows to call the `progresses` and `mainprogress` from different workers
 - `progresses`: contains the different progressbars
 - `mainprogress`: main progressbar, defaults to `Progress` or `ProgressUnknown`,
 according to `count_finishes` and whether all progresses have known length or not
 - `enabled`: `enabled == false` doesn't show anything and doesn't open a channel
 - `auto_close`: if true, the channel will close when all progresses are finished, otherwise,
 when mainprogress finishes or with `close(p)`
 - `count_finishes`: if false, main_progress will be the sum of the individual progressbars,
 if true, it will be equal to the number of finished progressbars
 - `count_overshoot`: overshooting progressmeters will be counted in the main progressmeter
 - `auto_reset_timer`: tinit in progresses will be reset at first call

use p[i] to access the i-th progressmeter, and p[0] to access the main one

# Example
```julia
using Distributed
addprocs(2)
@everywhere using ProgressMeter
p = MultipleProgress([Progress(10; desc="task \$i ") for i in 1:5], Progress(50; desc="global "))
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
function MultipleProgress(progresses::AbstractVector{<:AbstractProgress},
                          mainprogress::AbstractProgress;
                          enabled = true,
                          auto_close = true,
                          count_finishes = false,
                          count_overshoot = false,
                          auto_reset_timer = true)
    !enabled && return MultipleProgress(FakeChannel(), length(progresses))

    channel = RemoteChannel(() -> Channel{NTuple{4,Any}}(1024))
    mp = MultipleProgress(channel, length(progresses))
    @async runMultipleProgress(progresses, mainprogress, mp;
        auto_close=auto_close,
        count_finishes=count_finishes, 
        count_overshoot=count_overshoot, 
        auto_reset_timer=auto_reset_timer)
    return mp
end

function MultipleProgress(progresses::AbstractVector{Progress}; 
                          count_finishes=false, kwmain=(), kw...)
    main_length = count_finishes ? length(progresses) : sum(p->p.n, progresses)
    mainprogress = Progress(main_length; kwmain...)
    return MultipleProgress(progresses, mainprogress; count_finishes=count_finishes, kw...)
end

function MultipleProgress(progresses::AbstractVector{<:AbstractProgress}; 
                          count_finishes=false, kwmain=(), kw...)
    if count_finishes
        MultipleProgress(progresses, Progress(length(progresses); kwmain...); count_finishes=count_finishes, kw...)
    else
        MultipleProgress(progresses, ProgressUnknown(; kwmain...); count_finishes=count_finishes, kw...)
    end
end

"""
    MultipleProgress(mainprogress=ProgressUnknown(); auto_close=false, kw...)

is equivalent to

    MultipleProgress(AbstractProgress[], mainprogress; auto_close, kw...)

See also: `addprogress!`

Close the underlying channel with `finish!(p[0])` (finishes `mainprogress`) or `close(p)`.
"""
function MultipleProgress(mainprogress::AbstractProgress=ProgressUnknown(); auto_close=false, kw...)
    return MultipleProgress(AbstractProgress[], mainprogress; auto_close=auto_close, kw...)
end

function runMultipleProgress(progresses::AbstractVector{<:AbstractProgress},
                             mainprogress::AbstractProgress,
                             mp::MultipleProgress;
                             auto_close = true,
                             count_finishes = false,
                             count_overshoot = false,
                             auto_reset_timer = true)
    for p in progresses
        p.offset = -1
    end

    channel = mp.channel
    taken_offsets = Set{Int}()        
    max_offsets = 1
    try
        # we must make sure that 2 progresses aren't updated at the same time, 
        # that's why we use only one Channel
        while !has_finished(mainprogress) && !(auto_close && all(has_finished, progresses))
            
            p, f, args, kwt = take!(channel)

            if p == 0 # main progressbar
                if f == PP_CANCEL
                    finish!(mainprogress; keep=false)
                    cancel(mainprogress, args...; kwt..., keep=false)
                    break
                elseif f == PP_UPDATE 
                    update!(mainprogress, args...; kwt..., keep=false)
                elseif f == PP_NEXT
                    next!(mainprogress, args...; kwt..., keep=false)
                elseif f == PP_FINISH
                    finish!(mainprogress, args...; kwt..., keep=false)
                    break
                end
            else
                # add progress
                if f == MP_ADD_PROGRESS
                    resize!(progresses, max(length(progresses), p))
                    mp.amount = length(progresses)
                    progresses[p] = Progress(args...; kwt..., offset=-1)
                    continue
                elseif f == MP_ADD_UNKNOWN
                    resize!(progresses, max(length(progresses), p))
                    mp.amount = length(progresses)
                    progresses[p] = ProgressUnknown(args...; kwt..., offset=-1)
                    continue
                elseif f == MP_ADD_THRESH
                    resize!(progresses, max(length(progresses), p))
                    mp.amount = length(progresses)
                    progresses[p] = ProgressThresh(args...; kwt..., offset=-1)
                    continue
                end

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
                        progresses[p].tinit = time()
                    end
                    push!(taken_offsets, offset)
                end

                already_finished = has_finished(progresses[p])

                if f == PP_NEXT
                    if count_overshoot || !has_finished(progresses[p])
                        next!(progresses[p], args...; kwt..., keep=false)
                        !count_finishes && next!(mainprogress; keep=false)
                    end
                else
                    prev_p_counter = progresses[p].counter
                    
                    if f == PP_FINISH
                        finish!(progresses[p], args...; kwt..., keep=false)
                    elseif f == PP_CANCEL
                        finish!(progresses[p]; keep=false)
                        cancel(progresses[p], args...; kwt..., keep=false)
                    elseif f == PP_UPDATE
                        if !isempty(args)
                            value = args[1]
                            !count_overshoot && progresses[p] isa Progress && (value = min(value, progresses[p].n))
                            update!(progresses[p], value, args[2:end]...; kwt..., keep=false)
                        else
                            update!(progresses[p]; kwt..., keep=false)
                        end
                    end

                    !count_finishes && update!(mainprogress, 
                        mainprogress.counter - prev_p_counter + progresses[p].counter; keep=false)
                end

                if !already_finished && has_finished(progresses[p])
                    delete!(taken_offsets, progresses[p].offset)
                    count_finishes && next!(mainprogress; keep=false)
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
        print("\n" ^ (max_offsets+1))
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

"""
    addprogress!(mp[i], T::Type{<:AbstractProgress}, args...; kw...)

will add the progressbar `T(args..., kw...)` to the MultipleProgress `mp` at index `i`

# Example

```julia
p = MultipleProgress(Progress(N, "tasks done "); count_finishes=true)
sleep(0.1)
pmap(1:N) do i
    L = rand(20:50)
    addprogress!(p[i], Progress, L, desc=" task \$i ")
    for _ in 1:L
        sleep(0.05)
        next!(p[i])
    end
end

```
"""
addprogress!(p::ParallelProgress, ::Type{Progress}, args...; kw...) = (put!(p.channel, (MP_ADD_PROGRESS, args, kw)); nothing)
addprogress!(p::ParallelProgress, ::Type{ProgressThresh}, args...; kw...) = (put!(p.channel, (MP_ADD_THRESH, args, kw)); nothing)
addprogress!(p::ParallelProgress, ::Type{ProgressUnknown}, args...; kw...) = (put!(p.channel, (MP_ADD_UNKNOWN, args, kw)); nothing)
