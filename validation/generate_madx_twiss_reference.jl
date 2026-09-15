"""
Generate the MAD-X `twiss` reference table that validation/twiss_madx_benchmark.jl
compares Octopus against (stage 8 of the twiss campaign, benchmark A).

This script needs MAD-X (default /usr/local/bin/madx, override with the
environment variable OCTOPUS_MADX); the consumer does not, because the table
it writes is committed. Regenerate only when the fixture list changes, and
record the MAD-X version in the table name and header when you do.

Reference model
---------------
MAD-X 5.03.06 `twiss` on the stage 8 fixtures (shared module
validation/twiss_benchmark_cells.jl), at the pinned beam
`beam, mass=0.93827208943, charge=1, energy=3.0;` (NO particle=, which makes
MAD-X ignore mass=). Every fixture runs TWO twiss commands, in this order:
  1. `twiss, betx=1, bety=1, rmatrix, file=<id>_initial.tfs;` -- the
     initial-condition run, whose CELL\$END row carries the one-turn map
     re11..re66 whatever the periodic solver does (measured 2026-09-15, history section: it exists even
     when the periodic solve fails);
  2. `twiss, rmatrix, file=<id>_periodic.tfs;` -- the periodic run, whose
     CELL\$START row carries betx, alfx, bety, alfy, r11..r22, dx, dpx, dy, dpy
     and whose header carries Q1, Q2 (the summ tunes; = the last row's mux,
     muy exactly, measured 2026-09-15).
U2 additionally runs `twiss, deltap=+-1e-4, rmatrix` (periodic) for the
momentum-convention witness: FD dx/ddeltap of the closed orbit against the
dx column, whose ratio is beta0 (MAD-X DX = dx/dPT; the stage 8 A0 momentum witness).

Fixtures
--------
The 13 ids of the shared module, one deck each: S0 (10 m drift), W2 (lone
quadrupole tilted by pi/4), U1 (uncoupled FODO), U2 (dispersive DBA), K1
(skew-coupled), K2 (coupled, diagonal R), the rolled equal-tune FODO R_0,
R_0.01, R_0.1, R_pi8, R_pi4, and the detuned controls Rd_1e-3, Rd_1e-6.

Tolerance
---------
The gates listed under "Witnesses and sanity gates" below: beta0 pin 1e-12
absolute, S0 RE56 1e-12 relative, map-vs-map witnesses 1e-14, W2 rotation
1e-12, U2 FD/DX 1e-8 (the finite-difference truncation), |eigenvalue| - 1
within 1e-12, closed orbit below 1e-9, symplectic residual below 1e-12.

Inputs / Outputs
----------------
Input: MAD-X itself (OCTOPUS_MADX). Output: validation/reference/twiss_madx_<version>.tsv
(committed, atomic partial+mv write); decks, TFS files and MAD-X logs under
result/twiss_madx_reference_work/ (git-ignored) unless OCTOPUS_STAGE8_WORKDIR is set;
regenerate mode writes its fresh table under <workdir>/regenerate/ and never
touches the committed path.

Table form (validation/reference/twiss_madx_<version>.tsv)
--------------------------------------------------------------
Rows: one per (fixture, file). file=periodic rows carry the optics of the
CELL\$START row, Q1/Q2 from the header, and the periodic file's map; file=initial
rows carry NaN optics and the initial-condition file's map (the map the
consumer uses). Where both exist the generator asserts the two maps agree to
1e-14. S0 and W2 (a lone drift or quadrupole has no periodic solution) and R_pi4 (MAD-X TWCPIN's false
instability, measured 2026-09-15) have NO periodic file and only an initial row. The
momentum witness is the row (U2, fd_deltap): dx, dpx, dy, dpy hold the
central finite differences d(closed orbit)/d(deltap) at deltap = +-1e-4 and
q1, q2 the tunes at +1e-4; every other cell of that row is NaN.
Columns: fixture, file, beta0, gamma0, C, betx, alfx, bety, alfy, r11, r12,
r21, r22, dx, dpx, dy, dpy, q1, q2, co_max, re11..re66 (row-major); %.17g.

Coordinates and the conversion the reader applies
-------------------------------------------------
MAD-X (X, PX, Y, PY, T, PT). The one-turn map is AS PRINTED. Octopus reads
    M_oct = Sh(-C/gamma0^2) J0 M_madx J0^-1,  J0 = diag(1,1,1,1,beta0,1/beta0)
(`convert_map(:madx, M; beta0, gamma0, C)` of the shared module), with beta0 =
PC/ENERGY and gamma0 = GAMMA from the TFS header and C = LENGTH. The 4x4
transverse block is convention-free. Dispersion: eta_oct = beta0 * DX. The
r11..r22 are the Edwards-Teng R (= form1.R of Octopus, no transpose).

Witnesses and sanity gates (printed as `MADX-WITNESS name value expected |diff| PASS|FAIL`
and `MADX-GATE fixture gate value PASS|FAIL`; any FAIL aborts before the write)
-------------------------------------------------------------------------------
beta0 pin |PC/ENERGY - 0.9498330546994187| <= 1e-12 on every file; S0
|RE56 - L/(beta0^2 gamma0^2)| <= 1e-12 |RE56|; converted S0 map equals the
Octopus bare_map(S0) to 1e-14; the shear -C/gamma0^2 from the header equals
the module's -slip(C) to 1e-12 relative; W2 map equals Rt(pi/4) M0 Rt(pi/4)'
to 1e-12; U2 |FD/DX - beta0| <= 1e-8 (the FD truncation); sign(RE51),
sign(RE52) of U2 equal the signs of Octopus's M51, M52; the periodic and
initial maps agree to 1e-14. Gates per fixture (the stage 8 sanity gates, history section): (i) every
requested column named in the `*` row; (ii) no load-bearing column identically
zero; (iii) six |eigenvalue| within 1e-12 of 1 (S0, W2 exempt: a lone drift or quad is not
a cell); (iv) closed orbit below 1e-9; (v) symplectic residual of the converted
map below 1e-12.

Run
---
    julia --project=. validation/generate_madx_twiss_reference.jl
    OCTOPUS_STAGE8_REGENERATE=1 julia --project=. validation/generate_madx_twiss_reference.jl
        re-runs MAD-X into a temporary table and diffs it cell by cell
        against the committed one (bit-equal expected on the same binary)
    OCTOPUS_MADX=<path>            the MAD-X binary (default /usr/local/bin/madx)
    OCTOPUS_STAGE8_WORKDIR=<dir>   where decks, TFS files and logs are kept
                                   (default result/twiss_madx_reference_work, git-ignored)
Environment: script mode only, CUDA_VISIBLE_DEVICES="" (both CPU arms).
"""

