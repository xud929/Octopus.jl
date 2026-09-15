"""
Shared fixture module of the stage 8 external twiss benchmarks
(MAD-X twiss, PTC ptc_twiss, Xsuite twiss).

Purpose
-------
Every element number of the benchmark fixtures lives here once, copied from
the identity contract recipes (src/contracts/twiss_dispersion_identity.jl
228-309) and validation/lattice_cells.jl 70-113, together with the beam pin,
the stage 8 coordinate conversion law (history section, benchmark A), the two Octopus compile
modes, and the table reader/writer every benchmark shares. Nothing here
compares anything: the consumers own the comparisons.

Consumers (each `include`s this file relative to itself, like
validation/twiss_dispersion_identities.jl includes its neighbours):
    validation/twiss_madx_benchmark.jl      validation/generate_madx_twiss_reference.jl
    validation/twiss_ptc_benchmark.jl       validation/generate_ptc_twiss_reference.jl
    validation/twiss_xsuite_benchmark.jl    (generate_xsuite_twiss_reference.py reads the constants by eye)
and `write_benchmark_maps` writes validation/reference/twiss_benchmark_maps.tsv.

Beam pin (stage 8 decision D13, history section)
----------------------
Protons at 3.0 GeV TOTAL energy with the Octopus mass PMASS_EV =
938.27208943e6 eV: `reference_beta_gamma(3.0e9, PMASS_EV)` =
(0.9498330546994187, 3.1973667700405533), p0c = 2.8494991640982566e9 eV.
MAD-X and PTC decks carry exactly `beam, mass=0.93827208943, charge=1,
energy=3.0;` (NO `particle=`: with it MAD-X 5.03.06 silently ignores mass=),
xtrack `xt.Particles(mass0=938.27208943e6, p0c=2.8494991640982566e9)`.
Every driver asserts |beta0_header - BENCH_BETA0_PIN| <= 1e-12.

Conversion law (the stage 8 law, history section of benchmark A, adopted verbatim)
----------------------------------------------------
    M_oct = Sh(-C/gamma0^2) . J0 . F . M_ext . F^-1 . J0^-1
with Sh(u) the identity except entry (5,6) = u, C the cell length and
    MAD-X   J0 = diag(1,1,1,1,beta0,1/beta0)   F = I                    u = -C/gamma0^2
    Xsuite  J0 = I                             F = I                    u = -C/gamma0^2
    PTC tf  J0 = I                             F = diag(1,1,1,1,-1,1)   u = 0
This is the map of the BARE compile (target=:bare). For the TASK-compiled
line (target=:task) the shear is omitted for MAD-X and Xsuite (both carry
+C/gamma0^2 already) and Sh(+C/gamma0^2) is applied to PTC time=false.
The law is a left shear, not a similarity: the no-slip and the slip machine
are different dynamical systems (section 3, the note beside the law).

Compile modes (measured 2026-09-15 on the Octopus tree, history section)
-----------------------------------------------
`bare_map(cell)`: the Tuple of `compile_runtime` maps folded by
`one_turn_matrix` at the origin; no velocity slip anywhere, a drift has
(5,6) = 0 exactly. `task_map(cell)`: the same specs compiled through
`Octopus._physics_line(Octopus._runtime_entries(TrackingTask(specs)))`;
the survey-bound RF cavity then adds z += ds_turn * g(delta) before its
kick, so the one-turn (5,6) gains exactly +C/gamma0^2 and nothing else
moves. The slip needs a cavity of NONZERO strength in the line
(rf_cavity.jl:139 short-circuits a zero strength; a task-compiled drift
alone gives 0), so `task_map` of a cavity-free cell appends a marker cavity
of strength TASK_MARKER_STRENGTH = 1e-30 (its own M65 is ~1e-29).

Numbers are printed with %.17g everywhere. Nothing here runs Pkg.
"""

if !isdefined(Main, :Octopus)
    include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
end
using .Octopus
using LinearAlgebra
using Printf
using Random

