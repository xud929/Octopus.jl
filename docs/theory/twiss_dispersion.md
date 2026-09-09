# Coupled Twiss and dispersion: theory and analysis requirements

Status: theory draft for the first concrete Octopus analysis. No optics analysis
API is implemented by this document; the current analysis layer contains only
`PlaceholderAnalysis`. This note derives the mathematics and the requirements
an implementation must satisfy. Architecture and public API decisions belong in
`docs/design/` and source docstrings when implementation begins.

Reading order: Sections 2–7 cover 4D extraction and parameterization conversion;
Sections 8–9 cover direct and eigenbasis-based 6D decoupling; Section 10 covers
transport and mode identity. Sections 11–12 specify future implementation
requirements and verification coverage. Appendix A is the single-plane reduction.
The original draft's equation labels are retained where practical.

## 1. Purpose and conventions

This note develops a planned Octopus linear-optics analysis that obtains
coupled Twiss functions and dispersion from a real symplectic transfer matrix.
The periodic solution requires a one-turn map evaluated about a closed orbit
at the observation point. An element or transport-line matrix propagates an
initialized optics solution; it does not by itself determine periodic Twiss
functions.

The transverse analysis uses symplectically normalized eigenvectors as its primary representation. Edwards–Teng parameters are derived and compared with Sagan and Rubin [1]. Generalized Mais–Ripken functions follow the symplectic eigenvector formulation of Lebedev and Bogacz [2]. Crab and momentum dispersion follow the definitions and ordered canonical transformation of Xu, Luo, and Hao [3].

Ohmi–Hirata–Oide [5] supply a second explicit 6D canonical factorization;
Section 9 derives its conversion to the ordered transformation used here and
compares construction of Xsuite's normalizer [6–8]. Parzen [9] gives the
6D tune cubic; Glukhov [10] develops the symmetric three-mode construction;
Dieci–Friedman [11] connect invariant-subspace continuation with Riccati
iteration. We translate the useful results into the notation below and derive
their connection to the dispersion graph. These are connections between
established formalisms; this note makes no claim of priority for its algebraic
rearrangements.

For a 6×6 map, the longitudinal invariant plane determines the dispersion transformation. Removing that plane canonically supplies the symplectic 4×4 betatron map to which the transverse analysis applies. The normalizing basis is retained throughout so that mode identity, phase, reconstruction, and physical beam covariance remain accessible.

Notation is kept across parameterizations: the same physical quantity
keeps the same symbol. Source-paper names appear only in explicit
translations. The principal symbols are:

| Symbol | Meaning and size |
|---|---|
| $S_2,S_4,S_6$ | Canonical symplectic matrices, with dimensions indicated by the subscript. |
| $\mathbf r,\boldsymbol\ell,\mathbf X$ | Physical transverse 4-vector, longitudinal 2-vector, and full 6-vector. |
| $M_4,M_6$; $L_4,L_6$ | Periodic one-turn maps; section transfer maps between observation points. |
| $\bar M_j,\bar L_j$ | Decoupled 2×2 maps of eigenmode $j$, periodic and section respectively. |
| $\mathbf u_j,U_j$ | Normalized complex eigenvector and its real two-column pair; 4 or 6 rows according to the problem. The scalar $u_{j,a}$ is its component at physical coordinate $a$. |
| $U_4,U_6$ | Full real symplectic normalizers, 4×4 and 6×6, mapping normal to physical coordinates. |
| $U_{rs},U_{\ell s}$ | Transverse 4×2 and longitudinal 2×2 projections of the 6D longitudinal pair $U_s$. |
| $\mu_j,Q_j,\tau_j$ | One-turn phase, fractional tune, and eigenmode trace $2\cos\mu_j$. |
| $J_j,\epsilon_j$ | Single-particle action and rms ensemble eigenmode emittance. |
| $P_j,G_j$ | Invariant-plane projector and unit-emittance modal covariance; 4×4 in Section 3 and 6×6 when extended to full modes. |
| $R,\lambda,V_1,V_2$ | Edwards–Teng coupling matrix (2×2), scalar normalization, and two 4×4 canonical forms. |
| $\beta_j,\alpha_j,\gamma_j,\mathcal Q_j,\mathcal B_j$ | Unit-area eigenmode Twiss functions, 2×2 Twiss matrix, and 2×2 Courant–Snyder normalizer. |
| $\beta_{ja},\alpha_{ja},\gamma_{ja}$ | Mais–Ripken projections of eigenmode $j$ onto physical plane $a=x,y$; extended to $a=z$ for full 6D modes. |
| $\kappa_{ja},u,\nu_j$ | Projected signed symplectic area, shared 4D area partition, and relative transverse projection phase. Scalar $u$ is not the vector $\mathbf u_j$. |
| $\boldsymbol\zeta,\boldsymbol\eta$ | Canonical crab and momentum dispersion, each a transverse 4-vector. |
| $\mathscr D,h$ | Physical longitudinal graph (4×2) and signed longitudinal area of the normalized mode; $h=1-\boldsymbol\zeta^TS_4\boldsymbol\eta$. |
| $\mathcal M,\mathcal M_{\rm O}$ | Ordered and Ohmi 6×6 canonical transformations from their respective decoupled coordinates to physical coordinates. |

An overbar always identifies a quantity in decoupled canonical coordinates;
$\operatorname{adj}$ denotes the 2×2 adjugate. Matrix subscripts identifying
coordinate blocks are defined with each partition. For scalar entries of a
covariance or projector, coordinate labels identify individual rows and columns;
a parenthesized coordinate list explicitly selects a multi-coordinate block.
Use $\mathrm{in}/\mathrm{out}$ for endpoints and $j=1,2,s$ for physical
eigenmodes. "Form 1/2" refers only to the two Edwards–Teng matrix forms.

## 2. Coordinates, symplectic form, and assumptions

Use the transverse coordinates

$$
\mathbf r=(x,p_x,y,p_y)^T,
\qquad
S_2=\begin{pmatrix}0&1\\-1&0\end{pmatrix},
\qquad
S_4=\operatorname{diag}(S_2,S_2).
\tag{C1}
$$

For 6D analysis, use

$$
\mathbf X=(x,p_x,y,p_y,z,p_z)^T
=\begin{pmatrix}\mathbf r\\\boldsymbol\ell\end{pmatrix},
\quad
\boldsymbol\ell=(z,p_z)^T,
\quad S_6=\operatorname{diag}(S_4,S_2).
\tag{C2}
$$

The convention is $\{x,p_x\}=\{y,p_y\}=\{z,p_z\}=+1$. Here $p_x,p_y,p_z$ are canonical momenta with a fixed reference normalization; the coordinates represent deviations from the reference orbit. In particular, $p_z$ denotes the longitudinal canonical momentum used by the map, and all momentum dispersion derivatives below are taken with respect to this variable.

For Octopus tracking, the concrete longitudinal convention is
$z=s-\ell$ and $p_z=\delta=(P-P_0)/P_0$:
see [the longitudinal-convention derivation](lattice_hamiltonian_and_conventions.md)
and [the runtime convention](../../src/track/longitudinal.jl).
Transverse momenta are normalized to the same fixed $P_0$; positions have units
of length. The closed-orbit linearization and coordinate conversion must use
the same observation point, reference energy, and survey coordinate.
Arrival-time coordinates are not interchangeable with the path deficit.

For a coordinate change $\mathbf X\mapsto\widetilde{\mathbf X}$, let
$C_i=\partial\widetilde{\mathbf X}/\partial\mathbf X$ be its Jacobian at the
reference orbit at endpoint $i$. Transform a section map by
$\widetilde L_6=C_{\rm out}L_6C_{\rm in}^{-1}$, its basis by
$\widetilde U_{6,i}=C_iU_{6,i}$, and covariance by
$\widetilde\Sigma_{6,i}=C_i\Sigma_{6,i}C_i^T$. For a periodic map the endpoint convention
must close so this becomes a similarity transformation. A noncanonical scaling
also changes the represented symplectic form; do not test it against unchanged
$S_6$. Acceleration or a changing reference normalization requires explicit
endpoint bookkeeping, not an assumption of a fixed periodic symplectic map.

The input matrix must already be expressed in these coordinates and units. Mechanical slopes cannot replace canonical momenta without the appropriate coordinate conversion, particularly in solenoids; see Eqs. (2.3)–(2.14) of Ref. [2].

The assumed map is real, conservative, and symplectic:

$$
M_d^TS_dM_d=S_d,\qquad d=4\ \text{or}\ 6.
\tag{C3}
$$

Radiation damping, stochastic excitation, and other non-Hamiltonian effects require a separate damped-optics/covariance treatment. A transfer matrix also does not determine beam emittances; these are additional beam inputs.

For any real 2×2 matrix $K$, define the symplectic adjugate:

$$
\operatorname{adj}(K)=-S_2K^TS_2
=\begin{pmatrix}K_{22}&-K_{12}\\-K_{21}&K_{11}\end{pmatrix}.
\tag{C4}
$$

Thus

$$
K\operatorname{adj}(K)=\operatorname{adj}(K)K=(\det K)I,
\quad \operatorname{adj}(KL)=\operatorname{adj}(L)\,\operatorname{adj}(K),
\quad K+\operatorname{adj}(K)=(\operatorname{tr}K)I.
\tag{C5}
$$

Use $\operatorname{adj}$ only for the 2×2 adjugate, $^*$ for complex
conjugation, and $^\dagger$ for Hermitian transpose. Overbars are reserved
for decoupled canonical coordinates and their maps, bases, or covariances.

## 3. Eigenanalysis as the underlying 4D representation

### 3.1 Eigenvalues and the stable domain

Let $M_4\in\mathrm{Sp}(4,\mathbb R)$. Reality and symplecticity imply conjugate and reciprocal spectral symmetry. In the stable elliptic, nondegenerate case, the four eigenvalues form two distinct conjugate pairs on the unit circle:

$$
e^{-i\mu_1},\ e^{+i\mu_1},\
e^{-i\mu_2},\ e^{+i\mu_2}.
\tag{E1}
$$

The ordinary formulas below assume no eigenvalue at $\pm1$ and no coincidence between the two conjugate pairs. Unit modulus alone is insufficient for bounded motion if a Jordan block is present. At a degeneracy, an individual mode basis need not be unique even if the invariant subspace is well defined.

A one-turn matrix determines fractional tunes. It does not determine the integer tune or the number of phase windings through the lattice.

### 3.2 Symplectic orthogonality

For $M_4\mathbf v_j=\rho_j\mathbf v_j$, symplecticity gives

$$
(1-\rho_j\rho_k)\mathbf v_j^TS_4\mathbf v_k=0,
\qquad
(1-\rho_j^*\rho_k)\mathbf v_j^\dagger S_4\mathbf v_k=0.
\tag{E2}
$$

These follow by inserting $M_4^TS_4M_4=S_4$ between the vectors. They establish the cross-mode orthogonality in the nondegenerate case.

For a complex vector $\mathbf v$, $\mathbf v^\dagger S_4\mathbf v$ is purely imaginary. Conjugating $\mathbf v$ reverses its sign. Choose one member of each conjugate pair and scale it so that

$$
\boxed{\mathbf u_j^\dagger S_4\mathbf u_j=-2i.}
\tag{E3}
$$

For an eigensolver output $\mathbf v$, select the conjugate-pair member with $\operatorname{Im}(\mathbf v^\dagger S_4\mathbf v)<0$, and set

$$
\mathbf u=
\sqrt{\frac{-2}{\operatorname{Im}(\mathbf v^\dagger S_4\mathbf v)}}\,\mathbf v.
\tag{E4}
$$

Reject or flag an almost-zero symplectic norm using a scale-aware criterion. Euclidean normalization does not replace (E3).

With $\rho_j$ belonging to this chosen vector, define

$$
\mu_j=\operatorname{mod}[-\arg(\rho_j),2\pi],
\qquad Q_j=\mu_j/(2\pi).
\tag{E5}
$$

Do not select eigenvectors solely by the sign of the imaginary part of their eigenvalues: that would implicitly restrict the phase branch and can return the wrong orientation.

### 3.3 Real normalizing matrix and reconstruction

Form the real normalizing matrix

$$
\boxed{U_4=[\operatorname{Re}\mathbf u_1,-\operatorname{Im}\mathbf u_1,
\operatorname{Re}\mathbf u_2,-\operatorname{Im}\mathbf u_2].}
\tag{E6}
$$

Equation (E3) gives $(\operatorname{Re}\mathbf u_j)^TS_4(-\operatorname{Im}\mathbf u_j)=1$. Together with (E2), this proves

$$
U_4^TS_4U_4=S_4,
\qquad U_4^{-1}=-S_4U_4^TS_4.
\tag{E7}
$$

Define

$$
\mathcal R(\mu)=\begin{pmatrix}\cos\mu&\sin\mu\\-\sin\mu&\cos\mu\end{pmatrix}.
$$

Taking real and imaginary parts of the eigenvector equation gives

$$
M_4U_4=U_4\operatorname{diag}(\mathcal R(\mu_1),\mathcal R(\mu_2)),
$$

and hence

$$
\boxed{M_4=U_4\operatorname{diag}(\mathcal R(\mu_1),\mathcal R(\mu_2))U_4^{-1}.}
\tag{E8}
$$

This is the central reconstruction identity and a numerical acceptance test. It agrees with Eqs. (2.19), (3.2), and (3.6)–(3.7) of Ref. [2].

For normal coordinates $\boldsymbol\xi=U_4^{-1}\mathbf r$,

$$
J_j=\frac{\xi_{2j-1}^2+\xi_{2j}^2}{2}
=\frac{|\mathbf u_j^\dagger S_4\mathbf r|^2}{2}.
\tag{E9}
$$

Thus the normalization fixes the action scale, not just the eigenvector shape.

### 3.4 Closed-form extraction without 4D eigenvectors

The three parameterizations describe the same nondegenerate stable map.
They can be extracted directly using the eigenmode traces
$\tau_j=2\cos\mu_j$ and real invariant-plane projectors. Before mode assignment,

$$
\boxed{\tau_\pm=
\frac{\operatorname{tr}M_4\pm
\sqrt{2\operatorname{tr}(M_4^2)-(\operatorname{tr}M_4)^2+8}}2.}
\tag{E10}
$$

This follows from $\operatorname{tr}M_4=\tau_1+\tau_2$ and
$\operatorname{tr}(M_4^2)=\tau_1^2+\tau_2^2-4$. For $j\ne k$, define

$$
\boxed{P_j=\frac{M_4+M_4^{-1}-\tau_k I_4}{\tau_j-\tau_k}.}
\tag{E11}
$$

On mode $j$, $M_4+M_4^{-1}=\tau_j I$; consequently $P_j^2=P_j$,
$P_1+P_2=I$, and $P_jP_k=0$. These are symplectic invariant-plane
projectors, not generally Euclidean orthogonal projectors.

Set $\cos\mu_j=\tau_j/2$ and choose the sign of
$\sin\mu_j=\pm\sqrt{1-(\tau_j/2)^2}$ so that

