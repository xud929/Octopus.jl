## U12 injected-defect measurement against validate_element_metadata().
## Registers a TEMPORARY lying ElementMeta in-process, one lie at a time, and
## reports whether the validator flags it. No repository file is touched.

using Octopus
using Octopus: ElementSpec, ElementMeta, ParamMeta, PlaceholderAnalysis,
               register_element_meta!, validate_element_metadata,
               AbstractTrackingMethod, Symplectic6DMap, param, getparam,
               compile_runtime

const K = :u12_fake
const ST = ElementSpec{K}

struct U12Method <: AbstractTrackingMethod end
Octopus.description(::Type{U12Method}) = "u12 probe method"

struct U12Runtime
    a::Float64
end
U12Runtime(spec::ElementSpec, method) = U12Runtime(Float64(param(spec, :a)))

# A "declared runtime type" whose constructor returns something else.
struct U12Wrong end
U12Wrong(spec::ElementSpec, method) = U12Runtime(0.0)

# A runtime that reads a key nobody declared.
struct U12Sneaky
    a::Float64
    secret::Float64
end
U12Sneaky(spec::ElementSpec, method) =
    U12Sneaky(Float64(param(spec, :a)), Float64(getparam(spec, :secret, 7.0)))

abstract type U12Spec end
U12Spec(; a, b=2.0, tracking_method=U12Method()) =
    ST(; a=a, b=b, tracking_method=tracking_method)

const HELP = "U12Spec(; a, b=2.0, tracking_method=U12Method()); ghost is optional."

base_params() = (
    a=ParamMeta(required=true, unit="m", meaning="strength a"),
    b=ParamMeta(default=2.0, unit="m", meaning="optional b"),
    tracking_method=ParamMeta(default=U12Method(), meaning="per-element tracking method"),
)

function base_kwargs()
    return Dict{Symbol,Any}(
        :kind => K,
        :spec_type => ST,
        :friendly_constructor => U12Spec,
        :runtime_type => U12Runtime,
        :description => "u12 probe element",
        :keywords => [:thin_element],
        :tracking_methods => DataType[U12Method],
        :contracts => DataType[],
        :analyses => DataType[PlaceholderAnalysis],
        :parameters => base_params(),
        :example => U12Spec(a=1.0),
        :construction_help => HELP,
    )
end

function unregister!()
    filter!(T -> !(T === ST || T === U12Wrong), Octopus.REGISTERED_ELEMENT_SPECS)
    for T in collect(keys(Octopus.ELEMENT_META_BY_SPEC_TYPE))
        Octopus.ELEMENT_META_BY_SPEC_TYPE[T].kind === K &&
            delete!(Octopus.ELEMENT_META_BY_SPEC_TYPE, T)
    end
    for T in collect(keys(Octopus.ELEMENT_META_BY_FRIENDLY_TYPE))
        Octopus.ELEMENT_META_BY_FRIENDLY_TYPE[T].kind === K &&
            delete!(Octopus.ELEMENT_META_BY_FRIENDLY_TYPE, T)
    end
    delete!(Octopus.ELEMENT_META_BY_KIND, K)
    return nothing
end

results = Tuple{String,Bool,Vector{String}}[]

function case(label, overrides::Dict{Symbol,Any}=Dict{Symbol,Any}(); extra=nothing)
    kw = base_kwargs()
    merge!(kw, overrides)
    unregister!()
    local errs
    try
        meta = ElementMeta(; (k => v for (k, v) in kw)...)
        register_element_meta!(meta)
        extra === nothing || extra()
        r = validate_element_metadata()
        errs = filter(e -> occursin(string(K), e) || occursin("U12", e), r.errors)
    catch err
        errs = ["REGISTRATION/VALIDATION THREW: " * sprint(showerror, err)]
    end
    unregister!()
    push!(results, (label, !isempty(errs), errs))
    return nothing
end

# ---- negative control: the honest meta must validate clean -------------------
case("D0 CONTROL honest meta (expect NO error)")

# ---- lies the prior pass claims are caught ----------------------------------
case("D1 tracking_methods contains a non-TrackingMethod (Int64)",
     Dict{Symbol,Any}(:tracking_methods => DataType[Int64],
                      :runtime_types => Dict{DataType,Any}(Int64 => U12Runtime,
                                                           U12Method => U12Runtime)))
case("D2 contracts contains a non-Contract (Int64)",
     Dict{Symbol,Any}(:contracts => DataType[Int64]))
case("D3 analyses contains a non-Analysis (Int64)",
     Dict{Symbol,Any}(:analyses => DataType[Int64]))
case("D4 runtime_type absent from runtime_types map",
     Dict{Symbol,Any}(:runtime_type => Float64,
                      :runtime_types => Dict{DataType,Any}(U12Method => U12Runtime)))
case("D5 unapproved physics keyword",
     Dict{Symbol,Any}(:keywords => [:u12_not_a_keyword]))
case("D6 parameter both required and defaulted",
     Dict{Symbol,Any}(:parameters => (a=ParamMeta(required=true, default=3.0, meaning="strength a"),
                                      b=ParamMeta(default=2.0, meaning="optional b"),
                                      tracking_method=ParamMeta(default=U12Method(), meaning="per-element tracking method"))))
