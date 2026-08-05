using Test
using Octopus
using LinearAlgebra
# Test-only: Octopus takes no runtime dependency on any AD package.
using ForwardDiff
# Test-only: loading Symbolics activates the OctopusSymbolicsExt weak-dep
# extension, so the suite exercises the adapter the way a user reaches it.
# Before the extension existed the adapter was dead in package mode and the
# round-trip test silently took its unavailable branch forever (part 6, R3).
using Symbolics

# Whether the CUDA half of this suite ran at all must be visible in the summary,
# not inferable only by noticing that some testsets printed fewer assertions.
#
# More than twenty testsets are gated behind `_HAS_CUDA && CUDA.functional()`
# (the 2026-08-05 audit counted 24+ in the back half alone and replaced the
# three `else @test true` green-lies with honest skips; gated sets without an
# else still vanish silently — prefer `else @test_skip` in new ones). CI
# (`.github/workflows/ci.yml`) runs on
# `ubuntu-latest` with no GPU, so on CI **every** CUDA test is skipped while the
# run still reports "Testing Octopus tests passed".
#
# That matters more than it looks. The correctness argument for `pic_cuda.jl`
# rests almost entirely on CPU/CUDA parity: the CPU side is independently
# verified (hand-derived kernels, analytic references), the CUDA plane layout has
# no CPU counterpart to be verified against, and the measured parity residual is
# ~1e-15 against a ~1e-5 signal for any plane-level error. Take the parity tests
# away and that argument evaporates -- silently. `AGENTS.md` states the rule for
# contracts ("do not report an unrun check as passed"); this is the same rule for
# the suite.
#
# Ordering caveat (2026-08-05 audit, U17-7): this file aborts at the first
# failing testset, and the tightest physics backstops -- the symplecticity
# validation, the 8% high-energy weak-strong limit, the Yokoya coherent-mode
# contract with its executed negative control -- run at the very END, after
# the whole CUDA block. An abort anywhere earlier silently drops the only
# tests with real discriminating power on absolute beam-beam physics, so a
# red run's summary says nothing about them: fix the first failure and rerun
# before drawing any physics conclusion from what did pass.
const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()

@testset "CUDA coverage status" begin
    if CUDA_TESTS_ACTIVE
        @test Octopus.CUDA.functional()
    else
        @info """
        NO CUDA DEVICE: the GPU half of this suite did NOT run.
        Nine CUDA-gated testsets were skipped, including every CPU/CUDA parity
        check. A green run here says nothing about pic_cuda.jl, gaussian_pic_cuda.jl
        or spectral_cuda.jl. Run on a GPU host before trusting a CUDA change."""
        @test_skip "CUDA device not available -- GPU half of the suite skipped"
    end
end

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

