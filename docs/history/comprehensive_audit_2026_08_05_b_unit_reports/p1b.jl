using Octopus
function go()
    seen = Set{Method}()
    nm = 0
    hit = 0
    for name in names(Octopus; all=true, imported=false)
        isdefined(Octopus, name) || continue
        f = try getfield(Octopus, name) catch; continue end
        f isa Union{Function,Type} || continue
        f isa Core.Builtin && continue
        ms = try methods(f) catch; continue end
        name === :track! && (hit = length(ms))
        for m in ms
            m.module === Octopus || continue
            m in seen && continue
            push!(seen, m)
            nm += 1
        end
    end
    println("nmethods=", nm, "  methods(Octopus.track!) at its name: ", hit)
    println("track! in seen: ", count(m -> m.name === :track!, seen))
    println("validate in seen: ", count(m -> m.name === :validate, seen))
    # Which names does the sweep actually visit successfully?
    visited = Symbol[]
    for name in names(Octopus; all=true, imported=false)
        isdefined(Octopus, name) || continue
        f = try getfield(Octopus, name) catch; continue end
        f isa Union{Function,Type} || continue
        f isa Core.Builtin && continue
        push!(visited, name)
    end
    println("names visited: ", length(visited), " of ", length(names(Octopus; all=true, imported=false)))
    println(":track! visited? ", :track! in visited, "   :validate visited? ", :validate in visited)
end
go()
