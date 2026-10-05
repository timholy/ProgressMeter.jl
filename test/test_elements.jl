include("golden_cases.jl")
include("golden_outputs.jl")

@testset "default layout unchanged: $name" for (name, case) in GOLDEN_CASES
    @test capture(case; color = name == "progress_color") == GOLDEN_OUTPUTS[name]
end

mutable struct CountingElement <: ProgressMeter.AbstractProgressElement
    calls::Int
end
function ProgressMeter.print_element(e::CountingElement, p::ProgressMeter.AbstractProgress, status::ProgressMeter.ProgressStatus)
    e.calls += 1
    return status.finished ? " done" : " calls=$(e.calls)"
end

@testset "custom elements" begin
    e = CountingElement(0)
    out = capture() do io
        p = Progress(10; output = io, desc = "Custom:", dt = 1e6,
            elements = (ProgressMeter.Description(), "[", ProgressMeter.Counter(), "]", e))
        for _ in 1:3
            next!(p)        # dt too large to redraw
        end
        @test e.calls == 0
        next!(p; force = true)
        @test e.calls == 1
        finish!(p)
    end
    @test out == "\rCustom: [4] calls=1\e[K\rCustom: [10] done\e[K\n"

    # elements can be set after construction, and work for all progress types
    out = capture() do io
        p = ProgressThresh(1.0; output = io, elements = (ProgressMeter.Threshold(),))
        update!(p, 2.0; force = true)
        p.elements = (ProgressMeter.Counter(), " iterations")
        update!(p, 3.0; force = true)
    end
    @test out == "\r(thresh = 1, value = 2)\e[K\r2 iterations\e[K"

    out = capture() do io
        p = ProgressUnknown(; output = io, elements = (ProgressMeter.Spinner(), ProgressMeter.Counter()))
        next!(p; force = true); finish!(p)
    end
    @test out == "\r◐1\e[K\r✓1\e[K\n"
end

@testset "bar width" begin
    elements = (ProgressMeter.Description(), ProgressMeter.Bar(), ProgressMeter.Percentage())
    for width in (40, 80)
        out = capture(; width) do io
            p = Progress(10; output = io, desc = "Bar:", elements)
            update!(p, 5; force = true)
        end
        line = split(out, '\r')[2]
        # the bar fills the line except for the last column
        @test textwidth(replace(line, "\e[K" => "")) == width - 1
    end

    # a fixed barlen takes precedence
    out = capture() do io
        p = Progress(10; output = io, barlen = 4, barglyphs = BarGlyphs("[=> ]"), elements)
        update!(p, 5; force = true)
    end
    @test out == "\rProgress: [==> ] 50%\e[K"

    # two bars share the remaining width
    out = capture(; width = 31) do io
        p = Progress(10; output = io, elements = (ProgressMeter.Bar(), "|", ProgressMeter.Bar()))
        update!(p, 5; force = true)
    end
    @test textwidth(replace(split(out, '\r')[2], "\e[K" => "")) == 29
end