@testset "Virtual drifts: the named three are symplectic, the unsafe two are not" begin
    # ThinStrongBeamSpec claims all three named drifts are exact flows of their
    # own Hamiltonian and therefore symplectic. Only :hirata was checked.
    #
    # The step scan is what makes this a proof rather than a threshold: a
    # symplectic map's finite-difference residual is truncation error and falls
    # as step^2, while a structurally non-symplectic map's residual is flat.
    # The two UnsafeVirtualDrift models are the negative control -- without
    # them a passing tolerance says nothing about discriminating power.
    covariance = [
        1.21e-8   1.0e-9   2.4e-9  -3.0e-10
        1.0e-9    4.0e-8   2.0e-10  1.5e-9
        2.4e-9    2.0e-10  6.4e-9  -6.0e-10
       -3.0e-10   1.5e-9  -6.0e-10  2.25e-8
    ]
    q0 = [4.0e-4, 1.0e-4, -2.0e-4, -1.5e-4, 1.2e-3, 2.0e-4]
    form = zeros(6, 6)
    for coordinate in (1, 3, 5)
        form[coordinate, coordinate + 1] = 1
        form[coordinate + 1, coordinate] = -1
    end
    drift_residual(drift, step) = begin
        element = ThinStrongBeam(ThinStrongBeamSpec{Float64}(;
            kbb=1.0e-8, covariance=covariance, center=(2.0e-5, -1.0e-5, 3.0e-4),
            angle=(3.0e-4, -2.0e-4, 0.0), virtual_drift=drift))
        jacobian = hcat([(
            collect(element((q0 .+ (collect(1:6) .== column) .* step)...)) -
            collect(element((q0 .- (collect(1:6) .== column) .* step)...))
        ) / (2step) for column in 1:6]...)
        norm(transpose(jacobian) * form * jacobian - form, Inf)
    end

    for drift in (:hirata, :chromatic, :exact)
        fine = drift_residual(drift, 3.0e-7)
        coarse = drift_residual(drift, 3.0e-6)
        @test fine < 5.0e-7
        # step^2: a decade coarser must cost about two decades of residual.
        @test 50 < coarse / fine < 200
    end

    for drift in (UnsafeVirtualDrift(:chromatic_frozen_energy),
                  UnsafeVirtualDrift(:paraxial_frozen_longitudinal))
        fine = drift_residual(drift, 3.0e-7)
        coarse = drift_residual(drift, 3.0e-6)
        @test fine > 1.0e-5
        # Flat under refinement: the violation is structural, not truncation.
        @test isapprox(coarse, fine; rtol=0.05)
    end
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
                                              bend_fringe=true, nst=2)),
            # A curved frame makes the straight multipole kick a non-gradient
            # unless the content is a PURE NORMAL dipole: by Cauchy-Riemann,
            # d(dpx)/dy - d(dpy)/dx = -L h Im f. The skew dipole is the case
            # that looks exempt and is not -- its curved potential does not
            # terminate, Psi_1 = Ks0 (1+hx) seeding Psi_3 = h^2 Ks0/(1+hx) --
            # and tracking it straight cost L h Ks0, measured 2.5e-3.
            ("bend with skew dipole", SBendSpec(L=1.1, h=0.18, b0=0.18, ks=(0.05,), nst=2)),
            ("bend with skew quadrupole", SBendSpec(L=1.1, h=0.18, b0=0.18, k1s=0.4, nst=2)),
            ("bend with normal dipole error", SBendSpec(L=1.1, h=0.18, b0=0.18, kn=(0.05,), nst=2)))
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

    # Audit part 7, K1: RBendSpec is exported, user-facing and PTC-validated,
    # and constructs an ElementSpec{:sbend} -- so type-level queries must
    # resolve to the sbend metadata rather than silently missing the registry
    # and reporting a confident empty answer about a validated element. Before
    # the friendly-alias registration, required_contracts(RBendSpec) was [] and
    # element_help(RBendSpec) printed an invented kind :RBendSpec.
    @test required_contracts(RBendSpec) == required_contracts(SBendSpec)
    @test PTCConsistencyContract in required_contracts(RBendSpec)
    @test supported_tracking_methods(RBendSpec) == supported_tracking_methods(SBendSpec)
    @test !isempty(keys(parameter_schema(RBendSpec)))
    let help = sprint(io -> element_help(io, RBendSpec))
        @test occursin("Element kind: :sbend", help)
        @test !occursin(":RBendSpec", help)
        @test occursin("PTCConsistencyContract", help)
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
    # The wrapped element is reachable for inspection and IS the runtime the
    # aligned compile produces (`x || true` here used to be a tautology).
    let wrapped = compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, x_offset=1e-3))
        @test wrapped.inner isa LatticeMagnet
        @test typeof(wrapped.inner) ===
              typeof(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7)))
    end
end

