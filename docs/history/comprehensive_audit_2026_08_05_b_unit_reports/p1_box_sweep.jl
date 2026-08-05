# U18 probe 1: coverage and discriminating power of the Core.Box sweep
# (test/runtests.jl "No method grows a Core.Box outside the argued allowlist").
using Octopus

expr_has_box(x) = x isa GlobalRef ? (x.mod === Core && x.name === :Box) :
                  x isa Expr ? any(expr_has_box, x.args) : false
clean_name(m) = begin
    s = String(m.name)
    startswith(s, "#") || return s
    parts = split(s, '#'; keepempty=false)
    isempty(parts) ? s : String(parts[1])
end

# ---- (A) the sweep exactly as the test writes it -------------------------
function sweep_test_way()
    seen = Set{Method}()
    boxed = Tuple{String,String,Int}[]
    n = 0
    for name in names(Octopus; all=true, imported=false)
        isdefined(Octopus, name) || continue
        f = try
            getfield(Octopus, name)
        catch
            continue
        end
        f isa Union{Function,Type} || continue
        f isa Core.Builtin && continue
        ms = try
            methods(f)
        catch
            continue
        end
        for m in ms
            m.module === Octopus || continue
            m in seen && continue
            push!(seen, m)
            n += 1
            ci = try
                Base.uncompressed_ir(m)
            catch
                continue
            end
            ci === nothing && continue
            any(expr_has_box, ci.code) || continue
            file = basename(String(m.file))
            file == "none" && continue
            push!(boxed, (clean_name(m), file, m.line))
        end
    end
    (n, seen, boxed)
end

# ---- (B) a wider sweep: every method anywhere whose defining module is Octopus
function sweep_global()
    seen = Set{Method}()
    mods = Module[]
    function collect_mods(m::Module, depth)
        m in mods && return
        push!(mods, m)
        depth > 2 && return
        for nm in names(m; all=true, imported=false)
            isdefined(m, nm) || continue
            v = try getfield(m, nm) catch; continue end
            v isa Module && v !== m && collect_mods(v, depth + 1)
        end
    end
    for m in Base.loaded_modules_array()
        collect_mods(m, 0)
    end
    for mod in mods
        for name in names(mod; all=true, imported=false)
            isdefined(mod, name) || continue
            f = try getfield(mod, name) catch; continue end
            f isa Union{Function,Type} || continue
            f isa Core.Builtin && continue
            ms = try methods(f) catch; continue end
            for m in ms
                m.module === Octopus || continue
                push!(seen, m)
            end
        end
    end
    seen
end

n_test, seen_test, boxed_test = sweep_test_way()
seen_all = sweep_global()
println("sweep as written: nmethods = ", n_test)
println("global scan     : methods with m.module===Octopus = ", length(seen_all))
missed = setdiff(seen_all, seen_test)
println("MISSED by the test's enumeration: ", length(missed))
# which functions are they?
byfunc = Dict{String,Int}()
for m in missed
    k = String(m.name)
    byfunc[k] = get(byfunc, k, 0) + 1
end
println("missed by name (top 30):")
for (k, v) in sort(collect(byfunc); by = x -> -x[2])[1:min(30, length(byfunc))]
    println("   ", k, "  ", v)
end
# any missed method carrying a box?
missed_boxed = String[]
for m in missed
    ci = try Base.uncompressed_ir(m) catch; continue end
    ci === nothing && continue
    any(expr_has_box, ci.code) || continue
    push!(missed_boxed, "$(m.name) @ $(basename(String(m.file))):$(m.line)")
end
println("MISSED methods that DO carry a Core.Box: ", length(missed_boxed))
foreach(x -> println("   ", x), missed_boxed)

println()
println("boxed methods found by the sweep (name, file, line):")
for b in sort(boxed_test)
    println("   ", b)
end

# how many methods does each allowlist (name,file) pair cover in total?
allowed = [("read_beam_coordinates", "Beam.jl"),
           ("_initialize_moment_file!", "BeamObservers.jl"),
           ("validate", "Contracts.jl"),
           ("_contract_default_initial_rep", "Contracts.jl"),
           ("GaussianStrongBeam", "strong_beam.jl"),
           ("_activate_symbolics_adapter!", "symbolic.jl"),
           ("_spectral_collide_longitudinal!", "spectral.jl")]
println()
println("allowlist coverage breadth (methods matching each (name,file), boxed or not):")
for (nm, fl) in allowed
    c = count(m -> clean_name(m) == nm && basename(String(m.file)) == fl, seen_test)
    cb = count(b -> b[1] == nm && b[2] == fl, boxed_test)
    println("   ($nm, $fl): $c methods match the pattern, $cb of them currently box")
end
