"""
Twiss benchmark against MAD-X `twiss` (stage 8, benchmark A of the twiss and
dispersion campaign; design note docs/design/twiss_dispersion_analysis.md
staging item 8; theory 12.2 item 3, MAD-X half). The
external tool is NOT run here: this script reads only the committed table
validation/reference/twiss_madx_5.03.06.tsv written by
validation/generate_madx_twiss_reference.jl, converts every exported MAD-X
one-turn map into Octopus coordinates, runs `analyze` on the CONVERTED map and
compares the result with MAD-X's own periodic optics row and summ tunes.

Reference model
---------------
MAD-X 5.03.06 `twiss, rmatrix` (periodic) and `twiss, betx=1, bety=1, rmatrix`
(initial condition) per fixture at the pinned beam
`beam, mass=0.93827208943, charge=1, energy=3.0;` (beta0 = 0.9498330546994187,
gamma0 = 3.1973667700405533, both re-read from the table and pinned at 1e-12).
Conversion law (recorded in the stage 8 benchmark A section of
docs/history/twiss_dispersion_analysis_history.md, applied by the shared module's
`convert_map(:madx, ...)`):
    M_oct = Sh(-C/gamma0^2) J0 M_madx J0^-1,  J0 = diag(1,1,1,1,beta0,1/beta0),
Sh(u) the identity except entry (5,6) = u. The transverse 4x4 block is
convention-free, so tunes, Edwards-Teng R and the ET mode Twiss carry no
conversion; only the dispersion columns (eta_oct = beta0 * DX) and the map
witnesses use the converted map. MAD-X's r11..r22 are the Edwards-Teng R of
form 1 (`form1.R`, no transpose); betx/alfx/bety/alfy are the ET MODE
functions, not the Mais-Ripken projections.

Error metric
------------
Per row |octopus - madx|, judged against tol * max(|madx|, 1) for the relative
classes (the floor 1 keeps a legitimately zero external value, e.g. dx on a
bend-free cell, from turning a 1e-17 residual into a red row) and against the
absolute tolerance for cos mu / sin mu. Layers:
  A0 witnesses (abort before A1 on any failure): the S0 drift (5,6) as a
     formula in the table's own beta0/gamma0/L; converted S0 vs the Octopus
     bare drift map (1e-14); the shear vs the module's slip (1e-12 rel); the
     6D partnership u = -C/gamma0^2 re-derived from the header; the U2 FD
     momentum witness FD/DX vs beta0 (1e-8, the O(deltap^2) truncation); the
     sign of RE51/RE52 vs Octopus M51/M52 on U2; the periodic and initial
     maps agree to 1e-14 wherever both exist.
  A1 convention layer (U1, U2, K1, K2): analyze on the converted map vs the
     periodic row; cos mu, sin mu (TOL-A abs 1e-13), ET mode beta/alpha
     (TOL-A rel 1e-12; physical.beta printed beside them on uncoupled cells),
     form1.R entry by entry (TOL-A) only on K1/K2 where rule Z's branch is
     separated (TW-MADX-BRANCH prints t, det U, Delta = t^2 + det U, lambda,
     g on every fixture), lambda = 1/sqrt(1 + det R_madx) vs the Sagan-Rubin
     gamma of the exported map (1e-12), eta vs beta0*DX (TOL-B rel 1e-12).
  A2 model layer (U1, U2, K1, K2): Octopus `bare_map` of the lattice cell at
     nst in {4,8,16,32,64}, integrator_order 4, vs the converted MAD-X map,
     max |entry|; gate = fitted convergence order 4.0 +- 0.3 over the five
     points plus the nst=64 residual under the frozen cap (stage 8 decision D6, history section).
  A3 the rolled equal-tune FODO R(theta), theta in {0, 0.01, 0.1, pi/8, pi/4},
     and the detuned controls Rd(1e-3), Rd(1e-6): the EXPORTED map's cos mu
     and its rotation identity M(theta) = Rt(theta) M(0) Rt(theta)' at TOL-F
     (1e-10); MAD-X's periodic tunes as a DIRECTIONAL SENTINEL (right at
     theta = 0 and on Rd, wrong by more than 1e-4 at 0.01, 0.1, pi/8, absent
     at pi/4); Octopus's refusal as REASON SYMBOLS (status :passed, tunes
     empty, beta/alpha/gamma/ET-R reason :cluster_unresolved, cluster
     :definite) on both the converted MAD-X map and the lattice map. No
     Octopus tune is asserted on the degenerate cell. Rd(1e-3) is the gated
     control (its tunes at TOL-F); Rd(1e-6) is RECORDED only: at a 3.4e-7
     split MAD-X's periodic tune leaves its own exported map's eigenvalue by
     1.8e-11 in q (the approach to the TWCPIN failure) and Octopus reports
     status :failed (frame symplecticity at the 1/split conditioning).
  A4 free cross-code row (recorded): MAD-X vs xtrack on K1 (q, ET beta/alpha,
     g_edw_teng) if validation/reference/xsuite_twiss_xtrack_0.112.0.tsv exists.
  A5 printed seed row (recorded): M(theta) vs V1(-tan theta I) M(0) V1^-1 and
     r11..r22 vs -tan(theta) I_2.

Tolerance
---------
TOL-A 1e-12 relative (beta, alpha, R entries), 1e-13 absolute (cos mu, sin mu);
TOL-B 1e-12 relative (beta0*DX); TOL-E fitted order 4.0 +- 0.3 and the nst=64
cap (frozen below with its provenance); TOL-F 1e-10 absolute (degenerate cell).

Configuration
-------------
`TwissDispersionAnalysis(strict=false, scaling=:none)`; results read through
`physical.*` and the form-1 objects of `edwards_teng_normalizer` (the presented
form is asserted to be 1 on K1/K2); every read branches on `is_determined`.

Fixtures
--------
S0, W2 (witness only), U1, U2, K1, K2, R_0, R_0.01, R_0.1, R_pi8, R_pi4,
Rd_1e-3, Rd_1e-6 of validation/twiss_benchmark_cells.jl (the stage 8 fixture set, described in that module header).

Inputs/Outputs (under `result/`)
-------------------------------
Input: validation/reference/twiss_madx_5.03.06.tsv (and, for A4 only, the
Xsuite table beside it). Output: result/twiss_madx_benchmark.tsv, one row per
printed line (layer, fixture, quantity, octopus, madx, diff, tol, class, status).

Run
---
    julia --project=. validation/twiss_madx_benchmark.jl

Environment
-----------
    CUDA_VISIBLE_DEVICES=""        (script mode; the AVX2 arm adds
                                    OPENBLAS_CORETYPE=Haswell and julia -C haswell)
Overrides:
    OCTOPUS_STAGE8_DEFECT   none (default) | drop_J (J0 = I in the conversion) |
                            transpose_R (form1.R transposed before the R rows);
                            each turns a named TW-MADX line red (stage 8 decision D16, history section).
"""