@testset "The bend map is cancellation-free as b0 goes to zero" begin
    lb(h, b0, L, v) = collect(Octopus._lattice_bend(h, b0, L, v...))
    ld(h, L, v) = collect(Octopus._lattice_drift(h, L, v...))
    u = (1.3e-3, 3.0e-4, -0.9e-3, -2.2e-4, 0.0, 1.1e-3)
    big = (7.0e-3, 2.0e-3, -5.0e-3, -1.5e-3, 1.0e-3, -2.0e-3)

    # The defect this replaced: `_lattice_bend` formed 1/b0, so the map's error
    # grew as ~1.5e-16/b0 and passed 1e-12 once b0 fell below ~1.5e-4. Only
    # b0 EXACTLY zero was safe, because it took the drift branch instead. The
    # difference from the drift limit must now fall linearly in b0 with no
    # floor -- at b0 = 1e-15 the old map was off by 0.16.
    #
    # The tolerance widens as b0 shrinks, and that is the floating-point floor
    # rather than slack: the quantity being resolved is a b0-sized change in
    # momenta of order one, so at b0 = 1e-15 it is about ten ulp and agreeing to
    # 1% is as well as double precision can do. The defect this catches is not
    # subtle at that scale -- the old map was wrong by a factor of 1.5e14 there.
    let h = 0.18, L = 1.1, ref = ld(h, L, u)
        slope = maximum(abs, lb(h, 1.0e-3, L, u) .- ref) / 1.0e-3
        for (b0, rtol) in ((1.0e-5, 1.0e-8), (1.0e-7, 1.0e-8), (1.0e-9, 1.0e-7),
                           (1.0e-11, 1.0e-5), (1.0e-13, 1.0e-3), (1.0e-15, 0.05))
            @test maximum(abs, lb(h, b0, L, u) .- ref) ≈ slope * b0 rtol = rtol
        end
    end

    # The two paths now meet at the seam. `_body_step` still sends b0 = 0 to the
    # drift -- it is the fast path for every quadrupole, sextupole, octupole,
    # multipole and drift -- but that is now a speed choice rather than the only
    # defined option, and the bend agrees there instead of dividing by zero.
    for (h, L) in ((0.18, 1.1), (0.0, 0.8), (0.5, 1.0), (-0.4, 1.3))
        for v in (u, big)
            @test maximum(abs, lb(h, 0.0, L, v) .- ld(h, L, v)) < 1.0e-15
        end
    end

    # Beyond a quarter turn in one step the b0 -> 0 state runs backwards through
    # the rotated frame, so the rewrite hands back to the direct form. Those
    # bends must still track, and stay symplectic.
    let S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
        for (h, b0, L) in ((0.18, 0.18, 1.1), (0.18, 1.0e-6, 1.1), (0.0, 0.35, 0.8),
                           (2.5, 2.5, 1.0), (-2.5, -2.5, 1.0), (0.5, 0.1, 2.0))
            J = zeros(6, 6)
            for j in 1:6
                v = ComplexF64[u...]
                v[j] += 1e-30im
                J[:, j] = imag.(collect(Octopus._lattice_bend(h, b0, L, v...))) ./ 1e-30
            end
            @test maximum(abs, J' * S6 * J - S6) < 1.0e-13
        end
    end

    # atan(u)/u is 1 at the origin and continuous across the series crossover.
    @test Octopus._atan_over(0.0) == 1.0
    @test Octopus._atan_over(1.0e-5) ≈ 1.0 - 1.0e-10 / 3 rtol = 1.0e-12
    @test Octopus._atan_over(1.0e-4 + eps()) ≈ Octopus._atan_over(1.0e-4 - eps()) rtol = 1.0e-14
    @test Octopus._atan_over(0.7) ≈ atan(0.7) / 0.7
end

@testset "Series helpers hold full precision across their crossovers" begin
    # 2026-08-05 audit, U10-5/U10-6/U10-7. The removable-singularity helpers
    # guard |u| < crossover with a series, but the defects sat just OUTSIDE the
    # old windows (closed-branch cancellation) or in a truncated series.
    relerr(v, ref) = Float64(abs((big(v) - ref) / ref))

    # U10-5: (1 - cos u)/h cancels as ~eps/u^2, so at the old 1e-4 boundary the
    # closed branch was 5.86e-9 relative while the series held 5.2e-17 — an
    # 8-digit cliff one ulp wide. The crossover now sits at 0.125 with the
    # series extended through u^8; both sides must hold <= 1e-14.
    vers_ref(h) = (1 - cos(big(h))) / big(h)
    @test relerr(Octopus._curv_vers(1.001e-4, 1.0), vers_ref(1.001e-4)) < 1.0e-15
    @test relerr(Octopus._curv_vers(1.0e-2, 1.0), vers_ref(1.0e-2)) < 1.0e-15
    for h in (prevfloat(0.125), nextfloat(0.125), 0.13, 0.15)
        @test relerr(Octopus._curv_vers(h, 1.0), vers_ref(h)) < 1.0e-14
    end

    # U10-6: _sol_log_over_h truncated its series at O(u^2) for a 1e-4
    # crossover: 2.5e-13 value jump and 1.5e-8 d/dh error at the boundary. The
    # series now runs through u^7 and switches at 1e-2 (the AD derivative of
    # log1p(u)/h cancels as ~2eps/u, so the closed side only supports the
    # 1e-13 derivative target for u >~ 4e-3). Value AND first derivative must
    # be continuous to <= 1e-13 on both sides.
    log_ref(h) = log1p(big(h)) / big(h)
    dlog_ref(h) = (1 / (1 + big(h)) / big(h)) - log1p(big(h)) / big(h)^2
    g(h) = Octopus._sol_log_over_h(h, 1.0)
    for h in (1.001e-4, prevfloat(1.0e-2), nextfloat(1.0e-2), 2.0e-2)
        @test relerr(g(h), log_ref(h)) < 1.0e-15
        @test relerr(ForwardDiff.derivative(g, h), dlog_ref(h)) < 1.0e-13
    end
    @test abs(g(prevfloat(1e-2)) - g(nextfloat(1e-2))) / abs(g(1e-2)) < 1.0e-15

    # U10-7: _wedge formed Delta = (A + asin(px/w) - asin(pxn/w))/b1, an O(b1)
    # angle from O(A) terms — error grew as ~eps*A/b1 (measured 2.8e-10 on z at
    # b1 = 1e-8). Rationalised like `_lattice_bend`; vs BigFloat (the original
    # closed formulas) the error must sit at the representation floor for small
    # b1, and the b1 -> 0 limit must still reach _rot_xz linearly.
    let A = 0.1, x = 1e-3, px = 2e-3, y = -1.5e-3, py = 1.2e-3, z = 5e-4, pz = 1e-3
        function wedge_big(b1)
            Ab, b1b, xb, pxb, yb, pyb, zb, pzb = big.((A, b1, x, px, y, py, z, pz))
            ps = sqrt((1 + pzb)^2 - pxb^2 - pyb^2)
            pxn = pxb * cos(Ab) + (ps - b1b * xb) * sin(Ab)
            w = sqrt((1 + pzb)^2 - pyb^2)
            psn = sqrt((1 + pzb)^2 - pxn^2 - pyb^2)
            xn = xb * cos(Ab) + (xb * pxb * sin(2Ab) + sin(Ab)^2 * (2xb * ps - b1b * xb^2)) /
                                (psn + ps * cos(Ab) - pxb * sin(Ab))
            D = (Ab + asin(pxb / w) - asin(pxn / w)) / b1b
            return xn, pxn, yb + pyb * D, pyb, zb - D * (1 + pzb), pzb
        end
        for b1 in (1e-6, 1e-8, 1e-10)
            o = Octopus._wedge(A, b1, x, px, y, py, z, pz)
            @test maximum(abs.(big.(collect(o)) .- collect(wedge_big(b1)))) < 1.0e-16
        end
        r = collect(Octopus._rot_xz(A, x, px, y, py, z, pz))
        slope = maximum(abs.(collect(Octopus._wedge(A, 1e-3, x, px, y, py, z, pz)) .- r)) / 1e-3
        for b1 in (1e-5, 1e-7, 1e-9)
            @test maximum(abs.(collect(Octopus._wedge(A, b1, x, px, y, py, z, pz)) .- r)) ≈
                  slope * b1 rtol = 1.0e-3
        end
        # exactly reached, and still symplectic, at b1 == 0 and at moderate b1
        @test collect(Octopus._wedge(A, 0.0, x, px, y, py, z, pz)) == r
        S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
        for b1 in (0.3, 1e-8)
            J = zeros(6, 6)
            for j in 1:6
                v = ComplexF64[x, px, y, py, z, pz]
                v[j] += 1e-30im
                J[:, j] = imag.(collect(Octopus._wedge(A, b1, v...))) ./ 1e-30
            end
            @test maximum(abs, J' * S6 * J - S6) < 1.0e-13
        end
    end
end

@testset "ref_tilt rolls the design orbit" begin
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

    # Like a misalignment, a roll that is not asked for must leave the runtime
    # exactly what it was, so an ordinary bend keeps its type and its bits.
    @test compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4)) isa LatticeMagnet
    @test collect(compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4))(u...)) ==
          collect(compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=0.0))(u...))

    # The nesting is the physics and is visible in the type: the roll is the
    # OUTER wrapper, so a rolled misaligned bend is a RefTilted of a
    # MisalignedElement and never the other way round.
    @test compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=0.3)) isa
          RefTilted{<:LatticeMagnet}
    @test compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=0.3,
                                    x_offset=1e-3)) isa
          RefTilted{<:MisalignedElement}

    # An RBEND reaches the sector map by adding angle/2 to each pole face, and
    # forwards its keywords through that conversion, so it takes a roll too.
    @test compile_runtime(RBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=0.3)) isa
          RefTilted{<:LatticeMagnet}

    # A conjugation by a rotation inherits symplecticity from what it wraps.
    for s in (SBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=0.3),
              SBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=pi / 2),
              SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4, ref_tilt=0.3),
              RBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=pi / 2),
              RBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4, ref_tilt=0.3,
                        x_offset=1e-3, misalign_convention=:madx),
              SBendSpec(L=1.1, angle=0.198, k1=0.6, e1=0.1, e2=0.1, nst=4,
                        ref_tilt=0.3, x_offset=1e-3, tilt=0.02,
                        misalign_convention=:madx))
        J = jac(compile_runtime(s))
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-13
    end

    # On a STRAIGHT element the two meanings of "tilt" coincide exactly: with no
    # design orbit to roll, rolling the plane is rolling the body. Bit for bit,
    # because both go through the same pinned R_z -- this is the check that
    # would catch a sign or a transpose in the new rotation.
    for spec in ((L=0.3, k1=1.2, k2=8.0), (L=0.3, k1s=0.9,))
        a = compile_runtime(SBendSpec(; spec..., angle=0, nst=4, ref_tilt=0.37))
        b = compile_runtime(SBendSpec(; spec..., angle=0, nst=4, tilt=0.37))
        @test collect(a(u...)) == collect(b(u...))
    end

    # A rotationally symmetric element cannot notice the roll at all. This also
    # exercises the wrap on an element that does not declare ref_tilt: it is
    # applied wherever it is set, so it is never silently dropped.
    for s in (DriftSpec(L=0.7), SolenoidSpec(L=1.3, ks=0.35))
        rolled = compile_runtime(typeof(s)(; params(s)..., ref_tilt=0.41))
        @test maximum(abs, collect(rolled(u...)) .- collect(compile_runtime(s)(u...))) < 1.0e-15
    end

    # A vertical bend is a horizontal bend with ref_tilt = pi/2, which is the
    # case that was inexpressible before. Two ways of saying it: the dispersion
    # moves plane, and the map is the horizontal one with the axes exchanged.
    let off = (0.0, 0.0, 0.0, 0.0, 0.0, 3.0e-3),
        h = compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4)),
        v = compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, ref_tilt=pi / 2))

        @test abs(v(off...)[1]) < 1.0e-15
        @test v(off...)[3] ≈ h(off...)[1] atol = 1.0e-15
        @test abs(h(off...)[3]) < 1.0e-15

        x, px, y, py, z, pz = u
        X, PX, Y, PY, Z, PZ = h(y, py, -x, -px, z, pz)
        @test maximum(abs, collect(v(u...)) .- (-Y, -PY, X, PX, Z, PZ)) < 1.0e-15
    end

    # Which frame an alignment error is quoted in is a convention split, exactly
    # as the reference point and the composition order already were. With no
    # misalignment there is nothing to quote, so the two must agree; with one,
    # they must not -- and that difference is the whole reason the PTC
    # comparison needs a two-parameter case.
    let b = (ref_tilt=0.3, misalign_convention=:bmad),
        m = (ref_tilt=0.3, misalign_convention=:madx)

        @test collect(compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4; b...))(u...)) ==
              collect(compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4; m...))(u...))
        @test collect(compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, x_offset=1e-3; b...))(u...)) !=
              collect(compile_runtime(SBendSpec(L=1.1, angle=0.198, nst=4, x_offset=1e-3; m...))(u...))
    end

    # The roll reaches the map, and it is not a relabelling of the body roll:
    # on a BENT element ref_tilt and tilt are different magnets.
    let bare = compile_runtime(SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4)),
        roll = compile_runtime(SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4, ref_tilt=0.3)),
        body = compile_runtime(SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4, tilt=0.3))

        @test maximum(abs, collect(roll(u...)) .- collect(bare(u...))) > 1.0e-6
        @test maximum(abs, collect(roll(u...)) .- collect(body(u...))) > 1.0e-6
    end
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
    # Tightened from <= 3 (2026-08-05 audit): the three kinds this pin was
    # giving headroom to were BROKEN probe baselines (no keyword constructor
    # form), silently skipped; they now have keyword forms, the contract
    # reports broken kinds as failures, and the honest count is zero.
    @test r.metrics[:skipped_kinds] == 0
    @test r.metrics[:broken_kinds] == 0

    # The contract must be able to fail, or it is decoration. The original
    # control here asserted `status in (:passed, :failed)`, which cannot
    # fail (2026-08-05 audit, U16-2); the real control empties the
    # documented-inactive allowlist, so the drift's genuinely inert `nst`
    # must be REPORTED as a failure naming drift.nst.
    let bad = ElementParameterEffectivenessContract(
            inactive=empty(Octopus.DEFAULT_INACTIVE_ELEMENT_PARAMS))
        r = validate(bad)
        @test r.status === :failed
        @test occursin("drift.nst", r.message)
    end
    @test haskey(Octopus.DEFAULT_INACTIVE_ELEMENT_PARAMS, (:drift, :nst))
