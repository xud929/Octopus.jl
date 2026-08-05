export MarkerSpec, ThinMultipoleSpec, ThinDipoleSpec, ThinQuadrupoleSpec,
       ThinSextupoleSpec, HKickerSpec, VKickerSpec, KickerSpec,
       Marker, ThinMultipole

# ---------------------------------------------------------------------------
# Zero-length elements.
#
# A thin element carries *integrated* strengths: `knl[i]` is `K_{i-1} L`, the
# limit of a thick magnet as `L -> 0` at fixed `K L`. That is the same limit
# MAD-X's MULTIPOLE takes, and it is why these elements take `knl`/`ksl` rather
# than `kn`/`ks` -- the units differ, and silently reusing the thick names would
# invite a magnet that is wrong by a factor of its own length.
#
# All of them share one runtime, because they are all the same map: a thin
# multipole kick plus an optional steering kick. The kind is metadata, exactly
# as it is for the thick magnets.
# ---------------------------------------------------------------------------

"""
    Marker(spec, method)

The identity map. A marker occupies no length and does nothing to a particle;
it exists so a lattice can name a position -- an interaction point, a survey
reference, the place a diagnostic will eventually live.

Kept as a real element rather than an omission so that a line's element list
matches the lattice description it came from, and so that positions survive
round-tripping through a lattice file.
"""
struct Marker{M<:AbstractTrackingMethod} <: AbstractTrackOp
    method::M
end
Marker(::ElementSpec, method::AbstractTrackingMethod=Symplectic6DMap()) = Marker(method)

@inline track_particle(::Symplectic6DMap, ::Marker, x, px, y, py, z, pz) =
    (x, px, y, py, z, pz)
@inline (elem::Marker)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

# `T<:Number` rather than `T<:AbstractFloat`: a dual number is `<:Real` and a
# truncated power series is `<:Number`, so the tighter bound refuses a parameter
# derivative outright. Float64 still satisfies it, so nothing else changes.
"""
    ThinMultipole{M,T,N}

Zero-length multipole kick with an optional steering kick.

The multipole part is the thick kick of `_lattice_kick` at unit length in a
straight frame, evaluated with integrated strengths, so it is the same
expansion, the same factorial convention and the same real recurrence:

    dpx - i dpy = -sum_n (K_n L + i Ks_n L) (x + iy)^n / n!

The steering part is `hkick`/`vkick`, added last. It is kept separate from
`knl[1]` on purpose even though both are dipole kicks: a corrector is defined by
the kick it delivers, `dpx = +hkick`, while a dipole field of integrated
strength `K0 L` gives `dpx = -K0 L`. Folding one into the other would silently
flip the sign of every corrector in a lattice.

Being zero length, the map has no drift and no chromatic denominator: in the
exact Hamiltonian the chromatic dependence lives in the drift, and there is none
here. It is exactly symplectic, being a kick from a potential.
"""
struct ThinMultipole{M<:AbstractTrackingMethod,T<:Number,N} <: AbstractTrackOp
    method::M
    knl::NTuple{N,T}
    ksl::NTuple{N,T}
    hkick::T
    vkick::T
end

@inline function track_particle(::Symplectic6DMap, elem::ThinMultipole{M,T,N},
                                x, px, y, py, z, pz) where {M,T,N}
    x, px, y, py, z, pz =
        _lattice_kick(elem.knl, elem.ksl, zero(T), one(T), x, px, y, py, z, pz)
    return x, px + elem.hkick, y, py + elem.vkick, z, pz
end

@inline (elem::ThinMultipole)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

function ThinMultipole(spec::ElementSpec,
                       method::AbstractTrackingMethod=tracking_method(spec))
    T = numeric_type(spec)
    knraw = collect(T, getparam(spec, :knl, ()))
    ksraw = collect(T, getparam(spec, :ksl, ()))
    knl, ksl = _strength_tuples(T, knraw, ksraw)
    return ThinMultipole{typeof(method),T,length(knl)}(
        method, knl, ksl,
        T(getparam(spec, :hkick, zero(T))), T(getparam(spec, :vkick, zero(T))))