# ---------------------------------------------------------------- beam pin
const BENCH_E_TOTAL_EV = 3.0e9
const BENCH_MASS_EV = PMASS_EV                       # 938.27208943e6
const BENCH_MASS_GEV_STRING = "0.93827208943"        # the deck literal
const BENCH_BETA0, BENCH_GAMMA0 = reference_beta_gamma(BENCH_E_TOTAL_EV, BENCH_MASS_EV)
const BENCH_P0C_EV = BENCH_BETA0 * BENCH_E_TOTAL_EV  # 2.8494991640982566e9
const BENCH_BETA0_PIN = 0.9498330546994187
const BENCH_GAMMA0_PIN = 3.1973667700405533
const BENCH_BETA0_ATOL = 1e-12
abs(BENCH_BETA0 - BENCH_BETA0_PIN) <= BENCH_BETA0_ATOL ||
    error("beam pin: reference_beta_gamma gives beta0 = $(BENCH_BETA0), pin $(BENCH_BETA0_PIN)")
const BENCH_MADX_BEAM = "beam, mass=$(BENCH_MASS_GEV_STRING), charge=1, energy=3.0;"
const BENCH_XTRACK_PARTICLES = "xt.Particles(mass0=938.27208943e6, p0c=2.8494991640982566e9)"

# PTC's EFFECTIVE beam (stage 8 decision D19, history section of benchmark B). PTC 5.03.06 evaluates the cavity kick at
# its INTERNAL proton mass whatever the deck's beam mass says (measured
# 2026-09-15: deck masses 0.93827208943, 0.9383 and 0.93837 all print the W1
# RE65 = -0.185846588444706 bit-identically; 0.95 is honored), while the TFS
# header still prints the deck beam. The like-for-like Octopus twin of every
# PTC row WITH A CAVITY (W1, B4, B4K, G6) is compiled with its cavity at this
# beam through the cavity_beta0 / cavity_gamma0 keywords below. Derived, never
# a pinned digit; the assert only guards the derivation.
const PTC_INTERNAL_PROTON_MASS_GEV = 0.938272081358
const PTC_BETA0, PTC_GAMMA0 = reference_beta_gamma(BENCH_E_TOTAL_EV, PTC_INTERNAL_PROTON_MASS_GEV * 1e9)
const PTC_BETA0_PIN = 0.94983305558539122
const PTC_BETA0_RESIDUAL = abs(PTC_BETA0 - PTC_BETA0_PIN)
PTC_BETA0_RESIDUAL <= BENCH_BETA0_ATOL ||
    error("PTC effective beam: reference_beta_gamma gives beta0 = $(PTC_BETA0), expected $(PTC_BETA0_PIN)")

"The velocity-slip constant C/gamma0^2 of a cell of length C at the pinned beam."
slip(C; gamma0=BENCH_GAMMA0) = C / gamma0^2

# Cell element numbers (once). Quadrupole kn[2] is K1 in 1/m^2.
const RF_FREQUENCY_HZ = 400.0e6
const RF_STRENGTH = 0.02             # qV/(P0 c); V = 0.02 * p0c = 56.989983281965137 MV
const CRAB_STRENGTH = 0.05           # linear crab coefficient d(px)/dz in 1/m
const TASK_MARKER_STRENGTH = 1e-30   # marker cavity of task_map on cavity-free cells
const G6_CELLS = 6
const G6_HARMONIC = 12
const G6_VOLT_EV = 2.0e6             # the PTC ring6 twin's 2.0 MV (0.2 MV is the second ladder point)
const DEFAULT_NST = 64
const DEFAULT_ORDER = 4

# ---------------------------------------------------------------- specs
# Every builder below returns a Tuple of element SPECS in tracking order;
# `compile_cell` turns it into the Tuple of compiled runtime maps the
# consumers pass to `analyze` / `one_turn_matrix`, and remembers the specs
# so `task_map` can recompile the same numbers through a TrackingTask.
const _SPECS_OF_CELL = IdDict{Any,Tuple}()

_quad(L, k1; nst, order, tilt=0.0) =
    QuadrupoleSpec(L=L, kn=(0.0, k1), nst=nst, integrator_order=order, tilt=tilt)
_drift(L) = DriftSpec(L=L)
_bend(L, angle; nst, order) =
    SBendSpec(L=L, h=angle / L, b0=angle / L, nst=nst, integrator_order=order)
_rf(strength; frequency=RF_FREQUENCY_HZ, cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0) =
    ThinRFCavitySpec(frequency; strength=strength, beta0=cavity_beta0, gamma0=cavity_gamma0)
_crab(strength) = ThinCrabCavitySpec{1}(RF_FREQUENCY_HZ; strengthX=(-Float64(strength),))

