module ProgressMeter

using Printf: @sprintf
using Distributed

export Progress, ProgressThresh, ProgressUnknown, BarGlyphs, next!, update!, cancel, finish!, @showprogress, progress_map, progress_pmap, ijulia_behavior

"""
`ProgressMeter` contains a suite of utilities for displaying progress
in long-running computations. The major functions/types in this module
are:

- `@showprogress`: an easy interface for straightforward situations
- `Progress`: an object for managing progress updates with a predictable number of iterations
- `ProgressThresh`: an object for managing progress updates where termination is governed by a threshold
- `next!` and `update!`: report that progress has been made
- `cancel` and `finish!`: early termination
"""
ProgressMeter

abstract type AbstractProgress end

"""
Holds the five characters that will be used to generate the progress bar.
"""
mutable struct BarGlyphs
    leftend::Char
    fill::Char
    front::Union{Vector{Char}, Char}
    empty::Char
    rightend::Char
end

"""
String constructor for BarGlyphs - will split the string into 5 chars
"""
function BarGlyphs(s::AbstractString)
    glyphs = (s...,)
    if !isa(glyphs, NTuple{5,Char})
        error("""
            Invalid string in BarGlyphs constructor.
            You supplied "$s".
            Note: string argument must be exactly 5 characters long, e.g. "[=> ]".
        """)
    end
    return BarGlyphs(glyphs...)
end
const defaultglyphs = BarGlyphs('|','█', Sys.iswindows() ? '█' : ['▏','▎','▍','▌','▋','▊','▉'],' ','|',)

# Internal struct for holding common properties and internals for progress meters
Base.@kwdef mutable struct ProgressCore
    color::Symbol               = :green        # color of the meter
    desc::String                = "Progress: "  # prefix to the percentage, e.g.  "Computing..."
    dt::Real                    = Float64(0.1)  # minimum time between updates
    enabled::Bool               = true          # is the output enabled
    offset::Int                 = 0             # position offset of progress bar (default is 0)
    output::IO                  = stderr        # output stream into which the progress is written
    showspeed::Bool             = false         # should the output include average time per iteration
    # internals
    check_iterations::Int       = 1             # number of iterations to check time for
    counter::Int                = 0             # current iteration
    lock::Threads.ReentrantLock = Threads.ReentrantLock()   # lock used when threading detected
    numprintedvalues::Int       = 0             # num values printed below progress in last iteration
    prev_update_count::Int      = 1             # counter at last update
    printed::Bool               = false         # true if we have issued at least one status update
    threads_used::Vector{Int}   = Int[]         # threads that have used this progress meter
    tinit::Float64              = time()        # time meter was initialized
    tlast::Float64              = time()        # time of last update
    tsecond::Float64            = time()        # ignore the first loop given usually uncharacteristically slow
end

"""
`prog = Progress(n; dt=0.1, desc="Progress: ", color=:green,
output=stderr, barlen=tty_width(desc), start=0)` creates a progress meter for a
task with `n` iterations or stages starting from `start`. Output will be
generated at intervals at least `dt` seconds apart, and perhaps longer if each
iteration takes longer than `dt`. `desc` is a description of
the current task. Optionally you can disable the progress bar by setting
`enabled=false`. You can also append a per-iteration average duration like
"(12.34 ms/it)" to the description by setting `showspeed=true`.
"""
mutable struct Progress <: AbstractProgress
    n::Int                  # total number of iterations
    start::Int              # which iteration number to start from
    barlen::Union{Int,Nothing} # progress bar size (default is available terminal width)
    barglyphs::BarGlyphs    # the characters to be used in the bar
    # internals
    core::ProgressCore

    function Progress(
            n::Integer;
            start::Integer=0,
            barlen::Union{Int,Nothing}=nothing,
            barglyphs::BarGlyphs=defaultglyphs,
            kwargs...)
        CLEAR_IJULIA[] = clear_ijulia()
        core = ProgressCore(;kwargs...)
        new(n, start, barlen, barglyphs, core)
    end
end
# forward common core properties to main types
function Base.setproperty!(p::T, name::Symbol, value) where T<:AbstractProgress
    if hasfield(T, name)
        setfield!(p, name, value)
    else
        setproperty!(p.core, name, value)
    end
end
function Base.getproperty(p::T, name::Symbol) where T<:AbstractProgress
    if hasfield(T, name)
        getfield(p, name)
    else
        getproperty(p.core, name)
    end
end

