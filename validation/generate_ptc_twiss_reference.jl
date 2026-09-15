"""
Generate the PTC ptc_twiss reference table of the stage 8 benchmark B
(validation/twiss_ptc_benchmark.jl reads it; docs/theory/twiss_dispersion.md
12.2 item 3, the PTC half). This script needs MAD-X (PTC as distributed with
MAD-X 5.03.06); the consumer does not, because the table is committed.

Reference model
---------------
PTC through ptc_create_layout, model=1, method=6, nst=10, exact=true,
time=false (stage 8 decision D4, history section of benchmark B). method=6 replaces the method=2 of
validation/generate_ptc_reference.jl because the exact sbend at method=2
nst=10 carries a closed-orbit artifact of x = -4.7e-5 m per DBA cell that
method=6 removes; the method=2 artifact ladder (nst = 1, 10, 40, 160) is
printed with its fitted order for the record. Every run is one MAD-X job in
its own directory; the 6D runs (icase=6, which is FATAL without betz > 0)
come last. The beam is the pinned one of stage 8 decision D13, written verbatim as
BENCH_MADX_BEAM of validation/twiss_benchmark_cells.jl.

Coordinate rule (probes p2 S2, S3)
----------------------------------
ptc_twiss time=false prints (X,PX,Y,PY,T,PT) with coordinate 6 = delta =
dp/p0 and its RE rows in the ptc_track T orientation (row 5 = +path-length
excess); RE is cumulative from the START row, so only the END row is read.
The table is written AS PRINTED (stage 8 decision D7) and the reader applies
F = diag(1,1,1,1,-1,1):  M_oct = F RE F (J0 = I, no shear; the stage 8 conversion law, history section),
the partner of the Octopus BARE compile.

Witnesses (the stage 8 B0 witness set, run before any optics row is written)
-----------------------------------------------------------
S0 drift L = 10 m: |RE56| <= 1e-12 (time=false has no chromatic slip) and,
with pt = 1e-3 as the initial condition, |RE12 - L/(1 + 1e-3)| <= 1e-12
relative (coordinate 6 is delta). W1 lone 400 MHz cavity, volt = 60 MV =
strength * E_total, lag = 0.5, at PTC's EFFECTIVE beam (stage 8 decision D19: PTC
evaluates the cavity at its internal proton mass PTC_INTERNAL_PROTON_MASS_GEV
whatever the deck says, so beta0_ptc = PTC_BETA0 of the shared module): gated
at 1e-10 are |RE65_flipped - strength (2 pi f/c)/PTC_BETA0^2|, RE65_flipped
against the Octopus bare W1 twin compiled with cavity_beta0 = PTC_BETA0,
cavity_gamma0 = PTC_GAMMA0, and that twin against the formula; RECORDED (not
gated) is RE65_flipped against the formula at the HEADER beta0 (the PTC
internal-mass effect, 3.467e-10). RE65_flipped = -RE65 as printed. If the
first gated line misses, the 6D rows are ABORTED (not written) and the
script errors after writing the 5D rows.
Every 6D run: the symplectic residual of RE as printed and of F RE F (the
latter <= 1e-12). Every run: |PC/ENERGY - BENCH_BETA0_PIN| <= 1e-12 from
the TFS header, MASS == 0.93827208943 to 1e-15.

PTC traps encoded as assertions
-------------------------------
RE is all zeros without the bare rmatrix flag; unknown columns print
silently as zeros; so every requested column is checked present in the
column row and a per-run list of load-bearing columns is checked non-zero.
icase=5 prints RE55 = 0 (p2 open question 2): RE55 is not load-bearing there.

Configuration
-------------
OCTOPUS_MADX            MAD-X binary (default /usr/local/bin/madx).
OCTOPUS_STAGE8_WORKDIR  directory for the decks and TFS files (default a
                        fresh mktempdir).
OCTOPUS_STAGE8_REGENERATE=1  regenerate into a temporary table and diff it
                        cell by cell against the committed one (stage 8 decision D17);
                        the committed table is not touched in that mode.

Fixtures (validation/twiss_benchmark_cells.jl; the stage 8 fixture table in the history section)
-----------------------------------------------------------------
S0, W1 (witnesses); U1, U2, K2 at icase=5, no=1, closed_orbit=true;
B4, B4K (60 MV, 400 MHz), G6 at 2.0 and 0.2 MV (h = 12) at icase=6,
rmatrix, closed_orbit=true, lag = 0.5 (the stable phase with time=false).

Inputs/Outputs
--------------
Writes validation/reference/ptc_twiss_madx_<version>.tsv atomically
(partial file then mv). The name must NOT start with ptc_madx_, which is the
selector of PTCConsistencyContract's tracking table (the stage 8 PTC layer design, history section).

Run
---
    env CUDA_VISIBLE_DEVICES="" julia --project=. validation/generate_ptc_twiss_reference.jl

Environment
-----------
MAD-X 5.03.06 (/usr/local/bin/madx), Julia project of this repository.
Numbers are printed with %.17g. Nothing here runs Pkg.
"""

