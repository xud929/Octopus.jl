export PatchSpec, Patch

# ---------------------------------------------------------------------------
# Patch: a deliberate change of reference frame.
#
# Design: `docs/theory/misalignment_and_patch_maps.md` Section 7.5. Reference
# implementation: Bmad's `track_a_patch`.
#
# A patch is NOT a misalignment, and the difference is intent rather than
# arithmetic. A misalignment says a magnet is not where it was meant to be, is
# referenced to that magnet's centre, and restores the frame at its exit. A
# patch says the reference frame genuinely changes here, attaches to no element,
# and the new frame persists downstream. Expressing a crossing angle as a
# misalignment would restore the frame where the geometry says it must not, and
# would report a design choice as a machine error to anything reading alignment.
# ---------------------------------------------------------------------------

# `T<:Number` rather than `T<:AbstractFloat`: the same widening the magnet
# needed, and for the same reason -- a dual number is `<:Real` and a truncated
# power series is `<:Number`, so the tighter bound refuses a parameter
# derivative. Float64 still satisfies it, so ordinary elements are unchanged.
"""
    Patch{M,T}

Exact change of reference frame: translate the origin, rotate the axes, then
drift each particle to the new entrance face.

The map is exact in `(1+delta)` and in amplitude -- it is geometry, not an
expansion -- and it is symplectic because a rigid frame change is a canonical
transformation.

`dx`, `dy`, `dz` place the new frame's origin in the old frame. `angle_x`,
`angle_y` and `angle_s` rotate its axes, composed in that order to match
`_rot_xz`'s convention. `t_offset` shifts the reference arrival time, which is
what lets a patch describe a path-length difference between two branches rather
than only a geometric one.

!!! warning "A patch angle and a misalignment angle of the same value roll opposite ways"
    A patch and the misalignment/`ref_tilt` family share `_misalign_matrix`, but
    apply it in opposite senses: the patch forms `W * a` (`_patch_apply`) while
    the frame changes form `Wᵀ * a` (`_frame_change`, `_s_rotate`). So
    `PatchSpec(angle_s = +ψ)` and `tilt = +ψ` are **not** the same rotation --
    they are inverses.

    Measured: a quadrupole with `tilt = +0.37` equals the same quadrupole
    sandwiched between `PatchSpec(angle_s = -0.37)` and
    `PatchSpec(angle_s = +0.37)` exactly (0.0), and differs from the
    `(+0.37, -0.37)` sandwich by 2.0e-4 (2026-08-05_b audit, U16-5).

    This is a convention split, not a defect on either side: the misalignment
    family is pinned against PTC at 5e-13 by the `quad_mis_all`/`cfbend_mis_all`
    reference cases, and the patch follows Bmad's `track_a_patch`. What was
    missing is that `_patch_rotation`'s rationale below -- sharing the matrix so
    a patch "cannot drift away from the magnets it sits between" -- guarantees
    the composition order and the x-sign, and NOT the overall sense. Compose the
    two by measurement, not by assuming the parameter names agree.
"""
struct Patch{M<:AbstractTrackingMethod,T<:Number} <: AbstractTrackOp
    method::M
    dx::T
    dy::T
    dz::T
    angle_x::T
    angle_y::T
    angle_s::T
    t_offset::T
    madx::Bool               # composition order; false = :bmad, as for misalignments
end

# Cross-backend rounding class (`CrossBackendRounding`, src/track/Track.jl).
_cross_backend_rounding(::Patch) = _rounding_class(untouched=(:pz,), ulp=(:x, :px, :y, :py, :z), ulp_bound=8,
    why="the rotation `_patch_rotation` from `sin`/`cos` of the angles, evaluated per particle on each backend's libm, and the fused frame products `W1 x + W2 y + W3 dz` (33% of 1e5 particles part in py for a rotation about x); z through the face drift and the reference excess; pz is never written")

