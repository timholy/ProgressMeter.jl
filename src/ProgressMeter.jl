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

"""
`prog = Progress(n; dt=0.1, desc="Progress: ", color=:green,
output=stderr, barlen=tty_width(desc), start=0)` creates a progress meter for a
task with `n` iterations or stages starting from `start`. Output will be
generated at intervals at least `dt` seconds apart, and perhaps longer if each
iteration takes longer than `dt`. `desc` is a description of
the current task. Optionally you can disable the progress bar by setting
`enable=false`. You can also append a per-iteration average duration like
"(12.34 ms/it)" to the description by setting `showspeed=true`.
"""
mutable struct Progress <: AbstractProgress
    n::Int
    reentrantlocker::Threads.ReentrantLock
    dt::Float64
    counter::Int
    tinit::Float64
    tsecond::Float64           # ignore the first loop given usually uncharacteristically slow
    tlast::Float64
    printed::Bool              # true if we have issued at least one status update
    desc::String               # prefix to the percentage, e.g.  "Computing..."
    barlen::Union{Int,Nothing} # progress bar size (default is available terminal width)
    barglyphs::BarGlyphs       # the characters to be used in the bar
    color::Symbol              # default to green
    output::IO                 # output stream into which the progress is written
    offset::Int                # position offset of progress bar (default is 0)
    numprintedvalues::Int      # num values printed below progress in last iteration
    start::Int                 # which iteration number to start from
    enabled::Bool              # is the output enabled
    showspeed::Bool            # should the output include average time per iteration
    check_iterations::Int
    prev_update_count::Int
    threads_used::Vector{Int}

    function Progress(n::Integer;
                      dt::Real=0.1,
                      desc::AbstractString="Progress: ",
                      color::Symbol=:green,
                      output::IO=stderr,
                      barlen=nothing,
                      barglyphs::BarGlyphs=BarGlyphs('|','█', Sys.iswindows() ? '█' : ['▏','▎','▍','▌','▋','▊','▉'],' ','|',),
                      offset::Integer=0,
                      start::Integer=0,
                      enabled::Bool = true,
                      showspeed::Bool = false,
                     )
        RUNNING_IJULIA_KERNEL[] = running_ijulia_kernel()
        CLEAR_IJULIA[] = clear_ijulia()
        reentrantlocker = Threads.ReentrantLock()
        counter = start
        tinit = tsecond = tlast = time()
        printed = false
        new(n, reentrantlocker, dt, counter, tinit, tsecond, tlast, printed, desc, barlen, barglyphs, color, output, offset, 0, start, enabled, showspeed, 1, 1, Int[])
    end
end

Progress(n::Integer, dt::Real, desc::AbstractString="Progress: ",
         barlen=nothing, color::Symbol=:green, output::IO=stderr;
         offset::Integer=0) =
    Progress(n, dt=dt, desc=desc, barlen=barlen, color=color, output=output, offset=offset)

Progress(n::Integer, desc::AbstractString, offset::Integer=0) = Progress(n, desc=desc, offset=offset)