# Octopus is loaded by the fixture module through the guarded include (validation/twiss_benchmark_cells.jl).
include(joinpath(@__DIR__, "twiss_benchmark_cells.jl"))
using Printf
using LinearAlgebra

const MADX_BIN = get(ENV, "OCTOPUS_MADX", "/usr/local/bin/madx")
const REGENERATE = get(ENV, "OCTOPUS_STAGE8_REGENERATE", "0") == "1"
const WORKDIR = let d = get(ENV, "OCTOPUS_STAGE8_WORKDIR", "")
    isempty(d) ? mktempdir() : (mkpath(d); abspath(d))
end
const OUTDIR = joinpath(@__DIR__, "reference")
const PTC_LAYOUT = "ptc_create_layout, model=1, method=6, nst=10, exact=true, time=false;"
const LAG = 0.5
const W1_VOLT_MV = RF_STRENGTH * BENCH_E_TOTAL_EV / 1e6      # 60.0 MV = strength * E_total
const RF_FREQ_MHZ = RF_FREQUENCY_HZ / 1e6                      # 400.0
const G6_FREQ_MHZ = G6_FREQUENCY_HZ / 1e6                      # 108.47725186970942
const S0_LENGTH = 10.0
const PT_WITNESS = 1.0e-3

# ---------------------------------------------------------------- decks
# Element numbers are the fixture module's (specs_U1, specs_U2, specs_K2,
# specs_B4, specs_B4K, specs_G6, specs_W1, specs_S0); every sequence is named
# lat, so the periodic optics sit in the LAT$START row and the cumulative
# one-turn RE in the LAT$END row.
g17(x) = @sprintf("%.17g", x)

const DBA_ELEMENTS = """
qd: quadrupole, l=0.25, k1=-1.1;
qf: quadrupole, l=0.35, k1=1.5__QFTILT__;
b:  sbend, l=1.0, angle=0.2;
d:  drift, l=0.6;
"""
const DBA_CELL_BODY = """
  qd, at=0.125;
  d,  at=0.55;
  b,  at=1.35;
  d,  at=2.15;
  qf, at=2.625;
  d,  at=3.10;
  b,  at=3.90;
  d,  at=4.70;
  qd, at=5.125;
"""

dba_elements(tilt) = replace(DBA_ELEMENTS, "__QFTILT__" => (tilt == 0 ? "" : ", tilt=$(g17(tilt))"))
cavity_line(volt_MV, freq_MHz) =
    "cav: rfcavity, l=0, volt=$(g17(volt_MV)), freq=$(g17(freq_MHz)), lag=$(g17(LAG));\n"

"One-cell DBA lattice (U2, K2), optionally with the B4/B4K cavity at the end."
function dba_lattice(tilt; cavity=false)
    els = dba_elements(tilt) * (cavity ? cavity_line(W1_VOLT_MV, RF_FREQ_MHZ) : "")
    return els * "lat: sequence, l=5.25;\n" * DBA_CELL_BODY *
           (cavity ? "  cav, at=5.25;\n" : "") * "endsequence;\n"
end

"Six DBA cells plus the ring cavity (G6) at volt_MV."
function g6_lattice(volt_MV)
    els = dba_elements(0.0) * cavity_line(volt_MV, G6_FREQ_MHZ) *
          "cell: sequence, l=5.25;\n" * DBA_CELL_BODY * "endsequence;\n"
    body = join(("  cell, at=$(g17(5.25 * (i - 0.5)));\n" for i in 1:G6_CELLS))
    return els * "lat: sequence, l=$(g17(G6_LENGTH));\n" * body * "  cav, at=$(g17(G6_LENGTH));\n" * "endsequence;\n"
end

const U1_LATTICE = """
qf: quadrupole, l=0.3, k1=1.6;
qd: quadrupole, l=0.3, k1=$(g17(-1.6 * (1 + 1e-3)));
d:  drift, l=1.2;
lat: sequence, l=3.0;
  qf, at=0.15;
  d,  at=0.9;
  qd, at=1.65;
  d,  at=2.4;
endsequence;
"""
const S0_LATTICE = """
dd: drift, l=$(g17(S0_LENGTH));
lat: sequence, l=$(g17(S0_LENGTH));
  dd, at=$(g17(S0_LENGTH / 2));
endsequence;
"""
# MAD-X refuses a zero-length sequence, so the lone cavity is followed by a
# 0.2 m drift; a drift has row 6 = e6, so (drift * cavity) keeps row 6 of the
# cavity and RE65 is the cavity's own.
const W1_LATTICE = cavity_line(W1_VOLT_MV, RF_FREQ_MHZ) * """
lat: sequence, l=0.2;
  cav, at=0.0;
endsequence;
"""

