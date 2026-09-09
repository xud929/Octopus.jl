# Twiss/dispersion literature review

Date: 2026-09-09. Scope: the owner's three supplied papers and their useful
results for the [optics theory note](../theory/twiss_dispersion.md).
This is a theory/documentation revision, not an implemented analysis.

## Executive summary and current open scope

Parzen's tune cubic is now credited and connected explicitly to D17.
Glukhov's recurrent-matrix construction supplies a symmetric interpretation of
the new full-6D projectors D26, connected here to the physical dispersion graph
by D27. Three-plane signed-area and covariance identities K12–K14 retain
complete mode information. Dieci–Friedman's Riccati iteration and continuation
framework connect to D20–D21 and the graph sensitivity/predictor D28–D29.

The former Section 10.5 GLSF lattice application and G1–G7 design benchmarks
were removed at the owner's request. They are not steps in this analysis.
The general chart-singularity caveat and modal bunch-length identity remain
in Sections 8.3/8.8 and 9.3; old historical records remain unchanged.

Open work: concrete analysis architecture/API, implementation, contracts and
tracked-lattice validation. No confirmed note defect remains open in this
scoped pass. Neither continuation nor the cited papers guarantees unique
individual modes at a spectral collision. No runtime speedup is claimed.

## Scope, provenance, and traceability

Applicable AGENTS.md routes: “Change public documentation or APIs” and
“Audit, correctness review, or post-campaign neighbour audit.”
Octopus's current concrete physics focus is beam–beam tracking; this note
continues to describe a future analysis. Source, runtime options, registry
snapshot and CUDA settings were not changed.

The primary reviewer read all three papers, independently derived the
load-bearing additions, made every repository edit, and reran both new probes
and the prior theory/notation probes. A read-only Glukhov unit reviewed the
full paper, assigned note seams, and post-edit additions. Its
[archived report](audit_twiss_dispersion_literature_2026_09_09_unit_reports/U1_report.md)
distinguishes leads from primary dispositions.

| Region | Coverage and evidence |
|---|---|
| Parzen, 3 pages | Full primary read; page 2 rendered to check OCR-damaged signs/adjugates; Eqs. 22–25 independently compared with D17. |
| Glukhov, 15 pages including appendices | Full primary and unit reads; Secs. III–VIII/X–XI and Appendix B mapped to D26, K12–K13, normalization and inverse ambiguity; unit probe rerun by primary. |
| Dieci–Friedman, supplied 9-page preprint | Full primary read; page 5 rendered; Eqs. 12–14 compared with D14/D20/D21, Eq. 16 specialized by differentiating D14. Publisher bibliography verified. |
| Note Sections 1, 3.4, 8–12 and references | Targeted primary reread of changed formulas/consumers; unit independently reviewed 8.5, 8.8, 9.3 and 11–12. No new line-by-line audit of unchanged Sections 4–7. |
| Documentation neighbours | Whole-note math syntax/reference check; delimiter/removal tripwires; README index, todo scope and experiences entry. |
| Runtime/contracts/validation/performance | No implementation or acceptance changes; manufactured matrix algebra is not a production contract or tracked-lattice validation. No timing claims. |

Pre-edit note SHA-256:
2188b84c3f2e19becf9ff6dddb61782f1dda0e075e603541c580a36b7b187b47.
Earlier theory record SHA-256 remains
46b7eb6d6dfb8d02e799ac5840a1a1a9da3f25fd2b36428d8feed821f2e9e1f6;
notation record remains
79c133e7a11e2fef3dc2371c59df2c94e169f6fb9dad18ef584e9f03d9be6186.

Source provenance, retrieved 2026-09-09:

