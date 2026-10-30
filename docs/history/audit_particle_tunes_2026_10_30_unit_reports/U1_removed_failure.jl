# U1 targeted particle-tune neighbour-audit reproducer, 2026-10-30.
# See U1.md for the measured red/green result and scope.
using Octopus, Test
struct U1FailSecond <: Octopus.AbstractTrackOp
    enabled::Base.RefValue{Bool}
end
(op::U1FailSecond)(ctx::TrackingContext,id,x,px,y,py,z,pz) =
    op.enabled[] && id == 2 ? error("U1 deliberately fails particle two") : (x,px,y,py,z,pz)
function main()
    enabled = Ref(false)
    spec = Linear6DSpec(beta1=(1.,1.,1.),dmu=(0.3,0.4,-0.05),particle_tunes=(nux=0.21,))
    aperture = ApertureSpec(shape=:rectangle,x_limit=1.,y_limit=1.,name="U1 loss")
    task = TrackingTask((spec,aperture,U1FailSecond(enabled));policy=CPUThreadsExecutionPolicy(threads=1))
    previous = Phase6DRep(ntuple(_ -> fill(0.001,2),6)...)
    execute!(task,previous;turns=1)
    oldrecord = loss_record(task)
    clear_particle_tunes!(task)
    spec.particle_tunes = nothing
    enabled[] = true
    current = Phase6DRep([2.,0.001],zeros(2),zeros(2),zeros(2),zeros(2),zeros(2))
    @test_throws Exception execute!(task,current;turns=1)
    println("U1-REMOVED-FAILURE old_record_restored=",loss_record(task) === oldrecord,
            " old_owner_restored=",task.loss_owner[].value === previous.x,
            " first_particle_dead=",!isfinite(current.x[1]),
            " counts=",Octopus.loss_counts(loss_record(task)))
    @test task.loss_owner[].value === current.x
    @test loss_record(task) !== oldrecord
    @test sum(Octopus.loss_counts(loss_record(task))) == 1
end
main()