const OPTICS_COLUMNS = ["beta11", "beta12", "beta13", "beta21", "beta22", "beta23", "beta31", "beta32", "beta33",
                        "alfa11", "alfa12", "alfa13", "alfa21", "alfa22", "alfa23", "alfa31", "alfa32", "alfa33",
                        "gama11", "gama22", "gama33", "disp1", "disp2", "disp3", "disp4", "mu1", "mu2", "mu3",
                        "x", "px", "y", "py", "t", "pt"]
const RE_COLUMNS = ["re$(i)$(j)" for i in 1:6 for j in 1:6]
const HEADER_PARAMS = ["MASS", "CHARGE", "ENERGY", "PC", "LENGTH", "ALPHA_C", "ETA_C", "Q1", "Q2", "QS",
                       "ORBIT_X", "ORBIT_PX", "ORBIT_Y", "ORBIT_PY", "ORBIT_PT"]

# ---------------------------------------------------------------- runs
struct Run
    id::String          # table row id
    layer::String       # witness | 5d | 6d
    lattice::String     # element and sequence definitions
    ptc_twiss::String   # the ptc_twiss command body (flags only; table/file are appended)
    icase::Int
    volt_MV::Float64    # 0 when no cavity
    freq_MHz::Float64
    C::Float64
    nonzero::Vector{String}   # load-bearing columns (silent-zero trap)
    layout::String
end
Run(id, layer, lattice, cmd, icase, volt, freq, C, nonzero) =
    Run(id, layer, lattice, cmd, icase, volt, freq, C, nonzero, PTC_LAYOUT)

const NZ_4D = ["re11", "re12", "re21", "re22", "re33", "re34", "re43", "re44", "re66", "beta11", "beta22",
               "gama11", "gama22", "mu1", "mu2"]
const NZ_5D = vcat(NZ_4D, ["disp1", "re16", "re26"])   # DISP2 is 0 at the DBA mirror point, not load-bearing
const NZ_6D = vcat(NZ_5D, ["re55", "re56", "re65", "beta33", "mu3", "QS"])
const IC6 = "icase=6, no=1, closed_orbit=false, betx=1, bety=1, betz=1, rmatrix"

const RUNS = Run[
    Run("S0", "witness", S0_LATTICE, IC6, 6, 0.0, 0.0, S0_LENGTH,
        ["re11", "re12", "re22", "re33", "re34", "re44", "re55", "re66"]),
    Run("S0_pt", "witness", S0_LATTICE, IC6 * ", pt=$(g17(PT_WITNESS))", 6, 0.0, 0.0, S0_LENGTH,
        ["re11", "re12", "re22", "re33", "re34", "re44", "re55", "re66", "pt"]),
    Run("W1", "witness", W1_LATTICE, IC6, 6, W1_VOLT_MV, RF_FREQ_MHZ, 0.2,
        ["re11", "re22", "re33", "re44", "re55", "re65", "re66"]),
    Run("U1", "5d", U1_LATTICE, "icase=5, no=1, closed_orbit=true, rmatrix", 5, 0.0, 0.0, 3.0, NZ_4D),
    Run("U2", "5d", dba_lattice(0.0), "icase=5, no=1, closed_orbit=true, rmatrix", 5, 0.0, 0.0, 5.25, NZ_5D),
    Run("K2", "5d", dba_lattice(K_TILT), "icase=5, no=1, closed_orbit=true, rmatrix", 5, 0.0, 0.0, 5.25,
        vcat(NZ_5D, ["re13", "re31", "beta12", "beta21"])),
    # 6D LAST: icase=6 without betz > 0 is fatal and aborts the whole MAD-X job.
    Run("B4", "6d", dba_lattice(0.0; cavity=true), "icase=6, no=1, closed_orbit=true, rmatrix", 6,
        W1_VOLT_MV, RF_FREQ_MHZ, 5.25, NZ_6D),
    Run("B4K", "6d", dba_lattice(K_TILT; cavity=true), "icase=6, no=1, closed_orbit=true, rmatrix", 6,
        W1_VOLT_MV, RF_FREQ_MHZ, 5.25, vcat(NZ_6D, ["re13", "re31", "beta12", "beta21"])),
    Run("G6_2.0MV", "6d", g6_lattice(2.0), "icase=6, no=1, closed_orbit=true, rmatrix", 6,
        2.0, G6_FREQ_MHZ, G6_LENGTH, NZ_6D),
    Run("G6_0.2MV", "6d", g6_lattice(0.2), "icase=6, no=1, closed_orbit=true, rmatrix", 6,
        0.2, G6_FREQ_MHZ, G6_LENGTH, NZ_6D),
]

