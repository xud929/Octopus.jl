# The child of `StrongStrongPICMultiProcessConsistencyContract` (multi-process
# step 4c): one launched process per rank, building the SAME beams the parent
# built -- under the multi-process policy, which draws the whole beam and
# keeps this rank's shard -- running the same PIC task divided, then gathering
# both beams onto rank 0 and writing them with the luminosity series to the
# file the parent named. Not part of the Octopus module: the contract launches
# it as a script under the caller's project, which must carry `MPI` so the
# extension loads (asserted below rather than silently running the
# passthrough as a single process).
#
#     mpiexec -n 2 julia --project=<env with Octopus and MPI> \
#         src/contracts/mpi_pic_consistency_child.jl n_particles=1024 turns=2 \
#         grid=32,32 nslices=3 deposit_method=CIC green_cache=slice_pair \
#         threads_per_rank=1 seed=123456789 ranks=2 out=/tmp/mpi_2.h5
using Octopus
using MPI

fail(msg) = (println("MPI-PIC-CONTRACT FAIL ", msg); flush(stdout); exit(1))
Base.get_extension(Octopus, :OctopusMPIExt) === nothing &&
    fail("OctopusMPIExt is not loaded; the child would run as a single process")

spec = Octopus._mpi_pic_contract_spec(ARGS)
policy = MultiProcessExecutionPolicy(threads=spec.threads_per_rank)
base = StrongStrongPICBackendConsistencyContract(
    n_particles=spec.n_particles, turns=spec.turns, grid=spec.grid, nslices=spec.nslices,
    deposit_method=spec.deposit_method, green_cache=spec.green_cache, seed=spec.seed)

set_global_rng!(seed=spec.seed, method=:philox)
beam1, beam2 = Octopus._strong_strong_contract_base_beams(base, policy)
artifact = joinpath(dirname(spec.out), "mpi_$(spec.ranks)_artifact.h5")
task = Octopus._strong_strong_contract_task(base, artifact; policy=policy)
execute!(task, beam1, beam2; turns=spec.turns)

resolved = Octopus._resolve_execution_policy(policy, beam1.rep)
Octopus._with_execution_policy(resolved) do
    Octopus._mp_nranks() == spec.ranks ||
        fail("the communicator holds $(Octopus._mp_nranks()) rank(s), not the $(spec.ranks) launched")
    Octopus._with_beam_shards(beam1.rep, beam2.rep) do
        # Rows in global particle order once gathered (rank order is shard
        # order), so the parent compares particle for particle.
        rows1 = Octopus._mp_gather_rows(hcat(Octopus.coordinate_arrays(beam1.rep)...))
        rows2 = Octopus._mp_gather_rows(hcat(Octopus.coordinate_arrays(beam2.rep)...))
        if Octopus._mp_is_root()
            series = read(Octopus.TaskOutput(artifact), :luminosity; name="ip")
            Octopus.HDF5.h5open(spec.out, "w") do f
                f["beam1"] = rows1
                f["beam2"] = rows2
                f["turns"] = collect(Int, series.turn)
                f["values"] = collect(Float64, series.value)
                f["nranks"] = Octopus._mp_nranks()
            end
        end
    end
end
flush(stdout)