end

@testset "PTC coverage cannot narrow silently" begin
    r = validate(PTCConsistencyContract())
    @test r.status === :passed
    # Every declared spec must have been compared, not just the ones the
    # committed table happens to carry.
    @test r.metrics[:cases] == length(Octopus._ptc_reference_specs())

    # The guard must be able to fire, or it is decoration: drop one case's rows
    # from a copy of the table and the contract has to fail naming it rather
    # than pass on the remaining cases.
    source = Octopus._ptc_reference_path(PTCConsistencyContract())
    mktempdir() do dir
        truncated = joinpath(dir, "ptc_madx_truncated.tsv")
        open(truncated, "w") do io
            for line in eachline(source)
                startswith(line, "drift\t") && continue
                println(io, line)
            end
        end
        narrowed = validate(PTCConsistencyContract(path=truncated))
        @test narrowed.status === :failed
        @test occursin("drift", narrowed.message)
    end
end

@testset "Integrated Green kernel on the axes" begin
    # `_pic_atan_ratio` referenced a name this module never defines, so every
    # on-axis node of the DEFAULT :integrated Green kernel raised
    # UndefVarError. Reached only when a mesh puts a node exactly on an axis,
    # which is why it survived: found by running the solver-option contract
    # against a caller that had moved the global RNG.
    for (x, y) in ((0.0, 1.0), (1.0, 0.0), (0.0, 2.5), (-3.0, 0.0))
        # The half-pi is multiplied by the coordinate that is zero on that
        # branch, so the kernel is exactly zero there rather than merely finite.
        @test Octopus._pic_kernel_integral(x, y) == 0.0
    end
    @test Octopus._pic_atan_ratio(1.0, 0.0) ≈ pi / 2
    @test Octopus._pic_atan_ratio(-1.0, 0.0) ≈ -pi / 2
    @test Octopus._pic_atan_ratio(0.0, 0.0) == 0.0
    @test Octopus._pic_atan_ratio(1.0, 1.0) ≈ pi / 4
