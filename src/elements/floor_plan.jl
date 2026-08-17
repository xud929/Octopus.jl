# Draft of src/elements/floor_plan.jl — reviewed against the theory note
# before installation; installed only after the audit commit lands.
export FloorFrame, survey

"""
    FloorFrame

One row of a floor-plan survey (docs/theory/floor_plan_survey.md): the global
frame at an element's EXIT, MAD-X `SURVEY` conventions — `position` is
`(X, Y, Z)`, `theta` the azimuth about global `Y`, `phi` the elevation
(`+` upward), `psi` the roll, with `W = R_Y(θ)·R_X(−φ)·R_Z(ψ)` the local→
global rotation whose flattened rows are `w`. `s` is the arc position of the
exit, from the same placement lengths the arc survey sums.
"""
struct FloorFrame
    s::Float64
    position::NTuple{3,Float64}
    theta::Float64
    phi::Float64
    psi::Float64
    w::NTuple{9,Float64}
end

# Row-major 3x3 helpers over NTuple{9}. The rotation CONVENTION is not
# re-derived here: bends and patches compose through the same numeric anchors
# the theory note pins against MAD-X, and patches reuse _patch_rotation.
@inline _fp_mul(a::NTuple{9,Float64}, b::NTuple{9,Float64}) = (
    a[1]*b[1]+a[2]*b[4]+a[3]*b[7], a[1]*b[2]+a[2]*b[5]+a[3]*b[8], a[1]*b[3]+a[2]*b[6]+a[3]*b[9],
    a[4]*b[1]+a[5]*b[4]+a[6]*b[7], a[4]*b[2]+a[5]*b[5]+a[6]*b[8], a[4]*b[3]+a[5]*b[6]+a[6]*b[9],
    a[7]*b[1]+a[8]*b[4]+a[9]*b[7], a[7]*b[2]+a[8]*b[5]+a[9]*b[8], a[7]*b[3]+a[8]*b[6]+a[9]*b[9])
@inline _fp_apply(w::NTuple{9,Float64}, v::NTuple{3,Float64}) = (
    w[1]*v[1]+w[2]*v[2]+w[3]*v[3],
    w[4]*v[1]+w[5]*v[2]+w[6]*v[3],
    w[7]*v[1]+w[8]*v[2]+w[9]*v[3])
@inline _fp_transpose(w::NTuple{9,Float64}) =
    (w[1], w[4], w[7], w[2], w[5], w[8], w[3], w[6], w[9])
const _FP_IDENTITY = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
@inline _fp_ry(a) = (cos(a), 0.0, sin(a), 0.0, 1.0, 0.0, -sin(a), 0.0, cos(a))
@inline _fp_rz(a) = (cos(a), -sin(a), 0.0, sin(a), cos(a), 0.0, 0.0, 0.0, 1.0)

"""
    _floor_step(entry) -> (d, R)

One element's LOCAL geometric contribution: displacement `d` of the exit
origin and rotation `R` of the exit frame, both in the entry frame
(theory note §2). Derived generically rather than per kind:

- any spec with frame curvature `h ≠ 0` and arc length `L` bends by
  `α = h·L` in the plane rolled by `ref_tilt` — the SURVEY follows `h` and
  never `b0`, exactly as the misalignment survey does, and this one rule
  covers `:sbend`, the curved solenoid, and any future curved kind without
  an enumeration to go stale;
- a patch contributes its `(dx, dy, dz)` and its `_patch_rotation` matrix —
  the same matrix its tracking map applies to coordinates, transposed,
  because coordinates and frames transform contragradiently (pinned by the
  `srot`/`yrot` MAD-X fixtures and by the note's §4 item 2);
- everything else is straight: `d = (0, 0, L)` with the placement length.
"""
function _floor_step(entry)
    spec = entry isa LineEntry ? getfield(entry, :spec) : entry
    L = _placement_length(entry)
    if spec isa ElementSpec{:patch}
        dx = Float64(getparam(entry, :dx, 0.0))
        dy = Float64(getparam(entry, :dy, 0.0))
        dz = Float64(getparam(entry, :dz, 0.0))
        ax = Float64(getparam(entry, :angle_x, 0.0))
        ay = Float64(getparam(entry, :angle_y, 0.0))
        as = Float64(getparam(entry, :angle_s, 0.0))
        madx = getparam(entry, :convention, :bmad) === :madx
        R = _fp_transpose(_patch_rotation(Float64, ax, ay, as, madx))
        return (dx, dy, dz), R
    end
    return _floor_arc_step(entry, Float64(L))
end

# The arc-or-straight tail of `_floor_step`, at an arbitrary length `ell`
# along the element. `ell = L` is the full step; `ell < L` is the PARTIAL
# step the curved-girder reference point needs when the girder's centre
# (arc length L/2 of the assembly) falls inside a member. Patches never
# take the partial form: they are zero-length, so no interior point exists.
function _floor_arc_step(entry, ell::Float64)
    h = Float64(getparam(entry, :h, 0.0))
    if !iszero(h) && !iszero(ell)
        alpha = h * ell
        rho = 1.0 / h
        t = Float64(getparam(entry, :ref_tilt, 0.0))
        d0 = (rho * (cos(alpha) - 1.0), 0.0, rho * sin(alpha))
        rt = _fp_rz(t)
        return _fp_apply(rt, d0), _fp_mul(rt, _fp_mul(_fp_ry(-alpha), _fp_transpose(rt)))
    end
    return (0.0, 0.0, ell), _FP_IDENTITY
