module ProgressMeter

using Printf: @sprintf

export Progress, ProgressThresh, ProgressUnknown, BarGlyphs, next!, update!, cancel, finish!, @showprogress, progress_map, progress_pmap, ijulia_behavior
@static if VERSION >= v"1.11.0-DEV.469"
    eval(Meta.parse("public AbstractProgressElement, ProgressStatus, print_element, Description, Percentage, Bar, ETA, Speed, ElapsedTime, Counter, Threshold, Spinner"))
end

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

# forward common core properties to main types
function Base.setproperty!(p::T, name::Symbol, value) where T<:AbstractProgress
    if hasfield(T, name)
        ty = fieldtype(T, name)
        value = value isa ty ? value : convert(ty, value)
        setfield!(p, name, value)
    else
        setproperty!(getfield(p, :core), name, value)
    end
end
function Base.getproperty(p::T, name::Symbol) where T<:AbstractProgress
    if hasfield(T, name)
        getfield(p, name)
    else
        getproperty(getfield(p, :core), name)
    end
end

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
    elements::Union{Nothing,Tuple} = nothing    # elements of the status line, `nothing` for the default layout
    # internals
    check_iterations::Int       = 1             # number of iterations to check time for
    counter::Int                = 0             # current iteration
    lock::Threads.ReentrantLock = Threads.ReentrantLock()   # lock used when threading detected
    numprintedvalues::Int       = 0             # num values printed below progress in last iteration
    prev_update_count::Int      = 1             # counter at last update
    printed::Bool               = false         # true if we have issued at least one status update
    safe_lock::Int              = 2*(Threads.nthreads()>1) # 0: no lock, 1: lock, 2: detect
    thread_id::Int              = Threads.threadid() # id of the thread that created the progressmeter
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
To customize the status line pass a tuple of `elements`, e.g.
`elements=(ProgressMeter.Description(), ProgressMeter.Bar(), " ", MyElement())`,
see [`ProgressMeter.AbstractProgressElement`](@ref).
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

"""
`prog = ProgressThresh(thresh; dt=0.1, desc="Progress: ",
color=:green, output=stderr)` creates a progress meter for a task
which will terminate once a value less than or equal to `thresh` is
reached. Output will be generated at intervals at least `dt` seconds
apart, and perhaps longer if each iteration takes longer than
`dt`. `desc` is a description of the current task. Optionally you can disable
the progress meter by setting `enabled=false`. You can also append a
per-iteration average duration like "(12.34 ms/it)" to the description by
setting `showspeed=true`. The status line can be customized with `elements`,
see [`ProgressMeter.AbstractProgressElement`](@ref).
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
The status line can be customized with `elements`, see
[`ProgressMeter.AbstractProgressElement`](@ref).
"""
const spinner_chars = ['◐','◓','◑','◒']
const spinner_done = '✓'

mutable struct ProgressUnknown <: AbstractProgress
    # internals
    done::Bool              # is the task done?
    spinner::Bool           # show a spinner
    spincounter::Int        # counter for spinner
    spinnerchars::Union{AbstractChar,AbstractString,AbstractVector{<:AbstractChar}} # spinner characters of the current update
    core::ProgressCore      # common properties and internals

    function ProgressUnknown(; spinner::Bool=false, kwargs...)
        CLEAR_IJULIA[] = clear_ijulia()
        core = ProgressCore(;kwargs...)
        new(false, spinner, 0, spinner_chars, core)
    end
end

#...length of percentage and ETA string with days is 29 characters, speed string is always 14 extra characters
description_prefix(desc::AbstractString) = isempty(desc) || endswith(desc, " ") ? desc : desc * " "

function tty_width(desc, output, showspeed::Bool)
    full_width = displaysize(output)[2]
    desc_width = length(description_prefix(desc))
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

"""
    AbstractProgressElement

Supertype for the pieces that make up the status line of a progress meter. A progress
meter concatenates the strings returned by [`print_element`](@ref ProgressMeter.print_element)
for each of its `elements`. Define a subtype and a `print_element` method to show custom
information:

```julia
mutable struct Accepted <: ProgressMeter.AbstractProgressElement
    count::Int
end
ProgressMeter.print_element(e::Accepted, p, status) = " accepted: \$(e.count)"

accepted = Accepted(0)
p = Progress(100; elements = (ProgressMeter.Description(), ProgressMeter.Percentage(),
                              ProgressMeter.Bar(), ProgressMeter.ETA(), accepted))
```
"""
abstract type AbstractProgressElement end

