"""
Twiss benchmark against PTC ptc_twiss (MAD-X 5.03.06): the Octopus
TwissDispersionAnalysis on the benchmark cells of validation/twiss_benchmark_cells.jl
against the committed PTC table validation/reference/ptc_twiss_madx_5.03.06.tsv
(stage 8, benchmark B; theory 12.2 item 3, PTC half). The suite never runs
MAD-X: the table is the reference, its generator is
validation/generate_ptc_twiss_reference.jl.

Reference model
---------------
PTC ptc_twiss at ptc_create_layout, model=1, method=6, nst=10, exact=true,
time=false on the same element numbers, read AS PRINTED. Coordinates
(X,PX,Y,PY,T,PT) with coordinate 6 = delta = dp/p0 and row 5 in the ptc_track
T orientation; the reader applies F = diag(1,1,1,1,-1,1), J0 = I and no
shear (the stage 8 conversion law, history section: M_oct = F RE F, the partner of the Octopus BARE
compile). Layers: B0 convention witnesses (S0 drift RE56 = 0, S0_pt RE12 =
L/(1+delta), the lone cavity W1 flipped RE65 = strength k/PTC_BETA0^2 with
k = 2 pi f/c (PTC's effective beam, stage 8 decision D19; the header-beta0 formula is
recorded), the Octopus W1 twin's M65 against the same formula, the
symplectic residual of F RE F, which is 0-vs-0 on the committed drift and
cavity rows); B1 the 5D convention layer (icase=5: U1, U2, K2) on the 4x4
block plus column 6 with row 5 completed symplectically (RE55 prints 0 at
icase=5), M56 after F against the Octopus bare M56 (the gated magnitude and
sign of F, TOL-C), DISP1..4 against physical.eta
with NO momentum factor, BETA_jj/ALFA_jj against physical.beta/alpha,
cos mu_j against the Octopus tunes matched by plane content; B2 the 6D layer
(icase=6 rows, when the table carries them) against the bare compile with
longitudinal_mode = 2 pi QS from PTC, DISP1..4 RECORDED against
physical.graph[:, 2] as a fixed-z quantity; B3 the BETA_jk index order
decided in-run on the coupled cell with both transposes printed; B4L the
Octopus nst ladder against F RE F.

Error metric
------------
Per row |octopus - external|, judged FLOORED-RELATIVE (|diff| <= tol *
max(1, |ext|): relative above |ext| = 1, absolute at tol below it, so the
exact-zero DISP2/DISP4 entries do not divide) for beta, alpha, dispersion
and matrix entries, absolute for cos mu; the
model layer reports the max-entry residual per nst and the fitted
convergence order of log(residual) against log(nst).

Tolerance
---------
TOL-C (PTC): 1e-9 relative on DISP1..4, BETA_jk, ALFA_jk; 1e-10 absolute on
cos mu; 1e-12 on the symplectic residual of F RE F. Witnesses 1e-12
(drift rows), 1e-10 (W1 cavity). TOL-E (model layer): fitted order
4.0 +- 0.3 over nst in {4, 8, 16, 32, 64} at integrator_order 4, the nst=32
residual RECORDED (the design's 1e-9 there is not reached: stage 8 decision D6 wins), plus
the frozen nst=64 cap LADDER_CAP_64 = 8.4916074172269873e-09 (frozen at ten
times the worst 5D nst=64 residual of the first passing run and deliberately
NOT re-frozen when the 6D rows landed; it now stands 1.68x above the measured
worst, G6 5.0524842989951857e-09; provenance beside the constant).

Configuration
-------------
TwissDispersionAnalysis(strict=false, scaling=:none); on 6D rows
longitudinal_mode is the PTC synchrotron tune 2 pi |QS|. The presented
Edwards-Teng form is asserted to be 1 on coupled cells; every Determined
field is branched on is_determined and its reason recorded. Beam pin:
|beta0_header - 0.9498330546994187| <= 1e-12 on every row (stage 8 decision D13).
PTC's effective beam (stage 8 decision D19, history section of benchmark B): PTC evaluates the cavity kick at its
internal proton mass PTC_INTERNAL_PROTON_MASS_GEV = 0.938272081358 GeV
whatever the deck says, so the Octopus twins of the cavity rows (W1, B4,
B4K, G6_*) are compiled with cavity_beta0 = PTC_BETA0, cavity_gamma0 =
PTC_GAMMA0 (derived in the shared module from E_total = 3.0 GeV; beta0_ptc =
0.94983305558539111, the D19 pin 0.94983305558539122 with residual
1.1102230246251565e-16; 8.86e-10 above the header beta0). The W1 formula at the
HEADER beta0 is RECORDED with its 3.467e-10 miss, not gated. On every 6D row
the twin's M65 is GATED against the converted PTC RE65 at 1e-10 absolute (a
twin at the deck beam would miss by 3.47e-10), so D19's twin rule is a checked
fact. ALFA33: PTC prints it in its own (T, PT) orientation of coordinate 5,
under which alfa_33 is odd and every beta and transverse alfa is even, so the
Octopus alpha of mode 3 is compared with the sign flipped (row
ALFA33_PTC_T_convention_sign); the Ripken alpha is invariant under eigenvector
conjugation, so the mode's orientation never enters the sign.

Fixtures
--------
S0 (10 m drift), S0_pt, W1 (lone 400 MHz cavity, 60 MV), U1 (detuned FODO),
U2 (DBA cell), K2 (DBA with the qf tilted 0.05), and any 6D row (B4, B4K,
G6) the table carries; builders and beam constants from
validation/twiss_benchmark_cells.jl (nst 64, integrator order 4 unless the
ladder says otherwise).

Inputs / Outputs (under result/)
----------------------------------
Input: validation/reference/ptc_twiss_madx_5.03.06.tsv (91 columns, %.17g).
Output: result/twiss_ptc_benchmark.tsv, one row per gated, witness,
recorded and model TW-PTC line (tag, fixture, quantity, octopus, external,
diff, tol, class, verdict); TW-PTC-NOTE and TW-PTC-DIGEST are printed only.
Printed: TW-PTC-WITNESS, TW-PTC, TW-PTC-RECORDED, TW-PTC-MODEL,
TW-PTC-ORDER <fixture> <order> <centre>+-<tol>, TW-PTC-NOTE (free text),
TW-PTC-DIGEST <rows> <fails> <worst ratio>; then error() on any FAIL.

Run
---
    julia --project=. validation/twiss_ptc_benchmark.jl

Environment
-----------
    CUDA_VISIBLE_DEVICES=""            (script mode, CPU only)
    OPENBLAS_CORETYPE=Haswell julia -C haswell   (the AVX2 gate arm)

Overrides
---------
    OCTOPUS_STAGE8_DEFECT     none (default) | drop_F (the flip F is not applied to
                              the PTC map) | cavity_57MV (every Octopus cavity twin
                              runs with its strength scaled by 57/60: the W1 twin at
                              57 MV instead of 60 MV, B4/B4K likewise, G6 at 1.9 and
                              0.19 MV); each turns a named TW-PTC line red and is
                              documented in the history
    OCTOPUS_STAGE8_PTC_TABLE  path of the PTC table to read instead of the
                              committed one (development only; the suite reads
                              the committed table)
"""

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using LinearAlgebra
using Printf