$$
\boxed{G_j=-\frac{(M_4-M_4^{-1})P_jS_4}{2\sin\mu_j}}
\tag{E12}
$$

is positive semidefinite of rank two. In the exact elliptic domain one sign
gives the normalized positive modal covariance and the other its negative.
Do not impose $\sin\mu_j>0$: this would lose tunes above one half.
To prove (E12), write $P_j=U_j(-S_2U_j^TS_4)$, where
$U_j=[\operatorname{Re}\mathbf u_j,-\operatorname{Im}\mathbf u_j]$
is the real 4×2 column pair in (E6), and use
$(M_4-M_4^{-1})U_j=2\sin(\mu_j)\,U_jS_2$. Then $G_j=U_jU_j^T$.

The real modal covariance and projector also determine the complex
outer product, which retains relative phases between physical components:

$$
\boxed{\mathbf u_j\mathbf u_j^\dagger=G_j+iP_jS_4.}
\tag{E13}
$$

Indeed, $P_jS_4=U_jS_2U_j^T=\operatorname{Im}(\mathbf u_j\mathbf u_j^\dagger)$.
Choose a physical coordinate $b\in\{x,p_x,y,p_y\}$ with $(G_j)_{b,b}>0$.
Making that component real and positive gives

$$
\boxed{\mathbf u_j=
\frac{(G_j+iP_jS_4)_{:b}}{\sqrt{(G_j)_{b,b}}},
\qquad
M_4=\sum_{j=1}^2(\cos(\mu_j)P_j+\sin(\mu_j)G_jS_4).}
\tag{E14}
$$

Choose a well-scaled nonzero pivot; it need not be a position component.
Thus a complete closed-form eigenmode extraction requires scalar square
roots and matrix arithmetic, not a 4D eigenvector solve. This is an
alternative and an independent check, not a claim of better conditioning
than a numerical eigensolver. Coincident traces and $\sin\mu_j=0$ are excluded.

For a physical plane $a=x,y$, the Mais–Ripken projections are
$\beta_{ja}=(G_j)_{a,a}$, $\alpha_{ja}=-(G_j)_{a,p_a}$,
$\gamma_{ja}=(G_j)_{p_a,p_a}$, and $\kappa_{ja}=(P_jS_4)_{a,p_a}$.
Here $p_a$ is the momentum paired with $a$. The relative phase products
are entries of $\mathbf u_j\mathbf u_j^\dagger$, including their sine signs.
Section 6 gives the equivalent component formulas.
Section 7.5 supplies the direct Edwards–Teng extraction.

## 4. Edwards–Teng periodic solution

### 4.1 Edwards–Teng forms 1 and 2

Partition the transverse map into 2×2 physical-plane blocks, where each
$x$ block label denotes the pair $(x,p_x)$ and each $y$ label denotes
$(y,p_y)$:

$$
M_4=\begin{pmatrix}M_{xx}&M_{xy}\\M_{yx}&M_{yy}\end{pmatrix},
\qquad M_4=V\operatorname{diag}(\bar M_1,\bar M_2)V^{-1}.
\tag{T1}
$$

Use the two Edwards–Teng parameterization forms

$$
V_1(R)=\lambda\begin{pmatrix}I&\operatorname{adj}(R)\\-R&I\end{pmatrix},
\qquad
V_2(R)=\lambda\begin{pmatrix}\operatorname{adj}(R)&I\\I&-R\end{pmatrix}.
\tag{T2}
$$

Throughout this note, **form 1** and **form 2** identify these two matrix forms. The two physical oscillations are called **eigenmodes**, indexed by $j=1,2$. The selected Edwards–Teng form and the physical eigenmode identities are recorded separately.

Direct multiplication gives $V_1^TS_4V_1=\lambda^2(1+\det R)S_4$. Therefore

$$
\boxed{1+\det R>0,\qquad
\lambda=\frac1{\sqrt{1+\det R}}.}
\tag{T3}
$$

The same condition holds for $V_2$. Replacing $1+\det R$ by its absolute value outside this domain would give $V^TS_4V=-S_4$, which is not a canonical normalization.

The two forms obey

$$
\boxed{\begin{gathered}
V_2=V_1\begin{pmatrix}0&I\\I&0\end{pmatrix},\\
V_1\operatorname{diag}(\bar M_1,\bar M_2)V_1^{-1}
=V_2\operatorname{diag}(\bar M_2,\bar M_1)V_2^{-1}.
\end{gathered}}
\tag{T4}
$$

This identity exchanges the normal-coordinate column pairs and their corresponding blocks while retaining the physical coordinate order. Section 5 describes changes of parameterization during transport while following the physical eigenmodes.

### 4.2 Coupling matrix from the physical map

For form 1, multiply $M_4=V_1\operatorname{diag}(\bar M_1,\bar M_2)V_1^{-1}$:

$$
\begin{aligned}
M_{xx}&=\lambda^2(\bar M_1+\operatorname{adj}(R)\bar M_2R),&
M_{xy}&=\lambda^2(-\bar M_1\operatorname{adj}(R)+\operatorname{adj}(R)\bar M_2),\\
M_{yx}&=\lambda^2(-R\bar M_1+\bar M_2R),&
M_{yy}&=\lambda^2(\bar M_2+R\bar M_1\operatorname{adj}(R)).
\end{aligned}
\tag{T5}
$$

The adjugate identities (C5) give

$$
\begin{aligned}
\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy}
&=\frac{1-\det R}{1+\det R}
(\operatorname{tr}\bar M_1-\operatorname{tr}\bar M_2),\\
\operatorname{adj}(M_{xy})+M_{yx}
&=-\frac{\operatorname{tr}\bar M_1-\operatorname{tr}\bar M_2}{1+\det R}R.
\end{aligned}
\tag{T6}
$$

Squaring the first identity and adding four times the determinant of the
second gives the discriminant, the squared separation of the eigenmode traces:

$$
\boxed{\Delta=
(\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy})^2
+4\det(\operatorname{adj}(M_{xy})+M_{yx})
=(\operatorname{tr}\bar M_1-\operatorname{tr}\bar M_2)^2.}
\tag{T7}
$$

For distinct eigenmode traces,

$$
\boxed{R=
-\frac{2(\operatorname{adj}(M_{xy})+M_{yx})}
{\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy}+\operatorname{tr}\bar M_1-\operatorname{tr}\bar M_2}.}
\tag{T8}
$$

The trace difference $\operatorname{tr}\bar M_1-\operatorname{tr}\bar M_2$ is one of the two signs of $\sqrt\Delta$. When $\operatorname{tr}M_{xx}\ne\operatorname{tr}M_{yy}$, the branch connected to $R=0$ in the uncoupled limit is

$$
\boxed{R=
-\frac{2\operatorname{sign}(\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy})
(\operatorname{adj}(M_{xy})+M_{yx})}
{|\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy}|+\sqrt\Delta}.}
\tag{T9}
$$

Equation (T9) is an initialization branch, not a mode-continuation rule.
A prescribed eigenmode ordering can require the other sign in (T8) or the
other Edwards–Teng form. Do not reapply the sign-of-trace rule at every point
and silently exchange physical eigenmodes.

Its determinant and normalization are

$$
\boxed{\begin{aligned}
\det R&=\frac{\sqrt\Delta-|\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy}|}
{\sqrt\Delta+|\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy}|},\\
\lambda^2&=\frac12\left(1+
\frac{|\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy}|}{\sqrt\Delta}\right).
\end{aligned}}
\tag{T10}
$$

For $\Delta>0$, this branch has $-1<\det R\le1$. Negative $\det R$ is admissible and gives $\lambda>1$. If $\operatorname{tr}M_{xx}=\operatorname{tr}M_{yy}$ and $\Delta>0$, use (T8) with the trace ordering fixed by eigenmode continuity; then $\det R=1$ and $\lambda^2=1/2$. Evaluating (T9) with a zero sign would lose the coupling. At $\Delta=0$, the distinct-eigenmode assumption fails.

The normal blocks follow directly from $M_4V=V\operatorname{diag}(\bar M_1,\bar M_2)$:

$$
\boxed{\begin{array}{lll}
\text{form 1:}&\bar M_1=M_{xx}-M_{xy}R,&\bar M_2=M_{yy}+M_{yx}\operatorname{adj}(R),\\
\text{form 2:}&\bar M_1=M_{yy}+M_{yx}\operatorname{adj}(R),&\bar M_2=M_{xx}-M_{xy}R.
\end{array}}
\tag{T11}
$$

No division by $\det(\operatorname{adj}(M_{xy})+M_{yx})$ occurs. Nonzero rank-one coupling is therefore included when the trace discriminant is nonzero.

### 4.3 Comparison with Sagan and Rubin

The diagonal scalar in the decoupling matrix of Ref. [1] is $\lambda$, and its upper-right coupling block is $\lambda\operatorname{adj}(R)$. Equations (T3), (T9), and (T10) imply

$$
\boxed{\begin{aligned}
\lambda^2+\det(\lambda\operatorname{adj}(R))&=\lambda^2(1+\det R)=1,\\
\lambda\operatorname{adj}(R)
&=-\frac{\operatorname{sign}(\operatorname{tr}M_{xx}-\operatorname{tr}M_{yy})
(M_{xy}+\operatorname{adj}(M_{yx}))}{\lambda\sqrt\Delta}.
\end{aligned}}
\tag{T12}
$$

These are Eqs. (8)–(10) of Ref. [1], expressed with the physical blocks of (T1). The appearance of $M_{xy}+\operatorname{adj}(M_{yx})$ in (T12) follows by taking the adjugate of $\operatorname{adj}(M_{xy})+M_{yx}$ in (T9). The normal-block formulas in that reference then reduce to (T11).

### 4.4 Stability and eigenmode Twiss functions

The two eigenmode traces, before assigning their physical labels, are

$$
\tau_\pm=\frac{\operatorname{tr}M_{xx}+\operatorname{tr}M_{yy}\pm\sqrt\Delta}{2}.
\tag{T13}
$$

For the nondegenerate elliptic case require

$$
\Delta>0,\qquad |\tau_+|<2,\qquad |\tau_-|<2.
\tag{T14}
$$

Check the spectrum and reconstruction residuals as well. For example, $\operatorname{diag}(2,1/2,\mathcal R(1.2))$ is symplectic and has a positive discriminant, but one eigenmode is hyperbolic.

For eigenmode $j=1,2$, the 2×2 map $\bar M_j$ gives

$$
\cos\mu_j=\tfrac12\operatorname{tr}\bar M_j,\qquad
\sin\mu_j=\operatorname{sign}((\bar M_j)_{12})\sqrt{1-\cos^2\mu_j}.
$$

The eigenmode Twiss functions are

$$
\boxed{\beta_j=\frac{(\bar M_j)_{12}}{\sin\mu_j},\qquad
\alpha_j=\frac{(\bar M_j)_{11}-(\bar M_j)_{22}}{2\sin\mu_j},\qquad
\gamma_j=-\frac{(\bar M_j)_{21}}{\sin\mu_j}.}
\tag{T15}
$$

Thus $\beta_j>0$, $\beta_j\gamma_j-\alpha_j^2=1$, and

$$
\bar M_j=\begin{pmatrix}
\cos\mu_j+\alpha_j\sin\mu_j&\beta_j\sin\mu_j\\
-\gamma_j\sin\mu_j&\cos\mu_j-\alpha_j\sin\mu_j
\end{pmatrix},
\quad \mu_j=\operatorname{mod}[\operatorname{atan2}(\sin\mu_j,\cos\mu_j),2\pi].
\tag{T16}
$$

Near $\sin\mu_j=0$, this extraction is ill conditioned. A significantly unstable trace must not be clipped to the stable interval.

The Courant–Snyder normalizer is

$$
\mathcal B_j=\begin{pmatrix}\sqrt{\beta_j}&0\\
-\alpha_j/\sqrt{\beta_j}&1/\sqrt{\beta_j}\end{pmatrix},
\qquad \mathcal B=\operatorname{diag}(\mathcal B_1,\mathcal B_2).
\tag{T17}
$$

In a compatible phase convention, $U_4=V\mathcal B$. The form 2 generally requires an additional phase adjustment to satisfy the Mais–Ripken position convention of Section 6.

## 5. Edwards–Teng propagation

Let the section map and its decoupled representation be

$$
L_4=\begin{pmatrix}L_{xx}&L_{xy}\\L_{yx}&L_{yy}\end{pmatrix},
\qquad L_4V_{\rm in}=V_{\rm out}\operatorname{diag}(\bar L_1,\bar L_2).
\tag{P1}
$$

Here $V_{\rm in},V_{\rm out}$ are the selected Edwards–Teng forms at the endpoints, and $\bar L_1,\bar L_2$ transport the two physical eigenmodes. Direct multiplication gives

$$
\begin{aligned}
L_4V_1(R_{\rm in})
&=\lambda_{\rm in}
\begin{pmatrix}
L_{xx}-L_{xy}R_{\rm in}&L_{xx}\operatorname{adj}(R_{\rm in})+L_{xy}\\
L_{yx}-L_{yy}R_{\rm in}&L_{yx}\operatorname{adj}(R_{\rm in})+L_{yy}
\end{pmatrix},\\
L_4V_2(R_{\rm in})
&=\lambda_{\rm in}
\begin{pmatrix}
L_{xx}\operatorname{adj}(R_{\rm in})+L_{xy}&L_{xx}-L_{xy}R_{\rm in}\\
L_{yx}\operatorname{adj}(R_{\rm in})+L_{yy}&L_{yx}-L_{yy}R_{\rm in}
\end{pmatrix}.
\end{aligned}
\tag{P2}
$$

If the parameterization remains in form 1 or remains in form 2,

$$
\boxed{\begin{aligned}
R_{\rm out}&=-(L_{yx}-L_{yy}R_{\rm in})(L_{xx}-L_{xy}R_{\rm in})^{-1},\\
\lambda_{\rm out}&=\lambda_{\rm in}\sqrt{\det(L_{xx}-L_{xy}R_{\rm in})}.
\end{aligned}}
\tag{P3}
$$

This requires $\det(L_{xx}-L_{xy}R_{\rm in})=\det(L_{yx}\operatorname{adj}(R_{\rm in})+L_{yy})>0$. For a change from form 1 to form 2, or from form 2 to form 1,

$$
\boxed{\begin{aligned}
R_{\rm out}&=-(L_{yx}\operatorname{adj}(R_{\rm in})+L_{yy})(L_{xx}\operatorname{adj}(R_{\rm in})+L_{xy})^{-1},\\
\lambda_{\rm out}&=\lambda_{\rm in}\sqrt{\det(L_{xx}\operatorname{adj}(R_{\rm in})+L_{xy})}.
\end{aligned}}
\tag{P4}
$$

This requires $\det(L_{xx}\operatorname{adj}(R_{\rm in})+L_{xy})=\det(L_{yx}-L_{yy}R_{\rm in})>0$. Comparing the remaining blocks of (P2) gives:

