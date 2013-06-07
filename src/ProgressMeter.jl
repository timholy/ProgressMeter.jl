module ProgressMeter

export Progress, next!

type Progress
    n::Int
    dt::Float64
    counter::Int
    inext::Int
    tlast::Float64
    printed::Bool    # true if we have issued at least one status update
    
    function Progress(n::Integer, dt::Real)
        this = new(convert(Int, n), convert(Float64, dt), 0)
        this.inext = iceil(n/100)
        this.tlast = time()
        this.printed = false
        this
    end
end

function next!(p::Progress)
    t = time()
    p.counter += 1
    if p.counter >= p.n
        if p.printed
            printover("Progress: done", :green)
            println()
        end
        return
    end
    if p.counter >= p.inext
        p.inext += iceil(p.n/100)
        if t > p.tlast+p.dt
            printover(string("Progress: ", iround(100*p.counter/p.n), "%"), :green)
            p.tlast = t
            p.printed = true
        end
    end
end
    

function printover(io::IO, s::String, color::Symbol = color_normal)
    print(io, "\u1b[1G")   # go to first column
    print_with_color(color, io, s)
    print(io, "\u1b[K")    # clear the rest of the line
end

printover(s::String, color::Symbol = color_normal) = printover(OUTPUT_STREAM, s, color)

end
