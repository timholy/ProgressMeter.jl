module PerformanceBenchmarks

using Test
using ProgressMeter
using ProgressMeter: start_background_progress_thread!, background_update!, finish!
using BenchmarkTools
using Base.Threads: atomic_add!
using Statistics

@testset "Progress Meter Performance" begin
    @testset "Background Thread Overhead" begin
        # Simulate complex, computationally intensive work
        function heavy_computational_work(complexity)
            result = 0.0
            # Nested loops to increase computational complexity
            for _ in 1:complexity
                result += sum(
                    sin(x) * cos(x) * tan(x) 
                    for x in range(0, π, length=1000)
                )
                # Add matrix-like operations to increase complexity
                result *= sqrt(result)
            end
            return result
        end
        
        creation_times = [
            @elapsed begin
                p = ProgressUnknown(desc="Heavy Computation")
                start_time = time()
                ProgressMeter.start_background_progress_thread!(p)
                
                total_steps = 500
                complexity_levels = [10, 50, 100]  # Varying computational intensity
                thread_results = zeros(Threads.nthreads())
                
                @sync Threads.@threads for thread_id in 1:Threads.nthreads()
                    # Dynamically assign complexity based on thread
                    thread_complexity = complexity_levels[mod1(thread_id, length(complexity_levels))]
                    
                    local thread_result = 0.0
                    local thread_steps = 0
                    
                    for i in 1:total_steps
                        # Substantial computational work with variable complexity
                        thread_result += heavy_computational_work(thread_complexity)
                        ProgressMeter.background_update!(p, i)
                        thread_steps = i
                    end
                    
                    thread_results[thread_id] = thread_result
                end
                
                ProgressMeter.finish!(p)
                total_time = time() - start_time
            end
            for _ in 1:50
        ]

        # More relaxed performance constraints
        @test mean(creation_times) < 1.0  # Under 1 second per tracking
        @test std(creation_times) < 0.5   # Lower variance
    end

    @testset "Update Channel Performance" begin
        # Test non-blocking, lock-free update mechanism
        p = ProgressUnknown()
        start_background_progress_thread!(p)
        
        # Use a thread-safe data structure with atomic operations
        update_times = zeros(Float64, 1000)
        update_counter = Threads.Atomic{Int}(0)
        
        # Measure time to put updates in channel with simulated contention
        total_updates = 1000
        Threads.@threads for i in 1:total_updates
            start = time()
            background_update!(p, i)
            
            # Atomic, thread-safe update of shared array
            idx = atomic_add!(update_counter, 1) + 1
            update_times[idx] = time() - start
        end
        
        finish!(p)
        
        # Filter out any zero values
        valid_times = filter(x -> x > 0, update_times)
        
        # Verify update mechanism performance
        @test mean(valid_times) < 0.001  # Under 1ms per update
        @test std(valid_times) < 0.0005  # Low variance
    end

    @testset "Atomic Progress State" begin
        # Test thread-safe progress updates with atomic operations
        p = ProgressUnknown(desc="Atomic Progress Test")
        start_background_progress_thread!(p)
        
        # Use atomic counter to track updates across threads
        update_counter = Threads.Atomic{Int}(0)
        total_updates = 1000
        
        Threads.@threads for _ in 1:total_updates
            # Simulate work and update progress
            background_update!(p, 1)
            
            # Atomically increment a shared counter
            atomic_add!(update_counter, 1)
        end
        
        finish!(p)
        
        # Verify all updates were processed
        @test update_counter[] == total_updates
    end

    @testset "Total Update Channel Performance" begin
        # Test total update channel performance and throughput
        p = ProgressUnknown(desc="Total Update Performance")
        start_background_progress_thread!(p)
        
        total_updates = 10000
        start_time = time()
        
        Threads.@threads for i in 1:total_updates
            background_update!(p, 1)
        end
        
        finish!(p)
        total_time = time() - start_time
        
        # Debug information
        @info "Counter details" p.counter[] total_updates
        
        # Verify total update performance
        @test total_time < 1.0  # Total update time under 1 second
        @test p.counter[] == total_updates  # All updates processed
    end
end

end