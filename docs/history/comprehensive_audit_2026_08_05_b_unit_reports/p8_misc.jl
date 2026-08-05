## (1) Is a SECOND @element_spec block for an already-registered kind (same
##     spec_type) noticed by anything, or does it silently replace the first?
## (2) Runtime Objects section: totalize the hand-appended list against the
##     AbstractTrackOp type tree.
## (3) Does the unknown-key warning re-fire at every compile of a knob-carrying
##     spec (resolve_knobs rebuilds the ElementSpec)?

using Octopus
using Octopus: ElementSpec, ElementMeta, ParamMeta, PlaceholderAnalysis,
               register_element_meta!, validate_element_metadata,
               AbstractTrackOp, _subtypes_recursive, param

const REPO = "/cfs/ad/dxu/Library/Julia/Octopus"

println("== (1) duplicate @element_spec for the same kind ==")
before = element_meta(:drift).description
kw = Dict{Symbol,Any}(
    :kind => :drift,
    :spec_type => ElementSpec{:drift},
    :friendly_constructor => nothing,
    :runtime_type => nothing,
    :description => "HIJACKED by a second @element_spec block",
    :keywords => Symbol[],
    :tracking_methods => DataType[],
    :contracts => DataType[],
    :analyses => DataType[],
    :parameters => NamedTuple(),
    :example => ElementSpec{:drift}(; L=0.5),
    :construction_help => "",
)
register_element_meta!(ElementMeta(; (k => v for (k, v) in kw)...))
r = validate_element_metadata()
println("  description before  = ", repr(before))
println("  description after   = ", repr(element_meta(:drift).description))
println("  registered specs    = ", length(Octopus.registered_element_specs()),
        " (was 30)")
println("  validate_element_metadata: passed=", r.passed, " nerrors=", length(r.errors))
for e in r.errors
    println("        | ", e)
end
println("  => a second block for an existing kind is ",
        r.passed ? "SILENTLY ACCEPTED" : "rejected")

println()
println("== (2) Runtime Objects coverage vs the AbstractTrackOp tree ==")
snapshot = read(joinpath(REPO, "docs", "registry_snapshot.md"), String)
runtime_section = split(snapshot, "## Runtime Objects")[end]
ops = sort([nameof(T) for T in _subtypes_recursive(AbstractTrackOp) if !isabstracttype(T)];
           by = string)
missing_ops = [o for o in ops if !occursin("`" * string(o) * "`", runtime_section)]
println("  concrete AbstractTrackOp subtypes = ", length(ops))
println("  absent from the Runtime Objects section = ", length(missing_ops),
        " -> ", missing_ops)
println("  full tree: ", ops)

println()
println("== (3) unknown-key warning at construction vs at every compile ==")
@knob U12.k = 1.0
println("  -- constructing DriftSpec(L=0.5, typo_key=1.0): expect ONE warning")
d = DriftSpec(L=0.5, typo_key=1.0)
println("  -- compiling it 3 times (no knob): expect NO further warning")
for _ in 1:3
    compile_runtime(d)
end
println("  -- constructing a knob-carrying spec with the same typo")
dk = DriftSpec(L=@knob_expr(U12.k), typo_key=1.0)
println("  -- compiling it 3 times (knob-carrying): watch for repeats")
for _ in 1:3
    compile_runtime(dk)
end
println("  done")
