# Node-Indexed Interaction Meshes

What `interaction_grid = :node` is for, why it works, and what it costs.

This note is self-contained. The surrounding numerical analysis — how the slice
field is interpolated between longitudinal solve nodes, and the error constants —
is in [`slice_longitudinal_interpolation.md`](slice_longitudinal_interpolation.md);
this note covers only the mesh-indexing question.

## 1. The problem

In a sliced strong-strong collision, the field of one source slice is solved on a
transverse mesh and interpolated onto the opposing beam's particles. The mesh has
to be sized from the particles it serves, so the natural implementation sizes one
mesh per **slice pair** — that is the default, `interaction_grid = :slice_pair`.

That makes the mesh a function of the field particle's slice index. And the slice
index is a *step function* of the particle's longitudinal coordinate `z`.

The PIC discretization error depends on the mesh — on its origin and cell size.
So the kick a particle receives is

$$\Delta\mathbf p_\perp(z) = \underbrace{\Delta\mathbf p^{\text{exact}}_\perp(z)}_{\text{smooth in }z} + \underbrace{\varepsilon\big(\mathcal G(s(z))\big)}_{\text{step function of }z}$$

Two particles infinitesimally apart in `z`, on opposite sides of a slice
boundary, are kicked on **different meshes** and therefore receive different
discretization errors. The kick is discontinuous.

Measured magnitude: $\sim10^{-3}$ relative, which is roughly five times the
longitudinal interpolation error it sits beside, and it does not shrink with more
slices.

Why this matters: particles execute synchrotron motion, sweeping back and forth
across slice boundaries every synchrotron period. A discontinuity sampled
periodically is a noise source that drives artificial emittance growth — and
`interaction_grid = :source_slice` was measured to reduce vertical emittance
growth by 7-31%, confirming the mechanism is dynamically real, not cosmetic.

## 2. The observation the fix rests on

The algorithm *already* guarantees continuity, and only the mesh spoils it.

Adjacent field slices share a boundary: `rb` of slice `s` is `lb` of slice `s+1`.
The field solves are performed at source drifts $\sigma = (c-z)/2$ evaluated at the
slice boundaries, so

$$\sigma_R^{(s)} = \tfrac12\big(c - z_R^{(s)}\big) = \tfrac12\big(c - z_L^{(s+1)}\big) = \sigma_L^{(s+1)}.$$

The right node of one slice and the left node of the next are **the same source
drift** — the same physical field. Taking limits from either side of the shared
boundary $z^*$, the interpolation weights collapse to $(0,1)$ and $(1,0)$, so both
sides evaluate that *same* plane. In exact arithmetic the transverse kick is
already $C^0$.

It is only because the two sides read that shared plane on **different meshes**
that they disagree.

## 3. The fix

Index the mesh by the **interpolation node** instead of the slice:

```text
nodes:     z_0     z_1     z_2     z_3
meshes:    G_0     G_1     G_2     G_3
slices:       [ 1 ]   [ 2 ]   [ 3 ]
```

Slice `s` reads node `s` on `G_s` and node `s+1` on `G_{s+1}`. Slice `s+1` reads
node `s+1` on `G_{s+1}` and node `s+2` on `G_{s+2}`.

At the boundary between them both sides evaluate **node `s+1` on `G_{s+1}`** —
the same plane on the same mesh. The discretization error is now identical on
both sides and cancels exactly, restoring the $C^0$ property the algorithm
already had analytically.

Measured: the transverse boundary jump falls from $\sim10^{-3}$ to
$1.1\times10^{-9}$ — the floating-point floor.

### 3.1 Why not just share one mesh for everything

`interaction_grid = :source_slice` does that: one mesh per source slice, sized to
the union over all its field slices. It removes the jump equally well, but the
union must cover the source drifted across the field beam's *entire* longitudinal
range, and a drifted slice grows as $\sigma\sqrt{1+(s/\beta^*)^2}$. On production
EIC parameters that coarsens the vertical cells by $2.70\times$ in one of the two
collision directions.

A node mesh covers only its own drift and the two slices adjacent to it, so there
is no union over the beam and no hourglass sensitivity: measured coarsening
$1.05-1.12\times$.

## 4. Why three planes per slice

Node mode has two requirements that pull in opposite directions.

