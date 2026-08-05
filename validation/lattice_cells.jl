"""
FODO, DBA and TBA cells built from the lattice magnets, checked for
symplecticity, closure and CPU/CUDA consistency.

Reference model
---------------
No external reference: this script checks the *cells* rather than the element
maps, which are validated against PTC by `PTCConsistencyContract` (see
`validation/generate_ptc_reference.jl`). What is checked here is that magnets
compose into working lattices and that the composed line tracks identically on
CPU and CUDA.

Error metric
------------
- one-turn Jacobian residual `max|J' S J - S|` by complex-step differentiation;
- linear stability `|trace(M_2x2)| < 2` per transverse plane, which is what
  makes the cell a usable lattice rather than an arbitrary sequence;
- long-term Courant-Snyder invariant drift over many turns, which catches a map
  that is symplectic once but not stably so. Measured **on momentum**: cells
  containing bends have dispersion, so an off-momentum particle oscillates about
  the dispersion orbit and the on-axis invariant is not conserved for it;
- `max|coordinate|` between CPU and CUDA tracking of the same particles.

Cells
-----
FODO  focus-drift-defocus-drift.
DBA   double-bend achromat: two sector bends with a focusing quadrupole between,
      wrapped in defocusing quads -- a bare Chasman-Green cell has no vertical
      focusing at all and is unstable.
TBA   triple-bend achromat: three sector bends, focusing between them.

Quadrupole strengths are not hand-tuned: the script scans a small grid for a
working point stable in both planes and reports the one it picked.

Outputs (under `result/`)
-------------------------
`lattice_cells.tsv` -- one row per cell with every metric above.

Run
---
    julia --project=. validation/lattice_cells.jl

Environment
-----------
    OCTOPUS_LATTICE_N       particles for the backend comparison (default 4096)
    OCTOPUS_LATTICE_TURNS   turns for the backend comparison (default 4)
    OCTOPUS_LATTICE_LONG    turns for the invariant-drift check (default 2000)
"""

include(joinpath(@__DIR__, "..", "src", "Octopus.jl"))
using .Octopus
using LinearAlgebra
using Printf

const N = parse(Int, get(ENV, "OCTOPUS_LATTICE_N", "4096"))
const TURNS = parse(Int, get(ENV, "OCTOPUS_LATTICE_TURNS", "4"))
const LONG = parse(Int, get(ENV, "OCTOPUS_LATTICE_LONG", "2000"))
const NST = 4
const ORDER = 4

"FODO cell: focusing quad, drift, defocusing quad, drift."
fodo_cell(kq) = (
    compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, kq), nst=NST, integrator_order=ORDER)),
    compile_runtime(DriftSpec(L=1.2)),
    compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, -kq), nst=NST, integrator_order=ORDER)),
    compile_runtime(DriftSpec(L=1.2)))

"""
Double-bend achromat. A bare Chasman-Green cell (two bends and one focusing
quad) has no vertical focusing at all, so the cell is wrapped in a defocusing
quad on each side -- this is why `kd` exists rather than being an embellishment.
"""
function dba_cell(kf, kd; Lb=1.0, angle=0.20)
    bend = compile_runtime(SBendSpec(L=Lb, h=angle / Lb, b0=angle / Lb,
                                     nst=NST, integrator_order=ORDER))
    qf = compile_runtime(QuadrupoleSpec(L=0.35, kn=(0.0, kf), nst=NST, integrator_order=ORDER))
    qd = compile_runtime(QuadrupoleSpec(L=0.25, kn=(0.0, kd), nst=NST, integrator_order=ORDER))
    d = compile_runtime(DriftSpec(L=0.6))
    return (qd, d, bend, d, qf, d, bend, d, qd)
end

"Triple-bend achromat: three bends, focusing between them, defocusing outside."
function tba_cell(kf, kd; Lb=0.9, angle=0.14)
    bend = compile_runtime(SBendSpec(L=Lb, h=angle / Lb, b0=angle / Lb,
                                     nst=NST, integrator_order=ORDER))
    qf = compile_runtime(QuadrupoleSpec(L=0.3, kn=(0.0, kf), nst=NST, integrator_order=ORDER))
    qd = compile_runtime(QuadrupoleSpec(L=0.25, kn=(0.0, kd), nst=NST, integrator_order=ORDER))
    d = compile_runtime(DriftSpec(L=0.5))
    return (qd, d, bend, d, qf, d, bend, d, qf, d, bend, d, qd)
