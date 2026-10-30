# Initialization versus warm steady tracking; run with julia --project=. --threads=4 from the project root.
using Octopus
function measure()
    for policy in (CPUThreadsExecutionPolicy(threads=4), CUDAExecutionPolicy()), n in (128,8192)
        rep=Octopus._rep_on_backend(backend_type(policy),Phase6DRep(ntuple(k->fill(0.001*k,n),6)...))
        spec=Linear6DSpec(beta1=(2.,3.,4.),dmu=(.1,.2,-.02),particle_tunes=(nux=(x,px,y,py,z,pz)->0.21+0.01*x*x,))
        task=TrackingTask((spec,);policy=policy,loss_report=false)
        # Compile/launch once on another owner, then measure first preparation.
        warm=Octopus._rep_on_backend(backend_type(policy),Phase6DRep(ntuple(k->fill(0.001*k,n),6)...))
        execute!(TrackingTask((spec,);policy=policy,loss_report=false),warm;turns=2)
        policy isa CUDAExecutionPolicy && Octopus.CUDA.synchronize()
        init=@timed begin
            execute!(task,rep;turns=1)
            policy isa CUDAExecutionPolicy && Octopus.CUDA.synchronize()
        end
        execute!(task,rep;turns=32)
        policy isa CUDAExecutionPolicy && Octopus.CUDA.synchronize()
        steady=@timed begin
            execute!(task,rep;turns=32)
            policy isa CUDAExecutionPolicy && Octopus.CUDA.synchronize()
        end
        binding=only(values(task.particle_tunes[].bindings))
        owned=sum(a->length(a)*sizeof(eltype(a)),binding.tunes)+sum(a->length(a)*sizeof(eltype(a)),binding.rotations)
        println("TUNE-PERF policy=",nameof(typeof(policy))," n=",n," initialization_seconds=",init.time," initialization_host_bytes=",init.bytes," steady_turns=32 steady_seconds=",steady.time," steady_host_bytes=",steady.bytes," owned_coefficient_bytes=",owned)
    end
end
measure()
