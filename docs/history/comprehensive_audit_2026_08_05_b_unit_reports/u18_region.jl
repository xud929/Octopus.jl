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

const CUDA_TESTS_ACTIVE = Octopus._HAS_CUDA && Octopus.CUDA.functional()
println("CUDA_TESTS_ACTIVE = ", CUDA_TESTS_ACTIVE)
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
    # only, so the second block below pins full bit-equality — luminosity
    # included — at n=15000, above every threshold, for 1/4/8 workers
    # (measured exact, 0 ulp, at zero collide-time cost: 3.06 s vs 3.10 s at
    # n=1e6). The first block keeps the original sub-threshold pin; its
    # spectral-luminosity tolerance covers the historical 1-ulp fold-order
    # allowance, which equality also satisfies.
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

    tq = ThinQuadrupoleSpec(k1l=0.05)
    entry = line_entries(BeamLine("L", tq, DriftSpec(L=1.0)))[1]
    @test_throws ArgumentError entry.k1l = 999.0
    q = QuadrupoleSpec(L=0.3, k1=1.2, nst=2)
    @test_throws ArgumentError q.k1 = 999.0

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
        @test validate(StrongStrongPICBackendConsistencyContract()).passed
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