"""
`prog = ProgressThresh(thresh; dt=0.1, desc="Progress: ",
color=:green, output=stderr)` creates a progress meter for a task
which will terminate once a value less than or equal to `thresh` is
reached. Output will be generated at intervals at least `dt` seconds
apart, and perhaps longer if each iteration takes longer than
`dt`. `desc` is a description of the current task. Optionally you can disable
the progress meter by setting `enabled=false`. You can also append a
per-iteration average duration like "(12.34 ms/it)" to the description by
setting `showspeed=true`.
"""
mutable struct ProgressThresh{T<:Real} <: AbstractProgress
    thresh::T           # termination threshold
    val::T              # current value
    # internals
    triggered::Bool     # has the threshold been reached?
    core::ProgressCore  # common properties and internals

    function ProgressThresh{T}(thresh; val::T=typemax(T), triggered::Bool=false, kwargs...) where T
        CLEAR_IJULIA[] = clear_ijulia()
        core = ProgressCore(;kwargs...)
        new{T}(thresh, val, triggered, core)
    end
end
ProgressThresh(thresh::Real; kwargs...) = ProgressThresh{typeof(thresh)}(thresh; kwargs...)


"""
`prog = ProgressUnknown(; dt=0.1, desc="Progress: ",
color=:green, output=stderr)` creates a progress meter for a task
which has a non-deterministic termination criterion.
Output will be generated at intervals at least `dt` seconds
apart, and perhaps longer if each iteration takes longer than
`dt`. `desc` is a description of the current task. Optionally you can disable
the progress meter by setting `enabled=false`. You can also append a
per-iteration average duration like "(12.34 ms/it)" to the description by
setting `showspeed=true`.  Instead of displaying a counter, it
can optionally display a spinning ball by passing `spinner=true`.
"""
mutable struct ProgressUnknown <: AbstractProgress
    # internals
    done::Bool              # is the task done?
    spinner::Bool           # show a spinner
    spincounter::Int        # counter for spinner
    core::ProgressCore      # common properties and internals

    function ProgressUnknown(; spinner::Bool=false, kwargs...)
        CLEAR_IJULIA[] = clear_ijulia()
        core = ProgressCore(;kwargs...)
        new(false, spinner, 0, core)
    end
end

#...length of percentage and ETA string with days is 29 characters, speed string is always 14 extra characters
function tty_width(desc, output, showspeed::Bool)
    full_width = displaysize(output)[2]
    desc_width = length(desc)
    eta_width = 29
    speed_width = showspeed ? 14 : 0
    return max(0, full_width - desc_width - eta_width - speed_width)
end

# Package level behavior of IJulia clear output
@enum IJuliaBehavior IJuliaWarned IJuliaClear IJuliaAppend

const IJULIABEHAVIOR = Ref(IJuliaWarned)

function ijulia_behavior(b)
    @assert b in [:warn, :clear, :append]
    b == :warn && (IJULIABEHAVIOR[] = IJuliaWarned)
    b == :clear && (IJULIABEHAVIOR[] = IJuliaClear)
    b == :append && (IJULIABEHAVIOR[] = IJuliaAppend)
end

# Whether or not to use IJulia.clear_output
const CLEAR_IJULIA = Ref{Bool}(false)
running_ijulia_kernel() = isdefined(Main, :IJulia) && Main.IJulia.inited
clear_ijulia() = (IJULIABEHAVIOR[] != IJuliaAppend) && running_ijulia_kernel()

function calc_check_iterations(p, t)
    if t == p.tlast
        # avoid a NaN which could happen because the print time compensation makes an assumption about how long printing
        # takes, therefore it's possible (but rare) for `t == p.tlast`
        return p.check_iterations
    end
    # Adjust the number of iterations that skips time check based on how accurate the last number was
    iterations_per_dt = (p.check_iterations / (t - p.tlast)) * p.dt
    return round(Int, clamp(iterations_per_dt, 1, p.check_iterations * 10))
end