end

@testset "The luminosity tree reduction's power-of-two guard is enforced" begin
    # `_cuda_pic_luminosity_overlap_partials_kernel!` reduces with a tree that
    # ORPHANS elements unless the thread count is a power of two, so a bad count
    # silently corrupts luminosity -- a headline observable. Two validations guard
    # it: the `CUDAPICLaunchConfig` constructor (interface.jl, `ispow2(lum)`) and
    # `_resolve_cuda_pic_configuration`, which catches a non-power-of-two
    # INHERITED from the generic policy thread count.
    #
    # Neither was exercised by any test. Both could have been deleted and nothing
    # would have noticed -- the part 1 pattern, "a check that exists and is never
    # executed", guarding the one number a beam-beam code is judged on.
    #
    # Measured reachability before writing this: bare `collide!` falls back to 256;
    # power-of-two policy counts are inherited unchanged; 96/192/320/100/224 are
    # all rejected at resolution; an explicit power-of-two override rescues a
    # non-power-of-two policy. No non-power-of-two value reaches the kernel.

    # (a) constructor guard -- host-side, needs no device
    for bad in (96, 192, 320, 100, 224, 3)
        @test_throws ArgumentError CUDAPICLaunchConfig(luminosity_threads=bad)
    end
    for good in (32, 64, 128, 256, 512, 1024)
        @test CUDAPICLaunchConfig(luminosity_threads=good).luminosity_threads == good
    end
    # the guard is specific to luminosity: the other families use no tree reduction
    @test CUDAPICLaunchConfig(kick_threads=96).kick_threads == 96

    # (b) the inherited path, and the override that rescues it
    if CUDA_TESTS_ACTIVE
        set_global_rng!(seed=7, method=:philox)
        b = Beam(256, CUDAExecutionPolicy(), Float64; beta=(0.55, 0.056, 12.7),
                 alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-5, 1.0e-2), cutoff=5.0,
                 rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
                 r0=RE * ME0 / EMASS_EV, npart=1.0e11)
        resolved(t) = Octopus._resolve_execution_policy(
            CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=t)), b.rep)
        threads(pol, solver) = Octopus._with_solver_execution_configuration(solver, pol) do
            Octopus._cuda_pic_threads(:luminosity)
        end
        plain = PICPoissonSolver(; grid=(32, 32))
        for t in (32, 64, 128, 256)
            @test ispow2(threads(resolved(t), plain))
        end
        for t in (96, 192, 320, 100, 224)
            @test_throws ArgumentError threads(resolved(t), plain)
        end
        override = PICPoissonSolver(; grid=(32, 32),
            backend_configurations=(CUDAPICLaunchConfig(luminosity_threads=64),))
        @test threads(resolved(96), override) == 64
    else
        @test_skip "CUDA device not available"
    end
    # (c) the fallback a bare `collide!` uses when no configuration is installed
    @test ispow2(Octopus._cuda_pic_threads(:luminosity))
