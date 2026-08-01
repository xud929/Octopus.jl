export DriftSpec, QuadrupoleSpec, SextupoleSpec, OctupoleSpec, MultipoleSpec,
       SBendSpec, LatticeMagnet, LATTICE_INTEGRATOR_ORDERS

"""
Supported integrator orders for `LatticeMagnet`.

`2` is Strang drift-kick-drift; `4` is the Forest-Ruth composition PTC uses for
`METHOD=4` (four drifts, three kicks, with negative second coefficients). The
coefficients are pinned to PTC's so that agreement at finite `nst` is possible
at all -- different fourth-order compositions agree only as `nst -> infinity`.
See `docs/theory/lattice_hamiltonian_and_conventions.md` Section 7.
"""
const LATTICE_INTEGRATOR_ORDERS = (2, 4)

# Forest-Ruth / Yoshida-4, a = 1 - 2^(1/3).
const _FR_A = 1 - cbrt(2.0)
const _FR_D1 = 0.5 / (1 + _FR_A)
const _FR_D2 = _FR_A * _FR_D1
const _FR_K1 = 1 / (1 + _FR_A)
const _FR_K2 = (_FR_A - 1) * _FR_K1

# Fringe selector bits. Kept as a type parameter so a magnet with fringes off
# compiles to the same straight-line code it had before they existed.
const FRINGE_NONE = 0
const FRINGE_MULTIPOLE = 1      # hard-edge multipole fringe (Forest-Milutinovic)
const FRINGE_SOFT_QUAD = 2      # soft-edge quadrupole fringe (VA, VS)
const FRINGE_DIPOLE_EDGE = 4    # pole face: rotation, curvature, wedge
const FRINGE_BEND = 8           # exact hard-edge dipole fringe (Maxwell-required)

# ---------------------------------------------------------------------------
# Small-argument-safe curvature helpers.
#
# The closed forms of Section 5 contain 1/h, which is a removable singularity:
# evaluating them near h = 0 loses five to eight digits to cancellation
# (Section 5.2). Every 1/h is therefore routed through these two functions,
# which are smooth at h = 0 by construction:
#     C1 = sin(hL)/h  -> L ,      C2 = (1 - cos(hL))/h -> 0 .
# ---------------------------------------------------------------------------
@inline function _curv_sin(h::T, L::T) where {T}
    u = h * L
    abs(u) < T(1e-4) && return L * (one(T) - u * u / 6 * (one(T) - u * u / 20))
    return sin(u) / h
end

@inline function _curv_vers(h::T, L::T) where {T}
    u = h * L
    abs(u) < T(1e-4) && return h * L * L / 2 * (one(T) - u * u / 12 * (one(T) - u * u / 30))
    return (one(T) - cos(u)) / h
end

"""
Exact drift in a frame of curvature `h`, in the `z = s - l` convention.

Both `y` and `z` follow from one shared quantity, the second from the first by
`p_y -> -(1 + p_z)` (Section 5). Written so that no `1/h` is ever formed.
"""
@inline function _lattice_drift(h::T, L::T, x, px, y, py, z, pz) where {T}
    ps0 = sqrt((1 + pz)^2 - px * px - py * py)
    if h == 0
        xn = x + px / ps0 * L
        return xn, px, y + py / ps0 * L, py, z + L - (1 + pz) / ps0 * L, pz
    end
    c, s = cos(h * L), sin(h * L)
    C1 = _curv_sin(h, L)
    C2 = _curv_vers(h, L)
    pxn = px * c + ps0 * s
    psn = -px * s + ps0 * c
    xn = (ps0 * C2 + px * C1 + x * ps0) / psn
    Δ = (-px * C2 + ps0 * C1 + xn * pxn - x * px) / ((1 + pz)^2 - py * py)
    return xn, pxn, y + py * Δ, py, z + L - (1 + pz) * Δ, pz
end

"""
Exact sector bend: frame curvature `h`, dipole strength `b0`, independent.

`h == 0` is a straight-frame bend; `b0 == 0` is a curved drift; `h == b0` is a
sector bend on its design orbit.
"""
@inline function _lattice_bend(h::T, b0::T, L::T, x, px, y, py, z, pz) where {T}
    ps0 = sqrt((1 + pz)^2 - px * px - py * py)
    w = sqrt((1 + pz)^2 - py * py)
    dpx0 = -b0 * (1 + h * x) + h * ps0
    C1 = _curv_sin(h, L)
    C2 = _curv_vers(h, L)
    c, s = cos(h * L), sin(h * L)
    pxn = px * c + dpx0 * C1
    psn = sqrt((1 + pz)^2 - pxn * pxn - py * py)
    # x - x0 written without 1/h (Section 5.2)
    xn = x + ((psn - ps0) + px * s + dpx0 * C2) / b0
    Δ = (h * L - (asin(pxn / w) - asin(px / w))) / b0
    return xn, pxn, y + py * Δ, py, z + L - (1 + pz) * Δ, pz
end

