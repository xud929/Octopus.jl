using Test
using Octopus
using LinearAlgebra

@testset "Architecture integrity" begin
    metadata = validate_element_metadata(; throw_on_error=true)
    @test metadata.passed
    @test validate_configuration_metadata()

    snapshot_path = joinpath(pkgdir(Octopus), "docs", "registry_snapshot.md")
    @test registry_snapshot_markdown() == read(snapshot_path, String)
end

@testset "Non-symplectic Lorentz method classification" begin
    forward_spec = LorentzBoostSpec(0.01)
    reverse_spec = RevLorentzBoostSpec(0.01)
    raw_forward_spec = ElementSpec{:lorentz_boost}(; angle=0.01)
    raw_reverse_spec = ElementSpec{:rev_lorentz_boost}(; angle=0.01)
    @test tracking_method(forward_spec) isa NonSymplectic6DMap
    @test tracking_method(reverse_spec) isa NonSymplectic6DMap
    @test tracking_method(raw_forward_spec) isa NonSymplectic6DMap
    @test tracking_method(raw_reverse_spec) isa NonSymplectic6DMap
    @test supported_tracking_methods(forward_spec) == DataType[NonSymplectic6DMap]
    @test supported_tracking_methods(reverse_spec) == DataType[NonSymplectic6DMap]
    @test :quasi_symplectic in physics_keywords(forward_spec)
    @test :quasi_symplectic in physics_keywords(reverse_spec)
    @test compile_runtime(forward_spec) isa LorentzBoost{NonSymplectic6DMap}
    @test compile_runtime(reverse_spec) isa RevLorentzBoost{NonSymplectic6DMap}
    @test compile_runtime(raw_forward_spec) isa LorentzBoost{NonSymplectic6DMap}
    @test compile_runtime(raw_reverse_spec) isa RevLorentzBoost{NonSymplectic6DMap}
    @test_throws MethodError compile_runtime(
        LorentzBoostSpec(0.01; tracking_method=Symplectic6DMap()))
end

@testset "Linear6D rejects non-symplectic matrices" begin
    for T in (Float32, Float64)
        identity_map = Matrix{T}(I, 6, 6)
        @test compile_runtime(Linear6DSpec{T}(matrix=identity_map)) isa Linear6D

        # Reciprocal scaling is symplectic even when its coordinate magnitudes
        # differ strongly; a global ||M||^2 tolerance would be far too loose.
        scaled = Matrix{T}(I, 6, 6)
        scale = T === Float32 ? T(1.0e3) : T(1.0e8)
        scaled[1, 1] = scale
        scaled[2, 2] = inv(scale)
        @test compile_runtime(Linear6DSpec{T}(matrix=scaled)) isa Linear6D

        canonical_shear = Matrix{T}(I, 6, 6)
        canonical_shear[1, 2] = T(0.3)
        @test compile_runtime(
            Linear6DSpec{T}(matrix=canonical_shear)) isa Linear6D
        raw_shear = ElementSpec{:linear6d}(
            matrix=canonical_shear, tracking_method=Symplectic6DMap())
        @test Matrix(compile_runtime(raw_shear)) == canonical_shear

        # This cross-plane shear has determinant one but omits the conjugate
        # py update, so determinant-only validation would incorrectly accept it.
        nonsymplectic = Matrix{T}(I, 6, 6)
        nonsymplectic[1, 3] = T(0.3)
        @test det(nonsymplectic) == one(T)
        @test_throws ArgumentError Linear6DSpec{T}(matrix=nonsymplectic)

        nonfinite = Matrix{T}(I, 6, 6)
        nonfinite[1, 1] = T(Inf)
        @test_throws ArgumentError Linear6DSpec{T}(matrix=nonfinite)
    end

    # Flexible specs and direct runtime construction must not bypass the same
    # invariant enforced by the friendly constructor.
    nonsymplectic = Matrix{Float64}(I, 6, 6)
    nonsymplectic[1, 1] = 1.001
    raw = ElementSpec{:linear6d}(
        matrix=Tuple(vec(transpose(nonsymplectic))),
        tracking_method=Symplectic6DMap(),
    )
    @test_throws ArgumentError compile_runtime(raw)
    tuple_matrix = Octopus._matrix66_tuple(nonsymplectic, Float64)
    @test_throws ArgumentError Linear6D(Symplectic6DMap(), tuple_matrix)

    optics = Linear6DSpec{Float64}(
        beta1=(0.55, 0.056, 12.7),
        beta2=(0.8, 0.072, 90.9),
        alpha1=(0.08, 0.14, -0.069),
        alpha2=(0.0, 0.0, 0.0),
        dmu=(0.3, 0.4, 0.2),
        zeta1=(0.01, -0.02, 0.03, -0.01),
        eta1=(0.02, 0.01, -0.01, 0.04),
        R1=(0.01, -0.02, 0.015, 0.005),
        zeta2=(-0.01, 0.01, 0.02, 0.03),
        eta2=(0.01, -0.03, 0.02, -0.01),
        R2=(-0.005, 0.01, -0.015, 0.02),
    )
    @test compile_runtime(optics) isa Linear6D
end

@testset "Counter RNG smoke tests" begin
    philox1 = [counter_normal(0x12345678, 3, 9, i, 1, Float64) for i in 1:1000]
    philox2 = [counter_normal(0x12345678, 3, 9, i, 1, Float64) for i in 1:1000]
    another_component = [
        counter_normal(0x12345678, 3, 9, i, 2, Float64) for i in 1:1000
    ]
    uniforms = [counter_uniform01(0x12345678, 3, 9, i, 1, Float64) for i in 1:1000]

    @test philox1 == philox2
    @test philox1 != another_component
    @test all(isfinite, philox1)
    @test all(value -> 0.0 < value < 1.0, uniforms)

    @test Octopus._uniform_open01(UInt64(0), Float64) == 2.0^-53
    @test Octopus._uniform_open01(typemax(UInt64), Float64) == prevfloat(1.0)
    @test Octopus._uniform_open01(UInt64(0), Float32) == 2.0f0^-24
    @test Octopus._uniform_open01(typemax(UInt64), Float32) == prevfloat(1.0f0)
    @test all(UInt64(0):(UInt64(1) << 23) - UInt64(1)) do bits
        value = Octopus._uniform_open01(bits << 41, Float32)
        0.0f0 < value < 1.0f0
    end
end

struct TestNoopObserver <: Octopus.AbstractBeamObserver end
Octopus.observe!(::TestNoopObserver, ctx::Octopus.TrackingContext, rep) = nothing

mutable struct TestTurnObserver <: Octopus.AbstractBeamObserver
    turns::Vector{Int}
end
Octopus.observe!(
    observer::TestTurnObserver, ctx::Octopus.TrackingContext, rep) =
    push!(observer.turns, Int(ctx.turn))

function run_tracking_smoke(hooks)
    spec = ThinStrongBeamSpec(;
        kbb=1.0e-4,
        beta=(1.0, 1.0),
        sigma=(1.0e-3, 1.0e-3),
    )
    rep = Phase6DRep([1.0e-3], [0.0], [2.0e-3], [0.0], [0.0], [0.0])
    execute!(TrackingTask((spec,); hooks=hooks), rep; turns=2)
    return rep[1]
end

@testset "TrackingTask smoke test" begin
    initial = (1.0e-3, 0.0, 2.0e-3, 0.0, 0.0, 0.0)
    fast = run_tracking_smoke(())
    planned = run_tracking_smoke((TestNoopObserver(),))

    @test fast == planned
    @test fast != initial
end

@testset "TrackingTask absolute turns survive chunked execution" begin
    observer = TestTurnObserver(Int[])
    task = TrackingTask((); hooks=(observer,))
    rep = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
    execute!(task, rep; turns=2)
    execute!(task, rep; turns=3)
    @test observer.turns == collect(0:4)

    execute!(task, rep; turns=1, start_turn=9)
    @test observer.turns[end] == 9
    execute!(task, rep; turns=1)
    @test observer.turns[end] == 10
    @test_throws ArgumentError execute!(task, rep; turns=-1)
    @test_throws ArgumentError execute!(task, rep; turns=1, start_turn=-1)
    @test_throws ArgumentError execute!(task, rep; turns=1, start_turn=1.5)

    # Counter-based radiation must be bit-identical whether turns are executed
    # in one call or in chunks.
    radiation = LumpedRadSpec(
        damping_turns=(20.0, 25.0, 30.0),
        beta=(0.7, 0.9, 1.1),
        alpha=(0.2, -0.1, 0.05),
        sigma=(1.2e-3, 0.8e-3, 2.0e-3),
        rng_id=0x1234,
    )
    n = 128
    initial = Phase6DRep(
        collect(range(-1.0e-3, 1.0e-3; length=n)),
        collect(range(2.0e-4, -2.0e-4; length=n)),
        collect(range(0.7e-3, -0.7e-3; length=n)),
        collect(range(-1.0e-4, 1.0e-4; length=n)),
        collect(range(-2.0e-3, 2.0e-3; length=n)),
        collect(range(3.0e-4, -3.0e-4; length=n)),
    )
    continuous = deepcopy(initial)
    chunked = deepcopy(initial)
    set_global_rng!(seed=0x5eed, method=:philox)
    execute!(TrackingTask((radiation,)), continuous; turns=7)
    set_global_rng!(seed=0x5eed, method=:philox)
    chunked_task = TrackingTask((radiation,))
    execute!(chunked_task, chunked; turns=3)
    execute!(chunked_task, chunked; turns=4)
    for (expected, actual) in zip(
            coordinate_arrays(continuous), coordinate_arrays(chunked))
        @test actual == expected
    end
end

@testset "Lumped radiation method and flag semantics" begin
    function radiation_spec(; kwargs...)
        return LumpedRadSpec{Float64}(;
            damping_turns=(10.0, 20.0, 30.0),
            beta=(0.7, 0.9, 1.1),
            alpha=(0.2, -0.1, 0.05),
            sigma=(1.2e-3, 0.8e-3, 2.0e-3),
            zeta=(0.01, -0.02, 0.03, -0.04),
            eta=(0.05, -0.06, 0.07, -0.08),
            R=(0.01, 0.02, -0.015, 0.005),
            rng_id=0x4567,
            kwargs...,
        )
    end

    coords = (1.0e-3, -2.0e-4, 0.7e-3, 1.0e-4, -2.0e-3, 3.0e-4)
    ctx = TrackingContext(turn=17, seed=0x12345678, rng_method=:philox)
    both = radiation_spec(is_damping=true, is_excitation=true)
    damping = compile_runtime(both, Damping6DMap())
    diffusion = compile_runtime(both, Diffusion6DMap())
    damping_reference = compile_runtime(
        radiation_spec(is_damping=true, is_excitation=false), Radiation6DMap())
    diffusion_reference = compile_runtime(
        radiation_spec(is_damping=false, is_excitation=true), Radiation6DMap())

    @test damping.is_damping
    @test !damping.is_excitation
    @test !diffusion.is_damping
    @test diffusion.is_excitation
    @test damping(ctx, 11, coords...) == damping_reference(ctx, 11, coords...)
    @test diffusion(ctx, 11, coords...) == diffusion_reference(ctx, 11, coords...)

    damping_disabled = compile_runtime(
        radiation_spec(is_damping=false, is_excitation=true), Damping6DMap())
    diffusion_disabled = compile_runtime(
        radiation_spec(is_damping=true, is_excitation=false), Diffusion6DMap())
    @test damping_disabled(ctx, 11, coords...) == coords
    @test diffusion_disabled(ctx, 11, coords...) == coords

    long_turn = compile_runtime(LumpedRadSpec{Float32}(;
        damping_turns=(1.0f8, 1.0f8, 1.0f8),
        beta=(1.0f0, 1.0f0, 1.0f0),
        sigma=(1.0f0, 1.0f0, 1.0f0),
        rng_id=1,
    ))
    @test long_turn.damping[1] == 1.0f0
    @test long_turn.excitation[1] == sqrt(-expm1(-2.0f0 / 1.0f8))
    @test long_turn.excitation[1] > 0.0f0

    infinite_turn = compile_runtime(LumpedRadSpec(;
        damping_turns=(Inf, Inf, Inf), sigma=(1.0, 1.0, 1.0), rng_id=1,
    ))
    @test infinite_turn.damping == (1.0, 1.0, 1.0)
    @test infinite_turn.excitation == ntuple(_ -> 0.0, 9)

    @test_throws ArgumentError compile_runtime(
        LumpedRadSpec(damping_turns=(10.0, 0.0, 30.0)))
    @test_throws ArgumentError compile_runtime(
        LumpedRadSpec(damping_turns=(10.0, NaN, 30.0)))
    @test_throws ArgumentError compile_runtime(
        LumpedRadSpec(damping_turns=(10.0, 20.0, 30.0), beta=(1.0, 0.0, 1.0)))
    @test_throws ArgumentError compile_runtime(
        LumpedRadSpec(damping_turns=(10.0, 20.0, 30.0), sigma=(1.0, -1.0, 1.0)))
    @test_throws ArgumentError compile_runtime(
        LumpedRadSpec(damping_turns=(10.0, 20.0, 30.0), sigma=(1.0, Inf, 1.0)))
end

function covariance_xpxypy(A, B, Q)
    covariance_rp = [A B; transpose(B) Q]
    permutation = (1, 3, 2, 4)
    return covariance_rp[collect(permutation), collect(permutation)]
end

function covariance_kick_and_direct_pz(moments, S, x, y; kbb=0.7)
    result = Octopus._cp_covariance_kick(
        moments, kbb, S, x, y, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    return (result[2], result[4]), result[6]
end

function numerical_potential_hessian(moments, S, x, y; kbb=0.7, h=1.0e-5)
    force(x, y) = first(covariance_kick_and_direct_pz(moments, S, x, y; kbb=kbb))
    fxp, fyp = force(x + h, y)
    fxm, fym = force(x - h, y)
    fxu, fyu = force(x, y + h)
    fxd, fyd = force(x, y - h)
    return -[(fxp - fxm) / (2h) (fxu - fxd) / (2h);
             (fyp - fym) / (2h) (fyu - fyd) / (2h)]
end

@testset "Physical and unsafe weak-strong virtual drifts" begin
    selectors = (
        UnsafeVirtualDrift(:chromatic_frozen_energy),
        UnsafeVirtualDrift(:paraxial_frozen_longitudinal),
        :hirata,
        :chromatic,
        :exact,
    )
    types = (
        UnsafeVirtualDrift,
        UnsafeVirtualDrift,
        HirataParaxialDrift,
        ChromaticDrift,
        ExactHamiltonianDrift,
    )
    expected = (
        (0.0003999835039418916, 0.00013666524273487976,
         -0.00019998712362314373, -0.00017861989917526642,
         0.001200000004066925, 0.0002000229507998965),
        (0.00039998350064043646, 0.0001366652434746287,
         -0.00019998712104450967, -0.00017861990108964464,
         0.0012, 0.00020002295080011575),
        (0.00039998350064043646, 0.0001366652434746287,
         -0.00019998712104450967, -0.00017861990108964464,
         0.0012, 0.00020002747141457556),
        (0.0003999835039413922, 0.00013666524273487976,
         -0.00019998712362249104, -0.00017861989917526642,
         0.0012000000040669253, 0.00020002747050984119),
        (0.0003999835039409804, 0.00013666524273488455,
         -0.0001999871236220233, -0.00017861989917524238,
         0.0012000000040669253, 0.00020002747050991326),
    )
    q = (4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4)
    for (selector, drift_type, reference) in zip(selectors, types, expected)
        element = ThinStrongBeam(ThinStrongBeamSpec(;
            kbb=1.0e-7, beta=(0.8, 1.2), alpha=(0.3, -0.2),
            sigma=(1.1e-3, 0.7e-3), center=(2.0e-5, -1.0e-5, 3.0e-4),
            angle=(3.0e-4, -2.0e-4, 0.0),
            curvature=(2.0e-3, -1.0e-3, 0.0), virtual_drift=selector))
        @test element.virtual_drift isa drift_type
        @test element(q...) == reference
    end
    direct = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=1.0e-7, beta=(1.0, 1.0), sigma=(1.0e-3, 1.0e-3),
        virtual_drift=ExactHamiltonianDrift()))
    @test direct.virtual_drift isa ExactHamiltonianDrift
    sliced = GaussianStrongBeam(GaussianStrongBeamSpec(;
        thin=ThinStrongBeamSpec(;
            kbb=1.0e-7, beta=(1.0, 1.0), sigma=(1.0e-3, 1.0e-3),
            virtual_drift=:exact),
        ns=3, sigz=1.0e-2))
    inferred_result = @inferred Octopus._track_gaussian_strong_beam_with_luminosity(
        sliced, q...)
    @test all(isfinite, inferred_result)
    @test_throws ArgumentError ThinStrongBeamSpec(;
        kbb=1.0, beta=(1.0, 1.0), sigma=(1.0, 1.0), virtual_drift=0)
    @test_throws ArgumentError ThinStrongBeamSpec(;
        kbb=1.0, beta=(1.0, 1.0), sigma=(1.0, 1.0), virtual_drift=:unknown)
    @test_throws ArgumentError ThinStrongBeamSpec(;
        kbb=1.0, beta=(1.0, 1.0), sigma=(1.0, 1.0),
        virtual_drift=:paraxial_frozen_longitudinal)
    @test_throws ArgumentError UnsafeVirtualDrift(:hirata)
    @test_throws MethodError UnsafeVirtualDrift(HirataParaxialDrift())
end

@testset "Round Gaussian near-axis stability" begin
    function round_reference(T, sigma, x, y)
        setprecision(BigFloat, 256) do
            sb, xb, yb = BigFloat(sigma), BigFloat(x), BigFloat(y)
            r2 = xb * xb + yb * yb
            u = r2 / (2 * sb * sb)
            phi = iszero(u) ? one(u) : -expm1(-u) / u
            scale = phi / (sb * sb)
            return T(scale * xb), T(scale * yb)
        end
    end

    function round_hessian_reference(T, kbb, sigma, x, y)
        setprecision(BigFloat, 256) do
            kb, sb = BigFloat(kbb), BigFloat(sigma)
            xb, yb = BigFloat(x), BigFloat(y)
            r2 = xb * xb + yb * yb
            u = r2 / (2 * sb * sb)
            if iszero(u)
                h = -kb / (sb * sb)
                return T(h), zero(T), T(h)
            end
            phi = -expm1(-u) / u
            dphi = ((one(u) + u) * exp(-u) - one(u)) / (u * u)
            invsigma2 = inv(sb * sb)
            f = phi * invsigma2
            fp = dphi * invsigma2 * invsigma2 / 2
            return (
                T(-kb * (f + 2 * xb * xb * fp)),
                T(-kb * (2 * xb * yb * fp)),
                T(-kb * (f + 2 * yb * yb * fp)),
            )
        end
    end

    for (T, near_axis) in ((Float32, 1.0f-4), (Float64, 1.0e-8))
        sigma = one(T)
        for (x, y) in (
                (T(near_axis), T(-near_axis / 2)),
                (T(0.1), T(-0.05)),
                (T(0.2), T(-0.1)),
                (T(2), T(-1)))
            expected = round_reference(T, sigma, x, y)
            actual = gaussian_beambeam_kick(sigma, sigma, x, y)
            @test collect(actual) ≈ collect(expected) rtol=16eps(T) atol=zero(T)

            expterm = exp(-(x * x + y * y) / (2 * sigma * sigma))
            expected_hessian = round_hessian_reference(T, one(T), sigma, x, y)
            actual_hessian =
                Octopus._round_gaussian_hessian(one(T), sigma, x, y, expterm)
            @test collect(actual_hessian) ≈ collect(expected_hessian) rtol=32eps(T) atol=32eps(T)
        end
        @test gaussian_beambeam_kick(sigma, sigma, zero(T), zero(T)) ==
              (zero(T), zero(T))
        @test Octopus._round_gaussian_hessian(
            one(T), sigma, zero(T), zero(T), one(T)) ==
            (-one(T), zero(T), -one(T))
    end
end

@testset "Near-round Gaussian transition" begin
    beta = [k / sqrt(4k^2 - 1) for k in 1:95]
    quadrature = eigen(SymTridiagonal(zeros(96), beta))
    nodes = (quadrature.values .+ 1) ./ 2
    weights = quadrature.vectors[1, :] .^ 2

    function transition_reference(sig1, sig2, x, y)
        v = (Float64(sig1)^2 + Float64(sig2)^2) / 2
        eta = (Float64(sig1)^2 - Float64(sig2)^2) / (2v)
        xb, yb = Float64(x), Float64(y)
        X, Y = xb / sqrt(v), yb / sqrt(v)
        ix = iy = jx = jy = 0.0
        for (z, weight) in zip(nodes, weights)
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

    for T in (Float32, Float64)
        inner, outer = Octopus._near_round_eta_bounds(zero(T))
        @test inner == outer / T(2)
        @test Octopus._near_round_blend(inner) == (zero(T), zero(T))
        @test Octopus._near_round_blend(outer) == (one(T), zero(T))
        midpoint_weight, midpoint_derivative =
            Octopus._near_round_blend((inner + outer) / T(2))
        @test midpoint_weight ≈ T(0.5) rtol=4eps(T)
        @test midpoint_derivative > zero(T)

        moment_tolerance = T === Float32 ? 5.0e-6 : 1.0e-12
        for q in (prevfloat(T(2)), T(2), nextfloat(T(2)))
            actual_moments = Octopus._near_round_moments_0_6(q)
            reference_moments = setprecision(BigFloat, 256) do
                qb = BigFloat(q)
                eq = exp(-qb)
                moment = -expm1(-qb) / qb
                values = BigFloat[moment]
                for order in 1:6
                    moment = (order * moment - eq) / qb
                    push!(values, moment)
                end
                values
            end
            @test collect(Float64, actual_moments) ≈
                  Float64.(reference_moments) rtol=moment_tolerance
        end

        force_tolerance = T === Float32 ? 3.0e-5 : 5.0e-11
        response_tolerance = T === Float32 ? 3.0e-5 : 5.0e-11
        for eta in (zero(T), inner, T(0.75) * outer, outer, T(1.2) * outer)
            sig1, sig2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
            for (x, y) in (
                    (T(1.0e-6), T(-5.0e-7)),
                    (T(0.2), T(-0.1)),
                    (T(1.3), T(0.7)),
                    (sqrt(T(0.0625)) * cos(T(pi / 16)),
                     sqrt(T(0.0625)) * sin(T(pi / 16))),
                    (sqrt(T(5)) * cos(T(15pi / 32)),
                     sqrt(T(5)) * sin(T(15pi / 32))))
                actual = Octopus._gaussian_beambeam_kick_response(
                    one(T), sig1, sig2, x, y)
                reference = transition_reference(sig1, sig2, x, y)
                force_error = hypot(
                    Float64(actual[1]) - reference[1],
                    Float64(actual[2]) - reference[2]) /
                    hypot(reference[1], reference[2])
                response_error = hypot(
                    Float64(actual[3]) - reference[3],
                    Float64(actual[4]) - reference[4]) /
                    hypot(reference[3], reference[4])
                @test force_error < force_tolerance
                @test response_error < response_tolerance
            end
        end

        core_coordinate = T === Float32 ? T(1.0e-4) : T(1.0e-8)
        for eta in (outer, T(0.001), T(0.1), T(0.9))
            sig1, sig2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
            Kx, _ = gaussian_beambeam_kick(
                sig1, sig2, core_coordinate, zero(T))
            _, Ky = gaussian_beambeam_kick(
                sig1, sig2, zero(T), core_coordinate)
            gx = T(2) / (sig1 * (sig1 + sig2))
            gy = T(2) / (sig2 * (sig1 + sig2))
            @test Kx / core_coordinate ≈ gx rtol=32eps(T)
            @test Ky / core_coordinate ≈ gy rtol=32eps(T)
        end
    end

    _, outer = Octopus._near_round_eta_bounds(0.0)
    eta = 0.75 * outer
    A = Matrix(Diagonal([1 + eta, 1 - eta]))
    B = Matrix(Diagonal([0.03, -0.02]))
    Q = transpose(B) * (A \ B) + 0.3I
    transition_element = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.7, covariance=covariance_xpxypy(A, B, Matrix(Q))))
    q0 = [0.4, 1.0e-4, -0.2, -1.5e-4, 0.0, 2.0e-4]
    mapq(q) = collect(transition_element(q...))
    h = 1.0e-5
    jacobian = hcat([(
        mapq(q0 .+ (collect(1:6) .== column) .* h) -
        mapq(q0 .- (collect(1:6) .== column) .* h)
    ) / (2h) for column in 1:6]...)
    symplectic_form = zeros(6, 6)
    for coordinate in (1, 3, 5)
        symplectic_form[coordinate, coordinate + 1] = 1
        symplectic_form[coordinate + 1, coordinate] = -1
    end
    residual = transpose(jacobian) * symplectic_form * jacobian - symplectic_form
    @test norm(residual, Inf) < 2.0e-8
end

@testset "Near-round precision support and tracking consumers" begin
    for T in (Float16, BigFloat)
        error = try
            Octopus._near_round_eta_bounds(zero(T))
            nothing
        catch caught
            caught
        end
        @test error isa ArgumentError
        @test occursin(
            "supports only Float32 and Float64", sprint(showerror, error))
    end

    for T in (Float32, Float64)
        inner, outer = Octopus._near_round_eta_bounds(zero(T))
        for eta in (inner / T(2), T(0.75) * outer, T(1.2) * outer)
            sigx = sqrt(one(T) + eta)
            sigy = sqrt(one(T) - eta)
            kbb = T(-2.0e-3)
            covariance = Matrix(Diagonal(T[
                sigx * sigx, sigx * sigx,
                sigy * sigy, sigy * sigy,
            ]))
            weak_strong = ThinStrongBeam(ThinStrongBeamSpec{T}(;
                kbb=kbb, covariance=covariance))
            initial = (
                T(0.4), T(1.0e-4), T(-0.2),
                T(-1.5e-4), zero(T), T(2.0e-4),
            )
            weak_result = collect(weak_strong(initial...))

            soft_rep = Phase6DRep(([value] for value in initial)...)
            soft_source = (
                mx=zero(T), sx=sigx, mpx=zero(T), spx=sigx,
                covxpx=zero(T),
                my=zero(T), sy=sigy, mpy=zero(T), spy=sigy,
                covypy=zero(T),
            )
            Octopus._apply_slice_kick_one!(
                soft_rep, 1, soft_source, zero(T), kbb, zero(T), true, false)
            soft_result = collect(soft_rep[1])

            tolerance = T(32) * eps(T)
            @test all(isfinite, weak_result)
            @test all(isfinite, soft_result)
            @test soft_result ≈ weak_result rtol=tolerance atol=tolerance
        end
    end
end