# update progress display
function updateProgress!(p::Progress; showvalues = (),
                         truncate_lines = false, valuecolor = :blue,
                         offset::Integer = p.offset, keep = (offset == 0),
                         desc::Union{Nothing,AbstractString} = nothing,
                         ignore_predictor = false, color = p.color, max_steps = p.n)
    !p.enabled && return
    if p.counter == 2 # ignore the first loop given usually uncharacteristically slow
        p.tsecond = time()
    end
    if desc !== nothing && desc !== p.desc
        if p.barlen !== nothing
            p.barlen += length(p.desc) - length(desc) #adjust bar length to accommodate new description
        end
        p.desc = desc
    end
    p.offset = offset
    p.color = color
    p.n = max_steps
    if p.counter >= p.n
        if p.counter == p.n && p.printed
            t = time()
            barlen = p.barlen isa Nothing ? tty_width(p.desc, p.output, p.showspeed) : p.barlen
            percentage_complete = 100.0 * p.counter / p.n
            percentage_rounded = 100
            bar = barstring(barlen, percentage_complete, barglyphs=p.barglyphs)
            elapsed_time = t - p.tinit
            dur = durationstring(elapsed_time)
            spacer = endswith(p.desc, " ") ? "" : " "
            msg = @sprintf "%s%s%3u%%%s Time: %s" p.desc spacer percentage_rounded bar dur
            if p.showspeed
                sec_per_iter = elapsed_time / (p.counter - p.start)
                msg = @sprintf "%s (%s)" msg speedstring(sec_per_iter)
            end
            !CLEAR_IJULIA[] && print(p.output, "\n" ^ (p.offset + p.numprintedvalues))
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
            if keep
                println(p.output)
            else
                print(p.output, "\r\u1b[A" ^ (p.offset + p.numprintedvalues))
            end
            flush(p.output)
        end
        return nothing
    end
    if ignore_predictor || predicted_updates_per_dt_have_passed(p)
        t = time()
        if p.counter > 2
            p.check_iterations = calc_check_iterations(p, t)
        end
        if t > p.tlast+p.dt
            barlen = p.barlen isa Nothing ? tty_width(p.desc, p.output, p.showspeed) : p.barlen
            percentage_complete = 100.0 * p.counter / p.n
            percentage_rounded = min(99, round(Int, percentage_complete)) # don't round up to 100% if not finished (#300)
            bar = barstring(barlen, percentage_complete, barglyphs=p.barglyphs)
            elapsed_time = t - p.tinit
            est_total_time = elapsed_time * (p.n - p.start) / (p.counter - p.start)
            if 0 <= est_total_time <= typemax(Int)
                eta_sec = round(Int, est_total_time - elapsed_time )
                eta = durationstring(eta_sec)
            else
                eta = "N/A"
            end
            spacer = endswith(p.desc, " ") ? "" : " "
            msg = @sprintf "%s%s%3u%%%s  ETA: %s" p.desc spacer percentage_rounded bar eta
            if p.showspeed
                sec_per_iter = elapsed_time / (p.counter - p.start)
                msg = @sprintf "%s (%s)" msg speedstring(sec_per_iter)
            end
            !CLEAR_IJULIA[] && print(p.output, "\n" ^ (p.offset + p.numprintedvalues))
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
            !CLEAR_IJULIA[] && print(p.output, "\r\u1b[A" ^ (p.offset + p.numprintedvalues))
            flush(p.output)
            # Compensate for any overhead of printing. This can be
            # especially important if you're running over a slow network
            # connection.
            p.tlast = t + 2*(time()-t)
            p.printed = true
            p.prev_update_count = p.counter
        end
    end
    return nothing
end

function updateProgress!(p::ProgressThresh; showvalues = (),
                         truncate_lines = false, valuecolor = :blue,
                         offset::Integer = p.offset, keep = (offset == 0),
                         desc = p.desc, ignore_predictor = false,
                         color = p.color, thresh = p.thresh)
    !p.enabled && return
    p.offset = offset
    p.thresh = thresh
    p.color = color
    p.desc = desc
    if p.val <= p.thresh && !p.triggered
        p.triggered = true
        if p.printed
            t = time()
            elapsed_time = t - p.tinit
            p.triggered = true
            dur = durationstring(elapsed_time)
            msg = @sprintf "%s Time: %s (%d iterations)" p.desc dur p.counter
            if p.showspeed
                sec_per_iter = elapsed_time / p.counter
                msg = @sprintf "%s (%s)" msg speedstring(sec_per_iter)
            end
            print(p.output, "\n" ^ (p.offset + p.numprintedvalues))
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
            if keep
                println(p.output)
            else
                print(p.output, "\r\u1b[A" ^ (p.offset + p.numprintedvalues))
            end
            flush(p.output)
        end
        return
    end

    if ignore_predictor || predicted_updates_per_dt_have_passed(p)
        t = time()
        if p.counter > 2
            p.check_iterations = calc_check_iterations(p, t)
        end
        if t > p.tlast+p.dt && !p.triggered
            msg = @sprintf "%s (thresh = %g, value = %g)" p.desc p.thresh p.val
            if p.showspeed
                elapsed_time = t - p.tinit
                sec_per_iter = elapsed_time / p.counter
                msg = @sprintf "%s (%s)" msg speedstring(sec_per_iter)
            end
            print(p.output, "\n" ^ (p.offset + p.numprintedvalues))
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
            print(p.output, "\r\u1b[A" ^ (p.offset + p.numprintedvalues))
            flush(p.output)
            # Compensate for any overhead of printing. This can be
            # especially important if you're running over a slow network
            # connection.
            p.tlast = t + 2*(time()-t)
            p.printed = true
            p.prev_update_count = p.counter
        end
    end
end

const spinner_chars = ['◐','◓','◑','◒']
const spinner_done = '✓'