function madx_version()
    dir = mkpath(joinpath(WORKDIR, "version"))
    write(joinpath(dir, "v.madx"), "stop;\n")
    out = read(Cmd(`$MADX_BIN v.madx`; dir=dir), String)
    m = match(r"MAD-X\s+([0-9.]+)", out)
    m === nothing && error("could not determine the MAD-X version")
    return String(m.captures[1])
end

"""
Parse a ptc_twiss TFS file: the @ header params (Dict name => string), the
column names of the * row (upper case, as printed) and the named rows
(Dict row name => Vector of cell strings, one per column).
"""
function read_tfs(path::AbstractString)
    isfile(path) || error("read_tfs: no such file $(path)")
    params = Dict{String,String}()
    colnames = String[]
    rows = Dict{String,Vector{String}}()
    for line in eachline(path)
        s = strip(line)
        isempty(s) && continue
        if startswith(s, "@")
            f = split(s)
            length(f) >= 4 && (params[String(f[2])] = String(strip(join(f[4:end], " "), '"')))
        elseif startswith(s, "*")
            colnames = String.(split(s)[3:end])   # drop the * and the NAME column (the row name is the key)
        elseif startswith(s, "\$")
            continue
        else
            f = split(s)
            name = String(strip(f[1], '"'))
            rows[name] = String.(f[2:end])
            length(f) - 1 == length(colnames) || error("read_tfs: row $(name) has $(length(f) - 1) cells, $(length(colnames)) columns in $(path)")
        end
    end
    isempty(colnames) && error("read_tfs: no column row in $(path)")
    return (params=params, colnames=colnames, rows=rows)
end

cell(tfs, row::AbstractString, col::AbstractString) =
    parse(Float64, tfs.rows[row][findfirst(==(uppercase(col)), tfs.colnames)])
param(tfs, name::AbstractString) = parse(Float64, tfs.params[name])

# ---------------------------------------------------------------- one MAD-X job per run
const ALL_COLUMNS = vcat(["name", "s"], OPTICS_COLUMNS, RE_COLUMNS)

function deck_text(run::Run, tfsname::AbstractString)
    return """
    ! stage 8 benchmark B, run $(run.id) ($(run.layer)); generated by validation/generate_ptc_twiss_reference.jl
    option, -echo, -info, -warn;
    option, rbarc=false;
    set, format="22.16e";
    $(BENCH_MADX_BEAM)
    value, beam->beta, beam->gamma, beam->pc, beam->mass;
    $(run.lattice)use, sequence=lat;
    select, flag=ptc_twiss, clear;
    select, flag=ptc_twiss, column=$(join(ALL_COLUMNS, ","));
    ptc_create_universe;
    $(run.layout)
    ptc_twiss, $(run.ptc_twiss), table=ptc_twiss, file=$(tfsname);
    ptc_end;
    stop;
    """
end

"Run MAD-X in its own directory; assert on the table, never on the exit code (W4)."
function run_madx(run::Run)
    dir = mkpath(joinpath(WORKDIR, run.id))
    tfsname = lowercase("tw_$(run.id).tfs")   # MAD-X lowercases file names
    rm(joinpath(dir, tfsname); force=true)
    write(joinpath(dir, "job.madx"), deck_text(run, tfsname))
    log = joinpath(dir, "job.out")
    rc = 0
    try
        Base.run(pipeline(Cmd(`$MADX_BIN job.madx`; dir=dir); stdout=log, stderr=log))
    catch err
        err isa ProcessFailedException || rethrow()
        rc = first(err.procs).exitcode
    end
    isfile(joinpath(dir, tfsname)) ||
        error("run $(run.id): MAD-X wrote no table (rc=$(rc)); see $(log)")
    tfs = read_tfs(joinpath(dir, tfsname))
    check_table(run, tfs)
    println(@sprintf("PTC-RUN %s rc=%d rows=%d columns=%d", run.id, rc, length(tfs.rows), length(tfs.colnames)))
    return tfs
end

