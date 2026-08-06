using Test
using Octopus
using LinearAlgebra
# Seeded sweeps whose sample values must not be dyadic (see the TSC weight
# testset -- a dyadic-only grid cannot fail on the defect it names, audit U20-1).
using Random
# Capturing warnings as evidence: a testset that asserts a solver did NOT clip
# charge has to be able to see the warning it must not find (audit U19-2).
using Logging
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
        # No count here on purpose. This message said "Nine" while the real
        # number had grown past twenty, because a hand-maintained tally of a set
        # that grows with every new CUDA testset has nothing to keep it honest
        # (2026-08-05_b audit, U20-11). The skipped testsets now announce
        # themselves individually in the summary's Broken column, which is the
        # count that cannot drift.
        @info """
        NO CUDA DEVICE: the GPU half of this suite did NOT run.
        Every CUDA-gated testset was skipped, including all CPU/CUDA parity
        checks; each reports itself as Broken/skipped in the summary below.
        A green run here says nothing about pic_cuda.jl, gaussian_pic_cuda.jl
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

@testset "RF cavity closes the longitudinal plane" begin
    # docs/theory/rf_cavity_and_reference_energy.md. A cavity WITHOUT
    # acceleration -- Bmad's rfcavity, not its lcavity -- so the reference
    # energy is constant and phase = 0 is no net acceleration.
    u = (1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 0.2, 8.0e-4)
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    cav(; kw...) = compile_runtime(ThinRFCavitySpec(400.8e6; e0=275e9, mc2=PMASS_EV, kw...))

    # registered like any other element
    @test :thin_rf_cavity in summarize_registry().elements
    @test validate_element_metadata().passed

    # A switched-off cavity is exactly nothing, not nothing to round-off.
    @test collect(cav(voltage=0.0)(u...)) == collect(u)
    # ... and with a length it is a drift, to the round-off of splitting one
    # drift into two halves -- a few ulp on a z of 0.2, not a physics difference.
    @test maximum(abs, collect(cav(voltage=0.0, L=2.0)(u...)) .-
                       collect(compile_runtime(DriftSpec(L=2.0))(u...))) < 1.0e-15

    # thin is the exact L -> 0 limit of drift-kick-drift, converging linearly
    let thin = collect(cav(voltage=12e6)(u...))
        prev = Inf
        for L in (1.0e-3, 1.0e-5, 1.0e-7)
            e = maximum(abs, collect(cav(voltage=12e6, L=L)(u...)) .- thin)
            @test e < prev
            prev = e
        end
        @test prev < 1.0e-10
    end

    # symplectic, which is the composition claim: two canonical wrappers around
    # a kick that changes only the momentum by a function of the coordinate
    for (L, ph) in ((0.0, pi / 2), (0.0, 0.3), (2.0, 0.3), (2.0, 0.0))
        e = cav(voltage=12e6, L=L, phase=ph)
        J = zeros(6, 6)
        for j in 1:6
            v = ComplexF64[u...]
            v[j] += 1e-30im
            J[:, j] = imag.(collect(e(v...))) ./ 1e-30
        end
        @test maximum(abs, J' * S6 * J - S6) < 1.0e-14
    end

    # The kick is exactly qV sin(theta)/(P0 c), measured in p_t where it is
    # stated -- not in pz, where it would pick up the beta factor and hide it.
    let e0 = 275e9, V = 12e6, f = 400.8e6, ph = 0.3, z = 0.2, pz = 8.0e-4
        b0, g0 = reference_beta_gamma(e0, PMASS_EV)
        o = cav(voltage=V, phase=ph)(0.0, 0.0, 0.0, 0.0, z, pz)
        z1, pin = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, z, pz; beta0=b0, gamma0=g0)
        _, pout = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, o[5], o[6]; beta0=b0, gamma0=g0)
        @test pout - pin ≈ V / (b0 * e0) * sin(2pi * f / CLIGHT * z1 + ph) atol = 1.0e-16
    end

    # THE BETA FACTOR. dδ/dp_t must be 1/beta, not 1. This is the check that a
    # formula lifted from a code with another longitudinal convention fails,
    # and it is invisible for an electron ring.
    for (e0, mc2) in ((10e9, PMASS_EV), (275e9, PMASS_EV), (10e9, EMASS_EV))
        b0, g0 = reference_beta_gamma(e0, mc2)
        e = compile_runtime(ThinRFCavitySpec(400.8e6; voltage=1.0e6, e0=e0, mc2=mc2, phase=pi / 2))
        o = e(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        _, pin = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, 0.0, 0.0; beta0=b0, gamma0=g0)
        _, pout = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, o[5], o[6]; beta0=b0, gamma0=g0)
        @test o[6] / (pout - pin) ≈ 1 / particle_beta(PATHLENGTH_DELTA, 0.0; beta0=b0, gamma0=g0) rtol = 1.0e-5
    end
    # and it is genuinely a proton-versus-electron difference, not a rounding one
    @test 1 / reference_beta(10e9, PMASS_EV) - 1 > 1.0e-3
    @test 1 / reference_beta(10e9, EMASS_EV) - 1 < 1.0e-8

    # Synchrotron motion in a toy ring: stable, area-preserving, and nu_s
    # scaling as sqrt(V), which is the signature of a harmonic bucket.
    ring(V) = begin
        M = Matrix{Float64}(I, 6, 6)
        M[5, 6] = -1.0e-3                     # a pure longitudinal slip
        [compile_runtime(ThinRFCavitySpec(400.8e6; voltage=V, e0=275e9, mc2=PMASS_EV)),
         compile_runtime(Linear6DSpec(; matrix=Tuple(vec(permutedims(M)))))]
    end
    nus = map((2e6, 8e6, 32e6)) do V
        ops = ring(V)
        J = zeros(2, 2)
        for j in 1:2
            v = ComplexF64[0, 0, 0, 0, 0, 0]
            v[4 + j] += 1e-30im
            o = foldl((c, op) -> op(c...), ops; init=Tuple(v))
            J[:, j] = [imag(o[5]), imag(o[6])] ./ 1e-30
        end
        @test abs(J[1, 1] * J[2, 2] - J[1, 2] * J[2, 1] - 1) < 1.0e-12   # area preserved
        @test abs(J[1, 1] + J[2, 2]) < 2                                  # stable
        acos((J[1, 1] + J[2, 2]) / 2) / 2pi
    end
    @test nus[2] / nus[1] ≈ 2 rtol = 1.0e-6      # quadrupling V doubles nu_s
    @test nus[3] / nus[2] ≈ 2 rtol = 1.0e-6

    # construction errors, each naming the fix
    @test_throws ArgumentError ThinRFCavitySpec(400.8e6; voltage=1e6)                    # no e0/mc2
    @test_throws ArgumentError ThinRFCavitySpec(400.8e6; strength=1e-5)                  # no beta0
    @test_throws ArgumentError ThinRFCavitySpec(400.8e6)                                 # nothing at all
    @test_throws ArgumentError ThinRFCavitySpec(-1.0; voltage=1e6, e0=275e9, mc2=PMASS_EV)
    @test_throws ArgumentError ThinRFCavitySpec(400.8e6; voltage=1e6, e0=275e9,
                                            mc2=PMASS_EV, strength=1e-5)             # both

    # Units match ThinCrabCavity deliberately: one meaning of `phase` per lattice.
    @test parameter_schema(ElementSpec{:thin_rf_cavity}).frequency.unit ==
          parameter_schema(ElementSpec{:thin_crab_cavity}).frequency.unit == "Hz"
    @test parameter_schema(ElementSpec{:thin_rf_cavity}).phase.unit ==
          parameter_schema(ElementSpec{:thin_crab_cavity}).phase.unit == "rad"
end

@testset "Longitudinal conventions convert exactly" begin
    # docs/theory/lattice_hamiltonian_and_conventions.md Section 2, implemented.
    # The claim being tested is not "accurate" but EXACT: all four pairs come
    # from one (q_t, p_t) by generating functions, so every conversion is
    # symplectic at any amplitude, not to first order in delta.
    convs = (TIME_ENERGY, SIGMA_PSIGMA, PATHLENGTH_DELTA, TIME_DELTA)
    cases = (reference_beta_gamma(275e9, PMASS_EV),      # proton, beta0 < 1 visibly
             reference_beta_gamma(24e9, PMASS_EV),       # proton, lower
             reference_beta_gamma(10e9, EMASS_EV))       # electron, ultrarelativistic

    @test convention_number.(convs) == (1, 2, 3, 4)
    @test tracking_convention() === PATHLENGTH_DELTA     # Octopus tracks #3

    # round trip, every ordered pair, with and without an arc offset
    for (b0, g0) in cases, s in (0.0, 37.0), a in convs, b in convs
        z1, p1 = convert_longitudinal(PATHLENGTH_DELTA => a, 1.3e-3, 8.0e-4;
                                      beta0=b0, gamma0=g0, s=s)
        z2, p2 = convert_longitudinal(a => b, z1, p1; beta0=b0, gamma0=g0, s=s)
        z3, p3 = convert_longitudinal(b => a, z2, p2; beta0=b0, gamma0=g0, s=s)
        @test max(abs(z3 - z1), abs(p3 - p1)) < 1.0e-15
    end

    # exactly symplectic: the 2x2 longitudinal Jacobian has unit determinant
    for (b0, g0) in cases, a in convs, b in convs
        a === b && continue
        J = zeros(2, 2)
        for j in 1:2
            zc = complex(1.3e-3, j == 1 ? 1e-30 : 0.0)
            pc = complex(8.0e-4, j == 2 ? 1e-30 : 0.0)
            o = convert_longitudinal(a => b, zc, pc; beta0=b0, gamma0=g0, s=37.0)
            J[:, j] = [imag(o[1]), imag(o[2])] ./ 1e-30
        end
        @test abs(J[1, 1] * J[2, 2] - J[1, 2] * J[2, 1] - 1) < 1.0e-14
    end

    # the note's own identities, term by term
    let (b0, g0) = reference_beta_gamma(24e9, PMASS_EV), z = 1.3e-3, pz = 8.0e-4
        z1, pt = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, z, pz; beta0=b0, gamma0=g0)
        z2, ps = convert_longitudinal(PATHLENGTH_DELTA => SIGMA_PSIGMA, z, pz; beta0=b0, gamma0=g0)
        z4, d4 = convert_longitudinal(PATHLENGTH_DELTA => TIME_DELTA, z, pz; beta0=b0, gamma0=g0)
        beta = particle_beta(PATHLENGTH_DELTA, pz; beta0=b0, gamma0=g0)
        @test z2 ≈ b0 * z1 atol = 1.0e-18
        @test z4 ≈ beta * z1 atol = 1.0e-18
        @test ps ≈ pt / b0 atol = 1.0e-18
        @test d4 ≈ pz atol = 1.0e-15               # #3 and #4 share a momentum
        @test beta ≈ (1 + pz) / (1 / b0 + pt) atol = 1.0e-15
        # an on-momentum particle travels at the reference velocity, exactly
        @test particle_beta(PATHLENGTH_DELTA, 0.0; beta0=b0, gamma0=g0) == b0
    end

    # `s` shifts ONLY PathLengthDelta -- its coordinate is s - l rather than a
    # pure time. That is the PTC `TIME=FALSE` offset the note flags, isolated
    # here so a comparison cannot pick it up by accident.
    let (b0, g0) = reference_beta_gamma(24e9, PMASS_EV)
        for c in convs
            a = convert_longitudinal(TIME_ENERGY => c, 1.3e-3, 8.0e-4; beta0=b0, gamma0=g0, s=0.0)
            b = convert_longitudinal(TIME_ENERGY => c, 1.3e-3, 8.0e-4; beta0=b0, gamma0=g0, s=37.0)
            if c === PATHLENGTH_DELTA
                @test abs(b[1] - a[1]) > 1.0e-6
            else
                @test b[1] == a[1]
            end
        end
    end

    # reference kinematics, and the error a kinetic energy would produce
    @test reference_gamma(275e9, PMASS_EV) ≈ 275e9 / PMASS_EV
    @test reference_beta(10e9, EMASS_EV) < 1
    @test reference_beta(1e12, EMASS_EV) > reference_beta(10e9, EMASS_EV)
    @test_throws ArgumentError reference_beta(0.5 * PMASS_EV, PMASS_EV)

    # differentiable, like every other map: dz1/dz = 1/beta for #3 -> #1
    let (b0, g0) = reference_beta_gamma(24e9, PMASS_EV), h = 1e-30, pz = 8.0e-4
        o = convert_longitudinal(PATHLENGTH_DELTA => TIME_ENERGY, complex(1.3e-3, h), pz;
                                 beta0=b0, gamma0=g0)
        @test imag(o[1]) / h ≈ 1 / particle_beta(PATHLENGTH_DELTA, pz; beta0=b0, gamma0=g0) rtol = 1e-12
    end
end

@testset "ForwardDiff differentiates the lattice" begin
    # Octopus takes NO runtime dependency on ForwardDiff. It works because the
    # element layer is generic in its number type, so this testset is here to
    # keep it that way -- and to reach two things complex-step cannot:
    # second derivatives, and the solenoid, whose kernel already uses complex
    # arithmetic internally so the complex-step trick cannot nest inside it.
    u = [1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 0.0, 1.0e-3]
    S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])
    qf = QuadrupoleSpec(L=0.4, k1=1.7, nst=4)
    qd = QuadrupoleSpec(L=0.4, k1=-1.7, nst=4)
    dr = DriftSpec(L=0.6)
    bend = SBendSpec(L=1.1, angle=0.198, k1=0.3, e1=0.05, e2=0.05, nst=4)
    ops = [compile_runtime(e) for e in BeamLine("CELL", qf, dr, bend, dr, qd, dr)]
    track(v) = collect(foldl((c, o) -> o(c...), ops; init=Tuple(v)))

    # 1. the transfer matrix, against the complex step the suite already trusts
    J = ForwardDiff.jacobian(track, u)
    Jcs = zeros(6, 6)
    for j in 1:6
        v = ComplexF64.(u)
        v[j] += 1e-30im
        Jcs[:, j] = imag.(collect(foldl((c, o) -> o(c...), ops; init=Tuple(v)))) ./ 1e-30
    end
    @test maximum(abs, J .- Jcs) < 1.0e-13
    @test maximum(abs, J' * S6 * J - S6) < 1.0e-13

    # 2. derivatives with respect to PARAMETERS, which is what the number-type
    #    sweep bought and what a transfer matrix alone cannot give.
    obj(p) = begin
        line = BeamLine("CELL",
            QuadrupoleSpec(L=0.4, k1=p[1], nst=4), DriftSpec(L=0.6),
            SBendSpec(L=1.1, h=p[2], b0=p[2], k1=0.3, e1=0.05, e2=0.05, nst=4),
            DriftSpec(L=0.6), QuadrupoleSpec(L=0.4, k1=-p[1], nst=4, x_offset=p[3]),
            DriftSpec(L=0.6))
        o = foldl((c, e) -> compile_runtime(e)(c...), line; init=Tuple(eltype(p).(u)))
        return o[1]^2 + o[3]^2
    end
    p0 = [1.7, 0.18, 1.0e-4]
    g = ForwardDiff.gradient(obj, p0)
    for (i, h) in ((1, 1e-6), (2, 1e-6), (3, 1e-8))
        e = zeros(3); e[i] = h
        @test g[i] ≈ (obj(p0 .+ e) - obj(p0 .- e)) / 2h rtol = 1.0e-5
    end

    # 3. a Hessian. Complex-step is first order only and cannot check this at
    #    all, so nesting is genuinely new coverage -- it also exercises
    #    ForwardDiff's tag machinery, which is what stops an inner perturbation
    #    leaking into the outer one.
    H = ForwardDiff.hessian(obj, p0)
    # Near-exact, not bit-exact: nested-dual Hessians are not guaranteed
    # bit-symmetric, and the u^8 series terms the 2026-08-05 campaign added
    # to the curvature helpers (U10-5/6) round one ij/ji pair differently at
    # 4.3e-19 — one ulp at this scale. The old `== 0.0` held only by
    # arithmetic accident; the FD value pins below carry the discriminating
    # power.
    @test maximum(abs, H .- H') <= 8 * eps() * max(1.0, maximum(abs, H))
    @test all(isfinite, H)
    #    Symmetric and finite alone cannot see a wrong-but-finite value, so pin
    #    every column against a central finite difference of the gradient --
    #    which item 2 already pinned against differences of obj itself.
    #    Measured agreement 4e-9..9e-8, so rtol=1e-5 leaves >100x headroom.
    for (j, h) in ((1, 1e-5), (2, 1e-5), (3, 1e-7))
        e = zeros(3); e[j] = h
        @test H[:, j] ≈ (ForwardDiff.gradient(obj, p0 .+ e) .-
                         ForwardDiff.gradient(obj, p0 .- e)) ./ 2h rtol = 1.0e-5
    end

    # 4. the solenoid, invisible to complex-step because its own kernel builds
    #    `complex(a, b)` internally. A dual reaches it, so this is the only
    #    guard that a Float64 pin there would trip.
    for (mk, v, h) in ((L -> SolenoidSpec(L=L, ks=0.35), 1.3, 1e-7),
                       (k -> SolenoidSpec(L=1.3, ks=k), 0.35, 1e-7))
        d = ForwardDiff.derivative(x -> collect(compile_runtime(mk(x))(u...)), v)
        fd = (collect(compile_runtime(mk(v + h))(u...)) .-
              collect(compile_runtime(mk(v - h))(u...))) ./ 2h
        @test maximum(abs, d .- fd) / max(maximum(abs, fd), 1e-8) < 1.0e-5
    end

    # 5. several knobs at once. Each must land in its OWN partial slot; seeding
    #    two knobs with a scalar partial silently sums their derivatives into
    #    one, and `gradient` is what makes that impossible.
    let
        @knob fd_qa::Real
        @knob fd_qb::Real
        run() = foldl((c, e) -> compile_runtime(e)(c...),
                      (ElementSpec{:quadrupole}(; L=0.4, nst=4, kn=(0.0, @knob_expr fd_qa)),
                       DriftSpec(L=0.6),
                       ElementSpec{:quadrupole}(; L=0.4, nst=4, kn=(0.0, @knob_expr -fd_qb)),
                       DriftSpec(L=0.6)); init=Tuple(u))[1]
        gk = ForwardDiff.gradient(p -> (set_knob!(:fd_qa, p[1]);
                                        set_knob!(:fd_qb, p[2]); run()), [1.7, 1.5])
        set_knob!(:fd_qa, 1.7); set_knob!(:fd_qb, 1.5)
        one(i, h) = (e = zeros(2); e[i] = h; e)
        f2(p) = (set_knob!(:fd_qa, p[1]); set_knob!(:fd_qb, p[2]); r = run();
                 set_knob!(:fd_qa, 1.7); set_knob!(:fd_qb, 1.5); r)
        for i in 1:2
            e = one(i, 1e-6)
            @test gk[i] ≈ (f2([1.7, 1.5] .+ e) - f2([1.7, 1.5] .- e)) / 2e-6 rtol = 1.0e-5
        end
        # the two are genuinely independent, not a directional derivative
        @test gk[1] != gk[2]
    end
end

@testset "BeamLine composes, addresses and tracks" begin
    u = (1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 0.0, 1.0e-3)
    qf = QuadrupoleSpec(L=0.4, k1=1.7, nst=4, name="QF")
    qd = QuadrupoleSpec(L=0.4, k1=-1.7, nst=4, name="QD")
    dr = DriftSpec(L=0.6, name="DR")

    # Nesting is construction syntax: it expands away, leaving provenance.
    fodo = BeamLine("FODO", qf, dr, qd, dr)
    ring = BeamLine("RING", fodo, fodo)
    @test length(fodo) == 4 && length(ring) == 8
    @test entry_path(ring[1]) == "RING/FODO/QF"
    @test entry_path(ring[5]) == "RING/FODO[2]/QF"
    @test entry_path(ring[4]) == "RING/FODO/DR[2]"
    @test s_positions(ring) == [0.0, 0.4, 1.0, 1.4, 2.0, 2.4, 3.0, 3.4]

    # A line tracks exactly as the equivalent bare tuple. This is the check that
    # the container is a construction convenience and not a physics change.
    mk() = Phase6DRep([1.0e-3, 2.0e-3], [0.0, 1.0e-4], [0.5e-3, -1.0e-3],
                      [0.0, -1.0e-4], [0.0, 0.0], [1.0e-3, 0.0])
    let a = mk(), b = mk()
        execute!(TrackingTask(ring), a; turns=3)
        execute!(TrackingTask((qf, dr, qd, dr, qf, dr, qd, dr)), b; turns=3)
        @test collect(a[1]) == collect(b[1]) && collect(a[2]) == collect(b[2])
    end
    # ... including a weak-strong line, which is a different tracking method.
    let ip = ThinStrongBeamSpec(kbb=1.0e-4, beta=(1.0, 1.0), sigma=(1.0e-3, 1.0e-3))
        a = Phase6DRep([1.0e-3], [0.0], [2.0e-3], [0.0], [0.0], [0.0])
        b = Phase6DRep([1.0e-3], [0.0], [2.0e-3], [0.0], [0.0], [0.0])
        execute!(TrackingTask(BeamLine("IR", ip, DriftSpec(L=0.5))), a; turns=2)
        execute!(TrackingTask((ip, DriftSpec(L=0.5))), b; turns=2)
        @test collect(a[1]) == collect(b[1])
    end

    # Selection: one entry point, XPath-shaped, instead of a family of lookups.
    let cqs = BeamLine("CQS", qf, qd), arc = BeamLine("ARC1", cqs, dr, cqs, dr)
        @test find_entries(arc, sel"ARC1/CQS[2]") == [4, 5]
        @test find_entries(arc, sel"ARC1//QF") == [1, 4]
        @test find_entries(arc, sel"ARC1/CQS[*]/QD") == [2, 5]
        @test find_entries(arc, sel"*/CQS[1]/QF") == [1]
        @test find_entries(arc, r"ARC1/DR") == [3, 6]
        @test find_entries(arc, e -> getparam(e, :L, 0.0) > 0.5) == [3, 6]
        @test find_entries(arc, ElementSpec{:drift}) == [3, 6]
        # Selecting an assembly selects everything in it, not a node standing
        # for it, which is why matching is against a path PREFIX.
        @test length(find_entries(arc, sel"ARC1")) == length(arc)
        @test isempty(find_entries(arc, sel"NOPE"))
    end
    @test_throws ArgumentError Octopus._parse_selector("")
    @test_throws ArgumentError Octopus._parse_selector("A[0]")
    @test_throws ArgumentError Octopus._parse_selector("A[x]")

    # Cross-cutting tags: a magnet is in a cryostat AND on a power supply, and
    # those do not nest. A set, not a second path.
    let l = BeamLine("PS", BeamLine("M", qf; tags=(:cryo,)); tags=(:ps7,))
        @test entry_tags(l[1]) == Set([:cryo, :ps7])
        @test find_entries(l, :cryo) == [1] && find_entries(l, :ps7) == [1]
    end

    # Shared spec, private placement. Both occurrences follow qf until one is
    # overridden, after which it is detached -- the behaviour a trim supply
    # would NOT want, which is what knob expressions are for.
    let line = BeamLine("L", qf, dr, qf)
        base = collect(compile_runtime(line[3])(u...))
        line[3].x_offset = 1.0e-3
        @test collect(compile_runtime(line[1])(u...)) == base   # sibling untouched
        @test collect(compile_runtime(line[3])(u...)) != base   # this one moved
        for (k, v) in ((:kn, (0.0, 1.9)), (:nst, 16), (:tilt, 0.02))
            e = Octopus.LineEntry(qf, [("QF", 1)], Set{Symbol}(), Dict{Symbol,Any}(k => v))
            @test collect(compile_runtime(e)(u...)) != base
        end
    end
    # A named strength is folded into kn at construction, so an override naming
    # it would be written, reported, and never read. Rejected where it is
    # written rather than silently ignored.
    let line = BeamLine("L", qf, dr)
        @test_throws ArgumentError line[1].k1 = 1.9
        @test_throws ArgumentError line[1].spec = qd
        line[1].kn = (0.0, 1.9)
        @test getparam(line[1], :kn) == (0.0, 1.9)
    end

    # Reflection is ORDER ONLY, as MAD-X and Bmad both define it.
    let rev = reverse(BeamLine("CELL", qf, dr, qd))
        @test [entry_path(e) for e in rev] == ["CELL/QD", "CELL/DR", "CELL/QF"]
    end
    @test length(repeat(BeamLine("CELL", qf, dr, qd), 3)) == 9
    @test_throws ArgumentError repeat(BeamLine("CELL", qf), 0)

    # Registered like any other element kind, which is the point of a line
    # being an ElementSpec rather than a new core object.
    @test :line in summarize_registry().elements
    @test validate_element_metadata().passed
    @test haskey(parameter_schema(ElementSpec{:line}), :x_offset)
    @test example_spec(ElementSpec{:line}) isa ElementSpec{:line}
    # The keyword form is what reflection needs and what turns a slice into a
    # line; it takes placements ready-made instead of expanding children.
    let arc = BeamLine("ARC1", qf, dr, qd, dr)
        head = BeamLine(; name="HEAD", entries=arc[1:2])
        @test length(head) == 2
        @test [entry_path(e) for e in head] == ["ARC1/QF", "ARC1/DR"]
    end

    # A line carrying state of its own does not dissolve: it is a cryostat, and
    # misaligning it moves its contents RIGIDLY. This is the design note's claim
    # that assembly misalignment falls out of _misalignment_wrap for free.
    let q1 = QuadrupoleSpec(L=0.4, k1=1.2, nst=4, name="Q1"),
        q2 = QuadrupoleSpec(L=0.4, k1=-1.2, nst=4, name="Q2"),
        d = 2.0e-4

        aligned = BeamLine("CRYO", q1, DriftSpec(L=0.3), q2)
        cryo = BeamLine("CRYO", q1, DriftSpec(L=0.3), q2; x_offset=d)
        lat = BeamLine("LAT", DriftSpec(L=0.2, name="A"), cryo)
        @test length(lat) == 2                       # the cryostat stays whole
        @test compile_runtime(cryo) isa MisalignedElement
        @test compile_runtime(aligned) isa Octopus.CompositeLine

        ra = collect(compile_runtime(aligned)(u...))
        @test maximum(abs, collect(compile_runtime(cryo)(u...)) .- ra) > 1.0e-6
        # Rigidity: displace the girder and the beam together and nothing
        # changes. Every magnet inside must have moved by the same amount.
        shifted = collect(compile_runtime(cryo)(u[1] + d, u[2], u[3], u[4], u[5], u[6]))
        shifted[1] -= d
        @test maximum(abs, shifted .- ra) < 1.0e-15
    end
end

@testset "Loss accounting reports itself" begin
    # Drained on a task so a full pipe buffer cannot deadlock the capture.
    function capture_stdout(f)
        original = stdout
        rd, wr = redirect_stdout()
        reader = @async read(rd, String)
        try
            f()
        finally
            redirect_stdout(original)
            close(wr)
        end
        return fetch(reader)
    end

    line = (DriftSpec(L=1.0), ApertureSpec(x_limit=2.0e-3, name="COLL_A"),
            DriftSpec(L=2.5), ApertureSpec(y_limit=1.0e-3, name="COLL_B"),
            DriftSpec(L=0.5))
    mk() = Phase6DRep([1.0e-3, 5.0e-3, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0],
                      [0.0, 0.0, 4.0e-3, 0.0], [0.0, 0.0, 0.0, 0.0],
                      zeros(4), zeros(4))

    # Arc position: the summed L ahead of each aperture, in the same order as
    # aperture_names and aperture_counts so a reader can zip the three.
    @test Octopus._aperture_s_positions(line) == [1.0, 3.5]
    @test Octopus._aperture_s_positions((MarkerSpec(), DriftSpec(L=0.4),
                                         ApertureSpec(x_limit=1.0))) == [0.4]
    # Zero-length entries advance nothing, including an in-line observer.
    @test Octopus._aperture_s_positions(
        (DriftSpec(L=1.0), ScheduledObserver(BPMObserver("b")),
         ApertureSpec(x_limit=1.0))) == [1.0]

    allow_lost_particles(; enabled=true) do
        # Silent when nothing was lost: this is what keeps an automatic
        # diagnostic usable in a test suite and a validation sweep.
        quiet = capture_stdout() do
            execute!(TrackingTask((DriftSpec(L=1.0),
                                   ApertureSpec(x_limit=1.0, name="WIDE"))), mk(); turns=1)
        end
        @test isempty(quiet)

        # Lossy run with no file: the summary goes to stdout, per collimator.
        out = capture_stdout() do
            execute!(TrackingTask(line), mk(); turns=1)
        end
        @test occursin("2 of 4 particles lost", out)
        @test occursin("COLL_A", out) && occursin("COLL_B", out)

        # ... and the off-switch works, or a library that chatters cannot be used.
        @test isempty(capture_stdout() do
            execute!(TrackingTask(line; loss_report=false), mk(); turns=1)
        end)

        # The switch skips the O(N) reduction rather than suppressing its
        # output, which is the point of having it -- so it also switches off the
        # detection. No warning on a non-finite particle, and no summary in the
        # file. Pinned because it is a trade a caller should not discover.
        @test Octopus._task_loss_summary(TrackingTask(line; loss_report=false),
                                         mk()) === nothing
        @test Octopus._task_loss_summary(TrackingTask(line), mk()) !== nothing
        silent = tempname() * ".h5"
        execute!(TrackingTask(line; loss_log=silent, loss_report=false), mk(); turns=1)
        Octopus.HDF5.h5open(silent) do f
            @test !haskey(f, "summary_dead")     # detection off, records still written
            @test read(f["aperture_s"]) == [1.0, 3.5]
        end
        rm(silent; force=true)

        # A file was asked for, so the console stays quiet and the numbers land
        # in the artifact instead -- including the arc positions, which the
        # writer has always accepted and nothing ever supplied.
        path = tempname() * ".h5"
        @test isempty(capture_stdout() do
            execute!(TrackingTask(line; loss_log=path), mk(); turns=1)
        end)
        Octopus.HDF5.h5open(path) do f
            @test read(f["aperture_s"]) == [1.0, 3.5]
            @test read(f["aperture_names"]) == ["COLL_A", "COLL_B"]
            @test read(f["summary_particles"]) == 4
            @test read(f["summary_dead"]) == 2
            @test read(f["summary_logged"]) == 2
            @test read(f["summary_unattributed"]) == 0
            @test read(f["summary_live"]) == 2
        end
        rm(path; force=true)

        # `unattributed` is the whole reason the summary exists: a particle that
        # went non-finite with no aperture responsible. It must warn, and it
        # must do so even when the line has no aperture at all -- which is
        # exactly the case where nothing else would notice.
        nan_rep() = Phase6DRep([1.0e-3, NaN], [0.0, 0.0], [0.0, 0.0],
                               [0.0, 0.0], zeros(2), zeros(2))
        @test_logs (:warn,) match_mode = :any execute!(
            TrackingTask((DriftSpec(L=1.0), ApertureSpec(x_limit=1.0, name="WIDE"))),
            nan_rep(); turns=1)
        @test_logs (:warn,) match_mode = :any execute!(
            TrackingTask((DriftSpec(L=1.0),)), nan_rep(); turns=1)
        # ... and with the reduction skipped there is nothing left to warn from.
        @test_logs execute!(TrackingTask((DriftSpec(L=1.0),); loss_report=false),
                            nan_rep(); turns=1)
    end
end

@testset "Every walker over the line agrees on what a container is" begin
    # Audit part 7, T1/T3/T4/T5: `_append_runtime_line!` walked nested vectors
    # and `LineEntry` placements while the sizing, arc-length, knob and
    # contract walks each missed one of them. The worst consequence was T3: an
    # aperture inside a nested vector was bound with a lattice-order id but not
    # counted when sizing `counts`, so its kill was an unchecked write past the
    # end of the vector -- and the summary reported the collimation as
    # `unattributed`. Each assertion below fails on the pre-fix code.

    # T3: the sizing walk sees a vector-nested aperture.
    nested = (DriftSpec(L=1.0), ApertureSpec(x_limit=2.0e-3, name="TOP"),
              [DriftSpec(L=2.5), ApertureSpec(y_limit=1.0e-3, name="NESTED")],
              DriftSpec(L=0.5))
    task = TrackingTask(nested)
    @test length(Octopus._aperture_specs(task.elements)) == 2
    rep = Phase6DRep([1.0e-3, 5.0e-3, 0.0, 0.0], zeros(4),
                     [0.0, 0.0, 4.0e-3, 0.0], zeros(4), zeros(4), zeros(4))
    allow_lost_particles(; enabled=true) do
        execute!(task, rep; turns=1)
    end
    @test loss_counts(loss_record(task)) == [1, 1]
    let s = loss_summary(rep, task)
        @test s.unattributed == 0
        @test s.names == ["TOP", "NESTED"]
        @test s.by_aperture == [1, 1]
    end

    # T4: elements inside the vector advance arc length.
    @test Octopus._aperture_s_positions(nested) == [1.0, 3.5]

    # T1: a knob assignment reaches a task built from a BeamLine. The tuple
    # twin of this test lives in the knob testset; before the fix the tuple
    # task recompiled and this one silently kept tracking the old value.
    @knob walker_knob = 0.25
    kspec = ElementSpec{:crab_dispersion}(; zeta1=@knob_expr(walker_knob),
        zeta2=0.0, zeta3=0.0, zeta4=0.0, tracking_method=Symplectic6DMap())
    bl_task = TrackingTask(BeamLine("KNOBLINE", kspec);
                           policy=CPUThreadsExecutionPolicy(threads=1))
    @test Octopus._has_knob_parameters(bl_task.elements)
    runbl() = (r = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [1e-3], [0.0]);
               execute!(bl_task, r; turns=1); r.x[1])
    @test runbl() == 1e-4 + 0.25 * 1e-3
    set_knob!(:walker_knob, 0.5)
    @test runbl() == 1e-4 + 0.5 * 1e-3
    # A line kept whole (own state) is knob-dependent through its placements;
    # a knob-free line is not, or every line task would recompile every turn.
    @test Octopus._has_knob_parameters(BeamLine("CRYO", kspec; x_offset=1.0e-4))
    @test !Octopus._has_knob_parameters(BeamLine("PLAIN", DriftSpec(L=1.0)))

    # T5: contracts and analyses reach a BeamLine task and a nested vector.
    qspec = ElementSpec{:quadrupole}(; L=0.4, nst=4, kn=(0.0, 0.1))
    tuple_task = TrackingTask((qspec,))
    @test !isempty(tuple_task.contracts)
    @test TrackingTask(BeamLine("Q", qspec)).contracts == tuple_task.contracts
    @test TrackingTask(BeamLine("Q", qspec)).analyses == tuple_task.analyses
    @test TrackingTask((DriftSpec(L=1.0), [qspec])).contracts == tuple_task.contracts
end

# Deliberate mid-run failure for the crashed-execute! tests below.
struct FailAtTurnAction <: Octopus.AbstractBeamAction
    at::Int64
end
Octopus.apply_action!(a::FailAtTurnAction, ctx, rep) =
    (ctx.turn == a.at && error("deliberate failure at turn $(ctx.turn)"); nothing)

# Observer pair for the stranded-finalizer test (part 7, T7).
mutable struct FinalizeFlagObserver <: Octopus.AbstractBeamObserver
    finalized::Bool
end
Octopus.observe!(o::FinalizeFlagObserver, ctx, rep) = nothing
Octopus.finalize_observer!(o::FinalizeFlagObserver) = (o.finalized = true; nothing)
struct ThrowingFinalizeObserver <: Octopus.AbstractBeamObserver end
Octopus.observe!(::ThrowingFinalizeObserver, ctx, rep) = nothing
Octopus.finalize_observer!(::ThrowingFinalizeObserver) = error("finalize failure")
# Mid-run reseed for the noise-snapshot test (part 7, T8).
struct ReseedGlobalRNGAction <: Octopus.AbstractBeamAction end
Octopus.apply_action!(::ReseedGlobalRNGAction, ctx, rep) =
    (set_global_rng!(seed=999); nothing)

@testset "Observer finalizers, BPM noise keys, and the schedule planner" begin
    # T7: one throwing finalizer must not strand the others -- a finalizer is
    # where buffered measurements reach disk. The first error still surfaces.
    flag_task = FinalizeFlagObserver(false)
    flag_line = FinalizeFlagObserver(false)
    t7 = TrackingTask((DriftSpec(L=1.0), ScheduledObserver(flag_line));
                      hooks=(ScheduledObserver(ThrowingFinalizeObserver()),
                             ScheduledObserver(flag_task)))
    @test_throws ErrorException execute!(
        t7, Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0]); turns=1)
    @test flag_task.finalized
    @test flag_line.finalized

    # T8: the noise draw is a function of the execute-time RNG snapshot, as
    # stochastic tracking is -- a mid-run set_global_rng! must not
    # retroactively change a reading.
    seed_a = UInt64(424242)
    set_global_rng!(seed=seed_a)
    method_a = global_rng_method()
    bpm8 = BPMObserver("t8"; x_noise=1.0)
    t8 = TrackingTask((DriftSpec(L=1.0),);
                      hooks=(ScheduledAction(ReseedGlobalRNGAction()),
                             ScheduledObserver(bpm8)))
    execute!(t8, Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0]); turns=1)
    @test readings(bpm8)[2][1] ==
          Octopus.octopus_normal(seed_a, method_a, 0, bpm8.rng_id, 0, 1, Float64)
    set_global_rng!(seed=seed_a)

    # T9: x_noise is per-reading, so a BPM read twice in one turn draws twice;
    # occurrence 0 keeps the exact pre-existing stream.
    bpm9 = BPMObserver("t9"; x_noise=1.0)
    t9 = TrackingTask((DriftSpec(L=1.0),);
                      hooks=(ScheduledObserver(bpm9), ScheduledObserver(bpm9)))
    execute!(t9, Phase6DRep([0.0], [0.0], [0.0], [0.0], [0.0], [0.0]); turns=1)
    let (turns9, x9, _) = readings(bpm9)
        @test turns9 == [0, 0]
        @test x9[1] != x9[2]
        @test x9[1] ==
              Octopus.octopus_normal(seed_a, method_a, 0, bpm9.rng_id, 0, 1, Float64)
        @test x9[2] ==
              Octopus.octopus_normal(seed_a, method_a, 0, bpm9.rng_id, 1, 1, Float64)
    end

    # T10: the EveryNSteps planner must not enumerate from the schedule start
    # -- its cost was proportional to the ABSOLUTE turn (29.5 ms at 1e8,
    # penalising exactly the chunked long run first_turn serves). Equivalence
    # against the enumerate-and-filter oracle, then a generous cost ceiling.
    oracle(s, turns, first) = begin
        lo = Int(first); hi = lo + Int(turns)
        stop = min(s.stop, hi)
        s.start >= stop ? Int[] :
            [t for t in s.start:s.step:(stop - 1) if lo <= t < hi]
    end
    for start in 0:3, step in 1:4, stop in (0, 1, 5, 17, 100), turns in 0:4,
        first in (0, 1, 3, 7, 50)

        s = EveryNSteps(start, stop, step)
        @test Octopus._scheduled_turns(s, turns, first) == oracle(s, turns, first)
    end
    let s = EveryNSteps(start=0, stop=typemax(Int), step=1)
        Octopus._scheduled_turns(s, 5, 10^8)          # warm up
        @test @elapsed(Octopus._scheduled_turns(s, 5, 10^8)) < 0.005
        @test Octopus._scheduled_turns(s, 5, 10^8) == collect(10^8:(10^8 + 4))
    end

    # T11: rng_id is the one field deciding whether two BPMs share a noise
    # stream, and it must appear in the configuration report.
    let entries = configuration_report(BPMObserver("t11"; x_noise=1.0))
        @test any(e -> e.name === :rng_id, entries)
    end
end

@testset "A crashed execute! still delivers its loss artifacts" begin
    # Audit part 7, T6. The stored turn deliberately does not advance on
    # failure (documented retry semantics), so the retry replays the same
    # absolute window -- which means (a) the loss file must be flushed on the
    # failure path, since a crashed run is exactly when it is wanted, and
    # (b) an observer must not keep the failed window's partial readings, or
    # the retry appends duplicate turn labels and the table is corrupt for
    # every downstream reader.
    path = tempname() * ".h5"
    bpm = BPMObserver("b")
    line = (DriftSpec(L=1.0), ApertureSpec(x_limit=2.0e-3, name="COLL"),
            DriftSpec(L=0.5))
    task = TrackingTask(line;
                        hooks=(ScheduledObserver(bpm),
                               ScheduledAction(FailAtTurnAction(3))),
                        loss_log=path)
    rep = Phase6DRep([1.0e-3, 5.0e-3, 0.0, 0.0], zeros(4),
                     [0.0, 0.0, 1.0e-4, 0.0], zeros(4), zeros(4), zeros(4))
    allow_lost_particles(; enabled=true) do
        @test_throws ErrorException execute!(task, rep; turns=5)
    end
    @test task.next_turn[] == 0                # documented: no advance on failure
    @test isfile(path)                         # T6a: the artifact exists after a crash
    Octopus.HDF5.h5open(path) do f
        @test read(f["aperture_counts"]) == [1]
        @test read(f["summary_dead"]) == 1
    end
    @test readings(bpm)[1] == [0, 1, 2]
    allow_lost_particles(; enabled=true) do
        @test_throws ErrorException execute!(task, rep; turns=5)
    end
    @test readings(bpm)[1] == [0, 1, 2]        # T6b: retry does not duplicate labels
    rm(path; force=true)

    # The discard is a no-op for an ordinary chunked run: two successful
    # chunks still append distinct turns.
    bpm2 = BPMObserver("b2")
    chunked = TrackingTask((DriftSpec(L=1.0),); hooks=(ScheduledObserver(bpm2),))
    r2 = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    execute!(chunked, r2; turns=3)
    execute!(chunked, r2; turns=3)
    @test readings(bpm2)[1] == [0, 1, 2, 3, 4, 5]
end

@testset "Slicing degenerate conventions and the spectral charge tripwire" begin
    # R7 (part 6): a zero-width z distribution used to land in slice 1 on the
    # CPU equal-width/equal-area paths and in slice `ns` everywhere a
    # boundary-comparison assignment ran (the CUDA routes, and the CPU
    # boundary-search methods) -- same beam, different slice, per backend.
    # One convention now: slice 1.
    whichslice(s) = [k for k in 1:length(s.indices) if !isempty(s.indices[k])]
    rep0() = Phase6DRep(zeros(8), zeros(8), zeros(8), zeros(8),
                        fill(1.5e-3, 8), zeros(8))
    for method in (:equal_area, :equal_width, :normal_quantile)
        sl = LongitudinalSlicing(nslices=4, method=method)
        @test whichslice(longitudinal_slices(rep0(), sl)) == [1]
    end
    if CUDA_TESTS_ACTIVE
        for method in (:equal_area, :equal_width)
            sl = LongitudinalSlicing(nslices=4, method=method)
            drep = Phase6DRep((Octopus.CUDA.CuArray(a)
                               for a in coordinate_arrays(rep0()))...)
            @test whichslice(Octopus._cuda_longitudinal_slices(drep, sl)) == [1]
        end
    else
        # The R7 degenerate-slice CUDA convention was the last silent gate in
        # the file's own header count (2026-08-05 audit, U16-6).
        @test_skip "CUDA device not available"
    end

    # R2 (part 6): :equal_count membership is by RANK. For continuous z the
    # reported boundaries and the index sets agree exactly; under ties the tie
    # group splits across slices and a tied particle sits exactly ON its
    # boundary -- documented behaviour, pinned here so the contract is tested
    # rather than assumed.
    sl9 = LongitudinalSlicing(nslices=9, method=:equal_count)
    violations(rep) = begin
        s = longitudinal_slices(rep, sl9)
        bad = Tuple{Int,Int}[]
        for k in 1:length(s.indices), i in s.indices[k]
            lb, rb = s.boundary[k], s.boundary[k + 1]
            inside = k == length(s.indices) ? (lb <= rep.z[i] <= rb) : (lb <= rep.z[i] < rb)
            inside || push!(bad, (k, i))
        end
        (s, bad)
    end
    zc = [2.0e-2 * sin(0.7 * i + 2.0) for i in 1:2000]
    _, bad_c = violations(Phase6DRep(zeros(2000), zeros(2000), zeros(2000),
                                     zeros(2000), zc, zeros(2000)))
    @test isempty(bad_c)
    zq = [round(2.0e-2 * sin(0.7 * i + 2.0); digits=3) for i in 1:2000]
    sq, bad_q = violations(Phase6DRep(zeros(2000), zeros(2000), zeros(2000),
                                      zeros(2000), zq, zeros(2000)))
    @test !isempty(bad_q)                       # ties DO split; that is the contract
    @test all(zq[i] == sq.boundary[k + 1] for (k, i) in bad_q)   # each sits ON its boundary

    # R9 (part 6): the spectral deposit clips silently at the Dirichlet wall,
    # and the box is sized ONCE from pre-collision coordinates -- so a strong
    # enough intra-collision kick pushes later slice-pair deposits out of the
    # box. The tripwire makes that a warning instead of silent charge loss;
    # measured on this exact configuration: 83% of a slice's charge was being
    # dropped with no signal at all.
    strong(n) = begin
        s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
        x = s(1.0e-4, 0.0); x[1] = 8.0e-4
        rep = Phase6DRep(x, s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2),
                         s(1.0e-2, 2.0), s(1.0e-4, 2.5))
        params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
        Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
    end
    sp64 = SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
        grid=(64, 64), slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
    @test_logs (:warn, r"clipped charge at the Dirichlet wall") match_mode = :any collide!(
        sp64, strong(256), strong(256), CPUThreadsBackend)

    # R10 (part 6): the same overflow through :grid_free does not clip -- the
    # odd periodic extension mirrors the source back inside at exactly -1x,
    # silently. The guard turns that into a directed warning.
    gf = SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
        grid=(16, 16), method=:grid_free,
        slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
    @test_logs (:warn, r"grid_free source outside the Dirichlet box") match_mode = :any collide!(
        gf, strong(256), strong(256), CPUThreadsBackend)
end

@testset "Curved frame x transverse field: every routing is a gradient" begin
    # The h != 0 cross-product sweep (docs/todo.md). A straight multipole
    # kick in a curved frame is a gradient iff h*Im f == 0 -- pure normal
    # dipole content only; everything else must route through the curved
    # potential. The 2026-08-03 audit found the routing missing twice
    # (2.5e-3 .. 3.2e-2 of symplecticity); this pins the whole content grid
    # on the only two kinds whose schemas offer both curvature and field
    # (derived, not assumed: no other registered kind carries both), plus the
    # undeclared-h channel through the shared LatticeMagnet compile.
    S6 = zeros(6, 6)
    for (q, p) in ((1, 2), (3, 4), (5, 6))
        S6[q, p] = 1.0
        S6[p, q] = -1.0
    end
    u0 = [1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 1.0e-3, 1.0e-4]
    residual(mapf) = begin
        J = ForwardDiff.jacobian(u -> collect(mapf(u...)), u0)
        maximum(abs, J' * S6 * J - S6)
    end

    # Instrument self-check, and the sweep's negative control: the straight
    # kick fed skew-dipole content at h != 0 is the recorded defect, and the
    # residual must reproduce its analytic magnitude L*h*Ks0 -- measured to
    # 15 digits when this was built.
    let bad = (x, px, y, py, z, pz) ->
            Octopus._lattice_kick((0.0,), (0.05,), 0.05, 1.0, x, px, y, py, z, pz)
        @test isapprox(residual(bad), 2.5e-3; rtol=1.0e-6)
    end

    contents = [NamedTuple(), (kn=(0.02,),), (ks=(0.05,),), (kn=(0.0, 0.6),),
                (ks=(0.0, 0.6),), (kn=(0.0, 0.0, 2.0),), (ks=(0.0, 0.0, 2.0),),
                (kn=(0.0, 0.0, 0.0, 12.0),), (ks=(0.0, 0.0, 0.0, 12.0),),
                (kn=(0.0, 0.6, 1.0), ks=(0.03, 0.2))]
    for kw in contents
        @test residual(compile_runtime(SBendSpec(; L=1.1, h=0.05, b0=0.05, nst=2, kw...))) < 1.0e-12
    end
    for kw in [(nst=1,), (nst=8,), (nst=2, integrator_order=4),
               (nst=2, bend_model=:drift_kick), (nst=2, e1=0.1, e2=0.1),
               (nst=2, bend_fringe=false), (nst=2, fringe=:multipole)]
        @test residual(compile_runtime(SBendSpec(; L=1.1, h=0.05, b0=0.05,
                                                 ks=(0.05, 0.4), kw...))) < 1.0e-12
    end
    @test residual(compile_runtime(SBendSpec(; L=1.1, h=0.05, b0=0.03, nst=2,
                                             ks=(0.05, 0.4)))) < 1.0e-12
    # Solenoid: skew multipoles are spelled kskew there. This grid also
    # regression-covers the coordinate Jacobian itself -- `_sol_log_over_h`
    # used a strict `(::T, ::T)` signature and the curved solenoid was a
    # MethodError under ForwardDiff with Float64 elements until this sweep
    # was built (same strict-signature class as part 7's G1).
    sol_kw(kw) = NamedTuple(k === :ks ? :kskew => v : k => v for (k, v) in pairs(kw))
    for kw in contents
        # The empty content is the pure curved solenoid, which takes the
        # implicit-midpoint path and sits at its 1.1e-9 nst=4 floor -- it is
        # asserted at the right tolerances by the dedicated pair below, not
        # here. The 2026-08-05 audit found this loop asserting 1e-12 on it,
        # which failed (deterministically) every full-suite run since the
        # sweep landed and aborted the suite at this testset.
        isempty(pairs(kw)) && continue
        @test residual(compile_runtime(SolenoidSpec(; L=1.3, ks=1.7, h=0.18,
                                                    nst=4, sol_kw(kw)...))) < 1.0e-12
    end
    # The pure curved solenoid takes the implicit-midpoint path, whose fixed
    # 16-sweep solve has a DOCUMENTED convergence floor at coarse nst
    # (1.1e-9 at nst=4, machine epsilon by nst=16, per the table beside
    # _SOL_MIDPOINT_ITERS) -- convergent with nst, unlike the structural
    # non-gradient this sweep exists to catch, which nst does not remove.
    @test residual(compile_runtime(SolenoidSpec(L=1.3, ks=1.7, h=0.18, nst=4))) < 1.0e-8
    @test residual(compile_runtime(SolenoidSpec(L=1.3, ks=1.7, h=0.18, nst=16))) < 1.0e-12
    # Undeclared h on a raw spec still routes through the shared gate.
    @test residual(compile_runtime(ElementSpec{:quadrupole}(;
        L=0.7, nst=2, kn=(0.0, 1.1), ks=(0.04,), h=0.05))) < 1.0e-12
end

@testset "Straight solenoids differentiate, and curved=false means straight" begin
    # 2026-08-05 audit F17 (U10-1/2/3/4). The straight solenoid's body was
    # complex-typed (`complex(x, y)` has no Dual method) and `_curv_sin` was
    # strict `(::T,::T)` with a coordinate-dependent kappa, so EVERY straight
    # solenoid was a MethodError under a ForwardDiff coordinate Jacobian —
    # invisible to the h≠0 sweep above, which only exercises curved solenoids.
    # The map is now a real-arithmetic transcription, verified bit-identical
    # on floats over a 42-point grid. And `curved=false` stored the RAW h, so
    # the solenoid tracked a silent non-gradient kick (|J'SJ-S| = 2.5e-3)
    # and the magnet kept the curvature its own warning said was ignored
    # (1.6e-7 against a real h=0 track); both runtimes now store the
    # curvature they actually track with.
    S6 = zeros(6, 6)
    for (q, p) in ((1, 2), (3, 4), (5, 6))
        S6[q, p] = 1.0
        S6[p, q] = -1.0
    end
    u0 = [1.0e-3, 1.0e-4, -0.5e-3, 2.0e-4, 1.0e-3, 1.0e-4]
    residual(mapf) = begin
        J = ForwardDiff.jacobian(u -> collect(mapf(u...)), u0)
        maximum(abs, J' * S6 * J - S6)
    end
    # Straight pure solenoid and straight solenoid with multipoles: the
    # Jacobian exists (no MethodError) and the map is symplectic.
    @test residual(compile_runtime(SolenoidSpec(L=1.3, ks=1.7))) < 1.0e-10
    @test residual(compile_runtime(SolenoidSpec(L=1.3, ks=1.7,
                                                kskew=(0.05,), nst=4))) < 1.0e-10
    # A dual PARAMETER through the multipole strengths compiles and tracks
    # (U10-2: the promotion once covered only L, ks, h).
    d_k1 = ForwardDiff.derivative(0.6) do k1
        el = compile_runtime(SolenoidSpec(L=1.3, ks=1.7, kn=(0.0, k1), nst=2))
        el(u0...)[2]
    end
    @test isfinite(d_k1)
    # curved=false with h≠0 warns, stores h=0, and tracks EXACTLY as h=0.
    sol_cf = @test_logs (:warn, r"curved = false") match_mode = :any compile_runtime(
        SolenoidSpec(L=1.3, ks=1.7, h=0.05, kskew=(0.05,), curved=false, nst=4))
    sol_h0 = compile_runtime(SolenoidSpec(L=1.3, ks=1.7, kskew=(0.05,), nst=4))
    @test sol_cf.h == 0.0
    @test sol_cf(u0...) == sol_h0(u0...)
    @test residual(sol_cf) < 1.0e-9
    mag_cf = @test_logs (:warn, r"curved = false") match_mode = :any compile_runtime(
        SBendSpec(L=1.1, h=0.1, b0=0.1, kn=(0.0, 0.4), curved=false, nst=2))
    mag_h0 = compile_runtime(SBendSpec(L=1.1, h=0.0, b0=0.1, kn=(0.0, 0.4), nst=2))
    @test mag_cf(u0...) == mag_h0(u0...)
end

@testset "No method grows a Core.Box outside the argued allowlist" begin
    # The concurrency sweep (docs/todo.md): two of the three 2026-08-03
    # threading defects were one Julia trap -- a name assigned both in a `do`
    # block and its enclosing function is one shared Core.Box across every
    # worker. The sweep is on LOWERED code because a text sweep gave six
    # false positives and missed a real one. Every current box is serial
    # except one, argued below; a NEW box anywhere fails this test and must
    # either be fixed or argued onto the list.
    expr_has_box(x) = x isa GlobalRef ? (x.mod === Core && x.name === :Box) :
                      x isa Expr ? any(expr_has_box, x.args) : false
    clean_name(m) = begin
        s = String(m.name)
        startswith(s, "#") || return s
        parts = split(s, '#'; keepempty=false)
        isempty(parts) ? s : String(parts[1])
    end
    allowed = Set([
        # serial file I/O and initialisation
        ("read_beam_coordinates", "Beam.jl"),
        ("_initialize_moment_file!", "BeamObservers.jl"),
        # serial contract validation helpers
        ("validate", "Contracts.jl"),
        ("_contract_default_initial_rep", "Contracts.jl"),
        # serial constructor (branch-reassigned locals captured by ntuple lambdas)
        ("GaussianStrongBeam", "strong_beam.jl"),
        # one-shot adapter activation; self-recursive local closures
        ("_activate_symbolics_adapter!", "symbolic.jl"),
        # THE one concurrent-closure box, confirmed benign in audit parts 1
        # and 6: the worker closure only READS `luminosity` (through typeof),
        # the write is outside the do block, and the workers are @sync-joined.
        # The natural refactor `luminosity += local_lum` INSIDE the closure
        # would reproduce the _threaded_histogram defect exactly -- which is
        # what this test exists to catch.
        ("_spectral_collide_longitudinal!", "spectral.jl"),
    ])
    offenders = String[]
    nmethods = 0
    seen = Set{Method}()
    for name in names(Octopus; all=true, imported=false)
        isdefined(Octopus, name) || continue
        f = try
            getfield(Octopus, name)
        catch
            continue
        end
        f isa Union{Function,Type} || continue
        f isa Core.Builtin && continue
        ms = try
            methods(f)
        catch
            continue
        end
        for m in ms
            m.module === Octopus || continue
            m in seen && continue
            push!(seen, m)
            nmethods += 1
            ci = try
                Base.uncompressed_ir(m)
            catch
                continue
            end
            ci === nothing && continue
            any(expr_has_box, ci.code) || continue
            file = basename(String(m.file))
            file == "none" && continue          # @generated bodies: compile-time, serial
            (clean_name(m), file) in allowed && continue
            push!(offenders, "$(m.name) @ $(file):$(m.line)")
        end
    end
    @test nmethods > 2000              # the sweep actually swept
    @test isempty(offenders)
    isempty(offenders) || foreach(o -> @info("new Core.Box: " * o), offenders)
end

@testset "CPU solver stack is thread-count invariant" begin
    # Identical inputs must give bit-identical results at every worker
    # count. The original pin ran only BELOW the 4096-particle parallel
    # thresholds (n=1500), so the threaded deposit/moment/kick folds were
    # never inside the pinned envelope — and above them the chunk-ordered
    # reductions moved with the worker count (coordinates ~8e-15, moments to
    # 131,072 ulps; 2026-08-05 audit U5-1/2, U16-3). The reductions now use
    # FIXED chunk grids with the serial/chunked choice made by data size
    # only, so the second block below pins bit-equality at n=15000, above the
    # moment and kick thresholds, for 1/4/8 workers (measured exact, 0 ulp, at
    # zero collide-time cost: 3.06 s vs 3.10 s at n=1e6).
    #
    # "luminosity included" was in that sentence and is not true of every
    # solver: the spectral TRANSVERSE path still folds its luminosity over
    # worker-count-many chunks, and moves by ~1 ulp. It has its own block
    # below with the envelope that actually holds (U18-2). pic, gpic and
    # spectral_l are exact, luminosity included. The first block keeps the original sub-threshold pin;
    # its spectral-luminosity tolerance covers the historical 1-ulp fold-order
    # allowance, which equality also satisfies.
    #
    # This block no longer reaches the THREADED DEPOSIT, and saying so matters
    # more than the coverage it lost. The deposit threshold is now mesh-scaled
    # (U6-2: its fixed cost is grid-sized, so a particle count alone routed
    # small slices on big grids into a path 28x slower), and at these grids
    # that needs ~41k-164k particles per slice — far past what belongs in CI.
    # The deposit's own worker invariance is therefore pinned directly, on the
    # threaded entry point, in the third block below. Routing through collide!
    # at production sizes to reach it would trade minutes of CI for the same
    # assertion.
    mkr(n) = begin
        s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
        z = [2.0e-2 * sin(0.7 * i + 2.0) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
        Phase6DRep(s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9),
                   s(1.0e-5, 1.2), z, s(1.0e-4, 2.5))
    end
    mkb(n) = begin
        rep = mkr(n)
        params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0e-9, npart=n)
        Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
    end
    workers(f, k, rep) = Octopus._with_execution_policy(f,
        Octopus._resolve_execution_policy(CPUThreadsExecutionPolicy(threads=k), rep))
    slc = LongitudinalSlicing(nslices=3, method=:equal_count)
    for (label, solver) in (
            ("pic", PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
                grid=(16, 16), green_cache=:none, slicing=slc)),
            ("gpic", GaussianPICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
                luminosity_scale=1.0, grid=(16, 16), green_cache=:none, slicing=slc)),
            ("spectral_t", SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
                luminosity_scale=1.0, grid=(32, 32), longitudinal_kick=false, slicing=slc)),
            ("spectral_l", SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
                luminosity_scale=1.0, grid=(32, 32), slicing=slc)))
        outs = map((1, 4)) do k
            b1, b2 = mkb(1500), mkb(1500)
            lum = workers(k, b1.rep) do
                collide!(solver, b1, b2, CPUThreadsBackend)
            end
            (lum, map(copy, coordinate_arrays(b1.rep)), map(copy, coordinate_arrays(b2.rep)))
        end
        if startswith(label, "spectral")
            @test isapprox(outs[1][1], outs[2][1]; rtol=8 * eps(Float64))
        else
            @test outs[1][1] == outs[2][1]
        end
        @test all(a == b for (a, b) in zip(outs[1][2], outs[2][2]))
        @test all(a == b for (a, b) in zip(outs[1][3], outs[2][3]))
    end

    # Above every parallel threshold: full bit-equality at 1/4/8 workers.
    for (label, solver) in (
            ("pic", PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
                grid=(16, 16), green_cache=:none, slicing=slc)),
            ("gpic", GaussianPICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
                luminosity_scale=1.0, grid=(16, 16), green_cache=:none, slicing=slc)),
            ("spectral_l", SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
                luminosity_scale=1.0, grid=(32, 32), slicing=slc)))
        # Counts clamped to the pool: the policy refuses workers above
        # Threads.nthreads (measured at the suite's --threads=4 when this
        # block first asked for 8). Any two distinct counts prove the
        # invariance; 1/4/8 was verified out-of-suite on an 8-thread pool.
        counts = unique((1, 2, Threads.nthreads(:default)))
        outs = map(counts) do k
            b1, b2 = mkb(15000), mkb(15000)
            lum = workers(k, b1.rep) do
                collide!(solver, b1, b2, CPUThreadsBackend)
            end
            (lum, map(copy, coordinate_arrays(b1.rep)), map(copy, coordinate_arrays(b2.rep)))
        end
        for other in 2:length(outs)
            @test outs[1][1] == outs[other][1]
            @test all(a == b for (a, b) in zip(outs[1][2], outs[other][2]))
            @test all(a == b for (a, b) in zip(outs[1][3], outs[other][3]))
        end
    end

    # `spectral_t` (transverse-only spectral) was in the sub-threshold block
    # above and silently absent from this one, with nothing in the code or
    # comments recording the omission -- and it is precisely the arm the
    # omission mattered for (2026-08-05_b audit, U18-2). Its COORDINATES are
    # bit-identical across worker counts like everything else, but its
    # luminosity is not: `spectral.jl` still partitions that fold by
    # `_cpu_worker_count()` (the pair-batch reduction near line 1103), unlike
    # the PIC deposit and the moment reduction which use fixed chunk counts.
    #
    # Measured at n=15000: max|dL| = 8.0 at nslices=3 and 16.0 at nslices=15
    # across 1/2/4 workers, i.e. 1.7e-16 and 2.7e-16 relative -- about one ulp,
    # the signature of a chunk-ordered float fold whose chunk count moved.
    #
    # Pinned as a documented envelope rather than dropped: coordinates must be
    # bit-identical, and the luminosity must agree to a few ulp. That makes a
    # real regression (a changed reduction, not a changed fold order) fail here,
    # where the omission made nothing fail at all. Restoring exact equality
    # needs the fixed-chunk-grid treatment applied to the spectral pair-batch
    # reduction; that is a separate, priced change.
    let spec_t = SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
            luminosity_scale=1.0, grid=(32, 32), longitudinal_kick=false, slicing=slc)
        counts = unique((1, 2, Threads.nthreads(:default)))
        outs = map(counts) do k
            b1, b2 = mkb(15000), mkb(15000)
            lum = workers(k, b1.rep) do
                collide!(spec_t, b1, b2, CPUThreadsBackend)
            end
            (lum, map(copy, coordinate_arrays(b1.rep)), map(copy, coordinate_arrays(b2.rep)))
        end
        for other in 2:length(outs)
            @test all(a == b for (a, b) in zip(outs[1][2], outs[other][2]))
            @test all(a == b for (a, b) in zip(outs[1][3], outs[other][3]))
            # A few ulp of the value, not a blanket rtol: 8 ulp at this
            # magnitude is ~6e-16 relative, far below any physical change.
            @test abs(outs[1][1] - outs[other][1]) <= 8 * eps(outs[1][1])
        end
    end

    # The threaded deposit itself, entered directly. Since U6-2 made the
    # deposit threshold mesh-scaled, the collide! blocks above no longer route
    # here at CI-sized inputs, and an unexercised invariance claim is not a
    # claim (Measured Lesson: a check only counts while it executes).
    #
    # The path is chosen by data and mesh only, so the routing decision is
    # asserted to be worker-count-blind as well as the arithmetic: a future
    # `_cpu_worker_count()` creeping back into the predicate fails here.
    let nx = 8, ny = 8,
        # Derived from the threshold, not hardcoded: if the constant moves, this
        # input follows it instead of silently dropping to the serial path.
        n = Octopus._PIC_DEPOSIT_PARTICLES_PER_CELL * nx * ny
        x = [1.0e-4 * sin(0.7i) for i in 1:n]
        y = [1.0e-5 * sin(0.31i) for i in 1:n]
        px = [1.0e-6 * sin(1.1i) for i in 1:n]
        py = [1.0e-7 * sin(0.53i) for i in 1:n]
        x0, y0 = -2.0e-4, -2.0e-5
        hx, hy = 4.0e-4 / (2nx), 4.0e-5 / (2ny)
        counts = unique((1, 2, Threads.nthreads(:default)))
        # Exactly on the threshold, so this input is on the threaded side and
        # one particle fewer is not -- the boundary itself is pinned.
        @test Octopus._pic_deposit_parallel(n, nx, ny)
        @test !Octopus._pic_deposit_parallel(n - 1, nx, ny)
        for method in (:CIC, :TSC)
            grids = map(counts) do k
                ws = Octopus._pic_cpu_workspace(Float64, nx, ny)
                ch = zeros(2nx, 2ny)
                Octopus._with_execution_policy(
                    Octopus.ResolvedCPUExecutionPolicy(k)) do
                    # The routing decision must not see the worker count.
                    @test Octopus._pic_deposit_parallel(n, nx, ny)
                    Octopus._pic_deposit_drifted_threaded!(
                        ch, method, x, px, y, py, 0.0, x0, y0, hx, hy, nx, ny, ws)
                end
                copy(ch)
            end
            for other in 2:length(grids)
                @test grids[1] == grids[other]     # bit-identical, not approx
            end
        end
    end
end

@testset "CUDA equal_area histogram matches the CPU membership rule" begin
    # R8 (part 6): the histogram is now one atomic kernel pass instead of a
    # device broadcast + reduction PER BIN (57.8 ms -> 3.2 ms at n=1e6,
    # ns=15). U2-2 then aligned its membership with the CPU `_slice_bin`
    # (division + clamp): the kernel must land every live finite particle in
    # the bin the CPU `_threaded_histogram` gives it, bit for bit -- the old
    # edge-comparison rule disagreed on ~0.8% of quantized-z samples and
    # dropped rounding orphans the CPU clamps into the extreme bins.
    if CUDA_TESTS_ACTIVE
        oracle(z_h, flags_h, zmin, width, bins) = begin
            counts = zeros(Int, bins)
            for (i, zi) in enumerate(z_h)
                flags_h === nothing || flags_h[i] || continue
                b = Octopus._slice_bin(zi, zmin, width, bins)
                b == 0 || (counts[b] += 1)
            end
            counts
        end
        kernel_counts(z_d, flags_d, zmin, width, bins) = begin
            counts_d = Octopus.CUDA.zeros(Int32, bins)
            threads = 256
            Octopus.CUDA.@cuda threads=threads blocks=cld(length(z_d), threads) Octopus._cuda_equal_area_histogram_kernel!(
                counts_d, z_d, flags_d, zmin, width, bins)
            Int.(Array(counts_d))
        end
        for (n, bins, quantize) in ((2000, 45, true), (2000, 45, false),
                                    (777, 10, true), (1000, 7, false))
            z_h = [2.0e-2 * sin(0.7 * i + 2.0) + 1.0e-3 * sin(3.1 * i) for i in 1:n]
            quantize && (z_h = round.(z_h; digits=3))
            flags_h = [i % 5 != 0 for i in 1:n]         # some dead
            zmin, zmax = extrema(z_h[flags_h])
            width = (zmax - zmin) / bins
            z_d = Octopus.CUDA.CuArray(z_h)
            flags_d = Octopus.CUDA.CuArray(flags_h)
            @test kernel_counts(z_d, flags_d, zmin, width, bins) ==
                  oracle(z_h, flags_h, zmin, width, bins)
            zmin2, zmax2 = extrema(z_h)
            width2 = (zmax2 - zmin2) / bins
            @test kernel_counts(z_d, nothing, zmin2, width2, bins) ==
                  oracle(z_h, nothing, zmin2, width2, bins)
        end
    else
        @test_skip "CUDA device not available"
    end
end

@testset "Spectral solve/eval split is exact" begin
    # R12 (part 6): the transverse path now solves each source once and
    # evaluates the stored mesh per field slice. This pins the seam: a stored
    # mesh must evaluate bit-identically to the monolithic solve-and-eval.
    # (At the change itself, full transverse collides were captured pre- and
    # post-refactor and diffed bit-identical at 4 threads, ns=8.)
    mkc(scale, phase, n) = [scale * sin(0.7 * i + phase) for i in 1:n]
    sx, sy = mkc(1.0e-4, 0.0, 500), mkc(1.0e-4, 0.9, 500)
    fx, fy = mkc(8.0e-5, 0.4, 300), mkc(8.0e-5, 1.3, 300)
    L = 2.0e-4
    ws1 = Octopus._SpectralGridWS(32, 32)
    ws2 = Octopus._SpectralGridWS(32, 32)
    Ex0, Ey0 = Octopus._spectral_field_grid!(ws1, sx, sy, fx, fy, L, L)
    Octopus._spectral_field_grid_solve!(ws2, sx, sy, L, L)
    Ex1, Ey1 = Octopus._spectral_field_grid_eval(copy(ws2.Exg), copy(ws2.Eyg),
                                                 32, 32, fx, fy, L, L)
    @test Ex1 == Ex0
    @test Ey1 == Ey0
end

@testset "Every example script runs against the current interface" begin
    # Examples are the precedents agents and users imitate (AGENTS.md), and
    # none was executed by this suite -- which is how a refactor that renamed
    # an internal broke examples/knob_control.jl silently through six green
    # suite runs. Each script runs in a subprocess at its small config
    # defaults (the weak-strong pair at 2 turns / 10k macroparticles;
    # knob_control at 1 turn / 4 particles; strong-strong at 200/beam —
    # all CPU policy), so this also
    # enforces "update examples when public APIs change". Costs one package
    # load per script; exit 0 is the assertion, with the output tail
    # surfaced on failure.
    root = dirname(@__DIR__)
    scripts = vcat(
        [joinpath(root, "examples", f) for f in
         ("knob_control.jl", "weak_strong_tracking.jl", "strong_strong_tracking.jl")],
        [joinpath(root, "test", "examples", f) for f in
         ("weak_strong_tracking.jl", "strong_strong_tracking.jl")])
    for script in scripts
        buf = IOBuffer()
        p = run(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$(root) $(script)`,
                         stdout=buf, stderr=buf); wait=false)
        wait(p)
        ok = success(p)
        if !ok
            text = String(take!(buf))
            @info "example script failed" script last(text, 2000)
        end
        @test ok
    end
    # The clean examples write into repo-root result/ by their documented
    # config (gitignored, but every Pkg.test left the artifacts behind;
    # 2026-08-05 audit, U18-3). Remove exactly the files these runs create,
    # in both output directories, and leave anything else in result/ alone.
    for dir in (joinpath(root, "result"), joinpath(root, "test", "result")),
        name in ("weak_strong.lum", "weak_strong_moments.h5",
                 "pic_hcc.lum", "pic_hcc.ele.h5", "pic_hcc.pro.h5")

        rm(joinpath(dir, name); force=true)
    end
end

@testset "Every export is documented" begin
    # 76 of 335 exports lacked documentation when the 2026-08-05 audit swept
    # them (U13-5); the sweep also found ten exports whose complete
    # docstrings had silently DETACHED because a comment line sat between
    # the docstring and the definition — on this Julia that attaches the
    # docs to nothing, with no warning. This keeps both classes closed: a
    # new undocumented export and a docstring detached by a later comment
    # both land here by name.
    undocumented = [n for n in names(Octopus)
                    if n !== :Octopus && occursin("No documentation found",
                        string(Base.Docs.doc(Base.Docs.Binding(Octopus, n))))]
    @test isempty(undocumented)
end

@testset "The module precompiles without overwriting its own methods" begin
    # Part 6 §8.7: a same-signature method silently overwrote another, PASSED
    # the full suite (both methods behaved identically), and was caught only
    # by accident when an unrelated verification happened to load the package
    # in a fresh process. This guard makes that check deliberate. Two
    # subtleties bought by measurement: a plain runtime `include` is SILENT
    # about overwrites on this Julia, so the guard must force an actual
    # precompile (`Base.compilecache` is unconditional); and the driver can
    # exit 0 even when the worker reports the collision, so the assertion is
    # on the message, not the exit code. Costs one full precompile (~1 min).
    prog = "Base.compilecache(Base.identify_package(\"Octopus\"))"
    err = IOBuffer()
    p = run(pipeline(`$(Base.julia_cmd()) --startup-file=no --project=$(dirname(@__DIR__)) -e $prog`,
                     stderr=err, stdout=devnull); wait=false)
    wait(p)
    text = String(take!(err))
    @test success(p)
    @test !occursin("Method overwriting is not permitted", text)
    @test !occursin(r"Method definition .* overwritten", text)
end

@testset "Metadata queries and the validator check declarations, not themselves" begin
    # Audit part 7, K2/K3/K5/K6/K8.

    # K2: the three named-strength thin constructors build bit-identical
    # runtimes to the PTC-validated ThinMultipoleSpec spellings, which is what
    # justifies their PTCConsistencyContract declaration transitively -- the
    # PTC table exercises thin_multipole, and these are the same runtime.
    same(x, y) = typeof(x) == typeof(y) &&
        all(getfield(x, f) == getfield(y, f) for f in fieldnames(typeof(x)))
    let a = 0.037
        @test same(compile_runtime(ThinDipoleSpec(k0l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(a,))))
        @test same(compile_runtime(ThinDipoleSpec(k0sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(a,))))
        @test same(compile_runtime(ThinQuadrupoleSpec(k1l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(0.0, a))))
        @test same(compile_runtime(ThinQuadrupoleSpec(k1sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(0.0, a))))
        @test same(compile_runtime(ThinSextupoleSpec(k2l=a)),
                   compile_runtime(ThinMultipoleSpec(knl=(0.0, 0.0, a))))
        @test same(compile_runtime(ThinSextupoleSpec(k2sl=a)),
                   compile_runtime(ThinMultipoleSpec(ksl=(0.0, 0.0, a))))
    end

    # K5: list-returning queries hand out copies; mutating one must not
    # corrupt the registry.
    let c = required_contracts(ElementSpec{:sbend})
        push!(c, Int64)
        @test !(Int64 in required_contracts(ElementSpec{:sbend}))
        @test validate_element_metadata().passed
    end

    # K8: a line has no tracking method of its own; an explicit request is
    # rejected rather than silently discarded.
    let line = BeamLine("L", DriftSpec(L=1.0))
        @test compile_runtime(line) isa Octopus.CompositeLine
        @test_throws ArgumentError compile_runtime(line, Symplectic6DMap())
    end

    # K3/K6: probe metas registered temporarily, removed afterwards so the
    # snapshot test still sees only the real registry.
    try
        # K6: friendly_constructor = nothing is permitted metadata and must
        # be reported, not crash snapshot generation.
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:k6_probe, spec_type=ElementSpec{:k6_probe},
            friendly_constructor=nothing,
            example=ElementSpec{:k6_probe}(Dict{Symbol,Any}())))
        @test occursin("(no friendly constructor)", registry_snapshot_markdown())

        # K3: the injected-defect scenario that used to validate clean -- a
        # meta whose contract is not a contract, whose analysis is not an
        # analysis, and whose example cannot compile -- must now FAIL.
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:k3_liar, spec_type=ElementSpec{:k3_liar},
            tracking_methods=[Symplectic6DMap], runtime_type=Octopus.LatticeMagnet,
            contracts=[Int64], analyses=[String],
            example=ElementSpec{:k3_liar}(Dict{Symbol,Any}())))
        r = validate_element_metadata()
        @test !r.passed
        @test any(e -> occursin("k3_liar", e) && occursin("not an AbstractContract", e), r.errors)
        @test any(e -> occursin("k3_liar", e) && occursin("not an AbstractAnalysis", e), r.errors)
        @test any(e -> occursin("k3_liar", e) && occursin("does not compile", e), r.errors)
    finally
        for k in (:k6_probe, :k3_liar)
            delete!(Octopus.ELEMENT_META_BY_KIND, k)
            T = ElementSpec{k}
            delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, T)
            filter!(t -> t !== T, Octopus.REGISTERED_ELEMENT_SPECS)
        end
    end
    @test validate_element_metadata().passed      # registry restored
end

@testset "StrongStrongTask luminosity_append continues one file" begin
    # Companion to MomentObserver append: with the default the .lum file is
    # rewritten per execute!; with luminosity_append=true it is continued,
    # replayed windows drop their stale rows, and a mismatched header is
    # refused. Together they make the injection swap-out workflow (a new
    # beam passed to the same task) produce continuous single files with no
    # driver-side stitching.
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(300, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
    end
    beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
    L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                      alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
    ip = StrongStrongCollision(:ip)
    lines() = ((ip, L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))),
               (ip, L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))))
    lum_turns(path) = [parse(Int, first(split(l))) for l in readlines(path)[2:end]]

    # default: replaced per execute! (historical behaviour, pinned)
    p1 = tempname() * ".lum"
    l1, l2 = lines()
    t1 = StrongStrongTask(l1, l2; luminosity_path=p1)
    b1, b2 = beams(); execute!(t1, b1, b2; turns=3)
    b1, b2 = beams(); execute!(t1, b1, b2; turns=3)
    @test lum_turns(p1) == [3, 4, 5]

    # append: continued across execute! calls and across a beam swap
    p2 = tempname() * ".lum"
    t2 = StrongStrongTask(l1, l2; luminosity_path=p2, luminosity_append=true)
    b1, b2 = beams(); execute!(t2, b1, b2; turns=3)
    b1new, b2same = beams(); execute!(t2, b1new, b2same; turns=4)
    @test lum_turns(p2) == collect(0:6)
    @test count(l -> startswith(l, "turn"), readlines(p2)) == 1     # one header

    # rewind idempotence: replaying from turn 3 drops the stale rows
    b1, b2 = beams(); execute!(t2, b1, b2; turns=2, start_turn=3)
    @test lum_turns(p2) == collect(0:4)

    # a mismatched header is refused, not silently mixed
    p3 = tempname() * ".lum"
    open(p3, "w") do io
        println(io, "turn\tother_ip")
        println(io, "0\t1.0")
    end
    t3 = StrongStrongTask(l1, l2; luminosity_path=p3, luminosity_append=true)
    b1, b2 = beams()
    @test_throws ArgumentError execute!(t3, b1, b2; turns=1)

    foreach(p -> rm(p; force=true), (p1, p2, p3))
end

@testset "Mixed-IP schedule rows drop loudly; solver equality is by configuration" begin
    # Two U4 observations (2026-08-05 audit §7). (1) A .lum row must carry
    # one value per collision column, and NaN already means "evaluated and
    # failed", so a turn where per-IP luminosity schedules disagree cannot
    # be written without corrupting one meaning or the other — the row is
    # dropped whole, and that loss is now loud. (2) _collision_solver
    # compared the two lines' solvers by identity, refusing structurally
    # identical objects built independently; solvers are immutable
    # configuration records, so equality is by type + resolved configuration.
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(300, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
    end
    beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
    L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                      alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
    l6a = L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069))
    l6b = L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01))
    mkpic(; kw...) = PICPoissonSolver(; kbb1=1.0e-6, kbb2=1.0e-6,
        luminosity_scale=1.0, grid=(16, 16),
        slicing=LongitudinalSlicing(nslices=2, method=:equal_count), kw...)

    # (2) same configuration, distinct objects: accepted (threw
    # "different Poisson solver objects" before); a genuinely different
    # configuration still throws.
    t_eq = StrongStrongTask(
        (StrongStrongCollision(:ip; poisson_solver=mkpic()), l6a),
        (StrongStrongCollision(:ip; poisson_solver=mkpic()), l6b))
    b1, b2 = beams()
    @test (execute!(t_eq, b1, b2; turns=1); true)
    t_ne = StrongStrongTask(
        (StrongStrongCollision(:ip; poisson_solver=mkpic()), l6a),
        (StrongStrongCollision(:ip; poisson_solver=mkpic(grid=(24, 24))), l6b))
    b1, b2 = beams()
    @test_throws ArgumentError execute!(t_ne, b1, b2; turns=1)

    # (1) IP2 evaluates luminosity only at turn 0: turn 0 writes a complete
    # row, turn 1 is partial — dropped whole, loudly, and the file carries
    # exactly the complete rows.
    p = tempname() * ".lum"
    ip1 = StrongStrongCollision(:ip1; poisson_solver=mkpic())
    ip2 = StrongStrongCollision(:ip2;
        poisson_solver=mkpic(luminosity_schedule=AtTurns([0])))
    t = StrongStrongTask((ip1, l6a, ip2), (ip1, l6b, ip2); luminosity_path=p)
    b1, b2 = beams()
    @test_logs (:warn, r"luminosity row dropped") match_mode = :any execute!(
        t, b1, b2; turns=2)
    @test [parse(Int, first(split(l))) for l in readlines(p)[2:end]] == [0]
    rm(p; force=true)
end

@testset "MomentObserver append mode continues one table across executions" begin
    # append=false is the documented replace-per-execution behaviour (pinned
    # first); append=true creates a chunked/extendible HDF5 table whose
    # continuation state lives in the FILE, so chunked runs, injection
    # swap-outs, path-sharing tasks, and process restarts all produce one
    # table with continuous absolute turns. Replayed windows drop their stale
    # rows (the BPM idempotence rule), and a replace-mode file refuses to be
    # continued rather than corrupt.
    turns_in(path) = Octopus.HDF5.h5open(path) do f
        n = Int(read(f["record_count"])[1])
        Int.(f["data"][1:n, 1])
    end
    mk1() = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    dline = (DriftSpec(L=1.0),)

    p1 = tempname() * ".h5"
    t1 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p1; capacity=2)),))
    execute!(t1, mk1(); turns=3)
    execute!(t1, mk1(); turns=3)
    @test turns_in(p1) == [3, 4, 5]                    # replace default, as documented

    p2 = tempname() * ".h5"
    obs = MomentObserver(p2; capacity=2, append=true)
    t2 = TrackingTask(dline; hooks=(ScheduledObserver(obs),))
    execute!(t2, mk1(); turns=3)
    execute!(t2, mk1(); turns=3)
    @test turns_in(p2) == collect(0:5)                 # one file, contiguous

    obs_restart = MomentObserver(p2; capacity=2, append=true)
    t3 = TrackingTask(dline; hooks=(ScheduledObserver(obs_restart),))
    execute!(t3, mk1(); turns=2, start_turn=6)
    @test turns_in(p2) == collect(0:7)                 # fresh object, same file: restart works

    p3 = tempname() * ".h5"
    obs3 = MomentObserver(p3; capacity=1, append=true)
    t4 = TrackingTask(dline; hooks=(ScheduledObserver(obs3),
                                    ScheduledAction(FailAtTurnAction(3))))
    @test_throws ErrorException execute!(t4, mk1(); turns=5)
    @test turns_in(p3) == [0, 1, 2]
    t5 = TrackingTask(dline; hooks=(ScheduledObserver(obs3),))
    execute!(t5, mk1(); turns=5)
    @test turns_in(p3) == collect(0:4)                 # retry replays without duplicates

    p4 = tempname() * ".h5"
    t6 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p4; capacity=2)),))
    execute!(t6, mk1(); turns=2)
    t7 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p4; capacity=2, append=true)),))
    @test_throws ArgumentError execute!(t7, mk1(); turns=2)   # fixed-size file refused

    t8 = TrackingTask(dline; hooks=(ScheduledObserver(
        MomentObserver(p2; capacity=2, append=true, orders=1:1)),))
    @test_throws ArgumentError execute!(t8, mk1(); turns=2)   # column mismatch refused

    foreach(p -> rm(p; force=true), (p1, p2, p3, p4))
end

@testset "Nested lines have length, reflection keeps state, folded sugar is rejected everywhere" begin
    # 2026-08-05 audit open-queue U11-1/2/3/4/8. An own-state sub-line
    # (cryostat) counted as ZERO length in every arc-length walker;
    # reverse() rebuilt positionally and dropped the line's own state; the
    # folded-strength override guard missed every thin kind; the same sugar
    # was assignable (stored-never-read) at spec level; and an aperture
    # inside a kept-whole line silently vanished from loss accounting.
    cryo = BeamLine("CRYO", QuadrupoleSpec(L=0.4, k1=1.0, nst=2),
                    DriftSpec(L=1.0); x_offset=2.0e-4)
    arc = BeamLine("ARC", cryo, DriftSpec(L=1.0))
    @test s_positions(arc) == [0.0, 1.4]
    @test Octopus.total_length(arc) == 2.4
    @test Octopus._aperture_s_positions(
        (cryo, DriftSpec(L=1.0), ApertureSpec(x_limit=1.0e-3, name="END"))) == [2.4]

    rev = reverse(cryo)
    @test getparam(rev, :x_offset, nothing) == 2.0e-4
    @test getparam(reverse(rev), :x_offset, nothing) == 2.0e-4

    # 2026-08-05_b audit, U15-3: the U11-2 fix above stopped reverse() from
    # dropping the line's own state, but did it by re-listing the SAME
    # LineEntry objects -- so the reflected line shared each placement's
    # `overrides` Dict and `path` Vector with its source. Measured:
    # `rev[1] === cryo[2]`, and `rev[1].k1 = 9.9` set
    # `getparam(cryo[2], :k1) == 9.9`. That contradicts the composition model,
    # which requires per-occurrence error parameters not to share
    # (theory/beam_line_composition §7b). Placements are copied now; the SPEC
    # is still shared, which is correct -- two placements of one magnet are one
    # magnet -- and only the per-placement mutable state is duplicated.
    ri, ci = line_entries(rev), line_entries(cryo)
    @test ri[1] !== ci[2]
    @test getfield(ri[1], :overrides) !== getfield(ci[2], :overrides)
    @test getfield(ri[1], :path) !== getfield(ci[2], :path)
    @test getfield(ri[1], :spec) === getfield(ci[2], :spec)   # order still reversed
    ri[1].k1 = 9.9
    @test getparam(ri[1], :k1) == 9.9
    @test getparam(ci[2], :k1, nothing) === nothing            # no write-through

    tq = ThinQuadrupoleSpec(k1l=0.05)
    entry = line_entries(BeamLine("L", tq, DriftSpec(L=1.0)))[1]
    @test_throws ArgumentError entry.k1l = 999.0
    q = QuadrupoleSpec(L=0.3, k1=1.2, nst=2)
    @test_throws ArgumentError q.k1 = 999.0

    # 2026-08-05_b audit, U15-7: the SIXTH fold site. `SolenoidSpec` folds
    # `_MULTIPOLE_NAMED` too, and was missing from `_FOLDED_NAMED_STRENGTHS`
    # one commit after the thin kinds were added for the identical reason, so
    # `entry.k1 = 999.0` on a solenoid placement was accepted, reported by
    # getparam, and never read (compile_runtime kept kn = (0.0, 0.5)).
    sol = SolenoidSpec(L=1.0, ks=0.3, k1=0.5)
    @test !haskey(getfield(sol, :params), :k1)          # it really does fold
    sol_entry = line_entries(BeamLine("S", sol))[1]
    @test_throws ArgumentError sol_entry.k1 = 999.0
    # The message must name `kn`, NOT `ks`: on a solenoid `ks` is the solenoid
    # strength, so the default (:kn, :ks) advice would tell the user to
    # overwrite the element's defining parameter.
    sol_msg = try
        sol_entry.k1 = 999.0
        ""
    catch err
        sprint(showerror, err)
    end
    @test occursin("kn", sol_msg)
    @test !occursin("Assign `ks`", sol_msg)

    hidden = BeamLine("CRYO2", ApertureSpec(x_limit=1.0e-3, name="HIDDEN"),
                      DriftSpec(L=0.5); x_offset=1.0e-4)
    @test_logs (:warn, r"outside loss accounting") match_mode = :any TrackingTask(
        (hidden, DriftSpec(L=1.0)))
    @test_logs TrackingTask((ApertureSpec(x_limit=1.0e-3, name="OPEN"),
                             DriftSpec(L=1.0)))
end

@testset "Unknown spec keys warn, placement keys bind, set_param! bumps the epoch" begin
    # 2026-08-05 audit open-queue U3-10/U13-1/U13-2. Every friendly
    # constructor documents open keyword storage, so unknown keys stay LEGAL
    # — but a typo of a physics parameter looked identical and tracked
    # silently (an out-of-schema e1=0.2 on a quadrupole shifts tracking by
    # 7.7e-7); construction now warns once naming the keys. The placement
    # keys compile_runtime consumes for EVERY kind (offsets, pitches, tilt,
    # ref_tilt, misalign_convention) are exempt and are now accepted by the
    # documented `spec.key = value` binding path, which used to reject them
    # on 17 of 30 kinds while compiling them happily. set_param! is the
    # deliberate-metadata door that bumps the recompile epoch the raw
    # params-Dict write skips.
    @test_logs (:warn, r"unknown parameter") match_mode = :any QuadrupoleSpec(
        L=0.3, k1=1.2, this_keyword_does_not_exist=1.0)
    # The offending key travels in the structured kwargs, which @test_logs
    # regexes do not inspect — match the message and check the kwarg below.
    @test_logs (:warn, r"unknown parameter") match_mode = :any ElementSpec{:quadrupole}(; bogus=2.0)
    @test_logs DriftSpec(L=0.5, x_offset=1.0e-3)          # placement: silent
    d = DriftSpec(L=0.5)
    d.x_offset = 1.0e-3
    @test compile_runtime(d) isa Octopus.MisalignedElement
    e0 = Octopus._spec_epoch()
    set_param!(d, :my_note, "hello")
    @test Octopus._spec_epoch() == e0 + 1
    @test d.params[:my_note] == "hello"
end

@testset "Contract coverage guards: declared kinds, solver tree, broken baselines, unrun contracts" begin
    # 2026-08-05 audit open-queue items U3-3/4/6/7. The symplecticity case
    # list now carries the solenoid (the one kind that DECLARES the
    # contract) and a declaration↔case tripwire; the configuration-metadata
    # validator derives solver/observer completeness from the type trees;
    # the effectiveness contract fails a probe-less solver; a throwing
    # baseline is a reported failure, not a silent skip; and the contracts
    # nothing used to execute run here.
    r = validate(SymplecticityContract())
    @test r.passed
    @test r.metrics[:kinds_declaring_without_case] == 0
    @test haskey(r.metrics, :Solenoid_residual)
    @test haskey(r.metrics, :SolenoidCurvedMultipole_residual)

    # Tripwire control: a temporarily registered kind declaring the contract
    # with an uncovered runtime type must FAIL the contract by name.
    try
        Octopus.register_element_meta!(Octopus.ElementMeta(;
            kind=:symp_liar, spec_type=ElementSpec{:symp_liar},
            contracts=[SymplecticityContract], runtime_type=Base.RefValue))
        rl = validate(SymplecticityContract())
        @test !rl.passed
        @test occursin("symp_liar", rl.message)
    finally
        delete!(Octopus.ELEMENT_META_BY_KIND, :symp_liar)
        delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, ElementSpec{:symp_liar})
        filter!(t -> t !== ElementSpec{:symp_liar}, Octopus.REGISTERED_ELEMENT_SPECS)
    end
    @test validate(SymplecticityContract()).passed        # registry restored

    # Broken-baseline control (U3-7): a probe whose baseline throws must fail
    # the parameter contract naming the kind, not vanish into the skip count.
    let probes = copy(Octopus.DEFAULT_ELEMENT_PARAM_PROBES)
        probes[:quadrupole] = (L="not a length",)
        rb = validate(ElementParameterEffectivenessContract(probes=probes))
        @test rb.status === :failed
        @test occursin("quadrupole", rb.message)
        @test rb.metrics[:broken_kinds] == 1
    end

    # Probe-less-solver control (U3-4 sibling): the sweep must refuse to run
    # with a solver missing from its probe table.
    let probes = copy(Octopus._default_solver_option_probes())
        delete!(probes, :SpectralPoissonSolver)
        rs = validate(SolverOptionEffectivenessContract(probes=probes))
        @test rs.status === :failed
        @test occursin("SpectralPoissonSolver", rs.message)
    end

    # U3-6/U21-13: these contracts were executed by no test and no CI.
    rp = validate(PublicConfigurationEffectivenessContract())
    rp.status === :passed ||
        @info "public-configuration contract result" rp.status rp.message rp.metrics
    @test rp.status === :passed || (rp.status === :skipped && !CUDA_TESTS_ACTIVE)
    if CUDA_TESTS_ACTIVE
        rpic = validate(StrongStrongPICBackendConsistencyContract())
        @test rpic.passed
        # `passed` alone did not mean the per-pair luminosity trace was
        # compared: that comparison was gated on `batch_mode == :wavefront` and,
        # when skipped, still reported success having compared nothing
        # (2026-08-05_b audit, U1-1). The count is now asserted, so a contract
        # that certifies backend equivalence while comparing an empty set fails
        # here instead of passing quietly.
        @test rpic.metrics[:slice_pair_luminosity_records_compared] > 0
        @test rpic.metrics[:slice_pair_luminosity_records_compared] ==
              rpic.metrics[:slice_pair_luminosity_cpu_records]
        @test validate(StrongStrongGaussianBackendConsistencyContract()).passed
    else
        @test_skip "CUDA device not available"
    end
end

@testset "The elliptical strong-beam kick differentiates" begin
    # 2026-08-05 audit open-queue U7-1: the η≠0 Bassetti-Erskine kick threw
    # under ForwardDiff — the near-round precision calibration rejected dual
    # number types outright, and the exact CPU Faddeeva route had no dual
    # method. The OctopusForwardDiffExt rules (shared verbatim with script
    # mode) supply the holomorphic Faddeeva derivative w′(z) = −2zw(z) + 2i/√π
    # and the calibration pass-through. Correctness is pinned by the
    # symplecticity of the dual-computed Jacobian, which needs every entry
    # jointly right (central-difference cross-check at build: 6.8e-5, the FD
    # floor); pre-fix this testset errors instead of failing a tolerance.
    el = compile_runtime(ThinStrongBeamSpec{Float64}(kbb=1.0e-4, beta=(1.0, 1.0),
                                                     sigma=(106.0e-6, 9.5e-6)))
    u0 = [0.8e-4, 1.0e-5, 0.4e-4, -2.0e-5, 1.0e-3, 1.0e-4]
    J = ForwardDiff.jacobian(u -> collect(el(u...)), u0)
    S6 = zeros(6, 6)
    for (q, p) in ((1, 2), (3, 4), (5, 6))
        S6[q, p] = 1.0
        S6[p, q] = -1.0
    end
    @test maximum(abs, J' * S6 * J - S6) < 1.0e-10
end

@testset "Every continuing observer drops its replayed window" begin
    # 2026-08-05 audit open-queue U6-2: only MomentObserver and the task-level
    # .lum path followed the drop-at-first_turn idempotence rule; the
    # Luminosity, JLD2, binary-moment, and coordinate-snapshot observers
    # duplicated turn labels on a crashed-execute! retry or an explicit rewind
    # (measured [0,1,2,0,1,2,3,4,5]). All four now discard rows/records at or
    # beyond the incoming window's first turn; snapshots use the observer's
    # (turn → byte offset) map, since their record format carries no turn
    # label.
    mk1() = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    dline = (DriftSpec(L=1.0),)

    p1 = tempname() * ".tsv"
    t1 = TrackingTask(dline; hooks=(ScheduledObserver(LuminosityObserver(p1)),))
    execute!(t1, mk1(); turns=3)
    execute!(t1, mk1(); turns=4, start_turn=1)
    @test [parse(Int, first(split(l, '\t'))) for l in readlines(p1)] == collect(0:4)

    p2 = tempname() * ".jld2"
    t2 = TrackingTask(dline; hooks=(ScheduledObserver(JLD2BeamMomentObserver(p2; capacity=1)),))
    execute!(t2, mk1(); turns=3)
    execute!(t2, mk1(); turns=4, start_turn=1)
    jturns = Octopus.JLD2.jldopen(p2, "r") do f
        Int.(f["data"][:, 1])
    end
    @test jturns == collect(0:4)

    p3 = tempname() * ".dat"
    t3 = TrackingTask(dline; hooks=(ScheduledObserver(BeamMomentObserver(p3; capacity=1)),))
    execute!(t3, mk1(); turns=3)
    execute!(t3, mk1(); turns=4, start_turn=1)
    bturns = open(p3, "r") do io
        n = Int(read(io, Int32))
        fl = Int(read(io, Int32))
        fmt = String(read(io, fl))
        ncols = count(==(','), fmt) + 1
        [(seek(io, 8 + fl + (i - 1) * ncols * 8); Int(read(io, Float64))) for i in 1:n]
    end
    @test bturns == collect(0:4)

    p4 = tempname() * ".dat"
    t4 = TrackingTask(dline; hooks=(ScheduledObserver(CoordinateSnapshotObserver(p4; append=false)),))
    execute!(t4, mk1(); turns=3)
    execute!(t4, mk1(); turns=2, start_turn=1)
    nrec = open(p4, "r") do io
        c = 0
        while !eof(io)
            n = Int(read(io, UInt32))
            skip(io, 6 * n * 8)
            c += 1
        end
        c
    end
    @test nrec == 3

    foreach(p -> rm(p; force=true), (p1, p2, p3, p4))
end

@testset "Philox4x32-10 matches the Random123 known-answer vectors" begin
    # 2026-08-05 audit (U15-1/U19-5): the RNG validation script measures only
    # moments and correlations, and PASSED a Philox with the Weyl key bump
    # removed and a 3-round variant. These are the upstream Random123
    # kat_vectors for philox4x32-10, driven exactly as counter_philox4x32
    # drives the round loop; they pin the implementation, not its statistics.
    philox10(c0, c1, c2, c3, k0, k1) = begin
        for _ in 1:Octopus.PHILOX4X32_ROUNDS
            c0, c1, c2, c3 = Octopus._philox4x32_round(c0, c1, c2, c3, k0, k1)
            k0 += Octopus.PHILOX4X32_W0
            k1 += Octopus.PHILOX4X32_W1
        end
        (c0, c1, c2, c3)
    end
    @test Octopus.PHILOX4X32_ROUNDS == 10
    @test philox10(0x00000000, 0x00000000, 0x00000000, 0x00000000,
                   0x00000000, 0x00000000) ==
          (0x6627e8d5, 0xe169c58d, 0xbc57ac4c, 0x9b00dbd8)
    @test philox10(0xffffffff, 0xffffffff, 0xffffffff, 0xffffffff,
                   0xffffffff, 0xffffffff) ==
          (0x408f276d, 0x41c83b0e, 0xa20bc7c6, 0x6d5451fd)
    @test philox10(0x243f6a88, 0x85a308d3, 0x13198a2e, 0x03707344,
                   0xa4093822, 0x299f31d0) ==
          (0xd16cfe09, 0x94fdcceb, 0x5001e420, 0x24126ea1)
end

@testset "Wrapped stochastic elements keep their context, shared streams warn, unbound apertures cannot corrupt" begin
    # 2026-08-05 audit F13/F14/F15. F13: MisalignedElement/RefTilted/
    # CompositeLine defined no context-aware call, so the generic
    # AbstractTrackOp fallback dropped ctx and a wrapped LumpedRad fell back
    # to its stateful contextless RNG — measured |dx| = 1.4e-4 between two
    # identical executions. F14: LumpedRadSpec auto-assigns one rng_id per
    # spec OBJECT, so placing one spec twice draws identical noise at both
    # placements (two kicks measured exactly 2x one; variance 4x not 2x) —
    # now warned at task construction. F15: a loss_record bump with an
    # unbound element_id=0 was a silent @inbounds out-of-bounds write.
    rad = LumpedRadSpec(
        damping_turns=(20.0, 25.0, 30.0),
        beta=(0.7, 0.9, 1.1),
        alpha=(0.2, -0.1, 0.05),
        sigma=(1.2e-3, 0.8e-3, 2.0e-3),
        rng_id=0x77,
        x_offset=1.0e-4)
    mk() = Phase6DRep([1.0e-3], [1.0e-4], [-0.5e-3], [2.0e-4], [1.0e-3], [1.0e-4])
    run_once() = begin
        set_global_rng!(seed=99, method=:philox)
        rep = mk()
        execute!(TrackingTask((rad,)), rep; turns=3)
        collect(coordinate_arrays(rep)[1])
    end
    @test compile_runtime(rad) isa Octopus.MisalignedElement
    @test run_once() == run_once()          # F13: bit-repeatable through the wrapper

    plain = LumpedRadSpec(damping_turns=(20.0, 25.0, 30.0), beta=(0.7, 0.9, 1.1),
                          alpha=(0.2, -0.1, 0.05), sigma=(1.2e-3, 0.8e-3, 2.0e-3),
                          rng_id=0x78)
    @test_logs (:warn, r"share an rng_id") match_mode = :any TrackingTask(
        (plain, DriftSpec(L=1.0), plain))   # F14: duplicate placement warns
    @test_logs TrackingTask((plain, DriftSpec(L=1.0)))  # single placement silent

    # F15: an unbound (element_id=0) recording aperture kills the particle but
    # leaves counts untouched and the loss unattributed — defined behavior,
    # where the unguarded write was memory corruption.
    counts = zeros(Int32, 1)
    Octopus._aperture_bump!(counts, 0)
    Octopus._aperture_bump!(counts, 2)
    Octopus._aperture_bump!(counts, 1)
    @test counts == Int32[1]
end

@testset "Append continuation: torn writes dropped, corruption refused, wipes loud" begin
    # 2026-08-05 audit (F1, U4-1/U4-2, U6-1, A-5): a hard-killed run leaves a
    # partial last line whose truncated turn field ("1" of "12") parses under
    # the idempotence drop rule and used to survive the retry as a duplicate
    # turn label; a fresh task with no start_turn used to wipe the whole
    # append file silently; a zero-byte HDF5 leftover used to fail with a raw
    # HDF5 open error. Now: torn last lines are dropped with a warning,
    # mid-file corruption is refused, total replacement warns naming the
    # start_turn remedy, and the zero-byte leftover initializes fresh.
    mkb(rng_id, charge, mc2, E0) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(300, CPUThreadsExecutionPolicy(), Float64;
            beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
            sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
            charge=charge, mc2=mc2, E0=E0, r0=RE * ME0 / mc2, npart=1.0e10)
    end
    beams() = (mkb(1, -1.0, EMASS_EV, 10.0e9), mkb(2, 1.0, PMASS_EV, 275.0e9))
    L6s(b, t) = Linear6DSpec{Float64}(; beta1=b, beta2=b, alpha1=(0.0, 0.0, 0.0),
                                      alpha2=(0.0, 0.0, 0.0), dmu=2pi .* t)
    ip = StrongStrongCollision(:ip)
    l1 = (ip, L6s((0.55, 0.056, 12.7), (0.08, 0.14, -0.069)))
    l2 = (ip, L6s((0.8, 0.072, 90.9), (0.228, 0.210, -0.01)))
    lum_turns(path) = [parse(Int, first(split(l, '\t'))) for l in readlines(path)[2:end]]

    # A torn last line is dropped with a warning and cannot become a
    # duplicate turn label on the retry.
    p1 = tempname() * ".lum"
    t1 = StrongStrongTask(l1, l2; luminosity_path=p1, luminosity_append=true)
    b1, b2 = beams(); execute!(t1, b1, b2; turns=3)
    open(io -> print(io, "1"), p1, "a")            # torn first byte of a "12..." row
    t1b = StrongStrongTask(l1, l2; luminosity_path=p1, luminosity_append=true)
    b1, b2 = beams()
    @test_logs (:warn, r"torn partial last line") match_mode = :any execute!(
        t1b, b1, b2; turns=1, start_turn=3)
    @test lum_turns(p1) == [0, 1, 2, 3]

    # A malformed row that is NOT last cannot come from a torn final write:
    # refused, and refused BEFORE any companion observer is truncated (U4-4).
    open(p1, "a") do io
        println(io, "garbage\trow")
        println(io, "9\t1.0")
    end
    t1c = StrongStrongTask(l1, l2; luminosity_path=p1, luminosity_append=true)
    b1, b2 = beams()
    @test_throws ArgumentError execute!(t1c, b1, b2; turns=1, start_turn=10)

    # Total replacement (fresh task, no start_turn) is loud, naming the remedy.
    p2 = tempname() * ".lum"
    t2 = StrongStrongTask(l1, l2; luminosity_path=p2, luminosity_append=true)
    b1, b2 = beams(); execute!(t2, b1, b2; turns=3)
    t2b = StrongStrongTask(l1, l2; luminosity_path=p2, luminosity_append=true)
    b1, b2 = beams()
    @test_logs (:warn, r"replacing the entire existing luminosity") match_mode = :any execute!(
        t2b, b1, b2; turns=2)
    @test lum_turns(p2) == [0, 1]

    # MomentObserver twin: loud wipe, and a zero-byte leftover initializes fresh.
    turns_in(path) = Octopus.HDF5.h5open(path) do f
        n = Int(read(f["record_count"])[1])
        Int.(f["data"][1:n, 1])
    end
    mk1() = Phase6DRep([1e-4], [0.0], [0.0], [0.0], [0.0], [0.0])
    dline = (DriftSpec(L=1.0),)
    p3 = tempname() * ".h5"
    t3 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p3; capacity=2, append=true)),))
    execute!(t3, mk1(); turns=3)
    t3b = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p3; capacity=2, append=true)),))
    @test_logs (:warn, r"replacing the entire existing moment table") match_mode = :any execute!(
        t3b, mk1(); turns=2)
    @test turns_in(p3) == [0, 1]

    p4 = tempname() * ".h5"
    touch(p4)                                      # crash-at-create leftover
    t4 = TrackingTask(dline; hooks=(ScheduledObserver(MomentObserver(p4; capacity=2, append=true)),))
    execute!(t4, mk1(); turns=2)
    @test turns_in(p4) == [0, 1]

    foreach(p -> rm(p; force=true), (p1, p2, p3, p4))
end

@testset "A task re-run on the other backend reallocates its loss record" begin
    # Audit part 7, T2: the `fits` test compared shape only, against its own
    # docstring's "shape or backend" -- a CPU-built record handed to a CUDA
    # kernel is a KernelError, and a device record handed to the CPU bump is a
    # MethodError.
    if CUDA_TESTS_ACTIVE
        line = (DriftSpec(L=1.0), ApertureSpec(x_limit=2.0e-3, name="C"),
                DriftSpec(L=0.5))
        mk() = Phase6DRep([1.0e-3, 5.0e-3, 0.0, 0.0], zeros(4),
                          [0.0, 0.0, 1.0e-4, 0.0], zeros(4), zeros(4), zeros(4))
        task = TrackingTask(line)
        allow_lost_particles(; enabled=true) do
            execute!(task, mk(); turns=1)
            @test loss_counts(loss_record(task)) == [1]
            device = Phase6DRep((Octopus.CUDA.CuArray(a)
                                 for a in coordinate_arrays(mk()))...)
            execute!(task, device; turns=1)
            @test loss_record(task).counts isa Octopus.CUDA.CuArray
            @test loss_counts(loss_record(task)) == [1]
            execute!(task, mk(); turns=1)      # and back
            @test loss_record(task).counts isa Array
            @test loss_counts(loss_record(task)) == [1]
        end
    else
        @test_skip "CUDA device not available"
    end
end

@testset "BPM reads a device number, not the truth" begin
    line = (QuadrupoleSpec(L=0.4, k1=1.7, nst=4), DriftSpec(L=0.6),
            QuadrupoleSpec(L=0.4, k1=-1.7, nst=4), DriftSpec(L=0.6))
    mkrep() = Phase6DRep([1.0e-3, 2.0e-3, -1.0e-3], [1.0e-4, -2.0e-4, 0.5e-4],
                         [0.5e-3, -1.5e-3, 2.0e-3], [2.0e-4, 1.0e-4, -1.0e-4],
                         [0.0, 0.0, 0.0], [1.0e-3, -1.0e-3, 0.0])

    # The reason a BPM is an observer and not an element: a zero-length element
    # cannot carry a reading offset. The entrance and exit frames cancel, so a
    # misaligned marker is the identity -- the machinery runs and the map is
    # bit-identical. Documented in docs/theory/bpm_measurement_model.md Sec. 2.
    let u = (3.0e-3, 3.0e-4, -2.0e-3, -2.2e-4, 2.0e-3, 1.1e-3)
        plain = compile_runtime(MarkerSpec())
        moved = compile_runtime(MarkerSpec(x_offset=1.0e-3, y_offset=-8.0e-4))
        @test moved isa MisalignedElement          # the wrap really is applied
        @test collect(moved(u...)) == collect(plain(u...))   # and does nothing
    end

    # Zero errors must return the centroid itself, which is what ties the new
    # readout path to the already-validated moment reduction.
    let bpm = BPMObserver("b1"), rep = mkrep()
        execute!(TrackingTask(line; hooks=(ScheduledObserver(bpm),)), rep; turns=3)
        turns, xs, ys = readings(bpm)
        st = beam_statistics(rep)
        @test turns == [0, 1, 2]
        @test xs[end] == st.mean[1]
        @test ys[end] == st.mean[3]
    end

    # A BPM is passive: tracking must be bit-identical with and without one.
    let r1 = mkrep(), r2 = mkrep()
        execute!(TrackingTask(line), r1; turns=3)
        execute!(TrackingTask(line; hooks=(ScheduledObserver(BPMObserver("b2")),)), r2; turns=3)
        @test collect(r1[1]) == collect(r2[1])
    end

    # The model reduces exactly to MAD-X's `reading = (1+MSCAL)*true + MRE`.
    let m = BPMObserver("madx"; x_gain=0.5, x_readout=1.0e-4, y_gain=-0.3, y_readout=-2.0e-5)
        rx, ry = bpm_reading(m, 2.0e-3, 1.0e-3, 0)
        @test rx == 1.5 * 2.0e-3 + 1.0e-4
        @test ry == 0.7 * 1.0e-3 - 2.0e-5
    end

    # Signs and geometry. The offset is a body position and SUBTRACTS (Bmad),
    # unlike MAD-X's MREX which is a reading bias and is x_readout here.
    @test bpm_reading(BPMObserver("o"; x_offset=1.0e-3), 0.0, 0.0, 0)[1] == -1.0e-3
    @test bpm_reading(BPMObserver("b"; x_readout=1.0e-3), 0.0, 0.0, 0)[1] == +1.0e-3
    let (rx, ry) = bpm_reading(BPMObserver("r"; tilt=pi / 2), 1.0e-3, 0.0, 0)
        @test abs(rx) < 1.0e-18
        @test ry ≈ -1.0e-3 atol = 1.0e-18
    end

    # Every error term has to reach the reading, in the spirit of the element
    # parameter effectiveness contract -- the misaligned marker above is the
    # cautionary tale for what a silently-inert parameter looks like.
    for kw in (:x_offset, :y_offset, :tilt, :x_gain, :y_gain,
               :x_readout, :y_readout, :x_noise, :y_noise)
        base = bpm_reading(BPMObserver("z"), 1.3e-3, -0.7e-3, 1)
        moved = bpm_reading(BPMObserver("z"; (kw => 3.7e-3,)...), 1.3e-3, -0.7e-3, 1)
        @test moved != base
    end

    # Noise is a counter-RNG draw keyed by turn and rng_id, so it reproduces
    # across chunked execution -- the invariant the tracking RNG already holds.
    let
        set_global_rng!(seed=999)
        a = BPMObserver("c"; x_noise=1.0e-5, rng_id=42)
        ra = mkrep()
        execute!(TrackingTask(line; hooks=(ScheduledObserver(a),)), ra; turns=4)
        set_global_rng!(seed=999)
        b = BPMObserver("c"; x_noise=1.0e-5, rng_id=42)
        rb = mkrep()
        task = TrackingTask(line; hooks=(ScheduledObserver(b),))
        execute!(task, rb; turns=2)
        execute!(task, rb; turns=2)
        @test readings(b)[1] == [0, 1, 2, 3]
        @test readings(a)[2] == readings(b)[2]
    end

    # Noise of the requested width, and two BPMs must not share a stream.
    let bpm = BPMObserver("n"; x_noise=2.0e-5, rng_id=5)
        s = [bpm_reading(bpm, 0.0, 0.0, t)[1] for t in 1:4000]
        @test abs(sum(s) / length(s)) < 3.0e-6
        @test 1.8e-5 < sqrt(sum(abs2, s) / length(s)) < 2.2e-5
        other = BPMObserver("n2"; x_noise=2.0e-5, rng_id=6)
        @test bpm_reading(bpm, 0.0, 0.0, 1)[1] != bpm_reading(other, 0.0, 0.0, 1)[1]
    end

    @test_throws ArgumentError BPMObserver("bad"; x_noise=-1.0)
    @test_throws ArgumentError BPMObserver("bad"; y_noise=-1.0)
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
                  :dev_thin_multipole_skew,
                  # ref_tilt: the design-orbit roll MAD-X spells `tilt` on the
                  # bend itself. The last two carry a roll AND a misalignment,
                  # which is the only way the frame the error is quoted in
                  # becomes observable -- with the wrong choice they land at
                  # 2.0e-4 and 3.5e-4 rather than here.
                  :dev_sbend_reftilt, :dev_sbend_reftilt_vertical,
                  :dev_cfbend_reftilt, :dev_cfbend_reftilt_mis_dx,
                  :dev_cfbend_reftilt_mis_all,
                  # The same through RBEND, which reaches the sector map via
                  # the angle/2 face conversion the roll has to survive.
                  :dev_rbend_reftilt, :dev_rbend_reftilt_vertical,
                  :dev_rbend_k1_reftilt_mis_all,
                  # A spread of roll angles: negative, cos = sin, cos < 0, the
                  # full flip, and the near-identity regime. Our map has no
                  # quadrant logic, so these mostly pin that MAD-X has none
                  # either -- it neither normalises nor special-cases `tilt`.
                  :dev_sbend_reftilt_neg, :dev_cfbend_reftilt_quarter,
                  :dev_sbend_reftilt_obtuse, :dev_sbend_reftilt_pi,
                  :dev_sbend_reftilt_small,
                  # The ordering case at a NEGATIVE roll: a sign slip in the
                  # R_z(-psi) conjugation survives every positive-angle case.
                  :dev_cfbend_reftilt_neg_mis_all)
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

    # A counter-RNG element must COMPILE in the fused CUDA kernel. Every
    # stochastic draw funnels through octopus_uint64, whose unknown-method
    # throw as first written (2026-08-05 hygiene sweep, U15-4) interpolated
    # the code into the message — a heap string, invalid device IR — so any
    # line containing a stochastic element failed cuda_track_kernel!
    # compilation outright, and nothing here tracked one to notice. Caught by
    # the U21-5 validation-line extension; the message is static now, and
    # this pins the whole class: compile, run, and agree with the CPU.
    lumped = LumpedRadSpec{Float64}(;
        damping_turns=(4000.0, 4000.0, 2000.0), beta=(0.8, 0.072, 90.0),
        alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), rng_id=103)
    stochastic_gpu = validate(ElementTrackingBackendConsistencyContract(;
        line=(lumped,), n_particles=256, turns=2,
        backend_a=CPUThreadsBackend, backend_b=CUDABackend,
        atol=1.0e-10, rtol=1.0e-10))
    @test stochastic_gpu.status in (:passed, :skipped)
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

@testset "CUDA :equal_count is equal-count even when z has ties" begin
    # The CPU slices the sort PERMUTATION, so populations are exact by
    # construction. CUDA computed boundaries and then re-derived membership from
    # `z .>= lb .& z .< rb` -- and a comparison cannot split a tie: when several
    # particles share a z value the boundary lands on that value and they all fall
    # the same side.
    #
    # Measured before the fix, 2000 particles quantised to 64 distinct z:
    #   ns=5  CPU [400,400,400,400,400]      CUDA [400,337,460,394,409]   15.8%
    #   ns=9  CPU [222,222,222,222,223,...]  CUDA [211,189,255,...]       27.8%
    # in the slice WEIGHT, which multiplies kbb directly.
    #
    # Ties are measure-zero for continuous Float64 z, which is why this survived
    # every existing test -- but routine for a Float32 beam, for z loaded at
    # limited precision, and for any initial condition that puts z on a grid.
    #
    # The CPU half of the invariant needs no GPU, so it runs on every host --
    # only the CUDA parity half is gated.
    n = 2000
    mkb(pol) = begin
        set_global_rng!(seed=5, method=:philox)
        Beam(n, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
             sigma=(1.0e-4, 1.0e-5, 1.0e-2), cutoff=5.0, rng_id=1, charge=-1.0,
             mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.0e11)
    end
    b = mkb(CPUThreadsBackend)
    z = round.(Array(b.rep.z) ./ 1.0e-3) .* 1.0e-3       # deliberate ties
    copyto!(b.rep.z, z)
    @test length(unique(z)) < n ÷ 10                      # the premise holds
    for ns in (5, 9)
        sl = LongitudinalSlicing(nslices=ns, method=:equal_count)
        sc = Octopus.longitudinal_slices(b.rep, sl)
        # exact equal-count even under ties, as the docstring promises
        cc = [length(i) for i in sc.indices]
        @test maximum(cc) - minimum(cc) <= 1
    end
    if CUDA_TESTS_ACTIVE
        g = mkb(CUDAExecutionPolicy())
        copyto!(g.rep.z, z)
        for ns in (5, 9)
            sl = LongitudinalSlicing(nslices=ns, method=:equal_count)
            sc = Octopus.longitudinal_slices(b.rep, sl)
            sg = Octopus._cuda_longitudinal_slices(g.rep, sl)
            # exact equal-count on the GPU too, and the same counts
            cc = [length(i) for i in sc.indices]
            cg = [length(i) for i in sg.indices]
            @test cg == cc
            # and the same particles, not merely the same counts
            @test [sort(Array(i)) for i in sg.indices] == [sort(Array(i)) for i in sc.indices]
            @test Array(sg.weight) == Array(sc.weight)
            @test Array(sg.center) == Array(sc.center)
        end
        # continuous z (no ties) must be untouched by the change
        b2 = mkb(CPUThreadsBackend); g2 = mkb(CUDAExecutionPolicy())
        for ns in (1, 4, 15)
            sl = LongitudinalSlicing(nslices=ns, method=:equal_count)
            sc = Octopus.longitudinal_slices(b2.rep, sl)
            sg = Octopus._cuda_longitudinal_slices(g2.rep, sl)
            @test [sort(Array(i)) for i in sg.indices] == [sort(Array(i)) for i in sc.indices]
            @test Array(sg.weight) == Array(sc.weight)
            @test Array(sg.boundary) == Array(sc.boundary)
        end
    else
        @test_skip "CUDA device not available"
    end
end

@testset "The CUDA spectral Dirichlet box honours allow_lost_particles" begin
    # The box is sized from WHOLE coordinate arrays, not from slice membership, so
    # the live mask that slicing applies for free does not reach it and has to be
    # explicit. The CPU does that (`_masked_rms`/`_masked_ext`); the CUDA
    # re-implementation was written with unconditional reductions.
    #
    # Measured before the fix, four dead particles parked at |x| = 1e-1:
    #   CPU  half-width 1.5894818e-3
    #   CUDA half-width 1.5920522e-1     -- a factor of 100
    # Every slice pair then sees a different mesh, so every kick differs.
    #
    # Invisible to the existing tests because the CPU lost-particle test covers
    # SpectralPoissonSolver but the CUDA one covers only moments and slicing, and
    # the CPU/CUDA spectral parity test never enters allow_lost_particles. The
    # cross-product of two supported features, which is the shape this audit
    # series keeps finding.
    if CUDA_TESTS_ACTIVE
        mkpair(pol; poison=false) = begin
            set_global_rng!(seed=31, method=:philox)
            e = Beam(400, pol, Float64; beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(1.0e-4, 1.0e-5, 1.0e-2), cutoff=5.0, rng_id=1, charge=-1.0,
                mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.0e11)
            p = Beam(400, pol, Float64; beta=(0.8, 0.072, 90.9), alpha=(0.0, 0.0, 0.0),
                sigma=(9.0e-5, 8.0e-6, 6.0e-2), cutoff=5.0, rng_id=2, charge=1.0,
                mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=7.0e10)
            if poison
                x = Array(e.rep.x); y = Array(e.rep.y); pz = Array(e.rep.pz)
                for i in 1:4
                    x[i] = 1.0e-1; y[i] = -1.0e-1; pz[i] = NaN
                end
                copyto!(e.rep.x, x); copyto!(e.rep.y, y); copyto!(e.rep.pz, pz)
            end
            (e, p)
        end
        s = SpectralPoissonSolver()
        for poison in (false, true)
            ec, pc = mkpair(CPUThreadsBackend; poison=poison)
            eg, pg = mkpair(CUDAExecutionPolicy(); poison=poison)
            bc = allow_lost_particles() do; Octopus._spectral_box(s, ec.rep, pc.rep) end
            bg = allow_lost_particles() do; Octopus._cuda_spectral_box(s, eg.rep, pg.rep) end
            bcd = allow_lost_particles() do; Octopus._spectral_box_drifted(s, ec.rep, pc.rep) end
            bgd = allow_lost_particles() do; Octopus._cuda_spectral_box_drifted(s, eg.rep, pg.rep) end
            @test isapprox(collect(bg), collect(bc); rtol=1e-12)
            @test isapprox(collect(bgd), collect(bcd); rtol=1e-12)
        end
        # fail-fast must survive: a NaN in a coordinate the box reduces, with the
        # flag OFF, still has to trip the chokepoint rather than be masked away
        let (e, p) = mkpair(CUDAExecutionPolicy())
            x = Array(e.rep.x); x[3] = NaN; copyto!(e.rep.x, x)
            @test_throws ArgumentError Octopus._cuda_spectral_box(s, e.rep, p.rep)
            # and with the flag ON and that particle marked dead, it is excluded
            pz = Array(e.rep.pz); pz[3] = NaN; copyto!(e.rep.pz, pz)
            box = allow_lost_particles() do; Octopus._cuda_spectral_box(s, e.rep, p.rep) end
            @test all(isfinite, collect(box))
        end
    else
        @test_skip "CUDA device not available"
    end
end

@testset "The non-finite reporter does not assert what its own scan disproved" begin
    # `_nonfinite_coordinate_error` is called when a caller detects a non-finite
    # DERIVED quantity, and then scans the raw coordinates to name the culprit.
    # When the scan finds nothing it used to report
    #     "0 of N macroparticles have a non-finite coordinate; first at index 0 with ."
    # -- an error asserting a fact it had just disproved, with an empty detail and
    # a nonsense index, sending the reader to the particle array when the fault is
    # upstream of it.
    #
    # Reachable on BOTH backends, for two different reasons: a drifted position
    # `x + px*s` can overflow to +-Inf from finite `x` and `px` when the drift is
    # large; and on the CUDA fused wavefront route the flag is raised by a slice
    # MOMENT whose beam need not be the beam scanned, because the kick crosses
    # beams.
    finite = (x=[1.0, 2.0, 3.0], px=[0.0, 0.0, 0.0])
    err = try
        Octopus._nonfinite_coordinate_error(:beam2, finite; context="probe")
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    # it must NOT claim a count it did not find, nor point at index 0
    @test !occursin("0 of 3 macroparticles", err.msg)
    @test !occursin("index 0", err.msg)
    # it must say what it actually knows: coordinates clean, fault is derived
    @test occursin("are\nfinite", err.msg) || occursin("are finite", err.msg)
    @test occursin("DERIVED", err.msg)
    @test occursin("non-finite", err.msg)          # the shared marker other tests match on

    # the genuine case still reports precisely
    poisoned = (x=[1.0, NaN, 3.0], px=[0.0, 0.0, 0.0])
    err2 = try
        Octopus._nonfinite_coordinate_error(:beam1, poisoned)
        nothing
    catch e
        e
    end
    @test err2 isa ArgumentError
    @test occursin("1 of 3 macroparticles", err2.msg)
    @test occursin("index 2", err2.msg)
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

# Deterministic beam of `n` particles, with `dead` marked non-finite in a
# rotating choice of coordinate. Poisoning different coordinates matters: a
# particle killed through `py` keeps a perfectly ordinary `x` and `z`, so a mask
# that tested only the coordinates a given reduction reads would keep it.
function loss_test_coords(n)
    s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
    return Dict(:x => s(1.0e-4, 0.0), :px => s(1.0e-5, 0.3),
                :y => s(1.0e-4, 0.9), :py => s(1.0e-5, 1.2),
                :z => s(1.0e-2, 2.0), :pz => s(1.0e-4, 2.5))
end

const _LOSS_FIELDS = (:x, :pz, :py, :z, :px, :y)

function loss_test_rep(n, dead; values=nothing)
    c = loss_test_coords(n)
    for (k, d) in enumerate(dead)
        field = _LOSS_FIELDS[mod1(k, 6)]
        c[field][d] = values === nothing ? (isodd(k) ? NaN : Inf) : values
    end
    return Phase6DRep(c[:x], c[:px], c[:y], c[:py], c[:z], c[:pz])
end

function loss_survivor_rep(n, dead)
    c = loss_test_coords(n)
    keep = setdiff(1:n, dead)
    return Phase6DRep((c[k][keep] for k in (:x, :px, :y, :py, :z, :pz))...)
end

@testset "allow_lost_particles is off by default and scoped" begin
    @test allow_lost_particles() == false
    @test allow_lost_particles(() -> allow_lost_particles()) == true
    @test allow_lost_particles(() -> allow_lost_particles(); enabled=false) == false
    # The scope must not leak, including out of a throwing body.
    @test_throws ErrorException allow_lost_particles(() -> error("boom"))
    @test allow_lost_particles() == false

    # A particle is live only when all six coordinates are finite. Testing fewer
    # would call a particle that died in momentum alive.
    @test is_live(1.0, 2.0, 3.0, 4.0, 5.0, 6.0)
    for slot in 1:6, bad in (NaN, Inf, -Inf)
        coords = Any[1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
        coords[slot] = bad
        @test !is_live(coords...)
    end
    rep = loss_test_rep(20, [3, 11])
    @test count_live(rep) == 18
    @test count_dead(rep) == 2
end

@testset "Lost particles are excluded from every reduction" begin
    n = 200
    dead = [5, 77, 133]
    poisoned = loss_test_rep(n, dead)
    survivors = loss_survivor_rep(n, dead)

    # Beam statistics: masked over the full beam must equal the same statistics
    # computed on a beam that simply does not contain the dead particles, and
    # `n` must report the denominator actually used.
    masked = allow_lost_particles() do
        beam_statistics(poisoned; diagonal_fourth=true)
    end
    reference = beam_statistics(survivors; diagonal_fourth=true)
    @test masked.n == n - length(dead)
    @test masked.mean ≈ reference.mean atol=1e-18
    @test masked.covariance ≈ reference.covariance atol=1e-24
    @test masked.emittance ≈ reference.emittance atol=1e-24
    @test masked.diagonal_fourth_central ≈ reference.diagonal_fourth_central atol=1e-30
    # Without the flag the same beam still poisons the statistics, which is the
    # signal that a non-finite coordinate is a bug when losses are not expected.
    @test !isfinite(beam_statistics(poisoned).mean[1])

    # Moment observer rows, the reduction the todo names first.
    ms = (Moment((1, 0, 0, 0, 0, 0)), Moment((0, 0, 1, 0, 0, 0)),
          Moment((2, 0, 0, 0, 0, 0)), Moment((1, 1, 0, 0, 0, 0)),
          Moment((0, 0, 0, 0, 2, 0)))
    ctx = TrackingContext(turn=7)
    row_masked = allow_lost_particles() do
        Octopus._moment_observer_row(ctx, poisoned, ms)
    end
    row_reference = Octopus._moment_observer_row(ctx, survivors, ms)
    @test row_masked == row_reference
    @test row_masked[1] == 7.0
    # One dead particle takes out every moment, not just its own coordinate,
    # because all six means feed every central moment.
    @test any(!isfinite, Octopus._moment_observer_row(ctx, poisoned, ms)[2:end])

    # An all-dead beam has no moments. NaN is the honest answer and the turn
    # column must survive so the record still says when it happened.
    all_dead = loss_test_rep(8, 1:8)
    row_dead = allow_lost_particles() do
        Octopus._moment_observer_row(ctx, all_dead, ms)
    end
    @test row_dead[1] == 7.0
    @test all(isnan, row_dead[2:end])
end

@testset "Lost particles cannot influence a strong-strong collision" begin
    n = 4000
    dead = [5, 137, 2011]
    sl = LongitudinalSlicing(nslices=3, method=:equal_count)
    solvers = (
        ("PIC", PICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
             grid=(64, 64), green_cache=:none, slicing=sl)),
        ("PIC sigma", PICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
             grid=(64, 64), green_cache=:none, slicing=sl, grid_extent=:sigma)),
        ("Gaussian", GaussianPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4,
             luminosity_scale=1.0, slicing=sl)),
        ("GaussianPIC", GaussianPICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4,
             luminosity_scale=1.0, grid=(64, 64), green_cache=:none, slicing=sl)),
        # Spectral runs an order weaker than its siblings, and the reason is
        # measured (2026-08-05_b audit, U19-2). Its Dirichlet box is sized once
        # from pre-collision coordinates; at kbb = 1e-4 the intra-collision kick
        # carried particles outside it and the deposit tripwire fired on EVERY
        # solve with a clipped fraction between 0.216 and 1.0 -- including the
        # clean/clean arm, so it was the configuration clipping, not the
        # corpses. The three corpse variants were then equal because all three
        # were equally destroyed, and the arm validated a degenerate
        # configuration.
        #
        # It also spent the tripwire's process-wide `maxlog = 8` budget here:
        # this testset alone emitted ~30 such events, after which the R9
        # dropped-charge warning was SILENT for the rest of the Julia process,
        # including every later testset. Fixing the regime fixes that too.
        # Measured: 8 clip warnings at 1e-4, 4 at 1e-5, 0 at 1e-6.
        ("Spectral", SpectralPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6,
             luminosity_scale=1.0, grid=(64, 64), slicing=sl)),
    )
    clean_rep() = Phase6DRep((loss_test_coords(n)[k]
                              for k in (:x, :px, :y, :py, :z, :pz))...)
    # The same particles are dead in all three, but their corpses differ wildly:
    # rotating NaN/Inf coordinates, then all six NaN, then non-finite alongside
    # finite transverse values seven orders of magnitude outside the beam. If a
    # corpse leaked into a grid extent or a moment, the third would move the
    # answer by orders of magnitude.
    function corpse(variant)
        variant == 1 && return loss_test_rep(n, dead)
        variant == 2 && return loss_test_rep(n, dead; values=NaN)
        c = loss_test_coords(n)
        for d in dead
            c[:pz][d] = Inf; c[:x][d] = 1.0e3; c[:y][d] = -1.0e3
        end
        return Phase6DRep(c[:x], c[:px], c[:y], c[:py], c[:z], c[:pz])
    end
    for (name, solver) in solvers
        # The corpse-variant equality is only evidence if the arm is solving a
        # sane configuration. If the mesh is clipping most of the charge, all
        # three variants agree because all three are equally destroyed -- which
        # is what the Spectral arm did (U19-2). Assert the regime, so a coupling
        # or box change cannot quietly return it.
        buf = IOBuffer()
        values = with_logger(SimpleLogger(buf, Logging.Warn)) do
            allow_lost_particles() do
                [collide!(solver, test_beam(corpse(v)), test_beam(clean_rep()),
                          CPUThreadsBackend) for v in 1:3]
            end
        end
        @test !occursin("clipped charge", String(take!(buf)))
        @test all(isfinite, values)
        @test values[1] == values[2] == values[3]
        # Without the flag the deliberate loss is still reported as a failure.
        @test_throws ArgumentError collide!(solver, test_beam(corpse(1)),
                                            test_beam(clean_rep()), CPUThreadsBackend)
    end
end

@testset "Lost-particle charge semantics are pinned per solver family" begin
    # The two solver families implement DIFFERENT documented semantics for a
    # dead particle's share of the bunch charge, and the corpse-variant equality
    # above is blind to both by construction: a count-normalization defect is
    # corpse-content-independent, so all three variants move together. Pin each
    # family's semantics against a survivors-only reference so a silent change
    # on either side fails here.
    #
    # Gaussian: slice weights are live fractions summing to one, so the solver
    # RENORMALIZES -- a masked beam collides bit-identically to a beam that
    # simply does not contain the corpses.
    # PIC: `_pic_kbb1`/`_pic_kbb2` keep dividing by the FULL macro count (the
    # `_nonfinite_coordinate_error` docstring in interface.jl): a dead particle
    # stops depositing and the bunch carries proportionally less charge, so the
    # kick on the opposing beam scales by the live fraction, while the
    # luminosity -- normalized per live particle -- stays put.
    #
    # kbb is tiny so the kick is linear and the live fraction is read off the
    # kick rms directly: measured masked/survivors kick rms ratio 0.899934
    # against live_frac 0.9 (residual 7.3e-5), and the Gaussian arms are
    # bit-identical. A renormalizing PIC lands at 1.0, 111x outside the rtol;
    # a charge-reducing Gaussian breaks the bit equality by ~1e-7 in the
    # coordinates and the luminosity in the 5th digit.
    n = 4000
    dead = collect(1:10:n)                      # 10% dead, spread across z
    live_frac = (n - length(dead)) / n
    sl = LongitudinalSlicing(nslices=3, method=:equal_count)
    kbb = 1.0e-10
    rms(v) = sqrt(sum(abs2, v) / length(v))
    clean() = Phase6DRep((loss_test_coords(n)[k]
                          for k in (:x, :px, :y, :py, :z, :pz))...)
    # npart pinned equal on both arms so the beams differ ONLY by the corpses.
    mk(rep) = begin
        params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
        Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
    end
    function masked_vs_survivors(solver)
        masked_tgt = mk(clean())
        l_masked = allow_lost_particles() do
            collide!(solver, mk(loss_test_rep(n, dead)), masked_tgt,
                     CPUThreadsBackend)
        end
        surv_tgt = mk(clean())
        l_surv = collide!(solver, mk(loss_survivor_rep(n, dead)), surv_tgt,
                          CPUThreadsBackend)
        return l_masked, l_surv, masked_tgt, surv_tgt
    end

    lg_m, lg_s, gt_m, gt_s = masked_vs_survivors(GaussianPoissonSolver(
        kbb1=kbb, kbb2=kbb, luminosity_scale=1.0, slicing=sl))
    @test lg_m == lg_s
    @test all(a == b for (a, b) in zip(coordinate_arrays(gt_m),
                                       coordinate_arrays(gt_s)))

    lp_m, lp_s, pt_m, pt_s = masked_vs_survivors(PICPoissonSolver(
        kbb1=kbb, kbb2=kbb, luminosity_scale=1.0, grid=(64, 64),
        green_cache=:none, slicing=sl))
    z0 = clean()
    kick_masked = pt_m.rep.py .- z0.py
    kick_surv = pt_s.rep.py .- z0.py
    @test rms(kick_surv) > 0                    # the premise: a kick happened
    @test isapprox(rms(kick_masked) / rms(kick_surv), live_frac; rtol=1.0e-3)
    @test isapprox(lp_m, lp_s; rtol=1.0e-4)

    # 2026-08-05_b audit, U19-3: this pinned 2 of the 5 solver configurations
    # its sibling testset exercises, and the two it omitted are exactly the two
    # a reader would most likely guess wrong -- SpectralPoissonSolver
    # renormalizes (like Gaussian) while GaussianPICPoissonSolver keeps the live
    # fraction (like PIC), which is the opposite of what the names suggest. A
    # silent change to either failed nothing anywhere in the suite.
    #
    # The ratio is the discriminating instrument, not the family name: measured
    # masked/survivors kick rms 0.899981 for GaussianPIC and 1.000000 for
    # Spectral against live_frac = 0.9. A renormalizing PIC lands at 0.999919,
    # 111x outside this rtol, so the check separates the two semantics cleanly.
    function kick_ratio(solver)
        m, s, tm, ts = masked_vs_survivors(solver)
        base = clean()
        return rms(tm.rep.py .- base.py) / rms(ts.rep.py .- base.py), m, s
    end

    r_gpic, lgp_m, lgp_s = kick_ratio(GaussianPICPoissonSolver(
        kbb1=kbb, kbb2=kbb, luminosity_scale=1.0, grid=(64, 64),
        green_cache=:none, slicing=sl))
    @test isapprox(r_gpic, live_frac; rtol=1.0e-3)   # keeps the live fraction
    @test isapprox(lgp_m, lgp_s; rtol=1.0e-4)

    r_spec, lsp_m, lsp_s = kick_ratio(SpectralPoissonSolver(
        kbb1=kbb, kbb2=kbb, luminosity_scale=1.0, grid=(64, 64), slicing=sl))
    @test isapprox(r_spec, 1.0; rtol=1.0e-3)         # renormalizes
    @test isapprox(lsp_m, lsp_s; rtol=1.0e-4)
    # The two semantics must stay distinguishable: if a change collapsed them,
    # both ratios would agree and this margin would vanish.
    @test abs(r_spec - r_gpic) > 0.05
end

@testset "Lost particles are dropped from every slicing method" begin
    n = 400
    dead = [5, 137, 201]
    poisoned = loss_test_rep(n, dead)
    survivors = loss_survivor_rep(n, dead)
    keep = setdiff(1:n, dead)
    remap = Dict(orig => k for (k, orig) in enumerate(keep))
    z_poisoned = begin
        c = loss_test_coords(n)
        c[:z][5] = NaN
        Phase6DRep(c[:x], c[:px], c[:y], c[:py], c[:z], c[:pz])
    end
    for method in (:equal_area, :equal_count, :equal_width, :gaussian, :specified)
        sl = method === :specified ?
            LongitudinalSlicing(nslices=4, method=method, positions=[-0.6, 0.0, 0.6]) :
            LongitudinalSlicing(nslices=4, method=method)
        masked = allow_lost_particles() do
            Octopus.longitudinal_slices(poisoned, sl)
        end
        reference = Octopus.longitudinal_slices(survivors, sl)
        @test masked.center ≈ reference.center atol=1e-18
        @test masked.weight ≈ reference.weight atol=1e-15
        @test masked.boundary ≈ reference.boundary atol=1e-18
        # Weights are a fraction of the live beam, so they still sum to one.
        @test sum(masked.weight) ≈ 1.0
        # No dead particle joins any slice, under any method.
        @test sum(length, masked.indices) == n - length(dead)
        for s in 1:4
            @test sort([remap[i] for i in masked.indices[s]]) == sort(reference.indices[s])
        end
        # Without the flag, a non-finite z is still a hard failure. Slicing reads
        # only z, so that is the coordinate it can fail on; a particle that died
        # in x or py carries an ordinary z, passes through here, and is caught
        # by a downstream chokepoint instead.
        @test_throws ArgumentError Octopus.longitudinal_slices(z_poisoned, sl)
        # `isa Any` was true of every value including `nothing`, so this
        # asserted only "did not throw" while reading as a value pin
        # (2026-08-05_b audit, U19-6). Assert the shape instead: a rep
        # poisoned away from z must still produce a real slicing with the
        # requested number of slices.
        sliced_nonz = Octopus.longitudinal_slices(poisoned, sl)
        @test sliced_nonz !== nothing
        @test length(sliced_nonz.indices) == length(reference.indices)
    end
    # A beam with nothing left alive cannot be sliced, and says so plainly
    # rather than surfacing as a non-finite boundary.
    all_dead = loss_test_rep(8, 1:8)
    err = try
        allow_lost_particles() do
            Octopus.longitudinal_slices(all_dead, LongitudinalSlicing(nslices=2))
        end
        nothing
    catch e
        e
    end
    @test err isa ArgumentError && occursin("at least one live particle", err.msg)
end

@testset "Lost-particle masking agrees between CPU and CUDA" begin
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        n = 500
        dead = [5, 77, 133]
        host = loss_test_rep(n, dead)
        survivors = loss_survivor_rep(n, dead)
        device = Phase6DRep((Octopus.CUDA.CuArray(a)
                             for a in coordinate_arrays(host))...)

        ms = (Moment((1, 0, 0, 0, 0, 0)), Moment((0, 0, 1, 0, 0, 0)),
              Moment((2, 0, 0, 0, 0, 0)), Moment((1, 1, 0, 0, 0, 0)),
              Moment((0, 0, 0, 0, 2, 0)), Moment((0, 0, 0, 0, 0, 2)))
        ctx = TrackingContext(turn=3)
        observer = MomentObserver(tempname() * ".h5"; orders=2, capacity=4)

        cuda_masked = allow_lost_particles() do
            Octopus._moment_observer_row(ctx, device, ms, observer)
        end
        reference = Octopus._moment_observer_row(ctx, survivors, ms)
        @test cuda_masked ≈ reference atol=1e-18
        @test cuda_masked[1] == 3.0
        # Unmasked, the CUDA reduction is poisoned just like the CPU one.
        @test any(!isfinite,
                  Octopus._moment_observer_row(ctx, device, ms, observer)[2:end])

        # Slicing: the device path drops the dead under every method, and the
        # broadcast comparisons alone would not have -- Inf survives `z <= rb`
        # when rb is itself infinite, and a particle killed through px or py
        # carries an ordinary z.
        for method in (:equal_area, :equal_count, :equal_width, :gaussian)
            sl = LongitudinalSlicing(nslices=4, method=method)
            cuda_slices = allow_lost_particles() do
                Octopus._cuda_longitudinal_slices(device, sl)
            end
            cpu_slices = Octopus.longitudinal_slices(survivors, sl)
            @test cuda_slices.center ≈ cpu_slices.center atol=1e-15
            @test cuda_slices.weight ≈ cpu_slices.weight atol=1e-15
            @test sum(length, cuda_slices.indices) == n - length(dead)
            @test sum(cuda_slices.weight) ≈ 1.0
        end
    else
        @test_skip "CUDA device not available"
    end
end

@testset "Gathered CUDA PIC routes carry pz; :node refuses silent degradation" begin
    # 2026-08-05 audit F10/F11. F10: `_cuda_pic_extract_slice` built 5-field
    # slices when longitudinal_kick=false while the quadratic/node kick
    # launchers marshal `.pz` unconditionally — every gathered route crashed
    # with "type NamedTuple has no field pz" on a validated configuration the
    # CPU handles (the kernels themselves guard the pz WRITE by the flag).
    # F11: the non-indexed wavefront sub-routes never read the node caches,
    # so interaction_grid=:node silently degraded to :slice_pair there
    # (measured 1.2e-2 coordinate shift vs the honored route), including when
    # pic_timing_detail=true knocked the route off the async path at runtime
    # — a diagnostic changing physics. Now the gathered routes gather all six
    # coordinates (CPU parity measured 7.2e-15..1.4e-14, pinned at 1e-13) and
    # both the static gate and the runtime route guard refuse the
    # silently-degrading combinations.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        mkbp(policy, rng_id) = begin
            set_global_rng!(seed=5, method=:philox)
            Beam(512, policy, Float64;
                beta=(0.55, 0.056, 12.7), alpha=(0.0, 0.0, 0.0),
                sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0, rng_id=rng_id,
                charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV,
                npart=1.0e10)
        end
        allc(b) = map(a -> Array(a), (b.rep.x, b.rep.px, b.rep.y, b.rep.py, b.rep.z, b.rep.pz))
        mdiff(c1, c2) = maximum(maximum(abs.(a .- b)) for (a, b) in zip(c1, c2))
        base = (kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0, grid=(32, 32),
                slicing=LongitudinalSlicing(nslices=3, method=:equal_area))
        for mk in (
            () -> PICPoissonSolver(; base..., slice_interpolation=:quadratic,
                                   longitudinal_kick=false, cuda_indexed_wavefront=false),
            () -> PICPoissonSolver(; base..., slice_interpolation=:quadratic,
                                   longitudinal_kick=false, batch_mode=:sequential,
                                   cuda_async=false),
            () -> PICPoissonSolver(; base..., interaction_grid=:node,
                                   longitudinal_kick=false, batch_mode=:sequential,
                                   cuda_async=false),
        )
            bg1, bg2 = mkbp(CUDAExecutionPolicy(), 1), mkbp(CUDAExecutionPolicy(), 2)
            collide!(mk(), bg1, bg2, CUDABackend)
            bc1, bc2 = mkbp(CPUThreadsExecutionPolicy(), 1), mkbp(CPUThreadsExecutionPolicy(), 2)
            collide!(mk(), bc1, bc2, CPUThreadsBackend)
            @test mdiff(allc(bg1), allc(bc1)) < 1.0e-13
            @test mdiff(allc(bg2), allc(bc2)) < 1.0e-13
        end
        for kw in ((cuda_indexed_wavefront=false,), (cuda_wavefront_fft=false,),
                   (cuda_batch_fft=false,), (cuda_async=false,))
            s = PICPoissonSolver(; base..., interaction_grid=:node,
                                 batch_mode=:wavefront, kw...)
            @test_throws ArgumentError collide!(
                s, mkbp(CUDAExecutionPolicy(), 1), mkbp(CUDAExecutionPolicy(), 2),
                CUDABackend)
        end
        sND = PICPoissonSolver(; base..., interaction_grid=:node, batch_mode=:wavefront)
        ipc = StrongStrongCollision(:ip)
        L6c = Linear6DSpec{Float64}(; beta1=(0.55, 0.056, 12.7),
            beta2=(0.55, 0.056, 12.7), alpha1=(0.0, 0.0, 0.0),
            alpha2=(0.0, 0.0, 0.0), dmu=2pi .* (0.08, 0.14, -0.069))
        tD = StrongStrongTask((ipc, L6c), (ipc, L6c); poisson_solver=sND,
            diagnostics=StrongStrongDiagnostics(pic_timing_detail=true))
        @test_throws ArgumentError execute!(
            tD, mkbp(CUDAExecutionPolicy(), 1), mkbp(CUDAExecutionPolicy(), 2); turns=1)
    else
        @test_skip "CUDA device not available"
    end
end

@testset "CUDA last_luminosity is the final turn's value, as on CPU" begin
    # 2026-08-05 audit open-queue U7-2: the CUDA weak-strong kernels
    # accumulated luminosity across the in-kernel turn loop, so
    # last_luminosity came out ~turns × the CPU value (measured exactly 3.0×
    # at turns=3 for the thin element, with the CPU showing genuine per-turn
    # variation the sum erased). Pinned at multi-turn CPU parity.
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        for kind in (:thin_strong_beam, :gaussian_strong_beam)
            spec = example_spec(ElementSpec{kind})
            mkrep() = Phase6DRep([1.0e-4, -2.0e-4, 3.0e-5], [1.0e-5, 0.0, -5.0e-6],
                                 [-0.5e-4, 2.0e-5, 1.0e-6], [2.0e-5, -1.0e-5, 0.0],
                                 [1.0e-3, -1.0e-2, 5.0e-3], [1.0e-4, 2.0e-4, -3.0e-4])
            ec = compile_runtime(spec)
            rc = mkrep()
            pol = Octopus.ResolvedCPUExecutionPolicy(4)
            Octopus._with_execution_policy(pol) do
                track!(rc, ec, 3, pol)
            end
            eg = compile_runtime(spec)
            rg = Phase6DRep((Octopus.CUDA.CuArray(a)
                             for a in coordinate_arrays(mkrep()))...)
            track!(rg, eg, 3, CUDABackend)
            @test isapprox(Float64(eg.last_luminosity), Float64(ec.last_luminosity);
                           rtol=1.0e-12)
        end
    else
        @test_skip "CUDA device not available"
    end
end

aperture_beam(n; seed=7) = begin
    set_global_rng!(seed=seed, method=:philox)
    Beam(n, CPUThreadsBackend, Float64; beta=(0.5, 0.5, 10.0), alpha=(0.0, 0.0, 0.0),
         sigma=(1.0e-3, 1.0e-3, 1.0e-2), cutoff=4.0, rng_id=1,
         charge=-1.0, mc2=EMASS_EV, E0=1.0e10, r0=RE * ME0 / EMASS_EV, npart=1.0e11)
end

# `===` elementwise, so NaN compares equal to NaN. Ordinary `==` would call two
# identically-dead beams different. Both sides are pulled to host first: `===`
# cannot be broadcast across a device and a host array.
coords_identical(a, b) = all(all(Array(x) .=== Array(y))
                             for (x, y) in zip(coordinate_arrays(a), coordinate_arrays(b)))

wide_aperture() = compile_runtime(ApertureSpec(x_limit=1.0, y_limit=1.0, name="WIDE"))

@testset "Aperture kills what is outside and nothing else" begin
    a = compile_runtime(ApertureSpec(shape=:rectangle, x_limit=1.0e-3, y_limit=2.0e-3,
                                     name="COLL"))
    @test a isa Aperture
    @test isbits(a)                       # must compile for the GPU
    @test tracking_method(ApertureSpec()) isa NonSymplectic6DMap

    # Inside passes through bit-unchanged; outside becomes NaN in all six.
    @test a(5.0e-4, 1.0, 1.0e-3, 2.0, 3.0, 4.0) === (5.0e-4, 1.0, 1.0e-3, 2.0, 3.0, 4.0)
    @test all(isnan, a(2.0e-3, 1.0, 0.0, 2.0, 3.0, 4.0))

    # A particle that arrives already dead is NOT re-killed and NOT attributed
    # here: `was_alive` is false, so this is not the transition. Tested through
    # a non-transverse coordinate too, since that is the case a two-coordinate
    # test would get wrong.
    @test a(NaN, 1.0, 0.0, 2.0, 3.0, 4.0)[2] === 1.0
    @test a(0.0, NaN, 0.0, 2.0, 3.0, 4.0)[1] === 0.0
    @test a(0.0, 1.0, 0.0, 2.0, 3.0, Inf)[1] === 0.0

    # Killing is idempotent: applying the aperture again changes nothing.
    once = a(2.0e-3, 1.0, 0.0, 2.0, 3.0, 4.0)
    @test all(isnan, a(once...))

    # Shapes. The rectellipse is the intersection, so a point inside the
    # rectangle but outside the ellipse is rejected.
    rect = compile_runtime(ApertureSpec(shape=:rectangle, x_limit=1.0e-3, y_limit=1.0e-3))
    ell = compile_runtime(ApertureSpec(shape=:ellipse, x_limit=1.0e-3, y_limit=1.0e-3))
    rel = compile_runtime(ApertureSpec(shape=:rectellipse, x_limit=1.0e-3, y_limit=1.0e-3))
    corner = (0.9e-3, 0.0, 0.9e-3, 0.0, 0.0, 0.0)   # in the rectangle, outside the circle
    @test !isnan(rect(corner...)[1])
    @test isnan(ell(corner...)[1])
    @test isnan(rel(corner...)[1])

    # A predicate reproduces an analytic shape exactly, and stays isbits.
    pred = compile_runtime(ApertureSpec(
        alive=(x, px, y, py, z, pz) -> (x / 1.0e-3)^2 + (y / 1.0e-3)^2 <= 1.0))
    @test isbits(pred)
    for (px_, py_) in ((0.5e-3, 0.5e-3), (0.9e-3, 0.9e-3), (0.0, 1.5e-3))
        probe = (px_, 0.0, py_, 0.0, 0.0, 0.0)
        @test isnan(pred(probe...)[1]) == isnan(ell(probe...)[1])
    end
    # A predicate can depend on coordinates a transverse shape cannot see.
    zcol = compile_runtime(ApertureSpec(alive=(x, px, y, py, z, pz) -> abs(z) < 0.1))
    @test !isnan(zcol(0.0, 0.0, 0.0, 0.0, 0.05, 0.0)[1])
    @test isnan(zcol(0.0, 0.0, 0.0, 0.0, 0.5, 0.0)[1])

    # Offsets move the acceptance with the magnet body.
    off = compile_runtime(ApertureSpec(shape=:rectangle, x_limit=1.0e-3, y_limit=1.0e-3,
                                       dx=5.0e-3))
    @test isnan(off(0.0, 0.0, 0.0, 0.0, 0.0, 0.0)[1])
    @test !isnan(off(5.0e-3, 0.0, 0.0, 0.0, 0.0, 0.0)[1])

    @test_throws ArgumentError ApertureSpec(shape=:hexagon, x_limit=1.0, y_limit=1.0) |> compile_runtime
    @test_throws ArgumentError ApertureSpec(x_limit=-1.0, y_limit=1.0) |> compile_runtime
end

@testset "An aperture that kills nothing changes nothing" begin
    # The load-bearing guarantee: inserting apertures must not perturb any other
    # physics. Bit-identical, not merely close.
    line = (compile_runtime(DriftSpec(L=0.5)),
            compile_runtime(ThinQuadrupoleSpec(k1l=0.05)))
    b1 = aperture_beam(2000)
    track!(b1.rep, line, 10; policy=CPUThreadsExecutionPolicy())
    b2 = aperture_beam(2000)
    track!(b2.rep, (line[1], wide_aperture(), line[2], wide_aperture()), 10;
           policy=CPUThreadsExecutionPolicy())
    @test coords_identical(b1.rep, b2.rep)
    @test count_dead(b2.rep) == 0

    # Weak-strong: coordinates and the luminosity diagnostic both unchanged.
    mkws() = compile_runtime(ThinStrongBeamSpec(kbb=1.0e-3, sigma=(1.0e-3, 1.0e-3),
                                                klum=1.0, beta=(0.5, 0.5)))
    ws1 = mkws(); w1 = aperture_beam(2000; seed=11)
    track!(w1.rep, (ws1,), 5; policy=CPUThreadsExecutionPolicy())
    ws2 = mkws(); w2 = aperture_beam(2000; seed=11)
    track!(w2.rep, (wide_aperture(), ws2, wide_aperture()), 5;
           policy=CPUThreadsExecutionPolicy())
    @test coords_identical(w1.rep, w2.rep)
    @test ws1.last_luminosity === ws2.last_luminosity

    # Strong-strong: every solver, luminosity and both beams unchanged.
    sl = LongitudinalSlicing(nslices=3, method=:equal_count)
    solvers = (
        PICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
                         grid=(32, 32), green_cache=:none, slicing=sl),
        GaussianPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0, slicing=sl),
        SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
                              grid=(32, 32), slicing=sl),
        GaussianPICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
                                 grid=(32, 32), green_cache=:none, slicing=sl),
    )
    for solver in solvers
        x1, y1 = aperture_beam(2000; seed=11), aperture_beam(2000; seed=11)
        plain = collide!(solver, x1, y1, CPUThreadsBackend)
        x2, y2 = aperture_beam(2000; seed=11), aperture_beam(2000; seed=11)
        track!(x2.rep, (wide_aperture(),), 1; policy=CPUThreadsExecutionPolicy())
        track!(y2.rep, (wide_aperture(),), 1; policy=CPUThreadsExecutionPolicy())
        with_aperture = collide!(solver, x2, y2, CPUThreadsBackend)
        @test plain === with_aperture
        @test coords_identical(x1.rep, x2.rep)
        @test coords_identical(y1.rep, y2.rep)
    end
end

@testset "Aperture loss record, counter and output" begin
    n = 500
    beam = aperture_beam(n)
    record = LossRecord(["COLL_A", "COLL_B"], n, beam.rep)
    line = (compile_runtime(DriftSpec(L=0.5)),
            compile_runtime(ApertureSpec(shape=:rectangle, x_limit=2.0e-3, y_limit=1.0,
                                         name="COLL_A", element_id=1, loss_record=record)),
            compile_runtime(ThinQuadrupoleSpec(k1l=0.05)),
            compile_runtime(ApertureSpec(shape=:ellipse, x_limit=3.0e-3, y_limit=1.5e-3,
                                         name="COLL_B", element_id=2, loss_record=record)))

    # A recording aperture cannot run on the context-free path, and must say so
    # rather than produce a correct run with a silently empty log.
    @test Octopus._requires_tracking_context(line)
    @test_throws ArgumentError track!(beam.rep, line, 1,
                                      Octopus.ResolvedCPUExecutionPolicy(1))

    track!(beam.rep, line, 5; policy=CPUThreadsExecutionPolicy())
    losses = loss_records(record)
    dead = count_dead(beam.rep)
    @test dead > 0
    # NOTE: `sum(loss_counts(record)) == dead` below is a CONCURRENCY assertion
    # as much as a bookkeeping one, and it only bites when this process has more
    # than one thread -- `_run_logical_workers` never spawns for a single
    # worker. It passed for months against a counter that lost 53% of its
    # increments at 8 workers. CI now runs `--threads=4` so that this line means
    # something; if you are running it by hand, use `julia -t` or it proves
    # nothing about the shared counter.
    @test Threads.nthreads(:default) > 1 skip = (Threads.nthreads(:default) == 1)
    # Exactly one record per dead particle: no double-logging across turns or
    # across the two apertures, and no loss missed.
    @test length(losses.particle_id) == dead
    @test length(unique(losses.particle_id)) == dead
    @test sum(loss_counts(record)) == dead
    # The counter agrees with the records aperture by aperture, not just in total.
    for id in 1:2
        @test count(==(id), losses.element_id) == loss_counts(record)[id]
    end
    # Coordinates are the pre-kill ones. Recording after the kill would store NaN
    # and lose exactly the information the log exists for.
    @test all(isfinite, losses.x) && all(isfinite, losses.pz)
    @test all(0 .<= losses.turn .< 5)

    # Output carries only the losses, and names them.
    path = tempname() * ".h5"
    written = write_loss_record(path, record; s=[12.5, 47.0])
    @test written == dead
    @test written < n
    back = read_loss_record(path)
    @test back.particle_id == losses.particle_id
    @test back.turn == losses.turn && back.element_id == losses.element_id
    @test all(back[k] == losses[k] for k in (:x, :px, :y, :py, :z, :pz))
    @test back.aperture_names == ["COLL_A", "COLL_B"]
    @test back.aperture_counts == Int64.(loss_counts(record))
    @test back.aperture_s == [12.5, 47.0]

    # No log requested: counters only, no per-particle allocation, no file.
    counters = LossRecord(["A"], n, beam.rep; log=false)
    @test counters.slots === nothing
    @test_throws ArgumentError loss_records(counters)
end

@testset "Aperture reconciliation exposes unattributed deaths" begin
    n = 500
    beam = aperture_beam(n)
    # Kill three by hand before tracking: numerical deaths no aperture can claim.
    # Two of them die in coordinates the aperture does not even read.
    hand_killed = (3, 9, 17)
    beam.rep.x[3] = NaN; beam.rep.pz[9] = NaN; beam.rep.py[17] = NaN
    record = LossRecord(["COLL_A"], n, beam.rep)
    line = (compile_runtime(DriftSpec(L=0.5)),
            compile_runtime(ApertureSpec(shape=:rectangle, x_limit=2.0e-3, y_limit=1.0,
                                         name="COLL_A", element_id=1, loss_record=record)))
    track!(beam.rep, line, 5; policy=CPUThreadsExecutionPolicy())

    summary = loss_summary(beam, record)
    @test summary.particles == n
    @test summary.live + summary.dead == n
    @test summary.dead == summary.logged + summary.unattributed
    # The gap is the diagnostic: exactly the three that no aperture stopped.
    @test summary.unattributed == length(hand_killed)
    # And they are absent from the log, because the aperture did not lose them.
    losses = loss_records(record)
    @test !any(in(losses.particle_id), hand_killed)
end

@testset "Aperture losses are identical on CPU and CUDA" begin
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        n = 500
        mkline(rec) = (
            compile_runtime(DriftSpec(L=0.5)),
            compile_runtime(ApertureSpec(shape=:rectangle, x_limit=2.0e-3, y_limit=1.0,
                                         name="A", element_id=1, loss_record=rec)),
            compile_runtime(ThinQuadrupoleSpec(k1l=0.05)),
            compile_runtime(ApertureSpec(shape=:ellipse, x_limit=3.0e-3, y_limit=1.5e-3,
                                         name="B", element_id=2, loss_record=rec)))

        cpu = aperture_beam(n)
        cpu_record = LossRecord(["A", "B"], n, cpu.rep)
        track!(cpu.rep, mkline(cpu_record), 5; policy=CPUThreadsExecutionPolicy())

        host = aperture_beam(n)
        device = Phase6DRep((Octopus.CUDA.CuArray(a)
                             for a in coordinate_arrays(host.rep))...)
        gpu_record = LossRecord(["A", "B"], n, device)
        track!(device, mkline(gpu_record), 5; policy=CUDAExecutionPolicy())

        @test loss_counts(gpu_record) == loss_counts(cpu_record)
        c, g = loss_records(cpu_record), loss_records(gpu_record)
        # Byte-identical, which is what the private-slot layout buys over an
        # atomic append: slot i is particle i on both backends, so there is no
        # scheduling-dependent ordering to reconcile.
        @test g.particle_id == c.particle_id
        @test g.turn == c.turn
        @test g.element_id == c.element_id
        @test all(g[k] == c[k] for k in (:x, :px, :y, :py, :z, :pz))
        @test coords_identical(device, cpu.rep)
    else
        @test_skip "CUDA device not available"
    end
end

@testset "Curvature is resolved before tracking, not inside the kernel" begin
    u0 = (1.2e-3, 3.1e-4, -0.8e-3, -1.7e-4, 2.0e-3, 4.0e-3)
    # The frame decides by default, and the choice lands in the TYPE so no
    # curvature test survives into the tracking kernel.
    @test compile_runtime(DriftSpec(L=0.7)) isa
          Octopus.LatticeMagnet{<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,false}
    @test compile_runtime(DriftSpec(L=0.7, h=0.05)) isa
          Octopus.LatticeMagnet{<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,true}
    @test compile_runtime(SBendSpec(L=1.1, h=0.18, b0=0.18)) isa
          Octopus.LatticeMagnet{<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,true}

    # curved = true at h = 0 runs the curved closed form where the straight one
    # also applies. Both are exact here, so this validates the path rather than
    # an approximation -- and it must agree to roundoff.
    for spec in (DriftSpec(L=0.7), QuadrupoleSpec(L=0.4, k1=1.7, nst=4),
                 SextupoleSpec(L=0.25, k2=14.0, nst=4))
        straight = compile_runtime(spec)
        forced = compile_runtime(typeof(spec)(; spec.params..., curved=true))
        @test forced isa Octopus.LatticeMagnet{<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,<:Any,true}
        @test collect(forced(u0...)) ≈ collect(straight(u0...)) atol=1e-15
    end

    # curved = false with h != 0 ignores the curvature and says so.
    @test_logs (:warn,) compile_runtime(DriftSpec(L=0.7, h=0.05, curved=false))
    ignored = (@test_logs (:warn,) compile_runtime(DriftSpec(L=0.7, h=0.05, curved=false)))
    @test collect(ignored(u0...)) == collect(compile_runtime(DriftSpec(L=0.7))(u0...))

    # And a curved drift still equals the exact curved map it always did.
    @test collect(compile_runtime(DriftSpec(L=0.7, h=0.05))(u0...)) ==
          collect(Octopus._lattice_drift(0.05, 0.7, u0...))
end

@testset "Patch: deliberate change of reference frame" begin
    u0 = (1.2e-3, 3.1e-4, -0.8e-3, -1.7e-4, 2.0e-3, 4.0e-3)
    p(; kw...) = compile_runtime(PatchSpec(; kw...))

    @test isbits(p(angle_x=0.01))
    @test p(angle_x=0.01) isa Patch          # must NOT be wrapped as a misalignment
    @test collect(p()(u0...)) == collect(u0)  # no parameters is the identity

    # A patch composed with its inverse is the identity. This is the cheapest
    # check that the frame rotation is composed in the right direction: an
    # inverted W passes almost everything else.
    for (fwd, inv) in ((( dx=1.0e-3, dy=-2.0e-3, dz=0.05), (dx=-1.0e-3, dy=2.0e-3, dz=-0.05)),
                       ((angle_x=0.012,),  (angle_x=-0.012,)),
                       ((angle_y=-0.008,), (angle_y=0.008,)),
                       ((angle_s=0.3,),    (angle_s=-0.3,)),
                       ((t_offset=0.02,),  (t_offset=-0.02,)))
        @test collect(p(; inv...)(p(; fwd...)(u0...)...)) ≈ collect(u0) atol=1e-16
    end

    # A purely longitudinal patch IS a drift: the drift-to-the-new-face step is
    # what gives a patch an effective length, so dz must reproduce DriftSpec
    # exactly rather than merely relabel s.
    @test collect(p(dz=0.4)(u0...)) == collect(compile_runtime(DriftSpec(L=0.4))(u0...))

    # Which frame changes a drift is invariant under, and which it is not.
    # Free propagation is invariant under a transverse shift and under a roll,
    # because it is translation- and axially-symmetric. It is NOT invariant
    # under a pitch, which tilts the propagation axis -- the endpoint moves by
    # about L*theta. Getting this backwards would mean the position was not
    # being rotated along with the momentum.
    drift = compile_runtime(DriftSpec(L=1.5))
    ref = collect(drift(u0...))
    sandwich(tr, inv) = collect(p(; inv...)(drift(p(; tr...)(u0...)...)...))
    @test sandwich((dx=3.0e-3, dy=-2.0e-3), (dx=-3.0e-3, dy=2.0e-3)) ≈ ref atol=1e-16
    @test sandwich((angle_s=0.2,), (angle_s=-0.2,)) ≈ ref atol=1e-16
    pitched = sandwich((angle_x=5.0e-3,), (angle_x=-5.0e-3,))
    @test !isapprox(pitched, ref; atol=1e-6)
    @test maximum(abs.(pitched .- ref)) ≈ 1.5 * 5.0e-3 rtol=0.2

    # The patch composes its rotation with the SAME routine misalignments use,
    # which is what stops the two from drifting apart. That routine's order and
    # signs are pinned against PTC by quad_mis_all / cfbend_mis_all (all three
    # angles, 5e-13), so the patch inherits a validated convention rather than
    # carrying an unvalidated one of its own.
    @test Octopus._patch_rotation(Float64, 0.012, -0.008, 0.3, false) ==
          Octopus._misalign_matrix(Float64, -0.008, -0.012, 0.3, false)

    # A single rotation is order-independent, so the two conventions must agree
    # exactly -- which is precisely why one-axis reference cases cannot pin the
    # convention and why the multi-axis PTC cases are the ones that matter.
    for one in ((angle_x=0.012,), (angle_y=-0.008,), (angle_s=0.3,))
        @test collect(p(; one...)(u0...)) == collect(p(; one..., convention=:madx)(u0...))
    end
    # With two angles they differ, and the size is the point: the discrepancy is
    # the PRODUCT of the angles, and it lands at full second-order magnitude
    # because the rotation acts on the three-momentum whose longitudinal
    # component is ~1. At angle_x = 0.012 and angle_s = 0.3 that is 3.6e-3 in
    # the transverse momenta, which are themselves ~3e-4 -- an order of
    # magnitude larger than the quantity it perturbs. This is why picking the
    # convention by guess is not survivable, and why single-axis reference cases
    # cannot catch it.
    two = (angle_x=0.012, angle_s=0.3)
    diff = maximum(abs.(collect(p(; two...)(u0...)) .-
                        collect(p(; two..., convention=:madx)(u0...))))
    @test collect(p(; two...)(u0...)) != collect(p(; two..., convention=:madx)(u0...))
    @test diff ≈ 0.012 * 0.3 rtol=0.05
    @test_throws ArgumentError compile_runtime(PatchSpec(angle_x=0.01, convention=:bogus))

    # Symplectic: a rigid frame change is a canonical transformation.
    J = Float64[0 1 0 0 0 0; -1 0 0 0 0 0; 0 0 0 1 0 0; 0 0 -1 0 0 0; 0 0 0 0 0 1; 0 0 0 0 -1 0]
    el = p(dx=1.0e-3, dy=-2.0e-3, dz=0.05, angle_x=0.012, angle_y=-0.008, angle_s=0.3)
    h = 1.0e-7; M = zeros(6, 6)
    for j in 1:6
        up = collect(u0); dn = collect(u0); up[j] += h; dn[j] -= h
        M[:, j] = (collect(el(up...)) .- collect(el(dn...))) ./ (2h)
    end
    @test maximum(abs.(M' * J * M .- J)) < 1.0e-8

    # A dead particle stays dead.
    @test all(isnan, collect(el(NaN, NaN, NaN, NaN, NaN, NaN)))
end

@testset "Exact solenoid map" begin
    u0 = (1.2e-3, 3.1e-4, -0.8e-3, -1.7e-4, 2.0e-3, 4.0e-3)
    sol(ks, L) = compile_runtime(SolenoidSpec(L=L, ks=ks))

    @test isbits(sol(1.7, 1.3))          # must compile for the GPU

    # The requirement that forced an exact derivation instead of the paraxial
    # matrix: a switched-off solenoid must be the SAME drift the rest of the
    # lattice uses, to roundoff rather than to a tolerance.
    drift = collect(Octopus._lattice_drift(0.0, 1.3, u0...))
    @test collect(sol(0.0, 1.3)(u0...)) ≈ drift atol=1e-15
    @test collect(sol(1.0e-12, 1.3)(u0...)) ≈ drift atol=1e-14
    @test collect(sol(0.0, 1.3)(u0...)) ≈ collect(compile_runtime(DriftSpec(L=1.3))(u0...)) atol=1e-15

    # Zero length is the identity for any strength: the two edge conversions are
    # evaluated at the same x,y and cancel term by term. Not the same thing as a
    # MAD-X thin solenoid, which holds ks*L fixed instead.
    @test collect(sol(1.7, 0.0)(u0...)) == collect(u0)

    # The closed form must solve Hamilton's equations, not merely look like it.
    # RK4 on the equations of motion from the theory note, Section 4.1.
    function rk4_solenoid(ks, L, u0; n=100_000)
        k = ks / 2
        f(u) = begin
            x, px, y, py, z, pz = u
            Px = px + k * y; Py = py - k * x
            ps = sqrt((1 + pz)^2 - Px^2 - Py^2)
            (Px / ps, k * Py / ps, Py / ps, -k * Px / ps, 1 - (1 + pz) / ps, 0.0)
        end
        u = u0; h = L / n
        for _ in 1:n
            a = f(u); b = f(u .+ h / 2 .* a); c = f(u .+ h / 2 .* b); d = f(u .+ h .* c)
            u = u .+ (h / 6) .* (a .+ 2 .* b .+ 2 .* c .+ d)
        end
        return u
    end
    for ks in (0.35, 1.7, -0.9)
        @test collect(sol(ks, 1.3)(u0...)) ≈ collect(rk4_solenoid(ks, 1.3, u0)) atol=1e-12
    end

    # A solenoid is axisymmetric, so the map commutes with a rotation about s.
    # Catches any implementation that treats x and y asymmetrically.
    function rot(u, t)
        c, s = cos(t), sin(t)
        (c*u[1]-s*u[3], c*u[2]-s*u[4], s*u[1]+c*u[3], s*u[2]+c*u[4], u[5], u[6])
    end
    @test collect(sol(1.7, 1.3)(rot(u0, 0.7)...)) ≈ collect(rot(sol(1.7, 1.3)(u0...), 0.7)) atol=1e-15

    # The Larmor half-angle. The displacement runs along HALF the momentum
    # rotation; if the half disappears a factor of two is wrong in the potential.
    on_axis = (0.0, 1.0e-4, 0.0, 0.0, 0.0, 0.0)
    ks, L = 1.7, 1.3
    m = sol(ks, L)(on_axis...)
    ps = sqrt(1.0 - 1.0e-8)
    @test atan(m[3], m[1]) ≈ -ks * L / (2 * ps) rtol=1e-8

    # p_s is a constant of the motion, so the transverse kinetic momentum has
    # constant magnitude: the solenoid rotates it and does no work.
    kin(u, ks) = begin
        k = ks / 2
        (u[2] + k * u[3])^2 + (u[4] - k * u[1])^2
    end
    @test kin(sol(1.7, 1.3)(u0...), 1.7) ≈ kin(u0, 1.7) rtol=1e-14

    # Reversing sign and length returns the particle: the map is invertible and
    # the two edge conversions are consistent with each other.
    back = sol(1.7, -1.3)(sol(1.7, 1.3)(u0...)...)
    @test collect(back) ≈ collect(u0) atol=1e-15

    # Chromaticity is present, not added: kappa depends on p_s hence on delta.
    off = (u0[1], u0[2], u0[3], u0[4], u0[5], 0.02)
    on = (u0[1], u0[2], u0[3], u0[4], u0[5], 0.0)
    @test sol(1.7, 1.3)(off...)[1] != sol(1.7, 1.3)(on...)[1]

    # Over-momentum throws, exactly as the drift does. Recorded as a property
    # rather than a feature: see docs/theory/solenoid.md Section 9.1.
    @test_throws DomainError sol(1.7, 1.3)(0.0, 1.5, 0.0, 0.0, 0.0, 0.0)
    # A dead particle stays dead and does not resurrect.
    @test all(isnan, collect(sol(1.7, 1.3)(NaN, NaN, NaN, NaN, NaN, NaN)))
end

@testset "Solenoid with superimposed multipoles" begin
    u0 = (1.2e-3, 3.1e-4, -0.8e-3, -1.7e-4, 2.0e-3, 4.0e-3)
    pure = compile_runtime(SolenoidSpec(L=1.3, ks=1.7))
    comb = compile_runtime(SolenoidSpec(L=1.3, ks=1.7, k1=0.6, nst=8))
    @test isbits(comb)

    # A pure solenoid drops to the exact single-map path and is bit-identical to
    # what it was before multipoles existed -- adding the capability must not
    # perturb the element that does not use it.
    @test collect(compile_runtime(SolenoidSpec(L=1.3, ks=1.7, k1=0.0))(u0...)) ==
          collect(pure(u0...))

    # ks = 0 with a quadrupole component must reproduce the actual quadrupole:
    # the splitting reduces to the thing it is splitting.
    @test collect(compile_runtime(SolenoidSpec(L=1.3, ks=0.0, k1=0.6, nst=64))(u0...)) ≈
          collect(compile_runtime(QuadrupoleSpec(L=1.3, k1=0.6, nst=64))(u0...)) atol=1e-15

    # Named strengths fold exactly as they do for the thick magnets, and the
    # skew partner lands in `kskew` because `ks` is taken by the solenoid.
    @test haskey(SolenoidSpec(L=1.0, ks=0.1, k1s=0.3).params, :kskew)
    @test collect(compile_runtime(SolenoidSpec(L=1.3, ks=0.5, kn=(0.0, 0.6), nst=8))(u0...)) ==
          collect(compile_runtime(SolenoidSpec(L=1.3, ks=0.5, k1=0.6, nst=8))(u0...))
    # Setting the same order twice is contradictory, not merely redundant.
    @test_throws ArgumentError SolenoidSpec(L=1.3, ks=0.5, k1=0.6, kn=(0.0, 0.9))
    @test_throws ArgumentError compile_runtime(SolenoidSpec(L=1.3, ks=0.5, k1=0.6, nst=0))

    # Second-order Strang: quadrupling the steps must cut the error ~16x. This
    # is what says the splitting is what it claims to be rather than merely
    # convergent to something.
    ref = collect(compile_runtime(SolenoidSpec(L=1.3, ks=1.7, k1=0.6, k2=8.0, nst=4096))(u0...))
    err(nst) = maximum(abs.(collect(
        compile_runtime(SolenoidSpec(L=1.3, ks=1.7, k1=0.6, k2=8.0, nst=nst))(u0...)) .- ref))
    for (coarse, fine) in ((4, 16), (16, 64), (64, 256))
        @test 12.0 < err(coarse) / err(fine) < 20.0
    end

    # The combined map stays symplectic: Strang splitting of two symplectic maps
    # is symplectic at every step count, exact or not.
    J = Float64[0 1 0 0 0 0; -1 0 0 0 0 0; 0 0 0 1 0 0; 0 0 -1 0 0 0; 0 0 0 0 0 1; 0 0 0 0 -1 0]
    h = 1.0e-7; M = zeros(6, 6)
    for j in 1:6
        up = collect(u0); dn = collect(u0); up[j] += h; dn[j] -= h
        M[:, j] = (collect(comb(up...)) .- collect(comb(dn...))) ./ (2h)
    end
    @test maximum(abs.(M' * J * M .- J)) < 1.0e-8
end

@testset "Solenoid in a curved frame" begin
    u0 = (1.2e-3, 3.1e-4, -0.8e-3, -1.7e-4, 2.0e-3, 4.0e-3)
    sol(; kw...) = compile_runtime(SolenoidSpec(; kw...))
    @test isbits(sol(L=1.3, ks=1.7, h=0.18, nst=8))

    # h = 0 must still take the exact closed form, untouched by curvature
    # support existing.
    @test collect(sol(L=1.3, ks=1.7, h=0.0, nst=8)(u0...)) ==
          collect(sol(L=1.3, ks=1.7)(u0...))

    # ks = 0 in a curved frame must reproduce the exact curved drift -- the
    # element reduces to the thing the rest of the lattice already uses.
    for h in (0.05, 0.18)
        @test collect(sol(L=1.3, ks=0.0, h=h, nst=400)(u0...)) ≈
              collect(Octopus._lattice_drift(h, 1.3, u0...)) atol=1e-7
    end

    # The integrator converges to the exact straight map as the frame flattens.
    # Taken at h = 1e-12 so the physical O(h*L) difference is negligible and
    # what is left is the integration error alone.
    exact = collect(sol(L=1.3, ks=1.7)(u0...))
    flat(n) = maximum(abs.(collect(sol(L=1.3, ks=1.7, h=1.0e-12, nst=n)(u0...)) .- exact))
    @test flat(128) < 1.0e-7
    @test flat(8) / flat(32) > 8.0        # second order

    # And the physical limit: at finite h the curved map differs from the
    # straight one at first order in h, which is the frame curvature doing what
    # it should rather than an error.
    dev(h) = maximum(abs.(collect(sol(L=1.3, ks=1.7, h=h, nst=200)(u0...)) .- exact))
    @test dev(1.0e-3) / dev(1.0e-4) ≈ 10.0 rtol=0.1

    # Second-order convergence in nst at production curvature.
    ref = collect(sol(L=1.3, ks=1.7, h=0.18, nst=8192)(u0...))
    err(n) = maximum(abs.(collect(sol(L=1.3, ks=1.7, h=0.18, nst=n)(u0...)) .- ref))
    for (coarse, fine) in ((8, 32), (32, 128), (128, 512))
        @test 12.0 < err(coarse) / err(fine) < 20.0
    end

    # Symplectic at EVERY step count, including a coarse one. This is what the
    # 16 fixed-point sweeps buy: a truncated implicit solve converges but is not
    # symplectic, and would pass every test above while failing this one.
    J = Float64[0 1 0 0 0 0; -1 0 0 0 0 0; 0 0 0 1 0 0; 0 0 -1 0 0 0; 0 0 0 0 0 1; 0 0 0 0 -1 0]
    for n in (4, 16, 64)
        el = sol(L=1.3, ks=1.7, h=0.18, nst=n); hh = 1.0e-7; M = zeros(6, 6)
        for j in 1:6
            up = collect(u0); dn = collect(u0); up[j] += hh; dn[j] -= hh
            M[:, j] = (collect(el(up...)) .- collect(el(dn...))) ./ (2hh)
        end
        @test maximum(abs.(M' * J * M .- J)) < 1.0e-7
    end

    # `curved` overrides the frame-derived default, and both directions matter.
    @test compile_runtime(SolenoidSpec(L=1.3, ks=1.7)) isa Octopus.Solenoid{<:Any,<:Any,0,false}
    @test compile_runtime(SolenoidSpec(L=1.3, ks=1.7, h=0.18)) isa Octopus.Solenoid{<:Any,<:Any,0,true}
    @test compile_runtime(SolenoidSpec(L=1.3, ks=1.7, curved=true)) isa Octopus.Solenoid{<:Any,<:Any,0,true}

    # curved = true at h = 0 is the strongest check the integrator gets: it runs
    # against the EXACT closed form on the same frame, so this is a direct
    # validation rather than an h -> 0 limit, and the reference has no error of
    # its own to hide behind.
    straight = collect(sol(L=1.3, ks=1.7)(u0...))
    ierr(n) = maximum(abs.(collect(sol(L=1.3, ks=1.7, curved=true, nst=n)(u0...)) .- straight))
    @test ierr(512) < 1.0e-8
    for (coarse, fine) in ((8, 32), (32, 128), (128, 512))
        @test 12.0 < ierr(coarse) / ierr(fine) < 20.0
    end

    # curved = false with h != 0 is a legitimate approximation, but never a
    # silent one: it warns, and then tracks as a straight solenoid.
    @test_logs (:warn,) compile_runtime(SolenoidSpec(L=1.3, ks=1.7, curved=false, h=0.18))
    ignored = (@test_logs (:warn,) compile_runtime(
        SolenoidSpec(L=1.3, ks=1.7, curved=false, h=0.18)))(u0...)
    @test collect(ignored) == straight

    # Curvature composes with superimposed multipoles.
    @test isbits(sol(L=1.3, ks=1.7, h=0.18, k1=0.6, nst=8))
    @test all(isfinite, collect(sol(L=1.3, ks=1.7, h=0.18, k1=0.6, nst=8)(u0...)))

    # ...and it must stay SYMPLECTIC while doing so, which `isfinite` never
    # checked. A curved frame makes the straight multipole kick a non-gradient
    # for everything except a pure normal dipole -- by Cauchy-Riemann,
    # d(dpx)/dy - d(dpy)/dx = -L h Im f -- so the kick has to differentiate the
    # tabulated curved potential instead. Tracked straight it cost 9.6e-4 with
    # k1 and 3.2e-2 with k0s, neither of which `nst` removes, because it is a
    # structural error and not truncation. The pure normal dipole is the one
    # exemption and is included to pin that it stays on the cheap path.
    # Symplecticity alone cannot catch a map that is canonical but WRONG, and
    # nothing external implements a curved solenoid, so the falsifying check is
    # the limit. Two of them:
    #
    #   h -> 0   must converge to the STRAIGHT solenoid, which PTC validates at
    #            4.7e-13. Convergence is first order in h, because a curved
    #            frame really does differ from a straight one at O(h); what
    #            would indicate a wrong map is convergence to a different limit,
    #            or none. Measured ratios 10.0 / 10.0 / 10.01 per decade at
    #            nst = 1024. At coarse nst the Strang splitting error masks it
    #            below h ~ 1e-5, which is why this uses a fine nst.
    #
    #   ks -> 0  with k1 must reproduce a curved-frame QUADRUPOLE, which
    #            `LatticeMagnet` builds through a completely different path
    #            (exact curved drift plus `_curved_kick`, no implicit midpoint).
    #            Two independent implementations agreeing is the strongest
    #            evidence available here; measured 6.8e-10 at nst = 1024.
    let u = u0, ferr = (a, b) -> maximum(abs, collect(a) .- collect(b))
        for (nm, kw) in (("k1", (k1=0.6,)), ("k0s", (k0s=0.2,)))
            ref = sol(; L=1.3, ks=1.7, nst=256, kw...)(u...)
            e4 = ferr(sol(; L=1.3, ks=1.7, h=1.0e-4, nst=256, kw...)(u...), ref)
            e5 = ferr(sol(; L=1.3, ks=1.7, h=1.0e-5, nst=256, kw...)(u...), ref)
            @test 8.0 < e4 / e5 < 12.0        # first order in h, not something else
        end
        qref = compile_runtime(SBendSpec(L=1.3, h=0.18, b0=0.0, k1=0.6,
                                         bend_fringe=false, nst=256))(u...)
        @test ferr(sol(L=1.3, ks=0.0, h=0.18, k1=0.6, nst=256)(u...), qref) < 1.0e-6
    end

    for (name, kw) in (("normal quad", (k1=0.6,)), ("skew quad", (k1s=0.6,)),
                       ("skew dipole", (k0s=0.2,)), ("normal dipole", (k0=0.2,)),
                       ("sextupole", (k2=3.0,)))
        for n in (8, 32)
            el = sol(; L=1.3, ks=1.7, h=0.18, nst=n, kw...)
            hh = 1.0e-7; M = zeros(6, 6)
            for j in 1:6
                up = collect(u0); dn = collect(u0); up[j] += hh; dn[j] -= hh
                M[:, j] = (collect(el(up...)) .- collect(el(dn...))) ./ (2hh)
            end
            @test maximum(abs.(M' * J * M .- J)) < 1.0e-7
        end
    end
end

@testset "Solenoid agrees on CPU and CUDA" begin
    if Octopus._HAS_CUDA && Octopus.CUDA.functional()
        n = 5000
        mk() = begin
            set_global_rng!(seed=11, method=:philox)
            Beam(n, CPUThreadsBackend, Float64; beta=(0.5, 0.5, 10.0), alpha=(0.0, 0.0, 0.0),
                 sigma=(1.0e-3, 1.0e-3, 1.0e-2), cutoff=4.0, rng_id=1,
                 charge=-1.0, mc2=EMASS_EV, E0=1.0e10, r0=RE * ME0 / EMASS_EV, npart=1.0e11)
        end
        line = (compile_runtime(SolenoidSpec(L=1.3, ks=1.7)),
                compile_runtime(ThinQuadrupoleSpec(k1l=0.05)),
                compile_runtime(SolenoidSpec(L=0.8, ks=-0.9)))
        cpu = mk(); track!(cpu.rep, line, 20; policy=CPUThreadsExecutionPolicy())
        host = mk()
        device = Phase6DRep((Octopus.CUDA.CuArray(a)
                             for a in coordinate_arrays(host.rep))...)
        track!(device, line, 20; policy=CUDAExecutionPolicy())
        scale = maximum(maximum(abs.(a)) for a in coordinate_arrays(cpu.rep))
        diff = maximum(maximum(abs.(Array(x) .- y))
                       for (x, y) in zip(coordinate_arrays(device), coordinate_arrays(cpu.rep)))
        @test diff / scale < 1.0e-13
        @test all(all(isfinite, a) for a in coordinate_arrays(cpu.rep))
    else
        @test_skip "CUDA device not available"
    end
end

@testset "TrackingTask owns the loss record" begin
    n = 400
    specs = (DriftSpec(L=0.5),
             ApertureSpec(shape=:rectangle, x_limit=2.0e-3, y_limit=1.0, name="H"),
             ThinQuadrupoleSpec(k1l=0.05),
             ApertureSpec(shape=:ellipse, x_limit=3.0e-3, y_limit=1.5e-3, name="V"))

    # The ergonomic point: no hand-assigned element_id, no hand-built record.
    path = tempname() * ".h5"
    task = TrackingTask(specs; loss_log=path)
    beam = aperture_beam(n)
    execute!(task, beam; turns=5)
    record = loss_record(task)
    @test record !== nothing
    # Ids come from lattice order, names from the specs.
    @test aperture_names(record) == ["H", "V"]
    summary = loss_summary(beam, task)
    @test summary.dead == summary.logged
    @test summary.unattributed == 0
    @test summary.by_aperture == Int.(loss_counts(record))

    # The file is written without being asked, and holds only losses.
    written = read_loss_record(path)
    @test length(written.particle_id) == summary.dead
    @test length(written.particle_id) < n
    @test written.aperture_names == ["H", "V"]

    # A run split across execute! calls produces the same file as one long run.
    # The record is cumulative and a particle is lost at most once, so rewriting
    # whole is idempotent.
    split_path = tempname() * ".h5"
    split_task = TrackingTask(specs; loss_log=split_path)
    split_beam = aperture_beam(n)
    execute!(split_task, split_beam; turns=2)
    execute!(split_task, split_beam; turns=3)
    split = read_loss_record(split_path)
    @test split.particle_id == written.particle_id
    @test split.turn == written.turn
    @test split.element_id == written.element_id
    @test split.x == written.x

    # The same specs on two beams must get two independent records: a spec is a
    # description, not a place to accumulate state.
    a, b = TrackingTask(specs), TrackingTask(specs)
    execute!(a, aperture_beam(n); turns=5)
    execute!(b, aperture_beam(n; seed=99); turns=5)
    @test loss_record(a) !== loss_record(b)
    @test loss_counts(loss_record(a)) != loss_counts(loss_record(b))

    # Re-running a task on a differently sized beam reallocates, because the
    # slots are indexed by particle.
    resized = TrackingTask(specs; loss_log=tempname() * ".h5")
    execute!(resized, aperture_beam(n); turns=2)
    first_record = loss_record(resized)
    execute!(resized, aperture_beam(900); turns=2)
    @test loss_record(resized) !== first_record
    @test size(loss_record(resized).slots, 2) == 900

    # No log path: counters only, no per-particle allocation.
    counters = TrackingTask(specs)
    execute!(counters, aperture_beam(n); turns=3)
    @test loss_record(counters).slots === nothing
    @test sum(loss_counts(loss_record(counters))) > 0

    # A line with no aperture allocates nothing and is otherwise untouched.
    plain = TrackingTask((DriftSpec(L=0.5), ThinQuadrupoleSpec(k1l=0.05)))
    plain_beam = aperture_beam(n)
    execute!(plain, plain_beam; turns=5)
    @test loss_record(plain) === nothing
    @test count_dead(plain_beam) == 0
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

@testset "GaussianPIC hybrid accepts non-Float64 beams" begin
    # Audit part 7, G1 -- broader than reported: ANY non-Float64 rep threw a
    # MethodError, not only mixed-precision ones. The profile buffers are
    # allocated in the workspace's promoted scalar type (rep1, rep2, kbb1,
    # kbb2) while the drifted-solve helpers converted their scalars with
    # eltype(source.x), and _gpic_gaussian_profile! requires the two to agree.
    # The plain PIC solver survives the same beams because its deposit helpers
    # are generically typed. A Float32 rep is routine: it is what a Float32
    # beam loads at, and the solver's own kbb is Float64 by construction.
    mkbeam(T) = begin
        s(scale, phase) = T[T(scale * sin(0.7 * i + phase)) for i in 1:64]
        rep = Phase6DRep(s(1.0e-4, 0.0), s(1.0e-5, 0.3), s(1.0e-4, 0.9),
                         s(1.0e-5, 1.2), s(1.0e-2, 2.0), s(1.0e-4, 2.5))
        params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=64)
        Beam{CPUThreadsBackend,typeof(params),typeof(rep)}(params, rep)
    end
    sl = LongitudinalSlicing(nslices=2, method=:equal_count)
    mkgpic() = GaussianPICPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4,
        luminosity_scale=1.0, grid=(16, 16), green_cache=:none, slicing=sl)
    b32a, b32b = mkbeam(Float32), mkbeam(Float32)
    lum32 = collide!(mkgpic(), b32a, b32b, CPUThreadsBackend)
    b64a, b64b = mkbeam(Float64), mkbeam(Float64)
    lum64 = collide!(mkgpic(), b64a, b64b, CPUThreadsBackend)
    @test isfinite(lum32)
    @test isapprox(lum32, lum64; rtol=1.0e-5)      # Float32 inputs, not a new physics
    @test all(all(isfinite, a) for a in coordinate_arrays(b32a.rep))
    @test all(all(isfinite, a) for a in coordinate_arrays(b32b.rep))
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
    e0, p0 = round_pair()
    px0 = copy(e0.rep.px)
    py0 = copy(p0.rep.py)
    eg, pg = round_pair()
    collide!(GaussianPoissonSolver(slicing=sl, longitudinal_kick=false), eg, pg, CPUThreadsBackend)
    kick_e_ref = eg.rep.px .- px0
    kick_p_ref = pg.rep.py .- py0
    # Both spectral variants reproduce the analytic Bassetti-Erskine kick (physical
    # kbb convention identical to GaussianPoissonSolver); the residual is the
    # deposition/mode-truncation shape error. Compare the per-particle KICK, not
    # final momenta: the proton-side kick is only ~5% of the intrinsic momentum
    # spread, so an rms-of-final-momenta ratio passed with the kick zeroed,
    # doubled, or sign-flipped (measured ratios 0.998 / 1.004 / 0.999 against
    # atol=0.03), and the electron side was blind to a sign flip (0.989). Against
    # the kick itself those same mutations give relative errors 1.0 / 0.96 / 2.0
    # on both beams, while the real residual is 0.017-0.027.
    for (method, grid) in ((:grid, (128, 128)), (:grid_free, (48, 48)))
        es, ps = round_pair()
        collide!(SpectralPoissonSolver(slicing=sl, method=method, grid=grid,
                                       domain_factor=16.0, longitudinal_kick=false),
                 es, ps, CPUThreadsBackend)
        kick_e = es.rep.px .- px0
        kick_p = ps.rep.py .- py0
        @test rms(kick_e .- kick_e_ref) / rms(kick_e_ref) < 0.05
        @test rms(kick_p .- kick_p_ref) / rms(kick_p_ref) < 0.05
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
    # Best-effort overlap: the spawned pair exercises concurrent leases only
    # if the scheduler interleaves them — at nthreads() == 1 they serialize
    # and would pass with a shared-workspace defect present (2026-08-05
    # audit, U17-6). The deterministic variant below carries the claim.
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

    # Deterministic reentrancy: hold a lease of the same workspace size for
    # the whole collide, forcing it onto a SECOND pool workspace on every
    # schedule, single-threaded included — no scheduler cooperation needed.
    held_lease = Octopus._acquire_spectral_grid_ws_pool(24, 40, 1)
    try
        held1, held2 = pair()
        held_luminosity = collide!(solver, held1, held2, CPUThreadsBackend)
        for (expected, actual) in ((expected1, held1), (expected2, held2))
            for (reference, candidate) in zip(
                    coordinate_arrays(expected), coordinate_arrays(actual))
                @test candidate ≈ reference rtol=2.0e-13 atol=2.0e-18
            end
        end
        @test held_luminosity ≈ expected_luminosity rtol=2.0e-13
    finally
        Octopus._release_spectral_grid_ws_pool!(held_lease)
    end
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

    # (a') the in-range top edge u == n-1 keeps its charge ON the boundary node.
    # The clamp used to move base inward while f was still computed from
    # floor(u), giving weights (1, 0) one cell inward — measured charge centre
    # of mass 3.0 for a particle AT u = 4 on a 5-node axis. The fraction is now
    # measured from the clamped base: weights (0, 1), centre of mass 4.0, and
    # interior weights are bit-identical (2026-08-05 audit, U5-7; the CUDA
    # `_cuda_pic_cic_weights` carries the same fix).
    for n in (5, 16, 64)
        @test Octopus._pic_cic_weights(float(n - 1), n) == (n - 1, (0.0, 1.0))
    end
    let Q = zeros(5, 5)
        Octopus._pic_deposit_serial!(Q, :CIC, [4.0], [4.0], 0.0, 0.0, 1.0, 1.0, 5, 5)
        @test sum(Q) == 1.0
        @test sum(Q[i, j] * (i - 1) for i in 1:5, j in 1:5) == 4.0
        @test Q[5, 5] == 1.0
    end
    @test Octopus._pic_cic_weights(2.25, 5) == (3, (0.75, 0.25))  # interior unchanged

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

@testset "PIC luminosity overlap sums the full deposit extent" begin
    # `_pic_luminosity!` deposits onto (nx+1) x (ny+1) NODE arrays but the
    # overlap sum used to run 1:nx, 1:ny. The luminosity mesh puts particles at
    # u in [0.05, nx-1.05], so a TSC deposit's top-edge stencil reaches node
    # nx+1 (base = floor(u)+1 clamped, stencil base..base+2): that charge was
    # deposited and then excluded — measured 0.26% of a uniform beam's charge,
    # an 8.0e-5 relative luminosity deficit. CIC's stencil never passes node
    # nx, so CIC is bit-identical (2026-08-05 audit, U5-8; the three CUDA
    # overlap sums cover the same full extent).
    n = 200
    x1 = [1.0e-4 * (i - 1) / (n - 1) for i in 1:n]        # uniform: edge-heavy
    y1 = [1.0e-4 * ((i * 7) % n) / n for i in 1:n]
    x2 = copy(x1); y2 = reverse(y1)
    results = Dict{Symbol,Any}()
    for method in (:CIC, :TSC)
        solver = PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, grid=(16, 16),
                                  deposit_method=method)
        nx, ny = Octopus._pic_luminosity_grid(solver)
        q1 = zeros(nx + 1, ny + 1); q2 = zeros(nx + 1, ny + 1)
        lum = Octopus._pic_luminosity!(solver, x1, y1, x2, y2, 1.0, q1, q2)
        excluded = sum(q1[nx + 1, :]) + sum(q1[:, ny + 1]) - q1[nx + 1, ny + 1]
        full = sum(q1 .* q2)
        truncated = full - (sum(q1[nx + 1, :] .* q2[nx + 1, :]) +
                            sum(q1[:, ny + 1] .* q2[:, ny + 1]) -
                            q1[nx + 1, ny + 1] * q2[nx + 1, ny + 1])
        results[method] = (lum=lum, full=full, truncated=truncated, excluded=excluded)
    end
    # CIC provably never reaches the top row/column; TSC measurably does.
    @test results[:CIC].excluded == 0.0
    @test results[:TSC].excluded > 0.4                     # ~0.51 of 200 charges
    # The returned luminosity is built from the FULL overlap sum on both
    # methods: the mesh (hence the hx*hy scale) depends only on the particles,
    # so lum/full must agree across methods — it cannot if either still
    # truncates (the TSC truncation was 8.0e-5 relative, far above this rtol).
    @test isapprox(results[:CIC].lum / results[:CIC].full,
                   results[:TSC].lum / results[:TSC].full; rtol=1e-12)
    # and the recovered TSC charge is the measured 8.0e-5-relative deficit
    @test (results[:TSC].full - results[:TSC].truncated) / results[:TSC].full > 5e-5
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
    else
        # Without this the testset reports Total 0 on a CPU-only host: no pass,
        # no skip, nothing to notice (2026-08-05_b audit, U20-3).
        @test_skip "CUDA device not available"
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
            # Kick and Hessian are compared SEPARATELY, because they differ by
            # eight orders of magnitude here and `isapprox` on the joined vector
            # judges both against the norm -- which the O(1) Hessian sets. The
            # testset's named subject is the near-axis KICK, and under the joined
            # comparison a 2.7% (Float32) relative error in it passed
            # (2026-08-05_b audit, U20-5): tolerance 16eps(Float32)*1.414 =
            # 2.70e-6 against |kx| = 1.0e-4.
            @test actual[1:2] ≈ expected[1:2] rtol=16eps(T) atol=16eps(T)*abs(x)
            @test actual[3:5] ≈ expected[3:5] rtol=16eps(T) atol=16eps(T)
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
                    act = Array(output)
                    exp4 = collect(expected)
                    # Kick (1:2) and Hessian (3:4) compared separately: joined,
                    # `isapprox` scales the absolute floor by the vector norm,
                    # which the O(1) Hessian sets, so at the near-axis point the
                    # kick's effective tolerance was 4.27e-5 against |Kx| ~
                    # 9.5e-7 -- 45x the quantity. Measured consequence: at
                    # Float32, 5 of 25 (eta, point) samples accepted a ZERO
                    # kick, and sign-flipped and 10x-wrong kicks passed too
                    # (2026-08-05_b audit, U20-4). The absolute floor for the
                    # kick is now scaled to the kick's own magnitude.
                    kick_floor = tolerance * max(maximum(abs, exp4[1:2]), eps(T))
                    @test act[1:2] ≈ exp4[1:2] rtol=tolerance atol=kick_floor
                    @test act[3:4] ≈ exp4[3:4] rtol=tolerance atol=tolerance
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

    @testset "CUDA spectral deposit tripwire (R9, U9-1)" begin
        # Kernel-level: one fully-out-of-box particle among in-box ones leaves
        # exactly its unit charge in ws.dropped, for each of the three deposit
        # kernels. The negative control must be exactly 0.0, not merely small:
        # the clipped weight is a subset-sum difference in matching term
        # order, so a fully-deposited particle contributes nothing at all.
        lease = Octopus._acquire_spectral_cuda_ws(Float64, 16, 16)
        ws = lease.workspace
        try
            n = 64
            sx = Octopus.CUDA.CuArray([fill(1.0e-4, n - 1); 5.0e-3])
            sy = Octopus.CUDA.zeros(Float64, n)
            spx = Octopus.CUDA.zeros(Float64, n)
            spy = Octopus.CUDA.zeros(Float64, n)
            Lx = Ly = 1.0e-3
            dropped() = Array(ws.dropped)[1]
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_field!(ws, sx, sy, Lx, Ly)
            @test dropped() ≈ 1.0 atol = 1.0e-12
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_potential_solve!(
                ws, ws.PhigL, ws.ExgL, ws.EygL, sx, spx, sy, spy, 0.0, Lx, Ly)
            @test dropped() ≈ 1.0 atol = 1.0e-12
            idx = Octopus.CUDA.CuArray(collect(1:n))
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_potential_solve_idx!(
                ws, ws.PhigL, ws.ExgL, ws.EygL, sx, spx, sy, spy, idx, 0.0, Lx, Ly)
            @test dropped() ≈ 1.0 atol = 1.0e-12
            inside = Octopus.CUDA.CuArray(fill(1.0e-4, n))
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_field!(ws, inside, sy, Lx, Ly)
            @test dropped() == 0.0

            # A PARTIALLY clipped particle, which is what separates a charge
            # tally from a particle tally. Everything above uses a fully
            # out-of-box probe leaving exactly 1.0, and 1.0 is also what a
            # per-particle counter reports and what a "count only when nothing
            # was written" counter reports -- so two of the four defects
            # injected into these kernels went uncaught (2026-08-05_b audit,
            # U20-6). At x = 0.94*Lx the particle straddles the wall and leaves
            # a FRACTIONAL 0.49: a particle counter would say 1.0, a
            # fully-outside-only counter 0.0, and silent clipping 0.0.
            partial = Octopus.CUDA.CuArray([fill(1.0e-4, n - 1); 0.94 * Lx])
            Octopus.CUDA.fill!(ws.dropped, 0.0)
            Octopus._cuda_spectral_field!(ws, partial, sy, Lx, Ly)
            d_partial = dropped()
            @test isapprox(d_partial, 0.49; atol = 1.0e-3)
            # Stated as its own assertion so the discriminating property cannot
            # be lost to a tolerance widening: it must be neither 0 nor 1.
            @test 0.05 < d_partial < 0.95
        finally
            Octopus._release_spectral_cuda_ws!(lease)
        end

        # Collide-level: the CPU R9 configuration (box sized once from
        # pre-collision coordinates, strong intra-collision kick; the CPU
        # twin of this assert is in the slicing testset) warns through the
        # CUDA 6D path too -- one aggregate warning per collision where the
        # CPU path warns per solve. No transverse-path assert: that map never
        # moves x/y inside the collision, so its deposits cannot clip.
        strong_gpu(n) = begin
            s(scale, phase) = [scale * sin(0.7 * i + phase) for i in 1:n]
            x = s(1.0e-4, 0.0); x[1] = 8.0e-4
            rep = Phase6DRep((Octopus.CUDA.CuArray(a) for a in
                (x, s(1.0e-5, 0.3), s(1.0e-4, 0.9), s(1.0e-5, 1.2),
                 s(1.0e-2, 2.0), s(1.0e-4, 2.5)))...)
            params = BeamParams{Float64}(charge=1.0, mc2=1.0, E0=1.0, r0=1.0, npart=n)
            Beam{Octopus.CUDABackend,typeof(params),typeof(rep)}(params, rep)
        end
        sp64 = SpectralPoissonSolver(kbb1=1.0e-4, kbb2=1.0e-4, luminosity_scale=1.0,
            grid=(64, 64), slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
        @test_logs (:warn, r"clipped charge at the Dirichlet wall") match_mode = :any collide!(
            sp64, strong_gpu(256), strong_gpu(256), Octopus.CUDABackend)
    end

    @testset "TSC weights are bit-identical across backends (U2-3)" begin
        # The CUDA kernel once derived w3 = 1 - w1 - w2 while the CPU uses
        # the closed form — a 1-ulp backend divergence in a deposit both
        # sides must agree on. The kernel helper is pure arithmetic, so it
        # is compared on the host, both branches and the edges included.
        # The dyadic grid alone cannot fail on the defect it names. Steps of
        # 15/256 and 32/256 have few significant bits, so for every one of its
        # 528 samples t = f*f, 0.75 - t and 0.125 + 0.5*(t +- f) are exact,
        # w1 + w2 + w3 sums to 1 exactly, and the complement w3 = 1 - w1 - w2
        # rounds to the closed form bit for bit. Measured: 0 of 528 samples
        # discriminate, against 68.3% of random u (2026-08-05_b audit, U20-1;
        # the recorded U2-3 defect re-injected into the kernel passed this
        # testset). Non-dyadic samples are therefore swept as well -- and the
        # testset asserts its own discriminating power rather than assuming it,
        # so a future grid change that quietly returns it to all-dyadic fails
        # here instead of going blind.
        rng = MersenneTwister(20260805)
        discriminating = 0
        mismatches = 0
        for n in (16, 33)
            dyadic = vcat(collect(range(0.0, n - 1.0; length=257)),
                          [0.5, 1.5, 7.25, 7.5, 7.75, n - 1.5, n - 1.0])
            nondyadic = [1.0 + (n - 2.0) * rand(rng) for _ in 1:256]
            for u in vcat(dyadic, nondyadic)
                base_cpu, w_cpu = Octopus._pic_tsc_weights(u, n)
                base_gpu, w1, w2, w3 = Octopus._cuda_pic_tsc_weights(u, Int32(n))
                (Int(base_gpu) == base_cpu && (w1, w2, w3) === w_cpu) ||
                    (mismatches += 1)
                # Would this sample tell the closed form from the complement?
                w_cpu[3] === (1 - w_cpu[1] - w_cpu[2]) || (discriminating += 1)
            end
        end
        @test mismatches == 0
        # Coverage tripwire: without this the testset can pass while being
        # incapable of failing. ~68% of non-dyadic draws discriminate, so 512
        # draws make a zero here impossible unless the sweep itself regressed.
        @test discriminating > 100
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
else
    # This `if` guards 17 testsets and 358 assertions. Without an `else` the
    # whole block does not exist on a CPU-only host -- `Total 0`, no pass and
    # no skip -- which is the failure class the header of this file forbids
    # (2026-08-05_b audit, U20-3). One visible skip stands in for the block.
    @testset "CUDA GPU-only block" begin
        @test_skip "CUDA device not available -- 17 GPU-only testsets did not run"
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

        # Julia-Expr bridge, and the Symbolics adapter -- unconditional: the
        # suite loads Symbolics, so the weak-dep extension MUST have
        # activated. The previous version branched on availability and took
        # the unavailable branch on every package-mode run (part 6, R3).
        e3 = knob_expression("t_knob.k1 / t_knob.brho + 2.0")
        @test knob_expression(string(knob_to_expr(e3))) == e3
        # Through the PUBLIC query (2026-08-05 audit, U14-5): user scripts
        # branching on adapter availability must not need an internal.
        @test knob_symbolics_available()
        # Was `knob_symbolics_available() === _symbolics_adapter_active()`,
        # which compares a function to its own body (symbolic.jl defines the
        # former AS the latter) and so could never fail (2026-08-05_b audit,
        # U20-7). The real claim in the comment above is that a user script
        # must not need the internal -- i.e. that the public query is
        # exported. Assert that.
        @test :knob_symbolics_available in names(Octopus)
        e4 = knob_expression("t_knob.k1 * t_knob.brho + t_knob.k1")
        @test knob_value(knob_from_symbolic(knob_symbolic(e4))) ≈ knob_value(e4)

        # The consumer-boundary contract.
        result = validate(KnobEffectivenessContract())
        @test result.passed
        @test result.metrics[:knob_resolution_receipt]
    finally
        reset_knobs!()
    end
end

@testset "Knob registry atomicity and round-trip totality" begin
    # Pins the 2026-08-05 audit's U14 findings: a rejected knob call must leave
    # NO partial state (the registry's permanent epoch/mutation-path
    # discipline), and the documented string round trip must be total.
    reset_knobs!()
    try
        # 2026-08-05 audit, U14-1: `@knob dep::T` on an expression-defined knob
        # used to retype the entry and CONVERT its cached value before the
        # rejection throw, with no epoch bump -- knob_value then reported
        # 0.1f0::Float32 while dependent caches and every compiled runtime kept
        # 0.1, and nothing recompiled. The guard now precedes any mutation.
        @knob t_atom.a = 0.1
        @knob t_atom.b = t_atom.a * 1.0
        v0 = knob_value("t_atom.b")
        e0 = knob_epoch()
        @test_throws ArgumentError Octopus._knob_define!(
            Symbol("t_atom.b"), Float32, nothing, nothing)
        @test knob_value("t_atom.b") === v0     # value AND type untouched
        @test knob_epoch() == e0                # no bump from a rejected call
        # Same discipline on the redefinition branch: an rhs that fails to
        # lower must not leave a retype behind either.
        @test_throws ArgumentError Octopus._knob_define!(
            Symbol("t_atom.b"), Float32, Meta.parse("rand() * 2.0"), nothing)
        @test knob_value("t_atom.b") === v0
        @test knob_epoch() == e0
        # The legitimate retype of an INDEPENDENT knob still converts the value
        # and still bumps (the 2026-08-04 audit's R4 fix, re-pinned here).
        Octopus._knob_define!(Symbol("t_atom.a"), Float32, nothing, nothing)
        @test knob_value("t_atom.a") === 0.1f0
        @test knob_epoch() != e0

        # 2026-08-05 audit, U14-4: `@knob sin.x = 1.0` used to register the
        # knob and bump the epoch BEFORE _ensure_knob_root threw on the
        # collision with Base.sin; the root is now validated first.
        e4 = knob_epoch()
        @test_throws ArgumentError Core.eval(@__MODULE__, :(@knob sin.x = 1.0))
        @test !(Symbol("sin.x") in list_knobs())
        @test knob_epoch() == e4

        # 2026-08-05 audit, U14-3: a knob named like an expression-language
        # constant was declarable but silently unreachable (`@knob_expr(pi)`
        # lowers to KnobConst, so registry and expressions disagreed on one
        # name). Now rejected at declaration, for every named constant.
        for name in (:pi, :π, :ℯ, :NaN, :Inf)
            @test_throws ArgumentError Octopus._knob_define!(name, Meta.parse("3.0"))
            @test !(name in list_knobs())
        end
        @test knob_epoch() == e4

        # 2026-08-05 audit, U14-2: `^` is right-associative, so a `^` nested as
        # the BASE of another `^` must keep its parentheses -- `(u^v)^w` used
        # to print as "u ^ v ^ w" and reparse as u^(v^w): 64 became 512 through
        # the documented knob_expression(string(e)) == e round trip.
        @knob t_atom.u = 2.0
        @knob t_atom.v = 3.0
        @knob t_atom.w = 2.0
        epow = knob_expression("(t_atom.u ^ t_atom.v) ^ t_atom.w")
        @test string(epow) == "(t_atom.u ^ t_atom.v) ^ t_atom.w"
        @test knob_expression(string(epow)) == epow
        @test knob_value(epow) == 64.0
        eright = knob_expression("t_atom.u ^ (t_atom.v ^ t_atom.w)")
        @test knob_expression(string(eright)) == eright
        @test knob_value(eright) == 512.0

        # 2026-08-05_b audit, U20-2/U13-4: the class above regenerated one
        # operator to the left. `+` and `*` were printed WITHOUT parentheses
        # around a nested same-precedence child on the grounds that they
        # associate -- which they do not in floating point. `a + (b + c)` printed
        # "a + b + c", reparsed to a flat 3-ary call, and the value moved.
        #
        # The pin is the WHOLE binary x binary x operand-position grid rather
        # than a hand-picked sample, because the mixed same-precedence cases are
        # the ones a same-operator sweep misses: `u + (v - w)` and `u * (v / w)`
        # also re-associated, and the latter turned 1e300 into Inf through the
        # documented round trip. Operators come from `_KNOB_OPERATORS`, so a
        # newly whitelisted infix operator enters the grid the day it is added.
        infix = filter(op -> op in (:+, :-, :*, :/, :^),
                       sort!(collect(keys(Octopus._KNOB_OPERATORS))))
        @test length(infix) == 5          # tripwire: the table still has these
        assoc_fail = Tuple{Symbol,Symbol,Int}[]
        shapes = 0
        for outer in infix, inner in infix, pos in 1:2
            leaf_u = Octopus.KnobRef(Symbol("t_atom.u"))
            nested = Octopus.KnobCall(inner, [Octopus.KnobRef(Symbol("t_atom.v")),
                                              Octopus.KnobRef(Symbol("t_atom.w"))])
            ex = Octopus.KnobCall(outer, pos == 1 ? [nested, leaf_u] : [leaf_u, nested])
            shapes += 1
            (knob_expression(string(ex)) == ex) || push!(assoc_fail, (outer, inner, pos))
        end
        @test shapes == 50
        @test isempty(assoc_fail)
        # The value change that made this more than a structural nit: without
        # the parentheses this evaluates 0.0 before the round trip and 1.0 after.
        @knob t_atom.big = 1.0e16
        @knob t_atom.negbig = -1.0e16
        @knob t_atom.one = 1.0
        ecancel = knob_expression("t_atom.big + (t_atom.negbig + t_atom.one)")
        @test knob_value(ecancel) == 0.0
        @test knob_value(knob_expression(string(ecancel))) == 0.0
        # Precedence must still print naturally -- the fix must not parenthesize
        # across levels, only within one.
        @test string(knob_expression("t_atom.u + t_atom.v * t_atom.w")) ==
              "t_atom.u + t_atom.v * t_atom.w"
        # Non-finite constant folds (e.g. d(x/0.0)/dx) used to print as "NaN",
        # which reparsed as KnobRef(:NaN) -> "unknown knob NaN". NaN/Inf are
        # named constants to the parser now, `-Inf` folds back to one constant
        # (Julia has no negative literal for it), and KnobConst equality is
        # isequal-based so the NaN round trip is testable at all.
        dnan = knob_derivative(knob_expression("t_atom.u / 0.0"), Symbol("t_atom.u"))
        @test dnan isa Octopus.KnobConst
        @test knob_expression(string(dnan)) == dnan
        for c in (Octopus.KnobConst(Inf), Octopus.KnobConst(-Inf))
            @test knob_expression(string(c)) == c
        end

        # 2026-08-05 audit, U14-7: the design doc promises `2 * e` a directed
        # error, but only Float64(e)/float(e) had one -- everything else was a
        # bare MethodError. Arithmetic composition and Number conversion now
        # both direct the user to @knob_expr/knob_value.
        eexpr = knob_expression("2.0 * t_atom.u")
        @test_throws ArgumentError 2 * eexpr
        @test_throws ArgumentError 2.0 * eexpr
        @test_throws ArgumentError (1 // 2) * eexpr
        @test_throws ArgumentError eexpr + 1
        @test_throws ArgumentError eexpr / eexpr
        @test_throws ArgumentError eexpr^2
        @test_throws ArgumentError Int(eexpr)
        @test_throws ArgumentError Float64(eexpr)
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
        @test_skip "CUDA device not available"
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
        @test_skip "CUDA device not available"
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
        @test_skip "CUDA device not available"
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
    else
        # Part (e) alone is GPU-only; without this the testset shrinks from 15
        # assertions to 10 on a CPU-only host with nothing to show for it
        # (2026-08-05_b audit, U20-3).
        @test_skip "CUDA device not available"
    end
end

@testset "The lattice Green box is sized in physical units, not index units" begin
    # `_PIC_LATTICE_GREEN_MULT = 8` multiplied the padded extent on BOTH axes, which
    # is an index-unit criterion. The periodic box is `Mx*hx` by `My*hy`, so at
    # rho = hx/hy = 11 it was eleven times flatter than it was wide while the
    # separations it must cover are eleven times wider than tall in physical units.
    # Points far along x therefore saw their y-images. Measured end to end: at the
    # 11:1 production aspect ratio `:lattice` was 10.3x WORSE than the `:integrated`
    # default it exists to improve on (3.21e-2 vs 3.10e-3), and got worse with grid
    # refinement -- the signature of an error that is not discretization.

    # (a) the multiplier scales on the fine-spacing axis, symmetrically, and caps
    @test Octopus._pic_lattice_box_mult(1.0) == (8, 8)
    @test Octopus._pic_lattice_box_mult(5.0) == (8, 40)
    @test Octopus._pic_lattice_box_mult(0.2) == (40, 8)
    let (mx, my) = Octopus._pic_lattice_box_mult(25.0)
        @test mx == 8 && my == Octopus._PIC_LATTICE_GREEN_MULT_MAX   # the cap binds
    end
    # symmetric under rho -> 1/rho
    for rho in (2.0, 5.0, 11.0, 25.0)
        @test Octopus._pic_lattice_box_mult(rho) == reverse(Octopus._pic_lattice_box_mult(1 / rho))
    end

    # (b) the property the box controls: along the COARSE axis, where the physical
    # separation is large, the table must be -ln r + const. That is the part
    # box contamination destroys; the fine-axis deviation is the genuine
    # near-origin lattice correction and is expected to remain.
    nx = ny = 64
    for rho in (1.0, 5.0, 11.0, 25.0)
        tab = Octopus._pic_lattice_green_table(nx, ny, rho)
        at(m) = tab[m + 2nx + 1, 0 + 2ny + 1]
        C = -at(8) - log(8.0)
        worst = maximum(abs(at(m) + log(float(m)) + C) for m in (12, 16, 24, 32))
        # post-fix worst is 7.3e-4 (rho=1) to 5.1e-3 (rho=25, at the cap);
        # pre-fix it was 1.4e-1 at rho=11, so this bound is discriminating
        @test worst < 1.0e-2
    end

    # (c) rho = 1 is untouched, so every previously recorded isotropic result stands
    @test Octopus._pic_lattice_box_mult(1.0) == (8, 8)
    let tab = Octopus._pic_lattice_green_table(32, 32, 1.0)
        @test isapprox(abs(tab[1 + 2 * 32 + 1, 2 * 32 + 1]), pi / 2; rtol=1e-5)
    end
end

@testset "Source and field grids keep equal extent, which the field derivative assumes" begin
    # `E = -grad(phi)` is differenced with a cell size taken from the SOURCE grid
    # (pic_cpu.jl `_pic_solve_drifted_field_with_green_fft!` passes
    # `source_grid.width/(nx-1)` into `_pic_field!`), while `phi` is interpolated on
    # the FIELD grid (`_pic_interpolate_kick` uses `grid.width/(nx-1)`). Those agree
    # only because `_pic_interaction_grids` returns the same width/height for both
    # grids, differing in origin alone.
    #
    # That is an unstated invariant of exactly the shape audit part 3's S14 turned
    # out to be: established by one function, silently depended on by another. And
    # it is worse than S14 in one respect -- BOTH backends take the spacing from the
    # source grid, so a divergence would make them wrong identically and CPU/CUDA
    # parity could not see it. Hence a direct test of the invariant rather than of
    # any output.
    # Deterministic sweep rather than a seeded RNG: the claim is about an
    # invariant, so exhausting the option cross-product is both reproducible and
    # more pointed than sampling. Boxes are deliberately asymmetric between the
    # source and field beams, which is the case where equal extents are least
    # obvious -- `_pic_interaction_grids` takes the max span per axis.
    boxes = (
        (-1.0e-3, 1.0e-3, -1.0e-4, 1.0e-4, -2.0e-3, 2.0e-3, -3.0e-4, 3.0e-4),
        (-3.0e-4, 2.5e-4, -2.0e-5, 3.0e-5, -1.0e-4, 4.0e-4, -4.0e-5, 1.0e-5),
        (0.0, 5.0e-3, 0.0, 1.0e-5, -5.0e-3, 0.0, -1.0e-5, 0.0),
        (-7.0e-6, 7.0e-6, -9.0e-3, 9.0e-3, -1.0e-6, 1.0e-6, -1.0e-2, 1.0e-2),
    )
    for gt in (:integrated, :standard, :lattice),
        q in (0.0, 0.125),
        mte in ((0.0, 0.0), (2.0e-3, 2.0e-4)),
        b in boxes

        s = PICPoissonSolver(; grid=(64, 64), green_type=gt,
                               grid_quantize=q, min_transverse_extent=mte)
        sxmin, sxmax, symin, symax, fxmin, fxmax, fymin, fymax = b
        sg, fg = Octopus._pic_interaction_grids(s, sxmin, sxmax, symin, symax,
                                                   fxmin, fxmax, fymin, fymax)
        # (a) as produced
        @test sg.width == fg.width
        @test sg.height == fg.height
        # (b) after the Green cache's expansion, which scales both by one factor
        es = Octopus._pic_expand_grid_by(sg, 1.25)
        ef = Octopus._pic_expand_grid_by(fg, 1.25)
        @test es.width == ef.width
        @test es.height == ef.height
        # (c) after the part-3 realignment, which must move origins only
        ra, rb = Octopus._pic_realign_expanded_grids(gt, es, ef, 64, 64)
        @test ra.width == rb.width
        @test ra.height == rb.height
        @test ra.width == es.width && rb.width == ef.width
    end
    # negative control: the equality is a real constraint, not trivially
    # true. The old form asserted sg.width != fg.width * 1.01, which only
    # excludes width == 0 (2026-08-05 audit, U17-8). The real control: the
    # two beams' raw spans genuinely differ, so equal produced widths mean
    # the shared max-span rule did the work, not identical inputs.
    let s = PICPoissonSolver(; grid=(64, 64))
        sxmin, sxmax, symin, symax = -1e-3, 1e-3, -1e-4, 1e-4
        fxmin, fxmax, fymin, fymax = -2e-3, 2e-3, -3e-4, 3e-4
        @test (sxmax - sxmin) != (fxmax - fxmin)
        @test (symax - symin) != (fymax - fymin)
        sg, fg = Octopus._pic_interaction_grids(s, sxmin, sxmax, symin, symax,
                                                   fxmin, fxmax, fymin, fymax)
        @test sg.width == fg.width
        @test sg.height == fg.height
        @test sg.width > 0 && sg.height > 0
    end
end

@testset "Green-cache expansion preserves the grid alignment its kernels require" begin
    # `_pic_expand_grid_by` scales `width` with the node count fixed, so the cell
    # size grows while the origin separation does not: an exact k-cell separation
    # became k/(1+growth) cells. `:lattice` is tabulated by INTEGER separation and
    # `_pic_green_lattice!` rounded silently, so the cached Green function was that
    # of a source displaced by the residual -- measured 0.400 cells at the default
    # growth of 0.25, on both CPU and CUDA, which is why the parity test agreed.
    nx = ny = 64
    seps(s, sg, fg) = begin
        hx = sg.width / (nx - 1); hy = sg.height / (ny - 1)
        ((fg.x0 - sg.x0) / hx, (fg.y0 - sg.y0) / hy)
    end
    frac(v) = abs(v - round(v))

    for gt in (:lattice, :standard, :integrated)
        s = PICPoissonSolver(; grid=(nx, ny), green_type=gt)
        sg, fg = Octopus._pic_interaction_grids(s, -3.0e-4, 2.5e-4, -2.0e-5, 3.0e-5,
                                                   -1.0e-4, 4.0e-4, -4.0e-5, 1.0e-5)
        dx0, dy0 = seps(s, sg, fg)
        # what _pic_interaction_grids guarantees: integer for :lattice/:integrated,
        # a deliberate half cell for :standard
        want = gt === :standard ? 0.5 : 0.0
        @test frac(dx0 - want) < 1e-9
        @test frac(dy0 - want) < 1e-9

        sgE = Octopus._pic_expand_grid_by(sg, 1.25)
        fgE = Octopus._pic_expand_grid_by(fg, 1.25)
        # the expansion on its own destroys it -- this is the defect, kept as the
        # negative control so the test below cannot pass vacuously
        dxE, _ = seps(s, sgE, fgE)
        @test frac(dxE - want) > 0.1

        sgA, fgA = Octopus._pic_realign_expanded_grids(gt, sgE, fgE, nx, ny)
        dxA, dyA = seps(s, sgA, fgA)
        if gt === :integrated
            # deliberately untouched: its kernel is evaluated at real coordinates,
            # and moving the default mesh would change results that carry no defect
            @test (sgA.x0, fgA.x0) == (sgE.x0, fgE.x0)
        else
            @test frac(dxA - want) < 1e-9
            @test frac(dyA - want) < 1e-9
        end
    end

    # `_pic_green_lattice!` now refuses a fractional separation instead of rounding
    let s = PICPoissonSolver(; grid=(nx, ny), green_type=:lattice)
        sg, fg = Octopus._pic_interaction_grids(s, -3.0e-4, 2.5e-4, -2.0e-5, 3.0e-5,
                                                   -1.0e-4, 4.0e-4, -4.0e-5, 1.0e-5)
        hx = sg.width / (nx - 1); hy = sg.height / (ny - 1)
        g = Matrix{Float64}(undef, 2nx, 2ny)
        @test Octopus._pic_green_lattice!(g, fg.x0, fg.y0, sg.x0, sg.y0, hx, hy, nx, ny) === g
        @test_throws ArgumentError Octopus._pic_green_lattice!(
            g, fg.x0 + 0.4 * hx, fg.y0, sg.x0, sg.y0, hx, hy, nx, ny)
    end

    # end to end: the combination that carried the defect is the DEFAULT cache
    sl = LongitudinalSlicing(nslices=4, method=:normal_quantile, center_position=:centroid)
    mk() = begin
        set_global_rng!(seed=91, method=:philox)
        e = Beam(2000, CPUThreadsBackend, Float64; beta=(0.55, 0.056, 12.7),
            alpha=(0.0, 0.0, 0.0), sigma=(106.0e-6, 9.5e-6, 7.0e-3), cutoff=5.0,
            rng_id=1, charge=-1.0, mc2=EMASS_EV, E0=10.0e9, r0=RE * ME0 / EMASS_EV, npart=1.7e11)
        p = Beam(2000, CPUThreadsBackend, Float64; beta=(0.8, 0.072, 90.9),
            alpha=(0.0, 0.0, 0.0), sigma=(95.0e-6, 8.5e-6, 6.0e-2), cutoff=5.0,
            rng_id=2, charge=1.0, mc2=PMASS_EV, E0=275.0e9, r0=RE * ME0 / PMASS_EV, npart=0.7e11)
        (e, p)
    end
    for gt in (:lattice, :standard, :integrated)
        e, p = mk()
        l = collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), green_type=gt,
                                        green_cache=:slice_pair), e, p, CPUThreadsBackend)
        @test isfinite(l) && all(isfinite, vcat(coordinate_arrays(e)...))
    end
end

@testset "grid_extent is rejected, not ignored, where no estimator runs" begin
    # `grid_extent` is consumed by `_pic_axis_extent`, which only the per-slice-pair
    # sizing path calls. `:source_slice` sizes from `_pic_union_bounds` and `:node`
    # from `_pic_build_node_grids!`, both plain min/max -- so a non-default value was
    # accepted and produced BIT-IDENTICAL results. Same class as the hybrid solver's
    # dropped `grid_extent` (audit part 2 S8), and rejected the same way.
    for ig in (:node, :source_slice)
        @test_throws ArgumentError PICPoissonSolver(interaction_grid=ig, grid_extent=:sigma)
        @test PICPoissonSolver(interaction_grid=ig).grid_extent === :extrema
        @test PICPoissonSolver(interaction_grid=ig, grid_extent=:extrema).interaction_grid === ig
    end
    # the mode that DOES read it keeps working -- otherwise the check above would
    # pass by forbidding the option outright
    @test PICPoissonSolver(interaction_grid=:slice_pair, grid_extent=:sigma).grid_extent === :sigma
end

@testset "Dropped PIC charge reaches a reader" begin
    # `_PICCPUWorkspace.dropped` documented itself as "Never silent", `grid_extent`'s
    # option metadata promises out-of-range particles are "dropped and counted", and
    # validation/README.md says the count must stay at zero in production. The
    # counter was incremented in `_pic_interaction!` and read by NOTHING in the
    # repository -- the one validation script with a `dropped` column recomputes its
    # own from `_pic_axis_extent`.
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
    run(; kw...) = begin
        e, p = mk()
        collide!(PICPoissonSolver(; slicing=sl, grid=(64, 64), kw...), e, p, CPUThreadsBackend)
    end
    # the default covers every particle by construction, so it must stay silent
    @test_logs run()
    @test_logs run(grid_extent=:extrema)
    # a deliberately under-covering estimator must not be silent, and the
    # count it reports must be a real one — the bare (:warn,) pin passed
    # with any message carrying any count (2026-08-05 audit, U17-8)
    dropped_logs, _ = Test.collect_test_logs() do
        run(grid_extent=:sigma, grid_extent_sigma=1.5)
    end
    dropped_warns = [l for l in dropped_logs
                     if occursin("dropped particles", string(l.message))]
    @test !isempty(dropped_warns)
    @test all(l -> l.kwargs[:dropped] isa Integer && l.kwargs[:dropped] > 0,
              dropped_warns)

    # and the count is against the MESH, not the estimator box: the mesh carries
    # 1.5 cells of margin, so a particle in the margin is interpolated, not dropped
    @test Octopus._pic_count_outside_box([0.5, 1.5, 2.5], [1.5, 1.5, 1.5],
                                         1.0, 2.0, 1.0, 2.0) == 2
    @test Octopus._pic_count_outside_box([1.0, NaN, 2.0], [1.5, 1.5, 1.5],
                                         1.0, 2.0, 1.0, 2.0) == 1
    # per PARTICLE, not per axis: a corner escapee — outside in both x and y —
    # used to increment the counter by 2 (2026-08-05 audit, U5-6)
    @test Octopus._pic_count_outside_box([5.0], [5.0], 1.0, 2.0, 1.0, 2.0) == 1
    # the drifted variant counts each source particle once, however many of the
    # sL/sR deposit planes (or axes) miss the box (2026-08-05 audit, U5-5/U5-6)
    @test Octopus._pic_count_outside_box_drifted(
        [1.5], [10.0], [1.5], [10.0], 0.1, -0.1, 1.0, 2.0, 1.0, 2.0) == 1

    # SOURCE-side drops are counted too: under grid_extent = :sigma a source
    # outlier's charge is dropped by the deposit's zero-weight branch, and that
    # used to leave dropped == 0 with ~1 particle-charge silently missing from
    # the field (2026-08-05 audit, U5-5).
    let nx = 32, ny = 32
        solver = PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, grid=(nx, ny),
                                  green_cache=:none, grid_extent=:sigma,
                                  grid_extent_sigma=2.0)
        nsrc = 4001
        sx = [i <= 2000 ? -1.0e-4 : 1.0e-4 for i in 1:4000]
        push!(sx, 3.0e-3)                        # one source outlier at ~30 sigma
        sy = [isodd(i) ? -1.0e-4 : 1.0e-4 for i in 1:nsrc]
        source = (x=sx, px=zeros(nsrc), y=sy, py=zeros(nsrc),
                  z=zeros(nsrc), pz=zeros(nsrc))
        nf = 1000
        fx = [isodd(i) ? -1.0e-4 : 1.0e-4 for i in 1:nf]
        fy = [i % 4 < 2 ? -1.0e-4 : 1.0e-4 for i in 1:nf]
        field = (x=fx, px=zeros(nf), y=fy, py=zeros(nf), z=zeros(nf), pz=zeros(nf))
        param = (weight=1.0, lb=-1.0e-3, center=0.0, rb=1.0e-3)
        ws = Octopus._pic_cpu_workspace(Float64, nx, ny)
        ws.dropped[] = 0
        Octopus._pic_interaction!(solver, source, param, field, param, 1.0e-6,
                                  ws, nothing, nothing)
        @test ws.dropped[] == 1                          # was 0
        @test isapprox(nsrc - sum(ws.charge), 1.0; atol=1e-9)  # the missing charge
    end

    # 2026-08-05_b audit, U6-1. Everything above runs on interaction_grid =
    # :slice_pair with grid_extent = :sigma. The counting used to be gated on
    # `grid_extent !== :extrema`, while `_validate_pic_solver` REJECTS any
    # non-:extrema grid_extent for :node and :source_slice -- so in exactly the
    # two modes whose meshes are built before the collision (at turn start, and
    # at the source slice's first use) and deposited into after the
    # intra-collision kicks, the tripwire was structurally unreachable. Measured
    # on an EIC-like pair: 2 of 1,800,000 source deposits outside the mesh under
    # :node with dropped == 0 and no warning.
    #
    # Reachability is what this pins, and it is asserted by injection rather
    # than by hoping a particle escapes: with the counters forced to report,
    # :node and :source_slice must produce a nonzero tally and :slice_pair must
    # not (there `:extrema` covers by construction, and the block is skipped on
    # purpose so the default path pays nothing).
    let nx = 8, ny = 8
        solver = PICPoissonSolver(kbb1=1.0e-6, kbb2=1.0e-6, luminosity_scale=1.0,
            grid=(nx, ny), green_cache=:none, interaction_grid=:node,
            slicing=LongitudinalSlicing(nslices=2, method=:equal_count))
        ns = 800
        sx = [1.0e-4 * sin(0.7i) for i in 1:ns]
        sy = [1.0e-4 * sin(0.31i) for i in 1:ns]
        source = (x=sx, px=zeros(ns), y=sy, py=zeros(ns),
                  z=zeros(ns), pz=zeros(ns), weight=fill(1.0, ns))
        nf = 400
        field = (x=[1.0e-4 * sin(1.1i) for i in 1:nf], px=zeros(nf),
                 y=[1.0e-4 * sin(0.53i) for i in 1:nf], py=zeros(nf),
                 z=zeros(nf), pz=zeros(nf))
        param = (weight=1.0, lb=-1.0e-3, center=0.0, rb=1.0e-3)
        cache = Dict{Int,Any}()
        Octopus._pic_build_node_grids!(cache, solver, Float64, source, 0.0,
                                       (x=field.x, px=field.px, y=field.y, py=field.py,
                                        z=field.z, pz=field.pz),
                                       1:nf, [-1.0e-3, 0.0, 1.0e-3])
        gL, gR = cache[1], cache[2]
        ws = Octopus._pic_cpu_workspace(Float64, nx, ny)

        ws.dropped[] = 0
        Octopus._pic_interaction_node!(solver, source, param, field, param,
                                       1.0e-6, ws, gL, gR)
        before = ws.dropped[]

        # The mechanism itself: the node mesh is built at TURN START and
        # deposited into after the intra-collision kicks have moved the
        # particles. Displacing one source particle far past the mesh
        # reproduces that, and it must be counted rather than vanishing through
        # the zero-weight branch. Before the fix this path carried no counting
        # call of any kind, so BOTH numbers were 0 and the difference could not
        # exist -- which is what makes the increase, not the absolute value,
        # the assertion worth pinning.
        source.x[1] = 1.0e3
        ws.dropped[] = 0
        Octopus._pic_interaction_node!(solver, source, param, field, param,
                                       1.0e-6, ws, gL, gR)
        @test ws.dropped[] > before
    end
end
