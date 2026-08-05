using Octopus
const O = Octopus

# Re-implement validate(ElementParameterEffectivenessContract) with full accounting
# of every branch that CONTINUES without counting.
contract = ElementParameterEffectivenessContract()
function run_probe(contract, u)
u = (2.3e-3, 4.1e-4, -1.7e-3, -3.2e-4, 1.5e-3, 9.0e-4)
checked = 0
ignored = String[]
skipped_kinds = Symbol[]
no_meta = Any[]
unperturbable = String[]      # _perturb_param returned nothing  -> NEVER counted
rejected = String[]           # perturbed ctor threw            -> NEVER counted
excused = String[]            # listed in `inactive`            -> NEVER counted
nonparammeta = String[]
kinds_seen = Symbol[]

for T in O.registered_element_specs()
    meta = O._element_meta_or_nothing(T)
    if meta === nothing; push!(no_meta, T); continue; end
    push!(kinds_seen, meta.kind)
    ctor = meta.friendly_constructor
    if ctor === nothing; push!(skipped_kinds, meta.kind); continue; end
    probe = if haskey(contract.probes, meta.kind)
        Dict{Symbol,Any}(pairs(contract.probes[meta.kind]))
    else
        ex = O.example_spec(T)
        ex isa ElementSpec ? Dict{Symbol,Any}(O.params(ex)) : nothing
    end
    if probe === nothing; push!(skipped_kinds, meta.kind); continue; end
    baseline = try
        collect(O.compile_runtime(ctor(; probe...))(u...))
    catch err
        println("BROKEN ", meta.kind); continue
    end
    for (key, pmeta) in pairs(O.parameter_schema(T))
        if !(pmeta isa O.ParamMeta); push!(nonparammeta, "$(meta.kind).$(key)"); continue; end
        if haskey(contract.inactive, (meta.kind, key)); push!(excused, "$(meta.kind).$(key)"); continue; end
        current = get(probe, key, pmeta.default === nothing ? 0.0 : pmeta.default)
        new = O._perturb_param(key, current)
        if new === nothing
            push!(unperturbable, "$(meta.kind).$(key)::$(typeof(current))")
            continue
        end
        moved = try
            collect(O.compile_runtime(ctor(; merge(probe, Dict{Symbol,Any}(key => new))...))(u...))
        catch
            push!(rejected, "$(meta.kind).$(key)")
            continue
        end
        checked += 1
        maximum(abs, moved .- baseline) <= contract.atol && push!(ignored, "$(meta.kind).$(key)")
    end
end

return (;checked, ignored, skipped_kinds, no_meta, unperturbable, rejected, excused, nonparammeta, kinds_seen)
end
res = run_probe(contract, nothing)
(;checked, ignored, skipped_kinds, no_meta, unperturbable, rejected, excused, nonparammeta, kinds_seen) = res
println("checked            = ", checked)
println("ignored            = ", length(ignored), " ", ignored)
println("skipped_kinds      = ", length(skipped_kinds), " ", skipped_kinds)
println("specs w/o meta     = ", length(no_meta), " ", no_meta)
println()
println("SILENTLY UNCOUNTED (neither checked nor reported):")
println("  unperturbable (_perturb_param -> nothing): ", length(unperturbable))
for s in sort(unperturbable); println("     ", s); end
println("  rejected-perturbation (ctor threw, 'consumed by definition'): ", length(rejected))
for s in sort(rejected); println("     ", s); end
println("  non-ParamMeta schema entries: ", length(nonparammeta), " ", nonparammeta)
println("  excused by `inactive`: ", length(excused))
println()
println("=== STALE `inactive` ENTRIES: (kind,param) pairs that never matched ===")
excused_set = Set(excused)
stale = String[]
for ((kind, param), reason) in contract.inactive
    "$(kind).$(param)" in excused_set || push!(stale, "$(kind).$(param)")
end
println(length(stale), " of ", length(contract.inactive), ": ", sort(stale))

println()
println("=== STALE `probes` ENTRIES: kinds with a probe but no registered meta ===")
for k in sort(collect(keys(contract.probes)); by=string)
    k in kinds_seen || println("  ", k)
end

println()
println("=== live contract result ===")
r = validate(contract)
println(r.status, " | ", r.message)
println(r.metrics)
