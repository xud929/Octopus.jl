"""
Twiss benchmark C: Octopus's twiss and dispersion analysis against Xsuite
(xtrack 0.112.0) on the committed reference table
validation/reference/xsuite_twiss_xtrack_0.112.0.tsv (stage 8 of the twiss
campaign, design note staging item 8, theory 12.2 item 7; history section of benchmark C). The suite never runs
python: the generator validation/generate_xsuite_twiss_reference.py froze
the table once; this script only reads it.

Reference model
---------------
Four layers, printed with the tag TW-XSUITE:
  C0 convention witnesses, each a FORMULA in the table's own beta0/gamma0
     and L (never a pinned probe digit): the S0 drift R[4,5] = L/gamma0^2
     at TOL-D and R[5,4] = 0; the sheared drift Sh(-L/gamma0^2) R against
     the Octopus bare S0 map; the rule X sign row on U2 (sign R[4,0],
     R[4,1] against Octopus M51, M52); the lone cavity W1 R[5,4] against
     -M65 of the Octopus bare map; the lone rolled quadrupole against
     Rt(t) M(0) Rt(t)'. The witnesses run before any optics row.
  C1 matrix level, NO conversion: xtrack's get_linear_normal_form ran on
     the committed Octopus maps (validation/reference/twiss_benchmark_maps.tsv),
     so both sides read the same matrix. Compared: cos mu, sin mu per mode
     (modes matched by EIGENVALUE, rule T), the Mais-Ripken beta and alpha
     by (matched mode, plane) against physical.beta / physical.alpha, the
     Edwards-Teng mode beta/alpha (betx_edw_teng ...) against form1.twiss,
     g_edw_teng against form1.lambda, the rank-2 normalizer invariant
     W_j W_j' against U_k U_k' (gauge- and label-free), the momentum column
     dx..dpy against physical.graph[:,2] on bunched maps and physical.eta
     on coasting maps (xtrack's own 4d route), the zeta column dx_zeta..
     against physical.zeta, and h * dx against physical.eta with the
     un-repaired gap |dx - eta| printed (theory 9.5).
  C2 lattice level: Line.twiss(method='4d') on xtrack twins of U1, U2, K1,
     K2, R(0.1), R(pi/4), Rd(1e-3), Rd(1e-6). The xtrack one-turn map is
     converted by the section 3 law M_oct = Sh(-C/gamma0^2) R (J0 = F = I)
     and compared with Octopus's bare map over the nst ladder {4,8,16,32,64}
     (TOL-E: the fitted convergence order and the frozen nst=64 cap); the
     lattice functions at nst=64 are reported beside it; dispersion at
     TOL-D; on the rolled cells only label-free quantities (TOL-F) and
     Octopus's reason symbols (stage 8 decision D8).
  C3 the 6D twin T6 (U2 plus the flipped cavity, strength -0.02, LAST;
     xt.Cavity(voltage=5.6989983281965137e7, frequency=400e6, lag=0)):
     Octopus TASK compile against the xtrack line. The longitudinal 2x2
     witness (M55, M56, M65, M66) runs BEFORE any transverse row; then
     betx/bety/alfx/alfy at TOL-D, eta = h * tw6.dx against physical.eta
     at TOL-D, qs recorded. If the witness fails the layer is RECORDED, not
     gated (stage 8 decision D5).

Error metric
------------
|octopus - xtrack| against bound = tol * max(|xtrack|, 1) for relative classes
and bound = tol for absolute classes, one printed line per quantity in the grammar
TW-XSUITE <fixture> <quantity> <octopus> <external> <|diff|> <bound> <class> PASS|FAIL
(the <bound> slot carries the APPLIED bound, so |diff| <= <bound> reads PASS on the line;
the class column names the tolerance family), every number %.17g; TW-XSUITE-WITNESS,
-MODEL <fixture> <nst> <maxdiff>, -ORDER <fixture> <order> <cap> PASS|FAIL, -RECORDED,
-DIGEST <rows> <fails> <worst ratio>, and TW-XSUITE-NOTE lines for the extra counters.

Tolerance
---------
TOL-A 1e-12 relative (beta, alpha, R, normalizer projectors), 1e-13
absolute (cos mu, sin mu): same matrix both sides. TOL-D 1e-7 relative on
anything touching rows/columns 5-6 of an xtrack finite-difference map
(13-particle central differences, floor 1.65e-9 on the drift). TOL-E the
fitted order 4.0 +- 0.3 over the nst ladder plus the nst=64 cap frozen
below with its provenance. TOL-F 1e-10 absolute on the degenerate rolled
cells and their detuned controls.

Configuration
-------------
TwissDispersionAnalysis(strict=false, scaling=:none); every quantity is
read from physical.* or the form-1 objects of edwards_teng_normalizer
(triple unwrap, rule Y; the presented form is asserted to be 1 on the
coupled cells); every read branches on is_determined (rule D); the
coasting route's reciprocal-scaled eta is printed beside physical.eta once
per coasting fixture and never compared (rule S).

Fixtures
--------
S0, W1, Q_rot0.05 (witnesses); U1, U2, K1, K2, R_0.1, R_pi4, Rd_1e-3,
Rd_1e-6, B4, B5, T6, D6_1..3, D8_1..3 (C1); the eight 4d lattice twins
(C2); T6 (C3); all from validation/twiss_benchmark_cells.jl (the stage 8 fixture table, history section).

Inputs/Outputs (under result/)
------------------------------
Inputs: validation/reference/xsuite_twiss_xtrack_0.112.0.tsv and
validation/reference/twiss_benchmark_maps.tsv (both committed).
Output: result/twiss_xsuite_benchmark.tsv, one row per printed line
(layer, fixture, quantity, octopus, xtrack, diff, bound, class, status).

Run
---
    julia --project=. validation/twiss_xsuite_benchmark.jl

Environment
-----------
    CUDA_VISIBLE_DEVICES=""        (script mode; the AVX2 arm adds
                                    OPENBLAS_CORETYPE=Haswell and julia -C haswell)
Overrides:
    OCTOPUS_STAGE8_DEFECT   none (default) | drop_shear (the C2 conversion
                            omits Sh(-C/gamma0^2), so the converted 4d lattice
                            map keeps xtrack's slip and the eight C2
                            rows_cols_5_6_maxscaled_nst64 lines turn red;
                            C3 pairs xtrack with the TASK compile, u = 0, and
                            the C0 S0 witness names target=:bare, so neither
                            is reached by the defect; stage 8 decision D16).
"""

include(joinpath(@__DIR__, "twiss_benchmark_cells.jl"))   # guards Octopus itself
using .Octopus
using LinearAlgebra
using Printf
using SHA

# ---------------------------------------------------------------- configuration
const XSUITE_TABLE = joinpath(@__DIR__, "reference", "xsuite_twiss_xtrack_0.112.0.tsv")
const MAPS_TABLE = joinpath(@__DIR__, "reference", "twiss_benchmark_maps.tsv")
const SIDECAR = joinpath(@__DIR__, "reference", "xsuite_twiss_provenance.txt")
const OUT_TSV = normpath(joinpath(@__DIR__, "..", "result", "twiss_xsuite_benchmark.tsv"))
const DEFECT = Symbol(get(ENV, "OCTOPUS_STAGE8_DEFECT", "none"))
DEFECT in (:none, :drop_shear) ||
    error("OCTOPUS_STAGE8_DEFECT must be none or drop_shear, got $(DEFECT)")

const TOL_A_REL = 1e-12          # beta, alpha, R entries, normalizer projectors (same matrix both sides)
const TOL_A_ABS = 1e-13          # cos mu, sin mu
const TOL_D_REL = 1e-7           # anything touching rows/columns 5-6 of an xtrack finite-difference map (floor 1.65e-9)
const TOL_F_ABS = 1e-10          # the degenerate rolled cells and their detuned controls
const TOL_PIN = 1e-12            # header pins and exact zeros
const TOL_MAP = 1e-14            # map-vs-map witnesses on Octopus maps
const ORDER_TARGET = 4.0
const ORDER_BAND = 0.3
const NST_LADDER = (4, 8, 16, 32, 64)
# nst=64 residual cap of the C2 model ladder (stage 8 decision D6), frozen from the first passing native run of this script
# (2026-09-15, sapphirerapids; the record is docs/history/twiss_dispersion_analysis_history.md, section
# "2026-09-15: stage 8, benchmark C"): the largest nst=64 residual of the transverse 4x4 block over the four gated
# lattice cells U1, U2, K1, K2 is U2's 2.3920456726500561e-09 (K2 2.3805526438991365e-09, U1 2.0827201074880008e-10,
# K1 3.4805491821998658e-12). The cap is ten times that,
# clipped at the design's 1e-8 absolute (stage 8 TOL-E); an upper bound only, the gate is the fitted order.
const NST64_MEASURED_MAX = 2.3920456726500561e-09
const NST64_CAP = min(10 * NST64_MEASURED_MAX, 1e-8)

