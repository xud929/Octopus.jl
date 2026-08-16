export DriftSpec, QuadrupoleSpec, SextupoleSpec, OctupoleSpec, MultipoleSpec,
       SBendSpec, RBendSpec, LatticeMagnet, LATTICE_INTEGRATOR_ORDERS

"""
Supported integrator orders for `LatticeMagnet`.

`2` is Strang drift-kick-drift; `4` is the Forest-Ruth composition PTC uses for
`METHOD=4` (four drifts, three kicks, with negative second coefficients). The
coefficients are pinned to PTC's so that agreement at finite `nst` is possible
at all -- different fourth-order compositions agree only as `nst -> infinity`.
See `docs/theory/lattice_hamiltonian_and_conventions.md` Section 7.
"""
const LATTICE_INTEGRATOR_ORDERS = (2, 4)

"""
Series/closed-form crossover for `_curv_vers`, as a named constant rather than
a literal in the branch.

The suite's seam checks straddle this value, and they used to do it with a
hand-copied `0.125`: moving the constant here would have put `prevfloat(0.125)`
and `nextfloat(0.125)` on the same side, so the seam tests would silently stop
straddling anything while still passing (2026-08-05_b audit, U17b-2). Now there
is one definition and the test derives its probe points from it.
"""
const CURV_VERS_CROSSOVER = 0.125

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
# Untyped signatures, promoting through the product: the straight solenoid
# calls `_curv_sin(kappa/2, L)` with a COORDINATE-dependent kappa, so under a
# ForwardDiff coordinate Jacobian the arguments arrive as (Dual, Float64) and
# the former strict `(::T, ::T)` pair was a MethodError — the same class as
# `_sol_log_over_h`'s recorded fix, invisible to the parameter-derivative
# sweep whose duals arrive matched (2026-08-05 audit, F17).
@inline function _curv_sin(h, L)
    u = h * L
    T = typeof(u)
    # `real(T)` for the crossover, not `T`: element parameters may now be dual
    # numbers or complex (a parameter derivative), and a complex threshold does
    # not order. Same reason `_atan_over` does it.
    abs(u) < real(T)(1e-4) && return L * (one(T) - u * u / 6 * (one(T) - u * u / 20))
    return sin(u) / h
end


@inline function _curv_vers(h, L)
    u = h * L
    T = typeof(u)
    # `real(T)` for the crossover, not `T` — see `_curv_sin`.
    #
    # The crossover is 0.125, not the 1e-4 the family uses elsewhere: the
    # `(1 - cos u)/h` cancellation does not stop at the guard, it decays as
    # ~eps/u^2, so at the old boundary the closed branch was 5.86e-9 relative
    # (measured vs BigFloat) against the series' 5.2e-17 — an 8-digit cliff one
    # ulp wide. The series therefore runs out to where the closed form has
    # recovered: measured vs BigFloat across the seam, the closed branch holds
    # <= 7.2e-15 for u in [0.125, 0.5] and the series (extended by the u^6 and
    # u^8 terms below, alternating so the truncation is bounded by the first
    # omitted term u^10/239500800 ~ 4e-18) holds <= 8.5e-17 — seam jump
    # 6.0e-15 (2026-08-05 audit, U10-5).
    #
    # The closed-branch figure was recorded as 5.9e-15 and is 20% optimistic:
    # re-measured at 400-bit precision over 400k points, the maximum is
    # 7.106e-15 at u = 0.1255, just inside the crossover where the cancellation
    # is worst (2026-08-05_b audit, U9-4). That matters because it is exactly
    # the kind of number a later session re-derives a tolerance from -- and one
    # did: the suite's bound on this branch had to be loosened from 1e-14 to
    # 1e-13 (U17b-1), because 1e-14 is only 1.4x the true error and half an ulp
    # of `cos` is amplified 118x here.
    abs(u) < real(T)(CURV_VERS_CROSSOVER) && return h * L * L / 2 *
        (one(T) - u * u / 12 * (one(T) - u * u / 30 * (one(T) - u * u / 56 * (one(T) - u * u / 90))))
    return (one(T) - cos(u)) / h
end

"""
`atan(u)/u`, smooth at `u = 0`, where it is 1.

The bend's `1/b0` is removed the same way its `1/h` was, and this is the helper
that finishes the job: the angle the dipole turns the momentum through comes out
as `atan(b0 * G)`, and dividing that by `b0` is a `0/0` exactly as
`sin(hL)/h` was.

Unlike the two curvature helpers, this one is handed a *coordinate*-dependent
argument, so it is reached with a complex value under complex-step
differentiation. The crossover therefore compares against `real(T)` -- `T(1e-4)`
would be a complex threshold and would not order.
"""
@inline function _atan_over(u::T) where {T}
    abs(u) < real(T)(1e-4) && return one(T) - u * u / 3 * (one(T) - 3 * u * u / 5)
    return atan(u) / u
end

"""
Exact drift in a frame of curvature `h`, in the `z = s - l` convention.

Both `y` and `z` follow from one shared quantity, the second from the first by
`p_y -> -(1 + p_z)` (Section 5). Written so that no `1/h` is ever formed.
"""
@inline function _lattice_drift(::Val{false}, h::T, L::T, x, px, y, py, z, pz) where {T}
    ps0 = sqrt((1 + pz)^2 - px * px - py * py)
    return x + px / ps0 * L, px, y + py / ps0 * L, py, z + L - (1 + pz) / ps0 * L, pz
end

@inline function _lattice_drift(::Val{true}, h::T, L::T, x, px, y, py, z, pz) where {T}
    ps0 = sqrt((1 + pz)^2 - px * px - py * py)
    c, s = cos(h * L), sin(h * L)
    C1 = _curv_sin(h, L)
    C2 = _curv_vers(h, L)
    pxn = px * c + ps0 * s
    psn = -px * s + ps0 * c
    xn = (ps0 * C2 + px * C1 + x * ps0) / psn
    Delta = (-px * C2 + ps0 * C1 + xn * pxn - x * px) / ((1 + pz)^2 - py * py)
    return xn, pxn, y + py * Delta, py, z + L - (1 + pz) * Delta, pz
end

# Value-dispatched shim for callers outside the tracking path (tests, the
# solenoid's drift-limit check) that hold `h` as a number rather than a type.
@inline _lattice_drift(h::T, L::T, x, px, y, py, z, pz) where {T} =
    iszero(h) ? _lattice_drift(Val(false), h, L, x, px, y, py, z, pz) :
                _lattice_drift(Val(true), h, L, x, px, y, py, z, pz)

