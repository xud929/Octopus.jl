export Symplectic6DMap, Damping6DMap, Diffusion6DMap, Radiation6DMap,
       WeakStrongBeamBeamMap, default_method

"""
    Symplectic6DMap

Closed-form six-dimensional symplectic coordinate transformation. This method
tag is used for thin coordinate transforms and kicks that preserve the
six-dimensional canonical structure.
"""
struct Symplectic6DMap <: AbstractTrackingMethod end

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

Return the preferred tracking method object for an element spec.
"""
default_method(::Type{<:AbstractElementSpec}) = Symplectic6DMap()
default_method(spec::AbstractElementSpec) = default_method(typeof(spec))

description(::Type{Symplectic6DMap}) =
    "Closed-form six-dimensional symplectic coordinate transformation."
description(::Type{Damping6DMap}) =
    "Closed-form six-dimensional dissipative damping transformation."
description(::Type{Diffusion6DMap}) =
    "Closed-form six-dimensional stochastic diffusion transformation."
description(::Type{Radiation6DMap}) =
    "Closed-form six-dimensional radiation damping and stochastic diffusion transformation."
description(::Type{WeakStrongBeamBeamMap}) =
    "Particle-level weak-strong beam-beam interaction map."
