#=
Validate the smooth transition between the near-round Gaussian expansion and
the elliptical Bassetti-Erskine evaluator.

Run from the project root:

    julia --project=. validation/near_round_gaussian_transition.jl

Reference model:
    Fixed-interval Gaussian field integrals evaluated with 96-point
    Gauss-Legendre quadrature.

Metrics:
    Pointwise relative force error, relative principal covariance-response
    error, exact core-gradient error, extrapolated value and first-derivative
    gaps at both blend endpoints, six-dimensional symplecticity, and CPU/CUDA
    parity when CUDA is available.

Gated (the run exits 1 naming the metric): the Float64 force and response
relative errors, the observed/nominal conditioning ratio of both types, and
-- since 2026-10-20, comprehensive audit 2026-10-18 F-238 -- the Float64
core-gradient error, the 6D symplectic residual and all eight endpoint
continuity gaps, each against a bound stated with its derivation in the main
block; CPU/CUDA parity when a device is functional, and with
OCTOPUS_REQUIRE_GPU_CONTRACT=1 a missing device fails the run (the one
parser is `Octopus._require_gpu_contract()`). The Float32 errors are
reported. The main block then re-feeds the recorded defect (a x1.1 evaluator
error over a window of the blend) and requires the instrument to see it, in
the gated metric for a mid-blend window and in the continuity gaps for the
two endpoint windows that the sweep's sampling cannot reach (Phase 12 of
docs/comprehensive_audit.md).

Overrides: OCTOPUS_REQUIRE_GPU_CONTRACT (above) and OCTOPUS_NEAR_ROUND_DEFECT
= none (default) | mid | inner_edge | outer_edge, which injects the x1.1
evaluator error into the main sweeps over t in [0.30, 0.40], [0.01, 0.04] or
[0.96, 0.99] so that a gate can be shown red: `mid` fails the Float64 force
gate, the two edges fail the continuity-gap gates and nothing else (the
sweep's sampling does not reach them).

The gate's CUDA arm runs this script with the parity leg required (the
testset "CUDA-requiring validation scripts run in the gate's CUDA arm" in
test/runtests.jl reads the line below; validation/README.md):

GATE-CUDA-ARM: env OCTOPUS_REQUIRE_GPU_CONTRACT=1 ; verdict "CUDA parity Float64: max relative error"

The transition scan uses mean variance s^2 = 1.  Errors are therefore already
in the natural force (1/s) and covariance-response (1/s^2) scales.
=#

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using LinearAlgebra

function _transition_gauss_legendre(n)
    beta = [k / sqrt(4k^2 - 1) for k in 1:(n - 1)]
    quadrature = eigen(SymTridiagonal(zeros(n), beta))
    return (quadrature.values .+ 1) ./ 2, quadrature.vectors[1, :] .^ 2
end

const _TRANSITION_NODES, _TRANSITION_WEIGHTS = _transition_gauss_legendre(96)

function _transition_reference(sig1, sig2, x, y)
    s1, s2 = Float64(sig1), Float64(sig2)
    xb, yb = Float64(x), Float64(y)
    v = (s1^2 + s2^2) / 2
    eta = (s1^2 - s2^2) / (2v)
    X, Y = xb / sqrt(v), yb / sqrt(v)
    ix = iy = jx = jy = 0.0
    for (z, weight) in zip(_TRANSITION_NODES, _TRANSITION_WEIGHTS)
        density = exp(-z / 2 * (
            X^2 / (1 + eta * z) + Y^2 / (1 - eta * z)))
        fx = density / ((1 + eta * z)^1.5 * (1 - eta * z)^0.5)
        fy = density / ((1 + eta * z)^0.5 * (1 - eta * z)^1.5)
        ix += weight * fx
        iy += weight * fy
        jx += weight * z / (1 + eta * z) * fx
        jy += weight * z / (1 - eta * z) * fy
    end
    return (
        xb / v * ix,
        yb / v * iy,
        -(ix / v - xb^2 / v^2 * jx),
        -(iy / v - yb^2 / v^2 * jy),
    )