"""
Exact sector bend: frame curvature `h`, dipole strength `b0`, independent.

`h == 0` is a straight-frame bend; `b0 == 0` is a curved drift; `h == b0` is a
sector bend on its design orbit.
"""
@inline function _lattice_bend(h::T, b0::T, L::T, x, px, y, py, z, pz) where {T}
    ps0 = sqrt((1 + pz)^2 - px * px - py * py)
    w2 = (1 + pz)^2 - py * py
    C1 = _curv_sin(h, L)
    C2 = _curv_vers(h, L)
    c, s = cos(h * L), sin(h * L)
    q = 1 + h * x
    # The b0 = 0 state: the frame turns by hL and the momentum turns with it.
    # Everything below is a departure from it, which is what makes the factor of
    # b0 explicit instead of hiding it inside a 0/0.
    pxr = px * c + ps0 * s
    psr = ps0 * c - px * s
    pxn = pxr - b0 * q * C1                 # identically px*c + dpx0*C1
    psn = sqrt(w2 - pxn * pxn)
    den = psn + psr
    U = psn * s - pxn * c
    V = pxn * s + psn * c
    D = ps0 * V - px * U                    # -> w2 as b0 -> 0
    # `real` so the test survives complex-step differentiation: the imaginary
    # perturbation is infinitesimal and cannot move the map across this
    # boundary, so deciding on the real part keeps one branch for the value and
    # its derivative -- which is also what makes the derivative meaningful.
    if abs(h * L) < real(T)(pi) / 2 && real(den) > 0 && real(D) > 0
        # Cancellation-free. `psn - psr` is rationalised through
        # psn^2 - psr^2 = pxr^2 - pxn^2 = (b0 q C1)(pxr + pxn), and the angle
        # the dipole turns the momentum through comes out as atan(b0 G), so
        # both 1/b0 factors cancel analytically rather than numerically.
        R = (pxn + pxr) / den
        xn = x + q * (C1 * R - C2)
        G = q * C1 * (pxr * R + psr) / D
        Δ = G * _atan_over(b0 * G)
    else
        # Beyond a quarter turn of frame rotation in one step the b0 -> 0 state
        # runs backwards through the rotated frame, so there is no small-b0
        # limit to protect and nothing cancels; the direct forms of Section 5.2
        # are well conditioned there. `b0 != 0` holds by construction --
        # `_body_step` sends b0 = 0 to the drift.
        dpx0 = -b0 * q + h * ps0
        w = sqrt(w2)
        xn = x + ((psn - ps0) + px * s + dpx0 * C2) / b0
        Δ = (h * L - (asin(pxn / w) - asin(px / w))) / b0
    end
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
    # Section 4.5: dpx = -L (1+hx) By, dpy = +L (1+hx) Bx. The only content that
    # may take this path with h != 0 is a PURE NORMAL DIPOLE (anything else
    # routes to _curved_kick, see `_needs_curved_potential`), and the curved
    # dipole field is exactly K0, so the factor is exact rather than truncated.
    #
    # This restriction is not cosmetic, and it is exactly a pure NORMAL dipole
    # rather than "a dipole". Writing the sum as the analytic
    # f(w) = sum (K_n + i Ks_n) w^n / n!, w = x + iy, this map is
    # dpx = -L(1+hx) Re f and dpy = +L(1+hx) Im f, so by Cauchy-Riemann
    #
    #     d(dpx)/dy - d(dpy)/dx = -L h Im f .
    #
    # It is a gradient -- and hence symplectic -- iff h Im f vanishes
    # identically, i.e. iff every order above the normal dipole is zero. The
    # SKEW dipole is not exempt: its curved potential does not terminate
    # (Psi_1 = Ks0 (1+hx) seeds Psi_3 = h^2 Ks0/(1+hx)). Routing it here anyway
    # cost O(L h Ks0) of symplecticity -- measured 2.5e-3 at L=1, h=Ks0=0.05.
    g = 1 + h * x
    return x, px - L * g * ar, y, py + L * g * ai, z, pz
end

"""
    _needs_curved_potential(kn, ks, h) -> Bool

Does a curved frame force this magnet's kick through the tabulated potential?

`_lattice_kick` is a gradient in a curved frame **iff** the content is a pure
normal dipole (see the derivation in that function). So the exemption is exactly
index 1 of `kn`, and everything else -- every order from the quadrupole up,
normal or skew, **and the skew dipole** -- needs `_curved_potential_coeffs`.

Shared with the solenoid, which Strang-splits against the same `_lattice_kick`
and therefore inherits the same condition.
"""
@inline _needs_curved_potential(kn, ks, h) =
    h != 0 && any(i -> (i >= 2 && (kn[i] != 0 || ks[i] != 0)) ||
                       (i == 1 && ks[i] != 0), eachindex(kn))

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

Two guards reproduce `MULTIPOLE_FRINGER` in PTC's `Sh_def_kind.f90`:

  * `hf` caps the order, as PTC's `MIN(EL%NMUL, HIGHEST_FRINGE)` does. `0` means
    every order the magnet carries; PTC's own default is `2`, i.e. dipole and
    quadrupole only. Ours is uncapped, because enabling a sextupole's fringe and
    silently getting nothing back is worse than a documented deviation -- but
    matching PTC requires `hf = 2`.
  * `drop1` suppresses the *normal* dipole term, as PTC's
    `IF(J==1.AND.EL%BEND_FRINGE)` branch does, which keeps the skew `AN(1)` but
    drops `BN(1)`. When the exact hard-edge dipole fringe is already running,
    the dipole's fringe is accounted for there, and including it again here
    double-counts it. This matters precisely for `bend_model = :drift_kick`,
    which folds the dipole into `kn[1]`.

A magnet with one order or fewer has no multipole fringe at all, matching PTC's
`IF(EL%NMUL<=1) RETURN`.
"""
@inline function _multipole_fringe(kn::NTuple{N,T}, ks::NTuple{N,T}, σ,
                                   hf::Int, drop1::Bool,
                                   x, px, y, py, z, pz) where {N,T}
    N <= 1 && return x, px, y, py, z, pz
    Fx = zero(x); Fy = zero(x)
    Fxx = zero(x); Fxy = zero(x); Fyx = zero(x); Fyy = zero(x)
    pr = one(x); pi_ = zero(x)               # (x+iy)^(j-1)
    invfac = one(x)                          # 1/(j-1)!
    @inbounds for j in 1:N
        hf > 0 && j > hf && break
        # PTC's field expansion carries NO factorial: its BN(j) is
        # K_{j-1}/(j-1)!. kn[] is stored in the MAD-X convention (Section 4.1),
        # so the factorial is removed here.
        cr = (drop1 && j == 1) ? zero(T) : kn[j] * invfac
        ci = ks[j] * invfac
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
    psn = sqrt((1 + pz)^2 - pxn * pxn - py * py)
    xn = x * cos(A) + (x * px * sin(2A) + sin(A)^2 * (2 * x * ps - b1 * x * x)) /
                      (psn + ps * cos(A) - px * sin(A))
    # Δ = (A + asin(px/w) - asin(pxn/w)) / b1 is an O(b1) angle assembled from
    # O(A) terms, the identical 1/b0 cancellation `_lattice_bend` was rewritten
    # to remove (its error grew as ~eps*A/b1: measured 2.8e-10 on z at
    # b1 = 1e-8). Rationalised the same way. With phi = asin(px/w) + A the
    # rotated momentum is pxr = w*sin(phi), psr = w*cos(phi), and
    #     sin(phi - asin(pxn/w)) = (pxr*psn - psr*pxn) / w^2
    #                            = b1*x*sin(A) * (pxn*(pxr+pxn)/(psn+psr) + psn) / w^2 ,
    #     cos(phi - asin(pxn/w)) = (psr*psn + pxr*pxn) / w^2 ,
    # where psn - psr was rationalised through psn^2 - psr^2 = pxr^2 - pxn^2
    # = (b1*x*sin(A))*(pxr + pxn), so the factor of b1 is explicit and the
    # angle comes out as atan(b1*G) with both 1/b1 cancelling analytically —
    # the b1 -> 0 limit G -> x*sin(A)/psr is exactly `_rot_xz`'s
    # sstar/ps = x*tan(A)/(ps - px*tan(A)) (2026-08-05 audit, U10-7).
    psr = ps * cos(A) - px * sin(A)
    pxr = px * cos(A) + ps * sin(A)
    den = psn + psr
    Dc = psr * psn + pxr * pxn
    # `real` for the same complex-step reason as `_lattice_bend`. Outside this
    # branch |phi - asin(pxn/w)| >= pi/2: a wedge turning the momentum by more
    # than a quarter turn, which is not a small-b1 state — nothing cancels and
    # the direct form is well conditioned there.
    if real(den) > 0 && real(Dc) > 0
        G = x * sin(A) * (pxn * (pxr + pxn) / den + psn) / Dc
        Δ = G * _atan_over(b1 * G)
    else
        w = sqrt((1 + pz)^2 - py * py)
        Δ = (A + asin(px / w) - asin(pxn / w)) / b1
    end
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

# The linear pole-face focusing map of Section 6.3.2 used to live here and has
# been removed: PTC has no separate linear edge-focusing map, because the exact
# `FRINGE_dipole` together with `WEDGE` already does that work, and keeping a
# second uncalled edge map invited the reader to believe edge focusing was
# applied somewhere it was not. The derivation stays in the theory note.

"""
Quadrupole-in-wedge kick, PTC's `MAD8_WEDGE` term.

A combined-function magnet with an angled pole face gets a thin sextupole-like
kick proportional to the edge angle and the quadrupole component:

    dpx = e b2 (wc1 x^2 - wc2 y^2 / 2) ,     dpy = -e b2 wc2 x y

It is a gradient (of `e b2 (wc1 x^3/3 - wc2 x y^2/2)`), so it is exactly
symplectic. The sign does *not* alternate between faces: PTC adds `+EDGE(1)` at
entry and `+EDGE(2)` at exit.

`wc` defaults to `(1, 2)`, which is what PTC's `MAD8_WEDGE` branch hardcodes:

    x(2)=x(2)+EDGE*bn(2)*(x(1)**2-x(3)**2)
    x(4)=x(4)-EDGE*bn(2)*(2*x(1)*x(3))