include(joinpath(@__DIR__, "twiss_benchmark_cells.jl"))

# ---------------------------------------------------------------- constants
const PTC_TAG = "TW-PTC"
const PTC_TABLE_DEFAULT = normpath(joinpath(@__DIR__, "reference", "ptc_twiss_madx_5.03.06.tsv"))
const PTC_TABLE = get(ENV, "OCTOPUS_STAGE8_PTC_TABLE", PTC_TABLE_DEFAULT)
const PTC_OUT_TSV = normpath(joinpath(@__DIR__, "..", "result", "twiss_ptc_benchmark.tsv"))
const PTC_DEFECT = Symbol(get(ENV, "OCTOPUS_STAGE8_DEFECT", "none"))
const PTC_DEFECTS = (:none, :drop_F, :cavity_57MV)
PTC_DEFECT in PTC_DEFECTS || error("OCTOPUS_STAGE8_DEFECT must be one of $(PTC_DEFECTS), got $(PTC_DEFECT)")

const TOL_C_REL = 1e-9        # DISP, BETA, ALFA (relative, floored at |ext| = 1)
const TOL_C_COS = 1e-10       # cos mu (absolute)
const TOL_C_SYMP = 1e-12      # symplectic residual of F RE F
const TOL_WITNESS = 1e-12     # S0 rows
const TOL_W1 = 1e-10          # the lone cavity row (the stage 8 W1 witness)
const LADDER_NSTS = (4, 8, 16, 32, 64)
const LADDER_ORDER = 4.0
const LADDER_ORDER_TOL = 0.3
# Stage 8 decision D6 (which overrides the design's TOL-E): the gate is the fitted order plus an nst=64 cap of
# ten times the maximum measured on the first passing run; the design's nst=32 < 1e-9 gate is
# RECORDED only (measured nst=32 residuals 3.4e-9 U1, 1.2e-8 U2/K2 at order 3.96-3.98).
# Provenance of the cap: native arm 2026-09-15, first passing run (5D rows only), worst nst=64
# residual 8.4916074172269873e-10 on U2 (U1 2.4152943534083704e-10, K2 8.4513440690159314e-10), x10.
# When the 6D rows landed (stage 8 decision D19, same day) their nst=64 residuals were B4 8.5503359947836088e-10,
# B4K 8.505682824733185e-10, G6_2.0MV and G6_0.2MV 5.0524842989951857e-09; the cap was deliberately
# NOT re-frozen, so it stands at 1.68x the measured worst (ratio 0.59499739575161859, the digest's worst).
const LADDER_CAP_64 = 8.4916074172269873e-09
const CAVITY_MV_NOMINAL = 60.0   # W1 twin: strength 0.02 * E_total 3000 MeV

fmt(x::Real) = @sprintf("%.17g", Float64(x))
fmt(x::AbstractString) = String(x)

# ---------------------------------------------------------------- table
"Read the committed table; return (header, colnames, rows::Vector{Dict{String,String}})."
function read_table(path::AbstractString)
    t = read_reference_table(path)
    n = length(t.columns[t.colnames[1]])
    rows = [Dict{String,String}(c => t.columns[c][i] for c in t.colnames) for i in 1:n]
    return (header=t.header, colnames=t.colnames, rows=rows)
end

"The tool version named in the header's # tool: line (the whole line, for the record)."
function table_version(header::Vector{String})
    i = findfirst(l -> startswith(l, "# tool:"), header)
    return i === nothing ? "(no tool line)" : header[i]
end

rowf(row::Dict{String,String}, col::AbstractString) =
    haskey(row, col) ? parse(Float64, row[col]) : error("column $(col) missing from the table")
rowid(row) = row["id"]
rowlayer(row) = row["layer"]

"The 6x6 RE matrix of a row AS PRINTED (RE_jk_end)."
function re_matrix(row::Dict{String,String})
    M = zeros(6, 6)
    for j in 1:6, k in 1:6
        M[j, k] = rowf(row, "RE$(j)$(k)_end")
    end
    return M
end

"Rows of the table whose layer is one of layers, in table order."
rows_of(tab, layers...) = [r for r in tab.rows if rowlayer(r) in layers]
row_by_id(tab, id) = (i = findfirst(r -> rowid(r) == id, tab.rows); i === nothing ? nothing : tab.rows[i])

# ---------------------------------------------------------------- conversion
"""
The section 3 law for PTC time=false through the shared convert_map (F RE F,
J0 = I, no shear). The drop_F defect returns RE untouched, so row 5 keeps
PTC's T orientation and the dispersive rows go red by name.
"""
function ptc_to_octopus(RE::AbstractMatrix; beta0, gamma0, C)
    PTC_DEFECT === :drop_F && return Matrix{Float64}(RE)
    return convert_map(:ptc, RE; beta0, gamma0, C)
end