include(joinpath(@__DIR__, "twiss_benchmark_cells.jl"))

const MADX_BIN = get(ENV, "OCTOPUS_MADX", "/usr/local/bin/madx")
const REGENERATE = get(ENV, "OCTOPUS_STAGE8_REGENERATE", "0") == "1"
const WORKDIR = abspath(get(ENV, "OCTOPUS_STAGE8_WORKDIR",
                            joinpath(@__DIR__, "..", "result", "twiss_madx_reference_work")))
const OUTDIR = joinpath(@__DIR__, "reference")
const DELTAP_FD = 1.0e-4
const BETA0_PIN_ATOL = BENCH_BETA0_ATOL          # 1e-12 (stage 8 decision D13, history section)

# ---------------------------------------------------------------- MAD-X fixture decks
# Element numbers are the shared module's (specs_* of twiss_benchmark_cells.jl);
# %.17g literals round-trip to the same doubles MAD-X parses.
_g(x) = @sprintf("%.17g", Float64(x))

struct MadxFixture
    id::String
    elements::String     # element definitions
    line::String         # the cell line body
    C::Float64           # cell length in metres
    deltap_fd::Bool      # run the deltap=+-1e-4 periodic pair (U2 only)
    witness_only::Bool   # W2: no periodic solution expected; gate (iii) exempt
end
MadxFixture(id, elements, line, C) = MadxFixture(id, elements, line, C, false, false)

_fodo(id, kf, kd, tilt_f, tilt_d) = MadxFixture(id,
    "qf: quadrupole, l=0.2, k1=$(_g(kf)), tilt=$(_g(tilt_f));\n" *
    "qd: quadrupole, l=0.2, k1=$(_g(kd)), tilt=$(_g(tilt_d));\n" *
    "dr: drift, l=1.0;", "qf, dr, qd, dr", 2.4)