include(joinpath(@__DIR__, "twiss_benchmark_cells.jl"))   # guards Octopus itself
using .Octopus
using LinearAlgebra
using Printf

const MADX_TABLE = joinpath(@__DIR__, "reference", "twiss_madx_5.03.06.tsv")
const XSUITE_TABLE = joinpath(@__DIR__, "reference", "xsuite_twiss_xtrack_0.112.0.tsv")
const OUT_TSV = normpath(joinpath(@__DIR__, "..", "result", "twiss_madx_benchmark.tsv"))
const DEFECT = Symbol(get(ENV, "OCTOPUS_STAGE8_DEFECT", "none"))
DEFECT in (:none, :drop_J, :transpose_R) ||
    error("OCTOPUS_STAGE8_DEFECT must be none, drop_J or transpose_R, got $(DEFECT)")

# tolerance classes (stage 8 TOL-A..F with their measured floors: history section, benchmark A)
const TOL_A_REL = 1e-12          # beta, alpha, gamma, R entries
const TOL_A_ABS = 1e-13          # cos mu, sin mu
const TOL_B_REL = 1e-12          # beta0 * DX
const TOL_F_ABS = 1e-10          # the degenerate rolled cell
const TOL_MAP = 1e-14            # map-vs-map witnesses
const TOL_PIN = 1e-12            # header pins, shear, lambda vs gamma_SR
const TOL_FD = 1e-8              # the U2 finite-difference momentum witness
const ORDER_TARGET = 4.0
const ORDER_BAND = 0.3
const NST_LADDER = (4, 8, 16, 32, 64)
# nst=64 residual cap of the model ladder: ten times the maximum measured on
# the first passing native run of this script (2026-09-15, sapphirerapids).
# The four TW-MADX-MODEL <fixture> 64 residuals of that run were
#   U1 2.0827214952667816e-10, U2 7.8839690331733436e-10,
#   K1 3.4806602045023283e-12, K2 7.8473405551449105e-10,
# recorded in docs/history/twiss_dispersion_analysis_history.md, section
# "2026-09-15: stage 8, benchmark A" (the tracked record; the AVX2 arm
# reproduces them to ulp level). Upper bound only, the order fit is the gate.
const NST64_MEASURED_MAX = 7.8839690331733436e-10
const NST64_CAP = 10 * NST64_MEASURED_MAX

fmt(x::Real) = @sprintf("%.17g", Float64(x))
fmt(x::Integer) = string(x)
fmt(x::AbstractString) = String(x)
fmt(x) = string(x)

# ---------------------------------------------------------------- the table
const TABLE = read_reference_table(MADX_TABLE)
const COLS = TABLE.columns
const NROWS = length(COLS["fixture"])
cellf(col::AbstractString, i::Integer) = parse(Float64, COLS[col][i])

"Row index of (fixture, file) or nothing."
function row_index(fixture::AbstractString, file::AbstractString)
    for i in 1:NROWS
        COLS["fixture"][i] == fixture && COLS["file"][i] == file && return i
    end
    return nothing
end

"The 6x6 MAD-X map re11..re66 of table row i, as printed."
function table_map(i::Integer)
    M = zeros(6, 6)
    for a in 1:6, b in 1:6
        M[a, b] = cellf("re$(a)$(b)", i)
    end
    return M
end

table_optics(i) = (betx=cellf("betx", i), alfx=cellf("alfx", i), bety=cellf("bety", i),
                   alfy=cellf("alfy", i),
                   R=[cellf("r11", i) cellf("r12", i); cellf("r21", i) cellf("r22", i)],
                   D=[cellf("dx", i), cellf("dpx", i), cellf("dy", i), cellf("dpy", i)],
                   q1=cellf("q1", i), q2=cellf("q2", i))
table_beam(i) = (beta0=cellf("beta0", i), gamma0=cellf("gamma0", i), C=cellf("C", i))

# ---------------------------------------------------------------- the rows
const ROWS = NamedTuple{(:layer, :fixture, :quantity, :octopus, :external, :diff, :tol, :class, :status),
                        Tuple{String,String,String,Float64,Float64,Float64,Float64,String,String}}[]
const RATIOS = Float64[]       # diff / bound of every gated row, for the digest's worst ratio

function record!(layer, fixture, quantity, oct, ext, diff, tol, class, status)
    push!(ROWS, (layer=String(layer), fixture=String(fixture), quantity=String(quantity),
                 octopus=Float64(oct), external=Float64(ext), diff=Float64(diff), tol=Float64(tol),
                 class=String(class), status=String(status)))
end

"Gated comparison. class in (\"TOL-A\", \"TOL-B\", \"TOL-F\", ...); relative when rel=true."
function compare_row(layer, fixture, quantity, oct::Real, ext::Real, tol::Real, class; rel::Bool=true)
    diff = abs(Float64(oct) - Float64(ext))
    bound = rel ? tol * max(abs(Float64(ext)), 1.0) : tol
    status = (isfinite(diff) && diff <= bound) ? "PASS" : "FAIL"
    println("TW-MADX ", fixture, " ", quantity, " ", fmt(oct), " ", fmt(ext), " ", fmt(diff), " ",
            fmt(tol), " ", class, " ", status)
    record!(layer, fixture, quantity, oct, ext, diff, tol, class, status)
    push!(RATIOS, bound > 0 ? diff / bound : (diff == 0 ? 0.0 : Inf))
    return status == "PASS"
end

# ---------------------------------------------------------------- printed lines
function witness_row(name, value::Real, expected::Real, tol::Real; rel::Bool=false, fixture="witness")
    diff = abs(Float64(value) - Float64(expected))
    bound = rel ? tol * max(abs(Float64(expected)), eps()) : tol
    status = (isfinite(diff) && diff <= bound) ? "PASS" : "FAIL"
    println("TW-MADX-WITNESS ", name, " ", fmt(value), " ", fmt(expected), " ", fmt(diff), " ", status)
    record!("A0", fixture, name, value, expected, diff, tol, rel ? "witness-rel" : "witness-abs", status)
    push!(RATIOS, bound > 0 ? diff / bound : (diff == 0 ? 0.0 : Inf))
    return status == "PASS"
end

