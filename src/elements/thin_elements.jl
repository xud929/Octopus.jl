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
struct ThinMultipole{M<:AbstractTrackingMethod,T<:AbstractFloat,N,MIS} <: AbstractTrackOp
    method::M
    knl::NTuple{N,T}
    ksl::NTuple{N,T}
    hkick::T
    vkick::T
    qin::NTuple{9,T}; oin::NTuple{3,T}
    qout::NTuple{9,T}; oout::NTuple{3,T}
end

@inline function track_particle(::Symplectic6DMap, elem::ThinMultipole{M,T,N,MIS},
                                x, px, y, py, z, pz) where {M,T,N,MIS}
    # Same structure as a thick magnet: the misalignment wraps the map. `MIS` is
    # a type parameter, so an aligned element compiles to exactly the kick.
    if MIS
        x, px, y, py, z, pz = _frame_change(elem.qin, elem.oin, x, px, y, py, z, pz)
    end
    x, px, y, py, z, pz =
        _lattice_kick(elem.knl, elem.ksl, zero(T), one(T), x, px, y, py, z, pz)
    px += elem.hkick
    py += elem.vkick
    if MIS
        x, px, y, py, z, pz = _frame_change(elem.qout, elem.oout, x, px, y, py, z, pz)
    end
    return x, px, y, py, z, pz
end

@inline (elem::ThinMultipole)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

function ThinMultipole(spec::ElementSpec,
                       method::AbstractTrackingMethod=tracking_method(spec))
    T = Float64
    knraw = collect(T, getparam(spec, :knl, ()))
    ksraw = collect(T, getparam(spec, :ksl, ()))
    knl, ksl = _strength_tuples(T, knraw, ksraw)
    dx = T(getparam(spec, :x_offset, zero(T)))
    dy = T(getparam(spec, :y_offset, zero(T)))
    dz = T(getparam(spec, :z_offset, zero(T)))
    xp = T(getparam(spec, :x_pitch, zero(T)))
    yp = T(getparam(spec, :y_pitch, zero(T)))
    tl = T(getparam(spec, :tilt, zero(T)))
    mis = !(dx == 0 && dy == 0 && dz == 0 && xp == 0 && yp == 0 && tl == 0)
    conv = Symbol(getparam(spec, :misalign_convention, :bmad))
    conv in (:bmad, :madx) || throw(ArgumentError(
        "misalign_convention must be :bmad or :madx; got $(repr(conv))"))
    ident = (one(T), zero(T), zero(T), zero(T), one(T), zero(T),
             zero(T), zero(T), one(T))
    zero3 = (zero(T), zero(T), zero(T))
    # At zero length the entrance, centre and exit coincide, so the reference
    # point cannot matter and the two conventions differ only in the order the
    # rotations compose. The frames still come from `_misalign_frames`, so a
    # thin element and a thick one cannot drift apart in convention.
    qin, oin, qout, oout = mis ?
        _misalign_frames(T, _misalign_matrix(T, xp, yp, tl, conv === :madx),
                         (dx, dy, dz), zero(T), zero(T), zero(T)) :
        (ident, zero3, ident, zero3)
    return ThinMultipole{typeof(method),T,length(knl),mis}(
        method, knl, ksl,
        T(getparam(spec, :hkick, zero(T))), T(getparam(spec, :vkick, zero(T))),
        qin, oin, qout, oout)
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

for (kind, ctor) in ((:marker, :MarkerSpec), (:hkicker, :HKickerSpec),
                     (:vkicker, :VKickerSpec), (:kicker, :KickerSpec))
    @eval begin
        abstract type $ctor end
        $ctor(; kwargs...) = ElementSpec{$(QuoteNode(kind))}(_spec_params(; kwargs...))
    end
end

const _THIN_COMMON = (
    knl=ParamMeta(default=(), meaning="integrated normal strengths; index i holds K_{i-1} L, so knl[2] is K1 L. Integrated, not the thick kn: a thin element is the L -> 0 limit at fixed K L"),
    ksl=ParamMeta(default=(), meaning="skew partners of knl"),
    x_offset=ParamMeta(default=0, meaning="misalignment: horizontal displacement of the element"),
    y_offset=ParamMeta(default=0, meaning="misalignment: vertical displacement"),
    z_offset=ParamMeta(default=0, meaning="misalignment: longitudinal displacement. At zero length this is a pure drift of the kick location and has no effect on the transverse map"),
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
    )
    example = MarkerSpec()
    construction_help = "Friendly constructor: MarkerSpec(; tracking_method=Symplectic6DMap()). Takes no physics parameters, because it has none: the map is the identity. Use it to name an interaction point, a survey reference, or a place a diagnostic will live."
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
    )
    example = ThinMultipoleSpec(k1l=0.05, k2l=1.2)
    construction_help = "Friendly constructor: ThinMultipoleSpec(; knl=(), ksl=(), k0l=0, k0sl=0, k1l=0, k1sl=0, k2l=0, k2sl=0, k3l=0, k3sl=0, k4l=0, k4sl=0, k5l=0, k5sl=0, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). Strengths are integrated: knl[i] is K_{i-1} L. This is MAD-X's MULTIPOLE. For a steering kick use HKickerSpec/VKickerSpec/KickerSpec, whose sign convention is the opposite one."
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
    )
    example = ThinDipoleSpec(k0l=1.0e-3)
    construction_help = "Friendly constructor: ThinDipoleSpec(; k0l=0, k0sl=0, knl=(), ksl=(), x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). A field, so dpx = -k0l. For a steering corrector, whose sign is the other way, use HKickerSpec."
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
    )
    example = ThinQuadrupoleSpec(k1l=0.05)
    construction_help = "Friendly constructor: ThinQuadrupoleSpec(; k1l=0, k1sl=0, knl=(), ksl=(), x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The thin-lens quadrupole, focal length 1/k1l."
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
    )
    example = ThinSextupoleSpec(k2l=1.2)
    construction_help = "Friendly constructor: ThinSextupoleSpec(; k2l=0, k2sl=0, knl=(), ksl=(), x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The thin-lens sextupole used for chromaticity correction."
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
    )
    example = HKickerSpec(hkick=1.0e-4)
    construction_help = "Friendly constructor: HKickerSpec(; hkick=0, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). dpx = +hkick, the steering convention; a ThinDipoleSpec of strength k0l gives dpx = -k0l instead."
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
    )
    example = VKickerSpec(vkick=1.0e-4)
    construction_help = "Friendly constructor: VKickerSpec(; vkick=0, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). dpy = +vkick."
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
    )
    example = KickerSpec(hkick=1.0e-4, vkick=-5.0e-5)
    construction_help = "Friendly constructor: KickerSpec(; hkick=0, vkick=0, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). dpx = +hkick and dpy = +vkick."
end