| Initial → final parameterization | $\bar L_1$ | $\bar L_2$ |
|---|---|---|
| Form 1 → form 1 | $\dfrac{\lambda_{\rm in}}{\lambda_{\rm out}}(L_{xx}-L_{xy}R_{\rm in})$ | $\dfrac{\lambda_{\rm in}}{\lambda_{\rm out}}(L_{yx}\operatorname{adj}(R_{\rm in})+L_{yy})$ |
| Form 1 → form 2 | $\dfrac{\lambda_{\rm in}}{\lambda_{\rm out}}(L_{yx}-L_{yy}R_{\rm in})$ | $\dfrac{\lambda_{\rm in}}{\lambda_{\rm out}}(L_{xx}\operatorname{adj}(R_{\rm in})+L_{xy})$ |
| Form 2 → form 1 | $\dfrac{\lambda_{\rm in}}{\lambda_{\rm out}}(L_{xx}\operatorname{adj}(R_{\rm in})+L_{xy})$ | $\dfrac{\lambda_{\rm in}}{\lambda_{\rm out}}(L_{yx}-L_{yy}R_{\rm in})$ |
| Form 2 → form 2 | $\dfrac{\lambda_{\rm in}}{\lambda_{\rm out}}(L_{yx}\operatorname{adj}(R_{\rm in})+L_{yy})$ | $\dfrac{\lambda_{\rm in}}{\lambda_{\rm out}}(L_{xx}-L_{xy}R_{\rm in})$ |

For example, the upper-left block for form 1 → form 1 gives $\lambda_{\rm in}(L_{xx}-L_{xy}R_{\rm in})=\lambda_{\rm out}\bar L_1$. Since $\det \bar L_1=1$, it gives the normalization in (P3). The lower-left block then gives $R_{\rm out}$. The other cases follow in the same way and agree with the propagation construction in Sec. III of Ref. [1].

Symplecticity also gives

$$
\det(L_{xx}-L_{xy}R_{\rm in})+\det(L_{yx}-L_{yy}R_{\rm in})=1/\lambda_{\rm in}^2>0.
\tag{P5}
$$

At least one of the two determinant choices is positive in exact arithmetic. Retain the current form while its blocks are well conditioned, and change forms before a required block becomes singular. Evaluate block ratios with linear solves.

For the unit-emittance eigenmode Twiss matrix,

$$
\mathcal Q_j=\begin{pmatrix}\beta_j&-\alpha_j\\-\alpha_j&\gamma_j\end{pmatrix},
$$

propagation is

$$
\mathcal Q_{1,{\rm out}}=\bar L_1\mathcal Q_{1,{\rm in}}\bar L_1^T,\qquad
\mathcal Q_{2,{\rm out}}=\bar L_2\mathcal Q_{2,{\rm in}}\bar L_2^T.
\tag{P6}
$$

The first subscript identifies the physical eigenmode; the endpoint is indicated separately. These equations require no periodicity of the section map.

## 6. Mais–Ripken functions from eigenvectors

### 6.1 Phase-independent extraction

For either normalized eigenmode, label its physical components directly:

$$
\mathbf u_j=(u_{j,x},u_{j,p_x},u_{j,y},u_{j,p_y})^T.
$$

For $a=x,y$, $p_a$ denotes the corresponding canonical momentum. Define

$$
\boxed{
\begin{aligned}
\beta_{ja}&=|u_{j,a}|^2,\\
\alpha_{ja}&=-\operatorname{Re}(u_{j,a}^*u_{j,p_a}),\\
\gamma_{ja}&=|u_{j,p_a}|^2,\\
\kappa_{ja}&=-\operatorname{Im}(u_{j,a}^*u_{j,p_a}).
\end{aligned}}
\tag{M1}
$$

These quantities are invariant under an arbitrary overall phase of the eigenvector. Symplectic normalization gives

$$
\kappa_{jx}+\kappa_{jy}=1.
\tag{M2}
$$

To obtain the cross-mode relations, partition the real symplectic normalizer into 2×2 blocks $U_{aj}$. Equation (M1) gives $\det U_{aj}=\kappa_{ja}$. The diagonal blocks of both $U_4^TS_4U_4=S_4$ and $U_4S_4U_4^T=S_4$, using $KS_2K^T=(\det K)S_2$, then give

$$
\kappa_{1x}=\kappa_{2y}=1-u,
\qquad \kappa_{1y}=\kappa_{2x}=u.
\tag{M3}
$$

Thus

$$
\boxed{u=-\operatorname{Im}(u_{1,y}^*u_{1,p_y})
=-\operatorname{Im}(u_{2,x}^*u_{2,p_x}).}
\tag{M4}
$$

Agreement between these two independent evaluations is a useful residual.

For each plane and eigenmode,

$$
\boxed{\beta_{ja}\gamma_{ja}-\alpha_{ja}^2=\kappa_{ja}^2.}
\tag{M5}
$$

The right-hand side is generally not one. Therefore do not use $(1+\alpha_{ja}^2)/\beta_{ja}$ for a projected eigenmode gamma function. Instead use (M1), which also works at zero position projection.

### 6.2 Relative phase factors and explicit eigenvectors

When the reference position components are nonzero, choose $u_{1,x}>0$ and $u_{2,y}>0$ real by multiplying the eigenvectors by $u_{1,x}^*/|u_{1,x}|$ and $u_{2,y}^*/|u_{2,y}|$, respectively. This adjustment requires no angle evaluation.

Store the relative phase through its cosine and sine:

$$
\boxed{\begin{aligned}
\cos\nu_1&=\frac{\operatorname{Re}(u_{1,y}u_{1,x}^*)}
{\sqrt{\beta_{1x}\beta_{1y}}},&
\sin\nu_1&=\frac{\operatorname{Im}(u_{1,y}u_{1,x}^*)}
{\sqrt{\beta_{1x}\beta_{1y}}},\\
\cos\nu_2&=\frac{\operatorname{Re}(u_{2,x}u_{2,y}^*)}
{\sqrt{\beta_{2x}\beta_{2y}}},&
\sin\nu_2&=\frac{\operatorname{Im}(u_{2,x}u_{2,y}^*)}
{\sqrt{\beta_{2x}\beta_{2y}}}.
\end{aligned}}
\tag{M6}
$$

The notation $\cos\nu_j,\sin\nu_j$ names these real factors; the angles $\nu_j$ need not be computed or stored. Each pair satisfies $\cos^2\nu_j+\sin^2\nu_j=1$ where its projections are nonzero.

Since

$$
u_{j,a}^*u_{j,p_a}=-\alpha_{ja}-i\kappa_{ja},
$$

the eigenvectors become

$$
\mathbf u_1=
\begin{pmatrix}
\sqrt{\beta_{1x}}\\
-\dfrac{\alpha_{1x}+i(1-u)}{\sqrt{\beta_{1x}}}\\
\sqrt{\beta_{1y}}(\cos\nu_1+i\sin\nu_1)\\
-\dfrac{\alpha_{1y}+iu}{\sqrt{\beta_{1y}}}(\cos\nu_1+i\sin\nu_1)
\end{pmatrix},
\quad
\mathbf u_2=
\begin{pmatrix}
\sqrt{\beta_{2x}}(\cos\nu_2+i\sin\nu_2)\\
-\dfrac{\alpha_{2x}+iu}{\sqrt{\beta_{2x}}}(\cos\nu_2+i\sin\nu_2)\\
\sqrt{\beta_{2y}}\\
-\dfrac{\alpha_{2y}+i(1-u)}{\sqrt{\beta_{2y}}}
\end{pmatrix}.
\tag{M7}
$$

Equation (M7) is the eigenvector parameterization in Eq. (4.12) of Ref. [2]. Using (E6) gives

$$
U_4=\begin{pmatrix}
\sqrt{\beta_{1x}}&0&\sqrt{\beta_{2x}}\cos\nu_2&-\sqrt{\beta_{2x}}\sin\nu_2\\
-\dfrac{\alpha_{1x}}{\sqrt{\beta_{1x}}}&\dfrac{1-u}{\sqrt{\beta_{1x}}}&
\dfrac{-\alpha_{2x}\cos\nu_2+u\sin\nu_2}{\sqrt{\beta_{2x}}}&
\dfrac{\alpha_{2x}\sin\nu_2+u\cos\nu_2}{\sqrt{\beta_{2x}}}\\
\sqrt{\beta_{1y}}\cos\nu_1&-\sqrt{\beta_{1y}}\sin\nu_1&\sqrt{\beta_{2y}}&0\\
\dfrac{-\alpha_{1y}\cos\nu_1+u\sin\nu_1}{\sqrt{\beta_{1y}}}&
\dfrac{\alpha_{1y}\sin\nu_1+u\cos\nu_1}{\sqrt{\beta_{1y}}}&
-\dfrac{\alpha_{2y}}{\sqrt{\beta_{2y}}}&\dfrac{1-u}{\sqrt{\beta_{2y}}}
\end{pmatrix}.
\tag{M8}
$$

Equation (M8) agrees with Eq. (4.13) of Ref. [2]. The scalar parameters are constrained by symplecticity; they cannot all be chosen independently. The two one-turn phases $\mu_j$ and the constrained generalized functions contain ten independent real parameters, matching the dimension of $\mathrm{Sp}(4,\mathbb R)$.

When a position component vanishes, the corresponding phase may be undefined and (M7) may contain removable or genuine coordinate singularities. Keep the eigenvector and (M1) as the authoritative result; do not evaluate a formula containing division by zero. This includes the exactly uncoupled limit, where the secondary projections vanish.

### 6.3 Interpretation and covariance

The parameter $u$ describes a signed partition of symplectic area. It can be negative. If mode labels are maintained through an exchange, it can also exceed one. The usual labeling in Ref. [2] additionally chooses $1-u\ge0$; that is a labeling convention rather than a bound on every continuously labeled representation.

Also, $u=0$ alone does not prove the absence of coupling. A nonzero rank-one $R$ has $\det R=0$ and can produce nonzero secondary projections while $u=0$. This limitation is discussed in Sec. 5 of Ref. [2].

For a matched ensemble with uncorrelated eigenmodes and rms eigenmode emittances $\epsilon_1,\epsilon_2$,

$$
\boxed{\Sigma=U_4\operatorname{diag}(\epsilon_1,\epsilon_1,
\epsilon_2,\epsilon_2)U_4^T
=\sum_{j=1}^2\epsilon_j\operatorname{Re}(\mathbf u_j\mathbf u_j^\dagger).}
\tag{M9}
$$

In particular,

$$
\sigma_x^2=\epsilon_1\beta_{1x}+\epsilon_2\beta_{2x},\qquad
\sigma_y^2=\epsilon_1\beta_{1y}+\epsilon_2\beta_{2y},
\tag{M10}
$$

$$
\Sigma_{xy}=
\epsilon_1\sqrt{\beta_{1x}\beta_{1y}}\cos\nu_1+
\epsilon_2\sqrt{\beta_{2x}\beta_{2y}}\cos\nu_2.
\tag{M11}
$$

For centered coordinates ordered as $(x,p_x,y,p_y)$, all entries of the covariance matrix are

$$
\boxed{\Sigma=
\begin{pmatrix}
\epsilon_1\beta_{1x}+\epsilon_2\beta_{2x}
&-\epsilon_1\alpha_{1x}-\epsilon_2\alpha_{2x}
&\Sigma_{xy}&\Sigma_{x p_y}\\
-\epsilon_1\alpha_{1x}-\epsilon_2\alpha_{2x}
&\epsilon_1\gamma_{1x}+\epsilon_2\gamma_{2x}
&\Sigma_{p_x y}&\Sigma_{p_x p_y}\\
\Sigma_{xy}&\Sigma_{p_x y}
&\epsilon_1\beta_{1y}+\epsilon_2\beta_{2y}
&-\epsilon_1\alpha_{1y}-\epsilon_2\alpha_{2y}\\
\Sigma_{x p_y}&\Sigma_{p_x p_y}
&-\epsilon_1\alpha_{1y}-\epsilon_2\alpha_{2y}
&\epsilon_1\gamma_{1y}+\epsilon_2\gamma_{2y}
\end{pmatrix}.}
\tag{M12}
$$

Here $\Sigma_{ab}=\langle ab\rangle$ and $\Sigma_{xy}$ is given in (M11). The projected gamma functions can be written as

$$
\begin{aligned}
\gamma_{1x}&=\frac{\alpha_{1x}^2+(1-u)^2}{\beta_{1x}},&
\gamma_{1y}&=\frac{\alpha_{1y}^2+u^2}{\beta_{1y}},\\
\gamma_{2x}&=\frac{\alpha_{2x}^2+u^2}{\beta_{2x}},&
\gamma_{2y}&=\frac{\alpha_{2y}^2+(1-u)^2}{\beta_{2y}}.
\end{aligned}
\tag{M13}
$$

The remaining cross-plane entries follow by substituting (M7) into (M9):

$$
\boxed{\begin{aligned}
\Sigma_{x p_y}
={}&\epsilon_1\sqrt{\frac{\beta_{1x}}{\beta_{1y}}}
(-\alpha_{1y}\cos\nu_1+u\sin\nu_1)\\
&-\epsilon_2\sqrt{\frac{\beta_{2x}}{\beta_{2y}}}
[\alpha_{2y}\cos\nu_2+(1-u)\sin\nu_2].
\end{aligned}}
\tag{M14}
$$

$$
\boxed{\begin{aligned}
\Sigma_{p_x y}
={}&-\epsilon_1\sqrt{\frac{\beta_{1y}}{\beta_{1x}}}
[\alpha_{1x}\cos\nu_1+(1-u)\sin\nu_1]\\
&+\epsilon_2\sqrt{\frac{\beta_{2y}}{\beta_{2x}}}
(-\alpha_{2x}\cos\nu_2+u\sin\nu_2).
\end{aligned}}
\tag{M15}
$$

$$
\boxed{\begin{aligned}
\Sigma_{p_x p_y}
={}&\frac{\epsilon_1}{\sqrt{\beta_{1x}\beta_{1y}}}
\left\{
[\alpha_{1x}\alpha_{1y}+u(1-u)]\cos\nu_1
+[(1-u)\alpha_{1y}-u\alpha_{1x}]\sin\nu_1
\right\}\\
&+\frac{\epsilon_2}{\sqrt{\beta_{2x}\beta_{2y}}}
\left\{
[\alpha_{2x}\alpha_{2y}+u(1-u)]\cos\nu_2
+[(1-u)\alpha_{2x}-u\alpha_{2y}]\sin\nu_2
\right\}.
\end{aligned}}
\tag{M16}
$$

Equations (M11)–(M16) specify the full symmetric matrix using the Mais–Ripken functions and the two rms eigenmode emittances. At zero position projection, expressions containing a beta denominator are unavailable; the vector formula (M9), with gamma functions from (M1), remains finite and defines the limiting covariance.

This is why a single Edwards–Teng beta is not generally the physical beam-size coefficient. The ensemble emittance convention in (M9) is rms; a boundary-particle amplitude $\sqrt{2J_j}$ must not be substituted for an rms emittance without the appropriate averaging.

## 7. Conversion between Edwards–Teng and Mais–Ripken

### 7.1 Matrix form of the conversion

Use the Twiss matrices $\mathcal Q_j$ from Section 5 and $\lambda^2=(1+\det R)^{-1}$. Each projected mode matrix has the form

