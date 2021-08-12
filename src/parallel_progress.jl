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

function ParallelProgress(n::Integer; kw...)
    return ParallelProgress(Progress(n; kw...); kw...)
end

function ParallelProgress(progress::AbstractProgress)
    channel = RemoteChannel(() -> Channel{NTuple{3,Any}}(1024))
    pp = ParallelProgress(channel)
    
    @async begin
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
        
        pp.channel = FakeChannel()
        while isready(channel)
            take!(channel)
        end
        close!(channel)
    end
    return pp
end

has_finished(p::Progress) = p.counter >= p.n
has_finished(p::ProgressThresh) = p.triggered
has_finished(p::ProgressUnknown) = p.done

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

Base.getindex(mp::MultipleProgress, n) = ParallelProgress.(MultipleChannel.(Ref(mp.channel), n))
Base.lastindex(mp::MultipleProgress) = mp.amount

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
                          count_overshoot = false,
                          mainprogress = true,
                          kws = [() for _ in lengths],
                          kw...)
    @assert length(lengths) == length(kws) "`length(lengths)` must be equal to `length(kws)`"
    amount = length(lengths)

    total_length = sum(lengths)
    mainprogress && (main_progress = Progress(total_length; offset=0, kw...))
    progresses = Union{Progress,Nothing}[nothing for _ in 1:amount]
    taken_offsets = Set{Int}()
    mainprogress && push!(taken_offsets, 0)
    channel = RemoteChannel(() -> Channel{NTuple{4,Any}}())

    max_offsets = 0

    mp = MultipleProgress(channel, amount, collect(lengths))

    # we must make sure that 2 progresses aren't updated at the same time, 
    # that's why we use only one Channel
    @async begin
        try
            while main_progress.counter < total_length
                
                p, f, args, kw = take!(channel)

                # main progressbar
                if p == 0
                    mainprogress || continue
                    if f == PP_CANCEL
                        cancel(main_progress, args...; kw...)
                        break
                    elseif f == PP_UPDATE
                        if !isempty(args) && args[1] == (:)
                            update!(main_progress, main_progress.counter, args[2:end]...; kw...)
                        else
                            update!(main_progress, args...; kw...)
                        end
                    elseif f == PP_NEXT
                        next!(main_progress, args...; kw...)
                    elseif f == PP_FINISH
                        finish!(main_progress, args...; kw...)
                    end
                else

                    # first time calling progress p
                    if isnothing(progresses[p])
                        # find first available offset
                        offset = 0
                        while offset in taken_offsets
                            offset += 1
                        end
                        max_offsets = max(max_offsets, offset)
                        progresses[p] = Progress(lengths[p]; offset=offset, kws[p]...)
                        push!(taken_offsets, offset)
                    end


                    if f == PP_NEXT
                        if count_overshoot || progresses[p].counter < lengths[p]
                            next!(progresses[p], args...; kw...)
                            mainprogress && next!(main_progress)
                        end
                    else
                        prev_p_value = progresses[p].counter
                        
                        if f == PP_FINISH
                            finish!(progresses[p], args...; kw...)
                        elseif f == PP_CANCEL
                            finish!(progresses[p])
                            cancel(progresses[p], args...; kw...)
                        elseif f == PP_UPDATE
                            if !isempty(args)
                                value = args[1]
                                value == (:) && (value = progresses[p].counter)
                                !count_overshoot && (value = min(value, lengths[p]))
                                update!(progresses[p], value, args[2:end]...; kw...)
                            else
                                update!(progresses[p]; kw...)
                            end
                        end

                        mainprogress && update!(main_progress, 
                                main_progress.counter - prev_p_value + progresses[p].counter)
                    end

                    if progresses[p].counter >= lengths[p]
                        delete!(taken_offsets, progresses[p].offset)
                    end
                end
            end
        catch e
            println("ERROR")
            println(e)
        end
        mp.channel = FakeChannel()
        while isready(channel)
            take!(channel)
        end
        close(channel)
        print("\n" ^ max_offsets)
    end

    return mp
end