spinner_char(p::ProgressUnknown, spinner::AbstractChar) = spinner
spinner_char(p::ProgressUnknown, spinner::AbstractVector{<:AbstractChar}) =
    p.done ? spinner_done : spinner[p.spincounter % length(spinner) + firstindex(spinner)]
spinner_char(p::ProgressUnknown, spinner::AbstractString) =
    p.done ? spinner_done : spinner[nextind(spinner, 1, p.spincounter % length(spinner))]

function updateProgress!(p::ProgressUnknown; showvalues = (), truncate_lines = false,
                        valuecolor = :blue, desc = p.desc, ignore_predictor = false,
                        spinner::Union{AbstractChar,AbstractString,AbstractVector{<:AbstractChar}} = spinner_chars,
                        offset::Integer = p.offset, keep = (offset == 0),
                        color = p.color)
    !p.enabled && return
    p.offset = offset
    p.color = color
    p.desc = desc
    if p.done
        if p.printed
            t = time()
            elapsed_time = t - p.tinit
            dur = durationstring(elapsed_time)
            if p.spinner
                msg = @sprintf "%c %s    Time: %s" spinner_char(p, spinner) p.desc dur
                p.spincounter += 1
            else
                msg = @sprintf "%s %d    Time: %s" p.desc p.counter dur
            end
            if p.showspeed
                sec_per_iter = elapsed_time / p.counter
                msg = @sprintf "%s (%s)" msg speedstring(sec_per_iter)
            end
            print(p.output, "\n" ^ (p.offset + p.numprintedvalues))
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
            if keep
                println(p.output)
            else
                print(p.output, "\r\u1b[A" ^ (p.offset + p.numprintedvalues))
            end
            flush(p.output)
        end
        return
    end
    if ignore_predictor || predicted_updates_per_dt_have_passed(p)
        t = time()
        if p.counter > 2
            p.check_iterations = calc_check_iterations(p, t)
        end
        if t > p.tlast+p.dt
            dur = durationstring(t-p.tinit)
            if p.spinner
                msg = @sprintf "%c %s    Time: %s" spinner_char(p, spinner) p.desc dur
                p.spincounter += 1
            else
                msg = @sprintf "%s %d    Time: %s" p.desc p.counter dur
            end
            if p.showspeed
                elapsed_time = t - p.tinit
                sec_per_iter = elapsed_time / p.counter
                msg = @sprintf "%s (%s)" msg speedstring(sec_per_iter)
            end
            print(p.output, "\n" ^ (p.offset + p.numprintedvalues))
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
            print(p.output, "\r\u1b[A" ^ (p.offset + p.numprintedvalues))
            flush(p.output)
            # Compensate for any overhead of printing. This can be
            # especially important if you're running over a slow network
            # connection.
            p.tlast = t + 2*(time()-t)
            p.printed = true
            p.prev_update_count = p.counter
            return
        end
    end
end

predicted_updates_per_dt_have_passed(p::AbstractProgress) = p.counter - p.prev_update_count >= p.check_iterations

function is_threading(p::AbstractProgress)
    Threads.nthreads() == 1 && return false
    length(p.threads_used) > 1 && return true
    if !in(Threads.threadid(), p.threads_used)
        push!(p.threads_used, Threads.threadid())
    end
    return length(p.threads_used) > 1
end

function lock_if_threading(f::Function, p::AbstractProgress)
    if is_threading(p)
        lock(p.lock) do
            f()
        end
    else
        f()
    end
end

# update progress display
"""
    next!(p::Union{Progress, ProgressUnknown}; step::Int = 1, options...)

Report that `step` units of progress have been made. Depending on the time interval since
the last update, this may or may not result in a change to the display.

You may optionally change the `color` of the display. See also `update!`.
"""
function next!(p::Union{Progress, ProgressUnknown}; step::Int = 1, options...)
    lock_if_threading(p) do
        p.counter += step
        updateProgress!(p; ignore_predictor = step == 0, options...)
    end
end

"""
    update!(p::Union{Progress, ProgressUnknown}, [counter]; options...)

Set the progress counter to `counter`, relative to the `n` units of progress specified
when `prog` was initialized.  Depending on the time interval since the last update,
this may or may not result in a change to the display.

You may optionally change the color of the display. See also `next!`.
"""
function update!(p::Union{Progress, ProgressUnknown}, counter::Int=p.counter; options...)
    lock_if_threading(p) do
        counter_changed = p.counter != counter
        p.counter = counter
        updateProgress!(p; ignore_predictor = !counter_changed, options...)
    end
end

"""
    update!(p::ProgressThresh, [val]; increment::Bool=true, options...)

Set the progress counter to current value `val`.
"""
function update!(p::ProgressThresh, val=p.val; increment::Bool = true, options...)
    lock_if_threading(p) do
        p.val = val
        if increment
            p.counter += 1
        end
        updateProgress!(p; options...)
    end
