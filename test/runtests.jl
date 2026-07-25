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
