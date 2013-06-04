module ProgressMeter

export Progress, next!

type Progress
    n::Int
    dt::Float64
    counter::Int
    inext::Int
    tlast::Float64
    nprintover::Int
    printed::Bool    # true if we have issued at least one status update
    
    function Progress(n::Integer, dt::Real)
        this = new(convert(Int, n), convert(Float64, dt), 0)
        this.inext = iceil(n/100)
        this.tlast = time()
        this.nprintover = 0
        this.printed = false
        this
    end
end

function next!(p::Progress)
    t = time()
    p.counter += 1
    if p.counter >= p.n
        if p.printed
            printover("Progress: done", p.nprintover, :green)
            println()
        end
        return
    end
    if p.counter >= p.inext
        p.inext += iceil(p.n/100)
        if t > p.tlast+p.dt
            p.nprintover = printover(string("Progress: ", iround(100*p.counter/p.n), "%"), p.nprintover, :green)
            p.tlast = t
            p.printed = true
        end
    end
end
    

function printover(io::IO, s::String, n::Integer, color::Symbol = color_normal)
    print(io, "\r"*" "^n*"\r")
    print_with_color(color, io, s)
    length(s)
end

printover(s::String, n::Integer, color::Symbol = color_normal) = printover(OUTPUT_STREAM, s, n, color)

end