$$
\begin{pmatrix}
\beta_{ja}&-\alpha_{ja}\\
-\alpha_{ja}&\gamma_{ja}
\end{pmatrix}.
$$

For any real 2×2 block $K$, its transformed entries are explicitly

$$
\begin{aligned}
(K\mathcal Q_jK^T)_{11}
&=\beta_jK_{11}^2-2\alpha_jK_{11}K_{12}+\gamma_jK_{12}^2,\\
-(K\mathcal Q_jK^T)_{12}
&=-\beta_jK_{11}K_{21}
+\alpha_j(K_{11}K_{22}+K_{12}K_{21})-\gamma_jK_{12}K_{22},\\
(K\mathcal Q_jK^T)_{22}
&=\beta_jK_{21}^2-2\alpha_jK_{21}K_{22}+\gamma_jK_{22}^2.
\end{aligned}
\tag{B1}
$$

Thus the tables below give all projected beta, alpha, and gamma functions without introducing separate auxiliary functions. In this section $\gamma_j=(1+\alpha_j^2)/\beta_j$ refers to the unit-area Edwards–Teng mode; the projected functions obey (M5).

### 7.2 Form 1

The normalizer is

$$
U_4=V_1\mathcal B
=\lambda\begin{pmatrix}
\mathcal B_1&\operatorname{adj}(R)\mathcal B_2\\
-R\mathcal B_1&\mathcal B_2
\end{pmatrix}.
\tag{B2}
$$

Its position entries already satisfy the phase convention of Section 6.2. Taking the determinants of the 2×2 blocks gives

$$
\boxed{u=\lambda^2\det R=\frac{\det R}{1+\det R},
\qquad1-u=\lambda^2.}
\tag{B3}
$$

The projected eigenmode matrices are:

| Projection | $\begin{pmatrix}\beta_{ja}&-\alpha_{ja}\\-\alpha_{ja}&\gamma_{ja}\end{pmatrix}$ |
|---|---|
| Eigenmode 1, x | $\lambda^2\mathcal Q_1$ |
| Eigenmode 1, y | $\lambda^2R\mathcal Q_1R^T$ |
| Eigenmode 2, x | $\lambda^2\operatorname{adj}(R)\mathcal Q_2\operatorname{adj}(R)^T$ |
| Eigenmode 2, y | $\lambda^2\mathcal Q_2$ |

Using the entries $R_{ij}$ of the coupling matrix, (M6) gives

$$
\boxed{\begin{aligned}
\cos\nu_1&=\frac{\alpha_1R_{12}-\beta_1R_{11}}
{\sqrt{(\alpha_1R_{12}-\beta_1R_{11})^2+R_{12}^2}},&
\sin\nu_1&=\frac{R_{12}}
{\sqrt{(\alpha_1R_{12}-\beta_1R_{11})^2+R_{12}^2}},\\
\cos\nu_2&=\frac{\alpha_2R_{12}+\beta_2R_{22}}
{\sqrt{(\alpha_2R_{12}+\beta_2R_{22})^2+R_{12}^2}},&
\sin\nu_2&=\frac{R_{12}}
{\sqrt{(\alpha_2R_{12}+\beta_2R_{22})^2+R_{12}^2}}.
\end{aligned}}
\tag{B4}
$$

These are normalized real pairs; no inverse trigonometric function is required.

The primary projections give the inverse Twiss relations

$$
\boxed{\beta_1=\frac{\beta_{1x}}{1-u},\qquad
\alpha_1=\frac{\alpha_{1x}}{1-u},\qquad
\beta_2=\frac{\beta_{2y}}{1-u},\qquad
\alpha_2=\frac{\alpha_{2y}}{1-u}.}
\tag{B5}
$$

These agree with Eq. (7.16) of Ref. [2]. The matrix form remains real for $-1<\det R<0$, where $u<0$.

### 7.3 Form 2

The corresponding normalizer before phase adjustment is

$$
V_2\mathcal B
=\lambda\begin{pmatrix}
\operatorname{adj}(R)\mathcal B_1&\mathcal B_2\\
\mathcal B_1&-R\mathcal B_2
\end{pmatrix}.
\tag{B6}
$$

Its block determinants give

$$
\boxed{u=\lambda^2=\frac1{1+\det R},
\qquad1-u=\lambda^2\det R.}
\tag{B7}
$$

The projected eigenmode matrices are:

| Projection | $\begin{pmatrix}\beta_{ja}&-\alpha_{ja}\\-\alpha_{ja}&\gamma_{ja}\end{pmatrix}$ |
|---|---|
| Eigenmode 1, x | $\lambda^2\operatorname{adj}(R)\mathcal Q_1\operatorname{adj}(R)^T$ |
| Eigenmode 1, y | $\lambda^2\mathcal Q_1$ |
| Eigenmode 2, x | $\lambda^2\mathcal Q_2$ |
| Eigenmode 2, y | $\lambda^2R\mathcal Q_2R^T$ |

Before the position components are made real and positive, the first eigenvector has

$$
u_{1,x}=\frac{\lambda}{\sqrt{\beta_1}}
(\beta_1R_{22}+\alpha_1R_{12}+iR_{12}),
\qquad u_{1,y}=\lambda\sqrt{\beta_1}.
$$

The relative phase factor $u_{1,y}u_{1,x}^*/|u_{1,y}u_{1,x}|$ therefore conjugates the complex factor in $u_{1,x}$. Applying the same reasoning to the second eigenvector gives

$$
\boxed{\begin{aligned}
\cos\nu_1&=\frac{\alpha_1R_{12}+\beta_1R_{22}}
{\sqrt{(\alpha_1R_{12}+\beta_1R_{22})^2+R_{12}^2}},&
\sin\nu_1&=-\frac{R_{12}}
{\sqrt{(\alpha_1R_{12}+\beta_1R_{22})^2+R_{12}^2}},\\
\cos\nu_2&=\frac{\alpha_2R_{12}-\beta_2R_{11}}
{\sqrt{(\alpha_2R_{12}-\beta_2R_{11})^2+R_{12}^2}},&
\sin\nu_2&=-\frac{R_{12}}
{\sqrt{(\alpha_2R_{12}-\beta_2R_{11})^2+R_{12}^2}}.
\end{aligned}}
\tag{B8}
$$

Rephasing the eigenvectors as in Section 6.2 puts (B6) into the form (M8) without changing their projected functions. If a denominator in (B4) or (B8) vanishes, the associated relative phase is undefined; retain the vector and covariance entries directly.

The inverse Twiss relations are

$$
\boxed{\beta_1=\frac{\beta_{1y}}u,\qquad
\alpha_1=\frac{\alpha_{1y}}u,\qquad
\beta_2=\frac{\beta_{2x}}u,\qquad
\alpha_2=\frac{\alpha_{2x}}u.}
\tag{B9}
$$

The form 2 requires $u>0$, whereas the form 1 requires $1-u>0$. At least one condition holds for every real $u$. For $\det R<0$ in the form 2, $u>1$; an exchange of the eigenmode labels restores the additional labeling convention $1-u\ge0$ used in Ref. [2].

### 7.4 Coupling matrix from the normalizer

Partition $U_4$ into physical-plane rows and eigenmode-pair columns:

$$
U_4=\begin{pmatrix}U_{x1}&U_{x2}\\U_{y1}&U_{y2}\end{pmatrix}.
$$

The within-eigenmode phase rotations cancel in block ratios. Therefore

$$
\boxed{\begin{array}{ll}
\text{form 1:}&R=-U_{y1}U_{x1}^{-1},\quad
\operatorname{adj}(R)=U_{x2}U_{y2}^{-1},\\[2mm]
\text{form 2:}&R=-U_{y2}U_{x2}^{-1},\quad
\operatorname{adj}(R)=U_{x1}U_{y1}^{-1}.
\end{array}}
\tag{B10}
$$

Choose a form with an admissible positive area weight and well-conditioned blocks, and evaluate the ratios with linear solves. The two expressions in each row provide an independent consistency check. Equations (B5) or (B9) then recover its Edwards–Teng Twiss functions from the Mais–Ripken functions.

### 7.5 Direct extraction and complete conversion routes

The projectors and covariances of Section 3.4 remove the need to choose
eigenvector phases before extracting Edwards–Teng parameters. With physical
coordinate-pair block subscripts, their exact relations are

$$
\boxed{
\begin{array}{c|c|c|c|c}
\text{form}&\lambda^2&R&\mathcal Q_1&\mathcal Q_2\\ \hline
1&1-u&-(P_1)_{(y,p_y),(x,p_x)}/(1-u)&(G_1)_{(x,p_x),(x,p_x)}/(1-u)&(G_2)_{(y,p_y),(y,p_y)}/(1-u)\\
2&u&-(P_2)_{(y,p_y),(x,p_x)}/u&(G_1)_{(y,p_y),(y,p_y)}/u&(G_2)_{(x,p_x),(x,p_x)}/u
\end{array}}
\tag{B11}
$$

For example, in form 1 the lower-left projector block is
$(P_1)_{(y,p_y),(x,p_x)}=-\lambda^2R$ and $(G_1)_{(x,p_x),(x,p_x)}=\lambda^2\mathcal Q_1$.
This proves the first row; exchanging the column pairs proves the second.
Each row requires its positive area weight and a numerically usable chart.

The extraction and conversion routes are therefore complete on their
respective nonsingular domains:

| Input | Conversion |
|---|---|
| 4D map | (E10)–(E14) give the eigenmodes; (M1), (M6) give Mais–Ripken; (B11) gives Edwards–Teng. Numerical eigenanalysis is an alternative. |
| Edwards–Teng | Construct $V\mathcal B$ with its stated form; recover vectors by (E6), then (M1), (M6). |
| Complete Mais–Ripken | Construct (M7) or (M8); extract Edwards–Teng by (B10), (B5), (B9). |
| Eigenmodes | Form $U_4$ and the modal covariances $G_j$; use (M1), (M6), (B10) or (B11), with $P_j=-\operatorname{Im}(\mathbf u_j\mathbf u_j^\dagger)S_4$. |

"Complete Mais–Ripken" includes the signed area partition and the relative
phase cosines **and sines**, not only projected beta/alpha functions.
At zero projections, retain the eigenvectors or Hermitian matrices instead
of claiming that undefined position phases encode the missing information.
Reconstructing the one-turn map from any parameterization additionally
requires the assigned phases $\mu_1,\mu_2$.
There is no globally unique phase convention or mode label supplied by the
matrix alone at degeneracy.

## 8. Crab and momentum dispersion

### 8.1 Canonical definitions

Define crab dispersion $\boldsymbol\zeta$ and momentum dispersion $\boldsymbol\eta$ as in Eqs. (2)–(8) of Ref. [3]:

$$
\begin{pmatrix}\mathbf r\\z\\p_z\end{pmatrix}
=\mathcal M
\begin{pmatrix}\overline{\mathbf r}\\\bar z\\\bar p_z\end{pmatrix},
\qquad
\boxed{\boldsymbol\zeta=
\left.\frac{\partial\mathbf r}{\partial\bar z}\right|_{\overline{\mathbf r},\bar p_z},
\qquad
\boldsymbol\eta=
\left.\frac{\partial\mathbf r}{\partial\bar p_z}\right|_{\overline{\mathbf r},\bar z}.}
\tag{D1}
$$

The barred coordinates are canonically decoupled. The derivatives hold the other barred coordinates fixed. The elementary dispersion transformations are

$$
\mathcal M_\eta=
\begin{pmatrix}
I_4&0&\boldsymbol\eta\\
\boldsymbol\eta^TS_4&1&0\\
0&0&1
\end{pmatrix},
\qquad
\mathcal M_\zeta=
\begin{pmatrix}
I_4&\boldsymbol\zeta&0\\
0&1&0\\
-\boldsymbol\zeta^TS_4&0&1
\end{pmatrix}.
\tag{D2}
$$

These are Eqs. (4) and (6) of Ref. [3], using $(S_4\mathbf a)^T=-\mathbf a^TS_4$. Apply $\mathcal M_\eta$ first, so that

$$
\boxed{\mathcal M=\mathcal M_\zeta\mathcal M_\eta
=\begin{pmatrix}
I_4+\boldsymbol\zeta\boldsymbol\eta^TS_4&\boldsymbol\zeta&\boldsymbol\eta\\
\boldsymbol\eta^TS_4&1&0\\
-\boldsymbol\zeta^TS_4&0&h
\end{pmatrix},\qquad
h=1-\boldsymbol\zeta^TS_4\boldsymbol\eta.}
\tag{D3}
$$

The transverse coordinates satisfy

$$
\mathbf r=(I_4+\boldsymbol\zeta\boldsymbol\eta^TS_4)\overline{\mathbf r}
+\boldsymbol\zeta\bar z+\boldsymbol\eta\bar p_z.
\tag{D4}
$$

Equation (D4) implements the derivative definitions exactly. The product order in (D3) fixes the decoupled coordinate basis; reversing it changes that basis and the dispersion coefficients. Both the derivatives and this ordered transformation are part of the convention.

### 8.2 Physical longitudinal graph

Partition the periodic map as

$$
M_6=\begin{pmatrix}M_{rr}&M_{r\ell}\\M_{\ell r}&M_{\ell\ell}\end{pmatrix},
\qquad
M_{rr}:4\times4,\quad M_{r\ell}:4\times2,\quad
M_{\ell r}:2\times4,\quad M_{\ell\ell}:2\times2.
\tag{D5}
$$

The block labels $r,\ell$ refer to the physical coordinate groups
$\mathbf r=(x,p_x,y,p_y)^T$ and $\boldsymbol\ell=(z,p_z)^T$.
They label rows first and columns second; $M_{rr}$ is not the decoupled
betatron map.

Identify the invariant plane continuously connected to the synchrotron mode. On this plane $\overline{\mathbf r}=0$, and (D3) becomes

$$
\mathbf r=\boldsymbol\zeta\bar z+\boldsymbol\eta\bar p_z,
\qquad z=\bar z,\qquad p_z=h\bar p_z.
\tag{D6}
$$

When $h\ne0$, the plane is a graph over the physical longitudinal coordinates:

$$
\boxed{\mathbf r=\mathscr D\boldsymbol\ell,\qquad
\mathscr D=\left[\boldsymbol\zeta\ \frac{\boldsymbol\eta}{h}\right].}
\tag{D7}
$$

Conversely, writing $\mathscr D_{:j}$ for column $j$,

$$
\boxed{\boldsymbol\zeta=\mathscr D_{:1},\qquad
h=\frac1{1+\mathscr D_{:1}^TS_4\mathscr D_{:2}},\qquad
\boldsymbol\eta=h\mathscr D_{:2}.}
\tag{D8}
$$

This follows by substituting $\boldsymbol\eta=h\mathscr D_{:2}$ into the definition of $h$ in (D3). The momentum derivative on the physical plane is $\partial\mathbf r/\partial p_z=\boldsymbol\eta/h$. It equals $\boldsymbol\eta$ when $\boldsymbol\zeta^TS_4\boldsymbol\eta=0$, including the limits of pure momentum dispersion and pure crab dispersion. Away from this plane, the transverse companion term in (D3) also contributes to $z$.

