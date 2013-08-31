module ProgressMeter

export Progress, next!, cancel

type Progress
    n::Int
    dt::Float64
    counter::Int
    inext::Int
    tfirst::Float64
    tlast::Float64
    printed::Bool    # true if we have issued at least one status update
    desc::String
    barlen::Int
    
    function Progress(n::Integer, dt::Real = 1.0, desc::String = "Progress: ", barlen::Int = 0)
        this = new(convert(Int, n), convert(Float64, dt), 0)
        this.inext = ceil(n/100)
        this.tfirst = time()
        this.tlast = this.tfirst
        this.printed = false
        this.desc = desc
        this.barlen = barlen
        this
    end

end

function next!(p::Progress)
    t = time()
    p.counter += 1
    if p.counter >= p.n
        if p.printed
            percentage_complete = 100.0 * p.counter / p.n
            bar = print_bar(p.barlen, percentage_complete)
            dur = print_duration(t-p.tfirst)
            msg = @sprintf "%s%3u%%%s Time: %s" p.desc iround(percentage_complete) bar dur
            printover(msg, :green)
            println()
        end
        return
    end
    if p.counter >= p.inext
        p.inext += iceil(p.n/100)
        if t > p.tlast+p.dt
            percentage_complete = 100.0 * p.counter / p.n
            bar = print_bar(p.barlen, percentage_complete)
            elapsed_time = t - p.tfirst
            est_total_time = 100 * elapsed_time / percentage_complete
            eta_sec = iround( est_total_time - elapsed_time )
            eta = print_duration(eta_sec)
            msg = @sprintf "%s%3u%%%s  ETA: %s" p.desc iround(percentage_complete) bar eta
            printover(msg, :green)
            # Compensate for any overhead of printing. This can be especially important
            # if you're running over a slow network connection.
            p.tlast = t + 2*(time()-t)
            p.printed = true
        end
    end
end

function cancel(p::Progress, msg::String = "Computation aborted before all tasks were completed", color = :red)
    if p.printed
        printover(msg, color)
        println()
    end
    return
end

function printover(io::IO, s::String, color::Symbol = color_normal)
    print(io, "\u1b[1G")   # go to first column
    print_with_color(color, io, s)
    print(io, "\u1b[K")    # clear the rest of the line
end

printover(s::String, color::Symbol = color_normal) = printover(STDOUT, s, color)

function print_bar(barlen, percentage_complete)
    bar = ""
    if barlen>0
        nsolid = iround(barlen * percentage_complete / 100)
        nempty = barlen - nsolid
        bar = string("|", repeat("#",nsolid), repeat(" ",nempty), "|")
    end
    return bar
end

function print_duration(nsec)
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
    return hhmmss
end

end