_dba(id, qf_tilt) = MadxFixture(id,
    "qd: quadrupole, l=0.25, k1=$(_g(-1.1));\nd: drift, l=0.6;\n" *
    "bd: sbend, l=1.0, angle=0.2;\nqf: quadrupole, l=0.35, k1=1.5, tilt=$(_g(qf_tilt));",
    "qd, d, bd, d, qf, d, bd, d, qd", 5.25, id == "U2", false)

const MADX_FIXTURES = MadxFixture[
    MadxFixture("S0", "dr: drift, l=10.0;", "dr", 10.0, false, true),   # a bare drift has no periodic solution: witness only
    MadxFixture("W2", "q: quadrupole, l=0.2, k1=1.0, tilt=$(_g(pi / 4));", "q", 0.2, false, true),
    MadxFixture("U1", "qf: quadrupole, l=0.3, k1=1.6;\nd: drift, l=1.2;\n" *
                      "qd: quadrupole, l=0.3, k1=$(_g(-1.6 * (1 + 1e-3)));", "qf, d, qd, d", 3.0),
    _dba("U2", 0.0),
    _fodo("K1", 1.0, -1.0, 0.0, K_TILT),
    _dba("K2", K_TILT),
    [_fodo(r.id, 1.0, -1.0, r.theta, r.theta) for r in ROLLED_THETAS]...,
    [_fodo(r.id, 1.0, -(1 + r.eps), pi / 4, pi / 4) for r in RD_EPSILONS]...,
]

# ---------------------------------------------------------------- decks, MAD-X, TFS
const TWISS_OPTICS_COLS = ["betx", "alfx", "bety", "alfy", "r11", "r12", "r21", "r22",
                           "dx", "dpx", "dy", "dpy"]
const TWISS_ORBIT_COLS = ["x", "px", "y", "py", "t", "pt"]
const TWISS_RE_COLS = ["re$(i)$(j)" for i in 1:6 for j in 1:6]
const TWISS_SELECT_COLS = ["name", "s", TWISS_OPTICS_COLS..., "mux", "muy",
                           TWISS_ORBIT_COLS..., TWISS_RE_COLS...]

"The deck of one fixture: hygiene lines, elements, the pinned beam, the two (or four) twiss runs."
function deck_text(fx::MadxFixture)
    io = IOBuffer()
    println(io, "! stage 8 benchmark A fixture $(fx.id) (validation/generate_madx_twiss_reference.jl)")
    println(io, "option, -echo, -info, -warn;")
    println(io, "option, rbarc=false;")
    println(io, "set, format=\"22.16e\";")
    println(io, fx.elements)
    println(io, "cell: line=($(fx.line));")
    println(io, BENCH_MADX_BEAM)
    println(io, "use, period=cell;")
    println(io, "select, flag=twiss, clear;")
    println(io, "select, flag=twiss, column=", join(TWISS_SELECT_COLS, ","), ";")
    println(io, "twiss, betx=1, bety=1, rmatrix, file=\"$(fx.id)_initial.tfs\";")
    println(io, "twiss, rmatrix, file=\"$(fx.id)_periodic.tfs\";")
    if fx.deltap_fd
        println(io, "twiss, deltap=$(_g(DELTAP_FD)), rmatrix, file=\"$(fx.id)_dpp.tfs\";")
        println(io, "twiss, deltap=$(_g(-DELTAP_FD)), rmatrix, file=\"$(fx.id)_dpm.tfs\";")
    end
    println(io, "stop;")
    return String(take!(io))
end

"Run MAD-X on `deck` inside `dir`, capturing stdout+stderr to `<deck>.out`. Exit codes are NOT trusted (MAD-X returns 0 on a failed twiss)."
function run_madx(dir::AbstractString, deck::AbstractString)
    isfile(MADX_BIN) || error("MAD-X binary not found at $(MADX_BIN) (set OCTOPUS_MADX)")
    log = joinpath(dir, deck * ".out")
    run(pipeline(Cmd(`$(MADX_BIN) $(deck)`; dir=dir, ignorestatus=true); stdout=log, stderr=log))
    return log
end

"The MAD-X version from a stop;-only deck (validation/generate_ptc_reference.jl:316-321)."
function madx_version(dir::AbstractString)
    write(joinpath(dir, "version.madx"), "stop;\n")
    log = run_madx(dir, "version.madx")
    m = match(r"MAD-X\s+([0-9.]+)", read(log, String))
    m === nothing && error("could not determine the MAD-X version from $(log)")
    return String(m.captures[1])
end

