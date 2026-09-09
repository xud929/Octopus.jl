# Twiss/dispersion notation review

Date: 2026-09-09. Scope: the complete
[Twiss/dispersion theory note](../theory/twiss_dispersion.md), revised at the
owner's request for consistent symbols and no unnecessary intermediate aliases.
This is a documentation correction, not a new analysis implementation.

## Scope, provenance, and traceability

The primary reviewer read the entire pre-edit note, changed its notation, and
re-walked the changed formulas and their consumers throughout Sections 1–12
and Appendix A. An independent read-only review covered every line of
Sections 1–7 and Appendix A before and after the main rewrite; its
[unit report](audit_twiss_dispersion_notation_2026_09_09_unit_reports/U1_report.md)
records leads rather than unverified findings. The primary reviewer reproduced
the reported text defects and made every edit.

Applicable routes: "Change public documentation or APIs" and "Audit,
correctness review, or post-campaign neighbour audit" in AGENTS.md.
The analysis layer remains placeholder-only. The earlier
[theory-review record](audit_twiss_dispersion_theory_2026_09_08.md) is preserved,
including its original notation and equation names. Its SHA-256 remains
46b7eb6d6dfb8d02e799ac5840a1a1a9da3f25fd2b36428d8feed821f2e9e1f6.

| Region | Review and disposition |
|---|---|
| Sections 1–3 | Dimensioned symbol dictionary; S2/S4/S6 versus scalar action; direct traces and trigonometric factors; projector and modal covariance retained; redundant Hermitian-matrix alias removed. |
| Sections 4–7 | Periodic M blocks versus section L blocks; named eigenmode maps; adjugate function versus decoupled overbars; ET forms versus physical modes; direct eigenvector components; unambiguous scalar and 2×2 covariance indices. |
| Sections 8–9 | Physical 4+2 block names, U-based longitudinal pair/projections, explicit Ohmi factor and inverse in canonical dispersion variables, source-only translation dictionary, Xsuite construction and responses in the same notation. |
| Section 10 | Endpoint labels separated from mode labels; unnamed one-use overlap score; GLSF canonical coordinates, mode-2 emittance/Twiss functions, shared modal covariance, descriptive elementary section maps. |
| Sections 11–12 and Appendix A | Residuals without one-use aliases; cross-references and future-work status; explicit components and positive-h domain for the reduced graph. |
| Documentation neighbours | Index, open analysis row, lessons entry, and the new report/probes; old history and registry snapshot unchanged. |

The rewrite independently checks the O2/O3 inverse and symplecticity using
zeta^T S4 eta = 1-h; division of O2's longitudinal columns gives D7/O4;
multiplication of O3 by D3 gives O5. E13/E14 now use the same outer product
explicitly and its real diagonal for the pivot. Indexed map substitutions
do not change the block equations. The numerical tests below check these
claims against independent matrix products and extend the earlier probe.

No new public object, consumer, option, contract, or API is claimed.
Production analysis, tracked-lattice validation, radiation physics, nonlinear
GLSF performance, a fresh external-package execution, and performance
benchmarking are outside this notation-only scope. The source comparison
remains pinned to the commit already cited by the theory note.

## Findings and corrections

Confirmed presentation defects: source-paper notation had leaked into the
main derivation; several symbols changed dimensions or roles without an
explicit boundary; temporary trace, sine/cosine, column, and residual aliases
obscured quantities already defined elsewhere. These are resolved by the
changes listed above. Reused objects with a defined role, such as invariant
projectors, unit-emittance covariances, normalizing bases, Twiss matrices,
dispersion graphs, signed areas, and actual section maps, remain named.

The neighbour pass also caught errors introduced during the rewrite:
16 accidentally renamed MR equation tags, two untranslated lower-left map
blocks, 13 adjugate endpoint subscripts outside their arguments, joined
LaTeX commands, and two malformed "form" phrases. All were corrected.
The executable syntax checks below reject injected examples of the tag,
block, and joined-command errors.

Correction to the review instrument: an initial extraction compiled 559
expressions but did not handle multiline inline mathematics completely.
A dollar-delimiter accounting assertion caught that coverage gap. The fixed
extractor accounts for every delimiter and compiles all 564 expressions,
with 129 unique equation tags and no unresolved local equation references.
The first generated TeX file also contained blank paragraphs inside display
math; trimming the extracted formula fixed the rendering harness, not the note.
This is a LaTeX syntax check, not a claim about a specific Markdown renderer
or page layout.

## Reproduction and numerical results

