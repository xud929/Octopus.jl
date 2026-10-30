# U1 targeted particle-tune neighbour-audit reproducer, 2026-10-30.
# See U1.md for the measured red/green result and scope.
using Octopus, MPI, Random
MPI.Initialized() || MPI.Init()
comm = MPI.COMM_WORLD
rank = MPI.Comm_rank(comm)
nranks = MPI.Comm_size(comm)
nranks == 4 || error("U1 witness requires exactly four MPI ranks")
Base.get_extension(Octopus, :OctopusMPIExt) === nothing && error("MPI extension is inactive")
case = Symbol(ARGS[1])
receipt_dir = ARGS[2]
mkpath(receipt_dir)
struct U1Distribution end
Random.rand(rng::Random.AbstractRNG, ::U1Distribution) = 0.2 + 0.01rand(rng)
optics = (beta1=(1.,1.,1.), dmu=(0.3,0.4,-0.05))
spec = if case === :presence
    rank == 0 ? Linear6DSpec(;optics...,particle_tunes=(nux=0.21,)) : Linear6DSpec(;optics...)
elseif case === :planes
    Linear6DSpec(;optics...,particle_tunes=rank == 0 ? (nux=0.21,) : (nuy=0.21,))
elseif case === :stream
    Linear6DSpec(;optics...,particle_tunes=(nux=TuneDistribution(U1Distribution()),),
                 rng_id=rank == 0 ? 0x701011 : 0x701012)
elseif case === :nominal
    Linear6DSpec(beta1=optics.beta1,dmu=rank == 0 ? (0.3,0.4,-0.05) : (0.3,0.5,-0.05),
                 particle_tunes=(nux=0.21,))
else
    error("unknown U1 witness case")
end
interval = Octopus._mp_shard_range(7,nranks,rank)
rep = Phase6DRep(ntuple(k -> fill(0.001k,length(interval)),6)...)
before = map(copy,Octopus.coordinate_arrays(rep))
task = TrackingTask((spec,);policy=MultiProcessExecutionPolicy(threads=1,ranks=nranks),loss_report=false)
path = joinpath(receipt_dir,"u1_$(case)_rank_$(rank).txt")
write(path,"entered rank=$rank case=$case\n")
failure = try
    execute!(task,rep;turns=1)
    nothing
catch err
    err
end
unchanged = all(isequal(a,b) for (a,b) in zip(before,Octopus.coordinate_arrays(rep)))
open(path,"a") do io
    println(io,"refused=",failure !== nothing," unchanged=",unchanged)
    println(io,"error=",failure === nothing ? "NONE" : sprint(showerror,failure))
end
MPI.Barrier(comm) # all completed ranks publish evidence before the negative verdict
failure !== nothing || error("U1 mismatched metadata was silently accepted on rank $rank")
unchanged || error("U1 refusal changed coordinates on rank $rank")
MPI.Barrier(comm)
rank == 0 && println("PARTICLE-TUNES-U1-MPI-REFUSAL ",case)
