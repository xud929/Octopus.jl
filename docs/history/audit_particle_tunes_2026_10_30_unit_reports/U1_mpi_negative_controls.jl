# Run in an environment containing Octopus, MPI and MPICH_jll.
# The child inherits that environment; no campaign-specific /tmp path is used.
using Octopus, MPICH_jll
root = pkgdir(Octopus)
child_load_path = join(Base.load_path(), Sys.iswindows() ? ';' : ':')
child_project = dirname(Base.active_project())
length(ARGS) <= 1 || error("pass at most one output directory")
output_root = isempty(ARGS) ? mktempdir(prefix="octopus_u1_mpi_") : abspath(only(ARGS))
println("U1-MPI-CONTROL-OUTPUT ", output_root); flush(stdout)
for case in ("planes", "presence")
    directory=joinpath(output_root,"particle_tunes_mpi_red_"*case)
    mkpath(directory)
    cmd=addenv(`$(MPICH_jll.mpiexec()) -n 4 $(Base.julia_cmd()) --startup-file=no --threads=2 -L $(joinpath(@__DIR__,"U1_inject_old_admission.jl")) $(joinpath(@__DIR__,"U1_mpi_control_witness.jl")) $case $directory`,
        "JULIA_LOAD_PATH"=>child_load_path,"JULIA_PROJECT"=>child_project)
    timedout=Ref(false)
    open(joinpath(directory,"launcher.log"),"w") do io
        process=run(pipeline(cmd;stdout=io,stderr=io);wait=false)
        watchdog=Timer(90) do _
            if process_running(process)
                timedout[]=true
                kill(process)
            end
        end
        wait(process);close(watchdog)
        success(process) && error("old admission unexpectedly passed mismatch witness")
    end
    receipts=[read(joinpath(directory,"u1_$(case)_rank_$(rank).txt"),String) for rank in 0:3]
    all(r->occursin("entered",r),receipts) || error("negative control did not reach the experiment")
    if case=="planes"
        all(r->occursin("refused=false unchanged=false",r),receipts) || error("plane mismatch control failed for another reason")
    else
        peers_changed = any(r->occursin("unchanged=false",r), receipts[2:end])
        active_incomplete = !occursin("refused=", receipts[1])
        corruption = any(r->occursin("particle counts",r),receipts)
        # The same mismatch has two measured timing outcomes: peers can write
        # changed-coordinate/bogus-count receipts, or MPI can abort before any
        # completion receipt with this precise collective-size error. All four
        # entry markers above are required in either case; a generic failure
        # or a pre-entry compilation timeout does not qualify.
        launcher_text = read(joinpath(directory,"launcher.log"),String)
        truncated_gather = occursin(
            "Fatal error in internal_Allgather: Message truncated", launcher_text)
        incomplete = any(r->!occursin("refused=",r),receipts)
        observed = (peers_changed && active_incomplete && corruption) ||
                   (active_incomplete && truncated_gather) ||
                   (timedout[] && incomplete)
        observed || error("presence control did not reproduce incoherent MPI collectives")
        println("U1-MPI-PRESENCE-MECHANISM peers_changed=",peers_changed,
                " corrupted_counts=",corruption," truncated_allgather=",truncated_gather,
                " timedout=",timedout[]); flush(stdout)
    end
    println("PARTICLE-TUNES-MPI-NEGATIVE case=",case," timedout=",timedout[]," receipts=",length(receipts)," expected_defect=true");flush(stdout)
end