function recorded_row(layer, fixture, quantity, oct::Real, ext::Real)
    diff = abs(Float64(oct) - Float64(ext))
    println("TW-MADX-RECORDED ", fixture, " ", quantity, " ", fmt(oct), " ", fmt(ext), " ", fmt(diff))
    record!(layer, fixture, quantity, oct, ext, diff, NaN, "recorded", "RECORDED")
    return diff
end

function recorded_note(layer, fixture, quantity, text::AbstractString)
    println("TW-MADX-RECORDED ", fixture, " ", quantity, " ", text)
    record!(layer, fixture, quantity, NaN, NaN, NaN, NaN, "recorded", "RECORDED")
end

"A boolean assertion printed as a witness with value 1/0 and expected 1."
assert_row(name, ok::Bool; fixture="witness", layer="A0") =
    witness_row(name, ok ? 1.0 : 0.0, 1.0, 0.0; fixture=fixture)

# ---------------------------------------------------------------- 4x4 algebra
adj2(B::AbstractMatrix) = [B[2, 2] -B[1, 2]; -B[2, 1] B[1, 1]]   # symplectic conjugate of a 2x2
Rt(theta::Real) = kron([cos(theta) -sin(theta); sin(theta) cos(theta)], Matrix{Float64}(I, 2, 2))
V1_form1(R::AbstractMatrix) = (1 / sqrt(1 + det(R))) * [Matrix{Float64}(I, 2, 2) adj2(R); -R Matrix{Float64}(I, 2, 2)]

"Rule Z operands of MAD-X twcpin on the 4x4 block: t, det U, Delta = t^2 + det U, R_madx, lambda, gamma_SR."
function branch_operands(M4::AbstractMatrix)
    A = M4[1:2, 1:2]; B = M4[1:2, 3:4]; Cm = M4[3:4, 1:2]; D = M4[3:4, 3:4]
    t = (tr(A) - tr(D)) / 2
    U = Cm + adj2(B)
    detU = det(U)
    Delta = detU + t^2
    R_madx = Delta > 0 && t != 0 ? -U / (t + sign(t) * sqrt(Delta)) : fill(NaN, 2, 2)
    lambda = Delta > 0 ? 1 / sqrt(1 + det(R_madx)) : NaN
    gamma_SR = Delta > 0 ? sqrt(0.5 + 0.5 * abs(t) / sqrt(Delta)) : NaN
    return (t=t, detU=detU, Delta=Delta, R=R_madx, lambda=lambda, gamma_SR=gamma_SR)
end

function print_branch(fixture, M4::AbstractMatrix, R_table::AbstractMatrix)
    b = branch_operands(M4)
    lam_table = 1 / sqrt(1 + det(R_table))
    println("TW-MADX-BRANCH ", fixture, " ", fmt(b.t), " ", fmt(b.detU), " ", fmt(b.Delta), " ",
            fmt(lam_table), " ", fmt(b.gamma_SR))
    record!("A1", fixture, "branch_t", b.t, NaN, NaN, NaN, "branch", "RECORDED")
    record!("A1", fixture, "branch_detU", b.detU, NaN, NaN, NaN, "branch", "RECORDED")
    record!("A1", fixture, "branch_Delta", b.Delta, NaN, NaN, NaN, "branch", "RECORDED")
    return (b..., lambda_table=lam_table)
end

"cos and sin of the two transverse eigen-tunes of a 4x4 (or the 4x4 block of a 6x6) map, sorted by |v[1]|^2+|v[2]|^2 (x-like first)."
function block_cos_sin(M4::AbstractMatrix)
    E = eigen(Matrix{Float64}(M4[1:4, 1:4]))
    out = NamedTuple{(:cos, :sin, :xcontent, :modulus),NTuple{4,Float64}}[]
    for k in eachindex(E.values)
        lam = E.values[k]
        imag(lam) > 0 || continue
        v = E.vectors[:, k]
        push!(out, (cos=real(lam) / abs(lam), sin=imag(lam) / abs(lam),
                    xcontent=(abs2(v[1]) + abs2(v[2])) / sum(abs2, v), modulus=abs(lam)))
    end
    sort!(out; by=m -> -m.xcontent)
    return out
end

# ---------------------------------------------------------------- conversion
"The section 3 law on a table row; the D16 defect drop_J uses J0 = I (the :xsuite branch of convert_map, same shear)."
function converted_map(i::Integer)
    b = table_beam(i)
    code = DEFECT === :drop_J ? :xsuite : :madx
    return convert_map(code, table_map(i); beta0=b.beta0, gamma0=b.gamma0, C=b.C)
end

