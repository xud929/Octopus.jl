using Octopus
const O = Octopus

# Extend the contract to the class it structurally cannot see: Symbol-valued
# parameters. `_perturb_param` returns `nothing` for every Symbol, so these
# 83 declared parameters are neither `checked` nor `ignored` -- the contract
# reports "every declared element parameter reached the map".
#
# Candidate alternatives are mined from the parameter's own `meaning` string
# (every `:symbol` token it names) plus a generic list; any candidate the
# constructor accepts is a legal value. A parameter with two legal values that
# compile to the SAME map is declared-but-ignored, invisibly.

const GENERIC = [:none, :all, :linear, :quadratic, :exact, :drift_kick, :madx, :bmad,
                 :multipole, :hard_edge, :soft_edge, :ellipse, :rectangle, :circle,
                 :equal_area, :equal_count, :equal_width, :normal_quantile,
                 :entrance, :centre, :center, :exit, :standard, :integrated,
                 :CIC, :TSC, :first, :second, :fourth, :sigma, :extrema, :off, :on]

u = (2.3e-3, 4.1e-4, -1.7e-3, -3.2e-4, 1.5e-3, 9.0e-4)
contract = ElementParameterEffectivenessContract()
report = String[]
unseen = 0
for T in O.registered_element_specs()
    meta = O._element_meta_or_nothing(T); meta === nothing && continue
    ctor = meta.friendly_constructor; ctor === nothing && continue
    probe = haskey(contract.probes, meta.kind) ?
        Dict{Symbol,Any}(pairs(contract.probes[meta.kind])) :
        (O.example_spec(T) isa ElementSpec ? Dict{Symbol,Any}(O.params(O.example_spec(T))) : nothing)
    probe === nothing && continue
    base = try collect(O.compile_runtime(ctor(; probe...))(u...)) catch; continue end
    for (key, pmeta) in pairs(O.parameter_schema(T))
        pmeta isa O.ParamMeta || continue
        haskey(contract.inactive, (meta.kind, key)) && continue
        current = get(probe, key, pmeta.default === nothing ? 0.0 : pmeta.default)
        current isa Symbol || continue
        O._perturb_param(key, current) === nothing || continue
        global unseen += 1
        cands = Symbol[]
        for m in eachmatch(r":(\w+)", pmeta.meaning); push!(cands, Symbol(m.captures[1])); end
        append!(cands, GENERIC)
        legal = Symbol[]; maps = Dict{Symbol,Vector{Float64}}()
        for c in unique(cands)
            c === current && continue
            out = try collect(O.compile_runtime(ctor(; merge(probe, Dict{Symbol,Any}(key => c))...))(u...))
                  catch; nothing end
            out === nothing && continue
            push!(legal, c); maps[c] = out
        end
        same = [c for c in legal if maximum(abs, maps[c] .- base) == 0.0]
        diff = [c for c in legal if maximum(abs, maps[c] .- base) != 0.0]
        if isempty(legal)
            push!(report, "  $(meta.kind).$(key) = :$(current)  -> NO alternative found (unprobed either way)")
        elseif isempty(diff)
            push!(report, "  $(meta.kind).$(key) = :$(current)  -> IGNORED: legal alternatives $(same) all give a BITWISE IDENTICAL map")
        else
            push!(report, "  $(meta.kind).$(key) = :$(current)  -> consumed (moved by $(diff)); inert alternatives: $(same)")
        end
    end
end
println("Symbol-valued declared parameters the contract can never report: ", unseen)
println()
for l in sort(report); println(l); end
println()
println("SUMMARY: ", count(l -> occursin("IGNORED", l), report), " declared-but-ignored, ",
        count(l -> occursin("NO alternative", l), report), " unprobed, ",
        count(l -> occursin("consumed", l), report), " consumed-once-extended")