| Paper | Download used | SHA-256 |
|---|---|---|
| Parzen, 1995 | https://arxiv.org/pdf/acc-phys/9506001 | e2d01f200483c85dfd845da5fc8e126df86d62dea26cbe89807944bedffc749e |
| Glukhov, PRAB 28, 084001 (2025) | https://harvest.aps.org/v2/journals/articles/10.1103/3ld3-dmmv/fulltext | 3aaee8b3da5aed2846cef2f8e7ab999d2e93d678bdd782ca86dcac7db7c46b9f |
| Dieci–Friedman, February 19, 2001 preprint | https://dieci.math.gatech.edu/preps/DiFrContInvSub.pdf | 093e547eda6236255d92b317e7f780306c01d79fb1fa8635620b5a690c3fdc2d |

The last paper's publisher citation is Numerical Linear Algebra with
Applications 8, 317–327 (2001), DOI 10.1002/nla.245. Equation references
identify the supplied preprint version. Direct APS PDF download returned
HTTP 403; the APS harvest endpoint supplied the paper. PDF rendering issued
Type-3-font bounding-box warnings; both inspected equation pages were readable.
No paper was unavailable or skipped.

## Findings, derivations, and corrections

1. **Reference gap resolved.** Pre-edit D17 was correct but did not connect
   to Parzen. Substitution of his Lambda=tau/2 and multiplication by eight
   gives the same monic cubic. Independent trace/block coefficients agree.
   The source's temporary coefficient alphabet is not imported.

2. **Symmetric construction added.** On each modal plane, M+inverse(M)
   acts as tau times the identity, so polynomial interpolation gives D26.
   Substitution of the canonical pair into P=-U S2 U^T S6 proves D27 and
   the signed-area identities. K13 follows from M P; K14 follows from the
   physical z row of the ordered transform.

3. **Continuation connection added.** Exchanging source graph-block order
   gives D14; the simple/Newton iterations give D20/D21. Differentiating
   all four varying map blocks gives D28; Taylor expansion gives D29.
   The source orthogonal basis is not a canonical normalizer.
   On preprint page 5 a printed 12 subscript accompanies the lower-left
   forcing E21; dimensions and Eq. 16 use the lower-left block.
   D28 was independently derived, not copied from that passage.

4. **Source-only sign caution not imported.** Unit lead U1-1 flags
   Glukhov Sec. VII's sentence permitting mixed projected-beta signs.
   In our stable, simple, canonical convention, K13 gives nonnegative
   beta=|u_component|^2 even with negative signed area. Primary derivation
   and the source-block probe confirm this: 921 negative areas, zero
   negative betas. This limits importing that sentence under our
   conventions; it is not an audit of every exceptional source case.

5. **Design scope reduced.** GLSF application removed; general K14 and the
   physical-chart caveat preserved. No optimized-lattice or radiation
   performance claim is imported.

Post-edit leads U1-2/U1-3 caught two introduced issues, now corrected:
eight display delimiters around D26–D29 became single dollars because
JavaScript string replacement interprets double dollars specially; and the
singular-chart fallback incorrectly referenced K9's unavailable ordered
factorization. Literal delimiters are restored, and K9 is explicitly
conditional on chart availability.

Instrument corrections: the unit suggested the old render harness might
rewrap every expression as display math. Primary inspection shows it
preserves inline/display distinction; that suspected blind spot is not
claimed. The new source tripwire directly checks single-dollar delimiter
lines. The primary probe's initial soft-scope warning and redundant fixture
inverse were corrected before final measurements. The unit's initial
soft-scope error was corrected with local scope; the archived version ran.

## Formula verification and numerical results

All probes below executed. CPU Float64, Julia 1.12.4, four Julia threads,
one BLAS thread, seed 20260909. Primary normalized error is
norm(actual-expected)/max(1,norm(expected)) <= 1e-10; central-difference
derivative tolerance is 1e-9 for truncation error. Source-block tolerance
is 1e-9; its exact metrics are explicit in its code.

Primary coverage: 100 stable 6D maps, 300 projectors, 900 physical projections,
six explicit h values (-2,-0.5,0.15,0.5,1,2), a smooth canonical scan at four
step sizes, and a singular physical graph with regular full basis and
unchanged separated tunes. No fixture skipped. The random subset has no
negative longitudinal h; explicit charts supply that coverage.