"""
    read_tfs(path) -> (header::Dict{String,Any}, names::Vector{String}, cols::Dict{String,Vector{Float64}}, rownames::Vector{String})

TFS reader: `@ KEY %fmt value` header lines (strings unquoted), the `*` column
row (names kept lower-case), `\$` types skipped, data rows split on whitespace.
"""
function read_tfs(path::AbstractString)
    isfile(path) || error("read_tfs: no such file $(path)")
    header = Dict{String,Any}()
    names = String[]
    cols = Dict{String,Vector{Float64}}()
    rownames = String[]
    for line in eachline(path)
        f = split(strip(line))
        isempty(f) && continue
        if f[1] == "@"
            val = join(f[4:end], " ")
            header[String(f[2])] = occursin("s", f[3]) ? strip(val, '"') : parse(Float64, val)
        elseif f[1] == "*"
            names = lowercase.(String.(f[2:end]))
            for n in names
                cols[n] = Float64[]
            end
        elseif f[1] == "\$"
            continue
        else
            length(f) == length(names) ||
                error("read_tfs: row with $(length(f)) fields, $(length(names)) columns in $(path)")
            push!(rownames, strip(String(f[1]), '"'))
            for (n, v) in zip(names[2:end], f[2:end])
                push!(cols[n], parse(Float64, v))
            end
        end
    end
    isempty(names) && error("read_tfs: no column row in $(path)")
    return (header=header, names=names, cols=cols, rownames=rownames)
end

"beta0 = PC/ENERGY, gamma0 = GAMMA, C = LENGTH from a TFS header."
tfs_beam(t) = (beta0=t.header["PC"] / t.header["ENERGY"], gamma0=t.header["GAMMA"], C=t.header["LENGTH"])

"The 6x6 map of the LAST row (CELL\$END), row-major re11..re66."
tfs_map(t) = [t.cols["re$(i)$(j)"][end] for i in 1:6, j in 1:6]

# ---------------------------------------------------------------- witnesses and gates
# Every check is a NUMBER compared to a formula in the header's own beta0/gamma0/C
# (stage 8 rule W: every witness is a formula in the header's own beam); nothing here trusts an exit code. Results accumulate in CHECKS
# as (line, pass) so the table header and the report can quote them.
const CHECKS = Tuple{String,Bool}[]

function witness!(name, value, expected, tol; relative=false)
    d = abs(value - expected)
    lim = relative ? tol * abs(expected) : tol
    ok = d <= lim
    line = @sprintf("MADX-WITNESS %s %.17g %.17g %.17g %s", name, value, expected, d, ok ? "PASS" : "FAIL")
    push!(CHECKS, (line, ok)); println(line)
    return ok
end
function gate!(fixture, name, value, ok::Bool)
    line = @sprintf("MADX-GATE %s %s %.17g %s", fixture, name, value, ok ? "PASS" : "FAIL")
    push!(CHECKS, (line, ok)); println(line)
    return ok
end
function record!(name, value)
    line = @sprintf("MADX-RECORDED %s %.17g", name, value)
    push!(CHECKS, (line, true)); println(line)
end

"Rt(t) = kron([c -s; s c], I2) on the 4x4 block, identity on (5,6): Octopus's tilt rotation, = MAD-X's R(-t) (both measured 2026-09-15 to <= 8.9e-16, history section)."
function tilt_rotation(t::Real)
    c, s = cos(t), sin(t)
    R = Matrix{Float64}(I, 6, 6)
    R[1:4, 1:4] = kron([c -s; s c], Matrix{Float64}(I, 2, 2))
    return R
end
"The analytic thick quadrupole map in MAD-X coordinates (k1 > 0 focuses in x; (5,6) = L/(beta0^2 gamma0^2))."
function analytic_quad_ext(L, k1; beta0, gamma0)
    k = sqrt(abs(k1)); f = [cos(k * L) sin(k * L) / k; -k * sin(k * L) cos(k * L)]
    d = [cosh(k * L) sinh(k * L) / k; k * sinh(k * L) cosh(k * L)]
    M = Matrix{Float64}(I, 6, 6)
    M[1:2, 1:2] = k1 > 0 ? f : d; M[3:4, 3:4] = k1 > 0 ? d : f
    M[5, 6] = L / (beta0^2 * gamma0^2)
    return M
end

