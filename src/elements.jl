"""
    ProgressMeter.Elements

The pieces that make up the status line of a progress meter. Pass a tuple of them as
`elements` to `Progress`, `ProgressThresh` or `ProgressUnknown` to rearrange or extend the
status line, e.g.

```julia
using ProgressMeter
p = Progress(100; elements = (Elements.Description(), Elements.Percentage(),
                              Elements.Bar(), Elements.Colored(Elements.ETA(), :blue)))
```

`using ProgressMeter.Elements` brings the element names into scope. Define a subtype of
[`AbstractProgressElement`](@ref) with a [`print_element`](@ref) method for a custom element.
"""
module Elements

using Printf: @sprintf
using ..ProgressMeter: ProgressMeter, AbstractProgress, Progress, ProgressThresh, ProgressUnknown

export AbstractProgressElement, print_element, Colored, Description, Percentage, Bar, ETA,
    Speed, ElapsedTime, Counter, Threshold, Spinner

"""
    AbstractProgressElement

Supertype for the pieces that make up the status line of a progress meter. A progress
meter concatenates the strings returned by [`print_element`](@ref) for each of its
`elements`. Define a subtype and a `print_element` method to show custom information:

```julia
mutable struct Accepted <: Elements.AbstractProgressElement
    count::Int
end
Elements.print_element(e::Accepted, p) = " accepted: \$(e.count)"

accepted = Accepted(0)
p = Progress(100; elements = (Elements.Description(), Elements.Percentage(),
                              Elements.Bar(), Elements.ETA(), accepted))
```
"""
abstract type AbstractProgressElement end

"""
    print_element(element, p::AbstractProgress) -> String

Return the text of `element` for the progress meter `p`. Called once per element each time
the meter is redrawn (at most every `dt` seconds), so this is the place to compute
whatever the element shows. Besides the fields of the meter (e.g. `p.counter`, `p.desc`),
`p.tcurrent` is the `time()` of the redraw, `p.tinit` the time the meter was created and
`p.finished` whether this is the final redraw. Strings are elements that print themselves.
"""
function print_element end
# strings in `elements` act as separators, e.g. " " or "    Time: " in the default layouts
print_element(s::AbstractString, ::AbstractProgress) = s

# seconds since the meter was created, as of the current redraw
elapsed(p::AbstractProgress) = p.tcurrent - p.tinit

"""
    Colored(element, color)

Print `element` in `color` instead of the color of the meter. `color` is a `Symbol` or an
`Int` (0-255) as accepted by `printstyled`, e.g. `Colored(ETA(), :blue)`.
"""
struct Colored{E} <: AbstractProgressElement
    element::E
    color::Union{Symbol,Int}
end
print_element(c::Colored, p::AbstractProgress) = print_element(c.element, p)

element_color(element, p::AbstractProgress) = p.color
element_color(c::Colored, ::AbstractProgress) = c.color

"""Description of the progress meter (`desc`), followed by a space unless it already ends with one."""
struct Description <: AbstractProgressElement
    pad::Bool   # false: print `desc` verbatim
end
Description() = Description(true)
print_element(e::Description, p::AbstractProgress) = e.pad ? ProgressMeter.description_prefix(p.desc) : p.desc

"""Percentage of completed steps of a `Progress`, e.g. ` 42%`."""
struct Percentage <: AbstractProgressElement end
function print_element(::Percentage, p::Progress)
    # don't round up to 100% if not finished (#300)
    percentage = p.finished ? 100 : min(99, round(Int, 100.0 * p.counter / p.n))
    return @sprintf "%3u%%" percentage
end

"""
The bar of a `Progress`, drawn with the meter's `barglyphs`. Its length is the meter's
`barlen`, or, if that is `nothing`, the terminal width left over by the other elements.
"""
struct Bar <: AbstractProgressElement
    legacy_width::Bool   # true: estimate the width of the default elements instead of measuring
end
Bar() = Bar(false)
print_element(b::Bar, p::Progress) = render_bar(b, p, 0, 1)

# the bar inside an element, `nothing` if it isn't a bar; bars are rendered after the other elements
bar(element) = nothing
bar(b::Bar) = b
bar(c::Colored) = bar(c.element)