Step-halving predictor-error ratios are 3.9981–3.9995 (exact derivatives)
and 4.0002–4.0010 (finite-difference forcing). This demonstrates second-order
initial error on this family, not universal convergence or performance.
Three controls reject omitted reciprocal-cubic terms, reversed sensitivity
forcing, and lost cross-plane signs.

Primary output:

```text
Julia 1.12.4; Float64 CPU; Julia threads=4; BLAS threads=1; seed=20260909; tol=1.0e-10
6D E12 covariance                          n=300 max=1.8338903228984843e-15
6D completeness                            n=100 max=3.7838432698249946e-16
6D projector idempotence                   n=300 max=2.2363283618384641e-15
6D projector symplectic adjoint            n=300 max=4.3039215932601977e-15
6D reconstruction                          n=100 max=3.5902119198045172e-16
D19 vs D27                                 n=100 max=1.5318620017775811e-15
D26 known-plane projector                  n=300 max=2.3005681274267974e-15
D27 graph extraction                       n=100 max=8.0920713114236714e-16
D27 invariance                             n=100 max=6.7375194834009308e-16
D27 signed longitudinal area               n=100 max=1.7627112576466439e-15
D28 analytic derivative                    n=  1 max=6.3596013107845015e-17
D28 central difference                     n=  1 max=2.1870440678550391e-12
D29 corrected graph                        n=  4 max=3.9336616622388689e-14
D29 finite-difference corrected graph      n=  4 max=1.4560769965973406e-14
K12 matched covariance                     n=100 max=1.6359575137712873e-15
K12 mode area sums                         n=100 max=4.1043229949538602e-16
K12 physical plane area sums               n=100 max=4.2518304777254294e-16
K12 projected determinant                  n=900 max=2.5347893817055591e-15
K13 physical Twiss block                   n=900 max=1.5493363003227523e-15
K14 longitudinal covariance                n= 12 max=2.1981144401738019e-16
Parzen vs trace cubic                      n=100 max=1.5948813696437087e-15
chart-boundary canonical basis             n=  3 max=9.0757098364609868e-17
chart-boundary separated spectrum          n=  3 max=3.7652782462899716e-16
constructed h                              n=  6 max=1.3877787807814457e-16
cubic vs known modal traces                n=100 max=9.0943678691591696e-16
input symplecticity                        n=100 max=1.4189354416318049e-15
sign ambiguity diagonal blocks             n=  3 max=0
signed h algebraic graph                   n=  6 max=3.3229698159961803e-15
signed h graph                             n=  6 max=2.0023574631961955e-14
signed h projector                         n=  6 max=1.7102676490598052e-14
signed ordered chart                       n=  6 max=1.0773106566277396e-15
negative projected areas=304; random negative h=0
tangent predictor errors=[9.538865375639637e-6, 2.3858419746246136e-6, 5.966013554400934e-7, 1.4916795646179514e-7]; halving ratios=[3.9981128159757833, 3.999055571814207, 3.999527576774807]
finite-difference predictor errors=[3.41468208575764e-5, 8.534554970152075e-6, 2.1333732730751154e-6, 5.333103415616593e-7]; halving ratios=[4.001007782713707, 4.0004977459242665, 4.000247335965945]
three negative controls rejected; physical chart singularity detected; no fixture skipped
```

The source-block probe was independently rerun by the primary, exit zero:

```text
Julia 1.12.4; threads=4; BLAS threads=1
cofactor=1.5187850976872141e-12
covariance=1.1432503343238096e-13
projector=5.155579115503474e-13
source_normalization=1.6524403177703763e-14
twiss=2.7610040285339126e-13
weight=1.5298873279334657e-13
weight_sums=4.75175454539567e-14
300 canonical stable maps; 2700 projections
negative weights=921; minimum weight=-5.370169920378526
negative betas=0; minimum beta=0.00020351916656215942
maximum source W1 canonical defect=11.293415779115996
```

