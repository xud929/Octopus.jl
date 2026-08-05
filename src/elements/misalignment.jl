export MisalignedElement

# ---------------------------------------------------------------------------
# Misalignment: a rigid displacement of an element body.
#
# A misalignment does not change the field. It changes the relationship between
# the body frame and the design frame the coordinates live in, so the map is a
# change of frame applied to the particle, wrapped around the untouched element:
#
#     design --M_in--> body --[element]--> body --M_out--> design
#
# Each M is a canonical transformation, so symplecticity is inherited and no new
# argument is needed. Derivation and the PTC/Bmad comparison:
# `docs/theory/misalignment_and_patch_maps.md`.
#
# This lives OUTSIDE any element. A misalignment is a property of where an
# element sits, not of how it tracks, so it composes with a tracking map rather
# than being reimplemented inside each one. `compile_runtime` wraps whatever
# runtime an element produces, which is why a new element type gets
# misalignments for free and cannot get the convention subtly wrong.
#
# The factorization is Bmad's -- one rotation applied to position and momentum,
# then a single exact drift onto the displaced plane -- rather than PTC's four
# sequential one-parameter maps, because it costs one square root instead of
# four. The bookkeeping is PTC's: the entrance and exit maps are derived
# independently from the geometry, never one from the other.
# ---------------------------------------------------------------------------

"""
Body-to-design rotation, row-major. The transpose maps design axes to body axes
and is what the entrance map needs.

The three elementary rotations are the same and so are their signs; the two
codes differ only in the **order they compose**, which is a genuine convention
split and not a sign slip:

    :bmad   W = R_y(x_pitch) R_x(-y_pitch) R_z(tilt)
    :madx   W = R_z(tilt) R_x(-y_pitch) R_y(x_pitch)

Bmad's is `floor_angles_to_w_mat`, a fixed-axis composition. MAD-X's comes from
`MAD_MISALIGN_FIBRE` calling `GEO_ROT` three times with `ent1 = ent2 = ent` reset
before each, so each rotation is taken about the *already rotated* axes -- an
intrinsic sequence z, then x, then y, which composes as `R_z R_x R_y`. The two
agree exactly for any single rotation, which is why one-degree-of-freedom
reference cases cannot tell them apart, and disagree at second order in the
angles once more than one is nonzero.
"""
function _misalign_matrix(::Type{T}, θ, φ, ψ, madx::Bool) where {T}
    sθ, cθ = sincos(T(θ)); sφ, cφ = sincos(T(φ)); sψ, cψ = sincos(T(ψ))
    z = one(T); n = zero(T)
    Ry = (cθ, n, sθ, n, z, n, -sθ, n, cθ)
    Rx = (z, n, n, n, cφ, sφ, n, -sφ, cφ)          # R_x(-phi)
    Rz = (cψ, -sψ, n, sψ, cψ, n, n, n, z)
    return madx ? _m3(_m3(Rz, Rx), Ry) : _m3(_m3(Ry, Rx), Rz)
end

"""
Move the particle from one frame to another and drift it onto the new face.

`Q` holds the destination frame's axes as columns, expressed in the source
frame, row-major; `o` is the destination origin in source coordinates. The
particle enters on the source face (`s = 0`) and leaves on the destination face.

The drift is what makes this more than a matrix multiply: the destination face
is a different plane in space, and the distance to it depends on the particle.

The longitudinal update carries no `+ds` term. Unlike a drift, a frame change
does not move the reference particle, so only the path-length *difference*
enters -- matching PTC's `TRANS` and `ROT_XZ`, which likewise update the
longitudinal variable by `ds (1+delta)/p_s` alone.

One kernel serves both faces and both geometries. Everything that distinguishes
an entrance from an exit, or a straight magnet from a bend, is in the `(Q, o)`
pair, which `_misalign_frames` computes once at compile time.
"""
@inline function _frame_change(Q::NTuple{9,T}, o::NTuple{3,T},
                               x, px, y, py, z, pz) where {T}
    ps = sqrt((1 + pz)^2 - px * px - py * py)
    ax = x - o[1]; ay = y - o[2]; az = -o[3]
    rx = Q[1] * ax + Q[4] * ay + Q[7] * az          # Q' a
    ry = Q[2] * ax + Q[5] * ay + Q[8] * az
    rz = Q[3] * ax + Q[6] * ay + Q[9] * az
    qx = Q[1] * px + Q[4] * py + Q[7] * ps          # Q' p
    qy = Q[2] * px + Q[5] * py + Q[8] * ps
    qz = Q[3] * px + Q[6] * py + Q[9] * ps
    ds = -rz
    return rx + ds * qx / qz, qx, ry + ds * qy / qz, qy, z - ds * (1 + pz) / qz, pz