PTC's other branch, taken when its fringes are on, multiplies by the module
variable `wedge_coeff`, which is declared with **no initializer** in
`Sh_def_kind.f90` -- so that path uses whatever static storage holds, in
practice zero. Set `wedge_coeff = (0, 0)` to reproduce it.
"""
@inline function _wedge_quad(e::T, b2::T, wc1::T, wc2::T,
                             x, px, y, py, z, pz) where {T}
    (e == 0 || b2 == 0) && return x, px, y, py, z, pz
    return x, px + e * b2 * (wc1 * x * x - wc2 * y * y / 2), y,
           py - e * b2 * (wc2 * x * y), z, pz
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

# `T<:Number`, not `T<:AbstractFloat`: a dual number is `<:Real` and a truncated
# power series is `<:Number`, so the tighter bound would refuse both and with them
# every parameter derivative. Ordinary magnets are still built at Float64.
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
struct LatticeMagnet{M<:AbstractTrackingMethod,T<:Number,N,ORDER,FRINGE,MC,NC,CURVED} <: AbstractTrackOp
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
    wc1::T; wc2::T           # PTC MAD8_WEDGE coefficients
    hf::Int                  # multipole-fringe order cap; 0 means uncapped
    kill1::Bool; kill2::Bool # PTC KILL_ENT_FRINGE / KILL_EXI_FRINGE
end

@inline _has(::LatticeMagnet{M,T,N,O,F,MC,NC,C}, bit) where {M,T,N,O,F,MC,NC,C} = (F & bit) != 0

"""
Dipole strength as the face maps see it. `bend_model` decides whether the dipole
sits in the integrable map (`b0`) or in the kick (`kn[1]`); the faces must see
the same field either way.
"""
@inline _bend_strength(elem::LatticeMagnet{M,T,N}) where {M,T,N} =
    elem.b0 != 0 ? elem.b0 : (N >= 1 ? elem.kn[1] : zero(T))

@inline function _entrance(elem::LatticeMagnet{M,T,N,O,F,MC,NC,C},
                           x, px, y, py, z, pz) where {M,T,N,O,F,MC,NC,C}
    b1 = _bend_strength(elem)
    if F & FRINGE_DIPOLE_EDGE != 0
        x, px, y, py, z, pz = _rot_xz(elem.e1, x, px, y, py, z, pz)
        x, px, y, py, z, pz = _face(b1, elem.hface1, elem.e1, one(T), x, px, y, py, z, pz)
    end
    # The hard-edge dipole fringe runs regardless of the pole-face angle: it is
    # Maxwell-required, not an edge-angle effect (see _fringe_dipole_exact).
    # kill1 suppresses the three fringe mechanisms at this face, as PTC's
    # KILL_ENT_FRINGE does; it deliberately does NOT suppress ROT_XZ, FACE or
    # WEDGE, which are geometry rather than fringe and which PTC leaves running.
    if F & FRINGE_BEND != 0 && !elem.kill1
        x, px, y, py, z, pz = _fringe_dipole_exact(b1, elem.fint1, elem.hgap1,
                                                   one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_MULTIPOLE != 0 && !elem.kill1
        x, px, y, py, z, pz = _multipole_fringe(elem.kn, elem.ks, one(T), elem.hf,
                                                F & FRINGE_BEND != 0, x, px, y, py, z, pz)
    end
    if F & FRINGE_SOFT_QUAD != 0 && N >= 2 && !elem.kill1
        x, px, y, py, z, pz = _soft_quad_fringe(elem.kn[2], elem.ks[2], elem.va, elem.vs,
                                                one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_DIPOLE_EDGE != 0
        # PTC applies this between the fringes and the wedge, with the edge
        # angle entering unsigned at both faces.
        N >= 2 && ((x, px, y, py, z, pz) =
            _wedge_quad(elem.e1, elem.kn[2], elem.wc1, elem.wc2, x, px, y, py, z, pz))
        x, px, y, py, z, pz = _wedge(-elem.e1, b1, x, px, y, py, z, pz)
    end
    return x, px, y, py, z, pz
end

@inline function _exit(elem::LatticeMagnet{M,T,N,O,F,MC,NC,C},
                       x, px, y, py, z, pz) where {M,T,N,O,F,MC,NC,C}
    b1 = _bend_strength(elem)
    if F & FRINGE_DIPOLE_EDGE != 0
        x, px, y, py, z, pz = _wedge(-elem.e2, b1, x, px, y, py, z, pz)
        N >= 2 && ((x, px, y, py, z, pz) =
            _wedge_quad(elem.e2, elem.kn[2], elem.wc1, elem.wc2, x, px, y, py, z, pz))
    end
    if F & FRINGE_SOFT_QUAD != 0 && N >= 2 && !elem.kill2
        x, px, y, py, z, pz = _soft_quad_fringe(elem.kn[2], elem.ks[2], elem.va, elem.vs,
                                                -one(T), x, px, y, py, z, pz)
    end
    if F & FRINGE_MULTIPOLE != 0 && !elem.kill2
        x, px, y, py, z, pz = _multipole_fringe(elem.kn, elem.ks, -one(T), elem.hf,
                                                F & FRINGE_BEND != 0, x, px, y, py, z, pz)
    end
    if F & FRINGE_BEND != 0 && !elem.kill2
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
@inline _step_kick(elem::LatticeMagnet{M,T,N,O,F,MC,NC,C}, d, x, px, y, py, z, pz) where {M,T,N,O,F,MC,NC,C} =
    NC == 0 ? _lattice_kick(elem.kn, elem.ks, elem.h, d, x, px, y, py, z, pz) :
              _curved_kick(elem.psi, Val(MC), d, x, px, y, py, z, pz)

# The frame is straight or curved by TYPE, decided in `compile_runtime`, so the
# kernel contains only the branch it needs.
#
# `b0 == 0` remains a field test, and it is a FAST PATH rather than a guard.
# Every quadrupole, sextupole, octupole, multipole and drift has b0 = 0, and so
# does every bend running `bend_model = :drift_kick`, which is what a PTC
# comparison requires -- so this branch is the common case, not the exception,
# and it is what keeps their integrable step at a handful of flops instead of
# routing it through the bend's trigonometry and two square roots.
#
# It used to be a division-by-zero guard as well, because `_lattice_bend` formed
# 1/b0. It no longer is: that map is cancellation-free and its own b0 -> 0 limit
# is finite, so the two paths now agree at b0 = 0 rather than one of them being
# undefined there. Deleting the test would be correct and slow.
@inline _body_step(elem::LatticeMagnet{M,T,N,O,F,MC,NC,C}, d, x, px, y, py, z, pz) where {M,T,N,O,F,MC,NC,C} =
    elem.b0 == 0 ? _lattice_drift(Val(C), elem.h, d, x, px, y, py, z, pz) :
                   _lattice_bend(elem.h, elem.b0, d, x, px, y, py, z, pz)

@inline function track_particle(::Symplectic6DMap, elem::LatticeMagnet{M,T,N,ORDER,F,MC,NC,C},
                                x, px, y, py, z, pz) where {M,T,N,ORDER,F,MC,NC,C}
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

# Every key `_lattice_magnet` reads below is declared by EVERY kind it
# compiles: `_LATTICE_BODY_PARAMS` (defined beside `_COMMON_PARAMS` below) is
# merged into all six schemas, and `_LATTICE_BODY_KEYS` is derived from it.
# Until 2026-08-15 each kind declared only its own subset -- drift was missing
# 21 of the 23, quadrupole/sextupole/octupole/multipole 15 each, sbend 2 -- and
# the unknown-key warning needed an `_extra_tracked_keys` side list so it could
# not claim a key the runtime reads is "NOT being tracked" (2026-08-05_b audit,
# U9-2). The completed schemas make that side list unnecessary: the warning
# checks the schema, and the schema now tells the truth.

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
        "bend_model must be :exact or :drift_kick; got $(repr(model))"))
    if model === :drift_kick && b0 != 0
        isempty(knraw) && (knraw = T[zero(T)])
        knraw[1] += b0
        b0 = zero(T)
    end
    kn, ks = _strength_tuples(T, knraw, ksraw)
    # `curved` selects the frame's tracking path and is resolved HERE, before
    # anything downstream consumes the curvature -- nothing about curvature is
    # decided inside a kernel. Defaults to `!iszero(h)`; `true` at h = 0
    # exercises the curved closed form where the straight one also applies,
    # and `false` at h != 0 ignores the curvature and warns rather than doing
    # so silently. `hc` is the curvature the element actually tracks with:
    # the 2026-08-05 audit (U10-4) found the old ordering built the psi table
    # and stored raw h with `curved = false`, so the body kept the curvature
    # its own warning said was ignored (1.6e-7 against a real h = 0 track).
    requested_curved = getparam(spec, :curved, nothing)
    curved = requested_curved === nothing ? !iszero(h) : Bool(requested_curved)
    if !curved && !iszero(h)
        @warn "element has curved = false with h != 0; the frame curvature is \
               ignored and the body tracks in a straight frame" h
    end
    hc = curved ? h : zero(T)
    # A curved frame changes the multipole potential itself (Section 4.4), so a
    # combined-function magnet needs the curved field table. A pure NORMAL
    # dipole is exempt: its curved potential terminates (Psi_2 = 0), so the
    # straight form is already exact for it once the (1+hx) factor is applied.
    # The skew dipole is NOT exempt -- see `_needs_curved_potential`.
    combined = _needs_curved_potential(kn, ks, hc)
    curved_order = Int(getparam(spec, :curved_order, 8))
    curved_order >= 1 || throw(ArgumentError("curved_order must be positive, got $curved_order"))
    psi = combined ? _curved_potential_coeffs(T, kn, ks, hc, curved_order) : ()
    mc = combined ? curved_order : 0
    edge = Bool(getparam(spec, :bend_fringe, true))
    bits = _fringe_bits(Symbol(getparam(spec, :fringe, :none)), edge)
    hf = Int(getparam(spec, :highest_fringe, 0))
    hf >= 0 || throw(ArgumentError("highest_fringe must be non-negative, got $hf"))
    wc = getparam(spec, :wedge_coeff, (1, 2))
    length(wc) == 2 || throw(ArgumentError(
        "wedge_coeff must hold two values, got $(length(wc))"))
    return LatticeMagnet{typeof(method),T,length(kn),order,bits,mc,length(psi),curved}(
        method, L, hc, b0, kn, ks, psi, nst,
        T(getparam(spec, :e1, zero(T))), T(getparam(spec, :e2, zero(T))),
        T(getparam(spec, :fint1, zero(T))), T(getparam(spec, :fint2, zero(T))),
        T(getparam(spec, :hgap1, zero(T))), T(getparam(spec, :hgap2, zero(T))),
        T(getparam(spec, :hface1, zero(T))), T(getparam(spec, :hface2, zero(T))),
        T(getparam(spec, :va, zero(T))), T(getparam(spec, :vs, zero(T))),
        T(wc[1]), T(wc[2]), hf,
        Bool(getparam(spec, :kill_ent_fringe, false)),
        Bool(getparam(spec, :kill_exi_fringe, false)))
end

# `_lattice_magnet` has always been generic in `T`; this was the only caller and
# it pinned Float64, which is what kept parameter derivatives out.
LatticeMagnet(spec::ElementSpec, method::AbstractTrackingMethod=tracking_method(spec)) =
    _lattice_magnet(spec, method, numeric_type(spec))

const _COMMON_PARAMS = (
    L=ParamMeta(required=true, meaning="arc length in metres"),
    nst=ParamMeta(default=1, meaning="integration steps; runtime data, so a convergence study over it does not recompile"),
    integrator_order=ParamMeta(default=2, meaning="2 (Strang) or 4 (Forest-Ruth, PTC METHOD=4 coefficients)"),
    fringe=ParamMeta(default=:none, alternatives=(:none, :multipole, :soft_quad, :all), meaning="per-magnet fringe selection: :none, :multipole (hard-edge Forest-Milutinovic), :soft_quad (VA/VS), or :all. Defaults off because the hard-edge multipole fringe is purely nonlinear -- it leaves the linear map unchanged to 0 ulp -- so it can be enabled on the few magnets that need it, such as a final-focus quadrupole, without perturbing the optics elsewhere. :soft_quad is different: it IS a linear map and does move the tune"),
    va=ParamMeta(default=0, meaning="soft-edge quadrupole fringe: equivalent linear-ramp length; signed"),
    vs=ParamMeta(default=0, meaning="soft-edge quadrupole fringe: second-moment parameter"),
    highest_fringe=ParamMeta(default=0, meaning="cap on the order included in the hard-edge multipole fringe, matching PTC's HIGHEST_FRINGE. 0 means every order the magnet carries, which is this code's default because enabling a sextupole's fringe and silently getting nothing back would be worse; PTC's own default is 2 (dipole and quadrupole only), so set 2 to reproduce PTC. Inactive unless fringe includes :multipole"),
    kill_ent_fringe=ParamMeta(default=false, meaning="suppress all three fringe mechanisms at the entrance face, matching PTC's KILL_ENT_FRINGE. Geometry maps (pole-face rotation, face curvature, wedge) still run, as they do in PTC. MAD-X sets the exit equivalent automatically when FINTX=0"),
    kill_exi_fringe=ParamMeta(default=false, meaning="suppress all three fringe mechanisms at the exit face, matching PTC's KILL_EXI_FRINGE"),
    x_offset=ParamMeta(default=0, meaning="misalignment: horizontal displacement of the magnet body, referenced to the element centre as alignment data is. Curved elements are handled through the survey, whose geometry follows h rather than b0"),
    y_offset=ParamMeta(default=0, meaning="misalignment: vertical displacement of the body centre"),
    z_offset=ParamMeta(default=0, meaning="misalignment: longitudinal displacement of the body centre"),
    x_pitch=ParamMeta(default=0, meaning="misalignment: rotation of the body about the y axis, in radians, about the element centre (Bmad's x_pitch)"),
    y_pitch=ParamMeta(default=0, meaning="misalignment: rotation of the body about the x axis, in radians, about the element centre (Bmad's y_pitch)"),
    tilt=ParamMeta(default=0, meaning="misalignment: roll of the body about the longitudinal axis, in radians. Geometric, and distinct from building a skew magnet through ks"),
    misalign_convention=ParamMeta(default=:bmad, alternatives=(:bmad, :madx), meaning="which code's misalignment convention to follow. :bmad references the displacement to the element centre, as survey data means, and composes the rotations about fixed axes as R_y R_x R_z. :madx references it to the entrance frame and composes them intrinsically as R_z R_x R_y, reproducing EALIGN through MAD_MISALIGN_FIBRE. The two agree only for a pure translation of a straight element, and for any single rotation"),
    tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
)

# The 23 body keys `_lattice_magnet` reads for EVERY kind it compiles, as one
# schema table merged into all six kinds (U9-2). The kind names the intent; the
# keys carry the field and geometry; the runtime is one function -- so `e1` on
# a quadrupole is read (measured 7.7e-7 shift) and a drift given `b0` bends.
# Declaring the full set everywhere is the truth-telling repair: `element_help`
# is accurate, the unknown-key warning needs no side list, and every entry sits
# under the parameter-effectiveness sweep. A kind whose meta needs more than
# the generic meaning (drift's exactness, the bend's angle sugar) overrides the
# entry in its own `parameters = merge(_LATTICE_BODY_PARAMS, (...))` call --
# later keys win, so a curated meaning can never be clobbered by this table.
const _LATTICE_BODY_PARAMS = (
    h=ParamMeta(default=0, meaning="reference-frame curvature 1/rho; the frame of any lattice-magnet kind may be curved, a curved drift included. Independent of the dipole strength b0"),
    b0=ParamMeta(default=0, meaning="dipole strength q B0 / P0; independent of the frame curvature h. Read for every lattice-magnet kind by the one shared runtime, so setting it on any kind adds a real dipole field"),
    kn=ParamMeta(default=(), meaning="normal multipole strengths as a positional tuple; index i holds K_{i-1}, so kn[2] is K1. The named kinds fold their defining strengths (k1, k2, ...) into this at construction and use the tuple for measured field errors on top"),
    ks=ParamMeta(default=(), meaning="skew partners of kn"),
    bend_model=ParamMeta(default=:exact, alternatives=(:exact, :drift_kick), meaning="where the dipole sits in the splitting: :exact puts it in the integrable map (no splitting error, exact at nst=1); :drift_kick puts it in the kick, reproducing PTC MODEL=1 at finite nst"),
    curved=ParamMeta(default=nothing, meaning="force the curved or straight body path. `nothing` lets the frame decide, i.e. curved when h != 0. Resolved at compile_runtime and carried in the type, so no curvature test happens inside the tracking kernel. `true` at h = 0 exercises the curved closed form where the straight one also applies; `false` at h != 0 ignores the curvature and warns"),
    curved_order=ParamMeta(default=8, meaning="truncation order of the curved-frame field expansion used by curved multipole bodies (Section 4.4); a convergence parameter, unused when h == 0 or the magnet is a pure dipole"),
    bend_fringe=ParamMeta(default=true, meaning="pole-face maps (exact rotation, face curvature, FINT/HGAP, wedge) and the Maxwell-required hard-edge dipole fringe. Defaults ON because it is first-order optics whenever e1 or e2 is nonzero: measured J[4,3] moves from 0 to -0.036 at e1=e2=0.1. With perpendicular faces it is purely nonlinear (linear map identical to 0 ulp), but it is still what PTC does and what Maxwell requires. Set false only to obtain the bare integrable map"),
    fringe=_COMMON_PARAMS.fringe,
    highest_fringe=_COMMON_PARAMS.highest_fringe,
    wedge_coeff=ParamMeta(default=(1, 2), meaning="coefficients of the quadrupole-in-wedge kick applied at an angled pole face, PTC's wedge_coeff. The default (1,2) is what PTC's MAD8_WEDGE branch hardcodes and is its behaviour with fringes off; PTC's other branch reads a module variable left with no initializer, so (0,0) reproduces that. Inactive unless bend_fringe is on, a pole-face angle is nonzero, and the magnet carries a quadrupole component"),
    e1=ParamMeta(default=0, meaning="entrance pole-face angle"),
    e2=ParamMeta(default=0, meaning="exit pole-face angle"),
    fint1=ParamMeta(default=0, meaning="entrance fringe-field integral"),
    fint2=ParamMeta(default=0, meaning="exit fringe-field integral"),
    hgap1=ParamMeta(default=0, meaning="entrance half gap"),
    hgap2=ParamMeta(default=0, meaning="exit half gap"),
    hface1=ParamMeta(default=0, meaning="entrance pole-face curvature"),
    hface2=ParamMeta(default=0, meaning="exit pole-face curvature"),
    va=_COMMON_PARAMS.va,
    vs=_COMMON_PARAMS.vs,
    kill_ent_fringe=_COMMON_PARAMS.kill_ent_fringe,
    kill_exi_fringe=_COMMON_PARAMS.kill_exi_fringe,
)

# Derived, not hand-listed: the authoritative key list IS the table above.
const _LATTICE_BODY_KEYS = keys(_LATTICE_BODY_PARAMS)

# One shared construction_help sentence naming every body key, concatenated
# into each kind's help so the metadata validator's mention check holds for
# all six without six hand-copied enumerations.
const _LATTICE_BODY_HELP = " Body keys read by the ONE shared lattice-magnet runtime for every kind (drift, quadrupole, sextupole, octupole, multipole, sbend), so any of these is legal and tracked on any of the six -- the kind names the intent, the keys carry the field and geometry: h (frame curvature; a curved drift is real), b0 (dipole strength; a drift given b0 bends), kn and ks (multipole strengths; index i holds K_{i-1}), bend_model (:exact or :drift_kick), curved and curved_order (body-path override and curved-frame truncation order), bend_fringe with pole-face geometry e1, e2, fint1, fint2, hgap1, hgap2, hface1, hface2 and wedge_coeff, fringe with highest_fringe, va, vs (soft-edge quadrupole fringe), kill_ent_fringe, kill_exi_fringe."

# ---------------------------------------------------------------------------
# Named strength keywords.
#
# `kn`/`ks` are positional: index i holds K_{i-1}. That is the right storage for
# a general multipole, but it makes the common case clumsy and, worse, silently
# wrong -- `kn = (0, 12.0)` in a `SextupoleSpec` is a quadrupole, and nothing
# says so. Each named kind therefore also accepts the strength that defines it
# (`k1` for a quadrupole, `k2` for a sextupole, `k3` for an octupole, with skew
# partners), folded into the tuple at construction.
#
# Both spellings are kept deliberately. The named keyword is how a magnet of
# that kind is normally built; the tuple is how measured field errors and
# feed-down are added on top of it, without giving up the descriptive kind. A
# real sextupole with a K3 error is still a sextupole, not a multipole.
# ---------------------------------------------------------------------------

const _NO_NAMED = ()
const _QUAD_NAMED = ((:k1, :k1s, 1),)
const _SEXT_NAMED = ((:k2, :k2s, 2),)
const _OCT_NAMED = ((:k3, :k3s, 3),)
const _BEND_NAMED = ((:k1, :k1s, 1), (:k2, :k2s, 2))
# The general multipole covers every order it is likely to be built from: K0
# (a dipole corrector) through K5 (dodecapole). Nothing about order 4 and up is
# special to the kick -- `_lattice_kick` is generic in N and symplectic to
# round-off at any order -- so a decapole is `k4`, not four leading zeros.
# Orders beyond K5 stay in the positional tuple, where they are rare enough
# that spelling the tuple out is honest rather than clumsy.
const _MULTIPOLE_NAMED = ((:k0, :k0s, 0), (:k1, :k1s, 1), (:k2, :k2s, 2),
                          (:k3, :k3s, 3), (:k4, :k4s, 4), (:k5, :k5s, 5))

# Declared fold sites, read by the beam-line override guard
# (`_reject_folded_override`, beam_line.jl). POPULATED BESIDE EACH FOLD SITE —
# here, in thin_elements.jl and in solenoid.jl — rather than hand-listed in
# one distant table: the one-place list fell behind twice (2026-08-05 U11-3:
# the thin kinds; 2026-08-05_b U15-7: :solenoid one commit later), each miss
# turning a placement override into a written-reported-never-read no-op.
# `_fold_named_strengths` verifies its caller's kind against these at every
# construction, so an undeclared fold site fails its own @element_spec
# example at include time — the loudest tripwire a registration can have.
const _FOLDED_NAMED_STRENGTHS = Dict{Symbol,Any}()
# Which tuple pair a kind folds into (kn/ks unless declared otherwise); the
# guard's rejection message points at the right one.
const _FOLDED_TUPLE_KEYS = Dict{Symbol,Tuple{Symbol,Symbol}}()

_FOLDED_NAMED_STRENGTHS[:quadrupole] = _QUAD_NAMED
_FOLDED_NAMED_STRENGTHS[:sextupole] = _SEXT_NAMED
_FOLDED_NAMED_STRENGTHS[:octupole] = _OCT_NAMED
_FOLDED_NAMED_STRENGTHS[:sbend] = _BEND_NAMED
_FOLDED_NAMED_STRENGTHS[:multipole] = _MULTIPOLE_NAMED

"""
Element type of the folded strength tuples, promoted over **both** spellings
before either is read.