"""
    ProgressStatus

Passed to every [`print_element`](@ref ProgressMeter.print_element) call of a redraw.
Fields: `t` (`time()` of the redraw), `elapsed` (seconds since the meter was created) and
`finished` (whether this is the final redraw).
"""
struct ProgressStatus
    t::Float64
    elapsed::Float64
    finished::Bool
end
ProgressStatus(p::AbstractProgress, t::Float64, finished::Bool) = ProgressStatus(t, t - p.tinit, finished)

"""
    print_element(element, p::AbstractProgress, status::ProgressStatus) -> String

Return the text of `element` for the progress meter `p`. Called once per element each time
the meter is redrawn (at most every `dt` seconds), so this is the place to compute
whatever the element shows. Strings are elements that print themselves.
"""
function print_element end
print_element(s::AbstractString, ::AbstractProgress, ::ProgressStatus) = s

"""Description of the progress meter (`desc`), followed by a space unless it already ends with one."""
struct Description <: AbstractProgressElement
    pad::Bool   # false: print `desc` verbatim
end
Description() = Description(true)
print_element(e::Description, p::AbstractProgress, ::ProgressStatus) = e.pad ? description_prefix(p.desc) : p.desc

"""Percentage of completed steps of a `Progress`, e.g. ` 42%`."""
struct Percentage <: AbstractProgressElement end
function print_element(::Percentage, p::Progress, status::ProgressStatus)
    # don't round up to 100% if not finished (#300)
    percentage = status.finished ? 100 : min(99, round(Int, 100.0 * p.counter / p.n))
    return @sprintf "%3u%%" percentage
end

"""
The bar of a `Progress`, drawn with the meter's `barglyphs`. Its length is the meter's
`barlen`, or, if that is `nothing`, the terminal width left over by the other elements.
"""
struct Bar <: AbstractProgressElement
    legacy_width::Bool   # true: estimate the width of the default elements instead of measuring
end
Bar() = Bar(false)
print_element(b::Bar, p::Progress, status::ProgressStatus) = render_bar(b, p, status, 0, 1)

function render_bar(b::Bar, p::Progress, status::ProgressStatus, width_used::Int, nbars::Int)
    barlen = if p.barlen !== nothing
        p.barlen
    elseif b.legacy_width
        tty_width(p.desc, p.output, p.showspeed)
    else
        # leave the last column free so the line doesn't wrap, the two bar ends need 2 columns
        max(0, ((displaysize(p.output)::Tuple{Int,Int})[2] - width_used - 1) ÷ nbars - 2)
    end
    percentage_complete = status.finished ? 100.0 : 100.0 * p.counter / p.n
    return barstring(barlen, percentage_complete; barglyphs = p.barglyphs)
end

"""Estimated remaining time of a `Progress`, or the total time once finished."""
struct ETA <: AbstractProgressElement end
function print_element(::ETA, p::Progress, status::ProgressStatus)
    status.finished && return " Time: " * durationstring(status.elapsed)
    est_total_time = status.elapsed * (p.n - p.start) / (p.counter - p.start)
    if 0 <= est_total_time <= typemax(Int)
        eta = durationstring(round(Int, est_total_time - status.elapsed))
    else
        eta = "N/A"
    end
    return "  ETA: " * eta
end

"""Average time per iteration, e.g. ` (12.34 ms/it)`."""
struct Speed <: AbstractProgressElement end
print_element(::Speed, p::AbstractProgress, status::ProgressStatus) =
    " (" * speedstring(status.elapsed / iterations(p)) * ")"

iterations(p::Progress) = p.counter - p.start
iterations(p::AbstractProgress) = p.counter

"""Time elapsed since the progress meter was created."""
struct ElapsedTime <: AbstractProgressElement end
print_element(::ElapsedTime, ::AbstractProgress, status::ProgressStatus) = durationstring(status.elapsed)

"""Number of iterations so far."""
struct Counter <: AbstractProgressElement end
print_element(::Counter, p::AbstractProgress, ::ProgressStatus) = string(p.counter)

"""Threshold and current value of a `ProgressThresh`, or the time and iterations taken once finished."""
struct Threshold <: AbstractProgressElement end
function print_element(::Threshold, p::ProgressThresh, status::ProgressStatus)
    status.finished && return @sprintf "Time: %s (%d iterations)" durationstring(status.elapsed) p.counter
    return @sprintf "(thresh = %g, value = %g)" p.thresh p.val
end

