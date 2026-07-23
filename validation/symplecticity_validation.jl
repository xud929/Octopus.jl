#=
Finite-difference symplecticity validation for Octopus six-dimensional maps.

Run from the project root:

    julia --project=. validation/symplecticity_validation.jl

Controls:

    OCTOPUS_SYMPLECTICITY_STEP=3e-7
    OCTOPUS_SYMPLECTICITY_TOL=5e-7

The script checks runtime maps that are registered as `Symplectic6DMap` plus
the weak-strong beam-beam maps that are intended to be six-dimensional
symplectic. Stochastic radiation maps are intentionally excluded. Hirata's
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
const DEFAULT_TOL = parse(Float64, get(ENV, "OCTOPUS_SYMPLECTICITY_TOL", "5e-7"))

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

function symplecticity_cases()
    linear = Linear6D(Linear6DSpec{Float64}(;
        beta1=(0.8, 0.072, 90.0),
        beta2=(0.82, 0.075, 91.0),
        alpha1=(0.0, 0.0, 0.0),
        alpha2=(0.01, -0.02, 0.0),
        dmu=(0.08, 0.12, 0.02),
        zeta1=(0.002, -0.001, 0.0, 0.0),
        eta1=(0.001, 0.0, -0.001, 0.0),
        R1=(0.001, -0.0005, 0.0003, 0.0007),
        zeta2=(0.001, 0.0005, -0.0003, 0.0002),
        eta2=(-0.0004, 0.0001, 0.0002, -0.0001),
        R2=(0.0006, 0.0002, -0.0001, 0.0005),
    ))
    covariance = [
        1.21e-8   1.0e-9   2.4e-9  -3.0e-10
        1.0e-9    4.0e-8   2.0e-10  1.5e-9
        2.4e-9    2.0e-10  6.4e-9  -6.0e-10
       -3.0e-10   1.5e-9  -6.0e-10  2.25e-8
    ]
    thin = ThinStrongBeam(ThinStrongBeamSpec{Float64}(;
        kbb=1.0e-8,
        covariance=covariance,
        center=(2.0e-5, -1.0e-5, 3.0e-4),
        angle=(3.0e-4, -2.0e-4, 0.0),
        virtual_drift=:hirata,
    ))
    gaussian = GaussianStrongBeam(GaussianStrongBeamSpec{Float64}(;
        thin=ThinStrongBeamSpec{Float64}(;
            kbb=8.0e-9,
            covariance=covariance,
            center=(-1.0e-5, 2.0e-5, -2.0e-4),
            angle=(2.0e-4, -1.0e-4, 0.0),
            virtual_drift=:hirata,
        ),
        ns=3,
        sigz=7.0e-3,
        slice_method=:equal_area,
    ))
    q0 = [4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4]
    return (
        (name=:Linear6D, element=linear, q0=q0, tolerance=5.0e-8),
        (name=:CrabDispersion, element=CrabDispersion(CrabDispersionSpec{Float64}(zeta1=0.02, zeta2=-0.01, zeta3=0.004, zeta4=0.002)), q0=q0, tolerance=5.0e-8),
        (name=:MomentumDispersion, element=MomentumDispersion(MomentumDispersionSpec{Float64}(eta1=0.03, eta2=-0.006, eta3=0.002, eta4=0.01)), q0=q0, tolerance=5.0e-8),
        (name=:XYCoupling, element=XYCoupling(0.01, -0.003, 0.002, 0.004), q0=q0, tolerance=5.0e-8),
        (name=:ThinCrabCavity, element=ThinCrabCavity{2}(197.0e6; strengthX=(1.0e-5, -2.0e-6), strengthY=(3.0e-6, 0.0), phase=(0.0, 0.2)), q0=q0, tolerance=5.0e-7),
        (name=:ChromaticityKick, element=ChromaticityKick(ChromaticityKickSpec{Float64}(; xi=(1.2, -0.8), beta=(0.82, 0.075), alpha=(0.01, -0.02), zeta=(0.002, -0.001, 0.0, 0.0), eta=(0.001, 0.0, -0.001, 0.0), R=(0.001, -0.0005, 0.0003, 0.0007))), q0=q0, tolerance=5.0e-6),
        (name=:ThinStrongBeam, element=thin, q0=q0, tolerance=5.0e-7),
        (name=:GaussianStrongBeam, element=gaussian, q0=q0, tolerance=5.0e-7),
    )
end

function run_lorentz_quasisymplectic_validation(; angle=0.01,
                                                  step=DEFAULT_STEP,
                                                  inverse_tolerance=1.0e-10,
                                                  determinant_tolerance=2.0e-7)
    q0 = [4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4]
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

if abspath(PROGRAM_FILE) == @__FILE__
    results = run_symplecticity_validation()
    print_symplecticity_results(results)
    all(result -> result.passed, results) ||
        error("one or more symplecticity checks failed")
    lorentz = run_lorentz_quasisymplectic_validation()
    print_lorentz_quasisymplectic_result(lorentz)
    lorentz.inverse_passed && lorentz.determinant_passed ||
        error("Lorentz quasi-symplectic check failed")
end