end

# Phase-12 instrument validation (docs/comprehensive_audit.md): the recorded
# defect is FED to the sweep by the script itself and the metrics must see it.
# `_INJECTION[]` is `nothing` for the clean sweep, or `(lo, hi, factor)`: at a
# blend fraction t = (eta - inner)/(outer - inner) inside [lo, hi] the
# evaluator's result is multiplied by `factor`, a relative error of
# `factor - 1` confined to that window. Every evaluation of the sweep and of
# the continuity probes goes through `_kick_response`, so the injection
# reaches whatever the clean run measures. Until 2026-10-20 this validation
# existed only as a comment describing a one-off measurement whose recorded
# magnitude ("caught at 1.0000e-03") did not match its recorded defect (a
# x1.1 error is 1.0e-1), and nothing re-fed it (comprehensive audit
# 2026-10-18, F-238 / U43-5).
const _INJECTION = Ref{Union{Nothing,Tuple{Float64,Float64,Float64}}}(nothing)

function _kick_response(::Type{T}, eta, sig1, sig2, x, y) where {T}
    value = collect(Octopus._gaussian_beambeam_kick_response(
        one(T), sig1, sig2, T(x), T(y)))
    injection = _INJECTION[]
    if injection !== nothing
        inner, outer = Octopus._near_round_eta_bounds(zero(T))
        t = (Float64(eta) - Float64(inner)) / (Float64(outer) - Float64(inner))
        injection[1] <= t <= injection[2] && (value .*= T(injection[3]))
    end
    return value
end

function _transition_value(::Type{T}, eta, x, y) where {T}
    etaT = T(eta)
    sig1 = sqrt(one(T) + etaT)
    sig2 = sqrt(one(T) - etaT)
    return _kick_response(T, etaT, sig1, sig2, x, y)
end

function _continuity_metrics(::Type{T}, boundary) where {T}
    h = boundary * T(0.01)
    max_force_value_gap = 0.0
    max_response_value_gap = 0.0
    max_force_derivative_gap = 0.0
    max_response_derivative_gap = 0.0
    max_force_value_gap_natural = 0.0
    max_response_value_gap_natural = 0.0
    max_force_derivative_gap_natural = 0.0
    max_response_derivative_gap_natural = 0.0
    q_values = unique!(sort!(vcat(
        T[5.0e-13, 5.0e-9, 5.0e-5],
        collect(range(T(1 / 64), T(8); length=129)))))
    angles = range(zero(T), T(pi / 2); length=33)

    for q in q_values, angle in angles
        radius = sqrt(T(2) * q)
        x, y = radius * cos(angle), radius * sin(angle)
        fm2 = Float64.(_transition_value(T, boundary - 2h, x, y))
        fm1 = Float64.(_transition_value(T, boundary - h, x, y))
        f0 = Float64.(_transition_value(T, boundary, x, y))
        fp1 = Float64.(_transition_value(T, boundary + h, x, y))
        fp2 = Float64.(_transition_value(T, boundary + 2h, x, y))

        left_value = 2fm1 - fm2
        right_value = 2fp1 - fp2
        left_derivative = (3 * f0 - 4 * fm1 + fm2) / (2Float64(h))
        right_derivative = (-3 * f0 + 4 * fp1 - fp2) / (2Float64(h))

        force_scale = max(norm(f0[1:2]), eps(Float64))
        response_scale = max(norm(f0[3:4]), eps(Float64))
        max_force_value_gap = max(
            max_force_value_gap,
            norm(left_value[1:2] - right_value[1:2]) / force_scale)
        max_response_value_gap = max(
            max_response_value_gap,
            norm(left_value[3:4] - right_value[3:4]) / response_scale)
        max_force_value_gap_natural = max(
            max_force_value_gap_natural,
            norm(left_value[1:2] - right_value[1:2]))
        max_response_value_gap_natural = max(
            max_response_value_gap_natural,
            norm(left_value[3:4] - right_value[3:4]))
        max_force_derivative_gap = max(
            max_force_derivative_gap,
            Float64(boundary) *
            norm(left_derivative[1:2] - right_derivative[1:2]) / force_scale)
        max_response_derivative_gap = max(
            max_response_derivative_gap,
            Float64(boundary) *
            norm(left_derivative[3:4] - right_derivative[3:4]) / response_scale)
        max_force_derivative_gap_natural = max(
            max_force_derivative_gap_natural,
            Float64(boundary) *
            norm(left_derivative[1:2] - right_derivative[1:2]))
        max_response_derivative_gap_natural = max(
            max_response_derivative_gap_natural,
            Float64(boundary) *
            norm(left_derivative[3:4] - right_derivative[3:4]))
    end

    return (
        force_value_gap=max_force_value_gap,
        response_value_gap=max_response_value_gap,
        force_derivative_gap=max_force_derivative_gap,
        response_derivative_gap=max_response_derivative_gap,
        force_value_gap_natural=max_force_value_gap_natural,
        response_value_gap_natural=max_response_value_gap_natural,
        force_derivative_gap_natural=max_force_derivative_gap_natural,
        response_derivative_gap_natural=max_response_derivative_gap_natural,
    )
