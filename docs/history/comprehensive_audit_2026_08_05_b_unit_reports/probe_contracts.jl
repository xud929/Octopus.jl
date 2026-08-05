using Octopus
using Test

println("=== ElementParameterEffectivenessContract ===")
r = validate(ElementParameterEffectivenessContract())
println("status = ", r.status)
println("metrics = ", r.metrics)
println("message = ", r.message)

println("\n--- negative control (empty inactive allowlist) ---")
bad = ElementParameterEffectivenessContract(
    inactive=empty(Octopus.DEFAULT_INACTIVE_ELEMENT_PARAMS))
rb = validate(bad)
println("status = ", rb.status)
println("message = ", rb.message)
println("occursin drift.nst = ", occursin("drift.nst", rb.message))
println("metrics = ", rb.metrics)

println("\n=== PTCConsistencyContract ===")
rp = validate(PTCConsistencyContract())
println("status = ", rp.status)
println("cases metric = ", rp.metrics[:cases],
        "  n_specs = ", length(Octopus._ptc_reference_specs()),
        "  rows = ", rp.metrics[:rows])
println("max_deviation = ", rp.metrics[:max_deviation])

println("\n=== SolverOptionEffectivenessContract ===")
rs = validate(SolverOptionEffectivenessContract())
println("status = ", rs.status)
println("metrics = ", rs.metrics)