Computed up front rather than growing the vector's type as it goes: `k1` and
`kn` fold into one tuple, and a differentiable strength must survive whichever
way it was written. `Float64[...]` here is what silently discarded a dual and
made `QuadrupoleSpec(kn=(0.0, dual))` come back as a plain magnet.
"""
function _strength_eltype(named, d, nkey, skey)
    T = Float64
    for key in (nkey, skey), v in get(d, key, ())
        T = promote_type(T, typeof(float(v)))
    end
    for (nsym, ssym, _) in named, sym in (nsym, ssym)
        haskey(d, sym) && (T = promote_type(T, typeof(float(d[sym]))))
    end
    return T
end


"""
    _fold_named_strengths(named, kwargs; nkey, skey, kind)

Fold named strength keywords into the positional `kn`/`ks` tuples that
`_lattice_magnet` reads.

`named` lists `(normal, skew, order)` triples, where `order` is the `n` of
`K_n` and therefore lands at index `n+1` (Section 4.1 indexing). Setting the
same order both ways is contradictory rather than merely redundant, so it
throws instead of letting one spelling silently win.

`kind` is REQUIRED, and is this function's self-declaring tripwire
(2026-08-05_b audit, U15-7): the beam-line override guard's tables
(`_FOLDED_NAMED_STRENGTHS` / `_FOLDED_TUPLE_KEYS`, beam_line.jl) were
hand-maintained against this function's call sites and fell behind twice —
the thin kinds, then `:solenoid` one commit later — each miss turning a
per-occurrence override into a written-reported-never-read no-op. Every fold
site now names its kind and the fold verifies the guard declares it, so an
undeclared folding kind fails at its FIRST construction, in any test or
example that builds it, rather than passing silently. The registry's
example-compiles check constructs every kind, which is what makes this a
coverage tripwire rather than a hope.
"""
function _fold_named_strengths(named, kwargs; nkey::Symbol=:kn, skey::Symbol=:ks,
                               kind::Symbol)
    if !isempty(named)
        declared = get(_FOLDED_NAMED_STRENGTHS, kind, nothing)
        declared === named || throw(ArgumentError(
            "element kind $(kind) folds named strengths, but the beam-line " *
            "override guard does not declare it (or declares a different " *
            "strength list): add :$(kind) => the same named-strength constant " *
            "to _FOLDED_NAMED_STRENGTHS in beam_line.jl, so placement " *
            "overrides of its named strengths are rejected instead of " *
            "silently never read (U15-7)"))
        declared_keys = get(_FOLDED_TUPLE_KEYS, kind, (:kn, :ks))
        declared_keys == (nkey, skey) || throw(ArgumentError(
            "element kind $(kind) folds into ($(nkey), $(skey)) but the " *
            "override guard's _FOLDED_TUPLE_KEYS says $(declared_keys); " *
            "align them so the rejection message names the real tuple (U15-7)"))
    end
    d = Dict{Symbol,Any}(kwargs)
    T = _strength_eltype(named, d, nkey, skey)
    kn = T[T(float(v)) for v in get(d, nkey, ())]
    ks = T[T(float(v)) for v in get(d, skey, ())]
    for (nsym, ssym, order) in named,
        (sym, vec, which) in ((nsym, kn, String(nkey)), (ssym, ks, String(skey)))

        haskey(d, sym) || continue
        i = order + 1
        if i <= length(vec) && vec[i] != 0
            throw(ArgumentError(
                "$(sym) and a nonzero $(which)[$(i)] both set the same strength; " *
                "give one or the other"))
        end
        while length(vec) < i
            push!(vec, zero(T))
        end
        vec[i] = T(float(d[sym]))
        delete!(d, sym)
    end
    isempty(kn) || (d[nkey] = Tuple(kn))
    isempty(ks) || (d[skey] = Tuple(ks))
    return d
end

# Friendly constructors follow the house pattern: an abstract type carrying a
# keyword constructor, so metadata queries such as `parameter_schema` dispatch
# on the type. `compile_runtime` needs no methods here -- it routes through
# `runtime_type`, which every kind maps to `LatticeMagnet`.
for (kind, ctor, named) in ((:drift, :DriftSpec, :_NO_NAMED),
                            (:quadrupole, :QuadrupoleSpec, :_QUAD_NAMED),
                            (:sextupole, :SextupoleSpec, :_SEXT_NAMED),
                            (:octupole, :OctupoleSpec, :_OCT_NAMED),
                            (:multipole, :MultipoleSpec, :_MULTIPOLE_NAMED))
    @eval begin
        abstract type $ctor end
        $ctor(; kwargs...) = ElementSpec{$(QuoteNode(kind))}(
            _spec_params(; _fold_named_strengths($named, kwargs;
                                                 kind=$(QuoteNode(kind)))...))
    end
end

"""
Friendly constructor for `ElementSpec{:drift}`: a field-free drift of length
`L`, exact in `(1+delta)`; the reference frame may be curved. See
`element_help(:drift)` for the parameter schema.
"""
DriftSpec

"""
Friendly constructor for `ElementSpec{:quadrupole}`: a thick quadrupole of
length `L` and strength `k1`, tracked as exact drifts interleaved with
multipole kicks. See `element_help(:quadrupole)` for the parameter schema.
"""
QuadrupoleSpec

"""
Friendly constructor for `ElementSpec{:sextupole}`: a thick sextupole of
length `L` and strength `k2`, tracked as exact drifts interleaved with
multipole kicks. See `element_help(:sextupole)` for the parameter schema.
"""
SextupoleSpec

"""
Friendly constructor for `ElementSpec{:octupole}`: a thick octupole of length
`L` and strength `k3`, tracked as exact drifts interleaved with multipole
kicks. See `element_help(:octupole)` for the parameter schema.
"""
OctupoleSpec

"""
Friendly constructor for `ElementSpec{:multipole}`: a thick general multipole
with strengths `kn`/`ks` (`kn[i] = K_{i-1}`, thick strengths, not the thin
family's integrated `K_n L`). See `element_help(:multipole)` for the parameter
schema.
"""
MultipoleSpec

"""
Friendly constructor for `ElementSpec{:sbend}`: an exact sector bend, where
`angle` sets both the frame curvature and the dipole field, `h = b0 =
angle / L`, with pole-face angles and fringe fields available. See
`element_help(:sbend)` for the parameter schema.
"""
abstract type SBendSpec end

"""
Friendly constructor for a rectangular bend, built as an `ElementSpec{:sbend}`
with `angle/2` added to each pole-face angle -- MAD-X's exact RBEND face
conversion, a construction convenience over the validated sector-bend map.
See `element_help(:sbend)` for the parameter schema.

**`L` is the ARC length, as it is for every Octopus element** — the survey,
`s_positions`, and `total_length` are all sums of `L`, and this kind is no
exception. This deliberately does **not** match MAD-X's default RBEND length
semantics: with MAD-X's `RBARC=true` (its default) the `L` you write in a
MAD-X lattice is the **chord**, and MAD-X surveys the computed arc (measured
on 5.03.06: `rbend, l=2, angle=0.5` surveys `s = 2.020986251`). Porting a
MAD-X RBEND, either convert the length yourself or hand the chord over
directly:

    RBendSpec(chord=2.0, angle=0.5)    # MAD-X RBARC semantics: L = chord·(θ/2)/sin(θ/2)
    RBendSpec(L=2.0209862…, angle=0.5) # the same magnet, by its arc

`chord` and `L` are mutually exclusive; `chord` is folded into `L` at
construction and never stored, so it cannot be overridden on a placement
(the guard names the conversion). The choice of arc-`L` is a feature, not an
accident: one length rule for every element is what keeps the survey a plain
`L`-sum, and it is pinned externally against a true MAD-X RBEND by the
`MADXSurveyConsistencyContract` fixture `rbend_chord`.
"""
abstract type RBendSpec end

# An RBEND is a sector bend whose faces are parallel to each other rather than
# perpendicular to the design orbit, which is the same magnet with `angle/2`
# added to each pole-face angle. MAD-X converts it exactly this way, so RBEND
# stays a construction convenience over the validated sector-bend map rather
# than a second bend implementation. `e1`/`e2` remain available and are taken as
# *additional* face angles on top of the half-angle, matching MAD-X.
function RBendSpec(; kwargs...)
    d = Dict{Symbol,Any}(kwargs)
    haskey(d, :angle) || throw(ArgumentError("RBendSpec needs angle"))
    if haskey(d, :chord)
        haskey(d, :L) && throw(ArgumentError(
            "give either `L` (the arc length) or `chord` (MAD-X RBARC \
             semantics, folded to L = chord * (angle/2) / sin(angle/2)), \
             not both"))
        half = float(d[:angle]) / 2
        chord = float(pop!(d, :chord))
        d[:L] = iszero(half) ? chord : chord * half / sin(half)
    end
    haskey(d, :L) || throw(ArgumentError(
        "RBendSpec needs `L` (arc length) or `chord` (MAD-X RBARC semantics)"))
    half = float(d[:angle]) / 2
    d[:e1] = float(get(d, :e1, 0.0)) + half
    d[:e2] = float(get(d, :e2, 0.0)) + half
    return SBendSpec(; (Symbol(k) => v for (k, v) in d)...)
end

# `angle` is the design-orbit spelling: one number sets both the frame curvature
# and the field, h = b0 = angle / L, which is what a lattice file means by a
# bend angle. Giving h and b0 directly stays available for the case they differ
# (a bend off its design orbit), but giving both spellings is contradictory.
function SBendSpec(; kwargs...)
    d = _fold_named_strengths(_BEND_NAMED, kwargs; kind=:sbend)
    if haskey(d, :angle)
        (haskey(d, :h) || haskey(d, :b0)) && throw(ArgumentError(
            "angle and h/b0 both set the bend geometry; give one or the other"))
        haskey(d, :L) || throw(ArgumentError("angle needs L, to give h = b0 = angle / L"))
        L = float(d[:L])
        L == 0 && throw(ArgumentError("angle needs a nonzero L"))
        d[:b0] = d[:h] = float(d[:angle]) / L
        delete!(d, :angle)
    end
    return ElementSpec{:sbend}(_spec_params(; d...))
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
    parameters = merge(_LATTICE_BODY_PARAMS, (
        L=ParamMeta(required=true, meaning="arc length in metres"),
        nst=ParamMeta(default=1, meaning="integration steps; a PURE drift is exact and ignores them, but the shared lattice-magnet runtime reads body strengths on every kind, so a drift given kn/ks content splits and steps like any magnet"),
        integrator_order=ParamMeta(default=2, meaning="unused by a pure drift, which is exact; splits a drift carrying body strengths, as on any magnet"),
        tracking_method=ParamMeta(default=Symplectic6DMap(), meaning="per-element tracking method"),
        _PLACEMENT_PARAMS...,
    ))
    example = DriftSpec(L=0.5)
    construction_help = "Friendly constructor: DriftSpec(; L, h=0, curved=nothing, nst=1, integrator_order=2, tracking_method=Symplectic6DMap()). Exact in (1+delta); h != 0 gives a curved drift. nst and integrator_order are accepted for interface uniformity; a pure drift is exact and ignores them, while a drift given body strengths splits like any magnet. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel." * _LATTICE_BODY_HELP
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
    parameters = merge(_LATTICE_BODY_PARAMS, (
        L=_COMMON_PARAMS.L,
        k1=ParamMeta(default=0, meaning="normal quadrupole strength K1; the normal way to build a quadrupole. Folded into kn[2] at construction"),
        k1s=ParamMeta(default=0, meaning="skew quadrupole strength; folded into ks[2] at construction"),
        kn=ParamMeta(default=(), meaning="normal strengths as a positional tuple; index i holds K_{i-1}, so kn[2] is K1. Use it for measured field errors on top of k1. Setting k1 and a nonzero kn[2] together throws"),
        ks=ParamMeta(default=(), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        x_offset=_COMMON_PARAMS.x_offset,
        y_offset=_COMMON_PARAMS.y_offset,
        z_offset=_COMMON_PARAMS.z_offset,
        x_pitch=_COMMON_PARAMS.x_pitch,
        y_pitch=_COMMON_PARAMS.y_pitch,
        tilt=_COMMON_PARAMS.tilt,
        misalign_convention=_COMMON_PARAMS.misalign_convention,
        tracking_method=_COMMON_PARAMS.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
        # Declared explicitly because this kind enumerates the common keys
        # instead of splatting `_PLACEMENT_PARAMS`; without it, naming an
        # ordinary lattice element warned that the value was NOT being
        # tracked (2026-08-05_b audit, U15-12).
        name=_PLACEMENT_PARAMS.name,
    ))
    example = QuadrupoleSpec(L=0.3, k1=1.2)
    construction_help = "Friendly constructor: QuadrupoleSpec(; L, k1=0, k1s=0, kn=(), ks=(), nst=1, integrator_order=2, fringe=:none, va=0, vs=0, highest_fringe=0, kill_ent_fringe=false, kill_exi_fringe=false, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The misalignment keywords displace the magnet body rigidly about the element centre; bends are handled through the survey, which uses h and never b0. Normal use is k1, with k1s for the skew partner. kn/ks remain available for field errors: kn[i] is K_{i-1}, so kn[2] is K1, and setting both k1 and a nonzero kn[2] throws. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel." * _LATTICE_BODY_HELP
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
    parameters = merge(_LATTICE_BODY_PARAMS, (
        L=_COMMON_PARAMS.L,
        k2=ParamMeta(default=0, meaning="normal sextupole strength K2; the normal way to build a sextupole. Folded into kn[3] at construction"),
        k2s=ParamMeta(default=0, meaning="skew sextupole strength; folded into ks[3] at construction"),
        kn=ParamMeta(default=(), meaning="normal strengths as a positional tuple; index i holds K_{i-1}, so kn[3] is K2. Use it for measured field errors on top of k2. Setting k2 and a nonzero kn[3] together throws"),
        ks=ParamMeta(default=(), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        x_offset=_COMMON_PARAMS.x_offset,
        y_offset=_COMMON_PARAMS.y_offset,
        z_offset=_COMMON_PARAMS.z_offset,
        x_pitch=_COMMON_PARAMS.x_pitch,
        y_pitch=_COMMON_PARAMS.y_pitch,
        tilt=_COMMON_PARAMS.tilt,
        misalign_convention=_COMMON_PARAMS.misalign_convention,
        tracking_method=_COMMON_PARAMS.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
        # Declared explicitly because this kind enumerates the common keys
        # instead of splatting `_PLACEMENT_PARAMS`; without it, naming an
        # ordinary lattice element warned that the value was NOT being
        # tracked (2026-08-05_b audit, U15-12).
        name=_PLACEMENT_PARAMS.name,
    ))
    example = SextupoleSpec(L=0.2, k2=12.0)
    construction_help = "Friendly constructor: SextupoleSpec(; L, k2=0, k2s=0, kn=(), ks=(), nst=1, integrator_order=2, fringe=:none, va=0, vs=0, highest_fringe=0, kill_ent_fringe=false, kill_exi_fringe=false, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The misalignment keywords displace the magnet body rigidly about the element centre; bends are handled through the survey, which uses h and never b0. Normal use is k2, with k2s for the skew partner. kn/ks remain available for field errors: kn[i] is K_{i-1}, so kn[3] is K2, and setting both k2 and a nonzero kn[3] throws. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel." * _LATTICE_BODY_HELP
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
    parameters = merge(_LATTICE_BODY_PARAMS, (
        L=_COMMON_PARAMS.L,
        k3=ParamMeta(default=0, meaning="normal octupole strength K3; the normal way to build an octupole. Folded into kn[4] at construction"),
        k3s=ParamMeta(default=0, meaning="skew octupole strength; folded into ks[4] at construction"),
        kn=ParamMeta(default=(), meaning="normal strengths as a positional tuple; index i holds K_{i-1}, so kn[4] is K3. Use it for measured field errors on top of k3. Setting k3 and a nonzero kn[4] together throws"),
        ks=ParamMeta(default=(), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        x_offset=_COMMON_PARAMS.x_offset,
        y_offset=_COMMON_PARAMS.y_offset,
        z_offset=_COMMON_PARAMS.z_offset,
        x_pitch=_COMMON_PARAMS.x_pitch,
        y_pitch=_COMMON_PARAMS.y_pitch,
        tilt=_COMMON_PARAMS.tilt,
        misalign_convention=_COMMON_PARAMS.misalign_convention,
        tracking_method=_COMMON_PARAMS.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
        # Declared explicitly because this kind enumerates the common keys
        # instead of splatting `_PLACEMENT_PARAMS`; without it, naming an
        # ordinary lattice element warned that the value was NOT being
        # tracked (2026-08-05_b audit, U15-12).
        name=_PLACEMENT_PARAMS.name,
    ))
    example = OctupoleSpec(L=0.1, k3=300.0)
    construction_help = "Friendly constructor: OctupoleSpec(; L, k3=0, k3s=0, kn=(), ks=(), nst=1, integrator_order=2, fringe=:none, va=0, vs=0, highest_fringe=0, kill_ent_fringe=false, kill_exi_fringe=false, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The misalignment keywords displace the magnet body rigidly about the element centre; bends are handled through the survey, which uses h and never b0. Normal use is k3, with k3s for the skew partner. kn/ks remain available for field errors: kn[i] is K_{i-1}, so kn[4] is K3, and setting both k3 and a nonzero kn[4] throws. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel." * _LATTICE_BODY_HELP
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
    parameters = merge(_LATTICE_BODY_PARAMS, (
        L=_COMMON_PARAMS.L,
        k0=ParamMeta(default=0, meaning="normal dipole strength K0, i.e. a corrector kick; folded into kn[1] at construction"),
        k0s=ParamMeta(default=0, meaning="skew dipole strength; folded into ks[1] at construction"),
        k1=ParamMeta(default=0, meaning="normal quadrupole strength K1; folded into kn[2] at construction"),
        k1s=ParamMeta(default=0, meaning="skew quadrupole strength; folded into ks[2] at construction"),
        k2=ParamMeta(default=0, meaning="normal sextupole strength K2; folded into kn[3] at construction"),
        k2s=ParamMeta(default=0, meaning="skew sextupole strength; folded into ks[3] at construction"),
        k3=ParamMeta(default=0, meaning="normal octupole strength K3; folded into kn[4] at construction"),
        k3s=ParamMeta(default=0, meaning="skew octupole strength; folded into ks[4] at construction"),
        k4=ParamMeta(default=0, meaning="normal decapole strength K4; folded into kn[5] at construction"),
        k4s=ParamMeta(default=0, meaning="skew decapole strength; folded into ks[5] at construction"),
        k5=ParamMeta(default=0, meaning="normal dodecapole strength K5; folded into kn[6] at construction"),
        k5s=ParamMeta(default=0, meaning="skew dodecapole strength; folded into ks[6] at construction"),
        kn=ParamMeta(default=(), meaning="normal strengths of any length as a positional tuple; index i holds K_{i-1}. Use it for orders beyond K5 and for measured field errors. Setting a named strength and the matching nonzero kn entry together throws"),
        ks=ParamMeta(default=(), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        x_offset=_COMMON_PARAMS.x_offset,
        y_offset=_COMMON_PARAMS.y_offset,
        z_offset=_COMMON_PARAMS.z_offset,
        x_pitch=_COMMON_PARAMS.x_pitch,
        y_pitch=_COMMON_PARAMS.y_pitch,
        tilt=_COMMON_PARAMS.tilt,
        misalign_convention=_COMMON_PARAMS.misalign_convention,
        tracking_method=_COMMON_PARAMS.tracking_method,
        ref_tilt=_PLACEMENT_PARAMS.ref_tilt,
        # Declared explicitly because this kind enumerates the common keys
        # instead of splatting `_PLACEMENT_PARAMS`; without it, naming an
        # ordinary lattice element warned that the value was NOT being
        # tracked (2026-08-05_b audit, U15-12).
        name=_PLACEMENT_PARAMS.name,
    ))
    example = MultipoleSpec(L=0.2, k1=1.0, k2=5.0)
    construction_help = "Friendly constructor: MultipoleSpec(; L, k0=0, k0s=0, k1=0, k1s=0, k2=0, k2s=0, k3=0, k3s=0, k4=0, k4s=0, k5=0, k5s=0, kn=(), ks=(), nst=1, integrator_order=2, fringe=:none, va=0, vs=0, highest_fringe=0, kill_ent_fringe=false, kill_exi_fringe=false, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The misalignment keywords displace the magnet body rigidly about the element centre; bends are handled through the survey, which uses h and never b0. Named strengths run K0 (dipole corrector) through K5 (dodecapole), each folded into kn/ks at construction, so a decapole is k4 rather than four leading zeros. Orders beyond K5 and field errors use the positional tuples, where kn[i] is K_{i-1}. Setting a named strength and the matching nonzero kn entry together throws. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel." * _LATTICE_BODY_HELP
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
    parameters = merge(_LATTICE_BODY_PARAMS, (
        L=_COMMON_PARAMS.L,
        angle=ParamMeta(default=0, meaning="design-orbit bend angle in radians; sets h = b0 = angle / L at construction. The normal way to build a bend. Contradicts h/b0, so giving both throws"),
        h=ParamMeta(default=0, meaning="reference-frame curvature 1/rho; need not equal b0. Give h and b0 instead of angle when they differ"),
        k1=ParamMeta(default=0, meaning="normal quadrupole component of a combined-function bend; folded into kn[2] at construction"),
        k1s=ParamMeta(default=0, meaning="skew quadrupole component; folded into ks[2] at construction"),
        k2=ParamMeta(default=0, meaning="normal sextupole component of a combined-function bend; folded into kn[3] at construction"),
        k2s=ParamMeta(default=0, meaning="skew sextupole component; folded into ks[3] at construction"),
        kn=ParamMeta(default=(), meaning="normal multipole strengths as a positional tuple; index i holds K_{i-1}. Use it for orders beyond k2 and for field errors. Setting k1/k2 and the matching nonzero kn entry together throws"),
        ks=ParamMeta(default=(), meaning="skew partners of kn"),
        nst=_COMMON_PARAMS.nst,
        integrator_order=_COMMON_PARAMS.integrator_order,
        x_offset=_COMMON_PARAMS.x_offset,
        y_offset=_COMMON_PARAMS.y_offset,
        z_offset=_COMMON_PARAMS.z_offset,
        x_pitch=_COMMON_PARAMS.x_pitch,
        y_pitch=_COMMON_PARAMS.y_pitch,
        tilt=ParamMeta(default=0, meaning="misalignment: roll of the magnet BODY about the longitudinal axis, in radians, with the design orbit unchanged. An error. This is Bmad's `roll` and MAD-X's `EALIGN, dpsi` -- it is NOT MAD-X's `sbend, tilt=`, which rolls the design orbit and is `ref_tilt` here"),
        ref_tilt=ParamMeta(default=0, meaning="roll of the DESIGN ORBIT plane about the longitudinal axis, in radians: the reference trajectory itself bends in a rotated plane. A design choice, not an error, and the thing a body roll is not -- a vertical bend is ref_tilt = pi/2. Bmad's `ref_tilt`, and what MAD-X spells `sbend, tilt=`. The magnet a misalignment displaces is the rolled one; which axes that error is measured along follows misalign_convention, :bmad taking the rolled frame and :madx the unrolled design frame, and the two differ only when a roll and a misalignment are both nonzero"),
        misalign_convention=_COMMON_PARAMS.misalign_convention,
        # Declared explicitly because this kind enumerates the common keys
        # instead of splatting `_PLACEMENT_PARAMS` (2026-08-05_b audit, U15-12).
        name=_PLACEMENT_PARAMS.name,
        tracking_method=_COMMON_PARAMS.tracking_method,
    ))
    example = SBendSpec(L=1.0, angle=0.05)
    construction_help = "Friendly constructor: SBendSpec(; L, angle=0, h=0, b0=0, k1=0, k1s=0, k2=0, k2s=0, kn=(), ks=(), e1=0, e2=0, fint1=0, fint2=0, hgap1=0, hgap2=0, hface1=0, hface2=0, bend_fringe=true, bend_model=:exact, curved=nothing, curved_order=8, wedge_coeff=(1,2), nst=1, integrator_order=2, fringe=:none, highest_fringe=0, kill_ent_fringe=false, kill_exi_fringe=false, x_offset=0, y_offset=0, z_offset=0, x_pitch=0, y_pitch=0, tilt=0, ref_tilt=0, misalign_convention=:bmad, tracking_method=Symplectic6DMap()). The misalignment keywords displace the magnet body rigidly about the element centre; bends are handled through the survey, which uses h and never b0. Normal use is angle, which sets h = b0 = angle / L; give h and b0 directly when the frame curvature and the field differ, but not alongside angle. Combined-function bends take k1/k2 (k1s/k2s skew), with kn/ks for higher orders and field errors. TILT VERSUS REF_TILT: tilt rolls the magnet body and is an error (Bmad roll, MAD-X EALIGN dpsi); ref_tilt rolls the design orbit plane and is a design choice (Bmad ref_tilt, MAD-X `sbend, tilt=`). A vertical bend is ref_tilt=pi/2. Translating a MAD-X bend tilt into Octopus tilt is the common mistake and gives a machine error where the lattice meant geometry. RBendSpec(; L, angle, ...) builds this same kind with parallel pole faces: it adds angle/2 to each of e1/e2 (the MAD-X RBEND face conversion) and forwards everything else to SBendSpec, so every contract and parameter here applies to it. RBendSpec's L is the ARC length like every Octopus element -- NOT MAD-X's default RBEND semantics, where the written L is the chord (RBARC=true) and the surveyed arc is longer; porting a MAD-X RBEND, give RBendSpec(chord=..., angle=...) and the arc L = chord*(angle/2)/sin(angle/2) is computed at construction (chord and L are mutually exclusive; chord is folded and never stored). Pinned against a true MAD-X RBEND by the MADXSurveyConsistencyContract fixture rbend_chord. Placement (every kind, consumed by the compile-time misalignment and design-roll wraps): x_offset, y_offset, z_offset [m], x_pitch, y_pitch, tilt, ref_tilt [rad], misalign_convention (:bmad or :madx). name: an optional label, carried into beam-line provenance paths and diagnostics, never read by a tracking kernel." * _LATTICE_BODY_HELP
end

# RBendSpec constructs an ElementSpec{:sbend}, so its metadata IS the sector
# bend's. Registered as a friendly alias so type-level queries answer with the
# validated sbend contracts instead of silently missing the registry.
register_friendly_alias!(RBendSpec, :sbend)