end

# Small row-major 3x3 helpers. Compile-time only, so clarity beats speed.
@inline _m3(A, B) = ntuple(k -> begin
        i, j = divrem(k - 1, 3)
        A[3i + 1] * B[j + 1] + A[3i + 2] * B[j + 4] + A[3i + 3] * B[j + 7]
    end, 9)
@inline _m3t(A, B) = ntuple(k -> begin
        i, j = divrem(k - 1, 3)
        A[i + 1] * B[j + 1] + A[i + 4] * B[j + 4] + A[i + 7] * B[j + 7]
    end, 9)                                          # A' * B
@inline _m3v(A, v) = (A[1] * v[1] + A[2] * v[2] + A[3] * v[3],
                      A[4] * v[1] + A[5] * v[2] + A[6] * v[3],
                      A[7] * v[1] + A[8] * v[2] + A[9] * v[3])
@inline _m3tv(A, v) = (A[1] * v[1] + A[4] * v[2] + A[7] * v[3],
                       A[2] * v[1] + A[5] * v[2] + A[8] * v[3],
                       A[3] * v[1] + A[6] * v[2] + A[9] * v[3])

"""
    _survey_frame(T, h, s)

The design frame at arc length `s`, expressed in the frame at `s = 0`: the
origin and the axes as columns.

This is the survey, and it is the whole content of the curved case. With
curvature `h` the design orbit is the arc

    X(s) = ( -(1 - cos hs)/h , 0 , sin(hs)/h ),

whose tangent turns by `hs` and whose local `x` axis turns with it, so the frame
rotation is `R_y(-hs)`. Both components route through the same
cancellation-safe helpers the drift uses, so `h = 0` returns the straight frame
exactly rather than by cancellation.

**It depends on `h` only.** The design geometry is set by the reference frame
curvature; `b0` is the field the magnet actually has. Octopus keeps the two
independent (a bend off its design orbit has `h != b0`), and a misalignment is a
statement about geometry, so `b0` must not appear here.
"""
function _survey_frame(::Type{T}, h::T, s::T) where {T}
    o = (-_curv_vers(h, s), zero(T), _curv_sin(h, s))
    c, sn = cos(h * s), sin(h * s)
    A = (c, zero(T), -sn,
         zero(T), one(T), zero(T),
         sn, zero(T), c)
    return A, o
end