end

# Named integrated strengths, folded into knl/ksl the same way the thick magnets
# fold k1/k2/k3 into kn/ks.
const _THIN_MULTI_NAMED = ((:k0l, :k0sl, 0), (:k1l, :k1sl, 1), (:k2l, :k2sl, 2),
                           (:k3l, :k3sl, 3), (:k4l, :k4sl, 4), (:k5l, :k5sl, 5))
const _THIN_DIP_NAMED = ((:k0l, :k0sl, 0),)
const _THIN_QUAD_NAMED = ((:k1l, :k1sl, 1),)
const _THIN_SEXT_NAMED = ((:k2l, :k2sl, 2),)

for (kind, ctor, named) in ((:thin_multipole, :ThinMultipoleSpec, :_THIN_MULTI_NAMED),
                            (:thin_dipole, :ThinDipoleSpec, :_THIN_DIP_NAMED),
                            (:thin_quadrupole, :ThinQuadrupoleSpec, :_THIN_QUAD_NAMED),
                            (:thin_sextupole, :ThinSextupoleSpec, :_THIN_SEXT_NAMED))
    @eval begin
        abstract type $ctor end
        $ctor(; kwargs...) = ElementSpec{$(QuoteNode(kind))}(_spec_params(;
            _fold_named_strengths($named, kwargs; nkey=:knl, skey=:ksl)...))
    end
end

"""
Friendly constructor for `ElementSpec{:thin_multipole}`: a zero-length
multipole kick with integrated strengths `knl`/`ksl` (`knl[i] = K_{i-1} L`),
MAD-X's MULTIPOLE. See `element_help(:thin_multipole)` for the parameter
schema.
"""
ThinMultipoleSpec

"""
Friendly constructor for `ElementSpec{:thin_dipole}`: a zero-length dipole
kick of integrated field strength `k0l`, so `dpx = -k0l`; for a steering
corrector with the opposite sign convention use `HKickerSpec`. See
`element_help(:thin_dipole)` for the parameter schema.
"""
ThinDipoleSpec

"""
Friendly constructor for `ElementSpec{:thin_quadrupole}`: the thin-lens
quadrupole with integrated strength `k1l`, focal length `1/k1l`. See
`element_help(:thin_quadrupole)` for the parameter schema.
"""
ThinQuadrupoleSpec

"""
Friendly constructor for `ElementSpec{:thin_sextupole}`: the thin-lens
sextupole with integrated strength `k2l`, the workhorse of chromaticity
correction. See `element_help(:thin_sextupole)` for the parameter schema.
"""
ThinSextupoleSpec

for (kind, ctor) in ((:marker, :MarkerSpec), (:hkicker, :HKickerSpec),
                     (:vkicker, :VKickerSpec), (:kicker, :KickerSpec))
    @eval begin
        abstract type $ctor end
        $ctor(; kwargs...) = ElementSpec{$(QuoteNode(kind))}(_spec_params(; kwargs...))
    end
end

"""
Friendly constructor for `ElementSpec{:marker}`: the identity map, kept as a
real element so a lattice can name a position. See `element_help(:marker)` for
the parameter schema.
"""
MarkerSpec

"""
Friendly constructor for `ElementSpec{:hkicker}`: a zero-length horizontal
steering corrector, `dpx = +hkick` -- the steering sign convention, opposite a
`ThinDipoleSpec` field of the same strength. See `element_help(:hkicker)` for
the parameter schema.
"""
HKickerSpec

"""
Friendly constructor for `ElementSpec{:vkicker}`: a zero-length vertical
steering corrector, `dpy = +vkick`. See `element_help(:vkicker)` for the
parameter schema.
"""
VKickerSpec

"""
Friendly constructor for `ElementSpec{:kicker}`: a zero-length combined
steering corrector, `dpx = +hkick` and `dpy = +vkick`. See
`element_help(:kicker)` for the parameter schema.
"""
KickerSpec

