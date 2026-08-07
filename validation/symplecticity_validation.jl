#=
Finite-difference symplecticity validation for Octopus six-dimensional maps.

Run from the project root:

    julia --project=. validation/symplecticity_validation.jl

Controls:

    OCTOPUS_SYMPLECTICITY_STEP=3e-7
    OCTOPUS_SYMPLECTICITY_TOL=5e-8

The script checks the 12 cases `SymplecticityContract` declares -- it derives
that list rather than copying it -- which covers 7 of the 22 registered kinds
whose metadata declares `Symplectic6DMap`, plus the weak-strong beam-beam maps
and the Lorentz pair. It is NOT a sweep of every symplectic runtime map: the
whole thick lattice-magnet family (drift, quadrupole, sextupole, octupole,
multipole, sbend), the thin kickers and multipoles, the marker and the thin RF
cavity have no case here. The lattice magnets are covered against PTC instead,
which is a different claim (agreement with an external code, not
||J'SJ - S|| <= tol); the thin kickers, marker and RF cavity are covered by
neither. Counted, not assumed (2026-08-05_b audit, U24-3); this paragraph
previously read "checks runtime maps that are registered as `Symplectic6DMap`",
which a reader reasonably took as all of them. Stochastic radiation maps are intentionally excluded. Hirata's
crossing-angle Lorentz maps are reported separately: they are exact inverse
coordinate transformations, but only *quasi*-symplectic in accelerator
coordinates. Their determinants are `sec(angle)^3` and `cos(angle)^3`, so
they must not be judged by `J' * S * J == S`.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using LinearAlgebra

const DEFAULT_STEP = parse(Float64, get(ENV, "OCTOPUS_SYMPLECTICITY_STEP", "3e-7"))
# A floor, applied as `max(case.tolerance, default_tolerance)` below, so raising
# it relaxes every case at once. It must sit at or below the tightest per-case
# tolerance or that case's declared value never binds: at the former 5e-7 the
# four 5e-8 linear-map cases were judged ten times looser than they declare,
# against measured residuals of ~1.5e-13. Kept equal to the
# SymplecticityContract floor so the two stay mirrors of each other.
const DEFAULT_TOL = parse(Float64, get(ENV, "OCTOPUS_SYMPLECTICITY_TOL", "1e-11"))

function symplectic_form6(::Type{T}=Float64) where {T}
    S = zeros(T, 6, 6)
    for coordinate in (1, 3, 5)
        S[coordinate, coordinate + 1] = one(T)
        S[coordinate + 1, coordinate] = -one(T)
    end
    return S
end

function finite_difference_jacobian6(map, q0; step=DEFAULT_STEP)
    q = collect(Float64, q0)
    jacobian = Matrix{Float64}(undef, 6, 6)
    for column in 1:6
        h = step * max(abs(q[column]), 1.0)
        dq = zeros(Float64, 6)
        dq[column] = h
        plus = collect(Float64, map(q .+ dq))
        minus = collect(Float64, map(q .- dq))
        jacobian[:, column] .= (plus .- minus) ./ (2h)
    end
    return jacobian
end

function symplecticity_residual(map, q0; step=DEFAULT_STEP)
    J = finite_difference_jacobian6(map, q0; step=step)
    S = symplectic_form6(Float64)
    return norm(transpose(J) * S * J - S, Inf)
end

function jacobian_determinant(map, q0; step=DEFAULT_STEP)
    return det(finite_difference_jacobian6(map, q0; step=step))
end

function map_inverse_residual(forward, reverse, q0)
    forward_q0 = forward(q0...)
    reverse_q0 = reverse(q0...)
    return max(norm(collect(reverse(forward_q0...)) .- q0, Inf),
               norm(collect(forward(reverse_q0...)) .- q0, Inf))
end

# One case list, two independent evaluators (2026-08-05 audit, U21-4). The
# script used to carry its own hand copy of the contract's case list, and
# the copy had gone stale — 8 of the contract's 12 cases, no solenoid, no
# chromatic/exact virtual-drift sweep, no registry tripwire — while both
# sides claimed mirror status of the other. The list now IS the contract's
# (`_symplecticity_contract_cases`, whose validate carries the
# declaration↔case tripwire), so the mirror cannot drift. What stays
# independent here is the EVALUATOR: the finite-difference Jacobian and the
# symplectic form above are written locally, so a defect in the contract's
# own differentiation cannot hide itself.
symplecticity_cases() = Octopus._symplecticity_contract_cases()

# The Lorentz leg's knowledge comes from the contract too (2026-08-05_b audit,
# U24-7). Angle, probe point and both tolerances used to be literals duplicated
# here -- exactly the pattern the case-list repair above removed one function
# up. They agreed; nothing made them agree tomorrow, and nothing would have
# reported the divergence. Defaults now read the contract's own fields, which
# became fields precisely so they could be read (U4-16); an explicit argument
# still overrides, which is what a probe of a tightened bound needs.
const _SYMP_CONTRACT_DEFAULTS = SymplecticityContract()

function run_lorentz_quasisymplectic_validation(;
        angle=_SYMP_CONTRACT_DEFAULTS.lorentz_angle,
        step=DEFAULT_STEP,
        inverse_tolerance=_SYMP_CONTRACT_DEFAULTS.lorentz_inverse_tolerance,
        determinant_tolerance=_SYMP_CONTRACT_DEFAULTS.lorentz_determinant_tolerance)
    q0 = copy(Octopus.SYMPLECTICITY_PROBE_POINT)
    forward = LorentzBoost(angle)
    reverse = RevLorentzBoost(angle)
    forward_det = jacobian_determinant(q -> forward(q...), q0; step=step)
    reverse_det = jacobian_determinant(q -> reverse(q...), q0; step=step)
    inverse_residual = map_inverse_residual(forward, reverse, q0)
    expected_forward = sec(angle)^3
    expected_reverse = cos(angle)^3
    return (
        angle=angle,
        forward_det=forward_det,
        reverse_det=reverse_det,
        expected_forward_det=expected_forward,
        expected_reverse_det=expected_reverse,
        inverse_residual=inverse_residual,
        determinant_error=max(abs(forward_det - expected_forward),
                              abs(reverse_det - expected_reverse)),
        inverse_passed=inverse_residual <= inverse_tolerance,
        determinant_passed=max(abs(forward_det - expected_forward),
                               abs(reverse_det - expected_reverse)) <= determinant_tolerance,
    )
end

function run_symplecticity_validation(; step=DEFAULT_STEP, default_tolerance=DEFAULT_TOL)
    results = map(symplecticity_cases()) do case
        residual = symplecticity_residual(q -> case.element(q...), case.q0; step=step)
        tolerance = max(case.tolerance, default_tolerance)
        return (name=case.name, residual=residual, tolerance=tolerance,
                passed=residual <= tolerance)
    end
    return results
end

function print_symplecticity_results(results)
    println("Finite-difference 6D symplecticity validation")
    for result in results
        println("  ", result.name,
                ": residual = ", result.residual,
                ", tolerance = ", result.tolerance,
                ", passed = ", result.passed)
    end
end

function print_lorentz_quasisymplectic_result(result)
    println("Hirata Lorentz quasi-symplectic validation")
    println("  forward determinant = ", result.forward_det,
            " (expected ", result.expected_forward_det, ")")
    println("  reverse determinant = ", result.reverse_det,
            " (expected ", result.expected_reverse_det, ")")
    println("  inverse residual = ", result.inverse_residual)
    println("  determinant error = ", result.determinant_error)
    println("  passed = ", result.inverse_passed && result.determinant_passed)
end

"""
Run the contract's declaration-vs-coverage tripwire and report it.

The case list is derived from `SymplecticityContract` rather than copied, but
deriving it is only half of Measured Lesson 4: the tripwire that catches a
registered kind DECLARING the contract with no case lives in
`validate(::SymplecticityContract)`, and this script never called it. Since this
script is the documented way to check symplecticity after a change
(`validation/README.md`), the check a developer actually ran was the one without
the tripwire (2026-08-05_b audit, U24-5).
"""
function run_symplecticity_coverage()
    r = validate(SymplecticityContract())
    uncovered = get(r.metrics, :kinds_declaring_without_case, nothing)
    println()
    println("Declaration-vs-coverage tripwire (from the contract, not this script):")
    println("  registered kinds declaring SymplecticityContract with no case = ",
            uncovered === nothing ? "<metric absent>" : uncovered)
    return r
end

if abspath(PROGRAM_FILE) == @__FILE__
    results = run_symplecticity_validation()
    print_symplecticity_results(results)
    all(result -> result.passed, results) ||
        error("one or more symplecticity checks failed")
    coverage = run_symplecticity_coverage()
    coverage.passed ||
        error("symplecticity declaration-vs-coverage tripwire failed: " * coverage.message)
    lorentz = run_lorentz_quasisymplectic_validation()
    print_lorentz_quasisymplectic_result(lorentz)
    lorentz.inverse_passed && lorentz.determinant_passed ||
        error("Lorentz quasi-symplectic check failed")
end