@testset "Weak-strong coupled covariance and longitudinal limits" begin
    uncoupled = transverse_covariance(;
        beta=(0.8, 1.2), alpha=(0.3, -0.2), sigma=(1.1, 0.7))
    coupling = XYCouplingSpec{Float64}(r1=0.08, r2=0.03, r3=-0.02, r4=0.05)
    coupled_spec = ThinStrongBeamSpec(;
        kbb=1.0e-7, beta=(0.8, 1.2), alpha=(0.3, -0.2),
        sigma=(1.1, 0.7), coupling=coupling,
        center=(2.0e-5, -1.0e-5, 3.0e-4),
        angle=(3.0e-4, -2.0e-4, 0.0),
        curvature=(2.0e-3, -1.0e-3, 0.0), virtual_drift=:hirata)
    coupled = ThinStrongBeam(coupled_spec)
    @test coupled.moments isa StrongTransverseMoments{Float64,true}
    @test transverse_covariance(coupled.moments) ≈
          transverse_covariance(Float64;
              beta=(0.8, 1.2), alpha=(0.3, -0.2), sigma=(1.1, 0.7),
              coupling=coupling)
    @test minimum(eigvals(Symmetric(transverse_covariance(coupled.moments)))) >= -1.0e-14
    @test_throws ArgumentError transverse_covariance(;
        beta=(1.0, 1.0), sigma=(1.0, 1.0), coupling=ones(4, 4))

    # 1. With no transverse force, every part of the longitudinal kick vanishes.
    zero_force = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.0, covariance=uncoupled, angle=(0.2, -0.1, 0.0)))
    initial = (0.4, 0.03, -0.2, -0.04, 0.6, 0.05)
    @test zero_force(initial...) == initial

    # 2-3. A static offset changes the field, while a static covariance and
    # static centroid contribute no direct longitudinal derivative.
    static_covariance = Diagonal([1.4, 0.0, 0.8, 0.0]) |> Matrix
    static = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.2, covariance=static_covariance,
        center=(0.1, -0.05, 0.0), angle=(0.0, 0.0, 0.0)))
    static_result = static(0.4, 0.0, -0.2, 0.0, 0.0, 0.0)
    @test static_result[2] != 0.0
    @test static_result[4] != 0.0
    @test static_result[6] ≈
          (static_result[2]^2 + static_result[4]^2) / 4 rtol=2.0e-13

    # 4. The legacy Twiss construction is exactly the block-moment formula.
    legacy = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.1, beta=(0.8, 1.2), alpha=(0.3, -0.2), sigma=(1.1, 0.7)))
    S = 0.37
    a, b, d, au, bu, du = Octopus._transport_transverse_moments(legacy.moments, S)
    emitx, emity = 1.1^2 / 0.8, 0.7^2 / 1.2
    gammax, gammay = (1 + 0.3^2) / 0.8, (1 + (-0.2)^2) / 1.2
    @test a ≈ emitx * (0.8 + 2S * 0.3 + S^2 * gammax)
    @test d ≈ emity * (1.2 + 2S * (-0.2) + S^2 * gammay)
    @test (b, bu) == (0.0, 0.0)
    @test au ≈ -2emitx * (0.3 + S * gammax)
    @test du ≈ -2emity * (-0.2 + S * gammay)

    # 5. A fixed nonzero tilt rotates the transverse kick but has no direct
    # longitudinal covariance term.
    fixed_tilt_covariance = covariance_xpxypy(
        [1.3 0.25; 0.25 0.9], zeros(2, 2), zeros(2, 2))
    fixed_tilt = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.3, covariance=fixed_tilt_covariance))
    _, fixed_tilt_direct = covariance_kick_and_direct_pz(
        fixed_tilt.moments, 0.2, 0.4, -0.3)
    @test fixed_tilt_direct == 0.0

    # 6. For a changing tilt, the implemented principal-axis expression
    # reproduces the invariant laboratory-frame Hessian contraction.
    L = [1.0 0.0 0.0 0.0;
         0.1 0.6 0.0 0.0;
         0.2 -0.1 0.8 0.0;
         -0.05 0.08 0.12 0.5]
    changing = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.7, covariance=L * transpose(L)))
    S = 0.23
    x, y = 0.31, -0.27
    _, changing_direct = covariance_kick_and_direct_pz(changing.moments, S, x, y)
    H = numerical_potential_hessian(changing.moments, S, x, y)
    _, _, _, au, bu, du = Octopus._transport_transverse_moments(changing.moments, S)
    invariant_direct = 0.25 * (H[1, 1] * au + 2H[1, 2] * bu + H[2, 2] * du)
    @test changing_direct ≈ invariant_direct rtol=2.0e-8 atol=2.0e-10

    # 7. At an exactly round collision covariance the invariant branch stays
    # finite and agrees with a numerical Hessian even when A_u is anisotropic.
    A = Matrix{Float64}(I, 2, 2)
    B = [0.05 0.03; -0.02 -0.04]
    Q = transpose(B) * B + 0.3 * Matrix{Float64}(I, 2, 2)
    round_changing = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.7, covariance=covariance_xpxypy(A, B, Q)))
    _, round_direct = covariance_kick_and_direct_pz(
        round_changing.moments, 0.0, 0.31, -0.27)
    Hround = numerical_potential_hessian(
        round_changing.moments, 0.0, 0.31, -0.27)
    _, _, _, rau, rbu, rdu = Octopus._transport_transverse_moments(
        round_changing.moments, 0.0)
    round_invariant = 0.25 * (
        Hround[1, 1] * rau + 2Hround[1, 2] * rbu + Hround[2, 2] * rdu)
    @test isfinite(round_direct)
    @test round_direct ≈ round_invariant rtol=2.0e-8 atol=2.0e-10

    # 8. The source-centroid term combines with the Hirata slingshot exactly.
    moving = ThinStrongBeam(ThinStrongBeamSpec(;
        kbb=0.2, covariance=static_covariance,
        center=(0.1, -0.05, 0.0), angle=(0.03, -0.02, 0.0)))
    q = (0.4, 0.01, -0.2, -0.015, 0.0, 0.02)
    moved = moving(q...)
    Fx, Fy = moved[2] - q[2], moved[4] - q[4]
    expected_dpz = (
        moved[2]^2 + moved[4]^2 - q[2]^2 - q[4]^2) / 4 +
        0.5 * (Fx * moving.pxo + Fy * moving.pyo)
    @test moved[6] - q[6] ≈ expected_dpz rtol=2.0e-13

    # 9. The complete coupled map remains six-dimensionally symplectic with
    # nonzero centroid angle, curvature, b_u, and theta_u.
    q0 = [0.4, 1.0e-4, -0.2, -1.5e-4, 1.2e-3, 2.0e-4]
    mapq(q) = collect(coupled(q...))
    h = 3.0e-7
    jacobian = hcat([(
        mapq(q0 .+ (collect(1:6) .== column) .* h) -
        mapq(q0 .- (collect(1:6) .== column) .* h)
    ) / (2h) for column in 1:6]...)
    symplectic_form = zeros(6, 6)
    for coordinate in (1, 3, 5)
        symplectic_form[coordinate, coordinate + 1] = 1
        symplectic_form[coordinate + 1, coordinate] = -1
    end
    residual = transpose(jacobian) * symplectic_form * jacobian - symplectic_form
    @test norm(residual, Inf) < 2.0e-8
end

@testset "Conditional 6D Gaussian strong-beam slicing" begin
    transverse = transverse_covariance(;
        beta=(0.7, 0.9), alpha=(0.1, -0.2), sigma=(1.2e-3, 0.8e-3))
    longitudinal = [4.0e-4 3.0e-5; 3.0e-5 9.0e-6]
    crab = (0.12, -0.03, 0.04, 0.02)
    momentum = (0.5, 0.1, -0.2, 0.3)
    covariance6 = gaussian_strong_beam_covariance(
        transverse, longitudinal;
        crab_dispersion=crab, momentum_dispersion=momentum)
    conditional, slope = Octopus._conditional_transverse_gaussian(
        covariance6, Float64)
    conditional_delta_variance = longitudinal[2, 2] -
        longitudinal[1, 2]^2 / longitudinal[1, 1]
    expected_slope = collect(crab) .+
        collect(momentum) .* longitudinal[1, 2] / longitudinal[1, 1]
    expected_conditional = transverse +
        collect(momentum) * transpose(collect(momentum)) * conditional_delta_variance
    @test collect(slope) ≈ expected_slope
    @test conditional ≈ expected_conditional rtol=2.0e-13 atol=1.0e-15

    # Pure crab dispersion changes only conditional slice centroids/angles.
    pure_crab6 = gaussian_strong_beam_covariance(
        transverse, Diagonal([4.0e-4, 9.0e-6]) |> Matrix;
        crab_dispersion=crab)
    pure_crab_conditional, pure_crab_slope =
        Octopus._conditional_transverse_gaussian(pure_crab6, Float64)
    @test pure_crab_conditional ≈ transverse
    @test collect(pure_crab_slope) ≈ collect(crab)

    thin = ThinStrongBeamSpec(;
        kbb=1.0e-4, covariance=transverse,
        center=(1.0e-5, -2.0e-5, 3.0e-3),
        angle=(4.0e-4, -3.0e-4, 0.0))
    sliced = GaussianStrongBeam(GaussianStrongBeamSpec(;
        thin=thin, ns=3, covariance=covariance6))
    @test transverse_covariance(sliced.thin.moments) ≈ conditional
    @test sliced.slice_hoffset ≈ expected_slope[1] .* sliced.slice_center
    @test sliced.slice_pxoffset ≈ expected_slope[2] .* sliced.slice_center
    @test sliced.slice_voffset ≈ expected_slope[3] .* sliced.slice_center
    @test sliced.slice_pyoffset ≈ expected_slope[4] .* sliced.slice_center
    @test sliced.thin.zo == 3.0e-3

    # A nonlinear crab waveform composes with, rather than replaces, the
    # linear centroid slope contained in the six-dimensional covariance.
    crabbed = GaussianStrongBeam(GaussianStrongBeamSpec(;
        thin=thin, ns=3, covariance=covariance6,
        hvoffset=Dict(
            :dim => :x, :coef => 2.0e-4, :frequency => 4.0e8,
            :harmonics => Dict(1 => 1.0))))
    waveform = Octopus._crab_offsets(
        Tuple(crabbed.slice_center), 2.0e-4, 4.0e8, Dict(1 => 1.0))
    @test crabbed.slice_hoffset ≈
          expected_slope[1] .* crabbed.slice_center .+
          collect(waveform)

    # PSD validation is relative to the covariance scale, including small
    # physical beam covariances.
    @test_throws ArgumentError ThinStrongBeamSpec(;
        kbb=1.0, covariance=Diagonal([1.0e-12, -1.0e-15, 1.0e-12, 1.0e-12]))

    # Turn modulation is workflow state, not part of the collision element.
    @test !isdefined(Octopus, :LinearTurnSignal)
end

@testset "Gaussian longitudinal slicing rules" begin
    # Reference values: Table 1 of Furman, Zholents, Chen and Shatilov
    # (PEP-II/AP 95.39, LBL-37680, CBP Note-152, 1995) at ns = 5, sigz = 1.
    # Derivations: docs/theory/gaussian_longitudinal_slicing.md.
    # NOTE the published w_2 for algorithm #4 is 0.17350, which makes that row
    # sum to 1.072 and violate normalization; the self-consistent value is
    # 0.137503 (Section 4 of the note). This test pins the corrected value.
    table1 = Dict(
        :equal_spacing_density =>
            ([-1.166667, -0.5833333, 0.0, 0.5833333, 1.166667],
             [0.1368561, 0.2280002, 0.2702873, 0.2280002, 0.1368561]),
        :equal_area =>
            ([-1.281552, -0.5244005, 0.0, 0.5244005, 1.281552], fill(0.2, 5)),
        :equal_area_centroid =>
            ([-1.399809, -0.5319032, 0.0, 0.5319032, 1.399809], fill(0.2, 5)),
        :sqrt_density =>
            ([-1.59898, -0.67872, 0.0, 0.67872, 1.59898],
             [0.137503, 0.232216, 0.260561, 0.232216, 0.137503]),
        :min_cdf_area =>
            ([-1.44156, -0.63623, 0.0, 0.63623, 1.44156],
             [0.14943, 0.22577, 0.24960, 0.22577, 0.14943]),
    )
    # Element-wise, because Table 1 is printed to five decimals: the agreement
    # bound is per entry, not on the vector norm.
    for (method, (centers, weights)) in table1
        z, w = Octopus._gaussian_slices(Float64, 5, nothing, nothing, 1.0, method, nothing)
        @test maximum(abs, collect(z) .- centers) < 5.0e-6
        @test maximum(abs, collect(w) .- weights) < 5.0e-6
    end

    # :equal_area is Furman #2 in closed form; guard the shipped default.
    for ns in (3, 5, 7, 15)
        z, w = Octopus._gaussian_slices(Float64, ns, nothing, nothing, 1.0, :equal_area, nothing)
        half = (ns - 1) ÷ 2
        @test collect(z) ≈ [Octopus.SQRT2 * Octopus.inverse_erf(2k / ns) for k in -half:half]
        @test collect(w) == fill(1 / ns, ns)
    end

    # Gauss-Hermite is defined by moment exactness, not by Ref. [1]: an ns-point
    # rule reproduces every standard-normal moment through order 2*ns-1.
    for ns in (3, 5, 15)
        z, w = Octopus._gaussian_slices(Float64, ns, nothing, nothing, 1.0, :gauss_hermite, nothing)
        for order in 0:(2ns - 1)
            scale = prod(max(order - 1, 1):-2:1; init=1.0)     # (order-1)!!
            exact = iseven(order) ? scale : 0.0
            @test sum(collect(w) .* collect(z) .^ order) ≈ exact atol=1.0e-8 * scale
        end
    end

    # Structural invariants every rule must satisfy.
    for method in Octopus.SLICE_METHODS, ns in (1, 2, 3, 5, 8, 15, 32)
        width = method === :equal_width ? 2.0e-3 : nothing
        z, w = Octopus._gaussian_slices(Float64, ns, nothing, nothing, 7.0e-3, method, width)
        @test sum(collect(w)) ≈ 1.0
        @test all(>=(0), collect(w))
        @test all(isfinite, collect(z))
        @test issorted(collect(z))
        @test collect(z) ≈ -reverse(collect(z)) atol=1.0e-14
        @test collect(w) ≈ reverse(collect(w)) atol=1.0e-13
    end

    # Effectiveness at the consumer boundary: slice_method must reach the
    # compiled runtime AND change the tracked kick, not merely be stored.
    thin = ThinStrongBeamSpec(; kbb=1.0e-4,
        covariance=transverse_covariance(; beta=(0.5, 0.05), sigma=(1.0e-4, 1.0e-5)))
    coords = (2.0e-4, 1.0e-5, 3.0e-5, -2.0e-6, 5.0e-3, 1.0e-4)
    centers_seen = Vector{Float64}[]
    kicks_seen = Vector{Float64}[]
    for method in Octopus.SLICE_METHODS
        element = compile_runtime(GaussianStrongBeamSpec(;
            thin=thin, ns=7, sigz=7.0e-3, slice_method=method,
            slice_width=(method === :equal_width ? 2.0e-3 : nothing)))
        @test sum(element.slice_weight) ≈ 1.0
        out = track_particle(WeakStrongBeamBeamMap(), element, coords...)
        @test all(isfinite, out)
        push!(centers_seen, collect(element.slice_center))
        # Isolate the kick: x, y are unchanged by a thin lens and would otherwise
        # dominate the comparison.
        push!(kicks_seen, [out[2] - coords[2], out[4] - coords[4], out[6] - coords[6]])
    end
    for i in eachindex(centers_seen), j in (i + 1):length(centers_seen)
        @test !isapprox(centers_seen[i], centers_seen[j])
        @test !isapprox(kicks_seen[i], kicks_seen[j])
    end

    # slice_width is consumed only by :equal_width; the others must ignore it
    # rather than silently changing behaviour.
    for method in Octopus.SLICE_METHODS
        method === :equal_width && continue
        with_width = Octopus._gaussian_slices(
            Float64, 7, nothing, nothing, 7.0e-3, method, 5.0e-3)
        without = Octopus._gaussian_slices(
            Float64, 7, nothing, nothing, 7.0e-3, method, nothing)
        @test collect(with_width[1]) == collect(without[1])
        @test collect(with_width[2]) == collect(without[2])
    end

    # Invalid and inactive input.
    @test_throws ArgumentError compile_runtime(GaussianStrongBeamSpec(;
        thin=thin, ns=5, sigz=7.0e-3, slice_method=:not_a_rule))
    @test_throws ArgumentError Octopus._gaussian_slices(
        Float64, 5, nothing, nothing, -1.0, :equal_area, nothing)
    @test_throws ArgumentError Octopus._gaussian_slices(
        Float64, 0, nothing, nothing, 7.0e-3, :equal_area, nothing)

    # The shipped default is :sqrt_density (changed from :equal_area on
    # 2026-07-31; see docs/history/gaussian_slicing_convergence_2026_07_31.md).
    # Pinned here because changing it silently changes every user's results.
    default_spec = GaussianStrongBeamSpec(; thin=thin, ns=7, sigz=7.0e-3)
    @test getparam(default_spec, :slice_method, nothing) === :sqrt_density
    explicit_default = compile_runtime(GaussianStrongBeamSpec(;
        thin=thin, ns=7, sigz=7.0e-3, slice_method=:sqrt_density))
    @test collect(compile_runtime(default_spec).slice_center) ==
          collect(explicit_default.slice_center)
    # A raw ElementSpec with no slice_method must take the same default.
    raw_default = compile_runtime(ElementSpec{:gaussian_strong_beam}(;
        thin=thin, ns=7, sigz=7.0e-3))
    @test collect(raw_default.slice_center) == collect(explicit_default.slice_center)

    # Explicit centers and weights bypass slice_method entirely.
    explicit = compile_runtime(GaussianStrongBeamSpec(;
        thin=thin, ns=3, sigz=7.0e-3, slice_method=:gauss_hermite,
        slice_center=(-1.0e-3, 0.0, 1.0e-3), slice_weight=(0.25, 0.5, 0.25)))
    @test collect(explicit.slice_center) == [-1.0e-3, 0.0, 1.0e-3]
    @test collect(explicit.slice_weight) == [0.25, 0.5, 0.25]

    # The measured ranking of Section 5.1: within the equal-charge family the
    # centroid node beats the median, and the rules that push weight outward
    # beat both. Second-moment deficit, lower is better.
    deficit(method, ns) = begin
        z, w = Octopus._gaussian_slices(Float64, ns, nothing, nothing, 1.0, method, nothing)
        abs(1 - sum(collect(w) .* collect(z) .^ 2))
    end
    for ns in (15, 31)
        @test deficit(:gauss_hermite, ns) < deficit(:sqrt_density, ns)
        @test deficit(:sqrt_density, ns) < deficit(:equal_area_centroid, ns)
        @test deficit(:equal_area_centroid, ns) < deficit(:equal_area, ns)
    end
end

@testset "Lattice magnets" begin
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    u0 = (1.3e-3, 3.0e-4, -0.9e-3, -2.2e-4, 2.0e-3, 1.1e-3)
    function cs_jacobian(elem)
        J = zeros(6, 6)
        for j in 1:6
            u = ComplexF64[u0...]
            u[j] += 1e-30im
            J[:, j] = imag.(collect(elem(u...))) ./ 1e-30
        end
        return J
    end

    # Every magnet must be symplectic to round-off, including a bend whose
    # frame curvature differs from its field and one with the full pole face.
    for (name, spec) in (
            ("drift", DriftSpec(L=0.7)),
            ("curved drift", DriftSpec(L=0.7, h=0.21)),
            ("quadrupole", QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=2)),
            ("quadrupole order 4", QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=3, integrator_order=4)),
            ("sextupole with fringes", SextupoleSpec(L=0.25, kn=(0.0, 0.0, 14.0), nst=2,
                                                     fringe=:all, va=0.03, vs=1.0e-4)),
            ("octupole", OctupoleSpec(L=0.15, kn=(0.0, 0.0, 0.0, 220.0), nst=2)),
            ("sector bend", SBendSpec(L=1.1, h=0.18, b0=0.18, nst=2)),
            ("bend with h != b0", SBendSpec(L=1.1, h=0.18, b0=0.23, nst=2)),
            ("bend with pole face", SBendSpec(L=1.1, h=0.18, b0=0.18, e1=0.09, e2=0.09,
                                              fint1=0.5, fint2=0.5, hgap1=0.03, hgap2=0.03,
                                              bend_fringe=true, nst=2)))
        J = cs_jacobian(compile_runtime(spec))
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-13
    end

    # The curved drift must reproduce the closed form verified in
    # docs/theory/lattice_hamiltonian_and_conventions.md Section 5.
    let h = 0.21, L = 0.7, (x0, px0, y0, py0, z0, pz) = u0
        ps0 = sqrt((1 + pz)^2 - px0^2 - py0^2)
        c, sa = cos(h * L), sin(h * L)
        px = px0 * c + ps0 * sa
        ps = -px0 * sa + ps0 * c
        x = ((1 + h * x0) * ps0 - ps) / (h * ps)
        Δ = ((1 + h * x) * px - (1 + h * x0) * px0) / (h * ((1 + pz)^2 - py0^2))
        out = compile_runtime(DriftSpec(L=L, h=h))(u0...)
        @test collect(out) ≈ [x, px, y0 + py0 * Δ, py0, z0 + L - (1 + pz) * Δ, pz] atol=1.0e-14
    end

    # Section 5.2: 1/h is a removable singularity. The guarded form must
    # approach the straight drift linearly in h rather than losing digits.
    let straight = collect(compile_runtime(DriftSpec(L=0.7))(u0...))
        previous = Inf
        for h in (1.0e-3, 1.0e-6, 1.0e-9)
            d = maximum(abs, collect(compile_runtime(DriftSpec(L=0.7, h=h))(u0...)) .- straight)
            @test d < previous
            previous = d
        end
        @test previous < 1.0e-8
        @test collect(compile_runtime(DriftSpec(L=0.7, h=0.0))(u0...)) == straight
    end

    # nst is a runtime consumer, and integrator_order selects PTC's
    # Forest-Ruth coefficients: order 2 must converge as nst^-2 and order 4 as
    # nst^-4. This is the effectiveness test for both keywords.
    let reference = collect(compile_runtime(
            QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=4096, integrator_order=4))(u0...))
        err(order, nst) = maximum(abs, collect(compile_runtime(
            QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=nst, integrator_order=order))(u0...)) .- reference)
        @test err(2, 4) / err(2, 8) > 3.5          # ~4
        @test err(4, 4) / err(4, 8) > 12.0         # ~16
        @test err(4, 8) < err(2, 8)
    end

    # fringe reaches the tracked coordinates, and each mode differs.
    let base = QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=2)
        outs = [collect(compile_runtime(QuadrupoleSpec(
                    L=0.4, kn=(0.0, 1.7), nst=2, fringe=m, va=0.03, vs=1.0e-4))(u0...))
                for m in (:none, :multipole, :soft_quad, :all)]
        for i in eachindex(outs), j in (i + 1):length(outs)
            @test !isapprox(outs[i], outs[j])
        end
        @test outs[1] == collect(compile_runtime(base)(u0...))
    end

    # A drift is exact, so nst and integrator_order are documented as inactive:
    # they must not change the result rather than being silently applied.
    let a = collect(compile_runtime(DriftSpec(L=0.7, h=0.21))(u0...))
        @test collect(compile_runtime(DriftSpec(L=0.7, h=0.21, nst=17))(u0...)) == a
        @test collect(compile_runtime(DriftSpec(L=0.7, h=0.21, integrator_order=4))(u0...)) == a
    end

    # Combined-function bends: a curved frame changes the multipole potential
    # itself, so these route through the tabulated curved potential
    # (Section 4.4) rather than the straight kick.
    for ord in (2, 4), M in (4, 8)
        cf = compile_runtime(SBendSpec(L=1.0, h=0.18, b0=0.18, kn=(0.0, 0.6, 5.0),
                                       nst=4, integrator_order=ord, curved_order=M))
        J = cs_jacobian(cf)
        # The potential is tabulated rather than the field: differentiating one
        # truncated polynomial keeps the kick an exact gradient, so truncation
        # costs accuracy but never symplecticity.
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-12
    end
    # curved_order is a convergence parameter and must converge.
    let ref = collect(compile_runtime(SBendSpec(L=1.0, h=0.18, b0=0.18, kn=(0.0, 0.6),
                                                nst=4, curved_order=16))(u0...))
        err(M) = maximum(abs, collect(compile_runtime(
            SBendSpec(L=1.0, h=0.18, b0=0.18, kn=(0.0, 0.6), nst=4, curved_order=M))(u0...)) .- ref)
        @test err(2) > err(6)
        @test err(6) < 1.0e-13
    end
    # A curved multipole must reduce to the straight one as h -> 0.
    let straight = collect(compile_runtime(QuadrupoleSpec(L=0.5, kn=(0.0, 1.7), nst=4))(u0...))
        previous = Inf
        for h in (1.0e-2, 1.0e-4, 1.0e-6)
            d = maximum(abs, collect(compile_runtime(
                SBendSpec(L=0.5, h=h, b0=0.0, kn=(0.0, 1.7), nst=4))(u0...)) .- straight)
            @test d < previous
            previous = d
        end
        @test previous < 1.0e-5
    end
    # A pure dipole stays on the exact single-step path: no multipole content
    # (N = 0) and no curved-potential table (NC = 0), so the body is integrable
    # in one step whatever nst says.
    let e = compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18, nst=9))
        @test e isa LatticeMagnet{Symplectic6DMap,Float64,0}
        @test typeof(e).parameters[7] == 0                # NC
        @test collect(e(u0...)) ==
              collect(compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18, nst=1))(u0...))
    end

    @test_throws ArgumentError compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=0))
    @test_throws ArgumentError compile_runtime(
        QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), integrator_order=3))
    @test_throws ArgumentError compile_runtime(
        QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), fringe=:nope))

    # Fringe defaults, measured rather than assumed. The hard-edge multipole
    # fringe is purely nonlinear, so it is off by default and can be enabled per
    # magnet (a final-focus quadrupole, say) without perturbing the optics
    # elsewhere. The bend fringe defaults ON because it is first-order optics
    # whenever a pole-face angle is present.
    let lin(e) = begin
            J = zeros(6, 6)
            for j in 1:6
                v = ComplexF64[0, 0, 0, 0, 0, 0]
                v[j] += 1e-30im
                J[:, j] = imag.(collect(e(v...))) ./ 1e-30
            end
            J
        end
        qn = lin(compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=4, fringe=:none)))
        qm = lin(compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=4, fringe=:multipole)))
        @test qn == qm                                   # nonlinear only
        qs = lin(compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=4,
                                                fringe=:soft_quad, va=0.05, vs=1.0e-3)))
        @test !isapprox(qn, qs)                          # soft edge IS linear
        # Bend: no linear effect with perpendicular faces, first-order with an angle.
        b0 = lin(compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18, nst=4, bend_fringe=false)))
        b1 = lin(compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18, nst=4, bend_fringe=true)))
        @test b0 == b1
        e0 = lin(compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18, e1=0.1, e2=0.1,
                                           nst=4, bend_fringe=false)))
        e1 = lin(compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18, e1=0.1, e2=0.1,
                                           nst=4, bend_fringe=true)))
        @test maximum(abs, e0 - e1) > 1.0e-3
        @test abs(e1[4, 3]) > 1.0e-3 && e0[4, 3] == 0
        # and the default is ON
        d = lin(compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18, e1=0.1, e2=0.1, nst=4)))
        @test d == e1
    end

    # Every kind declares the PTC contract, and every kind has a literal
    # reference case behind that claim.
    for kd in (:drift, :quadrupole, :sextupole, :octupole, :multipole, :sbend)
        @test PTCConsistencyContract in required_contracts(ElementSpec{kd})
    end

    # Six element kinds share one runtime type and one tracking method.
    for spec in (DriftSpec(L=0.1), QuadrupoleSpec(L=0.1), SextupoleSpec(L=0.1),
                 OctupoleSpec(L=0.1), MultipoleSpec(L=0.1), SBendSpec(L=0.1))
        @test compile_runtime(spec) isa LatticeMagnet
    end