const _THIN_COMMON = (
    knl=ParamMeta(default=(), meaning="integrated normal strengths; index i holds K_{i-1} L, so knl[2] is K1 L. Integrated, not the thick kn: a thin element is the L -> 0 limit at fixed K L"),
    ksl=ParamMeta(default=(), meaning="skew partners of knl"),
    x_offset=ParamMeta(default=0, meaning="misalignment: horizontal displacement of the element"),
    y_offset=ParamMeta(default=0, meaning="misalignment: vertical displacement"),
    z_offset=ParamMeta(default=0, unit="m", meaning="longitudinal placement offset: the kick is applied after a drift of z_offset and undone by the matching negative drift, so it DOES move the transverse coordinates a thin kick is evaluated at (measured dx = 5.0e-6 at z_offset = 1e-2; 2026-08-05 audit, U11-10)"),
    x_pitch=ParamMeta(default=0, meaning="misalignment: rotation about the y axis, in radians"),
    y_pitch=ParamMeta(default=0, meaning="misalignment: rotation about the x axis, in radians"),
    tilt=ParamMeta(default=0, meaning="misalignment: roll about the longitudinal axis, in radians. Geometric, and distinct from building a skew element through ksl"),
    misalign_convention=ParamMeta(default=:bmad, meaning="which code's misalignment convention to follow, :bmad or :madx. At zero length the reference point cannot matter, so the two differ only in the order the rotations compose"),
    tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
)

@element_spec begin
    kind = :marker
    spec_type = ElementSpec{:marker}
    friendly_constructor = MarkerSpec
    runtime_type = Marker
    description = "Zero-length placeholder: the identity map, used to name a position in a lattice."
    keywords = [:thin_element, :placeholder]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        tracking_method=_THIN_COMMON.tracking_method,
        _PLACEMENT_PARAMS...,
    )
    example = MarkerSpec()
    construction_help = "Friendly constructor: MarkerSpec(; tracking_method=Symplectic6DMap()). Takes no physics parameters, because it has none: the map is the identity. Use it to name an interaction point, a survey reference, or a place a diagnostic will live. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end

@element_spec begin
    kind = :thin_multipole
    spec_type = ElementSpec{:thin_multipole}
    friendly_constructor = ThinMultipoleSpec
    runtime_type = ThinMultipole
    description = "Zero-length multipole kick with integrated strengths."
    keywords = [:lattice_magnet, :thin_element, :nonlinear_interaction]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        knl=_THIN_COMMON.knl,
        ksl=_THIN_COMMON.ksl,
        k0l=ParamMeta(default=0, meaning="integrated dipole strength K0 L; folded into knl[1]"),
        k0sl=ParamMeta(default=0, meaning="skew partner of k0l"),
        k1l=ParamMeta(default=0, meaning="integrated quadrupole strength K1 L; folded into knl[2]"),
        k1sl=ParamMeta(default=0, meaning="skew partner of k1l"),
        k2l=ParamMeta(default=0, meaning="integrated sextupole strength K2 L; folded into knl[3]"),
        k2sl=ParamMeta(default=0, meaning="skew partner of k2l"),
        k3l=ParamMeta(default=0, meaning="integrated octupole strength K3 L; folded into knl[4]"),
        k3sl=ParamMeta(default=0, meaning="skew partner of k3l"),
        k4l=ParamMeta(default=0, meaning="integrated decapole strength K4 L; folded into knl[5]"),
        k4sl=ParamMeta(default=0, meaning="skew partner of k4l"),
        k5l=ParamMeta(default=0, meaning="integrated dodecapole strength K5 L; folded into knl[6]"),
        k5sl=ParamMeta(default=0, meaning="skew partner of k5l"),
        x_offset=_THIN_COMMON.x_offset,
        y_offset=_THIN_COMMON.y_offset,
        z_offset=_THIN_COMMON.z_offset,
        x_pitch=_THIN_COMMON.x_pitch,
        y_pitch=_THIN_COMMON.y_pitch,
        tilt=_THIN_COMMON.tilt,
        misalign_convention=_THIN_COMMON.misalign_convention,
        tracking_method=_THIN_COMMON.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
    )
    example = ThinMultipoleSpec(k1l=0.05, k2l=1.2)
    construction_help = "Friendly constructor: ThinMultipoleSpec(; knl=(), ksl=(), k0l=0, k0sl=0, k1l=0, k1sl=0, k2l=0, k2sl=0, k3l=0, k3sl=0, k4l=0, k4sl=0, k5l=0, k5sl=0, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). Strengths are integrated: knl[i] is K_{i-1} L. This is MAD-X's MULTIPOLE. For a steering kick use HKickerSpec/VKickerSpec/KickerSpec, whose sign convention is the opposite one. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end