**Transverse continuity** requires each node's plane be read on *that node's*
mesh — that is the whole point of Section 3.

**The longitudinal kick** is a *difference*,
$\Delta p_z \propto (\phi_L-\phi_R)/\Delta z$: a small difference of two large,
nearly-equal potentials. Within one mesh the discretization errors in $\phi_L$ and
$\phi_R$ are strongly correlated and cancel. Across two meshes they do not, and
because the signal is itself a small difference the residue swamps it — measured
20-50% error in $\Delta p_z$, with a discrepancy that varies more than its own
mean (relative spread 1.51), so it is not a removable constant offset either.

The asymmetry is exactly **average versus difference**:

| quantity | form | error behaviour |
|---|---|---|
| $\Delta\mathbf p_\perp$ | weighted **average**, weights sum to 1 | independent errors stay the same size |
| $\Delta p_z$ | **difference** of nearly-equal values | independent errors are amplified |

Averages tolerate independent errors, which is what lets the transverse blend read
each node's plane on its own mesh. Differences require *correlated* errors, which
forces the longitudinal pair onto one mesh.

So each slice needs three planes:

| plane | node | drift | mesh | purpose |
|---|---|---|---|---|
| `F_L` | `s` | $\sigma_s$ | `G_s` | transverse left; longitudinal left $\phi$ |
| `F_R` | `s+1` | $\sigma_{s+1}$ | `G_{s+1}` | transverse right |
| `F_Z` | `s+1` | $\sigma_{s+1}$ | **`G_s`** | longitudinal right $\phi$ |

`F_R` and `F_Z` are the *same physical field*, differing only in which mesh they
are discretized on. `F_Z` is `F_L`'s **longitudinal partner**: the right-end
potential re-solved on the left node's mesh so that the difference has correlated
errors.

`:slice_pair` never meets this conflict because it puts every plane of a pair on
one mesh — which is precisely the choice that creates the discontinuity.

## 5. Cost, and a design decision

Per source slice over `N` field slices, `:slice_pair` solves `2N` planes and
`:node` solves `3N`.

Only `2N+1` are *distinct*: there are `N+1` node planes (one per node) and `N`
longitudinal partners. The duplication is that `F_R` for slice `s` and `F_L` for
slice `s+1` are the same quantity — same node, same drift, same mesh, same source
slice.

**Sharing them is rejected.** The two uses occur at different points in the
collision schedule, and the source slice is kicked in between, so reusing the
first would leave the second one step stale. That trades away *physical*
strong-strong self-consistency to pay for removing a *numerical* artefact, which
defeats the purpose of the option. Self-consistency is not negotiable for a
performance number.

So `:node`'s solve count is inherently $1.5\times$ the baseline's, which appears
as a ~26% excess on the interaction stage (0.3912 s against 0.3110 s at the
production point). Any further optimization must come from implementation
overhead — mesh construction, Green-FFT reuse — not from the solve count.

## 6. What it does not fix

Node indexing removes the *mesh* contribution to the boundary discontinuity. Two
other mechanisms from Section 5 of the companion note remain:

- **Source evolution between collisions.** The shared node is solved once per
  adjacent slice and the source is kicked in between, so the two solves differ.
  Measured residual: $2.2\times10^{-5}$ (`Dpx`), $7.6-8.1\times10^{-5}$ (`Dpy`) —
  about $40\times$ below the mesh jump it replaces, and now the leading term.
- **Per-turn re-slicing jitter**, which `grid_extent = :sigma` addresses instead.

And node indexing does nothing for the *longitudinal* sawtooth, which is a
property of the two-node interpolation itself; that is what
`slice_interpolation = :quadratic` addresses.

## References

1. Companion note:
   [`slice_longitudinal_interpolation.md`](slice_longitudinal_interpolation.md) —
   the interpolation error analysis, the continuity-breaker taxonomy, and all
   measured tables.
2. Measurement records:
   `validation/slice_longitudinal_zscan.jl` (boundary jump),
   `validation/slice_interpolation_emittance_growth.jl` (dynamics),
   `validation/pic_option_consistency.jl` (multi-turn agreement and cost).
3. History:
   [`../history/slice_longitudinal_interpolation_record.md`](../history/slice_longitudinal_interpolation_record.md).
