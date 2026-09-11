# Mode degeneracy theory: derivation record and reproducible checks

Date: 2026-09-11. Scope: the documentation-only addition of Section 13
("Mode degeneracy") to [the theory note](../theory/twiss_dispersion.md) and
the creation of [the analysis design note](../design/twiss_dispersion_analysis.md).
No analysis, API, option, contract, or tracking code changed; the analysis
layer still holds only `PlaceholderAnalysis`.

## Coverage and provenance

Section 13 ports the owner's working notes on canonical dispersion at mode
degeneracy (September 2026, unpublished; numbered research trials 012 and
014–022 and a Schur-subspace extraction prototype) into the theory note's own
conventions, which the working notes already share: $M_6\mathbf u=e^{-i\mu}\mathbf u$,
$\mathbf u^\dagger S_6\mathbf u=-2i$, $U=[\operatorname{Re}\mathbf u,-\operatorname{Im}\mathbf u]$.
The research prototype and the trial documents use the conjugate convention
($e^{+i\mu}$, $V^\dagger J V=+2i$, $V=\overline{U}$); only real outputs
(projector, covariance, ambiguity-set center and shape, tunes, Gram spectrum)
were carried over, and every complex quantity was re-derived in the note's
convention. The Krein-signature statements cite Qin, Chung, Davidson, and
Burby (2015), Sec. II.

The 2026-09-11 design review that produced the design note ran ten reader
reports (theory Sections 1–7, 8, 9–12; the degeneracy notes, finding,
clarifications and prototype; the canonical-dispersion note, its verification
oracle and trials; the repository's object protocol, option certification,
weak-dependency rule, tracking and Jacobian machinery, test mechanics, and
ledger rules), three independent designs, three judges, one synthesis, and
four adversarial verifications (repository facts, theory fidelity, degeneracy
robustness, process compliance). The corrections those verifications forced
are listed in the design note's Provenance section. The review's intermediate
artefacts are not repository evidence; the evidence for Section 13 is the
probe below.

## Reproduction

Run from the repository root. The Julia code uses only standard libraries,
loads no Octopus implementation, fixes the random seed and the BLAS thread
count, and asserts every identity it prints. Matrix residuals are Frobenius
norms divided by `max(1, norm(expected))` in dimensionless synthetic
coordinates; the default assertion tolerance is `1e-10`, with tighter
tolerances stated per check. The rolled FODO cell is rebuilt analytically from
the thick-lens quadrupole and drift maps of the MAD-X deck in Section 13.10;
its tune and Gram minimum are pinned to the values the working notes obtained
from the MAD-X 5.09.03 exported map, so agreement to `1e-13` and `1e-12`
respectively is an independent confirmation of both the rebuild and the
degeneracy construction.

```bash
julia --startup-file=no --project=. --threads=4 -e 'text = read("docs/history/twiss_dispersion_degeneracy_theory_2026_09_11.md", String); code = match(r"(?s)<!-- degeneracy-probe-start -->\n```julia\n(.*?)\n```", text).captures[1]; include_string(Main, code, "degeneracy_probe.jl")'
```

Identity coverage, by Section 13 label: N1 (bounded powers of a semisimple
degenerate map, with a Jordan-block negative control), N2 (Gram inertia
basis-independent, conjugation flips it), N3 (splitting from the Hermitian
phase generator), N4–N6 (collective normalization, group projector and
covariance and their invariance under unitary mixing, the group version of
E12), N7 (four-dimensional equal pair), N9 (resolvent contour projector),
N10–N14 (every sampled mode lies on the ellipsoid surface; the scalar-readout
extrema equal the Hermitian-form eigenvalues; three-mode filled ellipsoid),
N15 (indefinite family: eigenvalue, norm, unbounded $\eta_x$, Gram signs),
N16–N18 (singular polynomial coefficient, the false graph with zero polynomial
residual and nonzero invariance residual, the pseudoinverse counterexample, the
singular Newton operator), N19–N21 (minimal-polynomial residual, normalized
frame, unitary restricted map at exact and split degeneracy), N22 (the
orientation-chord distance identity), and the Section 13.10 FODO cell with its
detuned controls. Not checked here: the finite-resolution covariance channel
of the working notes' trial 016, the Hausdorff stability bound of trial 019,
and any Octopus tracked lattice; those remain for the implementation's own
tests and benchmarks.