@element_spec begin
    kind = :thin_dipole
    spec_type = ElementSpec{:thin_dipole}
    friendly_constructor = ThinDipoleSpec
    runtime_type = ThinMultipole
    description = "Zero-length dipole kick of integrated strength K0 L."
    keywords = [:lattice_magnet, :thin_element]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        k0l=ParamMeta(default=0, meaning="integrated dipole strength K0 L; folded into knl[1]. Gives dpx = -K0 L, the field convention, not the corrector one"),
        k0sl=ParamMeta(default=0, meaning="skew partner of k0l, giving dpy = +Ks0 L"),
        knl=_THIN_COMMON.knl,
        ksl=_THIN_COMMON.ksl,
        x_offset=_THIN_COMMON.x_offset,
        y_offset=_THIN_COMMON.y_offset,
        z_offset=_THIN_COMMON.z_offset,
        x_pitch=_THIN_COMMON.x_pitch,
        y_pitch=_THIN_COMMON.y_pitch,
        tilt=_THIN_COMMON.tilt,
        misalign_convention=_THIN_COMMON.misalign_convention,
        tracking_method=_THIN_COMMON.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
    )
    example = ThinDipoleSpec(k0l=1.0e-3)
    construction_help = "Friendly constructor: ThinDipoleSpec(; k0l=0, k0sl=0, knl=(), ksl=(), x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). A field, so dpx = -k0l. For a steering corrector, whose sign is the other way, use HKickerSpec. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end

@element_spec begin
    kind = :thin_quadrupole
    spec_type = ElementSpec{:thin_quadrupole}
    friendly_constructor = ThinQuadrupoleSpec
    runtime_type = ThinMultipole
    description = "Zero-length quadrupole kick of integrated strength K1 L."
    keywords = [:lattice_magnet, :thin_element]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        k1l=ParamMeta(default=0, meaning="integrated quadrupole strength K1 L; folded into knl[2]"),
        k1sl=ParamMeta(default=0, meaning="skew partner of k1l"),
        knl=_THIN_COMMON.knl,
        ksl=_THIN_COMMON.ksl,
        x_offset=_THIN_COMMON.x_offset,
        y_offset=_THIN_COMMON.y_offset,
        z_offset=_THIN_COMMON.z_offset,
        x_pitch=_THIN_COMMON.x_pitch,
        y_pitch=_THIN_COMMON.y_pitch,
        tilt=_THIN_COMMON.tilt,
        misalign_convention=_THIN_COMMON.misalign_convention,
        tracking_method=_THIN_COMMON.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
    )
    example = ThinQuadrupoleSpec(k1l=0.05)
    construction_help = "Friendly constructor: ThinQuadrupoleSpec(; k1l=0, k1sl=0, knl=(), ksl=(), x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The thin-lens quadrupole, focal length 1/k1l. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end