# ---------------------------------------------------------------- A0 witnesses
function witness_rows()
    ok = true
    # beam pin on every row (stage 8 decision D13: mass=0.93827208943, energy=3.0, |beta0 - pin| <= 1e-12)
    worst_b = 0.0; worst_g = 0.0
    for i in 1:NROWS
        worst_b = max(worst_b, abs(cellf("beta0", i) - BENCH_BETA0_PIN))
        worst_g = max(worst_g, abs(cellf("gamma0", i) - BENCH_GAMMA0_PIN))
    end
    ok &= witness_row("beta0_pin_max_residual_over_rows", worst_b, 0.0, BENCH_BETA0_ATOL)
    ok &= witness_row("gamma0_pin_max_residual_over_rows", worst_g, 0.0, 1e-11)
    # S0: the drift (5,6) as a formula in the table's own beta0, gamma0, L
    i0 = row_index("S0", "initial")
    i0 === nothing && error("A0: no S0 initial row in the table")
    b = table_beam(i0); M = table_map(i0)
    ok &= witness_row("S0_RE56_vs_L/(beta0^2gamma0^2)", M[5, 6], b.C / (b.beta0^2 * b.gamma0^2), TOL_PIN; rel=true)
    ok &= witness_row("S0_RE12_vs_L", M[1, 2], b.C, TOL_PIN; rel=true)
    Mconv = converted_map(i0)
    Moct = bare_map(S0())
    ok &= witness_row("S0_converted_vs_octopus_bare_maxentry", maximum(abs, Mconv - Moct), 0.0, TOL_MAP)
    ok &= witness_row("S0_converted_times_octopus_inverse_vs_I6", maximum(abs, Mconv * inv(Moct) - I), 0.0, TOL_MAP)
    u = -b.C / b.gamma0^2
    ok &= witness_row("S0_shear_header_vs_module_slip", u, -slip(b.C; gamma0=b.gamma0), TOL_PIN; rel=true)
    J = J0(b.beta0)
    ok &= witness_row("S0_partnership_bare_(5,6)_after_shear", (shear(u) * J * M * J0_inverse(b.beta0))[5, 6], 0.0, TOL_MAP)
    ok &= witness_row("S0_converted_(5,6)_equals_bare_compile", Mconv[5, 6], 0.0, TOL_MAP)
    # W2: the tilt sense. M = Rt(pi/4) M0 Rt(pi/4)' means Rt' M Rt is block diagonal.
    iw = row_index("W2", "initial")
    iw === nothing && error("A0: no W2 initial row in the table")
    Mw = table_map(iw)[1:4, 1:4]
    R4 = Rt(pi / 4)
    M0 = R4' * Mw * R4
    other = R4 * Mw * R4'
    offblock(X) = max(maximum(abs, X[1:2, 3:4]), maximum(abs, X[3:4, 1:2]))
    ok &= witness_row("W2_Rt'MRt_offdiagonal_blocks", offblock(M0), 0.0, TOL_PIN)
    # at theta = pi/4 the other sense is ALSO block diagonal (it is the roll by pi/2, F and D swapped):
    # only the focusing signs below discriminate; the two senses differ by the recorded amount
    recorded_row("A0", "W2", "other_sense_RtMRt'_vs_Rt'MRt_maxentry", maximum(abs, other - M0), 0.0)
    ok &= witness_row("W2_unrolled_M21_focusing_sign", M0[2, 1] < 0 ? 1.0 : 0.0, 1.0, 0.0)
    ok &= witness_row("W2_unrolled_M43_defocusing_sign", M0[4, 3] > 0 ? 1.0 : 0.0, 1.0, 0.0)
    recorded_row("A0", "W2", "madx_vs_octopus_bare_4x4_maxentry(nst=64_model)", maximum(abs, Mw - bare_map(W2())[1:4, 1:4]), 0.0)
    # U2: the momentum convention (FD dx/ddeltap vs beta0 * DX) and the row-5 sign
    ifd = row_index("U2", "fd_deltap"); ip = row_index("U2", "periodic")
    (ifd === nothing || ip === nothing) && error("A0: U2 fd_deltap or periodic row missing")
    FD = cellf("dx", ifd); DX = cellf("dx", ip); bp = table_beam(ip)
    ok &= witness_row("U2_FD/DX_vs_beta0_header", FD / DX, bp.beta0, TOL_FD)
    ok &= witness_row("U2_FD_vs_beta0*DX_relative", FD, bp.beta0 * DX, TOL_FD; rel=true)
    iu = row_index("U2", "initial")
    Mu = table_map(iu); Mc = converted_map(iu)
    Mo = bare_map(U2())
    for (r, c) in ((5, 1), (5, 2))
        ok &= witness_row("U2_sign_RE$(r)$(c)_vs_octopus_M$(r)$(c)", sign(Mu[r, c]), sign(Mo[r, c]), 0.0)
        recorded_row("A0", "U2", "RE$(r)$(c)_as_printed", Mu[r, c], Mu[r, c])
        recorded_row("A0", "U2", "converted_M$(r)$(c)_vs_octopus_M$(r)$(c)(nst=64_model)", Mc[r, c], Mo[r, c])
    end
    recorded_row("A0", "U2", "converted_vs_octopus_bare_maxentry(nst=64_model)", maximum(abs, Mc - Mo), 0.0)
    # 6D partnership (the stage 8 conversion law, history section): the converted MAD-X map's (5,6) must match the Octopus compile
    # mode in use (BARE); a task-compiled partner would sit C/gamma0^2 away. The witness is the
    # converted U2 (5,6) against bare_map(U2())[5,6] at the model cap NST64_CAP (measured (5,6) gap
    # 6.3272997952168453e-12 on 2026-09-15, under the U2 nst=64 max-entry residual 7.8839690331733436e-10);
    # the shift a wrong partner would give, C/gamma0^2, is recorded beside it.
    ok &= witness_row("U2_partnership_converted_(5,6)_vs_octopus_bare_(5,6)", Mc[5, 6], Mo[5, 6], NST64_CAP)
    recorded_row("A0", "U2", "partnership_wrong_partner_shift_C/gamma0^2", slip(bp.C; gamma0=bp.gamma0), bp.C / bp.gamma0^2)
    # periodic and initial maps agree wherever both exist
    for f in unique(COLS["fixture"])
        a = row_index(f, "initial"); p = row_index(f, "periodic")
        (a === nothing || p === nothing) && continue
        ok &= witness_row("$(f)_periodic_vs_initial_map_maxentry", maximum(abs, table_map(a) - table_map(p)), 0.0, TOL_MAP)
    end
    return ok
end

# ---------------------------------------------------------------- analyze on the converted map
const ANALYSIS = TwissDispersionAnalysis(strict=false, scaling=:none)

reason_of(d) = is_determined(d) ? :none : d.reason

"""
analyze the converted map and gather the reads every layer needs, each guarded by
is_determined (rule D): tunes (rad/turn, eigen order), the presented form, form-1 R and
mode Twiss (triple unwrap, rule Y), physical beta/alpha/eta, the coasting-route eta
(printed only, rule S), the plane content of each mode and the cluster classification.
"""
function analyze_converted(M::AbstractMatrix)
    result = analyze(ANALYSIS, Matrix{Float64}(M))
    tunes = copy(result.physical.tunes)
    form = 0; R = nothing; twiss = nothing; lambda = NaN; detR = NaN
    xcontent = Float64[]
    frame_ok = false
    if is_determined(result.transverse)
        trv = determined_value(result.transverse)
        form = is_determined(trv.preferred_form) ? determined_value(trv.preferred_form) : 0
        if is_determined(trv.edwards_teng_normalizer)
            pair = determined_value(trv.edwards_teng_normalizer)
            f1 = pair.form1
            R = is_determined(f1.R) ? copy(determined_value(f1.R)) : nothing
            twiss = is_determined(f1.twiss) ? determined_value(f1.twiss) : nothing
            lambda = is_determined(f1.lambda) ? determined_value(f1.lambda) : NaN
            detR = is_determined(f1.det_R) ? determined_value(f1.det_R) : NaN
        end
        if is_determined(trv.frame)
            fr = determined_value(trv.frame)
            kappa = fr.signed_areas
            frame_ok = true
            for j in 1:size(kappa, 1)
                push!(xcontent, abs(kappa[j, 1]) / (abs(kappa[j, 1]) + abs(kappa[j, 2])))
            end
        end
    end
    beta = is_determined(result.physical.beta) ? determined_value(result.physical.beta) : nothing
    alpha = is_determined(result.physical.alpha) ? determined_value(result.physical.alpha) : nothing
    eta = is_determined(result.physical.eta) ? determined_value(result.physical.eta) : nothing
    coasting_eta = (result.dispersion !== nothing && is_determined(result.dispersion.coasting.eta)) ?
                   determined_value(result.dispersion.coasting.eta) : nothing
    clusters = result.clusters.clusters
    cluster_class = [c.classification for c in clusters]
    cluster_reason = [c.reason for c in clusters]
    return (result=result, status=result.status, tunes=tunes, form=form, R=R, twiss=twiss,
            lambda=lambda, detR=detR, beta=beta, alpha=alpha, eta=eta, coasting_eta=coasting_eta,
            xcontent=xcontent, frame_ok=frame_ok, cluster_class=cluster_class, cluster_reason=cluster_reason,
            reasons=(beta=reason_of(result.physical.beta), alpha=reason_of(result.physical.alpha),
                     gamma=reason_of(result.physical.gamma), edwards_teng_R=reason_of(result.physical.edwards_teng_R)))
