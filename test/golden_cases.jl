# Cases rendering progress meters into a fixed-size buffer; used to check that output stays stable.
function capture(f; width = 80, color = false)
    io = IOBuffer()
    f(IOContext(io, :displaysize => (24, width), :color => color))
    s = String(take!(io))
    # elapsed times and speeds depend on the machine
    s = replace(s, r"\d+:\d\d:\d\d" => "H:MM:SS")
    s = replace(s, r"(N/A|\s?\d+\.\d\d|>100) +(ns|μs|ms|s|m|hr|d)/it" => "SPEED/it")
    return s
end

const GOLDEN_CASES = [
    "progress" => io -> begin
        p = Progress(10; desc = "Working:", output = io)
        update!(p, 3; force = true); next!(p; force = true); finish!(p)
    end,
    "progress_showspeed" => io -> begin
        p = Progress(10; desc = "Working:", output = io, showspeed = true)
        update!(p, 3; force = true); finish!(p)
    end,
    "progress_glyphs_barlen" => io -> begin
        p = Progress(10; output = io, barlen = 20, barglyphs = BarGlyphs("[=> ]"))
        update!(p, 3; force = true); update!(p, 7; force = true); finish!(p)
    end,
    "progress_desc_change" => io -> begin
        p = Progress(10; desc = "A", output = io, barlen = 30)
        update!(p, 3; force = true); update!(p, 5; desc = "Longer description", force = true); finish!(p)
    end,
    "progress_nobar_start" => io -> begin
        p = Progress(10; output = io, barlen = 0, start = 2, showspeed = true)
        update!(p, 4; force = true); finish!(p)
    end,
    "progress_max_steps" => io -> begin
        p = Progress(10; output = io)
        update!(p, 4; force = true, max_steps = 20); update!(p, 20)
    end,
    "progress_showvalues_offset" => io -> begin
        p = Progress(10; output = io, offset = 1)
        update!(p, 3; force = true, showvalues = [(:a, 1), (:bbb, "x")])
        update!(p, 10; showvalues = () -> [(:a, 2)])
    end,
    "progress_cancel" => io -> begin
        p = Progress(10; output = io)
        update!(p, 3; force = true); cancel(p)
    end,
    "progress_color" => io -> begin
        p = Progress(10; output = io, color = :red, barlen = 10)
        update!(p, 3; force = true); finish!(p; color = :yellow)
    end,
    "thresh" => io -> begin
        p = ProgressThresh(0.1; desc = "Minimizing:", output = io)
        update!(p, 0.5; force = true); update!(p, 0.2; force = true); update!(p, 0.05)
    end,
    "thresh_showspeed" => io -> begin
        p = ProgressThresh(0.1; output = io, showspeed = true)
        update!(p, 0.5; force = true); finish!(p)
    end,
    "unknown" => io -> begin
        p = ProgressUnknown(; desc = "Reading:", output = io)
        next!(p; force = true); next!(p; force = true); finish!(p)
    end,
    "unknown_spinner_speed" => io -> begin
        p = ProgressUnknown(; desc = "Spinning:", output = io, spinner = true, showspeed = true)
        next!(p; force = true); next!(p; force = true, spinner = "ab"); finish!(p)
    end,
]