fmt(x::Real) = @sprintf("%.17g", Float64(x))
fmt(x::Integer) = string(x)
fmt(x::AbstractString) = String(x)
fmt(x) = string(x)

# ---------------------------------------------------------------- the two tables
const XT = read_reference_table(XSUITE_TABLE)
const XCOLS = XT.columns
const XKEY = Dict{NTuple{4,String},String}()
for i in 1:length(XCOLS["layer"])
    XKEY[(XCOLS["layer"][i], XCOLS["fixture"][i], XCOLS["compile"][i], XCOLS["quantity"][i])] = XCOLS["value"][i]
end
"The xtrack cell (layer, fixture, compile, quantity) as Float64; error if absent."
function xcell(layer, fixture, compile, quantity)
    k = (String(layer), String(fixture), String(compile), String(quantity))
    haskey(XKEY, k) || error("xsuite table: no cell $(k)")
    return parse(Float64, XKEY[k])
end
has_xcell(layer, fixture, compile, quantity) = haskey(XKEY, (String(layer), String(fixture), String(compile), String(quantity)))
"The 6x6 matrix stored as <prefix>11..<prefix>66 (prefix r or W)."
function xmatrix(layer, fixture, compile, prefix)
    M = zeros(6, 6)
    for a in 1:6, b in 1:6
        M[a, b] = xcell(layer, fixture, compile, "$(prefix)$(a)$(b)")
    end
    return M
end
"The value of a header line 'key: ...' style number is not needed; beta0/gamma0 are read from the beam header line."
function header_beam(header::Vector{String})
    line = header[findfirst(l -> occursin("beta0 ", l) && occursin("gamma0 ", l), header)]
    b = match(r"beta0 ([0-9.eE+-]+)", line); g = match(r"gamma0 ([0-9.eE+-]+)", line)
    return (beta0=parse(Float64, b.captures[1]), gamma0=parse(Float64, g.captures[1]))
end

const MT = read_reference_table(MAPS_TABLE)
const MCOLS = MT.columns
"Row index of (id, compile) in the Octopus maps table."
function maps_row(id, compile)
    for i in 1:length(MCOLS["id"])
        MCOLS["id"][i] == String(id) && MCOLS["compile"][i] == String(compile) && return i
    end
    error("maps table: no row ($(id), $(compile))")
end
"The committed Octopus map of (id, compile): 6x6, or 4x4 for the D8 rows (dim=4)."
function octopus_map(id, compile; dim::Int=6)
    i = maps_row(id, compile)
    M = zeros(6, 6)
    for a in 1:6, b in 1:6
        M[a, b] = parse(Float64, MCOLS["m$(a)$(b)"][i])
    end
    return dim == 4 ? M[1:4, 1:4] : M
end
maps_C(id, compile) = parse(Float64, MCOLS["C"][maps_row(id, compile)])

# ---------------------------------------------------------------- the rows
const ROWS = NamedTuple{(:layer, :fixture, :quantity, :octopus, :external, :diff, :bound, :class, :status),
                        Tuple{String,String,String,Float64,Float64,Float64,Float64,String,String}}[]

function record!(layer, fixture, quantity, oct, ext, diff, tol, class, status)
    push!(ROWS, (layer=String(layer), fixture=String(fixture), quantity=String(quantity),
                 octopus=Float64(oct), external=Float64(ext), diff=Float64(diff), bound=Float64(tol),
                 class=String(class), status=String(status)))
end

"Gated comparison; relative when rel=true (bound tol * max(|ext|, 1))."
function compare_row(layer, fixture, quantity, oct::Real, ext::Real, tol::Real, class; rel::Bool=true)
    diff = abs(Float64(oct) - Float64(ext))
    bound = rel ? tol * max(abs(Float64(ext)), 1.0) : tol
    status = (isfinite(diff) && diff <= bound) ? "PASS" : "FAIL"
    println("TW-XSUITE ", fixture, " ", quantity, " ", fmt(oct), " ", fmt(ext), " ", fmt(diff), " ",
            fmt(bound), " ", class, " ", status)   # the APPLIED bound, so the line is self-checking
    record!(layer, fixture, quantity, oct, ext, diff, bound, class, status)   # the APPLIED bound is what the table keeps
    return status == "PASS"
end

# ---------------------------------------------------------------- printed lines
function witness_row(name, value::Real, expected::Real, tol::Real; rel::Bool=false, fixture="witness", layer="C0")
    diff = abs(Float64(value) - Float64(expected))
    bound = rel ? tol * max(abs(Float64(expected)), eps()) : tol
    status = (isfinite(diff) && diff <= bound) ? "PASS" : "FAIL"
    println("TW-XSUITE-WITNESS ", name, " ", fmt(value), " ", fmt(expected), " ", fmt(diff), " ", status)
    record!(layer, fixture, name, value, expected, diff, bound, rel ? "witness-rel" : "witness-abs", status)
    return status == "PASS"
end

function recorded_row(layer, fixture, quantity, oct::Real, ext::Real)
    diff = abs(Float64(oct) - Float64(ext))
    println("TW-XSUITE-RECORDED ", fixture, " ", quantity, " ", fmt(oct), " ", fmt(ext), " ", fmt(diff))
    record!(layer, fixture, quantity, oct, ext, diff, NaN, "recorded", "RECORDED")
    return diff
end

function recorded_note(layer, fixture, quantity, text::AbstractString)
    println("TW-XSUITE-RECORDED ", fixture, " ", quantity, " ", text)
    record!(layer, fixture, quantity, NaN, NaN, NaN, NaN, "recorded", "RECORDED")
end

"A boolean assertion printed as a witness with value 1/0 and expected 1."
assert_row(name, ok::Bool; fixture="witness", layer="C0") =
    witness_row(name, ok ? 1.0 : 0.0, 1.0, 0.0; fixture=fixture, layer=layer)

