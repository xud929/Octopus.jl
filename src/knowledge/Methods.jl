export Symplectic6DMap, NonSymplectic6DMap, Damping6DMap, Diffusion6DMap, Radiation6DMap,
       WeakStrongBeamBeamMap, default_method

"""
    Symplectic6DMap

Closed-form six-dimensional symplectic coordinate transformation. This method
tag is used for thin coordinate transforms and kicks that preserve the
six-dimensional canonical structure.
"""
struct Symplectic6DMap <: AbstractTrackingMethod end

"""
    NonSymplectic6DMap

Closed-form deterministic six-dimensional map that is not canonical in the
accelerator coordinates being tracked. This method tag is used for exact
coordinate transformations whose Jacobian does not satisfy `J' * S * J == S`.
It is distinct from damping, diffusion, and radiation methods.
"""
struct NonSymplectic6DMap <: AbstractTrackingMethod end

"""
    Damping6DMap

Closed-form six-dimensional damping map. This method tag is used for radiation
or other dissipative transforms that intentionally do not preserve the
six-dimensional symplectic structure.
"""
struct Damping6DMap <: AbstractTrackingMethod end

"""
    Diffusion6DMap

Closed-form six-dimensional stochastic diffusion map. This method tag is used
for radiation-like excitation without damping.
"""
struct Diffusion6DMap <: AbstractTrackingMethod end

"""
    Radiation6DMap

Closed-form six-dimensional radiation damping and diffusion map. This method
tag is used for lumped radiation elements that may apply both damping and
stochastic excitation.
"""
struct Radiation6DMap <: AbstractTrackingMethod end

"""
    WeakStrongBeamBeamMap

Particle-level weak-strong beam-beam interaction map.
"""
struct WeakStrongBeamBeamMap <: AbstractTrackingMethod end

"""
    default_method(spec)

Return the preferred tracking method object for an element spec: the kind's
own override where it has one (the eight kinds whose methods exclude
`Symplectic6DMap`), else `Symplectic6DMap()`.

A registered kind that declares NO tracking method (`tracking_methods =
DataType[]`: the composite `:line`, whose placements each compile with their
own) is refused by name rather than answered with a method it denies.
`compile_runtime(spec, Symplectic6DMap())` refuses the same request on such a
kind, and the registry's two answers must agree; until the 2026-10-20 fix batch
this returned `Symplectic6DMap()` for the line (2026-10-18 comprehensive audit,
F-174). Derived from the declaration, so a future method-less kind needs no
override of its own; `validate_element_metadata` holds every kind to it.
"""
function default_method(T::Type{<:AbstractElementSpec})
    meta = _element_meta_or_nothing(T)
    if meta !== nothing && isempty(meta.tracking_methods)
        throw(ArgumentError(
            "element kind $(repr(meta.kind)) declares no tracking method of its own " *
            "(supported_tracking_methods is empty): a composite compiles each placement " *
            "with that placement's tracking_method, so there is no method to answer. " *
            "Set tracking_method on the placements instead."))
    end
    return Symplectic6DMap()
end
default_method(spec::AbstractElementSpec) = default_method(typeof(spec))

description(::Type{Symplectic6DMap}) =
    "Closed-form six-dimensional symplectic coordinate transformation."
description(::Type{NonSymplectic6DMap}) =
    "Closed-form deterministic six-dimensional non-canonical coordinate transformation."
description(::Type{Damping6DMap}) =
    "Closed-form six-dimensional dissipative damping transformation."
description(::Type{Diffusion6DMap}) =
    "Closed-form six-dimensional stochastic diffusion transformation."
description(::Type{Radiation6DMap}) =
    "Closed-form six-dimensional radiation damping and stochastic diffusion transformation."
description(::Type{WeakStrongBeamBeamMap}) =
    "Particle-level weak-strong beam-beam interaction map."