end

function _transition_covariance(A, B, Q)
    covariance_rp = [A B; transpose(B) Q]
    permutation = (1, 3, 2, 4)
    return covariance_rp[collect(permutation), collect(permutation)]
end

function _transition_symplectic_residual(eta; step=1.0e-5)
    A = Matrix(Diagonal([1 + eta, 1 - eta]))
    B = Matrix(Diagonal([0.03, -0.02]))
    Q = transpose(B) * (A \ B) + 0.3I
    element = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.7, covariance=_transition_covariance(A, B, Matrix(Q))))
    q0 = [0.4, 1.0e-4, -0.2, -1.5e-4, 0.0, 2.0e-4]
    mapq(q) = collect(element(q...))
    jacobian = hcat([(
        mapq(q0 .+ (collect(1:6) .== column) .* step) -
        mapq(q0 .- (collect(1:6) .== column) .* step)
    ) / (2step) for column in 1:6]...)
    symplectic_form = zeros(6, 6)
    for coordinate in (1, 3, 5)
        symplectic_form[coordinate, coordinate + 1] = 1
        symplectic_form[coordinate + 1, coordinate] = -1
    end
    return norm(
        transpose(jacobian) * symplectic_form * jacobian - symplectic_form,
        Inf)
end

function run_near_round_transition_validation(::Type{T}) where {T<:AbstractFloat}
    inner, outer = Octopus._near_round_eta_bounds(zero(T))
    # The BLEND INTERIOR is the point of this script, and it used to get one
    # sample (2026-08-05_b audit, U23-3). The list was
    # {0, inner/4, inner, (inner+outer)/2, outer, 2*outer, 1e-3, 1e-2, 0.1, 0.5}
    # and every entry but `(inner+outer)/2` sits at or outside an endpoint, so
    # ~92% of the interval the branch switch actually blends over was never
    # evaluated. Measured then: injecting a x1.1 evaluator error over t in
    # [0.30, 0.40] left the sweep at 6.1096e-12, bit-identical to baseline, and
    # left both continuity gaps identical too -- while the same injection at
    # t in [0.45, 0.55] was caught, which proves the metric works and the
    # sampling was what failed. (That record said "caught at 1.0000e-03"; a
    # x1.1 error is a 1.0e-1 relative error and that is what the metric reads
    # today, 1.0000e-01 for both windows -- comprehensive audit 2026-10-18,
    # U43-5. The injection now runs in this script's main block, below, so the
    # record is re-measured on every run rather than quoted.)
    #
    # 17 interior points put a sample within 0.03 of every t in (0, 1).
    blend_interior = T[inner + (outer - inner) * T(k / 18) for k in 1:17]
    eta_values = sort!(unique(T[
        0,
        inner / T(4),
        inner,
        blend_interior...,
        outer,
        T(2) * outer,
        T(0.001),
        T(0.01),
        T(0.1),
        T(0.5),
    ]))
    q_values = unique!(sort!(vcat(
        T[5.0e-13, 5.0e-9, 5.0e-5],
        collect(range(T(1 / 64), T(8); length=513)))))
    angles = range(zero(T), T(pi / 2); length=65)

    max_force_relative_error = 0.0
    max_response_relative_error = 0.0
    max_force_natural_error = 0.0
    max_response_natural_error = 0.0
    max_transition_force_relative_error = 0.0
    max_transition_response_relative_error = 0.0
    max_transition_force_natural_error = 0.0
    max_transition_response_natural_error = 0.0
    max_outer_series_response_natural_error = 0.0
    max_outer_exact_response_natural_error = 0.0
    for eta in eta_values
        sig1, sig2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
        for q in q_values, angle in angles
            radius = sqrt(T(2) * q)
            x, y = radius * cos(angle), radius * sin(angle)
            actual = _kick_response(T, eta, sig1, sig2, x, y)
            reference = _transition_reference(sig1, sig2, x, y)
            force_error = hypot(
                Float64(actual[1]) - reference[1],
                Float64(actual[2]) - reference[2])
            response_error = hypot(
                Float64(actual[3]) - reference[3],
                Float64(actual[4]) - reference[4])
            max_force_relative_error = max(
                max_force_relative_error,
                force_error / hypot(reference[1], reference[2]))
            max_response_relative_error = max(
                max_response_relative_error,
                response_error / hypot(reference[3], reference[4]))
            max_force_natural_error = max(max_force_natural_error, force_error)
            max_response_natural_error =
                max(max_response_natural_error, response_error)
            if eta <= T(2) * outer
                max_transition_force_relative_error = max(
                    max_transition_force_relative_error,
                    force_error / hypot(reference[1], reference[2]))
                max_transition_response_relative_error = max(
                    max_transition_response_relative_error,
                    response_error / hypot(reference[3], reference[4]))
                max_transition_force_natural_error = max(
                    max_transition_force_natural_error, force_error)
                max_transition_response_natural_error = max(
                    max_transition_response_natural_error, response_error)
            end
            if eta == outer
                series = Octopus._near_round_series_response(
                    one(T), one(T), eta, x, y)
                series_response_error = hypot(
                    Float64(series[3]) - reference[3],
                    Float64(series[4]) - reference[4])
                max_outer_series_response_natural_error = max(
                    max_outer_series_response_natural_error,
                    series_response_error)
                max_outer_exact_response_natural_error = max(
                    max_outer_exact_response_natural_error,
                    response_error)
            end
        end
    end

    core_coordinate = T === Float32 ? T(1.0e-4) : T(1.0e-8)
    max_core_gradient_error = 0.0
    for eta in (outer, T(0.001), T(0.01), T(0.1), T(0.5), T(0.9))
        sig1, sig2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
        Kx, _ = gaussian_beambeam_kick(
            sig1, sig2, core_coordinate, zero(T))
        _, Ky = gaussian_beambeam_kick(
            sig1, sig2, zero(T), core_coordinate)
        gx = T(2) / (sig1 * (sig1 + sig2))
        gy = T(2) / (sig2 * (sig1 + sig2))
        max_core_gradient_error = max(
            max_core_gradient_error,
            abs(Float64(Kx / core_coordinate / gx) - 1),
            abs(Float64(Ky / core_coordinate / gy) - 1))
    end

    return (
        arithmetic=T,
        conditioning_factor=Octopus._near_round_conditioning_factor(T),
        eta_inner=inner,
        eta_outer=outer,
        max_force_relative_error=max_force_relative_error,
        max_response_relative_error=max_response_relative_error,
        max_force_natural_error=max_force_natural_error,
        max_response_natural_error=max_response_natural_error,
        max_transition_force_relative_error=max_transition_force_relative_error,
        max_transition_response_relative_error=max_transition_response_relative_error,
        max_transition_force_natural_error=max_transition_force_natural_error,
        max_transition_response_natural_error=max_transition_response_natural_error,
        max_outer_series_response_natural_error=
            max_outer_series_response_natural_error,
        max_outer_exact_response_natural_error=
            max_outer_exact_response_natural_error,
        observed_outer_conditioning_factor=
            max_outer_exact_response_natural_error * Float64(outer) / eps(T),
        max_core_gradient_error=max_core_gradient_error,
        inner_continuity=_continuity_metrics(T, inner),
        outer_continuity=_continuity_metrics(T, outer),
        symplectic_residual=T === Float64 ?
            _transition_symplectic_residual(0.75 * Float64(outer)) : nothing,
    )
