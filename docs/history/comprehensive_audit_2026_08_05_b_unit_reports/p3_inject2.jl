## Addendum injections: corrected D21 (substring construction_help) and D23
## (multi-method runtime map where only the example's own method is exercised).

using Octopus
using Octopus: ElementSpec, ElementMeta, ParamMeta, PlaceholderAnalysis,
               register_element_meta!, validate_element_metadata,
               AbstractTrackingMethod, Symplectic6DMap, NonSymplectic6DMap, param

const K = :u12_fake
const ST = ElementSpec{K}

struct U12Method <: AbstractTrackingMethod end
Octopus.description(::Type{U12Method}) = "u12 probe method"

struct U12Runtime
    a::Float64
end
U12Runtime(spec::ElementSpec, method) = U12Runtime(Float64(param(spec, :a)))

abstract type U12Spec end
U12Spec(; a, b=2.0, tracking_method=U12Method()) =
    ST(; a=a, b=b, tracking_method=tracking_method)

function unregister!()
    filter!(T -> T !== ST, Octopus.REGISTERED_ELEMENT_SPECS)
    for T in collect(keys(Octopus.ELEMENT_META_BY_SPEC_TYPE))
        Octopus.ELEMENT_META_BY_SPEC_TYPE[T].kind === K &&
            delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, T)
    end
    for T in collect(keys(Octopus.ELEMENT_META_BY_FRIENDLY_TYPE))
        Octopus.ELEMENT_META_BY_FRIENDLY_TYPE[T].kind === K &&
            delete!(Octopus.ELEMENT_META_BY_FRIENDLY_TYPE, T)
    end
    delete!(Octopus.ELEMENT_META_BY_KIND, K)
end

function run(label, kw)
    unregister!()
    meta = ElementMeta(; (k => v for (k, v) in kw)...)
    register_element_meta!(meta)
    r = validate_element_metadata()
    errs = filter(e -> occursin(string(K), e), r.errors)
    unregister!()
    println(isempty(errs) ? "MISSED   " : "CAUGHT   ", label)
    for e in errs
        println("        | ", e)
    end
    return isempty(errs)
end

pars = (a=ParamMeta(required=true, meaning="strength a"),
        b=ParamMeta(default=2.0, meaning="optional b"),
        tracking_method=ParamMeta(default=U12Method(), meaning="per-element tracking method"))

# D21 corrected: construction_help documents NOTHING, yet every schema key is a
# substring of it ("a" and "b" inside "Absolutely", plus the literal
# "tracking_method").
run("D21 construction_help mentions every parameter only as an accidental substring",
    Dict{Symbol,Any}(
        :kind => K, :spec_type => ST, :friendly_constructor => U12Spec,
        :runtime_type => U12Runtime, :description => "u12 probe element",
        :keywords => [:thin_element], :tracking_methods => DataType[U12Method],
        :contracts => DataType[], :analyses => DataType[PlaceholderAnalysis],
        :parameters => pars, :example => U12Spec(a=1.0),
        :construction_help => "Absolutely tracking_method."))

# D23: two declared tracking methods; the SECOND method's runtime mapping is
# nonsense, but the single registered example uses the first method, so the
# `any(...)` match is satisfied and the lie never surfaces.
run("D23 second declared method maps to a nonsense runtime type (example uses the first)",
    Dict{Symbol,Any}(
        :kind => K, :spec_type => ST, :friendly_constructor => U12Spec,
        :runtime_type => U12Runtime, :description => "u12 probe element",
        :keywords => [:thin_element],
        :tracking_methods => DataType[U12Method, Symplectic6DMap],
        :runtime_types => Dict{DataType,Any}(U12Method => U12Runtime,
                                             Symplectic6DMap => Int),
        :contracts => DataType[], :analyses => DataType[PlaceholderAnalysis],
        :parameters => pars, :example => U12Spec(a=1.0),
        :construction_help => "U12Spec(; a, b=2.0, tracking_method=U12Method())"))

# Real exposure of D23: how many registered kinds declare more than one method?
println("\n== registered kinds with >1 declared tracking method ==")
for (kind, meta) in sort(collect(Octopus.ELEMENT_META_BY_KIND); by = p -> string(p[1]))
    n = length(meta.tracking_methods)
    n > 1 && println("  ", kind, "  methods=", n, " -> ",
                     join(string.(nameof.(meta.tracking_methods)), ", "),
                     "   example method = ",
                     string(nameof(typeof(Octopus.tracking_method(meta.example)))))
end

# And: which kinds' schemas now carry the placement keys (U13-2 completion)?
println("\n== placement-key schema coverage across registered kinds ==")
place = (:x_offset, :y_offset, :z_offset, :x_pitch, :y_pitch, :tilt,
         :misalign_convention, :ref_tilt)
missing_any = String[]
for (kind, meta) in sort(collect(Octopus.ELEMENT_META_BY_KIND); by = p -> string(p[1]))
    ks = keys(meta.parameters)
    miss = [p for p in place if !(p in ks)]
    isempty(miss) || push!(missing_any, "  " * string(kind) * ": missing " * join(string.(miss), ", "))
end
println("kinds = ", length(Octopus.ELEMENT_META_BY_KIND),
        "; kinds missing at least one placement key = ", length(missing_any))
foreach(println, missing_any)
