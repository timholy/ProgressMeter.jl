module ProgressMeter

using Compat

export Progress, next!, cancel, finish!, @showprogress

type Progress
    n::Int
    dt::Float64
    counter::Int
    tfirst::Float64
    tlast::Float64
    printed::Bool    # true if we have issued at least one status update
    desc::String     # prefix to the percentage, e.g.  "Computing..."
    barlen::Int      # progress bar size (default is available terminal width)
    color::Symbol    # default to green
    output::IO       # output stream into which the progress is written

    function Progress(n::Integer; dt::Real=1.0, desc::String="Progress: ", color::Symbol=:green, output::IO=STDOUT,
                      #...length of percentage and ETA string with days is 29 characters
                      barlen::Int=max(0, Base.tty_size()[2] - (length(desc)+29)))
        counter = 0
        tfirst = tlast = time()
        printed = false
        new(n, dt, counter, tfirst, tlast, printed, desc, barlen, color, output)
    end
end

Progress(n::Integer, dt::Real=1.0, desc::String="Progress: ", barlen::Int=0, color::Symbol=:green, output::IO=STDOUT) =
    Progress(n, dt=dt, desc=desc, barlen=barlen, color=color, output=output)

Progress(n::Integer, desc::String) = Progress(n, dt=0.01, desc=desc)

function next!(p::Progress)
    t = time()
    p.counter += 1
    if p.counter >= p.n
        if p.counter == p.n && p.printed
            percentage_complete = 100.0 * p.counter / p.n
            bar = barstring(p.barlen, percentage_complete)
            dur = durationstring(t-p.tfirst)
            msg = @sprintf "%s%3u%%%s Time: %s" p.desc round(Int, percentage_complete) bar dur
            printover(p.output, msg, p.color)
            println(p.output)
        end
        return
    end

    if t > p.tlast+p.dt
        percentage_complete = 100.0 * p.counter / p.n
        bar = barstring(p.barlen, percentage_complete)
        elapsed_time = t - p.tfirst
        est_total_time = 100 * elapsed_time / percentage_complete
        eta_sec = round(Int, est_total_time - elapsed_time )
        eta = durationstring(eta_sec)
        msg = @sprintf "%s%3u%%%s  ETA: %s" p.desc round(Int, percentage_complete) bar eta
        printover(p.output, msg, p.color)
        # Compensate for any overhead of printing. This can be especially important
        # if you're running over a slow network connection.
        p.tlast = t + 2*(time()-t)
        p.printed = true
    end
end

function next!(p::Progress, color::Symbol)
  p.color = color
  next!(p)
end

function cancel(p::Progress, msg::String = "Aborted before all tasks were completed", color = :red)
    if p.printed
        printover(p.output, msg, color)
        println(p.output)
    end
    return
end

function finish!(p::Progress)
    while p.counter < p.n
        next!(p)
    end
end

function printover(io::IO, s::String, color::Symbol = :color_normal)
    if isdefined(Main, :IJulia)
        print(io, "\r" * s)
    else
        print(io, "\u1b[1G")   # go to first column
        print_with_color(color, io, s)
        print(io, "\u1b[K")    # clear the rest of the line
    end
end

function barstring(barlen, percentage_complete; solidglyph="█", emptyglyph=" ")
    bar = ""
    if barlen>0
        nsolid = round(Int, barlen * percentage_complete / 100)
        nempty = barlen - nsolid
        bar = string("|", repeat(solidglyph, nsolid), repeat(emptyglyph, nempty), "|")
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
    if days>0
       return @sprintf "%u days, %s" days hhmmss
    end
    hhmmss
end

function showprogress_process_expr(node, metersym)
    if !isa(node, Expr)
        node
    elseif node.head === :break
        # special handling for break statement
        quote
            ($finish!)($metersym)
            $node
        end
    elseif node.head === :continue
        # special handling for continue statement
        quote
            ($next!)($metersym)
            $node
        end
    elseif node.head === :for || node.head === :while
        # do not process break and continue statements in inner loops
        node
    else
        # process each subexpression recursively
        Expr(node.head, [showprogress_process_expr(a, metersym) for a in node.args]...)
    end
end

macro showprogress(args...)
    if length(args) < 1
        throw(ArgumentError("@showprogress requires at least one argument."))
    end
    progressargs = args[1:end-1]
    loop = args[end]
    metersym = gensym("meter")

    if isa(loop, Expr) && loop.head === :for
        @assert length(loop.args) == 2
        assignidx = 1
        loopbodyidx = 2
    elseif isa(loop, Expr) && loop.head in (:comprehension, :dict_comprehension)
        @assert length(loop.args) == 2
        assignidx = 2
        loopbodyidx = 1
    elseif isa(loop, Expr) && loop.head in (:typed_comprehension, :typed_dict_comprehension)
        @assert length(loop.args) == 3
        assignidx = 3
        loopbodyidx = 2
    else
        throw(ArgumentError("Final argument to @showprogress must be a for loop or comprehension."))
    end

    newloop = Expr(loop.head, loop.args...)

    # Transform the loop body
    is_dict_comprehension = loop.head in (:dict_comprehension, :typed_dict_comprehension)
    if is_dict_comprehension
        @assert loop.args[loopbodyidx].head === :(=>)
        @assert length(loop.args[loopbodyidx].args) == 2
        innerbody = loop.args[loopbodyidx].args[2]
    else
        innerbody = loop.args[loopbodyidx]
    end
    newinnerbody = quote
        begin
            rv = $(esc(showprogress_process_expr(innerbody, metersym)))
            $(next!)($(esc(metersym)))
            rv
        end
    end
    if is_dict_comprehension
        newloop.args[loopbodyidx] = Expr(:(=>), esc(loop.args[loopbodyidx].args[1]), newinnerbody)
    else
        newloop.args[loopbodyidx] = newinnerbody
    end

    # Transform the loop assignment
    loopassign = loop.args[assignidx]
    @assert loopassign.head == :(=)
    @assert length(loopassign.args) == 2
    newloop.args[assignidx] = :($(esc(loopassign.args[1])) = iterable)

    return quote
        iterable = $(esc(loopassign.args[2]))
        $(esc(metersym)) = Progress(length(iterable), $([esc(arg) for arg in progressargs]...))
        $newloop
    end
end

end