"""Spinning character of a `ProgressUnknown`, a check mark once done."""
struct Spinner <: AbstractProgressElement end
function print_element(::Spinner, p::ProgressUnknown, ::ProgressStatus)
    c = spinner_char(p, p.spinnerchars)
    p.spincounter += 1
    return string(c)
end

# elements reproducing the layout from before elements were introduced; built on every redraw
# so that changes to e.g. `p.showspeed` take effect
function default_elements(p::Progress)
    elements = (Description(), Percentage(), Bar(true), ETA())
    return p.showspeed ? (elements..., Speed()) : elements
end

function default_elements(p::ProgressThresh)
    elements = (Description(false), " ", Threshold())
    return p.showspeed ? (elements..., Speed()) : elements
end

function default_elements(p::ProgressUnknown)
    elements = p.spinner ?
        (Spinner(), " ", Description(false), "    Time: ", ElapsedTime()) :
        (Description(false), " ", Counter(), "    Time: ", ElapsedTime())
    return p.showspeed ? (elements..., Speed()) : elements
end

function render_line(p::AbstractProgress, status::ProgressStatus)
    elements = something(p.elements, default_elements(p))
    # bars fill the width the other elements leave, so render those first
    parts = map(e -> e isa Bar ? "" : print_element(e, p, status)::AbstractString, elements)
    nbars = count(e -> e isa Bar, elements)
    if nbars > 0
        width_used = sum(textwidth, parts; init = 0)
        parts = map((e, s) -> e isa Bar ? render_bar(e, p, status, width_used, nbars) : s, elements, parts)
    end
    return join(parts)
end

# Print `msg` over the current line, followed by `showvalues`. `keep` decides what happens at
# the end: `true` moves to a new line, `false` moves back up to the meter, `nothing` (meter
# still running) moves back up unless `guard_ijulia` is set and IJulia output is being cleared
function draw!(p::AbstractProgress, msg::AbstractString; color = p.color, showvalues = (),
               valuecolor = :blue, truncate_lines = false,
               keep::Union{Bool,Nothing}, guard_ijulia::Bool)
    skip_newlines = guard_ijulia && CLEAR_IJULIA[]
    skip_newlines || print(p.output, "\n" ^ (p.offset + p.numprintedvalues))
    move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
    printover(p.output, msg, color)
    printvalues!(p, showvalues; color = valuecolor, truncate = truncate_lines)
    if keep === true
        println(p.output)
    elseif keep === false || !skip_newlines
        print(p.output, "\r\u1b[A" ^ (p.offset + p.numprintedvalues))
    end
    flush(p.output)
    return nothing
end

function draw_finished!(p::AbstractProgress; draw_options...)
    msg = render_line(p, ProgressStatus(p, time(), true))
    draw!(p, msg; draw_options...)
end

# redraw a running meter if enough iterations and time have passed since the last redraw
function draw_running!(p::AbstractProgress, force::Bool, ignore_predictor::Bool, can_draw::Bool = true;
                       draw_options...)
    if force || ignore_predictor || predicted_updates_per_dt_have_passed(p)
        t = time()
        if p.counter > 2
            p.check_iterations = calc_check_iterations(p, t)
        end
        if force || (t > p.tlast + p.dt && can_draw)
            msg = render_line(p, ProgressStatus(p, t, false))
            draw!(p, msg; keep = nothing, draw_options...)
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

# improve performance by checking if enabled before dealing with the options
function updateProgress!(p::AbstractProgress; options...)
    !p.enabled && return nothing
    _updateProgress!(p; options...)
end

# update progress display
function _updateProgress!(p::Progress; showvalues = (),
                         truncate_lines = false, valuecolor = :blue,
                         offset::Integer = p.offset, keep = (offset == 0),
                         desc::Union{Nothing,AbstractString} = nothing,
                         ignore_predictor = false, force::Bool = false,
                         color = p.color, max_steps = p.n)
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
    draw_options = (; showvalues, valuecolor, truncate_lines, guard_ijulia = true)
    if p.counter >= p.n
        if p.counter == p.n && p.printed
            draw_finished!(p; keep, draw_options...)
        end
        return nothing
    end
    draw_running!(p, force, ignore_predictor; draw_options...)
end

function _updateProgress!(p::ProgressThresh; showvalues = (),
                         truncate_lines = false, valuecolor = :blue,
                         offset::Integer = p.offset, keep = (offset == 0),
                         desc = p.desc,
                         ignore_predictor = false, force::Bool = false,
                         color = p.color, thresh = p.thresh)
    p.offset = offset
    p.thresh = thresh
    p.color = color
    p.desc = desc
    draw_options = (; showvalues, valuecolor, truncate_lines, guard_ijulia = false)
    if p.val <= p.thresh && !p.triggered
        p.triggered = true
        p.printed && draw_finished!(p; keep, draw_options...)
        return nothing
    end
    draw_running!(p, force, ignore_predictor, !p.triggered; draw_options...)
