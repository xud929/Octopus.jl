include("/cfs/ad/dxu/Library/Julia/Octopus/src/Octopus.jl")
using .Octopus
const O = Octopus
println("RF, phase/L left at their Int64 defaults : ",
  typeof(O.compile_runtime(O.ThinRFCavitySpec(4.008f8; strength=1f-4, beta0=0.99f0, gamma0=100f0))))
println("RF, phase=0f0, L=0f0 given explicitly    : ",
  typeof(O.compile_runtime(O.ThinRFCavitySpec(4.008f8; strength=1f-4, beta0=0.99f0, gamma0=100f0, phase=0f0, L=0f0))))
println("  promote_type(Float32, Int64)           = ", promote_type(Float32, Int64))
println("Patch, all params Float32                : ",
  typeof(O.compile_runtime(O.PatchSpec(dx=0.01f0, dy=0.0f0, dz=0.2f0, angle_x=0.0f0, angle_y=0.01f0, angle_s=0.0f0, t_offset=0.0f0))))
println("  (patch.jl promotes with an explicit Float64 in the list)")