"Load-bearing columns for gate (ii): dy/dpy/r's/orbit are legitimately zero on uncoupled cells."
function nonzero_columns(fx::MadxFixture, periodic::Bool)
    cols = ["s", "betx", "bety", "mux", "muy", "re11", "re12", "re22", "re33", "re34", "re44", "re55", "re56", "re66"]
    periodic && (fx.id in ("U2", "K2")) && push!(cols, "dx")
    periodic && (fx.id in ("K1", "K2") || startswith(fx.id, "R")) && !(fx.id == "R_0") &&
        append!(cols, ["r11", "r22"])
    return cols
end

"Gates (i)-(v) on one TFS file; returns the converted map. `periodic` selects the orbit gate and the optics columns."
function sanity_gates!(fx::MadxFixture, t, periodic::Bool; tag::AbstractString=fx.id * (periodic ? "/periodic" : "/initial"))
    missing = [c for c in TWISS_SELECT_COLS if !(c in t.names)]
    gate!(tag, "i_columns_present_missing", Float64(length(missing)), isempty(missing))
    zero_cols = [c for c in nonzero_columns(fx, periodic) if all(iszero, t.cols[c])]
    isempty(zero_cols) || println("  identically-zero load-bearing columns: ", join(zero_cols, ","))
    gate!(tag, "ii_nonzero_columns_zero", Float64(length(zero_cols)), isempty(zero_cols))
    b = tfs_beam(t)
    res = abs(b.beta0 - BENCH_BETA0_PIN)
    gate!(tag, "beta0_pin_residual", res, res <= BETA0_PIN_ATOL)
    gate!(tag, "gamma0_pin_residual", abs(b.gamma0 - BENCH_GAMMA0_PIN), abs(b.gamma0 - BENCH_GAMMA0_PIN) <= 1e-12)
    gate!(tag, "length_equals_C", abs(b.C - fx.C), abs(b.C - fx.C) <= 1e-12)
    M = tfs_map(t)
    em = eigen_moduli(M)
    println("  |eigenvalues| = ", join([_g(x) for x in em], " "))
    ok_eig = maximum(abs, em .- 1) <= 1e-12
    if fx.witness_only
        record!(tag * "_iii_eigen_moduli_max_dev(witness_only)", maximum(abs, em .- 1))
    else
        gate!(tag, "iii_eigen_moduli_max_dev", maximum(abs, em .- 1), ok_eig)
    end
    if periodic
        co = maximum(maximum(abs, t.cols[c]) for c in TWISS_ORBIT_COLS)
        gate!(tag, "iv_closed_orbit_max", co, co < 1e-9)
    end
    Mc = convert_map(:madx, M; beta0=b.beta0, gamma0=b.gamma0, C=b.C)
    sr = symplectic_residual(Mc)
    gate!(tag, "v_symplectic_residual_converted", sr, sr < 1e-12)
    return Mc
end

# ---------------------------------------------------------------- A0 convention witnesses
"S0: RE56 formula, converted map against Octopus bare_map(S0), the shear against the module's slip."
function witness_S0!(t)
    b = tfs_beam(t); M = tfs_map(t); L = b.C
    witness!("S0_RE56_vs_L/(beta0^2gamma0^2)", M[5, 6], L / (b.beta0^2 * b.gamma0^2), 1e-12; relative=true)
    Mc = convert_map(:madx, M; beta0=b.beta0, gamma0=b.gamma0, C=b.C)
    Moct = bare_map(S0())
    witness!("S0_converted_vs_octopus_bare_maxentry", maximum(abs, Mc - Moct), 0.0, 1e-14)
    witness!("S0_converted_times_octopus_inverse_vs_I6", maximum(abs, Mc * inv(Moct) - I), 0.0, 1e-14)
    witness!("S0_shear_header_vs_module_slip", -b.C / b.gamma0^2, -slip(b.C), 1e-12; relative=true)
    witness!("S0_analytic_drift_ext_vs_madx_map", maximum(abs, M - analytic_drift_ext(:madx, L; beta0=b.beta0, gamma0=b.gamma0)), 0.0, 1e-14)
    return nothing
end

