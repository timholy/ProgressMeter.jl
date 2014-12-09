module ProgressMeter

using Compat

export Progress, next!, cancel

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

    function Progress(n::Integer, dt::Real = 1.0, desc::String = "Progress: ", barlen::Int = 0, color::Symbol = :green)
        this = new(convert(Int, n), convert(Float64, dt), 0)
        this.tfirst = time()
        this.tlast = this.tfirst
        this.printed = false
        this.desc = desc
        this.barlen = barlen
        this.color = color
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
        this
    end
end

function next!(p::Progress)
    t = time()
    p.counter += 1
    if p.counter >= p.n
        if p.printed
            percentage_complete = 100.0 * p.counter / p.n
            bar = barstring(p.barlen, percentage_complete)
            dur = durationstring(t-p.tfirst)
            msg = @sprintf "%s%3u%%%s Time: %s" p.desc round(Int, percentage_complete) bar dur
            printover(msg, p.color)
            println()
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
        printover(msg, p.color)
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
        printover(msg, color)
        println()
    end
    return
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

printover(s::String, color::Symbol = :color_normal) = printover(STDOUT, s, color)

function barstring(barlen, percentage_complete)
    bar = ""
    if barlen>0
        nsolid = round(Int, barlen * percentage_complete / 100)
        nempty = barlen - nsolid
        bar = string("|", repeat("#",nsolid), repeat(" ",nempty), "|")
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

end
