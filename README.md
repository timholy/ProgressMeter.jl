# ProgressMeter.jl

[![Build Status](https://travis-ci.org/timholy/ProgressMeter.jl.svg?branch=master)](https://travis-ci.org/timholy/ProgressMeter.jl)

Progress meter for long-running operations in Julia

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
    p = Progress(n, 1)   # minimum update interval: 1 second
    for f in filenames
        # Here's where you do all the hard, slow work
        next!(p)
    end
end
```

You should see a green status line that indicates progress during this computation, including ETA and final duration.

If your computation runs so quickly that it never needs to show progress, no extraneous output will be displayed.

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

Finally, it is possible to use the `@showprogress` macro to wrap a `for` loop or comprehension, as long as the object being iterated over implements the `length` method.  This macro will correctly handle any `continue` statements in a `for` loop as well.

```julia
@showprogress 1 "Computing..." for i in 1:50
    sleep(0.1)
end
```

## Credits

Thanks to Alan Bahm, Andrew Burroughs, and Jim Garrison for major enhancements to this package.