Prior theory and notation probes also ran, exit zero. Their largest normalized
errors remain 1.7876163803962922e-13 (fixed-point graph) and
1.894069439299442e-14 (expanded cross covariance), below 1e-10.
Legacy GLSF fixtures ran as historical algebra regressions, not current
design benchmarks.

The prior record's whole-note render harness reports 129 unique tags,
all references resolved, and 585 complete expressions compiled by pdflatex.
This is a LaTeX syntax check, not a Markdown layout certification.
The added source tripwire passes and rejects single-dollar and stale-G1
injections.

## Reproduction

From the repository root, run each block in a fresh Julia process.
Replace “literature-probe” by “source-probe” or “source-lint” to select
the other blocks. The hexadecimal escape in the extraction regex matches
the backtick delimiters.

```bash
julia --startup-file=no --project=. --threads=4 -e 'text = read("docs/history/audit_twiss_dispersion_literature_2026_09_09.md", String); code = match(r"(?s)<!-- literature-probe-start -->\n\x60{3}julia\n(.*?)\n\x60{3}", text).captures[1]; include_string(Main, code, "literature_probe.jl")'
```

<!-- literature-probe-start -->
```julia
using LinearAlgebra, Random, Printf
BLAS.set_num_threads(1)
Random.seed!(20260909)
const S2 = [0.0 1; -1 0]
const S4 = kron(Matrix{Float64}(I, 2, 2), S2)
const S6 = kron(Matrix{Float64}(I, 3, 3), S2)
const I2 = Matrix{Float64}(I, 2, 2)
const I4 = Matrix{Float64}(I, 4, 4)
const I6 = Matrix{Float64}(I, 6, 6)
const tol = 1e-10
const worst = Dict{String, Float64}()
const counts = Dict{String, Int}()
rotation(mu) = [cos(mu) sin(mu); -sin(mu) cos(mu)]
adj2(A) = -S2 * transpose(A) * S2
function check(name, actual, expected; limit=tol)
    residual = norm(actual - expected) / max(1, norm(expected))
    worst[name] = max(get(worst, name, 0.0), residual)
    counts[name] = get(counts, name, 0) + 1
    @assert isfinite(residual) && residual <= limit (name, residual, limit)
end
function blocks(M)
    M[1:4,1:4], M[1:4,5:6], M[5:6,1:4], M[5:6,5:6]
end
function graph_residual(M,D)
    rr,rl,lr,ll = blocks(M)
    rr*D + rl - D*(lr*D + ll)
end
function sylvester_difference(A,B,C)
    reshape((kron(I2,A)-kron(transpose(B),I4)) \ vec(C),4,2)
end
function ordered(zeta,eta)
    h = 1-dot(zeta,S4*eta)
    [I4+zeta*transpose(eta)*S4 zeta eta;
     transpose(eta)*S4 1 0;
     -transpose(zeta)*S4 0 h]
end
function direct_graph(M,tau)
    rr,rl,lr,ll=blocks(M)
    -(rr*rr+rl*lr-tau*rr+I4) \ (rr*rl+rl*ll-tau*rl)
end
function newton_correct(M,D)
    rr,rl,lr,ll=blocks(M)
    for iteration in 1:12
        D += sylvester_difference(rr-D*lr,ll+lr*D,-graph_residual(M,D))
        norm(graph_residual(M,D)) < 1e-13 && return D
    end
    error("Newton failed")
end
function trace_cubic(M)
    t1,t2,t3=tr(M),tr(M*M),tr(M*M*M)
    [1,-t1,(t1*t1-t2)/2-3,-(t1^3-3*t1*t2+2*t3)/6+2*t1]
end
function parzen_cubic(M)
    C=(M+inv(M))/2
    t=[tr(M[2a-1:2a,2a-1:2a])/2 for a in 1:3]
    c12,c23,c31=C[1:2,3:4],C[3:4,5:6],C[5:6,1:2]
    a2=-sum(t)
    a1=t[1]*t[2]+t[2]*t[3]+t[3]*t[1]-det(c12)-det(c23)-det(c31)
    a0=-prod(t)-tr(c12*c23*c31)+t[1]*det(c23)+t[2]*det(c31)+t[3]*det(c12)
    [1,2*a2,4*a1,8*a0]
end
negative_areas=0
negative_h=0
for trial in 1:100
    H=0.35randn(6,6); H=(H+H')/2
    U=exp(S6*H)
    phases=[0.43,1.27,(-1)^trial*2.13]
    tau=2cos.(phases)
    normal=zeros(6,6)
    for j in 1:3
        normal[2j-1:2j,2j-1:2j]=rotation(phases[j])
    end
    M=U*normal/U
    check("input symplecticity",M'*S6*M,S6)
    check("Parzen vs trace cubic",parzen_cubic(M),trace_cubic(M))
    check("cubic vs known modal traces",trace_cubic(M),
          [1,-sum(tau),tau[1]*tau[2]+tau[2]*tau[3]+tau[3]*tau[1],-prod(tau)])
    projector_sum=zeros(6,6); reconstruction=zeros(6,6)
    area=zeros(3,3); covariance=zeros(6,6)
    for j in 1:3
        pair=U[:,2j-1:2j]
        P=I6
        for k in 1:3
            j==k && continue
            P=P*(M+inv(M)-tau[k]*I6)/(tau[j]-tau[k])
        end
        G=-(M-inv(M))*P*S6/(2sin(phases[j]))
        check("D26 known-plane projector",P,-pair*S2*pair'*S6)
        check("6D E12 covariance",G,pair*pair')
        check("6D projector idempotence",P*P,P)
        check("6D projector symplectic adjoint",P'*S6,S6*P)
        for a in 1:3
            rows=2a-1:2a
            area[j,a]=det(pair[rows,:])
            check("K13 physical Twiss block",(M*P)[rows,rows],
                  area[j,a]*cos(phases[j])*I2+sin(phases[j])*G[rows,rows]*S2)
            check("K12 projected determinant",det(G[rows,rows]),area[j,a]^2)
        end
        projector_sum+=P
        reconstruction+=cos(phases[j])*P+sin(phases[j])*G*S6
        covariance+=j*G
        if j==3
            h=det(pair[5:6,:])
            global negative_h += h<0
            @assert abs(h)>1e-4
            D=pair[1:4,:]/pair[5:6,:]
            check("D27 signed longitudinal area",P[5:6,5:6],h*I2)
            check("D27 graph extraction",P[1:4,5:6]/h,D)
            check("D19 vs D27",direct_graph(M,tau[3]),D)
            check("D27 invariance",graph_residual(M,D),zeros(4,2))
        end
    end
    global negative_areas += count(<(0),area)
    check("6D completeness",projector_sum,I6)
    check("6D reconstruction",reconstruction,M)
    check("K12 mode area sums",sum(area,dims=2),ones(3,1))
    check("K12 physical plane area sums",sum(area,dims=1),ones(1,3))
    check("K12 matched covariance",M*covariance*M',covariance)
end
for h in [-2.0,-0.5,0.15,0.5,1.0,2.0]
    zeta=[0.7,0.1,-0.2,0.05]
    eta=[0.1,(1-h+0.1zeta[2]+0.02zeta[3]+0.03zeta[4])/zeta[1],0.03,-0.02]
    O=ordered(zeta,eta)
    check("signed ordered chart",O'*S6*O,S6)
    check("constructed h",det(O[5:6,5:6]),h)
    for j in 1:2
        Gbar=zeros(4,4); Gbar[2j-1:2j,2j-1:2j]=I2
        G=O[:,1:4]*Gbar*O[:,1:4]'
        check("K14 longitudinal covariance",G[5,5],dot(eta,S4*Gbar*S4'*eta))
    end
    normal=cat(rotation(0.43),rotation(1.27),rotation(2.13);dims=(1,2))
    M=O*normal/O
    tau=2cos.([0.43,1.27,2.13])
    P=(M+inv(M)-tau[1]*I6)*(M+inv(M)-tau[2]*I6)/
      ((tau[3]-tau[1])*(tau[3]-tau[2]))
    D=O[1:4,5:6]/O[5:6,5:6]
    check("signed h projector",P[5:6,5:6],h*I2)
    check("signed h graph",P[1:4,5:6]/h,D)
    check("signed h algebraic graph",direct_graph(M,tau[3]),D)
end
# Analytically known, smooth canonical family supplies independent derivatives.
H=randn(6,6); H=(H+H')/2
generator=0.25S6*H
normal=zeros(6,6)
for (j,mu) in enumerate([0.43,1.27,2.13])
    normal[2j-1:2j,2j-1:2j]=rotation(mu)
end
function family(t)
    U=exp(t*generator)
    M=U*normal/U
    D=U[1:4,5:6]/U[5:6,5:6]
    Udot=generator*U
    Ddot=(Udot[1:4,5:6]-D*Udot[5:6,5:6])/U[5:6,5:6]
    M,D,Ddot,generator*M-M*generator
end
M,D,Ddot,Mdot=family(0.3)
rr,rl,lr,ll=blocks(M)
drr,drl,dlr,dll=blocks(Mdot)
rhs=-drr*D-drl+D*dlr*D+D*dll
recovered=sylvester_difference(rr-D*lr,ll+lr*D,rhs)
check("D28 analytic derivative",recovered,Ddot)
check("D28 central difference",Ddot,(family(0.30001)[2]-family(0.29999)[2])/2e-5;limit=1e-9)
errors=Float64[]; fd_errors=Float64[]
for dt in [0.01,0.005,0.0025,0.00125]
    Mnew,Dnew=family(0.3+dt)
    predicted=D+dt*recovered
    push!(errors,norm(predicted-Dnew))
    frr,frl,flr,fll=blocks((Mnew-M)/dt)
    fd_rhs=-frr*D-frl+D*flr*D+D*fll
    fd_predicted=D+dt*sylvester_difference(rr-D*lr,ll+lr*D,fd_rhs)
    push!(fd_errors,norm(fd_predicted-Dnew))
    check("D29 corrected graph",newton_correct(Mnew,predicted),Dnew)
    check("D29 finite-difference corrected graph",newton_correct(Mnew,fd_predicted),Dnew)
end
ratios=errors[1:3]./errors[2:4]
fd_ratios=fd_errors[1:3]./fd_errors[2:4]
@assert all(3.9 .< ratios .< 4.1)
@assert all(3.9 .< fd_ratios .< 4.1)
# Chart boundary with constant, separated tunes: rotate y and z mode pairs.
function mixing(angle)
    O=copy(I6)
    for (a,b) in [(3,5),(4,6)]
        O[a,a]=O[b,b]=cos(angle)
        O[a,b]=sin(angle); O[b,a]=-sin(angle)
    end
    O
end
for angle in [1.4,pi/2,1.7]
    U=mixing(angle); boundary_map=U*normal/U
    check("chart-boundary canonical basis",U'*S6*U,S6)
    check("chart-boundary separated spectrum",sort(real.(eigvals(boundary_map+inv(boundary_map)))),
          sort(repeat(2cos.([0.43,1.27,2.13]),inner=2)))
end
U=mixing(pi/2)
@assert norm(U[5:6,5:6])<1e-14
@assert rank(U[:,5:6])==2
# Negative controls: omit reciprocal-cubic corrections, reverse derivative,
# and discard physical cross-plane signs.
wrong_cubic=trace_cubic(M); wrong_cubic[3]+=3; wrong_cubic[4]-=2tr(M)
@assert norm(wrong_cubic-parzen_cubic(M))>0.1
@assert norm(sylvester_difference(rr-D*lr,ll+lr*D,-rhs)-Ddot)>0.1
U=exp(0.3generator); G=U[:,5:6]*U[:,5:6]'
flip=Diagonal([-1.0,-1,1,1,1,1]); Gflip=flip*G*flip
@assert norm(G-Gflip)>1e-3
for a in 1:3
    check("sign ambiguity diagonal blocks",G[2a-1:2a,2a-1:2a],Gflip[2a-1:2a,2a-1:2a])
end
@assert negative_areas>0
println("Julia ",VERSION,"; Float64 CPU; Julia threads=",Threads.nthreads(),
        "; BLAS threads=",BLAS.get_num_threads(),"; seed=20260909; tol=",tol)
for name in sort(collect(keys(worst)))
    @printf("%-42s n=%3d max=%.17g\n",name,counts[name],worst[name])
end
println("negative projected areas=",negative_areas,"; random negative h=",negative_h)
println("tangent predictor errors=",errors,"; halving ratios=",ratios)
println("finite-difference predictor errors=",fd_errors,"; halving ratios=",fd_ratios)
println("three negative controls rejected; physical chart singularity detected; no fixture skipped")
```

