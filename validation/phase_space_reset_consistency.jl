# Repeated fresh-copy, one-turn tracking is the independent reference for a
# turn-by-turn run with PhaseSpaceResetSpec. Every particle's six coordinates,
# the actual noise values, revival/loss events and the final trial are checked.
#
# Run: julia --project=. --threads=4 validation/phase_space_reset_consistency.jl
# Configuration: OCTOPUS_RESET_N=25, OCTOPUS_RESET_TURNS=8 (1:8),
# OCTOPUS_REQUIRE_GPU_CONTRACT=0 (set 1 to require the CUDA arm).
# Same-backend copies and reference outputs are exact/NaN-aware. CPU/CUDA
# physics uses the established tracking tolerance 1e-10 for Float64; Float32
# uses rtol=64eps(Float32) and, separately for each coordinate, atol equal to
# that rtol times the reference column's maximum finite absolute value.
# Turn/particle identity and the finite/lost mask match exactly. Noise is host-realized
# and must match exactly between policies. No MPI claim is made by this script:
# real one/two/four-rank checks run in test/mpi_seam_check.jl.
#
# GATE-CUDA-ARM: env OCTOPUS_REQUIRE_GPU_CONTRACT=1 OCTOPUS_RESET_N=17 OCTOPUS_RESET_TURNS=4 ; verdict "PHASE-SPACE-RESET validation passed"

using Octopus
include(joinpath(@__DIR__, "..", "test", "phase_space_reset_probe.jl"))

function psr_validation_main()
    n = parse(Int, get(ENV, "OCTOPUS_RESET_N", "25"))
    turns = parse(Int, get(ENV, "OCTOPUS_RESET_TURNS", "8"))
    n > 0 || error("OCTOPUS_RESET_N must be positive")
    1 <= turns <= 8 || error("OCTOPUS_RESET_TURNS must be in 1:8 for the prescribed noise table")
    cuda_active = Octopus._HAS_CUDA && Octopus.CUDA.functional()
    require_cuda = Octopus._require_gpu_contract()
    require_cuda && !cuda_active && error("CUDA required for phase-space reset validation but unavailable")
    policies = Any[CPUThreadsExecutionPolicy(threads=4)]
    cuda_active && push!(policies, CUDAExecutionPolicy())
    directory = mktempdir()
    checked = 0
    largest_gap = 0.0
    for T in (Float64, Float32), kind in psr_probe_kinds(), losses in (false, true)
        losses && kind !== :table && continue
        line = psr_probe_line(T, kind; losses=losses)
        reference = nothing
        for policy in policies
            prefix = string(nameof(typeof(policy)), "_", T, "_", kind, "_", losses)
            result = psr_probe_verify(policy, directory; T=T, kind=kind, losses=losses,
                n=n, turns=turns, prefix=prefix, line_override=line)
            psr_probe_pass(result) || error("phase-space reset oracle failed: $(prefix)")
            all(==(1.0), result.trials.completed) || error("incomplete trial in successful $(prefix)")
            all(==(Float64(n)), result.trials.particles) || error("wrong attempted ensemble in $(prefix)")
            if reference === nothing
                reference = result
            else
                comparison = psr_probe_backend_difference(result.rows, reference.rows, T)
                comparison.equal || error("CPU/CUDA response differs: $(prefix), $(comparison)")
                loss_comparison = psr_probe_backend_difference(result.reset_loss_rows,
                    reference.reset_loss_rows, T; identity_columns=3)
                loss_comparison.equal || error("CPU/CUDA loss events differ: $(prefix), $(loss_comparison)")
                result.noise == reference.noise || error("CPU/CUDA noise inputs differ: $(prefix)")
                largest_gap = max(largest_gap, comparison.max_abs)
                println("RESET-BACKEND precision=", T, " noise=", kind, " losses=", losses,
                        " identities_exact=", comparison.identity_equal,
                        " loss_mask_exact=", comparison.loss_mask_equal,
                        " scaled_max_by_coordinate=", comparison.scaled_max)
            end
            println("RESET-ORACLE policy=", nameof(typeof(policy)), " precision=", T,
                    " noise=", kind, " losses=", losses, " particles=", n,
                    " turns=", turns, " coordinate_rows=", result.row_count,
                    " loss_rows=", size(result.reset_loss_rows, 1),
                    " same_backend_max_abs=", result.coordinates.max_abs,
                    " restored_exact=", result.starts_exact)
            checked += 1
        end
    end
    cuda_active || println("SKIP CUDA: no functional device; only CPU reset cases executed")
    println("PHASE-SPACE-RESET validation passed cases=", checked,
            " cuda_active=", cuda_active, " max_cross_backend_abs=", largest_gap)
    return nothing
end

psr_validation_main()
