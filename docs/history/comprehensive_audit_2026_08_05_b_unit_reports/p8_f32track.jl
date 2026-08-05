include("/cfs/ad/dxu/Library/Julia/Octopus/src/Octopus.jl")
using .Octopus
const O = Octopus
u32 = (4.0f-4, 1.0f-4, -2.0f-4, -1.5f-4, 1.2f-3, 2.0f-4)
for (nm, sp) in (
  ("Patch",     O.PatchSpec(dz=0.2f0, angle_y=0.01f0)),
  ("RFCavity",  O.ThinRFCavitySpec(4.008f8; strength=1f-4, beta0=0.99f0, gamma0=100f0, phase=0f0, L=0f0)),
  ("ChromKick", O.ChromaticityKickSpec{Float32}(; xi=(1.2f0,-0.8f0), beta=(0.82f0,0.075f0))),
  ("CrabCav",   O.ThinCrabCavitySpec{2}(1.97f8; strengthX=(1f-5,-2f-6))),
  ("Boost",     O.LorentzBoostSpec(0.0125f0)))
    rt = O.compile_runtime(sp)
    out = rt(u32...)
    println(rpad(nm,10), " runtime ", rpad(string(typeof(rt)),58),
            " Float32 in -> out eltypes ", unique(map(typeof, out)))
end
