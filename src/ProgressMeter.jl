module ProgressMeter

using Printf: @sprintf
using Distributed

export Progress, ProgressThresh, BarGlyphs, next!, update!, cancel, finish!, @showprogress, progress_map, progress_pmap

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
    front::Char
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
output=stderr, barlen=tty_width(desc))` creates a progress meter for a
task with `n` iterations or stages. Output will be generated at
intervals at least `dt` seconds apart, and perhaps longer if each
iteration takes longer than `dt`. `desc` is a description of
the current task.
"""
mutable struct Progress <: AbstractProgress
    n::Int
    dt::Float64
    counter::Int
    tfirst::Float64
    tlast::Float64
    printed::Bool           # true if we have issued at least one status update
    desc::AbstractString    # prefix to the percentage, e.g.  "Computing..."
    offset::Int             # position offset of progress bar (default is 0)
    barlen::Int             # progress bar size (default is available terminal width)
    barglyphs::BarGlyphs    # the characters to be used in the bar
    color::Symbol           # default to green
    output::IO              # output stream into which the progress is written
    numprintedvalues::Int   # num values printed below progress in last iteration

    function Progress(n::Integer;
                      dt::Real=0.1,
                      desc::AbstractString="Progress: ",
                      offset::Int=0,
                      color::Symbol=:green,
                      output::IO=stderr,
                      barlen::Integer=tty_width(desc),
                      barglyphs::BarGlyphs=BarGlyphs('|','█','█',' ','|'))
        counter = 0
        tfirst = tlast = time()
        printed = false
        new(n, dt, counter, tfirst, tlast, printed, desc, offset, barlen, barglyphs, color, output, 0)
    end
end

Progress(n::Integer, dt::Real, desc::AbstractString="Progress: ", offset::Integer=0,
         barlen::Integer=tty_width(desc), color::Symbol=:green, output::IO=stderr) =
    Progress(n, dt=dt, desc=desc, offset=offset, barlen=barlen, color=color, output=output)

Progress(n::Integer, desc::AbstractString, offset::Integer=0) = Progress(n, desc=desc, offset=offset)


"""
`prog = ProgressThresh(thresh; dt=0.1, desc="Progress: ",
color=:green, output=stderr)` creates a progress meter for a task
which will terminate once a value less than or equal to `thresh` is
reached. Output will be generated at intervals at least `dt` seconds
apart, and perhaps longer if each iteration takes longer than
`dt`. `desc` is a description of the current task.
"""
mutable struct ProgressThresh{T<:Real} <: AbstractProgress
    thresh::T
    dt::Float64
    val::T
    counter::Int
    triggered::Bool
    tfirst::Float64
    tlast::Float64
    printed::Bool        # true if we have issued at least one status update
    desc::AbstractString # prefix to the percentage, e.g.  "Computing..."
    offset::Int             # position offset of progress bar (default is 0)
    color::Symbol        # default to green
    output::IO           # output stream into which the progress is written
    numprintedvalues::Int   # num values printed below progress in last iteration

    function ProgressThresh{T}(thresh;
                               dt::Real=0.1,
                               desc::AbstractString="Progress: ",
                               offset::Int=0,
                               color::Symbol=:green,
                               output::IO=stderr) where T
        tfirst = tlast = time()
        printed = false
        new{T}(thresh, dt, typemax(T), 0, false, tfirst, tlast, printed, desc, color, output, 0)
    end
end

ProgressThresh(thresh::Real, dt::Real=0.1, desc::AbstractString="Progress: ", positon::Integer=0,
         color::Symbol=:green, output::IO=stderr) =
    ProgressThresh{typeof(thresh)}(thresh, dt=dt, desc=desc, offset=0, color=color, output=output)

ProgressThresh(thresh::Real, desc::AbstractString) = ProgressThresh{typeof(thresh)}(thresh, desc=desc)

#...length of percentage and ETA string with days is 29 characters
tty_width(desc) = max(0, displaysize()[2] - (length(desc) + 29))

# update progress display
function updateProgress!(p::Progress; showvalues = Any[], valuecolor = :blue, offset::Integer = p.offset)
    p.offset = offset
    t = time()
    if p.counter >= p.n
        if p.counter == p.n && p.printed
            percentage_complete = 100.0 * p.counter / p.n
            bar = barstring(p.barlen, percentage_complete, barglyphs=p.barglyphs)
            dur = durationstring(t-p.tfirst)
            msg = @sprintf "%s%3u%%%s Time: %s" p.desc round(Int, percentage_complete) bar dur
            print(p.output, "\r")
            print(p.output, "\n" ^ p.offset)
            print(p.output, "\n" ^ p.numprintedvalues)
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor)
            print(p.output, "\u1b[A" ^ p.numprintedvalues)
            print(p.output, "\u1b[A" ^ p.offset)
        end
        return nothing
    end

    if t > p.tlast+p.dt
        percentage_complete = 100.0 * p.counter / p.n
        bar = barstring(p.barlen, percentage_complete, barglyphs=p.barglyphs)
        elapsed_time = t - p.tfirst
        est_total_time = 100 * elapsed_time / percentage_complete
        if 0 <= est_total_time <= typemax(Int)
            eta_sec = round(Int, est_total_time - elapsed_time )
            eta = durationstring(eta_sec)
        else
            eta = "N/A"
        end
        msg = @sprintf "%s%3u%%%s  ETA: %s" p.desc round(Int, percentage_complete) bar eta
        print(p.output, "\r")
        print(p.output, "\n" ^ p.offset)
        print(p.output, "\n" ^ p.numprintedvalues)
        move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
        printover(p.output, msg, p.color)
        printvalues!(p, showvalues; color = valuecolor)
        print(p.output, "\u1b[A" ^ p.numprintedvalues)
        print(p.output, "\r\u1b[A" ^ p.offset)
        # Compensate for any overhead of printing. This can be
        # especially important if you're running over a slow network
        # connection.
        p.tlast = t + 2*(time()-t)
        p.printed = true
    end
    return nothing
end

function updateProgress!(p::ProgressThresh; showvalues = Any[], valuecolor = :blue, offset::Integer = p.offset)
    p.offset = offset
    t = time()
    if p.val <= p.thresh && !p.triggered
        p.triggered = true
        if p.printed
            p.triggered = true
            dur = durationstring(t-p.tfirst)
            msg = @sprintf "%s Time: %s (%d iterations)" p.desc dur p.counter
            print(p.output, "\r")
            print(p.output, "\n" ^ p.offset)
            print(p.output, "\n" ^ p.numprintedvalues)
            move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
            printover(p.output, msg, p.color)
            printvalues!(p, showvalues; color = valuecolor)
            print(p.output, "\u1b[A" ^ p.numprintedvalues)
            print(p.output, "\r\u1b[A" ^ p.offset)
        end
        return
    end

    if t > p.tlast+p.dt && !p.triggered
        elapsed_time = t - p.tfirst
        msg = @sprintf "%s (thresh = %g, value = %g)" p.desc p.thresh p.val
        print(p.output, "\r")
        print(p.output, "\n" ^ p.offset)
        print(p.output, "\n" ^ p.numprintedvalues)
        move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
        printover(p.output, msg, p.color)
        printvalues!(p, showvalues; color = valuecolor)
        print(p.output, "\u1b[A" ^ p.numprintedvalues)
        print(p.output, "\r\u1b[A" ^ p.offset)
        # Compensate for any overhead of printing. This can be
        # especially important if you're running over a slow network
        # connection.
        p.tlast = t + 2*(time()-t)
        p.printed = true
    end
end

# update progress display
"""
`next!(prog, [color])` reports that one unit of progress has been
made. Depending on the time interval since the last update, this may
or may not result in a change to the display.

You may optionally change the color of the display. See also `update!`.
"""
function next!(p::Progress; options...)
    p.counter += 1
    updateProgress!(p; options...)
end

function next!(p::Progress, color::Symbol; options...)
    p.color = color
    next!(p; options...)
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
function update!(p::Progress, counter::Int; options...)
    p.counter = counter
    updateProgress!(p; options...)
end

function update!(p::Progress, counter::Int, color::Symbol; options...)
    p.color = color
    update!(p, counter; options...)
end

function update!(p::ProgressThresh, val; options...)
    p.val = val
    p.counter += 1
    updateProgress!(p; options...)
end

function update!(p::ProgressThresh, val, color::Symbol; options...)
    p.color = color
    update!(p, val; options...)
end


"""
`cancel(prog, [msg], [color=:red])` cancels the progress display
before all tasks were completed. Optionally you can specify the
message printed and its color.

See also `finish!`.
"""
function cancel(p::AbstractProgress, msg::AbstractString = "Aborted before all tasks were completed", color = :red; showvalues = Any[], valuecolor = :blue)
    if p.printed
        print(p.output, "\r")
        print(p.output, "\n" ^ p.offset)
        print(p.output, "\n" ^ p.numprintedvalues)
        move_cursor_up_while_clearing_lines(p.output, p.numprintedvalues)
        printover(p.output, msg, color)
        printvalues!(p, showvalues; color = valuecolor)
        println(p.output)
        print(p.output, "\u1b[A" ^ p.numprintedvalues)
        print(p.output, "\r\u1b[A" ^ p.offset)
    end
    return
end

"""
`finish!(prog)` indicates that all tasks have been completed.

See also `cancel`.
"""
function finish!(p::Progress; options...)
    while p.counter < p.n
        next!(p; options...)
    end
end

function finish!(p::ProgressThresh; options...)
    update!(p, p.thresh; options...)
end

# Internal method to print additional values below progress bar
function printvalues!(p::AbstractProgress, showvalues; color = false)
    length(showvalues) == 0 && return
    maxwidth = maximum(Int[length(string(name)) for (name, _) in showvalues])
    for (name, value) in showvalues
        msg = "\n  " * rpad(string(name) * ": ", maxwidth+2+1) * string(value)
        (color == false) ? print(p.output, msg) : printstyled(p.output, msg; color=color)
    end
    p.numprintedvalues = length(showvalues)
end

function move_cursor_up_while_clearing_lines(io, numlinesup)
    for _ in 1:numlinesup
        print(io, "\r\u1b[K\u1b[A")
    end
end

function printover(io::IO, s::AbstractString, color::Symbol = :color_normal)
    if isdefined(Main, :ESS) || isdefined(Main, :Atom)
        print(io, '\r', s)
    elseif isdefined(Main, :IJulia)
        print(io, '\r')
        printstyled(io, s; color=color) # Jupyter notebooks support ANSI color codes
        Main.IJulia.stdio_bytes[] = 0 # issue #76: circumvent IJulia I/O throttling
    else
        print(io, "\r")         # go to first column
        printstyled(io, s; color=color)
        print(io, "\u1b[K")     # clear the rest of the line
    end
end

function barstring(barlen, percentage_complete; barglyphs::BarGlyphs=BarGlyphs('|','█','█',' ','|'))
    bar = ""
    if barlen>0
        if percentage_complete == 100 # if we're done, don't use the "front" character
            bar = string(barglyphs.leftend, repeat(string(barglyphs.fill), barlen), barglyphs.rightend)
        else
            nsolid = round(Int, barlen * percentage_complete / 100)
            nempty = barlen - nsolid
            bar = string(barglyphs.leftend,
                         repeat(string(barglyphs.fill), max(0,nsolid-1)),
                         nsolid>0 ? barglyphs.front : "",
                         repeat(string(barglyphs.empty), nempty),
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
    seconds = r - 60*minutes

    hhmmss = @sprintf "%u:%02u:%02u" hours minutes seconds
    if days>9
        return @sprintf "%.2f days" nsec/(60*60*24)
    elseif days>0
        return @sprintf "%u days, %s" days hhmmss
    end
    hhmmss
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

`@showprogress` works for loops, comprehensions, map, and pmap.
"""
macro showprogress(args...)
    if length(args) < 1
        throw(ArgumentError("@showprogress requires at least one argument."))
    end
    progressargs = args[1:end-1]
    expr = args[end]
    orig = expr = copy(expr)
    metersym = gensym("meter")
    mapfuns = (:map, :pmap)
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
        throw(ArgumentError("Final argument to @showprogress must be a for loop, comprehension, map, or pmap; got $expr"))
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
            return isa(a, Symbol) || a.head != :kw
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

`mapfun` can be any function, but it is only tested with `map` and `pmap`.
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
Infer the number of calls to the mapped function (i.e. the length of the returned array) given the input arguments to map or pmap.
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