"S0: the bare 10 m drift (the conversion witness of every code)."
specs_S0(; kw...) = (_drift(10.0),)
"U1: the F3 detuned FODO, qf 1.6, qd -1.6016 (detune 1e-3), drifts 1.2; C = 3.0."
specs_U1(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER) =
    (_quad(0.3, 1.6; nst, order=integrator_order), _drift(1.2),
     _quad(0.3, -1.6 * (1 + 1e-3); nst, order=integrator_order), _drift(1.2))
"U2: the F1 DBA cell (qd, d, bend, d, qf, d, bend, d, qd); C = 5.25. `qf_tilt` makes K2."
function specs_U2(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER, qf_tilt=0.0)
    o = integrator_order
    bend = _bend(1.0, 0.2; nst, order=o)
    qf = _quad(0.35, 1.5; nst, order=o, tilt=qf_tilt)
    qd = _quad(0.25, -1.1; nst, order=o)
    d = _drift(0.6)
    return (qd, d, bend, d, qf, d, bend, d, qd)
end
"K1: coupled FODO qf(0.2,+1) dr(1) qd(0.2,-1,tilt) dr(1); C = 2.4. Default tilt 0.05."
specs_K1(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER, tilt=0.05) =
    (_quad(0.2, 1.0; nst, order=integrator_order), _drift(1.0),
     _quad(0.2, -1.0; nst, order=integrator_order, tilt=tilt), _drift(1.0))
"K2: U2 with the qf tilted (default 0.05; stage 8 fallback 0.02); C = 5.25."
specs_K2(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER, tilt=0.05) =
    specs_U2(; nst, integrator_order, qf_tilt=tilt)
"R(theta): the rolled equal-tune FODO, both quads tilted by theta; kd = -1.0 exact, Rd detunes it."
specs_rolled_fodo(theta; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER, kd=-1.0) =
    (_quad(0.2, 1.0; nst, order=integrator_order, tilt=theta), _drift(1.0),
     _quad(0.2, kd; nst, order=integrator_order, tilt=theta), _drift(1.0))
"W1: the lone 400 MHz cavity, strength 0.02, at the pinned beam (cavity_beta0/cavity_gamma0 move it, D19); C = 0."
specs_W1(; cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0, kw...) =
    (_rf(RF_STRENGTH; cavity_beta0, cavity_gamma0),)
"W2: the lone quadrupole L=0.2, K1=1, tilt=pi/4; C = 0.2."
specs_W2(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER) =
    (_quad(0.2, 1.0; nst, order=integrator_order, tilt=pi / 4),)
"B4: the F4 recipe, U2 + cavity (+0.02) LAST; bare compile is the benchmark; C = 5.25. rf_strength is for the consumers' injected defects only."
specs_B4(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER, rf_strength=RF_STRENGTH,
         cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0) =
    (specs_U2(; nst, integrator_order)..., _rf(rf_strength; cavity_beta0, cavity_gamma0))
"B4K: K2 + cavity, bare; C = 5.25. rf_strength is for the consumers' injected defects only."
specs_B4K(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER, tilt=0.05, rf_strength=RF_STRENGTH,
          cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0) =
    (specs_K2(; nst, integrator_order, tilt)..., _rf(rf_strength; cavity_beta0, cavity_gamma0))
"G6 cavity frequency h beta0 c / C with C = 6 * 5.25 = 31.5 m, h = 12."
const G6_LENGTH = G6_CELLS * 5.25
const G6_FREQUENCY_HZ = G6_HARMONIC * BENCH_BETA0 * CLIGHT / G6_LENGTH   # 1.0847725186970942e8
"""
G6 strength at V volts: V / E_total = 0.00066666666666666664 at 2.0 MV (stage 8 decision D19 item 3;
the decision's string 6.6666666666666670e-04 is 1 ulp off the computed double).
The same law as W1's volt = RF_STRENGTH * E_total (the stage 8 W1 witness): PTC's kick law
gives M65 = (qV/p0c) k / beta0 and Octopus's is strength * k / beta0^2, so
strength = qV/(p0c) * beta0 = V / E_total, NOT V / p0c.
"""
g6_strength(volt_eV=G6_VOLT_EV) = volt_eV / BENCH_E_TOTAL_EV
"G6: six U2 cells plus the ring cavity LAST, bare compile (the 6D partnership with PTC time=false)."
function specs_G6(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER, volt_eV=G6_VOLT_EV,
                  cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0)
    cell = specs_U2(; nst, integrator_order)
    ring = Tuple(Iterators.flatten(ntuple(_ -> cell, G6_CELLS)))
    return (ring..., _rf(g6_strength(volt_eV); frequency=G6_FREQUENCY_HZ, cavity_beta0, cavity_gamma0))