end


"""
    cancel(p::AbstractProgress, [msg]; color=:red, options...)

Cancel the progress display before all tasks were completed. Optionally you can specify
the message printed and its color.

See also `finish!`.
"""
function cancel(p::AbstractProgress, msg::AbstractString = "Aborted before all tasks were completed";
                color = :red, showvalues = (), truncate_lines = false,
                valuecolor = :blue, offset = p.offset, keep = (offset == 0))
    lock_if_threading(p) do
        p.offset = offset
        if p.printed
            print(p.output, "\n" ^ (p.offset + p.numprintedvalues))
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
            if keep
                println(p.output)
            else
                print(p.output, "\r\u1b[A" ^ (p.offset + p.numprintedvalues))
            end
        end
    end
    return
end

"""
    finish!(p::Progress; options...)

Indicate that all tasks have been completed.

See also `cancel`.
"""
function finish!(p::Progress; options...)
    if p.counter < p.n
        update!(p, p.n; options...)
    end
end

function finish!(p::ProgressThresh; options...)
    update!(p, p.thresh; options...)
end

function finish!(p::ProgressUnknown; options...)
    lock_if_threading(p) do
        p.done = true
        updateProgress!(p; options...)
    end
end

# Internal method to print additional values below progress bar
function printvalues!(p::AbstractProgress, showvalues; color = :normal, truncate = false)
    length(showvalues) == 0 && return
    maxwidth = maximum(Int[length(string(name)) for (name, _) in showvalues])

    p.numprintedvalues = 0

    for (name, value) in showvalues
        msg = "\n  " * rpad(string(name) * ": ", maxwidth+2+1) * string(value)
        max_len = (displaysize(p.output)::Tuple{Int,Int})[2]
        # I don't understand why the minus 1 is necessary here, but empircally
        # it is needed.
        msg_lines = ceil(Int, (length(msg)-1) / max_len)
        if truncate && msg_lines >= 2
            # For multibyte characters, need to index with nextind.
            printover(p.output, msg[1:nextind(msg, 1, max_len-1)] * "…", color)
            p.numprintedvalues += 1
        else
            printover(p.output, msg, color)
            p.numprintedvalues += msg_lines
        end
    end
    p
end

# Internal method to print additional values below progress bar (lazy-showvalues version)
printvalues!(p::AbstractProgress, showvalues::Function; kwargs...) = printvalues!(p, showvalues(); kwargs...)

function move_cursor_up_while_clearing_lines(io, numlinesup)
    if numlinesup > 0 && CLEAR_IJULIA[]
        Main.IJulia.clear_output(true)
        if IJULIABEHAVIOR[] == IJuliaWarned
            @warn "ProgressMeter by default refresh meters with additional information in IJulia via `IJulia.clear_output`, which clears all outputs in the cell. \n - To prevent this behaviour, do `ProgressMeter.ijulia_behavior(:append)`. \n - To disable this warning message, do `ProgressMeter.ijulia_behavior(:clear)`."
        end
    else
        for _ in 1:numlinesup
            print(io, "\r\u1b[K\u1b[A")
        end
    end
end

function printover(io::IO, s::AbstractString, color::Symbol = :color_normal)
    print(io, "\r")
    printstyled(io, s; color=color)
    if isdefined(Main, :IJulia)
        Main.IJulia.stdio_bytes[] = 0 # issue #76: circumvent IJulia I/O throttling
    elseif isdefined(Main, :ESS) || isdefined(Main, :Atom)
    else
        print(io, "\u1b[K")     # clear the rest of the line
    end
end

function compute_front(barglyphs::BarGlyphs, frac_solid::AbstractFloat)
    barglyphs.front isa Char && return barglyphs.front
    idx = round(Int, frac_solid * (length(barglyphs.front) + 1))
    return idx > length(barglyphs.front) ? barglyphs.fill :
           idx == 0 ? barglyphs.empty :
           barglyphs.front[idx]
end

function barstring(barlen, percentage_complete; barglyphs)
    bar = ""
    if barlen > 0
        if percentage_complete == 100 # if we're done, don't use the "front" character
            bar = string(barglyphs.leftend, repeat(string(barglyphs.fill), barlen), barglyphs.rightend)
        else
            n_bars = barlen * percentage_complete / 100
            nsolid = trunc(Int, n_bars)
            frac_solid = n_bars - nsolid
            nempty = barlen - nsolid - 1
            bar = string(barglyphs.leftend,
                         repeat(string(barglyphs.fill), max(0,nsolid)),
                         compute_front(barglyphs, frac_solid),
                         repeat(string(barglyphs.empty), max(0, nempty)),
                         barglyphs.rightend)
        end
    end
    bar