<!-- source-probe-start -->
```julia
using LinearAlgebra, Random
BLAS.set_num_threads(1)
Random.seed!(20260909)
S2 = [0.0 1.0; -1.0 0.0]
S6 = kron(Matrix{Float64}(I, 3, 3), S2)
adj2(A) = -S2 * transpose(A) * S2
rotation(mu) = [cos(mu) sin(mu); -sin(mu) cos(mu)]
mu = [0.6, -1.2, 2.4]
tau = 2cos.(mu)
R = zeros(6, 6)
for j in 1:3
    R[2j-1:2j, 2j-1:2j] = rotation(mu[j])
end
let
errors = Dict(name => 0.0 for name in (:projector, :covariance, :cofactor, :weight, :twiss, :source_normalization, :weight_sums))
negative_weights = 0
negative_betas = 0
minimum_beta = Inf
minimum_weight = Inf
maximum_nonsymplecticity = 0.0
for trial in 1:300
    H = randn(6, 6)
    H = 0.4 * (H + transpose(H))
    U = exp(S6 * H)
    M = U * R / U
    C = M + inv(M)
    P = Matrix{Float64}[]
    weights = zeros(3, 3)
    b = [tr(M[2a-1:2a, 2a-1:2a]) for a in 1:3]
    for j in 1:3
        other = filter(!=(j), 1:3)
        Pj = (C - tau[other[1]] * I) * (C - tau[other[2]] * I) / prod(tau[j] .- tau[other])
        push!(P, Pj)
        Uj = U[:, 2j-1:2j]
        Pknown = -Uj * S2 * transpose(Uj) * S6
        Gj = -(M - inv(M)) * Pj * S6 / (2sin(mu[j]))
        Gknown = Uj * transpose(Uj)
        errors[:projector] = max(errors[:projector], norm(Pj-Pknown) / max(1, norm(Pknown)))
        errors[:covariance] = max(errors[:covariance], norm(Gj-Gknown) / max(1, norm(Gknown)))
        for a in 1:3
            ra = 2a-1:2a
            aa = Uj[ra, :]
            others = filter(!=(a), 1:3)
            cofactor = (b[others[1]]-tau[j])*(b[others[2]]-tau[j]) - det(C[2others[1]-1:2others[1], 2others[2]-1:2others[2]])
            weights[a,j] = 0.5tr(Pj[ra,ra])
            errors[:cofactor] = max(errors[:cofactor], abs(weights[a,j] - cofactor / prod(tau[j] .- tau[other])))
            errors[:weight] = max(errors[:weight], abs(weights[a,j]-det(aa)))
            basis = Pj[:,ra]
            Tij = -S2 * transpose(basis) * S6 * M * basis
            expected = weights[a,j] * cos(mu[j]) * Matrix{Float64}(I,2,2) + sin(mu[j]) * Gknown[ra,ra] * S2
            errors[:twiss] = max(errors[:twiss], norm(Tij-expected) / max(1,norm(expected)))
            beta = Tij[1,2] / sin(mu[j])
            negative_betas += beta < -1e-10
            negative_weights += weights[a,j] < -1e-10
            minimum_beta = min(minimum_beta, beta)
            minimum_weight = min(minimum_weight, weights[a,j])
        end
    end
    W1 = hcat(P[1][:,1:2], P[2][:,3:4], P[3][:,5:6])
    area_metric = kron(Diagonal(diag(weights)), Matrix{Float64}(I,2,2))
    errors[:source_normalization] = max(errors[:source_normalization], norm(transpose(W1)*S6*W1 - S6*area_metric) / max(1,norm(W1)^2))
    maximum_nonsymplecticity = max(maximum_nonsymplecticity, norm(transpose(W1)*S6*W1 - S6))
    errors[:weight_sums] = max(errors[:weight_sums], maximum(abs.(sum(weights,dims=1).-1)), maximum(abs.(sum(weights,dims=2).-1)))
end
println("Julia ", VERSION, "; threads=", Threads.nthreads(), "; BLAS threads=", BLAS.get_num_threads())
for name in sort!(collect(keys(errors)); by=string)
    println(name, "=", errors[name])
    @assert errors[name] < 1e-9
end
println("300 canonical stable maps; 2700 projections")
println("negative weights=", negative_weights, "; minimum weight=", minimum_weight)
println("negative betas=", negative_betas, "; minimum beta=", minimum_beta)
println("maximum source W1 canonical defect=", maximum_nonsymplecticity)
@assert negative_weights > 0
@assert negative_betas == 0
end
```

