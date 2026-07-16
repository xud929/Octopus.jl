export faddeeva_w, faddeeva_w_approx, faddeeva_w_approx_reim,
       faddeeva_w_upper_reim, inverse_erf

using SpecialFunctions: erfcx, erfinv

"""
    faddeeva_w(z)

Return the Faddeeva function `w(z) = exp(-z^2) * erfc(-im*z)`.

This CPU path uses the complex-scaled complementary error function from
`SpecialFunctions.jl`.
"""
@inline faddeeva_w(z) = erfcx(-im * z)

const FADDEEVA_WEIDEMAN_L = 4.756828460010884
const FADDEEVA_WEIDEMAN_INVSQRTPI = 0.56418958354775628695
const FADDEEVA_WEIDEMAN_COEFFS = (
    -1.3025521217935973e-12,
    3.741291998426988e-12,
    8.027224718265558e-12,
    -2.1544363515424436e-11,
    -5.54421994425347e-11,
    1.165792323787329e-10,
    4.153751717583809e-10,
    -5.231007640937868e-10,
    -3.208014326405717e-9,
    8.124811240461938e-10,
    2.3797553774795865e-8,
    2.293044236434394e-8,
    -1.4813078923203715e-7,
    -4.184076397434344e-7,
    4.255833137983833e-7,
    4.401531732076136e-6,
    6.821031943091138e-6,
    -2.1409619205520203e-5,
    -0.00013075449254951188,
    -0.0002453298026994233,
    0.00039259136069880185,
    0.0045195411053458034,
    0.019006155784844825,
    0.05730440352983683,
    0.14060716226893633,
    0.2954445107150855,
    0.5460139720639329,
    0.9019254893647994,
    1.3455441692345438,
    1.8256696296324815,
    2.2635372999002663,
    2.5722534081245687,
)

"""
    faddeeva_w_approx_reim(zr, zi)

Return `(real(w), imag(w))` for the Faddeeva function using a fixed-order
Weideman rational approximation. This path uses scalar arithmetic only and is
intended for CUDA kernels.
"""
@inline function faddeeva_w_approx_reim(zr::T, zi::T) where {T<:AbstractFloat}
    if zi < zero(T)
        wr, wi = faddeeva_w_upper_reim(-zr, -zi)
        er, ei = _cexp_reim(-zr * zr + zi * zi, -2 * zr * zi)
        return 2 * er - wr, 2 * ei - wi
    end
    return faddeeva_w_upper_reim(zr, zi)
end

"""
    faddeeva_w_upper_reim(zr, zi)

Branch-light Faddeeva `w(z)` approximation for `imag(z) >= 0`, returned as
`(real(w), imag(w))`. This is the CUDA beam-beam hot path: Bassetti-Erskine
calls only upper-half-plane arguments after taking absolute transverse
coordinates.
"""
@inline function faddeeva_w_upper_reim(zr::T, zi::T) where {T<:AbstractFloat}
    x = abs(zr)
    y = zi

    if y > T(7) || (x > T(6) && (y > T(0.1) || (x > T(8) && y > T(1e-10)) || x > T(28)))
        return _faddeeva_w_cf_reim(zr, y)
    end

    L = T(FADDEEVA_WEIDEMAN_L)
    denr = L + zi
    deni = -zr
    numr = L - zi
    numi = zr
    zrZ, ziZ = _cdiv_reim(numr, numi, denr, deni)

    pr = zero(T)
    pi = zero(T)
    for c in FADDEEVA_WEIDEMAN_COEFFS
        pr, pi = _cmul_reim(pr, pi, zrZ, ziZ)
        pr += T(c)
    end

    den2r, den2i = _cmul_reim(denr, deni, denr, deni)
    tr, ti = _cdiv_reim(2 * pr, 2 * pi, den2r, den2i)
    ir, ii = _cdiv_reim(T(FADDEEVA_WEIDEMAN_INVSQRTPI), zero(T), denr, deni)
    return tr + ir, ti + ii
end

@inline function _faddeeva_w_cf_reim(zr::T, zi::T) where {T<:AbstractFloat}
    ispi = T(FADDEEVA_WEIDEMAN_INVSQRTPI)
    x = abs(zr)
    y = zi
    xs = zr
    if x + y > T(4000)
        if x + y > T(1e7)
            if x > y
                yax = y / xs
                denom = ispi / (xs + yax * y)
                return denom * yax, denom
            else
                xya = xs / y
                denom = ispi / (xya * xs + y)
                return denom, denom * xya
            end
        else
            dr = xs * xs - y * y - T(0.5)
            di = 2 * xs * y
            denom = ispi / (dr * dr + di * di)
            return denom * (xs * di - y * dr), denom * (xs * dr + y * di)
        end
    end

    c0, c1, c2, c3, c4 = T(3.9), T(11.398), T(0.08254), T(0.1421), T(0.2023)
    nu = floor(c0 + c1 / (c2 * x + c3 * y + c4))
    wr = xs
    wi = y
    nu = T(0.5) * (nu - one(T))
    while nu > T(0.4)
        invden = nu / (wr * wr + wi * wi)
        wr, wi = xs - wr * invden, y + wi * invden
        nu -= T(0.5)
    end
    invden = ispi / (wr * wr + wi * wi)
    return invden * wi, invden * wr
end

@inline faddeeva_w_approx(z::Complex{T}) where {T<:AbstractFloat} =
    complex(faddeeva_w_approx_reim(real(z), imag(z))...)

@inline function _cmul_reim(ar, ai, br, bi)
    return ar * br - ai * bi, ar * bi + ai * br
end

@inline function _cdiv_reim(ar, ai, br, bi)
    invden = inv(br * br + bi * bi)
    return (ar * br + ai * bi) * invden, (ai * br - ar * bi) * invden
end

@inline function _cexp_reim(ar, ai)
    e = exp(ar)
    return e * cos(ai), e * sin(ai)
end

"""Return the inverse error function using `SpecialFunctions.erfinv`."""
@inline inverse_erf(x) = erfinv(x)