case("D7 example missing a required parameter",
     Dict{Symbol,Any}(:parameters => (a=ParamMeta(required=true, meaning="strength a"),
                                      b=ParamMeta(default=2.0, meaning="optional b"),
                                      ghost=ParamMeta(required=true, meaning="required ghost"),
                                      tracking_method=ParamMeta(default=U12Method(), meaning="per-element tracking method"))))
case("D8 example carries an undeclared parameter",
     Dict{Symbol,Any}(:example => ST(; a=1.0, b=2.0, tracking_method=U12Method(), zz=5.0)))
case("D9 construction_help omits a declared parameter",
     Dict{Symbol,Any}(:construction_help => "zzz"))
case("D10 declared tracking method with no runtime type",
     Dict{Symbol,Any}(:tracking_methods => DataType[U12Method, Symplectic6DMap],
                      :runtime_types => Dict{DataType,Any}(U12Method => U12Runtime)))
case("D11 example does not compile (runtime type has no (spec,method) ctor)",
     Dict{Symbol,Any}(:runtime_type => Int,
                      :runtime_types => Dict{DataType,Any}(U12Method => Int)))
case("D12 example compiles to a type other than the declared runtime type",
     Dict{Symbol,Any}(:runtime_type => U12Wrong,
                      :runtime_types => Dict{DataType,Any}(U12Method => U12Wrong)))
case("D13 example is a spec of another kind",
     Dict{Symbol,Any}(:example => ElementSpec{:drift}(; L=0.5)))
case("D14 duplicate kind registered under a second spec_type",
     Dict{Symbol,Any}();
     extra = () -> begin
         kw2 = base_kwargs()
         kw2[:spec_type] = U12Wrong
         kw2[:friendly_constructor] = nothing
         register_element_meta!(ElementMeta(; (k => v for (k, v) in kw2)...))
     end)
case("D15 friendly_constructor resolves to a DIFFERENT schema",
     Dict{Symbol,Any}();
     extra = () -> begin
         Octopus.ELEMENT_META_BY_FRIENDLY_TYPE[U12Spec] =
             Octopus.ELEMENT_META_BY_KIND[:drift]
     end)

# ---- the hypothesised REMAINING blind spots ---------------------------------
case("D16 [blind-spot i] declared default 99.0 but the constructor applies 2.0",
     Dict{Symbol,Any}(:parameters => (a=ParamMeta(required=true, meaning="strength a"),
                                      b=ParamMeta(default=99.0, meaning="optional b"),
                                      tracking_method=ParamMeta(default=U12Method(), meaning="per-element tracking method"))))
case("D17 [blind-spot ii] declared parameter `ghost` that no code ever reads",
     Dict{Symbol,Any}(:parameters => (a=ParamMeta(required=true, meaning="strength a"),
                                      b=ParamMeta(default=2.0, meaning="optional b"),
                                      ghost=ParamMeta(default=0.0, meaning="never read by anything"),
                                      tracking_method=ParamMeta(default=U12Method(), meaning="per-element tracking method"))))
case("D18 [blind-spot iii] runtime READS an undeclared key (`secret`)",
     Dict{Symbol,Any}(:runtime_type => U12Sneaky,
                      :runtime_types => Dict{DataType,Any}(U12Method => U12Sneaky)))
case("D19 [blind-spot iv] declared unit is wrong (`a` in furlongs, used as metres)",
     Dict{Symbol,Any}(:parameters => (a=ParamMeta(required=true, unit="furlong", meaning="strength a"),
                                      b=ParamMeta(default=2.0, unit="m", meaning="optional b"),
                                      tracking_method=ParamMeta(default=U12Method(), meaning="per-element tracking method"))))
case("D20 [blind-spot v] approved-but-false physics keyword (:radiation on a kick)",
     Dict{Symbol,Any}(:keywords => [:radiation, :beam_beam, :collimation]))
case("D21 [blind-spot vi] construction_help mentions params only as letters",
     Dict{Symbol,Any}(:parameters => (a=ParamMeta(required=true, meaning="strength a"),
                                      b=ParamMeta(default=2.0, meaning="optional b")),
                      :example => ST(; a=1.0, b=2.0),
                      :construction_help => "Fabricates a bogus element."))
case("D22 [blind-spot vii] description is a lie (says quadrupole)",
     Dict{Symbol,Any}(:description => "Thick quadrupole magnet with fringe fields."))

println("\n================ INJECTED-DEFECT RESULTS ================")
global ncaught = 0
global nmiss = 0
for (label, caught, errs) in results
    global ncaught, nmiss
    tag = startswith(label, "D0") ? (caught ? "CONTROL FAILED" : "control clean") :
          (caught ? "CAUGHT" : "MISSED")
    startswith(label, "D0") || (caught ? (ncaught += 1) : (nmiss += 1))
    println(rpad(tag, 16), label)
    for e in errs
        println("        | ", e)
    end
end
println("\nCAUGHT $(ncaught) of $(ncaught + nmiss) injected lies (D0 is the negative control).")