"""
Thin multipole kick of length `L`, straight frame.

`kn[i]` is `K_{i-1}` and `ks[i]` is the skew partner, i.e. index 1 is the
dipole (Section 4.1 indexing, not PTC's). From Section 4.5,

    dpx - i dpy = -L * sum_n (K_n + i Ks_n) (x + iy)^n / n!

with **no** `1/(1+pz)` factor: in the exact Hamiltonian the chromatic
dependence lives in the drift, and adding it here would double-count.
"""
@inline function _lattice_kick(kn::NTuple{N,T}, ks::NTuple{N,T}, h::T, L::T,
                               x, px, y, py, z, pz) where {N,T}
    # Real recurrence rather than Complex: keeps the kernel GPU-friendly and
    # lets the map be complex-step differentiated in tests.
    ar = zero(x); ai = zero(x)
    tr = one(x);  ti = zero(x)               # (x+iy)^n / n!
    @inbounds for n in 1:N
        ar += kn[n] * tr - ks[n] * ti
        ai += kn[n] * ti + ks[n] * tr
        tr, ti = (tr * x - ti * y) / n, (tr * y + ti * x) / n
    end
    # Section 4.5: dpx = -L (1+hx) By, dpy = +L (1+hx) Bx. Only a dipole may
    # have h != 0 on this path with a PURE DIPOLE (a combined-function magnet
    # routes to _curved_kick), and the curved dipole field is exactly K0, so the
    # factor is exact rather than truncated.
    #
    # This restriction is not cosmetic. For a non-dipole field the map above is
    # not a gradient when h != 0 -- d/dy[-(1+hx)By] and d/dx[(1+hx)Bx] differ by
    # h*Bx -- so it would not be symplectic. Routing combined-function magnets
    # through the tabulated potential is what keeps the kick a gradient.
    g = 1 + h * x
    return x, px - L * g * ar, y, py + L * g * ai, z, pz
end

"""
    _curved_potential_coeffs(T, kn, ks, h, M)

Two-dimensional Taylor coefficients of `Psi = (1+hx) a_s` in a curved frame, to
order `M`, for a combined-function magnet.

The straight expansion of Section 4.1 is not a solution when `h != 0`, so a
gradient dipole needs the curved potential. Section 4.4 derives it as an exact
recursion in the `y` order,

    Psi_{k+2}(x) = -Psi_k''(x) + h/(1+hx) Psi_k'(x)

seeded on the midplane by the field definition: `Psi_0` integrates
`dPsi/dx = -(1+hx) By(x,0)`, and `Psi_1 = (1+hx) Bx(x,0)`. Only the dipole
terminates, which is why `M` is a convergence parameter rather than a fixed
choice.

**The potential is tabulated rather than the field, deliberately.** Truncating
the field breaks the cross-derivative symmetry that makes the kick a gradient,
and the map then fails to be symplectic at the truncation level (measured
1.5e-4). Differentiating one truncated potential keeps the kick an exact
gradient at any `M`, so truncation costs accuracy but never symplecticity.

Returns a row-major flat tuple of length `(M+1)^2`, index `k*(M+1)+j+1` holding
the coefficient of `x^j y^k`.
"""
function _curved_potential_coeffs(::Type{T}, kn, ks, h, M::Int) where {T}
    np = M + 1
    Ψ = [zeros(T, np) for _ in 0:M]
    # Psi_0: integrate -(1+hx) By(x,0) with By(x,0) = sum K_n x^n/n!
    fac = one(T)
    for n in 0:(length(kn) - 1)
        n > 0 && (fac *= n)
        c = T(kn[n + 1]) / fac
        n + 1 <= M && (Ψ[1][n + 2] -= c / (n + 1))
        n + 2 <= M && (Ψ[1][n + 3] -= c * h / (n + 2))
    end
    # Psi_1 = (1+hx) Bx(x,0) with Bx(x,0) = sum Ks_n x^n/n!
    if M >= 1
        fac = one(T)
        for n in 0:(length(ks) - 1)
            n > 0 && (fac *= n)
            c = T(ks[n + 1]) / fac
            n <= M && (Ψ[2][n + 1] += c)
            n + 1 <= M && (Ψ[2][n + 2] += c * h)
        end
    end
    g = T[(-1)^j * h^(j + 1) for j in 0:M]        # series of h/(1+hx)
    derivative(p) = T[j <= np - 1 ? j * p[j + 1] : zero(T) for j in 1:np]
    function truncated_product(a, b)
        c = zeros(T, np)
        for i in 1:np, j in 1:(np - i + 1)
            c[i + j - 1] += a[i] * b[j]
        end
        return c
    end
    for k in 0:(M - 2)
        d1 = derivative(Ψ[k + 1])
        Ψ[k + 3] = -derivative(d1) .+ truncated_product(g, d1)
    end
    kfac = one(T)
    coeffs = zeros(T, np * np)
    for k in 0:M
        k > 0 && (kfac *= k)
        for j in 0:M
            coeffs[k * np + j + 1] = Ψ[k + 1][j + 1] / kfac
        end
    end
    return Tuple(coeffs)
end

"""
Multipole kick in a curved frame. Section 4.5 with `H_kick = -Psi`:

    dpx = L dPsi/dx ,      dpy = L dPsi/dy

Both derivatives are taken from the *same* tabulated polynomial, so the kick is
an exact gradient and the map is symplectic to round-off at any truncation
order.
"""
@inline function _curved_kick(ψ::NTuple{NC,T}, ::Val{M}, L::T,
                              x, px, y, py, z, pz) where {NC,T,M}
    np = M + 1
    dx = zero(x); dy = zero(x)
    ypow = one(x)          # y^k
    yprev = zero(x)        # y^(k-1)
    @inbounds for k in 0:M
        rx = zero(x); r = zero(x)
        for j in M:-1:1
            rx = rx * x + j * ψ[k * np + j + 1]
        end
        for j in M:-1:0
            r = r * x + ψ[k * np + j + 1]
        end
        dx += rx * ypow
        k >= 1 && (dy += k * r * yprev)
        yprev = ypow
        ypow *= y
    end
    return x, px + L * dx, y, py + L * dy, z, pz
