include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
println("CUDA_TESTS_ACTIVE = ", CUDA_TESTS_ACTIVE)
ts = @testset "REGION-CUDA-BLOCK" begin
    include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/cuda_block.jl")
end