"W2: the lone tilted quad equals Rt(pi/4) M0 Rt(pi/4)' at 1e-12 (rule W); the Octopus model gap is recorded."
function witness_W2!(t)
    b = tfs_beam(t); M = tfs_map(t)
    M0 = analytic_quad_ext(0.2, 1.0; beta0=b.beta0, gamma0=b.gamma0)
    Rt = tilt_rotation(pi / 4)
    witness!("W2_madx_vs_Rt(pi/4)M0Rt'", maximum(abs, M - Rt * M0 * Rt'), 0.0, 1e-12)
    record!("W2_other_sense_Rt'M0Rt_maxdiff", maximum(abs, M - Rt' * M0 * Rt))
    Mc = convert_map(:madx, M; beta0=b.beta0, gamma0=b.gamma0, C=b.C)
    record!("W2_converted_vs_octopus_bare_maxentry(nst=64_model)", maximum(abs, Mc - bare_map(W2())))
    return nothing
end

"U2: the momentum-convention witness (FD dx/ddeltap vs beta0 DX) and rule X's row-5 sign witness."
function witness_U2!(tp, ti, tpp, tpm)
    b = tfs_beam(tp)
    for c in ("x", "px", "y", "py")
        v = (tpp.cols[c][1], tpm.cols[c][1])
        println(@sprintf("  U2 closed orbit %s at deltap=+%.17g: %.17g; at -%.17g: %.17g", c, DELTAP_FD, v[1], DELTAP_FD, v[2]))
    end
    fd = Dict(c => (tpp.cols[c][1] - tpm.cols[c][1]) / (2 * DELTAP_FD) for c in ("x", "px", "y", "py"))
    DX = tp.cols["dx"][1]
    record!("U2_FD_dx/ddeltap", fd["x"]); record!("U2_DX_column_start", DX)
    witness!("U2_FD/DX_vs_beta0_header", fd["x"] / DX, b.beta0, 1e-8)
    witness!("U2_FD_vs_beta0*DX_relative", fd["x"], b.beta0 * DX, 1e-8; relative=true)
    # the dispersion of the exported map itself: (I - M4)^-1 M[1:4,6] reproduces the dx column (measured 2e-16, history section)
    M = tfs_map(ti)
    Dpt = (Matrix{Float64}(I, 4, 4) - M[1:4, 1:4]) \ M[1:4, 6]
    witness!("U2_dx_column_vs_(I-M4)^-1M16", DX, Dpt[1], 1e-12; relative=true)
    witness!("U2_dpx_column_vs_(I-M4)^-1M26_abs", tp.cols["dpx"][1], Dpt[2], 1e-12)
    Moct = bare_map(U2())
    for (i, name) in ((1, "RE51"), (2, "RE52"))
        record!("U2_madx_$(name)", M[5, i]); record!("U2_octopus_M5$(i)", Moct[5, i])
        witness!("U2_sign_$(name)_vs_octopus", sign(M[5, i]), sign(Moct[5, i]), 0.0)
    end
    Mc = convert_map(:madx, M; beta0=b.beta0, gamma0=b.gamma0, C=b.C)
    record!("U2_converted_vs_octopus_bare_maxentry(nst=64_model)", maximum(abs, Mc - Moct))
    record!("U2_eta_oct=beta0*DX", b.beta0 * DX); record!("U2_octopus_(I-M4)^-1M16", ((I - Moct[1:4, 1:4]) \ Moct[1:4, 6])[1])
    return (; fd, q1=tpp.header["Q1"], q2=tpp.header["Q2"])
end

# ---------------------------------------------------------------- rows and the table
const TABLE_COLNAMES = ["fixture", "file", "beta0", "gamma0", "C", TWISS_OPTICS_COLS...,
                        "q1", "q2", "co_max", TWISS_RE_COLS...]
const NOTES = String[]      # per-fixture facts for the header (file availability)

_row(id, file, b, optics, q1, q2, co, M) =
    Any[id, file, b.beta0, b.gamma0, b.C, optics..., q1, q2, co, (M[i, j] for i in 1:6 for j in 1:6)...]
const NAN12 = fill(NaN, length(TWISS_OPTICS_COLS))
const NAN66 = fill(NaN, 6, 6)

"Run one fixture: deck, MAD-X, gates, witnesses; returns its table rows."
function run_fixture(fx::MadxFixture, dir::AbstractString)
    println("\n==== fixture ", fx.id)
    write(joinpath(dir, fx.id * ".madx"), deck_text(fx))
    run_madx(dir, fx.id * ".madx")
    pi_ = joinpath(dir, fx.id * "_initial.tfs"); pp = joinpath(dir, fx.id * "_periodic.tfs")
    isfile(pi_) || error("fixture $(fx.id): the initial-condition TFS file was not written ($(pi_))")
    ti = read_tfs(pi_)
    sanity_gates!(fx, ti, false)
    rows = Any[_row(fx.id, "initial", tfs_beam(ti), NAN12, NaN, NaN, NaN, tfs_map(ti))]
    if !isfile(pp)
        push!(NOTES, "$(fx.id): NO periodic TFS file written (MAD-X periodic twiss failed; " *
                     (fx.witness_only ? "expected, a lone drift or quadrupole is not a stable cell)" :
                      "TWCPIN false instability of the degenerate rolled cell, measured 2026-09-15); initial-condition map kept"))
        println("  ", NOTES[end])
        return rows, ti, nothing
    end
    tp = read_tfs(pp)
    sanity_gates!(fx, tp, true)
    dmap = maximum(abs, tfs_map(tp) - tfs_map(ti))
    witness!("$(fx.id)_periodic_vs_initial_map_maxentry", dmap, 0.0, 1e-14)
    optics = [tp.cols[c][1] for c in TWISS_OPTICS_COLS]
    co = maximum(maximum(abs, tp.cols[c]) for c in TWISS_ORBIT_COLS)
    q1, q2 = tp.header["Q1"], tp.header["Q2"]
    witness!("$(fx.id)_Q1_vs_mux_end", q1, tp.cols["mux"][end], 0.0)
    witness!("$(fx.id)_Q2_vs_muy_end", q2, tp.cols["muy"][end], 0.0)
    push!(rows, _row(fx.id, "periodic", tfs_beam(tp), optics, q1, q2, co, tfs_map(tp)))
    push!(NOTES, "$(fx.id): periodic and initial files written; maps agree to $(_g(dmap))")
    return rows, ti, tp
end

function header_lines(version)
    h = ["MAD-X twiss reference for validation/twiss_madx_benchmark.jl (stage 8 benchmark A); generated by validation/generate_madx_twiss_reference.jl",
         "MAD-X version: $(version)",
         "flags: option, -echo, -info, -warn; option, rbarc=false; set, format=\"22.16e\"; use, period=cell; twiss, betx=1, bety=1, rmatrix (initial rows) and twiss, rmatrix (periodic rows); U2 fd_deltap row from twiss, deltap=+-$(_g(DELTAP_FD)), rmatrix",
         "beam: $(BENCH_MADX_BEAM)  beta0 = PC/ENERGY, gamma0 = GAMMA from every TFS header; pin |beta0 - $(_g(BENCH_BETA0_PIN))| <= $(_g(BETA0_PIN_ATOL)) asserted per file",
         "coordinates: MAD-X (X,PX,Y,PY,T,PT) AS PRINTED; the map re11..re66 is the CELL\$END row of the named file; optics are the CELL\$START row of the periodic file; q1,q2 are the summ tunes (= mux,muy of the last row exactly); co_max = max |x,px,y,py,t,pt| over the rows",
         "conversion the reader applies: M_oct = Sh(-C/gamma0^2) J0 M J0^-1 with J0 = diag(1,1,1,1,beta0,1/beta0) (convert_map(:madx, M; beta0, gamma0, C)); eta_oct = beta0 * DX; r11..r22 = Edwards-Teng R = Octopus form1.R (no transpose); the 4x4 block is convention-free",
         "rows: file=initial carries the one-turn map and NaN optics; file=periodic carries the optics and its own map (agrees with the initial map to 1e-14 where both exist); file=fd_deltap (U2 only) carries dx,dpx,dy,dpy = central FD d(closed orbit)/d(deltap) at deltap=+-$(_g(DELTAP_FD)) and q1,q2 at +$(_g(DELTAP_FD)); NaN = not available",
         "MAD-X's rolled-cell tunes (R_0.01, R_0.1, R_pi8) are a DIRECTIONAL SENTINEL of TWCPIN's failure on the degenerate pair (stage 8 decision D9, history section), never pinned digits; R_pi4 has no periodic solution"]
    append!(h, "fixture: " .* NOTES)
    # Octopus-model numbers (nst=64 gaps, Octopus M5i digits) stay in the log only: they may move by an ulp between CPU arms
    n_gates = count(l -> startswith(l, "MADX-GATE"), first.(CHECKS))
    push!(h, "gates: $(n_gates) MADX-GATE checks (i)-(v) plus beta0/gamma0/length pins all PASS at generation (per-fixture values in the generator log); the witness lines follow")
    # LAPACK-derived diagnostics (eigenvalue moduli, the (I-M4) solve, the inverse) move by an ulp between CPU arms too
    lapack(l) = occursin("eigen_moduli", l) || occursin("(I-M4)^-1", l) || occursin("_inverse_", l)
    append!(h, [l for (l, _) in CHECKS if !startswith(l, "MADX-GATE") && !lapack(l) && !(occursin("nst=64_model", l) || occursin("U2_octopus_", l))])
    return h
end

function generate(table_path::AbstractString, dir::AbstractString)
    mkpath(dir)
    version = madx_version(dir)
    println("MAD-X version ", version, " at ", MADX_BIN, "; work dir ", dir)
    rows = Any[]; tfs = Dict{String,Any}()
    for fx in MADX_FIXTURES
        r, ti, tp = run_fixture(fx, dir)
        append!(rows, r); tfs[fx.id] = (ti, tp)
    end
    println("\n==== A0 witnesses")
    witness_S0!(tfs["S0"][1]); witness_W2!(tfs["W2"][1])
    tpp = read_tfs(joinpath(dir, "U2_dpp.tfs")); tpm = read_tfs(joinpath(dir, "U2_dpm.tfs"))
    u2 = MADX_FIXTURES[findfirst(f -> f.id == "U2", MADX_FIXTURES)]
    sanity_gates!(u2, tpp, false; tag="U2/deltap+1e-4"); sanity_gates!(u2, tpm, false; tag="U2/deltap-1e-4")
    fdw = witness_U2!(tfs["U2"][2], tfs["U2"][1], tpp, tpm)
    fdoptics = [NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, fdw.fd["x"], fdw.fd["px"], fdw.fd["y"], fdw.fd["py"]]
    push!(rows, _row("U2", "fd_deltap", tfs_beam(tfs["U2"][2]), fdoptics, fdw.q1, fdw.q2, NaN, NAN66))
    fails = [l for (l, ok) in CHECKS if !ok]
    println(@sprintf("\nMADX-GEN-DIGEST checks=%d fails=%d rows=%d", length(CHECKS), length(fails), length(rows)))
    isempty(fails) || error("generator aborted before the write; failing checks:\n" * join(fails, "\n"))
    write_reference_table(table_path, header_lines(version), TABLE_COLNAMES, rows)
    println("wrote ", table_path, " (", length(rows), " rows)")
    return table_path
end

# ---------------------------------------------------------------- regenerate mode (stage 8 decision D17, OCTOPUS_STAGE8_REGENERATE=1)
"Diff two tables cell by cell (header lines included); prints every difference and returns their count."
function diff_tables(committed::AbstractString, fresh::AbstractString)
    a = read_reference_table(committed); b = read_reference_table(fresh)
    n = 0
    for (i, (x, y)) in enumerate(zip(a.header, b.header))
        x == y || (n += 1; println("DIFF header line $(i):\n  committed: $(x)\n  fresh:     $(y)"))
    end
    length(a.header) == length(b.header) || (n += 1; println("DIFF header length $(length(a.header)) vs $(length(b.header))"))
    a.colnames == b.colnames || (n += 1; println("DIFF column row"))
    for c in a.colnames
        haskey(b.columns, c) || continue
        ca, cb = a.columns[c], b.columns[c]
        length(ca) == length(cb) || (n += 1; println("DIFF column $(c) length $(length(ca)) vs $(length(cb))"))
        for k in 1:min(length(ca), length(cb))
            ca[k] == cb[k] || (n += 1; println("DIFF row $(k) ($(a.columns["fixture"][k]),$(a.columns["file"][k])) column $(c): $(ca[k]) vs $(cb[k])"))
        end
    end
    return n
end

function main()
    mkpath(WORKDIR)
    version = madx_version(WORKDIR)
    committed = joinpath(OUTDIR, "twiss_madx_$(version).tsv")
    if REGENERATE
        isfile(committed) || error("regenerate mode: no committed table at $(committed)")
        fresh = joinpath(WORKDIR, "regenerate", "twiss_madx_$(version).tsv")
        generate(fresh, joinpath(WORKDIR, "regenerate"))
        n = diff_tables(committed, fresh)
        println(@sprintf("MADX-REGENERATE-DIFF %s %s differing_cells=%d %s", committed, fresh, n, n == 0 ? "PASS" : "FAIL"))
        n == 0 || error("regenerate mode: $(n) differing cells")
    else
        generate(committed, WORKDIR)
    end
end

main()