### 8.3 Extraction from the longitudinal eigenvector

Let $\mathbf u_s$ be the longitudinal eigenvector of $M_6$, selected and normalized by the 6D counterpart of Section 3:

$$
\mathbf u_s^\dagger S_6\mathbf u_s=-2i,\qquad
U_s=[\operatorname{Re}\mathbf u_s,-\operatorname{Im}\mathbf u_s]
=\begin{pmatrix}U_{rs}\\U_{\ell s}\end{pmatrix},
\quad U_{rs}:4\times2,\quad U_{\ell s}:2\times2.
\tag{D9}
$$

The pair $U_s$ is 6×2; its row blocks are the physical transverse and
longitudinal projections, not new normalizers. Every point in its span obeys
$\mathbf r=U_{rs}U_{\ell s}^{-1}\boldsymbol\ell$ when
$U_{\ell s}$ is invertible. Hence

$$
\boxed{\mathscr D=U_{rs}U_{\ell s}^{-1}.}
\tag{D10}
$$

This graph is invariant under any invertible real change of basis within the plane, including eigenvector amplitude and phase changes. Evaluate (D10) with a linear solve, check the conditioning of $U_{\ell s}$ in scaled coordinates, and apply (D8).

The same coefficients can be extracted directly from the normalized complex eigenvector. From (D7) and (D3),

$$
\mathscr D^TS_4\mathscr D=\frac{1-h}{h}S_2,\qquad
U_s^TS_6U_s
=U_{\ell s}^T(S_2+\mathscr D^TS_4\mathscr D)U_{\ell s}
=\frac{\det U_{\ell s}}{h}S_2=S_2.
\tag{D11}
$$

Thus $h=\det U_{\ell s}$. Expanding the 2×2 determinants in (D10) gives

$$
\boxed{\begin{aligned}
h&=-\operatorname{Im}(u_{s,z}^*u_{s,p_z}),\\
\zeta_a&=-\frac{\operatorname{Im}(u_{s,a}^*u_{s,p_z})}{h},\\
\eta_a&=-\operatorname{Im}(u_{s,z}^*u_{s,a}),
\qquad a=x,p_x,y,p_y.
\end{aligned}}
\tag{D12}
$$

These expressions use the full 6D normalization in (D9) and are independent of the eigenvector's overall phase. In contrast, (D10) is independent of amplitude normalization as well. A single complex ratio such as $u_{s,a}/u_{s,p_z}$ does not separate the two real dispersion vectors.

At $h=0$, a transformation already specified by finite coefficients in (D3)
remains canonical, but the longitudinal projection is singular. Not every
singularly projected invariant plane is representable by finite coefficients
in this ordered form: its longitudinal columns always include a vector with
physical $z=1$, so a plane contained in $z=0$ cannot be represented.
The division by $h$ in (D12) cannot determine a unique continuation of all
coefficients there. Retain the full invariant basis; a different computational
chart can continue that plane, but does not make dispersion over the original
physical $(z,p_z)$ coordinates available. See Section 8.8.

### 8.4 Invariance equation and weak-coupling approximation

Mapping a point on the graph gives

$$
\mathbf r'=(M_{rr}\mathscr D+M_{r\ell})\boldsymbol\ell,
\qquad
\boldsymbol\ell'=(M_{\ell r}\mathscr D+M_{\ell\ell})\boldsymbol\ell.
$$

Therefore its exact invariance equation is

$$
\boxed{M_{rr}\mathscr D+M_{r\ell}
=\mathscr D(M_{\ell r}\mathscr D+M_{\ell\ell}).}
\tag{D14}
$$

The longitudinal motion on the physical graph is governed by $M_{\ell r}\mathscr D+M_{\ell\ell}$. Eigenplane extraction solves (D14) directly. Other invariant planes can yield other solutions, so continuation from the physical longitudinal mode is necessary.

Neglecting the quadratic term $\mathscr D M_{\ell r}\mathscr D$ gives the weak-coupling approximation

$$
\boxed{M_{rr}\mathscr D-\mathscr D M_{\ell\ell}=-M_{r\ell}.}
\tag{D15}
$$

This Sylvester equation has a unique solution when the spectra of $M_{rr}$ and $M_{\ell\ell}$ are disjoint. In column-major vectorization,

$$
[I_2\otimes M_{rr}-M_{\ell\ell}^T\otimes I_4]
\operatorname{vec}(\mathscr D)=-\operatorname{vec}(M_{r\ell}).
\tag{D16}
$$

Recover $\boldsymbol\zeta,\boldsymbol\eta$ with (D8) and check the full residual in (D14), especially near a mode resonance. Applying $(I_4-M_{rr})^{-1}$ separately to the two forcing columns is generally invalid when longitudinal motion and feedback are present.

### 8.5 Exact algebraic solution

An exact expression for $\mathscr D$ can be obtained without solving the nonlinear equation iteratively. It requires the trace $\tau_s=2\cos\mu_s$ of the selected longitudinal eigenmode.

For a real symplectic 6×6 map, the characteristic polynomial factors into reciprocal pairs:

$$
\det(\rho I_6-M_6)
=\prod_{j=1,2,s}(\rho^2-\tau_j\rho+1).
$$

Taking traces of the first three powers gives

$$
\begin{aligned}
\operatorname{tr}M_6&=\tau_1+\tau_2+\tau_s,\\
\operatorname{tr}(M_6^2)&=\tau_1^2+\tau_2^2+\tau_s^2-6,\\
\operatorname{tr}(M_6^3)&=\tau_1^3+\tau_2^3+\tau_s^3-3\operatorname{tr}M_6.
\end{aligned}
$$

The elementary symmetric polynomials of the three traces therefore give the cubic

$$
\boxed{\begin{aligned}
0={}&\tau^3-(\operatorname{tr}M_6)\tau^2\\
&+\left[\frac{(\operatorname{tr}M_6)^2-\operatorname{tr}(M_6^2)}2-3\right]\tau\\
&-\frac{(\operatorname{tr}M_6)^3
-3(\operatorname{tr}M_6)\operatorname{tr}(M_6^2)
+2\operatorname{tr}(M_6^3)}6
+2\operatorname{tr}M_6.
\end{aligned}}
\tag{D17}
$$

Equation (D17) is the trace-invariant form of Parzen's tune cubic [9],
Eqs. (22)–(25). His matrix $C$ is $(M_6+M_6^{-1})/2$ and his root
$\Lambda$ is $\tau/2$; substituting $\Lambda=\tau/2$ in his monic cubic
and multiplying by eight gives (D17). Glukhov's recurrent matrix [10],
Secs. III–IV, is $M_6+M_6^{-1}$ itself, with roots $\tau_j$.
These source names are translations, not additional working symbols.

In the stable nondegenerate domain, the three roots are distinct and lie in
$(-2,2)$. Real roots alone do not establish stability: their magnitudes must
also be checked, and repeated roots require a separate semisimplicity
analysis. The cubic does not distinguish $\mu_j$ from $-\mu_j$; retain the
symplectic orientation test of Section 3 to select the phase branch.
Select $\tau_s$ by continuation from the synchrotron eigenmode.
The closed cubic formulas in [9,10] are useful analytic references; a
numerical root solver still requires no 6D eigenvectors. None of these
polynomial forms removes near-resonance conditioning.

The polynomial $M_6^2-\tau_sM_6+I_6$ annihilates the longitudinal plane, because each of its two eigenvalues satisfies $\rho^2-\tau_s\rho+1=0$. Thus

$$
\boxed{(M_6^2-\tau_sM_6+I_6)
\begin{pmatrix}\mathscr D\\I_2\end{pmatrix}=0.}
\tag{D18}
$$

The top four rows of (D18) are linear in $\mathscr D$:

$$
(M_{rr}^2+M_{r\ell}M_{\ell r}-\tau_sM_{rr}+I_4)\mathscr D
=-(M_{rr}M_{r\ell}+M_{r\ell}M_{\ell\ell}-\tau_sM_{r\ell}).
$$

Consequently,

$$
\boxed{\mathscr D=
-(M_{rr}^2+M_{r\ell}M_{\ell r}-\tau_sM_{rr}+I_4)^{-1}
(M_{rr}M_{r\ell}+M_{r\ell}M_{\ell\ell}-\tau_sM_{r\ell}).}
\tag{D19}
$$

Equation (D19), together with the selected root of (D17), is a closed algebraic solution of (D14) wherever its 4×4 coefficient matrix is invertible. Compute it with a linear solve, then convert to $\boldsymbol\zeta,\boldsymbol\eta$ using (D8).

To see why the top four rows suffice, note that the polynomial in (D18) has rank four when the longitudinal eigenvalue pair is distinct from the two betatron pairs. If its upper-left 4×4 block is invertible, those four rows span its row space; the bottom rows then vanish as well. Its kernel is precisely the selected longitudinal plane, so (D14) follows.

This expression does not eliminate branch selection. Choosing a different cubic root selects a different invariant plane. Check the full invariance residual and the restricted longitudinal trace,

$$
\operatorname{tr}(M_{\ell r}\mathscr D+M_{\ell\ell})=\tau_s,
$$

as well as the longitudinal projection conditioning. Near coincident eigenmode traces or a singular longitudinal projection, the cubic roots or the linear solve can be ill conditioned; retaining the invariant basis is then preferable.

#### Full 6D invariant planes from the same roots

The same roots also extend the projector construction (E11) to all three
modes. This gives a compact spectral-projector interpretation of the real
two-column eigenvector blocks constructed in Glukhov [10], Secs. V–VII:

$$
\boxed{P_j=
\prod_{\substack{k\in\{1,2,s\}\\k\ne j}}
\frac{M_6+M_6^{-1}-\tau_k I_6}{\tau_j-\tau_k},
\qquad j=1,2,s.}
\tag{D26}
$$

On mode $j$ each factor is the identity, whereas on either other mode one
factor vanishes. Thus $P_j^2=P_j$, $P_jP_k=0$ for $j\ne k$,
$\sum_jP_j=I_6$, and $P_j^TS_6=S_6P_j$.
Equations (E12)–(E14), with $M_6,S_6,I_6$ replacing their 4D counterparts,
then recover $G_j$, the oriented complex vector, and $U_j$.
The reconstruction sum now includes all three modes, and the pivot may
be any of the six physical coordinates.
This constructs the complete normalizer without singling out a physical
longitudinal projection. The polynomial projector is not an orthogonal
projector in the Euclidean metric, and its columns are not automatically
a canonical normalizing basis.

For dispersion, partition $P_s$ into the same physical $r,\ell$ row and
column groups as (D5). Since $P_s=-U_sS_2U_s^TS_6$, the 2×2 identity
$U_{\ell s}S_2U_{\ell s}^T=(\det U_{\ell s})S_2$ gives

$$
\boxed{(P_s)_{\ell\ell}=hI_2,\qquad
h=\tfrac12\operatorname{tr}(P_s)_{\ell\ell},\qquad
\mathscr D=\frac{(P_s)_{r\ell}}{h}\quad(h\ne0).}
\tag{D27}
$$

This is another closed algebraic extraction of the same graph, derived
here by connecting the full-mode projector with (D10)–(D11).
Use (D8) for canonical dispersion. Compare against (D19) and normalized
eigenvectors on the same branch. The full projector can remain finite when
$h=0$, although (D27) cannot provide the physical graph there. Conversely,
coincident $\tau_j$ invalidate (D26) itself; track the combined invariant
subspace instead of dividing by a vanishing mode separation.

### 8.6 Iteration initialized by the Sylvester approximation

The algebraic formulas provide independent direct solutions. Iteration is also
useful when a weak-coupling solution or a nearby optics solution is available.
The Riccati equation and the two iterations below are the invariant-subspace
equation and simple/Newton iterations of Dieci–Friedman [11],
preprint Eqs. (12)–(14), in our 4+2 graph convention. Their subspace is
written over the first coordinate block, whereas ours is over the second;
the exchanged block order explains the different positions of the coefficients.

**Fixed-point iteration.** Initialize $\mathscr D^{(0)}$ by solving (D15). Reinsert the quadratic term from the previous iterate:

$$
\boxed{M_{rr}\mathscr D^{(n+1)}
-\mathscr D^{(n+1)}M_{\ell\ell}
=-M_{r\ell}+\mathscr D^{(n)}M_{\ell r}\mathscr D^{(n)}.}
\tag{D20}
$$

Each step solves a Sylvester equation with the same left-hand operator. Its Schur decompositions can therefore be reused [4]. A fixed point satisfies (D14) exactly.

Convergence is conditional. For example, using the Frobenius norm for matrix errors, a sufficient local contraction condition is that $2\|M_{\ell r}\|_2\|\mathscr D_\star\|_2$ be smaller than the smallest singular value of $I_2\otimes M_{rr}-M_{\ell\ell}^T\otimes I_4$, where $\mathscr D_\star$ is the target solution. This follows by expanding the difference of the two quadratic terms. Weak coupling and well-separated block spectra favor convergence; a stable full map alone does not guarantee it.

**Newton iteration.** Linearize the quadratic term around $\mathscr D^{(n)}$:

$$
\begin{aligned}
\mathscr D^{(n+1)}M_{\ell r}\mathscr D^{(n+1)}
\simeq{}&
\mathscr D^{(n)}M_{\ell r}\mathscr D^{(n+1)}
+\mathscr D^{(n+1)}M_{\ell r}\mathscr D^{(n)}\\
&-\mathscr D^{(n)}M_{\ell r}\mathscr D^{(n)}.
\end{aligned}
$$

Substitution into (D14) yields a Sylvester equation directly for the next iterate:

$$
\boxed{\begin{aligned}
(M_{rr}-\mathscr D^{(n)}M_{\ell r})\mathscr D^{(n+1)}
-\mathscr D^{(n+1)}(M_{\ell\ell}+M_{\ell r}\mathscr D^{(n)})
=-M_{r\ell}-\mathscr D^{(n)}M_{\ell r}\mathscr D^{(n)}.
\end{aligned}}
\tag{D21}
$$

The sign of the quadratic term on the right differs from (D20). The linearization moves both first-order contributions to the left. In exact arithmetic, a full Newton step leaves the residual

$$
\boxed{\begin{aligned}
&M_{rr}\mathscr D^{(n+1)}+M_{r\ell}
-\mathscr D^{(n+1)}(M_{\ell r}\mathscr D^{(n+1)}+M_{\ell\ell})\\
&\qquad=-(\mathscr D^{(n+1)}-\mathscr D^{(n)})
M_{\ell r}(\mathscr D^{(n+1)}-\mathscr D^{(n)}).
\end{aligned}}
\tag{D22}
$$

The remaining term is quadratic in the update. Near the solution, Newton convergence is quadratic when its Sylvester operator is nonsingular. At the solution, $M_{rr}-\mathscr D_\star M_{\ell r}$ has the betatron spectrum and $M_{\ell\ell}+M_{\ell r}\mathscr D_\star$ has the longitudinal spectrum, so separation of the physical eigenmodes supplies this local condition.