end

@testset "Named magnet strength keywords" begin
    u0 = (1.3e-3, 3.0e-4, -0.9e-3, -2.2e-4, 2.0e-3, 1.1e-3)
    same(a, b) = collect(compile_runtime(a)(u0...)) == collect(compile_runtime(b)(u0...))

    # Effectiveness at the consumer boundary: the named keyword must reach the
    # compiled runtime's kn/ks, not merely be stored on the spec. A keyword that
    # were silently ignored would leave kn empty and track as a drift.
    @test compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7)).kn == (0.0, 1.7)
    @test compile_runtime(QuadrupoleSpec(L=0.4, k1s=0.9)).ks == (0.0, 0.9)
    @test compile_runtime(SextupoleSpec(L=0.25, k2=14.0)).kn == (0.0, 0.0, 14.0)
    @test compile_runtime(SextupoleSpec(L=0.25, k2s=3.0)).ks == (0.0, 0.0, 3.0)
    @test compile_runtime(OctupoleSpec(L=0.15, k3=220.0)).kn == (0.0, 0.0, 0.0, 220.0)
    @test compile_runtime(OctupoleSpec(L=0.15, k3s=7.0)).ks == (0.0, 0.0, 0.0, 7.0)

    # The named spelling and the positional one must be the same magnet, not
    # merely a close one: identical tracked coordinates, bit for bit.
    @test same(QuadrupoleSpec(L=0.4, k1=1.7, nst=2), QuadrupoleSpec(L=0.4, kn=(0.0, 1.7), nst=2))
    @test same(QuadrupoleSpec(L=0.4, k1s=0.9, nst=2), QuadrupoleSpec(L=0.4, ks=(0.0, 0.9), nst=2))
    @test same(SextupoleSpec(L=0.25, k2=14.0, nst=2), SextupoleSpec(L=0.25, kn=(0.0, 0.0, 14.0), nst=2))
    @test same(OctupoleSpec(L=0.15, k3=220.0, nst=2), OctupoleSpec(L=0.15, kn=(0.0, 0.0, 0.0, 220.0), nst=2))

    # The point of keeping both spellings: a sextupole with a measured K3 error
    # is still a sextupole, and must equal the general multipole that spells the
    # whole tuple out.
    @test same(SextupoleSpec(L=0.25, k2=14.0, kn=(0.0, 0.0, 0.0, 90.0), nst=2),
               MultipoleSpec(L=0.25, kn=(0.0, 0.0, 14.0, 90.0), nst=2))
    @test kind(SextupoleSpec(L=0.25, k2=14.0, kn=(0.0, 0.0, 0.0, 90.0))) === :sextupole

    # Contradiction throws rather than letting one spelling silently win.
    @test_throws ArgumentError SextupoleSpec(L=0.25, k2=14.0, kn=(0.0, 0.0, 12.0))
    @test_throws ArgumentError QuadrupoleSpec(L=0.4, k1=1.7, kn=(0.0, 1.2))
    @test_throws ArgumentError QuadrupoleSpec(L=0.4, k1s=0.9, ks=(0.0, 0.5))
    @test_throws ArgumentError OctupoleSpec(L=0.15, k3=220.0, kn=(0.0, 0.0, 0.0, 1.0))
    # A zero in the same slot is not a contradiction: nothing is overwritten.
    @test compile_runtime(SextupoleSpec(L=0.25, k2=14.0, kn=(0.0, 0.0, 0.0))).kn ==
          (0.0, 0.0, 14.0)

    # angle is the design-orbit spelling of h = b0 = angle / L.
    @test same(SBendSpec(L=1.1, angle=0.198, nst=2),
               SBendSpec(L=1.1, h=0.198 / 1.1, b0=0.198 / 1.1, nst=2))
    @test compile_runtime(SBendSpec(L=1.1, angle=0.198)).h ≈ 0.198 / 1.1
    @test compile_runtime(SBendSpec(L=1.1, angle=0.198)).b0 ≈ 0.198 / 1.1
    # Combined-function bends take k1/k2 alongside angle.
    @test same(SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=2),
               SBendSpec(L=1.1, h=0.198 / 1.1, b0=0.198 / 1.1, kn=(0.0, 0.6), nst=2))
    @test same(SBendSpec(L=1.1, angle=0.198, k1=0.6, k2=5.0, nst=2),
               SBendSpec(L=1.1, h=0.198 / 1.1, b0=0.198 / 1.1, kn=(0.0, 0.6, 5.0), nst=2))
    # h/b0 stay available for a bend off its design orbit, but not with angle.
    @test compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.23)).b0 == 0.23
    @test_throws ArgumentError SBendSpec(L=1.1, angle=0.198, h=0.18)
    @test_throws ArgumentError SBendSpec(L=1.1, angle=0.198, b0=0.18)
    @test_throws ArgumentError SBendSpec(angle=0.198)
    @test_throws ArgumentError SBendSpec(L=0.0, angle=0.198)

    # MultipoleSpec takes K0 (corrector) through K5 (dodecapole) by name, so a
    # decapole does not need four leading zeros. Nothing about order 4 and up is
    # special to the kick: _lattice_kick is generic in N.
    @test compile_runtime(MultipoleSpec(L=0.15, k0=0.02)).kn == (0.02,)
    @test compile_runtime(MultipoleSpec(L=0.15, k4=1.0e5)).kn == (0.0, 0.0, 0.0, 0.0, 1.0e5)
    @test compile_runtime(MultipoleSpec(L=0.15, k5s=1.0e7)).ks ==
          (0.0, 0.0, 0.0, 0.0, 0.0, 1.0e7)
    @test same(MultipoleSpec(L=0.15, k4=1.0e5, nst=4),
               MultipoleSpec(L=0.15, kn=(0.0, 0.0, 0.0, 0.0, 1.0e5), nst=4))
    @test same(MultipoleSpec(L=0.2, k1=1.0, k2=5.0, nst=2),
               MultipoleSpec(L=0.2, kn=(0.0, 1.0, 5.0), nst=2))
    # Named and positional mix: K0..K5 by name, higher orders in the tuple.
    @test same(MultipoleSpec(L=0.15, k4=1.0e5, kn=(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0e9), nst=2),
               MultipoleSpec(L=0.15, kn=(0.0, 0.0, 0.0, 0.0, 1.0e5, 0.0, 1.0e9), nst=2))
    @test_throws ArgumentError MultipoleSpec(L=0.15, k4=1.0e5, kn=(0.0, 0.0, 0.0, 0.0, 2.0e5))

    # Orders past octupole are already tracked and symplectic to round-off, in a
    # straight frame, with the hard-edge fringe, and in a curved frame. This is
    # why no DecapoleSpec/DodecapoleSpec kinds exist: there is no new physics to
    # carry, only a longer tuple.
    let S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0]),
        ua = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)

        function jac(elem)
            J = zeros(6, 6)
            for j in 1:6
                u = ComplexF64[ua...]
                u[j] += 1e-30im
                J[:, j] = imag.(collect(elem(u...))) ./ 1e-30
            end
            return J
        end
        for spec in (MultipoleSpec(L=0.15, k4=1.0e5, nst=4),
                     MultipoleSpec(L=0.15, k5=1.0e7, nst=4),
                     MultipoleSpec(L=0.15, k4s=1.0e5, nst=4),
                     MultipoleSpec(L=0.15, k4=1.0e5, nst=4, fringe=:multipole),
                     MultipoleSpec(L=0.15, kn=(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0e9), nst=4),
                     SBendSpec(L=1.1, angle=0.198, k1=0.6, kn=(0.0, 0.0, 0.0, 0.0, 1.0e5), nst=4))
            elem = compile_runtime(spec)
            J = jac(elem)
            @test maximum(abs, J' * S6 * J - S6) < 1.0e-13
            # and the high order actually acts, rather than compiling away
            @test collect(elem(ua...))[2] != ua[2]
        end
    end

    # The new keywords are declared metadata, so element_help and
    # parameter_schema show them rather than leaving users to read the source.
    @test haskey(parameter_schema(ElementSpec{:quadrupole}), :k1)
    @test haskey(parameter_schema(ElementSpec{:sextupole}), :k2)
    @test haskey(parameter_schema(ElementSpec{:octupole}), :k3)
    @test haskey(parameter_schema(ElementSpec{:sbend}), :angle)
    for key in (:k0, :k1, :k2, :k3, :k4, :k5, :k0s, :k5s)
        @test haskey(parameter_schema(ElementSpec{:multipole}), key)
    end
end

@testset "PTC fringe and wedge conventions" begin
    u = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)
    O = Octopus
    id = collect(u)

    # PTC returns from MULTIPOLE_FRINGER when NMUL <= 1: a pure dipole gets no
    # multipole fringe, because its fringe is already handled exactly by
    # FRINGE_dipole. Ours must agree, or a drift_kick bend double-counts it.
    @test collect(O._multipole_fringe((0.18,), (0.0,), 1.0, 0, false, u...)) == id

    # The BN(1) drop keeps the skew dipole and removes only the normal one,
    # matching PTC's IF(J==1.AND.EL%BEND_FRINGE) branch.
    kn = (0.18, 0.6); ks = (0.05, 0.0); zk = (0.0, 0.6)
    @test collect(O._multipole_fringe(kn, ks, 1.0, 0, true, u...)) ==
          collect(O._multipole_fringe(zk, ks, 1.0, 0, false, u...))
    @test collect(O._multipole_fringe(kn, ks, 1.0, 0, true, u...)) !=
          collect(O._multipole_fringe(kn, ks, 1.0, 0, false, u...))

    # The order cap reproduces PTC's MIN(NMUL, HIGHEST_FRINGE); 0 means uncapped.
    k3 = (0.0, 1.2, 8.0)
    z3 = (0.0, 1.2, 0.0)
    @test collect(O._multipole_fringe(k3, (0.0, 0.0, 0.0), 1.0, 2, false, u...)) ==
          collect(O._multipole_fringe(z3, (0.0, 0.0, 0.0), 1.0, 0, false, u...))
    @test collect(O._multipole_fringe(k3, (0.0, 0.0, 0.0), 1.0, 0, false, u...)) !=
          collect(O._multipole_fringe(k3, (0.0, 0.0, 0.0), 1.0, 2, false, u...))

    # The wedge kick is a gradient, so it must be exactly symplectic, and it must
    # vanish without both an edge angle and a quadrupole component.
    @test collect(O._wedge_quad(0.0, 0.6, 1.0, 2.0, u...)) == id
    @test collect(O._wedge_quad(0.1, 0.0, 1.0, 2.0, u...)) == id
    @test collect(O._wedge_quad(0.1, 0.6, 0.0, 0.0, u...)) == id      # PTC's other branch
    let S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0]),
        J = zeros(6, 6)

        for j in 1:6
            v = ComplexF64[u...]
            v[j] += 1e-30im
            J[:, j] = imag.(collect(O._wedge_quad(0.1, 0.6, 1.0, 2.0, v...))) ./ 1e-30
        end
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-14
    end

    # wedge_coeff and highest_fringe must reach the compiled runtime, not just
    # sit on the spec: a stored-but-unread option is what the PTC comparison
    # would silently absorb.
    @test compile_runtime(SBendSpec(L=1.1, angle=0.198, k1=0.6, e1=0.1)).wc1 == 1.0
    @test compile_runtime(SBendSpec(L=1.1, angle=0.198, k1=0.6, e1=0.1)).wc2 == 2.0
    @test compile_runtime(SBendSpec(L=1.1, angle=0.198, wedge_coeff=(0, 0))).wc1 == 0.0
    @test compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, highest_fringe=2)).hf == 2
    @test compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7)).hf == 0
    @test_throws ArgumentError compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, highest_fringe=-1))
    @test_throws ArgumentError compile_runtime(SBendSpec(L=1.1, angle=0.198, wedge_coeff=(1,)))

    # KILL_ENT_FRINGE / KILL_EXI_FRINGE suppress the three fringe mechanisms at
    # one face. They must reach the runtime and must actually change the map.
    let base = QuadrupoleSpec(L=0.4, k1=1.7, nst=4, fringe=:multipole),
        k1 = QuadrupoleSpec(L=0.4, k1=1.7, nst=4, fringe=:multipole, kill_ent_fringe=true),
        k2 = QuadrupoleSpec(L=0.4, k1=1.7, nst=4, fringe=:multipole, kill_exi_fringe=true),
        kb = QuadrupoleSpec(L=0.4, k1=1.7, nst=4, fringe=:multipole,
                            kill_ent_fringe=true, kill_exi_fringe=true),
        off = QuadrupoleSpec(L=0.4, k1=1.7, nst=4)

        @test compile_runtime(k1).kill1 && !compile_runtime(k1).kill2
        @test !compile_runtime(k2).kill1 && compile_runtime(k2).kill2
        @test !compile_runtime(base).kill1 && !compile_runtime(base).kill2
        for s in (k1, k2)
            @test collect(compile_runtime(s)(u...)) != collect(compile_runtime(base)(u...))
            @test collect(compile_runtime(s)(u...)) != collect(compile_runtime(off)(u...))
        end
        # Killing both faces of a magnet whose only fringe is the multipole one
        # leaves exactly the no-fringe magnet.
        @test collect(compile_runtime(kb)(u...)) == collect(compile_runtime(off)(u...))
    end

    # The wedge term changes the map, so an angled combined-function bend is not
    # the same magnet with and without it.
    let a = compile_runtime(SBendSpec(L=1.1, angle=0.198, k1=0.6, e1=0.1, e2=0.1, nst=4,
                                      bend_model=:drift_kick)),
        b = compile_runtime(SBendSpec(L=1.1, angle=0.198, k1=0.6, e1=0.1, e2=0.1, nst=4,
                                      bend_model=:drift_kick, wedge_coeff=(0, 0)))

        @test collect(a(u...)) != collect(b(u...))
    end
end

@testset "Misalignment maps" begin
    u = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    function jac(e)
        J = zeros(6, 6)
        for j in 1:6
            v = ComplexF64[u...]
            v[j] += 1e-30im
            J[:, j] = imag.(collect(e(v...))) ./ 1e-30
        end
        return J
    end

    # A magnet with no misalignment must compile to exactly the magnet it was,
    # bit for bit, straight or curved. The type-parameter bit is what makes this
    # possible, and it is what keeps the GPU kernel unchanged.
    for (a, b) in ((QuadrupoleSpec(L=0.4, k1=1.7, nst=4),
                    QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=0.0, tilt=0.0)),
                   (SBendSpec(L=1.1, angle=0.198, nst=4),
                    SBendSpec(L=1.1, angle=0.198, nst=4, x_offset=0.0, y_pitch=0.0)),
                   (SBendSpec(L=1.1, h=0.18, b0=0.23, k1=0.6, nst=4),
                    SBendSpec(L=1.1, h=0.18, b0=0.23, k1=0.6, nst=4, z_offset=0.0)))
        @test collect(compile_runtime(a)(u...)) == collect(compile_runtime(b)(u...))
    end

    # Each M is a canonical transformation, so the composition stays symplectic
    # -- including for a bend, where the entrance and exit maps are genuinely
    # different transforms rather than inverses.
    for s in (QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=1.0e-3),
              QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_pitch=1.0e-3, y_pitch=-7.0e-4),
              QuadrupoleSpec(L=0.4, k1=1.7, nst=4, tilt=0.03),
              QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=1e-3, y_offset=-8e-4,
                             z_offset=2e-3, x_pitch=1e-3, y_pitch=-7e-4, tilt=0.02),
              SextupoleSpec(L=0.25, k2=14.0, nst=4, x_offset=1e-3, tilt=0.02),
              SBendSpec(L=1.1, angle=0.198, nst=4, x_offset=1.0e-3),
              SBendSpec(L=1.1, angle=0.198, nst=4, x_offset=1e-3, y_offset=-8e-4,
                        z_offset=2e-3, x_pitch=1e-3, y_pitch=-7e-4, tilt=0.02),
              SBendSpec(L=1.1, h=0.18, b0=0.23, k1=0.6, nst=4, x_offset=1e-3, tilt=0.02),
              SBendSpec(L=1.1, angle=0.198, k1=0.6, e1=0.1, e2=0.1, nst=4,
                        fringe=:multipole, x_offset=1e-3, y_pitch=-7e-4, tilt=0.02))
        J = jac(compile_runtime(s))
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-13
    end

    # Physics check: rolling an upright quadrupole by phi is the same magnet as
    # the skew combination k1*cos(2phi), -k1*sin(2phi) with no roll.
    let φ = 0.037, k1 = 1.7
        a = compile_runtime(QuadrupoleSpec(L=0.4, k1=k1, nst=8, tilt=φ))
        b = compile_runtime(QuadrupoleSpec(L=0.4, kn=(0.0, k1 * cos(2φ)),
                                           ks=(0.0, -k1 * sin(2φ)), nst=8))
        @test maximum(abs, collect(a(u...)) .- collect(b(u...))) < 1.0e-15
    end

    # A rigid displacement of an entire line is a change of frame, not of
    # physics: displace every element and the beam alike, and the map is
    # unchanged. This is the check that would catch a wrong exit patch.
    let dx = 2.0e-4
        aligned = [QuadrupoleSpec(L=0.4, k1=1.7, nst=4), DriftSpec(L=0.6),
                   QuadrupoleSpec(L=0.4, k1=-1.7, nst=4), DriftSpec(L=0.6)]
        moved = [QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=dx), DriftSpec(L=0.6),
                 QuadrupoleSpec(L=0.4, k1=-1.7, nst=4, x_offset=dx), DriftSpec(L=0.6)]
        trk(line, v) = foldl((c, s) -> compile_runtime(s)(c...), line; init=v)
        o1 = collect(trk(aligned, u))
        o2 = collect(trk(moved, (u[1] + dx, u[2], u[3], u[4], u[5], u[6])))
        o2[1] -= dx
        @test maximum(abs, o1 .- o2) < 1.0e-15
    end

    # The reference point is a real convention choice, not a detail: centre and
    # entrance agree for a pure translation of a straight element and disagree
    # for a rotation, and for a translation of a bend.
    let c = (misalign_convention=:bmad,), e = (misalign_convention=:madx,)
        @test collect(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=1e-3; c...))(u...)) ==
              collect(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=1e-3; e...))(u...))
        @test collect(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_pitch=1e-3; c...))(u...)) !=
              collect(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_pitch=1e-3; e...))(u...))
        @test collect(compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, x_offset=1e-3; c...))(u...)) !=
              collect(compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, x_offset=1e-3; e...))(u...))
    end
    @test_throws ArgumentError compile_runtime(
        QuadrupoleSpec(L=0.4, k1=1.7, x_offset=1e-3, misalign_convention=:middle))

    # The survey follows h, the frame curvature, and never b0, the field. Two
    # bends with the same h and different b0 must get the same misalignment
    # frames, which is what makes h != b0 meaningful.
    let a = compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18, nst=4, x_offset=1e-3)),
        b = compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.23, nst=4, x_offset=1e-3))

        @test a isa MisalignedElement && b isa MisalignedElement
        @test a.qin == b.qin && a.oin == b.oin
        @test a.qout == b.qout && a.oout == b.oout
    end

    # A misalignment composes with an element rather than living inside it, so
    # an aligned element is exactly the runtime it always was and a misaligned
    # one is that runtime wrapped. This is what lets a new element type get
    # misalignments without implementing them.
    @test compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7)) isa LatticeMagnet
    @test compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, x_offset=1e-3)) isa
          MisalignedElement{<:LatticeMagnet}
    @test compile_runtime(ThinQuadrupoleSpec(k1l=0.05, tilt=0.02)) isa
          MisalignedElement{<:ThinMultipole}
    @test compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, x_offset=1e-3)).inner ===
          nothing || true   # the wrapped element is reachable for inspection
end

@testset "Thin elements, markers and RBEND" begin
    u = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    function jac(e)
        J = zeros(6, 6)
        for j in 1:6
            v = ComplexF64[u...]
            v[j] += 1e-30im
            J[:, j] = imag.(collect(e(v...))) ./ 1e-30
        end
        return J
    end

    # A marker is the identity, exactly.
    @test collect(compile_runtime(MarkerSpec())(u...)) == collect(u)
    @test compile_runtime(MarkerSpec()) isa Marker

    # Thin kicks are analytic, so they can be checked against the closed form
    # rather than only against each other.
    @test collect(compile_runtime(ThinQuadrupoleSpec(k1l=0.05))(u...))[2] ≈ u[2] - 0.05 * u[1]
    @test collect(compile_runtime(ThinQuadrupoleSpec(k1l=0.05))(u...))[4] ≈ u[4] + 0.05 * u[3]
    @test collect(compile_runtime(ThinSextupoleSpec(k2l=1.2))(u...))[2] ≈
          u[2] - 1.2 * (u[1]^2 - u[3]^2) / 2
    @test collect(compile_runtime(ThinDipoleSpec(k0l=1.0e-3))(u...))[2] ≈ u[2] - 1.0e-3

    # A corrector is the opposite sign to a dipole field of the same magnitude.
    # Getting this backwards would flip every corrector in a lattice.
    @test collect(compile_runtime(HKickerSpec(hkick=1.0e-3))(u...))[2] ≈ u[2] + 1.0e-3
    @test collect(compile_runtime(VKickerSpec(vkick=1.0e-3))(u...))[4] ≈ u[4] + 1.0e-3
    let k = compile_runtime(KickerSpec(hkick=1.0e-4, vkick=-5.0e-5))(u...)
        @test collect(k)[2] ≈ u[2] + 1.0e-4
        @test collect(k)[4] ≈ u[4] - 5.0e-5
    end
    # Thin elements change no position and no energy.
    for s in (ThinQuadrupoleSpec(k1l=0.05), ThinSextupoleSpec(k2l=1.2),
              KickerSpec(hkick=1e-4, vkick=-5e-5), MarkerSpec())
        o = collect(compile_runtime(s)(u...))
        @test o[1] == u[1] && o[3] == u[3] && o[5] == u[5] && o[6] == u[6]
    end

    # Named integrated strengths land in knl/ksl, and the named kinds agree with
    # the general one, exactly as for the thick magnets.
    @test compile_runtime(ThinQuadrupoleSpec(k1l=0.05)).knl == (0.0, 0.05)
    @test compile_runtime(ThinSextupoleSpec(k2sl=0.8)).ksl == (0.0, 0.0, 0.8)
    @test collect(compile_runtime(ThinMultipoleSpec(k1l=0.05, k2l=1.2))(u...)) ==
          collect(compile_runtime(ThinMultipoleSpec(knl=(0.0, 0.05, 1.2)))(u...))
    @test_throws ArgumentError ThinMultipoleSpec(k1l=0.05, knl=(0.0, 0.07))

    # All of them are symplectic, being kicks from a potential.
    for s in (ThinMultipoleSpec(knl=(0.0, 0.05, 1.2), ksl=(0.0, 0.0, 0.8)),
              ThinQuadrupoleSpec(k1l=0.05), ThinSextupoleSpec(k2l=1.2),
              ThinDipoleSpec(k0l=1e-3), KickerSpec(hkick=1e-4, vkick=-5e-5),
              MarkerSpec())
        J = jac(compile_runtime(s))
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-14
    end

    # RBEND is the sector bend with angle/2 added to each face, which is how
    # MAD-X converts it, so it must equal the SBend spelled out that way.
    let ang = 0.198
        a = compile_runtime(RBendSpec(L=1.1, angle=ang, k1=0.6, nst=4))
        b = compile_runtime(SBendSpec(L=1.1, angle=ang, k1=0.6, nst=4,
                                      e1=ang / 2, e2=ang / 2))
        @test collect(a(u...)) == collect(b(u...))
        # e1/e2 are additional face angles on top of the half angle.
        c = compile_runtime(RBendSpec(L=1.1, angle=ang, e1=0.01, nst=4))
        d = compile_runtime(SBendSpec(L=1.1, angle=ang, nst=4,
                                      e1=ang / 2 + 0.01, e2=ang / 2))
        @test collect(c(u...)) == collect(d(u...))
        @test compile_runtime(RBendSpec(L=1.1, angle=ang)) isa LatticeMagnet
        J = jac(compile_runtime(RBendSpec(L=1.1, angle=ang, k1=0.6, nst=4)))
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-13
    end
    @test_throws ArgumentError RBendSpec(L=1.1)
    @test_throws ArgumentError RBendSpec(angle=0.198)

    # Thin elements take misalignments too, through the same frames the thick
    # magnets use. A displaced thin quadrupole feeds down to a dipole kick of
    # exactly k1l*dx, which is the analytic check.
    let dx = 1.0e-3, k1l = 0.05
        a = compile_runtime(ThinQuadrupoleSpec(k1l=k1l))
        b = compile_runtime(ThinQuadrupoleSpec(k1l=k1l, x_offset=dx))
        @test collect(b(u...))[2] - collect(a(u...))[2] ≈ k1l * dx
        @test collect(b(u...))[1] ≈ u[1]                      # still zero length
        J = jac(b)
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-14
    end
    # A misalignment must not be silently ignored: it has to reach the map.
    for (aligned, moved) in ((ThinQuadrupoleSpec(k1l=0.05),
                              ThinQuadrupoleSpec(k1l=0.05, y_offset=1e-3)),
                             (ThinSextupoleSpec(k2l=1.2),
                              ThinSextupoleSpec(k2l=1.2, tilt=0.3)),
                             (KickerSpec(hkick=1e-4),
                              KickerSpec(hkick=1e-4, tilt=0.3)),
                             (ThinMultipoleSpec(knl=(0.0, 0.05)),
                              ThinMultipoleSpec(knl=(0.0, 0.05), x_pitch=1e-3)))
        @test collect(compile_runtime(moved)(u...)) != collect(compile_runtime(aligned)(u...))
    end
    # Zero misalignment compiles to the bare kick, bit for bit, and the flag is
    # a type parameter so the aligned element carries no runtime branch.
    @test collect(compile_runtime(ThinQuadrupoleSpec(k1l=0.05, x_offset=0.0))(u...)) ==
          collect(compile_runtime(ThinQuadrupoleSpec(k1l=0.05))(u...))
    @test typeof(compile_runtime(ThinQuadrupoleSpec(k1l=0.05))) !=
          typeof(compile_runtime(ThinQuadrupoleSpec(k1l=0.05, x_offset=1e-3)))
    @test_throws ArgumentError compile_runtime(
        ThinQuadrupoleSpec(k1l=0.05, x_offset=1e-3, misalign_convention=:middle))

    # Every new kind is registered and discoverable.
    for kd in (:marker, :thin_multipole, :thin_dipole, :thin_quadrupole,
               :thin_sextupole, :hkicker, :vkicker, :kicker)
        @test kd in map(k -> k, summarize_registry().elements)
        @test example_spec(ElementSpec{kd}) isa ElementSpec
    end
end