end

function durationstring(nsec)
    days = div(nsec, 60*60*24)
    r = nsec - 60*60*24*days
    hours = div(r,60*60)
    r = r - 60*60*hours
    minutes = div(r, 60)
    seconds = floor(r - 60*minutes)

    hhmmss = @sprintf "%u:%02u:%02u" hours minutes seconds
    if days > 9
        return @sprintf "%.2f days" nsec/(60*60*24)
    elseif days > 0
        return @sprintf "%u days, %s" days hhmmss
    end
    hhmmss
end

function speedstring(sec_per_iter)
    if sec_per_iter == Inf
        return "  N/A  s/it"
    end
    ns_per_iter = 1_000_000_000 * sec_per_iter
    for (divideby, unit) in (
        (1, "ns"),
        (1_000, "μs"),
        (1_000_000, "ms"),
        (1_000_000_000, "s"),
        (60 * 1_000_000_000, "m"),
        (60 * 60 * 1_000_000_000, "hr"),
        (24 * 60 * 60 * 1_000_000_000, "d")
    )
        if round(ns_per_iter / divideby) < 100
            return @sprintf "%5.2f %2s/it" (ns_per_iter / divideby) unit
        end
    end
    return " >100  d/it"
end

function showprogress_process_args(progressargs)
    return map(progressargs) do arg
        if Meta.isexpr(arg, :(=))
            arg = Expr(:kw, arg.args...)
        end
        return esc(arg)
    end
end

function showprogress_process_expr(node, metersym)
    if !isa(node, Expr)
        node
    elseif node.head === :break || node.head === :return
        # special handling for break and return statements
        quote
            ($finish!)($metersym)
            $node
        end
    elseif node.head === :for || node.head === :while
        # do not process inner loops
        #
        # FIXME: do not process break and return statements in inner functions
        # either
        node
    else
        # process each subexpression recursively
        Expr(node.head, [showprogress_process_expr(a, metersym) for a in node.args]...)
    end
end

struct ProgressWrapper{T}
    obj::T
    meter::Progress
end

Base.IteratorSize(wrap::ProgressWrapper) = Base.IteratorSize(wrap.obj)
Base.axes(wrap::ProgressWrapper, dim...) = Base.axes(wrap.obj, dim...)
Base.size(wrap::ProgressWrapper, dim...) = Base.size(wrap.obj, dim...)
Base.length(wrap::ProgressWrapper) = Base.length(wrap.obj)

Base.IteratorEltype(wrap::ProgressWrapper) = Base.IteratorEltype(wrap.obj)
Base.eltype(wrap::ProgressWrapper) = Base.eltype(wrap.obj)

function Base.iterate(wrap::ProgressWrapper, state...)
    ir = iterate(wrap.obj, state...)

    if ir === nothing
        finish!(wrap.meter)
    elseif !isempty(state)
        next!(wrap.meter)
    end

    return ir
end

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

    if na == 1
        # would be nice to do this with @sync @distributed but @sync is broken
        # https://github.com/JuliaLang/julia/issues/28979
        compute = quote
            waiting = @distributed for $(esc(var)) = $(esc(r))
                $(esc(body))
                put!(ch, true)
            end
            wait(waiting)
            nothing
        end
    else
        compute = quote
            @distributed $(esc(reducer)) for $(esc(var)) = $(esc(r))
                x = $(esc(body))
                put!(ch, true)
                x
            end
        end
    end

    quote
        let n = length($(esc(r)))
            p = Progress(n, $(showprogress_process_args(progressargs)...))
            ch = RemoteChannel(() -> Channel{Bool}(n))

            @async while take!(ch) next!(p) end
            results = $compute
            put!(ch, false)
            finish!(p)
            results
        end
    end
end

function showprogressthreads(args...)
    progressargs = args[1:end-1]
    expr = args[end]
    loop = expr.args[end]
    iters = loop.args[1].args[end]

    p = gensym()
    push!(loop.args[end].args, :(next!($p)))

    quote
        $(esc(p)) = Progress(
            length($(esc(iters)));
            $(showprogress_process_args(progressargs)...),
        )
        append!($(esc(p)).threads_used, 1:Threads.nthreads())
        $(esc(expr))
        finish!($(esc(p)))
    end
end

"""
```
@showprogress [desc="Computing..."] for i = 1:50
    # computation goes here
end

@showprogress [desc="Computing..."] pmap(x->x^2, 1:50)
```
displays progress in performing a computation.  You may optionally
supply a custom message to be printed that specifies the computation
being performed or other options.

`@showprogress` works for loops, comprehensions, and `map`-like
functions. These `map`-like functions rely on `ncalls` being defined
and can be checked with `methods(ProgressMeter.ncalls)`. New ones can
be added by defining `ProgressMeter.ncalls(::typeof(mapfun), args...) = ...`.

`@showprogress` is thread-safe and will work with `@distributed` loops
as well as threaded or distributed functions like `pmap` and `asyncmap`.

"""
macro showprogress(args...)
    showprogress(args...)
