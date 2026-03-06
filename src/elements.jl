

struct ProgressText <: AbstractProgressElement
    text::String
end
Base.convert(::Type{AbstractProgressElement}, s::AbstractString) = ProgressText(s)
prog_length(t::ProgressText) = length(t.text)
prog_string(t::ProgressText, _) = t.text

struct ProgressPercentage <: AbstractProgressElement end
prog_length(::ProgressPercentage) = 4 # "100%"
function prog_string(::ProgressPercentage, p::Progress)
    percentage_complete = 100.0 * p.counter / p.n
    percentage_rounded = min(100, floor(Int, percentage_complete))
    return lpad(string(percentage_rounded, "%"), 4)
end

struct ProgressBar <: AbstractProgressElement 
    barglyphs::BarGlyphs
    length::Int
    function ProgressBar(; barglyphs::BarGlyphs=defaultglyphs, length::Int=20)
        new(barglyphs, length)
    end
end
prog_length(e::ProgressBar) = e.length
function prog_string(e::ProgressBar, p::Progress)
    percentage_complete = min(100.0, 100.0 * p.counter / p.n)
    return barstring(e.length, percentage_complete; barglyphs=e.barglyphs)
end

struct ProgressETA <: AbstractProgressElement end
prog_length(::ProgressETA) = 29
function prog_string(::ProgressETA, p::Progress)
    if p.counter == 0
        return "ETA: N/A"
    end
    elapsed_time = time() - p.tinit
    est_total_time = elapsed_time * (p.n - p.start) / (p.counter - p.start)
    if 0 <= est_total_time <= typemax(Int)
        eta_sec = max(0, round(Int, est_total_time - elapsed_time))
        eta = durationstring(eta_sec)
    else
        eta = "N/A"
    end
    return "ETA: $eta"
end

struct ProgressSpeed <: AbstractProgressElement end
prog_length(::ProgressSpeed) = 14
function prog_string(::ProgressSpeed, p::Progress)
    if p.counter <= 1
        return "  N/A  s/it"
    end
    elapsed_time = time() - p.tinit
    sec_per_iter = elapsed_time / (p.counter - p.start)
    return speedstring(sec_per_iter)
end



const defaultprogresselements = ProgressElements(("Progress: ", ProgressPercentage(), " ", ProgressBar()," ", ProgressETA(), ", ", ProgressSpeed()))
