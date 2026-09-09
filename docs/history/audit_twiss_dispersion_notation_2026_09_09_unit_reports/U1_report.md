# U1: transverse notation reading unit

Read-only review by the transverse_review agent, before and after the main
rewrite. Every line of Sections 1–7 and Appendix A was read. No repository
file was edited by this unit; no new numerical probe was executed by it.
The primary reviewer independently confirmed and corrected the text issues.
Line numbers below identify the pre-edit or intermediate reviewed revision;
equation labels remain the durable location.

## Pre-edit leads

### LEAD notation-1 [P2 presentation, confidence high] theory/twiss_dispersion.md:247

Claim: t_n, c_j, s_j are unnecessary aliases in E10–E14.
Mechanism: They hide traces and the already defined phase mu_j.
Repro: Substitute tr(M), cos(mu_j), sin(mu_j) directly; retain the
positive-semidefinite criterion selecting the sine sign.

### LEAD notation-2 [P2 presentation, confidence high] theory/twiss_dispersion.md:299

Claim: A/B/C/D/E/F change meaning between T1 and P1–P6.
Mechanism: Periodic and section maps reuse all six unqualified letters.
Repro: Use physical-plane-indexed M/L blocks and decoupled M_j/L_j;
the four transport-table products remain the same.

### LEAD notation-3 [P2 dimensional ambiguity, confidence high] theory/twiss_dispersion.md:817

Claim: The amplitude sqrt(2J) uses a name defined as a 2×2 matrix.
Mechanism: C1 defines J as the symplectic matrix; E9 defines J_j as action.
Repro: Use sqrt(2J_j) and reserve S2/S4/S6 for symplectic matrices.

### LEAD notation-4 [P2 presentation, confidence high] theory/twiss_dispersion.md:271

Claim: E14's pivot index and subsequent physical-plane indices are ambiguous.
Mechanism: The old pivot a meant any coordinate, then a meant x/y; the
H-entry formulas additionally used undeclared q/p coordinate indices.
Repro: Declare a pivot coordinate and use actual a,p_a scalar entry labels.

### LEAD notation-5 [P2 dimensional ambiguity, confidence high] theory/twiss_dispersion.md:1009

Claim: Removing H_j must not make (G_j)_xx mean both a scalar and a block.
Mechanism: B11 uses a full 2×2 x,p_x block, whereas beta_jx is one entry.
Repro: Use explicit coordinate-pair indices for the B11 blocks.

### LEAD notation-6 [P3 presentation, confidence high] theory/twiss_dispersion.md:103

Claim: Overbars have unrelated adjugate and decoupled-coordinate meanings.
Mechanism: C4–C5 and Sections 8–10 require a reader to choose the operation.
Repro: Spell the adjugate as adj(K), retaining overbars for decoupled objects.

### LEAD notation-7 [P3 presentation, confidence high] theory/twiss_dispersion.md:313

Claim: ET "mode 1/2" competes with physical eigenmode numbering.
Mechanism: The propagation table requires repeatedly recovering the distinction.
Repro: Use "form 1/2" for ET, retaining mode labels for physical oscillations.

### LEAD notation-8 [P2 dimensional clarity, confidence high] theory/twiss_dispersion.md:2003

Claim: Appendix A silently shrinks the full dispersion vectors and graph.
Mechanism: A1 uses four-component quantities as two-component quantities.
Repro: Write the x,p_x rows explicitly, zero the vertical rows, and state the
selected form's h=lambda²>0 domain.

## Post-edit neighbour leads

The intermediate revision had five concrete issues:

1. T1/P1 retained two lower-left C entries instead of M_yx/L_yx.
2. All 16 MR tags became M_41 through M_416 while references remained M1–M16.
3. Thirteen endpoint adjugates read adj(R)_in instead of adj(R_in).
4. The full-coordinate conversion paragraph retained bare L and U_i instead
   of dimensioned L6 and full endpoint bases U_{6,i}.
5. The heading and propagation introduction contained "form 2s."

The primary reviewer confirmed all five and fixed them. The main record's
syntax probe injects representative stale-block and tag defects and rejects
them. Subsequent primary checks also found joined LaTeX commands.

## Clean and excluded regions

No algebra defect was found in the assigned pre-edit regions. On the
post-edit read, B11's pair indices, projector/eigenvector relations, phase
signs, and Appendix A's positive-h and dimensional qualifications were
consistent. Sections 8–12, rendering, the final numerical probes, and package
gating were the primary reviewer's scope, not this unit's.
