module ProgressMeter

using Compat

export Progress, next!, update!, cancel, finish!, @showprogress

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

    function Progress(n::Integer, dt::Real = 1.0, desc::String = "Progress: ", barlen::Int = 0, color::Symbol = :green, output::IO = STDOUT)
        this = new(convert(Int, n), convert(Float64, dt), 0)
        this.tfirst = time()
        this.tlast = this.tfirst
        this.printed = false
        this.desc = desc
        this.barlen = barlen
        this.color = color
        this.output = output
        this
    end

    function Progress(n::Integer, desc::String = "Progress: ")
        this = new(convert(Int, n), convert(Float64, 0.01), 0)
        this.tfirst = time()
        this.tlast = this.tfirst
        this.printed = false
        this.desc = desc
        #...length of percentage and ETA string with days is 29 characters
        this.barlen = max(0, Base.tty_size()[2] - (length(desc)+29))
        this.color = :green
        this.output = STDOUT
        this
    end
end

# update progress display
function updateProgress!(p::Progress)
    t = time()
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

function next!(p::Progress)
    p.counter += 1
    updateProgress!(p)
end

function next!(p::Progress, color::Symbol)
    p.color = color
    next!(p)
end


# for custom progress value 'counter'
function update!(p::Progress, counter::Int)
    p.counter = counter
    updateProgress!(p)
end

function update!(p::Progress, counter::Int, color::Symbol)
    p.color = color
    update!(p, counter)
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

immutable ProgressWrapper{T}
    obj::T
    meter::Progress
end

ProgressWrapper{T}(obj::T, meter::Progress) = ProgressWrapper{T}(obj, meter)

Base.length(wrap::ProgressWrapper) = Base.length(wrap.obj)
Base.start(wrap::ProgressWrapper) = (Base.start(wrap.obj), true)
Base.done(wrap::ProgressWrapper, state) = Base.done(wrap.obj, state[1])

function Base.next(wrap::ProgressWrapper, state)
    st, firstiteration = state
    firstiteration || next!(wrap.meter)
    i, st = Base.next(wrap.obj, st)
    return (i, (st, false))
end

macro showprogress(args...)
    if length(args) < 1
        throw(ArgumentError("@showprogress requires at least one argument."))
    end
    progressargs = args[1:end-1]
    loop = args[end]
    metersym = gensym("meter")

    if isa(loop, Expr) && loop.head === :for
        outerassignidx = 1
        loopbodyidx = endof(loop.args)
    elseif isa(loop, Expr) && loop.head in (:comprehension, :dict_comprehension)
        outerassignidx = endof(loop.args)
        loopbodyidx = 1
    elseif isa(loop, Expr) && loop.head in (:typed_comprehension, :typed_dict_comprehension)
        outerassignidx = endof(loop.args)
        loopbodyidx = 2
    else
        throw(ArgumentError("Final argument to @showprogress must be a for loop or comprehension."))
    end

    loop = copy(loop)

    # Transform the first loop assignment
    loopassign = loop.args[outerassignidx] = copy(loop.args[outerassignidx])
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
    if loop.head === :for
        loop.args[loopbodyidx] = showprogress_process_expr(loop.args[loopbodyidx], metersym)
    end

    # Escape all args except the loop assignment, which was already appropriately escaped.
    for i in 1:length(loop.args)
        if i != outerassignidx
            loop.args[i] = esc(loop.args[i])
        end
    end

    setup = quote
        iterable = $(esc(obj))
        $(esc(metersym)) = Progress(length(iterable), $([esc(arg) for arg in progressargs]...))
    end

    if loop.head === :for
        return quote
            $setup
            $loop
        end
    else
        # We're dealing with a comprehension
        return quote
            begin
                $setup
                rv = $loop
                next!($(esc(metersym)))
                rv
            end
        end
    end
end

end