"""
    _patch_rotation(T, angle_x, angle_y, angle_s, madx)

Frame matrix for a patch, built by the **same** routine misalignments use.

This delegates to `_misalign_matrix` rather than composing its own rotation, and
that is the whole point: the composition order and the sign on the x-rotation are
a genuine convention split that PTC and Bmad resolve differently, they agree for
any single rotation and disagree at second order once two are nonzero, and they
are already **pinned against PTC** by the `quad_mis_all` and `cfbend_mis_all`
reference cases (all three angles, agreement 5e-13). A patch composing its own
matrix would be unvalidated and free to drift away from the magnets it sits
between.

The mapping is by *axis*, which is what the patch's parameter names say:

    angle_y  ->  theta   (R_y, MAD-X's x_pitch)
    angle_x  -> -phi     (R_x, MAD-X's y_pitch, which carries the sign flip)
    angle_s  ->  psi     (R_z, tilt)

The negation on `angle_x` is not a correction; it is what makes
`angle_x = +eps` a positive rotation about the x axis given that
`_misalign_matrix` builds `R_x(-phi)`.

What is shared is the matrix, not the SENSE in which it is applied: the patch
forms `W * a` here while the misalignment and `ref_tilt` paths form `Wᵀ * a`.
The guarantee above is therefore about composition order and the x-sign, which
are the parts PTC and Bmad genuinely disagree on -- it is not a guarantee that
`angle_s = +psi` and `tilt = +psi` mean the same roll. They are inverses; see
the warning on `Patch` (audit U16-5).
"""
@inline _patch_rotation(::Type{T}, ax, ay, as, madx::Bool) where {T} =
    _misalign_matrix(T, ay, -ax, as, madx)

@inline function _patch_apply(W, a1, a2, a3)
    r11, r12, r13, r21, r22, r23, r31, r32, r33 = W
    return (r11 * a1 + r12 * a2 + r13 * a3,
            r21 * a1 + r22 * a2 + r23 * a3,
            r31 * a1 + r32 * a2 + r33 * a3)
end

"""
Exact patch map. Three steps, following Bmad's `track_a_patch`:

1. **Re-origin.** The particle sits at `(x, y, 0)` in the old frame; express it
   relative to the new origin at `(dx, dy, dz)`.
2. **Rotate.** Carry the offset position *and the full three-momentum* into the
   new frame. Rotating only the momentum is a common and silent error -- it
   leaves the particle at the right angle in the wrong place.
3. **Drift to the face.** The rotated particle is generally not on the new
   frame's `s = 0` plane, so drift it there. This is what gives a patch an
   effective length and makes `dz` change path length rather than merely
   relabel.

`p_s` is formed from the incoming momenta and is invariant under the rotation
(a rotation preserves `|p|` and `delta`), so the drift uses the rotated
`s`-component rather than recomputing a square root.

The drift to the face is spelled as `_lattice_drift`'s straight drift is: the
transverse update as `q / q3 * ds` and the path-length EXCESS over `ds` formed
cancellation-free, `ds (q1^2 + q2^2) / (q3 ((1 + p_z) + q3))` (exact by
`|q| = 1 + p_z`, with `_pt2_fused` so both backends round it alike), rather
than `z + ref - ds (1 + p_z)/q3`, which rounded two numbers near `ds` to
`eps(ds)` before cancelling them (the drift's own defect, 2026-10-16 neighbour
audit, U2-4). `z` is then `z + sxy + ref_excess - excess`: `sxy = r31 x +
r32 y` is the particle's transverse position projected on the new axis
(`s - ds`, exactly, by linearity), `ref_excess` the reference particle's own
excess over its projection `s`, the same expression at the reference's
direction `W (0, 0, 1)`. Two identities the suite pins hold by construction
rather than by two association orders agreeing: a purely longitudinal patch
has `sxy = 0`, `ref_excess = 0` and `q == p` exactly, so it IS the drift bit
for bit; the on-axis reference particle has `ds == s` and `q == W (0, 0, 1)`
exactly, so `excess == ref_excess` bitwise and it lands at exactly `z = 0`.

The reference bookkeeping used to live in a reference-length helper that
returned the new origin's displacement PROJECTED onto the new `s` axis
under a docstring claiming the projection was what the reference particle
traverses. It is not: the particle drifts `s/q3`, not `s`, to reach the face,
so a patch carrying both a `dz` and a transverse-axis rotation shifted `z` by
`dz (cos theta - 1)` (-1.943e-5 at `dz=0.23, angle_y=0.013`, -2.498e-3 at
`dz=0.50, angle_y=0.100`; 2026-08-05_b audit, U16-4). `ref_excess` above is
the corrected form, inline; the helper outlived its caller and was retired
(2026-10-18 audit, F-137).
"""
@inline function _patch_map(elem::Patch{M,T}, x, px, y, py, z, pz) where {M,T}
    ps = _ps_or_dead((1 + pz)^2 - px * px - py * py)
    W = _patch_rotation(T, elem.angle_x, elem.angle_y, elem.angle_s, elem.madx)
    # Position relative to the new origin, and the full three-momentum.
    r1, r2, r3 = _patch_apply(W, x - elem.dx, y - elem.dy, -elem.dz)
    q1, q2, q3 = _patch_apply(W, px, py, ps)
    # Drift to the new entrance face, s = 0.
    ds = -r3
    xn = r1 + q1 / q3 * ds
    yn = r2 + q2 / q3 * ds
    # The path travelled over that drift exceeds `ds` by `excess`; the
    # reference particle's path to the face exceeds its projection `s` by
    # `ref_excess` (the same expression at the reference's direction); `ds`
    # and `s` differ by the particle's transverse projection `sxy`.
    excess = ds * _pt2_fused(q1, q2) / (q3 * ((1 + pz) + q3))
    _, _, s = _patch_apply(W, elem.dx, elem.dy, elem.dz)
    q1r, q2r, q3r = _patch_apply(W, zero(T), zero(T), one(T))
    ref_excess = s * _pt2_fused(q1r, q2r) / (q3r * (one(T) + q3r))
    sxy = W[7] * x + W[8] * y
    return xn, q1, yn, q2, z + sxy + ref_excess - excess + elem.t_offset, pz