end

spinner_char(p::ProgressUnknown, spinner::AbstractChar) = spinner
spinner_char(p::ProgressUnknown, spinner::AbstractVector{<:AbstractChar}) =
    p.done ? spinner_done : spinner[p.spincounter % length(spinner) + firstindex(spinner)]
spinner_char(p::ProgressUnknown, spinner::AbstractString) =
    p.done ? spinner_done : spinner[nextind(spinner, 1, p.spincounter % length(spinner))]

function _updateProgress!(p::ProgressUnknown; showvalues = (), truncate_lines = false,
                        valuecolor = :blue, desc = p.desc,
                        ignore_predictor = false, force::Bool = false,
                        spinner::Union{AbstractChar,AbstractString,AbstractVector{<:AbstractChar}} = spinner_chars,
                        offset::Integer = p.offset, keep = (offset == 0),
                        color = p.color)
    p.offset = offset
    p.color = color
    p.desc = desc
    p.spinnerchars = spinner
    draw_options = (; showvalues, valuecolor, truncate_lines, guard_ijulia = false)
    if p.done
        p.printed && draw_finished!(p; keep, draw_options...)
        return nothing
    end
    draw_running!(p, force, ignore_predictor; draw_options...)
end

predicted_updates_per_dt_have_passed(p::AbstractProgress) = p.counter - p.prev_update_count >= p.check_iterations

function is_threading(p::AbstractProgress)
    p.safe_lock == 0 && return false
    p.safe_lock == 1 && return true
    if p.thread_id != Threads.threadid()
        lock(p.lock) do
            p.safe_lock = 1
        end
        return true
    end
    return false
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
            draw!(p, msg; color, showvalues, valuecolor, truncate_lines, keep, guard_ijulia = false)
        end
    end
    return nothing
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
        msg = "\n  " * lpad(string(name) * ": ", maxwidth+2+1) * string(value)
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
        # issue #76: circumvent IJulia I/O throttling
        if pkgversion(Main.IJulia) < v"1.30"
            Main.IJulia.stdio_bytes[] = 0
        else
            Main.IJulia.reset_stdio_count()
        end
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

# Defined in ProgressMeterDistributedExt.
"""
Equivalent of @showprogress for a distributed for loop.
```
result = @showprogress @distributed (+) for i = 1:50
    sleep(0.1)
    i^2
end
```
"""
function showprogressdistributed end

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
Support for `@distributed` and `pmap` loads with `using Distributed`.

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

        if macroname in (Symbol("@distributed"), :(Distributed.var"@distributed"))
            return showprogressdistributed(args...)

        elseif macroname in (Symbol("@threads"), :(Threads.var"@threads"))
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
specify the number of calls to `f`. Progress updates travel through the channel
returned by `ProgressMeter.progress_channel`.
"""
function progress_map(args...; mapfun=map,
                               progress=Progress(ncalls(mapfun, args...)),
                               channel_bufflen=min(1000, ncalls(mapfun, args...)),
                               kwargs...)
    isempty(args) && return mapfun(; kwargs...)
    f = first(args)
    other_args = args[2:end]
    channel = progress_channel(mapfun, channel_bufflen)
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
    ProgressMeter.progress_channel(::typeof(mapfun), bufflen)

Create the channel that carries progress updates from `mapfun`'s calls to the
progress display. The default is a local `Channel{Bool}(bufflen)`. With Distributed
loaded, every function `mapfun` reports through a `RemoteChannel`, which also reaches
worker processes. A `mapfun` known to run on the main process can keep the local
channel by defining `progress_channel(::typeof(mapfun), bufflen) = Channel{Bool}(bufflen)`.
"""
progress_channel(mapfun, bufflen) = Channel{Bool}(bufflen)

"""
    progress_pmap(f, [::AbstractWorkerPool], c...; progress=Progress(...), kwargs...)

Run `pmap` while displaying progress. Requires `using Distributed`.
"""
function progress_pmap end

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

function __init__()
    Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
        if exc.f in (showprogressdistributed, progress_pmap) && isempty(methods(exc.f))
            print(io, "\n`@showprogress @distributed` and `progress_pmap` load with `using Distributed`.")
        end
    end
end

include("deprecated.jl")

end # module
