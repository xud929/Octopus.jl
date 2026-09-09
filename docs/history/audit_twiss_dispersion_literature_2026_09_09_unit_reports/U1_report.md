# U1: Glukhov literature and post-edit neighbour review

Date: 2026-09-09. Read-only unit; no repository files changed by the unit.
This archive preserves the unit's findings as leads and records the primary
reviewer's dispositions separately. Numerical reproductions are embedded
in the [parent report](../audit_twiss_dispersion_literature_2026_09_09.md).

## Coverage and provenance

The unit read every page of S. Glukhov, “Symmetry properties of a symplectic
transport matrix and Twiss parameterization of a fully coupled motion,”
PRAB 28, 084001 (2025), including Appendices A–F and references.
[doi:10.1103/3ld3-dmmv](https://doi.org/10.1103/3ld3-dmmv).
PDF SHA-256:
3aaee8b3da5aed2846cef2f8e7ab999d2e93d678bdd782ca86dcac7db7c46b9f.

Pre-edit note regions read in full: Section 3.4 (line 250), Section 8.5
(1270), Section 9.3 (1534), Section 10.4 (1880), Sections 11–12 (2069),
references (2184), and the matched-ensemble qualification in 6.3 (747).
After editing, the unit read new D26–D29, K12–K14 and Sections 11–12.
Locations are historical pointers; equation labels are the durable identity.

The hypothesis was that the recurrent-matrix construction supports direct
6D projector extraction, but projected scalars and unnormalized source
columns are not a complete canonical normalizer.

## Results

The hypothesis is supported:

- Paper Sections III–VI, Eqs. 7, 9, 17 and 23–30 give the same three
  modal trace eigenvalues and normalized cofactor blocks as D26's
  spectral projectors. The product formula is our compact specialization,
  not a formula printed verbatim in the paper.
- E12–E14 extend to 6D with S6, including the positive-semidefinite G
  branch and map reconstruction. Appendix B excludes coincident modal
  traces; the denominator cannot be regularized by arbitrary labeling.
- The paper's large W1 assembles P1's horizontal column pair, P2's
  vertical pair and Ps's longitudinal pair. Its symplectic metric is
  S6 times diag(kappa_1x I2,kappa_2y I2,kappa_sz I2), not generally S6.
  It is neither our U6 nor Xsuite's normalized W.
- Paper Eqs. 35/38/47 give the signed-area row/column sums and projected
  determinant identity in K12; source physical-plane and mode indices
  have the opposite order to ours.
- Section VIII's physical coordinate-pair sign flips preserve projected
  scalar Twiss data but change interplane map blocks. This is missing
  cross-plane information, not harmless per-eigenvector phase freedom.
  Retaining full G+iPS or U6 preserves that information.
- Section X's covariance formula assumes a matched ensemble. The main
  note now repeats its uncorrelated-mode qualification at K10.

The complete scalar inverse parameterization is not needed: it adds
consistency conditions and inverse branches while the full basis already
supports unambiguous reconstruction up to modal phase.

## Leads and primary dispositions

### LEAD U1-1 [low, confidence high] docs/theory/twiss_dispersion.md:1534

Claim: Source-integration hazard only: do not import Glukhov Sec. VII's
statement allowing mixed projected-beta signs after choosing a positive
diagonal beta.

Mechanism: A projector column pair is Uj times the adjugate of the
corresponding physical projection. Its source Twiss block reduces to
kappa cos(mu) I2 + sin(mu) G_aa S2. Thus beta=G_aa's position diagonal
is nonnegative under our canonical phase convention; negative signed area
does not change that conclusion.

Repro: Execute the parent report's source-probe block. Expected 300 maps,
2700 projections, 921 negative areas, zero negative beta values, Twiss
identity residual below 1e-9.

Primary disposition: independently derived and rerun, confirmed under the
note's stable/simple convention. K13 states the positive covariance
convention; the source sentence was not imported. Not a pre-existing
Octopus defect or a claim about every exceptional source case.

### LEAD U1-2 [low, confidence high] docs/theory/twiss_dispersion.md:1372

Claim: D26–D29 initially used standalone single-dollar delimiters despite
being numbered display equations.

Mechanism: The inserted display delimiters had been transformed by the
text replacement operation, invalidating the intended display context.

Repro: Look for a line consisting of exactly one dollar sign around
D26–D29; eight were present before correction. The parent source-lint
block rejects an injected example.

Primary disposition: confirmed, all eight fixed; source check and
whole-note LaTeX compilation pass. The unit's additional suspicion that
the old renderer rewraps every expression as display was not borne out:
primary inspection showed it preserves inline/display distinctions.

### LEAD U1-3 [low, confidence high] docs/theory/twiss_dispersion.md:1566

Claim: The singular-chart fallback initially pointed to K9.

Mechanism: Canonically normalizing an auxiliary basis does not restore
the physical graph required by K9's ordered factorization.

Repro: Compare the first Section 8.8 failure bullet with D27 and K9
at h=0.

Primary disposition: confirmed and fixed. The text now uses full-mode
optics/covariance K10–K12, and applies K9 only where its chart exists.

## Executed measurements

Julia 1.12.4, four Julia threads, one BLAS thread, seed 20260909,
Float64, 300 stable maps generated with exp(S6 H), H symmetric.
Tolerance 1e-9; no skipped fixture. Exact metrics and runnable code
are in the parent report's source-probe block, rerun by the primary.

| Check | Largest error |
|---|---:|
| Projectors vs canonical basis | 5.155579115503474e-13 |
| Modal covariance | 1.1432503343238096e-13 |
| Source cofactor vs area weight | 1.5187850976872141e-12 |
| Area weight vs determinant | 1.5298873279334657e-13 |
| Source Twiss block identity | 2.7610040285339126e-13 |
| Source weighted symplectic metric | 1.6524403177703763e-14 |
| Area row/column sums | 4.75175454539567e-14 |

Minimum area -5.370169920378526; minimum projected beta
0.00020351916656215942. The source W1's actual canonical defect reaches
11.293415779115996, demonstrating that it is not automatically U6.
An initial soft-scope error was corrected in the scratch instrument
before these results; the archived probe exits zero.

## Post-edit clean results and exclusions

D26–D27 distinguish spectral from graph singularity. D28's derivative
signs/dimensions are correct; D29's order statement is conditional and
does not claim uncorrected final accuracy. K12–K14 handle signed areas,
nonnegative beta, matched covariance, and physical versus modal phase.
The implementation requirements do not promise unique modes at collisions.

Not executed by this unit: author's Python implementation, physical
lattice tracking, CUDA, Octopus suite, or degenerate-spectrum probes.
Dieci–Friedman source equation numbering was checked by the primary,
not this unit; the unit checked the added derivative algebra directly.
GLSF application algebra was outside the unit's assigned scope.
