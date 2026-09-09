# Twiss/dispersion theory draft: review and reproducible checks

Date: 2026-09-08. Scope: the documentation-only introduction of
[the theory note](../theory/twiss_dispersion.md), based on the supplied
`octopus_twiss_dispersion_design.md` draft and the subsequent source/paper review.
No concrete analysis, API, contract, or tracking change is implemented.

## Coverage and provenance

The primary reviewer read the complete supplied draft and the repository's
longitudinal-convention implementation, analysis placeholder, documentation
routing, and applicable audit protocol. Mathematical scope: 4D parameterizations,
6D invariant-plane solution and canonical separation, mode propagation,
Ohmi conversion, pinned Xsuite source construction/readout, and the GLSF
linear application. Radiation equilibrium and nonlinear GLSF performance
are outside scope.

An independent read-only neighbour review covered new Sections 3.4, 7.5,
9.4–9.5, and 10.5 against their inherited definitions, emphasizing signs,
mode identity, chart restrictions, and proposed-versus-implemented wording.
Source-route attribution for Xsuite was checked directly by the primary
reviewer at the commit linked in the note, including the full-6D eigenvector
construction and the separate forced-response four-dimensional branch.
The review caught single-dollar display delimiters in inserted equations;
these were corrected before the gate. Algebra and cross-reference checks
are reported separately from production software validation.

The original draft's numerical table is not copied as evidence because its
original scripts were not supplied. The reproducible probe below replaces
that evidence for its explicitly enumerated identities only. In particular,
it does not check every inherited component-expanded covariance expression,
every Edwards–Teng propagation form, or an Octopus tracked lattice.

## Reproduction

Run from the repository root. The Julia code uses only standard libraries,
loads no Octopus implementation, and fixes the random seed and BLAS thread
count. Matrix errors are Frobenius residuals divided by
`max(1, norm(expected))`, in dimensionless synthetic coordinates; the default
assertion tolerance is `1e-10`. The ideal integer GLSF matrix is checked
exactly. Iterations stop at an absolute Riccati residual of `1e-13`, with
100 steps as a test limit, not a general convergence claim.

The 204 transverse fixtures include independently exponentiated symplectic
normalizers and explicit negative-determinant coupling in both forms.
Both phase orientations are tested. The 100 six-dimensional fixtures are
weak-coupling maps with prescribed distinct phases; all must complete both
iterations and the positive-area Ohmi checks. Ineligible Edwards–Teng charts
are deliberately not evaluated; each form's actual coverage count is printed.
Separate fixtures cover negative/zero area, singular GLSF projection, and
three wrong-convention controls. Xsuite checks here verify the readout algebra,
not execution of its full installed package.

```bash
julia --startup-file=no --project=. --threads=4 -e 'text = read("docs/history/audit_twiss_dispersion_theory_2026_09_08.md", String); code = match(r"(?s)<!-- theory-probe-start -->\n```julia\n(.*?)\n```", text).captures[1]; include_string(Main, code, "twiss_dispersion_theory_probe.jl")'
```