end

"Index of the Octopus mode whose cos(tune) is closest to cos(2 pi q) (rule T: matched by eigenvalue, never by label)."
function match_mode(tunes::AbstractVector, q::Real)
    isempty(tunes) && return 0
    target = cos(2pi * q)
    return argmin([abs(cos(mu) - target) for mu in tunes])
end

"The rows of one physical quantity vs the periodic row; returns the AND of the gated statuses."
function tune_rows(fixture, an, q::Real, label::AbstractString, tol::Real, class::AbstractString)
    j = match_mode(an.tunes, q)
    if j == 0
        compare_row("A1", fixture, "cos_mu_$(label)", NaN, cos(2pi * q), tol, class; rel=false)
        compare_row("A1", fixture, "sin_mu_$(label)", NaN, sin(2pi * q), tol, class; rel=false)
        return (ok=false, j=0)
    end
    mu = an.tunes[j]
    ok = compare_row("A1", fixture, "cos_mu_$(label)", cos(mu), cos(2pi * q), tol, class; rel=false)
    ok &= compare_row("A1", fixture, "sin_mu_$(label)", sin(mu), sin(2pi * q), tol, class; rel=false)
    an.frame_ok && recorded_row("A1", fixture, "mode$(j)_x_content_for_$(label)", an.xcontent[j], label == "q1" ? 1.0 : 0.0)
    return (ok=ok, j=j)
end

# ---------------------------------------------------------------- A1 convention layer
const A1_FIXTURES = ("U1", "U2", "K1", "K2")
const COUPLED = ("K1", "K2")           # rule Z: the R rows are gated only here (branch separated)

"MAD-X's r11..r22 read against Octopus form1.R (the D16 defect transpose_R flips it)."
octopus_R(an) = an.R === nothing ? nothing : (DEFECT === :transpose_R ? permutedims(an.R) : an.R)

function convention_layer(fixture::AbstractString)
    ip = row_index(fixture, "periodic"); ia = row_index(fixture, "initial")
    (ip === nothing || ia === nothing) && error("A1: $(fixture) needs both a periodic and an initial row")
    opt = table_optics(ip); beam = table_beam(ip)
    M_madx = table_map(ia)
    an = analyze_converted(converted_map(ia))
    ok = true
    ok &= assert_row("$(fixture)_analyze_status_passed", an.status === :passed; fixture=fixture, layer="A1")
    # tunes (rule T): cos mu and sin mu, the mode matched by eigenvalue
    t1 = tune_rows(fixture, an, opt.q1, "q1", TOL_A_ABS, "TOL-A"); ok &= t1.ok
    t2 = tune_rows(fixture, an, opt.q2, "q2", TOL_A_ABS, "TOL-A"); ok &= t2.ok
    ok &= assert_row("$(fixture)_two_distinct_modes_matched", t1.j != 0 && t2.j != 0 && t1.j != t2.j; fixture=fixture, layer="A1")
    # the presented Edwards-Teng form: asserted 1 on the coupled cells, recorded elsewhere
    if fixture in COUPLED
        ok &= assert_row("$(fixture)_presented_ET_form_is_1", an.form == 1; fixture=fixture, layer="A1")
    else
        recorded_row("A1", fixture, "presented_ET_form", an.form, 1.0)
    end
    # ET mode functions (rule Y): betx/alfx are mode q1's, bety/alfy mode q2's
    if an.twiss === nothing || t1.j == 0 || t2.j == 0
        for q in ("betx", "alfx", "bety", "alfy")
            ok &= compare_row("A1", fixture, "ET_$(q)", NaN, getfield(opt, Symbol(q)), TOL_A_REL, "TOL-A")
        end
    else
        w1 = an.twiss[t1.j]; w2 = an.twiss[t2.j]
        ok &= compare_row("A1", fixture, "ET_betx", w1.beta, opt.betx, TOL_A_REL, "TOL-A")
        ok &= compare_row("A1", fixture, "ET_alfx", w1.alpha, opt.alfx, TOL_A_REL, "TOL-A")
        ok &= compare_row("A1", fixture, "ET_bety", w2.beta, opt.bety, TOL_A_REL, "TOL-A")
        ok &= compare_row("A1", fixture, "ET_alfy", w2.alpha, opt.alfy, TOL_A_REL, "TOL-A")
        ok &= witness_row("$(fixture)_form1_twiss_mu_vs_tunes", max(abs(w1.mu - an.tunes[t1.j]), abs(w2.mu - an.tunes[t2.j])), 0.0, TOL_A_ABS; fixture=fixture)
        if an.beta !== nothing
            # Mais-Ripken beside the ET functions: they coincide on the uncoupled cells and only there
            recorded_row("A1", fixture, "physical_beta[q1mode,x]_beside_betx", an.beta[t1.j, 1], opt.betx)
            recorded_row("A1", fixture, "physical_beta[q2mode,y]_beside_bety", an.beta[t2.j, 2], opt.bety)
            if !(fixture in COUPLED)
                ok &= compare_row("A1", fixture, "MR_beta_x", an.beta[t1.j, 1], opt.betx, TOL_A_REL, "TOL-A")
                ok &= compare_row("A1", fixture, "MR_beta_y", an.beta[t2.j, 2], opt.bety, TOL_A_REL, "TOL-A")
            end
        end
    end
    # rule Z: branch operands on every fixture; the R rows gated on the coupled cells only
    br = print_branch(fixture, M_madx[1:4, 1:4], opt.R)
    R_oct = octopus_R(an)
    for (k, name) in zip(((1, 1), (1, 2), (2, 1), (2, 2)), ("r11", "r12", "r21", "r22"))
        v = R_oct === nothing ? NaN : R_oct[k...]
        if fixture in COUPLED
            ok &= compare_row("A1", fixture, name, v, opt.R[k...], TOL_A_REL, "TOL-A")
        else
            recorded_row("A1", fixture, name, v, opt.R[k...])
        end
    end
    if fixture in COUPLED
        ok &= compare_row("A1", fixture, "lambda_from_madx_detR_vs_gamma_SR_of_map", br.lambda_table, br.gamma_SR, TOL_PIN, "pin")
        ok &= compare_row("A1", fixture, "octopus_form1_lambda_vs_madx_lambda", an.lambda, br.lambda_table, TOL_A_REL, "TOL-A")
    else
        recorded_row("A1", fixture, "octopus_form1_lambda_vs_madx_lambda", an.lambda, br.lambda_table)
    end
    all(isfinite, br.R) && recorded_row("A1", fixture, "twcpin_R_recomputed_from_map_vs_table_maxentry", maximum(abs, br.R - opt.R), 0.0)
    # dispersion (rule S): physical.eta vs beta0 * DX at TOL-B; the coasting route printed beside it
    for (k, name) in enumerate(("dx", "dpx", "dy", "dpy"))
        v = an.eta === nothing ? NaN : an.eta[k]
        ok &= compare_row("A1", fixture, "eta_$(name)_vs_beta0*$(uppercase(name))", v, beam.beta0 * opt.D[k], TOL_B_REL, "TOL-B")
    end
    if an.eta !== nothing && an.coasting_eta !== nothing
        recorded_row("A1", fixture, "coasting_eta_x(reciprocal_scaled_trap)_beside_physical_eta_x", an.coasting_eta[1], an.eta[1])
    end
    return ok