end

function showprogress(args...)
    if length(args) < 1
        throw(ArgumentError("@showprogress requires at least one argument."))
    end
    progressargs = args[1:end-1]
    expr = args[end]

    if !isa(expr, Expr)
        throw(ArgumentError("Final argument to @showprogress must be a for loop, comprehension, or a map-like function; got $expr"))
    end

    if expr.head == :call && expr.args[1] == :|>
        # e.g. map(x->x^2) |> sum
        expr.args[2] = showprogress(progressargs..., expr.args[2])
        return expr

    elseif expr.head in (:for, :comprehension, :typed_comprehension)
        return showprogress_loop(expr, progressargs)

    elseif expr.head == :call
        return showprogress_map(expr, progressargs)

    elseif expr.head == :do && expr.args[1].head == :call
        return showprogress_map(expr, progressargs)

    elseif expr.head == :macrocall
        macroname = expr.args[1]

        if macroname in (Symbol("@distributed"), :(Distributed.@distributed).args[1])
            # can be changed to `:(Distributed.var"@distributed")` if support for pre-1.3 is dropped
            return showprogressdistributed(args...)

        elseif macroname in (Symbol("@threads"), :(Threads.@threads).args[1])
            return showprogressthreads(args...)
        end
    end

    throw(ArgumentError("Final argument to @showprogress must be a for loop, comprehension, or a map-like function; got $expr"))
end

function showprogress_map(expr, progressargs)
    metersym = gensym("meter")

    # isolate call to map
    if expr.head == :do
        call = expr.args[1]
    else
        call = expr
    end

    # get args to map to determine progress length
    mapargs = collect(Any, filter(call.args[2:end]) do a
        return isa(a, Symbol) || isa(a, Number) || !(a.head in (:kw, :parameters))
    end)
    if expr.head == :do
        insert!(mapargs, 1, identity) # to make args for ncalls line up
    end

    # change call to progress_map
    mapfun = call.args[1]
    call.args[1] = :progress_map

    # escape args as appropriate
    for i in 2:length(call.args)
        call.args[i] = esc(call.args[i])
    end
    if expr.head == :do
        expr.args[2] = esc(expr.args[2])
    end

    # create appropriate Progress expression
    lenex = :(ncalls($(esc(mapfun)), $(esc.(mapargs)...)))
    progex = :(Progress($lenex, $(showprogress_process_args(progressargs)...)))

    # insert progress and mapfun kwargs
    push!(call.args, Expr(:kw, :progress, progex))
    push!(call.args, Expr(:kw, :mapfun, esc(mapfun)))

    return expr
end

function showprogress_loop(expr, progressargs)
    metersym = gensym("meter")
    orig = expr = copy(expr)

    if expr.head == :for
        outerassignidx = 1
        loopbodyidx = lastindex(expr.args)
    elseif expr.head == :comprehension
        outerassignidx = lastindex(expr.args)
        loopbodyidx = 1
    elseif expr.head == :typed_comprehension
        outerassignidx = lastindex(expr.args)
        loopbodyidx = 2
    end
    # As of julia 0.5, a comprehension's "loop" is actually one level deeper in the syntax tree.
    if expr.head !== :for
        @assert length(expr.args) == loopbodyidx
        expr = expr.args[outerassignidx] = copy(expr.args[outerassignidx])
        if expr.head == :flatten
            # e.g. [x for x in 1:10 for y in 1:x]
            expr = expr.args[1] = copy(expr.args[1])
        end
        @assert expr.head === :generator
        outerassignidx = lastindex(expr.args)
        loopbodyidx = 1
    end

    # Transform the first loop assignment
    loopassign = expr.args[outerassignidx] = copy(expr.args[outerassignidx])

    if loopassign.head === :filter
        # e.g. [x for x=1:10, y=1:10 if x>y]
        # y will be wrapped in ProgressWrapper
        for i in 1:length(loopassign.args)-1
            loopassign.args[i] = esc(loopassign.args[i])
        end
        loopassign = loopassign.args[end] = copy(loopassign.args[end])
    end

    if loopassign.head === :block
        # e.g. for x=1:10, y=1:x end
        # x will be wrapped in ProgressWrapper
        for i in 2:length(loopassign.args)
            loopassign.args[i] = esc(loopassign.args[i])
        end
        loopassign = loopassign.args[1] = copy(loopassign.args[1])
    end

    @assert loopassign.head === :(=)
    @assert length(loopassign.args) == 2
    obj = loopassign.args[2]
    loopassign.args[1] = esc(loopassign.args[1])
    loopassign.args[2] = :(ProgressWrapper(iterable, $(esc(metersym))))

    # Transform the loop body break and return statements
    if expr.head === :for
        expr.args[loopbodyidx] = showprogress_process_expr(expr.args[loopbodyidx], metersym)
    end

    # Escape all args except the loop assignment, which was already appropriately escaped.
    for i in 1:length(expr.args)
        if i != outerassignidx
            expr.args[i] = esc(expr.args[i])
        end
    end
    if orig !== expr
        # We have additional escaping to do; this will occur for comprehensions with julia 0.5 or later.
        for i in 1:length(orig.args)-1
            orig.args[i] = esc(orig.args[i])
        end
    end

    setup = quote
        iterable = $(esc(obj))
        $(esc(metersym)) = Progress(length(iterable), $(showprogress_process_args(progressargs)...))
    end

    if expr.head === :for
        return quote
            $setup
            $expr
        end
    else
        # We're dealing with a comprehension
        return quote
            begin
                $setup
                rv = $orig
                finish!($(esc(metersym)))
                rv
            end
        end
    end
