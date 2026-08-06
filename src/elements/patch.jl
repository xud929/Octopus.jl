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
"""
@inline function _patch_map(elem::Patch{M,T}, x, px, y, py, z, pz) where {M,T}
    ps = sqrt((1 + pz)^2 - px * px - py * py)
    W = _patch_rotation(T, elem.angle_x, elem.angle_y, elem.angle_s, elem.madx)
    # Position relative to the new origin, and the full three-momentum.
    r1, r2, r3 = _patch_apply(W, x - elem.dx, y - elem.dy, -elem.dz)
    q1, q2, q3 = _patch_apply(W, px, py, ps)
    # Drift to the new entrance face, s = 0.
    ds = -r3
    xn = r1 + ds * q1 / q3
    yn = r2 + ds * q2 / q3
    # Path length actually travelled over that drift, and the reference length
    # the frame change itself represents.
    path = ds * (1 + pz) / q3
    ref = _patch_reference_length(elem, W)
    return xn, q1, yn, q2, z + ref - path + elem.t_offset, pz
end

"""
Reference path length through the patch: the new origin's displacement projected
onto the new `s` axis. This is what the on-axis reference particle traverses, and
subtracting it is what keeps `z` measured against the reference rather than
against the old frame.
"""
@inline function _patch_reference_length(elem::Patch, W)
    _, _, s = _patch_apply(W, elem.dx, elem.dy, elem.dz)
    return s
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

Composing a patch with its exact inverse is the identity, which is the cheapest
check that the rotation is composed in the right direction.
"""
abstract type PatchSpec end

PatchSpec(; kwargs...) = ElementSpec{:patch}(_spec_params(; kwargs...))

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
    conv = Symbol(getparam(spec, :convention, :bmad))
    conv in (:bmad, :madx) || throw(ArgumentError(
        "patch convention must be :bmad or :madx; got $(repr(conv))"))
    T = float(promote_type(typeof(dx), typeof(dy), typeof(dz),
                           typeof(ax), typeof(ay), typeof(as), typeof(dt), Float64))
    return Patch{typeof(method),T}(method, T(dx), T(dy), T(dz),
                                   T(ax), T(ay), T(as), T(dt), conv === :madx)
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
        convention=ParamMeta(default=:bmad, meaning="rotation composition order when more than one angle is nonzero, :bmad or :madx. The same split the misalignments carry, and the same default; single-axis rotations agree either way"),
        t_offset=ParamMeta(default=0, meaning="reference arrival-time offset, in the same units as z. Lets a patch express a path-length difference between two branches rather than only a geometric one"),
        tracking_method=ParamMeta(default=NonSymplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    )
    example = PatchSpec(angle_x=12.5e-3)
    construction_help = "Friendly constructor: PatchSpec(; dx=0, dy=0, dz=0, angle_x=0, angle_y=0, angle_s=0, t_offset=0, convention=:bmad, tracking_method=NonSymplectic6DMap()). A DELIBERATE frame change -- a crossing angle, a beamline junction, a spectrometer arm -- not a misalignment: the new frame persists downstream instead of being restored. The map is exact in delta and amplitude because it is geometry, and composing a patch with its inverse is the identity. Derivation: docs/theory/misalignment_and_patch_maps.md Section 7.5. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end