end

# ---------------------------------------------------------------- A2 model layer
const CELL_BUILDERS = Dict{String,Function}(
    "U1" => (; kw...) -> U1(; kw...), "U2" => (; kw...) -> U2(; kw...),
    "K1" => (; kw...) -> K1(; tilt=K_TILT, kw...), "K2" => (; kw...) -> K2(; tilt=K_TILT, kw...))

"Least-squares slope of log(residual) against log(nst); the convergence order is minus that slope."
function fitted_order(nsts, residuals)
    x = log.(Float64.(collect(nsts))); y = log.(Float64.(collect(residuals)))
    xm = sum(x) / length(x); ym = sum(y) / length(y)
    return -sum((x .- xm) .* (y .- ym)) / sum((x .- xm) .^ 2)
end

function model_ladder(fixture::AbstractString)
    ia = row_index(fixture, "initial"); ip = row_index(fixture, "periodic")
    Mconv = converted_map(ia)
    build = CELL_BUILDERS[fixture]
    residuals = Float64[]
    for nst in NST_LADDER
        Moct = bare_map(build(; nst=nst, integrator_order=DEFAULT_ORDER))
        r = maximum(abs, Moct - Mconv)
        push!(residuals, r)
        println("TW-MADX-MODEL ", fixture, " ", nst, " ", fmt(r))
        record!("A2", fixture, "model_maxentry_nst$(nst)", r, 0.0, r, NaN, "TOL-E", "RECORDED")
        if nst == 4 && ip !== nothing
            # the contract's recipe row: the nst=4 model's ET betx against MAD-X, relative
            an4 = analyze_converted(Moct)
            opt = table_optics(ip)
            j = match_mode(an4.tunes, opt.q1)
            if an4.twiss !== nothing && j != 0
                recorded_row("A2", fixture, "nst4_recipe_ET_betx_relative_vs_madx", (an4.twiss[j].beta - opt.betx) / opt.betx, 0.0)
            end
        end
    end
    order = fitted_order(NST_LADDER, residuals)
    ok = abs(order - ORDER_TARGET) <= ORDER_BAND && residuals[end] <= NST64_CAP
    println("TW-MADX-ORDER ", fixture, " ", fmt(order), " ", fmt(NST64_CAP), " ", ok ? "PASS" : "FAIL")
    record!("A2", fixture, "fitted_order", order, ORDER_TARGET, abs(order - ORDER_TARGET), ORDER_BAND, "TOL-E", ok ? "PASS" : "FAIL")
    record!("A2", fixture, "nst64_residual_vs_cap", residuals[end], NST64_CAP, residuals[end], NST64_CAP, "TOL-E", residuals[end] <= NST64_CAP ? "PASS" : "FAIL")
    recorded_row("A2", fixture, "nst32_residual(1e-9_design_reference,recorded_per_D6)", residuals[end-1], 1e-9)
    return ok
end

# ---------------------------------------------------------------- A3 the rolled family, A5 the seed row
"""
    rolled_exact_anchor(; Lq=0.2, k=1.0, Ld=1.0)

Theory 13.10's equal-tune anchor computed from the R_0 fixture's OWN elements (specs_rolled_fodo in
validation/twiss_benchmark_cells.jl: thick quad L=0.2 k=+1, drift 1.0, thick quad L=0.2 k=-1, drift 1.0),
never a pinned digit: with phi = sqrt(k) Lq the analytic 2x2 blocks Qf = [cos phi, sin phi/sqrt(k); -sqrt(k) sin phi, cos phi],
Qd = [cosh phi, sinh phi/sqrt(k); sqrt(k) sinh phi, cosh phi], Dr = [1, Ld; 0, 1] give the one-turn block
M = Dr Qd Dr Qf, cos mu = tr(M)/2 (the same in both planes: the roll swaps them and the cell is F-D symmetric),
q = acos(cos mu)/(2pi). Evaluated: cos mu = 0.97440039720586435, q = 0.036089644373316153; the literals
0.9744003972058644 / 0.0360896443733161 formerly frozen here (read off a run) agree to 0 and 5.6e-17.
"""
function rolled_exact_anchor(; Lq=0.2, k=1.0, Ld=1.0)
    s = sqrt(k); phi = s * Lq
    Qf = [cos(phi) sin(phi)/s; -s*sin(phi) cos(phi)]
    Qd = [cosh(phi) sinh(phi)/s; s*sinh(phi) cosh(phi)]
    Dr = [1.0 Ld; 0.0 1.0]
    M = Dr * Qd * Dr * Qf
    c = (M[1, 1] + M[2, 2]) / 2
    return (cos=c, q=acos(c) / (2pi))