end
"T6: U2 + the FLIPPED cavity (strength -0.02), meant for the TASK compile (the xtrack 6D twin)."
specs_T6(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER) =
    (specs_U2(; nst, integrator_order)..., _rf(-RF_STRENGTH))
"B5: the F5 recipe, B4 + crab strengthX = -0.05 (px += 0.05 z, pz += 0.05 x), bare."
specs_B5(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER) =
    (specs_B4(; nst, integrator_order)..., _crab(CRAB_STRENGTH))

_is_thin(s) = s isa ElementSpec{:thin_rf_cavity} || s isa ElementSpec{:thin_crab_cavity}
"""
Cell length C in metres of a specs Tuple (thin elements contribute 0), rounded
to 12 decimals so that 0.2 + 1.0 + 0.2 + 1.0 prints as 2.4 and six DBA cells
as 31.5 (the decks state these lengths exactly).
"""
function cell_length(cell::Tuple)
    specs = all(s -> s isa ElementSpec, cell) ? cell : cell_specs(cell)
    C = 0.0
    for s in specs
        _is_thin(s) && continue
        C += Float64(s.L)
    end
    return round(C; digits=12)
end

"Compile a specs Tuple bare and remember the specs for `task_map`."
function compile_cell(specs::Tuple)
    cell = Tuple(compile_runtime(s) for s in specs)
    _SPECS_OF_CELL[cell] = specs
    return cell
end

# ---------------------------------------------------------------- cell builders
# One builder per stage 8 fixture id (the fixture table of the history section), returning the Tuple of compiled
# runtime maps (bare compile). Keywords: nst (default 64), integrator_order
# (default 4), plus the fixture's own knobs named in its specs_* docstring.
S0(; kw...) = compile_cell(specs_S0(; kw...))
U1(; kw...) = compile_cell(specs_U1(; kw...))
U2(; kw...) = compile_cell(specs_U2(; kw...))
K1(; kw...) = compile_cell(specs_K1(; kw...))
K2(; kw...) = compile_cell(specs_K2(; kw...))
rolled_fodo(theta; kw...) = compile_cell(specs_rolled_fodo(theta; kw...))
"Rd: R(pi/4) with kd = -(1 + eps), eps in {1e-3, 1e-6} (stage 8 fixture table)."
Rd(eps; theta=pi / 4, kw...) = compile_cell(specs_rolled_fodo(theta; kd=-(1.0 + eps), kw...))
# W1, B4, B4K, G6 take cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0 (D19:
# the PTC consumer passes PTC_BETA0, PTC_GAMMA0); the defaults keep the maps table rows.
W1(; cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0, kw...) =
    compile_cell(specs_W1(; cavity_beta0, cavity_gamma0, kw...))
W2(; kw...) = compile_cell(specs_W2(; kw...))
B4(; cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0, kw...) =
    compile_cell(specs_B4(; cavity_beta0, cavity_gamma0, kw...))
B4K(; cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0, kw...) =
    compile_cell(specs_B4K(; cavity_beta0, cavity_gamma0, kw...))
G6(; cavity_beta0=BENCH_BETA0, cavity_gamma0=BENCH_GAMMA0, kw...) =
    compile_cell(specs_G6(; cavity_beta0, cavity_gamma0, kw...))
T6(; kw...) = compile_cell(specs_T6(; kw...))
B5(; kw...) = compile_cell(specs_B5(; kw...))

"The specs a compiled cell was built from (registered by `compile_cell`)."
function cell_specs(cell::Tuple)
    haskey(_SPECS_OF_CELL, cell) ||
        error("cell_specs: this Tuple was not built by compile_cell; pass the specs Tuple to task_map instead")
    return _SPECS_OF_CELL[cell]
end

# ---------------------------------------------------------------- compile modes
"The 6x6 one-turn matrix at the origin of the BARE compile (no velocity slip)."
bare_map(cell::Tuple) = one_turn_matrix(cell; point=ntuple(_ -> 0.0, 6)).matrix

_has_cavity(specs::Tuple) = any(s -> s isa ElementSpec{:thin_rf_cavity}, specs)