"""
`prog = ProgressThresh(thresh; dt=0.1, desc="Progress: ",
color=:green, output=stderr)` creates a progress meter for a task
which will terminate once a value less than or equal to `thresh` is
reached. Output will be generated at intervals at least `dt` seconds
apart, and perhaps longer if each iteration takes longer than
`dt`. `desc` is a description of the current task. Optionally you can disable
the progress meter by setting `enable=false`. You can also append a
per-iteration average duration like "(12.34 ms/it)" to the description by
setting `showspeed=true`.
"""
mutable struct ProgressThresh{T<:Real} <: AbstractProgress
    thresh::T
    reentrantlocker::Threads.ReentrantLock
    dt::Float64
    val::T
    counter::Int
    triggered::Bool
    tinit::Float64
    tlast::Float64
    printed::Bool           # true if we have issued at least one status update
    desc::String            # prefix to the percentage, e.g.  "Computing..."
    color::Symbol           # default to green
    output::IO              # output stream into which the progress is written
    numprintedvalues::Int   # num values printed below progress in last iteration
    offset::Int             # position offset of progress bar (default is 0)
    enabled::Bool           # is the output enabled
    showspeed::Bool         # should the output include average time per iteration
    check_iterations::Int
    prev_update_count::Int
    threads_used::Vector{Int}

    function ProgressThresh{T}(thresh;
                               dt::Real=0.1,
                               desc::AbstractString="Progress: ",
                               color::Symbol=:green,
                               output::IO=stderr,
                               offset::Integer=0,
                               enabled = true,
                               showspeed::Bool = false) where T
        RUNNING_IJULIA_KERNEL[] = running_ijulia_kernel()
        CLEAR_IJULIA[] = clear_ijulia()
        reentrantlocker = Threads.ReentrantLock()
        tinit = tlast = time()
        printed = false
        new{T}(thresh, reentrantlocker, dt, typemax(T), 0, false, tinit, tlast, printed, desc, color, output, 0, offset, enabled, showspeed, 1, 1, Int[])
    end
end
ProgressThresh(thresh::Real; kwargs...) = ProgressThresh{typeof(thresh)}(thresh; kwargs...)

# Legacy constructor calls
ProgressThresh(thresh::Real, dt::Real, desc::AbstractString="Progress: ",
         color::Symbol=:green, output::IO=stderr;
         offset::Integer=0) =
    ProgressThresh(thresh; dt=dt, desc=desc, color=color, output=output, offset=offset)

ProgressThresh(thresh::Real, desc::AbstractString, offset::Integer=0) = ProgressThresh(thresh; desc=desc, offset=offset)

"""
`prog = ProgressUnknown(; dt=0.1, desc="Progress: ",
color=:green, output=stderr)` creates a progress meter for a task
which has a non-deterministic termination criterion.
Output will be generated at intervals at least `dt` seconds
apart, and perhaps longer if each iteration takes longer than
`dt`. `desc` is a description of the current task. Optionally you can disable
the progress meter by setting `enable=false`. You can also append a
per-iteration average duration like "(12.34 ms/it)" to the description by
setting `showspeed=true`.  Instead of displaying a counter, it
can optionally display a spinning ball by passing `spinner=true`.
"""
mutable struct ProgressUnknown <: AbstractProgress
    done::Bool
    reentrantlocker::Threads.ReentrantLock
    dt::Float64
    counter::Int
    spincounter::Int
    triggered::Bool
    tinit::Float64
    tlast::Float64
    printed::Bool           # true if we have issued at least one status update
    desc::String            # prefix to the percentage, e.g.  "Computing..."
    color::Symbol           # default to green
    spinner::Bool           # show a spinner
    output::IO              # output stream into which the progress is written
    numprintedvalues::Int   # num values printed below progress in last iteration
    enabled::Bool           # is the output enabled
    showspeed::Bool         # should the output include average time per iteration
    check_iterations::Int
    prev_update_count::Int
    threads_used::Vector{Int}
end

function ProgressUnknown(;dt::Real=0.1, desc::AbstractString="Progress: ", color::Symbol=:green, spinner::Bool=false, output::IO=stderr, enabled::Bool = true, showspeed::Bool = false)
    RUNNING_IJULIA_KERNEL[] = running_ijulia_kernel()
    CLEAR_IJULIA[] = clear_ijulia()
    reentrantlocker = Threads.ReentrantLock()
    tinit = tlast = time()
    printed = false
    ProgressUnknown(false, reentrantlocker, dt, 0, 0, false, tinit, tlast, printed, desc, color, spinner, output, 0, enabled, showspeed, 1, 1, Int[])
end

ProgressUnknown(dt::Real, desc::AbstractString="Progress: ",
         color::Symbol=:green, output::IO=stderr; kwargs...) =
    ProgressUnknown(dt=dt, desc=desc, color=color, output=output; kwargs...)

