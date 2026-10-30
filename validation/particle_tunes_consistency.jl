# Persistent particle tunes: independent BigFloat dense maps and finite-sum
# phase-mixing / prescribed dipole-kick response on CPU threads and CUDA.
# Run: julia --project=. --threads=4 validation/particle_tunes_consistency.jl
# Configuration: OCTOPUS_TUNES_N=17, OCTOPUS_TUNES_TURNS=64,
# OCTOPUS_REQUIRE_GPU_CONTRACT=0 (1 requires both CUDA launch-shape arms).
# Dense-map error uses 128*eps(T)*turns times each coordinate's reference
# scale. Response sums use |initial phase-plane amplitude| + sum|kicks|,
# because a whole zero-spread output column can cancel through zero. This
# allows two six-term products, optics preparation and accumulated phase
# rounding without a unit-sized absolute floor. Physical action and
# centroid/covariance tolerances use the same operation/turn scaling. The
# reference code in test/particle_tunes_probe.jl owns explicit dense canonical
# matrices and direct complex-power sums; it calls no new runtime helper.
# Prints per-policy measurements and a failing exit status for any violation.
# Real one/two/four-rank and empty-shard checks run in test/mpi_seam_check.jl.
# GATE-CUDA-ARM: env OCTOPUS_REQUIRE_GPU_CONTRACT=1 OCTOPUS_TUNES_N=17 OCTOPUS_TUNES_TURNS=24 ; verdict "PARTICLE-TUNES validation passed"

using Octopus
include(joinpath(@__DIR__, "..", "test", "particle_tunes_probe.jl"))

let source = read(@__FILE__, String)
    header = first(split(source, "using Octopus"; limit=2))
    declared = Set(m.match for m in eachmatch(r"OCTOPUS_[A-Z0-9_]+", header))
    read_variables = Set(m.captures[1] for m in eachmatch(r"\"(OCTOPUS_[A-Z0-9_]+)\"", source))
    # The common GPU parser reads this key on the script's behalf.
    push!(read_variables, "OCTOPUS_REQUIRE_GPU_CONTRACT")
    declared == read_variables || error("particle-tune validation environment header drift")
end

function pt_validation_main()
    n = parse(Int, get(ENV, "OCTOPUS_TUNES_N", "17"))
    turns = parse(Int, get(ENV, "OCTOPUS_TUNES_TURNS", "64"))
    n > 1 && turns > 0 || error("particle-tune validation needs N>1 and positive turns")
    gpu = Octopus._HAS_CUDA && Octopus.CUDA.functional()
    Octopus._require_gpu_contract() && !gpu && error("particle-tune validation requires CUDA but no device is functional")
    policies = Any[CPUThreadsExecutionPolicy(threads=t) for t in (1, 2, 4)]
    gpu && append!(policies, [CUDAExecutionPolicy(launch=CUDALaunchConfig(threads=t)) for t in (64, 256)])
    checked = 0
    worst_ratio = 0.0
    for T in (Float64, Float32)
        baseline = nothing
        for policy in policies
            dense = pt_probe_dense(policy; T=T, n=n)
            dense.comparison.equal || error("independent dense map failed: $(policy), $(T), $(dense.comparison)")
            table = only(dense.tables)
            table.bound && table.tunes == dense.labels || error("particle labels do not match their global input")
            receipts = filter(r -> r.consumer === :particle_tune_initialization, dense.receipts)
            length(receipts) == 1 || error("expected one actual preparation receipt")
            receipt = only(receipts)
            receipt.values.global_n == n && receipt.values.n_local == n || error("preparation receipt has wrong counts")
            receipt.backend === (policy isa CUDAExecutionPolicy ? CUDABackend : CPUThreadsBackend) || error("requested backend did not execute")
            if baseline === nothing
                baseline = dense.rows
            else
                pt_probe_difference(dense.rows, baseline, T; turns=3).equal || error("policy changed the particle response")
            end
            binding = only(values(dense.task.particle_tunes[].bindings))
            all(a -> typeof(a) === typeof(dense.rep.x), binding.tunes) || error("tune arrays are not resident with the coordinates")
            owned = binding.tunes
            execute!(dense.task, dense.rep; turns=2)
            binding.tunes === owned || error("steady tracking replaced the owned tune arrays")
            println("TUNE-DENSE precision=", T, " policy=", policy, " particles=", n,
                " max_abs=", dense.comparison.max_abs, " max_ratio=", dense.comparison.max_ratio,
                " owned_buffers_persist=true receipt_backend=", receipt.backend,
                " executed_threads=", dense.execution.threads, " launches=", dense.execution.launches)
            worst_ratio = max(worst_ratio, dense.comparison.max_ratio)
            checked += 1
            for kicks in (false, true), spread in (false, true)
                response = pt_probe_response(policy; T=T, n=n, turns=turns, kicks=kicks, spread=spread)
                response.max_ratio <= 1 || error("direct phase/kick sum failed: $(response.max_ratio)")
                response.centroid_gap <= 128eps(T)*turns*0.01 || error("centroid phase sum failed")
                response.covariance_gap <= 256eps(T)*turns*0.01^2 || error("central covariance response failed")
                if !kicks
                    response.action_relative <= 128eps(T)*turns || error("normalized action changed")
                    response.phasor_gap <= 128eps(T)*turns || error("recovered phase advance changed")
                end
                println("TUNE-RESPONSE precision=", T, " policy=", policy, " kicks=", kicks,
                    " spread=", spread, " particles=", n, " turns=", turns,
                    " max_ratio=", response.max_ratio, " action_relative=", response.action_relative,
                    " output_scaled_ratio_diagnostic=", response.output_scaled_max_ratio,
                    " phasor_gap=", response.phasor_gap, " centroid_gap=", response.centroid_gap,
                    " covariance_gap=", response.covariance_gap)
                worst_ratio = max(worst_ratio, response.max_ratio)
                checked += 1
            end
        end
    end
    gpu || println("SKIP CUDA: particle-tune validation executed CPU policies only")
    println("PARTICLE-TUNES validation passed cases=", checked, " cuda_active=", gpu,
        " worst_ratio=", worst_ratio)
end

pt_validation_main()