<!-- theory-probe-start -->
```julia
using LinearAlgebra, Random

function run_theory_checks()
    BLAS.set_num_threads(1)
    rng = MersenneTwister(20260908)
    eye(n) = Matrix{Float64}(I, n, n)
    J = [0.0 1.0; -1.0 0.0]
    S4, S6 = kron(eye(2), J), kron(eye(3), J)
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
    rot(mu) = [cos(mu) sin(mu); -sin(mu) cos(mu)]
    cs(b, a) = [sqrt(b) 0.0; -a / sqrt(b) 1 / sqrt(b)]
    adj(K) = -J * transpose(K) * J
    maxima = Dict{String,Float64}()
    counts = Dict{String,Int}()
    function check(name, actual, expected; tol=1e-10)
        residual = norm(actual - expected) / max(1.0, norm(expected))
        @assert isfinite(residual) && residual <= tol (name, residual, tol)
        maxima[name] = max(get(maxima, name, 0.0), residual)
        counts[name] = get(counts, name, 0) + 1
        residual
    end
    function mc(zeta, eta)
        h = 1 - dot(zeta, S4 * eta)
        [eye(4) + zeta * transpose(eta) * S4 zeta eta;
         transpose(eta) * S4 1.0 0.0;
         -transpose(zeta) * S4 0.0 h]
    end
    syl(A, L, rhs) = reshape(
        (kron(eye(2), A) - kron(transpose(L), eye(4))) \ vec(rhs), 4, 2)
    function check4(W)
        phases = [0.7, 4.0] # Tests both signs of sin(mu).
        R = bd(rot.(phases)...)
        M = W * R / W
        traces = 2 .* cos.(phases)
        t1, t2 = tr(M), tr(M * M)
        roots = [(t1 + s * sqrt(2t2 - t1^2 + 8)) / 2 for s in (-1, 1)]
        check("E10 traces", sort(roots), sort(traces))
        Ps, Gs = Matrix{Float64}[], Matrix{Float64}[]
        us = Vector{ComplexF64}[]
        for j in 1:2
            k = 3 - j
            P = (M + inv(M) - traces[k] * eye(4)) / (traces[j] - traces[k])
            st = sqrt(1 - (traces[j] / 2)^2)
            G = -(M - inv(M)) * P * S4 / (2st)
            st *= sign(tr(G))
            G = -(M - inv(M)) * P * S4 / (2st)
            @assert minimum(eigvals(Symmetric((G + G') / 2))) > -1e-10
            H = G + im * P * S4
            pair = W[:, 2j-1:2j]
            uref = pair[:, 1] - im * pair[:, 2]
            check("E12 modal covariance", G, pair * pair')
            check("E13 Hermitian mode", H, uref * uref')
            a = argmax(real.(diag(H)))
            u = H[:, a] / sqrt(real(H[a, a]))
            check("E14 extracted eigenvector", M * u, exp(-im * phases[j]) * u)
            check("E3 action normalization", dot(u, S4 * u), -2im)
            check("E12 phase orientation", st, sin(phases[j]))
            # Reconstruct M7 using relative complex position products.
            ref = j == 1 ? 1 : 3
            u *= conj(u[ref]) / abs(u[ref])
            rec = similar(u)
            for q in (1, 3)
                p = q + 1
                beta = abs2(u[q])
                alpha = -real(conj(u[q]) * u[p])
                kappa = -imag(conj(u[q]) * u[p])
                phase = H[q, ref] / sqrt(real(H[q, q] * H[ref, ref]))
                rec[q] = sqrt(beta) * phase
                rec[p] = -(alpha + im * kappa) / sqrt(beta) * phase
            end
            check("M7 mode reconstruction", rec, u)
            push!(Ps, P); push!(Gs, G); push!(us, u)
        end
        area = -imag(conj(us[1][3]) * us[1][4])
        check("M3 shared area", area, -imag(conj(us[2][1]) * us[2][2]))
        check("E14 map reconstruction",
              sum(cos(phases[j]) * Ps[j] + sin(phases[j]) * Gs[j] * S4 for j in 1:2), M)
        for form in 1:2
            weight = form == 1 ? 1 - area : area
            weight > 1e-3 || continue # Chart eligibility, counted in the report.
            P = Ps[form]
            Rc = -P[3:4, 1:2] / weight
            Q1 = (form == 1 ? Gs[1][1:2, 1:2] : Gs[1][3:4, 3:4]) / weight
            Q2 = (form == 1 ? Gs[2][3:4, 3:4] : Gs[2][1:2, 1:2]) / weight
            V = sqrt(weight) * (form == 1 ?
                [eye(2) adj(Rc); -Rc eye(2)] : [adj(Rc) eye(2); eye(2) -Rc])
            Uet = V * bd(cs(Q1[1, 1], -Q1[1, 2]), cs(Q2[1, 1], -Q2[1, 2]))
            check("B11 form $form reconstruction", Uet * R / Uet, M)
            check("B11 form $form symplectic", V' * S4 * V, S4)
        end
    end
    for trial in 1:200
        K = randn(rng, 4, 4)
        check4(exp(0.2 * S4 * (K + K')))
    end
    for Rc in ([0.4 0.1; -0.2 0.3], [0.4 0.0; 0.0 -0.5])
        for form in 1:2
            V = (form == 1 ? [eye(2) adj(Rc); -Rc eye(2)] :
                            [adj(Rc) eye(2); eye(2) -Rc]) / sqrt(1 + det(Rc))
            check4(V * bd(cs(1.3, 0.2), cs(0.8, -0.1)))
        end
    end

    iteration_counts = Dict("fixed" => Int[], "newton" => Int[])
    phases6 = [0.7, 1.3, 0.2]
    R6 = bd(rot.(phases6)...)
    for trial in 1:100
        K = randn(rng, 6, 6)
        W = exp(0.025 * S6 * (K + K'))
        M = W * R6 / W
        X, Y = W[1:4, 5:6], W[5:6, 5:6]
        D = X / Y
        h = det(Y)
        zeta, eta = D[:, 1], h * D[:, 2]
        T = mc(zeta, eta)
        check("D8 area conversion", h, 1 / (1 + dot(D[:, 1], S4 * D[:, 2])))
        check("K1 ordered symplectic", T' * S6 * T, S6)
        N = T \ (M * T)
        check("K4 off blocks", vcat(vec(N[1:4, 5:6]), vec(N[5:6, 1:4])), zeros(16))
        A, B, C, L = M[1:4, 1:4], M[1:4, 5:6], M[5:6, 1:4], M[5:6, 5:6]
        residual(Dn) = A * Dn + B - Dn * (C * Dn + L)
        check("D14 graph invariance", residual(D), zeros(4, 2))
        t1, t2, t3 = tr(M), tr(M^2), tr(M^3)
        c2 = (t1^2 - t2) / 2 - 3
        c3 = -(t1^3 - 3t1*t2 + 2t3) / 6 + 2t1
        roots = eigvals([0.0 0.0 -c3; 1.0 0.0 -c2; 0.0 1.0 t1])
        @assert all(abs.(imag.(roots)) .< 1e-10)
        roots = real.(roots)
        check("D17 cubic roots", sort(roots), sort(2 .* cos.(phases6)))
        tau = roots[argmin(abs.(roots .- 2cos(phases6[3])))]
        Da = -(A*A + B*C - tau*A + eye(4)) \ (A*B + B*L - tau*B)
        check("D19 algebraic graph", Da, D)
        for method in ("fixed", "newton")
            Dn = syl(A, L, -B)
            converged = false
            for iteration in 1:100
                Dnext = method == "fixed" ? syl(A, L, -B + Dn*C*Dn) :
                    syl(A - Dn*C, L + C*Dn, -B - Dn*C*Dn)
                if method == "newton"
                    check("D22 quadratic identity", residual(Dnext), -(Dnext-Dn)*C*(Dnext-Dn))
                end
                Dn = Dnext
                if norm(residual(Dn)) <= 1e-13
                    converged = true
                    push!(iteration_counts[method], iteration)
                    break
                end
            end
            @assert converged method
            check("D20-D21 $method graph", Dn, D)
        end
        # X2 cross-multiplied readout: independent scalar ratios.
        ratios = hcat((X[:, 1]*Y[2, 2] - X[:, 2]*Y[2, 1]) / det(Y),
                      (X[:, 2]*Y[1, 1] - X[:, 1]*Y[1, 2]) / det(Y))
        check("X2 graph readout algebra", ratios, D)
        # Ohmi positive-area chart; all these weak-coupling samples qualify.
        @assert h > 0
        a = sqrt(h); F = a * D; f, g = F[:, 1], F[:, 2]
        Fplus = -J * F' * S4
        AH = eye(4) - F * Fplus / (1 + a)
        H = [AH -F; Fplus a*eye(2)]
        Hi = [AH F; -Fplus a*eye(2)]
        Tb = eye(4) + f*g'*S4/(1+a) + g*f'*S4/(a*(1+a))
        check("O3 symplectic", H' * S6 * H, S6)
        check("O3 inverse", H * Hi, eye(6))
        check("O5 bridge", H * T, bd(Tb, [1/a 0.0; 0.0 a]))
        Bc = [1.0 -im; -im 1.0] / sqrt(2)
        V0 = bd(Bc, Bc, Bc) / W
        Fex = vcat(-J*transpose(V0[5:6, 1:2])*J*V0[5:6, 5:6]/a,
                   -J*transpose(V0[5:6, 3:4])*J*V0[5:6, 5:6]/a)
        check("O6 extraction", Fex, F)
        Wbar = T \ W
        for j in 1:2
            pair = Wbar[1:4, 2j-1:2j]
            check("G4 modal H", sum(abs2, W[5, 2j-1:2j]),
                  dot(eta, S4 * (pair * pair') * S4' * eta))
        end
    end
    for hv in (-1.0, 0.0, 0.5)
        zeta = [1.0, 0, 0, 0]; eta = [0.0, 1-hv, 0, 0]
        T = mc(zeta, eta)
        check("K1 signed and zero h", T' * S6 * T, S6)
        if hv != 0
            W = T; D = W[1:4, 5:6] / W[5:6, 5:6]
            check("D8 signed h", 1 / (1 + dot(D[:, 1], S4 * D[:, 2])), hv)
        end
    end
    for trial in 1:100
        K = randn(rng, 2, 2); A = exp(J * (K + K') / 2)
        B = cs(exp(randn(rng)), randn(rng)); Qi = B * B'
        d = randn(rng, 2); c = d' * J * A; Qf = A * Qi * A'
        check("G3 two H forms", (c * Qi * c')[1], dot(d, J * Qf * J' * d))
    end
    disp(d, dp) = [1.0 0 0 d; 0 1 0 dp; -dp d 1 0; 0 0 0 1]
    W0 = bd(cs(1.2, 0.1), cs(2.0, 0.3), cs(1.5, -0.2))
    M0 = W0 * R6 / W0
    for k in (0.9, 0.99, 1.0, 1.01, 1.1)
        K = eye(4); K[4, 3] = k
        L = eye(4); L[3, 4] = -1
        T4 = disp(1.0, 0.0) * L * K * disp(0.0, 1.0)
        T6 = bd(eye(2), T4); W = T6 * W0
        M = T6 * M0 / T6
        Y = W[5:6, 5:6]
        check("G5 projected determinant", det(Y), 1-k)
        check("G7 regular full basis", W \ (M * W), R6)
        check("G7 symplectic transport", T6' * S6 * T6, S6)
        if k == 1.0
            @assert rank(Y) == 1 && all(iszero, Y[1, :])
            check("G7 exact compression", T4,
                  [0.0 0 1 1; 0 1 0 1; 0 1 0 0; -1 0 1 1]; tol=0.0)
            check("G2 H at singular chart", sum(abs2, W[5, 3:4]), (1+0.3^2)/2)
        end
    end
    # Negative controls: wrong conventions must be detectably wrong.
    zeta = [0.5, 0, 0, 0]; eta = [0.0, 1, 0, 0]
    T = mc(zeta, eta); D = T[1:4, 5:6] / T[5:6, 5:6]
    @assert norm(D[:, 2] - eta) > 0.5
    Wbad = [eye(4) D; zeros(2, 4) eye(2)]
    @assert norm(Wbad' * S6 * Wbad - S6) > 0.1
    Lbad = [1.0 1 1 2; 0 1 0 0; 0 3 2 1; 0 1 1 1]
    check("G3 negative-control map symplectic", Lbad' * S4 * Lbad, S4)
    A, d, c = Lbad[1:2, 1:2], Lbad[1:2, 4], Lbad[3, 1:2]
    @assert dot(c, c) == 9 && dot(d, J * (A*A') * J' * d) == 4
    println("Julia ", VERSION, "; CPU Float64; Julia threads=", Threads.nthreads(),
            "; BLAS threads=", BLAS.get_num_threads(), "; seed=20260908")
    for name in sort(collect(keys(maxima)))
        println(name, " | ", counts[name], " | ", maxima[name])
    end
    for method in sort(collect(keys(iteration_counts)))
        println(method, " iteration range: ", extrema(iteration_counts[method]))
    end
    println("Negative controls: 3 passed. Matrix algebra only; no production analysis executed.")
end

run_theory_checks()
```
<!-- theory-probe-end -->