@element_spec begin
    kind = :thin_sextupole
    spec_type = ElementSpec{:thin_sextupole}
    friendly_constructor = ThinSextupoleSpec
    runtime_type = ThinMultipole
    description = "Zero-length sextupole kick of integrated strength K2 L."
    keywords = [:lattice_magnet, :thin_element, :nonlinear_interaction]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        k2l=ParamMeta(default=0, meaning="integrated sextupole strength K2 L; folded into knl[3]"),
        k2sl=ParamMeta(default=0, meaning="skew partner of k2l"),
        knl=_THIN_COMMON.knl,
        ksl=_THIN_COMMON.ksl,
        x_offset=_THIN_COMMON.x_offset,
        y_offset=_THIN_COMMON.y_offset,
        z_offset=_THIN_COMMON.z_offset,
        x_pitch=_THIN_COMMON.x_pitch,
        y_pitch=_THIN_COMMON.y_pitch,
        tilt=_THIN_COMMON.tilt,
        misalign_convention=_THIN_COMMON.misalign_convention,
        tracking_method=_THIN_COMMON.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
    )
    example = ThinSextupoleSpec(k2l=1.2)
    construction_help = "Friendly constructor: ThinSextupoleSpec(; k2l=0, k2sl=0, knl=(), ksl=(), x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The thin-lens sextupole used for chromaticity correction. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end

@element_spec begin
    kind = :hkicker
    spec_type = ElementSpec{:hkicker}
    friendly_constructor = HKickerSpec
    runtime_type = ThinMultipole
    description = "Zero-length horizontal steering corrector."
    keywords = [:lattice_magnet, :thin_element]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        hkick=ParamMeta(default=0, meaning="horizontal steering kick, dpx = +hkick. This is the corrector sign convention, opposite to a dipole field of the same magnitude"),
        x_offset=_THIN_COMMON.x_offset,
        y_offset=_THIN_COMMON.y_offset,
        z_offset=_THIN_COMMON.z_offset,
        x_pitch=_THIN_COMMON.x_pitch,
        y_pitch=_THIN_COMMON.y_pitch,
        tilt=_THIN_COMMON.tilt,
        misalign_convention=_THIN_COMMON.misalign_convention,
        tracking_method=_THIN_COMMON.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
    )
    example = HKickerSpec(hkick=1.0e-4)
    construction_help = "Friendly constructor: HKickerSpec(; hkick=0, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). dpx = +hkick, the steering convention; a ThinDipoleSpec of strength k0l gives dpx = -k0l instead. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end

@element_spec begin
    kind = :vkicker
    spec_type = ElementSpec{:vkicker}
    friendly_constructor = VKickerSpec
    runtime_type = ThinMultipole
    description = "Zero-length vertical steering corrector."
    keywords = [:lattice_magnet, :thin_element]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        vkick=ParamMeta(default=0, meaning="vertical steering kick, dpy = +vkick"),
        x_offset=_THIN_COMMON.x_offset,
        y_offset=_THIN_COMMON.y_offset,
        z_offset=_THIN_COMMON.z_offset,
        x_pitch=_THIN_COMMON.x_pitch,
        y_pitch=_THIN_COMMON.y_pitch,
        tilt=_THIN_COMMON.tilt,
        misalign_convention=_THIN_COMMON.misalign_convention,
        tracking_method=_THIN_COMMON.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
    )
    example = VKickerSpec(vkick=1.0e-4)
    construction_help = "Friendly constructor: VKickerSpec(; vkick=0, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). dpy = +vkick. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end

@element_spec begin
    kind = :kicker
    spec_type = ElementSpec{:kicker}
    friendly_constructor = KickerSpec
    runtime_type = ThinMultipole
    description = "Zero-length steering corrector acting in both planes."
    keywords = [:lattice_magnet, :thin_element]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        hkick=ParamMeta(default=0, meaning="horizontal steering kick, dpx = +hkick"),
        vkick=ParamMeta(default=0, meaning="vertical steering kick, dpy = +vkick"),
        x_offset=_THIN_COMMON.x_offset,
        y_offset=_THIN_COMMON.y_offset,
        z_offset=_THIN_COMMON.z_offset,
        x_pitch=_THIN_COMMON.x_pitch,
        y_pitch=_THIN_COMMON.y_pitch,
        tilt=_THIN_COMMON.tilt,
        misalign_convention=_THIN_COMMON.misalign_convention,
        tracking_method=_THIN_COMMON.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
    )
    example = KickerSpec(hkick=1.0e-4, vkick=-5.0e-5)
    construction_help = "Friendly constructor: KickerSpec(; hkick=0, vkick=0, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). dpx = +hkick and dpy = +vkick. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx)."
end
