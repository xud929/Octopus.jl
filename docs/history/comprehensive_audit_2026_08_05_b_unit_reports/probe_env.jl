using Octopus, CUDA
println("CUDA functional = ", CUDA.functional())
println("HAS_CUDA = ", Octopus._HAS_CUDA)
b = Beam(1000, CUDABackend, Float64; beta=(0.55,0.056,12.7), alpha=(0.0,0.0,0.0),
         sigma=(106e-6,9.5e-6,0.7e-2), cutoff=5.0, rng_id=1,
         charge=-1.0, mc2=Octopus.EMASS_EV, E0=10e9, r0=Octopus.RE, npart=1.7e11)
println("beam ok ", typeof(b.rep.x))