end

@inline track_particle(::NonSymplectic6DMap, elem::Patch, x, px, y, py, z, pz) =
    _patch_map(elem, x, px, y, py, z, pz)

@inline (elem::Patch)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

"""
    PatchSpec(; dx, dy, dz, angle_x, angle_y, angle_s, t_offset)

A deliberate change of reference frame — a crossing angle, a beamline junction,
a spectrometer arm, or a straight magnet entered at an angle.

**Not a misalignment.** `MisalignedElement` says a magnet is not where it was
meant to be and restores the frame at that magnet's exit; a `PatchSpec` says the
frame genuinely changes here and the change persists downstream. Using one for
the other is wrong in both directions: it would restore a frame the geometry
says must not be restored, and it would record a design choice as a machine
error.

The map is exact in `(1+delta)` and in amplitude, because it is geometry rather
than an expansion, and it is symplectic because a rigid frame change is a
canonical transformation. It declares `NonSymplectic6DMap` for a different
reason: the *particle-count* is preserved but the map is not a magnet map, and
the tracking-method tag names the kernel family rather than a physics claim.

```julia
PatchSpec(angle_x = 12.5e-3)          # a VERTICAL frame rotation: this
                                      # deflects in y (py = -0.0125). A
                                      # horizontal crossing angle -- which is
                                      # what every crossing in this repository
                                      # is -- is `angle_y` (2026-08-05_b audit,
                                      # U16-6: this line read "a crossing
                                      # angle" and named the wrong plane).
PatchSpec(dx = 0.05, dz = 1.2)        # a beamline junction
```

Composing a patch with its exact inverse (the transposed rotation -- the
`:madx` order with negated angles -- and the origin `-W·(dx, dy, dz)`) is the
identity in the transverse coordinates and momenta, which is the cheapest
check that the rotation is composed in the right direction. It is NOT the
identity in `z`: each patch measures `z` against its own entrance reference
particle (see `_patch_map`), so the round trip shifts every particle by the
same constant `R1 + R2 = (W31 dx + W32 dy + (W33 - 1) dz)/W33` -- the two
reference particles' paths -- which `t_offset = -(R1 + R2)` on the inverse
removes (measured -1.033905e-3 at `dx=0.03, dy=-0.02, dz=0.4` with all three
angles nonzero, equal to the derivation; 2026-10-18 audit, F-135).

`PatchSpec{T}(; ...)` is the typed form: `T` is the number type the patch
compiles in (`numeric_type`; `Float32` for a Float32 line).
"""
abstract type PatchSpec{T} end

# Untyped: stored as given, compiled in `numeric_type(spec)` (the Float64-floor
# promotion); `numeric_type=T` by keyword routes to the typed form, which
# stores `numeric_type = T` and the floating-point inputs as `T` (one precision
# rule for every kind, owner decision 2026-10-16).
function PatchSpec(; numeric_type=nothing, kwargs...)
    numeric_type === nothing || return PatchSpec{numeric_type}(; kwargs...)
    return ElementSpec{:patch}(_spec_params(; kwargs...))
end
(::Type{PatchSpec{T}})(; kwargs...) where {T} = ElementSpec{:patch}(_typed_spec_params(T; kwargs...))