ProgressUnknown(desc::AbstractString; kwargs...) = ProgressUnknown(desc=desc; kwargs...)

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
const RUNNING_IJULIA_KERNEL = Ref{Bool}(false)
const CLEAR_IJULIA = Ref{Bool}(false)
running_ijulia_kernel() = isdefined(Main, :IJulia) && Main.IJulia.inited
clear_ijulia() = (IJULIABEHAVIOR[] != IJuliaAppend) && running_ijulia_kernel()

function calc_check_iterations(p, t)
    # Adjust the number of iterations that skips time check based on how accurate the last number was
    iterations_per_dt = (p.check_iterations / (t - p.tlast)) * p.dt
    return round(Int, clamp(iterations_per_dt, 1, p.check_iterations * 10))
end

# update progress display
function updateProgress!(p::Progress; showvalues = (), truncate_lines = false, valuecolor = :blue,
                        offset::Integer = p.offset, keep = (offset == 0), desc::Union{Nothing,AbstractString} = nothing,
                        ignore_predictor = false)
    (!RUNNING_IJULIA_KERNEL[] & !p.enabled) && return
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
    if p.counter >= p.n
        if p.counter == p.n && p.printed
            t = time()
            barlen = p.barlen isa Nothing ? tty_width(p.desc, p.output, p.showspeed) : p.barlen
            percentage_complete = 100.0 * p.counter / p.n
            bar = barstring(barlen, percentage_complete, barglyphs=p.barglyphs)
            elapsed_time = t - p.tinit
            dur = durationstring(elapsed_time)
            msg = @sprintf "%s%3u%%%s Time: %s" p.desc round(Int, percentage_complete) bar dur
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
            bar = barstring(barlen, percentage_complete, barglyphs=p.barglyphs)
            elapsed_time = t - p.tinit
            est_total_time = elapsed_time * (p.n - p.start) / (p.counter - p.start)
            if 0 <= est_total_time <= typemax(Int)
                eta_sec = round(Int, est_total_time - elapsed_time )
                eta = durationstring(eta_sec)
            else
                eta = "N/A"
            end
            msg = @sprintf "%s%3u%%%s  ETA: %s" p.desc round(Int, percentage_complete) bar eta
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

function updateProgress!(p::ProgressThresh; showvalues = (), truncate_lines = false, valuecolor = :blue,
                        offset::Integer = p.offset, keep = (offset == 0), desc = p.desc, ignore_predictor = false)
    (!RUNNING_IJULIA_KERNEL[] & !p.enabled) && return
    p.offset = offset
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

function updateProgress!(p::ProgressUnknown; showvalues = (), truncate_lines = false, valuecolor = :blue, desc = p.desc,
                        ignore_predictor = false, spinner::Union{AbstractChar,AbstractString,AbstractVector{<:AbstractChar}} = spinner_chars)
    (!RUNNING_IJULIA_KERNEL[] & !p.enabled) && return
    p.desc = desc
    if p.done
        if p.printed
            t = time()
            elapsed_time = t - p.tinit
            dur = durationstring(elapsed_time)
            if p.spinner
                msg = @sprintf "%s %c \t Time: %s" p.desc spinner_char(p, spinner) dur
                p.spincounter += 1
            else
                msg = @sprintf "%s %d \t Time: %s" p.desc p.counter dur
            end
            if p.showspeed
                sec_per_iter = elapsed_time / p.counter
                msg = @sprintf "%s (%s)" msg speedstring(sec_per_iter)
            end
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
            println(p.output)
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
                msg = @sprintf "%s %c \t Time: %s" p.desc spinner_char(p, spinner) dur
                p.spincounter += 1
            else
                msg = @sprintf "%s %d \t Time: %s" p.desc p.counter dur
            end
            if p.showspeed
                elapsed_time = t - p.tinit
                sec_per_iter = elapsed_time / p.counter
                msg = @sprintf "%s (%s)" msg speedstring(sec_per_iter)
            end
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
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
        lock(p.reentrantlocker) do
            f()
        end
    else
        f()
    end
end