Run the two code blocks below from the repository root. They use standard
Julia libraries; the syntax/rendering block additionally requires pdflatex
with amsmath, amssymb, and mathrsfs. Rendering outputs are generated in a
temporary directory, never in the repository.

The algebra probe fixes CPU Float64, Julia 1.12.4, four Julia threads, one BLAS
thread, and seed 20260909. All matrix comparisons use
norm(actual-expected)/max(1,norm(expected)) <= 1e-10 in dimensionless coordinates.
There are 100 fixtures for each of the four ET transport combinations,
200 covariance/phase fixtures, and 200 Ohmi fixtures with h in
{0.15, 0.5, 1, 2}. Every listed check executed; no fixture was skipped.
The test variables used to transcribe the pre-rewrite Ohmi block expression
are confined to that reference arm, not reintroduced into the theory note.

The earlier record's full algebra probe was also re-executed, exit 0:
204 transverse fixtures, 100 weakly coupled 6D fixtures, the signed/zero-h
and singular-GLSF fixtures, and three convention negative controls.
Its largest recorded normalized residual remains
1.7876163803962922e-13 for fixed-point graph recovery, below 1e-10.
Its original equation-name labels refer to the earlier note revision.

New probe output:

```text
Julia 1.12.4; Float64 CPU; Julia threads=4; BLAS threads=1; seed=20260909; tol=1e-10
B4-B8 form 1 phase | 100 | 2.3876248941963676e-16
B4-B8 form 2 phase | 100 | 2.357182192694738e-16
M11-M16 expanded cross covariance | 200 | 1.894069439299442e-14
M12 full diagonal | 200 | 2.0936862184031217e-15
M12 same-plane cross covariance | 200 | 2.482534153247273e-16
M13 projected gamma | 200 | 2.558937633260452e-15
O2 canonical | 200 | 1.4462517180812762e-15
O2 old-new factor agreement | 200 | 8.422387887513979e-17
O3 inverse | 200 | 1.4462517180812762e-15
O4 invariant plane | 200 | 2.5834414155088685e-16
O5 bridge canonical | 200 | 2.89340289330916e-16
O5 coordinate bridge | 200 | 2.420309477548681e-15
P table form 1->1 blocks | 100 | 3.8461849692474513e-16
P table form 1->2 blocks | 100 | 3.663041338284266e-16
P table form 2->1 blocks | 100 | 3.047698535377612e-16
P table form 2->2 blocks | 100 | 3.377460135909662e-16
P3-P4 form 1->1 R | 100 | 8.412243472809729e-15
P3-P4 form 1->1 lambda | 100 | 6.301225122339244e-16
P3-P4 form 1->2 R | 100 | 5.0194828543853254e-15
P3-P4 form 1->2 lambda | 100 | 6.661338147750939e-16
P3-P4 form 2->1 R | 100 | 3.4530044443508814e-15
P3-P4 form 2->1 lambda | 100 | 6.301225122339244e-16
P3-P4 form 2->2 R | 100 | 1.5513976445453076e-15
P3-P4 form 2->2 lambda | 100 | 1.1102230246251565e-15
P5 area sum | 400 | 2.220446049250313e-15
P6 Twiss transport | 800 | 1.2099502712140473e-15
X1 modal covariance | 200 | 2.7874266437158984e-15
X2 graph | 200 | 1.3671203307539958e-15
X2 scalar response | 800 | 1.2212453270876722e-15
Negative controls: wrong companion sign and unscaled momentum column rejected.
```

The two new algebra negative controls reject an incorrect longitudinal
companion sign and confusing eta with eta/h. The rendering probe's three
injections verify its syntax guard can fail.

These sampled algebra checks are not production contracts. The final
markdown-only batch also owes the AGENTS.md fast lane, separately from these
probes. Full-lane-only physics, examples, heavy configuration, and MPI checks
are not certified by a markdown gate. The package gate's execution outcome
and exact skip list belong to its run receipt, not a predeclared pass here.

No confirmed notation finding remains open in the declared scope. Analysis
implementation and physical-lattice benchmarks remain on docs/todo.md.

```bash
julia --startup-file=no --project=. --threads=4 -e 'text = read("docs/history/audit_twiss_dispersion_notation_2026_09_09.md", String); code = match(r"(?s)<!-- notation-probe-start -->\n```julia\n(.*?)\n```", text).captures[1]; include_string(Main, code, "notation_probe.jl")'
julia --startup-file=no --project=. --threads=4 -e 'text = read("docs/history/audit_twiss_dispersion_notation_2026_09_09.md", String); code = match(r"(?s)<!-- notation-lint-start -->\n```julia\n(.*?)\n```", text).captures[1]; include_string(Main, code, "notation_lint.jl")'
```