"""
The 6x6 one-turn matrix at the origin of the TASK compile: the same specs
through `TrackingTask`, whose survey binding gives the cavity ds_turn = C and
the velocity slip z += ds_turn g(delta), i.e. (5,6) += C/gamma0^2. A cell
without a cavity gets the marker cavity (strength TASK_MARKER_STRENGTH)
appended, because a zero-strength cavity is bypassed and a task-compiled
drift alone carries no slip (p4 S2). Accepts the compiled cell or its specs.
"""
function task_map(cell::Tuple; marker_strength=TASK_MARKER_STRENGTH)
    specs = all(s -> s isa ElementSpec, cell) ? cell : cell_specs(cell)
    if !_has_cavity(specs)
        specs = (specs..., _rf(marker_strength))
    end
    line = Octopus._physics_line(Octopus._runtime_entries(TrackingTask(specs)))
    return one_turn_matrix(line; point=ntuple(_ -> 0.0, 6)).matrix
end

# ---------------------------------------------------------------- linear algebra helpers
"kron(I_n, [0 1; -1 0]): the symplectic form of validation/lattice_cells.jl (S6)."
symplectic_form(d::Integer) = kron(Matrix{Float64}(I, d ÷ 2, d ÷ 2), [0.0 1.0; -1.0 0.0])
"max |M' S M - S| over the entries."
function symplectic_residual(M::AbstractMatrix)
    S = symplectic_form(size(M, 1))
    return maximum(abs, transpose(M) * S * M - S)
end
"The six (or four) |eigenvalue| sorted descending."
eigen_moduli(M::AbstractMatrix) = sort(abs.(eigvals(Matrix{Float64}(M))); rev=true)
"Eigenvalue angles / 2pi in (-1/2, 1/2], one per conjugate pair (positive member), sorted by |angle|."
function eigen_tunes(M::AbstractMatrix)
    lam = eigvals(Matrix{Float64}(M))
    phi = [angle(l) / (2pi) for l in lam if imag(l) >= 0]
    return sort(phi; by=abs)
end
"true when every |eigenvalue| is within `tol` of 1."
is_stable(M::AbstractMatrix; tol=1e-9) = maximum(abs, eigen_moduli(M) .- 1) <= tol

# ---------------------------------------------------------------- conversion law (stage 8, history section of benchmark A)
"Sh(u): the identity except entry (5,6) = u."
function shear(u::Real)
    S = Matrix{Float64}(I, 6, 6)
    S[5, 6] = Float64(u)
    return S
end
"F = diag(1,1,1,1,-1,1): PTC's T (time=false) is -z; applied as F M F^-1 = F M F."
const FLIP = Matrix{Float64}(Diagonal([1.0, 1.0, 1.0, 1.0, -1.0, 1.0]))
"J0(beta0) = diag(1,1,1,1,beta0,1/beta0): MAD-X (T,PT) -> Octopus (z,delta) at s = 0."
J0(beta0::Real) = Matrix{Float64}(Diagonal([1.0, 1.0, 1.0, 1.0, Float64(beta0), 1.0 / Float64(beta0)]))
"1/J0: the diagonal inverse taken entry by entry (no general inverse)."
J0_inverse(beta0::Real) = Matrix{Float64}(Diagonal([1.0, 1.0, 1.0, 1.0, 1.0 / Float64(beta0), Float64(beta0)]))

const CONVERT_CODES = (:madx, :ptc, :xsuite)

"""
    convert_map(code, M_ext; beta0, gamma0, C, target=:bare) -> Matrix

The section 3 law M_oct = Sh(u) J0 F M_ext F^-1 J0^-1 for `code` in
(:madx, :ptc, :xsuite). `target=:bare` (the default) gives the map of the
bare Octopus compile: u = -C/gamma0^2 for MAD-X and Xsuite, 0 for PTC
time=false. `target=:task` gives the task-compiled line: u = 0 for MAD-X
and Xsuite (they carry the slip already), u = +C/gamma0^2 for PTC.
`beta0`, `gamma0`, `C` are the EXTERNAL header's own numbers (the stage 8 witness rule W).
"""
function convert_map(code::Symbol, M_ext::AbstractMatrix; beta0::Real, gamma0::Real, C::Real,
                     target::Symbol=:bare)
    code in CONVERT_CODES || error("convert_map: code must be one of $(CONVERT_CODES), got $(code)")
    target in (:bare, :task) || error("convert_map: target must be :bare or :task, got $(target)")
    size(M_ext) == (6, 6) || error("convert_map: a 6x6 matrix is required, got $(size(M_ext))")
    J = code === :madx ? J0(beta0) : Matrix{Float64}(I, 6, 6)
    Ji = code === :madx ? J0_inverse(beta0) : Matrix{Float64}(I, 6, 6)
    F = code === :ptc ? FLIP : Matrix{Float64}(I, 6, 6)
    s = Float64(C) / Float64(gamma0)^2
    u = if target === :bare
        code === :ptc ? 0.0 : -s
    else
        code === :ptc ? s : 0.0
    end
    return shear(u) * (J * (F * Matrix{Float64}(M_ext) * F) * Ji)