default_method(::Type{ElementSpec{:patch}}) = NonSymplectic6DMap()

function Patch(spec::ElementSpec{:patch},
               method::AbstractTrackingMethod=NonSymplectic6DMap())
    dx = getparam(spec, :dx, 0)
    dy = getparam(spec, :dy, 0)
    dz = getparam(spec, :dz, 0)
    ax = getparam(spec, :angle_x, 0)
    ay = getparam(spec, :angle_y, 0)
    as = getparam(spec, :angle_s, 0)
    dt = getparam(spec, :t_offset, 0)
    # `numeric_type(spec)`: the stored type of a `PatchSpec{T}`, else the
    # Float64-floor promotion of the stored parameters (one rule, 2026-10-16).
    T = numeric_type(spec)
    return Patch{typeof(method),T}(method, T(dx), T(dy), T(dz),
                                   T(ax), T(ay), T(as), T(dt), _patch_madx(spec))
end

"""
    _patch_madx(spec_or_entry) -> Bool

The patch's rotation-composition order as the ONE normalisation both consumers
read: `true` for `:madx`, `false` for `:bmad`, a String spelling accepted
either way, anything else refused by name. The tracking constructor above and
the floor plan's `_floor_step` each had their own reading -- `Symbol(...)` here,
`=== :madx` there -- so `convention="madx"` tracked in the `:madx` order and
surveyed in the `:bmad` order (5.9e-2 apart in the rotation matrix at 0.2 and
0.3 rad), and a misspelt String surveyed silently as `:bmad` (2026-10-18 audit,
F-133). A `LineEntry` reads through its merged parameters, like every placement
parameter.
"""
function _patch_madx(entry)
    conv = Symbol(getparam(entry, :convention, :bmad))
    conv in (:bmad, :madx) || throw(ArgumentError(
        "patch convention must be :bmad or :madx; got $(repr(conv))"))
    return conv === :madx
end

@element_spec begin
    kind = :patch
    spec_type = ElementSpec{:patch}
    friendly_constructor = PatchSpec
    runtime_type = Patch
    description = "Deliberate change of reference frame: translate, rotate, drift to the new face."
    keywords = [:coordinate_transform, :thin_element]
    tracking_methods = [NonSymplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        dx=ParamMeta(default=0, meaning="horizontal position of the new frame origin in the old frame"),
        dy=ParamMeta(default=0, meaning="vertical position of the new frame origin"),
        dz=ParamMeta(default=0, meaning="longitudinal position of the new frame origin; changes path length rather than merely relabelling, because the map drifts to the new face"),
        angle_x=ParamMeta(default=0, meaning="rotation of the new frame about the x axis, in radians"),
        angle_y=ParamMeta(default=0, meaning="rotation about the y axis, in radians"),
        angle_s=ParamMeta(default=0, meaning="roll of the new frame about the longitudinal axis, in radians"),
        convention=ParamMeta(default=:bmad, alternatives=(:bmad, :madx), meaning="rotation composition order when more than one angle is nonzero, :bmad or :madx. The same split the misalignments carry, and the same default; single-axis rotations agree either way"),
        t_offset=ParamMeta(default=0, meaning="reference arrival-time offset, in the same units as z. Lets a patch express a path-length difference between two branches rather than only a geometric one"),
        tracking_method=ParamMeta(default=NonSymplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = PatchSpec(angle_x=12.5e-3)
    construction_help = "Friendly constructor: PatchSpec(; dx=0, dy=0, dz=0, angle_x=0, angle_y=0, angle_s=0, t_offset=0, convention=:bmad, tracking_method=NonSymplectic6DMap()). A DELIBERATE frame change -- a crossing angle, a beamline junction, a spectrometer arm -- not a misalignment: the new frame persists downstream instead of being restored. The map is exact in delta and amplitude because it is geometry; composing a patch with its exact inverse restores the transverse coordinates and momenta, while z shifts by the two reference particles' path constant (see the docstring). Derivation: docs/theory/misalignment_and_patch_maps.md Section 7.5. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel. numeric_type (every kind): the number type the element compiles in, Float64 unless built by the typed form PatchSpec{T}(; ...) or given numeric_type=T by keyword (Float32 for a Float32 line; the untyped form promotes its inputs over a Float64 floor and never narrows); a beam whose element type differs from the element's is refused by name when a task compiles the line."
end