end

"Add a chromaticity-correcting sextupole, exercising a nonlinear element."
with_sextupole(cell; L=0.2, k2=8.0) =
    (cell..., compile_runtime(SextupoleSpec(L=L, kn=(0.0, 0.0, k2),
                                            nst=NST, integrator_order=ORDER)))

track_cell(cell, u) = foldl((c, e) -> e(c...), cell; init=u)

const S6 = kron(Matrix{Float64}(I, 3, 3), [0.0 1.0; -1.0 0.0])

function one_turn_jacobian(cell, u0)
    J = zeros(6, 6)
    for j in 1:6
        u = ComplexF64[u0...]
        u[j] += 1e-30im
        J[:, j] = imag.(collect(track_cell(cell, Tuple(u)))) ./ 1e-30
    end
    return J
end

traces(J) = (abs(J[1, 1] + J[2, 2]), abs(J[3, 3] + J[4, 4]))

"""
Courant-Snyder parameters of a stable 2x2 block. Returns `nothing` when the
block is unstable, which is what makes the scan below a stability search rather
than a guess.
"""
function twiss(M)
    tr = M[1, 1] + M[2, 2]
    abs(tr) >= 2 && return nothing
    smu = sign(M[1, 2]) * sqrt(1 - (tr / 2)^2)
    smu == 0 && return nothing
    return M[1, 2] / smu, (M[1, 1] - M[2, 2]) / (2smu)   # beta, alpha
end

"Search a small grid for a working point stable in both planes."
function find_stable(build, kfs, kds)
    best = nothing
    for kf in kfs, kd in kds
        cell = build(kf, kd)
        J = try
            one_turn_jacobian(cell, (1.0e-6, 0.0, 1.0e-6, 0.0, 0.0, 0.0))
        catch
            continue
        end
        all(isfinite, J) || continue
        tx, ty = traces(J)
        (tx < 2 && ty < 2) || continue
        score = max(tx, ty)                    # prefer the most stable point
        (best === nothing || score < best[3]) && (best = (kf, kd, score))
    end
    return best
end

"""
Relative drift of the Courant-Snyder invariant over `turns` turns. A map that is
symplectic once but not stably so shows up here and not in the Jacobian check.
"""
function invariant_drift(cell, u0, turns)
    # Linearize at the SAME point that is tracked: Twiss taken at a different
    # momentum describes a different ellipse and the invariant would drift for
    # that reason alone.
    J = one_turn_jacobian(cell, u0)
    tx = twiss(J[1:2, 1:2]); ty = twiss(J[3:4, 3:4])
    (tx === nothing || ty === nothing) && return NaN
    bx, ax = tx; by, ay = ty
    inv(u) = (u[1]^2 + (ax * u[1] + bx * u[2])^2) / bx +
             (u[3]^2 + (ay * u[3] + by * u[4])^2) / by
    u = u0
    i0 = inv(u0)
    worst = 0.0
    for _ in 1:turns
        u = try
            track_cell(cell, u)
        catch
            return NaN
        end
        all(isfinite, u) || return NaN
        worst = max(worst, abs(inv(u) - i0) / i0)
    end
    return worst
end

fodo_k = find_stable((kf, _) -> fodo_cell(kf), 0.3:0.05:1.6, (0.0,))
dba_k = find_stable(dba_cell, 0.6:0.1:3.0, -3.0:0.1:-0.2)
tba_k = find_stable(tba_cell, 0.6:0.1:3.0, -3.0:0.1:-0.2)
for (nm, k) in (("FODO", fodo_k), ("DBA", dba_k), ("TBA", tba_k))
    k === nothing && error("no stable working point found for $nm")