end
const ROLLED_EXACT_COS = rolled_exact_anchor().cos   # theory 13.10's cos mu of the equal-tune cell (the R_0 anchor is gated against it at TOL-F)
const ROLLED_EXACT_Q = rolled_exact_anchor().q       # theory 13.10's fractional tune, acos(ROLLED_EXACT_COS)/(2pi)

"D8: Octopus refuses the degenerate frame with reason symbols, never a tune."
function reason_rows(fixture, an, label)
    ok = assert_row("$(fixture)_$(label)_status_passed", an.status === :passed; fixture=fixture, layer="A3")
    ok &= assert_row("$(fixture)_$(label)_tunes_empty", isempty(an.tunes); fixture=fixture, layer="A3")
    for f in (:beta, :alpha, :gamma, :edwards_teng_R)
        ok &= assert_row("$(fixture)_$(label)_$(f)_reason_cluster_unresolved", getfield(an.reasons, f) === :cluster_unresolved; fixture=fixture, layer="A3")
    end
    idx = findall(==(:cluster_unresolved), an.cluster_reason)
    ok &= assert_row("$(fixture)_$(label)_unresolved_cluster_classified_definite",
                     !isempty(idx) && all(an.cluster_class[i] === :definite for i in idx); fixture=fixture, layer="A3")
    return ok
end