<!-- notation-probe-start -->
```julia
using LinearAlgebra, Random

function notation_checks()
    BLAS.set_num_threads(1)
    rng = MersenneTwister(20260909)
    eye(n) = Matrix{Float64}(I, n, n)
    S2 = [0.0 1.0; -1.0 0.0]
    S4, S6 = kron(eye(2), S2), kron(eye(3), S2)
    bd(A, B) = [A zeros(size(A, 1), size(B, 2));
                zeros(size(B, 1), size(A, 2)) B]
    rot(mu) = [cos(mu) sin(mu); -sin(mu) cos(mu)]
    adj2(A) = -S2 * transpose(A) * S2
    cs() = (b = exp(randn(rng)); a = randn(rng);
            [sqrt(b) 0.0; -a / sqrt(b) 1 / sqrt(b)])
    coupling() = 0.2randn(rng, 2, 2)
    et(R, form) = (form == 1 ? [eye(2) adj2(R); -R eye(2)] :
                               [adj2(R) eye(2); eye(2) -R]) / sqrt(1 + det(R))
    ordered(zeta, eta) = [
        eye(4) + zeta * eta' * S4 zeta eta;
        eta' * S4 1.0 0.0;
        -zeta' * S4 0.0 1 - dot(zeta, S4 * eta)]
    maxima = Dict{String, Float64}()
    counts = Dict{String, Int}()
    function check(name, actual, expected; tol=1e-10)
        err = norm(actual - expected) / max(1.0, norm(expected))
        @assert isfinite(err) && err <= tol (name, err)
        maxima[name] = max(get(maxima, name, 0.0), err)
        counts[name] = get(counts, name, 0) + 1
    end

    for _ in 1:100
        Rin, Rout = coupling(), coupling()
        @assert 1 + det(Rin) > 0 && 1 + det(Rout) > 0
        lin, lout = 1 / sqrt(1 + det(Rin)), 1 / sqrt(1 + det(Rout))
        Q1, Q2 = cs(), cs()
        L1, L2 = Q1 * rot(0.7) / Q1, Q2 * rot(1.1) / Q2
        for fin in 1:2, fout in 1:2
            L4 = et(Rout, fout) * bd(L1, L2) / et(Rin, fin)
            Lxx, Lxy, Lyx, Lyy = L4[1:2,1:2], L4[1:2,3:4],
                                  L4[3:4,1:2], L4[3:4,3:4]
            primary = Lxx - Lxy * Rin
            lower = Lyx - Lyy * Rin
            secondary = Lxx * adj2(Rin) + Lxy
            lowsecondary = Lyx * adj2(Rin) + Lyy
            Rgot = fin == fout ? -lower / primary : -lowsecondary / secondary
            lgot = lin * sqrt(det(fin == fout ? primary : secondary))
            blocks = (fin, fout) == (1,1) ? (primary, lowsecondary) :
                     (fin, fout) == (1,2) ? (lower, secondary) :
                     (fin, fout) == (2,1) ? (secondary, lower) :
                                            (lowsecondary, primary)
            check("P3-P4 form $fin->$fout R", Rgot, Rout)
            check("P3-P4 form $fin->$fout lambda", lgot, lout)
            check("P table form $fin->$fout blocks",
                  bd(blocks...) * lin / lout, bd(L1, L2))
            check("P5 area sum", det(primary) + det(lower), 1 / lin^2)
            for (L, Q) in ((L1, Q1), (L2, Q2))
                check("P6 Twiss transport", L * (Q * Q') * L', Q * Q')
            end
        end

        for form in 1:2
            U4 = et(Rin, form) * bd(Q1, Q2)
            modes = [U4[:,2j-1] - im * U4[:,2j] for j in 1:2]
            beta, alpha = zeros(2,2), zeros(2,2)
            for j in 1:2, a in 1:2
                q, p = modes[j][2a-1], modes[j][2a]
                beta[j,a] = abs2(q)
                alpha[j,a] = -real(conj(q) * p)
            end
            area = -imag(conj(modes[1][3]) * modes[1][4])
            phases = [modes[1][3] * conj(modes[1][1]),
                      modes[2][1] * conj(modes[2][3])]
            phases ./= abs.(phases)
            b1, a1 = (Q1 * Q1')[1,1], -(Q1 * Q1')[1,2]
            b2, a2 = (Q2 * Q2')[1,1], -(Q2 * Q2')[1,2]
            r11, r12, r22 = Rin[1,1], Rin[1,2], Rin[2,2]
            expected = form == 1 ?
                [complex(a1*r12-b1*r11, r12), complex(a2*r12+b2*r22, r12)] :
                [complex(a1*r12+b1*r22, -r12), complex(a2*r12-b2*r11, -r12)]
            expected ./= abs.(expected)
            check("B4-B8 form $form phase", phases, expected)
            c1, c2 = real.(phases)
            s1, s2 = imag.(phases)
            e1, e2 = 0.6, 1.7
            b1x,b1y,b2x,b2y = beta[1,1],beta[1,2],beta[2,1],beta[2,2]
            a1x,a1y,a2x,a2y = alpha[1,1],alpha[1,2],alpha[2,1],alpha[2,2]
            expanded = [
                e1*sqrt(b1x*b1y)*c1 + e2*sqrt(b2x*b2y)*c2,
                e1*sqrt(b1x/b1y)*(-a1y*c1+area*s1) -
                    e2*sqrt(b2x/b2y)*(a2y*c2+(1-area)*s2),
                -e1*sqrt(b1y/b1x)*(a1x*c1+(1-area)*s1) +
                    e2*sqrt(b2y/b2x)*(-a2x*c2+area*s2),
                e1/sqrt(b1x*b1y)*((a1x*a1y+area*(1-area))*c1+
                    ((1-area)*a1y-area*a1x)*s1) +
                e2/sqrt(b2x*b2y)*((a2x*a2y+area*(1-area))*c2+
                    ((1-area)*a2x-area*a2y)*s2)]
            Sigma4 = U4 * Diagonal([e1,e1,e2,e2]) * U4'
            check("M11-M16 expanded cross covariance", expanded,
                  [Sigma4[1,3],Sigma4[1,4],Sigma4[2,3],Sigma4[2,4]])
            gamma = [(a1x^2+(1-area)^2)/b1x (a1y^2+area^2)/b1y;
                     (a2x^2+area^2)/b2x (a2y^2+(1-area)^2)/b2y]
            check("M13 projected gamma", gamma,
                  [abs2(modes[1][2]) abs2(modes[1][4]);
                   abs2(modes[2][2]) abs2(modes[2][4])])
            expected_diagonal = [
                e1*b1x+e2*b2x, e1*gamma[1,1]+e2*gamma[2,1],
                e1*b1y+e2*b2y, e1*gamma[1,2]+e2*gamma[2,2]]
            check("M12 full diagonal", diag(Sigma4), expected_diagonal)
            check("M12 same-plane cross covariance", [Sigma4[1,2],Sigma4[3,4]],
                  [-e1*a1x-e2*a2x,-e1*a1y-e2*a2y])
        end
    end

    for htarget in (0.15, 0.5, 1.0, 2.0), _ in 1:50
        zeta, eta = 0.3randn(rng,4), 0.3randn(rng,4)
        eta += (1 - htarget - dot(zeta, S4 * eta)) * (S4' * zeta) / dot(zeta,zeta)
        h = 1 - dot(zeta, S4 * eta)
        Mcal = ordered(zeta, eta)
        # Direct transcription of O2/O3; no F/f/g helpers in this arm.
        MO = [eye(4)+(zeta*eta'-eta*zeta')*S4/(1+sqrt(h)) sqrt(h)*zeta eta/sqrt(h);
              eta'*S4/sqrt(h) sqrt(h) 0.0;
              -sqrt(h)*zeta'*S4 0.0 sqrt(h)]
        MOinv = [eye(4)+(zeta*eta'-eta*zeta')*S4/(1+sqrt(h)) -sqrt(h)*zeta -eta/sqrt(h);
                 -eta'*S4/sqrt(h) sqrt(h) 0.0;
                 sqrt(h)*zeta'*S4 0.0 sqrt(h)]
        bridge = bd(eye(4)+zeta*eta'*S4/(1+sqrt(h))+
                    eta*zeta'*S4/(sqrt(h)*(1+sqrt(h))), Diagonal([1/sqrt(h),sqrt(h)]))
        check("O2 canonical", MO' * S6 * MO, S6)
        check("O3 inverse", MOinv * MO, eye(6))
        check("O4 invariant plane", MO[1:4,5:6] / MO[5:6,5:6], [zeta eta/h])
        check("O5 coordinate bridge", MOinv * Mcal, bridge)
        check("O5 bridge canonical", bridge' * S6 * bridge, S6)
        # Independent pre-rewrite block representation.
        F = [sqrt(h)*zeta eta/sqrt(h)]
        Fplus = -S2 * F' * S4
        reference = [eye(4)-F*Fplus/(1+sqrt(h)) F; -Fplus sqrt(h)*eye(2)]
        check("O2 old-new factor agreement", MO, reference)
        U6 = Mcal * bd(bd(cs(), cs()), cs())
        pair = U6[:,5:6]
        u = pair[:,1] - im * pair[:,2]
        raw = 2.3exp(0.4im) * conj(u)
        fromX = hcat(real(raw),imag(raw)) / sqrt(dot(real(raw), S6 * imag(raw)))
        check("X1 modal covariance", fromX * fromX', pair * pair')
        check("X2 graph", pair[1:4,:] / pair[5:6,:], [zeta eta/h])
        for a in 1:4
            zgot = (U6[a,5]*U6[6,6]-U6[a,6]*U6[6,5])/det(U6[5:6,5:6])
            egot = (U6[a,6]*U6[5,5]-U6[a,5]*U6[5,6])/det(U6[5:6,5:6])
            check("X2 scalar response", [zgot,egot], [zeta[a],eta[a]/h])
        end
    end
    # Negative controls exercise sign and normalization sensitivity.
    zeta, eta = [0.4,0.1,-0.2,0.3], [0.2,-0.5,0.1,0.4]
    h = 1 - dot(zeta, S4 * eta)
    good = ordered(zeta,eta)
    wrong = copy(good); wrong[6,1:4] *= -1
    @assert norm(wrong' * S6 * wrong - S6) > 1e-2
    @assert norm(eta - eta/h) > 1e-2
    println("Julia ", VERSION, "; Float64 CPU; Julia threads=", Threads.nthreads(),
            "; BLAS threads=", BLAS.get_num_threads(), "; seed=20260909; tol=1e-10")
    for name in sort(collect(keys(maxima)))
        println(name, " | ", counts[name], " | ", maxima[name])
    end
    println("Negative controls: wrong companion sign and unscaled momentum column rejected.")
end
notation_checks()
```

