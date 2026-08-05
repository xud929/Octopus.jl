# U10 probe 5 (hypothesis d): silent option drops.
#  (1) Run the repository's own SolverOptionEffectivenessContract and print the
#      GaussianPICPoissonSolver rows.
#  (2) Independently: derive the option list from solver_option_schema (NOT a
#      hand list) and grep the two region files + the shared PIC helpers for a
#      read of each field, so an option that the contract exempts is still
#      accounted for.
using Octopus
const O = Octopus
using Printf

println("################ declared schema (derived, not hand-copied) ################")
schema = O.solver_option_schema(GaussianPICPoissonSolver)
names = collect(keys(schema))
@printf("%d declared options\n", length(names))
println(join(sort(String.(names)), ", "))

println()
println("################ solver_configuration keys ################")
s = GaussianPICPoissonSolver(grid=(24, 24))
conf = O.solver_configuration(s)
missing_from_conf = setdiff(Set(names), Set(keys(conf)))
extra_in_conf = setdiff(Set(keys(conf)), Set(names))
println("declared but absent from solver_configuration: ", collect(missing_from_conf))
println("in solver_configuration but not declared:      ", collect(extra_in_conf))

println()
println("################ configuration_report coverage ################")
rep = O.configuration_report(s)
repnames = Set(e.name for e in rep)
println("declared but absent from configuration_report: ", collect(setdiff(Set(names), repnames)))
println("statuses:")
for e in rep
    @printf("  %-32s %-22s %s\n", e.name, e.status, e.consumer)
end

println()
println("################ SolverOptionEffectivenessContract ################")
res = validate(SolverOptionEffectivenessContract())
println("overall status: ", res.status)
println("message: ", res.message)
for d in res.details
    sd = string(d)
    (occursin("GaussianPIC", sd) || occursin("gaussian_pic", sd)) && println("  ", sd)
end