# update progress display
"""
`next!(prog, [color], step = 1)` reports that `step` units of progress have been
made. Depending on the time interval since the last update, this may
or may not result in a change to the display.

You may optionally change the color of the display. See also `update!`.
"""
function next!(p::Union{Progress, ProgressUnknown}; step::Int = 1, options...)
    lock_if_threading(p) do
        p.counter += step
        updateProgress!(p; ignore_predictor = step == 0, options...)
    end
end

function next!(p::Union{Progress, ProgressUnknown}, color::Symbol; step::Int = 1, options...)
    lock_if_threading(p) do
        p.color = color
        p.counter += step
        updateProgress!(p; ignore_predictor = step == 0, options...)
    end
end

"""
`update!(prog, counter, [color])` sets the progress counter to
`counter`, relative to the `n` units of progress specified when `prog`
was initialized.  Depending on the time interval since the last
update, this may or may not result in a change to the display.

If `prog` is a `ProgressThresh`, `update!(prog, val, [color])` specifies
the current value.

You may optionally change the color of the display. See also `next!`.
"""
function update!(p::Union{Progress, ProgressUnknown}, counter::Int=p.counter, color::Symbol=p.color; options...)
    lock_if_threading(p) do
        counter_changed = p.counter != counter
        p.counter = counter
        p.color = color
        updateProgress!(p; ignore_predictor = !counter_changed, options...)
    end
end

function update!(p::ProgressThresh, val=p.val, color::Symbol=p.color; increment::Bool = true, options...)
    lock_if_threading(p) do
        p.val = val
        if increment
            p.counter += 1
        end
        p.color = color
        updateProgress!(p; options...)
    end
end


"""
`cancel(prog, [msg], [color=:red])` cancels the progress display
before all tasks were completed. Optionally you can specify the
message printed and its color.

See also `finish!`.
"""
function cancel(p::AbstractProgress, msg::AbstractString = "Aborted before all tasks were completed", color = :red; showvalues = (), truncate_lines = false, valuecolor = :blue, offset = p.offset, keep = (offset == 0))
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
`finish!(prog)` indicates that all tasks have been completed.

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
    if barlen>0
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
    if days>9
        return @sprintf "%.2f days" nsec/(60*60*24)
    elseif days>0
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

Base.length(wrap::ProgressWrapper) = Base.length(wrap.obj)

function Base.iterate(wrap::ProgressWrapper, state...)
    ir = iterate(wrap.obj, state...)

    if ir === nothing
        finish!(wrap.meter)
    elseif !isempty(state)
        next!(wrap.meter)
    end

    ir
end

"""
Equivalent of @showprogress for a distributed for loop.
```
result = @showprogress dt "Computing..." @distributed (+) for i = 1:50
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

    if expr.head != :macrocall || expr.args[1] != Symbol("@distributed")
        throw(ArgumentError("malformed @showprogress @distributed expression"))
    end

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

    setup = quote
        n = length($(esc(r)))
        p = Progress(n, $([esc(arg) for arg in progressargs]...))
        ch = RemoteChannel(() -> Channel{Bool}(n))
    end

    if na == 1
        # would be nice to do this with @sync @distributed but @sync is broken
        # https://github.com/JuliaLang/julia/issues/28979
        compute = quote
            display = @async let i = 0
                while i < n
                    take!(ch)
                    next!(p)
                    i += 1
                end
            end
            @distributed for $(esc(var)) = $(esc(r))
                $(esc(body))
                put!(ch, true)
            end
            nothing
        end
    else
        compute = quote
            display = @async while take!(ch) next!(p) end
            results = @distributed $(esc(reducer)) for $(esc(var)) = $(esc(r))
                x = $(esc(body))
                put!(ch, true)
                x
            end
            put!(ch, false)
            results
        end
    end

    quote
        $setup
        results = $compute
        wait(display)
        results
    end
end

"""
```
@showprogress dt "Computing..." for i = 1:50
    # computation goes here
end

@showprogress dt "Computing..." pmap(x->x^2, 1:50)
```
displays progress in performing a computation. `dt` is the minimum
interval between updates to the user. You may optionally supply a
custom message to be printed that specifies the computation being
performed.