<!-- notation-lint-start -->
```julia
function check_notation(note)
    tags = [m.captures[1] for m in eachmatch(r"\\tag\{([^}]+)\}", note)]
    @assert length(tags) == length(unique(tags))
    references = [m.captures[1] for m in eachmatch(r"\(([A-Z][0-9]+)\)", note)]
    @assert all(in(tags), references)
    forbidden = r"\\tag\{M_4\d+\}|\\\\C&|\\(?:quad|otimes|star)M_|\\operatorname\{adj\}\(R\)_|H_j|W_s|X_s|Y_s|q_\{[12j][xy]\}|t_n|c_j|s_j|form [12]s"
    @assert !occursin(forbidden, note)
    expressions = collect(eachmatch(r"(?s)\$\$(.*?)\$\$|\$([^$]*?)\$", note))
    @assert sum(m.captures[1] === nothing ? 2 : 4 for m in expressions) ==
            count(==('$'), note)
    for m in expressions
        formula = something(m.captures[1], m.captures[2])
        @assert count(==('{'), formula) == count(==('}'), formula)
    end
    println("Notation: ", length(tags), " unique tags; all references resolve; ",
            length(expressions), " complete math expressions; no retired aliases.")
    expressions
end

note = read("docs/theory/twiss_dispersion.md", String)
expressions = check_notation(note)
for defect in (raw"\tag{M_41}", raw"\\C&", raw"\otimesM_{rr}")
    rejected = try
        check_notation(note * "\n" * defect)
        false
    catch err
        err isa AssertionError || rethrow()
        true
    end
    @assert rejected
end
println("Notation negative controls: corrupted tag, stale block, joined command rejected.")

# Generated rendering artifacts stay outside the repository.
render_dir = mktempdir(prefix="octopus-notation-render-")
tex = raw"""\documentclass{article}
\usepackage[paperwidth=32in,paperheight=40in,margin=1in]{geometry}
\usepackage{amsmath,amssymb,mathrsfs}
\begin{document}
"""
for m in expressions
    if m.captures[1] === nothing
        global tex *= "\$" * m.captures[2] * "\$\\par\n"
    else
        global tex *= "\\[\n" * strip(m.captures[1]) * "\n\\]\n"
    end
end
tex *= "\\end{document}\n"
write(joinpath(render_dir, "equations.tex"), tex)
run(Cmd(["pdflatex", "-interaction=nonstopmode", "-halt-on-error",
         "-output-directory=" * render_dir, joinpath(render_dir, "equations.tex")]))
println("LaTeX compilation succeeded; generated artifacts: ", render_dir)
```