<!-- degeneracy-probe-start -->
```julia
using LinearAlgebra, Random

function run_degeneracy_checks()
    BLAS.set_num_threads(1)
    rng = MersenneTwister(20260911)
    eye(n) = Matrix{Float64}(I, n, n)
    J2 = [0.0 1.0; -1.0 0.0]
    S4, S6 = kron(eye(2), J2), kron(eye(3), J2)
    rot(mu) = [cos(mu) sin(mu); -sin(mu) cos(mu)]
    function bd(ms...)
        n = sum(size(m, 1) for m in ms)
        out = zeros(promote_type(map(eltype, ms)...), n, n)
        i = 1
        for m in ms
            r = i:i + size(m, 1) - 1
            out[r, r] = m
            i += size(m, 1)
        end
        out
    end
    maxima = Dict{String,Float64}()
    counts = Dict{String,Int}()
    function check(name, actual, expected; tol=1e-10)
        residual = norm(actual - expected) / max(1.0, norm(expected))
        @assert isfinite(residual) && residual <= tol (name, residual, tol)
        maxima[name] = max(get(maxima, name, 0.0), residual)
        counts[name] = get(counts, name, 0) + 1
        residual
    end
    randsymp(n, scale) = (K = randn(rng, n, n); exp(scale * (n == 6 ? S6 : S4) * (K + K')))
    # Oriented cluster basis: ordered complex Schur, eigenvalues within `radius`
    # of `center`, excluding the conjugate group. Returns the orthonormal basis
    # Q_c and the Gram matrix H_c = (i/2) Q_c' S Q_c of Section 13.
    function cluster_basis(M, S, center, radius)
        F = schur(complex(M))
        sel = [abs(z - center) < radius for z in F.values]
        m = count(sel)
        @assert 1 <= m <= size(M, 1) ÷ 2 "circle must isolate an admissible cluster"
        Fo = ordschur(F, sel)
        Q = Fo.Z[:, 1:m]
        H = (im / 2) * (Q' * S * Q)
        H = (H + H') / 2
        return Q, H, Fo.values[1:m]
    end
    function normalize_cluster(Q, H, S)
        lam, V = eigen(Hermitian(H))
        @assert minimum(lam) > 0 "cluster Gram is not positive definite"
        U = Q * (V * Diagonal(1 ./ sqrt.(lam)) * V')      # U_c = Q_c H_c^{-1/2}
        P = -imag(U * U') * S                              # P_c
        G = real(U * U')                                   # G_c
        return U, P, G
    end
    ambiguity(P, G) = (P[1:4, 6] / 2,                      # eta_mid = (P_c)_{r,p_z}/2
                       (G[5, 5] * G[1:4, 1:4] - G[1:4, 5] * G[5, 1:4]') / 4)  # A_eta
    eta_of(u) = -imag(u * u')[1:4, 5]                      # (D12): eta_a = -Im(u_z^* u_a)

    # ---- N1: semisimple degeneracy keeps powers bounded; a Jordan block does not.
    mu, gam = 0.73, 1.41
    for trial in 1:20
        W = randsymp(6, 0.15)
        M = W * bd(rot(mu), rot(gam), rot(mu)) / W
        bound = opnorm(W) * opnorm(inv(W))
        Mn = eye(6)
        worst = 0.0
        for n in 1:400
            Mn = M * Mn
            worst = max(worst, opnorm(Mn) / bound)
        end
        @assert worst <= 1 + 1e-9 ("N1 bounded powers", worst)
        counts["N1 bounded powers (ratio<=1)"] = get(counts, "N1 bounded powers (ratio<=1)", 0) + 1
        maxima["N1 bounded powers (ratio<=1)"] = max(get(maxima, "N1 bounded powers (ratio<=1)", 0.0), worst)
    end
    Jd = [rot(mu) 0.2*rot(mu); zeros(2, 2) rot(mu)]       # defective 4x4 block (interleaved below)
    perm = [1, 3, 2, 4]
    Jd = Jd[perm, perm]
    check("N1 negative control: defective block symplectic", Jd' * S4 * Jd, S4)
    growth = opnorm(Jd^400) / opnorm(Jd)
    @assert growth > 40 ("N1 Jordan growth", growth)

    # ---- N2: Gram inertia is basis independent; conjugation flips it.
    for trial in 1:50
        W = randsymp(6, 0.15)
        M = W * bd(rot(mu), rot(gam), rot(mu)) / W
        Q, H, _ = cluster_basis(M, S6, exp(-im * mu), 0.2)
        A = randn(rng, 2, 2) + im * randn(rng, 2, 2)      # arbitrary basis change
        Qa = Q * A
        Ha = (im / 2) * (Qa' * S6 * Qa); Ha = (Ha + Ha') / 2
        s1 = sort(sign.(eigvals(Hermitian(H)))); s2 = sort(sign.(eigvals(Hermitian(Ha))))
        check("N2 Gram inertia basis independent", s1, s2; tol=0.0)
        Qc, Hc, _ = cluster_basis(M, S6, exp(+im * mu), 0.2)
        check("N2 conjugate cluster flips inertia", sort(sign.(eigvals(Hermitian(Hc)))), -s1; tol=0.0)
        @assert minimum(eigvals(Hermitian(H))) > 0
    end

    # ---- N4/N5/N6/N9/N20/N21: collective normalization and group quantities.
    for trial in 1:50
        W = randsymp(6, 0.15)
        M = W * bd(rot(mu), rot(gam), rot(mu)) / W
        Q, H, lams = cluster_basis(M, S6, exp(-im * mu), 0.2)
        U, P, G = normalize_cluster(Q, H, S6)
        check("N4 U_c' S U_c = -2i I", U' * S6 * U, -2im * eye(2))
        check("N4 U_c^T S U_c = 0", transpose(U) * S6 * U, zeros(2, 2))
        check("N20 columns are eigenvectors at exact degeneracy", M * U, exp(-im * mu) * U)
        V = qr(randn(rng, 2, 2) + im * randn(rng, 2, 2)).Q * I   # random unitary mixing
        Um = U * V
        check("N5 P_c invariant under unitary mixing", -imag(Um * Um') * S6, P)
        check("N5 G_c invariant under unitary mixing", real(Um * Um'), G)
        check("N5 P_c idempotent", P * P, P)
        check("N5 P_c commutes with M", M * P, P * M)
        check("N5 M G_c M^T = G_c", M * G * M', G)
        check("N5 P_c symplectic adjoint", P' * S6, S6 * P)
        check("N6 G_c = -(M - M^-1) P_c S/(2 sin mu)", -(M - inv(M)) * P * S6 / (2sin(mu)), G)
        # N9: resolvent contour integral around the oriented cluster equals (i/2) U_c U_c' S.
        nq = 400; Pi = zeros(ComplexF64, 6, 6); r = 0.2
        for k in 0:nq-1
            th = 2pi * k / nq
            z = exp(-im * mu) + r * exp(im * th)
            Pi += inv(z * eye(6) - M) * (im * r * exp(im * th)) * (2pi / nq)
        end
        Pi /= 2pi * im
        check("N9 contour projector = (i/2) U_c U_c' S", Pi, (im / 2) * U * U' * S6)
        check("N9 P_c = 2 Re Pi_c", 2 * real(Pi), P)
        # N21: restricted map is unitary with the cluster phase.
        T = (im / 2) * (U' * S6 * M * U)
        check("N21 restricted map unitary", T' * T, eye(2))
        check("N21 restricted map = e^{-i mu} I at exact degeneracy", T, exp(-im * mu) * eye(2))
        # N19: minimal-polynomial residual vanishes on the cluster.
        check("N19 minimal polynomial annihilates cluster", (M * M - 2cos(mu) * M + eye(6)) * P, zeros(6, 6))
    end

    # ---- N7: four-dimensional equal pair.
    for trial in 1:50
        W4 = randsymp(4, 0.2)
        M4 = W4 * bd(rot(mu), rot(mu)) / W4
        Q, H, _ = cluster_basis(M4, S4, exp(-im * mu), 0.2)
        U, P, G = normalize_cluster(Q, H, S4)
        check("N7 P_c = I_4", P, eye(4))
        check("N7 M^2 - tau M + I = 0", M4 * M4 - 2cos(mu) * M4 + eye(4), zeros(4, 4))
        check("N7 G_c = -(M - cos mu I) S/sin mu", -(M4 - cos(mu) * eye(4)) * S4 / sin(mu), G)
        check("N7 G_c = W W^T", G, W4 * W4')
    end

    # ---- N10-N14: the dispersion ambiguity set of a definite synchrobetatron cluster.
    for trial in 1:30
        W = randsymp(6, 0.15)
        M = W * bd(rot(mu), rot(gam), rot(mu)) / W
        Q, H, _ = cluster_basis(M, S6, exp(-im * mu), 0.2)
        U, P, G = normalize_cluster(Q, H, S6)
        c0, A = ambiguity(P, G)
        A = (A + A') / 2
        @assert minimum(eigvals(Symmetric(A))) > -1e-12
        Ap = pinv(A; rtol=1e-10)
        for sample in 1:40
            c = randn(rng, 2) + im * randn(rng, 2); c /= norm(c)
            u = U * c
            check("N10 sampled mode is normalized eigenvector", M * u, exp(-im * mu) * u)
            check("N10 sampled mode norm -2i", [dot(u, S6 * u)], [-2im])
            eta = eta_of(u)
            check("N12 sample lies on the ellipsoid surface", [(eta - c0)' * Ap * (eta - c0)], [1.0])
            check("N12 sample lies in the range of A_eta", A * (Ap * (eta - c0)), eta - c0)
        end
        for k in 1:6
            a = randn(rng, 4)
            # a' eta(c) = c' K c with K Hermitian: extrema are its eigenvalues (N14).
            K = zeros(ComplexF64, 2, 2)
            for i in 1:2, j in 1:2
                ei = zeros(ComplexF64, 2); ej = zeros(ComplexF64, 2); ei[i] = 1; ej[j] = 1
                # bilinear form of eta_a(c) = -Im( (U c)(U c)^dagger )_{a,z} = -Im( sum_a a_a (U c)_a conj((U c)_z) )
                K[i, j] = (-1 / (2im)) * (dot(a, U[1:4, i]) * conj(U[5, j]) - conj(dot(a, U[1:4, j]) * conj(U[5, i])))
            end
            K = (K + K') / 2
            lam = eigvals(Hermitian(K))
            half = sqrt(max(0.0, dot(a, A * a)))
            check("N14 scalar interval endpoints", [minimum(lam), maximum(lam)], [dot(a, c0) - half, dot(a, c0) + half])
        end
    end
    # Three-mode definite degeneracy: filled four-dimensional ellipsoid.
    for trial in 1:10
        W = randsymp(6, 0.15)
        M = W * bd(rot(mu), rot(mu), rot(mu)) / W
        Q, H, _ = cluster_basis(M, S6, exp(-im * mu), 0.2)
        @assert size(Q, 2) == 3
        U, P, G = normalize_cluster(Q, H, S6)
        c0, A = ambiguity(P, G)
        check("N13 three-mode P_c = I_6", P, eye(6))
        check("N13 three-mode center = 0", c0, zeros(4))
        Ai = inv(Symmetric((A + A') / 2))
        best = 0.0
        for sample in 1:400
            c = randn(rng, 3) + im * randn(rng, 3); c /= norm(c)
            eta = eta_of(U * c)
            q = dot(eta, Ai * eta)
            @assert q <= 1 + 1e-9 ("N13 inside ellipsoid", q)
            best = max(best, q)
        end
        maxima["N13 three-mode ellipsoid (max sampled q<=1)"] = max(get(maxima, "N13 three-mode ellipsoid (max sampled q<=1)", 0.0), best)
        counts["N13 three-mode ellipsoid (max sampled q<=1)"] = get(counts, "N13 three-mode ellipsoid (max sampled q<=1)", 0) + 1
    end

    # ---- N15: indefinite semisimple degeneracy has unbounded canonical dispersion.
    let mu2 = 1.9, M = bd(rot(mu), rot(mu2), rot(-mu))
        ex, epx, ez, epz = eye(6)[:, 1], eye(6)[:, 2], eye(6)[:, 5], eye(6)[:, 6]
        for t in (0.0, 0.5, 1.0, 2.0, 4.0)
            u = im * sinh(t) * (ex + im * epx) + cosh(t) * (ez - im * epz)
            check("N15 indefinite family: eigenvalue e^{+i mu}, oriented phase -mu", M * u, exp(+im * mu) * u)
            check("N15 indefinite family: norm -2i", [dot(u, S6 * u)], [-2im])
            eta = eta_of(u)
            h = -imag(conj(u[5]) * u[6])
            check("N15 eta_x(t) = -sinh t cosh t", [eta[1]], [-sinh(t) * cosh(t)]; tol=1e-12)
            check("N15 h(t) = cosh^2 t", [h], [cosh(t)^2]; tol=1e-12)
        end
        Q, H, _ = cluster_basis(M, S6, exp(+im * mu), 0.2)
        lam = eigvals(Hermitian(H))
        @assert size(Q, 2) == 2 && minimum(lam) < 0 < maximum(lam) "N15 Gram must be indefinite"
        check("N15 indefinite Gram eigenvalues (orthonormal basis: +-1/2)", sort(lam), [-0.5, 0.5]; tol=1e-12)
        counts["N15 indefinite Gram (signs +,-)"] = 1; maxima["N15 indefinite Gram (signs +,-)"] = 0.0
    end

    # ---- N16-N18: polynomial kernel is not sufficient at a repeated selected pair.
    let M = bd(rot(mu), rot(gam), rot(mu))
        A, B, C, E = M[1:4, 1:4], M[1:4, 5:6], M[5:6, 1:4], M[5:6, 5:6]
        tau_s = 2cos(mu)
        poly = M * M - tau_s * M + eye(6)
        check("N16 det of (D19) coefficient vanishes", [det(poly[1:4, 1:4])], [0.0]; tol=1e-12)
        for t in (1.0, 0.1, 1e-2, 1e-4, 1e-6, 1e-8)
            D = zeros(4, 2); D[1, 1] = 1.0; D[2, 2] = -1 + t
            check("N17 polynomial residual of false graph", poly * vcat(D, eye(2)), zeros(6, 2); tol=1e-13)
            F = A * D + B - D * (C * D + E)
            check("N17 invariance residual = sqrt2 |sin mu| |2 - t|", [norm(F)], [sqrt(2) * abs(sin(mu)) * abs(2 - t)]; tol=1e-12)
        end
        # Pseudoinverse counterexample with the thin crab similarity p_x -> p_x - k z, p_z -> p_z - k x.
        k = 0.3
        Ck = eye(6); Ck[2, 5] = -k; Ck[6, 1] = -k
        check("N17 crab kick symplectic", Ck' * S6 * Ck, S6)
        Mk = Ck * M / Ck
        polyk = Mk * Mk - tau_s * Mk + eye(6)
        Dmp = -pinv(polyk[1:4, 1:4]; rtol=1e-12) * polyk[1:4, 5:6]
        check("N17 pseudoinverse graph is zero", Dmp, zeros(4, 2); tol=1e-12)
        Ak, Bk, Ckk, Ek = Mk[1:4, 1:4], Mk[1:4, 5:6], Mk[5:6, 1:4], Mk[5:6, 5:6]
        Fk = Ak * Dmp + Bk - Dmp * (Ckk * Dmp + Ek)
        check("N17 pseudoinverse invariance residual", [norm(Fk)], [sqrt(2) * k * sin(mu)]; tol=1e-12)
        # N18: Newton operator determinant (tau_1 - tau_s)^2 (tau_2 - tau_s)^2 vanishes here.
        Dtrue = zeros(4, 2)                                   # the plane {r = 0}? no: true planes are aI + bS2 in x rows
        Dtrue[1:2, 1:2] = 0.3 * eye(2) + 0.2 * J2
        L = kron(eye(2), A - Dtrue * C) - kron(transpose(E + C * Dtrue), eye(4))
        check("N18 Newton operator singular at repeated selected pair", [det(L)], [0.0]; tol=1e-10)
        F = A * Dtrue + B - Dtrue * (C * Dtrue + E)
        check("N18 true graph family is invariant", F, zeros(4, 2))
    end

    # ---- N3: splitting of a definite cluster from its Hermitian phase generator.
    for trial in 1:50
        delta = 10.0^(-1 - rand(rng) * 5)
        W = randsymp(6, 0.15)
        M = W * bd(rot(mu + delta), rot(gam), rot(mu - delta)) / W
        Q, H, _ = cluster_basis(M, S6, exp(-im * mu), 0.2)
        U, P, G = normalize_cluster(Q, H, S6)
        T = (im / 2) * (U' * S6 * M * U)
        check("N21 split cluster restricted map unitary", T' * T, eye(2))
        Hp = im * log(T)                                      # T = exp(-i Hp), Hp Hermitian on the local branch
        Hp = (Hp + Hp') / 2
        split = sqrt((real(Hp[1, 1]) - real(Hp[2, 2]))^2 + 4abs2(Hp[1, 2]))
        check("N3 splitting from the phase generator", [split], [2delta]; tol=1e-8)
        # N5 (split): group projector equals the sum of the two (D26)-type individual projectors.
        taus = 2cos.([mu + delta, gam, mu - delta])
        Z = M + inv(M)
        Pj(j) = prod((Z - taus[k] * eye(6)) / (taus[j] - taus[k]) for k in 1:3 if k != j)
        if delta > 1e-3
            check("N5 split: P_c = P_1 + P_3", P, Pj(1) + Pj(3); tol=1e-8)
        end
    end

    # ---- N22: Trial-016 distance identity in the normalized cluster representation.
    sig = ([0.0 1.0; 1.0 0.0], [0.0 -im; im 0.0], [1.0 0.0; 0.0 -1.0])
    for trial in 1:100
        delta = rand(rng) * 0.3
        n0 = randn(rng, 3); n0 /= norm(n0); n1 = randn(rng, 3); n1 /= norm(n1)
        # Restricted map (N21) with oriented phases mu +- delta, in the note's e^{-i mu} convention.
        Tn(n) = exp(-im * mu) * (cos(delta) * eye(2) - im * sin(delta) * sum(n[k] * sig[k] for k in 1:3))
        check("N22 restricted map unitary with phases mu+-delta", sort(mod.(-angle.(eigvals(Tn(n0))), 2pi)), sort([mu - delta, mu + delta]); tol=1e-12)
        check("N22 ||T(n)-T(n0)||_2 = |sin delta| ||n - n0||", [opnorm(Tn(n1) - Tn(n0))], [abs(sin(delta)) * norm(n1 - n0)]; tol=1e-12)
    end

    # ---- Rotated equal-tune FODO (Section 13.10): analytic rebuild of the MAD-X cell.
    let L = 0.2, k = 1.0, w = sqrt(abs(k)), a = w * L
        QF = [cos(a) sin(a)/w; -w*sin(a) cos(a)]
        QD = [cosh(a) sinh(a)/w; w*sinh(a) cosh(a)]
        Dr = [1.0 1.0; 0.0 1.0]
        Ax = Dr * QD * Dr * QF
        Ay = Dr * QF * Dr * QD
        th = pi / 4
        Rt = kron([cos(th) -sin(th); sin(th) cos(th)], eye(2))
        M4 = Rt * bd(Ax, Ay) * Rt'
        check("FODO rolled cell symplectic", M4' * S4 * M4, S4)
        cosmu = tr(M4) / 4
        check("FODO cos mu", [cosmu], [0.9744003972058644]; tol=1e-13)
        Q = acos(cosmu) / (2pi)
        check("FODO tune", [Q], [0.0360896443733161]; tol=1e-13)
        # Edwards-Teng discriminant (T7) vanishes: T9 has no branch.
        adj(K) = -J2 * K' * J2
        Mxx, Mxy, Myx, Myy = M4[1:2, 1:2], M4[1:2, 3:4], M4[3:4, 1:2], M4[3:4, 3:4]
        Delta = (tr(Mxx) - tr(Myy))^2 + 4det(adj(Mxy) + Myx)
        check("FODO (T7) discriminant = 0", [Delta], [0.0]; tol=1e-13)
        check("FODO minimal polynomial M^2 - tau M + I = 0", M4 * M4 - 2cosmu * M4 + eye(4), zeros(4, 4); tol=1e-13)
        mu0 = acos(cosmu)
        Qb, H, _ = cluster_basis(M4, S4, exp(-im * mu0), 0.1)
        lam = eigvals(Hermitian(H))
        @assert size(Qb, 2) == 2
        check("FODO Krein minimum (paper 0.0838222432933016)", [minimum(lam)], [0.0838222432933016]; tol=1e-12)
        U, P, G = normalize_cluster(Qb, H, S4)
        check("FODO P_c = I_4", P, eye(4); tol=1e-13)
        Sig = -(M4 - cosmu * eye(4)) * S4 / sin(mu0)
        check("FODO matched covariance G_c", G, Sig; tol=1e-13)
        check("FODO covariance closes", M4 * Sig * M4', Sig; tol=1e-13)
        @assert minimum(eigvals(Symmetric(Sig))) > 0.08 "FODO covariance positive"
        # Detuned controls: K_D = -(1+eps) splits the pair; report the complex gap.
        # Detuned controls of trial 012: qd has k1 = -(1+eps); a quadrupole focuses in one
        # plane and defocuses in the other, so x sees quad(-1-eps) and y sees quad(+1+eps).
        for ep in (1e-3, 1e-6, 1e-9, 1e-12)
            wd = sqrt(1 + ep); ad = wd * L
            QDe = [cosh(ad) sinh(ad)/wd; wd*sinh(ad) cosh(ad)]          # quad(-1-eps), x plane
            QFe = [cos(ad) sin(ad)/wd; -wd*sin(ad) cos(ad)]             # quad(+1+eps), y plane
            Axe = Dr * QDe * Dr * QF; Aye = Dr * QFe * Dr * QD
            Me = Rt * bd(Axe, Aye) * Rt'
            check("FODO detuned cell symplectic", Me' * S4 * Me, S4; tol=1e-13)
            ev = eigvals(Me)
            up = sort(filter(z -> imag(z) > 0, ev); by=angle)
            g = abs(up[1] - up[2])
            println("FODO detuned eps=", ep, ": tune split=", abs(angle(up[1]) - angle(up[2])) / (2pi),
                    ", complex gap g=", g, ", |M|_2=", opnorm(Me), ", roundoff floor 4*eps(Float64)*|M|_2=", 4 * eps(Float64) * opnorm(Me),
                    ", q = 2*rho_M0/g at kappa=1: ", 2 * 4 * eps(Float64) * opnorm(Me) / g)
        end
    end

    println("Julia ", VERSION, "; CPU Float64; Julia threads=", Threads.nthreads(),
            "; BLAS threads=", BLAS.get_num_threads(), "; seed=20260911; default tol=1e-10")
    for name in sort(collect(keys(maxima)))
        println(name, " | ", counts[name], " | ", maxima[name])
    end
    println("Negative controls: Jordan growth, indefinite Gram, false polynomial graph, pseudoinverse graph. Matrix algebra only; no production analysis executed.")
end

run_degeneracy_checks()
```
<!-- degeneracy-probe-end -->

