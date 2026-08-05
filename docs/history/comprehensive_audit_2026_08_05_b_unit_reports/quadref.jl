# Independent reference for the Bassetti-Erskine kick of a 2D Gaussian charge.
#
# DERIVATION (from the Coulomb Green's function, NOT from the code or the
# theory note):
#   The 2D Coulomb kernel satisfies  2u/|u|^2 = int_0^inf dt (u/t^2) exp(-|u|^2/(2t)).
#   Convolving with a Gaussian of covariance Sigma = diag(sx^2, sy^2) and using
#   exp(-|u|^2/2t) = 2*pi*t*G_{tI}(u),  (x-x')G_{tI}(x-x') = -t grad_x G_{tI}(x-x'),
#   and G_Sigma * G_{tI} = G_{Sigma + tI} gives
#       K(x) = -2 pi int_0^inf dt grad G_{Sigma + t I}(x),
#   i.e.
#       Kx = x int_0^inf dt E(t) / (sx^2+t)^{3/2} (sy^2+t)^{1/2}
#       Ky = y int_0^inf dt E(t) / (sx^2+t)^{1/2} (sy^2+t)^{3/2}
#       E(t) = exp(-x^2/(2(sx^2+t)) - y^2/(2(sy^2+t)))
#   Normalization check (sx=sy=s): Kx = 2x(1-exp(-r^2/2s^2))/r^2, the repository's
#   convention.
#
#   Finite-interval form with u = s2^2/(s2^2+t) in (0,1], Delta = s1^2 - s2^2 >= 0,
#   s1 >= s2:
#       Kx      =  x*s2   int_0^1 du E / (s2^2+u*Delta)^{3/2}
#       Ky      =  (y/s2) int_0^1 du E / (s2^2+u*Delta)^{1/2}
#       dKx/dx  =  s2     int_0^1 du E (1 - x^2 u/(s2^2+u*Delta)) / (s2^2+u*Delta)^{3/2}
#       dKy/dy  =  (1/s2) int_0^1 du E (1 - y^2 u/s2^2)           / (s2^2+u*Delta)^{1/2}
#       L/D = (Kx*y - Ky*x)/Delta = -(x*y/s2) int_0^1 du E u/(s2^2+u*Delta)^{3/2}
#         (algebraically cancellation-free, so it is also the Delta -> 0 limit)
#       E = exp(-x^2 u/(2(s2^2+u*Delta)) - y^2 u/(2*s2^2))

using LinearAlgebra

# Gauss-Legendre nodes/weights on [-1,1] by Golub-Welsch (BigFloat-safe input,
# Float64 eigensolve is plenty for n<=40).
function gauss_legendre(n::Int)
    b = [k / sqrt(4.0 * k * k - 1.0) for k in 1:(n - 1)]
    J = SymTridiagonal(zeros(n), b)
    e = eigen(J)
    return e.values, 2 .* abs2.(e.vectors[1, :])
end

const _GLN, _GLW = gauss_legendre(32)

"Composite Gauss-Legendre of f on [0,1] with `panels` panels, in type T."
function cgl(f, panels::Int, ::Type{T}=BigFloat) where {T}
    total = zero(T)
    h = one(T) / T(panels)
    for p in 0:(panels - 1)
        a = T(p) * h
        c = a + h / 2
        s = zero(T)
        for k in eachindex(_GLN)
            s += T(_GLW[k]) * f(c + (h / 2) * T(_GLN[k]))
        end
        total += s * h / 2
    end
    return total
end

"""
    be_reference(sigx, sigy, x, y; panels=400, T=BigFloat)

Return `(Kx, Ky, dKxdx, dKydy, L_over_D)` for the normalized Bassetti-Erskine
kick.  `L_over_D = (Kx*y - Ky*x)/(sigx^2 - sigy^2)` evaluated in its
cancellation-free integral form (finite for sigx == sigy).
"""
function be_reference(sigx, sigy, x, y; panels::Int=400, T::Type=BigFloat)
    swap = sigx < sigy
    s1 = T(swap ? sigy : sigx); s2 = T(swap ? sigx : sigy)
    X = T(swap ? y : x);        Y = T(swap ? x : y)
    d = s1 * s1 - s2 * s2
    s22 = s2 * s2
    E(u) = exp(-X * X * u / (2 * (s22 + u * d)) - Y * Y * u / (2 * s22))
    Kx = X * s2 * cgl(u -> E(u) / (s22 + u * d)^T(1.5), panels, T)
    Ky = (Y / s2) * cgl(u -> E(u) / sqrt(s22 + u * d), panels, T)
    dKx = s2 * cgl(u -> E(u) * (1 - X * X * u / (s22 + u * d)) / (s22 + u * d)^T(1.5), panels, T)
    dKy = (1 / s2) * cgl(u -> E(u) * (1 - Y * Y * u / s22) / sqrt(s22 + u * d), panels, T)
    LD = -(X * Y / s2) * cgl(u -> E(u) * u / (s22 + u * d)^T(1.5), panels, T)
    # Undo the swap: the swap exchanges the roles of x and y, and (Kx*y-Ky*x)
    # changes sign together with D = sigx^2 - sigy^2, so L/D is invariant.
    return swap ? (Ky, Kx, dKy, dKx, LD) : (Kx, Ky, dKx, dKy, LD)
end
