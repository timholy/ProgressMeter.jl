@deprecate Progress(n::Integer, dt::Real, desc::AbstractString="Progress: ",
    barlen=nothing, color::Symbol=:green, output::IO=stderr;
    offset::Integer=0) Progress(n; dt=dt, desc=desc, barlen=barlen, color=color, output=output, offset=offset)

@deprecate Progress(n::Integer, desc::AbstractString, offset::Integer=0; kwargs...) Progress(n; desc=desc, offset=offset, kwargs...)

@deprecate ProgressThresh(thresh::Real, dt::Real, desc::AbstractString="Progress: ",
         color::Symbol=:green, output::IO=stderr;
         offset::Integer=0) ProgressThresh(thresh; dt=dt, desc=desc, color=color, output=output, offset=offset)

@deprecate ProgressThresh(thresh::Real, desc::AbstractString, offset::Integer=0) ProgressThresh(thresh; desc=desc, offset=offset)

@deprecate ProgressUnknown(dt::Real, desc::AbstractString="Progress: ",
         color::Symbol=:green, output::IO=stderr; kwargs...) ProgressUnknown(; dt=dt, desc=desc, color=color, output=output, kwargs...)

@deprecate ProgressUnknown(desc::AbstractString; kwargs...) ProgressUnknown(; desc=desc, kwargs...)

@deprecate next!(p::Union{Progress, ProgressUnknown}, color::Symbol; options...) next!(p; color=color, options...)

@deprecate update!(p::AbstractProgress, val, color; options...) update!(p, val; color=color, options...)

@deprecate cancel(p::AbstractProgress, msg, color; options...) cancel(p, msg; color=color, options...)