`@showprogress` works for loops, comprehensions, map, reduce, and pmap.
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
    if expr.head == :macrocall && expr.args[1] == Symbol("@distributed")
        return showprogressdistributed(args...)
    end
    orig = expr = copy(expr)
    if expr.args[1] == :|> # e.g. map(x->x^2) |> sum
        expr.args[2] = showprogress(progressargs..., expr.args[2])
        return expr
    end
    metersym = gensym("meter")
    mapfuns = (:map, :asyncmap, :reduce, :pmap)
    kind = :invalid # :invalid, :loop, or :map

    if isa(expr, Expr)
        if expr.head == :for
            outerassignidx = 1
            loopbodyidx = lastindex(expr.args)
            kind = :loop
        elseif expr.head == :comprehension
            outerassignidx = lastindex(expr.args)
            loopbodyidx = 1
            kind = :loop
        elseif expr.head == :typed_comprehension
            outerassignidx = lastindex(expr.args)
            loopbodyidx = 2
            kind = :loop
        elseif expr.head == :call && expr.args[1] in mapfuns
            kind = :map
        elseif expr.head == :do
            call = expr.args[1]
            if call.head == :call && call.args[1] in mapfuns
                kind = :map
            end
        end
    end

    if kind == :invalid
        throw(ArgumentError("Final argument to @showprogress must be a for loop, comprehension, map, reduce, or pmap; got $expr"))
    elseif kind == :loop
        # As of julia 0.5, a comprehension's "loop" is actually one level deeper in the syntax tree.
        if expr.head !== :for
            @assert length(expr.args) == loopbodyidx
            expr = expr.args[outerassignidx] = copy(expr.args[outerassignidx])
            @assert expr.head === :generator
            outerassignidx = lastindex(expr.args)
            loopbodyidx = 1
        end

        # Transform the first loop assignment
        loopassign = expr.args[outerassignidx] = copy(expr.args[outerassignidx])
        if loopassign.head === :block # this will happen in a for loop with multiple iteration variables
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
            $(esc(metersym)) = Progress(length(iterable), $([esc(arg) for arg in progressargs]...))
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
                    next!($(esc(metersym)))
                    rv
                end
            end
        end
    else # kind == :map

        # isolate call to map
        if expr.head == :do
            call = expr.args[1]
        else
            call = expr
        end

        # get args to map to determine progress length
        mapargs = collect(Any, filter(call.args[2:end]) do a
            return isa(a, Symbol) || !(a.head in (:kw, :parameters))
        end)
        if expr.head == :do
            insert!(mapargs, 1, :nothing) # to make args for ncalls line up
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
        lenex = :(ncalls($(esc(mapfun)), ($([esc(a) for a in mapargs]...),)))
        progex = :(Progress($lenex, $([esc(a) for a in progressargs]...)))

        # insert progress and mapfun kwargs
        push!(call.args, Expr(:kw, :progress, progex))
        push!(call.args, Expr(:kw, :mapfun, esc(mapfun)))

        return expr
    end
end

"""
    progress_map(f, c...; mapfun=map, progress=Progress(...), kwargs...)

Run a `map`-like function while displaying progress.

`mapfun` can be any function, but it is only tested with `map`, `reduce` and `pmap`.
"""
function progress_map(args...; mapfun=map,
                               progress=Progress(ncalls(mapfun, args)),
                               channel_bufflen=min(1000, ncalls(mapfun, args)),
                               kwargs...)
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
Infer the number of calls to the mapped function (i.e. the length of the returned array) given the input arguments to map, reduce or pmap.
"""
function ncalls(mapfun::Function, map_args)
    if mapfun == pmap && length(map_args) >= 2 && isa(map_args[2], AbstractWorkerPool)
        relevant = map_args[3:end]
    else
        relevant = map_args[2:end]
    end
    if isempty(relevant)
        error("Unable to determine number of calls in $mapfun. Too few arguments?")
    else
        return maximum(length(arg) for arg in relevant)
    end
end

end
