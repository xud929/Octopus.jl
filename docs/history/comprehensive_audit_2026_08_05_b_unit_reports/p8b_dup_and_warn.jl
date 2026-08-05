using Octopus
using Octopus: ElementSpec, ElementMeta, register_element_meta!,
               validate_element_metadata, element_meta

println("== (1) an otherwise-HONEST second @element_spec block for :drift ==")
old = element_meta(:drift)
kw = Dict{Symbol,Any}(
    :kind => old.kind, :spec_type => old.spec_type,
    :friendly_constructor => old.friendly_constructor,
    :runtime_type => old.runtime_type,
    :runtime_types => old.runtime_types,
    :description => "HIJACKED: a second block silently replaced the first",
    :keywords => old.keywords, :tracking_methods => old.tracking_methods,
    :contracts => old.contracts, :analyses => old.analyses,
    :parameters => old.parameters, :example => old.example,
    :construction_help => old.construction_help,
)
register_element_meta!(ElementMeta(; (k => v for (k, v) in kw)...))
r = validate_element_metadata()
println("  description now      = ", repr(element_meta(:drift).description))
println("  registered specs     = ", length(Octopus.registered_element_specs()))
println("  validate passed      = ", r.passed, "  errors=", length(r.errors))
println("  => second block for an existing kind is ",
        r.passed ? "SILENTLY ACCEPTED (last one wins)" : "rejected")

println()
println("== (2) unknown-key warning: construction vs every compile ==")
@knob U12.k = 1.0
println("  -- construct DriftSpec(L=0.5, typo_key=1.0)")
d = DriftSpec(L=0.5, typo_key=1.0)
println("  -- compile it 3x (no knob parameter)")
for _ in 1:3
    compile_runtime(d)
end
println("  -- construct DriftSpec(L=@knob_expr(U12.k), typo_key=1.0)")
dk = DriftSpec(L=@knob_expr(U12.k), typo_key=1.0)
println("  -- compile it 3x (knob-carrying -> resolve_knobs rebuilds the spec)")
for _ in 1:3
    compile_runtime(dk)
end
println("  done")