end

# ---------------------------------------------------------------------------
# Fringe maps. Signs follow the z = s - l convention, i.e. every longitudinal
# update is the NEGATIVE of PTC's, whose variable is conjugate to delta with
# the opposite orientation (Sections 2.1, 5.3, 6.4).
# ---------------------------------------------------------------------------

"""
Hard-edge multipole fringe (Forest-Milutinovic), Section 6.2.

A canonical point transformation: the coordinates shift by the integrated
transverse vector potential and the momenta follow by the inverse-transpose
Jacobian, so the map is exactly symplectic rather than symplectic to an order.
`sigma` is `+1` entering the magnet and `-1` leaving it.
"""
@inline function _multipole_fringe(kn::NTuple{N,T}, ks::NTuple{N,T}, σ,
                                   x, px, y, py, z, pz) where {N,T}
    Fx = zero(x); Fy = zero(x)
    Fxx = zero(x); Fxy = zero(x); Fyx = zero(x); Fyy = zero(x)
    pr = one(x); pi_ = zero(x)               # (x+iy)^(j-1)
    invfac = one(x)                          # 1/(j-1)!
    @inbounds for j in 1:N
        # PTC's field expansion carries NO factorial: its BN(j) is
        # K_{j-1}/(j-1)!. kn[] is stored in the MAD-X convention (Section 4.1),
        # so the factorial is removed here.
        cr = kn[j] * invfac; ci = ks[j] * invfac
        invfac /= j
        qr, qi = pr, pi_                     # (x+iy)^(j-1)
        pr, pi_ = qr * x - qi * y, qr * y + qi * x   # (x+iy)^j
        f = -σ / (4 * (j + 1))
        U = f * (cr * pr - ci * pi_);  V = f * (cr * pi_ + ci * pr)
        DU = f * (cr * qr - ci * qi);  DV = f * (cr * qi + ci * qr)
        DUX = j * DU; DVX = j * DV; DUY = -j * DV; DVY = j * DU
        NF = (j + 2) / j
        Fx += U * x + NF * V * y
        Fy += U * y - NF * V * x
        Fxx += DUX * x + U + NF * y * DVX
        Fxy += DUY * x + NF * V + NF * y * DVY
        Fyx += DUX * y - NF * V - NF * x * DVX
        Fyy += DUY * y + U - NF * x * DVY
    end
    d = inv(1 + pz)
    A = 1 - Fxx * d; C = -Fxy * d
    B = -Fyx * d;    D = 1 - Fyy * d
    det = A * D - B * C
    pxn = (D * px - B * py) / det
    pyn = (A * py - C * px) / det
    return x - Fx * d, pxn, y - Fy * d, pyn, z + (pxn * Fx + pyn * Fy) * d * d, pz
end

"""
Soft-edge quadrupole fringe, Section 6.4.

`va` is the equivalent linear-ramp length (its signed square carries the sign of
the first moment `J1 = -k L^2 / 24`); `vs` carries the second moment, which
vanishes for a symmetric ramp and is therefore independent.
"""
@inline function _soft_quad_fringe(k1::T, ks1::T, va::T, vs::T, σ,
                                   x, px, y, py, z, pz) where {T}
    b = sqrt(k1 * k1 + ks1 * ks1)
    b == 0 && return x, px, y, py, z, pz
    p = 1 + pz
    f1 = -σ * va * abs(va) * b / p / 24
    f2 = vs * b / p
    α = -atan(ks1, k1) / 2
    c, s = cos(α), sin(α)
    x, y = c * x + s * y, -s * x + c * y
    px, py = c * px + s * py, -s * px + c * py
    dz = (f1 * x + f2 * (1 + f1 / 2) * px / p * exp(-f1)) * px / p -
         (f1 * y + f2 * (1 - f1 / 2) * py / p * exp(f1)) * py / p
    z -= dz
    x = x * exp(f1) + px * f2 / p
    y = y * exp(-f1) - py * f2 / p
    px *= exp(-f1)
    py *= exp(f1)
    x, y = c * x - s * y, s * x + c * y
    px, py = c * px - s * py, s * px + c * py
    return x, px, y, py, z, pz
end

"""
Exact pole-face frame rotation, Section 5.3.

The new reference plane is a different plane in space, so the particle is
drifted onto it: `s* = x tan(A) / PT` with `PT = 1 - px tan(A) / ps`.
"""
@inline function _rot_xz(A::T, x, px, y, py, z, pz) where {T}
    A == 0 && return x, px, y, py, z, pz
    ps = sqrt((1 + pz)^2 - px * px - py * py)
    t = tan(A)
    PT = 1 - px * t / ps
    sstar = x * t / PT
    return x / (cos(A) * PT), px * cos(A) + ps * sin(A),
           y + py * sstar / ps, py, z - (1 + pz) * sstar / ps, pz
end

"""
Wedge of dipole field, Section 5.3: the exact sector bend in the thin-sliver
limit `L -> 0`, `h -> inf`, `A = hL` fixed. Degenerates to `_rot_xz` at `b1 = 0`.
"""
@inline function _wedge(A::T, b1::T, x, px, y, py, z, pz) where {T}
    b1 == 0 && return _rot_xz(A, x, px, y, py, z, pz)
    A == 0 && return x, px, y, py, z, pz
    ps = sqrt((1 + pz)^2 - px * px - py * py)
    pxn = px * cos(A) + (ps - b1 * x) * sin(A)
    w = sqrt((1 + pz)^2 - py * py)
    psn = sqrt((1 + pz)^2 - pxn * pxn - py * py)
    xn = x * cos(A) + (x * px * sin(2A) + sin(A)^2 * (2 * x * ps - b1 * x * x)) /
                      (psn + ps * cos(A) - px * sin(A))
    Δ = (A + asin(px / w) - asin(pxn / w)) / b1
    return xn, pxn, y + py * Δ, py, z - Δ * (1 + pz), pz
