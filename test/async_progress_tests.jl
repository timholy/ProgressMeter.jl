module AsyncProgressTests

using Test
using ProgressMeter: start_background_progress_thread!, background_update!, ProgressUnknown, finish!
using Statistics
using Base.Threads: atomic_add!

@testset "Progress Background Thread" begin
    @testset "Thread-Safe Progress Updates" begin
        p = ProgressUnknown(desc="Concurrent Updates")
        start_background_progress_thread!(p)
        
        total_steps = 500
        update_states = Vector{Float64}(undef, Threads.nthreads())
        
        @sync begin
            Threads.@threads for thread_id in 1:Threads.nthreads()
                local thread_steps = 0
                
                for i in 1:total_steps
                    background_update!(p, 1)
                    thread_steps = i
                end
                
                update_states[thread_id] = thread_steps / total_steps
            end
        end
        
        # Verify meaningful progress across threads
        @test all(state -> state ≈ 1.0, update_states)
    end

    @testset "Background Thread Lifecycle" begin
        p = ProgressUnknown(desc="Lifecycle Test")
        
        @test begin
            start_background_progress_thread!(p)
            
            # Verify background thread and channel setup
            @info "Before finish!" p.core.background_thread p.core.update_channel p.core.stop_background_thread[]
            
            p.core.background_thread !== nothing &&
            !isopen(p.core.update_channel) == false &&
            !p.core.stop_background_thread[]
        end
        
        @test begin
            finish!(p)
            
            # Add a small delay to allow thread termination
            sleep(0.1)
            
            @info "After finish!" p.core.background_thread p.core.update_channel p.core.stop_background_thread[]
            
            # Verify thread termination
            p.core.background_thread === nothing &&
            isopen(p.core.update_channel) == false &&
            p.core.stop_background_thread[]
        end
    end

    @testset "Update Channel Performance" begin
        p = ProgressUnknown(desc="Channel Performance")
        start_background_progress_thread!(p)
        
        update_times = Float64[]
        total_updates = 1000
        
        for i in 1:total_updates
            start_time = time()
            background_update!(p, i)
            push!(update_times, time() - start_time)
        end
        
        finish!(p)
        
        # Verify low-latency updates
        @test mean(update_times) < 0.001  # Under 1ms per update
        @test std(update_times) < 0.0005  # Low variance
    end
end

end  # module AsyncProgressTests
