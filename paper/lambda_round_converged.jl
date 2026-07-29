#=
Round-beam converged Yokoya point (Table 2, PIC 128^2 row).

Table 2's PIC entries were originally produced by a driver that predates this
reproduction package.  This script re-measures them independently at the same
settings -- 8192 turns, 1e5 macroparticles per beam, xi = 0.005, single slice,
PIC on a 128^2 mesh, tunes (0.31, 0.32) -- with three fresh seeds, and reports
BOTH planes.

It is a thin wrapper: the measurement itself is `lambda_flat_converged.jl`
evaluated at aspect ratio 1.0 (round), so the round-beam and flat-beam points
of Sec. 5.1 come from one identical code path and differ only in the aspect
ratio.

Result archived in data/lambda_round_converged.tsv:
    Lambda_x = 1.197 +- 0.004,  Lambda_y = 1.206 +- 0.000
against the printed Table 2 values 1.198 +- 0.004 and 1.206 +- 0.003.

Run:
  julia --threads=8 --startup-file=no --project=. paper/lambda_round_converged.jl
=#

ENV["OCTOPUS_LFC_ASPECT"] = get(ENV, "OCTOPUS_LFC_ASPECT", "1.0")
ENV["OCTOPUS_LFC_TURNS"]  = get(ENV, "OCTOPUS_LFC_TURNS", "8192")
ENV["OCTOPUS_LFC_NMACRO"] = get(ENV, "OCTOPUS_LFC_NMACRO", "100000")
ENV["OCTOPUS_LFC_SEEDS"]  = get(ENV, "OCTOPUS_LFC_SEEDS", "20260727,20260728,20260729")
ENV["OCTOPUS_LFC_OUT"]    = get(ENV, "OCTOPUS_LFC_OUT",
                                 joinpath(@__DIR__, "data", "lambda_round_converged.tsv"))

include(joinpath(@__DIR__, "lambda_flat_converged.jl"))