end

@testset "A launch config a bare collide! cannot apply is not discarded silently" begin
    # `_with_solver_execution_configuration` installs the resolved launch config as
    # a scoped value, and its only caller is the StrongStrongTask path. A bare
    # `collide!(solver, beam1, beam2, CUDABackend)` installs nothing, so every PIC
    # launch family falls back to a fixed thread count and the device
    # MAX_THREADS_PER_BLOCK validation never runs.
    #
    # Measured before this test existed: a solver carrying
    # CUDAPICLaunchConfig(kick=64, deposition=64, field=64) produced 0
    # :cuda_pic_launch receipts through a bare collide! and 12 (threads {64,128})
    # through a task. Same class as audit part 2's S1 -- a public tuning surface
    # that silently does nothing -- so it must at least be loud.
    cfg = CUDAPICLaunchConfig(kick_threads=64, deposition_threads=64, field_threads=64)
    s = PICPoissonSolver(; grid=(32, 32), backend_configurations=(cfg,))
    plain = PICPoissonSolver(; grid=(32, 32))

    # host-side predicate: fires only when a config exists AND cannot be applied
    @test_logs (:warn,) Octopus._warn_inactive_pic_launch_config(s)
    @test_logs Octopus._warn_inactive_pic_launch_config(plain)          # nothing to warn about
    @test Octopus._warn_inactive_pic_launch_config(GaussianPoissonSolver()) === nothing

    # the composed hybrid must unwrap to the same predicate -- this is the S1 shape,
    # where an `isa` test against the concrete solver missed the composing type
    let g = GaussianPICPoissonSolver(; grid=(32, 32), backend_configurations=(cfg,))
        @test_logs (:warn,) Octopus._warn_inactive_pic_launch_config(g)
    end

    # and it must stay silent on the path that DOES apply the configuration
    if CUDA_TESTS_ACTIVE
        set_global_rng!(seed=7, method=:philox)
        b = Beam(64, CUDAExecutionPolicy(), Float64; beta=(0.55, 0.056, 12.7),
                 alpha=(0.0, 0.0, 0.0), sigma=(1.0e-4, 1.0e-5, 1.0e-2), cutoff=5.0,
                 rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9,
                 r0=RE * ME0 / EMASS_EV, npart=1.0e11)
        pol = Octopus._resolve_execution_policy(
            CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=128)), b.rep)
        @test_logs Octopus._with_solver_execution_configuration(s, pol) do
            Octopus._warn_inactive_pic_launch_config(s)
        end
    else
        @test_skip "CUDA device not available"
    end