## Execution record

The probe completed with every assertion satisfied. Output
(`name | count | maximum scaled residual`, preceded by the detuned-FODO
control lines that the design note's resolution bracket is read from):

```text
FODO detuned eps=0.001: tune split=0.00033940285385235643, complex gap g=0.0021325306204530298, |M|_2=2.9801428603287623, roundoff floor 4*eps(Float64)*|M|_2=2.646898576167411e-15, q = 2*rho_M0/g at kappa=1: 2.482401472486346e-12
FODO detuned eps=1.0e-6: tune split=3.395666804700915e-7, complex gap g=2.1335603775281936e-6, |M|_2=2.979741542412905, roundoff floor 4*eps(Float64)*|M|_2=2.6465421342551077e-15, q = 2*rho_M0/g at kappa=1: 2.480869219479246e-9
FODO detuned eps=1.0e-9: tune split=3.3956704813337786e-10, complex gap g=2.1335626767667733e-9, |M|_2=2.9797411411029975, roundoff floor 4*eps(Float64)*|M|_2=2.646541777820308e-15, q = 2*rho_M0/g at kappa=1: 2.480866211843291e-6
FODO detuned eps=1.0e-12: tune split=3.397141620397067e-13, complex gap g=2.1344915847082592e-12, |M|_2=2.9797411407016865, roundoff floor 4*eps(Float64)*|M|_2=2.6465417774638724e-15, q = 2*rho_M0/g at kappa=1: 0.0024797865650293487
Julia 1.12.4; CPU Float64; Julia threads=4; BLAS threads=1; seed=20260911; default tol=1e-10
FODO (T7) discriminant = 0 | 1 | 6.162975822039155e-33
FODO Krein minimum (paper 0.0838222432933016) | 1 | 3.0531133177191805e-16
FODO P_c = I_4 | 1 | 6.382156824153034e-15
FODO cos mu | 1 | 0.0
FODO covariance closes | 1 | 5.1502049049037836e-17
FODO detuned cell symplectic | 4 | 3.3528285148408725e-16
FODO matched covariance G_c | 1 | 5.055055306129106e-15
FODO minimal polynomial M^2 - tau M + I = 0 | 1 | 5.637267261327198e-16
FODO rolled cell symplectic | 1 | 1.2311736200577788e-16
FODO tune | 1 | 5.551115123125783e-17
N1 bounded powers (ratio<=1) | 20 | 0.9997893406625687
N1 negative control: defective block symplectic | 1 | 2.782023057015468e-17
N10 sampled mode is normalized eigenvector | 1200 | 2.5774617815899984e-15
N10 sampled mode norm -2i | 1200 | 1.554312554902249e-15
N12 sample lies in the range of A_eta | 1200 | 9.326232864572676e-15
N12 sample lies on the ellipsoid surface | 1200 | 1.2212453270876722e-14
N13 three-mode P_c = I_6 | 10 | 2.363930197937448e-15
N13 three-mode center = 0 | 10 | 1.536381426628689e-15
N13 three-mode ellipsoid (max sampled q<=1) | 10 | 0.9999999878964144
N14 scalar interval endpoints | 180 | 3.9706250529296014e-16
N15 eta_x(t) = -sinh t cosh t | 5 | 0.0
N15 h(t) = cosh^2 t | 5 | 0.0
N15 indefinite Gram (signs +,-) | 1 | 0.0
N15 indefinite Gram eigenvalues (orthonormal basis: +-1/2) | 1 | 2.0014830212433605e-16
N15 indefinite family: eigenvalue e^{+i mu}, oriented phase -mu | 5 | 0.0
N15 indefinite family: norm -2i | 5 | 1.1657341758564144e-13
N16 det of (D19) coefficient vanishes | 1 | 0.0
N17 crab kick symplectic | 1 | 0.0
N17 invariance residual = sqrt2 |sin mu| |2 - t| | 6 | 2.3544230555972015e-16
N17 polynomial residual of false graph | 6 | 0.0
N17 pseudoinverse graph is zero | 1 | 0.0
N17 pseudoinverse invariance residual | 1 | 0.0
N18 Newton operator singular at repeated selected pair | 1 | 0.0
N18 true graph family is invariant | 1 | 7.850462293418876e-17
N19 minimal polynomial annihilates cluster | 50 | 4.500993129116641e-15
N2 Gram inertia basis independent | 50 | 0.0
N2 conjugate cluster flips inertia | 50 | 0.0
N20 columns are eigenvectors at exact degeneracy | 50 | 2.269109943884652e-15
N21 restricted map = e^{-i mu} I at exact degeneracy | 50 | 9.741101236737946e-16
N21 restricted map unitary | 50 | 2.0039832794761065e-15
N21 split cluster restricted map unitary | 50 | 1.8213852836301737e-15
N22 restricted map unitary with phases mu+-delta | 100 | 3.4005498669568177e-16
N22 ||T(n)-T(n0)||_2 = |sin delta| ||n - n0|| | 100 | 1.942890293094024e-16
N3 splitting from the phase generator | 50 | 9.159339953157541e-16
N4 U_c' S U_c = -2i I | 50 | 1.0562335043677218e-15
N4 U_c^T S U_c = 0 | 50 | 2.67675652033176e-15
N5 G_c invariant under unitary mixing | 50 | 9.200651298371524e-16
N5 M G_c M^T = G_c | 50 | 3.541618574866344e-15
N5 P_c commutes with M | 50 | 1.934066282405354e-15
N5 P_c idempotent | 50 | 1.5132067995912836e-15
N5 P_c invariant under unitary mixing | 50 | 1.042963017602126e-15
N5 P_c symplectic adjoint | 50 | 0.0
N5 split: P_c = P_1 + P_3 | 15 | 2.0331115461790372e-14
N6 G_c = -(M - M^-1) P_c S/(2 sin mu) | 50 | 2.2539785798988687e-15
N7 G_c = -(M - cos mu I) S/sin mu | 50 | 2.0173191280602273e-15
N7 G_c = W W^T | 50 | 2.036755013094327e-15
N7 M^2 - tau M + I = 0 | 50 | 1.3988369538646852e-15
N7 P_c = I_4 | 50 | 2.0352616844985972e-15
N9 P_c = 2 Re Pi_c | 50 | 2.7846329018060516e-15
N9 contour projector = (i/2) U_c U_c' S | 50 | 3.056152042128432e-15
Negative controls: Jordan growth, indefinite Gram, false polynomial graph, pseudoinverse graph. Matrix algebra only; no production analysis executed.
```

The detuned-control lines give the numbers the design note uses for the
provisional resolution-chord default: complex gaps $2.13\times10^{-9}$ and
$2.13\times10^{-12}$ at $\varepsilon=10^{-9}$ and $10^{-12}$, and chords
$2.5\times10^{-6}$ and $2.5\times10^{-3}$ at unit normalizer conditioning
with a roundoff-level map error, whose geometric mean rounds to $10^{-4}$.

## Gate record

Documentation-only change (`git diff --name-only` names only `.md` files and
not `docs/registry_snapshot.md`): the targeted check is the `docs/README.md`
index entry, and the gate is the fast lane on the final tree. The fast-lane
result is appended below when it has run.

Result: fast lane (Pkg.test(test_args=["lane=fast"], julia_args=["--threads=4"])) on the final tree, 2026-09-11 15:45:47 to 15:59:54 on the shared CPU host, exit 0, 'Testing Octopus tests passed'; 15 heavyweight sections skipped by the lane, none of which carries a docs check: Element parameter effectiveness; Solver option effectiveness; script mode picks up the ForwardDiff rules; ForwardDiff differentiates the lattice; Curved frame x transverse field: every routing is a gradient; Every example script runs against the current interface; The multi-process seam runs under an MPI launcher; The developer harnesses run divided under an MPI launcher; Contract coverage guards: declared kinds, solver tree, broken baselines, unrun contracts; Lattice cells track and stay symplectic; CUDA GaussianPIC coupled subtraction matches CPU; Physics contracts; PIC green_type=:lattice; Green-cache expansion preserves the grid alignment its kernels require; PIC-family luminosity returns Float64 on every backend and precision. CUDA not active (a markdown-only change touches no device path). The verifier
corrections applied after the first lane run (the N22 convention, the N19
normalization note, the design-note wording, the todo status, and the
documentation guide's gate paragraph) were all on the tree this run gated;
only this paragraph was added afterwards.