<!-- source-lint-start -->
```julia
function check_literature_source(note)
    @assert !occursin(r"(?m)^\$$",note) "standalone single-dollar delimiter"
    @assert !occursin("### 10.5",note) "out-of-scope section retained"
    @assert !occursin(r"\(G[1-7]\)",note) "stale removed-equation reference"
    for tag in ("D26","D27","D28","D29","K12","K13","K14")
        @assert occursin("\\tag{"*tag*"}",note) tag
    end
    for reference in ("acc-phys/9506001","10.1103/3ld3-dmmv","10.1002/nla.245")
        @assert occursin(reference,note) reference
    end
    nothing
end
note=read("docs/theory/twiss_dispersion.md",String)
check_literature_source(note)
for bad in (replace(note,r"(?m)^\$\$$"=>"\$";count=1),note*"\n(G1)")
    rejected=try
        check_literature_source(bad)
        false
    catch error
        error isa AssertionError || rethrow()
        true
    end
    @assert rejected
end
println("Literature source checks passed; single-dollar and stale-GLSF-reference controls rejected.")
```

## Verification gate, exclusions, and handoff

Targeted checks do not substitute for the gate. This batch changes only
Markdown, excluding the registry snapshot; inspect both tracked and
untracked names before using that classification. AGENTS.md requires:

```bash
julia --project=. --threads=4 -e 'using Pkg; Pkg.test(test_args=["lane=fast"], julia_args=["--threads=4"])'
```

The final-tree gate is run after this record is written. Its outcome must
come from actual test output, not these algebra checks; this record makes
no advance claim that the gate passes.

Outside scope: production analysis contracts (none implemented), tracked
physical-lattice optics, external-code execution, radiation/damping,
the removed GLSF lattice design, performance measurements, and resolving
individual modes at degeneracy. Full lane is not required for this
Markdown-only class; heavyweight fast-lane skips must remain visible.
Existing CUDA warnings are neither suppressed nor fixed.

Change log: theory/references; README index; current analysis todo row;
basis-normalization lesson; this reproducible report and its unit report.
Earlier histories and tracking/source/configuration files are unchanged.
Future implementation remains in the Twiss/dispersion row of docs/todo.md.