end

function _near_round_transition_cuda_kernel!(output, sig1, sig2, x, y)
    index = (Octopus.CUDA.blockIdx().x - 1) * Octopus.CUDA.blockDim().x +
            Octopus.CUDA.threadIdx().x
    if index <= length(sig1)
        Kx, Ky, H1, H2 = Octopus._cuda_gaussian_beambeam_kick_response(
            one(eltype(output)), sig1[index], sig2[index], x[index], y[index])
        output[1, index] = Kx
        output[2, index] = Ky
        output[3, index] = H1
        output[4, index] = H2
    end
    return nothing
end

function run_near_round_cuda_parity(::Type{T}) where {T<:AbstractFloat}
    Octopus._HAS_CUDA && Octopus.CUDA.functional() || return nothing
    inner, outer = Octopus._near_round_eta_bounds(zero(T))
    eta_values = T[inner, T(0.75) * outer, outer, T(1.2) * outer, T(0.1)]
    points = Tuple{T,T}[
        (T(1.0e-6), T(-5.0e-7)),
        (T(0.2), T(-0.1)),
        (T(1.3), T(0.7)),
        (sqrt(T(0.0625)) * cos(T(pi / 16)),
         sqrt(T(0.0625)) * sin(T(pi / 16))),
        (sqrt(T(5)) * cos(T(15pi / 32)),
         sqrt(T(5)) * sin(T(15pi / 32))),
    ]
    sig1 = T[]
    sig2 = T[]
    x = T[]
    y = T[]
    expected = Vector{NTuple{4,T}}()
    for eta in eta_values, (xx, yy) in points
        s1, s2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
        push!(sig1, s1)
        push!(sig2, s2)
        push!(x, xx)
        push!(y, yy)
        push!(expected, Octopus._gaussian_beambeam_kick_response(
            one(T), s1, s2, xx, yy))
    end

    output = Octopus.CUDA.zeros(T, 4, length(sig1))
    threads = 128
    blocks = cld(length(sig1), threads)
    Octopus.CUDA.@cuda threads=threads blocks=blocks _near_round_transition_cuda_kernel!(
        output,
        Octopus.CUDA.CuArray(sig1),
        Octopus.CUDA.CuArray(sig2),
        Octopus.CUDA.CuArray(x),
        Octopus.CUDA.CuArray(y))
    Octopus.CUDA.synchronize()
    actual = Array(output)

    max_relative_error = 0.0
    max_natural_error = 0.0
    for index in eachindex(expected)
        reference = collect(Float64, expected[index])
        error = norm(Float64.(actual[:, index]) - reference)
        max_relative_error = max(
            max_relative_error, error / max(norm(reference), eps(Float64)))
        max_natural_error = max(max_natural_error, error)
    end
    return (
        arithmetic=T,
        max_relative_error=max_relative_error,
        max_natural_error=max_natural_error,
    )