Use (D15), a converged fixed-point result, or a transported neighboring solution as the initial value. If a Newton trial increases the full scaled invariance residual, shorten the update by repeated halving. A singular or poorly conditioned Sylvester operator calls for a full invariant-basis
calculation, an algebraic solve only if its own coefficient matrix is usable,
or continuation in lattice parameters. No graph solver removes a singularity
of the selected physical projection itself.

Stop using the full residual in (I1), and verify the selected longitudinal trace or eigenvalue pair. A small update alone is insufficient. Both iterations can converge to a different invariant plane when started far from the intended branch; continuation and the eigenmode checks remain part of the solution.

### 8.7 Ordinary coasting dispersion

For a coasting beam, assume the specific block structure

$$
M_6=\begin{pmatrix}
M_{rr}&0&M_{r p_z}\\
M_{z r}&1&(M_6)_{56}\\
0&0&1
\end{pmatrix}.
\tag{D23}
$$

Here $M_{r p_z}$ is the 4×1 transverse momentum-response column and
$M_{z r}$ the 1×4 path-length-response row; $(M_6)_{56}$ is a scalar.
The momentum $p_z$ is conserved and the transverse map has no $z$ dependence. The dispersion is

$$
\boxed{\boldsymbol\zeta=0,\quad h=1,\quad
(I_4-M_{rr})\boldsymbol\eta=M_{r p_z}.}
\tag{D24}
$$

A unique solution requires $I_4-M_{rr}$ to be invertible. The decoupled longitudinal map is the shear

$$
\bar M_s=\begin{pmatrix}1&(M_6)_{56}+M_{z r}\boldsymbol\eta\\0&1\end{pmatrix}.
\tag{D25}
$$

Its unit eigenvalue can be defective, so an elliptic eigenvector-pair extraction is inappropriate. Implement this block structure as a separate branch. Switching off the RF does not by itself imply (D23) if crab kicks or other elements retain longitudinal–transverse coupling.

### 8.8 Continuation across lattice settings

Transport through a fixed lattice, Section 10.2, and continuation as a
lattice setting changes are different problems. Let $t$ denote a real scan
parameter at a fixed observation point, not the longitudinal coordinate.
Dieci–Friedman [11], Theorem 1 and Sec. 2, provide the relevant numerical
framework: separated spectral clusters admit smooth invariant-subspace
bases, with a tangent predictor, Riccati corrector, and adaptive scan steps.
Their orthogonal block-triangularization is not a canonical decoupling;
the symplectic normalization and factorization in this note remain necessary.

In a regular physical graph chart, differentiate (D14) with respect to $t$.
Dots below denote this derivative, and all undotted quantities are evaluated
at the converged old setting:

$$
\boxed{\begin{aligned}
&(M_{rr}-\mathscr D M_{\ell r})\dot{\mathscr D}
-\dot{\mathscr D}(M_{\ell\ell}+M_{\ell r}\mathscr D)\\
&\quad=-\dot M_{rr}\mathscr D-\dot M_{r\ell}
+\mathscr D\dot M_{\ell r}\mathscr D+\mathscr D\dot M_{\ell\ell}.
\end{aligned}}
\tag{D28}
$$

The left side is exactly the Newton Sylvester operator from (D21).
It determines the physical dispersion-graph sensitivity, not a new coupling
parameterization. For a scan step $\Delta t$, initialize the corrector with

$$
\boxed{\mathscr D^{(0)}(t+\Delta t)
=\mathscr D(t)+\Delta t\,\dot{\mathscr D}(t).}
\tag{D29}
$$

For a twice differentiable map on a regular, spectrally separated branch,
the initial graph error is $O((\Delta t)^2)$, rather than the generally
$O(\Delta t)$ error of reusing $\mathscr D(t)$ unchanged.
If analytic map derivatives are unavailable, replace $\dot M_6$ on the
right of (D28) by $[M_6(t+\Delta t)-M_6(t)]/\Delta t$; this gives the
same second-order initial-error estimate. This is our physical-coordinate
specialization of the finite-difference Euler predictor in [11], Eq. (16);
it is not a second-order accurate final optics solution without correction.

Correct at the new setting with (D21). Accept only after checking (I1),
the selected eigenvalue pair, and basis continuity. Reduce $\Delta t$ on
failed convergence, poor spectral separation, or an ambiguous assignment;
record rejected steps. A small update is not a substitute for an invariance
residual, and the paper's numerical step-size constants are not physical
tolerances for Octopus.

Two failures must remain distinct:

- If the physical longitudinal projection becomes singular, retain the
  full mode pair and continue it in a local basis centered on the previous
  subspace. Dieci–Friedman's orthogonal-frame construction, preprint
  Eqs. (7)–(10), keeps a local graph small; its basis update uses inverse
  square roots that the paper evaluates through an SVD. Such an auxiliary
  orthogonal basis is not $U_6$: recover canonical normalization before
  using the full-mode optics and covariance in (K10)–(K12). Use (K9) only
  where its ordered chart exists, and report the original physical graph
  as unavailable.
- If the longitudinal and betatron spectra cease to be separated, the
  Sylvester operator can be singular even in a good coordinate chart.
  For nonnormal maps, conditioning is controlled by the Sylvester operator,
  not only by the smallest eigenvalue distance. A larger separated
  invariant cluster may remain continuable, but its individual mode
  labels and dispersion are no longer uniquely resolved.

## 9. Canonical separation of betatron and longitudinal motion

### 9.1 Canonical transformation and inverse

Each factor of (D2) is symplectic, so

$$
\boxed{\mathcal M^TS_6\mathcal M=S_6}
\tag{K1}
$$

for all real $\boldsymbol\zeta,\boldsymbol\eta$. In particular, the transformation itself imposes no square-root condition $h>0$. The inverse follows by reversing and inverting the two elementary factors:

$$
\boxed{\mathcal M^{-1}=
\begin{pmatrix}
I_4-\boldsymbol\eta\boldsymbol\zeta^TS_4&-\boldsymbol\zeta&-\boldsymbol\eta\\
-\boldsymbol\eta^TS_4&h&0\\
\boldsymbol\zeta^TS_4&0&1
\end{pmatrix}.}
\tag{K2}
$$

The decoupled coordinates are therefore

$$
\boxed{\begin{aligned}
\overline{\mathbf r}
&=(I_4-\boldsymbol\eta\boldsymbol\zeta^TS_4)\mathbf r
-\boldsymbol\zeta z-\boldsymbol\eta p_z,\\
\bar z&=hz-\boldsymbol\eta^TS_4\mathbf r,\\
\bar p_z&=p_z+\boldsymbol\zeta^TS_4\mathbf r.
\end{aligned}}
\tag{K3}
$$

These equations make the held-fixed coordinates in the derivative definition explicit. They also show why subtracting two transverse offsets alone does not provide a complete canonical transformation.

### 9.2 Block diagonalization and the transverse map

If the columns corresponding to $(\bar z,\bar p_z)$ span the identified longitudinal invariant plane, the transverse columns span its symplectic complement. That complement is also invariant because $M_6$ is symplectic. Thus

$$
\boxed{\bar M_6=\mathcal M^{-1}M_6\mathcal M
=\begin{pmatrix}\bar M_\beta&0\\0&\bar M_s\end{pmatrix}.}
\tag{K4}
$$

This is the decoupling requirement in Eqs. (11)–(12) of Ref. [3]. Both blocks preserve their standard symplectic forms:

$$
\bar M_\beta^TS_4\bar M_\beta=S_4,
\qquad \bar M_s^TS_2\bar M_s=S_2.
\tag{K5}
$$

Obtain the blocks directly from (K4) and check the off-diagonal residuals. When $h\ne0$, (K3) and (D7) also give

$$
\overline{\mathbf r}
=(I_4-\boldsymbol\eta\boldsymbol\zeta^TS_4)
(\mathbf r-\mathscr D\boldsymbol\ell).
\tag{K6}
$$

The invariant-plane equation implies

$$
(\mathbf r-\mathscr D\boldsymbol\ell)'
=(M_{rr}-\mathscr D M_{\ell r})
(\mathbf r-\mathscr D\boldsymbol\ell).
$$

Since $(I_4-\boldsymbol\eta\boldsymbol\zeta^TS_4)^{-1}
=I_4+\boldsymbol\eta\boldsymbol\zeta^TS_4/h$, the separated maps are

$$
\boxed{\begin{aligned}
\bar M_\beta
&=(I_4-\boldsymbol\eta\boldsymbol\zeta^TS_4)
(M_{rr}-\mathscr D M_{\ell r})
\left(I_4+\frac{\boldsymbol\eta\boldsymbol\zeta^TS_4}{h}\right),\\
\bar M_s
&=\operatorname{diag}(1,1/h)
(M_{\ell r}\mathscr D+M_{\ell\ell})\operatorname{diag}(1,h).
\end{aligned}}
\tag{K7}
$$

Apply Sections 3–7 to $\bar M_\beta$. The raw physical block $M_{rr}$ is generally not a symplectic transverse map, because

$$
M_{rr}^TS_4M_{rr}+M_{\ell r}^TS_2M_{\ell r}=S_4.
\tag{K8}
$$

The canonical factors in (K7) are also needed for $M_{rr}-\mathscr D M_{\ell r}$ to preserve the standard $S_4$ form.

### 9.3 Full normalizer and physical projected optics

Let $\bar U_\beta$ normalize $\bar M_\beta$ and $\bar U_s$ normalize the elliptic $\bar M_s$. The full normalizer is

$$
\boxed{U_6=\mathcal M\operatorname{diag}(\bar U_\beta,\bar U_s).}
\tag{K9}
$$

The Twiss functions extracted from $\bar M_\beta$ describe the decoupled canonical coordinates $\overline{\mathbf r}$. To obtain the physical $x,y$ modal projection functions under substantial 6D coupling, use the physical components of the three complex vectors represented by $U_6$ in (M1).

The single-$u$ identities of a complete 4D symplectic basis cannot be applied to only two truncated physical transverse projections of a fully coupled 6D basis. The third mode contributes to completeness. For a matched ensemble with uncorrelated modes and specified rms mode emittances,

$$
\Sigma_6=U_6\operatorname{diag}(\epsilon_1,\epsilon_1,
\epsilon_2,\epsilon_2,\epsilon_s,\epsilon_s)U_6^T.
\tag{K10}
$$

The symmetric three-mode view in Glukhov [10], Secs. VI–VII and X–XI,
connects directly to these physical projections. Extend (M1) to
$j=1,2,s$ and $a=x,y,z$, using the full vectors:

$$
\boxed{\begin{aligned}
G_j&=\operatorname{Re}(\mathbf u_j\mathbf u_j^\dagger)=U_jU_j^T,
&\Sigma_6&=\sum_{j=1,2,s}\epsilon_jG_j,\\
\kappa_{ja}&=-\operatorname{Im}(u_{j,a}^*u_{j,p_a}),
&\beta_{ja}\gamma_{ja}-\alpha_{ja}^2&=\kappa_{ja}^2,\\
\sum_{a=x,y,z}\kappa_{ja}&=1,
&\sum_{j=1,2,s}\kappa_{ja}&=1.
\end{aligned}}
\tag{K12}
$$

The first area sum is the normalization of a mode; the second follows from
completeness of $U_6$. These signed areas are not probabilities. The 3×3
array has four independent entries under its row/column sums, rather than
the single partition $u$ of a complete 4D basis. In particular
$\kappa_{sz}=h$. In Glukhov's notation the physical-plane index precedes the
mode index, so his $u_{aj}$ is our $\kappa_{ja}$; his large $W_j$ matrices
assemble column pairs from different projectors and are not our canonical
$U_6$.

A direct check of the Twiss convention is

$$
\boxed{(M_6P_j)_{(a,p_a),(a,p_a)}
=\kappa_{ja}\cos\mu_j I_2+
\sin\mu_j
\begin{pmatrix}
\alpha_{ja}&\beta_{ja}\\
-\gamma_{ja}&-\alpha_{ja}
\end{pmatrix}.}
\tag{K13}
$$

It follows from $M_6P_j=\cos\mu_j P_j+\sin\mu_jG_jS_6$ and
$(P_j)_{(a,p_a),(a,p_a)}=\kappa_{ja}I_2$. With our oriented normalization,
$\beta_{ja}=|u_{j,a}|^2\ge0$ for every physical projection, even when
$\kappa_{ja}<0$; do not replace a signed area by its absolute value or
independently choose a phase sign for each projection.

Projected scalar Twiss functions alone do not retain relative projection
phases. For example, conjugating $M_6$ by a physical coordinate-pair sign
flip $\operatorname{diag}(-I_2,I_2,I_2)$ leaves these scalars and tunes
unchanged while changing transverse cross-block signs. This is the discrete
ambiguity discussed in [10], Sec. VIII. Retaining $U_6$, or the full
$G_j+iP_jS_6=\mathbf u_j\mathbf u_j^\dagger$ for each resolved mode,
retains that information. A common phase rotation within one eigenmode is
a different freedom: it changes neither $P_j$ nor $G_j$.

Physical bunch length follows from $\sigma_z^2=\sum_j\epsilon_j(G_j)_{zz}$.
In the ordered chart, $z=\bar z+\boldsymbol\eta^TS_4\overline{\mathbf r}$
also gives a useful direct result for each betatron mode. Let $\bar G_j$
be its 4×4 unit-emittance covariance in the decoupled transverse coordinates:

$$
\boxed{(G_j)_{zz}
=\boldsymbol\eta^TS_4\bar G_jS_4^T\boldsymbol\eta,\qquad j=1,2.}
\tag{K14}
$$

This follows by applying the physical $z$ row of (D3) to that mode.
It remains exact when $\boldsymbol\zeta\ne0$, with canonical
$\boldsymbol\eta$ and barred optics. The full-covariance formula in (K12)
does not require the ordered dispersion chart to exist.

In the ordinary dispersion limit $\boldsymbol\zeta=0$, (D3) reduces to

$$
\mathbf r=\overline{\mathbf r}+\boldsymbol\eta\bar p_z,
\qquad z=\bar z+\boldsymbol\eta^TS_4\overline{\mathbf r},
\qquad p_z=\bar p_z,
\tag{K11}
$$

including the required longitudinal companion term and its convention-dependent sign.

### 9.4 Ohmi–Hirata–Oide factorization

Ohmi, Hirata, and Oide [5], Sec. III A–B, construct the full complex
eigenbasis first, then factor the normalization into transverse–longitudinal
separation, transverse Edwards–Teng separation, modal Twiss normalization,
and phase choice. Their conservative factorization is exact on its stated
domain; the paper's radiation approximations do not make it a weak-coupling
expansion.

We express the transverse–longitudinal factor using the same
$\boldsymbol\zeta,\boldsymbol\eta,h$ as (D3), without introducing new
dispersion vectors. Write $\mathcal M_{\rm O}$ for Ohmi's 6×6 canonical
transformation **from decoupled to physical coordinates**:

$$
\mathbf X=\mathcal M_{\rm O}\overline{\mathbf X}_{\rm O},
\qquad
\mathcal M_{\rm O}^{-1}M_6\mathcal M_{\rm O}
=\operatorname{diag}(\bar M_{\beta,{\rm O}},\bar M_{s,{\rm O}}).
\tag{O1}
$$

The subscript $\mathrm O$ distinguishes Ohmi's choice of decoupled
coordinates from our ordered choice. The transformation itself is, for $h>0$,

$$
\boxed{\mathcal M_{\rm O}=
\begin{pmatrix}
I_4+\dfrac{(\boldsymbol\zeta\boldsymbol\eta^T-
\boldsymbol\eta\boldsymbol\zeta^T)S_4}{1+\sqrt h}
&\sqrt h\,\boldsymbol\zeta&\boldsymbol\eta/\sqrt h\\[2mm]
\boldsymbol\eta^TS_4/\sqrt h&\sqrt h&0\\
-\sqrt h\,\boldsymbol\zeta^TS_4&0&\sqrt h
\end{pmatrix}.}
\tag{O2}
$$

Its inverse has the same diagonal blocks and the opposite
transverse–longitudinal off-diagonal blocks:

$$
\boxed{\mathcal M_{\rm O}^{-1}=
\begin{pmatrix}
I_4+\dfrac{(\boldsymbol\zeta\boldsymbol\eta^T-
\boldsymbol\eta\boldsymbol\zeta^T)S_4}{1+\sqrt h}
&-\sqrt h\,\boldsymbol\zeta&-\boldsymbol\eta/\sqrt h\\[2mm]
-\boldsymbol\eta^TS_4/\sqrt h&\sqrt h&0\\
\sqrt h\,\boldsymbol\zeta^TS_4&0&\sqrt h
\end{pmatrix}.}
\tag{O3}
$$

Multiplication using $\boldsymbol\zeta^TS_4\boldsymbol\eta=1-h$ verifies
both the inverse and $\mathcal M_{\rm O}^TS_6\mathcal M_{\rm O}=S_6$.
On the longitudinal plane, $\overline{\mathbf r}_{\rm O}=0$, so

$$
\begin{aligned}
\mathbf r&=\sqrt h\,\boldsymbol\zeta\,\bar z_{\rm O}
+\frac{\boldsymbol\eta}{\sqrt h}\bar p_{z,{\rm O}},\\
z&=\sqrt h\,\bar z_{\rm O},\qquad
p_z=\sqrt h\,\bar p_{z,{\rm O}},\\
\mathbf r&=\boldsymbol\zeta z+\frac{\boldsymbol\eta}{h}p_z
=\mathscr D\boldsymbol\ell.
\end{aligned}
\tag{O4}
$$

Thus (D3) and (O2) describe the same physical invariant plane.
Their difference is a canonical change within the separated coordinates:

$$
\boxed{\mathcal M_{\rm O}^{-1}\mathcal M
=\operatorname{diag}\left(
I_4+\frac{\boldsymbol\zeta\boldsymbol\eta^TS_4}{1+\sqrt h}
+\frac{\boldsymbol\eta\boldsymbol\zeta^TS_4}{\sqrt h(1+\sqrt h)},
\begin{pmatrix}1/\sqrt h&0\\0&\sqrt h\end{pmatrix}
\right).}
\tag{O5}
$$

This follows by multiplying (O3) and (D3). Both diagonal blocks in
(O5) are symplectic. In particular,
$\bar z_{\rm O}=\bar z/\sqrt h$ and
$\bar p_{z,{\rm O}}=\sqrt h\,\bar p_z$; the transverse coordinates
also change by the displayed 4×4 block. The decoupled Twiss functions
therefore need not agree numerically. After transforming their decoupled
bases consistently, both constructions recover the same physical
eigenmodes and covariance, up to within-mode phase choices.

For readers comparing with the original paper, this is the complete
translation needed for its Eqs. (100)–(105). Symbols in the left column
are the paper's, not additional notation used in our derivation.

| Paper symbol | Meaning in this note |
|---|---|
| $\widetilde H$ | $\mathcal M_{\rm O}^{-1}$: physical-to-decoupled transformation |
| $a>0$ | $\sqrt h$: common longitudinal diagonal entry of $\mathcal M_{\rm O}$ |
| $H_x$ | $\begin{pmatrix}\sqrt h\,\zeta_x&\eta_x/\sqrt h\\ \sqrt h\,\zeta_{p_x}&\eta_{p_x}/\sqrt h\end{pmatrix}$: horizontal rows of its two longitudinal columns |
| $H_y$ | $\begin{pmatrix}\sqrt h\,\zeta_y&\eta_y/\sqrt h\\ \sqrt h\,\zeta_{p_y}&\eta_{p_y}/\sqrt h\end{pmatrix}$: vertical rows of those columns |

The paper's Eq. (105) extracts these blocks from an already constructed
eigenbasis. In our symbols the same invariant-plane extraction is (D10)
or (D12), followed by (O2). By contrast, (D19) or (D20)–(D21) first
obtain $\mathscr D$ directly from the one-turn map; (D8) then supplies
$\boldsymbol\zeta,\boldsymbol\eta,h$ for either (D3) or (O2).
Solving for the invariant plane and choosing its canonical factorization
are separate operations.

The paper's determinant bars mean determinants, not absolute values.
Its Eq. (109) imposes a second positive determinant for the subsequent
transverse Edwards–Teng step. Failed conditions are handled there by
redefining/exchanging eigenmodes or changing the factorization.
For a fixed selected longitudinal eigenmode, our $h<0$ domain is outside
the real positive-root representation (O2). Another Ohmi factorization
after mode reassignment is not excluded. At $h=0$, (O2)–(O5) and
the graph extraction are unavailable; retain the invariant basis.

The eigenvector normalization also needs translation: if
$\mathbf v_j^{\rm O}$ denotes the paper's complex eigenvector, its
Eq. (79) uses $(\mathbf v_i^{\rm O})^TS_6(\mathbf v_j^{\rm O})^*
=-i\delta_{ij}$. Our convention is
$\mathbf u_j=\sqrt2\,(\mathbf v_j^{\rm O})^*$, with the conjugate
eigenvalue. This normalization difference leaves the real factor (O2)
unchanged.

### 9.5 Xsuite: construction of the normalizer and dispersion readout

This comparison is pinned to xtrack commit
384952bcb2cd44b500b341b87436f3b1cf3bc817, not an unversioned claim about
every Xsuite configuration. The matrix called $W$ in its source is the
full real normalizer $U_6$ in this note; we use $U_6$ below.

The conservative full-6D route in [6] computes eigenvectors of the full
one-turn matrix. For its raw eigenvector $\mathbf v_j^{\rm X}$, it
chooses the conjugate-pair member with
$(\operatorname{Re}\mathbf v_j^{\rm X})^TS_6
\operatorname{Im}\mathbf v_j^{\rm X}>0$ and constructs the real column pair

$$
U_j=
\frac{[\operatorname{Re}\mathbf v_j^{\rm X}\;\;
\operatorname{Im}\mathbf v_j^{\rm X}]}
{\sqrt{(\operatorname{Re}\mathbf v_j^{\rm X})^TS_6
\operatorname{Im}\mathbf v_j^{\rm X}}},
\qquad U_6=[U_1\;\;U_2\;\;U_s].
\tag{X1}
$$

Here each $U_j$ is 6×2. This is the 6D extension of (E6), with our
normalized complex vector proportional to $(\mathbf v_j^{\rm X})^*$.
Thus Xsuite's full normalizer includes transverse–longitudinal decoupling.
The difference from Sections 8–9 is the absence of a separate graph-based
direct/iterative construction of the ordered $\mathcal M$, not missing
coupled linear physics.
Mode sorting uses coordinate projections; continuation must be handled
explicitly in comparisons with our continuously labeled modes.

The readout in [7] eliminates the two longitudinal normal coordinates.
After expressing both codes in the same physical canonical pair, the
two reported response columns are

$$
\boxed{\mathscr D=U_{rs}U_{\ell s}^{-1}
=\left[\boldsymbol\zeta\;\;\frac{\boldsymbol\eta}{h}\right].}
\tag{X2}
$$

The blocks $U_{rs},U_{\ell s}$ are exactly those defined in (D9).
For example, with one-based physical coordinate indices
$a\in\{1,2,3,4\}$ and the longitudinal pair in columns 5 and 6,

$$
\zeta_a=\frac{(U_6)_{a5}(U_6)_{66}-(U_6)_{a6}(U_6)_{65}}
{\det U_{\ell s}},\qquad
\frac{\eta_a}{h}=
\frac{(U_6)_{a6}(U_6)_{55}-(U_6)_{a5}(U_6)_{56}}
{\det U_{\ell s}}.
$$

Consequently the reported momentum-response column must be multiplied
by $h$ to compare with the ordered canonical $\boldsymbol\eta$.
The source's scalar elimination expressions also assume their chosen
pivots exist; projection conditioning should be diagnosed separately from
a phase/pivot choice.

Xsuite's canonical longitudinal pair here is
$(\zeta_{\rm X},p_{\zeta,{\rm X}})$ with
$\zeta_{\rm X}=s-\beta_0ct$ and
$p_{\zeta,{\rm X}}=\Delta E/(\beta_0P_0c)$, whereas Octopus tracks
$(s-\ell,\delta)$. The subscript $\mathrm X$ identifies Xsuite coordinates;
$\zeta_{\rm X}$ is a particle coordinate, not our crab-dispersion vector
$\boldsymbol\zeta$. Convert both coordinates with the reference-orbit
Jacobian before applying (X2). At the reference momentum
$dp_{\zeta,{\rm X}}/d\delta=1$, but this does not make the finite-deviation
variables, their conjugate coordinates, or their derivatives interchangeable.

The four-dimensional construction in [8] is different. When no normalizer
is supplied, it computes both forced response columns using
$I_4-M_{rr}$ and assembles the following 6×6 matrix:

$$
\begin{pmatrix}
U_4&(I_4-M_{rr})^{-1}M_{r\ell}\\
0&I_2
\end{pmatrix}.
\tag{X3}
$$

Here $U_4$ normalizes the transverse problem solved by that 4D route.
The added columns represent fixed-initial-longitudinal-coordinate
transverse responses. This assembled matrix is generally neither a full
6D symplectic normalizer nor a basis for the invariant graph solving
(D14). A 4D/6D comparison must identify the route, not infer it from
the shared field name "crab dispersion."

| Construction | How the selected plane is obtained | Canonical output |
|---|---|---|
| Full eigenbasis | Full 6D eigensystem and symplectic normalization | Full $U_6$; (D10) extracts its graph when available. |
| Ohmi's presented construction | Full eigensystem, then factor extraction; (D12) expresses the dispersion extraction in our convention | $\mathcal M_{\rm O}$ from (O2), then transverse Edwards–Teng and modal Twiss factors. |
| Direct algebraic construction here | Selected trace from (D17), linear solve (D19) | $\mathcal M$ from (D8), (D3), or $\mathcal M_{\rm O}$ from (O2) for $h>0$. |
| Iterative construction here | Sylvester initialization and (D20) or (D21) | The same factors after convergence and branch checks. |

## 10. Propagation, measured tilt, and eigenmode tracking

### 10.1 Propagating 4D eigenvectors and phases

Given a symplectic section map $L_4$ and a phase-fixed $U_{4,{\rm in}}$, transport the basis as $L_4U_{4,{\rm in}}$. Requiring the endpoint normalizer to have the zero entries in (M8) gives

$$
\boxed{\begin{aligned}
\Delta\mu_1&=\operatorname{atan2}
\bigl((L_4U_{4,{\rm in}})_{12},(L_4U_{4,{\rm in}})_{11}\bigr),\\
\Delta\mu_2&=\operatorname{atan2}
\bigl((L_4U_{4,{\rm in}})_{34},(L_4U_{4,{\rm in}})_{33}\bigr).
\end{aligned}}
\tag{F1}
$$

Then

$$
U_{4,{\rm out}}=L_4U_{4,{\rm in}}
\operatorname{diag}[\mathcal R(-\Delta\mu_1),\mathcal R(-\Delta\mu_2)],
\tag{F2}
$$

and

$$
L_4=U_{4,{\rm out}}
\operatorname{diag}[\mathcal R(\Delta\mu_1),\mathcal R(\Delta\mu_2)]
U_{4,{\rm in}}^{-1}.
\tag{F3}
$$

These identities follow directly from the normalized eigenbasis and agree with Eqs. (6.1)–(6.3) of Ref. [2]. The quantities $\Delta\mu_j$ are accumulated eigenmode phase advances, distinct from the relative projection factors $\cos\nu_j,\sin\nu_j$ in Section 6. If only optics propagation is required, the rotation entries can be obtained by normalizing the real pairs in (F1), without evaluating the phase advances.

Unwrap requested phase advances along a sufficiently resolved lattice; a single long section determines them only modulo $2\pi$. If a reference position projection vanishes, use a nonzero component of the transported eigenvector to fix its phase and record the change of convention.

The differential identity $\alpha=-\beta'/2$ should not be used as the general definition of coupled Twiss functions. For physical projected Mais–Ripken functions it follows in regions with the appropriate canonical-to-slope relation and no longitudinal magnetic field; solenoids introduce additional terms. For Edwards–Teng coordinates, the varying decoupling transformation introduces further terms. See Sec. II.B of Ref. [1] and Sec. 5 of Ref. [2].

### 10.2 Propagating dispersion

Partition a section map into 4+2 blocks,

$$
L_6=\begin{pmatrix}L_{rr}&L_{r\ell}\\L_{\ell r}&L_{\ell\ell}\end{pmatrix},
$$

The $L$ block subscripts have the same physical row/column meaning as the
$M$ blocks in (D5), but refer to this section map. Propagating $\binom{\mathscr D_{\rm in}}{I_2}$ gives

$$
\boxed{\mathscr D_{\rm out}=(L_{rr}\mathscr D_{\rm in}+L_{r\ell})
(L_{\ell r}\mathscr D_{\rm in}+L_{\ell\ell})^{-1},}
\tag{F4}
$$

provided the final longitudinal projection is invertible. On a periodic map this reduces to (D14). Convert each endpoint graph to $\boldsymbol\zeta_i,\boldsymbol\eta_i,h_i$,
$i=\mathrm{in},\mathrm{out}$, using (D8), and construct $\mathcal M_i$ from (D3). The canonical section map is

$$
\boxed{\bar L_6=\mathcal M_{\rm out}^{-1}L_6\mathcal M_{\rm in}.}
\tag{F5}
$$

Its upper-left 4×4 block supplies $L_4$ in Section 10.1, and its off-diagonal blocks should vanish to numerical precision. Its longitudinal block is

$$
\boxed{\bar L_s=
\operatorname{diag}(1,1/h_{\rm out})
(L_{\ell r}\mathscr D_{\rm in}+L_{\ell\ell})
\operatorname{diag}(1,h_{\rm in}).}
\tag{F6}
$$

The factors $h_{\rm in},h_{\rm out}$ follow from $p_{z,i}=h_i\bar p_{z,i}$ on the longitudinal plane. The specialized dispersing-section and cavity formulas in Eqs. (17) and (23) of Ref. [3] provide element-level benchmarks. Transporting the full 6D normalizer gives an independent check of (F4)–(F6).