end

"""
The analytic one-turn map of the S0 drift as each external code prints it at
the beam (beta0, gamma0): (1,2) = (3,4) = L and (5,6) = +L/(beta0^2 gamma0^2)
for MAD-X, 0 for PTC time=false, +L/gamma0^2 for xtrack (the stage 8 convention
table, row "(5,6) of a bare L=10 drift").
"""
function analytic_drift_ext(code::Symbol, L::Real; beta0::Real=BENCH_BETA0, gamma0::Real=BENCH_GAMMA0)
    code in CONVERT_CODES || error("analytic_drift_ext: unknown code $(code)")
    M = Matrix{Float64}(I, 6, 6)
    M[1, 2] = L; M[3, 4] = L
    M[5, 6] = code === :madx ? L / (beta0^2 * gamma0^2) : code === :xsuite ? L / gamma0^2 : 0.0
    return M
end

# ---------------------------------------------------------------- dense matrix fixtures (D6/D8, F8)
const DENSE_SEED = UInt64(20260911)
const CONTRACT_DENSE_MAPS = 20      # the contract's dense_maps default (twiss_dispersion_identity.jl:213)
const CONTRACT_DENSE_MAPS_4D = 5    # dense_maps_4d default (:214)

"""
    dense_maps() -> Vector{NamedTuple}

The matrix-only fixtures: D6_1..3 = the first three F6a dense 6x6 draws, D8_1..3
= the first three F6b dense 4x4 draws, and F8 = the manufactured coasting map,
all from `MersenneTwister(20260911)` in the contract's own draw order (twenty
6x6 draws precede the 4x4 draws, twiss_dispersion_identity.jl:390-398), so the
numbers equal the suite's. The 4x4 maps are returned as given (`dim = 4`).
"""
function dense_maps()
    rng = MersenneTwister(DENSE_SEED)
    out = NamedTuple{(:id, :dim, :M),Tuple{String,Int,Matrix{Float64}}}[]
    for i in 1:CONTRACT_DENSE_MAPS
        M = Matrix{Float64}(Octopus._manufactured_symplectic_map(rng, 6; stable=true).M)
        i <= 3 && push!(out, (id="D6_$(i)", dim=6, M=M))
    end
    for i in 1:CONTRACT_DENSE_MAPS_4D
        M = Matrix{Float64}(Octopus._manufactured_symplectic_map(rng, 4; stable=true).M)
        i <= 3 && push!(out, (id="D8_$(i)", dim=4, M=M))
    end
    push!(out, (id="F8", dim=6, M=Matrix{Float64}(Octopus._identity_contract_coasting(DENSE_SEED).M)))
    return out
end

# ---------------------------------------------------------------- reference tables
"""
    read_reference_table(path) -> (header_lines, colnames, columns)

`header_lines` are the leading `#` lines (kept verbatim), `colnames` the
tab-separated column row, `columns` a Dict{String,Vector{String}} of the raw
cell strings (the caller parses: MAD-X and PTC print unknown columns as zeros,
so a numeric parse is never the load-bearing check).
"""
function read_reference_table(path::AbstractString)
    isfile(path) || error("read_reference_table: no such file $(path)")
    header = String[]
    colnames = String[]
    columns = Dict{String,Vector{String}}()
    for line in eachline(path)
        isempty(strip(line)) && continue
        if startswith(line, "#")
            isempty(colnames) || error("read_reference_table: a # line after the column row in $(path)")
            push!(header, line)
        elseif isempty(colnames)
            colnames = String.(split(line, '\t'))
            for c in colnames
                columns[c] = String[]
            end
        else
            cells = split(line, '\t')
            length(cells) == length(colnames) ||
                error("read_reference_table: row with $(length(cells)) cells, $(length(colnames)) columns in $(path)")
            for (c, v) in zip(colnames, cells)
                push!(columns[c], String(v))
            end
        end
    end
    isempty(colnames) && error("read_reference_table: no column row in $(path)")
    return (header=header, colnames=colnames, columns=columns)