end
@printf("stable working points: FODO kq=%.2f | DBA kf=%.2f kd=%.2f | TBA kf=%.2f kd=%.2f\n\n",
        fodo_k[1], dba_k[1], dba_k[2], tba_k[1], tba_k[2])

const CELLS = (
    ("FODO", fodo_cell(fodo_k[1])),
    ("FODO+sext", with_sextupole(fodo_cell(fodo_k[1]))),
    ("DBA", dba_cell(dba_k[1], dba_k[2])),
    ("DBA+sext", with_sextupole(dba_cell(dba_k[1], dba_k[2]))),
    ("TBA", tba_cell(tba_k[1], tba_k[2])),
    ("TBA+sext", with_sextupole(tba_cell(tba_k[1], tba_k[2]))),
)

u0 = (1.0e-4, 2.0e-5, -0.8e-4, -1.5e-5, 1.0e-3, 2.0e-4)

println("Lattice cells built from LatticeMagnet elements")
println("nst = $NST, integrator_order = $ORDER, particles = $N, turns = $TURNS\n")
@printf("%-10s %8s %12s %8s %8s %12s\n",
        "cell", "elems", "symplectic", "|tr_x|", "|tr_y|", "inv drift")
rows = Tuple[]
for (name, cell) in CELLS
    J = one_turn_jacobian(cell, u0)
    sy = maximum(abs, J' * S6 * J - S6)
    tx, ty = traces(J)
    dr = invariant_drift(cell, (u0[1], u0[2], u0[3], u0[4], 0.0, 0.0), LONG)
    @printf("%-10s %8d %12.2e %8.4f %8.4f %12.2e\n", name, length(cell), sy, tx, ty, dr)
    push!(rows, (name, length(cell), sy, tx, ty, dr))
end

println("\nCPU/CUDA consistency (ElementTrackingBackendConsistencyContract)")
backend_rows = Tuple[]
for (name, cell) in CELLS
    cpu = validate(ElementTrackingBackendConsistencyContract(;
        line=cell, n_particles=N, turns=TURNS,
        backend_a=CPUThreadsBackend, backend_b=CPUThreadsBackend,
        atol=1.0e-12, rtol=1.0e-12))
    gpu = validate(ElementTrackingBackendConsistencyContract(;
        line=cell, n_particles=N, turns=TURNS,
        backend_a=CPUThreadsBackend, backend_b=CUDABackend,
        atol=1.0e-10, rtol=1.0e-10))
    gd = get(gpu.metrics, :max_abs_error, NaN)
    @printf("  %-10s cpu/cpu %-8s  cpu/cuda %-8s  max|Δ| = %s\n",
            name, cpu.status, gpu.status,
            gpu.status === :skipped ? "n/a" : @sprintf("%.3e", gd))
    push!(backend_rows, (name, string(cpu.status), string(gpu.status), gd))
end

resultdir = normpath(joinpath(@__DIR__, "..", "result"))
mkpath(resultdir)
open(joinpath(resultdir, "lattice_cells.tsv"), "w") do io
    println(io, "cell\telements\tsymplectic_residual\ttrace_x\ttrace_y\tinvariant_drift\tcpu_cpu\tcpu_cuda\tcuda_max_diff")
    for (r, b) in zip(rows, backend_rows)
        @printf(io, "%s\t%d\t%.8e\t%.8f\t%.8f\t%.8e\t%s\t%s\t%.8e\n",
                r[1], r[2], r[3], r[4], r[5], r[6], b[2], b[3], b[4])
    end
end
println("\nTSV written to result/lattice_cells.tsv")

# Gate, not just print (2026-08-05 audit, U21-3): a :failed backend contract
# or a non-symplectic cell exited 0 and looked green in any driver.
for (r, b) in zip(rows, backend_rows)
    r[3] <= 5.0e-7 || error("cell $(r[1]) symplecticity residual $(r[3]) exceeds 5e-7")
    b[2] == "passed" || error("cell $(r[1]) CPU/CPU backend contract: $(b[2])")
    b[3] in ("passed", "skipped") || error("cell $(r[1]) CPU/CUDA backend contract: $(b[3])")
end
println("all cells gated: symplectic and backend-consistent")