function render_bar(b::Bar, p::Progress, width_used::Int, nbars::Int)
    barlen = if p.barlen !== nothing
        p.barlen
    elseif b.legacy_width
        ProgressMeter.tty_width(p.desc, p.output, p.showspeed)
    else
        # leave the last column free so the line doesn't wrap, the two bar ends need 2 columns
        max(0, ((displaysize(p.output)::Tuple{Int,Int})[2] - width_used - 1) ÷ nbars - 2)
    end
    percentage_complete = p.finished ? 100.0 : 100.0 * p.counter / p.n
    return ProgressMeter.barstring(barlen, percentage_complete; barglyphs = p.barglyphs)
end

"""Estimated remaining time of a `Progress`, or the total time once finished."""
struct ETA <: AbstractProgressElement end
function print_element(::ETA, p::Progress)
    elapsed_time = elapsed(p)
    p.finished && return " Time: " * ProgressMeter.durationstring(elapsed_time)
    est_total_time = elapsed_time * (p.n - p.start) / (p.counter - p.start)
    if 0 <= est_total_time <= typemax(Int)
        eta = ProgressMeter.durationstring(round(Int, est_total_time - elapsed_time))
    else
        eta = "N/A"
    end
    return "  ETA: " * eta
end

"""Average time per iteration, e.g. ` (12.34 ms/it)`."""
struct Speed <: AbstractProgressElement end
print_element(::Speed, p::AbstractProgress) =
    " (" * ProgressMeter.speedstring(elapsed(p) / iterations(p)) * ")"

iterations(p::Progress) = p.counter - p.start
iterations(p::AbstractProgress) = p.counter

"""Time elapsed since the progress meter was created."""
struct ElapsedTime <: AbstractProgressElement end
print_element(::ElapsedTime, p::AbstractProgress) = ProgressMeter.durationstring(elapsed(p))

"""Number of iterations so far."""
struct Counter <: AbstractProgressElement end
print_element(::Counter, p::AbstractProgress) = string(p.counter)

"""Threshold and current value of a `ProgressThresh`, or the time and iterations taken once finished."""
struct Threshold <: AbstractProgressElement end
function print_element(::Threshold, p::ProgressThresh)
    p.finished && return @sprintf "Time: %s (%d iterations)" ProgressMeter.durationstring(elapsed(p)) p.counter
    return @sprintf "(thresh = %g, value = %g)" p.thresh p.val
end

"""Spinning character of a `ProgressUnknown`, a check mark once done."""
struct Spinner <: AbstractProgressElement end
function print_element(::Spinner, p::ProgressUnknown)
    c = ProgressMeter.spinner_char(p, p.spinnerchars)
    p.spincounter += 1
    return string(c)
end

end # module Elements

using .Elements: Elements, Description, Percentage, Bar, ETA, Speed, ElapsedTime, Counter,
    Threshold, Spinner, print_element, element_color, bar, render_bar

# elements reproducing the layout from before elements were introduced; built on every redraw
# so that changes to e.g. `p.showspeed` take effect
function default_elements(p::Progress)
    elements = (Description(), Percentage(), Bar(true), ETA())
    return p.showspeed ? (elements..., Speed()) : elements
end

function default_elements(p::ProgressThresh)
    elements = (Description(false), " ", Threshold())
    return p.showspeed ? (elements..., Speed()) : elements
end

function default_elements(p::ProgressUnknown)
    elements = p.spinner ?
        (Spinner(), " ", Description(false), "    Time: ", ElapsedTime()) :
        (Description(false), " ", Counter(), "    Time: ", ElapsedTime())
    return p.showspeed ? (elements..., Speed()) : elements
end

const Segment = Pair{String,Union{Symbol,Int}}

# Assemble the status line as `text => color` segments; `p.tcurrent` and `p.finished` must be
# set for the current redraw
function render_line(p::AbstractProgress)
    elements = something(p.elements, default_elements(p))
    # call `print_element` of every element (built-in or user-defined) to assemble the line;
    # bars fill the width the other elements leave, so render those afterwards
    texts = map(e -> bar(e) === nothing ? print_element(e, p)::AbstractString : "", elements)
    nbars = count(e -> bar(e) !== nothing, elements)
    if nbars > 0
        width_used = sum(textwidth, texts; init = 0)
        texts = map((e, s) -> bar(e) === nothing ? s : render_bar(bar(e), p, width_used, nbars), elements, texts)
    end
    # merge neighbouring elements of the same color into one segment
    segments = Segment[]
    for (e, text) in zip(elements, texts)
        color = element_color(e, p)
        if !isempty(segments) && last(segments[end]) == color
            segments[end] = Segment(first(segments[end]) * text, color)
        else
            push!(segments, Segment(text, color))
        end
    end
    return segments
end