end

"%.17g for a Float64, plain string otherwise."
_cell_string(x::AbstractFloat) = @sprintf("%.17g", x)
_cell_string(x::Integer) = string(x)
_cell_string(x::AbstractString) = String(x)

"""
    write_reference_table(path, header_lines, colnames, rows)

Writes `# `-prefixed header lines (given without the prefix), the tab-separated
column row and one row per element of `rows` (each an iterable of cells;
floats at %.17g), to `path * ".partial-<pid>"` first and `mv`s onto `path`
only after every row is written (validation/generate_ptc_reference.jl:376-415).
"""
function write_reference_table(path::AbstractString, header_lines, colnames, rows)
    mkpath(dirname(abspath(path)))
    tmp = path * ".partial-$(getpid())"
    ok = false
    try
        open(tmp, "w") do io
            for h in header_lines
                println(io, "# ", h)
            end
            println(io, join(colnames, '\t'))
            for r in rows
                cells = collect(r)
                length(cells) == length(colnames) ||
                    error("write_reference_table: row with $(length(cells)) cells, $(length(colnames)) columns")
                println(io, join((_cell_string(c) for c in cells), '\t'))
            end
        end
        ok = true
    finally
        if ok
            mv(tmp, path; force=true)
        else
            rm(tmp; force=true)
        end
    end
    return path
end

# ---------------------------------------------------------------- the fixture list and the maps table
const ROLLED_THETAS = ((id="R_0", theta=0.0), (id="R_0.01", theta=0.01), (id="R_0.1", theta=0.1),
                       (id="R_pi8", theta=pi / 8), (id="R_pi4", theta=pi / 4))
const RD_EPSILONS = ((id="Rd_1e-3", eps=1e-3), (id="Rd_1e-6", eps=1e-6))
const K_TILT = 0.05     # K1/K2/B4K tilt; stage 8 fallback 0.02 if K2 were unstable (it is not, see the report)

"""
    benchmark_fixtures(; nst=64, integrator_order=4) -> Vector{NamedTuple}

Every stage 8 lattice fixture as `(id, cell, C)` with the compiled
bare cell, in table order: S0, U1, U2, K1, K2, R_<theta>, Rd_<eps>, W1, W2,
B4, B4K, G6, T6, B5.
"""
function benchmark_fixtures(; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER)
    kw = (; nst, integrator_order)
    out = NamedTuple{(:id, :cell, :C),Tuple{String,Tuple,Float64}}[]
    add!(id, cell) = push!(out, (id=id, cell=cell, C=cell_length(cell)))
    add!("S0", S0(; kw...)); add!("U1", U1(; kw...)); add!("U2", U2(; kw...))
    add!("K1", K1(; tilt=K_TILT, kw...)); add!("K2", K2(; tilt=K_TILT, kw...))
    for r in ROLLED_THETAS
        add!(r.id, rolled_fodo(r.theta; kw...))
    end
    for r in RD_EPSILONS
        add!(r.id, Rd(r.eps; kw...))
    end
    add!("W1", W1(; kw...)); add!("W2", W2(; kw...))
    add!("B4", B4(; kw...)); add!("B4K", B4K(; tilt=K_TILT, kw...)); add!("G6", G6(; kw...))
    add!("T6", T6(; kw...)); add!("B5", B5(; kw...))
    return out
end

const MAPS_TABLE_COLNAMES = ["id", "compile", "nst", "beta0", "gamma0", "C",
                             ["m$(i)$(j)" for i in 1:6 for j in 1:6]...]

"One table row: id, compile, nst, beta0, gamma0, C, m11..m66 (row-major)."
_maps_row(id, compile, nst, C, M) =
    Any[id, compile, nst, BENCH_BETA0, BENCH_GAMMA0, Float64(C), (M[i, j] for i in 1:6 for j in 1:6)...]

