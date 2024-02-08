# ProgressMeter.jl

[![Build Status](https://github.com/timholy/ProgressMeter.jl/workflows/CI/badge.svg)](https://github.com/timholy/ProgressMeter.jl/actions)

Progress meter for long-running operations in Julia

## Installation

Within julia, execute
```julia
using Pkg; Pkg.add("ProgressMeter")
```

## Usage

### Progress meters for tasks with a pre-determined number of steps

This works for functions that process things in loops or with `map`/`pmap`/`reduce`:

```julia
using Distributed
using ProgressMeter

@showprogress dt=1 desc="Computing..." for i in 1:50
    sleep(0.1)
end

@showprogress pmap(1:10) do x
    sleep(0.1)
    x^2
end

@showprogress reduce(1:10) do x, y
    sleep(0.1)
    x + y
end
```

The first incantation will use a minimum update interval of 1 second, and show the ETA and
final duration.  If your computation runs so quickly that it never needs to show progress,
no extraneous output will be displayed.

The `@showprogress` macro wraps a `for` loop, comprehension, `@distributed` for loop, or
`map`/`pmap`/`reduce` as long as the object being iterated over implements the `length`
method and will handle `continue` correctly.

```julia
using Distributed
using ProgressMeter

@showprogress @distributed for i in 1:10
    sleep(0.1)
end

result = @showprogress desc="Computing..." @distributed (+) for i in 1:10
    sleep(0.1)
    i^2
end
```

In the case of a `@distributed` for loop without a reducer, an `@sync` is implied.

You can also control progress updates and reports manually:

```julia
function my_long_running_function(filenames::Array)
    n = length(filenames)
    p = Progress(n; dt=1.0)   # minimum update interval: 1 second
    for f in filenames
        # Here's where you do all the hard, slow work
        next!(p)
    end
end
```

For tasks such as reading file data where the progress increment varies between iterations,
you can use `update!`:

```julia
using ProgressMeter

function readFileLines(fileName::String)
    file = open(fileName,"r")

    seekend(file)
    fileSize = position(file)

    seekstart(file)
    p = Progress(fileSize; dt=1.0)   # minimum update interval: 1 second
    while !eof(file)
        line = readline(file)
        # Here's where you do all the hard, slow work

        update!(p, position(file))
    end
end
```

The core methods `Progress()`, `ProgressThresh()`, `ProgressUnknown()`, and their updaters
are also thread-safe, so can be used with `Threads.@threads`, `Threads.@spawn` etc.:

```julia
using ProgressMeter
p = Progress(10)
Threads.@threads for i in 1:10
    sleep(2*rand())
    next!(p)
end
finish!(p)
```

```julia
using ProgressMeter
n = 10
p = Progress(n)
tasks = Vector{Task}(undef, n)
for i in 1:n
    tasks[i] = Threads.@spawn begin
        sleep(2*rand())
        next!(p)
    end
end
wait.(tasks)
finish!(p)
```

### Progress bar style

Optionally, a description string can be specified which will be prepended to the output,
and a progress meter `M` characters long can be shown.  E.g.

```julia
p = Progress(n; desc="Computing initial pass...")
```

will yield

```
Computing initial pass...53%|███████████████████████████                       |  ETA: 0:09:02
```

in a manner similar to [python-progressbar](https://code.google.com/p/python-progressbar/).

Also, other properties can be modified through keywords. The glyphs used in the bar may be
specified by passing a `BarGlyphs` object as the keyword argument `barglyphs`. The `BarGlyphs`
constructor can either take 5 characters as arguments or a single 5 character string. E.g.

```julia
p = Progress(n; dt=0.5, barglyphs=BarGlyphs("[=> ]"), barlen=50, color=:yellow)
```

will yield

```
Progress: 53%[==========================>                       ]  ETA: 0:09:02
```

It is possible to give a vector of characters that acts like a transition between the empty
character and the fully filled character. For example, definining the progress bar as:

```julia
p = Progress(n; dt=0.5,
             barglyphs=BarGlyphs('|','█', ['▁' ,'▂' ,'▃' ,'▄' ,'▅' ,'▆', '▇'],' ','|',),
             barlen=10)
```

might show the progress bar as:

```
Progress:  34%|███▃      |  ETA: 0:00:02
```

where the last bar is not yet fully filled.

### Progress meters for tasks with a target threshold

Some tasks only terminate when some criterion is satisfied, for
example to achieve convergence within a specified tolerance.  In such
circumstances, you can use the `ProgressThresh` type:

```julia
prog = ProgressThresh(1e-5; desc="Minimizing:")
for val in exp10.(range(2, stop=-6, length=20))
    update!(prog, val)
    sleep(0.1)
end
```

### Progress meters for tasks with an unknown number of steps

Some tasks only terminate when some non-deterministic criterion is satisfied. In such
circumstances, you can use the `ProgressUnknown` type:

```julia
prog = ProgressUnknown(desc="Titles read:")
for val in ["a" , "b", "c", "d"]
    next!(prog)
    if val == "c"
        finish!(prog)
        break
    end
    sleep(0.1)
end
```

This will display the number of calls to `next!` until `finish!` is called.

If your counter does not monotonically increases, you can also set the counter by hand.

```julia
prog = ProgressUnknown(desc="Total length of characters read:")
total_length_characters = 0
for val in ["aaa" , "bb", "c", "d"]
    global total_length_characters += length(val)
    update!(prog, total_length_characters)
    if val == "c"
        finish!(prog)
        break
    end
    sleep(0.5)
end
```

Alternatively, you can display a "spinning ball" symbol
by passing `spinner=true` to the `ProgressUnknown` constructor.
```julia
prog = ProgressUnknown(desc="Working hard:", spinner=true)
while true
    next!(prog)
    rand(1:2*10^8) == 1 && break
end
ProgressMeter.finish!(prog)
```

By default, `finish!` changes the spinner to a `✓`, but you can
use a different character by passing a `spinner` keyword
to `finish!`, e.g. passing `spinner='✗'` on a failure condition:
```julia
let found=false
    prog = ProgressUnknown(desc="Searching for the Answer:", spinner=true)
    for tries in 1:10^8
        next!(prog)
        if rand(1:2*10^8) == 42
            found=true
            break
        end
    end
    finish!(prog, spinner = found ? '✓' : '✗')
end
```

In fact, you can completely customize the spinner character
by passing a string (or array of characters) to animate as a `spinner`
argument to `next!`:
```julia
prog = ProgressUnknown(desc="Burning the midnight oil:", spinner=true)
while true
    next!(prog, spinner="🌑🌒🌓🌔🌕🌖🌗🌘")
    rand(1:10^8) == 0xB00 && break
end
finish!(prog)
```
(Other interesting-looking spinners include `"⌜⌝⌟⌞"`, `"⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"`, `"🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛"`, `"▖▘▝▗'"`, and `"▁▂▃▄▅▆▇█"`.)

### Printing additional information

You can also print and update information related to the computation by using
the `showvalues` keyword. The following example displays the iteration counter
and the value of a dummy variable `x` below the progress meter:

```julia
x,n = 1,10
p = Progress(n)
for iter in 1:10
    x *= 2
    sleep(0.5)
    next!(p; showvalues = [(:iter,iter), (:x,x)])
end
```

In the above example, the data passed to `showvalues` is evaluated even if the progress bar is not updated.
To avoid this unnecessary computation and reduce the overhead,
you can alternatively pass a zero-argument function as a callback to the `showvalues` keyword.

```julia
x,n = 1,10
p = Progress(n)
generate_showvalues(iter, x) = () -> [(:iter,iter), (:x,x)]
for iter in 1:10
    x *= 2
    sleep(0.5)
# unlike `showvalues=generate_showvalues(iter, x)()`, this version only evaluate the function when necessary
next!(p; showvalues = generate_showvalues(iter, x))
end
```

### Showing average time per iteration

You can include an average per-iteration duration in your progress meter
by setting the optional keyword argument `showspeed=true`
when constructing a `Progress`, `ProgressUnknown`, or `ProgressThresh`.

```julia
x,n = 1,10
p = Progress(n; showspeed=true)
for iter in 1:10
    x *= 2
    sleep(0.5)
    next!(p; showvalues = [(:iter,iter), (:x,x)])
end
```

will yield something like:

```
Progress:  XX%|███████████████████████████           |  ETA: XX:YY:ZZ (12.34  s/it)
```

instead of

```
Progress:  XX%|███████████████████████████                         |  ETA: XX:YY:ZZ
```

### Conditionally disabling a progress meter

In addition to the `showspeed` optional keyword argument,
all the progress meters also support the optional `enabled` keyword argument.
You can use this to conditionally disable a progress bar in cases where you want less verbose output
or are using another progress bar to track progress in looping over a function that itself uses a progress bar.

```julia
function my_awesome_slow_loop(n::Integer; show_progress=true)
    p = Progress(n; enabled=show_progress)
    for i in 1:n
        sleep(0.1)
        next!(p)
    end
end

const SHOW_PROGRESS_BARS = parse(Bool, get(ENV, "PROGRESS_BARS", "true"))

m = 100
# let environment variable disable outer loop progress bar
p = Progress(m; enabled=SHOW_PROGRESS_BARS)
for i in 1:m
    # disable inner loop progress bar since we are tracking progress in the outer loop
    my_awesome_slow_loop(i; show_progress=false)
    next!(p)
end
```

### ProgressMeter with additional information in Jupyter

Jupyter notebooks/lab does not allow one to overwrite only parts of the output of cell.
In releases up through 1.2, progress bars are printed repeatedly to the output.
Starting with release xx, by default Jupyter clears the output of a cell, but this will
remove **all** output from the cell. You can restore previous behavior by calling
`ProgressMeter.ijulia_behavior(:append)`. You can enable it again by calling `ProgressMeter.ijulia_behavior(:clear)`,
which will also disable the warning message.

### Tips for parallel programming

For remote parallelization, when multiple processes or tasks are being used for a computation,
the workers should communicate back to a single task for displaying the progress bar. This
can be accomplished with a `RemoteChannel`:

```julia
using ProgressMeter
using Distributed

n_steps = 20
p = Progress(n_steps)
channel = RemoteChannel(() -> Channel{Bool}(), 1)

# introduce a long-running dummy task to all workers
@everywhere long_task() = sum([ 1/x for x in 1:100_000_000 ])
@time long_task() # a single execution is about 0.3 seconds

@sync begin # start two tasks which will be synced in the very end
    # the first task updates the progress bar
    @async while take!(channel)
        next!(p)
    end

    # the second task does the computation
    @async begin
        @distributed (+) for i in 1:n_steps
            long_task()
            put!(channel, true) # trigger a progress bar update
            i^2
        end
        put!(channel, false) # this tells the printing task to finish
    end
end
```

Here, returning some number `i^2` and reducing it somehow `(+)`
is necessary to make the distribution happen.

### `progress_map`

More control over the progress bar in a map function can be achieved with the `progress_map`
and `progress_pmap` functions. The keyword argument `progress` can be used to supply a custom progress meter.

```julia
p = Progress(10, barglyphs=BarGlyphs("[=> ]"))
progress_map(1:10, progress=p) do x
    sleep(0.1)
    x^2
end
```

### Optional use of the progress meter

It possible to disable the progress meter when the use is optional.

```julia
x, n = 1, 10
p = Progress(n; enabled = false)
for iter in 1:10
    x *= 2
    sleep(0.5)
    ProgressMeter.next!(p)
end
```

In cases where the output is text output such as CI or in an HPC scheduler, the helper function
`is_logging` can be used to disable automatically.

```julia
is_logging(io) = isa(io, Base.TTY) == false || (get(ENV, "CI", nothing) == "true")
p = Progress(n; output = stderr, enabled = !is_logging(stderr))
```

### Adding support for more map-like functions

To add support for other functions, `ProgressMeter.ncalls` must be defined,
where `ncalls_map`, `ncalls_broadcast`, `ncalls_broadcast!` or `ncalls_reduce` can help

For example, with `tmap` from [`ThreadTools.jl`](https://github.com/baggepinnen/ThreadTools.jl):

```julia
using ThreadTools, ProgressMeter

ProgressMeter.ncalls(::typeof(tmap), ::Function, args...) = ProgressMeter.ncalls_map(args...)
ProgressMeter.ncalls(::typeof(tmap), ::Function, ::Int, args...) = ProgressMeter.ncalls_map(args...)

@showprogress tmap(abs2, 1:10^5)
@showprogress tmap(abs2, 4, 1:10^5)
```


## Development/debugging tips

When developing or debugging ProgressMeter it is convenient to redirect the output to
another terminal window such that it does not interfer with the Julia REPL window you are
using.

On Linux/macOS you can find the file name corresponding to the other terminal by using the
[`tty`](https://man7.org/linux/man-pages/man1/tty.1.html) command. This file can be `open`ed
and passed as the `output` keyword argument to the
`Progress`/`ProgressThresh`/`ProgressUnknown` constructors.

#### Example

Run `tty` from the other terminal window (the window where we want output to show up):

```
$ tty
/dev/pts/3
```

From the Julia REPL, open the file for writing, wrap in `IOContext` (to enable color), and
pass to the `Progress` constructor:

```julia
io = open("/dev/pts/3", "w")
ioc = IOContext(io, :color => true)
prog = Progress(10; output = ioc)
```

Output from `prog` will now print in the other terminal window when executing `update!`,
`next!`, etc.


## Credits

Thanks to Alan Bahm, Andrew Burroughs, and Jim Garrison for major enhancements to this package.
