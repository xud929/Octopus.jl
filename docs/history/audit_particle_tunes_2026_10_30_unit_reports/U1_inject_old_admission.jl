# Isolated negative control: restore the reviewed pre-fix admission method
# inside this Julia process only. Production source files remain unchanged.
using Octopus
Base.include_string(Octopus, read(joinpath(@__DIR__, "U1_old_admission.jl"), String),
                    "injected_pre_fix_particle_tune_admission.jl")