end

_floor_children(line::ElementSpec{:line}) = line_entries(line)

"""
    survey(elements) -> Vector{FloorFrame}

The floor plan: global position and orientation at every element exit, from
the initial frame `V = 0`, `W = I` (local `s` along global `+Z`), in MAD-X
`SURVEY` conventions. Accepts a line spec, a `BeamLine`, or a tuple of
specs/placements; kept-whole sub-lines are DESCENDED (their bends turn the
frame — the opposite choice from the arc walker, and deliberate on both
sides). Misalignments and `tilt` never move the survey; `ref_tilt` and
patches do. External check: `MADXSurveyConsistencyContract` compares every
column against MAD-X per element. Derivation and the measured convention
anchors: docs/theory/floor_plan_survey.md.
"""
function survey(elements)
    out = FloorFrame[]
    V = (0.0, 0.0, 0.0)
    W = _FP_IDENTITY
    s = Ref(0.0)
    V, W = _survey_walk!(out, elements, V, W, s)
    return out
end
survey(line::ElementSpec{:line}) = survey(line_entries(line))

function _survey_walk!(out, elements::Union{Tuple,AbstractVector}, V, W, s)
    for e in elements
        V, W = _survey_walk!(out, e, V, W, s)
    end
    return V, W
end
function _survey_walk!(out, entry, V, W, s)
    spec = entry isa LineEntry ? getfield(entry, :spec) : entry
    if spec isa ElementSpec{:line}
        return _survey_walk!(out, line_entries(spec), V, W, s)
    end
    spec isa AbstractElementSpec || return V, W     # in-line hooks: no geometry
    d, R = _floor_step(entry)
    V = V .+ _fp_apply(W, d)
    W = _fp_mul(W, R)
    s[] += _placement_length(entry)
    push!(out, FloorFrame(s[], V, _fp_theta(W), _fp_phi(W), _fp_psi(W), W))
    return V, W
end

# MAD-X angle extraction (theory note §3, verified against the tilt = 0.3
# anchor to the last printed digit). At the gimbal edge |phi| = pi/2 the
# atan2 pairs degrade to 0/0 = 0 rather than throwing.
@inline _fp_theta(w) = atan(w[3], w[9])
@inline _fp_phi(w) = asin(clamp(w[6], -1.0, 1.0))
@inline _fp_psi(w) = atan(w[4], w[5])

# Geometry-bearing entries of a line, flattened: kept-whole sub-lines are
# descended (their bends turn the frame, as in `_survey_walk!`), in-line
# hooks are dropped. Explicit flattening rather than a recursive closure so
# nothing mutable is captured (the `Core.Box` class).
function _girder_flat_entries!(out, entries)
    for e in entries
        spec = e isa LineEntry ? getfield(e, :spec) : e
        if spec isa ElementSpec{:line}
            _girder_flat_entries!(out, line_entries(spec))
        elseif spec isa AbstractElementSpec
            push!(out, e)
        end
    end
    return out
end

"""
    _girder_design_frames(line, starget) -> (Aref, Xref, Aend, Xend)

The frames a misaligned BEAM LINE's `_misalign_frames_from` needs, from the
same floor-plan steps `survey` composes: the design frame at arc length
`starget` along the assembly (the reference point -- `0.0` for the MAD-X
entrance convention, `total_length/2` for the Bmad centre convention) and the
design exit frame, both in the line's entrance coordinates. The reference
point may fall INSIDE a member, in which case that member contributes a
partial arc step; on an exact member boundary the frame after the crossing is
taken. The step and frame conventions here are the SAME row-major forms
`_survey_frame` uses (a single arc reproduces it identically -- pinned by the
girder testset), so the composed frames drop into the misalignment machinery
with no conversion.

Computed in `Float64`, like every floor-plan quantity: the design geometry
carries no dependence on the girder's own alignment parameters, so
alignment-seeded duals differentiate correctly through the wrap; a dual
seeded on a MEMBER's design length or curvature is truncated here, as it is
in `survey` itself.
"""
function _girder_design_frames(line::ElementSpec{:line}, starget::Float64)
    V = (0.0, 0.0, 0.0)
    W = _FP_IDENTITY
    Vref, Wref = V, W
    captured = starget <= 0.0
    s = 0.0
    for e in _girder_flat_entries!(Any[], line_entries(line))
        Lp = Float64(_placement_length(e))
        if !captured && starget < s + Lp
            d, R = _floor_arc_step(e, starget - s)
            Vref = V .+ _fp_apply(W, d)
            Wref = _fp_mul(W, R)
            captured = true
        end
        d, R = _floor_step(e)
        V = V .+ _fp_apply(W, d)
        W = _fp_mul(W, R)
        s += Lp
        if !captured && s >= starget
            Vref, Wref = V, W
            captured = true
        end
    end
    captured || ((Vref, Wref) = (V, W))
    return Wref, Vref, W, V
end