"Every requested column present, every load-bearing cell non-zero, the beam pinned (D13)."
function check_table(run::Run, tfs)
    for c in ALL_COLUMNS[2:end]   # NAME is the row key, not a numeric column
        uppercase(c) in tfs.colnames || error("run $(run.id): requested column $(c) missing from the table")
    end
    haskey(tfs.rows, "LAT\$START") && haskey(tfs.rows, "LAT\$END") ||
        error("run $(run.id): LAT\$START / LAT\$END rows missing; rows = $(sort(collect(keys(tfs.rows))))")
    for p in HEADER_PARAMS
        haskey(tfs.params, p) || error("run $(run.id): header parameter $(p) missing")
    end
    for c in run.nonzero
        v = c == "QS" ? param(tfs, "QS") : cell(tfs, (startswith(c, "re") || startswith(c, "mu")) ? "LAT\$END" : "LAT\$START", c)
        v != 0 || error("run $(run.id): load-bearing column $(c) printed 0 (PTC's silent-zero trap)")
    end
    beta0_h = param(tfs, "PC") / param(tfs, "ENERGY")
    mass_h = param(tfs, "MASS")
    res = abs(beta0_h - BENCH_BETA0_PIN)
    println(@sprintf("PTC-BEAM %s beta0_header %.17g pin %.17g residual %.17g mass_header %.17g %s",
                     run.id, beta0_h, BENCH_BETA0_PIN, res, mass_h, res <= BENCH_BETA0_ATOL ? "PASS" : "FAIL"))
    res <= BENCH_BETA0_ATOL || error("run $(run.id): beta0 header $(beta0_h) misses the pin by $(res)")
    abs(mass_h - parse(Float64, BENCH_MASS_GEV_STRING)) <= 1e-15 ||
        error("run $(run.id): MASS header $(mass_h) is not $(BENCH_MASS_GEV_STRING); particle= would silently override mass=")
    return nothing
end

"The one-turn RE at LAT\$END, as printed."
re_matrix(tfs) = [cell(tfs, "LAT\$END", "re$(i)$(j)") for i in 1:6, j in 1:6]

# ---------------------------------------------------------------- witnesses (the stage 8 B0 set)
# PTC's cavity kick is evaluated at PTC's OWN proton mass: MAD-X 5.03.06 snaps
# any deck mass within ~1e-4 of it to PTC_INTERNAL_PROTON_MASS_GEV (measured
# 2026-09-15: mass=0.9383 and 0.93837 print the bit-identical RE65, mass=0.95
# is honored and matches the formula to 17 digits). The header PC/ENERGY still
# report the deck beam. PTC_INTERNAL_PROTON_MASS_GEV, PTC_BETA0 and PTC_GAMMA0
# come from the shared module (stage 8 decision D19 item 1); the gated W1 lines use them
# and the header-beta0 line is recorded.

const FAILED_WITNESSES = String[]   # every gated witness that missed, by name (review B2 form/physics: the header names them)
witness_line(name, value, expected, tol; gated=true) = begin
    d = abs(value - expected)
    ok = d <= tol
    tag = gated ? "TW-PTC-WITNESS" : "TW-PTC-RECORDED-WITNESS"
    println(@sprintf("%s %s %.17g %.17g %.17g %s", tag, name, value, expected, d, gated ? (ok ? "PASS" : "FAIL") : "recorded"))
    gated && !ok && push!(FAILED_WITNESSES, name)
    return ok
end

