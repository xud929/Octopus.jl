# Twiss / dispersion route dump: the per-route data behind the (I1) route acceptance floor of
# src/analysis/dispersion_routes.jl (`_kappa_route`, re-derived 2026-09-14; stage 7 carried items 6/12 of the
# Twiss/dispersion campaign). Purpose: one TSV row per FORMED dispersion route over the identity contract's 6x6 matrix
# fixtures (the 200 dense maps; the tuple and BeamLine fixtures F1-F5, the 20 dense 4x4 maps and the coasting map F8
# add no row) plus the suite's weak-cavity map, through `analyze` with the default scaling (:auto), so that the ratio
# normalized / (eps kappa_route) of every accepted and rejected graph can be read in both CPU arms and the floor's
# window recomputed offline (the stage 4a driver validation/twiss_dispersion_acceptance_windows.jl measures the window
# itself; this dump is the raw material).
# Usage, from the repository root (the arm is whatever OPENBLAS_CORETYPE / -C the caller sets):
#   julia --startup-file=no --project=. --threads=4 validation/twiss_dispersion_route_dump.jl OUT.tsv
# Columns (tab separated, one header line):
#   fixture        the contract's fixture name (produced by the fixture builder, never typed here)
#   route          :eigenplane | :polynomial | :projector | :newton | :fixed_point
#   primary        1 when the route is the report's primary route
#   status         the route's status (:none = accepted; :not_invariant, :graph_isotropic, ...)
#   converged      1 when the route's iteration reached its stop floor (direct routes: 1)
#   iterations     the iteration count (direct routes: 0)
#   normalized     the route's normalized (I1) residual as REPORTED by the route
#   raw            the route's raw (I1) residual ||F(D)||_F
#   nA, nMrl, nB   the three normalizer terms ||M_rr D||_F, ||M_rl||_F, ||D (M_lr D + M_ll)||_F on the scaled matrix
#   nMs_F, nMs_2   ||M_s||_F and ||M_s||_2 of the scaled matrix the routes ran on (result.matrix_scaled)
#   nD_F, nD_2     ||D||_F and ||D||_2 of the route's graph
#   cc             the route's reported coefficient_condition (its amplification factor; NaN when unavailable)
#   trace_residual tr(M_lr D + M_ll) - tau_s of the graph (NaN when unavailable)
#   area           the canonical area 1 + D1' S_4 D2 (NaN when unavailable)
#   tune1..tune3   the physical tunes (NaN padded)
#   result_status  the analysis verdict (:passed | :degraded | :failed)
#   recomputed_normalized   _graph_invariance_residual(M_s, D).normalized recomputed here (must equal `normalized`)
#   kappa_route    Octopus._kappa_route(M_s, D, cc) on the SAME matrix the routes ran on with the route's reported
#                  condition (unavailable -> 1), the kappa of the kernel's floor
#   ratio          normalized / (eps kappa_route): the multiplier-1 ratio of the route against its own floor (a :none
#                  row sits below _ROUTE_INVARIANCE_MULTIPLIER; a graph this floor rejected sits above it, while a
#                  converged iterate the trace-residual branch check rejected can sit below it)
using Octopus, LinearAlgebra, Printf
const O = Octopus
dv(x) = O.determined_value(x)
c = TwissDispersionIdentityContract(dense_maps=200, dense_maps_4d=20)
fx = collect(O._identity_contract_fixtures(c))
co = O._identity_contract_coasting(c.seed)
Mc = O._identity_contract_mcal(zeros(4), co.eta)
weak = Mc * O._identity_contract_blockdiag(co.A4, [1.0 0.7; -1e-6 1 - 0.7e-6]) * O._symplectic_inverse(Mc)
push!(fx, (name="D12 weak cavity (M[6,5] = -1e-6 folded, shear 0.7)", input=weak,
           analysis=TwissDispersionAnalysis(strict=false, emittances=c.emittances, dispersion_routes=(:eigenplane, :polynomial, :projector, :newton, :fixed_point)), kind=:weak))
out = open(ARGS[1], "w")
println(out, join(["fixture", "route", "primary", "status", "converged", "iterations", "normalized", "raw", "nA", "nMrl", "nB", "nMs_F", "nMs_2",
                   "nD_F", "nD_2", "cc", "trace_residual", "area", "tune1", "tune2", "tune3", "result_status", "recomputed_normalized",
                   "kappa_route", "ratio"], "\t"))
n = 0
for f in fx
    x = f.input
    (x isa AbstractMatrix && size(x) == (6, 6)) || continue
    a = f.analysis isa TwissDispersionAnalysis ? f.analysis : TwissDispersionAnalysis(strict=false, emittances=c.emittances)
    r = try analyze(a, x) catch err; println(stderr, "THREW ", f.name, " ", typeof(err)); nothing end
    r === nothing && continue
    r.dispersion === nothing && continue
    Ms = r.matrix_scaled
    Mrr = Ms[1:4, 1:4]; Mrl = Ms[1:4, 5:6]; Mlr = Ms[5:6, 1:4]; Mll = Ms[5:6, 5:6]
    tu = r.physical.tunes
    tunes = length(tu) == 3 ? tu : vcat(tu, fill(NaN, 3 - length(tu)))
    for rt in r.dispersion.routes
        rt.status === :route_not_selected && continue
        O.is_determined(rt.graph) || continue
        D = dv(rt.graph)
        A = Mrr * D; B = D * (Mlr * D + Mll)
        res = O.is_determined(rt.invariance_residual) ? dv(rt.invariance_residual) : (normalized=NaN, raw=NaN)
        rec = O._graph_invariance_residual(Ms, D).normalized
        cc = O.is_determined(rt.coefficient_condition) ? dv(rt.coefficient_condition) : NaN
        tr_res = O.is_determined(rt.trace_residual) ? dv(rt.trace_residual) : NaN
        area = O.is_determined(rt.canonical_area) ? dv(rt.canonical_area) : NaN
        # the kernel's kappa: the scaled matrix the routes ran on, the route's graph, its reported condition (unavailable -> 1)
        kr = O._kappa_route(Ms, D, rt.coefficient_condition)
        ratio = res.normalized / (eps(Float64) * kr)
        @printf(out, "%s\t%s\t%d\t%s\t%d\t%d\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%.6e\t%s\t%.6e\t%.6e\t%.6e\n",
                f.name, rt.route, rt.route === r.dispersion.primary ? 1 : 0, rt.status, rt.converged ? 1 : 0, rt.iterations, res.normalized, res.raw,
                norm(A), norm(Mrl), norm(B), norm(Ms), opnorm(Ms), norm(D), opnorm(D), cc, tr_res, area, tunes[1], tunes[2], tunes[3], r.status, rec, kr, ratio)
        global n += 1
    end
end
close(out)
println("wrote ", ARGS[1], ": ", n, " route rows over ", length(fx), " fixtures; arm ", get(ENV, "OPENBLAS_CORETYPE", "native"), " host ", Sys.CPU_NAME)