function rolled_family()
    ok = true
    i00 = row_index("R_0", "initial")
    M0 = table_map(i00)[1:4, 1:4]
    modes0 = block_cos_sin(M0)
    exact_cos = modes0[1].cos
    exact_q = acos(exact_cos) / (2pi)
    # stage 8 A3: the exported map is right at every roll AND ties to theory 13.10: the R_0 anchor
    # is GATED at TOL-F against the theory anchor computed from the fixture's own L and k (rolled_exact_anchor;
    # measured 1.1102230246251565e-16 on cos mu, 8.3266726846886741e-17 on q), so a common-mode deck error cannot keep the family green.
    ok &= compare_row("A3", "R_0", "exported_cos_mu_vs_theory_13.10_constant", exact_cos, ROLLED_EXACT_COS, TOL_F_ABS, "TOL-F"; rel=false)
    ok &= compare_row("A3", "R_0", "exact_q_from_exported_map_vs_theory_13.10", exact_q, ROLLED_EXACT_Q, TOL_F_ABS, "TOL-F"; rel=false)
    for r in ROLLED_THETAS
        f = r.id; theta = r.theta
        ia = row_index(f, "initial"); ip = row_index(f, "periodic")
        Mth = table_map(ia)[1:4, 1:4]
        modes = block_cos_sin(Mth)
        ok &= assert_row("$(f)_exported_map_two_eigenpairs", length(modes) == 2; fixture=f, layer="A3")
        for (k, m) in enumerate(modes)
            ok &= compare_row("A3", f, "exported_cos_mu_mode$(k)", m.cos, exact_cos, TOL_F_ABS, "TOL-F"; rel=false)
            ok &= compare_row("A3", f, "exported_eigen_modulus_mode$(k)", m.modulus, 1.0, TOL_F_ABS, "TOL-F"; rel=false)
        end
        Rr = Rt(theta)
        ok &= compare_row("A3", f, "exported_map_vs_Rt(theta)M0Rt(theta)'_maxentry", maximum(abs, Mth - Rr * M0 * Rr'), 0.0, TOL_F_ABS, "TOL-F"; rel=false)
        recorded_row("A3", f, "other_sense_Rt'M0Rt_maxentry", maximum(abs, Mth - Rr' * M0 * Rr), 0.0)
        # D9: MAD-X's periodic tunes as a directional sentinel
        if ip === nothing
            ok &= assert_row("$(f)_no_periodic_solution(TWCPIN_false_instability)", theta == pi / 4; fixture=f, layer="A3")
        else
            q1 = cellf("q1", ip); q2 = cellf("q2", ip)
            recorded_row("A3", f, "madx_periodic_q1_vs_exact", q1, exact_q)
            recorded_row("A3", f, "madx_periodic_q2_vs_exact", q2, exact_q)
            if theta == 0
                ok &= compare_row("A3", f, "sentinel_|q1-exact|_right_at_theta0", abs(q1 - exact_q), 0.0, TOL_F_ABS, "TOL-F"; rel=false)
            else
                ok &= assert_row("$(f)_sentinel_|q1-exact|>1e-4_wrong_periodic_solve", abs(q1 - exact_q) > 1e-4; fixture=f, layer="A3")
            end
        end
        # D8: Octopus reason symbols on the converted MAD-X map and on the lattice map
        ok &= reason_rows(f, analyze_converted(converted_map(ia)), "converted")
        ok &= reason_rows(f, analyze_converted(bare_map(rolled_fodo(theta))), "lattice_nst64")
        # A5: the seed row, recorded (both signs of tan theta, see the report)
        for (sgn, tag) in ((-1.0, "-tan"), (1.0, "+tan"))
            V = V1_form1(sgn * tan(theta) * Matrix{Float64}(I, 2, 2))
            recorded_row("A5", f, "seed_M(theta)_vs_V1($(tag)(theta)I)M0V1^-1_maxentry", maximum(abs, Mth - V * M0 * inv(V)), 0.0)
            ip === nothing || recorded_row("A5", f, "madx_r11..r22_vs_$(tag)(theta)I_maxentry",
                                           maximum(abs, table_optics(ip).R - sgn * tan(theta) * Matrix{Float64}(I, 2, 2)), 0.0)
        end
        ip === nothing || print_branch(f, Mth, table_optics(ip).R)
    end
    # the detuned controls: Rd(1e-3) is the GATED control (stage 8 A3); Rd(1e-6) is RECORDED, because at a
    # 3.4e-7 tune split MAD-X's own periodic tune departs from its exported map's eigenvalue by ~1.8e-11 in q
    # (the approach to the TWCPIN failure, D9) and Octopus reports status :failed (frame symplecticity at
    # the 1/split conditioning) with strict=false; both are printed, neither is pinned.
    for r in RD_EPSILONS
        f = r.id; gated = r.eps >= 1e-3
        ia = row_index(f, "initial"); ip = row_index(f, "periodic")
        Mth = table_map(ia)[1:4, 1:4]; opt = table_optics(ip)
        modes = block_cos_sin(Mth)
        for (q, label) in ((opt.q1, "q1"), (opt.q2, "q2"))
            k = argmin([abs(m.cos - cos(2pi * q)) for m in modes])
            mu_map = atan(modes[k].sin, modes[k].cos)
            if gated
                ok &= compare_row("A3", f, "madx_periodic_mu_$(label)_vs_exported_map_eigen", 2pi * q, mu_map, TOL_F_ABS, "TOL-F"; rel=false)
            else
                recorded_row("A3", f, "madx_periodic_mu_$(label)_vs_exported_map_eigen(approach_to_TWCPIN_failure)", 2pi * q, mu_map)
            end
        end
        recorded_row("A3", f, "tune_split_q1-q2", opt.q1 - opt.q2, 0.0)
        an = analyze_converted(converted_map(ia))
        recorded_note("A3", f, "analyze_status", string(an.status, " failures=", an.result.failures))
        if gated
            ok &= assert_row("$(f)_analyze_status_passed", an.status === :passed; fixture=f, layer="A3")
            t1 = tune_rows(f, an, opt.q1, "q1", TOL_F_ABS, "TOL-F"); t2 = tune_rows(f, an, opt.q2, "q2", TOL_F_ABS, "TOL-F")
            ok &= t1.ok & t2.ok
        else
            for (q, label) in ((opt.q1, "q1"), (opt.q2, "q2"))
                j = match_mode(an.tunes, q)
                j == 0 || recorded_row("A3", f, "octopus_mu_$(label)_vs_madx_2pi_q(not_gated)", an.tunes[j], 2pi * q)
                j == 0 || recorded_row("A3", f, "octopus_mu_$(label)_vs_exported_map_eigen", an.tunes[j],
                                       atan(modes[argmin([abs(m.cos - cos(an.tunes[j])) for m in modes])].sin, modes[argmin([abs(m.cos - cos(an.tunes[j])) for m in modes])].cos))
            end
        end
        recorded_row("A3", f, "presented_ET_form", an.form, 1.0)
        br = print_branch(f, Mth, opt.R)
        R_oct = octopus_R(an)
        R_oct === nothing || recorded_row("A3", f, "form1.R_vs_madx_r11..r22_maxentry(branch_near_degenerate,not_gated)", maximum(abs, R_oct - opt.R), 0.0)
        recorded_row("A3", f, "octopus_form1_lambda_vs_madx_lambda", an.lambda, br.lambda_table)
    end
    return ok
end

# ---------------------------------------------------------------- A4 the free cross-code row (recorded)
function cross_code_row()
    if !isfile(XSUITE_TABLE)
        println("TW-MADX-RECORDED K1 madx_vs_xtrack skipped (no Xsuite table at ", XSUITE_TABLE, ")")
        record!("A4", "K1", "madx_vs_xtrack_skipped", NaN, NaN, NaN, NaN, "recorded", "RECORDED")
        return
    end
    xs = read_reference_table(XSUITE_TABLE).columns
    vals = Dict{String,Float64}()
    for i in eachindex(xs["layer"])
        xs["layer"][i] == "C2" && xs["fixture"][i] == "K1" && xs["compile"][i] == "line4d" || continue
        vals[xs["quantity"][i]] = parse(Float64, xs["value"][i])
    end
    if isempty(vals)
        recorded_note("A4", "K1", "madx_vs_xtrack", "skipped (no C2 K1 line4d rows in the Xsuite table)")
        return
    end
    ip = row_index("K1", "periodic"); opt = table_optics(ip)
    for (madx_name, madx_v, xt_name) in (("q1", opt.q1, "qx"), ("q2", opt.q2, "qy"),
                                          ("betx", opt.betx, "betx_edw_teng"), ("alfx", opt.alfx, "alfx_edw_teng"),
                                          ("bety", opt.bety, "bety_edw_teng"), ("alfy", opt.alfy, "alfy_edw_teng"),
                                          ("betx", opt.betx, "betx"), ("bety", opt.bety, "bety"))
        haskey(vals, xt_name) || continue
        recorded_row("A4", "K1", "madx_$(madx_name)_vs_xtrack_$(xt_name)", madx_v, vals[xt_name])
    end
    haskey(vals, "g_edw_teng") && recorded_row("A4", "K1", "madx_lambda_from_detR_vs_xtrack_g_edw_teng", 1 / sqrt(1 + det(opt.R)), vals["g_edw_teng"])
end

# ---------------------------------------------------------------- digest, table, gate
function digest()
    nfail = count(r -> r.status == "FAIL", ROWS)
    worst = isempty(RATIOS) ? NaN : maximum(RATIOS)
    println("TW-MADX-DIGEST ", length(ROWS), " ", nfail, " ", fmt(worst))
    return nfail
end

function write_rows()
    header = ["Octopus twiss benchmark against MAD-X 5.03.06 twiss (validation/twiss_madx_benchmark.jl); input validation/reference/twiss_madx_5.03.06.tsv",
              "one row per recorded comparison (a TW-MADX-BRANCH line records its operands t, det U, Delta as three rows and the ladder records the cap beside each order, so the row count exceeds the printed-line count): layer A0..A5, fixture, quantity, octopus, external (MAD-X or the formula), |diff|, tol, class, status (PASS/FAIL/RECORDED)",
              "defect override OCTOPUS_STAGE8_DEFECT=$(DEFECT); numbers %.17g; NaN = not applicable"]
    cols = ["layer", "fixture", "quantity", "octopus", "external", "diff", "tol", "class", "status"]
    rows = [(r.layer, r.fixture, r.quantity, r.octopus, r.external, r.diff, r.tol, r.class, r.status) for r in ROWS]
    write_reference_table(OUT_TSV, header, cols, rows)
    println("TSV written to result/twiss_madx_benchmark.tsv (", length(rows), " rows)")
end

function gate(nfail::Integer, aborted::Bool)
    aborted && error("TW-MADX: an A0 convention witness FAILED; layers A1-A5 were not run (", nfail, " FAIL rows)")
    nfail == 0 || error("TW-MADX: ", nfail, " FAIL row(s); see the TW-MADX lines above")
    println("twiss MAD-X benchmark: ", length(ROWS), " rows, 0 FAIL, worst ratio ", fmt(maximum(RATIOS)))
end

function main()
    println("TW-MADX-CONFIG table=", basename(MADX_TABLE), " version=", strip(replace(TABLE.header[2], "# MAD-X version:" => "")),
            " defect=", DEFECT, " analysis=TwissDispersionAnalysis(strict=false, scaling=:none) ladder=", NST_LADDER)
    ok0 = witness_rows()
    if !ok0
        nfail = digest(); write_rows(); gate(nfail, true)
    end
    ok = true
    for f in A1_FIXTURES
        ok &= convention_layer(f)
    end
    for f in A1_FIXTURES
        ok &= model_ladder(f)
    end
    ok &= rolled_family()
    cross_code_row()
    nfail = digest()
    write_rows()
    gate(nfail, false)
end

main()