"S0 and W1 witnesses; returns (all_pass, lines) where lines are the header sentences."
function run_witnesses(tfs::Dict{String,Any})
    ok = true
    RE_S0 = re_matrix(tfs["S0"])
    ok &= witness_line("S0_RE56_zero", RE_S0[5, 6], 0.0, 1e-12)
    RE_pt = re_matrix(tfs["S0_pt"])
    exp12 = S0_LENGTH / (1 + PT_WITNESS)
    ok &= witness_line("S0_RE12_at_pt_1e-3_is_L_over_1+delta", RE_pt[1, 2], exp12, 1e-12 * exp12)
    RE_W1 = re_matrix(tfs["W1"])
    k = 2pi * RF_FREQUENCY_HZ / CLIGHT
    beta0_h = param(tfs["W1"], "PC") / param(tfs["W1"], "ENERGY")
    abs(param(tfs["W1"], "ENERGY") * 1e9 - BENCH_E_TOTAL_EV) <= 1e-12 * BENCH_E_TOTAL_EV ||
        error("W1 header ENERGY $(param(tfs["W1"], "ENERGY")) GeV is not the fixture beam $(BENCH_E_TOTAL_EV) eV")
    flipped = (FLIP * RE_W1 * FLIP)[6, 5]
    # stage 8 decision D19 item 2: the three gated lines at PTC's effective beam; the abort flag keys on the first
    formula_ptc = RF_STRENGTH * k / PTC_BETA0^2
    w1 = witness_line("W1_RE65_flipped_vs_strength_k_over_PTC_BETA0^2", flipped, formula_ptc, 1e-10)
    twin_M65 = bare_map(W1(; cavity_beta0=PTC_BETA0, cavity_gamma0=PTC_GAMMA0))[6, 5]
    ok &= witness_line("W1_RE65_flipped_vs_Octopus_bare_twin_M65_at_PTC_beam", flipped, twin_M65, 1e-10)
    ok &= witness_line("W1_Octopus_twin_M65_vs_formula_at_PTC_BETA0", twin_M65, formula_ptc, 1e-10)
    # recorded, not gated: the same identity at the HEADER beta0 misses by 3.467e-10, the PTC internal-mass effect
    witness_line("W1_RE65_flipped_vs_formula_at_header_beta0_PTC_internal_mass_effect", flipped,
                 RF_STRENGTH * k / beta0_h^2, 1e-10; gated=false)
    println(@sprintf("PTC-EFFECTIVE-BEAM mass_GeV %.17g beta0_ptc %.17g gamma0_ptc %.17g beta0_header %.17g header_minus_ptc %.17g derivation_residual %.17g",
                     PTC_INTERNAL_PROTON_MASS_GEV, PTC_BETA0, PTC_GAMMA0, beta0_h, beta0_h - PTC_BETA0, PTC_BETA0_RESIDUAL))
    ok &= w1
    return (ok, w1)
end

"Symplectic residual of RE as printed and after F (the 6D rows; after F must be <= 1e-12)."
function symplectic_witness(id, RE)
    before = symplectic_residual(RE)
    after = symplectic_residual(FLIP * RE * FLIP)
    println(@sprintf("TW-PTC-WITNESS %s_symplectic_before_F %.17g %.17g %.17g recorded", id, before, 0.0, before))
    return witness_line("$(id)_symplectic_after_F", after, 0.0, 1e-12)
end

# ---------------------------------------------------------------- the method=2 orbit-artifact ladder (D4, printed)
const LADDER = [(2, 1), (2, 10), (2, 40), (2, 160), (6, 10)]

function orbit_ladder()
    xs = Float64[]
    ns = Float64[]
    for (method, nst) in LADDER
        layout = "ptc_create_layout, model=1, method=$(method), nst=$(nst), exact=true, time=false;"
        r = Run("ladder_m$(method)_n$(nst)", "ladder", dba_lattice(0.0), "icase=5, no=1, closed_orbit=true, rmatrix",
                5, 0.0, 0.0, 5.25, vcat(NZ_4D, ["disp1"]), layout)
        tfs = run_madx(r)
        x = param(tfs, "ORBIT_X")
        println(@sprintf("TW-PTC-MODEL U2_orbit_artifact method=%d nst=%d ORBIT_X %.17g ORBIT_PT %.17g DISP1 %.17g Q1 %.17g",
                         method, nst, x, param(tfs, "ORBIT_PT"), cell(tfs, "LAT\$START", "disp1"), param(tfs, "Q1")))
        if method == 2
            push!(xs, log(abs(x)))
            push!(ns, log(nst))
        end
    end
    A = hcat(ones(length(ns)), ns)
    slope = (A \ xs)[2]
    ok = abs(-slope - 2.0) <= 0.2
    println(@sprintf("TW-PTC-ORDER U2_orbit_artifact_method2 %.17g 2.0+-0.2 %s", -slope, ok ? "PASS" : "FAIL"))
    return -slope
end

# ---------------------------------------------------------------- the table
const META_COLS = ["id", "layer", "icase", "method", "nst", "volt_MV", "freq_MHz", "lag", "C", "beta0_header", "gamma0_header"]
const PARAM_COLS = ["ALPHA_C", "ETA_C", "Q1", "Q2", "QS", "ORBIT_X", "ORBIT_PX", "ORBIT_Y", "ORBIT_PY", "ORBIT_PT"]
const START_COLS = uppercase.(filter(c -> !startswith(c, "mu"), OPTICS_COLUMNS))   # periodic optics at LAT$START
const END_COLS = vcat(["MU1", "MU2", "MU3"], uppercase.(RE_COLUMNS))                # cumulative at LAT$END
const COLNAMES = vcat(META_COLS, PARAM_COLS, START_COLS .* "_start", END_COLS .* "_end")