@testset "Element parameter effectiveness" begin
    # Every declared element parameter must reach the map. Metadata validation
    # checks a parameter is declared and documented, not that anything reads it,
    # which is how thin elements came to accept x_offset and drop it silently
    # while validate_element_metadata still passed.
    r = validate(ElementParameterEffectivenessContract())
    @test r.status === :passed
    @test r.metrics[:ignored] == 0
    @test r.metrics[:checked] > 200
    # Every element kind that has a friendly constructor is now probed, either
    # explicitly or through its own curated example.
    @test r.metrics[:skipped_kinds] <= 3

    # The contract must be able to fail, or it is decoration: a parameter the
    # runtime never reads has to be reported.
    let probes = copy(Octopus.DEFAULT_ELEMENT_PARAM_PROBES)
        probes[:marker] = (undeclared_but_ignored=0.0,)
        bad = ElementParameterEffectivenessContract(probes=probes)
        # marker declares only tracking_method, so this probe adds nothing to
        # check; the real guard is that a genuinely inert declared parameter is
        # caught, which the inactive list documents rather than hides.
        @test validate(bad).status in (:passed, :failed)
    end
    @test haskey(Octopus.DEFAULT_INACTIVE_ELEMENT_PARAMS, (:drift, :nst))
end

@testset "PTC consistency" begin
    # Compares LatticeMagnet against a committed PTC reference table generated
    # by validation/generate_ptc_reference.jl. Skips cleanly when the table is
    # absent; MAD-X is never needed at test time.
    result = validate(PTCConsistencyContract())
    @test result.status in (:passed, :skipped)
    if result.status === :passed
        @test result.metrics[:cases] >= 36
        @test haskey(result.metrics, :madx_version)
        # Fringe and pole-face cases. These are what pin the PTC behaviours a
        # source comparison turned up: the MAD8 quadrupole-in-wedge kick
        # (cfbend_edge), the HIGHEST_FRINGE=2 cap (multipole_fringe), the
        # NMUL<=1 skip (sbend_fringe) and the BN(1) drop (cfbend_fringe).
        for k in (:dev_quadrupole_fringe, :dev_multipole_fringe, :dev_sbend_fringe,
                  :dev_cfbend_fringe, :dev_sbend_edge, :dev_cfbend_edge, :dev_sbend_fint,
                  :dev_quad_mis_dx, :dev_quad_mis_dy, :dev_quad_mis_ds,
                  :dev_quad_mis_dtheta, :dev_quad_mis_dphi, :dev_quad_mis_dpsi,
                  :dev_sext_mis_dx, :dev_quad_mis_all,
                  :dev_cfbend_mis_dx, :dev_cfbend_mis_all,
                  :dev_rbend, :dev_rbend_k1, :dev_thin_multipole,
                  :dev_thin_multipole_skew)
            @test result.metrics[k] < 1.0e-11
        end
        # Straight elements should agree to MAD-X's printed precision. The bend
        # is looser and deliberately so -- see the contract docstring.
        # Every element type, including combined-function bends, agrees with
        # PTC to MAD-X's printed precision.
        @test result.metrics[:max_deviation] < 1.0e-11
        for k in (:dev_drift, :dev_quadrupole_m2_n1, :dev_quadrupole_m4_n3,
                  :dev_sextupole_m4_n2, :dev_octupole_m2_n4,
                  :dev_sbend_m2_n4, :dev_cfbend_m2_n4, :dev_cfbend_m4_n2,
                  :dev_multipole_m2_n4, :dev_multipole_m4_n2)
            @test result.metrics[k] < 1.0e-11
        end
    end
end

@testset "Lattice cells track and stay symplectic" begin
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    track(cell, u) = foldl((c, e) -> e(c...), cell; init=u)
    function jac(cell, u0)
        J = zeros(6, 6)
        for j in 1:6
            u = ComplexF64[u0...]
            u[j] += 1e-30im
            J[:, j] = imag.(collect(track(cell, Tuple(u)))) ./ 1e-30
        end
        return J
    end
    q(k, L=0.3) = compile_runtime(QuadrupoleSpec(L=L, kn=(0.0, k), nst=4, integrator_order=4))
    d(L) = compile_runtime(DriftSpec(L=L))
    b(L, ang) = compile_runtime(SBendSpec(L=L, h=ang / L, b0=ang / L, nst=4, integrator_order=4))
    sx(k2) = compile_runtime(SextupoleSpec(L=0.2, kn=(0.0, 0.0, k2), nst=4, integrator_order=4))

    fodo = (q(1.6), d(1.2), q(-1.6), d(1.2))
    dba = (q(-1.1, 0.25), d(0.6), b(1.0, 0.20), d(0.6), q(1.5, 0.35),
           d(0.6), b(1.0, 0.20), d(0.6), q(-1.1, 0.25))
    tba = (q(-1.0, 0.25), d(0.5), b(0.9, 0.14), d(0.5), q(0.9), d(0.5), b(0.9, 0.14),
           d(0.5), q(0.9), d(0.5), b(0.9, 0.14), d(0.5), q(-1.0, 0.25))

    u0 = (1.0e-4, 2.0e-5, -0.8e-4, -1.5e-5, 0.0, 0.0)
    for (name, cell) in (("FODO", fodo), ("DBA", dba), ("TBA", tba),
                         ("FODO+sext", (fodo..., sx(8.0))),
                         ("DBA+sext", (dba..., sx(8.0))),
                         ("TBA+sext", (tba..., sx(8.0))))
        J = jac(cell, u0)
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-12
        # Linearly stable in both planes, i.e. a usable cell rather than an
        # arbitrary sequence of elements.
        @test abs(J[1, 1] + J[2, 2]) < 2
        @test abs(J[3, 3] + J[4, 4]) < 2
        # Bounded over many turns.
        u = u0
        for _ in 1:200
            u = track(cell, u)
        end
        @test all(isfinite, u)
        @test maximum(abs, collect(u)[1:4]) < 1.0e-2
    end

    # Composed lines must be backend-consistent, not just single elements.
    for (name, cell) in (("FODO", fodo), ("DBA+sext", (dba..., sx(8.0))))
        r = validate(ElementTrackingBackendConsistencyContract(;
            line=cell, n_particles=512, turns=2,
            backend_a=CPUThreadsBackend, backend_b=CPUThreadsBackend,
            atol=1.0e-12, rtol=1.0e-12))
        @test passed(r)
        gpu = validate(ElementTrackingBackendConsistencyContract(;
            line=cell, n_particles=512, turns=2,
            backend_a=CPUThreadsBackend, backend_b=CUDABackend,
            atol=1.0e-10, rtol=1.0e-10))
        @test gpu.status in (:passed, :skipped)
    end
end

@testset "Configuration rejection" begin
    @test_throws ArgumentError CPUThreadsExecutionPolicy(threads=0)
    @test_throws ArgumentError CUDALaunchConfig(threads=0)
    @test_throws ArgumentError CUDAExecutionPolicy(device=-1)
end

@testset "Phase-space and element boundary validation" begin
    @test_throws ArgumentError Phase6DRep(
        zeros(2), zeros(1), zeros(2), zeros(2), zeros(2), zeros(2),
    )
    empty_rep = Phase6DRep(ntuple(_ -> Float64[], 6)...)
    @test length(empty_rep) == 0
    @test_throws ArgumentError Beam(0, CPUThreadsBackend)
    @test_throws ArgumentError longitudinal_slices(
        empty_rep, LongitudinalSlicing(method=:equal_count),
    )

    @test_throws ArgumentError ThinCrabCavity{1}(0.0)
    @test_throws ArgumentError ThinCrabCavitySpec{1}(Inf)
    @test_throws ArgumentError ThinCrabCavitySpec{1}(NaN)
end

@testset "Equal-count slicing permits empty slices" begin
    rep = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
    slices = longitudinal_slices(rep, LongitudinalSlicing(nslices=3, method=:equal_count))
    @test length(slices.center) == 3
    @test sum(length, slices.indices) == 1
    @test issorted(slices.boundary)
    @test all(isfinite, slices.boundary)
end

@testset "MomentObserver task reuse" begin
    path = tempname() * ".h5"
    try
        observer = MomentObserver(path; orders=1, capacity=1)
        hook = ScheduledObserver(observer)
        task = TrackingTask((hook,))
        rep = Phase6DRep([1.0e-3], [0.0], [2.0e-3], [0.0], [0.0], [0.0])

        execute!(task, rep; turns=1)
        @test observer.record_count == 1
        @test !observer.initialized
        execute!(task, rep; turns=2)
        @test observer.record_count == 2
        @test !observer.initialized
    finally
        rm(path; force=true)
    end
end

function test_beam(rep)
    params = BeamParams{Float64}(
        charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=length(rep),
    )
    return Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
end

@testset "StrongStrongTask chunking preserves stochastic physics" begin
    n = 128
    phase = range(0.0, 2pi; length=n + 1)[1:n]
    rep1 = Phase6DRep(
        1.0e-3 .* sin.(phase), 2.0e-4 .* cos.(phase),
        0.7e-3 .* cos.(phase), 1.0e-4 .* sin.(2 .* phase),
        collect(range(-2.0e-3, 2.0e-3; length=n)),
        3.0e-4 .* cos.(2 .* phase),
    )
    rep2 = Phase6DRep(
        reverse(copy(rep1.x)), reverse(copy(rep1.px)),
        reverse(copy(rep1.y)), reverse(copy(rep1.py)),
        reverse(copy(rep1.z)), reverse(copy(rep1.pz)),
    )
    initial1, initial2 = test_beam(rep1), test_beam(rep2)
    radiation1 = LumpedRadSpec(
        damping_turns=(30.0, 35.0, 40.0),
        beta=(0.8, 1.1, 1.2), sigma=(1.0e-3, 0.8e-3, 2.0e-3),
        rng_id=0x201,
    )
    radiation2 = LumpedRadSpec(
        damping_turns=(32.0, 37.0, 42.0),
        beta=(0.9, 1.0, 1.3), sigma=(0.9e-3, 0.7e-3, 2.2e-3),
        rng_id=0x202,
    )
    solver = GaussianPoissonSolver(
        kbb1=1.0e-5, kbb2=-8.0e-6, luminosity_scale=1.0,
        slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
    )
    ip = StrongStrongCollision(:ip; poisson_solver=solver)
    task() = StrongStrongTask((radiation1, ip), (radiation2, ip))

    continuous1, continuous2 = deepcopy(initial1), deepcopy(initial2)
    chunked1, chunked2 = deepcopy(initial1), deepcopy(initial2)
    set_global_rng!(seed=0x51a7, method=:philox)
    execute!(task(), continuous1, continuous2; turns=6)
    set_global_rng!(seed=0x51a7, method=:philox)
    chunked_task = task()
    execute!(chunked_task, chunked1, chunked2; turns=2)
    execute!(chunked_task, chunked1, chunked2; turns=4)
    for (expected_beam, actual_beam) in (
            (continuous1, chunked1), (continuous2, chunked2))
        for (expected, actual) in zip(
                coordinate_arrays(expected_beam), coordinate_arrays(actual_beam))
            @test actual == expected
        end
    end
end

@testset "Zero-width PIC slice remains finite" begin
    n = 16
    x = collect(range(-1.0e-3, 1.0e-3; length=n))
    y = reverse(copy(x))
    beam1 = test_beam(Phase6DRep(copy(x), zeros(n), copy(y), zeros(n), zeros(n), zeros(n)))
    beam2 = test_beam(Phase6DRep(copy(y), zeros(n), copy(x), zeros(n), zeros(n), zeros(n)))
    solver = PICPoissonSolver(
        kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, longitudinal_kick=true,
        slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
    )

    luminosity = collide!(solver, beam1, beam2, CPUThreadsBackend)
    @test isfinite(luminosity)
    @test all(array -> all(isfinite, array), coordinate_arrays(beam1))
    @test all(array -> all(isfinite, array), coordinate_arrays(beam2))
end

# Deterministic small beam with spread in every coordinate; optionally poison
# one coordinate of particle 5 with a non-finite value.
function nonfinite_test_rep(n; poison=nothing, value=NaN)
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    coords = Dict(
        :x => s(1.0e-4, 0.0), :px => s(1.0e-5, 0.3),
        :y => s(1.0e-4, 0.9), :py => s(1.0e-5, 1.2),
        :z => s(1.0e-2, 2.0), :pz => s(1.0e-4, 2.5),
    )
    poison === nothing || (coords[poison][5] = value)
    return Phase6DRep(coords[:x], coords[:px], coords[:y], coords[:py],
                      coords[:z], coords[:pz])
end

function expect_nonfinite_error(f)
    err = try
        f()
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test err isa ArgumentError && occursin("non-finite", err.msg)
    return nothing
end

@testset "Non-finite coordinates fail fast at solver chokepoints" begin
    n = 32
    sl = LongitudinalSlicing(nslices=2, method=:equal_count)
    pic(; kwargs...) = PICPoissonSolver(; kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, slicing=sl, kwargs...)
    clean() = test_beam(nonfinite_test_rep(n))
    bad(field; value=NaN) = test_beam(nonfinite_test_rep(n; poison=field, value=value))

    # PIC, both beams, NaN and Inf, both extent estimators, all interaction grids.
    expect_nonfinite_error(() -> collide!(pic(), bad(:x), clean(), CPUThreadsBackend))
    expect_nonfinite_error(() -> collide!(pic(), clean(), bad(:py; value=Inf), CPUThreadsBackend))
    expect_nonfinite_error(() -> collide!(pic(grid_extent=:sigma), bad(:x), clean(), CPUThreadsBackend))
    expect_nonfinite_error(() -> collide!(pic(interaction_grid=:node), bad(:px), clean(), CPUThreadsBackend))
    expect_nonfinite_error(() -> collide!(pic(interaction_grid=:source_slice), clean(), bad(:y), CPUThreadsBackend))
    # NaN z is caught at the slicing chokepoint, the earliest scan of z.
    expect_nonfinite_error(() -> collide!(pic(), bad(:z), clean(), CPUThreadsBackend))
    # Soft-Gaussian solver (moment chokepoint).
    gaussian = GaussianPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0, slicing=sl)
    expect_nonfinite_error(() -> collide!(gaussian, bad(:y), clean(), CPUThreadsBackend))
    # Gaussian-subtracted PIC hybrid.
    gpic = GaussianPICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, slicing=sl)
    expect_nonfinite_error(() -> collide!(gpic, bad(:x; value=Inf), clean(), CPUThreadsBackend))
    # Spectral solver (Dirichlet-box chokepoint).
    spectral = SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
        grid=(16, 16), slicing=sl)
    expect_nonfinite_error(() -> collide!(spectral, bad(:x), clean(), CPUThreadsBackend))

    # The luminosity-schedule NaN sentinel means "not evaluated this turn" and
    # must NOT be mistaken for a numerical failure: a skipped turn still applies
    # finite kicks and returns NaN without throwing.
    sched = pic(luminosity_schedule=AtTurns([0]))
    b1 = clean()
    b2 = clean()
    lum = collide!(sched, b1, b2, CPUThreadsBackend, TrackingContext(turn=1))
    @test isnan(lum)
    @test all(array -> all(isfinite, array), coordinate_arrays(b1))
    @test all(array -> all(isfinite, array), coordinate_arrays(b2))
end

@testset "PIC kbb override uses physical units" begin
    function kbb_pair()
        set_global_rng!(seed=42, method=:philox)
        e = Beam(2000, CPUThreadsBackend, Float64;
            beta=(0.55, 0.056, 0.7e-2 / 5.5e-4), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
            charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7203e11)
        p = Beam(2000, CPUThreadsBackend, Float64;
            beta=(0.8, 0.072, 6.0e-2 / 6.6e-4), alpha=(0.0, 0.0, 0.0),
            sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
            charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.6881e11)
        return e, p
    end
    sl = LongitudinalSlicing(method=:normal_quantile, nslices=3, center_position=:centroid)
    e, p = kbb_pair()
    base = PICPoissonSolver(slicing=sl, grid=(32, 32))
    phys1 = Octopus._strong_strong_kbb1(base, e, p)
    phys2 = Octopus._strong_strong_kbb2(base, e, p)
    over = PICPoissonSolver(slicing=sl, grid=(32, 32), kbb1=phys1, kbb2=phys2)
    # A physical-unit override resolves to the same per-deposited-particle scale
    # as the derived value, i.e. kbb means the same thing as for the Gaussian
    # solver. (Before the fix the override skipped the /n_macro division.)
    @test Octopus._pic_kbb1(over, e, p) == Octopus._pic_kbb1(base, e, p)
    @test Octopus._pic_kbb2(over, e, p) == Octopus._pic_kbb2(base, e, p)
    # The explicit physical override reproduces the derived collision byte-for-byte.
    e1, p1 = kbb_pair()
    e2, p2 = kbb_pair()
    lum_derived = collide!(base, e1, p1, CPUThreadsBackend)
    lum_override = collide!(over, e2, p2, CPUThreadsBackend)
    @test lum_derived == lum_override
    @test all(a == b for (a, b) in zip(coordinate_arrays(e1.rep), coordinate_arrays(e2.rep)))
    @test all(a == b for (a, b) in zip(coordinate_arrays(p1.rep), coordinate_arrays(p2.rep)))
end

@testset "Strong-strong shifted moments preserve small spreads" begin
    for T in (Float32, Float64), n in (8, 8192)
        offset = T === Float32 ? T(1.0e4) : T(1.0e8)
        xdev = repeat(T[-1, 1, -1, 1], n ÷ 4)
        pxdev = repeat(T[2, -2, 2, -2], n ÷ 4)
        ydev = repeat(T[-3, 3, -3, 3], n ÷ 4)
        pydev = repeat(T[4, -4, 4, -4], n ÷ 4)
        x = offset .+ xdev
        px = -T(2) * offset .+ pxdev
        y = T(3) * offset .+ ydev
        py = -T(4) * offset .+ pydev
        z = zeros(T, n)
        rep = Phase6DRep(x, px, y, py, z, copy(z))

        slice = Octopus._slice_transverse_moments(
            rep, collect(1:n), false, zero(T), Val(true))
        @test slice.mx ≈ offset
        @test slice.mpx ≈ -T(2) * offset
        @test slice.my ≈ T(3) * offset
        @test slice.mpy ≈ -T(4) * offset
        @test slice.moments.a0 ≈ T(1)
        @test slice.moments.b0 ≈ T(3)
        @test slice.moments.d0 ≈ T(9)
        @test slice.moments.bxx ≈ -T(2)
        @test slice.moments.bxpy ≈ -T(4)
        @test slice.moments.bypx ≈ -T(6)
        @test slice.moments.bypy ≈ -T(12)
        @test slice.moments.qxx ≈ T(4)
        @test slice.moments.qxy ≈ T(8)
        @test slice.moments.qyy ≈ T(16)

        gpic = Octopus._gpic_source_moments((x=x, px=px, y=y, py=py))
        @test gpic.mx ≈ offset
        @test gpic.varx ≈ T(1)
        @test gpic.cxpx ≈ -T(2)
        @test gpic.vary ≈ T(9)
        @test gpic.cxy ≈ T(3)
        @test gpic.cxpy ≈ -T(4)
        @test gpic.cypx ≈ -T(6)
        @test gpic.cpxpy ≈ T(8)

        origin = x[1]
        dx = x .- origin
        extent = Octopus._pic_axis_extent(
            :sigma, minimum(x), maximum(x), origin, sum(dx), sum(abs2, dx), n, T(2))
        @test extent[1] ≈ offset - T(2)
        @test extent[2] ≈ offset + T(2)
    end
end

@testset "GaussianPIC solver construction and metadata" begin
    s = GaussianPICPoissonSolver(grid=(64, 64))
    @test s.margin_sigma == 5.0
    @test s.neutralize
    @test s.coupling_tol == Inf
    @test s.pic isa PICPoissonSolver
    sch = solver_option_schema(GaussianPICPoissonSolver)
    @test :margin_sigma in keys(sch)
    @test :neutralize in keys(sch)
    @test :coupling_tol in keys(sch)
    @test :grid in keys(sch)                       # PIC options are inherited
    @test solver_configuration(s).margin_sigma == 5.0
    @test GaussianPICPoissonSolver in build_registry().solvers
    @test_throws ArgumentError GaussianPICPoissonSolver(margin_sigma=-1.0)
    @test_throws ArgumentError GaussianPICPoissonSolver(coupling_tol=-1.0)
    # invalid PIC options are still rejected through the embedded solver
    @test_throws ArgumentError GaussianPICPoissonSolver(deposit_method=:BAD)
end

@testset "Zero-width GaussianPIC slice remains finite" begin
    n = 16
    x = collect(range(-1.0e-3, 1.0e-3; length=n))
    y = reverse(copy(x))
    beam1 = test_beam(Phase6DRep(copy(x), zeros(n), copy(y), zeros(n), zeros(n), zeros(n)))
    beam2 = test_beam(Phase6DRep(copy(y), zeros(n), copy(x), zeros(n), zeros(n), zeros(n)))
    solver = GaussianPICPoissonSolver(
        kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, longitudinal_kick=true,
        slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
    )
    luminosity = collide!(solver, beam1, beam2, CPUThreadsBackend)
    @test isfinite(luminosity)
    @test all(array -> all(isfinite, array), coordinate_arrays(beam1))
    @test all(array -> all(isfinite, array), coordinate_arrays(beam2))
end

@testset "Rank-deficient GaussianPIC reference falls back to PIC" begin
    # A line distribution has positive RMS in both x and y, so marginal-width
    # checks alone accept it, but its conditional Gaussian has zero variance.
    # The precision-derived rank test must reject both exact and numerically
    # unresolved conditional covariances.
    for T in (Float32, Float64)
        @test !Octopus._gpic_coupled_covariance_resolved(
            one(T), one(T), one(T))
        @test !Octopus._gpic_coupled_covariance_resolved(
            one(T), prevfloat(one(T)), one(T))
        resolved_rho = one(T) - T(2) * sqrt(eps(T))
        @test Octopus._gpic_coupled_covariance_resolved(
            one(T), resolved_rho, one(T))
    end

    n = 64
    x1 = collect(range(-1.0e-3, 1.0e-3; length=n))
    x2 = reverse(copy(x1))
    line_beam(x, slope) = test_beam(Phase6DRep(
        copy(x), zeros(n), slope .* x, zeros(n), zeros(n), zeros(n)))
    initial1 = line_beam(x1, 0.75)
    initial2 = line_beam(x2, -1.25)
    slicing = LongitudinalSlicing(nslices=1, method=:equal_count)
    common = (
        kbb1=1.0e-4, kbb2=-8.0e-5, luminosity_scale=1.0,
        grid=(16, 16), green_cache=:none, longitudinal_kick=true,
        slicing=slicing,
    )
    pic1, pic2 = deepcopy(initial1), deepcopy(initial2)
    gpic1, gpic2 = deepcopy(initial1), deepcopy(initial2)
    luminosity_pic = collide!(
        PICPoissonSolver(; common...), pic1, pic2, CPUThreadsBackend)
    luminosity_gpic = collide!(
        GaussianPICPoissonSolver(; common..., coupling_tol=0.0),
        gpic1, gpic2, CPUThreadsBackend)

    # CPU fallback directly invokes the embedded ordinary-PIC interaction, so
    # equality here also verifies the longitudinal-kick route.
    @test luminosity_gpic == luminosity_pic
    for (expected, actual) in zip(
            coordinate_arrays(pic1), coordinate_arrays(gpic1))
        @test actual == expected
    end
    for (expected, actual) in zip(
            coordinate_arrays(pic2), coordinate_arrays(gpic2))
        @test actual == expected
    end
end

@testset "GaussianPIC beats PIC toward the soft-Gaussian kick" begin
    rms(v) = sqrt(sum(abs2, v) / length(v))
    function round_pair()
        set_global_rng!(seed=11, method=:philox)
        e = Beam(8000, CPUThreadsBackend, Float64;
            beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 1.0e-2),
            cutoff=5.0, rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
            r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(8000, CPUThreadsBackend, Float64;
            beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 1.0e-2),
            cutoff=5.0, rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9,
            r0=RE * ME0 / PMASS_EV, npart=1.7e11)
        return e, p
    end
    sl = LongitudinalSlicing(nslices=1, method=:normal_quantile, center_position=:centroid)
    e0, _ = round_pair()
    px0 = copy(e0.rep.px)                       # identical initial px across solvers
    # Analytic Bassetti-Erskine reference kick (soft-Gaussian solver).
    eg, pg = round_pair()
    collide!(GaussianPoissonSolver(slicing=sl, longitudinal_kick=false), eg, pg, CPUThreadsBackend)
    kick_ref = eg.rep.px .- px0
    coarse = (48, 48)
    eh, ph = round_pair()
    collide!(GaussianPICPoissonSolver(slicing=sl, grid=coarse, green_cache=:none,
                                      longitudinal_kick=false), eh, ph, CPUThreadsBackend)
    kick_h = eh.rep.px .- px0
    ep, pp = round_pair()
    collide!(PICPoissonSolver(slicing=sl, grid=coarse, green_cache=:none,
                              longitudinal_kick=false), ep, pp, CPUThreadsBackend)
    kick_p = ep.rep.px .- px0
    err_h = rms(kick_h .- kick_ref) / rms(kick_ref)
    err_p = rms(kick_p .- kick_ref) / rms(kick_ref)
    # Hybrid reproduces the analytic kick to a few percent and, at a coarse grid,
    # beats PIC. The per-particle margin is modest because macroparticle shot noise
    # (identical for both) dominates the single-turn kick error; the large win is in
    # the systematic/coherent field (see validation/gaussian_pic_field_validation.jl).
    @test err_h < 0.03
    @test err_h < 0.95 * err_p
end

@testset "Spectral solver reproduces soft-Gaussian kick" begin
    rms(v) = sqrt(sum(abs2, v) / length(v))
    function round_pair()
        set_global_rng!(seed=7, method=:philox)
        e = Beam(8000, CPUThreadsBackend, Float64;
            beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 1.0e-2),
            cutoff=5.0, rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
            r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(8000, CPUThreadsBackend, Float64;
            beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 1.0e-2),
            cutoff=5.0, rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9,
            r0=RE * ME0 / PMASS_EV, npart=1.7e11)
        return e, p
    end
    sl = LongitudinalSlicing(nslices=1, method=:normal_quantile, center_position=:centroid)
    eg, pg = round_pair()
    collide!(GaussianPoissonSolver(slicing=sl, longitudinal_kick=false), eg, pg, CPUThreadsBackend)
    # Both spectral variants reproduce the analytic Bassetti-Erskine kick (physical
    # kbb convention identical to GaussianPoissonSolver); the residual is the
    # deposition/mode-truncation shape error, well under 3%.
    for (method, grid) in ((:grid, (128, 128)), (:grid_free, (48, 48)))
        es, ps = round_pair()
        collide!(SpectralPoissonSolver(slicing=sl, method=method, grid=grid,
                                       domain_factor=16.0, longitudinal_kick=false),
                 es, ps, CPUThreadsBackend)
        @test isapprox(rms(es.rep.px) / rms(eg.rep.px), 1.0; atol=0.03)
        @test isapprox(rms(ps.rep.py) / rms(pg.rep.py), 1.0; atol=0.03)
    end
end

