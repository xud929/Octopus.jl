using Octopus
function test_seen()
    seen = Set{Method}()
    for name in names(Octopus; all=true, imported=false)
        isdefined(Octopus, name) || continue
        f = try getfield(Octopus, name) catch; continue end
        f isa Union{Function,Type} || continue
        f isa Core.Builtin && continue
        ms = try methods(f) catch; continue end
        for m in ms
            m.module === Octopus || continue
            push!(seen, m)
        end
    end
    seen
end
function global_seen()
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
    owners = Dict{Method,String}()
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
                get!(owners, m, string(mod) * "." * string(name))
            end
        end
    end
    (seen, owners, mods)
end
a = test_seen()
b, owners, mods = global_seen()
println("test-way: ", length(a), "  global: ", length(b), "  modules walked: ", length(mods))
missed = setdiff(b, a)
println("missed: ", length(missed))
for m in Iterators.take(sort(collect(missed); by = m -> (String(m.name), m.line)), 25)
    println("   ", m.name, "  ", basename(String(m.file)), ":", m.line, "   owner=", get(owners, m, "?"))
end
println()
println("extra in test-way but not global: ", length(setdiff(a, b)))
