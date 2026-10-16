using Test
using ProgressMeter
using IJulia

# `using IJulia` loaded the extension, which registered its backend
ext = Base.get_extension(ProgressMeter, :ProgressMeterIJuliaExt)
@test ext !== nothing
backend = ProgressMeter.IJULIA_BACKEND[]
@test backend isa ext.WithIJulia
@test ProgressMeter.ijulia_loaded(backend)
@test hasmethod(ProgressMeter.ijulia_clear_output, Tuple{ext.WithIJulia})

# no kernel runs under Pkg.test, so meters behave as in a plain terminal
@test !IJulia.inited
@test !ProgressMeter.running_ijulia_kernel()
@test !ProgressMeter.clear_ijulia()
# the #76 workaround fires only inside a kernel:  outside one, `reset_stdio_count`
# would dereference the absent default kernel
@test ProgressMeter.ijulia_reset_stdio(backend) === nothing

# stand in for a running kernel:  `Kernel()` opens no sockets, and setting its
# `inited` mirrors into `IJulia.inited`, which is what the hooks read
if pkgversion(IJulia) >= v"1.30"
    kernel = IJulia.Kernel()
    setglobal!(IJulia, :_default_kernel, kernel)
    kernel.inited = true
    behavior = ProgressMeter.IJULIABEHAVIOR[]   # earlier tests may have changed it
    try
        @test ProgressMeter.running_ijulia_kernel()
        ProgressMeter.ijulia_behavior(:clear)
        @test ProgressMeter.clear_ijulia()
        ProgressMeter.ijulia_behavior(:append)   # opts out of clearing the cell
        @test !ProgressMeter.clear_ijulia()
        # the #76 workaround resets the kernel's output byte count after every printover
        kernel.stdio_bytes = 100
        ProgressMeter.ijulia_reset_stdio(backend)
        @test kernel.stdio_bytes == 0
        kernel.stdio_bytes = 100
        ProgressMeter.printover(IOBuffer(), "msg")
        @test kernel.stdio_bytes == 0
    finally
        kernel.inited = false
        setglobal!(IJulia, :_default_kernel, nothing)
        ProgressMeter.IJULIABEHAVIOR[] = behavior
    end
end

# with IJulia loaded, `printover` leaves out the line clear, as it did before the extension
let io = IOBuffer()
    ProgressMeter.printover(io, "msg")
    @test String(take!(io)) == "\rmsg"
end

# a meter still renders in full
let io = IOBuffer()
    p = Progress(3; output=io, dt=0)
    for i in 1:3
        update!(p, i; force=true)
    end
    @test occursin("100%", String(take!(io)))
end