end

"""
Exact hard-edge dipole fringe, Section 6.3.1.

**Not optional, and not the same thing as `FINT`/`HGAP`.** With
`fint = hgap = 0` the generalized entrance angle is still
`Phi0 = atan(x'/(1+y'^2))`, nonzero whenever the trajectory is not parallel to
the axis. It is the dipole's share of the fringe Maxwell forces on any hard edge
(Section 6.2): a step-function dipole field cannot be curl-free without it. PTC
applies it at both faces of an exact bend regardless of the pole-face angle.

Works in slopes and keeps them exactly. The `y` update is the closed-form root
of `y_new = y + B y_new^2 / 2`, written cancellation-free.
"""
@inline function _fringe_dipole_exact(b1::T, fint::T, hgap::T, σ,
                                      x, px, y, py, z, pz) where {T}
    b1 == 0 && return x, px, y, py, z, pz
    b = σ * b1
    p = 1 + pz
    ps = sqrt(p * p - px * px - py * py)
    xp = px / ps
    yp = py / ps
    fg = fint * hgap
    d11 = (1 + xp * xp) / ps;   d21 = xp * yp / ps;      d31 = -xp
    d12 = xp * yp / ps;         d22 = (1 + yp * yp) / ps; d32 = -yp
    d13 = -p * xp / (ps * ps);  d23 = -p * yp / (ps * ps); d33 = p / ps
    u = xp / (1 + yp * yp)
    Φ = atan(u) - 2 * b * fg * (1 + xp * xp * (2 + yp * yp)) * ps
    co2 = b / cos(Φ)^2
    co1 = co2 / (1 + u * u)
    f1 = co1 / (1 + yp * yp) - co2 * 2 * b * fg * (2 * xp * (2 + yp * yp) * ps)
    f2 = -co1 * 2 * xp * yp / (1 + yp * yp)^2 - co2 * 2 * b * fg * (2 * xp * xp * yp) * ps
    f3 = -co2 * 2 * b * fg * (1 + xp * xp * (2 + yp * yp))
    tanΦ = b * tan(Φ)
    B = f1 * d12 + f2 * d22 + f3 * d32
    y = 2y / (1 + sqrt(1 - 2 * B * y))
    py -= tanΦ * y
    B = f1 * d11 + f2 * d21 + f3 * d31
    x += B * y * y / 2
    B = f1 * d13 + f2 * d23 + f3 * d33
    z += B * y * y / 2                # sign flipped from PTC (Section 2.1)
    if fg != 0
        c3 = b * b / (72 * fg) / p
        py -= 4 * c3 * y^3
        z -= c3 * y^4 / p
    end
    return x, px, y, py, z, pz
end

"""
Linear pole-face focusing with the fringe-field-integral correction
(Section 6.3.2), plus the cubic term inherited from SAD that most codes omit.
"""
@inline function _dipole_edge(b1::T, e::T, fint::T, hgap::T, σ,
                              x, px, y, py, z, pz) where {T}
    b1 == 0 && return x, px, y, py, z, pz
    ψ = fint * hgap == 0 ? zero(T) :
        2 * σ * fint * hgap * b1 * (1 + sin(e)^2) / cos(e)
    px += tan(e) * σ * b1 * x
    py -= tan(e - ψ) * σ * b1 * y
    if fint * hgap != 0
        py -= b1 * b1 / (18 * fint * hgap) * y^3
    end
    return x, px, y, py, z, pz
end

"""
Pole-face curvature term `FACE`, Section 6.3.
"""
@inline function _face(b1::T, hface::T, e::T, σ, x, px, y, py, z, pz) where {T}
    (b1 == 0 || hface == 0) && return x, px, y, py, z, pz
    C = inv(cos(e)^3)
    px += σ * b1 * hface / 2 * (x * x - C * y * y)
    py -= σ * b1 * hface * C * x * y
    return x, px, y, py, z, pz
end

# ---------------------------------------------------------------------------
# Runtime element
# ---------------------------------------------------------------------------

"""
    LatticeMagnet{M,T,N,ORDER,FRINGE}

Compiled runtime for a straight or curved lattice magnet. One type covers
drift, quadrupole, sextupole, octupole, general multipole and sector bend: the
magnet *kind* is data (which `kn`/`ks` entries are nonzero, and whether `h` and
`b0` are set), not a distinct type with its own tracking method.

`N` (number of multipole orders) and `ORDER` (integrator order) are type
parameters because they are bounded and cluster across a lattice. `nst` is
runtime data, so a convergence study over step count does not recompile.

Derivations: `docs/theory/lattice_hamiltonian_and_conventions.md`.
"""
struct LatticeMagnet{M<:AbstractTrackingMethod,T<:AbstractFloat,N,ORDER,FRINGE,MC,NC} <: AbstractTrackOp
    method::M
    L::T
    h::T                     # reference-frame curvature
    b0::T                    # dipole strength carried by the exact map
    kn::NTuple{N,T}          # kn[i] = K_{i-1}, normal, kicked
    ks::NTuple{N,T}          # skew partners
    psi::NTuple{NC,T}        # curved-frame potential table; empty unless combined-function
    nst::Int
    e1::T; e2::T             # pole-face angles
    fint1::T; fint2::T
    hgap1::T; hgap2::T
    hface1::T; hface2::T
    va::T; vs::T