## Execution record

The reproducible algebra probe completed successfully with the following
recorded configuration, counts, and maximum residuals. Both eligible chart
counts are explicit; skipped/ineligible charts are not reported as passes.

```text
Julia 1.12.4; CPU Float64; Julia threads=4; BLAS threads=1; seed=20260908
B11 form 1 reconstruction | 203 | 1.391466977502873e-15
B11 form 1 symplectic | 203 | 5.670119843763444e-16
B11 form 2 reconstruction | 91 | 4.205694559538952e-14
B11 form 2 symplectic | 91 | 1.8962842438571747e-14
D14 graph invariance | 100 | 5.3362135596618594e-17
D17 cubic roots | 100 | 6.53413855859973e-15
D19 algebraic graph | 100 | 1.9289331415414636e-15
D20-D21 fixed graph | 100 | 1.7876163803962922e-13
D20-D21 newton graph | 100 | 8.359460585508948e-16
D22 quadratic identity | 200 | 5.954301771220658e-17
D8 area conversion | 100 | 4.440892098500626e-16
D8 signed h | 2 | 0.0
E10 traces | 204 | 5.626735999202711e-16
E12 modal covariance | 408 | 2.101919175323391e-15
E12 phase orientation | 408 | 0.0
E13 Hermitian mode | 408 | 2.097787152889199e-15
E14 extracted eigenvector | 408 | 1.0834981305402306e-15
E14 map reconstruction | 204 | 2.9316027311883265e-16
E3 action normalization | 408 | 8.885826494747141e-16
G2 H at singular chart | 1 | 1.1102230246251565e-16
G3 negative-control map symplectic | 1 | 0.0
G3 two H forms | 100 | 8.326672684688674e-16
G4 modal H | 200 | 1.0408340855860843e-17
G5 projected determinant | 5 | 1.3877787807814457e-17
G7 exact compression | 1 | 0.0
G7 regular full basis | 5 | 2.9741751412379914e-16
G7 symplectic transport | 5 | 4.079219866531549e-18
K1 ordered symplectic | 100 | 1.6352421421410482e-16
K1 signed and zero h | 3 | 0.0
K4 off blocks | 100 | 8.362973266830865e-17
M3 shared area | 204 | 5.551115123125783e-16
M7 mode reconstruction | 408 | 1.50242034868248e-14
O3 inverse | 100 | 3.4225365663928015e-16
O3 symplectic | 100 | 3.4225365575832673e-16
O5 bridge | 100 | 2.644069686613075e-16
O6 extraction | 100 | 1.2423575550114723e-16
X2 graph readout algebra | 100 | 2.90282856959113e-17
fixed iteration range: (3, 6)
newton iteration range: (2, 2)
Negative controls: 3 passed. Matrix algebra only; no production analysis executed.
```

Local-link checks and equation-label checks passed: 130 unique numbered
equations, no unresolved parenthesized local equation references, and 296
balanced display delimiters. The normalizer/dispersion status wording was
re-walked after the neighbour audit so a singular graph also bypasses
chart-dependent 4D extraction in the proposed analysis sequence.
Actual browser/PDF math rendering was not tested.

The final-tree batch gate is the markdown-only fast lane:

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(test_args=["lane=fast"], julia_args=["--threads=4"])'
```

This gate checks repository integration, not the correctness of an implemented
optics analysis. The batch contains only Markdown files; the generated
registry snapshot and runtime/source files are unchanged. The full lane and
the proposed physical-lattice benchmarks are not claimed by this record.
The live gate prints every skipped testset; its execution status is reported
in the task handoff, separately from the completed algebra checks above.
