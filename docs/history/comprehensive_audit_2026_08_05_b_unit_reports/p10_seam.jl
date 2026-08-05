using Octopus, ForwardDiff
const O = Octopus
# Is `_linear6d_matrix_from_optics`'s missing zeta/eta/R promotion reachable?
d = ForwardDiff.Dual(0.01, 1.0)
try
    sp = ElementSpec{:linear6d}(Dict{Symbol,Any}(
        :beta1=>(3.1,2.2,40.0), :beta2=>(3.1,2.2,40.0),
        :alpha1=>(0.0,0.0,0.0), :alpha2=>(0.0,0.0,0.0),
        :dmu=>(0.7,1.3,0.02),
        :zeta1=>(d,0.0,0.0,0.0), :zeta2=>(0.0,0.0,0.0,0.0),
        :eta1=>(0.0,0.0,0.0,0.0), :eta2=>(0.0,0.0,0.0,0.0),
        :R1=>(0.0,0.0,0.0,0.0), :R2=>(0.0,0.0,0.0,0.0),
        :tracking_method=>Symplectic6DMap()))
    e = compile_runtime(sp)
    println("raw-spec Dual zeta1 -> ok, ", typeof(e))
catch err
    println("raw-spec Dual zeta1 -> FAIL ", string(typeof(err)), ": ", first(sprint(showerror, err), 110))
end
