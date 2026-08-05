using Octopus
reset_knobs!()
@knob a = 2.0
e = @knob_expr(a * 3.0)
hasknob(v) = v isa Octopus.AbstractKnobExpression ||
             (v isa Union{Tuple,AbstractVector} && any(hasknob, v))
s1 = ElementSpec{:crab_dispersion}(; zeta1=e, zeta2=0.0, zeta3=0.0, zeta4=0.0,
                                   tracking_method=Symplectic6DMap())
s2 = ElementSpec{:thin_crab_cavity}(; N=1, frequency=1.0e8, strengthX=(e,),
                                    strengthY=(0.0,), phase=(0.0,),
                                    tracking_method=Symplectic6DMap())
s3 = ElementSpec{:crab_dispersion}(; zeta1=0.0, zeta2=0.0, zeta3=0.0, zeta4=0.0,
                                   tracking_method=Symplectic6DMap())
s3.params[:probe_nested] = ((e, 0.0), 1.0)
s4 = ElementSpec{:crab_dispersion}(; zeta1=0.0, zeta2=0.0, zeta3=0.0, zeta4=0.0,
                                   tracking_method=Symplectic6DMap())
s4.params[:probe_vector] = [e, 0.0]
for (label, s) in (("scalar", s1), ("flat tuple", s2), ("nested tuple", s3), ("vector", s4))
    hk = Octopus._has_knob_parameters(s)
    rs = Octopus.resolve_knobs(s)
    left = [k for (k, v) in Octopus.params(rs) if hasknob(v)]
    println(rpad(label, 14), " _has_knob_parameters=", rpad(string(hk), 6),
            " unresolved after resolve_knobs: ", isempty(left) ? "none" : string(left))
end
