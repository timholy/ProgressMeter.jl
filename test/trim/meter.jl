# Smoke test for `juliac --trim=safe`:  a meter that updates and finishes must
# compile with no verifier errors and run without runtime code generation.
# CI builds and runs it from the repository root with
#
#     julia --project=test/trim -e 'using Pkg; Pkg.instantiate()'
#     julia --project=test/trim -e 'using JuliaC; JuliaC.main(ARGS)' -- \
#         --output-exe pmtrim --project=test/trim --experimental --trim=safe test/trim/meter.jl
#     JULIA_LOAD_CODEGEN_LIB=0 ./pmtrim
using ProgressMeter

function @main(args::Vector{String})::Cint
    # `force` prints every frame:  otherwise a frame is skipped while the clock has
    # not moved past the previous one, and a trimmed binary can run the whole loop
    # inside one microsecond, printing nothing at all
    p = Progress(3; output=Core.stderr, dt=0.0)
    for i in 1:3
        update!(p, i; force=true)
    end
    finish!(p)
    return 0
end

Base.Experimental.entrypoint(main, (Vector{String},))