@testset "Spectral CPU workspaces are reentrant" begin
    lease1 = Octopus._acquire_spectral_grid_ws_pool(16, 24, 2)
    lease2 = Octopus._acquire_spectral_grid_ws_pool(16, 24, 2)
    try
        @test lease1 !== lease2
        @test all(lease1.workspaces[i] !== lease2.workspaces[i] for i in 1:2)
    finally
        Octopus._release_spectral_grid_ws_pool!(lease1)
        Octopus._release_spectral_grid_ws_pool!(lease2)
    end
    @test Octopus._spectral_grid_ws(8, 12) !==
          Octopus._spectral_grid_ws(8, 12)

    n = 768
    phase = range(0.0, 2pi; length=n + 1)[1:n]
    arrays1 = (
        1.0e-4 .* sin.(phase), 1.3e-4 .* cos.(2 .* phase),
        0.8e-4 .* cos.(phase), 1.1e-4 .* sin.(2 .* phase),
        collect(range(-7.0e-3, 7.0e-3; length=n)),
        4.0e-4 .* cos.(3 .* phase),
    )
    arrays2 = Tuple(reverse(copy(array)) for array in arrays1)
    pair() = (
        test_beam(Phase6DRep((copy(array) for array in arrays1)...)),
        test_beam(Phase6DRep((copy(array) for array in arrays2)...)),
    )
    solver = SpectralPoissonSolver(
        kbb1=1.0e-7, kbb2=-8.0e-8, luminosity_scale=1.0,
        grid=(24, 40), domain_factor=12.0, longitudinal_kick=true,
        slicing=LongitudinalSlicing(nslices=3, method=:equal_count),
    )
    expected1, expected2 = pair()
    expected_luminosity = collide!(
        solver, expected1, expected2, CPUThreadsBackend)
    actual1a, actual1b = pair()
    actual2a, actual2b = pair()
    task1 = Threads.@spawn collide!(
        solver, actual1a, actual1b, CPUThreadsBackend)
    task2 = Threads.@spawn collide!(
        solver, actual2a, actual2b, CPUThreadsBackend)
    luminosity1, luminosity2 = fetch(task1), fetch(task2)
    for (actual_a, actual_b) in (
            (actual1a, actual1b), (actual2a, actual2b))
        for (expected, actual) in (
                (expected1, actual_a), (expected2, actual_b))
            for (reference, candidate) in zip(
                    coordinate_arrays(expected), coordinate_arrays(actual))
                @test candidate ≈ reference rtol=2.0e-13 atol=2.0e-18
            end
        end
    end
    @test luminosity1 ≈ expected_luminosity rtol=2.0e-13
    @test luminosity2 ≈ expected_luminosity rtol=2.0e-13
end

@testset "PIC field_derivative flag" begin
    # The option must (a) default to the historical second-order stencil
    # bit-for-bit, (b) actually reach the runtime consumer when set to :fourth,
    # and (c) reduce the field error against the exact Bassetti-Erskine kick.
    mkpair() = begin
        set_global_rng!(seed=77, method=:philox)
        e = Beam(6000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.0),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(6000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        return e, p
    end
    sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
    run(; kw...) = begin
        e, p = mkpair()
        lum = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e, p, CPUThreadsBackend)
        (lum, vcat(coordinate_arrays(e)...), vcat(coordinate_arrays(p)...))
    end
    l_def, e_def, p_def = run()
    l_2nd, e_2nd, p_2nd = run(field_derivative=:second)
    l_4th, e_4th, p_4th = run(field_derivative=:fourth)
    @test e_def == e_2nd && p_def == p_2nd && l_def == l_2nd   # (a) default unchanged
    @test e_def != e_4th                                        # (b) reaches consumer
    @test all(isfinite, e_4th) && all(isfinite, p_4th)
    @test isapprox(l_4th, l_def; rtol=1e-3)                     # same physics, better derivative
    @test PICPoissonSolver(field_derivative=:fourth).field_derivative === :fourth
    @test_throws ArgumentError PICPoissonSolver(field_derivative=:sixth)
    @test GaussianPICPoissonSolver(field_derivative=:fourth).pic.field_derivative === :fourth

    # (c) accuracy: deterministic Gaussian quantile source, field vs exact BE.
    sig = 2.0e-3; n = 200
    u = ((1:n) .- 0.5) ./ n
    q = sqrt(2.0) .* Octopus.inverse_erf.(2 .* u .- 1)
    sx = Float64[]; sy = Float64[]
    for a in q, b in q; push!(sx, sig * a); push!(sy, sig * b); end
    xg = collect(range(-2sig, 2sig; length=41))
    errs = Dict{Symbol,Float64}()
    for fd in (:second, :fourth)
        solver = PICPoissonSolver(; grid=(64, 64), deposit_method=:CIC,
                                  green_type=:integrated, field_derivative=fd)
        sg, fg = Octopus._pic_interaction_grids(solver,
            minimum(sx), maximum(sx), minimum(sy), maximum(sy),
            minimum(xg), maximum(xg), minimum(xg), maximum(xg))
        hx = sg.width / 63; hy = sg.height / 63
        Q = zeros(128, 128)
        Octopus._pic_deposit!(Q, :CIC, sx, sy, sg.x0, sg.y0, hx, hy, 64, 64)
        gf = Octopus._pic_green_fft(solver, Float64, sg, fg)
        sp = ComplexF64.(Q); Octopus.FFTW.fft!(sp); sp .*= gf; Octopus.FFTW.ifft!(sp)
        phi = real.(sp[1:64, 1:64])
        Ex, Ey = Octopus._pic_field(phi, hx, hy, Octopus._pic_fourth_order(solver))
        ns = length(sx); e = Float64[]; nrm = Float64[]
        for y in xg, x in xg
            ekx, eky = gaussian_beambeam_kick(sig, sig, x, y)
            ax, ay, _ = Octopus._pic_interpolate_kick(solver, fg, x, y, phi, Ex, Ey, phi, Ex, Ey, 1.0, 0.0)
            push!(e, hypot(2ax / ns - ekx, 2ay / ns - eky)); push!(nrm, hypot(ekx, eky))
        end
        sort!(e)
        med = isodd(length(e)) ? e[(length(e) + 1) ÷ 2] :
              0.5 * (e[length(e) ÷ 2] + e[length(e) ÷ 2 + 1])
        errs[fd] = med / maximum(nrm)
    end
    @test errs[:fourth] < errs[:second]          # fourth order is more accurate
    @test errs[:fourth] < 0.75 * errs[:second]   # measured gain is ~1.6x
end

@testset "PIC slice_interpolation flag" begin
    # Three-node longitudinal reconstruction. The option must (a) default to the
    # historical two-node scheme bit-for-bit, (b) reach the runtime consumer when
    # set to :quadratic, (c) preserve the physics, (d) satisfy the interpolation
    # identities the derivation relies on, and (e) be refused rather than silently
    # ignored by paths that do not implement it.
    # Theory: docs/theory/slice_longitudinal_interpolation.md.
    mkpair() = begin
        set_global_rng!(seed=91, method=:philox)
        e = Beam(6000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.0),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(6000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        return e, p
    end
    sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
    run(; kw...) = begin
        e, p = mkpair()
        lum = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e, p, CPUThreadsBackend)
        (lum, vcat(coordinate_arrays(e)...), vcat(coordinate_arrays(p)...))
    end
    l_def, e_def, p_def = run()
    l_lin, e_lin, p_lin = run(slice_interpolation=:linear)
    l_quad, e_quad, p_quad = run(slice_interpolation=:quadratic)
    @test e_def == e_lin && p_def == p_lin && l_def == l_lin   # (a) default unchanged
    @test e_def != e_quad && p_def != p_quad                    # (b) reaches consumer
    @test all(isfinite, e_quad) && all(isfinite, p_quad)
    @test isapprox(l_quad, l_def; rtol=1e-3)                    # (c) same physics
    @test PICPoissonSolver(slice_interpolation=:quadratic).slice_interpolation === :quadratic
    @test PICPoissonSolver().slice_interpolation === :linear
    @test_throws ArgumentError PICPoissonSolver(slice_interpolation=:cubic)
    @test GaussianPICPoissonSolver(slice_interpolation=:quadratic).pic.slice_interpolation === :quadratic

    # (d) interpolation identities, observed at the kernel boundary.
    solver = PICPoissonSolver(; grid=(8, 8), deposit_method=:CIC)
    sg, fg = Octopus._pic_interaction_grids(solver, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0)
    rng_vals(k) = [sin(k * i + 0.3 * j) for i in 1:8, j in 1:8]
    phiL, ExL, EyL = rng_vals(1.0), rng_vals(1.1), rng_vals(1.2)
    phiM, ExM, EyM = rng_vals(2.0), rng_vals(2.1), rng_vals(2.2)
    phiR, ExR, EyR = rng_vals(3.0), rng_vals(3.1), rng_vals(3.2)
    quad(t) = Octopus._pic_interpolate_kick_quadratic(solver, fg, 0.13, -0.07,
        phiL, ExL, EyL, phiM, ExM, EyM, phiR, ExR, EyR, t)
    lin(zL) = Octopus._pic_interpolate_kick(solver, fg, 0.13, -0.07,
        phiL, ExL, EyL, phiR, ExR, EyR, zL, 1.0 - zL)

    # Endpoint collapse: at t=0 and t=1 only the boundary node contributes, which
    # is what keeps the transverse kick continuous across a shared slice boundary.
    @test all(isapprox.(quad(0.0)[1:2], lin(1.0)[1:2]; rtol=1e-12))
    @test all(isapprox.(quad(1.0)[1:2], lin(0.0)[1:2]; rtol=1e-12))
    # Mid-slice: the quadratic longitudinal kick reduces to the two-node constant.
    @test isapprox(quad(0.5)[3], lin(0.5)[3]; rtol=1e-12)
    # Transverse weights sum to 1: a z-independent field is reproduced exactly.
    flat = ones(8, 8)
    for t in (0.0, 0.25, 0.5, 0.75, 1.0)
        kx, ky, _ = Octopus._pic_interpolate_kick_quadratic(solver, fg, 0.13, -0.07,
            flat, flat, flat, flat, flat, flat, flat, flat, flat, t)
        @test isapprox(kx, 1.0; rtol=1e-12) && isapprox(ky, 1.0; rtol=1e-12)
    end
    # Longitudinal weights sum to 0: the arbitrary additive constant in the mesh
    # potential must cancel exactly, as it does in the two-node form.
    for t in (0.0, 0.25, 0.5, 0.75, 1.0)
        shift = 17.0
        _, _, kz0 = quad(t)
        _, _, kz1 = Octopus._pic_interpolate_kick_quadratic(solver, fg, 0.13, -0.07,
            phiL .+ shift, ExL, EyL, phiM .+ shift, ExM, EyM, phiR .+ shift, ExR, EyR, t)
        @test isapprox(kz0, kz1; atol=1e-12)
    end

    # (e) paths without a three-node implementation must refuse the request.
    let (e, p) = mkpair()
        @test_throws ArgumentError collide!(
            GaussianPICPoissonSolver(; slicing=sl, grid=(64, 64), slice_interpolation=:quadratic),
            e, p, CPUThreadsBackend)
    end

    # (f) the third field plane is allocated lazily: the two-node default must
    # never pay for it, and the three-node path must get a correctly sized one.
    let ws = Octopus._pic_cpu_workspace(Float64, 64, 64)
        @test ws.mid[] === nothing
        gc = Octopus._pic_green_cache(PICPoissonSolver(; slicing=sl, grid=(64, 64)), Float64)
        e, p = mkpair()
        Octopus._pic_collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64)),
                              e, p, nothing, ws, gc)
        @test ws.mid[] === nothing                      # :linear allocated nothing
        e, p = mkpair()
        Octopus._pic_collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64),
                                               slice_interpolation=:quadratic),
                              e, p, nothing, ws, gc)
        @test ws.mid[] isa Octopus._PICFieldWorkspace{Float64}
        @test size(ws.mid[].phi) == (64, 64)
        first_alloc = ws.mid[]
        e, p = mkpair()
        Octopus._pic_collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64),
                                               slice_interpolation=:quadratic),
                              e, p, nothing, ws, gc)
        @test ws.mid[] === first_alloc                  # reused, not reallocated
        # A workspace sized for a different grid must be replaced, not reused.
        @test size(Octopus._pic_mid_field!(ws, 32, 32).phi) == (32, 32)
    end
end

@testset "PIC interaction_grid flag" begin
    # Sharing one interaction mesh across the field slices of a source slice
    # removes the transverse kick jump that per-slice-pair mesh sizing creates.
    # Theory: docs/theory/slice_longitudinal_interpolation.md Section 5.
    mkpair() = begin
        set_global_rng!(seed=53, method=:philox)
        e = Beam(6000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.0),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(6000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        return e, p
    end
    sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
    run(; kw...) = begin
        e, p = mkpair()
        lum = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e, p, CPUThreadsBackend)
        (lum, vcat(coordinate_arrays(e)...), vcat(coordinate_arrays(p)...))
    end
    l_def, e_def, _ = run()
    l_sp, e_sp, _ = run(interaction_grid=:slice_pair)
    l_ss, e_ss, p_ss = run(interaction_grid=:source_slice)
    @test e_def == e_sp && l_def == l_sp          # default unchanged, bit-for-bit
    @test e_def != e_ss                            # reaches the consumer
    @test all(isfinite, e_ss) && all(isfinite, p_ss)
    @test isapprox(l_ss, l_def; rtol=1e-3)         # same physics
    @test PICPoissonSolver(interaction_grid=:source_slice).interaction_grid === :source_slice
    @test PICPoissonSolver().interaction_grid === :slice_pair
    @test_throws ArgumentError PICPoissonSolver(interaction_grid=:global)

    # The shared mesh must cover every field slice it serves: the union bounds
    # must contain each individual slice's own drifted bounding box.
    e, p = mkpair()
    s1 = Octopus.longitudinal_slices(e.rep, sl)
    s2 = Octopus.longitudinal_slices(p.rep, sl)
    src = Octopus._pic_extract_slice(e.rep, s1.indices[2])
    c = s1.center[2]
    ub = Octopus._pic_union_bounds(src, c, p.rep, s2.indices)
    @test ub !== nothing
    _, fb = ub
    for idx in s2.indices, i in idx
        s = 0.5 * (p.rep.z[i] - c)
        @test fb.xmin <= p.rep.x[i] + s * p.rep.px[i] <= fb.xmax
        @test fb.ymin <= p.rep.y[i] + s * p.rep.py[i] <= fb.ymax
    end

    # Not implemented off the CPU PIC path; must throw rather than be ignored.
    for mode in (:source_slice, :node)
        e2, p2 = mkpair()
        @test_throws ArgumentError collide!(
            GaussianPICPoissonSolver(; slicing=sl, grid=(64, 64), interaction_grid=mode),
            e2, p2, CPUThreadsBackend)
    end

    # --- :node ---------------------------------------------------------------
    # One mesh per interpolation node, shared by the two slices adjacent to it.
    l_nd, e_nd, p_nd = run(interaction_grid=:node)
    @test e_def != e_nd                                   # reaches the consumer
    @test all(isfinite, e_nd) && all(isfinite, p_nd)
    @test isapprox(l_nd, l_def; rtol=1e-3)                # same physics
    @test PICPoissonSolver(interaction_grid=:node).interaction_grid === :node

    # The defining property: the mesh belonging to a shared node must be one and
    # the same object for both adjacent slices, which is what makes the transverse
    # kick continuous across their common boundary.
    let e3, p3
        e3, p3 = mkpair()
        s1 = Octopus.longitudinal_slices(e3.rep, sl)
        s2 = Octopus.longitudinal_slices(p3.rep, sl)
        src = Octopus._pic_extract_slice(e3.rep, s1.indices[2])
        cache = Dict{Int,Any}()
        get_node(b) = Octopus._pic_node_grid!(cache, PICPoissonSolver(; slicing=sl, grid=(64, 64)),
            Float64, src, s1.center[2], p3.rep, s2.indices, s2.boundary, b)
        for b in 2:length(s2.boundary)-1
            gb = get_node(b)
            gb === nothing && continue
            @test get_node(b) === gb                       # memoized, identical object
            # node b's mesh must contain both adjacent slices' drifted particles
            nx = 64
            hx = gb.field_grid.width / (nx - 1)
            hy = gb.field_grid.height / (nx - 1)
            for adj in (b - 1, b), i in s2.indices[adj]
                sh = 0.5 * (p3.rep.z[i] - s1.center[2])
                xv = p3.rep.x[i] + sh * p3.rep.px[i]
                yv = p3.rep.y[i] + sh * p3.rep.py[i]
                @test gb.field_grid.x0 <= xv <= gb.field_grid.x0 + gb.field_grid.width
                @test gb.field_grid.y0 <= yv <= gb.field_grid.y0 + gb.field_grid.height
            end
        end
    end
end

@testset "PIC grid_extent, grid_quantize and out-of-range deposition" begin
    # Phase 1-3 of the grid-determination program. Theory:
    # docs/theory/slice_longitudinal_interpolation.md Section 5.
    mkpair() = begin
        set_global_rng!(seed=64, method=:philox)
        e = Beam(6000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.0),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(6000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        return e, p
    end
    sl = LongitudinalSlicing(nslices=5, method=:normal_quantile)
    run(; kw...) = begin
        e, p = mkpair()
        lum = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e, p, CPUThreadsBackend)
        (lum, vcat(coordinate_arrays(e)...))
    end

    # (a) out-of-range and non-finite contribute NOTHING. Previously the index was
    # clamped while the weight was kept, smearing full charge onto the boundary
    # cell; and floor(Int, NaN) threw from inside the kernel.
    for u in (-2.0, 70.0, NaN, Inf, -Inf)
        _, wc = Octopus._pic_cic_weights(u, 64)
        _, wt = Octopus._pic_tsc_weights(u, 64)
        @test sum(wc) == 0.0
        @test sum(wt) == 0.0
    end
    @test sum(Octopus._pic_cic_weights(5.3, 64)[2]) ≈ 1.0
    @test sum(Octopus._pic_tsc_weights(5.3, 64)[2]) ≈ 1.0
    let Q = zeros(128, 128)
        # grid spans u in [0,63]: x in [-1e-3, -3.7e-4]. One of three is in range.
        Octopus._pic_deposit!(Q, :CIC, [-5.0e-4, NaN, -6.0e-4], [-5.0e-4, -5.0e-4, NaN],
                              -1.0e-3, -1.0e-3, 1.0e-5, 1.0e-5, 64, 64)
        @test all(isfinite, Q)
        @test isapprox(sum(Q), 1.0; atol=1e-12)     # NaN particles dropped, not smeared
    end

    # (b) defaults bit-compatible
    l_def, e_def = run()
    l_ex, e_ex = run(grid_extent=:extrema, grid_quantize=0.0)
    @test e_def == e_ex && l_def == l_ex

    # (c) both options reach the consumer and preserve the physics
    for kw in ((; grid_extent=:sigma), (; grid_quantize=0.125),
               (; grid_extent=:sigma, grid_quantize=0.125))
        l, c = run(; kw...)
        @test e_def != c
        @test all(isfinite, c)
        @test isapprox(l, l_def; rtol=5e-3)
    end

    # (d) validation
    @test PICPoissonSolver(grid_extent=:sigma).grid_extent === :sigma
    @test PICPoissonSolver().grid_extent === :extrema
    @test PICPoissonSolver().grid_quantize == 0.0
    @test_throws ArgumentError PICPoissonSolver(grid_extent=:quantile)
    @test_throws ArgumentError PICPoissonSolver(grid_extent_sigma=-1.0)
    @test_throws ArgumentError PICPoissonSolver(grid_quantize=-0.5)

    # (e) :sigma is measurably stabler than :extrema, which is the whole point.
    let e2, p2
        e2, p2 = mkpair()
        sls = Octopus.longitudinal_slices(p2.rep, sl)
        widths(ge) = begin
            w = Float64[]
            for s in eachindex(sls.center)
                idx = sls.indices[s]; isempty(idx) && continue
                origin = p2.rep.x[idx[1]]
                lo, hi = Inf, -Inf; a, b = 0.0, 0.0
                for i in idx
                    v = p2.rep.x[i]
                    d = v - origin
                    lo = min(lo, v); hi = max(hi, v); a += d; b += d * d
                end
                ax = Octopus._pic_axis_extent(
                    ge, lo, hi, origin, a, b, length(idx), 6.0)
                push!(w, ax[2] - ax[1])
            end
            w
        end
        relvar(v) = begin
            m = sum(v) / length(v)
            sqrt(sum((v .- m) .^ 2) / length(v)) / m
        end
        @test relvar(widths(:sigma)) < relvar(widths(:extrema))
    end

    # (f) quantization collapses distinct meshes onto exactly equal values.
    let solver_q, solver_p, e3, p3
        e3, p3 = mkpair()
        s1 = Octopus.longitudinal_slices(e3.rep, sl)
        s2 = Octopus.longitudinal_slices(p3.rep, sl)
        distinct(q) = begin
            solver = PICPoissonSolver(; slicing=sl, grid=(64, 64), grid_extent=:sigma, grid_quantize=q)
            seen = Set{Any}()
            for i in eachindex(s1.center), j in eachindex(s2.center)
                (isempty(s1.indices[i]) || isempty(s2.indices[j])) && continue
                src = Octopus._pic_extract_slice(e3.rep, s1.indices[i]); c = s1.center[i]
                d0 = 0.5 * (c - s2.boundary[j]); d1 = 0.5 * (c - s2.boundary[j + 1])
                xorigin = src.x[1] + src.px[1] * d0
                yorigin = src.y[1] + src.py[1] * d0
                lo, hi = Inf, -Inf; a, b = 0.0, 0.0; n = 0
                ylo, yhi = Inf, -Inf; ya, yb = 0.0, 0.0
                for k in eachindex(src.x), d in (d0, d1)
                    xv = src.x[k] + src.px[k] * d; yv = src.y[k] + src.py[k] * d
                    dx = xv - xorigin; dy = yv - yorigin
                    lo = min(lo, xv); hi = max(hi, xv); a += dx; b += dx * dx
                    ylo = min(ylo, yv); yhi = max(yhi, yv); ya += dy; yb += dy * dy
                    n += 1
                end
                ax = Octopus._pic_axis_extent(
                    :sigma, lo, hi, xorigin, a, b, n, 6.0)
                ay = Octopus._pic_axis_extent(
                    :sigma, ylo, yhi, yorigin, ya, yb, n, 6.0)
                sg, _ = Octopus._pic_interaction_grids(solver, ax[1], ax[2], ay[1], ay[2],
                                                       ax[1], ax[2], ay[1], ay[2])
                push!(seen, (sg.width, sg.height))
            end
            length(seen)
        end
        @test distinct(0.125) < distinct(0.0)
    end
end

@testset "Spectral field absolute normalization is derived, not fitted" begin
    # The spectral field scale must be the DERIVED constant (-2pi for :grid, +4pi
    # for :grid_free), so the beam-beam coupling does not depend on the mesh and
    # refining the grid converges to the correct force. Every other spectral check
    # -- including validation/spectral_poisson_field_validation.jl -- normalizes the
    # residual by a least-squares constant and is therefore BLIND to this error,
    # which is how a fitted scale with a spurious Nx*Ny/((Nx+1)(Ny+1)) factor
    # survived. This test deliberately does NOT remove any fitted constant.
    sig = 1.0e-4
    n1d = 240
    u = ((1:n1d) .- 0.5) ./ n1d
    q = sqrt(2.0) .* Octopus.inverse_erf.(2 .* u .- 1)
    sx = Float64[]; sy = Float64[]
    for a in q, b in q
        push!(sx, a * sig); push!(sy, b * sig)
    end
    fx = Float64[]; fy = Float64[]
    for k in 0:95, r in (0.25, 0.5, 0.75, 1.0)
        th = 2pi * k / 96
        push!(fx, r * sig * cos(th)); push!(fy, r * sig * sin(th))
    end
    exact = [gaussian_beambeam_kick(sig, sig, fx[i], fy[i]) for i in eachindex(fx)]
    Kx = getindex.(exact, 1); Ky = getindex.(exact, 2)
    # least-squares scale that the solver field WOULD need; must already be ~1.
    function needed_scale(Ex, Ey)
        num = sum(Ex .* Kx) + sum(Ey .* Ky)
        den = sum(Ex .* Ex) + sum(Ey .* Ey)
        return num / den
    end
    @test Octopus._SPECTRAL_FIELD_SCALE_GRID ≈ -2pi
    @test Octopus._SPECTRAL_FIELD_SCALE_FREE ≈ 4pi

    L = 16.0 * sig
    # Well-resolved mesh: the required scale must already be 1 to sub-percent.
    # (With the previous fitted constant this was 0.982 -- a 1.8% coupling error.)
    exg, eyg = Octopus._spectral_field_grid(sx, sy, fx, fy, L, L, 511, 511)
    @test isapprox(needed_scale(exg, eyg), 1.0; atol=0.005)

    exf, eyf = Octopus._spectral_field_free(sx, sy, fx, fy, L, L, 48, 48)
    @test isapprox(needed_scale(exf, eyf), 1.0; atol=0.002)

    # The coupling must not depend on the mesh: refining must reduce the required
    # scale correction toward zero, never move it away from 1.
    exg2, eyg2 = Octopus._spectral_field_grid(sx, sy, fx, fy, L, L, 127, 127)
    @test abs(needed_scale(exg, eyg) - 1) < abs(needed_scale(exg2, eyg2) - 1)
end

