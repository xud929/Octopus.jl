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

function _transition_value(::Type{T}, eta, x, y) where {T}
    etaT = T(eta)
    sig1 = sqrt(one(T) + etaT)
    sig2 = sqrt(one(T) - etaT)
    return collect(Octopus._gaussian_beambeam_kick_response(
        one(T), sig1, sig2, T(x), T(y)))
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
    eta_values = sort!(unique(T[
        0,
        inner / T(4),
        inner,
        (inner + outer) / T(2),
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
            actual = Octopus._gaussian_beambeam_kick_response(
                one(T), sig1, sig2, x, y)
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
    results = map((Float32, Float64)) do T
        result = run_near_round_transition_validation(T)
        print_near_round_transition_result(result)
        result
    end
    for T in (Float32, Float64)
        parity = run_near_round_cuda_parity(T)
        parity === nothing || println(
            "CUDA parity ", T,
            ": max relative error = ", parity.max_relative_error,
            ", max natural-scale error = ", parity.max_natural_error)
    end
    all(result -> all(isfinite, (
            result.max_force_relative_error,
            result.max_response_relative_error,
            result.max_core_gradient_error)), results) ||
        error("non-finite transition validation metric")
end
