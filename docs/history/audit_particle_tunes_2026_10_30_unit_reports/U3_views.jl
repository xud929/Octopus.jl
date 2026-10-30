# Run from project root: julia --project=. --threads=4 this_file.jl
# Observational RED/GREEN probe; positive assertions live in test/runtests.jl.
using Octopus
for kind in (:particle_tunes, :phase_space_reset)
    storage=ntuple(k->fill(0.001k,8),6)
    rep=Phase6DRep(map(a->view(a,2:7),storage)...)
    elements = kind === :particle_tunes ?
        (Linear6DSpec(beta1=(1.,1.,1.),dmu=(0.3,0.4,-0.05),particle_tunes=(nux=0.21,)),) :
        (PhaseSpaceResetSpec(),)
    task=TrackingTask(elements;policy=CPUThreadsExecutionPolicy(threads=1))
    first_failure=try execute!(task,rep;turns=1);nothing catch err;err end
    GC.gc()
    continuation_failure=try execute!(task,rep;turns=1);nothing catch err;err end
    println("PARTICLE-TUNES-VIEW kind=",kind," first=",first_failure===nothing ? "passed" : sprint(showerror,first_failure),
      " continuation_after_gc=",continuation_failure===nothing ? "passed" : sprint(showerror,continuation_failure))
    flush(stdout)
end

function view_rep()
    storage = ntuple(_->zeros(8),6)
    rep = Phase6DRep(map(a->view(a,2:7),storage)...)
    rep.x[1] = 2.0
    rep
end
ap=ApertureSpec(shape=:rectangle,x_limit=1.,y_limit=1.,name="view_loss")
rep=view_rep()
task=TrackingTask((ap,);policy=CPUThreadsExecutionPolicy(threads=1))
execute!(task,rep;turns=1)
previous=loss_record(task)
GC.gc()
owner_live=task.loss_owner[].value === rep.x
execute!(task,rep;turns=1)
println("VIEW-LOSS tracking owner_survived=",owner_live," record_preserved=",loss_record(task)===previous," old_counts=",loss_counts(previous)," current_counts=",loss_counts(loss_record(task)));flush(stdout)
ip=StrongStrongCollision(:ip)
ss=StrongStrongTask((ap,ip),(ip,);policy=CPUThreadsExecutionPolicy(threads=1))
ssrep=view_rep()
ssprevious=Octopus._ensure_loss_record!(ss,1,ssrep)
ssprevious.counts[1]=1
GC.gc()
ssowner_live=ss.loss_owners[1][].value === ssrep.x
ssnow=Octopus._ensure_loss_record!(ss,1,ssrep)
println("VIEW-LOSS strongstrong_binding owner_survived=",ssowner_live," record_preserved=",ssnow===ssprevious," old_counts=",loss_counts(ssprevious)," current_counts=",loss_counts(ssnow));flush(stdout)