end

function print_near_round_transition_result(result)
    println(result.arithmetic)
    println("  nominal conditioning factor = ", result.conditioning_factor)
    println("  eta interval = [", result.eta_inner, ", ", result.eta_outer, "]")
    println("  max force relative error = ", result.max_force_relative_error)
    println("  max response relative error = ", result.max_response_relative_error)
    println("  max force natural-scale error = ", result.max_force_natural_error)
    println("  max response natural-scale error = ", result.max_response_natural_error)
    println("  transition-only max force relative error = ",
        result.max_transition_force_relative_error)
    println("  transition-only max response relative error = ",
        result.max_transition_response_relative_error)
    println("  transition-only max force natural-scale error = ",
        result.max_transition_force_natural_error)
    println("  transition-only max response natural-scale error = ",
        result.max_transition_response_natural_error)
    println("  outer series response natural-scale error = ",
        result.max_outer_series_response_natural_error)
    println("  outer exact response natural-scale error = ",
        result.max_outer_exact_response_natural_error)
    println("  observed outer conditioning factor = ",
        result.observed_outer_conditioning_factor)
    println("  max core-gradient relative error = ", result.max_core_gradient_error)
    println("  inner endpoint continuity = ", result.inner_continuity)
    println("  outer endpoint continuity = ", result.outer_continuity)
    result.symplectic_residual === nothing ||
        println("  6D symplectic residual = ", result.symplectic_residual)