### 10.3 Dispersion and measured bunch tilt

The entries $(M_6)_{1:4,5}$ and $(M_6)_{1:4,6}$ are the one-turn responses to initial $z$ and $p_z$ at fixed initial transverse coordinates. They are the forcing columns $M_{r\ell}$. Periodic dispersion instead satisfies the invariant-plane equation (D14).

A measured bunch-tilt slope also depends on the beam covariance. For an ensemble entirely on the longitudinal plane, with $h\ne0$ and nonzero longitudinal variance, (D7) gives

$$
x=\zeta_x z+\frac{\eta_x}{h}p_z
\quad\Longrightarrow\quad
\boxed{\frac{\operatorname{Cov}(x,z)}{\operatorname{Var}(z)}
=\zeta_x+\frac{\eta_x}{h}
\frac{\operatorname{Cov}(p_z,z)}{\operatorname{Var}(z)}.}
\tag{F7}
$$

The momentum contribution includes the scale conversion between $p_z$ and $\bar p_z$. For a general matched 6D ensemble, evaluate the physical covariance with (K10); all three modes can contribute to the physical longitudinal coordinates. A transfer matrix determines the mode geometry, while beam size and tilt additionally require mode emittances or a beam covariance.

### 10.4 Physical eigenmode labels

At a weak-coupling starting point, label the two betatron modes by their uncoupled continuations and the longitudinal mode by its synchrotron continuation. A small tune can help initialize this choice but is not a universal longitudinal-mode identifier.

For a lattice scan, compare normalized vectors at the same physical point.
Use $S_4$ for transverse vectors or $S_6$ for full vectors. A useful
phase-independent matching score is the absolute symplectic overlap

$$
\frac12\left|\mathbf u_{j,{\rm old}}^\dagger S_d
\mathbf u_{k,{\rm new}}\right|,\qquad d=4\ \text{or}\ 6.
\tag{F8}
$$

Use assignment across all modes, together with continuity and spectral separation. This overlap is a matching score, not a probability. For propagation through a fixed lattice, transport the basis directly rather than independently sorting eigenvalues at every element.

At exact or nearly unresolved resonances, track invariant subspaces and report the ambiguity of individual mode parameters. Arbitrarily mixing eigenvectors with different resolved eigenvalues to impose orthogonality would destroy their eigenvector property. Section 8.8 provides a predictor–corrector continuation method for a separated longitudinal plane; it does not resolve a genuine mode degeneracy.

## 11. Requirements for the planned analysis

No function names, result types, keywords, or contracts are introduced here.
The existing [analysis layer](../../src/analysis/Analysis.jl) is placeholder-only.
A future implementation should separate the following mathematical operations:
normalized mode extraction; complete parameterization conversion; invariant-plane
solution; canonical factorization; basis transport; covariance reconstruction.
Public architecture decisions should be recorded separately when they are made.

The mathematical alternatives for dispersion are eigenplane extraction (D12),
the cubic-root algebraic expression (D19), full-mode projectors (D26)–(D27),
Newton iteration (D21), fixed-point iteration (D20), and the explicit coasting
limit (D24). The predictor (D28)–(D29) initializes scan continuation; it does
not replace the invariant-plane corrector.
If a full normal basis is already required, eigenplane extraction avoids
duplicating the eigenproblem. The direct and iterative routes remain valuable
independent constructions and continuation methods; no universal speed or
conditioning ranking is claimed.

### 11.1 Analysis sequence

1. Find or accept the reference closed orbit, linearize, and convert to the documented canonical coordinates.
2. Scale coordinates for conditioning using a documented transformation; preserve the corresponding symplectic form and transform final results back.
3. Check symplecticity. Do not silently alter a substantially nonsymplectic matrix to make the optics routine succeed.
4. For a 4D problem, run Section 3 directly. For a bunched 6D problem, identify the longitudinal eigenmode and apply the selected dispersion solution method. Initialize an iteration with (D15), a neighboring solution, or the scan predictor (D29). Use (D24) for the coasting block structure (D23).
5. Check the graph invariance (D14) and the selected longitudinal trace or eigenvalue pair, construct the canonical transformation (D3), and obtain the betatron and longitudinal blocks with (K4). Verify their symplecticity and the off-diagonal residuals. If the longitudinal projection is singular, retain the full 6D basis and report that this dispersion representation is unavailable.
6. Where the 4+2 factorization is available, extract Mais–Ripken functions and their cosine/sine factors from the 4D betatron eigenbasis. Derive Edwards–Teng parameters from that basis, and benchmark against (T9) at well-conditioned points. If this chart is unavailable, retain physical projections of all three full modes; do not apply the complete-4D single-$u$ identities to truncated 6D vectors.
7. Propagate the full basis through the lattice, and propagate the graph where its chart is valid. Reconstruct local maps, maintain eigenmode labels, and unwrap phase advances only with sufficient sampling.
8. If requested, combine the full basis with specified mode emittances or a supplied covariance matrix to compute physical beam sizes and tilt.

### 11.2 Numerical status and diagnostics

Return diagnostic information with the optics result, rather than replacing invalid quantities with plausible numbers:

- Coordinate convention and reference point.
- Symplectic defect, unit-circle departure, eigenvector residual, and normalizer reconstruction residual.
- Conjugate-pair separation, eigenmode-label assignment, and near-degeneracy status.
- Edwards–Teng parameterization form, relevant area weights, and block conditioning.
- Longitudinal projection conditioning, $h$, the convention $\mathcal M=\mathcal M_\zeta\mathcal M_\eta$, and the dispersion invariance residual.
- Validity of each relative cosine/sine pair when a projection vanishes.
- Dispersion solution method, selected longitudinal trace, coefficient-matrix or Sylvester conditioning, iteration count, and final invariance residual.
- For a scan, accepted/rejected parameter steps, predictor choice, auxiliary chart changes, and whether an individual mode or a larger unresolved cluster is being continued.

For example, evaluate

$$
\text{normalized eigenmode residual}=\frac{\|M_4U_4-U_4\operatorname{diag}(\mathcal R(\mu_1),\mathcal R(\mu_2))\|}{\max(1,\|M_4U_4\|,\|U_4\|)},
$$

$$
\text{normalized graph residual}=\frac{\|M_{rr}\mathscr D+M_{r\ell}-\mathscr D(M_{\ell r}\mathscr D+M_{\ell\ell})\|}
{\max(1,\|M_{rr}\mathscr D\|,\|M_{r\ell}\|,
\|\mathscr D(M_{\ell r}\mathscr D+M_{\ell\ell})\|)}.
\tag{I1}
$$

Choose numerical tolerances in scaled coordinates, according to precision, Jacobian accuracy, and conditioning. Raw norms mixing metres and dimensionless momenta are not universal physical error measures.

## 12. Verification scope and implementation benchmarks

### 12.1 What is checked, and what remains proposed

The external draft's numerical table is not carried forward as repository
evidence: its original generating scripts were not supplied.
The [review and reproducible algebra checks](../history/audit_twiss_dispersion_theory_2026_09_08.md)
record the independent checks performed for this note, their exact cases,
tolerances, numerical environment, and exclusions.
The subsequent [notation review](../history/audit_twiss_dispersion_notation_2026_09_09.md)
checks the whole note's symbols, compiles every mathematical expression, and
adds algebra checks for the rewritten Ohmi factors, all four Edwards–Teng
transport cases, relative phases, and component-expanded covariance.
The [literature review](../history/audit_twiss_dispersion_literature_2026_09_09.md)
checks the Parzen cubic conversion, symmetric 6D projectors and signed areas,
and the continuation predictor against manufactured canonical maps. It
also records removal of the former GLSF application section; its historical
checks remain in the earlier records, not in the current design requirements.
Those checks establish sampled algebraic consistency, not correctness of a
yet-unimplemented Octopus analysis or agreement with tracked physical lattices.

A future implementation must reproduce each applicable identity and test
failure diagnostics, chart changes, and independent reference constructions.
The lattice benchmarks below are requirements, **not passed tests**.

### 12.2 Lattice benchmarks

1. **Uncoupled lattice:** recover known Courant–Snyder functions, zero secondary projections, and the correct phase and tune branch.
2. **Known coupled construction:** cover both signs of $\det R$, both forms, a change of form, and reconstruction of all matrix blocks.
3. **Momentum dispersion:** compare with a finite difference of the coasting closed orbit using the same momentum and coordinate convention.
4. **Crab coupling:** embed a canonical thin kick $p_x\mapsto p_x+kz$, $p_z\mapsto p_z+kx$ in a stable ring. Include both companion kicks under (C2).
5. **Full 6D covariance:** compare direct covariance transport with reconstruction from the three normal modes and specified rms mode emittances.
6. **Dispersion solution methods:** compare eigenvector, both algebraic constructions, fixed-point, and Newton results on the same longitudinal branch. Check Parzen's block cubic against (D17), and the three signed-area row/column sums in (K12). Include a case with a poorly conditioned raw Sylvester operator and verify that the routine reports it or selects another method.
7. **Ohmi and Xsuite conventions:** verify (O2)–(O5) and (X2) after coordinate conversion; distinguish full-6D normalization from forced 4D responses.
8. **Parameter continuation:** compare (D28) against finite differences, verify the $O((\Delta t)^2)$ predictor error and corrected graph residual, and preserve mode identity across a physical projection singularity using the full basis. Reject ambiguous steps near a mode collision; do not claim the individual plane remains unique there.
9. **Exceptional cases:** exercise nearly equal mode frequencies, eigenvalues near $\pm1$, ill-conditioned longitudinal projections, and the $h=0$ graph singularity. Include negative $h$. Verify that diagnostics identify ambiguous or unavailable parameters without returning spurious unique values.

## Appendix A. Single-transverse-plane Edwards–Teng reduction

For the $(x,p_x,z,p_z)$ reduction in Eqs. (28)–(32) of Ref. [3],
use $V_1(R)$ from (T2) with the second pair interpreted as longitudinal
and no vertical coupling. Its longitudinal columns are
$\lambda\binom{\operatorname{adj}(R)}{I_2}$. Consequently
$\mathscr D_{(x,p_x),:}=\operatorname{adj}(R)$, with zero $y,p_y$ rows.
Equations (T3) and (D8) give $h=\lambda^2>0$ on this selected form.
The corresponding components of the full dispersion vectors are

$$
\boxed{\begin{pmatrix}
\zeta_x&\eta_x\\
\zeta_{p_x}&\eta_{p_x}
\end{pmatrix}
=\operatorname{adj}(R)\begin{pmatrix}1&0\\0&\lambda^2\end{pmatrix}
=(\lambda\operatorname{adj}(R))
\begin{pmatrix}1/\lambda&0\\0&\lambda\end{pmatrix}.}
\tag{A1}
$$

The off-diagonal coupling block in Ref. [3] is
$\lambda\operatorname{adj}(R)$ in this notation, so (A1) reproduces its
Eq. (32). This reduction does not cover a fixed longitudinal mode with
negative $h$. Equations (D9)–(D12) extend the extraction to the full 6D
longitudinal plane without restricting its transverse coupling to one
physical plane.

## References

[1] D. Sagan and D. Rubin, “Linear analysis of coupled lattices,” *Phys. Rev. ST Accel. Beams* **2**, 074001 (1999). [doi:10.1103/PhysRevSTAB.2.074001](https://doi.org/10.1103/PhysRevSTAB.2.074001).

[2] V. A. Lebedev and S. A. Bogacz, “Betatron motion with coupling of horizontal and vertical degrees of freedom,” *JINST* **5**, P10010 (2010). [doi:10.1088/1748-0221/5/10/P10010](https://doi.org/10.1088/1748-0221/5/10/P10010).

[3] D. Xu, Y. Luo, and Y. Hao, “Combined effects of crab dispersion and momentum dispersion in colliders with local crab crossing scheme,” *Phys. Rev. Accel. Beams* **25**, 071002 (2022). [doi:10.1103/PhysRevAccelBeams.25.071002](https://doi.org/10.1103/PhysRevAccelBeams.25.071002).

[4] R. H. Bartels and G. W. Stewart, “Solution of the matrix equation $AX+XB=C$,” *Commun. ACM* **15**, 820–826 (1972). [doi:10.1145/361573.361582](https://doi.org/10.1145/361573.361582).


[5] K. Ohmi, K. Hirata, and K. Oide, “From the beam-envelope matrix to
synchrotron-radiation integrals,” *Phys. Rev. E* **49**, 751–765 (1994),
especially Sec. III A–B, Eqs. (76)–(110).
[doi:10.1103/PhysRevE.49.751](https://doi.org/10.1103/PhysRevE.49.751).

[6] Xsuite developers, xtrack
[linear_normal_form.py](https://github.com/xsuite/xtrack/blob/384952bcb2cd44b500b341b87436f3b1cf3bc817/xtrack/linear_normal_form.py),
commit 384952bcb2cd44b500b341b87436f3b1cf3bc817:
get_linear_normal_form, _build_w_matrix_from_eigenvectors, sort_modes.

[7] Xsuite developers, xtrack
[lattice_functions_from_W.py](https://github.com/xsuite/xtrack/blob/384952bcb2cd44b500b341b87436f3b1cf3bc817/xtrack/twiss/lattice_functions_from_W.py),
same commit, dispersion ratios and returned fields.
Canonical-coordinate construction also uses
[transfer_matrices.py](https://github.com/xsuite/xtrack/blob/384952bcb2cd44b500b341b87436f3b1cf3bc817/xtrack/twiss/transfer_matrices.py)
and [optics_propagation.py](https://github.com/xsuite/xtrack/blob/384952bcb2cd44b500b341b87436f3b1cf3bc817/xtrack/twiss/optics_propagation.py).

[8] Xsuite developers, xtrack
[periodic_solution.py](https://github.com/xsuite/xtrack/blob/384952bcb2cd44b500b341b87436f3b1cf3bc817/xtrack/twiss/periodic_solution.py),
same commit, four-dimensional normalizer assembly.

[9] G. Parzen, “Normal mode tunes for linear coupled motion in six dimensional
phase space,” arXiv:acc-phys/9506001 (1995), especially Eqs. (22)–(27).
[preprint](https://arxiv.org/pdf/acc-phys/9506001).

[10] S. Glukhov, “Symmetry properties of a symplectic transport matrix and Twiss
parameterization of a fully coupled motion,” *Phys. Rev. Accel. Beams*
**28**, 084001 (2025), especially Secs. III–VIII, X–XI, and Appendix B.
[doi:10.1103/3ld3-dmmv](https://doi.org/10.1103/3ld3-dmmv).

[11] L. Dieci and M. J. Friedman, “Continuation of invariant subspaces,”
*Numerical Linear Algebra with Applications* **8**, 317–327 (2001).
[doi:10.1002/nla.245](https://doi.org/10.1002/nla.245);
[author preprint, February 19, 2001](https://dieci.math.gatech.edu/preps/DiFrContInvSub.pdf).
Equation numbers cited above refer to this supplied preprint.