function table_row(run::Run, tfs)
    beta0_h = param(tfs, "PC") / param(tfs, "ENERGY")
    gamma0_h = param(tfs, "ENERGY") / param(tfs, "MASS")
    meta = Any[run.id, run.layer, run.icase, 6, 10, run.volt_MV, run.freq_MHz, run.volt_MV == 0 ? 0.0 : LAG, run.C, beta0_h, gamma0_h]
    return vcat(meta, [param(tfs, p) for p in PARAM_COLS],
                [cell(tfs, "LAT\$START", c) for c in START_COLS],
                [cell(tfs, "LAT\$END", c) for c in END_COLS])
end

function header_lines(version, w1_ok, ladder_order)
    return [
        "PTC ptc_twiss reference for the stage 8 benchmark B (validation/twiss_ptc_benchmark.jl reads it; theory 12.2 item 3, PTC half)",
        "generator: validation/generate_ptc_twiss_reference.jl; regenerate with OCTOPUS_STAGE8_REGENERATE=1 to diff cell by cell",
        "tool: MAD-X $(version) (PTC as distributed with it), /usr/local/bin/madx",
        "flags: ptc_create_layout, model=1, method=6, nst=10, exact=true, time=false (stage 8 decision D4; validation/generate_ptc_reference.jl keeps method=2)",
        "method=2 orbit-artifact ladder on U2 (icase=5): ORBIT_X ~ nst^-order with fitted order $(g17(ladder_order)) at nst = 1, 10, 40, 160; method=6 nst=10 removes it (see the generator log)",
        "5D rows: ptc_twiss, icase=5, no=1, closed_orbit=true, rmatrix (U1, U2, K2); RE55 prints 0 at icase=5 and row 5 of RE is not trustworthy there (p2 open question 2)",
        "6D rows: ptc_twiss, icase=6, no=1, closed_orbit=true, rmatrix (B4, B4K at 60 MV 400 MHz; G6 at 2.0 and 0.2 MV, h=12), lag=0.5 (the stable phase with time=false)",
        "witness rows: S0 (drift 10 m) and S0_pt (pt=1e-3 initial condition) and W1 (lone cavity 60 MV 400 MHz lag=0.5 followed by a 0.2 m drift), icase=6, closed_orbit=false, betx=bety=betz=1",
        "beam: $(BENCH_MADX_BEAM) beta0 = $(g17(BENCH_BETA0_PIN)) gamma0 = $(g17(BENCH_GAMMA0_PIN)) (stage 8 decision D13; beta0_header = PC/ENERGY of each TFS header, asserted to 1e-12)",
        "PTC-effective beam (stage 8 decision D19): PTC evaluates the cavity kick at its internal proton mass $(g17(PTC_INTERNAL_PROTON_MASS_GEV)) GeV whatever the deck mass says (measured 2026-09-15 on the W1 kick); beta0_ptc = $(g17(PTC_BETA0)), gamma0_ptc = $(g17(PTC_GAMMA0)) (derived from E_total 3.0 GeV); with time=false only the cavity rows see it",
        "twin rule: the Octopus twins of the cavity rows (W1, B4, B4K, G6_2.0MV, G6_0.2MV) are compiled with cavity_beta0 = beta0_ptc, cavity_gamma0 = gamma0_ptc (the like-for-like beam PTC ran); the header beam above is the deck's and the D13 pin",
        "coordinates: (X,PX,Y,PY,T,PT) with coordinate 6 = delta = dp/p0; RE rows in the ptc_track T orientation (row 5 = +path-length excess); optics columns *_start are the periodic values at LAT\$START, *_end are cumulative at LAT\$END (RE = one-turn map, MU = tunes in units of 2 pi)",
        "conversion the reader applies: the table is AS PRINTED (stage 8 decision D7); M_oct = F RE F with F = diag(1,1,1,1,-1,1), J0 = I, no shear (the stage 8 conversion law; partner of the Octopus BARE compile)",
        "W1 witness (the stage 8 B0 witness amended by decision D19) at PTC's effective beam: $(w1_ok ? "PASS; the 6D rows B4, B4K, G6_2.0MV, G6_0.2MV are in this table from a fresh freeze" : "FAIL; the 6D rows (B4, B4K, G6_2.0MV, G6_0.2MV) were ABORTED from this table"); the formula at the header beta0 misses by 3.467e-10 and is recorded, not gated; gated witnesses that missed: $(isempty(FAILED_WITNESSES) ? "none" : join(FAILED_WITNESSES, ", "))",
        "BETA_jk index order (stage 8 layer B3, decided in-run by the consumer on the coupled rows): j = plane, k = mode, i.e. BETA_jk = Octopus physical.beta[mode k, plane j]; the (mode, plane) reading misses by 2.4808469094089958 on B4K and 4.7146912630910229 on K2 (consumer run 2026-09-15). ALFA33 is printed in PTC's T orientation (odd under F); the consumer flips the sign of the Octopus mode-3 alpha",
        "columns: $(length(COLNAMES)); data at %.17g; one row per run",
    ]