"""
Coasting completion of an icase=5 map: the 4x4 block A and column 6 (d) are
trusted, row 6 is e6, and row 5 follows from M' S M = S:
r = -A' S4 d, RE55 = 1. m56 is the (5,6) entry kept from the printed map.
"""
function coasting_completion(RE::AbstractMatrix; m56::Real=RE[5, 6])
    A = Matrix{Float64}(RE[1:4, 1:4]); d = Vector{Float64}(RE[1:4, 6])
    S4 = symplectic_form(4)
    M = zeros(6, 6)
    M[1:4, 1:4] = A; M[1:4, 6] = d
    M[5, 1:4] = -(A' * (S4 * d)); M[5, 5] = 1.0; M[5, 6] = Float64(m56)
    M[6, 6] = 1.0
    return M
end

# ---------------------------------------------------------------- rows, printing
# One record per printed line; kind in (:gated, :witness, :recorded, :model, :order).
struct BenchRow
    kind::Symbol
    tag::String
    fixture::String
    quantity::String
    octopus::Float64
    external::Float64
    diff::Float64
    tol::Float64
    class::String
    verdict::String     # PASS | FAIL | recorded
end
const ROWS = BenchRow[]

"Print one line in the stage 8 printed-line grammar and remember it."
function print_tw(r::BenchRow)
    if r.kind === :gated
        println(r.tag, " ", r.fixture, " ", r.quantity, " ", fmt(r.octopus), " ", fmt(r.external), " ",
                fmt(r.diff), " ", fmt(r.tol), " ", r.class, " ", r.verdict)
    elseif r.kind === :witness
        println(r.tag, " ", r.quantity, " ", fmt(r.octopus), " ", fmt(r.external), " ", fmt(r.diff), " ", r.verdict)
    elseif r.kind === :recorded
        println(r.tag, " ", r.fixture, " ", r.quantity, " ", fmt(r.octopus), " ", fmt(r.external), " ", fmt(r.diff))
    elseif r.kind === :model
        println(r.tag, " ", r.fixture, " ", r.quantity, " ", fmt(r.diff))
    else # :order
        println(r.tag, " ", r.fixture, " ", fmt(r.octopus), " ", fmt(r.external), "+-", fmt(r.tol), " ", r.verdict)
    end
    push!(ROWS, r)
    return r
end

"Ratio |diff| / tol_effective, the digest's worst-ratio operand (0 for ungated rows)."
row_ratio(r::BenchRow) = r.kind in (:gated, :witness) && r.tol > 0 ? r.diff / r.tol : 0.0

"""
A gated comparison. metric = :rel judges |diff| <= tol * max(1, |ext|)
(relative, floored to absolute below |ext| = 1 so exact zeros do not divide);
metric = :abs judges |diff| <= tol. The stored tol is the effective one.
"""
function compare_row(fixture, quantity, oct::Real, ext::Real, tol::Real, class::AbstractString; metric::Symbol=:rel)
    diff = abs(Float64(oct) - Float64(ext))
    tol_eff = metric === :rel ? tol * max(1.0, abs(Float64(ext))) : Float64(tol)
    verdict = diff <= tol_eff ? "PASS" : "FAIL"
    return print_tw(BenchRow(:gated, PTC_TAG, String(fixture), String(quantity), oct, ext, diff, tol_eff, String(class), verdict))
end

"A witness line: TW-PTC-WITNESS <name> <value> <expected> <|diff|> PASS|FAIL (absolute tol)."
function witness_row(name, value::Real, expected::Real, tol::Real)
    diff = abs(Float64(value) - Float64(expected))
    verdict = diff <= tol ? "PASS" : "FAIL"
    return print_tw(BenchRow(:witness, PTC_TAG * "-WITNESS", "", String(name), value, expected, diff, tol, "witness", verdict))
end

"A recorded (not gated) line: TW-PTC-RECORDED <fixture> <quantity> <octopus> <external> <|diff|>."
function recorded_row(fixture, quantity, oct::Real, ext::Real)
    diff = abs(Float64(oct) - Float64(ext))
    return print_tw(BenchRow(:recorded, PTC_TAG * "-RECORDED", String(fixture), String(quantity), oct, ext, diff, 0.0, "recorded", "recorded"))
end

"A note line (not a row): free text prefixed by the tag, for reasons and decisions."
note(msg...) = println(PTC_TAG, "-NOTE ", msg...)

"Beam pin per row (stage 8 decision D13): |beta0_header - pin| <= 1e-12, gamma0 consistent with it."
function beam_pin_row(row)
    b = rowf(row, "beta0_header"); g = rowf(row, "gamma0_header")
    witness_row("$(rowid(row))_beta0_header_vs_pin", b, BENCH_BETA0_PIN, BENCH_BETA0_ATOL)
    abs(g - 1 / sqrt(1 - b^2)) <= 1e-12 * g || note(rowid(row), " gamma0_header ", fmt(g), " inconsistent with beta0_header")
    return (beta0=b, gamma0=g, C=rowf(row, "C"))
end

# ---------------------------------------------------------------- B0 witnesses
# PTC's effective beam (stage 8 decision D19): PTC_INTERNAL_PROTON_MASS_GEV, PTC_BETA0, PTC_GAMMA0 come from the shared
# module (derived from E_total; the module asserts the derivation). The row's gamma0_header must describe the
# same E_total, otherwise PTC_BETA0 is not the beam the row ran at.
function check_row_energy(gamma0::Real)
    E = BENCH_E_TOTAL_EV / 1e9
    abs(gamma0 * BENCH_MASS_EV / 1e9 - E) <= 1e-12 * E || note("gamma0_header ", fmt(gamma0), " does not describe E_total = ", fmt(E), " GeV")
    return nothing
end

"The W1 twin: the lone 400 MHz cavity at PTC's effective beam (D19) followed by the table's 0.2 m drift; strength scaled by the cavity_57MV defect."
function w1_twin(volt_MV::Real, C::Real)
    strength = RF_STRENGTH * (PTC_DEFECT === :cavity_57MV ? 57.0 : volt_MV) / CAVITY_MV_NOMINAL
    return compile_cell((_rf(strength; cavity_beta0=PTC_BETA0, cavity_gamma0=PTC_GAMMA0), _drift(C)))
end

"""
B0: the convention witnesses, run before any optics row. Every expected value
is a FORMULA in the row's own header beta0/gamma0 and C (the stage 8 witness rule W).
Returns true when every gated witness passed.
"""
function witness_rows(tab)
    ok = true
    # S0: the bare 10 m drift; RE56 = 0 exactly with time=false; the converted map equals the Octopus bare drift.
    s0 = row_by_id(tab, "S0"); s0 === nothing && error("witness row S0 missing from the table")
    b = beam_pin_row(s0); RE = re_matrix(s0)
    ok &= witness_row("S0_RE56_zero", RE[5, 6], 0.0, TOL_WITNESS).verdict == "PASS"
    ok &= witness_row("S0_RE12_is_L", RE[1, 2], b.C, TOL_WITNESS * b.C).verdict == "PASS"
    M = ptc_to_octopus(RE; b.beta0, b.gamma0, b.C)
    ok &= witness_row("S0_converted_vs_octopus_bare_max_entry", maximum(abs, M - bare_map(S0())), 0.0, TOL_WITNESS).verdict == "PASS"
    ok &= witness_row("S0_converted_vs_analytic_drift_max_entry", maximum(abs, M - FLIP * analytic_drift_ext(:ptc, b.C) * FLIP), 0.0, TOL_WITNESS).verdict == "PASS"
    # S0_pt: the same drift at pt = PT_start (1e-3): RE12 = L/(1+delta) says coordinate 6 is delta = dp/p0.
    s0p = row_by_id(tab, "S0_pt"); s0p === nothing && error("witness row S0_pt missing from the table")
    bp = beam_pin_row(s0p); REp = re_matrix(s0p); pt = rowf(s0p, "PT_start")
    exp12 = bp.C / (1 + pt)
    ok &= witness_row("S0_pt_RE12_is_L_over_1+delta", REp[1, 2], exp12, TOL_WITNESS * exp12).verdict == "PASS"
    ok &= witness_row("S0_pt_RE34_is_L_over_1+delta", REp[3, 4], exp12, TOL_WITNESS * exp12).verdict == "PASS"
    # W1: the lone cavity. Flipped RE65 = (F RE F)[6,5] = strength k/beta0^2, k = 2 pi f/c, with V = strength * E_total (stage 8 W1 witness: PTC M65 = (qV/p0c) k/beta0 equated to Octopus strength k/beta0^2).
    w1 = row_by_id(tab, "W1"); w1 === nothing && error("witness row W1 missing from the table")
    bw = beam_pin_row(w1); REw = re_matrix(w1)
    f_Hz = rowf(w1, "freq_MHz") * 1e6; volt_MV = rowf(w1, "volt_MV")
    k = 2pi * f_Hz / CLIGHT
    strength = volt_MV * 1e6 / BENCH_E_TOTAL_EV   # stage 8 W1 witness: V = strength * E_total, lambda-free
    Mw = ptc_to_octopus(REw; bw.beta0, bw.gamma0, bw.C)
    check_row_energy(bw.gamma0)
    note("W1 twin and every cavity twin compiled at PTC's effective beam (D19): mass ", fmt(PTC_INTERNAL_PROTON_MASS_GEV),
         " GeV, cavity_beta0 = PTC_BETA0 = ", fmt(PTC_BETA0), ", cavity_gamma0 = PTC_GAMMA0 = ", fmt(PTC_GAMMA0),
         "; header beta0 ", fmt(bw.beta0), " (header - ptc = ", fmt(bw.beta0 - PTC_BETA0), "); derivation residual ", fmt(PTC_BETA0_RESIDUAL))
    # Dossier D19 (2), gated at TOL_W1: the flipped RE65 against the formula at PTC's effective beta0, against the
    # Octopus bare twin compiled at that beam, and the twin against the formula (the row the cavity_57MV defect turns red).
    m65_formula_ptc = strength * k / PTC_BETA0^2
    ok &= witness_row("W1_M65_flipped_vs_strength_k_over_PTC_BETA0^2", Mw[6, 5], m65_formula_ptc, TOL_W1).verdict == "PASS"
    twin = w1_twin(volt_MV, bw.C); Mtwin = bare_map(twin)
    ok &= witness_row("W1_M65_flipped_vs_octopus_bare_twin_M65_at_PTC_beam", Mw[6, 5], Mtwin[6, 5], TOL_W1).verdict == "PASS"
    ok &= witness_row("W1_octopus_twin_M65_vs_formula_at_PTC_BETA0", Mtwin[6, 5], m65_formula_ptc, TOL_W1).verdict == "PASS"
    recorded_row("W1", "converted_vs_octopus_twin_max_entry", maximum(abs, Mw - Mtwin), 0.0)
    # Recorded, not gated: the same formula at the HEADER beta0 (the D13 pin) misses by 3.467e-10: the PTC internal-mass
    # effect (beta0 enters squared; header beta0 is 9.33e-10 relative below PTC's).
    recorded_row("W1", "M65_flipped_vs_formula_at_header_beta0_PTC_internal_mass_effect", Mw[6, 5], strength * k / bw.beta0^2)
    # Symplectic residual as printed and after F, for every 6x6 row of the table (icase=6 rows). On the committed
    # drift and cavity rows (S0, S0_pt, W1) both residuals are 0, so these rows are 0-vs-0 there; the discriminating
    # pair (as printed >> after F) exists only on ring rows. The magnitude of F is gated on the 5D rows instead
    # (M56_after_F_vs_octopus_bare_M56 in layer_5d).
    for r in tab.rows
        rowf(r, "icase") == 6 || continue
        REr = re_matrix(r); br = (beta0=rowf(r, "beta0_header"), gamma0=rowf(r, "gamma0_header"), C=rowf(r, "C"))
        recorded_row(rowid(r), "symplectic_residual_as_printed", symplectic_residual(REr), 0.0)
        ok &= witness_row("$(rowid(r))_symplectic_residual_after_F", symplectic_residual(ptc_to_octopus(REr; br...)), 0.0, TOL_C_SYMP).verdict == "PASS"
    end
    # Rule X (sign of row 5) on the dispersive U2 row: after F, M51 and M52 carry the Octopus signs (negative on the DBA, p4 S4).
    u2 = row_by_id(tab, "U2")
    if u2 !== nothing
        M2 = ptc_to_octopus(re_matrix(u2); beta0=rowf(u2, "beta0_header"), gamma0=rowf(u2, "gamma0_header"), C=rowf(u2, "C"))
        O2 = bare_map(U2())
        ok &= witness_row("U2_sign_M51_after_F_vs_octopus", sign(M2[5, 1]), sign(O2[5, 1]), 0.0).verdict == "PASS"
        ok &= witness_row("U2_sign_M52_after_F_vs_octopus", sign(M2[5, 2]), sign(O2[5, 2]), 0.0).verdict == "PASS"
    end
    return ok
end

# ---------------------------------------------------------------- analysis (rules S, Y, D)
"Unwrap a Determined or record its reason and return nothing (stage 8 working rule W5: branch on is_determined, never unwrap blindly)."
function unwrap_or_note(d, label, field)
    is_determined(d) && return determined_value(d)
    note(label, " ", field, " undetermined: status ", d.status, " reason ", d.reason, " detail ", repr(d.detail))
    return nothing
end

"""
Run analyze with strict=false and scaling=:none on a converted 6x6 map and
read the PHYSICAL objects (never a route field). mu_s (radians per turn,
in (0, pi)) is passed as longitudinal_mode on bunched maps so the
longitudinal selection is certified. Returns a NamedTuple; every undetermined
field is nothing with its reason printed.
"""
function analyze_converted(M::AbstractMatrix, label::AbstractString; mu_s=nothing)
    # 6D rows only: nonsymplectic=:flag, because PTC's printed precision on the 6-cell ring (3.75e-14 after F) exceeds
    # the analysis's default row-ratio rule (measured row ratio 2.83 on G6_2.0MV, which would throw); the defect is
    # printed instead. The 5D rows keep the default guard armed (measured row ratios 0.051, 0.100, 0.056 on U1, U2, K2).
    an = mu_s === nothing ? TwissDispersionAnalysis(strict=false, scaling=:none) :
                            TwissDispersionAnalysis(strict=false, scaling=:none, nonsymplectic=:flag, longitudinal_mode=Float64(mu_s))
    res = try
        analyze(an, Matrix{Float64}(M))
    catch e
        msg = sprint(showerror, e)
        note(label, " analyze THREW: ", msg)
        compare_row(label, "analyze_threw", 1.0, 0.0, 0.0, "TOL-C"; metric=:abs)
        return (result=nothing, beta=nothing, alpha=nothing, eta=nothing, graph=nothing, h=nothing, tunes=Float64[], form=nothing, R1=nothing)
    end
    sd = res.symplectic_defect
    note(label, " status ", res.status, " degradations ", repr(res.degradations), " failures ", repr(res.failures),
         "; symplectic defect frobenius ", fmt(sd.frobenius), " row_ratio ", fmt(sd.row_ratio))
    ph = res.physical
    beta = unwrap_or_note(ph.beta, label, "physical.beta")
    alpha = unwrap_or_note(ph.alpha, label, "physical.alpha")
    eta = unwrap_or_note(ph.eta, label, "physical.eta")
    graph = unwrap_or_note(ph.graph, label, "physical.graph")
    h = unwrap_or_note(ph.h, label, "physical.h")
    tunes = copy(ph.tunes)
    # Rule S: print the route field beside the physical one once per fixture so the reciprocal-scaling trap stays visible.
    if res.coasting !== nothing && res.coasting.holds
        ce = res.coasting.eta
        note(label, " coasting structure holds; coasting.eta (route field, never compared) ",
             is_determined(ce) ? join(fmt.(determined_value(ce)), ",") : string(ce.status), "; physical.eta ",
             eta === nothing ? "undetermined" : join(fmt.(eta), ","))
    end
    # Rule Y: the presented Edwards-Teng form and form 1's R through the double unwrap.
    form = nothing; R1 = nothing
    tr = unwrap_or_note(res.transverse, label, "transverse")
    if tr !== nothing
        form = unwrap_or_note(tr.preferred_form, label, "transverse.preferred_form")
        pair = unwrap_or_note(tr.edwards_teng_normalizer, label, "transverse.edwards_teng_normalizer")
        pair === nothing || (R1 = unwrap_or_note(pair.form1.R, label, "form1.R"))
        note(label, " presented Edwards-Teng form ", form === nothing ? "undetermined" : string(form),
             "; form1.R (scaled coordinates, scaling=:none) ", R1 === nothing ? "undetermined" : join(fmt.(vec(R1)), ","))
    end
    return (result=res, beta=beta, alpha=alpha, eta=eta, graph=graph, h=h, tunes=tunes, form=form, R1=R1)
end

"""
Mode matching by EIGENVALUE (rule T): the permutation perm with
perm[k] = the Octopus mode whose cos(tune) is closest to cos(2 pi MU_k) of
PTC mode k, chosen among all permutations by the smallest total mismatch;
margin is the mismatch of the runner-up permutation. Labels are never
matched by position; the plane content of every mode is printed beside it.
"""
function match_modes(tunes::AbstractVector, mus_turns::AbstractVector)
    n = length(mus_turns)
    perms = n == 2 ? ([1, 2], [2, 1]) :
            n == 3 ? ([1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]) :
            error("match_modes: $(n) modes")
    mism(p) = sum(abs(cos(tunes[p[k]]) - cos(2pi * mus_turns[k])) for k in 1:n)
    scores = sort([(mism(p), p) for p in perms]; by=first)
    return (perm=scores[1][2], mismatch=scores[1][1], margin=scores[2][1])
end

"cos of the PTC tune MU (in turns) and of the Octopus tune (radians); the comparison is orientation-free."
cos_turns(mu_turns::Real) = cos(2pi * mu_turns)

# ---------------------------------------------------------------- B1 5D layer (icase=5 rows) and B3 index order
"""
The Octopus twin of a table row (bare compile), by fixture id. The cavity
rows (B4, B4K, G6_*) are compiled with cavity_beta0 = PTC_BETA0,
cavity_gamma0 = PTC_GAMMA0, the beam PTC ran its cavity at (stage 8 decision D19);
the cavity-free rows have no beam dependence in the bare compile.
"""
function octopus_twin(id::AbstractString; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER)
    id == "U1" && return U1(; nst, integrator_order)
    id == "U2" && return U2(; nst, integrator_order)
    id == "K2" && return K2(; nst, integrator_order)
    # the cavity_57MV defect scales every cavity twin's strength by 57/60 (same scale as w1_twin)
    dscale = PTC_DEFECT === :cavity_57MV ? 57.0 / CAVITY_MV_NOMINAL : 1.0
    id == "B4" && return B4(; nst, integrator_order, rf_strength=RF_STRENGTH * dscale, cavity_beta0=PTC_BETA0, cavity_gamma0=PTC_GAMMA0)
    id == "B4K" && return B4K(; nst, integrator_order, rf_strength=RF_STRENGTH * dscale, cavity_beta0=PTC_BETA0, cavity_gamma0=PTC_GAMMA0)
    startswith(id, "G6_") && return G6(; nst, integrator_order, volt_eV=parse(Float64, replace(id[4:end], "MV" => "")) * 1e6 * dscale,
                                       cavity_beta0=PTC_BETA0, cavity_gamma0=PTC_GAMMA0)
    error("no Octopus twin for table row $(id)")
end
const COUPLED_IDS = ("K2", "B4K")
const EXPECTED_IDS = ("S0", "S0_pt", "W1", "U1", "U2", "K2", "B4", "B4K", "G6_2.0MV", "G6_0.2MV")
# Sign applied to Octopus alpha[mode, plane k] before comparing with PTC's ALFA_kk: alfa_33 is odd under
# F = diag(1,1,1,1,-1,1) (PTC's T orientation of coordinate 5), alfa_11/alfa_22 are even (review B2 physics, major 1).
const ALFA_SIGN_PTC_T = (1.0, 1.0, -1.0)

"The converted 6x6 of a 5D row: F RE F, then the coasting completion (RE55 prints 0 at icase=5)."
function converted_5d(row)
    b = (beta0=rowf(row, "beta0_header"), gamma0=rowf(row, "gamma0_header"), C=rowf(row, "C"))
    Mf = ptc_to_octopus(re_matrix(row); b...)
    return (M=coasting_completion(Mf), M_flipped=Mf, b=b)
end

"""
B3: the BETA_jk index order, decided on a coupled row. bm[j, k] is the
Octopus physical.beta[mode, plane]; jx, jy the modes of planes x, y.
Both readings are printed; the one within TOL-C is adopted when the other
misses by more than 1e-3; otherwise the row is a recorded finding.
"""
function index_order_rows(id, row, bm, jx, jy)   # jx, jy = the Octopus modes matched to PTC modes 1, 2 (j1, j2)
    b12 = rowf(row, "BETA12_start"); b21 = rowf(row, "BETA21_start")
    # reading (mode, plane): BETA12 = beta[mode x, plane y], BETA21 = beta[mode y, plane x]
    miss_mp = max(abs(b12 - bm[jx, 2]) / max(1.0, abs(b12)), abs(b21 - bm[jy, 1]) / max(1.0, abs(b21)))
    # reading (plane, mode): BETA12 = beta[mode y, plane x], BETA21 = beta[mode x, plane y]
    miss_pm = max(abs(b12 - bm[jy, 1]) / max(1.0, abs(b12)), abs(b21 - bm[jx, 2]) / max(1.0, abs(b21)))
    recorded_row(id, "BETA12_as_(mode,plane)_vs_beta[j1,y]", bm[jx, 2], b12)
    recorded_row(id, "BETA12_as_(plane,mode)_vs_beta[j2,x]", bm[jy, 1], b12)
    recorded_row(id, "BETA21_as_(mode,plane)_vs_beta[j2,x]", bm[jy, 1], b21)
    recorded_row(id, "BETA21_as_(plane,mode)_vs_beta[j1,y]", bm[jx, 2], b21)
    if miss_mp <= TOL_C_REL && miss_pm > 1e-3
        note(id, " BETA_jk index order DECIDED: (j = mode, k = plane); the (plane, mode) reading misses by ", fmt(miss_pm))
        compare_row(id, "BETA12", bm[jx, 2], b12, TOL_C_REL, "TOL-C"); compare_row(id, "BETA21", bm[jy, 1], b21, TOL_C_REL, "TOL-C")
        return :mode_plane
    elseif miss_pm <= TOL_C_REL && miss_mp > 1e-3
        note(id, " BETA_jk index order DECIDED: (j = plane, k = mode); the (mode, plane) reading misses by ", fmt(miss_mp))
        compare_row(id, "BETA12", bm[jy, 1], b12, TOL_C_REL, "TOL-C"); compare_row(id, "BETA21", bm[jx, 2], b21, TOL_C_REL, "TOL-C")
        return :plane_mode
    end
    note(id, " BETA_jk index order NOT decided (recorded finding): misses (mode,plane) ", fmt(miss_mp), " (plane,mode) ", fmt(miss_pm))
    return :undecided
end

"B1: DISP1..4 -> physical.eta, BETA_jj/ALFA_jj -> physical.beta/alpha, cos mu_j, all at TOL-C; B3 on the coupled row."
function layer_5d(tab)
    for row in rows_of(tab, "5d")
        id = rowid(row); beam_pin_row(row)
        c = converted_5d(row)
        recorded_row(id, "completed_row5_vs_printed_after_F_max|RE51..54|", maximum(abs, c.M[5, 1:4] - c.M_flipped[5, 1:4]), 0.0)
        recorded_row(id, "RE55_as_printed", c.M_flipped[5, 5], 1.0)
        compare_row(id, "symplectic_residual_completed_map", symplectic_residual(c.M), 0.0, TOL_C_SYMP, "TOL-C"; metric=:abs)
        O = bare_map(octopus_twin(id))
        # Gated: the one quantitative longitudinal entry of a 5D row; it carries the magnitude AND the sign of F
        # (drop_F sends it from 1.6e-11 to 0.163 on U2) and the u = 0 partnership (the task compile would sit C/gamma0^2 away).
        compare_row(id, "M56_after_F_vs_octopus_bare_M56", O[5, 6], c.M[5, 6], TOL_C_REL, "TOL-C")
        recorded_row(id, "max_entry_4x4+col6_octopus_nst64_vs_converted", maximum(abs, [O[1:4, 1:4] O[1:4, 6]] - [c.M[1:4, 1:4] c.M[1:4, 6]]), 0.0)
        a = analyze_converted(c.M, id)
        if a.eta === nothing || a.beta === nothing || a.alpha === nothing
            note(id, " optics undetermined; the TOL-C rows are not produced (see the reasons above)")
            compare_row(id, "analysis_determined", 0.0, 1.0, 0.0, "TOL-C"; metric=:abs)
            continue
        end
        for k in 1:4
            compare_row(id, "DISP$(k)_vs_physical.eta[$(k)]", a.eta[k], rowf(row, "DISP$(k)_start"), TOL_C_REL, "TOL-C")
        end
        mm = match_modes(a.tunes, [rowf(row, "MU1_end"), rowf(row, "MU2_end")])
        jx, jy = mm.perm
        note(id, " modes matched by cos mu: PTC (1,2) -> Octopus ", repr(mm.perm), " mismatch ", fmt(mm.mismatch), " runner-up ", fmt(mm.margin),
             "; plane content beta[mode,plane] = ", join(fmt.(vec(a.beta')), ","))
        if mm.margin <= 1e-6
            compare_row(id, "mode_matching_margin", mm.margin, 1.0, 0.0, "TOL-C"; metric=:abs); continue
        end
        compare_row(id, "BETA11", a.beta[jx, 1], rowf(row, "BETA11_start"), TOL_C_REL, "TOL-C")
        compare_row(id, "BETA22", a.beta[jy, 2], rowf(row, "BETA22_start"), TOL_C_REL, "TOL-C")
        compare_row(id, "ALFA11", a.alpha[jx, 1], rowf(row, "ALFA11_start"), TOL_C_REL, "TOL-C")
        compare_row(id, "ALFA22", a.alpha[jy, 2], rowf(row, "ALFA22_start"), TOL_C_REL, "TOL-C")
        compare_row(id, "cos_mu1", cos(a.tunes[jx]), cos_turns(rowf(row, "MU1_end")), TOL_C_COS, "TOL-C"; metric=:abs)
        compare_row(id, "cos_mu2", cos(a.tunes[jy]), cos_turns(rowf(row, "MU2_end")), TOL_C_COS, "TOL-C"; metric=:abs)
        if id in COUPLED_IDS
            witness_row("$(id)_presented_edwards_teng_form_is_1", a.form === nothing ? NaN : a.form, 1, 0.0)
            index_order_rows(id, row, a.beta, jx, jy)
        end
    end
end

# ---------------------------------------------------------------- B2 6D layer (icase=6 rows with a cavity)
"""
B2: the 6D rows (B4, B4K, G6_*) against the Octopus BARE compile (PTC time=false
has u = 0: the section 3 partnership, asserted through the S0 witness above and
re-stated here from the row's own header). longitudinal_mode = 2 pi |QS| is
passed from PTC so the longitudinal selection is certified. Gated at TOL-C:
BETA_kk, ALFA_kk (k = 1..3), cos mu_k, the off-diagonal BETA_pk in the decided
(plane, mode) order; RECORDED: DISP1..4 against physical.graph[:, 2] = eta/h,
the synchrotron eigenvector's dx/ddelta at FIXED z -- never called dispersion.
"""
function layer_6d(tab)
    rows = rows_of(tab, "6d")
    if isempty(rows)
        note("6D layer (B2/B3 on B4, B4K, G6): the table carries no 6d row (the generator aborts them when the W1 witness misses); nothing gated here")
        return
    end
    for row in rows
        id = rowid(row); b = beam_pin_row(row)
        RE = re_matrix(row); M = ptc_to_octopus(RE; b...)
        note(id, " partnership: PTC time=false has u = 0 (the slip C/gamma0^2 = ", fmt(slip(b.C; gamma0=b.gamma0)), " is NOT applied) -> Octopus BARE compile")
        recorded_row(id, "symplectic_residual_as_printed", symplectic_residual(RE), 0.0)
        compare_row(id, "symplectic_residual_after_F", symplectic_residual(M), 0.0, TOL_C_SYMP, "TOL-C"; metric=:abs)
        O = bare_map(octopus_twin(id))
        recorded_row(id, "max_entry_octopus_nst64_vs_converted", maximum(abs, O - M), 0.0)
        # GATED (review B2 physics, minor 6): the twin's cavity beam is checked, not assumed; a twin compiled at the
        # deck beam would miss by 0.18584658844470611 * 1.866e-9 = 3.47e-10 > TOL_W1 (D19).
        compare_row(id, "M65_octopus_twin_at_PTC_beam_vs_converted", O[6, 5], M[6, 5], TOL_W1, "TOL-C"; metric=:abs)
        qs = rowf(row, "QS"); mu_s = 2pi * abs(qs)
        note(id, " PTC QS ", fmt(qs), " -> longitudinal_mode mu_s ", fmt(mu_s), "; sign(M65 converted) ", fmt(sign(M[6, 5])), " sign(M65 octopus) ", fmt(sign(O[6, 5])))
        a = analyze_converted(M, id; mu_s=mu_s)
        if a.beta === nothing || a.alpha === nothing || size(a.beta, 1) != 3
            note(id, " 6D optics undetermined or not 3x3; the TOL-C rows are not produced")
            compare_row(id, "analysis_determined_6d", 0.0, 1.0, 0.0, "TOL-C"; metric=:abs)
            continue
        end
        mus = [rowf(row, "MU1_end"), rowf(row, "MU2_end"), qs]
        mm = match_modes(a.tunes, mus)
        note(id, " modes matched by cos mu: PTC (1,2,s) -> Octopus ", repr(mm.perm), " mismatch ", fmt(mm.mismatch), " runner-up ", fmt(mm.margin),
             "; Octopus tunes (rad) ", join(fmt.(a.tunes), ","), "; plane content beta[mode,plane] rows ", join(fmt.(vec(a.beta')), ","))
        if mm.margin <= 1e-6
            compare_row(id, "mode_matching_margin", mm.margin, 1.0, 0.0, "TOL-C"; metric=:abs); continue
        end
        js = a.tunes[mm.perm[3]]
        note(id, " mode 3 orientation: Octopus tune ", fmt(js), " (", js > pi ? "negative, 2pi - mu_s" : "positive", "), sign(M65) ", fmt(sign(M[6, 5])), "; cos mu is orientation-free")
        for k in 1:3
            j = mm.perm[k]
            # ALFA sign (review B2 physics, major 1): the Ripken alpha is INVARIANT under conjugation of the
            # eigenvector (orientation, rule T), so the mode's quadrant never flips it. What does flip it is the
            # F = diag(1,1,1,1,-1,1) the reader applies: PTC prints ALFA33 in its own (T, PT) orientation of
            # coordinate 5, under which alfa_33 is ODD and beta_33 (and every transverse alfa/beta) is EVEN.
            # So the sign is a convention CONSTANT tied to F: -1 for k = 3 only, +1 for k = 1, 2.
            s_k = ALFA_SIGN_PTC_T[k]
            compare_row(id, "BETA$(k)$(k)", a.beta[j, k], rowf(row, "BETA$(k)$(k)_start"), TOL_C_REL, "TOL-C")
            compare_row(id, "ALFA$(k)$(k)" * (s_k < 0 ? "_PTC_T_convention_sign" : ""), s_k * a.alpha[j, k], rowf(row, "ALFA$(k)$(k)_start"), TOL_C_REL, "TOL-C")
            compare_row(id, "cos_mu$(k)", cos(a.tunes[j]), cos_turns(mus[k]), TOL_C_COS, "TOL-C"; metric=:abs)
        end
        # off-diagonal Ripken betas in the (plane p, mode k) order decided on the coupled 5D row; both transposes printed on the coupled 6D row.
        if id in COUPLED_IDS
            witness_row("$(id)_presented_edwards_teng_form_is_1", a.form === nothing ? NaN : a.form, 1, 0.0)
            index_order_rows(id, row, a.beta, mm.perm[1], mm.perm[2])
        end
        for p in 1:3, k in 1:3
            p == k && continue
            (p, k) in ((1, 2), (2, 1)) && id in COUPLED_IDS && continue   # printed by index_order_rows
            compare_row(id, "BETA$(p)$(k)_as_(plane,mode)", a.beta[mm.perm[k], p], rowf(row, "BETA$(p)$(k)_start"), TOL_C_REL, "TOL-C")
        end
        # DISP1..4 in 6D: RECORDED against the fixed-z quantity graph[:, 2] = eta/h; canonical eta and h printed beside, never compared.
        if a.graph === nothing || a.eta === nothing || a.h === nothing
            note(id, " graph/eta/h undetermined; the fixed-z DISP rows are not recorded")
        else
            for p in 1:4
                recorded_row(id, "DISP$(p)_fixed_z_dx_ddelta_vs_physical.graph[$(p),2]", a.graph[p, 2], rowf(row, "DISP$(p)_start"))
            end
            note(id, " canonical eta (physical.eta) ", join(fmt.(a.eta), ","), "; h ", fmt(a.h), "; graph[:,2] = eta/h ", join(fmt.(a.graph[:, 2]), ","))
        end
    end
end

# ---------------------------------------------------------------- B4L model layer (TOL-E)
"Least-squares slope of log(y) against log(x); the convergence order is -slope."
function fitted_order(nsts, residuals)
    x = log.(Float64.(collect(nsts))); y = log.(max.(Float64.(residuals), 1e-300))
    xm = sum(x) / length(x); ym = sum(y) / length(y)
    return -sum((x .- xm) .* (y .- ym)) / sum((x .- xm) .^ 2)
end

"The compared entries of a map: the trusted 4x4 block plus column 6 on a 5D row, the whole 6x6 on a 6D row."
compared_block(M::AbstractMatrix, layer::AbstractString) = layer == "5d" ? [M[1:4, 1:4] M[1:4, 6]] : Matrix{Float64}(M)

"""
B4L: the Octopus bare twin at nst in LADDER_NSTS (integrator order 4) against
F RE F; TW-PTC-MODEL prints the max-entry residual per nst, TW-PTC-ORDER the
fitted order over all five points (gate 4.0 +- 0.3), then the nst=32
residual gate (1e-9) and, once frozen, the nst=64 cap. RECORDED beside it:
the same ladder against the Octopus nst=256 map (the integrator's own
convergence, separating it from PTC's method=6 nst=10 floor). Returns the
largest nst=64 residual seen (the operand of the D6 cap freeze).
"""
function model_ladder(tab)
    worst64 = 0.0
    for row in vcat(rows_of(tab, "5d"), rows_of(tab, "6d"))   # U1 first (stage 8 decision D6, control R8)
        id = rowid(row); layer = rowlayer(row)
        Rext = layer == "5d" ? converted_5d(row).M :
               ptc_to_octopus(re_matrix(row); beta0=rowf(row, "beta0_header"), gamma0=rowf(row, "gamma0_header"), C=rowf(row, "C"))
        Rb = compared_block(Rext, layer)
        Rself = compared_block(bare_map(octopus_twin(id; nst=256)), layer)
        res = Float64[]; res_self = Float64[]
        for nst in LADDER_NSTS
            Ob = compared_block(bare_map(octopus_twin(id; nst=nst)), layer)
            push!(res, maximum(abs, Ob - Rb)); push!(res_self, maximum(abs, Ob - Rself))
            print_tw(BenchRow(:model, PTC_TAG * "-MODEL", id, string(nst), 0.0, 0.0, res[end], 0.0, "TOL-E", "model"))
        end
        order = fitted_order(LADDER_NSTS, res)
        ok = abs(order - LADDER_ORDER) <= LADDER_ORDER_TOL
        print_tw(BenchRow(:order, PTC_TAG * "-ORDER", id, "order", order, LADDER_ORDER, abs(order - LADDER_ORDER), LADDER_ORDER_TOL, "TOL-E", ok ? "PASS" : "FAIL"))
        recorded_row(id, "ladder_nst4_residual_recipe_row", res[1], 0.0)
        recorded_row(id, "ladder_order_vs_octopus_nst256_self_convergence", fitted_order(LADDER_NSTS, res_self), LADDER_ORDER)
        note(id, " self-convergence residuals vs Octopus nst=256: ", join(fmt.(res_self), ","), "; PTC floor (nst=64 vs F RE F) ", fmt(res[end]))
        recorded_row(id, "ladder_nst32_residual_design_TOL-E_1e-9_not_gated_D6", res[4], 0.0)
        compare_row(id, "ladder_nst64_residual_cap", res[5], 0.0, LADDER_CAP_64, "TOL-E"; metric=:abs)
        worst64 = max(worst64, res[5])
    end
    note("ladder: largest nst=64 residual ", fmt(worst64), " against the frozen LADDER_CAP_64 ", fmt(LADDER_CAP_64), " (provenance beside the constant)")
    return worst64
end

# ---------------------------------------------------------------- digest, table, gate
"TW-PTC-DIGEST <rows> <fails> <worst ratio> over the gated and witness rows (recorded/model rows count as rows, never as fails)."
function digest(rows::Vector{BenchRow})
    fails = count(r -> r.verdict == "FAIL", rows)
    worst = isempty(rows) ? 0.0 : maximum(row_ratio, rows)
    println(PTC_TAG, "-DIGEST ", length(rows), " ", fails, " ", fmt(worst))
    return (rows=length(rows), fails=fails, worst=worst)
end

"Write result/twiss_ptc_benchmark.tsv: one row per printed line, atomically (partial + mv)."
function write_rows_tsv(path::AbstractString, rows::Vector{BenchRow}, tab)
    mkpath(dirname(path))
    # write_reference_table adds the "# " prefix itself; table_version returns the table's own "# tool:" line.
    header = ["twiss_ptc_benchmark.jl: one row per gated, witness, recorded and model TW-PTC line (TW-PTC-NOTE and TW-PTC-DIGEST are printed only); numbers %.17g",
              "reference table: $(PTC_TABLE)",
              replace(table_version(tab.header), r"^# " => ""),
              "defect: $(PTC_DEFECT); nst ladder $(LADDER_NSTS); LADDER_CAP_64 $(fmt(LADDER_CAP_64))"]
    colnames = ["tag", "fixture", "quantity", "octopus", "external", "diff", "tol", "class", "verdict"]
    data = [Any[r.tag, r.fixture, r.quantity, r.octopus, r.external, r.diff, r.tol, r.class, r.verdict] for r in rows]
    write_reference_table(path, header, colnames, data)
    return length(data)
end

"error() on any FAIL (the gate); the message names the first failing row."
function gate(rows::Vector{BenchRow})
    bad = filter(r -> r.verdict == "FAIL", rows)
    isempty(bad) && return true
    first_bad = bad[1]
    error("twiss_ptc_benchmark: $(length(bad)) FAIL row(s); first: $(first_bad.tag) $(first_bad.fixture) $(first_bad.quantity) ",
          fmt(first_bad.octopus), " vs ", fmt(first_bad.external), " diff ", fmt(first_bad.diff), " tol ", fmt(first_bad.tol))
end

function main()
    println("twiss_ptc_benchmark: table ", PTC_TABLE)
    tab = read_table(PTC_TABLE)
    println("twiss_ptc_benchmark: ", table_version(tab.header))
    for l in tab.header
        (startswith(l, "# flags:") || startswith(l, "# conversion") || startswith(l, "# beam:") || startswith(l, "# W1")) && println("twiss_ptc_benchmark: ", l)
    end
    # arm identity (review B2 form, minor 4): Sys.CPU_NAME prints the host under -C haswell too, so name the arm's own flags
    ctarget = Base.JLOptions().cpu_target == C_NULL ? "-" : unsafe_string(Base.JLOptions().cpu_target)
    println("twiss_ptc_benchmark: rows ", join(rowid.(tab.rows), ","), "; defect ", PTC_DEFECT, "; julia ", VERSION, " ", Sys.CPU_NAME,
            "; OPENBLAS_CORETYPE=", get(ENV, "OPENBLAS_CORETYPE", "-"), " cpu_target=", ctarget)
    # the table must carry every stage 8 PTC fixture (S0, W1, U1, U2, K2, B4, B4K, G6_2.0MV, G6_0.2MV): the generator's abort path writes a 5D-only table (review B2 form, major 1)
    missing_ids = setdiff(EXPECTED_IDS, rowid.(tab.rows))
    compare_row(isempty(missing_ids) ? "table" : join(missing_ids, "+"), "table_rows_present", Float64(length(EXPECTED_IDS) - length(missing_ids)),
                Float64(length(EXPECTED_IDS)), 0.0, "TOL-C"; metric=:abs)
    note("layers: B0 witnesses, B1 5D (icase=5), B2/B3 6D (icase=6 rows with a cavity), B4L nst ladder")
    witness_rows(tab)
    layer_5d(tab)
    layer_6d(tab)
    model_ladder(tab)
    d = digest(ROWS)
    n = write_rows_tsv(PTC_OUT_TSV, ROWS, tab)
    println("TSV written to result/twiss_ptc_benchmark.tsv (", n, " rows)")
    gate(ROWS)
    println("twiss_ptc_benchmark: ", d.rows, " rows, 0 fails, worst ratio ", fmt(d.worst))
end

main()