end

if abspath(PROGRAM_FILE) == @__FILE__
    println("Near-round Gaussian transition validation")
    # A documented defect injection for showing the gates red (the twiss
    # benchmarks' OCTOPUS_STAGE8_DEFECT precedent): OCTOPUS_NEAR_ROUND_DEFECT =
    # none (default) | mid | inner_edge | outer_edge applies the x1.1 evaluator
    # error over t in [0.30, 0.40], [0.01, 0.04] or [0.96, 0.99] to the MAIN
    # sweeps, so the run must fail at the metric that sees it (the force gate
    # for `mid`, the continuity gaps alone for the two edges). Reset before the
    # parity and Phase-12 blocks, which inject their own windows.
    defect = get(ENV, "OCTOPUS_NEAR_ROUND_DEFECT", "none")
    defect_windows = Dict("none" => nothing, "mid" => (0.30, 0.40, 1.1),
                          "inner_edge" => (0.01, 0.04, 1.1), "outer_edge" => (0.96, 0.99, 1.1))
    haskey(defect_windows, defect) || error(
        "OCTOPUS_NEAR_ROUND_DEFECT must be one of none, mid, inner_edge, outer_edge; got $(repr(defect))")
    _INJECTION[] = defect_windows[defect]
    defect == "none" || println("DEFECT INJECTED (OCTOPUS_NEAR_ROUND_DEFECT=", defect,
                                "): x1.1 over t in ", defect_windows[defect][1:2],
                                "; the gate that sees it must fail below")
    results = try
        map((Float32, Float64)) do T
            result = run_near_round_transition_validation(T)
            print_near_round_transition_result(result)
            result
        end
    finally
        _INJECTION[] = nothing
    end
    for T in (Float32, Float64)
        parity = run_near_round_cuda_parity(T)
        if parity === nothing
            # Assertable, not just visible (U25-10's rule): with
            # OCTOPUS_REQUIRE_GPU_CONTRACT=1 a missing device fails the run;
            # otherwise the skip is printed, where it used to print nothing.
            Octopus._require_gpu_contract() && error(
                "near-round CPU/CUDA parity for $(T) was required " *
                "(OCTOPUS_REQUIRE_GPU_CONTRACT=1) but no CUDA device is functional")
            println("CUDA parity ", T, ": skipped (no CUDA device)")
        else
            println("CUDA parity ", T,
                    ": max relative error = ", parity.max_relative_error,
                    ", max natural-scale error = ", parity.max_natural_error)
        end
    end
    all(result -> all(isfinite, (
            result.max_force_relative_error,
            result.max_response_relative_error,
            result.max_core_gradient_error)), results) ||
        error("non-finite transition validation metric")

    # `isfinite` was the ONLY failure condition here, in a script whose whole
    # purpose is to compute the two numbers that bind the near-round
    # calibration and the CPU/CUDA split -- so it printed them and asserted
    # neither (2026-08-05_b audit, U8-6). A validation script that cannot fail
    # is a report, not a validation.
    #
    # Bounds are ~3x the values measured on 2026-08-07 with an RTX 4500 Ada,
    # not round numbers: loose enough to survive a different GPU or a Julia
    # minor version, tight enough to notice a real drift.
    for (T, result) in zip((Float32, Float64), results)
        nominal = Float64(Octopus._near_round_conditioning_factor(T))
        observed = Float64(result.observed_outer_conditioning_factor)
        # The conditioning factor is the constant the outer crossover is sized
        # from. Nominal 64.0 / 8.0; measured 61.94 / 4.95. The Float32 gap is a
        # factor 1.6 and is why the bound is stated as a RATIO band rather than
        # an absolute: what matters is that the calibration still describes the
        # function, not that it matches to three digits.
        0.4 <= observed / nominal <= 2.5 || error(
            "near-round outer conditioning factor drifted from its calibration: " *
            "$(T) observed $(observed) against nominal $(nominal)")
    end
    let f64 = results[2]
        f64.max_force_relative_error < 2.0e-11 || error(
            "Float64 near-round force error regressed: $(f64.max_force_relative_error)")
        f64.max_response_relative_error < 4.0e-8 || error(
            "Float64 near-round response error regressed: $(f64.max_response_relative_error)")
        # The rest of the Float64 metrics, gated since 2026-10-20 (comprehensive
        # audit 2026-10-18, F-238 / U43-4: of about fifteen metrics three were
        # gated and the rest printed, and the endpoint continuity gaps are the
        # ONLY instrument that sees the first and last few percent of the blend
        # interval -- the main sweep samples t = k/18, so a defect confined to
        # t in [0.01, 0.04] or [0.96, 0.99] leaves every gated number at its
        # baseline and shows only in a gap; the Phase-12 block below proves
        # it on every run).
        #
        # Bounds, with their derivation. The gated gaps are the RELATIVE ones
        # (relative to the force or response scale at the endpoint; the
        # natural-scale gaps are printed beside them), the quantities the
        # Phase-12 block below measures under an injected defect: an evaluator
        # error of relative size delta at one side of an endpoint shows as a
        # gap of about delta (measured: x1.1 at the inner edge gives an inner
        # force value gap of 1.0e-1, at the outer edge an outer gap of 2.0e-1).
        # The clean relative gaps are roundoff carried through the evaluator,
        # measured 2026-10-20 on this tree (the gate's CUDA arm, probe
        # near_round_gpu_require): inner force / response value gaps 1.8e-15 /
        # 9.4e-13, outer 9.5e-13 / 6.7e-9; inner force / response derivative
        # gaps 2.0e-13 / 1.3e-11, outer 9.4e-11 / 5.2e-7. The response gaps are
        # the larger because the response is the second-order quantity, whose
        # relative roundoff carries the conditioning factor (64 nominal) and
        # whose own gated error above is 1.2e-8 against 4.0e-8. Each bound sits
        # at least 150x above its largest clean gap, where a CPU arm cannot move
        # roundoff, and 1e3 to 1e8 below the injected defect: force value gap
        # 1e-9 (1000x above 9.5e-13), response value gap 1e-6 (150x above
        # 6.7e-9), force derivative gap 1e-7 (1000x above 9.4e-11), response
        # derivative gap 1e-4 (200x above 5.2e-7). So a relative error down to
        # about 1e-9 in the force and 1e-6 in the response at an endpoint is
        # caught. The core-gradient error is exact arithmetic (2.2e-16
        # measured; bound 1e-12), and the 6D symplectic residual is the
        # finite-difference step's truncation (1.6e-10 measured at step 1e-5;
        # bound 1e-8).
        f64.max_core_gradient_error < 1.0e-12 || error(
            "Float64 near-round core-gradient error regressed: $(f64.max_core_gradient_error)")
        f64.symplectic_residual < 1.0e-8 || error(
            "near-round 6D symplectic residual regressed: $(f64.symplectic_residual)")
        for (side, gaps) in (("inner", f64.inner_continuity), ("outer", f64.outer_continuity))
            gaps.force_value_gap < 1.0e-9 || error(
                "Float64 $(side) endpoint force value gap regressed: $(gaps.force_value_gap)")
            gaps.response_value_gap < 1.0e-6 || error(
                "Float64 $(side) endpoint response value gap regressed: $(gaps.response_value_gap)")
            gaps.force_derivative_gap < 1.0e-7 || error(
                "Float64 $(side) endpoint force derivative gap regressed: $(gaps.force_derivative_gap)")
            gaps.response_derivative_gap < 1.0e-4 || error(
                "Float64 $(side) endpoint response derivative gap regressed: $(gaps.response_derivative_gap)")
        end
    end

    # Phase 12: feed the recorded defect to the instrument and require that it
    # is seen -- in the gated metric for a mid-blend window, and in the ONLY
    # instrument that reaches an endpoint window, the continuity gap. A
    # x1.1 error is a 1.0e-1 relative error; the metrics must read at least
    # half of it (the sampling puts a point within 0.03 of every t, so a
    # window 0.1 wide is always sampled). The injected sweeps are Float64
    # only; `_INJECTION[]` is reset before anything else runs.
    println("Phase 12: the recorded x1.1 evaluator defect, re-fed")
    phase12 = Tuple{String,Float64}[]
    try
        _INJECTION[] = (0.30, 0.40, 1.1)
        injected_mid = run_near_round_transition_validation(Float64)
        push!(phase12, ("force relative error, x1.1 over t in [0.30, 0.40]",
                        injected_mid.max_force_relative_error))
        _INJECTION[] = (0.01, 0.04, 1.1)
        injected_inner = run_near_round_transition_validation(Float64)
        push!(phase12, ("inner endpoint force value gap, x1.1 over t in [0.01, 0.04]",
                        injected_inner.inner_continuity.force_value_gap))
        push!(phase12, ("force relative error under the same edge injection (the sampling's blind spot, reported)",
                        injected_inner.max_force_relative_error))
        _INJECTION[] = (0.96, 0.99, 1.1)
        injected_outer = run_near_round_transition_validation(Float64)
        push!(phase12, ("outer endpoint force value gap, x1.1 over t in [0.96, 0.99]",
                        injected_outer.outer_continuity.force_value_gap))
    finally
        _INJECTION[] = nothing
    end
    for (label, value) in phase12
        println("  ", label, " = ", value)
    end
    seen(label) = phase12[findfirst(p -> startswith(p[1], label), phase12)][2]
    seen("force relative error, x1.1") >= 0.05 || error(
        "Phase 12: the gated force metric did not see a x1.1 defect over t in [0.30, 0.40]")
    seen("inner endpoint force value gap") >= 0.05 || error(
        "Phase 12: the inner continuity gap did not see a x1.1 defect over t in [0.01, 0.04]")
    seen("outer endpoint force value gap") >= 0.05 || error(
        "Phase 12: the outer continuity gap did not see a x1.1 defect over t in [0.96, 0.99]")

    # The CPU/CUDA split. The theory note lists "CPU versus CUDA evaluation" as
    # an axis on which C_BE varies, yet ONE constant serves both -- so the
    # parity number is the evidence that the single constant is still adequate,
    # and it was printed and dropped. Measured 1.37e-11 (Float64) and 1.15e-5
    # (Float32) against the independent quadrature.
    for (T, bound) in ((Float32, 4.0e-5), (Float64, 5.0e-11))
        parity = run_near_round_cuda_parity(T)
        parity === nothing && continue          # no GPU: nothing measured, nothing claimed
        parity.max_relative_error < bound || error(
            "near-round CPU/CUDA parity regressed for $(T): " *
            "$(parity.max_relative_error) exceeds $(bound)")
    end
end