"""
    _misalign_frames(T, W, d, h, L, sref)

Build the two `(Q, o)` pairs `_frame_change` needs, from the survey.

The body is the design element displaced rigidly about the design point at arc
length `sref`: the body reference frame sits at that design frame, offset by `d`
and rotated by `W`, both taken in that frame's own axes. From there the body's
own survey gives its entrance and exit faces, and the design survey gives the
faces the tracking coordinates must return to.

    entrance:  design frame at s=0          ->  body frame at body-arc -sref
    exit:      body frame at body-arc L-sref -> design frame at s=L

`sref` is where the two codes disagree, and it is not a detail. Bmad references
a misalignment to the element **centre** (`sref = L/2`), which is what survey
data means. MAD-X's `EALIGN`, via `MAD_MISALIGN_FIBRE`, references it to the
**entrance** (`sref = 0`), taking the displacement in entrance-frame axes. The
two agree for a pure translation of a straight element and disagree for
everything else -- notably for any rotation, and for a translation of a bend,
whose centre axes are turned by `hL/2` from its entrance axes.

The exit pair is built from the exit geometry, never by inverting the entrance
pair. For a straight element the two are related by a translation and inverting
would happen to work; for a bend the design frame has turned by `hL` in between,
so it would be wrong at first order in the bend angle -- and wrong in a way a
FODO test cannot see, because it needs a bend to show up at all.
"""
function _misalign_frames(::Type{T}, W::NTuple{9,T}, d::NTuple{3,T},
                          h::T, L::T, sref::T) where {T}
    Ac, C = _survey_frame(T, h, sref)                # design reference point
    Ob = C .+ _m3v(Ac, d)                            # body reference origin
    Ab = _m3(Ac, W)                                  # body reference axes
    Aen, Xen = _survey_frame(T, h, -sref)            # body entrance, in body axes
    Aex, Xex = _survey_frame(T, h, L - sref)         # body exit, in body axes
    Q_in = _m3(Ab, Aen)
    o_in = Ob .+ _m3v(Ab, Xen)
    Q_ex = _m3(Ab, Aex)
    o_ex = Ob .+ _m3v(Ab, Xex)
    Ad, Xd = _survey_frame(T, h, L)                  # design exit face
    # Express the design exit frame in body-exit coordinates.
    Q_out = _m3t(Q_ex, Ad)
    o_out = _m3tv(Q_ex, Xd .- o_ex)
    return Q_in, o_in, Q_out, o_out
end


"""
    MisalignedElement(inner, qin, oin, qout, oout)

An element displaced rigidly from its design position.

Holds the element it wraps and the two frame changes around it. Being a
composition of canonical maps with a symplectic one, it is symplectic whenever
the inner element is, and it is agnostic about what the inner element does --
magnet, cavity, or anything added later.
"""
# `T<:Number` rather than `T<:AbstractFloat`: the same widening the magnet
# needed, and for the same reason -- a dual number is `<:Real` and a truncated
# power series is `<:Number`, so the tighter bound refuses a parameter
# derivative. Float64 still satisfies it, so ordinary elements are unchanged.
struct MisalignedElement{E,T<:Number} <: AbstractTrackOp
    inner::E
    qin::NTuple{9,T}; oin::NTuple{3,T}
    qout::NTuple{9,T}; oout::NTuple{3,T}
end

@inline function track_particle(method::AbstractTrackingMethod, elem::MisalignedElement,
                                x, px, y, py, z, pz)
    x, px, y, py, z, pz = _frame_change(elem.qin, elem.oin, x, px, y, py, z, pz)
    x, px, y, py, z, pz = track_particle(method, elem.inner, x, px, y, py, z, pz)
    return _frame_change(elem.qout, elem.oout, x, px, y, py, z, pz)
end

# `_inner_method` rather than `elem.inner.method`: the wrapped op need not be a
# single magnet. A misaligned beam line wraps a `CompositeLine`, which is what
# makes a cryostat work, and it carries no method of its own.
@inline (elem::MisalignedElement)(x, px, y, py, z, pz) =
    track_particle(_inner_method(elem.inner), elem, x, px, y, py, z, pz)

# Forward the tracking context through the frame change. Without this method
# the generic AbstractTrackOp fallback (Track.jl) dropped ctx, so a wrapped
# stochastic element (LumpedRad) silently fell back to its contextless
# stateful RNG — non-repeatable draws and no CPU/CUDA identity (2026-08-05
# audit, F13; measured |dx| = 1.4e-4 between two identical ctx calls).
@inline function (elem::MisalignedElement)(ctx::TrackingContext, particle_id,
                                           x, px, y, py, z, pz)
    x, px, y, py, z, pz = _frame_change(elem.qin, elem.oin, x, px, y, py, z, pz)
    x, px, y, py, z, pz = elem.inner(ctx, particle_id, x, px, y, py, z, pz)
    return _frame_change(elem.qout, elem.oout, x, px, y, py, z, pz)
end

