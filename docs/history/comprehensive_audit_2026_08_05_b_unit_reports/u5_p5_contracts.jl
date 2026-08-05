using Octopus
const O = Octopus
println("CUDA functional: ", O._HAS_CUDA)
for C in (O.PublicConfigurationEffectivenessContract, O.SolverOptionEffectivenessContract)
    t = @elapsed r = validate(C())
    println("=== ", nameof(C), " status=", r.status, " (", round(t; digits=1), " s)")
    println("    ", r.message)
end