end

@testset "Solver option effectiveness" begin
    # The solver-level analogue. Element parameters had a mechanical sweep and
    # solver options did not, which is how GaussianPICPoissonSolver came to
    # discard every CUDAPICLaunchConfig and the inherited policy thread count
    # while configuration_report called them resolved.
    r = validate(SolverOptionEffectivenessContract())
    @test r.status in (:passed, :skipped)      # :skipped when no CUDA device
    @test r.metrics[:cpu_options_checked] > 60

    # Every declared option must be judged or exempted with a reason; an option
    # with neither fails, so the tables cannot fall behind the schema.
    let alts = copy(Octopus._default_solver_option_alternatives())
        alts[:SpectralPoissonSolver] = Dict{Symbol,Any}()
        bad = validate(SolverOptionEffectivenessContract(alternatives=alts))
        @test bad.status === :failed
        @test occursin("no declared alternative", bad.message)
    end

    # An alternative equal to the probe's own value would compare a solver
    # against itself and pass vacuously.
    let alts = copy(Octopus._default_solver_option_alternatives())
        alts[:GaussianPICPoissonSolver] =
            merge(alts[:GaussianPICPoissonSolver], Dict{Symbol,Any}(:deposit_method => :TSC))
        bad = validate(SolverOptionEffectivenessContract(alternatives=alts))
        @test bad.status === :failed
        @test occursin("equal to its own probe value", bad.message)
    end
end

