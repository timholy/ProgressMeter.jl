include("golden_cases.jl")
include("golden_outputs.jl")

@testset "default layout unchanged: $name" for (name, case) in GOLDEN_CASES
    @test capture(case; color = name == "progress_color") == GOLDEN_OUTPUTS[name]
end

mutable struct CountingElement <: Elements.AbstractProgressElement
    calls::Int
end
function Elements.print_element(e::CountingElement, p::ProgressMeter.AbstractProgress)
    e.calls += 1
    return p.finished ? " done" : " calls=$(e.calls)"
end

@testset "custom elements" begin
    e = CountingElement(0)
    out = capture() do io
        p = Progress(10; output = io, desc = "Custom:", dt = 1e6,
            elements = (Elements.Description(), "[", Elements.Counter(), "]", e))
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
        p = ProgressThresh(1.0; output = io, elements = (Elements.Threshold(),))
        update!(p, 2.0; force = true)
        p.elements = (Elements.Counter(), " iterations")
        update!(p, 3.0; force = true)
    end
    @test out == "\r(thresh = 1, value = 2)\e[K\r2 iterations\e[K"

    out = capture() do io
        p = ProgressUnknown(; output = io, elements = (Elements.Spinner(), Elements.Counter()))
        next!(p; force = true); finish!(p)
    end
    @test out == "\r◐1\e[K\r✓1\e[K\n"
end

@testset "bar width" begin
    elements = (Elements.Description(), Elements.Bar(), Elements.Percentage())
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
        p = Progress(10; output = io, elements = (Elements.Bar(), "|", Elements.Bar()))
        update!(p, 5; force = true)
    end
    @test textwidth(replace(split(out, '\r')[2], "\e[K" => "")) == 29
end

@testset "colors" begin
    using ProgressMeter.Elements: Colored, Description, Percentage, Bar
    elements = (Colored(Description(), :blue), Percentage(), Colored(Bar(), 208))
    out = capture(; color = true) do io
        p = Progress(10; output = io, desc = "Color:", barlen = 4, barglyphs = BarGlyphs("[=> ]"), elements)
        update!(p, 5; force = true)
    end
    # neighbouring elements of the same color share one escape sequence
    @test out == "\r\e[34mColor: \e[39m\e[32m 50%\e[39m\e[38;5;208m[==> ]\e[39m\e[K"

    # elements without a color follow the meter's color, also when changed on update
    out = capture(; color = true) do io
        p = Progress(10; output = io, desc = "Color:", barlen = 0, elements = (Colored(Description(), :blue), Percentage()))
        update!(p, 5; force = true, color = :red)
    end
    @test out == "\r\e[34mColor: \e[39m\e[31m 50%\e[39m\e[K"
end