end

@inline _has(::LatticeMagnet{M,T,N,O,F,MC,NC}, bit) where {M,T,N,O,F,MC,NC} = (F & bit) != 0

"""
Dipole strength as the face maps see it. `bend_model` decides whether the dipole
sits in the integrable map (`b0`) or in the kick (`kn[1]`); the faces must see
the same field either way.
"""
@inline _bend_strength(elem::LatticeMagnet{M,T,N}) where {M,T,N} =
    elem.b0 != 0 ? elem.b0 : (N >= 1 ? elem.kn[1] : zero(T))

@inline function _entrance(elem::LatticeMagnet{M,T,N,O,F,MC,NC},
                           x, px, y, py, z, pz) where {M,T,N,O,F,MC,NC}
    b1 = _bend_strength(elem)
    if F & FRINGE_DIPOLE_EDGE != 0
        x, px, y, py, z, pz = _rot_xz(elem.e1, x, px, y, py, z, pz)
        x, px, y, py, z, pz = _face(b1, elem.hface1, elem.e1, one(T), x, px, y, py, z, pz)
    end
    # The hard-edge dipole fringe runs regardless of the pole-face angle: it is
    # Maxwell-required, not an edge-angle effect (see _fringe_dipole_exact).
    if F & FRINGE_BEND != 0
        x, px, y, py, z, pz = _fringe_dipole_exact(b1, elem.fint1, elem.hgap1,
                                                   one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_MULTIPOLE != 0
        x, px, y, py, z, pz = _multipole_fringe(elem.kn, elem.ks, one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_SOFT_QUAD != 0 && N >= 2
        x, px, y, py, z, pz = _soft_quad_fringe(elem.kn[2], elem.ks[2], elem.va, elem.vs,
                                                one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_DIPOLE_EDGE != 0
        x, px, y, py, z, pz = _wedge(-elem.e1, b1, x, px, y, py, z, pz)
    end
    return x, px, y, py, z, pz
end

@inline function _exit(elem::LatticeMagnet{M,T,N,O,F,MC,NC},
                       x, px, y, py, z, pz) where {M,T,N,O,F,MC,NC}
    b1 = _bend_strength(elem)
    if F & FRINGE_DIPOLE_EDGE != 0
        x, px, y, py, z, pz = _wedge(-elem.e2, b1, x, px, y, py, z, pz)
    end
    if F & FRINGE_SOFT_QUAD != 0 && N >= 2
        x, px, y, py, z, pz = _soft_quad_fringe(elem.kn[2], elem.ks[2], elem.va, elem.vs,
                                                -one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_MULTIPOLE != 0
        x, px, y, py, z, pz = _multipole_fringe(elem.kn, elem.ks, -one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_BEND != 0
        x, px, y, py, z, pz = _fringe_dipole_exact(b1, elem.fint2, elem.hgap2,
                                                   -one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_DIPOLE_EDGE != 0
        x, px, y, py, z, pz = _face(b1, elem.hface2, elem.e2, -one(T), x, px, y, py, z, pz)
        x, px, y, py, z, pz = _rot_xz(elem.e2, x, px, y, py, z, pz)
    end
    return x, px, y, py, z, pz
end

"""
Kick for one sub-step. Uses the tabulated curved-frame field when the frame is
curved and the magnet carries multipoles beyond the dipole; otherwise the
straight closed form of Section 4.5, which is exact and cheaper.
"""
@inline _step_kick(elem::LatticeMagnet{M,T,N,O,F,MC,NC}, d, x, px, y, py, z, pz) where {M,T,N,O,F,MC,NC} =
    NC == 0 ? _lattice_kick(elem.kn, elem.ks, elem.h, d, x, px, y, py, z, pz) :
              _curved_kick(elem.psi, Val(MC), d, x, px, y, py, z, pz)

@inline _body_step(elem::LatticeMagnet, d, x, px, y, py, z, pz) =
    elem.b0 == 0 ? _lattice_drift(elem.h, d, x, px, y, py, z, pz) :
                   _lattice_bend(elem.h, elem.b0, d, x, px, y, py, z, pz)

@inline function track_particle(::Symplectic6DMap, elem::LatticeMagnet{M,T,N,ORDER,F,MC,NC},
                                x, px, y, py, z, pz) where {M,T,N,ORDER,F,MC,NC}
    x, px, y, py, z, pz = _entrance(elem, x, px, y, py, z, pz)
    if N == 0 && NC == 0
        # No multipole content: the body is integrable in one exact step, so
        # nst and integrator_order are genuinely inactive rather than merely
        # harmless. This is also the fast path for drifts and pure bends.
        elem.L != 0 && ((x, px, y, py, z, pz) = _body_step(elem, elem.L, x, px, y, py, z, pz))
    elseif elem.L != 0
        hstep = elem.L / elem.nst
        if ORDER == 2
            d = hstep / 2
            @inbounds for _ in 1:elem.nst
                x, px, y, py, z, pz = _body_step(elem, d, x, px, y, py, z, pz)
                x, px, y, py, z, pz = _step_kick(elem, hstep, x, px, y, py, z, pz)
                x, px, y, py, z, pz = _body_step(elem, d, x, px, y, py, z, pz)
            end
        else
            d1 = T(_FR_D1) * hstep; d2 = T(_FR_D2) * hstep
            k1 = T(_FR_K1) * hstep; k2 = T(_FR_K2) * hstep
            @inbounds for _ in 1:elem.nst
                x, px, y, py, z, pz = _body_step(elem, d1, x, px, y, py, z, pz)
                x, px, y, py, z, pz = _step_kick(elem, k1, x, px, y, py, z, pz)
                x, px, y, py, z, pz = _body_step(elem, d2, x, px, y, py, z, pz)
                x, px, y, py, z, pz = _step_kick(elem, k2, x, px, y, py, z, pz)
                x, px, y, py, z, pz = _body_step(elem, d2, x, px, y, py, z, pz)
                x, px, y, py, z, pz = _step_kick(elem, k1, x, px, y, py, z, pz)
                x, px, y, py, z, pz = _body_step(elem, d1, x, px, y, py, z, pz)
            end
        end
    end
    return _exit(elem, x, px, y, py, z, pz)
end

@inline (elem::LatticeMagnet)(x, px, y, py, z, pz) =
    track_particle(elem.method, elem, x, px, y, py, z, pz)

# ---------------------------------------------------------------------------
# Specs. Six element kinds share one runtime type and one tracking method: the
# magnet kind is data, not a separate implementation (AGENTS.md two-layer
# design). Only the friendly constructors and metadata differ.
# ---------------------------------------------------------------------------

const _FRINGE_MODES = (:none, :multipole, :soft_quad, :all)

function _fringe_bits(mode::Symbol, edge::Bool)
    mode in _FRINGE_MODES || throw(ArgumentError(
        "fringe must be one of $(_FRINGE_MODES); got $(repr(mode))"))
    bits = 0
    (mode === :multipole || mode === :all) && (bits |= FRINGE_MULTIPOLE)
    (mode === :soft_quad || mode === :all) && (bits |= FRINGE_SOFT_QUAD)
    # The hard-edge dipole fringe is Maxwell-required rather than an edge-angle
    # effect, so it follows the same switch instead of being a separate opt-in.
    edge && (bits |= FRINGE_DIPOLE_EDGE | FRINGE_BEND)
    return bits
end

"""
Pad the normal/skew strength lists to a common length; index `i` holds
`K_{i-1}`. A magnet with no multipole content compiles to `N = 0`, which makes
the kick and the multipole fringe identities at compile time and lets the body
be taken in a single exact step (see `track_particle`).
"""
function _strength_tuples(::Type{T}, kn, ks) where {T}
    n = max(length(kn), length(ks), 0)
    all(iszero, kn) && all(iszero, ks) && return (), ()
    return ntuple(i -> i <= length(kn) ? T(kn[i]) : zero(T), n),
           ntuple(i -> i <= length(ks) ? T(ks[i]) : zero(T), n)
end

function _lattice_magnet(spec::ElementSpec, method::AbstractTrackingMethod, ::Type{T}) where {T}
    L = T(param(spec, :L))
    nst = Int(getparam(spec, :nst, 1))
    nst > 0 || throw(ArgumentError("nst must be positive, got $nst"))
    order = Int(getparam(spec, :integrator_order, 2))
    order in LATTICE_INTEGRATOR_ORDERS || throw(ArgumentError(
        "integrator_order must be one of $(LATTICE_INTEGRATOR_ORDERS); got $order"))
    h = T(getparam(spec, :h, zero(T)))
    b0 = T(getparam(spec, :b0, zero(T)))
    knraw = collect(T, getparam(spec, :kn, ()))
    ksraw = collect(T, getparam(spec, :ks, ()))
    # bend_model decides which side of the splitting carries the dipole.
    #   :exact      -- b0 goes in the integrable map. No splitting error at all
    #                  for a pure bend, and exact at nst = 1.
    #   :drift_kick -- b0 goes in the kick, leaving a curved drift as the
    #                  integrable part. This is PTC's MODEL=1 arrangement and is
    #                  what a PTC comparison at finite nst requires.
    model = Symbol(getparam(spec, :bend_model, :exact))
    model in (:exact, :drift_kick) || throw(ArgumentError(
        "bend_model must be :exact or :drift_kick; got \$(repr(model))"))
    if model === :drift_kick && b0 != 0
        isempty(knraw) && (knraw = T[zero(T)])
        knraw[1] += b0
        b0 = zero(T)
    end
    kn, ks = _strength_tuples(T, knraw, ksraw)
    # A curved frame changes the multipole potential itself (Section 4.4), so a
    # combined-function magnet needs the curved field table. A pure dipole is
    # exempt: its curved potential terminates, so the straight form is already
    # exact for it once the (1+hx) factor is applied.
    combined = h != 0 && any(i -> i >= 2 && (kn[i] != 0 || ks[i] != 0), eachindex(kn))
    curved_order = Int(getparam(spec, :curved_order, 8))
    curved_order >= 1 || throw(ArgumentError("curved_order must be positive, got \$curved_order"))
    psi = combined ? _curved_potential_coeffs(T, kn, ks, h, curved_order) : ()
    mc = combined ? curved_order : 0
    edge = Bool(getparam(spec, :bend_fringe, true))
    bits = _fringe_bits(Symbol(getparam(spec, :fringe, :none)), edge)
    return LatticeMagnet{typeof(method),T,length(kn),order,bits,mc,length(psi)}(
        method, L, h, b0, kn, ks, psi, nst,
        T(getparam(spec, :e1, zero(T))), T(getparam(spec, :e2, zero(T))),
        T(getparam(spec, :fint1, zero(T))), T(getparam(spec, :fint2, zero(T))),
        T(getparam(spec, :hgap1, zero(T))), T(getparam(spec, :hgap2, zero(T))),
        T(getparam(spec, :hface1, zero(T))), T(getparam(spec, :hface2, zero(T))),
        T(getparam(spec, :va, zero(T))), T(getparam(spec, :vs, zero(T))))
end

LatticeMagnet(spec::ElementSpec, method::AbstractTrackingMethod=tracking_method(spec)) =
    _lattice_magnet(spec, method, Float64)

const _COMMON_PARAMS = (
    L=ParamMeta(required=true, meaning="arc length in metres"),
    nst=ParamMeta(default=1, meaning="integration steps; runtime data, so a convergence study over it does not recompile"),
    integrator_order=ParamMeta(default=2, meaning="2 (Strang) or 4 (Forest-Ruth, PTC METHOD=4 coefficients)"),
    fringe=ParamMeta(default=:none, meaning="per-magnet fringe selection: :none, :multipole (hard-edge Forest-Milutinovic), :soft_quad (VA/VS), or :all. Defaults off because the hard-edge multipole fringe is purely nonlinear -- it leaves the linear map unchanged to 0 ulp -- so it can be enabled on the few magnets that need it, such as a final-focus quadrupole, without perturbing the optics elsewhere. :soft_quad is different: it IS a linear map and does move the tune"),
    va=ParamMeta(default=0, meaning="soft-edge quadrupole fringe: equivalent linear-ramp length; signed"),
    vs=ParamMeta(default=0, meaning="soft-edge quadrupole fringe: second-moment parameter"),
    tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
)

# Friendly constructors follow the house pattern: an abstract type carrying a
# keyword constructor, so metadata queries such as `parameter_schema` dispatch
# on the type. `compile_runtime` needs no methods here -- it routes through
# `runtime_type`, which every kind maps to `LatticeMagnet`.
for (kind, ctor) in ((:drift, :DriftSpec), (:quadrupole, :QuadrupoleSpec),
                     (:sextupole, :SextupoleSpec), (:octupole, :OctupoleSpec),
                     (:multipole, :MultipoleSpec), (:sbend, :SBendSpec))
    @eval begin
        abstract type $ctor end
        $ctor(; kwargs...) = ElementSpec{$(QuoteNode(kind))}(_spec_params(; kwargs...))
    end
end

@element_spec begin
    kind = :drift
    spec_type = ElementSpec{:drift}
    friendly_constructor = DriftSpec
    runtime_type = LatticeMagnet
    description = "Exact field-free drift; the reference frame may be curved."
    keywords = [:lattice_magnet, :thick_element]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        L=ParamMeta(required=true, meaning="arc length in metres"),
        h=ParamMeta(default=0, meaning="reference-frame curvature 1/rho; a drift may be curved"),
        nst=ParamMeta(default=1, meaning="integration steps; unused because the drift is exact"),
        integrator_order=ParamMeta(default=2, meaning="unused because the drift is exact"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
    )
    example = DriftSpec(L=0.5)
    construction_help = "Friendly constructor: DriftSpec(; L, h=0, nst=1, integrator_order=2, tracking_method=Symplectic6DMap()). Exact in (1+delta); h != 0 gives a curved drift. nst and integrator_order are accepted for interface uniformity and unused, because the drift is exact."
end

@element_spec begin
    kind = :quadrupole
    spec_type = ElementSpec{:quadrupole}
    friendly_constructor = QuadrupoleSpec
    runtime_type = LatticeMagnet
    description = "Thick quadrupole: exact drift interleaved with multipole kicks."
    keywords = [:lattice_magnet, :thick_element, :nonlinear_interaction]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        L=_COMMON_PARAMS.L,
        kn=ParamMeta(default=(0, 0), meaning="normal strengths; index i holds K_{i-1}, so kn[2] is K1"),
        ks=ParamMeta(default=(0, 0), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        fringe=_COMMON_PARAMS.fringe,
        va=_COMMON_PARAMS.va,
        vs=_COMMON_PARAMS.vs,
        tracking_method=_COMMON_PARAMS.tracking_method,
    )
    example = QuadrupoleSpec(L=0.3, kn=(0.0, 1.2))
    construction_help = "Friendly constructor: QuadrupoleSpec(; L, kn=(0,K1), ks=(0,0), nst=1, integrator_order=2, fringe=:none, va=0, vs=0, tracking_method=Symplectic6DMap()). kn[i] is K_{i-1}."
end

@element_spec begin
    kind = :sextupole
    spec_type = ElementSpec{:sextupole}
    friendly_constructor = SextupoleSpec
    runtime_type = LatticeMagnet
    description = "Thick sextupole: exact drift interleaved with multipole kicks."
    keywords = [:lattice_magnet, :thick_element, :nonlinear_interaction]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        L=_COMMON_PARAMS.L,
        kn=ParamMeta(default=(0, 0, 0), meaning="normal strengths; kn[3] is K2"),
        ks=ParamMeta(default=(0, 0, 0), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        fringe=_COMMON_PARAMS.fringe,
        va=_COMMON_PARAMS.va,
        vs=_COMMON_PARAMS.vs,
        tracking_method=_COMMON_PARAMS.tracking_method,
    )
    example = SextupoleSpec(L=0.2, kn=(0.0, 0.0, 12.0))
    construction_help = "Friendly constructor: SextupoleSpec(; L, kn=(0,0,K2), ks=(0,0,0), nst=1, integrator_order=2, fringe=:none, va=0, vs=0, tracking_method=Symplectic6DMap())."
end

@element_spec begin
    kind = :octupole
    spec_type = ElementSpec{:octupole}
    friendly_constructor = OctupoleSpec
    runtime_type = LatticeMagnet
    description = "Thick octupole: exact drift interleaved with multipole kicks."
    keywords = [:lattice_magnet, :thick_element, :nonlinear_interaction]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        L=_COMMON_PARAMS.L,
        kn=ParamMeta(default=(0, 0, 0, 0), meaning="normal strengths; kn[4] is K3"),
        ks=ParamMeta(default=(0, 0, 0, 0), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        fringe=_COMMON_PARAMS.fringe,
        va=_COMMON_PARAMS.va,
        vs=_COMMON_PARAMS.vs,
        tracking_method=_COMMON_PARAMS.tracking_method,
    )
    example = OctupoleSpec(L=0.1, kn=(0.0, 0.0, 0.0, 300.0))
    construction_help = "Friendly constructor: OctupoleSpec(; L, kn=(0,0,0,K3), ks=(0,0,0,0), nst=1, integrator_order=2, fringe=:none, va=0, vs=0, tracking_method=Symplectic6DMap())."
end

@element_spec begin
    kind = :multipole
    spec_type = ElementSpec{:multipole}
    friendly_constructor = MultipoleSpec
    runtime_type = LatticeMagnet
    description = "Thick general multipole: exact drift interleaved with multipole kicks."
    keywords = [:lattice_magnet, :thick_element, :nonlinear_interaction]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        L=_COMMON_PARAMS.L,
        kn=ParamMeta(default=(0,), meaning="normal strengths of any length; index i holds K_{i-1}"),
        ks=ParamMeta(default=(0,), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        fringe=_COMMON_PARAMS.fringe,
        va=_COMMON_PARAMS.va,
        vs=_COMMON_PARAMS.vs,
        tracking_method=_COMMON_PARAMS.tracking_method,
    )
    example = MultipoleSpec(L=0.2, kn=(0.0, 1.0, 5.0))
    construction_help = "Friendly constructor: MultipoleSpec(; L, kn, ks, nst=1, integrator_order=2, fringe=:none, va=0, vs=0, tracking_method=Symplectic6DMap()). Field errors cost nothing structurally: add entries to kn/ks."
end

@element_spec begin
    kind = :sbend
    spec_type = ElementSpec{:sbend}
    friendly_constructor = SBendSpec
    runtime_type = LatticeMagnet
    description = "Exact sector bend with independent frame curvature and dipole strength."
    keywords = [:lattice_magnet, :thick_element, :coordinate_transform]
    tracking_methods = [Symplectic6DMap]
    contracts = [ElementTrackingBackendConsistencyContract, PTCConsistencyContract]
    analyses = [PlaceholderAnalysis]
    parameters = (
        L=_COMMON_PARAMS.L,
        h=ParamMeta(default=0, meaning="reference-frame curvature 1/rho; need not equal b0"),
        b0=ParamMeta(default=0, meaning="dipole strength q B0 / P0; independent of h"),
        kn=ParamMeta(default=(), meaning="normal multipole strengths for a combined-function bend; index i holds K_{i-1}"),
        ks=ParamMeta(default=(), meaning="skew partners of kn"),
        e1=ParamMeta(default=0, meaning="entrance pole-face angle"),
        e2=ParamMeta(default=0, meaning="exit pole-face angle"),
        fint1=ParamMeta(default=0, meaning="entrance fringe-field integral"),
        fint2=ParamMeta(default=0, meaning="exit fringe-field integral"),
        hgap1=ParamMeta(default=0, meaning="entrance half gap"),
        hgap2=ParamMeta(default=0, meaning="exit half gap"),
        hface1=ParamMeta(default=0, meaning="entrance pole-face curvature"),
        hface2=ParamMeta(default=0, meaning="exit pole-face curvature"),
        bend_fringe=ParamMeta(default=true, meaning="pole-face maps (exact rotation, face curvature, FINT/HGAP, wedge) and the Maxwell-required hard-edge dipole fringe. Defaults ON because it is first-order optics whenever e1 or e2 is nonzero: measured J[4,3] moves from 0 to -0.036 at e1=e2=0.1. With perpendicular faces it is purely nonlinear (linear map identical to 0 ulp), but it is still what PTC does and what Maxwell requires. Set false only to obtain the bare integrable map"),
        curved_order=ParamMeta(default=8, meaning="truncation order of the curved-frame field expansion used by combined-function bends (Section 4.4); a convergence parameter, unused when h == 0 or the magnet is a pure dipole"),
        bend_model=ParamMeta(default=:exact, meaning="where the dipole sits in the splitting: :exact puts it in the integrable map (no splitting error, exact at nst=1); :drift_kick puts it in the kick, reproducing PTC MODEL=1 at finite nst"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        fringe=_COMMON_PARAMS.fringe,
        tracking_method=_COMMON_PARAMS.tracking_method,
    )
    example = SBendSpec(L=1.0, h=0.05, b0=0.05)
    construction_help = "Friendly constructor: SBendSpec(; L, h=0, b0=0, e1=0, e2=0, fint1=0, fint2=0, hgap1=0, hgap2=0, hface1=0, hface2=0, bend_fringe=true, bend_model=:exact, curved_order=8, nst=1, integrator_order=2, fringe=:none, kn=(), ks=(), tracking_method=Symplectic6DMap()). h is the frame curvature and b0 the field; they need not agree. Combined-function bends are supported: give kn/ks alongside h."
end
