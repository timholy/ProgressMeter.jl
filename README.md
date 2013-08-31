# ProgressMeter.jl

Progress meter for long-running computations in Julia

## Installation

Within julia, execute
```julia
Pkg.add("ProgressMeter")
```

## Usage

This works for functions that process things in loops.
Here's a demonstration of how to use it:

```julia
using ProgressMeter

function my_long_running_function(filenames::Array)
    n = length(filenames)
    p = Progress(n, 1)   # minumum update interval: 1 second
    for f in filenames
        # Here's where you do all the hard, slow work
        next!(p)
    end
end
```

You should see a green status line that indicates progress during this computation, including ETA and final duration.

If your computation runs so quickly that it never needs to show progress, no extraneous output will be displayed.

Optionally, a description string can be specified which will be prepended to the output, and a progress meter M characters long can be shown.  E.g. 

```julia
p = Progress(n, 1, "Computing initial pass...", 50)
```

will yield

```
Computing initial pass...53%|###########################                       |  ETA: 0:09:02
```

in a manner similar to [python-progressbar](https://code.google.com/p/python-progressbar/).