end

function main()
    version = madx_version()
    println("PTC-VERSION $(version)")
    committed = joinpath(OUTDIR, "ptc_twiss_madx_$(version).tsv")
    startswith(basename(committed), "ptc_madx_") && error("the table name must not start with ptc_madx_")
    tfs = Dict{String,Any}()
    rows = Any[]
    aborted = Any[]
    w1_ok = true
    gated_ok = true
    for run in RUNS
        if run.layer == "6d" && !w1_ok
            println("TW-PTC-ABORT $(run.id): the W1 witness missed; the run is executed for the record only")
        end
        t = run_madx(run)
        tfs[run.id] = t
        if run.layer == "witness" && run.id == "W1"
            all_ok, w1_ok = run_witnesses(tfs)   # w1_ok = the first gated W1 line (the 6D abort key, D19 (2)); all_ok accumulates every gated witness
            gated_ok &= all_ok
        end
        run.layer == "6d" && (gated_ok &= symplectic_witness(run.id, re_matrix(t)))
        println(@sprintf("PTC-ROW %s Q1 %.17g Q2 %.17g QS %.17g BETA11 %.17g BETA22 %.17g BETA33 %.17g DISP1 %.17g ORBIT_X %.17g ORBIT_PT %.17g",
                         run.id, param(t, "Q1"), param(t, "Q2"), param(t, "QS"), cell(t, "LAT\$START", "beta11"),
                         cell(t, "LAT\$START", "beta22"), cell(t, "LAT\$START", "beta33"), cell(t, "LAT\$START", "disp1"),
                         param(t, "ORBIT_X"), param(t, "ORBIT_PT")))
        push!(run.layer == "6d" && !w1_ok ? aborted : rows, table_row(run, t))
    end
    order = orbit_ladder()
    hdr = header_lines(version, w1_ok, order)
    target = REGENERATE ? joinpath(WORKDIR, "regenerated_" * basename(committed)) : committed
    write_reference_table(target, hdr, COLNAMES, rows)
    println("PTC-TABLE $(target) rows=$(length(rows)) columns=$(length(COLNAMES))")
    if !isempty(aborted)
        scratch = joinpath(WORKDIR, "ptc_twiss_6d_aborted_$(version).tsv")
        write_reference_table(scratch, vcat(hdr, ["ABORTED 6D ROWS: not part of the committed table"]), COLNAMES, aborted)
        println("PTC-TABLE-ABORTED $(scratch) rows=$(length(aborted))")
    end
    if REGENERATE
        a = read_reference_table(committed)
        b = read_reference_table(target)
        ndiff = 0
        # the header block is compared line by line before the cells (a flag, beam or conversion change must show)
        for i in 1:max(length(a.header), length(b.header))
            ha = i <= length(a.header) ? a.header[i] : "<missing>"; hb = i <= length(b.header) ? b.header[i] : "<missing>"
            ha == hb || (ndiff += 1; println("TW-PTC-REGEN header line $(i): committed $(ha) regenerated $(hb)"))
        end
        a.colnames == b.colnames || (ndiff += 1; println("TW-PTC-REGEN column rows differ"))
        for c in a.colnames, i in 1:max(length(a.columns[c]), length(get(b.columns, c, String[])))
            va = i <= length(a.columns[c]) ? a.columns[c][i] : "<missing>"
            vb = haskey(b.columns, c) && i <= length(b.columns[c]) ? b.columns[c][i] : "<missing>"
            va == vb || (ndiff += 1; println("TW-PTC-REGEN row $(i) column $(c): committed $(va) regenerated $(vb)"))
        end
        println("TW-PTC-REGEN-DIGEST header_lines=$(length(a.header)) cells=$(length(a.colnames) * length(a.columns[first(a.colnames)])) differing=$(ndiff) $(ndiff == 0 ? "PASS" : "FAIL")")
        ndiff == 0 || error("regenerate mode: $(ndiff) cells differ from $(committed)")
    end
    w1_ok || error("the W1 witness missed at PTC's effective beam: the 6D rows were aborted (see TW-PTC-WITNESS lines)")
    # every other gated witness (S0 lines, the 2nd/3rd W1 line, the 6D after-F symplectic residuals) stops the freeze too,
    # AFTER the table is written so the failing state can be inspected (review B2 physics, minor 4)
    gated_ok || error("gated witness(es) missed: $(join(FAILED_WITNESSES, ", ")); the written table carries the FAIL in its header")
    return nothing
end

main()
