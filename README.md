# ProgressMeter.jl

[![Build Status](https://travis-ci.org/timholy/ProgressMeter.jl.svg?branch=master)](https://travis-ci.org/timholy/ProgressMeter.jl)

Progress meter for long-running operations in Julia

## Installation

Within julia, execute
```julia
Pkg.add("ProgressMeter")
```

## Usage

### Progress meters for tasks with a pre-determined number of steps

This works for functions that process things in loops.
Here's a demonstration of how to use it:

```julia
using ProgressMeter

@showprogress 1 "Computing..." for i in 1:50
    sleep(0.1)
end
```

This will use a minimum update interval of 1 second, and show the ETA and final duration.  If your computation runs so quickly that it never needs to show progress, no extraneous output will be displayed.

The `@showprogress` macro wraps a `for` loop or comprehension, as long as the object being iterated over implements the `length` method.  This macro will correctly handle any `continue` statements in a `for` loop as well.

You can also control progress updates and reports manually:

```julia
function my_long_running_function(filenames::Array)
    n = length(filenames)
    p = Progress(n, 1)   # minimum update interval: 1 second
    for f in filenames
        # Here's where you do all the hard, slow work
        next!(p)
    end
end
```

For tasks such as reading file data where the progress increment varies between iterations, you can use `update!`:

```julia
using ProgressMeter

function readFileLines(fileName::String)
    file = open(fileName,"r")

    seekend(file)
    fileSize = position(file)

    seekstart(file)
    p = Progress(fileSize, 1)   # minimum update interval: 1 second
    while !eof(file)
        line = readline(file)
        # Here's where you do all the hard, slow work

        update!(p, position(file))
    end
end
```

Optionally, a description string can be specified which will be prepended to the output, and a progress meter `M` characters long can be shown.  E.g.

```julia
p = Progress(n, 1, "Computing initial pass...", 50)
```

will yield

```
Computing initial pass...53%|###########################                       |  ETA: 0:09:02
```

in a manner similar to [python-progressbar](https://code.google.com/p/python-progressbar/).

### Progress meters for tasks with an unknown number of steps

Some tasks only terminate when some criterion is satisfied, for
example to achieve convergence within a specified tolerance.  In such
circumstances, you can use the `ProgressThresh` type:

```julia
prog = ProgressThresh(1e-5, "Minimizing:")
for val in logspace(2, -6, 20)
    ProgressMeter.update!(prog, val)
    sleep(0.1)
end
```

This will display progress until `val` drops below the threshold value (1e-5).

## Credits

Thanks to Alan Bahm, Andrew Burroughs, and Jim Garrison for major enhancements to this package.
