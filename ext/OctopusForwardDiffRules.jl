# Shared ForwardDiff derivative rules for Octopus — included by BOTH the
# OctopusForwardDiffExt package extension (package mode) and the script-mode
# activation at the bottom of src/Octopus.jl. Inside the Octopus module the
# name `Octopus` is the module itself, so the qualified names below resolve
# identically on both routes, and one shared file means neither route can
# drift from the other (the overwrite/drift trap of audit part 6 §8.7).
#
# Why these exist (2026-08-05 audit open-queue, U7-1): the elliptical (η≠0)
# Bassetti-Erskine kick was un-differentiable — the near-round precision
# calibration rejected dual number types outright, and the exact CPU Faddeeva
# route has no dual method in SpecialFunctions. The remaining near-round and
# Weideman arithmetic is dual-generic on its own.

# Precision calibration passes through to the dual's VALUE type: taking a
# derivative does not change which floating-point grid the evaluation runs
# on, so the calibrated factor is the value type's.
Octopus._near_round_conditioning_factor(::Type{ForwardDiff.Dual{T,V,N}}) where {T,V,N} =
    Octopus._near_round_conditioning_factor(V)

# Holomorphic chain rule for the Faddeeva function: w′(z) = −2·z·w(z) + 2i/√π.
# The primal is evaluated once at the dual's value; the complex derivative is
# distributed over the partials of the real and imaginary parts.
function Octopus.faddeeva_w(z::Complex{ForwardDiff.Dual{T,V,N}}) where {T,V,N}
    zv = Complex(ForwardDiff.value(real(z)), ForwardDiff.value(imag(z)))
    w = Octopus.faddeeva_w(zv)
    dw = -2 * zv * w + Complex(zero(V), 2 / sqrt(V(pi)))
    pr = ForwardDiff.partials(real(z))
    pim = ForwardDiff.partials(imag(z))
    rep = ForwardDiff.Partials(ntuple(k -> real(dw) * pr[k] - imag(dw) * pim[k], Val(N)))
    imp = ForwardDiff.Partials(ntuple(k -> imag(dw) * pr[k] + real(dw) * pim[k], Val(N)))
    return Complex(ForwardDiff.Dual{T}(real(w), rep), ForwardDiff.Dual{T}(imag(w), imp))
end