"""
    _misalignment_wrap(spec, inner)

Wrap `inner` in a `MisalignedElement` if `spec` carries a misalignment, and
return it untouched otherwise. Called from `compile_runtime`, so it applies to
every element without any element knowing about it.

The survey geometry comes from `L` and `h` on the spec: the frame curvature,
never the field, because a misalignment is a statement about geometry. An
element that declares neither is treated as zero length and straight, which is
what a thin element is.

# Misalignment against a rolled design orbit

When the element also carries a `ref_tilt`, the two codes disagree again, and in
the same style as `sref`: about **which frame the alignment error is stated in**.

    :bmad   the ROLLED frame. `track_a_bend` rotates by `ref_tilt` first and
            calls `offset_particle` inside that, so the offsets are the element's
            own transverse axes -- which the roll has turned.
    :madx   the UNROLLED design frame. `EALIGN` is survey data about where the
            magnet sits in the machine, so `dx` stays horizontal no matter how
            the design orbit is rolled.

Only the axes the error is *measured in* differ; the magnet being displaced is
the rolled one either way. So the `:madx` branch conjugates the rigid transform
into the rolled frame, `W -> R_z(-psi) W R_z(psi)` and `d -> R_z(-psi) d`, and
`ref_tilt` stays the outer wrapper in both.

This overturns what `docs/todo.md` predicted before the comparison was run. That
entry reasoned that a design choice must compose outside an error, and concluded
the roll wraps the misalignment in every convention. For MAD-X it is the other
way round: the error is stated in the unrolled frame, which is the roll composed
*inside*. The entry was right about the trap, though -- the difference is
invisible until both parameters are nonzero, and the one-at-a-time cases that
pin every other misalignment cannot see it. `cfbend_reftilt_mis_dx` and
`cfbend_reftilt_mis_all` are the cases that can: at `ref_tilt = 0.3` the wrong
choice lands 2.0e-4 and 3.5e-4 away from PTC, against 2.8e-13 and 4.5e-13 for
the right one.

The `:bmad` branch is Bmad's documented behaviour read from `track_a_bend`, and
unlike the `:madx` branch it is **not** pinned by a reference case here -- there
is no Bmad in this repository's validation path, the same position the `:bmad`
rotation-composition order is already in.
"""
function _misalignment_wrap(spec, inner)
    # Promoted from the spec, so seeding an alignment parameter with a dual
    # gives a derivative of the orbit with respect to the misalignment --
    # what beam-based alignment and orbit correction need.
    T = numeric_type(spec)
    dx = T(getparam(spec, :x_offset, zero(T)))
    dy = T(getparam(spec, :y_offset, zero(T)))
    dz = T(getparam(spec, :z_offset, zero(T)))
    xp = T(getparam(spec, :x_pitch, zero(T)))
    yp = T(getparam(spec, :y_pitch, zero(T)))
    tl = T(getparam(spec, :tilt, zero(T)))
    (dx == 0 && dy == 0 && dz == 0 && xp == 0 && yp == 0 && tl == 0) && return inner
    conv = Symbol(getparam(spec, :misalign_convention, :bmad))
    conv in (:bmad, :madx) || throw(ArgumentError(
        "misalign_convention must be :bmad or :madx; got $(repr(conv))"))
    madx = conv === :madx
    L = T(getparam(spec, :L, zero(T)))
    h = T(getparam(spec, :h, zero(T)))
    sref = madx ? zero(T) : L / 2          # MAD-X references the entrance
    W = _misalign_matrix(T, xp, yp, tl, madx)
    d = (dx, dy, dz)
    psi = T(getparam(spec, :ref_tilt, zero(T)))
    if madx && psi != 0
        # Carry an error stated in the unrolled design frame into the rolled one
        # the body lives in. R_z comes from `_misalign_matrix` rather than being
        # written out here, for the reason the patch does the same.
        R = _misalign_matrix(T, zero(T), zero(T), psi, false)
        W = _m3(_m3t(R, W), R)
        d = _m3tv(R, d)
    end
    qin, oin, qout, oout = _misalign_frames(T, W, d, h, L, sref)
    return MisalignedElement(inner, qin, oin, qout, oout)
end