"""
    write_benchmark_maps(path; nst=64, integrator_order=4) -> path

validation/reference/twiss_benchmark_maps.tsv: one row per fixture and compile
mode (bare and task for every lattice fixture; matrix for D6_*, D8_*, F8; the
4x4 D8 maps are embedded as blockdiag(M4, I2)), columns id, compile, nst,
beta0, gamma0, C, m11..m66 at %.17g, under the # header form of the stage 8 tables (history section).
"""
function write_benchmark_maps(path::AbstractString; nst=DEFAULT_NST, integrator_order=DEFAULT_ORDER)
    header = [
        "Octopus one-turn maps of the stage 8 twiss benchmark fixtures (fixture table: docs/history/twiss_dispersion_analysis_history.md, the 2026-09-15 stage 8 sections)",
        "purpose: the Octopus side of the MAD-X / PTC / Xsuite twiss benchmarks at the matrix level;",
        "consumers: validation/twiss_madx_benchmark.jl, validation/twiss_xsuite_benchmark.jl; documented for, not read by, validation/twiss_ptc_benchmark.jl",
        "producer: validation/twiss_benchmark_cells.jl write_benchmark_maps (Octopus tree of the commit that carries this file)",
        "flags: every thick magnet nst=$(nst), integrator_order=$(integrator_order); ComplexStepLinearization at the origin",
        "beam: protons, mass $(BENCH_MASS_GEV_STRING) GeV, total energy 3.0 GeV, beta0 $(_cell_string(BENCH_BETA0)), gamma0 $(_cell_string(BENCH_GAMMA0)), p0c $(_cell_string(BENCH_P0C_EV)) eV",
        "coordinates: Octopus (x, px, y, py, z, pz), z = s - ell (path deficit, negative for the longer path), pz = delta = dP/P0",
        "compile = bare: Tuple of compile_runtime maps, no velocity slip, a drift has (5,6) = 0; compile = task: the same specs through",
        "  TrackingTask (survey-bound cavity), (5,6) gains +C/gamma0^2; a cavity-free cell gets a marker cavity of strength $(TASK_MARKER_STRENGTH)",
        "compile = matrix: the manufactured dense maps of the identity contract, MersenneTwister(20260911) in the contract's draw order;",
        "  nst = 0, C = 0; D8_* are 4x4 maps embedded as blockdiag(M4, I2) (read m11..m44)",
        "conversion the reader applies to an EXTERNAL map: M_oct = Sh(u) J0 F M_ext F^-1 J0^-1 (convert_map; the stage 8 conversion law, same history sections):",
        "  MAD-X J0 = diag(1,1,1,1,beta0,1/beta0), F = I, u = -C/gamma0^2 (bare) or 0 (task); Xsuite J0 = I, F = I, same u;",
        "  PTC time=false J0 = I, F = diag(1,1,1,1,-1,1), u = 0 (bare) or +C/gamma0^2 (task)",
        "fixtures: K1, K2, B4K tilt $(K_TILT); R_* = rolled FODO at theta in {0, 0.01, 0.1, pi/8, pi/4}; Rd_* = R(pi/4) with kd = -(1+eps);",
        "  W1 = lone 400 MHz cavity strength $(RF_STRENGTH); W2 = lone quad L=0.2 K1=1 tilt pi/4; B4 = U2 + cavity(+$(RF_STRENGTH)); T6 = U2 + cavity(-$(RF_STRENGTH));",
        "  G6 = six U2 cells + cavity f = $(_cell_string(G6_FREQUENCY_HZ)) Hz, strength $(_cell_string(g6_strength())) (V = 2.0 MV); B5 = B4 + crab strengthX -$(CRAB_STRENGTH)",
        "cavity rows (W1, B4, B4K, G6) are at the DECK beam above; the PTC benchmark compiles its cavity twins at PTC's effective beam",
        "  (mass $(PTC_INTERNAL_PROTON_MASS_GEV) GeV, beta0 $(_cell_string(PTC_BETA0)); stage 8 decision D19), so its twin M65 sits 1.9e-9 relative below these rows",
        "numbers: %.17g; the stability of each row is the consumer's sanity gate, not asserted here",
    ]
    rows = Vector{Any}()
    for f in benchmark_fixtures(; nst, integrator_order)
        push!(rows, _maps_row(f.id, "bare", nst, f.C, bare_map(f.cell)))
        push!(rows, _maps_row(f.id, "task", nst, f.C, task_map(f.cell)))
    end
    for d in dense_maps()
        M = d.dim == 6 ? d.M : (M6 = Matrix{Float64}(I, 6, 6); M6[1:4, 1:4] = d.M; M6)
        push!(rows, _maps_row(d.id, "matrix", 0, 0.0, M))
    end
    return write_reference_table(path, header, MAPS_TABLE_COLNAMES, rows)
end
