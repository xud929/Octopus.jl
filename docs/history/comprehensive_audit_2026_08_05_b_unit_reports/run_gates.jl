include("/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/prelude.jl")
const D = "/tmp/claude-320114/-cfs-ad-dxu/37c712a3-734a-4817-a05e-4c9e12cabcef/scratchpad/audit/"
println("CUDA_TESTS_ACTIVE = ", CUDA_TESTS_ACTIVE)
for f in ("ts_gpic_coupled_cuda.jl", "ts_greencache_slicepair.jl", "ts_pic_timing.jl",
          "ts_pic_parity_routes.jl", "ts_lattice.jl")
    include(D * f)
end
