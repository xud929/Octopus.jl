export RefTilted

# ---------------------------------------------------------------------------
# ref_tilt: a roll of the DESIGN ORBIT PLANE.
#
# Derivation, the PTC comparison, and the convention split over which frame an
# alignment error is quoted in when the design orbit is rolled:
# `docs/theory/misalignment_and_patch_maps.md` Sections 6a and 6b.
#
# This is the second of the two things the word "tilt" means, and the codes do
# not agree on which one they call it:
#
#   roll the magnet BODY, design orbit unchanged     Bmad `roll`      MAD-X `EALIGN, dpsi`
#   roll the DESIGN ORBIT plane                      Bmad `ref_tilt`  MAD-X `sbend, tilt=`
#
# The first is an error and is Octopus's `tilt`, handled as a misalignment. The
# second is a design choice: it says the reference trajectory itself bends in a
# rotated plane. A vertical bend is a horizontal bend with `ref_tilt = pi/2`,
# and without this it is inexpressible.
#
# So MAD-X's `tilt` on a bend is Bmad's `ref_tilt`, NOT Octopus's `tilt`. A
# lattice translated by matching the keyword spelling rather than the meaning
# gets a rolled magnet where it wanted a rolled orbit, which is a machine error
# where the design intended geometry.
#
# The map is a conjugation, and it is complete for tracking. Octopus's lattice
# is a sequence of maps in local curvilinear frames; a bend already turns its
# frame by `hL`, and conjugating it with an `s`-roll makes it turn in a rotated
# plane, after which the next element simply receives coordinates in the new
# frame. Nothing absolute -- no survey, no global geometry -- is required. What
# `ref_tilt` cannot do without a geometry layer is REPORT where the magnet sits
# in space, which is a different question from tracking through it.
# ---------------------------------------------------------------------------

"""
    RefTilted(inner, c, s)

An element whose design orbit plane is rolled about the longitudinal axis.

Holds the element it wraps and the cosine and sine of the roll. The map is

    design --R(-ref_tilt)--> rolled --[element]--> rolled --R(+ref_tilt)--> design

a conjugation by a rotation of `(x, px)` against `(y, py)`. Being a rotation
composed with a symplectic map and its inverse, it is symplectic whenever the
inner element is, and it leaves `z` and `pz` untouched: a roll about `s` maps
the `s = 0` plane to itself, so unlike a misalignment there is no drift onto a
displaced face and no path-length term.
"""
struct RefTilted{E,T<:AbstractFloat} <: AbstractTrackOp
    inner::E
    c::T
    s::T
end

"""
Rotate the transverse coordinates and momenta by `-psi`, given `c = cos psi` and
`s = sin psi`. Pass `-s` to rotate by `+psi`.

This is `_frame_change` with `Q = R_z(psi)` and no offset, written out: with the
rotation about `s`, the third row of `Q` is `(0, 0, 1)`, so `rz` vanishes, the
drift term `ds` vanishes with it, and the square root over `p_s` that the
general frame change needs is dead work. Four lines remain.
"""
@inline _s_rotate(c, s, x, px, y, py) =
    (c * x + s * y, c * px + s * py, c * y - s * x, c * py - s * px)

@inline function track_particle(method::AbstractTrackingMethod, elem::RefTilted,
                                x, px, y, py, z, pz)
    c, s = elem.c, elem.s
    x, px, y, py = _s_rotate(c, s, x, px, y, py)
    x, px, y, py, z, pz = track_particle(method, elem.inner, x, px, y, py, z, pz)
    x, px, y, py = _s_rotate(c, -s, x, px, y, py)
    return x, px, y, py, z, pz
end

@inline (elem::RefTilted)(x, px, y, py, z, pz) =
    track_particle(_inner_method(elem.inner), elem, x, px, y, py, z, pz)

_inner_method(inner) = inner.method
_inner_method(inner::MisalignedElement) = _inner_method(inner.inner)

"""
    _ref_tilt_wrap(spec, inner)

Wrap `inner` in a `RefTilted` if the spec carries a `ref_tilt`, and return it
untouched otherwise. Called from `compile_runtime` **outside**
`_misalignment_wrap`.

The roll being the outer wrapper is a statement about the *maps*, not about
whose frame an alignment error is quoted in. Those are separate questions and
only the first one is settled here: the magnet that a misalignment displaces is
the rolled magnet, in every convention. Which axes the displacement is measured
along is a convention split, it is resolved in `_misalignment_wrap`, and the
`:madx` branch conjugates the error into the rolled frame rather than reordering
these two wrappers.

Ordering therefore cannot be tested with one parameter at a time. Both a roll
and a misalignment must be nonzero before any of it is observable, which is what
`cfbend_reftilt_mis_dx` and `cfbend_reftilt_mis_all` exist for.

The rotation itself is not composed here. It comes from `_misalign_matrix`, the
same routine the misalignments and the patch use, whose sign and composition
order are pinned against PTC. A pure `R_z(psi)` in that routine's row-major
layout has `W[1] = cos psi` and `W[4] = sin psi`, and `_frame_change` applies the
transpose, which is why these two entries are exactly the entrance rotation.

Applied to any element that carries the parameter, not only to bends. For a
straight element it coincides exactly with `tilt` -- rolling the design plane of
an orbit that does not bend is the same as rolling the body -- so a `ref_tilt`
there is redundant rather than ignored, and the equality is a test.
"""
function _ref_tilt_wrap(spec, inner)
    T = Float64
    psi = T(getparam(spec, :ref_tilt, zero(T)))
    psi == 0 && return inner
    W = _misalign_matrix(T, zero(T), zero(T), psi, false)
    return RefTilted(inner, W[1], W[4])
end
