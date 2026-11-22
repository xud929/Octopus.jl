# BBSCL comparison scripts

The drivers, input generators and raw results behind
[`docs/history/bbscl_comparison_2026_11_22.md`](../../docs/history/bbscl_comparison_2026_11_22.md),
the implementation and performance comparison between Octopus and BBSCL (K. Ohmi's CUDA
beam-beam and space-charge collider code, `github.com/BBSCL/bbscl`, HEAD `24b5eaf`). Read the
record first; this file says how to run things.

## Octopus arms

Three drivers, one per case, each configured by `OCT_*` environment variables listed in its
header (defaults are the production points of the record):

| driver | case | default point |
|---|---|---|
| `octopus_strong_strong_bbscl.jl` | S: e-p strong-strong, PIC (`OCT_SOLVER=pic`) or soft-Gaussian (`gaussian`), Hirata boosts, one-turn linear maps, electron radiation | 2,560,000 e / 1,024,000 p, 15 slices, 128 x 128, 200 turns |
| `octopus_weak_strong_bbscl.jl` | W: weak proton beam against a rigid 7-slice electron beam | 1,024,000 p, 200 turns |
| `octopus_lattice_bbscl.jl` | L: 8-cell FODO ring (80 thick elements and a thin RF cavity); `OCT_MODE=optics OCT_NCELL=1` writes the matched cell optics `lattice_optics.txt`, `OCT_MODE=track` runs | 1,048,576 p, 200 turns |

They load Octopus from the source tree (`include("../../src/Octopus.jl")`), run on CUDA by default
(`OCT_GPU=1`, an error if no device) or on CPU threads (`OCT_GPU=0`), record `turn_timings`, read
the luminosity back from an in-memory run artifact and write a TSV per run (`OCT_OUT`). A reduced
CPU check of each:

```bash
OCT_GPU=0 OCT_NE=20480 OCT_NP=20480 OCT_TURNS=5 julia --project=. --threads=4 validation/bbscl_comparison/octopus_strong_strong_bbscl.jl
OCT_GPU=0 OCT_N=20480 OCT_TURNS=5 julia --project=. --threads=4 validation/bbscl_comparison/octopus_weak_strong_bbscl.jl
OCT_GPU=0 OCT_N=4096 OCT_TURNS=5 OCT_OPTICS=validation/bbscl_comparison/lattice_optics.txt julia --project=. --threads=4 validation/bbscl_comparison/octopus_lattice_bbscl.jl
```

## BBSCL arms

`gen_bbscl_S.py`, `gen_bbscl_W.py`, `gen_bbscl_L.py` write the BBSCL input files from the same
physics constants as the drivers (the generated production inputs are committed under `inputs/`).
BBSCL's grammar is positional (`Type Name=({k0, k1, ...});`, a space after the type keyword,
comments ending with `;`); the slot meanings are commented in the generators and derived in the
record. Two conventions the generators handle: the strong-strong kick coefficient uses the
electron radius for both beams, so the electron bunch population is handed over as
`N_e m_e/m_p` for a proton partner; the luminosity in `.f10` is per particle pair and is
converted to m^-2 per crossing by `summarize.py`.

Build BBSCL out of tree (its Makefile passes no `-O` and no `-arch`; `pr.mk` lacks
`section_map.o`), with a CUDA 12.6 toolkit:

```bash
cp -r <bbscl checkout>/*.cu <bbscl checkout>/*.h <bbscl checkout>/Makefile <bbscl checkout>/pr.mk build/ && cd build
make -j16 LD=nvcc COMPFLAGS="-w -dc -O3 -arch=sm_89 -ccbin g++ -Xcompiler -O3" LDFLAGS="-arch=sm_89 -ccbin g++ -lcurand -lcufft -lcusolver" collider
make -f pr.mk -j16 LD=nvcc COMPFLAGS="..." LDFLAGS="..." prmb   # fails at link: relink by hand with section_map.o added
./collider_test bbscl_S        # reads bbscl_S_e.in and bbscl_S_p.in in the working directory
./prmb_test bbscl_W            # reads bbscl_W.in
```

## Chains, tables, tunes

`run_production.sh` (cases S and W), `run_lattice.sh` (case L) and `run_diag.sh` (BBSCL cost
decomposition) are the sequential GPU-exclusive chains that produced `results/`; they take the
repository root from their own location and write under `result/bbscl_comparison/`. `summarize.py`
rebuilds the record's tables from a results directory; `tunes.py` extracts fractional tunes from a
BBSCL `.f10` or an Octopus moments TSV. `results/` holds the per-turn outputs of every arm
(BBSCL `.f10` and stdout, Octopus TSVs and logs), the numbers behind every claim in the record.