# ---------------------------------------------------------------- small algebra
Rt(theta::Real) = kron([cos(theta) -sin(theta); sin(theta) cos(theta)], Matrix{Float64}(I, 2, 2))
"The rank-2 invariant of mode j of a normalizer: columns 2j-1, 2j times their transpose."
mode_projector(U::AbstractMatrix, j::Integer) = (V = U[:, 2j-1:2j]; V * V')
"Least-squares slope of log(residual) against log(nst); the convergence order is minus that slope."
function fitted_order(nsts, residuals)
    x = log.(Float64.(collect(nsts))); y = log.(Float64.(collect(residuals)))
    xm = sum(x) / length(x); ym = sum(y) / length(y)
    return -sum((x .- xm) .* (y .- ym)) / sum((x .- xm) .^ 2)
end
maxabs(A) = maximum(abs, A)

# ---------------------------------------------------------------- the analysis
const ANALYSIS = TwissDispersionAnalysis(strict=false, scaling=:none)
reason_of(d) = is_determined(d) ? :none : d.reason
dval(d) = is_determined(d) ? determined_value(d) : nothing

"""
analyze a map (4x4 or 6x6, no conversion here) and gather every read the layers
need, each guarded by is_determined (rule D): tunes (rad/turn, eigen order), the
presented form, form-1 R, lambda and mode Twiss (triple unwrap, rule Y), the
physical normalizer, beta/alpha/gamma [mode, plane], graph = [zeta, eta/h], zeta,
eta, h, the coasting-route eta (printed only, rule S), the cluster reasons.
"""
function analyze_map(M::AbstractMatrix; mu_s=nothing)
    # mu_s (rad/turn, in (0, pi)) certifies the longitudinal selection on a bunched map (the default
    # :max_signed_z_area heuristic is UNCERTIFIED and leaves the status :degraded); here it is xtrack's own |mu3|
    an_obj = mu_s === nothing ? ANALYSIS : TwissDispersionAnalysis(strict=false, scaling=:none, longitudinal_mode=Float64(mu_s))
    result = analyze(an_obj, Matrix{Float64}(M))
    tunes = copy(result.physical.tunes)
    form = 0; R = nothing; twiss = nothing; lambda = NaN; twiss2 = nothing; lambda2 = NaN
    if is_determined(result.transverse)
        trv = determined_value(result.transverse)
        form = is_determined(trv.preferred_form) ? determined_value(trv.preferred_form) : 0
        if is_determined(trv.edwards_teng_normalizer)
            pair = determined_value(trv.edwards_teng_normalizer)
            f1 = pair.form1
            R = dval(f1.R); twiss = dval(f1.twiss)
            lambda = is_determined(f1.lambda) ? determined_value(f1.lambda) : NaN
            # form 2 is kept beside form 1: xtrack's ET form follows its mode LABEL (largest |v[0]|), not the
            # larger lambda, so on a strongly coupled map its g_edw_teng can be Octopus's form-2 lambda (D8_3)
            f2 = pair.form2
            twiss2 = dval(f2.twiss)
            lambda2 = is_determined(f2.lambda) ? determined_value(f2.lambda) : NaN
        end
    end
    ph = result.physical
    coasting_eta = (result.dispersion !== nothing && is_determined(result.dispersion.coasting.eta)) ?
                   determined_value(result.dispersion.coasting.eta) : nothing
    clusters = result.clusters.clusters
    return (result=result, status=result.status, tunes=tunes, form=form, R=R, twiss=twiss, lambda=lambda,
            twiss2=twiss2, lambda2=lambda2,
            U=dval(ph.normalizer), beta=dval(ph.beta), alpha=dval(ph.alpha), gamma=dval(ph.gamma),
            graph=dval(ph.graph), zeta=dval(ph.zeta), eta=dval(ph.eta), h=dval(ph.h),
            coasting=(result.coasting !== nothing && result.coasting.holds), coasting_eta=coasting_eta,
            degradations=copy(result.degradations), failures=copy(result.failures),
            cluster_class=[c.classification for c in clusters], cluster_reason=[c.reason for c in clusters],
            reasons=(beta=reason_of(ph.beta), alpha=reason_of(ph.alpha), gamma=reason_of(ph.gamma),
                     edwards_teng_R=reason_of(ph.edwards_teng_R), normalizer=reason_of(ph.normalizer),
                     eta=reason_of(ph.eta), zeta=reason_of(ph.zeta), h=reason_of(ph.h)))
end

"Index of the Octopus mode whose cos(tune) is closest to the real part of the unit eigenvalue (rule T: by eigenvalue, never by label)."
function match_mode(tunes::AbstractVector, lam::Complex)
    isempty(tunes) && return 0
    return argmin([abs(cos(mu) - real(lam) / abs(lam)) for mu in tunes])
end

"xtrack's eigenvalue of mode j (the first of its pair) as a complex number."
xeig(layer, fixture, compile, j) = complex(xcell(layer, fixture, compile, "eig$(2j-1)_re"), xcell(layer, fixture, compile, "eig$(2j-1)_im"))

"cos mu and sin mu of Octopus mode k against xtrack's eigenvalue lam (absolute tolerance)."
function tune_rows(layer, fixture, an, k::Integer, lam::Complex, label::AbstractString, tol::Real, class::AbstractString)
    c = real(lam) / abs(lam); s = imag(lam) / abs(lam)
    if k == 0
        ok = compare_row(layer, fixture, "cos_mu_$(label)", NaN, c, tol, class; rel=false)
        ok &= compare_row(layer, fixture, "sin_mu_$(label)", NaN, s, tol, class; rel=false)
        return ok
    end
    ok = compare_row(layer, fixture, "cos_mu_$(label)", cos(an.tunes[k]), c, tol, class; rel=false)
    ok &= compare_row(layer, fixture, "sin_mu_$(label)", sin(an.tunes[k]), s, tol, class; rel=false)
    return ok
end

# ---------------------------------------------------------------- C0 convention witnesses (rules W and X)
const BEAM = header_beam(XT.header)
const SHEAR_TARGET = DEFECT === :drop_shear ? :task : :bare   # drop_shear: the C2 conversion omits Sh(-C/gamma0^2)

"The xtrack lattice map converted to the Octopus BARE convention by the section 3 law (J0 = F = I)."
function converted_lattice_map(R::AbstractMatrix, C::Real)
    return convert_map(:xsuite, R; beta0=BEAM.beta0, gamma0=BEAM.gamma0, C=C, target=SHEAR_TARGET)
end

"""
Every witness is a formula in the table's own beta0/gamma0 and the fixture's C
(rule W); the rule X sign row runs here too. Returns false if any witness fails,
and the caller stops before any optics comparison.
"""
function witness_rows()
    ok = true
    # the beam pin (stage 8 decision D13) and the maps table's beam beside it
    ok &= witness_row("header_beta0_vs_pin", BEAM.beta0, BENCH_BETA0_PIN, BENCH_BETA0_ATOL)
    ok &= witness_row("header_gamma0_vs_pin", BEAM.gamma0, BENCH_GAMMA0_PIN, TOL_PIN)
    ok &= witness_row("maps_table_beta0_vs_header", parse(Float64, MCOLS["beta0"][1]), BEAM.beta0, TOL_PIN)
    # the C1 premise "both sides read the same matrix": the maps table the xtrack table was frozen from is the one
    # read here, by its sha256 against the sidecar's "input maps:" line
    sidecar_sha = let m = match(r"^input maps: \S+ sha256 ([0-9a-f]{64})"m, read(SIDECAR, String))
        m === nothing ? "" : m.captures[1]
    end
    maps_sha = bytes2hex(open(sha256, MAPS_TABLE))
    println("TW-XSUITE-NOTE maps_table_sha256 ", maps_sha, " sidecar ", isempty(sidecar_sha) ? "missing" : sidecar_sha)
    ok &= assert_row("maps_table_sha256_matches_sidecar", !isempty(sidecar_sha) && maps_sha == sidecar_sha)
    # S0: the 10 m drift; R[4,5] (python) is r56 here (1-based table indices)
    L = maps_C("S0", "bare")
    R0 = xmatrix("C0", "S0", "line4d", "r")
    slip0 = L / BEAM.gamma0^2
    ok &= witness_row("S0_r56_vs_L_over_gamma0sq(TOL-D_rel)", R0[5, 6], slip0, TOL_D_REL; rel=true, fixture="S0")
    ok &= witness_row("S0_table_L_over_gamma0sq_vs_formula", xcell("C0", "S0", "line4d", "L_over_gamma0sq"), slip0, TOL_PIN; fixture="S0")
    ok &= witness_row("S0_r65_zero", R0[6, 5], 0.0, TOL_PIN; fixture="S0")
    ok &= witness_row("S0_r12_r34_vs_L_maxabs", max(abs(R0[1, 2] - L), abs(R0[3, 4] - L)), 0.0, TOL_D_REL * L; fixture="S0")
    M0_bare = octopus_map("S0", "bare"); M0_task = octopus_map("S0", "task")
    conv0 = convert_map(:xsuite, R0; beta0=BEAM.beta0, gamma0=BEAM.gamma0, C=L, target=:bare)
    ok &= witness_row("S0_converted_vs_octopus_bare_maxabs(TOL-D_scale_1e-8)", maxabs(conv0 - M0_bare), 0.0, 1e-8; fixture="S0")
    recorded_row("C0", "S0", "xtrack_r56_vs_octopus_task_m56(both_carry_the_slip)", R0[5, 6], M0_task[5, 6])
    recorded_row("C0", "S0", "octopus_bare_m56", M0_bare[5, 6], 0.0)
    ok &= witness_row("S0_octopus_task_m56_vs_L_over_gamma0sq", M0_task[5, 6], slip0, TOL_PIN; fixture="S0")
    # 6D partnership asserted (section 3): the xtrack line and the Octopus task compile share u = +C/gamma0^2
    ok &= witness_row("S0_partnership_task_minus_bare_m56_vs_slip", M0_task[5, 6] - M0_bare[5, 6], slip0, TOL_PIN; fixture="S0")
    # rule X: the sign of the zeta row on the dispersive cell U2 (xtrack C2 line map vs Octopus bare map)
    RU2 = xmatrix("C2", "U2", "line4d", "r"); MU2 = octopus_map("U2", "bare")
    ok &= witness_row("U2_sign_r51_vs_octopus_m51", sign(RU2[5, 1]), sign(MU2[5, 1]), 0.0; fixture="U2")
    ok &= witness_row("U2_sign_r52_vs_octopus_m52", sign(RU2[5, 2]), sign(MU2[5, 2]), 0.0; fixture="U2")
    recorded_row("C0", "U2", "r51_vs_octopus_m51", RU2[5, 1], MU2[5, 1])
    recorded_row("C0", "U2", "r52_vs_octopus_m52", RU2[5, 2], MU2[5, 2])
    # W1: the lone cavity; xtrack lag=0 is the FLIPPED Octopus strength, so r65 = -M65 (TOL-D)
    RW1 = xmatrix("C0", "W1", "line6d", "r"); MW1 = octopus_map("W1", "bare")
    ok &= witness_row("W1_r65_vs_minus_octopus_m65(TOL-D_rel)", RW1[6, 5], -MW1[6, 5], TOL_D_REL; rel=true, fixture="W1")
    ok &= witness_row("W1_octopus_m65_vs_strength_k_over_beta0sq", MW1[6, 5],
                      RF_STRENGTH * 2pi * RF_FREQUENCY_HZ / (BENCH_BETA0 * CLIGHT) / BENCH_BETA0, 1e-12; rel=true, fixture="W1")
    ok &= witness_row("W1_r56_zero", RW1[5, 6], 0.0, TOL_D_REL; fixture="W1")
    # the lone rolled quadrupole (L 0.2, k1 1.0, rot_s_rad 0.05) against the Octopus tilt (Rt(t) M(0) Rt(t)')
    t = K_TILT
    Rq = xmatrix("C0", "Q_rot0.05", "line4d", "r")[1:4, 1:4]
    Mq0 = bare_map(compile_cell((_quad(0.2, 1.0; nst=DEFAULT_NST, order=DEFAULT_ORDER),)))[1:4, 1:4]
    Mqt = bare_map(compile_cell((_quad(0.2, 1.0; nst=DEFAULT_NST, order=DEFAULT_ORDER, tilt=t),)))[1:4, 1:4]
    ok &= witness_row("Qrot_xtrack_vs_octopus_tilt_maxabs(model,1e-10)", maxabs(Rq - Mqt), 0.0, 1e-10; fixture="Q_rot0.05")
    ok &= witness_row("Qrot_xtrack_vs_Rt(t)M0Rt(t)'_maxabs(1e-10)", maxabs(Rq - Rt(t) * Mq0 * Rt(t)'), 0.0, 1e-10; fixture="Q_rot0.05")
    recorded_row("C0", "Q_rot0.05", "other_sense_Rt(t)'M0Rt(t)_maxabs", maxabs(Rq - Rt(t)' * Mq0 * Rt(t)), 0.0)
    ok &= witness_row("Qrot_octopus_tilt_vs_Rt(t)M0Rt(t)'_maxabs", maxabs(Mqt - Rt(t) * Mq0 * Rt(t)'), 0.0, TOL_MAP; fixture="Q_rot0.05")
    return ok
end

# ---------------------------------------------------------------- C1 matrix level (same matrix both sides)
const ROLLED_C1 = ("R_0.1", "R_pi4")
const DETUNED_C1 = ("Rd_1e-3", "Rd_1e-6")
const COUPLED_C1 = ("K1", "K2", "D6_1", "D6_2", "D6_3", "D8_1", "D8_2", "D8_3")   # the presented ET form is asserted 1 here
const ROLLED_EXACT_COS = 0.9744003972058644     # theory 13.10's cos mu of the equal-tune cell (recorded beside the map's own)
# xtrack's Mais-Ripken names by (mode, plane): mode 1 = (betx, bety1), mode 2 = (betx2, bety); alpha and gamma alike
const MR_NAMES = Dict((1, 1) => ("betx", "alfx", "gamx"), (1, 2) => ("bety1", "alfy1", "gamy1"),
                      (2, 1) => ("betx2", "alfx2", "gamx2"), (2, 2) => ("bety", "alfy", "gamy"))
const ET_NAMES = Dict(1 => ("betx_edw_teng", "alfx_edw_teng"), 2 => ("bety_edw_teng", "alfy_edw_teng"))

"D8: Octopus refuses the degenerate frame with reason symbols, never a tune."
function reason_rows(layer, fixture, an, label)
    ok = assert_row("$(fixture)_$(label)_status_passed", an.status === :passed; fixture=fixture, layer=layer)
    ok &= assert_row("$(fixture)_$(label)_tunes_empty", isempty(an.tunes); fixture=fixture, layer=layer)
    for f in (:beta, :alpha, :gamma, :edwards_teng_R)
        ok &= assert_row("$(fixture)_$(label)_$(f)_reason_cluster_unresolved", getfield(an.reasons, f) === :cluster_unresolved; fixture=fixture, layer=layer)
    end
    idx = findall(==(:cluster_unresolved), an.cluster_reason)
    ok &= assert_row("$(fixture)_$(label)_unresolved_cluster_classified_definite",
                     !isempty(idx) && all(an.cluster_class[i] === :definite for i in idx); fixture=fixture, layer=layer)
    return ok
end

"The rolled cells in C1: label-free cos mu of the 4x4 block against xtrack's two modes (TOL-F), then the reason rows."
function c1_rolled(fixture, compile, M, an)
    ok = true
    lam4 = eigvals(M[1:4, 1:4])
    coss = sort(unique(round.(real.(lam4) ./ abs.(lam4); digits=14)))
    for j in 1:2
        lam = xeig("C1", fixture, compile, j)
        c = real(lam) / abs(lam)
        k = argmin(abs.(coss .- c))
        ok &= compare_row("C1", fixture, "cos_mu_mode$(j)_vs_4x4_block_eigenvalue", coss[k], c, TOL_F_ABS, "TOL-F"; rel=false)
        ok &= compare_row("C1", fixture, "eigen_modulus_mode$(j)", abs(lam), 1.0, TOL_F_ABS, "TOL-F"; rel=false)
        recorded_row("C1", fixture, "xtrack_cos_mu_mode$(j)_vs_theory_13.10_constant", c, ROLLED_EXACT_COS)
        recorded_row("C1", fixture, "xtrack_label_decided_betx_mode$(j)", xcell("C1", fixture, compile, j == 1 ? "betx" : "betx2"), NaN)
    end
    ok &= reason_rows("C1", fixture, an, "matrix")
    return ok
end

"""
Transverse rows of one C1 fixture: cos/sin mu per xtrack mode (matched by
eigenvalue), the Mais-Ripken beta/alpha/gamma by (matched mode, plane), the
Edwards-Teng mode functions and lambda (form 1), the rank-2 normalizer
invariant. Returns (ok, k) with k the Octopus mode index of each xtrack mode.
"""
function c1_transverse(fixture, compile, an, W::AbstractMatrix, nmodes::Int, tol_rel, tol_abs, class)
    ok = true
    # :degraded is accepted (the values stay Determined and are gated below); the text is printed beside it
    ok &= assert_row("$(fixture)_analyze_status_not_failed", an.status !== :failed; fixture=fixture, layer="C1")
    an.status === :passed || recorded_note("C1", fixture, "octopus_status_$(an.status)", join(vcat(an.degradations, an.failures), " | "))
    ks = zeros(Int, nmodes)
    for j in 1:nmodes
        lam = xeig("C1", fixture, compile, j)
        ks[j] = match_mode(an.tunes, lam)
        ok &= tune_rows("C1", fixture, an, ks[j], lam, "mode$(j)", tol_abs, class)
    end
    ok &= assert_row("$(fixture)_modes_matched_distinct", all(ks .> 0) && length(unique(ks)) == nmodes; fixture=fixture, layer="C1")
    if fixture in COUPLED_C1
        ok &= assert_row("$(fixture)_presented_ET_form_is_1", an.form == 1; fixture=fixture, layer="C1")
    else
        recorded_row("C1", fixture, "presented_ET_form", an.form, 1.0)
    end
    # Mais-Ripken by (matched mode, plane): xtrack's mode 1 and 2 only carry transverse names
    for j in 1:2, plane in 1:2
        names = MR_NAMES[(j, plane)]
        for (field, name) in zip((:beta, :alpha, :gamma), names)
            A = getfield(an, field)
            v = (A === nothing || ks[j] == 0) ? NaN : A[ks[j], plane]
            ok &= compare_row("C1", fixture, "MR_$(name)", v, xcell("C1", fixture, compile, name), tol_rel, class; rel=(class != "TOL-F"))
        end
    end
    # Edwards-Teng mode functions (rule Y, form 1) and lambda. Octopus's form1.twiss is the 4D Edwards-Teng
    # decomposition of the transverse block (two entries); xtrack's betx_edw_teng is betx1/sqrt(betx1 gamx1 - alfx1^2)
    # on the Mais-Ripken functions of the FULL normalizer, so on a bunched map (three modes) the two are
    # different objects (measured 3-15 percent apart) and the rows are RECORDED there, gated on 4D/coasting maps.
    # Octopus presents form 1 (asserted above); xtrack's ET form follows its mode label (largest |v[1]|), so the
    # Octopus form compared is selected WITHOUT reading the external table: xtrack's own (T15) formula
    # lambda = (betx1 gamx1 - alfx1^2)^(1/4) evaluated on OCTOPUS's Mais-Ripken functions of the mode matched to
    # xtrack's mode 1 (gated above at TOL-A) gives lambda_int; the form whose lambda is nearer lambda_int is
    # compared, and g_edw_teng stays a real test of it (fix_C E1; D8_3 selects form 2, D8_1/D8_2 form 1)
    gate_et = nmodes == 2
    g = xcell("C1", fixture, compile, "g_edw_teng")
    k1 = ks[1]
    lam_int = (k1 == 0 || any(A -> A === nothing, (an.beta, an.alpha, an.gamma))) ? NaN :
              (an.beta[k1, 1] * an.gamma[k1, 1] - an.alpha[k1, 1]^2)^0.25
    recorded_row("C1", fixture, "lambda_internal_(T15)_on_octopus_MR_mode1_vs_g_edw_teng", lam_int, g)
    use2 = isfinite(an.lambda2) && isfinite(lam_int) && abs(an.lambda2 - lam_int) < abs(an.lambda - lam_int)
    tw_et = use2 ? an.twiss2 : an.twiss
    lam_et = use2 ? an.lambda2 : an.lambda
    recorded_row("C1", fixture, "octopus_ET_form_selected_by_lambda_internal(vs_presented_form)", use2 ? 2.0 : 1.0, Float64(an.form))
    for j in 1:2
        bname, aname = ET_NAMES[j]
        tw = (tw_et === nothing || ks[j] == 0 || ks[j] > length(tw_et)) ? nothing : tw_et[ks[j]]
        for (name, v) in ((bname, tw === nothing ? NaN : tw.beta), (aname, tw === nothing ? NaN : tw.alpha))
            if gate_et
                ok &= compare_row("C1", fixture, "ET_$(name)", v, xcell("C1", fixture, compile, name), tol_rel, class; rel=(class != "TOL-F"))
            else
                recorded_row("C1", fixture, "ET4D_$(name)_vs_xtrack_6D_formula(different_object)", v, xcell("C1", fixture, compile, name))
            end
        end
    end
    if gate_et
        ok &= compare_row("C1", fixture, "ET_lambda_vs_g_edw_teng", lam_et, g, tol_rel, class; rel=(class != "TOL-F"))
    else
        recorded_row("C1", fixture, "ET4D_lambda_vs_xtrack_6D_g_edw_teng(different_object)", lam_et, g)
    end
    # the rank-2 normalizer invariant W_j W_j' vs U_k U_k' (gauge- and label-free), modes matched by eigenvalue
    if an.U === nothing
        ok &= compare_row("C1", fixture, "rank2_projector_maxabs_rel", NaN, 0.0, tol_rel, class; rel=false)
    else
        d = size(an.U, 1)
        for j in 1:nmodes
            P = mode_projector(W[1:d, 1:d], j)
            Q = ks[j] == 0 ? fill(NaN, d, d) : mode_projector(an.U, ks[j])
            ok &= compare_row("C1", fixture, "rank2_projector_mode$(j)_maxabs_rel", maxabs(P - Q) / maxabs(Q), 0.0, tol_rel, class; rel=false)
        end
    end
    return (ok=ok, ks=ks)
end

const DISP_NAMES = ("dx", "dpx", "dy", "dpy")

"""
Dispersion rows of one C1 fixture (theory (X2), two columns). Bunched 6x6 map:
dx..dpy against physical.graph[:,2] (= eta/h), dx_zeta.. against physical.zeta,
physical.h against det(U_ls) of xtrack's own normalizer, and physical.eta against
h * dx with the un-repaired gap |dx - eta| printed (theory 9.5). All rows read the
same exact matrix on both sides, so they carry the fixture's TOL-A class. Coasting 6x6 map: xtrack's W-route dx is 0 by construction on the
only_4d_block form, so the compared external number is its own 4d route dx_4d;
the reciprocal-scaled coasting.eta is printed beside physical.eta (rule S).
"""
function c1_dispersion(fixture, compile, an, bunched::Bool, W::AbstractMatrix, tol_rel, class)
    ok = true
    rel = class != "TOL-F"
    if bunched
        G = an.graph
        for (r, name) in enumerate(DISP_NAMES)
            ok &= compare_row("C1", fixture, "$(name)_vs_graph[:,2]", G === nothing ? NaN : G[r, 2], xcell("C1", fixture, compile, name), tol_rel, class; rel=rel)
        end
        for (r, name) in enumerate(DISP_NAMES)
            ok &= compare_row("C1", fixture, "$(name)_zeta_vs_physical_zeta", an.zeta === nothing ? NaN : an.zeta[r], xcell("C1", fixture, compile, "$(name)_zeta"), tol_rel, class; rel=rel)
        end
        # h itself, gated against an external construction of it: h = det(U_ls) = W55 W66 - W56 W65 of xtrack's own
        # normalizer (theory (X2): D = U_rs U_ls^-1 = [zeta, eta/h]); the eta rows below are then h times the graph rows
        h = an.h === nothing ? NaN : an.h
        ok &= compare_row("C1", fixture, "physical_h_vs_det(U_ls)", h, W[5, 5] * W[6, 6] - W[5, 6] * W[6, 5], tol_rel, class; rel=rel)
        for (r, name) in enumerate(DISP_NAMES)
            dxt = xcell("C1", fixture, compile, name)
            eta_r = an.eta === nothing ? NaN : an.eta[r]
            ok &= compare_row("C1", fixture, "physical_eta_vs_h*$(name)", eta_r, h * dxt, tol_rel, class; rel=rel)
            r == 1 && recorded_row("C1", fixture, "unrepaired_gap_|dx-eta_x|_without_h", dxt, eta_r)
        end
        recorded_row("C1", fixture, "xtrack_4d_route_dx_4d_beside_eta_x(different_object)", xcell("C1", fixture, compile, "dx_4d"), an.eta === nothing ? NaN : an.eta[1])
    else
        for (r, name) in enumerate(DISP_NAMES)
            ok &= compare_row("C1", fixture, "eta_$(name)_vs_xtrack_4d_route_$(name)_4d", an.eta === nothing ? NaN : an.eta[r], xcell("C1", fixture, compile, "$(name)_4d"), tol_rel, class; rel=rel)
        end
        for (r, name) in enumerate(DISP_NAMES)
            ok &= compare_row("C1", fixture, "zeta_$(name)_vs_xtrack_$(name)_zeta_4d(0_vs_0)", an.zeta === nothing ? NaN : an.zeta[r], xcell("C1", fixture, compile, "$(name)_zeta_4d"), tol_rel, class; rel=rel)
        end
        recorded_row("C1", fixture, "xtrack_W_route_dx_on_only_4d_block(0_by_construction)", xcell("C1", fixture, compile, "dx"), 0.0)
        recorded_row("C1", fixture, "physical_h_coasting", an.h === nothing ? NaN : an.h, 1.0)
        if an.coasting_eta !== nothing && an.eta !== nothing
            recorded_row("C1", fixture, "coasting_eta_x(reciprocal_scaled_trap)_beside_physical_eta_x", an.coasting_eta[1], an.eta[1])
        end
    end
    return ok
end

# fixture id, maps-table compile, matrix dimension
const C1_FIXTURES = (("U1", "bare", 6), ("U2", "bare", 6), ("K1", "bare", 6), ("K2", "bare", 6),
                     ("R_0.1", "bare", 6), ("R_pi4", "bare", 6), ("Rd_1e-3", "bare", 6), ("Rd_1e-6", "bare", 6),
                     ("B4", "bare", 6), ("B5", "bare", 6), ("T6", "task", 6),
                     ("D6_1", "matrix", 6), ("D6_2", "matrix", 6), ("D6_3", "matrix", 6),
                     ("D8_1", "matrix", 4), ("D8_2", "matrix", 4), ("D8_3", "matrix", 4))

function matrix_layer()
    ok = true
    for (fixture, compile, dim) in C1_FIXTURES
        M = octopus_map(fixture, compile; dim=dim)
        only4d = xcell("C1", fixture, compile, "only_4d_block") == 1.0
        W = xmatrix("C1", fixture, compile, "W")
        recorded_row("C1", fixture, "xtrack_normal_form_residual_maxabs", xcell("C1", fixture, compile, "normal_form_residual_maxabs"), 0.0)
        recorded_row("C1", fixture, "octopus_symplectic_residual", symplectic_residual(M), 0.0)
        bunched = dim == 6 && !only4d
        # on a bunched map the longitudinal selection is certified by xtrack's own |mu3| (rad/turn)
        an = bunched ? analyze_map(M; mu_s=abs(xcell("C1", fixture, compile, "mu3"))) : analyze_map(M)
        bunched && recorded_note("C1", fixture, "longitudinal_mode_certified_by_xtrack_mu3", fmt(abs(xcell("C1", fixture, compile, "mu3"))))
        if fixture in ROLLED_C1
            ok &= c1_rolled(fixture, compile, M, an)
            continue
        end
        if fixture == "Rd_1e-6"
            # eps = 1e-6 splits the pair by 3.4e-7 turns; the frame is conditioned at eps_mach/split ~ 6.5e-10,
            # above TOL-F, and Octopus's own (E7) gate refuses the frame: RECORDED, not gated (see the report)
            recorded_note("C1", fixture, "octopus_status", string(an.status, " ", join(an.failures, "; ")))
            for j in 1:2
                lam = xeig("C1", fixture, compile, j); k = match_mode(an.tunes, lam)
                k == 0 && continue
                recorded_row("C1", fixture, "cos_mu_mode$(j)", cos(an.tunes[k]), real(lam) / abs(lam))
                recorded_row("C1", fixture, "MR_$(MR_NAMES[(j, j)][1])", an.beta === nothing ? NaN : an.beta[k, j], xcell("C1", fixture, compile, MR_NAMES[(j, j)][1]))
                an.twiss === nothing || k > 2 || recorded_row("C1", fixture, "ET_$(ET_NAMES[j][1])", an.twiss[k].beta, xcell("C1", fixture, compile, ET_NAMES[j][1]))
            end
            continue
        end
        detuned = fixture in DETUNED_C1
        tol_rel = detuned ? TOL_F_ABS : TOL_A_REL
        tol_abs = detuned ? TOL_F_ABS : TOL_A_ABS
        class = detuned ? "TOL-F" : "TOL-A"
        # the normalizer's conditioning: the manufactured dense maps (D6_*, D8_*) are gated at TOL-A widened to
        # 10 kappa(U)^2 eps_mach when that exceeds 1e-12 (D8_2: kappa 174, measured 1.6e-12 relative on beta 102)
        kappa = an.U === nothing ? NaN : cond(an.U)
        recorded_row("C1", fixture, "normalizer_condition_number_kappa(U)", kappa, 1.0)
        if startswith(fixture, "D") && !detuned && isfinite(kappa) && 10 * kappa^2 * eps() > tol_rel
            tol_rel = 10 * kappa^2 * eps()
            class = "TOL-A-cond"
            recorded_note("C1", fixture, "TOL-A_widened_by_conditioning_to", fmt(tol_rel))
        end
        nmodes = only4d ? 2 : 3
        tr = c1_transverse(fixture, compile, an, W, nmodes, tol_rel, tol_abs, class)
        ok &= tr.ok
        if dim == 6
            ok &= assert_row("$(fixture)_coasting_structure_$(bunched ? "absent" : "present")", an.coasting == !bunched; fixture=fixture, layer="C1")
            ok &= c1_dispersion(fixture, compile, an, bunched, W, tol_rel, class)
        end
    end
    return ok
end

# ---------------------------------------------------------------- C2 lattice level (xtrack Line.twiss 4d twins)
const C2_FIXTURES = ("U1", "U2", "K1", "K2", "R_0.1", "R_pi4", "Rd_1e-3", "Rd_1e-6")
const C2_ORDERED = ("U1", "U2", "K1", "K2")          # the ladder gate (TOL-E) and the dispersion rows (TOL-D)
const C2_ROLLED = ("R_0.1", "R_pi4")                  # label-free rows at TOL-F and the reason symbols (D8)
const CELL_BUILDERS = Dict{String,Function}(
    "U1" => (; kw...) -> U1(; kw...), "U2" => (; kw...) -> U2(; kw...),
    "K1" => (; kw...) -> K1(; tilt=K_TILT, kw...), "K2" => (; kw...) -> K2(; tilt=K_TILT, kw...),
    "R_0.1" => (; kw...) -> rolled_fodo(0.1; kw...), "R_pi4" => (; kw...) -> rolled_fodo(pi / 4; kw...),
    "Rd_1e-3" => (; kw...) -> Rd(1e-3; kw...), "Rd_1e-6" => (; kw...) -> Rd(1e-6; kw...))

xc2(fixture, q) = xcell("C2", fixture, "line4d", q)

"""
The lattice functions of Octopus's analysis of one map against xtrack's tw
(4d): returns the largest relative difference over betx, bety, alfx, alfy
(Mais-Ripken by matched mode and plane), the ET mode beta/alpha, cos/sin of
both tunes; the modes are matched by eigenvalue from xtrack's cos_mux/sin_mux.
Prints nothing; the caller prints the ladder.
"""
function c2_lattice_residual(fixture, an)
    an.status === :passed || return NaN
    lam1 = complex(xc2(fixture, "cos_mux"), xc2(fixture, "sin_mux"))
    lam2 = complex(xc2(fixture, "cos_muy"), xc2(fixture, "sin_muy"))
    k1 = match_mode(an.tunes, lam1); k2 = match_mode(an.tunes, lam2)
    (k1 == 0 || k2 == 0 || k1 == k2 || an.beta === nothing || an.alpha === nothing || an.twiss === nothing) && return NaN
    rel(a, b) = abs(a - b) / max(abs(b), 1.0)
    worst = 0.0
    worst = max(worst, rel(an.beta[k1, 1], xc2(fixture, "betx")), rel(an.beta[k2, 2], xc2(fixture, "bety")))
    worst = max(worst, rel(an.alpha[k1, 1], xc2(fixture, "alfx")), rel(an.alpha[k2, 2], xc2(fixture, "alfy")))
    worst = max(worst, rel(an.twiss[k1].beta, xc2(fixture, "betx_edw_teng")), rel(an.twiss[k2].beta, xc2(fixture, "bety_edw_teng")))
    worst = max(worst, rel(an.twiss[k1].alpha, xc2(fixture, "alfx_edw_teng")), rel(an.twiss[k2].alpha, xc2(fixture, "alfy_edw_teng")))
    worst = max(worst, abs(cos(an.tunes[k1]) - real(lam1)), abs(sin(an.tunes[k1]) - imag(lam1)))
    worst = max(worst, abs(cos(an.tunes[k2]) - real(lam2)), abs(sin(an.tunes[k2]) - imag(lam2)))
    return worst
end

"The nst=64 lattice functions printed one by one (RECORDED: the gate is the ladder's order)."
function c2_lattice_rows(fixture, an)
    lam1 = complex(xc2(fixture, "cos_mux"), xc2(fixture, "sin_mux"))
    lam2 = complex(xc2(fixture, "cos_muy"), xc2(fixture, "sin_muy"))
    k1 = match_mode(an.tunes, lam1); k2 = match_mode(an.tunes, lam2)
    (k1 == 0 || k2 == 0) && return
    recorded_row("C2", fixture, "nst64_cos_mux", cos(an.tunes[k1]), real(lam1))
    recorded_row("C2", fixture, "nst64_cos_muy", cos(an.tunes[k2]), real(lam2))
    if an.beta !== nothing && an.alpha !== nothing
        recorded_row("C2", fixture, "nst64_MR_betx", an.beta[k1, 1], xc2(fixture, "betx"))
        recorded_row("C2", fixture, "nst64_MR_bety", an.beta[k2, 2], xc2(fixture, "bety"))
        recorded_row("C2", fixture, "nst64_MR_alfx", an.alpha[k1, 1], xc2(fixture, "alfx"))
        recorded_row("C2", fixture, "nst64_MR_alfy", an.alpha[k2, 2], xc2(fixture, "alfy"))
    end
    if an.twiss !== nothing
        recorded_row("C2", fixture, "nst64_ET_betx_edw_teng", an.twiss[k1].beta, xc2(fixture, "betx_edw_teng"))
        recorded_row("C2", fixture, "nst64_ET_bety_edw_teng", an.twiss[k2].beta, xc2(fixture, "bety_edw_teng"))
    end
    recorded_row("C2", fixture, "nst64_ET_lambda_vs_g_edw_teng", an.lambda, xc2(fixture, "g_edw_teng"))
    recorded_row("C2", fixture, "presented_ET_form", an.form, 1.0)
end

"Dispersion of the coasting lattice map (TOL-D): physical.eta of the nst=64 Octopus map against tw.dx..dpy."
function c2_dispersion_rows(fixture, an)
    ok = true
    for (r, name) in enumerate(DISP_NAMES)
        ok &= compare_row("C2", fixture, "eta_$(name)_vs_tw_$(name)", an.eta === nothing ? NaN : an.eta[r], xc2(fixture, name), TOL_D_REL, "TOL-D")
    end
    if an.coasting_eta !== nothing && an.eta !== nothing
        recorded_row("C2", fixture, "coasting_eta_x(reciprocal_scaled_trap)_beside_physical_eta_x", an.coasting_eta[1], an.eta[1])
    end
    return ok
end

"""
One C2 fixture: xtrack's 4d line map converted by the section 3 law (bare
target; the drop_shear defect omits the shear), the Octopus model ladder over
nst with the fitted order (TOL-E) and the frozen nst=64 cap, the lattice
functions over the same ladder, the dispersion (TOL-D), the label-free rows of
the rolled cells (TOL-F) and Octopus's reason symbols there (D8).
"""
function lattice_fixture(fixture)
    ok = true
    R = xmatrix("C2", fixture, "line4d", "r")
    C = xc2(fixture, "C")
    ok &= witness_row("$(fixture)_C_vs_maps_table_C", C, maps_C(fixture, "bare"), TOL_PIN; fixture=fixture, layer="C2")
    recorded_row("C2", fixture, "xtrack_eigen_modulus_departure_maxabs", maximum(abs(xc2(fixture, "eigmod$(j)") - 1) for j in 1:6), 0.0)
    recorded_row("C2", fixture, "xtrack_c_minus", xc2(fixture, "c_minus"), 0.0)
    Mconv = converted_lattice_map(R, C)
    recorded_row("C2", fixture, "converted_m56_beside_xtrack_r56(shear_removed_unless_drop_shear)", Mconv[5, 6], R[5, 6])
    build = CELL_BUILDERS[fixture]
    residuals = Float64[]; fres = Float64[]; an64 = nothing
    for nst in NST_LADDER
        Moct = bare_map(build(; nst=nst))
        # the ladder residual is the transverse 4x4 block: rows/columns 5-6 of the xtrack map are finite
        # differences at the TOL-D scale (r56 alone sits at 3.7e-10..5e-9 after conversion) and would flatten the fit
        r = maxabs(Moct[1:4, 1:4] - Mconv[1:4, 1:4]); push!(residuals, r)
        an = analyze_map(Moct)
        fr = c2_lattice_residual(fixture, an); push!(fres, fr)
        println("TW-XSUITE-MODEL ", fixture, " ", nst, " ", fmt(r))
        println("TW-XSUITE-NOTE ", fixture, " lattice_functions_maxrel_nst", nst, " ", fmt(fr))
        record!("C2", fixture, "model_maxabs_nst$(nst)", r, 0.0, r, NaN, "model", "MODEL")
        record!("C2", fixture, "lattice_functions_maxrel_nst$(nst)", fr, 0.0, fr, NaN, "model", "MODEL")
        if nst == DEFAULT_NST
            an64 = an
            ok &= witness_row("$(fixture)_built_nst64_vs_maps_table_maxabs", maxabs(Moct - octopus_map(fixture, "bare")), 0.0, TOL_MAP; fixture=fixture, layer="C2")
            D = abs.(Moct - Mconv) ./ max.(abs.(Mconv), 1.0)
            long = maximum(D[i, j] for i in 1:6, j in 1:6 if i > 4 || j > 4)
            ok &= compare_row("C2", fixture, "rows_cols_5_6_maxscaled_nst64", long, 0.0, TOL_D_REL, "TOL-D"; rel=false)
            recorded_row("C2", fixture, "r56_converted_minus_octopus_nst64", Mconv[5, 6], Moct[5, 6])
        end
    end
    order = fitted_order(NST_LADDER, residuals)
    forder = fitted_order(NST_LADDER, fres)
    gated = fixture in C2_ORDERED
    cap_ok = !isfinite(NST64_CAP) || residuals[end] <= NST64_CAP
    order_ok = abs(order - ORDER_TARGET) <= ORDER_BAND && cap_ok
    status = gated ? (order_ok ? "PASS" : "FAIL") : "RECORDED"
    if gated
        println("TW-XSUITE-ORDER ", fixture, " ", fmt(order), " ", fmt(NST64_CAP), " ", status)
    else
        println("TW-XSUITE-RECORDED ", fixture, " model_fitted_order(not_gated) ", fmt(order), " ", fmt(ORDER_TARGET), " ", fmt(abs(order - ORDER_TARGET)))
    end
    println("TW-XSUITE-NOTE ", fixture, " model_nst64_residual_vs_frozen_cap ", fmt(residuals[end]), " ", fmt(NST64_CAP))
    record!("C2", fixture, "model_fitted_order", order, ORDER_TARGET, abs(order - ORDER_TARGET), ORDER_BAND, "TOL-E", status)
    record!("C2", fixture, "model_nst64_vs_frozen_cap", residuals[end], NST64_CAP, residuals[end], NST64_CAP, "TOL-E", status)
    gated && (ok &= order_ok)
    recorded_row("C2", fixture, "nst32_block_residual(design_1e-9_reference,not_gated_per_A2_precedent)", residuals[end-1], 1e-9)
    recorded_row("C2", fixture, "nst4_block_residual(recipe_row)", residuals[1], 0.0)
    # the lattice functions converge with the map until the FD floor of the 4x4 block (about 1e-10); their order
    # is fitted on the ladder points above ten times TOL-F only, and recorded (the transverse gate is the map's order)
    above = [i for i in eachindex(fres) if isfinite(fres[i]) && fres[i] > 10 * TOL_F_ABS]
    forder_above = length(above) >= 3 ? fitted_order(collect(NST_LADDER)[above], fres[above]) : NaN
    recorded_row("C2", fixture, "lattice_functions_fitted_order(all_points)", forder, ORDER_TARGET)
    recorded_row("C2", fixture, "lattice_functions_fitted_order(points_above_1e-9)", forder_above, ORDER_TARGET)
    recorded_row("C2", fixture, "lattice_functions_maxrel_at_nst64", fres[end], 0.0)
    if fixture in C2_ROLLED
        lam4 = eigvals(Mconv[1:4, 1:4])
        coss = sort(unique(round.(real.(lam4) ./ abs.(lam4); digits=14)))
        cx = cos(2pi * xc2(fixture, "qx")); cy = cos(2pi * xc2(fixture, "qy"))
        ok &= compare_row("C2", fixture, "cos_2pi_qx_vs_converted_4x4_eigenvalue", coss[argmin(abs.(coss .- cx))], cx, TOL_F_ABS, "TOL-F"; rel=false)
        ok &= compare_row("C2", fixture, "cos_2pi_qy_vs_converted_4x4_eigenvalue", coss[argmin(abs.(coss .- cy))], cy, TOL_F_ABS, "TOL-F"; rel=false)
        ok &= compare_row("C2", fixture, "cos_mux_vs_cos_muy(equal_tunes)", xc2(fixture, "cos_mux"), xc2(fixture, "cos_muy"), TOL_F_ABS, "TOL-F"; rel=false)
        recorded_row("C2", fixture, "xtrack_cos_mux_vs_theory_13.10_constant", xc2(fixture, "cos_mux"), ROLLED_EXACT_COS)
        recorded_row("C2", fixture, "xtrack_label_decided_betx", xc2(fixture, "betx"), NaN)
        ok &= reason_rows("C2", fixture, an64, "lattice")
    elseif fixture == "Rd_1e-6"
        recorded_note("C2", fixture, "octopus_status", string(an64.status, " ", join(an64.failures, "; ")))
        c2_lattice_rows(fixture, an64)
    else
        ok &= assert_row("$(fixture)_nst64_status_not_failed", an64.status !== :failed; fixture=fixture, layer="C2")
        an64.status === :passed || recorded_note("C2", fixture, "octopus_status_$(an64.status)", join(vcat(an64.degradations, an64.failures), " | "))
        if fixture in DETUNED_C1
            # Rd_1e-3: the near-degenerate pair at TOL-F, label-free through the eigenvalue match
            for (q, cq, sq) in (("x", "cos_mux", "sin_mux"), ("y", "cos_muy", "sin_muy"))
                lam = complex(xc2(fixture, cq), xc2(fixture, sq))
                ok &= tune_rows("C2", fixture, an64, match_mode(an64.tunes, lam), lam, "q$(q)", TOL_F_ABS, "TOL-F")
            end
        else
            ok &= assert_row("$(fixture)_coasting_structure_present", an64.coasting; fixture=fixture, layer="C2")
            fixture in ("K1", "K2") && (ok &= assert_row("$(fixture)_presented_ET_form_is_1", an64.form == 1; fixture=fixture, layer="C2"))
        end
        c2_lattice_rows(fixture, an64)
    end
    if fixture in C2_ORDERED || fixture in C2_ROLLED
        ok &= c2_dispersion_rows(fixture, an64)
    else
        an64.eta === nothing || recorded_row("C2", fixture, "eta_x_vs_tw_dx", an64.eta[1], xc2(fixture, "dx"))
    end
    return ok
end

function lattice_layer()
    ok = true
    for fixture in C2_FIXTURES
        ok &= lattice_fixture(fixture)
    end
    return ok
end

# ---------------------------------------------------------------- C3 the 6D twin (T6: U2 with one cavity)
xc3(q) = xcell("C3", "T6", "line6d", q)

"""
The longitudinal 2x2 witness runs BEFORE any transverse row: the xtrack 6d
line map converted with target=:task (both twins carry the slip +C/gamma0^2,
no shear) against the Octopus T6 task map, entries (5,5),(5,6),(6,5),(6,6) at
TOL-D. If it fails the whole layer is RECORDED (D5 fallback) and gates nothing.
Otherwise tw6 betx/bety/alfx/alfy (Mais-Ripken by matched mode) and
physical.eta against eta = h * tw6_dx are gated at TOL-D (Octopus side first).
"""
function longitudinal_layer()
    ok = true
    f = "T6"
    R = xmatrix("C3", f, "line6d", "r"); R6 = xmatrix("C3", f, "line6d", "tw6_r")
    recorded_row("C3", f, "xtrack_R_vs_tw6_R_matrix_maxabs", maxabs(R - R6), 0.0)
    recorded_row("C3", f, "xtrack_stable_flag", xc3("stable"), 1.0)
    recorded_row("C3", f, "xtrack_eigen_modulus_departure_maxabs", maximum(abs(xc3("eigmod$(j)") - 1) for j in 1:6), 0.0)
    recorded_row("C3", f, "xtrack_free_closed_orbit_R_shift_maxabs", xc3("co_free_R_shift_maxabs"), 0.0)
    for q in ("x", "px", "y", "py", "zeta", "delta")
        recorded_row("C3", f, "xtrack_free_closed_orbit_$(q)", xc3("co_free_$(q)"), 0.0)
    end
    C = xc3("C")
    ok &= witness_row("T6_C_vs_maps_table_C", C, maps_C(f, "task"), TOL_PIN; fixture=f, layer="C3")
    Mt = octopus_map(f, "task")
    Mconv = convert_map(:xsuite, R; beta0=BEAM.beta0, gamma0=BEAM.gamma0, C=C, target=:task)
    wit = true
    for (i, j) in ((5, 5), (5, 6), (6, 5), (6, 6))
        wit &= witness_row("T6_longitudinal_r$(i)$(j)_vs_task_m$(i)$(j)(TOL-D_rel)", Mconv[i, j], Mt[i, j], TOL_D_REL; rel=true, fixture=f, layer="C3")
    end
    recorded_row("C3", f, "converted_vs_octopus_task_6x6_maxabs", maxabs(Mconv - Mt), 0.0)
    recorded_row("C3", f, "converted_vs_octopus_task_4x4_block_maxabs", maxabs(Mconv[1:4, 1:4] - Mt[1:4, 1:4]), 0.0)
    an = analyze_map(Mt; mu_s=2pi * abs(xc3("tw6_qs")))
    recorded_note("C3", f, "longitudinal_mode_certified_by_xtrack_2pi_qs", fmt(2pi * abs(xc3("tw6_qs"))))
    lam1 = complex(xc3("tw6_cos_mux"), xc3("tw6_sin_mux")); lam2 = complex(xc3("tw6_cos_muy"), xc3("tw6_sin_muy"))
    lam3 = complex(cos(2pi * xc3("tw6_qs")), sin(2pi * xc3("tw6_qs")))
    k1 = match_mode(an.tunes, lam1); k2 = match_mode(an.tunes, lam2); k3 = match_mode(an.tunes, lam3)
    gate = wit && an.status !== :failed && k1 > 0 && k2 > 0 && k3 > 0 && length(unique((k1, k2, k3))) == 3
    if !wit
        println("TW-XSUITE-FALLBACK T6 longitudinal_witness_failed layer_C3_RECORDED_per_D5")
        recorded_note("C3", f, "fallback", "longitudinal witness failed: the C3 rows below are RECORDED, none gated")
    end
    an.status === :passed || recorded_note("C3", f, "octopus_status_$(an.status)", join(vcat(an.degradations, an.failures), " | "))
    row(q, oct, ext) = gate ? compare_row("C3", f, q, oct, ext, TOL_D_REL, "TOL-D") : (recorded_row("C3", f, q, oct, ext); true)
    ok &= assert_row("T6_analyze_status_not_failed", an.status !== :failed; fixture=f, layer="C3")
    ok &= assert_row("T6_three_modes_matched_distinct", k1 > 0 && k2 > 0 && k3 > 0 && length(unique((k1, k2, k3))) == 3; fixture=f, layer="C3")
    ok &= assert_row("T6_coasting_structure_absent", !an.coasting; fixture=f, layer="C3")
    for (k, lam, name) in ((k1, lam1, "x"), (k2, lam2, "y"), (k3, lam3, "s"))
        k == 0 && continue
        recorded_row("C3", f, "cos_mu$(name)_vs_tw6", cos(an.tunes[k]), real(lam))
        recorded_row("C3", f, "sin_mu$(name)_vs_tw6", sin(an.tunes[k]), imag(lam))
    end
    k3 == 0 || recorded_row("C3", f, "qs_vs_tw6_qs", an.tunes[k3] / 2pi, xc3("tw6_qs"))
    if an.beta !== nothing && an.alpha !== nothing && k1 > 0 && k2 > 0
        ok &= row("MR_betx_vs_tw6_betx", an.beta[k1, 1], xc3("tw6_betx"))
        ok &= row("MR_bety_vs_tw6_bety", an.beta[k2, 2], xc3("tw6_bety"))
        ok &= row("MR_alfx_vs_tw6_alfx", an.alpha[k1, 1], xc3("tw6_alfx"))
        ok &= row("MR_alfy_vs_tw6_alfy", an.alpha[k2, 2], xc3("tw6_alfy"))
        recorded_row("C3", f, "MR_bety1_vs_tw6_bety1", an.beta[k1, 2], xc3("tw6_bety1"))
        recorded_row("C3", f, "MR_betx2_vs_tw6_betx2", an.beta[k2, 1], xc3("tw6_betx2"))
    else
        ok &= row("MR_betx_vs_tw6_betx", NaN, xc3("tw6_betx"))
    end
    an.twiss === nothing || k1 > length(an.twiss) || recorded_row("C3", f, "ET4D_betx_vs_tw6_betx_edw_teng(different_object)", an.twiss[k1].beta, xc3("tw6_betx_edw_teng"))
    h = an.h === nothing ? NaN : an.h
    recorded_row("C3", f, "physical_h", h, 1.0)
    for (r, name) in enumerate(DISP_NAMES)
        ok &= row("physical_eta_vs_h*tw6_$(name)", an.eta === nothing ? NaN : an.eta[r], h * xc3("tw6_$(name)"))
        recorded_row("C3", f, "tw6_$(name)_vs_graph[:,2]", an.graph === nothing ? NaN : an.graph[r, 2], xc3("tw6_$(name)"))
        recorded_row("C3", f, "tw6_$(name)_zeta_vs_physical_zeta", an.zeta === nothing ? NaN : an.zeta[r], xc3("tw6_$(name)_zeta"))
    end
    recorded_row("C3", f, "unrepaired_gap_|tw6_dx-eta_x|_without_h", xc3("tw6_dx"), an.eta === nothing ? NaN : an.eta[1])
    recorded_row("C3", f, "tw6_dx_vs_C1_T6_task_dx(same_matrix_two_routes)", xc3("tw6_dx"), xcell("C1", f, "task", "dx"))
    recorded_row("C3", f, "tw6_slip_factor", xc3("tw6_slip_factor"), 0.0)
    recorded_row("C3", f, "tw6_momentum_compaction_factor", xc3("tw6_momentum_compaction_factor"), 0.0)
    return ok
end

# ---------------------------------------------------------------- digest, table, gate
function write_rows(path)
    mkpath(dirname(path))
    tmp = path * ".partial-$(getpid())"
    open(tmp, "w") do io
        println(io, "# TW-XSUITE rows of validation/twiss_xsuite_benchmark.jl; defect=", DEFECT, "; table ", basename(XSUITE_TABLE))
        println(io, join(("layer", "fixture", "quantity", "octopus", "external", "diff", "bound", "class", "status"), "\t"))
        for r in ROWS
            println(io, join((r.layer, r.fixture, r.quantity, fmt(r.octopus), fmt(r.external), fmt(r.diff), fmt(r.bound), r.class, r.status), "\t"))
        end
    end
    mv(tmp, path; force=true)
end

function main()
    println("TW-XSUITE start defect=", DEFECT, " table=", basename(XSUITE_TABLE), " julia=", VERSION, " threads=", Threads.nthreads())
    ok = witness_rows()
    if ok
        ok &= matrix_layer()
        ok &= lattice_layer()
        ok &= longitudinal_layer()
    else
        println("TW-XSUITE witnesses failed: no optics comparison runs (rule W)")
    end
    gated = [r for r in ROWS if r.status in ("PASS", "FAIL") && isfinite(r.bound) && r.bound > 0 && isfinite(r.diff)]
    ratios = [r.diff / r.bound for r in gated]
    worst = isempty(ratios) ? NaN : maximum(ratios)
    if !isempty(ratios)
        w = gated[argmax(ratios)]
        println("TW-XSUITE-WORST ", w.layer, " ", w.fixture, " ", w.quantity, " diff=", fmt(w.diff), " bound=", fmt(w.bound), " ", w.class)
    end
    nfail = count(r -> r.status == "FAIL", ROWS)
    nrec = count(r -> r.status == "RECORDED", ROWS)
    println("TW-XSUITE-DIGEST ", length(ROWS), " ", nfail, " ", fmt(worst))
    println("TW-XSUITE-NOTE digest gated=", count(r -> r.status in ("PASS", "FAIL"), ROWS),
            " recorded=", nrec, " defect=", DEFECT, " ", (ok && nfail == 0) ? "PASS" : "FAIL")
    write_rows(OUT_TSV)
    println("TW-XSUITE table ", OUT_TSV)
    (ok && nfail == 0) || error("TW-XSUITE: $(nfail) FAIL row(s) (defect=$(DEFECT)); see the TW-XSUITE lines above")
    return nothing
end

main()