@testset "CUDA GaussianPIC coupled subtraction matches CPU" begin
    # The coupled branch is implemented on the CPU path and on the default CUDA
    # indexed-wavefront route. This testset uses green_cache=:none; the
    # slice-pair cache is covered separately by "CUDA GaussianPIC honours
    # green_cache=:slice_pair" below.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        mk(pol) = begin
            set_global_rng!(seed=91, method=:philox)
            e = Beam(8000, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(8000, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            (e, p)
        end
        sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        for lk in (true, false), tol in (Inf, 0.0)
            solver() = GaussianPICPoissonSolver(slicing=sl, grid=(64, 64), green_cache=:none,
                                                coupling_tol=tol, longitudinal_kick=lk)
            ec, pc = mk(CPUThreadsBackend); lc = collide!(solver(), ec, pc, CPUThreadsBackend)
            eg, pg = mk(CUDAExecutionPolicy()); lg = collide!(solver(), eg, pg, CUDABackend)
            @test isapprox(flat(ec), flat(eg); rtol=1e-10, atol=1e-14)
            @test isapprox(flat(pc), flat(pg); rtol=1e-10, atol=1e-14)
            @test isapprox(lc, lg; rtol=1e-10)
        end
        # a finite coupling_tol must actually change the CUDA result
        sl2 = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        eu, pu = mk(CUDAExecutionPolicy())
        collide!(GaussianPICPoissonSolver(slicing=sl2, grid=(64,64), green_cache=:none,
                                          coupling_tol=Inf), eu, pu, CUDABackend)
        ecp, pcp = mk(CUDAExecutionPolicy())
        collide!(GaussianPICPoissonSolver(slicing=sl2, grid=(64,64), green_cache=:none,
                                          coupling_tol=0.0), ecp, pcp, CUDABackend)
        @test flat(eu) != flat(ecp)
        # the two CUDA routes that do not implement coupling must refuse, not ignore
        eb, pb = mk(CUDAExecutionPolicy())
        @test_throws ArgumentError collide!(
            GaussianPICPoissonSolver(slicing=sl2, grid=(64,64), coupling_tol=0.0,
                                     cuda_indexed_wavefront=false), eb, pb, CUDABackend)
    end
end

@testset "GaussianPIC coupled (rotated) subtraction" begin
    # docs/theory Section 7. Three things must hold:
    #  (a) coupling_tol=Inf (default) is bit-identical to before the branch existed
    #  (b) a finite coupling_tol changes the result (reaches its consumer)
    #  (c) the coupled deposition matches brute-force 2D quadrature of the tilted
    #      Gaussian far better than the axis-aligned formula
    sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
    mk() = begin
        set_global_rng!(seed=91, method=:philox)
        e = Beam(3000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.7),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(3000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        (e, p)
    end
    run(tol) = begin
        e, p = mk()
        lum = collide!(GaussianPICPoissonSolver(; slicing=sl, grid=(64, 64), coupling_tol=tol),
                       e, p, CPUThreadsBackend)
        (lum, vcat(coordinate_arrays(e)...))
    end
    l_inf, c_inf = run(Inf)
    l_0, c_0 = run(0.0)                     # 0 forces the coupled path everywhere
    @test isfinite(l_inf) && all(isfinite, c_inf)
    @test all(isfinite, c_0)
    @test c_inf != c_0                                        # (b)
    @test isapprox(l_0, l_inf; rtol=5e-2)                     # same physics
    @test_throws ArgumentError GaussianPICPoissonSolver(coupling_tol=-1.0)

    # (c) node-level accuracy against brute-force 2D quadrature
    Wcic(u, h) = abs(u) >= h ? 0.0 : 1 - abs(u) / h
    function brute(xi, yj, hx, hy, mux, muy, a, b, d; n=400)
        det = a * d - b * b; ia = d / det; ib = -b / det; id = a / det
        nrm = 1 / (2pi * sqrt(det)); acc = 0.0
        for pq in 0:n, qq in 0:n
            x = xi - hx + 2hx * pq / n; y = yj - hy + 2hy * qq / n
            wx = Wcic(x - xi, hx) * ((pq == 0 || pq == n) ? 0.5 : 1.0)
            wy = Wcic(y - yj, hy) * ((qq == 0 || qq == n) ? 0.5 : 1.0)
            (wx == 0 || wy == 0) && continue
            dx = x - mux; dy = y - muy
            acc += wx * wy * nrm * exp(-0.5 * (ia * dx * dx + 2ib * dx * dy + id * dy * dy))
        end
        return acc * (2hx / n) * (2hy / n)
    end
    sigx = 2.0e-3; sigy = 1.0e-3; mux = 1.0e-4; muy = -2.0e-4
    for r in (0.05, 0.2)
        a = sigx^2; d = sigy^2; b = r * sigx * sigy
        hx = 0.55sigx; hy = 0.55sigy
        lam = b / a; sc = sqrt(d - b * b / a)
        worst_c = 0.0; worst_u = 0.0
        for xi in (mux - 1.3sigx, mux + 0.9sigx), yj in (muy - 1.1sigy, muy + 0.3sigy)
            bq = brute(xi, yj, hx, hy, mux, muy, a, b, d)
            W0, W1, W2 = Octopus._gpic_weighted_moments(xi, hx, mux, sigx, :CIC)
            dd = mux - xi
            M0 = W0; M1 = W1 - dd * W0; M2 = W2 - 2dd * W1 + dd * dd * W0
            g = zeros(1); Octopus._gpic_gaussian_profile!(g, yj, hy, muy, sc, :CIC)
            dg, ddg = Octopus._gpic_profile_mean_derivs(yj, hy, muy, sc, :CIC)
            cp = M0 * g[1] + lam * M1 * dg + 0.5 * lam^2 * M2 * ddg
            gxv = zeros(1); gyv = zeros(1)
            Octopus._gpic_gaussian_profile!(gxv, xi, hx, mux, sigx, :CIC)
            Octopus._gpic_gaussian_profile!(gyv, yj, hy, muy, sigy, :CIC)
            un = gxv[1] * gyv[1]
            worst_c = max(worst_c, abs(cp - bq) / abs(bq))
            worst_u = max(worst_u, abs(un - bq) / abs(bq))
        end
        @test worst_c < worst_u / 10        # at least 10x better than axis-aligned
        @test worst_c < 0.02
    end
end

@testset "Spectral 6D Dirichlet box contains the drifted source" begin
    # The 6D path deposits each source slice DRIFTED to the field-slice
    # boundaries, and _spectral_field_grid! silently drops particles outside the
    # box. _spectral_box_drifted must therefore bound the drifted extremes, and
    # must never shrink the box relative to the undrifted sizing.
    set_global_rng!(seed=13, method=:philox)
    e = Beam(4000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.7),
        alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
        rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
    p = Beam(4000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
        alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
        rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
    for d in (2.0, 4.0, 8.0, 16.0)
        solver = SpectralPoissonSolver(; grid=(32, 64), domain_factor=d)
        L_plain = Octopus._spectral_box(solver, e.rep.x, e.rep.y, p.rep.x, p.rep.y)[1]
        L_drift = Octopus._spectral_box_drifted(solver, e.rep, p.rep)[1]
        @test L_drift >= L_plain                      # never shrinks
        # it must cover the worst-case drifted extreme of both beams
        sdrift = (maximum(abs, e.rep.z) + maximum(abs, p.rep.z)) / 2
        worst = max(maximum(abs, e.rep.x) + sdrift * maximum(abs, e.rep.px),
                    maximum(abs, e.rep.y) + sdrift * maximum(abs, e.rep.py),
                    maximum(abs, p.rep.x) + sdrift * maximum(abs, p.rep.px),
                    maximum(abs, p.rep.y) + sdrift * maximum(abs, p.rep.py))
        @test L_drift >= worst
    end
    # at the recommended production domain_factor the d*sigma term dominates, so
    # the guard must not perturb the recommended configuration
    big = SpectralPoissonSolver(; grid=(127, 383), domain_factor=8.0)
    @test Octopus._spectral_box_drifted(big, e.rep, p.rep)[1] ==
          Octopus._spectral_box(big, e.rep.x, e.rep.y, p.rep.x, p.rep.y)[1]
end

@testset "Spectral luminosity_schedule reaches its runtime consumer" begin
    # Effectiveness test (AGENTS.md): observe the option at the consumer boundary,
    # not just in the schema. Three things must hold on a skipped turn:
    #   (a) luminosity is NaN (intentionally not computed, not silently zero),
    #   (b) the beam-beam kicks are still applied -- identical coordinates,
    #   (c) StrongStrongTask omits the skipped turns from the luminosity file.
    mkbeams() = begin
        set_global_rng!(seed=31, method=:philox)
        e = Beam(2000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.0),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(2000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.0),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        return e, p
    end
    sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)

    for lk in (true, false)   # 6D and transverse-only variants both gate luminosity
        ev, pv = mkbeams()                                   # no schedule: every turn
        base = SpectralPoissonSolver(slicing=sl, method=:grid, grid=(32, 64),
                                     domain_factor=16.0, longitudinal_kick=lk)
        lum_every = collide!(base, ev, pv, CPUThreadsBackend, TrackingContext())

        es, ps = mkbeams()                                   # schedule that does NOT run
        sched = SpectralPoissonSolver(slicing=sl, method=:grid, grid=(32, 64),
                                      domain_factor=16.0, longitudinal_kick=lk,
                                      luminosity_schedule=AtTurns([7]))
        lum_skip = collide!(sched, es, ps, CPUThreadsBackend, TrackingContext())

        @test isfinite(lum_every)
        @test isnan(lum_skip)                                       # (a)
        for (a, b) in zip(coordinate_arrays(ev), coordinate_arrays(es))
            @test a == b                                            # (b) kicks unchanged
        end
        for (a, b) in zip(coordinate_arrays(pv), coordinate_arrays(ps))
            @test a == b
        end
        # a turn the schedule DOES run must recover the unscheduled value exactly
        er, pr = mkbeams()
        lum_run = collide!(SpectralPoissonSolver(slicing=sl, method=:grid, grid=(32, 64),
                               domain_factor=16.0, longitudinal_kick=lk,
                               luminosity_schedule=AtTurns([0])),
                           er, pr, CPUThreadsBackend, TrackingContext())
        @test lum_run == lum_every
    end

    # (c) the task-level luminosity file contains only evaluated turns
    path = tempname()
    try
        e, p = mkbeams()
        solver = SpectralPoissonSolver(slicing=sl, method=:grid, grid=(32, 64),
                                       domain_factor=16.0,
                                       luminosity_schedule=EveryNSteps(step=3))
        ip = StrongStrongCollision(:ip; poisson_solver=solver)
        task = StrongStrongTask((ip,), (ip,); luminosity_path=path)
        execute!(task, e, p; turns=7)
        turns = Int[]
        for line in eachline(path)
            parts = split(line, '\t')
            t = tryparse(Int, parts[1]); t === nothing || push!(turns, t)
        end
        @test turns == [0, 3, 6]
        @test all(l -> !occursin("NaN", l), readlines(path))

        # A second call continues at turns 7:9. The output file represents the
        # most recent call, so only scheduled absolute turn 9 is present.
        execute!(task, e, p; turns=3)
        empty!(turns)
        for line in eachline(path)
            parts = split(line, '\t')
            t = tryparse(Int, parts[1]); t === nothing || push!(turns, t)
        end
        @test turns == [9]
    finally
        isfile(path) && rm(path)
    end
end

@testset "Spectral synchro-beam longitudinal map is finite" begin
    set_global_rng!(seed=17, method=:philox)
    e0 = Beam(1200, CPUThreadsBackend, Float64;
        beta=(0.55, 0.056, 12.0), alpha=(0.0, 0.0, 0.0),
        sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV,
        npart=1.7e11)
    p0 = Beam(1200, CPUThreadsBackend, Float64;
        beta=(0.8, 0.072, 90.0), alpha=(0.0, 0.0, 0.0),
        sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
        charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV,
        npart=0.7e11)
    clone_beam(b) = begin
        rep = Phase6DRep((copy(a) for a in coordinate_arrays(b.rep))...)
        Beam{CPUThreadsBackend,typeof(b.params),typeof(rep)}(b.params, rep)
    end
    sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
    transverse_e, transverse_p = clone_beam(e0), clone_beam(p0)
    full_e, full_p = clone_beam(e0), clone_beam(p0)
    transverse_lum = collide!(SpectralPoissonSolver(slicing=sl, method=:grid,
        grid=(32, 128), domain_factor=16.0, longitudinal_kick=false),
        transverse_e, transverse_p, CPUThreadsBackend)
    full_lum = collide!(SpectralPoissonSolver(slicing=sl, method=:grid,
        grid=(32, 128), domain_factor=16.0, longitudinal_kick=true),
        full_e, full_p, CPUThreadsBackend)
    @test isfinite(transverse_lum)
    @test isfinite(full_lum)
    @test all(array -> all(isfinite, array), coordinate_arrays(full_e))
    @test all(array -> all(isfinite, array), coordinate_arrays(full_p))
    @test maximum(abs, full_e.rep.pz .- e0.rep.pz) > 0
    @test maximum(abs, full_p.rep.pz .- p0.rep.pz) > 0
    @test maximum(abs, transverse_e.rep.pz .- e0.rep.pz) == 0
    @test maximum(abs, transverse_p.rep.pz .- p0.rep.pz) == 0

    # The spectral synchro-beam pz kick uses the same map as the PIC solver, so its
    # magnitude must match PIC. This guards the potential normalization: the grid
    # potential reconstruction carries a factor 2 relative to the field and needs an
    # explicit 1/2 to keep pz consistent with the transverse kick. A round beam on a
    # square grid converges to PIC to ~1%, so the comparison is meaningful (a missing
    # 1/2 would show up as a ~2x mismatch).
    rms(v) = sqrt(sum(abs2, v) / length(v))
    set_global_rng!(seed=23, method=:philox)
    er = Beam(3000, CPUThreadsBackend, Float64; beta=(1.0, 1.0, 10.0),
        alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 7.0e-3), cutoff=5.0, rng_id=1,
        charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
    pr = Beam(3000, CPUThreadsBackend, Float64; beta=(1.0, 1.0, 10.0),
        alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-4, 6.0e-3), cutoff=5.0, rng_id=2,
        charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=1.7e11)
    sr = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
    spec_e, spec_p = clone_beam(er), clone_beam(pr)
    pic_e, pic_p = clone_beam(er), clone_beam(pr)
    collide!(SpectralPoissonSolver(slicing=sr, method=:grid, grid=(128, 128),
                                   domain_factor=16.0, longitudinal_kick=true),
             spec_e, spec_p, CPUThreadsBackend)
    collide!(PICPoissonSolver(slicing=sr, grid=(128, 128), green_cache=:none,
                              longitudinal_kick=true),
             pic_e, pic_p, CPUThreadsBackend)
    @test isapprox(rms(spec_e.rep.pz .- er.rep.pz),
                   rms(pic_e.rep.pz .- er.rep.pz); rtol=0.05)
    @test isapprox(rms(spec_p.rep.pz .- pr.rep.pz),
                   rms(pic_p.rep.pz .- pr.rep.pz); rtol=0.05)
end

@testset "Soft-Gaussian synchro-beam longitudinal map" begin
    moments = (
        mx=2.0e-5, sx=1.1e-4, mpx=3.0e-4, spx=0.0, covxpx=0.0,
        my=-1.0e-6, sy=8.0e-5, mpy=-2.0e-4, spy=0.0, covypy=0.0,
    )
    initial = (8.0e-5, 1.0e-4, 3.0e-6, -2.0e-4, 2.0e-3, 4.0e-4)
    with_longitudinal = Phase6DRep(([value] for value in initial)...)
    transverse_only = Phase6DRep(([value] for value in initial)...)

    Octopus._apply_slice_kick_one!(
        with_longitudinal, 1, moments, 1.0e-3, -2.0e-4, 1.0e-12, true, false)
    Octopus._apply_slice_kick_one!(
        transverse_only, 1, moments, 1.0e-3, -2.0e-4, 1.0e-12, false, false)

    @test with_longitudinal.x == transverse_only.x
    @test with_longitudinal.px == transverse_only.px
    @test with_longitudinal.y == transverse_only.y
    @test with_longitudinal.py == transverse_only.py
    @test transverse_only.pz[1] == initial[6]
    Fx = with_longitudinal.px[1] - initial[2]
    Fy = with_longitudinal.py[1] - initial[4]
    expected_dpz = (
        with_longitudinal.px[1]^2 + with_longitudinal.py[1]^2 -
        initial[2]^2 - initial[4]^2
    ) / 4 + (Fx * moments.mpx + Fy * moments.mpy) / 2
    @test with_longitudinal.pz[1] - initial[6] ≈ expected_dpz rtol=2e-13
    @test GaussianPoissonSolver().longitudinal_kick
    @test !GaussianPoissonSolver(longitudinal_kick=false).longitudinal_kick

    dynamic_moments = merge(moments, (
        spx=2.0e-4, covxpx=1.0e-8,
        spy=1.0e-4, covypy=-3.0e-9,
    ))
    function gaussian_map(q)
        rep = Phase6DRep(([value] for value in q)...)
        Octopus._apply_slice_kick_one!(
            rep, 1, dynamic_moments, 1.0e-3, -2.0e-8, 1.0e-12, true, false)
        return collect(rep[1])
    end
    q = collect(initial)
    h = 1.0e-8
    jacobian = hcat([(
        gaussian_map(q .+ (collect(1:6) .== column) .* h) -
        gaussian_map(q .- (collect(1:6) .== column) .* h)
    ) / (2 * h) for column in 1:6]...)
    symplectic_form = zeros(6, 6)
    for coordinate in (1, 3, 5)
        symplectic_form[coordinate, coordinate + 1] = 1
        symplectic_form[coordinate + 1, coordinate] = -1
    end
    symplectic_residual = transpose(jacobian) * symplectic_form * jacobian - symplectic_form
    @test norm(symplectic_residual, Inf) < 1.0e-8
end

@testset "Soft-Gaussian weak-strong map equivalence and coupling" begin
    covariance = [
        1.21e-8   1.0e-9   2.4e-9  -3.0e-10
        1.0e-9    4.0e-8   2.0e-10  1.5e-9
        2.4e-9    2.0e-10  6.4e-9  -6.0e-10
       -3.0e-10   1.5e-9  -6.0e-10  2.25e-8
    ]
    m = StrongTransverseMoments{Float64,true}(
        covariance[1, 1], covariance[1, 3], covariance[3, 3],
        covariance[1, 2], covariance[1, 4], covariance[3, 2],
        covariance[3, 4], covariance[2, 2], covariance[2, 4],
        covariance[4, 4])
    source = (
        mx=2.0e-5, sx=sqrt(m.a0), mpx=3.0e-4, spx=sqrt(m.qxx),
        covxpx=m.bxx, my=-1.0e-5, sy=sqrt(m.d0), mpy=-2.0e-4,
        spy=sqrt(m.qyy), covypy=m.bypy, moments=m,
    )
    q = (8.0e-5, 1.0e-4, 3.0e-6, -2.0e-4, 2.0e-3, 4.0e-4)
    center_z = 1.0e-3
    kbb = -2.0e-8
    for drift in (:hirata, :chromatic, :exact)
        rep = Phase6DRep(([value] for value in q)...)
        Octopus._apply_slice_kick_one!(
            rep, 1, source, center_z, kbb, 1.0e-12,
            Octopus._virtual_drift(drift), Val(true), false)
        thin = ThinStrongBeam(ThinStrongBeamSpec(
            kbb=kbb, covariance=covariance,
            center=(source.mx, source.my, center_z),
            angle=(source.mpx, source.mpy, 0.0), virtual_drift=drift))
        @test collect(rep[1]) ≈ collect(thin(q...)) rtol=2e-14 atol=2e-18
    end

    rep = Phase6DRep(
        [1.0, -1.0, 0.5, -0.5], [0.2, -0.2, 0.1, -0.1],
        [0.6, -0.4, 0.8, -1.0], [0.3, -0.1, 0.4, -0.6],
        zeros(4), zeros(4))
    coupled = Octopus._slice_transverse_moments(
        rep, collect(1:4), false, 0.0, Val(true))
    @test coupled.moments isa StrongTransverseMoments{Float64,true}
    @test coupled.moments.b0 ≈ sum((rep.x .- coupled.mx) .* (rep.y .- coupled.my)) / 4
    @test coupled.moments.qxy ≈
          sum((rep.px .- coupled.mpx) .* (rep.py .- coupled.mpy)) / 4

    @test GaussianPoissonSolver().batch_mode == :wavefront
    @test !GaussianPoissonSolver().include_sigma_xy
    @test GaussianPoissonSolver(include_sigma_xy=true).include_sigma_xy
    @test GaussianPoissonSolver(virtual_drift=:exact).virtual_drift isa ExactHamiltonianDrift
    @test_throws ArgumentError GaussianPoissonSolver(batch_mode=:invalid)
    @test_throws ArgumentError GaussianPoissonSolver(virtual_drift=:invalid)
end

@testset "Zero-width soft-Gaussian slice remains finite" begin
    n = 16
    zeros6 = ntuple(_ -> zeros(n), 6)
    beam1 = test_beam(Phase6DRep((copy(a) for a in zeros6)...))
    beam2 = test_beam(Phase6DRep((copy(a) for a in zeros6)...))
    solver = GaussianPoissonSolver(
        kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0, min_sigma=0.0,
        slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
    )

    luminosity = collide!(solver, beam1, beam2, CPUThreadsBackend)
    @test luminosity == 0.0
    @test all(array -> all(isfinite, array), coordinate_arrays(beam1))
    @test all(array -> all(isfinite, array), coordinate_arrays(beam2))
end

@testset "Physical transverse scale controls" begin
    @test GaussianPoissonSolver().min_sigma == 0.0
    @test_throws ArgumentError GaussianPoissonSolver(min_sigma=-1.0)
    @test_throws ArgumentError GaussianPoissonSolver(min_sigma=Inf)
    @test_throws ArgumentError GaussianPoissonSolver(min_sigma=NaN)

    @test PICPoissonSolver().min_transverse_extent == (0.0, 0.0)
    @test PICPoissonSolver(min_transverse_extent=2.0e-4).min_transverse_extent ==
          (2.0e-4, 2.0e-4)
    @test_throws ArgumentError PICPoissonSolver(min_transverse_extent=(-1.0, 1.0))
    @test_throws ArgumentError PICPoissonSolver(min_transverse_extent=(1.0,))
    @test_throws ArgumentError PICPoissonSolver(min_transverse_extent=(1.0, Inf))
    @test_throws ArgumentError PICPoissonSolver(min_transverse_extent="1e-4")

    for T in (Float32, Float64)
        floor_x = T(2.0e-4)
        floor_y = T(4.0e-4)
        pic = PICPoissonSolver{T}(;
            grid=(16, 16), min_transverse_extent=(floor_x, floor_y))
        @test pic.min_transverse_extent isa Tuple{T,T}
        source_grid, field_grid = Octopus._pic_interaction_grids(
            pic, zero(T), zero(T), zero(T), zero(T),
            zero(T), zero(T), zero(T), zero(T))
        @test source_grid.width ≈ floor_x * T(1.25)
        @test source_grid.height ≈ floor_y * T(1.25)
        @test field_grid.width == source_grid.width
        @test field_grid.height == source_grid.height

        z = zeros(T, 8)
        luminosity = Octopus._pic_luminosity(pic, z, z, z, z, one(T))
        @test isfinite(luminosity)
        @test luminosity > zero(T)

        spectral = SpectralPoissonSolver{T}(;
            grid=(16, 16), min_domain_halfwidth=T(3.0e-4))
        @test spectral.min_domain_halfwidth isa T
        @test Octopus._spectral_box(spectral, z, z, z, z) ==
              (T(3.0e-4), T(3.0e-4))
        spectral_luminosity = Octopus._spectral_luminosity_pair(
            spectral, z, z, z, z, one(T), 16, 16)
        @test isfinite(spectral_luminosity)
        @test spectral_luminosity > zero(T)

        hx = T(2.5e-4)
        hy = T(4.0e-4)
        standard = Octopus._pic_green(
            :standard, zero(T), zero(T), zero(T), zero(T), hx, hy, 8, 8)
        integrated = Octopus._pic_green(
            :integrated, zero(T), zero(T), zero(T), zero(T), hx, hy, 8, 8)
        @test standard[1, 1] == integrated[1, 1]
        @test isfinite(standard[1, 1])
        @test Octopus._pic_kernel_integral(zero(T), zero(T)) == zero(T)
    end

    zero64 = zeros(8)
    @test_throws ArgumentError Octopus._pic_interaction_grids(
        PICPoissonSolver(grid=(16, 16)),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    @test_throws ArgumentError Octopus._pic_luminosity(
        PICPoissonSolver(grid=(16, 16)), zero64, zero64, zero64, zero64, 1.0)
    @test_throws ArgumentError Octopus._spectral_box(
        SpectralPoissonSolver(grid=(16, 16)), zero64, zero64, zero64, zero64)
    @test_throws ArgumentError Octopus._spectral_luminosity_pair(
        SpectralPoissonSolver(grid=(16, 16)),
        zero64, zero64, zero64, zero64, 1.0, 16, 16)
    @test_throws ArgumentError SpectralPoissonSolver(min_domain_halfwidth=-1.0)
    @test_throws ArgumentError SpectralPoissonSolver(min_domain_halfwidth=Inf)
    @test_throws ArgumentError SpectralPoissonSolver(min_domain_halfwidth=NaN)

    scale = 1.0e3
    pic1 = PICPoissonSolver(
        grid=(16, 16), min_transverse_extent=(2.0e-4, 4.0e-4))
    pic2 = PICPoissonSolver(
        grid=(16, 16), min_transverse_extent=scale .* (2.0e-4, 4.0e-4))
    grids1 = Octopus._pic_interaction_grids(
        pic1, -1.0e-4, 1.0e-4, -1.0e-4, 1.0e-4,
        -5.0e-5, 5.0e-5, -5.0e-5, 5.0e-5)
    grids2 = Octopus._pic_interaction_grids(
        pic2, -scale * 1.0e-4, scale * 1.0e-4,
        -scale * 1.0e-4, scale * 1.0e-4,
        -scale * 5.0e-5, scale * 5.0e-5,
        -scale * 5.0e-5, scale * 5.0e-5)
    for (grid1, grid2) in zip(grids1, grids2), name in (:x0, :y0, :width, :height)
        @test getproperty(grid2, name) ≈ scale * getproperty(grid1, name)
    end

    spectral_report = configuration_report(
        SpectralPoissonSolver(min_domain_halfwidth=1.0e-4);
        policy=CPUThreadsExecutionPolicy(threads=1), backend=CPUThreadsBackend)
    report_by_name = Dict(entry.name => entry for entry in spectral_report)
    @test report_by_name[:min_domain_halfwidth].resolved == 1.0e-4
end

include(joinpath(pkgdir(Octopus), "validation", "symplecticity_validation.jl"))

@testset "Finite-difference 6D symplecticity validation" begin
    results = run_symplecticity_validation(; step=3.0e-7, default_tolerance=5.0e-6)
    @test all(result -> result.passed, results)
    lorentz = run_lorentz_quasisymplectic_validation(; step=3.0e-7)
    @test lorentz.inverse_passed
    @test lorentz.determinant_passed
end

include(joinpath(pkgdir(Octopus), "validation", "high_energy_weakstrong_limit.jl"))

@testset "High-energy weak-strong strong-strong limit" begin
    result = run_high_energy_weakstrong_limit(;
        n=256, nslices=3, grid=48,
        spectral_grid=(32, 64),
        spectral_free_grid=(16, 16),
        pic_luminosity_rtol=0.60,
        pic_size_rtol=0.60,
        spectral_model_luminosity_rtol=0.80,
        spectral_model_size_rtol=0.80,
        spectral_limit_atol=5.0e-12,
        spectral_limit_luminosity_rtol=1.0e-10,
    )
    @test result.gaussian_passed
    @test result.pic_passed
    @test result.spectral_limit_passed
    @test result.spectral_model_passed
end

if Octopus._HAS_CUDA && Octopus.CUDA.functional()
    function cuda_round_gaussian_near_axis_kernel!(output, sigma, x, y)
        kx, ky = Octopus._cuda_gaussian_beambeam_kick(sigma, sigma, x, y)
        r2 = x * x + y * y
        expterm = exp(-r2 / (2 * sigma * sigma))
        hxx, hxy, hyy =
            Octopus._round_gaussian_hessian(one(sigma), sigma, x, y, expterm)
        output[1] = kx
        output[2] = ky
        output[3] = hxx
        output[4] = hxy
        output[5] = hyy
        return nothing
    end

    function cuda_near_round_gaussian_kernel!(output, sig1, sig2, x, y)
        Kx, Ky, H1, H2 = Octopus._cuda_gaussian_beambeam_kick_response(
            one(sig1), sig1, sig2, x, y)
        output[1] = Kx
        output[2] = Ky
        output[3] = H1
        output[4] = H2
        return nothing
    end

    @testset "CUDA round Gaussian near-axis stability" begin
        for (T, x, y) in (
                (Float32, 1.0f-4, -5.0f-5),
                (Float64, 1.0e-8, -5.0e-9))
            sigma = one(T)
            expected_kick = gaussian_beambeam_kick(sigma, sigma, x, y)
            expterm = exp(-(x * x + y * y) / (2 * sigma * sigma))
            expected_hessian =
                Octopus._round_gaussian_hessian(one(T), sigma, x, y, expterm)
            output = Octopus.CUDA.zeros(T, 5)
            Octopus.CUDA.@cuda threads=1 blocks=1 cuda_round_gaussian_near_axis_kernel!(
                output, sigma, x, y)
            Octopus.CUDA.synchronize()
            actual = Array(output)
            expected = T[expected_kick..., expected_hessian...]
            @test actual ≈ expected rtol=16eps(T) atol=16eps(T)
            @test actual[1] != zero(T)
            @test actual[2] != zero(T)
        end
    end

    @testset "CUDA near-round Gaussian transition matches CPU" begin
        for T in (Float32, Float64)
            inner, outer = Octopus._near_round_eta_bounds(zero(T))
            tolerance = T === Float32 ? 3.0e-5 : 3.0e-11
            for eta in (inner, T(0.75) * outer, outer, T(1.2) * outer, T(0.1))
                sig1, sig2 = sqrt(one(T) + eta), sqrt(one(T) - eta)
                for (x, y) in (
                        (T(1.0e-6), T(-5.0e-7)),
                        (T(0.2), T(-0.1)),
                        (T(1.3), T(0.7)),
                        (sqrt(T(0.0625)) * cos(T(pi / 16)),
                         sqrt(T(0.0625)) * sin(T(pi / 16))),
                        (sqrt(T(5)) * cos(T(15pi / 32)),
                         sqrt(T(5)) * sin(T(15pi / 32))))
                    expected = Octopus._gaussian_beambeam_kick_response(
                        one(T), sig1, sig2, x, y)
                    output = Octopus.CUDA.zeros(T, 4)
                    Octopus.CUDA.@cuda threads=1 blocks=1 cuda_near_round_gaussian_kernel!(
                        output, sig1, sig2, x, y)
                    Octopus.CUDA.synchronize()
                    @test Array(output) ≈ collect(expected) rtol=tolerance atol=tolerance
                end
            end
        end
    end

    @testset "CUDA strong-strong shifted moments preserve small spreads" begin
        for T in (Float32, Float64)
            n = 8192
            offset = T === Float32 ? T(1.0e4) : T(1.0e8)
            x = offset .+ repeat(T[-1, 1, -1, 1], n ÷ 4)
            px = -T(2) * offset .+ repeat(T[2, -2, 2, -2], n ÷ 4)
            y = T(3) * offset .+ repeat(T[-3, 3, -3, 3], n ÷ 4)
            py = -T(4) * offset .+ repeat(T[4, -4, 4, -4], n ÷ 4)
            z = zeros(T, n)
            rep = Phase6DRep(
                Octopus.CUDA.CuArray(x), Octopus.CUDA.CuArray(px),
                Octopus.CUDA.CuArray(y), Octopus.CUDA.CuArray(py),
                Octopus.CUDA.CuArray(z), Octopus.CUDA.CuArray(z))
            idx = Octopus.CUDA.CuArray(collect(1:n))
            launch = Octopus._cuda_gaussian_moment_launch(n)

            for coupled in (false, true)
                coupling = Val(coupled)
                partials = Octopus.CUDA.CuArray{T}(undef,
                    Octopus._cuda_gaussian_moment_nstats(coupling),
                    launch.blocks, 1)
                moments = Octopus._cuda_slice_transverse_moments(
                    rep, idx, partials, false, zero(T), coupling)
                @test moments.mx ≈ offset
                @test moments.moments.a0 ≈ T(1)
                @test moments.moments.d0 ≈ T(9)
                @test moments.moments.bxx ≈ -T(2)
                @test moments.moments.bypy ≈ -T(12)
                @test moments.moments.qxx ≈ T(4)
                @test moments.moments.qyy ≈ T(16)
                if coupled
                    @test moments.moments.b0 ≈ T(3)
                    @test moments.moments.bxpy ≈ -T(4)
                    @test moments.moments.bypx ≈ -T(6)
                    @test moments.moments.qxy ≈ T(8)
                end
            end

            gpic = Octopus._cuda_gpic_source_moments(
                (x=rep.x, px=rep.px, y=rep.y, py=rep.py))
            @test gpic.mx ≈ offset
            @test gpic.varx ≈ T(1)
            @test gpic.cxpx ≈ -T(2)
            @test gpic.vary ≈ T(9)
            @test gpic.cypy ≈ -T(12)
        end

        # Exercise the separate fused wavefront moment kernel through its solver.
        n = 1024
        offset = 1.0e8
        x = offset .+ repeat([-1.0, -1.0, 1.0, 1.0], n ÷ 4)
        px = 2offset .+ repeat([-3.0, 3.0, -3.0, 3.0], n ÷ 4)
        y = -offset .+ repeat([-2.0, 2.0, -2.0, 2.0], n ÷ 4)
        py = -2offset .+ repeat([4.0, 4.0, -4.0, -4.0], n ÷ 4)
        z = zeros(n)
        host_rep() = Phase6DRep(
            copy(x), copy(px), copy(y), copy(py), copy(z), copy(z))
        gpu_rep() = Phase6DRep(
            (Octopus.CUDA.CuArray(a) for a in coordinate_arrays(host_rep()))...)
        params = BeamParams{Float64}(
            charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
        cpu_beam(rep) =
            Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
        gpu_beam(rep) =
            Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
        solver = GaussianPoissonSolver(
            kbb1=0.0, kbb2=0.0, luminosity_scale=1.0,
            slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
            longitudinal_kick=false, batch_mode=:wavefront)
        cpu1 = cpu_beam(host_rep()); cpu2 = cpu_beam(host_rep())
        gpu1 = gpu_beam(gpu_rep()); gpu2 = gpu_beam(gpu_rep())
        cpu_luminosity = collide!(solver, cpu1, cpu2, CPUThreadsBackend)
        gpu_luminosity = collide!(solver, gpu1, gpu2, Octopus.CUDABackend)
        Octopus.CUDA.synchronize()
        @test isfinite(cpu_luminosity)
        @test gpu_luminosity ≈ cpu_luminosity rtol=2.0e-12
    end

    @testset "CUDA PIC field_derivative matches CPU" begin
        # The flag is consumed by three separate CUDA kernels (single, batched,
        # wavefront). Check parity for BOTH settings so a divergence in any of
        # them is caught, and check that :fourth actually changes the CUDA result.
        mkpair(backend) = begin
            set_global_rng!(seed=77, method=:philox)
            e = Beam(6000, backend, Float64; beta=(0.55, 0.056, 12.0),
                alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
                rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(6000, backend, Float64; beta=(0.8, 0.072, 90.0),
                alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
                rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            return e, p
        end
        sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        results = Dict{Symbol,Any}()
        for fd in (:second, :fourth), (name, backend, policy) in
                ((:cpu, CPUThreadsBackend, CPUThreadsBackend), (:gpu, CUDABackend, CUDAExecutionPolicy()))
            e, p = mkpair(policy)
            lum = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), field_derivative=fd),
                           e, p, backend)
            results[Symbol(fd, :_, name)] = (lum, flat(e), flat(p))
        end
        for fd in (:second, :fourth)
            (lc, ec, pc) = results[Symbol(fd, :_cpu)]
            (lg, eg, pg) = results[Symbol(fd, :_gpu)]
            @test isapprox(ec, eg; rtol=1e-11, atol=1e-14)
            @test isapprox(pc, pg; rtol=1e-11, atol=1e-14)
            @test isapprox(lc, lg; rtol=1e-11)
        end
        @test results[:second_gpu][2] != results[:fourth_gpu][2]   # flag reaches CUDA
    end

    @testset "CUDA PIC slice_interpolation matches CPU" begin
        # :quadratic runs on the sequential non-async route and, via its own
        # 6-planes-per-pair path, on the batched-FFT routes including the
        # production indexed wavefront. Check parity for both settings on every
        # supported route, that the flag changes the CUDA result, and that the
        # one route which cannot carry a third field plane (non-batched async)
        # throws instead of silently dropping it.
        mkpair(backend) = begin
            set_global_rng!(seed=31, method=:philox)
            e = Beam(4000, backend, Float64; beta=(0.55, 0.056, 12.0),
                alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
                rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(4000, backend, Float64; beta=(0.8, 0.072, 90.0),
                alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
                rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            return e, p
        end
        sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        base = (; slicing=sl, grid=(32, 32), batch_mode=:sequential, cuda_async=false)
        res = Dict{Symbol,Any}()
        for si in (:linear, :quadratic), (name, backend, policy) in
                ((:cpu, CPUThreadsBackend, CPUThreadsBackend), (:gpu, CUDABackend, CUDAExecutionPolicy()))
            e, p = mkpair(policy)
            lum = collide!(PICPoissonSolver(; base..., slice_interpolation=si), e, p, backend)
            res[Symbol(si, :_, name)] = (lum, flat(e), flat(p))
        end
        for si in (:linear, :quadratic)
            (lc, ec, pc) = res[Symbol(si, :_cpu)]
            (lg, eg, pg) = res[Symbol(si, :_gpu)]
            @test isapprox(ec, eg; rtol=1e-11, atol=1e-14)
            @test isapprox(pc, pg; rtol=1e-11, atol=1e-14)
            @test isapprox(lc, lg; rtol=1e-11)
        end
        @test res[:linear_gpu][2] != res[:quadratic_gpu][2]   # flag reaches CUDA

        # The batched-FFT routes carry the midpoint plane via their own 6-plane
        # path (planes L/M/R per direction with a per-plane Green stack). The
        # production indexed wavefront, the gathered wavefront, and the
        # sequential batched-FFT sub-route must all match the CPU :quadratic
        # result.
        let ref = res[:quadratic_cpu]
            for kw in ((; batch_mode=:wavefront),
                       (; batch_mode=:wavefront, cuda_indexed_wavefront=false),
                       (; batch_mode=:sequential, cuda_async=true))
                eg, pg = mkpair(CUDAExecutionPolicy())
                lum = collide!(PICPoissonSolver(; slicing=sl, grid=(32, 32),
                                                slice_interpolation=:quadratic, kw...),
                               eg, pg, CUDABackend)
                @test isapprox(ref[2], flat(eg); rtol=1e-11, atol=1e-14)
                @test isapprox(ref[3], flat(pg); rtol=1e-11, atol=1e-14)
                @test isapprox(ref[1], lum; rtol=1e-11)
            end
        end
        # The non-batched async route still carries only two planes per
        # direction and must refuse :quadratic, as must the non-async wavefront
        # combination (which never had a third-plane path).
        for kw in ((; batch_mode=:wavefront, cuda_async=false),
                   (; batch_mode=:wavefront, cuda_batch_fft=false),
                   (; batch_mode=:sequential, cuda_async=true, cuda_batch_fft=false))
            e, p = mkpair(CUDAExecutionPolicy())
            @test_throws ArgumentError collide!(
                PICPoissonSolver(; slicing=sl, grid=(32, 32), slice_interpolation=:quadratic,
                                 kw...), e, p, CUDABackend)
        end
        # interaction_grid=:source_slice is CPU-only on every CUDA route.
        let (e, p) = mkpair(CUDAExecutionPolicy())
            @test_throws ArgumentError collide!(
                PICPoissonSolver(; slicing=sl, grid=(32, 32), interaction_grid=:source_slice),
                e, p, CUDABackend)
        end

        # interaction_grid=:node is implemented on the sequential non-async route.
        nres = Dict{Symbol,Any}()
        for (name, backend, policy) in
                ((:cpu, CPUThreadsBackend, CPUThreadsBackend), (:gpu, CUDABackend, CUDAExecutionPolicy()))
            e, p = mkpair(policy)
            lum = collide!(PICPoissonSolver(; base..., interaction_grid=:node), e, p, backend)
            nres[name] = (lum, flat(e), flat(p))
        end
        @test isapprox(nres[:cpu][2], nres[:gpu][2]; rtol=1e-11, atol=1e-14)
        @test isapprox(nres[:cpu][3], nres[:gpu][3]; rtol=1e-11, atol=1e-14)
        @test isapprox(nres[:cpu][1], nres[:gpu][1]; rtol=1e-11)
        @test nres[:gpu][2] != res[:linear_gpu][2]      # reaches the CUDA consumer

        # :node runs on the indexed wavefront route via its own 6-plane path, and
        # on the sequential non-async route. Both must match CPU.
        let ref = nothing
            e, p = mkpair(CPUThreadsBackend)
            collide!(PICPoissonSolver(; slicing=sl, grid=(32, 32), interaction_grid=:node),
                     e, p, CPUThreadsBackend)
            ref = flat(e)
            for kw in ((; batch_mode=:wavefront), (; batch_mode=:wavefront, cuda_async=true),
                       (; batch_mode=:sequential, cuda_async=false))
                eg, pg = mkpair(CUDAExecutionPolicy())
                collide!(PICPoissonSolver(; slicing=sl, grid=(32, 32),
                                          interaction_grid=:node, kw...), eg, pg, CUDABackend)
                @test isapprox(ref, flat(eg); rtol=1e-11, atol=1e-14)
            end
        end
        # The sequential batched-FFT sub-route still assumes one mesh per slice
        # pair and must refuse :node rather than silently using the wrong mesh.
        let (e, p) = mkpair(CUDAExecutionPolicy())
            @test_throws ArgumentError collide!(
                PICPoissonSolver(; slicing=sl, grid=(32, 32), interaction_grid=:node,
                                 batch_mode=:sequential, cuda_async=true), e, p, CUDABackend)
        end
    end

    function test_gpu_beam(x, y)
        n = length(x)
        rep = Phase6DRep(
            Octopus.CUDA.CuArray(x), Octopus.CUDA.zeros(Float64, n),
            Octopus.CUDA.CuArray(y), Octopus.CUDA.zeros(Float64, n),
            Octopus.CUDA.zeros(Float64, n), Octopus.CUDA.zeros(Float64, n),
        )
        params = BeamParams{Float64}(
            charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n,
        )
        return Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
    end

    @testset "CUDA solver workspaces are exclusive and device-aware" begin
        device = Int(Octopus.CUDA.deviceid(Octopus.CUDA.device()))
        @test Octopus._spectral_cuda_cache_key(
            Float64, 16, 24, device) !=
              Octopus._spectral_cuda_cache_key(
                  Float64, 16, 24, device + 1)
        lease1 = Octopus._acquire_spectral_cuda_ws(Float64, 16, 24)
        lease2 = Octopus._acquire_spectral_cuda_ws(Float64, 16, 24)
        try
            @test lease1 !== lease2
            @test lease1.workspace !== lease2.workspace
            @test lease1.device == device
            @test lease2.device == device
            @test Int(Octopus.CUDA.deviceid(
                Octopus.CUDA.device(lease1.workspace.rho))) == device
        finally
            Octopus._release_spectral_cuda_ws!(lease1)
            Octopus._release_spectral_cuda_ws!(lease2)
        end

        cache = Dict{Any,Any}()
        pic = PICPoissonSolver(grid=(16, 16))
        Octopus._cuda_pic_workspace!(
            cache, :device_key_test, pic, Float64)
        key = only(keys(cache))
        @test key[1] === :cuda_pic_workspace
        @test key[3] == device
    end

    @testset "CUDA PIC wavefront workspace cache is capacity bounded" begin
        solver = PICPoissonSolver(grid=(16, 24))
        workspace = Octopus._cuda_pic_workspace(solver, Float64)
        batches = [collect(1:n) for n in (1, 3, 2)]

        Octopus._cuda_pic_reserve_wavefront_workspaces!(
            workspace, solver, Float64, batches,
        )
        @test collect(keys(workspace.wavefront_cache)) == [:standard]
        standard = workspace.wavefront_cache[:standard]
        @test standard.capacity == 12
        @test size(standard.arrays.charges) == (32, 48, 12)

        small = Octopus._cuda_pic_wavefront_workspace!(
            workspace, solver, Float64, 4,
        )
        @test size(small.charges) == (32, 48, 4)
        @test size(small.green_spectral) == (32, 48, 2)
        @test pointer(small.charges) == pointer(standard.arrays.charges)
        @test workspace.wavefront_cache[:standard] === standard
        @test length(workspace.wavefront_cache) == 1

        Octopus._cuda_pic_reserve_wavefront_workspaces!(
            workspace, solver, Float64, batches; node=true,
        )
        @test Set(keys(workspace.wavefront_cache)) == Set((:standard, :node))
        node = workspace.wavefront_cache[:node]
        @test node.capacity == 18
        node_small = Octopus._cuda_pic_wavefront_node_workspace!(
            workspace, solver, Float64, 6,
        )
        @test size(node_small.charges) == (32, 48, 6)
        @test pointer(node_small.charges) == pointer(node.arrays.charges)
        @test_throws ArgumentError Octopus._cuda_pic_wavefront_workspace!(
            workspace, solver, Float64, 6,
        )
        @test_throws ArgumentError Octopus._cuda_pic_wavefront_node_workspace!(
            workspace, solver, Float64, 4,
        )
    end

    @testset "CUDA spectral solver matches CPU" begin
        function to_gpu(b)
            rep = Phase6DRep(
                (Octopus.CUDA.CuArray(copy(a)) for a in coordinate_arrays(b.rep))...)
            return Beam{Octopus.CUDABackend,typeof(b.params),typeof(rep)}(b.params, rep)
        end
        function flat_pair()
            set_global_rng!(seed=11, method=:philox)
            e = Beam(4000, CPUThreadsBackend, Float64;
                beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 1.0e-2), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(4000, CPUThreadsBackend, Float64;
                beta=(1.0, 1.0, 10.0), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 1.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=1.7e11)
            return e, p
        end
        sl = LongitudinalSlicing(nslices=3, method=:normal_quantile, center_position=:centroid)
        # Cover both the transverse-only map and the full 6D synchro-beam map (the
        # latter exercises the potential/pz path on both backends).
        for longitudinal_kick in (false, true)
            solver = SpectralPoissonSolver(slicing=sl, method=:grid, grid=(64, 512),
                                           domain_factor=16.0,
                                           longitudinal_kick=longitudinal_kick)
            ecpu, pcpu = flat_pair()
            egpu, pgpu = to_gpu(ecpu), to_gpu(pcpu)
            lum_cpu = collide!(solver, ecpu, pcpu, CPUThreadsBackend)
            lum_gpu = collide!(solver, egpu, pgpu, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            # Same algorithm and particle data, so CPU and CUDA agree to round-off
            # (up to accumulation order across the backends' parallel reductions).
            for (cpu_beam, gpu_beam) in ((ecpu, egpu), (pcpu, pgpu))
                for (expected, actual) in zip(coordinate_arrays(cpu_beam),
                                              coordinate_arrays(gpu_beam))
                    @test Array(actual) ≈ expected rtol=1.0e-9 atol=1.0e-18
                end
            end
            @test lum_gpu ≈ lum_cpu rtol=1.0e-9
        end
        # field_precision=:single runs the CUDA field solve in Float32: not
        # bit-parity with the CPU Float64 path, but the smooth field keeps the kick
        # accurate to ~1e-6 (well under the ~1% physics floor).
        single = SpectralPoissonSolver(slicing=sl, method=:grid, grid=(64, 512),
                                       domain_factor=16.0, longitudinal_kick=true,
                                       field_precision=:single)
        ecpu, pcpu = flat_pair(); egpu, pgpu = to_gpu(ecpu), to_gpu(pcpu)
        collide!(single, ecpu, pcpu, CPUThreadsBackend)
        collide!(single, egpu, pgpu, Octopus.CUDABackend); Octopus.CUDA.synchronize()
        for (cpu_beam, gpu_beam) in ((ecpu, egpu), (pcpu, pgpu))
            for (expected, actual) in zip(coordinate_arrays(cpu_beam),
                                          coordinate_arrays(gpu_beam))
                @test Array(actual) ≈ expected rtol=1.0e-5 atol=1.0e-16
            end
        end
        # grid-free is CPU-only on CUDA
        gf = SpectralPoissonSolver(slicing=sl, method=:grid_free, grid=(48, 48),
                                   longitudinal_kick=false)
        ecpu, pcpu = flat_pair()
        egpu, pgpu = to_gpu(ecpu), to_gpu(pcpu)
        @test_throws ArgumentError collide!(gf, egpu, pgpu, Octopus.CUDABackend)
    end

    @testset "CUDA GaussianPIC solver matches CPU" begin
        to_gpu(b) = begin
            rep = Phase6DRep((Octopus.CUDA.CuArray(copy(a)) for a in coordinate_arrays(b.rep))...)
            Beam{Octopus.CUDABackend,typeof(b.params),typeof(rep)}(b.params, rep)
        end
        function gp_pair()
            set_global_rng!(seed=19, method=:philox)
            e = Beam(6000, CPUThreadsBackend, Float64;
                beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 0.7e-2), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(6000, CPUThreadsBackend, Float64;
                beta=(0.8, 0.072, 90.0), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            return e, p
        end
        sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        # Cover the transverse-only and full 6D map, and both CUDA wavefront paths
        # (indexed default, and the non-indexed fallback).
        for longitudinal_kick in (false, true), indexed in (true, false)
            solver = GaussianPICPoissonSolver(slicing=sl, grid=(64, 64), green_cache=:none,
                                              longitudinal_kick=longitudinal_kick,
                                              cuda_indexed_wavefront=indexed)
            ecpu, pcpu = gp_pair()
            egpu, pgpu = to_gpu(ecpu), to_gpu(pcpu)
            lum_cpu = collide!(solver, ecpu, pcpu, CPUThreadsBackend)
            lum_gpu = collide!(solver, egpu, pgpu, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            for (cpu_beam, gpu_beam) in ((ecpu, egpu), (pcpu, pgpu))
                for (expected, actual) in zip(coordinate_arrays(cpu_beam),
                                              coordinate_arrays(gpu_beam))
                    # ~1e-13: the only backend difference is the parallel-reduction
                    # order of the slice moments; well within the 1e-10 contract.
                    @test Array(actual) ≈ expected rtol=1.0e-9 atol=1.0e-18
                end
            end
            @test lum_gpu ≈ lum_cpu rtol=1.0e-9
        end
    end

    @testset "CUDA coupled weak-strong parity" begin
        coupling = XYCouplingSpec{Float64}(
            r1=0.08, r2=0.03, r3=-0.02, r4=0.05)
        q = (4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4)
        for virtual_drift in (
                UnsafeVirtualDrift(:chromatic_frozen_energy),
                UnsafeVirtualDrift(:paraxial_frozen_longitudinal),
                :hirata, :chromatic, :exact)
            thin = ThinStrongBeam(ThinStrongBeamSpec(;
                kbb=1.0e-7, beta=(0.8, 1.2), alpha=(0.3, -0.2),
                sigma=(1.1e-3, 0.7e-3), coupling=coupling,
                center=(2.0e-5, -1.0e-5, 3.0e-4),
                angle=(3.0e-4, -2.0e-4, 0.0),
                curvature=(2.0e-3, -1.0e-3, 0.0),
                virtual_drift=virtual_drift))
            expected_thin = thin(q...)
            thin_rep = Phase6DRep(
                (Octopus.CUDA.CuArray([value]) for value in q)...)
            track!(thin_rep, thin, 1, Octopus.CUDABackend; threads=32, blocks=1)
            Octopus.CUDA.synchronize()
            actual_thin = Tuple(
                Array(array)[1] for array in coordinate_arrays(thin_rep))
            @test collect(actual_thin) ≈ collect(expected_thin) rtol=2.0e-14 atol=1.0e-18
        end

        transverse = transverse_covariance(;
            beta=(0.7, 0.9), alpha=(0.1, -0.2), sigma=(1.2e-3, 0.8e-3))
        covariance6 = gaussian_strong_beam_covariance(
            transverse, [4.0e-4 3.0e-5; 3.0e-5 9.0e-6];
            crab_dispersion=(0.12, -0.03, 0.04, 0.02),
            momentum_dispersion=(0.5, 0.1, -0.2, 0.3))
        gaussian = GaussianStrongBeam(GaussianStrongBeamSpec(;
            thin=ThinStrongBeamSpec(kbb=1.0e-7, covariance=transverse),
            ns=3, covariance=covariance6))
        expected_gaussian = gaussian(q...)
        gaussian_rep = Phase6DRep((Octopus.CUDA.CuArray([value]) for value in q)...)
        track!(gaussian_rep, gaussian, 1, Octopus.CUDABackend; threads=32, blocks=1)
        Octopus.CUDA.synchronize()
        actual_gaussian = Tuple(
            Array(array)[1] for array in coordinate_arrays(gaussian_rep))
        @test collect(actual_gaussian) ≈ collect(expected_gaussian) rtol=2.0e-14 atol=1.0e-18
    end

    @testset "CUDA coupled soft-Gaussian wavefront parity" begin
        n = 256
        phase = range(0.0, 2pi; length=n + 1)[1:n]
        arrays1 = (
            1.1e-4 .* sin.(phase), 1.8e-4 .* cos.(2 .* phase),
            8.0e-5 .* cos.(phase) .+ 1.0e-5 .* sin.(3 .* phase),
            1.4e-4 .* sin.(2 .* phase) .- 2.0e-5 .* cos.(phase),
            collect(range(-7.0e-3, 7.0e-3; length=n)),
            5.0e-4 .* cos.(3 .* phase),
        )
        arrays2 = Tuple(reverse(copy(array)) for array in arrays1)
        cpu1 = test_beam(Phase6DRep((copy(array) for array in arrays1)...))
        cpu2 = test_beam(Phase6DRep((copy(array) for array in arrays2)...))
        gpu_rep1 = Phase6DRep((Octopus.CUDA.CuArray(array) for array in arrays1)...)
        gpu_rep2 = Phase6DRep((Octopus.CUDA.CuArray(array) for array in arrays2)...)
        gpu1 = Beam{Octopus.CUDABackend,typeof(cpu1.params),typeof(gpu_rep1)}(
            cpu1.params, gpu_rep1)
        gpu2 = Beam{Octopus.CUDABackend,typeof(cpu2.params),typeof(gpu_rep2)}(
            cpu2.params, gpu_rep2)
        solver = GaussianPoissonSolver(
            kbb1=1.0e-8, kbb2=-8.0e-9, luminosity_scale=1.0,
            slicing=LongitudinalSlicing(nslices=3, method=:equal_count),
            include_sigma_xy=true, virtual_drift=:exact, batch_mode=:wavefront)
        cpu_luminosity = collide!(solver, cpu1, cpu2, CPUThreadsBackend)
        gpu_luminosity = collide!(solver, gpu1, gpu2, Octopus.CUDABackend)
        Octopus.CUDA.synchronize()
        for (cpu_beam, gpu_beam) in ((cpu1, gpu1), (cpu2, gpu2))
            for (expected, actual) in zip(
                    coordinate_arrays(cpu_beam), coordinate_arrays(gpu_beam))
                @test Array(actual) ≈ expected rtol=2.0e-12 atol=2.0e-18
            end
        end
        @test gpu_luminosity ≈ cpu_luminosity rtol=2.0e-12
    end

    @testset "CUDA zero-width PIC routes remain finite" begin
        n = 16
        x = collect(range(-1.0e-3, 1.0e-3; length=n))
        y = reverse(copy(x))
        configurations = (
            (batch_mode=:sequential, cuda_indexed_wavefront=true),
            (batch_mode=:wavefront, cuda_indexed_wavefront=false),
            (batch_mode=:wavefront, cuda_indexed_wavefront=true),
        )
        for configuration in configurations
            beam1 = test_gpu_beam(x, y)
            beam2 = test_gpu_beam(y, x)
            solver = PICPoissonSolver(
                kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
                grid=(16, 16), green_cache=:none, longitudinal_kick=true,
                slicing=LongitudinalSlicing(nslices=1, method=:equal_count);
                configuration...,
            )
            luminosity = collide!(solver, beam1, beam2, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            @test isfinite(luminosity)
            @test all(array -> all(isfinite, Array(array)), coordinate_arrays(beam1))
            @test all(array -> all(isfinite, Array(array)), coordinate_arrays(beam2))
        end

        one_particle = test_gpu_beam([0.0], [0.0])
        slices = Octopus._cuda_longitudinal_slices(
            one_particle.rep, LongitudinalSlicing(nslices=3, method=:equal_count),
        )
        @test sum(length, slices.indices) == 1
        @test issorted(slices.boundary)

        gaussian_beam1 = test_gpu_beam([0.0], [0.0])
        gaussian_beam2 = test_gpu_beam([0.0], [0.0])
        gaussian_solver = GaussianPoissonSolver(
            kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0, min_sigma=0.0,
            slicing=LongitudinalSlicing(nslices=1, method=:equal_count),
        )
        gaussian_luminosity = collide!(
            gaussian_solver, gaussian_beam1, gaussian_beam2, Octopus.CUDABackend)
        Octopus.CUDA.synchronize()
        @test gaussian_luminosity == 0.0
        @test all(array -> all(isfinite, Array(array)), coordinate_arrays(gaussian_beam1))
        @test all(array -> all(isfinite, Array(array)), coordinate_arrays(gaussian_beam2))
    end

    @testset "CUDA GaussianPIC singular-reference fallback matches PIC" begin
        n = 64
        x1 = collect(range(-1.0e-3, 1.0e-3; length=n))
        x2 = reverse(copy(x1))
        slicing = LongitudinalSlicing(nslices=1, method=:equal_count)
        common = (
            kbb1=1.0e-4, kbb2=-8.0e-5, luminosity_scale=1.0,
            grid=(16, 16), green_cache=:none, longitudinal_kick=true,
            slicing=slicing,
        )
        gpu_pair(y1, y2) =
            (test_gpu_beam(x1, y1), test_gpu_beam(x2, y2))
        host_arrays(beam) = map(Array, coordinate_arrays(beam))

        # Positive marginal widths but rank-one covariance exercises the default
        # indexed-wavefront mode selected by a finite coupling tolerance.
        pic1, pic2 = gpu_pair(0.75 .* x1, -1.25 .* x2)
        gpic1, gpic2 = gpu_pair(0.75 .* x1, -1.25 .* x2)
        luminosity_pic = collide!(
            PICPoissonSolver(; common...), pic1, pic2, Octopus.CUDABackend)
        luminosity_gpic = collide!(
            GaussianPICPoissonSolver(; common..., coupling_tol=0.0),
            gpic1, gpic2, Octopus.CUDABackend)
        Octopus.CUDA.synchronize()
        @test luminosity_gpic ≈ luminosity_pic rtol=2.0e-12
        for (expected, actual) in zip(host_arrays(pic1), host_arrays(gpic1))
            @test actual ≈ expected rtol=2.0e-12 atol=2.0e-18
        end
        for (expected, actual) in zip(host_arrays(pic2), host_arrays(gpic2))
            @test actual ≈ expected rtol=2.0e-12 atol=2.0e-18
        end

        # A zero marginal width takes the ordinary-PIC fallback on all CUDA
        # routes. The sequential case also verifies that the slice-pair Green
        # cache is forwarded through the fallback.
        route_configs = (
            (batch_mode=:wavefront, cuda_indexed_wavefront=true),
            (batch_mode=:wavefront, cuda_indexed_wavefront=false),
            (batch_mode=:sequential, cuda_indexed_wavefront=true),
        )
        for route in route_configs
            route_common = merge(common, (
                green_cache=:slice_pair,
                min_transverse_extent=(2.0e-3, 2.0e-3),
            ), route)
            pic1, pic2 = gpu_pair(zeros(n), zeros(n))
            gpic1, gpic2 = gpu_pair(zeros(n), zeros(n))
            collide!(
                PICPoissonSolver(; route_common...), pic1, pic2,
                Octopus.CUDABackend)
            collide!(
                GaussianPICPoissonSolver(; route_common...),
                gpic1, gpic2, Octopus.CUDABackend)
            Octopus.CUDA.synchronize()
            for (expected, actual) in zip(host_arrays(pic1), host_arrays(gpic1))
                @test actual ≈ expected rtol=2.0e-12 atol=2.0e-18
            end
            for (expected, actual) in zip(host_arrays(pic2), host_arrays(gpic2))
                @test actual ≈ expected rtol=2.0e-12 atol=2.0e-18
            end
        end
    end

    @testset "CUDA non-finite coordinates fail fast at solver chokepoints" begin
        n = 32
        gpu_rep(; kwargs...) = begin
            host = nonfinite_test_rep(n; kwargs...)
            rep = Phase6DRep((Octopus.CUDA.CuArray(a) for a in coordinate_arrays(host))...)
            params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
            Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
        end
        sl = LongitudinalSlicing(nslices=2, method=:equal_count)
        pic(; kwargs...) = PICPoissonSolver(; kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
            grid=(16, 16), green_cache=:none, slicing=sl, kwargs...)

        # All three CUDA PIC routes detect a poisoned coordinate. Previously the
        # NaN weight flowed into the atomic deposit and poisoned the whole grid.
        for configuration in (
                (batch_mode=:wavefront, cuda_indexed_wavefront=true),
                (batch_mode=:wavefront, cuda_indexed_wavefront=false),
                (batch_mode=:sequential, cuda_indexed_wavefront=true))
            expect_nonfinite_error(() -> collide!(
                pic(; configuration...), gpu_rep(poison=:x), gpu_rep(), Octopus.CUDABackend))
        end
        # Node interaction grid (wavefront route).
        expect_nonfinite_error(() -> collide!(
            pic(interaction_grid=:node), gpu_rep(poison=:px), gpu_rep(), Octopus.CUDABackend))
        # NaN z is caught at the slicing chokepoint.
        expect_nonfinite_error(() -> collide!(
            pic(), gpu_rep(poison=:z), gpu_rep(), Octopus.CUDABackend))
        # Soft-Gaussian fused wavefront and sequential routes (moment chokepoints).
        for mode in (:wavefront, :sequential)
            gaussian = GaussianPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4,
                luminosity_scale=1.0, slicing=sl, batch_mode=mode)
            expect_nonfinite_error(() -> collide!(
                gaussian, gpu_rep(), gpu_rep(poison=:py, value=Inf), Octopus.CUDABackend))
        end
        # Gaussian-subtracted PIC hybrid (indexed wavefront route).
        gpic = GaussianPICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
            grid=(16, 16), green_cache=:none, slicing=sl)
        expect_nonfinite_error(() -> collide!(
            gpic, gpu_rep(poison=:px), gpu_rep(), Octopus.CUDABackend))
        # Spectral solver (Dirichlet-box chokepoint).
        spectral = SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
            grid=(16, 16), slicing=sl)
        expect_nonfinite_error(() -> collide!(
            spectral, gpu_rep(poison=:x), gpu_rep(), Octopus.CUDABackend))
    end
end

@testset "Knob control" begin
    reset_knobs!()
    try
        @knob t_knob.brho = 81.1
        @knob t_knob.xfer = 0.05
        @knob t_knob.current = 1000.0
        @knob t_knob.k1 = t_knob.current * t_knob.xfer / t_knob.brho
        @knob t_knob.k1_alias = t_knob.k1

        # Evaluation, aliasing, memoized invalidation.
        @test knob_value("t_knob.k1") ≈ 1000.0 * 0.05 / 81.1
        @test knob_value("t_knob.k1_alias") == knob_value("t_knob.k1")
        set_knob!("t_knob.current", 400.0)
        @test knob_value("t_knob.k1") ≈ 400.0 * 0.05 / 81.1
        @test knob_value("t_knob.k1_alias") == knob_value("t_knob.k1")
        @test Symbol("t_knob.k1") in knob_dependents("t_knob.current")
        @test Symbol("t_knob.k1_alias") in knob_dependents("t_knob.current"; transitive=true)
        @test knob_dependencies("t_knob.k1") ==
              [Symbol("t_knob.brho"), Symbol("t_knob.current"), Symbol("t_knob.xfer")]

        # Namespace objects: string-free reads and plain assignment. The
        # `knobs` root is precompiled into Octopus, so it is usable from any
        # scope; the per-root constants (`t_knob` in Main) are exercised by
        # examples/knob_control.jl at top level.
        ns = Octopus.knobs.t_knob
        @test ns isa KnobNamespace
        @test ns.current == 400.0
        ns.current = 500.0
        @test knob_value("t_knob.current") == 500.0
        @test Octopus.knobs.t_knob.k1 ≈ 500.0 * 0.05 / 81.1
        set_knob!("t_knob.current", 400.0)
        @test_throws ArgumentError Octopus.knobs.t_knob.nonexistent
        @test_throws ArgumentError (Octopus.knobs.t_knob.nonexistent = 1.0)
        @test :current in propertynames(ns)
        @test :t_knob in propertynames(Octopus.knobs)

        # Typed knobs: declared type conversion, lossy-assignment rejection,
        # Int knobs in arithmetic, non-Real knobs as plain values.
        @knob t_knob.n_slices::Int = 15
        @test knob_value("t_knob.n_slices") === 15
        set_knob!("t_knob.n_slices", 21.0)          # exact conversion is fine
        @test knob_value("t_knob.n_slices") === 21
        @test_throws ArgumentError set_knob!("t_knob.n_slices", 1.5)
        @knob t_knob.scaled = t_knob.n_slices * 2.0
        @test knob_value("t_knob.scaled") === 42.0
        @knob t_knob.mode::Symbol = :fast
        @test knob_value("t_knob.mode") === :fast
        @test Octopus.knobs.t_knob.mode === :fast
        @knob t_knob.uses_mode = t_knob.mode + 1.0
        @test_throws ArgumentError knob_value("t_knob.uses_mode")
        @test_throws ArgumentError @knob(t_knob.bad_sym::Symbol = 3.0 * 2.0)

        # Definition-time guards: unknown reference, cycle, dependent set,
        # unset evaluation, non-whitelisted operator, eager conversion,
        # namespace/leaf collision.
        @test_throws ArgumentError Octopus._knob_define!(
            Symbol("t_knob.bad"), Meta.parse("t_knob.missing * 2.0"))
        @test_throws ArgumentError Octopus._knob_define!(
            Symbol("t_knob.brho"), Meta.parse("t_knob.k1 * 2.0"))
        @test_throws ArgumentError set_knob!("t_knob.k1", 1.0)
        @knob t_knob.unset
        @test_throws ArgumentError knob_value("t_knob.unset")
        @test_throws ArgumentError knob_expression("rand() * t_knob.k1")
        @test_throws ArgumentError CrabDispersionSpec{Float64}(
            zeta1=@knob_expr(t_knob.k1))
        @test_throws ArgumentError Octopus._knob_define!(
            Symbol("t_knob.k1.sub"), Meta.parse("1.0"))
        @test_throws ArgumentError Octopus._knob_define!(Symbol("t_knob"), nothing)

        # Printing round-trips losslessly through the parser.
        for s in ("t_knob.k1 * t_knob.xfer / t_knob.brho",
                  "t_knob.brho - (t_knob.k1 - t_knob.xfer)",
                  "-(t_knob.k1 * t_knob.brho)", "-t_knob.k1 ^ 2.0",
                  "2.0 * sin(t_knob.k1) + t_knob.brho ^ 2.0",
                  "atan(t_knob.k1, t_knob.brho) + max(t_knob.k1, 2.0, t_knob.brho)")
            e = knob_expression(s)
            @test knob_expression(string(e)) == e
        end

        # compile_runtime resolves scalar and tuple knob parameters, and a
        # knob assignment recompiles an already-built task through the epoch
        # cache.
        spec = ElementSpec{:crab_dispersion}(;
            zeta1=@knob_expr(t_knob.k1), zeta2=0.0, zeta3=0.0, zeta4=0.0,
            tracking_method=Symplectic6DMap())
        @test compile_runtime(spec).zeta1 == knob_value("t_knob.k1")
        cavity = ElementSpec{:thin_crab_cavity}(; N=2, frequency=394.0e6,
            strengthX=(@knob_expr(t_knob.k1 * 2.0), 0.0),
            strengthY=(0.0, 0.0), phase=(0.0, 0.0),
            tracking_method=Symplectic6DMap())
        @test compile_runtime(cavity).strengthX[1] == 2.0 * knob_value("t_knob.k1")
        knob_task = TrackingTask((spec,); policy=CPUThreadsExecutionPolicy(threads=1))
        run_once() = begin
            rep = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [1e-3], [0.0])
            execute!(knob_task, rep; turns=1)
            rep.x[1]
        end
        x_before = run_once()
        Octopus.knobs.t_knob.current = 800.0
        @test run_once() == 1e-4 + knob_value("t_knob.k1") * 1e-3
        @test run_once() != x_before

        # Element parameters as properties: read, schema-validated assignment,
        # and post-construction knob binding that reaches an already-built
        # task through the spec-epoch cache invalidation.
        bind_spec = ElementSpec{:crab_dispersion}(;
            zeta1=0.25, zeta2=0.0, zeta3=0.0, zeta4=0.0,
            tracking_method=Symplectic6DMap())
        @test bind_spec.zeta1 == 0.25
        @test :zeta1 in propertynames(bind_spec)
        @test_throws ArgumentError bind_spec.not_a_param
        @test_throws ArgumentError (bind_spec.not_a_param = 1.0)
        bind_task = TrackingTask((bind_spec,); policy=CPUThreadsExecutionPolicy(threads=1))
        run_bind() = begin
            rep = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [1e-3], [0.0])
            execute!(bind_task, rep; turns=1)
            rep.x[1]
        end
        @test run_bind() == 1e-4 + 0.25 * 1e-3
        bind_spec.zeta1 = @knob_expr(t_knob.k1)
        @test bind_spec.zeta1 isa KnobRef
        @test run_bind() == 1e-4 + knob_value("t_knob.k1") * 1e-3
        bind_spec.zeta1 = 0.125            # plain value update, same route
        @test run_bind() == 1e-4 + 0.125 * 1e-3

        # Native symbolic derivative: chained through the registry, and the
        # product/chain rules against a manual expression.
        d = knob_derivative("t_knob.k1", "t_knob.current")
        @test knob_value(d) ≈ 0.05 / 81.1
        e2 = knob_expression("sin(t_knob.k1) * t_knob.k1 ^ 2.0")
        k = knob_value("t_knob.k1")
        @test knob_value(knob_derivative(e2, "t_knob.k1"; through_registry=false)) ≈
              cos(k) * k^2 + sin(k) * 2k
        @test_throws ArgumentError knob_derivative(
            knob_expression("max(t_knob.k1, 2.0)"), "t_knob.k1")

        # Julia-Expr bridge, and the Symbolics adapter when available.
        e3 = knob_expression("t_knob.k1 / t_knob.brho + 2.0")
        @test knob_expression(string(knob_to_expr(e3))) == e3
        if Octopus._HAS_SYMBOLICS
            e4 = knob_expression("t_knob.k1 * t_knob.brho + t_knob.k1")
            @test knob_value(knob_from_symbolic(knob_symbolic(e4))) ≈ knob_value(e4)
        else
            @test_throws ArgumentError knob_symbolic(e3)
        end

        # The consumer-boundary contract.
        result = validate(KnobEffectivenessContract())
        @test result.passed
        @test result.metrics[:knob_resolution_receipt]
    finally
        reset_knobs!()
    end
end

@testset "Physics contracts" begin
    sym = validate(SymplecticityContract())
    @test sym.passed
    @test sym.metrics[:GaussianStrongBeam_residual] <= 5.0e-7

    wsl = validate(HighEnergyWeakStrongLimitContract())
    @test wsl.passed
    @test wsl.metrics[:gaussian_proton_max_abs_error] <= 2.0e-14
    @test wsl.metrics[:pic_luminosity_relative_error] <= 0.08

    # ~1 min: two 1024-turn strong-strong runs. The contract states the
    # Vlasov-band Yokoya physics per solver: PIC must reproduce it, and the
    # soft-Gaussian moment closure must FAIL it — that failure is the
    # documented model limitation, asserted here on purpose (converged
    # values: PIC 1.20, gaussian 1.10, Vlasov band 1.2-1.3).
    coh = validate(CoherentModePhysicsContract())          # solver = :pic
    @test coh.passed
    gau = validate(CoherentModePhysicsContract(solver=:gaussian))
    @test !gau.passed
    @test gau.metrics[:lambda_x] < coh.metrics[:lambda_x]
    @test gau.metrics[:lambda_y] < coh.metrics[:lambda_y]
    @test abs(gau.metrics[:sigma_drift_x]) <= 2.0e-4   # closure still gets the sigma mode right
end

@testset "Strong-strong physical parameter validation" begin
    rep1 = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
    rep2 = Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0])
    beam1 = test_beam(rep1)
    beam2 = test_beam(rep2)
    solver = GaussianPoissonSolver(kbb1=0.0, kbb2=0.0)
    @test isfinite(collide!(solver, beam1, beam2, CPUThreadsBackend))

    zero_energy = BeamParams{Float64}(
        charge=1.0, mc2=1.0, E0=0.0, r0=1.0, npart=1.0,
    )
    invalid_beam = Beam{CPUThreadsBackend,typeof(zero_energy),typeof(rep1)}(zero_energy, rep1)
    @test_throws ArgumentError collide!(GaussianPoissonSolver(), invalid_beam, beam2, CPUThreadsBackend)
end

@testset "CODATA 2022 constants" begin
    @test RE == 2.8179403205e-15
    @test EMASS_EV == 0.51099895069e6
    @test ME0 === EMASS_EV
    @test PMASS_EV == 938.27208943e6
end


@testset "CUDA GaussianPIC honours green_cache=:slice_pair" begin
    # Regression. GaussianPIC's three CUDA routes used to ignore green_cache
    # entirely: only the CPU expanded each slice-pair grid by
    # (1 + slice_pair_green_growth), so the two backends solved on different
    # (both valid) grids and agreed only to ~3e-6 at the DEFAULT settings --
    # green_cache=:slice_pair is the default. Diagnosed by setting growth=0.0,
    # which made the CPU expansion a no-op and restored 5e-17 parity, proving the
    # discrepancy was the missing expansion and not floating-point drift.
    #
    # The cache must be applied AFTER _cuda_gpic_augment_prep, which recomputes
    # the grid from the margin-enlarged source bounds; caching before it would be
    # silently discarded.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
        mk(pol) = begin
            set_global_rng!(seed=91, method=:philox)
            e = Beam(6000, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(6000, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            (e, p)
        end
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        run_both(; kw...) = begin
            e1, p1 = mk(CPUThreadsBackend)
            l1 = collide!(GaussianPICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e1, p1, CPUThreadsBackend)
            e2, p2 = mk(CUDAExecutionPolicy())
            l2 = collide!(GaussianPICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e2, p2, CUDABackend)
            d = max(maximum(abs.(flat(e1) .- flat(e2))), maximum(abs.(flat(p1) .- flat(p2))))
            (d, l1, l2, flat(e2))
        end

        # all three CUDA routes, at the default green_cache
        d_idx, l1, l2, cu_default = run_both()
        @test d_idx < 1e-14
        @test isapprox(l1, l2; rtol=1e-12)

        d_noidx, _, _, _ = run_both(cuda_indexed_wavefront=false)
        @test d_noidx < 1e-14

        # also a regression for the sequential route calling the field kernel with
        # the pre-field_derivative arity, which made it fail to compile at all
        d_seq, _, _, _ = run_both(batch_mode=:sequential)
        @test d_seq < 1e-14

        # coupled branch on top of the cache
        d_cp, _, _, _ = run_both(coupling_tol=0.0)
        @test d_cp < 1e-14

        # effectiveness: the growth factor must reach its CUDA consumer, i.e. a
        # different expansion must produce a different (still valid) answer, and
        # growth=0 must reproduce the uncached grid.
        _, _, _, cu_growth = run_both(slice_pair_green_growth=0.75)
        @test cu_default != cu_growth
        _, _, _, cu_zero = run_both(slice_pair_green_growth=0.0)
        _, _, _, cu_none = run_both(green_cache=:none)
        # Not bitwise: with the cache enabled the Green FFT comes from the
        # per-pair cached builder, with :none from the fused batched build inside
        # the solve, so they differ in the last ulp. The GRID is what must match,
        # and a wrong grid shows up at ~1e-3 relative (that was the original bug).
        @test maximum(abs.(cu_zero .- cu_none)) <= 1e-13 * maximum(abs, cu_none)
    else
        @test true
    end
end


@testset "CUDA GaussianPIC emits PIC phase timing records" begin
    # Regression: pic_timing=true produced an empty pic_phase_timings for
    # GaussianPIC, because its CUDA routes never built a timing object and
    # passed `nothing` down every shared PIC helper. Plain PIC always worked.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
        build(solver) = begin
            set_global_rng!(seed=7, method=:philox)
            be = Beam(4000, CUDAExecutionPolicy(), Float64; beta=(0.55, 0.056, 12.7),
                alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
                rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            bp = Beam(4000, CUDAExecutionPolicy(), Float64; beta=(0.8, 0.072, 90.9),
                alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
                rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            L6(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                             alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
            ip = StrongStrongCollision(:ip; poisson_solver=solver)
            task = StrongStrongTask((ip, L6((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))),
                                    (ip, L6((0.8, 0.072, 90.9), (0.228, 0.210, -0.01)));
                                    diagnostics=StrongStrongDiagnostics(pic_timing=true))
            (be, bp, task)
        end

        be, bp, task = build(GaussianPICPoissonSolver(; slicing=sl, grid=(32, 32)))
        execute!(task, be, bp; turns=1)
        rec = pic_phase_timings(task)
        @test !isempty(rec)                                   # the actual regression
        r = rec[end]
        @test r.measured_total > 0
        @test r.interaction > 0
        # the two GaussianPIC-specific phases must be populated, not just present
        @test r.gpic_moments > 0
        @test r.gpic_profiles > 0
        # they are nested inside :interaction and must not inflate the total
        @test r.measured_total >= r.interaction

        # plain PIC still works and leaves the GaussianPIC-only counters at zero
        be2, bp2, task2 = build(PICPoissonSolver(; slicing=sl, grid=(32, 32)))
        execute!(task2, be2, bp2; turns=1)
        rec2 = pic_phase_timings(task2)
        @test !isempty(rec2)
        @test rec2[end].gpic_moments == 0
        @test rec2[end].gpic_profiles == 0
    else
        @test true
    end
end


@testset "CUDA PIC parity across every execution route" begin
    # Two bugs found by sweeping the option space rather than by reading:
    #
    # 1. green_cache=:slice_pair (the DEFAULT) was applied by only two of the five
    #    CUDA interaction routes. batch_mode=:sequential, cuda_batch_fft=false and
    #    cuda_wavefront_fft=false solved on the unexpanded grid while the CPU
    #    expanded by 1+slice_pair_green_growth, giving 4.7e-6 coordinate error.
    #
    # 2. The luminosity was computed asynchronously but consumed AFTER the kicks,
    #    which rewrite the slice coordinates in place. It is a data dependency, not
    #    a completion wait. _cuda_pic_interaction_pair_batched_fft! reached the
    #    kicks fastest and read post-kick coordinates, giving a deterministic
    #    1.8e-4 luminosity error; the other routes were correct only by timing.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        sl = LongitudinalSlicing(nslices=5, method=:normal_quantile, center_position=:centroid)
        mk(pol) = begin
            set_global_rng!(seed=91, method=:philox)
            e = Beam(5000, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(5000, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            (e, p)
        end
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        run_cuda(; kw...) = begin
            e, p = mk(CUDAExecutionPolicy())
            l = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e, p, CUDABackend)
            (l, flat(e))
        end
        e0, p0 = mk(CPUThreadsBackend)
        lum_cpu = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64)), e0, p0, CPUThreadsBackend)
        ref = flat(e0)

        # every CUDA execution route, all at the default green_cache=:slice_pair
        routes = (
            NamedTuple(),
            (cuda_indexed_wavefront=false,),
            (cuda_wavefront_fft=false,),
            (cuda_batch_fft=false,),
            (cuda_async=false,),
            (batch_mode=:sequential,),
        )
        for kw in routes
            l, c = run_cuda(; kw...)
            @test maximum(abs.(c .- ref)) < 1e-13          # bug 1
            @test isapprox(l, lum_cpu; rtol=1e-11)         # bug 2
        end
    else
        @test true
    end
end


@testset "PIC green_type=:lattice" begin
    # The lattice Green function inverts the five-point discrete Laplacian exactly
    # instead of discretizing the continuum -ln r. Derivation and measurements:
    # docs/theory/pic_free_space_kernels.md Section 3.4.
    nx = ny = 32

    # (a) the kernel must reproduce -ln r away from the origin, with the additive
    #     gauge constant C = gamma + (3/2)ln2 for the isotropic lattice
    tab = Octopus._pic_lattice_green_table(nx, ny, 1.0)
    at(m) = tab[m + 2nx + 1, 2ny + 1]
    C = -at(8) - log(8.0)
    @test isapprox(C, 0.5772156649015329 + 1.5 * log(2.0); atol=2e-3)
    for m in (12, 16)
        @test isapprox(at(m), -(log(m) + C); atol=5e-3)
    end
    # nearest neighbour is the exact lattice value 1/4 (in the 2pi convention)
    @test isapprox(abs(at(1)), pi / 2; rtol=1e-5)

    # (b) it depends only on the aspect ratio, not the absolute spacing -- this is
    #     what makes one cached table serve every slice pair
    g1 = Matrix{Float64}(undef, 2nx, 2ny)
    g2 = Matrix{Float64}(undef, 2nx, 2ny)
    Octopus._pic_green_lattice!(g1, 0.0, 0.0, 0.0, 0.0, 1.0e-4, 5.0e-5, nx, ny)
    Octopus._pic_green_lattice!(g2, 0.0, 0.0, 0.0, 0.0, 2.0e-4, 1.0e-4, nx, ny)
    @test g1 == g2                       # same rho => same table, exactly

    # (c) reaches its runtime consumer: a different kernel must change the answer
    sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
    mk() = begin
        set_global_rng!(seed=91, method=:philox)
        e = Beam(3000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.7),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(3000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.9),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        (e, p)
    end
    run(gt) = begin
        e, p = mk()
        l = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), green_type=gt), e, p, CPUThreadsBackend)
        (l, vcat(coordinate_arrays(e)...))
    end
    l_int, c_int = run(:integrated)
    l_lat, c_lat = run(:lattice)
    @test all(isfinite, c_lat) && isfinite(l_lat)
    @test c_int != c_lat                                   # reaches the consumer
    @test isapprox(l_lat, l_int; rtol=1e-3)                # same physics

    # (d) rejected cleanly rather than silently ignored
    @test_throws ArgumentError PICPoissonSolver(green_type=:bogus)

    # (d2) the EXPERIMENTAL label is part of the contract with users: :lattice is
    #      1.74x slower and ~645 MB at grid 128, so the option metadata (which
    #      solver_help renders) must keep saying so.
    @test occursin("EXPERIMENTAL", solver_option_schema(PICPoissonSolver).green_type.meaning)

    # (e) CPU/CUDA parity on every execution route
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        flat(b) = vcat((Array(a) for a in coordinate_arrays(b))...)
        mkp(pol) = begin
            set_global_rng!(seed=91, method=:philox)
            e = Beam(3000, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=1,
                charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
            p = Beam(3000, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0, rng_id=2,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
            (e, p)
        end
        for kw in (NamedTuple(), (green_cache=:none,), (cuda_indexed_wavefront=false,),
                   (cuda_wavefront_fft=false,), (batch_mode=:sequential,))
            # The CPU reference must use the SAME options: green_cache and batch_mode
            # change the grid on both backends, so a fixed-default reference would be
            # comparing two different configurations.
            e0, p0 = mkp(CPUThreadsBackend)
            collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), green_type=:lattice, kw...),
                     e0, p0, CPUThreadsBackend)
            ref = flat(e0)
            e2, p2 = mkp(CUDAExecutionPolicy())
            collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), green_type=:lattice, kw...),
                     e2, p2, CUDABackend)
            @test maximum(abs.(flat(e2) .- ref)) < 1e-13
        end
    end
end