@testset "Element parameters carry their own number type" begin
    u = (1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 0.0, 1.0e-3)

    # An ordinary element is still Float64, which is the thing that must not
    # change: the GPU kernels and every measured result depend on it.
    @test typeof(compile_runtime(QuadrupoleSpec(L=0.4, k1=1.7, nst=4))).parameters[2] === Float64
    @test typeof(compile_runtime(SBendSpec(L=1.1, angle=0.198, k1=0.6, nst=4))).parameters[2] === Float64
    @test numeric_type(QuadrupoleSpec(L=0.4, k1=1.7)) === Float64

    # The runtime numeric type is promoted from the SPEC rather than pinned, so
    # a parameter given in another precision survives instead of being silently
    # downcast. `_fold_named_strengths` used to force Float64 here.
    @test numeric_type(QuadrupoleSpec(L=big"0.4", k1=big"1.7")) === BigFloat
    @test typeof(compile_runtime(QuadrupoleSpec(L=big"0.4", k1=big"1.7", nst=4))).parameters[2] === BigFloat
    @test eltype(getparam(QuadrupoleSpec(L=0.4, k1=big"1.7"), :kn)) === BigFloat

    # And the bound is `Number`, not `AbstractFloat`, which is what lets a dual
    # number or a truncated power series be a magnet strength. Complex-step
    # exercises exactly that path with nothing extra: seed the imaginary part of
    # a PARAMETER and the imaginary part of the output is the derivative with
    # respect to it -- the same trick the symplecticity tests use on
    # coordinates, now available for strengths, lengths and misalignments.
    let h = 1e-30
        dk1(v) = [imag(x) / h for x in compile_runtime(
            QuadrupoleSpec(L=0.4, k1=complex(v, h), nst=4))(u...)]
        ref(k) = collect(compile_runtime(QuadrupoleSpec(L=0.4, k1=k, nst=4))(u...))
        @test maximum(abs, dk1(1.7) .- (ref(1.7 + 1e-6) .- ref(1.7 - 1e-6)) ./ 2e-6) < 1.0e-9

        # A misalignment derivative, which is what beam-based alignment needs,
        # and which required the wrappers to stop pinning Float64 too.
        dx(v) = [imag(x) / h for x in compile_runtime(
            QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=complex(v, h)))(u...)]
        refx(d) = collect(compile_runtime(
            QuadrupoleSpec(L=0.4, k1=1.7, nst=4, x_offset=d))(u...))
        @test maximum(abs, dx(1.0e-3) .-
                           (refx(1.0e-3 + 1e-8) .- refx(1.0e-3 - 1e-8)) ./ 2e-8) < 1.0e-8

        # ... and through a bend, where the curvature enters the survey, the
        # pole faces and the curved-frame kick.
        dh(v) = [imag(x) / h for x in compile_runtime(
            SBendSpec(L=1.1, h=complex(v, h), b0=0.18, k1=0.6, e1=0.05, nst=4))(u...)]
        refh(g) = collect(compile_runtime(
            SBendSpec(L=1.1, h=g, b0=0.18, k1=0.6, e1=0.05, nst=4))(u...))
        @test maximum(abs, dh(0.18) .- (refh(0.18 + 1e-6) .- refh(0.18 - 1e-6)) ./ 2e-6) < 1.0e-8
    end

    # Non-numeric parameters must not disturb the promotion.
    @test numeric_type(QuadrupoleSpec(L=0.4, k1=1.7, nst=4, fringe=:all,
                                      misalign_convention=:madx)) === Float64

    # A knob is a machine control -- one supply feeding a whole magnet family --
    # so differentiating with respect to one is the most useful derivative
    # there is. That needs the knob to hold the seeded type and, crucially, the
    # COMPOUND expression evaluator not to cast its result: `Float64(f(vals...))`
    # would have computed the right value and thrown the derivative away
    # silently. BigFloat stands in for a dual here so the test needs no AD
    # dependency; both are simply "not Float64".
    let
        @knob adsweep_a::Real
        @knob adsweep_b::Real
        set_knob!(:adsweep_a, big"1.7")
        set_knob!(:adsweep_b, big"0.05")
        @test knob_value(:adsweep_a) isa BigFloat
        @test knob_value(@knob_expr adsweep_a) isa BigFloat
        @test knob_value(@knob_expr -(adsweep_a + adsweep_b)) isa BigFloat   # compound
        spec = ElementSpec{:quadrupole}(; L=0.4, nst=4,
                                        kn=(0.0, @knob_expr -(adsweep_a + adsweep_b)))
        @test numeric_type(Octopus.resolve_knobs(spec)) === BigFloat
        @test typeof(compile_runtime(spec)).parameters[2] === BigFloat
        # a Float64 knob still yields a Float64 element, unchanged
        set_knob!(:adsweep_a, 1.7); set_knob!(:adsweep_b, 0.05)
        @test typeof(compile_runtime(spec)).parameters[2] === Float64
        # A knob declared ::Float64 still narrows to Float64, which is the point
        # of declaring it -- and is exactly why an AD seed needs a wider
        # declaration. BigFloat narrows silently because the conversion exists;
        # a dual number has no conversion at all and is rejected outright.
        @knob adsweep_strict::Float64 = 1.7
        set_knob!(:adsweep_strict, big"1.9")
        @test knob_value(:adsweep_strict) isa Float64
    end

    # A sweep over every registered element: seed each numeric parameter with a
    # complex step and check the derivative against a central difference. This
    # is the regression guard for the whole class -- a future `Float64` written
    # where the type should be carried shows up here as a lost element rather
    # than as a silently non-differentiable one.
    let H = 1e-30, verified = String[], disagreed = String[]
        seed(spec, key, v) = (p = copy(getfield(spec, :params)); p[key] = v;
                              ElementSpec{kind(spec)}(p))
        for T in sort(collect(Octopus.registered_element_specs()); by=string)
            meta = Octopus._element_meta_or_nothing(T)
            meta === nothing && continue
            ex = example_spec(T)
            ex isa ElementSpec || continue
            for (key, val) in sort(collect(getfield(ex, :params)); by=x -> string(x[1]))
                val isa Real && !(val isa Bool) && !(val isa Integer) || continue
                val == 0 && continue
                try
                    d = [imag(x) / H for x in
                         compile_runtime(seed(ex, key, complex(float(val), H)))(u...)]
                    h = abs(float(val)) * 1e-6
                    f(v) = collect(compile_runtime(seed(ex, key, v))(u...))
                    fd = (f(float(val) + h) .- f(float(val) - h)) ./ (2h)
                    err = maximum(abs, d .- fd) / max(maximum(abs, fd), 1e-8)
                    push!(isfinite(err) && err < 1e-4 ? verified : disagreed,
                          "$(meta.kind).$(key)")
                catch sweep_err
                    # Genuinely not complex-steppable, and each for a reason:
                    # an aperture is a threshold test (a complex coordinate
                    # has no ordering, so it raises a MethodError) and the
                    # strong-beam evaluators are calibrated per precision
                    # (MethodError / InexactError on a complex parameter).
                    # Only those two exception types may be swallowed; a bare
                    # catch here once hid every possible regression, so
                    # anything else -- a genuine error in an element map --
                    # propagates and fails the testset.
                    sweep_err isa Union{MethodError,InexactError} || rethrow()
                end
            end
        end
        @test isempty(disagreed)
        # The floor is today's exact count (25: measured 2026-08 -- the caught
        # bucket holds only aperture.x/y_limit, gaussian_strong_beam.sigz and
        # thin_strong_beam.kbb/klum), so silently losing even ONE element to
        # the catch above fails. Raise this number when a new differentiable
        # parameter is registered; never lower it.
        @test length(verified) >= 25
        # the kinds that must stay differentiable
        for k in ("quadrupole", "sextupole", "octupole", "multipole", "sbend",
                  "drift", "patch", "kicker", "thin_crab_cavity")
            @test any(startswith(v, k * ".") for v in verified)
        end
    end
end