end

"""
    progress_map(f, c...; mapfun=map, progress=Progress(...), kwargs...)

Run a `map`-like function while displaying progress.

`mapfun` can be any function, but it is only tested with `map`, `reduce` and `pmap`.
`ProgressMeter.ncalls(::typeof(mapfun), ::Function, args...)` must be defined to
specify the number of calls to `f`.
"""
function progress_map(args...; mapfun=map,
                               progress=Progress(ncalls(mapfun, args...)),
                               channel_bufflen=min(1000, ncalls(mapfun, args...)),
                               kwargs...)
    isempty(args) && return mapfun(; kwargs...)
    f = first(args)
    other_args = args[2:end]
    channel = RemoteChannel(()->Channel{Bool}(channel_bufflen), 1)
    local vals
    @sync begin
        # display task
        @async while take!(channel)
            next!(progress)
        end

        # map task
        @sync begin
            vals = mapfun(other_args...; kwargs...) do x...
                val = f(x...)
                put!(channel, true)
                yield()
                return val
            end
            put!(channel, false)
        end
    end
    return vals
end

"""
    progress_pmap(f, [::AbstractWorkerPool], c...; progress=Progress(...), kwargs...)

Run `pmap` while displaying progress.
"""
progress_pmap(args...; kwargs...) = progress_map(args...; mapfun=pmap, kwargs...)

"""
    ProgressMeter.ncalls(::typeof(mapfun), ::Function, args...)

Infer the number of calls to the mapped function (often the length of the returned array)
to define the length of the `Progress` in `@showprogress` and `progress_map`.
Internally uses one of `ncalls_map`, `ncalls_broadcast(!)` or `ncalls_reduce` depending
on the type of `mapfun`.

Support for additional functions can be added by defining
`ProgressMeter.ncalls(::typeof(mapfun), ::Function, args...)`.
"""
ncalls(::typeof(map), ::Function, args...) = ncalls_map(args...)
ncalls(::typeof(map!), ::Function, args...) = ncalls_map(args...)
ncalls(::typeof(foreach), ::Function, args...) = ncalls_map(args...)
ncalls(::typeof(asyncmap), ::Function, args...) = ncalls_map(args...)

ncalls(::typeof(pmap), ::Function, args...) = ncalls_map(args...)
ncalls(::typeof(pmap), ::Function, ::AbstractWorkerPool, args...) = ncalls_map(args...)

ncalls(::typeof(mapfoldl), ::Function, ::Function, args...) = ncalls_map(args...)
ncalls(::typeof(mapfoldr), ::Function, ::Function, args...) = ncalls_map(args...)
ncalls(::typeof(mapreduce), ::Function, ::Function, args...) = ncalls_map(args...)

ncalls(::typeof(broadcast), ::Function, args...) = ncalls_broadcast(args...)
ncalls(::typeof(broadcast!), ::Function, args...) = ncalls_broadcast!(args...)

ncalls(::typeof(foldl), ::Function, arg) = ncalls_reduce(arg)
ncalls(::typeof(foldr), ::Function, arg) = ncalls_reduce(arg)
ncalls(::typeof(reduce), ::Function, arg) = ncalls_reduce(arg)

ncalls_reduce(arg) = length(arg) - 1

function ncalls_broadcast(args...)
    length(args) < 1 && return 1
    return prod(length, Broadcast.combine_axes(args...))
end

function ncalls_broadcast!(args...)
    length(args) < 1 && return 1
    return length(args[1])
end

function ncalls_map(args...)
    length(args) < 1 && return 1
    return minimum(length, args)
end

include("deprecated.jl")

end # module
